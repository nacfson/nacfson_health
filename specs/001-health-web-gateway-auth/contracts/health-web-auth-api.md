# Contract: health-web Auth API (browser-facing)

All paths are on `https://health.nacfson.cloud`. Error bodies follow the API convention
`{"error":"<code>","message":"…"}`. A `401` body is exactly `{"error":"unauthorized"}`.

## GET /api/auth/config (public, DB-free, gateway-free)

Frontend `startupProbe` target. `200 {"login_url":"/api/auth/login"}`. Sets no cookies.

## GET /api/auth/login?next=<path> (public)

- `next`: optional relative path. It MUST start with a single `/`. Anything else (absolute URL,
  `//host`, `\`, control characters) becomes `/`.
- Sets `__Host-health_login`.
- `302 Location: https://auth.nacfson.cloud/oauth/start?return=<urlencoded
  https://health.nacfson.cloud/api/auth/callback?pa_bind=<b64url sha256(nonce)>[&next=<path>]>`

## GET /api/auth/callback?ticket=&pa_bind=&next= (public, called by the gateway's redirect)

| Condition | Response |
|---|---|
| no `ticket` | `302 /?auth=failed` |
| missing nonce cookie, missing `pa_bind`, or mismatch | `302 /?auth=failed` (ticket NOT redeemed) |
| exchange `401` / bad body / empty handle | `302 /?auth=failed` |
| exchange unreachable / 5xx | `302 /?auth=unavailable` |
| `audience != project-health` | `302 /?auth=failed` |
| DB failure | `302 /?auth=unavailable` |
| success | upsert user, create session, set `__Host-health_session`, clear `__Host-health_login`, `302 <next or />` |

Every response clears `__Host-health_login`.

## GET /api/me (authenticated)

`200 {"user_id":"<uuid>"}`. Issues `health_csrf` if absent. No email.

## POST /api/auth/logout (cookie + CSRF)

- Requires an allowed `Origin` and `X-CSRF-Token` equal to the `health_csrf` cookie. Otherwise
  `403 {"error":"csrf_failed"}`.
- Always deletes the session row (if any) and clears `__Host-health_session`.
- `200 {"status":"signed_out","platform":"revoked"}` when the gateway confirmed revocation.
- `200 {"status":"signed_out","platform":"unconfirmed"}` when the gateway call failed.
- `200 {"status":"signed_out","platform":"none"}` when there was no session.

Replaces `POST /api/logout` (removed).

## Every other /api/* route

Unchanged paths and payloads. Authentication per `research.md` R6:

- `401 {"error":"unauthorized"}`: no, unknown, or expired session, or the gateway rejected it.
- `503 {"error":"auth_unavailable","message":"…"}`: the gateway is unreachable.

Request headers `X-User-Id`, `X-User-Email`, `X-User-Roles`, `X-User-Subject`, `X-User-Issuer`, and
`Authorization` are deleted before authentication and never trusted.
