# P069 scheduler — re-grounded against P072's final schema

P072 changes the meaning of a field P069's scheduler reads. This page records
what the scheduler actually reads, whether a catalog carrying the new
`provenance` object still loads for it, and one place where I did **not** do
what P072's own plan asked, with the reason.

Verdict up front: **backward compatible, with one behavioural change and one
deliberate deviation from the plan.**

---

## 1. What the scheduler reads from the catalog

Every catalog access in `aid-test-scheduler.sh`, at the revision this was
checked against:

| Read | Where | After P072 |
|---|---|---|
| `.run_units[]` keyed by `run_unit_id` | `cmd_dispatch`, the `$by_id` map | unchanged |
| `.parallel.status` | was read raw at line ~226 | **changed** — now resolved through `aid_test_catalog_effective_status_map` |
| `.parallel.exclusive_resources[]` | resolved-locks construction | unchanged |
| `.runtime.fingerprint` | overlay staleness check | unchanged |
| `.parallel.provenance` | not read directly | new field, read only by the resolver |

The scheduler no longer reads `parallel.status` directly. It receives an
`id -> effective_status` map computed in one batch pass and looks up each unit.
The jq program's shape is otherwise as it was.

## 2. Does a catalog with `provenance` still load?

Yes. `provenance` is an additive object on `parallel`, and the catalog schema
requires it **conditionally** — only for a non-`unknown` status. A catalog
written before P072 carries no `provenance` at all, validates, loads, and
resolves to a uniform effective `unknown`.

That conditional was not free. Making `provenance` unconditionally required was
tried first and broke seven suites, including every catalog the Wave-0 scanner
generates, because the scanner writes `status: unknown` with no provenance
block. A catalog that predates the field has to keep loading — as `unknown`,
which is the fail-closed value, not as trusted.

Commands run for this check:

```
bats test-aid-test-scheduler.bats                    # 18/18
bats test-aid-test-catalog-provenance.bats           # 20/20
bash test-integration-parallel-authority-e2e.sh      # 10/10
```

## 3. The behavioural change: an overlay can no longer rescue a revoked unit

P069: an approved overlay entry whose `catalog_fingerprint_at_promotion`
matched the current catalog fingerprint promoted the unit, full stop.

P072: provenance is a floor for everything it has **actually assessed**. So:

| Situation | Overlay may promote? |
|---|---|
| Catalog says `unknown` because nobody assessed the unit | **Yes** — unchanged from P069 |
| Catalog said `safe`, but the unit's resources have since changed | **No** — new |

The second row is the change. An overlay entry in that situation is vouching
for content it never saw: its fingerprint check is against the catalog, not
against the sources. Provenance checks the sources. Letting the overlay win
would keep a second authority over the one question this work exists to give a
single answer to.

Asserted by `test-aid-test-scheduler.bats`, in both directions — a unit
promoted off `unknown` still batches; a unit whose source gained a `flock` stays
isolated however the overlay is approved.

## 4. Where I did not follow the plan, and why

P072 Step 25 asks for something stricter: *"the overlay may only narrow the
effective status, never widen it."*

I implemented that, and then reverted it. The reason is in the overlay's own
schema:

```json
"promoted_status": {
  "enum": ["safe", "constrained"],
  "description": "The scheduler NEVER reads this array to demote a unit to
                  unknown/exclusive — only to promote off unknown."
}
```

The mechanism admits only two values, both more permissive than `unknown`; its
fields are named `promoted_status` and `promoted_at`; and its stated contract is
that it is never used to demote. A narrow-only overlay is a mechanism with
nothing left to do — the rule would not have restricted the overlay, it would
have deleted it, while leaving the schema, the approval script and the field
names describing something that no longer happens.

What Step 25 was protecting is that the overlay must not contradict a content
check. The never-verified/revoked split achieves exactly that and keeps the
overlay's real use: **provenance wins wherever it has an opinion; the overlay
resolves only the case where it has none.**

This is recorded rather than quietly done. If the stricter rule is still wanted,
it is a change to the overlay schema and its approval flow — a separate
amendment, not a line in the resolver.

## 4a. PM decision on the deviation — 2026-08-04

The section above described a deviation but left it hanging: the plan still said
one thing and the code did another, which is not a resolved deviation, it is an
unrecorded one. The PM review of 2026-08-04 called that out and directed that
the decision be recorded and the plan amended to whichever contract was actually
chosen.

**Decision: the deviation is ACCEPTED. The narrow-only rule is withdrawn.**

The binding contract for the scheduler overlay is now:

> Provenance wins wherever it has an opinion. The overlay resolves only the case
> where provenance has none.

| Provenance state | Overlay may promote? | Why |
|---|---|---|
| Verified and matching | n/a — already `safe` | nothing to resolve |
| REVOKED (source hash or resource digest mismatch) | **No** | provenance has an opinion, and it is `unknown`; an overlay promoting here would contradict a content check |
| Never verified | **Yes**, if the entry is approved | provenance has no opinion; this is the overlay's whole remaining purpose |

**What changed as a result:** the plan text at Slice 5 step 25 and Slice 6
step 4 (`.aid-o/plans/P072-test-audit-decision-quality.md`) carries an `AMENDED
2026-08-04` block stating this contract in place of "only narrow, never widen".
The acceptance criterion for that step is correspondingly the revoked-vs-
never-verified split, not overlay monotonicity.

**What was NOT decided:** whether the overlay should be able to demote at all.
That remains a separate P069 amendment touching the overlay schema
(`promoted_status` currently admits only `safe` and `constrained`), the approval
script and the field names. It is deferred, not rejected.

## 5. What this check did NOT prove

- **Scheduled concurrency on this repository.** The 3-stage rollout gate
  requires qualifying divergence evidence that this repository does not have,
  and that campaign remains deliberately deferred. The scheduler therefore runs
  at `sequential` here. That is an honest partial result, not a bypassed gate —
  advancing the stage without the evidence was not done.
- **The generated `execution.yaml` versus this repository's own.** The
  self-host configuration is gitignored and differs from what
  `compose_execution_yaml` generates. The consumption test below runs against a
  generated one, and says so.

## 6. Where the assertions live

- `scripts/tests/bats/test-aid-test-scheduler.bats` — effective-status
  consumption, both overlay directions
- `scripts/tests/test-integration-scheduler-catalog-consumption.sh` — the
  scheduler's selection matches the resolver's answer for the same catalog
- `scripts/tests/test-integration-parallel-authority-e2e.sh` — all three
  consumers agree, from a clean clone
