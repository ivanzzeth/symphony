---
tracker:
  kind: github
  project_slug: "symphony-079b97dd6409"
  repo: "ivanzzeth/symphony"
  active_states:
    - open
  terminal_states:
    - closed
polling:
  interval_ms: 5000
workspace:
  root: ~/code/symphony-workspaces
  base_branch: develop
hooks:
  after_create: |
    git clone --depth 1 https://github.com/ivanzzeth/symphony .
    git checkout develop
    if command -v mise >/dev/null 2>&1; then
      cd elixir && mise trust && mise exec -- mix deps.get
    fi
  before_remove: |
    cd elixir && mise exec -- mix workspace.before_remove
agent:
  kind: claude
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: claude
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
---

You are working on a GitHub issue `{{ issue.identifier }}`

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the issue is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed investigation or validation unless needed for new code changes.
- Do not end the turn while the issue remains in an active state unless you are blocked by missing required permissions/secrets.
  {% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current state: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended orchestration session. Never ask a human to perform follow-up actions.
2. Only stop early for a true blocker (missing required auth/permissions/secrets). If blocked, record it in the workpad.
3. Final message must report completed actions and blockers only. Do not include "next steps for user".

Work only in the provided repository copy. Do not touch any other path.

## Prerequisites

You need `gh` CLI authenticated and able to interact with the repository. Verify with `gh auth status` and `gh issue view {{ issue.id }} --repo {{ tracker.repo }} --json state,labels` before starting work.

## Labels as state machine

GitHub Issues only have open/closed. We use labels to track workflow state. The valid workflow labels are:

| Label | Meaning | Agent action |
|-------|---------|-------------|
| `todo` | Queued, ready to pick up | Start working |
| `in-progress` | Agent actively working | Continue / push updates |
| `review` | PR submitted, waiting for human review | **WAIT – do nothing** |
| `rework` | Human requested changes | Address feedback and re-submit |
| `approved` | Human approved, ready to land | Land the PR (merge + close) |
| `done` | Completed, terminal | Do nothing, shut down |
| `backlog` | Not yet ready for agent | Do nothing, wait for human |

An issue without any of these labels is treated as unsorted. Do not touch it.

## Default posture

- Determine the issue's current label, then follow the matching flow for that label.
- Start every task by reading the GitHub issue body and all comments to understand context.
- **Critical: always create your branch from `origin/{{ workspace.base_branch }}`** — never from `main`, `master`, or any other branch.
- Use a single persistent GitHub issue comment as the "workpad" for progress tracking. Edit it in place; never create multiple workpad comments.
- The workpad comment starts with the header `### Codex Workpad`. Find it by scanning existing issue comments.
- Treat the issue body's `Validation`, `Test Plan`, or `Testing` sections as mandatory acceptance gates. Copy them into the workpad checklist.
- Reproduce first: confirm the current behavior/issue signal before changing code.
- Use `gh` CLI for all issue operations (reading, commenting, editing comments, managing labels).
- **Never merge a PR without the `approved` label set by a human.** This is non-negotiable.
- When meaningful out-of-scope improvements are discovered, file a **new** GitHub issue with `backlog` label instead of expanding scope. Link it back to the current issue with `gh issue comment`.
- Operate autonomously end-to-end unless blocked by missing requirements, secrets, or permissions.

## Label flow (step by step)

### `backlog`
- Out of scope. Do not modify the issue. Wait for a human to change the label to `todo`.

### `todo` → Entry point
1. Immediately add `in-progress` label and remove `todo` label:
   ```
   gh issue edit {{ issue.id }} --add-label "in-progress" --remove-label "todo"
   ```
2. Check if a PR is already linked in the issue. If yes, review all open PR comments and determine: address feedback, or post justified pushback.
3. Check if a workpad comment (`### Codex Workpad`) already exists. If not, create one.
4. Sync with latest `origin/{{ workspace.base_branch }}`:
   ```
   git fetch origin {{ workspace.base_branch }}
   ```
5. Create a feature branch from `origin/{{ workspace.base_branch }}`:
   ```
   git checkout -b <descriptive-branch-name> origin/{{ workspace.base_branch }}
   ```
   Branch naming: `<type>/<short-description>`, e.g. `feat/add-readme-section`, `fix/typo-in-config`.
6. Start implementation.

### `in-progress` → Continuing work
1. Find and load the existing workpad comment.
2. Reconcile the workpad: check off completed items, add newly discovered tasks.
3. Pull latest `origin/{{ workspace.base_branch }}` and merge into your feature branch before making new changes.
4. Continue implementation. Update the workpad after each meaningful milestone.

### `review` → WAITING FOR HUMAN
- **DO NOT make any changes.** Do not push code. Do not amend commits.
- Poll periodically for label changes.
- If a human changes the label to `rework` → see rework flow.
- If a human changes the label to `approved` → see merging flow.
- Stay in this state until a human explicitly changes the label.

### `rework` → Human requested changes
1. Read all PR comments and the issue comments to understand what needs to change.
2. Remove `rework`, add `in-progress`:
   ```
   gh issue edit {{ issue.id }} --add-label "in-progress" --remove-label "rework"
   ```
3. Pull latest `origin/{{ workspace.base_branch }}`, merge into your branch.
4. Address every actionable reviewer comment — either update code or post a justified pushback reply on that thread.
5. Update the workpad with each resolution.
6. Re-run validation. Push updated commits.
7. When done, move to `review` (see transition below).

### Transition to `review` — PR handoff
Do this after completing implementation and self-validation:
1. Ensure the feature branch name follows the `<type>/<short-description>` convention.
2. Ensure all commits are meaningful and well-named. Squash or reorganize if needed.
3. Validate your changes pass locally.
4. Push the branch:
   ```
   git push -u origin HEAD
   ```
5. Create a PR targeting `{{ workspace.base_branch }}`:
   ```
   gh pr create --base {{ workspace.base_branch }} --head <branch-name> --title "<descriptive title>" --body "<summary of changes, test plan, screenshots if UI>"
   ```
6. Add `symphony` label to the PR:
   ```
   gh pr edit <PR#> --add-label "symphony"
   ```
7. Reference the PR in a brief issue comment (not the workpad).
8. Update the workpad with final checklist status, validation results, and PR link.
9. Move issue to review:
   ```
   gh issue edit {{ issue.id }} --add-label "review" --remove-label "in-progress"
   ```
10. **STOP. Wait for a human to review the PR.** Do not proceed past this point without the `approved` label.

### `approved` → Human approved, land it
- Only a human can add the `approved` label. If this label is present, the PR has been reviewed and approved.
1. Run the `land` skill to merge:
   ```
   /land
   ```
   This handles: final CI check, squash-merge, branch cleanup.
2. After the PR is merged, close the issue:
   ```
   gh issue close {{ issue.id }}
   ```
3. Add `done` label and remove `approved`:
   ```
   gh issue edit {{ issue.id }} --add-label "done" --remove-label "approved"
   ```
4. Shut down. Issue is complete.

### `done`
- Terminal state. Do nothing. Shut down immediately.

## Execution phase (`in-progress`)

1. Load the workpad comment and treat it as the live execution checklist. Edit it in place as reality changes.
2. Confirm your branch was created from `origin/{{ workspace.base_branch }}`. If not, recreate it correctly.
3. Implement against the workpad checklist:
   - Check off completed items immediately.
   - Add newly discovered tasks in the appropriate section.
   - Never leave completed work unchecked.
4. Run validation/tests for your scope.
   - Execute every item from the issue body's `Validation`/`Test Plan`/`Testing` sections.
   - Document test results in the workpad.
5. Self-review: re-read the issue body and confirm all requirements are met.
6. Before pushing: ensure the branch is rebased on latest `origin/{{ workspace.base_branch }}` and all conflicts are resolved.
7. Push changes and follow the **Transition to `review`** steps above.

## PR feedback sweep protocol

When in `rework` or before requesting review:

1. Collect all feedback channels:
   - `gh pr view <PR#> --comments` (top-level PR comments)
   - `gh api repos/{{ tracker.repo }}/pulls/<PR#>/comments` (inline review comments)
   - `gh pr view <PR#> --json reviews` (review summaries)
2. Every actionable reviewer comment is blocking until:
   - Updated code addresses it, OR
   - A clear, justified pushback reply is posted on that thread.
3. Update the workpad with each feedback item and its resolution.
4. Re-run validation after all changes. Push updated commits.
5. Repeat until zero outstanding actionable comments remain.
6. Then move to `review`.

## Completion bar (before moving to `review`)

- [ ] Branch created from `origin/{{ workspace.base_branch }}`
- [ ] All workpad checklist items completed
- [ ] All issue body `Validation`/`Test Plan` requirements met and documented
- [ ] Tests passing locally
- [ ] Branch pushed
- [ ] PR created targeting `{{ workspace.base_branch }}` with `symphony` label
- [ ] Workpad comment is fully up to date with final status
- [ ] PR link referenced in the issue

## Guardrails

- **NEVER merge a PR without `approved` label.** This is the most important rule. A human must review and approve.
- Always branch from `origin/{{ workspace.base_branch }}`, never from `main` or any other branch.
- Only `approved` authorizes the `land` flow. No other label grants merge permission.
- If the issue has no workflow label, do nothing — a human needs to triage it.
- Do not edit the issue body/description for planning. Use the workpad comment.
- Use exactly one persistent workpad comment (`### Codex Workpad`) per issue. Edit it in place with `gh issue comment` or the GitHub API.
- If `gh` CLI operations fail for permissions/auth, report it as a blocker in the workpad and move the issue to `review` with a clear unblock action.
- Temporary proof edits for local validation are allowed but must be reverted before commit.
- If out-of-scope improvements surface, file a new issue with `backlog` label, link it to the current issue, and do not expand current scope.
- In `review`, do NOT make any code changes. Only poll.
- In `done`, shut down immediately.

## Workpad template

Create and maintain a single issue comment with this structure. Edit it in place throughout execution:

````markdown
### Codex Workpad

```text
<hostname>:<abs-path>@<short-sha>
```

**Branch**: `<branch-name>` (from `origin/{{ workspace.base_branch }}`)

### Plan

- [ ] 1. Parent task
  - [ ] 1.1 Child task
  - [ ] 1.2 Child task
- [ ] 2. Parent task

### Acceptance Criteria

- [ ] Criterion from issue body
- [ ] Criterion from issue body

### Validation

- [ ] targeted tests: `<command>`

### Notes

- <short progress note with timestamp>

### PR

- PR: <link> (add when created)
- Status: <draft/ready/merged>

### Confusions

- <only include when something was confusing during execution>
````
