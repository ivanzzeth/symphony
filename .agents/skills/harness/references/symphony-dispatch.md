# Symphony Dispatch Protocol

## Overview

When the harness skill is invoked by the Symphony platform (not manually by a user), additional context is available through the project's `.agents/WORKFLOW.md` contract. This document defines how harness agents should integrate with Symphony's orchestration layer.

## Detection

Symphony dispatch is active when:
- `project/.agents/WORKFLOW.md` exists — this is the Symphony execution contract
- The orchestrator detects it was spawned by a Symphony harness manager (check `_workspace/` for a `symphony_context.json` file)

If neither is present, treat this as a standalone/manual harness invocation and use default protocols.

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
1. Read `.agents/WORKFLOW.md` to understand the execution contract
2. Check `_workspace/symphony_context.json` for the current issue context
3. Align the harness execution plan with the WORKFLOW.md requirements — the harness serves the platform's execution contract

### Agent Scope
- Agents defined by the harness operate within the project directory
- Symphony provides the workspace; harness agents should not modify `.agents/WORKFLOW.md` or `.omc/` state
- All intermediate artifacts go to `_workspace/` as usual

### Output Convention
- Final outputs go to paths specified in WORKFLOW.md, or default to `_workspace/`
- The orchestrator should produce a completion signal (`_workspace/done.json`) when the contract is fulfilled
- Include a summary of what was done, token usage, and any follow-up recommendations

### Agent Lifecycle
- Symphony manages the harness agent's process lifecycle — the harness should not spawn long-running daemons
- Clean up sub-agents and teams before returning control to Symphony
- The harness agent is one step in Symphony's pipeline; keep outputs structured for downstream consumption

## Non-Symphony (Standalone) Mode

When no WORKFLOW.md is detected:
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
