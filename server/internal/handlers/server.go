// Package handlers wires the HTTP API: routing, middleware, sessions and the
// endpoint implementations. Everything speaks JSON and reports errors as
// {"error": code, "message": text}.
package handlers

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/tahuffman1s/openword/server/internal/auth"
	"github.com/tahuffman1s/openword/server/internal/config"
	"github.com/tahuffman1s/openword/server/internal/httpx"
	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/push"
	"github.com/tahuffman1s/openword/server/internal/ratelimit"
	"github.com/tahuffman1s/openword/server/internal/store"
)

const (
	// SessionCookie is the cookie name carrying the session token.
	SessionCookie = "ow_session"
	// sessionTTL is how long a session lives after its last extension.
	sessionTTL = 90 * 24 * time.Hour
	// sessionSlide: the expiry is pushed out again once it is more than
	// this much older than a fresh one, i.e. at most once a day.
	sessionSlide = 24 * time.Hour

	bodyLimitDefault = 1 << 20 // 1 MB
	bodyLimitLarge   = 4 << 20 // 4 MB for avatar and backup uploads
)

// Notifier is what the handlers need from the push service.
type Notifier interface {
	SendToUser(ctx context.Context, userID string, n push.Notification) (int, error)
}

// Server holds the dependencies of every handler.
type Server struct {
	store       store.Store
	cfg         *config.Config
	push        Notifier
	vapidPublic string
	log         *slog.Logger
	limiter     *ratelimit.Limiter
	now         func() time.Time
}

// New builds a Server. vapidPublic is served to clients for subscribing.
func New(st store.Store, cfg *config.Config, n Notifier, vapidPublic string, log *slog.Logger) *Server {
	return &Server{
		store:       st,
		cfg:         cfg,
		push:        n,
		vapidPublic: vapidPublic,
		log:         log,
		limiter:     ratelimit.New(10, 20),
		now:         time.Now,
	}
}

// Routes returns the fully wired handler.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", s.healthz)

	// Auth (public, rate limited).
	mux.HandleFunc("POST /api/auth/register", s.rateLimited(s.register))
	mux.HandleFunc("POST /api/auth/login", s.rateLimited(s.login))
	mux.HandleFunc("POST /api/auth/logout", s.logout)

	// Me.
	mux.HandleFunc("GET /api/me", s.auth(s.getMe))
	mux.HandleFunc("PATCH /api/me", s.auth(s.patchMe))
	mux.HandleFunc("DELETE /api/me", s.auth(s.deleteMe))
	mux.HandleFunc("POST /api/me/password", s.auth(s.changePassword))
	mux.HandleFunc("PUT /api/me/avatar", s.auth(s.putAvatar))
	mux.HandleFunc("DELETE /api/me/avatar", s.auth(s.deleteAvatar))
	mux.HandleFunc("PUT /api/me/backup", s.auth(s.putBackup))
	mux.HandleFunc("GET /api/me/backup", s.auth(s.getBackup))
	mux.HandleFunc("DELETE /api/me/backup", s.auth(s.deleteBackup))

	// Users.
	mux.HandleFunc("GET /api/users/search", s.auth(s.searchUsers))
	mux.HandleFunc("GET /api/users/{id}/avatar", s.getAvatar)
	mux.HandleFunc("GET /api/users/{username}", s.auth(s.getUserProfile))

	// Friends.
	mux.HandleFunc("GET /api/friends", s.auth(s.listFriends))
	mux.HandleFunc("DELETE /api/friends/{userId}", s.auth(s.removeFriend))
	mux.HandleFunc("GET /api/friends/requests", s.auth(s.listFriendRequests))
	mux.HandleFunc("POST /api/friends/requests", s.auth(s.createFriendRequest))
	mux.HandleFunc("POST /api/friends/requests/{id}/accept", s.auth(s.acceptFriendRequest))
	mux.HandleFunc("POST /api/friends/requests/{id}/decline", s.auth(s.declineFriendRequest))
	mux.HandleFunc("DELETE /api/friends/requests/{id}", s.auth(s.cancelFriendRequest))

	// Activity & streaks.
	mux.HandleFunc("POST /api/activity", s.auth(s.postActivity))
	mux.HandleFunc("GET /api/activity", s.auth(s.getActivity))
	mux.HandleFunc("PUT /api/streak", s.auth(s.putStreak))
	mux.HandleFunc("GET /api/streaks", s.auth(s.getStreaks))

	// Achievements & feed.
	mux.HandleFunc("POST /api/achievements", s.auth(s.postAchievement))
	mux.HandleFunc("POST /api/achievements/batch", s.auth(s.postAchievementBatch))
	mux.HandleFunc("GET /api/feed", s.auth(s.getFeed))
	mux.HandleFunc("POST /api/feed/{id}/cheer", s.auth(s.cheer))
	mux.HandleFunc("DELETE /api/feed/{id}/cheer", s.auth(s.uncheer))

	// Push.
	mux.HandleFunc("GET /api/push/vapid", s.getVAPID)
	mux.HandleFunc("POST /api/push/subscriptions", s.auth(s.subscribePush))
	mux.HandleFunc("DELETE /api/push/subscriptions", s.auth(s.unsubscribePush))
	mux.HandleFunc("POST /api/push/test", s.auth(s.testPush))

	// Anything else under /api is a JSON 404 rather than the mux's text one.
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		httpx.NotFound(w, "No such endpoint.")
	})

	return s.logging(s.bodyLimit(s.securityHeaders(mux)))
}

