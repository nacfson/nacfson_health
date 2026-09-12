package auth

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"
)

const CentralSessionCookieName = "nacfson_session"

var (
	ErrInvalidToken              = errors.New("invalid token")
	ErrInternalAuthNotConfigured = errors.New("internal auth not configured")
)

type AuthUser struct {
	ID    uuid.UUID
	Email string
}

type CookieSession struct {
	UserID    string    `json:"user_id"`
	Email     string    `json:"email"`
	IsAdmin   bool      `json:"is_admin"`
	ExpiresAt time.Time `json:"expires_at"`
}

// BearerSession is the GET /api/auth/session response for opaque native tokens.
type BearerSession struct {
	ExpiresAt time.Time `json:"expires_at"`
	User      struct {
		ID      string `json:"id"`
		Email   string `json:"email"`
		IsAdmin bool   `json:"is_admin"`
	} `json:"user"`
}

type CentralClient struct {
	baseURL       string
	internalURL   string
	internalToken string
	client        *http.Client
}

func NewCentralClient(publicURL, internalURL, internalToken string, client *http.Client) *CentralClient {
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	publicURL = strings.TrimRight(publicURL, "/")
	internalURL = strings.TrimRight(internalURL, "/")
	if publicURL == "" {
		publicURL = internalURL
	}
	if internalURL == "" {
		internalURL = publicURL
	}
	return &CentralClient{
		baseURL:       publicURL,
		internalURL:   internalURL,
		internalToken: strings.TrimSpace(internalToken),
		client:        client,
	}
}

func (c *CentralClient) backendURL() string {
	if c.internalURL != "" {
		return c.internalURL
	}
	return c.baseURL
}

func NormalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

// ValidateSession calls GET /api/auth/session with the caller's opaque Bearer
// token (native / non-cookie clients). Identity always comes from Auth — never
// from client X-User-* headers.
func (c *CentralClient) ValidateSession(ctx context.Context, token string) (AuthUser, BearerSession, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return AuthUser{}, BearerSession{}, ErrInvalidToken
	}

	endpoint, err := url.JoinPath(c.backendURL(), "/api/auth/session")
	if err != nil {
		return AuthUser{}, BearerSession{}, fmt.Errorf("auth: session URL: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return AuthUser{}, BearerSession{}, fmt.Errorf("auth: session request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := c.client.Do(req)
	if err != nil {
		return AuthUser{}, BearerSession{}, fmt.Errorf("auth: session failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return AuthUser{}, BearerSession{}, fmt.Errorf("auth: read session: %w", err)
	}
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return AuthUser{}, BearerSession{}, ErrInvalidToken
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return AuthUser{}, BearerSession{}, fmt.Errorf("auth: session status %d", resp.StatusCode)
	}

	var payload BearerSession
	if err := json.Unmarshal(body, &payload); err != nil {
		slog.Error("auth: decode bearer session", "error", err)
		return AuthUser{}, BearerSession{}, fmt.Errorf("auth: decode session: %w", err)
	}
	email := NormalizeEmail(payload.User.Email)
	if payload.User.ID == "" || email == "" {
		return AuthUser{}, BearerSession{}, ErrInvalidToken
	}
	if !payload.ExpiresAt.IsZero() && !payload.ExpiresAt.After(time.Now()) {
		return AuthUser{}, BearerSession{}, ErrInvalidToken
	}
	id, err := uuid.Parse(payload.User.ID)
	if err != nil {
		return AuthUser{}, BearerSession{}, ErrInvalidToken
	}
	payload.User.Email = email
	return AuthUser{ID: id, Email: email}, payload, nil
}

// LogoutBearerSession calls DELETE /api/auth/session with a Bearer token.
func (c *CentralClient) LogoutBearerSession(ctx context.Context, token string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		return ErrInvalidToken
	}
	endpoint, err := url.JoinPath(c.backendURL(), "/api/auth/session")
	if err != nil {
		return fmt.Errorf("auth: bearer logout URL: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, endpoint, nil)
	if err != nil {
		return fmt.Errorf("auth: bearer logout request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("auth: bearer logout failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return ErrInvalidToken
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("auth: bearer logout status %d", resp.StatusCode)
	}
	return nil
}

// ValidateCookieSession calls GET /api/internal/cookie-session (PN algorithm).
func (c *CentralClient) ValidateCookieSession(ctx context.Context, cookieValue string) (AuthUser, CookieSession, error) {
	if strings.TrimSpace(cookieValue) == "" {
		return AuthUser{}, CookieSession{}, ErrInvalidToken
	}
	if c.internalToken == "" {
		return AuthUser{}, CookieSession{}, ErrInternalAuthNotConfigured
	}

	endpoint, err := url.JoinPath(c.backendURL(), "/api/internal/cookie-session")
	if err != nil {
		return AuthUser{}, CookieSession{}, fmt.Errorf("auth: cookie session URL: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return AuthUser{}, CookieSession{}, fmt.Errorf("auth: cookie session request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.internalToken)
	req.AddCookie(&http.Cookie{Name: CentralSessionCookieName, Value: cookieValue})

	resp, err := c.client.Do(req)
	if err != nil {
		return AuthUser{}, CookieSession{}, fmt.Errorf("auth: cookie session failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return AuthUser{}, CookieSession{}, fmt.Errorf("auth: read cookie session: %w", err)
	}
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return AuthUser{}, CookieSession{}, ErrInvalidToken
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return AuthUser{}, CookieSession{}, fmt.Errorf("auth: cookie session status %d", resp.StatusCode)
	}

	var payload CookieSession
	if err := json.Unmarshal(body, &payload); err != nil {
		slog.Error("auth: decode cookie session", "error", err)
		return AuthUser{}, CookieSession{}, fmt.Errorf("auth: decode cookie session: %w", err)
	}
	email := NormalizeEmail(payload.Email)
	if payload.UserID == "" || email == "" || payload.ExpiresAt.IsZero() {
		return AuthUser{}, CookieSession{}, ErrInvalidToken
	}
	if !payload.ExpiresAt.After(time.Now()) {
		return AuthUser{}, CookieSession{}, ErrInvalidToken
	}
	id, err := uuid.Parse(payload.UserID)
	if err != nil {
		return AuthUser{}, CookieSession{}, ErrInvalidToken
	}
	payload.Email = email
	return AuthUser{ID: id, Email: email}, payload, nil
}

// LogoutCookieSession calls DELETE /api/auth/session with the session cookie (PN algorithm).
func (c *CentralClient) LogoutCookieSession(ctx context.Context, cookieValue string) error {
	if strings.TrimSpace(cookieValue) == "" {
		return ErrInvalidToken
	}
	endpoint, err := url.JoinPath(c.backendURL(), "/api/auth/session")
	if err != nil {
		return fmt.Errorf("auth: cookie logout URL: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, endpoint, nil)
	if err != nil {
		return fmt.Errorf("auth: cookie logout request: %w", err)
	}
	req.AddCookie(&http.Cookie{Name: CentralSessionCookieName, Value: cookieValue})

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("auth: cookie logout failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return ErrInvalidToken
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("auth: cookie logout status %d", resp.StatusCode)
	}
	return nil
}