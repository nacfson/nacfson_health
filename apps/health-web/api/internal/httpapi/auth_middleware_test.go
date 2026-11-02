package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/platformauth"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

func meUserID(t *testing.T, env *testEnv, token string, mutate func(*http.Request)) string {
	t.Helper()
	rec := do(t, env.handler, http.MethodGet, "/api/me", sessionCookie(token), mutate)
	if rec.Code != http.StatusOK {
		t.Fatalf("/api/me = %d %s", rec.Code, rec.Body.String())
	}
	var body struct {
		UserID string `json:"user_id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	return body.UserID
}

func TestMissingCookieIsUnauthorizedWithoutGatewayCall(t *testing.T) {
	env := newTestEnv(t)

	rec := do(t, env.handler, http.MethodGet, "/api/v1/weight?date=2026-11-02", nil, nil)

	assertBareUnauthorized(t, rec)
	if _, conf, _ := env.gateway.calls(); conf != 0 {
		t.Fatal("the gateway must not be called without a session cookie")
	}
}

func TestForgedIdentityWithoutSessionIsUnauthorized(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "victim-token", "victim-handle", "sub-victim")

	rec := do(t, env.handler, http.MethodGet, "/api/me", nil, func(r *http.Request) {
		r.Header.Set("X-User-Id", "11111111-1111-1111-1111-111111111111")
		r.Header.Set("X-User-Subject", "sub-victim")
		r.Header.Set("X-User-Issuer", testIssuer)
		r.Header.Set("X-Project-Audience", testAudience)
		r.Header.Set("Authorization", "Bearer victim-handle")
	})

	assertBareUnauthorized(t, rec)
	if _, conf, _ := env.gateway.calls(); conf != 0 {
		t.Fatal("a forged bearer must not be forwarded to the gateway")
	}
}

func TestForgedHeadersDoNotChangeAuthenticatedIdentity(t *testing.T) {
	env := newTestEnv(t)
	alice := env.sessions.seed(t, env.gateway, "alice-token", "alice-handle", "sub-alice")
	bob := env.sessions.seed(t, env.gateway, "bob-token", "bob-handle", "sub-bob")

	got := meUserID(t, env, "alice-token", func(r *http.Request) {
		r.Header.Set("X-User-Id", bob.String())
		r.Header.Set("X-User-Subject", "sub-bob")
		r.Header.Set("Authorization", "Bearer bob-handle")
	})

	if got != alice.String() {
		t.Fatalf("identity = %s, want alice %s (headers must be ignored)", got, alice)
	}
	env.gateway.mu.Lock()
	confirmed := append([]string(nil), env.gateway.confirmed...)
	env.gateway.mu.Unlock()
	if len(confirmed) != 1 || confirmed[0] != "alice-handle" {
		t.Fatalf("gateway confirmed %v, want only alice-handle", confirmed)
	}
}

func TestEachSessionResolvesToItsOwnAccount(t *testing.T) {
	env := newTestEnv(t)
	alice := env.sessions.seed(t, env.gateway, "alice-token", "alice-handle", "sub-alice")
	bob := env.sessions.seed(t, env.gateway, "bob-token", "bob-handle", "sub-bob")

	if alice == bob {
		t.Fatal("two platform identities must get two accounts")
	}
	if got := meUserID(t, env, "alice-token", nil); got != alice.String() {
		t.Fatalf("alice resolved to %s", got)
	}
	if got := meUserID(t, env, "bob-token", nil); got != bob.String() {
		t.Fatalf("bob resolved to %s", got)
	}
}

func TestUnknownSessionCookieIsClearedAndUnauthorized(t *testing.T) {
	env := newTestEnv(t)

	rec := do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("never-issued"), nil)

	assertBareUnauthorized(t, rec)
	assertCookieCleared(t, rec, sessionCookieName)
	if _, conf, _ := env.gateway.calls(); conf != 0 {
		t.Fatal("unknown sessions must not reach the gateway")
	}
}

func TestExpiredSessionIsUnauthorized(t *testing.T) {
	env := newTestEnv(t)
	id := env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
	env.sessions.sessions["tok"] = store.WebSession{UserID: id, Issuer: testIssuer, Subject: "sub-alice", SessionHandle: "h", ExpiresAt: time.Now().Add(-time.Minute)}

	assertBareUnauthorized(t, do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok"), nil))
}

func TestGatewayRejectionEndsSession(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
	env.gateway.confirmErr = platformauth.ErrRejected // revoked elsewhere, or expired

	rec := do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok"), nil)

	assertBareUnauthorized(t, rec)
	assertCookieCleared(t, rec, sessionCookieName)
	if _, ok := env.sessions.get("tok"); ok {
		t.Fatal("a rejected session must be deleted")
	}
}

func TestGatewayOutageFailsClosedAndKeepsSession(t *testing.T) {
	for _, err := range []error{platformauth.ErrUnavailable, errors.New("dial tcp: connection refused")} {
		env := newTestEnv(t)
		env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
		env.gateway.confirmErr = err

		rec := do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok"), nil)

		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("status = %d, want 503 (body %s)", rec.Code, rec.Body.String())
		}
		var body map[string]string
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		if body["error"] != "auth_unavailable" {
			t.Fatalf("body = %s, want auth_unavailable", rec.Body.String())
		}
		if _, ok := env.sessions.get("tok"); !ok {
			t.Fatal("an outage must not delete the session")
		}
		if findCookie(rec, sessionCookieName) != nil {
			t.Fatal("an outage must not touch the session cookie")
		}
	}
}

func TestSessionStoreOutageFailsClosed(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.failAll = errors.New("db down")

	rec := do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok"), nil)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
}

func TestForeignAudienceIsRejected(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
	env.gateway.handles["h"] = platformauth.Confirmed{Issuer: testIssuer, Subject: "sub-alice", Audience: "project-pn"}

	rec := do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok"), nil)

	assertBareUnauthorized(t, rec)
	if _, ok := env.sessions.get("tok"); ok {
		t.Fatal("a foreign-audience session must be deleted")
	}
}

func TestMissingAudienceIsRejected(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
	env.gateway.handles["h"] = platformauth.Confirmed{Issuer: testIssuer, Subject: "sub-alice"}

	assertBareUnauthorized(t, do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok"), nil))
}

func TestIdentityMismatchIsRejected(t *testing.T) {
	cases := map[string]platformauth.Confirmed{
		"other subject": {Issuer: testIssuer, Subject: "sub-mallory", Audience: testAudience},
		"other issuer":  {Issuer: "https://evil.example.com/realms/platform", Subject: "sub-alice", Audience: testAudience},
	}
	for name, confirmed := range cases {
		t.Run(name, func(t *testing.T) {
			env := newTestEnv(t)
			env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
			env.gateway.handles["h"] = confirmed

			rec := do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok"), nil)

			assertBareUnauthorized(t, rec)
			if _, ok := env.sessions.get("tok"); ok {
				t.Fatal("a mismatched session must be deleted")
			}
		})
	}
}

func TestRefreshedHandleIsStored(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "tok", "old-handle", "sub-alice")
	env.gateway.handles["old-handle"] = platformauth.Confirmed{
		Issuer: testIssuer, Subject: "sub-alice", Audience: testAudience, RefreshedHandle: "new-handle",
	}

	meUserID(t, env, "tok", nil)

	if sess, _ := env.sessions.get("tok"); sess.SessionHandle != "new-handle" {
		t.Fatalf("stored handle = %q, want new-handle", sess.SessionHandle)
	}
}

func TestSessionPersistsAcrossRequests(t *testing.T) {
	env := newTestEnv(t)
	alice := env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
	for i := 0; i < 20; i++ {
		if got := meUserID(t, env, "tok", nil); got != alice.String() {
			t.Fatalf("request %d resolved to %s", i, got)
		}
	}
}

func TestMeIssuesReadableCSRFCookie(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")

	rec := do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok"), func(r *http.Request) {
		r.Header.Set("X-Forwarded-Proto", "https")
	})

	csrf := findCookie(rec, csrfCookieName)
	if csrf == nil || csrf.Value == "" || csrf.HttpOnly || !csrf.Secure || csrf.Path != "/" || csrf.SameSite != http.SameSiteLaxMode {
		t.Fatalf("health_csrf = %+v", csrf)
	}
}

func TestMutationsRequireCSRF(t *testing.T) {
	cases := map[string]func(*http.Request){
		"no token": func(r *http.Request) { r.Header.Set("Origin", testOrigin) },
		"mismatched token": func(r *http.Request) {
			r.Header.Set("Origin", testOrigin)
			r.Header.Set(csrfHeaderName, "a")
			r.AddCookie(&http.Cookie{Name: csrfCookieName, Value: "b"})
		},
		"foreign origin": func(r *http.Request) {
			r.Header.Set("Origin", "https://evil.example.com")
			r.Header.Set(csrfHeaderName, "a")
			r.AddCookie(&http.Cookie{Name: csrfCookieName, Value: "a"})
		},
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			env := newTestEnv(t)
			env.sessions.seed(t, env.gateway, "tok", "h", "sub-alice")
			rec := do(t, env.handler, http.MethodPost, "/api/v1/weight", sessionCookie("tok"), mutate)
			if rec.Code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403 (body %s)", rec.Code, rec.Body.String())
			}
		})
	}
}
