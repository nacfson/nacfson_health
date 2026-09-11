package atwater

import (
	"math"
	"testing"
)

func TestKcalFromMacros(t *testing.T) {
	cases := []struct {
		name    string
		c, p, f float64
		want    int
	}{
		{"ten each", 10, 10, 10, 170},
		{"half up", 1.5, 1.5, 1.5, 26},
		{"macros", 30, 20, 5, 245},
		{"larger", 60, 30, 15, 495},
		{"nan carbs", math.NaN(), 10, 10, 0},
		{"inf protein", 10, math.Inf(1), 10, 0},
		{"neg carbs", -1, 10, 10, 0},
		{"neg protein", 10, -1, 10, 0},
		{"neg fat", 10, 10, -1, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := KcalFromMacros(tc.c, tc.p, tc.f)
			if got != tc.want {
				t.Fatalf("got %d want %d", got, tc.want)
			}
		})
	}
}