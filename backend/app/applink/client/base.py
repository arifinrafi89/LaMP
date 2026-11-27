"""What every Applink client shares: the request bodies, their shape check and the reply.

Rules from Applink's API (plan 3, guide 12):
- every value is a JSON string, except destinationAddresses and subscriberIds (lists of
  strings) and applicationMetaData (an object of strings); empty optional fields are left out;
- only /sms/send carries "version"; OTP, Subscription and CaaS don't;
- CaaS spells "Currency" with a capital C;
- success is judged by statusCode, never by the HTTP status.

The client refuses, before any network call, a service the app doesn't have and (in
sandbox) a number that isn't on our own allow-list. Passwords are read from the settings
at send time and never stored in a reply or a log.
"""
import logging
from dataclasses import dataclass, field
from typing import Any

from app.applink import codes, tel
from app.applink.config import AppName, ApplinkSettings

log = logging.getLogger("app.applink")

PATH_SERVICE = {
    "/otp/request": "otp", "/otp/verify": "otp",
    "/subscription/send": "subscription", "/subscription/query-base": "subscription",
    "/subscription/getSubscriberChargingInfo": "subscription",
    "/sms/send": "sms",
    "/caas/direct/debit": "caas", "/caas/otp/verify": "caas",
}
# The charging path is never retried by the client: a timeout there is settled only by
# Applink's charging notification (plan 3.7).
CHARGING_PATHS = frozenset({"/caas/direct/debit", "/caas/otp/verify"})

_REQUIRED = {
    "/otp/request": ("applicationId", "password", "subscriberId"),
    "/otp/verify": ("applicationId", "password", "referenceNo", "otp"),
    "/subscription/send": ("applicationId", "password", "subscriberId", "action"),
    "/subscription/query-base": ("applicationId", "password"),
    "/subscription/getSubscriberChargingInfo": ("applicationId", "password", "subscriberIds"),
    "/sms/send": ("version", "applicationId", "password", "message", "destinationAddresses"),
    "/caas/direct/debit": ("applicationId", "password", "externalTrxId", "amount", "paymentInstrumentName",
                           "subscriberId", "Currency"),
    "/caas/otp/verify": ("applicationId", "password", "referenceNo", "otp", "sourceAddress"),
}
_LISTS = {"destinationAddresses", "subscriberIds"}
_OBJECTS = {"applicationMetaData"}
REDACTED = ("password", "otp", "referenceNo", "requestCorrelator")


class ShapeError(ValueError):
    """Our own request body breaks Applink's rules: a bug in our code, never sent."""


class ServiceNotEnabled(RuntimeError):
    """The app doesn't have this service, so the call is refused locally (instead of E1309)."""


class NotOnAllowList(RuntimeError):
    """Sandbox: the number isn't in APPLINK_ALLOWED_NUMBERS, so nothing is sent."""


def check_shape(path: str, body: dict[str, Any]) -> None:
    """Raise ShapeError if the body isn't what Applink accepts for this path."""
    if path not in _REQUIRED:
        raise ShapeError(f"unknown Applink path {path}")
    missing = [k for k in _REQUIRED[path] if k not in body]
    if missing:
        raise ShapeError(f"{path}: missing {', '.join(missing)}")
    if ("version" in body) != (path == "/sms/send"):
        raise ShapeError(f"{path}: 'version' belongs only on /sms/send")
    if path == "/caas/direct/debit" and "currency" in body:
        raise ShapeError("CaaS needs 'Currency' with a capital C")
    for key, value in body.items():
        if key in _LISTS:
            if not isinstance(value, list) or not value or not all(isinstance(v, str) and v for v in value):
                raise ShapeError(f"{path}: {key} must be a non-empty list of strings")
        elif key in _OBJECTS:
            if not isinstance(value, dict) or not all(isinstance(v, str) for v in value.values()):
                raise ShapeError(f"{path}: {key} must be an object of strings")
        elif not isinstance(value, str) or value == "":
            raise ShapeError(f"{path}: {key} must be a non-empty string")


def _is_address(value: Any) -> bool:
    return isinstance(value, str) and (value.startswith("tel:") or tel.is_plain_number(value))


def address(value: str) -> str:
    """A typed number in Applink's format (tel:8801…); a masked id exactly as Applink sent it."""
    return tel.to_tel(value) if tel.is_plain_number(value) else value.strip()


def redact(body: dict[str, Any]) -> dict[str, Any]:
    """A copy safe to keep or log: secrets and codes replaced, numbers masked."""
    out: dict[str, Any] = {}
    for k, v in body.items():
        if k in REDACTED:
            out[k] = "***"
        elif k in ("subscriberId", "sourceAddress", "address", "destinationAddress") and _is_address(v):
            out[k] = tel.mask(v)  # a short code such as 21213 isn't a person's number
        elif k in _LISTS:
            out[k] = [tel.mask(x) for x in v]
        else:
            out[k] = v
    return out


@dataclass
class Reply:
    """Applink's answer. `status_code` is None only when no answer came (timed_out)."""
    path: str
    status_code: str | None
    status_detail: str = ""
    data: dict[str, Any] = field(default_factory=dict)
    timed_out: bool = False
    ms: int = 0

    @property
    def outcome(self) -> codes.Outcome:
        return codes.classify(self.status_code)

    @property
    def ok(self) -> bool:
        return self.outcome is codes.Outcome.SUCCESS

    def get(self, key: str, default: Any = None) -> Any:
        return self.data.get(key, default)


