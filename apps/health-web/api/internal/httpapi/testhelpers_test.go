package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/config"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/platformauth"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

const (
	testIssuer   = "https://auth.nacfson.cloud/realms/platform"
	testAudience = "project-health"
	testOrigin   = "https://health.nacfson.cloud"
)

// fakeGateway implements Gateway in memory. Handles map to identities; tests
// tweak the error/override fields to drive each failure branch.
type fakeGateway struct {
	mu sync.Mutex

	// tickets: ticket -> exchange result
	tickets     map[string]platformauth.Exchanged
	exchangeErr error

	// handles: session handle -> confirmed identity
	handles    map[string]platformauth.Confirmed
	confirmErr error

	revokeErr error

	exchanged []string
	confirmed []string
	revoked   []string
}

func newFakeGateway() *fakeGateway {
	return &fakeGateway{
		tickets: map[string]platformauth.Exchanged{},
		handles: map[string]platformauth.Confirmed{},
	}
}

// signIn registers a ticket and its handle for subject.
func (g *fakeGateway) signIn(ticket, handle, subject string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.tickets[ticket] = platformauth.Exchanged{
		SessionHandle: handle, Issuer: testIssuer, Subject: subject, Audience: testAudience, ExpiresIn: time.Hour,
	}
	g.handles[handle] = platformauth.Confirmed{Issuer: testIssuer, Subject: subject, Audience: testAudience}
}

func (g *fakeGateway) Exchange(_ context.Context, ticket string) (platformauth.Exchanged, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.exchanged = append(g.exchanged, ticket)
	if g.exchangeErr != nil {
		return platformauth.Exchanged{}, g.exchangeErr
	}
	ex, ok := g.tickets[ticket]
	if !ok {
		return platformauth.Exchanged{}, platformauth.ErrRejected
	}
	delete(g.tickets, ticket) // single use
	return ex, nil
}

func (g *fakeGateway) Confirm(_ context.Context, handle string) (platformauth.Confirmed, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.confirmed = append(g.confirmed, handle)
	if g.confirmErr != nil {
		return platformauth.Confirmed{}, g.confirmErr
	}
	c, ok := g.handles[handle]
	if !ok {
		return platformauth.Confirmed{}, platformauth.ErrRejected
	}
	return c, nil
}

func (g *fakeGateway) Revoke(_ context.Context, handle string) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.revoked = append(g.revoked, handle)
	if g.revokeErr != nil {
		return g.revokeErr
	}
	delete(g.handles, handle)
	return nil
}

func (g *fakeGateway) calls() (exchanged, confirmed, revoked int) {
	g.mu.Lock()
	defer g.mu.Unlock()
	return len(g.exchanged), len(g.confirmed), len(g.revoked)
}

// fakeSessions implements SessionStore in memory, keyed by raw token.
type fakeSessions struct {
	mu       sync.Mutex
	users    map[string]uuid.UUID // issuer|subject -> id
	sessions map[string]store.WebSession
	failAll  error
}

func newFakeSessions() *fakeSessions {
	return &fakeSessions{users: map[string]uuid.UUID{}, sessions: map[string]store.WebSession{}}
}

func (s *fakeSessions) EnsureUser(_ context.Context, issuer, subject string) (uuid.UUID, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failAll != nil {
		return uuid.Nil, s.failAll
	}
	key := issuer + "|" + subject
	if id, ok := s.users[key]; ok {
		return id, nil
	}
	id := uuid.New()
	s.users[key] = id
	return id, nil
}

func (s *fakeSessions) CreateWebSession(_ context.Context, token string, sess store.WebSession) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failAll != nil {
		return s.failAll
	}
	s.sessions[token] = sess
	return nil
}

func (s *fakeSessions) WebSession(_ context.Context, token string) (store.WebSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failAll != nil {
		return store.WebSession{}, s.failAll
	}
	sess, ok := s.sessions[token]
	if !ok || !sess.ExpiresAt.After(time.Now()) {
		delete(s.sessions, token)
		return store.WebSession{}, store.ErrNotFound
	}
	return sess, nil
}

func (s *fakeSessions) UpdateWebSessionHandle(_ context.Context, token, handle string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess, ok := s.sessions[token]
	if ok {
		sess.SessionHandle = handle
		s.sessions[token] = sess
	}
	return nil
}

func (s *fakeSessions) DeleteWebSession(_ context.Context, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sessions, token)
	return nil
}

func (s *fakeSessions) get(token string) (store.WebSession, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess, ok := s.sessions[token]
	return sess, ok
}

func (s *fakeSessions) count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.sessions)
}

// seed stores a ready session for subject under token, backed by handle.
func (s *fakeSessions) seed(t *testing.T, g *fakeGateway, token, handle, subject string) uuid.UUID {
	t.Helper()
	g.mu.Lock()
	g.handles[handle] = platformauth.Confirmed{Issuer: testIssuer, Subject: subject, Audience: testAudience}
	g.mu.Unlock()
	id, _ := s.EnsureUser(context.Background(), testIssuer, subject)
	if err := s.CreateWebSession(context.Background(), token, store.WebSession{
		UserID: id, Issuer: testIssuer, Subject: subject, SessionHandle: handle, ExpiresAt: time.Now().Add(time.Hour),
	}); err != nil {
		t.Fatal(err)
	}
	return id
}

type testEnv struct {
	handler  http.Handler
	gateway  *fakeGateway
	sessions *fakeSessions
}

// newTestEnv wires the real router against fakes. The data store is nil, so
// any test that reaches a data route would panic: auth tests must stop first.
func newTestEnv(t *testing.T) *testEnv {
	t.Helper()
	cfg := config.Config{
		AppAddr:        ":0",
		PublicAppURL:   testOrigin,
		PublicAuthURL:  "https://auth.nacfson.cloud",
		GatewayAuthURL: "http://gateway.identity.svc:8080/auth",
		AllowedOrigins: []string{testOrigin},
	}
	g := newFakeGateway()
	s := newFakeSessions()
	return &testEnv{handler: NewHandler(cfg, nil, s, g), gateway: g, sessions: s}
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
	return &http.Cookie{Name: sessionCookieName, Value: value}
}

func withCSRF(r *http.Request) {
	r.Header.Set("Origin", testOrigin)
	r.Header.Set(csrfHeaderName, "csrf-token")
	r.AddCookie(&http.Cookie{Name: csrfCookieName, Value: "csrf-token"})
}

func findCookie(rec *httptest.ResponseRecorder, name string) *http.Cookie {
	for _, cookie := range rec.Result().Cookies() {
		if cookie.Name == name {
			return cookie
		}
	}
	return nil
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

func assertCookieCleared(t *testing.T, rec *httptest.ResponseRecorder, name string) {
	t.Helper()
	c := findCookie(rec, name)
	if c == nil || c.Value != "" || c.MaxAge >= 0 {
		t.Fatalf("%s not cleared: %+v", name, c)
	}
}
