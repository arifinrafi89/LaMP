"""The sign-in package's routers (build plan A0.4; sign-in routes come in A1.2)."""
from fastapi import APIRouter, FastAPI
from fastapi.testclient import TestClient

from app.auth import routes


def test_sign_in_and_legal_live_under_api_v1_only():
    assert isinstance(routes.api_router, APIRouter)
    assert routes.auth_router.prefix == "/auth"
    assert not hasattr(routes, "root_router")
    app = FastAPI()
    app.include_router(routes.api_router, prefix="/api/v1")
    c = TestClient(app)
    assert c.get("/api/v1/legal/current").status_code == 200
    assert c.get("/api/v1/legal/terms").status_code == 200
    assert c.get("/legal/current").status_code == 404  # nothing outside /api/v1
