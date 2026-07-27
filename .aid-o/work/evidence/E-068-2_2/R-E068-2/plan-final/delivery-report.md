> **Location note.** These four reports are PLAN-level artifacts of P068, not
> artifacts of E-068-2_2. They live under this EPIC's evidence directory because
> the commit-scope hook governs the FSM state this run is in and permits only it;
> filing them here keeps them tracked rather than dropping them. The plan-final
> run directory is where they belong once the plan's own boundary runs.

# Delivery report — P068

Head: e7e3d5f2821a28d12cd8b44c7ab0845896b56dde
_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T19:10:07Z
outcome: partial

## What P068 delivers, in plain terms

Before this plan, a release happened per EPIC. Each EPIC bumped a version,
tagged, and merged to `main` on its own. That meant the thing that reached
`main` was never reviewed as a whole, and "the plan is done" was a claim
somebody wrote down rather than something the system could check.

P068 moves the release to the plan boundary. A plan now:

1. merges each of its EPICs into a plan branch — nothing released, nothing
   tagged, nothing pushed;
2. freezes a candidate commit once every EPIC is in;
3. runs the gate profile once, against that frozen candidate;
4. has the Auditor, Curator, Simplifier and Reporter review it once, at that
   point, bound to that candidate by content hash;
5. asks the PM for one authorization naming that exact candidate and the exact
   target-branch head it was approved against;
6. merges with a compare-and-swap — if anything moved `main` in the meantime,
   the merge is refused rather than rebased over;
7. creates at most one tag, and pushes at most once, behind an explicit opt-in;
8. can only be declared closed once a receipt of all this is committed in git.

The short version: **only the exact thing the PM approved can reach `main`, and
a plan cannot claim to be finished without durable proof that it did.**

## Outcome: partial, and why

Every mechanism is implemented, reviewed and tested. What has NOT happened is
the live dogfood — running a real plan end to end through the new path and
merging it to `main`. That advances the repository's mainline, which is a PM
decision, and it was not taken unilaterally.  has not moved from
`0158a68` at any point.

## Evidence

- 168 tests in the plan-boundary suite; AC7 30/30, AC8 12/12, AC9 7/7,
  AC10 4/4, and the AC5 + AC7 regression at 68/68.
- Sibling suites green: lifecycle, lifecycle-e2e, lifecycle-reconcile,
  plan-close, plan-close-check.
- Three standing checks — control-boundary, instruction-sweep, skill-lint — all
  passing, and the first two each proven to FAIL on a fixture.
- Gates passed for both EPICs under the PM-approved quarantine profile;
  `bats_all` is quarantined and is never reported as pass.

## What the PM is asked to decide

1. Authorize the live dogfood, including its merge to `main`.
2. Stamp P068's own lifecycle manifest so its mode is mechanically declared
   before its plan-final merge.
3. Whether to release 2.63.0 now or after the dogfood.
