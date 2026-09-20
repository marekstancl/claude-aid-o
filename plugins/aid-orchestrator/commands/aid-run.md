---
name: aid-run
description: Execute EPIC pipeline — 6-state FSM with optional autonomous mode
user_invocable: true
---

Run the 6-state FSM controller to orchestrate an EPIC through its full lifecycle. Replaces the old `/aid-run-epic` and `/aid-first-aid` commands.


## A plan that predates the autonomy flag

`plan-start` stamps a plan-level `autonomy` field (P090). A plan STARTED BEFORE
that carries none, and continuation then falls back to the project's own
`autonomous_mode` and says so on every merge. That fallback is a safety net, not
a state to live in: stamp the plan once, and it stops guessing.

```bash
bash {plugin_path}/scripts/aid-plan-fsm.sh plan-state <plan_id> --set-autonomy auto|manual
```

Stamp it when you first touch such a plan — the line the merge prints names the
command. `auto` is right when the project runs this plan unattended; `manual`
when a human drives it. Until 2026-08-28 the absent field read as `manual`
outright, so a project with `autonomous_mode: true` stopped after every EPIC
and nothing said why.

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
- **M-effort decisions** → take the default the recovery policy already declares for the stop's
  class, in the plugin's `defaults/policies/auto-recovery.yaml` (a project MAY override it with
  its own `config/policies/auto-recovery.yaml`, which no `/aid-init` creates and most projects
  never have). That file is the defaults authority: it names the stop
  classes, the reversible actions each one may take, and its budget. An earlier version of this
  line pointed at `config/permissions.yaml`, which has never held any such key — the tier rule was
  real, its mechanical backing was not
- **Recoverable technical decisions** (retry, repair, stale evidence, process failure,
  test selection) → dispatch the configured Codex adjudicator, record its decision in
  `timeline.jsonl`, then continue. Do not ask the PM to choose between technical A/B/C options.
- **PM-authority decisions only** (product intent, material scope expansion, destructive or
  externally visible action, security risk acceptance, secret/credential access) → pause for PM.
- Gate retries → auto-retry up to configured max (default: 2)
- Version bump on intermediate phase → auto-defer (bump only on final phase)

