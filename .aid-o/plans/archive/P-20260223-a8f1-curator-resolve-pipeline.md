---
id: P-20260223-a8f1
type: plan
status: completed
completed: 2026-02-23
created: 2026-02-23
author: PM + AI
---

# Plan: Curator Resolution Pipeline — Auto-Evaluate, Fix, Learn

## Context

The AID Orchestrator plugin (v0.6.0) has a Curator agent and Lessons-Extractor that produce valuable outputs (improvement proposals, lessons, gotchas), but these outputs hit dead ends:

1. **Curator proposals have no resolution path.** They land in `backlog.md` with status `proposed` and stay there — the Orchestrator never evaluates or resolves them. The Curator runs in DONE state (after PM_APPROVAL), so proposals are never acted upon within the EPIC that generated them. 15 unresolved proposals across 6 completed EPICs.
2. **Lessons-Extractor has weak dedup.** Only >80% text overlap against local `lessons-learned.md`. No Qdrant semantic dedup, no cross-session awareness — duplicates accumulate.
3. **ID schema mismatch.** `backlog.md` uses `PROP-{YYYYMMDD}-{NNN}` but the spec (`improvement-proposals.md`, `curator.md`) defines `IMP-{NNN}`.
4. **No analytics integration.** `/aid-analytics` doesn't read backlog health or curator pipeline metrics.
5. **No learning mechanism.** Orchestrator doesn't learn from PM approval patterns. Same proposals get re-evaluated without context every time.

Triggered by: `/aid-analytics` project review (2026-02-23) revealing 0 retries, 0 escalations, but 15 unresolved backlog proposals across 6 completed EPICs.

## Goal

Add a CURATOR_RESOLVE state to the EPIC orchestration pipeline that auto-evaluates Curator proposals before PM approval, implements approved fixes within the current EPIC, presents a compact summary to PM with override capability, and learns from PM decisions for future auto-resolution.

## Scope

**In scope:**
- New CURATOR_RESOLVE state in epic-orchestration state machine (between GATES and PM_APPROVAL)
- Auto-evaluate algorithm (YAML rules + Qdrant learned decisions + default)
- Fix agent dispatch for approved proposals (within current EPIC)
- PM override and rule-teaching at PM_APPROVAL
- Lessons-Extractor 3-layer dedup (text + semantic + Qdrant)
- Move Curator + Lessons-Extractor dispatch from DONE to CURATOR_RESOLVE
- Analytics "Improvement Pipeline" section in `/aid-analytics`
- `curator_auto_rules` section in `decision-policies.yaml`
- `backlog.md` ID migration (PROP → IMP)
- DONE state simplification (remove moved items)

**Out of scope:**
- Auditor changes (process audit from P-20260222-cfe6 is separate)
- `/aid-brainstorm` backlog awareness integration (future EPIC)
- `/aid-backlog` user-facing command (future EPIC)
- Curator agent internal logic changes (collection, dedup, pattern analysis unchanged)

## Approach

### Option A: New CURATOR_RESOLVE State (Recommended)

Add a dedicated state between GATES and PM_APPROVAL:

```
Steps → Gates → CURATOR_RESOLVE → PM_APPROVAL → DONE
```

CURATOR_RESOLVE sub-steps:
1. Parallel dispatch: Curator (sonnet) + Lessons-Extractor (haiku)
2. Auto-evaluate each proposal via 3-tier algorithm (YAML rules → Qdrant history → default)
3. Dispatch fix agents for all approved proposals (no effort limit)
4. Process LE output with 3-layer dedup, write to workspace files
5. Prepare compact PM summary (implemented/rejected/deferred)
6. Transition to PM_APPROVAL (which now includes Curator summary + PM override/teach options)

**Pros:**
- Clean separation in state machine — dedicated state with clear purpose
- Best traceability in stage_log (CURATOR_RESOLVE entries)
- PM sees resolved proposals BEFORE approving merge
- Orchestrator learns from PM overrides (YAML + Qdrant)
- DONE state becomes simpler

**Cons:**
- Larger structural change (new state + renumbering)
- All existing references to "Curator in DONE" must be updated

### Option B: Enriched GATES State

Add Curator + LE into existing GATES state.

**Pros:** No new state, smaller change.
**Cons:** GATES becomes overloaded (quality gates + curator + lessons + fixes). Semantically wrong — gates are technical checks, not improvement pipeline.

### Option C: Pre-processing in PM_APPROVAL

