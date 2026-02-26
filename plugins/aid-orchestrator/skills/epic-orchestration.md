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

2. GENERATE PLAN
   → Analyze EPIC → roles, dependency graph, parallel groups
   → Generate Plan JSON + run file
   → Validate against schema and quality checks
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
   → Release sub-phase (version bump if needed)
   → Branch merge, archive, auditor, metrics
   → EPIC queue check (auto-pickup next EPIC)
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

- **Planner:** `skills/planner.md` — dependency graph, parallel groups, analysis groups generation
- **Parallel dispatch:** `skills/parallel-dispatch.md` — branch strategy, dispatch protocol, conflict detection
- **Analysis merge:** `skills/analysis-merge.md` — merge strategies (union, consensus, weighted)
- **PM communication:** `skills/slack-mcp.md` — Slack MCP protocol, message types, fallback
- **Epic queue:** `skills/epic-queue.md` — queue management, auto-pickup protocol
- **FIRST AID mode start:** `commands/aid-first-aid.md` — PM confirms queue, permissions elevated, auto-mode activated
- **FIRST AID mode stop:** `commands/aid-stop.md` — immediate mode switch to manual or paused
- **Permission lifecycle:** `skills/permission-sandwich.md` — permission backup, elevation, restoration, crash recovery
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
- **Release policy:** `.aid-o/03-config/policies/release-policy.yaml`

---

**Last Updated:** 2026-02-26
