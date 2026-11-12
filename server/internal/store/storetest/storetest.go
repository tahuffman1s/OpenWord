// Package storetest is a conformance suite every store.Store implementation
// must pass. memstore runs it always; pgstore runs it when TEST_DATABASE_URL
// is set.
package storetest

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
)

func ptr(s string) *string { return &s }

// Run executes the suite against a fresh store from newStore.
func Run(t *testing.T, newStore func(t *testing.T) store.Store) {
	t.Run("Users", func(t *testing.T) { testUsers(t, newStore(t)) })
	t.Run("Sessions", func(t *testing.T) { testSessions(t, newStore(t)) })
	t.Run("Friends", func(t *testing.T) { testFriends(t, newStore(t)) })
	t.Run("Activity", func(t *testing.T) { testActivity(t, newStore(t)) })
	t.Run("Achievements", func(t *testing.T) { testAchievements(t, newStore(t)) })
	t.Run("PushBackupReminders", func(t *testing.T) { testPushBackupReminders(t, newStore(t)) })
}

func mkUser(t *testing.T, st store.Store, name string) *model.User {
	t.Helper()
	u := &model.User{Username: name, DisplayName: "User " + name, PasswordHash: "h", ReminderDays: 127,
		ReminderOnlyIfUndone: true, FriendReminders: true}
	if err := st.CreateUser(context.Background(), u); err != nil {
		t.Fatalf("create %s: %v", name, err)
	}
	return u
}

func testUsers(t *testing.T, st store.Store) {
	ctx := context.Background()
	a := mkUser(t, st, "alice")
	if a.ID == "" || a.CreatedAt.IsZero() {
		t.Fatal("id/created_at not filled")
	}
	if err := st.CreateUser(ctx, &model.User{Username: "alice", DisplayName: "x", PasswordHash: "h"}); !errors.Is(err, store.ErrUsernameTaken) {
		t.Fatalf("dup username: %v", err)
	}
	a.Email = ptr("a@x.io")
	if err := st.UpdateUser(ctx, a); err != nil {
		t.Fatal(err)
	}
	if err := st.CreateUser(ctx, &model.User{Username: "bob", DisplayName: "x", PasswordHash: "h", Email: ptr("a@x.io")}); !errors.Is(err, store.ErrEmailTaken) {
		t.Fatalf("dup email: %v", err)
	}
	b := mkUser(t, st, "bob")
	b.Email = ptr("a@x.io")
	if err := st.UpdateUser(ctx, b); !errors.Is(err, store.ErrEmailTaken) {
		t.Fatalf("dup email on update: %v", err)
	}
	if got, err := st.GetUserByEmail(ctx, "A@x.io"); err != nil || got.ID != a.ID {
		t.Fatalf("by email: %v %v", got, err)
	}
	if got, err := st.GetUserByUsername(ctx, "ALICE"); err != nil || got.ID != a.ID {
		t.Fatalf("by username: %v %v", got, err)
	}
	if _, err := st.GetUser(ctx, "00000000-0000-4000-8000-000000000000"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing user: %v", err)
	}
	us, err := st.GetUsers(ctx, []string{a.ID, b.ID})
	if err != nil || len(us) != 2 {
		t.Fatalf("get users: %v %v", us, err)
	}
	res, err := st.SearchUsers(ctx, "USER B", a.ID, 10)
	if err != nil || len(res) != 1 || res[0].ID != b.ID {
		t.Fatalf("search by display name: %v %v", res, err)
	}
	res, _ = st.SearchUsers(ctx, "al", a.ID, 10)
	if len(res) != 0 {
		t.Fatal("search must exclude self")
	}
	res, _ = st.SearchUsers(ctx, "%", a.ID, 10)
	if len(res) != 0 {
		t.Fatal("LIKE wildcards must be escaped")
	}
	if err := st.UpdatePassword(ctx, a.ID, "h2"); err != nil {
		t.Fatal(err)
	}
	if got, _ := st.GetUser(ctx, a.ID); got.PasswordHash != "h2" {
		t.Fatal("password not updated")
	}
	now := time.Now().UTC().Truncate(time.Millisecond)
	if err := st.TouchLastSeen(ctx, a.ID, now); err != nil {
		t.Fatal(err)
	}
	if got, _ := st.GetUser(ctx, a.ID); got.LastSeenAt == nil || !got.LastSeenAt.Equal(now) {
		t.Fatalf("last seen: %v", got.LastSeenAt)
	}
	v, err := st.SetAvatar(ctx, a.ID, []byte{1, 2, 3}, "image/jpeg")
	if err != nil || v != 1 {
		t.Fatalf("set avatar: %d %v", v, err)
	}
	data, ct, v, err := st.GetAvatar(ctx, a.ID)
	if err != nil || string(data) != "\x01\x02\x03" || ct != "image/jpeg" || v != 1 {
		t.Fatalf("get avatar: %v %s %d %v", data, ct, v, err)
	}
	if err := st.ClearAvatar(ctx, a.ID); err != nil {
		t.Fatal(err)
	}
	if _, _, _, err := st.GetAvatar(ctx, a.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("cleared avatar: %v", err)
	}
	if err := st.DeleteUser(ctx, a.ID); err != nil {
		t.Fatal(err)
	}
	if err := st.DeleteUser(ctx, a.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("double delete: %v", err)
	}
}

