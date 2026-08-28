---
name: linear
description: |
  Use Symphony's `linear_graphql` client tool for raw Linear GraphQL
  operations: comment create/update/delete, issue state transitions, GitHub PR
  attachments, uploads, and issue execution workpad (`## Codex Workpad`) flows
  including Rework reset. Use whenever Linear API access is needed in-session.
---

# Linear GraphQL

Use this skill for raw Linear GraphQL work during Symphony app-server sessions.

## Symphony issue execution — Linear access

`elixir/WORKFLOW.md` requires talking to Linear via a configured **Linear MCP**
server or the injected **`linear_graphql`** tool. **CLI fallback:** when those are
unavailable in the Cursor session but the authenticated **`linear` CLI** works
(`linear issue update`, `linear issue comment add|update`, `linear api`), use it
for states, comments, and raw GraphQL, and record **which tool** was used in
workpad **`Notes`**. If **no** Linear access works, follow the **Prerequisite**
and **Blocked-access escape hatch**: **do not** ask the human to configure Linear
during unattended issue execution. Record what is missing, why it blocks
acceptance/validation, and exact human unblock actions in the workpad (and a
single blocker comment if no workpad exists yet per WORKFLOW Guardrails); for
non-GitHub missing tool/auth, WORKFLOW directs moving to **`In Review`** with the
workpad brief. Then move states per WORKFLOW blocked-access rules.

## Primary tool

Use the `linear_graphql` client tool exposed by Symphony's app-server session.
It reuses Symphony's configured Linear auth for the session.

Tool input:

```json
{
  "query": "query or mutation document",
  "variables": {
    "optional": "graphql variables object"
  }
}
```

Tool behavior:

- Send one GraphQL operation per tool call.
- Treat a top-level `errors` array as a failed GraphQL operation even if the
  tool call itself completed.
- Keep queries/mutations narrowly scoped; ask only for the fields you need.

## Discovering unfamiliar operations

When you need an unfamiliar mutation, input type, or object field, use targeted
introspection through `linear_graphql`.

List mutation names:

```graphql
query ListMutations {
  __type(name: "Mutation") {
    fields {
      name
    }
  }
}
```

Inspect a specific input object:

```graphql
query CommentCreateInputShape {
  __type(name: "CommentCreateInput") {
    inputFields {
      name
      type {
        kind
        name
        ofType {
          kind
          name
        }
      }
    }
  }
}
```

## Common workflows

### Query an issue by key, identifier, or id

Use these progressively:

- Start with `issue(id: $key)` when you have a ticket key such as `MT-686`.
- Fall back to `issues(filter: ...)` when you need identifier search semantics.
- Once you have the internal issue id, prefer `issue(id: $id)` for narrower reads.

Lookup by issue key:

```graphql
query IssueByKey($key: String!) {
  issue(id: $key) {
    id
    identifier
    title
    state {
      id
      name
      type
    }
    project {
      id
      name
    }
    branchName
    url
    description
    updatedAt
    links {
      nodes {
        id
        url
        title
      }
    }
  }
}
```

Lookup by identifier filter:

```graphql
query IssueByIdentifier($identifier: String!) {
  issues(filter: { identifier: { eq: $identifier } }, first: 1) {
    nodes {
      id
      identifier
      title
      state {
        id
        name
        type
      }
      project {
        id
        name
      }
      branchName
      url
      description
      updatedAt
    }
  }
}
```

Resolve a key to an internal id:

```graphql
query IssueByIdOrKey($id: String!) {
  issue(id: $id) {
    id
    identifier
    title
  }
}
```

Read the issue once the internal id is known:

```graphql
query IssueDetails($id: String!) {
  issue(id: $id) {
    id
    identifier
    title
    url
    description
    state {
      id
      name
      type
    }
    project {
      id
      name
    }
    attachments {
      nodes {
        id
        title
        url
        sourceType
      }
    }
  }
}
```

### Query team workflow states for an issue

Use this before changing issue state when you need the exact `stateId`:

```graphql
query IssueTeamStates($id: String!) {
  issue(id: $id) {
    id
    team {
      id
      key
      name
      states {
        nodes {
          id
          name
          type
        }
      }
    }
  }
}
```

### Edit an existing comment

Use `commentUpdate` through `linear_graphql`:

```graphql
mutation UpdateComment($id: String!, $body: String!) {
  commentUpdate(id: $id, input: { body: $body }) {
    success
    comment {
      id
      body
    }
  }
}
```

