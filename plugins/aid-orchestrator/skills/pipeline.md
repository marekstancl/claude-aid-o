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
loads it and writes the per-run record `<run evidence>/recovery-ladder.jsonl`. Two classes enter
that record from CODE and need nothing from the controller — **GATE_TIMEOUT** and **JOB_LOST** from
the gate runner. The other four are
the controller's own responsibility, and this is the checklist for them:

| Class | When the AUTO loop routes it | Route |
|---|---|---|
| **TRANSIENT_INFRA** | a Codex reviewer dispatch reports `unavailable` / `rate_limited` / `timeout` | `aid_ladder_attempt … TRANSIENT_INFRA wait_and_resume` (or `retry_once` / `resume_missing_lenses`). Still NOT a loop iteration — no review budget is consumed |
| **JOB_LOST** | `watchdog` returns `resume_needed` with a `lost`/missing newest job record | `aid_ladder_attempt … JOB_LOST collect_and_continue` |
| **DISPATCH_ORPHANED** | `fsm_check_orphan_dispatches` dies; its message names the exact `aid_ladder_emit` command | run that command, then `aid_ladder_attempt … DISPATCH_ORPHANED collect_and_continue` |
| **REVIEW_EXHAUSTED** | a bounded review loop (gate fix, CP2/CP3, the CP1 ledger) declares itself terminal | the policy allows it NO action: straight to `aid_recovery_adjudicate`, then `aid_ladder_escalate` on `escalate` |
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
| GATES→DONE | `gates_report.json` with `overall: pass` (+ the plan-gate floor and the profile floor — see §5) |
| ESCALATION→EXECUTE/GATES | `escalation_decision` field set |
| `done-advance review→release` | `pm_decision=merge`, archived task file, a fresh EPIC review (legacy mode) — §7 |

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
  'EPIC review provider down after three retries, diff reviewed by hand in PR #42'
