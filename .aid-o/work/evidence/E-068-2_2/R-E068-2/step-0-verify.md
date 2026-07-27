# Step 1/5 (index 0) — step_1_backend — Verification

## What the step delivered
The in-flight inventory and the default mode flip: `aid-plan-fsm.sh inventory`
(+ `--apply`), `defaults/policies/plan-boundary-policy.yaml`, the guarded
default-mode resolver, and the auto-pipeline changes that stamp the mode into
the git-tracked lifecycle manifest and close the manifest-write escape hatch.

## Acceptance criteria

- [x] A new one-EPIC plan follows `task → plan → main` — the pipeline now calls `plan-start` for a plan with no state and stamps the resolved mode; no special case is made for one-EPIC plans.
- [x] Existing active plans are inventoried and stamped `legacy_epic_release_mode` without migration — asserted, including that no branch is created.
- [x] New plans default to `plan_branch` only when the project's `execution.yaml` declares a `gate_profiles` block, and otherwise fall back to legacy with a logged `plan_branch_unavailable: no_gate_profiles`.
- [x] Missing, unknown or mixed mode exits non-zero before mutation — an unknown declared mode is refused with the manifest byte-identical, and an unknown policy value fails closed to legacy naming the value.

## Test evidence
AC8 block **11/11**; AC7 + delegation regressions **31/31**.
Logs: `scratchpad/ac8e.log`, `scratchpad/s1-regress.log`.

## CP2
Verdict **pass**, one real defect found and fixed (see `verifier-output-step-0.md`).

## Note for the plan
This step is what makes the pre-plan-final blocker recorded in E-068-1_2's CP3
fixable: `inventory` can now stamp P068 explicitly. The stamp itself is a
separate, deliberate act and is not performed here.

## Memory Used
- N/A — no relevant memory entries found (reason: the step's context is the plan text and the code it names).

## Memory Written
- N/A — no new reusable patterns introduced (reason: the durability lesson is already recorded in the commit and the CP2 output).

step_index: 0
step_id: step_1_backend
plan_step_hash: 8901ef2175a08702f37f0b174f6197b74e3501c8b695eae51e9fc55113d3df91
reviewed_commit: 750b155da3d7443174f7fd7cfe2ce374c2239b01
idempotency_token: E-068-2_2-R-E068-2-step-0-750b155

## Result: PASS
