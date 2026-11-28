"""Database tables (docs/PLAN.md section 5).

Portable SQLAlchemy 2.0 models: PostgreSQL in Docker, SQLite in tests.
Money is stored as Float in whole or 2-decimal BDT; engines round outputs to 2 decimals.
"""

from datetime import date, datetime

from sqlalchemy import JSON, Boolean, Date, DateTime, Float, ForeignKey, Integer, String, event, false
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, relationship

# Pharmacy kinds (build plan 4.2). Only demo and team_test shops may keep a fixed
# settings.as_of_date; real shops always run on today's Dhaka date.
PHARMACY_KINDS = ("real", "demo", "team_test")
FIXED_DATE_KINDS = ("demo", "team_test")


class Base(DeclarativeBase):
    pass


class Pharmacy(Base):
    __tablename__ = "pharmacy"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str]
    city: Mapped[str]
    cash_on_hand: Mapped[float] = mapped_column(Float, default=0)  # at the start of settings.as_of_date
    settings: Mapped[dict] = mapped_column(JSON)
    kind: Mapped[str] = mapped_column(String, default="real", server_default="real")  # PHARMACY_KINDS
    # Two letters at the start of every card code (GL-7KQM-4XPA), set when the shop is created.
    card_prefix: Mapped[str | None] = mapped_column(String(2), nullable=True)
    setup_complete: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    created_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Owner(Base):
    """The person who runs a pharmacy (one per pharmacy in Phase 1). The phone number is kept
    only as a keyed hash (to find the owner at sign-in) and encrypted (to show it masked)."""

    __tablename__ = "owner"
    id: Mapped[str] = mapped_column(String, primary_key=True)  # uuid
    pharmacy_id: Mapped[str | None] = mapped_column(ForeignKey("pharmacy.id"), nullable=True)  # null until setup
    subscriber_ref: Mapped[str | None] = mapped_column(String, nullable=True)  # as Applink returned it
    phone_hash: Mapped[str] = mapped_column(String, unique=True)  # HMAC with a server pepper
    phone_enc: Mapped[str] = mapped_column(String)                # AES-GCM
    language: Mapped[str] = mapped_column(String, default="en")   # en | bn
    created_at: Mapped[datetime] = mapped_column(DateTime)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Supplier(Base):
    __tablename__ = "supplier"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    name: Mapped[str]
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    return_cutoff_days: Mapped[int] = mapped_column(Integer, default=30)
    # A business contact, used only for the share-to-supplier draft (build plan 2.2).
    phone: Mapped[str | None] = mapped_column(String, nullable=True)
    payment_days: Mapped[int] = mapped_column(Integer, default=30, server_default="30")
    # Removed by the owner. Kept, because invoices and stock batches point at it.
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Invoice(Base):
    __tablename__ = "invoice"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    supplier_id: Mapped[int] = mapped_column(ForeignKey("supplier.id"))
    invoice_no: Mapped[str]
    invoice_date: Mapped[date] = mapped_column(Date)
    due_date: Mapped[date] = mapped_column(Date)
    total: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String, default="unpaid")  # unpaid | paid
    supplier_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    capture_id: Mapped[str | None] = mapped_column(String, nullable=True)
    supplier: Mapped[Supplier] = relationship()
    lines: Mapped[list["InvoiceLine"]] = relationship(back_populates="invoice", cascade="all, delete-orphan")
    payments: Mapped[list["Payment"]] = relationship(back_populates="invoice", cascade="all, delete-orphan")


class InvoiceLine(Base):
    __tablename__ = "invoice_line"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    invoice_id: Mapped[int] = mapped_column(ForeignKey("invoice.id"))
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))  # copied from the parent on flush
    product: Mapped[str]
    strength: Mapped[str | None] = mapped_column(String, nullable=True)
    pack: Mapped[str | None] = mapped_column(String, nullable=True)
    batch_no: Mapped[str]
    expiry_date: Mapped[date] = mapped_column(Date)
    qty: Mapped[int]
    unit_cost: Mapped[float] = mapped_column(Float)
    line_total: Mapped[float] = mapped_column(Float)
    invoice: Mapped[Invoice] = relationship(back_populates="lines")


class Payment(Base):
    __tablename__ = "payment"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    invoice_id: Mapped[int] = mapped_column(ForeignKey("invoice.id"))
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))  # copied from the parent on flush
    amount: Mapped[float] = mapped_column(Float)
    paid_on: Mapped[date] = mapped_column(Date)
    method: Mapped[str | None] = mapped_column(String, nullable=True)  # cash | bkash | nagad | other
    invoice: Mapped[Invoice] = relationship(back_populates="payments")


class SalesDay(Base):
    __tablename__ = "sales_day"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    date: Mapped[date] = mapped_column(Date)
    cash_sales: Mapped[float] = mapped_column(Float, default=0)
    credit_sales: Mapped[float] = mapped_column(Float, default=0)
    dues_collected: Mapped[float] = mapped_column(Float, default=0)
    expenses: Mapped[float] = mapped_column(Float, default=0)


