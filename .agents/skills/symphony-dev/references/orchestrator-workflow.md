# Symphony Development Orchestrator — Reference

Load this file when the orchestrator needs detailed workflow guidance beyond the SKILL.md body.

**Related contract:** Linear issue execution (orchestrator-dispatched tickets) is
governed by `elixir/WORKFLOW.md` and the **Symphony Issue Execution** section of
`AGENTS.md`—not this dev pipeline. When a change touches dispatch, hooks, or
issue-agent behavior, read that file. Harness and dev agents **must not** edit
`elixir/WORKFLOW.md` unless a human explicitly performs that change outside
automated harness runs.

## Phase Execution Order

```
Phase 0: Context Detection
  │
  ▼
Phase 1: Plan (symphony-planner)
  │  └── Output: _workspace/01_planner_plan.md
  │
  ▼
Phase 2: Develop (symphony-developer, isolation: worktree)
  │  └── Output: code in elixir/ + _workspace/03_developer_progress.md
  │
  ├──▶ Phase 3a: Test (symphony-tester) ─── _workspace/02_tester_report.md
  │
  └──▶ Phase 3b: Build (symphony-builder) ─── _workspace/04_builder_report.md
  │
  ▼
Phase 4: Review (symphony-reviewer) ─── _workspace/05_reviewer_report.md
  │
  ▼
Phase 5: Cleanup & Summary
```

## Fix Loop Protocol

When fix is needed after Phase 3 or Phase 4:

```
1. Read _workspace/02_tester_report.md (test failures)
2. Read _workspace/04_builder_report.md (build failures)
3. Re-invoke symphony-developer with both reports
4. Re-invoke symphony-tester + symphony-builder in parallel
5. Re-invoke symphony-reviewer if previous review had issues
6. Repeat max 3 iterations
```

## Agent Prompt Template Variables

| Variable | Source | Used In |
|----------|--------|---------|
| `{user request}` | User's message | Phase 1 |
| `{worktree path}` | Phase 2 result | Phase 3, 4 |
| Test report path | `_workspace/02_tester_report.md` | Fix loop |
| Build report path | `_workspace/04_builder_report.md` | Fix loop |
| Review report path | `_workspace/05_reviewer_report.md` | Fix loop |

## Worktree Lifecycle

1. Phase 2: Orchestrator creates worktree via `isolation: "worktree"` in Agent()
2. If worktree is returned (non-empty path): use it for all subsequent file operations
3. Fix loop: re-invoke developer inside the same worktree
4. Phase 5: Worktree is automatically cleaned up when agent exits (if no changes) or its path+branch are returned

## Skill Loading Order

When invoking each agent, the orchestrator must instruct the agent to load its skill:

| Agent | Skill to load |
|-------|---------------|
| symphony-planner | `.agents/skills/elixir-planner/SKILL.md` |
| symphony-developer | `.agents/skills/elixir-developer/SKILL.md` |
| symphony-tester | `.agents/skills/elixir-tester/SKILL.md` |
| symphony-builder | `.agents/skills/elixir-builder/SKILL.md` |
| symphony-reviewer | `.agents/skills/elixir-reviewer/SKILL.md` |
