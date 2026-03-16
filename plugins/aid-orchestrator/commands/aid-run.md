---
name: aid-run
description: Execute task pipeline — 6-state FSM with optional autonomous mode
user_invocable: true
---

Run the 6-state FSM controller to orchestrate a task through its full lifecycle. Replaces the old `/aid-run-epic` and `/aid-first-aid` commands.

## Usage

```
/aid-run                        # manual mode — start or auto-detect active task
/aid-run <task-id>              # manual mode — start specific task
/aid-run --auto                 # autonomous mode — auto-approve S-effort fixes
/aid-run --auto --task <id>     # autonomous mode for specific task
/aid-run --resume               # resume interrupted run from state.yaml
```

## Flags

| Flag | Behavior |
|------|----------|
| (none) | Manual mode — asks PM approval at each escalation |
| `--auto` | Autonomous mode (replaces `/aid-first-aid`) |
| `--resume` | Resume from last known state in `state.yaml` |
| `--task <id>` | Specify task ID (otherwise auto-detect) |

### Autonomous Mode (`--auto`)

Escalation rules for `--auto`:
- **S-effort fixes** → auto-approve, apply fix, continue
- **M-effort decisions** → use default decision from `config/permissions.yaml`
- **L-effort and security issues** → ALWAYS escalate to PM (never auto-approve)
- Gate retries → auto-retry up to configured max (default: 2)
- Version bump on intermediate phase → auto-defer (bump only on final phase)

Requires `autonomous_mode: true` in `.aid-o/config/permissions.yaml`.
If not set, `--auto` prints a warning and falls back to manual mode.

## MECHANICAL ENFORCEMENT PROTOCOL

The FSM is mechanically enforced via precondition-verified transitions.
Scripts WILL REFUSE to proceed if preconditions are not met.

### Rules (non-negotiable):

1. **Before any action:** `bash {plugin_path}/scripts/aid-fsm.sh verify-state <state_file>` — confirms current state + allowed transitions
2. **Every state transition:** `bash {plugin_path}/scripts/aid-fsm.sh transition <from> <to> <state_file>` — verifies preconditions, exits non-zero if unmet
3. **If transition fails:** STOP. Read the error message. Fix the precondition. Do NOT bypass.
4. **PRE-FLIGHT is mandatory:** `READY→EXECUTE` requires `plan.json` to exist in run dir
5. **Gates are mandatory:** `GATES→DONE` requires `gates_report.json` with `overall: pass`
6. **Steps must complete:** `EXECUTE→GATES` requires `current_step >= total_steps`
7. **Do NOT edit state.yaml directly** — all mutations go through `aid-fsm.sh` commands (`transition`, `increment-step`, `set-field`)
8. **`--force` is PM-only** — never use without explicit PM instruction; logged to audit trail
9. **Multi-layer defense** — `aid-release.sh` and git pre-commit hook independently verify `done_phase` before allowing release/commit on FSM branches
10. **Step verification evidence** — `increment-step` REFUSES to advance without `step-{N}-verify.md` containing `## Result: PASS` in evidence dir

### Agent dispatch rules (non-negotiable but instruction-enforced):
11. **Verbatim plan content** — NEVER send agents "read the plan". Extract relevant section and paste VERBATIM into agent prompt. Include code snippets, AC, mockups.
12. **Visual verification** — after any UI step: Playwright screenshot + compare with mockup. "Compiles" ≠ "looks right".

### Precondition failures are HARD STOPS:
- Do NOT attempt alternative transitions to work around a failure
- Do NOT modify `state.yaml` directly to bypass checks
- Present the error to PM and wait for guidance
- The error message tells you exactly what's missing

### Gate execution:
- Use `--state-file` and `--report-file` flags with `aid-run-gates.sh`:
  ```
  bash {plugin_path}/scripts/aid-run-gates.sh run-all <execution.yaml> <epic_id> <run_id> <timeline_file> \
    --state-file <state_file> --report-file <evidence_dir>/gates/gates_report.json
  ```
- `--state-file` ensures gates only run when FSM is in GATES state
- `--report-file` persists `gates_report.json` (required by `GATES→DONE` precondition)

## PRE-FLIGHT (before FSM starts)

**Plugin path verification:**
1. Read `plugin_path` from `.aid-o/config/plugin.yaml`
2. Verify: `test -f {plugin_path}/scripts/aid-fsm.sh`
3. If stale or missing → re-discover: `glob ~/.claude/plugins/**/aid-orchestrator/scripts/aid-fsm.sh` → update `plugin.yaml`
4. If still not found → abort with: "Plugin scripts not found. Run `/aid-init` to refresh."

**Bash pipeline** (using resolved `plugin_path`):
1. `{plugin_path}/scripts/aid-plan-to-epic.sh` — convert plan to task file (if running from plan)
2. `{plugin_path}/scripts/aid-epic-to-json.sh` — parse DAG → plan.json
3. `{plugin_path}/scripts/aid-json-to-run.sh` — plan.json → execution.yaml + state.yaml init

These are **bash scripts**. No LLM involvement. Exit non-zero → abort with error message.
PM must fix the underlying issue (missing steps, circular deps, invalid task format).

