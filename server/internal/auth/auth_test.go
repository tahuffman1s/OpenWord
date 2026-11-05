package auth

import (
	"strings"
	"testing"
)

func TestHashAndVerify(t *testing.T) {
	h, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(h, "$argon2id$v=19$m=65536,t=3,p=2$") {
		t.Fatalf("unexpected encoding: %s", h)
	}
	ok, err := VerifyPassword(h, "correct horse battery staple")
	if err != nil || !ok {
		t.Fatalf("verify: ok=%v err=%v", ok, err)
	}
	ok, err = VerifyPassword(h, "wrong")
	if err != nil || ok {
		t.Fatalf("wrong password accepted: ok=%v err=%v", ok, err)
	}
}

func TestHashIsSalted(t *testing.T) {
	a, _ := HashPassword("same")
	b, _ := HashPassword("same")
	if a == b {
		t.Fatal("two hashes of the same password should differ")
	}
}

func TestVerifyMalformed(t *testing.T) {
	for _, bad := range []string{"", "plain", "$argon2i$v=19$m=1,t=1,p=1$AAAA$AAAA", "$argon2id$v=18$m=1,t=1,p=1$AAAA$AAAA", "$argon2id$v=19$m=0,t=1,p=1$AAAA$AAAA"} {
		ok, err := VerifyPassword(bad, "x")
		if ok || err == nil {
			t.Errorf("%q: expected error, got ok=%v err=%v", bad, ok, err)
		}
	}
}

func TestDummyHashVerifies(t *testing.T) {
	if _, err := VerifyPassword(DummyHash, "anything"); err != nil {
		t.Fatalf("dummy hash should be well-formed: %v", err)
	}
}

func TestToken(t *testing.T) {
	a, err := NewToken()
	if err != nil {
		t.Fatal(err)
	}
	b, _ := NewToken()
	if a == b || len(a) != 43 {
		t.Fatalf("bad tokens: %q %q", a, b)
	}
	if len(HashToken(a)) != 32 {
		t.Fatal("hash length")
	}
	if string(HashToken(a)) == string(HashToken(b)) {
		t.Fatal("hash collision")
	}
}
