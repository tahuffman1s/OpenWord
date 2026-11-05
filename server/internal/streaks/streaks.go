// Package streaks computes the friend streak between two users from their
// 'learn' activity days.
//
// Definition (also in docs/api.md): a friend streak is the number of
// consecutive calendar days, counted backwards from today or yesterday
// (whichever is the latest day BOTH users have), on which both users have a
// 'learn' activity day. If neither today nor yesterday is shared, the
// current streak is 0. The streak is "at risk" when it is alive as of
// yesterday but one of the two has not learned today yet. Best is the
// longest such run within the loaded window.
package streaks

import (
	"sort"
	"time"
)

// DayLayout is the calendar-day format used throughout the API.
const DayLayout = "2006-01-02"

// Window is how far back learn days are loaded for streak computation.
const Window = 400

// Friend is the result of a friend streak computation.
type Friend struct {
	Current int    `json:"current"`
	Best    int    `json:"best"`
	LastDay string `json:"lastDay"` // last shared day of the current streak, "" if none
	AtRisk  bool   `json:"atRisk"`
}

// AddDays shifts a YYYY-MM-DD day by n calendar days. Days are treated as
// UTC midnights so DST never bites.
func AddDays(day string, n int) string {
	t, err := time.Parse(DayLayout, day)
	if err != nil {
		return day
	}
	return t.AddDate(0, 0, n).Format(DayLayout)
}

// Today returns the current calendar day in loc.
func Today(now time.Time, loc *time.Location) string {
	return now.In(loc).Format(DayLayout)
}

// Compute evaluates the friend streak from two lists of learn days
// (any order, duplicates tolerated) as of `today`.
func Compute(aDays, bDays []string, today string) Friend {
	shared := intersect(aDays, bDays)
	if len(shared) == 0 {
		return Friend{}
	}
	has := make(map[string]bool, len(shared))
	for _, d := range shared {
		has[d] = true
	}

	yesterday := AddDays(today, -1)
	var start string
	switch {
	case has[today]:
		start = today
	case has[yesterday]:
		start = yesterday
	}

	f := Friend{Best: longestRun(shared)}
	if start == "" {
		return f
	}
	f.LastDay = start
	for d := start; has[d]; d = AddDays(d, -1) {
		f.Current++
	}
	// Alive as of yesterday, but not yet secured for today.
	f.AtRisk = start == yesterday
	return f
}

// intersect returns the sorted, de-duplicated days present in both lists.
func intersect(a, b []string) []string {
	set := make(map[string]struct{}, len(a))
	for _, d := range a {
		set[d] = struct{}{}
	}
	seen := map[string]struct{}{}
	var out []string
	for _, d := range b {
		if _, ok := set[d]; !ok {
			continue
		}
		if _, dup := seen[d]; dup {
			continue
		}
		seen[d] = struct{}{}
		out = append(out, d)
	}
	sort.Strings(out)
	return out
}

// longestRun returns the longest run of consecutive days in a sorted,
// de-duplicated list.
func longestRun(days []string) int {
	best, run := 0, 0
	prev := ""
	for _, d := range days {
		if prev != "" && AddDays(prev, 1) == d {
			run++
		} else {
			run = 1
		}
		if run > best {
			best = run
		}
		prev = d
	}
	return best
}
