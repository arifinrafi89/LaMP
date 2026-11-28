"""Customer cards: a patient sees what they owe the pharmacy and picks a way to pay it back.

The customer opens /me/<code>. The code is the only key, so the card carries amounts only:
the pharmacy's alias for the customer, never a name or a medicine. A plan is a promise, not a
payment: no money moves until the customer pays at the counter.
"""

import math
import re
import secrets
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.applink.config import get_settings as applink_settings
from app.db import models as m
from app.schemas import PatientCardOut, PatientPlan, PlanOption, PlanPart
from app.schemas.product import CustomerBalance, CustomerRow, JoinText

from .common import as_of, get_pharmacy, r2
from .logbus import log, notify

PLAN_PARTS = (1, 2, 4)
PART_GAP_DAYS = 7          # the parts of a plan fall due a week apart
FIRST_PART_WITHIN_DAYS = 14  # the first part must fall within two weeks of the pharmacy's today


def _bdt(x: float) -> str:
    return f"BDT {x:,.0f}"


def normalize_code(raw: str) -> str:
    """'gl7kqm4xpa', 'GL 7KQM 4XPA' and 'GL-7KQM-4XPA' are the same code."""
    s = re.sub(r"[^A-Z0-9]", "", raw.upper())
    return f"{s[:2]}-{s[2:6]}-{s[6:]}" if len(s) == 10 else s


def split(amount: float, parts: int) -> list[float]:
    """Equal whole-taka parts; the last part takes the remainder. 6,500 in 4 → 1,625 × 4."""
    base = math.floor(amount / parts)
    return [float(base)] * (parts - 1) + [r2(amount - base * (parts - 1))]


def schedule(amount: float, parts: int, first_on: date) -> list[PlanPart]:
    return [PlanPart(n=i + 1, due_on=first_on + timedelta(days=PART_GAP_DAYS * i), amount=a)
            for i, a in enumerate(split(amount, parts))]


def _plan(d: m.PatientDue) -> PatientPlan | None:
    if d.plan_parts is None or d.plan_first_on is None:
        return None
    return PatientPlan(parts=d.plan_parts, first_on=d.plan_first_on,
                       schedule=schedule(d.amount, d.plan_parts, d.plan_first_on))


def _by_code(db: Session, code: str) -> m.PatientDue:
    d = db.scalar(select(m.PatientDue).where(m.PatientDue.code == normalize_code(code)))
    if d is None:
        raise HTTPException(404, "No card with that code. Check the code on your slip from the pharmacy.")
    return d


def get_card(db: Session, code: str) -> PatientCardOut:
    d = _by_code(db, code)
    ph = get_pharmacy(db, d.pharmacy_id)
    today = as_of(ph)
    return PatientCardOut(
        pharmacy_name=ph.name, city=ph.city, label=d.label, amount=r2(d.amount), since=d.since,
        days_outstanding=(today - d.since).days, as_of=today,
        latest_first_on=today + timedelta(days=FIRST_PART_WITHIN_DAYS),
        options=[PlanOption(parts=n, part_amount=split(d.amount, n)[0]) for n in PLAN_PARTS],
        plan=_plan(d),
    )


def set_plan(db: Session, code: str, parts: int, first_on: date, *,
             by: Literal["family", "owner"] = "family") -> PatientCardOut:
    """Record the customer's promise. Setting it again replaces it. When the family sets it
    on their card, the owner is told; when the owner sets it with them at the counter, not."""
    d = _by_code(db, code)
    today = as_of(get_pharmacy(db, d.pharmacy_id))
    if parts not in PLAN_PARTS:
        raise HTTPException(422, f"Choose {', '.join(map(str, PLAN_PARTS[:-1]))} or {PLAN_PARTS[-1]} parts.")
    if not today <= first_on <= today + timedelta(days=FIRST_PART_WITHIN_DAYS):
        raise HTTPException(422, f"Pick a first payment date within {FIRST_PART_WITHIN_DAYS} days")
    d.plan_parts, d.plan_first_on = parts, first_on
    d.plan_amount, d.plan_set_on = r2(d.amount), today
    log("T1", "PATIENT", "plan_set", db, customer=d.label, amount=r2(d.amount), parts=parts, first_on=first_on,
        by=by)
    if by == "family":
        how = "in one payment" if parts == 1 else f"in {parts} weekly parts"
        notify("owner", f"{d.label} set a payment plan",
               f"{_bdt(d.amount)} {how}, starting {first_on:%d %b}.", link="/customers", db=db)
    db.flush()
    return get_card(db, code)


# The owner's customers (build plan 2.2 "Customers"; task I2.2).

CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"  # no 0, 1, I or O: read out at the counter


def join_text(code: str) -> JoinText:
    """What the family texts to join SMS (plan 3.4): LAMP and the code without dashes."""
    return JoinText(text="LAMP " + code.replace("-", ""), to=applink_settings().sms_shortcode)


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def _not_after_today(ph: m.Pharmacy, on: date) -> None:
    if on > as_of(ph):
        raise ApiProblem(422, "invalid", "The date can't be after today.")


def shop_card(db: Session, pid: str, code: str) -> m.PatientDue:
    """This shop's card, by code in any spelling; another shop's, or none at all, is 404."""
    d = db.scalar(select(m.PatientDue).where(m.PatientDue.code == normalize_code(code)))
    if d is None or d.pharmacy_id != pid:
        raise ApiProblem(404, "not_found", "Not found.")
    return d


