"""Terms, privacy policy and consent wordings (app/auth/legal.py, plan G3 and 13.3)."""
import re

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.auth import legal
from app.auth.routes import api_router


@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(api_router, prefix="/api/v1")
    return TestClient(app)


def test_current_gives_versions_and_links_the_app_can_open(client):
    r = client.get("/api/v1/legal/current", headers={"x-forwarded-proto": "https", "host": "lamp-api-k2xf.onrender.com"})
    assert r.status_code == 200
    assert r.json() == {
        "terms_version": legal.TERMS_VERSION, "privacy_version": legal.PRIVACY_VERSION,
        "terms_url": "https://lamp-api-k2xf.onrender.com/api/v1/legal/terms",
        "privacy_url": "https://lamp-api-k2xf.onrender.com/api/v1/legal/privacy"}


@pytest.mark.parametrize("doc", ["terms", "privacy"])
@pytest.mark.parametrize("lang", ["en", "bn"])
def test_each_page_in_each_language(client, doc, lang):
    r = client.get(f"/api/v1/legal/{doc}", params={"lang": lang})
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    page = r.text
    assert f'<html lang="{lang}">' in page and legal.TITLES[(doc, lang)] in page
    assert "?lang=" + ("bn" if lang == "en" else "en") in page  # the switch to the other language
    assert "21213" in page and "LAMP STOP" in page


def test_an_unknown_language_falls_back_to_english(client):
    assert '<html lang="en">' in client.get("/api/v1/legal/terms", params={"lang": "fr"}).text


@pytest.mark.parametrize("name", ["terms.en", "terms.bn", "privacy.en", "privacy.bn"])
def test_the_texts_say_what_the_system_really_does(name):
    text = (legal.HERE / f"{name}.html").read_text(encoding="utf-8")
    assert "USSD" not in text  # dropped on 27 Nov
    assert "2026-11-28" in text or "২০২৬-১১-২৮" in text  # the version is shown
    if name.startswith("privacy"):
        for must in ("OpenAI", "Render", "Applink", "21213"):
            assert must in text, must
        assert re.search(r"Singapore|সিঙ্গাপুর", text)


def test_both_languages_have_the_same_sections():
    for doc in ("terms", "privacy"):
        en = (legal.HERE / f"{doc}.en.html").read_text(encoding="utf-8").count("<h2>")
        bn = (legal.HERE / f"{doc}.bn.html").read_text(encoding="utf-8").count("<h2>")
        assert en == bn > 5


def test_consent_wordings_exist_in_both_languages_and_name_the_price():
    for version in (legal.FAMILY_WORDING, legal.PLUS_WORDING):
        wording = legal.CONSENT_WORDINGS[version]
        assert set(wording) == {"en", "bn"}
    assert "BDT 50 a month + VAT" in legal.CONSENT_WORDINGS[legal.PLUS_WORDING]["en"]
    assert "{code}" in legal.CONSENT_WORDINGS[legal.FAMILY_WORDING]["en"]
    assert "Free" in legal.CONSENT_WORDINGS[legal.FAMILY_WORDING]["en"]
