"""Applink tables (build plan 4.3; migration branch `applink`).

Built task by task: the subscription mirror and consents arrive with sign-in (A1.2); the
callbacks, families, SMS and charges add theirs in A2.1, A2.2 and A3.1. Times are naive UTC.
"""
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.models import Base


class Subscriber(Base):
    """Our mirror of one Applink subscription (plan 3.3). No Applink call is made on sign-in
    or page load: entitlements are read from here, kept up to date by the notification
    callback and the nightly check."""

    __tablename__ = "subscriber"
    __table_args__ = (UniqueConstraint("app", "subscriber_ref", name="uq_subscriber_app_ref"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    app: Mapped[str] = mapped_column(String)             # core | plus
    subscriber_ref: Mapped[str] = mapped_column(String)  # exactly as Applink returned it (masked)
    owner_id: Mapped[str | None] = mapped_column(ForeignKey("owner.id"), nullable=True, index=True)
    status: Mapped[str] = mapped_column(String)          # REGISTERED, INITIAL, REG_PENDING, …
    frequency: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime)
    updated_at: Mapped[datetime] = mapped_column(DateTime)
    last_notified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_confirmed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class ApplinkConsent(Base):
    """What a person agreed to, word for word by version (plan 3.3, 3.4, 13.3). Named so it
    can't clash with the lenders' `consent` table."""

    __tablename__ = "applink_consent"
    id: Mapped[int] = mapped_column(primary_key=True)
    subject: Mapped[str] = mapped_column(String)     # owner | family
    subject_id: Mapped[str] = mapped_column(String, index=True)  # owner id, or the family's card code
    purpose: Mapped[str] = mapped_column(String)     # terms | privacy | family_sms | plus
    wording_version: Mapped[str] = mapped_column(String)
    price_text: Mapped[str | None] = mapped_column(String, nullable=True)
    channel: Mapped[str] = mapped_column(String)     # app | counter | sms
    given_at: Mapped[datetime] = mapped_column(DateTime)
    withdrawn_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
