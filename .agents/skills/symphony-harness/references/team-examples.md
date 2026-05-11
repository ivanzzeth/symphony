# Agent Team Examples

---

## Example 1: Research Team (Agent Team Mode)

### Team Architecture: Fan-out/Fan-in
### Execution Mode: Agent Team

```
[Leader/Orchestrator]
    ├── TeamCreate(research-team)
    ├── TaskCreate(4 research tasks)
    ├── Members self-coordinate (SendMessage)
    ├── Collect results (Read)
    └── Generate integrated report
```

### Agent Configuration

| Member | Agent Type | Role | Output |
|--------|-----------|------|--------|
| official-researcher | general-purpose | Official docs/blogs | research_official.md |
| media-researcher | general-purpose | Media/investment | research_media.md |
| community-researcher | general-purpose | Community/social | research_community.md |
| background-researcher | general-purpose | Background/competition/academic | research_background.md |
| (leader = orchestrator) | — | Integrated report | final_report.md |

> Research agents use the `general-purpose` built-in type, but MUST be defined as `.agents/agents/{name}.md` files. The file must specify role, research scope, and team communication protocol to ensure reusability and collaboration quality.

### Orchestrator Workflow (Agent Team)

```
Phase 1: Preparation
  - Analyze user input (determine topic, research mode)
  - Create _workspace/

Phase 2: Team Formation
  - TeamCreate(team_name: "research-team", members: [
      { name: "official", prompt: "Research official channels..." },
      { name: "media", prompt: "Research media/investment trends..." },
      { name: "community", prompt: "Research community reactions..." },
      { name: "background", prompt: "Research background/competitive landscape..." }
    ])
  - TaskCreate(tasks: [
      { title: "Official channel research", assignee: "official" },
      { title: "Media trend research", assignee: "media" },
      { title: "Community reaction research", assignee: "community" },
      { title: "Background research", assignee: "background" }
    ])

Phase 3: Execution
  - 4 members research independently
  - Share interesting findings via SendMessage between members
    (e.g., media shares investment news with background)
  - Members directly discuss conflicting information
  - Each member saves file on completion + notifies leader

Phase 4: Integration
  - Leader Reads 4 outputs
  - Generates integrated report
  - Annotates conflicting information with sources

Phase 5: Cleanup
  - Request members to complete
  - Team cleanup
  - Preserve _workspace/ (for post-hoc verification and audit trail)
```

### Team Communication Pattern

```
official ──SendMessage──→ background  (share related official announcements)
media ────SendMessage──→ background  (share investment/acquisition info)
community ─SendMessage──→ media      (community reactions relevant to media)
all members ──TaskUpdate──→ shared task list  (progress updates)
leader ←───── idle notification ──── completed member   (automatic)
```

---

## Example 2: Sci-Fi Novel Writing Team (Agent Team Mode)

### Team Architecture: Pipeline + Fan-out
### Execution Mode: Agent Team

```
Phase 1 (parallel — agent team): worldbuilder + character-designer + plot-architect
  → Coordinate consistency via SendMessage
Phase 2 (sequential): prose-stylist (drafting)
Phase 3 (parallel — agent team): science-consultant + continuity-manager (review)
  → Share discoveries via SendMessage
Phase 4 (sequential): prose-stylist (apply review feedback)
```

### Agent Configuration

| Member | Agent Type | Role | Skill |
|--------|-----------|------|-------|
| worldbuilder | custom | World-building | world-setting |
| character-designer | custom | Character design | character-profile |
| plot-architect | custom | Plot structure | outline |
| prose-stylist | custom | Style editing + drafting | write-scene, review-chapter |
| science-consultant | custom | Science verification | science-check |
| continuity-manager | custom | Consistency verification | consistency-check |

### Full Agent File Example: `worldbuilder.md`

```markdown
---
name: worldbuilder
description: "Expert in building sci-fi novel worlds. Designs physics laws, social structures, technology levels, and history."
---

# Worldbuilder — Sci-Fi World Design Expert

You are a world-building expert for sci-fi novels. Grounded in scientific fact but expanding imagination, you build the physical, social, and technological foundations of the world the story unfolds in.

## Core Role
1. Define the world's physical laws and technology level
2. Design social structures, political systems, economic systems
3. Establish historical context and current conflict structures
4. Describe locations with environment and atmosphere

## Work Principles
- Internal consistency is paramount — no contradictions between setting elements
- Use "if this technology exists, then..." chain questions to deduce world-level ripple effects
- The world serves the story — avoid excessive setting that obstructs the plot

## Input/Output Protocol
- Input: User's world concept, genre requirements
- Output: `_workspace/01_worldbuilder_setting.md`
- Format: Markdown. Sections (physics/society/technology/history/locations)

## Team Communication Protocol
- To character-designer: SendMessage social structure, class system, occupation info
- To plot-architect: SendMessage main conflict structures, crisis elements
- From science-consultant: Receive scientific error feedback → revise setting
- When world settings change: broadcast to all relevant members

## Error Handling
- If concept is vague: propose 3 directions and request selection
- If scientific error found: present alternatives alongside

## Collaboration
- Provide social structure info to character-designer
- Provide conflict structure info to plot-architect
- Incorporate science-consultant feedback to revise settings
```

### Team Workflow Detail

```
Phase 1: TeamCreate(team_name: "novel-team", members: [worldbuilder, character-designer, plot-architect])
         TaskCreate([world-building, character design, plot structure])
         → Members self-coordinate and work in parallel
         → worldbuilder sends social structure to character-designer via SendMessage
         → character-designer sends protagonist setup to plot-architect via SendMessage

Phase 2: Clean up Phase 1 team → call prose-stylist as sub-agent (solo drafting, no team needed)
         prose-stylist Reads 3 outputs from _workspace/ and drafts
         → saves result to _workspace/02_prose_draft.md

Phase 3: Create new team — TeamCreate(team_name: "review-team", members: [science-consultant, continuity-manager])
         (Only one team active per session, but Phase 1 team was cleaned up, so new team can be created)
         → Both reviewers examine draft, share discoveries
         → science-consultant notifies continuity-manager when physics errors found
         → Clean up team after review complete

Phase 4: Call prose-stylist as sub-agent, apply review results for final revision
```

