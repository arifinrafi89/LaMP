"""Customers (build plan 2.2 "Customers", 3.4; task I2.2, part 3): the owner's list with each
card's join text, adding a card, a sale, a payment, and the plan set at the counter.
Amounts only: no name field exists anywhere."""

import re
from datetime import timedelta

import pytest
from sqlalchemy import func, select

from app.db import models as m
from app.db.seed import SEED_AS_OF
from app.engines import patients

P = "/api/v1/pharmacies/green-life"
TODAY = SEED_AS_OF
CODE = re.compile(r"^GL-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$")


def _add(client, amount=1200.0, since=TODAY):
    return client.post(f"{P}/customers", json={"amount": amount, "since": since.isoformat()})


def _money(client, code, kind, amount, on=TODAY, method=None):
    body = {"amount": amount, "on": on.isoformat()} | ({"method": method} if method else {})
    return client.post(f"{P}/customers/{code}/{kind}", json=body)


def _ledger(api_db, code):
    return list(api_db.scalars(select(m.PatientLedger).where(m.PatientLedger.code == code)
                               .order_by(m.PatientLedger.id)))


# --- The list and adding a card ----------------------------------------------------------

def test_add_customer(client, api_db):
    r = _add(client)
    assert r.status_code == 201, r.text
    j = r.json()
    assert CODE.match(j["code"]), j["code"]
    assert j["label"] == "Customer 007"  # the seed has six
    assert j["join"] == {"text": "LAMP " + j["code"].replace("-", ""), "to": "21213"}
    assert set(j) == {"code", "label", "join"}
    card = api_db.scalar(select(m.PatientDue).where(m.PatientDue.code == j["code"]))
    assert card.pharmacy_id == "green-life" and card.amount == 1200 and card.since == TODAY
    [opening] = _ledger(api_db, j["code"])
    assert opening.kind == "adjust" and opening.amount == 1200 and opening.on_date == TODAY


def test_labels_count_up(client):
    assert _add(client).json()["label"] == "Customer 007"
    assert _add(client).json()["label"] == "Customer 008"


def test_customer_rows(client):
    code = _add(client).json()["code"]
    r = client.get(f"{P}/customers")
    assert r.status_code == 200, r.text
    rows = r.json()
    assert len(rows) == 7
    row = next(x for x in rows if x["code"] == code)
    assert row == {"code": code, "label": "Customer 007", "amount": 1200, "since": TODAY.isoformat(),
                   "days_outstanding": 0, "status": "no_plan", "plan": None, "sms_status": "NONE",
                   "join": {"text": "LAMP " + code.replace("-", ""), "to": "21213"}, "trusted": False}
    assert all(set(x) == set(row) for x in rows)
    assert "name" not in r.text


def test_rows_are_oldest_debt_first(client):
    rows = client.get(f"{P}/customers").json()
    assert [x["since"] for x in rows] == sorted(x["since"] for x in rows)


def test_future_since_is_422(client):
    r = _add(client, since=TODAY + timedelta(days=1))
    assert r.status_code == 422 and r.json()["code"] == "invalid"


def test_a_negative_amount_is_422(client):
    assert _add(client, amount=-1).status_code == 422


def test_join_text():
    assert patients.join_text("GL-7KQM-4XPA").model_dump() == {"text": "LAMP GL7KQM4XPA", "to": "21213"}


# --- Sales and payments on a card --------------------------------------------------------

def test_sale_then_payment(client, api_db):
    code = _add(client, amount=1000).json()["code"]
    r = _money(client, code, "sales", 500)
    assert r.status_code == 201, r.text
    assert r.json() == {"code": code, "amount": 1500}
    r = _money(client, code, "payments", 200, method="bkash")
    assert r.status_code == 201, r.text
    assert r.json() == {"code": code, "amount": 1300}
    rows = _ledger(api_db, code)
    assert [(x.kind, x.amount, x.method) for x in rows] == [("adjust", 1000, None), ("sale", 500, None),
                                                            ("payment", -200, "bkash")]
    api_db.expire_all()
    assert sum(x.amount for x in rows) == api_db.scalar(select(m.PatientDue.amount).where(m.PatientDue.code == code))


def test_a_code_in_any_spelling(client):
    code = _add(client).json()["code"]
    r = _money(client, code.replace("-", "").lower(), "sales", 100)
    assert r.status_code == 201 and r.json()["code"] == code


def test_overpayment_is_422_and_nothing_changes(client, api_db):
    code = _add(client, amount=300).json()["code"]
    r = _money(client, code, "payments", 300.01, method="cash")
    assert r.status_code == 422 and r.json()["code"] == "invalid"
    assert len(_ledger(api_db, code)) == 1
    assert _money(client, code, "payments", 300, method="cash").json()["amount"] == 0


