"""Customers (build plan 2.2 "Customers", 3.4; task I2.2): the owner's list with each card's
join text, adding a card, a sale, a payment, and the plan set with the family at the counter.

Mounted on the owner router in routes.py, so {pid} is already the caller's own shop; a card
code of another shop is 404. Amounts only: there is no name field. The phone and remind
routes come with the Applink facade (A2.2 part 2), as does the receipt SMS for a payment.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.engines import get_pharmacy, patients
from app.schemas import PatientCardOut
from app.schemas.product import CustomerBalance, CustomerCreate, CustomerCreated, CustomerMoneyIn, CustomerPlanIn, CustomerRow

from .problems import ERRORS

router = APIRouter(responses=ERRORS)
C = "/pharmacies/{pid}/customers"


@router.get(C, response_model=list[CustomerRow])
def list_customers(pid: str, db: Session = Depends(get_db)):
    """Every customer card, oldest debt first, with its SMS status, join text and trust."""
    return patients.rows_for_owner(db, pid)


@router.post(C, response_model=CustomerCreated, status_code=201)
def add_customer(pid: str, body: CustomerCreate, db: Session = Depends(get_db)):
    """A new card, `{amount, since}` → its code, label and the text the family sends to join."""
    d = patients.new_card(db, get_pharmacy(db, pid), body.amount, body.since)
    db.commit()
    return CustomerCreated(code=d.code, label=d.label, join=patients.join_text(d.code))


@router.post(f"{C}/{{code}}/sales", response_model=CustomerBalance, status_code=201)
def add_sale(pid: str, code: str, body: CustomerMoneyIn, db: Session = Depends(get_db)):
    out = patients.record(db, pid, code, "sale", body.amount, body.on, None)
    db.commit()
    return out


@router.post(f"{C}/{{code}}/payments", response_model=CustomerBalance, status_code=201)
def add_payment(pid: str, code: str, body: CustomerMoneyIn, db: Session = Depends(get_db)):
    out = patients.record(db, pid, code, "payment", body.amount, body.on, body.method or "cash")
    db.commit()
    return out


@router.put(f"{C}/{{code}}/plan", response_model=PatientCardOut)
def set_plan(pid: str, code: str, body: CustomerPlanIn, db: Session = Depends(get_db)):
    """The owner sets the plan with the family at the counter: the same engine as the card."""
    d = patients.shop_card(db, pid, code)
    out = patients.set_plan(db, d.code, body.parts, body.first_on, by="owner")
    db.commit()
    return out
