"""Arifin's packages plug into main.py the way task I0.5 expects (build plan A0.4).

main.py imports app.<name>.routes for auth, applink and jobs, mounts api_router
under /api/v1 and root_router at the root, and starts app.jobs.runner.
"""
import importlib

from fastapi import APIRouter, FastAPI
from fastapi.testclient import TestClient

from app.applink import routes


def test_applink_has_both_routers():
    assert isinstance(routes.api_router, APIRouter)
    assert isinstance(routes.root_router, APIRouter)


def test_callbacks_stay_out_of_the_openapi_schema():
    app = FastAPI()
    app.include_router(routes.api_router, prefix="/api/v1")
    app.include_router(routes.root_router)
    paths = TestClient(app).get("/openapi.json").json()["paths"]
    assert not [p for p in paths if p.startswith("/applink/")]


def test_all_three_packages_mount_like_main_py_does():
    app = FastAPI()
    mounted = []
    for name in ("auth", "applink", "jobs"):
        mod = importlib.import_module(f"app.{name}.routes")
        if (api := getattr(mod, "api_router", None)) is not None:
            app.include_router(api, prefix="/api/v1")
            mounted.append(f"{name}:api")
        if (root := getattr(mod, "root_router", None)) is not None:
            app.include_router(root)
            mounted.append(f"{name}:root")
    assert mounted == ["auth:api", "applink:api", "applink:root", "jobs:api"]
    assert TestClient(app).get("/openapi.json").status_code == 200
