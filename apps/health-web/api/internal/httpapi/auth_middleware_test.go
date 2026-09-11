package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/auth"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/config"
)

// centralStub impersonates the ProcessManager Auth service contract:
// GET /api/internal/cookie-session and DELETE /api/auth/session.
type centralStub struct {
	server *httptest.Server

	mu             sync.Mutex
	sessionBody    string
	sessionStatus  int
	logoutStatus   int
	seenValidate   http.Header
	seenLogout     http.Header
	logoutRequests int
}

func newCentralStub(t *testing.T) *centralStub {
	t.Helper()
	stub := &centralStub{
		sessionStatus: http.StatusOK,
		sessionBody: `{"user_id":"11111111-1111-1111-1111-111111111111",
			"email":"USER@Example.com","is_admin":false,
			"expires_at":"` + time.Now().Add(time.Hour).UTC().Format(time.RFC3339) + `"}`,
		logoutStatus: http.StatusNoContent,
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/internal/cookie-session", func(w http.ResponseWriter, r *http.Request) {
		stub.mu.Lock()
		stub.seenValidate = r.Header.Clone()
		body, status := stub.sessionBody, stub.sessionStatus
		stub.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	})
	mux.HandleFunc("DELETE /api/auth/session", func(w http.ResponseWriter, r *http.Request) {
		stub.mu.Lock()
		stub.seenLogout = r.Header.Clone()
		stub.logoutRequests++
		status := stub.logoutStatus
		stub.mu.Unlock()
		w.WriteHeader(status)
	})
	stub.server = httptest.NewServer(mux)
	t.Cleanup(stub.server.Close)
	return stub
}

func (s *centralStub) validateHeaders() http.Header {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.seenValidate
}

func (s *centralStub) logoutHeaders() http.Header {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.seenLogout
}

func (s *centralStub) logouts() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.logoutRequests
}

// newTestHandler wires the real router against a stub Auth service. The store is
// nil: every test here stops before touching the database.
func newTestHandler(t *testing.T, stub *centralStub) http.Handler {
	t.Helper()
	cfg := config.Config{
		AppAddr:        ":0",
		AllowedOrigins: []string{"https://health.nacfson.cloud"},
	}
	central := auth.NewCentralClient(stub.server.URL, stub.server.URL, "internal-token", stub.server.Client())
	return NewHandler(cfg, nil, central)
}

func do(t *testing.T, handler http.Handler, method, target string, cookie *http.Cookie, mutate func(*http.Request)) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, target, nil)
	if cookie != nil {
		req.AddCookie(cookie)
	}
	if mutate != nil {
		mutate(req)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func sessionCookie(value string) *http.Cookie {
	return &http.Cookie{Name: auth.CentralSessionCookieName, Value: value}
}

func assertBareUnauthorized(t *testing.T, rec *httptest.ResponseRecorder) {
	t.Helper()
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 (body %s)", rec.Code, rec.Body.String())
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"unauthorized"}` {
		t.Fatalf("body = %s, want bare unauthorized", got)
	}
}

func TestAuthMiddlewareRejectsMissingCookie(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/api/me", nil, nil)

	assertBareUnauthorized(t, rec)
	if stub.validateHeaders() != nil {
		t.Fatal("auth service must not be called without a cookie")
	}
}

func TestAuthMiddlewareRejectsUnknownSession(t *testing.T) {
	stub := newCentralStub(t)
	stub.sessionStatus = http.StatusUnauthorized
	stub.sessionBody = `{"error":"unauthorized"}`
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/api/me", sessionCookie("stale"), nil)

	assertBareUnauthorized(t, rec)
}

func TestAuthMiddlewareRejectsExpiredSession(t *testing.T) {
	stub := newCentralStub(t)
	stub.sessionBody = `{"user_id":"11111111-1111-1111-1111-111111111111",
		"email":"user@example.com","is_admin":false,
		"expires_at":"` + time.Now().Add(-time.Minute).UTC().Format(time.RFC3339) + `"}`
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/api/me", sessionCookie("expired"), nil)

	assertBareUnauthorized(t, rec)
}

func TestMeReturnsIdentityAndIssuesCSRFCookie(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/api/me", sessionCookie("good"), nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", rec.Code, rec.Body.String())
	}
	var payload struct {
		UserID string `json:"user_id"`
		Email  string `json:"email"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.UserID != "11111111-1111-1111-1111-111111111111" {
		t.Fatalf("user_id = %q", payload.UserID)
	}
	if payload.Email != "user@example.com" {
		t.Fatalf("email = %q, want normalized lowercase email", payload.Email)
	}

	validate := stub.validateHeaders()
	if got := validate.Get("Authorization"); got != "Bearer internal-token" {
		t.Fatalf("Authorization = %q, want internal bearer token", got)
	}
	if got := validate.Get("Cookie"); got != auth.CentralSessionCookieName+"=good" {
		t.Fatalf("forwarded Cookie = %q", got)
	}

	csrf := findCookie(rec, csrfCookieName)
	if csrf == nil || csrf.Value == "" {
		t.Fatal("expected health_csrf cookie to be issued on authenticated GET")
	}
	if csrf.HttpOnly {
		t.Fatal("health_csrf must be readable by the SPA")
	}
	if csrf.Path != "/" {
		t.Fatalf("health_csrf path = %q, want /", csrf.Path)
	}
	if csrf.SameSite != http.SameSiteLaxMode {
		t.Fatalf("health_csrf SameSite = %v, want Lax", csrf.SameSite)
	}
}

