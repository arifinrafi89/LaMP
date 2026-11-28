# LaMP progress tracker

*How much of the build plan is done. Task ids and details are in [`LaMP-Build-Plan.md`](LaMP-Build-Plan.md), section 7 (the stages) and its Applink track. Last updated: 28 Nov 2026.*

**How to tick**

- Tick `[x]` when a task is done and pushed, and write where it is: **on `main`** (merged), **PR #n** (waiting for review), or **on a branch** (pushed but no PR to `main` yet).
- For settings and forms (Render, Applink, GitHub), tick when it's done and checked.
- Update the summary table in the same commit, and change the "Last updated" date. "Of those, on `main`" counts only ticked tasks whose work is merged into `main`.
- Each person ticks their own tasks. Arifin ticks in the same PR as the work.

## Where to pick up (27 Nov, end of day)

**For everyone, and your coding agents**

- **On `main`:**
  - the 27 Nov plan (no USSD; build order in stages) and this tracker;
  - Arifin's `applink/`, `auth/` and `jobs/` packages;
  - the Applink client and its mock (`backend/app/applink/client/`);
  - the families' text parser (`applink/family/commands.py`) and every SMS in English and Bangla (`applink/templates/`);
  - a gitleaks secret scan on every PR (`server.yml`).

  617 server tests pass.
- **Live:** `https://lamp-api-k2xf.onrender.com` runs the callback stub. `/health` is up, and all five Applink callback addresses answer S1000.
- **Rules so far:**
  - one branch per task (`<name>/<task>`), with a PR to `main`;
  - tick here in the same PR as the work;
  - no AI attribution in commits or PRs;
  - never commit secrets (gitleaks checks every PR);
  - only touch your own folders (CODEOWNERS).

**Ishmam: the main blocker**

1. **Merge `ishmam/I0.3-day0-setup` into `main`.** It holds I0.2–I0.5 and I1.1–I1.4: Alembic, the `owner` table and contract v1. Arifin's code was tested merged with it, and 650 tests pass.
2. **Update the contract for the 27 Nov plan:**
   1. `/demo/ussd` becomes `/demo/sms`, plus `GET /demo/sms/thread`.
   2. `CustomerCreated` and the customer rows get `join: {text, to}`.
   3. `MeOut` gets `family_join_routes`.
   4. Add `POST /plus/otp`, and `PlusStatus` gets `OTP_SENT`.
   5. Add the error `join_by_text` (403), for when the counter route is off.

**Ayon**

- Next is Stage 2: Y2.2 Scan, Y2.3 Stock and Y2.4 offline.
- Customers (Y3.1) shows the join text: `LAMP <code>` to 21213.
- The drawn phone (Y4.1) is now an SMS phone that calls `/demo/sms`.

**Arifin: next, in order**

1. **UptimeRobot (A0.1e):** sign in, then add the check.
2. **Once Ishmam's branch is on `main`:**
   - A1.3 jobs;
   - A1.2 sign-in;
   - A2.1 callbacks;
   - A2.2 part 2: joining and delivery reports;
   - the rest of A1.4: `render.yaml`, the Postgres tests and `tick.yml`.
3. **Your calls:**
   - send both Applink apps for approval (the drafts are ready);
   - add the two backup secrets to GitHub;
   - choose how to protect `main` (requiring Ishmam's review would block Arifin's own merges).

**For a coding agent picking up Arifin's part**

- **Read first:**
  - `backend/app/applink/client/base.py`: the rules for every Applink call;
  - `client/mock.py`: the test scenarios, keyed on a number's last two digits;
  - `family/commands.py`: the parser for families' texts.
- **Run the tests:** `cd backend && pytest -q`.
- **Before merging:** also test with any unmerged teammate branch that `main` will soon depend on.
- **Secrets:** never print them. The user pastes them from their clipboard.

## Summary

