# Epic Orchestration — Controller State Machine

**Skill:** epic-orchestration
**Dependencies:** agent-core, quality-gates, run-management

---

## TL;DR

This skill defines the **Controller** that orchestrates an EPIC through its full lifecycle:
EPIC → Plan → Execute Steps → Gates → Curator Resolution → PM Approval → Done.

The Controller is a state machine. Every transition produces evidence. Failures trigger retry (max 3) then escalation to PM.

This is the top-level orchestrator module. The full specification is split across four focused modules for maintainability. This file provides the high-level overview, execution flow, and module reference map.

---

## Module Map

The orchestration logic is organized into four focused modules. Each module is self-contained and can be read independently.

| Module | File | Responsibility |
|--------|------|---------------|
| **FSM Core** | `skills/epic-state-machine.md` | 11-state FSM definition, state diagram, state definitions, detailed flow (IDLE through DONE), evidence store structure, ID generation, error handling summary |
| **Agent Dispatch** | `skills/dispatch-protocol.md` | Agent dispatch protocol (sequential, parallel, analysis, wiring), source plan integration, branch management, worktree isolation, orchestration logging |
| **Quality Gates** | `skills/gate-evaluation.md` | PHASE_CHECK (output validation, acceptance, discovered issues, diff generation, metrics), GATES, GATE_RETRY, ESCALATION, CURATOR_RESOLVE, PM_APPROVAL |
| **Auto-Mode Controller** | `skills/first-aid-controller.md` | FIRST AID mode (mode storage, reading, start/stop), auto-mode behavior at each state (PLAN_REVIEW, PHASE_CHECK, ESCALATION, CURATOR_RESOLVE, PM_APPROVAL, DONE), complete DONE state logic |

---

## Execution Flow

The Controller follows this high-level sequence when processing an EPIC:

```
1. RECEIVE EPIC
   → Load and validate EPIC file
   → Create run branch
   → Probe memory system
   → See: skills/epic-state-machine.md Section "1. IDLE → PLANNING"

2. LOAD PLAN (formerly: GENERATE PLAN)
   → plan.json and run.md are pre-created by `/aid-plan-epic` (via pipeline scripts)
   → PLANNING state validates and loads these artifacts, not generates them inline
   → See: skills/epic-state-machine.md Section "2. PLANNING"

3. REVIEW PLAN
   → Present rich plan summary to PM (or auto-approve in FIRST AID mode)
   → PM chooses GO / REVISE / ABORT
   → See: skills/epic-state-machine.md Section "3. PLAN_REVIEW"
   → Auto-mode: skills/first-aid-controller.md Section "PLAN_REVIEW — Auto-Mode Behavior"

4. EXECUTE STEPS (loop)
   → For each step (sequential or parallel):
     a. Dispatch agent with context, playbook, and permissions
        → See: skills/dispatch-protocol.md
     b. Validate outputs (acceptance, scope, quality)
        → See: skills/gate-evaluation.md Section "PHASE_CHECK"
     c. Advance to next step or escalate
        → See: skills/epic-state-machine.md Section "6. NEXT_PHASE"

5. RUN QUALITY GATES
   → Execute all gates from gates.yaml
   → Retry failures up to max_attempts
   → See: skills/gate-evaluation.md Sections "GATES" and "GATE_RETRY"

6. RESOLVE CURATOR PROPOSALS
   → Dispatch Curator + Lessons-Extractor
   → Auto-evaluate proposals (3-tier algorithm)
   → Dispatch fix agents for approved proposals
   → See: skills/gate-evaluation.md Section "CURATOR_RESOLVE"
   → Auto-mode: skills/first-aid-controller.md Section "CURATOR_RESOLVE — Auto-Mode Behavior"

7. PM APPROVAL
   → Present final summary with Curator results
   → PM approves, overrides, teaches rules, or rejects
   → See: skills/gate-evaluation.md Section "PM_APPROVAL"
   → Auto-mode: skills/first-aid-controller.md Section "PM_APPROVAL — Auto-Mode Behavior"

8. DONE
   → Token usage aggregation (dispatch_complete entries → usage_summary)
   → Write usage_summary to plan_progress.json + Qdrant
   → Release sub-phase (version bump if needed)
   → Branch merge, archive, auditor, metrics
   → EPIC queue check (auto-pickup next EPIC)
   → See: "DONE State — Token Usage Aggregation" section below
   → See: skills/first-aid-controller.md Section "DONE State"
```

---

## How to Read These Modules

**If you are the Controller executing an EPIC**, follow the execution flow above. Each step references the specific module and section to read.

