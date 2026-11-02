package httpapi

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"net/http"
	"strings"
	"time"
)

// CSRF uses a host-only, readable cookie plus a matching header, because the
// session itself is an automatically-sent cookie (__Host-health_session).
const (
	csrfCookieName = "health_csrf"
	csrfHeaderName = "X-CSRF-Token"
	csrfTokenTTL   = 24 * time.Hour
)

// csrfProtection issues the CSRF cookie for authenticated requests and enforces
// it (plus an allow-listed Origin) on mutations.
func (h *Handler) csrfProtection(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := UserFromContext(r.Context()); !ok {
			next.ServeHTTP(w, r)
			return
		}

		if _, err := ensureCSRFToken(w, r); err != nil {
			writeError(w, http.StatusInternalServerError, "internal", "could not initialize csrf protection")
			return
		}

		if isMutationMethod(r.Method) {
			if !originAllowed(r.Header.Get("Origin"), h.cfg.AllowedOrigins) {
				writeError(w, http.StatusForbidden, "csrf_failed", "origin is not allowed")
				return
			}
			if !csrfTokenMatches(r) {
				writeError(w, http.StatusForbidden, "csrf_failed", "missing or mismatched CSRF token")
				return
			}
		}

		next.ServeHTTP(w, r)
	})
}

// csrfRequestValid is the full CSRF check for cookie-authenticated mutations
// that run outside the middleware (logout): allow-listed Origin plus a
// matching health_csrf cookie/header pair.
func csrfRequestValid(r *http.Request, allowedOrigins []string) bool {
	return originAllowed(r.Header.Get("Origin"), allowedOrigins) && csrfTokenMatches(r)
}

func csrfTokenMatches(r *http.Request) bool {
	cookie, err := r.Cookie(csrfCookieName)
	headerToken := strings.TrimSpace(r.Header.Get(csrfHeaderName))
	if err != nil || strings.TrimSpace(cookie.Value) == "" || headerToken == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(cookie.Value), []byte(headerToken)) == 1
}

func ensureCSRFToken(w http.ResponseWriter, r *http.Request) (string, error) {
	if cookie, err := r.Cookie(csrfCookieName); err == nil && strings.TrimSpace(cookie.Value) != "" {
		return cookie.Value, nil
	}
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	http.SetCookie(w, &http.Cookie{
		Name:     csrfCookieName,
		Value:    token,
		Path:     "/",
		MaxAge:   int(csrfTokenTTL / time.Second),
		Secure:   requestIsSecure(r),
		HttpOnly: false,
		SameSite: http.SameSiteLaxMode,
	})
	return token, nil
}

func isMutationMethod(method string) bool {
	switch method {
	case http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete:
		return true
	default:
		return false
	}
}

func originAllowed(origin string, allowedOrigins []string) bool {
	origin = strings.TrimRight(strings.TrimSpace(origin), "/")
	if origin == "" {
		return false
	}
	for _, allowed := range allowedOrigins {
		allowed = strings.TrimRight(strings.TrimSpace(allowed), "/")
		if strings.EqualFold(origin, allowed) {
			return true
		}
	}
	return false
}

func requestIsSecure(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	return strings.EqualFold(strings.TrimSpace(r.Header.Get("X-Forwarded-Proto")), "https")
}
