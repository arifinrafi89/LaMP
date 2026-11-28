# LaMP: start here

LaMP helps small pharmacies in Bangladesh keep track of bills, stock, cash and what customers owe. Families get their balance and reminders by SMS through Banglalink's Applink. It has a Flutter app (`mobile/`) and a FastAPI server (`backend/`). The whole design is in [`docs/LaMP-Build-Plan.md`](docs/LaMP-Build-Plan.md).

## Before you do anything

1. Pull `main`.
2. Read **[`docs/PROGRESS.md`](docs/PROGRESS.md)**: "How we work", then "Where to pick up", then "The flow".
3. Take the **first unticked step in "The flow"** that has no open PR yet (`gh pr list`). The [A]/[I]/[Y] tags show who the plan first gave a task to. They no longer say who does it: whoever is working takes the next step.

## The loop, for every step

Every step gets its own branch and its own pull request. Nobody pushes to `main` directly, not even for docs. Use the superpowers skills named below. They are installed as the `superpowers` plugin for Claude Code. Invoke each one with the Skill tool when you reach its step.

1. **Branch.** Pull `main`, then `git switch -c <name>/<task>`, for example `ayon/I2.2-core-routes`. A big step may be split into parts, with one branch and one PR per part.
2. **Plan.** For a new feature or a change in behaviour, `superpowers:brainstorming` first. For anything with several steps, `superpowers:writing-plans`, then carry the plan out with `superpowers:executing-plans` (or `superpowers:subagent-driven-development`). PROGRESS.md names the plan sections to read.
3. **Build test first** with `superpowers:test-driven-development`. For a failing test, a red CI run or any bug, use `superpowers:systematic-debugging` before you change any code.
4. **Run the tests:** `cd backend && pytest -q`. To set up once: Python 3.12+, `pip install -e ".[dev]"`. For `mobile/` changes, also run `flutter analyze` and `flutter test` in `mobile/`. Follow `superpowers:verification-before-completion`: never say a step is done, fixed or passing until you have seen the commands pass.
5. **Tick** the step in `docs/PROGRESS.md` on the same branch, as "on `main` (PR #n)". Update the summary table and "Last updated" too.
6. **Review, then open the PR.** Review your own diff with `superpowers:requesting-code-review` and fix what it finds. Then push the branch and open a PR to `main` with `gh pr create`. Say what changed, why, and how it was tested. CODEOWNERS asks the right teammate to review it.
7. **Get it green and approved.** Read the CI run on the PR, and fix anything red on the branch. Answer review comments with `superpowers:receiving-code-review`: check each one against the code before you change anything.
8. **Merge** once CI is green and a teammate has approved. Then delete the branch, pull `main`, and start the next step on a new branch. `superpowers:finishing-a-development-branch` walks through this.

## Before you stop (limit near, end of the day)

Commit what you have to the step's branch and push it. If the step isn't finished, open its PR as a draft (`gh pr create --draft`). Never merge anything red into `main`. Then rewrite "Where to pick up" in `docs/PROGRESS.md`, on that branch. Say what's done, what's half-done (the branch and the PR), what the next step is, and any traps you hit. That box is the only handover the next person's agent gets.

## Hard rules

- Never commit `.env`, keys or tokens, and never print a secret in chat or in logs. gitleaks checks every push.
- No AI attribution in commits or PRs: no `Co-Authored-By` lines.
- Never push to `main` directly, and never merge a PR whose CI is red. Every change goes through a branch and a PR.
- Start each commit message with its area (`api:`, `auth:`, `applink:`, `mobile:`, `docs:` …).
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
