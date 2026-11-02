package httpapi

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/platformauth"
)

func logoutOutcome(t *testing.T, env *testEnv, token string) (int, string) {
	t.Helper()
	var cookie *http.Cookie
	if token != "" {
		cookie = sessionCookie(token)
	}
	rec := do(t, env.handler, http.MethodPost, "/api/auth/logout", cookie, withCSRF)
	if rec.Code != http.StatusOK {
		return rec.Code, rec.Body.String()
	}
	assertCookieCleared(t, rec, sessionCookieName)
	var body struct {
		Status   string `json:"status"`
		Platform string `json:"platform"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body.Status != "signed_out" {
		t.Fatalf("logout body = %s", rec.Body.String())
	}
	return rec.Code, body.Platform
}

func TestLogoutRevokesPlatformSessionAndEndsBrowserSession(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")

	_, platform := logoutOutcome(t, env, "tok")

	if platform != "revoked" {
		t.Fatalf("platform = %q, want revoked", platform)
	}
	env.gateway.mu.Lock()
	revoked := append([]string(nil), env.gateway.revoked...)
	env.gateway.mu.Unlock()
	if len(revoked) != 1 || revoked[0] != "h" {
		t.Fatalf("revoked %v, want the stored handle", revoked)
	}
	if _, ok := env.sessions.get("tok"); ok {
		t.Fatal("session row must be deleted")
	}
	assertBareUnauthorized(t, do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok"), nil))
}

func TestLogoutStillEndsSessionWhenRevocationFails(t *testing.T) {
	for _, err := range []error{platformauth.ErrUnavailable, platformauth.ErrRejected} {
		env := newTestEnv(t)
		env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
		env.gateway.revokeErr = err

		_, platform := logoutOutcome(t, env, "tok")

		if platform != "unconfirmed" {
			t.Fatalf("platform = %q, want unconfirmed", platform)
		}
		if _, ok := env.sessions.get("tok"); ok {
			t.Fatal("session row must be deleted even when revocation fails")
		}
	}
}

func TestLogoutWorksWhenGatewayAlreadyRejectsSession(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
	env.gateway.confirmErr = platformauth.ErrRejected

	if code, platform := logoutOutcome(t, env, "tok"); code != http.StatusOK || platform != "revoked" {
		t.Fatalf("logout = %d %q", code, platform)
	}
	if _, conf, _ := env.gateway.calls(); conf != 0 {
		t.Fatal("logout must not depend on session confirmation")
	}
}

func TestLogoutWithoutSession(t *testing.T) {
	env := newTestEnv(t)
	if _, platform := logoutOutcome(t, env, ""); platform != "none" {
		t.Fatalf("platform = %q, want none", platform)
	}
	if _, _, rev := env.gateway.calls(); rev != 0 {
		t.Fatal("nothing to revoke without a session")
	}
}

func TestLogoutRequiresCSRF(t *testing.T) {
	cases := map[string]func(*http.Request){
		"no csrf": func(r *http.Request) { r.Header.Set("Origin", testOrigin) },
		"foreign origin": func(r *http.Request) {
			withCSRF(r)
			r.Header.Set("Origin", "https://evil.example.com")
		},
		"no origin": func(r *http.Request) {
			withCSRF(r)
			r.Header.Del("Origin")
		},
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			env := newTestEnv(t)
			env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")

			rec := do(t, env.handler, http.MethodPost, "/api/auth/logout", sessionCookie("tok"), mutate)

			if rec.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403", rec.Code)
			}
			if _, _, rev := env.gateway.calls(); rev != 0 {
				t.Fatal("no revocation without CSRF")
			}
			if _, ok := env.sessions.get("tok"); !ok {
				t.Fatal("session must survive a rejected logout")
			}
		})
	}
}
