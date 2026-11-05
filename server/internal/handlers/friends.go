package handlers

import (
	"errors"
	"net/http"
	"time"

	"github.com/tahuffman1s/openword/server/internal/httpx"
	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
	"github.com/tahuffman1s/openword/server/internal/streaks"
	"github.com/tahuffman1s/openword/server/internal/validate"
)

type friendStreakJSON struct {
	Current int    `json:"current"`
	Best    int    `json:"best"`
	LastDay string `json:"lastDay"`
}

type friendJSON struct {
	User          model.PublicUser  `json:"user"`
	Since         time.Time         `json:"since"`
	Streak        *model.StreakJSON `json:"streak"`
	FriendStreak  *friendStreakJSON `json:"friendStreak"`
	LastActiveDay *string           `json:"lastActiveDay"`
}

// friendView assembles the friend entry returned by list/accept/create.
func (s *Server) friendView(r *http.Request, me *model.User, f model.Friend) (*friendJSON, error) {
	views, err := s.friendViews(r, me, []model.Friend{f})
	if err != nil {
		return nil, err
	}
	return &views[0], nil
}

func (s *Server) friendViews(r *http.Request, me *model.User, friends []model.Friend) ([]friendJSON, error) {
	ctx := r.Context()
	ids := make([]string, len(friends))
	for i, f := range friends {
		ids[i] = f.User.ID
	}
	snaps, err := s.store.GetStreaks(ctx, ids)
	if err != nil {
		return nil, err
	}
	lastActive, err := s.store.LastActiveDays(ctx, ids)
	if err != nil {
		return nil, err
	}
	today := streaks.Today(s.now(), userLocation(me))
	fs, err := streaks.ForFriends(ctx, s.store, me.ID, ids, today)
	if err != nil {
		return nil, err
	}
	out := make([]friendJSON, 0, len(friends))
	for _, f := range friends {
		v := friendJSON{User: f.User.Public(), Since: f.Since.UTC(), Streak: snaps[f.User.ID].JSON()}
		if st, ok := fs[f.User.ID]; ok && st.Best > 0 {
			v.FriendStreak = &friendStreakJSON{Current: st.Current, Best: st.Best, LastDay: st.LastDay}
		}
		if d, ok := lastActive[f.User.ID]; ok {
			v.LastActiveDay = &d
		}
		out = append(out, v)
	}
	return out, nil
}

// GET /api/friends
func (s *Server) listFriends(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	friends, err := s.store.ListFriends(r.Context(), me.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	views, err := s.friendViews(r, me, friends)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"friends": views})
}

