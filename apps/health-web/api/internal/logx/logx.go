// Package logx implements Project Log Contract v3 for the health-web Go
// binaries (health-api and health-migrate).
package logx

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"
	"unicode/utf8"
)

// MaxStacktraceBytes is the 8 KiB cap on exception.stacktrace (contract §3, FR-004).
const MaxStacktraceBytes = 8192

const timeLayout = "2006-01-02T15:04:05.000Z07:00"

type traceIDContextKey struct{}

// WithTraceID stores a 32-lowercase-hex W3C trace_id in ctx.
func WithTraceID(ctx context.Context, traceID string) context.Context {
	if ctx == nil {
		ctx = context.Background()
	}
	return context.WithValue(ctx, traceIDContextKey{}, traceID)
}

// TraceIDFromContext returns the trace_id stored in ctx, or "".
func TraceIDFromContext(ctx context.Context) string {
	if ctx == nil {
		return ""
	}
	tid, _ := ctx.Value(traceIDContextKey{}).(string)
	return tid
}

// New returns a JSON slog.Logger that formats time in UTC with millisecond
// precision, attaches service.name and service.version to every record, maps
// top-level "error" attrs to exception.message + exception.type (from the
// innermost unwrapped error), and caps exception.stacktrace at 8 KiB.
func New(w io.Writer, service, version string) *slog.Logger {
	if w == nil {
		w = os.Stderr
	}
	if strings.TrimSpace(version) == "" {
		version = "v0.0.0"
	}
	base := slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level:       slog.LevelDebug,
		ReplaceAttr: replaceAttr,
	}).WithAttrs([]slog.Attr{
		slog.String("service.name", service),
		slog.String("service.version", version),
	})
	return slog.New(&contractHandler{inner: base})
}

func replaceAttr(groups []string, a slog.Attr) slog.Attr {
	if len(groups) != 0 {
		return a
	}
	val := a.Value.Resolve()
	switch a.Key {
	case slog.TimeKey:
		if val.Kind() == slog.KindTime {
			return slog.String(slog.TimeKey, val.Time().UTC().Format(timeLayout))
		}
	case "exception.stacktrace":
		return slog.String("exception.stacktrace", TruncateStacktrace(val.String()))
	}
	return a
}

type contractHandler struct {
	inner        slog.Handler
	inGroup      bool
	hasTraceID   bool
	hasException bool
}

func (h *contractHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.inner.Enabled(ctx, level)
}

func (h *contractHandler) Handle(ctx context.Context, r slog.Record) error {
	nr := slog.NewRecord(r.Time, r.Level, r.Message, r.PC)
	hasTraceID := h.hasTraceID
	hasException := h.hasException

	r.Attrs(func(a slog.Attr) bool {
		val := a.Value.Resolve()
		if !h.inGroup && a.Key == "error" {
			if err, ok := val.Any().(error); ok && err != nil {
				nr.AddAttrs(
					slog.String("exception.type", errorType(err)),
					slog.String("exception.message", err.Error()),
				)
				hasException = true
			} else if val.Any() != nil && val.String() != "" {
				nr.AddAttrs(slog.String("exception.message", val.String()))
				hasException = true
			}
			return true
		}
		if !h.inGroup && a.Key == "exception.stacktrace" {
			nr.AddAttrs(slog.String("exception.stacktrace", TruncateStacktrace(val.String())))
			return true
		}
		if !h.inGroup && (a.Key == "exception.message" || a.Key == "exception.type") && val.String() != "" {
			hasException = true
		}
		if !h.inGroup && a.Key == "trace_id" && val.String() != "" {
			hasTraceID = true
		}
		nr.AddAttrs(a)
		return true
	})

	if !hasTraceID {
		if tid := TraceIDFromContext(ctx); tid != "" {
			nr.AddAttrs(slog.String("trace_id", tid))
		}
	}
	if r.Level >= slog.LevelError && !hasException {
		nr.AddAttrs(slog.String("exception.message", r.Message))
	}

	return h.inner.Handle(ctx, nr)
}

