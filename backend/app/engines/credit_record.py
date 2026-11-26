"""The customer's credit record, bought for BDT 10 (build plan 1.4 B; built in I3.2)."""

from sqlalchemy.orm import Session


def on_paid(db: Session, pid: str, charge_id: str) -> None:
    """Called by Arifin's charge flow once Applink confirms the BDT 10 payment. Marks the
    record as bought for that shop. Not built yet: I3.2."""
    raise NotImplementedError("credit_record.on_paid is built in I3.2")
