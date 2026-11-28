"""Two shops for the tenancy tests (build plan 9.3 item 1): Green Life (A, the seed) and
Bravo (B), a copy with changed names, ids and figures. Each has an owner token.

SQLite in memory by default; TEST_DATABASE_URL runs it on Postgres, as CI does from A1.4.
"""

import json
import os
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import models as m
from app.db.seed import SEED_DIR, add_invoice, load_seed, upsert_sales_days
from app.db.session import get_db
from app.main import app
from tenancy_support import A, B


_url = os.environ.get("TEST_DATABASE_URL", "sqlite://")
engine = (create_engine(_url, connect_args={"check_same_thread": False}, poolclass=StaticPool)
          if _url.startswith("sqlite") else create_engine(_url))
TenancySession = sessionmaker(bind=engine, expire_on_commit=False)


def _get_db():
    db = TenancySession()
    try:
        yield db
    finally:
        db.close()


def _d(s: str):
    from datetime import date

    return date.fromisoformat(s)


def add_shop_b(db) -> dict:
    """Bravo: Green Life's seed under other names and ids, with 1,111 more cash."""
    seed = json.loads((SEED_DIR / "green_life.json").read_text(encoding="utf-8"))
    p = seed["pharmacy"]
    db.add(m.Pharmacy(id=B, name="Bravo Medical Hall", city="Khulna", cash_on_hand=p["cash_on_hand"] + 1111,
                      settings=p["settings"], kind="team_test", card_prefix="BR", setup_complete=True,
                      created_at=datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)))
    for s in seed["suppliers"]:
        db.add(m.Supplier(pharmacy_id=B, **(s | {"name": "Bravo " + s["name"]})))
    db.flush()
    for inv in seed["invoices"]:
        add_invoice(db, B, inv | {"supplier": "Bravo " + inv["supplier"], "invoice_no": "BR-" + inv["invoice_no"]},
                    supplier_confirmed=inv["supplier_confirmed"], payment=inv["payment"])
    upsert_sales_days(db, B, seed["sales_days"])
    for b in seed["stock_batches"]:
        sup = db.query(m.Supplier).filter_by(pharmacy_id=B, name="Bravo " + b["supplier"]).one()
        db.add(m.StockBatch(pharmacy_id=B, supplier_id=sup.id, product="Bravo " + b["product"],
                            batch_no="BR-" + b["batch_no"], expiry_date=_d(b["expiry_date"]), qty=b["qty"],
                            unit_cost=b["unit_cost"]))
    codes = []
    for i, pd in enumerate(seed["patient_dues"]):
        code = f"BR-{i:04d}-BRVO"
        codes.append(code)
        db.add(m.PatientDue(pharmacy_id=B, label=pd["label"], amount=pd["amount"] + 11, since=_d(pd["since"]),
                            code=code))
    orders = []
    for o in seed["planned_orders"]:
        sup = db.query(m.Supplier).filter_by(pharmacy_id=B, name="Bravo " + o["supplier"]).one()
        oid = "bravo-" + o["id"]
        orders.append(oid)
        db.add(m.PlannedOrder(id=oid, pharmacy_id=B, supplier_id=sup.id, ref="BR-" + o["ref"],
                              due_date=_d(o["due_date"]), status=o["status"],
                              lines=[m.PlannedOrderLine(pharmacy_id=B, product="Bravo " + ln["product"], qty=ln["qty"],
                                                        unit_cost=ln["unit_cost"], expiry_date=_d(ln["expiry_date"]))
                                     for ln in o["lines"]]))
    db.flush()
    from app.engines import actions as action_engine
    from app.schemas import ActionProposal

    action = action_engine.propose_action(db, B, ActionProposal(kind="set_aside", payload={"amount": 777}), "owner")
    db.commit()
    return {"codes": codes, "orders": orders, "action": action.id}


@pytest.fixture
def two_shops(owner_headers):
    """(client, ids): the client carries A's token; `ids` holds B's ids and both tokens."""
    with TenancySession() as s:
        load_seed(s, with_demo_captures=True)
        ids = add_shop_b(s)
        ids["a_headers"] = owner_headers(s, A)
        ids["b_headers"] = owner_headers(s, B)
    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = _get_db
    try:
        yield TestClient(app, headers=ids["a_headers"]), ids
    finally:
        if previous is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = previous
