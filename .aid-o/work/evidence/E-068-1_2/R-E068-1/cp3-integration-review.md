# CP3 — integration + security review (E-068-1_2)

_reviewer: controller (performed directly, not delegated — PM instruction 2026-07-26)
_scope: plan-close ordering and atomicity, crash recovery, Step 5 CAS and
        authorization invariants. Unrelated findings go to the backlog; no
        exploratory loop was opened.
_reviewed_range: 0158a68..HEAD

## Finding — a missing lifecycle manifest downgraded a mandatory receipt (FIXED)

For a `plan_branch` plan the `.aid-lifecycle` receipt is the only durable,
git-tracked proof that the plan reached its boundary, and the plan text calls it
mandatory. Both the close transaction and Check 5.11 decided that on the
presence of the FILE rather than the plan's MODE, so a missing
`.aid-lifecycle/manifests/<plan>.yaml` did not block — it dropped the close into
the legacy "predates the lifecycle layer, close without a receipt" path and the
plan was declared CLOSED with no proof. Inverse of AC7's "removing the manifest
blocks close", and the same fail-open shape as the earlier findings in this EPIC.

Fixed in `e6df701`: both sites key on the mode. Under `--plan-branch` a missing
manifest blocks; the escape hatch stays available to legacy plans, which is who
it was written for. Regression added and passing.

## Verified sound

**Close ordering (the CP3 pre-review finding, fixed in 42b0075).** In
`aid-fsm.sh cmd_plan_close` the required-report gate is at :5493, the
irreversible plan-layer close at :5516, the EPIC marker at :5556. Nothing
durable precedes the gate — the only earlier writes are append-only audit-log
entries, which record a skip decision and change no state.

**Close atomicity.** The transaction runs check -> `plan_op_begin` (intent) ->
receipt or abort record (`git_applied`) -> marker written to `.tmp` and moved
into place -> `CLOSED` -> `plan_op_commit` (state_committed). The marker is
published by `mv -f`, so a crash cannot leave a half-written one. Every failure
path releases the lock and states plainly what was and was not written.

**Crash recovery.** A crash between the receipt and the marker converges on
re-run: the plan-layer close is idempotent (`aid_plan_closure_state` reports
`closed`, no second receipt is built) and the re-run completes the marker. This
is asserted directly by the delegation regression added in `42b0075`, which
proves the receipt blob and its commit count are unchanged across the re-run.
An existing marker whose preconditions no longer hold is reported
`close_marker_invalid` rather than trusted.

**Step 5 CAS.** Only two code paths move `refs/heads/<target>`, and both are
compare-and-swap. The merge publish
(`aid-plan-fsm.sh:3892`) passes the frozen `target_head` as the expected old
value, and the commit exists as a dangling object until that call succeeds — a
rejected swap leaves the target byte-identical. The plan-mode plumbing commit
(`aid-lifecycle.sh:275`) passes the expected parent and short-circuits when the
rebuilt tree already matches it, so a resumed pass is a documented no-op.

**Step 5 authorization.** The PM decision is validated against the schema and
bound to plan, attempt, candidate and approved target head, and its `decided_at`
is checked against the manifest's `candidate_frozen_at`, all before any Git
action. The stale-authorization guard is disarmed only when our own published
merge explains where the target head is (M1), and the operation key names the
candidate so a new candidate is a new operation (M2).

## Carried to the backlog, not fixed here

- **M6 from CP2** — beyond the four delegation cases added in `42b0075`, the
  `aid-fsm.sh` plan_branch branch has no coverage of its mode-resolution or
  state-gate arms.
- **L2 from CP2** — the CHANGELOG entry and the enforcement-registry rows for
  the new `plan-close` gate and its Check 5 sub-checks. Both files are outside
  every step's `allowed_paths` in this EPIC; carried to the plan's step 9.
- **The stale-auth landing state** — when the guard fires from `PLAN_MERGING`,
  `plan_final_invalidate` cannot reach `PLAN_SYNC` (no such legal transition)
  and the candidate binding is left in place. Publishing is still refused, so
  the invariant holds, but the recorded state does not match the message.

## Verdict

**pass** — one finding, found and fixed with a regression; the boundary
invariants hold on the reviewed HEAD.

## Correction (2026-07-26, PM)

An earlier phrasing in this run described `plan_diff` as quarantined. It is not.
`execution.yaml` carries a `quarantine:` block on `bats_all` alone; in the
quick-profile gate run `plan_diff` was simply `profile_excluded`, like
`targeted_tests`, `shell_pipeline_smoke` and the two `ui_calibration_*` gates.
The distinction matters: a quarantined gate can never be reported as `pass` and
its exclusion is a standing risk acceptance, whereas a profile exclusion is an
ordinary scoping decision recorded in the report.

## Blocking item for plan-final (not for this EPIC)

P068 has no committed `.aid-lifecycle/manifests/P068.yaml`, so `mode:
plan_branch` is not mechanically declared for this plan. `_fsm_declared_plan_mode`
answers from the target branch's committed copy, so today it would resolve P068
to `legacy_epic_release_mode` and a later `done-advance review→release` could not
prove its entitlement to skip the planning stack. This must be resolved before
plan-final. It is explicitly NOT a reason to run per-EPIC Curator/Auditor: under
the target `plan_branch` model those roles belong at the plan-final boundary,
and the per-EPIC CP3 pair is what this EPIC owes — which is recorded above.
