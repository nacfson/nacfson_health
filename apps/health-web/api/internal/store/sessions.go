package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// WebSession is a server-side browser session. The browser holds only the raw
// token (in __Host-health_session); the database stores sha256(token).
type WebSession struct {
	UserID        uuid.UUID
	Issuer        string
	Subject       string
	SessionHandle string
	ExpiresAt     time.Time
}

// NewSessionToken returns a fresh random browser session token (32 bytes,
// base64url, 43 characters).
func NewSessionToken() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", fmt.Errorf("store: session token: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

// HashSessionToken is the lookup key stored in web_sessions.id_hash.
func HashSessionToken(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

// CreateWebSession stores a session for token. The caller sets the cookie.
func (s *Store) CreateWebSession(ctx context.Context, token string, sess WebSession) error {
	if strings.TrimSpace(token) == "" || sess.UserID == uuid.Nil || strings.TrimSpace(sess.SessionHandle) == "" {
		return fmt.Errorf("%w: incomplete web session", ErrInvalid)
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO web_sessions (id_hash, user_id, issuer, subject, session_handle, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6)`,
		HashSessionToken(token), sess.UserID, sess.Issuer, sess.Subject, sess.SessionHandle, sess.ExpiresAt,
	)
	if err != nil {
		return fmt.Errorf("store: create web session: %w", err)
	}
	return nil
}

// WebSession loads an unexpired session. Unknown or expired tokens return
// ErrNotFound; an expired row is deleted on the way out.
func (s *Store) WebSession(ctx context.Context, token string) (WebSession, error) {
	if strings.TrimSpace(token) == "" {
		return WebSession{}, ErrNotFound
	}
	hash := HashSessionToken(token)
	var sess WebSession
	err := s.pool.QueryRow(ctx, `
		SELECT user_id, issuer, subject, session_handle, expires_at
		FROM web_sessions WHERE id_hash = $1`, hash,
	).Scan(&sess.UserID, &sess.Issuer, &sess.Subject, &sess.SessionHandle, &sess.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return WebSession{}, ErrNotFound
	}
	if err != nil {
		return WebSession{}, fmt.Errorf("store: load web session: %w", err)
	}
	if !sess.ExpiresAt.After(time.Now()) {
		if _, err := s.pool.Exec(ctx, `DELETE FROM web_sessions WHERE id_hash = $1`, hash); err != nil {
			return WebSession{}, fmt.Errorf("store: delete expired web session: %w", err)
		}
		return WebSession{}, ErrNotFound
	}
	return sess, nil
}

// UpdateWebSessionHandle replaces the gateway handle after a refresh.
func (s *Store) UpdateWebSessionHandle(ctx context.Context, token, handle string) error {
	if strings.TrimSpace(handle) == "" {
		return fmt.Errorf("%w: empty session handle", ErrInvalid)
	}
	if _, err := s.pool.Exec(ctx, `UPDATE web_sessions SET session_handle = $2 WHERE id_hash = $1`,
		HashSessionToken(token), handle); err != nil {
		return fmt.Errorf("store: update web session: %w", err)
	}
	return nil
}

// DeleteWebSession removes a session. Deleting a missing session is not an error.
func (s *Store) DeleteWebSession(ctx context.Context, token string) error {
	if strings.TrimSpace(token) == "" {
		return nil
	}
	if _, err := s.pool.Exec(ctx, `DELETE FROM web_sessions WHERE id_hash = $1`, HashSessionToken(token)); err != nil {
		return fmt.Errorf("store: delete web session: %w", err)
	}
	return nil
}

// PurgeExpiredWebSessions deletes every expired session and returns the count.
func (s *Store) PurgeExpiredWebSessions(ctx context.Context) (int64, error) {
	tag, err := s.pool.Exec(ctx, `DELETE FROM web_sessions WHERE expires_at <= now()`)
	if err != nil {
		return 0, fmt.Errorf("store: purge web sessions: %w", err)
	}
	return tag.RowsAffected(), nil
}