**The first action of `--auto`, before anything else:**

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" auto-mode set auto --by "aid-run --auto"
```

It writes `.aid-o/work/auto-mode-state.yaml`, which every later decision point
reads through `aid_autonomous_mode`. Until P095 no script wrote that file, so a
run that announced itself as AUTO was read back as manual at every checkpoint.
If the command fails, stop: a run that cannot record its own mode is not an
AUTO run.

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
| `blocked_for_pm` | yes | The run stopped at a PM-authority decision and is waiting for a person. | `aid_ladder_escalate` (`lib/aid-recovery-ladder.sh`), through the single map writer, when a class's terminus reaches escalation. |
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
   `STALLED?` marker plus the recovery line. `/aid-status` does report
   `ctl=awaiting_host_resume` for a run — but it COMPUTES that word from both facts at render time
   and writes nothing back: the map's sha256 is unchanged across a render, and with either fact
   missing the row falls back to the RECORDED value (or to `liveness?` when the derivation cannot
   run at all). So the word names two facts holding together, never a value anything stored or
   emitted as a verdict.

**The resume flow.** When both hold, run `bash {plugin_path}/scripts/aid-fsm.sh resume <epic_id>`.
It claims the artifact exactly once, collects the referenced job's terminal result, records it as a
durable gate-row checkpoint under `<evidence_dir>/gates_rows/<gate>.json` (`resume` never edits a
final report; the next `run-all` re-attaches to that same supervised job and *collects* its terminal
result rather than re-running the suite, deriving an identical row and overwriting the checkpoint —
the checkpoint is the durable record, not the delivery route), updates the active-runs entry, and prints
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
     checkpoint, updates the active-runs entry, and prints what it
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

Do not hand-roll that dispatch. Source `scripts/lib/aid-recovery-adjudicate.sh` and call
`aid_recovery_adjudicate <run_evidence_dir> <stop_class> <facts_file>`. It builds the prompt pack
(verified facts, current FSM state, the ladder record so far, the class's `allowed_actions` from
`defaults/policies/auto-recovery.yaml` as an explicit allowlist, and the forbidden
authority-expanding actions), dispatches through the same isolated Codex transport the C3 bridge
uses, accepts only a reply naming exactly one action from that allowlist plus a rationale, retries
once with the rejection quoted, and records every exchange to `timeline.jsonl`, the ladder record and
a per-exchange audit artifact. It prints the selected action, or `escalate` — which is not an action
and must never be executed as one. The full convention, the fail-closed paths and the authority
ceiling are specified in that file's header.

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
7. **Do NOT edit fsm-state.yaml directly** — all mutations go through `aid-fsm.sh` commands (`transition`, `increment-step`, `set-field`). Every `set-field` leaves a `field_set` line in the run's `timeline.jsonl` wherever one can be derived, and the four fields that are transition preconditions (`total_steps`, `current_step`, `plan_json_hash`, `base_commit`) need `--reason "<20+ chars>"` and a resolvable timeline, or the command refuses
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
15. **Wave dispatch is decided by code** — before a wave, `aid_parallel_decide` (`lib/aid-parallel-dispatch.sh`) says `concurrent` or `serial: <reason>`; only `concurrent` may dispatch several agents at once, each in its own step worktree, and never more than `orchestration.yaml → dispatch.max_parallel`. Returns are still taken ONE at a time: validate the contract return, commit, write step-verify, merge, increment-step (`pipeline.md §4` "Parallel groups").
16c. **A regenerated plan is accepted through `rebase-plan`, never by hand** — when `increment-step` reports "plan.json hash mismatch" after the PM regenerated the plan, run `bash {plugin_path}/scripts/aid-fsm.sh rebase-plan <state_file> --reason "<why, 20+ chars>"`. It accepts only when the step in flight and every done step are unchanged (future steps may change), re-stamps the hash and records the rebase. Never `set-field plan_json_hash`; re-init is the last resort (it rewrites `base_commit`).
16b. **Scope grows through `amend-scope`, never by hand** — when a step needs a file its `allowed_paths` do not list, run `bash {plugin_path}/scripts/aid-fsm.sh amend-scope <state_file> --add <path> [--add ...] --reason "<why, 20+ chars>"` and re-dispatch. It widens `plan.json` for the current step, re-stamps `plan_json_hash`, writes `steps/<id>/scope-amendment.json` and a timeline event — so the commit hook, `increment-step` and the contract validator all accept the file. A missing test file beside an in-scope source is routine (no PM ask); new production files are a PM decision (rule 11 of `skills/pipeline.md` escalations).
16a. **AID's own defects go to `.aid-o/work/aid-plugin-issues.md`** (date → plugin version → what happened → what it caused → what you did), never to the project backlog — see `skills/agent-protocol.md` §"Problems with AID itself". The file exists from the first run (created at plan-start / init, rules in its header). This includes anything you had to `--force` past and every `amend-scope`, and plugin defects Codex reports (you write those — Codex is read-only). The Stop hook reminds once per session when AID refused or was bypassed and nothing was written.
16. **Per-step commit** — the controller commits each accepted return (`aid_dispatch_contract_commit`) BEFORE calling `increment-step`. One commit per step, never a bulk commit at the end — also when steps ran concurrently.

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

8. `{plugin_path}/scripts/aid-queue-add.sh` — put every generated EPIC in the
   queue. **This step is not optional and nothing later creates the entries for
   you:** a plan whose EPICs never reached the queue merges its first EPIC and
   then stalls, because `epic-merge-to-plan` finds nothing to continue with, and
   the failure surfaces as a queue inconsistency far from its cause (ACTA P020,
   2026-08-31 — reported as a merge defect and it was this).

**Before you commit anything, be on the branch you mean to commit to.** The
pipeline leaves the plan worktree on `plan/<id>` after each init (step 7), so a
step's commit belongs on that step's `task/<epic>/main` and getting there is the
caller's job — no script switches for you at commit time. This is written here
because agents were told they had got it wrong without ever having been told the
rule (ACTA, 2026-08-31).

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

## Step review (CP2) and EPIC review (CP3)

Every step is reviewed before it is closed, and every EPIC before it goes to
GATES, by ONE mechanism (P094): a deterministic step check, then a round of
independent reviewers (`skills/step-review-roles.md`) whose answers the
adjudicator turns into one merged list. The FSM reads the round index and
nothing else: `increment-step` refuses without `cp2/step-N/rounds.json` at
HEAD, `EXECUTE→GATES` without `cp3/rounds.json`, and GATES→DONE / done-advance
refuse a cp3 round behind HEAD (the D4 test-churn exception with the
`CP3-Freshness-Exception:` trailer excepted). A hand-written skip is refused
too: the index has to come from the step check's own timeline event.

**When.** cp2: after `step-N-verify.md` is written and the step's commit is on
the branch, before `increment-step`. cp3: after the last step, before
`transition EXECUTE GATES`. Skip only when `review_checkpoints.enabled` or the
checkpoint's key is `false` (`prepare` then exits 3; the FSM passes with an
audit line).

1. The step check (deterministic, no model). It writes `<cp dir>/step-check.json`
   and, for `skip` or `no_change`, the round index itself — nothing to dispatch:
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp2 --step <N> --evidence-dir <run dir>
   bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp3 --evidence-dir <run dir>
   ```
