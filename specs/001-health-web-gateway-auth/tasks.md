---

description: "Tasks for 001 health-web sign-in through the platform gateway"
---

# Tasks: health-web Sign-In Through the Platform Gateway

**Input**: Design documents from `/specs/001-health-web-gateway-auth/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Required. Constitution VI requires negative tests for auth, tenancy, and migration work.

All paths are relative to `apps/health-web/` unless they start with `docs/`, `AGENTS.md`, or `specs/`.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [ ] T001 Confirm the baseline: `go vet ./... && go test ./...` pass in `api/` before changes

---

## Phase 2: Foundational (blocks every story)

- [ ] T002 Add `api/db/migrations/000002_platform_identity.up.sql` and `.down.sql` (`users`, `web_sessions`, per data-model.md)
- [ ] T003 [P] Rewrite `api/internal/config/config.go`: drop `CENTRAL_AUTH_URL`, `CENTRAL_AUTH_INTERNAL_URL`, `AUTH_SESSION_INTERNAL_TOKEN`. Add `GATEWAY_AUTH_URL`, `PUBLIC_AUTH_URL`, `PUBLIC_APP_URL` (fallback `APP_PUBLIC_URL`), `PROJECT_AUDIENCE`, `MIGRATE_ON_START`, and `GatewayBaseURL()` / `AppHost()` / `Audience()` helpers
- [ ] T004 [P] Create `api/internal/platformauth/gateway.go`: `Client` with `Exchange`, `Confirm`, `Revoke`, `ErrRejected`, `ErrUnavailable` (contracts/gateway-consumer.md)
- [ ] T005 [P] Create `api/internal/platformauth/gateway_test.go`: stub-gateway tests for every status row in contracts/gateway-consumer.md, including the `X-Forwarded-Host` and bearer headers
- [ ] T006 [P] Create `api/internal/store/users.go` (`EnsureUser`) and `api/internal/store/sessions.go` (`CreateWebSession`, `WebSession`, `UpdateWebSessionHandle`, `DeleteWebSession`, `PurgeExpiredWebSessions`) with sha256 token hashing
- [ ] T007 Create `api/internal/httpapi/auth_identity.go` (`AuthUser`, context helpers, `SessionStore` interface) and delete `api/internal/auth/central_client.go`
- [ ] T008 Update `api/cmd/api/main.go`: run migrations and seed when `MIGRATE_ON_START` (default true), exit non-zero on failure, wire `platformauth.Client`, start the hourly session purge, remove the central client and token warning

**Checkpoint**: The API compiles with the new dependencies. Auth routes come next.

---

## Phase 3: User Story 1 - Sign in and reach my data (P1) 🎯 MVP

**Goal**: An unsigned visitor sees the sign-in screen, signs in through the gateway, and lands back
signed in with working data APIs.

**Independent Test**: The quickstart browser steps 1–2. In tests: login redirect, then callback with
a stub ticket, then `/api/me` 200.

### Tests

- [ ] T009 [P] [US1] `api/internal/httpapi/auth_flow_test.go`: login redirect shape (`return` URL, `pa_bind`, nonce cookie attributes, `next` sanitising), callback success (user upsert, session cookie attributes, redirect to `next`), callback failures (no ticket, missing/mismatched binding without redeeming, exchange 401 → `failed`, exchange down → `unavailable`, foreign audience → `failed`)
- [ ] T010 [P] [US1] `api/internal/httpapi/handlers_session_test.go`: `/api/auth/config` stays public, DB-free, gateway-free, cookie-free, with body `{"login_url":"/api/auth/login"}`

### Implementation

- [ ] T011 [US1] Create `api/internal/httpapi/handlers_auth.go`: `authConfig`, `login`, `callback`, `me` (`{user_id}` only). Delete `handlers_session.go`
- [ ] T012 [US1] Rewrite `api/internal/httpapi/auth_middleware.go`: public allow-list (`/healthz`, `/readyz`, `GET /api/auth/config|login|callback`, `POST /api/auth/logout`), cookie → session row → gateway confirm → identity match → refresh handle → user in context, with the R6 failure mapping and structured log events
- [ ] T013 [US1] Update `api/internal/httpapi/router.go`: new routes, `Handler{cfg, store, sessions, gateway}`, remove `/api/logout`
- [ ] T014 [US1] Update `frontend/src/auth.js`: no automatic redirect. `loginURL()` → `/api/auth/login?next=<path>`. Show the gate with a reason from `?auth=` (`failed`/`unavailable`/`signed_out`), then clean the URL. 401 → gate "세션이 만료되었습니다". 503 → gate "로그인 서비스를 일시적으로 사용할 수 없습니다"
- [ ] T015 [US1] Update `frontend/src/api.js`: the 401 handler shows the gate (keeping form state) instead of redirecting
- [ ] T016 [US1] Update `frontend/public/index.html`: gate copy ("Google 계정으로 로그인 · nacfson 통합 계정"), button "Google로 계속", topbar without email

**Checkpoint**: US1 is fully testable on its own.

---

## Phase 4: User Story 3 - Each person sees only their own data (P1)

**Goal**: Forged identity, foreign sessions, and gateway outages never yield data. Users are
isolated.

**Independent Test**: In `go test`: forged headers → 401. Foreign audience → 401 and session
deleted. Gateway down → 503. Two sessions resolve to two different user ids. Identity mismatch → 401.

- [ ] T017 [P] [US3] `api/internal/httpapi/auth_middleware_test.go`: forged `X-User-*`/`Authorization` without cookie → 401 and no gateway call. Unknown cookie → 401 and cookie cleared. Expired row → 401. Gateway 401 → 401, row deleted, cookie cleared. Gateway 503 / network error → 503 `auth_unavailable`, row kept. Audience mismatch and subject mismatch → 401, row deleted. Refreshed handle stored. Two users get distinct `user_id` in context. Spoofed headers never reach handlers
- [ ] T018 [US3] Make sure `discardClientIdentityHeaders` also strips `X-User-Subject`, `X-User-Issuer`, `Authorization` in `api/internal/httpapi/auth_identity.go`

**Checkpoint**: US1 and US3 pass together.

---

## Phase 5: User Story 2 - Stay signed in, and leave cleanly (P2)

**Goal**: The session persists across reloads and tabs. Logout revokes the platform session and ends
health-web's session.

**Independent Test**: In `go test`: repeated requests with one cookie succeed. Logout → gateway
revoke called with the stored handle, row deleted, cookie cleared, `platform` outcome reported. CSRF
enforced.

- [ ] T019 [P] [US2] `api/internal/httpapi/logout_test.go`: CSRF/Origin required (403 otherwise). Revoked → `platform:"revoked"`. Gateway failure → `platform:"unconfirmed"` with row still deleted. No session → `platform:"none"`. Gateway rejecting the session does not block logout
- [ ] T020 [US2] Implement `logout` in `api/internal/httpapi/handlers_auth.go`. Export the CSRF check helper in `api/internal/httpapi/csrf.go`. Remove `clearCentralSessionCookie`
- [ ] T021 [US2] Update `frontend/src/auth.js` `logout()`: `POST /api/auth/logout`, then show the gate with "로그아웃되었습니다", or "로그아웃되었지만 다른 nacfson 서비스의 로그아웃은 확인되지 않았습니다" when `platform:"unconfirmed"`
- [ ] T022 [US2] Update the account card in `frontend/public/index.html`: no email row, "로그인 방식: Google (nacfson 통합 계정)", button "로그아웃 (모든 nacfson 서비스)". Update `showApp` in `frontend/src/auth.js` accordingly

**Checkpoint**: US1, US2, and US3 all pass.

---

## Phase 6: User Story 4 - The old sign-in system is gone (P3)

**Goal**: No trace of ProcessManager Auth outside history.

**Independent Test**: The quickstart §2 sweep returns nothing. The API starts with no retired env.

- [ ] T023 [US4] Update `api/internal/httpapi/json.go` and `api/internal/store/store.go` package comments. Remove retired references from `api/internal/httpapi/csrf.go` comments
- [ ] T024 [P] [US4] Rewrite `README.md` (Authentication, API table, Configuration, Local development)
- [ ] T025 [P] [US4] Update `AGENTS.md` (project summary web line, Task Routing health-web line, reference table rows for the new changelog and spec)
- [ ] T026 [P] [US4] Update `docs/features.md` (strike the ProcessManager SSO / K8s items, add gateway sign-in items) and mark `docs/changelog-health-web-mvp.md` auth/K8s lines superseded
- [ ] T027 [P] [US4] Create `docs/changelog-health-web-gateway-auth.md` (background, outage retrospective, DB 000002, UX changes) and add a health-web Postgres section to `docs/db-schema.md`
- [ ] T028 [US4] Run the quickstart §2 sweep and fix any remaining matches

---

## Phase 7: Polish & Cross-Cutting

- [ ] T029 `gofmt -l`, `go vet ./...`, `go test ./...` in `api/`
- [ ] T030 Run `frontend/smoke-test.sh` (needs docker). If docker is unavailable, record that
- [ ] T031 Run `node --check` on every changed SPA module
- [ ] T032 Live verification per quickstart §3 after merge and the `nacfson_pipeline` image pin bump (outside this branch)

---

## Dependencies & Execution Order

- Phase 2 blocks everything. T007 depends on T004 (types) and T006 (store API).
- US1 (Phase 3) is required before US3 and US2 tests can exercise the middleware end to end.
- US3 and US2 are independent of each other after US1.
- US4 docs can run in parallel with US2 and US3. T028 runs last.

## Parallel Example

```text
T003 config.go | T004 gateway.go | T005 gateway_test.go | T006 store/users.go + sessions.go
T009 auth_flow_test.go | T010 handlers_session_test.go
T024 README | T025 AGENTS.md | T026 features.md | T027 changelog + db-schema.md
```

## Implementation Strategy

MVP = Phases 1–3 (the outage is fixed). Phase 4 must ship in the same release: a sign-in fix
without the isolation tests is not releasable (spec US3 rationale). Phases 5–7 complete the feature.
Everything ships as one PR because the deploy unit is a single image pair.
