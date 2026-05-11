---
name: harness
description: "Configure agent harnesses. Meta-skill that defines specialized agents and creates the skills they will use. Trigger when: (1) 'configure harness', 'build harness', 'set up harness' requested, (2) 'harness design', 'harness engineering' requested, (3) building harness-based automation for a new domain/project, (4) reconfiguring or extending an existing harness, (5) 'harness check', 'harness audit', 'harness status', 'agent/skill sync' or any harness operations/maintenance request, (6) 'continue harness', 'resume harness', or finishing a partial harness reconfiguration from current workspace state."
---

# Harness — Agent Team & Skill Architect

Configures a harness tailored to a domain/project, defines each agent's role, and creates the skills agents will use. This is a meta-skill.

**Core principles:**
1. Generate agent definitions (`.agents/agents/`) and skills (`.agents/skills/`).
2. **Use agent teams as the default execution mode.**
3. **Register harness context in AGENTS.md** — record harness structure and trigger rules in the project AGENTS.md so agent teams activate immediately in new sessions.
4. **The harness is a living system, not a static artifact.** — After every execution, incorporate feedback and continuously update agents, skills, and AGENTS.md.
5. **Symphony dispatch: read the workflow contract FIRST, before changing anything.** The running `symphony` process injects a workflow file path into the dispatch context. Read that file in full before modifying `.agents/` or `AGENTS.md`. If the injected path is missing or unreadable, fall back to **`elixir/WORKFLOW.md`** (this monorepo’s canonical contract) and note it in the ticket workpad **Notes** — see `references/symphony-dispatch.md` → *Workflow file resolution*. Manual invocations still read any workflow path referenced in project context.

## Workflow

### Phase 0: Audit & Environment Detection

When the harness skill triggers, first assess the current harness state and detect the execution environment.

1. Read `project/.agents/agents/`, `project/.agents/skills/`, `project/AGENTS.md`
2. Detect execution context:
   - **Symphony dispatch**: The harness run is driven by Symphony (for example `SymphonyElixir.Harness.Manager` after a `WORKFLOW.md` content-hash change, an explicit harness dispatch, or caller-supplied orchestrator context such as `_workspace/symphony_context.json`).
     1. **Hard prerequisite: read the workflow contract in full before other edits.** The dispatch context provides a workflow file path — read that file first. If the path is **missing or unreadable** (common for ephemeral `/tmp/...` copies), fall back to the monorepo canonical **`elixir/WORKFLOW.md`**, note which path was used in the ticket workpad **Notes**, then continue. See `references/symphony-dispatch.md` → *Workflow file resolution*.
     2. Only after a successful read (injected or fallback) may you proceed to audit `.agents/` and `AGENTS.md`.
   - **Manual invocation**: User-requested harness work without the Symphony dispatch signals above. Still check for a workflow file in the project when one is referenced, and read it before making changes. Use standard standalone protocols.
3. Branch by current state:
   - **New build**: agent/skill directories are missing or empty → run all phases starting from Phase 1
   - **Existing extension**: harness exists and new agents/skills requested → run only the phases needed per the selection matrix below
   - **Operations/maintenance**: audit, fix, or sync existing harness → go to Phase 7-5 operations/maintenance workflow

   **Phase selection matrix for existing extensions:**
   | Change type | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 | Phase 6 |
   |-------------|---------|---------|---------|---------|---------|---------|
   | Add agent | Skip (use Phase 0 results) | Placement decision only | Required | If dedicated skills needed | Modify orchestrator | Required |
   | Add/modify skill | Skip | Skip | Skip | Required | If connections change | Required |
   | Architecture change | Skip | Required | Affected agents only | Affected skills only | Required | Required |
4. Cross-reference existing agent/skill lists against AGENTS.md records to detect drift
5. Summarize audit findings for the user and confirm the execution plan

**Multi-turn resume (Symphony harness):** Prompts like “Continue the harness configuration…” mean **continuation**, not a greenfield rebuild: re-read `elixir/WORKFLOW.md`, re-audit `.agents/` and `AGENTS.md`, finish only incomplete edits, keep `AGENTS.md` aligned with `.agents/` (this monorepo often symlinks `CLAUDE.md` → `AGENTS.md`—edit **once**), and append **Change History**. If audit finds **no drift**, append a dated row noting a verification-only pass rather than re-touching files blindly. See `references/symphony-dispatch.md` → *Harness multi-turn resume*.

