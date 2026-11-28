# LaMP progress tracker

*How much of the build plan is done. Task ids and details are in [`LaMP-Build-Plan.md`](LaMP-Build-Plan.md), section 7 (the stages) and its Applink track. Last updated: 28 Nov 2026, night (back to a branch and a PR for every task).*

**How we work (since 28 Nov)**

- **One flow, not three lanes.** The [I]/[A]/[Y] tags below say who the plan first gave a task to. They no longer decide who builds it. Whoever is working (a teammate or their coding agent) takes the **first open task in "The flow"** below.
- **One task at a time, one branch and one pull request per task.** Nobody pushes to `main` directly, not even for docs. The full loop, with the superpowers skill for each step, is in [`CLAUDE.md`](../CLAUDE.md):
  1. pull `main`, then branch off it: `<name>/<task>`, for example `ayon/I2.2-core-routes`;
  2. plan the task (`superpowers:brainstorming` for anything new, `superpowers:writing-plans` for anything with several steps);
  3. build it test first (`superpowers:test-driven-development`); for a failing test or a bug, `superpowers:systematic-debugging` before any fix;
  4. run the whole server suite (`cd backend && pytest -q`), and `flutter analyze` and `flutter test` for `mobile/` changes, and see them pass before you call the task done (`superpowers:verification-before-completion`);
  5. tick the task here, on the same branch;
  6. review your own diff (`superpowers:requesting-code-review`), push the branch and open a PR to `main`;
  7. merge once CI is green on the PR and a teammate has approved it, then delete the branch (`superpowers:finishing-a-development-branch`).
- **Ticks:** tick `[x]` in the task's own PR, written as **on `main` (PR #n)**, so the tick reaches `main` with the work. For a setting or form, tick once it is done and checked. Update the summary table and the "Last updated" date in the same PR.
- **Hand over before you stop.** When a limit is near, commit what you have to the task's branch, push it, and open the PR as a draft if it isn't finished. Never merge anything red. Then rewrite "Where to pick up" (in that PR) for the next person: the branch, the PR, what's done and what's next.
- **Rules that stay:** no AI attribution in commits; never commit `.env` or keys (gitleaks checks every push); tests never call Applink or OpenAI (`APPLINK_MODE=mock`, `LLM_MODE=replay`); no customer names or medicines anywhere, amounts only.

## Where to pick up (28 Nov, evening handover)

- **Done today, all on `main`, CI green (716 server tests pass):**
  - Ishmam's setup merged: Alembic (`core` and `applink` branches), the `owner` table and shop kinds, contract v1, real Dhaka dates, the engine stubs for jobs.
  - Flow steps 1–3 below: the contract for the 27 Nov plan; owner sign-in (A1.2); one shop per session with the tenancy harness (I2.1).
- **How owners sign in now:**
  - `POST /auth/otp/request` and `/auth/otp/verify` on the Applink mock (the code is `123456`), then a 15-minute bearer token and a rotating refresh token;
  - every `/pharmacies/{pid}/*` route takes its shop from the token (`api/deps.py`), and another shop's id answers 404;
  - LaMP.ai's PIN unlock (`/pharmacies/{pid}/session`, `owner_session`) is gone; the PIN is only asked at loan approval, until I3.3 retires loan applications.
