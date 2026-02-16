# Epic Orchestration — Controller State Machine

**Version:** 0.1.0
**Skill:** epic-orchestration
**Dependencies:** agent-core, quality-gates, session-management

---

## TL;DR

This skill defines the **Controller** that orchestrates an EPIC through its full lifecycle:
EPIC → Plan → Execute Steps → Gates → PM Approval → Done.

The Controller is a state machine. Every transition produces evidence. Failures trigger retry (max 3) then escalation to PM.

---

## State Machine

```
┌──────┐
│ IDLE │
└──┬───┘
   │ receive EPIC
   ▼
┌──────────┐
│ PLANNING │──────────────────────────────────┐
└──┬───────┘                                  │
   │ Plan JSON generated                      │ planning fails
   ▼                                          ▼
┌─────────────┐                          ┌────────────┐
│ PLAN_REVIEW │                          │ ESCALATION │
└──┬──────────┘                          └────────────┘
   │ PM approves plan                         ▲
   ▼                                          │
┌───────────┐                                 │
│ EXECUTING │◄────────────────┐               │
└──┬────────┘                 │               │
   │ step completes           │               │
   ▼                          │               │
┌─────────────┐               │               │
│ PHASE_CHECK │               │               │
└──┬──────┬───┘               │               │
   │      │                   │               │
   │      │ more steps        │               │
   │      └───► NEXT_PHASE ───┘               │
   │                                          │
   │ all steps done                           │
   ▼                                          │
┌───────┐     fail + retries < max            │
│ GATES │────────► GATE_RETRY ────────────────┤
└──┬────┘     fail + retries >= max           │
   │                                          │
   │ all pass                                 │
   ▼                                          │
┌──────────────┐                              │
│ PM_APPROVAL  │                              │
└──┬───────┬───┘                              │
   │       │                                  │
   │       │ rejected                         │
   │       └──────────────────────────────────┘
   │ approved
   ▼
┌──────┐
│ DONE │
└──────┘
```

### State Definitions

| State | Entry Action | Exit Condition | Evidence |
|-------|-------------|----------------|----------|
| **IDLE** | Load EPIC file, validate structure | EPIC parsed successfully | `epic_input.md` saved |
| **PLANNING** | Read EPIC → generate Plan JSON per `plan.schema.json` | Valid Plan JSON produced | `plan.json` saved |
| **PLAN_REVIEW** | Present plan to PM, show steps + dependencies + parallel groups | PM says GO | `pm_plan_approval.json` |
| **EXECUTING** | Dispatch current step's agent (per role playbook) | Step produces expected outputs | `stage_log.jsonl` entry, `diffs/` |
| **PHASE_CHECK** | Verify step outputs against acceptance criteria | Auto-decision per `decision-policies.yaml` | Check result in `stage_log.jsonl` |
| **NEXT_PHASE** | Advance to next step (or next parallel group) | Next step ready | Updated `plan_progress.json` |
| **GATES** | Run all gates from `gates.yaml` | All required gates pass | `gates_report.json` |
| **GATE_RETRY** | Generate fix instructions from gate failure, re-dispatch | Fix applied, re-run gate | Retry entry in `gates_report.json` |
| **ESCALATION** | Present failure to PM with options | PM decides (fix/skip/abort) | `pm_decision.json` |
| **PM_APPROVAL** | Present final results + evidence to PM | PM approves merge | `pm_decision.json` |
| **DONE** | Merge branch, archive evidence, update session | — | `final_report.md` |

---

## Detailed Flow

### 1. IDLE → PLANNING

**Trigger:** `/run-epic <epic-file>` command or Controller receives EPIC path.

**Actions:**
1. Read EPIC file, validate it has required sections (Goal, Scope, Constraints, DoD, Acceptance Criteria)
2. Read `.aid-o/03-config/policies/decision-policies.yaml` for architecture principles
3. Read `.aid-o/03-config/policies/gates.yaml` for gate definitions
4. Read relevant playbooks from `.aid-o/03-config/playbooks/`
5. Transition to PLANNING

**Evidence:** Copy EPIC to `.aid-o/04-engine/evidence/{epic_id}/{run_id}/epic_input.md`

