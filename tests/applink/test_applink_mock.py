"""The mock's scenarios (client/mock.py, build plan 3.9)."""
import pytest

from app.applink.client.mock import MockClient
from app.applink.config import ApplinkSettings

HAPPY = "01912345600"


class Clock:
    def __init__(self):
        self.now = 1_800_000_000.0

    def __call__(self):
        return self.now


@pytest.fixture
def clock():
    return Clock()


def client(clock, **kw) -> MockClient:
    return MockClient(ApplinkSettings(_env_file=None, **kw), clock=clock)


def number(last_two: str) -> str:
    return "tel:88019123456" + last_two


def sign_in(c: MockClient, n: str, code: str = "123456"):
    ref = c.otp_request("core", n).get("referenceNo")
    return ref, c.otp_verify("core", ref, code)


def test_happy_sign_in_gives_a_masked_id_and_a_registered_notification(clock):
    c = client(clock)
    _, r = sign_in(c, HAPPY)
    assert r.ok and r.get("subscriptionStatus") == "REGISTERED"
    assert r.get("subscriberId").startswith("tel:MASK") and "1912345600" not in r.get("subscriberId")
    [(app, kind, payload)] = c.drain()
    assert (app, kind, payload["status"]) == ("core", "subscription/notify", "REGISTERED")
    assert payload["subscriberId"] == r.get("subscriberId")
    assert "password" in payload  # Applink's notification carries it; the handler must drop it


def test_masked_ids_are_stable_per_app_and_differ_between_apps(clock):
    c = client(clock)
    assert c.address("core", HAPPY) == c.address("core", "+880 1912-345600")
    assert c.address("core", HAPPY) != c.address("plus", HAPPY)
    assert client(clock, masking=False).address("core", HAPPY) == "tel:8801912345600"


def test_wrong_code_then_right_code(clock):
    c = client(clock)
    ref, r = sign_in(c, number("01"))
    assert r.status_code == "E1850"
    assert c.otp_verify("core", ref, "123456").ok


def test_any_wrong_code_is_refused(clock):
    c = client(clock)
    ref, r = sign_in(c, HAPPY, code="000000")
    assert r.status_code == "E1850"


def test_expired_code(clock):
    c = client(clock)
    assert sign_in(c, number("02"))[1].status_code == "E1851"
    ref = c.otp_request("core", HAPPY).get("referenceNo")
    clock.now += 301
    assert c.otp_verify("core", ref, "123456").status_code == "E1851"


def test_unknown_reference(clock):
    assert client(clock).otp_verify("core", "NOPE", "123456").status_code == "E1855"


def test_not_whitelisted_on_every_call(clock):
    c = client(clock)
    assert c.otp_request("core", number("06")).status_code == "E1343"
    assert c.send_sms("core", number("06"), "hi").status_code == "E1343"


def test_flaky_twice_then_fine(clock):
    c = client(clock)
    assert [c.query_base("core").status_code for _ in range(1)] == ["S1000"]  # no number: never flaky
    codes_seen = [c.send_sms("core", number("08"), "hi").status_code for _ in range(3)]
    assert codes_seen == ["E1603", "E1603", "S1000"]


def test_reg_pending_then_registered(clock):
    c = client(clock)
    r = c.subscribe("core", number("07"))
    assert r.get("subscriptionStatus") == "REG_PENDING."
    assert [p["status"] for _, _, p in c.drain()] == ["REGISTERED"]


def test_plus_blocked_after_registering(clock):
    c = client(clock)
    c.subscribe("plus", number("09"))
    assert [p["status"] for _, _, p in c.drain()] == ["REGISTERED", "TEMPORARY_BLOCKED"]


def test_subscription_send_refused(clock):
    assert client(clock).subscribe("core", number("11")).status_code == "E1309"


def test_unsubscribe_and_base_size(clock):
    c = client(clock)
    c.subscribe("core", HAPPY)
    c.subscribe("core", number("55"))
    assert c.query_base("core").get("baseSize") == "2"
    c.unsubscribe("core", c.address("core", HAPPY))
    assert c.query_base("core").get("baseSize") == "1"
    info = c.charging_info("core", [c.address("core", HAPPY), c.address("core", number("55"))])
    assert [row["subscriptionStatus"] for row in info.get("destinationResponses")] == ["UNREGISTERED", "REGISTERED"]


def test_sms_gives_a_message_id_and_a_delivery_report(clock):
    c = client(clock)
    r = c.send_sms("core", c.address("core", HAPPY), "hi")
    assert r.ok and r.get("destinationResponses")[0]["messageId"]
    [(_, kind, report)] = c.drain()
    assert kind == "sms/report" and report["deliveryStatus"] == "DELIVERED"
    assert report["requestId"] == r.get("requestId")


def test_credit_record_charge_paid(clock):
    c = client(clock)
    debit = c.caas_debit("core", "LMP-1", HAPPY)
    assert debit.status_code == "P1003"  # nothing charged yet
    assert c.caas_verify("core", debit.get("requestCorrelator"), "999999", HAPPY).status_code == "E1850"
    assert c.drain() == []  # a wrong code moves no money
    assert c.caas_verify("core", debit.get("requestCorrelator"), "123456", HAPPY).ok
    [(_, kind, n)] = c.drain()
    assert kind == "caas/notify" and n["statusCode"] == "S1000" and n["paidAmount"] == "10.00"
    assert n["externalTrxId"] == "LMP-1" and n["referenceId"] == debit.get("requestCorrelator")


def test_credit_record_low_balance(clock):
    assert client(clock).caas_debit("core", "LMP-2", number("03")).status_code == "E1326"


def test_credit_record_notification_says_failed(clock):
    c = client(clock)
    debit = c.caas_debit("core", "LMP-3", number("04"))
    c.caas_verify("core", debit.get("requestCorrelator"), "123456", number("04"))
    [(_, _, n)] = c.drain()
    assert n["statusCode"] != "S1000" and n["paidAmount"] == "0.00"


def test_credit_record_debit_times_out_then_the_notification_says_paid(clock):
    c = client(clock)
    debit = c.caas_debit("core", "LMP-4", number("05"))
    assert debit.timed_out and debit.status_code is None
    [(_, kind, n)] = c.drain()
    assert kind == "caas/notify" and n["statusCode"] == "S1000" and n["externalTrxId"] == "LMP-4"


def test_incoming_text_and_the_non_subscriber_that_goes_missing(clock):
    c = client(clock)
    mo = c.incoming_sms("core", HAPPY, "LAMP GL7KQM4XPA")
    assert mo["message"] == "LAMP GL7KQM4XPA" and mo["sourceAddress"] == c.address("core", HAPPY)
    assert c.incoming_sms("core", number("10"), "LAMP GL7KQM4XPA") is None
    c.subscribe("core", number("10"))
    assert c.incoming_sms("core", number("10"), "LAMP") is not None


def test_nothing_secret_is_kept_in_the_call_log(clock):
    c = client(clock, core_password="real-secret")
    sign_in(c, HAPPY)
    assert "real-secret" not in str(c.sent) and "123456" not in str(c.sent)
