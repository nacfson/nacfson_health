package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
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

// MasterFormula is one 1RM formula row for native SQLite cache.
type MasterFormula struct {
	ExerciseKey        string          `json:"exercise_key"`
	FormulaType        string          `json:"formula_type"`
	Coefficients       json.RawMessage `json:"coefficients"`
	Source             string          `json:"source"`
	OptimalRepMax      int             `json:"optimal_rep_max"`
	NoticeTranslations json.RawMessage `json:"notice_translations"`
	UpdatedAt          time.Time       `json:"updated_at"`
}

// MasterBundle is the full admin-curated catalog native clients replace into
// SQLite (categories, definitions, translations, formulas).
type MasterBundle struct {
	Categories            []map[string]any `json:"categories"`
	CategoryTranslations  []map[string]any `json:"category_translations"`
	Definitions           []map[string]any `json:"definitions"`
	Translations          []map[string]any `json:"translations"`
	Formulas              []map[string]any `json:"formulas"`
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

// MasterBundleForNative returns raw table rows for the Flutter SQLite replace
// protocol (same shape as the former Supabase selects).
func (s *Store) MasterBundleForNative(ctx context.Context) (MasterBundle, error) {
	out := MasterBundle{
		Categories:           make([]map[string]any, 0, 16),
		CategoryTranslations: make([]map[string]any, 0, 32),
		Definitions:          make([]map[string]any, 0, 300),
		Translations:         make([]map[string]any, 0, 600),
		Formulas:             make([]map[string]any, 0, 64),
	}

	catRows, err := s.pool.Query(ctx, `SELECT category_key, display_order, updated_at
		FROM exercise_categories ORDER BY display_order, category_key`)
	if err != nil {
		return MasterBundle{}, fmt.Errorf("store: master categories: %w", err)
	}
	defer catRows.Close()
	for catRows.Next() {
		var key string
		var order int
		var updatedAt time.Time
		if err := catRows.Scan(&key, &order, &updatedAt); err != nil {
			return MasterBundle{}, fmt.Errorf("store: scan master category: %w", err)
		}
		out.Categories = append(out.Categories, map[string]any{
			"category_key": key, "display_order": order,
			"updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
			"is_deleted": false,
		})
	}
	if err := catRows.Err(); err != nil {
		return MasterBundle{}, err
	}

	ctRows, err := s.pool.Query(ctx, `SELECT category_key, locale, display_name, updated_at
		FROM exercise_category_translations ORDER BY category_key, locale`)
	if err != nil {
		return MasterBundle{}, fmt.Errorf("store: master category translations: %w", err)
	}
	defer ctRows.Close()
	for ctRows.Next() {
		var key, locale, name string
		var updatedAt time.Time
		if err := ctRows.Scan(&key, &locale, &name, &updatedAt); err != nil {
			return MasterBundle{}, fmt.Errorf("store: scan category translation: %w", err)
		}
		out.CategoryTranslations = append(out.CategoryTranslations, map[string]any{
			"category_key": key, "locale": locale, "display_name": name,
			"updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
		})
	}
	if err := ctRows.Err(); err != nil {
		return MasterBundle{}, err
	}

	defRows, err := s.pool.Query(ctx, `SELECT exercise_key, COALESCE(category_key,''), is_compound,
			default_name, updated_at FROM exercise_definitions ORDER BY exercise_key`)
	if err != nil {
		return MasterBundle{}, fmt.Errorf("store: master definitions: %w", err)
	}
	defer defRows.Close()
	for defRows.Next() {
		var key, cat, defaultName string
		var compound bool
		var updatedAt time.Time
		if err := defRows.Scan(&key, &cat, &compound, &defaultName, &updatedAt); err != nil {
			return MasterBundle{}, fmt.Errorf("store: scan definition: %w", err)
		}
		out.Definitions = append(out.Definitions, map[string]any{
			"exercise_key": key, "category_key": cat, "is_compound": compound,
			"default_name": defaultName,
			"updated_at":   updatedAt.UTC().Format(time.RFC3339Nano),
			"is_deleted":   false,
		})
	}
	if err := defRows.Err(); err != nil {
		return MasterBundle{}, err
	}

	trRows, err := s.pool.Query(ctx, `SELECT exercise_key, locale, display_name, aliases::text, updated_at
		FROM exercise_translations ORDER BY exercise_key, locale`)
	if err != nil {
		return MasterBundle{}, fmt.Errorf("store: master translations: %w", err)
	}
	defer trRows.Close()
	for trRows.Next() {
		var key, locale, name, aliases string
		var updatedAt time.Time
		if err := trRows.Scan(&key, &locale, &name, &aliases, &updatedAt); err != nil {
			return MasterBundle{}, fmt.Errorf("store: scan translation: %w", err)
		}
		var aliasAny any = []any{}
		if strings.TrimSpace(aliases) != "" {
			_ = json.Unmarshal([]byte(aliases), &aliasAny)
		}
		out.Translations = append(out.Translations, map[string]any{
			"exercise_key": key, "locale": locale, "display_name": name,
			"aliases": aliasAny, "updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
		})
	}
	if err := trRows.Err(); err != nil {
		return MasterBundle{}, err
	}

	fRows, err := s.pool.Query(ctx, `SELECT exercise_key, formula_type, coefficients::text, source,
			optimal_rep_max, notice_translations::text, updated_at
		FROM one_rm_formulas ORDER BY exercise_key`)
	if err != nil {
		return MasterBundle{}, fmt.Errorf("store: master formulas: %w", err)
	}
	defer fRows.Close()
	for fRows.Next() {
		var key, formulaType, coeffs, source, notices string
		var optimal int
		var updatedAt time.Time
		if err := fRows.Scan(&key, &formulaType, &coeffs, &source, &optimal, &notices, &updatedAt); err != nil {
			return MasterBundle{}, fmt.Errorf("store: scan formula: %w", err)
		}
		var coeffAny any = map[string]any{}
		var noticeAny any = map[string]any{}
		if strings.TrimSpace(coeffs) != "" {
			_ = json.Unmarshal([]byte(coeffs), &coeffAny)
		}
		if strings.TrimSpace(notices) != "" {
			_ = json.Unmarshal([]byte(notices), &noticeAny)
		}
		out.Formulas = append(out.Formulas, map[string]any{
			"exercise_key": key, "formula_type": formulaType,
			"coefficients": coeffAny, "source": source,
			"optimal_rep_max": optimal, "notice_translations": noticeAny,
			"updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
			"is_deleted": false,
		})
	}
	return out, fRows.Err()
}
