# Verifier output step 1

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T18:41:42Z
classification: FULL_REVIEW
verdict: pass
checkpoint: cp2
reason: The seam is inert unless explicitly set and can only cause an exit; the matrix exercises real process death at every boundary and the 68-test AC5+AC7 regression confirms normal operation is unaffected.

## Reviewed

The `AID_PLAN_FSM_CRASH_AFTER` seam and the AC9 matrix.

## Security consideration — a deliberate crash path in shipped code

A test seam that can terminate a transactional command is worth scrutinising,
because a seam that could be triggered accidentally would be a denial-of-service
on the release boundary. Checked:

- It is a no-op unless the environment variable is set AND names the exact phase
  being recorded; there is no wildcard, no numeric form and no default.
- Its only effect is `exit 99`. It writes nothing, moves no ref and changes no
  state, so an induced crash is indistinguishable from a power cut at that point —
  which is precisely what makes the matrix meaningful.
- 99 is outside every exit code this script uses, so a test cannot mistake an
  induced crash for a genuine failure, nor the reverse.
- It fires AFTER the phase record, never before, so the state the resume finds is
  the state the specification promises at that boundary.

## Verified by execution

Each matrix case was run against real Git state, not fixtures: the merge is
genuinely published before the git_applied crash, and the resume genuinely
reuses it (exactly one merge commit on the target branch). Two consecutive
crashes at the same boundary converge identically, so the resume is not
one-shot. The rollback case asserts the merge is still an ancestor of the target
branch after the revert — the difference between reverting forward and rewriting
history.

Two defects in the tests themselves were found and fixed before the pass: an
invented `terminal_reason` field (the decision schema is closed and names it
`reason`, so the decision was rejected as malformed and never reached the abort
path), and a revert applied to whatever branch HEAD pointed at rather than to
the target branch — which proved nothing, since the controller's worktree sits
on the plan branch after a close.

## Tests

AC9 7/7. AC5 + AC7 re-run at 68/68 with the seam present and unset.
