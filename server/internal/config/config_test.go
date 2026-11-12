package config

import (
	"log/slog"
	"testing"
)

func TestFromEnv(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	if _, err := FromEnv(); err == nil {
		t.Fatal("missing DATABASE_URL should fail")
	}
	t.Setenv("DATABASE_URL", "postgres://x")
	t.Setenv("LOG_LEVEL", "debug")
	t.Setenv("TRUST_PROXY", "0")
	t.Setenv("OPENWORD_PUBLIC_URL", "https://ow.example/")
	t.Setenv("OPENWORD_ADMIN_EMAIL", "a@b.c")
	c, err := FromEnv()
	if err != nil {
		t.Fatal(err)
	}
	if c.Listen != ":8080" || c.LogLevel != slog.LevelDebug || c.TrustProxy || c.PublicURL != "https://ow.example" {
		t.Errorf("unexpected config %+v", c)
	}
	if c.VAPIDSubject() != "mailto:a@b.c" {
		t.Error(c.VAPIDSubject())
	}
	t.Setenv("LOG_LEVEL", "loud")
	if _, err := FromEnv(); err == nil {
		t.Fatal("bad LOG_LEVEL should fail")
	}
}
