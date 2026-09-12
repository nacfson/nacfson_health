package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/domain/atwater"
)

// Sync resource names match the native Flutter table names.
const (
	SyncExerciseRecords   = "exercise_records"
	SyncDietRecords       = "diet_records"
	SyncWeightRecords     = "weight_records"
	SyncExerciseTemplates = "exercise_templates"
	SyncFoodTemplates     = "food_templates"
	SyncWorkoutRoutines   = "workout_routines"
)

// SyncRow is a loosely-typed native sync payload. Field names follow the
// Flutter Supabase wire format (timestamp, not recorded_at).
type SyncRow map[string]any

// UpsertSyncRows batch-upserts rows for one syncable table, scoped to userID.
// Client user_id is ignored; tenancy always comes from Auth.
func (s *Store) UpsertSyncRows(ctx context.Context, userID uuid.UUID, resource string, rows []SyncRow) error {
	switch resource {
	case SyncExerciseRecords, SyncDietRecords, SyncWeightRecords,
		SyncExerciseTemplates, SyncFoodTemplates, SyncWorkoutRoutines:
		// ok
	default:
		return fmt.Errorf("%w: unknown sync resource %q", ErrInvalid, resource)
	}
	if len(rows) == 0 {
		return nil
	}
	switch resource {
	case SyncExerciseRecords:
		return s.upsertExerciseSync(ctx, userID, rows)
	case SyncDietRecords:
		return s.upsertDietSync(ctx, userID, rows)
	case SyncWeightRecords:
		return s.upsertWeightSync(ctx, userID, rows)
	case SyncExerciseTemplates:
		return s.upsertExerciseTemplateSync(ctx, userID, rows)
	case SyncFoodTemplates:
		return s.upsertFoodTemplateSync(ctx, userID, rows)
	case SyncWorkoutRoutines:
		return s.upsertWorkoutRoutineSync(ctx, userID, rows)
	default:
		return fmt.Errorf("%w: unknown sync resource %q", ErrInvalid, resource)
	}
}

// PullSyncRows returns live (is_deleted=false) rows with updated_at > since.
// When since is nil, every live row for the tenant is returned.
func (s *Store) PullSyncRows(ctx context.Context, userID uuid.UUID, resource string, since *time.Time) ([]SyncRow, error) {
	switch resource {
	case SyncExerciseRecords:
		return s.pullExerciseSync(ctx, userID, since)
	case SyncDietRecords:
		return s.pullDietSync(ctx, userID, since)
	case SyncWeightRecords:
		return s.pullWeightSync(ctx, userID, since)
	case SyncExerciseTemplates:
		return s.pullExerciseTemplateSync(ctx, userID, since)
	case SyncFoodTemplates:
		return s.pullFoodTemplateSync(ctx, userID, since)
	case SyncWorkoutRoutines:
		return s.pullWorkoutRoutineSync(ctx, userID, since)
	default:
		return nil, fmt.Errorf("%w: unknown sync resource %q", ErrInvalid, resource)
	}
}

func (s *Store) upsertExerciseSync(ctx context.Context, userID uuid.UUID, rows []SyncRow) error {
	batch := &pgx.Batch{}
	for _, row := range rows {
		id, err := requiredUUID(row, "uuid")
		if err != nil {
			return err
		}
		ts, err := rowTime(row, "timestamp", "recorded_at")
		if err != nil {
			return err
		}
		updatedAt, err := rowTime(row, "updated_at")
		if err != nil {
			return err
		}
		setType := strings.TrimSpace(rowString(row, "set_type"))
		if setType == "" {
			setType = SetTypeWork
		}
		if _, err := normalizeSetType(&setType); err != nil {
			return err
		}
		batch.Queue(`INSERT INTO exercise_records (
				uuid, user_id, recorded_at, exercise_type, exercise_name, exercise_key, category_key,
				current_set, weight, reps, rpe, set_type, created_at, updated_at, is_deleted)
			VALUES ($1,$2,$3,$4,$5,NULLIF($6,''),NULLIF($7,''),$8,$9,$10,$11,$12,$13,$14,$15)
			ON CONFLICT (uuid) DO UPDATE SET
				recorded_at = EXCLUDED.recorded_at,
				exercise_type = EXCLUDED.exercise_type,
				exercise_name = EXCLUDED.exercise_name,
				exercise_key = EXCLUDED.exercise_key,
				category_key = EXCLUDED.category_key,
				current_set = EXCLUDED.current_set,
				weight = EXCLUDED.weight,
				reps = EXCLUDED.reps,
				rpe = EXCLUDED.rpe,
				set_type = EXCLUDED.set_type,
				updated_at = EXCLUDED.updated_at,
				is_deleted = EXCLUDED.is_deleted
			WHERE exercise_records.user_id = $2`,
			id, userID, ts, rowString(row, "exercise_type"), rowString(row, "exercise_name"),
			rowString(row, "exercise_key"), rowString(row, "category_key"),
			rowInt(row, "current_set", 1), rowFloat(row, "weight"), rowInt(row, "reps", 0),
			rowFloat(row, "rpe"), setType, coalesceTime(row, "created_at", updatedAt), updatedAt,
			rowBool(row, "is_deleted"))
	}
	return s.sendBatch(ctx, batch, "upsert exercise sync")
}

