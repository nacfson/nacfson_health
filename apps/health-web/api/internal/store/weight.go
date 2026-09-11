package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// WeightRecord is one body-weight measurement in kilograms.
type WeightRecord struct {
	UUID       string    `json:"uuid"`
	RecordedAt time.Time `json:"recorded_at"`
	Weight     float64   `json:"weight"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// WeightInput carries create/patch payloads.
type WeightInput struct {
	UUID       *string    `json:"uuid"`
	RecordedAt *time.Time `json:"recorded_at"`
	Weight     *float64   `json:"weight"`
}

const weightColumns = `uuid, recorded_at, weight, created_at, updated_at`

func scanWeight(row rowScanner) (WeightRecord, error) {
	var rec WeightRecord
	err := row.Scan(&rec.UUID, &rec.RecordedAt, &rec.Weight, &rec.CreatedAt, &rec.UpdatedAt)
	return rec, err
}

// ListWeight returns the caller's weigh-ins inside [r.Start, r.End).
func (s *Store) ListWeight(ctx context.Context, userID uuid.UUID, r Range) ([]WeightRecord, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+weightColumns+`
		FROM weight_records
		WHERE user_id = $1 AND is_deleted = false AND recorded_at >= $2 AND recorded_at < $3
		ORDER BY recorded_at DESC, created_at DESC`, userID, r.Start, r.End)
	if err != nil {
		return nil, fmt.Errorf("store: list weight: %w", err)
	}
	defer rows.Close()

	records := make([]WeightRecord, 0, 16)
	for rows.Next() {
		rec, err := scanWeight(rows)
		if err != nil {
			return nil, fmt.Errorf("store: scan weight: %w", err)
		}
		records = append(records, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: iterate weight: %w", err)
	}
	return records, nil
}

// CreateWeight inserts a weigh-in.
func (s *Store) CreateWeight(ctx context.Context, userID uuid.UUID, in WeightInput) (WeightRecord, error) {
	if in.Weight == nil {
		return WeightRecord{}, fmt.Errorf("%w: weight is required", ErrInvalid)
	}
	if err := validateWeight(*in.Weight); err != nil {
		return WeightRecord{}, err
	}
	id, err := newUUID(in.UUID)
	if err != nil {
		return WeightRecord{}, err
	}
	recordedAt := time.Now()
	if in.RecordedAt != nil {
		recordedAt = in.RecordedAt.UTC()
	}
	rec, err := scanWeight(s.pool.QueryRow(ctx, `INSERT INTO weight_records
			(uuid, user_id, recorded_at, weight)
		VALUES ($1, $2, $3, $4)
		RETURNING `+weightColumns, id, userID, recordedAt, *in.Weight))
	if err != nil {
		return WeightRecord{}, fmt.Errorf("store: create weight: %w", err)
	}
	return rec, nil
}

// UpdateWeight patches a weigh-in.
func (s *Store) UpdateWeight(ctx context.Context, userID, recordID uuid.UUID, in WeightInput) (WeightRecord, error) {
	if in.Weight != nil {
		if err := validateWeight(*in.Weight); err != nil {
			return WeightRecord{}, err
		}
	}
	rec, err := scanWeight(s.pool.QueryRow(ctx, `UPDATE weight_records SET
			recorded_at = COALESCE($3::timestamptz, recorded_at),
			weight = COALESCE($4::double precision, weight)
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false
		RETURNING `+weightColumns, recordID, userID, in.RecordedAt, in.Weight))
	if errors.Is(err, pgx.ErrNoRows) {
		return WeightRecord{}, ErrNotFound
	}
	if err != nil {
		return WeightRecord{}, fmt.Errorf("store: update weight: %w", err)
	}
	return rec, nil
}

// DeleteWeight soft-deletes a weigh-in.
func (s *Store) DeleteWeight(ctx context.Context, userID, recordID uuid.UUID) error {
	tag, err := s.pool.Exec(ctx, `UPDATE weight_records SET is_deleted = true
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false`, recordID, userID)
	if err != nil {
		return fmt.Errorf("store: delete weight: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// LatestWeight returns the most recent weigh-in, if any.
func (s *Store) LatestWeight(ctx context.Context, userID uuid.UUID) (float64, bool, error) {
	var weight float64
	err := s.pool.QueryRow(ctx, `SELECT weight FROM weight_records
		WHERE user_id = $1 AND is_deleted = false
		ORDER BY recorded_at DESC, created_at DESC LIMIT 1`, userID).Scan(&weight)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, fmt.Errorf("store: latest weight: %w", err)
	}
	return weight, true, nil
}

func validateWeight(weight float64) error {
	if weight <= 0 || weight > 500 {
		return fmt.Errorf("%w: weight must be between 0 and 500 kg", ErrInvalid)
	}
	return nil
}
