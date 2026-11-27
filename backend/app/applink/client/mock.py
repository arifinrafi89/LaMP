"""The in-process mock of Applink (build plan 3.9).

Used on laptops, in CI, in production until Applink approves the apps, and for every
demo shop even in production. No network. Every request body is checked the way the
platform checks it (check_shape), so a malformed body fails the test that sent it.

Scenarios, keyed on the last two digits of the real number:

    01  the first OTP check fails (E1850), the next right code passes
    02  the OTP has expired (E1851)
    03  not enough balance on the CaaS debit (E1326)
    04  the CaaS charging notification says failed
    05  the CaaS debit times out; the charging notification then says paid
    06  the number isn't whitelisted (E1343) on every call
    07  REG_PENDING first, REGISTERED by notification
    08  E1603 twice for each call, then S1000
    09  LaMP Plus is registered, then TEMPORARY_BLOCKED by notification
    10  a text from this number goes missing unless it is subscribed (plan 3.4 step 5)
    11  /subscription/send is refused (the subscribe-method switch, plan 3.4 step 3)

Any other number takes the happy path. The OTP is always 123456.

With APPLINK_MASKING on (the default, as in our form), the mock hands out masked
addresses: a stable hash per number, different in each app, as Applink may do.

`callbacks` collects what Applink would post back to us (subscription and charging
notifications, delivery reports); `drain()` hands them over and clears the list. Every
call is kept in `sent`, with secrets redacted.
"""
import hashlib
import itertools
import time
from collections.abc import Callable
from typing import Any

from app.applink import codes, tel
from app.applink.client.base import ApplinkClient, Reply, redact
from app.applink.config import AppName, ApplinkSettings

OTP = "123456"
OTP_LIFETIME_S = 300


