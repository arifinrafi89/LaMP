"""The jobs router that main.py mounts under /api/v1 (build plan D6, 10; task A1.3).

POST /internal/jobs/tick is the backstop GitHub Actions calls every 15 minutes and at 07:59
Dhaka (tick.yml, A1.4), with the X-Tick-Secret header. It queues the day's due jobs and runs
what is due, as one pass of the loop would. A missing or wrong secret answers 404, so the
route can't be found by probing.
"""
import hmac

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy.orm import Session, sessionmaker

from app.db.session import get_db

from . import runner, scheduler
from .config import get_settings
from .registry import utcnow

api_router = APIRouter(prefix="/internal/jobs", tags=["jobs"], include_in_schema=False)


@api_router.post("/tick")
def tick(x_tick_secret: str | None = Header(default=None), db: Session = Depends(get_db)) -> dict:
    expected = get_settings().tick_secret()
    if not expected or not x_tick_secret or not hmac.compare_digest(x_tick_secret.encode(), expected.encode()):
        raise HTTPException(404, "Not Found")
    now = utcnow()
    queued = scheduler.tick(db, now)
    db.commit()
    # Not a heartbeat: /ready reports whether the loop itself is alive.
    ran = runner.run_due(sessionmaker(bind=db.get_bind(), expire_on_commit=False), now)
    return {"queued": queued, "ran": ran}
