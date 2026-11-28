"""Save the demo shop's History as text: logs/sandbox_execution_trace.log (submission item 6).

    DEMO_CODE=... python scripts/export_trace.py [--base http://127.0.0.1:8000/api/v1]

Signs in as the demo shop (POST /auth/demo; the server needs DEMO_ENABLED and DEMO_CODE)
and reads its own History (/pharmacies/{pid}/logs/export, one hash chain per shop). One
line per event:
[2026-10-16T14:05:00Z] [T3:REGISTRY] lock_acquired commitment=8f9c… application=APP-0001
"""

import argparse
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "logs" / "sandbox_execution_trace.log"
OUT_JSONL = OUT.with_suffix(".jsonl")  # verifiable copy: python scripts/verify_trace.py


PIN = "2468"  # demo owner PIN, still asked at loan approval until I3.3 (only its hash is in the seed)


def signed_in_opener(base: str, demo_code: str | None = None) -> urllib.request.OpenerDirector:
    """An opener that sends the demo shop owner's bearer token on every call."""
    code = demo_code or os.environ.get("DEMO_CODE", "")
    req = urllib.request.Request(f"{base.rstrip('/')}/auth/demo", method="POST",
                                 data=json.dumps({"demo_code": code}).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        signed_in = json.loads(r.read().decode("utf-8"))
    opener = urllib.request.build_opener()
    opener.addheaders = [("Authorization", f"Bearer {signed_in['access_token']}")]
    opener.pharmacy_id = (signed_in.get("pharmacy") or {}).get("id", "green-life")  # type: ignore[attr-defined]
    return opener


def export(base: str = "http://127.0.0.1:8000/api/v1", opener: urllib.request.OpenerDirector | None = None) -> Path:
    opener = opener or signed_in_opener(base)
    logs = f"{base.rstrip('/')}/pharmacies/{getattr(opener, 'pharmacy_id', 'green-life')}/logs/export"
    with opener.open(logs, timeout=30) as r:
        text = r.read().decode("utf-8")
    with opener.open(logs + "?format=jsonl", timeout=30) as r:
        jsonl = r.read().decode("utf-8")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    OUT_JSONL.write_text(jsonl, encoding="utf-8", newline="\n")
    return OUT


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8000/api/v1")
    print(f"Wrote {export(ap.parse_args().base)}")
