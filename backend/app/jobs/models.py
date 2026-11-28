"""The job table (build plan 4.3, D6; task A1.3): one row per piece of background work.

A Postgres table claimed with FOR UPDATE SKIP LOCKED, so two workers never run one job; no
Redis. `dedupe_key` is unique, so the same work (e.g. "reminder:<code>:<part>:<date>") is
queued once however many times it is asked for.
"""
from datetime import datetime

from sqlalchemy import JSON, DateTime, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.models import Base

STATUSES = ("queued", "running", "done", "failed")


class Job(Base):
    __tablename__ = "job"
    __table_args__ = (Index("ix_job_due", "status", "run_at"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    kind: Mapped[str] = mapped_column(String)
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    run_at: Mapped[datetime] = mapped_column(DateTime)               # UTC, naive
    dedupe_key: Mapped[str | None] = mapped_column(String, unique=True, nullable=True)
    status: Mapped[str] = mapped_column(String, default="queued")    # STATUSES
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    last_error: Mapped[str | None] = mapped_column(String, nullable=True)  # the error's type only: no data
    locked_by: Mapped[str | None] = mapped_column(String, nullable=True)   # host:pid of the worker
    locked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
