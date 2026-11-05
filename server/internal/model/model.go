// Package model holds the domain types shared by the store implementations,
// the HTTP handlers and the background workers. These are internal
// representations; the JSON shapes exposed by the API live in json.go.
package model

import (
	"encoding/json"
	"time"
)

// Activity kinds the client may record. The strings are part of the API
// contract and of the activity_days CHECK constraint.
const (
	KindLearn  = "learn"
	KindRead   = "read"
	KindPlan   = "plan"
	KindQuiz   = "quiz"
	KindListen = "listen"
)

// ActivityKinds lists every accepted activity kind, in display order.
var ActivityKinds = []string{KindLearn, KindRead, KindPlan, KindQuiz, KindListen}

// AchievementKinds lists every accepted achievement kind.
var AchievementKinds = []string{"badge", "level", "streak", "plan", "quiz", "memory", "friend"}

// User is a full account row minus the avatar bytes (which are fetched on
// demand because they can be ~30 KB each and are rarely needed).
type User struct {
	ID                   string     `db:"id"`
	Username             string     `db:"username"`
	DisplayName          string     `db:"display_name"`
	Bio                  string     `db:"bio"`
	Email                *string    `db:"email"`
	PasswordHash         string     `db:"password_hash"`
	AvatarVersion        int        `db:"avatar_version"`
	CreatedAt            time.Time  `db:"created_at"`
	UpdatedAt            time.Time  `db:"updated_at"`
	ReminderTime         *string    `db:"reminder_time"` // "HH:MM" local time, nil = off
	ReminderTZ           *string    `db:"reminder_tz"`   // IANA zone name
	ReminderDays         int        `db:"reminder_days"` // bitmask, Mon=1 … Sun=64
	ReminderOnlyIfUndone bool       `db:"reminder_only_if_undone"`
	FriendReminders      bool       `db:"friend_reminders"`
	LastSeenAt           *time.Time `db:"last_seen_at"`
}

// Clone returns a shallow copy with the pointer fields duplicated, so a
// caller may mutate it without affecting cached state.
func (u *User) Clone() *User {
	c := *u
	if u.Email != nil {
		e := *u.Email
		c.Email = &e
	}
	if u.ReminderTime != nil {
		t := *u.ReminderTime
		c.ReminderTime = &t
	}
	if u.ReminderTZ != nil {
		z := *u.ReminderTZ
		c.ReminderTZ = &z
	}
	if u.LastSeenAt != nil {
		s := *u.LastSeenAt
		c.LastSeenAt = &s
	}
	return &c
}

// Session is a login session. Only the SHA-256 of the bearer token is kept.
type Session struct {
	TokenHash []byte    `db:"token_hash"`
	UserID    string    `db:"user_id"`
	CreatedAt time.Time `db:"created_at"`
	ExpiresAt time.Time `db:"expires_at"`
	UserAgent string    `db:"user_agent"`
}

// Friend is a friendship as seen from one side.
type Friend struct {
	User  *User
	Since time.Time
}

// FriendRequest is a pending invitation from one user to another.
type FriendRequest struct {
	ID        string    `db:"id"`
	FromUser  string    `db:"from_user"`
	ToUser    string    `db:"to_user"`
	Message   string    `db:"message"`
	CreatedAt time.Time `db:"created_at"`
}

// ActivityDay records that a user did `Kind` on local calendar day `Day`.
type ActivityDay struct {
	UserID  string    `db:"user_id"`
	Day     string    `db:"day"` // YYYY-MM-DD in the client's local calendar
	Kind    string    `db:"kind"`
	Count   int       `db:"count"`
	FirstAt time.Time `db:"first_at"`
	LastAt  time.Time `db:"last_at"`
}

// StreakSnapshot is the client's own streak model, mirrored so friends can
// see it. The server never derives it.
type StreakSnapshot struct {
	UserID    string    `db:"user_id"`
	Current   int       `db:"current"`
	Best      int       `db:"best"`
	Freezes   int       `db:"freezes"`
	LastDay   string    `db:"last_day"`
	UpdatedAt time.Time `db:"updated_at"`
}

// Achievement is one entry in the social feed.
type Achievement struct {
	ID        string    `db:"id"`
	UserID    string    `db:"user_id"`
	Key       string    `db:"key"`
	Kind      string    `db:"kind"`
	Title     string    `db:"title"`
	Detail    string    `db:"detail"`
	EarnedAt  time.Time `db:"earned_at"`
	CreatedAt time.Time `db:"created_at"`
}

// PushSubscription is a Web Push endpoint registered by one browser.
type PushSubscription struct {
	ID         string     `db:"id"`
	UserID     string     `db:"user_id"`
	Endpoint   string     `db:"endpoint"`
	P256dh     string     `db:"p256dh"`
	Auth       string     `db:"auth"`
	UserAgent  string     `db:"user_agent"`
	CreatedAt  time.Time  `db:"created_at"`
	LastUsedAt *time.Time `db:"last_used_at"`
	Failures   int        `db:"failures"`
}

// Backup is the opaque JSON blob the client stores for restore on a new
// device.
type Backup struct {
	UserID    string          `db:"user_id"`
	Body      json.RawMessage `db:"body"`
	UpdatedAt time.Time       `db:"updated_at"`
	SizeBytes int             `db:"size_bytes"`
}

// Reminder log kinds.
const (
	ReminderDaily  = "daily"
	ReminderFriend = "friend"
)
