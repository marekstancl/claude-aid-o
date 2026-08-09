---
name: aid-run
description: Execute EPIC pipeline — 6-state FSM with optional autonomous mode
user_invocable: true
---

Run the 6-state FSM controller to orchestrate an EPIC through its full lifecycle. Replaces the old `/aid-run-epic` and `/aid-first-aid` commands.

## Usage

```
/aid-run                        # manual mode — start or auto-detect active EPIC
/aid-run <epic-id>              # manual mode — start specific EPIC
/aid-run --auto                 # autonomous mode — auto-approve S-effort fixes
/aid-run --auto --epic <id>     # autonomous mode for specific EPIC
/aid-run --resume               # resume interrupted run from fsm-state.yaml
```

## Flags

| Flag | Behavior |
|------|----------|
| (none) | Manual mode — asks PM approval at each escalation |
| `--auto` | Autonomous mode (replaces `/aid-first-aid`) |
| `--resume` | Resume from last known state in `fsm-state.yaml` |
| `--epic <id>` | Specify EPIC ID (otherwise auto-detect) |

### Autonomous Mode (`--auto`)

Escalation rules for `--auto`:
- **S-effort fixes** → auto-approve, apply fix, continue
- **M-effort decisions** → use default decision from `config/permissions.yaml`
- **Recoverable technical decisions** (retry, repair, stale evidence, process failure,
  test selection) → dispatch the configured Codex adjudicator, record its decision in
  `timeline.jsonl`, then continue. Do not ask the PM to choose between technical A/B/C options.
- **PM-authority decisions only** (product intent, material scope expansion, destructive or
  externally visible action, security risk acceptance, secret/credential access) → pause for PM.
- Gate retries → auto-retry up to configured max (default: 2)
- Version bump on intermediate phase → auto-defer (bump only on final phase)

Requires `autonomous_mode: true` in `.aid-o/config/permissions.yaml`.
If not set, `--auto` prints a warning and falls back to manual mode.

### What `--auto` records about itself — the four run states

Read this before starting an AUTO run — it is what you, or the next controller, reason from after
an interruption.

Every live EPIC has an entry in `.aid-o/work/active-runs.json`. The entry's `auto_controller` field
is stamped at `init`, the only site that writes an entry into the map (`upsert_active_run`). The
other lifecycle boundaries do not re-stamp it — the done-advance review→release edge, `plan-close`
and `active-runs prune` all REMOVE the entry instead. After `init`,
`aid-fsm.sh active-runs set <epic> auto_controller <value>` is the only single-field writer. Three
values are **storable**, and the fourth state is never stored at all.

| State | Stored? | What it means | Who sets it |
|-------|---------|---------------|-------------|
| `active` | yes | An autonomous controller is alive and owns this run. | `init`, when `AID_AUTO_MODE=1`; re-asserted by `aid-run-gates.sh` after the run's last background job is collected, and by `aid-fsm.sh resume` — in both cases only for an AUTO run. |
| `manual` | yes | No autonomous controller — a human drives this run. The conservative default whenever the entry is not stamped AUTO. | `init`, when `AID_AUTO_MODE=1` is not set |
| `blocked_for_pm` | yes | The run stopped at a PM-authority decision and is waiting for a person. | *Nothing writes it yet.* The value is accepted by the writer and reserved for the escalation ladder's terminus, which is a later plan step. Treat it today as vocabulary, not as observed state. |
| `awaiting_host_resume` | **never** | A background gate was handed off and the controller then died: the run's continuation artifact is still on disk and nothing has signalled liveness. | Nobody. It is **derived** at read time. |

`awaiting_host_resume` is derived rather than stored for one reason: a controller that has died
cannot write anything on its way out, so any stored flag would be written by the one party that is
by definition unable to write. The writer enforces this — passing `awaiting_host_resume` to
`active-runs set` is rejected with an error naming why. Consumers compute it instead, from two
facts the dead controller provably left behind:

1. the run's continuation artifact `<evidence_dir>/auto_resume_required.json` still exists (it is
   written *before* a background job spawns and deleted only on a clean terminal collect), and
2. no liveness signal is recent enough. `aid-fsm.sh active-runs stalled` is the shipped derivation
   of that half — newest of the entry's `updated_at` and the run timeline's newest event, against
   `AID_ACTIVE_RUN_STALL_SEC` (default 2100 s) — and `/aid-status` renders its verdict as the
   `STALLED?` marker plus the recovery line. The string `awaiting_host_resume` does appear in
   output — as the writer's rejection message (`aid-fsm.sh`) and in `/aid-help` prose — but no
   surface ever reports it as an observed state of a run: it names the two facts holding together,
   not a value anything stores or emits as a verdict.