func testSessions(t *testing.T, st store.Store) {
	ctx := context.Background()
	a := mkUser(t, st, "alice")
	now := time.Now().UTC().Truncate(time.Millisecond)
	hash := []byte("0123456789abcdef0123456789abcdef")
	s := &model.Session{TokenHash: hash, UserID: a.ID, CreatedAt: now, ExpiresAt: now.Add(time.Hour), UserAgent: "ua"}
	if err := st.CreateSession(ctx, s); err != nil {
		t.Fatal(err)
	}
	got, err := st.GetSession(ctx, hash)
	if err != nil || got.UserID != a.ID || !got.ExpiresAt.Equal(s.ExpiresAt) {
		t.Fatalf("get session: %+v %v", got, err)
	}
	if err := st.ExtendSession(ctx, hash, now.Add(2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if got, _ := st.GetSession(ctx, hash); !got.ExpiresAt.Equal(now.Add(2 * time.Hour)) {
		t.Fatal("not extended")
	}
	if n, err := st.DeleteExpiredSessions(ctx, now.Add(3*time.Hour)); err != nil || n != 1 {
		t.Fatalf("expire: %d %v", n, err)
	}
	if _, err := st.GetSession(ctx, hash); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("after expiry: %v", err)
	}
	_ = st.CreateSession(ctx, s)
	if err := st.DeleteSession(ctx, hash); err != nil {
		t.Fatal(err)
	}
	if _, err := st.GetSession(ctx, hash); !errors.Is(err, store.ErrNotFound) {
		t.Fatal("not deleted")
	}
}

func testFriends(t *testing.T, st store.Store) {
	ctx := context.Background()
	a, b, c := mkUser(t, st, "alice"), mkUser(t, st, "bob"), mkUser(t, st, "carol")
	now := time.Now().UTC().Truncate(time.Millisecond)

	r := &model.FriendRequest{FromUser: a.ID, ToUser: b.ID, Message: "hi"}
	if err := st.CreateFriendRequest(ctx, r); err != nil || r.ID == "" {
		t.Fatalf("create request: %v", err)
	}
	if err := st.CreateFriendRequest(ctx, &model.FriendRequest{FromUser: a.ID, ToUser: b.ID}); !errors.Is(err, store.ErrDuplicate) {
		t.Fatalf("dup request: %v", err)
	}
	if got, err := st.FindFriendRequest(ctx, a.ID, b.ID); err != nil || got.ID != r.ID {
		t.Fatalf("find: %v %v", got, err)
	}
	if _, err := st.FindFriendRequest(ctx, b.ID, a.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("reverse find: %v", err)
	}
	in, out, err := st.ListFriendRequests(ctx, b.ID)
	if err != nil || len(in) != 1 || len(out) != 0 || in[0].Message != "hi" {
		t.Fatalf("list b: %v %v %v", in, out, err)
	}
	if n, _ := st.CountIncomingRequests(ctx, b.ID); n != 1 {
		t.Fatal("count")
	}
	if err := st.CreateFriendship(ctx, b.ID, a.ID, now); err != nil {
		t.Fatal(err)
	}
	if err := st.CreateFriendship(ctx, a.ID, b.ID, now); !errors.Is(err, store.ErrDuplicate) {
		t.Fatalf("dup friendship: %v", err)
	}
	if err := st.DeleteFriendRequestsBetween(ctx, b.ID, a.ID); err != nil {
		t.Fatal(err)
	}
	if n, _ := st.CountIncomingRequests(ctx, b.ID); n != 0 {
		t.Fatal("request not removed")
	}
	if ok, _ := st.AreFriends(ctx, a.ID, b.ID); !ok {
		t.Fatal("should be friends")
	}
	if ok, _ := st.AreFriends(ctx, a.ID, c.ID); ok {
		t.Fatal("should not be friends")
	}
	_ = st.CreateFriendship(ctx, a.ID, c.ID, now)
	fs, err := st.ListFriends(ctx, a.ID)
	if err != nil || len(fs) != 2 || fs[0].User.ID != b.ID || fs[1].User.ID != c.ID || !fs[0].Since.Equal(now) {
		t.Fatalf("list friends: %+v %v", fs, err)
	}
	ids, _ := st.FriendIDs(ctx, c.ID)
	if len(ids) != 1 || ids[0] != a.ID {
		t.Fatalf("friend ids: %v", ids)
	}
	if err := st.DeleteFriendship(ctx, c.ID, a.ID); err != nil {
		t.Fatal(err)
	}
	if err := st.DeleteFriendship(ctx, c.ID, a.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("double unfriend: %v", err)
	}
	r2 := &model.FriendRequest{FromUser: c.ID, ToUser: a.ID}
	_ = st.CreateFriendRequest(ctx, r2)
	if got, _ := st.GetFriendRequest(ctx, r2.ID); got == nil || got.FromUser != c.ID {
		t.Fatal("get request")
	}
	if err := st.DeleteFriendRequest(ctx, r2.ID); err != nil {
		t.Fatal(err)
	}
	if err := st.DeleteFriendRequest(ctx, r2.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("double delete request: %v", err)
	}
	// Deleting a user removes the friendship.
	if err := st.DeleteUser(ctx, b.ID); err != nil {
		t.Fatal(err)
	}
	if ids, _ := st.FriendIDs(ctx, a.ID); len(ids) != 0 {
		t.Fatalf("friendship should cascade: %v", ids)
	}
}

func testActivity(t *testing.T, st store.Store) {
	ctx := context.Background()
	a, b := mkUser(t, st, "alice"), mkUser(t, st, "bob")
	now := time.Now().UTC().Truncate(time.Millisecond)
	put := func(u *model.User, day, kind string, count int) *model.ActivityDay {
		t.Helper()
		got, err := st.UpsertActivity(ctx, &model.ActivityDay{UserID: u.ID, Day: day, Kind: kind, Count: count, FirstAt: now, LastAt: now})
		if err != nil {
			t.Fatal(err)
		}
		return got
	}
	put(a, "2026-03-01", "learn", 1)
	if got := put(a, "2026-03-01", "learn", 3); got.Count != 3 {
		t.Fatalf("count should rise: %+v", got)
	}
	if got := put(a, "2026-03-01", "learn", 1); got.Count != 3 {
		t.Fatalf("count should not fall: %+v", got)
	}
	put(a, "2026-03-02", "read", 1)
	put(a, "2026-03-03", "learn", 1)
	put(b, "2026-03-03", "learn", 1)
	put(b, "2025-01-01", "learn", 1)

	rows, err := st.ListActivity(ctx, a.ID, "2026-03-01", "2026-03-02")
	if err != nil || len(rows) != 2 || rows[0].Kind != "learn" || rows[1].Day != "2026-03-02" {
		t.Fatalf("list: %+v %v", rows, err)
	}
	ld, err := st.LearnDays(ctx, []string{a.ID, b.ID}, "2026-01-01")
	if err != nil || len(ld[a.ID]) != 2 || len(ld[b.ID]) != 1 || ld[a.ID][0] != "2026-03-01" {
		t.Fatalf("learn days: %v %v", ld, err)
	}
	if ok, _ := st.HasActivity(ctx, a.ID, "2026-03-02", "read"); !ok {
		t.Fatal("has read")
	}
	if ok, _ := st.HasActivity(ctx, a.ID, "2026-03-02", "learn"); ok {
		t.Fatal("no learn on the 2nd")
	}
	last, _ := st.LastActiveDays(ctx, []string{a.ID, b.ID})
	if last[a.ID] != "2026-03-03" || last[b.ID] != "2026-03-03" {
		t.Fatalf("last active: %v", last)
	}

	snap := &model.StreakSnapshot{UserID: a.ID, Current: 2, Best: 5, Freezes: 1, LastDay: "2026-03-03", UpdatedAt: now}
	if err := st.PutStreak(ctx, snap); err != nil {
		t.Fatal(err)
	}
	snap.Current = 3
	if err := st.PutStreak(ctx, snap); err != nil {
		t.Fatal(err)
	}
	if got, err := st.GetStreak(ctx, a.ID); err != nil || got.Current != 3 || got.Best != 5 {
		t.Fatalf("get streak: %+v %v", got, err)
	}
	if _, err := st.GetStreak(ctx, b.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing streak: %v", err)
	}
	if m, _ := st.GetStreaks(ctx, []string{a.ID, b.ID}); len(m) != 1 || m[a.ID].Freezes != 1 {
		t.Fatalf("get streaks: %v", m)
	}
}

func testAchievements(t *testing.T, st store.Store) {
	ctx := context.Background()
	a, b := mkUser(t, st, "alice"), mkUser(t, st, "bob")
	base := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	mk := func(u *model.User, key string, day int) *model.Achievement {
		t.Helper()
		ach := &model.Achievement{UserID: u.ID, Key: key, Kind: "badge", Title: key, EarnedAt: base.AddDate(0, 0, day)}
		created, err := st.CreateAchievement(ctx, ach)
		if err != nil || !created || ach.ID == "" {
			t.Fatalf("create %s: created=%v err=%v", key, created, err)
		}
		return ach
	}
	a1 := mk(a, "a1", 1)
	a2 := mk(a, "a2", 3)
	b1 := mk(b, "b1", 2)
	dup := &model.Achievement{UserID: a.ID, Key: "a1", Kind: "level", Title: "other", EarnedAt: base}
	if created, err := st.CreateAchievement(ctx, dup); err != nil || created || dup.ID != a1.ID || dup.Title != "a1" {
		t.Fatalf("dup: created=%v %+v %v", created, dup, err)
	}
	if got, err := st.GetAchievement(ctx, b1.ID); err != nil || got.Key != "b1" {
		t.Fatalf("get: %+v %v", got, err)
	}
	if l, _ := st.ListAchievements(ctx, a.ID, 1); len(l) != 1 || l[0].ID != a2.ID {
		t.Fatalf("list newest first: %+v", l)
	}
	when := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	if err := st.AddCheer(ctx, a1.ID, b.ID, when); err != nil {
		t.Fatal(err)
	}
	if err := st.AddCheer(ctx, a1.ID, b.ID, when); err != nil {
		t.Fatalf("cheer should be idempotent: %v", err)
	}
	if err := st.AddCheer(ctx, "00000000-0000-4000-8000-000000000000", b.ID, when); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("cheer missing: %v", err)
	}
	if n, _ := st.CountCheers(ctx, a1.ID); n != 1 {
		t.Fatal("count cheers")
	}
	page, err := st.Feed(ctx, []string{a.ID, b.ID}, base.AddDate(0, 0, 10), 2, b.ID)
	if err != nil || len(page.Items) != 2 || page.Items[0].ID != a2.ID || page.Items[1].ID != b1.ID {
		t.Fatalf("feed: %+v %v", page, err)
	}
	page, _ = st.Feed(ctx, []string{a.ID, b.ID}, page.Items[1].EarnedAt, 2, b.ID)
	if len(page.Items) != 1 || page.Items[0].ID != a1.ID || page.Cheers[a1.ID] != 1 || !page.Cheered[a1.ID] {
		t.Fatalf("feed page 2: %+v", page)
	}
	if err := st.RemoveCheer(ctx, a1.ID, b.ID); err != nil {
		t.Fatal(err)
	}
	if n, _ := st.CountCheers(ctx, a1.ID); n != 0 {
		t.Fatal("cheer not removed")
	}
	if p, _ := st.Feed(ctx, nil, base, 10, a.ID); len(p.Items) != 0 {
		t.Fatal("empty ids")
	}
}

