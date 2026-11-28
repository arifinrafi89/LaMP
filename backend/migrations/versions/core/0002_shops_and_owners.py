"""Shops and owners: owner, shop kind, pharmacy_id on child tables, patient_ledger (I1.1)

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-26

Child rows get their shop's id copied from the parent row before the column
becomes NOT NULL, so a database already holding the demo shop upgrades cleanly.
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | Sequence[str] | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# child table -> (parent table, foreign-key column in the child)
CHILDREN = {
    "invoice_line": ("invoice", "invoice_id"),
    "payment": ("invoice", "invoice_id"),
    "planned_order_line": ("planned_order", "order_id"),
}


def upgrade() -> None:
    with op.batch_alter_table("pharmacy") as b:
        b.add_column(sa.Column("kind", sa.String(), server_default="real", nullable=False))
        b.add_column(sa.Column("card_prefix", sa.String(length=2), nullable=True))
        b.add_column(sa.Column("setup_complete", sa.Boolean(), server_default=sa.false(), nullable=False))
        b.add_column(sa.Column("created_at", sa.DateTime(), nullable=True))
        b.add_column(sa.Column("deleted_at", sa.DateTime(), nullable=True))
    # Shops from before this revision are the copied demo shop.
    op.execute("UPDATE pharmacy SET kind = 'demo', setup_complete = true")

    op.create_table(
        "owner",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("pharmacy_id", sa.String(), nullable=True),
        sa.Column("subscriber_ref", sa.String(), nullable=True),
        sa.Column("phone_hash", sa.String(), nullable=False),
        sa.Column("phone_enc", sa.String(), nullable=False),
        sa.Column("language", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("deleted_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["pharmacy_id"], ["pharmacy.id"], name="fk_owner_pharmacy"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("phone_hash", name="uq_owner_phone_hash"),
    )

    for child, (parent, fk) in CHILDREN.items():
        with op.batch_alter_table(child) as b:
            b.add_column(sa.Column("pharmacy_id", sa.String(), nullable=True))
        op.execute(f"UPDATE {child} SET pharmacy_id = "
                   f"(SELECT {parent}.pharmacy_id FROM {parent} WHERE {parent}.id = {child}.{fk})")
        with op.batch_alter_table(child) as b:
            b.alter_column("pharmacy_id", existing_type=sa.String(), nullable=False)
            b.create_foreign_key(f"fk_{child}_pharmacy", "pharmacy", ["pharmacy_id"], ["id"])

    with op.batch_alter_table("audit_log") as b:
        b.add_column(sa.Column("pharmacy_id", sa.String(), nullable=True))

    op.create_table(
        "patient_ledger",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("pharmacy_id", sa.String(), nullable=False),
        sa.Column("code", sa.String(), nullable=False),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("amount", sa.Float(), nullable=False),
        sa.Column("on_date", sa.Date(), nullable=False),
        sa.Column("method", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["code"], ["patient_dues.code"], name="fk_patient_ledger_code"),
        sa.ForeignKeyConstraint(["pharmacy_id"], ["pharmacy.id"], name="fk_patient_ledger_pharmacy"),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    op.drop_table("patient_ledger")
    with op.batch_alter_table("audit_log") as b:
        b.drop_column("pharmacy_id")
    for child in reversed(list(CHILDREN)):
        with op.batch_alter_table(child) as b:
            b.drop_constraint(f"fk_{child}_pharmacy", type_="foreignkey")
            b.drop_column("pharmacy_id")
    op.drop_table("owner")
    with op.batch_alter_table("pharmacy") as b:
        for col in ("deleted_at", "created_at", "setup_complete", "card_prefix", "kind"):
            b.drop_column(col)
