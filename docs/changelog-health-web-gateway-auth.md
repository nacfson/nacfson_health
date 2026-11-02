# health-web — 플랫폼 게이트웨이 로그인 (2026-11-02)

Spec: `specs/001-health-web-gateway-auth/` (spec · clarifications · plan · research · contracts · tasks).
네이티브 Flutter 앱(`lib/`)은 변경 없음.

## 배경 / 사고 회고

- 증상: `https://health.nacfson.cloud` 접속 시 UI가 잠깐 보였다가 `404 page not found`. Hubble 에는
  네트워크 이상이 없었다. 패킷은 정상 전달되었고, 404 는 정상 HTTP 응답이었다.
- 원인 1: SPA 가 `/api/me` 401 을 받으면 `https://auth.nacfson.cloud/login?rd=…` 로 자동 리다이렉트했다.
  클러스터의 `auth.nacfson.cloud` 는 allowlist 경로(`/realms/platform/...`, `/oauth/start`,
  `/oauth/callback`, `/auth/logout`)만 라우팅하므로, `/login` 은 Traefik 기본 404 였다.
- 원인 2: API 가 은퇴한 ProcessManager Auth 계약(`/api/internal/cookie-session` + 공유 토큰)으로만 세션을
  확인했다. 토큰이 비어 있어 모든 요청이 401 이었다. 로그인 URL 만 고쳤다면 무한 루프가 되었을 것이다.
- 원인 3: `nacfson_pipeline` CONTRACT_DATABASE §6 은 "백엔드 기동 시 마이그레이션 자동 적용"을 요구하지만,
  API 는 이를 하지 않았고 migrate Job 도 없었다. 따라서 `proj_health` 스키마가 생성되지 않았을 가능성이 높다.
- 교훈: 플랫폼 계약(`nacfson_pipeline/contracts/`)이 바뀌면 소비 프로젝트의 문서·코드도 같은 단위로
  갱신한다. 자동 리다이렉트는 실패 원인을 숨기므로 로그인 화면에서 사유를 보여준다.

## 변경

### API (`apps/health-web/api`)

- 삭제: `internal/auth/central_client.go`, `handlers_session.go`, `POST /api/logout`,
  env `CENTRAL_AUTH_URL` / `CENTRAL_AUTH_INTERNAL_URL` / `AUTH_SESSION_INTERNAL_TOKEN`.
- 신규 `internal/platformauth`: 게이트웨이 `POST /auth/exchange`, `GET /auth`, `POST /auth/logout`
  클라이언트 (`X-Forwarded-Host: health.nacfson.cloud`, 5s timeout, 리다이렉트 미추종).
- 신규 라우트: `GET /api/auth/login`, `GET /api/auth/callback`, `POST /api/auth/logout`.
  `GET /api/auth/config` 는 경로를 유지한다(frontend startupProbe). 응답은 `{"login_url":"/api/auth/login"}` 로 바뀐다.
- 인증 미들웨어: `__Host-health_session` → `web_sessions` → 게이트웨이 확인 → audience·(issuer, subject)
  일치 확인 → refresh handle 저장. 거부되면 세션을 삭제하고 401, 게이트웨이 장애면 503 `auth_unavailable` 이다.
- `/api/me` 는 `{user_id}` 만 반환한다(이메일 제거).
- 기동 시 `migrations.Up` + master seed 를 실행한다(`MIGRATE_ON_START`, 실패 시 종료). 만료 세션은 매시간 purge 한다.
- 새 env: `GATEWAY_AUTH_URL`, `PUBLIC_AUTH_URL`, `PUBLIC_APP_URL`(`APP_PUBLIC_URL` fallback),
  `PROJECT_AUDIENCE`, `MIGRATE_ON_START`.

### DB (health-web Postgres, migration `000002_platform_identity`)

- `users(id, issuer, subject, created_at, last_seen_at)`, `UNIQUE(issuer, subject)`
- `web_sessions(id_hash sha256, user_id → users, issuer, subject, session_handle, created_at, expires_at)`
- 기존 user-owned 테이블은 변경하지 않는다(`user_id UUID` 유지). 상세: `docs/db-schema.md` "health-web Postgres".

### SPA (`apps/health-web/frontend`)

- 자동 리다이렉트를 제거했다. 로그인 화면의 "Google로 계속" 버튼으로만 로그인을 시작한다(`next` 로 현재 페이지 복귀).
- 로그인 화면에 사유를 표시한다: 미로그인 / 세션 만료 / 로그인 실패 / 일시적 장애 / 로그아웃(플랫폼 확인 실패 포함).
- 이메일 표시를 제거했다. 설정 → 계정에 로그인 방식(Google, nacfson 통합 계정)과
  "로그아웃 (모든 nacfson 서비스)" 를 표시한다.

## 설계 결정 (research.md)

- 게이트웨이 session handle(약 3–4 KB)은 브라우저 쿠키 한도(4 KB)에 걸리고,
  `strip-forged-headers` 가 `Authorization` 을 제거한다. 그래서 pipeline `projectauth` 의 "브라우저 bearer"
  방식 대신 서버측 세션 + 소형 `__Host-` 쿠키를 택했다.
- 로그아웃은 플랫폼 전체 로그아웃이다(clarification Q2).
- 접근 규칙: 플랫폼 로그인을 마친 누구나 자신의 데이터만 사용할 수 있다. 계정은 플랫폼이 소유한다(clarification Q1).

## 배포

이미지 교체만 필요하다. `nacfson_pipeline` 의 라우트·probe·NetworkPolicy·env 변경은 없다.
머지 후 GHCR 게시 → `nacfson_pipeline` `update-project-images` 로 pin 을 bump 하고 →
`specs/001-health-web-gateway-auth/quickstart.md` §3 으로 확인한다.
