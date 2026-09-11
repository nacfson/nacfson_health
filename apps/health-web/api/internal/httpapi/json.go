// Package httpapi exposes the health web API. Authentication is cookie-only:
// the SPA talks to this API on the same origin as its own pages, using the
// nacfson_session cookie issued by the central auth service.
package httpapi

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

// maxBodyBytes caps request bodies (diet/exercise payloads are tiny).
const maxBodyBytes = 1 << 20

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

// writeError emits {"error":"<code>","message":"..."}; message is omitted for
// the bare 401 contract.
func writeError(w http.ResponseWriter, status int, code, message string) {
	payload := map[string]string{"error": code}
	if strings.TrimSpace(message) != "" {
		payload["message"] = message
	}
	writeJSON(w, status, payload)
}

func writeUnauthorized(w http.ResponseWriter) {
	writeError(w, http.StatusUnauthorized, "unauthorized", "")
}

// decodeJSON reads a JSON body into dst. Unknown fields are tolerated so the
// SPA can send whole client-side rows.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "malformed JSON body")
		return false
	}
	return true
}

// writeStoreError maps store sentinel errors onto the public error contract.
func writeStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not_found", "resource not found")
	case errors.Is(err, store.ErrInvalid):
		writeError(w, http.StatusBadRequest, "invalid_request", strings.TrimPrefix(err.Error(), "invalid input: "))
	case errors.Is(err, store.ErrNoWeight):
		writeError(w, http.StatusBadRequest, "invalid_request", "a body weight is required (log a weigh-in or send weight)")
	case errors.Is(err, store.ErrConflict):
		writeError(w, http.StatusConflict, "conflict", "resource already exists")
	default:
		slog.Error("api: store failure", "error", err)
		writeError(w, http.StatusInternalServerError, "internal", "internal error")
	}
}
