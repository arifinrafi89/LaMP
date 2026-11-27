"""The sign-in router that main.py mounts under /api/v1 (build plan I0.5).

/auth/otp/request, /auth/otp/verify, /auth/refresh, /auth/sign-out,
/auth/devices and /auth/demo (plan 2.2) are added here in A1.2.
"""
from fastapi import APIRouter

api_router = APIRouter(prefix="/auth", tags=["auth"])
