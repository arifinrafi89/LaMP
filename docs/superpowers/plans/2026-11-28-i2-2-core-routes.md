# I2.2 Core routes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve, for real, the server routes the Flutter app already calls for first-day setup, the Today screen and customers. Today these answer 501 `not_built`.

**Architecture:** Each group of routes gets its own module under `backend/app/api/`. Money logic stays in `app/engines/`. Routes under `/pharmacies/{pid}/*` hang off the `owner` router in `api/routes.py`, so they inherit `require_owner` (404 for another shop). `/me` and `POST /pharmacies` sit on a session router that uses `signed_in_owner`. Each built route loses its "I" line in `api/contract.py`.

**Tech Stack:** FastAPI, SQLAlchemy 2.0, Alembic (`core` branch), pydantic v2, pytest (SQLite in memory).

**Spec:** `docs/LaMP-Build-Plan.md` 2.1 (rules), 2.2 (route table), 4.2 (tables); the shapes in `backend/app/schemas/product.py`; `docs/PROGRESS.md`, flow step 4 notes.

**Delivery:** three PRs, one per part, each on its own branch from `main`:
- `ayon/I2.2-core-routes`: Part 1
- `ayon/I2.2-setup-today`: Part 2
- `ayon/I2.2-customers`: Part 3

The I2.2 tick in PROGRESS.md goes in Part 3's PR. Parts 1 and 2 update "Where to pick up".

## Global Constraints

- Errors use `raise ApiProblem(status, code, detail)` (`app/api/problems.py`). A wrong value is 400 or 422, never 401: the app treats 401 as "refresh and retry".
- Another shop's id, or another shop's child id (supplier, invoice, card code), answers **404 `not_found`**, never 403.
- Money is BDT, rounded with `engines.common.r2`. Dates come from `engines.common.as_of(ph)`, never `date.today()`.
- Customer cards hold amounts only: no name field, no medicine. Card code `XX-XXXX-XXXX`; join text `LAMP <code without dashes>` to `ApplinkSettings.sms_shortcode` (`21213`).
- Routes ignore `Idempotency-Key` for now. I2.3 adds it.
- Every engine write that matters logs with `logbus.log(tier, component, event, db, pharmacy=pid, ...)`.
- Run the whole suite before each PR: `cd backend && pytest -q`. For app changes, also run `flutter analyze` and `flutter test` in `mobile/`.

## Review Focus

1. **A signed-in owner with no shop yet** calls `GET /me` (pharmacy `null`, `demo_tools` false) and `POST /pharmacies`. Calling `POST /pharmacies` a second time must not make a second shop: 409 `invalid`. Tested in Task 1.2.
2. **A deleted supplier** must not come back in `GET /suppliers`, and can't take new stock batches (422). Its old invoices still show in dues. Tested in Task 2.1.
3. **A supplier payment larger than what's still owed** on the invoice is refused with 422. A payment that clears the invoice marks it `paid`, so the forecast stops counting it. Tested in Task 2.3.
4. **Typing the same sales-book day twice** replaces that day (one row per date, as `upsert_sales_days` does for scanned pages). Tested in Task 2.3.
5. **A customer payment larger than the balance** is refused with 422. The balance never goes below 0. Tested in Task 3.2.

## File structure

