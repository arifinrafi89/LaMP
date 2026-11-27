"""Every SMS LaMP sends, in English and Bangla (build plan 3.5, 3.6).

    from app.applink.templates import render
    render("reminder", "bn", pharmacy="Green Life Pharmacy", n=2, of=4, amount=1625, due_on=date(...))

Rules (tested for every template):
- amounts and names only: never a customer's name, never a medicine;
- English within 140 GSM-7 characters, leaving room in case Applink's locked-on ads add a
  line; Bangla within 2 UCS-2 parts (134 characters);
- Bangla uses Bangla digits for amounts and dates; codes, the short code and card codes
  stay in English letters;
- a pharmacy name longer than 40 characters is shortened.
"""
from collections.abc import Callable
from typing import Literal

from app.applink.templates import sms_bn, sms_en

Lang = Literal["en", "bn"]
KINDS = ("card", "plan", "reminder", "receipt", "balance", "help", "not_found", "taken", "brief")
MAX_PHARMACY = 40
_BY_LANG: dict[str, object] = {"en": sms_en, "bn": sms_bn}


def pharmacy_name(name: str) -> str:
    # Cut, not "…": that character isn't GSM-7 and would halve an English SMS's length.
    name = " ".join(name.split())
    return name if len(name) <= MAX_PHARMACY else name[:MAX_PHARMACY].rstrip()


def render(kind: str, lang: Lang = "en", **fields) -> str:
    if kind not in KINDS:
        raise ValueError(f"no SMS template called {kind}")
    module = _BY_LANG.get(lang, sms_en)
    if "pharmacy" in fields:
        fields["pharmacy"] = pharmacy_name(fields["pharmacy"])
    fn: Callable[..., str] = getattr(module, kind)
    return fn(**fields)