### Phase 1: Domain Analysis
1. Identify domain/project from the user's request
2. Identify core task types (generation, validation, editing, analysis, etc.)
3. Analyze overlaps/conflicts with existing agents and skills based on Phase 0 audit
4. Explore the project codebase — understand the tech stack, data models, key modules
5. **Detect user proficiency** — gauge technical level from conversational cues (terminology used, question depth) and adjust communication tone accordingly. For less experienced users, avoid unexplained jargon like "assertion" or "JSON schema".

### Phase 2: Team Architecture Design

#### 2-1. Execution Mode Selection: Agent Team vs Sub-Agent

**Default to agent team.** When 2+ agents need to collaborate, prefer agent teams. Team members self-coordinate via direct communication (SendMessage) and shared task lists (TaskCreate); discovery sharing, conflict discussion, and gap filling improve result quality.

Choose sub-agent mode only when there is a single agent, or when inter-agent communication is unnecessary (only result passing is needed).

> See the "Execution Mode" section in `references/agent-design-patterns.md` for comparison table and decision tree.

#### 2-2. Architecture Pattern Selection

1. Decompose work into specialized domains
2. Determine agent team structure (see `references/agent-design-patterns.md` for architecture patterns)
   - **Pipeline**: Sequential dependent tasks
   - **Fan-out/Fan-in**: Parallel independent tasks
   - **Expert Pool**: Context-dependent selective invocation
   - **Generate-Verify**: Generation followed by quality review
   - **Supervisor**: Central agent manages state and dynamic distribution
   - **Hierarchical Delegation**: Parent agent delegates recursively to children

#### 2-3. Agent Separation Criteria

Evaluate along 4 axes: expertise, parallelism, context, reusability. See `references/agent-design-patterns.md` "Agent Separation Criteria" for detailed criteria table.

### Phase 3: Agent Definition Generation

**Every agent MUST be defined as a file at `project/.agents/agents/{name}.md`.** Never inline agent roles directly into the Agent tool's prompt parameter. Reasons:
- Agent definitions must exist as files to be reusable across sessions
- Team communication protocols must be explicit to guarantee collaboration quality
- The harness's core value is the separation of agents (who) and skills (how)

Even when using built-in types (`general-purpose`, `Explore`, `Plan`), create an agent definition file. Specify the built-in type via the Agent tool's `subagent_type` parameter; put the role, principles, and protocols in the agent definition file.

**Team reconfiguration:** Agent teams can only have one active team per session, but teams can be dissolved and reformed between phases. When different expert combinations are needed per phase (as in the pipeline pattern), save the previous team's outputs to files, clean up the team, and create a new one.

Define each agent at `project/.agents/agents/{name}.md`. Required sections: core role, work principles, input/output protocol, error handling, collaboration. For agent team mode, add a `## Team Communication Protocol` section specifying message send/receive targets and task request scope.

> See `references/agent-design-patterns.md` "Agent Definition Structure" + `references/team-examples.md` for templates and full file examples.

**Interim AGENTS.md sync (on Phase 3 completion):**
Immediately after Phase 3, update the agent list table in AGENTS.md. Reflect new agents right away, and sync deletions/changes too. This is an **interim sync** to guard against session interruption — Phase 5-4 finalizes the full context.

**When including a QA agent:**
- Use `general-purpose` type for QA agents (`Explore` is read-only and cannot run verification scripts)
- QA's core task is not "existence checking" but **"boundary cross-comparison"** — read API responses and frontend hooks simultaneously and compare shapes
- Run QA incrementally after each module completes, not once at the very end (incremental QA)
- See `references/qa-agent-guide.md` for detailed guidance

### Phase 4: Skill Generation

Create each agent's skills at `project/.agents/skills/{name}/SKILL.md`. See `references/skill-writing-guide.md` for detailed authoring guidance.

#### 4-1. Skill Structure

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (name, description required)
│   └── Markdown body
└── Bundled Resources (optional)
    ├── scripts/    — executable code for repetitive/deterministic tasks
    ├── references/ — reference docs loaded conditionally
    └── assets/     — files used in output (templates, images, etc.)
