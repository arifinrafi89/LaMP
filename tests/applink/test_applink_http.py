"""The real client's network rules (client/http.py), against a fake transport. No network."""
import json

import httpx
import pytest

from app.applink.client import factory
from app.applink.client.http import HttpClient
from app.applink.client.mock import MockClient
from app.applink.config import ApplinkSettings

CREDS = dict(core_app_id="APP_019205", core_password="pw-core", plus_app_id="APP_019207",
             plus_password="pw-plus", callback_secret="s" * 48)


def make(handler, **kw):
    sleeps: list[float] = []
    s = ApplinkSettings(_env_file=None, mode="sandbox", **{**CREDS, **kw})
    return HttpClient(s, transport=httpx.MockTransport(handler), sleep=sleeps.append), sleeps


def answer(code, **extra):
    return httpx.Response(200, json={"statusCode": code, "statusDetail": "x", **extra})


def test_posts_json_to_the_right_path_and_reads_the_status_code():
    seen = []

    def handler(req):
        seen.append((req.url.path, req.headers["content-type"], json.loads(req.content)))
        return answer("S1000", baseSize="3")

    c, _ = make(handler)
    r = c.query_base("core")
    assert r.ok and r.get("baseSize") == "3"
    path, ctype, body = seen[0]
    assert path == "/subscription/query-base" and ctype.startswith("application/json")
    assert body == {"applicationId": "APP_019205", "password": "pw-core"}


def test_an_error_inside_http_200_is_an_error():
    c, _ = make(lambda req: answer("E1313"))
    r = c.query_base("core")
    assert not r.ok and r.status_code == "E1313"


def test_transient_codes_are_retried_three_times_with_backoff():
    calls = []

    def handler(req):
        calls.append(1)
        return answer("E1603") if len(calls) < 3 else answer("S1000")

    c, sleeps = make(handler)
    assert c.query_base("core").ok
    assert len(calls) == 3 and len(sleeps) == 2 and sleeps[1] > sleeps[0]


def test_the_daily_limit_is_never_retried():
    calls = []
    c, _ = make(lambda req: calls.append(1) or answer("E1319"))
    assert c.send_sms("core", "tel:8801912345678", "hi").status_code == "E1319"
    assert len(calls) == 1


def test_otp_request_is_retried_once_only():
    calls = []
    c, _ = make(lambda req: calls.append(1) or answer("E1603"))
    assert c.otp_request("core", "tel:8801912345678").status_code == "E1603"
    assert len(calls) == 2


@pytest.mark.parametrize("call", ["debit", "verify"])
def test_the_charging_path_is_never_retried_on_a_code(call):
    calls = []
    c, _ = make(lambda req: calls.append(1) or answer("E1603"))
    if call == "debit":
        c.caas_debit("core", "LMP-1", "tel:8801912345678")
    else:
        c.caas_verify("core", "REF", "123456", "tel:8801912345678")
    assert len(calls) == 1


def test_a_timeout_after_sending_is_never_retried_and_comes_back_unknown():
    calls = []

    def handler(req):
        calls.append(1)
        raise httpx.ReadTimeout("slow", request=req)

    c, _ = make(handler)
    r = c.caas_debit("core", "LMP-1", "tel:8801912345678")
    assert r.timed_out and r.status_code is None and len(calls) == 1
    calls.clear()
    assert c.send_sms("core", "tel:8801912345678", "hi").timed_out and len(calls) == 1


def test_a_connection_that_never_reached_applink_is_retried():
    calls = []

    def handler(req):
        calls.append(1)
        if len(calls) < 3:
            raise httpx.ConnectError("refused", request=req)
        return answer("P1003", requestCorrelator="C1")

    c, _ = make(handler)
    assert c.caas_debit("core", "LMP-1", "tel:8801912345678").status_code == "P1003"
    assert len(calls) == 3


def test_a_page_that_isnt_applink_json_is_unknown_and_passwords_are_dropped():
    c, _ = make(lambda req: httpx.Response(502, text="<html>bad gateway</html>"))
    r = c.query_base("core")
    assert r.status_code is None and not r.ok
    c2, _ = make(lambda req: answer("S1000", password="leaked"))
    assert "password" not in c2.query_base("core").data


def test_sms_recipient_entry_decides_the_result():
    c, _ = make(lambda req: answer("S1000", destinationResponses=[
        {"address": "tel:8801912345678", "statusCode": "E1343", "statusDetail": "not white listed"}]))
    r = c.send_sms("core", "tel:8801912345678", "hi")
    assert r.status_code == "E1343" and not r.ok


def test_factory_gives_demo_shops_the_mock_and_others_the_mode(monkeypatch):
    for k, v in {**{f"APPLINK_{k.upper()}": v for k, v in CREDS.items()}, "APPLINK_MODE": "sandbox"}.items():
        monkeypatch.setenv(k, v)
    monkeypatch.setenv("APPLINK_CALLBACK_SECRET", "s" * 48)
    factory.reset()
    try:
        assert isinstance(factory.client_for("demo"), MockClient)
        assert isinstance(factory.client_for("real"), HttpClient)
        assert factory.client_for("real") is factory.client_for("team_test")
    finally:
        monkeypatch.setenv("APPLINK_MODE", "mock")
        factory.reset()
    assert isinstance(factory.client_for("real"), MockClient)
    factory.reset()
