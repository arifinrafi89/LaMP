"""POST /api/v1/chat: the copilot chat, streamed with the Vercel AI SDK UI message
protocol so the frontend's useChat reads it directly. main.py mounts this router."""

import json

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response
from pydantic_ai.ui.vercel_ai import VercelAIAdapter
from sqlalchemy.orm import Session

from app import engines
from app.api.deps import Caller, not_found, require_any_owner
from app.db.session import get_db

from . import chat
from .tools import ChatDeps

router = APIRouter()


@router.post("/chat")
async def chat_endpoint(request: Request, db: Session = Depends(get_db),
                        caller: Caller = Depends(require_any_owner)) -> Response:
    """Body: the AI SDK's chat request, plus `lang` ("en" by default, or "bn" for answers in
    Bangla). The shop comes from the session (plan 2.2), never the body: a `pharmacy_id` in
    the body that isn't the caller's own answers 404. No session: 401."""
    body = json.loads(await request.body() or b"{}")
    pid = caller.pharmacy_id
    lang = "bn" if body.get("lang") == "bn" else "en"
    if pid is None or body.get("pharmacy_id") not in (None, pid):
        raise not_found()
    engines.get_pharmacy(db, pid)  # 404 for a shop that's gone
    model = chat.model_for_mode()
    engines.log("T1", "CHAT", "chat_message", db, pharmacy=pid, mode=model.model_name.split(":")[0]
                if ":" in model.model_name else "live", prompt_version=chat.PROMPT_VERSION, lang=lang)
    db.commit()

    adapter = await VercelAIAdapter.from_request(request, agent=chat.agent, sdk_version=7)
    events = adapter.run_stream(model=model, deps=ChatDeps(db=db, pharmacy_id=pid),
                                usage_limits=chat.USAGE_LIMITS,
                                instructions=chat.BANGLA if lang == "bn" else None)
    # Every money figure in the answer must trace to this turn's tool outputs before it is shown.
    return adapter.streaming_response(chat.guard_stream(events, db, lang))
