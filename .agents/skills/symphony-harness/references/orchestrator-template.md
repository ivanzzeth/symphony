# Orchestrator Skill Template

The orchestrator is the top-level skill that coordinates the entire team. Two templates are provided based on execution mode.

---

## Template A: Agent Team Mode (default)

Agent teams are formed via `TeamCreate` and coordinated through shared task lists and `SendMessage`.

```markdown
---
name: {domain}-orchestrator
description: "Orchestrator that coordinates the {domain} agent team. {initial execution keywords}. Follow-up: MUST use this skill for {domain} result modifications, partial re-runs, updates, revisions, re-execution, or previous result improvement requests."
---

# {Domain} Orchestrator

Integrated skill that coordinates the {domain} agent team to produce {final output}.

## Execution Mode: Agent Team

## Agent Configuration

| Member | Agent Type | Role | Skill | Output |
|--------|-----------|------|-------|--------|
| {teammate-1} | {custom or built-in} | {role} | {skill} | {output-file} |
| {teammate-2} | {custom or built-in} | {role} | {skill} | {output-file} |
| ... | | | | |

## Workflow

### Phase 0: Context Detection (follow-up support)

Check for existing outputs to determine the execution mode:

1. Check if `_workspace/` directory exists
2. Determine execution mode:
   - **`_workspace/` absent** → initial run. Proceed to Phase 1
   - **`_workspace/` exists + user requests partial fix** → partial re-run. Re-call only the affected agents; overwrite only the modified target files
   - **`_workspace/` exists + new input provided** → fresh run. Move existing `_workspace/` to `_workspace_{YYYYMMDD_HHMMSS}/`, then proceed to Phase 1
3. For partial re-runs: include previous output paths in agent prompts so agents read existing results and incorporate feedback

### Phase 1: Preparation
1. Analyze user input — {what to determine}
2. Create `_workspace/` in the working directory (initial run only)
3. Store input data in `_workspace/00_input/`

### Phase 2: Team Formation

1. Create team:
   ```
   TeamCreate(
     team_name: "{domain}-team",
     members: [
       { name: "{teammate-1}", agent_type: "{type}", prompt: "{role description and task instructions}" },
       { name: "{teammate-2}", agent_type: "{type}", prompt: "{role description and task instructions}" },
       ...
     ]
   )
   ```

2. Register tasks:
   ```
   TaskCreate(tasks: [
     { title: "{task1}", description: "{details}", assignee: "{teammate-1}" },
     { title: "{task2}", description: "{details}", assignee: "{teammate-2}" },
     { title: "{task3}", description: "{details}", depends_on: ["{task1}"] },
     ...
   ])
   ```

   > 5~6 tasks per member is optimal. Use `depends_on` for dependencies.

### Phase 3: {Main work — e.g., research/generation/analysis}

**Execution style:** Team members self-coordinate

Team members claim tasks from the shared task list and execute independently.
The leader monitors progress and intervenes when needed.

**Inter-team communication rules:**
- {teammate-1} sends {what info} to {teammate-2} via SendMessage
- {teammate-2} saves results to file on completion and notifies leader
- If a member needs another member's results, they request via SendMessage

**Output storage:**

| Member | Output Path |
|--------|------------|
| {teammate-1} | `_workspace/{phase}_{teammate-1}_{artifact}.md` |
| {teammate-2} | `_workspace/{phase}_{teammate-2}_{artifact}.md` |

**Leader monitoring:**
- Receive automatic notifications when members become idle
- When a member is stuck, instruct via SendMessage or reassign tasks
- Check overall progress via TaskGet

### Phase 4: {Follow-up work — e.g., verification/integration}
1. Wait for all member tasks to complete (check status via TaskGet)
2. Collect each member's output via Read
3. {integration/verification logic}
4. Generate final output: `{output-path}/{filename}`

### Phase 5: Cleanup
1. Send completion message to members (SendMessage)
2. Clean up team (TeamDelete)
3. Preserve `_workspace/` directory (do not delete intermediate outputs — for post-hoc verification and audit trail)
4. Report result summary to user

> **When team reconfiguration is needed:** If different expert combinations are required per phase, clean up the current team with TeamDelete, then form the next phase's team with a new TeamCreate. Previous team outputs are preserved in `_workspace/` so the new team can access them via Read.

## Data Flow

```
[Leader] → TeamCreate → [teammate-1] ←SendMessage→ [teammate-2]
                            │                           │
                            ↓                           ↓
                      artifact-1.md              artifact-2.md
                            │                           │
                            └───────── Read ────────────┘
                                       ↓
                                [Leader: Integration]
                                       ↓
                                Final Output
```

## Error Handling

| Situation | Strategy |
|-----------|----------|
| 1 member fails/stops | Leader detects → check status via SendMessage → restart or create replacement |
| Majority of members fail | Notify user and confirm whether to proceed |
| Timeout | Use partial results collected so far, terminate incomplete members |
| Data conflict between members | Annotate sources and present both; never delete |
| Task status lag | Leader checks via TaskGet, manually updates via TaskUpdate |

## Test Scenarios

### Normal Flow
1. User provides {input}
2. Phase 1 derives {analysis result}
3. Phase 2 forms team ({N} members + {M} tasks)
4. Phase 3: members self-coordinate and execute
5. Phase 4: outputs integrated into final result
6. Phase 5: team cleanup
7. Expected result: `{output-path}/{filename}` created

### Error Flow
1. Phase 3: {teammate-2} stops with an error
2. Leader receives idle notification
3. Check status via SendMessage → attempt restart
4. If restart fails, reassign {teammate-2}'s task to {teammate-1}
5. Proceed to Phase 4 with remaining results
6. Final report notes "{teammate-2} area partially missing"
```

