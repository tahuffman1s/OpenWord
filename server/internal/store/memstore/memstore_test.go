package memstore

import (
	"testing"

	"github.com/tahuffman1s/openword/server/internal/store"
	"github.com/tahuffman1s/openword/server/internal/store/storetest"
)

func TestConformance(t *testing.T) {
	storetest.Run(t, func(t *testing.T) store.Store { return New() })
}
