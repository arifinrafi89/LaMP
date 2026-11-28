"""The plan as it was set: the card's balance then, and the day (build plan 2.2, a customer
row's `trusted`, "all parts paid on time"; task I2.2)

Revision ID: 0005
Revises: 0004
Create Date: 2026-11-29
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0005"
down_revision: str | Sequence[str] | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("patient_dues") as b:
        b.add_column(sa.Column("plan_amount", sa.Float(), nullable=True))
        b.add_column(sa.Column("plan_set_on", sa.Date(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("patient_dues") as b:
        b.drop_column("plan_set_on")
        b.drop_column("plan_amount")
