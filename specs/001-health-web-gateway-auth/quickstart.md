# Quickstart: Verify health-web Gateway Sign-In

## 1. Local (no cluster)

```bash
cd apps/health-web/api
go vet ./... && go test ./...
cd ../frontend && ./smoke-test.sh
```

`go test` covers the gateway stub flows: login redirect, callback binding, exchange failures, the
confirm/refresh/reject/unavailable mapping, forged headers, foreign audience, cross-user isolation,
and logout outcomes.

## 2. Retired-system sweep (SC-006)

```bash
git grep -nE 'nacfson_session|cookie-session|AUTH_SESSION_INTERNAL_TOKEN|CENTRAL_AUTH|ProcessManager SSO|auth\.nacfson\.cloud/login' \
  -- ':!docs/changelog-*' ':!specs/001-health-web-gateway-auth' ':!docs/superpowers' ':!.specify/memory/constitution.md'
```

Expected: no output.

## 3. After the image pin is bumped in nacfson_pipeline

```bash
H=https://health.nacfson.cloud
curl -s  $H/api/auth/config                    # {"login_url":"/api/auth/login"}
curl -s  -o /dev/null -w '%{http_code}\n' $H/api/me      # 401
curl -sI "$H/api/auth/login?next=/" | grep -i '^location'  # https://auth.nacfson.cloud/oauth/start?return=https%3A%2F%2Fhealth.nacfson.cloud%2Fapi%2Fauth%2Fcallback%3Fpa_bind%3D...
curl -s  -o /dev/null -w '%{http_code}\n' "$(curl -sI "$H/api/auth/login" | sed -n 's/^location: //Ip' | tr -d '\r')"  # 302 (gateway accepts the return host)
curl -s -H 'X-User-Id: 00000000-0000-0000-0000-000000000001' -H 'Authorization: Bearer x' \
     -o /dev/null -w '%{http_code}\n' $H/api/v1/weight     # 401
KUBECONFIG=~/.kube/nacfson-vps-k3s.yaml kubectl -n proj-health logs deploy/health-backend | head
#   expect: "migrations applied", "master catalog seeded", no AUTH_SESSION_INTERNAL_TOKEN warning
```

Browser (fresh profile):

1. Open `https://health.nacfson.cloud/` → sign-in screen with "Google로 계속". No automatic
   redirect.
2. Continue → Google → back on health-web, signed in. Save a weight entry and reload: it is still
   there.
3. Open a second tab: signed in.
4. Settings → 로그아웃 (모든 nacfson 서비스) → sign-in screen, "로그아웃되었습니다".
   `https://pn.nacfson.cloud` is signed out too.
5. A second Google account in another browser does not see the first account's entry.
