# nacfson_health Constitution

## Core Principles

### I. Two Products, One Domain, Separate Runtimes

The repository ships two products that MUST stay independently buildable and deployable:

- **Native app** (`lib/`, `ios/`, `android/`, `macos/`, ...): Flutter, Riverpod, go_router, sqflite,
  Supabase.
- **health-web** (`apps/health-web/`): Go API, vanilla SPA, and Postgres at
  `https://health.nacfson.cloud`, deployed by `nacfson_pipeline`.

A change to one product MUST NOT require a change to the other's code. The two products share
domain rules, not code or storage. Domain rules that both products implement (Atwater 4/4/9
calories, exercise volume `weight × reps`, Asia/Seoul calendar days, the master exercise seed, 1RM
formulas) MUST produce the same results in both. A change to a shared rule MUST update both
implementations, or record the gap in `docs/features.md`.

*Rationale:* The products have different storage, auth, and release paths. Coupling them would make
every web deploy wait on an app release and the reverse.

### II. Layered Data Flow

- **Native:** UI → Provider (StateNotifier) → Repository interface → SQLite implementation ↔
  SupabaseService. Widgets MUST NOT call SQLite, Supabase, or `SharedPreferences` directly.
- **health-web:** SPA → `/api/*` → `httpapi` handlers → `store`. Handlers MUST NOT build SQL.
  The SPA MUST NOT talk to Postgres, the auth gateway, or any third-party API directly.

New domains and tables MUST follow `docs/implementation-guide.md`.

*Rationale:* One way through each stack keeps sync, tenancy, and error handling in one place.

### III. Platform Identity Through the Cluster Gateway (health-web)

health-web is a `signIn: shared` project in `nacfson_pipeline` and MUST follow that repository's
`contracts/CONTRACT_AUTH_DOOR.md`:

- Browser sign-in MUST start at the platform gateway (`/oauth/start`). Sessions MUST be confirmed
  only by the backend, over the cluster network, against `GATEWAY_AUTH_URL`
  (`http://gateway.identity.svc:8080`).
- Identity MUST be the `(issuer, subject)` pair. Email MUST NOT key, look up, or link user data.
- The backend MUST verify the `project-health` audience. It MUST reject a missing, forged, expired,
  or foreign identity.
- Session checks MUST fail closed. If the gateway rejects a session or cannot be reached, protected
  endpoints answer `401` or `503` and never serve data.
- Client-supplied identity headers (`X-User-*`, forged `Authorization`) MUST be discarded before
  authentication.
- Every SQL statement on user-owned data MUST be scoped by the authenticated user's id.
- Legacy ProcessManager Auth (`nacfson_session`, `/api/internal/cookie-session`,
  `AUTH_SESSION_INTERNAL_TOKEN`, `auth.nacfson.cloud/login`) is retired and MUST NOT be
  reintroduced.

The native app keeps Supabase Auth. It MUST NOT depend on the cluster gateway.

*Rationale:* Running against an auth service the cluster no longer runs left health-web
unreachable (a `404` loop through `auth.nacfson.cloud/login`). Identity belongs to the platform. The
project only confirms it.

### IV. Visible, Classified Failures

Every DB write, sync, network call, and form submit MUST handle failure and show the user something
(`docs/error-handling.md`). Empty `catch` blocks are allowed only for the two documented patterns,
each with a one-line reason. Logging alone MUST NOT replace user feedback. health-web errors MUST use
the documented `{"error","message"}` codes. A `401` body MUST be exactly `{"error":"unauthorized"}`.

*Rationale:* Silent failures are what cost the most debugging time in this project.

### V. Additive, Fully Applied Migrations

- SQLite migrations MUST be idempotent and bump the DB version.
- Supabase migrations MUST be applied to the remote DB in the same unit of work that adds them.
- health-web migrations (`apps/health-web/api/db/migrations`) MUST ship as up/down pairs and MUST NOT
  drop user data without a written data plan in the feature spec.

Every migration MUST update the documents listed under "마이그레이션" in `AGENTS.md`.

*Rationale:* Half-applied migrations caused the v11 incident (`docs/changelog-v11.md`).

### VI. Tested Behaviour Before Merge