### Create a comment

Use `commentCreate` through `linear_graphql`:

```graphql
mutation CreateComment($issueId: String!, $body: String!) {
  commentCreate(input: { issueId: $issueId, body: $body }) {
    success
    comment {
      id
      url
    }
  }
}
```

### Issue execution workpad (`## Codex Workpad`)

Symphony’s `elixir/WORKFLOW.md` treats **one** Linear comment per issue as the live
scratchpad. Header must match exactly: `## Codex Workpad`.

**Find or reuse (bootstrap):**

1. Query the issue’s comments (include fields needed to detect resolution/archival
   in your client—Linear exposes different flags over time; skip any comment the
   API marks as resolved, archived, or otherwise ineligible per WORKFLOW).
2. Prefer the **active** workpad: WORKFLOW requires ignoring **resolved** comments
   when searching—only unresolved/active comments qualify.
3. If a reusable workpad exists, note its `id` and use **`commentUpdate`** for all
   further edits. Do not create a second workpad.

**Rework reset (WORKFLOW Step 4):**

When the ticket is in `Rework` and the flow calls for a clean slate: delete the
prior workpad comment (requires permission on that comment), then
**`commentCreate`** a fresh `## Codex Workpad` after branching from
`origin/develop`.

```graphql
mutation DeleteWorkpadComment($id: String!) {
  commentDelete(id: $id) {
    success
  }
}
```

If `commentDelete` fails (permissions, API policy), use the project’s documented
fallback (for example the update script mentioned in WORKFLOW guardrails) and
record the failure mode in the workpad.

**PR linkage vs workpad body:**

- Attach the GitHub PR with **`attachmentLinkGitHubPR`** (or equivalent) so the
  issue shows the PR link.
- Do **not** paste the PR URL into the workpad body—WORKFLOW keeps PR linkage on
  the issue, not duplicated inside the workpad.

**After PR merge (`Merging` → `Done`):** When `.agents/skills/land/SKILL.md` has
completed and the PR is merged, transition the issue to **`Done`** with
`issueUpdate` + the team’s completed `stateId`.

### Move an issue to a different state

Use `issueUpdate` with the destination `stateId`:

```graphql
mutation MoveIssueToState($id: String!, $stateId: String!) {
  issueUpdate(id: $id, input: { stateId: $stateId }) {
    success
    issue {
      id
      identifier
      state {
        id
        name
      }
    }
  }
}
```

### Attach a GitHub PR to an issue

Use the GitHub-specific attachment mutation when linking a PR:

```graphql
mutation AttachGitHubPR($issueId: String!, $url: String!, $title: String) {
  attachmentLinkGitHubPR(
    issueId: $issueId
    url: $url
    title: $title
    linkKind: links
  ) {
    success
    attachment {
      id
      title
      url
    }
  }
}
```

If you only need a plain URL attachment and do not care about GitHub-specific
link metadata, use:

```graphql
mutation AttachURL($issueId: String!, $url: String!, $title: String) {
  attachmentLinkURL(issueId: $issueId, url: $url, title: $title) {
    success
    attachment {
      id
      title
      url
    }
  }
}
```

### Introspection patterns used during schema discovery

Use these when the exact field or mutation shape is unclear:

```graphql
query QueryFields {
  __type(name: "Query") {
    fields {
      name
    }
  }
}
```

```graphql
query IssueFieldArgs {
  __type(name: "Query") {
    fields {
      name
      args {
        name
        type {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
            }
          }
        }
      }
    }
  }
}
```

### Upload a video to a comment

Do this in three steps:

1. Call `linear_graphql` with `fileUpload` to get `uploadUrl`, `assetUrl`, and
   any required upload headers.
2. Upload the local file bytes to `uploadUrl` with `curl -X PUT` and the exact
   headers returned by `fileUpload`.
3. Call `linear_graphql` again with `commentCreate` (or `commentUpdate`) and
   include the resulting `assetUrl` in the comment body.

Useful mutations:

```graphql
mutation FileUpload(
  $filename: String!
  $contentType: String!
  $size: Int!
  $makePublic: Boolean
) {
  fileUpload(
    filename: $filename
    contentType: $contentType
    size: $size
    makePublic: $makePublic
  ) {
    success
    uploadFile {
      uploadUrl
      assetUrl
      headers {
        key
        value
      }
    }
  }
}
```

## Todo kickoff order (`Todo` → `In Progress`)

