"""The job loop inside the web service (build plan D6; task A1.3). main.py starts and stops it.

Every JOBS_POLL_SECONDS it queues the day's scheduled jobs (scheduler.tick), then claims due
jobs with FOR UPDATE SKIP LOCKED, so two workers never run one job, and runs each in its own
transaction. A failed job is retried with backoff (1, 4, 16 … minutes) up to its kind's
max_attempts, then marked failed. A job left `running` by a worker that died is put back after
10 minutes. Each pass is a heartbeat; /ready reports the loop down once it is 2 minutes old.

A handler that logs for a shop calls `logbus.set_shop(db, pid)` first (flow step 5).
"""
import asyncio
import contextlib
import os
import socket
from collections.abc import Callable
from datetime import datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.engines import logbus

from . import scheduler
from .config import get_settings
from .models import Job
from .registry import HANDLERS, utcnow

WORKER = f"{socket.gethostname()}:{os.getpid()}"
STALE_AFTER = timedelta(minutes=10)
HEARTBEAT_MAX_AGE = timedelta(minutes=2)
BATCH = 20

SessionFactory = Callable[[], Session]

_task: asyncio.Task | None = None
_last_beat: datetime | None = None


def backoff(attempts: int) -> timedelta:
    """1, 4, 16 … minutes after the 1st, 2nd, 3rd … failed try."""
    return timedelta(minutes=4 ** max(0, attempts - 1))


def claim(db: Session, now: datetime, limit: int = BATCH, worker: str = WORKER) -> list[int]:
    """Mark up to `limit` due jobs running for this worker and return their ids."""
    db.execute(update(Job).where(Job.status == "running", Job.locked_at < now - STALE_AFTER)
               .values(status="queued", locked_by=None, locked_at=None))
    rows = list(db.scalars(select(Job).where(Job.status == "queued", Job.run_at <= now)
                           .order_by(Job.run_at, Job.id).limit(limit).with_for_update(skip_locked=True)))
    for j in rows:
        j.status, j.locked_by, j.locked_at, j.attempts = "running", worker, now, j.attempts + 1
    db.commit()
    return [j.id for j in rows]


def run_one(factory: SessionFactory, job_id: int, now: datetime) -> bool:
    """Run one claimed job; True if it succeeded."""
    with factory() as db:
        j = db.get(Job, job_id)
        handler = HANDLERS.get(j.kind)
        try:
            if handler is None:
                raise LookupError(f"no handler for {j.kind}")
            handler.fn(db, dict(j.payload or {}))
            j.status, j.locked_by, j.locked_at, j.last_error = "done", None, None, None
            db.commit()
            return True
        except Exception as exc:  # the job's own work is rolled back; the job row records the failure
            db.rollback()
            logbus.set_shop(db, None)
            j = db.get(Job, job_id)
            j.last_error = type(exc).__name__  # never the message: it may hold a number or a name
            final = j.attempts >= (handler.max_attempts if handler else 1)
            j.status = "failed" if final else "queued"
            if not final:
                j.run_at = now + backoff(j.attempts)
            j.locked_by = j.locked_at = None
            logbus.log("T0", "JOBS", "job_failed" if final else "job_retry", db, job=j.id, kind=j.kind,
                       attempts=j.attempts, error=j.last_error)
            db.commit()
            return False


def run_due(factory: SessionFactory, now: datetime | None = None, limit: int = BATCH) -> int:
    """Run every due job, a batch at a time; returns how many ran."""
    now = now or utcnow()
    ran = 0
    while True:
        with factory() as db:
            ids = claim(db, now, limit)
        for job_id in ids:
            run_one(factory, job_id, now)
        ran += len(ids)
        if len(ids) < limit:
            return ran


def beat(at: datetime | None = None) -> None:
    global _last_beat
    _last_beat = at or utcnow()


def healthy(now: datetime | None = None) -> bool:
    """Has the loop made a pass in the last 2 minutes?"""
    return _last_beat is not None and (now or utcnow()) - _last_beat < HEARTBEAT_MAX_AGE


def cycle(factory: SessionFactory, now: datetime | None = None) -> int:
    """One pass: queue the day's scheduled jobs, run what is due, beat."""
    now = now or utcnow()
    with factory() as db:
        scheduler.tick(db, now)
        db.commit()
    ran = run_due(factory, now)
    beat(now)
    return ran


async def _loop(factory: SessionFactory, every: float) -> None:
    while True:
        try:
            await asyncio.to_thread(cycle, factory)
        except Exception as exc:  # keep the loop alive; a stale heartbeat shows on /ready
            from app.engines import mailer

            mailer.alert("jobs_loop", "[LaMP] The job loop hit an error", f"{type(exc).__name__} in one pass.")
        await asyncio.sleep(every)


async def start(factory: SessionFactory | None = None) -> None:
    """Start the job loop (unless JOBS_LOOP is off). Safe to call more than once."""
    global _task
    cfg = get_settings()
    if not cfg.jobs_loop or (_task is not None and not _task.done()):
        return
    if factory is None:
        from app.db.session import SessionLocal

        factory = SessionLocal
    _task = asyncio.create_task(_loop(factory, cfg.jobs_poll_seconds))


async def stop() -> None:
    """Stop the job loop. Safe to call more than once."""
    global _task
    if _task is not None:
        _task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await _task
        _task = None
