"""Phone numbers and Applink addresses (build plan 1.2, 3 and 13.1).

Applink addresses look like ``tel:8801912345678``. With number masking on (it is
locked on in our form), Applink sends back an opaque id instead, such as
``tel:B%3C4d...``; those are stored exactly as received and never parsed.

Only numbers people type (an owner at sign-in, a family at the counter) go
through ``to_tel``. Logs only ever see ``mask``.
"""
import hashlib
import hmac
import re

_DIGITS = re.compile(r"\d+")
_TYPED = re.compile(r"^[\d\s+\-().]+$")
# A Bangladeshi mobile number: 01 then an operator digit 3-9, then 8 digits.
_BD_MOBILE = re.compile(r"^01[3-9]\d{8}$")
# Banglalink's prefixes (plan 1.3: phone_number.dart, Banglalink 019/014 only).
_BANGLALINK = ("019", "014")


class InvalidNumber(ValueError):
    """The text isn't a Bangladeshi mobile number."""


def local_digits(phone: str) -> str:
    """'+880 1912-345678', '8801912345678', 'tel:8801…', '01912345678' -> '01912345678'."""
    text = phone.strip()
    if text.lower().startswith("tel:"):
        text = text[4:]
    # Only digits and the usual separators; anything else (a masked id) isn't a number,
    # even if it happens to contain eleven digits in a row.
    if not _TYPED.match(text):
        raise InvalidNumber("not a Bangladeshi mobile number")
    digits = "".join(_DIGITS.findall(text))
    if digits.startswith("880"):
        digits = "0" + digits[3:]
    if not _BD_MOBILE.match(digits):
        raise InvalidNumber("not a Bangladeshi mobile number")
    return digits


def to_tel(phone: str) -> str:
    """Applink's format: 'tel:8801912345678' (no plus, no spaces)."""
    return "tel:88" + local_digits(phone)


def is_banglalink(phone: str) -> bool:
    """True for a Banglalink number (019 or 014). False for anything else, valid or not."""
    try:
        return local_digits(phone).startswith(_BANGLALINK)
    except InvalidNumber:
        return False


def is_plain_number(address: str) -> bool:
    """True if an Applink address is a real number, False for a masked id."""
    try:
        local_digits(address)
        return True
    except InvalidNumber:
        return False


def mask(address: str | None) -> str:
    """A form safe for logs and screens.

    'tel:8801912345678' -> '+880 19•• ••• 678'; a masked id keeps only its last 4 characters.
    """
    if not address:
        return "-"
    try:
        d = local_digits(address)
    except InvalidNumber:
        tail = address.strip()[-4:]
        return f"masked…{tail}"
    return f"+880 {d[1:3]}•• ••• {d[-3:]}"


def hmac_hash(address: str, pepper: str) -> str:
    """A stable, keyed hash for finding a number without storing it in the clear.

    Real numbers are normalised first, so '+880 1912…' and '01912…' hash the same.
    """
    if not pepper:
        raise ValueError("PHONE_PEPPER is not set")
    key = to_tel(address) if is_plain_number(address) else address.strip()
    return hmac.new(pepper.encode(), key.encode(), hashlib.sha256).hexdigest()
