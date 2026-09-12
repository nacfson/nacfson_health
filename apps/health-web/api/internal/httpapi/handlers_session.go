package httpapi

import (
	"log/slog"
	"net/http"
)

type meResponse struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
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

// logout revokes the central session (cookie or Bearer) and clears the SSO
// cookie when present.
func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	if method, ok := authMethodFromContext(r.Context()); ok && method == authMethodBearer {
		if token, ok := bearerTokenFromContext(r.Context()); ok && token != "" {
			if err := h.central.LogoutBearerSession(r.Context(), token); err != nil {
				slog.Warn("api: central bearer logout failed", "error", err)
			}
		}
		w.WriteHeader(http.StatusNoContent)
		return
	}
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
