"""The Applink routers that main.py mounts (build plan I0.5).

api_router   mounted under /api/v1: the demo phone, /demo/sms (A2.3)
root_router  mounted at the root: Applink's callbacks,
             /applink/{app}/{secret}/... (A2.1). They are not part of the app's
             contract, so they stay out of the OpenAPI schema.
"""
from fastapi import APIRouter

api_router = APIRouter(tags=["applink"])
root_router = APIRouter(include_in_schema=False)
