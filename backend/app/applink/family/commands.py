"""What a family's text to 21213 asks for (build plan 3.5). Pure: no database, no Applink.

Every command starts with our keyword, so Applink routes it to us. Some platforms pass
the keyword on and some strip it, so both forms are read the same way:

    LAMP GL7KQM4XPA        a card code: join, or the balance if already joined
    lamp gl-7kqm-4xpa      the same (case, spaces and dashes don't matter)
    LAMP                   the balance of the card(s) this phone is on
    LAMP STOP              stop (also OFF, UNSUB, UNSUBSCRIBE, বন্ধ; and STOP LAMP)
    LAMP HELP              help (also ?, সাহায্য)
    LAMP 123456            a 6-digit code texted back (FAMILY_SUBSCRIBE_METHOD=otp_textback)
    anything else          unknown: the reply is the help text

A text can only join, read a balance or stop. Nothing here changes an amount or a plan.
"""
import re
from dataclasses import dataclass
from typing import Literal

Kind = Literal["code", "balance", "stop", "help", "otp", "unknown"]

STOP_WORDS = frozenset({"STOP", "OFF", "UNSUB", "UNSUBSCRIBE", "বন্ধ"})
HELP_WORDS = frozenset({"HELP", "?", "সাহায্য"})
_CODE = re.compile(r"^[A-Z]{2}[A-Z0-9]{8}$")
_OTP = re.compile(r"^\d{6}$")
_CODE_SHAPES = {(10,), (2, 8), (6, 4), (2, 4, 4)}
_MAX_LEN = 160  # longer texts aren't commands; don't spend effort on them


@dataclass(frozen=True)
class Command:
    kind: Kind
    code: str | None = None  # 'GL-7KQM-4XPA', the engines' normal form
    otp: str | None = None


def card_code(text: str) -> str | None:
    """'gl7kqm4xpa', 'GL 7KQM 4XPA', 'GL-7KQM-4XPA' -> 'GL-7KQM-4XPA'; None if it isn't one."""
    s = re.sub(r"[^A-Z0-9]", "", text.upper())
    return f"{s[:2]}-{s[2:6]}-{s[6:]}" if _CODE.match(s) else None


def parse(text: str | None, keyword: str = "lamp") -> Command:
    raw = (text or "").strip()
    if len(raw) > _MAX_LEN:
        return Command("unknown")
    words = raw.replace("‌", " ").split()
    kw = keyword.upper()
    upper = [w.upper() for w in words]

    # The keyword first ('LAMP …'), glued on ('LAMPGL7KQM4XPA'), or last ('STOP LAMP').
    if upper and upper[0] == kw:
        rest = words[1:]
    elif upper and upper[0].startswith(kw) and card_code(words[0][len(kw):]):
        rest = [words[0][len(kw):]] + words[1:]
    elif len(upper) == 2 and upper[1] == kw and upper[0] in STOP_WORDS:
        return Command("stop")
    else:
        rest = words  # the platform stripped the keyword

    if not rest:
        return Command("balance")
    first = rest[0].upper()
    if first in STOP_WORDS:  # "LAMP STOP NOW" stops too: when in doubt, stop
        return Command("stop")
    if first in HELP_WORDS:
        return Command("help")
    joined = "".join(rest)
    if _OTP.match(joined):
        return Command("otp", otp=joined)
    # A code split by spaces only in the ways people type one (GL 7KQM 4XPA), so that ten
    # letters of ordinary words ("hello there") aren't read as a code.
    lengths = tuple(len(re.sub(r"[^A-Za-z0-9]", "", w)) for w in rest)
    code = card_code(joined) if lengths in _CODE_SHAPES else None
    if code:
        return Command("code", code=code)
    return Command("unknown")
