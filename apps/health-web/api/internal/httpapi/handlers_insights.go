package httpapi

import (
	"net/http"
	"strings"
	"time"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

// profileResponse is the profile DTO; exists=false carries the column defaults
// (kept in sync with the user_profiles DDL) so the settings form can render an
// empty state without special-casing nulls.
type profileResponse struct {
	Exists            bool       `json:"exists"`
	Gender            string     `json:"gender"`
	Age               int        `json:"age"`
	HeightM           float64    `json:"height_m"`
	Goal              string     `json:"goal"`
	ActivityLevel     string     `json:"activity_level"`
	TrainingIntensity string     `json:"training_intensity"`
	TargetCalories    int        `json:"target_calories"`
	TargetCarbs       float64    `json:"target_carbs"`
	TargetProtein     float64    `json:"target_protein"`
	TargetFat         float64    `json:"target_fat"`
	UpdatedAt         *time.Time `json:"updated_at,omitempty"`
}

func newProfileResponse(profile store.Profile, exists bool) profileResponse {
	response := profileResponse{
		Exists:            exists,
		Gender:            profile.Gender,
		Age:               profile.Age,
		HeightM:           profile.HeightM,
		Goal:              profile.Goal,
		ActivityLevel:     profile.ActivityLevel,
		TrainingIntensity: profile.TrainingIntensity,
		TargetCalories:    profile.TargetCalories,
		TargetCarbs:       profile.TargetCarbs,
		TargetProtein:     profile.TargetProtein,
		TargetFat:         profile.TargetFat,
	}
	if exists {
		updatedAt := profile.UpdatedAt
		response.UpdatedAt = &updatedAt
	}
	return response
}

func defaultProfile() store.Profile {
	return store.Profile{
		Gender:            "male",
		Age:               30,
		HeightM:           1.7,
		Goal:              "diet",
		ActivityLevel:     "moderate",
		TrainingIntensity: "moderate",
	}
}

func (h *Handler) getProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	profile, found, err := h.store.GetProfile(r.Context(), user.ID)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	if !found {
		writeJSON(w, http.StatusOK, newProfileResponse(defaultProfile(), false))
		return
	}
	writeJSON(w, http.StatusOK, newProfileResponse(profile, true))
}

func (h *Handler) putProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var input store.ProfileInput
	if !decodeJSON(w, r, &input) {
		return
	}
	profile, err := h.store.UpsertProfile(r.Context(), user.ID, input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newProfileResponse(profile, true))
}

type recalculateTargetsBody struct {
	Weight *float64 `json:"weight"`
}

func (h *Handler) recalculateTargets(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var body recalculateTargetsBody
	if !decodeJSON(w, r, &body) {
		return
	}
	profile, err := h.store.RecalculateTargets(r.Context(), user.ID, body.Weight)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newProfileResponse(profile, true))
}

func (h *Handler) summary(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	date := strings.TrimSpace(r.URL.Query().Get("date"))
	if date == "" {
		date = h.store.LocalDate(time.Now())
	}
	summary, err := h.store.Summary(r.Context(), user.ID, date)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func (h *Handler) masterExercises(w http.ResponseWriter, r *http.Request) {
	if _, ok := requireUser(w, r); !ok {
		return
	}
	catalog, err := h.store.MasterExercises(r.Context(), r.URL.Query().Get("locale"))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, catalog)
}
