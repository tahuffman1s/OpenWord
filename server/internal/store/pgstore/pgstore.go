// Package pgstore implements store.Store on Postgres via pgx.
package pgstore

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
)

// Store wraps a connection pool.
type Store struct {
	pool *pgxpool.Pool
}

// New returns a Store backed by pool.
func New(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

var _ store.Store = (*Store)(nil)

// userCols lists the users columns in the order model.User expects. The
// avatar bytes are deliberately excluded.
const userCols = `id, username, display_name, bio, email, password_hash, avatar_version,
	created_at, updated_at, reminder_time, reminder_tz, reminder_days,
	reminder_only_if_undone, friend_reminders, last_seen_at`

// isUnique reports whether err is a unique violation on the named
// constraint (or any, if name is empty).
func isUnique(err error, name string) bool {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "23505" {
		return false
	}
	return name == "" || pgErr.ConstraintName == name
}

func mapUserErr(err error) error {
	switch {
	case err == nil:
		return nil
	case isUnique(err, "users_username_key"):
		return store.ErrUsernameTaken
	case isUnique(err, "users_email_key"):
		return store.ErrEmailTaken
	default:
		return err
	}
}

func notFound(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return store.ErrNotFound
	}
	return err
}

func (s *Store) Ping(ctx context.Context) error { return s.pool.Ping(ctx) }

// Users -------------------------------------------------------------------

func (s *Store) CreateUser(ctx context.Context, u *model.User) error {
	err := s.pool.QueryRow(ctx, `INSERT INTO users
		(username, display_name, bio, email, password_hash, reminder_time, reminder_tz,
		 reminder_days, reminder_only_if_undone, friend_reminders)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		RETURNING id, created_at, updated_at`,
		u.Username, u.DisplayName, u.Bio, u.Email, u.PasswordHash, u.ReminderTime, u.ReminderTZ,
		u.ReminderDays, u.ReminderOnlyIfUndone, u.FriendReminders,
	).Scan(&u.ID, &u.CreatedAt, &u.UpdatedAt)
	return mapUserErr(err)
}

func (s *Store) getUserWhere(ctx context.Context, where string, args ...any) (*model.User, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+userCols+" FROM users WHERE "+where, args...)
	if err != nil {
		return nil, err
	}
	u, err := pgx.CollectExactlyOneRow(rows, pgx.RowToAddrOfStructByName[model.User])
	return u, notFound(err)
}

func (s *Store) GetUser(ctx context.Context, id string) (*model.User, error) {
	return s.getUserWhere(ctx, "id = $1", id)
}

func (s *Store) GetUserByUsername(ctx context.Context, username string) (*model.User, error) {
	return s.getUserWhere(ctx, "username = $1", strings.ToLower(username))
}

func (s *Store) GetUserByEmail(ctx context.Context, email string) (*model.User, error) {
	return s.getUserWhere(ctx, "email = $1", strings.ToLower(email))
}

func (s *Store) GetUsers(ctx context.Context, ids []string) (map[string]*model.User, error) {
	out := map[string]*model.User{}
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, "SELECT "+userCols+" FROM users WHERE id = ANY($1)", ids)
	if err != nil {
		return nil, err
	}
	us, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[model.User])
	if err != nil {
		return nil, err
	}
	for _, u := range us {
		out[u.ID] = u
	}
	return out, nil
}

func (s *Store) UpdateUser(ctx context.Context, u *model.User) error {
	err := s.pool.QueryRow(ctx, `UPDATE users SET
		display_name=$2, bio=$3, email=$4, reminder_time=$5, reminder_tz=$6, reminder_days=$7,
		reminder_only_if_undone=$8, friend_reminders=$9, updated_at=now()
		WHERE id=$1 RETURNING updated_at`,
		u.ID, u.DisplayName, u.Bio, u.Email, u.ReminderTime, u.ReminderTZ, u.ReminderDays,
		u.ReminderOnlyIfUndone, u.FriendReminders).Scan(&u.UpdatedAt)
	return mapUserErr(notFound(err))
}

func (s *Store) UpdatePassword(ctx context.Context, id, hash string) error {
	tag, err := s.pool.Exec(ctx, "UPDATE users SET password_hash=$2, updated_at=now() WHERE id=$1", id, hash)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return store.ErrNotFound
	}
	return nil
}

func (s *Store) TouchLastSeen(ctx context.Context, id string, at time.Time) error {
	_, err := s.pool.Exec(ctx, "UPDATE users SET last_seen_at=$2 WHERE id=$1", id, at)
	return err
}

