// Package memstore is an in-memory implementation of store.Store. It exists
// so the handler and scheduler tests can run without Postgres. It is not
// meant for production: nothing is persisted and queries are linear scans.
package memstore

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
)

// Store is a mutex-guarded set of maps mirroring the Postgres tables.
type Store struct {
	mu sync.Mutex

	users        map[string]*model.User
	avatars      map[string]avatar
	sessions     map[string]*model.Session // key: hex(token_hash)
	friendships  map[[2]string]time.Time   // key sorted (a<b)
	requests     map[string]*model.FriendRequest
	activity     map[string]*model.ActivityDay // key user|day|kind
	streaks      map[string]*model.StreakSnapshot
	achievements map[string]*model.Achievement
	cheers       map[[2]string]time.Time // [achievement, user]
	pushSubs     map[string]*model.PushSubscription
	backups      map[string]*model.Backup
	reminderLog  map[[3]string]time.Time // [user, day, kind]
	serverKeys   map[string]string
	PingErr      error // set to simulate a dead database
}

type avatar struct {
	data        []byte
	contentType string
}

// New returns an empty store.
func New() *Store {
	return &Store{
		users:        map[string]*model.User{},
		avatars:      map[string]avatar{},
		sessions:     map[string]*model.Session{},
		friendships:  map[[2]string]time.Time{},
		requests:     map[string]*model.FriendRequest{},
		activity:     map[string]*model.ActivityDay{},
		streaks:      map[string]*model.StreakSnapshot{},
		achievements: map[string]*model.Achievement{},
		cheers:       map[[2]string]time.Time{},
		pushSubs:     map[string]*model.PushSubscription{},
		backups:      map[string]*model.Backup{},
		reminderLog:  map[[3]string]time.Time{},
		serverKeys:   map[string]string{},
	}
}

var _ store.Store = (*Store)(nil)

func newID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	// Format as a UUID so handlers that validate the shape are happy.
	h := hex.EncodeToString(b[:])
	return h[0:8] + "-" + h[8:12] + "-4" + h[13:16] + "-" + h[16:20] + "-" + h[20:32]
}

func pair(a, b string) [2]string {
	if a < b {
		return [2]string{a, b}
	}
	return [2]string{b, a}
}

func (s *Store) Ping(context.Context) error { return s.PingErr }

// Users -------------------------------------------------------------------

func (s *Store) CreateUser(_ context.Context, u *model.User) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, x := range s.users {
		if x.Username == u.Username {
			return store.ErrUsernameTaken
		}
		if u.Email != nil && x.Email != nil && *x.Email == *u.Email {
			return store.ErrEmailTaken
		}
	}
	now := time.Now().UTC()
	u.ID = newID()
	u.CreatedAt = now
	u.UpdatedAt = now
	s.users[u.ID] = u.Clone()
	return nil
}

func (s *Store) GetUser(_ context.Context, id string) (*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.users[id]
	if !ok {
		return nil, store.ErrNotFound
	}
	return u.Clone(), nil
}

func (s *Store) GetUserByUsername(_ context.Context, username string) (*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, u := range s.users {
		if u.Username == strings.ToLower(username) {
			return u.Clone(), nil
		}
	}
	return nil, store.ErrNotFound
}

func (s *Store) GetUserByEmail(_ context.Context, email string) (*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, u := range s.users {
		if u.Email != nil && *u.Email == strings.ToLower(email) {
			return u.Clone(), nil
		}
	}
	return nil, store.ErrNotFound
}

func (s *Store) GetUsers(_ context.Context, ids []string) (map[string]*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string]*model.User{}
	for _, id := range ids {
		if u, ok := s.users[id]; ok {
			out[id] = u.Clone()
		}
	}
	return out, nil
}

func (s *Store) UpdateUser(_ context.Context, u *model.User) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	cur, ok := s.users[u.ID]
	if !ok {
		return store.ErrNotFound
	}
	if u.Email != nil {
		for id, x := range s.users {
			if id != u.ID && x.Email != nil && *x.Email == *u.Email {
				return store.ErrEmailTaken
			}
		}
	}
	cur.DisplayName = u.DisplayName
	cur.Bio = u.Bio
	cur.Email = u.Email
	cur.ReminderTime = u.ReminderTime
	cur.ReminderTZ = u.ReminderTZ
	cur.ReminderDays = u.ReminderDays
	cur.ReminderOnlyIfUndone = u.ReminderOnlyIfUndone
	cur.FriendReminders = u.FriendReminders
	cur.UpdatedAt = time.Now().UTC()
	u.UpdatedAt = cur.UpdatedAt
	return nil
}

