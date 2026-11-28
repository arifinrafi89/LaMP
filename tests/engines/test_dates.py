"""The pharmacy's "today" (build plan 0.6, I1.2) and the demo shop shifted by whole weeks (9.2)."""

import json
import re
from datetime import date, datetime, timedelta, timezone

from typing import Any

import pytest
import time_machine
from pydantic import TypeAdapter
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import models as m
from app.db.seed import SEED_AS_OF, load_seed, shift_dates, weeks_towards
from app.engines import (
    as_of, dhaka_today, get_accounts, get_alerts, get_dues, get_expiry, get_forecast, get_funding_plan,
    get_passport, get_trim, on_date,
)

PID = "green-life"


def _real_shop() -> m.Pharmacy:
    return m.Pharmacy(id="r", name="R", city="Bogura", kind="real", settings={"gross_margin_pct": 12})


def test_demo_shop_keeps_its_fixed_date(db):
    assert as_of(db.get(m.Pharmacy, PID)) == SEED_AS_OF


def test_real_shop_uses_todays_dhaka_date():
    with time_machine.travel(datetime(2026, 11, 26, 8, 0, tzinfo=timezone.utc), tick=False):
        assert dhaka_today() == date(2026, 11, 26)
        assert as_of(_real_shop()) == date(2026, 11, 26)


def test_dhaka_date_not_the_server_date():
    # 19:30 UTC on the 26th is already 01:30 on the 27th in Dhaka (UTC+6).
    with time_machine.travel(datetime(2026, 11, 26, 19, 30, tzinfo=timezone.utc), tick=False):
        assert dhaka_today() == date(2026, 11, 27)


def test_on_date_overrides_every_shop(db):
    with on_date(date(2026, 10, 9)):
        assert as_of(db.get(m.Pharmacy, PID)) == date(2026, 10, 9)
        assert as_of(_real_shop()) == date(2026, 10, 9)
    assert as_of(db.get(m.Pharmacy, PID)) == SEED_AS_OF


def test_weeks_towards():
    assert weeks_towards(date(2026, 10, 16)) == 0
    assert weeks_towards(date(2026, 10, 22)) == 0
    assert weeks_towards(date(2026, 11, 26)) == 5   # 41 days


def _figures(db) -> dict:
    """Everything the golden test checks, as JSON."""
    out = {}
    for name, fn in (("accounts", get_accounts), ("forecast", get_forecast), ("dues", get_dues),
                     ("alerts", get_alerts), ("expiry", get_expiry),
                     ("trim", lambda d, p: get_trim(d, p, "o-1")),
                     ("passport", get_passport), ("funding", get_funding_plan)):
        out[name] = json.loads(TypeAdapter(Any).dump_json(fn(db, PID)))
    return out


_DAY_MONTH = re.compile(r"\b(\d{2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b")
_TIMESTAMP = re.compile(r"\b(\d{4}-\d{2}-\d{2})T")


def _shift_text(figures: dict, days: int) -> dict:
    """Also move the dates written into sentences ("due 26 Oct") and the alert timestamps."""
    def day_month(mt: re.Match) -> str:
        d = datetime.strptime(f"{mt[1]} {mt[2]} {SEED_AS_OF.year}", "%d %b %Y").date() + timedelta(days=days)
        return d.strftime("%d %b")

    def stamp(mt: re.Match) -> str:
        return (date.fromisoformat(mt[1]) + timedelta(days=days)).isoformat() + "T"

    text = _TIMESTAMP.sub(stamp, _DAY_MONTH.sub(day_month, json.dumps(shift_dates(figures, days))))
    return json.loads(text)


@pytest.mark.parametrize("weeks", [5, 6, -3, 17, 52])
def test_golden_numbers_hold_when_shifted_by_whole_weeks(db, weeks):
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    with sessionmaker(bind=engine, expire_on_commit=False)() as shifted:
        load_seed(shifted, with_demo_captures=True, shift_weeks=weeks)
        assert as_of(shifted.get(m.Pharmacy, PID)) == SEED_AS_OF + timedelta(weeks=weeks)
        assert _figures(shifted) == _shift_text(_figures(db), 7 * weeks)
