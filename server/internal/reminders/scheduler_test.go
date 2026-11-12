package reminders

import (
	"context"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/push"
	"github.com/tahuffman1s/openword/server/internal/store/memstore"
)

type recorder struct{ sent []push.Notification }

func (r *recorder) SendToUser(_ context.Context, _ string, n push.Notification) (int, error) {
	r.sent = append(r.sent, n)
	return 1, nil
}

func ptr(s string) *string { return &s }

func mkUser(t *testing.T, st *memstore.Store, name string) *model.User {
	t.Helper()
	u := &model.User{Username: name, DisplayName: strings.ToUpper(name), PasswordHash: "x",
		ReminderDays: 127, ReminderOnlyIfUndone: true, FriendReminders: true}
	if err := st.CreateUser(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	if err := st.UpsertPushSubscription(context.Background(), &model.PushSubscription{UserID: u.ID, Endpoint: "ep-" + name, P256dh: "p", Auth: "a"}); err != nil {
		t.Fatal(err)
	}
	return u
}

func learn(t *testing.T, st *memstore.Store, uid, day string) {
	t.Helper()
	now := time.Now()
	if _, err := st.UpsertActivity(context.Background(), &model.ActivityDay{UserID: uid, Day: day, Kind: "learn", Count: 1, FirstAt: now, LastAt: now}); err != nil {
		t.Fatal(err)
	}
}

func TestDailyReminder(t *testing.T) {
	ctx := context.Background()
	st := memstore.New()
	rec := &recorder{}
	s := New(st, rec, slog.Default())

	u := mkUser(t, st, "alice")
	u.ReminderTime = ptr("07:30")
	u.ReminderTZ = ptr("Europe/Berlin")
	if err := st.UpdateUser(ctx, u); err != nil {
		t.Fatal(err)
	}

	// 06:29 UTC is 07:29 Berlin (CET, March 10): not yet.
	s.Tick(ctx, time.Date(2026, 3, 10, 6, 29, 0, 0, time.UTC))
	if len(rec.sent) != 0 {
		t.Fatal("sent too early")
	}
	// 07:30 Berlin: due.
	s.Tick(ctx, time.Date(2026, 3, 10, 6, 30, 0, 0, time.UTC))
	if len(rec.sent) != 1 || rec.sent[0].Tag != "daily" || rec.sent[0].URL != "/learn" {
		t.Fatalf("expected one daily reminder, got %+v", rec.sent)
	}
	// A second tick in the window must not resend.
	s.Tick(ctx, time.Date(2026, 3, 10, 6, 32, 0, 0, time.UTC))
	if len(rec.sent) != 1 {
		t.Fatal("duplicate reminder")
	}
	// Next day, lesson already done: nothing.
	learn(t, st, u.ID, "2026-03-11")
	s.Tick(ctx, time.Date(2026, 3, 11, 6, 30, 0, 0, time.UTC))
	if len(rec.sent) != 1 {
		t.Fatal("reminded although lesson done")
	}
	// Day after, done but onlyIfUndone off: reminded.
	u.ReminderOnlyIfUndone = false
	_ = st.UpdateUser(ctx, u)
	learn(t, st, u.ID, "2026-03-12")
	s.Tick(ctx, time.Date(2026, 3, 12, 6, 30, 0, 0, time.UTC))
	if len(rec.sent) != 2 {
		t.Fatal("expected reminder when onlyIfUndone is off")
	}
	// Weekday mask: 2026-03-13 is a Friday (bit 16). Disable it.
	u.ReminderDays = 127 &^ 16
	_ = st.UpdateUser(ctx, u)
	s.Tick(ctx, time.Date(2026, 3, 13, 6, 30, 0, 0, time.UTC))
	if len(rec.sent) != 2 {
		t.Fatal("reminded on a disabled weekday")
	}
}

func TestFriendReminder(t *testing.T) {
	ctx := context.Background()
	st := memstore.New()
	rec := &recorder{}
	s := New(st, rec, slog.Default())

	a := mkUser(t, st, "alice")
	b := mkUser(t, st, "bob")
	a.ReminderTZ = ptr("UTC")
	_ = st.UpdateUser(ctx, a)
	b.FriendReminders = false
	_ = st.UpdateUser(ctx, b)
	if err := st.CreateFriendship(ctx, a.ID, b.ID, time.Now()); err != nil {
		t.Fatal(err)
	}
	// Both learned yesterday; only bob learned today → alice's streak is at risk.
	learn(t, st, a.ID, "2026-03-09")
	learn(t, st, b.ID, "2026-03-09")
	learn(t, st, b.ID, "2026-03-10")

	s.Tick(ctx, time.Date(2026, 3, 10, 19, 0, 0, 0, time.UTC))
	if len(rec.sent) != 0 {
		t.Fatal("too early")
	}
	s.Tick(ctx, time.Date(2026, 3, 10, 19, 31, 0, 0, time.UTC))
	if len(rec.sent) != 1 || rec.sent[0].Tag != "friend" || !strings.Contains(rec.sent[0].Body, "BOB") {
		t.Fatalf("expected friend reminder for alice, got %+v", rec.sent)
	}
	s.Tick(ctx, time.Date(2026, 3, 10, 19, 33, 0, 0, time.UTC))
	if len(rec.sent) != 1 {
		t.Fatal("duplicate friend reminder")
	}
}

func TestWeekdayBit(t *testing.T) {
	if weekdayBit(time.Monday) != 1 || weekdayBit(time.Sunday) != 64 || weekdayBit(time.Wednesday) != 4 {
		t.Fatal("bitmask mapping wrong")
	}
}

func TestDue(t *testing.T) {
	loc := time.UTC
	at := func(h, m int) time.Time { return time.Date(2026, 1, 1, h, m, 0, 0, loc) }
	if !due(at(7, 30), "07:30") || !due(at(7, 34), "07:30") {
		t.Error("should be due within window")
	}
	if due(at(7, 29), "07:30") || due(at(7, 35), "07:30") || due(at(7, 30), "bad") {
		t.Error("should not be due")
	}
}
