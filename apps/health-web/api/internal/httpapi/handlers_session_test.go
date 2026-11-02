package httpapi

import (
	"net/http"
	"strings"
	"testing"
)

// GET /api/auth/config backs the nacfson_pipeline frontend startupProbe
// (CONTRACT_PROBES_READINESS: a public, DB-free `/api/...` route that proves the
// nginx `/api/` proxy reaches the backend). It must answer without a session,
// without the gateway, and without the database.
func TestAuthConfigIsPublicDBFreeAndGatewayFree(t *testing.T) {
	env := newTestEnv(t)

	rec := do(t, env.handler, http.MethodGet, "/api/auth/config", nil, nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", rec.Code, rec.Body.String())
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"login_url":"/api/auth/login"}` {
		t.Fatalf("body = %s", got)
	}
	if ex, conf, rev := env.gateway.calls(); ex+conf+rev != 0 {
		t.Fatal("the probe route must not call the gateway")
	}
	if len(rec.Result().Cookies()) != 0 {
		t.Fatalf("unexpected cookies on public route: %v", rec.Result().Cookies())
	}
}

func TestAuthConfigIgnoresInvalidSessionCookie(t *testing.T) {
	env := newTestEnv(t)

	rec := do(t, env.handler, http.MethodGet, "/api/auth/config", sessionCookie("stale"), nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if _, conf, _ := env.gateway.calls(); conf != 0 {
		t.Fatal("the gateway was called for a public route")
	}
}

func TestAuthConfigRejectsMutations(t *testing.T) {
	env := newTestEnv(t)
	assertBareUnauthorized(t, do(t, env.handler, http.MethodPost, "/api/auth/config", nil, nil))
}

func TestHealthzStaysPublic(t *testing.T) {
	env := newTestEnv(t)
	if rec := do(t, env.handler, http.MethodGet, "/healthz", nil, nil); rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if _, conf, _ := env.gateway.calls(); conf != 0 {
		t.Fatal("public endpoints must not call the gateway")
	}
}

func TestRetiredLogoutRouteIsGone(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
	rec := do(t, env.handler, http.MethodPost, "/api/logout", sessionCookie("tok"), withCSRF)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("POST /api/logout = %d, want 404", rec.Code)
	}
}
