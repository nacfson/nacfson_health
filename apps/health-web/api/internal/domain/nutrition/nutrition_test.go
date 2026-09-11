package nutrition

import "testing"

func TestCalculateTargetsGolden(t *testing.T) {
	// Male 80kg, 175cm, 30y, moderate activity+intensity, lean_gain
	got, err := CalculateTargets(Input{
		HeightCm:  175,
		WeightKg:  80,
		Gender:    GenderMale,
		Age:       30,
		Goal:      GoalLeanGain,
		Activity:  ActivityModerate,
		Intensity: IntensityModerate,
	})
	if err != nil {
		t.Fatal(err)
	}
	// BMR = 10*80 + 6.25*175 - 5*30 + 5 = 800 + 1093.75 - 150 + 5 = 1748.75
	// TDEE = 1748.75 * 1.55 = 2710.5625
	// lean_gain +200 = 2910.5625 → round/10*10 = 2910
	// protein = 80*2 = 160
	// fat = 2910*0.225/9 = 72.75 → 73
	// carbs = (2910 - 160*4 - 72.75*9)/4 = (2910-640-654.75)/4 = 1615.25/4 = 403.8125 → 404
	if got.Calories != 2910 {
		t.Fatalf("calories=%d want 2910", got.Calories)
	}
	if got.Protein != 160 {
		t.Fatalf("protein=%v want 160", got.Protein)
	}
	if got.Fat != 73 {
		t.Fatalf("fat=%v want 73", got.Fat)
	}
	if got.Carbs != 404 {
		t.Fatalf("carbs=%v want 404", got.Carbs)
	}
}

func TestDietFloor(t *testing.T) {
	got, err := CalculateTargets(Input{
		HeightCm:  160,
		WeightKg:  50,
		Gender:    GenderFemale,
		Age:       25,
		Goal:      GoalDiet,
		Activity:  ActivitySedentary,
		Intensity: IntensityLow,
	})
	if err != nil {
		t.Fatal(err)
	}
	// BMR = 10*50 + 6.25*160 - 5*25 - 161 = 500 + 1000 - 125 - 161 = 1214
	// TDEE = 1214 * 1.2 = 1456.8
	// diet -500 = 956.8; floor = max(1200, 50*22=1100) = 1200 → 1200
	if got.Calories != 1200 {
		t.Fatalf("calories=%d want 1200 (diet floor)", got.Calories)
	}
}

func TestInvalidInput(t *testing.T) {
	if _, err := CalculateTargets(Input{WeightKg: 0, HeightCm: 170, Age: 30}); err == nil {
		t.Fatal("expected error")
	}
}