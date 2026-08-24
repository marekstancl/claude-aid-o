---
name: pipeline
description: AID v2 pipeline reference — 6-state FSM (READY, EXECUTE, GATES, ESCALATION, DONE, ERROR) with state contracts
user_invocable: false
---

# AID Orchestrator v2 — Pipeline Reference

> **Resolve `$AID_PLUGIN_PATH` before running anything below.** Nothing sets it
> for you — not the plugin, not the workspace, not your shell. Every command
> here would otherwise fail with "file not found", and the reader is left to
> work the path out (which is how this survived unnoticed: a model usually
> does). The workspace records it, and this is the same source
> `commands/aid-run.md` §PRE-FLIGHT already uses:
>
> ```bash
> _aid_installed="$(jq -r '.plugins["aid-orchestrator@claude-aid-o"][0].version' \
>                   ~/.claude/plugins/installed_plugins.json 2>/dev/null)"
> AID_PLUGIN_PATH="$(yq -r '.plugin_path' "$(git rev-parse --show-toplevel)/.aid-o/config/plugin.yaml")"
> # The workspace PINS a version and old copies stay on disk, so "the file is
> # there" is not "the file is current": on 2026-08-24 a session ran its first
> # commands against 2.89.1 while 2.90.0 was the installed one. Compare, do not
> # assume.
> [[ -n "$_aid_installed" && "$AID_PLUGIN_PATH" != *"/$_aid_installed" ]] \
>   && AID_PLUGIN_PATH="$HOME/.claude/plugins/cache/claude-aid-o/aid-orchestrator/$_aid_installed"
> test -f "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" || echo "no plugin at $AID_PLUGIN_PATH — run /aid-init"
> ```


**Critical design rule:** This file describes WHAT happens in each state and what the LLM
must do. HOW (bash execution, transitions, file writes) is handled by scripts. The LLM never
implements state transitions — it reads the current state, performs its role, then calls
the appropriate script.

**State file:** `.aid-o/work/runs/{run_id}/fsm-state.yaml` (managed by `aid-fsm.sh`)

## Controller Quick Reference (step dispatch loop)

```
1. verify-state → get current state + allowed transitions
2. get-field current_step → step N
3. Read plan.json steps[N] → objective, role, AC, paths
4. Load role card from role-cards.md
5. Assemble context: EPIC + task + plan + prev outputs + permissions + standards + visual + memory
6. Dispatch agent (Agent tool with role)
7. Validate output: files? scope? AC met? memory_writes present?
8. Write step-{N}-verify.md (AC checklist + Memory Used/Written + Result: PASS)
9. increment-step (bash validates verify file)
10. Liveness check (mechanical, after every dispatch/gate action) — see "AUTO liveness step" below
11. If more steps → goto 2. If last step → CP3 integration review → transition EXECUTE→GATES
```

For full details on each item, see sections below.

### Controller ownership and AUTO liveness

The controller, not a dispatched agent, owns the lifecycle. Only the controller mutates FSM state,
creates commits, starts aggregate gates, finalizes evidence, and owns asynchronous jobs. An agent
may return an explicit job handoff only when the dispatch asked for one; the controller then assumes
ownership immediately.

In autonomous mode, the controller does not yield merely because a subprocess, test, or reviewer is
still running. Each asynchronous job must have a recorded PID, log path, start HEAD/tree hash,
started-at timestamp, expected p95, and hard deadline. Determine completion from the process and its
exit status. `tail -f` and notification arrival are not completion signals. If there is no live owned
process and no repository/evidence progress for 5 minutes, resume or diagnose automatically.

"Resume" names one mechanical path, and its last hop is honestly an instruction:

1. **The artifact.** A run that handed a gate to the background supervisor left exactly one
   continuation pointer at `<evidence_dir>/auto_resume_required.json`, written before the job was
   spawned and removed only when the run's last background job was collected. "A resume is
   required" is derived from (that pointer exists) AND (no liveness signal within the stall
   threshold) — it is never stored, because a dying controller cannot write anything on its way out.
2. **The command.** `aid-fsm.sh resume <epic_id>` claims the pointer exactly once, collects the
   referenced job's terminal result, writes it to the durable `gates_rows/<gate>.json` checkpoint
   (it never edits a final report in place), updates the active-runs entry through the single map
   writer, and prints three lines: what was
   found, what was recorded, and the next action. A job still in flight is a read-only status
   report — nothing is claimed, the pointer is untouched, and a later resume still works. A missing
   job record, a `lost` job, and a `stale` result are each reported verbatim with the rerun
   instruction; none of them is ever patched into the report as evidence.
3. **The printed next action.** The controller runs it.

**What the checkpoint is, precisely.** `gates_rows/<gate>.json` is a durable record of the result
`resume` collected — not the route by which that result reaches the report. The next `run-all`
iterates every defined gate, so it produces its own row for that gate: for a background gate it
re-attaches to the SAME supervised job and *collects* its terminal result rather than re-executing
the suite (that, not the checkpoint, is what makes a crash cost zero re-execution), and it then
overwrites the checkpoint with the row it derived. One condition bounds the re-attach, and only the
re-attach: a result produced by an EARLIER invocation is replayed only while the working tree has
not moved since — otherwise the job is superseded and the gate genuinely re-runs, which is what lets
a fix loop converge. A job this invocation supervised to completion is never second-guessed that
way: what its command returned is what the row says, and a tree that moved underneath it is recorded
on the row (`tree_moved_during_run`) rather than substituted for the verdict. The two rows are
byte-identical by construction, so the outcome is the same either way. The runner's restore-from-checkpoint pass is a fail-closed
safety net for a defined gate that produced no row at all in an invocation; no ordinary path through
the gate loop leaves a gate rowless, and a row it cannot verify against this run's own keyed binding
becomes an explicit `gate_row_stale` FAIL, never a pass.

**AUTO liveness step (loop item 10).** After every dispatch or gate action the controller runs one
query — no daemon, no waiting turn:

```
bash scripts/aid-job.sh watchdog --jobs-dir <run evidence>/jobs \
  --last-progress <epoch of the run timeline's last event> --interval 300
```

`--last-progress` is read from the run's `timeline.jsonl` (its last event's `ts`, or the file's
mtime) — no new bookkeeping. Two outcomes, both routed mechanically:

- **`busy`** — an owned job is live. Continue polling; this is not a stall and not a reason to end
  the turn.
- **`resume_needed`** — no live owned job and no progress within the interval. Enter the recovery
  ladder, classified by the NEWEST job record's state: a `lost` or `missing` record is **JOB_LOST**;
  a `timed_out`/`cancelled` record, or a jobs directory that never existed (a pure-foreground run),
  is **TRANSIENT_INFRA** and goes to diagnosis, never to a job collect. Either way the eager
  continuation artifact — not this query — is what guarantees the run can be continued. Entering the
  ladder means asking for the attempt before taking it:
  ```bash
  source "$AID_PLUGIN_PATH/scripts/lib/aid-recovery-ladder.sh"
  aid_ladder_attempt "<run evidence>" JOB_LOST collect_and_continue   # or TRANSIENT_INFRA + retry_once
  ```
  `proceed <n>` → take the action, then `aid_ladder_outcome … <n> succeeded|failed`.
  `adjudicate <reason>` → `aid_recovery_adjudicate`; `escalate` from that → `aid_ladder_escalate`.

A watchdog invocation that fails is logged and skipped: this step is belt-and-braces around the
artifact, and its absence must never block gates.

The same liveness question asked about OTHER runs is `aid-fsm.sh active-runs stalled` — the one
shared derivation (non-terminal entry AND nothing newer than the stall threshold, default 2100 s
via `AID_ACTIVE_RUN_STALL_SEC`, in either the map's `updated_at` or the run's timeline). It is
derived at read time and stored nowhere, so a controller that wakes up clears it by writing
anything; `/aid-status` renders the same verdict as `STALLED?`. The threshold sits deliberately
above the 1800 s dispatch-deadline clamp so a stall verdict can never race a dispatch pinned at it.

What `resume` does NOT promise: it cannot see an in-line (foreground) gate runner at all — only
supervised jobs are visible to `aid-job.sh`. Its write safety comes from the single-use claim on the
artifact, from refusing while a supervised sibling job of the same run is still in flight, and from
writing only the `gates_rows/<gate>.json` checkpoint, never a final report.

Steps 1 and 2 are mechanical: a command performs them and reports verified facts. Step 3 is an
instruction and nothing more — `resume` cannot execute the controller's turn, so a printed next
action is a handoff, not a completion. Treating it as completion is the failure this classification
exists to prevent.

The concrete helper implementing this contract is `scripts/aid-job.sh` (IMP-262) — a standalone,
opt-in supervisor used at the controller boundary in place of `tail -f`/notification waiting. It is
never a hard FSM/gate precondition and never a release-blocking ceremony:

- `aid-job.sh run --jobs-dir .aid-o/work/jobs [--deadline S] [--repo DIR] -- <cmd>` starts `<cmd>` in
  its own session/process-group and writes a durable record (id, PID + `/proc` starttime, command
  fingerprint, start HEAD/tree, timestamps, hard deadline) before exec. The record survives the
  launching controller: a resumed controller rediscovers the work without relaunching it.
- `aid-job.sh status --id <id>` derives state from the owned process + terminal result ONLY —
  `started` / `running` / `terminal_pass` / `terminal_fail` / `timed_out` / `cancelled` / `lost`.
  It is PID-reuse-safe: an alive-but-reused PID whose `/proc` starttime no longer matches is `lost`,
  never `running`, and a surviving `tail -f` never makes an exited job look live.
- `aid-job.sh collect --id <id> [--require-current]` idempotently returns the terminal result and
  never relaunches. A non-terminal job exits 3 — a started/in-flight job is not test evidence.
  `--require-current` marks the result `stale` (exit 4) when the tree moved, matching the
  immutable-revision evidence rule below.
- `aid-job.sh cancel --id <id>` signals the recorded process group (no orphaned child) and writes a
  terminal cancellation result.
- `aid-job.sh watchdog --jobs-dir DIR --last-progress EPOCH --interval S` is the queryable
  AUTO-liveness half: no live owned job plus no progress within the interval yields `resume_needed`
  (a query, not a daemon).
- `aid-job.sh redgreen --baseline <id> --fixed <id>` accepts only paired receipts where the SAME
  command fails at the baseline revision and passes at the fixed revision; a commit-message-only or
  non-terminal claim is rejected.

Recoverable technical forks go to the configured Codex adjudicator and are recorded in
`timeline.jsonl`. Only a decision requiring new authority pauses for the PM: product intent, material
scope expansion, destructive or externally visible action, security risk acceptance, or access to
credentials/secrets. Codex adjudication cannot grant that authority.

Until the dedicated adjudicator command lands, the controller uses the existing isolated Codex
transport with a bounded decision payload: verified facts, current FSM state, attempted recoveries,
allowed reversible actions, forbidden authority-expanding actions, and evidence paths. Accept only
one of the supplied actions and record the chosen action, rationale, risks, and evidence paths. An
answer outside the allowlist is not authorization. That convention is now codified in
`scripts/lib/aid-recovery-adjudicate.sh` — `aid_recovery_adjudicate <run evidence> <class> <facts>`
prints one allowlisted action or the literal `escalate`, and records every exchange either way.

**AUTO-loop ladder checklist.** `defaults/policies/auto-recovery.yaml` is the one authority for what
an AUTO run may do about a stop before a person is involved; `scripts/lib/aid-recovery-ladder.sh`
loads it and writes the per-run record `<run evidence>/recovery-ladder.jsonl`. Three classes enter
that record from CODE and need nothing from the controller — **GATE_TIMEOUT** and **JOB_LOST** from
the gate runner, **SERVICE_UNHEALTHY** from aid-service's restart-exhaustion path. The other four are
the controller's own responsibility, and this is the checklist for them:

| Class | When the AUTO loop routes it | Route |
|---|---|---|
| **TRANSIENT_INFRA** | a C0 plan-review or C3 audit dispatch reports `unavailable` / `rate_limited` / `timeout` | `aid_ladder_attempt … TRANSIENT_INFRA wait_and_resume` (or `retry_once` / `resume_missing_lenses`). Still NOT a loop iteration — no review budget is consumed |
| **JOB_LOST** | `watchdog` returns `resume_needed` with a `lost`/missing newest job record | `aid_ladder_attempt … JOB_LOST collect_and_continue` |
| **DISPATCH_ORPHANED** | `fsm_check_orphan_dispatches` dies; its message names the exact `aid_ladder_emit` command | run that command, then `aid_ladder_attempt … DISPATCH_ORPHANED collect_and_continue` |
| **REVIEW_EXHAUSTED** | a bounded review loop (gate fix, CP2/CP3, C3, the CP1 ledger) declares itself terminal | the policy allows it NO action: straight to `aid_recovery_adjudicate`, then `aid_ladder_escalate` on `escalate` |
| **UNCLASSIFIED** | anything else, and any class a project override removed | same as REVIEW_EXHAUSTED — a stop AID cannot name is a stop AID does not act on |

Those bounded loops keep their own budgets in their own files; the ladder declares them and records
their exhaustion, and never extends, shortens or replaces one. Its terminus is
adjudicate → ESCALATION → PM force, in that order: `aid_ladder_escalate` stamps
`auto_controller: blocked_for_pm` on the active-runs entry, and LEAVING ESCALATION still requires
`escalation_decision` in `fsm-state.yaml`. Continuing past a refused terminal state is the audited
`--force` surface below and nothing else — there is no ladder bypass. In a MANUAL run the emitters
still record (the evidence is worth having) but nothing routes to adjudication: the human is the
adjudicator.

Test evidence is immutable-revision evidence. It must record the exact command fingerprint,
start/end HEAD and relevant tree hash, timestamps, exit code, and pass/fail counts. Any relevant
change invalidates the old result. Step agents run targeted tests; the controller runs one expensive
aggregate suite on the final candidate HEAD and must not schedule duplicate aggregate gates.

---

## §1 FSM States

### Design Principle: 70/30 Deterministic-First

70% of pipeline decisions are deterministic (bash scripts): state transitions,
gate execution, scope validation, logging, archiving, pre-filter checks.
30% require LLM reasoning: code generation, reviews, curation, auditing.

**Rule:** Never dispatch an LLM agent when a bash check can answer the question.
The pre-filter stage (§13) enforces this for review checkpoints.

### Mechanical Enforcement

`aid-fsm.sh transition` verifies preconditions before allowing state changes.
Transitions are **rejected** (exit 1) if evidence of completed work is missing:

| Transition | Required evidence |
|---|---|
| READY→EXECUTE | `plan.json` exists, `total_steps >= 1` |
| EXECUTE→GATES | `current_step >= total_steps` |
| GATES→DONE | `gates_report.json` with `overall: pass` (+ plan-gate floor: `plan.json.gates[]` vs `excluded_gates[]`, P061 E1 — see §5) |
| ESCALATION→EXECUTE/GATES | `escalation_decision` field set |
| `done-advance review→release` | `curator-report` exists, `audit-report` exists, `pm_decision=merge` |

All FSM operations are logged to `timeline.jsonl` for audit trail.
Use `aid-fsm.sh verify-state` before any action to confirm allowed transitions.
Use `--force` only with explicit PM approval (logged as `fsm_force_override`).
DONE sub-phases use `aid-fsm.sh done-advance` (not `transition`).

### force_override Usage Policy

`aid-fsm.sh <command> ... --force` requires `--reason "<text>"` with **minimum 20 characters**.
Hard fail with copy-paste examples if missing or too short.

**When `--force` is mandatory:**
- Bypassing a FSM precondition when the check has a confirmed false-positive
- Skipping plan-level DONE gate on `cmd_init` when prior-plan CA review was completed out-of-band
- Skipping step verification in `cmd_increment_step` when verifier dispatch was unavailable (MCP outage)

**Examples (accepted by dispatcher):**
```
aid-fsm.sh transition EXECUTE GATES $state_file --force --reason \
  'plan.json bug — step 3 AC has typo blocking gates_no_generated_by check, fix in next EPIC'

aid-fsm.sh transition GATES DONE $state_file --force --reason \
  'security_scan false positive on test fixture, manually verified safe in commit abc1234'

aid-fsm.sh increment-step $state_file --force --reason \
  'step verifier dispatch unavailable due to MCP outage, manually reviewed diff in PR #42'

aid-fsm.sh done-advance review release $state_file --force --reason \
  'auditor agent dispatch failed retry-3, applying P1 finding fix manually'
```

**Telemetry (automatic, cannot be disabled):**
- `fsm_force_override` timeline event records `from`, `to`, `reason`, `caller`, `operator` fields
- Persistent entry to `.aid-o/work/audit-log.jsonl` (cross-EPIC trail, append-only)
- `compliance.json` captures `force_override_count` (int) + `force_override_reasons` (array) per EPIC
- `aid-compliance-report.sh --reflect` flags **🔴 SYSTEMATIC** if:
  - avg force_override_count across post-session-b EPICs > 1, OR
  - max per single EPIC > 3, OR
  - ≥ 30 % of EPICs used force at all, OR
  - any reason < 30 chars or matches low-quality regex `^(fix|bug|needed|done)$`

### FSM States

Six states. Scripts handle transitions. LLM acts within a state.

| State | Entry trigger | LLM role | Exit via |
|-------|--------------|----------|---------|
| **PRE-FLIGHT** | `/aid-run` invoked | None — bash only | → READY (auto) |
| **READY** | PRE-FLIGHT complete | **Auto mode: validate schema → auto-GO immediately.** Manual: review plan, ask PM for GO | `aid-fsm.sh transition READY EXECUTE` |
| **EXECUTE** | GO received or gate-fixer retry | Dispatch agent, verify output | `aid-fsm.sh transition EXECUTE GATES\|ESCALATION\|EXECUTE` |
| **GATES** | All steps done | None — scripts run gates | `aid-fsm.sh transition GATES DONE\|ESCALATION\|EXECUTE` |
| **ESCALATION** | EXECUTE or GATES failure | Manual: PM. Auto: Codex adjudication for technical recovery; PM only when new authority is required | `aid-fsm.sh transition ESCALATION EXECUTE\|GATES` |
| **DONE** | All gates pass | Auditor (C3) then Curator (serial), PM summary, merge on approval | — |
| **ERROR** | Unrecoverable failure or PM abort | Preserve evidence, report to PM | — (terminal) |

**Valid transitions** (enforced by `aid-fsm.sh transition`):

```
READY → EXECUTE | ERROR
EXECUTE → EXECUTE | GATES | ESCALATION | ERROR
GATES → DONE | EXECUTE | ESCALATION | ERROR
ESCALATION → EXECUTE | GATES | ERROR
```

---

## §2 PRE-FLIGHT

**No LLM involvement.** Scripts run deterministically, exit non-zero on
failure, and generation for one plan is ONE TRANSACTION: the CP1 decision is
taken once, every phase verifies it, and the whole package is sealed before any
FSM state or queue entry is created.

```bash
aid-generation-readiness.sh <plan.md>           # source grammar + provisional graph
# ── under one lock hold, before any output exists ──
#    transaction skeleton  → .aid-o/work/evidence/<plan_id>/generation/transaction.json
aid-cp1-gate.sh …                               # THE ONE CP1 call — once per plan, not per phase
#    sealed authority      → …/generation/generation-authority.json
aid-plan-to-epic.sh … --generation-authority … --transaction …   # per phase: VERIFY, never re-gate
aid-epic-to-json.sh …                           # repeat for every generated EPIC
aid-contract-validate.sh …                      # validate each generated package
aid-generation-finalize.sh …                    # seal all phases in one receipt
aid-plan-fsm.sh epic-start <plan> <epic> …      # plan_branch plans only: register task/<epic>/main
aid-json-to-run.sh … --generation-receipt …     # only now create run + FSM state
aid-queue-add.sh …                              # queue entries, ownership bound to the transaction
```

**`epic-start`, and why it is a step of this chain.** For a **`plan_branch`**
plan, `aid-fsm.sh init` will not adopt `task/<epic>/main` unless that branch is
a registered ref with recorded lineage back to `plan/<plan_id>` — that is the
plan-branch lineage check, and it refuses on a task branch nobody registered.
`epic-start` is what performs the registration: it creates the branch as a ref
(no checkout, no tracked writes) and records its lineage in the plan's
lifecycle manifest. So it must run **after** the phase's `plan.json` and
contract validation — the EPIC id it registers is only final once the package
verifies — and **before** `aid-json-to-run.sh` drives init, which is the first
consumer of the registration.

`aid-json-to-run.sh` runs it itself, from `--plan-id` / `--plan-mode` passed by
`aid-auto-pipeline.sh`, because generation is the only layer that knows both
values. It runs **only** when the mode is `plan_branch`: a legacy plan has no
plan branch to descend from, and `epic-start` rightly refuses without a
plan-boundary manifest. The mode is read from the plan's **committed lifecycle
manifest** — the mode this plan actually declares — never from the default-mode
resolver, which answers "what mode would a NEW plan get" and downgrades to
legacy in a project without `gate_profiles`, putting generation and init on two
different authorities.

The call is **best-effort by design**: a non-zero is reported and left to
`init`, which owns the verdict. An already-registered branch is the normal
resumed-generation case, and failing the chain on it would make a resume
impossible.

**Every phase, not only the first.** `init` runs inside the plan's execution
worktree and leaves it on that phase's `task/<epic>/main`. The caller-side
restore below cannot help: for a redirected init the caller's checkout is the
primary one and never moved. So `aid-json-to-run.sh` also returns the PLAN
WORKTREE to `plan/<id>` after init — between EPICs that is where it rests, and
it is why phase 2 finds a usable tree instead of one still sitting on phase 1's
branch (`ERROR: Currently on task/<epic-1>/main, expected task/<epic-2>/main.`).
A failed worktree restore stops the run with exit 4 and the exact `git -C`
command, for the same reason the caller-side one does: every later phase would
otherwise generate against a tree nobody chose.

**The branch-restore contract.** A **failing** `init` still hands the caller's
branch back before the failure is reported. `aid-json-to-run.sh` captures
init's exit status rather than dying on it, runs the branch restore, and only
then exits with init's status. Without this an init that auto-creates and
checks out `task/<epic>/main` on its way to refusing would leave the
operator's own checkout parked on that task branch — the "borrowed the PM's
tree" outcome the plan-branch topology exists to remove.

**On generation success:** every phase has an EPIC, `plan.json`, contract
validation evidence, a recorded entry in `transaction.json`, and one
plan-global generation receipt. Only then may the execution stage create
`fsm-state.yaml` with `state: READY` and queue entries.

**On failure:** the script exits non-zero with its error on stderr and
`/aid-run` reports it to the PM. Three failure shapes, told apart by their
first line:

