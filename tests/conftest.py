"""Shared test setup.

Tests run with DEV_MODE on (demo controls and the dev registry key); the test for
DEV_MODE off switches it off itself. Crash-alert email is off: tests never call Brevo.
The loan-approval PIN is on, so its tests run; tests/api/test_no_pin.py switches it off.
Owners sign in with a bearer token (app.auth); `owner_headers` makes one for any shop.
"""

import os
import uuid

import pytest

os.environ.setdefault("DEV_MODE", "true")
os.environ["BREVO_API_KEY"] = ""
os.environ["ASK_OWNER_PIN"] = "true"


@pytest.fixture
def owner_headers():
    """`make(db, pid)`: Authorization headers for that shop's owner, through a real device
    session (the way /auth/demo signs the demo shop in)."""

    def make(db, pid: str = "green-life") -> dict[str, str]:
        from app.auth import sessions, signin

        owner = signin.shop_owner(db, pid)
        s, _ = sessions.create(db, owner, {"id": f"test-{uuid.uuid4().hex[:8]}", "name": "Test phone",
                                           "os": "android", "app_version": "test"})
        token, _ = sessions.access_for(db, owner, s)
        db.commit()
        return {"Authorization": f"Bearer {token}"}

    return make
