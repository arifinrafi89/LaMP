"""The jobs router that main.py mounts under /api/v1 (build plan I0.5).

The secret tick endpoint, POST /internal/jobs/tick, is added here in A1.3.
"""
from fastapi import APIRouter

api_router = APIRouter(prefix="/internal/jobs", tags=["jobs"], include_in_schema=False)
