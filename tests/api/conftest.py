"""In-memory SQLite database with the seed pharmacy, for API tests."""

import os

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.seed import load_seed
from app.db.session import get_db
from app.main import app

# SQLite in memory by default; set TEST_DATABASE_URL to run against PostgreSQL, e.g.
# postgresql+psycopg://lamp:lamp@localhost:5432/lamp_test
_url = os.environ.get("TEST_DATABASE_URL", "sqlite://")
engine = (create_engine(_url, connect_args={"check_same_thread": False}, poolclass=StaticPool)
          if _url.startswith("sqlite") else create_engine(_url))
TestSession = sessionmaker(bind=engine, expire_on_commit=False)


def _get_db():
    db = TestSession()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = _get_db



@pytest.fixture
def anon():
    """A fresh seed and a client that hasn't signed in."""
    with TestSession() as s:
        load_seed(s, with_demo_captures=True)
    return TestClient(app)


@pytest.fixture
def client(anon, owner_headers):
    """Signed in as the owner of green-life (the same client as `anon`, now carrying the
    owner's bearer token). Lender calls pass headers=lender_headers(...)."""
    with TestSession() as s:
        anon.headers.update(owner_headers(s))
    return anon


@pytest.fixture
def api_db():
    """A session on the API tests' database."""
    with TestSession() as s:
        yield s
