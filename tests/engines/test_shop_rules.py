"""Shop rules on save (build plan 0.6 and 4.2)."""

from datetime import date

import pytest

from app.db import models as m


def _shop(kind: str, as_of: str | None) -> m.Pharmacy:
    settings = {"gross_margin_pct": 12, "cash_buffer": 0, "expiry_buffer_days": 30}
    if as_of:
        settings["as_of_date"] = as_of
    return m.Pharmacy(id=f"{kind}-shop", name="Shop", city="Bogura", settings=settings, kind=kind)


@pytest.mark.parametrize("kind", ["demo", "team_test"])
def test_demo_and_team_test_shops_may_keep_a_fixed_date(db, kind):
    db.add(_shop(kind, "2026-10-16"))
    db.flush()


def test_a_real_shop_with_a_fixed_date_fails_to_save(db):
    db.add(_shop("real", "2026-10-16"))
    with pytest.raises(ValueError, match="fixed date"):
        db.flush()
    db.rollback()


def test_a_real_shop_without_a_fixed_date_saves(db):
    db.add(_shop("real", None))
    db.flush()


def test_child_rows_take_their_shop_from_the_parent(db):
    inv = db.query(m.Invoice).filter_by(pharmacy_id="green-life").first()
    inv.lines.append(m.InvoiceLine(product="X", batch_no="B1", expiry_date=date(2027, 1, 1), qty=1,
                                   unit_cost=10, line_total=10))
    inv.payments.append(m.Payment(amount=5, paid_on=date(2026, 10, 10)))
    db.flush()
    assert {l.pharmacy_id for l in inv.lines} == {"green-life"}
    assert {p.pharmacy_id for p in inv.payments} == {"green-life"}


def test_seeded_children_all_carry_a_shop(db):
    for model in (m.InvoiceLine, m.Payment, m.PlannedOrderLine):
        assert db.query(model).filter(model.pharmacy_id.is_(None)).count() == 0
