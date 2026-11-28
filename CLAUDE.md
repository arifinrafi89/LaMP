# LaMP: start here

LaMP helps small pharmacies in Bangladesh keep track of bills, stock, cash and what customers owe. Families get their balance and reminders by SMS through Banglalink's Applink. It has a Flutter app (`mobile/`) and a FastAPI server (`backend/`). The whole design is in [`docs/LaMP-Build-Plan.md`](docs/LaMP-Build-Plan.md).

## Before you do anything

1. Pull `main`.
2. Read **[`docs/PROGRESS.md`](docs/PROGRESS.md)**: "How we work", then "Where to pick up", then "The flow".
3. Take the **first unticked step in "The flow"**. The [A]/[I]/[Y] tags show who the plan first gave a task to. They no longer say who does it: whoever is working takes the next step.

## The loop, for every step

1. Build the step and its tests. PROGRESS.md names the plan sections to read.
2. Run the server tests: `cd backend && pytest -q`. To set up once: Python 3.12+, `pip install -e ".[dev]"`. For `mobile/` changes, also run `flutter analyze` and `flutter test` in `mobile/`.
3. Commit straight to `main` and push. There are no branches and no PRs.
4. Tick the step in `docs/PROGRESS.md`, in the same commit or the next one. Update the summary table and "Last updated" too.
5. Read the CI run on `main` once. Fix anything red before you start the next step.

## Before you stop (limit near, end of the day)

Finish the step or back it out, so `main` stays green. Then rewrite "Where to pick up" in `docs/PROGRESS.md`. Say what's done, what's half-done and where it is, what the next step is, and any traps you hit. That box is the only handover the next person's agent gets.

## Hard rules

- Never commit `.env`, keys or tokens, and never print a secret in chat or in logs. gitleaks checks every push.
- No AI attribution in commits: no `Co-Authored-By` lines.
- Tests never call Applink or OpenAI: use `APPLINK_MODE=mock` and `LLM_MODE=replay`.
- Tests and staging use test data only. Real shops' and families' data exists only in production.
- Every Applink call is made from the server, never from the app. Credentials come only from the server's environment.
- Family cards and every SMS show amounts only: never a customer's real name, and never a medicine linked to a customer. A family's phone number lives in its own table, linked only to the card code.
- Don't cut security, privacy or data safety to save time. Cut features instead (plan 15.1).
- Website dashboards are parked, because they need the repo owner: Render, the Applink portal, UptimeRobot and GitHub settings. Skip them and take the next code step.

## Where things are

- `backend/app/api/contract.py`: every route that isn't built yet, with its shapes. Building a route means deleting its line here.
- `backend/app/applink/`: the Applink client and its mock (test scenarios are keyed on a phone number's last two digits), the SMS texts, and the families' text commands.
- `backend/migrations/`: Alembic, with two branches, `core` and `applink`.
- `contracts/openapi.json`: the API the app calls.
- `mobile/`: the Flutter app.