| File | Responsibility |
|---|---|
| `app/api/me.py` (new) | `GET /me`, `PATCH /me`, `POST /pharmacies`: the session router |
| `app/api/shop.py` (new) | `PATCH /pharmacies/{pid}`, `POST /setup/complete`, `pharmacy_out(ph)` |
| `app/engines/shops.py` (new) | `create_shop`, `card_prefix`, `update_shop`, `complete_setup` |
| `app/api/setup.py` (new) | suppliers CRUD, opening, stock batches, expenses |
| `app/api/money.py` (new) | `POST /payments`, `POST /sales-days` |
| `app/engines/books.py` (new) | `record_payment`, `record_sales_day`, `set_opening` |
| `app/engines/today.py` (new) | `get_today(db, pid) -> TodayOut` |
| `app/api/customers.py` (new) | customers list, create, sales, payments, plan |
| `app/engines/patients.py` | + `new_card`, `record`, `rows_for_owner`, `join_text`; `set_plan(..., by=)` |
| `app/db/models.py` + `migrations/versions/core/0004_setup_columns.py` | supplier `phone`, `payment_days`, `deleted_at`; stock_batch `strength`; payment `method` |
| `migrations/versions/core/0005_plan_as_set.py` | patient_dues `plan_amount`, `plan_set_on` (for `trusted`) |
| `app/api/routes.py` | include the new routers; use `shop.pharmacy_out`; drop the old `GET /customers` |
| `app/api/contract.py` | delete each built "I" line |
| `tests/api/test_me_and_shop.py`, `test_setup_routes.py`, `test_money_routes.py`, `test_today.py`, `test_customer_routes.py` (new) | one file per part of the route table |
| `tests/api/test_contract.py` | the not-built examples move to routes that are still unbuilt |
| `mobile/lib/features/today/today_screen.dart` (+ ARB) | one-thing kinds as the contract names them (Task 2.4) |

---

## Part 1: account and shop (PR 1)

### Task 1.1: `GET /me` and `PATCH /me`

**Files:**
- Create: `app/api/me.py`
- Modify: `app/api/routes.py` (include `me.router` in `router`); `app/api/contract.py` (delete the `GET /me` and `PATCH /me` lines)
- Modify: `tests/api/test_contract.py` (the `GET /me` example becomes `POST /me/export`)
- Test: `tests/api/test_me_and_shop.py`

**Interfaces:**
- Consumes: `deps.signed_in_owner(request, db) -> CurrentOwner`; `signin.owner_out(owner)`; `sessions.pharmacy_brief(db, owner)`; `sessions.plan_of(db, owner)`; `consents.needed(db, owner_id)`; `applink.config.get_settings().join_routes`.
- Produces: `me.router: APIRouter`; `plus_status(db, owner) -> PlusStatus`; `entitlements(db, owner, plan) -> Entitlements`.

- [ ] **Step 1: Write the failing tests**

```python
def test_me_for_the_demo_shop(client):
    r = client.get("/api/v1/me")
    assert r.status_code == 200
    j = r.json()
    assert j["pharmacy"] == {"id": "green-life", "name": "Green Life Pharmacy", "setup_complete": True}
    assert j["plan"] == "free" and j["plus_status"] == "NONE"
    assert j["entitlements"] == {"cash": False, "plan": False, "approvals": False, "ask": False, "scans_left": 10}
    assert j["demo_tools"] is True and j["family_join_routes"] == ["text"]
    assert set(j["consents_needed"]) <= {"terms", "privacy"}

def test_me_on_plus(client, api_db):  # a Plus subscriber row with status REGISTERED for green-life's owner
    ...; j = client.get("/api/v1/me").json()
    assert j["plan"] == "plus" and j["plus_status"] == "ACTIVE"
    assert j["entitlements"]["ask"] is True and j["entitlements"]["scans_left"] is None

def test_patch_me_sets_the_language(client):
    assert client.patch("/api/v1/me", json={"language": "bn"}).json()["owner"]["language"] == "bn"

def test_me_needs_a_token(anon):
    assert anon.get("/api/v1/me").status_code == 401
```

Check the shop's name against `seed/green_life.json`.

- [ ] **Step 2: Run them and see them fail:** `pytest tests/api/test_me_and_shop.py -q`. Expected: 501 `not_built`.
- [ ] **Step 3: Implement.**
  - `plus_status` maps the newest `Subscriber(app="plus")` status: none → `NONE`; `REGISTERED`, `TRIAL` → `ACTIVE`; `REG_PENDING`, `INITIAL` → `PENDING`; `TEMPORARY_BLOCKED` → `BLOCKED`; `UNREGISTERED` → `STOPPED`.
  - `entitlements`: `cash`, `plan`, `approvals` and `ask` = `plan == "plus"`. `scans_left` = `None` on Plus, else `max(0, 10 - this month's captures for the shop)`, or 10 with no shop. Put the 10 in `FREE_SCANS_PER_MONTH = 10` in `me.py`; I2.3 moves it.
  - `demo_tools` = the shop's kind is `demo` or `team_test`.
  - `family_join_routes` = `sorted(join_routes)`.
