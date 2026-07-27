# Targeted CP2/CP3 — the C4 producer wiring

_generated_by: controller (performed directly; the PM instructed that nothing in this run is to be delegated)
_generated_at: 2026-07-27T03:09:16Z
scope: commits bcebad5 (producer) and c63d55f (its CP2 fix) ONLY
reviewed_head: c63d55f1fa6115760e7ce73ec9bacdf6bcdb3238
verdict: pass

## Why this review exists separately

The plan-final specialist reports were written at `e7e3d5f`. The C4 producer
landed afterwards, at `bcebad5`. Reports that predate the change they are meant
to cover would be evidence of the wrong thing, so this is a narrow pass over the
producer wiring alone — not a re-audit, and deliberately not a re-run of the
whole suite.

## Finding — the producer could silently invalidate a completed review (FIXED in c63d55f)

`--stage inputs` had no plan-state precondition and overwrote all three
artifacts unconditionally. After `--stage review` records their sha256 in the
manifest, a second run would rewrite hash-bound files and `plan-close` would
report them ALTERED. That statement is true and its diagnosis is wrong: nothing
was tampered with, a producer was simply run twice. The stage now refuses while
a review is recorded against the same candidate, and says how to proceed. A
re-frozen candidate is the deliberate exception — the recorded review is void
from that moment, so producing fresh inputs is correct.

## Verified by execution, not by reading

- The producer's output is ACCEPTED by the validating review stage, end to end
  (AC11). Production and validation agree, which is the whole point of the
  follow-up.
- The subject hash is reproducible across runs over identical inputs, and
  changes when the source set changes — so it identifies what was aggregated
  rather than when it ran.
- An EPIC with no artifact is recorded `absent` in `sources[]` and moves the
  aggregation outcome to `aggregated_with_gaps`; it is never dropped.
- The stage refuses before the candidate is frozen, and refuses when no EPIC has
  merged into the plan.
- Each EPIC's artifact is read through the project root, not the caller's cwd,
  and every write is confined to the plan-final run directory.

Three defects in the first draft were found by running the REAL protocol
validator rather than by inspection: a missing `subject_hash` (exit 7), a
free-text verdict where the protocol has a closed enum (exit 8), and a
`revision` block lacking `head_is_current`/`freshness` (exit 11).

## Tests

Targeted plan-final set (AC3 review stage, AC4 identity, AC11 producer):
**44/44**. AC11 alone 6/6. No `bats_all`, no exploratory audit.

## Disposition of the earlier specialist reports

The Auditor, Curator, Simplifier and Reporter reports at `e7e3d5f` remain valid
for everything they reviewed. This document is their delta for the C4 producer,
and the Auditor's finding list gains one entry — the review-invalidation defect
above — which is fixed rather than carried.

## Explicitly NOT done here

No `inventory --apply` for P068, and no manifest commit. Per the PM decision of
2026-07-27: P068 historically did not run in `plan_branch` mode, so it must
never be stamped as such, and a standalone manifest commit would put
metadata-only changes on `main` without verifying or unblocking anything.
