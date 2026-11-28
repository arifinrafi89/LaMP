"""Money recorded by hand (build plan 2.2 "Daily screens"; task I2.2, part 2): a payment to a
supplier, and a typed sales-book day. They record rows; how a real shop's cash moves after
the opening is a question for the team (PROGRESS.md), so neither changes cash_on_hand."""

from datetime import timedelta

import pytest
from sqlalchemy import select

from app.db import models as m
from app.db.seed import SEED_AS_OF

P = "/api/v1/pharmacies/green-life"
TODAY = SEED_AS_OF
INVOICE = 45  # H-5520, BDT 11,300, unpaid, due 2026-11-04


def _pay(client, amount, invoice=INVOICE, method="bkash", paid_on=TODAY):
    return client.post(f"{P}/payments", json={"invoice_id": invoice, "amount": amount,
                                              "paid_on": paid_on.isoformat(), "method": method})


def _forecast_labels(client) -> set[str]:
    return {i["label"] for d in client.get(f"{P}/forecast").json()["days"] for i in d["items"]}


# --- Supplier payments -------------------------------------------------------------------

def test_payment_reduces_what_is_owed(client, api_db):
    before = client.get(f"{P}/dues").json()["total_due"]
    r = _pay(client, 3000)
    assert r.status_code == 201, r.text
    assert r.json() == {"saved": 1}
    assert client.get(f"{P}/dues").json()["total_due"] == pytest.approx(before - 3000)
    pay = api_db.scalar(select(m.Payment).where(m.Payment.invoice_id == INVOICE))
    assert pay.method == "bkash" and pay.pharmacy_id == "green-life" and pay.paid_on == TODAY
    assert api_db.get(m.Invoice, INVOICE).status == "unpaid"


def test_a_payment_does_not_change_the_opening_cash(client):
    start = client.get(f"{P}/forecast").json()["start_cash"]
    _pay(client, 3000)
    assert client.get(f"{P}/forecast").json()["start_cash"] == start


def test_payment_that_clears_the_invoice_marks_it_paid(client, api_db):
    assert any("H-5520" in label for label in _forecast_labels(client))
    assert _pay(client, 11300).status_code == 201
    api_db.expire_all()
    assert api_db.get(m.Invoice, INVOICE).status == "paid"
    assert not any("H-5520" in label for label in _forecast_labels(client))


def test_two_payments_can_clear_it(client, api_db):
    assert _pay(client, 6000).status_code == 201
    assert _pay(client, 5300, method="cash").status_code == 201
    api_db.expire_all()
    assert api_db.get(m.Invoice, INVOICE).status == "paid"


def test_overpayment_is_422(client, api_db):
    r = _pay(client, 11300.01)
    assert r.status_code == 422 and r.json()["code"] == "invalid"
    assert api_db.scalar(select(m.Payment).where(m.Payment.invoice_id == INVOICE)) is None


def test_a_paid_invoice_takes_no_more(client):
    paid = 1  # the seed's first invoice is paid in full
    r = _pay(client, 10, invoice=paid)
    assert r.status_code == 422 and r.json()["code"] == "invalid"


def test_future_payment_is_422(client):
    assert _pay(client, 100, paid_on=TODAY + timedelta(days=1)).status_code == 422


def test_foreign_or_unknown_invoice_is_404(client, api_db):
    api_db.add(m.Pharmacy(id="bravo", name="Bravo", city="Dhaka", cash_on_hand=0, settings={}, kind="real"))
    api_db.flush()
    sup = m.Supplier(pharmacy_id="bravo", name="Bravo Supplier")
    api_db.add(sup)
    api_db.flush()
    inv = m.Invoice(pharmacy_id="bravo", supplier_id=sup.id, invoice_no="BR-1", invoice_date=TODAY,
                    due_date=TODAY, total=500)
    api_db.add(inv)
    api_db.commit()
    for invoice in (inv.id, 99999):
        r = _pay(client, 100, invoice=invoice)
        assert r.status_code == 404 and r.json()["code"] == "not_found"
        assert "BR-" not in r.text


@pytest.mark.parametrize("bad", [{"amount": 0}, {"method": "card"}])
def test_bad_payment_values_are_422(client, bad):
    body = {"invoice_id": INVOICE, "amount": 100, "paid_on": TODAY.isoformat(), "method": "cash"} | bad
    assert client.post(f"{P}/payments", json=body).status_code == 422


# --- Sales-book days ---------------------------------------------------------------------

def _day(on, cash=5000.0, **kw) -> dict:
    return {"date": on.isoformat(), "cash_sales": cash, "credit_sales": 800, "dues_collected": 300,
            "expenses": 150} | kw


def test_a_sales_day_is_saved(client, api_db):
    on = TODAY - timedelta(days=1)
    r = client.post(f"{P}/sales-days", json=_day(on))
    assert r.status_code == 201, r.text
    assert r.json() == {"saved": 1}
    row = api_db.scalar(select(m.SalesDay).where(m.SalesDay.pharmacy_id == "green-life", m.SalesDay.date == on))
    assert (row.cash_sales, row.credit_sales, row.dues_collected, row.expenses) == (5000, 800, 300, 150)


def test_sales_day_twice_keeps_one_row(client, api_db):
    on = TODAY - timedelta(days=1)
    client.post(f"{P}/sales-days", json=_day(on, cash=5000))
    client.post(f"{P}/sales-days", json=_day(on, cash=6000))
    api_db.expire_all()
    rows = list(api_db.scalars(select(m.SalesDay).where(m.SalesDay.pharmacy_id == "green-life",
                                                        m.SalesDay.date == on)))
    assert len(rows) == 1 and rows[0].cash_sales == 6000


def test_today_can_be_typed_but_not_tomorrow(client):
    assert client.post(f"{P}/sales-days", json=_day(TODAY)).status_code == 201
    r = client.post(f"{P}/sales-days", json=_day(TODAY + timedelta(days=1)))
    assert r.status_code == 422 and r.json()["code"] == "invalid"


def test_negative_sales_are_422(client):
    assert client.post(f"{P}/sales-days", json=_day(TODAY, cash=-1)).status_code == 422