| First line | Meaning |
|-----------|---------|
| `aid_generation_force_required:` | The CP1 gate refused, and a deliberate PM override could proceed. The printed `aid-auto-pipeline.sh --plan <path> --queue-mode <mode> --force --reason '<why>'` already carries this invocation's values. |
| `aid_cp1_blocked:` | The CP1 gate refused with a condition `--force` cannot cover (mis-invocation, I/O, broken plan identity). The hard condition is named first, and `--force` is **refused in the same place** — it seals no authority and writes no waiver. |
| anything else | Not an AID gate. The failing script's own error is passed through verbatim; when AID's own checks had already passed in that run, one line is appended saying so. |

**On interruption:** rerun the same command. Phases whose recorded outputs still
re-hash to their recorded values are verified and skipped, ids stay identical,
and an EPIC already in the queue is an idempotent skip rather than a duplicate.

PRE-FLIGHT does NOT create the git branch — that is done by the command layer before
calling PRE-FLIGHT.

### Branch Enforcement

`aid-fsm.sh init` validates the git branch context before writing `fsm-state.yaml`. Six
HEAD states are handled:

| HEAD state | Action | Timeline event |
|------------|--------|----------------|
| `task/{epic_id}/main` (resume) | log_info, accept (continuing previous session) | — |
| `main` / `master` / `develop` | auto-checkout `task/{epic_id}/main` (creates branch) | — |
| **plan worktree on `plan/{plan_id}`** (P074) | auto-checkout `task/{epic_id}/main`, **created from the plan branch head** — so a second EPIC starts from the plan head the first one advanced, never from main | — |
| **plan worktree whose `plan/{plan_id}` no longer exists** | **hard fail** — every EPIC branch here is cut from the plan branch, so a missing base ref leaves an unowned tree with broken diff attribution. The message names branch repair; `--recreate-worktree` is explicitly NOT the remedy (the worktree is intact, its base ref is not). | — |
| `task/<other_epic>/main` (mismatch) | hard fail with copy-paste cleanup command | `fsm_branch_mismatch_detected` |
| anything else (`feat/*`, detached HEAD, …) | log_warn, accept (PM context-aware); inside the plan worktree the warning names the expected topology | `fsm_branch_unusual_detected` |
| FOREIGN worktree (git_dir under `.git/worktrees/`, not the plan's recorded one) | skip enforcement (caller controls branch) | — |

The worktree skip is no longer blanket. A plan's OWN execution worktree
(`.aid-worktrees/plan-<id>`, recorded in plan-state) is that plan's "main": it
is exactly where its EPICs are supposed to run, so enforcement RUNS there.
Skipping it would leave init sitting on `plan/<id>` with no task branch, and
done-advance would then attribute an empty diff to the EPIC. Only worktrees
that are NOT the plan's recorded one keep the old skip.

The uncommitted-changes guard runs in all modes — dirty workdir is rejected with
`git status` / `git stash` suggestion before init proceeds. (`init`'s own guard is
deliberately kept: done-advance must attribute a clean diff to the EPIC's work.)

### Which tree must be clean, per command

Clean-tree preflights are scoped to the tree the operation actually mutates —
never a blanket "the repo must be clean". Commands that only create refs or
commit objects require NO clean tree at all:

| Command | Tree that must be clean | Why |
|---------|------------------------|-----|
| `plan-start` | only its own lifecycle paths (`.aid-lifecycle/manifests/<plan>.yaml`, `.aid-lifecycle/repo-identity.yaml`) | branch creation is ref-only, but the mode write does touch those two tracked files — a targeted, non-forceable preflight asserts them clean before anything is created. Everything else may be dirty. The detached-HEAD refusal stays. |
| `epic-start` | none | it creates the task branch as a ref only (`git branch`) — no checkout, no tracked writes; an unrelated dirty tracked edit cannot be harmed. The detached-HEAD refusal stays. |
| `plan-merge-to-main` | none | plumbing-only publish: `merge-tree`/`commit-tree` plus a compare-and-swap `update-ref` against the PM-approved head — no worktree is ever touched, so no worktree content can leak into the merge. |
| `epic-merge-to-plan` | the tree it checks out and merges in — the plan's execution worktree when it has one, the state root for a legacy plan | the merge really is performed in that tree — a dirty file there could be swept into or collide with the merge. |
| `plan-finalize` `--stage sync\|freeze\|gates\|inputs` | the tree it merges in, freezes from and derives inputs in (same resolution as above) | a half-applied `prepare-plan` must never be frozen into a candidate, and the C4 inputs must be derived from a clean candidate tree. |
| `plan-finalize` `--stage review\|c4\|summary\|accept-ancillary` | exempt by design | inside the review boundary a tracked write is a SIGNAL (candidate changed → invalidation), not an operator mistake to stash away. |
| `aid-fsm.sh init` | the tree init runs in — the plan worktree for a worktree-recorded plan (clean by construction), the primary checkout otherwise | done-advance needs a clean diff to attribute. |

### Where a plan-linked command runs: redirect or refuse

Which tree a lifecycle command operates on is **enforced, not documented**. A
plan whose plan-state records an execution worktree (`.aid-worktrees/plan-<id>`,
created by `plan-start`) has ONE place its tree operations may happen, and every
plan-linked command that touches a tree checks before it touches one:

| Situation | Behaviour |
|-----------|-----------|
| Recorded worktree, invoked from anywhere else | **REDIRECT** — the command re-executes itself verbatim with the worktree as its working directory, printing `NOTE: <plan> executes in its own worktree — re-running this command in <path>`. Existing scripts and muscle memory keep working. |
| Recorded worktree, already invoked inside it | no-op, zero overhead |
| Recorded worktree that is missing or no longer git-registered | **REFUSE**, naming `plan-state <id> --recreate-worktree --reason "<why>"`. Never a silent fallback to the primary checkout. |
| Recorded path that is not a LINKED worktree (typically the primary checkout itself) | **REFUSE** the same way. `git worktree list` includes the primary checkout, so "registered" alone would accept a record naming the state root — and the cwd check would then pass it as "already there", running every checkout and merge in the PM's own tree while reporting isolation. Linkedness is validated **before** the cwd comparison. |
| No `worktree_path` recorded, but `.aid-worktrees/plan-<id>` exists or is registered | **REFUSE** — the crash window between `worktree add` and the state write. Names plan-start resume and `--recreate-worktree`; never a legacy pass. |
| No worktree recorded and none present (legacy plan) | one-line notice, runs in the state root exactly as before P074 |

Commands that get the redirect: `epic-merge-to-plan`, `plan-finalize` (every
stage), `aid-fsm.sh init`, `aid-fsm.sh done-advance`. Deliberately excluded:
`plan-merge-to-main` (plumbing-only, touches no tree) and `plan-start` (runs
before the worktree exists by definition).

`plan-close` and `plan-rollback` get the **inverse**: they REMOVE the worktree,
so invoked from inside it they refuse with the exact `cd <state_root>`
instruction — deleting the tree you are standing in is never redirected around.

**Relative paths survive the redirect.** The cwd changes, so the re-exec rewrites
relative path arguments against the operator's original cwd: every flag
documented as taking a path is enumerated (`--project-root`,
`--execution-yaml`, `--decision`, `--plan-file`, `--plan`, `--state-file`,
`--report-file`, `--output`, plus the `<key>=<path>` value half of
`--substitute-receipt`), and bare positionals such as `init`'s state-file
argument are rewritten only when they look like in-repo paths and git cannot
resolve them as a ref — so `plan/P074` and `task/E-074-1_1/main` pass through
untouched. State files given relative are additionally re-anchored to the state
root by `aid-fsm.sh init` and `done-advance` themselves, so a DIRECT in-worktree
invocation reads and writes the primary `.aid-o` rather than forking one.

**Loop guard.** The redirect sets `AID_WT_REDIRECTED=1`. If a re-executed
process still finds itself outside the recorded tree, plan-state is describing
a place it is not, and the command terminates with `worktree redirect loop`
instead of recursing. The guard is cleared once the cwd check passes, so a
nested command for a DIFFERENT plan can still redirect legitimately.

**Agent dispatch.** For a worktree-recorded plan the controller dispatches
implementer and specialist agents **with cwd = the plan worktree**. State reads
still resolve to the primary `.aid-o` (the roots contract), so nothing about
evidence or plan-state changes; only the tree the agent edits does.

The refusal messages of the plan-FSM checks — `epic-merge-to-plan`,
`plan-finalize`'s non-exempt stages, and plan-start's targeted lifecycle
preflight — name the tree they evaluated (`tree evaluated: <path>`), so a
refusal in a multi-worktree layout is attributable to the right checkout.
`aid-fsm.sh init`'s dirty guard predates that convention and keeps its
established message verbatim (`Uncommitted changes present. Commit or stash
before init:`); it evaluates the tree init runs in.

`fsm-state.yaml.created_at` is stamped at init time (ISO 8601 UTC) and consumed by
`fsm_check_grandfather()` for the EXECUTE→GATES precondition (§5). Threshold:
`AID_DEPLOY_DATE` env var or `${AID_PLUGIN_PATH}/DEPLOY_DATE` file.

### After aid-json-to-run.sh (execution stage)

After the complete generation receipt has been checked, running
`aid-json-to-run.sh` initializes the FSM and the EPIC is ready for `/aid-run`.
No manual `aid-fsm.sh init` call is required. To re-initialize
(rare — e.g. `/aid-run --streamlined` after a default-mode init), delete
`fsm-state.yaml` and re-run `aid-json-to-run.sh --streamlined`. The
`--streamlined` flag is what makes the re-init write `streamlined_mode: true`
(it is forwarded to the Step 18 `aid-fsm.sh init` call); re-running
`aid-json-to-run.sh` WITHOUT the flag reproduces full mode. The dual-file layout
(`state.yaml` + `fsm-state.yaml`) from earlier runs is still readable for backward
compatibility, but new runs produce only `fsm-state.yaml` as the single source of truth.

---

## §3 READY State

**LLM role:** Present the plan to PM and wait for approval.

**Read:** `plan.json` from `.aid-o/work/runs/{run_id}/`

**Present to PM:**
```
PLAN REVIEW — {epic_id}
Steps: {total_steps} ({parallel_groups} parallel waves)
Roles: {unique roles list}

Wave execution:
  Wave 0: [architect] {objective}  ~{file_count} files
  Wave 1: [backend] {objective}    ~{file_count} files  ← wave 0
  Wave 2: [qa]      {objective}    ~{file_count} files  ← wave 1

Quality Gates (will run after all steps):
  • test_cmd: {actual command from execution.yaml}
  • lint_cmd: {actual command}
  • build_cmd: {actual command}
  {list all gates from execution.yaml with actual commands}

Options:
  GO    — start execution (pause anytime with /aid-stop)
  REVISE — modify plan (stay in READY)
  ABORT  — cancel, no changes committed
```

**PM response:**
- **GO** → `aid-fsm.sh transition READY EXECUTE <state_file>`
- **REVISE** → Incorporate feedback, re-present (stay in READY)
- **ABORT** → `aid-fsm.sh transition READY ERROR <state_file>`

**Auto-mode (FIRST AID):** Skip PM presentation. Validate plan JSON schema — if valid,
auto-transition to EXECUTE. If invalid, escalate (see §9).

**Enforcement:** `READY→EXECUTE` requires `plan.json` to exist in run dir. If PRE-FLIGHT
was skipped, the transition will be rejected by `aid-fsm.sh`.

---

## §4 EXECUTE State

**LLM role:** Dispatch one step at a time. Verify output. Advance or escalate.

### Step dispatch

1. Read current step: `aid-fsm.sh get-field current_step <state_file>`
2. Load step definition from `plan.json` → `steps[current_step]`
3. Load role card from `skills/role-cards.md` for the step's `role`
4. Assemble dispatch prompt (see Context Assembly below)
5. Dispatch via Agent tool. The model tier comes from the step role's `**Model:**`
   field in `skills/role-cards.md` (single source of truth); an optional `step.model`
   in `plan.json` overrides it for that one step (default: `opus` if neither is set)
6. Save output to `evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/output.md`
7. Verify output (see Output Verification below)

### Context assembly

Dispatch prompt contains (in order):
1. Playbook content (trusted)
2. `EPIC CONTEXT:` block — first sentence of EPIC goal + step-level paths from `plan.json`
3. `## Your Task` — step objective, inputs, outputs, acceptance criteria
4. `## Source Plan` — matching section from `plan_ref` file (if `epic.plan_ref` is set)
5. Previous step outputs — from `evidence/.../steps/` (controlled by `step.context_scope`)
6. `PERMISSIONS CONTEXT` — from `.aid-o/config/policies/permissions.yaml`
7. `STANDARDS CONTEXT` — loaded when `project.yaml → standards.active != 'none'`
8. `VISUAL CONTEXT` — loaded when step has `visual_refs` in plan.json:
   a. Read `visual-spec.yaml` from mockup dir — include VERBATIM in prompt
   b. If source files exist (TSX/CSS): read relevant source file + lines
      from visual-spec.yaml component entries → paste VERBATIM in prompt
   c. If only PNG: include file paths for agent to Read as confirmation
   d. If companion HTML: read HTML files from `mockups/` → include verbatim in prompt + generate design-tokens.yaml (same as github source, HTML instead of TSX)
   e. Priority: source code > visual-spec.yaml > PNG
9. **UI CHANGE CONTRACT** — loaded when step has `ui_change_mode: existing_ui` in plan.json:
    a. Extract `step.ui_change_contract` from plan.json (path + sha256 + schema_version)
    b. Read the contract file at `step.ui_change_contract.path`
    c. Inject into agent prompt as `## UI Change Contract` block (verbatim JSON)
    d. If contract file missing or sha256 mismatch → ESCALATION (missing transport artifact)
    e. Also inject `gestalt_approval` object if companion set it (from companion evidence)

10. **MEMORY CONTEXT** (if `memory.enabled: true` in integrations.yaml):
   - Query Qdrant: `qdrant-find` with step objective as query
   - 2-tier injection into agent prompt:
     a. Top 10 results: summary only (~400 tokens)
     b. Top 3 most relevant: summary + code_example (~1100 tokens)
   - Token budget: ~1500 tokens max for memory context
   - Graceful skip if Qdrant unavailable (log warning, continue without memory)
   - Include in agent prompt under `## Project Memory Context` heading

11. **E2E CONTEXT** (if step has `role: e2e`):
   - Include ALL previous step outputs (not just last — agent needs full picture)
   - Include `project.yaml` (infra detection: test_cmd, build_cmd, docker-compose path)
   - Include `docker-compose.yml` if exists (services, ports, healthchecks)
   - Include high-level E2E scenarios from plan objective
   - Agent expands scenarios into concrete checks, starts infra if needed, executes
   - **Fix loop:** failed checks → agent fixes code → reruns ONLY failed checks → max 3 cycles per check → escalation
   - **Final rerun:** after all fixes, full E2E from scratch — must pass entirely on 1 run with 0 failures
   - step-verify Result: PASS only if final full rerun = 0 failures

Wrap EPIC goal, step objective, previous outputs, and memory context in
`<untrusted_content source="{field}">` tags (prompt injection defense).

### Agent Dispatch Protocol (non-negotiable)

These 6 rules apply to EVERY agent dispatch — frontend, backend, tests, migrations.
Violating them is the #1 cause of agents ignoring the plan.

1. **VERBATIM plan content, not references** — extract the relevant plan section
   (code snippets, AC, specifications) and paste it VERBATIM into the agent prompt.
   NEVER send "read the plan and implement Step X". The agent MUST receive the actual
   content, not a file path to read on its own.

2. **Visual assets as context** — if mockups, screenshots, or design references exist
   for the step, include them in the agent prompt. Text description of a visual
   ("purple gradient banner") is NOT a substitute for the actual image or source code.

3. **Post-step verification against AC** — after agent completes, check EVERY
   acceptance criterion from the plan 1-by-1. Write results to
   `evidence/{epic_id}/{run_id}/step-{N}-verify.md`. `increment-step` REFUSES
   to advance without this file.

4. **Visual verification for UI steps** — after any step that changes UI: take a
   Playwright screenshot and compare against mockup/plan. "Compiles" ≠ "looks right".
   Include comparison in step-verify.md.

5. **Resume on failure** — if AC are not met, resume the agent with specific failures
   (not "try again"). Max 2 fix attempts, then ESCALATION.

6. **Visual context for UI steps** — when step has `visual_refs`:
   Controller reads `visual-spec.yaml` + source code (if available) and pastes
   VERBATIM into prompt. Agent receives exact Tailwind classes and JSX structure —
   adapts to our data layer, does NOT invent design. Agent MUST write Visual
   Anchoring section before implementation code.

**Plan-boundary specialist dispatch (`reporter` / `simplifier` focus).** The Simplifier
and Reporter run at the plan boundary (§7), not per step. Wrap their dispatch by mode,
identically to the CP4 block (§7 step 9): in `agent_tool` mode (default) call `Agent()`
directly — no wrappers. In `subagent` mode ONLY, bracket the call with
`aid-emit-dispatch.sh` start/complete using `--focus reporter` (or `--focus simplifier`),
so the out-of-band provenance ledger records the dispatch:
```bash
bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start \
  --focus "reporter" --agent-id "aid-orchestrator:reporter" --evidence-dir "$evidence_dir"
# Agent({subagent_type: "aid-orchestrator:reporter", ...})
bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete \
  --focus "reporter" --output-file ".aid-o/reports/{plan_id}-delivery.md" \
  --evidence-dir "$evidence_dir"
```

### Standards context (item 7)

When `standards.active != 'none'` in `.aid-o/config/project.yaml`:

1. Load the active standard set (`general.yaml`, or `general.yaml` + `vulcan.yaml` merged)
2. Apply project-level overrides (`disabled_rules`, `severity_overrides`)
3. **Filter by relevance:**
   - Only include rules matching the project's `languages[]` from `project.yaml`
   - Omit rules with `gate_blocking: false` from the prominent section (include as advisory)
4. **Gate-blocking rules first:** Rules with `gate_blocking: true` are placed at the
   top of the context block with a `⚠ GATE-BLOCKING` prefix
5. Format as a `## Standards` section in the dispatch prompt:

```
## Standards ({profile} profile, {N} applicable rules)

⚠ GATE-BLOCKING:
- {RULE-ID}: {description} [severity: {severity}]
- ...

Advisory:
- {RULE-ID}: {description} [severity: {severity}]
- ...
```

When `standards.active == 'none'`: omit the Standards section entirely.

### Documentation reminder

For steps with `role: backend` or `role: frontend`:
- If the step changes public API or user-visible behavior, the agent MUST update relevant docs (README, API docs, CHANGELOG) before marking the step complete.
- The `docs_updated` gate in GATES state will fail if API-path files changed without corresponding docs updates.

### Output verification

After agent completes:
- `output.md` written? → If missing, go to ESCALATION (E5)
- Outputs match `step.outputs`? → If not, re-dispatch once with feedback
- Forbidden paths modified? → Re-dispatch once with warning; 2nd violation → ESCALATION
- Credit exhaustion detected? → Pause to `state: paused`, notify PM

**Step verification evidence (mandatory):**
After all checks pass, write `evidence/{epic_id}/{run_id}/step-{N}-verify.md`:
```markdown
# Step {N} Verification — {step_title}

## Acceptance Criteria
- [x] AC1 description — PASS (evidence: ...)
- [x] AC2 description — PASS (evidence: ...)
- [ ] AC3 description — FAIL (reason: ...)

## Visual Check (UI steps only — skip if no visual_refs and no ui_change_mode: existing_ui)
Mockup: {mockup_path}
Screenshot: {evidence/{epic_id}/{run_id}/screenshots/step_{N}_actual.png}

| Aspect | Match | Notes |
|--------|-------|-------|
| Layout (grid, columns, placement) | YES/NO | {details} |
| Colors (primary, bg, text, borders) | YES/NO | {details} |
| Typography (sizes, weights, fonts) | YES/NO | {details} |
| Spacing (padding, margins, gaps) | YES/NO | {details} |
| Components (presence, completeness) | YES/NO | {details} |

Verdict: MATCH / PARTIAL / MISMATCH

## Memory Used
- entry_id: {id} — {summary} (used for: {how it influenced implementation})
- N/A — no relevant memory entries found (reason: {why})

## Memory Written
- type: {component|pattern|convention} — {summary} (source_file: {path})
- N/A — no new reusable patterns introduced (reason: {why})

step_index: {N}
step_id: {plan.json steps[N].id}
plan_step_hash: {see recipe below}
reviewed_commit: {git rev-parse HEAD — the step's own commit}
idempotency_token: {a token unique to this step's evidence, e.g. {epic_id}-{run_id}-step-{N}-{short-HEAD}}

## Result: PASS / FAIL
```

**Step-binding block (IMP-263, required for new/strict runs).** The five
`key: value` lines above bind the evidence to the exact plan step and reviewed
commit so a copied/renamed prior verify file cannot complete a later step, and
so a re-invoked `increment-step` is idempotent. Compute `plan_step_hash` the
same way the FSM validates it (canonical, no trailing newline):

```bash
plan_step_hash=$(printf '%s' "$(jq -S -c ".steps[$N]" "$evidence_dir/plan.json")" | sha256sum | awk '{print $1}')
```

`reviewed_commit` MUST be the current `HEAD` (this step's own commit — write the
verify file AFTER the per-step commit). `idempotency_token` is the replay key:
it is recorded in `step-transition-ledger.jsonl` on advance, and a second call
carrying an already-recorded token returns `already_applied` without advancing.

On PASS: `aid-fsm.sh increment-step <state_file>` (refuses without step-verify.md).
**Read the machine-readable stdout, never a bare number:**
- `status=advanced advanced_from=<N> advanced_to=<N+1>` (exit 0) — the step advanced.
- `status=already_applied step=<N+1> token=<tok>` (exit 0) — this transition was
  already recorded (replay or crash-recovery self-heal); current_step is unchanged
  or repaired to the recorded target. **This is success, not an error — do NOT
  re-invoke** (the E-064-1_2 double-advance came from misreading the old bare `1`
  stdout as an error and calling `increment-step` again).
- Non-zero exit — a precondition failed (see stderr). Fix and retry; do not force
  past a `binding_*` rejection (stale/wrong-plan/wrong-commit/mismatched-step evidence).

Legacy compatibility: a verify file with no step-binding block still advances by
default (a `step_binding_absent` observe event is logged). Set
`AID_STEP_BINDING=strict` to require the binding on every non-grandfathered run.
On FAIL: resume agent with specific failures (max 2 attempts → ESCALATION)

**Visual verification protocol (frontend steps with visual_refs):**

0. **`## Visual Anchoring` section (ENFORCED):** the frontend agent's output MUST contain a
   `## Visual Anchoring` section (layout / colors / typography / spacing / components derived from
   the mockup — per the frontend role card in `role-cards.md`) BEFORE the implementation code.
   `aid-fsm.sh increment-step` hard-fails a frontend step that carries `visual_refs` but whose
   output lacks a `## Visual Anchoring` section (reason `frontend_missing_visual_anchoring`).
1. **Screenshot capture:** Start dev server if not running → Playwright navigates to
   affected page → screenshot at 1280x720 → save to `evidence/{epic_id}/{run_id}/screenshots/step_{N}_actual.png`
2. **Mechanical comparison:** Run `node {plugin_path}/lib/ui-fidelity/ui-compare.mjs --before <baseline.png> --after <actual.png>` → reads `verdict.json`
   - `verdict.pass: true` → PASS
   - `verdict.pass: false` → FAIL → resume agent with `verdict.reason` + paths. Max 2 fix attempts → ESCALATION.
3. **capture-absent = unverifiable:** If baseline or actual screenshot missing → verdict `unverifiable` → log to step-verify, do NOT PASS or FAIL the visual check; continue to next step with note.
4. **Skip conditions:** No visual_refs AND no `ui_change_mode: existing_ui` on step → skip visual check entirely.

### Review Checkpoint CP2 (per-step, ENFORCED v2.18.0+)

After step implementation + step-N-verify.md write, before `aid-fsm.sh increment-step`:

1. **Pre-filter classification** (deterministic bash, no LLM):
   ```
   bash $AID_PLUGIN_PATH/scripts/aid-prefilter.sh classify <N> <evidence_dir>
   ```

   **Run this for EVERY step. There is no step-0 special case** (P079 Step 9,
   IMP-474 — a live run seeded step 0 by hand and left every other step to
   classify, which looked like two different rules and was neither). The seed
   file `verifier-output-step-<N>.md` is always classify's product: a verifier
   that finds no seed means classify was SKIPPED for that step. Recovery: run
   classify, then dispatch the verifier — never hand-write the seed.
   Exit code:
   - `0` (SKIP) — verifier-output-step-N.md created with `classification: SKIP`; no further dispatch needed.
   - `10` (RUN) — caller dispatches verifier subagent with `focus=code-review`.
   - `20` (FAIL) — caller dispatches verifier subagent with `focus=security` (security keywords detected in diff).
   - `22` (`range_undetermined`) — cp2 could not determine its diff range (no `step_commit` event in
     timeline.jsonl AND no `base_commit` in fsm-state.yaml). **No output file is written** (no false SKIP
     stub). Recovery: let the FSM emit a `step_commit` (it is logged automatically at each
     `increment-step`) or ensure `base_commit` is set in fsm-state.yaml; or set `CP2_RANGE_POLICY=observe`
     to fall back to `HEAD~1..HEAD` (emits a loud `cp2_range_fallback` event). **NEVER hand-craft the
     output file** — that reintroduces the OBS-20260705-01 false-green.

   **Range resolution (cp2, P060 Step 3 — OBS-20260705-01):** cp2 classifies from the STEP boundary,
   not the last commit, so a production step with a bookkeeping commit on top is no longer false-green'd
   `docs_only`. Order: (1) last `step_commit` event in timeline → `step_commit_sha..HEAD`; (2) else
   `base_commit` from `evidence_dir/fsm-state.yaml` → `base_commit..HEAD` (fail-safe WIDER); (3) else
   exit 22 (blocking) or loud `HEAD~1..HEAD` fallback (`CP2_RANGE_POLICY=observe`).

2. **Verifier dispatch** (only for RUN/FAIL):

   **In `agent_tool` mode (default):** call `Agent()` directly — no `aid-emit-dispatch.sh` wrappers needed.

   **In `subagent` mode only (`dispatch_mode: subagent` in plugin.yaml):** wrap with start/complete:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start \
     --focus "cp2-step-<N>" \
     --agent-id "aid-orchestrator:verifier" \
     --evidence-dir "$evidence_dir"
   ```

   ```
   Agent({
     subagent_type: "aid-orchestrator:verifier",
     description: "CP2 step <N>",
     prompt: <verifier prompt with focus=<derived>, diff, DoD, step.outputs, step.forbidden_paths>
   })
   ```
   Verifier reads diff + DoD + step.outputs (nuanced deprivation per `agents/verifier.md`).
   Verifier updates verifier-output-step-N.md with verdict + findings (verdict was `pending` before dispatch).

   After `Agent()` returns (`subagent` mode only):
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete \
     --focus "cp2-step-<N>" \
     --output-file "$evidence_dir/verifier-output-step-<N>.md" \
     --evidence-dir "$evidence_dir"
   ```

   `<dispatch-focus>` substitution rule for CP2: `focus="cp2-step-N"`, `step_n=N`
   (literal step number). The same start/complete pair is re-emitted on every retry
   in the CP2 fix loop (max 2 iterations) — timeline therefore contains 2× start +
   2× complete events for retried steps; compliance check treats the last
   complete event as authoritative provenance.

3. **FSM precondition** (`aid-fsm.sh increment-step`):
   - Rejects if verifier-output-step-N.md missing, or has empty/missing `_generated_by` or `_generated_at` (anti-fabrication).
   - Rejects if `verdict: pending` (pre-filter classified RUN/FAIL but verifier never dispatched).
   - Rejects if plan.json sha256 hash differs from cmd_init-stamped hash (mid-EPIC tampering check).
   - **Rejects if `checkpoint:` is set and ≠ `cp2`** (P060 Step 3 bypass guard, increment call-site ONLY):
     a cp3/cp4-produced stub must not satisfy the per-step CP2 precondition. Absent `checkpoint` is
     backward-compatible. The shared `fsm_check_verifier_output` stays checkpoint-agnostic so the cp3
     consumers (EXECUTE→GATES) still accept `checkpoint: cp3`.
   - **Produces a `step_commit` event** at the step-advance tail (`step_n`, `commit_sha=HEAD`) — the
     boundary marker the next step's cp2 classify consumes for its diff range.
   - **Validates the IMP-263 step-binding** when present: `step_index` must equal `current_step`,
     `step_id`/`plan_step_hash` must match the live `plan.json` step, `reviewed_commit` must be
     current HEAD. A copied/renamed prior verify file is rejected (`binding_*` reasons) before any
     mutation. Absent binding → `step_binding_absent` observe event (or hard fail under
     `AID_STEP_BINDING=strict` on a non-grandfathered run).
   - **Idempotent + crash-safe**: the accepted `idempotency_token` and the `current_step` bump commit
     together via `step-transition-ledger.jsonl` (ledger append, then state bump). A replayed token
     returns `status=already_applied` without advancing; a crash between ledger and state is repaired
     on the next call (`step_transition_recovered`), so the pair is old-valid or new-valid — never a
     double advance. The controller reads `status=`, never bare stdout.

4. **Repeated-fail telemetry**:
   - `fsm_precondition_repeated_fail_step` (same step + same precondition × 3) → step is structurally problematic.
   - `fsm_precondition_repeated_fail_epic` (same precondition across different steps × 3) → systematic bypass.

5. **Verifier deprivation rules** (per `agents/verifier.md`): verifier sees ONLY diff + DoD + step.outputs +
   step.forbidden_paths. NO Architecture Context, NO Implementation Detail rationale, NO Memory queries.
   Prompt explicitly says "you do NOT see why, only what changed."

Fix loop per CP2 failure: gate-fixer → re-run pre-filter → re-dispatch verifier. Max 2 iterations. E7 on exhaustion.

A CP2 finding whose file no remaining step may touch is ROUTED before the
checkpoint closes (§13 *Routing a finding no remaining step may fix*);
done-advance refuses over one that was never recorded.
**Invalidation-Map call site 1/5:** after each applied CP2 fix, run the **Invalidation-Map Post-Fix Hook** (§13, observe-only) with `fix_ref=cp2-step-<N>-iter<K>` (capture `pre_fix_ref` before dispatching the fixer).

**Retry telemetry:** Every re-dispatch in the CP2 fix loop re-emits the same
`verifier_dispatch_start` / `verifier_dispatch_complete` pair documented above
(focus=`cp2-step-<N>`, step_n=`<N>`). Iteration 2 therefore appends a second
start/complete pair to `timeline.jsonl`; provenance binding uses the last
pair (closest to `_generated_at`).

#### C2 Dual-Emit in CP2

When step diff matches a C2 semantic surface (controlled by `review-profile.required_lenses`):
- Verifier task input includes: `c2_mode: "local"` (for local/contract steps) or omit for trivial steps
- Verifier writes `semantic-review-local.json` alongside `verifier-output-step-N.md`
- Gate (aid-fsm.sh) reads ONLY the .md — JSON is additive evidence (D1: gate unchanged)

### Dispatch Protocol

**`dispatch_mode` determines whether timeline events are required:**

| `dispatch_mode` | Default? | `aid-emit-dispatch.sh` wrappers required? |
|-----------------|----------|------------------------------------------|
| `agent_tool` | **Yes (v2.29.1+)** | **No** — CC Agent tool does not write timeline events; FSM bypasses provenance check |
| `subagent` | No (explicit opt-in in `.aid-o/config/plugin.yaml`) | **Yes** — must wrap every `Agent()` with start/complete pair |

In `agent_tool` mode (default): skip the `aid-emit-dispatch.sh` calls entirely. The provenance check returns `"agent_tool"` (non-blocking) and no orphan events are created.

In `subagent` mode (explicit `dispatch_mode: subagent` in plugin.yaml): every
`Agent({subagent_type, prompt})` dispatch MUST be wrapped by paired calls to
`aid-emit-dispatch.sh start` (before) and `aid-emit-dispatch.sh complete` (after).
The orchestrator does NOT skip these calls; if it does, `cmd_increment_step` blocks
the next step transition via the reconciliation backstop (Component B of P040).

> **⛔ Non-negotiable anti-fabrication rule.** For every review checkpoint the
> orchestrator MUST dispatch a real, independent verifier via `Agent({subagent_type:
> "aid-orchestrator:verifier", ...})` and let THAT subagent write its own
> `verifier-output-*.md`. The orchestrator MUST NOT (a) write, edit, or hand-fill a
> `verifier-output-*.md` itself, (b) reuse a prior run's verifier output, or (c)
> "review in its head" and record a verdict without dispatching. Self-written verifier
> output is a correctness violation, not a shortcut — it destroys the per-step
> independence guarantee that is AID's core value. This instruction is the REAL defense
> against fabrication: the provenance check (`verify_provenance`, §7) only flags
> *accidental* breakage (stale / missing / mismatched dispatch records) and returns
> `unverifiable` — it cannot, by design, detect a deliberately forged timeline, because
> the orchestrator controls every input. If a genuine dispatch is impossible (tooling
> failure), STOP and escalate to PM — never synthesize the verdict.

**Before each Agent() dispatch:**

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start \
  --focus "<cp1 | cp2-step-N | cp3-code-review | cp3-security | cp4-curator-validation>" \
  --agent-id "<subagent_type, e.g., aid-orchestrator:verifier>" \
  --evidence-dir "$evidence_dir"
```

**After each Agent() dispatch returns:**

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete \
  --focus "<same value as start>" \
  --output-file "$evidence_dir/verifier-output-<focus>.md" \
  --evidence-dir "$evidence_dir"
```

If the Agent() call crashes between start and complete, the pending entry remains and
the next `cmd_increment_step` blocks with `missing_dispatch_complete: <focus>`. PM
resolves by emitting the complete event (if the agent did run) or
`--force --reason "<≥20 chars>" --blocked-checks "dispatch_orphan_complete"`.

### Integration Review CP3 (pre-EXECUTE→GATES, ENFORCED v2.18.0+)

After all steps complete, before `aid-fsm.sh transition EXECUTE GATES`:

1. **Parallel dispatch** (single message with two Agent tool calls — leverages Krok 1 isolation finding T6):

   **In `agent_tool` mode (default):** call both `Agent()` calls in parallel directly — no `aid-emit-dispatch.sh` wrappers needed.

   **In `subagent` mode only:** emit starts before, completes after:
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start \
     --focus "cp3-code-review" \
     --agent-id "aid-orchestrator:verifier" \
     --evidence-dir "$evidence_dir"

   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start \
     --focus "cp3-security" \
     --agent-id "aid-orchestrator:verifier" \
     --evidence-dir "$evidence_dir"
   ```

   ```
   Agent({subagent_type: "aid-orchestrator:verifier", description: "CP3 code-review",
          prompt: <full diff (run_start..HEAD), DoD list, plan.json overall>})
   Agent({subagent_type: "aid-orchestrator:verifier", description: "CP3 security",
          prompt: <full diff, plan.json overall>})
   ```

   After both `Agent()` calls return (`subagent` mode only):
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete \
     --focus "cp3-code-review" \
     --output-file "$evidence_dir/verifier-output-cp3-code-review.md" \
     --evidence-dir "$evidence_dir"

   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete \
     --focus "cp3-security" \
     --output-file "$evidence_dir/verifier-output-cp3-security.md" \
     --evidence-dir "$evidence_dir"
   ```

   `<dispatch-focus>` substitution rule for CP3: emit two pairs serially even
   though the underlying `Agent()` calls run in parallel — focus values are
   `cp3-code-review` and `cp3-security`, `step_n="null"` for both. Same retry
   semantics as CP2 (last pair is authoritative).

2. **Outputs** (each verifier writes its dedicated file):
   - `verifier-output-cp3-code-review.md` — verdict + findings, `_generated_by: aid-orchestrator:verifier@<agent_id>`, `_generated_at: <ISO 8601 UTC>`, `Reviewed-Head: <sha>`
   - `verifier-output-cp3-security.md` — verdict + findings, `_generated_by: aid-orchestrator:verifier@<agent_id>`, `_generated_at: <ISO 8601 UTC>`, `Reviewed-Head: <sha>`

   **CP3 dispatch passes/requires `Reviewed-Head` explicitly.** Dispatch each CP3
   verifier with the sha the full-EPIC diff was generated against, and each verifier
   MUST record it as a line-start `Reviewed-Head: <sha>` field (see
   `agents/verifier.md` §Output Format). This is the freshness anchor consumed at
   GATES→DONE (P060 Step 4 / OBS-20260702-03): if HEAD later moves past that sha
   outside the narrow D4 exception, the DONE transition is blocked (stale review).

3. **FSM precondition** (`aid-fsm.sh transition EXECUTE GATES`):
   - Existing Session A check: `gates_report.json._generated_by` present (or grandfather skip).
   - NEW Session B: both CP3 output files must exist with valid `_generated_by` (file presence is AC target).
   - P060 Step 4: each CP3 output must carry `Reviewed-Head: <sha>`. `fsm_check_cp3_freshness`
     re-reads it at **GATES→DONE** (and again at `done-advance review→release`) and refuses a
     STALE review as DONE evidence unless the D4 exception (test/fixture/evidence-only churn
     WITH a `CP3-Freshness-Exception:` trailer) holds. Policy `CP3_FRESHNESS_POLICY` (default
     blocking).
   - Verdicts are recorded but NOT a target — verdict is verdict (no Goodhart pressure to fake clean reviews).

4. **Fix loop**: gate-fixer applies suggested fixes → re-dispatch CP3 (both verifiers in parallel again) → retry.
   Max 2 iterations per Session A pattern. E7 escalation on exhaustion.
   **Invalidation-Map call site 2/5:** after each applied CP3 fix, run the **Invalidation-Map Post-Fix Hook**
   (§13, observe-only) with `fix_ref=cp3-iter<K>` (capture `pre_fix_ref` before dispatching the fixer).

   **Retry telemetry:** Every re-dispatch in the CP3 fix loop re-emits both
   `verifier_dispatch_start` and both `verifier_dispatch_complete` events
   documented above (focus=`cp3-code-review` and `cp3-security`,
   step_n=`null`). Iteration 2 appends 4 additional events to
   `timeline.jsonl`; provenance binding uses the last pair per focus.

   **Deferring instead of fixing?** A finding you decide NOT to fix here, and
   which must not be lost at release, is recorded with `aid_obligation_add`
   (§13 *Carried obligations*) — plan-close refuses while one is open. A finding
   whose FILE no remaining step may touch is routed instead (§13 *Routing a
   finding no remaining step may fix*) — done-advance refuses over an
   unrecorded one.

#### C2 Dual-Emit in CP3

CP3 always dispatches with `c2_mode: "final"` (full EPIC diff):
- Verifier writes `semantic-review-final.json` to `evidence/{epic_id}/{run_id}/`
- Verifier writes existing `verifier-output-cp3-code-review.md` / `verifier-output-cp3-security.md` UNCHANGED
- Gate reads only the .md files (D1 unchanged)

### Wiring and Behavior Dispatch (C2 observe, E5)

Two additional C2 dispatch points run when the review-profile's required_lenses include wiring/behavior surfaces.
These are **observe-only** in E5 — they emit `semantic-review-{wiring|behavior}.json` but do NOT block EXECUTE progression.

#### Wiring dispatch (`c2_mode: "wiring"`)

**Criterion:** Dispatch when ALL of:
- At least 2 inter-step contracts (producer→consumer) are visible in the current diff AND
- Profile includes wiring surface (`wiring` in `review-profile.matched_surfaces[]`) AND
- At least one wiring lens applies (transaction_boundary, field_lineage, operation_order_resource_bound, ui_lifecycle, false_empty_distinction)

**Output:** `semantic-review-wiring.json` in evidence dir
**dispatch_observed:** Set `dispatch_observed.modes_dispatched[]` += `"wiring"` in the JSON

#### Behavior dispatch (`c2_mode: "behavior"`)

**Criterion:** Dispatch when ALL of:
- All core behavior paths for this EPIC are present in the accumulated diff (feature-complete slice) AND
- Profile includes behavior surface (`behavior` in `review-profile.matched_surfaces[]`) AND
- At least one behavior lens applies

**Output:** `semantic-review-behavior.json` in evidence dir
**dispatch_observed:** Set `dispatch_observed.modes_dispatched[]` += `"behavior"` in the JSON

**Both wiring and behavior dispatches:**
- Log `dispatch_observed` count to timeline.jsonl
- On failure: log `semantic_wiring_would_block` (observe, does NOT block increment)
- Gate (aid-fsm.sh) does NOT check these files — they are additive evidence only (D1)

### D0 Gate Point — Post-Execute Observe (E2)

After the last EXECUTE step completes (before transitioning to GATES), the C1 Delivery Engine
runs in observe mode:

```bash
bash {plugin_path}/scripts/aid-delivery-gate.sh \
  --epic {epic_id} --run {run_id} --base {base_sha} --phase D0
```

Output: `.aid-o/work/evidence/{epic_id}/{run_id}/delivery-gate.json`

**E2 observe mode:** The engine writes `delivery_gate_would_block` telemetry to `timeline.jsonl`
but never blocks FSM transitions. The `delivery_ready` field in the output JSON reflects what
would happen if enforcement were active. Blocking promotion is deferred to E10.

**Reading the output:**
- `delivery_gate.delivery_ready: false` → issues found (would have blocked in E10)
- `delivery_gate.summary.would_block: true` → same, written to timeline as telemetry
- `delivery_gate.checks[]` → per-check status (pass/fail/skip/unverifiable)
- Full protocol-v2 envelope validated by `aid-protocol-validate.sh`

If more steps remain: `aid-fsm.sh transition EXECUTE EXECUTE <state_file>`
If all steps done + CP3 pass: `aid-fsm.sh transition EXECUTE GATES <state_file>`
On unrecoverable error: `aid-fsm.sh transition EXECUTE ESCALATION <state_file>`

**Enforcement:** Call `increment-step` after each step completes. `EXECUTE→GATES` is rejected
if `current_step < total_steps`. `EXECUTE→EXECUTE` is rejected if `current_step >= total_steps`.

### Parallel groups

**TEMPORARY: Sequential execution enforced.** `orchestration.yaml → dispatch.max_parallel: 1`.
All steps execute one at a time regardless of wave grouping. This prevents:
- Mega-commits (controller must commit per step)
- Placeholder verify files (controller validates after each agent returns)
- Memory bypass (controller injects memory per dispatch)

When parallel is re-enabled (post Agent SDK migration):
- Dispatch all agents in the group simultaneously (single message, multiple Agent calls)
- Each agent writes to its own `steps/step_{N}_{role}/` subdirectory
- After all complete: check for merge conflicts before advancing
- Conflict → ESCALATION; clean → merge branches, advance

---

## §5 GATES State

**LLM role:** None during gate execution. LLM acts only if gates fail.

**Script:**
```
aid-run-gates.sh run-all <execution.yaml> <epic_id> <run_id> <timeline_file> \
  --state-file <state_file> --report-file <evidence_dir>/gates/gates_report.json \
  --plan-json <evidence_dir>/plan.json
```

`execution.yaml` defines gates (generated by `aid-epic-to-json.sh`). Each gate has:
`name`, `command`, `timeout_s`, `required`, `max_attempts`.

**On all gates pass:** `aid-fsm.sh transition GATES DONE <state_file>`

**Enforcement:** `--state-file` ensures gates only run in GATES state. `--report-file` persists
`gates_report.json` — required by `GATES→DONE` precondition. Without it, transition is rejected.

### Gate-Boundary Message (deterministic)

The gate boundary has no free-form summary. When the runner returns — on the DONE branch and on
the failing branch alike, in manual and auto mode — source `scripts/lib/aid-gate-outcome-summary.sh`
and run:

```bash
aid_gate_outcome_render "<the --report-file path passed above>" "<evidence_dir>" "<evidence_dir>/waivers"
```

It computes every number from the report (never re-derives one), writes
`<evidence_dir>/gate-outcome-artifact.html`, and prints the Finished or Blocked card — selected
from the envelope's `.overall`, never from a per-gate row — with a final `Artifact: <path>` line.
A waived gate renders as PM risk acceptance, never as a pass.

Publish the artifact body via the Artifact tool, then present the chat card verbatim.

The card shapes, the ordering rule and the language rule live in `skills/communication.md`; this
section wires them, it does not restate them. If the renderer exits non-zero, say so and present a
Blocked card built only from bounded computed facts, routing any raw-derived text through
`aid_gate_outcome_redact` from the same library first.

### Gate Profiles (`--profile`, P061 E1)

`aid-run-gates.sh run-all` accepts an optional `--profile <name>` flag that selects a named
subset of gates to run for that invocation, sourced from
`execution.yaml.gate_profiles.<name>.include[]` — a whitelist of gate keys:

```bash
aid-run-gates.sh run-all <execution.yaml> <epic_id> <run_id> <timeline_file> \
  --state-file <state_file> --report-file <evidence_dir>/gates/gates_report.json \
  --plan-json <evidence_dir>/plan.json \
  --profile <name>
```

- **Omitting `--profile` preserves pre-P061 behavior exactly** — every gate defined under
  `execution.yaml.gates` runs, even once `gate_profiles` exists in `execution.yaml`. This is
  the backward-compatibility contract.
- **Gates excluded by the active profile** — a gate defined under `.gates` but NOT listed in
  the profile's `include[]` — is never dispatched to `run_gate`. It gets an explicit
  `result: "profile_excluded"` row instead (counted toward the defined==processed integrity
  contract, never silently dropped). A `required: true` gate excluded this way does **not**
  fail the run — same treatment as a skipped `required: false` gate.
- **Fail-loud validation, upfront, before any gate runs:**
  - Unknown `--profile <name>` (no such key under `execution.yaml.gate_profiles`) → exit 1.
  - A profile's `include[]` names a gate not defined under `execution.yaml.gates` → exit 1.
- **`profile_source` is always `"cli_flag"` in this EPIC** — `--profile` is a purely explicit,
  manual CLI flag today, with no automatic selection. Profile auto-selection by risk/phase
  (P061 EPIC 2), the targeted test selector (EPIC 3), self-host default profile activation
  (EPIC 4), and `/aid-do` + release invocation (EPIC 5) are **not implemented yet**.

`gates_report.json` gains four additive fields:

| Field | Value when `--profile` used | Value when omitted |
|-------|------------------------------|---------------------|
| `profile` | profile name (string) | `null` |
| `profile_source` | `"cli_flag"` | `null` |
| `profile_reason` | `"explicit --profile flag"` | `null` |
| `excluded_gates` | array of excluded gate keys | `[]` |

### GATES→DONE Precondition

Beyond `gates_report.json.overall == "pass"`, the `GATES→DONE` transition enforces a
**plan-gate floor** (P061 E1 Step 3): if `plan.json.gates[]` declares a gate mandatory, that
gate must never vanish from the run just because the active `--profile` excluded it. Profile
exclusion alone does not flip `overall` to `fail` (by design — see above), so without this
check a plan-required gate could disappear from a run that still reports `overall: pass`.
`aid-fsm.sh` cross-references `plan.json.gates[]` against `gates_report.json.excluded_gates[]`
— any overlap refuses the transition with reason `plan_gate_profile_excluded`.

- **Unconditional** — this check fires on every `GATES→DONE` attempt, not opt-in, regardless
  of whether `--profile` was used. It is a no-op when `excluded_gates[]` is empty.
- **Fail-loud on a malformed `plan.json`** — if `plan.json` exists at `evidence_dir/plan.json`
  but fails to parse as JSON, the transition is refused with reason `plan_json_malformed`
  rather than being silently treated as "no gate requirements".
- **Design: fail-loud, not force-run** — `aid-fsm.sh` is a precondition checker, not a gate
  executor; it does not re-run the excluded gate itself (that would duplicate
  `aid-run-gates.sh`'s job). The fix is to widen the profile's `include[]` in
  `execution.yaml.gate_profiles` and re-run gates via `advance-to-gates`.
- **Override** — same scoping as the sibling `GATES→DONE` checks (`overall`, CP3 freshness):
  `aid-fsm.sh transition GATES DONE <state_file> --force --reason '<≥20 chars — PM-authorized
  reason>'`. Logged as `fsm_force_override` per the usual audit trail (§1).

**On gate failure (retries remaining):**
0. Capture the pre-fix ref BEFORE dispatching the fixer: `pre_fix_ref="$(git rev-parse HEAD)"`.
1. Dispatch gate-fixer agent with failure details and `gates_report.json`
2. `aid-fsm.sh transition GATES EXECUTE <state_file>` (re-enters EXECUTE for fix)
3. After fix: `aid-fsm.sh transition EXECUTE GATES <state_file>`
4. **Invalidation-Map call site 3/5:** run the **Invalidation-Map Post-Fix Hook** (§13, observe-only)
   with `fix_ref=gates-<gate>-attempt<K>`.

**Repeated-timeout policy block (P063 Step 3):** step 2 above (`aid-fsm.sh transition GATES
EXECUTE`) can now be refused. If `aid-run-gates.sh`'s retry loop already saw the gate time out
3+ times in a row, each at a timeout at least as large as the currently-configured
`timeout_seconds` (`gate_baseline_policy_check`, P063 Step 1), it stops retrying instead of
burning another attempt and marks the gate `retryable:false` with an `operator_action`
(`gate_baseline_mark_policy_block`). A policy-blocked gate has nothing for gate-fixer to act
on — the gate never ran to completion, so there is no failure output to fix, only a timeout
setting to change. Re-entering EXECUTE for it is pointless, so the `GATES→EXECUTE` FSM
precondition now refuses that specific transition (naming the blocking gate and its
`operator_action`) and the orchestrator should route straight to `GATES:ESCALATION` instead —
see "On gate failure (max_attempts exhausted)" below. `--force --reason '<≥20 chars>'` remains
the escape hatch, same as every sibling precondition.

**On gate failure (max_attempts exhausted):**
`aid-fsm.sh transition GATES ESCALATION <state_file>`

**Transition to DONE:** Curator, Auditor, CP4, and CP5 now execute in DONE state (§7).
GATES only runs deterministic quality checks.

### EXECUTE→GATES Precondition

For post-deploy EPICs (`fsm-state.yaml.created_at >= AID_DEPLOY_DATE`):

- `gates_report.json` MUST contain `_generated_by` field (set by `aid-run-gates.sh`).
- Hand-written reports are rejected with copy-paste remediation in stderr.
- Repeated-fail detection: ≥ 3 same-reason fails on the same EPIC trigger
  `fsm_precondition_repeated_fail` event + best-effort `try_telegram_alert()`
  (HTTP POST to `localhost:8817/send_message`).

For pre-deploy grandfathered EPICs (`created_at < AID_DEPLOY_DATE`): precondition
skipped (legacy compat — preserves resumability of the 203 pre-Session-A EPIC dirs).

`aid-run-gates.sh` writes three provenance fields on every successful run:

| Field | Purpose |
|-------|---------|
| `_generated_by` | `aid-run-gates.sh@v<X.Y.Z>` — proves runner produced the report |
| `_generated_at` | ISO 8601 UTC timestamp at write time |
| `_command_log` | array of `{name, command, exit_code, duration_ms}` per gate |

Plus two timeline events frame each run: `gate_runner_start` (with `report_path`,
`gate_count`, `command_list`) and `gate_runner_complete` (with `report_path`,
`overall`, `duration_sec`).

#### Recommended Flow: aid-fsm.sh advance-to-gates

Single atomic command runs the gates and — if they pass — performs `cmd_transition
EXECUTE GATES`. Eliminates the chicken-egg problem between `aid-run-gates.sh`
(required state==GATES) and the transition (required `gates_report.json` with
`_generated_by`), which produced `gates_no_generated_by` precondition fails in
P020 (8×) and P021 (4×) — 12 friction events across 3 EPICs.

```bash
bash $AID_PLUGIN_PATH/scripts/aid-fsm.sh advance-to-gates "$STATE_FILE"
```

Semantics:

- **Pre-conditions** validated cheaply: state==EXECUTE, `current_step >= total_steps`,
  `execution.yaml` exists. CP3 outputs are re-validated by `cmd_transition` after
  gates pass (single source of truth remains `check_preconditions`).
- **Atomicity:** gates fail → state stays EXECUTE (never modified); gates pass →
  `cmd_transition` validates `_generated_by` from the just-written report
  (guaranteed pass), state becomes GATES.
- **Implementation signal:** Env var `AID_GATES_TRIGGERED_BY_FSM=1` is set by
  `cmd_advance_to_gates` to bypass `aid-run-gates.sh`'s state guard. Manual
  callers don't set this var. Strict equality check (`=="1"`) prevents accidental
  bypass via truthy values.
- **Timeline events:** `fsm_pre_gates` (before runner), `gate_runner_start` /
  `gate_runner_complete` (runner internal), `fsm_transition from=EXECUTE to=GATES`
  (success), `fsm_advance_to_gates_fail` (failure, with `runner_exit=<rc>` or
  `transition_check_failed_after_gates_pass`).

#### Manual Two-Step Flow (Backward-Compatible)

For debugging, crash recovery, or scripts that need to inspect `gates_report.json`
between gates run and transition, the original two-step flow remains supported:

```bash
# Step 1: Run gates (omit --state-file to skip state guard, OR use state==GATES)
bash $AID_PLUGIN_PATH/scripts/aid-run-gates.sh run-all \
    "$EXECUTION_YAML" "$EPIC_ID" "$RUN_ID" \
    --report-file "$REPORT_FILE" \
    --plan-json "$EVIDENCE_DIR/plan.json"

# Step 2: Transition to GATES (check_preconditions validates _generated_by)
bash $AID_PLUGIN_PATH/scripts/aid-fsm.sh transition EXECUTE GATES "$STATE_FILE"
```

Use `advance-to-gates` for new code; manual flow stays for edge-case operations.

**`--plan-json` is required, not optional, when a `plan.json` exists.** Canonical
invocation: `aid-run-gates.sh run-all <execution.yaml> <epic_id> <run_id> --state-file <state> --report-file <report> --plan-json <evidence_dir>/plan.json`. The runner
reconciles `plan.json.gates[]` against `execution.yaml` and writes a
`plan_gates_reconciled: true` marker; the `EXECUTE→GATES` precondition refuses the
transition if a report is produced by bypassing `--plan-json` while `plan.json`
exists (a gate declared in the plan but undefined in `execution.yaml` would
otherwise silently never run and still report pass — OBS-20260702-05).

---

## §6 ESCALATION State

**LLM role:** Present failure to PM with structured options. Execute PM's choice.

**Read:** Current state from `fsm-state.yaml`, failure details from `timeline.jsonl`.

**Present to PM.** An escalation is a block that needs a decision, so it is
card 3 ("Blocked or failed") carrying card 2's recommendation lines — both
defined in `skills/communication.md`, which is the only place a card shape is
defined. This section is the single ESCALATION composite; every other surface
references it rather than restating it. Identifiers go LAST, per the ordering
rule: the PM reads what stopped and what to do before reading which EPIC it was.

```
Zastaveno: {trigger_reason — the concrete blocker, not an internal error label}.
Dopad: {what has not happened; what remains safe — nothing is merged or released}.
Co se ví: {the per-type context block below, rendered — the diagnostic itself, not a pointer to it}.
Doporučené řešení: A — oprav a nech to zopakovat: {the smallest safe action}. Dej pokyn, agent práci znovu odešle.
Alternativy: B — přeskočit a pokračovat dál (zaloguje se varování); C — zastavit EPIC a uložit postup (/aid-stop).
Riziko / co není ověřeno: {what was tried, and what those attempts did NOT prove}.
EPIC {epic_id}, stav {failed_state}, {executing_step}/{total_steps}.
```

Fill it from the canonical failure record, never from an agent's assertion.
`Doporučené řešení` is a recommendation and is never rendered as a fact; where
the recovery is a PM risk acceptance, name the exact public `--force --reason`
command and say what it does and does not override.

**Step rendering rule.** This section is the single authoritative definition of step numbering; every other surface references it rather than restating it. `current_step` in `fsm-state.yaml` is 0-BASED and counts COMPLETED steps, so it is never rendered to a human directly. Derive `executing_step = min(current_step + 1, total_steps)` and render it with the disambiguator that says which of the two situations it is: while steps remain, `Plan Step {executing_step} of {total_steps} is next`; once every step is done (`current_step == total_steps`, state GATES/DONE) `all {total_steps} steps complete`. Never a bare `Plan Step N of T` — against a 0-based field that phrasing is unreadable, and an uncapped `+1` renders a nonsensical `T+1 of T` for a finished run. When `total_steps` is 0 (a degenerate plan) render the machine values only. The machine field itself, the `aid-fsm.sh verify-state` JSON payload, and evidence filenames (`step-{N}-verify.md`, with N 0-based) stay 0-based and are frozen compatibility surfaces. `aid-fsm.sh`'s `_fsm_human_step` helper emits exactly this wording, appended AFTER the machine values so existing greps keep matching.


This block is the **Decision-required** card of `skills/communication.md` in its
FSM form: present the blocker and the recommended option in plain language
first, then the alternatives; the EPIC id, progress counter, failed state and
attempt history are the technical context that follows the decision, never
precedes it. The card shape, the ordering rule and the language rule are defined
in that file only — do not restate them here.

In FIRST AID mode, add option D: "Continue manual".

**Per-type context blocks** (include relevant block based on trigger):

| Trigger | Context to show |
|---------|----------------|
| E1-E3 | Agent: {name}, Step: {N}, Error: {stderr/finding}, Files: {affected paths} |
| E4 | Gate: {name}, Command: `{cmd}`, Exit: {code}, Retries: {N}/{max}, Output: {truncated} |
| E5 | Agent: {name}, Step: {N}, Expected: `evidence/.../output.md`, Got: nothing |
| E6 | Parallel group: wave {N}, Conflicting files: {list}, Branches: {list} |
| E7 | Checkpoint: {CP2\|CP3}, Focus: {code-review\|security}, Findings: {list}, Fix attempts: {N}/2 |
| E8 | Critical findings: {list from audit report}, Report: `.aid-o/work/evidence/{id}/{run}/audit-report.md` |

**PM response execution:**
- **A (Fix):** Record decision: `aid-fsm.sh set-field escalation_decision fix <state_file>` → then `aid-fsm.sh transition ESCALATION EXECUTE|GATES <state_file>`
- **B (Skip):** Record decision: `aid-fsm.sh set-field escalation_decision skip <state_file>` → advance to next logical state
- **C (Abort):** `aid-fsm.sh transition ESCALATION ERROR <state_file>`
- **D (manual):** Set `auto-mode-state.yaml: mode: manual`, continue in manual mode

**Enforcement:** `ESCALATION→EXECUTE` and `ESCALATION→GATES` require `escalation_decision` to be
set via `set-field`. The decision is automatically cleared after the transition succeeds.

**Escalation triggers:**
| ID | Trigger |
|----|---------|
| E1 | Step fails 2× + fresh approach fails |
| E2 | Security finding CRITICAL |
| E3 | Security finding HIGH (after step completes) |
| E4 | Gate fails after max_attempts |
| E5 | Agent produces no output |
| E6 | Merge conflict in parallel group |
| E7 | Verifier review failed after 2 fix-loop iterations |
| E8 | Auditor critical finding — PM chose ABORT in DONE summary |

---

## §7 DONE State

**LLM role:** Orchestrate pre-merge review and PM decision.

**Mechanical enforcement (4 layers):**
1. `aid-fsm.sh done-advance` — requires curator-report, audit-report, `pm_decision=merge`
2. `aid-release.sh` — refuses release if `done_phase != release`
3. Git pre-commit hook — blocks commits on `task/*/epic/*` branches in DONE/review
4. **Plan-level DONE gate** — `aid-fsm.sh init` refuses new cross-plan run if previous plan has unreviewed C+A findings (`ca-review-complete` marker missing)

Sub-phases (`review` → `release`) managed by `done-advance`. The `review` phase is auto-set
on GATES→DONE transition.

### DONE Closure Checklist

Ordered sequence — each step has a named gate. `done-advance` and `plan-close` enforce mechanically.

**In `plan_branch` mode, steps 3–9 are NOT per-EPIC — they are the plan-final boundary**
(P068). An intermediate EPIC in a `plan_branch` plan runs steps 1, 2, 2a, 10 and 11 only; the
Auditor, Curator, Simplifier, Reporter, the plan utilities and the `ca-review-complete`
marker all move to `aid-plan-fsm.sh plan-finalize <plan_id> --stage review`, which runs once
against the frozen candidate. The table below is the `legacy_epic_release_mode` sequence; the
plan-final equivalent is *Plan-final review boundary* further down this section.

| Step | Action | Gate (enforced) |
|------|--------|-----------------|
| 1 | Archive run file + update `active.md` | run.md `status: completed` |
| 2 | Generate `final_report.md` | file present in evidence dir |
| 2a | Build `audit-input-manifest.json` (C3 producer hook) | file present, `input_hash` matches hashed `allowlist[]` |
| 3 | Dispatch Auditor (C3), then Curator (serial, consumes `audit-report.json`) | both `*-report.md` present |
| 4 | Curator auto-fix (S/M/L) | gate-fixer applied |
| 5 | Auditor auto-fix (S/M/L, `auto_fixable: true`) | gate-fixer applied |
| 6 | CP4 verifier (curator/auditor diff) | `verifier-output-cp4-curator-validation.md` |
| 6a | CP5: auditor `blocking_findings` check | MERGE option blocked if `blocking_findings: true` |
| 7 | Simplifier (plan boundary) | `simplifier-report.md` required by `plan-close` |
| 8 | Reporter (plan boundary) | `delivery.md` required by `plan-close` |
| 9 | `plan-close` marker | `ca-review-complete` — `plan-close` enforces all of 3-8 |
| 10 | PM decision | MERGE / FIX / ABORT |
| 11 | `done-advance review release` | `pm_decision=merge` + reports present |

Anything this review DEFERS rather than fixes is recorded with
`aid_obligation_add` (§13 *Carried obligations*) before you move on — plan-close
refuses to close over an open `release_blocker`.

### Telemetry Overview

Four telemetry mechanisms fire automatically during DONE state. Detail in [Telemetry Reference](#telemetry-reference) below.

- **Epic Summary** (v2.18.0+) — after `done-advance review→release`, generates `evidence/<epic>/<run>/epic-summary.md` with delivery summary, warnings, and PM trust level (HIGH/MEDIUM/LOW). Best-effort; never blocks release.
- **Compliance Telemetry** — writes `compliance.json` with 6 enforcement dimensions; `overall: pass` if all checks ∈ {true, null}. Aggregator: `aid-compliance-report.sh`.
- **Tiered Severity** — `done-advance review release` refuses transition on `severity: blocking` failures; soft-fail if `yq` missing. Override via `--force --reason`. Severity registry: `.aid-o/config/check-severity.yaml`.
- **Compliance Recovery Alert** (P042) — Telegram `🛑` on block, `✅` on recovery. Config gate: `notifications.telegram.alert_on_compliance_recovery` (default `true`).

### Specialist dispatch is plan-final in `plan_branch` mode

The Auditor, Curator, Simplifier and Reporter dispatches described in this section are
**plan-final only** when the owning plan declares `mode: plan_branch` in
`.aid-lifecycle/manifests/{plan_id}.yaml`. An intermediate EPIC completion inside such a
plan dispatches none of them, and the FSM enforces that structurally: `done-advance
review release` skips CP4, the CP3 freshness re-check, the review-profile presence check,
the Curator/Auditor report requirements, the C3 audit + dispatch-provenance chain and the
EPIC-scoped C4 dual run (the authoritative list is `AID_PLAN_BRANCH_SKIPPED_STAGES` in
`scripts/aid-fsm.sh`, echoed into the run's `done_advance_plan_branch_mode` timeline event).

**The CP3 verifier pair is still dispatched per EPIC — it is NOT part of the skip.** Only
the CP3 *freshness re-check* (a re-verification at `review → release`) and the
*review-profile presence* check are skipped. The DONE-review CP3 code-review and CP3
security verifiers run for every EPIC in both modes, and under `streamlined_mode: true`
`fsm_check_streamlined_integration_review` — which runs ABOVE the skip guard and is
retained in both modes — hard-fails `done-advance` when
`verifier-output-cp3-code-review.md` or `verifier-output-cp3-security.md` is missing.
Skipping the CP3 pair on a `/aid-run --streamlined` plan-branch EPIC leaves no clean
recovery short of dispatching after the fact or forcing the transition.

**The auditor's `blocking_findings` verdict is also retained.** If a mid-plan Auditor run
(the exception below) writes an `audit-report`, its top-level `blocking_findings` field is
read in BOTH modes and a non-`false` value blocks the advance. No `audit-report` at all —
the normal shape of an intermediate EPIC — stays a silent no-op.

**The one exception — `mid_plan_specialist_review_exception`.** A PM may explicitly ask for
a specialist review mid-plan. Record it in the runtime plan manifest before dispatching:

```bash
bash -c 'source {plugin_path}/scripts/lib/aid-plan-manifest.sh
  plan_manifest_update {plan_id} ".plan_boundary_manifest.mid_plan_specialist_review_exception \
    = {\"epic_id\":\"{epic_id}\",\"reason\":\"<why the PM asked>\"}"'
```

The exception authorizes the dispatch; it does **not** re-enable the FSM release stack, and
it is counted as an exception rather than as a default invocation. Never dispatch a
mid-plan specialist without the recorded exception — an unrecorded dispatch is
indistinguishable from the pre-P064 per-EPIC ritual this plan replaced.

In `legacy_epic_release_mode` everything in this section runs exactly as before.

### C+A Execution Model: dispatch per EPIC, validate per Plan

**Per-EPIC (non-blocking):**
- Steps 1-6 as documented above (run file, archive, active.md, final_report, C3 producer hook,
  dispatch Auditor then Curator — serial, not parallel, E-057-2_2)
- C+A (as a pair) may still run as background agents relative to the NEXT EPIC — OK to start the
  next EPIC in the same plan while this EPIC's Auditor→Curator sequence is in flight. Within the
  pair itself, Auditor completes before Curator dispatches (Curator consumes `audit-report.json`).
- "Background" does not transfer ownership to a notification. The controller records the job
  contract (PID/agent id, evidence path, start revision, deadline), checks it on every loop, and
  collects the terminal result before using its evidence. It never uses `tail -f` as a watcher.
- done_phase stays `review` until plan-level checkpoint

**Per-Plan checkpoint (HARD STOP after last EPIC in plan):**

In `plan_branch` mode this checkpoint is not a controller convention — it is the FSM stage
*Plan-final review boundary* below, and the numbered list that follows describes the
`legacy_epic_release_mode` shape.

1. Wait for ALL pending C+A reports from all EPICs in this plan
2. Read all reports, compile findings across all EPICs
3. Apply ALL fixes — S, M, AND L effort (L findings are often trivial in practice)
4. CP4 verifier on aggregated fixes
5. **Simplifier (serial, after C+A fixes).** Dispatch the Simplifier agent
   (`agents/simplifier.md`) over the plan diff `base_commit..HEAD`; it writes
   `simplifier-report.md` (propose-only — it never edits code). Then **read its
   proposals and dispatch the gate-fixer with a `simplifier` proposal source**: apply
   `recommended_disposition: approve` items at effort **S/M**, and route **L**-effort
   items to the PM summary (deferred). CP4 re-runs on the applied diff — which now
   includes the simplifier edits — and reverts on FAIL, the same rail as the per-EPIC
   `review` sub-phase steps 7–9. Runs serially AFTER the C+A fixes so it simplifies the
   final shipped code, not a moving target. Toggle: `review_checkpoints.simplifier_pass`.
   **Invalidation-Map call site 5/5:** capture `pre_fix_ref` before dispatching the gate-fixer with the
   `simplifier` proposal source; after the simplifier-approved fixes are applied, run the
   **Invalidation-Map Post-Fix Hook** (§13, observe-only) with `fix_ref=done-simplifier`.
6. **Reporter (last, after the Simplifier + CP4).** Dispatch the Reporter agent
   (`agents/reporter.md`) as the final plan-boundary step. It tests the delivery and
   writes `.aid-o/reports/{plan_id}-delivery.md` (from
   `defaults/templates/delivery-report.md`) plus ≥1 evidence artifact under
   `evidence/{epic_id}/{run_id}/reporter/`. The `delivery_report_present` advisory
   compliance check is evaluated at this boundary (presence + on-disk `_test_evidence`).
   `epic-summary.sh` generation is unchanged — the Reporter augments it, does not replace it.
   Toggle: `review_checkpoints.delivery_report`.
7. Create `ca-review-complete` marker via **`aid-fsm.sh plan-close`** (not `touch`):
   ```bash
   bash {plugin_path}/scripts/aid-fsm.sh plan-close {epic_id} {evidence_dir} {project_root}
   ```
   `plan-close` verifies curator-report, audit-report, simplifier-report, and delivery report
   are all present (skipping disabled specialists), then writes the marker. Raw `touch` bypasses
   these checks — use `plan-close` exclusively.
8. PM Summary with MERGE/FIX/ABORT for entire plan
9. `aid-fsm.sh init` for next plan's EPICs now unblocked

**Enforcement:** `aid-fsm.sh init` blocks cross-plan runs without `ca-review-complete` markers.
The marker must be created via `plan-close`, not `touch` — `plan-close` enforces report presence.

### Plan-final review boundary (`plan_branch` mode) — `plan-finalize --stage review`

After `--stage gates` puts the plan in `PLAN_REVIEW`, every plan-level review runs **once**
against the frozen candidate. **The FSM dispatches nothing.** It declares which outputs must
exist, validates them against `candidate_sha`, and blocks until they do — the same division
already used for C3, where `aid-fsm.sh` validates a dispatch record the controller produced.

**Before the first `--stage review` invocation, run `--stage inputs` exactly once.** This is
an FSM-internal producer step — it dispatches nothing — that derives `review-profile.json`,
`plan-diff.json` (IMP-464/D2's hash-bound C3 AC verdict), `delivery-gate.json` and
`acceptance-evidence.json`, and (IMP-465/D3) generates the schema-valid protocol-v2 skeletons
for `curator-report.json`, `semantic-review-final.json` and `delivery-report.json` — every
envelope field filled, the artifact's own payload key left `null` for the dispatched specialist
to fill. Skipping this step does not just lose those artifacts: `--stage review`'s
generated-skeleton immutability check (D3) and its `plan_final_inputs.plan_diff_sha256` binding
(D2) both assume `--stage inputs` ran first, and specialists dispatched without it must
construct their entire envelope from prose again, exactly the failure mode D3 exists to remove.

```bash
git -C {project_root} checkout plan/{plan_id}   # its head IS candidate_sha
bash {plugin_path}/scripts/aid-plan-fsm.sh plan-finalize {plan_id} --stage inputs
```

**Then put the worktree ON the candidate and keep it there for the whole review boundary**
(unchanged by `--stage inputs`, which does not move HEAD):

```bash
git -C {project_root} checkout plan/{plan_id}   # its head IS candidate_sha
bash {plugin_path}/scripts/aid-plan-fsm.sh plan-finalize {plan_id} --stage review
```

This is the controller's job, not the stage's, because the specialists are dispatched
*between* the exit-7 invocation and the validating one. Two things depend on it: the
plan-level specialists review this worktree (an agent that reads files rather than
`git show base..candidate` would otherwise silently review the target branch), and the
stage's drift detection is baselined on it. `--stage gates` restores HEAD to wherever it
was when it finished, so after gates the worktree is **not** on the candidate — position
it again. The stage refuses with exit 1 if `HEAD != candidate_sha`.

| Exit | Meaning | Controller action |
|------|---------|-------------------|
| 7 | `awaiting_review_outputs` — one or more required outputs absent | **Not an error.** Dispatch the named agents, then re-run the stage |
| 1 | an output is present but stale / wrong-plan / wrong-candidate, or fails `aid-protocol-validate.sh` | Re-produce that output against the candidate; it is never accepted with a warning |
| 6 | the candidate changed (a tracked write) | Plan is now `PLAN_FIX`: re-run `sync` → `freeze` → `gates` → `review` against the NEW candidate |
| 0 | every output present, fresh and bound | Plan is now `AWAITING_PM` |

The stage writes `review-requirements.json` into the plan-final run directory
(`.aid-o/work/evidence/{plan_id}/R-{plan_id}-final-{n}/`) — the machine-readable contract of
what to dispatch, including the review range `plan_base_commit..candidate_sha`. **The review
range is the whole plan, not an EPIC diff**, so a defect introduced by the first EPIC is still
in range when it is detected after the last one is integrated.

Required outputs, all inside the run directory (never in the candidate tree):

| Output | Type | Binding checked |
|---|---|---|
| `semantic-review-final.json` | `semantic_review` | `revision.head_sha == candidate_sha`; `revision.base_sha == plan_base_commit` |
| `audit-report.json` | `audit_report` | `audit_report.reviewed_head == candidate_sha`; `input_manifest_hash` present AND equal to `audit-input-manifest.json`'s own `input_hash` |
| `audit-input-manifest.json` | `audit_input_manifest` | `audit_input_manifest.input_hash` chains to `audit-report.json` (D2); any `plan-diff.json` entry in `evidence_hashes[]` matches the producer-sealed hash |
| `curator-report.json` | `curator` | `curator.audit_report_ref` is sha256 of that audit report |
| `simplifier-report.md` | markdown | a `Head: <candidate_sha>` provenance line |
| `review-profile.json` | `review_profile` | derived over the plan range; `review_profile.required_lenses[]` present (arms the C3 gate) |
| `delivery-gate.json` | `delivery_gate` | `identity.epic_id: null`, `identity.plan_id` set, `sources[]` lists every contributing EPIC |
| `acceptance-evidence.json` | `acceptance_evidence` | same; a missing per-EPIC contribution is a blocker naming that EPIC |
| `delivery-report.json` | `delivery_report` | `identity.plan_id` set, `revision.head_sha == candidate_sha`, written **last** |
| `dispatch-record.json` | — | `candidate_sha` bound; exactly **1** dispatch per plan-boundary agent and per registered utility |

**Exactly once each.** `dispatch-record.json` carries `dispatches[] {agent, count}` for
`auditor`, `curator`, `simplifier`, `reporter` and `utilities[] {id, count}` for every
registered plan-boundary utility (default registry: `scanner_memory_scan`; override with
`plan_final_utilities:` in `execution.yaml`). Any count other than 1 fails the stage. The
accepted counts land in the manifest as `plan_final_review.dispatch_counts` and
`plan_final_review.utilities_run[]`.

**The Reporter is last.** It is dispatched only after the final non-mutating pass; the stage
refuses a `delivery-report.json` older than any other required output. Its authoritative
artifact is that protocol-v2 JSON — `.aid-o/reports/{plan_id}-delivery.md` remains a human
projection and is **explicitly not release authority**.

**Any tracked write is a fix, not a review result.** At the start (and again at the end) of
every invocation the stage compares `git rev-parse plan/{plan_id}` against `candidate_sha` and
checks `git status --porcelain` for uncommitted tracked changes. Either one calls
`plan_final_invalidate` with the reason: the candidate binding, the gate report and **every**
review output stop being authoritative and the plan returns to `PLAN_FIX`. This is why
`--stage review` does not take the generic dirty-tree refusal the other stages take — a dirty
tree here has a defined meaning, and hiding it behind "commit or stash first" would lose it.
Untracked writes into the run directory are the normal case and never invalidate anything.

**THE PLAN-FINAL BOUNDARY RULE (stated once, referenced everywhere).** After
freeze, plan-final agents write only run-scoped evidence. A tracked candidate
write is a FIX and requires a new candidate and a new review. The controller
alone renders committed or worktree projections, and only after merge/close —
outside any freeze window, where a projection cannot cost a review.

**WHICH TREE the rule is about (P074 Step 10).** For a plan with an execution
worktree, the fix signal is a tracked write **IN THE PLAN WORKTREE**
(`.aid-worktrees/plan-<id>`) — that is where the candidate lives, where the
review/c4 stages run after the Step 8 redirect, and the only tree the drift
check reads. **The PM's primary checkout is free during a review window**: an
unrelated tracked edit there does not invalidate anything, which is the whole
point of per-plan worktrees. Using the plan worktree for a deliberate manual
fix during `PLAN_FIX` is supported — that IS the fix workflow, and the next
freeze happens from that tree's state. Legacy plans (no recorded worktree) keep
today's behaviour exactly: the state root is the tree evaluated.

Role cards and agent contracts REFERENCE this paragraph rather than restating
it. Restating it is how the P082 contradiction survived: `agents/reporter.md`
ordered its outputs to be committed, this rule invalidated the review on
exactly that write, and the ordered path (`.aid-o/reports/`) is gitignored, so
the order was unexecutable in three independent ways at once — and the reporter
contract itself said so, two paragraphs below the order.

C3 applicability is unchanged: the single plan-level Auditor dispatch is always recorded, but
whether C3 **blocks** stays governed by `defaults/policies/c3-audit-policy.yaml`.

**Dispatching the plan-final Auditor in `c3` mode (IMP-464/D2).** Resolve the mode exactly as
step 6 does for a per-EPIC dispatch (`aid-audit-mode.sh` against `review-profile.json`, produced
by `--stage inputs` above). When `c3`, run the SAME bridge, pointed at the plan-final run
directory, with TWO additions on the `build-manifest` call only — `AID_C3_PLAN_ID` (so the
bridge's identity is plan-shaped: `identity.plan_id` set, `identity.epic_id` omitted, instead of
its per-EPIC default of deriving `epic_id` from the evidence directory's parent, which for a
plan-final run directory resolves to the PLAN id and would make `audit-report.json` fail
`--stage review`'s `identity.plan_id == plan_id` check forever) and `AID_PLAN_DIFF_SHA256` (so
`build-manifest` refuses to seal a `plan-diff.json` snapshot that has drifted from what the
controller produced). Both are scoped to the ONE `build-manifest` invocation, never exported
into the surrounding shell — `dispatch`/`verify` read identity back out of the manifest
`build-manifest` already wrote, and a persistent export would leak into a LATER per-EPIC
`build-manifest` call in the same session and incorrectly pin/plan-scope it:

```bash
run_dir=".aid-o/work/evidence/{plan_id}/R-{plan_id}-final-{n}"   # from review-requirements.json
plan_diff_sha256="$(jq -r \
  '.plan_boundary_manifest.plan_final_inputs.plan_diff_sha256' \
  .aid-o/work/plan-state/{plan_id}/plan-boundary-manifest.json)"
AID_C3_PLAN_ID="{plan_id}" AID_PLAN_DIFF_SHA256="$plan_diff_sha256" \
  bash {plugin_path}/scripts/lib/aid-c3-dispatch.sh build-manifest \
    "$run_dir" "$base_commit" "$candidate_sha" "$risk_profile"
AID_C3_ATTEMPT=1 bash {plugin_path}/scripts/lib/aid-c3-dispatch.sh dispatch "$run_dir"
bash {plugin_path}/scripts/lib/aid-c3-dispatch.sh verify   "$run_dir"
```

Omitting `AID_PLAN_DIFF_SHA256` does not fail closed — `build-manifest`'s pin check only runs
when the variable is set — so it is a silent no-op, not a refusal, if forgotten. This is why
`--stage review` (IMP-464 D2 round-2/3) now ALSO requires `audit-input-manifest.json` itself as
a required output and independently cross-checks it: `audit-report.json`'s `input_manifest_hash`
must equal the manifest's own `audit_input_manifest.input_hash`, and whenever `plan-diff.json`
carries a real verdict (`present`/`absent`, not the honest no-AC-lens `skipped`), the manifest's
`evidence_hashes[]` MUST record a matching `plan-diff.json` entry — a missing, non-array, or
mismatched one is refused, not treated as "C3 never read it". A forgotten
`AID_PLAN_DIFF_SHA256` export is still caught at the review boundary even though
`build-manifest` itself stayed silent. Omitting `AID_C3_PLAN_ID`, on the other hand, is NOT
silent — the resulting `audit-report.json` will fail `--stage review`'s plan-identity check
outright, exactly as it should for evidence that never proved which plan it belongs to.

### Review equivalence — an ancillary commit does NOT cost the review (P073)

A completed plan-level review used to die to ANY tracked write after the freeze:
an audit-log append or a rendered report threw away the whole review even though
nothing about the delivery had changed. It no longer does.

**Preconditions — all three are required for acceptance. An unmoved head is a
no-op; the other two REFUSE:**

1. The plan has a FROZEN candidate (`--stage freeze` ran).
2. The plan branch head MOVED off that candidate. Acceptance at an unmoved head
   is a no-op and writes nothing.
3. The freeze recorded a COMPLETE protected path set. A plan frozen before P073,
   or one whose EPIC `plan.json` files could not all be located, reports
   equivalence UNAVAILABLE — any movement then invalidates exactly as it always
   did, and no force changes that.

Acceptance is worth running at the moment a drift refusal costs you a review:
between `--stage review` and `plan-merge-to-main`. It does not require the
review to have completed — it preserves whatever review the frozen candidate
already carries — but if no review has run yet, re-freezing is cheaper.

```bash
bash {plugin_path}/scripts/aid-plan-fsm.sh plan-finalize {plan_id} --stage accept-ancillary
```

That records the moved head as review-equivalent to the frozen candidate: one
receipt in the plan-final run directory, bound in the manifest, and
`candidate_sha` left byte-identical. `--stage review` and `--stage c4` then
proceed, and `plan-merge-to-main` merges the accepted head after re-verifying
equivalence live against the current policy.

**Read the refusal before reaching for it.** The recovery hint appears ONLY when
the difference really is ancillary-only, so its presence is a reliable green
light. Its ABSENCE is not one single diagnosis — read what the message actually
says:

- It names PROTECTED paths → the change touched the delivery surface. That is a
  FIX, and the full recovery chain below applies.
- It says equivalence is UNAVAILABLE → nothing is wrong with your change; this
  freeze simply cannot support acceptance (legacy freeze, or a protected set
  that could not be completed). Re-freeze, or accept that any movement
  invalidates for this plan.
- Anything else → the message names its own repair. Do that, not this.

For a protected-surface FIX, the recovery is the FULL stage chain against the
new candidate — `inputs` is not optional, `--stage review` refuses without it:

```
--stage sync → --stage freeze → --stage gates → --stage inputs → --stage review
```

Two more things worth knowing:

- Only the EXACT accepted head is tolerated. One further commit — even another
  ancillary one — invalidates again and needs a fresh acceptance.
- Acceptance is idempotent on the same head, and it verifies its own receipt: a
  deleted or edited receipt is refused, not reported as still accepted.

### The PM force backdoor (P073)

**Exactly eight commands accept `--force`.** No other command does, and
`plan-state` (repair/attest/supersede) deliberately does not — it IS the audited
recovery mechanism a force would otherwise be used to fake:

```
plan-start   epic-start   epic-complete   epic-merge-to-plan
plan-finalize   plan-merge-to-main   plan-close   plan-rollback
```

`--force-reason "<text>"` works on all eight. `--reason` is accepted as a
synonym only on the six that own no business `--reason` of their own;
`epic-complete` and `plan-rollback` already use `--reason` for their own
meaning, so there you MUST use `--force-reason`.

```bash
bash {plugin_path}/scripts/aid-plan-fsm.sh plan-close {plan_id} \
  --force --force-reason "why this must proceed despite the refusal"
```

The reason is mandatory and at least 20 characters. When a precondition is
actually bypassed, the waiver receipt is written BEFORE the command proceeds, so
a force that cannot be recorded is refused rather than performed silently. A reason without `--force` is an error,
never a silently discarded argument.

**Do not try to predict what is forceable.** Each precondition is classified
`forceable` (bookkeeping — a dirty worktree, an unshared source plan, an
incomplete close) or `hard` (identity, evidence integrity, PM authorization),
and **the refusal message is the only authority**. Run the command normally
first and read what it says:

- It names its own recovery → do that. Force is the second route, never the
  first.
- It prints `FORCE CANNOT BYPASS '<name>'` → stop. There is nothing on the other
  side to complete; the message names the repair.
- Force succeeded but printed `bypassed nothing` → no waiver was written,
  because nothing was actually overridden.

**`closed_pending_receipt`.** A forced `plan-close` whose lifecycle receipt
write is itself the broken operation ends the plan as `closed_pending_receipt`,
not `closed` — the plan is terminal, but the durable proof is missing. Re-running
`plan-close` does NOT fix this: once the close marker exists, `plan-close` is a
no-op and says `ALREADY CLOSED`. Converge it instead by repairing what broke
(usually a missing `.aid-lifecycle/manifests/<plan_id>.yaml`) and then running
the lifecycle's own reconciliation:

```bash
bash {plugin_path}/scripts/aid-lifecycle.sh plan-reconcile {plan_id} --apply
```

It prints `state: closed` when the receipt is committed and reachable. Anything
else means it is not converged yet.

### Retiring a stale EPIC run (P073)

Use this ONLY when `aid-fsm.sh init` refuses a specific EPIC as a duplicate AND
that EPIC's run is genuinely stale (abandoned, superseded by a re-plan). It is
not a general cleanup tool. Do NOT delete state files by hand:

```bash
bash {plugin_path}/scripts/aid-plan-fsm.sh plan-state {plan_id} --supersede-epic {epic_id}
```

This archives the state file beside its evidence and authorises exactly ONE
re-initialisation, bound to the `plan.json` the re-init must present. Evidence
artifacts are never touched.

The authorisation is consumed only once the new state file exists, so an init
that fails a LATER gate does not burn it — fix the gate and re-run `init`. If
the init fails because the package itself is wrong (a different `plan.json` than
the one recorded), the record no longer matches and a fresh
`--supersede-epic` is required.

### Plan Boundary: Scanner Memory Scan

After C+A review and fix cycle on plan boundary (all EPICs of a plan complete):

1. **Aggregate memory_writes** — collect all `memory_writes` from step outputs across all EPICs of the plan
2. **Dispatch Scanner** agent in incremental mode with:
   - `git diff {plan_start_commit}..HEAD` — all changes in this plan
   - All curator-report and audit-report files from plan EPICs
   - Aggregated memory_writes from step outputs
   - Auditor memory_flags (if present)
3. **Scanner produces:**
   - CREATE operations (new patterns, components, decisions)
   - UPDATE operations (supersede existing entries with fresh data)
   - INVALIDATE operations (mark stale entries)
   - Kondice report: verified auditor flags (KEEP/UPDATE/INVALIDATE per flag)
4. **Controller validates** each operation (quality rules from memory-mcp.md)
5. **Controller writes** to Qdrant via qdrant-store
6. **PM summary** includes: "Memory: {N} active, {Y} created, {Z} updated, {W} invalidated"

### Sub-phase: `review`

1. **Run file:** Update `status: completed`, `completed: {timestamp}` in run.md frontmatter
2. **Archive:** Move run file to `runs/archive/`; update EPIC frontmatter if all runs complete
3. **Update:** `work/active.md` status
4. **Final report:** Generate `evidence/{epic_id}/{run_id}/final_report.md`

   **4a. Produce `review-profile.json` (C3 activation — E-059-1_2 Step 1).** Runs after the
   final report (step 4) and BEFORE the C3 producer hook (step 5). Orchestrator-side,
   deterministic. This is the step that actually creates `review-profile.json` in a live run
   (before IMP-177 it was only ever written by tests, so the whole C3 gate was dead code). The
   full `base_commit..HEAD` diff exists here, so the profile is computed over the WHOLE EPIC
   diff, not one step.

   1. **Resolve the EPIC task file** — `tasks/` first, `tasks/archive/` fallback (archival can
      race ahead of this step). Pass the resolved path POSITIONALLY (no `--epic`/`--run` flags):
      ```bash
      evidence_dir=".aid-o/work/evidence/{epic_id}/{run_id}"
      timeline="$evidence_dir/timeline.jsonl"
      epic_task_path="$(ls .aid-o/tasks/{epic_id}*.md 2>/dev/null | head -1)"
      [[ -z "$epic_task_path" ]] && epic_task_path="$(ls .aid-o/tasks/archive/{epic_id}*.md 2>/dev/null | head -1)"
      ```
   2. **If the EPIC file resolves → run the profiler** (`aid-prefilter.sh profile`, i.e.
      `cmd_profile`). Its `diff_range` is `base_commit..HEAD` read from `fsm-state.yaml`. Exit
      `22` (`range_undetermined`) is **NON-FATAL**: an unverifiable profile is emitted and the
      run continues — do NOT abort on it.
      ```bash
      set +e
      bash "$AID_PLUGIN_PATH/scripts/aid-prefilter.sh" profile "$epic_task_path" "$evidence_dir"
      prof_ec=$?
      set -e
      # exit 0 = profile emitted; exit 22 = unverifiable profile emitted (continue);
      # any other non-zero = investigate, but the presence check (below) is observe today.
      ```
   3. **If the EPIC file does NOT resolve → FAIL-LOUD (do NOT silently continue).** A missing
      EPIC file must not degrade to a *silent diff-only* profile: candidate-time surfaces alone
      could resolve to a LOW risk and skip C3 even though the (unread) EPIC declared high-risk
      targets. Instead, emit a profile that records the failure explicitly and forces
      `risk_profile: unverifiable` (so both the FSM presence check and `aid-audit-mode.sh` fail
      closed toward `c3`), and log a `review_profile_epic_unresolved` event:
      ```bash
      bash "$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh" log_event "$timeline" \
        review_profile_epic_unresolved epic="{epic_id}" reason="epic_task_file_not_found"
      jq -n --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
        schema_version: "aid-2.0", artifact_type: "review_profile",
        producer: "pipeline.md#review-profile-fail-loud", created_at: $created_at,
        control_protocol: "aid-2.0",
        provenance: {dispatch_mode: "deterministic", generated_by_tool: "pipeline.md#review-subphase"},
        review_profile: {
          matched_surfaces: [], plan_time_surfaces: [], candidate_time_surfaces: [],
          required_lenses: [], risk_profile: "unverifiable",
          plan_time_status: "unresolved", reason: "epic_task_file_not_found",
          ir_cadence: 3, c2_authorities_max: 3, llm_authorities_total_max: 5,
          profile_hash: "sha256:0000000000000000000000000000000000000000000000000000000000000000"
        }
      }' > "$evidence_dir/review-profile.json"
      ```
      The explicit `plan_time_status: "unresolved"` reason is what distinguishes this from a
      legitimate empty-plan-time profile — a reviewer (and the presence check) can tell the
      EPIC file was genuinely unreadable, not merely surface-free.

   **Enforcement:** the FSM `done-advance` review→release presence check reads
   `review-profile.json` — OBSERVE today (emits `review_profile_would_block`, does not block;
   grandfather-safe for in-flight EPICs), promoting to blocking at E10.
5. **C3 producer hook — build `audit-input-manifest.json`.** Runs after the final report
    (step 4) and before Curator/Auditor dispatch (step 6). Orchestrator-side, deterministic —
    no LLM judgment involved. Applies only when the run's risk profile requires C3
    (`c3_required: true` in `c3-audit-policy.yaml` — currently `high` and `unverifiable`, see
    that file's header comment); for any other risk profile (`docs_trivial`/`low`/`medium`)
    C3 is not required and this hook is skipped — Auditor dispatches in `legacy_health` mode
    instead. The Auditor/Curator dispatch mode is now selected mechanically by
    `aid-audit-mode.sh` (step 6 below), not by prose judgment.

    When mode is `c3`, the producer hook is now a **single call to the deterministic bridge** —
    the orchestrator no longer hand-assembles the manifest JSON. An earlier EPIC (E-065-1_7)
    moved the entire manifest-construction contract into `aid-c3-dispatch.sh build-manifest`:
    allowlist derivation (from `$AID_CHANGED_PATHS` + this run's evidence artifacts), the per-path
    `input_hash`, the `required_independence_level` lookup against `c3-audit-policy.yaml`,
    `prior_pass_summaries: "untrusted"` (D2), the Codex brief files, and the schema-conformant
    emit of `audit-input-manifest.json`. Call it instead of doing any of that by hand:

    ```bash
    # base_sha = base_commit from fsm-state.yaml (the EPIC's run-start commit);
    # head_sha = current HEAD; risk_profile from step 4a's review-profile.json.
    risk_profile=$(jq -r '.review_profile.risk_profile // "unverifiable"' \
      "$evidence_dir/review-profile.json" 2>/dev/null || echo "unverifiable")

    # Only when C3 is required for this risk profile. For docs_trivial/low/medium the
    # profile is NOT a C3 key — do NOT call the bridge; skip to step 6, which dispatches
    # the Auditor in legacy_health mode instead.
    bash "$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh" build-manifest \
      "$evidence_dir" "$base_sha" "$head_sha" "$risk_profile"
    ```

    `build-manifest <evidence_dir> <base_sha> <head_sha> <risk_profile>` (exactly 4 positional
    args) writes the Codex brief files under `$evidence_dir/c3/` and the canonical manifest at
    `$evidence_dir/audit-input-manifest.json`, conforming to
    `defaults/schemas/audit-input-manifest.schema.json`. It resolves the required independence
    level from `c3-audit-policy.yaml` internally, so the prose no longer computes it separately.
    A non-C3 risk profile (`docs_trivial`/`low`/`medium`) does not require C3 — the orchestrator
    skips this hook entirely and lets step 6 select `legacy_health`.

    **Gate:** DONE Closure Checklist row `2a` requires `audit-input-manifest.json` present, with
    an `input_hash` that a fresh recomputation over `allowlist[]` reproduces, before step 6's
    `c3` dispatch proceeds.

    **Consumed by:** step 6's `c3` branch — `aid-c3-dispatch.sh dispatch` reads this manifest to
    seal the Codex brief and drive the real Codex CLI, and `aid-c3-dispatch.sh verify` re-hashes
    it to prove `audit-report.json` is a faithful transform of the manifest + Codex response. In
    `legacy_health` mode the manifest is never built and `agents/auditor.md` runs its trust-based
    health audit instead.
6. **Serial dispatch (E-057-2_2):** first resolve the Auditor dispatch mode **mechanically**
   (not by prose judgment) from the profile produced in step 4a:
   ```bash
   audit_mode="$(bash "$AID_PLUGIN_PATH/scripts/lib/aid-audit-mode.sh" "$evidence_dir")"
   # → "c3" (independent audit) or "legacy_health"; a missing profile prints "c3"
   #   and exits 3 (fail-closed direction) — treat as c3.
   ```
   The two modes dispatch the Auditor **differently**:

   - **`c3` → deterministic bridge, NO `Agent()` for the audit.** Do NOT call
     `Agent(agents/auditor.md)` in this mode. Instead run the bridge over the manifest built in
     step 5:
     ```bash
     AID_C3_ATTEMPT=1 bash "$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh" dispatch "$evidence_dir"
     bash "$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh" verify   "$evidence_dir"
     ```
     `AID_C3_ATTEMPT=1` (P065 Step 17) layers this call's raw evidence under
     `c3/attempt-01/` and atomically copies its report to the canonical evidence-root path used
     everywhere else in this section — the FIRST, INITIAL dispatch is always attempt 1, even
     when the loop below never fires. `verify` is unaffected by the env var; it always reads the
     canonical evidence-root report.
     `dispatch <evidence_dir>` (exactly 1 positional arg) probes cross_provider availability for
     THIS run, invokes the real Codex CLI read-only, and writes `c3/c3-dispatch.json` plus
     `audit-report.json`/`.md`. `verify [--reference] <evidence_dir>` (1 positional arg, optional
     leading `--reference` flag) re-checks the codex provenance chain and proves
     `audit-report.json` is a faithful, deterministic transform of Codex's raw response.
     **On `dispatch` exit 2** (non-dispatched / unavailable / rate_limited / timeout) the bridge
     has ALREADY written a minimal `unverifiable` `audit-report.json` (a bridge-owned placeholder,
     never a pass) and `c3/c3-dispatch.json` records the real Codex outcome
     (`unavailable`/`rate_limited`/`timeout`). A missing / non-executable bridge script is treated
     the same as any other dispatch failure → `status: unverifiable`. Read policy
     `c3_on_unavailable` (`c3-audit-policy.yaml` → `c3_executor.c3_on_unavailable`) to decide what
     happens next — there is **no fallback to a `c3` pass** either way; the pipeline never
     substitutes the Claude auditor for a `c3` pass:

     - **`c3_on_unavailable: unverifiable`** — skip any further dispatch entirely. The
       orchestrator simply surfaces the bridge's minimal `unverifiable` report (step 12), nothing
       more to do.
     - **`c3_on_unavailable: degraded_advisory`** (shipped default — P065 Step 15, the plan's
       final flip) — dispatch the `c3_advisory` auditor as a **same-provider Claude fallback**,
       still never a `c3` pass:
       ```
       Agent(agents/auditor.md, {
         mode: "c3_advisory",
         provider: "claude-code",
         model: "<this session's configured model>",
         process_id: "advisory-<run_id>",
         evidence_dir: "$evidence_dir",
         manifest: "$evidence_dir/audit-input-manifest.json"
       })
       ```
       **The pipeline OWNS `provider`/`model`/`process_id`** — inject them into the dispatch
       input; `agents/auditor.md`'s `c3_advisory` mode only ECHOES them into the envelope (the D7
       contract "C3 Advisory Mode" documents) and HALTs if any of the three is missing from its
       input. Never let the advisory auditor self-identify these fields.

       **Artifact ownership on the advisory path.** The advisory auditor OVERWRITES
       `audit-report.json`/`.md` with the richer advisory report — still `status: unverifiable`,
       `.audit_report.advisory: true`, `.audit_report.independence_level: "context_only"`,
       findings present — so Curator/PM can consume the findings (never a `pass`, never
       `cross_provider`/`cross_model`). `c3/c3-dispatch.json` is left **UNTOUCHED** — it still
       records the real Codex `outcome: unavailable/rate_limited/timeout`, preserving the truth
       that Codex did not run and this report is advisory, not a real dispatch. Consequently
       `aid-c3-dispatch.sh verify` on an advisory report exits 2 (no dispatched provenance to
       verify against) — this is CORRECT: advisory reports never verify via the bridge, that is a
       documented, orthogonal path, not a bug.

       **Error handling.** If the `Agent()` advisory dispatch fails or returns nothing usable, the
       bridge's minimal `unverifiable` report stays on disk (never overwritten by an empty
       advisory); log `advisory_dispatch_failed` and continue to step 12 with the bridge's plain
       unverifiable report. If `c3_on_unavailable: degraded_advisory` but the `c3_advisory` mode
       is somehow unavailable, fall back to the plain `unverifiable` report (never a silent pass)
       and log `c3_advisory_unavailable`.

     Either branch: the merge-gate consequence (blocking vs observe per `c3-audit-policy.yaml`) is
     handled by the `aid-fsm.sh done-advance` C3 hook, not here. An advisory report's
     `.audit_report.advisory: true` (or `independence_level: "context_only"`) is a NEW block
     reason that hook recognizes — `c3_advisory_not_independent` — strictly additive to its
     existing `status == "unverifiable"` check, never a replacement for it.
   - **`legacy_health` → UNCHANGED.** Auditor (`agents/auditor.md`) dispatches via its own
     `Agent()` tool call in `legacy_health` (trust-based health-audit) mode. The bridge is never
     invoked at all for `docs_trivial`/`low`/`medium` profiles.

   **6a. C3 fix→reverify loop (P065 Step 16).** `c3` mode only — `legacy_health` never enters
   this loop (Curator dispatches immediately after it, as before). Runs after the `c3` branch's
   `dispatch`+`verify` above, BEFORE Curator dispatches (Curator must consume the loop's FINAL
   `audit-report.json`, never an intermediate attempt). This closes the CP5 gap: previously a
   blocking C3 finding only got flagged in the PM Summary (step 12) and the PM decided ABORT
   manually — C3 now gets the same bounded auto-repair loop CP2/CP3 already have
   (`review-checkpoints.yaml` `fix_loop.max_iterations: 2`), read here from
   `c3-audit-policy.yaml` → `c3_fix_loop` (`max_rechecks: 4`, `eligible_severities: [critical,
   high]`; policy unreadable → fail-closed to `max_rechecks: 4`). Initial audit + up to 4
   rechecks = 5 genuinely dispatched Codex sessions (P073 Step 1).

   **Entry condition:** the report is genuinely `dispatched` (a real Codex run — check
   `c3/c3-dispatch.json` `.dispatch.outcome == "dispatched"`, NOT the `degraded_advisory`
   fallback) AND `audit-report.json` `.audit_report.blocking_findings == true` with at least one
   finding whose severity ∈ `c3_fix_loop.eligible_severities`. A clean first audit (no blocking
   findings) never enters the loop — 0 extra Codex runs.

   **Not a loop iteration.** A `dispatch` returning `unavailable`/`rate_limited`/`timeout`/
   `invalid_output` is the EXISTING `unverifiable` (+ step 6's `degraded_advisory` fallback)
   path, not this loop — `c3_recheck_count` is NOT incremented and no gate-fixer/implementer
   runs (there is no finding to fix; Codex did not audit). Do not conflate the two paths.

   **Loop body** (while blocking AND `c3_recheck_count < max_rechecks`):
   1. Dispatch gate-fixer (S/M effort) or implementer (L effort) to fix the SPECIFIC blocking
      finding(s) by `fingerprint` — a targeted fix, never a general rewrite — producing a new
      commit → new HEAD.
      - Fix dispatch fails, or produces no diff (new HEAD identical to prior HEAD) → exit the
        loop to **ESCALATION** immediately (cannot make progress / would re-audit the identical
        HEAD).
   2. Re-run the bridge on `base_sha..newHEAD` for a fresh, isolated Codex pass — this is
      "recheck N":
      ```bash
      bash "$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh" build-manifest \
        "$evidence_dir" "$base_sha" "$newHEAD" "$risk_profile"   # new codex_brief_hash
      AID_C3_ATTEMPT=$((c3_recheck_count + 2)) \
        bash "$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh" dispatch "$evidence_dir"   # NEW
      # isolated codex exec — a genuinely new codex_session_id, never the prior attempt's
      bash "$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh" verify   "$evidence_dir"
      ```
      `AID_C3_ATTEMPT` (P065 Step 17) is `c3_recheck_count + 2` — at this point in the loop body
      `c3_recheck_count` still holds the count of rechecks ALREADY COMPLETED before this one (the
      increment in step 3 below happens AFTER this dispatch), so on the first loop entry
      (`c3_recheck_count == 0`) this recheck is attempt 2 (attempt 1 was the initial dispatch
      above); the second loop entry (`c3_recheck_count == 1`) is attempt 3; etc. — this layers
      each attempt's raw evidence + report under its own `c3/attempt-NN/` (preserving the full
      repair history for audit) while atomically copying the LATEST attempt's report to the
      canonical evidence-root path — the CANONICAL, i.e. last-attempt, report that `aid-fsm.sh`
      and Curator read (see the matching confirmation there). `verify` (unprefixed, no
      `AID_C3_ATTEMPT`) always checks the canonical path; `verify --reference
      "$evidence_dir/c3/attempt-NN"` checks a specific historical attempt directly.
   3. `bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" set-field c3_recheck_count <n> "$state_file"`
      (increment). Then re-evaluate blocking status on the new `audit-report.json`:
      - Still blocking AND the SAME finding `fingerprint` survived this recheck (fix
        ineffective) → **ESCALATION** immediately — do not burn the remaining budget on a
        non-converging fix. `dispatch`/`_c3_write_loop_summary` (P065 Step 17, DONE-review
        round 4) detects this MECHANICALLY — it compares this attempt's blocking-finding
        fingerprints against the immediately-prior dispatched attempt's and writes
        `c3/loop-summary.json` `outcome:"escalated"` / `escalation_reason:"same_fingerprint_survived"`
        itself; the controller does not need to take any extra action beyond re-checking
        `audit-report.json` as it already does — the terminal-outcome guard (rounds 1-2) then
        rejects any further automatic dispatch on its own.
      - Still blocking AND the findings are mutually conflicting (a controller judgment call
        the bridge cannot make mechanically) → **ESCALATION** immediately. Unlike the
        fingerprint case, this is NOT auto-detected — the controller MUST durably record it:
        ```bash
        bash "$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh" escalate "$evidence_dir" \
          "<reason, >=20 chars — what conflicts and why>"
        ```
        This writes the same `outcome:"escalated"` (`escalation_reason:"conflicting_findings"`)
        that the fingerprint case writes automatically, so it is picked up by the exact same
        terminal guard. Skipping this call is a Detector-without-Enforcement gap (see
        `docs/plans/AID-v3-principles.md` §1) — the controller's own prose judgment would
        otherwise never be durably recorded, leaving a later stray dispatch free to reopen the
        loop.
      - Still blocking, fingerprint(s) differ and findings do not conflict (a fix introduced a
        NEW critical/high finding — counts against this SAME budget, never a fresh one) → loop
        again if `c3_recheck_count < max_rechecks`, else fall through to the budget-exhaustion
        exit below.
      - Clean (no blocking findings) → exit the loop, proceed to Curator dispatch / merge
        decision.

   **Exit conditions (exactly one applies):**
   - **Clean** → proceed to Curator dispatch (step 6's closing paragraph) and the merge
     decision as normal.
   - **`c3_recheck_count == max_rechecks (4)` and still blocking** → **ESCALATION**: surfaced to
     the PM in step 12's summary as blocking (never silently merged); a 5th recheck / 6th total
     Codex run is PM-approved only, never automatic re-entry into this loop.

     **THE PM route is** `aid-fsm.sh pm-override grant c3 <plan_id> --reason "<text, >= 20
     chars>"`, which writes a single-use `c3-pm-escalation-override.json` that the exhaustion
     gate claims ATOMICALLY — one grant authorises exactly one further attempt (P073 Step 10,
     the same mechanism C0 uses). **Agents never create this artifact and never set an override
     environment variable.** The legacy `AID_C3_FORCE_BEYOND_ESCALATION` still works for one
     more release: it is converted into the same single-use artifact with a deprecation warning,
     once per plan, so a lingering export can no longer authorise attempt after attempt.
   - **Same fingerprint survives a recheck** (auto-detected, see step 3 above) **or conflicting
     findings** (controller calls `escalate`, see step 3 above) → **ESCALATION** immediately,
     regardless of remaining budget.
   - A blocking finding NOT in `eligible_severities` (e.g. `medium`) never triggers this loop —
     no auto-fix; surfaced to the PM as before (C3 blocks only on critical/high anyway, per
     `c3-audit-policy.yaml`).

   This EPIC 6 loop stays within the `review` sub-phase — it does not itself invoke
   `aid-fsm.sh transition ... ESCALATION` (the top-level FSM state; no `DONE:ESCALATION`
   transition exists — DONE's `review`/`release` sub-phases are orthogonal to the READY/
   EXECUTE/GATES/ESCALATION state machine in §1–§9). "ESCALATION" here means: the loop stops
   auto-fixing, the FINAL `audit-report.json` (still `blocking_findings: true`) is what
   Curator/step 12 consume, and the PM Summary's existing MERGE/FIX/ABORT decision point (step
   12) is where a human actually resolves it — MERGE is not a reasonable option while
   `blocking_findings: true` survives the loop, matching the existing "⛔ CRITICAL FINDINGS
   (block merge)" convention already in the summary template below.

   In **both** modes (after 6a resolves, for `c3`; immediately, for `legacy_health`) the
   Auditor output is FINAL before Curator dispatches; only after it completes does Curator
   (`agents/curator.md`) dispatch, via a separate `Agent()` tool call, consuming the Auditor's
   `audit-report.json` output (Curator hashes its content into `.curator.audit_report_ref` —
   `aid-fsm.sh done-advance` verifies this ref against a fresh `sha256sum` of the file and blocks
   release on mismatch). Curator's serial-after-Auditor dispatch pattern is identical regardless
   of how the `audit-report.json` was produced.
7. **Wait:** Auditor (and, for `c3`, the 6a fix→reverify loop) must complete before Curator
   dispatches; Curator must complete before continuing
8. **Curator auto-fix:** Gate-fixer applies approved proposals at **every effort level (S, M, L)**.
   Tier 2 default: S/M/L all approve; only an explicit `always_defer` rule (architecture,
   standards-L) defers.
9. **Auditor auto-fix:** Gate-fixer applies S/M/L effort items from auditor
   `recommended_fixes` (where `auto_fixable: true`).

   **Invalidation-Map call site 4/5:** capture `pre_fix_ref` before dispatching the gate-fixer in
   steps 8–9; after the curator/auditor auto-fixes are applied, run the **Invalidation-Map Post-Fix
   Hook** (§13, observe-only) with `fix_ref=done-curator` / `fix_ref=done-auditor` respectively.
10. **CP4:** Verifier (`code-review`) reviews the **applied** curator + auditor changes from
   steps 8–9 (it runs AFTER the fixes are applied, so it actually reviews them).
   If FAIL → revert those changes, log reversion.
   Skip per `review-checkpoints.yaml` (`cp4_curator_validation`).

   **Dispatch protocol:** in `agent_tool` mode (default), call `Agent()` directly.
   In `subagent` mode only: wrap with `aid-emit-dispatch.sh` start/complete pair
   (`--focus "cp4-curator-validation"`), identical to CP2/CP3:
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start \
     --focus "cp4-curator-validation" \
     --agent-id "aid-orchestrator:verifier" \
     --evidence-dir "$evidence_dir"
   # Agent({subagent_type: "aid-orchestrator:verifier", description: "CP4 curator validation", ...})
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete \
     --focus "cp4-curator-validation" \
     --output-file "$evidence_dir/verifier-output-cp4-curator-validation.md" \
     --evidence-dir "$evidence_dir"
   ```
   `fsm_check_cp4_curator_validation` (Component C) requires
   `verifier-output-cp4-curator-validation.md` when `curator-report.md` exists and
   any commit in `base_commit..HEAD` touched production code; mode-aware skip
   (`cp4_skipped_streamlined_advisory`) when `streamlined_mode` is true.
11. **CP5** (`legacy_epic_release_mode`, and `plan_branch` only when a mid-plan Auditor
    actually ran under a recorded `mid_plan_specialist_review_exception`)**:** Check
    auditor `blocking_findings` flag. If `true` → flag in summary (critical findings block
    MERGE option). Skip per `review-checkpoints.yaml`. On an intermediate `plan_branch`
    EPIC with no Auditor dispatch there is no flag to read and CP5 is a no-op — do not
    manufacture one, and do not treat its absence as a failed checkpoint. (The FSM's own
    retained read behaves the same way: a present `audit-report` blocks on a non-`false`
    verdict; an absent one is silence.)
12. **PM Summary** (always shown, even in FIRST AID mode):

```
DONE REVIEW — {epic_id}
{outcome in one plain sentence: what this EPIC now does for the PM}
Changed: {1-3 user-relevant effects}
Verified: {pass}/{total} gates pass; auditor {overall}/100 (trend: {delta} vs previous)
         {or the concrete reason something is unverified}
Next step: {the one recommended option below, with its one-line reason}

{if blocking_findings:}
⛔ CRITICAL FINDINGS (block merge):
  1. [{audit_type}] {finding} — effort: {S|M|L}
     Recommendation: {recommendation}
  Audit report: .aid-o/work/evidence/{epic_id}/{run_id}/audit-report.md

Detail — steps {done}/{total} | gates {pass}/{total} | duration {time}
  Auditor: Code {score} | Security {score} | Docs {score} | Process {score}
  {if audit mode was c3 — read from audit-report.json:}
  C3 Independence: {independence_level} achieved / {required_independence_level} required
    {if status == unverifiable:} ⚠️ status: unverifiable — {reason}
  Curator: {applied} fixes applied (S/M/L), {deferred} deferred
    Applied: {list of applied proposals with IDs}
    Deferred: {list — always-defer rules (architecture, standards-L) or rejected — PM can approve in backlog}
  Auto-fixes: {count} applied from auditor recommendations
    {list of fixes with file paths}

Key outputs: {artifact list}

Options (`legacy_epic_release_mode`):
  MERGE — release + merge to main + queue pickup
  FIX   — provide guidance, re-run review cycle
  ABORT — stop EPIC, no merge (/aid-stop)

Options (`plan_branch`):
  MERGE — merge this EPIC into the PLAN branch. No release, no tag, no push:
          the release happens once, later, at the plan-final boundary.
  FIX   — provide guidance, re-run review cycle
  ABORT — stop EPIC, no merge (/aid-stop)
```

This is the **Finished** card of `skills/communication.md` applied to DONE (the
**Blocked or failed** card replaces it when the review ends in a blocker the PM
must resolve): the outcome sentence leads, and every counter, score, report path
and evidence dir sits on or below the `Detail —` line. `commands/aid-run.md`
shows the same shape abridged — keep the two in step.

> **PM machine handoff (D11 — E9).** Independently of this human summary, once the FSM advances
> review→release (step 13 below), a deterministic PM brief is generated from `release-decision.json`
> (see **§7.6 PM Machine Handoff** below). The brief is generated after EVERY successful
> `done-advance review→release`, **including `--auto` / FIRST AID mode** — the machine
> `pm-decision-brief.json` + human `pm-summary.md` always land on disk (carrying the full
> evidence/Reporter/Simplifier/waiver status) so an auto-merge is never silent. Honest limitation:
> in E9 this is a convention, not a structural guarantee — see §7.6.

> **C3 `unverifiable` in the summary.** When the `c3` audit came back
> `status: unverifiable` (Codex could not be dispatched — see step 6), the summary shows that
> status with its `reason`, and the PM is still offered MERGE / FIX / ABORT below. Under the
> shipped default `enforcement: observe` (`c3-audit-policy.yaml`) the unverifiable verdict is
> **advisory** — the FSM `done-advance` C3 hook emits telemetry but does not block, so the PM is
> not forced to ABORT merely because C3 was unverifiable. Only under `enforcement: blocking` does
> that hook turn the unverifiable report into a hard merge-gate.

> **Advisory findings labelled distinctly (P065 Step 15).** When `audit-report.json` carries
> `.audit_report.advisory: true` — the `degraded_advisory` same-provider Claude fallback from
> step 6 — the PM summary above labels every finding from it **"advisory (Claude, not independent)"**,
> distinct from a genuine `c3` cross-provider/cross-model verdict, and still
> shows `status: unverifiable` (an advisory run is never a pass, regardless of how clean its
> findings look). Under `enforcement: blocking` the FSM `done-advance` C3 hook blocks with
> `c3_advisory_not_independent`; under the shipped `enforcement: observe` default it emits
> `c3_gate_would_block` telemetry only, matching the existing `unverifiable`-handling convention
> immediately above — same enforcement toggle, same telemetry event, just a more specific reason.

12. **PM decides:**
    - **MERGE** → set `pm_decision`, advance sub-phase, continue to step 13
    - **FIX** → PM provides guidance → dispatch fixes → re-run steps 5-11
    - **ABORT** → transition to ERROR (`status: aborted`, E8 logged)
13. **Advance to release sub-phase** (mechanically enforced):
    ```bash
    aid-fsm.sh set-field pm_decision merge <state_file>
    aid-fsm.sh done-advance review release <state_file>
    ```
    Preconditions in `legacy_epic_release_mode`: `curator-report` exists, `audit-report`
    exists, `pm_decision=merge`. If any missing → script refuses (exit 1).

    In `plan_branch` mode the Curator/Auditor/CP3/CP4/C3/C4 preconditions do not apply —
    the FSM skips that whole stack and emits a `done_advance_plan_branch_mode` timeline
    event naming every skipped stage. `pm_decision=merge`, the streamlined integration
    review, the abandoned check, DG-07 and tiered-severity compliance still apply in both
    modes. An **unresolvable** mode is a hard `plan_mode_unresolved` block, never a
    fallback: guessing legacy here would route you into merging a single EPIC into the
    target branch, which is exactly what `plan_branch` exists to prevent.

### §7.6 PM Machine Handoff — release-decision → PM brief (D9 coexistence)

The PM handoff is a two-artifact machine sequence produced at the review→release boundary. It is
the new **canonical machine handoff** for a release decision; the older human artifacts coexist
(see *Coexistence* below).

**Topology sequence (produced in this order):**

1. **`release-decision.json`** — the C4 aggregator (`aid-release-policy.sh`) emits the protocol-v2
   `release_decision` artifact carrying `release_ready`, `blockers`, `waivers_applied`, and the D11
   state fields (`merge_mode`, `evidence_verification_status`, `evidence_verified_at_head`,
   `reporter_status`/reason, `simplifier_status`/reason, `summary_for_pm`, `delivered_summary_ref`,
   `pm_brief_required`, `pm_brief_status`). In a live run this is produced by the FSM dual-run hook
   during `done-advance review→release`.
2. **`pm-decision-brief.json` + `pm-summary.md`** — `aid-pm-brief.sh <evidence_dir>` reads ONLY
   `release-decision.json` (no sibling files — not `epic-summary.md`, not `final_report.md`) and
   echoes its state into the protocol-v2 `pm_decision_brief` artifact plus a human `pm-summary.md`,
   then patches `pm_brief_status` back into `release-decision.json`
   (`generated`/`failed`/`incomplete`). Pure bash/jq, deterministic, no LLM.

   ```bash
   # Dispatch ONLY after a SUCCESSFUL done-advance (exit 0):
   bash "$AID_PLUGIN_PATH/scripts/aid-pm-brief.sh" "$evidence_dir"
   ```

   **Brief dispatch is gated on a SUCCESSFUL done-advance (exit 0).** We never want a `generated`
   brief that describes a non-zero-exit attempt. This is NOT "every failed attempt reaches C4" —
   that is false: class-2 hard-exit blocks (tiered-compliance `exit 2`, streamlined-integration,
   cp4-curator) preempt the transition BEFORE the C4 slot and emit `release_policy_preempted`
   (observe-only telemetry in `aid-fsm.sh`), so no `release-decision.json` is produced for them.
   After a fix + retry the brief is generated then — the retry either overwrites the existing
   `release-decision.json` (class-1 blocks that reached the C4 slot) or creates the first one
   (class-2 hard-exits).

3. **(Deferred E10) `--validate` blocks MERGE.** `aid-pm-brief.sh --validate` already fails closed
   when the brief does not faithfully echo the decision (catches over-optimism / tampering), but
   wiring that verdict as a *merge precondition* is **explicitly deferred to E10** — see *Honest
   limitation* below.

4. **Presentation layer — `scripts/lib/aid-plan-close-summary.sh`.** At the plan-final / close
   boundary of a `plan_branch` plan the controller renders the PM's card and artifact body from
   the handoff pair, instead of listing files:

   ```bash
   source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-close-summary.sh"
   aid_plan_close_render "$evidence_dir/pm-decision-brief.json" \
                         "$evidence_dir/release-decision.json" "$plan_id" "$evidence_dir"
   ```

   Publish the artifact body via the Artifact tool, then present the chat card verbatim.

   The card shapes are the ones `skills/communication.md` defines — Decision-required when the plan
   is not release-ready or `merge_mode` is not `auto`, Finished when recording a completed close.
   The renderer reads ONLY those two files (the same `release-decision.json` the brief was generated
   from, no sibling evidence), so the D6/D9 cycle-break holds. `aid-pm-brief.sh`, `pm-summary.md` and
   the plan-finalize labelled-fields guard are UNTOUCHED by this layer — it adds a rendering, never a
   second source of truth.

   It fails CLOSED, exit 1, when the brief lacks any of its eight required fields or the decision
   carries no `.release_decision.plan_summary` (every EPIC-mode decision does not) — no page is
   written at all. If the brief is absent at the boundary, report the Blocked card
   "plan-close brief missing — run aid-pm-brief.sh"; never improvise a plan summary from evidence
   files, which is exactly the cycle `aid-pm-brief.sh` exists to break. Under
   `legacy_epic_release_mode` this layer does not apply — the per-EPIC release keeps its existing
   text and is never retroactively re-shaped.

**Coexistence (D9 narrowing).** `pm-decision-brief.json` / `pm-summary.md` are the new canonical
machine handoff. The pre-existing PM outputs remain, unchanged, alongside it: `final_report.md`
(per-run), `epic-summary.md` (`aid-epic-summary.sh`, same transition), and the Reporter
`{plan_id}-delivery.md` (plan boundary). **Consolidating these into one surface is E11** — E9 adds
the canonical machine handoff without removing anything, so nothing that reads the older artifacts
breaks.

**D11 — brief generated after every successful done-advance.** The brief is generated after EVERY
successful `done-advance review→release`, **including `--auto` / FIRST AID mode**. The intent: an
auto-merge is never silent — the machine brief and its human summary always exist on disk, carrying
the full evidence/Reporter/Simplifier/waiver status even when the merge proceeds automatically.

**⚠️ Honest limitation (CP1 L1-F2) — in E9 "auto-merge never silent" is a convention, NOT a
structural guarantee.** Nothing structurally blocks a merge that lacks a brief: no FSM precondition
consumes `pm_brief_required` or `merge_mode=auto` to gate the merge (`grep pm-brief
scripts/aid-fsm.sh` = 0 hits). In `--auto` the orchestrator could theoretically skip the brief step
and the merge would still proceed with `pm_brief_status: pending`. `pm_brief_required` is an E9
**forward-compat** field. E9 delivers the *field + generator + patch-back* only; the *enforcement*
("merge without a brief does not proceed" — item 3 above) is **E10**. This is deliberate phasing per
[`AID-v3-principles.md`](../../../docs/plans/AID-v3-principles.md) §1 (*Detector without Enforcement
is Decoration*): until the enforcement lands this is a detector, named as such — not omitted. A
`pm_brief_status` that stays `pending` after a completed release transition is itself a finding (the
live-probe C4 observability contract treats a missing brief on an auto-merge as a finding, not a
skip).

### Sub-phase: `release`

**Steps 14-16 fork on the plan's declared release mode.** Read the mode before you do
anything in this sub-phase — it decides where this EPIC's work lands:

```bash
yq -r '.mode // "legacy_epic_release_mode"' .aid-lifecycle/manifests/{plan_id}.yaml
```

The FSM already resolved the same value during `done-advance review release` and recorded
it as a `done_advance_plan_branch_mode` timeline event (payload `skipped_stages[]`). If
`done-advance` exited non-zero with `plan_mode_unresolved`, **stop** — do not run either
branch below and do not guess. Repair the manifest on the target branch first.

#### `plan_branch` mode — an INTERMEDIATE EPIC completion

The per-EPIC release stack does not run here. There is no version bump, no tag, no push,
no target-branch merge and no plan-final release decision — those belong to the plan-final
run (P068). The FSM enforces the skip structurally; these instructions must match it.

14. **No release automation.** Do **not** call `aid-release.sh`, do not bump a version, do
    not tag, do not push, and do not refresh the plugin cache. A version bump per EPIC
    would advertise a release the plan has not made.
15. **Complete the EPIC, then merge it into the plan branch** — two commands, in this
    order, never a raw `git merge`:
    ```bash
    bash {plugin_path}/scripts/aid-plan-fsm.sh epic-complete {plan_id} {epic_id} \
      --project-root {project_root}
    bash {plugin_path}/scripts/aid-plan-fsm.sh epic-merge-to-plan {plan_id} {epic_id} \
      --project-root {project_root}
    ```
    `epic-complete` records this EPIC's contribution to the plan-final gate floor and marks
    the manifest entry pending merge. `epic-merge-to-plan` merges `task/{epic_id}/main`
    into `plan/{plan_id}` only — the target branch never moves. Handle the exit codes:

    | Exit | Meaning | What the controller does |
    |------|---------|--------------------------|
    | 0 | Merged, or already converged | Continue to step 16 |
    | 1 | Precondition failed (state not DONE, `lineage` not `proven`, unproven merge, dirty worktree, stale `--expected-plan-sha`) | Stop. Report the printed reason to the PM. Never re-run with a weakened check |
    | 2 | Usage error | Fix the invocation and re-run |
    | 3 | Lock held by a concurrent plan operation | Retry once the holder finishes |
    | 4 | Real Git conflict — the plan is now `CONFLICT` | Resolve on `plan/{plan_id}`, then re-run; the command is reconcilable |
    | 5 | Divergence between recorded and actual state | Stop. Do not repair by hand — `plan-state --repair` marks entries `lineage: unproven` for a reason |

15a. **Do NOT call `plan-record-delivery` here.** The hook writes the `.aid-lifecycle/`
    delivery bindings and hard-refuses to run off the target branch — which in
    `plan_branch` mode is never where an EPIC merge lands. Its responsibility moves to
    `plan-merge-to-main` (P068), which writes every binding in one pass after the plan
    branch reaches the target branch and a real target-branch merge SHA exists. **Skipping
    it without that relocation is not optional bookkeeping:** `aid_lifecycle_plan_close`
    refuses while any required EPIC lacks a binding, so a plan-branch plan would otherwise
    be permanently unable to close.
15b. **Report to the PM, in these words:** "EPIC complete and merged into
    `plan/{plan_id}`; plan remains open; no plan-final release decision has run yet."
    Do not describe this as a release, a delivery or a merge to `{target_branch}`.
16. **Queue — mirror the merge FIRST, then claim the next entry.** Two calls, in this
    order, through the plan-aware writer; never edit `queue.yaml` by hand:
    ```bash
    # 16a — mirror into the queue the merge step 15 just proved in Git.
    bash {plugin_path}/scripts/lib/aid-queue-write.sh set-status \
      {epic_id} merged_to_plan --project-root {project_root}

    # 16b — claim the next entry of THIS plan.
    bash {plugin_path}/scripts/lib/aid-queue-write.sh claim-next {plan_id} \
      --project-root {project_root}
    ```
    **16a is not optional bookkeeping — without it a multi-EPIC plan stalls at its
    second EPIC.** `epic-merge-to-plan` leaves the queue entry at `running`. When the
    dependency entry carries no `merge_target` — the shape `aid-queue-add.sh` writes
    whenever `plan/{plan_id}` did not yet exist at queue-add time, which is the normal
    ordering in `aid-auto-pipeline.sh` — `claim-next` resolves that dependency from its
    STATUS, sees `running`, and durably records
    `blocked:{next_epic_id}:dependency_unmerged:{epic_id}` on the dependent. The work is
    provably contained in `plan/{plan_id}` and provably absent from `{target_branch}` —
    exactly the state the plan exists to create — and the hand-off refuses it anyway.

    **A queue entry is a DERIVED VIEW, never evidence.** 16a mirrors the ancestry fact
    step 15 established in Git; it does not create it. For an entry that DOES carry a
    `merge_target`, `claim-next` proves readiness with a live
    `git merge-base --is-ancestor` check and ignores the status field entirely — so 16a
    can never unblock anything that did not really merge.

    | Exit | `set-status` (16a) | `claim-next` (16b) |
    |------|--------------------|--------------------|
    | 0 | Status written | Prints the claimed `<epic_id>` |
    | 1 | No such entry, or the entry sits in a terminal status (`released_to_main` / `abandoned` / `superseded`) — **nothing was written**. Stop: an EPIC that just merged cannot be terminal, so the queue and the manifest disagree. Report it; never hand-edit the queue to force agreement | Prints `blocked:<epic_id>:<reason>` (no dependency is ready) or `none` (no candidate entry for this plan). `none` after the last EPIC is the normal end of the plan |
    | 2 | Usage/validation — bad `epic_id`, a status outside the writable enum, or a `reason` outside the allowed charset. Nothing written; fix the invocation | Bad `plan_id` |
    | 3 | Lock unavailable, or a write that had to be durable was not. Retry once the holder finishes — never proceed as if it succeeded | Same |

    ⚠️ **Honest wiring status:** `queue_set_status` / `queue_claim_next` /
    `queue_set_plan` ship as a library only — **no production caller invokes them yet**,
    which is why the enforcement registry records the writer `status: planned`.
    `aid-plan-fsm.sh` does NOT write the queue: `epic-merge-to-plan` moves Git and the
    plan manifest and stops there. Until a later step (P068) wires these calls into it,
    the controller invokes the library directly as shown above — that is why 16a exists
    as its own explicit step rather than being described as a side effect of step 15. Do
    not describe queue pickup as automatic in `plan_branch` mode.

#### `legacy_epic_release_mode` — the per-EPIC release ritual

> **This ritual is NOT the default any more.** Since P068 Step 7 the default mode
> for a new plan is `plan_branch` whenever the project declares a `gate_profiles`
> table (`defaults/policies/plan-boundary-policy.yaml`, resolved by
> `aid-plan-fsm.sh __default-mode`); without that table it falls back here and
> says so with `plan_branch_unavailable: no_gate_profiles`. Everything in this
> subsection applies only when the plan's committed lifecycle manifest declares
> `mode: legacy_epic_release_mode`. In `plan_branch` the EPIC merges into the
> plan branch and nothing is released, tagged or pushed until the plan-final
> boundary.

14. **Release:** Call `aid-release.sh` — version bump
    - Standalone/last EPIC: mandatory bump
    - Intermediate EPIC: defer (auto-mode) or ask PM (manual mode)
15. **Branch merge:** `git merge task/{epic_id}/main --no-ff -m "feat: complete EPIC {epic_id}"`
    → delete run branch
15a. **Record delivery (IMP-232 v2.58.1 — post-merge, on the target branch):**
    ```bash
    bash {plugin_path}/scripts/aid-fsm.sh plan-record-delivery {epic_id} {project_root}
    ```
    This is the single, named post-merge hook. Run it IMMEDIATELY after step 15,
    on the target branch. It records THIS EPIC's delivery SHA + review provenance
    into the git-tracked lifecycle manifest (isolated index — your staged/working
    changes are untouched), and if this was the last **required** EPIC now
    delivered + review-accepted, it writes the closure receipt and the plan becomes
    `closed`. Metadata-only; never edits the plan or the merge. A merged EPIC whose
    historical review is unverifiable is recorded `delivery: delivered, review:
    unverifiable` — the plan stays `active`, never falsely closed. (Pre-merge
    `plan-close` at step 9 only verifies reviews + keeps the `ca-review-complete`
    marker; it does NOT write a delivery SHA or a tracked commit on the task branch.)
16. **Queue:** Read `config/queue.yaml` → auto-pickup next EPIC if queued.
    Metrics stored to Qdrant (`aid-orchestration-log`) or fallback JSONL.

**Auto-mode (FIRST AID) in `legacy_epic_release_mode`:** If no `blocking_findings` and
auditor score ≥ 80 → auto-MERGE. If `blocking_findings` or score < 80 → show summary,
require PM decision.

**Auto-mode (FIRST AID) in `plan_branch` mode:** There is no auditor score and no
`release-decision.json` for an intermediate EPIC — the specialists are plan-final. Applying
the legacy rule here would fall through to "require PM decision" on every intermediate
EPIC, defeating the autonomy the mode exists for. Evaluate instead, from artifacts an
intermediate EPIC really has:

1. `done-advance review release` exited 0 (it already enforced `pm_decision=merge`, the
   archived task file, the streamlined integration review, the abandoned check, DG-07,
   tiered compliance and — when a mid-plan `audit-report` exists — `blocking_findings`), and
2. `gates_report.json` → `overall: pass`, and
3. no `audit-report` was produced for this EPIC, or the one that was reports
   `blocking_findings: false`.

All three true → proceed automatically through steps 14-16 (`epic-complete` →
`epic-merge-to-plan` → queue `set-status merged_to_plan` → queue claim; the status write
is step 16a and is never skipped in auto-mode — skipping it blocks the next EPIC). Any
one false → stop and show the summary; the
merge into `plan/{plan_id}` needs a PM decision. **`epic-merge-to-plan` exiting 1/4/5 is
never auto-retried** — report the printed reason as documented in step 15.

**Evidence written (`legacy_epic_release_mode`):**
```
evidence/{epic_id}/{run_id}/
  final_report.md              # Summary (steps, gates, duration, artifacts)
  audit-report.md              # Auditor output
  curator_resolve_report.json  # Curator proposals + actions
  simplifier-report.md         # Simplifier proposals (plan boundary)
  reporter/                    # Reporter test-evidence artifacts (plan boundary)
  release-decision.json        # C4 release decision (protocol-v2 — §7.6)
  pm-decision-brief.json       # PM machine handoff, echoes release-decision (protocol-v2 — §7.6)
  pm-summary.md                # PM human summary, rendered from release-decision (§7.6)
.aid-o/reports/{plan_id}-delivery.md   # Reporter delivery report (committed)
```

**Evidence written (`plan_branch` mode, an intermediate EPIC):** only the per-EPIC
artifacts — `final_report.md`, `gates_report.json`, the CP2/CP3 verifier outputs,
`timeline.jsonl` (carrying `done_advance_plan_branch_mode`), `compliance.json` and
`epic-summary.md`. **None** of `audit-report.md`, `curator_resolve_report.json`,
`simplifier-report.md`, `reporter/`, `release-decision.json`, `pm-decision-brief.json`,
`pm-summary.md` or `{plan_id}-delivery.md` exists yet — they are written once, by the
plan-final run (P068). Do not report a missing one as a gap, and never read the previous
EPIC's copy in its place.

### Telemetry Reference

Full detail for the four telemetry mechanisms summarised in [Telemetry Overview](#telemetry-overview) above.

#### Epic Summary (auto-generated v2.18.0+)

After every successful `done-advance review→release`, `aid-fsm.sh` invokes
`aid-epic-summary.sh generate <evidence_dir>` (best-effort — failure logs a
warning but never blocks release).

Output: `evidence/<epic>/<run>/epic-summary.md` with 5 sections:

| Section | Source |
|---------|--------|
| `✅ Co bylo dodáno` | `git log <base_commit>..HEAD --oneline` |
| `⚠️ Varování a přeskočené kroky` | `timeline.jsonl` — branch events, force_override, gate retries |
| `❌ Co se nestihlo` | `audit-report.md` blocking/L-effort findings, `curator-report.md` deferred |
| `📋 Co dělat dál (PM akce)` | curator deferred proposals (always-defer rules: architecture, standards-L), escalations, force override audit reminder |
| `🔍 Honest signal — PM trust level` | `compliance.json` + heuristics → HIGH / MEDIUM / LOW |

**Trust level heuristics:**
- `branch_correct=false` + `branch` starts with `feature/` → false alarm (feature branch convention); no trust penalty
- `force_override_count > 0` → MEDIUM; audit-log.jsonl review required
- `gate_retries > 0` → MEDIUM
- `compliance.overall = false` → LOW
- All green + 0 force + 0 retries → HIGH

**IMP-089 forward-compat:** if `.aid-o/config/project.yaml` has a `branch_convention:` field, the trust heuristic respects it (even before IMP-089 ships).

#### Compliance Telemetry

After every successful `done-advance` to `release`, `aid-fsm.sh` writes
`evidence/<epic>/<run>/compliance.json` capturing 6 enforcement dimensions:

| Dimension | Session A status | Source |
|-----------|------------------|--------|
| `branch_correct` | measured | `fsm-state.yaml.branch` matches `^task/E-` |
| `execution_yaml_present` | measured | file exists at `<project>/.aid-o/config/execution.yaml` |
| `gates_generated_by` | measured | `gates_report.json._generated_by` field present |
| `memory_substantive` | `null` | Session B/C territory |
| `verifier_outputs` | `null` | Session B territory |
| `dod_present` | `null` | downstream |

`null` ALWAYS means "feature not yet measured by the deployed Session", NEVER
"not applicable". When Sessions B/C deploy, currently-null fields become
`true|false` and the same overall logic remains consistent.

`overall: "pass"` if all checks ∈ {true, null}; else `"fail"`. Plus a
`compliance_written` timeline event is emitted with `deploy_era`, `overall`,
`checks_passed`, `checks_failed` payload.

Aggregator: `bash $AID_PLUGIN_PATH/scripts/aid-compliance-report.sh --since YYYY-MM-DD`
produces a pre vs post comparison table.

Backfill (one-shot post-deploy): `bash $AID_PLUGIN_PATH/scripts/aid-compliance-backfill.sh --deploy-date YYYY-MM-DDTHH:MM:SSZ`
retroactively generates `compliance.json` for existing EPICs with `deploy_era: pre-session-a`
AND stamps missing `created_at:` field into `fsm-state.yaml` (CP1 M2 unblock for mid-FSM EPICs).

Diagnostic: `bash $AID_PLUGIN_PATH/scripts/aid-diagnostic.sh --output md` produces
a forensic frequency table (file counts, branch hygiene, gate authenticity, top
fsm_precondition_fail reasons) — productized version of the Krok 0 analysis.

#### Tiered Severity Enforcement

`cmd_done_advance review release` reads `compliance.json failures[]` and refuses
transition when any failure has `severity: "blocking"`. PM-authorized override
flow:

```bash
aid-fsm.sh done-advance review release <state_file> \
  --force \
  --reason '<≥20 chars explaining why this is acceptable>' \
  --blocked-checks 'check_a,check_b'
```

Override appends an `fsm_force_override` event to `.aid-o/work/audit-log.jsonl`
with `blocked_checks: ["check_a","check_b"]` JSON array, the reason, the
operator (`$USER`), and the timestamp.

**Soft-fail design:** if `yq` is not installed on the host OR `check-severity.yaml`
is missing, `fsm_build_failures` defaults ALL failures to `severity: advisory`.
Release proceeds; no blocking check fires. Install `yq` to enable per-check
severity enforcement (`brew install yq` / `snap install yq`).

**Severity registry:** `.aid-o/config/check-severity.yaml` (shipped by /aid-init).
Initial bootstrap (v2.21.0):

| Check                            | Severity  | Promoted at | Anchor                                                          |
|----------------------------------|-----------|-------------|-----------------------------------------------------------------|
| `verifier_provenance`            | blocking  | 2026-05-13  | P037-1 detector + AID-v3-principles.md §1                       |
| `gates_generated_by`             | blocking  | 2026-05-05  | Session A initial enforcement                                   |
| `plan_ac_match`                  | blocking  | 2026-05-13  | P037-2 plan-diff gate                                           |
| `memory_substantive`             | advisory  | —           | Awaiting empirical track record                                 |
| `dod_present`                    | advisory  | —           | Awaiting empirical track record                                 |
| `epic_compliance_coverage_ratio` | advisory  | —           | Awaiting empirical track record                                 |
| `ai_mechanics_friction_ratio`    | advisory  | —           | Awaiting empirical track record                                 |
| `iteration_density_per_step`     | advisory  | —           | Awaiting empirical track record                                 |

**Promotion ceremony (advisory → blocking):** per AID-v3-principles.md §1
tiered severity caveat, promotion happens when:

1. **Auto-criterion (empirical):** `force_override_rate[check] < 0.05` across
   N≥5 consecutive EPICs where the check ran. Surface via:
   ```bash
   bash $AID_PLUGIN_PATH/scripts/aid-promote-checks.sh --format markdown
   ```
2. **Explicit PM action:**
   ```bash
   aid-fsm.sh promote-check <check_name> --reason '<text ≥20 chars>'
   ```
   Updates `.aid-o/config/check-severity.yaml` in place and appends a
   `check_promoted` event to `audit-log.jsonl` (forensic trail).

Reference: `docs/plans/AID-v3-principles.md §1 — Detector without Enforcement
is Decoration`. P038 (v2.21.0) is the first concrete application of this
principle in AID.

#### Compliance Recovery Alert (P042, v2.29.0+)

Companion to the blocking flow above — the PM gets a signal in both directions:

1. **Block:** when `done-advance review→release` refuses transition on blocking
   failures, the FSM sends a `🛑 <epic>: N blocking compliance failure(s) —
   release blocked` Telegram alert and writes a `fsm_done_advance_blocked`
   timeline event (with the `blocked_checks` list).
2. **Recovery:** on the next successful `done-advance review→release` (zero
   blocking failures), if the last `fsm_done_advance_blocked` event has no later
   `fsm_done_advance_recovered` event, the FSM sends `✅ <epic>: compliance
   cleared, release unblocked. Checks: <list>` and writes a
   `fsm_done_advance_recovered` timeline event.

The recovered event doubles as a **dedup marker** — exactly one recovery alert
per block episode; subsequent clean runs stay silent until a new block occurs.

**Config gate:** `notifications.telegram.alert_on_compliance_recovery` in
`.aid-o/config/execution.yaml` (default `true`). Setting `false` suppresses the
Telegram message only — the `fsm_done_advance_recovered` timeline event is
always written (observable test signal, fixture 7d).

**Soft-fail:** missing timeline.jsonl or `jq` → recovery detection silently
skips (telemetry over correctness, same posture as compliance.json writes).

---

## §8 FAST MODE

**Trigger:** `/aid-do <task>` command.

**What it is:** Single-step EXECUTE without PRE-FLIGHT, plan.json, or gate suite.
Designed for quick tasks that don't warrant a full EPIC.

**LLM behavior:**
1. Log task to `.aid-o/logs/aid-do-log.jsonl` (action: `aid_do_start`)
2. Dispatch single agent (default: sonnet) with task description
3. Verify output (same as §4)
4. **Review Checkpoint CP6:** Pre-filter (§13) runs first on `git diff`.
   If pre-filter clean + trivial → skip. If pre-filter finds pattern → immediate FAIL.
   Otherwise dispatch verifier (`code-review`). Fix loop: gate-fixer → verifier, max 2.
   Advisory only (no ESCALATION in Fast Mode).
   Skip per `review-checkpoints.yaml` (`cp6_fast_mode_review`, `skip_trivial`).
5. Log completion (action: `aid_do_complete`, files_changed, duration_seconds)

**No fsm-state.yaml.** No branch. No gates. No Curator. Quick log only.

If task complexity grows (3+ files, multi-step) → suggest `/aid-plan --epic` instead.

---

## §9 Autonomous Mode (FIRST AID)

**Activation:** `/aid-run --auto` → sets `auto-mode-state.yaml: mode: auto`

**State file:** `.aid-o/work/auto-mode-state.yaml`

**LLM reads mode** at every decision point:
```
mode = read auto-mode-state.yaml → mode field
IF file missing or unreadable → default to "manual" (fail-safe)
```

**Auto-mode overrides:**

| Decision point | Manual | Auto |
|---------------|--------|------|
| READY — plan approval | Ask PM via Slack/chat | Validate JSON schema → auto-GO |
| EXECUTE — review cycle exhausted | ESCALATION | Fresh-approach cycle, then ESCALATION |
| ESCALATION | Options A/B/C | Options A/B/C/D (D = continue manual) |
| DONE — review sub-phase | Ask PM (MERGE/FIX/ABORT) | Guardrail check → auto-approve if pass |
| DONE — PM summary | Show MERGE/FIX/ABORT | Auto-MERGE if no blocking + score ≥ 80 |
| DONE — version bump | Ask PM for intermediate | Auto-defer for intermediate, mandatory for last |
| DONE — queue | Present "What's next?" | Auto-pickup next EPIC |

**Guardrails (DONE review auto-check):** All gates pass + no unresolved CRITICAL issues
+ escalation_count < 3 + auditor trend ≤ 5-point decline.

**Escalation budget:** max escalations per session = `orchestration.yaml` →
`escalation.max_per_session` (default 3). On breach → E12 (PM must review). The trigger table above
is the authoritative source — the YAML config files do not duplicate it.

**Stop:** `/aid-stop` → `mode: manual`, finish current step, pause.

---

## §10 Multi-Agent Dispatch

**Parallel groups:** Steps in `plan.json` with the same `wave` number execute concurrently.

**Isolation strategy** (from `dispatch-strategy.yaml → dispatch.strategy`):
- `worktrees` → `git worktree add .aid-o/worktrees/{step_id}` (preferred)
- `branches` → per-step branches from `epic/{epic_id}/main`
- `sequential` → no parallelism

**Dispatch limit:** `dispatch.worktrees.max_parallel` (default: 3). Excess steps queued.

**After parallel group completes:**
1. Dry-run merge check for shared files
2. Conflict → ESCALATION (E6)
3. Clean → merge one-by-one (by step number), delete worktrees/branches

**Analysis groups** (read-only agents, no branches):
- Triggered after target step passes output verification
- Defined in `plan.json → analysis_groups[]`
- Results in `evidence/.../steps/step_{N}_{role}/analysis_{purpose}_report.yaml`
- Critical findings → ESCALATION; high → log to PM (non-blocking)

---

## §11 Crash Recovery

**Detection:** `fsm-state.yaml` exists with `state != DONE` and no active process.

**Resume protocol:**

```bash
aid-fsm.sh get-state <state_file>   # Returns current state
```

1. Read `fsm-state.yaml` → `state`, `current_step`, `epic_id`, `run_id`
2. Read `fsm-state.yaml` → verify completed steps match `current_step`
3. If stash exists (`git stash list` shows `auto-escalation-*`): `git stash pop`
4. Resume from current state (LLM continues from the state in `fsm-state.yaml`)

**What to check before resuming:**
- `fsm-state.yaml` — which steps are `done`
- `timeline.jsonl` — last event logged
- `evidence/steps/` — which step outputs exist

**Manual mode:** do not auto-resume after a crash. Report to PM:
```
Stale state detected: {state} at step {executing_step}/{total_steps}.

Resume with: /aid-run --resume {run_id}
```

**Step rendering rule.** Render the resumed step per the Step rendering rule in skills/pipeline.md (§6 above) — the definition lives there and is not repeated here.


**Auto mode:** run `verify-state`, validate the recorded revision and owned-job status, then resume
from the last mechanically confirmed boundary. Route ambiguous technical recovery to Codex
adjudication. Pause for PM only if repair would require new authority; never remain idle solely
because the previous controller process disappeared.

---

## §12 Queue Management

**Queue file:** `.aid-o/config/queue.yaml`

**Add to queue:**
```bash
aid-queue-add.sh <epic_file> [--priority high|medium|low] [--depends-on E-xxx,E-yyy]
```
Validates EPIC file, checks for duplicates, runs Kahn's cycle detection, appends entry.

**Queue pickup** (DONE state, action 7):
1. `aid-queue-add.sh next` → returns next READY epic_id or empty
2. If READY epic found: auto-load and start new PRE-FLIGHT→READY cycle
3. If queue paused or empty: log, present "Queue empty" to PM

**Eligibility:** READY (deps completed) | WAITING (deps in progress) | BLOCKED (deps failed)
Only READY entries are eligible for pickup.

**Dependency revalidation before respecting a blocked/waiting status (P060, OBS-20260709-06):**
A queue entry's `depends_on` (the real schema field — epic IDs) is revalidated against
**live git** before any consumer treats the entry as blocked. This closes the false-BLOCK
dual of bookkeeping staleness: a stale "awaiting merge" flag once held a dependent EPIC
blocked long after its dependency had merged (and its task branch was deleted — the norm),
and a human had to catch it.

- **Consumer contract:** BEFORE respecting a blocked/waiting status at queue pickup — and at
  `/aid-run` pre-start, before honoring a blocked queue entry — call:
  ```bash
  aid-fsm.sh queue-revalidate <epic_id>   # → unblocked | blocked | failed | noop
  ```
  Respect the *revalidated* verdict, not the stored flag. `unblocked` → eligible; `blocked` →
  a genuinely-unmerged dep, keep waiting; `failed` (fail-loud) → stop and surface to PM;
  `noop` → nothing to revalidate (missing queue / no entry / no deps), fall through to the
  stored status.
- **4-output logic per dep (D8):** (1) dep branch exists + is-ancestor of main/HEAD → unblock
  (`queue_dep_revalidated`); (2) branch exists + NOT ancestor → blocked (correct — dep not
  merged); (3) branch **deleted after merge (the norm)** → merged-detection: unblock if the
  dep's queue `status: completed`, OR its evidence fsm-state is DONE, OR `git log --merges
  --grep` shows it reachable from main; (4) no signal at all → fail-loud (`queue_dep_unresolved`).
  Unparseable queue → `queue_parse_failed` fail-loud.
- **Also wired at init:** `aid-fsm.sh init` runs the same revalidation as a non-fatal new read
  path (a blocked/unresolved dep is a scheduling signal, not an init failure). During a live
  dogfood run the controller may execute a *cached* aid-fsm.sh that predates this — so the
  consumer call above is the enforcement surface, not init alone.

**Priority order:** critical > high > medium > low; within same priority: FIFO (added_at).

**Safety guards:**
- Max 1 concurrent EPIC
- Failed EPIC → queue auto-pauses (PM must investigate before next pickup)
- Conflict detection on mutations (`last_modified` check)

---

## §13 Review Checkpoint Protocol

Six automatic review checkpoints dispatch the verifier agent at key pipeline milestones.
Configuration: `.aid-o/config/policies/review-checkpoints.yaml` (lazy-created by `/aid-run`).

### Checkpoint Summary

| CP | Location | Verifier Focus | Fix Loop | Escalation |
|----|----------|----------------|----------|------------|
| CP1 | `/aid-plan` Step 9 | `docs-review` | No (PM decides) | None |
| CP2 | EXECUTE after step verify | `code-review` | Yes (max 2) | E7 |
| CP3 | EXECUTE→GATES transition | `code-review` + `security` | Yes (max 2) | E7 |
| CP4 | DONE after curator + auditor auto-fix (pre-merge) | `code-review` | Yes (revert on fail) | None |
| CP5 | DONE after auditor (pre-merge) | N/A (auditor flag) | N/A | PM ABORT → E8 |
| CP6 | `/aid-do` post-implementation | `code-review` | Yes (max 2) | Advisory only |

### Fix Loop Protocol

```
1. Verifier dispatched → produces canonical verifier output (top-level `_generated_by`/`_generated_at`/`classification`/`verdict`/`findings`)
2. If PASS or PASS_WITH_NOTES → continue (notes logged, non-blocking)
3. If FAIL + fix_loop_eligible:
   a. Dispatch gate-fixer (source: verifier_review) with findings
   b. Gate-fixer applies minimal fixes
   c. Re-dispatch verifier (iteration 2)
   d. If still FAIL → ESCALATION (E7) or warn PM (/aid-do)
4. If FAIL + NOT fix_loop_eligible → ESCALATION immediately
5. Max 2 iterations total, then escalate
```

> The **Fix Loop Protocol block above is descriptive prose** — a generic template describing
> how *every* fix loop is shaped. It is **NOT a gate-fixer dispatch call site** and MUST NOT
> carry an Invalidation-Map Post-Fix Hook invocation. The 5 real call sites are enumerated in
> the hook section immediately below.

### Routing a finding no remaining step may fix (P079 Step 7, IMP-473)

A CP2/CP3 finding whose target file is outside every remaining step's
`allowed_paths` has nowhere legitimate to be fixed. Before you close the
checkpoint, give it a route:

```bash
source "$AID_PLUGIN_PATH/scripts/lib/aid-routed-findings.sh"
aid_finding_route <plan_id> <fingerprint> <cp2|cp3-code-review|cp3-security> \
                  <step:<n> | epic:<epic_id> | backlog:IMP-<n>> <epic_id> <total_steps>
```

Copy the fingerprint VERBATIM from the review artifact — two fingerprint
formulas ship and the library deliberately recomputes neither.

`done-advance` is the mechanical backstop, in both directions: it refuses while
a finding routed to this EPIC is unresolved, AND it reconciles the canonical
`semantic-review-final.json` against the journal — an out-of-scope finding with
no route recorded is refused BY FINGERPRINT. Skipping the routing is caught at
the boundary, not lost.

### Carried obligations — a deferral that survives the run (P079 Step 6, IMP-476)

Whenever a checkpoint verdict, a C3 loop outcome or the DONE review leads you to
DEFER something that must happen before the plan ships, record it:

```bash
source "$AID_PLUGIN_PATH/scripts/lib/aid-obligations.sh"
aid_obligation_add <plan_id> release_blocker "<what is owed, in one sentence>" "<CP3|C3|done-review|…>"
```

Use `followup` instead of `release_blocker` when it genuinely does not block the
release; a `followup` is recorded and never blocks anything.

Two rules, both learned the expensive way:

- **Never write a deferral into a file you invent.** The first P076 run put one
  in a `carried-obligations.md` inside the plan worktree; the worktree was torn
  down at close and the obligation went with it. This library writes to the
  STATE root, which outlives every worktree, and refuses to write at all when it
  cannot resolve one.
- **Discharge it or register it.** `aid-plan-close-check.sh` refuses to close the
  plan while a `release_blocker` is open. The two exits are: fix it, or register
  it as a backlog IMP and record that —
  `aid_obligation_resolve <plan_id> <index> "registered as IMP-<n>"`.

### Invalidation-Map Post-Fix Hook (C3 activation — E-059-1_2 Step 2, IMP-177)

**Observe-only. NEVER triggers a re-run.** Run this hook immediately AFTER a gate-fixer has
applied a fix at any of the **5 in-scope gate-fixer dispatch sites** listed at the end of this
section. It closes the invalidation half of IMP-177: `scripts/lib/aid-invalidation-map.sh`
existed and was registered but was only ever called from tests — this hook is its live-flow
caller. The hook emits a `gate_fixer_fix_applied` timeline event (the substrate the FSM
`invalidation_map_expected` check keys off — nothing emitted it before this step) and then
runs the observe-only producer with the required 3-arg CLI.

**Sequence — the pre-fix ref MUST be captured BEFORE the gate-fixer runs:**

```bash
# --- BEFORE dispatching the gate-fixer at an in-scope site ---
pre_fix_ref="$(git rev-parse HEAD)"          # snapshot the ref PRIOR to the fix

# --- gate-fixer applies its fix (and commits it in the fix loop) ---

# --- AFTER the fix is applied: materialize changed paths + run the hook ---
evidence_dir=".aid-o/work/evidence/{epic_id}/{run_id}"
timeline="$evidence_dir/timeline.jsonl"
changed_paths_file="$(mktemp)"
# post-fix ref = HEAD (fix committed). If the fixer left the fix UNCOMMITTED, use
# `git diff --name-only "$pre_fix_ref"` (ref → working tree) instead of the range form.
git diff --name-only "${pre_fix_ref}..HEAD" > "$changed_paths_file"

# 1) Emit the substrate event FIRST — the FSM invalidation_map_expected check keys off it.
#    <fix_ref_label> is the site+iteration label from the call-site table below.
bash "$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh" log_event "$timeline" \
  gate_fixer_fix_applied fix_ref="<fix_ref_label>"

# 2) Observe-only invalidation-map (3-arg CLI). Records affected C1 checks / C2 modes as a
#    REQUEST only — it does NOT invoke delivery-gate or semantic-review, no auto-rerun exists.
bash "$AID_PLUGIN_PATH/scripts/lib/aid-invalidation-map.sh" \
  --fix-ref "<fix_ref_label>" --evidence-dir "$evidence_dir" --changed-paths "$changed_paths_file"
```

**Enforcement:** the FSM `done-advance` review→release `invalidation_map_expected` check reads
these two signals — OBSERVE today (emits `invalidation_map_expected_missing`, does not block),
promoting to blocking at E10 (`INVALIDATION_MAP_ENFORCEMENT=blocking` seam). See
AID-v3-principles.md §1 (Detector without Enforcement is Decoration).

**In-scope call sites (5) — each references this hook with a distinct `fix_ref` label:**

| # | Site | `fix_ref` label |
|---|------|-----------------|
| 1 | CP2 per-step fix loop (§ EXECUTE) | `cp2-step-<N>-iter<K>` |
| 2 | CP3 integration fix loop (EXECUTE→GATES) | `cp3-iter<K>` |
| 3 | GATES gate-fixer (§5) | `gates-<gate>-attempt<K>` |
| 4 | DONE Curator + Auditor auto-fix (§7 steps 8–9) | `done-curator` / `done-auditor` |
| 5 | DONE Simplifier-source fix (§7 plan boundary step 5) | `done-simplifier` |

**Explicitly OUT of scope (documented, not silently skipped):**
- **CP6 / `/aid-do` fast-mode** gate-fixer dispatch (§8) — OUT per **D6**. Fast Mode has no
  `fsm-state.yaml`, no evidence dir, and no C3/delivery-gate surface, so there is nothing for an
  invalidation-map to invalidate. Do NOT wire this hook there.
- The **"Fix Loop Protocol" block above** is descriptive prose, **not a 6th call site** (see note
  above it).

### Pre-Filter Stage (CP2, CP3, CP6)

Before dispatching verifier LLM, run deterministic bash checks on `git diff` output
(new/changed lines only — `scan_target: diff_only`):

1. Regex scan via `aid-prefilter.sh`, which reads `defaults/pre-filter-rules.yaml`
   (`skip_rules` + `fail_rules` — the single source of truth for pre-filter regexes;
   `review-checkpoints.yaml → pre_filter` only toggles the stage on/off + scan scope)
2. Decision:
   - **Pattern match found** → immediate FAIL (skip verifier LLM, enter fix loop directly)
   - **Clean + trivial** (≤ threshold) → SKIP (no verifier needed)
   - **Clean + non-trivial** → dispatch verifier (LLM review)

Pre-filter applies to CP2, CP3, and CP6 only. CP1 (docs), CP4 (curator+auditor), CP5 (auditor flag)
are not pre-filtered.

### Trivial Skip Rule

When `skip_trivial: true` in config:
- CP2 and CP6 are skipped if the step/task changed ≤ `trivial_threshold.max_files` files
  with ≤ `trivial_threshold.max_lines` total lines changed
- CP1, CP3, CP4, CP5 are never skipped by this rule (always run when enabled)

### Reference Files

- `agents/verifier.md` — auto-dispatch triggers, context assembly, output format
- `agents/gate-fixer.md` — accepts `verifier_review` source type
- `agents/auditor.md` — `blocking_findings` + `recommended_fixes` for CP5/auto-fix
- `config/policies/review-checkpoints.yaml` — checkpoint toggles, fix-loop config, pre-filter toggle + scan scope (the pre-filter REGEXES live in `defaults/pre-filter-rules.yaml`)

---

**Last Updated:** 2026-08-12
**Replaces:** epic-orchestration.md, epic-state-machine.md, dispatch-protocol.md,
gate-evaluation.md, first-aid-controller.md, auto-done-state.md, auto-escalation.md,
parallel-dispatch.md, gates-engine.md, retry-engine.md, analysis-merge.md,
cost-optimization.md, epic-queue.md, slack-mcp.md
