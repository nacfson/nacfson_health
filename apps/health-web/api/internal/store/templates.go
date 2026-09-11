package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/domain/atwater"
)

// ExerciseTemplate is a saved exercise preset.
type ExerciseTemplate struct {
	UUID                string    `json:"uuid"`
	Name                string    `json:"name"`
	ExerciseType        string    `json:"exercise_type"`
	ExerciseKey         string    `json:"exercise_key,omitempty"`
	CategoryKey         string    `json:"category_key,omitempty"`
	RestSecondsOverride *int      `json:"rest_seconds_override,omitempty"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
}

// ExerciseTemplateInput carries create/patch payloads. For
// rest_seconds_override: nil keeps the stored value, 0 clears it (NULL).
type ExerciseTemplateInput struct {
	UUID                *string `json:"uuid"`
	Name                *string `json:"name"`
	ExerciseType        *string `json:"exercise_type"`
	ExerciseKey         *string `json:"exercise_key"`
	CategoryKey         *string `json:"category_key"`
	RestSecondsOverride *int    `json:"rest_seconds_override"`
}

// FoodTemplate is a saved food preset; calories follow the macros (Atwater).
type FoodTemplate struct {
	UUID      string    `json:"uuid"`
	Name      string    `json:"name"`
	Carbs     float64   `json:"carbs"`
	Protein   float64   `json:"protein"`
	Fat       float64   `json:"fat"`
	Calories  int       `json:"calories"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// FoodTemplateInput carries create payloads.
type FoodTemplateInput struct {
	UUID    *string  `json:"uuid"`
	Name    *string  `json:"name"`
	Carbs   *float64 `json:"carbs"`
	Protein *float64 `json:"protein"`
	Fat     *float64 `json:"fat"`
}

const exerciseTemplateColumns = `uuid, name, exercise_type,
	COALESCE(exercise_key, ''), COALESCE(category_key, ''), rest_seconds_override,
	created_at, updated_at`

func scanExerciseTemplate(row rowScanner) (ExerciseTemplate, error) {
	var (
		tmpl ExerciseTemplate
		rest sql.NullInt64
	)
	if err := row.Scan(&tmpl.UUID, &tmpl.Name, &tmpl.ExerciseType, &tmpl.ExerciseKey,
		&tmpl.CategoryKey, &rest, &tmpl.CreatedAt, &tmpl.UpdatedAt); err != nil {
		return ExerciseTemplate{}, err
	}
	if rest.Valid {
		value := int(rest.Int64)
		tmpl.RestSecondsOverride = &value
	}
	return tmpl, nil
}

// ListExerciseTemplates returns the caller's exercise presets, newest first.
func (s *Store) ListExerciseTemplates(ctx context.Context, userID uuid.UUID) ([]ExerciseTemplate, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+exerciseTemplateColumns+`
		FROM exercise_templates WHERE user_id = $1 AND is_deleted = false
		ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("store: list exercise templates: %w", err)
	}
	defer rows.Close()

	templates := make([]ExerciseTemplate, 0, 16)
	for rows.Next() {
		tmpl, err := scanExerciseTemplate(rows)
		if err != nil {
			return nil, fmt.Errorf("store: scan exercise template: %w", err)
		}
		templates = append(templates, tmpl)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: iterate exercise templates: %w", err)
	}
	return templates, nil
}

// CreateExerciseTemplate inserts an exercise preset. A custom template keeps
// exercise_key/category_key NULL (Flutter v12-8 semantics).
func (s *Store) CreateExerciseTemplate(ctx context.Context, userID uuid.UUID, in ExerciseTemplateInput) (ExerciseTemplate, error) {
	name := trimOrEmpty(in.Name)
	if name == "" {
		return ExerciseTemplate{}, fmt.Errorf("%w: name is required", ErrInvalid)
	}
	if err := validateRestOverride(in.RestSecondsOverride); err != nil {
		return ExerciseTemplate{}, err
	}
	id, err := newUUID(in.UUID)
	if err != nil {
		return ExerciseTemplate{}, err
	}
	tmpl, err := scanExerciseTemplate(s.pool.QueryRow(ctx, `INSERT INTO exercise_templates
			(uuid, user_id, name, exercise_type, exercise_key, category_key, rest_seconds_override)
		VALUES ($1, $2, $3, $4, NULLIF($5, ''), NULLIF($6, ''), NULLIF($7, 0))
		RETURNING `+exerciseTemplateColumns,
		id, userID, name, trimOrEmpty(in.ExerciseType), trimOrEmpty(in.ExerciseKey),
		trimOrEmpty(in.CategoryKey), intOrZero(in.RestSecondsOverride)))
	if err != nil {
		return ExerciseTemplate{}, wrapTemplateWriteError("create exercise template", err)
	}
	return tmpl, nil
}

// UpdateExerciseTemplate patches an exercise preset.
func (s *Store) UpdateExerciseTemplate(ctx context.Context, userID, templateID uuid.UUID, in ExerciseTemplateInput) (ExerciseTemplate, error) {
	if in.Name != nil && strings.TrimSpace(*in.Name) == "" {
		return ExerciseTemplate{}, fmt.Errorf("%w: name must not be empty", ErrInvalid)
	}
	if err := validateRestOverride(in.RestSecondsOverride); err != nil {
		return ExerciseTemplate{}, err
	}
	tmpl, err := scanExerciseTemplate(s.pool.QueryRow(ctx, `UPDATE exercise_templates SET
			name = COALESCE($3::text, name),
			exercise_type = COALESCE($4::text, exercise_type),
			exercise_key = CASE WHEN $5::boolean THEN NULLIF($6::text, '') ELSE exercise_key END,
			category_key = CASE WHEN $7::boolean THEN NULLIF($8::text, '') ELSE category_key END,
			rest_seconds_override = CASE WHEN $9::boolean THEN NULLIF($10::integer, 0) ELSE rest_seconds_override END
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false
		RETURNING `+exerciseTemplateColumns,
		templateID, userID, in.Name, in.ExerciseType,
		in.ExerciseKey != nil, trimOrEmpty(in.ExerciseKey),
		in.CategoryKey != nil, trimOrEmpty(in.CategoryKey),
		in.RestSecondsOverride != nil, intOrZero(in.RestSecondsOverride)))
	if errors.Is(err, pgx.ErrNoRows) {
		return ExerciseTemplate{}, ErrNotFound
	}
	if err != nil {
		return ExerciseTemplate{}, wrapTemplateWriteError("update exercise template", err)
	}
	return tmpl, nil
}

// DeleteExerciseTemplate soft-deletes an exercise preset.
func (s *Store) DeleteExerciseTemplate(ctx context.Context, userID, templateID uuid.UUID) error {
	tag, err := s.pool.Exec(ctx, `UPDATE exercise_templates SET is_deleted = true
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false`, templateID, userID)
	if err != nil {
		return fmt.Errorf("store: delete exercise template: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

const foodTemplateColumns = `uuid, name, carbs, protein, fat, calories, created_at, updated_at`

func scanFoodTemplate(row rowScanner) (FoodTemplate, error) {
	var tmpl FoodTemplate
	err := row.Scan(&tmpl.UUID, &tmpl.Name, &tmpl.Carbs, &tmpl.Protein, &tmpl.Fat,
		&tmpl.Calories, &tmpl.CreatedAt, &tmpl.UpdatedAt)
	return tmpl, err
}

// ListFoodTemplates returns the caller's food presets, newest first.
func (s *Store) ListFoodTemplates(ctx context.Context, userID uuid.UUID) ([]FoodTemplate, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+foodTemplateColumns+`
		FROM food_templates WHERE user_id = $1 AND is_deleted = false
		ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("store: list food templates: %w", err)
	}
	defer rows.Close()

	templates := make([]FoodTemplate, 0, 16)
	for rows.Next() {
		tmpl, err := scanFoodTemplate(rows)
		if err != nil {
			return nil, fmt.Errorf("store: scan food template: %w", err)
		}
		templates = append(templates, tmpl)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: iterate food templates: %w", err)
	}
	return templates, nil
}

