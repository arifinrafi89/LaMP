"""Sign-in tables (build plan 4.3; migration branch `applink`).

Times are naive UTC, like the core tables. Nothing here holds a number or a token in the
clear: numbers are hashed (and sealed where they must be read back), tokens are hashed.
"""
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.models import Base


class AuthSession(Base):
    """One signed-in phone or browser. The refresh token is "<id>.<secret>"; only the secret's
    sha256 is stored, and it changes on every refresh. An old secret coming back means a
    stolen copy is in use, so the whole session ends (plan 2.1)."""

    __tablename__ = "auth_session"
    id: Mapped[str] = mapped_column(String, primary_key=True)  # uuid
    owner_id: Mapped[str] = mapped_column(ForeignKey("owner.id"), index=True)
    device_id: Mapped[str] = mapped_column(String)    # the app's own id for the device
    device_name: Mapped[str] = mapped_column(String)  # "Android phone", "Web browser"
    device_os: Mapped[str] = mapped_column(String)
    app_version: Mapped[str] = mapped_column(String)
    web: Mapped[bool] = mapped_column(default=False)  # the refresh token travels in a cookie
    refresh_hash: Mapped[str] = mapped_column(String)
    rotations: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime)
    last_used_at: Mapped[datetime] = mapped_column(DateTime)
    expires_at: Mapped[datetime] = mapped_column(DateTime)  # 30 days after last use
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    revoked_reason: Mapped[str | None] = mapped_column(String, nullable=True)  # sign_out | device | reuse | deleted


class OtpChallenge(Base):
    """One code sent by Applink (plan 3.2): CREATED → SENT → VERIFIED, or FAILED, EXPIRED, DEAD."""

    __tablename__ = "otp_challenge"
    id: Mapped[str] = mapped_column(String, primary_key=True)  # uuid, the app's challenge_id
    purpose: Mapped[str] = mapped_column(String)  # signin | plus
    app: Mapped[str] = mapped_column(String)      # core | plus (the Applink app that sent it)
    owner_id: Mapped[str | None] = mapped_column(ForeignKey("owner.id"), nullable=True)  # plus: who asked
    phone_hash: Mapped[str] = mapped_column(String, index=True)
    phone_enc: Mapped[str] = mapped_column(String)  # sealed, to create the owner at verify
    reference_enc: Mapped[str | None] = mapped_column(String, nullable=True)  # Applink's referenceNo, sealed
    language: Mapped[str] = mapped_column(String, default="en")
    status: Mapped[str] = mapped_column(String, default="CREATED")
    attempts: Mapped[int] = mapped_column(Integer, default=0)  # wrong codes so far
    last_code: Mapped[str | None] = mapped_column(String, nullable=True)  # Applink's last statusCode
    ip_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime)
    expires_at: Mapped[datetime] = mapped_column(DateTime)


class RateCounter(Base):
    """Fixed-window counters for the limits in plan 2.1, kept in the database so they hold
    across restarts and (later) several web instances."""

    __tablename__ = "rate_counter"
    key: Mapped[str] = mapped_column(String, primary_key=True)  # e.g. "otp:number:15m:<hash>"
    window_start: Mapped[datetime] = mapped_column(DateTime, primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0)
