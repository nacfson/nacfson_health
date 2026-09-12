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
	authMethodContextKey    contextKey = "authMethod"
	bearerTokenContextKey   contextKey = "authBearerToken"
)

type authMethod string

const (
	authMethodCookie authMethod = "cookie"
	authMethodBearer authMethod = "bearer"
)

func withUser(ctx context.Context, user auth.AuthUser) context.Context {
	return context.WithValue(ctx, userContextKey, user)
}

func withSessionCookie(ctx context.Context, cookieValue string) context.Context {
	return context.WithValue(ctx, sessionCookieContextKey, cookieValue)
}

func withAuthMethod(ctx context.Context, method authMethod) context.Context {
	return context.WithValue(ctx, authMethodContextKey, method)
}

func withBearerToken(ctx context.Context, token string) context.Context {
	return context.WithValue(ctx, bearerTokenContextKey, token)
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

func authMethodFromContext(ctx context.Context) (authMethod, bool) {
	method, ok := ctx.Value(authMethodContextKey).(authMethod)
	return method, ok
}

func bearerTokenFromContext(ctx context.Context) (string, bool) {
	value, ok := ctx.Value(bearerTokenContextKey).(string)
	return value, ok
}

// authMiddleware validates the central session cookie or an opaque Bearer
// token. Cookie wins when present (SPA SSO). Missing or invalid credentials
// always yield 401. Client X-User-* headers are never trusted.
func (h *Handler) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		discardClientIdentityHeaders(r)

		if isPublicRequest(r) {
			next.ServeHTTP(w, r)
			return
		}

		if cookie, err := r.Cookie(auth.CentralSessionCookieName); err == nil && strings.TrimSpace(cookie.Value) != "" {
			user, _, err := h.central.ValidateCookieSession(r.Context(), cookie.Value)
			if err != nil {
				writeAuthFailure(w, err)
				return
			}
			ctx := withAuthMethod(withSessionCookie(withUser(r.Context(), user), cookie.Value), authMethodCookie)
			next.ServeHTTP(w, r.WithContext(ctx))
			return
		}

		token := bearerToken(r)
		if token == "" {
			writeUnauthorized(w)
			return
		}
		user, _, err := h.central.ValidateSession(r.Context(), token)
		if err != nil {
			writeAuthFailure(w, err)
			return
		}
		ctx := withAuthMethod(withBearerToken(withUser(r.Context(), user), token), authMethodBearer)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func writeAuthFailure(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrInvalidToken):
		writeUnauthorized(w)
	case errors.Is(err, auth.ErrInternalAuthNotConfigured):
		slog.Error("api: central auth is not configured", "error", err)
		writeError(w, http.StatusInternalServerError, "internal", "authentication is not configured")
	default:
		slog.Error("api: session validation failed", "error", err)
		writeError(w, http.StatusServiceUnavailable, "auth_unavailable", "could not validate the session")
	}
}

func bearerToken(r *http.Request) string {
	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(header, "Bearer ") {
		return ""
	}
	return strings.TrimSpace(header[7:])
}

// isPublicRequest reports whether a request may bypass authentication.
func isPublicRequest(r *http.Request) bool {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		return false
	}
	switch strings.TrimRight(r.URL.Path, "/") {
	case "/healthz", "/readyz":
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