### 2. PLANNING

**Actions:**
1. Analyze EPIC to identify required roles and their sequence
2. Build dependency graph (which steps depend on which)
3. Identify parallel groups (steps that can run concurrently)
4. Generate Plan JSON conforming to `.aid-o/03-config/templates/plan.schema.json`
5. Validate Plan JSON against schema

**Plan Generation Rules:**
- Architect always runs first (contracts before implementation)
- Domain runs after Architect (needs contracts)
- Backend + Frontend can run in parallel (both depend on contracts)
- QA + Security + Observability can run in parallel (all depend on implementation)
- Docs runs after implementation steps
- Release runs last (needs all gates to pass)

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json`

### 3. PLAN_REVIEW

**Actions:**
1. Present Plan to PM in readable format:
   ```
   EPIC: {title}
   Steps: {count}
   Parallel groups: {count}
   Estimated roles: {list}
   Dependencies: {summary}
   Budget: ${max_cost}

   Step sequence:
   1. [architect] {objective}
   2. [domain] {objective} (depends on: step 1)
   3. [backend] {objective} (depends on: step 2) ← parallel group 1
   4. [frontend] {objective} (depends on: step 1) ← parallel group 1
   ...

   Proceed? (GO / REVISE / ABORT)
   ```
2. Wait for PM response
3. If REVISE: return to PLANNING with PM feedback
4. If ABORT: transition to DONE (status: aborted)
5. If GO: transition to EXECUTING

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_plan_approval.json`

### 4. EXECUTING

**Actions:**
1. Determine next step(s) to execute (respect dependency graph)
2. For sequential step:
   a. Create branch: `epic/{epic_id}/step_{N}_{role}`
   b. Load role playbook from `.aid-o/03-config/playbooks/{role}.md`
   c. Dispatch agent with context:
      - EPIC specification (relevant sections)
      - Plan step (objective, inputs, outputs, constraints)
      - Previous step outputs (if dependency)
      - Allowed/forbidden paths
   d. Agent executes and produces outputs
3. For parallel group:
   a. Create branch per agent: `epic/{epic_id}/step_{N}_{role}`
   b. Dispatch all agents in the group concurrently (use Task tool with parallel calls)
   c. Collect all outputs
4. Transition to PHASE_CHECK

**Context Passing Between Steps:**
```
Step N outputs → saved to .aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}/
Step N+1 inputs → read from .aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}/
```

Key context to pass:
- Architect → all: API contracts, ADR decisions
- Domain → Backend: entity definitions, invariants
- Backend → QA: endpoint implementations, test fixtures
- Backend → Security: code to review
- All → Docs: what changed and why

**Evidence:** For each step:
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}/output.md`
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}/diff.patch`
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/prompts/step_{N}_prompt.md`
- Entry in `.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl`

### 5. PHASE_CHECK

**Actions:**
1. Verify step produced expected outputs (from plan step definition)
2. Check outputs against `.aid-o/03-config/policies/decision-policies.yaml`:
   - Agent modified only allowed paths? → auto-accept
   - Agent modified forbidden paths? → auto-reject, re-dispatch with warning
   - Outputs match expected artifacts? → auto-accept
   - No output or error? → escalate
3. If parallel group: check all agents in the group

**Auto-Decision Logic:**
```
outputs_present AND within_scope → NEXT_PHASE
outputs_present AND scope_violation → re-dispatch (max 1 retry)
no_outputs OR error → ESCALATION
```

### 6. NEXT_PHASE

**Actions:**
1. Update `plan_progress.json` (mark step complete)
2. Check dependency graph for next available step(s)
3. If more steps: transition to EXECUTING
4. If all steps done: transition to GATES

### 7. GATES

**Actions:**
1. Read `.aid-o/03-config/policies/gates.yaml`
2. For each required gate:
   a. Run gate command (or check rule)
   b. Record pass/fail + output
3. If ALL required gates pass: transition to PM_APPROVAL
4. If ANY required gate fails: transition to GATE_RETRY

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/gates_report.json`:
```json
{
  "epic_id": "{epic_id}",
  "run_id": "{run_id}",
  "timestamp": "{ISO 8601}",
  "gates": [
    {
      "name": "tests_pass",
      "status": "pass",
      "output": "42 passed in 3.2s",
      "attempt": 1
    },
    {
      "name": "security_scan_pass",
      "status": "fail",
      "output": "1 HIGH finding: hardcoded secret in config.py:42",
      "attempt": 1
    }
  ],
  "overall": "fail",
  "next_action": "gate_retry"
}
```

