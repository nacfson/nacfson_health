package store

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/domain/nutrition"
)

// Profile is the caller's onboarding/nutrition profile (one row per user).
type Profile struct {
	Gender            string    `json:"gender"`
	Age               int       `json:"age"`
	HeightM           float64   `json:"height_m"`
	Goal              string    `json:"goal"`
	ActivityLevel     string    `json:"activity_level"`
	TrainingIntensity string    `json:"training_intensity"`
	TargetCalories    int       `json:"target_calories"`
	TargetCarbs       float64   `json:"target_carbs"`
	TargetProtein     float64   `json:"target_protein"`
	TargetFat         float64   `json:"target_fat"`
	UpdatedAt         time.Time `json:"updated_at"`
}

// ProfileInput carries upsert payloads; nil fields keep their stored value (or
// the column default on first insert).
type ProfileInput struct {
	Gender            *string  `json:"gender"`
	Age               *int     `json:"age"`
	HeightM           *float64 `json:"height_m"`
	Goal              *string  `json:"goal"`
	ActivityLevel     *string  `json:"activity_level"`
	TrainingIntensity *string  `json:"training_intensity"`
	TargetCalories    *int     `json:"target_calories"`
	TargetCarbs       *float64 `json:"target_carbs"`
	TargetProtein     *float64 `json:"target_protein"`
	TargetFat         *float64 `json:"target_fat"`
}

const profileColumns = `gender, age, height_m, goal, activity_level, training_intensity,
	target_calories, target_carbs, target_protein, target_fat, updated_at`

func scanProfile(row rowScanner) (Profile, error) {
	var profile Profile
	err := row.Scan(&profile.Gender, &profile.Age, &profile.HeightM, &profile.Goal,
		&profile.ActivityLevel, &profile.TrainingIntensity, &profile.TargetCalories,
		&profile.TargetCarbs, &profile.TargetProtein, &profile.TargetFat, &profile.UpdatedAt)
	return profile, err
}