```

**Telemetry (automatic, cannot be disabled):**
- `fsm_force_override` timeline event records `from`, `to`, `reason`, `caller`, `operator` fields
- Persistent entry to `.aid-o/work/audit-log.jsonl` (cross-EPIC trail, append-only)
- `compliance.json` captures `force_override_count` (int) + `force_override_reasons` (array) per EPIC
- Overuse of `--force` is read where it is recorded: the audit log, and the project's
  `.aid-o/work/aid-plugin-issues.md` (every force needed because AID was wrong is an entry,
  collected by the owner). The cross-project `aid-compliance-report.sh --reflect` aggregator
  was removed in v2.95.9 — nothing called it.

### FSM States

Six states. Scripts handle transitions. LLM acts within a state.

| State | Entry trigger | LLM role | Exit via |
|-------|--------------|----------|---------|
| **PRE-FLIGHT** | `/aid-run` invoked | None — bash only | → READY (auto) |
| **READY** | PRE-FLIGHT complete | **Auto mode: validate schema → auto-GO immediately.** Manual: review plan, ask PM for GO | `aid-fsm.sh transition READY EXECUTE` |
| **EXECUTE** | GO received or gate-fixer retry | Dispatch agent, verify output | `aid-fsm.sh transition EXECUTE GATES\|ESCALATION\|EXECUTE` |
| **GATES** | All steps done | None — scripts run gates | `aid-fsm.sh transition GATES DONE\|ESCALATION\|EXECUTE` |
| **ESCALATION** | EXECUTE or GATES failure | Manual: PM. Auto: Codex adjudication for technical recovery; PM only when new authority is required | `aid-fsm.sh transition ESCALATION EXECUTE\|GATES` |
| **DONE** | All gates pass | EPIC review (CP3), PM summary, merge on approval | — |
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
| `plan-finalize` `--stage freeze\|gates` | the tree it merges in and freezes from (same resolution as above) | a half-applied `prepare-plan` must never be frozen into a candidate. |
| `plan-finalize` `--stage produce\|decide`, `freeze --accept-ancillary` | exempt by design | inside the review boundary a tracked write is a SIGNAL (candidate changed → invalidation), not an operator mistake to stash away. |
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
2. Load step definition from `plan.json` → `steps[current_step]` (`step_id` = its `id`)
3. Read the step role's `**Model:**` and `**Effort:**` in `skills/role-cards.md`
4. Build the step's **dispatch contract** (P087) and its evidence directory:
   ```bash
   step_dir="$(bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" step-evidence-dir "$state_file" "$N")"
   source "$AID_PLUGIN_PATH/scripts/lib/aid-dispatch-contract.sh"
   aid_dispatch_contract_build "$evidence_dir/plan.json" "$N" "$step_dir/contract.json" "$evidence_dir"   # exit 3 = no paths, no contract owed
   ```
   The packet is built by code from `plan.json` — objective, allowed paths, dependencies,
   expected artifacts, acceptance criteria, UI contract, the step's own evidence dir — and
   carries a **version** (a hash of all of it). Memory is an item of the packet's context
   (item 10 below), not something the agent is trusted to remember.
5. Assemble dispatch prompt (see Context Assembly below); when a contract exists, paste
   `aid_dispatch_contract_prompt "$step_dir/contract.json"` verbatim after the task block —
   it tells the agent the version it must quote back and the `aid-return` block it owes,
   and carries the step role's card and the shared "Write the least code that works" rule
   (content, never a path).
6. Dispatch via Agent tool: subagent type `aid-orchestrator:implementer-light` when the card
   says `**Effort:** low`, else `aid-orchestrator:implementer`; model the card's `**Model:**`
   (an optional `step.model` in `plan.json` overrides it for that one step)
7. Save output to `$step_dir/output.md` (`evidence/{epic_id}/{run_id}/steps/{step_id}/`).
   **The controller writes this file, from the agent's final message, and nobody else.** Do
   not ask the agent to write its own `output.md`: the `aid-return` block sits in the
   agent's final message, and a file the agent wrote itself will not carry it — the contract
   validator then rejects the step as "files changed on disk but not declared in the
   return", which reads as a lie about the changes when only the block is missing.
   Every step, concurrent or not, has its own subdirectory; nothing is written into another
   step's.
8. Verify output (see Output Verification below)

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

### Step numbers: humans count from 1, the FSM from 0

`current_step`, `increment-step`, `--step N`, `step-N-verify.md` and
`cp2/step-N/` are **0-based**; the plan, the EPIC, the agent's report and
every message to the PM are **1-based**. This is deliberate and not going to change —
renumbering would orphan every existing evidence pack. When you write for a human, say
"step 3 (evidence `step-2-*`)"; when you look for evidence, subtract one.

### Scope amendment (a file the step did not list)

The step's `allowed_paths` come from the plan's `Files:` block. When work needs one more
file — most often a test beside an in-scope source, sometimes a genuinely new file the PM
approves — the controller widens the scope with ONE command and re-dispatches:

```bash
bash {plugin_path}/scripts/aid-fsm.sh amend-scope "$state_file" --add tests/test_x.py --reason "AC3 demands a test and the plan did not list it"
```

It updates the three readers of scope together: `plan.json` (the commit hook), the
`plan_json_hash` stamp (the `increment-step` tamper check) and `steps/<id>/scope-amendment.json`
(the contract validator unions it with the contract's own list). The contract is not rewritten
and the agent keeps quoting the version it was given. Never edit `plan.json` by hand mid-step:
that satisfies the hook and trips the hash, which is the contradiction this command exists to
end. Prevention is cheaper than amendment — a plan lists its tests in `Files:` (`Test:` bullet).

### Plan regenerated mid-EPIC

`increment-step` refuses when `plan.json` no longer matches the hash stamped at init — a
mid-EPIC edit could widen scope. When the PM regenerated the plan on purpose (a rename, a
later step rewritten), the sanctioned path is ONE command, never `set-field plan_json_hash`:

```bash
bash {plugin_path}/scripts/aid-fsm.sh rebase-plan "$state_file" --reason "plan regenerated after the helpdesk→asistent rename; steps 1-2 untouched"
```

It accepts the new plan only if the step in flight and every done step are unchanged
(same canonical hash — sorted-key JSON of the step — as their init snapshot in
`step-hashes.json`; future steps may change freely), re-stamps the
hash, and records from/to/reason in `plan-rebase.json`, the timeline and the audit log.
It never touches `base_commit` or `current_step`. If the current step changed, finish or
abandon it first (or `amend-scope` for an approved file); if a done step changed, restore
it — GATES scope is the union of all steps and history is not rewritten.

### Output verification

After agent completes:
- `output.md` written? → If missing, go to ESCALATION (E5)
- **Contract return (when `contract.json` exists):**
  ```bash
  aid_dispatch_contract_extract "$step_dir/output.md" > "$step_dir/return.json" \
    && aid_dispatch_contract_validate "$step_dir/contract.json" "$step_dir/return.json" "$tree_root"
  ```
  The validator judges the return against the packet and the disk, never against the
  agent's word: no `aid-return` block, a version other than the dispatched one, a status or
  gate result outside `done|blocked` / `pass|fail|skipped`, an expected artifact missing on
  disk, a file git sees changed but the return leaves out, a file changed outside the allowed
  paths, or evidence written into another step's directory → **reject** (report on stdout
  names every item). A rejected return is re-dispatched with the current packet — never
  accepted against stale instructions. Extra declared files inside scope are recorded
  (`extra_artifacts`), not refused. **`increment-step` re-runs this validation** for any
  step that has a `contract.json` and refuses to advance without an accepted `return.json`
  (`contract_return_missing` / `contract_return_rejected`) — the contract is an FSM
  precondition, not a request.
- Outputs match `step.outputs`? → If not, re-dispatch once with feedback
- Forbidden paths modified? → Re-dispatch once with warning; 2nd violation → ESCALATION
- Credit exhaustion detected? → Pause to `state: paused`, notify PM

**The turn may not end here.** While a contracted step is open — a `contract.json` written
this session and `current_step` not advanced past it — the `Stop` hook rule `turn_step_open`
(`defaults/hook-registry.yaml`, fail-closed once the canary has verified the installation)
refuses to close the turn and names the transition: validate the return, commit, write the
verify file, `increment-step` — or hand over explicitly with a Decision card or a Blocked card
(`skills/communication.md`). A `Write`/`Edit` outside every open step's paths is named by
`turn_write_scope` as context before it lands; it does not block, the validation above does.

**Per-step commit (controller, after an accepted return):**
```bash
aid_dispatch_contract_commit "$tree_root" "$step_dir/contract.json" "$step_dir/return.json" \
  "step {N}: {step title}"     # validates first (a rejected return is not committed), stages only
                               # the return's changed_files; prints the SHA or "nothing to commit"
