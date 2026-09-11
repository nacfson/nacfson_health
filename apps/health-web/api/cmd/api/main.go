// Command api serves the health web API (cookie-only auth, Postgres store).
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

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/auth"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/config"
	httpapi "github.com/nacfson/nacfson_health/apps/health-web/api/internal/httpapi"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/store"
)

func main() {
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

	st, err := store.New(ctx, cfg.DatabaseURL, location)
	if err != nil {
		slog.Error("database unavailable", "error", err)
		os.Exit(1)
	}
	defer st.Close()

	central := auth.NewCentralClient(cfg.CentralAuthURL, cfg.CentralAuthInternalURL, cfg.AuthSessionInternalToken, nil)
	if cfg.AuthSessionInternalToken == "" {
		slog.Warn("AUTH_SESSION_INTERNAL_TOKEN is empty: every request will fail authentication")
	}

	server := &http.Server{
		Addr:              cfg.AppAddr,
		Handler:           httpapi.NewHandler(cfg, st, central),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	errs := make(chan error, 1)
	go func() {
		slog.Info("health api listening",
			"addr", cfg.AppAddr,
			"public_url", cfg.AppPublicURL,
			"auth_url", cfg.CentralAuthInternalURL,
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
