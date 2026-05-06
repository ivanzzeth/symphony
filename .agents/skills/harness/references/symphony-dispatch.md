# Symphony Dispatch Protocol

## Overview

When the harness skill is invoked by the Symphony platform (not manually by a user), additional context comes from the **Symphony execution contract** (`WORKFLOW.md` — for this monorepo `elixir/WORKFLOW.md`, or whichever path the running `symphony` process was started with). This document defines how harness agents should integrate with Symphony's orchestration layer.

## Detection

Symphony dispatch is active when the harness run is triggered by Symphony’s
orchestrator (hash change, harness ticket, or explicit dispatch), not a casual
local edit. The **execution contract** for this repo lives at
`elixir/WORKFLOW.md` (or whichever path the running `symphony` process was
started with)—**not** under `.agents/`. A copy under `.agents/WORKFLOW.md` is
optional and not required for dispatch.

Heuristics:
- Orchestrator-spawned harness work often includes `_workspace/symphony_context.json`
  or equivalent issue metadata supplied by the caller.
- If neither platform context nor user intent references Symphony, treat this
  as a standalone/manual harness invocation and use default protocols.

**Never modify** the loaded WORKFLOW.md file; update only `.agents/` and
`AGENTS.md` when reconfiguring the harness.

## Symphony Context (when active)

When running under Symphony, these platform-level details are available:

### Current Issue/Task
- The active Linear/GitHub issue the Symphony orchestrator is working on
- Priority, assignee, state, and labels from the tracker

### Agent State
- Symphony's agent pool state (agents currently running, queued, completed)
- Available SSH worker hosts and their capacity
- Current turn number and remaining turn budget

### Execution Contract
- `WORKFLOW.md` defines what Symphony expects from this harness run
- May specify: target files, acceptance criteria, constraints, artifact paths

## Harness Agent Behavior Under Symphony

### Phase 0 Modifications
When Symphony dispatch is detected:
1. Read the repo’s **Symphony** `WORKFLOW.md` (for this monorepo: `elixir/WORKFLOW.md`) to understand the execution contract
2. Check `_workspace/symphony_context.json` (when present) for the current issue context
3. Align the harness execution plan with the WORKFLOW.md requirements — the harness serves the platform's execution contract

### Agent Scope
- Agents defined by the harness operate within the project directory
- Symphony provides the workspace; harness agents must not modify the Symphony `WORKFLOW.md` execution contract or `.omc/` state
- All intermediate artifacts go to `_workspace/` as usual

### Output Convention
- Final outputs go to paths specified in WORKFLOW.md, or default to `_workspace/`
- The orchestrator should produce a completion signal (`_workspace/done.json`) when the contract is fulfilled
- Include a summary of what was done, token usage, and any follow-up recommendations

### Agent Lifecycle
- Symphony manages the harness agent's process lifecycle — the harness should not spawn long-running daemons
- Clean up sub-agents and teams before returning control to Symphony
- The harness agent is one step in Symphony's pipeline; keep outputs structured for downstream consumption

## Harness multi-turn resume

`SymphonyElixir.Harness.Manager` may run several adapter turns for a single
harness dispatch. After the first turn, follow-up prompts are worded like:
“Continue the harness configuration. Resume from the current workspace and
`.agents/` state.” Treat that as **continuation**, not a new harness build:
re-read Phase 0 audit outputs, finish incomplete edits, sync `AGENTS.md` and
`.cursor/` mirrors, and avoid duplicating work already landed in the tree.

## Non-Symphony (Standalone) Mode

When no Symphony workflow context applies (manual harness request only):
- The harness operates fully autonomously as defined in the main SKILL.md workflow
- AGENTS.md registration ensures the harness activates in future sessions
- No platform constraints apply

## Symphony vs Harness Responsibilities

| Concern | Symphony Platform | Harness |
|---------|------------------|---------|
| Issue tracking | O | X |
| Agent pool & SSH workers | O | X |
| Turn budget & retry | O | X |
| Agent team composition | X | O |
| Skill definition & execution | X | O |
| Output quality & verification | X | O |
| AGENTS.md maintenance | X | O |
| Workspace artifact management | O (provides root) | O (organizes within) |