**If you are implementing a specific state**, go directly to the relevant module:
- States IDLE, PLANNING, PLAN_REVIEW, EXECUTING (overview), NEXT_PHASE → `skills/epic-state-machine.md`
- Agent dispatch details (prompt assembly, parallel, wiring) → `skills/dispatch-protocol.md`
- PHASE_CHECK, GATES, GATE_RETRY, ESCALATION, CURATOR_RESOLVE, PM_APPROVAL → `skills/gate-evaluation.md`
- Auto-mode behavior at any state, DONE state → `skills/first-aid-controller.md`

**If you are reviewing the architecture**, start with the state diagram in `skills/epic-state-machine.md`.

---

## Configuration References

- **Planner:** `skills/planner.md` — dependency graph, parallel groups, analysis groups generation (implemented by `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh`)
- **Pipeline scripts:** `plugins/aid-orchestrator/scripts/` — `aid-auto-pipeline.sh` orchestrates Plan→EPIC→plan.json→run.md→queue; plan.json and run.md are expected to pre-exist when `/aid-run-epic` is invoked
- **Parallel dispatch:** `skills/parallel-dispatch.md` — branch strategy, dispatch protocol, conflict detection
- **Analysis merge:** `skills/analysis-merge.md` — merge strategies (union, consensus, weighted)
- **PM communication:** `skills/slack-mcp.md` — Slack MCP protocol, message types, fallback
- **Epic queue:** `skills/epic-queue.md` — queue management, auto-pickup protocol
- **FIRST AID mode start:** `commands/aid-first-aid.md` — PM confirms queue, permissions elevated, auto-mode activated
- **FIRST AID mode stop:** `commands/aid-stop.md` — immediate mode switch to manual or paused
- **Auto-escalation protocol:** `skills/auto-escalation.md` — 16 trigger conditions, severity classification, escalation budget
- **Auto-mode DONE state:** `skills/auto-done-state.md` — DONE state in auto-mode: release decisions, queue transitions, cross-EPIC summary
- **Auto-mode state file:** `.aid-o/04-engine/auto-mode-state.yaml` — current mode, active EPIC, escalation count, progress snapshot
- **Gates:** `.aid-o/03-config/policies/gates.yaml`
- **Decision policies:** `.aid-o/03-config/policies/decision-policies.yaml`
- **Slack config:** `.aid-o/03-config/policies/slack-config.yaml`
- **Plan schema:** `.aid-o/03-config/templates/plan.schema.json` (includes `analysis_groups`)
- **EPIC template:** `.aid-o/03-config/templates/epic.md`
- **Playbooks:** `.aid-o/03-config/playbooks/{role}.md`
- **Evidence:** `.aid-o/04-engine/evidence/`
- **Epic queue:** `.aid-o/04-engine/epic-queue.yaml`
- **Runs:** `.aid-o/04-engine/runs/`
- **Memory:** `.aid-o/04-engine/memory/active-work.md`
- **Dispatch strategy:** `.aid-o/03-config/policies/dispatch-strategy.yaml`
- **Memory config:** `.aid-o/03-config/policies/memory-config.yaml`
- **Orchestration log (Qdrant):** collection `aid-orchestration-log`
- **Orchestration log (fallback):** `.aid-o/logs/orchestration-events.jsonl`
- **Lessons learned (file):** `.aid-o/04-engine/lessons-learned.md`
- **Cost optimization:** `skills/cost-optimization.md` (model selection, file scoping, dispatch optimization)
- **Token estimation:** `skills/token-estimator.md` (character-based heuristic, accuracy notes, calibration)
- **Dispatch config:** `.aid-o/03-config/policies/dispatch-config.yaml` (model tiers, budget alerts, token estimation params)
- **Release policy:** `.aid-o/03-config/policies/release-policy.yaml`

---

## DONE State — Token Usage Aggregation

At the DONE state, after all steps have completed and before the release sub-phase,
the Controller aggregates token usage from the run's stage_log.jsonl into a
`usage_summary` object. This provides a single consolidated view of estimated token
consumption for the entire EPIC run.

**References:**
- `skills/token-estimator.md` — estimation protocol and accuracy notes
- `skills/dispatch-protocol.md` — dispatch_complete entries with `usage` field
- `defaults/policies/dispatch-config.yaml` — budget alert thresholds

### Aggregation Protocol

```
DONE_USAGE_AGGREGATION:
  1. Read stage_log.jsonl from .aid-o/04-engine/evidence/{epic_id}/{run_id}/
  2. Filter entries where action == "dispatch_complete" AND usage field is present
  3. For each matching entry:
     a. Accumulate estimated_total_tokens into running total
        (skip entries where estimated_total_tokens is null)
     b. Accumulate by model tier (usage.model → opus|sonnet|haiku)
     c. Accumulate by role (extract role from step_id pattern: step_{N}_{role})
     d. Accumulate by step (use step_id as key)
     e. Accumulate duration_seconds into total_duration
     f. Count entries where usage.budget_alert is not null
  4. Produce usage_summary object
  5. Write usage_summary to plan_progress.json
  6. Store usage_summary to Qdrant (if available)
```