Extend PM_APPROVAL with a "pre-processing" phase.

**Pros:** Minimal structural change.
**Cons:** PM_APPROVAL does too much. Curator resolution mixed with PM decision logic.

### Decision

**Chosen:** Option A
**Rationale:** Clean state separation, best traceability, extensible (brainstorm integration later). The larger change is justified by the clear architectural improvement.

---

## CURATOR_RESOLVE State Specification

### State Position

```
IDLE → PLANNING → PLAN_REVIEW → EXECUTING → PHASE_CHECK → NEXT_PHASE
  → GATES → GATE_RETRY → CURATOR_RESOLVE → PM_APPROVAL → DONE
```

### State Table Row

| State | Description | Exit Condition | Evidence |
|-------|-------------|----------------|----------|
| **CURATOR_RESOLVE** | Dispatch Curator + Lessons-Extractor in parallel; auto-evaluate proposals via `decision-policies.yaml` rules + Qdrant history; dispatch fix agents for approved proposals; write lessons to workspace files | All proposals resolved, fixes complete | `curator_resolve_report.json`, updated `backlog.md`, updated `lessons-learned.md` |

### Trigger

All gates passed (transition from GATES).

### Sub-Steps

**1. Parallel Dispatch:**

```
a. Dispatch Curator agent (agents/curator.md, model: sonnet) with:
   - All step outputs: evidence/{epic_id}/{run_id}/steps/*/step_output.json
   - Gate results: evidence/{epic_id}/{run_id}/gates_report.json
   - Final report: evidence/{epic_id}/{run_id}/final_report.md
b. Dispatch Lessons-Extractor agent (agents/lessons-extractor.md, model: haiku) with:
   - Active session file
   - Git log and diff
c. Log: {"state": "CURATOR_RESOLVE", "action": "dispatch_parallel",
         "details": "Curator + Lessons-Extractor dispatched"}
```

**2. Process Curator Output:**

```
a. Parse curator_report.proposals[] from Curator agent output
b. If no proposals: log "0 proposals", skip to sub-step 4
c. For each proposal: run Auto-Evaluate Algorithm (sub-step 3)
```

**3. Auto-Evaluate Algorithm** (per proposal):

```
for each proposal in curator_report.proposals:
  1. Load curator_auto_rules from decision-policies.yaml
  2. Check explicit YAML rules:
     - always_approve[] → match on {type, area, priority}?
       → YES: decision = APPROVE. Log rule match.
     - always_reject[] → match?
       → YES: decision = REJECT. Log rule match.
     - always_defer[] → match?
       → YES: decision = DEFER. Log rule match.
  3. No explicit rule matched → Query Qdrant:
     - Search: type=curator_decision, similar to proposal title+area+type
     - If similarity > learning.similarity_threshold AND
       matching decisions >= learning.min_decisions:
       → Apply majority action from past decisions
       → Log: "learned from {N} past decisions"
  4. No rule, no Qdrant history:
     → Apply curator_auto_rules.default_action (default: approve)
     → Log: "default rule applied"
```

Decision stage_log entries:

```json
// APPROVE
{"state": "CURATOR_RESOLVE", "action": "auto_evaluate", "proposal": "IMP-{NNN}",
 "decision": "approve", "rule": "{matched_rule_or_source}"}

// REJECT
{"state": "CURATOR_RESOLVE", "action": "auto_evaluate", "proposal": "IMP-{NNN}",
 "decision": "reject", "reason": "{reason}"}

// DEFER
{"state": "CURATOR_RESOLVE", "action": "auto_evaluate", "proposal": "IMP-{NNN}",
 "decision": "defer", "reason": "{reason}"}
```

Backlog status updates per decision:
- **APPROVE:** `implementing` → (after fix) `implemented`
- **REJECT:** `orchestrator-rejected` (reason logged)
- **DEFER:** `deferred` (reason logged)

**4. Process Lessons-Extractor Output:**

```
a. Parse LE report for NEW LESSONS, NEW COMMANDS, NEW GOTCHAS sections
b. 3-layer dedup for each lesson/gotcha (see Lessons-Extractor 3-Layer Dedup section)
c. Write new lessons to .aid-o/04-engine/lessons-learned.md
d. Write new commands to .aid-o/04-engine/command-history.md
e. Store to Qdrant (if available) with metadata:
   {"type": "lesson", "subtype": "lesson|gotcha|command",
    "project_name": "{project_name}", "epic_id": "{epic_id}",
    "area": "{area}", "timestamp": "{ISO 8601}"}
f. Log: {"state": "CURATOR_RESOLVE", "action": "lessons_written",
         "new_lessons": {N}, "new_commands": {N}, "duplicates_skipped": {N}}
```