```
The controller is the only committer and it takes returns **one at a time**, in the order
they arrive — that is the protocol that keeps three agents returning at once from becoming
one commit. What the FSM guarantees is narrower and mechanical: a contracted step does not
advance on an unvalidated, unfinished or rejected return (`increment-step`). An agent that
changed nothing produces no commit and the fact is recorded.

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

### Step review (CP2) — one section, in the run command

After the step's commit and `step-N-verify.md`, before `increment-step`: the
step check, the reviewer round and `close`, exactly as `commands/aid-run.md`
"Step review (CP2) and EPIC review (CP3)" lists them (roles in
`skills/step-review-roles.md`). `increment-step` reads `cp2/step-N/rounds.json`
and nothing else. This skill does not restate the commands.

### Dispatch Protocol

> **⛔ Non-negotiable anti-fabrication rule.** Every reviewer of a round is a real,
> independent agent the controller dispatches inside the `aid-emit-dispatch.sh`
> start/complete bracket the adapter prescribes; `close` refuses an answer with
> no dispatch record (`no_dispatch_record`) and the FSM refuses a round prepared
> `--stub`. The controller never writes, edits or hand-fills a reviewer's file and
> never records a verdict it did not collect; when a dispatch is impossible, STOP
> and tell the PM — never synthesize the verdict.

### EPIC review (CP3) — one section, in the run command

After the last step, before `transition EXECUTE GATES`: the same step check
and round with `--checkpoint cp3` (`commands/aid-run.md` "Step review (CP2)
and EPIC review (CP3)"). `close` writes `<run>/semantic-review-final.json` for
the plan-final consumers and routes what stays open (§13). The FSM reads
`cp3/rounds.json`, bound to HEAD; GATES→DONE and done-advance re-check it
(the D4 exception with the `CP3-Freshness-Exception:` trailer kept).

### Semantic evidence of a step or an EPIC

Since P094 the reviewer round's `merged.json` is the semantic evidence of a step
and of an EPIC; the cp3 `close` writes the per-EPIC `semantic-review-final.json`.
The verifier's `c2_mode` dispatches at cp2 (`local`, `wiring`, `behavior`) are
gone; only the plan-final `final` mode remains (§7, `plan-finalize`).

### After the last step

If more steps remain: `aid-fsm.sh transition EXECUTE EXECUTE <state_file>`
If all steps done + CP3 pass: `aid-fsm.sh transition EXECUTE GATES <state_file>`
On unrecoverable error: `aid-fsm.sh transition EXECUTE ESCALATION <state_file>`

**Enforcement:** Call `increment-step` after each step completes. `EXECUTE→GATES` is rejected
if `current_step < total_steps`. `EXECUTE→EXECUTE` is rejected if `current_step >= total_steps`.

### Parallel groups

Steps that share a `Parallel Group` (a **wave**, from the plan's `**Parallel group:**`
field) may run at the same time. Whether they DO is decided by code before every wave,
never assumed from the plan:

```bash
source "$AID_PLUGIN_PATH/scripts/lib/aid-parallel-dispatch.sh"
plan_path="$(bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" get-field plan_path "$state_file")"   # plan.md, recorded by init ("null" in Fast Mode → serial)
orchestration_yaml="$(aid_state_path .aid-o/config/orchestration.yaml)"                     # state root, never the worktree
tree_root="$(git rev-parse --show-toplevel)"                                                 # the tree the run executes in
worktree_base="$(yq -r '.dispatch.worktree_base // ".aid-worktrees"' "$orchestration_yaml")"
# the wave: the current step's group in plan.json → parallel_groups[] (each entry lists the step ids of one wave)
wave_steps="$(jq -c --arg id "$step_id" '.parallel_groups[] | select(index($id))' "$evidence_dir/plan.json")"
wave_name="$(jq -r --arg id "$step_id" '.steps[] | select(.id == $id) | .parallel_group // "---"' "$evidence_dir/plan.json")"
wave_size="$(jq -r 'length' <<< "${wave_steps:-[]}")"
decision="$(aid_parallel_decide "$plan_path" "$orchestration_yaml" "$wave_name" "$wave_size" "$tree_root")"
# concurrent slots=<max_parallel> | serial: <reason>   — exit 0 either way; log the line to timeline.jsonl
```

`serial` is returned — with the reason — for a wave of one, for `dispatch.max_parallel: 1`
(the brake, `defaults/orchestration.yaml`), for a `dispatch.strategy` other than `worktrees`,
when git cannot hand out worktrees, when `aid-plan-parallel-check.sh --group <wave>` finds two
steps of THIS wave sharing a file or a declared interface, and when that check cannot run at
all. **The check never refuses a run; it degrades it.** A wave that cannot be proved safe
runs in order.

**Concurrent path** (decision `concurrent slots=N`: N is the ceiling the controller keeps —
the library does not count agents in flight — a wave larger than N runs in batches, the next
step dispatched as a slot frees):

1. For each step: `aid_parallel_step_worktree "$tree_root" "$step_id" HEAD "$worktree_base"`
   → its own tree on `step/<step_id>` at the current base (`dispatch.worktree_base`, default
   `.aid-worktrees`; a branch left by an earlier run is reset, never reused). Build its
   contract (§4 step 4) and dispatch it there — one message, several `Agent()` calls.
2. As each agent returns — **one at a time, in arrival order** — validate the return
   (§4 Output verification), commit it in the step's worktree (`aid_dispatch_contract_commit`),
   write its `step-{N}-verify.md`, then `aid_parallel_merge "$tree_root" "step/<step_id>" "$worktree_base"`.
3. A clean merge prints the SHA; the step's tree is removed when git agrees it is clean
   (a dirty one is kept and named — never deleted). **A conflict is aborted, the tree is
   untouched (`exit 1`, files named), the step's tree is put back on the base that moved —
   `aid_parallel_step_reset "$tree_root" "$step_id" HEAD "$worktree_base"` — and the step is
   dispatched again.** The same step failing twice is handled by
   `defaults/policies/auto-recovery.yaml`, not by a human queue.
4. An agent that dies leaves its tree and branch for inspection; the other steps continue.
5. `increment-step` once per merged step, in merge order.

What isolation guarantees, and what it does not: a collision surfaces as a merge conflict —
a state that is recognised and repeatable — never as a corrupted tree. Disjoint files and
disjoint declared interfaces do **not** guarantee disjoint effect; that boundary is recorded
in `defaults/enforcement-registry.yaml` (`parallel_dispatch_wave_check`).

---

## §5 Gates

**LLM role:** none while gates run. The runner is deterministic; the controller acts only on
the card it prints, and only a failing run puts anything in front of the PM.

**What a gate is.** One entry under `execution.yaml.gates.<id>`, read by
`scripts/aid-run-gates.sh` and by nothing else:

| Key | Meaning |
|-----|---------|
| `command` | the shell command; `{plan_path}`, `{epic_id}`, `{run_id}`, `{base_commit}`, `{evidence_dir}`, `{plugin_path}` are substituted, an unknown `{token}` fails the gate |
| `required` | `true` blocks GATES→DONE on failure; `false` is advisory. This is the only requiredness there is |
| `timeout_seconds` | the deadline, the only one it has; absent → 60; not a positive integer → `run-all` exits 2 before any gate runs |
| `max_retries` | retries after a failure inside one run (default 1) |
| `run_mode` | `foreground` (default) runs inline under `timeout(1)`; `background` runs as an `aid-job.sh` job the runner still polls to completion — it survives a dead session, it does not return early |

**Timeout rule.** The number in the file decides; no history steers a run. To choose it:
2 × p95 of the last 20 measured `duration_ms` of that gate (`job_timeout` rows excluded),
rounded up to 30 s, 60–3 600 s. `scripts/aid-gate-runtime-report.sh [gate]` prints that
proposal next to the configured value and never writes.

**Profile rule.** `gate_profiles.<name>.include[]` is an ORDERED table, declared narrowest
first; the declaration index is the rank (`lib/aid-gate-profile-select.sh` is the one resolver).
The runner chooses nothing: `--profile <name>` runs exactly that `include[]`, every other gate
gets a `status: skip, reason: not_in_profile` row; without `--profile` every gate runs.
`advance-to-gates` resolves the name for the run's `base_commit..HEAD` diff: the LAST declared
profile whose `when_paths` matches any changed path, else `default_profile`; a profile without
`when_paths` is never auto-selected; a project without `gate_profiles` gets no `--profile`.
The report records `profile`, `profile_source` (`caller` | `none`) and `profile_table`.

**Run it** (the atomic flow; gates fail → state stays EXECUTE, gates pass → EXECUTE→GATES):

```bash
bash $AID_PLUGIN_PATH/scripts/aid-fsm.sh advance-to-gates "$STATE_FILE" [--profile <name>]
```

The two-step form stays for debugging and crash recovery: `aid-run-gates.sh run-all
<execution.yaml> <epic_id> <run_id> [timeline] --state-file <s> --report-file
<evidence_dir>/gates/gates_report.json --plan-json <evidence_dir>/plan.json [--profile <name>]`,
then `aid-fsm.sh transition EXECUTE GATES <s>`. `--state-file` restricts the runner to GATES
state (`advance-to-gates` sets `AID_GATES_TRIGGERED_BY_FSM=1` to run it from EXECUTE);
`--plan-json` is required whenever `plan.json` exists — the runner reconciles `plan.json.gates[]`
against the table and writes `plan_gates_reconciled: true`, without which EXECUTE→GATES refuses.

**Row contract** (`gates_report.json.gates.<id>`, checkpointed per gate in
`<evidence_dir>/gates_rows/<id>.json`; `lib/aid-gate-row.sh` is its only home): `row_version: 2`,
`status` pass|fail|skip, `reason` from the closed vocabulary in `defaults/schemas/gate-row.schema.json`
(`exit_<n>`, `job_timeout`, `job_lost`, `job_cancelled`, `not_in_profile`, `missing_script`,
`vacuous_pass`, `reused_from`, `legacy_row` and the runner's did-not-run reasons), `exit_code`,
`duration_ms`, `started_at`, `completed_at`, `evidence`, `required`, `waived`, `reused_from`, and
`result` as the derived version-1 field for one release. A waiver is `waived: true` on a `fail`
row, never a pass. `overall` is `fail` iff a `required: true` gate failed without a valid waiver;
`skip` and `not_in_profile` never move it. The envelope carries `_generated_by`, `_generated_at`,
`_command_log[]`, `excluded_gates[]`, `waived_gates[]`, and `escalation` when a `targeted_tests`
exit 3/11 forced a second `--profile full` pass (`lib/aid-run-gates-report.sh`).

**Refusals** — each names the next command:

| Where | Reason | What it says |
|-------|--------|--------------|
| `run-all`, exit 2, before any gate | a key the runner no longer reads (removed layers: per-gate applicability, services, profile defaults) | the key, the gate, and `bash $AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh upgrade <project root>` |
| `run-all`, exit 2, before any gate | unknown `--profile`, or a profile whose `include[]` names no `required: true` gate | the declared table and the upgrade command |
| `run-all`, exit 1 | `include[]` names an undefined gate or one without `command` | the gate |
| EXECUTE→GATES | `gates_no_generated_by` (hand-written report), missing `plan_gates_reconciled` | the canonical `run-all` invocation |
| GATES→DONE | `overall != pass` | the failing gates (card below) |
| GATES→DONE | `plan_gate_profile_excluded` — a `plan.json.gates[]` gate is in `excluded_gates[]`; `plan_json_malformed` | widen `include[]`, re-run `advance-to-gates` |
| GATES→DONE | `risk_profile_unresolvable`, `profile_table_changed`, `risk_profile_below_required` — the recorded profile names none, is narrower than the resolver's answer for `base_commit..HEAD`, or the table changed since the run | `advance-to-gates <state>` or `run-all ... --profile <answer>` |

Every GATES→DONE refusal is overridable by `aid-fsm.sh transition GATES DONE <state_file> --force
--reason '<≥20 chars — PM-authorized reason>'`, logged as `fsm_force_override` (§1). Repeated
same-reason precondition fails (≥ 3) emit `fsm_precondition_repeated_fail` in the timeline.
Pre-deploy EPICs (`created_at < AID_DEPLOY_DATE`) skip the
`_generated_by` check (§2 grandfather).

**Gate-boundary message (deterministic).** When the runner returns — DONE branch and failing
branch alike, manual and auto mode — do not summarise. Source
`scripts/lib/aid-gate-outcome-summary.sh` and run:

```bash
aid_gate_outcome_render "<the --report-file path passed above>" "<evidence_dir>"
```

It computes every number from the report, follows `.overall` and never a per-gate row, and counts
a waiver as PM risk acceptance. Present the card it prints verbatim; a gate run owes the PM no
page (the PM reads two per plan: the written plan and the delivered one). Card shapes and the language rule are in `skills/communication.md`. If the renderer exits
non-zero, say so and present a Blocked card built only from bounded facts, routing raw-derived
text through `aid_gate_outcome_redact` first.

**On gate failure.** Retries remaining → dispatch `agents/gate-fixer.md` with the report,
`aid-fsm.sh transition GATES EXECUTE <state_file>`, and after the fix `EXECUTE GATES` again
(the fix loop is bounded in §4: max 3 cycles per check). Budget exhausted →
`aid-fsm.sh transition GATES ESCALATION <state_file>` (§6). On pass →
`aid-fsm.sh transition GATES DONE <state_file>`; the EPIC review and the PM decision happen in
DONE (§7).
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
| E7 | (retired with P094: an exhausted review round is a PM card, not an escalation state) |
| E8 | Open findings: {list from the EPIC review}, Round: `.aid-o/work/evidence/{id}/{run}/cp3/rounds.json` |

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
| E7 | retired (P094) — a cp2/cp3 round that fails after the last allowed round goes to the PM card |
| E8 | PM chose ABORT in the DONE summary |

---

## §7 DONE State

**LLM role:** Orchestrate the pre-merge review and the PM decision.

**Mechanical enforcement:**
1. `aid-fsm.sh done-advance review release` — requires `pm_decision=merge`, the archived task
   file, routed findings settled and tiered-severity compliance; in `legacy_epic_release_mode`
   also a fresh EPIC review (`cp3/rounds.json` at HEAD) and, under `enforcement: blocking`, a
   `release_ready: true` decision.
2. `aid-release.sh` — refuses a release while `done_phase != release`.
3. Git pre-commit hook — blocks commits on `task/*/epic/*` branches in DONE/review.
4. `aid-fsm.sh plan-close` — runs the plan-close self-check and writes `ca-review-complete`;
   never create that marker with `touch`.

Sub-phases (`review` → `release`) are managed by `done-advance`. `review` is set automatically on
the GATES→DONE transition.

**Who reviews what.** A step is reviewed by the step round (CP2), an EPIC by the EPIC round (CP3),
both described once in `commands/aid-run.md`. A `plan_branch` plan is then closed ONCE, by
`plan-finalize` (freeze → gates → produce → the whole-plan round → decide): read
**`commands/aid-run.md` → "Closing a plan (plan-final)"** and follow it; nothing here repeats it.
An intermediate EPIC of such a plan skips the per-EPIC release stack (the names are
`AID_PLAN_BRANCH_SKIPPED_STAGES` in `scripts/aid-fsm.sh`, echoed into the
`done_advance_plan_branch_mode` timeline event); its own CP3 round is NOT skipped, and under
`streamlined_mode: true` `fsm_check_streamlined_integration_review` hard-fails `done-advance`
when `cp3/rounds.json` is missing or did not close with `pass`.

Anything a review DEFERS rather than fixes is recorded with `aid_obligation_add`
(§13 *Carried obligations*) before you move on — the close refuses an open `release_blocker`.

### Telemetry Overview

Detail in [Telemetry Reference](#telemetry-reference) below.

- **Epic Summary** — after `done-advance review→release`, `evidence/<epic>/<run>/epic-summary.md`
  with the delivery summary, warnings and PM trust level. Best-effort; never blocks release.
- **Compliance Telemetry** — `compliance.json`; `overall: pass` if all checks ∈ {true, null}.
- **Tiered Severity** — `done-advance review release` refuses on `severity: blocking` failures;
  soft-fail if `yq` is missing. Override via `--force --reason`. Registry:
  `.aid-o/config/check-severity.yaml`.
- **Compliance Recovery** (P042) — timeline events on block and on recovery; no Telegram
  (P099: AID messages the PM only when an agent waits and when a plan is delivered).

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

### Sub-phase: `review`

1. **Run file:** `status: completed`, `completed: {timestamp}` in the run.md frontmatter.
2. **Archive:** move the run file to `runs/archive/`; update the EPIC frontmatter if all runs are complete.
3. **Update** `work/active.md` status.
4. **Final report:** generate `evidence/{epic_id}/{run_id}/final_report.md`.
5. **Review profile:** `review-profile.json` over the whole EPIC diff — an input of the release
   decision. Resolve the EPIC task file (`tasks/` first, `tasks/archive/` as the fallback) and pass
   it positionally; exit `22` (`range_undetermined`) is NON-FATAL, an unverifiable profile is
   emitted and the run continues:
   ```bash
   evidence_dir=".aid-o/work/evidence/{epic_id}/{run_id}"
   epic_task_path="$(ls .aid-o/tasks/{epic_id}*.md .aid-o/tasks/archive/{epic_id}*.md 2>/dev/null | head -1)"
   bash "$AID_PLUGIN_PATH/scripts/aid-review-profile.sh" "$epic_task_path" "$evidence_dir" || true
   ```
   An EPIC file that does not resolve is reported to the PM as a Blocked card; never continue on
   a profile computed without it.
6. **EPIC review (CP3)** — `commands/aid-run.md`, "EPIC review". Its findings are fixed by the
   role that wrote the code and confirmed by the next round; there is no separate fix agent and
   no second reviewer of the fixes.
7. **PM Summary** (always shown, even in FIRST AID mode):

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

Options (`legacy_epic_release_mode`):
  MERGE — release + merge to main + queue pickup
  FIX   — provide guidance, re-run the review
  ABORT — stop EPIC, no merge (/aid-stop)

Options (`plan_branch`):
  MERGE — merge this EPIC into the PLAN branch. No release, no tag, no push:
          the release happens once, later, when the plan is closed.
  FIX   — provide guidance, re-run the review
  ABORT — stop EPIC, no merge (/aid-stop)
```

This is the **Finished** card of `skills/communication.md` applied to DONE (the **Blocked or
failed** card replaces it when the review ends in a blocker the PM must resolve).
`commands/aid-run.md` shows the same shape abridged — keep the two in step.

8. **PM decides:** MERGE → step 9; FIX → guidance → fixes → steps 5-7 again; ABORT → ERROR
   (`status: aborted`, E8 logged).
9. **Advance to the release sub-phase** (mechanically enforced):
    ```bash
    aid-fsm.sh set-field pm_decision merge <state_file>
    aid-fsm.sh done-advance review release <state_file>
    ```
    An **unresolvable** plan mode is a hard `plan_mode_unresolved` block, never a fallback:
    guessing legacy here would merge a single EPIC into the target branch, which is exactly what
    `plan_branch` exists to prevent.

### §7.6 PM Machine Handoff — release-decision → PM brief

1. **`release-decision.json`** — `aid-release-policy.sh` emits the protocol-v2 `release_decision`
   (`release_ready`, `blockers`, `waivers_applied`, `merge_mode`, the evidence verification
   fields, `summary_for_pm`, `pm_brief_required`, `pm_brief_status`). Per EPIC it is produced
   inside `done-advance review→release`; for a plan, by `plan-finalize --stage decide`.
2. **`pm-decision-brief.json` + `pm-summary.md`** — `aid-pm-brief.sh <evidence_dir>` reads ONLY
   `release-decision.json` and patches `pm_brief_status` back into it. Pure bash/jq, no LLM.
   Dispatch it only after a SUCCESSFUL `done-advance` (exit 0); `decide` runs it itself.
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-pm-brief.sh" "$evidence_dir"
   ```
3. **The PM's page at a plan close** — `scripts/lib/aid-plan-close-summary.sh`:
   ```bash
   source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-close-summary.sh"
   aid_plan_close_render "$evidence_dir/pm-decision-brief.json" \
                         "$evidence_dir/release-decision.json" "$plan_id" "$evidence_dir"
   ```
   Publish the artifact body via the Artifact tool, then present the chat card verbatim. The renderer
   reads ONLY those two files and fails CLOSED (exit 1, no page) when the brief lacks a required
   field or the decision carries no `plan_summary`. If the brief is absent, report the Blocked
   card "plan-close brief missing — run aid-pm-brief.sh"; never improvise a summary from
   evidence files.

**Honest limitation.** Nothing structurally blocks a merge that lacks a brief: no FSM
precondition consumes `pm_brief_required`. The brief after every successful `done-advance`,
including `--auto` / FIRST AID, is a convention; a `pm_brief_status` that stays `pending` after a
release transition is itself a finding.

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
16. **Queue — the continuation is a program now; you do not perform it by hand.**
    Since P090 this whole sequence lives in `scripts/aid-plan-continue.sh`, and
    `epic-merge-to-plan` calls it ITSELF after a successful merge whenever the plan's
    `autonomy` field (written by `plan-start`) says `auto`. In an autonomous plan there
    is nothing for you to do at step 16: the merge you ran at step 15 already printed
    what it did.

    ```bash
    # Only when you are driving a MANUAL plan, or re-running after a failure.
    # Same sequence, same guarantees; --no-continue on epic-merge-to-plan turns
    # the automatic call off.
    bash {plugin_path}/scripts/aid-plan-continue.sh {plan_id} {epic_id} \
      --project-root {project_root}
    ```

    **What it does, in order** — and it stops at the first link that fails:

    | # | Link | What it guarantees |
    |---|------|--------------------|
    | 0 | **proof** | `git merge-base --is-ancestor <task branch> plan/{plan_id}`. Nothing is written before this passes |
    | 1 | **mirror** | `set-status {epic_id} merged_to_plan`; skipped if already there, which is what makes a re-run harmless |
    | 2 | **ask** | `aid-plan-fsm.sh next-epic {plan_id}` — changes nothing, records the answer in the plan timeline. `none`/`blocked:` ends here, queue unclaimed |
    | 3 | **claim** | `claim-next {plan_id}`; if the queue moved since the ask, the claim wins and the difference is recorded |
    | 4 | **start** | `epic-start` on exactly what the claim took. If it fails, the claim is undone back to `pending` |

    **Link 1 is not optional bookkeeping — without it a multi-EPIC plan stalls at its
    second EPIC.** `epic-merge-to-plan` leaves the queue entry at `running`. When the
    dependency entry carries no `merge_target` — the shape `aid-queue-add.sh` writes
    whenever `plan/{plan_id}` did not yet exist at queue-add time, which is the normal
    ordering in `aid-auto-pipeline.sh` — `claim-next` resolves that dependency from its
    STATUS, sees `running`, and durably records
    `blocked:{next_epic_id}:dependency_unmerged:{epic_id}` on the dependent. The work is
    provably contained in `plan/{plan_id}` and provably absent from `{target_branch}` —
    exactly the state the plan exists to create — and the hand-off refuses it anyway.

    **A queue entry is a DERIVED VIEW, never evidence.** Link 1 mirrors the ancestry fact
    step 15 established in Git; it does not create it. That is why link 0 exists: for an
    entry with no `merge_target` the status IS the readiness answer, so the mirror has to
    be earned against Git before it is written. For an entry that DOES carry a
    `merge_target`, `claim-next` proves readiness with its own live
    `git merge-base --is-ancestor` check and ignores the status field entirely.

    **`aid-plan-fsm.sh` still does not write the queue.** The boundary at
    `aid-plan-fsm.sh:89-92` is unchanged: `epic-merge-to-plan` moves Git and the plan
    manifest and hands control to a separate program that establishes its own proof.

    | Exit | `aid-plan-continue.sh` |
    |------|------------------------|
    | 0 | The plan moved on — or ended cleanly (`none` / `blocked:` / nothing owed). On `none` it names `plan-finalize`, `plan-merge-to-main`, `plan-close` and stops; closing a plan is a decision, and it does not make it |
    | 1 | A link failed and was named; the plan did not move. A refusal at link 1 because the entry is terminal means the queue and the manifest disagree — report it, never hand-edit the queue to force agreement |
    | 2 | Usage |
    | 3 | Transient: a lock was unavailable. Retry. **Never read as an end** |

    **The one state it will not clean up.** If a process dies between claim and start,
    the entry is left `running` with nothing running. `peek` deliberately does not return
    such an entry and the script will not silently reset one — it may be somebody else's
    live run. Release it explicitly with
    `aid-plan-continue.sh --reclaim <epic_id>`, which no automation ever calls.

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
    `aid-fsm.sh plan-close` only runs the plan-close self-check and writes the
    `ca-review-complete` marker; it does NOT write a delivery SHA or a tracked commit on
    the task branch.)
16. **Queue:** Read `config/queue.yaml` → auto-pickup next EPIC if queued.
    Metrics stored to Qdrant (`aid-orchestration-log`) or fallback JSONL.

**Auto-mode (FIRST AID) in `legacy_epic_release_mode`:** the EPIC review closed `pass` and
`release-decision.json` says `release_ready: true` → auto-MERGE. Anything else → show the
summary, require a PM decision.

**Auto-mode (FIRST AID) in `plan_branch` mode:** There is no `release-decision.json` for an
intermediate EPIC — the release is decided once, when the plan is closed. Evaluate, from
artifacts an intermediate EPIC really has:

1. `done-advance review release` exited 0 (it already enforced `pm_decision=merge`, the
   archived task file, the streamlined integration review, the abandoned check and
   tiered compliance), and
2. `gates_report.json` → `overall: pass`.

Both true → proceed automatically through steps 14-16 (`epic-complete` →
`epic-merge-to-plan`, which then calls `aid-plan-continue.sh` itself: mirror → ask →
claim → start. The mirror is never skipped in auto-mode — skipping it blocks the next
EPIC — and since P090 nothing has to remember to do it). Any
one false → stop and show the summary; the
merge into `plan/{plan_id}` needs a PM decision. **`epic-merge-to-plan` exiting 1/4/5 is
never auto-retried** — report the printed reason as documented in step 15.

**Evidence written (`legacy_epic_release_mode`):**
```
evidence/{epic_id}/{run_id}/
  final_report.md              # Summary (steps, gates, duration, artifacts)
  cp3/rounds.json              # the EPIC review
  release-decision.json        # the release decision (protocol-v2 — §7.6)
  pm-decision-brief.json       # PM machine handoff, echoes release-decision (protocol-v2 — §7.6)
  pm-summary.md                # PM human summary, rendered from release-decision (§7.6)
```

**Evidence written (`plan_branch` mode, an intermediate EPIC):** only the per-EPIC
artifacts — `final_report.md`, `gates_report.json`, the CP2/CP3 verifier outputs,
`timeline.jsonl` (carrying `done_advance_plan_branch_mode`), `compliance.json` and
`epic-summary.md`. **None** of `release-decision.json`, `pm-decision-brief.json` or
`pm-summary.md` exists yet — they are written once, when the plan is closed. Do not report a missing one as a gap, and never read the previous
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
| `❌ Co se nestihlo` | what the EPIC review left open (`cp3/round-N/merged.json`) |
| `📋 Co dělat dál (PM akce)` | escalations, force override audit reminder |
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

Cross-project aggregation and the one-shot backfill were removed in v2.95.9 (the May 2026
era comparison had no caller left); per-run `compliance.json` stays.

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

#### Compliance Recovery (P042, v2.29.0+)

Companion to the blocking flow above, recorded in the timeline only (no Telegram
since P099):

1. **Block:** when `done-advance review→release` refuses transition on blocking
   failures, the FSM writes a `fsm_done_advance_blocked` timeline event (with the
   `blocked_checks` list).
2. **Recovery:** on the next successful `done-advance review→release` (zero
   blocking failures), if the last `fsm_done_advance_blocked` event has no later
   `fsm_done_advance_recovered` event, the FSM writes a `fsm_done_advance_recovered`
   timeline event — one per block episode.

**Soft-fail:** missing timeline.jsonl or `jq` → recovery detection silently
skips (telemetry over correctness, same posture as compliance.json writes).

---

## §8 FAST MODE

**Trigger:** `/aid-do <task>` command.

**What it is:** Single-step EXECUTE without PRE-FLIGHT, plan.json, or gate suite.
Designed for quick tasks that don't warrant a full EPIC.

**LLM behavior:**
1. Log task to `.aid-o/logs/aid-do-log.jsonl` (action: `aid_do_start`)
2. Dispatch single agent (`aid-orchestrator:implementer`, model opus) with task description
3. Verify output (same as §4)
4. **Review Checkpoint CP6:** Pre-filter (§13) runs first on `git diff`.
   If pre-filter clean + trivial → skip. If pre-filter finds pattern → immediate FAIL.
   Otherwise dispatch verifier (`code-review`). Fix loop: gate-fixer → verifier, max 2.
   Advisory only (no ESCALATION in Fast Mode).
   Skip per `review-checkpoints.yaml` (`cp6_fast_mode_review`, `skip_trivial`).
5. Log completion (action: `aid_do_complete`, files_changed, duration_seconds)

**No fsm-state.yaml.** No branch. No gates. Quick log only.

If task complexity grows (3+ files, multi-step) → suggest `/aid-plan --epic` instead.

---

## §9 Autonomous Mode (FIRST AID)

**Activation:** `/aid-run --auto` runs `aid-fsm.sh auto-mode set auto --by "aid-run --auto"`
as its first action.

**State file:** `.aid-o/work/auto-mode-state.yaml`
**One writer:** `aid-fsm.sh auto-mode set` (`/aid-stop` writes `manual` through it too).
**One reader:** `aid_autonomous_mode` in `scripts/lib/aid-permissions.sh`.

**Every decision point reads the mode through that one reader**, which takes
`mode: manual` in the state file above an exported `AID_AUTO_MODE=1` (a PM stop
wins), then `AID_AUTO_MODE=1`, then `mode: auto`, then `permissions.yaml`.
A missing or unreadable file defaults to `manual` (fail-safe).

**Auto-mode overrides:**

| Decision point | Manual | Auto |
|---------------|--------|------|
| READY — plan approval | Ask PM via Slack/chat | Validate JSON schema → auto-GO |
| EXECUTE — review cycle exhausted | ESCALATION | Fresh-approach cycle, then ESCALATION |
| ESCALATION | Options A/B/C | Options A/B/C/D (D = continue manual) |
| DONE — review sub-phase | Ask PM (MERGE/FIX/ABORT) | Guardrail check → auto-approve if pass |
| DONE — PM summary | Show MERGE/FIX/ABORT | Auto-MERGE when the review passed and the decision is `release_ready` |
| DONE — version bump | Ask PM for intermediate | Auto-defer for intermediate, mandatory for last |
| DONE — queue | Present "What's next?" | Auto-pickup next EPIC |

**Guardrails (DONE review auto-check):** All gates pass + no unresolved CRITICAL issues
+ escalation_count < 3.

**Escalation budget:** max escalations per session = `orchestration.yaml` →
`escalation.max_per_session` (default 3). On breach → E12 (PM must review). The trigger table above
is the authoritative source — the YAML config files do not duplicate it.

**The bound session keeps going (P099).** `/aid-run --auto` records the session in the plan's
state (`plan-state <id> --bind-session`), and the Stop rule `queue_continuation_notice`
(`scripts/lib/aid-queue-continuation.sh`) refuses a turn of that session that ends with work left,
up to `orchestration.yaml → autonomy.continuation_budget` refusals; the PM's next prompt resets the
count. A Decision or Blocked card, a last line `AID-WAIT: <what>` while an AID background job is
live, or the spent budget lets the turn end; the card and the budget send the PM one "agent is
waiting" message (`aid_alert_waiting`). No other session is ever refused.

**Stop:** `/aid-stop` → `mode: manual`, finish current step, pause.

---

## §10 Multi-Agent Dispatch

**Parallel groups:** the wave decision, the per-step worktrees, the serial merge point and
the conflict-means-retry rule are specified once, in §4 "Parallel groups". `plan.json →
parallel_groups[]` is the machine form of the plan's waves.

**Isolation strategy** (`orchestration.yaml → dispatch.strategy`): `worktrees` — each step
in `<dispatch.worktree_base>/step-<step_id>` (default `.aid-worktrees`) on `step/<step_id>`
(`aid_parallel_step_worktree`);
`sequential` — no parallelism. `dispatch.max_parallel` caps agents in flight; excess steps
of a wave wait for a slot.

**Analysis groups** (read-only agents, no branches):
- Triggered after target step passes output verification
- Defined in `plan.json → analysis_groups[]`
- Results in `evidence/.../steps/{step_id}/analysis_{purpose}_report.yaml`
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

Five review checkpoints run at key pipeline milestones, all of them reviewer
rounds run by `scripts/aid-review-round.sh` (CP1: "Plan review
(CP1)" in `commands/aid-plan.md`, roles in `skills/plan-review-roles.md`, gated
by `scripts/aid-cp1-gate.sh`; CP2/CP3: "Step review (CP2) and EPIC review
(CP3)" in `commands/aid-run.md`; CP6: `commands/aid-do.md`; roles in
`skills/step-review-roles.md`; CP7, the whole-plan round: "Closing a plan
(plan-final)" in `commands/aid-run.md`).
Configuration: `.aid-o/config/policies/review-checkpoints.yaml` (lazy-created by `/aid-run`).

### Checkpoint Summary

| CP | Location | Verifier Focus | Fix Loop | Escalation |
|----|----------|----------------|----------|------------|
| CP1 | `/aid-plan` "Plan review (CP1)" | six plan reviewer roles, not the verifier | Rounds: 2 by default, a 3rd or only 1 on the PM's recorded override | PM card after each round |
| CP2 | `/aid-run` "Step review (CP2) and EPIC review (CP3)" | step reviewer roles, not the verifier | Rounds: 2 by default; the step's role fixes, the next round confirms | PM card after the last round |
| CP3 | same section, `--checkpoint cp3` | EPIC reviewer roles | same | PM card after the last round |
| CP6 | `/aid-do` "Review Check (CP6)" | step reviewer roles over the working tree | on the PM's word | Advisory only |
| CP7 | `/aid-run` "Closing a plan (plan-final)" | three whole-plan roles | 1 round per attempt; a fix mints the next attempt, which confirms it | Decision card (FIX / ABORT) |

### Fix Loop Protocol

A failed round (cp2/cp3/cp6) is fixed by the step's own role (`fix_of:` in
`scripts/lib/aid-review-adapter-claude.md`), never by the gate-fixer, and confirmed by
the next round; the gate-fixer keeps GATES only.
What stays open after the last allowed round, `close` routes or carries (below).

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

Whenever a checkpoint verdict or the DONE review leads you to
DEFER something that must happen before the plan ships, record it:

```bash
source "$AID_PLUGIN_PATH/scripts/lib/aid-obligations.sh"
aid_obligation_add <plan_id> release_blocker "<what is owed, in one sentence>" "<CP3|CP7|done-review|…>"
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

### Reference Files

- `skills/step-review-roles.md` — the reviewer roles of cp2/cp3/cp6; `skills/plan-review-roles.md` — of cp1
- `scripts/lib/aid-review-adapter-claude.md` — how the controller dispatches a round's reviewers and the fix
- `agents/gate-fixer.md` — GATES fixes
- `config/policies/review-checkpoints.yaml` — checkpoint toggles, reviewer blocks, rounds_default

---

**Last Updated:** 2026-09-23
**Replaces:** epic-orchestration.md, epic-state-machine.md, dispatch-protocol.md,
gate-evaluation.md, first-aid-controller.md, auto-done-state.md, auto-escalation.md,
parallel-dispatch.md, gates-engine.md, retry-engine.md, analysis-merge.md,
cost-optimization.md, epic-queue.md, slack-mcp.md
