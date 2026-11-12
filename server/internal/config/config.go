// Package config reads the process configuration from environment variables.
package config

import (
	"errors"
	"log/slog"
	"os"
	"strings"
)

// Config is everything the binary needs from its environment.
type Config struct {
	DatabaseURL string
	Listen      string
	InviteCode  string // when set, registration requires it
	PublicURL   string // e.g. https://openword.example; used in push links
	AdminEmail  string // VAPID subject mailto:
	LogLevel    slog.Level
	TrustProxy  bool // honour X-Forwarded-For / X-Forwarded-Proto
}

// FromEnv builds a Config from the environment, applying defaults.
func FromEnv() (*Config, error) {
	c := &Config{
		DatabaseURL: os.Getenv("DATABASE_URL"),
		Listen:      getenv("LISTEN", ":8080"),
		InviteCode:  os.Getenv("OPENWORD_INVITE_CODE"),
		PublicURL:   strings.TrimRight(os.Getenv("OPENWORD_PUBLIC_URL"), "/"),
		AdminEmail:  os.Getenv("OPENWORD_ADMIN_EMAIL"),
		TrustProxy:  getenv("TRUST_PROXY", "1") == "1",
	}
	if c.DatabaseURL == "" {
		return nil, errors.New("DATABASE_URL is required")
	}
	switch strings.ToLower(getenv("LOG_LEVEL", "info")) {
	case "debug":
		c.LogLevel = slog.LevelDebug
	case "info":
		c.LogLevel = slog.LevelInfo
	case "warn", "warning":
		c.LogLevel = slog.LevelWarn
	case "error":
		c.LogLevel = slog.LevelError
	default:
		return nil, errors.New("LOG_LEVEL must be debug, info, warn or error")
	}
	return c, nil
}

// VAPIDSubject returns the contact URI sent to push services.
func (c *Config) VAPIDSubject() string {
	if c.AdminEmail != "" {
		return "mailto:" + c.AdminEmail
	}
	if c.PublicURL != "" {
		return c.PublicURL
	}
	return "https://github.com/tahuffman1s/OpenWord"
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
