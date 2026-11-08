// Command api serves the health web API. Sign-in goes through the
// nacfson_pipeline platform gateway; sessions are server-side (Postgres).
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

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/config"
	httpapi "github.com/nacfson/nacfson_health/apps/health-web/api/internal/httpapi"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/logx"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/migrations"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/platformauth"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/seed"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

var version = "v0.0.0"

const sessionPurgeInterval = time.Hour

// purgeExpiredSessions deletes expired web_sessions rows every hour until ctx
// ends. Lookups already ignore expired rows; this only bounds table growth.
func purgeExpiredSessions(ctx context.Context, st *store.Store) {
	ticker := time.NewTicker(sessionPurgeInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			n, err := st.PurgeExpiredWebSessions(ctx)
			if err != nil {
				slog.Warn("auth.session.purge_failed", "error", err)
				continue
			}
			if n > 0 {
				slog.Info("auth.session.purged", "count", n)
			}
		}
	}
}

func main() {
	slog.SetDefault(logx.New(os.Stderr, "health-api", version))

	ctx := context.Background()
	cfg := config.Load()
	if cfg.DatabaseURL == "" {
		slog.Error("DATABASE_URL is required")
		os.Exit(1)
	}

	location, err := time.LoadLocation(cfg.Timezone)
	if err != nil {
		slog.Warn("unknown timezone, falling back to Asia/Seoul", "timezone", cfg.Timezone, "error", err)
		location, err = time.LoadLocation("Asia/Seoul")
		if err != nil {
			location = time.UTC
		}
	}

	// nacfson_pipeline CONTRACT_DATABASE §6: idempotent schema migrations run on
	// backend startup from MIGRATIONS_PATH. golang-migrate holds an advisory
	// lock, so overlapping rollouts cannot double-apply.
	if cfg.MigrateOnStart {
		if err := migrations.Up(cfg.MigrationsPath, cfg.DatabaseURL); err != nil {
			slog.Error("migrations failed", "path", cfg.MigrationsPath, "error", err)
			os.Exit(1)
		}
		slog.Info("migrations applied", "path", cfg.MigrationsPath)
		stats, err := seed.Run(ctx, cfg.DatabaseURL, cfg.SeedPath)
		if err != nil {
			slog.Error("master catalog seed failed", "path", cfg.SeedPath, "error", err)
			os.Exit(1)
		}
		slog.Info("master catalog seeded", "definitions", stats.Definitions, "translations", stats.Translations)
	}

	st, err := store.New(ctx, cfg.DatabaseURL, location)
	if err != nil {
		slog.Error("database unavailable", "error", err)
		os.Exit(1)
	}
	defer st.Close()

	if cfg.Audience() == "" {
		slog.Error("cannot derive the gateway audience; set PUBLIC_APP_URL or PROJECT_AUDIENCE")
		os.Exit(1)
	}
	gateway := platformauth.NewClient(cfg.GatewayBaseURL(), cfg.AppHost(), nil)

	purgeCtx, stopPurge := context.WithCancel(ctx)
	defer stopPurge()
	go purgeExpiredSessions(purgeCtx, st)

	server := &http.Server{
		Addr:              cfg.AppAddr,
		Handler:           httpapi.NewHandler(cfg, st, st, gateway),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	errs := make(chan error, 1)
	go func() {
		slog.Info("health api listening",
			"addr", cfg.AppAddr,
			"public_url", cfg.AppOrigin(),
			"auth_url", cfg.AuthOrigin(),
			"gateway_url", cfg.GatewayBaseURL(),
			"audience", cfg.Audience(),
			"timezone", location.String())
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errs <- err
		}
	}()

	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, os.Interrupt, syscall.SIGTERM)

	select {
	case err := <-errs:
		slog.Error("server stopped", "error", err)
		os.Exit(1)
	case sig := <-shutdown:
		slog.Info("shutting down", "signal", sig.String())
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			slog.Error("graceful shutdown failed", "error", err)
			os.Exit(1)
		}
	}
}
