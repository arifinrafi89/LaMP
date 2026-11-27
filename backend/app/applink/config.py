"""Applink settings, read only from the server's environment (build plan 1.2 and 10.2).

Credentials never appear in code, logs or the app bundle: passwords and the callback
secret are SecretStr, so printing the settings can't leak them.

    APPLINK_MODE                mock | sandbox | live (plan 3.9)
    APPLINK_CORE_APP_ID/_PASSWORD, APPLINK_PLUS_APP_ID/_PASSWORD
    APPLINK_CORE_SERVICES       otp,subscription,sms,caas  (a service not listed is refused
    APPLINK_PLUS_SERVICES       otp,subscription            locally instead of failing with E1309)
    APPLINK_SMS_SHORTCODE, APPLINK_SMS_KEYWORD, APPLINK_SMS_SOURCE (empty: leave sourceAddress out)
    APPLINK_MASKING             true while Applink keeps number masking on
    FAMILY_JOIN_ROUTES          text | counter | text,counter (plan 3.4)
    FAMILY_SUBSCRIBE_METHOD     subscription_send | otp_textback | applink_keyword
    APPLINK_ALLOWED_NUMBERS     sandbox allow-list; empty means off
    APPLINK_CALLBACK_SECRET, APPLINK_CALLBACK_IPS
    APPLINK_TPS, APPLINK_TIMEOUT_S, PRICE_CREDIT_RECORD, PRICE_PLUS_TEXT
"""
from dataclasses import dataclass
from decimal import Decimal
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import AliasChoices, Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from app.applink import tel

REPO_ROOT = Path(__file__).resolve().parents[3]

AppName = Literal["core", "plus"]
Service = Literal["otp", "subscription", "sms", "caas"]
SERVICES: tuple[str, ...] = ("otp", "subscription", "sms", "caas")
JOIN_ROUTES: tuple[str, ...] = ("text", "counter")
MIN_SECRET = 32


@dataclass(frozen=True)
class AppCredentials:
    name: str
    app_id: str
    password: SecretStr
    services: frozenset[str]


class ApplinkSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="APPLINK_", env_file=REPO_ROOT / ".env", extra="ignore")

    mode: Literal["mock", "sandbox", "live"] = "mock"
    base_url: str = "https://api.applink.com.bd"

    core_app_id: str = ""
    core_password: SecretStr = SecretStr("")
    core_services: str = "otp,subscription,sms,caas"
    plus_app_id: str = ""
    plus_password: SecretStr = SecretStr("")
    plus_services: str = "otp,subscription"

    sms_shortcode: str = "21213"
    sms_keyword: str = "lamp"
    sms_source: str = ""
    masking: bool = True

    family_join_routes: str = Field("text", validation_alias=AliasChoices("FAMILY_JOIN_ROUTES"))
    family_subscribe_method: Literal["subscription_send", "otp_textback", "applink_keyword"] = Field(
        "subscription_send", validation_alias=AliasChoices("FAMILY_SUBSCRIBE_METHOD"))

    allowed_numbers: str = ""
    callback_secret: SecretStr = SecretStr("")
    callback_ips: str = ""

    tps: int = Field(4, ge=1, le=5)  # Applink allows 5 a second (plan 3.1)
    timeout_s: float = Field(10.0, gt=0, le=60)
    price_credit_record: Decimal = Field(Decimal("10.00"), validation_alias=AliasChoices("PRICE_CREDIT_RECORD"))
    price_plus_text: str = Field("BDT 50 a month + VAT", validation_alias=AliasChoices("PRICE_PLUS_TEXT"))

    @field_validator("core_services", "plus_services")
    @classmethod
    def _known_services(cls, v: str) -> str:
        names = _split(v)
        unknown = names - set(SERVICES)
        if unknown:
            raise ValueError(f"unknown Applink services: {', '.join(sorted(unknown))}")
        return ",".join(s for s in SERVICES if s in names)

    @field_validator("family_join_routes")
    @classmethod
    def _known_routes(cls, v: str) -> str:
        names = _split(v)
        if not names or names - set(JOIN_ROUTES):
            raise ValueError("FAMILY_JOIN_ROUTES must be text, counter or text,counter")
        return ",".join(r for r in JOIN_ROUTES if r in names)

    @field_validator("allowed_numbers")
    @classmethod
    def _numbers(cls, v: str) -> str:
        # Fail at start-up on a typo, not on the first send.
        return ",".join(sorted(tel.to_tel(n) for n in _split(v)))

    @field_validator("price_credit_record")
    @classmethod
    def _allowed_caas_amount(cls, v: Decimal) -> Decimal:
        # The form allows these CaaS amounts only (plan 3.1); anything else fails at Applink.
        if v not in {Decimal("2"), Decimal("5"), Decimal("7"), Decimal("10")}:
            raise ValueError("PRICE_CREDIT_RECORD must be 2, 5, 7 or 10")
        return v.quantize(Decimal("0.01"))

    # ------------------------------------------------------------------ helpers

    def app(self, name: AppName) -> AppCredentials:
        if name == "core":
            return AppCredentials("core", self.core_app_id, self.core_password, frozenset(_split(self.core_services)))
        if name == "plus":
            return AppCredentials("plus", self.plus_app_id, self.plus_password, frozenset(_split(self.plus_services)))
        raise ValueError(f"unknown Applink app: {name}")

    def enabled(self, app: AppName, service: str) -> bool:
        return service in self.app(app).services

    @property
    def join_routes(self) -> frozenset[str]:
        return frozenset(_split(self.family_join_routes))

    @property
    def allowed(self) -> frozenset[str] | None:
        """The sandbox allow-list as tel: addresses, or None when it's off (empty)."""
        names = _split(self.allowed_numbers)
        return frozenset(names) if names else None

    @property
    def amount_text(self) -> str:
        """The credit record's price as Applink wants it: '10.00'."""
        return f"{self.price_credit_record:.2f}"

    def problems(self, app_env: str) -> list[str]:
        """Why this configuration mustn't start, as plain sentences. Empty means fine.

        Mock needs nothing. Sandbox and live need both apps' credentials and a callback secret
        of at least 32 characters. Live also needs APP_ENV=production (plan 3.9).
        """
        out: list[str] = []
        if self.mode == "mock":
            return out
        for name in ("core", "plus"):
            creds = self.app(name)
            if not creds.app_id or not creds.password.get_secret_value():
                out.append(f"APPLINK_{name.upper()}_APP_ID and APPLINK_{name.upper()}_PASSWORD must be set in {self.mode} mode")
        if len(self.callback_secret.get_secret_value()) < MIN_SECRET:
            out.append(f"APPLINK_CALLBACK_SECRET must be at least {MIN_SECRET} characters in {self.mode} mode")
        if self.mode == "live" and app_env != "production":
            out.append("APPLINK_MODE=live needs APP_ENV=production")
        if self.mode == "live" and self.allowed is not None:
            out.append("APPLINK_ALLOWED_NUMBERS must be empty in live mode")
        if "counter" in self.join_routes and self.masking:
            out.append("FAMILY_JOIN_ROUTES can't include counter while APPLINK_MASKING is on")
        return out


def _split(value: str) -> set[str]:
    return {part.strip().lower() for part in value.split(",") if part.strip()}


@lru_cache
def get_settings() -> ApplinkSettings:
    return ApplinkSettings()
