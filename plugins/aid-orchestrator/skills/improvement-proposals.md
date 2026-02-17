# Improvement Proposals Skill

**Purpose:** Define the standard format for `improvement_notes`, collection protocol,
deduplication rules, and integration with `backlog.md`.

**Used by:**
- All 9 role agents (output format)
- Curator agent (collection + deduplication + proposals)
- Orchestrator (proposal evaluation)

---

## 1. Improvement Notes Format

Every role agent MUST include an `improvement_notes` field in their `step_output`.
The field is always present — use an empty list `[]` if no observations.

```yaml
improvement_notes:
  - type: refactoring|performance|security|architecture|dx
    area: "path/to/file-or-module"
    observation: "What you observed — describe the problem"
    suggestion: "Concrete suggestion — what should be done"
    priority: low|medium|high
    source_agent: "{agent_role}"
    source_step: "{step_id}"
```

### Field Definitions

| Field | Required | Description |
|-------|----------|-------------|
| `type` | yes | Category of observation |
| `area` | yes | File path or module area affected |
| `observation` | yes | Factual description of what was observed |
| `suggestion` | yes | Concrete, actionable suggestion (not vague) |
| `priority` | yes | Impact level |
| `source_agent` | yes | Which agent role recorded this |
| `source_step` | yes | Which plan step this was observed during |

### Type Categories

| Type | Description | Examples |
|------|-------------|---------|
| `refactoring` | Code that works but should be restructured | Duplicated logic, god class, deep nesting |
| `performance` | Performance bottleneck or inefficiency | N+1 queries, missing cache, unnecessary re-renders |
| `security` | Security risk or vulnerability | Hardcoded secrets, missing input validation, weak auth |
| `architecture` | Architectural concern or pattern violation | Wrong layer dependency, missing abstraction, contract drift |
| `dx` | Developer experience issue | Missing types, unclear API, missing docs, poor error messages |

### Priority Levels

| Priority | Criteria |
|----------|----------|
| `low` | Nice to have. No immediate impact. Can wait. |
| `medium` | Should be addressed. Causes friction or minor risk. |
| `high` | Significant impact on quality, security, or maintainability. Address soon. |

---

## 2. When to Record Improvement Notes

### Record When

- You see code that could be improved but is **NOT in your current task scope**
- You find a potential security risk **outside your assigned files**
- You identify an architectural pattern that should be more consistent
- You notice duplicated code across modules
- You see missing or outdated documentation for important features
- You observe a performance bottleneck you weren't tasked to fix
- You notice DX issues (missing types, unclear API, poor error messages)

### Do NOT Record When

- The issue is **in your current task** — fix it directly in your implementation
- It's a **style preference** without objective backing (personal taste)
- The suggestion would require a **complete rewrite** with unclear benefit
- The issue is **already tracked** in backlog.md (Curator handles deduplication, but avoid obvious duplicates)
- It's a **known limitation** documented in decisions.yaml

### Quality Bar

Each note must be:
- **Specific** — points to actual file/module, not "the code needs work"
- **Actionable** — suggestion can be implemented without further research
- **Objective** — based on measurable criteria (complexity, duplication, security standard)
- **Scoped** — one observation per note, not a list of grievances

**Bad example:**
```yaml
- type: refactoring
  area: "src/"
  observation: "Code is messy"
  suggestion: "Clean it up"
  priority: medium
```

**Good example:**
```yaml
- type: refactoring
  area: "src/auth/middleware.py"
  observation: "Token validation logic duplicated in 3 route handlers (lines 42, 87, 134)"
  suggestion: "Extract shared validate_token() middleware, apply to routes via decorator"
  priority: high
```

---

## 3. Collection Protocol

The Curator agent follows this protocol after each session-end:

### Step 1: Collect

```
Read all step outputs from the latest run:
  evidence/{epic_id}/{run_id}/steps/*/step_output.json

Extract improvement_notes arrays from each step output.
Merge into a single flat list.
Tag each note with its source (agent + step) if not already tagged.
```

### Step 2: Load Context

```
Read existing data:
  .aid-o/04-engine/backlog.md          → known issues, proposals, history
  .aid-o/04-engine/lessons-learned.md  → past lessons (avoid re-proposing solved issues)
```

### Step 3: Deduplicate

For each collected note, compare against existing backlog entries:

**Exact match** — same `type` + `area` + similar `observation` (>80% overlap):
- Do NOT create new entry
- Add `source_agent`/`source_step` as additional source to existing entry
- If new source increases source count to 3+ → escalate priority (see Step 4)

**Similar match** — same `area` + related `type` (e.g., both about auth module):
- Merge observations if they describe the same underlying issue
- Keep the more specific suggestion
- Combine sources

**New** — no match found:
- Add to pending queue for proposal generation

### Step 4: Priority Escalation

Automatic priority adjustments:

| Condition | Action |
|-----------|--------|
| 3+ agents report same area + type | Escalate to `high` priority |
| `security` type with any priority | Minimum `medium` priority |
| Same note persists across 2+ sessions | Escalate one level (low→medium, medium→high) |
| Note matches a `lessons-learned.md` pattern | Flag as "recurring — needs systemic fix" |

### Step 5: Update Backlog

