# QA Agent Design Guide

Guide for including QA agents in build harnesses. Based on real bug patterns and root cause analysis from actual projects, this provides a systematic verification methodology for catching defects that QAs commonly miss.

---

## Table of Contents

1. Defect Patterns QA Agents Miss
2. Integration Coherence Verification
3. QA Agent Design Principles
4. Verification Checklist Template
5. QA Agent Definition Template

---

## 1. Defect Patterns QA Agents Miss

### 1-1. Boundary Mismatch

The most frequent defect. Two components are each "correctly" implemented, but the contract at the connection point is wrong.

| Boundary | Mismatch Example | Why It's Missed |
|----------|-----------------|-----------------|
| API response → Frontend hook | API returns `{ projects: [...] }`, hook expects `SlideProject[]` | Each individually verified as correct; no cross-comparison |
| API response field names → Type definitions | API returns `thumbnailUrl` (camelCase), type expects `thumbnail_url` (snake_case) | TypeScript generic casting hides mismatch from compiler |
| File paths → Link hrefs | Page at `/dashboard/create`, link points to `/create` | File structure and hrefs not cross-compared |
| State transition map → Actual status updates | Map defines `generating_template → template_approved`, code missing transition | Only checks map exists; doesn't trace all update code |
| API endpoints → Frontend hooks | API exists but no corresponding hook (never called) | API and hook lists not 1:1 mapped |
| Immediate response → Async result | API returns `{ status }` immediately; frontend accesses `data.failedIndices` | Only checks types without distinguishing sync/async |

### 1-2. Why Static Code Review Misses These

- **TypeScript generics limit**: `fetchJson<SlideProject[]>()` — compiles fine even when runtime response is `{ projects: [...] }`
- **`npm run build` pass ≠ correct behavior**: Type casting, `any`, generics let builds succeed while runtime fails
- **Existence check vs connection check**: "Does the API exist?" vs "Does the API's response match what the caller expects?" are fundamentally different verifications

---

## 2. Integration Coherence Verification

**Cross-comparison verification** areas that must be included in QA agents.

### 2-1. API Response ↔ Frontend Hook Type Cross-Verification

**Method**: Compare each API route's `NextResponse.json()` call with the corresponding hook's `fetchJson<T>` type parameter.

```
Verification steps:
1. Extract the object shape passed to NextResponse.json() in API routes
2. Check the T type in fetchJson<T> in corresponding hooks
3. Compare shape vs T for consistency
4. Check wrapping: if API returns { data: [...] }, does the hook extract .data?
```

**Patterns to watch for:**
- Paginated APIs: `{ items: [], total, page }` vs frontend expecting a bare array
- snake_case DB fields → camelCase API response → frontend type definition mismatches
- Immediate response (202 Accepted) vs final result shape differences

### 2-2. File Path ↔ Link/Router Path Mapping

**Method**: Extract URL paths from `src/app/` page files and cross-reference all `href`, `router.push()`, `redirect()` values in code.

```
Verification steps:
1. Extract URL patterns from page.tsx file paths under src/app/
   - (group) → removed from URL
   - [param] → dynamic segment
2. Collect all href=, router.push(, redirect( values in code
3. Verify each link matches an actual existing page path
4. Watch for route group URL prefixes (e.g., dashboard/ subtree)
```

### 2-3. State Transition Completeness Tracing

**Method**: Extract all `status:` updates from code and cross-reference against the state transition map.

```
Verification steps:
1. Extract allowed transitions from STATE_TRANSITIONS map
2. Grep all API routes for .update({ status: "..." }) patterns
3. Verify each transition is defined in the map
4. Identify map-defined transitions never executed in code (dead transitions)
5. Especially: check that intermediate states (e.g., generating_template) have transitions to final states (template_approved)
```

### 2-4. API Endpoint ↔ Frontend Hook 1:1 Mapping

**Method**: List all API routes and frontend hooks, verify pairs.

```
Verification steps:
1. Extract endpoint list by HTTP method from src/app/api/ route.ts files
2. Extract fetch call URL list from src/hooks/ use*.ts files
3. Identify API endpoints not called by any hook → flag "unused"
4. Determine if "unused" is intentional (admin API, etc.) or a bug (missing call)
```

---

## 3. QA Agent Design Principles

### 3-1. Use general-purpose, Not Explore

If the QA agent is type `Explore`, it can only read. But effective QA requires:
- Grep for pattern search (extract all `NextResponse.json()`)
- Script execution for automated comparison (API shape vs hook types)
- Ability to fix when needed

