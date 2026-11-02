# health-web MVP

> **Superseded (2026-11-02)**: the sign-in and deployment parts below are historical. health-web now
> signs in through the nacfson_pipeline platform gateway and is deployed by `nacfson_pipeline`. See
> `docs/changelog-health-web-gateway-auth.md` and `specs/001-health-web-gateway-auth/`.

Web product at `https://health.nacfson.cloud` (ProcessManager Option B). Lives in `apps/health-web/`; native Flutter SQLite + Supabase path unchanged. Sync bridge is out of MVP.

## Delivered

- Go API: cookie SSO (`nacfson_session`), CSRF `health_csrf`, Postgres user-owned tables (no `sync_status`), master seed from `master_exercise_seed_v12_6.json` — *SSO retired 2026-11*
- Domain ports: Atwater, Mifflin-St Jeor nutrition targets, exercise volume kcal coefficients
- Vanilla SPA: mockup v2 navy/mint, five tabs with CRUD
- K8s: `ProcessManager/k8s/health/` + restored spec §9 phases P0–P4 — *retired; deployment lives in nacfson_pipeline*

## Ops remaining (cluster unreachable from implement workstation)

1. ~~Push `health-api` / `health-frontend` to `192.168.219.100:5000`~~ → GHCR publish automated (`.github/workflows/publish-ghcr-images.yml`, 2026-10-25): `ghcr.io/nacfson/health-{backend,frontend}`; pin digests in `nacfson_pipeline`. Actions bumped to Node 24 majors (checkout v7, setup-go v7, docker/* v4/v6/v7) to clear the Node.js 20 deprecation warning
2. ~~Provision DB `health` on `shared-app-db.nacfson-data`~~ → `proj_health` via nacfson_pipeline vault-db-proxy
3. ~~Fill `health-secrets`, apply manifests, run migrate Job~~ → API applies migrations on start (2026-11)
4. Browser smoke on `https://health.nacfson.cloud` → see `specs/001-health-web-gateway-auth/quickstart.md`

See `apps/health-web/README.md`.
