"""Bangla SMS (build plan 3.5, 3.6). Bangla digits for amounts and dates; the short code,
LAMP and card codes in English letters. At most 2 UCS-2 parts (134 characters)."""
from datetime import date

from app.applink.templates.money import bdt_bn, date_bn, num_bn

SHORT_CODE = "21213"


def card(pharmacy: str, amount, code: str) -> str:
    return f"{pharmacy}: বাকি {bdt_bn(amount)} (কার্ড {code})। বাকি জানতে {SHORT_CODE}-এ LAMP পাঠান। বন্ধ: LAMP STOP"


def plan(pharmacy: str, parts: int, part_amount, first_on: date) -> str:
    if parts == 1:
        return f"{pharmacy}: {date_bn(first_on)}-এর মধ্যে {bdt_bn(part_amount)} দিন। ২ দিন আগে আমরা জানাব।"
    return (f"{pharmacy}: {num_bn(parts)}টি সাপ্তাহিক কিস্তি, প্রতিটি {bdt_bn(part_amount)}, প্রথমটি {date_bn(first_on)}। "
            f"প্রতিটির ২ দিন আগে আমরা জানাব।")


def reminder(pharmacy: str, n: int, of: int, amount, due_on: date) -> str:
    what = bdt_bn(amount) if of == 1 else f"কিস্তি {num_bn(n)}/{num_bn(of)}, {bdt_bn(amount)}"
    return f"{pharmacy}: {what}, শেষ দিন {date_bn(due_on)}। দোকানে দিন। বন্ধ: {SHORT_CODE}-এ LAMP STOP"


def receipt(pharmacy: str, paid, paid_on: date, balance) -> str:
    owe = "আপনার আর কোনো বাকি নেই।" if float(balance) <= 0 else f"আপনার বাকি এখন {bdt_bn(balance)}।"
    return f"{pharmacy} {date_bn(paid_on)} তারিখে {bdt_bn(paid)} পেয়েছে। {owe} ধন্যবাদ।"


def balance(pharmacy: str, amount, next_amount=None, next_on: date | None = None) -> str:
    if float(amount) <= 0:
        return f"{pharmacy}: আপনার কোনো বাকি নেই। ধন্যবাদ।"
    text = f"{pharmacy}: আপনার বাকি {bdt_bn(amount)}।"
    if next_amount is not None and next_on is not None:
        text += f" পরের কিস্তি {date_bn(next_on)}-এ {bdt_bn(next_amount)}।"
    return text


def help() -> str:  # noqa: A001 (the template's name)
    return (f"LaMP: বিনা খরচে বাকির রিমাইন্ডার পেতে রসিদের কার্ড কোডসহ LAMP লিখে {SHORT_CODE}-এ পাঠান "
            f"(যেমন LAMP GL7KQM4XPA)। বন্ধ করতে LAMP STOP।")


def not_found() -> str:
    return "LaMP: কার্ডটি পাওয়া যায়নি। রসিদে লেখা কোডটি দেখে আবার পাঠান।"


def taken() -> str:
    return "LaMP: এই কার্ডের রিমাইন্ডার অন্য একটি ফোনে যায়। ফার্মেসিতে জিজ্ঞেস করুন।"


def brief(on: date, cash_now, short_amount=None, short_on: date | None = None,
          expiring_value=None, steps: int = 0) -> str:
    parts = [f"LaMP {date_bn(on)}: হাতে নগদ {bdt_bn(cash_now)}।"]
    if short_amount and short_on:
        parts.append(f"{date_bn(short_on)}-এ ঘাটতি {bdt_bn(short_amount)}।")
    if expiring_value:
        parts.append(f"এ সপ্তাহে মেয়াদ শেষ: {bdt_bn(expiring_value)}।")
    if steps:
        parts.append(f"অ্যাপে {num_bn(steps)}টি কাজ বাকি।")
    return " ".join(parts)
