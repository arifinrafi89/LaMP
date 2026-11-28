"""Device sessions: create, refresh with rotation, list, end (build plan 2.1, 3.2).

A returning owner makes no Applink call: the refresh token keeps them signed in for 30
days of use. Reusing an old refresh token ends the whole session (someone copied it).
"""
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.applink.codes import ACTIVE_STATUSES
from app.applink.models import Subscriber
from app.auth import tokens
from app.auth.config import get_settings
from app.auth.models import AuthSession
from app.db.models import Owner, Pharmacy


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def expired() -> ApiProblem:
    return ApiProblem(401, "session_expired", "Your session has ended. Sign in again.")


def create(db: Session, owner: Owner, device: dict, *, now: datetime | None = None) -> tuple[AuthSession, str]:
    """A new session for this device, and its first refresh token. Signing in again on the
    same device replaces that device's old session."""
    now = now or _now()
    for old in db.scalars(select(AuthSession).where(AuthSession.owner_id == owner.id,
                                                    AuthSession.device_id == device["id"],
                                                    AuthSession.revoked_at.is_(None))):
        old.revoked_at, old.revoked_reason = now, "replaced"
    sid = str(uuid.uuid4())
    token, digest = tokens.new_refresh(sid)
    s = AuthSession(id=sid, owner_id=owner.id, device_id=device["id"][:64], device_name=device["name"][:60],
                    device_os=device["os"][:30], app_version=device["app_version"][:30],
                    web=device["os"].strip().lower() == "web", refresh_hash=digest, rotations=0,
                    created_at=now, last_used_at=now, expires_at=now + timedelta(days=get_settings().refresh_days))
    db.add(s)
    db.flush()
    return s, token


def rotate(db: Session, refresh_token: str | None, *, now: datetime | None = None) -> tuple[AuthSession, str]:
    """Swap a refresh token for a new one. 401 `session_expired` if it isn't the current one;
    an old one ends the session for good."""
    now = now or _now()
    parts = tokens.split_refresh(refresh_token)
    if parts is None:
        raise expired()
    sid, secret = parts
    s = db.get(AuthSession, sid)
    if s is None or s.revoked_at is not None or s.expires_at <= now:
        raise expired()
    if not tokens.same(tokens.refresh_hash(secret), s.refresh_hash):
        s.revoked_at, s.revoked_reason = now, "reuse"
        db.commit()  # the session ends even though this request fails
        raise expired()
    owner = db.get(Owner, s.owner_id)
    if owner is None or owner.deleted_at is not None:
        raise expired()
    token, digest = tokens.new_refresh(sid)
    s.refresh_hash, s.rotations = digest, s.rotations + 1
    s.last_used_at, s.expires_at = now, now + timedelta(days=get_settings().refresh_days)
    db.flush()
    return s, token


def active(db: Session, session_id: str, *, now: datetime | None = None) -> AuthSession | None:
    s = db.get(AuthSession, session_id)
    if s is None or s.revoked_at is not None or s.expires_at <= (now or _now()):
        return None
    return s


def end(db: Session, s: AuthSession, reason: str, *, now: datetime | None = None) -> None:
    if s.revoked_at is None:
        s.revoked_at, s.revoked_reason = now or _now(), reason


def end_all(db: Session, owner_id: str, reason: str) -> int:
    """Every session of this owner (account deletion)."""
    n = 0
    for s in db.scalars(select(AuthSession).where(AuthSession.owner_id == owner_id, AuthSession.revoked_at.is_(None))):
        end(db, s, reason)
        n += 1
    return n


def devices(db: Session, owner_id: str, *, now: datetime | None = None) -> list[AuthSession]:
    now = now or _now()
    return list(db.scalars(select(AuthSession).where(AuthSession.owner_id == owner_id,
                                                     AuthSession.revoked_at.is_(None),
                                                     AuthSession.expires_at > now)
                           .order_by(AuthSession.last_used_at.desc())))


def plan_of(db: Session, owner: Owner) -> str:
    """"plus" while the owner's LaMP Plus mirror is REGISTERED or TRIAL, else "free"."""
    status = db.scalar(select(Subscriber.status).where(Subscriber.app == "plus", Subscriber.owner_id == owner.id)
                       .order_by(Subscriber.updated_at.desc()))
    return "plus" if status in ACTIVE_STATUSES else "free"


def access_for(db: Session, owner: Owner, s: AuthSession) -> tuple[str, datetime]:
    return tokens.issue_access(owner.id, owner.pharmacy_id, s.id, plan_of(db, owner))


def pharmacy_brief(db: Session, owner: Owner) -> dict | None:
    ph = db.get(Pharmacy, owner.pharmacy_id) if owner.pharmacy_id else None
    if ph is None or ph.deleted_at is not None:
        return None
    return {"id": ph.id, "name": ph.name, "setup_complete": bool(ph.setup_complete)}
