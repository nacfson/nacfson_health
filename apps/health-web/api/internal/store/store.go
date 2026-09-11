// Package store is the Postgres persistence layer for the health web API.
// Every row is owned by exactly one tenant: the AuthUser.ID from the central
// cookie session. There is no local users table.
package store

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	// ErrNotFound is returned when a row does not exist for the tenant.
	ErrNotFound = errors.New("not found")
	// ErrInvalid is returned for malformed input (maps to HTTP 400).
	ErrInvalid = errors.New("invalid input")
	// ErrNoWeight is returned when a nutrition recalculation has no weight to use.
	ErrNoWeight = errors.New("weight required")
	// ErrConflict is returned when a unique constraint would be violated.
	ErrConflict = errors.New("conflict")
)

const dateLayout = "2006-01-02"

type Store struct {
	pool *pgxpool.Pool
	loc  *time.Location
}

// New opens a pgx pool, verifies connectivity and returns a Store. loc is the
// calendar location used by all date filters (Asia/Seoul in production).
func New(ctx context.Context, databaseURL string, loc *time.Location) (*Store, error) {
	if strings.TrimSpace(databaseURL) == "" {
		return nil, errors.New("store: DATABASE_URL is required")
	}
	if loc == nil {
		loc = time.UTC
	}
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("store: parse database url: %w", err)
	}
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("store: create pool: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("store: ping database: %w", err)
	}
	return &Store{pool: pool, loc: loc}, nil
}

func (s *Store) Close() { s.pool.Close() }

func (s *Store) Ping(ctx context.Context) error { return s.pool.Ping(ctx) }

// Range is a half-open time window [Start, End).
type Range struct {
	Start time.Time
	End   time.Time
}

// DayRange resolves a list filter into absolute bounds. Either ?date=YYYY-MM-DD
// or ?from=&to= (inclusive calendar days, store timezone) is accepted.
func (s *Store) DayRange(date, from, to string) (Range, error) {
	date = strings.TrimSpace(date)
	from = strings.TrimSpace(from)
	to = strings.TrimSpace(to)

	if date != "" {
		if from != "" || to != "" {
			return Range{}, fmt.Errorf("%w: use either date or from/to", ErrInvalid)
		}
		day, err := time.ParseInLocation(dateLayout, date, s.loc)
		if err != nil {
			return Range{}, fmt.Errorf("%w: date must be YYYY-MM-DD", ErrInvalid)
		}
		return Range{Start: day, End: day.AddDate(0, 0, 1)}, nil
	}

	if from == "" && to == "" {
		return Range{}, fmt.Errorf("%w: date or from/to is required", ErrInvalid)
	}
	start := time.Date(1970, 1, 1, 0, 0, 0, 0, s.loc)
	if from != "" {
		parsed, err := time.ParseInLocation(dateLayout, from, s.loc)
		if err != nil {
			return Range{}, fmt.Errorf("%w: from must be YYYY-MM-DD", ErrInvalid)
		}
		start = parsed
	}
	end := start.AddDate(100, 0, 0)
	if to != "" {
		parsed, err := time.ParseInLocation(dateLayout, to, s.loc)
		if err != nil {
			return Range{}, fmt.Errorf("%w: to must be YYYY-MM-DD", ErrInvalid)
		}
		end = parsed.AddDate(0, 0, 1)
	}
	if !end.After(start) {
		return Range{}, fmt.Errorf("%w: to must not precede from", ErrInvalid)
	}
	return Range{Start: start, End: end}, nil
}

// Day returns local midnight for a YYYY-MM-DD calendar day.
func (s *Store) Day(date string) (time.Time, error) {
	day, err := time.ParseInLocation(dateLayout, strings.TrimSpace(date), s.loc)
	if err != nil {
		return time.Time{}, fmt.Errorf("%w: date must be YYYY-MM-DD", ErrInvalid)
	}
	return day, nil
}

// LocalDate formats an instant as a calendar day in the store timezone.
func (s *Store) LocalDate(t time.Time) string {
	return t.In(s.loc).Format(dateLayout)
}

func newUUID(raw *string) (uuid.UUID, error) {
	if raw == nil || strings.TrimSpace(*raw) == "" {
		return uuid.New(), nil
	}
	id, err := uuid.Parse(strings.TrimSpace(*raw))
	if err != nil {
		return uuid.Nil, fmt.Errorf("%w: uuid", ErrInvalid)
	}
	return id, nil
}

// ParseUUID validates a path parameter holding a uuid.
func ParseUUID(raw string) (uuid.UUID, error) {
	id, err := uuid.Parse(strings.TrimSpace(raw))
	if err != nil {
		return uuid.Nil, fmt.Errorf("%w: uuid", ErrInvalid)
	}
	return id, nil
}

func trimOrEmpty(raw *string) string {
	if raw == nil {
		return ""
	}
	return strings.TrimSpace(*raw)
}

func floatOrZero(raw *float64) float64 {
	if raw == nil {
		return 0
	}
	return *raw
}

func intOrZero(raw *int) int {
	if raw == nil {
		return 0
	}
	return *raw
}

// rowScanner is satisfied by both pgx.Row and pgx.Rows.
type rowScanner interface {
	Scan(dest ...any) error
}
