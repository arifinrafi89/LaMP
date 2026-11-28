"""Per-shop History (build plan 2.2 "GET /pharmacies/{pid}/logs · /logs/stream · /logs/verify",
4.2 audit_log; flow step 5): every event carries its shop, each shop has its own hash chain,
and a shop's History shows only its own events."""

from datetime import date

from sqlalchemy import select

from app.db import models as m
from app.engines import logbus
from tenancy_support import A, B, B_MARKERS

LOGS_A = f"/api/v1/pharmacies/{A}/logs"
LOGS_B = f"/api/v1/pharmacies/{B}/logs"


def _b(ids) -> dict:
    return ids["b_headers"]


def _shops_of(db, events) -> set:
    ids = [int(e["id"][3:]) for e in events]
    return set(db.scalars(select(m.AuditLog.pharmacy_id).where(m.AuditLog.id.in_(ids))))


def test_each_shop_sees_only_its_own_events(two_shops, tenancy_db):
    client, ids = two_shops
    client.post(f"/api/v1/pharmacies/{B}/pause", json={"paused": True}, headers=_b(ids))
    client.post(f"/api/v1/pharmacies/{A}/actions", json={"kind": "set_aside", "payload": {"amount": 500}})
    a = client.get(LOGS_A).json()
    b = client.get(LOGS_B, headers=_b(ids)).json()
    assert a and b
    assert _shops_of(tenancy_db, a) == {A} and _shops_of(tenancy_db, b) == {B}
    assert not any(marker in str(a) for marker in B_MARKERS)
    assert "action_proposed" in {e["event"] for e in a}
    assert "action_proposed" in {e["event"] for e in b}  # the fixture's proposal for B


def test_every_event_of_a_request_carries_the_shop(two_shops, tenancy_db):
    client, ids = two_shops
    before = tenancy_db.scalar(select(m.AuditLog.id).order_by(m.AuditLog.id.desc()).limit(1))
    client.post(f"/api/v1/pharmacies/{B}/actions", json={"kind": "set_aside", "payload": {"amount": 300}},
                headers=_b(ids))
    new = list(tenancy_db.scalars(select(m.AuditLog.pharmacy_id).where(m.AuditLog.id > before)))
    assert new and set(new) == {B}


def test_another_shops_history_is_404(two_shops):
    client, _ = two_shops
    for path in ("", "/verify", "/export", "/stream?once=true"):
        r = client.get(f"{LOGS_B}{path}")
        assert r.status_code == 404 and r.json()["code"] == "not_found", path


def test_each_chain_verifies_on_its_own(two_shops):
    client, ids = two_shops
    client.post(f"/api/v1/pharmacies/{B}/actions", json={"kind": "set_aside", "payload": {"amount": 300}},
                headers=_b(ids))
    va = client.get(f"{LOGS_A}/verify").json()
    vb = client.get(f"{LOGS_B}/verify", headers=_b(ids)).json()
    assert va["intact"] and vb["intact"]
    assert va["count"] == len(client.get(LOGS_A).json())
    assert vb["count"] == len(client.get(LOGS_B, headers=_b(ids)).json())
    assert va["head_hash"] != vb["head_hash"]


def test_a_shops_chain_starts_at_genesis(two_shops, tenancy_db):
    client, ids = two_shops
    first_b = tenancy_db.scalar(select(m.AuditLog).where(m.AuditLog.pharmacy_id == B).order_by(m.AuditLog.id))
    assert first_b.prev_hash == logbus.GENESIS


def test_tampering_with_bs_history_leaves_as_intact(two_shops, tenancy_db):
    client, ids = two_shops
    row = tenancy_db.scalar(select(m.AuditLog).where(m.AuditLog.pharmacy_id == B).order_by(m.AuditLog.id))
    row.event += "x"
    tenancy_db.commit()
    assert client.get(f"{LOGS_A}/verify").json()["intact"] is True
    vb = client.get(f"{LOGS_B}/verify", headers=_b(ids)).json()
    assert vb["intact"] is False and vb["first_bad_id"] == f"lg-{row.id}"


def test_the_export_and_stream_are_the_shops_own(two_shops):
    client, ids = two_shops
    a_ids = [e["id"] for e in client.get(LOGS_A).json()]
    jsonl = client.get(f"{LOGS_A}/export", params={"format": "jsonl"}).text
    assert len(jsonl.splitlines()) == len(a_ids)
    assert not any(marker in jsonl for marker in B_MARKERS)
    stream = client.get(f"{LOGS_A}/stream", params={"once": "true"}).text
    assert stream.count("data: ") == len(a_ids)


def test_system_events_are_in_no_shops_history(two_shops, tenancy_db):
    client, ids = two_shops
    logbus.log("T0", "SYSTEM", "system_error", tenancy_db, route="GET /x", error="Boom")
    tenancy_db.commit()
    row = tenancy_db.scalar(select(m.AuditLog).where(m.AuditLog.event == "system_error"))
    assert row.pharmacy_id is None
    assert "system_error" not in {e["event"] for e in client.get(LOGS_A).json()}
    assert "system_error" not in {e["event"] for e in client.get(LOGS_B, headers=_b(ids)).json()}


def test_the_familys_plan_goes_to_its_shops_history(two_shops, tenancy_db):
    client, ids = two_shops
    code = ids["codes"][0]
    ph = tenancy_db.get(m.Pharmacy, B)
    today = date.fromisoformat(ph.settings["as_of_date"])
    assert client.post(f"/api/v1/cards/{code}/plan", json={"parts": 2, "first_on": today.isoformat()}).status_code == 200
    b_events = {e["event"] for e in client.get(LOGS_B, headers=_b(ids)).json()}
    assert {"plan_set", "notify"} <= b_events
    assert "plan_set" not in {e["event"] for e in client.get(LOGS_A).json()}
