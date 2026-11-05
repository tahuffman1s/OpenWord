// Package validate holds the input rules shared by the handlers. Every
// function returns a human-readable message suitable for an API error.
package validate

import (
	"errors"
	"net/mail"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/tahuffman1s/openword/server/internal/model"
)

var (
	usernameRe = regexp.MustCompile(`^[a-z0-9_]{3,24}$`)
	dayRe      = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)
	timeRe     = regexp.MustCompile(`^([01]\d|2[0-3]):[0-5]\d$`)
)

// Username lowercases and validates a username.
func Username(s string) (string, error) {
	s = strings.ToLower(strings.TrimSpace(s))
	if !usernameRe.MatchString(s) {
		return "", errors.New("username must be 3–24 characters of a-z, 0-9 or _")
	}
	return s, nil
}

// Password enforces the minimum length (and a sane maximum so argon2 does
// not chew on megabytes).
func Password(s string) error {
	if utf8.RuneCountInString(s) < 8 {
		return errors.New("password must be at least 8 characters")
	}
	if len(s) > 256 {
		return errors.New("password must be at most 256 bytes")
	}
	return nil
}

// DisplayName trims and checks 1–40 characters.
func DisplayName(s string) (string, error) {
	s = strings.TrimSpace(s)
	n := utf8.RuneCountInString(s)
	if n < 1 || n > 40 {
		return "", errors.New("displayName must be 1–40 characters")
	}
	return s, nil
}

// Bio trims and checks ≤ 160 characters.
func Bio(s string) (string, error) {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) > 160 {
		return "", errors.New("bio must be at most 160 characters")
	}
	return s, nil
}

// Email lowercases and checks the address shape. Empty is an error; callers
// treat an empty/null email as "no email" before calling this.
func Email(s string) (string, error) {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" || len(s) > 254 {
		return "", errors.New("email is invalid")
	}
	addr, err := mail.ParseAddress(s)
	if err != nil || addr.Address != s || !strings.Contains(s, "@") {
		return "", errors.New("email is invalid")
	}
	return s, nil
}

// Day checks the YYYY-MM-DD shape and that it is a real calendar date.
func Day(s string) error {
	if !dayRe.MatchString(s) {
		return errors.New("day must be YYYY-MM-DD")
	}
	if _, err := time.Parse("2006-01-02", s); err != nil {
		return errors.New("day is not a valid date")
	}
	return nil
}

// ActivityKind checks membership in model.ActivityKinds.
func ActivityKind(s string) error {
	for _, k := range model.ActivityKinds {
		if k == s {
			return nil
		}
	}
	return errors.New("kind must be one of " + strings.Join(model.ActivityKinds, ", "))
}

// AchievementKind checks membership in model.AchievementKinds.
func AchievementKind(s string) error {
	for _, k := range model.AchievementKinds {
		if k == s {
			return nil
		}
	}
	return errors.New("kind must be one of " + strings.Join(model.AchievementKinds, ", "))
}

// ReminderTime checks HH:MM (24h).
func ReminderTime(s string) error {
	if !timeRe.MatchString(s) {
		return errors.New("reminderTime must be HH:MM")
	}
	return nil
}

// TimeZone checks that s is a loadable IANA zone name.
func TimeZone(s string) error {
	if s == "" || s == "Local" {
		return errors.New("reminderTz must be an IANA time zone")
	}
	if _, err := time.LoadLocation(s); err != nil {
		return errors.New("reminderTz must be an IANA time zone")
	}
	return nil
}

// ReminderDays checks the Mon=1…Sun=64 bitmask.
func ReminderDays(n int) error {
	if n < 0 || n > 127 {
		return errors.New("reminderDays must be between 0 and 127")
	}
	return nil
}

// ShortText trims and bounds a free-text field such as a title or message.
func ShortText(s string, max int, field string) (string, error) {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) > max {
		return "", errors.New(field + " is too long")
	}
	return s, nil
}