```
PRE-FLIGHT Pipeline
====================================
  [1] aid-plan-to-epic.sh   → task file     ✓
  [2] aid-epic-to-json.sh   → plan.json     ✓
  [3] aid-json-to-run.sh    → state.yaml    ✓

FSM initialized: READY
```

## 6-State FSM

```
             ┌──────────┐
             │  READY   │
             └────┬─────┘
                  │ approve
             ┌────▼─────┐
        ┌───►│ EXECUTE  │◄───────────────┐
        │    └────┬─────┘                │
        │         │ all steps done       │ fix applied
        │    ┌────▼─────┐          ┌─────┴──────┐
        │    │  GATES   │─────────►│ ESCALATION │
        │    └────┬─────┘ retries  └─────┬──────┘
        │         │ all pass       skip  │
        │    ┌────▼─────┐    gate  │     │
        │    │   DONE   │◄─────────┘     │
        │    └────┬─────┘                │
        │         │ error                │
        │    ┌────▼─────┐                │
        │    │  ERROR   │                │
        │    └──────────┘                │
        │                                │
        └────────────────────────────────┘
              gate retry (max 2)
```

### State: READY

**Entry:** PRE-FLIGHT completed, `state.yaml` initialized.

**Actions:**
1. Load `execution.yaml` (gate definitions, step config)
2. Load `config/permissions.yaml` (mode, auto-approve rules)
3. Display task summary to PM:
   ```
   Task: {id} — {title}
   Steps: {N} ({parallel_groups} parallel groups)
   Mode: {manual|auto}

   Quality Gates (will run after all steps):
     • test_cmd: {actual command from execution.yaml}
     • lint_cmd: {actual command}
     • build_cmd: {actual command}
     {list all gates with actual commands}

   Options:
     GO    — start execution (pause anytime with /aid-stop)
     REVISE — modify plan (stay in READY)
     ABORT  — cancel, no changes committed
   ```
4. In manual mode → wait for PM decision (GO/REVISE/ABORT)
5. In auto mode → validate plan JSON schema, auto-GO

**Transition:** → EXECUTE (GO) | stay READY (REVISE) | ERROR (ABORT)

### State: EXECUTE

**Actions:**
1. Read `state.yaml` → find `current_step`
2. Check dependency graph → dispatch steps with all deps satisfied
3. For sequential step:
   - Create branch: `task/{task_id}/step_{N}_{role}`
   - Build agent prompt (per `pipeline.md §4`)
   - Dispatch agent via Task tool
   - Collect output → save to `work/evidence/{task_id}/{run_id}/steps/`
4. For parallel group:
   - Dispatch all agents in single message (multiple Task calls)
   - Collect all outputs
5. Verify outputs: present? scope respected? acceptance criteria met?
6. **Review Checkpoint CP2** — dispatch verifier (`code-review` focus) with step output + branch diff
   - If verifier PASS → continue
   - If verifier FAIL + `fix_loop_eligible` → dispatch gate-fixer with findings → re-dispatch verifier (max 2 iterations)
   - If fix loop exhausts or `fix_loop_eligible: false` → ESCALATION (E7)
   - Skip if `review_checkpoints.cp2_step_review: false` or step is trivial (see `skip_trivial` config)
7. Log to `timeline.jsonl`

**Integration Review (CP3):** When all steps are done, before transitioning to GATES:
- Dispatch verifier with `code-review` + `security` focuses in parallel (full diff since run start)
- Fix loop same as CP2 (gate-fixer → verifier, max 2 iterations)
- Skip if `review_checkpoints.cp3_integration_review: false`

**Transition:**
- All steps done + CP3 pass → GATES
- CP3 fix loop exhausts → ESCALATION (E7)
- Hard failure → ESCALATION
- Next step available → EXECUTE (self-loop, increment `current_step`)

### State: GATES

**Actions:**
1. Read gate definitions from `config/execution.yaml`
2. Run each gate command (per `scripts/aid-run-gates.sh`):
   - `test_cmd` from `config/project.yaml`
   - `lint_cmd` from `config/project.yaml`
   - `build_cmd` from `config/project.yaml`
   - Custom gates from `execution.yaml`
3. Generate `gates_report.json`
4. Log results to `timeline.jsonl`

**Transition:**
- All gates pass → DONE
- Gate fails + retries remaining → EXECUTE (dispatch gate-fixer, retry gate)
- Gate fails + retries exhausted → ESCALATION

### State: ESCALATION

**Trigger:** Gate failure after max retries, agent error, scope violation, acceptance not met.

**Actions:**
1. Build escalation context (reason, attempts, per-type details)
2. In manual mode → present to PM:
   ```
   ESCALATION: {reason}
   ====================================
   EPIC: {epic_id} | Step: {current_step}/{total_steps}

   {per-type context — see pipeline.md §6 per-type context blocks}

   What was tried: {attempt history}

   Options:
     (A) Fix — provide guidance, agent re-dispatches
     (B) Skip — proceed to next state (warnings logged)
     (C) Abort — halt EPIC, save progress (/aid-stop)

   Recommendation: {auto-generated}
   ```