func (s *Store) UpdatePassword(_ context.Context, id, hash string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.users[id]
	if !ok {
		return store.ErrNotFound
	}
	u.PasswordHash = hash
	u.UpdatedAt = time.Now().UTC()
	return nil
}

func (s *Store) TouchLastSeen(_ context.Context, id string, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if u, ok := s.users[id]; ok {
		u.LastSeenAt = &at
	}
	return nil
}

func (s *Store) SetAvatar(_ context.Context, id string, data []byte, contentType string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.users[id]
	if !ok {
		return 0, store.ErrNotFound
	}
	u.AvatarVersion++
	s.avatars[id] = avatar{data: append([]byte(nil), data...), contentType: contentType}
	return u.AvatarVersion, nil
}

func (s *Store) ClearAvatar(_ context.Context, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.users[id]
	if !ok {
		return store.ErrNotFound
	}
	u.AvatarVersion = 0
	delete(s.avatars, id)
	return nil
}

func (s *Store) GetAvatar(_ context.Context, id string) ([]byte, string, int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.users[id]
	a, ok2 := s.avatars[id]
	if !ok || !ok2 {
		return nil, "", 0, store.ErrNotFound
	}
	return a.data, a.contentType, u.AvatarVersion, nil
}

func (s *Store) DeleteUser(_ context.Context, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.users[id]; !ok {
		return store.ErrNotFound
	}
	delete(s.users, id)
	delete(s.avatars, id)
	delete(s.streaks, id)
	delete(s.backups, id)
	for k, v := range s.sessions {
		if v.UserID == id {
			delete(s.sessions, k)
		}
	}
	for k := range s.friendships {
		if k[0] == id || k[1] == id {
			delete(s.friendships, k)
		}
	}
	for k, v := range s.requests {
		if v.FromUser == id || v.ToUser == id {
			delete(s.requests, k)
		}
	}
	for k, v := range s.activity {
		if v.UserID == id {
			delete(s.activity, k)
		}
	}
	for k, v := range s.achievements {
		if v.UserID == id {
			delete(s.achievements, k)
			for ck := range s.cheers {
				if ck[0] == k {
					delete(s.cheers, ck)
				}
			}
		}
	}
	for ck := range s.cheers {
		if ck[1] == id {
			delete(s.cheers, ck)
		}
	}
	for k, v := range s.pushSubs {
		if v.UserID == id {
			delete(s.pushSubs, k)
		}
	}
	for k := range s.reminderLog {
		if k[0] == id {
			delete(s.reminderLog, k)
		}
	}
	return nil
}

func (s *Store) SearchUsers(_ context.Context, q, excludeID string, limit int) ([]*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	q = strings.ToLower(strings.TrimSpace(q))
	var out []*model.User
	for _, u := range s.users {
		if u.ID == excludeID {
			continue
		}
		if strings.HasPrefix(u.Username, q) || strings.Contains(strings.ToLower(u.DisplayName), q) {
			out = append(out, u.Clone())
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Username < out[j].Username })
	if len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}

// Sessions ----------------------------------------------------------------

func (s *Store) CreateSession(_ context.Context, sess *model.Session) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	c := *sess
	s.sessions[hex.EncodeToString(sess.TokenHash)] = &c
	return nil
}

func (s *Store) GetSession(_ context.Context, tokenHash []byte) (*model.Session, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess, ok := s.sessions[hex.EncodeToString(tokenHash)]
	if !ok {
		return nil, store.ErrNotFound
	}
	c := *sess
	return &c, nil
}

func (s *Store) ExtendSession(_ context.Context, tokenHash []byte, expiresAt time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sess, ok := s.sessions[hex.EncodeToString(tokenHash)]; ok {
		sess.ExpiresAt = expiresAt
	}
	return nil
}

func (s *Store) DeleteSession(_ context.Context, tokenHash []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sessions, hex.EncodeToString(tokenHash))
	return nil
}

