package ratelimit

import (
	"testing"
	"time"
)

func TestLimiter(t *testing.T) {
	l := New(60, 3) // 1/s, burst 3
	now := time.Unix(1000, 0)
	l.now = func() time.Time { return now }

	for i := 0; i < 3; i++ {
		if !l.Allow("a") {
			t.Fatalf("request %d should pass", i)
		}
	}
	if l.Allow("a") {
		t.Fatal("4th request should be limited")
	}
	if !l.Allow("b") {
		t.Fatal("other key should be independent")
	}
	now = now.Add(2 * time.Second)
	if !l.Allow("a") || !l.Allow("a") {
		t.Fatal("refill after 2s should allow 2")
	}
	if l.Allow("a") {
		t.Fatal("3rd after refill should be limited")
	}
	now = now.Add(time.Hour)
	for i := 0; i < 3; i++ {
		if !l.Allow("a") {
			t.Fatal("burst should be capped and refilled")
		}
	}
	if l.Allow("a") {
		t.Fatal("burst cap exceeded")
	}
}

func TestGC(t *testing.T) {
	l := New(60, 1)
	now := time.Unix(1000, 0)
	l.now = func() time.Time { return now }
	l.Allow("old")
	now = now.Add(20 * time.Minute)
	l.Allow("new")
	if _, ok := l.buckets["old"]; ok {
		t.Fatal("stale bucket should be collected")
	}
}
