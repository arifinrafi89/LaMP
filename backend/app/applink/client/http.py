"""The real Applink client, used in sandbox and live mode (build plan 3, 3.9).

Retries, and only where a retry can't cause harm:
- a connection that never reached Applink is retried (up to 3 attempts) for every call;
- a transient statusCode (plan 3.8) is retried with backoff and jitter, up to 3 attempts,
  except E1319 (the day's limit is spent), /otp/request (one retry, plan 3.2) and the
  charging path, which is never retried;
- a timeout after the request was sent is never retried: the reply comes back with
  timed_out=True, and the caller settles it (for CaaS, only the charging notification does).

TLS is always verified.
"""
import json
import random
import time
from collections.abc import Callable
from typing import Any

import httpx

from app.applink import codes
from app.applink.client.base import CHARGING_PATHS, ApplinkClient, Reply
from app.applink.config import AppName, ApplinkSettings

MAX_ATTEMPTS = 3
OTP_REQUEST_ATTEMPTS = 2


class HttpClient(ApplinkClient):
    def __init__(self, settings: ApplinkSettings, *, transport: httpx.BaseTransport | None = None,
                 sleep: Callable[[float], None] = time.sleep):
        super().__init__(settings)
        self.mode = settings.mode
        self._sleep = sleep
        self._http = httpx.Client(base_url=settings.base_url, timeout=settings.timeout_s, transport=transport,
                                  headers={"Content-Type": "application/json;charset=utf-8"})

    def close(self) -> None:
        self._http.close()

    def _post(self, app: AppName, path: str, body: dict[str, Any]) -> Reply:
        attempts = 1 if path in CHARGING_PATHS else OTP_REQUEST_ATTEMPTS if path == "/otp/request" else MAX_ATTEMPTS
        reply: Reply | None = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            started = time.monotonic()
            try:
                res = self._http.post(path, content=json.dumps(body))
            except (httpx.ConnectError, httpx.ConnectTimeout):
                # Never reached Applink: safe to try again, even on the charging path.
                if attempt < MAX_ATTEMPTS:
                    self._backoff(attempt)
                    continue
                return Reply(path, None, "could not connect to Applink", timed_out=True, ms=_ms(started))
            except httpx.TransportError:
                # Sent, but no answer: the outcome is unknown, so it is never sent again.
                return Reply(path, None, "no answer from Applink", timed_out=True, ms=_ms(started))
            reply = _parse(path, res, _ms(started))
            if attempt < attempts and codes.is_retryable(reply.status_code):
                self._backoff(attempt)
                continue
            return reply
        return reply  # pragma: no cover  (the loop always returns)

    def _backoff(self, attempt: int) -> None:
        self._sleep(0.5 * 2 ** (attempt - 1) + random.uniform(0, 0.25))


def _parse(path: str, res: httpx.Response, ms: int) -> Reply:
    try:
        data = res.json()
    except ValueError:
        data = {}
    if not isinstance(data, dict):
        data = {}
    data.pop("password", None)
    code = data.get("statusCode")
    if code is None:
        # Not an Applink answer at all (a proxy page, an empty body): treat as unknown.
        return Reply(path, None, f"HTTP {res.status_code} without a statusCode", data=data, ms=ms)
    return Reply(path, str(code), str(data.get("statusDetail", "")), data=data, ms=ms)


def _ms(started: float) -> int:
    return int((time.monotonic() - started) * 1000)
