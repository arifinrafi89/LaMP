"""Shared helpers for the engines.

Every date is relative to the pharmacy's "today" (`as_of`), which is (build plan 0.6, I1.2):
1. the date set with `on_date(...)`, if any (tests, and replaying a past day);
2. settings.as_of_date, for demo and team-test shops only;
3. otherwise today's date in Asia/Dhaka.
"""

from collections.abc import Generator
from contextlib import contextmanager
from contextvars import ContextVar
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import models as m


def get_pharmacy(db: Session, pid: str) -> m.Pharmacy:
    """The pharmacy row, or HTTP 404 if the id is unknown."""
    ph = db.get(m.Pharmacy, pid)
    if ph is None:
        raise HTTPException(404, "That pharmacy wasn't found.")
    return ph


DHAKA = ZoneInfo("Asia/Dhaka")
_on_date: ContextVar[date | None] = ContextVar("lamp_on_date", default=None)


def dhaka_today() -> date:
    """Today's date in Bangladesh."""
    return datetime.now(DHAKA).date()


@contextmanager
def on_date(day: date) -> Generator[None]:
    """Run the engines as if today were `day`, for every pharmacy:
    `with on_date(date(2026, 10, 16)): get_forecast(db, pid)`."""
    token = _on_date.set(day)
    try:
        yield
    finally:
        _on_date.reset(token)


def as_of(ph: m.Pharmacy) -> date:
    """The pharmacy's "today": an `on_date` override, else a demo or team-test shop's
    settings.as_of_date, else today in Dhaka."""
    if (override := _on_date.get()) is not None:
        return override
    fixed = (ph.settings or {}).get("as_of_date")
    if fixed and (ph.kind or "real") in m.FIXED_DATE_KINDS:
        return date.fromisoformat(fixed)
    return dhaka_today()


def margin(ph: m.Pharmacy) -> float:
    """Gross margin as a fraction: settings.gross_margin_pct / 100 (12% in the seed)."""
    return ph.settings["gross_margin_pct"] / 100


def r2(x: float) -> float:
    """Round to 2 decimals for money. Adding 0.0 turns -0.0 into 0.0."""
    return round(x + 0.0, 2)


def sales_days(db: Session, pid: str, today: date, period_days: int) -> list[m.SalesDay]:
    """Sales-book rows for the `period_days` days before today (today excluded)."""
    start = today - timedelta(days=period_days)
    return list(db.scalars(select(m.SalesDay).where(
        m.SalesDay.pharmacy_id == pid, m.SalesDay.date >= start, m.SalesDay.date < today)))


def invoices_since(db: Session, pid: str, start: date, end: date) -> list[m.Invoice]:
    """Invoices with start <= invoice_date <= end."""
    return list(db.scalars(select(m.Invoice).where(
        m.Invoice.pharmacy_id == pid, m.Invoice.invoice_date >= start, m.Invoice.invoice_date <= end)))