// DELETE /api/friends/{userId}
func (s *Server) removeFriend(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	err := s.store.DeleteFriendship(r.Context(), me.ID, r.PathValue("userId"))
	if storeErr(w, err, "You are not friends with that user.") {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type incomingRequestJSON struct {
	ID        string           `json:"id"`
	From      model.PublicUser `json:"from"`
	Message   string           `json:"message"`
	CreatedAt time.Time        `json:"createdAt"`
}

type outgoingRequestJSON struct {
	ID        string           `json:"id"`
	To        model.PublicUser `json:"to"`
	Message   string           `json:"message"`
	CreatedAt time.Time        `json:"createdAt"`
}

// GET /api/friends/requests
func (s *Server) listFriendRequests(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	me := userFrom(ctx)
	in, out, err := s.store.ListFriendRequests(ctx, me.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	var ids []string
	for _, q := range in {
		ids = append(ids, q.FromUser)
	}
	for _, q := range out {
		ids = append(ids, q.ToUser)
	}
	users, err := s.store.GetUsers(ctx, ids)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	incoming := make([]incomingRequestJSON, 0, len(in))
	for _, q := range in {
		if u, ok := users[q.FromUser]; ok {
			incoming = append(incoming, incomingRequestJSON{ID: q.ID, From: u.Public(), Message: q.Message, CreatedAt: q.CreatedAt.UTC()})
		}
	}
	outgoing := make([]outgoingRequestJSON, 0, len(out))
	for _, q := range out {
		if u, ok := users[q.ToUser]; ok {
			outgoing = append(outgoing, outgoingRequestJSON{ID: q.ID, To: u.Public(), Message: q.Message, CreatedAt: q.CreatedAt.UTC()})
		}
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"incoming": incoming, "outgoing": outgoing})
}

// POST /api/friends/requests {username, message?}
func (s *Server) createFriendRequest(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	me := userFrom(ctx)
	var req struct {
		Username string `json:"username"`
		Message  string `json:"message"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	username, err := validate.Username(req.Username)
	if err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	msg, err := validate.ShortText(req.Message, 200, "message")
	if err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	other, err := s.store.GetUserByUsername(ctx, username)
	if storeErr(w, err, "No such user.") {
		return
	}
	if other.ID == me.ID {
		httpx.BadRequest(w, "You cannot add yourself.")
		return
	}
	if friends, err := s.store.AreFriends(ctx, me.ID, other.ID); err != nil {
		httpx.Internal(w, err)
		return
	} else if friends {
		httpx.Error(w, http.StatusConflict, "already_friends", "You are already friends.")
		return
	}
	// If they already asked us, accept instead of creating a crossing request.
	if existing, err := s.store.FindFriendRequest(ctx, other.ID, me.ID); err == nil {
		s.acceptRequest(w, r, me, existing, http.StatusOK)
		return
	} else if !errors.Is(err, store.ErrNotFound) {
		httpx.Internal(w, err)
		return
	}
	fr := &model.FriendRequest{FromUser: me.ID, ToUser: other.ID, Message: msg}
	if err := s.store.CreateFriendRequest(ctx, fr); err != nil {
		if errors.Is(err, store.ErrDuplicate) {
			httpx.Error(w, http.StatusConflict, "already_requested", "You already sent a request to this user.")
			return
		}
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, map[string]any{"request": outgoingRequestJSON{
		ID: fr.ID, To: other.Public(), Message: fr.Message, CreatedAt: fr.CreatedAt.UTC(),
	}})
}

// acceptRequest turns an incoming request into a friendship and responds
// with the new friend entry.
func (s *Server) acceptRequest(w http.ResponseWriter, r *http.Request, me *model.User, fr *model.FriendRequest, status int) {
	ctx := r.Context()
	now := s.now().UTC()
	if err := s.store.CreateFriendship(ctx, fr.FromUser, fr.ToUser, now); err != nil && !errors.Is(err, store.ErrDuplicate) {
		httpx.Internal(w, err)
		return
	}
	if err := s.store.DeleteFriendRequestsBetween(ctx, fr.FromUser, fr.ToUser); err != nil {
		httpx.Internal(w, err)
		return
	}
	other, err := s.store.GetUser(ctx, fr.FromUser)
	if storeErr(w, err, "No such user.") {
		return
	}
	view, err := s.friendView(r, me, model.Friend{User: other, Since: now})
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, status, map[string]any{"friend": view})
}

// POST /api/friends/requests/{id}/accept
func (s *Server) acceptFriendRequest(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	fr, err := s.store.GetFriendRequest(r.Context(), r.PathValue("id"))
	if storeErr(w, err, "No such request.") {
		return
	}
	if fr.ToUser != me.ID {
		httpx.NotFound(w, "No such request.")
		return
	}
	s.acceptRequest(w, r, me, fr, http.StatusOK)
}

// POST /api/friends/requests/{id}/decline
func (s *Server) declineFriendRequest(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	fr, err := s.store.GetFriendRequest(r.Context(), r.PathValue("id"))
	if storeErr(w, err, "No such request.") {
		return
	}
	if fr.ToUser != me.ID {
		httpx.NotFound(w, "No such request.")
		return
	}
	if err := s.store.DeleteFriendRequest(r.Context(), fr.ID); err != nil && !errors.Is(err, store.ErrNotFound) {
		httpx.Internal(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /api/friends/requests/{id} — cancel my own outgoing request.
func (s *Server) cancelFriendRequest(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	fr, err := s.store.GetFriendRequest(r.Context(), r.PathValue("id"))
	if storeErr(w, err, "No such request.") {
		return
	}
	if fr.FromUser != me.ID {
		httpx.NotFound(w, "No such request.")
		return
	}
	if err := s.store.DeleteFriendRequest(r.Context(), fr.ID); err != nil && !errors.Is(err, store.ErrNotFound) {
		httpx.Internal(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
