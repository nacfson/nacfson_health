# health-web

Web product for nacfson_health, served at `https://health.nacfson.cloud`: a mobile-first Korean
SPA (`운동 · 식단 · 체중 · 요약 · 설정`) backed by a Go API and Postgres.

The native Flutter app (`lib/`, `ios/`, `android/`) is untouched by this app and keeps using its own
SQLite + Supabase stack. There is no sync bridge yet.

```
apps/health-web/
  api/        Go module github.com/nacfson/nacfson_health/apps/health-web/api
    cmd/api     HTTP server (applies migrations + seed on start; service.name=health-api)
    cmd/migrate manual migrate up/down/version/seed (service.name=health-migrate)
    internal/   config, logx (Log Contract v3 slog + W3C traceparent), platformauth (gateway client), store, httpapi, domain, migrations, seed
    db/         migrations/*.sql and master_exercise_seed_v12_6.json
  frontend/   static SPA (nginx image; service.name=health-web)
```

## Authentication

health-web is a `signIn: shared` project of the nacfson_pipeline platform
(`contracts/CONTRACT_AUTH_DOOR.md`). Accounts belong to the platform (Keycloak behind the
`identity/gateway` service, Google sign-in). The API is a small backend-for-frontend around it. Spec,
decisions, and contracts: `specs/001-health-web-gateway-auth/`.

1. The SPA shows its sign-in screen. **Google로 계속** opens `GET /api/auth/login?next=/path`.
2. The API sets `__Host-health_login=<nonce>` and redirects to
   `https://auth.nacfson.cloud/oauth/start?return=https://health.nacfson.cloud/api/auth/callback?pa_bind=<sha256(nonce)>`.
3. After Google sign-in the gateway redirects to `/api/auth/callback?…&ticket=<one-time>`. The API
   checks the nonce binding and redeems the ticket in-cluster (`POST {gateway}/auth/exchange`). It
   requires audience `project-health`, upserts `users(issuer, subject)`, stores the gateway session
   handle in `web_sessions`, and sets `__Host-health_session` (random 32-byte token, HttpOnly,
   Secure, SameSite=Lax, host-only). Failures land on `/?auth=failed|unavailable`.
4. Every other `/api/*` request: cookie → `web_sessions` row → `GET {gateway}/auth` with the stored
   handle. Audience and `(issuer, subject)` must match. A refreshed handle is stored. A rejected or
   mismatched session is deleted (`401 {"error":"unauthorized"}`). An unreachable gateway is
   `503 {"error":"auth_unavailable"}`, so nothing is served without a confirmed identity.
5. `POST /api/auth/logout` revokes the platform session (`POST {gateway}/auth/logout`), which signs
   the browser out of every nacfson service, and always deletes the local session.

Public routes: `GET /healthz`, `GET /readyz`, `GET /api/auth/config|login|callback`, and
`POST /api/auth/logout` (which checks CSRF itself). Email is never stored, returned, or used as an
identifier.

Mutations (including logout) require a CSRF token: the `health_csrf` cookie (readable, host-only,
`SameSite=Lax`, `Path=/`, `Secure` behind TLS) must match the `X-CSRF-Token` header, and `Origin`
must be listed in `ALLOWED_ORIGINS`. The cookie is issued on any authenticated request.

Client-supplied `X-User-*`, `X-Project-Audience`, and `Authorization` request headers are always
discarded.

## API

