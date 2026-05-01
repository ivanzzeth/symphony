package tui

import (
	"time"

	"github.com/ivanzzeth/symphony/aria/internal/orchestrator"
	"github.com/ivanzzeth/symphony/aria/internal/types"
)

type OrchestratorEventMsg struct {
	Event orchestrator.OrchestratorEvent
}

type TeamEventMsg struct {
	Event types.TeamEvent
}

type tickMsg time.Time
