package httpapi

import (
	"bytes"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"testing"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/logx"
)

func TestHTTPAPILogContractV3(t *testing.T) {
	var buf bytes.Buffer
	prev := slog.Default()
	slog.SetDefault(logx.New(&buf, "health-api", "v1.4.2"))
	t.Cleanup(func() { slog.SetDefault(prev) })

	env := newTestEnv(t)

	const wantTrace = "4bf92f3577b34da6a3ce929d0e0e4736"
	rec := do(t, env.handler, http.MethodGet, "/api/auth/login", nil, func(r *http.Request) {
		r.Header.Set("traceparent", "00-"+wantTrace+"-00f067aa0ba902b7-01")
	})
	if rec.Code != http.StatusFound {
		t.Fatalf("login status = %d, want 302", rec.Code)
	}

	// Drive a 503 error path through session store failure.
	env.sessions.failAll = errors.New("db connection refused")
	recErr := do(t, env.handler, http.MethodGet, "/api/me", sessionCookie("tok-1"), nil)
	if recErr.Code != http.StatusServiceUnavailable {
		t.Fatalf("/api/me status = %d, want 503", recErr.Code)
	}

	raw := strings.TrimSpace(buf.String())
	lines := strings.Split(raw, "\n")
	if len(lines) < 4 {
		t.Fatalf("expected at least 4 log lines, got %d:\n%s", len(lines), raw)
	}

	for i, line := range lines {
		var m map[string]any
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			t.Fatalf("line %d invalid JSON: %v\n%s", i, err, line)
		}
		if m["service.name"] != "health-api" || m["service.version"] != "v1.4.2" {
			t.Fatalf("line %d wrong service identity: %v", i, m)
		}
		tid, _ := m["trace_id"].(string)
		if len(tid) != 32 {
			t.Fatalf("line %d missing 32-hex trace_id: %q", i, tid)
		}
		if i < 2 && tid != wantTrace {
			t.Fatalf("line %d trace_id = %q, want %q", i, tid, wantTrace)
		}
		if m["level"] == "error" {
			excMsg, _ := m["exception.message"].(string)
			excType, _ := m["exception.type"].(string)
			if excMsg == "" && excType == "" {
				t.Fatalf("line %d level=error missing exception fields: %v", i, m)
			}
		}
	}
}