3. In auto mode → apply auto-decision rules:
   - S-effort fix patterns → auto-fix
   - M-effort → use default action from permissions
   - L-effort / security → escalate to PM (even in auto mode)

**Transition:**
- Fix → EXECUTE (resume from failed point)
- Skip gate → GATES (re-check remaining)
- Abort → ERROR

### State: DONE

DONE uses two mechanically enforced sub-phases: `review` → `release`.
Sub-phase transitions are managed by `done-advance` (not `transition`).

**Sub-phase: `review`** (auto-set on GATES→DONE)

1. Update `state.yaml`: `state: DONE`, `done_phase: review` (automatic)
2. Archive run file → `runs/archive/`
3. Update `work/active.md`
4. Generate `final_report.md`
5. **Parallel dispatch:** Curator + Auditor agents (two Agent calls in single message)
6. Wait for both to complete → evidence saved to `evidence/{epic_id}/{run_id}/`
7. **CP4** — verifier (`code-review`) on curator-proposed changes
   - If FAIL → revert curator changes, log reversion
   - Skip if `review_checkpoints.cp4_curator_validation: false`
8. **Curator auto-fix** — gate-fixer applies approved S + M effort proposals
9. **Auditor auto-fix** — gate-fixer applies S + M effort `recommended_fixes` (where `auto_fixable: true`)
10. **CP5** — check auditor `blocking_findings` flag → flag in PM summary
11. **PM Summary** (see `pipeline.md` §7 for full template):
    ```
    DONE REVIEW — {epic_id}
    Steps: {done}/{total} | Gates: {pass}/{total} | Duration: {time}

    Auditor Score: {overall}/100 (trend: {delta})
      Code: {n} | Security: {n} | Docs: {n} | Process: {n}

    Curator: {applied} fixes applied (S/M), {deferred} deferred (L)
    Auto-fixes: {count} from auditor recommendations

    {if blocking_findings:}
    ⛔ CRITICAL FINDINGS (block merge):
      1. [{type}] {finding} — effort: {S|M|L}
      Audit report: .aid-o/work/evidence/{id}/{run}/audit-report.md

    Key outputs: {artifact list}
    Evidence: .aid-o/work/evidence/{id}/{run_id}/

    Options:
      MERGE — release + merge to main + queue pickup
      FIX   — provide guidance, re-run review cycle
      ABORT — stop EPIC, no merge
    ```
12. **PM decides:** MERGE → step 13 | FIX → re-run steps 5-11 | ABORT → ERROR (E8)
13. **Advance sub-phase:** PM chose MERGE →
    ```
    bash {plugin_path}/scripts/aid-fsm.sh set-field pm_decision merge <state_file>
    bash {plugin_path}/scripts/aid-fsm.sh done-advance review release <state_file>
    ```
    Preconditions enforced: `curator-report` exists, `audit-report` exists, `pm_decision=merge`.

**Sub-phase: `release`** (after `done-advance review release`)

14. Release automation (`aid-release.sh`)
15. Branch merge: `git merge epic/{id} --no-ff` → delete run branch
16. Queue pickup + metrics logging

### State: ERROR

**Trigger:** Unrecoverable failure or PM abort.

**Actions:**
1. Log error to `timeline.jsonl`
2. Update `state.yaml`: `state: ERROR`
3. Preserve all evidence for debugging
4. Report to PM with error context

## Reference Files

- `skills/pipeline.md` — §4 EXECUTE dispatch protocol, §5 GATES protocol
- `scripts/aid-fsm.sh` — FSM transition validation
- `scripts/aid-run-gates.sh` — gate execution
- `scripts/lib/aid-stage-log.sh` — timeline.jsonl logging
- `config/execution.yaml` — gate definitions (lazy-created on first run)
- `config/permissions.yaml` — autonomous mode settings

## Important

- **Review Checkpoints** — CP2-CP5 dispatched automatically per `config/policies/review-checkpoints.yaml`; individually toggleable
- **Pre-merge review** — Curator + Auditor run in parallel BEFORE merge; PM approves via MERGE/FIX/ABORT
- **Escalation E7** — verifier review failed after 2 fix-loop iterations
- **Escalation E8** — PM chose ABORT in DONE summary due to critical auditor findings
- **6 states only** — READY, EXECUTE, GATES, ESCALATION, DONE, ERROR
- **DONE sub-phases** — `review → release`, managed by `done-advance` (not `transition`); `set-field` rejects writes to `done_phase`
- **No v1 states** — no IDLE, PRE_FLIGHT, SCOPE_CHECK, PLAN, CURATOR_RESOLVE, PM_APPROVAL, DEPLOY_CHECK, FINALIZING
- **PRE-FLIGHT is bash** — runs before FSM starts, not an FSM state
- **`--auto` replaces `/aid-first-aid`** — same autonomous behavior, integrated flag
- **`--resume` reads state.yaml** — picks up from last known state after crash/interrupt
- If `$ARGUMENTS` is empty → auto-detect: find single active task or list for selection
- Pipeline references: `pipeline.md §4 EXECUTE` for dispatch, `§5 GATES` for gate execution
