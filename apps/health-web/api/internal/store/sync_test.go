package store

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestRowTimeAcceptsTimestampAlias(t *testing.T) {
	ts := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	row := SyncRow{"timestamp": ts.Format(time.RFC3339Nano)}
	got, err := rowTime(row, "timestamp", "recorded_at")
	if err != nil {
		t.Fatal(err)
	}
	if !got.Equal(ts) {
		t.Fatalf("got %v want %v", got, ts)
	}
}

func TestRowTimeRequiresField(t *testing.T) {
	_, err := rowTime(SyncRow{}, "updated_at")
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestRequiredUUID(t *testing.T) {
	id := uuid.New()
	got, err := requiredUUID(SyncRow{"uuid": id.String()}, "uuid")
	if err != nil || got != id {
		t.Fatalf("got %v err %v", got, err)
	}
	if _, err := requiredUUID(SyncRow{"uuid": "nope"}, "uuid"); err == nil {
		t.Fatal("expected invalid uuid error")
	}
}

func TestEncodeItemsJSON(t *testing.T) {
	raw, err := encodeItemsJSON([]any{map[string]any{"name": "squat"}})
	if err != nil {
		t.Fatal(err)
	}
	if raw == "" || raw[0] != '[' {
		t.Fatalf("unexpected %q", raw)
	}
	raw2, err := encodeItemsJSON(`[{"name":"bench"}]`)
	if err != nil || raw2 != `[{"name":"bench"}]` {
		t.Fatalf("string passthrough failed: %q %v", raw2, err)
	}
}

func TestUnknownSyncResource(t *testing.T) {
	s := &Store{}
	if err := s.UpsertSyncRows(t.Context(), uuid.New(), "nope", nil); err == nil {
		t.Fatal("expected unknown resource error")
	}
	if _, err := s.PullSyncRows(t.Context(), uuid.New(), "nope", nil); err == nil {
		t.Fatal("expected unknown resource error")
	}
}
