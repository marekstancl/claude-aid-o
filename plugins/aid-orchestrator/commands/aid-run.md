---
name: aid-run
description: Run a plan — one run on plan/<id> through the 6-state FSM, with optional autonomous mode
user_invocable: true
---

Run the 6-state FSM controller over a plan's one run, from its file to the close. Since 3.0.0 (P114) a plan runs straight from its file: there are no EPIC files, no queue and no task branches; an EPIC id given to `/aid-run` and a plan generated the old way are refused `epic_path_removed` with the way out (finish such a run on 2.118.x, or close its plan and start a new one).


## Usage

```
/aid-run P<NNN>                 # start (or resume) the plan's run straight from its file (plan-run)
/aid-run --auto P<NNN>          # the same, autonomous
/aid-run                        # manual mode — continue the active run (active-runs.json)
/aid-run --resume               # resume an interrupted run from fsm-state.yaml
```

## Flags

| Flag | Behavior |
|------|----------|
| (none) | Manual mode — asks PM approval at each escalation |
| `--auto` | Autonomous mode (replaces `/aid-first-aid`) |
| `--resume` | Resume from last known state in `fsm-state.yaml` |

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
- **The PM says "don't ask, finish it"** (any wording of it): record it ONCE for the plan —
  `bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" standing --checkpoint cp2 --evidence-dir <run dir> --reason "<the PM's words>"`.
  Every step review of the plan may then run up to two fix-and-confirm rounds after its
  budget (fix the finding, `prepare` the next round) before anything is routed to the PM; a round
  that re-opens the same findings still stops. Never record it on your own judgment.
- **"AID: this session runs plugin X, but Y is installed"** in context: run `/reload-plugins`
  before dispatching any agent — the old agent cards lack the newer rules (P103).
- **"no verdict" from Claude Code's permission check** (the auto-mode classifier failed, the
  command did not run) is transient and not a PM decision: wait about a minute and run the SAME
  command again, up to 5 times, before a Blocked card; say so in one line (P103, 28. 9. 2026).
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

**And the last action of `--auto`** — the plan is closed, or the run stops at a
PM-authority decision it cannot pass:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" auto-mode set manual --by "aid-run --auto (finished)"
```

The state file is project-wide and outlives the run: left at `auto`, the next plain `/aid-run` would
be read as autonomous at every decision point and stamped `auto_controller: active`.

**Then bind this session to the plan and make sure the hook layer is in force**
(P099: the Stop hook keeps only the bound session working, and its refusals
count only while a canary verdict is fresh):

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh" plan-state <plan_id> --bind-session "$CLAUDE_CODE_SESSION_ID"
bash "$AID_PLUGIN_PATH/scripts/aid-hook-verify.sh" --status >/dev/null 2>&1 \
  || bash "$AID_PLUGIN_PATH/scripts/aid-hook-verify.sh" --canary
```

A canary that fails leaves the layer degraded; say so in one line and go on.
After `/clear` or in a new session, `/aid-run --auto` binds again.

**What ends an AUTO turn, and nothing else does.** The Stop hook refuses a turn
of the bound session that ends with work left, up to
`autonomy.continuation_budget` times (`orchestration.yaml`, 40) until the PM
answers. A turn may end with:
- a Decision card or a Blocked card (`skills/communication.md`) — the PM gets one
  "agent is waiting" message; the PM's "zastav se" is answered with a Blocked card;
- a last line `AID-WAIT: <what>` while a background gate job AID owns is live
  (`aid-job.sh`); the harness brings you back when it finishes;
- the budget spent, or an account limit — the PM gets the same one message.

Requires `autonomous_mode: true` in `.aid-o/config/permissions.yaml`.
If not set, `--auto` prints a warning and falls back to manual mode.

### What `--auto` records about itself — the four run states

Read this before starting an AUTO run — it is what you, or the next controller, reason from after
an interruption.

Every live run has an entry in `.aid-o/work/active-runs.json`, keyed by its id (`E-<nnn>-1_1`). The entry's `auto_controller` field
is stamped at `init`, the only site that writes an entry into the map (`upsert_active_run`). The
other lifecycle boundaries do not re-stamp it — the done-advance review→release edge, `plan-close`
and `active-runs prune` all REMOVE the entry instead. After `init`,
`aid-fsm.sh active-runs set <epic> auto_controller <value>` is the only single-field writer. Three
values are **storable**, and the fourth state is never stored at all.

| State | Stored? | What it means | Who sets it |
|-------|---------|---------------|-------------|
| `active` | yes | An autonomous controller is alive and owns this run. | `init`, when the run declared itself AUTO (`aid_auto_run_declared`: `AID_AUTO_MODE=1` or `auto-mode-state.yaml` says `auto`; `manual` there wins); re-asserted by `aid-run-gates.sh` after the run's last background job is collected, and by `aid-fsm.sh resume` — in both cases only for an AUTO run. |
| `manual` | yes | No autonomous controller — a human drives this run. The conservative default whenever the entry is not stamped AUTO. | `init`, when the run did not declare itself AUTO |
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
MUST keep ownership until the run completes, reaches a PM-authority decision, or encounters an
unrecoverable external outage. A recoverable technical problem is not a reason to end the turn.

- The controller is the sole owner of FSM mutations, commits, gates, evidence finalization, and
  long-running/background processes. Dispatched implementers and reviewers never own these.
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
  against the checkout a reviewer is reviewing.
- Codex adjudication and PM decisions are append-only audit events. The adjudicator may choose among
  already-authorized technical recovery paths; it cannot grant PM authority or waive security risk.

