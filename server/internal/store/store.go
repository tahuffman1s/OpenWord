// Package store defines the persistence interface used by the HTTP handlers
// and background workers. Two implementations exist: pgstore (Postgres, used
// in production) and memstore (in-memory, used by the handler tests so they
// run without a database).
package store

import (
	"context"
	"errors"
	"time"

	"github.com/tahuffman1s/openword/server/internal/model"
)

// Sentinel errors. Implementations must return exactly these (possibly
// wrapped) so handlers can map them to HTTP status codes.
var (
	ErrNotFound      = errors.New("not found")
	ErrUsernameTaken = errors.New("username taken")
	ErrEmailTaken    = errors.New("email taken")
	ErrDuplicate     = errors.New("duplicate")
)

// FeedPage is one page of the achievements feed.
type FeedPage struct {
	Items   []model.Achievement
	Cheers  map[string]int  // achievement id → cheer count
	Cheered map[string]bool // achievement id → viewer has cheered
}

// Store is the complete persistence contract. It is deliberately one
// interface: the application is small and a single fake is easier to keep
// honest than a dozen.
type Store interface {
	Ping(ctx context.Context) error

	// Users ---------------------------------------------------------------

	// CreateUser inserts u, filling ID, CreatedAt and UpdatedAt. Returns
	// ErrUsernameTaken or ErrEmailTaken on conflict.
	CreateUser(ctx context.Context, u *model.User) error
	GetUser(ctx context.Context, id string) (*model.User, error)
	GetUserByUsername(ctx context.Context, username string) (*model.User, error)
	GetUserByEmail(ctx context.Context, email string) (*model.User, error)
	GetUsers(ctx context.Context, ids []string) (map[string]*model.User, error)
	// UpdateUser writes the profile and settings columns of u (not the
	// password, avatar or last-seen fields). Returns ErrEmailTaken.
	UpdateUser(ctx context.Context, u *model.User) error
	UpdatePassword(ctx context.Context, id, hash string) error
	TouchLastSeen(ctx context.Context, id string, at time.Time) error
	// SetAvatar stores the image and bumps avatar_version, returning it.
	SetAvatar(ctx context.Context, id string, data []byte, contentType string) (int, error)
	ClearAvatar(ctx context.Context, id string) error
	// GetAvatar returns the bytes, content type and version; ErrNotFound when
	// the user does not exist or has no avatar.
	GetAvatar(ctx context.Context, id string) ([]byte, string, int, error)
	// DeleteUser removes the user and everything that references them.
	DeleteUser(ctx context.Context, id string) error
	// SearchUsers matches q against username (prefix) and display name
	// (substring), case-insensitively, excluding excludeID.
	SearchUsers(ctx context.Context, q, excludeID string, limit int) ([]*model.User, error)

	// Sessions ------------------------------------------------------------

	CreateSession(ctx context.Context, s *model.Session) error
	GetSession(ctx context.Context, tokenHash []byte) (*model.Session, error)
	ExtendSession(ctx context.Context, tokenHash []byte, expiresAt time.Time) error
	DeleteSession(ctx context.Context, tokenHash []byte) error
	DeleteExpiredSessions(ctx context.Context, now time.Time) (int64, error)

	// Friends -------------------------------------------------------------

	ListFriends(ctx context.Context, userID string) ([]model.Friend, error)
	FriendIDs(ctx context.Context, userID string) ([]string, error)
	AreFriends(ctx context.Context, a, b string) (bool, error)
	CreateFriendship(ctx context.Context, a, b string, at time.Time) error
	DeleteFriendship(ctx context.Context, a, b string) error

	// CreateFriendRequest inserts r, filling ID and CreatedAt. Returns
	// ErrDuplicate if one from→to already exists.
	CreateFriendRequest(ctx context.Context, r *model.FriendRequest) error
	GetFriendRequest(ctx context.Context, id string) (*model.FriendRequest, error)
	FindFriendRequest(ctx context.Context, from, to string) (*model.FriendRequest, error)
	ListFriendRequests(ctx context.Context, userID string) (incoming, outgoing []model.FriendRequest, err error)
	DeleteFriendRequest(ctx context.Context, id string) error
	// DeleteFriendRequestsBetween removes requests in either direction.
	DeleteFriendRequestsBetween(ctx context.Context, a, b string) error
	CountIncomingRequests(ctx context.Context, userID string) (int, error)

	// Activity ------------------------------------------------------------

	// UpsertActivity sets count to max(existing, count) and updates last_at.
	UpsertActivity(ctx context.Context, a *model.ActivityDay) (*model.ActivityDay, error)
	ListActivity(ctx context.Context, userID, fromDay, toDay string) ([]model.ActivityDay, error)
	// LearnDays returns, for each user, the sorted list of days >= fromDay
	// on which they have a 'learn' activity.
	LearnDays(ctx context.Context, userIDs []string, fromDay string) (map[string][]string, error)
	HasActivity(ctx context.Context, userID, day, kind string) (bool, error)
	// LastActiveDays returns the most recent activity day of any kind per user.
	LastActiveDays(ctx context.Context, userIDs []string) (map[string]string, error)

	// Streak snapshots ----------------------------------------------------

	PutStreak(ctx context.Context, s *model.StreakSnapshot) error
	GetStreak(ctx context.Context, userID string) (*model.StreakSnapshot, error)
	GetStreaks(ctx context.Context, userIDs []string) (map[string]*model.StreakSnapshot, error)

	// Achievements --------------------------------------------------------

	// CreateAchievement inserts a (filling ID/CreatedAt). If (user, key)
	// already exists, a is overwritten with the existing row and created is
	// false.
	CreateAchievement(ctx context.Context, a *model.Achievement) (created bool, err error)
	GetAchievement(ctx context.Context, id string) (*model.Achievement, error)
	ListAchievements(ctx context.Context, userID string, limit int) ([]model.Achievement, error)
	// Feed returns up to limit achievements of userIDs earned strictly before
	// `before`, newest first, with cheer data relative to viewerID.
	Feed(ctx context.Context, userIDs []string, before time.Time, limit int, viewerID string) (*FeedPage, error)
	AddCheer(ctx context.Context, achievementID, userID string, at time.Time) error
	RemoveCheer(ctx context.Context, achievementID, userID string) error
	CountCheers(ctx context.Context, achievementID string) (int, error)

	// Push ----------------------------------------------------------------

	// UpsertPushSubscription inserts or re-assigns the endpoint to s.UserID.
	UpsertPushSubscription(ctx context.Context, s *model.PushSubscription) error
	DeletePushSubscription(ctx context.Context, userID, endpoint string) error
	DeletePushSubscriptionByID(ctx context.Context, id string) error
	ListPushSubscriptions(ctx context.Context, userID string) ([]model.PushSubscription, error)
	// RecordPushResult resets failures and sets last_used_at on success, or
	// increments failures otherwise.
	RecordPushResult(ctx context.Context, id string, ok bool, at time.Time) error

	// Backups -------------------------------------------------------------

	PutBackup(ctx context.Context, b *model.Backup) error
	GetBackup(ctx context.Context, userID string) (*model.Backup, error)
	DeleteBackup(ctx context.Context, userID string) error

	// Reminders -----------------------------------------------------------

	// ReminderCandidates returns users who have at least one push
	// subscription and either a daily reminder configured or friend
	// reminders enabled.
	ReminderCandidates(ctx context.Context) ([]*model.User, error)
	// TryLogReminder records that a reminder of kind was sent for day and
	// returns true, or returns false if one was already logged.
	TryLogReminder(ctx context.Context, userID, day, kind string, at time.Time) (bool, error)

	// Server keys ---------------------------------------------------------

	// GetOrSetServerKey returns the stored value for name, storing value
	// first if none exists. Safe under concurrent callers.
	GetOrSetServerKey(ctx context.Context, name, value string) (string, error)
}
