"""GET /pharmacies/{pid}/today: one call for the Today screen (build plan 2.2; task I2.2,
part 2). Its "one thing" is the next thing to do (plan 5.2), the first that applies of:
finish setup, approve a waiting step, remind a customer whose part is due, scan the last 3
supplier bills, nothing."""

from datetime import datetime

from app.db import models as m
from app.db.seed import SEED_AS_OF

P = "/api/v1/pharmacies/green-life"
TODAY = SEED_AS_OF


def test_today_for_the_demo_shop(client):
    r = client.get(f"{P}/today")
    assert r.status_code == 200, r.text
    j = r.json()
    assert set(j) == {"as_of", "cash_now", "next_problem", "expiring_60d", "approvals_waiting", "one_thing", "alerts"}
    assert j["as_of"] == TODAY.isoformat()
    forecast = client.get(f"{P}/forecast").json()
    assert j["cash_now"] == forecast["start_cash"]
    first = forecast["shortfalls"][0] if forecast["shortfalls"] else None
    if first:
        assert j["next_problem"] == {"kind": "shortfall", "date": first["date"], "amount": first["amount"],
                                     "text_key": "today.short_on"}
    else:
        assert j["next_problem"] is None
    expiry = client.get(f"{P}/expiry", params={"horizon_days": 60}).json()
    assert j["expiring_60d"] == {"value": expiry["at_risk_value"], "return_eligible": expiry["return_eligible_value"]}
    assert j["approvals_waiting"] == 0
    assert [a["id"] for a in j["alerts"]] == [a["id"] for a in client.get(f"{P}/alerts").json()]
    assert j["one_thing"] == {"kind": "none", "action_id": None, "title_key": "today.one_thing.none"}


def test_today_one_thing_approve(client):
    a = client.post(f"{P}/actions", json={"kind": "set_aside", "payload": {"amount": 500}}).json()
    j = client.get(f"{P}/today").json()
    assert j["approvals_waiting"] == 1
    assert j["one_thing"] == {"kind": "approve", "action_id": a["id"], "title_key": "today.one_thing.approve"}


def test_today_one_thing_remind(client, api_db):
    card = api_db.query(m.PatientDue).filter_by(pharmacy_id="green-life").first()
    card.plan_parts, card.plan_first_on = 2, TODAY
    api_db.commit()
    assert client.get(f"{P}/today").json()["one_thing"]["kind"] == "remind"


def test_approve_comes_before_remind(client, api_db):
    card = api_db.query(m.PatientDue).filter_by(pharmacy_id="green-life").first()
    card.plan_parts, card.plan_first_on = 1, TODAY
    api_db.commit()
    client.post(f"{P}/actions", json={"kind": "set_aside", "payload": {"amount": 500}})
    assert client.get(f"{P}/today").json()["one_thing"]["kind"] == "approve"


def _new_shop(api_db, owner_headers, *, setup_complete: bool) -> tuple[str, dict]:
    api_db.add(m.Pharmacy(id="ph-new", name="Shapla", city="Dhaka", cash_on_hand=0, kind="real",
                          settings={"gross_margin_pct": 12, "cash_buffer": 0, "expiry_buffer_days": 30},
                          setup_complete=setup_complete, card_prefix="SH", created_at=datetime(2026, 11, 29)))
    api_db.commit()
    return "/api/v1/pharmacies/ph-new", owner_headers(api_db, "ph-new")


def test_today_for_a_new_shop_says_setup(anon, api_db, owner_headers):
    path, h = _new_shop(api_db, owner_headers, setup_complete=False)
    r = anon.get(f"{path}/today", headers=h)
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["cash_now"] == 0 and j["next_problem"] is None and j["alerts"] == []
    assert j["expiring_60d"] == {"value": 0, "return_eligible": 0} and j["approvals_waiting"] == 0
    assert j["one_thing"] == {"kind": "setup", "action_id": None, "title_key": "today.one_thing.setup"}


def test_a_set_up_shop_without_3_bills_is_asked_to_scan(anon, api_db, owner_headers):
    path, h = _new_shop(api_db, owner_headers, setup_complete=True)
    assert anon.get(f"{path}/today", headers=h).json()["one_thing"]["kind"] == "scan"
