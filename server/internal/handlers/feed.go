package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/tahuffman1s/openword/server/internal/httpx"
	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
	"github.com/tahuffman1s/openword/server/internal/validate"
)

type achievementInput struct {
	Key      string     `json:"key"`
	Kind     string     `json:"kind"`
	Title    string     `json:"title"`
	Detail   string     `json:"detail"`
	EarnedAt *time.Time `json:"earnedAt"`
}

// toModel validates in and builds the row (without ID/CreatedAt).
func (s *Server) achievementFromInput(userID string, in achievementInput) (*model.Achievement, error) {
	key, err := validate.ShortText(in.Key, 80, "key")
	if err != nil || key == "" {
		return nil, errors.New("key is required (≤ 80 characters)")
	}
	if err := validate.AchievementKind(in.Kind); err != nil {
		return nil, err
	}
	title, err := validate.ShortText(in.Title, 120, "title")
	if err != nil || title == "" {
		return nil, errors.New("title is required (≤ 120 characters)")
	}
	detail, err := validate.ShortText(in.Detail, 400, "detail")
	if err != nil {
		return nil, err
	}
	earned := s.now().UTC()
	if in.EarnedAt != nil {
		earned = in.EarnedAt.UTC()
		if earned.After(s.now().Add(24 * time.Hour)) {
			return nil, errors.New("earnedAt is in the future")
		}
	}
	return &model.Achievement{UserID: userID, Key: key, Kind: in.Kind, Title: title, Detail: detail, EarnedAt: earned}, nil
}

// POST /api/achievements
func (s *Server) postAchievement(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	var in achievementInput
	if err := httpx.Decode(r, &in); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	a, err := s.achievementFromInput(me.ID, in)
	if err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	created, err := s.store.CreateAchievement(r.Context(), a)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	httpx.JSON(w, status, map[string]any{"achievement": toAchievementJSON(*a)})
}

// POST /api/achievements/batch {achievements:[...]}
func (s *Server) postAchievementBatch(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	var req struct {
		Achievements []achievementInput `json:"achievements"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	if len(req.Achievements) > 500 {
		httpx.BadRequest(w, "at most 500 achievements per batch")
		return
	}
	rows := make([]*model.Achievement, 0, len(req.Achievements))
	for i, in := range req.Achievements {
		a, err := s.achievementFromInput(me.ID, in)
		if err != nil {
			httpx.BadRequest(w, "achievements["+strconv.Itoa(i)+"]: "+err.Error())
			return
		}
		rows = append(rows, a)
	}
	created := 0
	for _, a := range rows {
		ok, err := s.store.CreateAchievement(r.Context(), a)
		if err != nil {
			httpx.Internal(w, err)
			return
		}
		if ok {
			created++
		}
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"created": created})
}

type feedItem struct {
	ID       string           `json:"id"`
	User     model.PublicUser `json:"user"`
	Kind     string           `json:"kind"`
	Key      string           `json:"key"`
	Title    string           `json:"title"`
	Detail   string           `json:"detail"`
	EarnedAt time.Time        `json:"earnedAt"`
	Cheers   int              `json:"cheers"`
	Cheered  bool             `json:"cheered"`
	Mine     bool             `json:"mine"`
}

// GET /api/feed?before=<RFC3339>&limit=30
func (s *Server) getFeed(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	me := userFrom(ctx)
	q := r.URL.Query()
	before := s.now().Add(time.Hour).UTC() // tolerate slight client clock skew
	if b := q.Get("before"); b != "" {
		t, err := time.Parse(time.RFC3339Nano, b)
		if err != nil {
			httpx.BadRequest(w, "before must be an RFC 3339 timestamp")
			return
		}
		before = t
	}
	limit := 30
	if l := q.Get("limit"); l != "" {
		n, err := strconv.Atoi(l)
		if err != nil || n < 1 || n > 100 {
			httpx.BadRequest(w, "limit must be 1–100")
			return
		}
		limit = n
	}
	friendIDs, err := s.store.FriendIDs(ctx, me.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	ids := append([]string{me.ID}, friendIDs...)
	page, err := s.store.Feed(ctx, ids, before, limit, me.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	users, err := s.store.GetUsers(ctx, ids)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	items := make([]feedItem, 0, len(page.Items))
	for _, a := range page.Items {
		u, ok := users[a.UserID]
		if !ok {
			continue
		}
		items = append(items, feedItem{
			ID: a.ID, User: u.Public(), Kind: a.Kind, Key: a.Key, Title: a.Title, Detail: a.Detail,
			EarnedAt: a.EarnedAt.UTC(), Cheers: page.Cheers[a.ID], Cheered: page.Cheered[a.ID], Mine: a.UserID == me.ID,
		})
	}
	var nextBefore *string
	if len(page.Items) == limit {
		t := page.Items[len(page.Items)-1].EarnedAt.UTC().Format(time.RFC3339Nano)
		nextBefore = &t
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items, "nextBefore": nextBefore})
}

// cheerable loads the achievement and checks it belongs to me or a friend.
func (s *Server) cheerable(w http.ResponseWriter, r *http.Request) (*model.Achievement, bool) {
	ctx := r.Context()
	me := userFrom(ctx)
	a, err := s.store.GetAchievement(ctx, r.PathValue("id"))
	if storeErr(w, err, "No such achievement.") {
		return nil, false
	}
	if a.UserID != me.ID {
		friends, err := s.store.AreFriends(ctx, me.ID, a.UserID)
		if err != nil {
			httpx.Internal(w, err)
			return nil, false
		}
		if !friends {
			httpx.NotFound(w, "No such achievement.")
			return nil, false
		}
	}
	return a, true
}

// POST /api/feed/{id}/cheer
func (s *Server) cheer(w http.ResponseWriter, r *http.Request) {
	a, ok := s.cheerable(w, r)
	if !ok {
		return
	}
	me := userFrom(r.Context())
	if err := s.store.AddCheer(r.Context(), a.ID, me.ID, s.now().UTC()); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			httpx.NotFound(w, "No such achievement.")
			return
		}
		httpx.Internal(w, err)
		return
	}
	n, err := s.store.CountCheers(r.Context(), a.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"cheers": n, "cheered": true})
}

// DELETE /api/feed/{id}/cheer
func (s *Server) uncheer(w http.ResponseWriter, r *http.Request) {
	a, ok := s.cheerable(w, r)
	if !ok {
		return
	}
	me := userFrom(r.Context())
	if err := s.store.RemoveCheer(r.Context(), a.ID, me.ID); err != nil {
		httpx.Internal(w, err)
		return
	}
	n, err := s.store.CountCheers(r.Context(), a.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"cheers": n, "cheered": false})
}
