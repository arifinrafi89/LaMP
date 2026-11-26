"""The core functions Arifin's jobs call (build plan 1.4 B, I1.4)."""

from datetime import date, timedelta

import pytest

from app.db import models as m
from app.engines import brief, credit_record, patients

DEMO_DAY = date(2026, 10, 16)


def test_the_brief_for_the_demo_day(db):
    b = brief.daily_brief(db, "green-life", DEMO_DAY)
    assert b == brief.BriefFigures(pharmacy_id="green-life", on_date=DEMO_DAY, cash_now=39150.0,
                                   shortfall=brief.Shortfall(date(2026, 10, 26), 19000.0),  # golden: 19,000
                                   expiring_this_week=0.0, approvals_waiting=0)


def test_the_brief_is_for_the_day_asked_not_the_shops_fixed_date(db):
    later = brief.daily_brief(db, "green-life", DEMO_DAY + timedelta(days=60))
    assert later.on_date == DEMO_DAY + timedelta(days=60)
    assert later != brief.daily_brief(db, "green-life", DEMO_DAY)


def test_only_real_shops_that_finished_setup_get_a_brief(db):
    db.add_all([m.Pharmacy(id="real-done", name="A", city="Bogura", settings={}, kind="real", setup_complete=True),
                m.Pharmacy(id="real-new", name="B", city="Bogura", settings={}, kind="real"),
                m.Pharmacy(id="team", name="C", city="Bogura", settings={}, kind="team_test", setup_complete=True)])
    db.flush()
    assert brief.pharmacies_for_brief(db) == ["real-done"]


def test_find_by_code_takes_any_spelling_and_never_raises(db):
    d = db.query(m.PatientDue).filter_by(pharmacy_id="green-life").first()
    assert patients.find_by_code(db, d.code.lower().replace("-", " ")) == ("green-life", d.label)
    assert patients.find_by_code(db, "ZZ-0000-0000") is None


def test_parts_due_lists_each_part_on_its_day(db):
    d = db.query(m.PatientDue).filter_by(pharmacy_id="green-life").first()
    patients.set_plan(db, d.code, 4, DEMO_DAY + timedelta(days=2))
    week2 = DEMO_DAY + timedelta(days=9)
    due = [p for p in patients.parts_due(db, week2) if p.code == d.code]
    assert [(p.n, p.amount, p.due_on) for p in due] == [(2, patients.split(d.amount, 4)[1], week2)]
    assert [p for p in patients.parts_due(db, DEMO_DAY + timedelta(days=3)) if p.code == d.code] == []


def test_on_paid_is_not_built_yet(db):
    with pytest.raises(NotImplementedError):
        credit_record.on_paid(db, "green-life", "c-1")