```

#### 4-2. Description Writing — Active Trigger Induction

The description is the skill's sole trigger mechanism. Claude tends to be conservative about triggering, so write descriptions **actively ("pushy")**.

**Bad:** `"Skill for processing PDF documents"`
**Good:** `"Perform all PDF operations: read PDF files, extract text/tables, merge, split, rotate, watermark, encrypt, OCR. MUST use this skill whenever a .pdf file is mentioned or a PDF output is requested."`

Key: describe what the skill does + concrete trigger situations, and differentiate from similar-but-not-triggering cases.

#### 4-3. Body Writing Principles

| Principle | Description |
|-----------|-------------|
| **Explain Why** | Instead of dictatorial "ALWAYS/NEVER" instructions, convey the reason behind the rule. LLMs that understand the why make correct decisions in edge cases. |
| **Stay Lean** | The context window is a shared resource. Target SKILL.md body under 500 lines; delete or move to references/ anything that doesn't carry its weight. |
| **Generalize** | Explain principles so the agent can handle diverse inputs, rather than narrow rules that only fit specific examples. Avoid overfitting. |
| **Bundle Repetitive Code** | When agents repeatedly write the same scripts in test runs, pre-bundle them in `scripts/`. |
| **Use Imperative Tone** | Write in direct, instructional language. |

#### 4-4. Progressive Disclosure

Skills manage context via a 3-tier loading system:

| Tier | Loaded when | Size target |
|------|------------|-------------|
| **Metadata** (name + description) | Always in context | ~100 words |
| **SKILL.md body** | When skill triggers | <500 lines |
| **references/** | Only when needed | Unlimited (scripts can run without loading) |

**Size management rules:**
- When SKILL.md nears 500 lines, extract details into references/ and leave pointers in the body for "when to read this file"
- Reference files over 300 lines must include a **Table of Contents (ToC)** at the top
- For domain/framework variants, split into domain-specific files under references/ so only the relevant file is loaded

```
cloud-deploy/
├── SKILL.md (workflow + selection guide)
└── references/
    ├── aws.md    ← Load only when AWS selected
    ├── gcp.md
    └── azure.md
```

#### 4-5. Skill-Agent Connection Principles

- 1 agent ↔ 1~N skills (1:1 or 1:many)
- Multiple agents can share a skill
- Skills contain "how to do it"; agents contain "who does it"

> See `references/skill-writing-guide.md` for detailed writing patterns, examples, and data schema standards.

**Interim AGENTS.md sync (on Phase 4 completion):**
Immediately after Phase 4, update the skill list and directory structure in AGENTS.md. Reflect new skill directories in the directory tree right away. Like Phase 3, this is an **interim sync** against session interruption; Phase 5-4 does the final consolidation.

### Phase 5: Integration & Orchestration

The orchestrator is a special form of skill that weaves individual agents and skills into a single workflow, coordinating the entire team. While Phase 4's individual skills define "what each agent does and how," the orchestrator defines "who collaborates when and in what order." See `references/orchestrator-template.md` for concrete templates.

**Modifying orchestrator on existing extensions:** When extending (not building new), modify the existing orchestrator rather than creating a new one. When adding agents: reflect the new agent in team composition, task assignments, and data flow; add trigger keywords for the new agent to the description.

Orchestrator patterns differ by execution mode:

#### 5-0. Mode-Specific Orchestrator Patterns

**Agent Team Mode (default):**
The orchestrator forms the team via `TeamCreate` and assigns work via `TaskCreate`. Team members self-coordinate through `SendMessage`. The leader (orchestrator) monitors progress and synthesizes results.

```
[Orchestrator/Leader]
    ├── TeamCreate(team_name, members)
    ├── TaskCreate(tasks with dependencies)
    ├── Team members self-coordinate (SendMessage)
    ├── Result collection and synthesis
    └── Team cleanup
```

**Sub-Agent Mode:**
The orchestrator calls sub-agents directly via the `Agent` tool. Sub-agents return results only to the main agent.

```
[Orchestrator]
    ├── Agent(agent-1, run_in_background=true)
    ├── Agent(agent-2, run_in_background=true)
    ├── Await and collect results
    └── Produce integrated output
