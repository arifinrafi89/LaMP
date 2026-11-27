"""Request bodies, shape rules and local refusals shared by every client (client/base.py)."""
import pytest

from app.applink.client.base import ServiceNotEnabled, NotOnAllowList, ShapeError, check_shape, redact
from app.applink.client.mock import MockClient
from app.applink.config import ApplinkSettings


def settings(**kw) -> ApplinkSettings:
    return ApplinkSettings(_env_file=None, **kw)


def mock(**kw) -> MockClient:
    return MockClient(settings(**kw), clock=lambda: 1_800_000_000.0)


def last_body(client: MockClient) -> dict:
    return client.sent[-1][2]


def test_every_call_builds_a_body_applink_accepts():
    c = mock()
    ref = c.otp_request("core", "tel:8801912345678", meta={"client": "MOBILEAPP", "os": "android"}).get("referenceNo")
    c.otp_verify("core", ref, "123456")
    c.subscribe("core", "tel:8801912345678")
    c.unsubscribe("core", "tel:8801912345678")
    c.query_base("core")
    c.charging_info("core", ["tel:8801912345678"])
    c.send_sms("core", "tel:8801912345678", "Green Life Pharmacy: you owe BDT 4,875.")
    corr = c.caas_debit("core", "LMP-20261127-AAAA", "tel:8801912345678").get("requestCorrelator")
    c.caas_verify("core", corr, "123456", "tel:8801912345678")
    paths = [p for _, p, _ in c.sent]
    assert paths == ["/otp/request", "/otp/verify", "/subscription/send", "/subscription/send",
                     "/subscription/query-base", "/subscription/getSubscriberChargingInfo", "/sms/send",
                     "/caas/direct/debit", "/caas/otp/verify"]


def test_sms_body_is_one_address_in_a_list_with_version_and_a_delivery_report():
    c = mock()
    c.send_sms("core", "tel:8801912345678", "hello")
    body = last_body(c)
    assert body["version"] == "1.0"
    assert isinstance(body["destinationAddresses"], list) and len(body["destinationAddresses"]) == 1
    assert body["deliveryStatusRequest"] == "1"
    assert "sourceAddress" not in body  # left out until Applink confirms 21213 (Q8)


def test_source_address_is_sent_only_when_configured():
    c = mock(sms_source="21213")
    c.send_sms("core", "tel:8801912345678", "hello")
    assert last_body(c)["sourceAddress"] == "21213"


def test_caas_amount_comes_from_config_with_a_capital_c_currency():
    c = mock(price_credit_record="5")
    c.caas_debit("core", "LMP-1", "tel:8801912345678")
    body = last_body(c)
    assert body["amount"] == "5.00" and body["Currency"] == "BDT"
    assert body["paymentInstrumentName"] == "Mobile Account"
    assert "version" not in body


@pytest.mark.parametrize("path,body,why", [
    ("/otp/request", {"applicationId": "A", "password": "p", "subscriberId": "t", "version": "1.0"}, "version"),
    ("/sms/send", {"applicationId": "A", "password": "p", "message": "m", "destinationAddresses": ["t"]}, "missing"),
    ("/sms/send", {"version": "1.0", "applicationId": "A", "password": "p", "message": "m",
                   "destinationAddresses": "tel:8801912345678"}, "list"),
    ("/caas/direct/debit", {"applicationId": "A", "password": "p", "externalTrxId": "x", "amount": 10,
                            "paymentInstrumentName": "Mobile Account", "subscriberId": "t", "Currency": "BDT"},
     "string"),
    ("/caas/direct/debit", {"applicationId": "A", "password": "p", "externalTrxId": "x", "amount": "10.00",
                            "paymentInstrumentName": "Mobile Account", "subscriberId": "t", "currency": "BDT"},
     "missing"),
    ("/subscription/send", {"applicationId": "A", "password": "p", "subscriberId": "", "action": "1"}, "string"),
    ("/ussd/send", {}, "unknown"),
])
def test_bad_bodies_never_leave_the_server(path, body, why):
    with pytest.raises(ShapeError, match=why):
        check_shape(path, body)


def test_a_service_the_app_lacks_is_refused_before_any_call():
    c = mock()
    with pytest.raises(ServiceNotEnabled):
        c.send_sms("plus", "tel:8801912345678", "hello")
    assert c.sent == []


def test_sandbox_allow_list_refuses_other_numbers_but_not_masked_ids():
    c = mock(allowed_numbers="01912345678")
    c.mode = "sandbox"  # the allow-list applies only to the real client in sandbox
    c.send_sms("core", "tel:8801912345678", "hello")
    c.send_sms("core", "tel:MASKABCDEF", "hello")  # masked ids come from Applink itself
    with pytest.raises(NotOnAllowList):
        c.send_sms("core", "tel:8801712345678", "hello")
    assert len(c.sent) == 2


def test_redaction_hides_secrets_codes_and_numbers():
    shown = redact({"applicationId": "APP_1", "password": "pw", "otp": "123456", "referenceNo": "R",
                    "subscriberId": "tel:8801912345678", "destinationAddresses": ["tel:8801912345678"]})
    assert shown["password"] == shown["otp"] == shown["referenceNo"] == "***"
    assert shown["applicationId"] == "APP_1"
    assert "1912345" not in str(shown)


def test_credentials_come_from_settings_and_the_mock_has_placeholders():
    c = mock(core_app_id="APP_019205", core_password="real-secret")
    c.query_base("core")
    assert last_body(c)["applicationId"] == "APP_019205"
    assert last_body(c)["password"] == "***"
    assert mock().sent == [] and mock()._auth("plus")["applicationId"] == "APP_MOCK_PLUS"


def test_typed_numbers_are_sent_in_applinks_format_and_masked_ids_untouched():
    c = mock()
    c.send_sms("core", "01912345678", "hello")
    c.subscribe("core", "tel:MASKABCDEF")
    assert c.sent[-2][2]["destinationAddresses"] == ["+880 19•• ••• 678"]
    assert c.sent[-1][2]["subscriberId"] == "masked…CDEF"
    assert redact({"subscriberId": "01912345678", "sourceAddress": "21213"}) == {
        "subscriberId": "+880 19•• ••• 678", "sourceAddress": "21213"}