func (s *Store) SetAvatar(ctx context.Context, id string, data []byte, contentType string) (int, error) {
	var v int
	err := s.pool.QueryRow(ctx, `UPDATE users SET avatar=$2, avatar_type=$3,
		avatar_version=avatar_version+1, updated_at=now() WHERE id=$1 RETURNING avatar_version`,
		id, data, contentType).Scan(&v)
	return v, notFound(err)
}

func (s *Store) ClearAvatar(ctx context.Context, id string) error {
	tag, err := s.pool.Exec(ctx, `UPDATE users SET avatar=NULL, avatar_type=NULL,
		avatar_version=0, updated_at=now() WHERE id=$1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return store.ErrNotFound
	}
	return nil
}

func (s *Store) GetAvatar(ctx context.Context, id string) ([]byte, string, int, error) {
	var (
		data  []byte
		ctype *string
		v     int
	)
	err := s.pool.QueryRow(ctx, "SELECT avatar, avatar_type, avatar_version FROM users WHERE id=$1", id).
		Scan(&data, &ctype, &v)
	if err != nil {
		return nil, "", 0, notFound(err)
	}
	if data == nil || ctype == nil {
		return nil, "", 0, store.ErrNotFound
	}
	return data, *ctype, v, nil
}

func (s *Store) DeleteUser(ctx context.Context, id string) error {
	// Everything else cascades via foreign keys.
	tag, err := s.pool.Exec(ctx, "DELETE FROM users WHERE id=$1", id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return store.ErrNotFound
	}
	return nil
}

// escapeLike makes q safe to embed in a LIKE pattern.
func escapeLike(q string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return r.Replace(q)
}

func (s *Store) SearchUsers(ctx context.Context, q, excludeID string, limit int) ([]*model.User, error) {
	q = strings.ToLower(strings.TrimSpace(q))
	esc := escapeLike(q)
	rows, err := s.pool.Query(ctx, "SELECT "+userCols+` FROM users
		WHERE id <> $1 AND (username LIKE $2 OR lower(display_name) LIKE $3)
		ORDER BY (username LIKE $2) DESC, username
		LIMIT $4`, excludeID, esc+"%", "%"+esc+"%", limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[model.User])
}

// Sessions ----------------------------------------------------------------

func (s *Store) CreateSession(ctx context.Context, sess *model.Session) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO sessions (token_hash, user_id, created_at, expires_at, user_agent)
		VALUES ($1,$2,$3,$4,$5)`, sess.TokenHash, sess.UserID, sess.CreatedAt, sess.ExpiresAt, sess.UserAgent)
	return err
}

func (s *Store) GetSession(ctx context.Context, tokenHash []byte) (*model.Session, error) {
	rows, err := s.pool.Query(ctx, `SELECT token_hash, user_id, created_at, expires_at, user_agent
		FROM sessions WHERE token_hash=$1`, tokenHash)
	if err != nil {
		return nil, err
	}
	sess, err := pgx.CollectExactlyOneRow(rows, pgx.RowToAddrOfStructByName[model.Session])
	return sess, notFound(err)
}

func (s *Store) ExtendSession(ctx context.Context, tokenHash []byte, expiresAt time.Time) error {
	_, err := s.pool.Exec(ctx, "UPDATE sessions SET expires_at=$2 WHERE token_hash=$1", tokenHash, expiresAt)
	return err
}

func (s *Store) DeleteSession(ctx context.Context, tokenHash []byte) error {
	_, err := s.pool.Exec(ctx, "DELETE FROM sessions WHERE token_hash=$1", tokenHash)
	return err
}

func (s *Store) DeleteExpiredSessions(ctx context.Context, now time.Time) (int64, error) {
	tag, err := s.pool.Exec(ctx, "DELETE FROM sessions WHERE expires_at < $1", now)
	return tag.RowsAffected(), err
}

// Friends -----------------------------------------------------------------

func orderPair(a, b string) (string, string) {
	if a < b {
		return a, b
	}
	return b, a
}

