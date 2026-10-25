package httpapi

import (
	"log/slog"
	"net/http"
)

type meResponse struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
}

type authConfigResponse struct {
	AuthURL string `json:"auth_url"`
}

// authConfig is public and DB-free: it exposes only the public central Auth
// URL (never the internal URL or token). nacfson_pipeline's frontend
// startupProbe hits it through nginx `location /api/` to prove the proxy
// reaches the backend (CONTRACT_PROBES_READINESS), so it must not depend on
// the database or the central Auth service.
func (h *Handler) authConfig(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, authConfigResponse{AuthURL: h.cfg.CentralAuthURL})
}

// me is the SPA bootstrap call: it identifies the caller and (via the CSRF
// middleware) guarantees the health_csrf cookie exists for later mutations.
func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, meResponse{UserID: user.ID.String(), Email: user.Email})
}

// logout revokes the central cookie session and clears the local cookie.
func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	if cookie, ok := sessionCookieFromContext(r.Context()); ok && cookie != "" {
		if err := h.central.LogoutCookieSession(r.Context(), cookie); err != nil {
			// Best effort: the browser cookie is cleared regardless so the SPA
			// can drop back to the SSO gate.
			slog.Warn("api: central logout failed", "error", err)
		}
	}
	clearCentralSessionCookie(w)
	w.WriteHeader(http.StatusNoContent)
}
