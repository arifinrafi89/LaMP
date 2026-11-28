"""Contract v1: every Phase 1 route that isn't built yet (build plan 2.2, I0.4 and I1.3).

Each route here has its real request and response shapes, so contracts/openapi.json is the
whole Phase 1 contract from today and Ayon can run a mock of it:
    npx @stoplight/prism-cli mock contracts/openapi.json

Until a route is built it answers 501 with code `not_built`. Building a route means writing
it in its own module and deleting its line here; a test fails if both exist.

Lines marked "A" (sign-in, /legal, /me/consents, /plus/otp, /demo) are served by the auth and
applink packages; each stub steps aside on its own once a real route is mounted.
"""

import inspect
import re
from typing import Any

from fastapi import APIRouter, Body, Path
from fastapi.responses import JSONResponse

from app.schemas.patients import PatientCardOut
from app.schemas.product import (
    AppConfigOut, ChargeOtpIn, ChargeOut, ConsentsIn, CreditRecordOut, CreditShareOut, CustomerBalance,
    CustomerCreate, CustomerCreated, CustomerMoneyIn, CustomerPhoneIn, CustomerPlanIn, DeleteIn, DeleteOut,
    DemoSignInIn, DemoSmsIn, DemoSmsOut, DemoThreadOut, DeviceOut, ExpenseIn, ExportOut, ExportStarted, LegalOut,
    OpeningIn, OtpChallengeOut, OtpRequestIn, OtpVerifyIn, PaymentIn,
    PlusOtpIn, PlusOut, PlusSubscribeIn, Problem, RefreshIn, SalesDayIn, Saved, ShareIn, SignedInOut, SmsStatusOut,
    StockBatchIn, SupplierIn, SupplierOut, SupportReportIn, SupportReportOut, TelemetryIn, TodayOut, TokenPairOut,
    UsageOut,
)

P = "/pharmacies/{pid}"

