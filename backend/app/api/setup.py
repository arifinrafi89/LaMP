"""The first day's setup data (build plan 2.2 "Shop setup", 5.2 "First day"; task I2.2):
suppliers, the opening cash, typed opening stock and monthly expenses.

Mounted on the owner router in routes.py, so {pid} is already the caller's own shop. A
supplier id of another shop, or a removed one, is 404 like any id that isn't ours.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.problems import ERRORS, ApiProblem
from app.db import models as m
from app.db.session import get_db
from app.engines import books, get_pharmacy
from app.engines.common import r2
from app.engines.logbus import log
from app.schemas.product import ExpenseIn, OpeningIn, Saved, StockBatchIn, SupplierIn, SupplierOut

from .deps import not_found

router = APIRouter(responses=ERRORS)
P = "/pharmacies/{pid}"


def shop_supplier(db: Session, pid: str, sid: int) -> m.Supplier:
    """One of this shop's suppliers that hasn't been removed; 404 otherwise."""
    sup = db.get(m.Supplier, sid)
    if sup is None or sup.pharmacy_id != pid or sup.deleted_at is not None:
        raise not_found()
    return sup


def _name(body: SupplierIn) -> str:
    if not body.name.strip():
        raise ApiProblem(422, "invalid", "The supplier needs a name.")
    return body.name.strip()


def _out(sup: m.Supplier) -> SupplierOut:
    return SupplierOut(id=sup.id, name=sup.name, phone=sup.phone, payment_days=sup.payment_days,
                       return_cutoff_days=sup.return_cutoff_days)


# --- Suppliers ---------------------------------------------------------------------------

@router.get(f"{P}/suppliers", response_model=list[SupplierOut])
def list_suppliers(pid: str, db: Session = Depends(get_db)):
    rows = db.scalars(select(m.Supplier).where(m.Supplier.pharmacy_id == pid, m.Supplier.deleted_at.is_(None))
                      .order_by(m.Supplier.id))
    return [_out(s) for s in rows]


@router.post(f"{P}/suppliers", response_model=SupplierOut, status_code=201)
def add_supplier(pid: str, body: SupplierIn, db: Session = Depends(get_db)):
    sup = m.Supplier(pharmacy_id=pid, name=_name(body), verified=False, phone=body.phone,
                     payment_days=body.payment_days, return_cutoff_days=body.return_cutoff_days)
    db.add(sup)
    db.flush()
    log("T1", "SETUP", "supplier_added", db, pharmacy=pid, supplier=sup.id)
    db.commit()
    return _out(sup)


@router.patch(f"{P}/suppliers/{{sid}}", response_model=SupplierOut)
def edit_supplier(pid: str, sid: int, body: SupplierIn, db: Session = Depends(get_db)):
    sup = shop_supplier(db, pid, sid)
    sup.name, sup.phone = _name(body), body.phone
    sup.payment_days, sup.return_cutoff_days = body.payment_days, body.return_cutoff_days
    log("T1", "SETUP", "supplier_changed", db, pharmacy=pid, supplier=sid)
    db.commit()
    return _out(sup)


@router.delete(f"{P}/suppliers/{{sid}}", status_code=204)
def remove_supplier(pid: str, sid: int, db: Session = Depends(get_db)) -> Response:
    """Removed from the list. The row stays: invoices and stock batches point at it."""
    sup = shop_supplier(db, pid, sid)
    sup.deleted_at = datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)
    log("T1", "SETUP", "supplier_removed", db, pharmacy=pid, supplier=sid)
    db.commit()
    return Response(status_code=204)


# --- Opening cash, stock and expenses ----------------------------------------------------

@router.post(f"{P}/opening", response_model=Saved)
def set_opening(pid: str, body: OpeningIn, db: Session = Depends(get_db)):
    """The cash in the drawer today (first day, step 4)."""
    books.set_opening(db, get_pharmacy(db, pid), body.cash_on_hand, body.as_of)
    db.commit()
    return Saved(saved=1)


@router.post(f"{P}/stock-batches", response_model=Saved, status_code=201)
def add_stock(pid: str, body: list[StockBatchIn], db: Session = Depends(get_db)):
    """Typed opening stock. All lines are saved, or none: every supplier is checked first."""
    try:
        for line in body:
            shop_supplier(db, pid, line.supplier_id)
    except ApiProblem:
        raise ApiProblem(422, "invalid", "Pick one of your suppliers for every line.") from None
    for line in body:
        db.add(m.StockBatch(pharmacy_id=pid, supplier_id=line.supplier_id, product=line.product.strip(),
                            strength=line.strength, batch_no=line.batch_no.strip(), expiry_date=line.expiry_date,
                            qty=line.qty, unit_cost=r2(line.unit_cost)))
    log("T1", "SETUP", "stock_typed", db, pharmacy=pid, lines=len(body))
    db.commit()
    return Saved(saved=len(body))


@router.post(f"{P}/expenses", response_model=Saved, status_code=201)
def add_expenses(pid: str, body: list[ExpenseIn], db: Session = Depends(get_db)):
    """Monthly rent and salaries, for the forecast (first day, step 5)."""
    for line in body:
        db.add(m.ExpenseSchedule(pharmacy_id=pid, category=line.category.strip(), amount=r2(line.amount),
                                 day_of_month=line.day_of_month))
    log("T1", "SETUP", "expenses_added", db, pharmacy=pid, lines=len(body))
    db.commit()
    return Saved(saved=len(body))
