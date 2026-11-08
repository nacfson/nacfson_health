package logx_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/logx"
)

func TestLineHasRequiredKeys(t *testing.T) {
	var buf bytes.Buffer
	logger := logx.New(&buf, "health-api", "v1.4.2")
	logger.Info("hello")

	var m map[string]any
	if err := json.Unmarshal(buf.Bytes(), &m); err != nil {
		t.Fatalf("unmarshal: %v (%s)", err, buf.String())
	}
	for _, k := range []string{"time", "level", "msg", "service.name", "service.version"} {
		if _, ok := m[k]; !ok {
			t.Fatalf("missing %s in %s", k, buf.String())
		}
	}
	if m["service.name"] != "health-api" {
		t.Fatalf("service.name = %v, want health-api", m["service.name"])
	}
	if m["service.version"] != "v1.4.2" {
		t.Fatalf("service.version = %v, want v1.4.2", m["service.version"])
	}
	timeRe := regexp.MustCompile(`^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$`)
	if !timeRe.MatchString(fmt.Sprint(m["time"])) {
		t.Fatalf("time %q is not RFC 3339 UTC with milliseconds", m["time"])
	}
}

func TestErrorAttrBecomesException(t *testing.T) {
	var buf bytes.Buffer
	wrapped := fmt.Errorf("enrich word 4812: %w", context.DeadlineExceeded)
	logx.New(&buf, "health-api", "v1.4.2").Error("enrich failed", "error", wrapped)

	var m map[string]any
	if err := json.Unmarshal(buf.Bytes(), &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if m["level"] != "ERROR" {
		t.Fatalf("level = %v, want ERROR", m["level"])
	}
	if m["exception.message"] != "enrich word 4812: context deadline exceeded" {
		t.Fatalf("exception.message = %v", m["exception.message"])
	}
	if m["exception.type"] != "context.deadlineExceededError" {
		t.Fatalf("exception.type = %v, want context.deadlineExceededError", m["exception.type"])
	}
	if _, ok := m["error"]; ok {
		t.Fatal("top-level error attr must be replaced by exception.*")
	}
}

func TestExceptionHelperUnwrapsInnermost(t *testing.T) {
	uErr := &url.Error{Op: "Get", URL: "https://health.nacfson.cloud", Err: errors.New("connection reset")}
	joined := errors.Join(errors.New("outer"), fmt.Errorf("wrap: %w", uErr))

	attrs := logx.Exception(joined)
	var buf bytes.Buffer
	logx.New(&buf, "health-api", "v1.4.2").Error("request failed", attrs...)

	var m map[string]any
	if err := json.Unmarshal(buf.Bytes(), &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if m["exception.type"] != "*url.Error" {
		t.Fatalf("exception.type = %v, want *url.Error", m["exception.type"])
	}
	if !strings.Contains(fmt.Sprint(m["exception.message"]), "connection reset") {
		t.Fatalf("exception.message = %v", m["exception.message"])
	}
}

func TestStacktraceCappedAt8KiB(t *testing.T) {
	t.Run("exact 8192 bytes unchanged", func(t *testing.T) {
		exact := strings.Repeat("a", 8192)
		var buf bytes.Buffer
		logx.New(&buf, "health-api", "v1.4.2").Error("boom",
			"error", context.DeadlineExceeded,
			"exception.stacktrace", exact,
		)
		var m map[string]any
		if err := json.Unmarshal(buf.Bytes(), &m); err != nil {
			t.Fatalf("unmarshal: %v", err)
		}
		got := fmt.Sprint(m["exception.stacktrace"])
		if len(got) != 8192 || got != exact {
			t.Fatalf("expected unchanged 8192-byte trace, got len %d", len(got))
		}
	})

	t.Run("long multiline trace capped at 8192 with top kept and truncated marker", func(t *testing.T) {
		var lines []string
		lines = append(lines, "goroutine 1 [running]:")
		for i := 0; i < 300; i++ {
			lines = append(lines, fmt.Sprintf("main.frame%03d(0x%08x)\n\t/app/cmd/api/main.go:%d +0x42", i, i, i+10))
		}
		longTrace := strings.Join(lines, "\n")
		if len(longTrace) <= 8192 {
			t.Fatalf("fixture too short: %d", len(longTrace))
		}

		var buf bytes.Buffer
		logx.New(&buf, "health-api", "v1.4.2").Error("panic recovered",
			"error", context.DeadlineExceeded,
			"exception.stacktrace", longTrace,
		)
		var m map[string]any
		if err := json.Unmarshal(buf.Bytes(), &m); err != nil {
			t.Fatalf("unmarshal: %v", err)
		}
		got := fmt.Sprint(m["exception.stacktrace"])
		if len(got) > 8192 {
			t.Fatalf("stacktrace len = %d, exceeds 8192", len(got))
		}
		if !strings.HasPrefix(got, "goroutine 1 [running]:\n") {
			t.Fatalf("top of stacktrace not preserved: %q", got[:40])
		}
		markerRe := regexp.MustCompile(`\n…\[truncated (\d+) bytes\]$`)
		sub := markerRe.FindStringSubmatch(got)
		if sub == nil {
			t.Fatalf("missing truncation suffix in %q", got[len(got)-60:])
		}
		removed, err := strconv.Atoi(sub[1])
		if err != nil || removed <= 0 {
			t.Fatalf("invalid truncated byte count: %v", sub[1])
		}
		keptLen := len(got) - len(sub[0])
		if keptLen+removed != len(longTrace) {
			t.Fatalf("kept (%d) + removed (%d) != original (%d)", keptLen, removed, len(longTrace))
		}
	})
}

func TestTraceMiddlewarePropagatesAndLogsAccess(t *testing.T) {
	var buf bytes.Buffer
	prev := slog.Default()
	slog.SetDefault(logx.New(&buf, "health-api", "v1.4.2"))
	defer slog.SetDefault(prev)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /ok", func(w http.ResponseWriter, r *http.Request) {
		slog.InfoContext(r.Context(), "inside handler")
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("GET /fail", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	})

	h := logx.Middleware(mux)

	t.Run("uses incoming W3C traceparent", func(t *testing.T) {
		buf.Reset()
		req := httptest.NewRequest(http.MethodGet, "/ok", nil)
		req.Header.Set("traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)

		lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
		if len(lines) != 2 {
			t.Fatalf("expected 2 log lines (handler + access), got %d:\n%s", len(lines), buf.String())
		}
		for i, line := range lines {
			var m map[string]any
			if err := json.Unmarshal([]byte(line), &m); err != nil {
				t.Fatalf("line %d: %v", i, err)
			}
			if m["trace_id"] != "4bf92f3577b34da6a3ce929d0e0e4736" {
				t.Fatalf("line %d trace_id = %v", i, m["trace_id"])
			}
		}
		var access map[string]any
		_ = json.Unmarshal([]byte(lines[1]), &access)
		if access["http.request.method"] != "GET" || access["url.path"] != "/ok" || access["http.response.status_code"] != float64(200) {
			t.Fatalf("unexpected access fields: %v", access)
		}
		if _, ok := access["http.server.request.duration"].(float64); !ok {
			t.Fatalf("missing numeric http.server.request.duration: %v", access)
		}
	})

	t.Run("generates 32-hex trace_id when traceparent absent and sets level=ERROR on 5xx", func(t *testing.T) {
		buf.Reset()
		req := httptest.NewRequest(http.MethodGet, "/fail", nil)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)

		var access map[string]any
		if err := json.Unmarshal(buf.Bytes(), &access); err != nil {
			t.Fatalf("unmarshal: %v (%s)", err, buf.String())
		}
		if access["level"] != "ERROR" {
			t.Fatalf("level = %v, want ERROR for 503", access["level"])
		}
		tid := fmt.Sprint(access["trace_id"])
		if !regexp.MustCompile(`^[0-9a-f]{32}$`).MatchString(tid) || tid == strings.Repeat("0", 32) {
			t.Fatalf("invalid generated trace_id %q", tid)
		}
		if access["http.response.status_code"] != float64(503) {
			t.Fatalf("status_code = %v, want 503", access["http.response.status_code"])
		}
	})
}

func TestNoTextHandlers(t *testing.T) {
	root := filepath.Join("..", "..")
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return err
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if bytes.Contains(b, []byte("NewTextHandler")) {
			t.Errorf("%s contains slog.NewTextHandler", path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}