- [ ] **Step 4: Run the tests and see them pass.** Then run `pytest tests/api/test_contract.py tests/tenancy -q` and see it pass.
- [ ] **Step 5: Commit:** `api: GET and PATCH /me, the owner's plan, entitlements and join routes (I2.2, part 1)`

### Task 1.2: `POST /pharmacies`, `PATCH /pharmacies/{pid}`, `POST /pharmacies/{pid}/setup/complete`

**Files:**
- Create: `app/engines/shops.py`, `app/api/shop.py`
- Modify: `app/api/me.py` (`POST /pharmacies`); `app/api/routes.py` (`get_pharmacy` returns `shop.pharmacy_out(ph)`; `owner.include_router(shop.router)`); `app/api/contract.py` (delete 3 lines)
- Test: `tests/api/test_me_and_shop.py`

**Interfaces:**
- Produces:
  - `shops.create_shop(db, owner: Owner, name: str, city: str, area: str | None) -> Pharmacy`
  - `shops.card_prefix(name: str) -> str`
  - `shops.update_shop(db, ph, patch: PharmacyPatch) -> Pharmacy`
  - `shops.complete_setup(db, ph) -> Pharmacy`
  - `shop.pharmacy_out(ph) -> dict`: the PharmacyOut body, public settings only

- [ ] **Step 1: Write the failing tests**

```python
def test_a_new_owner_creates_a_shop(anon, api_db):   # sign in a new owner via the mock OTP (code 123456)
    r = anon.post("/api/v1/pharmacies", json={"name": "Shapla Pharmacy", "city": "Dhaka", "area": "Mirpur"}, headers=h)
    assert r.status_code == 201
    j = r.json()
    assert j["kind"] == "real" and j["setup_complete"] is False and j["card_prefix"] == "SP"
    assert j["settings"] == {"gross_margin_pct": 12, "cash_buffer": 0, "expiry_buffer_days": 30, "as_of_date": None}
    assert anon.get("/api/v1/me", headers=h).json()["pharmacy"]["id"] == j["id"]       # owner.pharmacy_id is set
    assert anon.get(f"/api/v1/pharmacies/{j['id']}", headers=h).status_code == 200     # the same token works at once

def test_a_second_shop_is_refused(...):   # same owner again → 409, code "invalid"
def test_card_prefix():
    assert shops.card_prefix("Green Life") == "GL"
    assert shops.card_prefix("Shapla") == "SH"
    assert len(shops.card_prefix("ঔষধালয়")) == 2   # no Latin letters: two random A–Z
def test_patch_shop(client):
    j = client.patch("/api/v1/pharmacies/green-life", json={"name": "Green Life 2", "gross_margin_pct": 15}).json()
    assert j["name"] == "Green Life 2" and j["settings"]["gross_margin_pct"] == 15
def test_setup_complete(...):   # new shop → POST setup/complete → setup_complete True, in /me too
```

- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.**
  - The id is `"ph-" + uuid4().hex[:12]`.
  - The settings are the defaults: 12% margin, 0 cash buffer, 30-day expiry buffer. `area` goes in `settings["area"]` (`pharmacy_out` leaves it out).
  - Set `kind="real"` and `created_at`, set `owner.pharmacy_id`, and log `T1 SETUP shop_created`.
  - `card_prefix`: the first letters of the first two Latin words; with one word, its first two letters; else two random `A`–`Z`.
- [ ] **Step 4: Run the whole suite and see it pass.** The tenancy class `session` already covers `^/api/v1/pharmacies$`.
- [ ] **Step 5: Commit:** `api: create a shop, rename it, finish setup (I2.2, part 1)`. Rewrite "Where to pick up", then open PR 1.

---

## Part 2: setup data, money by hand, Today (PR 2)

