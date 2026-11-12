package pgstore

import (
	"context"
	"io"
	"log/slog"
	"os"
	"testing"

	"github.com/tahuffman1s/openword/server/internal/db"
	"github.com/tahuffman1s/openword/server/internal/store"
	"github.com/tahuffman1s/openword/server/internal/store/storetest"
)

// TestConformance runs the shared store suite against a real Postgres when
// TEST_DATABASE_URL is set, e.g.
//
//	TEST_DATABASE_URL=postgres://openword:openword@localhost:5432/openword_test?sslmode=disable go test ./...
//
// Every table is truncated before each sub-test, so point it at a
// throwaway database.
func TestConformance(t *testing.T) {
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	pool, err := db.Open(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if err := db.Migrate(ctx, pool, slog.New(slog.NewTextHandler(io.Discard, nil))); err != nil {
		t.Fatal(err)
	}
	storetest.Run(t, func(t *testing.T) store.Store {
		if _, err := pool.Exec(ctx, `TRUNCATE users, server_keys CASCADE`); err != nil {
			t.Fatal(err)
		}
		return New(pool)
	})
}
