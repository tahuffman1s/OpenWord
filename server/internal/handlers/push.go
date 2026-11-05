package handlers

import (
	"net/http"
	"strings"

	"github.com/tahuffman1s/openword/server/internal/httpx"
	"github.com/tahuffman1s/openword/server/internal/model"
	"github.com/tahuffman1s/openword/server/internal/push"
)

// GET /api/push/vapid (public)
func (s *Server) getVAPID(w http.ResponseWriter, r *http.Request) {
	httpx.JSON(w, http.StatusOK, map[string]string{"publicKey": s.vapidPublic})
}

type subscriptionRequest struct {
	Endpoint string `json:"endpoint"`
	Keys     struct {
		P256dh string `json:"p256dh"`
		Auth   string `json:"auth"`
	} `json:"keys"`
}

// POST /api/push/subscriptions — the PushSubscription.toJSON() shape.
func (s *Server) subscribePush(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	var req subscriptionRequest
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	req.Endpoint = strings.TrimSpace(req.Endpoint)
	if !strings.HasPrefix(req.Endpoint, "https://") || len(req.Endpoint) > 2048 {
		httpx.BadRequest(w, "endpoint must be an https URL")
		return
	}
	if req.Keys.P256dh == "" || req.Keys.Auth == "" || len(req.Keys.P256dh) > 512 || len(req.Keys.Auth) > 128 {
		httpx.BadRequest(w, "keys.p256dh and keys.auth are required")
		return
	}
	sub := &model.PushSubscription{
		UserID:    me.ID,
		Endpoint:  req.Endpoint,
		P256dh:    req.Keys.P256dh,
		Auth:      req.Keys.Auth,
		UserAgent: truncate(r.UserAgent(), 256),
	}
	if err := s.store.UpsertPushSubscription(r.Context(), sub); err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, map[string]any{"id": sub.ID, "createdAt": sub.CreatedAt.UTC()})
}

// DELETE /api/push/subscriptions {endpoint}
func (s *Server) unsubscribePush(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	var req struct {
		Endpoint string `json:"endpoint"`
	}
	if err := httpx.Decode(r, &req); err != nil {
		httpx.BadRequest(w, err.Error())
		return
	}
	if err := s.store.DeletePushSubscription(r.Context(), me.ID, strings.TrimSpace(req.Endpoint)); err != nil {
		httpx.Internal(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// POST /api/push/test
func (s *Server) testPush(w http.ResponseWriter, r *http.Request) {
	me := userFrom(r.Context())
	sent, err := s.push.SendToUser(r.Context(), me.ID, push.Notification{
		Title: "OpenWord",
		Body:  "Push notifications are working.",
		URL:   "/",
		Tag:   "test",
	})
	if err != nil {
		httpx.Internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"sent": sent})
}
