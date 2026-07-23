# Post-P064 → P062/E10 execution checklist

**Created:** 2026-07-23
**Purpose:** canonical delivery order after P064, through executable completion of P062/E10
**Status:** active PM checklist — P064 complete, Phase 1 is next
**Sources:** P061, P062, P064, P066 interim, P068, IMP-258 and IMP-261–274

## Current checkpoint

| Item | State |
|---|---|
| P064 | **DONE** — both EPICs merged |
| P064 delivery baseline | `2a1ca60` |
| Checklist handoff on `main` | `e1341be` |
| Local release | `v2.61.0` at `193fd4a` |
| Remote | intentionally not pushed; `origin/main` remains `3fc14ae` |
| E-064-2_2 targeted boundary suite | 241/241 at reviewed HEAD, hash-bound receipt |
| Accepted waivers | `bats_all` quarantine, `plan_diff` quarantine, CP3 revision disagreement |
| C3 | real plan AC source proven; final result `unverifiable`, zero findings, targeted receipt not consumable by the sealed manifest |
| Next work | Phase 1 manual maintenance; **do not start P068 yet** |

The E-064-2_2 Curator used provisional labels `IMP-270…IMP-279` from a task
branch that did not contain the canonical backlog update. Canonical `IMP-270`
is already the gate-scoped waiver. Do not copy those provisional numbers into
the project backlog; deduplicate and renumber any surviving Curator proposals
from `IMP-271` onward.

## Outcome

Reach E10 only after AID has:

1. a reliable plan-level release cadence;
2. scoped, auditable waivers instead of broad FSM bypasses;
3. controller-owned long-running jobs and replay-safe step advancement;
4. an audited, isolated and materially shorter test portfolio;
5. completed risk-based profiles; and
6. a re-grounded E10 plan whose preconditions match the current repository.

This order is deliberate:

```text
P064 close
  → critical maintenance
  → P068 plan-final cutover
  → P066 test audit/scheduler + remediation
  → P061 E4/E5 completion and P061 close
  → P062 re-grounding/preflight
  → P062 E10 execution
```

## Temporary policy currently in force

- [ ] Keep `bats_all` quarantined in the AID self-host
  `.aid-o/config/execution.yaml`.
- [ ] Do not invoke `bats_all` directly or through `full`/`release`.
- [ ] Treat its quarantine result as `waived`/`profile_excluded`, never `pass`.
- [ ] Treat the current `plan_diff` timeout as unresolved/waived, never `pass`.
- [ ] Use affected targeted suites with terminal, HEAD-bound evidence.
- [ ] Never run two gate/test commands concurrently against the same mutable
  repository unless a scheduler has proved them isolated.
- [ ] Preserve the E-064-2_2 waiver, `exit 143` cancellations and
  `plan_diff exit 124` as evidence. Do not rewrite them green.

The local quarantine is temporary operating configuration, not a shipped AID
feature. It remains until the P066 exit criteria below are met and the PM
explicitly removes it.

## Phase 0 — close P064 honestly

- [x] Finish the single targeted
  `test-aid-plan-release-boundary.bats` run on the reviewed HEAD.
- [x] Store its terminal exit code, test counts, command fingerprint and HEAD.
- [x] Perform at most one C3 recheck focused on the corrected AC evidence.
- [x] Do not open another broad exploratory review loop from that recheck.
- [x] Run Curator, Auditor and CP4 against the same frozen revision.
- [x] Close and merge E-064-2_2, then close P064.
- [x] Create the local `v2.61.0` release/tag.
- [ ] Push `main` and `v2.61.0` only when explicitly authorized.
- [ ] Confirm the installed plugin cache resolves `v2.61.0` before Phase 1
  implementation starts.
- [x] Preserve all quarantine/waiver evidence in the delivery report.

**GO to Phase 1:** P064 is merged and closed; main and the plugin cache resolve
the same released plugin code.

## Phase 1 — critical manual maintenance before P068

These changes repair the mechanisms that would otherwise orchestrate their
own broken implementation. Implement and verify them manually outside
`/aid-run`, in small independent commits. Do not combine them into one large
plan.

### 1A — gate-scoped waiver (file as IMP-270)

