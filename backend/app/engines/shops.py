"""Creating and changing a shop (build plan 2.2 "Shop setup", 4.2; task I2.2).

A new shop is a real one, with the default settings (12% margin, no cash buffer, a 30-day
expiry buffer) and a 2-letter card prefix. One owner has one shop in Phase 1.
"""

import re
import secrets
import string
import uuid
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.db.models import Owner, Pharmacy
from app.schemas.product import PharmacyPatch

from .logbus import log

DEFAULT_SETTINGS = {"gross_margin_pct": 12, "cash_buffer": 0, "expiry_buffer_days": 30}


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def card_prefix(name: str) -> str:
    """The first letters of the first two Latin words ("Green Life" -> GL), or the first two
    letters of a single word ("Shapla" -> SH). A name with no Latin letters gets two random ones."""
    words = re.findall(r"[A-Za-z]+", name)
    if len(words) >= 2:
        return (words[0][0] + words[1][0]).upper()
    if words and len(words[0]) >= 2:
        return words[0][:2].upper()
    return "".join(secrets.choice(string.ascii_uppercase) for _ in range(2))


def create_shop(db: Session, owner: Owner, name: str, city: str, area: str | None) -> Pharmacy:
    if owner.pharmacy_id is not None:
        raise ApiProblem(409, "invalid", "You already have a shop.")
    if not name.strip() or not city.strip():
        raise ApiProblem(422, "invalid", "The shop needs a name and a town.")
    settings = dict(DEFAULT_SETTINGS)
    if area:
        settings["area"] = area
    ph = Pharmacy(id=f"ph-{uuid.uuid4().hex[:12]}", name=name.strip(), city=city.strip(), cash_on_hand=0,
                  settings=settings, kind="real", card_prefix=card_prefix(name), setup_complete=False,
                  created_at=_now())
    db.add(ph)
    db.flush()
    owner.pharmacy_id = ph.id  # the next request finds the shop from here: tokens don't carry it
    log("T1", "SETUP", "shop_created", db, pharmacy=ph.id)
    db.flush()
    return ph


def update_shop(db: Session, ph: Pharmacy, patch: PharmacyPatch) -> Pharmacy:
    """Name, city, margin and cash buffer (build plan 2.2)."""
    changed = patch.model_dump(exclude_unset=True, exclude_none=True)
    for key in ("name", "city"):
        if key in changed and not changed[key].strip():
            raise ApiProblem(422, "invalid", f"The shop's {key} can't be empty.")
    if "name" in changed:
        ph.name = changed["name"].strip()
    if "city" in changed:
        ph.city = changed["city"].strip()
    settings = dict(ph.settings or {})
    for key in ("gross_margin_pct", "cash_buffer"):
        if key in changed:
            settings[key] = changed[key]
    ph.settings = settings
    log("T1", "SETUP", "shop_updated", db, pharmacy=ph.id, fields=sorted(changed))
    db.flush()
    return ph


def complete_setup(db: Session, ph: Pharmacy) -> Pharmacy:
    """Setup is done: from here, Today has enough data to show figures."""
    if not ph.setup_complete:
        ph.setup_complete = True
        log("T1", "SETUP", "setup_completed", db, pharmacy=ph.id)
        db.flush()
    return ph
