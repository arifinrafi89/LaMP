from typing import Literal

from .common import ISODate, Model


class PharmacySettings(Model):
    gross_margin_pct: float
    cash_buffer: float
    expiry_buffer_days: int
    as_of_date: ISODate | None = None  # demo and team-test shops only (plan 0.6)


class PharmacyOut(Model):
    id: str
    name: str
    city: str
    settings: PharmacySettings
    asks_pin: bool = False  # the app asks the owner PIN (ASK_OWNER_PIN)
    kind: Literal["real", "demo", "team_test"] = "real"
    setup_complete: bool = False
    card_prefix: str | None = None