Do not hand-roll that dispatch. Source `scripts/lib/aid-recovery-adjudicate.sh` and call
`aid_recovery_adjudicate <run_evidence_dir> <stop_class> <facts_file>`. It builds the prompt pack
(verified facts, current FSM state, the ladder record so far, the class's `allowed_actions` from
`defaults/policies/auto-recovery.yaml` as an explicit allowlist, and the forbidden
authority-expanding actions), dispatches through the same isolated Codex transport the review rounds
use, accepts only a reply naming exactly one action from that allowlist plus a rationale, retries
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
14. **Per-plan C+A review** — after a plan's run, ALL C+A findings (S+M+L) must be addressed before starting next plan
15. **Wave dispatch is decided by code** — before a wave, `aid_parallel_decide` (`lib/aid-parallel-dispatch.sh`) says `concurrent` or `serial: <reason>`; only `concurrent` may dispatch several agents at once, each in its own step worktree, and never more than `orchestration.yaml → dispatch.max_parallel`. Returns are still taken ONE at a time: validate the contract return, commit, write step-verify, merge, increment-step (`pipeline.md §4` "Parallel groups").
16c. **A regenerated plan is accepted through `rebase-plan`, never by hand** — when `increment-step` reports "plan.json hash mismatch" after the PM regenerated the plan, run `bash {plugin_path}/scripts/aid-fsm.sh rebase-plan <state_file> --reason "<why, 20+ chars>"`. It accepts only when the step in flight and every done step are unchanged (future steps may change), re-stamps the hash and records the rebase. Never `set-field plan_json_hash`; re-init is the last resort (it rewrites `base_commit`).
16b. **Scope grows through `amend-scope`, never by hand** — when a step needs a file its `allowed_paths` do not list, run `bash {plugin_path}/scripts/aid-fsm.sh amend-scope <state_file> --add <path> [--add ...] --reason "<why, 20+ chars>"` and re-dispatch. It widens `plan.json` for the current step, re-stamps `plan_json_hash`, writes `steps/<id>/scope-amendment.json` and a timeline event — so the commit hook, `increment-step` and the contract validator all accept the file. A missing test file beside an in-scope source is routine (no PM ask); new production files are a PM decision (rule 11 of `skills/pipeline.md` escalations). After the last step it widens the last step and says which; another repository's file cannot be added this way — it must be in the step's `Files:` (`skills/pipeline.md` §Scope amendment). **A plan bound to a brief (P109):** the `--reason` names the `AC<n>` of the brief the widening serves — one the current step closes (`**Zavírá:**`), any step's during GATES — and the record carries it as `zadani_point`; a widening that serves none is refused (`amend_scope_no_brief_point`, `amend_scope_reason_names_no_point`) and is the PM's decision (rule 11) — in an `--auto` run the stand-in's (`--stand-in <auth.json>`, §Run decisions by the stand-in), unless the path is protected. The trace is for the step review and the close; it does not judge the content.
16a. **AID's own defects go to `.aid-o/work/aid-plugin-issues.md`** (date → plugin version → what happened → what it caused → what you did), never to the project backlog — see `skills/agent-protocol.md` §"Problems with AID itself". The file exists from the first run (created at plan-start / init, rules in its header). This includes anything you had to `--force` past and every `amend-scope`, and plugin defects Codex reports (you write those — Codex is read-only). The Stop hook reminds once per session when AID refused or was bypassed and nothing was written.
16. **Per-step commit** — the controller commits each accepted return (`aid_dispatch_contract_commit`) BEFORE calling `increment-step`. One commit per step, never a bulk commit at the end — also when steps ran concurrently.

16d. **Take a returned step over in the background (AID 3.11.0)** — instead of validating, committing, merging and running the step's tests in the foreground, start `bash {plugin_path}/scripts/aid-step-land.sh <state_file> <N> --check "<AC#>:<command>" … [--env NAME=value]` with Bash `run_in_background: true` and end the turn `AID-WAIT: převzetí kroku N`. Every acceptance criterion of the step whose text begins with a backticked command gets one `--check` with exactly that command (the project's test environment goes in `--env`). Meanwhile accept other returns (read-only), prepare and dispatch later steps, run review rounds. On the notification read `steps/<id>/land.json`: `landed` → write `step-N-verify.md` (command criteria cited from the record, the rest judged as before), the step check and CP2, then `increment-step`; anything else → decide as before (a conflict: `aid_parallel_step_reset` and dispatch again; a failed check: the step's role fixes it — in a wave on `step/<id>` and the same takeover again, on the serial path, where the step's commit already stands, as a commit on top and `--recheck`). After a review fixer committed: `aid-step-land.sh … --recheck` before `increment-step`, and rewrite the binding in `step-N-verify.md` (`reviewed_commit` = the new HEAD). `<N>` is `current_step` — 0-based, the plan's step N+1. A refusal "another takeover … is running" is the script's own output: the `land.json` there belongs to the takeover still running, do not read it as this one's result. The script never fixes anything; `increment-step` refuses a step whose record does not hold (`land_record_invalid`). Steps are taken over in order (`current_step`).

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
- The canonical call is `bash {plugin_path}/scripts/aid-fsm.sh advance-to-gates <state_file>`:
  it resolves the gate profile for the run's diff and runs the gates (skills/pipeline.md §5).
- Calling the runner directly is for debugging and crash recovery, and then names the profile
  (without `--profile` it runs every gate and says so):
  ```
  bash {plugin_path}/scripts/aid-run-gates.sh run-all <execution.yaml> <epic_id> <run_id> <timeline_file> \
    --state-file <state_file> --report-file <evidence_dir>/gates/gates_report.json --profile <name>
  ```
- `--state-file` ensures gates only run when FSM is in GATES state
- `--report-file` persists `gates_report.json` (required by `GATES→DONE` precondition)
- **`--profile <name>` (optional)** — `execution.yaml.gate_profiles` is an ordered list of
  named `include[]` sets, narrowest first; the runner runs exactly the named profile's
  `include[]` and gives every other gate a `status: skip, reason: not_in_profile` row (never
  silently dropped, never fails `overall`). Omitting `--profile` runs every defined gate. The
  runner never chooses: the CALLER names the profile, and the report records it (`profile`,
  `profile_source: caller|none`, `profile_table`). `aid-fsm.sh advance-to-gates` is that caller —
  it resolves the last declared profile whose `when_paths` matches the run's `base_commit..HEAD`
  diff, else `default_profile`, and passes the name. An unknown name, or a profile whose
  `include[]` names no `required: true` gate, is refused with exit 2 before any gate runs,
  naming the declared table and the upgrade command. See `pipeline.md §5`.
- **Two floors at `GATES→DONE`** — a gate named in `plan.json.gates[]` must not appear in
  `excluded_gates[]` (reason `plan_gate_profile_excluded`; a malformed `plan.json` is
  `plan_json_malformed`), and the recorded profile must be no narrower than the resolver's
  answer for the same diff on the same table (reasons `risk_profile_unresolvable`,
  `profile_table_changed`, `risk_profile_below_required`). Override via `--force --reason
  '<≥20 chars>'` like any other `GATES→DONE` precondition.

## PRE-FLIGHT (before FSM starts)

