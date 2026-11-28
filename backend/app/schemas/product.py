"""Contract v1 for the AppQuest product (build plan section 2, tasks I0.4 and I1.3).

Request and response shapes for every Phase 1 screen that LaMP.ai didn't have. Field names
are binding: the Flutter app (mobile/) and the server both follow them. Money is BDT with
2 decimals, dates are YYYY-MM-DD in Asia/Dhaka, timestamps carry an offset (plan 2.1).
Amounts only on customer cards: no names, no medicines.
"""

from typing import Literal

from pydantic import Field

from .cash import Alert
from .common import ISODate, Model, Timestamp
from .patients import PatientPlan

Lang = Literal["en", "bn"]
Plan = Literal["free", "plus"]
PlusStatus = Literal["NONE", "OTP_SENT", "PENDING", "ACTIVE", "BLOCKED", "STOPPED"]
JoinRoute = Literal["text", "counter"]  # how a family can join SMS (plan 3.4, FAMILY_JOIN_ROUTES)
SmsStatus = Literal["NONE", "PENDING", "ON", "STOPPED", "FAILED"]
PayMethod = Literal["cash", "bkash", "nagad", "other"]

# Machine codes the app turns into its own English or Bangla text (plan 2.1).
ErrorCode = Literal[
    "otp_wrong", "otp_expired", "otp_too_many", "not_banglalink", "session_expired", "plus_required",
    "scan_limit_reached", "ai_budget_reached", "update_required", "rate_limited", "applink_down",
    "charge_failed", "join_by_text", "not_found", "invalid", "not_built",
]


class Problem(Model):
    """Every error: FastAPI's `detail` in plain English, plus a code for the app."""

    detail: str
    code: ErrorCode
    retry_after: int | None = None  # seconds, for rate_limited and otp_too_many
    resets_on: ISODate | None = None  # for scan_limit_reached


# Sign-in and account (the /auth routes are Arifin's; their shapes live here so the contract is one file)

class OtpRequestIn(Model):
    phone: str = Field(examples=["+8801912345678"])  # normalised to tel:8801… on the server
    language: Lang = "en"


class OtpChallengeOut(Model):
    challenge_id: str
    expires_in: int = 300
    resend_after: int = 30


class DeviceIn(Model):
    id: str
    name: str
    os: str
    app_version: str


class OtpVerifyIn(Model):
    challenge_id: str
    code: str
    device: DeviceIn


class OwnerOut(Model):
    id: str
    phone_masked: str = Field(examples=["+880 19•• ••• 678"])
    language: Lang


class PharmacyBrief(Model):
    id: str
    name: str
    setup_complete: bool


class SignedInOut(Model):
    access_token: str
    expires_at: Timestamp
    refresh_token: str | None = None  # Android only; web gets an httpOnly cookie
    owner: OwnerOut
    pharmacy: PharmacyBrief | None
    is_new: bool


class RefreshIn(Model):
    refresh_token: str | None = None  # or the cookie on web


class TokenPairOut(Model):
    access_token: str
    expires_at: Timestamp
    refresh_token: str | None = None


class DeviceOut(Model):
    id: str
    name: str
    os: str
    last_used_at: Timestamp
    this_device: bool


class DemoSignInIn(Model):
    demo_code: str


class Entitlements(Model):
    cash: bool
    plan: bool
    approvals: bool
    ask: bool
    scans_left: int | None  # None: no monthly limit (Plus)


class MeOut(Model):
    owner: OwnerOut
    pharmacy: PharmacyBrief | None
    plan: Plan
    plus_status: PlusStatus
    entitlements: Entitlements
    demo_tools: bool  # demo and team-test shops only
    family_join_routes: list[JoinRoute] = Field(examples=[["text"]])  # "counter" only while masking is off
    consents_needed: list[Literal["terms", "privacy"]]


class MePatch(Model):
    language: Lang


class LegalOut(Model):
    terms_version: str
    privacy_version: str
    terms_url: str
    privacy_url: str


class ConsentsIn(Model):
    terms_version: str
    privacy_version: str


class ExportStarted(Model):
    export_id: str


class ExportOut(Model):
    status: Literal["building", "ready", "failed"]
    download_url: str | None = None  # valid for 10 minutes


class DeleteIn(Model):
    confirm: Literal["DELETE"]


class DeleteOut(Model):
    erase_on: ISODate  # after the 7-day undo window


# Shop setup (first day)

class PharmacyCreate(Model):
    name: str = Field(min_length=1, max_length=80)
    city: str = Field(min_length=1, max_length=40)
    area: str | None = Field(default=None, max_length=60)


class PharmacyPatch(Model):
    name: str | None = None
    city: str | None = None
    gross_margin_pct: float | None = Field(default=None, ge=0, le=60)
    cash_buffer: float | None = Field(default=None, ge=0)


class SupplierIn(Model):
    name: str = Field(min_length=1, max_length=80)
    phone: str | None = None  # a business contact, only for the share-to-supplier draft
    payment_days: int = Field(default=30, ge=0, le=180)
    return_cutoff_days: int = Field(default=30, ge=0, le=365)


class SupplierOut(SupplierIn):
    id: int


class OpeningIn(Model):
    cash_on_hand: float = Field(ge=0)
    as_of: ISODate


class StockBatchIn(Model):
    product: str
    strength: str | None = None
    batch_no: str
    expiry_date: ISODate
    qty: int = Field(gt=0)
    unit_cost: float = Field(ge=0)
    supplier_id: int


