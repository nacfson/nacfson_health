package store

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/domain/atwater"
)

// DietRecord is one logged meal/food entry. TotalCalories is always derived
// from the macros server-side (Atwater 4/4/9).
type DietRecord struct {
	UUID          string    `json:"uuid"`
	RecordedAt    time.Time `json:"recorded_at"`
	MealType      string    `json:"meal_type"`
	FoodName      string    `json:"food_name"`
	Carbs         float64   `json:"carbs"`
	Protein       float64   `json:"protein"`
	Fat           float64   `json:"fat"`
	TotalCalories int       `json:"total_calories"`
	Satisfaction  int       `json:"satisfaction"`
	Memo          string    `json:"memo"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// DietInput carries create/patch payloads; any client-supplied calorie value is
// ignored on purpose.
type DietInput struct {
	UUID         *string    `json:"uuid"`
	RecordedAt   *time.Time `json:"recorded_at"`
	MealType     *string    `json:"meal_type"`
	FoodName     *string    `json:"food_name"`
	Carbs        *float64   `json:"carbs"`
	Protein      *float64   `json:"protein"`
	Fat          *float64   `json:"fat"`
	Satisfaction *int       `json:"satisfaction"`
	Memo         *string    `json:"memo"`
}

const dietColumns = `uuid, recorded_at, meal_type, food_name, carbs, protein, fat,
	total_calories, satisfaction, memo, created_at, updated_at`

func scanDiet(row rowScanner) (DietRecord, error) {
	var rec DietRecord
	err := row.Scan(&rec.UUID, &rec.RecordedAt, &rec.MealType, &rec.FoodName, &rec.Carbs,
		&rec.Protein, &rec.Fat, &rec.TotalCalories, &rec.Satisfaction, &rec.Memo,
		&rec.CreatedAt, &rec.UpdatedAt)
	return rec, err
}

// ListDiet returns the caller's diet entries inside [r.Start, r.End).
func (s *Store) ListDiet(ctx context.Context, userID uuid.UUID, r Range) ([]DietRecord, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+dietColumns+`
		FROM diet_records
		WHERE user_id = $1 AND is_deleted = false AND recorded_at >= $2 AND recorded_at < $3
		ORDER BY recorded_at DESC, created_at DESC`, userID, r.Start, r.End)
	if err != nil {
		return nil, fmt.Errorf("store: list diet: %w", err)
	}
	defer rows.Close()

	records := make([]DietRecord, 0, 16)
	for rows.Next() {
		rec, err := scanDiet(rows)
		if err != nil {
			return nil, fmt.Errorf("store: scan diet: %w", err)
		}
		records = append(records, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: iterate diet: %w", err)
	}
	return records, nil
}

// CreateDiet inserts a diet entry, deriving total_calories via Atwater.
func (s *Store) CreateDiet(ctx context.Context, userID uuid.UUID, in DietInput) (DietRecord, error) {
	foodName := trimOrEmpty(in.FoodName)
	if foodName == "" {
		return DietRecord{}, fmt.Errorf("%w: food_name is required", ErrInvalid)
	}
	if err := validateMacros(in.Carbs, in.Protein, in.Fat); err != nil {
		return DietRecord{}, err
	}
	if err := validateSatisfaction(in.Satisfaction); err != nil {
		return DietRecord{}, err
	}
	id, err := newUUID(in.UUID)
	if err != nil {
		return DietRecord{}, err
	}
	carbs, protein, fat := floatOrZero(in.Carbs), floatOrZero(in.Protein), floatOrZero(in.Fat)
	recordedAt := time.Now()
	if in.RecordedAt != nil {
		recordedAt = in.RecordedAt.UTC()
	}

	rec, err := scanDiet(s.pool.QueryRow(ctx, `INSERT INTO diet_records
			(uuid, user_id, recorded_at, meal_type, food_name, carbs, protein, fat, total_calories, satisfaction, memo)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING `+dietColumns,
		id, userID, recordedAt, trimOrEmpty(in.MealType), foodName, carbs, protein, fat,
		atwater.KcalFromMacros(carbs, protein, fat), intOrZero(in.Satisfaction), trimOrEmpty(in.Memo)))
	if err != nil {
		return DietRecord{}, fmt.Errorf("store: create diet: %w", err)
	}
	return rec, nil
}

// UpdateDiet patches a diet entry. Calories are recomputed from the merged
// macros, so a macro edit always keeps the stored calories consistent.
func (s *Store) UpdateDiet(ctx context.Context, userID, recordID uuid.UUID, in DietInput) (DietRecord, error) {
	if in.FoodName != nil && strings.TrimSpace(*in.FoodName) == "" {
		return DietRecord{}, fmt.Errorf("%w: food_name must not be empty", ErrInvalid)
	}
	if err := validateMacros(in.Carbs, in.Protein, in.Fat); err != nil {
		return DietRecord{}, err
	}
	if err := validateSatisfaction(in.Satisfaction); err != nil {
		return DietRecord{}, err
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return DietRecord{}, fmt.Errorf("store: begin update diet: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	current, err := scanDiet(tx.QueryRow(ctx, `SELECT `+dietColumns+`
		FROM diet_records WHERE uuid = $1 AND user_id = $2 AND is_deleted = false FOR UPDATE`,
		recordID, userID))
	if errors.Is(err, pgx.ErrNoRows) {
		return DietRecord{}, ErrNotFound
	}
	if err != nil {
		return DietRecord{}, fmt.Errorf("store: load diet for update: %w", err)
	}

	if in.RecordedAt != nil {
		current.RecordedAt = in.RecordedAt.UTC()
	}
	if in.MealType != nil {
		current.MealType = strings.TrimSpace(*in.MealType)
	}
	if in.FoodName != nil {
		current.FoodName = strings.TrimSpace(*in.FoodName)
	}
	if in.Carbs != nil {
		current.Carbs = *in.Carbs
	}
	if in.Protein != nil {
		current.Protein = *in.Protein
	}
	if in.Fat != nil {
		current.Fat = *in.Fat
	}
	if in.Satisfaction != nil {
		current.Satisfaction = *in.Satisfaction
	}
	if in.Memo != nil {
		current.Memo = strings.TrimSpace(*in.Memo)
	}
	current.TotalCalories = atwater.KcalFromMacros(current.Carbs, current.Protein, current.Fat)

	updated, err := scanDiet(tx.QueryRow(ctx, `UPDATE diet_records SET
			recorded_at = $3, meal_type = $4, food_name = $5, carbs = $6, protein = $7,
			fat = $8, total_calories = $9, satisfaction = $10, memo = $11
		WHERE uuid = $1 AND user_id = $2
		RETURNING `+dietColumns,
		recordID, userID, current.RecordedAt, current.MealType, current.FoodName, current.Carbs,
		current.Protein, current.Fat, current.TotalCalories, current.Satisfaction, current.Memo))
	if err != nil {
		return DietRecord{}, fmt.Errorf("store: update diet: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return DietRecord{}, fmt.Errorf("store: commit update diet: %w", err)
	}
	return updated, nil
}

// DeleteDiet soft-deletes a diet entry.
func (s *Store) DeleteDiet(ctx context.Context, userID, recordID uuid.UUID) error {
	tag, err := s.pool.Exec(ctx, `UPDATE diet_records SET is_deleted = true
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false`, recordID, userID)
	if err != nil {
		return fmt.Errorf("store: delete diet: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func validateMacros(carbs, protein, fat *float64) error {
	for _, macro := range []*float64{carbs, protein, fat} {
		if macro == nil {
			continue
		}
		if math.IsNaN(*macro) || math.IsInf(*macro, 0) || *macro < 0 || *macro > 10000 {
			return fmt.Errorf("%w: macros must be between 0 and 10000", ErrInvalid)
		}
	}
	return nil
}

func validateSatisfaction(satisfaction *int) error {
	if satisfaction == nil {
		return nil
	}
	if *satisfaction < 0 || *satisfaction > 5 {
		return fmt.Errorf("%w: satisfaction must be between 0 and 5", ErrInvalid)
	}
	return nil
}
