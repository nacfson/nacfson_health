package store

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"
)

// EnsureUser returns the health-web project account for a platform identity,
// creating it on first sign-in. Accounts themselves are owned by the platform
// (Keycloak behind the gateway); this row only binds (issuer, subject) to the
// tenant id used by every user-owned table.
func (s *Store) EnsureUser(ctx context.Context, issuer, subject string) (uuid.UUID, error) {
	issuer = strings.TrimSpace(issuer)
	subject = strings.TrimSpace(subject)
	if issuer == "" || subject == "" {
		return uuid.Nil, fmt.Errorf("%w: issuer and subject are required", ErrInvalid)
	}
	var id uuid.UUID
	err := s.pool.QueryRow(ctx, `
		INSERT INTO users (id, issuer, subject)
		VALUES ($1, $2, $3)
		ON CONFLICT (issuer, subject) DO UPDATE SET last_seen_at = now()
		RETURNING id`,
		uuid.New(), issuer, subject,
	).Scan(&id)
	if err != nil {
		return uuid.Nil, fmt.Errorf("store: ensure user: %w", err)
	}
	return id, nil
}