### Task 2.1: migration 0004 and suppliers CRUD

**Files:**
- Modify: `app/db/models.py`
  - `Supplier`: + `phone: str | None`, + `payment_days: int = 30` (with a server default), + `deleted_at: datetime | None`
  - `StockBatch`: + `strength: str | None`
  - `Payment`: + `method: str | None`
- Create: `migrations/versions/core/0004_setup_columns.py` (revises `0003`, with a working `downgrade`)
- Create: `app/api/setup.py` (`router`, included into `owner`)
- Modify: `app/api/contract.py` (delete the 4 supplier lines)
- Test: `tests/api/test_setup_routes.py`; `tests/migrations` must stay green (heads match models; down and up again)

**Interfaces:**
- Produces: `setup.shop_supplier(db, pid, sid) -> Supplier`, which is 404 when the supplier is another shop's or deleted. Used by stock batches.

- [ ] **Step 1: Write the failing tests:**
  - `test_add_list_edit_delete_supplier`: POST answers 201 with an `id`; GET lists it; PATCH changes `payment_days`; DELETE answers 204 and the supplier is gone from GET.
  - `test_another_shops_supplier_is_404`: PATCH and DELETE on a supplier id of shop B answer 404.
  - `test_a_deleted_supplier_keeps_its_invoices`: delete a seed supplier that has invoices, and `GET /dues` still counts them.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.** DELETE is soft (`deleted_at`), because invoices and batches point at the supplier.
- [ ] **Step 4: Run `pytest tests/api/test_setup_routes.py tests/migrations -q` and see it pass.**
- [ ] **Step 5: Commit:** `api: suppliers, with migration 0004 for the setup columns (I2.2, part 2)`

### Task 2.2: opening cash, stock batches, expenses

**Files:**
- Create: `app/engines/books.py` (`set_opening`)
- Modify: `app/api/setup.py`; `app/api/contract.py` (delete 3 lines)
- Test: `tests/api/test_setup_routes.py`

**Interfaces:**
- Produces: `books.set_opening(db, ph, cash: float, on: date) -> None`

- [ ] **Step 1: Write the failing tests:**
  - `test_opening_sets_cash`: `{cash_on_hand: 25000, as_of: <shop today>}` → `{"saved": 1}`, and `GET /forecast` has `start_cash == 25000`.
  - `test_opening_in_the_future_is_422`.
  - `test_stock_batches`: 2 lines → `{"saved": 2}`. `GET /expiry?horizon_days=400` lists both, and `strength` is stored. A line with a deleted or foreign `supplier_id` → 422 and nothing saved.
  - `test_expenses_are_added`: POST `[rent 8000 on day 5, salaries 12000 on day 1]` → `{"saved": 2}`, and the forecast lists both on their days. (Build plan 2.2 doesn't say to replace the schedule; repeats are the `Idempotency-Key`'s job, in I2.3.)
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.**
  - Opening: "the opening cash" (build plan 2.2). It sets `ph.cash_on_hand`, which the forecast reads as the cash at the start of the shop's today. `as_of` may not be after `as_of(ph)`.
  - Expenses: one `ExpenseSchedule` row per line.
  - Stock batches: check every line first, then insert, so the call saves all lines or none.
- [ ] **Step 4: Run the tests and see them pass.**
- [ ] **Step 5: Commit:** `api: opening cash, typed stock and monthly expenses (I2.2, part 2)`

### Task 2.3: supplier payments and sales days by hand

**Files:**
- Create: `app/api/money.py`
- Modify: `app/engines/books.py`; `app/api/contract.py` (delete 2 lines)
- Test: `tests/api/test_money_routes.py`

**Interfaces:**
- Produces:
  - `books.record_payment(db, ph, invoice_id: int, amount: float, paid_on: date, method: str) -> Payment`
  - `books.record_sales_day(db, ph, day: SalesDayIn) -> SalesDay`

