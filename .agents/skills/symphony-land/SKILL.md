---
name: symphony-land
description:
  Land a PR by monitoring conflicts, resolving them, waiting for checks, and
  squash-merging when green; use when asked to land, merge, or shepherd a PR to
  completion. Also handles PR feedback sweep.
---

# Land

## Configuration (from WORKFLOW.md context)

- `repo_owner`: GitHub repo owner (e.g. `ivanzzeth`)
- `repo_name`: GitHub repo name (e.g. `symphony`)
- `base_branch`: target branch (e.g. `develop`)

These are injected by WORKFLOW.md. The skill reads them as session context.

## Modes

The land skill has two entry points:

| Mode | Trigger | What it does |
|------|---------|-------------|
| `sweep` | Before `In Review` | Gather PR feedback, address or push back, revalidate |
| `merge` | Issue in `Merging` | Full land loop: check CI, squash-merge, transition to Done |

---

## PR Feedback Sweep (`sweep` mode)

Run this before moving a ticket to `In Review` whenever a PR is attached.

1. Identify the PR number from issue links/attachments.
2. Gather feedback from all channels:
   - Top-level PR comments (`gh pr view --comments`).
   - Inline review comments (`gh api repos/<owner>/<repo>/pulls/<pr>/comments`).
   - Review summaries/states (`gh pr view --json reviews`).
3. Treat every actionable comment (human or bot) as blocking until one of:
   - code/test/docs updated to address it, or
   - explicit, justified pushback reply posted on that thread.
4. Update the workpad plan/checklist with each feedback item and resolution status.
5. Re-run validation after feedback-driven changes and push updates.
6. Repeat until no outstanding actionable comments remain.

---

## Merge Loop (`merge` mode)

### Preconditions

- `gh` CLI is authenticated.
- You are on the PR branch with a clean working tree.

### Steps

1. Locate the PR for the current branch.
2. Confirm validation is green locally before any push.
3. If uncommitted changes exist, commit with `commit`, push with `push`.
4. Check mergeability and conflicts against `base_branch`.
5. If conflicts: run `pull` to merge `origin/<base_branch>`, resolve, then `push`.
6. Ensure review comments are acknowledged and addressed (see Review Handling below).
7. Watch checks until complete — prefer `python3 .agents/skills/symphony-land/land_watch.py`.
8. If checks fail: pull logs, fix, commit, push, re-run checks.
9. When all green and feedback addressed: squash-merge using PR title/body.
10. After merge: transition the Linear issue to `Done` via `linear` skill.

### Async Watch Helper

```
python3 .agents/skills/symphony-land/land_watch.py
```

Exit codes:
- 2: Review comments detected (address feedback)
- 3: CI checks failed
- 4: PR head updated (autofix commit detected)

### Commands

```sh
# Branch and PR context
branch=$(git branch --show-current)
pr_number=$(gh pr view --json number -q .number)
pr_title=$(gh pr view --json title -q .title)
pr_body=$(gh pr view --json body -q .body)

# Check mergeability
mergeable=$(gh pr view --json mergeable -q .mergeable)
if [ "$mergeable" = "CONFLICTING" ]; then
  # Run pull → resolve → push
fi

# Watch checks
if ! gh pr checks --watch; then
  gh pr checks
  exit 1
fi

# Squash-merge
gh pr merge --squash --subject "$pr_title" --body "$pr_body"
```

### Failure Handling

- Checks fail: inspect logs with `gh pr checks` / `gh run view --log`, fix locally, commit+push, re-run.
- Flaky failures: use judgment — may proceed without fixing a clear flake.
- Auto-fix commit from CI: pull locally, merge `origin/<base_branch>`, add a real commit, force-push to retrigger CI.
- Mergeability `UNKNOWN`: wait and re-check.
- Do not enable auto-merge; this repo has no required checks.

### Review Handling

- Codex reviews: arrive as issue comments starting with `## Codex Review — <persona>`. Acknowledge before merge.
- Human review comments: blocking — respond and resolve before merging.
- Fetch review comments:
  ```sh
  gh api repos/<owner>/<repo>/pulls/"$pr_number"/comments           # inline
  gh api repos/<owner>/<repo>/issues/"$pr_number"/comments          # top-level
  ```
- Reply to inline review comments:
  ```sh
  gh api -X POST /repos/<owner>/<repo>/pulls/"$pr_number"/comments \
    -f body='[codex] <response>' -F in_reply_to=$comment_id
  ```
- All GitHub comments from this agent must be prefixed with `[codex]`.
- For each comment, choose: **accept**, **clarify**, or **push back**. Reply before changing code.
- When accepting feedback, include one-line rationale.
- When declining, offer alternative or follow-up trigger.
- Prefer a single consolidated "review addressed" comment after a batch of fixes.

### Scope & PR Metadata

- PR title/description must reflect full scope, not just the latest fix.
- Classify each review comment as: correctness, design, style, clarification, scope.
- For correctness feedback: provide concrete validation before closing.
- Correctness issues must be addressed. If deferring/declining, validate first and explain why.

## Notes

- The `pull` and `push` skills are called within the loop — do not call `gh pr merge` directly.
- Remote branches auto-delete on merge in this repo.
