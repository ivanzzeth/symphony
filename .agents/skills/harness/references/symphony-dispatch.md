# Symphony Dispatch Protocol

## Overview

When the harness skill is invoked by the Symphony platform (not manually by a user), the **workflow file path** is normally injected into the dispatch context by `SymphonyElixir.Harness.Manager`. The harness agent **must** load that file in full **when the path resolves on disk** before making changes to `.agents/` or `AGENTS.md`. If the path does not resolve, fall back to **`elixir/WORKFLOW.md`** per **Path Injection Mechanism**—still without editing workflow contract files. Never guess or assume contents based on prior runs alone.

## Path Injection Mechanism

The workflow file path is supplied to the harness agent as part of the dispatch context. The agent reads it from the context and uses it verbatim when the file exists. When the path is missing or unreadable (wrong host, cleaned `/tmp`, or permission errors), document that in the issue **`## Codex Workpad`** **`Notes`** and read the repo’s **`elixir/WORKFLOW.md`** as the canonical contract for this monorepo—without modifying either file as part of harness configuration.

## Detection

Symphony dispatch is active when the harness run is triggered by Symphony’s
orchestrator (hash change, harness ticket, or explicit dispatch), not a casual
local edit.

Heuristics:
- Orchestrator-spawned harness work often includes `_workspace/symphony_context.json`
  or equivalent issue metadata supplied by the caller.
- If neither platform context nor user intent references Symphony, treat this
  as a standalone/manual harness invocation and use default protocols.

**Never modify** the loaded workflow file; update only `.agents/` and
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
- Per-turn stream wait budget from WORKFLOW YAML: `agent.stream_timeout_ms` (orchestrator/adapters surface this as `turn_timeout` / stall-style events in logs when exceeded)

### Execution Contract
- `WORKFLOW.md` defines what Symphony expects from this harness run
- The file has two layers: YAML config (tracker, polling, workspace, hooks, `agent` pool limits including **`stream_timeout_ms`**, `codex` runner) **and** the Markdown prompt after the second `---` (status routing, Default posture, workpad rules, PR feedback sweep, completion bar). Harness reconfiguration must keep **AGENTS.md** and issue-execution skills (`pull`, `push`, `land`, `linear`, …) aligned with **both** layers.
- The Markdown template may include a **`{% if attempt %}` continuation block**: retry attempt number, resume-from-current-workspace instructions, and constraints on repeating completed work. Issue-execution agents must treat that as **continuation semantics**, not a cold start—see `issue-execution-checklist.md` → *Continuation / retry attempts*.
- **WORKFLOW Contract (numbered list):** unattended output, workpad-first, reproduce first, single workpad, ticket metadata rules, scope discipline — see `elixir/WORKFLOW.md` heading **Contract**.
- **State → Skill routing:** follow the Markdown **State → Skill routing** table in WORKFLOW for `Todo` through `Canceled` / `Duplicate`. For **`Backlog`**, use **Step 0** point 2 (do not modify the ticket — stop and wait for the human); `Backlog` is **not** a row in that table but is still routed in Step 0.
- **WORKFLOW command names:** the Markdown template uses **`pull`**, **`commit`**, **`push`**, and **`land sweep`** — same responsibilities as the harness **`pull`**, **`commit`**, **`push`**, and **`land`** skills (`land` sweep vs merge per `land` skill). Legacy prompts may still say `symphony-*`; treat as equivalent to **`pull`** / **`commit`** / **`push`** / **`land`**.
- **Workpad Step 1 shape:** user-facing work needs a **UI walkthrough** acceptance line; app-touching work needs **app-specific flow checks** in `Acceptance Criteria` (not only generic commands); pull evidence lives in **`Notes`** after the Step 1 **`pull`** sync — see `issue-execution-checklist.md` → *Step 1 — workpad bootstrap + acceptance criteria*.
- **Ticket-authored validation:** `Validation` / `Test Plan` / `Testing` content must be **mirrored** into the workpad as required checkboxes (**no optional downgrade**, WORKFLOW Step 1) and **executed in full** before completion (WORKFLOW Step 2; unmet items = incomplete work).
- **`Todo` + attached PR at kickoff:** run the **full PR feedback sweep** after the workpad exists and **before** new feature work (WORKFLOW State map + Step 2); before `In Review`, **`push`** required branch updates when fixes land.
- **Kickoff sync:** confirm **`pull`** evidence is in the workpad **`Notes`** and repo state is understood before substantive implementation (WORKFLOW Step 1).
- **Before `In Review`:** run **`land sweep`**; refresh the workpad so `Plan` / `Acceptance Criteria` / `Validation` match shipped reality; confirm every ticket-provided validation item is checked off; read **Manual QA Plan** when present (WORKFLOW Step 2 + Completion bar).
- **Unattended Contract:** final agent output must list **completed actions** and **blockers only**—no open-ended “next steps for user” (see WORKFLOW Contract point 1).
- **Prerequisite:** missing Linear MCP / `linear_graphql` → **blocked-access escape hatch** (record blocker; do not prompt the user to configure Linear mid-run).
- **Ticket metadata vs issue body:** Default posture asks to keep ticket metadata current (**state**, **checklist**, **acceptance criteria**, **links**); Guardrails forbid using the issue **description/body** for planning/progress—that belongs in **`## Codex Workpad`** (see `issue-execution-checklist.md`).
- **Workpad edit fallback:** MCP comment update preferred; if unavailable use the **update script** path documented in the `linear` skill—only block when both fail (WORKFLOW Guardrails).
- For a short operator checklist (PR sweep commands, merge→Done), see `issue-execution-checklist.md` in the same directory—still subordinate to the loaded workflow file.
- May specify: target files, acceptance criteria, constraints, artifact paths

## Harness Agent Behavior Under Symphony

### Phase 0 Modifications
When Symphony dispatch is detected:
1. Resolve the execution contract: read the **injected workflow file path** from the dispatch context when present **and** readable. If no path was supplied, or the file is missing/stale/unreadable (for example an ephemeral `/tmp/.../WORKFLOW.md` from another host), record that in the active issue workpad **`Notes`** when one exists, then read the repo’s canonical **`elixir/WORKFLOW.md`**. **Never** edit workflow contract files from harness work.
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
re-read `elixir/WORKFLOW.md`, re-audit `.agents/` and `AGENTS.md`, finish
incomplete edits only, and append **Change History** rather than replaying a
greenfield Phase 1–3 design. If the repo maps `.cursor/` to `.agents/` via
symlink, edits under `.agents/` are sufficient—do not maintain a second harness
copy. When `CLAUDE.md` is a symlink to `AGENTS.md` (this monorepo), updating
`AGENTS.md` covers both entrypoints.

**Distinction — do not conflate with issue execution:** the Markdown template’s
`{% if attempt %}` block governs **Linear ticket / Cursor CLI continuation**
(resume workspace + workpad; see `issue-execution-checklist.md`). **Harness**
multi-turn resume governs **meta-configuration** of `.agents/` and `AGENTS.md`
only—different prompt, different goal.

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
