"""Contract v1 (build plan 2.2): every Phase 1 route is in the OpenAPI document, the ones not
built yet answer 501 not_built, and a built route of Ishmam's is removed from the stub list."""

import pytest

from app.api.contract import ROUTES
from app.schemas.product import CustomerRow
from app.main import API_PREFIX, app


def _spec_ops() -> set[tuple[str, str]]:
    spec = app.openapi()
    return {(m.upper(), p.removeprefix(API_PREFIX)) for p, ops in spec["paths"].items() for m in ops}


def test_every_phase1_route_is_in_the_contract():
    ops = _spec_ops()
    missing = [(m, p) for m, p, *_ in ROUTES if (m, p) not in ops]
    assert missing == []


def test_the_today_shape_matches_the_apps_fixture():
    schema = app.openapi()["components"]["schemas"]["TodayOut"]
    assert set(schema["required"]) == {"as_of", "cash_now", "next_problem", "expiring_60d", "approvals_waiting",
                                       "one_thing", "alerts"}


@pytest.mark.parametrize("method,path", [("POST", "/me/export"), ("GET", "/pharmacies/green-life/usage"),
                                         ("GET", "/app/config")])
def test_unbuilt_routes_answer_not_built(anon, method, path):
    r = anon.request(method, f"{API_PREFIX}{path}")
    assert r.status_code == 501
    assert r.json()["code"] == "not_built"


def test_built_routes_are_removed_from_the_stub_list():
    """Once Ishmam builds a route, its stub line must go (Arifin's lines drop on their own)."""
    ops = {(m.upper(), p.removeprefix(API_PREFIX)): op["operationId"]
           for p, methods in app.openapi()["paths"].items() for m, op in methods.items()}
    assert any(not op_id.startswith("contract_") for op_id in ops.values())  # real routes are seen
    built = [(m, p) for m, p, *_, owner in ROUTES
             if owner == "I" and not ops.get((m, p), "contract_").startswith("contract_")]
    assert built == []


def test_the_27_nov_plan_is_in_the_contract():
    """No USSD: families join by text, the drawn phone texts 21213, and Plus starts with an OTP."""
    ops = _spec_ops()
    for route in [("POST", "/demo/sms"), ("GET", "/demo/sms/thread"), ("POST", "/demo/reset"),
                  ("POST", "/pharmacies/{pid}/plus/otp")]:
        assert route in ops, route
    assert not any("ussd" in path for _, path in ops)
    schemas = app.openapi()["components"]["schemas"]
    assert schemas["JoinText"]["required"] == ["text", "to"]
    assert "join" in schemas["CustomerCreated"]["required"]
    assert CustomerRow.model_fields["join"].is_required()  # GET /customers moves to it in I2.2
    assert "family_join_routes" in schemas["MeOut"]["required"]
    assert "OTP_SENT" in schemas["PlusOut"]["properties"]["status"]["enum"]
    assert "join_by_text" in schemas["Problem"]["properties"]["code"]["enum"]
    assert schemas["DemoSmsOut"]["properties"]["replies"]["items"]["$ref"].endswith("/DemoReply")
    assert set(schemas["DemoMessage"]["required"]) == {"direction", "text", "at"}