**The resume flow.** When both hold, run `bash {plugin_path}/scripts/aid-fsm.sh resume <epic_id>`.
It claims the artifact exactly once, collects the referenced job's terminal result, records it as a
durable gate-row checkpoint under `<evidence_dir>/gates_rows/<gate>.json` (the next `run-all`
assembles it — `resume` never edits a final report), updates the active-runs entry, and prints
three lines: what it found, what it recorded, and the next action. It never fabricates a result: a
missing job record, a `lost` job and a `stale` result are each reported verbatim with the rerun
instruction. A job still in flight is a read-only status report — nothing is claimed, the artifact
stays valid. Executing the printed next action is the controller's job, not the command's.

### AUTO liveness and ownership contract

`--auto` is a terminal-outcome contract, not merely automatic approval at READY. The controller
MUST keep ownership until the EPIC completes, reaches a PM-authority decision, or encounters an
unrecoverable external outage. A recoverable technical problem is not a reason to end the turn.

- The controller is the sole owner of FSM mutations, commits, gates, evidence finalization, and
  long-running/background processes. Dispatched implementers and verifiers never own these.
- Never finish a turn with only "waiting for tests/agent". For every asynchronous process record
  PID, log path, start HEAD, start tree hash, start time, expected p95, and hard deadline. Poll the
  process itself and collect its exit status; `tail -f` is forbidden as a completion detector.
- If no owned process is alive and no repository/evidence progress occurred for 5 minutes, resume
  or diagnose automatically. Do not wait indefinitely for a missing notification. "Resume" is a
  named mechanical path, not a judgement call:
  1. **The artifact.** A run that handed a gate to the background supervisor left exactly one
     continuation pointer at `<evidence_dir>/auto_resume_required.json`. Its presence, plus the
     absence of a liveness signal, is what "a resume is required" means — the state is derived,
     never stored, because a dying controller cannot write anything on its way out.
  2. **The command.** Run `scripts/aid-fsm.sh resume <epic_id>`. It claims that pointer exactly
     once, collects the referenced job's terminal result, records it as a durable gate-row
     checkpoint the next `run-all` assembles, updates the active-runs entry, and prints what it
     found, what it recorded, and the next action. A job still in flight is a read-only status
     report: nothing is claimed and the pointer stays valid for the next resume.
  3. **The printed next action.** Execute it.
  Steps 1–2 are mechanical — the command performs them and reports facts. Step 3 is an
  instruction: `resume` cannot take the controller's turn for it, so a resume that prints a next
  action and stops has not finished the work. The controller has.
- The concrete supervisor for this contract is `scripts/aid-job.sh` (IMP-262), opt-in at the
  controller boundary — not a hard precondition and not a release gate. `aid-job.sh run` starts a
  command in its own process group with a durable record; `status`/`collect` read completion from
  the owned process + terminal result (PID-reuse-safe, `tail -f` is never liveness, a started
  job is not evidence); `cancel` signals the recorded group so no child is orphaned; `watchdog`
  answers `resume_needed` when no owned job is live and no progress occurred within the interval.
- A test result is valid only for the recorded HEAD/tree and command fingerprint. If relevant files
  change during or after the run, mark the result stale. Never report pass counts without a completed
  result artifact containing command, start/end revision, timestamps, exit code, and counts.
- Run step-scoped tests during implementation. Run the expensive aggregate suite once, on the final
  immutable candidate HEAD. Do not run an aggregate gate together with another gate that recursively
  executes the same suite. A failed aggregate run may be followed by targeted diagnosis, but a fix
  requires one fresh final aggregate result; the pre-fix run cannot prove the post-fix HEAD.
- Verifiers use an isolated worktree or immutable revision. Never run a mutating fixer concurrently
  against the checkout a verifier is reviewing.
- Codex adjudication and PM decisions are append-only audit events. The adjudicator may choose among
  already-authorized technical recovery paths; it cannot grant PM authority or waive security risk.

