# Verifier output step 0

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T17:55:59Z
classification: FULL_REVIEW
verdict: pass
checkpoint: cp2
reason: One real defect found and fixed — the mode stamp was written to the worktree but never committed, so the git-tracked authority declared nothing. Fixed in 750b155 with a regression that asserts the committed copy.

## Finding — the stamp was not durable (FIXED in 750b155)

`aid_lifecycle_ensure_manifest` commits what it writes, and the step applied
`mode` with `yq -i` afterwards. The mode therefore lived only in the worktree
while the committed manifest — which `_fsm_declared_plan_mode` reads from
target_branch's tree — carried none. A plan created under the new default would
have declared nothing at all, which is the same silent-downgrade shape the step
exists to close.

The first fix attempt (re-calling ensure_manifest) was ineffective: it returns
early once the manifest is durable and rebuilds it from the plan otherwise, so
it neither knows nor preserves the field. The shipped fix commits the stamp
through the lifecycle layer's isolated-index path and then reads it back from
target_branch, failing closed under plan_branch when the read-back disagrees.

## Verified

- `inventory` mutates only under `--apply`, and only for a plan whose mode is
  `none`; the read-only run was asserted byte-identical.
- An unknown declared mode is refused before any mutation for that plan.
- A plan id matching no plan file and no queue entry is refused rather than
  invented.
- The default flip is guarded on the `gate_profiles` table and falls back with
  a logged `plan_branch_unavailable: no_gate_profiles`; an unknown policy value
  also fails closed to legacy and names the value.
- A project can opt out through its own policy copy.
- `defaults/templates/plan.md` still emits `lifecycle_strict: true` — verified,
  not edited.

## Tests

AC8 block 11/11. AC7 and the delegation regressions re-run clean at 31/31 on the
step's own tree.
