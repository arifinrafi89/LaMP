"""Job settings, read only from the server's environment (build plan D6, 10.2; task A1.3).

    JOBS_LOOP           run the job loop inside the web service (default on; tests turn it off)
    JOBS_POLL_SECONDS   how often the loop looks for due jobs (default 5)
    JOBS_TICK_SECRET    the secret the GitHub Actions tick sends (X-Tick-Secret), so a job still
                        runs if the service was asleep or restarted

With DEV_MODE on, an empty tick secret falls back to a fixed dev value; with DEV_MODE off it
must be a random string of at least 32 characters, or the server refuses to start.
"""
from functools import lru_cache
from pathlib import Path

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[3]
MIN_SECRET = 32
_NAME = "jobs_tick_secret"
_DEV_TICK_SECRET = f"dev-only-{_NAME}-not-for-any-real-shop"  # as auth/config.py builds its dev values


class JobsSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=REPO_ROOT / ".env", extra="ignore")

    dev_mode: bool = False
    jobs_loop: bool = True
    jobs_poll_seconds: float = 5.0
    jobs_tick_secret: SecretStr = SecretStr("")

    def tick_secret(self) -> str:
        value = self.jobs_tick_secret.get_secret_value()
        if value:
            return value
        return _DEV_TICK_SECRET if self.dev_mode else ""

    def problems(self) -> list[str]:
        """What stops the server starting. Names only, never values."""
        value = self.jobs_tick_secret.get_secret_value()
        if not value and not self.dev_mode:
            return ["JOBS_TICK_SECRET is not set"]
        if value and len(value) < MIN_SECRET:
            return [f"JOBS_TICK_SECRET is shorter than {MIN_SECRET} characters"]
        return []


@lru_cache
def get_settings() -> JobsSettings:
    return JobsSettings()


def check() -> None:
    """Called at start-up: refuse to run without a real tick secret (unless DEV_MODE)."""
    if problems := get_settings().problems():
        raise RuntimeError("Job settings: " + "; ".join(problems))
