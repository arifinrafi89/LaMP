"""The routers that main.py mounts under /api/v1 (build plan I0.5, A1.2).

api_router carries three groups:
  /auth/...        sign-in: otp/request, otp/verify, refresh, sign-out, devices, demo (2.2)
  /legal/...       the terms and privacy policy and their versions (G3, 13.3)
  /me/consents     the owner accepts the current terms and privacy policy

Web keeps the refresh token in an httpOnly cookie on /api/v1/auth (the static site
proxies /api/*, so it is one origin); Android gets it in the body and keeps it in secure
storage. Wrong codes answer 400, not 401: the app treats 401 as "refresh and retry".
"""
import uuid

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy.orm import Session

from app.api.problems import ApiProblem
from app.applink import otp
from app.auth import consents, crypto, ratelimit, sessions, signin
from app.auth.config import get_settings
from app.auth.deps import CurrentOwner, current_owner
from app.auth.legal import router as legal_router
from app.db.models import Owner
from app.db.session import get_db
from app.schemas.product import (
    ConsentsIn, DemoSignInIn, DeviceOut, OtpChallengeOut, OtpRequestIn, OtpVerifyIn, Problem, RefreshIn,
    SignedInOut, TokenPairOut,
)

COOKIE = "lamp_refresh"
COOKIE_PATH = "/api/v1/auth"

ERRORS = {code: {"model": Problem} for code in (400, 401, 403, 404, 422, 429, 503)}
auth_router = APIRouter(prefix="/auth", tags=["auth"], responses=ERRORS)
me_router = APIRouter(prefix="/me", tags=["account"], responses=ERRORS)


def _set_cookie(response: Response, token: str) -> None:
    cfg = get_settings()
    response.set_cookie(COOKIE, token, max_age=cfg.refresh_days * 86400, path=COOKIE_PATH, httponly=True,
                        secure=cfg.app_env != "dev", samesite="strict")


def _clear_cookie(response: Response) -> None:
    response.delete_cookie(COOKIE, path=COOKIE_PATH, httponly=True, samesite="strict",
                           secure=get_settings().app_env != "dev")


@auth_router.post("/otp/request", response_model=OtpChallengeOut, status_code=202)
def otp_request(body: OtpRequestIn, request: Request, db: Session = Depends(get_db)) -> OtpChallengeOut:
    number = otp.number_for(body.phone)
    ip = ratelimit.ip_hash(request)
    who = crypto.phone_hash(number)
    ratelimit.hit(db, ratelimit.OTP_PER_IP_HOUR, ip)
    ratelimit.hit(db, ratelimit.OTP_PER_NUMBER_15M, who)
    ratelimit.hit(db, ratelimit.OTP_PER_NUMBER_DAY, who)
    db.commit()  # the tries count even if Applink fails
    ch = otp.send(db, number, purpose="signin", app="core", language=body.language, ip_hash=ip)
    return OtpChallengeOut(challenge_id=ch.id, expires_in=int(otp.LIFETIME.total_seconds()),
                           resend_after=otp.RESEND_AFTER_S)


@auth_router.post("/otp/verify", response_model=SignedInOut)
def otp_verify(body: OtpVerifyIn, response: Response, db: Session = Depends(get_db)) -> dict:
    verified = otp.check(db, body.challenge_id, body.code, purpose="signin")
    owner, is_new = signin.owner_for(db, verified)
    s, refresh = sessions.create(db, owner, body.device.model_dump())
    out = signin.signed_in(db, owner, s, refresh, is_new=is_new)
    db.commit()
    if s.web:
        _set_cookie(response, refresh)
    return out


@auth_router.post("/refresh", response_model=TokenPairOut)
def refresh(request: Request, response: Response, body: RefreshIn | None = None,
            db: Session = Depends(get_db)) -> dict:
    from_body = body.refresh_token if body else None
    token = from_body or request.cookies.get(COOKIE)
    try:
        s, new = sessions.rotate(db, token)
    except ApiProblem:
        if not from_body:
            _clear_cookie(response)
        raise
    owner = db.get(Owner, s.owner_id)
    access, expires_at = sessions.access_for(db, owner, s)
    db.commit()
    if from_body:
        return {"access_token": access, "expires_at": expires_at, "refresh_token": new}
    _set_cookie(response, new)
    return {"access_token": access, "expires_at": expires_at, "refresh_token": None}


@auth_router.post("/sign-out", status_code=204)
def sign_out(response: Response, me: CurrentOwner = Depends(current_owner), db: Session = Depends(get_db)) -> None:
    sessions.end(db, me.session, "sign_out")
    db.commit()
    _clear_cookie(response)


@auth_router.get("/devices", response_model=list[DeviceOut])
def devices(me: CurrentOwner = Depends(current_owner), db: Session = Depends(get_db)) -> list[DeviceOut]:
    return [DeviceOut(id=s.id, name=s.device_name, os=s.device_os, last_used_at=s.last_used_at,
                      this_device=s.id == me.session.id) for s in sessions.devices(db, me.owner_id)]


@auth_router.delete("/devices/{device_id}", status_code=204)
def remove_device(device_id: str, me: CurrentOwner = Depends(current_owner), db: Session = Depends(get_db)) -> None:
    s = sessions.active(db, device_id)
    if s is None or s.owner_id != me.owner_id:
        raise ApiProblem(404, "not_found", "That device isn't signed in.")
    sessions.end(db, s, "device")
    db.commit()


@auth_router.post("/demo", response_model=SignedInOut)
def demo(body: DemoSignInIn, request: Request, response: Response, db: Session = Depends(get_db)) -> dict:
    ratelimit.hit(db, ratelimit.DEMO_PER_IP_MINUTE, ratelimit.ip_hash(request))
    db.commit()
    owner = signin.demo_owner(db, body.demo_code)
    web = "origin" in request.headers  # browsers send Origin on every POST; the Android app doesn't
    device = {"id": "demo-" + uuid.uuid4().hex[:16], "name": "Web browser" if web else "Demo phone",
              "os": "web" if web else "android", "app_version": request.headers.get("x-app-version", "")}
    s, refresh_token = sessions.create(db, owner, device)
    out = signin.signed_in(db, owner, s, refresh_token, is_new=False)
    db.commit()
    if s.web:
        _set_cookie(response, refresh_token)
    return out


@me_router.post("/consents", status_code=204)
def accept(body: ConsentsIn, me: CurrentOwner = Depends(current_owner), db: Session = Depends(get_db)) -> None:
    consents.record(db, me.owner_id, body.terms_version, body.privacy_version)
    db.commit()


api_router = APIRouter()
api_router.include_router(auth_router)
api_router.include_router(legal_router)
api_router.include_router(me_router)
