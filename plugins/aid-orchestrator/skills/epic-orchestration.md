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
| **PLAN_REVIEW** | Send plan to PM via Slack (or chat fallback), show steps + dependencies + parallel groups | PM says GO | `pm_plan_approval.json` |
| **EXECUTING** | Dispatch current step's agent (per role playbook); dispatch analysis_groups post-step (per `parallel-dispatch.md`) | Step produces expected outputs; analysis reports generated | `stage_log.jsonl` entry, `diffs/`, `analysis/` |
| **PHASE_CHECK** | Verify step outputs; merge analysis results; check parallel conflicts (per `parallel-dispatch.md`) | Auto-decision per `decision-policies.yaml`; critical analysis findings → ESCALATION | Check result in `stage_log.jsonl` |
| **NEXT_PHASE** | Advance to next step (or next parallel group) | Next step ready | Updated `plan_progress.json` |
| **GATES** | Run all gates from `gates.yaml` | All required gates pass | `gates_report.json` |
| **GATE_RETRY** | Generate fix instructions from gate failure, re-dispatch | Fix applied, re-run gate | Retry entry in `gates_report.json` |
| **ESCALATION** | Send failure to PM via Slack (or chat fallback) with options | PM decides (fix/skip/abort) | `pm_decision.json` |
| **PM_APPROVAL** | Send final results to PM via Slack (or chat fallback) | PM approves merge | `pm_decision.json` |
| **DONE** | Merge branch, archive evidence, run Curator + Auditor, send summaries via Slack, check Epic Queue for auto-pickup | — | `final_report.md`, `audit-report.md`, `curator_report.json`, `slack_log.jsonl` |

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

**Communication:** Per `skills/slack-mcp.md` Type B (Plan Approval).

**Actions:**
1. Format plan summary with step sequence, parallel groups, analysis groups, roles, budget
2. Send to PM via `send_pm_message("plan_approval", payload)`:
   - **Slack:** Posts Plan Approval message to configured channel, waits for reply
   - **Chat fallback:** Presents plan in conversation, waits for response
3. Wait for PM response via `wait_pm_response(message_ref, "plan_approval")`
4. If GO: transition to EXECUTING
5. If REVISE: return to PLANNING with PM feedback
6. If ABORT: transition to DONE (status: aborted)
7. If timeout: execute `timeout_actions.plan_approval` from `slack-config.yaml`

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_plan_approval.json`

### 4. EXECUTING

**Actions:**
1. Determine next step(s) to execute (respect dependency graph)
2. For sequential step:
   a. Create branch: `epic/{epic_id}/step_{N}_{role}` from `epic/{epic_id}/main`
   b. Load role playbook from `.aid-o/03-config/playbooks/{role}.md`
   c. Dispatch agent with context:
      - EPIC specification (relevant sections)
      - Plan step (objective, inputs, outputs, constraints)
      - Previous step outputs (if dependency)
      - Allowed/forbidden paths
   d. Agent executes and produces outputs
3. For parallel group (per `skills/parallel-dispatch.md`):
   a. Create branch per agent from `epic/{epic_id}/main` (same base commit)
   b. Add PARALLEL CONTEXT to each prompt (other agents, branch names, scope warning)
   c. Dispatch all agents in the group concurrently (use Task tool with parallel calls)
   d. Collect all outputs
4. Post-step analysis (analysis_groups — per `skills/parallel-dispatch.md` + `skills/analysis-merge.md`):
   a. After step passes PHASE_CHECK, check `plan.analysis_groups` for groups targeting this step
   b. If no analysis groups → skip
   c. If found: dispatch analysis agents (read-only, no branches) in parallel
   d. Collect outputs, apply merge strategy (`skills/analysis-merge.md`)
   e. Generate `analysis_report`, save to `evidence/analysis/`
   f. Critical findings → ESCALATION; high findings → PM warning; others → continue
5. Transition to PHASE_CHECK

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
3. If parallel group: check all agents in the group, then check for cross-agent conflicts:
   a. Collect all modified files across agents (`skills/parallel-dispatch.md` Section 3-4)
   b. If any file modified by 2+ agents → dry-run merge check
   c. Git merge conflict → ESCALATION with conflict details
   d. Clean merge → record and proceed
4. If analysis results present (from analysis_groups):
   a. Check for critical findings → ESCALATION
   b. Check for high findings → log warning to PM
   c. Merge analysis improvement_notes into step evidence (for Curator)

**Auto-Decision Logic:**
```
outputs_present AND within_scope → NEXT_PHASE
outputs_present AND scope_violation → re-dispatch (max 1 retry)
no_outputs OR error → ESCALATION
parallel_merge_conflict → ESCALATION
analysis_critical_findings → ESCALATION
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

