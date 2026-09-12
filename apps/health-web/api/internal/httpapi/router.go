package httpapi

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/auth"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/config"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

// Handler owns the API dependencies.
type Handler struct {
	cfg     config.Config
	store   *store.Store
	central *auth.CentralClient
}

// NewHandler builds the API router. Middleware order (outermost first):
// CORS → auth → CSRF → routes.
func NewHandler(cfg config.Config, st *store.Store, central *auth.CentralClient) http.Handler {
	h := &Handler{cfg: cfg, store: st, central: central}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", h.healthz)
	mux.HandleFunc("GET /readyz", h.readyz)
	mux.HandleFunc("GET /api/me", h.me)
	mux.HandleFunc("POST /api/logout", h.logout)

	mux.HandleFunc("GET /api/v1/profile", h.getProfile)
	mux.HandleFunc("PUT /api/v1/profile", h.putProfile)
	mux.HandleFunc("POST /api/v1/profile/recalculate-targets", h.recalculateTargets)

	mux.HandleFunc("GET /api/v1/exercise", h.listExercise)
	mux.HandleFunc("POST /api/v1/exercise", h.createExercise)
	mux.HandleFunc("PATCH /api/v1/exercise/{uuid}", h.updateExercise)
	mux.HandleFunc("DELETE /api/v1/exercise/{uuid}", h.deleteExercise)

	mux.HandleFunc("GET /api/v1/diet", h.listDiet)
	mux.HandleFunc("POST /api/v1/diet", h.createDiet)
	mux.HandleFunc("PATCH /api/v1/diet/{uuid}", h.updateDiet)
	mux.HandleFunc("DELETE /api/v1/diet/{uuid}", h.deleteDiet)

	mux.HandleFunc("GET /api/v1/weight", h.listWeight)
	mux.HandleFunc("POST /api/v1/weight", h.createWeight)
	mux.HandleFunc("PATCH /api/v1/weight/{uuid}", h.updateWeight)
	mux.HandleFunc("DELETE /api/v1/weight/{uuid}", h.deleteWeight)

	mux.HandleFunc("GET /api/v1/exercise-templates", h.listExerciseTemplates)
	mux.HandleFunc("POST /api/v1/exercise-templates", h.createExerciseTemplate)
	mux.HandleFunc("PATCH /api/v1/exercise-templates/{uuid}", h.updateExerciseTemplate)
	mux.HandleFunc("DELETE /api/v1/exercise-templates/{uuid}", h.deleteExerciseTemplate)

	mux.HandleFunc("GET /api/v1/food-templates", h.listFoodTemplates)
	mux.HandleFunc("POST /api/v1/food-templates", h.createFoodTemplate)
	mux.HandleFunc("DELETE /api/v1/food-templates/{uuid}", h.deleteFoodTemplate)

	mux.HandleFunc("GET /api/v1/workout-routines", h.listWorkoutRoutines)
	mux.HandleFunc("POST /api/v1/workout-routines", h.createWorkoutRoutine)
	mux.HandleFunc("PATCH /api/v1/workout-routines/{uuid}", h.updateWorkoutRoutine)
	mux.HandleFunc("DELETE /api/v1/workout-routines/{uuid}", h.deleteWorkoutRoutine)

	mux.HandleFunc("GET /api/v1/daily-routine/{date}", h.getDailyRoutine)
	mux.HandleFunc("PUT /api/v1/daily-routine/{date}", h.putDailyRoutine)

	mux.HandleFunc("GET /api/v1/master/exercises", h.masterExercises)
	mux.HandleFunc("GET /api/v1/master/bundle", h.masterBundle)

	mux.HandleFunc("POST /api/v1/sync/{resource}", h.pushSync)
	mux.HandleFunc("GET /api/v1/sync/{resource}", h.pullSync)

	mux.HandleFunc("GET /api/v1/summary", h.summary)

	mux.HandleFunc("/", h.notFound)

	return h.corsMiddleware(h.authMiddleware(h.csrfProtection(mux)))
}

// corsMiddleware answers credentialed preflights for allow-listed dev origins.
// In production the SPA is served from the same origin, so CORS is a no-op.
func (h *Handler) corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimRight(strings.TrimSpace(r.Header.Get("Origin")), "/")
		if origin != "" && originAllowed(origin, h.cfg.AllowedOrigins) {
			headers := w.Header()
			headers.Set("Access-Control-Allow-Origin", origin)
			headers.Set("Access-Control-Allow-Credentials", "true")
			headers.Add("Vary", "Origin")
			if r.Method == http.MethodOptions {
				headers.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
				headers.Set("Access-Control-Allow-Headers", "Content-Type, X-CSRF-Token, Authorization")
				headers.Set("Access-Control-Max-Age", "600")
				w.WriteHeader(http.StatusNoContent)
				return
			}
		} else if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (h *Handler) healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) readyz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if err := h.store.Ping(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "unavailable", "database unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) notFound(w http.ResponseWriter, _ *http.Request) {
	writeError(w, http.StatusNotFound, "not_found", "no such endpoint")
}

// requireUser returns the authenticated caller or writes a 401.
func requireUser(w http.ResponseWriter, r *http.Request) (auth.AuthUser, bool) {
	user, ok := UserFromContext(r.Context())
	if !ok {
		writeUnauthorized(w)
		return auth.AuthUser{}, false
	}
	return user, true
}

// pathUUID parses the {uuid} path value or writes a 400.
func pathUUID(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	id, err := store.ParseUUID(r.PathValue("uuid"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "uuid path parameter is not a valid uuid")
		return uuid.Nil, false
	}
	return id, true
}