func TestCSRFCookieIsSecureBehindTLSProxy(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/api/me", sessionCookie("good"), func(r *http.Request) {
		r.Header.Set("X-Forwarded-Proto", "https")
	})

	csrf := findCookie(rec, csrfCookieName)
	if csrf == nil || !csrf.Secure {
		t.Fatal("health_csrf must be Secure when X-Forwarded-Proto is https")
	}
}

func TestHealthzStaysPublic(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/healthz", nil, nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if stub.validateHeaders() != nil {
		t.Fatal("public endpoints must not call the auth service")
	}
}

func TestSpoofedIdentityHeadersAreDiscarded(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/api/me", sessionCookie("good"), func(r *http.Request) {
		r.Header.Set("X-User-Id", "99999999-9999-9999-9999-999999999999")
		r.Header.Set("X-User-Email", "attacker@example.com")
		r.Header.Set("X-User-Roles", "admin")
	})

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var payload struct {
		UserID string `json:"user_id"`
		Email  string `json:"email"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.UserID != "11111111-1111-1111-1111-111111111111" || payload.Email != "user@example.com" {
		t.Fatalf("identity came from headers: %+v", payload)
	}
	validate := stub.validateHeaders()
	for _, header := range []string{"X-User-Id", "X-User-Email", "X-User-Roles"} {
		if got := validate.Get(header); got != "" {
			t.Fatalf("%s leaked to the auth service: %q", header, got)
		}
	}
}

func TestMutationRequiresCSRFCookieAndHeader(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodPost, "/api/logout", sessionCookie("good"), func(r *http.Request) {
		r.Header.Set("Origin", "https://health.nacfson.cloud")
	})

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body %s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "csrf_failed") {
		t.Fatalf("body = %s, want csrf_failed", rec.Body.String())
	}
	if stub.logouts() != 0 {
		t.Fatal("session must not be revoked when CSRF validation fails")
	}
}

func TestMutationRejectsMismatchedCSRFToken(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodPost, "/api/logout", sessionCookie("good"), func(r *http.Request) {
		r.Header.Set("Origin", "https://health.nacfson.cloud")
		r.Header.Set(csrfHeaderName, "not-the-cookie")
		r.AddCookie(&http.Cookie{Name: csrfCookieName, Value: "cookie-token"})
	})

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body %s)", rec.Code, rec.Body.String())
	}
}

func TestMutationRejectsForeignOrigin(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodPost, "/api/logout", sessionCookie("good"), func(r *http.Request) {
		r.Header.Set("Origin", "https://evil.example.com")
		r.Header.Set(csrfHeaderName, "token")
		r.AddCookie(&http.Cookie{Name: csrfCookieName, Value: "token"})
	})

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body %s)", rec.Code, rec.Body.String())
	}
	if stub.logouts() != 0 {
		t.Fatal("foreign origin must not reach the handler")
	}
}

func TestLogoutRevokesCentralSessionAndClearsCookie(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodPost, "/api/logout", sessionCookie("good"), func(r *http.Request) {
		r.Header.Set("Origin", "https://health.nacfson.cloud")
		r.Header.Set(csrfHeaderName, "token")
		r.AddCookie(&http.Cookie{Name: csrfCookieName, Value: "token"})
	})

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (body %s)", rec.Code, rec.Body.String())
	}
	if stub.logouts() != 1 {
		t.Fatalf("central logout calls = %d, want 1", stub.logouts())
	}
	if got := stub.logoutHeaders().Get("Cookie"); got != auth.CentralSessionCookieName+"=good" {
		t.Fatalf("logout forwarded Cookie = %q", got)
	}
	cleared := findCookie(rec, auth.CentralSessionCookieName)
	if cleared == nil || cleared.Value != "" || cleared.MaxAge >= 0 {
		t.Fatalf("session cookie not cleared: %+v", cleared)
	}
}

func findCookie(rec *httptest.ResponseRecorder, name string) *http.Cookie {
	for _, cookie := range rec.Result().Cookies() {
		if cookie.Name == name {
			return cookie
		}
	}
	return nil
}
