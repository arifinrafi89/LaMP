# LaMP progress tracker

*How much of the build plan is done. Task ids and details are in [`LaMP-Build-Plan.md`](LaMP-Build-Plan.md), section 7 (the stages) and its Applink track. Last updated: 27 Nov 2026.*

**How to tick**

- Tick `[x]` when a task is done and pushed, and write where it is: **on `main`** (merged), **PR #n** (waiting for review), or **on a branch** (pushed but no PR to `main` yet).
- For settings and forms (Render, Applink, GitHub), tick when it's done and checked.
- Update the summary table in the same commit, and change the "Last updated" date. "Of those, on `main`" counts only ticked tasks whose work is merged into `main`.
- Each person ticks their own tasks. Arifin ticks in the same PR as the work.

## Summary

| Stage | Done | Of those, on `main` | Total |
|---|---|---|---|
| Stage 0: repo, accounts, Applink forms | 14 | 5 | 21 |
| Stage 1: foundations | 8 | 4 | 15 |
| Stage 2: core flows in mock mode | 1 | 1 | 12 |
| Stage 3: money, Plus, AI, families | 0 | 0 | 16 |
| Stage 4: test, fix, record | 0 | 0 | 11 |
| Stage 5: submit | 0 | 0 | 5 |
| Applink track | 1 | 0 | 9 |
| **All** | **24** | **10** | **89** |

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
- [ ] **A0.1d** `APPLINK_CALLBACK_SECRET` in Render · **[A]**
- [ ] **A0.1e** UptimeRobot keep-awake on `/health` · **[A]**
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
- [ ] **A1.4** `render.yaml`, `backup.yml`, `tick.yml`, `server.yml` · **[A]**
- [x] **Y1.1** App shell: go_router, theme, ARB en and bn, digits, `ApiClient` · **[Y]** · on `main`
- [x] **Y1.2** Welcome, number, code, token store (app side; server sign-in is A1.2) · **[Y]** · on `main`
- [x] **Y1.3** Today · **[Y]** · on `main` (PR #1)
- [ ] **MP1** Contract v1 frozen (approved by Ayon and Arifin) · signed off by **[I]**
- [ ] **MP2** Interfaces in 1.4 merged as stubs · signed off by **[A]** and **[I]**
- [ ] **I0.6 follow-up** If Farhan says no: engines rewritten (cut order 15.1) · **[I]** · only if needed

## Stage 2: the core flows, end to end in mock mode

- [ ] **I2.1** One shared `pharmacy_id` dependency; tenancy harness · **[I]**
- [ ] **I2.2** New routes: `/me`, setup, suppliers, opening, stock, expenses, `/today`, payments, sales days, customers · **[I]**
- [ ] **I2.3** Capture changes (`stored_file`, idempotency, free-plan count, `ai_usage`) · **[I]**
- [ ] **A2.1** The four Applink callbacks and the subscription mirror · **[A]**
- [ ] **A2.2** Families by SMS: `family/commands.py`, `join.py`, both join routes, templates, delivery reports · **[A]**
- [ ] **A2.3** The plan SMS; `/demo/sms` and the drawn phone's thread · **[A]**
- [ ] **A2.4** Sandbox items 1–7 as soon as the apps are approved · **[A]**
- [x] **Y2.1** Setup flow · **[Y]** · on `main` (PR #3)
- [ ] **Y2.2** Scan · **[Y]**
- [ ] **Y2.3** Stock · **[Y]**
- [ ] **Y2.4** Offline cache, error and empty states · **[Y]**
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
- [ ] **Y3.1** Customers: add with the join text, sale, payment, plan, SMS status · **[Y]**
- [ ] **Y3.2** Cash, Plan, Approvals · **[Y]**
- [ ] **Y3.3** Ask with the stream parser · **[Y]**
- [ ] **Y3.4** Credit record and LaMP Plus screens · **[Y]**
- [ ] **Y3.5** Screenshots for P3, P4, P8 · **[Y]**
- [ ] **MP4** Phase 1 feature freeze; proposal drafts in · signed off by **[I]**

## Stage 4: test, fix and record

- [ ] **Cross-testing pass** (9.5) and P0/P1 fixes · all
- [ ] **A4.1** Production to sandbox; Sentry and UptimeRobot alerts; backup checked · **[A]**
- [ ] **A4.2** Sandbox checklist run 2 · **[A]**
- [ ] **A4.3** Secret scan of the whole history · **[A]**
- [ ] **Y4.1** Settings, Help, report a problem, the SMS phone mock-up · **[Y]**
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
- [ ] **2** `APPLINK_CALLBACK_SECRET` in Render; UptimeRobot · **[A]**
- [ ] **3a** Approval arrived · Applink
- [ ] **3b** Ayon texts `LAMP test` to 21213; the stub's log shows whether it arrived · **[A]**, **[Y]**
- [ ] **4** Production to `sandbox`; sandbox items 1–7; `FAMILY_JOIN_ROUTES` and the subscribe method set · **[A]**
- [ ] **5** Questions sent to Applink in one message (`APPLINK_QUESTIONS.md`) · **[A]**
- [ ] **6** Full sandbox checklist, runs 1 and 2 · **[A]**
- [ ] **7** Live approval requested; `docs/GO_LIVE.md` · **[A]**
