package agent

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestExtractTokenSnapshot_AbsolutePath_ParamsMsgPayload(t *testing.T) {
	data := map[string]interface{}{
		"params": map[string]interface{}{
			"msg": map[string]interface{}{
				"payload": map[string]interface{}{
					"info": map[string]interface{}{
						"total_token_usage": map[string]interface{}{
							"input_tokens":  float64(100),
							"output_tokens": float64(50),
							"total_tokens":  float64(150),
						},
					},
				},
			},
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 100, 50, 150)
}

func TestExtractTokenSnapshot_AbsolutePath_SimpleParams(t *testing.T) {
	data := map[string]interface{}{
		"params": map[string]interface{}{
			"msg": map[string]interface{}{
				"info": map[string]interface{}{
					"total_token_usage": map[string]interface{}{
						"input_tokens":  float64(200),
						"output_tokens": float64(100),
						"total_tokens":  float64(300),
					},
				},
			},
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 200, 100, 300)
}

func TestExtractTokenSnapshot_AbsolutePath_ParamsTokenUsage(t *testing.T) {
	data := map[string]interface{}{
		"params": map[string]interface{}{
			"tokenUsage": map[string]interface{}{
				"total": map[string]interface{}{
					"input_tokens":  float64(50),
					"output_tokens": float64(25),
				},
			},
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 50, 25, 0)
}

func TestExtractTokenSnapshot_AbsolutePath_DirectTokenUsage(t *testing.T) {
	data := map[string]interface{}{
		"tokenUsage": map[string]interface{}{
			"total": map[string]interface{}{
				"input_tokens":  float64(300),
				"output_tokens": float64(150),
				"total_tokens":  float64(450),
			},
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 300, 150, 450)
}

func TestExtractTokenSnapshot_AbsolutePath_TokenUsageDirect(t *testing.T) {
	data := map[string]interface{}{
		"tokenUsage": map[string]interface{}{
			"input_tokens":  float64(75),
			"output_tokens": float64(30),
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 75, 30, 0)
}

func TestExtractTokenSnapshot_TurnCompleted_DirectUsage(t *testing.T) {
	data := map[string]interface{}{
		"method": "turn/completed",
		"usage": map[string]interface{}{
			"input_tokens":  float64(500),
			"output_tokens": float64(250),
			"total_tokens":  float64(750),
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 500, 250, 750)
}

func TestExtractTokenSnapshot_TurnCompleted_ParamsUsage(t *testing.T) {
	data := map[string]interface{}{
		"method": "turn/completed",
		"params": map[string]interface{}{
			"usage": map[string]interface{}{
				"input_tokens":  float64(400),
				"output_tokens": float64(200),
				"total_tokens":  float64(600),
			},
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 400, 200, 600)
}

func TestExtractTokenSnapshot_TurnCompleted_PayloadUsage(t *testing.T) {
	data := map[string]interface{}{
		"payload": map[string]interface{}{
			"method": "turn/completed",
			"usage": map[string]interface{}{
				"input_tokens":  float64(1000),
				"output_tokens": float64(500),
				"total_tokens":  float64(1500),
			},
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 1000, 500, 1500)
}

func TestExtractTokenSnapshot_CamelCaseKeys(t *testing.T) {
	data := map[string]interface{}{
		"tokenUsage": map[string]interface{}{
			"inputTokens":  float64(50),
			"outputTokens": float64(25),
			"totalTokens":  float64(75),
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 50, 25, 75)
}

func TestExtractTokenSnapshot_PromptCompletionKeys(t *testing.T) {
	data := map[string]interface{}{
		"params": map[string]interface{}{
			"msg": map[string]interface{}{
				"payload": map[string]interface{}{
					"info": map[string]interface{}{
						"total_token_usage": map[string]interface{}{
							"prompt_tokens":     float64(500),
							"completion_tokens": float64(300),
							"total_tokens":      float64(800),
						},
					},
				},
			},
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 500, 300, 800)
}

func TestExtractTokenSnapshot_PromptCompletionCamel(t *testing.T) {
	data := map[string]interface{}{
		"tokenUsage": map[string]interface{}{
			"promptTokens":     float64(200),
			"completionTokens": float64(100),
			"totalTokens":      float64(300),
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 200, 100, 300)
}

func TestExtractTokenSnapshot_NilData(t *testing.T) {
	snapshot := ExtractTokenSnapshot(nil)
	assert.Nil(t, snapshot)
}

func TestExtractTokenSnapshot_EmptyData(t *testing.T) {
	snapshot := ExtractTokenSnapshot(map[string]interface{}{})
	assert.Nil(t, snapshot)
}

func TestExtractTokenSnapshot_NonMapTokenUsage(t *testing.T) {
	snapshot := ExtractTokenSnapshot(map[string]interface{}{
		"tokenUsage": "not-a-map",
	})
	assert.Nil(t, snapshot)
}

func TestExtractTokenSnapshot_NonTokenMap(t *testing.T) {
	snapshot := ExtractTokenSnapshot(map[string]interface{}{
		"tokenUsage": map[string]interface{}{
			"name": "not a token map",
		},
	})
	assert.Nil(t, snapshot)
}

func TestExtractTokenSnapshot_NoInputField(t *testing.T) {
	snapshot := ExtractTokenSnapshot(map[string]interface{}{
		"tokenUsage": map[string]interface{}{
			"output_tokens": float64(100),
		},
	})
	requireNotNil(t, snapshot)
	assert.Equal(t, int64(0), snapshot.Input)
	assert.Equal(t, int64(100), snapshot.Output)
	assert.Equal(t, int64(0), snapshot.Total)
}

func TestExtractTokenSnapshot_NegativeValues(t *testing.T) {
	// output_tokens=0 makes integerTokenMap return true (0 >= 0),
	// but the negative input is rejected by integerLike so input=0.
	snapshot := ExtractTokenSnapshot(map[string]interface{}{
		"tokenUsage": map[string]interface{}{
			"input_tokens":  float64(-1),
			"output_tokens": float64(0),
		},
	})
	requireNotNil(t, snapshot)
	assert.Equal(t, int64(0), snapshot.Input)
	assert.Equal(t, int64(0), snapshot.Output)
}

func TestExtractTokenSnapshot_NestedPayload(t *testing.T) {
	data := map[string]interface{}{
		"payload": map[string]interface{}{
			"params": map[string]interface{}{
				"msg": map[string]interface{}{
					"payload": map[string]interface{}{
						"info": map[string]interface{}{
							"total_token_usage": map[string]interface{}{
								"input_tokens":  float64(42),
								"output_tokens": float64(21),
								"total_tokens":  float64(63),
							},
						},
					},
				},
			},
		},
	}
	snapshot := ExtractTokenSnapshot(data)
	requireValid(t, snapshot, 42, 21, 63)
}

// --- accumulator tests ---

func TestTokenAccumulator_FirstDelta(t *testing.T) {
	var acc tokenAccumulator
	delta := acc.accumulate(TokenSnapshot{Input: 100, Output: 50, Total: 150})
	requireNotNil(t, delta)
	assert.Equal(t, int64(100), delta.InputDelta)
	assert.Equal(t, int64(50), delta.OutputDelta)
	assert.Equal(t, int64(150), delta.TotalDelta)
}

func TestTokenAccumulator_IncrementalDelta(t *testing.T) {
	var acc tokenAccumulator
	_ = acc.accumulate(TokenSnapshot{Input: 100, Output: 50, Total: 150})

	delta := acc.accumulate(TokenSnapshot{Input: 250, Output: 120, Total: 370})
	requireNotNil(t, delta)
	assert.Equal(t, int64(150), delta.InputDelta)
	assert.Equal(t, int64(70), delta.OutputDelta)
	assert.Equal(t, int64(220), delta.TotalDelta)
}

func TestTokenAccumulator_NoChange(t *testing.T) {
	var acc tokenAccumulator
	_ = acc.accumulate(TokenSnapshot{Input: 100, Output: 50, Total: 150})

	delta := acc.accumulate(TokenSnapshot{Input: 100, Output: 50, Total: 150})
	assert.Nil(t, delta)
}

func TestTokenAccumulator_NoDoubleCounting(t *testing.T) {
	var acc tokenAccumulator
	_ = acc.accumulate(TokenSnapshot{Input: 100, Output: 50, Total: 150})

	// Lower values are ignored (guards against double-counting)
	delta := acc.accumulate(TokenSnapshot{Input: 80, Output: 40, Total: 120})
	assert.Nil(t, delta)
}

func TestTokenAccumulator_PartialUpdate(t *testing.T) {
	var acc tokenAccumulator
	_ = acc.accumulate(TokenSnapshot{Input: 100, Output: 50, Total: 150})

	// Only input increases
	delta := acc.accumulate(TokenSnapshot{Input: 200, Output: 50, Total: 150})
	requireNotNil(t, delta)
	assert.Equal(t, int64(100), delta.InputDelta)
	assert.Equal(t, int64(0), delta.OutputDelta)
	assert.Equal(t, int64(0), delta.TotalDelta)
}

func TestTokenAccumulator_AllZero(t *testing.T) {
	var acc tokenAccumulator
	delta := acc.accumulate(TokenSnapshot{Input: 0, Output: 0, Total: 0})
	assert.Nil(t, delta)
}

// --- integerLike tests ---

func TestIntegerLike_Float64(t *testing.T) {
	assert.Equal(t, int64(42), integerLike(float64(42)))
}

func TestIntegerLike_Float64Negative(t *testing.T) {
	assert.Equal(t, int64(-1), integerLike(float64(-1)))
}

func TestIntegerLike_Float64Fractional(t *testing.T) {
	assert.Equal(t, int64(-1), integerLike(float64(3.14)))
}

func TestIntegerLike_Int(t *testing.T) {
	assert.Equal(t, int64(10), integerLike(10))
}

func TestIntegerLike_IntNegative(t *testing.T) {
	assert.Equal(t, int64(-1), integerLike(-5))
}

func TestIntegerLike_String(t *testing.T) {
	assert.Equal(t, int64(-1), integerLike("123"))
}

func TestIntegerLike_Nil(t *testing.T) {
	assert.Equal(t, int64(-1), integerLike(nil))
}

// --- integerTokenMap tests ---

func TestIntegerTokenMap_SnakeKeys(t *testing.T) {
	m := map[string]interface{}{
		"input_tokens": float64(10),
	}
	assert.True(t, integerTokenMap(m))
}

func TestIntegerTokenMap_CamelKeys(t *testing.T) {
	m := map[string]interface{}{
		"inputTokens": float64(10),
	}
	assert.True(t, integerTokenMap(m))
}

func TestIntegerTokenMap_OutputOnly(t *testing.T) {
	m := map[string]interface{}{
		"output_tokens": float64(20),
	}
	assert.True(t, integerTokenMap(m))
}

func TestIntegerTokenMap_NotATokenMap(t *testing.T) {
	m := map[string]interface{}{
		"name": "not a token map",
	}
	assert.False(t, integerTokenMap(m))
}

func TestIntegerTokenMap_Nil(t *testing.T) {
	assert.False(t, integerTokenMap(nil))
}

// --- helpers ---

func requireValid(t *testing.T, s *TokenSnapshot, input, output, total int64) {
	t.Helper()
	requireNotNil(t, s)
	assert.Equal(t, input, s.Input)
	assert.Equal(t, output, s.Output)
	assert.Equal(t, total, s.Total)
}

func requireNotNil(t *testing.T, v interface{}) {
	t.Helper()
	if v == nil {
		t.Fatal("expected non-nil value")
	}
}
