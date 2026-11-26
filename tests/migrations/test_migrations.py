"""Migrations (build plan 4.4, I1.1): they build exactly the models' schema, go down and
up again, and carry an existing demo shop's rows over with their pharmacy_id filled in."""

from pathlib import Path

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, text

from app.db.models import Base

BACKEND = Path(__file__).resolve().parents[2] / "backend"


@pytest.fixture
def db_url(tmp_path):
    return f"sqlite:///{(tmp_path / 'mig.db').as_posix()}"


def _cfg(url: str) -> Config:
    cfg = Config(str(BACKEND / "alembic.ini"))
    cfg.set_main_option("sqlalchemy.url", url)
    return cfg


def test_heads_match_the_models(db_url):
    command.upgrade(_cfg(db_url), "heads")
    with create_engine(db_url).connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    assert diff == []


def test_down_and_up_again(db_url):
    cfg = _cfg(db_url)
    command.upgrade(cfg, "heads")
    command.downgrade(cfg, "-1")
    command.upgrade(cfg, "heads")
    command.downgrade(cfg, "base")


def test_existing_rows_get_their_shop(db_url):
    cfg = _cfg(db_url)
    command.upgrade(cfg, "0001")
    eng = create_engine(db_url)
    with eng.begin() as c:
        c.execute(text("INSERT INTO pharmacy (id, name, city, cash_on_hand, settings) "
                       "VALUES ('green-life', 'Green Life', 'Bogura', 0, '{\"as_of_date\": \"2026-10-16\"}')"))
        c.execute(text("INSERT INTO supplier (id, pharmacy_id, name, verified, return_cutoff_days) "
                       "VALUES (1, 'green-life', 'A', 1, 30)"))
        c.execute(text("INSERT INTO invoice (id, pharmacy_id, supplier_id, invoice_no, invoice_date, due_date, total, "
                       "status, supplier_confirmed) VALUES (1, 'green-life', 1, 'X1', '2026-10-01', '2026-10-31', 100, "
                       "'unpaid', 1)"))
        c.execute(text("INSERT INTO invoice_line (id, invoice_id, product, batch_no, expiry_date, qty, unit_cost, "
                       "line_total) VALUES (1, 1, 'P', 'B', '2027-01-01', 1, 100, 100)"))
        c.execute(text("INSERT INTO payment (id, invoice_id, amount, paid_on) VALUES (1, 1, 50, '2026-10-05')"))
    command.upgrade(cfg, "heads")
    with eng.connect() as c:
        assert c.execute(text("SELECT pharmacy_id FROM invoice_line")).scalar() == "green-life"
        assert c.execute(text("SELECT pharmacy_id FROM payment")).scalar() == "green-life"
        assert c.execute(text("SELECT kind FROM pharmacy")).scalar() == "demo"
