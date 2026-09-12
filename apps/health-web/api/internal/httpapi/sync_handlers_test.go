package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSyncResourceUnknownReturns404(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	rec := do(t, handler, http.MethodGet, "/api/v1/sync/not_a_table", nil, func(r *http.Request) {
		r.Header.Set("Authorization", "Bearer native-token")
	})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 (body %s)", rec.Code, rec.Body.String())
	}
}

func TestSyncPushRequiresAuth(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	body, _ := json.Marshal(map[string]any{"items": []any{}})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/weight_records", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	assertBareUnauthorized(t, rec)
}

func TestSyncPullInvalidSince(t *testing.T) {
	stub := newCentralStub(t)
	handler := newTestHandler(t, stub)

	// nil store will panic if we get past validation — since parse fails first.
	rec := do(t, handler, http.MethodGet, "/api/v1/sync/weight_records?since=not-a-date", nil, func(r *http.Request) {
		r.Header.Set("Authorization", "Bearer native-token")
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body %s)", rec.Code, rec.Body.String())
	}
}
