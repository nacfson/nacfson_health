package config

import (
	"os"
	"strings"
)

const (
	defaultAppAddr        = ":8080"
	defaultMigrationsPath = "file://db/migrations"
	defaultPublicURL      = "https://health.nacfson.cloud"
	defaultAllowedOrigins = "https://health.nacfson.cloud,http://localhost:8080,http://127.0.0.1:8080"
	defaultTZ             = "Asia/Seoul"
	defaultSeedPath       = "db/master_exercise_seed_v12_6.json"
)

type Config struct {
	AppAddr                  string
	AppPublicURL             string
	DatabaseURL              string
	MigrationsPath           string
	CentralAuthURL           string
	CentralAuthInternalURL   string
	AuthSessionInternalToken string
	AllowedOrigins           []string
	Timezone                 string
	SeedPath                 string
}

func Load() Config {
	internal := strings.TrimSpace(os.Getenv("CENTRAL_AUTH_INTERNAL_URL"))
	publicAuth := envOrDefault("CENTRAL_AUTH_URL", "https://auth.nacfson.cloud")
	return Config{
		AppAddr:                  envOrDefault("APP_ADDR", defaultAppAddr),
		AppPublicURL:             envOrDefault("APP_PUBLIC_URL", defaultPublicURL),
		DatabaseURL:              strings.TrimSpace(os.Getenv("DATABASE_URL")),
		MigrationsPath:           envOrDefault("MIGRATIONS_PATH", defaultMigrationsPath),
		CentralAuthURL:           publicAuth,
		CentralAuthInternalURL:   firstNonEmpty(internal, publicAuth),
		AuthSessionInternalToken: strings.TrimSpace(os.Getenv("AUTH_SESSION_INTERNAL_TOKEN")),
		AllowedOrigins:           splitAndTrim(envOrDefault("ALLOWED_ORIGINS", defaultAllowedOrigins)),
		Timezone:                 envOrDefault("TZ", defaultTZ),
		SeedPath:                 envOrDefault("SEED_PATH", defaultSeedPath),
	}
}

func envOrDefault(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

func splitAndTrim(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}