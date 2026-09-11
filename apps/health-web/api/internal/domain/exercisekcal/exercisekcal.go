package exercisekcal

// Body-part coefficients (Korean keys — matches Flutter exercise_type values).
var coefficients = map[string]float64{
	"하체":  1.00,
	"등":   0.85,
	"가슴":  0.85,
	"어깨":  0.60,
	"팔":   0.60,
	"코어":  0.50,
	"유산소": 0.00,
	"기타":  0.70,
}

const (
	fallbackCoefficient = 0.70
	kcalPerKgVolume     = 0.01
)

type Set struct {
	ExerciseType string
	Weight       float64
	Reps         int
	SetType      string // warmup|work|drop|failure
}

func CoefficientFor(bodyPart string) float64 {
	if c, ok := coefficients[bodyPart]; ok {
		return c
	}
	return fallbackCoefficient
}

func countsTowardVolume(setType string) bool {
	return setType == "work" || setType == "drop"
}

// Estimate ports Flutter estimateExerciseCalories: Σ(weight×reps×0.01×coeff) for work|drop.
func Estimate(sets []Set) float64 {
	var total float64
	for _, s := range sets {
		if !countsTowardVolume(s.SetType) {
			continue
		}
		total += s.Weight * float64(s.Reps) * kcalPerKgVolume * CoefficientFor(s.ExerciseType)
	}
	return total
}