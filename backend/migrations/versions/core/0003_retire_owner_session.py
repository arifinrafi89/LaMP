"""Retire owner_session: owners sign in with their phone now (auth_session, I2.1)

Revision ID: 0003
Revises: 0002
Create Date: 2026-11-28
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | Sequence[str] | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_table("owner_session")


def downgrade() -> None:
    op.create_table(
        "owner_session",
        sa.Column("token", sa.String(), nullable=False),
        sa.Column("pharmacy_id", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["pharmacy_id"], ["pharmacy.id"]),
        sa.PrimaryKeyConstraint("token"),
    )
