"""One shop can never see another's data (build plan 9.3; task I2.1).

Items run here: 1 (two shops, each with an owner token), 2 (every route has a class, and a
new route without one fails), 3 (A's token with B's ids answers 404 with nothing of B's),
4 (A's lists hold no B rows). Item 5 (raw SQL under row-level security) is Phase 2; item 6
(callbacks and jobs) joins with those tasks (A2.1, A3.3). The chat part of item 4 joins
with I3.1.
"""
import re

import pytest
from fastapi.routing import APIRoute

from app.api.deps import require_owner
from app.main import app
from tenancy_support import A, B, B_MARKERS

# Every route, by path, gets exactly one class (plan 9.3 item 2).
CLASSES: list[tuple[str, str]] = [
    ("owner", r"^/api/v1/pharmacies/\{pid\}(/.*)?$"),        # A's shop only, 404 otherwise
    ("session", r"^/api/v1/pharmacies$"),                     # creating a shop: signed in, no shop yet
    ("session", r"^/api/v1/(me(/.*)?|chat|auth/(sign-out|devices(/.*)?))$"),
    ("signin", r"^/api/v1/auth/(otp/request|otp/verify|refresh|demo)$"),
    ("public", r"^/api/v1/(health|ready|legal/.*|cards/\{code\}(/plan)?|app/config|lenders)$"),
    ("public", r"^/api/v1/(support/reports|telemetry/events)$"),
    ("lender", r"^/api/v1/lenders/\{lid\}/.*$"),
    ("dev", r"^/api/v1/dev/.*$"),
    ("demo", r"^/api/v1/demo/.*$"),
    ("callback", r"^/applink/.*$"),
    ("ops", r"^/api/v1/internal/.*$"),
    ("docs", r"^/(openapi\.json|docs(/oauth2-redirect)?|redoc)$"),
]


def _walk(routes):
    for r in routes:
        if type(r).__name__ == "_IncludedRouter":
            yield from _walk(r.effective_candidates())
        elif hasattr(r, "path") and hasattr(r, "methods"):
            yield r


def all_routes() -> list[tuple[str, str, object]]:
    """(method, path, route) for every route the app serves, hidden ones included."""
    out = []
    for r in _walk(app.routes):
        for method in sorted(r.methods or []):
            if method != "HEAD":
                out.append((method, r.path, r))
    return out


def built(route) -> bool:
    return not getattr(route.endpoint, "__name__", "").startswith("contract_")


def classify(path: str) -> str | None:
    hits = {cls for cls, pattern in CLASSES if re.match(pattern, path)}
    return hits.pop() if len(hits) == 1 else None


def _calls(dependant) -> set:
    found = {dependant.call}
    for d in dependant.dependencies:
        found |= _calls(d)
    return found


def test_every_route_has_exactly_one_class():
    unclassified = sorted({path for _, path, _ in all_routes() if classify(path) is None})
    assert unclassified == [], "add these routes to CLASSES in tests/tenancy/test_tenancy_routes.py"


def test_every_built_owner_route_checks_the_shop():
    unchecked = [(m, p) for m, p, r in all_routes()
                 if classify(p) == "owner" and built(r) and require_owner not in _calls(r.dependant)]
    assert unchecked == []


def _fill(path: str, ids: dict, pid: str) -> str:
    values = {"pid": pid, "cid": "cap-demo", "aid": ids["action"], "oid": ids["orders"][0],
              "consent_id": "1", "code": ids["codes"][0]}
    return re.sub(r"\{(\w+)\}", lambda mt: values.get(mt.group(1), "x"), path)


def _no_b(text: str) -> bool:
    return not any(marker in text for marker in B_MARKERS)


def test_as_token_with_bs_shop_id_is_404_everywhere(two_shops):
    client, ids = two_shops
    wrong = []
    for method, path, route in all_routes():
        if classify(path) != "owner" or not built(route):
            continue
        r = client.request(method, _fill(path, ids, B), json={} if method in ("POST", "PUT", "PATCH") else None)
        if r.status_code != 404 or not _no_b(r.text):
            wrong.append((method, path, r.status_code))
    assert wrong == []


@pytest.mark.parametrize("method,path", [
    ("GET", "/api/v1/pharmacies/{A}/orders/{oid}/trim"),
    ("POST", "/api/v1/pharmacies/{A}/actions/{aid}/approve"),
    ("POST", "/api/v1/pharmacies/{A}/actions/{aid}/reject"),
])
def test_as_shop_with_bs_child_ids_is_404(two_shops, method, path):
    client, ids = two_shops
    r = client.request(method, path.format(A=A, oid=ids["orders"][0], aid=ids["action"]))
    assert r.status_code == 404 and _no_b(r.text), r.text


def test_the_demo_shops_example_capture_is_its_own(two_shops):
    client, ids = two_shops
    assert client.get(f"/api/v1/pharmacies/{A}/captures/cap-demo").status_code == 200
    r = client.get(f"/api/v1/pharmacies/{B}/captures/cap-demo", headers=ids["b_headers"])
    assert r.status_code == 404  # found by this harness: every shop used to get the demo's example


def test_bs_token_works_for_b_only(two_shops):
    client, ids = two_shops
    assert client.get(f"/api/v1/pharmacies/{B}/accounts", headers=ids["b_headers"]).status_code == 200
    assert client.get(f"/api/v1/pharmacies/{A}/accounts", headers=ids["b_headers"]).status_code == 404


def test_as_lists_hold_no_b_rows(two_shops):
    client, ids = two_shops
    leaks, read = [], 0
    for method, path, route in all_routes():
        if method != "GET" or classify(path) != "owner" or not built(route) or path.count("{") != 1:
            continue
        r = client.get(_fill(path, ids, A), params={"once": "true"})  # History's stream sends its backlog and closes
        read += r.status_code == 200
        if not _no_b(r.text):
            leaks.append(path)
    assert leaks == [] and read >= 15


def test_b_sees_its_own_figures_not_as(two_shops):
    client, ids = two_shops
    a = client.get(f"/api/v1/pharmacies/{A}/customers").json()
    b = client.get(f"/api/v1/pharmacies/{B}/customers", headers=ids["b_headers"]).json()
    assert {row["code"] for row in b} == set(ids["codes"])
    assert not {row["code"] for row in a} & set(ids["codes"])


def test_as_history_holds_no_b_events(two_shops):
    client, ids = two_shops
    client.post(f"/api/v1/pharmacies/{B}/pause", json={"paused": True}, headers=ids["b_headers"])
    events = client.get(f"/api/v1/pharmacies/{A}/logs").json()
    assert events and all(e["data"].get("pharmacy") in (None, A) for e in events)
    assert _no_b(str(events))


def test_history_is_only_under_a_shop():
    """No History route outside /pharmacies/{pid}: the old global /logs* are gone (flow step 5)."""
    assert [p for _, p, _ in all_routes() if "/logs" in p and not p.startswith("/api/v1/pharmacies/{pid}/logs")] == []


def test_routes_list_sees_hidden_routes_too():
    paths = {p for _, p, _ in all_routes()}
    assert "/api/v1/legal/terms" in paths  # include_in_schema=False, like Applink's callbacks (A2.1)
    assert sum(p.startswith("/api/v1/pharmacies/{pid}") for p in paths) >= 30
    assert not [r for r in app.routes if isinstance(r, APIRoute) and r.path.startswith("/api/v1/pharmacies")]
