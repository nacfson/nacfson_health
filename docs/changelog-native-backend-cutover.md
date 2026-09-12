# health-web changelog — native backend cutover

## Native → owned backend (2026-09-12)

### Background

iOS/Android leave Supabase Auth + PostgREST. Cloud sync and auth now use the same
ProcessManager Auth + health-web Go/Postgres stack as the SPA. Local SQLite stays
offline-first; only the remote adapter changes. Cloud data starts empty (no Supabase
migration). Gemini and Apple Health / Health Connect stay in the UI but are gated.

### API (`apps/health-web/api`)

- Bearer auth: `Authorization: Bearer <opaque>` → Auth `GET /api/auth/session`. Cookie SSO
  and CSRF remain for the SPA; Bearer skips CSRF. Client `X-User-*` still discarded.
- Sync: `POST/GET /api/v1/sync/{resource}` for
  `exercise_records|diet_records|weight_records|exercise_templates|food_templates|workout_routines`.
  Push is uuid upsert; pull is `is_deleted=false` + optional `updated_at > since`.
- Master: `GET /api/v1/master/bundle` returns categories, translations, definitions,
  formulas for native SQLite replace.
- Migration `000002_sync_cursors` preserves client `updated_at` on sync upserts and adds
  `(user_id, updated_at)` indexes. No Supabase secrets in health-api k8s.

### Flutter (`lib/`)

- `HealthAuthService` + `HealthApiClient` + `HealthSyncService` replace
  `supabase_flutter` / `GoogleAuthService` / `SupabaseService`.
- Deep link: `nacfsonhealth://login-callback?token=…` (Auth must allow-list this URL and
  append the session token for custom-scheme redirects — see ProcessManager PR).
- dart-defines: `HEALTH_API_BASE_URL`, `CENTRAL_AUTH_URL`, `AUTH_REDIRECT_URL` (defaults
  to production hosts). `SUPABASE_*` / `GEMINI_API_KEY` removed from release configs.
- Gates: `GeminiService` soft-unavailable; `GatedHealthDataSource` for activity.

### Ops

- Shut down Supabase project usage for this app after shipping the store build.
- Apply health-web migration `000002` before native clients hit sync.
- Ensure Auth `AUTH_ALLOWED_REDIRECTS` includes `nacfsonhealth://login-callback`.
