"""Access and refresh tokens (build plan 2.1).

- Access: a 15-minute JWT (HS256, JWT_SECRET) with `sub` = owner id, `pid`, `sid` = session
  id and `plan`. It is checked against the session row on every request, so signing out or
  removing a device ends it at once, not 15 minutes later.
- Refresh: "<session id>.<random>", opaque to the app, rotated on every use. Only the
  random part's sha256 is stored (auth_session.refresh_hash).
"""
import hashlib
import hmac
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import jwt

from app.auth.config import get_settings

ISSUER = "lamp"
ALGORITHM = "HS256"


@dataclass(frozen=True)
class AccessClaims:
    owner_id: str
    pharmacy_id: str | None
    session_id: str
    plan: str
    expires_at: datetime


def issue_access(owner_id: str, pharmacy_id: str | None, session_id: str, plan: str,
                 *, now: datetime | None = None) -> tuple[str, datetime]:
    now = now or datetime.now(timezone.utc)
    exp = now + timedelta(minutes=get_settings().access_minutes)
    claims = {"iss": ISSUER, "typ": "access", "sub": owner_id, "pid": pharmacy_id, "sid": session_id,
              "plan": plan, "iat": int(now.timestamp()), "exp": int(exp.timestamp())}
    return jwt.encode(claims, get_settings().secret("jwt_secret"), algorithm=ALGORITHM), exp.replace(microsecond=0)


def read_access(token: str) -> AccessClaims | None:
    """The claims of a valid, unexpired access token; None for anything else."""
    try:
        c = jwt.decode(token, get_settings().secret("jwt_secret"), algorithms=[ALGORITHM], issuer=ISSUER,
                       options={"require": ["exp", "iat", "sub", "sid"]})
    except jwt.PyJWTError:
        return None
    if c.get("typ") != "access":
        return None
    return AccessClaims(owner_id=c["sub"], pharmacy_id=c.get("pid"), session_id=c["sid"],
                        plan=c.get("plan", "free"), expires_at=datetime.fromtimestamp(c["exp"], timezone.utc))


def new_refresh(session_id: str) -> tuple[str, str]:
    """A new refresh token for the session, and the hash to store."""
    secret = secrets.token_urlsafe(32)
    return f"{session_id}.{secret}", refresh_hash(secret)


def refresh_hash(secret: str) -> str:
    return hashlib.sha256(secret.encode()).hexdigest()


def split_refresh(token: str | None) -> tuple[str, str] | None:
    """(session id, secret) from a refresh token, or None if it isn't shaped like one."""
    if not token or token.count(".") != 1:
        return None
    sid, secret = token.split(".")
    if not sid or len(secret) < 20:
        return None
    return sid, secret


def same(a: str, b: str) -> bool:
    return hmac.compare_digest(a, b)
