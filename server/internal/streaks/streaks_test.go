package streaks

import (
	"testing"
	"time"
)

func days(ds ...string) []string { return ds }

func TestCompute(t *testing.T) {
	const today = "2026-03-10"
	cases := []struct {
		name string
		a, b []string
		want Friend
	}{
		{"no overlap", days("2026-03-10"), days("2026-03-09"), Friend{}},
		{"both today, three days",
			days("2026-03-08", "2026-03-09", "2026-03-10"),
			days("2026-03-07", "2026-03-08", "2026-03-09", "2026-03-10"),
			Friend{Current: 3, Best: 3, LastDay: "2026-03-10", AtRisk: false}},
		{"alive from yesterday, at risk",
			days("2026-03-08", "2026-03-09", "2026-03-10"),
			days("2026-03-08", "2026-03-09"),
			Friend{Current: 2, Best: 2, LastDay: "2026-03-09", AtRisk: true}},
		{"broken two days ago keeps best",
			days("2026-03-01", "2026-03-02", "2026-03-03", "2026-03-08"),
			days("2026-03-01", "2026-03-02", "2026-03-03", "2026-03-08"),
			Friend{Current: 0, Best: 3, LastDay: "", AtRisk: false}},
		{"best is older than current",
			days("2026-03-01", "2026-03-02", "2026-03-03", "2026-03-04", "2026-03-09", "2026-03-10"),
			days("2026-03-01", "2026-03-02", "2026-03-03", "2026-03-04", "2026-03-09", "2026-03-10"),
			Friend{Current: 2, Best: 4, LastDay: "2026-03-10", AtRisk: false}},
		{"duplicates and unsorted input",
			days("2026-03-10", "2026-03-09", "2026-03-10"),
			days("2026-03-09", "2026-03-10", "2026-03-09"),
			Friend{Current: 2, Best: 2, LastDay: "2026-03-10"}},
		{"crosses month boundary",
			days("2026-02-27", "2026-02-28", "2026-03-01"),
			days("2026-02-27", "2026-02-28", "2026-03-01"),
			func() Friend {
				return Friend{Current: 0, Best: 3}
			}()},
		{"empty", nil, nil, Friend{}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Compute(c.a, c.b, today)
			if got != c.want {
				t.Errorf("got %+v, want %+v", got, c.want)
			}
		})
	}
}

func TestComputeMonthBoundaryToday(t *testing.T) {
	a := days("2026-02-27", "2026-02-28", "2026-03-01")
	got := Compute(a, a, "2026-03-01")
	if got.Current != 3 || got.AtRisk {
		t.Errorf("got %+v", got)
	}
}

func TestAddDaysAndToday(t *testing.T) {
	if AddDays("2024-02-28", 1) != "2024-02-29" {
		t.Error("leap day")
	}
	if AddDays("2026-01-01", -1) != "2025-12-31" {
		t.Error("year boundary")
	}
	if AddDays("garbage", 1) != "garbage" {
		t.Error("garbage passthrough")
	}
	loc, _ := time.LoadLocation("Pacific/Auckland")
	now := time.Date(2026, 3, 10, 23, 30, 0, 0, time.UTC) // already the 11th in NZ
	if Today(now, loc) != "2026-03-11" {
		t.Errorf("Today = %s", Today(now, loc))
	}
	if Today(now, time.UTC) != "2026-03-10" {
		t.Error("utc today")
	}
}