**5. Dispatch Approved Fixes:**

```
For each APPROVED proposal:
  a. Determine agent role from proposal area/type (backend, frontend, docs, etc.)
  b. Dispatch fix agent with:
     - Proposal details (title, area, proposed_action, rationale)
     - Current file contents for the affected area
     - Instruction: implement the proposed fix, produce diff output
  c. Wait for fix completion
  d. Update backlog.md: status → implemented, epic_ref: current EPIC
  e. Store fix output in evidence/{epic_id}/{run_id}/curator_fixes/fix_{IMP_id}/
  f. Log each fix:
     {"state": "CURATOR_RESOLVE", "action": "fix_completed", "proposal": "IMP-{NNN}",
      "files_modified": ["path/to/file"], "agent": "{role}"}

If a fix agent fails: log warning, set proposal status → deferred with reason
"fix attempt failed", continue with remaining fixes.
```

No limits on fix size or effort — the Orchestrator approves everything relevant regardless of scope.

**6. Prepare PM Summary:**

```
Compile CURATOR_RESOLVE results into structured block for PM_APPROVAL:

--- Curator Resolution ---
Implemented ({count}):
  - IMP-{NNN}: {title} (effort: {effort})
Rejected by Orchestrator ({count}):
  - IMP-{NNN}: {title}
    Reason: {reason} [Rule: {rule_source}]
Deferred ({count}):
  - IMP-{NNN}: {title}
    Reason: {reason}
Lessons: {count} new | Gotchas: {count} new | Commands: {count} new

Store as evidence/{epic_id}/{run_id}/curator_resolve_report.json
```

**7. Transition → PM_APPROVAL**

```json
{"state": "CURATOR_RESOLVE", "action": "transition",
 "details": "{approved} approved ({fixed} fixed), {rejected} rejected, {deferred} deferred. → PM_APPROVAL"}
```

---

## PM_APPROVAL Extension

### Curator Summary Block

The PM_APPROVAL payload MUST include the Curator Resolution summary loaded from `curator_resolve_report.json`:

```
EPIC Ready for Approval: {epic_id}
====================================
Steps: {completed}/{total} | Gates: {passed}/{total} | Duration: {duration}

--- Curator Resolution ---
Implemented ({count}):
  - IMP-{NNN}: {title} (effort: {effort})

Rejected by Orchestrator ({count}):
  - IMP-{NNN}: {title}
    Reason: {reason} [Rule: {rule_source}]

Deferred ({count}):
  - IMP-{NNN}: {title}
    Reason: {reason}

Lessons: {count} new | Gotchas: {count} new

PM Actions:
  1. APPROVE — merge everything, EPIC done
  2. Override rejected: "fix IMP-{NNN}" — Orchestrator dispatches fix agent
  3. Teach rule: "always approve {type/area}" — added to auto-rules + Qdrant
  4. REJECT — do not merge
```

### PM Override Handling

If PM says "fix IMP-{NNN}" (override a rejected proposal):

```
a. Dispatch fix agent for the specified proposal
b. Update backlog.md: status → implemented, actor: pm-override
c. Store PM decision in Qdrant for learning:
   {"type": "curator_decision", "action": "approve",
    "proposal_type": "{type}", "proposal_area": "{area}",
    "project_name": "{project_name}", "epic_id": "{epic_id}",
    "pm_instruction": "override rejection", "timestamp": "{ISO 8601}"}
d. Log: {"state": "PM_APPROVAL", "action": "pm_override", "proposal": "IMP-{NNN}"}
```

### PM Rule Teaching

If PM says "always approve {pattern}" or similar:

```
a. Parse instruction to extract: type, area, or priority pattern
b. Append to decision-policies.yaml → curator_auto_rules.always_approve[]
c. Store in Qdrant as curator_decision with pm_instruction field
d. Confirm to PM: "Rule added: always approve {pattern}"
e. Log: {"state": "PM_APPROVAL", "action": "rule_learned", "rule": "{pattern}"}
```

---

## DONE State Simplification

### Items Removed from DONE (moved to CURATOR_RESOLVE)

