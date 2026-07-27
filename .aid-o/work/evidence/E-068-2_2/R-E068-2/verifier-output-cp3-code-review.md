# CP3 integration review — code-review focus

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T19:04:24Z
classification: FULL_REVIEW
verdict: pass
checkpoint: cp3
focus: code-review
reviewed_range: 4b50272..HEAD
reason: One recurrence of this EPIC's own durability defect found and fixed with a regression; the mode resolver, the migration path and the crash seam each hold their invariant.

## Finding — the durability defect recurred (FIXED in b030623)

`inventory --apply` stamped the lifecycle manifest with `yq -i` and reported
success. The manifest is the git-tracked authority exactly because a worktree
file proves nothing: `_fsm_declared_plan_mode` answers from the target branch's
committed tree. So every plan the inventory called "stamped" still declared
nothing where it counts, and — worse — the table asserted a migration state that
did not exist.

This is the SECOND occurrence of the same defect in this EPIC; the first was the
auto-pipeline stamp, fixed in step 1. That it recurred in a different file
written the same night is the useful signal: "write the file" and "make the
declaration durable" are separate acts, and the second is easy to forget because
the first looks finished.

The fix commits through the isolated-index path and reads the value back from
the target branch, reporting `stamp_not_durable` and returning non-zero when the
read-back disagrees.

## Verified sound

- `inventory --apply` stamps only a plan whose mode is `none`, so it can never
  overwrite an existing declaration or migrate a plan.
- An unknown declared mode is refused before any mutation for that plan; an
  unknown policy value fails closed to legacy and names the value.
- The default resolver can only return `plan_branch` when the project declares a
  `gate_profiles` table; every other path yields legacy with a reason.
- The auto-pipeline's escape hatch is closed under `plan_branch` and survives as
  an explicit, logged `AID_LIFECYCLE_MIGRATION=1` override.
- The three standing checks (control-boundary, instruction-sweep, skill-lint)
  all pass, and the first two were each proven to FAIL on a fixture.

## Carried to the backlog

- The live dogfood and its four dependent acceptance criteria, which need PM
  authorization because they advance the real target branch.
- The `plan_finalize_c4_reader_gap` recorded in the registry: the c4 stage
  validates three inputs no step of EPIC 1 produces.