func (s *Store) DeleteExpiredSessions(_ context.Context, now time.Time) (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var n int64
	for k, v := range s.sessions {
		if v.ExpiresAt.Before(now) {
			delete(s.sessions, k)
			n++
		}
	}
	return n, nil
}

// Friends -----------------------------------------------------------------

func (s *Store) ListFriends(_ context.Context, userID string) ([]model.Friend, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []model.Friend
	for k, since := range s.friendships {
		var other string
		switch userID {
		case k[0]:
			other = k[1]
		case k[1]:
			other = k[0]
		default:
			continue
		}
		if u, ok := s.users[other]; ok {
			out = append(out, model.Friend{User: u.Clone(), Since: since})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := strings.ToLower(out[i].User.DisplayName), strings.ToLower(out[j].User.DisplayName)
		if a != b {
			return a < b
		}
		return out[i].User.Username < out[j].User.Username
	})
	return out, nil
}

func (s *Store) FriendIDs(_ context.Context, userID string) ([]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []string
	for k := range s.friendships {
		if k[0] == userID {
			out = append(out, k[1])
		} else if k[1] == userID {
			out = append(out, k[0])
		}
	}
	sort.Strings(out)
	return out, nil
}

func (s *Store) AreFriends(_ context.Context, a, b string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.friendships[pair(a, b)]
	return ok, nil
}

func (s *Store) CreateFriendship(_ context.Context, a, b string, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if a == b {
		return store.ErrDuplicate
	}
	k := pair(a, b)
	if _, ok := s.friendships[k]; ok {
		return store.ErrDuplicate
	}
	s.friendships[k] = at
	return nil
}

func (s *Store) DeleteFriendship(_ context.Context, a, b string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	k := pair(a, b)
	if _, ok := s.friendships[k]; !ok {
		return store.ErrNotFound
	}
	delete(s.friendships, k)
	return nil
}

func (s *Store) CreateFriendRequest(_ context.Context, r *model.FriendRequest) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, x := range s.requests {
		if x.FromUser == r.FromUser && x.ToUser == r.ToUser {
			return store.ErrDuplicate
		}
	}
	r.ID = newID()
	r.CreatedAt = time.Now().UTC()
	c := *r
	s.requests[r.ID] = &c
	return nil
}

func (s *Store) GetFriendRequest(_ context.Context, id string) (*model.FriendRequest, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, ok := s.requests[id]
	if !ok {
		return nil, store.ErrNotFound
	}
	c := *r
	return &c, nil
}

func (s *Store) FindFriendRequest(_ context.Context, from, to string) (*model.FriendRequest, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, r := range s.requests {
		if r.FromUser == from && r.ToUser == to {
			c := *r
			return &c, nil
		}
	}
	return nil, store.ErrNotFound
}

func (s *Store) ListFriendRequests(_ context.Context, userID string) (incoming, outgoing []model.FriendRequest, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, r := range s.requests {
		if r.ToUser == userID {
			incoming = append(incoming, *r)
		} else if r.FromUser == userID {
			outgoing = append(outgoing, *r)
		}
	}
	byNewest := func(rs []model.FriendRequest) {
		sort.Slice(rs, func(i, j int) bool { return rs[i].CreatedAt.After(rs[j].CreatedAt) })
	}
	byNewest(incoming)
	byNewest(outgoing)
	return incoming, outgoing, nil
}

func (s *Store) DeleteFriendRequest(_ context.Context, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.requests[id]; !ok {
		return store.ErrNotFound
	}
	delete(s.requests, id)
	return nil
}

func (s *Store) DeleteFriendRequestsBetween(_ context.Context, a, b string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for id, r := range s.requests {
		if (r.FromUser == a && r.ToUser == b) || (r.FromUser == b && r.ToUser == a) {
			delete(s.requests, id)
		}
	}
	return nil
}

func (s *Store) CountIncomingRequests(_ context.Context, userID string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	n := 0
	for _, r := range s.requests {
		if r.ToUser == userID {
			n++
		}
	}
	return n, nil
}

// Activity ----------------------------------------------------------------

func actKey(userID, day, kind string) string { return userID + "|" + day + "|" + kind }