- New or changed behaviour MUST come with automated tests that fail without the change.
- Auth, tenancy, and migration changes MUST include negative tests: missing session, forged headers,
  foreign audience, gateway down, and cross-user access.
- health-web MUST pass `go vet ./...`, `go test ./...`, and `frontend/smoke-test.sh`.
- The native app MUST pass `flutter analyze` and `flutter test`.

External services (the gateway, Supabase) MUST be replaced by stubs in tests. Tests MUST NOT call
production endpoints.

### VII. Docs Move With Code

A change is incomplete until the documents it affects are updated in the same change:
`AGENTS.md` (summary and reference table), `docs/features.md`, `docs/db-schema.md`, a changelog
for the version, and `apps/health-web/README.md` for health-web. When a mistake teaches a rule,
that rule MUST be added to the relevant `docs/` guide.

*Rationale:* Agents and the maintainer work from these documents. Stale docs (for example health-web
still describing ProcessManager SSO) send work in the wrong direction.

## Technology & Security Constraints

- **Native stack:** Flutter/Dart, Riverpod StateNotifier, go_router ShellRoute, sqflite,
  supabase_flutter, fl_chart, Material 3, Pretendard. Theme colours MUST come from
  `Theme.of(context).colorScheme` or the `AppTheme` helpers (`docs/conventions.md`).
- **health-web stack:** Go 1.22+ on the standard library plus the existing modules (`pgx`,
  `golang-migrate`, `google/uuid`). A new Go module needs a justification in the feature plan. The SPA
  stays vanilla ES modules with no build step and no npm runtime dependencies.
- **Secrets:** No secret may be committed or baked into an image or frontend bundle. Native builds
  use `--dart-define`. health-web backend credentials come from the platform (vault proxies,
  in-cluster gateway). The backend MUST NOT need a shared auth token to confirm sessions.
- **Cookies (health-web):** Session cookies MUST be host-only (`__Host-` prefix), `HttpOnly`,
  `Secure`, and `SameSite=Lax`. Cookie-authenticated mutations MUST require the CSRF token and an
  allow-listed `Origin`.
- **Images and deployment:** health-web images are multi-arch (amd64 and arm64) and published to
  GHCR by `.github/workflows/publish-ghcr-images.yml`. Deployment, routes, probes, and network
  policy live in `nacfson_pipeline`, which pins images by digest. This repository MUST NOT carry
  Kubernetes manifests for health-web.
- **Probes:** The public, DB-free `GET /api/auth/config` remains the frontend startup probe
  target. Changing its path or making it depend on the DB or the gateway requires a coordinated
  `nacfson_pipeline` change.

## Development Workflow & Quality Gates

- Features that touch auth, tenancy, schema, or cross-repository contracts MUST go through Spec Kit:
  `/speckit.specify` → `/speckit.clarify` → `/speckit.plan` → `/speckit.tasks` →
  `/speckit.implement`. Specs live in `specs/NNN-<slug>/`.
- Before coding, read the `AGENTS.md` Task Routing document for the area being changed.
- Work happens on a branch and reaches `main` through a pull request. CI MUST be green before merge.
- A health-web change is not complete until it has been verified on the live site after the
  `nacfson_pipeline` image pin is bumped. Verification uses the browser-shaped checks in the
  feature's quickstart, not pod readiness alone.

## Governance

- **Precedence:** This constitution overrides other practice documents in this repository. Where
  health-web meets the platform, `nacfson_pipeline`'s constitution and contracts take precedence,
  and this document MUST NOT contradict them.
- **Amendments:** An amendment requires a written rationale, an impact note covering the native
  app, health-web, and the pipeline, a semantic version bump, and maintainer approval in the pull
  request that changes this file.
- **Versioning:** MAJOR for removing or redefining a principle. MINOR for a new principle or
  section, or materially expanded guidance. PATCH for wording and clarifications.
- **Compliance:** Every plan MUST pass the Constitution Check in `plan-template.md`. Every pull
  request review MUST confirm compliance. A deviation MUST be recorded with its justification in the
  plan's Complexity Tracking table.
- **Runtime guidance:** `AGENTS.md` and `docs/` hold the detailed rules this constitution points to.

**Version**: 1.0.0 | **Ratified**: 2026-11-02 | **Last Amended**: 2026-11-02
