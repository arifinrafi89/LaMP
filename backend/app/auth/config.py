"""Sign-in settings, read only from the server's environment (build plan 2.1, 10.2).

    APP_ENV          dev | staging | production
    JWT_SECRET       signs the 15-minute access tokens
    PHONE_PEPPER     keys the hash that finds an owner by number (never stored in the clear)
    PII_KEY          encrypts the owner's number and Applink's OTP reference (AES-GCM)
    DEMO_ENABLED, DEMO_CODE   the judges' demo shop sign-in (POST /auth/demo, plan D12)
    PROXY_HOPS       proxies in front of the server that add X-Forwarded-For (Render: 1)

With DEV_MODE on, empty secrets fall back to fixed dev values so a fresh copy runs; with
DEV_MODE off each must be a real random string of at least 32 characters, or the server
refuses to start. DEV_MODE on with APP_ENV=production refuses to start too.
"""
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[3]
MIN_SECRET = 32
SECRETS = ("jwt_secret", "phone_pepper", "pii_key")
_DEV_VALUES = {name: f"dev-only-{name}-not-for-any-real-shop" for name in SECRETS}


class AuthSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=REPO_ROOT / ".env", extra="ignore")

    app_env: Literal["dev", "staging", "production"] = "dev"
    dev_mode: bool = False
    jwt_secret: SecretStr = SecretStr("")
    phone_pepper: SecretStr = SecretStr("")
    pii_key: SecretStr = SecretStr("")
    demo_enabled: bool = False
    demo_code: SecretStr = SecretStr("")
    access_minutes: int = 15
    refresh_days: int = 30
    proxy_hops: int = 0

    def secret(self, name: str) -> str:
        """A secret's value; the fixed dev value only while DEV_MODE is on."""
        value = getattr(self, name).get_secret_value()
        if value:
            return value
        if self.dev_mode:
            return _DEV_VALUES[name]
        raise RuntimeError(f"{name.upper()} is not set. Set it in the server's environment (a random string "
                           f"of at least {MIN_SECRET} characters), or run with DEV_MODE=true.")

    def problems(self) -> list[str]:
        """What stops the server starting. Names only, never values."""
        out = []
        if self.dev_mode and self.app_env == "production":
            out.append("DEV_MODE=true with APP_ENV=production")
        for name in SECRETS:
            value = getattr(self, name).get_secret_value()
            if not value and not self.dev_mode:
                out.append(f"{name.upper()} is not set")
            elif value and len(value) < MIN_SECRET:
                out.append(f"{name.upper()} is shorter than {MIN_SECRET} characters")
        if self.demo_enabled and len(self.demo_code.get_secret_value()) < 6:
            out.append("DEMO_ENABLED is on but DEMO_CODE is shorter than 6 characters")
        return out


@lru_cache
def get_settings() -> AuthSettings:
    return AuthSettings()


def check() -> None:
    """Called at start-up: refuse to run with a broken sign-in setup."""
    if problems := get_settings().problems():
        raise RuntimeError("Sign-in settings: " + "; ".join(problems))
