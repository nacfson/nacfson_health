package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/auth"
)

type contextKey string

const (
	userContextKey          contextKey = "authUser"
	sessionCookieContextKey contextKey = "authSessionCookie"
)

func withUser(ctx context.Context, user auth.AuthUser) context.Context {
	return context.WithValue(ctx, userContextKey, user)
}

func withSessionCookie(ctx context.Context, cookieValue string) context.Context {
	return context.WithValue(ctx, sessionCookieContextKey, cookieValue)
}

// UserFromContext returns the authenticated caller placed there by the auth
// middleware. The user ID is the tenant key for every SQL statement.
func UserFromContext(ctx context.Context) (auth.AuthUser, bool) {
	user, ok := ctx.Value(userContextKey).(auth.AuthUser)
	return user, ok
}

func sessionCookieFromContext(ctx context.Context) (string, bool) {
	value, ok := ctx.Value(sessionCookieContextKey).(string)
	return value, ok
}

// authMiddleware validates the central session cookie. There is no bearer path
// for the web MVP: a missing or invalid cookie is always 401.
func (h *Handler) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Never trust identity headers: identity comes from the cookie check only.
		discardClientIdentityHeaders(r)

		if isPublicRequest(r) {
			next.ServeHTTP(w, r)
			return
		}

		cookie, err := r.Cookie(auth.CentralSessionCookieName)
		if err != nil || strings.TrimSpace(cookie.Value) == "" {
			writeUnauthorized(w)
			return
		}

		user, _, err := h.central.ValidateCookieSession(r.Context(), cookie.Value)
		if err != nil {
			switch {
			case errors.Is(err, auth.ErrInvalidToken):
				writeUnauthorized(w)
			case errors.Is(err, auth.ErrInternalAuthNotConfigured):
				slog.Error("api: central auth is not configured", "error", err)
				writeError(w, http.StatusInternalServerError, "internal", "authentication is not configured")
			default:
				slog.Error("api: cookie session validation failed", "error", err)
				writeError(w, http.StatusServiceUnavailable, "auth_unavailable", "could not validate the session")
			}
			return
		}

		ctx := withSessionCookie(withUser(r.Context(), user), cookie.Value)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// isPublicRequest reports whether a request may bypass authentication.
func isPublicRequest(r *http.Request) bool {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		return false
	}
	switch strings.TrimRight(r.URL.Path, "/") {
	case "/healthz", "/readyz", "/api/auth/config":
		return true
	default:
		return false
	}
}

// discardClientIdentityHeaders strips any spoofed identity headers. The nginx
// layer clears these too; this is the authoritative guard.
func discardClientIdentityHeaders(r *http.Request) {
	r.Header.Del("X-User-Id")
	r.Header.Del("X-User-Email")
	r.Header.Del("X-User-Roles")
}
