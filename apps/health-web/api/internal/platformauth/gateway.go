// Package platformauth is health-web's client for the nacfson_pipeline
// platform sign-in gateway (identity/gateway:8080). It is the only code in
// health-web that talks to the gateway.
//
// Contract: specs/001-health-web-gateway-auth/contracts/gateway-consumer.md
// (pinned against nacfson_pipeline gateway/internal/auth at 913f03c).
package platformauth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/nacfson/nacfson_health/apps/health-web/api/internal/logx"
)

var (
	// ErrRejected means the gateway answered and refused the ticket or session.
	ErrRejected = errors.New("platformauth: rejected by gateway")
	// ErrUnavailable means the gateway could not give an answer (network error,
	// 5xx, or an unexpected response). Callers MUST fail closed.
	ErrUnavailable = errors.New("platformauth: gateway unavailable")
)

const (
	defaultTimeout   = 5 * time.Second
	defaultExpiresIn = 8 * time.Hour
	maxResponseBytes = 64 << 10
)

// Client calls the gateway's internal endpoints on behalf of one project host.
type Client struct {
	baseURL string
	appHost string
	http    *http.Client
}

// NewClient builds a client. baseURL is the gateway origin without "/auth"
// (e.g. "http://gateway.identity.svc:8080"); appHost is sent as
// X-Forwarded-Host so the gateway binds tickets and audiences to this project.
func NewClient(baseURL, appHost string, httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: defaultTimeout}
	}
	// Never follow redirects: every gateway answer is read as-is.
	clone := *httpClient
	clone.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	return &Client{
		baseURL: strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		appHost: strings.TrimSpace(appHost),
		http:    &clone,
	}
}

// Exchanged is the result of redeeming a one-time sign-in ticket.
type Exchanged struct {
	SessionHandle string
	Issuer        string
	Subject       string
	Audience      string
	ExpiresIn     time.Duration
}

// Confirmed is the result of confirming a session handle.
type Confirmed struct {
	Issuer   string
	Subject  string
	Audience string
	// RefreshedHandle is non-empty when the gateway renewed the session; the
	// caller must store it in place of the old handle.
	RefreshedHandle string
}

// Exchange redeems a one-time ticket: POST {base}/auth/exchange.
func (c *Client) Exchange(ctx context.Context, ticket string) (Exchanged, error) {
	ticket = strings.TrimSpace(ticket)
	if ticket == "" {
		return Exchanged{}, ErrRejected
	}
	body, err := json.Marshal(map[string]string{"ticket": ticket})
	if err != nil {
		return Exchanged{}, fmt.Errorf("%w: encode ticket: %v", ErrUnavailable, err)
	}
	req, err := c.newRequest(ctx, http.MethodPost, "/auth/exchange", bytes.NewReader(body))
	if err != nil {
		return Exchanged{}, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return Exchanged{}, fmt.Errorf("%w: exchange: %v", ErrUnavailable, err)
	}
	defer drain(resp)

	switch {
	case resp.StatusCode == http.StatusOK:
	case resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusBadRequest:
		return Exchanged{}, fmt.Errorf("%w: exchange status %d", ErrRejected, resp.StatusCode)
	default:
		return Exchanged{}, fmt.Errorf("%w: exchange status %d", ErrUnavailable, resp.StatusCode)
	}

	var payload struct {
		SessionHandle string `json:"session_handle"`
		Subject       string `json:"subject"`
		Issuer        string `json:"issuer"`
		Audience      string `json:"audience"`
		ExpiresIn     int    `json:"expires_in"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxResponseBytes)).Decode(&payload); err != nil {
		return Exchanged{}, fmt.Errorf("%w: decode exchange: %v", ErrUnavailable, err)
	}
	out := Exchanged{
		SessionHandle: strings.TrimSpace(payload.SessionHandle),
		Issuer:        strings.TrimSpace(payload.Issuer),
		Subject:       strings.TrimSpace(payload.Subject),
		Audience:      strings.TrimSpace(payload.Audience),
		ExpiresIn:     time.Duration(payload.ExpiresIn) * time.Second,
	}
	if out.SessionHandle == "" || out.Issuer == "" || out.Subject == "" {
		return Exchanged{}, fmt.Errorf("%w: exchange returned an incomplete identity", ErrRejected)
	}
	if out.ExpiresIn <= 0 {
		out.ExpiresIn = defaultExpiresIn
	}
	return out, nil
}

// Confirm checks a session handle: GET {base}/auth with Authorization: Bearer.
func (c *Client) Confirm(ctx context.Context, handle string) (Confirmed, error) {
	handle = strings.TrimSpace(handle)
	if handle == "" {
		return Confirmed{}, ErrRejected
	}
	req, err := c.newRequest(ctx, http.MethodGet, "/auth", nil)
	if err != nil {
		return Confirmed{}, err
	}
	req.Header.Set("Authorization", "Bearer "+handle)

	resp, err := c.http.Do(req)
	if err != nil {
		return Confirmed{}, fmt.Errorf("%w: confirm: %v", ErrUnavailable, err)
	}
	defer drain(resp)

	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusUnauthorized, http.StatusForbidden:
		return Confirmed{}, fmt.Errorf("%w: confirm status %d", ErrRejected, resp.StatusCode)
	default:
		return Confirmed{}, fmt.Errorf("%w: confirm status %d", ErrUnavailable, resp.StatusCode)
	}

	out := Confirmed{
		Issuer:          strings.TrimSpace(resp.Header.Get("X-User-Issuer")),
		Subject:         strings.TrimSpace(resp.Header.Get("X-User-Subject")),
		Audience:        strings.TrimSpace(resp.Header.Get("X-Project-Audience")),
		RefreshedHandle: strings.TrimSpace(resp.Header.Get("X-Refreshed-Session-Handle")),
	}
	if out.Issuer == "" || out.Subject == "" {
		return Confirmed{}, fmt.Errorf("%w: confirm returned an incomplete identity", ErrRejected)
	}
	return out, nil
}

// Revoke ends the platform session: POST {base}/auth/logout with the bearer
// handle. nil means the gateway confirmed revocation.
func (c *Client) Revoke(ctx context.Context, handle string) error {
	handle = strings.TrimSpace(handle)
	if handle == "" {
		return ErrRejected
	}
	req, err := c.newRequest(ctx, http.MethodPost, "/auth/logout", nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+handle)

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%w: revoke: %v", ErrUnavailable, err)
	}
	defer drain(resp)

	switch resp.StatusCode {
	case http.StatusOK, http.StatusFound:
		return nil
	case http.StatusUnauthorized, http.StatusBadRequest:
		return fmt.Errorf("%w: revoke status %d", ErrRejected, resp.StatusCode)
	default:
		return fmt.Errorf("%w: revoke status %d", ErrUnavailable, resp.StatusCode)
	}
}

func (c *Client) newRequest(ctx context.Context, method, path string, body io.Reader) (*http.Request, error) {
	if c.baseURL == "" {
		return nil, fmt.Errorf("%w: gateway URL is not configured", ErrUnavailable)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, body)
	if err != nil {
		return nil, fmt.Errorf("%w: build request: %v", ErrUnavailable, err)
	}
	req.Header.Set("Accept", "application/json")
	if c.appHost != "" {
		req.Header.Set("X-Forwarded-Host", c.appHost)
	}
	if tid := logx.TraceIDFromContext(ctx); tid != "" {
		req.Header.Set("traceparent", logx.FormatTraceparent(tid))
	}
	return req, nil
}

func drain(resp *http.Response) {
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, maxResponseBytes))
	_ = resp.Body.Close()
}