`elixir/WORKFLOW.md` **Step 0** requires this **exact** startup sequence when
the ticket is in **`Todo`** (before analysis, reproduction, or implementation):

1. Move the issue to **`In Progress`** (`issueUpdate` with the correct
   `stateId`).
2. Find or create the single persistent **`## Codex Workpad`** comment (when
   searching, ignore **resolved** comments—only active/unresolved comments
   qualify).
3. Only then proceed with planning, `pull`, code changes, or validation.

If **`Todo`** already has a PR linked, treat kickoff as a **feedback/rework
loop**: run the full **PR feedback sweep** protocol from WORKFLOW before new
feature work.

## Symphony Issue Lifecycle

In the Symphony project, issue states determine whether the orchestrator
dispatches agents:

- `Backlog` — out of scope for dispatch. Do **not** modify issue state or body;
  wait until a human moves the ticket to `Todo`. Create new `Backlog` issues for
  future work or follow-up items you discover.
- `Todo` — queued. Symphony polls and dispatches an agent run. The first actions
  are the **Todo kickoff order** above (→ `In Progress`, then workpad, then
  work).
- `In Progress` — agent actively working.
- `In Review` — PR attached, waiting on human approval.
- `Merging` — approved by human, the agent executes the `land` flow.
- `Rework` — reviewer requested changes.
- `Done` / `Canceled` / `Duplicate` — terminal states.

Creating an issue in `Backlog` is the safe way to file work without triggering
Symphony. Creating an issue in `Todo` will cause Symphony to dispatch agents
immediately on the next poll tick (default every 5 seconds).

## Provisioning workflow states

Symphony auto-provisions missing workflow states on startup via
`WorkflowProvisioner`. When you need to manually create, audit, or repair
workflow states, use the mutations below.

### Audit current workflow states

`Team.workflowStates` was removed from Linear's schema. Use `Team.states` (paginated `WorkflowStateConnection`) until `pageInfo.hasNextPage` is false:

```graphql
query WorkflowStates($teamId: String!, $first: Int!, $after: String) {
  team(id: $teamId) {
    states(first: $first, after: $after) {
      nodes {
        id
        name
        type
        position
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
```

Do **not** use `draftWorkflowState`, `mergeWorkflowState`, or `startWorkflowState` to enumerate the board — those are singular Git-automation pointers (deprecated in favor of `gitAutomationStates`), not the full workflow.

### Resolve team ID from project slug

```graphql
query TeamByProject($projectSlug: String!) {
  projects(filter: {slugId: {eq: $projectSlug}}, first: 1) {
    nodes {
      teams(first: 1) {
        nodes {
          id
          name
        }
      }
    }
  }
}
```

### Required Symphony workflow states

Symphony expects these states on the team workflow:

| State | Type | Purpose |
|-------|------|---------|
| Backlog | backlog | Parked work, ignored by Symphony |
| Todo | unstarted | Queued for agent dispatch |
| In Progress | started | Agent actively working |
| In Review | started | PR attached, waiting for human |
| Merging | started | Human approved, auto-merge |
| Rework | started | Reviewer requested changes |
| Done | completed | Terminal success |
| Canceled | canceled | Terminal cancel |
| Duplicate | canceled | Terminal duplicate (treat as terminal; no further dispatch) |

### Create a missing workflow state

```graphql
mutation CreateWorkflowState($input: WorkflowStateCreateInput!) {
  workflowStateCreate(input: $input) {
    success
    workflowState {
      id
      name
      type
      position
    }
  }
}
```

Input fields:
- `teamId` (required) — team UUID
- `name` (required) — display name (e.g. "In Review")
- `type` — one of: `backlog`, `unstarted`, `started`, `completed`, `canceled`
- `color` — hex color (e.g. "#f2c94c")
- `position` — float for ordering (e.g. 2.5 between positions 2 and 3)

Color conventions used by Symphony:
- Backlog → `#bec2c8`, Todo → `#e2e2e2`, In Progress → `#f2c94c`
- In Review → `#f2994a`, Merging → `#5e6ad2`, Rework → `#eb5757`
- Done → `#5dc97c`, Canceled/Duplicate → `#95a2b3`

### Verify Symphony activity after Todo creation

When you create a `Todo` issue, Symphony creates a workspace within seconds:

```bash
ls ~/code/symphony-workspaces/<issue-identifier>
```

### Creating follow-up issues from an agent session