**Communication:** Per `skills/slack-mcp.md` Type A (Escalation).

**Actions:**
1. Build escalation payload with trigger reason, failure details, options, recommendation
2. Send to PM via `send_pm_message("escalation", payload)`:
   - **Slack:** Posts Escalation message with options A/B/C, waits for reply
   - **Chat fallback:** Presents failure context in conversation, waits for response
3. Wait for PM response via `wait_pm_response(message_ref, "escalation")`
4. Execute PM's choice:
   - Fix (`response_type: "fix"`) → return to appropriate state with PM guidance
   - Skip (`response_type: "skip"`) → mark as skipped, continue
   - Abort (`response_type: "abort"`) → transition to DONE (status: aborted)
   - Discussion (`response_type: "discussion"`) → incorporate PM's text, re-present options
   - Timeout → execute `timeout_actions.escalation` from `slack-config.yaml`

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_decision.json`

### 10. PM_APPROVAL

**Communication:** Per `skills/slack-mcp.md` Type C (Merge Approval).

**Actions:**
1. Compile final summary payload (steps, gates, changes, evidence path)
2. Send to PM via `send_pm_message("merge_approval", payload)`:
   - **Slack:** Posts Merge Approval message, waits for reply
   - **Chat fallback:** Presents summary in conversation, waits for response
3. Wait for PM response via `wait_pm_response(message_ref, "merge_approval")`
4. If APPROVE (`response_type: "approve"`): transition to DONE
5. If REJECT (`response_type: "reject"`): transition to ESCALATION (with PM feedback)
6. If REVISE (`response_type: "revise"`): return to EXECUTING with PM's revision instructions
7. If timeout: execute `timeout_actions.merge_approval` from `slack-config.yaml`

### 11. DONE

**Actions:**
1. If approved:
   a. Merge all step branches to main (or create PR)
   b. Update EPIC file status to "Completed"
   c. Archive session file to `.aid-o/04-engine/sessions/archive/`
   d. Update `.aid-o/04-engine/memory/active-work.md`
2. Generate final report
3. **POST-PROCESSING:**
   a. Dispatch **Curator agent** (`agents/curator.md`) — collects `improvement_notes`
      from all step outputs, deduplicates vs backlog, proposes improvements.
      Protocol: `skills/improvement-proposals.md`
   b. Dispatch **Auditor agent** (`agents/auditor.md`) — runs 5 audit types
      (code, security, docs, frontend, database), scores project health,
      tracks trend vs previous audit. Report → `evidence/{epic_id}/audit-report.md`
   c. Curator proposals → Orchestrator evaluates:
      - APPROVED proposals → PM via Slack Type D (Improvement Proposal, expects reply)
      - REJECTED proposals → PM via Slack Type E (Rejection Info, no reply)
      - Per `skills/slack-mcp.md` — batch handling: each proposal = separate message
   d. Auditor summary → PM via Slack Type F (Audit Summary, no reply)
      - If critical findings match `escalation_triggers` → additional Type A (Escalation)
   e. Auditor findings → Orchestrator validates → Curator processes into backlog
4. Send Status Update (Type G): `:checkered_flag: EPIC completed — merged to main`
5. **EPIC QUEUE CHECK** (per `skills/epic-queue.md`):
   a. Read `.aid-o/04-engine/epic-queue.yaml`
   b. IF queue is not paused AND next EPIC exists (status: "queued"):
      - Mark current EPIC as "completed" in queue
      - Mark next EPIC as "running"
      - Send Status Update: `:arrows_counterclockwise: Auto-starting next EPIC: {next_epic_id}`
      - Transition: DONE → IDLE (with next EPIC) — start new orchestration loop
   c. IF queue is paused OR empty:
      - Mark current EPIC as "completed" in queue (if in queue)
      - Send Status Update: `:white_check_mark: Queue empty. Orchestrator idle.`
      - Remain in terminal DONE state

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
  plan.json                  # Generated plan (includes analysis_groups)
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
  parallel_groups/            # Parallel execution evidence
    group_{N}/
      dispatch_log.json       # Dispatch times, prompts
      merge_log.json          # Merge order, conflict checks
      branch_status.json      # Branch names, base commit
  analysis/                   # Multi-perspective analysis results
    analysis_{N}_{purpose}/
      raw_{agent_role}.yaml   # Raw output from each analysis agent
      analysis_report.yaml    # Merged report (per analysis-merge.md)
      dispatch_log.json       # Analysis dispatch times
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

> **Reference:** `skills/parallel-dispatch.md` for complete protocol.

```
1. Identify all steps in the parallel group
2. For each step: prepare dispatch (same as sequential) + PARALLEL CONTEXT
3. Create all branches from epic/{epic_id}/main (same base commit)
4. Use single message with multiple Task tool calls
5. Collect all outputs
6. Check for conflicts (git dry-run merge + scope violations)
7. If conflicts: → ESCALATION
8. If no conflicts: merge branches into epic/{epic_id}/main, save evidence
```

### Analysis Group Dispatch

> **Reference:** `skills/parallel-dispatch.md` Section 2 + `skills/analysis-merge.md`

```
Triggered: AFTER target step passes PHASE_CHECK (not during execution)
Key difference: Analysis agents are READ-ONLY — no branches, no code changes

