# P072 — The parallel-safety authority, after this plan

> **ARCHIVED (P078, 2026-08-10).** The subsystem this page describes — the
> catalog `parallel` block, the lane runner, the scheduler and their shared
> resolver — was removed outright when the PM cancelled the test-parallelism
> line (2026-08-09). Kept as a historical record of the boundary as it stood;
> nothing here describes current behaviour.

One page, because the question "what decides whether these tests may run at the
same time?" had three answers before this plan and now has one.

Three surfaces existed. Here is what each one is now.

---

## 1. The catalog's `parallel` block — **the single computation**

`run_units[].parallel.status` (`safe | constrained | exclusive | unknown`) is
the authority. It is no longer a descriptive finding.

What changed: a non-`unknown` status must now carry `parallel.provenance` —
where it came from, when, by what method, and against which source content.
The catalog schema refuses a status without it, because this field decides
whether a test file runs concurrently with others and a claim nobody can check
is not admissible for that.

**Nobody reads `status` directly.** Every consumer goes through
`aid_test_catalog_provenance_effective_status`
(`scripts/lib/aid-test-catalog-provenance.sh`), which applies a two-tier
reversion rule:

| Situation | Effective status |
|---|---|
| Source hash matches | the recorded status stands |
| Hash differs, resource digest unchanged | stands; hash refreshed |
| Resource digest changed | `unknown` |
| A source path is gone | `unknown` |
| Recheck exceeds `decision.provenance_recheck_budget_ms` | `unknown` |

One tier would revert on any byte change, costing a full pilot for a comment
fix — and a rule that expensive stops being obeyed. Two tiers keep the cheap
case cheap without letting a real change through.

The hash covers the unit's **whole dependency closure**, not only its declared
`source_paths`. A status bound to a unit's own file survived its shared helper
acquiring a lock: the unit's bytes were unchanged, so nothing was ever
recomputed. The helper is part of what was verified, so it is part of what the
verification is bound to.

Promotion out of `unknown` needs **two kinds of evidence, never one**: a
resource map read from source (`aid-test-resource-map.sh`) and a pilot that ran
that exact membership serially and concurrently in a disposable clone
(`aid-test-parallel-pilot.sh`).

## 2. `bats-parallel-safe-allowlist.txt` — **retired**

The file remains, containing only a retirement notice, so that anyone who opens
it looking for the old list learns where the answer moved rather than finding
nothing. `aid-bats-parallel-lane.sh --allowlist` is still accepted and prints a
warning that it is not read; silently ignoring it would leave a caller
believing a list still governs the pool.

Why it went: a plain list cannot notice that a file it names has since acquired
a lock. It kept a file pooled long after the reason it was pooled had stopped
being true. The catalog can notice, because its status is bound to content.

P071 Step 3's real evidence was migrated rather than discarded
(`aid-test-catalog-migrate-p071-allowlist.sh`, `method:
migrated_p071_step3`) — so a migrated entry stays distinguishable from a freshly
piloted one — but a file changed since P071 verified it is **not** migrated. It
stays `unknown` and is named. Hashing edited content into a `safe` status would
launder a post-pilot change into fresh-looking evidence.

## 3. The scheduler overlay — **subordinate, and it may not rescue**

`test-scheduler-parallel-overlay.yaml` is an input to the shared resolver, not a
competing authority. `aid_test_catalog_effective_status_map` applies it on top
of provenance, with this precedence:

- **Never verified** — the catalog records `unknown` because nobody has
  assessed the unit. An approved overlay entry is exactly the PM decision meant
  to resolve that, and it carries its own freshness check
  (`catalog_fingerprint_at_promotion`). **It may promote.**
- **Revoked** — the unit claimed a status and its content has since moved.
  Here an overlay entry vouches for content it never saw. **It may not
  promote.**

Provenance is therefore a floor for what it has actually assessed. Treating both
cases alike in either direction is wrong: blocking both makes the overlay
useless for its purpose, and allowing both reintroduces the second authority.

---

## The three consumers

All three resolve through the same function. This is the property the plan
existed to create: before it, the lane runner used the resolver while the other
two read the raw field, so the same unit could be retired by one and dispatched
as safe by another.

| Consumer | What it does with the effective status |
|---|---|
| `aid-bats-parallel-lane.sh` | `safe` enters the `bats -j` pool; everything else runs sequentially. Pooled files are re-hashed immediately before dispatch, and a change aborts the run. |
| `aid-test-scheduler.sh` | Batches units by effective status and resolved locks. |
| `aid-select-tests.sh` | Sets `parallel_eligible` on emitted execution units. |

Two files stay out of the pool regardless of status
(`test-aid-plan-final-boundary.bats`, `test-aid-plan-release-boundary.bats`).
That exclusion is a **cost** decision, not a safety one, and it is deliberately
not expressed through this authority.

## What the audit still does not do

It recommends. It never writes `parallel.status`, never edits `execution.yaml`,
and never changes a scheduler mode. Lanes in the decision artifact are
proposals; acting on one is a separate, explicit step.

## Where the enforcement is recorded

`defaults/enforcement-registry.yaml`, mirrored in
`docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml`:
`test_catalog_parallel_provenance_binding`,
`test_lane_single_parallel_authority`,
`test_audit_resource_map_shared_evidence`,
`test_audit_pilot_evidence_bound`,
`test_audit_lane_membership_exact`.

Proven end to end from a clean clone by
`scripts/tests/test-integration-parallel-authority-e2e.sh`: committed catalog →
lane partition → shared-helper drift → the unit drops out of every consumer →
restored helper → eligibility returns.
