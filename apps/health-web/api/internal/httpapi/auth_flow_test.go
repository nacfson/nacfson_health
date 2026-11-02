package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/platformauth"
)

// startLogin runs GET /api/auth/login and returns the nonce cookie and the
// callback URL the gateway would return to.
func startLogin(t *testing.T, env *testEnv, next string) (*http.Cookie, *url.URL) {
	t.Helper()
	target := "/api/auth/login"
	if next != "" {
		target += "?next=" + url.QueryEscape(next)
	}
	rec := do(t, env.handler, http.MethodGet, target, nil, nil)
	if rec.Code != http.StatusFound {
		t.Fatalf("login status = %d, want 302", rec.Code)
	}
	loc, err := url.Parse(rec.Header().Get("Location"))
	if err != nil {
		t.Fatal(err)
	}
	if loc.Scheme != "https" || loc.Host != "auth.nacfson.cloud" || loc.Path != "/oauth/start" {
		t.Fatalf("login redirect = %s, want https://auth.nacfson.cloud/oauth/start", loc)
	}
	ret, err := url.Parse(loc.Query().Get("return"))
	if err != nil {
		t.Fatal(err)
	}
	if ret.Scheme != "https" || ret.Host != "health.nacfson.cloud" || ret.Path != "/api/auth/callback" {
		t.Fatalf("return = %s, want https://health.nacfson.cloud/api/auth/callback", ret)
	}
	nonce := findCookie(rec, loginCookieName)
	if nonce == nil || len(nonce.Value) != 32 {
		t.Fatalf("login nonce cookie missing or wrong size: %+v", nonce)
	}
	if !nonce.HttpOnly || !nonce.Secure || nonce.SameSite != http.SameSiteLaxMode || nonce.Path != "/" || nonce.Domain != "" {
		t.Fatalf("login cookie attributes wrong: %+v", nonce)
	}
	if got, want := ret.Query().Get("pa_bind"), bindDigest(nonce.Value); got != want {
		t.Fatalf("pa_bind = %q, want sha256(nonce) %q", got, want)
	}
	return nonce, ret
}

// finishLogin follows the gateway's redirect back to the callback with ticket.
func finishLogin(t *testing.T, env *testEnv, nonce *http.Cookie, ret *url.URL, ticket string) *httptest.ResponseRecorder {
	t.Helper()
	q := ret.Query()
	q.Set("ticket", ticket)
	ret.RawQuery = q.Encode()
	return do(t, env.handler, http.MethodGet, ret.RequestURI(), nonce, nil)
}

func TestLoginRedirectsToGatewayWithBoundCallback(t *testing.T) {
	env := newTestEnv(t)
	_, ret := startLogin(t, env, "/diet?d=2026-11-02")
	if got := ret.Query().Get("next"); got != "/diet?d=2026-11-02" {
		t.Fatalf("next = %q", got)
	}
	if ex, conf, _ := env.gateway.calls(); ex+conf != 0 {
		t.Fatal("login must not call the gateway server-side")
	}
}

func TestLoginDropsUnsafeNext(t *testing.T) {
	for _, next := range []string{
		"https://evil.example.com/", "//evil.example.com", "/\\evil.example.com", "javascript:alert(1)",
		"/api/v1/weight", "relative", "/ok\nSet-Cookie: x=y",
	} {
		env := newTestEnv(t)
		_, ret := startLogin(t, env, next)
		if got := ret.Query().Get("next"); got != "" {
			t.Fatalf("next %q kept as %q, want dropped", next, got)
		}
	}
}

