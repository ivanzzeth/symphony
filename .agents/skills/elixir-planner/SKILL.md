---
name: elixir-planner
description: "Produces implementation plans for the Symphony Elixir codebase. Analyzes requirements, explores the codebase, identifies affected modules and tests, decomposes work into ordered tasks, and assesses risks. MUST use this skill when planning ANY change to the Elixir orchestrator at elixir/ — new features, bug fixes, refactoring, or test additions. The plan MUST reference actual file paths (elixir/lib/symphony_elixir/{module}.ex) and call out every test file that needs creation or modification."
---

# Elixir Planner Skill

Domain-specific planning guidance for the Symphony Elixir orchestrator. Use this when producing implementation plans in `_workspace/01_planner_plan.md`.

## Domain Knowledge

### Module Map

| Area | Key Modules |
|------|------------|
| Core orchestration | `orchestrator.ex`, `agent_runner.ex`, `agent_symlinks.ex` |
| Workflow management | `workflow.ex`, `workflow_store.ex`, `process_config/store.ex` |
| Tracker integration | `tracker/github/adapter.ex`, `linear/adapter.ex`, `linear/client.ex` |
| AI adapters | `claude/adapter.ex`, `cursor/adapter.ex` |
| HTTP server | `http_server.ex`, `codex/app_server.ex` |
| Dashboard | `status_dashboard.ex` (Phoenix LiveView), `cli.ex` |
| Config | `config.ex`, `workspace.ex`, `ssh.ex` |
| Tests | `test/symphony_elixir/` — mirrors lib structure |

### WORKFLOW.md Boundaries

The WORKFLOW.md file at `elixir/WORKFLOW.md` is the **Symphony execution contract** and must NEVER be modified. It contains:
- Tracker config (Linear project slug, state machine)
- Polling interval
- Workspace settings (root, base_branch)
- Agent config (kind, max_concurrent, max_turns)
- Codex config (approval_policy, sandbox)

If the plan requires modifying WORKFLOW.md, flag it as BLOCKED and inform the user.

### Planning Heuristics

1. **Read before planning** — Always read the affected modules first. Look at function heads, `defstruct`, type specs, and test files to understand interfaces.
2. **Track test implications** — Every module change needs at least one test change. Check `/test/symphony_elixir/` for existing test coverage.
3. **Surface risks** — If the change affects the orchestrator's state machine (orchestrator.ex: `handle_cast`, `handle_call`), flag it as HIGH risk.
4. **Config changes** — If adding new config keys, they go in `elixir/config/config.exs` or `~/.config/symphony/symphony.yaml` (daemon-level). Never plan WORKFLOW.md changes.
5. **Break down by file** — Each task should reference specific file paths. "Update orchestrator.ex" is too vague; "Add `handle_info(:tick, state)` to orchestrator.ex at line ~200" is good.
