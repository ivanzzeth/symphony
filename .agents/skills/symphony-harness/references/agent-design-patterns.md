# Agent Team Design Patterns

## Execution Mode: Agent Teams vs Sub-Agents

Understand the key differences between the two execution modes and select the appropriate one.

### Agent Teams — Default Mode

The team leader forms a team via `TeamCreate`, and members run as independent Claude Code instances. Members communicate directly via `SendMessage` and self-coordinate through a shared task list (`TaskCreate`/`TaskUpdate`).

```
[Leader] ←→ [MemberA] ←→ [MemberB]
  ↕          ↕          ↕
  └──── Shared Task List ────┘
```

**Core tools:**
- `TeamCreate`: Create team + spawn members
- `SendMessage({to: name})`: Send message to specific member
- `SendMessage({to: "all"})`: Broadcast (high cost, use sparingly)
- `TaskCreate`/`TaskUpdate`: Manage shared task list

**Characteristics:**
- Members can directly converse, challenge, and verify each other
- Members exchange information without going through the leader
- Self-coordination via shared task list (can self-claim tasks)
- Automatic leader notification when members become idle
- Plan approval mode allows pre-review of risky operations

**Constraints:**
- Only one team **active** per session (but teams can be dissolved and reformed between phases)
- No nested teams (members cannot create their own teams)
- Leader is fixed (cannot transfer)
- Higher token cost

**Team reconfiguration pattern:**
When different expert combinations are needed per phase: save previous team outputs to files → clean up team → create new team. Previous team outputs are preserved in `_workspace/` so the new team can access them via Read.

### Sub-Agents — Lightweight Mode

The main agent creates sub-agents via the `Agent` tool. Sub-agents return results only to the main agent and do not communicate with each other.

```
[Main] → [SubA] → returns result
      → [SubB] → returns result
      → [SubC] → returns result
```

**Core tool:**
- `Agent(prompt, subagent_type, run_in_background)`: Create sub-agent

**Characteristics:**
- Lightweight and fast
- Results summarized and returned to main context
- Token-efficient

**Constraints:**
- Sub-agents cannot communicate with each other
- Main agent handles all coordination
- No real-time collaboration/challenge possible

### Mode Selection Decision Tree

```
Are there 2+ agents?
├── Yes → Is inter-agent communication needed?
│         ├── Yes → Agent Team (default)
│         │         Cross-validation, discovery sharing, real-time feedback improve quality.
│         │
│         └── No → Sub-agent also possible
│                  Generate-verify, expert pool, etc. where only result passing is needed.
│
└── No (1 agent) → Sub-agent
                   Single agent doesn't need team formation.
```

> **Core principle:** Agent teams are the default. When choosing sub-agents, ask: "Is inter-member communication truly unnecessary?"

---

## Agent Team Architecture Types

### 1. Pipeline
Sequential work flow. Each agent's output is the next agent's input.

```
[Analysis] → [Design] → [Implementation] → [Verification]
```

**Best for:** Each stage strongly depends on the previous stage's output
**Example:** Novel writing — world-building → characters → plot → draft → edit
**Caution:** Bottlenecks delay the entire pipeline. Design each stage to be as independent as possible.
**Team mode fit:** Strong sequential dependency limits team mode benefits. However, if there are parallel segments within the pipeline, team mode is useful.

### 2. Fan-out/Fan-in
Parallel processing followed by result integration. Independent tasks execute concurrently.

```
         ┌→ [ExpertA] ─┐
[Router] → ├→ [ExpertB] ─┼→ [Integrator]
         └→ [ExpertC] ─┘
```

**Best for:** Different perspectives/domains of analysis needed on the same input
**Example:** Comprehensive research — official/media/community/background simultaneous investigation → integrated report
**Caution:** The integration stage's quality determines overall quality.
**Team mode fit:** The most natural pattern for agent teams. **Must use agent team mode.** Members share discoveries and challenge each other; one agent's finding can redirect another's investigation direction in real time, significantly improving quality over solo research.

### 3. Expert Pool
Select and invoke the appropriate expert based on context.

```
[Router] → { ExpertA | ExpertB | ExpertC }
```

**Best for:** Different processing needed depending on input type
**Example:** Code review — invoke security/performance/architecture expert only in their relevant area
**Caution:** Router classification accuracy is critical.
**Team mode fit:** Sub-agents are more suitable. Only the needed expert is invoked, so a standing team is unnecessary.

### 4. Generate-Verify
A generator agent and verifier agent operate as a pair.

```
[Generator] → [Verifier] → (if issues) → [Generator] re-run
```

**Best for:** Output quality assurance is critical and objective verification criteria exist
**Example:** Webtoon — artist generates → reviewer inspects → regenerate problem panels
**Caution:** Set a max retry count (2~3) to prevent infinite loops.
**Team mode fit:** Agent teams are useful. SendMessage enables real-time feedback exchange between generator and verifier.

### 5. Supervisor
A central agent manages task state and dynamically distributes work to sub-agents.

```
         ┌→ [WorkerA]
[Supervisor] ─┼→ [WorkerB]    ← Supervisor monitors state and dynamically allocates
         └→ [WorkerC]
```

**Best for:** Variable workload or when task distribution must be decided at runtime
**Example:** Large-scale code migration — supervisor analyzes file list and assigns batches to workers
**Difference from fan-out:** Fan-out fixes task distribution upfront; supervisor adjusts dynamically based on progress
**Caution:** Make delegation units large enough that the supervisor doesn't become a bottleneck.
**Team mode fit:** The agent team's shared task list naturally matches the supervisor pattern. Register tasks via TaskCreate; members self-claim.

