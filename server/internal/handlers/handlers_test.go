package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tahuffman1s/openword/server/internal/config"
	"github.com/tahuffman1s/openword/server/internal/push"
	"github.com/tahuffman1s/openword/server/internal/store/memstore"
)

// fakePush records notifications and reports one delivery per subscription.
type fakePush struct {
	mu   sync.Mutex
	st   *memstore.Store
	sent []push.Notification
}

func (f *fakePush) SendToUser(ctx context.Context, userID string, n push.Notification) (int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, n)
	subs, _ := f.st.ListPushSubscriptions(ctx, userID)
	return len(subs), nil
}

// env is one test server with helpers.
type env struct {
	t     *testing.T
	st    *memstore.Store
	srv   *Server
	h     http.Handler
	push  *fakePush
	now   time.Time
	calls int
}

func newEnv(t *testing.T, invite string) *env {
	t.Helper()
	st := memstore.New()
	fp := &fakePush{st: st}
	cfg := &config.Config{Listen: ":0", InviteCode: invite, TrustProxy: true, PublicURL: "https://ow.example"}
	srv := New(st, cfg, fp, "VAPID_PUBLIC", slog.New(slog.NewTextHandler(io.Discard, nil)))
	e := &env{t: t, st: st, srv: srv, push: fp, now: time.Date(2026, 3, 10, 12, 0, 0, 0, time.UTC)}
	srv.now = func() time.Time { return e.now }
	e.h = srv.Routes()
	return e
}

type resp struct {
	code    int
	body    map[string]any
	raw     []byte
	headers http.Header
	cookies []*http.Cookie
}

