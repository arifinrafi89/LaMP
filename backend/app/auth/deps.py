"""Who is calling: `current_owner`, from the access token (build plan 2.1, I2.1 builds on it).

The token is checked against its session row on every request, so a signed-out or removed
device stops at once. Any failure is 401 `session_expired`; the app then refreshes once.
"""
from dataclasses import dataclass

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from app.auth import sessions, tokens
from app.auth.models import AuthSession
from app.db.models import Owner
from app.db.session import get_db


@dataclass
class CurrentOwner:
    owner: Owner
    session: AuthSession

    @property
    def owner_id(self) -> str:
        return self.owner.id

    @property
    def pharmacy_id(self) -> str | None:
        """Read from the database, not the token, so a shop set up a minute ago counts."""
        return self.owner.pharmacy_id


def bearer(request: Request) -> str | None:
    value = request.headers.get("authorization", "")
    scheme, _, token = value.partition(" ")
    if scheme.lower() != "bearer":
        return None
    return token.strip() or None


def current_owner(request: Request, db: Session = Depends(get_db)) -> CurrentOwner:
    token = bearer(request)
    claims = tokens.read_access(token) if token else None
    if claims is None:
        raise sessions.expired()
    s = sessions.active(db, claims.session_id)
    if s is None or s.owner_id != claims.owner_id:
        raise sessions.expired()
    owner = db.get(Owner, s.owner_id)
    if owner is None or owner.deleted_at is not None:
        raise sessions.expired()
    return CurrentOwner(owner=owner, session=s)
