"""The owner's account and their shop (build plan 2.2; task I2.2, part 1): GET and PATCH /me,
creating a shop, changing it, and finishing setup."""

import re
import uuid
from datetime import datetime, timezone

import pytest

from app.applink.models import Subscriber
from app.auth import crypto, sessions, signin
from app.db.models import Owner, Pharmacy
from app.engines import shops

ME = "/api/v1/me"
SHOPS = "/api/v1/pharmacies"


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


@pytest.fixture
def newcomer(api_db):
    """Headers for an owner who signed in a minute ago and has no shop yet."""
    number = f"tel:88019{uuid.uuid4().int % 10**8:08d}"
    owner = Owner(id=str(uuid.uuid4()), pharmacy_id=None, phone_hash=crypto.phone_hash(number),
                  phone_enc=crypto.seal(number, purpose=signin.OWNER_PHONE), language="bn", created_at=_now())
    api_db.add(owner)
    api_db.flush()
    s, _ = sessions.create(api_db, owner, {"id": "new-phone", "name": "Phone", "os": "android", "app_version": "1"})
    token, _ = sessions.access_for(api_db, owner, s)
    api_db.commit()
    return {"Authorization": f"Bearer {token}"}


def _plus(api_db, status: str) -> None:
    owner = signin.shop_owner(api_db, "green-life")
    api_db.add(Subscriber(app="plus", subscriber_ref=f"ref-{status}", owner_id=owner.id, status=status,
                          created_at=_now(), updated_at=_now()))
    api_db.commit()


# --- GET and PATCH /me -------------------------------------------------------------------

def test_me_for_the_demo_shop(client):
    r = client.get(ME)
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["pharmacy"] == {"id": "green-life", "name": "Green Life Pharmacy", "setup_complete": True}
    assert j["owner"]["phone_masked"] == "Demo shop"
    assert j["plan"] == "free" and j["plus_status"] == "NONE"
    assert j["entitlements"] == {"cash": False, "plan": False, "approvals": False, "ask": False, "scans_left": 10}
    assert j["demo_tools"] is True
    assert j["family_join_routes"] == ["text"]
    assert set(j["consents_needed"]) <= {"terms", "privacy"}


def test_me_on_plus(client, api_db):
    _plus(api_db, "REGISTERED")
    j = client.get(ME).json()
    assert j["plan"] == "plus" and j["plus_status"] == "ACTIVE"
    assert j["entitlements"] == {"cash": True, "plan": True, "approvals": True, "ask": True, "scans_left": None}


@pytest.mark.parametrize("status,shown", [("REG_PENDING", "PENDING"), ("INITIAL", "PENDING"),
                                          ("TEMPORARY_BLOCKED", "BLOCKED"), ("UNREGISTERED", "STOPPED")])
def test_plus_status_follows_the_mirror(client, api_db, status, shown):
    _plus(api_db, status)
    j = client.get(ME).json()
    assert j["plus_status"] == shown and j["plan"] == "free"


def test_scans_left_counts_this_months_photos(client, api_db):
    from app.db.models import Capture

    api_db.add(Capture(id="cap-x1", pharmacy_id="green-life", kind="invoice", status="confirmed", extraction={},
                       created_at=_now()))
    api_db.commit()
    assert client.get(ME).json()["entitlements"]["scans_left"] == 9


def test_patch_me_sets_the_language(client):
    r = client.patch(ME, json={"language": "bn"})
    assert r.status_code == 200, r.text
    assert r.json()["owner"]["language"] == "bn"
    assert client.get(ME).json()["owner"]["language"] == "bn"


def test_patch_me_refuses_an_unknown_language(client):
    assert client.patch(ME, json={"language": "fr"}).status_code == 422


def test_me_needs_a_token(anon):
    r = anon.get(ME)
    assert r.status_code == 401 and r.json()["code"] == "session_expired"


def test_me_without_a_shop(anon, newcomer):
    j = anon.get(ME, headers=newcomer).json()
    assert j["pharmacy"] is None and j["demo_tools"] is False
    assert j["owner"]["language"] == "bn" and "•" in j["owner"]["phone_masked"]  # never the whole number
    assert j["entitlements"]["scans_left"] == 10


# --- Creating a shop ---------------------------------------------------------------------

