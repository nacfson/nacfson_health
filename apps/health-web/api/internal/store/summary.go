package store

import (
	"context"
	"math"
	"sort"

	"github.com/google/uuid"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/domain/exercisekcal"
)

// Summary is the daily dashboard DTO (요약 tab).
type Summary struct {
	Date                  string   `json:"date"`
	ConsumedCalories      int      `json:"consumed_calories"`
	TargetCalories        int      `json:"target_calories"`
	Carbs                 float64  `json:"carbs"`
	Protein               float64  `json:"protein"`
	Fat                   float64  `json:"fat"`
	TargetCarbs           float64  `json:"target_carbs"`
	TargetProtein         float64  `json:"target_protein"`
	TargetFat             float64  `json:"target_fat"`
	IsWorkoutDay          bool     `json:"is_workout_day"`
	Muscles               []string `json:"muscles"`
	TotalVolume           float64  `json:"total_volume"`
	AvgRPE                float64  `json:"avg_rpe"`
	EstimatedExerciseKcal float64  `json:"estimated_exercise_kcal"`
	SetCount              int      `json:"set_count"`
}

// Summary aggregates one calendar day (store timezone) for the 요약 tab.
func (s *Store) Summary(ctx context.Context, userID uuid.UUID, date string) (Summary, error) {
	day, err := s.Day(date)
	if err != nil {
		return Summary{}, err
	}
	window := Range{Start: day, End: day.AddDate(0, 0, 1)}

	diet, err := s.ListDiet(ctx, userID, window)
	if err != nil {
		return Summary{}, err
	}
	exercise, err := s.ListExercise(ctx, userID, window)
	if err != nil {
		return Summary{}, err
	}
	profile, found, err := s.GetProfile(ctx, userID)
	if err != nil {
		return Summary{}, err
	}

	summary := Summary{Date: date, Muscles: []string{}, SetCount: len(exercise)}
	for _, rec := range diet {
		summary.ConsumedCalories += rec.TotalCalories
		summary.Carbs += rec.Carbs
		summary.Protein += rec.Protein
		summary.Fat += rec.Fat
	}
	if found {
		summary.TargetCalories = profile.TargetCalories
		summary.TargetCarbs = profile.TargetCarbs
		summary.TargetProtein = profile.TargetProtein
		summary.TargetFat = profile.TargetFat
	}

	chronological := make([]ExerciseRecord, len(exercise))
	copy(chronological, exercise)
	sort.SliceStable(chronological, func(i, j int) bool {
		return chronological[i].RecordedAt.Before(chronological[j].RecordedAt)
	})

	sets := make([]exercisekcal.Set, 0, len(chronological))
	seen := make(map[string]bool, len(chronological))
	var rpeSum float64
	var rpeCount int
	for _, rec := range chronological {
		sets = append(sets, exercisekcal.Set{
			ExerciseType: rec.ExerciseType,
			Weight:       rec.Weight,
			Reps:         rec.Reps,
			SetType:      rec.SetType,
		})
		if rec.ExerciseType != "" && !seen[rec.ExerciseType] {
			seen[rec.ExerciseType] = true
			summary.Muscles = append(summary.Muscles, rec.ExerciseType)
		}
		if rec.SetType == SetTypeWork || rec.SetType == SetTypeDrop {
			summary.TotalVolume += rec.Weight * float64(rec.Reps)
		}
		if rec.RPE > 0 {
			rpeSum += rec.RPE
			rpeCount++
		}
	}
	summary.IsWorkoutDay = len(chronological) > 0
	summary.TotalVolume = round2(summary.TotalVolume)
	summary.EstimatedExerciseKcal = round2(exercisekcal.Estimate(sets))
	if rpeCount > 0 {
		summary.AvgRPE = round1(rpeSum / float64(rpeCount))
	}
	return summary, nil
}

func round1(value float64) float64 { return math.Round(value*10) / 10 }

func round2(value float64) float64 { return math.Round(value*100) / 100 }