`/aid-run P<NNN>` starts the plan's one run (P111). One command does it all:
  `{plugin_path}/scripts/aid-plan-fsm.sh plan-run P<NNN> [--auto]`. It holds the
  generation lock and records its stages in the plan's one
  `generation/transaction.json` (`kind: plan_run`), so an interrupted start is
  resumed by running the same command: plan-start in plan_branch mode with the
  one run `E-<nnn>-1_1` declared → readiness → the CP1 seal → `plan.json` of the
  WHOLE plan (`lib/aid-plan-json.sh`; `direct: true`) → D5 → `epic_input.md` →
  the worktrees of the plan's `repo_roots` → the manifest entry (`direct: true`,
  no task branch) → the receipt check → `aid-fsm.sh init … plan/<id> … --direct`.
  It prints the state file; the run is one run of every step, on `plan/<id>`.
  It refuses a plan generated the old way (`epic_path_removed`: the EPIC path
  was removed in 3.0.0 — finish such a plan on 2.118.x, or close it and start a
  new plan) and a second start (`plan_run_already_started`). `--force --reason` passes a forceable CP1
  refusal (the PM's call): a refusal from the CP1 call is labelled
  `aid_generation_force_required:` when a deliberate PM `--force --reason` could
  proceed (the exact command is printed), `aid_cp1_blocked:` when it could not.
  An interrupted start is resumed by running the same command.

**Restarting a run that made no step (P112).** A run that stopped before its
first step (a plan that needed `repo_roots` after all, a plan fixed after its
CP1) starts again with ONE command:
`{plugin_path}/scripts/aid-plan-fsm.sh plan-run P<NNN> --restart --reason "<why, 20+ chars>"`.
It abandons the old run (`aid-fsm.sh abandon`), records the restart like
`supersede-generation` (a record, a timeline event, the audit-log line), moves
the run's evidence and its transaction into
`.aid-o/work/superseded-runs/<plan>-<UTC ts>/` (outside `evidence/`, so no hook
or status reader finds them) and runs `plan-run` again over the current plan
(seal and CP1 gate again; a foreign worktree is adopted and keeps its fork
point). Refused after any step (`restart_after_step` — resume the run, or close
the plan administratively), over uncommitted work or commits outside a step in
the plan's worktree (`restart_plan_dirty`) or a foreign worktree
(`restart_foreign_dirty`), and while a controller is still working on the run
(`restart_controller_live`). An interrupted restart resumes with the same
command (`restart.json`: moving → moved → done). Nothing is deleted.

**`repo_roots` — another repository is a worktree, never its live checkout
(direct run, P111).** A plan that changes files in another git repository
declares it in its frontmatter:
`repo_roots: [{name: docs, path: /opt/eco/docs, base_branch: main}]` (the lint
refuses a path that is not a git repository outside the project —
`repo_root_invalid`). `plan-run` creates — or on a rerun adopts — the worktree
`<path>/.aid-worktrees/plan-<id>--<name>` on the branch `plan/<id>-<project>`
(plan ids are per project) from the base branch's head, adds `.aid-worktrees/`
to that repository's `info/exclude`, and records the ONE mapping
`repo_roots[] = {name, path, worktree, branch, base}` in `plan.json`. In
EXECUTE the step's contract names the worktree path for every such file
(allowed paths and expected artifacts alike) and says "never in <path>"; the
agent commits there and its return names the repository by its name:
`repo_commits: [{repo: "docs", range: "<base>..<head>"}]`. The step check and
the return validator resolve the name through the same mapping and require the
range to be reachable from the worktree's branch — a commit made in the live
checkout (it shares the object store) is refused (`OTHER_MISSING: docs`). A
step naming a foreign repository the plan does not declare is refused
(`foreign_repo_undeclared`). At the close, `plan-finalize --stage freeze`
records each foreign branch's head; `produce` and `decide` refuse a missing
worktree, a branch that moved after freeze, or a reported range not on it
(`foreign_branch_unverified`); the decision, the PM card and the close page
list the foreign branches (name, branch, head, commits). **Merging them is the
PM's, by hand, after MERGE** — their gates are not run.

**Foreign repositories in review and measurement (P112).** Every reader of a
step's files or of a brief point reads the plan's worktree through ONE mapping
(`lib/aid-repo-roots.sh`), never the live checkout: the step review packet
carries `foreign-<name>.patch` with the ranges the step check verified
(`step-check.json` `other_repos`) and `files.json` with worktree paths; the
whole-plan packet carries each foreign branch from its frozen base; the prompt
names the worktree and forbids the live checkout. The measurer
(`aid-plan-diff.sh`, after a step and at the close) rewrites a point's `file:`
and every declared path in its `cmd` to the worktree, so the `plan_diff` gate
passes on what the plan built without merging the foreign branch first. A
missing worktree is `foreign_worktree_missing` (fail closed). The plan lint
refuses an absolute path into an undeclared repository before CP1
(`foreign_repo_undeclared`). A point that runs out of time is **unmeasured**
(`reason: timeout`, its limit), not absent: `increment-step` and the close name
it; re-measure a step with `AID_PLAN_DIFF_AC_TIMEOUT_FLOOR=<s>` (it raises even a
point's own `timeout:`, max 1800) — the plan is not edited mid-run; the next
plan gives the point `timeout:`.

**The pre-commit hook guards only the live run (P112).** The run that governs
a commit on a branch is taken ONLY from `.aid-o/work/active-runs.json` (the
entry whose state names that branch); a set-aside copy of a state never
governs. `init` fails without its map entry (`active_runs_write_failed`), the
map keeps a direct run until DONE/release, and an unreadable map refuses a
commit on `plan/*` or `task/*` (`active_runs_unreadable`).

**Plugin path verification:**
1. Read `plugin_path` from `.aid-o/config/plugin.yaml`
2. Verify: `test -f {plugin_path}/scripts/aid-fsm.sh`
3. If stale or missing → re-discover: `glob ~/.claude/plugins/**/aid-orchestrator/scripts/aid-fsm.sh` → update `plugin.yaml`
4. If still not found → abort with: "Plugin scripts not found. Run `/aid-init` to refresh."

**Before you commit anything, be on the branch you mean to commit to.** A step's
commit belongs on `plan/<id>`, in the plan's worktree (`aid_dispatch_contract_commit`
accepts that branch for the run whose `fsm-state.yaml` says `direct: true` and
names it); no script switches branches for you at commit time (ACTA, 2026-08-31).

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

## Step review (CP2)

Every step is reviewed before it is closed by ONE mechanism (P094): a
deterministic step check, then a round of independent reviewers
(`skills/step-review-roles.md`) whose answers the adjudicator turns into one
merged list. The FSM reads the round index and nothing else: `increment-step`
refuses without `cp2/step-N/rounds.json` at HEAD. A hand-written skip is
refused too: the index has to come from the step check's own timeline event.
The whole plan is read once more at the close (CP7, "Closing a plan" below);
the EPIC review (CP3) between them was removed in 3.0.0 (P114) — a project
file that still sets `cp3_integration_review` gets a legacy-key warning.

**When.** After `step-N-verify.md` is written and the step's commit is on
the branch, before `increment-step`. Skip only when `review_checkpoints.enabled` or the
checkpoint's key is `false` (`prepare` then exits 3; the FSM passes with an
audit line).

**What a step buys (P110, 2.116.0).** The verdict decides: `skip` (at most 3
files and 120 lines, inside the step's scope, no security pattern —
`step_review.skip_threshold`) has no reviewer; `review` asks `step_generalist`
and `step_security` as light reviewers; `review+security` asks `step_security`
as the full reviewer (`full_when`). `prepare` records the choice in
`round.json` `agents` and prints it next to each prompt; dispatch exactly that
agent type. A project keeps the old budget (two rounds, 1/50) in its own
`.aid-o/config/policies/review-checkpoints.yaml`.

1. The step check (deterministic, no model). It writes `<cp dir>/step-check.json`
   and, for `skip` or `no_change`, the round index itself — nothing to dispatch:
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp2 --step <N> --evidence-dir <run dir>
   ```
2. For `review` or `review+security`, prepare the round. It prints one prompt
   per expected role and its dispatch focus (`cp2-step-N-<role>`):
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" prepare <review> --round 1
   ```
   `<review>` is `--checkpoint cp2 --evidence-dir <run dir> --step <N>`.
3. Dispatch every reviewer, then `collect` and `close`, exactly as the
   controller instruction quoted below says (codex roles: `aid-review-round.sh
   dispatch <review> --round K --provider codex --role <role>`; a codex
   that gives no answer is replaced by the stand-in the quoted text describes).
