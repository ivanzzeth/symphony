package orchestrator

import (
	"fmt"
	"testing"
	"time"

	"github.com/ivanzzeth/symphony/aria/internal/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type issueStateTransition struct {
	from types.IssueState
	to   types.IssueState
}

func TestTransitionIssueState_AllTransitions(t *testing.T) {
	issueStates := []types.IssueState{
		types.Unclaimed,
		types.Claimed,
		types.Running,
		types.RetryQueued,
		types.Released,
	}

	validTransitions := map[issueStateTransition]struct{}{
		{from: types.Unclaimed, to: types.Claimed}:    {},
		{from: types.Claimed, to: types.Running}:      {},
		{from: types.Running, to: types.RetryQueued}:  {},
		{from: types.RetryQueued, to: types.Claimed}:  {},
		{from: types.Unclaimed, to: types.Released}:   {},
		{from: types.Claimed, to: types.Released}:     {},
		{from: types.Running, to: types.Released}:     {},
		{from: types.RetryQueued, to: types.Released}: {},
		{from: types.Released, to: types.Released}:    {},
	}

	for _, from := range issueStates {
		from := from
		for _, to := range issueStates {
			to := to
			t.Run(fmt.Sprintf("%s_to_%s", from, to), func(t *testing.T) {
				err := TransitionIssueState(from, to)
				_, isValid := validTransitions[issueStateTransition{from: from, to: to}]

				if isValid {
					require.NoError(t, err)
					return
				}

				require.Error(t, err)
				var invalidTransitionErr *InvalidTransitionError
				require.ErrorAs(t, err, &invalidTransitionErr)
				assert.Equal(t, from, invalidTransitionErr.From)
				assert.Equal(t, to, invalidTransitionErr.To)
			})
		}
	}
}

type runPhaseTransition struct {
	from types.RunPhase
	to   types.RunPhase
}

func TestTransitionRunPhase_AllTransitions(t *testing.T) {
	runPhases := []types.RunPhase{
		types.PreparingWorkspace,
		types.BuildingPrompt,
		types.LaunchingAgentProcess,
		types.InitializingSession,
		types.StreamingTurn,
		types.Finishing,
		types.Succeeded,
		types.Failed,
		types.TimedOut,
		types.Stalled,
		types.CanceledByReconciliation,
	}

	activePhases := []types.RunPhase{
		types.PreparingWorkspace,
		types.BuildingPrompt,
		types.LaunchingAgentProcess,
		types.InitializingSession,
		types.StreamingTurn,
		types.Finishing,
	}

	failurePhases := []types.RunPhase{
		types.Failed,
		types.TimedOut,
		types.Stalled,
		types.CanceledByReconciliation,
	}

	validTransitions := map[runPhaseTransition]struct{}{
		{from: types.PreparingWorkspace, to: types.BuildingPrompt}:         {},
		{from: types.BuildingPrompt, to: types.LaunchingAgentProcess}:      {},
		{from: types.LaunchingAgentProcess, to: types.InitializingSession}: {},
		{from: types.InitializingSession, to: types.StreamingTurn}:         {},
		{from: types.StreamingTurn, to: types.Finishing}:                   {},
		{from: types.Finishing, to: types.Succeeded}:                       {},
	}

	for _, from := range activePhases {
		for _, to := range failurePhases {
			validTransitions[runPhaseTransition{from: from, to: to}] = struct{}{}
		}
	}

	for _, from := range runPhases {
		from := from
		for _, to := range runPhases {
			to := to
			t.Run(fmt.Sprintf("%s_to_%s", from, to), func(t *testing.T) {
				err := TransitionRunPhase(from, to)
				_, isValid := validTransitions[runPhaseTransition{from: from, to: to}]

				if isValid {
					require.NoError(t, err)
					return
				}

				require.Error(t, err)
				var invalidTransitionErr *InvalidTransitionError
				require.ErrorAs(t, err, &invalidTransitionErr)
				assert.Equal(t, from, invalidTransitionErr.From)
				assert.Equal(t, to, invalidTransitionErr.To)
			})
		}
	}
}

