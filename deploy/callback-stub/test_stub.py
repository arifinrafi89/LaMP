"""Tests for the Day 0 callback stub. Run: python -m unittest -v (in this folder).

Outside tests/ on purpose: the stub is removed once the real applink router
is deployed, and CI's pytest collects only tests/.
"""
import json
import threading
import unittest
import urllib.error
import urllib.request

import stub

SECRET = "s" * 40
KINDS = ["sms/receive", "sms/report", "ussd/receive", "subscription/notify", "caas/notify"]


class StubTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = stub.build_server(SECRET, 0, host="127.0.0.1")
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def call(self, method, path, body=None, raw=None):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        req = urllib.request.Request(self.base + path, data=data, method=method,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            with e:
                return e.code, e.read()

    def test_health(self):
        status, body = self.call("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {"status": "ok"})
        self.assertEqual(self.call("HEAD", "/health")[0], 200)

    def test_all_five_paths_answer_s1000_for_both_apps(self):
        for app in ("core", "plus"):
            for kind in KINDS:
                with self.subTest(app=app, kind=kind):
                    status, body = self.call("POST", f"/applink/{app}/{SECRET}/{kind}", {"requestId": "r1"})
                    self.assertEqual(status, 200)
                    self.assertEqual(json.loads(body)["statusCode"], "S1000")

    def test_wrong_secret_unknown_app_or_kind_is_404(self):
        for path in (f"/applink/core/{'x' * 40}/sms/receive",
                     f"/applink/other/{SECRET}/sms/receive",
                     f"/applink/core/{SECRET}/sms/other",
                     f"/applink/core/{SECRET}"):
            with self.subTest(path=path):
                self.assertEqual(self.call("POST", path, {})[0], 404)

    def test_body_over_16_kb_is_413(self):
        status, _ = self.call("POST", f"/applink/core/{SECRET}/sms/receive", raw=b"{" + b" " * (16 * 1024) + b"}")
        self.assertEqual(status, 413)

    def test_body_not_json_is_400(self):
        status, _ = self.call("POST", f"/applink/core/{SECRET}/sms/receive", raw=b"not json")
        self.assertEqual(status, 400)

    def test_security_headers(self):
        req = urllib.request.Request(self.base + "/health")
        with urllib.request.urlopen(req) as r:
            self.assertIn("max-age", r.headers["Strict-Transport-Security"])
            self.assertEqual(r.headers["X-Content-Type-Options"], "nosniff")


if __name__ == "__main__":
    unittest.main()
