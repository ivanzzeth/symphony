---
name: commit
description:
  Create a well-formed git commit from current changes using session history for
  rationale and summary; use when asked to commit, prepare a commit message, or
  finalize staged work.
---

# Commit

## Goals

- Produce a commit that reflects the actual code changes and the session
  context.
- Follow common git conventions (type prefix, short subject, wrapped body).
- Include both summary and rationale in the body.

## Inputs

- Coding-agent session history (Cursor / Claude / Codex, depending on deployment)
  for intent and rationale.
- `git status`, `git diff`, and `git diff --staged` for actual changes.
- Repo-specific commit conventions if documented.

## Steps

1. Read session history to identify scope, intent, and rationale.
2. Inspect the working tree and staged changes (`git status`, `git diff`,
   `git diff --staged`).
3. Stage intended changes, including new files (`git add -A`) after confirming
   scope.
4. Sanity-check newly added files; if anything looks random or likely ignored
   (build artifacts, logs, temp files), flag it to the user before committing.
5. If staging is incomplete or includes unrelated files, fix the index or ask
   for confirmation.
6. Choose a conventional type and optional scope that match the change (e.g.,
   `feat(scope): ...`, `fix(scope): ...`, `refactor(scope): ...`).
7. Write a subject line in imperative mood, <= 72 characters, no trailing
   period.
8. Write a body that includes:
   - Summary of key changes (what changed).
   - Rationale and trade-offs (why it changed).
   - Tests or validation run (or explicit note if not run).
9. Append a `Co-authored-by` trailer using the project's configured identity
   (match the active CLI in WORKFLOW.md—for Cursor-backed runs the orchestrator
   uses `cursor --model auto`; use the team's Cursor co-author line if documented;
   otherwise follow repo AGENTS.md / commit conventions).
10. Wrap body lines at 72 characters.
11. Create the commit message with a here-doc or temp file and use
    `git commit -F <file>` so newlines are literal (avoid `-m` with `\n`).
12. Commit only when the message matches the staged changes: if the staged diff
    includes unrelated files or the message describes work that isn't staged,
    fix the index or revise the message before committing.

## Symphony issue execution (`elixir/WORKFLOW.md`)

Unattended Linear runs may use **temporary local proof edits** to validate
assumptions (WORKFLOW Step 2). **Revert every proof edit** before staging or
committing. Document what you tried and observed in the workpad `Validation` /
`Notes` sections. Never leave proof-only changes in commits.

**Unattended posture (WORKFLOW Instructions):** Do **not** ask the human to
confirm staging scope or wait on interactive prompts. If the index looks wrong
(suspicious paths, unrelated files), fix `git add` / revert noise yourself. Only
stop for a **true blocker**—record it in `## Codex Workpad` and transition the
issue per WORKFLOW (including blocked-access escape hatch when applicable)—do
not pause for “flag to user” / “ask for confirmation” from generic steps above.

## Output

- A single commit created with `git commit` whose message reflects the session.

## Template

Type and scope are examples only; adjust to fit the repo and changes.

```
<type>(<scope>): <short summary>

Summary:
- <what changed>
- <what changed>

Rationale:
- <why>
- <why>

Tests:
- <command or "not run (reason)">

Co-authored-by: <identity per project convention>
```
