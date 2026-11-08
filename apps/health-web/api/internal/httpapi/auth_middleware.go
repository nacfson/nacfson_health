package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/platformauth"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

// authMiddleware authenticates every non-public request:
//
//	__Host-health_session cookie -> web_sessions row -> gateway GET /auth
//	-> audience and (issuer, subject) must match the row -> AuthUser in context.
//
// It fails closed (research.md R6): a rejected or mismatched session is deleted
// and answered 401; an unreachable gateway or store is 503 and serves nothing.
func (h *Handler) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		discardClientIdentityHeaders(r)

		if isPublicRequest(r) {
			next.ServeHTTP(w, r)
			return
		}

		token := sessionTokenFromRequest(r)
		if token == "" {
			writeUnauthorized(w)
			return
		}
		user, ok := h.authenticate(w, r.Context(), token)
		if !ok {
			return
		}
		ctx := withSessionToken(withUser(r.Context(), user), token)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (h *Handler) authenticate(w http.ResponseWriter, ctx context.Context, token string) (AuthUser, bool) {
	sess, err := h.sessions.WebSession(ctx, token)
	if errors.Is(err, store.ErrNotFound) {
		clearSessionCookie(w)
		writeUnauthorized(w)
		return AuthUser{}, false
	}
	if err != nil {
		slog.ErrorContext(ctx, "auth.session.store_unavailable", "error", err)
		writeError(w, http.StatusServiceUnavailable, "unavailable", "session store unavailable")
		return AuthUser{}, false
	}

	confirmed, err := h.gateway.Confirm(ctx, sess.SessionHandle)
	switch {
	case errors.Is(err, platformauth.ErrRejected):
		h.endSession(ctx, w, token, "gateway_rejected")
		writeUnauthorized(w)
		return AuthUser{}, false
	case err != nil:
		slog.WarnContext(ctx, "auth.gateway.unavailable", "error", err)
		writeError(w, http.StatusServiceUnavailable, "auth_unavailable", "the sign-in service is temporarily unavailable")
		return AuthUser{}, false
	}

	if confirmed.Audience != h.cfg.Audience() {
		h.endSession(ctx, w, token, "audience_mismatch")
		writeUnauthorized(w)
		return AuthUser{}, false
	}
	if confirmed.Issuer != sess.Issuer || confirmed.Subject != sess.Subject {
		h.endSession(ctx, w, token, "identity_mismatch")
		writeUnauthorized(w)
		return AuthUser{}, false
	}

	if confirmed.RefreshedHandle != "" && confirmed.RefreshedHandle != sess.SessionHandle {
		if err := h.sessions.UpdateWebSessionHandle(ctx, token, confirmed.RefreshedHandle); err != nil {
			// The old handle stays valid until its refresh token expires
			// (revokeRefreshToken=false), so the request can still proceed.
			slog.WarnContext(ctx, "auth.session.refresh_store_failed", "error", err)
		}
	}
	return AuthUser{ID: sess.UserID}, true
}

// endSession deletes a session the gateway no longer vouches for and clears
// the browser cookie.
func (h *Handler) endSession(ctx context.Context, w http.ResponseWriter, token, reason string) {
	slog.InfoContext(ctx, "auth.session.rejected", "reason", reason)
	if err := h.sessions.DeleteWebSession(ctx, token); err != nil {
		slog.ErrorContext(ctx, "auth.session.delete_failed", "reason", reason, "error", err)
	}
	clearSessionCookie(w)
}

func sessionTokenFromRequest(r *http.Request) string {
	cookie, err := r.Cookie(sessionCookieName)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(cookie.Value)
}

// isPublicRequest reports whether a request may bypass authentication.
func isPublicRequest(r *http.Request) bool {
	path := strings.TrimRight(r.URL.Path, "/")
	if r.Method == http.MethodPost {
		// Logout authenticates itself (CSRF + session row) so it still works
		// when the gateway already rejects the session.
		return path == "/api/auth/logout"
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		return false
	}
	switch path {
	case "/healthz", "/readyz", "/api/auth/config", "/api/auth/login", "/api/auth/callback":
		return true
	default:
		return false
	}
}