class PatientDue(Base):
    """Amounts only, under an alias. Never medicine names."""

    __tablename__ = "patient_dues"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    label: Mapped[str]
    amount: Mapped[float] = mapped_column(Float)
    since: Mapped[date] = mapped_column(Date)
    # The customer's own card (/me/<code>): the code is the only key, so it is long and random.
    code: Mapped[str] = mapped_column(String, unique=True)
    plan_parts: Mapped[int | None] = mapped_column(Integer, default=None)
    plan_first_on: Mapped[date | None] = mapped_column(Date, default=None)


class PatientLedger(Base):
    """Every sale, payment or correction on a customer card. Amounts only: no names, no
    medicines. patient_dues.amount is the running balance these rows add up to."""

    __tablename__ = "patient_ledger"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    code: Mapped[str] = mapped_column(ForeignKey("patient_dues.code"))
    kind: Mapped[str]  # sale | payment | adjust
    amount: Mapped[float] = mapped_column(Float)  # + adds to what is owed, - reduces it
    on_date: Mapped[date] = mapped_column(Date)
    method: Mapped[str | None] = mapped_column(String, nullable=True)  # cash | bkash | nagad | other
    created_at: Mapped[datetime] = mapped_column(DateTime)


class ExpenseSchedule(Base):
    __tablename__ = "expense_schedule"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    category: Mapped[str]
    amount: Mapped[float] = mapped_column(Float)
    day_of_month: Mapped[int]


class StockBatch(Base):
    __tablename__ = "stock_batch"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    supplier_id: Mapped[int] = mapped_column(ForeignKey("supplier.id"))
    product: Mapped[str]
    strength: Mapped[str | None] = mapped_column(String, nullable=True)
    batch_no: Mapped[str]
    expiry_date: Mapped[date] = mapped_column(Date)
    qty: Mapped[int]
    unit_cost: Mapped[float] = mapped_column(Float)
    supplier: Mapped[Supplier] = relationship()


class PlannedOrder(Base):
    __tablename__ = "planned_order"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    supplier_id: Mapped[int] = mapped_column(ForeignKey("supplier.id"))
    ref: Mapped[str]
    due_date: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String, default="planned")  # planned | paid | cancelled
    # Set when the supplier accepts an extension: this much is paid deferred_days later.
    deferred_amount: Mapped[float] = mapped_column(Float, default=0)
    deferred_days: Mapped[int] = mapped_column(Integer, default=0)
    supplier: Mapped[Supplier] = relationship()
    lines: Mapped[list["PlannedOrderLine"]] = relationship(back_populates="order", cascade="all, delete-orphan")

    @property
    def total(self) -> float:
        return sum(l.qty * l.unit_cost for l in self.lines)


class PlannedOrderLine(Base):
    __tablename__ = "planned_order_line"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    order_id: Mapped[str] = mapped_column(ForeignKey("planned_order.id"))
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))  # copied from the parent on flush
    product: Mapped[str]
    qty: Mapped[int]
    unit_cost: Mapped[float] = mapped_column(Float)
    expiry_date: Mapped[date] = mapped_column(Date)
    order: Mapped[PlannedOrder] = relationship(back_populates="lines")


class Lender(Base):
    __tablename__ = "lender"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str]
    kind: Mapped[str]
    api_key_sha256: Mapped[str | None] = mapped_column(String, nullable=True)
    products: Mapped[list["LenderProduct"]] = relationship(back_populates="lender", cascade="all, delete-orphan")


class LenderProduct(Base):
    __tablename__ = "lender_product"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    lender_id: Mapped[str] = mapped_column(ForeignKey("lender.id"))
    key: Mapped[str]
    label: Mapped[str]
    apr_pct: Mapped[float | None] = mapped_column(Float, nullable=True)
    fee_pct: Mapped[float | None] = mapped_column(Float, nullable=True)
    min_amount: Mapped[float] = mapped_column(Float)
    max_amount: Mapped[float] = mapped_column(Float)
    tenor_days: Mapped[int]
    min_history_invoices: Mapped[int] = mapped_column(Integer, default=0)
    min_history_months: Mapped[int] = mapped_column(Integer, default=0)
    cost_bearer: Mapped[str] = mapped_column(String, default="pharmacy")
    lender: Mapped[Lender] = relationship(back_populates="products")


class Capture(Base):
    __tablename__ = "capture"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    kind: Mapped[str]
    status: Mapped[str] = mapped_column(String, default="needs_review")
    extraction: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime)


class ReturnClaim(Base):
    __tablename__ = "return_claim"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    action_id: Mapped[str]
    supplier: Mapped[str]
    batch_no: Mapped[str]
    expected_credit: Mapped[float] = mapped_column(Float)
    created_at: Mapped[datetime] = mapped_column(DateTime)


