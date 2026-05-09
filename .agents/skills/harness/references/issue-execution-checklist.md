# Issue execution — PR & review gates (Symphony)

Condensed from `elixir/WORKFLOW.md` for agents loading skills without the full
prompt. Authoritative text remains in **WORKFLOW.md**; this file is a checklist
only.

## Step 0 — branch and PR hygiene

- If a PR already exists for the current branch and GitHub reports it as
  **`CLOSED`** or **`MERGED`**, treat prior branch work as **non-reusable** for
  this run: create a **fresh branch** from `origin/develop` and restart kickoff
  (pull, workpad, plan) as a new attempt.

## Workpad environment stamp

- At the top of `## Codex Workpad`, include one fenced `text` line:
  `<hostname>:<abs-path>@<short-sha>` (WORKFLOW Step 1). Do **not** duplicate
  metadata already on the Linear issue (issue id, status, branch, PR link).

## Temporary proof edits

- WORKFLOW allows temporary local edits to validate assumptions (for example
  tweak a build input or a UI path). **Revert all proof edits** before
  `commit` / `push`. Record what you tried and the outcome in workpad
  `Validation` / `Notes`.

## PR feedback sweep (before `In Review`)

When the ticket has an attached PR, run **all** of the following until nothing
actionable remains:

1. Resolve PR number from issue links/attachments.
2. Collect feedback:
   - `gh pr view <pr> --comments`
   - `gh api repos/<owner>/<repo>/pulls/<pr>/comments` (inline reviews)
   - `gh pr view <pr> --json reviews`
3. Every actionable comment (human or bot, including inline) is blocking until
   addressed in code/tests/docs **or** an explicit, justified pushback exists on
   that thread.
4. Mirror each item and its status in the Linear `## Codex Workpad` plan/checklist.
5. Re-run validation after changes; repeat until clean.

## Manual QA Plan

If the PR has a **Manual QA Plan** comment, read it before moving to `In Review`
and use it to sharpen UI/runtime coverage.

## Blocked-access brief (non-GitHub tools/auth)

When moving to `In Review` under the escape hatch, the workpad blocker brief
must be concise and include:

- what is missing,
- why it blocks required acceptance/validation,
- exact human action needed to unblock.

GitHub access is **not** a default blocker—try documented fallbacks first and
record attempts in the workpad.

## Completion bar (reminder)

- Workpad `Plan` / `Acceptance Criteria` / `Validation` match completed work.
- Ticket `Validation` / `Test Plan` / `Testing` sections executed and checked off.
- PR checks green; PR linked on issue; label **`symphony`**; base **`develop`**.
- App-touching: run **`launch-app`** validation and capture/upload media via
  **`github-pr-media`** before handoff (WORKFLOW Step 2 and Completion bar).
- Optional `### Confusions` in workpad when execution was unclear.

## After squash-merge (`Merging` → `Done`)

Follow `.agents/skills/land/SKILL.md` and its watcher loop. When the PR is
merged, move the Linear issue to **`Done`** via `issueUpdate` with the completed
state id (use `linear` skill / `linear_graphql`).
