// Package reminders runs the once-a-minute scheduler that sends daily lesson
// reminders and friend-streak warnings over Web Push.
//
// How it works: every minute the scheduler loads every user who has a push
// subscription and either a daily reminder configured or friend reminders
// enabled. For each, it converts "now" to the user's time zone and checks:
//
//   - Daily: the local weekday is enabled in reminderDays and the local time
//     is within the first few minutes after reminderTime. A reminder_log row
//     (user, localDay, 'daily') is claimed before sending so each local day
//     gets at most one, even if two instances run. If reminderOnlyIfUndone
//     is set, nothing is sent when a 'learn' activity exists for localDay.
//
//   - Friend: at local 19:30 (same window), if the user has not learned
//     today and any friend streak is at risk, one "streak at risk" push is
//     sent naming the first such friend, logged as (user, localDay, 'friend').
package reminders

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/push"
	"github.com/tahuffman1s/openword/server/internal/store"
	"github.com/tahuffman1s/openword/server/internal/streaks"
)

// Notifier is the subset of push.Service the scheduler needs.
type Notifier interface {
	SendToUser(ctx context.Context, userID string, n push.Notification) (int, error)
}

// Scheduler ticks once a minute. Tick is exported so tests can drive it
// with a fixed clock.
type Scheduler struct {
	store store.Store
	push  Notifier
	log   *slog.Logger
}

// Window is how long after the configured minute a reminder is still
// considered due, so a slow tick or a brief outage does not skip a day.
const Window = 5 * time.Minute

// FriendReminderTime is the local time friend-streak warnings go out.
const FriendReminderTime = "19:30"

// New builds a scheduler.
func New(st store.Store, n Notifier, log *slog.Logger) *Scheduler {
	return &Scheduler{store: st, push: n, log: log}
}

// Run blocks until ctx is cancelled, ticking at the top of every minute.
func (s *Scheduler) Run(ctx context.Context) {
	// Align to the next minute boundary so "HH:MM" comparisons are exact.
	first := time.Until(time.Now().Truncate(time.Minute).Add(time.Minute))
	select {
	case <-ctx.Done():
		return
	case <-time.After(first):
	}
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	s.Tick(ctx, time.Now())
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			s.Tick(ctx, now)
		}
	}
}

// Tick evaluates every candidate once for the given instant.
func (s *Scheduler) Tick(ctx context.Context, now time.Time) {
	users, err := s.store.ReminderCandidates(ctx)
	if err != nil {
		s.log.Error("reminders: load candidates", "err", err)
		return
	}
	for _, u := range users {
		if ctx.Err() != nil {
			return
		}
		if err := s.tickUser(ctx, u, now); err != nil {
			s.log.Error("reminders: user tick failed", "user", u.ID, "err", err)
		}
	}
}

// due reports whether the local clock is within Window after hhmm.
func due(local time.Time, hhmm string) bool {
	var h, m int
	if _, err := fmt.Sscanf(hhmm, "%d:%d", &h, &m); err != nil {
		return false
	}
	target := time.Date(local.Year(), local.Month(), local.Day(), h, m, 0, 0, local.Location())
	d := local.Sub(target)
	return d >= 0 && d < Window
}

// weekdayBit maps Go's weekday to the Mon=1…Sun=64 bitmask.
func weekdayBit(d time.Weekday) int {
	return 1 << ((int(d) + 6) % 7)
}

func (s *Scheduler) tickUser(ctx context.Context, u *model.User, now time.Time) error {
	loc := time.UTC
	if u.ReminderTZ != nil {
		if l, err := time.LoadLocation(*u.ReminderTZ); err == nil {
			loc = l
		}
	}
	local := now.In(loc)
	today := local.Format(streaks.DayLayout)

	if u.ReminderTime != nil && u.ReminderTZ != nil &&
		u.ReminderDays&weekdayBit(local.Weekday()) != 0 && due(local, *u.ReminderTime) {
		if err := s.daily(ctx, u, today, now); err != nil {
			return err
		}
	}
	if u.FriendReminders && due(local, FriendReminderTime) {
		if err := s.friend(ctx, u, today, now); err != nil {
			return err
		}
	}
	return nil
}

func (s *Scheduler) daily(ctx context.Context, u *model.User, today string, now time.Time) error {
	if u.ReminderOnlyIfUndone {
		done, err := s.store.HasActivity(ctx, u.ID, today, model.KindLearn)
		if err != nil {
			return err
		}
		if done {
			return nil
		}
	}
	claimed, err := s.store.TryLogReminder(ctx, u.ID, today, model.ReminderDaily, now)
	if err != nil || !claimed {
		return err
	}
	sent, err := s.push.SendToUser(ctx, u.ID, push.Notification{
		Title: "OpenWord",
		Body:  "Today's lesson is waiting — keep your streak going.",
		URL:   "/learn",
		Tag:   "daily",
	})
	s.log.Info("daily reminder", "user", u.ID, "day", today, "sent", sent)
	return err
}

func (s *Scheduler) friend(ctx context.Context, u *model.User, today string, now time.Time) error {
	done, err := s.store.HasActivity(ctx, u.ID, today, model.KindLearn)
	if err != nil || done {
		return err
	}
	friendIDs, err := s.store.FriendIDs(ctx, u.ID)
	if err != nil || len(friendIDs) == 0 {
		return err
	}
	fs, err := streaks.ForFriends(ctx, s.store, u.ID, friendIDs, today)
	if err != nil {
		return err
	}
	var atRisk []string
	for _, fid := range friendIDs { // deterministic order
		if fs[fid].AtRisk {
			atRisk = append(atRisk, fid)
		}
	}
	if len(atRisk) == 0 {
		return nil
	}
	claimed, err := s.store.TryLogReminder(ctx, u.ID, today, model.ReminderFriend, now)
	if err != nil || !claimed {
		return err
	}
	friend, err := s.store.GetUser(ctx, atRisk[0])
	if err != nil {
		return err
	}
	body := fmt.Sprintf("Your streak with %s is at risk", friend.DisplayName)
	if len(atRisk) > 1 {
		body = fmt.Sprintf("Your streak with %s and %d more is at risk", friend.DisplayName, len(atRisk)-1)
	}
	sent, err := s.push.SendToUser(ctx, u.ID, push.Notification{
		Title: "OpenWord",
		Body:  body,
		URL:   "/learn",
		Tag:   "friend",
	})
	s.log.Info("friend reminder", "user", u.ID, "day", today, "sent", sent)
	return err
}
