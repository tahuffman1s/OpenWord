// Package auth implements password hashing and session token handling.
package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// Argon2id parameters. 64 MB / 3 passes / 2 lanes takes ~150 ms on a Pi 4
// and is the OWASP-recommended profile for memory-limited hosts.
const (
	argonMemory  = 64 * 1024 // KiB
	argonTime    = 3
	argonThreads = 2
	argonKeyLen  = 32
	argonSaltLen = 16
)

// ErrBadHash is returned when a stored hash cannot be parsed.
var ErrBadHash = errors.New("malformed password hash")

// HashPassword returns a PHC-formatted argon2id string:
//
//	$argon2id$v=19$m=65536,t=3,p=2$<salt>$<hash>
func HashPassword(password string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	return hashWithSalt(password, salt), nil
}

func hashWithSalt(password string, salt []byte) string {
	key := argon2.IDKey([]byte(password), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	enc := base64.RawStdEncoding
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemory, argonTime, argonThreads,
		enc.EncodeToString(salt), enc.EncodeToString(key))
}

// VerifyPassword reports whether password matches the encoded hash. It
// always performs the full argon2 computation (even on a malformed hash)
// so timing does not leak which usernames exist.
func VerifyPassword(encoded, password string) (bool, error) {
	params, salt, want, err := decodeHash(encoded)
	if err != nil {
		// Burn the same CPU as a real comparison, then fail.
		_ = argon2.IDKey([]byte(password), make([]byte, argonSaltLen), argonTime, argonMemory, argonThreads, argonKeyLen)
		return false, err
	}
	got := argon2.IDKey([]byte(password), salt, params.time, params.memory, params.threads, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1, nil
}

// DummyHash is a valid hash of a random password, used so that login
// attempts against unknown usernames cost the same as real ones.
var DummyHash = func() string {
	salt := make([]byte, argonSaltLen)
	_, _ = rand.Read(salt)
	return hashWithSalt("dummy-password-for-timing", salt)
}()

type argonParams struct {
	memory  uint32
	time    uint32
	threads uint8
}

func decodeHash(encoded string) (argonParams, []byte, []byte, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[0] != "" || parts[1] != "argon2id" {
		return argonParams{}, nil, nil, ErrBadHash
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return argonParams{}, nil, nil, ErrBadHash
	}
	var p argonParams
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &p.memory, &p.time, &p.threads); err != nil {
		return argonParams{}, nil, nil, ErrBadHash
	}
	if p.memory == 0 || p.time == 0 || p.threads == 0 {
		return argonParams{}, nil, nil, ErrBadHash
	}
	enc := base64.RawStdEncoding
	salt, err := enc.DecodeString(parts[4])
	if err != nil {
		return argonParams{}, nil, nil, ErrBadHash
	}
	hash, err := enc.DecodeString(parts[5])
	if err != nil || len(hash) == 0 {
		return argonParams{}, nil, nil, ErrBadHash
	}
	return p, salt, hash, nil
}