**As written in build plan 2.2, and no more:** both routes record rows. A payment is a `Payment` on the invoice (with `method`), and the invoice turns `paid` once its payments cover the total. A sales day is one `SalesDay` row per date, replaced if typed again. Neither changes `cash_on_hand`. The build plan doesn't say how a real shop's cash moves after the opening, so that question goes to the team in PR 2's description, not into code.

- [ ] **Step 1: Write the failing tests:**
  - `test_payment_reduces_what_is_owed`: pay part of an unpaid seed invoice → 201 `{"saved": 1}`, and `/dues` drops by the amount.
  - `test_payment_that_clears_the_invoice_marks_it_paid`: the invoice leaves the forecast's items.
  - `test_overpayment_is_422`.
  - `test_foreign_invoice_is_404`.
  - `test_sales_day_twice_keeps_one_row`: post a day with cash_sales 5000, then the same date with 6000 → one row for that date, holding 6000.
  - `test_future_sales_day_is_422`.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement**, with logs `T1 BOOKS payment_recorded` and `T1 BOOKS sales_day_recorded`.
- [ ] **Step 4: Run the tests and see them pass.** Check the golden numbers too (`pytest tests/engines -q`): the seed path is unchanged.
- [ ] **Step 5: Commit:** `api: supplier payments and sales-book days typed by hand (I2.2, part 2)`

### Task 2.4: `GET /pharmacies/{pid}/today`, and the app's one-thing kinds

**Files:**
- Create: `app/engines/today.py`; add a `GET /today` route in `app/api/money.py`, or a small `app/api/today.py`
- Modify: `app/api/contract.py` (delete the line); `tests/api/test_contract.py` (the `/today` example becomes `GET /pharmacies/green-life/usage`)
- Modify: `mobile/lib/features/today/today_screen.dart` `_target`; ARB en and bn if `remind` needs a string
- Test: `tests/api/test_today.py`; `mobile/test/features/today_test.dart`

**Interfaces:**
- Consumes: `brief.daily_brief(db, pid, on)`, `get_expiry(db, pid, 60)`, `get_alerts(db, pid)`.
- Produces: `today.get_today(db, pid) -> TodayOut`.

**Fields:**
- `as_of` and `cash_now` come from `daily_brief`.
- `next_problem` is the first shortfall, as `{kind: "shortfall", date, amount, text_key: "today.short_on"}`, or `null`.
- `expiring_60d` = `{value: at_risk_value, return_eligible: return_eligible_value}`.
- `approvals_waiting` comes from `daily_brief`.
- `alerts` comes from `get_alerts`.
- `one_thing` is the first of these that applies, with `title_key` set to `"today.one_thing.<kind>"`:
  1. `setup`: setup isn't complete;
  2. `approve`: an action is waiting, with the oldest proposed `action_id`;
  3. `remind`: a customer's plan part is due today or overdue;
  4. `scan`: the shop has fewer than 3 invoices ("Scan your last 3 supplier bills", build plan 5.2, first day step 6);
  5. `none`.

- [ ] **Step 1: Write the failing tests:**
  - `test_today_for_the_demo_shop`: the shape matches `TodayOut`. `cash_now` equals `/forecast`'s `start_cash`, and `approvals_waiting` equals the number of proposed actions.
  - `test_today_for_a_new_shop_says_setup`: a new shop, not set up yet → `one_thing.kind == "setup"`, and `next_problem` is `null` with no data.
  - `test_today_one_thing_approve`: a proposed action → `kind == "approve"` with its `action_id`.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement `get_today` and the route.** In the app, map `scan` → `/scan`, `setup` → `/setup` and `remind` → `/customers`. Drop `return_stock`, `scan_bill` and `finish_setup`, which the contract never had.
- [ ] **Step 4: Run all the checks and see them pass:** `pytest -q`, then `flutter analyze` and `flutter test` in `mobile/`.
- [ ] **Step 5: Commit:** `api: GET /today, one call for the Today screen; mobile: one-thing kinds as the contract names them (I2.2, part 2)`. Open PR 2.

---

## Part 3: customers (PR 3)

### Task 3.1: `GET /customers` as `CustomerRow`, `POST /customers`

