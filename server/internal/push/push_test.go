package push

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"testing"

	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/store/memstore"
)

// fakeTransport answers with a status per endpoint and records payloads.
type fakeTransport struct {
	status   map[string]int
	err      map[string]error
	payloads []Notification
}

func (f *fakeTransport) Send(_ context.Context, sub *model.PushSubscription, payload []byte) (int, error) {
	var n Notification
	_ = json.Unmarshal(payload, &n)
	f.payloads = append(f.payloads, n)
	if e := f.err[sub.Endpoint]; e != nil {
		return 0, e
	}
	if s, ok := f.status[sub.Endpoint]; ok {
		return s, nil
	}
	return 201, nil
}

func TestSendToUserPrunesAndCounts(t *testing.T) {
	ctx := context.Background()
	st := memstore.New()
	u := &model.User{Username: "a", DisplayName: "A", PasswordHash: "x", ReminderDays: 127}
	if err := st.CreateUser(ctx, u); err != nil {
		t.Fatal(err)
	}
	for _, ep := range []string{"ok", "gone", "flaky", "boom"} {
		if err := st.UpsertPushSubscription(ctx, &model.PushSubscription{UserID: u.ID, Endpoint: ep, P256dh: "p", Auth: "a"}); err != nil {
			t.Fatal(err)
		}
	}
	ft := &fakeTransport{
		status: map[string]int{"gone": 410, "flaky": 500},
		err:    map[string]error{"boom": errors.New("dial")},
	}
	svc := NewServiceWithTransport(st, ft, "https://ow.example/", slog.Default())
	sent, err := svc.SendToUser(ctx, u.ID, Notification{Title: "t", Body: "b", URL: "/learn", Tag: "daily"})
	if err != nil {
		t.Fatal(err)
	}
	if sent != 1 {
		t.Fatalf("sent = %d", sent)
	}
	subs, _ := st.ListPushSubscriptions(ctx, u.ID)
	byEP := map[string]model.PushSubscription{}
	for _, s := range subs {
		byEP[s.Endpoint] = s
	}
	if _, ok := byEP["gone"]; ok {
		t.Error("410 subscription should be removed")
	}
	if byEP["flaky"].Failures != 1 || byEP["boom"].Failures != 1 {
		t.Errorf("failures not counted: %+v", byEP)
	}
	if byEP["ok"].LastUsedAt == nil || byEP["ok"].Failures != 0 {
		t.Errorf("success not recorded: %+v", byEP["ok"])
	}
	if len(ft.payloads) != 4 || ft.payloads[0].URL != "https://ow.example/learn" {
		t.Errorf("payloads: %+v", ft.payloads)
	}
}

func TestLoadOrCreateKeysIsStable(t *testing.T) {
	ctx := context.Background()
	st := memstore.New()
	k1, err := LoadOrCreateKeys(ctx, st)
	if err != nil {
		t.Fatal(err)
	}
	k2, err := LoadOrCreateKeys(ctx, st)
	if err != nil {
		t.Fatal(err)
	}
	if k1 != k2 || k1.Public == "" || k1.Private == "" {
		t.Fatalf("keys should persist: %+v vs %+v", k1, k2)
	}
}
