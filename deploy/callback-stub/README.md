# Day 0 Applink callback stub (A0.1)

A tiny server that Render's `lamp-api` service runs until the real `backend/app/applink/` router is deployed. It gives Applink a live address for the app forms (A0.2) and answers every callback with success. It stores nothing.

| Request | Answer |
|---|---|
| `GET` or `HEAD /health` | `200 {"status": "ok"}` (Render's health check and UptimeRobot) |
| `POST /applink/{core\|plus}/{secret}/{kind}`, with `kind` one of `sms/receive`, `sms/report`, `ussd/receive`, `subscription/notify`, `caas/notify` | `200 {"statusCode": "S1000", "statusDetail": "Success"}` |
| A wrong secret, app or kind | `404` |
| A body over 16 KB | `413` |
| A body that isn't JSON | `400` |

- **Logs:** only the app, the kind and the `requestId`. Never phone numbers, message text or the secret, so the default access log is off, because it would print the path, and the path holds the secret.
- **Code:** the standard library only, so it doesn't touch `backend/pyproject.toml`.
- **Shutdown:** it exits cleanly on SIGTERM, which Render sends on every deploy.

## Environment

| Variable | Value |
|---|---|
| `APPLINK_CALLBACK_SECRET` | A random value of at least 32 characters. It is kept only in Render's environment, and the server refuses to start without it. The same value goes in the Applink callback URLs. |
| `PORT` | Set by Render. Defaults to 8000. |

## Render settings for `lamp-api` (until A1.4)

| Setting | Value |
|---|---|
| Runtime | Docker |
| Branch | `main` |
| Dockerfile path | `deploy/callback-stub/Dockerfile` |
| Docker build context | `deploy/callback-stub` |
| Health check path | `/health` |

When `render.yaml` lands (A1.4), the service switches to the backend's Dockerfile, and the same paths are served by `backend/app/applink/`. The service's address stays the same, and this folder is deleted.

## Test

```bash
cd deploy/callback-stub && python -m unittest -v
```
