// Package seed loads the bundled master exercise catalog (categories,
// definitions, translations, 1RM formulas) into Postgres. It is idempotent:
// every statement upserts, so the migrate Job may re-run it safely.
package seed

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Data mirrors the master_exercise_seed_v12_6.json export.
type Data struct {
	SchemaVersion        string                `json:"schema_version"`
	Categories           []Category            `json:"categories"`
	CategoryTranslations []CategoryTranslation `json:"category_translations"`
	Definitions          []Definition          `json:"definitions"`
	Translations         []Translation         `json:"translations"`
	OneRMFormulas        []OneRMFormula        `json:"one_rm_formulas"`
}

type Category struct {
	CategoryKey  string `json:"category_key"`
	DisplayOrder int    `json:"display_order"`
}

type CategoryTranslation struct {
	CategoryKey string `json:"category_key"`
	Locale      string `json:"locale"`
	DisplayName string `json:"display_name"`
}

type Definition struct {
	ExerciseKey string `json:"exercise_key"`
	CategoryKey string `json:"category_key"`
	IsCompound  bool   `json:"is_compound"`
	DefaultName string `json:"default_name"`
}

type Translation struct {
	ExerciseKey string   `json:"exercise_key"`
	Locale      string   `json:"locale"`
	DisplayName string   `json:"display_name"`
	Aliases     []string `json:"aliases"`
}

type OneRMFormula struct {
	ExerciseKey        string          `json:"exercise_key"`
	FormulaType        string          `json:"formula_type"`
	Coefficients       json.RawMessage `json:"coefficients"`
	Source             string          `json:"source"`
	OptimalRepMax      int             `json:"optimal_rep_max"`
	NoticeTranslations json.RawMessage `json:"notice_translations"`
}

// Stats reports how many rows each master table received.
type Stats struct {
	Categories           int
	CategoryTranslations int
	Definitions          int
	Translations         int
	OneRMFormulas        int
}

// Load parses and validates a seed file.
func Load(path string) (Data, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return Data{}, fmt.Errorf("seed: read %s: %w", path, err)
	}
	var data Data
	if err := json.Unmarshal(raw, &data); err != nil {
		return Data{}, fmt.Errorf("seed: parse %s: %w", path, err)
	}
	if len(data.Categories) == 0 || len(data.Definitions) == 0 {
		return Data{}, fmt.Errorf("seed: %s contains no master data", path)
	}
	return data, nil
}

// Run loads path and upserts the catalog using its own short-lived pool.
func Run(ctx context.Context, databaseURL, path string) (Stats, error) {
	data, err := Load(path)
	if err != nil {
		return Stats{}, err
	}
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return Stats{}, fmt.Errorf("seed: parse database url: %w", err)
	}
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return Stats{}, fmt.Errorf("seed: create pool: %w", err)
	}
	defer pool.Close()

	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		return Stats{}, fmt.Errorf("seed: ping database: %w", err)
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		return Stats{}, fmt.Errorf("seed: begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Parent rows first: definitions reference categories, translations and
	// formulas reference definitions.
	for _, row := range data.Categories {
		if _, err := tx.Exec(ctx, `INSERT INTO exercise_categories (category_key, display_order)
			VALUES ($1, $2)
			ON CONFLICT (category_key) DO UPDATE SET display_order = EXCLUDED.display_order`,
			row.CategoryKey, row.DisplayOrder); err != nil {
			return Stats{}, fmt.Errorf("seed: category %s: %w", row.CategoryKey, err)
		}
	}
	for _, row := range data.CategoryTranslations {
		if _, err := tx.Exec(ctx, `INSERT INTO exercise_category_translations
				(category_key, locale, display_name)
			VALUES ($1, $2, $3)
			ON CONFLICT (category_key, locale) DO UPDATE SET display_name = EXCLUDED.display_name`,
			row.CategoryKey, row.Locale, row.DisplayName); err != nil {
			return Stats{}, fmt.Errorf("seed: category translation %s/%s: %w", row.CategoryKey, row.Locale, err)
		}
	}
	for _, row := range data.Definitions {
		if _, err := tx.Exec(ctx, `INSERT INTO exercise_definitions
				(exercise_key, category_key, is_compound, default_name)
			VALUES ($1, NULLIF($2, ''), $3, $4)
			ON CONFLICT (exercise_key) DO UPDATE SET
				category_key = EXCLUDED.category_key,
				is_compound = EXCLUDED.is_compound,
				default_name = EXCLUDED.default_name`,
			row.ExerciseKey, row.CategoryKey, row.IsCompound, row.DefaultName); err != nil {
			return Stats{}, fmt.Errorf("seed: definition %s: %w", row.ExerciseKey, err)
		}
	}
	for _, row := range data.Translations {
		aliases, err := json.Marshal(orEmptyStrings(row.Aliases))
		if err != nil {
			return Stats{}, fmt.Errorf("seed: aliases %s/%s: %w", row.ExerciseKey, row.Locale, err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO exercise_translations
				(exercise_key, locale, display_name, aliases)
			VALUES ($1, $2, $3, $4::jsonb)
			ON CONFLICT (exercise_key, locale) DO UPDATE SET
				display_name = EXCLUDED.display_name,
				aliases = EXCLUDED.aliases`,
			row.ExerciseKey, row.Locale, row.DisplayName, string(aliases)); err != nil {
			return Stats{}, fmt.Errorf("seed: translation %s/%s: %w", row.ExerciseKey, row.Locale, err)
		}
	}
	for _, row := range data.OneRMFormulas {
		if _, err := tx.Exec(ctx, `INSERT INTO one_rm_formulas
				(exercise_key, formula_type, coefficients, source, optimal_rep_max, notice_translations)
			VALUES ($1, $2, $3::jsonb, $4, $5, $6::jsonb)
			ON CONFLICT (exercise_key) DO UPDATE SET
				formula_type = EXCLUDED.formula_type,
				coefficients = EXCLUDED.coefficients,
				source = EXCLUDED.source,
				optimal_rep_max = EXCLUDED.optimal_rep_max,
				notice_translations = EXCLUDED.notice_translations`,
			row.ExerciseKey, row.FormulaType, rawJSONOrEmptyObject(row.Coefficients),
			row.Source, row.OptimalRepMax, rawJSONOrEmptyObject(row.NoticeTranslations)); err != nil {
			return Stats{}, fmt.Errorf("seed: one_rm_formula %s: %w", row.ExerciseKey, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return Stats{}, fmt.Errorf("seed: commit: %w", err)
	}
	return Stats{
		Categories:           len(data.Categories),
		CategoryTranslations: len(data.CategoryTranslations),
		Definitions:          len(data.Definitions),
		Translations:         len(data.Translations),
		OneRMFormulas:        len(data.OneRMFormulas),
	}, nil
}

func rawJSONOrEmptyObject(raw json.RawMessage) string {
	if len(raw) == 0 {
		return "{}"
	}
	return string(raw)
}

func orEmptyStrings(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}
