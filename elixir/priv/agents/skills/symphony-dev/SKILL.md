---
name: symphony-dev
description: >
  FULL-Stack Elixir development orchestrator for the Symphony codebase at
  elixir/. Performs end-to-end feature development: PLAN (analyze requirements,
  explore codebase, produce task breakdown) → DEVELOP (implement Elixir code
  changes following project conventions) → TEST + BUILD in parallel (run
  ExUnit tests with coverage, compile escript) → REVIEW (quality check with
  severity-graded findings). MUST use this skill for ANY Symphony Elixir
  development work: implementing new features, fixing bugs, refactoring
  modules, adding tests, or improving the orchestrator codebase. Also handles
  follow-up work: re-run, re-do, partial re-execution, modify results, update
  implementation, improve based on previous output, re-test after fixes,
  re-build after changes, re-review after fixes. This is the primary
  development workflow for the Symphony project. Does NOT cover issue
  execution (use the Symphony Issue Execution harness for Linear ticket
  processing). TRIGGERS on: "implement X in elixir", "add feature to symphony",
  "fix bug in the orchestrator", "refactor module", "write tests for",
  "build the escript", "review code changes", "update the elixir code",
  "symphony development", "code review the changes", "run the test suite".
  Exclusions: does NOT handle Linear ticket dispatch (use the Issue Execution
  harness), does NOT handle infrastructure/daemon config (symphony.yaml).
---

# Symphony Development Orchestrator

Orchestrates the full development lifecycle for the Symphony Elixir codebase. This skill coordinates 5 specialized agents in a pipeline+fan-out pattern: Plan → Develop → (Test + Build in parallel) → Review.

## Execution Mode: Sub-Agent (Pipeline)

Each phase runs sequentially, building on the previous phase's output. Test and Build run in parallel after development.

## Agent Configuration

| Agent | subagent_type | Role | Output |
|-------|--------------|------|--------|
| symphony-planner | general-purpose | Requirements analysis & task breakdown | `_workspace/01_planner_plan.md` |
| symphony-developer | general-purpose | Elixir implementation | `_workspace/03_developer_progress.md` + code changes |
| symphony-tester | general-purpose | ExUnit tests & coverage | `_workspace/02_tester_report.md` |
| symphony-builder | general-purpose | Mix escript build | `_workspace/04_builder_report.md` |
| symphony-reviewer | general-purpose | Code quality review | `_workspace/05_reviewer_report.md` |

## Workflow

### Phase 0: Context Detection (Follow-up Support)

Check for existing outputs to determine execution mode:

1. Check if `_workspace/` directory exists
2. Determine execution mode:
   - **`_workspace/` absent** → Initial run. Proceed to Phase 1
   - **`_workspace/` exists + partial re-run requested** → Partial re-run. Identify which phases to re-run from the user's request. Preserve existing outputs for unaffected phases. Re-invoke only the affected agents with context from prior outputs.
   - **`_workspace/` exists + new input** → Fresh run. Move existing `_workspace/` to `_workspace_prev_YYYYMMDD_HHMMSS/`, then start Phase 1
3. For partial re-run: include paths to previous outputs in agent prompts so they can read and improve upon existing work

### Phase 1: Plan

1. Read the user's development request, feature description, or bug report
2. Create `_workspace/` directory
3. Launch the planner agent with `model: "opus"`:
   ```
   Agent(
     subagent_type: "general-purpose",
     model: "opus",
     prompt: "Read and follow the agent definition at .agents/agents/symphony-planner.md.
              Read and load the skill at .agents/skills/elixir-planner/SKILL.md.
              Analyze this request: {user request}.
              Explore the codebase at elixir/lib/ to identify affected modules.
              Produce an implementation plan at _workspace/01_planner_plan.md"
   )
   ```
4. Read `_workspace/01_planner_plan.md` and present the summary to the user
5. Wait for user approval or adjustments before proceeding (for simple/well-defined tasks, proceed directly)

### Phase 2: Develop

1. Read the plan from `_workspace/01_planner_plan.md`
2. Launch the developer agent (use `isolation: "worktree"` for any implementation that writes files):
   ```
   Agent(
     subagent_type: "general-purpose",
     model: "opus",
     isolation: "worktree",
     prompt: "Read and follow the agent definition at .agents/agents/symphony-developer.md.
              Read and load the skill at .agents/skills/elixir-developer/SKILL.md.
              Implementation plan is at _workspace/01_planner_plan.md.
              Implement the changes described in the plan. Work only inside elixir/.
              Track progress at _workspace/03_developer_progress.md.
              Write tests alongside implementation code."
   )
   ```
3. Read `_workspace/03_developer_progress.md` to verify completion

### Phase 3: Test & Build (Parallel)

Launch tester and builder in parallel:

**Tester:**
```
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Read and follow the agent definition at .agents/agents/symphony-tester.md.
           Read and load the skill at .agents/skills/elixir-tester/SKILL.md.
           Code changes have been made by symphony-developer.
           Run tests, diagnose failures, check coverage.
           Report results at _workspace/02_tester_report.md."
)
```

**Builder:**
```
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Read and follow the agent definition at .agents/agents/symphony-builder.md.
           Read and load the skill at .agents/skills/elixir-builder/SKILL.md.
           Code changes have been made by symphony-developer.
           Build the escript, resolve any compilation issues.
           Report results at _workspace/04_builder_report.md."
)
```

Wait for both to complete. Read both reports.

**Critical: Always check result and error fields on both agents.** An agent can return "completed" while its work stopped mid-task. If the worktree path is returned from the developer agent, check `elixir/test` in the worktree to verify changes exist.

**Fix Loop:** If tester or builder reports failures, re-invoke the developer agent to fix issues (inside the same worktree if one was created):
```
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Read .agents/agents/symphony-developer.md.
           Read _workspace/02_tester_report.md and _workspace/04_builder_report.md.
           Fix all reported issues. Update _workspace/03_developer_progress.md.
           Then re-run tester and builder until both pass."
)
```
Repeat the fix loop (max 3 iterations) until both test and build pass.

### Phase 4: Review

1. Launch the reviewer agent (if a worktree was created in Phase 2, pass the worktree path in the prompt):
   ```
   Agent(
     subagent_type: "general-purpose",
     model: "opus",
     prompt: "Read and follow the agent definition at .agents/agents/symphony-reviewer.md.
              Read and load the skill at .agents/skills/elixir-reviewer/SKILL.md.
              Review the code changes made in this session.
              Read _workspace/02_tester_report.md and _workspace/04_builder_report.md for context.
              Produce a severity-graded review at _workspace/05_reviewer_report.md."
   )
   ```
2. Read `_workspace/05_reviewer_report.md`
3. If CRITICAL or HIGH issues found: re-invoke developer to fix, then re-run Phase 3 (test+build) and Phase 4 (review)
4. Present final summary to user with all reports

### Phase 5: Cleanup

1. Preserve `_workspace/` directory (intermediate outputs kept for audit trail)
2. Report results to the user with a summary of what was accomplished, test results, build status, and review findings

## Data Flow

```
User Request
     │
     ▼
[Phase 1: symphony-planner] ──→ _workspace/01_planner_plan.md
     │
     ▼
[Phase 2: symphony-developer] ──→ _workspace/03_developer_progress.md
     │                             (code changes in elixir/)
     │
     ├──▶ [Phase 3a: symphony-tester] ──→ _workspace/02_tester_report.md
     │
     └──▶ [Phase 3b: symphony-builder] ──→ _workspace/04_builder_report.md
     │
     ▼
[Phase 4: symphony-reviewer] ──→ _workspace/05_reviewer_report.md
     │
     ▼
   Summary to User
```

## Error Handling

| Situation | Strategy |
|-----------|----------|
| Planner output is rejected | Present to user for clarification, re-run Phase 1 with refined input |
| Developer fails mid-implementation | Read progress file, diagnose, re-invoke with context of what was completed |
| Tests fail | Report failures → fix loop (max 3 iterations) → if still failing, report to user with details |
| Build fails | Diagnose compilation error → fix loop → if still failing, expand the fix to include build config changes |
| Reviewer finds CRITICAL issues | Mandatory fix loop: fix → test+build → re-review |
| Agent times out | Collect partial results, proceed to next phase if core output exists |
| Partial re-run | Only re-invoke the phases requested, pass prior outputs as context |
| WORKFLOW.md modification requested | BLOCK — this file is the Symphony execution contract and must not be modified. Inform the user. |

## Test Scenarios

### Normal Flow
1. User requests a new feature or bug fix for the Symphony Elixir codebase
2. Phase 1: Planner analyzes requirements, explores codebase, produces plan at `_workspace/01_planner_plan.md`
3. Phase 2: Developer implements changes in `elixir/`, tracks progress
4. Phase 3: Tester runs `mix test` with coverage, Builder compiles escript — both in parallel
5. Phase 4: Reviewer evaluates code quality, produces severity-graded report
6. Phase 5: Cleanup and final summary
7. Expected: All phases complete with passing tests, clean build, and no critical review issues

### Error Flow
1. Phase 2: Developer completes implementation
2. Phase 3a: Tester finds 2 failing tests
3. Fix loop triggered: Developer fixes issues, tester re-runs
4. Phase 3b: Builder reports compilation warning
5. Builder re-runs after fix, all clean
6. Phase 4: Reviewer finds 1 HIGH issue (missing edge case test)
7. Second fix loop: Developer adds test, tester confirms, reviewer approves on re-review
8. Expected: 2 fix loops, but final result has all passing tests, clean build, and clean review