### 6. Hierarchical Delegation
Parent agent recursively delegates to child agents. Complex problems decomposed step by step.

```
[Director] → [LeadA] → [WorkerA1]
                     → [WorkerA2]
           → [LeadB] → [WorkerB1]
```

**Best for:** Problems that naturally decompose into hierarchical structures
**Example:** Full-stack app development — director → frontend lead → (UI/logic/tests) + backend lead → (API/DB/tests)
**Caution:** Depth beyond 2 levels causes significant latency and context loss. Recommend 2 levels max.
**Team mode fit:** Agent teams don't support nesting (members can't create teams). Implement level 1 as a team and level 2 as sub-agents, or flatten into a single team.

## Composite Patterns

In practice, composite patterns are more common than pure patterns:

| Composite Pattern | Composition | Example |
|-------------------|-------------|---------|
| **Fan-out + Generate-Verify** | Parallel generation then individual verification | Multi-language translation — 4 languages in parallel → each reviewed by native reviewer |
| **Pipeline + Fan-out** | Parallelize some stages within a sequential flow | Analysis (sequential) → Implementation (parallel) → Integration test (sequential) |
| **Supervisor + Expert Pool** | Supervisor dynamically invokes experts | Customer inquiry handling — supervisor classifies inquiry then assigns to appropriate expert |

### Execution Mode for Composite Patterns

**Use agent teams for all composite patterns by default.** Active communication between members is the core driver of result quality.

| Scenario | Recommended Mode | Reason |
|----------|-----------------|--------|
| **Research + Analysis** | Agent team | Discovery sharing between researchers, real-time discussion of conflicting info |
| **Design + Implement + Verify** | Agent team | Feedback loop between designer, implementer, and verifier |
| **Supervisor + Workers** | Agent team | Dynamic allocation via shared task list, progress sharing between workers |
| **Generate + Verify** | Agent team | Real-time feedback between generator and verifier minimizes rework |

> Only consider mixing in sub-agents for fully isolated, single-shot tasks by a single agent.

## Agent Type Selection

Specify the agent type via the Agent tool's `subagent_type` parameter when invoking agents. Agent team members can also use custom agent definitions.

### Built-in Types

| Type | Tool Access | Best For |
|------|------------|----------|
| `general-purpose` | Full (including WebSearch, WebFetch) | Web research, general tasks |
| `Explore` | Read-only (no Edit/Write) | Codebase exploration, analysis |
| `Plan` | Read-only (no Edit/Write) | Architecture design, planning |

### Custom Types

Define agents in `.agents/agents/{name}.md` and invoke them via `subagent_type: "{name}"`. Custom agents have access to all tools.

### Selection Criteria

| Situation | Recommendation | Reason |
|-----------|---------------|--------|
| Complex role reused across sessions | **Custom type** (`.agents/agents/`) | Manage persona and work principles as files |
| Simple research/collection, prompt alone suffices | **`general-purpose`** + detailed prompt | No agent file needed; include instructions in prompt |
| Read-only code analysis/review | **`Explore`** | Prevents accidental file modification |
| Design/planning only | **`Plan`** | Focus on analysis, prevent code changes |
| Implementation requiring file modification | **Custom type** | Full tool access + specialized instructions |

**Principle:** Every agent MUST be defined as a file at `.agents/agents/{name}.md`. Even for built-in types, create an agent definition file specifying the role, principles, and protocols. Files enable reuse across sessions; explicit team communication protocols guarantee collaboration quality.

## Agent Definition Structure

```markdown
---
name: agent-name
description: "1-2 sentence role description. List trigger keywords."
---

# Agent Name — One-line role summary

You are a [role] expert in [domain].

## Core Role
1. Role 1
2. Role 2

## Work Principles
- Principle 1
- Principle 2

## Input/Output Protocol
- Input: [what to receive and from where]
- Output: [what to write and where]
- Format: [file format, structure]

## Team Communication Protocol (agent team mode)
- Receive messages: [from whom, about what]
- Send messages: [to whom, about what]
- Task claims: [what types of tasks to claim from shared task list]

## Error Handling
- [Behavior on failure]
- [Behavior on timeout]

## Collaboration
- Relationship with other agents
```

## Agent Separation Criteria

| Criterion | Separate | Merge |
|-----------|----------|-------|
| Expertise | Separate if domains differ | Merge if domains overlap |
| Parallelism | Separate if independently executable | Consider merging if sequentially dependent |
| Context | Separate if context burden is high | Merge if lightweight and fast |
| Reusability | Separate if used in other teams | Consider merging if only used in this team |

## Skills vs Agents

| Aspect | Skill | Agent |
|--------|-------|-------|
| Definition | Procedural knowledge + tool bundle | Expert persona + behavioral principles |
| Location | `.agents/skills/` | `.agents/agents/` |
| Trigger | User request keyword matching | Explicit invocation via Agent tool |
| Size | Small to large (workflow) | Small (role definition) |
| Purpose | "How to do it" | "Who does it" |

Skills are **procedural guides** that agents reference when performing tasks.
Agents are **expert role definitions** that utilize skills.

## Skill ↔ Agent Connection Patterns

Three ways agents leverage skills:

| Method | Implementation | Best For |
|--------|---------------|----------|
| **Skill tool invocation** | Agent prompt specifies `Invoke Skill tool with /skill-name` | Skill is an independent workflow and user-invocable |
| **Inline in prompt** | Include skill content directly in agent definition | Skill is short (<50 lines) and exclusive to this agent |
| **Reference load** | `Read` skill's references/ files as needed | Skill content is large and only conditionally needed |

Recommendation: Skill tool for high reusability, inline for exclusive use, reference load for large content.