# (method, path, request body, response model, success status, owner)
#   owner: "I" core routes or "A" the auth and applink packages (sign-in, legal, demo). A test checks that
#   a built "I" route has lost its line here; an "A" stub steps aside on its own.
ROUTES: list[tuple[str, str, Any, Any, int, str]] = [
    # Sign-in and account
    ("POST", "/auth/otp/request", OtpRequestIn, OtpChallengeOut, 202, "A"),
    ("POST", "/auth/otp/verify", OtpVerifyIn, SignedInOut, 200, "A"),
    ("POST", "/auth/refresh", RefreshIn, TokenPairOut, 200, "A"),
    ("POST", "/auth/sign-out", None, None, 204, "A"),
    ("GET", "/auth/devices", None, list[DeviceOut], 200, "A"),
    ("DELETE", "/auth/devices/{device_id}", None, None, 204, "A"),
    ("POST", "/auth/demo", DemoSignInIn, SignedInOut, 200, "A"),
    ("GET", "/legal/current", None, LegalOut, 200, "A"),
    ("POST", "/me/consents", ConsentsIn, None, 204, "A"),
    ("POST", "/me/export", None, ExportStarted, 202, "I"),
    ("GET", "/me/export/{export_id}", None, ExportOut, 200, "I"),
    ("POST", "/me/delete", DeleteIn, DeleteOut, 202, "I"),
    # Shop setup
    ("GET", f"{P}/suppliers", None, list[SupplierOut], 200, "I"),
    ("POST", f"{P}/suppliers", SupplierIn, SupplierOut, 201, "I"),
    ("PATCH", f"{P}/suppliers/{{sid}}", SupplierIn, SupplierOut, 200, "I"),
    ("DELETE", f"{P}/suppliers/{{sid}}", None, None, 204, "I"),
    ("POST", f"{P}/opening", OpeningIn, Saved, 200, "I"),
    ("POST", f"{P}/stock-batches", list[StockBatchIn], Saved, 201, "I"),
    ("POST", f"{P}/expenses", list[ExpenseIn], Saved, 201, "I"),
    # Daily screens
    ("GET", f"{P}/today", None, TodayOut, 200, "I"),
    ("POST", f"{P}/payments", PaymentIn, Saved, 201, "I"),
    ("POST", f"{P}/sales-days", SalesDayIn, Saved, 201, "I"),
    ("GET", f"{P}/usage", None, UsageOut, 200, "I"),
    # Customers
    ("POST", f"{P}/customers", CustomerCreate, CustomerCreated, 201, "I"),
    ("POST", f"{P}/customers/{{code}}/sales", CustomerMoneyIn, CustomerBalance, 201, "I"),
    ("POST", f"{P}/customers/{{code}}/payments", CustomerMoneyIn, CustomerBalance, 201, "I"),
    ("PUT", f"{P}/customers/{{code}}/plan", CustomerPlanIn, PatientCardOut, 200, "I"),
    ("POST", f"{P}/customers/{{code}}/phone", CustomerPhoneIn, SmsStatusOut, 202, "I"),
    ("DELETE", f"{P}/customers/{{code}}/phone", None, SmsStatusOut, 200, "I"),
    ("POST", f"{P}/customers/{{code}}/remind", None, SmsStatusOut, 202, "I"),
    # Credit record and LaMP Plus
    ("GET", f"{P}/credit-record", None, CreditRecordOut, 200, "I"),
    ("POST", f"{P}/credit-record/purchases", None, ChargeOut, 201, "I"),
    ("POST", f"{P}/credit-record/purchases/{{charge_id}}/otp", ChargeOtpIn, ChargeOut, 200, "I"),
    ("GET", f"{P}/credit-record/purchases/{{charge_id}}", None, ChargeOut, 200, "I"),
    ("GET", f"{P}/credit-record/pdf", None, None, 200, "I"),
    ("POST", f"{P}/credit-record/shares", ShareIn, CreditShareOut, 201, "I"),
    ("DELETE", f"{P}/credit-record/shares/{{share_id}}", None, None, 204, "I"),
    ("GET", f"{P}/plus", None, PlusOut, 200, "I"),
    ("POST", f"{P}/plus/subscribe", PlusSubscribeIn, PlusOut, 202, "I"),
    ("POST", f"{P}/plus/otp", PlusOtpIn, PlusOut, 200, "I"),
    ("POST", f"{P}/plus/cancel", None, PlusOut, 200, "I"),
    # Support and versions
    ("GET", "/app/config", None, AppConfigOut, 200, "I"),
    ("POST", "/support/reports", SupportReportIn, SupportReportOut, 201, "I"),
    ("POST", "/telemetry/events", TelemetryIn, None, 204, "I"),
    # The demo shop's drawn phone (demo and team-test shops only)
    ("POST", "/demo/sms", DemoSmsIn, DemoSmsOut, 200, "A"),
    ("GET", "/demo/sms/thread", None, DemoThreadOut, 200, "A"),
    ("POST", "/demo/reset", None, None, 204, "A"),
]

_ERRORS = {code: {"model": Problem} for code in (401, 403, 404, 422, 429, 501)}


def _stub(method: str, path: str, body: Any) -> Any:
    """An endpoint with the route's path parameters and body, answering 501 not_built."""
    params = [inspect.Parameter(name, inspect.Parameter.KEYWORD_ONLY, annotation=str, default=Path())
              for name in re.findall(r"{(\w+)}", path)]
    if body is not None:
        params.append(inspect.Parameter("body", inspect.Parameter.KEYWORD_ONLY, annotation=body, default=Body()))

    def endpoint(**_: Any) -> JSONResponse:
        return JSONResponse({"detail": f"{method} {path} isn't built yet.", "code": "not_built"}, status_code=501)

    endpoint.__signature__ = inspect.Signature(params)  # type: ignore[attr-defined]
    endpoint.__name__ = "contract_" + re.sub(r"\W+", "_", f"{method} {path}").strip("_").lower()
    return endpoint


def build_router(taken: set[tuple[str, str]]) -> APIRouter:
    """The not-yet-built routes, minus any that a real router already serves."""
    router = APIRouter(tags=["contract v1: not built yet"])
    for method, path, body, response, status, _owner in ROUTES:
        if (method, path) in taken:
            continue
        router.add_api_route(path, _stub(method, path, body), methods=[method], status_code=status,
                             response_model=response, responses=_ERRORS)
    return router
