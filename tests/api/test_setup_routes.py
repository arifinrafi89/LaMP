"""The first day's setup data (build plan 2.2 "Shop setup"; task I2.2, part 2): suppliers,
the opening cash, typed opening stock and monthly expenses."""

from datetime import timedelta

import pytest
from sqlalchemy import func, select

from app.db import models as m
from app.db.seed import SEED_AS_OF

P = "/api/v1/pharmacies/green-life"
TODAY = SEED_AS_OF  # the demo shop's fixed date in the tests


def _other_shop_supplier(api_db) -> int:
    api_db.add(m.Pharmacy(id="bravo", name="Bravo", city="Dhaka", cash_on_hand=0, settings={}, kind="real"))
    api_db.flush()
    sup = m.Supplier(pharmacy_id="bravo", name="Bravo Supplier")
    api_db.add(sup)
    api_db.commit()
    return sup.id


# --- Suppliers ---------------------------------------------------------------------------

def test_add_list_edit_delete_supplier(client):
    r = client.post(f"{P}/suppliers", json={"name": "Popular Pharma", "phone": "+8801711000000",
                                             "payment_days": 45, "return_cutoff_days": 60})
    assert r.status_code == 201, r.text
    sup = r.json()
    assert sup["name"] == "Popular Pharma" and sup["phone"] == "+8801711000000"
    assert sup["payment_days"] == 45 and sup["return_cutoff_days"] == 60 and isinstance(sup["id"], int)

    listed = client.get(f"{P}/suppliers").json()
    assert sup in listed and len(listed) == 25  # the seed's 24, plus this one

    r = client.patch(f"{P}/suppliers/{sup['id']}", json={"name": "Popular Pharma Ltd", "payment_days": 30})
    assert r.status_code == 200, r.text
    assert r.json()["name"] == "Popular Pharma Ltd" and r.json()["payment_days"] == 30

    assert client.delete(f"{P}/suppliers/{sup['id']}").status_code == 204
    assert sup["id"] not in {s["id"] for s in client.get(f"{P}/suppliers").json()}
    assert client.delete(f"{P}/suppliers/{sup['id']}").status_code == 404


def test_a_supplier_gets_the_defaults(client):
    sup = client.post(f"{P}/suppliers", json={"name": "Square"}).json()
    assert sup["phone"] is None and sup["payment_days"] == 30 and sup["return_cutoff_days"] == 30


@pytest.mark.parametrize("body", [{"name": ""}, {"name": "X", "payment_days": 181}, {"name": "X", "return_cutoff_days": -1}])
def test_bad_supplier_values_are_422(client, body):
    assert client.post(f"{P}/suppliers", json=body).status_code == 422


def test_another_shops_supplier_is_404(client, api_db):
    sid = _other_shop_supplier(api_db)
    assert client.patch(f"{P}/suppliers/{sid}", json={"name": "Mine"}).status_code == 404
    assert client.delete(f"{P}/suppliers/{sid}").status_code == 404
    assert client.patch(f"{P}/suppliers/99999", json={"name": "Mine"}).status_code == 404
    assert api_db.get(m.Supplier, sid).name == "Bravo Supplier"


def test_a_deleted_supplier_keeps_its_invoices(client):
    before = client.get(f"{P}/dues").json()["total_due"]
    assert client.delete(f"{P}/suppliers/4").status_code == 204  # Supplier D has an unpaid invoice
    assert client.get(f"{P}/dues").json()["total_due"] == before


# --- Opening cash ------------------------------------------------------------------------

def test_opening_sets_cash(client):
    r = client.post(f"{P}/opening", json={"cash_on_hand": 25000, "as_of": TODAY.isoformat()})
    assert r.status_code == 200, r.text
    assert r.json() == {"saved": 1}
    assert client.get(f"{P}/forecast").json()["start_cash"] == 25000


def test_opening_in_the_future_is_422(client):
    r = client.post(f"{P}/opening", json={"cash_on_hand": 25000, "as_of": (TODAY + timedelta(days=1)).isoformat()})
    assert r.status_code == 422 and r.json()["code"] == "invalid"


def test_negative_opening_cash_is_422(client):
    assert client.post(f"{P}/opening", json={"cash_on_hand": -1, "as_of": TODAY.isoformat()}).status_code == 422


# --- Opening stock -----------------------------------------------------------------------

def _line(**kw) -> dict:
    return {"product": "Napa", "strength": "500 mg", "batch_no": "NP-1", "expiry_date": "2027-03-31",
            "qty": 100, "unit_cost": 1.2, "supplier_id": 1} | kw


def test_stock_batches(client, api_db):
    r = client.post(f"{P}/stock-batches", json=[_line(), _line(product="Seclo", strength=None, batch_no="SC-9",
                                                               expiry_date="2027-01-15", qty=30, unit_cost=5)])
    assert r.status_code == 201, r.text
    assert r.json() == {"saved": 2}
    batches = {b["batch_no"]: b for b in client.get(f"{P}/expiry", params={"horizon_days": 400}).json()["batches"]}
    assert batches["NP-1"]["qty"] == 100 and batches["SC-9"]["product"] == "Seclo"
    row = api_db.scalar(select(m.StockBatch).where(m.StockBatch.batch_no == "NP-1"))
    assert row.strength == "500 mg" and row.pharmacy_id == "green-life"


@pytest.mark.parametrize("bad_supplier", ["deleted", "other_shop", "missing"])
def test_stock_for_a_supplier_not_ours_saves_nothing(client, api_db, bad_supplier):
    sid = {"deleted": 4, "other_shop": None, "missing": 99999}[bad_supplier]
    if bad_supplier == "deleted":
        client.delete(f"{P}/suppliers/4")
    if bad_supplier == "other_shop":
        sid = _other_shop_supplier(api_db)
    before = api_db.scalar(select(func.count()).select_from(m.StockBatch))
    r = client.post(f"{P}/stock-batches", json=[_line(), _line(batch_no="NP-2", supplier_id=sid)])
    assert r.status_code == 422 and r.json()["code"] == "invalid"
    assert api_db.scalar(select(func.count()).select_from(m.StockBatch)) == before


@pytest.mark.parametrize("bad", [{"qty": 0}, {"unit_cost": -1}, {"expiry_date": "soon"}])
def test_bad_stock_values_are_422(client, bad):
    assert client.post(f"{P}/stock-batches", json=[_line(**bad)]).status_code == 422


# --- Monthly expenses --------------------------------------------------------------------

def test_expenses_are_added(client, api_db):
    def count():
        return api_db.scalar(select(func.count()).select_from(m.ExpenseSchedule)
                             .where(m.ExpenseSchedule.pharmacy_id == "green-life"))

    before = count()
    r = client.post(f"{P}/expenses", json=[{"category": "Rent", "amount": 8000, "day_of_month": 5},
                                           {"category": "Salaries", "amount": 12000, "day_of_month": 1}])
    assert r.status_code == 201, r.text
    assert r.json() == {"saved": 2}
    assert count() == before + 2
    labels = {i["label"] for d in client.get(f"{P}/forecast").json()["days"] for i in d["items"]}
    assert {"Rent", "Salaries"} <= labels


@pytest.mark.parametrize("bad", [{"day_of_month": 29}, {"day_of_month": 0}, {"amount": -5}])
def test_bad_expenses_are_422(client, bad):
    line = {"category": "Rent", "amount": 8000, "day_of_month": 5} | bad
    assert client.post(f"{P}/expenses", json=[line]).status_code == 422
