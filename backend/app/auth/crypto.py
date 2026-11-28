"""The owner's number and Applink's references, kept so a leaked database shows neither.

- `phone_hash`: an HMAC of the number with PHONE_PEPPER, to find the owner at sign-in.
- `seal` / `unseal`: AES-GCM with a key from PII_KEY, for what must be read back (the
  owner's number, to send the Plus OTP; Applink's OTP reference, to verify the code).
  A sealed value looks like "v1.<base64url(nonce + ciphertext)>".
"""
import base64
import hashlib
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.applink import tel
from app.auth.config import get_settings

_VERSION = "v1"


def phone_hash(phone: str) -> str:
    return tel.hmac_hash(phone, get_settings().secret("phone_pepper"))


def _aes() -> AESGCM:
    return AESGCM(hashlib.sha256(get_settings().secret("pii_key").encode()).digest())


def seal(text: str, *, purpose: str) -> str:
    """Encrypt `text`. `purpose` is bound in, so a value sealed for one column can't be
    pasted into another and read back."""
    nonce = os.urandom(12)
    ct = _aes().encrypt(nonce, text.encode(), purpose.encode())
    return f"{_VERSION}.{base64.urlsafe_b64encode(nonce + ct).decode().rstrip('=')}"


def unseal(token: str, *, purpose: str) -> str:
    version, _, data = token.partition(".")
    if version != _VERSION or not data:
        raise ValueError("not a sealed value")
    raw = base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))
    return _aes().decrypt(raw[:12], raw[12:], purpose.encode()).decode()
