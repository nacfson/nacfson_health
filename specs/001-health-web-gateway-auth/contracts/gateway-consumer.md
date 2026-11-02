# Contract: health-web as a Gateway Consumer (in-cluster)

Source of truth: `nacfson_pipeline/contracts/CONTRACT_AUTH_DOOR.md` and
`nacfson_pipeline/gateway/internal/auth/{handler,logout}.go` (`913f03c`). This file pins what
health-web relies on. A gateway change that breaks a row here breaks health-web.

| Setting | Env | Default |
|---|---|---|
| Gateway verify URL | `GATEWAY_AUTH_URL` | `http://gateway.identity.svc:8080/auth` (already set on the Deployment) |
| Gateway base | derived: `GATEWAY_AUTH_URL` minus the trailing `/auth` | `http://gateway.identity.svc:8080` |
| Public sign-in origin | `PUBLIC_AUTH_URL` | `https://auth.nacfson.cloud` |
| Public app origin | `PUBLIC_APP_URL` (already set), fallback `APP_PUBLIC_URL` | `https://health.nacfson.cloud` |
| Expected audience | `PROJECT_AUDIENCE` | `project-` + first label of the app host (`project-health`) |

Every call sends `X-Forwarded-Host: <app host>` and uses a 5 s timeout.

## Exchange

`POST {base}/auth/exchange`, `Content-Type: application/json`, body `{"ticket":"<t>"}`.

- `200`: decode `session_handle` (required, non-empty), `subject`, `issuer` (required),
  `audience`, `expires_in` (seconds; `<= 0` → 28800).
- `401`: ticket rejected.
- Anything else, or a network error: unavailable.

## Confirm

`GET {base}/auth`, `Authorization: Bearer <handle>`.

- `200`: `X-User-Subject` and `X-User-Issuer` are required. `X-Project-Audience`, when present,
  MUST equal the expected audience. `X-Refreshed-Session-Handle`, when present, replaces the stored
  handle.
- `401`: rejected.
- `503`, any other status, or a network error: unavailable.

## Revoke

`POST {base}/auth/logout`, `Authorization: Bearer <handle>`, empty body.

- `200` (or `302`; redirects are not followed): revoked.
- Anything else: unconfirmed.

Not used: `X-User-Email`, the returned `Authorization` project JWT, and the legacy
`PLATFORM_SESSION` cookie path.
