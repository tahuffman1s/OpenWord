package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/tahuffman1s/openword/server/internal/auth"
	"github.com/tahuffman1s/openword/server/internal/httpx"
	"github.com/tahuffman1s/openword/server/internal/images"
	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
	"github.com/tahuffman1s/openword/server/internal/validate"
)

type meResponse struct {
	User     model.UserJSON     `json:"user"`
	Settings model.SettingsJSON `json:"settings"`
	Streak   *model.StreakJSON  `json:"streak"`
	Counts   struct {
		Friends         int `json:"friends"`
		PendingRequests int `json:"pendingRequests"`
	} `json:"counts"`
}

// GET /api/me
func (s *Server) getMe(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	u := userFrom(ctx)
	resp := meResponse{User: u.Private(), Settings: u.Settings()}

	streak, err := s.store.GetStreak(ctx, u.ID)
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		httpx.Internal(w, err)
		return
	}
	resp.Streak = streak.JSON()

	friends, err := s.store.FriendIDs(ctx, u.ID)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	resp.Counts.Friends = len(friends)
	if resp.Counts.PendingRequests, err = s.store.CountIncomingRequests(ctx, u.ID); err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, resp)
}

// PATCH /api/me
//
// The body is decoded into a map first so that "field": null (clear) can be
// told apart from the field being absent (leave alone).
func (s *Server) patchMe(w http.ResponseWriter, r *http.Request) {
	var fields map[string]json.RawMessage
	if err := httpx.Decode(r, &fields); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	u := userFrom(r.Context()).Clone()

	// optString unmarshals a string-or-null field; present reports whether
	// the key was in the body at all.
	optString := func(key string) (val *string, present bool, err error) {
		raw, ok := fields[key]
		if !ok {
			return nil, false, nil
		}
		if string(raw) == "null" {
			return nil, true, nil
		}
		var v string
		if err := json.Unmarshal(raw, &v); err != nil {
			return nil, true, errors.New(key + " must be a string or null")
		}
		return &v, true, nil
	}

	if v, ok, err := optString("displayName"); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	} else if ok {
		if v == nil {
			httpx.BadRequest(w, "displayName cannot be null")
			return
		}
		name, err := validate.DisplayName(*v)
		if err != nil {
			httpx.BadRequest(w, err.Error())
			return
		}
		u.DisplayName = name
	}
	if v, ok, err := optString("bio"); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	} else if ok {
		bio := ""
		if v != nil {
			bio = *v
		}
		if bio, err = validate.Bio(bio); err != nil {
			httpx.BadRequest(w, err.Error())
			return
		}
		u.Bio = bio
	}
	if v, ok, err := optString("email"); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	} else if ok {
		if v == nil || strings.TrimSpace(*v) == "" {
			u.Email = nil
		} else {
			e, err := validate.Email(*v)
			if err != nil {
				httpx.BadRequest(w, err.Error())
				return
			}
			u.Email = &e
		}
	}
	if v, ok, err := optString("reminderTime"); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	} else if ok {
		if v == nil || *v == "" {
			u.ReminderTime = nil
		} else {
			if err := validate.ReminderTime(*v); err != nil {
				httpx.BadRequest(w, err.Error())
				return
			}
			u.ReminderTime = v
		}
	}
	if v, ok, err := optString("reminderTz"); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	} else if ok {
		if v == nil || *v == "" {
			u.ReminderTZ = nil
		} else {
			if err := validate.TimeZone(*v); err != nil {
				httpx.BadRequest(w, err.Error())
				return
			}
			u.ReminderTZ = v
		}
	}
	if raw, ok := fields["reminderDays"]; ok {
		var n int
		if err := json.Unmarshal(raw, &n); err != nil {
			httpx.BadRequest(w, "reminderDays must be an integer")
			return
		}
		if err := validate.ReminderDays(n); err != nil {
			httpx.BadRequest(w, err.Error())
			return
		}
		u.ReminderDays = n
	}
	for key, dst := range map[string]*bool{
		"reminderOnlyIfUndone": &u.ReminderOnlyIfUndone,
		"friendReminders":      &u.FriendReminders,
	} {
		if raw, ok := fields[key]; ok {
			if err := json.Unmarshal(raw, dst); err != nil {
				httpx.BadRequest(w, key+" must be a boolean")
				return
			}
		}
	}

	if err := s.store.UpdateUser(r.Context(), u); err != nil {
		if errors.Is(err, store.ErrEmailTaken) {
			httpx.Error(w, http.StatusConflict, "email_taken", "That email is already in use.")
			return
		}
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, struct {
		User     model.UserJSON     `json:"user"`
		Settings model.SettingsJSON `json:"settings"`
	}{u.Private(), u.Settings()})
}