2. For `review` or `review+security`, prepare the round. It prints one prompt
   per expected role and its dispatch focus (`cp2-step-N-<role>`, `cp3-<role>`):
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" prepare <review> --round 1
   ```
   `<review>` is `--checkpoint cp2 --evidence-dir <run dir> --step <N>` for a
   step, `--checkpoint cp3 --evidence-dir <run dir>` for an EPIC.
3. Dispatch every reviewer, then `collect` and `close`, exactly as the
   controller instruction quoted below says (codex roles: `aid-review-round.sh
   dispatch <review> --round K --provider codex --role <role>`; an absent codex
   is `provider_absent` and the round closes degraded, never faked).
4. `close` prints the verdict. `pass` → `increment-step` / `transition`.
   `fail` with a round left (`rounds_default`, 2) → the step's own role fixes
   (the `fix_of:` dispatch in the instruction below), a new step check, then
   `prepare --round 2`: the confirmation round asks only the reporters of what
   stayed open. `fail` after the last round → the PM card.
5. The PM card after an exhausted round is the **Decision required** card of
   `skills/communication.md` (built with `scripts/lib/aid-decision-card.sh`):
   what stayed open (from `merged.json`, blockers first), and the options —
   fix and confirm in a PM-granted round, or accept. `close` has already
   routed the open findings (`routed`) or carried them (`carried`), so nothing
   is lost whichever the PM picks. A third round, or only one, exists only as
   the PM's recorded words:
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" override <review> --rounds 3 --reason "<the PM's words, ≥20 chars>"
   ```
   The override records the PM's words, the head sha and the time; it never
   changes a verdict.

<!-- adapter:begin -->
# Claude reviewers of a review round — controller instruction

The Agent tool is not callable from bash, so the controller dispatches every
reviewer whose provider is `claude`, at every checkpoint: the plan review
(`commands/aid-plan.md` "Plan review (CP1)") and the step, EPIC and fast-mode
reviews (`commands/aid-run.md` "Step review (CP2) and EPIC review (CP3)",
`commands/aid-do.md`) include this text verbatim. `<round dir>` is the
directory `prepare` printed, and `prepare` prints each role's `<focus>` next
to its prompt: `cp1-<role>` for a plan, `cp2-step-<N>-<role>` for a step,
`cp3-<role>` for an EPIC, `cp6-<role>` in fast mode, `cp7-<role>` at plan
close, the role with `_` replaced by `-` (the dispatch wrapper allows no
underscore in `--focus` or `--agent-id`).

For EACH expected role with `provider: claude` in `<round dir>/round.json`,
one at a time:

1. Open the dispatch:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus <focus> \
     --agent-id aid-orchestrator:review --evidence-dir <round dir>
   ```

2. Dispatch the reviewer with this one-line prompt, never the file's content
   (a packet runs to hundreds of kilobytes; pasted copies would fill the
   controller's own context):

   ```
   Agent(subagent_type: "general-purpose", model: <the role's model from the checkpoint's reviewer block>,
         prompt: "Your complete instructions are in <round dir>/prompt-<role>.md. Read that whole file first and follow it exactly.")
   ```

   The reviewer writes `<round dir>/reviewer-<role>.json` itself. Note the
   `subagent_tokens` figure the Agent result reports; when the result shows
   none, the value is `unknown`.

3. Close the dispatch. `<answer>` is `<round dir>/reviewer-<role>.json`; when
   the reviewer wrote no file, create the empty marker
   `<round dir>/reviewer-<role>.missing` and use that path instead:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus <focus> \
     --output-file <answer> --evidence-dir <round dir>
   ```

   A step round's `close` refuses a reviewer file with no such start/complete
   bracket in `<round dir>/timeline.jsonl` (`no_dispatch_record`): a file
   nobody dispatched does not close a round. Only a round prepared with
   `--stub` by the acceptance suite skips that check, and the FSM refuses to
   advance on such a round.

