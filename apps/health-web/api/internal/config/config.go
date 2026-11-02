package config

import (
	"net/url"
	"os"
	"strings"
)

const (
	defaultAppAddr        = ":8080"
	defaultMigrationsPath = "file://db/migrations"
	defaultPublicAppURL   = "https://health.nacfson.cloud"
	defaultPublicAuthURL  = "https://auth.nacfson.cloud"
	defaultGatewayAuthURL = "http://gateway.identity.svc:8080/auth"
	defaultAllowedOrigins = "https://health.nacfson.cloud,http://localhost:8080,http://127.0.0.1:8080"
	defaultTZ             = "Asia/Seoul"
	defaultSeedPath       = "db/master_exercise_seed_v12_6.json"
)

// Config is the API runtime configuration. Sign-in follows the nacfson_pipeline
// shared sign-in contract (CONTRACT_AUTH_DOOR): the browser starts at
// PublicAuthURL/oauth/start, and this backend confirms sessions with the
// in-cluster gateway at GatewayAuthURL. No shared secret is needed.
type Config struct {
	AppAddr        string
	PublicAppURL   string
	DatabaseURL    string
	MigrationsPath string
	MigrateOnStart bool
	PublicAuthURL  string
	GatewayAuthURL string
	// ProjectAudience is the gateway audience this project accepts. Empty means
	// "project-" + the first label of the PublicAppURL host.
	ProjectAudience string
	AllowedOrigins  []string
	Timezone        string
	SeedPath        string
}

func Load() Config {
	return Config{
		AppAddr: envOrDefault("APP_ADDR", defaultAppAddr),
		// PUBLIC_APP_URL is what nacfson_pipeline sets; APP_PUBLIC_URL is the
		// older local name.
		PublicAppURL:    firstNonEmpty(os.Getenv("PUBLIC_APP_URL"), os.Getenv("APP_PUBLIC_URL"), defaultPublicAppURL),
		DatabaseURL:     strings.TrimSpace(os.Getenv("DATABASE_URL")),
		MigrationsPath:  envOrDefault("MIGRATIONS_PATH", defaultMigrationsPath),
		MigrateOnStart:  !strings.EqualFold(strings.TrimSpace(os.Getenv("MIGRATE_ON_START")), "false"),
		PublicAuthURL:   envOrDefault("PUBLIC_AUTH_URL", defaultPublicAuthURL),
		GatewayAuthURL:  envOrDefault("GATEWAY_AUTH_URL", defaultGatewayAuthURL),
		ProjectAudience: strings.TrimSpace(os.Getenv("PROJECT_AUDIENCE")),
		AllowedOrigins:  splitAndTrim(envOrDefault("ALLOWED_ORIGINS", defaultAllowedOrigins)),
		Timezone:        envOrDefault("TZ", defaultTZ),
		SeedPath:        envOrDefault("SEED_PATH", defaultSeedPath),
	}
}

// AppOrigin is PublicAppURL without a trailing slash.
func (c Config) AppOrigin() string {
	return strings.TrimRight(strings.TrimSpace(c.PublicAppURL), "/")
}

// AppHost is the hostname of PublicAppURL (e.g. "health.nacfson.cloud").
func (c Config) AppHost() string {
	u, err := url.Parse(c.AppOrigin())
	if err != nil {
		return ""
	}
	return u.Hostname()
}

// Audience is the gateway audience this project accepts ("project-health").
func (c Config) Audience() string {
	if a := strings.TrimSpace(c.ProjectAudience); a != "" {
		return a
	}
	host := c.AppHost()
	if host == "" {
		return ""
	}
	return "project-" + strings.Split(host, ".")[0]
}

// AuthOrigin is PublicAuthURL without a trailing slash.
func (c Config) AuthOrigin() string {
	return strings.TrimRight(strings.TrimSpace(c.PublicAuthURL), "/")
}

// GatewayBaseURL strips the trailing "/auth" from GatewayAuthURL so the
// exchange and logout endpoints can be derived from the one URL the platform
// sets ("http://gateway.identity.svc:8080/auth" -> "http://gateway.identity.svc:8080").
func (c Config) GatewayBaseURL() string {
	base := strings.TrimRight(strings.TrimSpace(c.GatewayAuthURL), "/")
	return strings.TrimSuffix(base, "/auth")
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
