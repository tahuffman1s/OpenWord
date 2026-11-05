package handlers

import (
	"crypto/subtle"
	"errors"
	"net/http"
	"strings"

	"github.com/tahuffman1s/openword/server/internal/auth"
	"github.com/tahuffman1s/openword/server/internal/httpx"
	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
	"github.com/tahuffman1s/openword/server/internal/validate"
)

type registerRequest struct {
	Username    string  `json:"username"`
	Password    string  `json:"password"`
	DisplayName string  `json:"displayName"`
	Email       *string `json:"email"`
	InviteCode  string  `json:"inviteCode"`
}

// sessionResponse is returned by register and login. The token duplicates
// the cookie for clients that prefer Authorization: Bearer.
type sessionResponse struct {
	User  model.UserJSON `json:"user"`
	Token string         `json:"token"`
}

// POST /api/auth/register
func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	if s.cfg.InviteCode != "" && subtle.ConstantTimeCompare([]byte(req.InviteCode), []byte(s.cfg.InviteCode)) != 1 {
		httpx.Error(w, http.StatusForbidden, "invite_required", "A valid invite code is required to register.")
		return
	}
	username, err := validate.Username(req.Username)
	if err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	if err := validate.Password(req.Password); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	displayName := req.DisplayName
	if strings.TrimSpace(displayName) == "" {
		displayName = username
	}
	if displayName, err = validate.DisplayName(displayName); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	var email *string
	if req.Email != nil && strings.TrimSpace(*req.Email) != "" {
		e, err := validate.Email(*req.Email)
		if err != nil {
			httpx.BadRequest(w, err.Error())
			return
		}
		email = &e
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	u := &model.User{
		Username:             username,
		DisplayName:          displayName,
		Email:                email,
		PasswordHash:         hash,
		ReminderDays:         127,
		ReminderOnlyIfUndone: true,
		FriendReminders:      true,
	}
	if err := s.store.CreateUser(r.Context(), u); err != nil {
		switch {
		case errors.Is(err, store.ErrUsernameTaken):
			httpx.Error(w, http.StatusConflict, "username_taken", "That username is already taken.")
		case errors.Is(err, store.ErrEmailTaken):
			httpx.Error(w, http.StatusConflict, "email_taken", "That email is already in use.")
		default:
			httpx.Internal(w, err)
		}
		return
	}
	token, err := s.startSession(w, r, u)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, sessionResponse{User: u.Private(), Token: token})
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// POST /api/auth/login
func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	ident := strings.ToLower(strings.TrimSpace(req.Username))
	if ident == "" || req.Password == "" {
		httpx.BadRequest(w, "username and password are required")
		return
	}
	var (
		u   *model.User
		err error
	)
	if strings.Contains(ident, "@") {
		u, err = s.store.GetUserByEmail(r.Context(), ident)
	} else {
		u, err = s.store.GetUserByUsername(r.Context(), ident)
	}
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		httpx.Internal(w, err)
		return
	}
	// Always run the hash so unknown usernames take as long as wrong
	// passwords.
	hash := auth.DummyHash
	if u != nil {
		hash = u.PasswordHash
	}
	ok, _ := auth.VerifyPassword(hash, req.Password)
	if u == nil || !ok {
		httpx.Error(w, http.StatusUnauthorized, "bad_credentials", "Wrong username or password.")
		return
	}
	token, err := s.startSession(w, r, u)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, sessionResponse{User: u.Private(), Token: token})
}

// POST /api/auth/logout — idempotent; a missing or bad token still 204s.
func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if token := tokenFrom(r); token != "" {
		if err := s.store.DeleteSession(r.Context(), auth.HashToken(token)); err != nil {
			httpx.Internal(w, err)
			return
		}
	}
	s.clearCookie(w, r)
	w.WriteHeader(http.StatusNoContent)
}
