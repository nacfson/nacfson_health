package httpapi

import (
	"context"
	"net/http"

	"github.com/google/uuid"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/platformauth"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

// AuthUser is the authenticated caller. ID is the health-web project account
// bound to the platform identity (issuer, subject); it is the tenant key for
// every SQL statement. There is deliberately no email.
type AuthUser struct {
	ID uuid.UUID
}

// SessionStore is the slice of the store the auth layer needs. *store.Store
// implements it; tests use an in-memory fake.
type SessionStore interface {
	EnsureUser(ctx context.Context, issuer, subject string) (uuid.UUID, error)
	CreateWebSession(ctx context.Context, token string, sess store.WebSession) error
	WebSession(ctx context.Context, token string) (store.WebSession, error)
	UpdateWebSessionHandle(ctx context.Context, token, handle string) error
	DeleteWebSession(ctx context.Context, token string) error
}

// Gateway is the platform sign-in gateway. *platformauth.Client implements it.
type Gateway interface {
	Exchange(ctx context.Context, ticket string) (platformauth.Exchanged, error)
	Confirm(ctx context.Context, handle string) (platformauth.Confirmed, error)
	Revoke(ctx context.Context, handle string) error
}

type contextKey string

const (
	userContextKey         contextKey = "authUser"
	sessionTokenContextKey contextKey = "authSessionToken"
)

func withUser(ctx context.Context, user AuthUser) context.Context {
	return context.WithValue(ctx, userContextKey, user)
}

func withSessionToken(ctx context.Context, token string) context.Context {
	return context.WithValue(ctx, sessionTokenContextKey, token)
}

// UserFromContext returns the authenticated caller placed there by the auth
// middleware.
func UserFromContext(ctx context.Context) (AuthUser, bool) {
	user, ok := ctx.Value(userContextKey).(AuthUser)
	return user, ok
}

// discardClientIdentityHeaders strips identity a client may try to assert.
// Identity comes only from the session row confirmed by the gateway. Traefik's
// platform/strip-forged-headers and nginx clear some of these too; this is the
// authoritative guard.
func discardClientIdentityHeaders(r *http.Request) {
	for _, h := range []string{
		"X-User-Id", "X-User-Email", "X-User-Roles",
		"X-User-Subject", "X-User-Issuer", "X-Project-Audience",
		"Authorization",
	} {
		r.Header.Del(h)
	}
}