func (s *Store) pullExerciseSync(ctx context.Context, userID uuid.UUID, since *time.Time) ([]SyncRow, error) {
	query := `SELECT uuid, recorded_at, exercise_type, exercise_name,
			COALESCE(exercise_key,''), COALESCE(category_key,''),
			current_set, weight, reps, rpe, set_type, created_at, updated_at
		FROM exercise_records
		WHERE user_id = $1 AND is_deleted = false`
	args := []any{userID}
	if since != nil {
		query += ` AND updated_at > $2`
		args = append(args, since.UTC())
	}
	query += ` ORDER BY updated_at ASC`
	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("store: pull exercise sync: %w", err)
	}
	defer rows.Close()
	out := make([]SyncRow, 0, 16)
	for rows.Next() {
		var (
			id, exType, name, exKey, catKey, setType string
			currentSet, reps                         int
			weight, rpe                              float64
			recordedAt, createdAt, updatedAt         time.Time
		)
		if err := rows.Scan(&id, &recordedAt, &exType, &name, &exKey, &catKey,
			&currentSet, &weight, &reps, &rpe, &setType, &createdAt, &updatedAt); err != nil {
			return nil, fmt.Errorf("store: scan exercise sync: %w", err)
		}
		out = append(out, SyncRow{
			"uuid": id, "user_id": userID.String(),
			"timestamp": recordedAt.UTC().Format(time.RFC3339Nano),
			"updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
			"created_at": createdAt.UTC().Format(time.RFC3339Nano),
			"exercise_type": exType, "exercise_name": name,
			"exercise_key": exKey, "category_key": catKey,
			"current_set": currentSet, "weight": weight, "reps": reps, "rpe": rpe,
			"set_type": setType, "is_deleted": false,
		})
	}
	return out, rows.Err()
}

func (s *Store) upsertDietSync(ctx context.Context, userID uuid.UUID, rows []SyncRow) error {
	batch := &pgx.Batch{}
	for _, row := range rows {
		id, err := requiredUUID(row, "uuid")
		if err != nil {
			return err
		}
		ts, err := rowTime(row, "timestamp", "recorded_at")
		if err != nil {
			return err
		}
		updatedAt, err := rowTime(row, "updated_at")
		if err != nil {
			return err
		}
		carbs, protein, fat := rowFloat(row, "carbs"), rowFloat(row, "protein"), rowFloat(row, "fat")
		kcal := atwater.KcalFromMacros(carbs, protein, fat)
		batch.Queue(`INSERT INTO diet_records (
				uuid, user_id, recorded_at, meal_type, food_name, carbs, protein, fat,
				total_calories, satisfaction, memo, created_at, updated_at, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
			ON CONFLICT (uuid) DO UPDATE SET
				recorded_at = EXCLUDED.recorded_at,
				meal_type = EXCLUDED.meal_type,
				food_name = EXCLUDED.food_name,
				carbs = EXCLUDED.carbs,
				protein = EXCLUDED.protein,
				fat = EXCLUDED.fat,
				total_calories = EXCLUDED.total_calories,
				satisfaction = EXCLUDED.satisfaction,
				memo = EXCLUDED.memo,
				updated_at = EXCLUDED.updated_at,
				is_deleted = EXCLUDED.is_deleted
			WHERE diet_records.user_id = $2`,
			id, userID, ts, rowString(row, "meal_type"), rowString(row, "food_name"),
			carbs, protein, fat, kcal, rowInt(row, "satisfaction", 0), rowString(row, "memo"),
			coalesceTime(row, "created_at", updatedAt), updatedAt, rowBool(row, "is_deleted"))
	}
	return s.sendBatch(ctx, batch, "upsert diet sync")
}

