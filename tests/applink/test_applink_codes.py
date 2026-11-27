"""Applink status codes and subscription statuses (app/applink/codes.py, plan 3.8)."""
import pytest

from app.applink import codes
from app.applink.codes import Outcome

PLAN_3_8 = {
    Outcome.SUCCESS: "S1000",
    Outcome.PENDING: "P1003",
    Outcome.CONFIGURATION: "E1301 E1303 E1309 E1311 E1313 E1315 E1328 E1331",
    Outcome.CLIENT: "E1308 E1312 E1325 E1334 E1335 E1337 E1850 E1851 E1855 E1856",
    Outcome.USER_STATE: "E1317 E1326 E1342 E1343",
    Outcome.TRANSIENT: "E1318 E1319 E1341 E1601 E1602 E1603",
}


@pytest.mark.parametrize("outcome,code", [(o, c) for o, cs in PLAN_3_8.items() for c in cs.split()])
def test_every_code_in_the_plan_has_its_class(outcome, code):
    assert codes.classify(code) is outcome
    assert codes.DETAIL[code]


def test_the_table_has_nothing_the_plan_doesnt():
    planned = {c for cs in PLAN_3_8.values() for c in cs.split()}
    assert set(codes.OUTCOME) == planned
    assert set(codes.DETAIL) == planned


def test_unknown_codes_and_messy_input():
    assert codes.classify(" s1000 ") is Outcome.SUCCESS
    assert codes.classify("S1001") is Outcome.SUCCESS
    assert codes.classify("P1999") is Outcome.PENDING
    assert codes.classify("E9999") is Outcome.UNKNOWN
    assert codes.classify(None) is Outcome.UNKNOWN
    assert codes.classify("") is Outcome.UNKNOWN


def test_only_transient_codes_retry_and_never_the_daily_limit():
    assert codes.is_retryable("E1603")
    assert codes.is_retryable("E1318")
    assert not codes.is_retryable("E1319")
    assert not codes.is_retryable("E1313")
    assert not codes.is_retryable("P1003")


@pytest.mark.parametrize("raw,expected", [
    ("REGISTERED.", "REGISTERED"), (" registered ", "REGISTERED"), ("REG_PENDING", "REG_PENDING"),
    ("UNREGISTERED", "UNREGISTERED"), ("TEMPORARY_BLOCKED.", "TEMPORARY_BLOCKED"),
    ("INITIAL", "INITIAL"), ("TRIAL", "TRIAL"), ("REGISTERED SUCCESSFULLY", "REGISTERED"),
    ("", None), (None, None), ("SOMETHING", None),
])
def test_subscription_status_is_read_by_prefix(raw, expected):
    assert codes.subscription_status(raw) == expected


def test_only_registered_and_trial_unlock_anything():
    assert codes.ACTIVE_STATUSES == {"REGISTERED", "TRIAL"}