4. `close` prints the verdict. `pass` → `increment-step`.
   `fail` (cp2 `rounds_default` is 1) → the step's own role fixes (the
   `fix_of:` dispatch in the instruction below), a new step check, then
   `prepare --round 2`: the confirmation round (`second_round_when:
   open_finding_and_fix` — round 1 left a blocker or major open and HEAD
   moved) asks only the reporters of what stayed open, and its prompt carries
   `fix.patch` and the open findings, not the whole step again. `fail` after
   that round → the PM card; a third round needs the PM's override or standing
   instruction (`prepare` refuses it otherwise).
   A step that moves after a `pass` (a later commit on the same step) is
   confirmed the same way — a new step check, then `prepare --round <n+1>`: a
   delta round over the commits since, asking every role. ONE delta round
   (round `rounds_default + 1`) needs no override; a later one meets the
   round budget like any other round.
   A finding the adjudicator could not accept on form (`form_invalid` in
   `merged.json`) is open like any other: fix it, or dispute it.
5. The PM card after an exhausted round is the **Decision required** card of
   `skills/communication.md` (built with `scripts/lib/aid-decision-card.sh`):
   what stayed open (from `merged.json`, blockers first), and the options —
   fix and confirm in a PM-granted round, or accept (with the PM's standing instruction
   recorded — `aid-review-round.sh standing` — two such rounds need no card). `close` has already
   routed the open findings (`routed`) or carried them (`carried`), so nothing
   is lost whichever the PM picks. A third round, or only one, exists only as
   the PM's recorded words:
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" override <review> --rounds 3 --reason "<the PM's words, ≥20 chars>"
   ```
   The override records the PM's words, the head sha and the time; it never
   changes a verdict.
6. A finding the step's role believes wrong (the plan's criterion is wrong,
   the claim is false) is disputed, never edited: `dispute <review> --round K
   --fingerprint <fp> --reason "<why>"` marks it `disputed` and it keeps
   blocking. Only the PM clears it: render a **Decision** card that quotes the
   finding's fingerprint — put every full fingerprint the answer settles in the card data's `quotes` list
   (`aid_decision_card_render` prints them on the card, so the PM's first answer is recorded; AID 3.12.0) — wait
   for the answer, then
   `dispute … --pm accepted --finding-card <card file> --reason "<the PM's words>"`
   — refused without a PM prompt in the hook audit after the card. The round's
   verdict is recomputed; `--pm rejected` leaves it open. The same command
   settles a whole-plan (cp7) finding — one the author refuted by measurement,
   one the PM deferred to the backlog, or one the adjudicator kept as
   `form_invalid` because its evidence lies outside the candidate's repository:
   `dispute --checkpoint cp7 --evidence-dir <final run> --round K …`. **AID 3.12.0:** a cp7 `--pm accepted` (and a
   technical delegate verdict that settles a finding) also goes to the plan's `evidence/<plan>/pm-decisions.jsonl`;
   every later cp7 round of the plan — this attempt or the next — settles the same thing with it on collect
   (`settled_by`; same `match`, or for a PM answer the same first `zadani.md:N` citation on a finding that is not a
   blocker and not more severe), the round's prompt lists the decisions, and `decide` refuses a settlement it cannot
   verify (`pm_decision_unverified`). Do not ask the PM again about a finding marked `settled_by`. The
   dispute records its writes as a stage (`cp7-dispute-accepted` in
   `stage-writes.jsonl`), so `plan-finalize --stage decide` reads it as the
   PM's decision, not as tampering. A plan is never merged by hand around an
   open cp7 finding.

<!-- adapter:begin -->
# Claude reviewers of a review round — controller instruction

The Agent tool is not callable from bash, so the controller dispatches every
reviewer whose provider is `claude`, at every checkpoint: the plan review
(`commands/aid-plan.md` "Plan review (CP1)") and the step and fast-mode
reviews (`commands/aid-run.md` "Step review (CP2)", `commands/aid-do.md`)
include this text verbatim. `<round dir>` is the
directory `prepare` printed, and `prepare` prints each role's `<focus>` next
to its prompt: `cp1-<role>` for a plan, `cp2-step-<N>-<role>` for a step,
`cp6-<role>` in fast mode, `cp7-<role>` at plan
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
   Agent(subagent_type: <the agent prepare printed next to the role's prompt>, model: <the model printed there>,
         prompt: "Your complete instructions are in <round dir>/prompt-<role>.md. Read that whole file first and follow it exactly.")
   ```

   A harness that does not know `aid-orchestrator:reviewer-light` yet (an older
   installed plugin) takes `general-purpose` at the same model.

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
   bracket in `<round dir>/timeline.jsonl` (`no_dispatch_record`; `prepare` prints the
   exact start/complete commands per role — copy them, never write a bracket after the
   answer; a valid answer without one is re-dispatched via `retry --role <r>`): a file
   nobody dispatched does not close a round. Only a round prepared with
   `--stub` by the acceptance suite skips that check, and the FSM refuses to
   advance on such a round.

   A start for a role the round does not ask is refused on the spot (the focus
   must name one of `reviewers_expected`; `prepare` printed them). A start that
   will never get a complete — the reviewer was stopped, the role was dispatched
   by mistake — is withdrawn, never faked:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" cancel --focus <focus> \
     --evidence-dir <round dir> --reason "<why, 20+ characters>"
   ```

   A cancelled start is not a complete: an answer filed under it has no
   provenance and `close` still refuses it. A role that gave nothing (a codex
   record `answered: false`, or a start with no complete) is retried before
   `collect` with `retry --role <r>`, which withdraws its open start itself;
   nobody waits for the other roles to answer first.

## Stand-in for a Codex role

When `dispatch --provider codex` prints a line starting `STAND-IN:`, no codex
answer came (absent, outdated, over its usage limit, or a run that left no
answer) and the round records `fallback: "claude"` for that role. Dispatch it
exactly as above — the same prompt file, the same start/complete bracket — as
the agent and at the model the STAND-IN line names (`stand_in_model` of the
checkpoint's block), and tell the reviewer to write `"provider": "claude"` in its answer.
`collect` accepts a claude answer for a codex role ONLY with that record, and
counts a stand-in nobody dispatched as missing, which makes the round invalid.
Pass its token figure to `close` like any claude role. The PM card names the
stand-in and the reason in one line; the PM is told, not asked.

After ALL reviewers of the round (claude and codex) have been dispatched, run
`collect`. Only when `collect` exits 0, run `close` once with a token value for
every claude role; when it reports the round invalid, retry the roles it names
first (`close` refuses an invalid round). `<review>` is `--plan <plan>` for
CP1, `--checkpoint cp2 --evidence-dir <run dir> --step <N>` for a step:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" collect <review> --round K
bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" close <review> --round K \
  --tokens <role>=<n|unknown> ...
```

