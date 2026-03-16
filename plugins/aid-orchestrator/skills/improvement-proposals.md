---
name: improvement-proposals
description: Standard format for improvement notes — collection protocol, deduplication, Curator 3-tier evaluation
user_invocable: false
---

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

The Curator agent follows this protocol during the CURATOR_RESOLVE state (after all gates pass, before PM_APPROVAL):

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
  .aid-o/work/backlog.md          → known issues, proposals, history
  .aid-o/work/lessons-learned.md  → past lessons (avoid re-proposing solved issues)
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
| Same note persists across 2+ runs | Escalate one level (low→medium, medium→high) |
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

Location: `.aid-o/work/backlog.md`

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
- Note persists across 2+ runs without resolution

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
| `small` | < 1 run, localized change, no architecture impact |
| `medium` | 1-2 runs, touches multiple files, minor architecture change |
| `large` | 3+ runs, significant refactoring, architecture change |

---

## 6. Orchestrator Integration (CURATOR_RESOLVE State)

The Orchestrator auto-evaluates each Curator proposal during the CURATOR_RESOLVE state
(after GATES pass, before PM_APPROVAL) using a 3-tier algorithm.

### 3-Tier Auto-Evaluate Algorithm

```
for each proposal in curator_report.proposals:

  Tier 1: YAML Explicit Rules (highest priority, deterministic)
    Load curator_auto_rules from decision-policies.yaml.
    Check in order:
      → always_approve[] match on {type, area, priority}? → decision = APPROVE
      → always_reject[] match? → decision = REJECT
      → always_defer[] match? → decision = DEFER
    Rule matching: all specified keys must match. area uses glob matching.
    First match wins.
    Log: {"state": "CURATOR_RESOLVE", "action": "auto_evaluate",
          "proposal": "IMP-{NNN}", "decision": "{action}", "rule": "{matched_rule}"}

  Tier 2: Qdrant Past-Decision Similarity (if learning.enabled)
    No Tier 1 match → query Qdrant:
      → Search: type=curator_decision, similar to proposal title+area+type
      → If similarity > learning.similarity_threshold (default: 0.80) AND
        matching decisions >= learning.min_decisions (default: 3):
        → Apply majority action from past decisions
        → Log: "learned from {N} past decisions"
    If Qdrant unavailable: skip Tier 2, fall through to Tier 3.
    Warning logged: "Qdrant unavailable — learning disabled for this EPIC"

  Tier 3: Default Action (lowest priority, fallback)
    No rule match, no Qdrant history:
      → Apply curator_auto_rules.default_action (default: approve)
      → Log: "default rule applied"
```

### Decision Actions

| Decision | Backlog Status | Orchestrator Action |
|----------|---------------|---------------------|
| **APPROVE** | `implementing` → `implemented` | Dispatch fix agent for the proposal. After fix: update backlog, store fix output in evidence. |
| **REJECT** | `orchestrator-rejected` | Reason logged. PM sees rejection in Curator summary at PM_APPROVAL. |
| **DEFER** | `deferred` | Reason logged. PM sees deferral in Curator summary at PM_APPROVAL. |

Fix agent dispatch for APPROVED proposals:
- Determine agent role from proposal area/type (backend, frontend, docs, etc.)
- No limits on fix size or effort -- Orchestrator approves everything relevant
- If fix agent fails: set proposal status to `deferred` with reason "fix attempt failed"

### PM Override at PM_APPROVAL

After CURATOR_RESOLVE, PM receives a compact summary with override capabilities:

**PM "fix IMP-{NNN}" (override a rejection):**
1. Dispatch fix agent for the specified proposal
2. Update backlog.md: status -> implemented, actor: pm-override
3. Store PM decision in Qdrant for learning
4. Log: `{"state": "PM_APPROVAL", "action": "pm_override", "proposal": "IMP-{NNN}"}`

**PM "always approve {pattern}" (teach a rule):**
1. Parse instruction to extract: type, area, or priority pattern
2. Append to `decision-policies.yaml` -> `curator_auto_rules.always_approve[]`
3. Store in Qdrant as `curator_decision` with `pm_instruction` field
4. Confirm to PM: "Rule added: always approve {pattern}"
5. Log: `{"state": "PM_APPROVAL", "action": "rule_learned", "rule": "{pattern}"}`

### Qdrant Decision Storage (`curator_decision`)

Every auto-evaluate decision, PM override, and PM rule-teach is stored in Qdrant
for future learning:

```json
{
  "data": "Decision for proposal IMP-{NNN}: {action}. Type: {type}, Area: {area}. {reason}",
  "metadata": {
    "type": "curator_decision",
    "action": "approve|reject|defer",
    "proposal_type": "{type}",
    "proposal_area": "{area}",
    "project_name": "{project_name}",
    "epic_id": "{epic_id}",
    "decision_source": "yaml_rule|qdrant_learned|default|pm_override|pm_teach",
    "pm_instruction": "{instruction if PM-originated}",
    "timestamp": "{ISO 8601}"
  }
}
```

Graceful degradation: if Qdrant unavailable, Tier 2 is skipped, PM decisions are NOT
stored (logged to stage_log only), warning logged.

---

## 7. Integration Points

| Component | How it uses this skill |
|-----------|----------------------|
| Role agents (9) | Output format -- `improvement_notes` in `step_output` |
| Playbooks (9) | Guidance -- when and how to record notes |
| Curator agent | Collection protocol -- Steps 1-5 |
| Orchestrator (CURATOR_RESOLVE) | 3-tier auto-evaluate algorithm -- Section 6 |
| `backlog.md` | Storage format -- Section 4 |
| `decision-policies.yaml` | `curator_auto_rules` -- Tier 1 YAML rules for auto-evaluate |
| Qdrant (`curator_decision`) | Tier 2 learned decisions + decision storage |
| `epic-orchestration.md` | CURATOR_RESOLVE state triggers Curator + auto-evaluate |
| `run-epic.md` | CURATOR_RESOLVE state handling dispatches Curator |
