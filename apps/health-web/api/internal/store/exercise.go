package store

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Set types (Flutter v9 parity).
const (
	SetTypeWarmup  = "warmup"
	SetTypeWork    = "work"
	SetTypeDrop    = "drop"
	SetTypeFailure = "failure"
)

// ExerciseRecord is one logged set.
type ExerciseRecord struct {
	UUID         string    `json:"uuid"`
	RecordedAt   time.Time `json:"recorded_at"`
	ExerciseType string    `json:"exercise_type"`
	ExerciseName string    `json:"exercise_name"`
	ExerciseKey  string    `json:"exercise_key,omitempty"`
	CategoryKey  string    `json:"category_key,omitempty"`
	CurrentSet   int       `json:"current_set"`
	Weight       float64   `json:"weight"`
	Reps         int       `json:"reps"`
	RPE          float64   `json:"rpe"`
	SetType      string    `json:"set_type"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// ExerciseInput carries create/patch payloads; nil fields are left untouched.
type ExerciseInput struct {
	UUID         *string    `json:"uuid"`
	RecordedAt   *time.Time `json:"recorded_at"`
	ExerciseType *string    `json:"exercise_type"`
	ExerciseName *string    `json:"exercise_name"`
	ExerciseKey  *string    `json:"exercise_key"`
	CategoryKey  *string    `json:"category_key"`
	CurrentSet   *int       `json:"current_set"`
	Weight       *float64   `json:"weight"`
	Reps         *int       `json:"reps"`
	RPE          *float64   `json:"rpe"`
	SetType      *string    `json:"set_type"`
}

const exerciseColumns = `uuid, recorded_at, exercise_type, exercise_name,
	COALESCE(exercise_key, ''), COALESCE(category_key, ''),
	current_set, weight, reps, rpe, set_type, created_at, updated_at`

func scanExercise(row rowScanner) (ExerciseRecord, error) {
	var rec ExerciseRecord
	err := row.Scan(&rec.UUID, &rec.RecordedAt, &rec.ExerciseType, &rec.ExerciseName,
		&rec.ExerciseKey, &rec.CategoryKey, &rec.CurrentSet, &rec.Weight, &rec.Reps,
		&rec.RPE, &rec.SetType, &rec.CreatedAt, &rec.UpdatedAt)
	return rec, err
}

// ListExercise returns the caller's sets inside [r.Start, r.End), newest first.
func (s *Store) ListExercise(ctx context.Context, userID uuid.UUID, r Range) ([]ExerciseRecord, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+exerciseColumns+`
		FROM exercise_records
		WHERE user_id = $1 AND is_deleted = false AND recorded_at >= $2 AND recorded_at < $3
		ORDER BY recorded_at DESC, created_at DESC`, userID, r.Start, r.End)
	if err != nil {
		return nil, fmt.Errorf("store: list exercise: %w", err)
	}
	defer rows.Close()

	records := make([]ExerciseRecord, 0, 16)
	for rows.Next() {
		rec, err := scanExercise(rows)
		if err != nil {
			return nil, fmt.Errorf("store: scan exercise: %w", err)
		}
		records = append(records, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: iterate exercise: %w", err)
	}
	return records, nil
}

// CreateExercise inserts a set and self-heals the daily routine for its local
// date, mirroring the Flutter planner rule: logging a set enrolls the exercise
// in that day's routine when it is missing.
func (s *Store) CreateExercise(ctx context.Context, userID uuid.UUID, in ExerciseInput) (ExerciseRecord, error) {
	name := trimOrEmpty(in.ExerciseName)
	if name == "" {
		return ExerciseRecord{}, fmt.Errorf("%w: exercise_name is required", ErrInvalid)
	}
	setType, err := normalizeSetType(in.SetType)
	if err != nil {
		return ExerciseRecord{}, err
	}
	id, err := newUUID(in.UUID)
	if err != nil {
		return ExerciseRecord{}, err
	}
	if err := validateSetNumbers(in.Weight, in.Reps, in.RPE); err != nil {
		return ExerciseRecord{}, err
	}
	recordedAt := time.Now()
	if in.RecordedAt != nil {
		recordedAt = in.RecordedAt.UTC()
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return ExerciseRecord{}, fmt.Errorf("store: begin create exercise: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	rec, err := scanExercise(tx.QueryRow(ctx, `INSERT INTO exercise_records
			(uuid, user_id, recorded_at, exercise_type, exercise_name, exercise_key, category_key,
			 current_set, weight, reps, rpe, set_type)
		VALUES ($1, $2, $3, $4, $5, NULLIF($6, ''), NULLIF($7, ''), $8, $9, $10, $11, $12)
		RETURNING `+exerciseColumns,
		id, userID, recordedAt, trimOrEmpty(in.ExerciseType), name, trimOrEmpty(in.ExerciseKey),
		trimOrEmpty(in.CategoryKey), maxInt(intOrZero(in.CurrentSet), 1), floatOrZero(in.Weight),
		intOrZero(in.Reps), floatOrZero(in.RPE), setType))
	if err != nil {
		return ExerciseRecord{}, fmt.Errorf("store: create exercise: %w", err)
	}

	item := RoutineItem{
		Type:        rec.ExerciseType,
		Name:        rec.ExerciseName,
		ExerciseKey: rec.ExerciseKey,
		CategoryKey: rec.CategoryKey,
	}
	if err := s.appendRoutineItem(ctx, tx, userID, rec.RecordedAt, item); err != nil {
		return ExerciseRecord{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return ExerciseRecord{}, fmt.Errorf("store: commit create exercise: %w", err)
	}
	return rec, nil
}

// UpdateExercise patches a set in place (nil fields keep their stored value).
func (s *Store) UpdateExercise(ctx context.Context, userID, recordID uuid.UUID, in ExerciseInput) (ExerciseRecord, error) {
	if in.ExerciseName != nil && strings.TrimSpace(*in.ExerciseName) == "" {
		return ExerciseRecord{}, fmt.Errorf("%w: exercise_name must not be empty", ErrInvalid)
	}
	if err := validateSetNumbers(in.Weight, in.Reps, in.RPE); err != nil {
		return ExerciseRecord{}, err
	}
	if in.SetType != nil {
		if _, err := normalizeSetType(in.SetType); err != nil {
			return ExerciseRecord{}, err
		}
	}
	if in.CurrentSet != nil && *in.CurrentSet < 1 {
		return ExerciseRecord{}, fmt.Errorf("%w: current_set must be >= 1", ErrInvalid)
	}

	rec, err := scanExercise(s.pool.QueryRow(ctx, `UPDATE exercise_records SET
			recorded_at = COALESCE($3::timestamptz, recorded_at),
			exercise_type = COALESCE($4::text, exercise_type),
			exercise_name = COALESCE($5::text, exercise_name),
			exercise_key = CASE WHEN $6::boolean THEN NULLIF($7::text, '') ELSE exercise_key END,
			category_key = CASE WHEN $8::boolean THEN NULLIF($9::text, '') ELSE category_key END,
			current_set = COALESCE($10::integer, current_set),
			weight = COALESCE($11::double precision, weight),
			reps = COALESCE($12::integer, reps),
			rpe = COALESCE($13::double precision, rpe),
			set_type = COALESCE($14::text, set_type)
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false
		RETURNING `+exerciseColumns,
		recordID, userID, in.RecordedAt, in.ExerciseType, in.ExerciseName,
		in.ExerciseKey != nil, trimOrEmpty(in.ExerciseKey),
		in.CategoryKey != nil, trimOrEmpty(in.CategoryKey),
		in.CurrentSet, in.Weight, in.Reps, in.RPE, in.SetType))
	if errors.Is(err, pgx.ErrNoRows) {
		return ExerciseRecord{}, ErrNotFound
	}
	if err != nil {
		return ExerciseRecord{}, fmt.Errorf("store: update exercise: %w", err)
	}
	return rec, nil
}

// DeleteExercise soft-deletes a set.
func (s *Store) DeleteExercise(ctx context.Context, userID, recordID uuid.UUID) error {
	tag, err := s.pool.Exec(ctx, `UPDATE exercise_records SET is_deleted = true
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false`, recordID, userID)
	if err != nil {
		return fmt.Errorf("store: delete exercise: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func normalizeSetType(raw *string) (string, error) {
	if raw == nil || strings.TrimSpace(*raw) == "" {
		return SetTypeWork, nil
	}
	value := strings.TrimSpace(*raw)
	switch value {
	case SetTypeWarmup, SetTypeWork, SetTypeDrop, SetTypeFailure:
		return value, nil
	default:
		return "", fmt.Errorf("%w: set_type must be warmup|work|drop|failure", ErrInvalid)
	}
}

func validateSetNumbers(weight *float64, reps *int, rpe *float64) error {
	if weight != nil && (*weight < 0 || *weight > 2000) {
		return fmt.Errorf("%w: weight out of range", ErrInvalid)
	}
	if reps != nil && (*reps < 0 || *reps > 1000) {
		return fmt.Errorf("%w: reps out of range", ErrInvalid)
	}
	if rpe != nil && (*rpe < 0 || *rpe > 10) {
		return fmt.Errorf("%w: rpe must be between 0 and 10", ErrInvalid)
	}
	return nil
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
