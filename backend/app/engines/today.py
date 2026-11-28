"""The Today screen in one call (build plan 2.2 GET /today, 5.2; task I2.2).

The figures are the morning brief's (brief.daily_brief), the stock expiring in 60 days and the
alerts. The "one thing" is the next thing to do (plan 5.2), the first that applies of:
  setup    setup isn't finished (each first-day step can be skipped)
  approve  a step is waiting for the owner's approval (the oldest one)
  remind   a customer's plan part is due today or overdue
  scan     fewer than 3 supplier bills ("Scan your last 3 supplier bills", first day step 6)
  none     nothing to do
"""

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import models as m
from app.schemas.product import Expiring, NextProblem, OneThing, TodayOut

from . import patients
from .alerts import get_alerts
from .brief import daily_brief
from .common import as_of, get_pharmacy, r2
from .expiry import get_expiry

BILLS_TO_SCAN = 3


def _one_thing(db: Session, ph: m.Pharmacy, on) -> OneThing:
    def thing(kind: str, action_id: str | None = None) -> OneThing:
        return OneThing(kind=kind, action_id=action_id, title_key=f"today.one_thing.{kind}")

    if not ph.setup_complete:
        return thing("setup")
    waiting = db.scalar(select(m.Action.id).where(m.Action.pharmacy_id == ph.id, m.Action.status == "proposed")
                        .order_by(m.Action.created_at, m.Action.id))
    if waiting:
        return thing("approve", waiting)
    if patients.has_part_due(db, ph.id, on):
        return thing("remind")
    bills = db.scalar(select(func.count()).select_from(m.Invoice).where(m.Invoice.pharmacy_id == ph.id)) or 0
    if bills < BILLS_TO_SCAN:
        return thing("scan")
    return thing("none")


def get_today(db: Session, pid: str) -> TodayOut:
    ph = get_pharmacy(db, pid)
    on = as_of(ph)
    brief = daily_brief(db, pid, on)
    expiry = get_expiry(db, pid, 60)
    short = brief.shortfall
    return TodayOut(
        as_of=on,
        cash_now=brief.cash_now,
        next_problem=NextProblem(kind="shortfall", date=short.date, amount=short.amount, text_key="today.short_on")
        if short else None,
        expiring_60d=Expiring(value=r2(expiry.at_risk_value), return_eligible=r2(expiry.return_eligible_value)),
        approvals_waiting=brief.approvals_waiting,
        one_thing=_one_thing(db, ph, on),
        alerts=get_alerts(db, pid),
    )
