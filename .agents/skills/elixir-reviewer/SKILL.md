---
name: elixir-reviewer
description: "Reviews Elixir code quality in the Symphony orchestrator codebase. MUST use this skill when reviewing ANY code changes to elixir/. Checks: Elixir-specific patterns (pattern matching over conditionals, pipe operator judicious use, GenServer callback conventions, struct consistency, immutable patterns), project conventions (modules under 800 lines, functions under 50 lines, error handling with :ok/:error tuples, no hardcoded values, test mirroring, WORKFLOW.md never modified), code quality (no debug artifacts, descriptive naming, no deep nesting over 4 levels), and security (input validation, file operations, external API calls). Produces severity-graded report at _workspace/05_reviewer_report.md."
---

# Elixir Reviewer Skill

Domain-specific code review guidance for the Symphony Elixir codebase. Read this before reviewing code changes.

## Elixir-Specific Checklist

In addition to the general checklist in the agent definition:

### Pattern Matching vs Conditionals

```elixir
# PREFERRED: Pattern matching
def handle_call(:get, _from, state), do: {:reply, state, state}

# AVOID: Conditional when pattern matching works
def handle_call(msg, _from, state) do
  if msg == :get, do: {:reply, state, state}
end
```

### Pipe Operator (`|>`)

```elixir
# ACCEPTABLE: Short chain, clear flow
data |> validate() |> transform() |> format()

# AVOID: Deep chains that hide intermediate values (>3 pipes in logic functions)
# AVOID: Pipes with side effects (iex>)

# PREFERRED for complex logic: named intermediate variables
```

### GenServer Conventions

```elixir
# Every GenServer module should have:
defstruct [:state_field1, :state_field2]         # state struct

@impl true
def init(%Config{} = config) ...                  # init returns {:ok, state}

@impl true
def handle_call(:action, _from, state) ...         # sync calls

@impl true
def handle_cast({:action, args}, state) ...        # async calls

@impl true
def handle_info(:tick, state) ...                  # periodic timers
```

### Error Handling Style

```elixir
# PREFERRED: {:ok, result} / {:error, reason} tuples
def find(id) do
  case Repo.get(id) do
    nil -> {:error, :not_found}
    record -> {:ok, record}
  end
end

# FLAG: raise/rescue in non-test code (unless truly exceptional)
# FLAG: silent rescue/catch
```

## Project-Specific Checks

### Immutability (CRITICAL)

```elixir
# CORRECT: Returns new state
def update(state, field, value), do: %{state | field => value}

# WRONG: Mutates in place
# (structs are immutable in Elixir, so this is naturally enforced)
# But watch for: Agent.update, :ets, :persistent_term mutations
```

### Module Organization

```elixir
# PREFERRED: ~200-400 lines, max 800
# PREFERRED: One primary concept per module
# FLAG: Modules near 800 lines — recommend splitting
# FLAG: Functions over 50 lines — recommend extracting helpers
```

### Config vs Hardcoding

```elixir
# PREFERRED: Config module or module attribute
@default_timeout 5_000

# FLAG: Magic numbers in logic code (urls, ports, timeouts)
# FLAG: Hardcoded file paths
```

## Architecture Checks

- Does the change follow the existing module's pattern?
- Does the change respect the boundary between project-level config (WORKFLOW.md) and daemon-level config (symphony.yaml)?
- Does the change introduce a new dependency? If yes, flag for discussion.
- Does the change touch the Orchestrator state machine? If yes, test coverage must be thorough.

## Security-Focused Checks

- User input: any `def parse`, `def validate` should handle edge cases
- File operations: check path sanitization
- External API calls: check error handling for network failures
- Config values: never log or expose sensitive config values
