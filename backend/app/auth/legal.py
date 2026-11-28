"""Terms, privacy policy and consent wordings (build plan G3, 13.3; Arifin writes, Ishmam reviews).

    GET /api/v1/legal/current            the versions the owner must accept, and where to read them
    GET /api/v1/legal/terms?lang=en|bn   the terms of use, as a page
    GET /api/v1/legal/privacy?lang=en|bn the privacy policy, as a page

The texts live in legal_texts/ next to this file (terms.en.html, terms.bn.html, privacy.en.html,
privacy.bn.html). Changing a text means changing its version below, which makes the app
ask every owner to accept it again (`consents_needed` in /me).

The consent wordings are recorded by version with each consent (plan 4.3, applink_consent),
so what a person agreed to can always be shown later.
"""
from functools import lru_cache
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

TERMS_VERSION = "2026-11-28"
PRIVACY_VERSION = "2026-11-28"
HERE = Path(__file__).parent / "legal_texts"

# What a family or an owner agrees to, word for word (plan 3.3, 3.4).
CONSENT_WORDINGS: dict[str, dict[str, str]] = {
    "family-sms-2026-11-28": {
        "en": "Text LAMP {code} to 21213 for free reminders of what you owe. Free. Text LAMP STOP to stop.",
        "bn": "বাকির বিনা খরচের রিমাইন্ডার পেতে 21213-এ LAMP {code} লিখে পাঠান। কোনো খরচ নেই। বন্ধ করতে LAMP STOP পাঠান।",
    },
    "plus-2026-11-28": {
        "en": "LaMP Plus, BDT 50 a month + VAT from your mobile balance. Stop any time.",
        "bn": "LaMP Plus, মাসে ৳৫০ ও ভ্যাট, আপনার মোবাইল ব্যালান্স থেকে। যেকোনো সময় বন্ধ করা যায়।",
    },
}
FAMILY_WORDING = "family-sms-2026-11-28"
PLUS_WORDING = "plus-2026-11-28"

Doc = Literal["terms", "privacy"]
Lang = Literal["en", "bn"]
TITLES = {("terms", "en"): "LaMP terms of use", ("terms", "bn"): "LaMP ব্যবহারের শর্তাবলি",
          ("privacy", "en"): "LaMP privacy policy", ("privacy", "bn"): "LaMP গোপনীয়তা নীতি"}

router = APIRouter(prefix="/legal", tags=["legal"])


class LegalCurrent(BaseModel):
    terms_version: str
    privacy_version: str
    terms_url: str
    privacy_url: str


def _base(request: Request) -> str:
    """This server's public address, as the caller reached it (Render's proxy says https)."""
    proto = request.headers.get("x-forwarded-proto", request.url.scheme).split(",")[0].strip()
    host = request.headers.get("x-forwarded-host") or request.headers.get("host") or request.url.netloc
    return f"{proto}://{host}"


@router.get("/current", response_model=LegalCurrent)
def current(request: Request) -> LegalCurrent:
    base = _base(request) + "/api/v1/legal"
    return LegalCurrent(terms_version=TERMS_VERSION, privacy_version=PRIVACY_VERSION,
                        terms_url=f"{base}/terms", privacy_url=f"{base}/privacy")


@lru_cache
def _body(doc: str, lang: str) -> str:
    return (HERE / f"{doc}.{lang}.html").read_text(encoding="utf-8")


def _page(doc: Doc, lang: Lang) -> HTMLResponse:
    other = "bn" if lang == "en" else "en"
    switch = "বাংলায় পড়ুন" if other == "bn" else "Read in English"
    html = f"""<!doctype html>
<html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{TITLES[(doc, lang)]}</title>
<style>
body{{font-family:system-ui,"Noto Sans Bengali","Noto Sans",sans-serif;max-width:44rem;margin:0 auto;padding:1rem 1.1rem 3rem;
line-height:1.6;color:#1F2933;background:#fff}}h1{{color:#0B6E4F;font-size:1.5rem}}h2{{font-size:1.1rem;margin-top:1.6rem}}
.meta{{color:#5B6670;font-size:.9rem}}a{{color:#0B6E4F}}nav{{text-align:right;font-size:.95rem}}
@media (prefers-color-scheme:dark){{body{{background:#111;color:#e6e6e6}}.meta{{color:#aaa}}h1,a{{color:#5fd3a6}}}}
</style></head><body>
<nav><a href="?lang={other}">{switch}</a></nav>
{_body(doc, lang)}
</body></html>"""
    return HTMLResponse(html, headers={"Cache-Control": "public, max-age=3600", "X-Content-Type-Options": "nosniff"})


@router.get("/terms", response_class=HTMLResponse, include_in_schema=False)
def terms(lang: str = Query("en")) -> HTMLResponse:
    return _page("terms", "bn" if lang == "bn" else "en")


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
def privacy(lang: str = Query("en")) -> HTMLResponse:
    return _page("privacy", "bn" if lang == "bn" else "en")
