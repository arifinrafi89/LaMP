"""English SMS (build plan 3.5, 3.6). GSM-7 characters only, at most 140."""
from datetime import date

from app.applink.templates.money import bdt_en, date_en, day_en

SHORT_CODE = "21213"


def card(pharmacy: str, amount, code: str) -> str:
    return f"{pharmacy}: you owe {bdt_en(amount)} (card {code}). Text LAMP to {SHORT_CODE} for your balance. Stop: LAMP STOP"


def plan(pharmacy: str, parts: int, part_amount, first_on: date) -> str:
    if parts == 1:
        return f"{pharmacy}: pay {bdt_en(part_amount)} by {day_en(first_on)}. We'll text you 2 days before."
    return (f"{pharmacy}: {parts} weekly parts of {bdt_en(part_amount)}, first on {day_en(first_on)}. "
            f"We'll text you 2 days before each one.")


def reminder(pharmacy: str, n: int, of: int, amount, due_on: date) -> str:
    what = f"{bdt_en(amount)} is" if of == 1 else f"part {n} of {of}, {bdt_en(amount)}, is"
    return f"{pharmacy}: {what} due {day_en(due_on)}. Pay at the shop. Stop: LAMP STOP to {SHORT_CODE}"


def receipt(pharmacy: str, paid, paid_on: date, balance) -> str:
    owe = "You owe nothing now." if float(balance) <= 0 else f"You now owe {bdt_en(balance)}."
    return f"{pharmacy} got {bdt_en(paid)} on {date_en(paid_on)}. {owe} Thank you."


def balance(pharmacy: str, amount, next_amount=None, next_on: date | None = None) -> str:
    if float(amount) <= 0:
        return f"{pharmacy}: you owe nothing. Thank you."
    text = f"{pharmacy}: you owe {bdt_en(amount)}."
    if next_amount is not None and next_on is not None:
        text += f" Next: {bdt_en(next_amount)} on {day_en(next_on)}."
    return text


def help() -> str:  # noqa: A001 (the template's name)
    return (f"LaMP: text LAMP and the card code from your bill (like LAMP GL7KQM4XPA) to {SHORT_CODE} "
            f"for free payment reminders. LAMP STOP to stop.")


def not_found() -> str:
    return "LaMP: we couldn't find that card. Check the code on your bill."


def taken() -> str:
    return "LaMP: this card already gets reminders on another phone. Ask at the pharmacy."


def brief(on: date, cash_now, short_amount=None, short_on: date | None = None,
          expiring_value=None, steps: int = 0) -> str:
    """The owner's 8 AM SMS: each sentence only if it applies."""
    parts = [f"LaMP {date_en(on)}: cash {bdt_en(cash_now)}."]
    if short_amount and short_on:
        parts.append(f"Short {bdt_en(short_amount)} on {date_en(short_on)}.")
    if expiring_value:
        parts.append(f"Expiring this week: {bdt_en(expiring_value)}.")
    if steps:
        parts.append(f"{steps} step{'s' if steps != 1 else ''} wait{'s' if steps == 1 else ''} in the app.")
    return " ".join(parts)
