---
name: debug
description:
  Investigate stuck runs and execution failures by tracing Symphony and coding-agent
  logs with issue/session identifiers; use when runs stall, retry repeatedly, or
  fail unexpectedly.
---

# Debug

## Goals

- Find why a run is stuck, retrying, or failing.
- Correlate Linear issue identity to an agent session quickly (adapter-dependent).
- Read the right logs in the right order to isolate root cause.

## Log Sources

Issue-execution runs invoke the Cursor CLI as configured in `elixir/WORKFLOW.md`
(currently `cursor --model auto` under the YAML key `codex`). Adapter log lines
still correlate by `issue_identifier` / `session_id` as below.

- Primary runtime log: `log/symphony.log`
  - Default comes from `SymphonyElixir.LogFile` (`log/symphony.log`).
  - Includes orchestrator, agent runner, and coding-agent adapter lifecycle
    signals (Codex app-server emits `Codex session *` lines; Cursor/Claude
    adapters rely more on `Starting agent run for`, `Completed agent run for`,
    `Agent task *`, and `Issue stalled` lines—search by `issue_identifier` first).
- Rotated runtime logs: `log/symphony.log*`
  - Check these when the relevant run is older.

## Correlation Keys

- `issue_identifier`: human ticket key (example: `MT-625`)
- `issue_id`: Linear UUID (stable internal ID)
- `session_id`: Codex uses `<thread_id>-<turn_id>`; Cursor uses an opaque id from
  the CLI stream (still logged on turn completion—grep `session_id=` near the ticket)

`elixir/docs/logging.md` requires these fields for issue/session lifecycle logs. Use
them as your join keys during debugging.

## Quick Triage (Stuck Run)

1. Confirm scheduler/worker symptoms for the ticket.
2. Find recent lines for the ticket (`issue_identifier` first).
3. Extract `session_id` from matching lines.
4. Trace that `session_id` across start, stream, completion/failure, and stall
   handling logs.
5. Decide class of failure: timeout/stall, app-server startup failure, turn
   failure, or orchestrator retry loop.

## Commands

```bash
# 1) Narrow by ticket key (fastest entry point)
rg -n "issue_identifier=MT-625" log/symphony.log*

# 2) If needed, narrow by Linear UUID
rg -n "issue_id=<linear-uuid>" log/symphony.log*

# 3) Pull session IDs seen for that ticket
rg -o "session_id=[^ ;]+" log/symphony.log* | sort -u

# 4) Trace one session end-to-end
rg -n "session_id=<thread>-<turn>" log/symphony.log*

# 5) Focus on stuck/retry signals
rg -n "Issue stalled|scheduling retry|turn_timeout|turn_failed|Codex session failed|Codex session ended with error|Agent task exited|Agent task finished" log/symphony.log*
```

## Investigation Flow

1. Locate the ticket slice:
    - Search by `issue_identifier=<KEY>`.
    - If noise is high, add `issue_id=<UUID>`.
2. Establish timeline:
    - **Codex adapter:** first `Codex session started ... session_id=...`, then
      `Codex session completed` / `ended with error` / failure lines.
    - **Cursor (and similar) adapter:** anchor on `Starting agent run for` /
      `Completed agent run for ... session_id=` and orchestrator `Agent task *`
      lines for the same `issue_identifier`.
3. Classify the problem:
    - Stall loop: `Issue stalled ... restarting with backoff`.
    - App-server startup (Codex): `Codex session failed ...`.
    - Turn execution failure: `turn_failed`, `turn_cancelled`, `turn_timeout`, or
      `ended with error`.
    - Worker crash: `Agent task exited ... reason=...`.
4. Validate scope:
    - Check whether failures are isolated to one issue/session or repeating across
      multiple tickets.
5. Capture evidence:
    - Save key log lines with timestamps, `issue_identifier`, `issue_id`, and
      `session_id`.
    - Record probable root cause and the exact failing stage.

## Reading agent session logs

In Symphony, adapter diagnostics land in `log/symphony.log` and should be keyed
by `session_id` where the adapter emits it.

**Codex app-server lifecycle:**

1. `Codex session started ... session_id=...`
2. Stream/lifecycle events for the same `session_id`
3. Terminal: `Codex session completed ...`, `Codex session ended with error ...`,
   or `Issue stalled ... restarting with backoff`

**Cursor / short-lived CLI turns:**

1. `Starting agent run for ... issue_identifier=...`
2. `Completed agent run for ... session_id=... turn=...`
3. On failure: `Agent run failed`, `Agent task exited`, `:turn_timeout`, or
   `turn_failed` patterns from the adapter

For one specific session investigation, keep the trace narrow:

1. Capture one `session_id` for the ticket (from the lines above).
2. `rg -n "session_id=<id>" log/symphony.log*` (or ticket key first if `session_id` is noisy).
3. Mark the exact failing stage:
    - Codex startup before stream events: `Codex session failed ...`.
    - Turn/runtime failure: `turn_*` / `ended with error` / port exit / `:turn_timeout`.
    - Stall recovery: `Issue stalled ... restarting with backoff`.
4. Pair findings with `issue_identifier` and `issue_id` from nearby lines to
   confirm you are not mixing concurrent retries.

Always pair session findings with `issue_identifier`/`issue_id` to avoid mixing
concurrent runs.

## Notes

- Prefer `rg` over `grep` for speed on large logs.
- Check rotated logs (`log/symphony.log*`) before concluding data is missing.
- If required context fields are missing in new log statements, align with
  `elixir/docs/logging.md` conventions.