// GetProfile returns the caller's profile; found is false when none exists yet.
func (s *Store) GetProfile(ctx context.Context, userID uuid.UUID) (Profile, bool, error) {
	profile, err := scanProfile(s.pool.QueryRow(ctx, `SELECT `+profileColumns+`
		FROM user_profiles WHERE user_id = $1`, userID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Profile{}, false, nil
	}
	if err != nil {
		return Profile{}, false, fmt.Errorf("store: get profile: %w", err)
	}
	return profile, true, nil
}

// UpsertProfile creates or patches the caller's profile.
func (s *Store) UpsertProfile(ctx context.Context, userID uuid.UUID, in ProfileInput) (Profile, error) {
	if err := validateProfileInput(in); err != nil {
		return Profile{}, err
	}
	profile, err := scanProfile(s.pool.QueryRow(ctx, `INSERT INTO user_profiles
			(uuid, user_id, gender, age, height_m, goal, activity_level, training_intensity,
			 target_calories, target_carbs, target_protein, target_fat)
		VALUES ($1, $2,
			COALESCE($3::text, 'male'), COALESCE($4::integer, 30), COALESCE($5::double precision, 1.7),
			COALESCE($6::text, 'diet'), COALESCE($7::text, 'moderate'), COALESCE($8::text, 'moderate'),
			COALESCE($9::integer, 0), COALESCE($10::double precision, 0),
			COALESCE($11::double precision, 0), COALESCE($12::double precision, 0))
		ON CONFLICT (user_id) DO UPDATE SET
			gender = COALESCE($3::text, user_profiles.gender),
			age = COALESCE($4::integer, user_profiles.age),
			height_m = COALESCE($5::double precision, user_profiles.height_m),
			goal = COALESCE($6::text, user_profiles.goal),
			activity_level = COALESCE($7::text, user_profiles.activity_level),
			training_intensity = COALESCE($8::text, user_profiles.training_intensity),
			target_calories = COALESCE($9::integer, user_profiles.target_calories),
			target_carbs = COALESCE($10::double precision, user_profiles.target_carbs),
			target_protein = COALESCE($11::double precision, user_profiles.target_protein),
			target_fat = COALESCE($12::double precision, user_profiles.target_fat)
		RETURNING `+profileColumns,
		uuid.New(), userID, in.Gender, in.Age, in.HeightM, in.Goal, in.ActivityLevel,
		in.TrainingIntensity, in.TargetCalories, in.TargetCarbs, in.TargetProtein, in.TargetFat))
	if err != nil {
		return Profile{}, fmt.Errorf("store: upsert profile: %w", err)
	}
	return profile, nil
}

// RecalculateTargets runs the shared nutrition calculator and persists the
// result. weightKg overrides the latest weigh-in when provided.
func (s *Store) RecalculateTargets(ctx context.Context, userID uuid.UUID, weightKg *float64) (Profile, error) {
	profile, found, err := s.GetProfile(ctx, userID)
	if err != nil {
		return Profile{}, err
	}
	if !found {
		return Profile{}, ErrNotFound
	}
	weight := 0.0
	switch {
	case weightKg != nil && *weightKg > 0:
		weight = *weightKg
	default:
		latest, ok, err := s.LatestWeight(ctx, userID)
		if err != nil {
			return Profile{}, err
		}
		if !ok {
			return Profile{}, ErrNoWeight
		}
		weight = latest
	}
	if err := validateWeight(weight); err != nil {
		return Profile{}, fmt.Errorf("%w: weight must be between 0 and 500 kg", ErrInvalid)
	}

	targets, err := nutrition.CalculateTargets(nutrition.Input{
		HeightCm:  profile.HeightM * 100,
		WeightKg:  weight,
		Gender:    nutrition.Gender(profile.Gender),
		Age:       profile.Age,
		Goal:      nutrition.Goal(profile.Goal),
		Activity:  nutrition.ActivityLevel(profile.ActivityLevel),
		Intensity: nutrition.TrainingIntensity(profile.TrainingIntensity),
	})
	if err != nil {
		return Profile{}, fmt.Errorf("%w: %s", ErrInvalid, err)
	}

	updated, err := scanProfile(s.pool.QueryRow(ctx, `UPDATE user_profiles SET
			target_calories = $2, target_carbs = $3, target_protein = $4, target_fat = $5
		WHERE user_id = $1
		RETURNING `+profileColumns,
		userID, targets.Calories, targets.Carbs, targets.Protein, targets.Fat))
	if errors.Is(err, pgx.ErrNoRows) {
		return Profile{}, ErrNotFound
	}
	if err != nil {
		return Profile{}, fmt.Errorf("store: recalculate targets: %w", err)
	}
	return updated, nil
}

func validateProfileInput(in ProfileInput) error {
	if in.Gender != nil {
		switch strings.TrimSpace(*in.Gender) {
		case string(nutrition.GenderMale), string(nutrition.GenderFemale):
		default:
			return fmt.Errorf("%w: gender must be male|female", ErrInvalid)
		}
	}
	if in.Goal != nil {
		switch strings.TrimSpace(*in.Goal) {
		case string(nutrition.GoalDiet), string(nutrition.GoalLeanCut),
			string(nutrition.GoalLeanGain), string(nutrition.GoalBulkUp):
		default:
			return fmt.Errorf("%w: goal must be diet|lean_cut|lean_gain|bulk_up", ErrInvalid)
		}
	}
	if in.ActivityLevel != nil {
		switch strings.TrimSpace(*in.ActivityLevel) {
		case string(nutrition.ActivitySedentary), string(nutrition.ActivityLight),
			string(nutrition.ActivityModerate), string(nutrition.ActivityActive),
			string(nutrition.ActivityVeryActive):
		default:
			return fmt.Errorf("%w: activity_level must be sedentary|light|moderate|active|very_active", ErrInvalid)
		}
	}
	if in.TrainingIntensity != nil {
		switch strings.TrimSpace(*in.TrainingIntensity) {
		case string(nutrition.IntensityLow), string(nutrition.IntensityModerate),
			string(nutrition.IntensityHigh), string(nutrition.IntensityVeryHigh):
		default:
			return fmt.Errorf("%w: training_intensity must be low|moderate|high|very_high", ErrInvalid)
		}
	}
	if in.Age != nil && (*in.Age < 1 || *in.Age > 120) {
		return fmt.Errorf("%w: age must be between 1 and 120", ErrInvalid)
	}
	if in.HeightM != nil && (*in.HeightM < 0.5 || *in.HeightM > 2.5) {
		return fmt.Errorf("%w: height_m must be between 0.5 and 2.5", ErrInvalid)
	}
	if in.TargetCalories != nil && *in.TargetCalories < 0 {
		return fmt.Errorf("%w: target_calories must not be negative", ErrInvalid)
	}
	for _, macro := range []*float64{in.TargetCarbs, in.TargetProtein, in.TargetFat} {
		if macro != nil && *macro < 0 {
			return fmt.Errorf("%w: macro targets must not be negative", ErrInvalid)
		}
	}
	return nil
}
