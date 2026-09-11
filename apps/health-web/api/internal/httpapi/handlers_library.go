package httpapi

import (
	"net/http"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

// --- exercise templates -----------------------------------------------------

func (h *Handler) listExerciseTemplates(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	templates, err := h.store.ListExerciseTemplates(r.Context(), user.ID)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, templates)
}

func (h *Handler) createExerciseTemplate(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var input store.ExerciseTemplateInput
	if !decodeJSON(w, r, &input) {
		return
	}
	template, err := h.store.CreateExerciseTemplate(r.Context(), user.ID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, template)
}

func (h *Handler) updateExerciseTemplate(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	templateID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	var input store.ExerciseTemplateInput
	if !decodeJSON(w, r, &input) {
		return
	}
	template, err := h.store.UpdateExerciseTemplate(r.Context(), user.ID, templateID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, template)
}

func (h *Handler) deleteExerciseTemplate(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	templateID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteExerciseTemplate(r.Context(), user.ID, templateID); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- food templates ---------------------------------------------------------

func (h *Handler) listFoodTemplates(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	templates, err := h.store.ListFoodTemplates(r.Context(), user.ID)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, templates)
}

func (h *Handler) createFoodTemplate(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var input store.FoodTemplateInput
	if !decodeJSON(w, r, &input) {
		return
	}
	template, err := h.store.CreateFoodTemplate(r.Context(), user.ID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, template)
}

func (h *Handler) deleteFoodTemplate(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	templateID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteFoodTemplate(r.Context(), user.ID, templateID); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- workout routines -------------------------------------------------------

func (h *Handler) listWorkoutRoutines(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	routines, err := h.store.ListWorkoutRoutines(r.Context(), user.ID)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, routines)
}

func (h *Handler) createWorkoutRoutine(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var input store.WorkoutRoutineInput
	if !decodeJSON(w, r, &input) {
		return
	}
	routine, err := h.store.CreateWorkoutRoutine(r.Context(), user.ID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, routine)
}

func (h *Handler) updateWorkoutRoutine(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	routineID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	var input store.WorkoutRoutineInput
	if !decodeJSON(w, r, &input) {
		return
	}
	routine, err := h.store.UpdateWorkoutRoutine(r.Context(), user.ID, routineID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, routine)
}

func (h *Handler) deleteWorkoutRoutine(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	routineID, ok := pathUUID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteWorkoutRoutine(r.Context(), user.ID, routineID); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- daily routine ----------------------------------------------------------

// routineItemsBody accepts both items_json and items spellings.
type routineItemsBody struct {
	ItemsJSON *[]store.RoutineItem `json:"items_json"`
	Items     *[]store.RoutineItem `json:"items"`
}

func (body routineItemsBody) items() []store.RoutineItem {
	switch {
	case body.ItemsJSON != nil:
		return *body.ItemsJSON
	case body.Items != nil:
		return *body.Items
	default:
		return []store.RoutineItem{}
	}
}

func (h *Handler) getDailyRoutine(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	routine, err := h.store.GetDailyRoutine(r.Context(), user.ID, r.PathValue("date"))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, routine)
}

func (h *Handler) putDailyRoutine(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var body routineItemsBody
	if !decodeJSON(w, r, &body) {
		return
	}
	routine, err := h.store.PutDailyRoutine(r.Context(), user.ID, r.PathValue("date"), body.items())
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, routine)
}
