---
name: elixir-developer
description: "Implements and modifies Elixir code in the Symphony orchestrator at elixir/. Writes production code following Phoenix/LiveView conventions, GenServer patterns, and Elixir idioms. MUST use this skill when writing ANY code in the elixir/ directory. Teaches the: module conventions (GenServer callbacks, struct usage, config patterns, test mirroring), file organization (lib/ mirrors test/), immutable patterns, error handling style (tuple returns with :ok/:error), and the rule to NEVER modify WORKFLOW.md. Covers both new features and bug fixes."
---

# Elixir Developer Skill

Domain-specific implementation guidance for the Symphony Elixir codebase at `elixir/`. Read this before writing any code.

## Codebase Conventions

### Module Structure

Every module in `lib/symphony_elixir/` follows this pattern:

```elixir
defmodule SymphonyElixir.ModuleName do
  @moduledoc false  # or brief one-liner

  # Types and structs
  defstruct [:field1, :field2]

  # Client API
  def public_function(arg) do
    # delegation or thin wrapper
  end

  # GenServer callbacks (if applicable)
  @impl true
  def init(state), do: {:ok, state}

  # Private helpers
  defp helper(arg), do: arg
end
```

### Test Mirroring

Every module in `lib/` has a mirror in `test/`:

| Source | Test |
|--------|------|
| `lib/symphony_elixir/orchestrator.ex` | `test/symphony_elixir/orchestrator_test.exs` |
| `lib/symphony_elixir/config.ex` | `test/symphony_elixir/config_test.exs` |
| `lib/symphony_elixir/cli.ex` | `test/symphony_elixir/cli_test.exs` |

### Error Handling Pattern

Return `{:ok, result}` on success, `{:error, reason}` on failure:

```elixir
def process(data) do
  with {:ok, validated} <- validate(data),
       {:ok, transformed} <- transform(validated) do
    {:ok, transformed}
  end
end
```

### Config Pattern

Runtime configuration goes in `config.ex` via `Application.compile_env/3`:

```elixir
@default_port 4001
def port, do: Application.get_env(:symphony_elixir, :port, @default_port)
```

### State Management

GenServers store state in structs. Never mutate — use `%{state | field: new_value}`:

```elixir
def handle_call(:get_state, _from, state), do: {:reply, state, state}
def handle_cast({:update, val}, state), do: {:noreply, %{state | field: val}}
```

## Boundaries

- **NEVER** modify `elixir/WORKFLOW.md` — it is the Symphony execution contract
- **NEVER** modify `deps/` — managed by `mix deps.get`
- **Work inside `elixir/`** — code outside this directory is scaffolding/workpad artifacts
- **Build commands** always use `mise exec -- mix ...` — never bare `mix`
