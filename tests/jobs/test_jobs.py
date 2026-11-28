"""The job table, runner, scheduler, tick endpoint and /ready (build plan D6, 1.4 C, 4.3, 2.2;
task A1.3). Their own database: SQLite in memory, or TEST_DATABASE_URL (Postgres in CI, where
SKIP LOCKED is real). The loop is off in tests (JOBS_LOOP=false)."""

import asyncio
import os
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import models as m
from app.db.session import get_db
from app.jobs import config, registry, runner, scheduler
from app.jobs.models import Job
from app.main import app

NOW = datetime(2026, 11, 29, 2, 0, 0)  # UTC: 08:00 in Dhaka


_URL = os.environ.get("TEST_DATABASE_URL", "sqlite://")
ON_POSTGRES = _URL.startswith("postgresql")


@pytest.fixture
def factory():
    engine = (create_engine(_URL, connect_args={"check_same_thread": False}, poolclass=StaticPool)
              if _URL.startswith("sqlite") else create_engine(_URL))
    _drop_alembic_version(engine)
    m.Base.metadata.drop_all(engine)
    m.Base.metadata.create_all(engine)
    yield sessionmaker(bind=engine, expire_on_commit=False)
    _drop_alembic_version(engine)  # on a shared Postgres it would outlive the test, and the run
    engine.dispose()


def _drop_alembic_version(engine) -> None:
    """test_ready_reports_each_part makes this table; it isn't one of the models' tables."""
    with engine.begin() as conn:
        conn.execute(text("DROP TABLE IF EXISTS alembic_version"))


@pytest.fixture(autouse=True)
def clean_registry():
    handlers, schedule = dict(registry.HANDLERS), list(scheduler.SCHEDULE)
    runner._last_beat = None
    yield
    registry.HANDLERS.clear()
    registry.HANDLERS.update(handlers)
    scheduler.SCHEDULE[:] = schedule
    runner._last_beat = None


@pytest.fixture
def client(factory):
    def _get_db():
        db = factory()
        try:
            yield db
        finally:
            db.close()

    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = _get_db
    try:
        yield TestClient(app)
    finally:
        if previous is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = previous


def _jobs(factory):
    with factory() as db:
        return {j.id: j for j in db.scalars(select(Job))}


# --- Queuing -----------------------------------------------------------------------------

def test_enqueue_and_dedupe(factory):
    registry.job("test.noop")(lambda db, payload: None)
    with factory() as db:
        a = registry.enqueue(db, "test.noop", {"n": 1}, dedupe_key="noop:1")
        b = registry.enqueue(db, "test.noop", {"n": 2}, dedupe_key="noop:1")
        c = registry.enqueue(db, "test.noop", {"n": 3})
        db.commit()
        assert a.id == b.id != c.id and b.payload == {"n": 1}
        assert a.status == "queued" and a.attempts == 0


def test_unknown_kind_is_refused(factory):
    with factory() as db, pytest.raises(ValueError):
        registry.enqueue(db, "test.nobody-handles-this")


def test_a_kind_has_one_handler():
    registry.job("test.once")(lambda db, p: None)
    with pytest.raises(ValueError):
        registry.job("test.once")(lambda db, p: None)


# --- Running -----------------------------------------------------------------------------

def test_due_jobs_run_and_later_ones_wait(factory):
    seen = []
    registry.job("test.record")(lambda db, payload: seen.append(payload["n"]))
    with factory() as db:
        registry.enqueue(db, "test.record", {"n": 1}, run_at=NOW - timedelta(minutes=1))
        later = registry.enqueue(db, "test.record", {"n": 2}, run_at=NOW + timedelta(minutes=5))
        db.commit()
    assert runner.run_due(factory, NOW) == 1
    assert seen == [1]
    jobs = _jobs(factory)
    assert jobs[later.id].status == "queued"
    assert [j.status for j in jobs.values() if j.id != later.id] == ["done"]
    assert runner.run_due(factory, NOW) == 0  # a done job never runs again