---

## Example 3: Webtoon Production Team (Sub-Agent Mode)

### Team Architecture: Generate-Verify
### Execution Mode: Sub-Agent

> With only 2 agents in a generate-verify pattern, and result passing being the core need (not communication), sub-agents are appropriate.

```
Phase 1: Agent(webtoon-artist) → generate panels
Phase 2: Agent(webtoon-reviewer) → inspect
Phase 3: Agent(webtoon-artist) → regenerate problem panels (max 2 loops)
```

### Agent Configuration

| Agent | subagent_type | Role | Skill |
|-------|--------------|------|-------|
| webtoon-artist | custom | Panel image generation | generate-webtoon |
| webtoon-reviewer | custom | Quality inspection | review-webtoon, fix-webtoon-panel |

### Full Agent File Example: `webtoon-reviewer.md`

```markdown
---
name: webtoon-reviewer
description: "Expert in reviewing webtoon panel quality. Evaluates composition, character consistency, text readability, and directing."
---

# Webtoon Reviewer — Webtoon Quality Inspection Expert

You are an expert in reviewing webtoon panel quality. You evaluate panels based on visual completeness, story delivery, and character consistency.

## Core Role
1. Evaluate each panel's composition and visual completeness
2. Verify character appearance consistency across panels
3. Assess speech bubble text readability and placement
4. Review overall episode directing flow and pacing

## Work Principles
- Judge clearly with PASS/FIX/REDO 3-tier system
- FIX = resolvable with partial edits; REDO = full regeneration needed
- Judge by objective criteria (consistency, readability, composition), not subjective taste

## Input/Output Protocol
- Input: Panel images in `_workspace/panels/` directory
- Output: `_workspace/review_report.md`
- Format:
  ```
  ## Panel {N}
  - Verdict: PASS | FIX | REDO
  - Reason: [specific reason]
  - Fix direction: [concrete fix direction if FIX/REDO]
  ```

## Error Handling
- On image load failure: mark panel as REDO
- After 2 regeneration attempts, force-PASS REDO panels with warning

## Collaboration
- Deliver fix directions to webtoon-artist (file-based)
- Re-inspect regenerated panels (max 2 loops)
```

### Error Handling

```
Retry policy:
- REDO verdict panels → request regeneration from artist (with specific fix directions)
- Max 2 loops, then force PASS
- If 50%+ of panels are REDO: suggest user revise the prompt
```

---

## Example 4: Code Review Team (Agent Team Mode)

### Team Architecture: Fan-out/Fan-in + Discussion
### Execution Mode: Agent Team

> Code review is a prime case where agent teams shine. Reviewers from different perspectives share discoveries and challenge each other, enabling deeper reviews.

```
[Leader] → TeamCreate(review-team)
    ├── security-reviewer: Check security vulnerabilities
    ├── performance-reviewer: Analyze performance impact
    └── test-reviewer: Verify test coverage
    → Reviewers share discoveries (SendMessage)
    → Leader synthesizes results
```

### Team Communication Pattern

```
security ──SendMessage──→ performance  ("This SQL query is injectable, check performance angle too")
performance ──SendMessage──→ test      ("N+1 query found, check if relevant tests exist")
test ────SendMessage──→ security      ("No auth module tests, opinion on security priority?")
```

Key: Reviewers communicate directly **without going through the leader**, rapidly catching cross-cutting issues.

---

## Example 5: Supervisor Pattern — Code Migration Team (Agent Team Mode)

### Team Architecture: Supervisor
### Execution Mode: Agent Team

```
[supervisor/leader] → Analyze file list → Assign batches
    ├→ [migrator-1] (batch A)
    ├→ [migrator-2] (batch B)
    └→ [migrator-3] (batch C)
    ← Receive TaskUpdate → Assign additional batches or reassign
```

### Agent Configuration

| Member | Role |
|--------|------|
| (leader = migration-supervisor) | File analysis, batch distribution, progress management |
| migrator-1~3 | Migrate assigned file batches |

### Supervisor Dynamic Distribution Logic (using Agent Team)

```
1. Collect full list of target files
2. Estimate complexity (file size, import count, dependencies)
3. Register file batches as tasks via TaskCreate (with dependencies)
4. Members self-claim tasks
5. When member reports completion via TaskUpdate:
   - Success → auto-claim next task
   - Failure → leader checks cause via SendMessage → reassign or assign to another member
6. All tasks complete → leader runs integration tests
```

Difference from fan-out: Tasks are not fixed upfront but **dynamically allocated at runtime**. The shared task list's self-claim feature naturally matches the supervisor pattern.

---

## Output Pattern Summary

### Agent Definition File
Location: `project/.agents/agents/{agent-name}.md`
Required sections: Core role, work principles, input/output protocol, error handling, collaboration
Team mode additional section: **Team Communication Protocol** (message receive/send targets, task claim scope)

### Skill File Structure
Location: `project/.agents/skills/{skill-name}/SKILL.md` (project level)
Or: `~/.claude/skills/{skill-name}/SKILL.md` (global level)

### Integration Skill (Orchestrator)
Top-level skill that coordinates the entire team. Defines per-scenario agent configuration and workflows.
Template: see `references/orchestrator-template.md`.
**Must explicitly state execution mode** — agent team (default) or sub-agent.