| Method | Path | Notes |
|---|---|---|
| GET | `/healthz` | liveness, no auth |
| GET | `/readyz` | DB ping, no auth |
| GET | `/api/auth/config` | `{"login_url":"/api/auth/login"}`. No auth, no DB, no gateway call. Frontend `startupProbe` target in nacfson_pipeline |
| GET | `/api/auth/login` | `?next=<same-site path>` → `302` to the gateway's `/oauth/start` |
| GET | `/api/auth/callback` | gateway return. Redeems the ticket, sets the session, `302` to `next` or `/?auth=…` |
| POST | `/api/auth/logout` | platform-wide sign-out. `{"status":"signed_out","platform":"revoked\|unconfirmed\|none"}` |
| GET | `/api/me` | `{user_id}`, issues `health_csrf` |
| GET / PUT | `/api/v1/profile` | upsert profile; `GET` returns `exists:false` + defaults when unset |
| POST | `/api/v1/profile/recalculate-targets` | body `{"weight":<kg optional>}`; persists daily targets |
| GET / POST | `/api/v1/exercise` | list `?date=` or `?from=&to=`; create |
| PATCH / DELETE | `/api/v1/exercise/{uuid}` | update / soft delete |
| GET / POST | `/api/v1/diet` | same filters; calories derived from macros |
| PATCH / DELETE | `/api/v1/diet/{uuid}` | calories recomputed from the merged macros |
| GET / POST | `/api/v1/weight` | same filters |
| PATCH / DELETE | `/api/v1/weight/{uuid}` | |
| GET / POST | `/api/v1/exercise-templates` | PATCH / DELETE `/{uuid}` |
| GET / POST / DELETE | `/api/v1/food-templates` | `DELETE /{uuid}`; no PATCH (Flutter parity) |
| GET / POST | `/api/v1/workout-routines` | PATCH / DELETE `/{uuid}` |
| GET / PUT | `/api/v1/daily-routine/{date}` | planner day, `YYYY-MM-DD` |
| GET | `/api/v1/master/exercises?locale=ko` | categories + 257 definitions with translations |
| GET | `/api/v1/summary?date=` | daily dashboard DTO |

Conventions:

- Lists return bare JSON arrays; create returns `201` + the stored row; PATCH returns the updated row;
  DELETE returns `204`. Timestamps are RFC3339 UTC; dates are Asia/Seoul calendar days.
- Errors are `{"error":"<code>","message":"..."}` with codes `invalid_request`, `not_found`,
  `conflict`, `csrf_failed`, `unauthorized`, `unavailable`, `auth_unavailable`, `internal`.
  `401` is exactly `{"error":"unauthorized"}`.
- Diet and food-template calories are always computed server-side with Atwater coefficients
  (`round(carbs*4 + protein*4 + fat*9)`, non-finite/negative → `0`); any client-supplied calorie value
  is ignored.
- Logging an exercise set self-heals the day's routine: if the exercise name is missing from
  `daily_routine.items_json` for that local date, it is appended.
- Deleting records is a soft delete (`is_deleted = true`); lists, summaries and master reads filter
  deleted rows out.

## Configuration

| Env | Default | Purpose |
|---|---|---|
| `APP_ADDR` | `:8080` | listen address |
| `PUBLIC_APP_URL` | `https://health.nacfson.cloud` | public origin (`APP_PUBLIC_URL` accepted as a fallback). Its first host label derives the audience |
| `DATABASE_URL` | — (required) | Postgres URL for the `health` database |
| `MIGRATIONS_PATH` | `file://db/migrations` | golang-migrate source |
| `MIGRATE_ON_START` | `true` | apply migrations and the idempotent master seed before serving (nacfson_pipeline CONTRACT_DATABASE §6). Startup fails if either fails |
| `SEED_PATH` | `db/master_exercise_seed_v12_6.json` | master catalog JSON |
| `GATEWAY_AUTH_URL` | `http://gateway.identity.svc:8080/auth` | in-cluster gateway verify URL. `/auth/exchange` and `/auth/logout` are derived from it |
| `PUBLIC_AUTH_URL` | `https://auth.nacfson.cloud` | browser-facing sign-in origin (`/oauth/start`) |
| `PROJECT_AUDIENCE` | `project-` + host label (`project-health`) | gateway audience this API accepts |
| `ALLOWED_ORIGINS` | `https://health.nacfson.cloud,http://localhost:8080,http://127.0.0.1:8080` | CSRF/CORS allow-list |
| `TZ` | `Asia/Seoul` | calendar timezone for date filters |

