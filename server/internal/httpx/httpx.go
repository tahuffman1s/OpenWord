// Package httpx holds small helpers for JSON request/response handling and
// the API's error envelope.
package httpx

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
)

// ErrorBody is the JSON envelope for every error response.
type ErrorBody struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

// JSON writes v as a JSON response with the given status.
func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	enc := json.NewEncoder(w)
	if err := enc.Encode(v); err != nil {
		slog.Warn("write json", "err", err)
	}
}

// Error writes the standard error envelope.
func Error(w http.ResponseWriter, status int, code, message string) {
	JSON(w, status, ErrorBody{Error: code, Message: message})
}

// Common error writers.
func BadRequest(w http.ResponseWriter, msg string) {
	Error(w, http.StatusBadRequest, "validation", msg)
}
func NotFound(w http.ResponseWriter, msg string) { Error(w, http.StatusNotFound, "not_found", msg) }
func Unauthorized(w http.ResponseWriter) {
	Error(w, http.StatusUnauthorized, "unauthorized", "Sign in to continue.")
}
func Forbidden(w http.ResponseWriter, msg string) { Error(w, http.StatusForbidden, "forbidden", msg) }
func Internal(w http.ResponseWriter, err error) {
	slog.Error("internal error", "err", err)
	Error(w, http.StatusInternalServerError, "internal", "Something went wrong on our side.")
}

// Decode reads a JSON body into v. Unknown fields are ignored so clients may
// evolve independently; trailing garbage is rejected. The body must already
// be wrapped in http.MaxBytesReader by the body-limit middleware.
func Decode(r *http.Request, v any) error {
	ct := r.Header.Get("Content-Type")
	if ct != "" && !strings.HasPrefix(ct, "application/json") {
		return errors.New("Content-Type must be application/json")
	}
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(v); err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			return errors.New("request body is too large")
		}
		if errors.Is(err, io.EOF) {
			return errors.New("request body is empty")
		}
		return errors.New("request body is not valid JSON: " + err.Error())
	}
	if dec.More() {
		return errors.New("request body has trailing data")
	}
	return nil
}

// IsTooLarge reports whether err came from http.MaxBytesReader.
func IsTooLarge(err error) bool {
	var maxErr *http.MaxBytesError
	return errors.As(err, &maxErr)
}