- [ ] Replace broad transition `--force` for gate exceptions with a
  gate-scoped authorization.
- [ ] Bind authorization to project, plan/EPIC, run, exact HEAD, gate ID,
  command fingerprint, authorizer, reason and expiry/single use.
- [ ] A waived required gate is reported as `waived`, never `pass`.
- [ ] Every unrelated gate and FSM precondition remains enforced.
- [ ] Missing, stale, forged or mismatched authorization fails immediately.
- [ ] Add negative tests proving a `bats_all` waiver cannot waive
  `plan_diff`, CP3 freshness, another HEAD or another run.

### 1B — AUTO liveness and replay safety

- [ ] **IMP-262:** controller-owned job supervisor with durable terminal
  receipts, process-group ownership, resume/collect and no orphan watchers.
- [ ] **IMP-263:** idempotent `increment-step`, bound to the exact step,
  plan-step hash, reviewed commit and idempotency token.
- [ ] Prove that duplicate invocation advances once and that a renamed
  previous-step verifier cannot complete the next step.

### 1C — audit and lineage integrity

- [ ] **IMP-269:** C3 records and enforces
  `ac_source: plan|final_report_fallback|stub`; required AC lenses accept only
  the explicit plan source.
- [ ] Extend **IMP-269** to bind test evidence as well as AC evidence:
  accept a revision-bound, command-fingerprinted targeted-run receipt in the
  sealed manifest, or seal a narrowly allow-listed recheck command. A
  quarantined gate must not force C3 to `unverifiable` merely because valid
  targeted evidence has no manifest channel.
- [ ] Preserve `unverifiable` as distinct from `fail`; C3 must not be promoted
  to blocking while the quarantine/targeted-evidence contract is unresolved.
- [ ] **IMP-264:** compute evidence freshness at read time; stop trusting a
  persisted `head_is_current: true`.
- [ ] **IMP-265:** lineage omission defaults to `unproven`; healthy repair is
  idempotent and preserves valid attestations.
- [ ] **IMP-267:** attestation re-derives merge/base ancestry from Git.
- [ ] **IMP-258:** repair propagates per-write failures instead of swallowing
  them through `|| true`.
- [ ] Decide **IMP-266:** audited reopen from an incorrect
  `merged_to_plan`, or a documented deliberately terminal recovery ceremony.

### 1D — P064 dormant-path blockers owed before P068

These were non-blocking for P064 because its lifecycle manifest remained
`legacy_epic_release_mode`. They become live the moment P068 enables the new
path.

- [ ] Make `plan-start --mode` explicit. Omission must not silently default
  to `plan_branch`; alternatively refuse `plan_branch` until
  `plan-finalize` and `plan-merge-to-main` are installed.
- [ ] Constrain queue `merge_target` semantically, in both contract twins, to
  the owning `plan/Pxxx` branch or resolved target branch. A hand-edited
  dependency branch must not self-satisfy ancestry.
- [ ] Route `cmd_init` through the same fail-closed committed-manifest mode
  authority as `done-advance`. Missing `yq`, malformed manifests and unknown
  modes must resolve to `unresolved`, never silently to legacy.
- [x] Replace the second `grep -oP` in `aid-queue-add.sh` (`f60efab`).
- [ ] Widen the regression guard from one `$FSM` file to every relevant
  `plugins/aid-orchestrator/scripts/**` shell source so the same portability
  defect cannot be reintroduced elsewhere.
- [ ] Correct the new enforcement rows that claim `active` behavior whose
  P068 reader does not exist yet; writer-only controls remain
  `planned`/`unmapped`.

**Verification policy:** targeted red-green suites only. The quarantined
`bats_all` is not a required implementation check for this maintenance.

**GO to Phase 2:** scoped waivers, job ownership, replay-safe steps and the
AC/lineage fixes are released and present in the plugin cache.

## Phase 2 — re-ground P068 before execution

P068 is already drafted and EPIC files exist, but it was authored before P064
finished. Do not execute the existing generated tasks without this pass.

- [ ] Verify every P064 interface and artifact against post-merge main.
- [ ] Update stale paths, commands, schemas, counts, version assumptions and
  acceptance commands.
