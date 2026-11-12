// Command openword-api is the OpenWord backend: accounts, friends, streaks,
// the achievements feed, Web Push reminders and encrypted-at-rest-by-you
// backups, in one small static binary in front of Postgres.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	// Embed the IANA zone database so reminder time zones resolve even on a
	// base image without tzdata. Costs ~450 KB.
	_ "time/tzdata"

	"github.com/tahuffman1s/openword/server/internal/config"
	"github.com/tahuffman1s/openword/server/internal/db"
	"github.com/tahuffman1s/openword/server/internal/handlers"
	"github.com/tahuffman1s/openword/server/internal/push"
	"github.com/tahuffman1s/openword/server/internal/reminders"
	"github.com/tahuffman1s/openword/server/internal/store/pgstore"
)

func main() {
	if err := run(); err != nil {
		slog.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.FromEnv()
	if err != nil {
		return err
	}
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.LogLevel}))
	slog.SetDefault(log)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool, log); err != nil {
		return err
	}
	st := pgstore.New(pool)

	keys, err := push.LoadOrCreateKeys(ctx, st)
	if err != nil {
		return err
	}
	pusher := push.NewService(st, keys, cfg.VAPIDSubject(), cfg.PublicURL, log)

	srv := handlers.New(st, cfg, pusher, keys.Public, log)
	httpServer := &http.Server{
		Addr:              cfg.Listen,
		Handler:           srv.Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second, // avatar/backup uploads over a slow tunnel
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}

	// Background workers.
	go reminders.New(st, pusher, log).Run(ctx)
	go func() {
		t := time.NewTicker(time.Hour)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				if n, err := st.DeleteExpiredSessions(ctx, time.Now()); err != nil {
					log.Warn("session cleanup", "err", err)
				} else if n > 0 {
					log.Info("expired sessions removed", "count", n)
				}
			}
		}
	}()

	errCh := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", cfg.Listen, "inviteRequired", cfg.InviteCode != "", "publicUrl", cfg.PublicURL)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}
	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return httpServer.Shutdown(shutdownCtx)
}