---

## Template B: Sub-Agent Mode (lightweight)

Sub-agents are called directly via the `Agent` tool and return results only to the main agent.

```markdown
---
name: {domain}-orchestrator
description: "Orchestrator that coordinates {domain} agents. {initial execution keywords}. Follow-up: MUST use this skill for {domain} result modifications, partial re-runs, updates, revisions, re-execution, or previous result improvement requests."
---

# {Domain} Orchestrator

Integrated skill that coordinates {domain} agents to produce {final output}.

## Execution Mode: Sub-Agent

## Agent Configuration

| Agent | subagent_type | Role | Skill | Output |
|-------|--------------|------|-------|--------|
| {agent-1} | {custom or built-in type} | {role} | {skill} | {output-file} |
| {agent-2} | {custom or built-in type} | {role} | {skill} | {output-file} |
| ... | | | | |

## Workflow

### Phase 0: Context Detection (follow-up support)

Check for existing outputs to determine the execution mode:

1. Check if `_workspace/` directory exists
2. Determine execution mode:
   - **`_workspace/` absent** → initial run. Proceed to Phase 1
   - **`_workspace/` exists + user requests partial fix** → partial re-run. Re-call only the affected agents
   - **`_workspace/` exists + new input provided** → fresh run. Move existing `_workspace/` to `_workspace_{YYYYMMDD_HHMMSS}/`

### Phase 1: Preparation
1. Analyze user input — {what to determine}
2. Create `_workspace/` in the working directory (initial run only)
3. Store input data in `_workspace/00_input/`

### Phase 2: {Main work — e.g., research/generation/analysis}

**Execution style:** {parallel | sequential | conditional}

{If parallel}
Call N Agent tools simultaneously in a single message:

| Agent | Input | Output | run_in_background |
|-------|-------|--------|-------------------|
| {agent-1} | {input source} | `_workspace/{phase}_{agent}_{artifact}.md` | true |
| {agent-2} | {input source} | `_workspace/{phase}_{agent}_{artifact}.md` | true |

{If sequential}
Pass previous agent's output as next agent's input:

1. Execute {agent-1} → creates `_workspace/01_{artifact}.md`
2. Execute {agent-2} (input: output of step 1) → creates `_workspace/02_{artifact}.md`

### Phase 3: {Follow-up work — e.g., verification/integration}
1. Collect Phase 2 outputs via Read
2. {integration/verification logic}
3. Generate final output: `{output-path}/{filename}`

### Phase 4: Cleanup
1. Preserve `_workspace/` directory (do not delete intermediate outputs — for post-hoc verification and audit trail)
2. Report result summary to user

## Data Flow

```
Input → [agent-1] → artifact-1 ─┐
                                ├→ [Integration] → Final Output
Input → [agent-2] → artifact-2 ─┘
```

## Error Handling

| Situation | Strategy |
|-----------|----------|
| 1 agent fails | Retry once. If still failing, proceed without that result; note omission in report |
| Majority of agents fail | Notify user and confirm whether to proceed |
| Timeout | Use partial results collected so far |
| Data conflict between agents | Annotate sources and present both; never delete |

## Test Scenarios

### Normal Flow
1. User provides {input}
2. Phase 1 derives {analysis result}
3. Phase 2: {N} agents execute in parallel, each producing output
4. Phase 3: outputs integrated into final report
5. Expected result: `{output-path}/{filename}` created

### Error Flow
1. Phase 2: {agent-2} fails
2. Retry once, still failing
3. Proceed to Phase 3 without {agent-2}'s result
4. Final report notes "{agent-2} area data not collected"
5. Notify user of partial completion
```

---

## Writing Principles

1. **State execution mode first** — declare "Agent Team" or "Sub-Agent" at the top of the orchestrator
2. **Be specific about TeamCreate/SendMessage/TaskCreate usage in agent team mode** — team formation, task registration, communication rules
3. **Specify all Agent tool parameters in sub-agent mode** — name, subagent_type, prompt, run_in_background
4. **Use absolute file paths** — no relative paths; clear paths rooted at `_workspace/`
5. **Declare inter-phase dependencies** — which phase depends on which phase's output
6. **Make error handling realistic** — don't assume "everything succeeds"
7. **Test scenarios are mandatory** — at least 1 normal + 1 error flow

## Follow-up Keywords in Description

The orchestrator description must go beyond initial execution keywords. Always include these follow-up expressions:

- re-run / re-execute / update / modify / revise
- "re-do only {part} of {domain}"
- "based on previous results", "improve results"
- Domain-appropriate everyday terms (e.g., for a launch strategy harness: "launch", "promotion", "trending")

Without follow-up keywords, the harness becomes effectively dead code after the first run.

## Real Orchestrator Reference

Basic fan-out/fan-in orchestrator structure:
Preparation → Phase 0 (context detection) → TeamCreate + TaskCreate → N members execute in parallel → Read + integration → Cleanup.
See `references/team-examples.md` research team example for reference.