func (s *Store) ListFriends(ctx context.Context, userID string) ([]model.Friend, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+prefixCols("u", userCols)+`, f.created_at AS since
		FROM friendships f
		JOIN users u ON u.id = CASE WHEN f.user_a = $1 THEN f.user_b ELSE f.user_a END
		WHERE f.user_a = $1 OR f.user_b = $1
		ORDER BY lower(u.display_name), u.username`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []model.Friend
	for rows.Next() {
		var u model.User
		var since time.Time
		if err := rows.Scan(&u.ID, &u.Username, &u.DisplayName, &u.Bio, &u.Email, &u.PasswordHash,
			&u.AvatarVersion, &u.CreatedAt, &u.UpdatedAt, &u.ReminderTime, &u.ReminderTZ,
			&u.ReminderDays, &u.ReminderOnlyIfUndone, &u.FriendReminders, &u.LastSeenAt, &since); err != nil {
			return nil, err
		}
		out = append(out, model.Friend{User: &u, Since: since})
	}
	return out, rows.Err()
}

// prefixCols rewrites "a, b" into "p.a, p.b" for joined selects.
func prefixCols(p, cols string) string {
	parts := strings.Split(cols, ",")
	for i, c := range parts {
		parts[i] = p + "." + strings.TrimSpace(c)
	}
	return strings.Join(parts, ", ")
}

func (s *Store) FriendIDs(ctx context.Context, userID string) ([]string, error) {
	rows, err := s.pool.Query(ctx, `SELECT CASE WHEN user_a = $1 THEN user_b ELSE user_a END
		FROM friendships WHERE user_a = $1 OR user_b = $1`, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}

func (s *Store) AreFriends(ctx context.Context, a, b string) (bool, error) {
	a, b = orderPair(a, b)
	var ok bool
	err := s.pool.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM friendships WHERE user_a=$1 AND user_b=$2)", a, b).Scan(&ok)
	return ok, err
}

func (s *Store) CreateFriendship(ctx context.Context, a, b string, at time.Time) error {
	if a == b {
		return store.ErrDuplicate
	}
	a, b = orderPair(a, b)
	_, err := s.pool.Exec(ctx, "INSERT INTO friendships (user_a, user_b, created_at) VALUES ($1,$2,$3)", a, b, at)
	if isUnique(err, "") {
		return store.ErrDuplicate
	}
	return err
}

func (s *Store) DeleteFriendship(ctx context.Context, a, b string) error {
	a, b = orderPair(a, b)
	tag, err := s.pool.Exec(ctx, "DELETE FROM friendships WHERE user_a=$1 AND user_b=$2", a, b)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return store.ErrNotFound
	}
	return nil
}

func (s *Store) CreateFriendRequest(ctx context.Context, r *model.FriendRequest) error {
	err := s.pool.QueryRow(ctx, `INSERT INTO friend_requests (from_user, to_user, message)
		VALUES ($1,$2,$3) RETURNING id, created_at`, r.FromUser, r.ToUser, r.Message).
		Scan(&r.ID, &r.CreatedAt)
	if isUnique(err, "") {
		return store.ErrDuplicate
	}
	return err
}

const requestCols = "id, from_user, to_user, message, created_at"

func (s *Store) GetFriendRequest(ctx context.Context, id string) (*model.FriendRequest, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+requestCols+" FROM friend_requests WHERE id=$1", id)
	if err != nil {
		return nil, err
	}
	r, err := pgx.CollectExactlyOneRow(rows, pgx.RowToAddrOfStructByName[model.FriendRequest])
	return r, notFound(err)
}

func (s *Store) FindFriendRequest(ctx context.Context, from, to string) (*model.FriendRequest, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+requestCols+" FROM friend_requests WHERE from_user=$1 AND to_user=$2", from, to)
	if err != nil {
		return nil, err
	}
	r, err := pgx.CollectExactlyOneRow(rows, pgx.RowToAddrOfStructByName[model.FriendRequest])
	return r, notFound(err)
}

func (s *Store) ListFriendRequests(ctx context.Context, userID string) ([]model.FriendRequest, []model.FriendRequest, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+requestCols+` FROM friend_requests
		WHERE from_user=$1 OR to_user=$1 ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, nil, err
	}
	all, err := pgx.CollectRows(rows, pgx.RowToStructByName[model.FriendRequest])
	if err != nil {
		return nil, nil, err
	}
	var in, out []model.FriendRequest
	for _, r := range all {
		if r.ToUser == userID {
			in = append(in, r)
		} else {
			out = append(out, r)
		}
	}
	return in, out, nil
}

func (s *Store) DeleteFriendRequest(ctx context.Context, id string) error {
	tag, err := s.pool.Exec(ctx, "DELETE FROM friend_requests WHERE id=$1", id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return store.ErrNotFound
	}
	return nil
}

func (s *Store) DeleteFriendRequestsBetween(ctx context.Context, a, b string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM friend_requests
		WHERE (from_user=$1 AND to_user=$2) OR (from_user=$2 AND to_user=$1)`, a, b)
	return err
}