class ApplinkClient:
    """The calls LaMP makes. Subclasses implement `_post`; everything else is shared."""

    mode = "base"

    def __init__(self, settings: ApplinkSettings):
        self.settings = settings

    # ------------------------------------------------------------- OTP (plan 3.2)
    def otp_request(self, app: AppName, subscriber: str, meta: dict[str, str] | None = None) -> Reply:
        subscriber = address(subscriber)
        body = self._auth(app) | {"subscriberId": subscriber}
        if meta:
            body["applicationMetaData"] = {k: str(v) for k, v in meta.items() if v}
        return self._send(app, "/otp/request", body, subscriber)

    def otp_verify(self, app: AppName, reference_no: str, otp: str) -> Reply:
        return self._send(app, "/otp/verify", self._auth(app) | {"referenceNo": reference_no, "otp": otp})

    # ---------------------------------------------------- Subscription (plan 3.3)
    def subscribe(self, app: AppName, subscriber: str) -> Reply:
        subscriber = address(subscriber)
        return self._send(app, "/subscription/send", self._auth(app) | {"subscriberId": subscriber, "action": "1"},
                          subscriber)

    def unsubscribe(self, app: AppName, subscriber: str) -> Reply:
        subscriber = address(subscriber)
        return self._send(app, "/subscription/send", self._auth(app) | {"subscriberId": subscriber, "action": "0"},
                          subscriber)

    def query_base(self, app: AppName) -> Reply:
        return self._send(app, "/subscription/query-base", self._auth(app))

    def charging_info(self, app: AppName, subscribers: list[str]) -> Reply:
        if not 1 <= len(subscribers) <= 10:
            raise ValueError("getSubscriberChargingInfo takes 1 to 10 subscribers")
        subscribers = [address(s) for s in subscribers]
        return self._send(app, "/subscription/getSubscriberChargingInfo",
                          self._auth(app) | {"subscriberIds": list(subscribers)}, *subscribers)

    # ------------------------------------------------------------- SMS (plan 3.6)
    def send_sms(self, app: AppName, to: str, message: str) -> Reply:
        """One message to one address (we never broadcast). The reply's status is the
        recipient's own entry when Applink gives one, since S1000 overall can hide a failure."""
        to = address(to)
        body = {"version": "1.0"} | self._auth(app) | {
            "message": message, "destinationAddresses": [to], "deliveryStatusRequest": "1"}
        if self.settings.sms_source:
            body["sourceAddress"] = self.settings.sms_source
        reply = self._send(app, "/sms/send", body, to)
        entries = reply.get("destinationResponses") or []
        if reply.ok and entries and isinstance(entries[0], dict) and entries[0].get("statusCode"):
            reply.status_code = str(entries[0]["statusCode"])
            reply.status_detail = str(entries[0].get("statusDetail", reply.status_detail))
        return reply

    # ------------------------------------------------------------ CaaS (plan 3.7)
    def caas_debit(self, app: AppName, external_trx_id: str, subscriber: str) -> Reply:
        """The amount always comes from config (PRICE_CREDIT_RECORD), never from the app."""
        subscriber = address(subscriber)
        body = self._auth(app) | {
            "externalTrxId": external_trx_id, "amount": self.settings.amount_text,
            "paymentInstrumentName": "Mobile Account", "subscriberId": subscriber, "Currency": "BDT"}
        return self._send(app, "/caas/direct/debit", body, subscriber)

    def caas_verify(self, app: AppName, reference_no: str, otp: str, source_address: str) -> Reply:
        source_address = address(source_address)
        body = self._auth(app) | {"referenceNo": reference_no, "otp": otp, "sourceAddress": source_address}
        return self._send(app, "/caas/otp/verify", body, source_address)

    # ------------------------------------------------------------------- shared
    def _auth(self, app: AppName) -> dict[str, str]:
        creds = self.settings.app(app)
        return {"applicationId": creds.app_id, "password": creds.password.get_secret_value()}

    def _send(self, app: AppName, path: str, body: dict[str, Any], *numbers: str) -> Reply:
        if not self.settings.enabled(app, PATH_SERVICE[path]):
            raise ServiceNotEnabled(f"{PATH_SERVICE[path]} isn't enabled for the {app} app")
        allowed = self.settings.allowed if self.mode == "sandbox" else None
        if allowed is not None:
            for n in numbers:
                if tel.is_plain_number(n) and tel.to_tel(n) not in allowed:
                    raise NotOnAllowList(f"{tel.mask(n)} isn't on APPLINK_ALLOWED_NUMBERS")
        check_shape(path, body)
        reply = self._post(app, path, body)
        log.info("applink call app=%s path=%s mode=%s status=%s ms=%d number=%s", app, path, self.mode,
                 reply.status_code or ("timeout" if reply.timed_out else "-"), reply.ms,
                 tel.mask(numbers[0]) if numbers else "-")
        return reply

    def _post(self, app: AppName, path: str, body: dict[str, Any]) -> Reply:  # pragma: no cover
        raise NotImplementedError
