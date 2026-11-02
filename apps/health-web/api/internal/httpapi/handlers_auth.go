package httpapi

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/platformauth"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

// Browser cookies (data-model.md). The __Host- prefix forces Secure, Path=/
// and no Domain, so neither cookie is ever shared with sibling subdomains.
const (
	sessionCookieName = "__Host-health_session"
	loginCookieName   = "__Host-health_login"
	loginCookieTTL    = 10 * time.Minute
	maxNextLength     = 512
)

type authConfigResponse struct {
	LoginURL string `json:"login_url"`
}

type meResponse struct {
	UserID string `json:"user_id"`
}

type logoutResponse struct {
	Status   string `json:"status"`
	Platform string `json:"platform"`
}

// authConfig is public, DB-free and gateway-free. nacfson_pipeline's frontend
// startupProbe hits it through nginx `location /api/` to prove the proxy
// reaches the backend (CONTRACT_PROBES_READINESS), so it must stay that way.
func (h *Handler) authConfig(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, authConfigResponse{LoginURL: "/api/auth/login"})
}

// login starts sign-in: it binds the attempt to this browser with a nonce
// cookie and sends the browser to the platform gateway's /oauth/start. The
// gateway returns to /api/auth/callback with a one-time ticket.
func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	nonce, err := randomHex(16)
	if err != nil {
		slog.Error("auth.login.nonce_failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal", "could not start sign-in")
		return
	}
	setCookie(w, loginCookieName, nonce, int(loginCookieTTL/time.Second))

	q := url.Values{}
	q.Set("pa_bind", bindDigest(nonce))
	if next := sanitizeNext(r.URL.Query().Get("next")); next != "/" {
		q.Set("next", next)
	}
	callback := h.cfg.AppOrigin() + "/api/auth/callback?" + q.Encode()
	target := h.cfg.AuthOrigin() + "/oauth/start?return=" + url.QueryEscape(callback)

	slog.Info("auth.login.start")
	w.Header().Set("Cache-Control", "no-store")
	http.Redirect(w, r, target, http.StatusFound)
}

// callback finishes sign-in. Every failure lands on the SPA sign-in screen
// with a reason (?auth=failed|unavailable); nothing is served without a
// redeemed, audience-checked ticket.
func (h *Handler) callback(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	nonceCookie, _ := r.Cookie(loginCookieName)
	clearCookie(w, loginCookieName)

	fail := func(reason, outcome string) {
		slog.Warn("auth.callback.failed", "reason", reason)
		http.Redirect(w, r, "/?auth="+outcome, http.StatusFound)
	}

	query := r.URL.Query()
	ticket := strings.TrimSpace(query.Get("ticket"))
	if ticket == "" {
		fail("missing_ticket", "failed")
		return
	}
	expected := strings.TrimSpace(query.Get("pa_bind"))
	if nonceCookie == nil || strings.TrimSpace(nonceCookie.Value) == "" || expected == "" ||
		subtle.ConstantTimeCompare([]byte(bindDigest(nonceCookie.Value)), []byte(expected)) != 1 {
		// Login CSRF guard: the ticket is never redeemed for a browser that did
		// not start this sign-in.
		fail("binding_mismatch", "failed")
		return
	}

	exchanged, err := h.gateway.Exchange(r.Context(), ticket)
	switch {
	case errors.Is(err, platformauth.ErrRejected):
		fail("ticket_rejected", "failed")
		return
	case err != nil:
		slog.Warn("auth.gateway.unavailable", "step", "exchange", "error", err)
		fail("gateway_unavailable", "unavailable")
		return
	}
	if exchanged.Audience != h.cfg.Audience() {
		fail("audience_mismatch", "failed")
		return
	}

	userID, err := h.sessions.EnsureUser(r.Context(), exchanged.Issuer, exchanged.Subject)
	if err != nil {
		slog.Error("auth.callback.store_failed", "step", "ensure_user", "error", err)
		fail("store_error", "unavailable")
		return
	}
	token, err := store.NewSessionToken()
	if err != nil {
		slog.Error("auth.callback.token_failed", "error", err)
		fail("token_error", "unavailable")
		return
	}
	err = h.sessions.CreateWebSession(r.Context(), token, store.WebSession{
		UserID:        userID,
		Issuer:        exchanged.Issuer,
		Subject:       exchanged.Subject,
		SessionHandle: exchanged.SessionHandle,
		ExpiresAt:     time.Now().Add(exchanged.ExpiresIn),
	})
	if err != nil {
		slog.Error("auth.callback.store_failed", "step", "create_session", "error", err)
		fail("store_error", "unavailable")
		return
	}

	// Replace any session this browser already had.
	if old := sessionTokenFromRequest(r); old != "" && old != token {
		if err := h.sessions.DeleteWebSession(r.Context(), old); err != nil {
			slog.Warn("auth.callback.old_session_delete_failed", "error", err)
		}
	}
	setCookie(w, sessionCookieName, token, int(exchanged.ExpiresIn/time.Second))

	slog.Info("auth.callback.ok", "user_id", userID.String())
	http.Redirect(w, r, sanitizeNext(query.Get("next")), http.StatusFound)
}