class SetAside(Base):
    __tablename__ = "set_aside"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    action_id: Mapped[str]
    amount: Mapped[float] = mapped_column(Float)
    start: Mapped[date] = mapped_column(Date)
    created_at: Mapped[datetime] = mapped_column(DateTime)


# Consents, lender applications, registry, actions, audit log.

class Consent(Base):
    __tablename__ = "consent"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    lender_id: Mapped[str] = mapped_column(ForeignKey("lender.id"))
    scopes: Mapped[list] = mapped_column(JSON)
    granted_at: Mapped[datetime] = mapped_column(DateTime)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Application(Base):
    __tablename__ = "application"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    action_id: Mapped[str | None] = mapped_column(String, nullable=True)
    lender_id: Mapped[str] = mapped_column(ForeignKey("lender.id"))
    product_key: Mapped[str]
    amount: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String, default="pending")
    decision: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime)


class RegistryLock(Base):
    __tablename__ = "registry_lock"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    commitment: Mapped[str] = mapped_column(String, unique=True)
    application_id: Mapped[str]
    created_at: Mapped[datetime] = mapped_column(DateTime)


class Action(Base):
    __tablename__ = "action"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    kind: Mapped[str]
    status: Mapped[str] = mapped_column(String, default="proposed")
    payload: Mapped[dict] = mapped_column(JSON)
    proposed_by: Mapped[str]
    created_at: Mapped[datetime] = mapped_column(DateTime)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    result: Mapped[dict | None] = mapped_column(JSON, nullable=True)


class WalletTxn(Base):
    """Sandbox wallet movements LaMP caused (loan payouts). The opening balance is the
    pharmacy's cash on hand minus these."""

    __tablename__ = "wallet_txn"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    date: Mapped[date] = mapped_column(Date)
    amount: Mapped[float] = mapped_column(Float)  # + in, - out
    kind: Mapped[str]
    ref: Mapped[str]
    created_at: Mapped[datetime] = mapped_column(DateTime)


class StatementLine(Base):
    """External wallet/bank statement lines (seeded), to reconcile against the books."""

    __tablename__ = "statement_line"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    date: Mapped[date] = mapped_column(Date)
    amount: Mapped[float] = mapped_column(Float)  # + credit, - debit
    payee: Mapped[str]
    ref: Mapped[str]


class FollowUp(Base):
    """A conditional step of an approved plan: if the supplier declines or doesn't reply,
    LaMP proposes the fallback (it still needs the owner's approval)."""

    __tablename__ = "followup"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    pharmacy_id: Mapped[str] = mapped_column(ForeignKey("pharmacy.id"))
    plan_action_id: Mapped[str]
    fallback_kind: Mapped[str]
    fallback_payload: Mapped[dict] = mapped_column(JSON)
    amount: Mapped[float] = mapped_column(Float)
    deadline: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String, default="waiting")  # waiting | fired | cancelled
    trigger: Mapped[str | None] = mapped_column(String, nullable=True)  # declined | no_reply, once known
    fired_action_id: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime)


class AuditLog(Base):
    __tablename__ = "audit_log"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    # The shop an event belongs to (null for system events). The per-shop hash chain comes later.
    pharmacy_id: Mapped[str | None] = mapped_column(String, nullable=True)
    ts: Mapped[datetime] = mapped_column(DateTime)
    tier: Mapped[str]
    component: Mapped[str]
    event: Mapped[str]
    data: Mapped[dict] = mapped_column(JSON)
    # Hash chain: hash = sha256(prev_hash + canonical event). Editing any row breaks it.
    prev_hash: Mapped[str] = mapped_column(String, default="")
    hash: Mapped[str] = mapped_column(String, default="")


# Child rows carry their shop's id, so every pharmacy table can be filtered (and, in Phase 2,
# locked by row-level security) on pharmacy_id alone. The id comes from the parent row.
_CHILD_PARENT = {InvoiceLine: "invoice", Payment: "invoice", PlannedOrderLine: "order"}


@event.listens_for(Session, "before_flush")
def _shop_rules(session: Session, _ctx, _instances) -> None:
    for obj in list(session.new) + list(session.dirty):
        parent_attr = _CHILD_PARENT.get(type(obj))
        if parent_attr and obj.pharmacy_id is None:
            parent = getattr(obj, parent_attr)
            if parent is not None:
                obj.pharmacy_id = parent.pharmacy_id
        if isinstance(obj, Pharmacy):
            check_pharmacy(obj)


def check_pharmacy(ph: Pharmacy) -> None:
    """A real shop never has a fixed date: its "today" is always today in Dhaka."""
    kind = ph.kind or "real"
    if kind not in PHARMACY_KINDS:
        raise ValueError(f"Unknown pharmacy kind {kind!r}.")
    if kind not in FIXED_DATE_KINDS and (ph.settings or {}).get("as_of_date"):
        raise ValueError("A real pharmacy can't have a fixed date (settings.as_of_date).")
