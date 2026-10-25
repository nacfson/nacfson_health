package httpapi

import (
	"encoding/json"
	"net/http"
	"testing"
)

// GET /api/auth/config backs the nacfson_pipeline frontend startupProbe
// (CONTRACT_PROBES_READINESS: a public, DB-free `/api/...` route that proves the
// nginx `/api/` proxy reaches the backend). It must answer without a session,
// without the central Auth service, and without the database.
func TestAuthConfigIsPublicAndDBFree(t *testing.T) {
	stub := newCentralStub(t)
	// newTestHandler wires a nil store: any DB access would panic.
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/api/auth/config", nil, nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", rec.Code, rec.Body.String())
	}
	var body struct {
		AuthURL string `json:"auth_url"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body %q: %v", rec.Body.String(), err)
	}
	if body.AuthURL != "https://auth.nacfson.cloud" {
		t.Fatalf("auth_url = %q, want public central auth URL", body.AuthURL)
	}
	if stub.validateHeaders() != nil {
		t.Fatal("central auth was called; the probe route must not depend on it")
	}
	if len(rec.Result().Cookies()) != 0 {
		t.Fatalf("unexpected cookies on public route: %v", rec.Result().Cookies())
	}
}

func TestAuthConfigIgnoresInvalidSessionCookie(t *testing.T) {
	stub := newCentralStub(t)
	stub.sessionStatus = http.StatusUnauthorized
	stub.sessionBody = `{"error":"unauthorized"}`
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/api/auth/config", sessionCookie("stale"), nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", rec.Code, rec.Body.String())
	}
	if stub.validateHeaders() != nil {
		t.Fatal("central auth was called for a public route")
	}
}

func TestAuthConfigRejectsMutations(t *testing.T) {
	handler := newTestHandler(t, newCentralStub(t))

	rec := do(t, handler, http.MethodPost, "/api/auth/config", nil, nil)

	assertBareUnauthorized(t, rec)
}