class MockClient(ApplinkClient):
    mode = "mock"

    def __init__(self, settings: ApplinkSettings, *, clock: Callable[[], float] = time.time):
        super().__init__(settings)
        self._clock = clock
        self._seq = itertools.count(1)
        self.sent: list[tuple[str, str, dict[str, Any]]] = []
        self.callbacks: list[tuple[str, str, dict[str, Any]]] = []
        self._numbers: dict[str, str] = {}             # address -> real tel: number
        self._otps: dict[str, dict[str, Any]] = {}       # referenceNo -> challenge
        self._charges: dict[str, dict[str, Any]] = {}    # requestCorrelator -> charge
        self._subs: dict[tuple[str, str], str] = {}      # (app, address) -> status
        self._flaky: dict[tuple[str, str], int] = {}     # (path, number) -> E1603s given

    # ----------------------------------------------------------- addresses
    def address(self, app: AppName, number: str) -> str:
        """How Applink would show this number to the app: masked, or plain if masking is off."""
        real = tel.to_tel(number)
        if not self.settings.masking:
            self._numbers[real] = real
            return real
        masked = "tel:MASK" + hashlib.sha256(f"{app}:{real}".encode()).hexdigest()[:24].upper()
        self._numbers[masked] = real
        return masked

    def _real(self, address: str | None) -> str:
        if not address:
            return ""
        if address in self._numbers:
            return self._numbers[address]
        return tel.to_tel(address) if tel.is_plain_number(address) else address

    @staticmethod
    def _scenario(number: str) -> str:
        """The last two digits of a real number; masked ids this mock didn't make have none."""
        if not number or not tel.is_plain_number(number):
            return ""
        return tel.local_digits(number)[-2:]

    def _auth(self, app: AppName) -> dict[str, str]:
        creds = self.settings.app(app)
        return {"applicationId": creds.app_id or f"APP_MOCK_{app.upper()}",
                "password": creds.password.get_secret_value() or "mock-password"}

    # ------------------------------------------------------------- the platform
    def _post(self, app: AppName, path: str, body: dict[str, Any]) -> Reply:
        self.sent.append((app, path, redact(body)))
        if path == "/sms/send":
            number = self._real(body["destinationAddresses"][0])  # sourceAddress is our short code
        else:
            number = self._real(body.get("subscriberId") or body.get("sourceAddress"))
        if path == "/otp/verify":
            number = (self._otps.get(body["referenceNo"]) or {}).get("number", "")
        elif path == "/caas/otp/verify":
            number = (self._charges.get(body["referenceNo"]) or {}).get("number", number)
        sc = self._scenario(number)
        if sc == "06":
            return self._reply(path, "E1343")
        if sc == "08":
            key = (path, number)
            self._flaky[key] = self._flaky.get(key, 0) + 1
            if self._flaky[key] <= 2:
                return self._reply(path, "E1603")
        handler = getattr(self, "_" + path.strip("/").replace("/", "_").replace("-", "_"))
        return handler(app, body, number, sc)

    def _otp_request(self, app, body, number, sc):
        ref = f"MOCKREF{next(self._seq):06d}"
        self._otps[ref] = {"app": app, "number": number, "created": self._clock(), "first_fail": sc == "01"}
        return self._reply("/otp/request", "S1000", referenceNo=ref, version="1.0")

    def _otp_verify(self, app, body, number, sc):
        ch = self._otps.get(body["referenceNo"])
        if ch is None or ch["app"] != app:
            return self._reply("/otp/verify", "E1855")
        if sc == "02" or self._clock() - ch["created"] > OTP_LIFETIME_S:
            return self._reply("/otp/verify", "E1851")
        if ch["first_fail"]:
            ch["first_fail"] = False
            return self._reply("/otp/verify", "E1850")
        if body["otp"] != OTP:
            return self._reply("/otp/verify", "E1850")
        del self._otps[body["referenceNo"]]
        address = self.address(app, number)
        status = self._register(app, address, number, sc)
        return self._reply("/otp/verify", "S1000", subscriptionStatus=status, subscriberId=address)

    def _subscription_send(self, app, body, number, sc):
        if sc == "11":
            return self._reply("/subscription/send", "E1309")
        address = body["subscriberId"] if not tel.is_plain_number(body["subscriberId"]) else self.address(app, number)
        if body["action"] == "0":
            self._subs[(app, address)] = "UNREGISTERED"
            self._notify(app, address, "UNREGISTERED")
            return self._reply("/subscription/send", "S1000", subscriptionStatus="UNREGISTERED", version="1.0")
        status = self._register(app, address, number, sc)
        return self._reply("/subscription/send", "S1000", subscriptionStatus=status + ".", version="1.0")

    def _subscription_query_base(self, app, body, number, sc):
        size = sum(1 for (a, _), s in self._subs.items() if a == app and s in codes.ACTIVE_STATUSES)
        return self._reply("/subscription/query-base", "S1000", baseSize=str(size), version="1.0")

    def _subscription_getSubscriberChargingInfo(self, app, body, number, sc):
        price = "50.00 BDT" if app == "plus" else "0.00 BDT"
        rows = []
        for address in body["subscriberIds"]:
            status = self._subs.get((app, address), "UNREGISTERED")
            rows.append({"subscriberId": address, "subscriptionStatus": status, "numberType": "prepaid",
                         "lastChargedAmount": price if status in codes.ACTIVE_STATUSES else "0.00 BDT",
                         "lastChargedDate": self._stamp("%Y-%m-%d %H:%M:%S"),
                         "statusCode": "S1000", "statusDetail": "Request was successfully processed"})
        return self._reply("/subscription/getSubscriberChargingInfo", "S1000", destinationResponses=rows,
                           version="1.0")

    def _sms_send(self, app, body, number, sc):
        address = body["destinationAddresses"][0]
        request_id = f"MOCKSMS{next(self._seq):06d}"
        entry = {"timeStamp": self._stamp("%y%m%d%H%M"), "address": address, "messageId": request_id,
                 "statusCode": "S1000", "statusDetail": "Success"}
        if body.get("deliveryStatusRequest") == "1":
            self.callbacks.append((app, "sms/report", {
                "destinationAddress": address, "timeStamp": self._stamp("%y%m%d%H%M"),
                "requestId": request_id, "deliveryStatus": "DELIVERED"}))
        return self._reply("/sms/send", "S1000", requestId=request_id, destinationResponses=[entry], version="1.0")

    def _caas_direct_debit(self, app, body, number, sc):
        if sc == "03":
            return self._reply("/caas/direct/debit", "E1326")
        corr = f"MOCKCORR{next(self._seq):08d}"
        charge = {"app": app, "number": number, "address": body["subscriberId"], "amount": body["amount"],
                  "externalTrxId": body["externalTrxId"], "internalTrxId": f"MOCKTRX{next(self._seq):08d}"}
        self._charges[corr] = charge
        if sc == "05":
            self._charging_notification(app, charge, corr, paid=True)
            return Reply("/caas/direct/debit", None, "no answer from Applink", timed_out=True)
        return self._reply("/caas/direct/debit", "P1003", requestCorrelator=corr,
                           internalTrxId=charge["internalTrxId"], externalTrxId=charge["externalTrxId"],
                           timeStamp=self._stamp("%Y-%m-%dT%H:%M:%S.000Z"))

    def _caas_otp_verify(self, app, body, number, sc):
        charge = self._charges.get(body["referenceNo"])
        if charge is None or charge["app"] != app:
            return self._reply("/caas/otp/verify", "E1855")
        if body["otp"] != OTP:
            return self._reply("/caas/otp/verify", "E1850")
        self._charging_notification(app, charge, body["referenceNo"], paid=sc != "04")
        return self._reply("/caas/otp/verify", "S1000", externalTrxId=charge["externalTrxId"],
                           internalTrxId=charge["internalTrxId"], version="1.0")

    # ------------------------------------------------------------ helpers
    def _register(self, app: str, address: str, number: str, sc: str) -> str:
        if sc == "07":
            self._subs[(app, address)] = "REG_PENDING"
            self._notify(app, address, "REGISTERED")
            return "REG_PENDING"
        self._subs[(app, address)] = "REGISTERED"
        self._notify(app, address, "REGISTERED")
        if sc == "09" and app == "plus":
            self._notify(app, address, "TEMPORARY_BLOCKED")
        return "REGISTERED"

    def _notify(self, app: str, address: str, status: str) -> None:
        # Applink's real notification carries the app's password; ours does too, so the
        # callback handler's redaction is tested against the real shape.
        self.callbacks.append((app, "subscription/notify", {
            "timeStamp": self._stamp("%Y%m%d%H%M%S"), "version": "1.0", **self._auth(app),
            "subscriberId": address, "frequency": "monthly", "status": status}))

    def _charging_notification(self, app: str, charge: dict[str, Any], corr: str, *, paid: bool) -> None:
        self.callbacks.append((app, "caas/notify", {
            "timeStamp": self._stamp("%d-%b-%Y %H:%M"), "TotalAmount": charge["amount"],
            "externalTrxId": charge["externalTrxId"], "balanceDue": "0" if paid else charge["amount"],
            "statusDetail": "Request was Successfully processed, Due amount fully paid." if paid
            else codes.DETAIL["E1308"],
            "currency": "BDT", "version": "1.0", "internalTrxId": charge["internalTrxId"],
            "paidAmount": charge["amount"] if paid else "0.00", "referenceId": corr,
            "statusCode": "S1000" if paid else "E1308"}))

    def _reply(self, path: str, code: str, **data: Any) -> Reply:
        data = {"statusCode": code, "statusDetail": codes.DETAIL.get(code, ""), **data}
        return Reply(path, code, data["statusDetail"], data=data)

    def _stamp(self, fmt: str) -> str:
        return time.strftime(fmt, time.gmtime(self._clock()))

    # ------------------------------------------------- driving it from tests
    def incoming_sms(self, app: AppName, number: str, text: str) -> dict[str, Any] | None:
        """What Applink would post to /sms/receive when this number texts 21213, or None if
        the text goes missing (scenario 10, a non-subscriber)."""
        address = self.address(app, number)
        if self._scenario(tel.to_tel(number)) == "10" and \
                self._subs.get((app, address)) not in codes.ACTIVE_STATUSES:
            return None
        return {"version": "1.0", "applicationId": self._auth(app)["applicationId"], "sourceAddress": address,
                "message": text, "requestId": f"MOCKMO{next(self._seq):06d}", "encoding": "0"}

    def drain(self) -> list[tuple[str, str, dict[str, Any]]]:
        out, self.callbacks = self.callbacks, []
        return out