// --- middleware --------------------------------------------------------------

// statusWriter captures the status code for the access log.
type statusWriter struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func (w *statusWriter) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	n, err := w.ResponseWriter.Write(b)
	w.bytes += n
	return n, err
}

func (s *Server) logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := s.now()
		sw := &statusWriter{ResponseWriter: w}
		next.ServeHTTP(sw, r)
		if r.URL.Path == "/healthz" {
			return // too chatty to log
		}
		s.log.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", sw.status,
			"bytes", sw.bytes,
			"ms", s.now().Sub(start).Milliseconds(),
			"ip", s.clientIP(r),
		)
	})
}

func (s *Server) bodyLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		limit := int64(bodyLimitDefault)
		if r.Method == http.MethodPut && (r.URL.Path == "/api/me/avatar" || r.URL.Path == "/api/me/backup") {
			limit = bodyLimitLarge
		}
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, limit)
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		next.ServeHTTP(w, r)
	})
}

// rateLimited applies the per-IP token bucket.
func (s *Server) rateLimited(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.limiter.Allow(s.clientIP(r)) {
			w.Header().Set("Retry-After", "60")
			httpx.Error(w, http.StatusTooManyRequests, "rate_limited", "Too many attempts. Try again in a minute.")
			return
		}
		next(w, r)
	}
}

