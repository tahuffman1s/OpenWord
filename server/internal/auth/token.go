package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
)

// TokenBytes is the entropy of a session token.
const TokenBytes = 32

// NewToken returns a fresh random session token, base64url-encoded
// without padding (43 characters).
func NewToken() (string, error) {
	b := make([]byte, TokenBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// HashToken returns the SHA-256 of a token; only this is stored.
func HashToken(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}
