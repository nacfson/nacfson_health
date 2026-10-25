# health-web MVP

Web product at `https://health.nacfson.cloud` (ProcessManager Option B). Lives in `apps/health-web/`; native Flutter SQLite + Supabase path unchanged. Sync bridge is out of MVP.

## Delivered

- Go API: cookie SSO (`nacfson_session`), CSRF `health_csrf`, Postgres user-owned tables (no `sync_status`), master seed from `master_exercise_seed_v12_6.json`
- Domain ports: Atwater, Mifflin-St Jeor nutrition targets, exercise volume kcal coefficients
- Vanilla SPA: mockup v2 navy/mint, five tabs with CRUD
- K8s: `ProcessManager/k8s/health/` + restored spec §9 phases P0–P4

## Ops remaining (cluster unreachable from implement workstation)

1. ~~Push `health-api` / `health-frontend` to `192.168.219.100:5000`~~ → GHCR publish automated (`.github/workflows/publish-ghcr-images.yml`, 2026-10-25): `ghcr.io/nacfson/health-{backend,frontend}`; pin digests in `nacfson_pipeline`
2. Provision DB `health` on `shared-app-db.nacfson-data`
3. Fill `health-secrets`, apply manifests, run migrate Job
4. Browser smoke on `https://health.nacfson.cloud`

See `apps/health-web/README.md`.
