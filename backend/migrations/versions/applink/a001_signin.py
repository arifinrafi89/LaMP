"""Sign-in: auth_session, otp_challenge, rate_counter; the subscription mirror and consents (A1.2)

Revision ID: a001
Revises: (first of the applink branch)
Depends on: 0002 (core: the owner table)
Create Date: 2026-11-28
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a001"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = ("applink",)
depends_on: str | Sequence[str] | None = "0002"


def upgrade() -> None:
    op.create_table(
        "auth_session",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("owner_id", sa.String(), nullable=False),
        sa.Column("device_id", sa.String(), nullable=False),
        sa.Column("device_name", sa.String(), nullable=False),
        sa.Column("device_os", sa.String(), nullable=False),
        sa.Column("app_version", sa.String(), nullable=False),
        sa.Column("web", sa.Boolean(), nullable=False),
        sa.Column("refresh_hash", sa.String(), nullable=False),
        sa.Column("rotations", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("last_used_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("revoked_reason", sa.String(), nullable=True),
        sa.ForeignKeyConstraint(["owner_id"], ["owner.id"], name="fk_auth_session_owner"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_auth_session_owner_id", "auth_session", ["owner_id"])

    op.create_table(
        "otp_challenge",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("purpose", sa.String(), nullable=False),
        sa.Column("app", sa.String(), nullable=False),
        sa.Column("owner_id", sa.String(), nullable=True),
        sa.Column("phone_hash", sa.String(), nullable=False),
        sa.Column("phone_enc", sa.String(), nullable=False),
        sa.Column("reference_enc", sa.String(), nullable=True),
        sa.Column("language", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("last_code", sa.String(), nullable=True),
        sa.Column("ip_hash", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["owner_id"], ["owner.id"], name="fk_otp_challenge_owner"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_otp_challenge_phone_hash", "otp_challenge", ["phone_hash"])

    op.create_table(
        "rate_counter",
        sa.Column("key", sa.String(), nullable=False),
        sa.Column("window_start", sa.DateTime(), nullable=False),
        sa.Column("count", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("key", "window_start"),
    )

    op.create_table(
        "subscriber",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("app", sa.String(), nullable=False),
        sa.Column("subscriber_ref", sa.String(), nullable=False),
        sa.Column("owner_id", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("frequency", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("last_notified_at", sa.DateTime(), nullable=True),
        sa.Column("last_confirmed_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["owner_id"], ["owner.id"], name="fk_subscriber_owner"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("app", "subscriber_ref", name="uq_subscriber_app_ref"),
    )
    op.create_index("ix_subscriber_owner_id", "subscriber", ["owner_id"])

    op.create_table(
        "applink_consent",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("subject", sa.String(), nullable=False),
        sa.Column("subject_id", sa.String(), nullable=False),
        sa.Column("purpose", sa.String(), nullable=False),
        sa.Column("wording_version", sa.String(), nullable=False),
        sa.Column("price_text", sa.String(), nullable=True),
        sa.Column("channel", sa.String(), nullable=False),
        sa.Column("given_at", sa.DateTime(), nullable=False),
        sa.Column("withdrawn_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_applink_consent_subject_id", "applink_consent", ["subject_id"])


def downgrade() -> None:
    op.drop_index("ix_applink_consent_subject_id", table_name="applink_consent")
    op.drop_table("applink_consent")
    op.drop_index("ix_subscriber_owner_id", table_name="subscriber")
    op.drop_table("subscriber")
    op.drop_table("rate_counter")
    op.drop_index("ix_otp_challenge_phone_hash", table_name="otp_challenge")
    op.drop_table("otp_challenge")
    op.drop_index("ix_auth_session_owner_id", table_name="auth_session")
    op.drop_table("auth_session")