func (s *Store) CountIncomingRequests(ctx context.Context, userID string) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx, "SELECT count(*) FROM friend_requests WHERE to_user=$1", userID).Scan(&n)
	return n, err
}

// Activity ----------------------------------------------------------------

func (s *Store) UpsertActivity(ctx context.Context, a *model.ActivityDay) (*model.ActivityDay, error) {
	rows, err := s.pool.Query(ctx, `INSERT INTO activity_days (user_id, day, kind, count, first_at, last_at)
		VALUES ($1,$2,$3,$4,$5,$6)
		ON CONFLICT (user_id, day, kind) DO UPDATE SET
			count = GREATEST(activity_days.count, EXCLUDED.count),
			last_at = EXCLUDED.last_at
		RETURNING user_id, day, kind, count, first_at, last_at`,
		a.UserID, a.Day, a.Kind, a.Count, a.FirstAt, a.LastAt)
	if err != nil {
		return nil, err
	}
	return pgx.CollectExactlyOneRow(rows, pgx.RowToAddrOfStructByName[model.ActivityDay])
}

func (s *Store) ListActivity(ctx context.Context, userID, fromDay, toDay string) ([]model.ActivityDay, error) {
	rows, err := s.pool.Query(ctx, `SELECT user_id, day, kind, count, first_at, last_at FROM activity_days
		WHERE user_id=$1 AND day >= $2 AND day <= $3 ORDER BY day, kind`, userID, fromDay, toDay)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByName[model.ActivityDay])
}

func (s *Store) LearnDays(ctx context.Context, userIDs []string, fromDay string) (map[string][]string, error) {
	out := map[string][]string{}
	if len(userIDs) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `SELECT user_id, day FROM activity_days
		WHERE user_id = ANY($1) AND kind = 'learn' AND day >= $2 ORDER BY user_id, day`, userIDs, fromDay)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id, day string
		if err := rows.Scan(&id, &day); err != nil {
			return nil, err
		}
		out[id] = append(out[id], day)
	}
	return out, rows.Err()
}

func (s *Store) HasActivity(ctx context.Context, userID, day, kind string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM activity_days WHERE user_id=$1 AND day=$2 AND kind=$3)",
		userID, day, kind).Scan(&ok)
	return ok, err
}

func (s *Store) LastActiveDays(ctx context.Context, userIDs []string) (map[string]string, error) {
	out := map[string]string{}
	if len(userIDs) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `SELECT user_id, max(day) FROM activity_days
		WHERE user_id = ANY($1) GROUP BY user_id`, userIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id, day string
		if err := rows.Scan(&id, &day); err != nil {
			return nil, err
		}
		out[id] = day
	}
	return out, rows.Err()
}

// Streak snapshots --------------------------------------------------------

