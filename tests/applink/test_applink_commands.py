"""Reading a family's text to 21213 (app/applink/family/commands.py, plan 3.5)."""
import pytest

from app.applink.family.commands import Command, card_code, parse
from app.engines.patients import normalize_code


@pytest.mark.parametrize("text", [
    "LAMP GL7KQM4XPA", "lamp gl7kqm4xpa", "Lamp GL-7KQM-4XPA", "  LAMP   GL 7KQM 4XPA  ",
    "LAMPGL7KQM4XPA", "GL7KQM4XPA", "lamp gl-7kqm-4xpa\n",
])
def test_a_card_code_in_any_form(text):
    assert parse(text) == Command("code", code="GL-7KQM-4XPA")


def test_card_codes_match_the_engines_own_normal_form():
    for raw in ("gl7kqm4xpa", "GL 7KQM 4XPA", "GL-7KQM-4XPA"):
        assert card_code(raw) == normalize_code(raw)


@pytest.mark.parametrize("text", ["LAMP", "lamp", " Lamp ", ""])
def test_the_keyword_alone_asks_for_the_balance(text):
    assert parse(text) == Command("balance")


@pytest.mark.parametrize("text", [
    "LAMP STOP", "lamp stop", "LAMP OFF", "LAMP UNSUB", "LAMP UNSUBSCRIBE", "STOP LAMP", "stop lamp",
    "STOP", "LAMP বন্ধ", "LAMP STOP NOW PLEASE",
])
def test_every_way_of_stopping(text):
    assert parse(text) == Command("stop")


@pytest.mark.parametrize("text", ["LAMP HELP", "lamp help me", "LAMP ?", "HELP", "LAMP সাহায্য"])
def test_help(text):
    assert parse(text) == Command("help")


@pytest.mark.parametrize("text", ["LAMP 123456", "lamp 123 456", "123456"])
def test_a_texted_back_code(text):
    assert parse(text) == Command("otp", otp="123456")


@pytest.mark.parametrize("text", [
    "LAMP GL7KQM4XP", "LAMP 7KQM4XPAGL", "LAMP hello there", "LAMP 12345", "hi", "LAMP GL7K QM4X PA",
    "LAMP " + "A" * 200, None,
])
def test_anything_else_is_unknown_or_harmless(text):
    assert parse(text).kind in {"unknown", "balance"}
    assert parse(text).code is None


def test_another_keyword_is_honoured():
    assert parse("LAMPPLUS STOP", keyword="lampplus") == Command("stop")
    assert parse("LAMP GL7KQM4XPA", keyword="lampplus") == Command("unknown")