- **Next:** flow step 4, **I2.2 Core routes**. Build each route in its own module under `backend/app/api/`, and delete its "I" line in `api/contract.py` (a test checks this). Notes for it:
  - `/me`: `consents_needed` comes from `app.auth.consents.needed()`, and `family_join_routes` from `app.applink.config.get_settings().join_routes`;
  - `plan` and `plus_status`: read the `subscriber` mirror (`app.auth.sessions.plan_of()` shows how);
  - `POST /pharmacies` must set `owner.pharmacy_id`, so the next request finds the new shop (tokens don't carry it);
  - `GET /customers` must move from `PatientDueOut` to `CustomerRow`, with `join: {text: "LAMP " + code without dashes, to: "21213"}`.
- **Traps hit today:**
  - The clone path "Applink Hackathon" has a space. `alembic.ini` now lists migration folders one per line; keep it that way.
  - FastAPI here wraps included routers lazily (`_IncludedRouter`). To list every route, walk them the way `tests/tenancy/test_tenancy_routes.py` does.
  - Errors go through `app/api/problems.py` (`raise ApiProblem(status, code, detail)`). Wrong codes answer 400, never 401: the app treats 401 as "refresh and retry".
  - In tests, `owner_headers(db, pid)` (in `tests/conftest.py`) signs in any shop's owner. The API `client` fixture already carries green-life's token.
  - Test helper modules need unique names (`api_support.py`, `tenancy_support.py`): there are no `__init__.py` files, so `from conftest import …` picks the wrong folder's conftest.
  - With `DEV_MODE=true`, the empty `JWT_SECRET`, `PHONE_PEPPER` and `PII_KEY` fall back to dev values. Without it, the server won't start until they are set (`.env.example`).
  - History (`/logs*`) is still one chain for every shop. A strict xfail test in the tenancy harness marks it; flow step 5 fixes it.
- **Parked, for later:** everything on a website dashboard: Render, the Applink portal, UptimeRobot, GitHub settings. Until then, everything is built and tested in mock mode on a laptop.

**For a coding agent picking up**

- **Read first:**
  - the task's lines in [`LaMP-Build-Plan.md`](LaMP-Build-Plan.md): section 2.2 for routes, 3 for Applink, 4.3 for tables;
  - `backend/app/api/contract.py`: the routes not built yet, with their shapes. Building one means deleting its line there;
  - `backend/app/applink/client/base.py` and `client/mock.py`: the rules for every Applink call, and the test scenarios keyed on a number's last two digits.
- **Run the tests:** `cd backend && pytest -q`.
- **Secrets:** never print them. The user pastes them from their clipboard.

## The flow: what to build next, in order

Each step needs the ones before it. Tick here and in the stage lists below.

1. [x] **Contract for the 27 Nov plan:** `/demo/sms` and `GET /demo/sms/thread`; `join: {text, to}` on new customers and customer rows; `family_join_routes` in `/me`; `POST /plus/otp` and `OTP_SENT`; the `join_by_text` error. Ayon's app already calls these. · on `main` (28 Nov)
2. [x] **A1.2 Sign-in:** OTP sign-in (mock), tokens, refresh rotation, devices, demo sign-in, rate limits, `current_owner`; `POST /me/consents`. The `applink` migration branch starts here. · on `main` (28 Nov): `app/auth/`, `applink/otp.py`, migration `a001`
3. [x] **I2.1 One shop per session:** a shared dependency gives every owner route its `pharmacy_id` from the token (404 for another shop's id); tenancy test harness. · on `main` (28 Nov): `api/deps.py`, `tests/tenancy/`; the PIN unlock retired (core migration `0003`)
4. [ ] **I2.2 Core routes:** `/me`, create and set up a shop, suppliers, opening, stock, expenses, `/today`, payments, sales days, customers.
5. [ ] **Per-shop History:** every audit event carries its shop (`audit_log.pharmacy_id`), one hash chain per shop, and `/logs*` (list, export, verify, stream) show only the caller's shop. Then remove the strict xfail in `tests/tenancy/test_tenancy_routes.py`.
6. [ ] **A1.3 Jobs:** table, runner inside the web service, scheduler (Asia/Dhaka), tick endpoint; `/ready`.
7. [ ] **A1.4 part 2, CI:** server tests on Postgres, and the migration check (up, down one, up).
8. [ ] **A2.1 Callbacks:** the four Applink callbacks (answer first, dedupe, secret, IP list, redaction) and the subscription mirror.
9. [ ] **A2.2 part 2, families by SMS:** the facade (`applink/services.py`), `join.py`, both join routes, delivery reports.
10. [ ] **A2.3 The plan SMS; `/demo/sms`**, the drawn phone's thread, `/demo/reset`.
11. [ ] **I2.3 Capture changes:** `stored_file`, idempotency, the free plan's 10 scans, `ai_usage`.
12. [ ] **MP3 locally:** sign in (mock OTP), set up a shop, scan a demo bill, and Today shows the figures, with the app against a local server.
13. [ ] **A3.1 + I3.2 Credit record:** the CaaS state machine and charging notification; preview, PDF, shares, `/r/{token}`, `on_paid`.
14. [ ] **A3.2 + I3.1 LaMP Plus and Ask:** consent, the OTP on the Plus app, cancel, entitlements; chat with `pid` from the session, the Plus gate, per-shop budget.
15. [ ] **I3.3 Approvals;** `/dev`, `/lenders` and `/consents` not mounted in production.
16. [ ] **A3.3 Jobs that run every day:** 8 AM brief, reminders, nightly reconcile, stuck charges, demo reseed.
17. [ ] **Account and support routes:** `/me` export and delete, `/app/config`, `/support/reports`, `/telemetry/events`, `/usage`.
18. [ ] **I3.4 Tenancy tests for every route.**
19. [ ] **Stage 4 checks:** cross-testing pass (9.5) and P0/P1 fixes; I4.1 eval, red team and golden tests on Postgres; A4.3 secret scan of the whole history; Y4.2 integration tests against a local server.
20. [ ] **Words:** I4.2 README declarations; proposal drafts (I3.5, A3.5), screenshots (Y3.5), proposal compiled (I4.3).

**Done by people, not code:** I0.6 Farhan's written OK; the video (11.1); submitting (Stage 5).

**Parked (website dashboards), for later:** A0.0b Ishmam made an admin, A0.0c protecting `main`, A0.1e UptimeRobot, A0.2b and A0.2c sending both Applink apps for approval, A1.4 `render.yaml`, `backup.yml` and `tick.yml`, A2.4, A3.4, A4.1 and A4.2 (sandbox), Y4.2's web build on Render and signed APK, and the Applink track. Applink's approval takes about 2 days, so while it is parked, Phase 1 is shown in mock mode.

## Summary

| Stage | Done | Of those, on `main` | Total |
|---|---|---|---|
| Stage 0: repo, accounts, Applink forms | 16 | 10 | 21 |
| Stage 1: foundations | 11 | 11 | 16 |
| Stage 2: core flows in mock mode | 6 | 6 | 13 |
| Stage 3: money, Plus, AI, families | 4 | 4 | 16 |
| Stage 4: test, fix, record | 1 | 1 | 11 |
| Stage 5: submit | 0 | 0 | 5 |
| Applink track | 1 | 0 | 9 |
| **All** | **39** | **32** | **91** |

## Stage 0: the repo, accounts and Applink forms

- [x] **I0.1** Import commit (D14), pytest workflow, `CODEOWNERS` · **[I]** · on `main` (PR #2)
- [x] **I0.2** Defaults in 0.2 accepted · **[I]** · on `main` (merged 28 Nov)
- [x] **I0.3** Stage 0 dependencies, Alembic skeleton · **[I]** · on `main` (merged 28 Nov)
- [x] **I0.4** Contract v0 · **[I]** · on `main` (merged 28 Nov, as contract v1)
- [x] **I0.5** `main.py` mounts Arifin's packages · **[I]** · on `main` (merged 28 Nov)
- [x] **A0.0a** Ishmam and Ayon added to the repo · **[A]** · done (both have write access)
- [ ] **A0.0b** Ishmam made an admin · **[A]**
- [ ] **A0.0c** `main` protected (tell the others first) · **[A]**
- [x] **A0.1a** Render web service `lamp-api` running the callback stub · **[A]** · on `main` (PR #7)
- [x] **A0.1b** Render Postgres `lamp-db` · **[A]** · done (free, Singapore, PostgreSQL 16)
- [x] **A0.1c** Render's outbound addresses in the Applink forms · **[A]** · done (508 single IPs)
- [x] **A0.1d** `APPLINK_CALLBACK_SECRET` in Render · **[A]** · done 27 Nov: `lamp-api` is live; all five callback addresses answer S1000, a wrong secret gets 404, and the log holds no secret
- [ ] **A0.1e** UptimeRobot keep-awake on `/health` · **[A]** · next: Arifin signs in at dashboard.uptimerobot.com, then an HTTP check every 5 minutes
- [x] **A0.2a** Both Applink apps filled in and saved as drafts (LaMP `APP_019205`, LaMPPlus `APP_019207`) · **[A]** · done
- [ ] **A0.2b** Both apps sent for approval · **[A]**
- [ ] **A0.2c** Both approval emails sent from the team lead's address · **[I]**
- [x] **A0.3** Sign-in endpoint shapes to Ishmam · **[A]** · agreed: Ishmam's contract v1 (on his branch) matches plan 2.2 for every `/auth` route
- [x] **A0.4** Empty `applink/`, `auth/`, `jobs/` packages with their routers · **[A]** · on `main` (PR #10)
- [x] **Y0.1** `mobile/` created, design system copied, design lint tests green · **[Y]** · on `main`
- [x] **Y0.2** `mobile.yml` · **[Y]** · on `main`
- [x] **MP0** New repo ready: tests pass in CI, CODEOWNERS in, the empty modules mounted, `mobile/` builds · signed off by **[I]** · checked 28 Nov: `pytest`, `server` and `mobile` green on `main`; `auth`, `applink` and `jobs` mounted

## Stage 1: foundations

- [x] **I1.1** Alembic baseline 0001 + 0002 (`owner`, `pharmacy_id` on child tables, `patient_ledger`) · **[I]** · on `main` (merged 28 Nov)
- [x] **I1.2** Real Dhaka date, `on_date`, demo seed shifted by whole weeks · **[I]** · on `main` (merged 28 Nov)
- [x] **I1.3** Contract v1 for every Phase 1 screen · **[I]** · on `main` (merged 28 Nov)
- [x] **I1.4** Stubs for the core functions in 1.4 B · **[I]** · on `main` (merged 28 Nov)
- [ ] **I0.6** Farhan's written OK, screenshot in `docs/PRIOR_WORK.md` · **[I]**
- [x] **A1.1** Applink config, phone helpers, status-code table, client and mock · **[A]** · on `main` (PRs #11 and #12)
- [x] **A1.2** `auth/`: OTP sign-in, tokens, refresh, devices, rate limits · **[A]** · on `main` (28 Nov)
- [ ] **A1.3** `jobs/`: table, runner inside the web service, scheduler, tick endpoint · **[A]**
- [ ] **A1.4** `render.yaml`, `backup.yml`, `tick.yml`, `server.yml` · **[A]** · `server.yml` with the secret scan on `main` (PR #14); the Postgres tests join it with the migrations; `render.yaml` waits for the migrations, `tick.yml` for A1.3, `backup.yml` for its secrets
- [x] **Y1.1** App shell: go_router, theme, ARB en and bn, digits, `ApiClient` · **[Y]** · on `main`
- [x] **Y1.2** Welcome, number, code, token store (app side; server sign-in is A1.2) · **[Y]** · on `main`
- [x] **Y1.3** Today · **[Y]** · on `main` (PR #1)
- [x] **G3** Terms, privacy policy and consent wordings in English and Bangla; `/legal/current` · **[A]** · on `main` (PR #24)
- [x] **MP1** Contract v1 frozen (approved by Ayon and Arifin) · signed off by **[I]** · checked 28 Nov: every API path the app calls is in `contracts/openapi.json`, and the 27 Nov changes are in
- [ ] **MP2** Interfaces in 1.4 merged as stubs · signed off by **[A]** and **[I]**
- [ ] **I0.6 follow-up** If Farhan says no: engines rewritten (cut order 15.1) · **[I]** · only if needed

## Stage 2: the core flows, end to end in mock mode

- [x] **I2.1** One shared `pharmacy_id` dependency; tenancy harness · **[I]** · on `main` (28 Nov)
- [ ] **I2.2** New routes: `/me`, setup, suppliers, opening, stock, expenses, `/today`, payments, sales days, customers · **[I]**
- [ ] **I2.3** Capture changes (`stored_file`, idempotency, free-plan count, `ai_usage`) · **[I]**
- [ ] **A2.1** The four Applink callbacks and the subscription mirror · **[A]**
- [ ] **A2.2** Families by SMS: `family/commands.py`, `join.py`, both join routes, templates, delivery reports · **[A]** · part 1 (reading texts, SMS templates in English and Bangla) on `main` (PR #13); joining and delivery reports need the migrations
- [ ] **A2.3** The plan SMS; `/demo/sms` and the drawn phone's thread · **[A]**
- [ ] **A2.4** Sandbox items 1–7 as soon as the apps are approved · **[A]**
- [x] **Y2.1** Setup flow · **[Y]** · on `main` (PR #3)
- [x] **Y2.2** Scan · **[Y]** · on `main` (PR #17)
- [x] **Y2.3** Stock · **[Y]** · on `main` (PR #17)
- [x] **Y2.4** Offline cache, error and empty states · **[Y]** · on `main` (PR #17)
- [x] **Y-card** The family's web card `/me/<code>`: what they owe and a plan they choose · **[Y]** · on `main` (PR #23)
- [ ] **MP3** First end-to-end on the production service in mock mode · signed off by **[I]** and **[Y]**

## Stage 3: money, Plus, AI and families

- [ ] **I3.1** Chat: session `pid`, Plus gate, budget, recordings, red-team cases · **[I]**
- [ ] **I3.2** Credit record: preview, PDF, shares, `/r/{token}`, `on_paid` · **[I]**
- [ ] **I3.3** Approvals; `/dev`, `/lenders`, `/consents` unmounted in production · **[I]**
- [ ] **I3.4** Tenancy tests for every route · **[I]**
- [ ] **I3.5** Proposal P1, P2, P5 drafts · **[I]**
- [ ] **A3.1** CaaS state machine and charging notification · **[A]**
- [ ] **A3.2** LaMP Plus: consent, OTP on the Plus app, cancel, entitlements · **[A]**
- [ ] **A3.3** Jobs: 8 AM brief, reminders, reconcile, stuck charges, demo reseed · **[A]**
- [ ] **A3.4** Sandbox checklist run 1 · **[A]**
- [ ] **A3.5** Proposal P6 draft · **[A]**
- [x] **Y3.1** Customers: add with the join text, sale, payment, plan, SMS status · **[Y]** · on `main` (PR #18)
- [x] **Y3.2** Cash, Plan, Approvals · **[Y]** · on `main` (PR #19)
- [x] **Y3.3** Ask with the stream parser · **[Y]** · on `main` (PR #21)
- [x] **Y3.4** Credit record and LaMP Plus screens · **[Y]** · on `main` (PR #20)
- [ ] **Y3.5** Screenshots for P3, P4, P8 · **[Y]**
- [ ] **MP4** Phase 1 feature freeze; proposal drafts in · signed off by **[I]**

## Stage 4: test, fix and record

- [ ] **Cross-testing pass** (9.5) and P0/P1 fixes · all
- [ ] **A4.1** Production to sandbox; Sentry and UptimeRobot alerts; backup checked · **[A]**
- [ ] **A4.2** Sandbox checklist run 2 · **[A]**
- [ ] **A4.3** Secret scan of the whole history · **[A]**
- [x] **Y4.1** Settings, Help, report a problem, the SMS phone mock-up · **[Y]** · on `main` (PR #22: Settings, Help, the update gate, the drawn SMS phone)
- [ ] **Y4.2** Web build on Render, signed APK, integration tests · **[Y]**
- [ ] **I4.1** Eval, red team, golden tests on Postgres · **[I]**
- [ ] **I4.2** README declarations · **[I]**
- [ ] **I4.3** Proposal compiled · **[I]**
- [ ] **Video recorded** (11.1) · all
- [ ] **MP5** Release candidate `v0.1.0-rc1` · signed off by **[I]**

## Stage 5: submit

- [ ] **Step 1** P0 fixes; final video cut · **[I]**
- [ ] **Step 2** Proposal final, 8 pages · **[I]**, checked by **[A]** and **[Y]**
- [ ] **Step 3** Code freeze, tag `v0.1.0`, final deploy and smoke test · **[A]**, **[Y]**
- [ ] **Step 4** Submitted, at least 6 hours before the deadline · **[I]**
- [ ] **MP6** AppQuest's 22-item checklist ticked · signed off by **[I]**

## The Applink track (beside the stages)

- [x] **1a** Both drafts finished (LaMP's description and stop text updated on 27 Nov) · **[A]** · done
- [ ] **1b** Both apps sent for approval, approval emails the same hour · **[A]**, **[I]**
- [ ] **2** `APPLINK_CALLBACK_SECRET` in Render (done 27 Nov); UptimeRobot (open) · **[A]**
- [ ] **3a** Approval arrived · Applink
- [ ] **3b** Ayon texts `LAMP test` to 21213; the stub's log shows whether it arrived · **[A]**, **[Y]**
- [ ] **4** Production to `sandbox`; sandbox items 1–7; `FAMILY_JOIN_ROUTES` and the subscribe method set · **[A]**
- [ ] **5** Questions sent to Applink in one message (`APPLINK_QUESTIONS.md`) · **[A]**
- [ ] **6** Full sandbox checklist, runs 1 and 2 · **[A]**
- [ ] **7** Live approval requested; `docs/GO_LIVE.md` · **[A]**
