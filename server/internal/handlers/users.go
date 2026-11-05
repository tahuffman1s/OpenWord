package handlers

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/tahuffman1s/openword/server/internal/httpx"
	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
	"github.com/tahuffman1s/openword/server/internal/streaks"
)

// Relation values returned alongside other users' profiles.
const (
	relNone      = "none"
	relFriend    = "friend"
	relRequested = "requested" // I sent them a request
	relIncoming  = "incoming"  // they sent me one
)

// relationFunc classifies other users relative to me, from one batch of
// queries so that search results do not cost three queries each.
func (s *Server) relationFunc(ctx context.Context, meID string) (func(otherID string) string, error) {
	friends, err := s.store.FriendIDs(ctx, meID)
	if err != nil {
		return nil, err
	}
	in, out, err := s.store.ListFriendRequests(ctx, meID)
	if err != nil {
		return nil, err
	}
	isFriend := map[string]bool{}
	for _, id := range friends {
		isFriend[id] = true
	}
	incoming := map[string]bool{}
	for _, r := range in {
		incoming[r.FromUser] = true
	}
	outgoing := map[string]bool{}
	for _, r := range out {
		outgoing[r.ToUser] = true
	}
	return func(id string) string {
		switch {
		case isFriend[id]:
			return relFriend
		case outgoing[id]:
			return relRequested
		case incoming[id]:
			return relIncoming
		default:
			return relNone
		}
	}, nil
}

// GET /api/users/{id}/avatar?v=N (public)
func (s *Server) getAvatar(w http.ResponseWriter, r *http.Request) {
	data, ctype, version, err := s.store.GetAvatar(r.Context(), r.PathValue("id"))
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			w.Header().Set("Cache-Control", "no-cache")
			httpx.NotFound(w, "No avatar.")
			return
		}
		httpx.Internal(w, err)
		return
	}
	etag := fmt.Sprintf(`"%d"`, version)
	w.Header().Set("ETag", etag)
	// The URL carries the version, so the response can be cached forever;
	// a new avatar means a new URL.
	if v, _ := strconv.Atoi(r.URL.Query().Get("v")); v == version {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	} else {
		w.Header().Set("Cache-Control", "public, max-age=60")
	}
	if strings.Contains(r.Header.Get("If-None-Match"), etag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("Content-Type", ctype)
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

type searchUser struct {
	model.PublicUser
	Relation string `json:"relation"`
}

// GET /api/users/search?q=
func (s *Server) searchUsers(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	me := userFrom(ctx)
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" || len(q) > 64 {
		httpx.BadRequest(w, "q is required (1–64 characters)")
		return
	}
	users, err := s.store.SearchUsers(ctx, q, me.ID, 20)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	rel, err := s.relationFunc(ctx, me.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	out := make([]searchUser, 0, len(users))
	for _, u := range users {
		out = append(out, searchUser{PublicUser: u.Public(), Relation: rel(u.ID)})
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"users": out})
}

type achievementJSON struct {
	ID       string    `json:"id"`
	Kind     string    `json:"kind"`
	Key      string    `json:"key"`
	Title    string    `json:"title"`
	Detail   string    `json:"detail"`
	EarnedAt time.Time `json:"earnedAt"`
}

func toAchievementJSON(a model.Achievement) achievementJSON {
	return achievementJSON{
		ID:       a.ID,
		Kind:     a.Kind,
		Key:      a.Key,
		Title:    a.Title,
		Detail:   a.Detail,
		EarnedAt: a.EarnedAt.UTC(),
	}
}

// GET /api/users/{username}
func (s *Server) getUserProfile(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	me := userFrom(ctx)
	u, err := s.store.GetUserByUsername(ctx, r.PathValue("username"))
	if storeErr(w, err, "No such user.") {
		return
	}
	rel, err := s.relationFunc(ctx, me.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	relation := rel(u.ID)
	if u.ID == me.ID {
		relation = "self"
	}
	streak, err := s.store.GetStreak(ctx, u.ID)
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		httpx.Internal(w, err)
		return
	}
	var friendStreak *streaks.Friend
	if relation == relFriend {
		today := streaks.Today(s.now(), userLocation(me))
		fs, err := streaks.ForFriends(ctx, s.store, me.ID, []string{u.ID}, today)
		if err != nil {
			httpx.Internal(w, err)
			return
		}
		f := fs[u.ID]
		friendStreak = &f
	}
	achs, err := s.store.ListAchievements(ctx, u.ID, 20)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	out := make([]achievementJSON, 0, len(achs))
	for _, a := range achs {
		out = append(out, toAchievementJSON(a))
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"user":         u.Public(),
		"streak":       streak.JSON(),
		"friendStreak": friendStreak,
		"achievements": out,
		"relation":     relation,
	})
}