func (s *Store) pullDietSync(ctx context.Context, userID uuid.UUID, since *time.Time) ([]SyncRow, error) {
	query := `SELECT uuid, recorded_at, meal_type, food_name, carbs, protein, fat,
			total_calories, satisfaction, memo, created_at, updated_at
		FROM diet_records WHERE user_id = $1 AND is_deleted = false`
	args := []any{userID}
	if since != nil {
		query += ` AND updated_at > $2`
		args = append(args, since.UTC())
	}
	query += ` ORDER BY updated_at ASC`
	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("store: pull diet sync: %w", err)
	}
	defer rows.Close()
	out := make([]SyncRow, 0, 16)
	for rows.Next() {
		var (
			id, meal, food, memo             string
			carbs, protein, fat              float64
			kcal, satisfaction               int
			recordedAt, createdAt, updatedAt time.Time
		)
		if err := rows.Scan(&id, &recordedAt, &meal, &food, &carbs, &protein, &fat,
			&kcal, &satisfaction, &memo, &createdAt, &updatedAt); err != nil {
			return nil, fmt.Errorf("store: scan diet sync: %w", err)
		}
		out = append(out, SyncRow{
			"uuid": id, "user_id": userID.String(),
			"timestamp": recordedAt.UTC().Format(time.RFC3339Nano),
			"updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
			"created_at": createdAt.UTC().Format(time.RFC3339Nano),
			"meal_type": meal, "food_name": food,
			"carbs": carbs, "protein": protein, "fat": fat,
			"total_calories": kcal, "satisfaction": satisfaction, "memo": memo,
			"is_deleted": false,
		})
	}
	return out, rows.Err()
}

func (s *Store) upsertWeightSync(ctx context.Context, userID uuid.UUID, rows []SyncRow) error {
	batch := &pgx.Batch{}
	for _, row := range rows {
		id, err := requiredUUID(row, "uuid")
		if err != nil {
			return err
		}
		ts, err := rowTime(row, "timestamp", "recorded_at")
		if err != nil {
			return err
		}
		updatedAt, err := rowTime(row, "updated_at")
		if err != nil {
			return err
		}
		batch.Queue(`INSERT INTO weight_records (
				uuid, user_id, recorded_at, weight, created_at, updated_at, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7)
			ON CONFLICT (uuid) DO UPDATE SET
				recorded_at = EXCLUDED.recorded_at,
				weight = EXCLUDED.weight,
				updated_at = EXCLUDED.updated_at,
				is_deleted = EXCLUDED.is_deleted
			WHERE weight_records.user_id = $2`,
			id, userID, ts, rowFloat(row, "weight"),
			coalesceTime(row, "created_at", updatedAt), updatedAt, rowBool(row, "is_deleted"))
	}
	return s.sendBatch(ctx, batch, "upsert weight sync")
}

func (s *Store) pullWeightSync(ctx context.Context, userID uuid.UUID, since *time.Time) ([]SyncRow, error) {
	query := `SELECT uuid, recorded_at, weight, created_at, updated_at
		FROM weight_records WHERE user_id = $1 AND is_deleted = false`
	args := []any{userID}
	if since != nil {
		query += ` AND updated_at > $2`
		args = append(args, since.UTC())
	}
	query += ` ORDER BY updated_at ASC`
	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("store: pull weight sync: %w", err)
	}
	defer rows.Close()
	out := make([]SyncRow, 0, 16)
	for rows.Next() {
		var (
			id                               string
			weight                           float64
			recordedAt, createdAt, updatedAt time.Time
		)
		if err := rows.Scan(&id, &recordedAt, &weight, &createdAt, &updatedAt); err != nil {
			return nil, fmt.Errorf("store: scan weight sync: %w", err)
		}
		out = append(out, SyncRow{
			"uuid": id, "user_id": userID.String(),
			"timestamp": recordedAt.UTC().Format(time.RFC3339Nano),
			"updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
			"created_at": createdAt.UTC().Format(time.RFC3339Nano),
			"weight": weight, "is_deleted": false,
		})
	}
	return out, rows.Err()
}