1. Check plan.analysis_groups for groups targeting completed step
2. If found: prepare analysis prompts (step output, diff, mode, strategy)
3. Dispatch all analysis agents in parallel (Task tool)
4. Collect analysis_output YAML from each agent
5. Apply merge strategy (union|consensus|weighted) per analysis-merge.md
6. Generate consolidated analysis_report
7. Save to evidence/analysis/
8. Critical findings → ESCALATION
```

### Branch Management

> **Reference:** `skills/parallel-dispatch.md` Section 1 for complete branch strategy.

```
Base branch:
  epic/{epic_id}/main — created from HEAD of main at EPIC start

Per-step branches:
  epic/{epic_id}/step_{N}_{role}

Merge strategy:
  Sequential steps: branch from epic/{epic_id}/main → merge back after pass
  Parallel steps: all fork from epic/{epic_id}/main → merge one-by-one (by step #) after all pass
  Analysis: NO branches (read-only analysis, reports only)
  Final: PR from epic/{epic_id}/main → main
```

---

## Communication Protocol

States PLAN_REVIEW, ESCALATION, and PM_APPROVAL communicate with PM via `skills/slack-mcp.md`.
The DONE state sends Curator proposals (Type D), rejection info (Type E), and audit summaries (Type F).
Status updates (Type G) are sent at key orchestration points (non-blocking, fire-and-forget).

If Slack MCP is not configured (`.aid-o/03-config/policies/slack-config.yaml` missing or
`slack.enabled: false`), all communication falls back to chat-based presentation (pre-Session 6 behavior).

The DONE state checks `.aid-o/04-engine/epic-queue.yaml` (per `skills/epic-queue.md`) and
auto-starts the next queued EPIC if available.

## Configuration References

- **Planner:** `skills/planner.md` — dependency graph, parallel groups, analysis groups generation
- **Parallel dispatch:** `skills/parallel-dispatch.md` — branch strategy, dispatch protocol, conflict detection
- **Analysis merge:** `skills/analysis-merge.md` — merge strategies (union, consensus, weighted)
- **PM communication:** `skills/slack-mcp.md` — Slack MCP protocol, message types, fallback
- **Epic queue:** `skills/epic-queue.md` — queue management, auto-pickup protocol
- **Gates:** `.aid-o/03-config/policies/gates.yaml`
- **Decision policies:** `.aid-o/03-config/policies/decision-policies.yaml`
- **Slack config:** `.aid-o/03-config/policies/slack-config.yaml`
- **Plan schema:** `.aid-o/03-config/templates/plan.schema.json` (includes `analysis_groups`)
- **EPIC template:** `.aid-o/03-config/templates/epic.md`
- **Playbooks:** `.aid-o/03-config/playbooks/{role}.md`
- **Evidence:** `.aid-o/04-engine/evidence/`
- **Epic queue:** `.aid-o/04-engine/epic-queue.yaml`
- **Sessions:** `.aid-o/04-engine/sessions/`
- **Memory:** `.aid-o/04-engine/memory/active-work.md`

---

## Integration with Session Management

The Controller creates a session file for each EPIC run:
1. On PLANNING: create session file from EPIC (auto-generated phases from plan steps)
2. On each PHASE_CHECK: update session file (step status, commit hash)
3. On analysis complete: log analysis_report summary to session file
4. On GATES: update session file (gate results)
5. On DONE: complete session file, archive

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
| Git merge conflict in parallel | PHASE_CHECK | ESCALATION with conflict details |
| Analysis critical findings | PHASE_CHECK | ESCALATION (PM must acknowledge) |
| Analysis agent failure | EXECUTING | Skip agent, log warning, proceed |
| PM rejects final | PM_APPROVAL | ESCALATION with feedback |

---

**Version:** 0.1.0
**Last Updated:** 2026-02-16