func TestCalculateBackoff(t *testing.T) {
	tests := []struct {
		name    string
		issueID string
		attempt int
		maxMs   int
	}{
		{name: "continuation_retry_uses_fixed_delay", issueID: "issue-1", attempt: 0, maxMs: 300_000},
		{name: "attempt_1_uses_base_backoff_with_jitter", issueID: "issue-1", attempt: 1, maxMs: 300_000},
		{name: "attempt_2_uses_exponential_backoff_with_jitter", issueID: "issue-1", attempt: 2, maxMs: 300_000},
		{name: "attempt_3_uses_exponential_backoff_with_jitter", issueID: "issue-1", attempt: 3, maxMs: 300_000},
		{name: "backoff_caps_at_max", issueID: "issue-1", attempt: 10, maxMs: 300_000},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			delayMs := CalculateBackoff(tt.issueID, tt.attempt, tt.maxMs)

			if tt.attempt <= 0 {
				assert.Equal(t, 1_000, delayMs)
				return
			}

			baseDelay := expectedFailureBackoff(tt.attempt, tt.maxMs)
			jitterRange := baseDelay / 10
			minDelay := baseDelay - jitterRange
			maxDelay := baseDelay + jitterRange
			if maxDelay > tt.maxMs {
				maxDelay = tt.maxMs
			}

			assert.GreaterOrEqual(t, delayMs, minDelay)
			assert.LessOrEqual(t, delayMs, maxDelay)
			assert.Equal(t, delayMs, CalculateBackoff(tt.issueID, tt.attempt, tt.maxMs), "backoff should be deterministic")
		})
	}
}

func TestCalculateBackoff_ContinuationRespectsMax(t *testing.T) {
	tests := []struct {
		name    string
		issueID string
		attempt int
		maxMs   int
	}{
		{name: "continuation_capped_when_max_below_fixed_delay", issueID: "issue-continuation", attempt: 0, maxMs: 500},
		{name: "negative_attempt_treated_as_continuation_and_capped", issueID: "issue-continuation", attempt: -1, maxMs: 500},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			delayMs := CalculateBackoff(tt.issueID, tt.attempt, tt.maxMs)
			assert.LessOrEqual(t, delayMs, tt.maxMs)
			assert.Equal(t, 500, delayMs)
		})
	}
}

func TestCalculateBackoff_DifferentIssueIDsDifferentJitter(t *testing.T) {
	attempt := 2
	maxMs := 300_000

	delayA := CalculateBackoff("issue-a", attempt, maxMs)
	delayB := CalculateBackoff("issue-b", attempt, maxMs)

	assert.NotEqual(t, delayA, delayB)
}

func TestCheckBoundedConcurrency(t *testing.T) {
	tests := []struct {
		name    string
		running int
		max     int
		want    bool
	}{
		{name: "below_limit_accepts_work", running: 2, max: 3, want: true},
		{name: "at_limit_rejects_work", running: 3, max: 3, want: false},
		{name: "above_limit_rejects_work", running: 4, max: 3, want: false},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, checkBoundedConcurrency(tt.running, tt.max))
		})
	}
}

func TestDetectStall_Boundaries(t *testing.T) {
	now := time.Date(2026, time.January, 1, 0, 0, 0, 0, time.UTC)

	tests := []struct {
		name           string
		lastEventTime  time.Time
		stallTimeoutMs int
		want           bool
	}{
		{name: "before_timeout", lastEventTime: now.Add(-9 * time.Second), stallTimeoutMs: 10_000, want: false},
		{name: "at_timeout", lastEventTime: now.Add(-10 * time.Second), stallTimeoutMs: 10_000, want: false},
		{name: "after_timeout", lastEventTime: now.Add(-10*time.Second - 1*time.Millisecond), stallTimeoutMs: 10_000, want: true},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, detectStallAt(now, tt.lastEventTime, tt.stallTimeoutMs))
		})
	}
}