- Item 3: POST-PROCESSING — Lessons-Extractor dispatch
- Item 4: Lessons-Learned File Update
- Item 5: Command-History File Update
- Item 9: Curator Post-Processing (proposals + backlog)

### Items Retained in DONE

- Item 1: Merge branch
- Item 2: Archive evidence
- Item 6: Stage log final entry
- Item 7: Auditor dispatch (audits final state INCLUDING Curator fixes)
- Item 8: Session status update
- Item 9b: Example EPIC Extraction (if eligible)
- Item 10: EPIC Queue check
- Item 11: Slack summary

### Migration Note

```
NOTE: Curator dispatch, Lessons-Extractor dispatch, and lessons/command-history
file writes have been moved to the CURATOR_RESOLVE state. They now run BEFORE
PM_APPROVAL, not after it. The Auditor remains in DONE because it audits the
final state including any Curator fixes.
```

### DONE Evidence Column Update

Remove `curator_report.json` from DONE evidence (moved to CURATOR_RESOLVE). DONE evidence becomes: `final_report.md`, `audit-report.md`, `slack_log.jsonl`.

---

## Auto-Evaluate Rules Configuration

### `curator_auto_rules` in decision-policies.yaml

```yaml
# ─── Curator Auto-Resolution Rules ───────────────────────────────────
# Used by CURATOR_RESOLVE state to auto-evaluate improvement proposals.
# PM can teach new rules via "always approve {pattern}" at PM_APPROVAL.
curator_auto_rules:
  # Explicit rules (deterministic, highest priority)
  always_approve:
    - { type: dx }                         # DX improvements always
    - { type: security, priority: high }   # Critical security always
    - { area: "docs/*" }                   # Documentation always

  always_reject: []
    # Example: - { type: refactoring, area: "legacy/*" }

  always_defer:
    - { type: architecture }               # Architecture changes need separate planning

  # Default behavior when no rule matches and no Qdrant history found
  default_action: approve   # approve | defer | reject

  # Qdrant learning settings
  learning:
    enabled: true
    similarity_threshold: 0.80   # Min similarity score for past-decision match
    min_decisions: 3              # Min past decisions with same action to trust pattern
```

### Rule Matching Logic

Each rule is a dictionary with optional keys `{type, area, priority}`. A proposal matches a rule when ALL specified keys match:
- `type`: exact match against proposal type
- `area`: glob match against proposal area (e.g., `docs/*` matches `docs/api/auth.md`)
- `priority`: exact match against proposal priority

First match wins — rules are evaluated in order within each list.

---

## Qdrant Learning Storage

### `curator_decision` Type

Every auto-evaluate decision, PM override, and PM rule-teach is stored in Qdrant for future learning:

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

### Graceful Degradation

If Qdrant is unavailable:
- Tier 2 (Qdrant lookup) is skipped — fall through to Tier 3 (default action)
- PM decisions are NOT stored (logged to stage_log only)
- A warning is logged: `"Qdrant unavailable — learning disabled for this EPIC"`

---

## Lessons-Extractor 3-Layer Dedup

### Dedup Protocol (applied by Controller in CURATOR_RESOLVE)

For EACH extracted lesson, command, and gotcha:

**Layer 1 — Exact text match:**
- Compare against existing entries in `lessons-learned.md` / `command-history.md`
- If exact text (or >90% character overlap) exists: tag `DUPLICATE: exact`
- Include reference: `existing_entry: "{matching text}"`

**Layer 2 — Semantic overlap:**
- Compare meaning against existing entries (>80% semantic overlap)
- If lesson describes same insight with different wording: tag `DUPLICATE: semantic`
- Include reference: `similar_to: "{closest matching text}"`

**Layer 3 — Qdrant cross-session:**
- If Qdrant is available, search for `type=lesson` with similarity >0.85
- Match from SAME project: tag `DUPLICATE: qdrant-same-project`
- Match from DIFFERENT project: tag `CROSS_PROJECT: {source_project}`
  (NOT a duplicate — include with cross-project tag)

### Output Tagging

Each item in the LE report MUST include a `dedup_status` field:
- `NEW` — no duplicates found, include in output
- `DUPLICATE: {layer}` — duplicate found, Controller will skip
- `CROSS_PROJECT: {source}` — similar lesson from another project, Controller keeps it

---

## Analytics Integration

### Report Type 4: Improvement Pipeline

**EPIC-level section** (appended to EPIC Report):

Query: `stage_log` entries with `state=CURATOR_RESOLVE` for `{epic_id}` + `backlog.md` entries with `epic_ref={epic_id}`