- [ ] Re-run plan lint, dependency/artifact ownership checks and bounded C0.
- [ ] Regenerate P068 EPIC files only after the reviewed plan is final.
- [ ] Carry every unresolved P064 handoff finding explicitly.
- [ ] Add the following mandatory **full-suite-last** cadence:
  1. targeted checks and exploratory reviews run first;
  2. fixes converge before candidate freeze;
  3. one frozen candidate receives the plan-final expensive gates;
  4. a production fix invalidates the candidate and may justify one rerun;
  5. further reruns require a gate-scoped PM/Codex decision;
  6. no concurrent gates against one mutable worktree.
- [ ] While quarantine is active, plan-final evidence must display the waived
  `bats_all`/`plan_diff` status and use approved targeted evidence. It must not
  claim a clean full-suite result.

**GO to Phase 3:** P068 is re-grounded against released P064 and its generated
EPICs match the reviewed plan byte-for-byte.

## Phase 3 — deliver P068

- [ ] Deliver candidate synchronization and immutable freeze.
- [ ] Deliver one plan-final gate/review stack per plan.
- [ ] Deliver plan-mode C4 and exact-SHA PM/Codex authorization.
- [ ] Deliver compare-and-swap merge, one tag/push and durable close receipt.
- [ ] Complete cutover and remove obsolete per-EPIC release instructions.
- [ ] Dogfood the complete multi-EPIC path on tracked changes.
- [ ] Demonstrate that intermediate EPICs do not run the release stack.
- [ ] Demonstrate that a plan normally pays the expensive release boundary
  once, not once per EPIC.

**GO to Phase 4:** `plan_branch` is the proven default for new plans and the
legacy path remains explicitly available for already in-flight plans.

## Phase 4 — P066 test portfolio audit, scheduler and remediation

P066 is currently an interim specification, not an executable plan.

- [ ] Convert
  `.aid-o/work/interim-P066-test-portfolio-audit-and-parallel-execution.md`
  into a grounded executable plan.
- [ ] Explicitly include both `bats_all` and `plan_diff` as primary incidents.
- [ ] Inventory every configured test entry point and stable test identity.
- [ ] Prove which tests protect real behavior and which are duplicate, stale,
  flaky, mock-only or unnecessarily expensive.
- [ ] Identify live-repository, Git, `.aid-o`, port, Docker, database,
  environment and filesystem interference.
- [ ] Stream per-suite output while running; never retain the only diagnostic
  in memory until the aggregate ends.
- [ ] Give every run controller ownership, a process group, a deadline,
  separate logs and a terminal receipt.
- [ ] Build deterministic, resource-aware batches. Unknown isolation remains
  sequential.
- [ ] Compare sequential and parallel membership and verdicts before
  promotion.
- [ ] Generate and approve a separate AID self-host remediation plan.
- [ ] Execute that remediation plan: repair isolation/performance, remove or
  quarantine tests only with explicit PM approval.

### Quarantine exit criteria

Do not restore the real `bats_all` command merely because one run happens to
pass.

- [ ] No configured test entry point is missing from the catalog.
- [ ] No overlapping runner can mutate the same live state without a lock or
  isolated workspace.
- [ ] A failure identifies the exact suite/test before the aggregate exits.
- [ ] Sequential and scheduled runs have identical membership and verdicts
  across the calibrated sample.
- [ ] Cancellation/restart cannot orphan work or duplicate a run.
- [ ] `plan_diff` no longer launches an opaque nested aggregate against live
  mutable state.
- [ ] A PM-approved measured runtime target is met. Proposed target for the
  P066 writer to validate: AID self-host full-suite p95 at or below 20 minutes
  on the reference host, without reduced coverage.
- [ ] The restored command, timeout, retry and concurrency settings are based
  on measured post-remediation data.
- [ ] PM explicitly removes the quarantine.

**GO to Phase 5:** the quarantine is removed by a reviewed change and full
suite execution is isolated, diagnosable and materially shorter.

## Phase 5 — finish and close P061

P061 determines **which** tests run. P068 determines **when** expensive
validation runs. P066 makes the remaining run efficient.

- [ ] Re-ground P061 E4/E5 against the P064/P068/P066 implementation.
- [ ] E4: finish project/consumer distribution of gate profiles and safe
  `/aid-init` upgrade behavior.
