# Step 2/5 (index 1) — step_2_qa — Verification

## What the step delivered
The single test seam `AID_PLAN_FSM_CRASH_AFTER` wired into all four
transaction points, and the AC9 resilience matrix that uses it to kill the
process for real at each boundary and assert what survived.

## Acceptance criteria

- [x] An EPIC merge conflict enters `CONFLICT` and records no completion — the conflict paths were already covered by the existing suite; this step adds the crash half of the matrix at the same boundaries.
- [x] A pre-merge abort leaves the target branch unchanged and records terminal evidence — asserted, including that the plan branch and evidence are preserved.
- [x] A hotfix on the target branch forces resynchronisation before candidate freeze — asserted via the stale-authorization path, with the plan returned to PLAN_SYNC.
- [x] Failure after the final Git merge but before the queue and close update is reconciled on resume — asserted: exactly one merge commit, and identical behaviour across two consecutive crashes.
- [x] Published rollback uses a new revert commit, never a history rewrite — asserted on the target branch, with the merge still an ancestor.

## Test evidence
AC9 **7/7**; AC5 + AC7 regression **68/68** with the seam present and unset.
Logs: `scratchpad/ac9b.log`, `scratchpad/s2-regress.log`.

## CP2
Verdict **pass**. Two defects in the tests themselves were found and fixed
before the pass (see `verifier-output-step-1.md`); no defect was found in the
production seam.

## Memory Used
- N/A — no relevant memory entries found (reason: the boundaries under test are this plan's own, defined in its Data Model section).

## Memory Written
- N/A — no new reusable patterns introduced (reason: the seam is specific to this FSM's phase records).

step_index: 1
step_id: step_2_qa
plan_step_hash: e75831e6672d6ad436e438e04806a32813a14f8a97a5261babd3891014042ee9
reviewed_commit: e12d1349506f0464e1d95fd0d4610112fdf9c500
idempotency_token: E-068-2_2-R-E068-2-step-1-e12d134

## Result: PASS
