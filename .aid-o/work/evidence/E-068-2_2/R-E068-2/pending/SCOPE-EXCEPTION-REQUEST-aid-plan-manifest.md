# Scope-exception request — two changes in `lib/aid-plan-manifest.sh`

**Status: APPLIED 2026-07-27, under explicit PM authorization.**

> PM autorizuje scope extension E-068-2_2 na
> `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` výhradně pro:
> odstranění přechodu `pending:merged_to_plan` z obou transition tables a
> povolení `ABORTED` v candidate-bearing state invariantu. Důvod: oba defekty
> byly přímo reprodukovány autorizovaným P067 dogfoodem a jsou nutnou součástí
> F2/F3 closure. Autorizace nezahrnuje jiné refaktory ani změny manifestového
> kontraktu.

Both changes are applied and nothing else in the file was touched: no refactor,
no other contract change. The regression that could not pass before — `AC5:
after an ABORT, plan-state agrees with the authoritative state file` — is back
in the suite and green, and it additionally asserts the abandoned candidate is
RETAINED, which is the whole reason ABORTED had to join that state set.

`plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` is in EPIC 1's
`allowed_paths`, not EPIC 2's, so the commit-scope hook refuses it in the state
this run is in. Both changes below are required by PM-ordered fixes, and neither
was committed out of scope or bypassed with `--no-verify`.

## 1. Remove `pending:merged_to_plan` from the transition table (F2)

PM instruction of 2026-07-27: *"Samotná cesta `pending → merged_to_plan` se
odstraní."*

Defence in depth rather than the primary fix — the completion gate committed in
`9b7889c` refuses a `pending` EPIC before the transition table is ever consulted,
which AC12's first case asserts. The table should still lose the edge: a pending
EPIC has completed nothing, so the route should never have existed.

The change is stashed (`git stash list`) and is a two-line edit: drop
`"pending:merged_to_plan"` from both the documentation array and the jq
`$legal_transitions` list.

## 2. Allow `ABORTED` in the candidate-bearing state set (F3)

Found while closing the P067 dogfood, and it is a genuine inconsistency:

```
$ aid-plan-fsm.sh plan-merge-to-main P067 --decision <ABORT>
PM DECISION ABORT: ... P067 is now ABORTED
$ aid-plan-fsm.sh plan-state P067
{"plan_state":"AWAITING_PM", ...}
```

The command says ABORTED and the very next query disagrees. `plan-state` reports
from the runtime manifest's `plan_state` mirror; `plan-state.yaml` (the
authority) does say `ABORTED`. The merge path mirrors its `CLOSED` transition,
the abort path did not — and when I added the mirror write it was refused:

```
PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=P067 —
candidate_sha is set while plan_state is too early (not in
PLAN_GATES/PLAN_REVIEW/AWAITING_PM/PLAN_MERGING/CLOSED)
```

So the mirror *cannot* hold `ABORTED` while a candidate is set. An aborted plan
deliberately RETAINS its abandoned candidate — the abort message names it, and
the close record asserts the target branch is unchanged against it — so clearing
the candidate is the wrong fix. `ABORTED` belongs in that state set.

Committed already in `aid-plan-fsm.sh`: the abort path now attempts the mirror
write and, when refused, warns explicitly that `plan-state` will under-report
until reconciled. That is honest but not sufficient — it is a warning about a
known-wrong reading, not a correct reading.

Also pending: the regression `AC5: after an ABORT, plan-state agrees with the
authoritative state file`, which cannot pass until the invariant admits ABORTED.
It is written and removed from the suite rather than left red.

## What is affected while this is unresolved

An aborted plan reports `AWAITING_PM` from `plan-state` and from any reader of
the manifest mirror. Nothing merges — the authoritative state is correct and
every guard reads it — but a PM or a tool asking "what state is this plan in?"
gets the wrong answer for an aborted plan. P067 is in exactly this state now.