## Stand-in for a Codex role

When `dispatch --provider codex` prints a line starting `STAND-IN:`, no codex
could be reached (absent, outdated, or over its usage limit) and the round
records `fallback: "claude"` for that role. Dispatch it exactly as above — the
same prompt file, the same start/complete bracket — at the model the STAND-IN
line names (`stand_in_model` of the checkpoint's block), and tell the reviewer
to write `"provider": "claude"` in its answer. `collect` accepts a claude answer
for a codex role ONLY with that record, and counts a stand-in nobody dispatched
as missing, which makes the round invalid. Pass its token figure to `close` like
any claude role. The PM card names the stand-in and the reason in one line; the
PM is told, not asked.

After ALL reviewers of the round (claude and codex) have been dispatched, run
`collect`. Only when `collect` exits 0, run `close` once with a token value for
every claude role; when it reports the round invalid, retry the roles it names
first (`close` refuses an invalid round). `<review>` is `--plan <plan>` for
CP1, `--checkpoint cp2 --evidence-dir <run dir> --step <N>` for a step,
`--checkpoint cp3 --evidence-dir <run dir>` for an EPIC:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" collect <review> --round K
bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" close <review> --round K \
  --tokens <role>=<n|unknown> ...
```

When `close` reports `fail` on a step or EPIC round and a round remains
(`rounds_default`, or the PM's `override`), the fix is the step's own role's:

```
Agent(subagent_type: "aid-orchestrator:implementer", model: <the model of the step's role card in skills/role-cards.md>,
      prompt: "fix_of: <round dir>; role: <the step's role card name>. Read <round dir>/merged.json, fix every finding with status open (blocker and major first), commit with the message prefix fix(review):, and report the finding fingerprints you addressed. Touch nothing a finding does not name.")
```

Then `aid-step-check.sh` again (the range now ends at the fix commit) and
`prepare --round K+1`: the confirmation round asks only the reporters of what
stayed open and shows them the open findings and the fix diff. Record the
fixer's model and tokens on the next `close` with
`--fixer <role>=<model>:<tokens_in>:<tokens_out>`.

When `close` reports `fail` on the LAST allowed round, it has already written
what stays open where the plan-final boundary reads it: a blocker or major a
later step's declared files cover becomes a carried obligation
(`carried` in merged.json); any other, and every one at cp3, is routed to the
EPIC (`routed`) and done-advance refuses until the PM resolves or backlogs it
(`skills/pipeline.md` §13). Say so on the PM card; do not route by hand what
`close` routed.

Never edit a reviewer's file, never write one on a reviewer's behalf, and never
dispatch a role twice: a role `collect` lists as invalid or missing goes
through `retry`, then this procedure for that role alone.
<!-- adapter:end -->

### State: READY

**Entry:** PRE-FLIGHT completed, `fsm-state.yaml` initialized.

**Actions:**
1. Load `execution.yaml` (gate definitions, step config)
2. Load `config/permissions.yaml` (`autonomous_mode` — the one key this file holds for the run;
   the per-class recovery defaults live in the plugin's `defaults/policies/auto-recovery.yaml`,
   which a project may override — but need not, and no installer creates — by placing its own
   `config/policies/auto-recovery.yaml`)
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
3. Dispatch the step — or the wave, when `aid_parallel_decide` says `concurrent` (rule 15):
   - Serial: work happens on the EPIC branch `task/{epic_id}/main` (created by `aid-fsm.sh init`).
     Concurrent: each step in `.aid-worktrees/step-<step_id>` on `step/<step_id>`, merged back one at a time.
   - Build the dispatch contract + agent prompt (per `pipeline.md §4`)
   - Dispatch agent via Task tool
   - Collect output → save to `work/evidence/{epic_id}/{run_id}/steps/{step_id}/`; validate the `aid-return` block
4. Verify outputs: present? scope respected? acceptance criteria met?
5. **Step review (CP2)** — the section "Step review (CP2) and EPIC review (CP3)"
   above: step check, round, `close`; `increment-step` refuses without the
   step's round index at HEAD
6. Log to `timeline.jsonl`

**EPIC review (CP3):** when all steps are done, before transitioning to GATES —
the same section, `--checkpoint cp3`.

**Transition:**
- All steps done + cp3 round `pass` → GATES
- cp3 round `fail` after the last allowed round → the PM card (fix in a PM-granted round, or accept); never a silent advance
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

**Gate-boundary message (deterministic, both manual and auto mode).** When the gate runner
returns — at the GATES→DONE boundary and equally on the failing branch — do NOT write a gate
summary of your own. Source `scripts/lib/aid-gate-outcome-summary.sh` and run:

```bash
aid_gate_outcome_render "<the --report-file path you passed the runner>" "<evidence_dir>" "<evidence_dir>/waivers"
```

Pass the runner's own `--report-file` path explicitly — it is the preferred wiring; the
renderer only falls back to `<evidence_dir>/gates/gates_report.json` and then the flat
`<evidence_dir>/gates_report.json`. It writes `<evidence_dir>/gate-outcome-artifact.html` and
prints the card (Finished, or Blocked when `overall: fail`) with a final `Artifact: <path>` line.

Publish the artifact body via the Artifact tool, then present the chat card verbatim.

Card shapes, the ordering rule and the language rule are defined once in `skills/communication.md`
— do not restate or re-word them here.

**If the renderer exits non-zero** (missing or invalid report): say so, and present a Blocked
card built from BOUNDED COMPUTED FACTS only — gate names, results, exit codes, counts. Never
skip the boundary message, and never hand-write it from raw gate output: any raw-derived text
must first pass through `aid_gate_outcome_redact` from the same library, which applies the same
deterministic redactor the artifact body uses. No path from gate output to the PM skips redaction.

**Transition:**
- All gates pass → DONE
- Gate fails + retries remaining → EXECUTE (dispatch gate-fixer, retry gate)
- Gate fails + retries exhausted → ESCALATION

### State: ESCALATION

**Trigger:** Gate failure after max retries, agent error, scope violation, acceptance not met.

**Actions:**
1. Build escalation context (reason, attempts, per-type details)
2. In manual mode → present to PM using the ESCALATION composite defined in
   skills/pipeline.md §6, which builds it from cards 3 and 2 of
   skills/communication.md. Read it there and follow it; this surface
   deliberately carries the pointer and not a second skeleton, so a correction
   to the card cannot leave a stale copy behind here. The per-type context
   blocks that fill it are in the same section.

**Step rendering rule.** How a step number is rendered to a human, and which machine fields stay frozen, are defined by the Step rendering rule in skills/pipeline.md. Read it there and follow it; this surface deliberately carries the pointer and not the rule, so a correction to the definition cannot leave a stale copy behind here.

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

DONE uses two mechanically enforced sub-phases: `review` → `release`, managed by `done-advance`
(not `transition`). Detail: `pipeline.md §7`.

**Sub-phase: `review`** (auto-set on GATES→DONE)

1. Update `fsm-state.yaml`: `state: DONE`, `done_phase: review` (automatic)
2. Archive run file → `runs/archive/`
3. `work/active.md` refreshes automatically at the done-advance boundary (generated index of active streams — never hand-edit it; detail lives in `work/plan-state/`)
4. Generate `final_report.md`
5. Produce `review-profile.json` (`pipeline.md §7`, step 5)
6. **EPIC review (CP3)** — "Step review (CP2) and EPIC review (CP3)" above. A finding is fixed by
   the role that wrote the code and confirmed by the next round.
7. **PM Summary** (see `pipeline.md` §7 for the full template):
    ```
    DONE REVIEW — {epic_id}
    {outcome in one plain sentence: what this EPIC now does for the PM}
    Changed: {1-3 user-relevant effects}
    Verified: {pass}/{total} gates pass; EPIC review {verdict}
             {or the concrete reason something is unverified}
    Next step: {the one recommended option below, with its one-line reason}

    Detail — steps {done}/{total} | gates {pass}/{total} | duration {time}
      EPIC review: {blockers open} blockers, {majors open} majors — cp3/rounds.json
    Key outputs: {artifact list}
    Evidence: .aid-o/work/evidence/{id}/{run_id}/

    Options (`legacy_epic_release_mode`):
      MERGE — release + merge to main + queue pickup
      FIX   — provide guidance, re-run the review
      ABORT — stop EPIC, no merge

    Options (`plan_branch`):
      MERGE — merge this EPIC into the PLAN branch; no release, no tag, no push.
              The release happens once, later, when the plan is closed.
      FIX   — provide guidance, re-run the review
      ABORT — stop EPIC, no merge
    ```
    This is the **Finished** card of `skills/communication.md` applied to DONE:
    outcome sentence first, then what changed, what is verified and the one
    recommended next step; counters, report paths and evidence dirs belong to
    the `Detail —` line and below it, never above it. If the review ends in a
    blocker the PM must resolve, render the **Blocked or failed** card instead
    and keep the same ordering.
8. **PM decides:** MERGE → step 9 | FIX → re-run steps 5-7 | ABORT → ERROR (E8)
9. **Advance sub-phase:** PM chose MERGE →
    ```
    bash {plugin_path}/scripts/aid-fsm.sh set-field pm_decision merge <state_file>
    bash {plugin_path}/scripts/aid-fsm.sh done-advance review release <state_file>
    ```
    Enforced in both modes: `pm_decision=merge`, the archived-task-file check, routed
    findings, the streamlined integration review, the abandoned check and tiered compliance.
    `legacy_epic_release_mode` adds the **cp3 head re-check** and the release decision; a
    `plan_branch` EPIC skips those two (its release is decided when the plan is closed), but
    never CP3 itself — under `--streamlined` its closed passing index (`cp3/rounds.json`)
    remains a hard precondition of `done-advance`.

**Sub-phase: `release`** (after `done-advance review release`)

Steps 14-16 fork on the plan's declared release mode
(`.aid-lifecycle/manifests/{plan_id}.yaml` → `mode`). Full instructions in
`pipeline.md §7` — "Sub-phase: `release`".

*In `plan_branch` mode (an intermediate EPIC inside an open plan):*

14. No release automation — no `aid-release.sh`, no version bump, no tag, no push
15. `aid-plan-fsm.sh epic-complete`, then `aid-plan-fsm.sh epic-merge-to-plan` — only
    `plan/{plan_id}` moves; the target branch is never touched, and
    `plan-record-delivery` is deferred to `plan-merge-to-main` (P068)
16. Queue — **there is nothing to do here in an autonomous plan.** Since P090 the whole
    sequence (proof → mirror → ask → claim → start) is `scripts/aid-plan-continue.sh`,
    and `epic-merge-to-plan` calls it itself after a successful merge whenever the plan's
    `autonomy` field says `auto`. Its output is part of what step 15 printed.
    In a MANUAL plan, or to re-run after a failure, invoke it yourself:
    `aid-plan-continue.sh {plan_id} {epic_id}` — exit 0 the plan moved on or ended
    cleanly, 1 a named failure, 2 usage, 3 transient (retry; never read as an end).
    `--no-continue` on `epic-merge-to-plan` turns the automatic call off.
    **Why the mirror inside it is never skipped:** `epic-merge-to-plan` leaves the entry
    at `running`, and a dependent whose dependency has no `merge_target` is resolved from
    that status — so without `merged_to_plan` the next EPIC is recorded
    `blocked:…:dependency_unmerged` and the plan stalls at EPIC 2.
    **This paragraph describes the behaviour; it does not create it** — the guarantee is
    in the script and in `test-plan-continue.bats`, which is the entire point of P090.
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

## Closing a plan (plan-final)

When every EPIC of a `plan_branch` plan is `merged_to_plan`, abandoned with a
reason, or superseded, the plan is closed ONCE, as a whole, in four stages and
one review round. Every stage is bound to one frozen candidate, records what it
wrote, and ends its output with `next:` or names what it refuses and what to
run instead. Follow what the tool prints; this section is the map.

`<fsm>` is `bash "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"`, `<round>` is
`bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh"`. Stay in the plan's
worktree (`.aid-worktrees/plan-<id>`) on `plan/<id>` for the whole close.

| # | Command | What it does | It refuses when |
|---|---------|--------------|-----------------|
| 0 | `bash "$AID_PLUGIN_PATH/scripts/aid-release.sh" prepare-plan <plan> --bump auto --plan-branch plan/<plan>` | the version commit, BEFORE the freeze, so the candidate already contains the release metadata | the tree is dirty; HEAD is not the plan branch |
| 1 | `<fsm> plan-finalize <plan> --stage freeze` | merges the target branch into `plan/<plan>`, freezes the candidate, mints `R-<plan>-final-<N>` | an EPIC is not terminal; the merge conflicts (exit 4, state CONFLICT); the tree is dirty |
| 2 | `<fsm> plan-finalize <plan> --stage gates` | the plan-final gate run; a gate that passed in the previous attempt and whose `inputs:` did not change is copied (`reused_from`), not executed | a gate fails (the report names it); the branch moved off the candidate |
| 3 | `<fsm> plan-finalize <plan> --stage produce` | review profile, plan-diff, acceptance evidence, and what the round reads (`cp7/`) | gates have not passed; the candidate moved |
| 4 | `<round> prepare\|collect\|close --checkpoint cp7 --evidence-dir <run dir> --project-root <plan worktree> --round 1` | the whole-plan review: `final_criteria`, `final_claims`, `final_generalist` | `produce` has not run; HEAD is not the candidate; a reviewer file has no dispatch bracket |
| 5 | `<fsm> plan-finalize <plan> --stage decide` | the one aggregate: `release-decision.json`, the sealed receipt, the PM page with attempts, minutes and USD | the round is not closed; a decision input was edited by hand (named); the candidate moved |

**The round (row 4)** is dispatched exactly as a step or EPIC round: the
procedure, the prompt files, the dispatch bracket (`aid-emit-dispatch.sh start` …
`complete`, focus `cp7-<role>`), the Codex role and its stand-in are the ones in
"Step review (CP2) and EPIC review (CP3)" and "Stand-in for a Codex role" above.
`prepare` prints one prompt per role it asks; a role it lists as *carried* is not
dispatched. `produce` prints the exact `prepare` command with the run directory.
A plan has one round per attempt: a fix moves the candidate, so its confirmation
is round 1 of the next attempt.

**When something is open.** `close` reports `fail`, or `decide` prints
`NOT READY` with the blockers:

1. The role that wrote the code fixes it, on the plan branch:
   ```
   Agent(subagent_type: "aid-orchestrator:implementer", model: <the model of that role's card in skills/role-cards.md>,
         prompt: "fix_of: <run dir>/cp7/round-1; role: <the role of the step that owns the file; backend when no step owns it>. Read merged.json, fix every finding with status open (blocker and major first), commit with the message prefix fix(review):, and report the fingerprints you addressed. Touch nothing a finding does not name.")
   ```
   The owning step is the one whose declared files cover the path (`plan.json` of the EPIC whose commit last touched it: `git log -1 -- <path>`).
2. `--stage freeze` again. It mints the next attempt and writes `fix-class.json`:
   what the fix touched decides what is read again. A change to CHANGELOG, README
   or docs re-asks `final_claims`; an edit of the plan's criteria re-asks
   `final_criteria`; code re-asks everyone; a role whose inputs were not touched
   and which had no finding is carried. The round's packet shows the re-asked
   reviewers what stayed open and the fix diff.
3. `gates` (unchanged gates are copied), `produce`, the round, `decide`.

An ancillary-only move after the freeze (AID's own bookkeeping, e.g. the id
counter) costs nothing: `freeze` names `--stage freeze --accept-ancillary`, which
writes the equivalence receipt and keeps the gates, the round and the decision.

**When to go to the PM, and with which card** (`skills/communication.md`). Try the
fix path once first; escalate when it does not apply or did not help.

| Refusal | Try once | Then show the PM |
|---------|----------|------------------|
| a gate is red and the failure is real | the fix path above | **Blocked** card: the gate, what it printed, the smallest fix |
| a cp7 blocker is still open after a fixed attempt | one more fix when the finding changed; else stop | **Decision** card: FIX (what it costs) / accept with a recorded dispute / ABORT |
| the project disputes a finding | `<round> dispute` is CP1-only: do not edit the finding | **Decision** card quoting the finding and its evidence |
| the branch was rewritten (`fix-class.json` reason `rewritten_branch`) | nothing is carried; run the full attempt | none, unless it repeats: then **Blocked** |
| `verification_report` blocks | read its `git_clean` evidence: commit or discard the named tracked file | **Blocked** card naming the file |
| `final_review_disabled` | switch `cp7_plan_final_review` back on | **Decision** card; only the PM's words go into `--stage decide --waive-final-review --reason "<words>"`, and the page then says the plan was NOT read as a whole |

**At the end.** `decide` prints `READY` and the plan is `AWAITING_PM`. Render the
page and the card from the two files it wrote, publish the page with the
Artifact tool and present the card verbatim (`commands/aid-plan.md`, "Plan-final
/ close boundary"); state no number yourself. MERGE runs
`<fsm> plan-merge-to-main <plan> --decision <file>`; FIX is the fix path; ABORT is
`plan-abort` with the PM's reason.

`legacy_epic_release_mode` has no plan close: each EPIC releases at its own DONE,
and the whole-delivery review the decision reads there is the EPIC's own cp3 round.

## Reference Files

- `skills/pipeline.md` — §4 EXECUTE dispatch protocol, §5 GATES protocol
- `scripts/lib/aid-review-adapter-claude.md` — the controller instruction quoted in "Step review (CP2) and EPIC review (CP3)"; `skills/step-review-roles.md` — the reviewer roles of cp2/cp3/cp6
- `scripts/aid-fsm.sh` — FSM transition validation
- `scripts/aid-run-gates.sh` — gate execution
- `scripts/lib/aid-stage-log.sh` — timeline.jsonl logging
- `config/execution.yaml` — gate definitions (lazy-created on first run)
- `config/permissions.yaml` — `autonomous_mode` (read by `aid-release-policy.sh`)
- `defaults/policies/auto-recovery.yaml` (plugin) — AUTO-mode recovery policy: stop classes,
  allowed reversible actions, budgets, and the ownership table of the retry loops it does NOT
  govern. This is the file that ships and the file that applies; `config/policies/auto-recovery.yaml`
  in the project is an OPTIONAL override that no `/aid-init` creates, and is used only when it
  exists and validates

## Important

- **Review Checkpoints** — CP2/CP3 are review rounds (the section above), CP7 the whole-plan round of "Closing a plan"; every checkpoint toggles in `config/policies/review-checkpoints.yaml`
- **Pre-merge review** — the EPIC review round (CP3), per EPIC in both modes; a `plan_branch` plan is read once more as a whole when it is closed (CP7). PM approves via MERGE/FIX/ABORT in both modes
- **Exhausted review round** — a cp2/cp3 round that fails after the last allowed round is a PM decision (fix in a granted round, or accept with the findings routed), not an escalation state
- **Escalation E8** — PM chose ABORT in the DONE summary
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
- **`cmd_increment_step` skips per-step CP2** — the step's review round
  (`cp2/step-N/rounds.json`) precondition is bypassed. All other step
  preconditions (step-verify presence, `## Result: PASS`, AC checklist, commit
  ref, Memory Used/Written) and the Component B orphan-dispatch check still run
  in both modes.
- **`done-advance review → release` requires integration review only** — instead
  of accumulated per-step cp2 evidence, the transition refuses to advance unless
  the EPIC review round closed with verdict `pass` (`cp3/rounds.json`) and
  `gates_report.json` exists. Missing either hard-fails with `streamlined_integration_review`.
- **Abandoned check fires on `< 3` timeline events** — a streamlined run whose
  `timeline.jsonl` has fewer than 3 events (init + transition to EXECUTE + at
  least one step/phase event) is treated as claimed-but-never-executed and
  hard-fails with `streamlined_abandoned` (NR 12 SOUSTO P009 anchor).
- **`compliance.json` emits `coverage_mode: "streamlined"`** plus
  `skipped_dimensions: ["verifier_outputs.cp2_rounds"]`
  so the cross-EPIC aggregator distinguishes a legitimate streamlined run from a
  full run that is missing that evidence. Full mode emits
  `coverage_mode: "full"` and an empty `skipped_dimensions` array.

Both streamlined checks are PM-overridable via
`done-advance review release <state_file> --force --reason '<≥20 chars>' --blocked-checks 'streamlined_integration_review'`
(or `streamlined_abandoned`), which writes an audited override entry.


**Last Updated:** 2026-09-20