When discovering out-of-scope improvements during execution, file a follow-up
`Backlog` issue that:
- has a clear title, description, and acceptance criteria;
- is in the same project;
- links the current issue as `related`;
- uses `blockedBy` when the follow-up depends on the current issue.

### Create an issue

Use `issueCreate`. The only strictly required field is `teamId` + `title`, but
you MUST always set `projectId` so Symphony can discover the issue (Symphony
queries by project slug). You should also set `stateId` to control whether
Symphony picks it up.

```graphql
mutation CreateIssue(
  $teamId: String!,
  $title: String!,
  $projectId: String!,
  $description: String,
  $stateId: String,
  $priority: Int,
  $labelIds: [String!],
  $assigneeId: String
) {
  issueCreate(input: {
    teamId: $teamId,
    title: $title,
    projectId: $projectId,
    description: $description,
    stateId: $stateId,
    priority: $priority,
    labelIds: $labelIds,
    assigneeId: $assigneeId
  }) {
    success
    issue {
      id
      identifier
      title
      url
      project { id name }
      state { id name type }
      priority
      labels { nodes { id name } }
      assignee { id name }
    }
  }
}
```

### Find team ID and workflow states

Creating or moving an issue requires `teamId` and `stateId`. Discover them:

```graphql
query TeamStates($teamKey: String) {
  teams(filter: { key: { eq: $teamKey } }, first: 1) {
    nodes {
      id
      name
      key
      states {
        nodes {
          id
          name
          type
          position
        }
      }
    }
  }
}
```

If you already have a known issue, get its team states directly:

```graphql
query IssueTeamStates($id: String!) {
  issue(id: $id) {
    team {
      id
      key
      states { nodes { id name type } }
    }
  }
}
```

### Find team labels

Labels are scoped to a team. List them before assigning:

```graphql
query TeamLabels($teamId: String!) {
  team(id: $teamId) {
    id
    labels { nodes { id name } }
  }
}
```

### Create an issue with labels

After looking up label IDs from the team, pass them in `labelIds`:

```graphql
mutation CreateIssueWithLabels(
  $teamId: String!,
  $title: String!,
  $stateId: String,
  $labelIds: [String!]
) {
  issueCreate(input: {
    teamId: $teamId,
    title: $title,
    stateId: $stateId,
    labelIds: $labelIds
  }) {
    success
    issue {
      id
      identifier
      labels { nodes { id name } }
    }
  }
}
```

### Update an issue (fields beyond state)

`issueUpdate` supports updating title, description, priority, labels,
assignee, and state simultaneously:

```graphql
mutation UpdateIssue(
  $id: String!,
  $title: String,
  $description: String,
  $priority: Int,
  $stateId: String,
  $labelIds: [String!],
  $assigneeId: String
) {
  issueUpdate(id: $id, input: {
    title: $title,
    description: $description,
    priority: $priority,
    stateId: $stateId,
    labelIds: $labelIds,
    assigneeId: $assigneeId
  }) {
    success
    issue {
      id
      identifier
      title
      description
      state { id name }
      priority
      labels { nodes { id name } }
      assignee { id name }
    }
  }
}
```

Omitted fields are left unchanged. `labelIds` replaces the full set — to
preserve existing labels, include their IDs in the list. Priority follows
Linear's scale (lower = higher priority; 1 = urgent, 4 = low).

### Resolve current viewer

When you need your own user ID for self-assignment:

```graphql
query Viewer { viewer { id name email } }
```

### Assign an issue

```graphql
mutation AssignIssue($id: String!, $assigneeId: String!) {
  issueUpdate(id: $id, input: { assigneeId: $assigneeId }) {
    success
    issue { id identifier assignee { id name } }
  }
}
```

### Unassign an issue

```graphql
mutation UnassignIssue($id: String!) {
  issueUpdate(id: $id, input: { assigneeId: null }) {
    success
    issue { id identifier assignee { id name } }
  }
}
```

## Usage rules

- Use `linear_graphql` for comment edits, uploads, and ad-hoc Linear API
  queries.
- Prefer the narrowest issue lookup that matches what you already know:
  key -> identifier search -> internal id.
- For state transitions, fetch team states first and use the exact `stateId`
  instead of hardcoding names inside mutations.
- Prefer `attachmentLinkGitHubPR` over a generic URL attachment when linking a
  GitHub PR to a Linear issue.
- Do not introduce new raw-token shell helpers for GraphQL access.
- If you need shell work for uploads, only use it for signed upload URLs
  returned by `fileUpload`; those URLs already carry the needed authorization.
