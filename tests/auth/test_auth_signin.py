"""Owner sign-in (build plan 2.1, 2.2, 3.2; task A1.2), on the Applink mock.

Mock numbers: the last two digits pick a scenario (client/mock.py); the code is 123456.
"""
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from sqlalchemy import select

from app.applink.models import ApplinkConsent, Subscriber
from app.auth import legal, ratelimit
from app.auth.config import AuthSettings, get_settings
from app.auth.models import AuthSession, OtpChallenge
from app.db.models import Owner

A = "/api/v1/auth"
PHONE = "+8801912345600"
ANDROID = {"id": "dev-android-1", "name": "Android phone", "os": "android", "app_version": "1.0.0+1"}
BROWSER = {"id": "dev-web-1", "name": "Web browser", "os": "web", "app_version": "1.0.0+1"}


def ask(web, phone=PHONE, language="bn"):
    return web.post(f"{A}/otp/request", json={"phone": phone, "language": language})


def sign_in(web, phone=PHONE, device=ANDROID, code="123456"):
    r = ask(web, phone)
    assert r.status_code == 202, r.text
    return web.post(f"{A}/otp/verify", json={"challenge_id": r.json()["challenge_id"], "code": code, "device": device})


def bearer(r) -> dict:
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


# ------------------------------------------------------------------ the code itself

def test_request_answers_a_challenge_and_never_applinks_reference(web, auth_db):
    r = ask(web)
    assert r.status_code == 202
    assert r.json().keys() == {"challenge_id", "expires_in", "resend_after"}
    assert r.json()["expires_in"] == 300 and r.json()["resend_after"] == 30
    ch = auth_db.get(OtpChallenge, r.json()["challenge_id"])
    assert ch.status == "SENT" and ch.app == "core" and ch.language == "bn"
    assert "MOCKREF" not in ch.reference_enc and "1912345600" not in ch.phone_enc  # sealed


@pytest.mark.parametrize("phone,code", [("+8801712345678", "not_banglalink"), ("01512345678", "not_banglalink"),
                                        ("12345", "invalid"), ("019123456789999", "invalid")])
def test_only_banglalink_numbers(web, phone, code):
    r = ask(web, phone)
    assert r.status_code == 422 and r.json()["code"] == code


def test_first_sign_in_creates_the_owner_without_a_shop(web, auth_db):
    r = sign_in(web)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["is_new"] is True and body["pharmacy"] is None
    assert body["owner"]["phone_masked"] == "+880 19•• ••• 600" and body["owner"]["language"] == "bn"
    assert body["refresh_token"] and body["access_token"]
    owner = auth_db.get(Owner, body["owner"]["id"])
    assert owner.subscriber_ref.startswith("tel:MASK")  # masking is on: Applink's id, as returned
    assert "1912345600" not in owner.phone_enc and "1912345600" not in owner.phone_hash
    sub = auth_db.scalar(select(Subscriber).where(Subscriber.owner_id == owner.id))
    assert (sub.app, sub.status, sub.subscriber_ref) == ("core", "REGISTERED", owner.subscriber_ref)


def test_signing_in_again_finds_the_same_owner(web):
    first = sign_in(web).json()
    again = sign_in(web, "01912345600", device={**ANDROID, "id": "dev-android-2"}).json()
    assert again["is_new"] is False and again["owner"]["id"] == first["owner"]["id"]


def test_a_wrong_code_counts_and_the_fifth_ends_the_challenge(web):
    cid = ask(web).json()["challenge_id"]
    for left in (4, 3, 2, 1):
        r = web.post(f"{A}/otp/verify", json={"challenge_id": cid, "code": "000000", "device": ANDROID})
        assert r.status_code == 400 and r.json()["code"] == "otp_wrong"
        assert f"{left} tr" in r.json()["detail"]
    r = web.post(f"{A}/otp/verify", json={"challenge_id": cid, "code": "000000", "device": ANDROID})
    assert r.status_code == 429 and r.json()["code"] == "otp_too_many"
    r = web.post(f"{A}/otp/verify", json={"challenge_id": cid, "code": "123456", "device": ANDROID})
    assert r.json()["code"] == "otp_too_many"  # even the right code is too late now


