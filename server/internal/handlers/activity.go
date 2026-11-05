package handlers

import (
	"errors"
	"net/http"

	"github.com/tahuffman1s/openword/server/internal/httpx"
	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
	"github.com/tahuffman1s/openword/server/internal/streaks"
	"github.com/tahuffman1s/openword/server/internal/validate"
)

// Bounds for POST /api/activity days, relative to the user's local today.
const (
	activityMaxFutureDays = 3
	activityMaxPastDays   = 400
)

// POST /api/activity {day, kind, count?}
func (s *Server) postActivity(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	var req struct {
		Day   string `json:"day"`
		Kind  string `json:"kind"`
		Count int    `json:"count"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	if err := validate.Day(req.Day); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	if err := validate.ActivityKind(req.Kind); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	if req.Count < 0 || req.Count > 10000 {
		httpx.BadRequest(w, "count must be between 0 and 10000")
		return
	}
	if req.Count == 0 {
		req.Count = 1
	}
	// The client picks the local calendar day; we only sanity-check it
	// against our idea of their today so a wrong clock cannot write 2099.
	today := streaks.Today(s.now(), userLocation(me))
	if req.Day > streaks.AddDays(today, activityMaxFutureDays) || req.Day < streaks.AddDays(today, -activityMaxPastDays) {
		httpx.BadRequest(w, "day is too far from today")
		return
	}
	now := s.now().UTC()
	a, err := s.store.UpsertActivity(r.Context(), &model.ActivityDay{
		UserID: me.ID, Day: req.Day, Kind: req.Kind, Count: req.Count, FirstAt: now, LastAt: now,
	})
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"day": a.Day, "kind": a.Kind, "count": a.Count})
}

// GET /api/activity?from=&to=
func (s *Server) getActivity(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	q := r.URL.Query()
	today := streaks.Today(s.now(), userLocation(me))
	from, to := q.Get("from"), q.Get("to")
	if to == "" {
		to = today
	}
	if from == "" {
		from = streaks.AddDays(to, -90)
	}
	if err := validate.Day(from); err != nil {
		httpx.BadRequest(w, "from: "+err.Error())
		return
	}
	if err := validate.Day(to); err != nil {
		httpx.BadRequest(w, "to: "+err.Error())
		return
	}
	if from > to {
		httpx.BadRequest(w, "from must not be after to")
		return
	}
	rows, err := s.store.ListActivity(r.Context(), me.ID, from, to)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	type dayJSON struct {
		Day   string         `json:"day"`
		Kinds map[string]int `json:"kinds"`
	}
	days := []dayJSON{}
	for _, a := range rows {
		if len(days) == 0 || days[len(days)-1].Day != a.Day {
			days = append(days, dayJSON{Day: a.Day, Kinds: map[string]int{}})
		}
		days[len(days)-1].Kinds[a.Kind] = a.Count
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"from": from, "to": to, "days": days})
}

// PUT /api/streak {current, best, freezes, lastDay}
func (s *Server) putStreak(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	var req struct {
		Current int    `json:"current"`
		Best    int    `json:"best"`
		Freezes int    `json:"freezes"`
		LastDay string `json:"lastDay"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	if req.Current < 0 || req.Best < 0 || req.Freezes < 0 {
		httpx.BadRequest(w, "streak values must not be negative")
		return
	}
	if req.LastDay != "" {
		if err := validate.Day(req.LastDay); err != nil {
			httpx.BadRequest(w, "lastDay: "+err.Error())
			return
		}
	}
	st := &model.StreakSnapshot{
		UserID: me.ID, Current: req.Current, Best: max(req.Best, req.Current),
		Freezes: req.Freezes, LastDay: req.LastDay, UpdatedAt: s.now().UTC(),
	}
	if err := s.store.PutStreak(r.Context(), st); err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"streak": st.JSON()})
}

type friendStreakEntry struct {
	User    model.PublicUser `json:"user"`
	Current int              `json:"current"`
	Best    int              `json:"best"`
	LastDay string           `json:"lastDay"`
	AtRisk  bool             `json:"atRisk"`
}

// GET /api/streaks
func (s *Server) getStreaks(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	me := userFrom(ctx)
	mine, err := s.store.GetStreak(ctx, me.ID)
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		httpx.Internal(w, err)
		return
	}
	friends, err := s.store.ListFriends(ctx, me.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	ids := make([]string, len(friends))
	for i, f := range friends {
		ids[i] = f.User.ID
	}
	today := streaks.Today(s.now(), userLocation(me))
	fs, err := streaks.ForFriends(ctx, s.store, me.ID, ids, today)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	out := make([]friendStreakEntry, 0, len(friends))
	for _, f := range friends {
		st := fs[f.User.ID]
		out = append(out, friendStreakEntry{
			User: f.User.Public(), Current: st.Current, Best: st.Best, LastDay: st.LastDay, AtRisk: st.AtRisk,
		})
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"streak": mine.JSON(), "friendStreaks": out})
}