```

#### 5-1. Data Transfer Protocol

Specify inter-agent data transfer methods within the orchestrator:

| Strategy | Method | Execution Mode | Best for |
|----------|--------|---------------|----------|
| **Message-based** | Direct team communication via `SendMessage` | Agent team | Real-time coordination, feedback exchange, lightweight state passing |
| **Task-based** | Work state sharing via `TaskCreate`/`TaskUpdate` | Agent team | Progress tracking, dependency management, task requests |
| **File-based** | Write/read files at agreed paths | Both | Large data, structured outputs, audit trail needed |

**Recommended combination for agent team mode:** Task-based (coordination) + File-based (outputs) + Message-based (real-time communication)

File-based transfer rules:
- Store intermediate outputs in a `_workspace/` folder under the working directory
- File naming convention: `{phase}_{agent}_{artifact}.{ext}` (e.g., `01_analyst_requirements.md`)
- Only final outputs go to user-specified paths; preserve intermediate files (`_workspace/`) for post-hoc verification and audit trail

#### 5-2. Error Handling

Include error handling policy in the orchestrator. Core principle: 1 retry, then proceed without that result on re-failure (note the omission in the report); never delete conflicting data — annotate the sources instead.

> See `references/orchestrator-template.md` "Error Handling" for per-type strategy table and implementation details.

#### 5-3. Team Mode: Team Size Guidelines

| Work scale | Recommended team size | Tasks per member |
|------------|----------------------|------------------|
| Small (5~10 tasks) | 2~3 | 3~5 |
| Medium (10~20 tasks) | 3~5 | 4~6 |
| Large (20+ tasks) | 5~7 | 4~5 |

> More team members = more coordination overhead. 3 focused members beat 5 scattered ones.

#### 5-4. AGENTS.md Harness Context Registration

After harness configuration is complete, register the harness context in the project's `AGENTS.md`. Since AGENTS.md is always loaded when a new session starts, the harness's existence and usage rules must be recorded there so agent teams function correctly in subsequent sessions.

**What to record in AGENTS.md (no duplication with orchestrator):**

````markdown
## Harness: {domain name}

**Goal:** {one-line core harness goal}

**Agent Team:**
| Agent | Role |
|-------|------|
| {name} | {one-line role description} |

**Skills:**
| Skill | Purpose | Used By |
|-------|---------|---------|
| {skill-name} | {one-line description} | {agent-name} |

**Execution Rules:**
- For {domain}-related work requests, process via the `{orchestrator-skill-name}` skill using the agent team
- Simple questions/confirmations may be answered directly without the agent team
- Intermediate outputs: `_workspace/` directory
- When invoked by Symphony: read the project’s `WORKFLOW.md` execution contract (Symphony monorepo: `elixir/WORKFLOW.md`)

**Directory Structure:**
```
.agents/
├── agents/
│   └── {agent-name}.md
└── skills/
    └── {skill-name}/
        ├── SKILL.md
        └── references/
