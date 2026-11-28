"""Changing the shop and finishing setup (build plan 2.2 "Shop setup"; task I2.2).

Mounted on the owner router in routes.py, so `require_owner` has already checked that
{pid} is the caller's own shop (404 otherwise).
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.config import settings
from app.db.models import Pharmacy
from app.db.session import get_db
from app.engines import get_pharmacy, shops
from app.schemas import PharmacyOut, PharmacySettings
from app.schemas.product import PharmacyPatch

router = APIRouter()


def pharmacy_out(ph: Pharmacy) -> dict:
    """The PharmacyOut body. Only the public settings: they also hold the PIN hash, the PIN
    lockout, the Pause state and the area."""
    public = {k: v for k, v in (ph.settings or {}).items() if k in PharmacySettings.model_fields}
    return {"id": ph.id, "name": ph.name, "city": ph.city, "settings": public, "asks_pin": settings.ask_owner_pin,
            "kind": ph.kind, "setup_complete": bool(ph.setup_complete), "card_prefix": ph.card_prefix}


@router.patch("/pharmacies/{pid}", response_model=PharmacyOut)
def patch_pharmacy(pid: str, body: PharmacyPatch, db: Session = Depends(get_db)):
    """Name, city, margin and cash buffer."""
    ph = shops.update_shop(db, get_pharmacy(db, pid), body)
    db.commit()
    return pharmacy_out(ph)


@router.post("/pharmacies/{pid}/setup/complete", response_model=PharmacyOut)
def complete_setup(pid: str, db: Session = Depends(get_db)):
    """Setup is done. Each step could be skipped; Today shows what is still missing."""
    ph = shops.complete_setup(db, get_pharmacy(db, pid))
    db.commit()
    return pharmacy_out(ph)
