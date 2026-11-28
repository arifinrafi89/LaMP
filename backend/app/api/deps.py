"""Who is calling (build plan 2.1, D7; task I2.1). Applied at router level in routes.py, so no
route can forget its check.

- Owner routes (/pharmacies/{pid}/*): the signed-in owner (app.auth.deps.current_owner, a
  bearer token). `pid` must be the owner's own shop; any other id answers **404, not 403**,
  so shop ids can't be probed. No token → 401 `session_expired`; a lender key instead → 403.
  The session's events are logged as that shop's (logbus.set_shop), so its History
  (/pharmacies/{pid}/logs*) holds them.
- Lender routes (/lenders/{lid}/*): that lender's X-Lender-Key.
- Dev routes (/dev/*): 404 unless DEV_MODE is on.

This is the only place a route learns its shop: `Caller.pharmacy_id` comes from the
session, never from a body or a default.
"""

from dataclasses import dataclass

from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.auth.deps import CurrentOwner, current_owner
from app.config import settings
from app.db.models import Pharmacy
from app.db.session import get_db
from app.engines import auth, logbus


@dataclass
class Caller:
    role: str          # "owner" or "lender"
    pharmacy_id: str | None = None
    lender_id: str | None = None
    owner_id: str | None = None


def not_found() -> ApiProblem:
    return ApiProblem(404, "not_found", "Not found.")


def signed_in_owner(request: Request, db: Session) -> CurrentOwner:
    """The owner behind the bearer token. A lender's key where a token should be is 403."""
    try:
        return current_owner(request, db)
    except ApiProblem as p:
        if p.status == 401 and auth.lender_for_key(db, request.headers.get("x-lender-key")) is not None:
            raise ApiProblem(403, "invalid", "This page is for the pharmacy owner.") from None
        raise


def require_owner(pid: str, request: Request, db: Session = Depends(get_db)) -> Caller:
    """The owner of this pharmacy. Another shop's id, a deleted shop or none at all: 404."""
    me = signed_in_owner(request, db)
    if me.pharmacy_id is None or me.pharmacy_id != pid:
        raise not_found()
    ph = db.get(Pharmacy, pid)
    if ph is None or ph.deleted_at is not None:
        raise not_found()
    logbus.set_shop(db, pid)
    return Caller("owner", pharmacy_id=pid, owner_id=me.owner_id)


def require_any_owner(request: Request, db: Session = Depends(get_db)) -> Caller:
    """Any signed-in owner (routes with no pharmacy in the path); their shop may be None."""
    me = signed_in_owner(request, db)
    return Caller("owner", pharmacy_id=me.pharmacy_id, owner_id=me.owner_id)


def require_lender(lid: str, db: Session = Depends(get_db),
                   x_lender_key: str | None = Header(default=None)) -> Caller:
    """The lender named in the path, from its key."""
    lender = auth.lender_for_key(db, x_lender_key)
    if lender is None:
        raise HTTPException(401, "Sign in as a lender first.")
    if lender.id != lid:
        raise HTTPException(403, "This belongs to another lender.")
    return Caller("lender", lender_id=lid)


def dev_only() -> None:
    """Demo controls exist only with DEV_MODE=true."""
    if not settings.dev_mode:
        raise HTTPException(404, "Not Found")