| Stage | Done | Of those, on `main` | Total |
|---|---|---|---|
| Stage 0: repo, accounts, Applink forms | 15 | 5 | 21 |
| Stage 1: foundations | 9 | 5 | 16 |
| Stage 2: core flows in mock mode | 5 | 5 | 13 |
| Stage 3: money, Plus, AI, families | 4 | 4 | 16 |
| Stage 4: test, fix, record | 1 | 1 | 11 |
| Stage 5: submit | 0 | 0 | 5 |
| Applink track | 1 | 0 | 9 |
| **All** | **35** | **20** | **91** |

> **Waiting to reach `main`:** Ishmam's branch `ishmam/I0.3-day0-setup` holds I0.2, I0.3, I0.4, I0.5 and I1.1–I1.4 (PRs #4 and #5 were merged into his own branches, not into `main`). Until it's merged, `main` has no Alembic, no Stage 0 packages, no `owner` table and no contract v1, and Arifin's and Ayon's server-side work can't build on them.

## Stage 0: the repo, accounts and Applink forms

- [x] **I0.1** Import commit (D14), pytest workflow, `CODEOWNERS` · **[I]** · on `main` (PR #2)
- [x] **I0.2** Defaults in 0.2 accepted · **[I]** · on a branch (`ishmam/I0.3-day0-setup`)
- [x] **I0.3** Stage 0 dependencies, Alembic skeleton · **[I]** · on a branch (`ishmam/I0.3-day0-setup`)
- [x] **I0.4** Contract v0 · **[I]** · on a branch (`ishmam/I0.3-day0-setup`, as contract v1)
- [x] **I0.5** `main.py` mounts Arifin's packages · **[I]** · on a branch (`ishmam/I0.3-day0-setup`)
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
- [ ] **MP0** New repo ready: tests pass in CI, CODEOWNERS in, the empty modules mounted, `mobile/` builds · signed off by **[I]**

## Stage 1: foundations

- [x] **I1.1** Alembic baseline 0001 + 0002 (`owner`, `pharmacy_id` on child tables, `patient_ledger`) · **[I]** · on a branch (`ishmam/I0.3-day0-setup`)
- [x] **I1.2** Real Dhaka date, `on_date`, demo seed shifted by whole weeks · **[I]** · on a branch (`ishmam/I0.3-day0-setup`)
- [x] **I1.3** Contract v1 for every Phase 1 screen · **[I]** · on a branch (`ishmam/I0.3-day0-setup`)
- [x] **I1.4** Stubs for the core functions in 1.4 B · **[I]** · on a branch (`ishmam/I0.3-day0-setup`)
- [ ] **I0.6** Farhan's written OK, screenshot in `docs/PRIOR_WORK.md` · **[I]**
- [x] **A1.1** Applink config, phone helpers, status-code table, client and mock · **[A]** · on `main` (PRs #11 and #12)
- [ ] **A1.2** `auth/`: OTP sign-in, tokens, refresh, devices, rate limits · **[A]**
- [ ] **A1.3** `jobs/`: table, runner inside the web service, scheduler, tick endpoint · **[A]**
- [ ] **A1.4** `render.yaml`, `backup.yml`, `tick.yml`, `server.yml` · **[A]** · `server.yml` with the secret scan on `main` (PR #14); the Postgres tests join it with the migrations; `render.yaml` waits for the migrations, `tick.yml` for A1.3, `backup.yml` for its secrets
- [x] **Y1.1** App shell: go_router, theme, ARB en and bn, digits, `ApiClient` · **[Y]** · on `main`
- [x] **Y1.2** Welcome, number, code, token store (app side; server sign-in is A1.2) · **[Y]** · on `main`
- [x] **Y1.3** Today · **[Y]** · on `main` (PR #1)
- [x] **G3** Terms, privacy policy and consent wordings in English and Bangla; `/legal/current` · **[A]** · on `main` (PR #24)
- [ ] **MP1** Contract v1 frozen (approved by Ayon and Arifin) · signed off by **[I]**
- [ ] **MP2** Interfaces in 1.4 merged as stubs · signed off by **[A]** and **[I]**
- [ ] **I0.6 follow-up** If Farhan says no: engines rewritten (cut order 15.1) · **[I]** · only if needed

## Stage 2: the core flows, end to end in mock mode

- [ ] **I2.1** One shared `pharmacy_id` dependency; tenancy harness · **[I]**
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