// CreateFoodTemplate inserts a food preset, deriving calories via Atwater.
func (s *Store) CreateFoodTemplate(ctx context.Context, userID uuid.UUID, in FoodTemplateInput) (FoodTemplate, error) {
	name := trimOrEmpty(in.Name)
	if name == "" {
		return FoodTemplate{}, fmt.Errorf("%w: name is required", ErrInvalid)
	}
	if err := validateMacros(in.Carbs, in.Protein, in.Fat); err != nil {
		return FoodTemplate{}, err
	}
	id, err := newUUID(in.UUID)
	if err != nil {
		return FoodTemplate{}, err
	}
	carbs, protein, fat := floatOrZero(in.Carbs), floatOrZero(in.Protein), floatOrZero(in.Fat)
	tmpl, err := scanFoodTemplate(s.pool.QueryRow(ctx, `INSERT INTO food_templates
			(uuid, user_id, name, carbs, protein, fat, calories)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING `+foodTemplateColumns,
		id, userID, name, carbs, protein, fat, atwater.KcalFromMacros(carbs, protein, fat)))
	if err != nil {
		return FoodTemplate{}, wrapTemplateWriteError("create food template", err)
	}
	return tmpl, nil
}

// DeleteFoodTemplate soft-deletes a food preset.
func (s *Store) DeleteFoodTemplate(ctx context.Context, userID, templateID uuid.UUID) error {
	tag, err := s.pool.Exec(ctx, `UPDATE food_templates SET is_deleted = true
		WHERE uuid = $1 AND user_id = $2 AND is_deleted = false`, templateID, userID)
	if err != nil {
		return fmt.Errorf("store: delete food template: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func validateRestOverride(rest *int) error {
	if rest == nil || *rest == 0 {
		return nil
	}
	if *rest < 60 || *rest > 300 {
		return fmt.Errorf("%w: rest_seconds_override must be 60-300 seconds (0 clears it)", ErrInvalid)
	}
	return nil
}

// wrapTemplateWriteError maps the partial unique name index to ErrConflict.
func wrapTemplateWriteError(op string, err error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return fmt.Errorf("%w: a template with that name already exists", ErrConflict)
	}
	return fmt.Errorf("store: %s: %w", op, err)
}
