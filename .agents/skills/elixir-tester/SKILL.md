---
name: elixir-tester
description: "Runs ExUnit tests and coverage checks for the Symphony Elixir codebase at elixir/. MUST use this skill when running tests, diagnosing failures, checking coverage, or adding test infrastructure. Covers: test runner commands (mise exec -- mix test), diagnosis patterns (mix test --trace, --failed, line-specific), coverage targets (80%+ threshold, 100% project threshold with ignored modules), common failure patterns (config not loaded, process state, LiveView tests), and test conventions (AAA pattern, descriptive names, @moduletag usage, test helpers in test/support/)."
---

# Elixir Tester Skill

Domain-specific testing guidance for the Symphony Elixir codebase at `elixir/`. Read this before running or debugging tests.

## Test Runner Commands

All commands use `mise exec --` prefix:

```bash
cd elixir && mise exec -- mix test                    # full suite
cd elixir && mise exec -- mix test --trace             # detailed output
cd elixir && mise exec -- mix test --failed            # re-run failures only
cd elixir && mise exec -- mix test --cover             # with coverage
cd elixir && mise exec -- mix test test/path/file.exs  # single file
cd elixir && mise exec -- mix test test/path/file.exs:12  # single line
```

## Coverage Configuration

The project sets `test_coverage [threshold: 100]` in mix.exs with an `ignore_modules` list. Key ignored modules include `Config`, `Linear.Client`, `Orchestrator`, `AgentRunner`, `CLI`, `HttpServer`, `StatusDashboard`, `LogFile`, `Workspace`, and all `SymphonyElixirWeb.*` modules. When checking coverage:
- Target 80%+ for code you write
- Report overall percentage but focus on uncovered lines in *your* changed modules
- Do not report ignored modules as gaps

## Common Failure Patterns

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `** (UndefinedFunctionError)` for Config | Config not started | Add `SymphonyElixir.Config` to test setup or use `start_supervised!` |
| LiveView test timeout | LiveView not mounting | Check `async: false` and route config |
| GenServer timeout | Process not started | Use `start_supervised!` in `setup` block |
| `** (ArgumentError) errors` in assertion | Pattern mismatch | Check assertion target type |
| Tests pass in isolation but fail in suite | Shared state or async interference | Check `@moduletag :capture_log` or set `async: false` |

## Test Structure Conventions

```elixir
defmodule SymphonyElixir.ModuleTest do
  use ExUnit.Case, async: true
  # Or: use SymphonyElixir.DataCase for config-dependent tests

  describe "public_function/1" do
    test "returns ok tuple on success" do
      # Arrange
      input = valid_input()

      # Act
      result = Module.public_function(input)

      # Assert
      assert {:ok, _} = result
    end

    test "returns error tuple on invalid input" do
      assert {:error, :invalid} = Module.public_function(nil)
    end
  end
end
```

## Debugging Tips

- `mix test --trace` shows each test name as it runs — useful for finding hangs
- `mix test --failed` runs only previously failed tests
- Use `IO.puts()` for debug output (but remove before finalizing)
- Check `log/symphony.log*` for server-side log output (console handler is removed at startup)
- For Process-dependent tests: `Process.sleep(10)` after a GenServer.cast, or better, `assert_receive` with timeout