func testPushBackupReminders(t *testing.T, st store.Store) {
	ctx := context.Background()
	a, b := mkUser(t, st, "alice"), mkUser(t, st, "bob")
	now := time.Now().UTC().Truncate(time.Millisecond)

	sub := &model.PushSubscription{UserID: a.ID, Endpoint: "https://p/1", P256dh: "p", Auth: "x", UserAgent: "ua"}
	if err := st.UpsertPushSubscription(ctx, sub); err != nil || sub.ID == "" {
		t.Fatalf("sub: %v", err)
	}
	if err := st.RecordPushResult(ctx, sub.ID, false, now); err != nil {
		t.Fatal(err)
	}
	// Same endpoint re-registered by another user moves over and resets failures.
	moved := &model.PushSubscription{UserID: b.ID, Endpoint: "https://p/1", P256dh: "p2", Auth: "x2"}
	if err := st.UpsertPushSubscription(ctx, moved); err != nil || moved.ID != sub.ID || moved.Failures != 0 {
		t.Fatalf("move sub: %+v %v", moved, err)
	}
	if l, _ := st.ListPushSubscriptions(ctx, a.ID); len(l) != 0 {
		t.Fatal("endpoint should have moved")
	}
	if err := st.RecordPushResult(ctx, sub.ID, true, now); err != nil {
		t.Fatal(err)
	}
	l, _ := st.ListPushSubscriptions(ctx, b.ID)
	if len(l) != 1 || l[0].LastUsedAt == nil || l[0].P256dh != "p2" {
		t.Fatalf("list subs: %+v", l)
	}
	if err := st.DeletePushSubscription(ctx, b.ID, "https://p/1"); err != nil {
		t.Fatal(err)
	}
	if l, _ := st.ListPushSubscriptions(ctx, b.ID); len(l) != 0 {
		t.Fatal("not deleted")
	}
	_ = st.UpsertPushSubscription(ctx, sub)
	_ = st.DeletePushSubscriptionByID(ctx, sub.ID)
	if l, _ := st.ListPushSubscriptions(ctx, a.ID); len(l) != 0 {
		t.Fatal("not deleted by id")
	}

	// Backups.
	if _, err := st.GetBackup(ctx, a.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing backup: %v", err)
	}
	bk := &model.Backup{UserID: a.ID, Body: []byte(`{"a":1}`), UpdatedAt: now, SizeBytes: 7}
	if err := st.PutBackup(ctx, bk); err != nil {
		t.Fatal(err)
	}
	bk.Body = []byte(`{"a":2}`)
	if err := st.PutBackup(ctx, bk); err != nil {
		t.Fatal(err)
	}
	// jsonb may re-space the document, so compare semantically.
	got, err := st.GetBackup(ctx, a.ID)
	var doc map[string]any
	if err != nil || json.Unmarshal(got.Body, &doc) != nil || doc["a"] != float64(2) || got.SizeBytes != 7 {
		t.Fatalf("get backup: %+v %v", got, err)
	}
	if err := st.DeleteBackup(ctx, a.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := st.GetBackup(ctx, a.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatal("backup not deleted")
	}

	// Reminder candidates need a subscription.
	a.ReminderTime, a.ReminderTZ = ptr("07:00"), ptr("UTC")
	_ = st.UpdateUser(ctx, a)
	if c, _ := st.ReminderCandidates(ctx); len(c) != 0 {
		t.Fatalf("no subs → no candidates: %v", c)
	}
	_ = st.UpsertPushSubscription(ctx, &model.PushSubscription{UserID: a.ID, Endpoint: "https://p/2", P256dh: "p", Auth: "x"})
	b.FriendReminders = false
	_ = st.UpdateUser(ctx, b)
	_ = st.UpsertPushSubscription(ctx, &model.PushSubscription{UserID: b.ID, Endpoint: "https://p/3", P256dh: "p", Auth: "x"})
	c, err := st.ReminderCandidates(ctx)
	if err != nil || len(c) != 1 || c[0].ID != a.ID {
		t.Fatalf("candidates: %v %v", c, err)
	}
	if ok, err := st.TryLogReminder(ctx, a.ID, "2026-03-01", "daily", now); err != nil || !ok {
		t.Fatalf("first log: %v %v", ok, err)
	}
	if ok, _ := st.TryLogReminder(ctx, a.ID, "2026-03-01", "daily", now); ok {
		t.Fatal("second log should be refused")
	}
	if ok, _ := st.TryLogReminder(ctx, a.ID, "2026-03-01", "friend", now); !ok {
		t.Fatal("other kind is independent")
	}

	// Server keys.
	if v, _ := st.GetOrSetServerKey(ctx, "k", "first"); v != "first" {
		t.Fatal("set")
	}
	if v, _ := st.GetOrSetServerKey(ctx, "k", "second"); v != "first" {
		t.Fatal("must keep first value")
	}
}