// me is the SPA bootstrap call: it identifies the caller and (via the CSRF
// middleware) guarantees the health_csrf cookie exists for later mutations.
func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, meResponse{UserID: user.ID.String()})
}

// logout revokes the platform session (platform-wide sign-out) and always
// ends this browser's health-web session.
func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	if !csrfRequestValid(r, h.cfg.AllowedOrigins) {
		writeError(w, http.StatusForbidden, "csrf_failed", "missing or mismatched CSRF token")
		return
	}

	platform := "none"
	if token := sessionTokenFromRequest(r); token != "" {
		sess, err := h.sessions.WebSession(r.Context(), token)
		switch {
		case err == nil:
			if err := h.gateway.Revoke(r.Context(), sess.SessionHandle); err != nil {
				slog.Warn("auth.logout.revoke_failed", "error", err)
				platform = "unconfirmed"
			} else {
				platform = "revoked"
			}
		case errors.Is(err, store.ErrNotFound):
			// Already gone (expired or rejected earlier): nothing to revoke.
		default:
			slog.Error("auth.logout.store_failed", "error", err)
			platform = "unconfirmed"
		}
		if err := h.sessions.DeleteWebSession(r.Context(), token); err != nil {
			slog.Error("auth.logout.delete_failed", "error", err)
		}
	}
	clearSessionCookie(w)

	slog.Info("auth.logout", "platform", platform)
	writeJSON(w, http.StatusOK, logoutResponse{Status: "signed_out", Platform: platform})
}

// sanitizeNext keeps a post-sign-in target inside this site. Anything that is
// not a plain absolute path (a scheme, a host, "//", "\", control characters,
// or an API path) becomes "/".
func sanitizeNext(raw string) string {
	next := strings.TrimSpace(raw)
	if next == "" || len(next) > maxNextLength || !strings.HasPrefix(next, "/") ||
		strings.HasPrefix(next, "//") || strings.ContainsAny(next, `\`) {
		return "/"
	}
	for _, r := range next {
		if unicode.IsControl(r) {
			return "/"
		}
	}
	u, err := url.Parse(next)
	if err != nil || u.Scheme != "" || u.Host != "" || u.User != nil {
		return "/"
	}
	if u.Path == "/api" || strings.HasPrefix(u.Path, "/api/") {
		return "/"
	}
	return next
}

func bindDigest(nonce string) string {
	sum := sha256.Sum256([]byte(nonce))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func randomHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func setCookie(w http.ResponseWriter, name, value string, maxAge int) {
	http.SetCookie(w, &http.Cookie{
		Name:     name,
		Value:    value,
		Path:     "/",
		MaxAge:   maxAge,
		Secure:   true,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
}

func clearCookie(w http.ResponseWriter, name string) {
	http.SetCookie(w, &http.Cookie{
		Name:     name,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		Expires:  time.Unix(1, 0),
		Secure:   true,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
}

func clearSessionCookie(w http.ResponseWriter) { clearCookie(w, sessionCookieName) }
