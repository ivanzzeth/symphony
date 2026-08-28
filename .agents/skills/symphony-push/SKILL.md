---
name: push
description:
  Push current branch changes to origin and create or update the corresponding
  pull request; use when asked to push, publish updates, or create pull request.
---

# Push

## Configuration (from WORKFLOW.md context)

- `test_command`: validation command before push (e.g. `cd elixir && mise exec -- mix test`)
- `base_branch`: target branch for PRs (e.g. `develop`)
- `pr_label`: GitHub label for PRs (e.g. `symphony`)

These are injected by WORKFLOW.md. The skill reads them as session context.

## Goals

- Push current branch changes to `origin` safely.
- Create a PR if none exists for the branch, otherwise update the existing PR.
- Keep branch history clean when remote has moved.

## Related Skills

- **`pull`** (alias dir: `symphony-pull/`): use when push is rejected (non-fast-forward, stale branch).
- **`commit`** (alias dir: `symphony-commit/`): use to create clean commits before pushing.

## Steps

1. Identify current branch and confirm remote state.
2. Run `<test_command>` before pushing. If it fails, fix and re-run until green.
3. Push branch to `origin` with upstream tracking if needed.
4. If push is rejected:
   - Non-fast-forward or sync problem: run **`pull`** to merge `origin/<base_branch>`, resolve conflicts, rerun validation, push again.
   - For `--force-with-lease`: use only when history was intentionally rewritten.
   - Auth/permissions failures: try documented fallbacks per WORKFLOW blocked-access posture, log attempts in workpad, then stop with exact error only if no safe path remains.
5. Ensure a PR exists for the branch:
   - No PR exists: create one with `--base <base_branch>`.
   - PR exists and is open: update it.
   - Branch tied to a closed/merged PR: create a fresh branch from `origin/<base_branch>` and a new PR.
6. Write a clear PR title describing the change outcome. On branch updates, reconsider if the title still matches scope.
7. Write/update PR body using `.github/pull_request_template.md`:
   - Fill every section with concrete content.
   - Replace placeholder comments (`<!-- ... -->`).
   - On updates, refresh body to reflect total PR scope.
8. Reply with the PR URL from `gh pr view` (do not paste into workpad body — link the PR on the Linear issue per WORKFLOW).

## Commands

```sh
# Identify branch
branch=$(git branch --show-current)

# Validation gate
<test_command>

# Initial push
git push -u origin HEAD

# If rejected (non-fast-forward): run pull first, then retry
git push -u origin HEAD

# Only if history was rewritten locally:
git push --force-with-lease origin HEAD

# Set PR title — write a human-readable title describing this change
pr_title="<clear PR title for this change>"

# Ensure a PR exists
pr_state=$(gh pr view --json state -q .state 2>/dev/null || true)
if [ "$pr_state" = "MERGED" ] || [ "$pr_state" = "CLOSED" ]; then
  # Branch tied to closed/merged PR — create fresh branch from <base_branch>
  git checkout origin/<base_branch>
  git checkout -b "fix/<linear-issue-key>-rework"
  # Then create a new PR
  gh pr create --base <base_branch> --head "$(git branch --show-current)" -l <pr_label> --title "$pr_title"
elif [ -z "$pr_state" ]; then
  gh pr create --base <base_branch> --head "$branch" -l <pr_label> --title "$pr_title"
else
  gh pr edit --title "$pr_title"
  gh pr edit --add-label <pr_label> 2>/dev/null || true
fi

# Show PR URL
gh pr view --json url -q .url
```

## Notes

- Do not use `--force`; only `--force-with-lease` as last resort.
- Distinguish sync problems (use the **`pull`** skill; alias dir `symphony-pull/`) from auth/permissions problems (document fallbacks, then stop).