func (s *Store) upsertExerciseTemplateSync(ctx context.Context, userID uuid.UUID, rows []SyncRow) error {
	batch := &pgx.Batch{}
	for _, row := range rows {
		id, err := requiredUUID(row, "uuid")
		if err != nil {
			return err
		}
		updatedAt, err := rowTime(row, "updated_at")
		if err != nil {
			return err
		}
		name := rowString(row, "name")
		if name == "" {
			return fmt.Errorf("%w: name is required", ErrInvalid)
		}
		var rest any
		if v, ok := row["rest_seconds_override"]; ok && v != nil {
			rest = rowInt(row, "rest_seconds_override", 0)
		}
		batch.Queue(`INSERT INTO exercise_templates (
				uuid, user_id, name, exercise_type, exercise_key, category_key,
				rest_seconds_override, created_at, updated_at, is_deleted)
			VALUES ($1,$2,$3,$4,NULLIF($5,''),NULLIF($6,''),$7,$8,$9,$10)
			ON CONFLICT (uuid) DO UPDATE SET
				name = EXCLUDED.name,
				exercise_type = EXCLUDED.exercise_type,
				exercise_key = EXCLUDED.exercise_key,
				category_key = EXCLUDED.category_key,
				rest_seconds_override = EXCLUDED.rest_seconds_override,
				updated_at = EXCLUDED.updated_at,
				is_deleted = EXCLUDED.is_deleted
			WHERE exercise_templates.user_id = $2`,
			id, userID, name, rowString(row, "exercise_type"),
			rowString(row, "exercise_key"), rowString(row, "category_key"),
			rest, coalesceTime(row, "created_at", updatedAt), updatedAt, rowBool(row, "is_deleted"))
	}
	return s.sendBatch(ctx, batch, "upsert exercise template sync")
}