def test_a_code_that_is_not_digits_counts_as_wrong_without_asking_applink(web):
    cid = ask(web).json()["challenge_id"]
    r = web.post(f"{A}/otp/verify", json={"challenge_id": cid, "code": "12a456", "device": ANDROID})
    assert r.status_code == 400 and r.json()["code"] == "otp_wrong"


def test_applink_says_wrong_once_then_the_right_code_works(web):  # mock scenario 01
    cid = ask(web, "+8801912345601").json()["challenge_id"]
    r = web.post(f"{A}/otp/verify", json={"challenge_id": cid, "code": "123456", "device": ANDROID})
    assert r.json()["code"] == "otp_wrong"
    r = web.post(f"{A}/otp/verify", json={"challenge_id": cid, "code": "123456", "device": ANDROID})
    assert r.status_code == 200


def test_an_expired_code(web):  # mock scenario 02
    r = sign_in(web, "+8801912345602")
    assert r.status_code == 400 and r.json()["code"] == "otp_expired"


def test_our_own_timer_expires_the_code_too(web, auth_db):
    cid = ask(web).json()["challenge_id"]
    ch = auth_db.get(OtpChallenge, cid)
    ch.expires_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(seconds=1)
    auth_db.commit()
    r = web.post(f"{A}/otp/verify", json={"challenge_id": cid, "code": "123456", "device": ANDROID})
    assert r.json()["code"] == "otp_expired"
    auth_db.expire_all()
    assert auth_db.get(OtpChallenge, cid).status == "EXPIRED"


def test_a_used_or_unknown_challenge_is_expired(web):
    r = ask(web)
    cid = r.json()["challenge_id"]
    assert web.post(f"{A}/otp/verify", json={"challenge_id": cid, "code": "123456", "device": ANDROID}).status_code == 200
    again = web.post(f"{A}/otp/verify", json={"challenge_id": cid, "code": "123456", "device": ANDROID})
    assert again.json()["code"] == "otp_expired"
    nobody = web.post(f"{A}/otp/verify", json={"challenge_id": "nope", "code": "123456", "device": ANDROID})
    assert nobody.status_code == 400 and nobody.json()["code"] == "otp_expired"


def test_a_number_not_on_applinks_test_list(web):  # mock scenario 06 (E1343)
    r = ask(web, "+8801912345606")
    assert r.status_code == 403 and r.json()["code"] == "invalid"


def test_applink_down_says_so_and_when_to_retry(web, auth_db):  # mock scenario 08 (E1603)
    r = ask(web, "+8801912345608")
    assert r.status_code == 503 and r.json()["code"] == "applink_down" and r.json()["retry_after"] == 60
    assert auth_db.scalar(select(OtpChallenge.status)) == "FAILED"


# ------------------------------------------------------------------ limits

def test_three_codes_per_number_per_15_minutes(web):
    for _ in range(3):
        assert ask(web).status_code == 202
    r = ask(web)
    assert r.status_code == 429 and r.json()["code"] == "rate_limited"
    assert 0 < r.json()["retry_after"] <= 900 and r.headers["retry-after"] == str(r.json()["retry_after"])
    assert ask(web, "+8801912345611").status_code == 202  # another number is fine


def test_twenty_codes_per_ip_per_hour(web):
    for i in range(20):
        assert ask(web, f"+88014123456{20 + i:02d}").status_code == 202, i  # no mock scenarios
    assert ask(web, "+8801412345699").json()["code"] == "rate_limited"


def test_window_start_is_stable_within_a_window():
    t = datetime(2026, 11, 28, 10, 7, 30)
    w = ratelimit._window_start(t, timedelta(minutes=15))
    assert w == datetime(2026, 11, 28, 10, 0) and ratelimit._window_start(t + timedelta(minutes=7), timedelta(minutes=15)) == w


# ------------------------------------------------------------------ sessions

def test_the_access_token_says_who_and_which_session(web, auth_db):
    r = sign_in(web)
    claims = jwt.decode(r.json()["access_token"], options={"verify_signature": False})
    assert claims["sub"] == r.json()["owner"]["id"] and claims["pid"] is None and claims["plan"] == "free"
    s = auth_db.get(AuthSession, claims["sid"])
    assert s.device_id == "dev-android-1" and not s.web
    exp = datetime.fromtimestamp(claims["exp"], timezone.utc) - datetime.fromtimestamp(claims["iat"], timezone.utc)
    assert exp == timedelta(minutes=15)
    assert r.json()["refresh_token"].split(".")[0] == s.id and r.json()["refresh_token"] not in s.refresh_hash


