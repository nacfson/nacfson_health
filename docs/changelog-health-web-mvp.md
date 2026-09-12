# health-web MVP

Web product at `https://health.nacfson.cloud` (ProcessManager Option B). Lives in `apps/health-web/`; native Flutter SQLite + Supabase path unchanged. Sync bridge is out of MVP.

## Delivered

- Go API: cookie SSO (`nacfson_session`), CSRF `health_csrf`, Postgres user-owned tables (no `sync_status`), master seed from `master_exercise_seed_v12_6.json`
- Domain ports: Atwater, Mifflin-St Jeor nutrition targets, exercise volume kcal coefficients
- Vanilla SPA: web-native navy/mint shell (sidebar + History routes), five domains with CRUD; no phone bezel
- K8s: `ProcessManager/k8s/health/` + restored spec §9 phases P0–P4

## Web-native UI rebuild

One-shot frontend-only ship (API/auth/schema untouched):

- Dropped `--shell-max` / `.phone` / notch / bottom tab chrome
- Added `.app-shell` sidebar (brand, nav, user chip, logout), sticky date bar, desktop type scale
- Routes: `/` · `/summary` (home), `/workout`, `/diet`, `/weight`, `/settings` via `src/router.js`
- Domain layouts: summary dashboard grid; workout/diet two-column; wider weight chart; grouped settings
- Responsive ≤800px: sidebar drawer (not a phone mockup)
- Date prev/next/today refreshes the active tab

## Ops

Live origin uses GHCR arm64 images on Oracle k3s (`health` namespace). See `apps/health-web/README.md`.
