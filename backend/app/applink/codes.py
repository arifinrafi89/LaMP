"""Applink's status codes, and what the server does with each (build plan 3.8).

Applink answers HTTP 200 even for errors, so every reply is judged by its
statusCode alone. One table decides the reaction:

    success        proceed (for SMS, also check each recipient's entry)
    pending        never re-send; settle from the notification (CaaS P1003)
    configuration  our setup is broken: no retry, alert, the app shows applink_down
    client         our payload is wrong, or a person typed a wrong code
    user_state     tell the person what to do (Banglalink number, top up, test list)
    transient      retry with backoff, at most 3 times (never on the charging path)
"""
from enum import StrEnum


class Outcome(StrEnum):
    SUCCESS = "success"
    PENDING = "pending"
    CONFIGURATION = "configuration"
    CLIENT = "client"
    USER_STATE = "user_state"
    TRANSIENT = "transient"
    UNKNOWN = "unknown"


_CLASSES: dict[Outcome, tuple[str, ...]] = {
    Outcome.SUCCESS: ("S1000",),
    Outcome.PENDING: ("P1003",),
    Outcome.CONFIGURATION: ("E1301", "E1303", "E1309", "E1311", "E1313", "E1315", "E1328", "E1331"),
    Outcome.CLIENT: ("E1308", "E1312", "E1325", "E1334", "E1335", "E1337", "E1850", "E1851", "E1855", "E1856"),
    Outcome.USER_STATE: ("E1317", "E1326", "E1342", "E1343"),
    Outcome.TRANSIENT: ("E1318", "E1319", "E1341", "E1601", "E1602", "E1603"),
}
OUTCOME: dict[str, Outcome] = {code: outcome for outcome, codes in _CLASSES.items() for code in codes}

# Applink's own wording (developer portal, status codes page), shortened where it names
# placeholders; E1326 and E1337 use the plan's wording (3.7, 3.8). The mock answers with
# these, so tests see the real texts.
DETAIL: dict[str, str] = {
    "S1000": "Success",
    "P1003": "Request successfully proceed. OTP will send to user.",
    "E1301": "Requested ApplicationID is not allowed within the System for operator.",
    "E1303": "IP address from which this request originated is not provisioned to send requests to this application.",
    "E1308": "Permanent charging error.",
    "E1309": "Requested service is not allowed for this application.",
    "E1311": "Mobile terminated SMS messages are not enabled. Check your NCS configuration in provisioning.",
    "E1312": "Request is invalid.",
    "E1313": "Authentication failed.",
    "E1315": "Cannot find the requested service or it is not active.",
    "E1317": "MSISDN in request is invalid or not allowed.",
    "E1318": "Transaction limit per second has exceeded.",
    "E1319": "Transaction limit for today has exceeded.",
    "E1325": "Format of the address is invalid. Expected format is tel:8801959979376.",
    "E1326": "Insufficient balance.",
    "E1328": "Applink error E1328.",  # in our plan's table, but no published wording
    "E1331": "sourceAddress is not allowed.",
    "E1334": "Message length is too long.",
    "E1335": "Advertisement message length is too long.",
    "E1337": "Duplicate request.",
    "E1341": "Request failed for all the destinations.",
    "E1342": "MSISDN is black listed.",
    "E1343": "MSISDN is not white listed. Only white listed numbers are allowed at this state.",
    "E1601": "System experienced an unexpected error.",
    "E1602": "Applink error E1602.",  # likewise
    "E1603": "Temporary system error occurred while delivering your request.",
    "E1850": "Invalid OTP.",
    "E1851": "OTP request has been expired.",
    "E1855": "Invalid reference number.",
    "E1856": "Invalid Request.",
}


def classify(code: str | None) -> Outcome:
    """The class of a statusCode. Unlisted S codes count as success and unlisted P codes as
    pending; any other unknown code is UNKNOWN, which callers treat like a configuration error."""
    if not code:
        return Outcome.UNKNOWN
    code = code.strip().upper()
    if code in OUTCOME:
        return OUTCOME[code]
    if code.startswith("S"):
        return Outcome.SUCCESS
    if code.startswith("P"):
        return Outcome.PENDING
    return Outcome.UNKNOWN


def is_retryable(code: str | None) -> bool:
    """Retry with backoff? Only transient codes, and never E1319 (the day's limit is spent)."""
    return classify(code) is Outcome.TRANSIENT and (code or "").strip().upper() != "E1319"


SUBSCRIPTION_STATUSES = ("REG_PENDING", "TEMPORARY_BLOCKED", "UNREGISTERED", "REGISTERED", "INITIAL", "TRIAL")
# Only these unlock anything (plan 3.3).
ACTIVE_STATUSES = frozenset({"REGISTERED", "TRIAL"})


def subscription_status(raw: str | None) -> str | None:
    """Applink's subscriptionStatus, normalised: trimmed, upper-cased, a trailing dot dropped
    ("REGISTERED." -> "REGISTERED"), then read by prefix. None if it isn't one we know."""
    if not raw:
        return None
    s = raw.strip().rstrip(".").strip().upper()
    if s in SUBSCRIPTION_STATUSES:
        return s
    for known in SUBSCRIPTION_STATUSES:
        if s.startswith(known):
            return known
    return None
