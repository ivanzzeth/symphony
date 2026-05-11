---
tracker:
  kind: linear
  project_slug: "symphony-079b97dd6409"
  active_states:
    - Todo
    - In Progress
    - In Review
    - Merging
    - Rework
  terminal_states:
    - Backlog
    - Done
    - Canceled
    - Duplicate
polling:
  interval_ms: 5000
workspace:
  root: ~/code/symphony-workspaces
  base_branch: develop
hooks:
  after_create: |
    git clone --depth 1 --branch {{ workspace.base_branch }} https://github.com/ivanzzeth/symphony .
    git checkout {{ workspace.base_branch }}
    if command -v mise >/dev/null 2>&1; then
      cd elixir && mise trust && mise exec -- mix deps.get
    fi
  before_remove: |
    if [ -d elixir ]; then
      cd elixir && mise exec -- mix workspace.before_remove
    else
      echo "elixir/ directory not found; skipping before_remove hook"
    fi
agent:
  kind: cursor
  max_concurrent_agents: 10
  max_turns: 20
  stream_timeout_ms: 600000
codex:
  command: cursor --model auto
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
---

You are working on a Linear ticket `{{ issue.identifier }}`

{% if attempt %}
Continuation context:
- This is retry attempt #{{ attempt }} — resume from current workspace/workpad state.
- Do not repeat completed investigation or validation unless new code changes require it.
- Do not end the turn while the issue remains in an active state unless blocked by missing required permissions/secrets.
{% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

## Contract

1. **Unattended:** never ask the human for follow-up actions. Final message = completed actions + blockers only.
2. **Workpad-first:** open `## Codex Workpad` and bring it up to date before any new implementation.
3. **Reproduce first:** confirm the current behavior/issue signal before changing code.
4. **Single workpad:** all progress notes live in one workpad comment. Do not post separate "done" comments.
5. **Ticket metadata:** keep state, checklist, acceptance criteria, and links current. Do not edit the issue body for planning.
6. **Scope discipline:** out-of-scope discoveries → separate Backlog issue with `related` link + `blockedBy` if dependent.

## State → Skill routing

| State | Action | Skill |
|-------|--------|-------|
| Todo | Move to InProgress → bootstrap workpad → begin | `linear` + `pull` |
| In Progress | Sync → implement → commit → push → sweep | `pull` → implement → `commit` → `push` → `land sweep` |
| In Review | Wait + poll | None (no code changes) |
| Merging | Land PR → Done | `land` (merge mode) |
| Rework | Full reset → fresh branch | `linear` (delete workpad) → `pull` (fresh branch) |
| Canceled / Duplicate | Do nothing, shut down | None |

## Step 0: Route

1. Fetch issue by ID, read current state.
2. Route per State → Skill table above. For `Backlog`: do not modify — stop and wait for human.
3. `Todo` sequencing: `issueUpdate(state: "In Progress")` → find/create `## Codex Workpad` → begin work.
4. If branch PR is CLOSED/MERGED: fresh branch from `origin/{{ workspace.base_branch }}`, restart from reproduction.
5. If state and issue content are inconsistent: document in workpad Notes, proceed with safest flow.

## Step 1: Workpad bootstrap

1. Find `## Codex Workpad` (ignore resolved comments). Create if missing. Reuse the same comment ID.
2. Stamp the workpad top: ```text <host>:<path>@<short-sha>```
3. Add `Plan`, `Acceptance Criteria`, `Validation`, `Notes` sections with checklists.
   - If ticket provides `Validation`/`Test Plan`/`Testing`: mirror into workpad as required items.
   - If app-touching: add app-specific flow checks to `Acceptance Criteria`.
4. Run `pull` to sync `origin/{{ workspace.base_branch }}` before any code edits.
   - Record pull evidence in `Notes`: source(s), outcome (`clean`/`conflicts resolved`), HEAD SHA.

## Step 2: Execute

1. Implement against workpad plan. Keep checklists current.
2. Temporary proof edits allowed for validation; revert every one before commit.
3. `commit` → `push` (creates/updates PR targeting `develop` with `symphony` label).
4. Before `In Review`: run `land sweep` (PR feedback sweep), confirm checks green, refresh workpad.
5. Move to `In Review` only when Completion bar below is satisfied.

## Step 3: In Review

- No code changes. Poll for review decisions.
- Feedback requiring changes → move to `Rework`.
- Approved → human moves to `Merging`.

## Step 4: Rework

1. Close existing PR. Delete old `## Codex Workpad`.
2. Fresh branch from `origin/{{ workspace.base_branch }}`.
3. New workpad → new plan → execute end-to-end.

## Completion bar before In Review

- Workpad checklists fully complete and accurate.
- Acceptance criteria + required ticket-provided validation items done.
- Validation/tests green on latest commit.
- PR feedback sweep complete, no actionable comments.
- PR checks green, branch pushed, PR linked on issue.
- PR targets `develop` with `symphony` label.
- If app-touching: runtime validation + media captured.

## Guardrails

- Do not edit the issue body for planning/progress.
- Exactly one persistent workpad per issue.
- Temporary proof edits must be reverted before commit.
- If no workpad exists when blocked: add one blocker comment (blocker, impact, unblock action).
- Out-of-scope discoveries → separate Backlog issue, not scope expansion.
- In `In Review`: no changes. In terminal states (`Done`, `Canceled`, `Duplicate`): do nothing, shut down.

## Blocked-access escape hatch

- GitHub is **not** a default blocker. Try fallbacks (alternate remote/auth mode), document in workpad.
- Non-GitHub missing tool/auth: move to `In Review` with blocker brief in workpad (what's missing, why it blocks, exact unblock action).
- This is the one intentional exception to "no next steps for user" — keep the brief action-oriented and in the workpad only.

## Prerequisite

Linear MCP or `linear_graphql` tool must be available. If absent, stop and follow the blocked-access escape hatch (record blocker instead of asking the user).