No shared secret is needed: the gateway is reached only over the cluster network, and the platform
NetworkPolicy allows `proj-health` egress to `identity/gateway:8080`.

## Local development

```bash
cd apps/health-web/api

# api (applies migrations + seed on start)
DATABASE_URL='postgres://localhost:5432/health?sslmode=disable' go run ./cmd/api

# tests (gateway and session store are faked; no Postgres needed)
go vet ./... && go test ./...
```

Signing in needs the in-cluster gateway, so an end-to-end sign-in is only possible on the cluster.
Locally, the API serves the public routes, and every authenticated route answers
`503 auth_unavailable` (or `401` without a cookie). Schema-only work can still use
`go run ./cmd/migrate up|down --steps N|version|seed`.

## Container

`api/Dockerfile` builds one image containing both binaries plus `db/`:

```bash
docker build -t ghcr.io/nacfson/health-backend:dev apps/health-web/api
```

`WORKDIR` is `/app` (`./api`, `./migrate`, `db/migrations`, `db/master_exercise_seed_v12_6.json`).
`./api` applies `db/migrations` and the seed itself on start (`MIGRATE_ON_START`), so the deployment
needs no migrate Job. `./migrate` stays for manual `down` / `version`. The image runs as UID 65532. The Go build stage runs on the builder's native platform and
cross-compiles for the target (`TARGETOS`/`TARGETARCH`), so arm64 builds skip QEMU for compilation.

## Published images (CI)

`.github/workflows/publish-ghcr-images.yml` publishes both images on every push to `main` that touches
`apps/health-web/**` (or the workflow itself):

| Image | Context | Port |
|---|---|---|
| `ghcr.io/nacfson/health-backend` | `apps/health-web/api` | 8080 |
| `ghcr.io/nacfson/health-frontend` | `apps/health-web/frontend` | 8080 |

- Platforms: `linux/amd64` + `linux/arm64` (one OCI index per tag).
- Tags: 7-char commit SHA, `vX.Y.Z` on tag builds, plus `latest` on `main`.
- Labels: `org.opencontainers.image.source` (this repo), `org.opencontainers.image.revision`
  (full commit SHA), and `org.opencontainers.image.version` (`vX.Y.Z` on tag builds, or
  `v0.0.0-<7-char-sha>` on untagged builds — never `latest`), matching `service.version` injected via
  `--build-arg SERVICE_VERSION` (`-ldflags "-X main.version=..."` in Go, `nginx.conf` substitution in
  frontend).
- `go vet` + `go test` for the API, `frontend/smoke-test.sh`, and the `log-contract` job gate both
  builds:
  - The SPA smoke test runs the SPA image the way the pipeline pod does (UID 10001, read-only rootfs,
    all capabilities dropped, writable `/tmp` · `/var/cache/nginx` · `/var/log/nginx`) against a stub
    `health-backend`. It checks `/`, `/healthz` and `/api/auth/config` on 8080 (the liveness, readiness
    and startup probe paths).
  - The `log-contract` job validates `health-migrate`, `health-api`, and `health-web` logs (both normal
    and handled error paths) against `nacfson_pipeline` `CONTRACT_LOG_SCHEMA.md` v3 using
    `ghcr.io/nacfson/logcheck`.
- Pull requests (and manual runs from other branches) build both images without logging in or
  pushing.
- After pushing, the run re-reads the published index and fails if a platform, label, or port is
  wrong. The run's step summary prints the `ghcr.io/nacfson/health-<role>@sha256:…` pin.

Deployment pins live in `nacfson_pipeline` (`deploy/projects/health/workloads/*.yaml`). Update them
with that repo's `update-project-images` skill, e.g. `proj-health backend image: <Actions run URL>`.
The publish job names (`Publish backend image` / `Publish frontend image`) carry the role word that
skill matches on, so keep them.

If the first push fails with `denied: permission_denied: write_package`, the package was created
outside Actions: open the package on GitHub → Package settings → Manage Actions access → add
`nacfson/nacfson_health` with **Write**, then re-run the failed jobs.
