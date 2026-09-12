package httpapi

import (
	"net/http"
	"strings"
	"time"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

const syncMaxBodyBytes = 8 << 20 // 8 MiB — native batch pushes

type syncPushRequest struct {
	Items []store.SyncRow `json:"items"`
}

var syncResources = map[string]struct{}{
	store.SyncExerciseRecords:   {},
	store.SyncDietRecords:       {},
	store.SyncWeightRecords:     {},
	store.SyncExerciseTemplates: {},
	store.SyncFoodTemplates:     {},
	store.SyncWorkoutRoutines:   {},
}

func syncResource(w http.ResponseWriter, r *http.Request) (string, bool) {
	name := strings.TrimSpace(r.PathValue("resource"))
	if _, ok := syncResources[name]; !ok {
		writeError(w, http.StatusNotFound, "not_found", "unknown sync resource")
		return "", false
	}
	return name, true
}

// pushSync upserts a batch of rows for one syncable table (native push step).
func (h *Handler) pushSync(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	resource, ok := syncResource(w, r)
	if !ok {
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, syncMaxBodyBytes)
	var req syncPushRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.Items == nil {
		req.Items = []store.SyncRow{}
	}
	if err := h.store.UpsertSyncRows(r.Context(), user.ID, resource, req.Items); err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"upserted": len(req.Items)})
}

// pullSync returns live delta rows since ?since= (RFC3339). Empty since = full.
func (h *Handler) pullSync(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	resource, ok := syncResource(w, r)
	if !ok {
		return
	}
	var since *time.Time
	if raw := strings.TrimSpace(r.URL.Query().Get("since")); raw != "" {
		parsed, err := time.Parse(time.RFC3339Nano, raw)
		if err != nil {
			parsed, err = time.Parse(time.RFC3339, raw)
		}
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid_request", "since must be RFC3339")
			return
		}
		utc := parsed.UTC()
		since = &utc
	}
	rows, err := h.store.PullSyncRows(r.Context(), user.ID, resource, since)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	if rows == nil {
		rows = []store.SyncRow{}
	}
	writeJSON(w, http.StatusOK, rows)
}

// masterBundle returns the five master tables for native SQLite replace.
func (h *Handler) masterBundle(w http.ResponseWriter, r *http.Request) {
	if _, ok := requireUser(w, r); !ok {
		return
	}
	bundle, err := h.store.MasterBundleForNative(r.Context())
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, bundle)
}