// clientIP returns the caller's address, honouring the first hop of
// X-Forwarded-For when a trusted proxy is in front.
func (s *Server) clientIP(r *http.Request) string {
	if s.cfg.TrustProxy {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			first, _, _ := strings.Cut(xff, ",")
			if ip := strings.TrimSpace(first); ip != "" {
				return ip
			}
		}
		if rip := r.Header.Get("X-Real-IP"); rip != "" {
			return strings.TrimSpace(rip)
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// isSecure reports whether the client reached us over HTTPS, directly or
// via a proxy that says so.
func (s *Server) isSecure(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	return s.cfg.TrustProxy && strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
}

// --- sessions ----------------------------------------------------------------

type ctxKey int

const (
	ctxUser ctxKey = iota
	ctxSession
)

// userFrom returns the authenticated user placed by auth().
func userFrom(ctx context.Context) *model.User {
	u, _ := ctx.Value(ctxUser).(*model.User)
	return u
}

func sessionFrom(ctx context.Context) *model.Session {
	s, _ := ctx.Value(ctxSession).(*model.Session)
	return s
}

// tokenFrom extracts the raw session token from the cookie or the
// Authorization: Bearer header.
func tokenFrom(r *http.Request) string {
	if h := r.Header.Get("Authorization"); h != "" {
		if scheme, tok, ok := strings.Cut(h, " "); ok && strings.EqualFold(scheme, "Bearer") {
			return strings.TrimSpace(tok)
		}
	}
	if c, err := r.Cookie(SessionCookie); err == nil {
		return c.Value
	}
	return ""
}

// auth requires a valid session and slides its expiry.
func (s *Server) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := tokenFrom(r)
		if token == "" {
			httpx.Unauthorized(w)
			return
		}
		hash := auth.HashToken(token)
		sess, err := s.store.GetSession(r.Context(), hash)
		now := s.now()
		if err != nil || !sess.ExpiresAt.After(now) {
			if err != nil && !errors.Is(err, store.ErrNotFound) {
				httpx.Internal(w, err)
				return
			}
			s.clearCookie(w, r)
			httpx.Unauthorized(w)
			return
		}
		u, err := s.store.GetUser(r.Context(), sess.UserID)
		if err != nil {
			if errors.Is(err, store.ErrNotFound) {
				s.clearCookie(w, r)
				httpx.Unauthorized(w)
				return
			}
			httpx.Internal(w, err)
			return
		}
		// Sliding expiry: extend at most once a day.
		if sess.ExpiresAt.Before(now.Add(sessionTTL - sessionSlide)) {
			sess.ExpiresAt = now.Add(sessionTTL)
			if err := s.store.ExtendSession(r.Context(), hash, sess.ExpiresAt); err != nil {
				s.log.Warn("extend session", "err", err)
			}
			s.setCookie(w, r, token)
		}
		// Record presence, at most every few minutes.
		if u.LastSeenAt == nil || now.Sub(*u.LastSeenAt) > 5*time.Minute {
			if err := s.store.TouchLastSeen(r.Context(), u.ID, now); err != nil {
				s.log.Warn("touch last seen", "err", err)
			}
		}
		ctx := context.WithValue(r.Context(), ctxUser, u)
		ctx = context.WithValue(ctx, ctxSession, sess)
		next(w, r.WithContext(ctx))
	}
}

// startSession creates a session for u and sets the cookie. It returns the
// raw token so API clients without cookies can use it as a bearer token.
func (s *Server) startSession(w http.ResponseWriter, r *http.Request, u *model.User) (string, error) {
	token, err := auth.NewToken()
	if err != nil {
		return "", err
	}
	now := s.now()
	sess := &model.Session{
		TokenHash: auth.HashToken(token),
		UserID:    u.ID,
		CreatedAt: now,
		ExpiresAt: now.Add(sessionTTL),
		UserAgent: truncate(r.UserAgent(), 256),
	}
	if err := s.store.CreateSession(r.Context(), sess); err != nil {
		return "", err
	}
	s.setCookie(w, r, token)
	return token, nil
}

func (s *Server) setCookie(w http.ResponseWriter, r *http.Request, token string) {
	http.SetCookie(w, &http.Cookie{
		Name:     SessionCookie,
		Value:    token,
		Path:     "/",
		MaxAge:   int(sessionTTL.Seconds()),
		HttpOnly: true,
		Secure:   s.isSecure(r),
		SameSite: http.SameSiteLaxMode,
	})
}

func (s *Server) clearCookie(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{
		Name:     SessionCookie,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   s.isSecure(r),
		SameSite: http.SameSiteLaxMode,
	})
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// --- misc ----------------------------------------------------------------------

func (s *Server) healthz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.store.Ping(ctx); err != nil {
		s.log.Error("healthz: db ping failed", "err", err)
		http.Error(w, "db unavailable", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write([]byte("ok"))
}

// storeErr maps store errors to responses; returns true if it wrote one.
func storeErr(w http.ResponseWriter, err error, notFoundMsg string) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, store.ErrNotFound):
		httpx.NotFound(w, notFoundMsg)
	default:
		httpx.Internal(w, err)
	}
	return true
}

// userLocation returns the user's reminder zone, or UTC.
func userLocation(u *model.User) *time.Location {
	if u.ReminderTZ != nil {
		if loc, err := time.LoadLocation(*u.ReminderTZ); err == nil {
			return loc
		}
	}
	return time.UTC
}
