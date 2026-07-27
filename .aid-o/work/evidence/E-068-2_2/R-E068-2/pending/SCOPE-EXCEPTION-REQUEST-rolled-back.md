# Scope-exception request — `ROLLED_BACK` support in two lib files

**Status: NOT COMMITTED. Implemented, tested and held pending a PM decision.**

`plan-rollback` is committed (`d4067c8`) and its tests pass, but the state it
writes cannot exist without two small changes in files this EPIC does not own.
Both are applied in the working tree, verified live against P075, and captured in
`ROLLED_BACK-state-support.patch`.

## 1. `lib/aid-plan-state.sh` — the state and its one transition

- adds `"PLAN_MERGING:ROLLED_BACK"` to the legal transition table;
- adds `ROLLED_BACK` to the known plan-state set.

Nothing else. `ROLLED_BACK` is reachable from exactly one state — a plan whose
merge was published — and is terminal.

## 2. `lib/aid-plan-manifest.sh` — ROLLED_BACK may carry a candidate

One entry added to the candidate-bearing state set, for the same reason
`ABORTED` was added under the previous authorization: a rolled-back plan RETAINS
the candidate that was merged and then reverted, because that SHA is half the
rollback record. Without it the manifest mirror cannot hold the state and
`plan-state` under-reports — exactly the F3 shape.

## Verified live, on the real P075

```
plan-rollback P075 --revert-commit dd80b914
ROLLED BACK: P075 merged as a79918da and was reverted by dd80b914; main is back
at its pre-merge tree (37efd31a) with both commits still reachable.

plan_state (authoritative) = ROLLED_BACK
plan_state (mirror)        = ROLLED_BACK
plan_final_rollback        = {result: rolled_back, merge: a79918da,
                              revert: dd80b914, cand: 801140bf,
                              before: 37efd31a}
marker                     = plan-rollback-complete
```

Before these two changes the same command left the plan ROLLED_BACK in
`plan-state.yaml` and `AWAITING_PM` in the mirror, with a warning — honest, but a
wrong answer to every reader.

## What the authorization would cover

Exactly the two edits above. No refactor, no other transition, no other change to
the manifest contract. `AC13` (5 cases) and the AC5 mirror regressions are the
red-green evidence; the ABORT path is asserted to still refuse a published merge,
so the new state does not weaken the old contract.

## Still outstanding, NOT in this request

`plan-close-check.sh` reads the delivery report's `Head` from YAML frontmatter
while the P075 report carried a bare line. The Reporter's agent card is fixed
(committed) to say plainly where it goes; whether the CHECK should also accept a
bare line is a separate contract decision and is not bundled here.