func (s *Store) pullExerciseTemplateSync(ctx context.Context, userID uuid.UUID, since *time.Time) ([]SyncRow, error) {
	query := `SELECT uuid, name, exercise_type, COALESCE(exercise_key,''), COALESCE(category_key,''),
			rest_seconds_override, created_at, updated_at
		FROM exercise_templates WHERE user_id = $1 AND is_deleted = false`
	args := []any{userID}
	if since != nil {
		query += ` AND updated_at > $2`
		args = append(args, since.UTC())
	}
	query += ` ORDER BY updated_at ASC`
	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("store: pull exercise template sync: %w", err)
	}
	defer rows.Close()
	out := make([]SyncRow, 0, 16)
	for rows.Next() {
		var (
			id, name, exType, exKey, catKey string
			rest                            *int
			createdAt, updatedAt            time.Time
		)
		if err := rows.Scan(&id, &name, &exType, &exKey, &catKey, &rest, &createdAt, &updatedAt); err != nil {
			return nil, fmt.Errorf("store: scan exercise template sync: %w", err)
		}
		row := SyncRow{
			"uuid": id, "user_id": userID.String(), "name": name,
			"exercise_type": exType, "exercise_key": exKey, "category_key": catKey,
			"created_at": createdAt.UTC().Format(time.RFC3339Nano),
			"updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
			"is_deleted": false,
		}
		if rest != nil {
			row["rest_seconds_override"] = *rest
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

func (s *Store) upsertFoodTemplateSync(ctx context.Context, userID uuid.UUID, rows []SyncRow) error {
	batch := &pgx.Batch{}
	for _, row := range rows {
		id, err := requiredUUID(row, "uuid")
		if err != nil {
			return err
		}
		updatedAt, err := rowTime(row, "updated_at")
		if err != nil {
			return err
		}
		name := rowString(row, "name")
		if name == "" {
			return fmt.Errorf("%w: name is required", ErrInvalid)
		}
		carbs, protein, fat := rowFloat(row, "carbs"), rowFloat(row, "protein"), rowFloat(row, "fat")
		kcal := atwater.KcalFromMacros(carbs, protein, fat)
		batch.Queue(`INSERT INTO food_templates (
				uuid, user_id, name, carbs, protein, fat, calories, created_at, updated_at, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
			ON CONFLICT (uuid) DO UPDATE SET
				name = EXCLUDED.name,
				carbs = EXCLUDED.carbs,
				protein = EXCLUDED.protein,
				fat = EXCLUDED.fat,
				calories = EXCLUDED.calories,
				updated_at = EXCLUDED.updated_at,
				is_deleted = EXCLUDED.is_deleted
			WHERE food_templates.user_id = $2`,
			id, userID, name, carbs, protein, fat, kcal,
			coalesceTime(row, "created_at", updatedAt), updatedAt, rowBool(row, "is_deleted"))
	}
	return s.sendBatch(ctx, batch, "upsert food template sync")
}

func (s *Store) pullFoodTemplateSync(ctx context.Context, userID uuid.UUID, since *time.Time) ([]SyncRow, error) {
	query := `SELECT uuid, name, carbs, protein, fat, calories, created_at, updated_at
		FROM food_templates WHERE user_id = $1 AND is_deleted = false`
	args := []any{userID}
	if since != nil {
		query += ` AND updated_at > $2`
		args = append(args, since.UTC())
	}
	query += ` ORDER BY updated_at ASC`
	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("store: pull food template sync: %w", err)
	}
	defer rows.Close()
	out := make([]SyncRow, 0, 16)
	for rows.Next() {
		var (
			id, name             string
			carbs, protein, fat  float64
			kcal                 int
			createdAt, updatedAt time.Time
		)
		if err := rows.Scan(&id, &name, &carbs, &protein, &fat, &kcal, &createdAt, &updatedAt); err != nil {
			return nil, fmt.Errorf("store: scan food template sync: %w", err)
		}
		out = append(out, SyncRow{
			"uuid": id, "user_id": userID.String(), "name": name,
			"carbs": carbs, "protein": protein, "fat": fat, "calories": kcal,
			"created_at": createdAt.UTC().Format(time.RFC3339Nano),
			"updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
			"is_deleted": false,
		})
	}
	return out, rows.Err()
}

func (s *Store) upsertWorkoutRoutineSync(ctx context.Context, userID uuid.UUID, rows []SyncRow) error {
	batch := &pgx.Batch{}
	for _, row := range rows {
		id, err := requiredUUID(row, "uuid")
		if err != nil {
			return err
		}
		updatedAt, err := rowTime(row, "updated_at")
		if err != nil {
			return err
		}
		itemsJSON, err := encodeItemsJSON(row["items_json"])
		if err != nil {
			return err
		}
		batch.Queue(`INSERT INTO workout_routines (
				uuid, user_id, name, items_json, created_at, updated_at, is_deleted)
			VALUES ($1,$2,$3,$4::jsonb,$5,$6,$7)
			ON CONFLICT (uuid) DO UPDATE SET
				name = EXCLUDED.name,
				items_json = EXCLUDED.items_json,
				updated_at = EXCLUDED.updated_at,
				is_deleted = EXCLUDED.is_deleted
			WHERE workout_routines.user_id = $2`,
			id, userID, rowString(row, "name"), itemsJSON,
			coalesceTime(row, "created_at", updatedAt), updatedAt, rowBool(row, "is_deleted"))
	}
	return s.sendBatch(ctx, batch, "upsert workout routine sync")
}

func (s *Store) pullWorkoutRoutineSync(ctx context.Context, userID uuid.UUID, since *time.Time) ([]SyncRow, error) {
	query := `SELECT uuid, name, items_json::text, created_at, updated_at
		FROM workout_routines WHERE user_id = $1 AND is_deleted = false`
	args := []any{userID}
	if since != nil {
		query += ` AND updated_at > $2`
		args = append(args, since.UTC())
	}
	query += ` ORDER BY updated_at ASC`
	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("store: pull workout routine sync: %w", err)
	}
	defer rows.Close()
	out := make([]SyncRow, 0, 16)
	for rows.Next() {
		var (
			id, name, itemsJSON  string
			createdAt, updatedAt time.Time
		)
		if err := rows.Scan(&id, &name, &itemsJSON, &createdAt, &updatedAt); err != nil {
			return nil, fmt.Errorf("store: scan workout routine sync: %w", err)
		}
		var items any
		if err := json.Unmarshal([]byte(itemsJSON), &items); err != nil {
			return nil, fmt.Errorf("store: decode items_json: %w", err)
		}
		out = append(out, SyncRow{
			"uuid": id, "user_id": userID.String(), "name": name,
			"items_json": items,
			"created_at": createdAt.UTC().Format(time.RFC3339Nano),
			"updated_at": updatedAt.UTC().Format(time.RFC3339Nano),
			"is_deleted": false,
		})
	}
	return out, rows.Err()
}

