"""The signed-in owner: GET and PATCH /me, and creating their shop (build plan 2.2; task I2.2).

These routes have no shop in the path, so they take the owner from the bearer token
(`signed_in_owner`); the owner may have no shop yet.
"""

from datetime import datetime, time

from fastapi import APIRouter, Depends, Request
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.applink.config import get_settings as applink_settings
from app.applink.models import Subscriber
from app.auth import consents, sessions, signin
from app.auth.deps import CurrentOwner
from app.db.models import Capture, Owner, Pharmacy
from app.db.session import get_db
from app.engines import dhaka_today, shops
from app.schemas import PharmacyOut
from app.schemas.product import Entitlements, MeOut, MePatch, PharmacyCreate

from .deps import signed_in_owner
from .shop import pharmacy_out

router = APIRouter()

# The free plan's scans a month (build plan 2.2, captures; D1). I2.3 enforces it at capture time.
FREE_SCANS_PER_MONTH = 10

# The Plus mirror's Applink status, as the app shows it (build plan 3.3). OTP_SENT comes with A3.2.
_PLUS_STATUS = {"REGISTERED": "ACTIVE", "TRIAL": "ACTIVE", "REG_PENDING": "PENDING", "INITIAL": "PENDING",
                "TEMPORARY_BLOCKED": "BLOCKED", "UNREGISTERED": "STOPPED"}


def me_owner(request: Request, db: Session = Depends(get_db)) -> CurrentOwner:
    return signed_in_owner(request, db)


def plus_status(db: Session, owner: Owner) -> str:
    status = db.scalar(select(Subscriber.status).where(Subscriber.app == "plus", Subscriber.owner_id == owner.id)
                       .order_by(Subscriber.updated_at.desc()))
    return _PLUS_STATUS.get(status, "NONE") if status else "NONE"


def scans_this_month(db: Session, pid: str) -> int:
    start = datetime.combine(dhaka_today().replace(day=1), time.min)
    return db.scalar(select(func.count()).select_from(Capture).where(
        Capture.pharmacy_id == pid, Capture.created_at >= start)) or 0


def entitlements(db: Session, owner: Owner, plan: str) -> Entitlements:
    """Cash, Plan, Approvals and Ask are Plus screens; scans are 10 a month on the free plan."""
    plus = plan == "plus"
    if plus:
        left = None
    elif owner.pharmacy_id is None:
        left = FREE_SCANS_PER_MONTH
    else:
        left = max(0, FREE_SCANS_PER_MONTH - scans_this_month(db, owner.pharmacy_id))
    return Entitlements(cash=plus, plan=plus, approvals=plus, ask=plus, scans_left=left)


def me_out(db: Session, owner: Owner) -> MeOut:
    plan = sessions.plan_of(db, owner)
    ph = db.get(Pharmacy, owner.pharmacy_id) if owner.pharmacy_id else None
    return MeOut(
        owner=signin.owner_out(owner),
        pharmacy=sessions.pharmacy_brief(db, owner),
        plan=plan,
        plus_status=plus_status(db, owner),
        entitlements=entitlements(db, owner, plan),
        demo_tools=ph is not None and ph.kind in ("demo", "team_test"),
        family_join_routes=sorted(applink_settings().join_routes),
        consents_needed=consents.needed(db, owner.id),
    )


@router.get("/me", response_model=MeOut)
def get_me(me: CurrentOwner = Depends(me_owner), db: Session = Depends(get_db)):
    return me_out(db, me.owner)


@router.patch("/me", response_model=MeOut)
def patch_me(body: MePatch, me: CurrentOwner = Depends(me_owner), db: Session = Depends(get_db)):
    """The language LaMP's texts to the owner use."""
    me.owner.language = body.language
    db.commit()
    return me_out(db, me.owner)


@router.post("/pharmacies", response_model=PharmacyOut, status_code=201)
def create_pharmacy(body: PharmacyCreate, me: CurrentOwner = Depends(me_owner), db: Session = Depends(get_db)):
    """The first setup step: the shop's name and town. One shop per owner in Phase 1."""
    ph = shops.create_shop(db, me.owner, body.name, body.city, body.area)
    db.commit()
    return pharmacy_out(ph)
