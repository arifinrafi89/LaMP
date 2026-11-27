"""Phone numbers and Applink addresses (app/applink/tel.py)."""
import pytest

from app.applink import tel


@pytest.mark.parametrize("typed", [
    "01912345678", "+8801912345678", "8801912345678", "+880 1912-345678",
    "tel:8801912345678", "tel:+8801912345678", "tel: 8801912345678", " 01912 345 678 ",
])
def test_every_way_of_typing_a_number_gives_applinks_format(typed):
    assert tel.to_tel(typed) == "tel:8801912345678"


@pytest.mark.parametrize("bad", [
    "", "12345", "01212345678", "0191234567", "019123456789", "+1 202 555 0123",
    "tel:B%3C4d9f01912345678x", "abc01912345678",
])
def test_anything_else_is_refused(bad):
    with pytest.raises(tel.InvalidNumber):
        tel.to_tel(bad)


def test_banglalink_is_019_or_014_only():
    assert tel.is_banglalink("01912345678")
    assert tel.is_banglalink("+8801412345678")
    assert not tel.is_banglalink("01712345678")
    assert not tel.is_banglalink("not a number")


def test_masked_ids_are_told_apart_from_numbers():
    assert tel.is_plain_number("tel:8801912345678")
    assert not tel.is_plain_number("tel:B%3C4d9f0a1b2c3d")


def test_mask_never_shows_more_than_the_last_digits():
    assert tel.mask("tel:8801912345678") == "+880 19•• ••• 678"
    assert tel.mask("tel:B%3C4d9f0a1b2c3d") == "masked…2c3d"
    assert tel.mask(None) == "-"
    assert "1912345" not in tel.mask("01912345678")


def test_hash_is_stable_keyed_and_ignores_how_the_number_was_typed():
    a = tel.hmac_hash("01912345678", "pepper-1")
    assert a == tel.hmac_hash("+880 1912-345678", "pepper-1")
    assert a != tel.hmac_hash("01912345678", "pepper-2")
    assert "1912345678" not in a
    assert tel.hmac_hash("tel:B%3C4d9f", "pepper-1") == tel.hmac_hash(" tel:B%3C4d9f ", "pepper-1")
    with pytest.raises(ValueError):
        tel.hmac_hash("01912345678", "")
