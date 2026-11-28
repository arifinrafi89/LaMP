"""Setup columns: a supplier's phone, payment days and removal; a batch's strength; how a
supplier was paid (build plan 2.2 "Shop setup" and "Daily screens"; task I2.2)

Revision ID: 0004
Revises: 0003
Create Date: 2026-11-29
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0004"
down_revision: str | Sequence[str] | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("supplier") as b:
        b.add_column(sa.Column("phone", sa.String(), nullable=True))
        b.add_column(sa.Column("payment_days", sa.Integer(), server_default="30", nullable=False))
        b.add_column(sa.Column("deleted_at", sa.DateTime(), nullable=True))
    with op.batch_alter_table("stock_batch") as b:
        b.add_column(sa.Column("strength", sa.String(), nullable=True))
    with op.batch_alter_table("payment") as b:
        b.add_column(sa.Column("method", sa.String(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("payment") as b:
        b.drop_column("method")
    with op.batch_alter_table("stock_batch") as b:
        b.drop_column("strength")
    with op.batch_alter_table("supplier") as b:
        b.drop_column("deleted_at")
        b.drop_column("payment_days")
        b.drop_column("phone")