def test_a_failure_is_retried_with_backoff_then_marked_failed(factory):
    def boom(db, payload):
        raise RuntimeError("customer +8801712345678 owes 500")

    registry.job("test.boom", max_attempts=2)(boom)
    with factory() as db:
        j = registry.enqueue(db, "test.boom", run_at=NOW)
        db.commit()
    runner.run_due(factory, NOW)
    first = _jobs(factory)[j.id]
    assert first.status == "queued" and first.attempts == 1 and first.run_at == NOW + timedelta(minutes=1)
    assert first.last_error == "RuntimeError"  # never the message: it may hold a number
    assert runner.run_due(factory, NOW) == 0  # not before its backoff
    runner.run_due(factory, NOW + timedelta(minutes=1))
    final = _jobs(factory)[j.id]
    assert final.status == "failed" and final.attempts == 2 and final.locked_by is None
    with factory() as db:
        events = list(db.scalars(select(m.AuditLog).where(m.AuditLog.component == "JOBS")))
    assert [e.event for e in events] == ["job_retry", "job_failed"]
    assert all(e.pharmacy_id is None for e in events) and "8801712345678" not in str([e.data for e in events])


def test_backoff_grows():
    assert [runner.backoff(n) for n in (1, 2, 3)] == [timedelta(minutes=1), timedelta(minutes=4),
                                                      timedelta(minutes=16)]


def test_a_failed_jobs_work_is_rolled_back(factory):
    def half_done(db, payload):
        db.add(m.Lender(id="half", name="Half", kind="bank"))
        db.flush()
        raise ValueError("stop")

    registry.job("test.half", max_attempts=1)(half_done)
    with factory() as db:
        registry.enqueue(db, "test.half", run_at=NOW)
        db.commit()
    runner.run_due(factory, NOW)
    with factory() as db:
        assert db.get(m.Lender, "half") is None


def test_a_job_logs_into_its_shops_history(factory):
    from app.engines import logbus

    def for_shop(db, payload):
        logbus.set_shop(db, payload["pid"])
        logbus.log("T2", "BRIEF", "brief_sent", db)

    registry.job("test.shop")(for_shop)
    with factory() as db:
        db.add(m.Pharmacy(id="ph-1", name="One", city="Dhaka", cash_on_hand=0, settings={}, kind="real"))
        registry.enqueue(db, "test.shop", {"pid": "ph-1"}, run_at=NOW)
        db.commit()
    runner.run_due(factory, NOW)
    with factory() as db:
        row = db.scalar(select(m.AuditLog).where(m.AuditLog.event == "brief_sent"))
    assert row.pharmacy_id == "ph-1"


def test_two_claims_never_take_the_same_job(factory):
    registry.job("test.noop")(lambda db, payload: None)
    with factory() as db:
        for _ in range(3):
            registry.enqueue(db, "test.noop", run_at=NOW)
        db.commit()
    with factory() as db:
        first = runner.claim(db, NOW, worker="w1")
    with factory() as db:
        second = runner.claim(db, NOW, worker="w2")
    assert len(first) == 3 and second == []


@pytest.mark.skipif(not ON_POSTGRES, reason="SKIP LOCKED needs Postgres (TEST_DATABASE_URL)")
def test_skip_locked_on_postgres(factory):
    """While one worker's claim is still open, another worker skips those rows (D6)."""
    registry.job("test.noop")(lambda db, payload: None)
    with factory() as db:
        for _ in range(4):
            registry.enqueue(db, "test.noop", run_at=NOW)
        db.commit()
    with factory() as holder, factory() as other:
        held = list(holder.scalars(select(Job).where(Job.status == "queued").order_by(Job.id).limit(2)
                                   .with_for_update(skip_locked=True)))
        taken = runner.claim(other, NOW, worker="w2")  # the holder hasn't committed yet
        assert len(held) == 2 and sorted(taken) == sorted(
            j.id for j in _jobs(factory).values() if j.id not in {h.id for h in held})
        holder.rollback()


def test_a_job_left_running_by_a_dead_worker_comes_back(factory):
    registry.job("test.noop")(lambda db, payload: None)
    with factory() as db:
        registry.enqueue(db, "test.noop", run_at=NOW)
        db.commit()
    with factory() as db:
        [jid] = runner.claim(db, NOW, worker="dead")
    with factory() as db:
        assert runner.claim(db, NOW + timedelta(minutes=9), worker="w2") == []
    with factory() as db:
        assert runner.claim(db, NOW + timedelta(minutes=11), worker="w2") == [jid]


# --- The scheduler (Asia/Dhaka) ----------------------------------------------------------

def test_a_daily_job_is_queued_once_a_day_from_its_dhaka_time(factory):
    registry.job("test.brief")(lambda db, payload: None)
    scheduler.daily("test.brief", "08:00")
    with factory() as db:
        assert scheduler.tick(db, NOW - timedelta(minutes=1)) == 0  # 07:59 in Dhaka
        assert scheduler.tick(db, NOW) == 1
        assert scheduler.tick(db, NOW + timedelta(hours=3)) == 0     # once that day
        assert scheduler.tick(db, NOW + timedelta(days=1)) == 1      # and again the next
        db.commit()
        keys = sorted(j.dedupe_key for j in db.scalars(select(Job)))
    assert keys == ["test.brief:2026-11-29", "test.brief:2026-11-30"]


