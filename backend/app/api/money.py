"""The daily screens' own routes (build plan 2.2 "Daily screens"; task I2.2): Today in one
call, and money recorded by hand (a payment to a supplier, a typed sales-book day).

Mounted on the owner router in routes.py, so {pid} is already the caller's own shop.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.engines import books, get_pharmacy
from app.engines.today import get_today
from app.schemas.product import PaymentIn, SalesDayIn, Saved, TodayOut
from .problems import ERRORS

router = APIRouter(responses=ERRORS)
P = "/pharmacies/{pid}"


@router.get(f"{P}/today", response_model=TodayOut)
def today(pid: str, db: Session = Depends(get_db)):
    """One call for the Today screen, made for slow networks."""
    return get_today(db, pid)


@router.post(f"{P}/payments", response_model=Saved, status_code=201)
def record_payment(pid: str, body: PaymentIn, db: Session = Depends(get_db)):
    books.record_payment(db, get_pharmacy(db, pid), body.invoice_id, body.amount, body.paid_on, body.method)
    db.commit()
    return Saved(saved=1)


@router.post(f"{P}/sales-days", response_model=Saved, status_code=201)
def record_sales_day(pid: str, body: SalesDayIn, db: Session = Depends(get_db)):
    books.record_sales_day(db, get_pharmacy(db, pid), body)
    db.commit()
    return Saved(saved=1)