def test_refresh_rotates_and_an_old_token_ends_the_session(web):
    first = sign_in(web).json()["refresh_token"]
    second = web.post(f"{A}/refresh", json={"refresh_token": first})
    assert second.status_code == 200 and second.json()["refresh_token"] != first
    reuse = web.post(f"{A}/refresh", json={"refresh_token": first})
    assert reuse.status_code == 401 and reuse.json()["code"] == "session_expired"
    newest = web.post(f"{A}/refresh", json={"refresh_token": second.json()["refresh_token"]})
    assert newest.status_code == 401  # the whole session ended
    devices = web.get(f"{A}/devices", headers=bearer(second))
    assert devices.status_code == 401  # and its access token with it


@pytest.mark.parametrize("token", [None, "", "garbage", "a.b", "nope." + "x" * 40])
def test_a_bad_refresh_token(web, token):
    r = web.post(f"{A}/refresh", json={"refresh_token": token})
    assert r.status_code == 401 and r.json()["code"] == "session_expired"


def test_devices_and_removing_one(web):
    phone = sign_in(web)
    laptop = sign_in(web, device=BROWSER)
    listed = web.get(f"{A}/devices", headers=bearer(phone)).json()
    assert {d["name"] for d in listed} == {"Android phone", "Web browser"}
    mine = [d for d in listed if d["this_device"]]
    assert len(mine) == 1 and mine[0]["name"] == "Android phone"
    other = next(d for d in listed if not d["this_device"])
    assert web.delete(f"{A}/devices/{other['id']}", headers=bearer(phone)).status_code == 204
    assert web.get(f"{A}/devices", headers=bearer(laptop)).status_code == 401
    assert web.delete(f"{A}/devices/{other['id']}", headers=bearer(phone)).json()["code"] == "not_found"


def test_another_owners_device_cant_be_removed(web):
    a = sign_in(web)
    b = sign_in(web, "+8801912345611")
    b_device = web.get(f"{A}/devices", headers=bearer(b)).json()[0]["id"]
    assert web.delete(f"{A}/devices/{b_device}", headers=bearer(a)).status_code == 404
    assert web.get(f"{A}/devices", headers=bearer(b)).status_code == 200


def test_signing_in_again_on_the_same_device_replaces_its_session(web):
    old = sign_in(web)
    new = sign_in(web)
    assert web.get(f"{A}/devices", headers=bearer(old)).status_code == 401
    assert len(web.get(f"{A}/devices", headers=bearer(new)).json()) == 1


def test_sign_out_ends_the_session_at_once(web):
    r = sign_in(web)
    assert web.post(f"{A}/sign-out", headers=bearer(r)).status_code == 204
    assert web.get(f"{A}/devices", headers=bearer(r)).status_code == 401
    assert web.post(f"{A}/refresh", json={"refresh_token": r.json()["refresh_token"]}).status_code == 401


@pytest.mark.parametrize("header", [None, "Bearer", "Bearer nope", "Basic abc"])
def test_no_or_bad_access_token(web, header):
    r = web.get(f"{A}/devices", headers={"Authorization": header} if header else {})
    assert r.status_code == 401 and r.json()["code"] == "session_expired"


def test_a_token_signed_with_another_key_is_refused(web):
    r = sign_in(web)
    claims = jwt.decode(r.json()["access_token"], options={"verify_signature": False})
    forged = jwt.encode(claims, "x" * 40, algorithm="HS256")
    assert web.get(f"{A}/devices", headers={"Authorization": f"Bearer {forged}"}).status_code == 401


def test_web_keeps_the_refresh_token_in_a_cookie(web):
    r = sign_in(web, device=BROWSER)
    assert r.status_code == 200 and r.json()["refresh_token"] is None
    cookie = r.headers["set-cookie"]
    assert "lamp_refresh=" in cookie and "HttpOnly" in cookie and "Path=/api/v1/auth" in cookie
    assert "samesite=strict" in cookie.lower()
    again = web.post(f"{A}/refresh", json={})
    assert again.status_code == 200 and again.json()["refresh_token"] is None and "lamp_refresh=" in again.headers["set-cookie"]
    assert web.post(f"{A}/sign-out", headers=bearer(again)).status_code == 204
    web.cookies.clear()
    assert web.post(f"{A}/refresh", json={}).status_code == 401