### 8. GATE_RETRY

**Actions:**
1. Read failed gate details from `gates_report.json`
2. Check retry count against `.aid-o/03-config/policies/gates.yaml` retry.max_attempts
3. If retries remaining:
   a. Analyze failure output
   b. Generate fix instructions (what to change and why)
   c. Dispatch appropriate agent to fix (usually backend or security)
   d. Re-run failed gate
   e. Update `gates_report.json` with retry result
4. If max retries exceeded: transition to ESCALATION

**Retry Logic:**
```
attempt = 1
while gate_fails AND attempt <= max_attempts:
    fix_instructions = analyze_failure(gate_output)
    dispatch_fix_agent(fix_instructions)
    gate_result = run_gate(gate)
    attempt += 1
if gate_fails:
    → ESCALATION
```

### 9. ESCALATION

**Trigger:** Gate failure after max retries, agent error, scope violation, budget exceeded, or ambiguous criteria.

**Actions:**
1. Present failure context to PM:
   ```
   ESCALATION — {trigger_reason}
   ================================
   EPIC: {epic_id}
   State: {current_state}
   Details: {failure_details}

   Options:
   A) {option from escalation_triggers in decision-policies.yaml}
   B) {option}
   C) Abort EPIC

   Recommendation: {auto recommendation if possible}
   ```
2. Wait for PM decision
3. Execute PM's choice:
   - Fix → return to appropriate state
   - Skip → mark as skipped, continue
   - Abort → transition to DONE (status: aborted)

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_decision.json`

### 10. PM_APPROVAL

**Actions:**
1. Present final summary:
   ```
   EPIC COMPLETE — Ready for Merge
   ================================
   EPIC: {title}
   Steps completed: {N}/{total}
   Gates: ALL PASS
   Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/

   Changes:
   - {file count} files changed
   - {commit count} commits
   - Branches: {list}

   Merge to main? (APPROVE / REJECT / REVISE)
   ```
2. If APPROVE: transition to DONE
3. If REJECT: transition to ESCALATION (PM provides feedback)
4. If REVISE: return to EXECUTING with PM's revision instructions

### 11. DONE

**Actions:**
1. If approved:
   a. Merge all step branches to main (or create PR)
   b. Update EPIC file status to "Completed"
   c. Archive session file to `.aid-o/04-engine/sessions/archive/`
   d. Update `.aid-o/04-engine/memory/active-work.md`
2. Generate final report

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/final_report.md`:
```markdown
# EPIC Run Report: {epic_id}

## Summary
- Status: {completed/aborted}
- Duration: {start} → {end}
- Steps: {completed}/{total}
- Gates: {pass_count}/{total_count}
- Retries: {count}
- Escalations: {count}
- LLM Cost: ${estimated}

## Steps
| # | Role | Status | Duration | Branch |
|---|------|--------|----------|--------|
| 1 | architect | done | ... | epic/{epic_id}/step_1_architect |

## Gate Results
| Gate | Status | Attempts |
|------|--------|----------|
| tests_pass | pass | 1 |

## Evidence
All artifacts stored in: .aid-o/04-engine/evidence/{epic_id}/{run_id}/
```

---

## Evidence Store Structure

```
.aid-o/04-engine/evidence/{epic_id}/{run_id}/
  epic_input.md              # Original EPIC
  plan.json                  # Generated plan
  plan_progress.json         # Step completion tracking
  pm_plan_approval.json      # PM's plan approval
  pm_decision.json           # PM decisions (escalations, final approval)
  stage_log.jsonl            # Structured log of all state transitions
  gates_report.json          # Gate results with retry history
  final_report.md            # Summary report
  prompts/                   # All prompts sent to agents
    step_1_architect.md
    step_2_domain.md
    ...
  steps/                     # Step outputs
    step_1_architect/
      output.md
      diff.patch
    step_2_domain/
      output.md
      diff.patch
    ...
  gates/                     # Gate command outputs
    tests_pass.txt
    lint_pass.txt
    security_scan_pass.txt
    ...
```

