"""Which Applink client a call gets (build plan 1.2, 3.9, D12).

Demo shops always get the mock, even in production, so judges never trigger real SMS
or charges. Everyone else gets the client APPLINK_MODE names. The HTTP client (and
httpx) is imported only in sandbox and live mode.
"""
from functools import lru_cache

from app.applink.client.base import ApplinkClient
from app.applink.client.mock import MockClient
from app.applink.config import get_settings

DEMO_KINDS = frozenset({"demo"})


def client_for(pharmacy_kind: str | None = None) -> ApplinkClient:
    if pharmacy_kind in DEMO_KINDS or get_settings().mode == "mock":
        return _mock()
    return _http()


@lru_cache
def _mock() -> MockClient:
    return MockClient(get_settings())


@lru_cache
def _http() -> ApplinkClient:
    from app.applink.client.http import HttpClient  # needs httpx; only sandbox and live use it

    return HttpClient(get_settings())


def reset() -> None:
    """Forget the cached clients and settings (tests, or after the environment changes)."""
    _mock.cache_clear()
    _http.cache_clear()
    get_settings.cache_clear()
