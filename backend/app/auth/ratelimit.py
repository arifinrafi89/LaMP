"""Fixed-window limits kept in the database (build plan 2.1).

    sign-in codes   3 per number per 15 minutes, 10 per number per day, 20 per IP per hour
    code tries      5 per code (counted on the challenge itself, not here)
    demo sign-in    10 a minute per IP

`hit()` counts one try and raises 429 `rate_limited` with `retry_after` once a window is
full. IPs and numbers are stored only as keyed hashes.
"""
import hashlib
import hmac
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import Request
from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.auth.config import get_settings
from app.auth.models import RateCounter


@dataclass(frozen=True)
class Limit:
    name: str
    count: int
    window: timedelta


OTP_PER_NUMBER_15M = Limit("otp:number:15m", 3, timedelta(minutes=15))
OTP_PER_NUMBER_DAY = Limit("otp:number:day", 10, timedelta(days=1))
OTP_PER_IP_HOUR = Limit("otp:ip:hour", 20, timedelta(hours=1))
DEMO_PER_IP_MINUTE = Limit("demo:ip:minute", 10, timedelta(minutes=1))


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _window_start(at: datetime, window: timedelta) -> datetime:
    epoch = datetime(2026, 1, 1)
    n = (at - epoch) // window
    return epoch + n * window


def client_ip(request: Request) -> str:
    """The caller's address. Behind Render's proxy (PROXY_HOPS=1) it is the entry the proxy
    added to X-Forwarded-For, which a caller can't forge; with no proxy, the socket's."""
    hops = get_settings().proxy_hops
    if hops > 0:
        chain = [p.strip() for p in request.headers.get("x-forwarded-for", "").split(",") if p.strip()]
        if len(chain) >= hops:
            return chain[-hops]
    return request.client.host if request.client else "unknown"


def ip_hash(request: Request) -> str:
    pepper = get_settings().secret("phone_pepper").encode()
    return hmac.new(pepper, ("ip:" + client_ip(request)).encode(), hashlib.sha256).hexdigest()[:32]


def hit(db: Session, limit: Limit, subject: str, *, now: datetime | None = None) -> None:
    """Count one try against `limit` for `subject` (a hash); 429 if the window is full."""
    now = now or _now()
    start = _window_start(now, limit.window)
    key = f"{limit.name}:{subject}"
    row = db.get(RateCounter, (key, start))
    if row is None:
        row = RateCounter(key=key, window_start=start, count=0)
        db.add(row)
    if row.count >= limit.count:
        retry = max(1, int((start + limit.window - now).total_seconds()))
        raise ApiProblem(429, "rate_limited", "Too many tries. Wait a little and try again.", retry_after=retry)
    row.count += 1
    db.flush()


def prune(db: Session, *, now: datetime | None = None) -> int:
    """Drop windows that ended more than a day ago (run by the nightly job)."""
    cutoff = (now or _now()) - timedelta(days=2)
    return db.execute(delete(RateCounter).where(RateCounter.window_start < cutoff)).rowcount or 0