func (s *Store) PutStreak(ctx context.Context, st *model.StreakSnapshot) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO streak_snapshots (user_id, current, best, freezes, last_day, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6)
		ON CONFLICT (user_id) DO UPDATE SET current=EXCLUDED.current, best=EXCLUDED.best,
			freezes=EXCLUDED.freezes, last_day=EXCLUDED.last_day, updated_at=EXCLUDED.updated_at`,
		st.UserID, st.Current, st.Best, st.Freezes, st.LastDay, st.UpdatedAt)
	return err
}

const streakCols = "user_id, current, best, freezes, last_day, updated_at"

func (s *Store) GetStreak(ctx context.Context, userID string) (*model.StreakSnapshot, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+streakCols+" FROM streak_snapshots WHERE user_id=$1", userID)
	if err != nil {
		return nil, err
	}
	st, err := pgx.CollectExactlyOneRow(rows, pgx.RowToAddrOfStructByName[model.StreakSnapshot])
	return st, notFound(err)
}

func (s *Store) GetStreaks(ctx context.Context, userIDs []string) (map[string]*model.StreakSnapshot, error) {
	out := map[string]*model.StreakSnapshot{}
	if len(userIDs) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, "SELECT "+streakCols+" FROM streak_snapshots WHERE user_id = ANY($1)", userIDs)
	if err != nil {
		return nil, err
	}
	sts, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[model.StreakSnapshot])
	if err != nil {
		return nil, err
	}
	for _, st := range sts {
		out[st.UserID] = st
	}
	return out, nil
}

// Achievements ------------------------------------------------------------

const achievementCols = "id, user_id, key, kind, title, detail, earned_at, created_at"

func (s *Store) CreateAchievement(ctx context.Context, a *model.Achievement) (bool, error) {
	// ON CONFLICT DO NOTHING returns no row on conflict; a second query
	// fetches the existing one. Two round trips only on the rare duplicate.
	rows, err := s.pool.Query(ctx, `INSERT INTO achievements (user_id, key, kind, title, detail, earned_at)
		VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (user_id, key) DO NOTHING
		RETURNING `+achievementCols, a.UserID, a.Key, a.Kind, a.Title, a.Detail, a.EarnedAt)
	if err != nil {
		return false, err
	}
	created, err := pgx.CollectRows(rows, pgx.RowToStructByName[model.Achievement])
	if err != nil {
		return false, err
	}
	if len(created) == 1 {
		*a = created[0]
		return true, nil
	}
	rows, err = s.pool.Query(ctx, "SELECT "+achievementCols+" FROM achievements WHERE user_id=$1 AND key=$2", a.UserID, a.Key)
	if err != nil {
		return false, err
	}
	existing, err := pgx.CollectExactlyOneRow(rows, pgx.RowToStructByName[model.Achievement])
	if err != nil {
		return false, notFound(err)
	}
	*a = existing
	return false, nil
}

func (s *Store) GetAchievement(ctx context.Context, id string) (*model.Achievement, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+achievementCols+" FROM achievements WHERE id=$1", id)
	if err != nil {
		return nil, err
	}
	a, err := pgx.CollectExactlyOneRow(rows, pgx.RowToAddrOfStructByName[model.Achievement])
	return a, notFound(err)
}

func (s *Store) ListAchievements(ctx context.Context, userID string, limit int) ([]model.Achievement, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+achievementCols+` FROM achievements
		WHERE user_id=$1 ORDER BY earned_at DESC, id DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByName[model.Achievement])
}

func (s *Store) Feed(ctx context.Context, userIDs []string, before time.Time, limit int, viewerID string) (*store.FeedPage, error) {
	page := &store.FeedPage{Cheers: map[string]int{}, Cheered: map[string]bool{}}
	if len(userIDs) == 0 {
		return page, nil
	}
	rows, err := s.pool.Query(ctx, `SELECT a.id, a.user_id, a.key, a.kind, a.title, a.detail, a.earned_at, a.created_at,
			(SELECT count(*) FROM cheers c WHERE c.achievement_id = a.id) AS cheers,
			EXISTS (SELECT 1 FROM cheers c WHERE c.achievement_id = a.id AND c.user_id = $4) AS cheered
		FROM achievements a
		WHERE a.user_id = ANY($1) AND a.earned_at < $2
		ORDER BY a.earned_at DESC, a.id DESC LIMIT $3`, userIDs, before, limit, viewerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var a model.Achievement
		var n int
		var cheered bool
		if err := rows.Scan(&a.ID, &a.UserID, &a.Key, &a.Kind, &a.Title, &a.Detail, &a.EarnedAt, &a.CreatedAt, &n, &cheered); err != nil {
			return nil, err
		}
		page.Items = append(page.Items, a)
		page.Cheers[a.ID] = n
		page.Cheered[a.ID] = cheered
	}
	return page, rows.Err()
}