func TestParseRateLimits(t *testing.T) {
	tests := []struct {
		name string
		data map[string]interface{}
		want func(t *testing.T, info *types.RateLimitInfo)
	}{
		{
			name: "nil_data",
			data: nil,
			want: func(t *testing.T, info *types.RateLimitInfo) {
				assert.Nil(t, info)
			},
		},
		{
			name: "empty_map",
			data: map[string]interface{}{},
			want: func(t *testing.T, info *types.RateLimitInfo) {
				assert.Nil(t, info)
			},
		},
		{
			name: "direct_buckets_in_data",
			data: map[string]interface{}{
				"primary": map[string]interface{}{
					"remaining":    float64(500),
					"limit":        float64(1000),
					"reset_in_s":   float64(30),
					"requests_used": float64(500),
				},
				"secondary": map[string]interface{}{
					"remaining": float64(20000),
					"limit":     float64(20000),
				},
			},
			want: func(t *testing.T, info *types.RateLimitInfo) {
				require.NotNil(t, info)
				require.NotNil(t, info.Primary)
				assert.Equal(t, float64(500), info.Primary.Remaining)
				assert.Equal(t, float64(1000), info.Primary.Limit)
				assert.Equal(t, float64(30), info.Primary.ResetInS)
				require.NotNil(t, info.Secondary)
				assert.Equal(t, float64(20000), info.Secondary.Remaining)
			},
		},
		{
			name: "rate_limits_key_wrapper",
			data: map[string]interface{}{
				"rate_limits": map[string]interface{}{
					"limit_id": "model-tokens",
					"primary": map[string]interface{}{
						"remaining": float64(0),
						"limit":     float64(800),
						"reset_in_s": float64(45),
					},
				},
			},
			want: func(t *testing.T, info *types.RateLimitInfo) {
				require.NotNil(t, info)
				assert.Equal(t, "model-tokens", info.LimitID)
				require.NotNil(t, info.Primary)
				assert.Equal(t, float64(0), info.Primary.Remaining)
				assert.Equal(t, float64(45), info.Primary.ResetInS)
			},
		},
		{
			name: "nested_in_usage",
			data: map[string]interface{}{
				"usage": map[string]interface{}{
					"prompt_tokens": float64(100),
					"rate_limits": map[string]interface{}{
						"credits": map[string]interface{}{
							"remaining": float64(50),
							"limit":     float64(1000),
						},
					},
				},
			},
			want: func(t *testing.T, info *types.RateLimitInfo) {
				require.NotNil(t, info)
				require.NotNil(t, info.Credits)
				assert.Equal(t, float64(50), info.Credits.Remaining)
				assert.Equal(t, float64(1000), info.Credits.Limit)
			},
		},
		{
			name: "with_reset_at_iso8601",
			data: map[string]interface{}{
				"primary": map[string]interface{}{
					"remaining":  float64(10),
					"limit":      float64(1000),
					"reset_at":   "2026-01-01T00:00:30Z",
				},
			},
			want: func(t *testing.T, info *types.RateLimitInfo) {
				require.NotNil(t, info)
				require.NotNil(t, info.Primary)
				assert.Equal(t, float64(10), info.Primary.Remaining)
				assert.False(t, info.Primary.ResetAt.IsZero())
				assert.Equal(t, 2026, info.Primary.ResetAt.Year())
			},
		},
		{
			name: "integer_values_as_int",
			data: map[string]interface{}{
				"primary": map[string]interface{}{
					"remaining": int(500),
					"limit":     int(1000),
				},
			},
			want: func(t *testing.T, info *types.RateLimitInfo) {
				require.NotNil(t, info)
				require.NotNil(t, info.Primary)
				assert.Equal(t, float64(500), info.Primary.Remaining)
			},
		},
		{
			name: "no_meaningful_buckets_returns_nil",
			data: map[string]interface{}{
				"rate_limits": map[string]interface{}{
					"limit_id": "",
				},
			},
			want: func(t *testing.T, info *types.RateLimitInfo) {
				assert.Nil(t, info)
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			info := parseRateLimits(tt.data)
			tt.want(t, info)
		})
	}
}

func TestIsRateLimitAgentEvent(t *testing.T) {
	tests := []struct {
		name  string
		event types.AgentEvent
		want  bool
	}{
		{
			name: "explicit_rate_limit_exceeded_event",
			event: types.AgentEvent{Type: "rate_limit_exceeded"},
			want:  true,
		},
		{
			name: "turn_failed_with_rate_limit_message",
			event: types.AgentEvent{
				Type: "turn/failed",
				Data: map[string]interface{}{"error": "rate limit exceeded"},
			},
			want: true,
		},
		{
			name: "turn_failed_with_429_message",
			event: types.AgentEvent{
				Type: "turn/failed",
				Data: map[string]interface{}{"error": "HTTP 429 Too Many Requests"},
			},
			want: true,
		},
		{
			name: "turn_failed_with_status_code_429",
			event: types.AgentEvent{
				Type: "turn/failed",
				Data: map[string]interface{}{"message": "status code 429"},
			},
			want: true,
		},
		{
			name: "turn_failed_with_too_many_requests",
			event: types.AgentEvent{
				Type: "turn/failed",
				Data: map[string]interface{}{"error": "too many requests"},
			},
			want: true,
		},
		{
			name: "turn_failed_non_rate_limit_error",
			event: types.AgentEvent{
				Type: "turn/failed",
				Data: map[string]interface{}{"error": "connection refused"},
			},
			want: false,
		},
		{
			name:  "turn_started_not_rate_limit",
			event: types.AgentEvent{Type: "turn/started"},
			want:  false,
		},
		{
			name:  "session_status_not_rate_limit",
			event: types.AgentEvent{Type: "session.status"},
			want:  false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, isRateLimitAgentEvent(tt.event))
		})
	}
}

