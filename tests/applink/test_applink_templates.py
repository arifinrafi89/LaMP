"""SMS templates in English and Bangla (app/applink/templates, plan 3.6)."""
import inspect
import re
from datetime import date

import pytest

from app.applink import templates
from app.applink.templates import money, render, sms_bn, sms_en

LONGEST = "Shaheed Suhrawardy Medical Pharmacy Ltd."  # 40 characters
assert len(LONGEST) == 40
GSM7 = set("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZ"
           "ÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà")
D1, D2 = date(2026, 10, 29), date(2026, 11, 5)

# Every template, filled with the longest values it can meet.
CASES = {
    "card": dict(pharmacy=LONGEST, amount=125000, code="GL-7KQM-4XPA"),
    "plan": dict(pharmacy=LONGEST, parts=4, part_amount=31250.50, first_on=D1),
    "reminder": dict(pharmacy=LONGEST, n=2, of=4, amount=31250.50, due_on=D2),
    "receipt": dict(pharmacy=LONGEST, paid=31250.50, paid_on=D1, balance=93751.50),
    "balance": dict(pharmacy=LONGEST, amount=93751.50, next_amount=31250.50, next_on=D2),
    "help": {},
    "not_found": {},
    "taken": {},
    "brief": dict(on=D1, cash_now=1250000, short_amount=190000, short_on=D2, expiring_value=18400, steps=12),
}


@pytest.mark.parametrize("kind", templates.KINDS)
def test_english_fits_one_gsm7_sms_with_room_to_spare(kind):
    text = render(kind, "en", **CASES[kind])
    assert set(text) <= GSM7, set(text) - GSM7
    assert len(text) <= 140, (len(text), text)


@pytest.mark.parametrize("kind", templates.KINDS)
def test_bangla_fits_two_parts_with_bangla_digits(kind):
    text = render(kind, "bn", **CASES[kind])
    assert len(text) <= 134, (len(text), text)
    # Only the short code, LAMP commands and card codes may keep English digits.
    leftover = re.sub(r"21213|GL-?7KQM-?4XPA|LAMP|STOP", "", text)
    assert not re.search(r"[0-9]", leftover), leftover


def test_no_template_can_take_a_name_or_a_medicine():
    for module in (sms_en, sms_bn):
        for kind in templates.KINDS:
            params = set(inspect.signature(getattr(module, kind)).parameters)
            assert not params & {"name", "customer", "patient", "medicine", "medicines", "drug"}


def test_both_languages_have_every_template():
    for kind in templates.KINDS:
        assert callable(getattr(sms_en, kind)) and callable(getattr(sms_bn, kind))
    with pytest.raises(ValueError):
        render("ussd_menu", "en")


def test_the_plans_own_examples():
    g = "Green Life Pharmacy"
    assert render("card", "en", pharmacy=g, amount=6500, code="GL-7KQM-4XPA") == (
        "Green Life Pharmacy: you owe BDT 6,500 (card GL-7KQM-4XPA). Text LAMP to 21213 for your balance. "
        "Stop: LAMP STOP")
    assert render("plan", "en", pharmacy=g, parts=4, part_amount=1625, first_on=D1) == (
        "Green Life Pharmacy: 4 weekly parts of BDT 1,625, first on Thu 29 Oct. We'll text you 2 days before each one.")
    assert render("reminder", "en", pharmacy=g, n=2, of=4, amount=1625, due_on=D2) == (
        "Green Life Pharmacy: part 2 of 4, BDT 1,625, is due Thu 5 Nov. Pay at the shop. Stop: LAMP STOP to 21213")
    assert render("receipt", "en", pharmacy=g, paid=1625, paid_on=D1, balance=4875) == (
        "Green Life Pharmacy got BDT 1,625 on 29 Oct. You now owe BDT 4,875. Thank you.")
    assert render("balance", "en", pharmacy=g, amount=4875, next_amount=1625, next_on=D2) == (
        "Green Life Pharmacy: you owe BDT 4,875. Next: BDT 1,625 on Thu 5 Nov.")


def test_paid_off_and_single_part_wording():
    g = "Green Life Pharmacy"
    assert "nothing" in render("receipt", "en", pharmacy=g, paid=1625, paid_on=D1, balance=0)
    assert "নেই" in render("receipt", "bn", pharmacy=g, paid=1625, paid_on=D1, balance=0)
    assert render("reminder", "en", pharmacy=g, n=1, of=1, amount=6500, due_on=D2).startswith(
        "Green Life Pharmacy: BDT 6,500 is due")
    assert "by Thu 29 Oct" in render("plan", "en", pharmacy=g, parts=1, part_amount=6500, first_on=D1)


def test_the_owners_brief_says_only_what_applies():
    assert render("brief", "en", on=D1, cash_now=41000) == "LaMP 29 Oct: cash BDT 41,000."
    assert render("brief", "en", on=D1, cash_now=41000, steps=1).endswith("1 step waits in the app.")
    assert render("brief", "en", on=D1, cash_now=41000, steps=2).endswith("2 steps wait in the app.")


def test_long_pharmacy_names_are_cut_to_40():
    name = templates.pharmacy_name("A" * 60)
    assert len(name) == 40 and set(name) <= GSM7


@pytest.mark.parametrize("amount,en,bn", [
    (6500, "6,500", "৬,৫০০"), (125000, "1,25,000", "১,২৫,০০০"), (1625.5, "1,625.50", "১,৬২৫.৫০"),
    (19000, "19,000", "১৯,০০০"), (0, "0", "০"), (10000000, "1,00,00,000", "১,০০,০০,০০০"),
])
def test_amounts_use_lakh_grouping_like_the_app(amount, en, bn):
    assert money.bdt_en(amount) == "BDT " + en
    assert money.bdt_bn(amount) == "৳" + bn


def test_dates():
    assert money.day_en(D1) == "Thu 29 Oct"
    assert money.date_bn(D1) == "২৯ অক্টোবর"
