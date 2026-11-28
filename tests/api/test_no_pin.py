"""With ASK_OWNER_PIN off (the shared demo): loan approvals don't ask for the PIN.
Everything else stays closed as before."""

import pytest

from app.config import settings
from api_support import lender_headers

P = "/api/v1/pharmacies/green-life"


@pytest.fixture
def no_pin(monkeypatch):
    monkeypatch.setattr(settings, "ask_owner_pin", False)


def test_the_pharmacy_says_no_pin(client, no_pin):
    assert client.get(P).json()["asks_pin"] is False


def test_still_closed_without_a_session(anon, no_pin):
    assert anon.get(f"{P}/passport").status_code == 401
    assert anon.get(f"{P}/passport", headers=lender_headers()).status_code == 403


def test_loan_approval_needs_no_pin(client, no_pin):
    client.post(f"{P}/consents", json={"lender_id": "wallet-lender"})
    a = client.post(f"{P}/actions", json={"kind": "loan_application", "payload": {
        "lender_id": "wallet-lender", "product_key": "wallet_loan", "amount": 8200}}).json()
    assert a["requires_pin"] is False
    r = client.post(f"{P}/actions/{a['id']}/approve")
    assert r.status_code == 200, r.text
    assert client.get(f"{P}/policy").json()["pin_required_for"] == []


def test_pin_on_reports_it(client):
    assert client.get(P).json()["asks_pin"] is True