def test_a_future_sale_is_422(client):
    code = _add(client).json()["code"]
    assert _money(client, code, "sales", 100, on=TODAY + timedelta(days=1)).status_code == 422


@pytest.mark.parametrize("amount", [0, -5])
def test_zero_or_negative_money_is_422(client, amount):
    code = _add(client).json()["code"]
    assert _money(client, code, "sales", amount).status_code == 422


# --- The plan, set with the family at the counter ----------------------------------------

def test_owner_sets_the_plan(client):
    code = _add(client, amount=1000).json()["code"]
    first = TODAY + timedelta(days=3)
    r = client.put(f"{P}/customers/{code}/plan", json={"parts": 2, "first_on": first.isoformat()})
    assert r.status_code == 200, r.text
    plan = r.json()["plan"]
    assert plan["parts"] == 2 and [p["amount"] for p in plan["schedule"]] == [500, 500]
    assert client.get(f"/api/v1/cards/{code}").json()["plan"] == plan
    row = next(x for x in client.get(f"{P}/customers").json() if x["code"] == code)
    assert row["status"] == "planned" and row["plan"] == plan


def test_a_plan_outside_two_weeks_is_422(client):
    code = _add(client).json()["code"]
    r = client.put(f"{P}/customers/{code}/plan", json={"parts": 2, "first_on": (TODAY + timedelta(days=15)).isoformat()})
    assert r.status_code == 422


# --- Trusted: all parts paid on time (build plan 2.2) ------------------------------------

def _planned(client, api_db, *, paid_on_day: int | None, pay: float = 500):
    """A BDT 1,000 card with 2 weekly parts of 500: part 1 due today, part 2 in 7 days. With
    `paid_on_day`, 500 is paid that many days after today."""
    code = _add(client, amount=1000).json()["code"]
    client.put(f"{P}/customers/{code}/plan", json={"parts": 2, "first_on": TODAY.isoformat()})
    if paid_on_day is not None:
        _money(client, code, "payments", pay, on=TODAY, method="cash")
        row = _ledger(api_db, code)[-1]
        row.on_date = TODAY + timedelta(days=paid_on_day)
        api_db.commit()
    return code


def _trusted(client, api_db, code, days_later: int) -> bool:
    ph = api_db.get(m.Pharmacy, "green-life")
    ph.settings = ph.settings | {"as_of_date": (TODAY + timedelta(days=days_later)).isoformat()}
    api_db.commit()
    return next(x for x in client.get(f"{P}/customers").json() if x["code"] == code)["trusted"]


def test_a_part_paid_on_its_day_is_trusted(client, api_db):
    code = _planned(client, api_db, paid_on_day=0)
    assert _trusted(client, api_db, code, days_later=1) is True


def test_a_part_paid_a_day_late_is_not_trusted(client, api_db):
    code = _planned(client, api_db, paid_on_day=1)
    assert _trusted(client, api_db, code, days_later=2) is False


def test_an_unpaid_part_is_not_trusted(client, api_db):
    code = _planned(client, api_db, paid_on_day=None)
    assert _trusted(client, api_db, code, days_later=1) is False


def test_the_second_part_counts_too(client, api_db):
    code = _planned(client, api_db, paid_on_day=0)  # part 1 paid; part 2 (due day 7) never paid
    assert _trusted(client, api_db, code, days_later=8) is False


def test_nothing_due_yet_is_not_trusted(client, api_db):
    code = _planned(client, api_db, paid_on_day=None)
    assert _trusted(client, api_db, code, days_later=0) is False


# --- Another shop's card -----------------------------------------------------------------

def test_another_shops_code_is_404(client, api_db):
    api_db.add(m.Pharmacy(id="bravo", name="Bravo", city="Dhaka", cash_on_hand=0, settings={}, kind="real"))
    api_db.flush()
    api_db.add(m.PatientDue(pharmacy_id="bravo", label="Customer 001", amount=400, since=TODAY, code="BR-2222-3333"))
    api_db.commit()
    for kind in ("sales", "payments"):
        r = _money(client, "BR-2222-3333", kind, 10, method="cash")
        assert r.status_code == 404 and r.json()["code"] == "not_found" and "BR-" not in r.text
    r = client.put(f"{P}/customers/BR-2222-3333/plan", json={"parts": 1, "first_on": TODAY.isoformat()})
    assert r.status_code == 404
    assert api_db.scalar(select(func.count()).select_from(m.PatientLedger)) == 0
    assert api_db.scalar(select(m.PatientDue.plan_parts).where(m.PatientDue.code == "BR-2222-3333")) is None
