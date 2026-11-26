"""main.py mounts Arifin's packages once they exist (build plan I0.5)."""

import importlib
import sys
import types

from fastapi import APIRouter
from fastapi.testclient import TestClient


def _fake_package(name: str, *, api: bool, root: bool) -> None:
    pkg = types.ModuleType(f"app.{name}")
    pkg.__path__ = []
    routes = types.ModuleType(f"app.{name}.routes")
    if api:
        r = APIRouter()
        r.get(f"/{name}-probe")(lambda: {"ok": name})
        routes.api_router = r
    if root:
        r = APIRouter()
        r.get(f"/{name}-root-probe")(lambda: {"ok": name})
        routes.root_router = r
    sys.modules[f"app.{name}"] = pkg
    sys.modules[f"app.{name}.routes"] = routes


def test_missing_packages_are_skipped():
    from app import main

    for m in main.MOUNTED:  # anything mounted is a package that really exists
        assert importlib.util.find_spec(f"app.{m.split(':')[0]}") is not None


def test_routers_mount_under_api_and_root(monkeypatch):
    from app import main

    _fake_package("auth", api=True, root=False)
    _fake_package("applink", api=True, root=True)
    try:
        mounted = main._mount_plugged_in()
        c = TestClient(main.app)
        answers = [c.get(p).status_code for p in ("/api/v1/auth-probe", "/api/v1/applink-probe", "/applink-root-probe")]
    finally:
        for k in ("app.auth", "app.auth.routes", "app.applink", "app.applink.routes"):
            sys.modules.pop(k, None)
    assert {"auth:api", "applink:api", "applink:root"} <= set(mounted)
    assert answers == [200, 200, 200]
