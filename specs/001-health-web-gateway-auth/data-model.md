# Data Model: health-web Sign-In Through the Platform Gateway

Migration: `apps/health-web/api/db/migrations/000002_platform_identity.{up,down}.sql`

## users (health-web project account)

| Column | Type | Rules |
|---|---|---|
| `id` | `UUID` PK | Generated in Go (`uuid.New()`). Tenant key used by every user-owned table's `user_id` |
| `issuer` | `TEXT NOT NULL` | Platform issuer (e.g. `https://auth.nacfson.cloud/realms/platform`) |
| `subject` | `TEXT NOT NULL` | Keycloak subject |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | First confirmed sign-in |
| `last_seen_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Updated on each successful callback |

- `UNIQUE (issuer, subject)`: exactly one project account per platform identity (FR-005, FR-006).
- No email, name, or credential columns.
- Created only by the callback's upsert:
  `INSERT … ON CONFLICT (issuer, subject) DO UPDATE SET last_seen_at = now() RETURNING id`.

## web_sessions (browser session)

| Column | Type | Rules |
|---|---|---|
| `id_hash` | `BYTEA` PK | `sha256(cookie token)`. The raw token (32 random bytes, base64url) exists only in the browser cookie |
| `user_id` | `UUID NOT NULL` → `users(id) ON DELETE CASCADE` | Owner |
| `issuer` | `TEXT NOT NULL` | Copied from the exchange. Every gateway confirmation MUST return the same value |
| `subject` | `TEXT NOT NULL` | Same rule |
| `session_handle` | `TEXT NOT NULL` | Opaque gateway handle. Replaced when the gateway returns `X-Refreshed-Session-Handle`. Never logged or returned to clients |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | |
| `expires_at` | `TIMESTAMPTZ NOT NULL` | `created_at + expires_in` from `/auth/exchange` (8 h) |

- Index on `expires_at` for the hourly purge.
- State transitions: **created** (callback) → **refreshed** (handle replaced, any number of times) →
  **deleted** (logout, gateway `401`, identity mismatch, expiry).

## Existing user-owned tables

`user_profiles`, `exercise_records`, `diet_records`, `weight_records`, `exercise_templates`,
`food_templates`, `workout_routines`, `daily_routine` keep `user_id UUID NOT NULL` and every query
keeps its `WHERE user_id = $1` scope (FR-008). This feature adds no foreign keys to them, because
000001 has no FKs and adding them is not needed for isolation.

## Cookies (browser)

| Name | Value | Attributes | Lifetime |
|---|---|---|---|
| `__Host-health_session` | session token (43 chars) | `Path=/`, `Secure`, `HttpOnly`, `SameSite=Lax`, host-only | `Max-Age = expires_in` |
| `__Host-health_login` | login nonce (32 hex chars) | same | 10 min, cleared at callback |
| `health_csrf` | CSRF token (unchanged) | `Path=/`, `Secure` behind TLS, readable, `SameSite=Lax` | 24 h |

Retired: `nacfson_session` (FR-018).