# ------------------------------------------------------------------ consents

def test_consents_record_the_current_versions_only(web, auth_db):
    from app.auth import consents

    r = sign_in(web)
    owner_id = r.json()["owner"]["id"]
    assert consents.needed(auth_db, owner_id) == ["terms", "privacy"]
    wrong = web.post("/api/v1/me/consents", headers=bearer(r), json={"terms_version": "2020-01-01",
                                                                      "privacy_version": legal.PRIVACY_VERSION})
    assert wrong.status_code == 422 and wrong.json()["code"] == "invalid"
    body = {"terms_version": legal.TERMS_VERSION, "privacy_version": legal.PRIVACY_VERSION}
    assert web.post("/api/v1/me/consents", headers=bearer(r), json=body).status_code == 204
    assert web.post("/api/v1/me/consents", headers=bearer(r), json=body).status_code == 204  # twice is fine
    auth_db.expire_all()
    assert consents.needed(auth_db, owner_id) == []
    rows = auth_db.scalars(select(ApplinkConsent).where(ApplinkConsent.subject_id == owner_id)).all()
    assert sorted((c.purpose, c.channel) for c in rows) == [("privacy", "app"), ("terms", "app")]


def test_consents_need_a_session(web):
    body = {"terms_version": legal.TERMS_VERSION, "privacy_version": legal.PRIVACY_VERSION}
    assert web.post("/api/v1/me/consents", json=body).status_code == 401


# ------------------------------------------------------------------ the demo shop

def test_demo_sign_in_is_off_unless_enabled(web):
    r = web.post(f"{A}/demo", json={"demo_code": "anything"})
    assert r.status_code == 404 and r.json()["code"] == "not_found"


@pytest.fixture
def demo_on(monkeypatch):
    monkeypatch.setenv("DEMO_ENABLED", "true")
    monkeypatch.setenv("DEMO_CODE", "GREEN-LIFE-26")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_demo_sign_in_opens_the_demo_shop(web, demo_on):
    assert web.post(f"{A}/demo", json={"demo_code": "wrong"}).json()["code"] == "invalid"
    r = web.post(f"{A}/demo", json={"demo_code": "green-life-26"})
    assert r.status_code == 200, r.text
    assert r.json()["pharmacy"] == {"id": "green-life", "name": "Green Life Pharmacy", "setup_complete": True}
    assert r.json()["owner"]["phone_masked"] == "Demo shop" and r.json()["refresh_token"]
    browser = web.post(f"{A}/demo", json={"demo_code": "GREEN-LIFE-26"}, headers={"Origin": "http://localhost"})
    assert browser.json()["refresh_token"] is None and "lamp_refresh=" in browser.headers["set-cookie"]
    assert browser.json()["owner"]["id"] == r.json()["owner"]["id"]  # one demo owner, many devices


def test_demo_sign_in_is_limited_per_ip(web, demo_on):
    for _ in range(10):
        web.post(f"{A}/demo", json={"demo_code": "wrong"})
    assert web.post(f"{A}/demo", json={"demo_code": "GREEN-LIFE-26"}).json()["code"] == "rate_limited"


# ------------------------------------------------------------------ settings

def test_settings_refuse_a_broken_production_setup():
    bad = AuthSettings(app_env="production", dev_mode=True, jwt_secret="short", _env_file=None)
    problems = bad.problems()
    assert "DEV_MODE=true with APP_ENV=production" in problems
    assert "JWT_SECRET is shorter than 32 characters" in problems
    assert not any("short" in p.replace("shorter", "") for p in problems)  # names, never values
    missing = AuthSettings(dev_mode=False, _env_file=None)
    assert {"JWT_SECRET is not set", "PHONE_PEPPER is not set", "PII_KEY is not set"} <= set(missing.problems())
    with pytest.raises(RuntimeError, match="JWT_SECRET is not set"):
        missing.secret("jwt_secret")
    ok = AuthSettings(dev_mode=False, jwt_secret="j" * 32, phone_pepper="p" * 32, pii_key="k" * 32, _env_file=None)
    assert ok.problems() == []
