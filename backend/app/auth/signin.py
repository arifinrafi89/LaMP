"""What happens once a code is right, and the demo shop's sign-in (build plan 3.2, D12).

VERIFIED: upsert the owner by the number they typed (its hash), keep Applink's id for them
exactly as returned, mirror the core app's `subscriptionStatus`, and open a device session.
`INITIAL` still signs in; the morning SMS waits for the REGISTERED notification.
"""
import hmac
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.applink import otp, tel
from app.applink.models import Subscriber
from app.auth import crypto, sessions
from app.auth.config import get_settings
from app.auth.models import AuthSession
from app.db.models import Owner, Pharmacy

OWNER_PHONE = "owner.phone"
DEMO_PHONE = "demo"


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def owner_out(owner: Owner) -> dict:
    number = crypto.unseal(owner.phone_enc, purpose=OWNER_PHONE)
    masked = "Demo shop" if number == DEMO_PHONE else tel.mask(number)
    return {"id": owner.id, "phone_masked": masked, "language": owner.language}


def mirror(db: Session, app: str, ref: str, status: str, owner_id: str | None) -> Subscriber:
    """Our copy of one Applink subscription, keyed by (app, the id Applink gave)."""
    now = _now()
    row = db.scalar(select(Subscriber).where(Subscriber.app == app, Subscriber.subscriber_ref == ref))
    if row is None:
        row = Subscriber(app=app, subscriber_ref=ref, status=status, created_at=now, updated_at=now)
        db.add(row)
    row.status, row.updated_at, row.last_confirmed_at = status, now, now
    if owner_id is not None:
        row.owner_id = owner_id
    return row


def owner_for(db: Session, verified: otp.Verified) -> tuple[Owner, bool]:
    ch = verified.challenge
    owner = db.scalar(select(Owner).where(Owner.phone_hash == ch.phone_hash))
    is_new = owner is None
    if owner is None:
        owner = Owner(id=str(uuid.uuid4()), pharmacy_id=None, phone_hash=ch.phone_hash,
                      phone_enc=crypto.seal(otp.phone_of(ch), purpose=OWNER_PHONE),
                      language=ch.language, created_at=_now())
        db.add(owner)
    elif owner.deleted_at is not None:
        # Signing in again within the 7-day undo window keeps the account (plan 13.3).
        owner.deleted_at = None
    owner.subscriber_ref = verified.subscriber_ref
    db.flush()
    mirror(db, "core", verified.subscriber_ref, verified.subscription_status, owner.id)
    return owner, is_new


def signed_in(db: Session, owner: Owner, s: AuthSession, refresh: str, *, is_new: bool) -> dict:
    access, expires_at = sessions.access_for(db, owner, s)
    return {"access_token": access, "expires_at": expires_at, "refresh_token": None if s.web else refresh,
            "owner": owner_out(owner), "pharmacy": sessions.pharmacy_brief(db, owner), "is_new": is_new}


def demo_owner(db: Session, code: str) -> Owner:
    """The owner of the demo shop, for the judges' "Open the demo shop" button."""
    cfg = get_settings()
    if not cfg.demo_enabled:
        raise ApiProblem(404, "not_found", "There is no demo here.")
    expected = cfg.demo_code.get_secret_value()
    if not expected or not hmac.compare_digest(code.strip().upper().encode(), expected.strip().upper().encode()):
        raise ApiProblem(400, "invalid", "That demo code isn't right.")
    shop = db.scalar(select(Pharmacy).where(Pharmacy.kind == "demo", Pharmacy.deleted_at.is_(None))
                     .order_by(Pharmacy.created_at))
    if shop is None:
        raise ApiProblem(404, "not_found", "The demo shop isn't set up yet.")
    digest = crypto.phone_hash(f"demo:{shop.id}")
    owner = db.scalar(select(Owner).where(Owner.phone_hash == digest))
    if owner is None:
        owner = Owner(id=str(uuid.uuid4()), pharmacy_id=shop.id, phone_hash=digest,
                      phone_enc=crypto.seal(DEMO_PHONE, purpose=OWNER_PHONE), language="en", created_at=_now())
        db.add(owner)
        db.flush()
    return owner
