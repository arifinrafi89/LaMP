"""The owner's consents to the terms and privacy policy (build plan 13.3, G3).

`/me` lists `consents_needed` until the owner has accepted the current version of each;
changing a text's version in legal.py asks every owner again.
"""
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.applink.models import ApplinkConsent
from app.auth import legal


def _given(db: Session, owner_id: str, purpose: str, version: str) -> bool:
    return db.scalar(select(ApplinkConsent.id).where(
        ApplinkConsent.subject == "owner", ApplinkConsent.subject_id == owner_id,
        ApplinkConsent.purpose == purpose, ApplinkConsent.wording_version == version,
        ApplinkConsent.withdrawn_at.is_(None)).limit(1)) is not None


def needed(db: Session, owner_id: str) -> list[str]:
    current = {"terms": legal.TERMS_VERSION, "privacy": legal.PRIVACY_VERSION}
    return [purpose for purpose, version in current.items() if not _given(db, owner_id, purpose, version)]


def record(db: Session, owner_id: str, terms_version: str, privacy_version: str) -> None:
    """Record acceptance of the current versions; any other version is refused (422)."""
    if terms_version != legal.TERMS_VERSION or privacy_version != legal.PRIVACY_VERSION:
        raise ApiProblem(422, "invalid", "These aren't the current terms. Open them again and accept.")
    now = datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)
    for purpose, version in (("terms", terms_version), ("privacy", privacy_version)):
        if not _given(db, owner_id, purpose, version):
            db.add(ApplinkConsent(subject="owner", subject_id=owner_id, purpose=purpose, wording_version=version,
                                  channel="app", given_at=now))