- [ ] E5: finish `/aid-do` no-bypass risk escalation and the generic release
  invocation.
- [ ] Reconcile anything superseded by P064/P068 rather than implementing it
  twice.
- [ ] Resolve the denominator explicitly: current design treats E1–E5 as
  required and E6 as backlog/out-of-scope. Record that in the durable
  lifecycle manifest and plan closure evidence.
- [ ] Close P061 only after every required EPIC is delivered and accepted.

**GO to Phase 6:** P061 is durably closed and consumer projects can use the
same risk-based profiles instead of AID self-host-only configuration.

## Phase 6 — re-ground P062/E10

The current P062 document is stale and must not be executed as written:

- it says P061 must merge all six EPICs, while the current P061 design treats
  E6 as non-blocking backlog;
- it reports only P061 E1 as merged;
- it targets version 2.56.0 although the repository is already beyond 2.60;
- it predates the P064/P068 cadence, P066 scheduler and current C3 evidence
  contract.

Required work:

- [ ] Re-read every P062 citation, path, command and schema against current
  main.
- [ ] Resolve and document the P061 denominator mismatch; never satisfy it by
  fake merge counts.
- [ ] Replace stale version numbers with a release-time version policy.
- [ ] Make speed calibration consume P061 profile events, P063 baselines,
  P066 scheduling context and P068 plan-boundary cadence.
- [ ] Verify non-zero real C3 hook evidence from P065-era runs.
- [ ] Resolve IMP-179 instruction/cache freshness prerequisite.
- [ ] Resolve IMP-201 or explicitly keep the affected C4 control in observe.
- [ ] Run bookkeeping hygiene preflight without mutating unrelated plans.
- [ ] Re-run lint, CP1/C0 and independent plan verification with a bounded
  review budget.
- [ ] Regenerate P062 EPICs from the final reviewed plan.

**GO to Phase 7:** every E10 hard precondition is executable and true on
current main; no prerequisite depends on stale prose or obsolete bookkeeping.

## Phase 7 — execute P062/E10

- [ ] Build the preflight and freshness evidence.
- [ ] Measure detection, false-DONE, false-positive and unique-detection
  behavior.
- [ ] Measure wall-clock, profile savings and full-suite/scheduler cost.
- [ ] Run the grounded regression dataset and old-vs-new dual run.
- [ ] Calibrate C4 content verdict and risk-profile escalation.
- [ ] Produce a per-control decision table:
  `promote_to_blocking|keep_observe|keep_dual_run|defer|E11-removal-candidate`.
- [ ] Promote only controls supported by evidence and satisfied
  preconditions.
- [ ] Delete no legacy control in E10; removal belongs to E11.
- [ ] Publish the E10 report, release and durable plan closure.

## Explicitly deferred

These do not block the path to E10 unless reclassified by a fresh finding:

- IMP-268 debug CLI hardening;
- IMP-255–257 and IMP-259–260 refactoring/diagnostic cleanup;
- IMP-261 INIT/SETUP redesign implementation (analysis may proceed
  independently, but do not fold it into P068/P066/E10);
- E11 legacy-control deletion;
- cross-plan train releases and parallel implementation agents.

## PM stop rules

- A waiver never becomes a fabricated pass.
- No full-suite retry starts automatically after the bounded allowance.
- No background job without an owned terminal receipt can block AUTO.
- A new unrelated audit finding is classified and recorded; it does not
  silently expand the current delivery scope.
- A direct regression of the invariant currently being fixed remains a
  blocker.
- Any proposed removal of test coverage requires explicit PM approval.

## Implementer progress log

The implementer owns this section during Phase 1. Append one row after every
independently reviewable commit; do not rewrite earlier rows.

| UTC date | Batch | Commit | Targeted red/green evidence | Independent review | Remaining blocker |
|---|---|---|---|---|---|
| 2026-07-23 | P064 baseline | `2a1ca60` | boundary 241/241; three waivers remain visible | Auditor 89/100, no merge blocker | Phase 1 not started |

When Phase 1 finishes, update the top-level checkpoint, mark only genuinely
completed checkboxes, and record the released version plus cache SHA.