### usage_summary Schema

The `usage_summary` is added to `plan_progress.json` as a top-level field. It is
ADDITIVE — existing fields in plan_progress.json are not modified.

```json
{
  "usage_summary": {
    "total_estimated_tokens": 123456,
    "by_model": {
      "opus": 50000,
      "sonnet": 60000,
      "haiku": 13456
    },
    "by_role": {
      "architect": 30000,
      "backend": 40000,
      "qa": 25000,
      "code-reviewer": 15000,
      "gate-fixer": 13456
    },
    "by_step": {
      "step_1_architect": 30000,
      "step_2_backend": 40000,
      "step_3_qa": 25000,
      "step_4_code-reviewer": 15000,
      "step_5_gate-fixer": 13456
    },
    "total_duration_seconds": 600,
    "budget_alerts_triggered": 0
  }
}
```

**Field descriptions:**

| Field | Type | Description |
|-------|------|-------------|
| `total_estimated_tokens` | int | Sum of all `estimated_total_tokens` from dispatch_complete entries (null entries excluded) |
| `by_model` | object | Tokens grouped by model tier key (opus, sonnet, haiku). Missing tiers omitted |
| `by_role` | object | Tokens grouped by agent role (extracted from step_id). Roles with 0 tokens omitted |
| `by_step` | object | Tokens grouped by step_id. Steps with null estimates omitted |
| `total_duration_seconds` | int | Sum of all `duration_seconds` from dispatch_complete entries |
| `budget_alerts_triggered` | int | Count of entries where `usage.budget_alert` was "warn" or "critical" |

### Writing to plan_progress.json

```
WRITE_USAGE_SUMMARY:
  1. Read plan_progress.json from .aid-o/04-engine/runs/{run_id}/
  2. Parse as JSON object
  3. Add "usage_summary" key with the aggregated object
  4. Write back to plan_progress.json
  5. If plan_progress.json does not exist or is unreadable:
     → Log warning to stage_log.jsonl
     → Skip writing (do not create new file)
     → Continue to next DONE sub-phase
```

### Qdrant Storage

If Qdrant MCP is available, store the usage summary as a metric for cross-EPIC
analytics and cost trend analysis.

```
STORE_USAGE_TO_QDRANT:
  1. Check Qdrant MCP availability (same probe as orchestration logging)
  2. IF available:
     a. Build metric payload:
        {
          "metric_kind": "token_profile",
          "epic_id": "{epic_id}",
          "run_id": "{run_id}",
          "timestamp": "{ISO 8601}",
          "total_estimated_tokens": usage_summary.total_estimated_tokens,
          "by_model": usage_summary.by_model,
          "by_role": usage_summary.by_role,
          "total_duration_seconds": usage_summary.total_duration_seconds,
          "budget_alerts_triggered": usage_summary.budget_alerts_triggered,
          "step_count": count of entries in by_step
        }
     b. Store via qdrant-store to collection "aid-orchestration-log"
     c. Metadata: { "metric_kind": "token_profile", "epic_id": "{epic_id}" }
  3. IF Qdrant unavailable:
     → Append metric to .aid-o/logs/orchestration-events.jsonl (same fallback as
       dispatch event logging — see skills/dispatch-protocol.md)
     → Continue — never block DONE state for Qdrant failures
```

### Non-Blocking Guarantee

The entire usage aggregation sequence is non-blocking. If any step fails (missing
stage_log.jsonl, parse error, Qdrant unavailable, plan_progress.json write failure),
the Controller:

1. Logs the error to stage_log.jsonl: `{"state": "DONE", "action": "usage_aggregation_error", "error": "{message}"}`
2. Continues to the next DONE sub-phase (release, branch merge, archive)
3. Usage aggregation failure NEVER prevents EPIC completion

---

## Release Sub-Phase — CLAUDE.md Count Verification

This check runs as part of the release checklist (BEFORE the version bump and CHANGELOG
steps) to ensure CLAUDE.md stays in sync with the actual number of command and skill files.

#### RELEASE CHECK — CLAUDE.md Counts

```
RELEASE_CHECK_COUNTS:
  1. actual_commands = count of .md files in plugins/aid-orchestrator/commands/
  2. actual_skills = count of .md files in plugins/aid-orchestrator/skills/
  3. Read CLAUDE.md lines containing "slash commands" and "skills"
  4. Extract the numbers from those lines
  5. IF actual_commands != extracted command count OR actual_skills != extracted skill count:
     → Update CLAUDE.md with correct counts before proceeding with release commit
     → Log: "CLAUDE.md counts updated: commands {old}→{new}, skills {old}→{new}"
  6. This check is part of the release checklist — release commit MUST NOT have stale counts
```

---

**Last Updated:** 2026-02-28