def test_the_dhaka_date_not_the_utc_date(factory):
    registry.job("test.late")(lambda db, payload: None)
    scheduler.daily("test.late", "03:00")
    with factory() as db:
        scheduler.tick(db, datetime(2026, 11, 29, 21, 30))  # 03:30 on 30 Nov in Dhaka
        [j] = db.scalars(select(Job))
    assert j.payload == {"on": "2026-11-30"}


def test_a_kind_is_scheduled_once():
    scheduler.daily("test.twice", "08:00")
    with pytest.raises(ValueError):
        scheduler.daily("test.twice", "09:00")


# --- The loop's heartbeat ----------------------------------------------------------------

def test_a_pass_beats_and_the_beat_goes_stale(factory):
    assert runner.healthy(NOW) is False
    runner.cycle(factory, NOW)
    assert runner.healthy(NOW + timedelta(seconds=119)) is True
    assert runner.healthy(NOW + timedelta(minutes=2)) is False


def test_the_loop_runs_inside_the_service(factory, monkeypatch):
    monkeypatch.setenv("JOBS_LOOP", "true")
    monkeypatch.setenv("JOBS_POLL_SECONDS", "0.01")
    config.get_settings.cache_clear()
    seen = []
    registry.job("test.loop")(lambda db, payload: seen.append(1))
    with factory() as db:
        registry.enqueue(db, "test.loop")  # due now, by the real clock the loop reads
        db.commit()

    async def run():
        await runner.start(factory)
        await runner.start(factory)  # a second start does nothing
        for _ in range(100):
            if seen:
                break
            await asyncio.sleep(0.02)
        await runner.stop()
        await runner.stop()

    try:
        asyncio.run(run())
    finally:
        config.get_settings.cache_clear()
    assert seen == [1] and runner.healthy()


# --- The tick endpoint and /ready --------------------------------------------------------

def test_the_tick_needs_its_secret(client):
    assert client.post("/api/v1/internal/jobs/tick").status_code == 404
    assert client.post("/api/v1/internal/jobs/tick", headers={"X-Tick-Secret": "wrong"}).status_code == 404


def test_the_tick_queues_and_runs_whats_due(client, factory):
    seen = []
    registry.job("test.tick")(lambda db, payload: seen.append(payload["on"]))
    scheduler.daily("test.tick", "00:00")
    secret = config.get_settings().tick_secret()  # the dev value: DEV_MODE is on in tests
    r = client.post("/api/v1/internal/jobs/tick", headers={"X-Tick-Secret": secret})
    assert r.status_code == 200, r.text
    assert r.json() == {"queued": 1, "ran": 1} and len(seen) == 1
    assert client.post("/api/v1/internal/jobs/tick", headers={"X-Tick-Secret": secret}).json() == {"queued": 0,
                                                                                                 "ran": 0}


def test_a_real_server_needs_a_tick_secret(monkeypatch):
    monkeypatch.setenv("DEV_MODE", "false")
    monkeypatch.delenv("JOBS_TICK_SECRET", raising=False)
    assert config.JobsSettings(_env_file=None).problems() == ["JOBS_TICK_SECRET is not set"]
    monkeypatch.setenv("JOBS_TICK_SECRET", "short")
    assert config.JobsSettings(_env_file=None).problems() == ["JOBS_TICK_SECRET is shorter than 32 characters"]
    monkeypatch.setenv("JOBS_TICK_SECRET", "x" * 32)
    assert config.JobsSettings(_env_file=None).problems() == []


def test_ready_reports_each_part(client, factory):
    r = client.get("/api/v1/ready")
    assert r.status_code == 503
    assert r.json() == {"status": "not_ready", "database": True, "migrations": False, "jobs": False}

    from app.api.routes import _migration_heads

    with factory() as db:
        db.execute(text("CREATE TABLE alembic_version (version_num VARCHAR(32) NOT NULL)"))
        for head in _migration_heads():
            db.execute(text("INSERT INTO alembic_version VALUES (:v)"), {"v": head})
        db.commit()
    runner.beat()
    r = client.get("/api/v1/ready")
    assert r.status_code == 200 and r.json() == {"status": "ok", "database": True, "migrations": True, "jobs": True}