class ExpenseIn(Model):
    category: str
    amount: float = Field(ge=0)
    day_of_month: int = Field(ge=1, le=28)


class Saved(Model):
    """What a setup step answers: how many rows it saved."""

    saved: int


# Today (one call, made for slow networks)

class NextProblem(Model):
    kind: Literal["shortfall"]
    date: ISODate
    amount: float
    text_key: str = Field(examples=["today.short_on"])


class Expiring(Model):
    value: float
    return_eligible: float


class OneThing(Model):
    kind: Literal["approve", "scan", "setup", "remind", "none"]
    action_id: str | None = None
    title_key: str = Field(examples=["today.one_thing.approve"])


class TodayOut(Model):
    as_of: ISODate
    cash_now: float
    next_problem: NextProblem | None
    expiring_60d: Expiring
    approvals_waiting: int
    one_thing: OneThing
    alerts: list[Alert]


# Money recorded by hand (these replace the simulated wallet)

class PaymentIn(Model):
    invoice_id: int
    amount: float = Field(gt=0)
    paid_on: ISODate
    method: PayMethod = "cash"


class SalesDayIn(Model):
    date: ISODate
    cash_sales: float = Field(ge=0)
    credit_sales: float = Field(ge=0)
    dues_collected: float = Field(ge=0)
    expenses: float = Field(ge=0)


class UsageOut(Model):
    plan: Plan
    scans_used: int
    scans_limit: int | None  # None on Plus
    ai_used_bdt: float
    ai_budget_bdt: float
    resets_on: ISODate


# Customers (free) — amounts only, never names or medicines

class JoinText(Model):
    """What a family texts to join SMS (plan 3.4): shown in the app, read out, written on the bill."""

    text: str = Field(examples=["LAMP GL7KQM4XPA"])
    to: str = Field(examples=["21213"])


class CustomerRow(Model):
    code: str = Field(examples=["GL-7KQM-4XPA"])
    label: str = Field(examples=["Customer 003"])
    amount: float
    since: ISODate
    days_outstanding: int
    status: Literal["planned", "no_plan"]
    plan: PatientPlan | None
    sms_status: SmsStatus
    join: JoinText
    trusted: bool  # every part so far paid on time


class CustomerCreate(Model):
    amount: float = Field(ge=0)
    since: ISODate


class CustomerCreated(Model):
    code: str
    label: str
    join: JoinText


class CustomerMoneyIn(Model):
    amount: float = Field(gt=0)
    on: ISODate
    method: PayMethod | None = None  # payments only


class CustomerBalance(Model):
    code: str
    amount: float  # what the customer owes now


class CustomerPlanIn(Model):
    parts: Literal[1, 2, 4]
    first_on: ISODate


class FamilyConsentIn(Model):
    agreed: Literal[True]
    wording_version: str


class CustomerPhoneIn(Model):
    phone: str
    language: Lang = "bn"
    consent: FamilyConsentIn


class SmsStatusOut(Model):
    sms_status: SmsStatus


# Credit record (CaaS BDT 10) and LaMP Plus (Subscription BDT 50 a month)

ChargeStatus = Literal["OTP_SENT", "VERIFYING", "PAID", "FAILED", "EXPIRED", "UNKNOWN"]


class CreditShareOut(Model):
    id: str
    lender_name: str
    url: str
    expires_at: Timestamp
    views: int


class CreditRecordOut(Model):
    bills_total: int
    paid_on_time: int
    months: int
    purchased: bool
    shares: list[CreditShareOut]


class ChargeOut(Model):
    charge_id: str
    status: ChargeStatus
    amount: float = 10.00
    attempts_left: int | None = None
    reason: str | None = None  # when FAILED


class ChargeOtpIn(Model):
    otp: str


class ShareIn(Model):
    lender_name: str = Field(min_length=1, max_length=80)
    expires_in_days: int = Field(default=7, ge=1, le=30)


class PlusConsentIn(Model):
    price_text: str = Field(examples=["BDT 50 a month + VAT"])
    wording_version: str


class PlusSubscribeIn(Model):
    consent: PlusConsentIn


class PlusOtpIn(Model):
    """The code Banglalink texted for the Plus app (plan 3.3)."""

    otp: str = Field(min_length=4, max_length=8)


class PlusOut(Model):
    status: PlusStatus
    renews_on: ISODate | None = None


# Support, versions

class AppConfigOut(Model):
    min_version: str
    latest_version: str
    play_url: str
    maintenance: bool
    flags: dict[str, bool]


class SupportReportIn(Model):
    category: Literal["bug", "question", "idea", "other"]
    message: str = Field(min_length=1, max_length=2000)
    screen: str | None = None
    app_version: str | None = None


class SupportReportOut(Model):
    report_id: str


class TelemetryEvent(Model):
    name: str
    screen: str | None = None
    at: Timestamp


class TelemetryIn(Model):
    events: list[TelemetryEvent] = Field(max_length=100)


# The demo shop's drawn phone (plan 5.7): texts to 21213 run the real SMS command code (3.5)

class DemoSmsIn(Model):
    text: str = Field(min_length=1, max_length=160, examples=["LAMP GL7KQM4XPA"])


class DemoReply(Model):
    text: str


class DemoSmsOut(Model):
    replies: list[DemoReply]  # what LaMP texted back, in order (often one, sometimes none)


class DemoMessage(Model):
    direction: Literal["in", "out"]  # in: the phone texted 21213 · out: LaMP texted the phone
    text: str
    at: Timestamp


class DemoThreadOut(Model):
    messages: list[DemoMessage]  # oldest first, including what the owner's actions sent
