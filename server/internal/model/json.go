package model

import (
	"fmt"
	"time"
)

// PublicUser is the profile shape other users may see.
type PublicUser struct {
	ID            string    `json:"id"`
	Username      string    `json:"username"`
	DisplayName   string    `json:"displayName"`
	Bio           string    `json:"bio"`
	AvatarVersion int       `json:"avatarVersion"`
	AvatarURL     *string   `json:"avatarUrl"`
	CreatedAt     time.Time `json:"createdAt"`
}

// UserJSON is the owner's view of their own account: PublicUser plus email.
type UserJSON struct {
	PublicUser
	Email *string `json:"email"`
}

// SettingsJSON is the reminder-related settings block of GET /api/me.
type SettingsJSON struct {
	ReminderTime         *string `json:"reminderTime"`
	ReminderTZ           *string `json:"reminderTz"`
	ReminderDays         int     `json:"reminderDays"`
	ReminderOnlyIfUndone bool    `json:"reminderOnlyIfUndone"`
	FriendReminders      bool    `json:"friendReminders"`
}

// StreakJSON is the API shape of a StreakSnapshot.
type StreakJSON struct {
	Current   int       `json:"current"`
	Best      int       `json:"best"`
	Freezes   int       `json:"freezes"`
	LastDay   string    `json:"lastDay"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// AvatarURL builds the cache-busted avatar URL, or nil when no avatar is set.
func AvatarURL(id string, version int) *string {
	if version == 0 {
		return nil
	}
	s := fmt.Sprintf("/api/users/%s/avatar?v=%d", id, version)
	return &s
}

// Public converts a User to its public JSON view.
func (u *User) Public() PublicUser {
	return PublicUser{
		ID:            u.ID,
		Username:      u.Username,
		DisplayName:   u.DisplayName,
		Bio:           u.Bio,
		AvatarVersion: u.AvatarVersion,
		AvatarURL:     AvatarURL(u.ID, u.AvatarVersion),
		CreatedAt:     u.CreatedAt.UTC(),
	}
}

// Private converts a User to the owner's JSON view.
func (u *User) Private() UserJSON {
	return UserJSON{PublicUser: u.Public(), Email: u.Email}
}

// Settings extracts the reminder settings block.
func (u *User) Settings() SettingsJSON {
	return SettingsJSON{
		ReminderTime:         u.ReminderTime,
		ReminderTZ:           u.ReminderTZ,
		ReminderDays:         u.ReminderDays,
		ReminderOnlyIfUndone: u.ReminderOnlyIfUndone,
		FriendReminders:      u.FriendReminders,
	}
}

// JSON converts a StreakSnapshot to its API shape; nil in, nil out.
func (s *StreakSnapshot) JSON() *StreakJSON {
	if s == nil {
		return nil
	}
	return &StreakJSON{
		Current:   s.Current,
		Best:      s.Best,
		Freezes:   s.Freezes,
		LastDay:   s.LastDay,
		UpdatedAt: s.UpdatedAt.UTC(),
	}
}
