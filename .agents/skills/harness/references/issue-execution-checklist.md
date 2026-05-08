# Issue execution — PR & review gates (Symphony)

Condensed from `elixir/WORKFLOW.md` for agents loading skills without the full
prompt. Authoritative text remains in **WORKFLOW.md**; this file is a checklist
only.

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

## Completion bar (reminder)

- Workpad `Plan` / `Acceptance Criteria` / `Validation` match completed work.
- Ticket `Validation` / `Test Plan` / `Testing` sections executed and checked off.
- PR checks green; PR linked on issue; label **`symphony`**; base **`develop`**.
- App-touching: **`launch-app`** and **`github-pr-media`** per WORKFLOW **App
  runtime validation** section.
- Optional `### Confusions` in workpad when execution was unclear.

## After squash-merge (`Merging` → `Done`)

Follow `.agents/skills/land/SKILL.md` and its watcher loop. When the PR is
merged, move the Linear issue to **`Done`** via `issueUpdate` with the completed
state id (use `linear` skill / `linear_graphql`).
