package exercisekcal

import "testing"

func TestEstimate(t *testing.T) {
	cases := []struct {
		name string
		sets []Set
		want float64
	}{
		{"legs work", []Set{{"하체", 100, 8, "work"}}, 8.0},
		{"shoulder", []Set{{"어깨", 100, 10, "work"}}, 6.0},
		{"core", []Set{{"코어", 100, 10, "work"}}, 5.0},
		{"unknown", []Set{{"미분류", 100, 10, "work"}}, 7.0},
		{"cardio", []Set{{"유산소", 100, 10, "work"}}, 0.0},
		{"warmup excluded", []Set{{"하체", 100, 8, "warmup"}}, 0.0},
		{"failure excluded", []Set{{"하체", 100, 8, "failure"}}, 0.0},
		{"drop included", []Set{{"하체", 100, 8, "drop"}}, 8.0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Estimate(tc.sets)
			if got != tc.want {
				t.Fatalf("got %v want %v", got, tc.want)
			}
		})
	}
}