func TestSignInRoundTripCreatesAccountAndSession(t *testing.T) {
	env := newTestEnv(t)
	env.gateway.signIn("ticket-1", "handle-1", "sub-alice")

	nonce, ret := startLogin(t, env, "/weight")
	rec := finishLogin(t, env, nonce, ret, "ticket-1")

	if rec.Code != http.StatusFound || rec.Header().Get("Location") != "/weight" {
		t.Fatalf("callback = %d %q, want 302 /weight", rec.Code, rec.Header().Get("Location"))
	}
	session := findCookie(rec, sessionCookieName)
	if session == nil || len(session.Value) != 43 {
		t.Fatalf("session cookie missing or wrong size: %+v", session)
	}
	if !session.HttpOnly || !session.Secure || session.SameSite != http.SameSiteLaxMode || session.Path != "/" || session.Domain != "" {
		t.Fatalf("session cookie attributes wrong: %+v", session)
	}
	if session.MaxAge != 3600 {
		t.Fatalf("session MaxAge = %d, want gateway expires_in 3600", session.MaxAge)
	}
	assertCookieCleared(t, rec, loginCookieName)

	stored, ok := env.sessions.get(session.Value)
	if !ok || stored.SessionHandle != "handle-1" || stored.Subject != "sub-alice" || stored.Issuer != testIssuer {
		t.Fatalf("stored session = %+v, %v", stored, ok)
	}
	if strings.Contains(rec.Body.String(), "handle-1") || strings.Contains(rec.Header().Get("Location"), "handle-1") {
		t.Fatal("the gateway handle must never reach the browser")
	}

	me := do(t, env.handler, http.MethodGet, "/api/me", session, nil)
	if me.Code != http.StatusOK {
		t.Fatalf("/api/me = %d %s", me.Code, me.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(me.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["user_id"] != stored.UserID.String() || len(body) != 1 {
		t.Fatalf("/api/me body = %v, want only user_id %s", body, stored.UserID)
	}
}

func TestSecondSignInReusesProjectAccount(t *testing.T) {
	env := newTestEnv(t)
	env.gateway.signIn("t1", "h1", "sub-alice")
	env.gateway.signIn("t2", "h2", "sub-alice")

	n1, r1 := startLogin(t, env, "")
	c1 := findCookie(finishLogin(t, env, n1, r1, "t1"), sessionCookieName)
	n2, r2 := startLogin(t, env, "")
	c2 := findCookie(finishLogin(t, env, n2, r2, "t2"), sessionCookieName)

	s1, _ := env.sessions.get(c1.Value)
	s2, _ := env.sessions.get(c2.Value)
	if s1.UserID != s2.UserID {
		t.Fatalf("same platform identity got two accounts: %s vs %s", s1.UserID, s2.UserID)
	}
}

func TestCallbackReplacesExistingBrowserSession(t *testing.T) {
	env := newTestEnv(t)
	env.sessions.seed(t, env.gateway, "old-token", "old-handle", "sub-alice")
	env.gateway.signIn("t", "h", "sub-alice")

	nonce, ret := startLogin(t, env, "")
	q := ret.Query()
	q.Set("ticket", "t")
	ret.RawQuery = q.Encode()
	rec := do(t, env.handler, http.MethodGet, ret.RequestURI(), nonce, func(r *http.Request) {
		r.AddCookie(sessionCookie("old-token"))
	})

	if rec.Code != http.StatusFound {
		t.Fatalf("status = %d", rec.Code)
	}
	if _, ok := env.sessions.get("old-token"); ok {
		t.Fatal("old browser session must be deleted after a new sign-in")
	}
}

func TestCallbackFailures(t *testing.T) {
	cases := []struct {
		name       string
		setup      func(env *testEnv)
		mutate     func(nonce *http.Cookie, q url.Values) (*http.Cookie, url.Values)
		wantAuth   string
		wantRedeem bool
	}{
		{
			name:     "missing ticket",
			mutate:   func(n *http.Cookie, q url.Values) (*http.Cookie, url.Values) { q.Del("ticket"); return n, q },
			wantAuth: "failed",
		},
		{
			name:     "missing nonce cookie (forged or cross-browser callback)",
			mutate:   func(_ *http.Cookie, q url.Values) (*http.Cookie, url.Values) { return nil, q },
			wantAuth: "failed",
		},
		{
			name: "binding mismatch",
			mutate: func(n *http.Cookie, q url.Values) (*http.Cookie, url.Values) {
				q.Set("pa_bind", bindDigest("someone-else"))
				return n, q
			},
			wantAuth: "failed",
		},
		{
			name:     "missing pa_bind",
			mutate:   func(n *http.Cookie, q url.Values) (*http.Cookie, url.Values) { q.Del("pa_bind"); return n, q },
			wantAuth: "failed",
		},
		{
			name:       "ticket rejected (used, expired, other host)",
			setup:      func(env *testEnv) { env.gateway.exchangeErr = platformauth.ErrRejected },
			wantAuth:   "failed",
			wantRedeem: true,
		},
		{
			name:       "gateway unreachable",
			setup:      func(env *testEnv) { env.gateway.exchangeErr = platformauth.ErrUnavailable },
			wantAuth:   "unavailable",
			wantRedeem: true,
		},
		{
			name: "foreign audience",
			setup: func(env *testEnv) {
				env.gateway.tickets["t"] = platformauth.Exchanged{SessionHandle: "h", Issuer: testIssuer, Subject: "s", Audience: "project-pn"}
			},
			wantAuth:   "failed",
			wantRedeem: true,
		},
		{
			name:       "store down",
			setup:      func(env *testEnv) { env.sessions.failAll = errors.New("db down") },
			wantAuth:   "unavailable",
			wantRedeem: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			env := newTestEnv(t)
			env.gateway.signIn("t", "h", "sub-alice")
			if tc.setup != nil {
				tc.setup(env)
			}
			nonce, ret := startLogin(t, env, "/weight")
			q := ret.Query()
			q.Set("ticket", "t")
			if tc.mutate != nil {
				nonce, q = tc.mutate(nonce, q)
			}
			ret.RawQuery = q.Encode()

			rec := do(t, env.handler, http.MethodGet, ret.RequestURI(), nonce, nil)

			if rec.Code != http.StatusFound || rec.Header().Get("Location") != "/?auth="+tc.wantAuth {
				t.Fatalf("callback = %d %q, want 302 /?auth=%s", rec.Code, rec.Header().Get("Location"), tc.wantAuth)
			}
			if findCookie(rec, sessionCookieName) != nil {
				t.Fatal("no session cookie may be set on a failed callback")
			}
			assertCookieCleared(t, rec, loginCookieName)
			if env.sessions.count() != 0 {
				t.Fatal("no session may be stored on a failed callback")
			}
			if ex, _, _ := env.gateway.calls(); (ex > 0) != tc.wantRedeem {
				t.Fatalf("ticket redeemed = %v, want %v", ex > 0, tc.wantRedeem)
			}
		})
	}
}

func TestReplayedTicketIsRejected(t *testing.T) {
	env := newTestEnv(t)
	env.gateway.signIn("t", "h", "sub-alice")
	nonce, ret := startLogin(t, env, "")
	if rec := finishLogin(t, env, nonce, ret, "t"); rec.Header().Get("Location") != "/" {
		t.Fatalf("first use = %q", rec.Header().Get("Location"))
	}
	again := finishLogin(t, env, nonce, ret, "t")
	if again.Header().Get("Location") != "/?auth=failed" {
		t.Fatalf("replay = %q, want /?auth=failed", again.Header().Get("Location"))
	}
}