**Recommendation**: Use `general-purpose` type, but specify "verify → report → request fix" protocol in the agent definition.

### 3-2. Prioritize "Cross-Comparison" Over "Existence Check"

| Weak Checklist | Strong Checklist |
|---------------|-----------------|
| Do API endpoints exist? | Do API endpoint response shapes match corresponding hook types? |
| Is the state transition map defined? | Do all status update code match the map's transitions? |
| Do page files exist? | Do all links in code point to actually existing pages? |
| Is TypeScript strict mode on? | Are there any type safety bypasses via generic casting? |

### 3-3. "Read Both Sides Simultaneously" Principle

To catch boundary bugs, QA must never read just one side. Always:
- Read the API route **and** the corresponding hook **together**
- Read the state transition map **and** the actual update code **together**
- Read the file structure **and** the link paths **together**

Explicitly state this principle in the agent definition.

### 3-4. Run QA After Each Module Completes, Not Just Post-Build

If the orchestrator only places QA in "Phase 4: After everything is done":
- Bugs accumulate, raising fix cost
- Early boundary mismatches propagate to downstream modules

**Recommended pattern**: Run cross-verification of each API + corresponding hook immediately after the backend API completes (incremental QA).

---

## 4. Verification Checklist Template

Integration coherence checklist for web applications, to include in QA agent definitions.

```markdown
### Integration Coherence Verification (Web App)

#### API ↔ Frontend Connections
- [ ] All API route response shapes match corresponding hook generic types
- [ ] Wrapped responses ({ items: [...] }) are unwrapped in hooks
- [ ] snake_case ↔ camelCase conversion is consistently applied
- [ ] Immediate responses (202) vs final result shapes are distinguished in frontend
- [ ] Every API endpoint has a corresponding frontend hook that actually calls it

#### Routing Coherence
- [ ] All href/router.push values in code match actual page file paths
- [ ] Route group ((group)) removal from URLs is accounted for in path verification
- [ ] Dynamic segments ([id]) are populated with correct parameters

#### State Machine Coherence
- [ ] All defined state transitions are executed in code (no dead transitions)
- [ ] All status updates in code are defined in the transition map (no unauthorized transitions)
- [ ] Intermediate-to-final state transitions are not missing
- [ ] Status-based branches in frontend (if status === "X") have actually reachable X values

#### Data Flow Coherence
- [ ] DB schema field names and API response field name mappings are consistent
- [ ] Frontend type definitions match API response field names
- [ ] Optional field null/undefined handling is consistent on both sides
```

---

## 5. QA Agent Definition Template

Core sections to include in a build harness QA agent.

```markdown
---
name: qa-inspector
description: "QA verification expert. Verifies spec compliance, integration coherence, and design quality."
---

# QA Inspector

## Core Role
Verify implementation quality against spec and **inter-module integration coherence**.

## Verification Priority

1. **Integration Coherence** (highest) — boundary mismatches are the primary cause of runtime errors
2. **Functional Spec Compliance** — API/state machine/data model
3. **Design Quality** — colors/typography/responsive
4. **Code Quality** — unused code, naming conventions

## Verification Method: "Simultaneous Dual-Side Reading"

Boundary verification requires opening **both sides' code simultaneously** for comparison:

| Verification Target | Left (Producer) | Right (Consumer) |
|--------------------|-----------------|------------------|
| API response shape | route.ts NextResponse.json() | hooks/ fetchJson<T> |
| Routing | src/app/ page file paths | href, router.push values |
| State transitions | STATE_TRANSITIONS map | .update({ status }) code |
| DB → API → UI | Table column names | API response fields → type definitions |

## Team Communication Protocol

- On discovery: send specific fix request to the relevant agent (file:line + fix method)
- For boundary issues: notify **both** side agents
- To leader: verification report (pass/fail/unverified items separated)
```

---

## Real Case Study: Bugs Found in Production

All content in this guide is extracted from lessons learned from real bugs:

| Bug | Boundary | Root Cause |
|-----|----------|------------|
| `projects?.filter is not a function` | API→Hook | API returned `{projects:[]}`, hook expected bare array |
| All dashboard links 404 | File path→href | `/dashboard/` prefix missing |
| Theme images not showing | API→Component | `thumbnailUrl` vs `thumbnail_url` |
| Theme selection not saving | API→Hook | select-theme API existed, no hook |
| Generation page waits forever | State transition→Code | `template_approved` transition code missing |
| `data.failedIndices` crash | Immediate response→Frontend | Background result accessed from immediate response |
| Post-completion slide view 404 | File path→href | `/projects/` → `/dashboard/projects/` |
