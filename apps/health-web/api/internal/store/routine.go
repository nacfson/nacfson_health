package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// RoutineItem is one planned exercise inside a routine's items_json. The JSON
// shape is kept identical to the Flutter client (camelCase identity keys) so
// future sync work needs no translation. Snake_case input is accepted too.
type RoutineItem struct {
	Type        string `json:"type,omitempty"`
	Name        string `json:"name"`
	ExerciseKey string `json:"exerciseKey,omitempty"`
	CategoryKey string `json:"categoryKey,omitempty"`
}

// UnmarshalJSON accepts both the Flutter camelCase shape and snake_case input.
func (it *RoutineItem) UnmarshalJSON(data []byte) error {
	var raw struct {
		Type             string `json:"type"`
		ExerciseType     string `json:"exercise_type"`
		Name             string `json:"name"`
		ExerciseName     string `json:"exercise_name"`
		ExerciseKey      string `json:"exerciseKey"`
		ExerciseKeySnake string `json:"exercise_key"`
		CategoryKey      string `json:"categoryKey"`
		CategoryKeySnake string `json:"category_key"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	it.Type = strings.TrimSpace(firstNonEmpty(raw.Type, raw.ExerciseType))
	it.Name = strings.TrimSpace(firstNonEmpty(raw.Name, raw.ExerciseName))
	it.ExerciseKey = strings.TrimSpace(firstNonEmpty(raw.ExerciseKey, raw.ExerciseKeySnake))
	it.CategoryKey = strings.TrimSpace(firstNonEmpty(raw.CategoryKey, raw.CategoryKeySnake))
	return nil
}

// canonical normalizes an item and reports whether it is usable.
func (it RoutineItem) canonical() (RoutineItem, bool) {
	it.Type = strings.TrimSpace(it.Type)
	it.Name = strings.TrimSpace(it.Name)
	it.ExerciseKey = strings.TrimSpace(it.ExerciseKey)
	it.CategoryKey = strings.TrimSpace(it.CategoryKey)
	if it.Name == "" {
		return RoutineItem{}, false
	}
	return it, true
}

// DailyRoutine is the planner row for one calendar day (one row per user/day).
type DailyRoutine struct {
	Date      string        `json:"date"`
	Items     []RoutineItem `json:"items_json"`
	UpdatedAt *time.Time    `json:"updated_at,omitempty"`
}

// WorkoutRoutine is a saved routine preset.
type WorkoutRoutine struct {
	UUID      string        `json:"uuid"`
	Name      string        `json:"name"`
	Items     []RoutineItem `json:"items_json"`
	CreatedAt time.Time     `json:"created_at"`
	UpdatedAt time.Time     `json:"updated_at"`
}

// WorkoutRoutineInput carries create/patch payloads.
type WorkoutRoutineInput struct {
	UUID  *string        `json:"uuid"`
	Name  *string        `json:"name"`
	Items *[]RoutineItem `json:"items_json"`
}

// UnmarshalJSON accepts both items_json and items spellings.
func (in *WorkoutRoutineInput) UnmarshalJSON(data []byte) error {
	var raw struct {
		UUID      *string        `json:"uuid"`
		Name      *string        `json:"name"`
		ItemsJSON *[]RoutineItem `json:"items_json"`
		Items     *[]RoutineItem `json:"items"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	in.UUID = raw.UUID
	in.Name = raw.Name
	if raw.ItemsJSON != nil {
		in.Items = raw.ItemsJSON
	} else {
		in.Items = raw.Items
	}
	return nil
}

// GetDailyRoutine returns the planner row for a YYYY-MM-DD day; a missing row
// yields an empty, ready-to-render routine rather than ErrNotFound.
func (s *Store) GetDailyRoutine(ctx context.Context, userID uuid.UUID, date string) (DailyRoutine, error) {
	if _, err := s.Day(date); err != nil {
		return DailyRoutine{}, err
	}
	out := DailyRoutine{Date: date, Items: []RoutineItem{}}

	var raw string
	var updatedAt time.Time
	err := s.pool.QueryRow(ctx, `SELECT items_json::text, updated_at
		FROM daily_routine WHERE user_id = $1 AND date = $2::date`, userID, date).Scan(&raw, &updatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return out, nil
	}
	if err != nil {
		return DailyRoutine{}, fmt.Errorf("store: get daily routine: %w", err)
	}
	if err := decodeItems(raw, &out.Items); err != nil {
		return DailyRoutine{}, err
	}
	out.UpdatedAt = &updatedAt
	return out, nil
}

// PutDailyRoutine replaces the planner row for a day.
func (s *Store) PutDailyRoutine(ctx context.Context, userID uuid.UUID, date string, items []RoutineItem) (DailyRoutine, error) {
	if _, err := s.Day(date); err != nil {
		return DailyRoutine{}, err
	}
	clean := make([]RoutineItem, 0, len(items))
	for _, item := range items {
		normalized, ok := item.canonical()
		if !ok {
			return DailyRoutine{}, fmt.Errorf("%w: routine item name is required", ErrInvalid)
		}
		clean = append(clean, normalized)
	}
	payload, err := json.Marshal(clean)
	if err != nil {
		return DailyRoutine{}, fmt.Errorf("store: encode routine items: %w", err)
	}

	out := DailyRoutine{Date: date, Items: []RoutineItem{}}
	var raw string
	var updatedAt time.Time
	err = s.pool.QueryRow(ctx, `INSERT INTO daily_routine (uuid, user_id, date, items_json)
		VALUES ($1, $2, $3::date, $4::jsonb)
		ON CONFLICT (user_id, date) DO UPDATE SET items_json = EXCLUDED.items_json
		RETURNING items_json::text, updated_at`, uuid.New(), userID, date, string(payload)).
		Scan(&raw, &updatedAt)
	if err != nil {
		return DailyRoutine{}, fmt.Errorf("store: put daily routine: %w", err)
	}
	if err := decodeItems(raw, &out.Items); err != nil {
		return DailyRoutine{}, err
	}
	out.UpdatedAt = &updatedAt
	return out, nil
}

// appendRoutineItem self-heals the planner: when a set is logged for an exercise
// that the day's routine does not contain yet, the exercise is appended.
func (s *Store) appendRoutineItem(ctx context.Context, tx pgx.Tx, userID uuid.UUID, recordedAt time.Time, item RoutineItem) error {
	normalized, ok := item.canonical()
	if !ok {
		return nil
	}
	payload, err := json.Marshal(normalized)
	if err != nil {
		return fmt.Errorf("store: encode routine item: %w", err)
	}
	localDate := recordedAt.In(s.loc).Format(dateLayout)

	_, err = tx.Exec(ctx, `INSERT INTO daily_routine (uuid, user_id, date, items_json)
		VALUES ($1, $2, $3::date, jsonb_build_array($4::jsonb))
		ON CONFLICT (user_id, date) DO UPDATE
		SET items_json = (CASE WHEN jsonb_typeof(daily_routine.items_json) = 'array'
				THEN daily_routine.items_json ELSE '[]'::jsonb END) || $4::jsonb
		WHERE NOT ((CASE WHEN jsonb_typeof(daily_routine.items_json) = 'array'
				THEN daily_routine.items_json ELSE '[]'::jsonb END)
			@> jsonb_build_array(jsonb_build_object('name', $5::text)))`,
		uuid.New(), userID, localDate, string(payload), normalized.Name)
	if err != nil {
		return fmt.Errorf("store: append routine item: %w", err)
	}
	return nil
}

// ListWorkoutRoutines returns the caller's saved routine presets, newest first.
func (s *Store) ListWorkoutRoutines(ctx context.Context, userID uuid.UUID) ([]WorkoutRoutine, error) {
	rows, err := s.pool.Query(ctx, `SELECT uuid, name, items_json::text, created_at, updated_at
		FROM workout_routines WHERE user_id = $1 AND is_deleted = false
		ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("store: list workout routines: %w", err)
	}
	defer rows.Close()

	routines := make([]WorkoutRoutine, 0, 8)
	for rows.Next() {
		routine, err := scanWorkoutRoutine(rows)
		if err != nil {
			return nil, fmt.Errorf("store: scan workout routine: %w", err)
		}
		routines = append(routines, routine)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: iterate workout routines: %w", err)
	}
	return routines, nil
}

func scanWorkoutRoutine(row rowScanner) (WorkoutRoutine, error) {
	var (
		routine WorkoutRoutine
		raw     string
	)
	if err := row.Scan(&routine.UUID, &routine.Name, &raw, &routine.CreatedAt, &routine.UpdatedAt); err != nil {
		return WorkoutRoutine{}, err
	}
	if err := decodeItems(raw, &routine.Items); err != nil {
		return WorkoutRoutine{}, err
	}
	return routine, nil
}

// CreateWorkoutRoutine stores a new routine preset.
func (s *Store) CreateWorkoutRoutine(ctx context.Context, userID uuid.UUID, in WorkoutRoutineInput) (WorkoutRoutine, error) {
	name := trimOrEmpty(in.Name)
	if name == "" {
		return WorkoutRoutine{}, fmt.Errorf("%w: name is required", ErrInvalid)
	}
	id, err := newUUID(in.UUID)
	if err != nil {
		return WorkoutRoutine{}, err
	}
	payload, err := marshalItems(in.Items)
	if err != nil {
		return WorkoutRoutine{}, err
	}
	routine, err := scanWorkoutRoutine(s.pool.QueryRow(ctx, `INSERT INTO workout_routines
			(uuid, user_id, name, items_json)
		VALUES ($1, $2, $3, $4::jsonb)
		RETURNING uuid, name, items_json::text, created_at, updated_at`, id, userID, name, payload))
	if err != nil {
		return WorkoutRoutine{}, fmt.Errorf("store: create workout routine: %w", err)
	}
	return routine, nil
}

// UpdateWorkoutRoutine patches a routine preset.
func (s *Store) UpdateWorkoutRoutine(ctx context.Context, userID, routineID uuid.UUID, in WorkoutRoutineInput) (WorkoutRoutine, error) {
	if in.Name != nil && strings.TrimSpace(*in.Name) == "" {
		return WorkoutRoutine{}, fmt.Errorf("%w: name must not be empty", ErrInvalid)
	}
	payload, err := marshalItems(in.Items)
	if err != nil {
		return WorkoutRoutine{}, err
	}
	routine, err := scanWorkoutRoutine(s.pool.QueryRow(ctx, `UPDATE workout_routines SET
			name = COALESCE($3::text, name),
			items_json = COALESCE($4::jsonb, items_json)
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false
		RETURNING uuid, name, items_json::text, created_at, updated_at`,
		routineID, userID, in.Name, payload))
	if errors.Is(err, pgx.ErrNoRows) {
		return WorkoutRoutine{}, ErrNotFound
	}
	if err != nil {
		return WorkoutRoutine{}, fmt.Errorf("store: update workout routine: %w", err)
	}
	return routine, nil
}

// DeleteWorkoutRoutine soft-deletes a routine preset.
func (s *Store) DeleteWorkoutRoutine(ctx context.Context, userID, routineID uuid.UUID) error {
	tag, err := s.pool.Exec(ctx, `UPDATE workout_routines SET is_deleted = true
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false`, routineID, userID)
	if err != nil {
		return fmt.Errorf("store: delete workout routine: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// marshalItems encodes routine items for a jsonb parameter (nil when absent).
func marshalItems(items *[]RoutineItem) (any, error) {
	if items == nil {
		return nil, nil
	}
	clean := make([]RoutineItem, 0, len(*items))
	for _, item := range *items {
		normalized, ok := item.canonical()
		if !ok {
			return nil, fmt.Errorf("%w: routine item name is required", ErrInvalid)
		}
		clean = append(clean, normalized)
	}
	payload, err := json.Marshal(clean)
	if err != nil {
		return nil, fmt.Errorf("store: encode routine items: %w", err)
	}
	return string(payload), nil
}

func decodeItems(raw string, out *[]RoutineItem) error {
	items := []RoutineItem{}
	if strings.TrimSpace(raw) != "" {
		if err := json.Unmarshal([]byte(raw), &items); err != nil {
			return fmt.Errorf("store: decode routine items: %w", err)
		}
	}
	if items == nil {
		items = []RoutineItem{}
	}
	*out = items
	return nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
