"""Background jobs (Arifin; build plan D6 and 1.4 C).

Render's free plan has no workers or cron jobs, so the job loop runs inside the
web service (runner.py), with a GitHub Actions tick as the backstop. Built in A1.3.
"""
