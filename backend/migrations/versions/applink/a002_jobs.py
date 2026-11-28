"""The job table (build plan 4.3, D6; task A1.3)

Revision ID: a002
Revises: a001
Create Date: 2026-11-29
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a002"
down_revision: str | Sequence[str] | None = "a001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "job",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("run_at", sa.DateTime(), nullable=False),
        sa.Column("dedupe_key", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("last_error", sa.String(), nullable=True),
        sa.Column("locked_by", sa.String(), nullable=True),
        sa.Column("locked_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("dedupe_key"),
    )
    op.create_index("ix_job_due", "job", ["status", "run_at"])


def downgrade() -> None:
    op.drop_index("ix_job_due", table_name="job")
    op.drop_table("job")