Until a dedicated adjudicator command is available, use the existing isolated Codex transport. Give
it only: verified facts, current FSM state, attempted recoveries, an explicit allowlist of reversible
in-scope actions, and forbidden authority-expanding actions. Require one selected action plus a short
rationale and risk note. Reject an answer outside the allowlist, append the accepted decision and
evidence paths to `timeline.jsonl`, and continue. This is a temporary dispatch convention, not a
substitute for the project-scoped adjudicator configuration planned for INIT/SETUP.

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
7. **Do NOT edit fsm-state.yaml directly** — all mutations go through `aid-fsm.sh` commands (`transition`, `increment-step`, `set-field`)
8. **`--force` is PM-only** — never use without explicit PM instruction; logged to audit trail
9. **Multi-layer defense** — `aid-release.sh` and git pre-commit hook independently verify `done_phase` before allowing release/commit on FSM branches
10. **Step verification evidence** — `increment-step` REFUSES to advance without `step-{N}-verify.md` containing `## Result: PASS` in evidence dir
10a. **Read `status=` from increment-step, never a bare number** — success prints `status=advanced advanced_from=N advanced_to=N+1` (exit 0). `status=already_applied ...` (exit 0) means the transition was already recorded (replay/crash-recovery) — it is SUCCESS, do NOT re-invoke. A bare-numeric misread as an error is exactly what caused the E-064-1_2 double advance. Non-zero exit = a real precondition failure (see stderr); never `--force` past a `binding_*` rejection.
10b. **Step-binding (IMP-263)** — write `step_index` / `step_id` / `plan_step_hash` / `reviewed_commit` (=HEAD) / `idempotency_token` into `step-{N}-verify.md` AFTER the per-step commit. The binding is validated against the live `plan.json` + FSM state before any mutation, so a copied prior verify file cannot complete a later step. See `skills/pipeline.md` for the `plan_step_hash` recipe and `AID_STEP_BINDING=strict`.

### Agent dispatch rules (non-negotiable but instruction-enforced):
11. **Verbatim plan content** — NEVER send agents "read the plan". Extract relevant section and paste VERBATIM into agent prompt. Include code snippets, AC, mockups.
12. **Visual verification** — after any UI step: Playwright screenshot + compare with mockup. "Compiles" ≠ "looks right".
13. **Plan-level DONE gate** — `aid-fsm.sh init` blocks new cross-plan run if previous plan has unreviewed C+A findings (no `ca-review-complete` marker)
14. **Per-plan C+A review** — after last EPIC in a plan, ALL C+A findings (S+M+L) must be addressed before starting next plan
15. **Sequential dispatch** — `orchestration.yaml → max_parallel: 1`. Dispatch ONE agent at a time. After each agent returns: validate output, commit, write step-verify, increment-step. NEVER dispatch multiple agents in parallel.
16. **Per-step commit** — MUST `git commit` after each step completes, BEFORE calling `increment-step`. One commit per step, not bulk commits at the end.

### Precondition failures are HARD STOPS:
- Do NOT attempt alternative transitions to work around a failure
- Do NOT modify `fsm-state.yaml` directly to bypass checks
- **Manual mode:** present the error to PM and wait for guidance
- **Auto mode:** preserve the failed state, diagnose the named precondition, and route recoverable
  technical choices to Codex adjudication. Pause for PM only when the decision requires PM authority
  under the AUTO contract above.
- The error message tells you exactly what's missing

### Context window:
- Do NOT warn about context window, compaction, or token limits
- Do NOT ask PM about context management
- With 1M token window, context is not a concern — continue working
- Do NOT pause between EPICs to "check context" — proceed to next EPIC immediately

**The one carve-out.** The rules above forbid ending a turn to talk about context, and the AUTO
liveness contract forbids ending a turn on "waiting". Neither is a licence to hide a real handoff.
The one legitimate turn-ending message is the `awaiting_host_resume` card: the artifact exists, the
resume command is printed, and nothing false is claimed. The card has four parts, in order:
**what stopped** (derived from the artifact plus the missing liveness signal), **the impact** (what
is consequently not done), **the recommended action**, and **the exact command**
`bash {plugin_path}/scripts/aid-fsm.sh resume <epic_id>`. A card that omits the artifact path, omits
the command, or asserts a gate result nobody collected is not this carve-out — it is the failure the
carve-out exists to distinguish itself from.

### Gate execution:
- Use `--state-file` and `--report-file` flags with `aid-run-gates.sh`:
  ```
  bash {plugin_path}/scripts/aid-run-gates.sh run-all <execution.yaml> <epic_id> <run_id> <timeline_file> \
    --state-file <state_file> --report-file <evidence_dir>/gates/gates_report.json
  ```