func (s *Store) UpsertActivity(_ context.Context, a *model.ActivityDay) (*model.ActivityDay, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	k := actKey(a.UserID, a.Day, a.Kind)
	cur, ok := s.activity[k]
	if !ok {
		c := *a
		s.activity[k] = &c
		return &c, nil
	}
	if a.Count > cur.Count {
		cur.Count = a.Count
	}
	cur.LastAt = a.LastAt
	c := *cur
	return &c, nil
}

func (s *Store) ListActivity(_ context.Context, userID, fromDay, toDay string) ([]model.ActivityDay, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []model.ActivityDay
	for _, a := range s.activity {
		if a.UserID == userID && a.Day >= fromDay && a.Day <= toDay {
			out = append(out, *a)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Day != out[j].Day {
			return out[i].Day < out[j].Day
		}
		return out[i].Kind < out[j].Kind
	})
	return out, nil
}

func (s *Store) LearnDays(_ context.Context, userIDs []string, fromDay string) (map[string][]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	want := map[string]bool{}
	for _, id := range userIDs {
		want[id] = true
	}
	out := map[string][]string{}
	for _, a := range s.activity {
		if want[a.UserID] && a.Kind == model.KindLearn && a.Day >= fromDay {
			out[a.UserID] = append(out[a.UserID], a.Day)
		}
	}
	for _, days := range out {
		sort.Strings(days)
	}
	return out, nil
}

func (s *Store) HasActivity(_ context.Context, userID, day, kind string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.activity[actKey(userID, day, kind)]
	return ok, nil
}

func (s *Store) LastActiveDays(_ context.Context, userIDs []string) (map[string]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	want := map[string]bool{}
	for _, id := range userIDs {
		want[id] = true
	}
	out := map[string]string{}
	for _, a := range s.activity {
		if want[a.UserID] && a.Day > out[a.UserID] {
			out[a.UserID] = a.Day
		}
	}
	return out, nil
}

// Streak snapshots --------------------------------------------------------

func (s *Store) PutStreak(_ context.Context, st *model.StreakSnapshot) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	c := *st
	s.streaks[st.UserID] = &c
	return nil
}

func (s *Store) GetStreak(_ context.Context, userID string) (*model.StreakSnapshot, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	st, ok := s.streaks[userID]
	if !ok {
		return nil, store.ErrNotFound
	}
	c := *st
	return &c, nil
}

func (s *Store) GetStreaks(_ context.Context, userIDs []string) (map[string]*model.StreakSnapshot, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string]*model.StreakSnapshot{}
	for _, id := range userIDs {
		if st, ok := s.streaks[id]; ok {
			c := *st
			out[id] = &c
		}
	}
	return out, nil
}

// Achievements ------------------------------------------------------------

func (s *Store) CreateAchievement(_ context.Context, a *model.Achievement) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, x := range s.achievements {
		if x.UserID == a.UserID && x.Key == a.Key {
			*a = *x
			return false, nil
		}
	}
	a.ID = newID()
	a.CreatedAt = time.Now().UTC()
	c := *a
	s.achievements[a.ID] = &c
	return true, nil
}

func (s *Store) GetAchievement(_ context.Context, id string) (*model.Achievement, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	a, ok := s.achievements[id]
	if !ok {
		return nil, store.ErrNotFound
	}
	c := *a
	return &c, nil
}

func newestFirst(as []model.Achievement) {
	sort.Slice(as, func(i, j int) bool {
		if !as[i].EarnedAt.Equal(as[j].EarnedAt) {
			return as[i].EarnedAt.After(as[j].EarnedAt)
		}
		return as[i].ID > as[j].ID
	})
}

func (s *Store) ListAchievements(_ context.Context, userID string, limit int) ([]model.Achievement, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []model.Achievement
	for _, a := range s.achievements {
		if a.UserID == userID {
			out = append(out, *a)
		}
	}
	newestFirst(out)
	if len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}