def test_a_new_owner_creates_a_shop(anon, newcomer, api_db):
    r = anon.post(SHOPS, json={"name": "Shapla Pharmacy", "city": "Dhaka", "area": "Mirpur"}, headers=newcomer)
    assert r.status_code == 201, r.text
    j = r.json()
    assert re.fullmatch(r"ph-[0-9a-f]{12}", j["id"])
    assert j["name"] == "Shapla Pharmacy" and j["city"] == "Dhaka"
    assert j["kind"] == "real" and j["setup_complete"] is False and j["card_prefix"] == "SP"
    assert j["settings"] == {"gross_margin_pct": 12, "cash_buffer": 0, "expiry_buffer_days": 30, "as_of_date": None}
    # The owner's shop is set, so the same token reaches it at once (tokens don't carry it).
    me = anon.get(ME, headers=newcomer).json()
    assert me["pharmacy"] == {"id": j["id"], "name": "Shapla Pharmacy", "setup_complete": False}
    assert anon.get(f"{SHOPS}/{j['id']}", headers=newcomer).status_code == 200
    ph = api_db.get(Pharmacy, j["id"])
    api_db.refresh(ph)
    assert ph.settings["area"] == "Mirpur" and ph.created_at is not None and ph.cash_on_hand == 0


def test_a_second_shop_is_refused(anon, newcomer):
    assert anon.post(SHOPS, json={"name": "One", "city": "Dhaka"}, headers=newcomer).status_code == 201
    r = anon.post(SHOPS, json={"name": "Two", "city": "Dhaka"}, headers=newcomer)
    assert r.status_code == 409 and r.json()["code"] == "invalid"


def test_the_demo_owner_cant_make_another_shop(client):
    assert client.post(SHOPS, json={"name": "Two", "city": "Dhaka"}).status_code == 409


def test_creating_a_shop_needs_a_token(anon):
    assert anon.post(SHOPS, json={"name": "One", "city": "Dhaka"}).status_code == 401


@pytest.mark.parametrize("body", [{"name": "", "city": "Dhaka"}, {"name": "One"}, {"name": "x" * 81, "city": "D"}])
def test_a_shop_needs_a_name_and_a_city(anon, newcomer, body):
    assert anon.post(SHOPS, json=body, headers=newcomer).status_code == 422


@pytest.mark.parametrize("name,prefix", [("Green Life", "GL"), ("Shapla", "SH"), ("shapla pharmacy", "SP"),
                                         ("  Ma  Medicine Corner ", "MM"), ("123 Drug House", "DH")])
def test_card_prefix(name, prefix):
    assert shops.card_prefix(name) == prefix


def test_card_prefix_without_latin_letters():
    p = shops.card_prefix("ঔষধালয়")
    assert re.fullmatch(r"[A-Z]{2}", p)


# --- Changing the shop and finishing setup -----------------------------------------------

def test_patch_shop(client):
    r = client.patch(f"{SHOPS}/green-life", json={"name": "Green Life 2", "gross_margin_pct": 15, "cash_buffer": 5000})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["name"] == "Green Life 2" and j["city"] == "Bogura"
    assert j["settings"]["gross_margin_pct"] == 15 and j["settings"]["cash_buffer"] == 5000
    assert "owner_pin" not in j["settings"]
    assert client.get(f"{SHOPS}/green-life").json()["name"] == "Green Life 2"


@pytest.mark.parametrize("body", [{"name": ""}, {"gross_margin_pct": 61}, {"cash_buffer": -1}])
def test_patch_shop_refuses_bad_values(client, body):
    assert client.patch(f"{SHOPS}/green-life", json=body).status_code == 422


def test_setup_complete(anon, newcomer):
    pid = anon.post(SHOPS, json={"name": "Shapla", "city": "Dhaka"}, headers=newcomer).json()["id"]
    r = anon.post(f"{SHOPS}/{pid}/setup/complete", headers=newcomer)
    assert r.status_code == 200, r.text
    assert r.json()["setup_complete"] is True
    assert anon.get(ME, headers=newcomer).json()["pharmacy"]["setup_complete"] is True


def test_another_owners_shop_is_404(anon, newcomer):
    for method, path in (("PATCH", f"{SHOPS}/green-life"), ("POST", f"{SHOPS}/green-life/setup/complete")):
        r = anon.request(method, path, json={"name": "Mine now"} if method == "PATCH" else None, headers=newcomer)
        assert r.status_code == 404 and r.json()["code"] == "not_found"