**Files:**
- Create: `app/api/customers.py` (`router`, included into `owner`)
- Modify: `app/engines/patients.py`; `app/api/routes.py` (remove the old `list_customers`); `app/api/contract.py` (delete the `POST /customers` line)
- Modify: `app/db/models.py` (`PatientDue`: + `plan_amount: float | None`, + `plan_set_on: date | None`); create `migrations/versions/core/0005_plan_as_set.py` (revises `0004`)
- Test: `tests/api/test_customer_routes.py`; `tests/tenancy` stays green (`test_b_sees_its_own_figures_not_as` reads the new rows)

**Interfaces:**
- Produces:
  - `patients.join_text(code: str) -> JoinText`
  - `patients.new_card(db, ph, amount: float, since: date) -> PatientDue`
  - `patients.rows_for_owner(db, pid) -> list[CustomerRow]`
  - `patients.CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"`

- [ ] **Step 1: Write the failing tests:**
  - `test_add_customer`: `{amount: 1200, since: <today>}` → 201. `code` matches `^GL-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$`, `label` is `"Customer 007"` (seed has 6), and `join == {"text": "LAMP " + code.replace("-", ""), "to": "21213"}`.
  - `test_customer_rows`: every row has `sms_status == "NONE"`, `join` and `trusted`. There is no `name` key anywhere in the body.
  - `test_trusted_means_every_part_paid_on_time`: a plan of 2 parts set on day 0, with part 1 paid on its due date → trusted. The same card with part 1 paid a day late → not trusted.
  - `test_future_since_is_422`.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.**
  - Codes are drawn with `secrets.choice` and retried on a clash.
  - The label is `Customer NNN`, the shop's count + 1, padded to 3 digits.
  - The opening balance is a ledger row `kind="adjust"`.
  - `sms_status` is `"NONE"` until A2.2 part 2 adds `family_contact`.
  - `trusted`: "all parts paid on time" (build plan 2.2). Every plan part due before today was covered, by its due date, by the card's ledger payments on or after the day the plan was set, and at least one part has fallen due. This needs the plan's parts as they were set, so migration 0005 adds `patient_dues.plan_amount` (the balance when the plan was set) and `plan_set_on`. `set_plan` fills both. A card with no plan is not trusted.
- [ ] **Step 4: Run the tests and see them pass.**
- [ ] **Step 5: Commit:** `api: customers listed with their join text, and added with a new card (I2.2, part 3)`

### Task 3.2: sales, payments and plan on a card

**Files:**
- Modify: `app/api/customers.py`; `app/engines/patients.py` (`record`; `set_plan(db, code, parts, first_on, *, by: Literal["family", "owner"] = "family")`, which notifies the owner only when `by == "family"`); `app/api/contract.py` (delete 3 lines)
- Test: `tests/api/test_customer_routes.py`

**Interfaces:**
- Produces: `patients.record(db, pid, code, kind: Literal["sale", "payment"], amount, on, method) -> CustomerBalance`, which is 404 when the card is another shop's.

- [ ] **Step 1: Write the failing tests:**
  - `test_sale_then_payment`: sale 500 → `amount` +500; payment 200 (bkash) → `amount` −200. There are two ledger rows, and the sum of the ledger equals `patient_dues.amount`.
  - `test_overpayment_is_422_and_nothing_changes`.
  - `test_owner_sets_the_plan`: PUT `{parts: 2, first_on: <today+3>}` → a `PatientCardOut` with 2 parts. `GET /cards/{code}` shows the same plan.
  - `test_another_shops_code_is_404` for each of the three routes.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.** Payment receipts and the plan SMS come with A2.2 and A2.3: add nothing here.
- [ ] **Step 4: Run the whole suite and see it pass.**
- [ ] **Step 5: Commit:** `api: sales, payments and the plan on a customer card (I2.2, part 3)`. Tick I2.2 (flow step 4 and Stage 2) in PROGRESS.md, then open PR 3.

The phone and remind routes stay as contract stubs: they belong to A2.2 part 2 (the Applink facade).