func TestIsRateLimitErrorMessage(t *testing.T) {
	tests := []struct {
		name string
		msg  string
		want bool
	}{
		{"exact_match", "rate limit exceeded", true},
		{"contains", "request failed: rate limit exceeded after 50 calls", true},
		{"rate_limited_string", "rate limited", true},
		{"rate_limit_exceeded_underscore", "rate_limit_exceeded", true},
		{"too_many_requests", "too many requests", true},
		{"http_429", "HTTP 429 Too Many Requests", true},
		{"status_code_429", "status code 429", true},
		{"case_insensitive", "Rate Limited", true},
		{"connection_refused_not_rate", "connection refused", false},
		{"timeout_not_rate", "request timed out", false},
		{"empty", "", false},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, isRateLimitErrorMessage(tt.msg))
		})
	}
}

func TestRateLimitBackoffExtension(t *testing.T) {
	tests := []struct {
		name   string
		limits *types.RateLimitInfo
		want   time.Duration
	}{
		{
			name:   "nil_limits",
			limits: nil,
			want:   0,
		},
		{
			name: "primary_has_reset_in_s",
			limits: &types.RateLimitInfo{
				Primary: &types.RateLimitBucket{Remaining: 0, ResetInS: 45},
			},
			want: 45 * time.Second,
		},
		{
			name: "secondary_has_longer_reset",
			limits: &types.RateLimitInfo{
				Primary:   &types.RateLimitBucket{Remaining: 10, ResetInS: 30},
				Secondary: &types.RateLimitBucket{Remaining: 0, ResetInS: 60},
			},
			want: 60 * time.Second,
		},
		{
			name: "reset_at_in_future_takes_precedence",
			limits: &types.RateLimitInfo{
				Primary: &types.RateLimitBucket{
					Remaining: 0,
					ResetAt:   time.Now().Add(90 * time.Second),
					ResetInS:  45,
				},
			},
			want: 90 * time.Second,
		},
		{
			name: "all_buckets_nil",
			limits: &types.RateLimitInfo{
				LimitID: "test",
			},
			want: 0,
		},
		{
			name: "reset_in_past_returns_zero",
			limits: &types.RateLimitInfo{
				Primary: &types.RateLimitBucket{
					Remaining: 0,
					ResetAt:   time.Now().Add(-10 * time.Second),
				},
			},
			want: 0,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			got := rateLimitBackoffExtension(tt.limits)
			if tt.want == 0 {
				assert.Equal(t, time.Duration(0), got)
			} else {
				assert.GreaterOrEqual(t, got, tt.want-time.Second,
					"extension should be at least reset time minus 1s")
			}
		})
	}
}

func TestIsRateLimited(t *testing.T) {
	tests := []struct {
		name   string
		limits *types.RateLimitInfo
		want   bool
	}{
		{
			name:   "nil_limits",
			limits: nil,
			want:   false,
		},
		{
			name: "primary_exhausted",
			limits: &types.RateLimitInfo{
				Primary: &types.RateLimitBucket{Remaining: 0},
			},
			want: true,
		},
		{
			name: "credits_exhausted",
			limits: &types.RateLimitInfo{
				Credits: &types.RateLimitBucket{Remaining: -1},
			},
			want: true,
		},
		{
			name: "all_have_remaining",
			limits: &types.RateLimitInfo{
				Primary:   &types.RateLimitBucket{Remaining: 100},
				Secondary: &types.RateLimitBucket{Remaining: 5000},
			},
			want: false,
		},
		{
			name: "no_buckets_set",
			limits: &types.RateLimitInfo{
				LimitID: "anon",
			},
			want: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, isRateLimited(tt.limits))
		})
	}
}

func TestParseFloat64(t *testing.T) {
	tests := []struct {
		name  string
		value interface{}
		want  float64
	}{
		{"float64", float64(42), 42},
		{"int", int(42), 42},
		{"int64", int64(42), 42},
		{"string", "42.5", 42.5},
		{"string_int", "42", 42},
		{"invalid_string", "abc", 0},
		{"nil_like", nil, 0},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, parseFloat64(tt.value))
		})
	}
}

func expectedFailureBackoff(attempt int, maxMs int) int {
	if attempt <= 0 {
		return 0
	}

	delay := 10_000
	for step := 1; step < attempt; step++ {
		if delay >= maxMs {
			return maxMs
		}
		if delay > maxMs/2 {
			delay = maxMs
			break
		}
		delay *= 2
	}

	if delay > maxMs {
		return maxMs
	}

	return delay
}
