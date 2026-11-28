"""Audit log: every state change, action transition, registry lock and capture.

Events are stored in audit_log; the SSE endpoint streams new rows to the UI.
Tiers: T0 read-only/regulator views, T1 owner and extraction, T2 engines,
T3 lender and financial execution.

The log is a hash chain (win plan CORE-09): each row stores
hash = sha256(prev_hash + canonical(event)), with GENESIS before the first row.
Changing, inserting or deleting any row breaks every hash after it; verify() finds
the first bad row. The head hash, published outside the database, anchors the chain.

Every event belongs to a shop, or to none (system events), and each shop has its own
chain (build plan 4.2; flow step 5): a shop's History lists, exports and verifies only its
own events. The shop is `pharmacy=` in the event, or else the one the request's session
was opened for (`shop(db, pid)`, which require_owner sets for every owner route).
"""

import hashlib
import json
from collections.abc import Generator
from contextlib import contextmanager
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import models as m
from app.schemas import LogEvent, VerifyOut

TIERS = {"T0", "T1", "T2", "T3"}
GENESIS = "0" * 64
SHOP_KEY = "lamp_pharmacy_id"  # in Session.info: the shop this session's events belong to


def set_shop(db: Session, pid: str | None) -> None:
    """From here on, this session's events belong to `pid` (None: system events)."""
    db.info[SHOP_KEY] = pid


@contextmanager
def shop(db: Session, pid: str | None) -> Generator[None]:
    """Events logged inside belong to `pid`; the session's shop is put back after."""
    before = db.info.get(SHOP_KEY)
    set_shop(db, pid)
    try:
        yield
    finally:
        set_shop(db, before)


def shop_of(db: Session, data: dict) -> str | None:
    pid = data.get("pharmacy")
    return pid if isinstance(pid, str) and pid else db.info.get(SHOP_KEY)


def _utc_now() -> datetime:
    """Naive UTC, like every other time we store. An aware time in a `timestamp without time
    zone` column is turned into the database's local time by Postgres, which breaks the hash."""
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def _jsonable(v):
    if isinstance(v, (date, datetime)):
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, dict):
        return {k: _jsonable(x) for k, x in v.items()}
    if isinstance(v, (list, tuple, set)):
        return [_jsonable(x) for x in v]
    return v


def log(tier: str, component: str, event: str, db: Session | None = None, **data) -> None:
    """Record one event. Inside a request, pass `db`: the row is committed with the
    caller's transaction. Without `db` (e.g. from agents/), it is committed at once."""
    if tier not in TIERS:
        raise ValueError(f"Unknown tier {tier!r}")
    row = m.AuditLog(ts=_utc_now(), tier=tier, component=component.upper(),
                     event=event, data=_jsonable(data))
    if db is not None:
        row.pharmacy_id = shop_of(db, data)
        _chain(db, row)
        return
    from app.db.session import SessionLocal

    with SessionLocal() as own:
        row.pharmacy_id = shop_of(own, data)
        _chain(own, row)
        own.commit()


def notify(audience: str, title: str, body: str, link: str | None = None, db: Session | None = None) -> None:
    """A notification for the owner's or the admin's screen (win plan CORE-06). It travels
    on the log stream as component NOTIFY, event "notify". The caller builds the text from
    engine numbers; a notification never approves anything."""
    log("T1", "NOTIFY", "notify", db, audience=audience, title=title, body=body, link=link)


def canonical(ts: datetime, tier: str, component: str, event: str, data: dict) -> str:
    """The exact text that is hashed: compact JSON with sorted keys and a UTC timestamp."""
    ts = ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
    return json.dumps({"ts": ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "tier": tier,
                       "component": component, "event": event, "data": data},
                      sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def link(prev_hash: str, text: str) -> str:
    return hashlib.sha256((prev_hash + text).encode("utf-8")).hexdigest()


def _same_shop(pid: str | None):
    return m.AuditLog.pharmacy_id.is_(None) if pid is None else m.AuditLog.pharmacy_id == pid


def _chain(db: Session, row: m.AuditLog) -> None:
    """Link the row to the last event of the same shop (or of the system chain)."""
    last = db.scalar(select(m.AuditLog.hash).where(_same_shop(row.pharmacy_id))
                     .order_by(m.AuditLog.id.desc()).limit(1))
    row.prev_hash = last or GENESIS
    row.hash = link(row.prev_hash, canonical(row.ts, row.tier, row.component, row.event, row.data))
    db.add(row)
    db.flush()


def verify(db: Session, pid: str | None) -> VerifyOut:
    """Recompute one shop's chain (None: the system chain) from GENESIS. first_bad_id is the
    first row that doesn't match."""
    prev, count = GENESIS, 0
    for row in db.scalars(select(m.AuditLog).where(_same_shop(pid)).order_by(m.AuditLog.id)):
        count += 1
        expect = link(prev, canonical(row.ts, row.tier, row.component, row.event, row.data or {}))
        if row.prev_hash != prev or row.hash != expect:
            return VerifyOut(intact=False, count=count, head_hash=None, first_bad_id=f"lg-{row.id}")
        prev = row.hash
    return VerifyOut(intact=True, count=count, head_hash=None if count == 0 else prev)


def as_record(row_event: LogEvent, prev_hash: str) -> dict:
    """One line of the verifiable JSONL trace."""
    return {"id": row_event.id, "ts": row_event.ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "tier": row_event.tier, "component": row_event.component, "event": row_event.event,
            "data": row_event.data, "prev_hash": prev_hash, "hash": row_event.hash}


def to_event(row: m.AuditLog) -> LogEvent:
    """Audit-log row to LogEvent. Naive timestamps are treated as UTC."""
    ts = row.ts if row.ts.tzinfo else row.ts.replace(tzinfo=timezone.utc)
    return LogEvent(id=f"lg-{row.id}", ts=ts, tier=row.tier, component=row.component, event=row.event,
                    data=row.data or {}, hash=row.hash or None)


def events(db: Session, pid: str | None, since: str | None = None, after_id: int = 0) -> list[LogEvent]:
    """One shop's events in order (None: the system's). `since` is a log id ("lg-12") or an
    ISO timestamp."""
    q = select(m.AuditLog).where(_same_shop(pid)).order_by(m.AuditLog.id)
    if since and since.startswith("lg-") and since[3:].isdigit():
        after_id = max(after_id, int(since[3:]))
    elif since:
        q = q.where(m.AuditLog.ts > datetime.fromisoformat(since.replace("Z", "+00:00")).replace(tzinfo=None))
    if after_id:
        q = q.where(m.AuditLog.id > after_id)
    return [to_event(r) for r in db.scalars(q)]


def _value(v) -> str:
    if isinstance(v, list):
        return ",".join(_value(x) for x in v)
    if isinstance(v, str) and len(v) == 64 and all(c in "0123456789abcdef" for c in v):
        return v[:12] + "…"  # commitments are long hex strings
    return str(v)


def as_text(e: LogEvent) -> str:
    """`[2026-10-16T14:05:00Z] [T3:REGISTRY] lock_acquired commitment=8f9c… application=APP-0001`"""
    ts = e.ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    fields = " ".join(f"{k}={_value(v)}" for k, v in e.data.items())
    line = f"[{ts}] [{e.tier}:{e.component}] {e.event}" + (f" {fields}" if fields else "")
    return line + (f" #{e.hash[:12]}" if e.hash else "")
