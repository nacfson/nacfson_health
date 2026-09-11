package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// DefaultMasterLocale is used when a request omits ?locale=.
const DefaultMasterLocale = "ko"

// MasterCategory is a localized exercise category.
type MasterCategory struct {
	CategoryKey  string `json:"category_key"`
	DisplayName  string `json:"display_name"`
	DisplayOrder int    `json:"display_order"`
}

// MasterExercise is a localized exercise definition.
type MasterExercise struct {
	ExerciseKey string   `json:"exercise_key"`
	CategoryKey string   `json:"category_key"`
	DisplayName string   `json:"display_name"`
	DefaultName string   `json:"default_name"`
	IsCompound  bool     `json:"is_compound"`
	Aliases     []string `json:"aliases"`
}

// MasterData is the read-only master exercise catalog for one locale.
type MasterData struct {
	Locale     string           `json:"locale"`
	Categories []MasterCategory `json:"categories"`
	Exercises  []MasterExercise `json:"exercises"`
}

// MasterExercises returns the seeded master catalog localized for locale
// (falling back to default names when a translation is missing).
func (s *Store) MasterExercises(ctx context.Context, locale string) (MasterData, error) {
	locale = normalizeLocale(locale)
	out := MasterData{
		Locale:     locale,
		Categories: make([]MasterCategory, 0, 16),
		Exercises:  make([]MasterExercise, 0, 300),
	}

	categoryRows, err := s.pool.Query(ctx, `SELECT c.category_key,
			COALESCE(t.display_name, c.category_key), c.display_order
		FROM exercise_categories c
		LEFT JOIN exercise_category_translations t
			ON t.category_key = c.category_key AND t.locale = $1
		ORDER BY c.display_order, c.category_key`, locale)
	if err != nil {
		return MasterData{}, fmt.Errorf("store: list categories: %w", err)
	}
	defer categoryRows.Close()
	for categoryRows.Next() {
		var category MasterCategory
		if err := categoryRows.Scan(&category.CategoryKey, &category.DisplayName, &category.DisplayOrder); err != nil {
			return MasterData{}, fmt.Errorf("store: scan category: %w", err)
		}
		out.Categories = append(out.Categories, category)
	}
	if err := categoryRows.Err(); err != nil {
		return MasterData{}, fmt.Errorf("store: iterate categories: %w", err)
	}

	exerciseRows, err := s.pool.Query(ctx, `SELECT d.exercise_key, COALESCE(d.category_key, ''),
			COALESCE(t.display_name, d.default_name), d.default_name, d.is_compound,
			COALESCE(t.aliases::text, '[]')
		FROM exercise_definitions d
		LEFT JOIN exercise_categories c ON c.category_key = d.category_key
		LEFT JOIN exercise_translations t
			ON t.exercise_key = d.exercise_key AND t.locale = $1
		ORDER BY COALESCE(c.display_order, 1000), d.default_name, d.exercise_key`, locale)
	if err != nil {
		return MasterData{}, fmt.Errorf("store: list exercises: %w", err)
	}
	defer exerciseRows.Close()
	for exerciseRows.Next() {
		var (
			exercise MasterExercise
			aliases  string
		)
		if err := exerciseRows.Scan(&exercise.ExerciseKey, &exercise.CategoryKey,
			&exercise.DisplayName, &exercise.DefaultName, &exercise.IsCompound, &aliases); err != nil {
			return MasterData{}, fmt.Errorf("store: scan exercise: %w", err)
		}
		exercise.Aliases = []string{}
		if strings.TrimSpace(aliases) != "" {
			if err := json.Unmarshal([]byte(aliases), &exercise.Aliases); err != nil {
				return MasterData{}, fmt.Errorf("store: decode aliases for %s: %w", exercise.ExerciseKey, err)
			}
		}
		if exercise.Aliases == nil {
			exercise.Aliases = []string{}
		}
		out.Exercises = append(out.Exercises, exercise)
	}
	if err := exerciseRows.Err(); err != nil {
		return MasterData{}, fmt.Errorf("store: iterate exercises: %w", err)
	}
	return out, nil
}

func normalizeLocale(locale string) string {
	locale = strings.ToLower(strings.TrimSpace(locale))
	if locale == "" || len(locale) > 8 {
		return DefaultMasterLocale
	}
	return locale
}
