package web

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/ivanzzeth/symphony/aria/internal/hub"
	"github.com/ivanzzeth/symphony/aria/internal/orchestrator"
)

var _ SnapshotProvider = (*TeamSnapshotProvider)(nil)

func TestTeamSnapshotProviderSnapshotReturnsEmptySnapshot(t *testing.T) {
	provider := NewTeamSnapshotProvider()
	snapshot := provider.Snapshot()

	assert.Equal(t, orchestrator.StateSnapshot{}, snapshot)
}

func TestNewServerWithTeamSnapshotProvider(t *testing.T) {
	source := make(chan WebEvent)
	h := hub.NewHub(source)
	provider := NewTeamSnapshotProvider()

	require.NotPanics(t, func() {
		srv := NewServer(":0", provider, h, nil)
		require.NotNil(t, srv)
		require.Equal(t, provider, srv.snapshotProvider)
	})
}
