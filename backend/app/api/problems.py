"""Errors with a machine code for the app (build plan 2.1).

Every error the app is meant to explain answers `{"detail": "plain English", "code": "otp_wrong",
"retry_after": 30}`. The app shows its own English or Bangla words for each `code` and falls
back to `detail`. Raise `ApiProblem` anywhere (a route, a dependency); `install(app)` turns it
into that answer. FastAPI's own errors keep their shape, plus `code` where one fits.
"""
from datetime import date

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class ApiProblem(Exception):
    def __init__(self, status: int, code: str, detail: str, *, retry_after: int | None = None,
                 resets_on: date | None = None, headers: dict[str, str] | None = None):
        super().__init__(detail)
        self.status, self.code, self.detail = status, code, detail
        self.retry_after, self.resets_on = retry_after, resets_on
        self.headers = dict(headers or {})
        if retry_after is not None:
            self.headers.setdefault("Retry-After", str(retry_after))

    def body(self) -> dict:
        out: dict = {"detail": self.detail, "code": self.code}
        if self.retry_after is not None:
            out["retry_after"] = self.retry_after
        if self.resets_on is not None:
            out["resets_on"] = self.resets_on.isoformat()
        return out


def response(p: ApiProblem) -> JSONResponse:
    return JSONResponse(p.body(), status_code=p.status, headers=p.headers)


_HTTP_CODES = {401: "session_expired", 404: "not_found", 422: "invalid", 429: "rate_limited"}


async def _problem(_: Request, exc: ApiProblem) -> JSONResponse:
    return response(exc)


async def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    body: dict = {"detail": exc.detail}
    if exc.status_code in _HTTP_CODES:
        body["code"] = _HTTP_CODES[exc.status_code]
    return JSONResponse(body, status_code=exc.status_code, headers=getattr(exc, "headers", None))


async def _invalid(_: Request, exc: RequestValidationError) -> JSONResponse:
    # The FastAPI list of errors stays under detail (the copied tests read it), plus the code.
    return JSONResponse({"detail": jsonable_encoder(exc.errors()), "code": "invalid"}, status_code=422)


def install(app: FastAPI) -> None:
    app.add_exception_handler(ApiProblem, _problem)
    app.add_exception_handler(StarletteHTTPException, _http)
    app.add_exception_handler(RequestValidationError, _invalid)
