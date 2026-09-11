package nutrition

import "math"

type Gender string

const (
	GenderMale   Gender = "male"
	GenderFemale Gender = "female"
)

type Goal string

const (
	GoalDiet     Goal = "diet"
	GoalLeanCut  Goal = "lean_cut"
	GoalLeanGain Goal = "lean_gain"
	GoalBulkUp   Goal = "bulk_up"
)

type ActivityLevel string

const (
	ActivitySedentary  ActivityLevel = "sedentary"
	ActivityLight      ActivityLevel = "light"
	ActivityModerate   ActivityLevel = "moderate"
	ActivityActive     ActivityLevel = "active"
	ActivityVeryActive ActivityLevel = "very_active"
)

type TrainingIntensity string

const (
	IntensityLow      TrainingIntensity = "low"
	IntensityModerate TrainingIntensity = "moderate"
	IntensityHigh     TrainingIntensity = "high"
	IntensityVeryHigh TrainingIntensity = "very_high"
)

type Input struct {
	HeightCm  float64
	WeightKg  float64
	Gender    Gender
	Age       int
	Goal      Goal
	Activity  ActivityLevel
	Intensity TrainingIntensity
}

type Targets struct {
	Calories int
	Carbs    float64
	Protein  float64
	Fat      float64
}

func activityMultiplier(a ActivityLevel) float64 {
	switch a {
	case ActivitySedentary:
		return 1.2
	case ActivityLight:
		return 1.375
	case ActivityModerate:
		return 1.55
	case ActivityActive:
		return 1.725
	case ActivityVeryActive:
		return 1.9
	default:
		return 1.55
	}
}

func proteinGPerKg(i TrainingIntensity) float64 {
	switch i {
	case IntensityLow:
		return 1.8
	case IntensityModerate:
		return 2.0
	case IntensityHigh:
		return 2.2
	case IntensityVeryHigh:
		return 2.4
	default:
		return 2.0
	}
}

// ComputeBMR is Mifflin-St Jeor (kcal/day). heightCm is centimeters.
func ComputeBMR(weightKg, heightCm float64, age int, gender Gender) float64 {
	base := 10*weightKg + 6.25*heightCm - 5*float64(age)
	if gender == GenderFemale {
		return base - 161
	}
	return base + 5
}

func applyGoalAdjustment(tdee, weightKg float64, goal Goal) float64 {
	switch goal {
	case GoalDiet:
		adjusted := tdee - 500
		floor := math.Max(1200.0, weightKg*22)
		return math.Max(floor, adjusted)
	case GoalLeanCut:
		return tdee - 200
	case GoalLeanGain:
		return tdee + 200
	case GoalBulkUp:
		return tdee + 500
	default:
		return tdee + 200
	}
}

// CalculateTargets ports Flutter calculateTargets.
func CalculateTargets(in Input) (Targets, error) {
	if in.WeightKg <= 0 {
		return Targets{}, errInvalid("weightKg")
	}
	if in.HeightCm <= 0 {
		return Targets{}, errInvalid("heightCm")
	}
	if in.Age <= 0 {
		return Targets{}, errInvalid("age")
	}
	if in.Activity == "" {
		in.Activity = ActivityModerate
	}
	if in.Intensity == "" {
		in.Intensity = IntensityModerate
	}
	if in.Goal == "" {
		in.Goal = GoalLeanGain
	}
	if in.Gender == "" {
		in.Gender = GenderMale
	}

	bmr := ComputeBMR(in.WeightKg, in.HeightCm, in.Age, in.Gender)
	tdee := bmr * activityMultiplier(in.Activity)
	targetKcal := applyGoalAdjustment(tdee, in.WeightKg, in.Goal)
	kcalRounded := int(math.Round(targetKcal/10)) * 10

	proteinG := in.WeightKg * proteinGPerKg(in.Intensity)
	fatG := float64(kcalRounded) * 0.225 / 9
	remaining := float64(kcalRounded) - proteinG*4 - fatG*9
	carbsG := math.Max(0, remaining/4)

	return Targets{
		Calories: kcalRounded,
		Carbs:    math.Round(carbsG),
		Protein:  math.Round(proteinG),
		Fat:      math.Round(fatG),
	}, nil
}

type invalidArg string

func (e invalidArg) Error() string { return "invalid " + string(e) }

func errInvalid(name string) error { return invalidArg(name) }