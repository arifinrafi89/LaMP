"""Daily jobs at a Dhaka time (build plan D6, 1.4 C; task A1.3). A3.3 adds the jobs
themselves (the 8 AM brief, reminders at 10:00, the nightly reconcile, the demo reseed).

    daily("brief.morning", "08:00")

`tick(db, now)` queues each daily job whose time has come today in Asia/Dhaka, once per
day (dedupe key "<kind>:<date>"). The loop calls it every few seconds and the GitHub Actions
tick calls it as a backstop: a job missed while the service slept still runs that day.
"""
from dataclasses import dataclass
from datetime import datetime, time, timezone

from sqlalchemy.orm import Session

from app.engines.common import DHAKA

from .registry import enqueue_new


@dataclass(frozen=True)
class Daily:
    kind: str
    at: time  # Asia/Dhaka


SCHEDULE: list[Daily] = []


def daily(kind: str, at: str) -> Daily:
    """Run `kind` every day at `at` ("HH:MM", Dhaka time)."""
    entry = Daily(kind, time.fromisoformat(at))
    if any(d.kind == kind for d in SCHEDULE):
        raise ValueError(f"{kind!r} is already scheduled")
    SCHEDULE.append(entry)
    return entry


def tick(db: Session, now: datetime) -> int:
    """Queue today's daily jobs that are due; returns how many were newly queued. `now` is UTC
    (naive or aware)."""
    utc = now if now.tzinfo else now.replace(tzinfo=timezone.utc)
    local = utc.astimezone(DHAKA)
    queued = 0
    for d in SCHEDULE:
        if local.time() >= d.at:
            day = local.date().isoformat()
            _, new = enqueue_new(db, d.kind, {"on": day}, run_at=utc.replace(tzinfo=None),
                                 dedupe_key=f"{d.kind}:{day}")
            queued += new
    return queued
