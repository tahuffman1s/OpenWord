// Package push sends Web Push notifications and manages the VAPID key pair.
package push

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	webpush "github.com/SherClockHolmes/webpush-go"

	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store"
)

// Notification is the JSON payload the service worker receives.
type Notification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
	URL   string `json:"url"` // where a tap should navigate
	Tag   string `json:"tag"` // collapses repeated notifications
}

// Keys is a VAPID key pair, base64url-encoded as webpush-go expects.
type Keys struct {
	Public  string
	Private string
}

// Server-key names in the server_keys table.
const (
	keyPublic  = "vapid_public"
	keyPrivate = "vapid_private"
)

// LoadOrCreateKeys returns the stored VAPID pair, generating and storing one
// on first start. Both halves are written together so a concurrent starter
// can never see a mismatched pair.
func LoadOrCreateKeys(ctx context.Context, st store.Store) (Keys, error) {
	priv, pub, err := webpush.GenerateVAPIDKeys()
	if err != nil {
		return Keys{}, fmt.Errorf("generate vapid keys: %w", err)
	}
	// The private key is claimed first; whoever wins also owns the public
	// key slot because the pair is stored as one JSON value.
	pairJSON, _ := json.Marshal(Keys{Public: pub, Private: priv})
	stored, err := st.GetOrSetServerKey(ctx, keyPrivate, string(pairJSON))
	if err != nil {
		return Keys{}, err
	}
	var k Keys
	if err := json.Unmarshal([]byte(stored), &k); err != nil || k.Public == "" || k.Private == "" {
		return Keys{}, fmt.Errorf("stored vapid key is malformed")
	}
	// Mirror the public half under its own name for operators poking at
	// the table; harmless if it already exists.
	if _, err := st.GetOrSetServerKey(ctx, keyPublic, k.Public); err != nil {
		return Keys{}, err
	}
	return k, nil
}

// Transport performs one push delivery. It is an interface so tests and the
// scheduler tests can observe sends without talking to a push service.
type Transport interface {
	// Send delivers payload to sub and returns the push service's HTTP status.
	Send(ctx context.Context, sub *model.PushSubscription, payload []byte) (int, error)
}

// webpushTransport is the real Transport backed by webpush-go.
type webpushTransport struct {
	keys    Keys
	subject string
	client  *http.Client
}

func (t *webpushTransport) Send(ctx context.Context, sub *model.PushSubscription, payload []byte) (int, error) {
	resp, err := webpush.SendNotificationWithContext(ctx, payload, &webpush.Subscription{
		Endpoint: sub.Endpoint,
		Keys:     webpush.Keys{P256dh: sub.P256dh, Auth: sub.Auth},
	}, &webpush.Options{
		HTTPClient:      t.client,
		Subscriber:      t.subject,
		VAPIDPublicKey:  t.keys.Public,
		VAPIDPrivateKey: t.keys.Private,
		TTL:             6 * 3600, // a reminder is useless after a few hours
		Urgency:         webpush.UrgencyNormal,
	})
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	return resp.StatusCode, nil
}

// Service fans a notification out to all of a user's subscriptions and
// keeps the subscription table healthy.
type Service struct {
	store     store.Store
	transport Transport
	baseURL   string
	log       *slog.Logger
	now       func() time.Time
}

// maxFailures is the number of consecutive non-gone failures after which a
// subscription is dropped anyway, so a permanently broken endpoint does not
// cost a request every day forever.
const maxFailures = 20

// NewService builds a Service that sends with the real Web Push transport.
// baseURL, if non-empty, makes payload URLs absolute.
func NewService(st store.Store, keys Keys, subject, baseURL string, log *slog.Logger) *Service {
	return &Service{
		store: st,
		transport: &webpushTransport{
			keys:    keys,
			subject: subject,
			client:  &http.Client{Timeout: 15 * time.Second},
		},
		baseURL: strings.TrimRight(baseURL, "/"),
		log:     log,
		now:     time.Now,
	}
}

// NewServiceWithTransport is NewService with an injected Transport (tests).
func NewServiceWithTransport(st store.Store, t Transport, baseURL string, log *slog.Logger) *Service {
	return &Service{store: st, transport: t, baseURL: strings.TrimRight(baseURL, "/"), log: log, now: time.Now}
}

// SendToUser delivers n to every subscription of userID. It returns how many
// deliveries the push service accepted. Subscriptions answering 404 or 410
// are deleted; other failures are counted.
func (s *Service) SendToUser(ctx context.Context, userID string, n Notification) (int, error) {
	subs, err := s.store.ListPushSubscriptions(ctx, userID)
	if err != nil {
		return 0, err
	}
	if n.URL != "" && s.baseURL != "" && strings.HasPrefix(n.URL, "/") {
		n.URL = s.baseURL + n.URL
	}
	payload, err := json.Marshal(n)
	if err != nil {
		return 0, err
	}
	sent := 0
	for i := range subs {
		sub := &subs[i]
		status, err := s.transport.Send(ctx, sub, payload)
		switch {
		case err != nil:
			s.log.Warn("push send failed", "user", userID, "sub", sub.ID, "err", err)
			s.fail(ctx, sub)
		case status == http.StatusNotFound || status == http.StatusGone:
			s.log.Info("push subscription gone, removing", "user", userID, "sub", sub.ID, "status", status)
			_ = s.store.DeletePushSubscriptionByID(ctx, sub.ID)
		case status >= 200 && status < 300:
			sent++
			_ = s.store.RecordPushResult(ctx, sub.ID, true, s.now())
		default:
			s.log.Warn("push service rejected", "user", userID, "sub", sub.ID, "status", status)
			s.fail(ctx, sub)
		}
		if ctx.Err() != nil {
			return sent, ctx.Err()
		}
	}
	return sent, nil
}

func (s *Service) fail(ctx context.Context, sub *model.PushSubscription) {
	_ = s.store.RecordPushResult(ctx, sub.ID, false, s.now())
	if sub.Failures+1 >= maxFailures {
		s.log.Info("push subscription dropped after repeated failures", "sub", sub.ID)
		_ = s.store.DeletePushSubscriptionByID(ctx, sub.ID)
	}
}

// ErrNoSubscriptions can be used by callers that want to distinguish "no
// devices" from "sent nowhere".
var ErrNoSubscriptions = errors.New("no push subscriptions")
