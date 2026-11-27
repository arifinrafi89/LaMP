"""Amounts and dates for SMS, in the same style as the app (lakh grouping, plan 5.4)."""
from datetime import date
from decimal import ROUND_HALF_UP, Decimal

BN_DIGITS = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")
EN_DAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
EN_MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
BN_MONTHS = ("জানুয়ারি", "ফেব্রুয়ারি", "মার্চ", "এপ্রিল", "মে", "জুন", "জুলাই", "আগস্ট", "সেপ্টেম্বর",
             "অক্টোবর", "নভেম্বর", "ডিসেম্বর")


def lakh(amount: float | int | Decimal) -> str:
    """6500 -> '6,500'; 125000 -> '1,25,000'; 1625.5 -> '1,625.50' (paisa only when there are some)."""
    value = Decimal(str(amount)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    sign = "-" if value < 0 else ""
    whole, _, paisa = f"{abs(value):.2f}".partition(".")
    if len(whole) > 3:
        head, tail = whole[:-3], whole[-3:]
        groups = []
        while len(head) > 2:
            groups.insert(0, head[-2:])
            head = head[:-2]
        if head:
            groups.insert(0, head)
        whole = ",".join(groups + [tail])
    return sign + whole + ("" if paisa == "00" else "." + paisa)


def bdt_en(amount) -> str:
    return "BDT " + lakh(amount)


def bdt_bn(amount) -> str:
    return "৳" + lakh(amount).translate(BN_DIGITS)


def day_en(d: date) -> str:
    """'Thu 29 Oct'"""
    return f"{EN_DAYS[d.weekday()]} {d.day} {EN_MONTHS[d.month - 1]}"


def date_en(d: date) -> str:
    """'29 Oct'"""
    return f"{d.day} {EN_MONTHS[d.month - 1]}"


def date_bn(d: date) -> str:
    """'২৯ অক্টোবর'"""
    return f"{str(d.day).translate(BN_DIGITS)} {BN_MONTHS[d.month - 1]}"


def num_bn(n: int) -> str:
    return str(n).translate(BN_DIGITS)
