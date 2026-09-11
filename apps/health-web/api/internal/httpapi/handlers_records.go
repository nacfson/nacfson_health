package httpapi

import (
	"net/http"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

// dayRange resolves the ?date= / ?from=&to= filter shared by record lists.
func (h *Handler) dayRange(w http.ResponseWriter, r *http.Request) (store.Range, bool) {
	query := r.URL.Query()
	window, err := h.store.DayRange(query.Get("date"), query.Get("from"), query.Get("to"))
	if err != nil {
		writeStoreError(w, err)
		return store.Range{}, false
	}
	return window, true
}

// --- exercise ---------------------------------------------------------------

func (h *Handler) listExercise(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	window, ok := h.dayRange(w, r)
	if !ok {
		return
	}
	records, err := h.store.ListExercise(r.Context(), user.ID, window)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, records)
}

func (h *Handler) createExercise(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var input store.ExerciseInput
	if !decodeJSON(w, r, &input) {
		return
	}
	record, err := h.store.CreateExercise(r.Context(), user.ID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, record)
}

func (h *Handler) updateExercise(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	recordID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	var input store.ExerciseInput
	if !decodeJSON(w, r, &input) {
		return
	}
	record, err := h.store.UpdateExercise(r.Context(), user.ID, recordID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, record)
}

func (h *Handler) deleteExercise(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	recordID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteExercise(r.Context(), user.ID, recordID); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- diet -------------------------------------------------------------------

func (h *Handler) listDiet(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	window, ok := h.dayRange(w, r)
	if !ok {
		return
	}
	records, err := h.store.ListDiet(r.Context(), user.ID, window)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, records)
}

func (h *Handler) createDiet(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var input store.DietInput
	if !decodeJSON(w, r, &input) {
		return
	}
	record, err := h.store.CreateDiet(r.Context(), user.ID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, record)
}

func (h *Handler) updateDiet(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	recordID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	var input store.DietInput
	if !decodeJSON(w, r, &input) {
		return
	}
	record, err := h.store.UpdateDiet(r.Context(), user.ID, recordID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, record)
}

func (h *Handler) deleteDiet(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	recordID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteDiet(r.Context(), user.ID, recordID); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- weight -----------------------------------------------------------------

func (h *Handler) listWeight(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	window, ok := h.dayRange(w, r)
	if !ok {
		return
	}
	records, err := h.store.ListWeight(r.Context(), user.ID, window)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, records)
}

func (h *Handler) createWeight(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var input store.WeightInput
	if !decodeJSON(w, r, &input) {
		return
	}
	record, err := h.store.CreateWeight(r.Context(), user.ID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, record)
}

func (h *Handler) updateWeight(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	recordID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	var input store.WeightInput
	if !decodeJSON(w, r, &input) {
		return
	}
	record, err := h.store.UpdateWeight(r.Context(), user.ID, recordID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, record)
}

func (h *Handler) deleteWeight(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	recordID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteWeight(r.Context(), user.ID, recordID); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
