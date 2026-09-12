# health-web

Web product for nacfson_health, served at `https://health.nacfson.cloud`: a mobile-first Korean
SPA (`운동 · 식단 · 체중 · 요약 · 설정`) backed by a Go API and Postgres.

The native Flutter app (`lib/`, `ios/`, `android/`) uses the same Postgres via Bearer
auth and the sync bridge (`POST/GET /api/v1/sync/{resource}`). SQLite remains offline-first.

```
apps/health-web/
  api/        Go module github.com/nacfson/nacfson_health/apps/health-web/api
    cmd/api     HTTP server
    cmd/migrate schema migrations + master-data seed
    internal/   config, auth, store, httpapi, domain, migrations, seed
    db/         migrations/*.sql and master_exercise_seed_v12_6.json
  frontend/   static SPA (nginx image)
```

## Authentication

Dual auth on health-api:

1. **SPA (cookie SSO):** browser holds `nacfson_session` →
   `GET {CENTRAL_AUTH_INTERNAL_URL}/api/internal/cookie-session` with
   `Authorization: Bearer {AUTH_SESSION_INTERNAL_TOKEN}`. Mutations need `health_csrf` +
   allow-listed `Origin`.
2. **Native (Bearer):** `Authorization: Bearer <opaque session>` → Auth
   `GET /api/auth/session`. CSRF is skipped for Bearer. Logout uses
   `DELETE /api/auth/session` with the same Bearer.

There is no local users table. The returned Auth `user_id` is the tenant key for every
SQL statement. Missing or invalid credentials → `401 {"error":"unauthorized"}`. Public
exceptions: `GET /healthz`, `GET /readyz`.

`X-User-Id` / `X-User-Email` / `X-User-Roles` request headers are always discarded.

No Supabase secrets are used by health-api.

## API

| Method | Path | Notes |
|---|---|---|
| GET | `/healthz` | liveness, no auth |
| GET | `/readyz` | DB ping, no auth |
| GET | `/api/me` | `{user_id,email}`, issues `health_csrf` |
| POST | `/api/logout` | revokes the cookie session via Auth |
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
| GET | `/api/v1/master/exercises?locale=ko` | categories + definitions (SPA picker) |
| GET | `/api/v1/master/bundle` | full native master dump (+ formulas) |
| POST / GET | `/api/v1/sync/{resource}` | native push upsert / pull delta (`since`) |
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
| `APP_PUBLIC_URL` | `https://health.nacfson.cloud` | public origin |
| `DATABASE_URL` | — (required) | Postgres URL for the `health` database |
| `MIGRATIONS_PATH` | `file://db/migrations` | golang-migrate source |
| `SEED_PATH` | `db/master_exercise_seed_v12_6.json` | master catalog JSON |
| `CENTRAL_AUTH_URL` | `https://auth.nacfson.cloud` | browser-facing Auth origin |
| `CENTRAL_AUTH_INTERNAL_URL` | falls back to `CENTRAL_AUTH_URL` | in-cluster Auth base URL |
| `AUTH_SESSION_INTERNAL_TOKEN` | — | shared verifier token for the Auth internal API |
| `ALLOWED_ORIGINS` | `https://health.nacfson.cloud,http://localhost:8080,http://127.0.0.1:8080` | CSRF/CORS allow-list |
| `TZ` | `Asia/Seoul` | calendar timezone for date filters |

`AUTH_SESSION_INTERNAL_TOKEN` must never reach the frontend bundle or nginx configmaps.

## Local development

```bash
# 1. schema + master data (idempotent)
cd apps/health-web/api
DATABASE_URL='postgres://localhost:5432/health?sslmode=disable' go run ./cmd/migrate up
DATABASE_URL='postgres://localhost:5432/health?sslmode=disable' go run ./cmd/migrate seed

# 2. api
DATABASE_URL='postgres://localhost:5432/health?sslmode=disable' \
AUTH_SESSION_INTERNAL_TOKEN='<dev verifier token>' \
CENTRAL_AUTH_INTERNAL_URL='https://auth.nacfson.cloud' \
go run ./cmd/api

# 3. tests
go test ./...
```

`migrate` also accepts `down --steps N` and `version`.

## Container

`api/Dockerfile` builds one image containing both binaries plus `db/`:

```bash
docker build -t 192.168.219.100:5000/health-api:latest apps/health-web/api
```

`WORKDIR` is `/app` (`./api`, `./migrate`, `db/migrations`, `db/master_exercise_seed_v12_6.json`), so
the migrate Job only needs `DATABASE_URL` and can run `./migrate up` followed by `./migrate seed`.
The image runs as UID 65532.