func (s *Store) AddCheer(ctx context.Context, achievementID, userID string, at time.Time) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO cheers (achievement_id, user_id, created_at) VALUES ($1,$2,$3)
		ON CONFLICT DO NOTHING`, achievementID, userID, at)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23503" { // foreign key: achievement gone
		return store.ErrNotFound
	}
	return err
}

func (s *Store) RemoveCheer(ctx context.Context, achievementID, userID string) error {
	_, err := s.pool.Exec(ctx, "DELETE FROM cheers WHERE achievement_id=$1 AND user_id=$2", achievementID, userID)
	return err
}

func (s *Store) CountCheers(ctx context.Context, achievementID string) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx, "SELECT count(*) FROM cheers WHERE achievement_id=$1", achievementID).Scan(&n)
	return n, err
}

// Push --------------------------------------------------------------------

const pushCols = "id, user_id, endpoint, p256dh, auth, user_agent, created_at, last_used_at, failures"

func (s *Store) UpsertPushSubscription(ctx context.Context, sub *model.PushSubscription) error {
	rows, err := s.pool.Query(ctx, `INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
		VALUES ($1,$2,$3,$4,$5)
		ON CONFLICT (endpoint) DO UPDATE SET user_id=EXCLUDED.user_id, p256dh=EXCLUDED.p256dh,
			auth=EXCLUDED.auth, user_agent=EXCLUDED.user_agent, failures=0
		RETURNING `+pushCols, sub.UserID, sub.Endpoint, sub.P256dh, sub.Auth, sub.UserAgent)
	if err != nil {
		return err
	}
	got, err := pgx.CollectExactlyOneRow(rows, pgx.RowToStructByName[model.PushSubscription])
	if err != nil {
		return err
	}
	*sub = got
	return nil
}

func (s *Store) DeletePushSubscription(ctx context.Context, userID, endpoint string) error {
	_, err := s.pool.Exec(ctx, "DELETE FROM push_subscriptions WHERE user_id=$1 AND endpoint=$2", userID, endpoint)
	return err
}

func (s *Store) DeletePushSubscriptionByID(ctx context.Context, id string) error {
	_, err := s.pool.Exec(ctx, "DELETE FROM push_subscriptions WHERE id=$1", id)
	return err
}

func (s *Store) ListPushSubscriptions(ctx context.Context, userID string) ([]model.PushSubscription, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+pushCols+" FROM push_subscriptions WHERE user_id=$1 ORDER BY created_at", userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByName[model.PushSubscription])
}

func (s *Store) RecordPushResult(ctx context.Context, id string, ok bool, at time.Time) error {
	var err error
	if ok {
		_, err = s.pool.Exec(ctx, "UPDATE push_subscriptions SET failures=0, last_used_at=$2 WHERE id=$1", id, at)
	} else {
		_, err = s.pool.Exec(ctx, "UPDATE push_subscriptions SET failures=failures+1 WHERE id=$1", id)
	}
	return err
}

// Backups -----------------------------------------------------------------

func (s *Store) PutBackup(ctx context.Context, b *model.Backup) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO backups (user_id, body, updated_at, size_bytes) VALUES ($1,$2,$3,$4)
		ON CONFLICT (user_id) DO UPDATE SET body=EXCLUDED.body, updated_at=EXCLUDED.updated_at,
			size_bytes=EXCLUDED.size_bytes`, b.UserID, b.Body, b.UpdatedAt, b.SizeBytes)
	return err
}

func (s *Store) GetBackup(ctx context.Context, userID string) (*model.Backup, error) {
	b := &model.Backup{UserID: userID}
	err := s.pool.QueryRow(ctx, "SELECT body, updated_at, size_bytes FROM backups WHERE user_id=$1", userID).
		Scan(&b.Body, &b.UpdatedAt, &b.SizeBytes)
	if err != nil {
		return nil, notFound(err)
	}
	return b, nil
}

func (s *Store) DeleteBackup(ctx context.Context, userID string) error {
	_, err := s.pool.Exec(ctx, "DELETE FROM backups WHERE user_id=$1", userID)
	return err
}

// Reminders ---------------------------------------------------------------

func (s *Store) ReminderCandidates(ctx context.Context) ([]*model.User, error) {
	rows, err := s.pool.Query(ctx, "SELECT "+userCols+` FROM users
		WHERE ((reminder_time IS NOT NULL AND reminder_tz IS NOT NULL) OR friend_reminders)
		  AND EXISTS (SELECT 1 FROM push_subscriptions p WHERE p.user_id = users.id)
		ORDER BY id`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[model.User])
}

func (s *Store) TryLogReminder(ctx context.Context, userID, day, kind string, at time.Time) (bool, error) {
	tag, err := s.pool.Exec(ctx, `INSERT INTO reminder_log (user_id, day, kind, sent_at) VALUES ($1,$2,$3,$4)
		ON CONFLICT DO NOTHING`, userID, day, kind, at)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// Server keys -------------------------------------------------------------

func (s *Store) GetOrSetServerKey(ctx context.Context, name, value string) (string, error) {
	if _, err := s.pool.Exec(ctx, "INSERT INTO server_keys (name, value) VALUES ($1,$2) ON CONFLICT DO NOTHING", name, value); err != nil {
		return "", err
	}
	var v string
	if err := s.pool.QueryRow(ctx, "SELECT value FROM server_keys WHERE name=$1", name).Scan(&v); err != nil {
		return "", fmt.Errorf("read server key %q: %w", name, err)
	}
	return v, nil
}