When `close` reports `fail` on a step round and a round remains
(`rounds_default`, or the PM's `override`), the fix is the step's own role's:

```
Agent(subagent_type: <"aid-orchestrator:implementer-light" when the step's role card says **Effort:** low, else "aid-orchestrator:implementer">,
      model: <the **Model:** of the step's role card in skills/role-cards.md>,
      prompt: "fix_of: <round dir>; role: <the step's role card name>. Read <round dir>/merged.json, fix every finding with status open (blocker and major first), commit with the message prefix fix(review):, and report the finding fingerprints you addressed. For a blocker or major, fix its rule (the finding's `rule`, or state it) everywhere it can fail in the change, not only at the cited line, at the root (an allowlist over a blocklist, one check every path passes), and test the rule once, on the path the finding names — a second case only when it takes a different code path, and say which. Touch nothing outside the rules the findings name.")
```

Then `aid-step-check.sh` again (the range now ends at the fix commit) and
`prepare --round K+1`: the confirmation round asks only the reporters of what
stayed open and shows them the open findings and the fix diff. Record the
fixer's model and tokens on the next `close` with
`--fixer <role>=<model>:<tokens_in>:<tokens_out>`.

When `close` reports `fail` on the LAST allowed round, it has already written
what stays open where the plan-final boundary reads it: a blocker or major a
later step's declared files cover becomes a carried obligation
(`carried` in merged.json); any other is routed to the run
(`routed`) and done-advance refuses until the PM resolves or backlogs it
(`skills/pipeline.md` §13). Say so on the PM card; do not route by hand what
`close` routed.

Never edit a reviewer's file, never write one on a reviewer's behalf, and never
dispatch a role twice: a role `collect` lists as invalid or missing goes
through `retry`, then this procedure for that role alone. A reason that starts
`form:` means a finding would have been dropped for its form: quote that reason
to the same reviewer; it is asked once, and a second malformed finding is dropped.
<!-- adapter:end -->

## Escalations settled by an independent agent (P112)

PM 13. 10. 2026: in a plan that runs `--auto` (its plan state says
`autonomy: auto`) every escalation that would stop the run on the PM is decided
by an independent agent — automatically, with no instruction before each plan.
A manual plan gets the same when the PM records it once:
`aid-review-round.sh standing --plan <plan> --delegate --reason "<the PM's words>"`
(`evidence/<plan>/delegate.json`; it grants no extra rounds). A PM stop
(`/aid-stop`) ends the automatic delegation.

What is delegated: a disputed finding (`dispute` without `--pm`, CP2/CP7)
and every blocker or major still open after the last round the step or
plan allows. Minor findings never reach the PM's card and are listed at the
close as before. The plan review (CP1) is never delegated.

The controller's loop, per round, before `close` (close refuses while one is
pending and prints the list):

1. `aid-review-round.sh delegate … --round K --pending` — the fingerprints that
   await a verdict; empty → `close`.
2. `aid-review-round.sh delegate … --round K --fingerprint <fp>` — runs Codex
   through the round's own runner on `adjudicator-delegated-<fp16>.prompt.md`
   (`<fp16>` = the 16 hex characters after `sha256:`) and records its verdict.
   **Exit 4 + `STAND-IN:`** — Codex is out (absent, over its limit, no answer):
   dispatch the prompt to an independent `general-purpose` agent with a clean
   context inside the bracket
   `aid-emit-dispatch.sh start --focus adjudicator-delegated-<fp16> --agent-id claude:adjudicator-delegated --evidence-dir <round dir>` … `complete … --output-file <verdict>`,
   then record: `… delegate … --fingerprint <fp> --verdict <verdict file>`.
3. Next fingerprint; never a PM turn in between.

