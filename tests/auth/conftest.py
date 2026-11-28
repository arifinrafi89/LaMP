"""Sign-in tests: their own in-memory database with the demo shop, the real app, and the
Applink mock (APPLINK_MODE=mock). The override is put back after each test."""

import os

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.applink.client import factory
from app.auth.config import get_settings
from app.db.seed import load_seed
from app.db.session import get_db
from app.main import app

_url = os.environ.get("TEST_DATABASE_URL", "sqlite://")
engine = (create_engine(_url, connect_args={"check_same_thread": False}, poolclass=StaticPool)
          if _url.startswith("sqlite") else create_engine(_url))
AuthTestSession = sessionmaker(bind=engine, expire_on_commit=False)


def _get_db():
    db = AuthTestSession()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture
def auth_db():
    with AuthTestSession() as s:
        yield s


@pytest.fixture
def web(monkeypatch):
    """A client on a fresh seed, signed in as nobody."""
    monkeypatch.setenv("APPLINK_MODE", "mock")
    monkeypatch.delenv("APP_ENV", raising=False)
    factory.reset()
    get_settings.cache_clear()
    with AuthTestSession() as s:
        load_seed(s)
    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = _get_db
    try:
        yield TestClient(app)
    finally:
        if previous is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = previous
        get_settings.cache_clear()
        factory.reset()
