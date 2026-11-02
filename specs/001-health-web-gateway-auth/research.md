# Research: health-web Sign-In Through the Platform Gateway

All facts below were read from `nacfson_pipeline` at `913f03c` (`gateway/`, `contracts/`,
`deploy/`, `clusters/vps-k3s/`) and from the live cluster on 2026-11-02 (read-only).

## R1. Gateway endpoints health-web consumes

| Endpoint | Caller | Request | Response |
|---|---|---|---|
| `GET https://auth.nacfson.cloud/oauth/start?return=<url>` | Browser | `return` MUST be `https`, no userinfo, host in `PROJECT_RETURN_HOSTS` (includes `health.nacfson.cloud`). Otherwise `400`. | `302` to Keycloak (`kc_idp_hint=google`). After sign-in, `302` to `<return>&ticket=<one-time>` |
| `POST http://gateway.identity.svc:8080/auth/exchange` | Backend | JSON `{"ticket":"…"}`, header `X-Forwarded-Host: health.nacfson.cloud` (ticket is bound to that host) | `200 {"session_handle","subject","issuer","audience","expires_in"}`. `401` if the ticket is unknown, used, expired, or for another host |
| `GET http://gateway.identity.svc:8080/auth` | Backend | `Authorization: Bearer <session_handle>`, `X-Forwarded-Host: health.nacfson.cloud` | `200` + headers `X-User-Subject`, `X-User-Issuer`, `X-Project-Audience`, optional `X-Refreshed-Session-Handle` (also `Authorization`, `X-User-Email`, which health-web ignores). `401` unsigned/expired/revoked/foreign audience. `503` when Keycloak is unreachable |
| `POST http://gateway.identity.svc:8080/auth/logout` | Backend | `Authorization: Bearer <session_handle>`. The bearer path needs no CSRF/Origin (that check applies only to the legacy cookie path) | `200 {"status":"revoked"}`. `400` malformed, `502` revocation failed, `503` revocation not configured |

The audience is derived from the host's first label: `health.nacfson.cloud` → `project-health`.
Keycloak has a `project-health-audience` mapper.

**Decision**: health-web calls these four endpoints directly. It does not import
`nacfson_pipeline/gateway/pkg/projectauth`: that module path (`nacfson_pipeline/gateway`) cannot be
fetched with `go get`, and the package assumes the browser holds the handle (see R2).

## R2. Where the session handle lives

The session handle is AES-GCM-sealed JSON containing a Keycloak access token, a refresh token,
session id, subject, and issuer, base64url-encoded with a `v1.` prefix. Keycloak access tokens with
`openid profile email` scopes are typically 1.2–1.8 KB and refresh tokens 0.7–1 KB, so the sealed
handle lands around 3–4 KB. A refreshed handle can grow.

Options:

| Option | Verdict |
|---|---|
| A. Handle in browser JS memory, sent as `Authorization: Bearer` (projectauth / pipeline 009 design) | Rejected. Every health route carries `platform/strip-forged-headers`, which sets `Authorization: ""`, and Traefik removes a header whose custom value is empty. The bearer would not reach the backend. It also exposes the handle to page scripts, which FR-012 forbids. |
| B. Handle itself in an HttpOnly cookie | Rejected. At about 3–4 KB plus attributes it sits at the browser's 4096-byte per-cookie limit. Browsers drop oversize cookies silently, which would look like a sign-in loop. |
| C. Random session id in a host-only HttpOnly cookie; handle stored server-side | **Chosen.** The cookie stays small and constant-size. The handle never reaches the browser. Revocation and refresh are a row update. Sessions survive backend restarts. |

`CONTRACT_AUTH_DOOR.md` §3.2 already describes a backend-held, cookie-carried session. Option C
keeps the gateway call itself bearer-based (§3 of `docs/project-auth-verification.md`).

## R3. Sign-in handoff binding (login CSRF)

**Decision**: Mirror projectauth's binding. `GET /api/auth/login` sets `__Host-health_login=<nonce>`
(random 128-bit hex, HttpOnly, Secure, SameSite=Lax, 10 min) and puts
`pa_bind=base64url(sha256(nonce))` in the callback URL passed as `return`. The callback compares the
two in constant time before redeeming the ticket. The gateway's own `OIDC_AUTH_STATE` cookie binds
the Keycloak leg. The ticket is single-use and host-bound (R1). SameSite=Lax cookies are sent on the
top-level `302` navigation back from `auth.nacfson.cloud`.

## R4. Identity and project accounts

**Decision**: New table `users(id uuid, issuer, subject, UNIQUE(issuer, subject))`. Upserted on a
successful callback. Every existing user-owned table keeps `user_id UUID`, so no store query changes.
No email, name, or profile identity data is stored (FR-006, FR-016). The gateway's `X-User-Email`
header is ignored.

## R5. Schema migrations never ran in the cluster

`nacfson_pipeline/contracts/CONTRACT_DATABASE.md` §6 requires idempotent migrations to run
"automatically on backend startup from `MIGRATIONS_PATH`". The health API never does this, and the
pipeline has no migrate Job or init container. So `proj_health` most likely has no tables, and there
is certainly no user data to carry over (the spec's pre-release assumption holds, and gets verified
in the startup log).

**Decision**: On startup, `cmd/api` runs `migrations.Up(MIGRATIONS_PATH)` and then the idempotent
master-catalog seed before serving. A failure exits non-zero, so startup fails visibly. A
`MIGRATE_ON_START=false` escape hatch exists for local work. golang-migrate takes a Postgres advisory
lock, so a rolling update cannot double-apply. No pipeline change is needed (SC-007).

## R6. Failure mapping

| Gateway result | health-web response | Cookie | Log event |
|---|---|---|---|
| `/auth` 200, audience = `project-health`, issuer/subject = session row | proceed | refresh handle if `X-Refreshed-Session-Handle` | — |
| `/auth` 200 but audience or identity mismatch | `401 {"error":"unauthorized"}` | delete row, clear cookie | `auth.session.rejected reason=identity_mismatch` |
| `/auth` 401 | `401 {"error":"unauthorized"}` | delete row, clear cookie | `auth.session.rejected reason=gateway_401` |
| `/auth` 503, other status, or network error | `503 {"error":"auth_unavailable"}` | keep | `auth.gateway.unavailable` |
| no cookie, unknown or expired row | `401 {"error":"unauthorized"}` | clear cookie | — |

Callback failures redirect to `/?auth=failed` (binding mismatch, ticket rejected, audience mismatch)
or `/?auth=unavailable` (gateway unreachable). The SPA shows the reason on the sign-in screen
(FR-001a).

## R7. Logout

`POST /api/auth/logout` requires the CSRF token and an allowed Origin (constitution: cookie-auth
mutations). It runs even when the gateway would reject the session. It calls gateway
`/auth/logout` with the stored handle, then always deletes the row and clears the cookie. The
response reports `{"status":"signed_out","platform":"revoked"|"unconfirmed"|"none"}` so the SPA can
warn when platform-wide revocation was not confirmed (spec edge case).

## R8. Probe route

`GET /api/auth/config` stays public and DB-free at the same path (frontend `startupProbe`,
`smoke-test.sh`). Its body changes to `{"login_url":"/api/auth/login"}`. No gateway call.

## R9. Expired session cleanup

Rows expire at `created_at + expires_in` (8 h from the gateway). Lookups ignore and delete expired
rows. A background ticker in `cmd/api` purges expired rows hourly.
