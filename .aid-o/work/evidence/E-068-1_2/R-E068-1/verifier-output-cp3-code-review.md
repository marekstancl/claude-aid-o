# CP3 integration review — code-review focus

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T16:31:56Z
classification: FULL_REVIEW
verdict: pass
checkpoint: cp3
focus: code-review
reviewed_range: 0158a68..HEAD
reason: One fail-open finding on the mandatory-receipt path, found and fixed with a regression; the close ordering, atomicity and crash-recovery invariants hold on the reviewed HEAD.

## Finding — a missing lifecycle manifest downgraded a mandatory receipt (FIXED in e6df701)

For a `plan_branch` plan the `.aid-lifecycle` receipt is the only durable,
git-tracked proof that the plan reached its boundary. Both the close transaction
and Check 5.11 decided that on the presence of the FILE rather than the plan's
MODE, so a missing `.aid-lifecycle/manifests/<plan>.yaml` did not block — it
dropped the close into the legacy "predates the lifecycle layer, close without a
receipt" path, and the plan was declared CLOSED with no proof. That is the
inverse of AC7's "removing the manifest blocks close".

Both sites now key on the mode: under `--plan-branch` the absence blocks, while
the escape hatch stays available to legacy plans. Regression added and passing.

## Verified sound

**Close ordering.** In `aid-fsm.sh cmd_plan_close` the required-report gate is
at :5493, the irreversible plan-layer close at :5516, the EPIC marker at :5556.
Nothing durable precedes the gate; the only earlier writes are append-only
audit-log entries that change no state. (This ordering was itself the
pre-review finding, fixed in 42b0075.)

**Close atomicity.** check -> `plan_op_begin` (intent) -> receipt or abort
record (`git_applied`) -> marker via `.tmp` + `mv -f` -> `CLOSED` ->
`plan_op_commit`. The marker cannot be observed half-written. Every failure
path releases the lock and states what was and was not written.

**Crash recovery.** A crash between the receipt and the marker converges on
re-run: the plan-layer close is idempotent and the re-run completes only the
marker. Asserted directly by the delegation regression, which proves the receipt
blob and its commit count are unchanged across the re-run. An existing marker
whose preconditions no longer hold is reported `close_marker_invalid`.

**Restore-on-failure.** The plan-mode receipt path and the abort path both
restore their tracked files byte-identically on every failure branch, so the
prescribed re-run is actually runnable — the defect class this EPIC hit twice.

## Carried to the backlog

- Coverage of the `aid-fsm.sh` plan_branch mode-resolution and state-gate arms
  beyond the four delegation cases added in 42b0075.
- The CHANGELOG entry and enforcement-registry rows for the new `plan-close`
  gate and its Check 5 sub-checks — both files are outside every step's
  `allowed_paths` in this EPIC; carried to the plan's step 9.
- When the stale-auth guard fires from `PLAN_MERGING`,
  `plan_final_invalidate` cannot reach `PLAN_SYNC` (no legal transition) and
  the candidate binding is left in place. Publishing is still refused, so the
  invariant holds, but the recorded state does not match the message.
