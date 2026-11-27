"""Applink settings (app/applink/config.py, plan 10.2)."""
from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.applink.config import ApplinkSettings

SECRET = "s" * 48
APPLINK_ENV = [
    "APPLINK_MODE", "APPLINK_CORE_APP_ID", "APPLINK_CORE_PASSWORD", "APPLINK_PLUS_APP_ID",
    "APPLINK_PLUS_PASSWORD", "APPLINK_CORE_SERVICES", "APPLINK_PLUS_SERVICES", "APPLINK_MASKING",
    "FAMILY_JOIN_ROUTES", "FAMILY_SUBSCRIBE_METHOD", "APPLINK_ALLOWED_NUMBERS",
    "APPLINK_CALLBACK_SECRET", "APPLINK_TPS", "PRICE_CREDIT_RECORD",
]


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    for name in APPLINK_ENV:
        monkeypatch.delenv(name, raising=False)


def settings(**kw) -> ApplinkSettings:
    return ApplinkSettings(_env_file=None, **kw)


def full(**kw) -> ApplinkSettings:
    base = dict(core_app_id="APP_019205", core_password="pw-core", plus_app_id="APP_019207",
                plus_password="pw-plus", callback_secret=SECRET)
    return settings(**{**base, **kw})


def test_defaults_match_the_applink_form():
    s = settings()
    assert s.mode == "mock"
    assert s.sms_shortcode == "21213" and s.sms_keyword == "lamp" and s.sms_source == ""
    assert s.masking is True
    assert s.join_routes == {"text"}
    assert s.app("core").services == {"otp", "subscription", "sms", "caas"}
    assert s.app("plus").services == {"otp", "subscription"}
    assert s.amount_text == "10.00"
    assert s.tps == 4
    assert s.allowed is None


def test_read_from_the_environment(monkeypatch):
    monkeypatch.setenv("APPLINK_MODE", "sandbox")
    monkeypatch.setenv("APPLINK_CORE_APP_ID", "APP_019205")
    monkeypatch.setenv("FAMILY_JOIN_ROUTES", "counter, text")
    monkeypatch.setenv("APPLINK_ALLOWED_NUMBERS", "01912345678, +8801412345678")
    s = settings()
    assert s.mode == "sandbox"
    assert s.app("core").app_id == "APP_019205"
    assert s.join_routes == {"text", "counter"}
    assert s.allowed == {"tel:8801912345678", "tel:8801412345678"}


def test_a_service_not_listed_is_refused_locally():
    s = settings()
    assert s.enabled("core", "caas")
    assert not s.enabled("plus", "sms")
    assert not s.enabled("core", "ussd")


def test_secrets_never_show_when_printed():
    s = full()
    shown = repr(s) + str(s) + str(s.model_dump())
    assert "pw-core" not in shown and "pw-plus" not in shown and SECRET not in shown


@pytest.mark.parametrize("bad", [
    {"core_services": "otp,ussd"},
    {"family_join_routes": "ussd"},
    {"family_join_routes": ""},
    {"price_credit_record": "3.00"},
    {"allowed_numbers": "0191234"},
    {"tps": 6},
    {"mode": "prod"},
    {"family_subscribe_method": "magic"},
])
def test_bad_values_fail_at_start_up(bad):
    with pytest.raises(ValidationError):
        settings(**bad)


def test_mock_needs_nothing():
    assert settings().problems("dev") == []


def test_sandbox_and_live_need_credentials_and_a_long_secret():
    assert full(mode="sandbox").problems("production") == []
    missing = settings(mode="sandbox", callback_secret="short").problems("production")
    assert any("APPLINK_CORE_APP_ID" in p for p in missing)
    assert any("APPLINK_PLUS_APP_ID" in p for p in missing)
    assert any("APPLINK_CALLBACK_SECRET" in p for p in missing)


def test_live_needs_production_and_no_allow_list():
    assert full(mode="live").problems("production") == []
    assert any("APP_ENV=production" in p for p in full(mode="live").problems("staging"))
    assert any("ALLOWED_NUMBERS" in p for p in full(mode="live", allowed_numbers="01912345678").problems("production"))


def test_counter_route_needs_masking_off():
    assert any("counter" in p for p in full(mode="sandbox", family_join_routes="text,counter").problems("production"))
    assert full(mode="sandbox", family_join_routes="text,counter", masking=False).problems("production") == []


def test_price_is_kept_to_two_decimals():
    assert settings(price_credit_record="5").price_credit_record == Decimal("5.00")
