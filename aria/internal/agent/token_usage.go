package agent

import "encoding/json"

// TokenSnapshot captures extracted token usage from a single event payload.
type TokenSnapshot struct {
	Input  int64 `json:"input"`
	Output int64 `json:"output"`
	Total  int64 `json:"total"`
}

// TokenDelta is the change between consecutive snapshots.
type TokenDelta struct {
	InputDelta    int64 `json:"input_delta"`
	OutputDelta   int64 `json:"output_delta"`
	TotalDelta    int64 `json:"total_delta"`
	InputReported int64 `json:"input_reported"`
	OutputReported int64 `json:"output_reported"`
	TotalReported int64 `json:"total_reported"`
}

// tokenAccumulator tracks cumulative token usage and prevents double-counting
// by comparing each new snapshot against the last reported values.
type tokenAccumulator struct {
	lastInputReported  int64
	lastOutputReported int64
	lastTotalReported  int64
}

// accumulate computes the delta between the current snapshot and the previous
// reported values, then updates the accumulator. Returns nil when there is
// no new usage to report.
func (a *tokenAccumulator) accumulate(snapshot TokenSnapshot) *TokenDelta {
	inputDelta := a.computeDelta(snapshot.Input, &a.lastInputReported)
	outputDelta := a.computeDelta(snapshot.Output, &a.lastOutputReported)
	totalDelta := a.computeDelta(snapshot.Total, &a.lastTotalReported)

	if inputDelta == 0 && outputDelta == 0 && totalDelta == 0 {
		return nil
	}

	return &TokenDelta{
		InputDelta:    inputDelta,
		OutputDelta:   outputDelta,
		TotalDelta:    totalDelta,
		InputReported: a.lastInputReported,
		OutputReported: a.lastOutputReported,
		TotalReported: a.lastTotalReported,
	}
}

func (a *tokenAccumulator) computeDelta(nextTotal int64, prevReported *int64) int64 {
	if nextTotal <= 0 || nextTotal < *prevReported {
		return 0
	}
	delta := nextTotal - *prevReported
	*prevReported = nextTotal
	return delta
}

// ExtractTokenSnapshot extracts token usage from an event data map by trying
// multiple payload sources and known JSON paths, mirroring the Elixir
// orchestrator extraction logic.
func ExtractTokenSnapshot(data map[string]interface{}) *TokenSnapshot {
	if data == nil {
		return nil
	}

	payloads := []map[string]interface{}{data}
	if usage, ok := getMap(data, "usage"); ok {
		payloads = append(payloads, usage)
	}
	if payload, ok := getMap(data, "payload"); ok {
		payloads = append(payloads, payload)
	}

	for _, p := range payloads {
		if snapshot := absoluteTokenUsage(p); snapshot != nil {
			return snapshot
		}
	}

	for _, p := range payloads {
		if snapshot := turnCompletedUsage(p); snapshot != nil {
			return snapshot
		}
	}

	return nil
}

// absoluteTokenUsage walks known JSON paths that contain total_token_usage or
// tokenUsage objects, returning the first valid token snapshot found.
func absoluteTokenUsage(payload map[string]interface{}) *TokenSnapshot {
	absolutePaths := [][]string{
		{"params", "msg", "payload", "info", "total_token_usage"},
		{"params", "msg", "info", "total_token_usage"},
		{"params", "tokenUsage", "total"},
		{"tokenUsage", "total"},
		{"tokenUsage"},
	}

	for _, path := range absolutePaths {
		value := mapAtPath(payload, path)
		if m, ok := value.(map[string]interface{}); ok && integerTokenMap(m) {
			return extractTokenFields(m)
		}
	}

	return nil
}

// turnCompletedUsage extracts token usage from turn/completed events.
func turnCompletedUsage(payload map[string]interface{}) *TokenSnapshot {
	method := getString(payload, "method")
	if method != "turn/completed" && method != "turn_completed" {
		return nil
	}

	var direct map[string]interface{}
	if usage, ok := getMap(payload, "usage"); ok {
		direct = usage
	} else if p, ok := mapAtPath(payload, []string{"params"}).(map[string]interface{}); ok {
		direct, _ = getMap(p, "usage")
	}

	if direct == nil {
		return nil
	}
	if integerTokenMap(direct) {
		return extractTokenFields(direct)
	}
	return nil
}

// integerTokenMap returns true if the map contains at least one integer-like
// token field (input/output/total tokens or their prompt/completion variants).
func integerTokenMap(m map[string]interface{}) bool {
	if m == nil {
		return false
	}
	tokenFields := []string{
		"input_tokens", "output_tokens", "total_tokens",
		"prompt_tokens", "completion_tokens",
		"inputTokens", "outputTokens", "totalTokens",
		"promptTokens", "completionTokens",
	}
	for _, field := range tokenFields {
		if integerLike(m[field]) >= 0 {
			return true
		}
	}
	return false
}

// extractTokenFields pulls input, output, and total token counts from a map
// using the same key-variant lookup as the Elixir orchestrator.
func extractTokenFields(m map[string]interface{}) *TokenSnapshot {
	return &TokenSnapshot{
		Input:  getTokenUsage(m, tokenInputKeys),
		Output: getTokenUsage(m, tokenOutputKeys),
		Total:  getTokenUsage(m, tokenTotalKeys),
	}
}

var (
	tokenInputKeys = []string{
		"input_tokens", "prompt_tokens",
		"inputTokens", "promptTokens",
		"input", "prompt",
	}

	tokenOutputKeys = []string{
		"output_tokens", "completion_tokens",
		"outputTokens", "completionTokens",
		"output", "completion",
	}

	tokenTotalKeys = []string{
		"total_tokens", "total",
		"totalTokens",
	}
)

// getTokenUsage returns the first integer-like value for any of the given keys.
func getTokenUsage(m map[string]interface{}, keys []string) int64 {
	for _, key := range keys {
		if v := integerLike(m[key]); v >= 0 {
			return v
		}
	}
	return 0
}

// mapAtPath walks a series of string keys through nested maps.
func mapAtPath(m map[string]interface{}, path []string) interface{} {
	if m == nil {
		return nil
	}
	current := interface{}(m)
	for _, key := range path {
		cm, ok := current.(map[string]interface{})
		if !ok {
			return nil
		}
		current = cm[key]
	}
	return current
}

// integerLike returns the value cast to int64 if it is a non-negative integer,
// or -1 if it is not a valid token count.
func integerLike(v interface{}) int64 {
	switch n := v.(type) {
	case float64:
		if n >= 0 && n == float64(int64(n)) {
			return int64(n)
		}
	case int:
		if n >= 0 {
			return int64(n)
		}
	case int64:
		if n >= 0 {
			return n
		}
	case json.Number:
		if i, err := n.Int64(); err == nil && i >= 0 {
			return i
		}
	}
	return -1
}

func getString(m map[string]interface{}, key string) string {
	if m == nil {
		return ""
	}
	v, _ := m[key].(string)
	return v
}

func getMap(m map[string]interface{}, key string) (map[string]interface{}, bool) {
	if m == nil {
		return nil, false
	}
	v, ok := m[key].(map[string]interface{})
	return v, ok
}
