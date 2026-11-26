"""Day 0 Applink callback stub (plan A0.1).

Answers S1000 on the five Applink callback paths for both apps, so Render's
`lamp-api` service has a stable address and a health check before the real
`backend/app/applink/` router exists. It stores nothing and logs no phone
numbers or message text: only the app, the callback kind and the requestId.

Standard library only, so it never touches backend/pyproject.toml.

Paths (plan 2.2):  POST /applink/{core|plus}/{secret}/{kind}
    kind = sms/receive | sms/report | ussd/receive | subscription/notify | caas/notify
Health:            GET or HEAD /health

Environment:
    APPLINK_CALLBACK_SECRET  required, at least 32 characters
    PORT                     set by Render (default 8000)
"""
import hmac
import json
import logging
import os
import signal
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APPS = {"core", "plus"}
KINDS = {"sms/receive", "sms/report", "ussd/receive", "subscription/notify", "caas/notify"}
MAX_BODY = 16 * 1024  # plan 10.1: 16 KB body limit on /applink/*
OK = {"statusCode": "S1000", "statusDetail": "Success"}
SECURITY_HEADERS = {
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "no-store",
}

log = logging.getLogger("callback-stub")


def make_handler(secret: str):
    secret_b = secret.encode()

    class Handler(BaseHTTPRequestHandler):
        server_version = "lamp"
        sys_version = ""

        def _send(self, status: int, body: dict | None = None) -> None:
            data = json.dumps(body).encode() if body is not None else b""
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            for k, v in SECURITY_HEADERS.items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD" and data:
                self.wfile.write(data)

        def log_message(self, fmt, *args):  # the default logs full paths, which hold the secret
            pass

        def do_GET(self):
            if self.path.split("?")[0] == "/health":
                self._send(200, {"status": "ok"})
            else:
                self._send(404, {"detail": "Not Found"})

        do_HEAD = do_GET

        def do_POST(self):
            parts = self.path.split("?")[0].strip("/").split("/")
            # applink / app / secret / kind (two segments)
            if len(parts) != 5 or parts[0] != "applink":
                return self._send(404, {"detail": "Not Found"})
            app, given, kind = parts[1], parts[2].encode(), "/".join(parts[3:])
            if app not in APPS or kind not in KINDS or not hmac.compare_digest(given, secret_b):
                return self._send(404, {"detail": "Not Found"})
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                return self._send(400, {"detail": "Bad Content-Length"})
            if length > MAX_BODY:
                return self._send(413, {"detail": "Body too large"})
            raw = self.rfile.read(length) if length else b""
            try:
                body = json.loads(raw or b"{}")
            except ValueError:
                return self._send(400, {"detail": "Body is not JSON"})
            request_id = body.get("requestId", "-") if isinstance(body, dict) else "-"
            log.info("callback app=%s kind=%s requestId=%s", app, kind, request_id)
            self._send(200, OK)

    return Handler


def build_server(secret: str, port: int, host: str = "0.0.0.0") -> ThreadingHTTPServer:
    return ThreadingHTTPServer((host, port), make_handler(secret))


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    secret = os.environ.get("APPLINK_CALLBACK_SECRET", "")
    if len(secret) < 32:
        sys.exit("APPLINK_CALLBACK_SECRET is missing or shorter than 32 characters")
    port = int(os.environ.get("PORT", "8000"))
    # As PID 1 in a container, Python ignores SIGTERM unless it has a handler;
    # Render sends SIGTERM on every deploy and restart.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    server = build_server(secret, port)
    log.info("callback stub listening on port %d", port)
    server.serve_forever()


if __name__ == "__main__":
    main()
