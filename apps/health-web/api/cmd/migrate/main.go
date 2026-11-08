// Command migrate applies schema migrations and seeds the master exercise
// catalog.
//
//	migrate up                 apply all pending migrations
//	migrate down --steps N     roll back N migrations
//	migrate version            print the current schema version
//	migrate seed               upsert the master exercise catalog (idempotent)
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/config"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/logx"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/migrations"
	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/seed"
)

var version = "v0.0.0"

func main() {
	slog.SetDefault(logx.New(os.Stderr, "health-migrate", version))

	var steps int
	flag.IntVar(&steps, "steps", 1, "number of migration steps for down")
	flag.Parse()

	command := "up"
	if flag.NArg() > 0 {
		command = flag.Arg(0)
	}

	cfg := config.Load()
	if cfg.DatabaseURL == "" {
		slog.Error("DATABASE_URL is required")
		os.Exit(1)
	}

	switch command {
	case "up":
		if err := migrations.Up(cfg.MigrationsPath, cfg.DatabaseURL); err != nil {
			slog.Error("migration up failed", "error", err)
			os.Exit(1)
		}
		slog.Info("migrations applied", "path", cfg.MigrationsPath)
	case "down":
		if steps < 1 {
			slog.Error("steps must be positive")
			os.Exit(1)
		}
		if err := migrations.Down(cfg.MigrationsPath, cfg.DatabaseURL, steps); err != nil {
			slog.Error("migration down failed", "error", err)
			os.Exit(1)
		}
		slog.Info("migrations rolled back", "steps", steps)
	case "version":
		schemaVersion, dirty, err := migrations.Version(cfg.MigrationsPath, cfg.DatabaseURL)
		if err != nil {
			slog.Error("migration version failed", "error", err)
			os.Exit(1)
		}
		slog.Info("migration version", "schema_version", schemaVersion, "dirty", dirty)
	case "seed":
		stats, err := seed.Run(context.Background(), cfg.DatabaseURL, cfg.SeedPath)
		if err != nil {
			slog.Error("seed failed", "error", err, "path", cfg.SeedPath)
			os.Exit(1)
		}
		slog.Info("master exercise catalog seeded",
			"path", cfg.SeedPath,
			"categories", stats.Categories,
			"category_translations", stats.CategoryTranslations,
			"definitions", stats.Definitions,
			"translations", stats.Translations,
			"one_rm_formulas", stats.OneRMFormulas)
	default:
		slog.Error("unknown migration command", "command", command)
		os.Exit(1)
	}
}
