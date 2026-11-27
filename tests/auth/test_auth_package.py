"""The sign-in package's router shape (build plan A0.4; routes come in A1.2)."""
from fastapi import APIRouter

from app.auth import routes


def test_sign_in_lives_under_api_v1_auth_only():
    assert isinstance(routes.api_router, APIRouter)
    assert routes.api_router.prefix == "/auth"
    assert not hasattr(routes, "root_router")