Output:
- Curator Activity: proposals generated, auto-approved, auto-rejected, PM overrides
- Lessons Extracted: new lessons, new gotchas, duplicates skipped, cross-project matches
- Fix Effectiveness: fixes implemented, files modified, fix agent models used

**Project-level section** (appended to Project Trends):

Query: all `backlog.md` entries + Qdrant `curator_decision` entries for `{project_name}`

Output:
- Backlog Health: total/active/implemented/rejected/deferred counts, implementation rate
- Recurring Issues: top hotspot areas, proposals persisting 3+ EPICs
- Learning Progress: auto-rules count, Qdrant decisions, auto-resolve accuracy (PM override rate)
- Lessons Trends: per-EPIC lesson/gotcha/duplicate counts

### Qdrant Query Pattern

```json
{
  "collection_name": "aid-memory",
  "query": "curator auto-evaluate decisions for {project_name}",
  "filter": {
    "must": [
      {"key": "type", "match": {"value": "curator_decision"}},
      {"key": "project_name", "match": {"value": "{project_name}"}}
    ]
  },
  "limit": 100
}
```

---

## Backlog ID Migration

### Migration Plan

Replace all `PROP-{YYYYMMDD}-{NNN}` IDs with `IMP-{NNN}` in `backlog.md`. Add alias table for legacy reference.

### ID Alias Table

| Legacy ID | New ID |
|-----------|--------|
| PROP-20260219-001 | IMP-009 |
| PROP-20260219-002 | IMP-010 |
| PROP-20260219-003 | IMP-011 |
| PROP-20260219-004 | IMP-012 |
| PROP-20260219-005 | IMP-013 |
| PROP-20260218-008 | IMP-014 |
| PROP-20260218-009 | IMP-015 |
| PROP-20260218-012 | IMP-016 |

IMP-001 through IMP-008 already exist (from E-20260221-c5de). Implemented entries (PROP-20260218-001 through PROP-20260218-013) get IMP-017 through IMP-029.

### Rules

- `IMP-{NNN}` format, zero-padded 3 digits, auto-incrementing, never reused
- Legacy `PROP-*` IDs appear ONLY in the aliases table
- All table rows, deferred entries, and implemented entries use `IMP-{NNN}`

---

## Agent Specification Updates

### Curator Agent (`agents/curator.md`)

Updates:
- **Dispatch context:** Change from `session-management.md at session-end` / `aid-run-epic.md POST_PROCESSING` → `epic-orchestration.md CURATOR_RESOLVE state (after GATES pass, before PM_APPROVAL)`
- **Identity:** Update timing from "after every session ends" → "after all steps complete and gates pass, during CURATOR_RESOLVE"
- **New note:** "Your proposals are auto-evaluated by the Orchestrator using `curator_auto_rules` from `decision-policies.yaml`. Approved proposals may be fixed immediately within the same EPIC."
- **Orchestrator Integration section:** Full rewrite with auto-evaluate flow, fix dispatch, PM override, Qdrant learning (see PM_APPROVAL Extension section above)

### Lessons-Extractor Agent (`agents/lessons-extractor.md`)

Updates:
- **Description:** Change to "Dispatched during CURATOR_RESOLVE state in parallel with Curator agent. Outputs are deduplicated by the Controller before writing to workspace files."
- **New section 3b:** "Deduplication Check" with 3-layer dedup instructions and output tagging (see Lessons-Extractor 3-Layer Dedup section above)
- **Important section:** Update dispatch context to "Dispatched during CURATOR_RESOLVE state (after GATES, before PM_APPROVAL). Runs in parallel with Curator agent."

### Improvement-Proposals Skill (`skills/improvement-proposals.md`)

Updates:
- **Section 6 (Orchestrator Integration):** Full rewrite → "Orchestrator Integration (CURATOR_RESOLVE State)" with 3-tier auto-evaluate algorithm documentation (Tier 1: YAML rules, Tier 2: Qdrant similarity, Tier 3: default action), decision actions table, PM override docs, Qdrant `curator_decision` storage format
- **Section 7 (Integration Points):** Update table to reflect CURATOR_RESOLVE as trigger source, add `decision-policies.yaml` and Qdrant as integration points

---

## Command Updates

### `aid-run-epic.md`

- Add CURATOR_RESOLVE handling in state machine loop (between GATES and PM_APPROVAL)
- Remove Curator + Lessons-Extractor dispatch from DONE/POST_PROCESSING references
- Keep Auditor dispatch in DONE

