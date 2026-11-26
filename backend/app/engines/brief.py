"""The figures behind the 8 AM SMS and the Today screen (build plan 1.4 B, I1.4).

Pure functions: no Applink in here. Arifin's morning job calls `pharmacies_for_brief` and then
`daily_brief` for each shop, and owns the wording and the sending.
"""

from dataclasses import dataclass
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import models as m

from .common import get_pharmacy, on_date, r2
from .expiry import get_expiry
from .forecast import get_forecast


@dataclass(frozen=True)
class Shortfall:
    date: date
    amount: float


@dataclass(frozen=True)
class BriefFigures:
    pharmacy_id: str
    on_date: date
    cash_now: float
    shortfall: Shortfall | None       # the first day cash runs short in the next 30 days
    expiring_this_week: float         # stock value that expires within 7 days
    approvals_waiting: int


def daily_brief(db: Session, pid: str, on: date) -> BriefFigures:
    """The shop's figures as of the morning of `on`. Amounts in BDT, rounded to 2 decimals."""
    get_pharmacy(db, pid)
    with on_date(on):
        fc = get_forecast(db, pid)
        week = get_expiry(db, pid, horizon_days=7)
    first = fc.shortfalls[0] if fc.shortfalls else None
    waiting = db.scalar(select(func.count()).select_from(m.Action).where(
        m.Action.pharmacy_id == pid, m.Action.status == "proposed")) or 0
    return BriefFigures(pharmacy_id=pid, on_date=on, cash_now=r2(fc.start_cash),
                        shortfall=Shortfall(first.date, r2(first.amount)) if first else None,
                        expiring_this_week=r2(week.at_risk_value), approvals_waiting=waiting)


def pharmacies_for_brief(db: Session) -> list[str]:
    """Real shops that finished setup and haven't been deleted. Demo and team-test shops are
    left out: their SMS go to the mock."""
    return list(db.scalars(select(m.Pharmacy.id).where(
        m.Pharmacy.kind == "real", m.Pharmacy.setup_complete.is_(True), m.Pharmacy.deleted_at.is_(None))
        .order_by(m.Pharmacy.id)))
