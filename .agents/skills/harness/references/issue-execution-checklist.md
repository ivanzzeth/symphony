# Issue execution — PR & review gates (Symphony)

Condensed from `elixir/WORKFLOW.md` for agents loading skills without the full
prompt. Authoritative text remains in **WORKFLOW.md**; this file is a checklist
only.

## Default posture (WORKFLOW)

- Start by determining the ticket’s **current status**, then follow the matching flow.
- **Workpad-first:** open the tracking **`## Codex Workpad`** and bring it up to date **before** new implementation work (every task / continuation).
- Invest up front in **planning** and **verification design**.
- **Reproduce first:** confirm the current behavior or issue signal **before** changing code so the fix target is explicit.
- Keep **ticket metadata** current: **state**, **checklist**, **acceptance criteria**, and **links**—while keeping **all** planning and progress in the workpad, **not** the issue description (Guardrails).
- Mirror ticket-authored **`Validation`**, **`Test Plan`**, or **`Testing`** sections into the workpad and treat them as non-negotiable acceptance input (Default posture).

## Step 0 — branch and PR hygiene

- If a PR already exists for the current branch and GitHub reports it as
  **`CLOSED`** or **`MERGED`**, treat prior branch work as **non-reusable** for
  this run: create a **fresh branch** from `origin/develop` and restart kickoff
  (pull, workpad, plan) as a new attempt.

## Todo kickoff sequencing (WORKFLOW Step 0)

For issues arriving in **`Todo`**, run startup in this **exact** order before
substantive analysis or implementation:

1. Transition the issue to **`In Progress`** (`issueUpdate` / equivalent).
2. Find or bootstrap the single **`## Codex Workpad`** comment (ignore resolved
   comments when searching).
3. Only then begin planning, reproduction, or code work.

If a **`Todo`** ticket already has a PR attached at kickoff, treat it as a
feedback loop: run the **PR feedback sweep** early (see below and WORKFLOW
Status map / Step 2) before new feature work.

## Continuation / retry attempts

When the orchestrator injects **continuation** context (retry attempt number,
“resume from current workspace,” do not repeat completed work), honor it:
resume from the live workpad and branch state, avoid redoing finished
investigation or validation unless a new change invalidates it, and do not stop
while the issue is still in an **active** workflow state except for true
blockers (missing required auth/secrets)—per WORKFLOW default posture.

## Step 0 — inconsistent state vs issue content (WORKFLOW Step 0 §6)

When Linear **workflow state** and **issue content or attachments** look inconsistent,
post a **short** Linear comment documenting the mismatch, then pick the **safest**
Step 0 routing branch from WORKFLOW—do not silently assume one interpretation.

## Unattended session output (WORKFLOW Instructions)

- Final agent message must report **completed actions** and **blockers only**.
- Do **not** include open-ended “next steps for user” prompts.
- **`commit` / `pull` / `land` skills** include Symphony-specific overrides: no interactive confirmation loops—document decisions in `## Codex Workpad` and follow blocked-access / state rules instead.

## Single workpad — no extra completion comments (WORKFLOW Default posture)

- Use the one **`## Codex Workpad`** comment for **all** progress and handoff notes.
- Do **not** post separate “done” or summary comments outside that workpad.

## Ticket metadata vs issue description (WORKFLOW Default posture + Guardrails)

- Keep **ticket metadata** current during execution: **state**, **checklist**, **acceptance criteria**, **links** (including PR attachments), and labels when required.
- Do **not** edit the issue **body/description** for planning or progress tracking; use **`## Codex Workpad`** for that (Guardrails).

## Execution checklist hygiene (WORKFLOW Step 2)

- Never leave **completed** work unchecked in the workpad plan—keep checkboxes aligned with reality after each milestone.

## `In Review` — freeze (WORKFLOW Step 3)

While **`In Review`**: do **not** write implementation code and do **not** change
**ticket content** (WORKFLOW wording—covers issue fields and any edits used for
planning/progress outside the permitted workpad pattern). Wait and poll GitHub/Linear for review outcomes;
follow WORKFLOW-permitted transitions only (for example human approval → `Merging`,
or required fixes → `Rework`).

## Blocked before workpad exists (WORKFLOW Guardrails)

If blocked and **no** workpad exists yet, add **one** concise blocker comment on the issue describing the blocker, impact, and the next unblock action (then follow blocked-access rules when moving states).

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
