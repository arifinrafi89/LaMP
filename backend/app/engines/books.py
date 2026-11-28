"""The shop's books, typed by hand (build plan 2.2 "Shop setup" and "Daily screens"; task I2.2).

The opening cash, supplier payments and sales-book days. Each records rows, as the plan writes
it. The plan doesn't say how a real shop's cash moves after the opening, so a payment or a
sales day doesn't change `cash_on_hand` (an open question in PROGRESS.md).
"""

from datetime import date

from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.db import models as m
from app.db.seed import upsert_sales_days
from app.schemas.product import SalesDayIn

from .common import as_of, r2
from .logbus import log


def _not_after_today(ph: m.Pharmacy, on: date, what: str) -> None:
    if on > as_of(ph):
        raise ApiProblem(422, "invalid", f"The {what} can't be after today.")


def set_opening(db: Session, ph: m.Pharmacy, cash: float, on: date) -> None:
    """The opening cash: the forecast reads it as the cash at the start of the shop's today."""
    _not_after_today(ph, on, "opening cash date")
    ph.cash_on_hand = r2(cash)
    log("T1", "SETUP", "opening_cash_set", db, pharmacy=ph.id, cash_on_hand=r2(cash), as_of=on)
    db.flush()


def record_payment(db: Session, ph: m.Pharmacy, invoice_id: int, amount: float, paid_on: date,
                   method: str) -> m.Payment:
    """A payment to a supplier against one of the shop's invoices. The invoice is paid once
    its payments cover the total; more than is still owed is refused."""
    inv = db.get(m.Invoice, invoice_id)
    if inv is None or inv.pharmacy_id != ph.id:
        raise ApiProblem(404, "not_found", "Not found.")
    _not_after_today(ph, paid_on, "payment date")
    owed = r2(inv.total - sum(p.amount for p in inv.payments))
    if inv.status == "paid" or owed <= 0:
        raise ApiProblem(422, "invalid", "This bill is already paid.")
    if r2(amount) > owed:
        raise ApiProblem(422, "invalid", f"Only BDT {owed:,.2f} is still owed on this bill.")
    pay = m.Payment(amount=r2(amount), paid_on=paid_on, method=method)
    inv.payments.append(pay)
    if r2(owed - amount) <= 0:
        inv.status = "paid"
    log("T1", "BOOKS", "payment_recorded", db, pharmacy=ph.id, invoice=inv.invoice_no, amount=r2(amount),
        method=method, paid_on=paid_on, invoice_paid=inv.status == "paid")
    db.flush()
    return pay


def record_sales_day(db: Session, ph: m.Pharmacy, day: SalesDayIn) -> None:
    """One sales-book day, typed. Typing the same date again replaces it, as a scanned page does."""
    _not_after_today(ph, day.date, "sales day")
    upsert_sales_days(db, ph.id, [day.model_dump()])
    log("T1", "BOOKS", "sales_day_recorded", db, pharmacy=ph.id, date=day.date)
