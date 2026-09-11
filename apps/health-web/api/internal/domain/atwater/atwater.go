package atwater

import "math"

// KcalFromMacros ports Flutter kcalFromMacros exactly:
// non-finite → 0, any negative → 0, else round(c*4 + p*4 + f*9).
func KcalFromMacros(carbs, protein, fat float64) int {
	if math.IsNaN(carbs) || math.IsInf(carbs, 0) ||
		math.IsNaN(protein) || math.IsInf(protein, 0) ||
		math.IsNaN(fat) || math.IsInf(fat, 0) {
		return 0
	}
	if carbs < 0 || protein < 0 || fat < 0 {
		return 0
	}
	return int(math.Round(carbs*4 + protein*4 + fat*9))
}