# EPIC-generation integrity — implementation contract

**Status:** active manual maintenance on `fix/epic-generation-integrity`.

## The problem in plain language

A plan must be checked before it is split into EPICs.  The old flow asked for
a graph that was only produced after splitting, so a valid plan could be
blocked waiting for an artifact that it was itself prevented from producing.

The repair must not turn that false block into a blind pass.  It gives each
artifact one owner and one meaning, then proves that the generated EPIC package
still matches the reviewed source plan before any strict plan starts work.

## Artifact ownership

| Artifact | Owner | Meaning | Consumer |
|---|---|---|---|
| `generation/provisional-graph.json` | readiness | Whole-plan graph parsed from source plan before generation | C0 / CP1 |
| `c0/plan-graph.json` | `aid-c0-contract.sh` | Contract graph of one generated `plan.json` | C0 contract checks |
| `generation/final-graph.json` | generation finalizer | Whole-plan graph reconstructed/verified from all generated EPIC mappings | finalizer |
| `generation/receipt.json` | generation finalizer | Hash-bound proof that source graph, all phases and generated artifacts agree | strict/high-risk init |

No artifact may stand in for another. In particular, the provisional graph is
never written to `c0/plan-graph.json`, so later EPIC contract production cannot
overwrite pre-generation evidence.

## Required execution order

1. Lint and parse the source plan through the shared fail-closed parser.
2. Write the provisional whole-plan graph and bind it to the exact source-plan
   SHA. C0 receives it as a named input.
3. Generate **all** EPIC files and their `plan.json` files, without starting or
   queuing any EPIC.
4. Finalizer verifies the complete phase set and source-plan bindings, writes
   final graph + receipt atomically.
5. Only then may auto-pipeline create runs, initialise FSM state and queue
   EPICs. Strict/high-risk init requires the receipt; legacy plans retain their
   explicit migration path.

This order is essential: adding a receipt check to the old per-phase init loop
would reproduce the same producer-before-consumer deadlock.

## Compatibility and failure policy

- New strict/high-risk plans fail closed on missing, stale or mismatched
  generation receipts.
- Legacy/in-flight plans are not retroactively blocked; they remain loud,
  explicitly classified migration runs.
- Direct single-phase generation may create an EPIC, but cannot claim a
  complete-package receipt. The error must point to the sanctioned finalizer
  or auto-pipeline, not to a generic PM override.
- A malformed dependency declaration, ambiguous path list, missing phase,
  duplicate phase, source SHA mismatch or final-graph disagreement is an
  actionable hard failure before FSM state is written.

## Tests required before merge

1. Valid P074-style plan: no previous graph, valid source graph, no override.
2. One-line and multi-line dependencies produce identical graph semantics.
3. Malformed/missing/self/forward/cyclic dependency fails before any EPIC write.
4. `a.md`, `b.md` fails; `a.md` + `b.md` preserves both paths.
5. Source graph and per-EPIC C0 graph coexist and are both sealed correctly.
6. Missing phase, modified EPIC metadata, modified `plan.json`, or graph
   disagreement prevents receipt and strict init.
7. Complete package creates one receipt; strict init succeeds only afterwards.
8. Legacy plan remains operational with an explicit migration record.

## Deliberately excluded

CP2 orchestration, generic delivery-gate `required_when` policy and test-suite
scheduling are independent work. They are not smuggled into this repair.