The verdict (`defaults/templates/adjudicator-delegated.md`): `accepted` /
`rejected` for a dispute, `dismiss` / `fix` for a finding open after the rounds
(`fix` grants one more fix-and-confirm round; a finding still open after it gets
a second verdict, `dismiss` or class `brief`), a class and, for a technical
dispute about a check, the re-run command with its exit and output. Class
`technical` is the delegate's to decide; **`brief`, `money` and `data` go to the
PM's card** (`delegation_out_of_scope` — the brief, money and live data stay the
PM's) and `--defer-criterion` takes no review delegate (a technically failed
measurement is the stand-in's, below). A Claude verdict counts
only under its closed bracket and a Codex verdict only with the runner's
`delegate_codex_verdict` event of its sha256 (`delegation_missing` otherwise).
Every settlement is a line of `evidence/<plan>/delegated-disputes.jsonl`; the
close card and page list them. **P117:** a verdict is bound to its evidence (the
finding, the author's dispute, HEAD); new evidence allows one new verdict, the old
one is kept as `superseded` — once per finding and round, then the PM. A finding
whose cited lines a later commit changed is never delegated
(`delegation_fix_pending`): the next round's confirmation judges the fix.

## Run decisions by the stand-in (P117)

The same delegation covers the run's own decisions that are not review findings —
every refusal prints its class (`defaults/refusal-classes.yaml`): `stand_in` and
`agent_fix_then_stand_in` (after the agent's own fix failed) are the stand-in's in
an `--auto` run, `pm` stays the PM's, `incident` is fixed and run again. The loop:

1. Write the proposal: `{"kind": "scope_extension|no_change_step|visual_check|measurement_failed|rename|blocked_step", "step": <0-based index>, …}`
   (`paths` / `criterion` / `rename: {old, new}` / `action: "redispatch", return_sha256` — the action exactly).
2. `aid-stand-in.sh ask --evidence-dir <run> --code <the refusal code> --proposal <file>`.
   **Exit 3 `PROTECTED`** — the brief, AID's config, a `protected_paths` path, another repository, an outside
   service: render the Decision card; the PM decides. **Exit 4 `STAND-IN:`** — dispatch the prompt to an
   independent `general-purpose` agent inside the bracket `stand-in-<id>` (start … complete with
   `--output-file` the verdict file it names), then `aid-stand-in.sh record --evidence-dir <run> --id <id> --verdict <file>`.
3. Run the command with the permission it printed: `amend-scope … --stand-in <auth.json>`,
   `increment-step <state> --stand-in <auth.json>` (a step without a change, the visual check),
   `increment-step <state> --defer-criterion AC<n> --reason "…" --stand-in <auth.json>` (a point whose step
   measurement failed technically; the close measures it again), `amend-contract <state> --rename old=new --reason "…" --stand-in <auth.json>`,
   `step-redispatch <state> --stand-in <auth.json> --reason "…"`. A permission covers that one action, once.


### State: READY

**Entry:** PRE-FLIGHT completed, `fsm-state.yaml` initialized.

**Actions:**
1. Load `execution.yaml` (gate definitions, step config)
2. Load `config/permissions.yaml` (`autonomous_mode` — the one key this file holds for the run;
   the per-class recovery defaults live in the plugin's `defaults/policies/auto-recovery.yaml`,
   which a project may override — but need not, and no installer creates — by placing its own
   `config/policies/auto-recovery.yaml`)
3. **AUTO MODE → SKIP TO STEP 5 IMMEDIATELY.** Do NOT display the run summary, do NOT present Options, do NOT wait for PM.
4. **Manual mode only:** Display the run summary to PM:
   ```
   Plan: {plan_id} — {title} (run {epic_id})
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
   - Serial: work happens on the run's branch — `fsm-state.yaml` `branch`: `plan/{plan_id}`
     itself (`direct: true`, P111 — no task branch exists and none is created).
     Concurrent: each step in `.aid-worktrees/step-<step_id>` on `step/<step_id>`, merged back one
     at a time into the run's branch (the tree it is checked out in).
   - Build the dispatch contract + agent prompt (per `pipeline.md §4`)
   - Dispatch agent via Task tool
   - Collect output → save to `work/evidence/{epic_id}/{run_id}/steps/{step_id}/`; validate the `aid-return` block
4. Verify outputs: present? scope respected? acceptance criteria met?
5. **Step review (CP2)** — the section "Step review (CP2)"
   above: step check, round, `close`; `increment-step` refuses without the
   step's round index at HEAD
5a. **The step's points run (P110)** — `prepare --checkpoint cp2` runs
   `aid-plan-diff.sh --step N --plan-json <run>/plan.json` before it builds the
   packet (the brief points the step closes — a point several steps name is
   measured at the last one — and the step's own `- [ ] [<role>]` criteria with
   a block), so the reviewer reads measured verdicts. `increment-step` reads
   `cp2/step-N/plan-diff.json` bound to HEAD (stale or missing: it measures
   again) and refuses any `absent` point (`step_criteria_failed`, with `next:`);
   `--force` does not waive it. The one way out is the PM's answer on a
   Decision card that quotes the point:
   `aid-fsm.sh increment-step <state> --defer-criterion AC<n> --reason "<the PM's words>" --finding-card <card>`
   (`defer_refused` names what is missing: no card, the card does not quote the
   point, no PM reply after it, a point the step does not close, a reason under
   20 characters). The deferral lands in `cp2/step-N/deferred.json`; every
   later measurement re-checks its card, and the close measures the point.
6. Log to `timeline.jsonl`

**Transition:**
- All steps done → GATES
- Hard failure → ESCALATION
- Next step available → EXECUTE (self-loop, increment `current_step`)

### State: GATES

**Actions:**
1. Read gate definitions from `config/execution.yaml`
2. Run each gate command (per `scripts/aid-run-gates.sh`): every gate under
   `execution.yaml.gates` — or, with `--profile <name>`, only that profile's `include[]`; the
   rest get a `not_in_profile` skip row (see "Gate execution" above, `pipeline.md §5`)
3. Generate `gates_report.json`
4. Log results to `timeline.jsonl`

**Gate-boundary message (deterministic, both manual and auto mode).** When the gate runner
returns — at the GATES→DONE boundary and equally on the failing branch — do NOT write a gate
summary of your own. Source `scripts/lib/aid-gate-outcome-summary.sh` and run:

```bash
aid_gate_outcome_render "<the --report-file path you passed the runner>" "<evidence_dir>"
```

Pass the runner's own `--report-file` path explicitly — it is the preferred wiring; the
renderer only falls back to `<evidence_dir>/gates/gates_report.json` and then the flat
`<evidence_dir>/gates_report.json`. It prints the card (Finished, or Blocked when
`overall: fail`); present it verbatim. A gate run owes the PM no page.

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
6. **PM Summary** (see `pipeline.md` §7 for the full template):
    ```
    DONE REVIEW — {plan_id} ({epic_id})
    {outcome in one plain sentence: what this run now does for the PM}
    Changed: {1-3 user-relevant effects}
    Verified: {pass}/{total} gates pass; step reviews {verdict}
             {or the concrete reason something is unverified}
    Next step: {the one recommended option below, with its one-line reason}

    Detail — steps {done}/{total} | gates {pass}/{total} | duration {time}
    Key outputs: {artifact list}
    Evidence: .aid-o/work/evidence/{id}/{run_id}/

    Options:
      MERGE — record the run on the PLAN branch and go to the close; no release,
              no tag, no push. The release happens once, when the plan is closed.
      FIX   — provide guidance, re-run the review
      ABORT — stop the run, no merge
    ```
    This is the **Finished** card of `skills/communication.md` applied to DONE:
    outcome sentence first, then what changed, what is verified and the one
    recommended next step; counters, report paths and evidence dirs belong to
    the `Detail —` line and below it, never above it. If the review ends in a
    blocker the PM must resolve, render the **Blocked or failed** card instead
    and keep the same ordering.
7. **PM decides:** MERGE → step 8 | FIX → re-run steps 5-6 | ABORT → ERROR (E8)
8. **Advance sub-phase:** PM chose MERGE →
    ```
    bash {plugin_path}/scripts/aid-fsm.sh set-field pm_decision merge <state_file>
    bash {plugin_path}/scripts/aid-fsm.sh done-advance review release <state_file> --direct
    ```
    Enforced: `pm_decision=merge`, the archived-task-file check, routed findings, the
    streamlined integration review (a streamlined run needs the gates report and the
    close's CP7), the abandoned check and tiered compliance.

**Sub-phase: `release`** (after `done-advance review release --direct`)

The run is direct (`direct: true` in `fsm-state.yaml`, started by `plan-run`, P111):
the controller runs `aid-fsm.sh done-advance review release <state> --direct` —
ONE command; the controller calls nothing else. Before it writes `done_phase: release` it records the run
`merged_to_plan` at the tip of `plan/{plan_id}` and moves the plan to
`PLAN_SYNC` (it invokes `aid-plan-fsm.sh epic-complete … --direct` itself); a
failure leaves `done_phase: review` and the same command is run again. The flag
is required on a direct run (`done_advance_needs_direct`); `done-advance` of a
run of the removed EPIC path is refused `epic_path_removed`. `--resume` after a crash inside it reruns
`done-advance review release <state> --direct` (a second record is a no-op).
The close is `plan-finalize` (below). The pre-commit hook guards `plan/{plan_id}` until `done_phase: release`; the
close's commits after that are `plan-finalize`'s.

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

When the plan's run is `merged_to_plan` (done-advance --direct recorded it), the
plan is closed ONCE, as a whole, in four stages and
one review round. Every stage is bound to one frozen candidate, records what it
wrote, and ends its output with `next:` or names what it refuses and what to
run instead. Follow what the tool prints; this section is the map.

`<fsm>` is `bash "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"`, `<round>` is
`bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh"`. Stay in the plan's
worktree (`.aid-worktrees/plan-<id>`) on `plan/<id>` for the whole close.

| # | Command | What it does | It refuses when |
|---|---------|--------------|-----------------|
| 0 | `bash "$AID_PLUGIN_PATH/scripts/aid-release.sh" prepare-plan <plan> --bump minor\|patch --plan-branch plan/<plan>` (`auto` asks when the plan's commits carry no type; `none` when a step of the plan already raised the version and wrote its CHANGELOG section — recorded, nothing committed) | the version commit, BEFORE the freeze, so the candidate already contains the release metadata | the tree is dirty; HEAD is not the plan branch |
| 1 | `<fsm> plan-finalize <plan> --stage freeze` | merges the target branch into `plan/<plan>`, freezes the candidate, mints `R-<plan>-final-<N>` | an EPIC is not terminal; the merge conflicts (exit 4, state CONFLICT); the tree is dirty |
| 2 | `<fsm> plan-finalize <plan> --stage gates` | the plan-final gate run; a gate that passed in the previous attempt and whose `inputs:` did not change is copied (`reused_from`), not executed | a gate fails (the report names it); the branch moved off the candidate |
| 3 | `<fsm> plan-finalize <plan> --stage produce` | review profile, plan-diff, acceptance evidence, and what the round reads (`cp7/`) | gates have not passed; the candidate moved |
| 4 | `<round> prepare\|collect\|close --checkpoint cp7 --evidence-dir <run dir> --project-root <plan worktree> --round 1` | the whole-plan review: `final_criteria` (the brief point by point against the isolated measurement) and `final_generalist` (Codex: across the EPICs, the claims, the security and operations checklist); a project may add `final_claims` | `produce` has not run; HEAD is not the candidate; a reviewer file has no dispatch bracket; the plan-diff was not measured in isolation (`cp7_measurement_stale`); the brief is not the one the plan is bound to (`cp7_brief_sha_mismatch`), missing (`zadani_file_missing`) or, for a strict plan, not named (`plan_names_no_brief`) |
| 5 | `<fsm> plan-finalize <plan> --stage decide` | the one aggregate: `release-decision.json`, the sealed receipt, the PM page with attempts, minutes and USD | the round is not closed; a decision input was edited by hand (named); the candidate moved |

**Gates and the project's tests (P110).** With `project_tests:` declared in
`execution.yaml`, a change to the project's test files needs a gate of the
run's profile flagged `runs_project_tests: true` that proves, through
`--evidence-file {evidence_dir}/gates/<gate>.evidence.json`, that it ran them —
otherwise the row `project_tests` fails (`profile_skips_project_tests`,
`project_tests_evidence_missing`, `project_tests_not_selected`); a suite left to
the nightly tier is `nightly_covers`, a project without the key is only advised
(`project_tests_undeclared`). `run-all-tests.sh --evidence-file` writes the
evidence; `aid-run-gates.sh record-tests --glob … --evidence-file … -- <cmd>`
wraps a whole-suite runner; `aid-run-gates.sh --lint-profiles <execution.yaml>`
checks every profile. The PM waives with `aid-gate-waiver.sh issue project_tests`.

**The measurer at the close (row 3, P110).** `produce` runs every brief point
through `aid-plan-diff.sh --isolated --cwd <the plan worktree>` (the release
profile's `plan_diff` gate passes `--isolated --cwd .`). The rule is the
project's, read from the state root's `execution.yaml`: without
`verification_env:` each `cmd` point runs in a new network namespace with
loopback up and your own uid (no host service, no outbound network, a clean
environment, and whatever it starts in the background dies with it); with
`verification_env:` it runs with those variables and the host network,
recorded as `network: host (verification_env)`. A point the close cannot run
that way is `absent` with a reason and never counts as verified:
`no_isolation` (no usable `unshare --map-user` — `next:` names util-linux ≥ 2.38
and user namespaces), `env_stripped: <VAR>` (a test-service variable such as
`*_TEST_DATABASE_URL` is in your environment but not declared — declare it),
`no_verification_env` (the command names a database URL),
`verification_env_unset: <VAR>`. `--cwd` on a directory that is not a git
worktree exits 3 (`cwd_not_worktree`). `plan-diff.json` records
`isolation {worktree, env_keys, network}`; `produce` prints it.

**The round (row 4)** is dispatched exactly as a step round: the
procedure, the prompt files, the dispatch bracket (`aid-emit-dispatch.sh start` …
`complete`, focus `cp7-<role>`), the Codex role and its stand-in are the ones in
"Step review (CP2)" and "Stand-in for a Codex role" above.
`prepare` prints one prompt per role it asks; a role it lists as *carried* is not
dispatched. `produce` prints the exact `prepare` command with the run directory.
A plan has one round per attempt: a fix moves the candidate, so its confirmation
is round 1 of the next attempt.

**When something is open.** `close` reports `fail`, or `decide` prints
`NOT READY` with the blockers:

1. The role that wrote the code fixes it, on the plan branch:
   ```
   Agent(subagent_type: <"aid-orchestrator:implementer-light" when that role's card says **Effort:** low, else "aid-orchestrator:implementer">,
         model: <the **Model:** of that role's card in skills/role-cards.md>,
         prompt: "fix_of: <run dir>/cp7/round-1; role: <the role of the step that owns the file; backend when no step owns it>. Read merged.json, fix the open findings by CLASS, not one by one (every finding that shares a rule or a pattern is one fix); before you commit, list every caller of each function you changed and every place the rule you introduce applies (graphify explain, or grep), fix those too, and put the list in the commit message; commit with the message prefix fix(review):, and report the fingerprints you addressed. For a blocker or major, fix its rule (the finding's `rule`, or state it) everywhere it can fail in the change, not only at the cited line, at the root (an allowlist over a blocklist, one check every path passes), and test the rule once, on the path the finding names — a second case only when it takes a different code path, and say which. Touch nothing outside the rules the findings name.")
   ```
   The owning step is the one whose declared files cover the path (the run's `plan.json`; the commit that last touched it: `git log -1 -- <path>`).
2. `--stage freeze` again. It mints the next attempt and writes `fix-class.json`:
   what the fix touched decides what is read again. `final_criteria` is never
   carried — every attempt re-measures every point. A change to CHANGELOG,
   README or docs or to the code re-asks `final_generalist` (and `final_claims`
   where a project keeps it); a role whose inputs were not touched and which
   had no finding is carried. A brief point measured `absent` is a blocker
   finding of `final_criteria`. The round's packet shows the re-asked
   reviewers what stayed open and the fix diff.
3. `gates` (unchanged gates are copied), `produce`, the round, `decide`.

**Closing is not development** (P010, agents: twelve attempts, four of the last
findings written by the fixes). Three rules, and one number to watch:

- **Fix by class, not by finding.** Eight separate fixes where three would do
  are five extra attempts. Group the open findings by the rule they break and
  send ONE fix per class.
- **List the callers before the commit.** The fixer names every caller of what
  it changed and every place the new rule applies, and fixes them in the same
  commit — the confirmation round then checks the rule everywhere, not the
  cited line again.
- **Three attempts feeding on themselves → the PM, not another fix.** `close`
  prints `closing: attempt N, M min since the first freeze, findings on lines
  written during the closing: R …` (`measurement.json` `closing`). When R is
  above zero for the third attempt in a row, do not fix: write the open
  findings to the backlog and show the PM a **Decision** card — close with the
  findings disputed and recorded / one more attempt / defer the plan. This is a
  rule for you, not a gate: the plugin counts, you stop.

An ancillary-only move after the freeze (AID's own bookkeeping, e.g. the id
counter) costs nothing: `freeze` names `--stage freeze --accept-ancillary`, which
writes the equivalence receipt and keeps the gates, the round and the decision.

**When to go to the PM, and with which card** (`skills/communication.md`). Try the
fix path once first; escalate when it does not apply or did not help.

| Refusal | Try once | Then show the PM |
|---------|----------|------------------|
| a gate is red and the failure is real | the fix path above | **Blocked** card: the gate, what it printed, the smallest fix |
| a cp7 blocker is still open after a fixed attempt | one more fix when the finding changed; else stop | **Decision** card: FIX (what it costs) / accept with a recorded dispute (`dispute --checkpoint cp7 … --pm accepted --finding-card`) / ABORT |
| the project disputes a finding | `<round> dispute` (CP1, CP2, CP7): do not edit the finding | **Decision** card quoting the finding and its evidence |
| the branch was rewritten (`fix-class.json` reason `rewritten_branch`) | nothing is carried; run the full attempt | none, unless it repeats: then **Blocked** |
| `verification_report` blocks | read its `git_clean` evidence: commit or discard the named tracked file | **Blocked** card naming the file |
| `final_review_disabled` | switch `cp7_plan_final_review` back on | **Decision** card; only the PM's words go into `--stage decide --waive-final-review --reason "<words>"`, and the page then says the plan was NOT read as a whole |

**At the end.** `decide` prints `READY` and the plan is `AWAITING_PM`. Render the
page and the card from the two files it wrote (`aid-plan-close-summary.sh`, `commands/aid-plan.md`, "Plan-final
/ close boundary"). Publish the page with `scripts/aid-pm-page-publish.sh <page> --plan <Pnnn> --kind plan|close|brainstorm --title "<title>"`, then present the chat card verbatim: on `none <page>` publish nothing; on `artifact <page>` publish that body via the Artifact tool; on `link <url>` add one line `Stránka: <url>` under the card; on a failure add one line `Stránka se nezveřejnila: <reason>` and publish nothing else. State no number yourself. MERGE runs
`<fsm> plan-record-decision <plan> MERGE --by pm` (it writes the decision into the
attempt's directory and prints the path), then
`<fsm> plan-merge-to-main <plan> --decision <that path>`; FIX is the fix path; ABORT is
`plan-abort` with the PM's reason.

**The close cleans up.** `plan-close` removes the plan's own worktree, the step
trees and `step/*` branches its merge contains, and its `brainstorm-`/`generation-`
scratch trees; a tree with uncommitted work, a branch the merge does not contain
and a tree outside `.aid-worktrees/` are kept and named, and `cleanup.json` in the
plan-final evidence lists both. A plan built or merged outside `plan-finalize`
(it stopped in `PLAN_GATES`, say) is closed from where it stands with
`<fsm> plan-close <plan> --administrative --reason "<the PM's words>"`; the close
is recorded as administrative, never as an ordinary one.

## Reference Files

- `skills/pipeline.md` — §4 EXECUTE dispatch protocol, §5 GATES protocol
- `scripts/lib/aid-review-adapter-claude.md` — the controller instruction quoted in "Step review (CP2)"; `skills/step-review-roles.md` — the reviewer roles of cp2/cp6/cp7
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

- **Review Checkpoints** — CP2 is the step round (the section above), CP7 the whole-plan round of "Closing a plan" (CP3, the EPIC review, was removed in 3.0.0); every checkpoint toggles in `config/policies/review-checkpoints.yaml`
- **Pre-merge review** — every step is reviewed (CP2) and the plan is read once more as a whole when it is closed (CP7). PM approves via MERGE/FIX/ABORT
- **Exhausted review round** — a cp2 round that fails after the last allowed round is a PM decision (fix in a granted round, or accept with the findings routed), not an escalation state
- **Escalation E8** — PM chose ABORT in the DONE summary
- **6 states only** — READY, EXECUTE, GATES, ESCALATION, DONE, ERROR
- **DONE sub-phases** — `review → release`, managed by `done-advance` (not `transition`); `set-field` rejects writes to `done_phase`
- **No v1 states** — no IDLE, PRE_FLIGHT, SCOPE_CHECK, PLAN, CURATOR_RESOLVE, PM_APPROVAL, DEPLOY_CHECK, FINALIZING
- **PRE-FLIGHT is bash** — runs before FSM starts, not an FSM state
- **`--auto` replaces `/aid-first-aid`** — same autonomous behavior, integrated flag
- **`--resume` reads fsm-state.yaml** — picks up from last known state after crash/interrupt (legacy `state.yaml` still accepted as fallback)
- If `$ARGUMENTS` is empty → **auto-detect over plan streams**. Read
  `.aid-o/work/plan-state/*/plan-state.yaml` (phase + `worktree_path`) and
  `.aid-o/work/active-runs.json` (the map keyed by the run id `E-<nnn>-1_1`,
  carrying `plan_id`, `state`, `branch`) from the state root — the same reads
  `/aid-status` documents as recipes `plan-rows` / `plan-epics`:
  - **Zero active plans** — do not start anything. List the plans available in
    `.aid-o/plans/` and suggest `/aid-plan` or `/aid-run P<NNN>`.
  - **One active plan** — continue its run (confirming the target with the PM).
  - **Two or more active plans** — never guess. Print a **named selection list**,
    one row per active plan in plan-id order: plan id, lifecycle phase, worktree
    path (with `missing!` when recorded but absent), and its run's state (recipe
    `next-epic` of `commands/aid-status.md`: the live run, else `(none)`). Ask
    the PM which plan to run and wait; `/aid-run P<NNN>` skips the question.
  - A plan whose recorded worktree is missing stays selectable, but the run is
    refused after selection with the repair line
    (`plan-state <id> --recreate-worktree --reason`) — selection reports state,
    it does not repair it.
- Pipeline references: `pipeline.md §4 EXECUTE` for dispatch, `§5 GATES` for gate execution

### `--streamlined` mode

Streamlined mode (P040 Component D) trades per-step verification depth for an
integration-review checkpoint, suitable for low-risk plans (see the streamlined
trigger criteria in `/aid-plan`). When `--streamlined` is passed to `init`:

- **`cmd_init` writes `streamlined_mode: true`** into `fsm-state.yaml`. All
  downstream FSM checks read this field via `yq`.
- **`cmd_increment_step` skips per-step CP2** — the step's review round
  (`cp2/step-N/rounds.json`) precondition is bypassed. All other step
  preconditions (step-verify presence, `## Result: PASS`, AC checklist, commit
  ref, Memory Used/Written) and the Component B orphan-dispatch check still run
  in both modes.
- **`done-advance review → release` requires the gates report, and the whole-plan
  review after it** — a streamlined run is reviewed only by the close's CP7, so it
  is refused outside `plan_branch` mode (`streamlined_cp3_off`), and without
  `gates_report.json` it hard-fails with `streamlined_integration_review`.
- **Abandoned check fires on `< 3` timeline events** — a streamlined run whose
  `timeline.jsonl` has fewer than 3 events (init + transition to EXECUTE + at
  least one step/phase event) is treated as claimed-but-never-executed and
  hard-fails with `streamlined_abandoned` (NR 12 SOUSTO P009 anchor).
- **`compliance.json` emits `coverage_mode: "streamlined"`** plus
  `skipped_dimensions: ["verifier_outputs.cp2_rounds"]`
  so the aggregator distinguishes a legitimate streamlined run from a
  full run that is missing that evidence. Full mode emits
  `coverage_mode: "full"` and an empty `skipped_dimensions` array.

Both streamlined checks are PM-overridable via
`done-advance review release <state_file> --force --reason '<≥20 chars>' --blocked-checks 'streamlined_integration_review'`
(or `streamlined_abandoned`), which writes an audited override entry.


**Last Updated:** 2026-09-24