// POST /api/me/password
func (s *Server) changePassword(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Current string `json:"current"`
		Next    string `json:"next"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	u := userFrom(r.Context())
	if ok, _ := auth.VerifyPassword(u.PasswordHash, req.Current); !ok {
		httpx.Error(w, http.StatusUnauthorized, "bad_credentials", "Current password is wrong.")
		return
	}
	if err := validate.Password(req.Next); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	hash, err := auth.HashPassword(req.Next)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	if err := s.store.UpdatePassword(r.Context(), u.ID, hash); err != nil {
		httpx.Internal(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// PUT /api/me/avatar — raw image bytes in the body.
func (s *Server) putAvatar(w http.ResponseWriter, r *http.Request) {
	ct := r.Header.Get("Content-Type")
	if !strings.HasPrefix(ct, "image/") {
		httpx.BadRequest(w, "Content-Type must be image/*")
		return
	}
	jpg, err := images.Avatar(r.Body)
	switch {
	case err == nil:
	case httpx.IsTooLarge(err):
		httpx.Error(w, http.StatusRequestEntityTooLarge, "too_large", "Images must be 4 MB or smaller.")
		return
	case errors.Is(err, images.ErrTooLarge):
		httpx.BadRequest(w, "Image dimensions are too large.")
		return
	case errors.Is(err, images.ErrUnsupported):
		httpx.BadRequest(w, "Could not read that image. Use PNG, JPEG, GIF or WebP.")
		return
	default:
		httpx.Internal(w, err)
		return
	}
	u := userFrom(r.Context())
	v, err := s.store.SetAvatar(r.Context(), u.ID, jpg, images.AvatarContentType)
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"avatarVersion": v, "avatarUrl": model.AvatarURL(u.ID, v)})
}

// DELETE /api/me/avatar
func (s *Server) deleteAvatar(w http.ResponseWriter, r *http.Request) {
	if err := s.store.ClearAvatar(r.Context(), userFrom(r.Context()).ID); err != nil {
		httpx.Internal(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /api/me — requires the password; removes the account and all data.
func (s *Server) deleteMe(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Password string `json:"password"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	u := userFrom(r.Context())
	if ok, _ := auth.VerifyPassword(u.PasswordHash, req.Password); !ok {
		httpx.Error(w, http.StatusUnauthorized, "bad_credentials", "Password is wrong.")
		return
	}
	if err := s.store.DeleteUser(r.Context(), u.ID); err != nil {
		httpx.Internal(w, err)
		return
	}
	s.clearCookie(w, r)
	w.WriteHeader(http.StatusNoContent)
}

// PUT /api/me/backup — any JSON document up to 4 MB.
func (s *Server) putBackup(w http.ResponseWriter, r *http.Request) {
	var body json.RawMessage
	if err := httpx.Decode(r, &body); err != nil {
		if strings.Contains(err.Error(), "too large") {
			httpx.Error(w, http.StatusRequestEntityTooLarge, "too_large", "Backups must be 4 MB or smaller.")
			return
		}
		httpx.BadRequest(w, err.Error())
		return
	}
	b := &model.Backup{
		UserID:    userFrom(r.Context()).ID,
		Body:      body,
		UpdatedAt: s.now().UTC(),
		SizeBytes: len(body),
	}
	if err := s.store.PutBackup(r.Context(), b); err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"updatedAt": b.UpdatedAt, "sizeBytes": b.SizeBytes})
}

// GET /api/me/backup — returns the stored document verbatim.
func (s *Server) getBackup(w http.ResponseWriter, r *http.Request) {
	b, err := s.store.GetBackup(r.Context(), userFrom(r.Context()).ID)
	if storeErr(w, err, "No backup stored.") {
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Backup-Updated-At", b.UpdatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(b.Body)
}

// DELETE /api/me/backup
func (s *Server) deleteBackup(w http.ResponseWriter, r *http.Request) {
	if err := s.store.DeleteBackup(r.Context(), userFrom(r.Context()).ID); err != nil {
		httpx.Internal(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