- `--state-file` ensures gates only run when FSM is in GATES state
- `--report-file` persists `gates_report.json` (required by `GATES→DONE` precondition)
- **`--profile <name>` (P061 E1, optional)** — restricts this run to the gate keys listed in
  `execution.yaml.gate_profiles.<name>.include[]`. Gates NOT in that list get an explicit
  `profile_excluded` result row (never silently dropped, never fails `overall`). Omitting
  `--profile` runs every defined gate exactly as before. Unknown profile name, or an
  `include[]` entry that isn't a key under `execution.yaml.gates`, fails loud (exit 1) before
  any gate runs. Today `--profile` is a purely explicit, manual flag — nothing in `/aid-run`
  selects it automatically yet (that's a later P061 EPIC). See `pipeline.md §5` for full detail.
- **Plan-gate floor at `GATES→DONE`** — if `plan.json.gates[]` names a gate, that gate must
  not appear in `gates_report.json.excluded_gates[]`; `aid-fsm.sh` refuses the transition
  (reason `plan_gate_profile_excluded`) otherwise. A malformed `plan.json` also blocks the
  transition (reason `plan_json_malformed`) rather than being treated as no requirements.
  Override via `--force --reason '<≥20 chars>'` like any other `GATES→DONE` precondition.

## PRE-FLIGHT (before FSM starts)

**Plugin path verification:**
1. Read `plugin_path` from `.aid-o/config/plugin.yaml`
2. Verify: `test -f {plugin_path}/scripts/aid-fsm.sh`
3. If stale or missing → re-discover: `glob ~/.claude/plugins/**/aid-orchestrator/scripts/aid-fsm.sh` → update `plugin.yaml`
4. If still not found → abort with: "Plugin scripts not found. Run `/aid-init` to refresh."

**Bash pipeline** (using resolved `plugin_path`) — when running from a plan,
steps 1–3 are ONE TRANSACTION held under a single lock:
1. `{plugin_path}/scripts/aid-cp1-gate.sh` — the ONE CP1 call for the whole plan, before any output exists (skipped when a valid sealed authority already binds this identity).
2. `generation-authority.json` + `transaction.json` — the sealed decision and the per-phase record, written under `.aid-o/work/evidence/<plan_id>/generation/`.
3. `{plugin_path}/scripts/aid-plan-to-epic.sh` — generate every EPIC, each VERIFYING the authority rather than re-running the gate
4. `{plugin_path}/scripts/aid-epic-to-json.sh` — parse every EPIC → plan.json
5. `{plugin_path}/scripts/aid-generation-finalize.sh` — verify the complete package and write its receipt.
6. `{plugin_path}/scripts/aid-plan-fsm.sh epic-start` — register each EPIC's `task/<epic>/main` as a ref with lineage back to `plan/<id>`. plan_branch plans only, and driven by `aid-json-to-run.sh` from the plan's COMMITTED mode; `init` is the first consumer of that lineage and refuses without it. Legacy plans skip it — they have no plan branch to descend from.
7. `{plugin_path}/scripts/aid-json-to-run.sh` — plan.json → execution.yaml + fsm-state.yaml init, only after the receipt. A **failing** init still hands the caller's branch back before the failure is reported, and the plan worktree is returned to `plan/<id>` after each init so the next phase does not meet a tree still on the previous phase's task branch.
   When `/aid-run --streamlined` is invoked, the orchestrator MUST pass
   `--streamlined` to this script: `aid-json-to-run.sh … --streamlined`. The
   script forwards it to its Step 18 `aid-fsm.sh init` call, which writes
   `streamlined_mode: true` into `fsm-state.yaml` (P040 Component D). Without this
   passthrough the auto-init defaults to full mode regardless of the `/aid-run`
   flag. The positional execution `mode` stays `full` — streamlined is a
   separate dimension carried only by the `--streamlined` flag.

These are **bash scripts**. No LLM involvement. Exit non-zero → abort with error message.
PM must fix the underlying issue (missing steps, circular deps, invalid EPIC format).

A refusal from the CP1 call is labelled: `aid_generation_force_required:` when
a deliberate PM `--force --reason` could proceed (the exact command is printed
with this invocation's values), `aid_cp1_blocked:` when it could not — and on that class `--force` is refused in the same place rather than merely unadvertised. Anything
else that fails is passed through verbatim. An interrupted PRE-FLIGHT is
resumed by rerunning the same command — verified phases are skipped.

```
PRE-FLIGHT Pipeline
====================================
  [1] CP1 gate (once per plan) → authority       ✓
  [2] transaction.json opened                    ✓
  [3] all phases: plan-to-epic + epic-to-json    ✓
  [4] aid-generation-finalize.sh → receipt       ✓
  [5] aid-json-to-run.sh → fsm-state.yaml        ✓

FSM initialized: READY
```

## 6-State FSM

```
             ┌──────────┐
             │  READY   │
             └────┬─────┘
                  │ approve
        ┌────────►┌────▼─────┐ ◄── fix applied (ESCALATION→EXECUTE)
        │ gate    │ EXECUTE  │
        │ retry   └────┬─────┘
        │ (max 2)      │ all steps done
        │         ┌────▼─────┐   all pass    ┌──────────┐
        └─────────│  GATES   │──────────────►│   DONE   │  (terminal:
                  └────┬─────┘               └──────────┘   review→release)
                       │ retries exhausted
                  ┌────▼───────┐  skip gate
                  │ ESCALATION │─────────────► GATES
                  └────────────┘

   ERROR (terminal) ◄── hard failure from any of READY / EXECUTE / GATES / ESCALATION
```

### State: READY

**Entry:** PRE-FLIGHT completed, `fsm-state.yaml` initialized.

**Actions:**
1. Load `execution.yaml` (gate definitions, step config)
2. Load `config/permissions.yaml` (mode, auto-approve rules)
3. **AUTO MODE → SKIP TO STEP 5 IMMEDIATELY.** Do NOT display EPIC summary, do NOT present Options, do NOT wait for PM.
4. **Manual mode only:** Display EPIC summary to PM:
   ```
   EPIC: {id} — {title}
   Steps: {N}
   Mode: manual

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
   Wait for PM decision (GO/REVISE/ABORT).
5. **Auto mode:** Validate plan JSON schema → auto-GO → transition READY→EXECUTE immediately. No presentation, no waiting.

**Transition:** → EXECUTE (GO) | stay READY (REVISE) | ERROR (ABORT)

### State: EXECUTE

**Actions:**
1. Read `fsm-state.yaml` → find `current_step`
2. Check dependency graph → pick the next step with all deps satisfied
3. Dispatch the step (one agent at a time — `max_parallel: 1`, see rule 15):
   - Work happens on the single EPIC branch `task/{epic_id}/main` (created by `aid-fsm.sh init`); there is no per-step branch.
   - Build agent prompt (per `pipeline.md §4`)
   - Dispatch agent via Task tool
   - Collect output → save to `work/evidence/{epic_id}/{run_id}/steps/`
4. Verify outputs: present? scope respected? acceptance criteria met?
5. **Review Checkpoint CP2** — dispatch verifier (`code-review` focus) with step output + branch diff
   - If verifier PASS → continue
   - If verifier FAIL + `fix_loop_eligible` → dispatch gate-fixer with findings → re-dispatch verifier (max 2 iterations)
   - If fix loop exhausts or `fix_loop_eligible: false` → ESCALATION (E7)
   - Skip if `review_checkpoints.cp2_step_review: false` or step is trivial (see `skip_trivial` config)
6. Log to `timeline.jsonl`

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
   - If `--profile <name>` was passed, only gates in that profile's `include[]` run — the rest
     get a `profile_excluded` row (see "Gate execution" above, `pipeline.md §5`)
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
   EPIC: {epic_id} | Step: {executing_step}/{total_steps}


   {per-type context — see pipeline.md §6 per-type context blocks}

   What was tried: {attempt history}

   Options:
     (A) Fix — provide guidance, agent re-dispatches
     (B) Skip — proceed to next state (warnings logged)
     (C) Abort — halt EPIC, save progress (/aid-stop)

   Recommendation: {auto-generated}
   ```

**Step rendering rule.** `current_step` in `fsm-state.yaml` is 0-BASED and counts COMPLETED steps, so it is never rendered to a human directly. Derive `executing_step = min(current_step + 1, total_steps)` and render that: while executing it names the step being worked on; once every step is done (`current_step == total_steps`, state GATES/DONE) it caps at `total_steps`, so the line reads `total_steps/total_steps` rather than a nonsensical `T+1 of T`. When `total_steps` is 0 (a degenerate plan) render the machine values only. The machine field itself, the `aid-fsm.sh verify-state` JSON payload, and evidence filenames stay 0-based and are frozen compatibility surfaces.

3. In auto mode → apply auto-decision rules:
   - S-effort fix patterns → auto-fix
   - M-effort → use default action from permissions
   - Recoverable L-effort technical decisions → Codex adjudication + logged decision
   - Security risk acceptance, product/scope decisions, destructive or externally visible actions
     → PM (the adjudicator cannot authorize these)

**Transition:**
- Fix → EXECUTE (resume from failed point)
- Skip gate → GATES (re-check remaining)
- Abort → ERROR

### State: DONE

DONE uses two mechanically enforced sub-phases: `review` → `release`.
**C+A model:** Dispatch per EPIC (background OK), validate per Plan (hard stop). See `pipeline.md §7`.
Sub-phase transitions are managed by `done-advance` (not `transition`).

**Sub-phase: `review`** (auto-set on GATES→DONE)

1. Update `fsm-state.yaml`: `state: DONE`, `done_phase: review` (automatic)
2. Archive run file → `runs/archive/`
3. `work/active.md` refreshes automatically at the done-advance boundary (generated index of active streams — never hand-edit it; detail lives in `work/plan-state/`)
4. Generate `final_report.md`
5. **Parallel dispatch:** Curator + Auditor agents (two Agent calls in single message)
6. Wait for both to complete → evidence saved to `evidence/{epic_id}/{run_id}/`
7. **Curator auto-fix** — gate-fixer applies approved proposals at every effort (S/M/L); only an
   explicit always-defer rule (architecture, standards-L) defers
8. **Auditor auto-fix** — gate-fixer applies S/M/L `recommended_fixes` (where `auto_fixable: true`)
9. **CP4** — verifier (`code-review`) reviews the APPLIED curator/auditor changes (runs AFTER the
   apply, so it actually reviews them)
   - If FAIL → revert those changes, log reversion
   - Skip if `review_checkpoints.cp4_curator_validation: false`
10. **CP5** — check auditor `blocking_findings` flag → flag in PM summary
11. **PM Summary** (see `pipeline.md` §7 for full template):
    ```
    DONE REVIEW — {epic_id}
    Steps: {done}/{total} | Gates: {pass}/{total} | Duration: {time}

    Auditor Score: {overall}/100 (trend: {delta})
      Code: {n} | Security: {n} | Docs: {n} | Process: {n}

    Curator: {applied} fixes applied (S/M/L), {deferred} deferred (always-defer rules / rejected)
    Auto-fixes: {count} from auditor recommendations
    Simplifier: {applied} applied, {deferred} L-effort deferred
    Delivery report: .aid-o/reports/{plan_id}-delivery.md (outcome: {pass|partial|no-runtime})

    {if blocking_findings:}
    ⛔ CRITICAL FINDINGS (block merge):
      1. [{type}] {finding} — effort: {S|M|L}
      Audit report: .aid-o/work/evidence/{id}/{run}/audit-report.md

    Key outputs: {artifact list}
    Evidence: .aid-o/work/evidence/{id}/{run_id}/

    Options (`legacy_epic_release_mode`):
      MERGE — release + merge to main + queue pickup
      FIX   — provide guidance, re-run review cycle
      ABORT — stop EPIC, no merge

    Options (`plan_branch`):
      MERGE — merge this EPIC into the PLAN branch; no release, no tag, no push.
              The release happens once, later, at the plan-final boundary.
      FIX   — provide guidance, re-run review cycle
      ABORT — stop EPIC, no merge
    ```
    The summary above is the `legacy_epic_release_mode` shape. In `plan_branch`
    mode the Auditor/Curator/Simplifier/Reporter lines describe the PLAN-FINAL
    review, not a per-EPIC one — those roles run once per plan, at the boundary,
    against the frozen candidate. An EPIC completing in `plan_branch` mode owes
    its CP3 pair and its own evidence, not a specialist stack.
12. **PM decides:** MERGE → step 13 | FIX → re-run steps 5-11 | ABORT → ERROR (E8)
13. **Advance sub-phase:** PM chose MERGE →
    ```
    bash {plugin_path}/scripts/aid-fsm.sh set-field pm_decision merge <state_file>
    bash {plugin_path}/scripts/aid-fsm.sh done-advance review release <state_file>
    ```
    Preconditions enforced in `legacy_epic_release_mode`: `curator-report` exists,
    `audit-report` exists, `pm_decision=merge`. In `plan_branch` mode the FSM skips the
    Curator/Auditor/CP4/C3/C4 stack plus the **CP3 freshness re-check** and the
    **review-profile presence** check. It does **not** skip CP3 itself — the CP3
    code-review + CP3 security verifiers are still dispatched per EPIC, and under
    `--streamlined` their two outputs remain a hard precondition of `done-advance`.
    `pm_decision=merge`, the archived-task-file check, the auditor's `blocking_findings`
    verdict whenever an `audit-report` exists at all, and the other EPIC-local checks
    (streamlined integration review, abandoned check, DG-07, tiered compliance) still apply.

**Sub-phase: `release`** (after `done-advance review release`)

Steps 14-16 fork on the plan's declared release mode
(`.aid-lifecycle/manifests/{plan_id}.yaml` → `mode`). Full instructions in
`pipeline.md §7` — "Sub-phase: `release`".

*In `plan_branch` mode (an intermediate EPIC inside an open plan):*

14. No release automation — no `aid-release.sh`, no version bump, no tag, no push
15. `aid-plan-fsm.sh epic-complete`, then `aid-plan-fsm.sh epic-merge-to-plan` — only
    `plan/{plan_id}` moves; the target branch is never touched, and
    `plan-record-delivery` is deferred to `plan-merge-to-main` (P068)
16. Queue, in this order, both direct calls to `lib/aid-queue-write.sh` (library only —
    `aid-plan-fsm.sh` does not write the queue yet):
    **16a** `aid-queue-write.sh set-status {epic_id} merged_to_plan` — mirrors the merge
    step 15 proved in Git. **Never skip it:** `epic-merge-to-plan` leaves the entry at
    `running`, and a dependent whose dependency has no `merge_target` is resolved from
    that status, so the next EPIC is recorded `blocked:…:dependency_unmerged` and the
    plan stalls at EPIC 2.
    **16b** `aid-queue-write.sh claim-next {plan_id}` — exit 0 prints the claimed id,
    exit 1 is `blocked:<id>:<reason>` or `none`, exit 2 usage, exit 3 lock.
    Then report: "EPIC complete and merged into `plan/{plan_id}`; plan remains open; no
    plan-final release decision has run yet"

*In `legacy_epic_release_mode` (pre-P064):*

14. Release automation (`aid-release.sh`)
15. Branch merge: `git merge task/{epic_id}/main --no-ff` → delete run branch
16. Queue pickup + metrics logging

*Mode unresolvable:* `done-advance` exits non-zero with `plan_mode_unresolved`. Stop and
repair the lifecycle manifest — never fall back to the legacy branch.

### State: ERROR

**Trigger:** Unrecoverable failure or PM abort.

**Actions:**
1. Log error to `timeline.jsonl`
2. Update `fsm-state.yaml`: `state: ERROR`
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
- **Pre-merge review** — mode-dependent. In `legacy_epic_release_mode` Curator + Auditor run in parallel before the EPIC merge. In `plan_branch` they do not run per EPIC at all: they are plan-final roles, dispatched once per plan against the frozen candidate, and the EPIC owes its CP3 code-review + security pair instead. PM approves via MERGE/FIX/ABORT in both modes
- **Escalation E7** — verifier review failed after 2 fix-loop iterations
- **Escalation E8** — PM chose ABORT in DONE summary due to critical auditor findings
- **6 states only** — READY, EXECUTE, GATES, ESCALATION, DONE, ERROR
- **DONE sub-phases** — `review → release`, managed by `done-advance` (not `transition`); `set-field` rejects writes to `done_phase`
- **No v1 states** — no IDLE, PRE_FLIGHT, SCOPE_CHECK, PLAN, CURATOR_RESOLVE, PM_APPROVAL, DEPLOY_CHECK, FINALIZING
- **PRE-FLIGHT is bash** — runs before FSM starts, not an FSM state
- **`--auto` replaces `/aid-first-aid`** — same autonomous behavior, integrated flag
- **`--resume` reads fsm-state.yaml** — picks up from last known state after crash/interrupt (legacy `state.yaml` still accepted as fallback)
- If `$ARGUMENTS` is empty → **auto-detect over plan streams**, never "the single
  active EPIC". Read `.aid-o/work/plan-state/*/plan-state.yaml` (phase +
  `worktree_path`) and `.aid-o/work/active-runs.json` (the map keyed by
  `epic_id`, carrying `plan_id`, `state`, `branch`) from the state root — the
  same reads `/aid-status` documents as recipes `plan-rows` / `plan-epics`:
  - **Zero active plans** — no plan-state entry outside PLAN_MERGING / CLOSED /
    ABORTED / ROLLED_BACK. Do not start anything. List the plans available in
    `.aid-o/plans/` and suggest `/aid-plan` or an explicit `/aid-run <epic-id>`.
  - **One active plan** — today's behaviour, unchanged: pick that stream's next
    actionable EPIC and proceed (still confirming the target with the PM as
    before).
  - **Two or more active plans** — never guess. Print a **named selection list**,
    one row per active plan in plan-id order: plan id, lifecycle phase, worktree
    path (with `missing!` when recorded but absent), and the plan's **next
    actionable EPIC**. Ask the PM which stream to run and wait; `/aid-run
    <epic-id>` skips the question entirely. Example:

    ```
    Two active plans — which stream?
      1) P074 — EPIC_INTEGRATION  worktree .aid-worktrees/plan-P074  next: E-074-2_3  [READY]
      2) P073 — PLAN_GATES        worktree .aid-worktrees/plan-P073 missing!  next: E-073-4_4  [queue:pending, 1 dep(s) unverified]
    ```
  - **"Next actionable EPIC" is one shared, deterministic rule** — defined once
    in `commands/aid-status.md` ("Next actionable EPIC" + recipe `next-epic`)
    and used verbatim here, so `/aid-status` and `/aid-run` never name different
    EPICs for the same plan:
    1. The plan's entries in `active-runs.json` whose `state` is `READY`,
       `EXECUTE` or `GATES`, **sorted by `epic_id`, lowest first**. A JSON
       object's key order is not an ordering and must never be treated as one.
    2. Otherwise the queue candidate: the first entry **in queue file order**
       belonging to the plan whose normalized status is `pending` (legacy
       `queued` reads as `pending`) or `blocked` — the exact claimability test
       `queue_claim_next` uses (`scripts/lib/aid-queue-write.sh`). It is shown
       as a candidate with its unverified `depends_on` count, because the full
       eligibility test includes a live `git merge-base --is-ancestor` check per
       dependency that only `queue_claim_next` performs — and that function
       CLAIMS (writes `running`/`blocked`), so selection must not call it. The
       claim happens when the run actually starts; a candidate can still turn
       out blocked there, and that is reported, not guessed at selection time.
    3. Otherwise `(none)`.
  - A plan whose recorded worktree is missing stays selectable, but the run is
    refused after selection with the repair line
    (`plan-state <id> --recreate-worktree --reason`) — selection reports state,
    it does not repair it.
- Pipeline references: `pipeline.md §4 EXECUTE` for dispatch, `§5 GATES` for gate execution

### `--streamlined` mode

Streamlined mode (P040 Component D) trades per-step verification depth for an
integration-review checkpoint, suitable for low-risk EPICs (see the streamlined
trigger criteria in `/aid-plan`). When `--streamlined` is passed to `init`:

- **`cmd_init` writes `streamlined_mode: true`** into `fsm-state.yaml`. All
  downstream FSM checks read this field via `yq`.
- **`cmd_increment_step` skips per-step CP2** — the per-step
  `verifier-output-step-N.md` (CP2) precondition is bypassed. All other step
  preconditions (step-verify presence, `## Result: PASS`, AC checklist, commit
  ref, Memory Used/Written) and the Component B orphan-dispatch check still run
  in both modes.
- **`done-advance review → release` requires integration review only** — instead
  of accumulated per-step CP2 evidence, the transition refuses to advance unless
  all three integration-review files exist in the run's evidence dir:
  `verifier-output-cp3-code-review.md`, `verifier-output-cp3-security.md`, and
  `gates_report.json`. Missing any one hard-fails with `streamlined_integration_review`.
- **CP4 validation is advisory** — when the §7 curator/auditor auto-fix touched
  production code, full mode hard-fails without `verifier-output-cp4-curator-validation.md`;
  streamlined mode emits a `cp4_skipped_streamlined_advisory` audit event and
  proceeds.
- **Abandoned check fires on `< 3` timeline events** — a streamlined run whose
  `timeline.jsonl` has fewer than 3 events (init + transition to EXECUTE + at
  least one step/phase event) is treated as claimed-but-never-executed and
  hard-fails with `streamlined_abandoned` (NR 12 SOUSTO P009 anchor).
- **`compliance.json` emits `coverage_mode: "streamlined"`** plus
  `skipped_dimensions: ["verifier_outputs.cp2_per_step", "verifier_outputs.cp4_curator_validation"]`
  so the cross-EPIC aggregator distinguishes a legitimate streamlined run from a
  full run that is missing that evidence. Full mode emits
  `coverage_mode: "full"` and an empty `skipped_dimensions` array.

Both streamlined checks are PM-overridable via
`done-advance review release <state_file> --force --reason '<≥20 chars>' --blocked-checks 'streamlined_integration_review'`
(or `streamlined_abandoned`), which writes an audited override entry.


**Last Updated:** 2026-08-09
