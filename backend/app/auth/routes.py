"""The routers that main.py mounts under /api/v1 (build plan I0.5).

api_router carries two groups:
  /auth/...   sign-in: otp/request, otp/verify, refresh, sign-out, devices, demo (A1.2)
  /legal/...  the terms and privacy policy and their versions (G3, 13.3)
Sign-in routes are added to auth_router before it is included below.
"""
from fastapi import APIRouter

from app.auth.legal import router as legal_router

auth_router = APIRouter(prefix="/auth", tags=["auth"])

api_router = APIRouter()
api_router.include_router(auth_router)
api_router.include_router(legal_router)
