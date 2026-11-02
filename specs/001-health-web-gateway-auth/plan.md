# Implementation Plan: health-web Sign-In Through the Platform Gateway

**Branch**: `001-health-web-gateway-auth` | **Date**: 2026-11-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-health-web-gateway-auth/spec.md`

## Summary

Replace health-web's retired ProcessManager cookie SSO with the cluster's platform gateway
(`signIn: shared`). The Go API becomes a small backend-for-frontend:

- `/api/auth/login` sends the browser to the gateway's `/oauth/start`.
- `/api/auth/callback` redeems the one-time ticket in-cluster, upserts a project account keyed by
  `(issuer, subject)`, and sets a small host-only `__Host-health_session` cookie. The gateway's
  session handle stays in Postgres.
- Every `/api/*` request is confirmed against the gateway's `/auth` (fail closed).
- Logout revokes the platform session.

The SPA stops redirecting automatically, shows a sign-in screen with reasons, and drops the email
UI. The API also starts running its schema migrations and seed on boot, as the platform database
contract requires (research R5).

## Technical Context

**Language/Version**: Go 1.22 (API), vanilla ES modules (SPA)

**Primary Dependencies**: Go stdlib `net/http`, `pgx/v5`, `golang-migrate/v4`, `google/uuid`
(all existing; no new modules)

**Storage**: Postgres `proj_health` via `vault-db-proxy`. New tables `users`, `web_sessions`

**Testing**: `go test` with an `httptest` gateway stub and an in-memory session store;
`frontend/smoke-test.sh`

**Target Platform**: k3s on a VPS (`proj-health`), images from GHCR, amd64 + arm64

**Project Type**: Web service + static SPA inside a mixed repo (Flutter app untouched)

**Performance Goals**: Auth adds one DB lookup and one in-cluster gateway call per API request
(well under 50 ms p95 in-cluster). Single-user-scale traffic

**Constraints**: Cookie ≤ 100 bytes. No secrets in the image or SPA. The probe path is unchanged.
No `nacfson_pipeline` change beyond the image pin

**Scale/Scope**: One backend replica, a handful of users

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|---|---|---|
| I. Two products, separate runtimes | Pass | Only `apps/health-web/**` and docs change. `lib/` untouched |
| II. Layered data flow | Pass | Handlers → `store` (`users.go`, `sessions.go`). SPA talks only to `/api/*` |
| III. Platform identity via gateway | Pass | `/oauth/start` sign-in, backend-only confirmation, `(issuer, subject)`, audience check, fail-closed mapping (R6), header stripping, retired system removed |
| IV. Visible, classified failures | Pass | `?auth=` reasons on the gate, `auth_unavailable` 503, logout `platform` outcome, structured logs |
| V. Additive, applied migrations | Pass | `000002` up/down, additive only. Applied on startup per CONTRACT_DATABASE (R5). Docs updated |
| VI. Tested behaviour | Pass | Negative tests: missing session, forged headers, foreign audience, gateway down, cross-user, binding mismatch |
| VII. Docs move with code | Pass | README, AGENTS.md, features.md, db-schema.md, new changelog |
| Constraints: cookies | Pass | `__Host-` prefix, HttpOnly, Secure, Lax. CSRF kept for mutations including logout |
| Constraints: probe | Pass | `GET /api/auth/config` path unchanged, DB-free and gateway-free |
| Pipeline precedence | Deviation recorded | The pipeline's projectauth SDK keeps the handle in the browser. See Complexity Tracking |

Post-design re-check: no new violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-health-web-gateway-auth/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── health-web-auth-api.md
│   └── gateway-consumer.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
apps/health-web/
├── api/
│   ├── cmd/api/main.go                    # migrate+seed on start, wire gateway client + session purge
│   ├── db/migrations/000002_platform_identity.{up,down}.sql   # NEW
│   └── internal/
│       ├── auth/central_client.go          # DELETE
│       ├── platformauth/gateway.go         # NEW: Exchange / Confirm / Revoke
│       ├── platformauth/gateway_test.go    # NEW
│       ├── config/config.go                # retire CENTRAL_*/AUTH_SESSION_INTERNAL_TOKEN; add gateway/public URLs
│       ├── store/users.go, sessions.go     # NEW
│       └── httpapi/
│           ├── auth_identity.go            # NEW: AuthUser + context helpers (moved from auth pkg)
│           ├── auth_middleware.go          # rewrite: cookie → session row → gateway confirm
│           ├── handlers_auth.go            # NEW: login / callback / logout / config / me
│           ├── handlers_session.go         # DELETE (folded into handlers_auth.go)
│           ├── csrf.go                     # drop central cookie clearing; export check for logout
│           ├── router.go                   # routes + SessionStore interface
│           └── *_test.go                   # rewrite around gateway stub + fake session store
└── frontend/
    ├── public/index.html                   # gate copy, account card, logout label
    └── src/auth.js, api.js                 # no auto-redirect, reasons, new logout
```

**Structure Decision**: Keep the existing `apps/health-web/{api,frontend}` layout. The new
`internal/platformauth` package is the only gateway-aware code. `httpapi` depends on it and on a
narrow `SessionStore` interface so tests run without Postgres.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Server-side `web_sessions` table instead of the pipeline's browser-held bearer handle (projectauth / spec 009) | `strip-forged-headers` blanks `Authorization` at the edge, the handle is about 3–4 KB, and FR-012 forbids script-readable credentials | Bearer in JS: stripped at the edge and exposed to XSS. Handle-in-cookie: at the 4 KB browser limit, so it would fail silently |
| API runs migrations at startup | CONTRACT_DATABASE §6 requires it and nothing else applies them | Pipeline migrate Job: would break SC-007 (image-only rollout) and duplicate the contract |
