package platformauth

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type seen struct {
	method, path, auth, host, body string
}

func stubGateway(t *testing.T, handler func(w http.ResponseWriter, r *http.Request)) (*Client, *[]seen) {
	t.Helper()
	var calls []seen
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		calls = append(calls, seen{r.Method, r.URL.Path, r.Header.Get("Authorization"), r.Header.Get("X-Forwarded-Host"), string(b)})
		handler(w, r)
	}))
	t.Cleanup(srv.Close)
	return NewClient(srv.URL+"/", "health.nacfson.cloud", srv.Client()), &calls
}

func TestExchangeSendsTicketAndHostAndDecodesIdentity(t *testing.T) {
	c, calls := stubGateway(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"session_handle":"v1.h","subject":"sub-1","issuer":"https://auth.nacfson.cloud/realms/platform","audience":"project-health","expires_in":3600}`))
	})

	got, err := c.Exchange(context.Background(), " t-1 ")
	if err != nil {
		t.Fatalf("Exchange: %v", err)
	}
	want := Exchanged{"v1.h", "https://auth.nacfson.cloud/realms/platform", "sub-1", "project-health", time.Hour}
	if got != want {
		t.Fatalf("got %+v, want %+v", got, want)
	}
	call := (*calls)[0]
	if call.method != http.MethodPost || call.path != "/auth/exchange" || call.host != "health.nacfson.cloud" {
		t.Fatalf("unexpected call %+v", call)
	}
	if strings.TrimSpace(call.body) != `{"ticket":"t-1"}` {
		t.Fatalf("body = %q", call.body)
	}
}

func TestExchangeDefaultsExpiry(t *testing.T) {
	c, _ := stubGateway(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"session_handle":"h","subject":"s","issuer":"i","audience":"project-health"}`))
	})
	got, err := c.Exchange(context.Background(), "t")
	if err != nil || got.ExpiresIn != 8*time.Hour {
		t.Fatalf("got %+v, %v; want 8h default", got, err)
	}
}

func TestExchangeErrorMapping(t *testing.T) {
	cases := []struct {
		name   string
		status int
		body   string
		want   error
	}{
		{"ticket rejected", http.StatusUnauthorized, `{"error":"unauthorized"}`, ErrRejected},
		{"malformed ticket", http.StatusBadRequest, `{}`, ErrRejected},
		{"incomplete identity", http.StatusOK, `{"session_handle":"","subject":"s","issuer":"i"}`, ErrRejected},
		{"gateway error", http.StatusBadGateway, ``, ErrUnavailable},
		{"garbage body", http.StatusOK, `not json`, ErrUnavailable},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, _ := stubGateway(t, func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(tc.status)
				_, _ = w.Write([]byte(tc.body))
			})
			if _, err := c.Exchange(context.Background(), "t"); !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
		})
	}
}

func TestExchangeEmptyTicketNeverCallsGateway(t *testing.T) {
	c, calls := stubGateway(t, func(http.ResponseWriter, *http.Request) {})
	if _, err := c.Exchange(context.Background(), "  "); !errors.Is(err, ErrRejected) {
		t.Fatalf("err = %v", err)
	}
	if len(*calls) != 0 {
		t.Fatal("gateway called for an empty ticket")
	}
}

func TestConfirmSendsBearerAndHostAndReadsHeaders(t *testing.T) {
	c, calls := stubGateway(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("X-User-Subject", "sub-1")
		w.Header().Set("X-User-Issuer", "iss")
		w.Header().Set("X-Project-Audience", "project-health")
		w.Header().Set("X-Refreshed-Session-Handle", "v1.new")
		w.Header().Set("X-User-Email", "ignored@example.com")
	})

	got, err := c.Confirm(context.Background(), "v1.old")
	if err != nil {
		t.Fatalf("Confirm: %v", err)
	}
	if got != (Confirmed{Issuer: "iss", Subject: "sub-1", Audience: "project-health", RefreshedHandle: "v1.new"}) {
		t.Fatalf("got %+v", got)
	}
	call := (*calls)[0]
	if call.method != http.MethodGet || call.path != "/auth" || call.auth != "Bearer v1.old" || call.host != "health.nacfson.cloud" {
		t.Fatalf("unexpected call %+v", call)
	}
}

func TestConfirmErrorMapping(t *testing.T) {
	cases := []struct {
		name    string
		status  int
		headers map[string]string
		want    error
	}{
		{"unsigned", http.StatusUnauthorized, nil, ErrRejected},
		{"forbidden", http.StatusForbidden, nil, ErrRejected},
		{"keycloak down", http.StatusServiceUnavailable, nil, ErrUnavailable},
		{"unexpected", http.StatusInternalServerError, nil, ErrUnavailable},
		{"redirect is not followed", http.StatusFound, map[string]string{"Location": "/elsewhere"}, ErrUnavailable},
		{"missing subject", http.StatusOK, map[string]string{"X-User-Issuer": "iss"}, ErrRejected},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, _ := stubGateway(t, func(w http.ResponseWriter, _ *http.Request) {
				for k, v := range tc.headers {
					w.Header().Set(k, v)
				}
				w.WriteHeader(tc.status)
			})
			if _, err := c.Confirm(context.Background(), "h"); !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
		})
	}
}

func TestConfirmUnreachableGatewayIsUnavailable(t *testing.T) {
	srv := httptest.NewServer(http.NotFoundHandler())
	url := srv.URL
	srv.Close()
	c := NewClient(url, "health.nacfson.cloud", nil)
	if _, err := c.Confirm(context.Background(), "h"); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("err = %v, want ErrUnavailable", err)
	}
}

func TestRevokeMapping(t *testing.T) {
	cases := []struct {
		status int
		want   error
	}{
		{http.StatusOK, nil},
		{http.StatusFound, nil},
		{http.StatusBadRequest, ErrRejected},
		{http.StatusBadGateway, ErrUnavailable},
		{http.StatusServiceUnavailable, ErrUnavailable},
	}
	for _, tc := range cases {
		c, calls := stubGateway(t, func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(tc.status) })
		err := c.Revoke(context.Background(), "v1.h")
		if tc.want == nil && err != nil || tc.want != nil && !errors.Is(err, tc.want) {
			t.Fatalf("status %d: err = %v, want %v", tc.status, err, tc.want)
		}
		call := (*calls)[0]
		if call.method != http.MethodPost || call.path != "/auth/logout" || call.auth != "Bearer v1.h" {
			t.Fatalf("unexpected call %+v", call)
		}
	}
}

func TestUnconfiguredClientIsUnavailable(t *testing.T) {
	c := NewClient("", "health.nacfson.cloud", nil)
	if _, err := c.Confirm(context.Background(), "h"); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("err = %v", err)
	}
}
