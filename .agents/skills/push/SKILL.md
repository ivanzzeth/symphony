---
name: push
description:
  Push current branch changes to origin and create or update the corresponding
  pull request; use when asked to push, publish updates, or create pull request.
---

# Push

## Symphony issue execution (unattended)

When this skill runs inside the Linear issue-execution flow (`elixir/WORKFLOW.md`), the session is **unattended**: do not ask the human for follow-ups. Surface blockers in the `## Codex Workpad` per WORKFLOW. Every PR must **target `develop`** and include the **`symphony`** label (`gh pr create ... -l symphony` or `gh pr edit --add-label symphony`). For GitHub auth/push failures, WORKFLOW treats GitHub as **not** a default blocker: try reasonable fallbacks (alternate credential helper, re-auth flow, documented remote variants), document each attempt in the workpad, then only stop as a true blocker if nothing works.

## Prerequisites

- `gh` CLI is installed and available in `PATH`.
- `gh auth status` succeeds for GitHub operations in this repo.

## Goals

- Push current branch changes to `origin` safely.
- Create a PR if none exists for the branch, otherwise update the existing PR.
- Keep branch history clean when remote has moved.

## Related Skills

- `pull`: use this when push is rejected or sync is not clean (non-fast-forward,
  merge conflict risk, or stale branch).

## Steps

1. Identify current branch and confirm remote state.
2. Run local validation (`cd elixir && mise exec -- mix test`) before pushing.
3. Push branch to `origin` with upstream tracking if needed, using whatever
   remote URL is already configured.
4. If push is not clean/rejected:
   - If the failure is a non-fast-forward or sync problem, run the `pull`
     skill to merge `origin/develop`, resolve conflicts, and rerun validation.
   - Push again; use `--force-with-lease` only when history was rewritten.
   - If the failure is due to auth, permissions, or workflow restrictions on
     the configured remote, try **documented fallbacks** first (WORKFLOW
     blocked-access posture for GitHub), log each attempt in the workpad, then
     stop with the exact error only if no safe path remains—do not silently
     rewrite remotes or weaken security without recording rationale.

5. Ensure a PR exists for the branch:
   - If no PR exists, create one with `--base develop` (or the repo’s configured
     `workspace.base_branch`, which is `develop` for Symphony).
   - If a PR exists and is open, update it.
   - If branch is tied to a closed/merged PR, create a new branch + PR.
   - Ensure the **`symphony`** label is present on the PR (add on create or via
     `gh pr edit --add-label symphony`).
   - Write a proper PR title that clearly describes the change outcome
   - For branch updates, explicitly reconsider whether current PR title still
     matches the latest scope; update it if it no longer does.
6. Write/update PR body explicitly using `.github/pull_request_template.md`:
   - Fill every section with concrete content for this change.
   - Replace all placeholder comments (`<!-- ... -->`).
   - Keep bullets/checkboxes where template expects them.
   - If PR already exists, refresh body content so it reflects the total PR
     scope (all intended work on the branch), not just the newest commits,
     including newly added work, removed work, or changed approach.
   - Do not reuse stale description text from earlier iterations.
7. Validate PR body with `mix pr_body.check` and fix all reported issues.
8. Reply with the PR URL from `gh pr view` (orchestrator/session output is fine;
   do **not** paste the PR URL into the Linear `## Codex Workpad` body—link the PR
   on the issue per WORKFLOW).

## Commands

```sh
# Identify branch
branch=$(git branch --show-current)

# Minimal validation gate
cd elixir && mise exec -- mix test

# Initial push: respect the current origin remote.
git push -u origin HEAD

# If that failed because the remote moved, use the pull skill. After
# pull-skill resolution and re-validation, retry the normal push:
git push -u origin HEAD

# If the configured remote rejects the push for auth, permissions, or workflow
# restrictions, stop and surface the exact error.

# Only if history was rewritten locally:
git push --force-with-lease origin HEAD

# Ensure a PR exists (create only if missing)
pr_state=$(gh pr view --json state -q .state 2>/dev/null || true)
if [ "$pr_state" = "MERGED" ] || [ "$pr_state" = "CLOSED" ]; then
  echo "Current branch is tied to a closed PR; create a new branch + PR." >&2
  exit 1
fi

# Write a clear, human-friendly title that summarizes the shipped change.
pr_title="<clear PR title written for this change>"
if [ -z "$pr_state" ]; then
  gh pr create --base develop --head "$branch" -l symphony --title "$pr_title"
else
  # Reconsider title on every branch update; edit if scope shifted.
  gh pr edit --title "$pr_title"
  gh pr edit --add-label symphony 2>/dev/null || true
fi

# Write/edit PR body to match .github/pull_request_template.md before validation.
# Example workflow:
# 1) open the template and draft body content for this PR
# 2) gh pr edit --body-file /tmp/pr_body.md
# 3) for branch updates, re-check that title/body still match current diff

tmp_pr_body=$(mktemp)
gh pr view --json body -q .body > "$tmp_pr_body"
(cd elixir && mise exec -- mix pr_body.check --file "$tmp_pr_body")
rm -f "$tmp_pr_body"

# Show PR URL for the reply
gh pr view --json url -q .url
```

## Notes

- Do not use `--force`; only use `--force-with-lease` as the last resort.
- Distinguish sync problems from remote auth/permission problems:
  - Use the `pull` skill for non-fast-forward or stale-branch issues.
  - Surface auth, permissions, or workflow restrictions directly instead of
    changing remotes or protocols.
