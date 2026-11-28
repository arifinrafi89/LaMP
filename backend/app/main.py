"""FastAPI entry point. All routes live under /api/v1."""

import asyncio
import importlib
import threading
import traceback
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import func, inspect, select

from app.api import problems
from app.api.routes import router
from app.config import registry_secret, settings
from app.db.models import Pharmacy
from app.db.seed import load_seed
from app.db.session import SessionLocal, engine, get_db
from app.engines import logbus, mailer

API_PREFIX = "/api/v1"


def _seed_if_empty() -> None:
    """The schema comes only from migrations (`alembic upgrade heads` in the start command,
    build plan 4.4). A database with no shop yet gets the demo shop; nothing is ever wiped."""
    if not inspect(engine).has_table("pharmacy"):
        raise RuntimeError("The database has no tables. Run `alembic upgrade heads` from backend/ first.")
    with SessionLocal() as db:
        if db.scalar(select(func.count()).select_from(Pharmacy)) == 0:
            load_seed(db, with_demo_captures=settings.demo_reset_with_captures)


@asynccontextmanager
async def lifespan(_: FastAPI):
    try:
        registry_secret()  # refuse to start without a real REGISTRY_KEY (unless DEV_MODE)
        _check_plugged_in()  # sign-in and Applink settings (JWT_SECRET, PHONE_PEPPER, PII_KEY, …)
        _seed_if_empty()
    except Exception as exc:
        mailer.alert("startup", "[LaMP] API failed to start",
                     f"The API stopped during startup at {_now()}.\n\n{type(exc).__name__}: {exc}\n\n"
                     "Check the backend logs (docker compose logs backend) and restart it.", background=False)
        raise
    auto = asyncio.create_task(_auto_reset()) if settings.dev_mode and settings.demo_auto_reset_minutes > 0 else None
    # Arifin's job loop runs inside the web service (plan D6): app.jobs.runner.start() / stop().
    runner = _optional("app.jobs.runner")
    if runner is not None and hasattr(runner, "start"):
        await runner.start()
    yield
    if runner is not None and hasattr(runner, "stop"):
        await runner.stop()
    if auto:
        auto.cancel()


def _check_plugged_in() -> None:
    """Each plugged-in package may refuse a broken setup: `app.<name>.config.check()`."""
    for name in PLUGGED_IN:
        config = _optional(f"app.{name}.config")
        if config is not None and hasattr(config, "check"):
            config.check()


def _optional(module: str):
    """A module that may not exist yet (Arifin's packages before A0.4)."""
    try:
        return importlib.import_module(module)
    except ModuleNotFoundError as exc:
        if module.startswith(exc.name or "?"):
            return None
        raise


async def _auto_reset() -> None:
    """Shared demo: judges use one database, so put the story back every N minutes."""
    from app.api.routes import reset_demo

    def once():
        with SessionLocal() as db:
            reset_demo(db, settings.demo_reset_with_captures)
            logbus.log("T0", "SYSTEM", "demo_auto_reset", db, minutes=settings.demo_auto_reset_minutes)
            db.commit()

    while True:
        await asyncio.sleep(settings.demo_auto_reset_minutes * 60)
        try:
            await asyncio.to_thread(once)
        except Exception as exc:  # keep the loop alive; the crash handler only sees requests
            mailer.alert("auto_reset", "[LaMP] Demo auto-reset failed", f"{type(exc).__name__} at {_now()}.")


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


app = FastAPI(title="LaMP-Copilot API", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
problems.install(app)  # errors with a machine code for the app (plan 2.1)
app.include_router(router, prefix=API_PREFIX)


def _log_system_error(route: str, error: str, at: str, rid: str) -> None:
    gen = app.dependency_overrides.get(get_db, get_db)()  # the same database the routes use
    try:
        db = next(gen)
        logbus.log("T0", "SYSTEM", "system_error", db, route=route, error=error, at=at, request_id=rid)
        db.commit()
    except Exception:
        pass
    finally:
        gen.close()


@app.exception_handler(Exception)
async def crash_alert(request: Request, exc: Exception):
    """Any unhandled error: a plain 500 with a request id, a system_error log event, and an
    email to the admin (engines/mailer.py). No request data goes into the log or the email."""
    rid = uuid.uuid4().hex[:12]
    where = f"{request.method} {request.url.path}"
    frame = traceback.extract_tb(exc.__traceback__)[-1] if exc.__traceback__ else None
    at = f"{Path(frame.filename).name}:{frame.lineno} in {frame.name}" if frame else "unknown"
    # Email first; the log line goes on a background thread, since the database may be what failed.
    threading.Thread(target=_log_system_error, args=(where, type(exc).__name__, at, rid), daemon=True).start()
    mailer.alert(f"500 {where} {type(exc).__name__}", f"[LaMP] Server error on {where}",
                 f"The API hit an unexpected error and returned 500.\n\nRoute: {where}\nError: {type(exc).__name__}\n"
                 f"Where: {at}\nTime: {_now()}\nRequest id: {rid}\n\nThe same request id is in the audit log "
                 "(event system_error). Look at the backend logs and get back to it.")
    return JSONResponse({"detail": "Internal server error", "request_id": rid}, status_code=500)


# Pritom's chat router (POST /api/v1/chat), mounted once it exists.
try:
    app.include_router(importlib.import_module("app.agents.router").router, prefix=API_PREFIX)
except ImportError:
    pass


# Arifin's modules (build plan 1.2, task I0.5). Each package mounts once it exists:
#   app.<name>.routes.api_router   mounted under /api/v1 (sign-in, /demo/ussd, the tick endpoint)
#   app.<name>.routes.root_router  mounted at the root (Applink's callbacks: /applink/{app}/{secret}/...)
# A package that is missing, or has no routes module yet, is skipped, so main.py never needs editing.
PLUGGED_IN = ("auth", "applink", "jobs")


def _mount_plugged_in() -> list[str]:
    mounted = []
    for name in PLUGGED_IN:
        try:
            mod = importlib.import_module(f"app.{name}.routes")
        except ModuleNotFoundError as exc:
            if exc.name not in (f"app.{name}", f"app.{name}.routes"):
                raise  # the module exists but imports something missing: a real error
            continue
        if (api := getattr(mod, "api_router", None)) is not None:
            app.include_router(api, prefix=API_PREFIX)
            mounted.append(f"{name}:api")
        if (root := getattr(mod, "root_router", None)) is not None:
            app.include_router(root)
            mounted.append(f"{name}:root")
    return mounted


MOUNTED = _mount_plugged_in()


# Contract v1 (build plan 2.2): every Phase 1 route not built yet answers 501 not_built with
# its real shapes, so contracts/openapi.json is the whole contract. Mounted last.
def _served() -> set[tuple[str, str]]:
    spec = app.openapi()
    app.openapi_schema = None  # rebuilt with the contract routes below
    return {(method.upper(), path.removeprefix(API_PREFIX)) for path, ops in spec["paths"].items() for method in ops}


app.include_router(importlib.import_module("app.api.contract").build_router(_served()), prefix=API_PREFIX)