### `aid-help.md`

- Add CURATOR_RESOLVE to state machine description (between GATES and PM_APPROVAL)
- Update Curator agent description to reference CURATOR_RESOLVE state
- Add PM override and rule teaching to PM interaction points documentation

---

## High-Level Steps

| # | Step | Description | Estimated Effort |
|---|------|-------------|-----------------|
| 1 | architect | Design CURATOR_RESOLVE state: ADR with sub-steps, auto-evaluate algorithm, stage_log entries, PM_APPROVAL extension, DONE simplification | M |
| 2 | backend | Add CURATOR_RESOLVE to epic-orchestration.md: state table row, flow diagram, full state section (sub-steps 1-7 with auto-evaluate, fix dispatch, LE processing) | L |
| 3 | backend | Extend PM_APPROVAL in epic-orchestration.md: Curator summary block, PM override handling, PM rule teaching, Qdrant learning | M |
| 4 | backend | Simplify DONE in epic-orchestration.md: remove items 3/4/5/9, add migration note, renumber remaining items | M |
| 5 | backend | Add `curator_auto_rules` to decision-policies.yaml + update curator.md + lessons-extractor.md + improvement-proposals.md | M |
| 6 | backend | Update aid-run-epic.md: add CURATOR_RESOLVE handling, remove Curator/LE from DONE references | M |
| 7 | backend | Add Improvement Pipeline to analytics.md + migrate backlog.md IDs (PROP → IMP) | S |
| 8 | docs | Update aid-help.md: state machine, Curator agent description, PM interaction points | M |
| 9 | qa | Cross-reference verification: grep all modified files for stale references, validate state flow completeness | S |

### Dependencies & Parallelism

```
Step 1 (architect) ──→ Steps 2, 3 (epic-orchestration core — SERIALIZE on hot file)
Steps 2, 3 ──→ Step 4 (DONE simplification needs 2+3 complete)
Step 1 ──→ Step 5 (agents + policies — parallel group: group-agents)
Steps 2, 3, 4 ──→ Step 6 (aid-run-epic — parallel group: group-commands)
Step 1 ──→ Step 7 (analytics + backlog — parallel group: group-commands)
Steps 2, 3, 4, 5 ──→ Step 8 (aid-help — needs all core changes done)
All ──→ Step 9 (qa verification)
```

Steps 5+6+7 can partially parallelize (separate file ownership). Steps 2-4 must serialize (epic-orchestration.md is hot file).

## Constraints

- All changes are markdown/YAML instruction edits — no code, no tests, no build
- Must not break existing EPIC execution — state machine must be backwards-compatible
- Qdrant learning is optional (graceful degradation when Qdrant unavailable)
- PM override at PM_APPROVAL must be non-blocking (PM can skip with plain APPROVE)
- `backlog.md` history must be preserved (never delete entries, only migrate IDs)
- Budget: $10 max LLM cost (documentation edits, medium complexity)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Stale cross-references after state renumbering | medium | medium | Step 9: comprehensive grep verification |
| Auto-evaluate default "approve" too aggressive | low | medium | Configurable via `default_action` in YAML; PM can override |
| Qdrant learning produces wrong decisions | low | low | `min_decisions: 3` threshold; PM always has override |
| CURATOR_RESOLVE adds latency to EPIC completion | medium | low | Curator + LE run in parallel; fixes are opt-in |

## Success Criteria

- CURATOR_RESOLVE state exists in epic-orchestration.md state table and flow diagram
- Auto-evaluate algorithm documented with 3-tier decision flow (YAML → Qdrant → default)
- PM_APPROVAL presents Curator summary with implemented/rejected/deferred counts
- PM can override rejections and teach rules at PM_APPROVAL
- Lessons-Extractor spec includes 3-layer dedup with DUPLICATE tagging
- DONE state no longer dispatches Curator or Lessons-Extractor
- `decision-policies.yaml` contains `curator_auto_rules` section
- Analytics skill has "Improvement Pipeline" report type
- `backlog.md` uses `IMP-{NNN}` IDs with legacy alias table
- No stale references to "Curator in DONE" or "POST_PROCESSING Curator" in any file
- All cross-references verified by grep across modified files

## Next Steps

- [ ] Create EPIC from this plan → E-20260223-a8f1
- [ ] Execute via /aid-run-epic

---

**Last Updated:** 2026-02-23