**Rules:**
- No secrets in evidence (redact before saving)
- PII minimized
- Every state transition appends to `stage_log.jsonl`

### stage_log.jsonl Format

Each line is a JSON object:
```json
{"timestamp": "2026-02-15T14:30:00Z", "state": "EXECUTING", "step": "step_1_architect", "action": "dispatch_agent", "details": "Dispatching architect with EPIC context"}
{"timestamp": "2026-02-15T14:32:00Z", "state": "PHASE_CHECK", "step": "step_1_architect", "action": "check_outputs", "details": "Outputs present: openapi_spec.yaml, ADR-001.md", "result": "pass"}
```

---

## Agent Dispatch Protocol

### Sequential Step Dispatch

```
1. Load playbook: .aid-o/03-config/playbooks/{role}.md
2. Build prompt:
   - System: playbook content
   - Context: EPIC goal + scope + constraints
   - Task: plan step objective + inputs + outputs
   - Previous outputs: evidence from dependency steps
   - Constraints: allowed_paths, forbidden_paths
3. Dispatch via Task tool (subagent_type matching role or general-purpose)
4. Collect output
5. Save to .aid-o/04-engine/evidence/
```

### Parallel Group Dispatch

```
1. Identify all steps in the parallel group
2. For each step: prepare dispatch (same as sequential)
3. Use single message with multiple Task tool calls
4. Collect all outputs
5. Check for conflicts between parallel outputs
6. If conflicts: → ESCALATION
7. If no conflicts: save all to .aid-o/04-engine/evidence/
```

### Branch Management

```
Per-step branches:
  epic/{epic_id}/step_{N}_{role}

Merge strategy:
  Sequential steps: merge into previous step's branch
  Parallel steps: merge all into epic/{epic_id}/main
  Final: PR from epic/{epic_id}/main → main
```

---

## Configuration References

- **Gates:** `.aid-o/03-config/policies/gates.yaml`
- **Decision policies:** `.aid-o/03-config/policies/decision-policies.yaml`
- **Plan schema:** `.aid-o/03-config/templates/plan.schema.json`
- **EPIC template:** `.aid-o/03-config/templates/epic.md`
- **Playbooks:** `.aid-o/03-config/playbooks/{role}.md`
- **Evidence:** `.aid-o/04-engine/evidence/`
- **Sessions:** `.aid-o/04-engine/sessions/`
- **Memory:** `.aid-o/04-engine/memory/active-work.md`

---

## Integration with Session Management

The Controller creates a session file for each EPIC run:
1. On PLANNING: create session file from EPIC (auto-generated phases from plan steps)
2. On each PHASE_CHECK: update session file (step status, commit hash)
3. On GATES: update session file (gate results)
4. On DONE: complete session file, archive

Session file frontmatter:
```yaml
id: S-{YYYYMMDD}-{hash}
type: new-feature
status: active
epic_id: {epic_id}
orchestrated: true  # marks this as Controller-managed
```

---

## Error Handling Summary

| Error | State | Action |
|-------|-------|--------|
| EPIC file invalid | IDLE | Report error, stay IDLE |
| Plan generation fails | PLANNING | Retry once, then ESCALATION |
| PM rejects plan | PLAN_REVIEW | Return to PLANNING with feedback |
| Agent produces no output | EXECUTING | ESCALATION |
| Agent modifies forbidden paths | PHASE_CHECK | Auto-reject, re-dispatch once |
| Gate fails, retries left | GATES | GATE_RETRY |
| Gate fails, no retries | GATE_RETRY | ESCALATION |
| Budget exceeded | Any | ESCALATION |
| Conflicting parallel outputs | PHASE_CHECK | ESCALATION |
| PM rejects final | PM_APPROVAL | ESCALATION with feedback |

---

**Version:** 0.1.0
**Last Updated:** 2026-02-16
