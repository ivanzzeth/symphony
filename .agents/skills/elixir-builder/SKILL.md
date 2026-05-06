---
name: elixir-builder
description: "Builds the Symphony escript binary, manages dependencies, and resolves compilation errors for the Elixir codebase at elixir/. MUST use this skill when building the project (mix build), resolving dependency issues (mix deps.get, mix deps.clean), fixing compiler warnings or errors, or verifying the escript (bin/symphony --help). Commands always use 'mise exec --' prefix. Key paths: escript entry point = SymphonyElixir.CLI, output = elixir/bin/symphony, compile-time config = elixir/config/, lock file = elixir/mix.lock. Never modify mix.exs unless explicitly for dependency changes."
---

# Elixir Builder Skill

Domain-specific build guidance for the Symphony Elixir codebase at `elixir/`. Read this before building or diagnosing compilation issues.

## Build Commands

All commands use the `mise exec --` prefix:

```bash
cd elixir && mise exec -- mix deps.get               # fetch dependencies
cd elixir && mise exec -- mix deps.clean --unused     # clean stale deps
cd elixir && mise exec -- mix deps.unlock <dep>       # unlock a dep for update
cd elixir && mise exec -- mix compile --warnings-as-errors  # strict compile
cd elixir && mise exec -- mix escript.build           # build binary
cd elixir && mise exec -- mix clean                   # clean build artifacts
cd elixir && mise exec -- mix build                   # full build alias (deps + compile + escript)
```

## Build Pipeline

The `mix build` alias (defined in `mix.exs` aliases) typically runs:
1. `deps.get` — fetch dependencies
2. `compile --warnings-as-errors` — compile with strict warnings
3. `escript.build` — produce `bin/symphony`

For isolated steps: run them individually rather than `mix build` every time.

## Escript Details

- **Entry point**: `SymphonyElixir.CLI` (defined in `mix.exs` under `escript: [main_module: SymphonyElixir.CLI]`)
- **Output**: `elixir/bin/symphony`
- **Required CLI flags**: `--i-understand-that-this-will-be-running-without-the-usual-guardrails`
- **Optional flags**: `--config path`, `--port N`, `--host HOST`
- **Positional arg**: optional WORKFLOW.md path (defaults to `WORKFLOW.md` in CWD)

## Common Compilation Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `== Compilation error in file ...` | Syntax error or undefined module | Check the exact file+line in the error |
| `warning: variable "x" is unused` | Dead code | Prefix with `_` or remove |
| `** (Mix) Unknown task` | Missing dep or wrong CWD | Verify `cd elixir` and `mise exec -- mix deps.get` |
| `dependency ... is out of date` | Lock file mismatch | `mise exec -- mix deps.get` |
| `could not compile dependency ...` | Native dep issue | Check system libs or update dep |
| NIF/Erlang module errors | Missing system packages | Check for `erlang-dev` or similar |

## File System Boundaries

- `elixir/mix.exs` — Do NOT modify unless explicitly required
- `elixir/mix.lock` — Do NOT manually edit; let mix manage it
- `elixir/config/` — Compile-time config; changes here require recompile
- `elixir/deps/` — Managed by `mix deps.get`; never edit manually
- `elixir/_build/` — Build artifacts; safe to delete for clean build
- `~/.config/symphony/symphony.yaml` — Daemon-level runtime config; NOT in the repo
