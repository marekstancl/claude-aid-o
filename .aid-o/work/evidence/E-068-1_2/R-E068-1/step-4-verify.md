# Step 5/6 (index 4) — step_5_backend — Verification

## What the step delivered
The compare-and-swap merge of the frozen plan candidate onto the target branch:
`plan-merge-to-main` validates the PM decision against the frozen candidate
binding, publishes the merge with `git update-ref <ref> <new> <expected-old>`
so a concurrent advance of the target branch loses instead of being overwritten,
commits the lifecycle bindings by plumbing on top, creates at most one tag, and
pushes at most once behind an explicit opt-in.

## CP2 step review
Verdict: **pass**, with 4 MEDIUM and 8 LOW findings. All four MEDIUMs were fixed
in `5ec3a62` (see that commit message for the per-finding detail):

- M1 — the stale-authorization guard could be disarmed by any recorded
  `resulting_sha`, letting a CAS publish land against a head the PM never
  approved. Now disarmed only when our own published merge explains the head.
- M2 — the merge op key was plan-id-only, so a second legitimate attempt was
  misread as a crash resume (fail-closed, but a false diagnosis). Now keyed on
  the candidate.
- M3 — stage-2 failure prescribed a re-run that its own clean-worktree
  precondition refused. The precondition now exempts the command's own
  `.aid-o/` runtime workspace once the merge is published.
- M4 — the `pre-push` exemption matched only the local side of a refspec, so
  `git push origin plan/P068:main` slipped the target branch through. Both
  sides are now checked; proven end-to-end in a disposable repository whose
  state makes the guard genuinely block.

The 8 LOWs are recorded in the CP2 findings file and carried to the EPIC's
integration review (CP3); none of them affect the boundary invariant.

## Test evidence
Command: `bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats`
Result: **111 ok / 0 not ok**, run on this step's own commit tree.
Log: `scratchpad/step5-final.log`.

Note: the suite reliably hangs in teardown after emitting all 111 results; the
result lines are complete and the hung process was terminated after collection.
That hang is a known suite-level defect, not a failure of the code under test.

One test-artifact defect was found and fixed while running: the decision helper
hardcoded `decided_at: 2026-07-26T00:00:00Z`, which silently became "before the
freeze" once real time passed midnight, so all AC5 refusal tests failed on the
freshness guard instead of the cause each isolates. It now derives from the
manifest's actual `candidate_frozen_at` and is time-independent.

## Scope
Only files inside this step's `allowed_paths` were modified:
`aid-plan-fsm.sh`, `defaults/hooks/pre-push`,
`tests/bats/test-aid-plan-final-boundary.bats`.

## Acceptance criteria

- [x] Missing, `FIX`, `ABORT`, stale, malformed, wrong-plan, wrong-candidate decisions each refuse the merge and leave the target branch unchanged (AC5 block, 22/22).
- [x] A decision artifact that fails `pm-plan-decision.schema.json`, or whose binding fields do not match the frozen candidate, is rejected before any Git action.
- [x] The freeze-time validation is fail-closed on every degenerate input: a missing, empty or unparseable `candidate_frozen_at` refuses the merge.
- [x] A concurrent target-branch advance loses the compare-and-swap and returns the plan to PLAN_SYNC as a stale authorization (hardened by M1).
- [x] The merge commit is built without moving any ref; a failed publish leaves the target branch byte-identical.
- [x] The lifecycle commit advances the target ref by plumbing after the merge is published, with no checkout of the target branch.
- [x] No intermediate EPIC creates a version commit or tag; a plan resolving to no version bump merges and closes without one.
- [x] Resume after each transaction boundary creates no duplicate merge, no duplicate tag and no duplicate push (hardened by M2 and M3).
- [x] Pushing `plan/*` or `task/*` with `feat:`/`fix:` commits and no release commit is blocked, and the exemption cannot be used to push the target branch (hardened by M4, proven end-to-end).
- [x] Every abandoned or superseded EPIC is re-scoped in the lifecycle manifest as part of the close transaction.
- [x] After the merge, every non-abandoned EPIC has a `delivery_sha` binding.

## Memory Used
- N/A — no relevant memory entries found (reason: step-local hardening of code written earlier in this same EPIC).

## Memory Written
- N/A — no new reusable patterns introduced (reason: fixes are specific to this command's resume/CAS semantics).

step_index: 4
step_id: step_5_backend
plan_step_hash: 455737b9de2cb407d72e72d3c23f45c6879cdec0956a6420e92a3f1f51523912
reviewed_commit: 5ec3a62387b5234fee77031149c164d5dd9c7f3c
idempotency_token: E-068-1_2-R-E068-1-step-4-5ec3a62

## Result: PASS