```
For each new/escalated note:
  1. Assign ID: IMP-{NNN} (auto-increment, never reuse)
  2. Add to backlog.md in appropriate section:
     - New proposals → "Active Proposals" table
     - Deduplication merges → update existing row (add sources, adjust priority)
  3. Record timestamp
```

---

## 4. Backlog.md Format

Location: `.aid-o/04-engine/backlog.md`

```markdown
# Backlog

> Last updated: {ISO 8601 timestamp}
> Total entries: {N} | Active: {N} | Deferred: {N} | Rejected: {N} | Implemented: {N}

## Active Proposals

| ID | Type | Area | Observation | Suggestion | Priority | Sources | Status | Created |
|-----|------|------|------------|-----------|----------|---------|--------|---------|
| IMP-001 | refactoring | src/auth/ | Token validation duplicated in 3 handlers | Extract shared middleware | high | architect,backend,security | pending | 2026-02-17 |
| IMP-002 | dx | src/api/ | No TypeScript types for API responses | Generate types from OpenAPI spec | medium | frontend | pending | 2026-02-17 |

## Deferred

| ID | Type | Area | Suggestion | Reason | Deferred by | Date |
|-----|------|------|-----------|--------|-------------|------|
| IMP-003 | architecture | src/events/ | Move to event sourcing | Too large for current sprint | PM | 2026-02-17 |

## Rejected

| ID | Type | Area | Suggestion | Rejected by | Reason | Date |
|-----|------|------|-----------|-------------|--------|------|
| IMP-004 | refactoring | src/legacy/ | Rewrite in Rust | orchestrator | Cost/benefit ratio too low | 2026-02-17 |

## Implemented

| ID | Type | Area | Epic Ref | Implemented | Date |
|-----|------|------|----------|-------------|------|
| IMP-005 | security | src/auth/ | E-20260220-auth | Fixed hardcoded secret | 2026-02-20 |
```

### Status Values

| Status | Meaning | Who sets it |
|--------|---------|-------------|
| `pending` | New, awaiting Orchestrator evaluation | Curator |
| `proposed` | Orchestrator approved, sent to PM | Orchestrator |
| `approved` | PM approved, Epic will be created | PM |
| `deferred` | PM deferred to later | PM |
| `pm-rejected` | PM rejected | PM |
| `orchestrator-rejected` | Orchestrator rejected before PM | Orchestrator |
| `implemented` | Done, linked to Epic | Orchestrator |

### ID Schema

- Format: `IMP-{NNN}` (zero-padded 3 digits)
- Auto-incrementing, sequential
- **Never reuse** — even if entry is rejected or implemented
- Start from `IMP-001`

---

## 5. Proposal Generation

The Curator generates proposals for the Orchestrator from high-priority notes:

### Proposal Criteria

Generate a proposal when:
- Priority is `high`
- 3+ sources report the same issue
- Security type with `medium` or `high` priority
- Note persists across 2+ sessions without resolution

### Proposal Format

```yaml
proposal:
  id: "IMP-{NNN}"
  title: "Short descriptive title"
  type: refactoring|performance|security|architecture|dx
  area: "affected path/module"
  rationale: "Why this should be addressed — evidence from agents"
  proposed_action: "Concrete steps to implement"
  effort: small|medium|large
  priority: high
  sources:
    - agent: "backend"
      step: "step-3"
      observation: "Token validation duplicated..."
    - agent: "security"
      step: "step-5"
      observation: "Auth middleware inconsistent..."
  cost_benefit: "Brief analysis of cost vs benefit"
```

### Effort Estimates

| Effort | Description |
|--------|-------------|
| `small` | < 1 session, localized change, no architecture impact |
| `medium` | 1-2 sessions, touches multiple files, minor architecture change |
| `large` | 3+ sessions, significant refactoring, architecture change |

---

## 6. Orchestrator Integration

```
Curator sends proposals to Orchestrator:

Orchestrator evaluates each proposal:
  ├── REJECT → backlog.md status: orchestrator-rejected
  │     Reason logged. Info sent to PM (Slack / chat).
  │
  └── APPROVE → proposal forwarded to PM
        PM decides:
        ├── APPROVE → Orchestrator creates new Epic
        ├── DEFER  → backlog.md status: deferred (with reason + date)
        └── REJECT → backlog.md status: pm-rejected (with reason)

All transitions logged in backlog.md with timestamp + actor.
```

### Orchestrator Rejection Criteria

The Orchestrator SHOULD reject proposals that:
- Have effort `large` with priority `low`
- Duplicate a recently rejected proposal (< 30 days)
- Conflict with an active Epic or architectural decision
- Are outside project scope

The Orchestrator SHOULD NOT reject proposals that:
- Are `security` type with `high` priority
- Have 3+ independent sources
- Address persistent issues (2+ sessions)

---

## 7. Integration Points

| Component | How it uses this skill |
|-----------|----------------------|
| Role agents (9) | Output format — `improvement_notes` in `step_output` |
| Playbooks (9) | Guidance — when and how to record notes |
| Curator agent | Collection protocol — Steps 1-5 |
| Orchestrator | Proposal evaluation — Section 6 |
| `backlog.md` | Storage format — Section 4 |
| `run-epic.md` | POST_PROCESSING state triggers Curator |
| `session-management.md` | session-end triggers Curator |
