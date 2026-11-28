"""Job kinds and queuing (build plan 1.4 C; task A1.3).

    @job("export.build", max_attempts=3)
    def build_export(db, payload): ...

    enqueue(db, "export.build", {"export_id": "..."}, run_at=None, dedupe_key=None)

A handler gets the runner's session as well as the payload (1.4 C sketches only the
payload), so its work and the job's "done" commit together: a job that fails changes nothing.
"""
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .models import Job

HandlerFn = Callable[[Session, dict], None]


@dataclass(frozen=True)
class Handler:
    kind: str
    fn: HandlerFn
    max_attempts: int


HANDLERS: dict[str, Handler] = {}


def job(kind: str, max_attempts: int = 3) -> Callable[[HandlerFn], HandlerFn]:
    """Register `fn(db, payload)` as the handler for `kind`."""
    if max_attempts < 1:
        raise ValueError("max_attempts must be at least 1")

    def register(fn: HandlerFn) -> HandlerFn:
        if kind in HANDLERS and HANDLERS[kind].fn is not fn:
            raise ValueError(f"Job kind {kind!r} already has a handler")
        HANDLERS[kind] = Handler(kind, fn, max_attempts)
        return fn

    return register


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def enqueue_new(db: Session, kind: str, payload: dict | None = None, run_at: datetime | None = None,
                dedupe_key: str | None = None) -> tuple[Job, bool]:
    """Like `enqueue`, and also whether a new row was made (False: the dedupe key was taken)."""
    if kind not in HANDLERS:
        raise ValueError(f"No handler for job kind {kind!r}")
    if dedupe_key is not None:
        existing = db.scalar(select(Job).where(Job.dedupe_key == dedupe_key))
        if existing is not None:
            return existing, False
    row = Job(kind=kind, payload=dict(payload or {}), run_at=run_at or utcnow(), dedupe_key=dedupe_key,
              status="queued", attempts=0)
    try:
        with db.begin_nested():  # another worker may queue the same key at the same moment
            db.add(row)
            db.flush()
    except IntegrityError:
        return db.scalar(select(Job).where(Job.dedupe_key == dedupe_key)), False
    return row, True


def enqueue(db: Session, kind: str, payload: dict | None = None, run_at: datetime | None = None,
            dedupe_key: str | None = None) -> Job:
    """Queue `kind` to run at `run_at` (UTC; now by default). With a dedupe key that is
    already queued or done, nothing new is queued and that job is returned."""
    return enqueue_new(db, kind, payload, run_at, dedupe_key)[0]