func (h *contractHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	transformed := make([]slog.Attr, 0, len(attrs))
	hasTraceID := h.hasTraceID
	hasException := h.hasException

	for _, a := range attrs {
		val := a.Value.Resolve()
		if !h.inGroup && a.Key == "error" {
			if err, ok := val.Any().(error); ok && err != nil {
				transformed = append(transformed,
					slog.String("exception.type", errorType(err)),
					slog.String("exception.message", err.Error()),
				)
				hasException = true
			} else if val.Any() != nil && val.String() != "" {
				transformed = append(transformed, slog.String("exception.message", val.String()))
				hasException = true
			}
			continue
		}
		if !h.inGroup && a.Key == "exception.stacktrace" {
			transformed = append(transformed, slog.String("exception.stacktrace", TruncateStacktrace(val.String())))
			continue
		}
		if !h.inGroup && (a.Key == "exception.message" || a.Key == "exception.type") && val.String() != "" {
			hasException = true
		}
		if !h.inGroup && a.Key == "trace_id" && val.String() != "" {
			hasTraceID = true
		}
		transformed = append(transformed, a)
	}

	return &contractHandler{
		inner:        h.inner.WithAttrs(transformed),
		inGroup:      h.inGroup,
		hasTraceID:   hasTraceID,
		hasException: hasException,
	}
}

func (h *contractHandler) WithGroup(name string) slog.Handler {
	if name == "" {
		return h
	}
	return &contractHandler{
		inner:        h.inner.WithGroup(name),
		inGroup:      true,
		hasTraceID:   h.hasTraceID,
		hasException: h.hasException,
	}
}

// Exception returns slog attributes for exception.type (from the innermost
// unwrapped error) and exception.message.
func Exception(err error) []any {
	if err == nil {
		return nil
	}
	return []any{
		"exception.type", errorType(err),
		"exception.message", err.Error(),
	}
}

func isGenericErrorType(t string) bool {
	switch t {
	case "*fmt.wrapError", "*errors.joinError", "*errors.errorString", "error", "Exception", "Error":
		return true
	default:
		return false
	}
}

func unwrapInnermost(err error) error {
	if err == nil {
		return nil
	}
	var deepestConcrete error
	cur := err
	for cur != nil {
		if !isGenericErrorType(fmt.Sprintf("%T", cur)) {
			deepestConcrete = cur
		}
		if u := errors.Unwrap(cur); u != nil {
			cur = u
			continue
		}
		if u, ok := cur.(interface{ Unwrap() []error }); ok {
			var firstNonNil error
			for _, sub := range u.Unwrap() {
				if sub == nil {
					continue
				}
				if firstNonNil == nil {
					firstNonNil = sub
				}
				inner := unwrapInnermost(sub)
				if inner != nil && !isGenericErrorType(fmt.Sprintf("%T", inner)) {
					deepestConcrete = inner
				}
			}
			if deepestConcrete != nil && !isGenericErrorType(fmt.Sprintf("%T", deepestConcrete)) {
				return deepestConcrete
			}
			if firstNonNil != nil {
				cur = firstNonNil
				continue
			}
		}
		break
	}
	if deepestConcrete != nil {
		return deepestConcrete
	}
	return cur
}

func errorType(err error) string {
	inner := unwrapInnermost(err)
	if inner == nil {
		return ""
	}
	t := fmt.Sprintf("%T", inner)
	if isGenericErrorType(t) {
		return strings.TrimPrefix(t, "*")
	}
	return t
}

// TruncateStacktrace caps s at MaxStacktraceBytes (8192 bytes), keeping the top
// and cutting the bottom with "\n…[truncated N bytes]".
func TruncateStacktrace(s string) string {
	if len(s) <= MaxStacktraceBytes {
		return s
	}
	maxSuffixLen := len(fmt.Sprintf("\n…[truncated %d bytes]", len(s)))
	limit := MaxStacktraceBytes - maxSuffixLen
	if nl := strings.LastIndexByte(s[:limit], '\n'); nl > 0 {
		cut := nl
		removed := len(s) - cut
		return fmt.Sprintf("%s\n…[truncated %d bytes]", s[:cut], removed)
	}
	cut := limit
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	removed := len(s) - cut
	return fmt.Sprintf("%s\n…[truncated %d bytes]", s[:cut], removed)
}