// do performs a JSON request. token, if set, is sent as a Bearer header.
func (e *env) do(method, path string, body any, token string) resp {
	e.t.Helper()
	var rd io.Reader
	ct := ""
	switch b := body.(type) {
	case nil:
	case []byte:
		rd = bytes.NewReader(b)
		ct = "application/json"
	case string:
		rd = strings.NewReader(b)
		ct = "application/json"
	default:
		js, _ := json.Marshal(b)
		rd = bytes.NewReader(js)
		ct = "application/json"
	}
	req := httptest.NewRequest(method, path, rd)
	req.RemoteAddr = fmt.Sprintf("10.0.0.%d:1234", 1+e.calls%200)
	e.calls++
	req.Header.Set("X-Forwarded-For", "203.0.113.7")
	if ct != "" {
		req.Header.Set("Content-Type", ct)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	out := resp{code: rec.Code, raw: rec.Body.Bytes(), headers: rec.Header(), cookies: rec.Result().Cookies()}
	if strings.HasPrefix(rec.Header().Get("Content-Type"), "application/json") && len(out.raw) > 0 {
		_ = json.Unmarshal(out.raw, &out.body)
	}
	return out
}

// register creates a user and returns their bearer token.
func (e *env) register(username string) string {
	e.t.Helper()
	r := e.do("POST", "/api/auth/register", map[string]any{
		"username": username, "password": "password123", "displayName": strings.ToUpper(username),
	}, "")
	if r.code != 201 {
		e.t.Fatalf("register %s: %d %s", username, r.code, r.raw)
	}
	return r.body["token"].(string)
}

func (e *env) userID(token string) string {
	e.t.Helper()
	r := e.do("GET", "/api/me", nil, token)
	if r.code != 200 {
		e.t.Fatalf("me: %d %s", r.code, r.raw)
	}
	return r.body["user"].(map[string]any)["id"].(string)
}

func (e *env) befriend(a, b string) {
	e.t.Helper()
	ub := e.do("GET", "/api/me", nil, b).body["user"].(map[string]any)["username"].(string)
	r := e.do("POST", "/api/friends/requests", map[string]any{"username": ub}, a)
	if r.code != 201 {
		e.t.Fatalf("request: %d %s", r.code, r.raw)
	}
	id := r.body["request"].(map[string]any)["id"].(string)
	r = e.do("POST", "/api/friends/requests/"+id+"/accept", nil, b)
	if r.code != 200 {
		e.t.Fatalf("accept: %d %s", r.code, r.raw)
	}
}

func (e *env) learn(token, day string) {
	e.t.Helper()
	r := e.do("POST", "/api/activity", map[string]any{"day": day, "kind": "learn"}, token)
	if r.code != 200 {
		e.t.Fatalf("activity: %d %s", r.code, r.raw)
	}
}

func want(t *testing.T, r resp, code int, errCode string) {
	t.Helper()
	if r.code != code {
		t.Fatalf("status %d, want %d: %s", r.code, code, r.raw)
	}
	if errCode != "" && r.body["error"] != errCode {
		t.Fatalf("error %v, want %s: %s", r.body["error"], errCode, r.raw)
	}
}

// --- tests ----------------------------------------------------------------------

func TestRegisterLoginLogout(t *testing.T) {
	e := newEnv(t, "")
	r := e.do("POST", "/api/auth/register", map[string]any{"username": "Alice", "password": "password123", "email": "Alice@Example.com"}, "")
	want(t, r, 201, "")
	user := r.body["user"].(map[string]any)
	if user["username"] != "alice" || user["displayName"] != "alice" || user["email"] != "alice@example.com" || user["avatarUrl"] != nil {
		t.Fatalf("user: %v", user)
	}
	var cookie *http.Cookie
	for _, c := range r.cookies {
		if c.Name == SessionCookie {
			cookie = c
		}
	}
	if cookie == nil || !cookie.HttpOnly || cookie.Path != "/" || cookie.SameSite != http.SameSiteLaxMode || cookie.Secure {
		t.Fatalf("cookie: %+v", cookie)
	}

	// Cookie auth works too.
	req := httptest.NewRequest("GET", "/api/me", nil)
	req.AddCookie(cookie)
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	if rec.Code != 200 {
		t.Fatalf("cookie auth: %d", rec.Code)
	}

	// Secure cookie behind an HTTPS proxy.
	req = httptest.NewRequest("POST", "/api/auth/login", strings.NewReader(`{"username":"alice","password":"password123"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Forwarded-Proto", "https")
	rec = httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	if rec.Code != 200 {
		t.Fatalf("login: %d %s", rec.Code, rec.Body)
	}
	if cs := rec.Result().Cookies(); len(cs) == 0 || !cs[0].Secure {
		t.Fatalf("expected Secure cookie behind https proxy: %+v", cs)
	}

	want(t, e.do("POST", "/api/auth/register", map[string]any{"username": "alice", "password": "password123"}, ""), 409, "username_taken")
	want(t, e.do("POST", "/api/auth/register", map[string]any{"username": "bob", "password": "password123", "email": "alice@example.com"}, ""), 409, "email_taken")
	want(t, e.do("POST", "/api/auth/register", map[string]any{"username": "ab", "password": "password123"}, ""), 400, "validation")
	want(t, e.do("POST", "/api/auth/register", map[string]any{"username": "bob", "password": "short"}, ""), 400, "validation")
	want(t, e.do("POST", "/api/auth/register", "{not json", ""), 400, "validation")

	// Login by email, wrong password, unknown user.
	r = e.do("POST", "/api/auth/login", map[string]any{"username": "ALICE@example.com", "password": "password123"}, "")
	want(t, r, 200, "")
	token := r.body["token"].(string)
	want(t, e.do("POST", "/api/auth/login", map[string]any{"username": "alice", "password": "nope"}, ""), 401, "bad_credentials")
	want(t, e.do("POST", "/api/auth/login", map[string]any{"username": "nobody", "password": "password123"}, ""), 401, "bad_credentials")

	want(t, e.do("GET", "/api/me", nil, token), 200, "")
	want(t, e.do("POST", "/api/auth/logout", nil, token), 204, "")
	want(t, e.do("GET", "/api/me", nil, token), 401, "unauthorized")
	want(t, e.do("GET", "/api/me", nil, ""), 401, "unauthorized")
	want(t, e.do("GET", "/api/nope", nil, ""), 404, "not_found")
}

func TestInviteCode(t *testing.T) {
	e := newEnv(t, "secret")
	want(t, e.do("POST", "/api/auth/register", map[string]any{"username": "alice", "password": "password123"}, ""), 403, "invite_required")
	want(t, e.do("POST", "/api/auth/register", map[string]any{"username": "alice", "password": "password123", "inviteCode": "wrong"}, ""), 403, "invite_required")
	want(t, e.do("POST", "/api/auth/register", map[string]any{"username": "alice", "password": "password123", "inviteCode": "secret"}, ""), 201, "")
}

func TestSessionSlidingExpiry(t *testing.T) {
	e := newEnv(t, "")
	tok := e.register("alice")
	e.now = e.now.Add(2 * 24 * time.Hour)
	r := e.do("GET", "/api/me", nil, tok)
	want(t, r, 200, "")
	refreshed := false
	for _, c := range r.cookies {
		if c.Name == SessionCookie && c.Value == tok {
			refreshed = true
		}
	}
	if !refreshed {
		t.Fatal("expected cookie to be re-issued after a day")
	}
	e.now = e.now.Add(91 * 24 * time.Hour)
	want(t, e.do("GET", "/api/me", nil, tok), 401, "unauthorized")
}

func TestRateLimit(t *testing.T) {
	e := newEnv(t, "")
	var last resp
	for i := 0; i < 21; i++ {
		last = e.do("POST", "/api/auth/login", map[string]any{"username": "x", "password": "password123"}, "")
	}
	want(t, last, 429, "rate_limited")
	// Different forwarded IP is independent.
	req := httptest.NewRequest("POST", "/api/auth/login", strings.NewReader(`{"username":"x","password":"password123"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Forwarded-For", "198.51.100.9, 10.0.0.1")
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	if rec.Code != 401 {
		t.Fatalf("other ip should not be limited: %d", rec.Code)
	}
}

func TestMePatchPasswordDelete(t *testing.T) {
	e := newEnv(t, "")
	tok := e.register("alice")
	r := e.do("PATCH", "/api/me", map[string]any{
		"displayName": " Alice W ", "bio": "hi", "email": "a@b.co", "reminderTime": "07:30",
		"reminderTz": "Europe/London", "reminderDays": 31, "reminderOnlyIfUndone": false, "friendReminders": false,
	}, tok)
	want(t, r, 200, "")
	settings := r.body["settings"].(map[string]any)
	if settings["reminderTime"] != "07:30" || settings["reminderTz"] != "Europe/London" || settings["reminderDays"] != float64(31) ||
		settings["reminderOnlyIfUndone"] != false || settings["friendReminders"] != false {
		t.Fatalf("settings: %v", settings)
	}
	if r.body["user"].(map[string]any)["displayName"] != "Alice W" {
		t.Fatalf("user: %v", r.body["user"])
	}
	// Clear with null; leave the rest alone.
	r = e.do("PATCH", "/api/me", `{"email":null,"reminderTime":null}`, tok)
	want(t, r, 200, "")
	if r.body["user"].(map[string]any)["email"] != nil || r.body["settings"].(map[string]any)["reminderTime"] != nil ||
		r.body["settings"].(map[string]any)["reminderTz"] != "Europe/London" {
		t.Fatalf("after null patch: %s", r.raw)
	}
	want(t, e.do("PATCH", "/api/me", map[string]any{"reminderTz": "Nowhere/Land"}, tok), 400, "validation")
	want(t, e.do("PATCH", "/api/me", map[string]any{"reminderTime": "25:00"}, tok), 400, "validation")
	want(t, e.do("PATCH", "/api/me", map[string]any{"displayName": ""}, tok), 400, "validation")
	want(t, e.do("PATCH", "/api/me", map[string]any{"reminderDays": 200}, tok), 400, "validation")

	// Email conflict on patch.
	tok2 := e.register("bob")
	want(t, e.do("PATCH", "/api/me", map[string]any{"email": "a@b.co"}, tok), 200, "")
	want(t, e.do("PATCH", "/api/me", map[string]any{"email": "A@b.co"}, tok2), 409, "email_taken")

	// Password change.
	want(t, e.do("POST", "/api/me/password", map[string]any{"current": "wrong", "next": "newpassword1"}, tok), 401, "bad_credentials")
	want(t, e.do("POST", "/api/me/password", map[string]any{"current": "password123", "next": "short"}, tok), 400, "validation")
	want(t, e.do("POST", "/api/me/password", map[string]any{"current": "password123", "next": "newpassword1"}, tok), 204, "")
	want(t, e.do("POST", "/api/auth/login", map[string]any{"username": "alice", "password": "newpassword1"}, ""), 200, "")

	// GET /api/me counts.
	r = e.do("GET", "/api/me", nil, tok)
	want(t, r, 200, "")
	if r.body["streak"] != nil || r.body["counts"].(map[string]any)["friends"] != float64(0) {
		t.Fatalf("me: %s", r.raw)
	}

	// Delete account.
	want(t, e.do("DELETE", "/api/me", map[string]any{"password": "wrong"}, tok), 401, "bad_credentials")
	want(t, e.do("DELETE", "/api/me", map[string]any{"password": "newpassword1"}, tok), 204, "")
	want(t, e.do("GET", "/api/me", nil, tok), 401, "unauthorized")
	want(t, e.do("POST", "/api/auth/login", map[string]any{"username": "alice", "password": "newpassword1"}, ""), 401, "bad_credentials")
}

func pngBytes(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{uint8(x), uint8(y), 128, 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestAvatar(t *testing.T) {
	e := newEnv(t, "")
	tok := e.register("alice")
	id := e.userID(tok)

	want(t, e.do("GET", "/api/users/"+id+"/avatar", nil, ""), 404, "not_found")

	upload := func(body []byte, ct string) resp {
		req := httptest.NewRequest("PUT", "/api/me/avatar", bytes.NewReader(body))
		req.Header.Set("Content-Type", ct)
		req.Header.Set("Authorization", "Bearer "+tok)
		rec := httptest.NewRecorder()
		e.h.ServeHTTP(rec, req)
		out := resp{code: rec.Code, raw: rec.Body.Bytes(), headers: rec.Header()}
		_ = json.Unmarshal(out.raw, &out.body)
		return out
	}
	want(t, upload([]byte("nope"), "text/plain"), 400, "validation")
	want(t, upload([]byte("nope"), "image/png"), 400, "validation")
	r := upload(pngBytes(t, 40, 30), "image/png")
	want(t, r, 200, "")
	if r.body["avatarVersion"] != float64(1) || r.body["avatarUrl"] != "/api/users/"+id+"/avatar?v=1" {
		t.Fatalf("upload: %s", r.raw)
	}
	big := make([]byte, 4<<20+1)
	want(t, upload(big, "image/png"), 413, "too_large")

	r = e.do("GET", "/api/users/"+id+"/avatar?v=1", nil, "")
	if r.code != 200 || r.headers.Get("Content-Type") != "image/jpeg" || r.headers.Get("ETag") != `"1"` ||
		!strings.Contains(r.headers.Get("Cache-Control"), "immutable") {
		t.Fatalf("get avatar: %d %v", r.code, r.headers)
	}
	if img, _, err := image.Decode(bytes.NewReader(r.raw)); err != nil || img.Bounds().Dx() != 256 {
		t.Fatalf("avatar not a 256px jpeg: %v", err)
	}
	// Mismatched version is served but not immutable.
	r = e.do("GET", "/api/users/"+id+"/avatar?v=0", nil, "")
	if r.code != 200 || strings.Contains(r.headers.Get("Cache-Control"), "immutable") {
		t.Fatalf("stale version: %d %v", r.code, r.headers)
	}
	// Conditional GET.
	req := httptest.NewRequest("GET", "/api/users/"+id+"/avatar?v=1", nil)
	req.Header.Set("If-None-Match", `"1"`)
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	if rec.Code != 304 {
		t.Fatalf("expected 304, got %d", rec.Code)
	}
	// User JSON reflects it.
	r = e.do("GET", "/api/me", nil, tok)
	if r.body["user"].(map[string]any)["avatarVersion"] != float64(1) {
		t.Fatalf("me after avatar: %s", r.raw)
	}
	want(t, e.do("DELETE", "/api/me/avatar", nil, tok), 204, "")
	want(t, e.do("GET", "/api/users/"+id+"/avatar", nil, ""), 404, "not_found")
}

func TestFriendsFlow(t *testing.T) {
	e := newEnv(t, "")
	a := e.register("alice")
	b := e.register("bob")
	c := e.register("carol")
	bID := e.userID(b)

	// Validation.
	want(t, e.do("POST", "/api/friends/requests", map[string]any{"username": "alice"}, a), 400, "validation")
	want(t, e.do("POST", "/api/friends/requests", map[string]any{"username": "ghost"}, a), 404, "not_found")

	// Request + duplicate.
	r := e.do("POST", "/api/friends/requests", map[string]any{"username": "bob", "message": "hi!"}, a)
	want(t, r, 201, "")
	reqID := r.body["request"].(map[string]any)["id"].(string)
	want(t, e.do("POST", "/api/friends/requests", map[string]any{"username": "bob"}, a), 409, "already_requested")

	// Search shows relation.
	r = e.do("GET", "/api/users/search?q=b", nil, a)
	want(t, r, 200, "")
	users := r.body["users"].([]any)
	if len(users) != 1 || users[0].(map[string]any)["relation"] != "requested" {
		t.Fatalf("search: %s", r.raw)
	}
	r = e.do("GET", "/api/users/search?q=ALICE", nil, b)
	if r.body["users"].([]any)[0].(map[string]any)["relation"] != "incoming" {
		t.Fatalf("search incoming: %s", r.raw)
	}
	want(t, e.do("GET", "/api/users/search", nil, b), 400, "validation")

	// Lists.
	r = e.do("GET", "/api/friends/requests", nil, b)
	want(t, r, 200, "")
	in := r.body["incoming"].([]any)
	if len(in) != 1 || in[0].(map[string]any)["message"] != "hi!" || in[0].(map[string]any)["from"].(map[string]any)["username"] != "alice" {
		t.Fatalf("incoming: %s", r.raw)
	}
	r = e.do("GET", "/api/friends/requests", nil, a)
	if len(r.body["outgoing"].([]any)) != 1 || len(r.body["incoming"].([]any)) != 0 {
		t.Fatalf("outgoing: %s", r.raw)
	}
	r = e.do("GET", "/api/me", nil, b)
	if r.body["counts"].(map[string]any)["pendingRequests"] != float64(1) {
		t.Fatalf("pending count: %s", r.raw)
	}

	// Only the recipient may accept; only the sender may cancel.
	want(t, e.do("POST", "/api/friends/requests/"+reqID+"/accept", nil, a), 404, "not_found")
	want(t, e.do("DELETE", "/api/friends/requests/"+reqID, nil, b), 404, "not_found")
	r = e.do("POST", "/api/friends/requests/"+reqID+"/accept", nil, b)
	want(t, r, 200, "")
	if r.body["friend"].(map[string]any)["user"].(map[string]any)["username"] != "alice" {
		t.Fatalf("accept: %s", r.raw)
	}
	want(t, e.do("POST", "/api/friends/requests", map[string]any{"username": "bob"}, a), 409, "already_friends")

	// Crossing requests auto-accept.
	want(t, e.do("POST", "/api/friends/requests", map[string]any{"username": "alice"}, c), 201, "")
	r = e.do("POST", "/api/friends/requests", map[string]any{"username": "carol"}, a)
	want(t, r, 200, "")
	if r.body["friend"] == nil {
		t.Fatalf("auto-accept: %s", r.raw)
	}

	// Friend list sorted by display name, with streak data.
	r = e.do("GET", "/api/friends", nil, a)
	want(t, r, 200, "")
	friends := r.body["friends"].([]any)
	if len(friends) != 2 || friends[0].(map[string]any)["user"].(map[string]any)["username"] != "bob" ||
		friends[1].(map[string]any)["user"].(map[string]any)["username"] != "carol" {
		t.Fatalf("friends: %s", r.raw)
	}
	if friends[0].(map[string]any)["friendStreak"] != nil || friends[0].(map[string]any)["lastActiveDay"] != nil {
		t.Fatalf("expected empty streak data: %s", r.raw)
	}

	// Profile.
	r = e.do("GET", "/api/users/bob", nil, a)
	want(t, r, 200, "")
	if r.body["relation"] != "friend" || r.body["friendStreak"] == nil || r.body["user"].(map[string]any)["email"] != nil {
		t.Fatalf("profile: %s", r.raw)
	}
	if _, has := r.body["user"].(map[string]any)["email"]; has {
		t.Fatalf("public profile must not expose email: %s", r.raw)
	}
	r = e.do("GET", "/api/users/alice", nil, a)
	if r.body["relation"] != "self" {
		t.Fatalf("self profile: %s", r.raw)
	}
	want(t, e.do("GET", "/api/users/zed", nil, a), 404, "not_found")

	// Decline and cancel.
	d := e.register("dave")
	r = e.do("POST", "/api/friends/requests", map[string]any{"username": "dave"}, a)
	id := r.body["request"].(map[string]any)["id"].(string)
	want(t, e.do("POST", "/api/friends/requests/"+id+"/decline", nil, d), 204, "")
	r = e.do("POST", "/api/friends/requests", map[string]any{"username": "dave"}, a)
	id = r.body["request"].(map[string]any)["id"].(string)
	want(t, e.do("DELETE", "/api/friends/requests/"+id, nil, a), 204, "")
	want(t, e.do("DELETE", "/api/friends/requests/"+id, nil, a), 404, "not_found")

	// Unfriend.
	want(t, e.do("DELETE", "/api/friends/"+bID, nil, a), 204, "")
	want(t, e.do("DELETE", "/api/friends/"+bID, nil, a), 404, "not_found")
	r = e.do("GET", "/api/friends", nil, a)
	if len(r.body["friends"].([]any)) != 1 {
		t.Fatalf("after unfriend: %s", r.raw)
	}
}

func TestActivityAndStreaks(t *testing.T) {
	e := newEnv(t, "")
	a := e.register("alice")
	b := e.register("bob")
	e.befriend(a, b)

	// Validation: bad day, bad kind, out of range.
	want(t, e.do("POST", "/api/activity", map[string]any{"day": "2026-3-1", "kind": "learn"}, a), 400, "validation")
	want(t, e.do("POST", "/api/activity", map[string]any{"day": "2026-03-10", "kind": "nap"}, a), 400, "validation")
	want(t, e.do("POST", "/api/activity", map[string]any{"day": "2026-03-20", "kind": "learn"}, a), 400, "validation")
	want(t, e.do("POST", "/api/activity", map[string]any{"day": "2024-01-01", "kind": "learn"}, a), 400, "validation")
	want(t, e.do("POST", "/api/activity", map[string]any{"day": "2026-03-13", "kind": "learn"}, a), 200, "")

	// Upsert keeps the max count.
	r := e.do("POST", "/api/activity", map[string]any{"day": "2026-03-10", "kind": "read", "count": 3}, a)
	want(t, r, 200, "")
	r = e.do("POST", "/api/activity", map[string]any{"day": "2026-03-10", "kind": "read"}, a)
	if r.body["count"] != float64(3) {
		t.Fatalf("count: %s", r.raw)
	}

	// Streak: both learned 8th and 9th; only bob today → alice at risk.
	for _, d := range []string{"2026-03-08", "2026-03-09"} {
		e.learn(a, d)
		e.learn(b, d)
	}
	e.learn(b, "2026-03-10")

	r = e.do("GET", "/api/activity?from=2026-03-08&to=2026-03-10", nil, a)
	want(t, r, 200, "")
	days := r.body["days"].([]any)
	if len(days) != 3 || days[2].(map[string]any)["kinds"].(map[string]any)["read"] != float64(3) {
		t.Fatalf("activity: %s", r.raw)
	}
	want(t, e.do("GET", "/api/activity?from=2026-03-10&to=2026-03-01", nil, a), 400, "validation")

	r = e.do("GET", "/api/streaks", nil, a)
	want(t, r, 200, "")
	fs := r.body["friendStreaks"].([]any)[0].(map[string]any)
	if fs["current"] != float64(2) || fs["best"] != float64(2) || fs["lastDay"] != "2026-03-09" || fs["atRisk"] != true {
		t.Fatalf("friend streak: %s", r.raw)
	}
	e.learn(a, "2026-03-10")
	r = e.do("GET", "/api/streaks", nil, b)
	fs = r.body["friendStreaks"].([]any)[0].(map[string]any)
	if fs["current"] != float64(3) || fs["atRisk"] != false || fs["lastDay"] != "2026-03-10" {
		t.Fatalf("friend streak after learn: %s", r.raw)
	}

	// Friend list carries it too.
	r = e.do("GET", "/api/friends", nil, a)
	f := r.body["friends"].([]any)[0].(map[string]any)
	if f["friendStreak"].(map[string]any)["current"] != float64(3) || f["lastActiveDay"] != "2026-03-10" {
		t.Fatalf("friends streak: %s", r.raw)
	}

	// Own streak snapshot.
	want(t, e.do("PUT", "/api/streak", map[string]any{"current": -1}, a), 400, "validation")
	r = e.do("PUT", "/api/streak", map[string]any{"current": 5, "best": 3, "freezes": 1, "lastDay": "2026-03-10"}, a)
	want(t, r, 200, "")
	if r.body["streak"].(map[string]any)["best"] != float64(5) {
		t.Fatalf("best should be raised to current: %s", r.raw)
	}
	r = e.do("GET", "/api/friends", nil, b)
	if r.body["friends"].([]any)[0].(map[string]any)["streak"].(map[string]any)["current"] != float64(5) {
		t.Fatalf("friend sees snapshot: %s", r.raw)
	}
	r = e.do("GET", "/api/me", nil, a)
	if r.body["streak"].(map[string]any)["freezes"] != float64(1) {
		t.Fatalf("me streak: %s", r.raw)
	}
}

func TestActivityUsesUserTimezone(t *testing.T) {
	e := newEnv(t, "")
	a := e.register("alice")
	// Server clock: 2026-03-10 12:00 UTC. In Auckland that is the 11th, so
	// the 14th is 3 days ahead and allowed; in UTC it would be 4 and rejected.
	want(t, e.do("POST", "/api/activity", map[string]any{"day": "2026-03-14", "kind": "learn"}, a), 400, "validation")
	want(t, e.do("PATCH", "/api/me", map[string]any{"reminderTz": "Pacific/Auckland"}, a), 200, "")
	want(t, e.do("POST", "/api/activity", map[string]any{"day": "2026-03-14", "kind": "learn"}, a), 200, "")
}

func TestAchievementsAndFeed(t *testing.T) {
	e := newEnv(t, "")
	a := e.register("alice")
	b := e.register("bob")
	c := e.register("carol")
	e.befriend(a, b)

	want(t, e.do("POST", "/api/achievements", map[string]any{"key": "", "kind": "badge", "title": "x"}, a), 400, "validation")
	want(t, e.do("POST", "/api/achievements", map[string]any{"key": "k", "kind": "nope", "title": "x"}, a), 400, "validation")
	r := e.do("POST", "/api/achievements", map[string]any{"key": "first_lesson", "kind": "badge", "title": "First lesson", "earnedAt": "2026-03-01T10:00:00Z"}, a)
	want(t, r, 201, "")
	achID := r.body["achievement"].(map[string]any)["id"].(string)
	r = e.do("POST", "/api/achievements", map[string]any{"key": "first_lesson", "kind": "badge", "title": "Changed"}, a)
	want(t, r, 200, "")
	if r.body["achievement"].(map[string]any)["id"] != achID || r.body["achievement"].(map[string]any)["title"] != "First lesson" {
		t.Fatalf("idempotent post: %s", r.raw)
	}
	r = e.do("POST", "/api/achievements/batch", map[string]any{"achievements": []map[string]any{
		{"key": "first_lesson", "kind": "badge", "title": "dup"},
		{"key": "level_2", "kind": "level", "title": "Level 2", "earnedAt": "2026-03-05T10:00:00Z"},
		{"key": "streak_7", "kind": "streak", "title": "7 days", "earnedAt": "2026-03-09T10:00:00Z"},
	}}, a)
	want(t, r, 200, "")
	if r.body["created"] != float64(2) {
		t.Fatalf("batch: %s", r.raw)
	}
	want(t, e.do("POST", "/api/achievements", map[string]any{"key": "bob_1", "kind": "quiz", "title": "Quiz", "earnedAt": "2026-03-08T10:00:00Z"}, b), 201, "")
	want(t, e.do("POST", "/api/achievements", map[string]any{"key": "carol_1", "kind": "quiz", "title": "Hidden"}, c), 201, "")

	// Feed: self + friends, newest first, with paging.
	r = e.do("GET", "/api/feed?limit=2", nil, a)
	want(t, r, 200, "")
	items := r.body["items"].([]any)
	if len(items) != 2 || items[0].(map[string]any)["key"] != "streak_7" || items[1].(map[string]any)["key"] != "bob_1" ||
		items[0].(map[string]any)["mine"] != true || items[1].(map[string]any)["mine"] != false || r.body["nextBefore"] == nil {
		t.Fatalf("feed page 1: %s", r.raw)
	}
	r = e.do("GET", "/api/feed?limit=2&before="+r.body["nextBefore"].(string), nil, a)
	items = r.body["items"].([]any)
	if len(items) != 2 || items[0].(map[string]any)["key"] != "level_2" || items[1].(map[string]any)["key"] != "first_lesson" {
		t.Fatalf("feed page 2: %s", r.raw)
	}
	r = e.do("GET", "/api/feed", nil, a)
	for _, it := range r.body["items"].([]any) {
		if it.(map[string]any)["key"] == "carol_1" {
			t.Fatal("non-friend item leaked into feed")
		}
	}
	want(t, e.do("GET", "/api/feed?before=yesterday", nil, a), 400, "validation")

	// Cheers: friend may, stranger may not; toggling.
	r = e.do("POST", "/api/feed/"+achID+"/cheer", nil, b)
	want(t, r, 200, "")
	if r.body["cheers"] != float64(1) || r.body["cheered"] != true {
		t.Fatalf("cheer: %s", r.raw)
	}
	want(t, e.do("POST", "/api/feed/"+achID+"/cheer", nil, b), 200, "") // idempotent
	want(t, e.do("POST", "/api/feed/"+achID+"/cheer", nil, c), 404, "not_found")
	r = e.do("GET", "/api/feed", nil, b)
	for _, it := range r.body["items"].([]any) {
		m := it.(map[string]any)
		if m["id"] == achID && (m["cheers"] != float64(1) || m["cheered"] != true) {
			t.Fatalf("feed cheer state: %s", r.raw)
		}
	}
	r = e.do("DELETE", "/api/feed/"+achID+"/cheer", nil, b)
	if r.body["cheers"] != float64(0) || r.body["cheered"] != false {
		t.Fatalf("uncheer: %s", r.raw)
	}
	want(t, e.do("POST", "/api/feed/00000000-0000-4000-8000-000000000000/cheer", nil, b), 404, "not_found")

	// Profile shows the last achievements.
	r = e.do("GET", "/api/users/alice", nil, b)
	if len(r.body["achievements"].([]any)) != 3 {
		t.Fatalf("profile achievements: %s", r.raw)
	}
}

func TestPush(t *testing.T) {
	e := newEnv(t, "")
	r := e.do("GET", "/api/push/vapid", nil, "")
	want(t, r, 200, "")
	if r.body["publicKey"] != "VAPID_PUBLIC" {
		t.Fatalf("vapid: %s", r.raw)
	}
	a := e.register("alice")
	want(t, e.do("POST", "/api/push/subscriptions", map[string]any{"endpoint": "http://insecure", "keys": map[string]string{"p256dh": "p", "auth": "a"}}, a), 400, "validation")
	want(t, e.do("POST", "/api/push/subscriptions", map[string]any{"endpoint": "https://push.example/1", "keys": map[string]string{"p256dh": "", "auth": "a"}}, a), 400, "validation")
	sub := map[string]any{"endpoint": "https://push.example/1", "keys": map[string]string{"p256dh": "p", "auth": "a"}}
	want(t, e.do("POST", "/api/push/subscriptions", sub, a), 201, "")
	want(t, e.do("POST", "/api/push/subscriptions", sub, a), 201, "") // re-subscribe is fine
	r = e.do("POST", "/api/push/test", nil, a)
	want(t, r, 200, "")
	if r.body["sent"] != float64(1) || len(e.push.sent) != 1 || e.push.sent[0].Tag != "test" {
		t.Fatalf("test push: %s %+v", r.raw, e.push.sent)
	}
	want(t, e.do("DELETE", "/api/push/subscriptions", map[string]any{"endpoint": "https://push.example/1"}, a), 204, "")
	r = e.do("POST", "/api/push/test", nil, a)
	if r.body["sent"] != float64(0) {
		t.Fatalf("after unsubscribe: %s", r.raw)
	}
}

func TestBackup(t *testing.T) {
	e := newEnv(t, "")
	a := e.register("alice")
	want(t, e.do("GET", "/api/me/backup", nil, a), 404, "not_found")
	doc := `{"version":1,"progress":{"john":[1,2,3]}}`
	r := e.do("PUT", "/api/me/backup", doc, a)
	want(t, r, 200, "")
	if r.body["sizeBytes"] != float64(len(doc)) || r.body["updatedAt"] == nil {
		t.Fatalf("put backup: %s", r.raw)
	}
	r = e.do("GET", "/api/me/backup", nil, a)
	want(t, r, 200, "")
	if string(r.raw) != doc || r.headers.Get("X-Backup-Updated-At") == "" {
		t.Fatalf("get backup: %s", r.raw)
	}
	want(t, e.do("PUT", "/api/me/backup", `{"a":1} trailing`, a), 400, "validation")
	// Over the 4 MB limit.
	huge := `{"x":"` + strings.Repeat("a", 4<<20) + `"}`
	want(t, e.do("PUT", "/api/me/backup", huge, a), 413, "too_large")
	// A 1 MB+ body on an ordinary endpoint is rejected.
	want(t, e.do("POST", "/api/achievements", `{"key":"`+strings.Repeat("a", 1<<20)+`"}`, a), 400, "validation")
	want(t, e.do("DELETE", "/api/me/backup", nil, a), 204, "")
	want(t, e.do("GET", "/api/me/backup", nil, a), 404, "not_found")
}

func TestHealthz(t *testing.T) {
	e := newEnv(t, "")
	r := e.do("GET", "/healthz", nil, "")
	if r.code != 200 || string(r.raw) != "ok" {
		t.Fatalf("healthz: %d %s", r.code, r.raw)
	}
	e.st.PingErr = fmt.Errorf("down")
	if r := e.do("GET", "/healthz", nil, ""); r.code != 503 {
		t.Fatalf("healthz with dead db: %d", r.code)
	}
}

func TestDeleteUserCascades(t *testing.T) {
	e := newEnv(t, "")
	a := e.register("alice")
	b := e.register("bob")
	e.befriend(a, b)
	e.learn(a, "2026-03-10")
	want(t, e.do("POST", "/api/achievements", map[string]any{"key": "k", "kind": "badge", "title": "t"}, a), 201, "")
	want(t, e.do("DELETE", "/api/me", map[string]any{"password": "password123"}, a), 204, "")
	r := e.do("GET", "/api/friends", nil, b)
	if len(r.body["friends"].([]any)) != 0 {
		t.Fatalf("friendship should be gone: %s", r.raw)
	}
	r = e.do("GET", "/api/feed", nil, b)
	if len(r.body["items"].([]any)) != 0 {
		t.Fatalf("feed should be empty: %s", r.raw)
	}
}