def new_card(db: Session, ph: m.Pharmacy, amount: float, since: date) -> m.PatientDue:
    """A new customer card: a long random code, the next "Customer NNN" label, and the opening
    balance as the ledger's first row. No name field exists."""
    _not_after_today(ph, since)
    prefix = ph.card_prefix or "LP"
    while True:
        body = "".join(secrets.choice(CODE_ALPHABET) for _ in range(8))
        code = f"{prefix}-{body[:4]}-{body[4:]}"
        if db.scalar(select(m.PatientDue.id).where(m.PatientDue.code == code)) is None:
            break
    n = (db.scalar(select(func.count()).select_from(m.PatientDue).where(m.PatientDue.pharmacy_id == ph.id)) or 0) + 1
    d = m.PatientDue(pharmacy_id=ph.id, label=f"Customer {n:03d}", amount=r2(amount), since=since, code=code)
    db.add(d)
    db.flush()
    db.add(m.PatientLedger(pharmacy_id=ph.id, code=code, kind="adjust", amount=r2(amount), on_date=since,
                           created_at=_now()))
    log("T1", "PATIENT", "card_added", db, pharmacy=ph.id, customer=d.label, amount=r2(amount))
    db.flush()
    return d


def record(db: Session, pid: str, code: str, kind: Literal["sale", "payment"], amount: float, on: date,
           method: str | None) -> CustomerBalance:
    """A sale adds to what the customer owes; a payment takes it off. Amounts only. A payment
    larger than the balance is refused."""
    d = shop_card(db, pid, code)
    _not_after_today(get_pharmacy(db, pid), on)
    amount = r2(amount)
    if kind == "payment" and amount > r2(d.amount):
        raise ApiProblem(422, "invalid", f"This customer owes BDT {d.amount:,.2f}; the payment is more than that.")
    signed = amount if kind == "sale" else -amount
    d.amount = r2(d.amount + signed)
    db.add(m.PatientLedger(pharmacy_id=pid, code=d.code, kind=kind, amount=signed, on_date=on,
                           method=method if kind == "payment" else None, created_at=_now()))
    log("T1", "PATIENT", f"{kind}_recorded", db, pharmacy=pid, customer=d.label, amount=amount, balance=d.amount)
    db.flush()
    return CustomerBalance(code=d.code, amount=d.amount)


def trusted(db: Session, d: m.PatientDue, today: date) -> bool:
    """All parts paid on time (build plan 2.2): every part of the plan, as it was set, that fell
    due before today was covered by its due date by the payments since the plan was set. A card
    with no plan, or no part due yet, isn't trusted yet."""
    if None in (d.plan_parts, d.plan_first_on, d.plan_amount, d.plan_set_on):
        return False
    due = [p for p in schedule(d.plan_amount, d.plan_parts, d.plan_first_on) if p.due_on < today]
    if not due:
        return False
    paid = [(row.on_date, -row.amount) for row in db.scalars(select(m.PatientLedger).where(
        m.PatientLedger.code == d.code, m.PatientLedger.kind == "payment",
        m.PatientLedger.on_date >= d.plan_set_on))]
    owed = 0.0
    for part in due:
        owed += part.amount
        if r2(sum(a for on, a in paid if on <= part.due_on)) < r2(owed):
            return False
    return True


def rows_for_owner(db: Session, pid: str) -> list[CustomerRow]:
    """Every customer card of the shop, oldest debt first, with its join text. sms_status is
    NONE until families join by text (A2.2 part 2 adds family_contact)."""
    today = as_of(get_pharmacy(db, pid))
    rows = db.scalars(select(m.PatientDue).where(m.PatientDue.pharmacy_id == pid)
                      .order_by(m.PatientDue.since, m.PatientDue.label))
    return [CustomerRow(code=d.code, label=d.label, amount=r2(d.amount), since=d.since,
                        days_outstanding=(today - d.since).days, status="planned" if d.plan_parts else "no_plan",
                        plan=_plan(d), sms_status="NONE", join=join_text(d.code), trusted=trusted(db, d, today))
            for d in rows]


# For Arifin's jobs (build plan 1.4 B, I1.4): the reminder job and the family SMS.

@dataclass(frozen=True)
class DuePart:
    pharmacy_id: str
    code: str
    n: int
    amount: float
    due_on: date


def find_by_code(db: Session, code: str) -> tuple[str, str] | None:
    """(pharmacy id, label) for a card code in any spelling, or None. Never raises: an SMS
    reply with a wrong code just gets the 'no such code' text."""
    d = db.scalar(select(m.PatientDue).where(m.PatientDue.code == normalize_code(code)))
    return (d.pharmacy_id, d.label) if d else None


def parts_due(db: Session, due_on: date) -> list[DuePart]:
    """Every plan part that falls due on `due_on`, across all shops, by shop then code."""
    rows = db.scalars(select(m.PatientDue).where(m.PatientDue.plan_parts.is_not(None))
                      .order_by(m.PatientDue.pharmacy_id, m.PatientDue.code))
    return [DuePart(d.pharmacy_id, d.code, p.n, p.amount, p.due_on)
            for d in rows if (plan := _plan(d)) for p in plan.schedule if p.due_on == due_on]


def has_part_due(db: Session, pid: str, on: date) -> bool:
    """Does any customer of this shop have a plan part due on or before `on`, still unpaid?
    (Today's "remind" one thing.)"""
    rows = db.scalars(select(m.PatientDue).where(m.PatientDue.pharmacy_id == pid,
                                                 m.PatientDue.plan_parts.is_not(None), m.PatientDue.amount > 0))
    return any(p.due_on <= on for d in rows if (plan := _plan(d)) for p in plan.schedule)