func (s *Store) Feed(_ context.Context, userIDs []string, before time.Time, limit int, viewerID string) (*store.FeedPage, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	want := map[string]bool{}
	for _, id := range userIDs {
		want[id] = true
	}
	var items []model.Achievement
	for _, a := range s.achievements {
		if want[a.UserID] && a.EarnedAt.Before(before) {
			items = append(items, *a)
		}
	}
	newestFirst(items)
	if len(items) > limit {
		items = items[:limit]
	}
	page := &store.FeedPage{Items: items, Cheers: map[string]int{}, Cheered: map[string]bool{}}
	for _, a := range items {
		for k := range s.cheers {
			if k[0] == a.ID {
				page.Cheers[a.ID]++
				if k[1] == viewerID {
					page.Cheered[a.ID] = true
				}
			}
		}
	}
	return page, nil
}

func (s *Store) AddCheer(_ context.Context, achievementID, userID string, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.achievements[achievementID]; !ok {
		return store.ErrNotFound
	}
	k := [2]string{achievementID, userID}
	if _, ok := s.cheers[k]; !ok {
		s.cheers[k] = at
	}
	return nil
}

func (s *Store) RemoveCheer(_ context.Context, achievementID, userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.cheers, [2]string{achievementID, userID})
	return nil
}

func (s *Store) CountCheers(_ context.Context, achievementID string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	n := 0
	for k := range s.cheers {
		if k[0] == achievementID {
			n++
		}
	}
	return n, nil
}

// Push --------------------------------------------------------------------

func (s *Store) UpsertPushSubscription(_ context.Context, sub *model.PushSubscription) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, x := range s.pushSubs {
		if x.Endpoint == sub.Endpoint {
			x.UserID = sub.UserID
			x.P256dh = sub.P256dh
			x.Auth = sub.Auth
			x.UserAgent = sub.UserAgent
			x.Failures = 0
			*sub = *x
			return nil
		}
	}
	sub.ID = newID()
	sub.CreatedAt = time.Now().UTC()
	c := *sub
	s.pushSubs[sub.ID] = &c
	return nil
}

func (s *Store) DeletePushSubscription(_ context.Context, userID, endpoint string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for id, x := range s.pushSubs {
		if x.UserID == userID && x.Endpoint == endpoint {
			delete(s.pushSubs, id)
		}
	}
	return nil
}

func (s *Store) DeletePushSubscriptionByID(_ context.Context, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.pushSubs, id)
	return nil
}

func (s *Store) ListPushSubscriptions(_ context.Context, userID string) ([]model.PushSubscription, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []model.PushSubscription
	for _, x := range s.pushSubs {
		if x.UserID == userID {
			out = append(out, *x)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.Before(out[j].CreatedAt) })
	return out, nil
}

func (s *Store) RecordPushResult(_ context.Context, id string, ok bool, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	x, found := s.pushSubs[id]
	if !found {
		return nil
	}
	if ok {
		x.Failures = 0
		x.LastUsedAt = &at
	} else {
		x.Failures++
	}
	return nil
}

// Backups -----------------------------------------------------------------

func (s *Store) PutBackup(_ context.Context, b *model.Backup) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	c := *b
	c.Body = append(json.RawMessage(nil), b.Body...)
	s.backups[b.UserID] = &c
	return nil
}

func (s *Store) GetBackup(_ context.Context, userID string) (*model.Backup, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, ok := s.backups[userID]
	if !ok {
		return nil, store.ErrNotFound
	}
	c := *b
	return &c, nil
}

func (s *Store) DeleteBackup(_ context.Context, userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.backups, userID)
	return nil
}

// Reminders ---------------------------------------------------------------

func (s *Store) ReminderCandidates(context.Context) ([]*model.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	hasSub := map[string]bool{}
	for _, x := range s.pushSubs {
		hasSub[x.UserID] = true
	}
	var out []*model.User
	for _, u := range s.users {
		if !hasSub[u.ID] {
			continue
		}
		if (u.ReminderTime != nil && u.ReminderTZ != nil) || u.FriendReminders {
			out = append(out, u.Clone())
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, nil
}

func (s *Store) TryLogReminder(_ context.Context, userID, day, kind string, at time.Time) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	k := [3]string{userID, day, kind}
	if _, ok := s.reminderLog[k]; ok {
		return false, nil
	}
	s.reminderLog[k] = at
	return true, nil
}

// Server keys -------------------------------------------------------------

func (s *Store) GetOrSetServerKey(_ context.Context, name, value string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if v, ok := s.serverKeys[name]; ok {
		return v, nil
	}
	s.serverKeys[name] = value
	return value, nil
}
