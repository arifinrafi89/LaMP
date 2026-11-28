"""Applink OTP for owner sign-in and for starting LaMP Plus (build plan 3.2, 3.3).

    CREATED  rate limits passed   → SENT on S1000 · FAILED on a setup error (alert) or no answer
    SENT     5-minute timer       → VERIFIED on S1000 · SENT again on E1850 (5 tries)
                                  · EXPIRED on E1851 or after 5 minutes · DEAD on E1855 or the 5th wrong code

Applink's referenceNo is sealed on the challenge row and never sent to the app or logged.
Every state change is committed before an error goes back, so wrong tries always count.
"""
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.applink import codes, tel
from app.applink.client.base import NotOnAllowList, ServiceNotEnabled
from app.applink.client.factory import client_for
from app.applink.config import AppName
from app.auth import crypto
from app.auth.models import OtpChallenge

log = logging.getLogger("lamp.applink.otp")

LIFETIME = timedelta(minutes=5)
RESEND_AFTER_S = 30
MAX_TRIES = 5
PHONE_PURPOSE = "otp_challenge.phone"
REF_PURPOSE = "otp_challenge.reference"


@dataclass(frozen=True)
class Verified:
    challenge: OtpChallenge
    subscriber_ref: str        # exactly as Applink returned it (masked while masking is on)
    subscription_status: str   # normalised: REGISTERED, INITIAL, …


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def applink_down(detail: str = "Banglalink's service isn't answering. Try again in a minute.") -> ApiProblem:
    return ApiProblem(503, "applink_down", detail, retry_after=60)


def number_for(phone: str) -> str:
    """The number as tel:8801…, or 422 if it isn't a Banglalink mobile number."""
    try:
        number = tel.to_tel(phone)
    except ValueError:
        raise ApiProblem(422, "invalid", "That doesn't look like a mobile number.") from None
    if not tel.is_banglalink(number):
        raise ApiProblem(422, "not_banglalink", "Use a Banglalink number (019 or 014).")
    return number


def send(db: Session, number: str, *, purpose: str, app: AppName, language: str = "en",
         owner_id: str | None = None, ip_hash: str | None = None, meta: dict[str, str] | None = None,
         pharmacy_kind: str | None = None) -> OtpChallenge:
    """Ask Applink to text a code to `number` (already checked by `number_for`)."""
    now = _now()
    ch = OtpChallenge(id=str(uuid.uuid4()), purpose=purpose, app=app, owner_id=owner_id,
                      phone_hash=crypto.phone_hash(number), phone_enc=crypto.seal(number, purpose=PHONE_PURPOSE),
                      language=language, status="CREATED", attempts=0, ip_hash=ip_hash,
                      created_at=now, expires_at=now + LIFETIME)
    db.add(ch)
    db.commit()
    try:
        reply = client_for(pharmacy_kind).otp_request(app, number, meta)
    except NotOnAllowList:
        _finish(db, ch, "FAILED", "allow-list")
        raise ApiProblem(403, "invalid", "This number isn't on the test list yet.") from None
    except ServiceNotEnabled:
        _finish(db, ch, "FAILED", "service")
        log.error("otp_request refused locally: OTP isn't enabled for the %s app", app)
        raise applink_down() from None
    if reply.timed_out:
        _finish(db, ch, "FAILED", "timeout")
        raise applink_down()
    code = (reply.status_code or "").upper()
    if reply.ok and reply.get("referenceNo"):
        ch.reference_enc = crypto.seal(str(reply.get("referenceNo")), purpose=REF_PURPOSE)
        _finish(db, ch, "SENT", code)
        return ch
    _finish(db, ch, "FAILED", code or "none")
    if code in ("E1317", "E1856"):
        raise ApiProblem(422, "not_banglalink", "Use a Banglalink number (019 or 014).")
    if code in ("E1343",):
        raise ApiProblem(403, "invalid", "This number isn't on the test list yet.")
    if code == "E1342":
        raise ApiProblem(403, "invalid", "Banglalink has blocked messages to this number.")
    if reply.outcome in (codes.Outcome.CONFIGURATION, codes.Outcome.UNKNOWN):
        log.error("otp_request failed with %s on the %s app: our Applink setup is broken", code or "no code", app)
    raise applink_down()


def check(db: Session, challenge_id: str, code: str, *, purpose: str, owner_id: str | None = None,
          pharmacy_kind: str | None = None) -> Verified:
    """Check the code the person typed. Errors: otp_wrong, otp_expired, otp_too_many, applink_down."""
    ch = db.get(OtpChallenge, challenge_id)
    if ch is None or ch.purpose != purpose or (owner_id is not None and ch.owner_id != owner_id):
        raise _expired()
    if ch.status != "SENT" or ch.reference_enc is None:
        raise _too_many() if ch.status == "DEAD" else _expired()
    if _now() >= ch.expires_at:
        _finish(db, ch, "EXPIRED", "timer")
        raise _expired()
    code = (code or "").strip()
    if not code.isdigit() or not 4 <= len(code) <= 8:
        return _wrong(db, ch)
    reference = crypto.unseal(ch.reference_enc, purpose=REF_PURPOSE)
    reply = client_for(pharmacy_kind).otp_verify(ch.app, reference, code)
    if reply.timed_out:
        raise applink_down()
    status = (reply.status_code or "").upper()
    if reply.ok:
        ref = reply.get("subscriberId")
        if not ref:
            log.error("otp_verify answered S1000 without subscriberId on the %s app", ch.app)
            raise applink_down()
        _finish(db, ch, "VERIFIED", status)
        return Verified(ch, str(ref), codes.subscription_status(reply.get("subscriptionStatus")) or "INITIAL")
    if status == "E1850":
        return _wrong(db, ch)
    if status == "E1851":
        _finish(db, ch, "EXPIRED", status)
        raise _expired()
    if status == "E1855":
        _finish(db, ch, "DEAD", status)
        raise _expired()
    if reply.outcome in (codes.Outcome.CONFIGURATION, codes.Outcome.UNKNOWN):
        log.error("otp_verify failed with %s on the %s app: our Applink setup is broken", status or "no code", ch.app)
    raise applink_down()


def phone_of(ch: OtpChallenge) -> str:
    return crypto.unseal(ch.phone_enc, purpose=PHONE_PURPOSE)


def _finish(db: Session, ch: OtpChallenge, status: str, last_code: str) -> None:
    ch.status, ch.last_code = status, last_code[:16]
    db.commit()


def _wrong(db: Session, ch: OtpChallenge):
    ch.attempts += 1
    if ch.attempts >= MAX_TRIES:
        _finish(db, ch, "DEAD", "tries")
        raise _too_many()
    db.commit()
    left = MAX_TRIES - ch.attempts
    raise ApiProblem(400, "otp_wrong", f"That code isn't right. {left} {'try' if left == 1 else 'tries'} left.")


def _expired() -> ApiProblem:
    return ApiProblem(400, "otp_expired", "The code has expired. Send a new one.")


def _too_many() -> ApiProblem:
    return ApiProblem(429, "otp_too_many", "Too many wrong codes. Send a new one.", retry_after=RESEND_AFTER_S)
