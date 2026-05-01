package web

import "github.com/ivanzzeth/symphony/aria/internal/orchestrator"

type TeamSnapshotProvider struct{}

func NewTeamSnapshotProvider() *TeamSnapshotProvider {
	return &TeamSnapshotProvider{}
}

func (p *TeamSnapshotProvider) Snapshot() orchestrator.StateSnapshot {
	return orchestrator.StateSnapshot{}
}