```

**Change History:**
| Date | Change | Target | Reason |
|------|--------|--------|--------|
| {YYYY-MM-DD} | Initial configuration | All | - |
````

**AGENTS.md vs Orchestrator role division:**

| Item | AGENTS.md | Orchestrator Skill |
|------|----------|-------------------|
| Harness existence notification | O | X |
| Agent list (name + one-line role) | O | O (detailed) |
| Skill list (name + purpose + agent) | O | O (detailed) |
| Directory structure | O | X |
| Trigger rules | O (which situations trigger skills) | X (handled by description) |
| Workflow details | X | O |
| Data flow | X | O |
| Error handling | X | O |
| Change history | O | X |

Key: AGENTS.md only contains "a harness exists, when to use it"; delegate "how to execute" to the orchestrator.

#### 5-5. Follow-up Task Support

The orchestrator must handle not just initial execution but also follow-up work. Ensure these three things:

**1. Include follow-up keywords in orchestrator description:**
Initial creation keywords alone won't trigger follow-up requests. Required follow-up expressions in description:
- "re-run", "rerun", "update", "modify", "revise", "improve"
- "re-do {domain}'s {partial task}"
- "based on previous results", "improve results"

**2. Add context detection step to orchestrator Phase 1:**
At workflow start, check for existing outputs to determine execution mode:
- `_workspace/` exists + user requests partial fix → **partial re-run** (re-call only affected agents)
- `_workspace/` exists + user provides new input → **fresh run** (move existing `_workspace/` to `_workspace_prev/`)
- `_workspace/` absent → **initial run**

**3. Include re-invocation guidance in agent definitions:**
Each agent `.md` file must specify "behavior when prior output exists":
- If previous result file exists, read it and incorporate improvements
- If user feedback is given, modify only the relevant parts

> See `references/orchestrator-template.md` "Phase 0: Context Detection" section.

### Phase 6: Verification & Testing

Verify the generated harness. See `references/skill-testing-guide.md` for detailed testing methodology.

#### 6-1. Structural Verification

- Confirm all agent files are in correct locations
- Validate skill frontmatter (name, description)
- Check cross-agent reference consistency
- Verify no commands were generated

#### 6-2. Execution Mode Verification

- Agent team mode: verify communication paths between members, task dependencies, team size appropriateness
- Sub-agent mode: verify each agent's input/output connections, `run_in_background` settings

#### 6-3. Skill Execution Testing

Perform actual execution tests for each generated skill:

1. **Write test prompts** — create 2~3 realistic test prompts per skill. Use concrete, natural language that actual users would type.

2. **With-skill vs Without-skill comparison** — where possible, run with and without the skill in parallel to verify the skill's added value. Spawn two sub-agents:
   - **With-skill**: reads the skill and performs the task
   - **Without-skill (baseline)**: performs the same task without the skill

3. **Result evaluation** — assess output quality qualitatively (user review) + quantitatively (assertion-based). When outputs are objectively verifiable (file creation, data extraction, etc.), define assertions. For subjective outputs (tone, design), rely on user feedback.

4. **Iterative improvement loop** — when issues are found in test results:
   - **Generalize** the feedback before modifying the skill (no narrow fixes for specific examples only)
   - Re-test after modification
   - Repeat until the user is satisfied or no meaningful improvement remains

5. **Bundle repetitive patterns** — when agents repeatedly write the same code during testing (e.g., all tests generate identical helper scripts), pre-bundle that code into `scripts/`.

#### 6-4. Trigger Verification

Verify each skill's description triggers correctly:

1. **Should-trigger queries** (8~10) — varied expressions that should trigger the skill (formal/casual, explicit/implicit)
2. **Should-NOT-trigger queries** (8~10) — "near-miss" queries with similar keywords but better suited to a different tool/skill

**Near-miss key:** Obviously unrelated queries like "write a fibonacci function" have no testing value. Good test cases are **boundary-ambiguous queries** like "extract the chart from this Excel file as PNG" (xlsx skill vs image conversion).

Also check for trigger conflicts with existing skills at this stage.

#### 6-5. Dry-Run Testing

- Review orchestrator skill phase ordering for logical soundness
- Verify no dead links in data transfer paths
- Confirm every agent's inputs match previous phase outputs
- Verify fallback paths are executable for each error scenario

#### 6-6. Test Scenario Documentation

- Add a `## Test Scenarios` section to the orchestrator skill
- Document at least 1 normal flow + 1 error flow

### Phase 7: Harness Evolution

The harness is not a static artifact created once and left alone. It is a system that continuously evolves based on user feedback.

#### 7-1. Post-Execution Feedback Collection

After every harness execution, invite user feedback:
- "Is there anything to improve in the results?"
- "Any changes you'd like to the agent team composition or workflow?"

If no feedback, move on. Don't push, but always provide the opportunity.

#### 7-2. Feedback Integration Paths

Different feedback types target different artifacts:

| Feedback type | Modification target | Example |
|--------------|-------------------|---------|
| Output quality | That agent's skill | "Analysis is too shallow" → add depth criteria to skill |
| Agent role | Agent definition `.md` | "Security review also needed" → add new agent |
| Workflow order | Orchestrator skill | "Should verify first" → reorder phases |
| Team composition | Orchestrator + agents | "These two could merge" → merge agents |
| Trigger gap | Skill description | "That phrasing doesn't work" → expand description |

#### 7-3. Change History

Record every change in AGENTS.md's **Change History** table (same table as the Phase 5-4 template's "Change History" section):

```markdown
**Change History:**
| Date | Change | Target | Reason |
|------|--------|--------|--------|
| 2026-04-05 | Initial configuration | All | - |
| 2026-04-07 | Added QA agent | agents/qa.md | Feedback: output quality verification lacking |
| 2026-04-10 | Added tone guide | skills/content-creator | Feedback: "too stiff" |
```

This history tracks the harness's evolutionary direction and prevents regression.

#### 7-4. Evolution Triggers

Propose evolution not only when the user explicitly says "modify the harness," but also when:
- The same type of feedback repeats 2+ times
- An agent exhibits a pattern of repeated failures
- The user is observed working around the orchestrator manually

#### 7-5. Operations/Maintenance Workflow