func (s *Store) sendBatch(ctx context.Context, batch *pgx.Batch, label string) error {
	br := s.pool.SendBatch(ctx, batch)
	defer br.Close()
	for i := 0; i < batch.Len(); i++ {
		if _, err := br.Exec(); err != nil {
			return fmt.Errorf("store: %s row %d: %w", label, i, err)
		}
	}
	return nil
}

func requiredUUID(row SyncRow, key string) (uuid.UUID, error) {
	raw := rowString(row, key)
	if raw == "" {
		return uuid.Nil, fmt.Errorf("%w: %s is required", ErrInvalid, key)
	}
	id, err := uuid.Parse(raw)
	if err != nil {
		return uuid.Nil, fmt.Errorf("%w: %s", ErrInvalid, key)
	}
	return id, nil
}

func rowString(row SyncRow, key string) string {
	v, ok := row[key]
	if !ok || v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return strings.TrimSpace(t)
	default:
		return strings.TrimSpace(fmt.Sprint(t))
	}
}

func rowBool(row SyncRow, key string) bool {
	v, ok := row[key]
	if !ok || v == nil {
		return false
	}
	switch t := v.(type) {
	case bool:
		return t
	case string:
		return strings.EqualFold(t, "true") || t == "1"
	case float64:
		return t != 0
	default:
		return false
	}
}

func rowFloat(row SyncRow, key string) float64 {
	v, ok := row[key]
	if !ok || v == nil {
		return 0
	}
	switch t := v.(type) {
	case float64:
		return t
	case float32:
		return float64(t)
	case int:
		return float64(t)
	case int64:
		return float64(t)
	case json.Number:
		f, _ := t.Float64()
		return f
	case string:
		var f float64
		fmt.Sscanf(t, "%f", &f)
		return f
	default:
		return 0
	}
}

func rowInt(row SyncRow, key string, fallback int) int {
	v, ok := row[key]
	if !ok || v == nil {
		return fallback
	}
	switch t := v.(type) {
	case float64:
		return int(t)
	case int:
		return t
	case int64:
		return int(t)
	case json.Number:
		i, _ := t.Int64()
		return int(i)
	case string:
		var i int
		fmt.Sscanf(t, "%d", &i)
		return i
	default:
		return fallback
	}
}

func rowTime(row SyncRow, keys ...string) (time.Time, error) {
	for _, key := range keys {
		v, ok := row[key]
		if !ok || v == nil {
			continue
		}
		switch t := v.(type) {
		case string:
			parsed, err := time.Parse(time.RFC3339Nano, t)
			if err != nil {
				parsed, err = time.Parse(time.RFC3339, t)
			}
			if err != nil {
				return time.Time{}, fmt.Errorf("%w: %s", ErrInvalid, key)
			}
			return parsed.UTC(), nil
		case time.Time:
			return t.UTC(), nil
		}
	}
	return time.Time{}, fmt.Errorf("%w: %s is required", ErrInvalid, keys[0])
}

func coalesceTime(row SyncRow, key string, fallback time.Time) time.Time {
	if t, err := rowTime(row, key); err == nil {
		return t
	}
	return fallback
}

func encodeItemsJSON(raw any) (string, error) {
	if raw == nil {
		return "[]", nil
	}
	if s, ok := raw.(string); ok {
		if strings.TrimSpace(s) == "" {
			return "[]", nil
		}
		if !json.Valid([]byte(s)) {
			return "", fmt.Errorf("%w: items_json", ErrInvalid)
		}
		return s, nil
	}
	b, err := json.Marshal(raw)
	if err != nil {
		return "", fmt.Errorf("%w: items_json", ErrInvalid)
	}
	return string(b), nil
}
