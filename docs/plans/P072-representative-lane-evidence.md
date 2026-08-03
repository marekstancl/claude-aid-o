# P072 Step 18 — Representative lane evidence

**Run:** 2026-08-03, disposable clone of `feat/p072-test-audit-decision-quality`,
via `aid-test-parallel-pilot.sh --workers 4 --repeat 2`.
**Receipt:** `pilots/representative-lane.json`
(schema `aid-test-parallel-pilot-v1`).

> **Scope, stated first because it is the thing most easily overread:** this
> covers the FOUR units listed below and nothing else. It is not a statement
> about the other 63 pooled units, and it is not a statement about the pool as
> a whole. A pilot promotes the membership it ran.

---

## Membership

```
bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary
bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-runtime-report
bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-gitignore-backfill
bats:plugins/aid-orchestrator/scripts/tests/bats/test-delivery-report
```

Four units of moderate, comparable cost — enough for concurrency to have
something to overlap, small enough that a repeat of 2 stays affordable.

## What was measured

| repetition | serial | concurrent (4 workers) | cases | verdict | clone dirty | wrote outside snapshot |
|---|---|---|---|---|---|---|
| 1 | 29 197 ms | 14 105 ms | 36 | match | 0 | 0 |
| 2 | 29 200 ms | 16 256 ms | 36 | match | 0 | 0 |

Both sides exited zero from a `terminal_pass` job in both repetitions.

**Verdict: `proposed`.** Benefit **12 944 ms** (slowest serial minus slowest
concurrent), against a `pilot_noise_ms` threshold of 2 000 ms.

## What "match" means here

Not "both runs said N passed". The comparison is:

- exit code and terminal job state on both sides;
- the per-case result sequence compared **position by position** — 36 cases,
  same name and same status at every index.

Position rather than name because two cases sharing a name are two facts. An
earlier version of this pilot matched by name, found the passing one of a
duplicate pair, and reported `match` for a run whose exit code was 1.

## What the leak check covered

After every run, a content digest of the entire snapshot — including files git
ignores and edits to files that were already present — compared against the
reference the snapshot was made from, plus an inventory of the snapshot's
parent directory. Both empty in all four runs.

Each side of each repetition ran in its **own fresh copy** of the reference
root. Sharing one tree between the serial and concurrent sides would let the
serial run warm state that makes a cold race disappear exactly when it is being
looked for.

## What this does NOT establish

- **Anything about the other 63 pooled units.** Their `safe` status comes from
  P071's migrated evidence, bound to their current content by the provenance
  rule, not from this pilot.
- **That 4 workers is the right number.** It is the number this run used. A
  different worker count is a different measurement.
- **That the benefit generalises.** 12.9 s on four units of this size says
  nothing about a pool of 67; the whole-pool figure is its own measurement and
  has not been taken.
- **That nothing can leak.** The leak check covers the snapshot and its parent.
  A write to an arbitrary absolute path elsewhere on the machine would not be
  seen here — that class is caught earlier, by the Step 14 resource map, which
  reports such a write as `shared` and keeps the unit out of a candidate lane
  before any pilot runs.

## Status against the plan

- Step 18 asked for both durations, both verdicts, the membership and the
  leak-check results, recorded for one representative lane. **Met**, with the
  repeat policy satisfied rather than assumed.
- The document states explicitly that its result covers only the piloted
  membership. **Met** — first paragraph.
- Nothing here writes the catalog, changes `scheduler.mode`, or approves a
  mapping. The lane is a proposal in the decision artifact.