Perform systematic inspection, modification, and synchronization of an existing harness. Follow this workflow when entering the "operations/maintenance" branch from Phase 0.

**Step 1: State Audit**
- Compare `.agents/agents/` file list against AGENTS.md agent table → produce discrepancy list
- Compare `.agents/skills/` directory list against AGENTS.md skill table → produce discrepancy list
- Compare AGENTS.md directory structure against actual filesystem → detect drift
- Report audit findings to the user

**Step 2: Incremental Add/Modify**
- Per user request: add/modify/delete agents, add/modify/delete skills
- One change at a time; run Step 3 (sync) immediately after each change

**Step 3: AGENTS.md Sync**
- Update agent table, skill table, directory structure, and change history to match actual state
- Record date, change content, target, and reason in change history

**Step 4: Change Verification**
- Structural verification of modified agents/skills (per Phase 6-1)
- If changes affect triggers, run trigger verification (per Phase 6-4)
- For large changes (architecture changes, 3+ agents added/removed), also run Phase 6-3 (execution testing) and 6-5 (dry-run)
- Final confirmation that AGENTS.md matches actual files

## Output Checklist

Confirm after generation:

- [ ] `project/.agents/agents/` — **agent definition files must be created** (file required even for built-in types)
- [ ] `project/.agents/skills/` — skill files (SKILL.md + references/)
- [ ] 1 orchestrator skill (includes data flow + error handling + test scenarios)
- [ ] Execution mode specified (agent team or sub-agent)
- [ ] `.agents/commands/` — nothing generated
- [ ] No conflicts with existing agents/skills
- [ ] Skill descriptions are actively ("pushy") written — **includes follow-up task keywords**
- [ ] SKILL.md body under 500 lines; extracted to references/ if exceeded
- [ ] Execution verified with 2~3 test prompts
- [ ] Trigger verification (should-trigger + should-NOT-trigger) complete
- [ ] **Harness context registered in AGENTS.md** (agent list, skill list, execution rules, change history)
- [ ] **AGENTS.md agent/skill/directory structure/key reference paths reflected** — synced immediately on Phase 3, 4 completion
- [ ] **AGENTS.md change history records agent/skill additions, deletions, modifications**
- [ ] **Orchestrator Phase 1 includes context detection step** (initial/follow-up/partial re-run detection)
- [ ] **Symphony dispatch context integrated** — when invoked under Symphony, WORKFLOW.md and platform state are considered

## Test scenarios (Symphony harness)

Use these as quick dry-runs after reconfiguring `.agents/` or `AGENTS.md`:

1. **Normal:** User asks to sync harness with `elixir/WORKFLOW.md`. Expect Phase 0
   audit, diff of YAML + prompt sections, updates under `.agents/` + `AGENTS.md`
   only, change-history row.
2. **Error:** `elixir/WORKFLOW.md` missing or unreadable. Expect harness to stop
   after reporting the blocker; no partial writes to skills.
3. **Continuation:** Resume harness configuration from current tree. Expect
   re-audit, no duplicate agent files, linear/land/pull alignment verified.

## References

- Harness patterns: `references/agent-design-patterns.md`
- Existing harness examples (with full file contents): `references/team-examples.md`
- Orchestrator template: `references/orchestrator-template.md`
- **Skill writing guide**: `references/skill-writing-guide.md` — writing patterns, examples, data schema standards
- **Skill testing guide**: `references/skill-testing-guide.md` — testing/evaluation/iterative improvement methodology
- **QA agent guide**: `references/qa-agent-guide.md` — reference when including QA agents in build harnesses. Covers integration consistency verification methodology, boundary bug patterns, QA agent definition template. Based on 7 real bugs found in actual projects.
- **Symphony dispatch**: `references/symphony-dispatch.md` — Symphony platform integration protocols for harness agents dispatched by the Symphony orchestrator.
- **Issue PR gates (checklist)**: `references/issue-execution-checklist.md` — WORKFLOW Step 1 workpad shape (app flow checks, ticket validation mirror, pull evidence in `Notes`), Step 2 implement/push/sweep, Guardrails (no extra completion comments), `Todo`+PR flow, workpad edit fallback, PR feedback sweep, Manual QA Plan, mandatory validation gate, completion bar (runtime validation + media), merge→Done, blocked-access escape hatch (pointers only; `elixir/WORKFLOW.md` is authoritative).