// ParseTraceparent extracts the 32-lowercase-hex trace_id from a W3C
// traceparent header ("00-<32-hex>-<16-hex>-<2-hex>").
func ParseTraceparent(header string) (string, bool) {
	parts := strings.Split(strings.ToLower(strings.TrimSpace(header)), "-")
	if len(parts) != 4 {
		return "", false
	}
	ver, traceID, parentID, flags := parts[0], parts[1], parts[2], parts[3]
	if len(ver) != 2 || ver == "ff" || !isLowerHex(ver) {
		return "", false
	}
	if len(traceID) != 32 || !isLowerHex(traceID) || isAllZeros(traceID) {
		return "", false
	}
	if len(parentID) != 16 || !isLowerHex(parentID) || isAllZeros(parentID) {
		return "", false
	}
	if len(flags) != 2 || !isLowerHex(flags) {
		return "", false
	}
	return traceID, true
}

// FormatTraceparent builds a W3C traceparent header value from a 32-hex trace_id.
func FormatTraceparent(traceID string) string {
	if len(traceID) != 32 {
		return ""
	}
	return "00-" + traceID + "-" + traceID[:16] + "-01"
}

// NewTraceID generates a random 16-byte (32 lowercase hex) W3C trace_id.
func NewTraceID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil || b == [16]byte{} {
		b[15] = 1
	}
	return hex.EncodeToString(b[:])
}

func isLowerHex(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return len(s) > 0
}

func isAllZeros(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] != '0' {
			return false
		}
	}
	return true
}

type statusRecorder struct {
	http.ResponseWriter
	ctx         context.Context
	status      int
	wroteHeader bool
}

func (r *statusRecorder) WriteHeader(code int) {
	if !r.wroteHeader {
		r.status = code
		r.wroteHeader = true
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	if !r.wroteHeader {
		r.status = http.StatusOK
		r.wroteHeader = true
	}
	return r.ResponseWriter.Write(b)
}

func (r *statusRecorder) Unwrap() http.ResponseWriter {
	return r.ResponseWriter
}

// ContextFromResponseWriter returns the request context attached by Middleware,
// or context.Background() if w was not wrapped by Middleware.
func ContextFromResponseWriter(w http.ResponseWriter) context.Context {
	for w != nil {
		if sr, ok := w.(*statusRecorder); ok && sr.ctx != nil {
			return sr.ctx
		}
		u, ok := w.(interface{ Unwrap() http.ResponseWriter })
		if !ok {
			break
		}
		w = u.Unwrap()
	}
	return context.Background()
}

// Middleware parses the incoming W3C traceparent header (or generates a new
// 32-hex trace_id), stores trace_id in the request context, and emits one
// access log line per request with the contract v3 HTTP attributes.
func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		traceID, ok := ParseTraceparent(r.Header.Get("traceparent"))
		if !ok {
			traceID = NewTraceID()
		}
		ctx := WithTraceID(r.Context(), traceID)
		rec := &statusRecorder{
			ResponseWriter: w,
			ctx:            ctx,
			status:         http.StatusOK,
		}

		next.ServeHTTP(rec, r.WithContext(ctx))

		duration := time.Since(start).Seconds()
		msg := fmt.Sprintf("%s %s %d", r.Method, r.URL.Path, rec.status)
		attrs := []any{
			"trace_id", traceID,
			"http.request.method", r.Method,
			"url.path", r.URL.Path,
			"http.response.status_code", rec.status,
			"http.server.request.duration", duration,
		}
		if rec.status >= http.StatusInternalServerError {
			slog.ErrorContext(ctx, msg, attrs...)
		} else {
			slog.InfoContext(ctx, msg, attrs...)
		}
	})
}
