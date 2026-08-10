---
id: P072
type: regular
status: done
created: 2026-08-02
author: PM + AI
lifecycle_strict: true
depends_on_plans: [P066, P069, P071]
risk: high
---

> **Closure (2026-08-08):** Implemented outside the AID pipeline on feat/p072-* (released across v2.69.x-v2.79.x incl. Step 28 whole-path proof); absorbed P070. Archived during the 2026-08-08 bookkeeping cleanup.

# Plan: Test-Audit Decision Quality, Diagnostic Depth and Whole-Path Proof

> **PLAN STATUS 2026-08-04 (round 2): LIVE-ACCEPTANCE PENDING — not complete.**
> Round 2: a real `--mode full` audit ran and could not finish. It found three
> blockers, all defects of this plan, all fixed in v2.70.1 with tests — see
> `docs/plans/P072-real-audit-record.md`. v2.70.0 and v2.70.1 ARE released,
> because installing the plugin is a precondition of the acceptance runs; a
> release is not a claim of completion.
> Every step is implemented and its automated proof is green, but Step 24's real
> full audit and the consumer E2E from the installed release candidate have not
> been run. Until both are green this plan is not complete and `v2.70.0` must not
> be tagged or released. Recorded in `docs/plans/P072-real-audit-record.md`.


## Stakeholder Brief

AID can already inventory a project's tests, but it cannot yet decide anything about them. Its last
real run against this repository produced 83 test units of which 83 were labelled "parallel safety
unknown", 83 carried no statement of what behavior they protect, and 83 were marked low confidence.
A project owner reading that output learns only that the auditor was uncertain.

This plan turns that inventory into a decision. Every discovered test gets exactly one verdict —
keep, fix, merge, split, rewrite cheaper, remove, quarantine, keep serial, parallelize, or measure —
and each verdict must name the behavior the test protects and the evidence behind the decision. An
audit that cannot decide must say `incomplete` and is then mechanically blocked from being turned
into a remediation plan, which today it is not.

It also closes a contradiction that shipped three days ago. Release v2.68.0 added a real parallel
test lane driven by a hand-maintained text file listing 72 approved-safe files, while the
schema-bound catalog continues to say "unknown" for all 83 units. Two approval surfaces disagree by
construction, and the text file silently keeps trusting a file after its contents change. This plan
merges them into one authority with provenance, preserving the real evidence v2.68.0 produced
rather than re-earning or discarding it.

Delivered: a strict decision artifact, a six-part plain-language recommendation, a cost root-cause
profiler, a source-aware resource map, a bounded parallel pilot, discovery of the 36 shell test
suites and 7 mis-classified Bats suites currently invisible to the auditor, and one end-to-end proof that an approved audit result
actually drives scheduled execution through the real gate runner.

Key risks: the plan touches the gate execution path and the test catalog schema, so a mistake can
break how this project runs its own tests; and the final wall-clock proof requires multi-hour real
measurement that cannot be substituted with fixtures. Both are addressed by fail-closed defaults
(anything unproven stays sequential) and by an explicit rule that the campaign is reported honestly
or reported as not done.

## Plan Type

`regular` — new distributable plugin capability plus a schema change to an already-approved,
git-tracked consumer artifact (`test-catalog.yaml`) and a behavior change to a gate-adjacent
execution script (`aid-bats-parallel-lane.sh`).

`risk: high` is declared deliberately and matches `review-checkpoint-contracts.md`'s high-risk
pattern set on two counts: the plan modifies schema/validation surfaces
(`test-catalog.schema.json`, a new decision schema consumed by a release-blocking bridge), and it
modifies how a project's real gate execution selects and dispatches tests
(`aid-bats-parallel-lane.sh`, and the interface P069's `aid-test-scheduler.sh` reads). CP1-deep and
the C0 cross-provider review loop therefore both apply.

## Context

This plan is the re-grounded, executable form of the design document
`docs/plans/2026-08-02-IMP-TEST-AUDIT-DECISION-QUALITY-AND-DIAGNOSTICS.md`, whose specification is
`docs/plans/2026-08-02-SPEC-P072-test-audit-decision-quality.md`. The design document was written against
`main` at v2.66.2 and deferred its own implementation until "P069 is merged or frozen". P069 merged
and released as v2.67.0 on 2026-08-02; P071 released as v2.68.0 the same day. The deferral
condition has been met, so the design was re-grounded against what actually shipped before this
plan was written.

**Measured baseline (working tree at `db1aad9`, 2026-08-02).** Every figure below was measured, not
copied from the design document, and several correct it:

| Fact | Measured | Command | Design doc claimed |
|---|---|---|---|
| `.bats` files in tree | 93 | `find …/tests -name '*.bats' \| wc -l` | 76 |
| `test-*.sh` files in tree | 43 | `find …/tests -name 'test-*.sh' \| wc -l` | 39 |
| — of which carry Bats syntax (`@test`) | 7 | `grep -lE '^\s*@test ' …/tests/test-*.sh` | not stated |
| — genuine shell suites | 36 | 43 minus 7 | "39" |
| Real Bats run units (93 `.bats` + 7 `.sh`) | 100 | as above | not stated |
| Total test files | 136 | 93 + 43 | 115 |
| Named `@test` cases in `.bats` | 2108 | `grep -rhE '^@test ' --include='*.bats' \| wc -l` | 1,936 |
| Named `@test` cases in bats-syntax `.sh` | 84 | `grep -hE '^@test ' …/test-*.sh \| wc -l` | not stated |
| Approved catalog `run_units` | 83 | `yq -r '.run_units\|length'` | 83 |
| — `runner: bats` | 74 | `yq -r '.run_units[].runner' \| sort \| uniq -c` | not stated |
| — `runner: declared-command` | 8 | as above | not stated |
| — `runner: package-script` | 1 | as above | not stated |
| `parallel.status: unknown` | 83 / 83 | `yq -r '.run_units[].parallel.status'` | "every one" |
| `behavior_claims: []` (empty) | 83 / 83 | `yq` select on empty array | not stated |
| `confidence: low` | 83 / 83 | `yq -r '.run_units[].confidence'` | not stated |
| Run units with >1 `source_paths` | 0 / 83 | `yq -r '.run_units[].source_paths\|length'` | not stated |
| Bats run units covered by the catalog | 74 of 100 | 93+7 in tree, 74 in catalog | not stated |
| Shell suites covered by the catalog | 0 of 36 | no `sh:` adapter exists | "39 invisible" |
| Real gates in `execution.yaml` | 9 | `yq -r '.gates\|keys'` | not stated |
| Gate run units in the catalog | 8 — `gate:bats_boundary` absent | `yq` on `runner=="declared-command"` | not stated |
| Catalog `generated_at` | 2026-07-30T13:41:15Z (pre-P071) | `yq -r '.generated_at'` | — |

The approved catalog therefore covers 74 of 136 real test files, carries zero behavior claims, knows
nothing about parallel safety for any unit, and has drifted behind the tree on two axes in three
days: 26 uncovered Bats run units, and one entire gate (`gate:bats_boundary`, added by P071 on
2026-08-02) that does not exist in it at all.

**Taxonomy correction that the design document and P071's own records both got wrong.** Seven files
matching `test-*.sh` are Bats suites carrying a `#!/usr/bin/env bats` shebang, and `run-all-tests.sh`
line 140 already dispatches them with `bats`, not `bash`, by sniffing that shebang. They are
therefore Bats run units that the `*.bats` glob in `aid-test-adapter-bats.sh` line 60 misses, not
shell suites. Any adapter that classifies by filename alone will mis-run them; any count that calls
them shell suites is wrong. The seven are `test-token-count.sh`, `test-stage-log.sh`, `test-fsm.sh`,
`test-integration-phase1.sh`, `test-release.sh`, `test-scope-check.sh` and `test-run-gates.sh`.

**The central finding that the design document could not know.** P071 shipped
`aid-bats-parallel-lane.sh` plus `defaults/config/bats-parallel-safe-allowlist.txt`, a flat text
file listing 72 approved-safe bats files. That script's own header states that the catalog's
`parallel.status` field "is NEVER consulted as a pool-eligibility signal". Meanwhile the
allowlist's provenance header records that the 72-file set was verified twice for real: P066's
audit `audit-20260802-070629` read all 83 bats files directly and confirmed the shared
`setup_test_evidence_dir`/`mktemp`-per-test isolation helper, and P071 Step 3 ran that exact set via
`bats -j 4` twice — 1382 `@test` cases, 0 failures, `git status --short` empty both times.

So the two kinds of evidence a durable promotion requires were already produced, and then written
to a file with no schema, no content binding, no expiry and no re-validation, while the durable
protocol field still reads `unknown`.

**There are three authorities, not two.** P069 shipped a third: `aid-test-scheduler.sh` lines
204-228 read `.aid-o/config/test-scheduler-parallel-overlay.yaml` and, when that overlay's `status`
is `approved` and its entry's `catalog_fingerprint_at_promotion` equals the run unit's
`runtime.fingerprint`, use the overlay's `promoted_status` **instead of** the catalog's
`parallel.status`. So the current precedence is: scheduler overlay outranks catalog, and the
parallel lane ignores both in favour of a text file. Three surfaces, one of which
(`parallel.status`) no execution path reads at all — precisely the failure mode
`docs/plans/AID-v3-principles.md` §1 names, reproduced three times over.

The overlay is closer to correct than the allowlist: it is schema-versioned, has an approval status,
and binds to `runtime.fingerprint`, which is a real staleness guard. This plan therefore does not
discard it — it makes the catalog's provenance-bound effective status the single computation and
subordinates the overlay to it, rather than adding a fourth surface alongside the three.

**P070 is absorbed, not depended upon.** `P070-test-portfolio-audit-selfhost-remediation.md` is
still `status: draft` and never shipped: `scripts/lib/` contains exactly four adapters (`bats`,
`contract`, `declared-command`, `package-script`) and no `sh:` adapter, although
`test-catalog.schema.json` line 135 already reserves the `sh:<relative-path-without-extension>`
naming convention. Its shell suites — 36 genuine ones, once the 7 Bats-syntax files are
routed correctly — cannot be reconciled without that adapter, so this plan
absorbs both P070 items rather than depending on an unowned draft.

## Goal

Make `/aid-audit-tests --mode full` produce a complete, evidence-graded decision about every
discovered test unit — or honestly refuse to call itself complete — and prove once, end to end, that
an approved decision actually drives real scheduled gate execution.

## Scope

**In scope:**

- A strict, versioned consolidated decision artifact (`aid-test-audit-decision-v1`) with
  `audit_status: complete | incomplete`, and a fail-closed refusal to hand an `incomplete` audit to
  `/aid-plan write`.
- A mandatory terminal disposition per discovered `run_unit_id`, with deterministic reconciliation
  of inventory / shard-assignment / disposition counts.
- Disposition content requirements: behavior claim, failure signal, uniqueness or overlap, layer
  fitness, falsification evidence for every coverage-reducing proposal.
- A `sh:` shell-suite discovery adapter bringing the 36 genuine standalone suites into `run_units`,
  plus shebang-correct routing of the 7 Bats-syntax `test-*.sh` files to the Bats adapter.
- The disposable-clone `.aid-o/config/` precondition fix (P070 item 1).
- The aggregate result-grammar fix so `test-semantic-review.sh` stops being counted as `0/0`.
- A bounded cost root-cause profiler with streamed evidence and honest partial receipts.
- A source-aware resource-map builder replacing grep-only parallel-safety reasoning.
- A bounded disposable-clone parallel-pilot runner producing proposals, never configuration.
- Reconciliation of the three parallel-safety surfaces (catalog field, text allowlist, P069
  scheduler overlay) into one provenance-bound catalog computation, preserving P071's real 72-file
  evidence and leaving the overlay only the power to narrow.
- A six-part decision-first chat renderer replacing the current five-part findings handoff.
- Enforcement-registry rows for every new detection capability introduced here.
- One real full audit, its sanctioned approval, and one fresh-project end-to-end proof that P069's
  scheduler consumes it through `aid-run-gates.sh`, with a double-execution ledger and measured
  before/after wall-clock.

**Out of scope:**

- Any automatic remediation. No test is edited, deleted, split, merged, quarantined or parallelised
  by this plan's code paths.
- Any change to `dispatch.max_parallel` or to code-writing agent concurrency.
- Any change to P069's shipped 3-stage rollout gate semantics (`sequential` → `observe_parallel` →
  `parallel`) beyond reading the reconciled catalog field.
- The broader `/aid-help`/`/aid-init`/`/aid-setup` UX work, which remains
  `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md`.
- Lifting the `bats_boundary` quarantine for `test-aid-plan-final-boundary.bats` and
  `test-aid-plan-release-boundary.bats`. This plan diagnoses their cost; the lift decision remains a
  separate PM quarantine-decision record.
- Retro-fitting decision-quality output onto `--mode static` or `--mode measure`. The mandatory
  terminal disposition is a `full`-mode obligation only.

## Approach

**Chosen approach: reconcile onto the catalog, then build the evidence producers that fill it.**

The catalog is already the schema-bound, git-tracked, version-stamped artifact with an explicit
`proposed` → `approved` lifecycle and a separate mapping-confirmation gate. `aid-bats-parallel-lane.sh`
already loads it, already refuses to run when its top-level `status` is not `approved`, and already
derives its complete file list from it — it declines to read only one field, `parallel.status`,
because that field is uniformly `unknown`. Making the lane read a provenance-bound `parallel` block
from the same file it already loads is therefore a small change with a large coherence gain: one
authority, one approval lifecycle, and a real consumer for a field that is currently decoration.

Fail-closed behavior is preserved exactly. The lane keeps its three-bucket partition (parallel pool
/ sequential / boundary) and its rule that anything not explicitly proven safe runs sequentially. The
change is the source of the proof, not the default.

The evidence producers — resource map, profiler, pilot — are then built to populate that field with
citations, so a promotion is reproducible rather than remembered.

**Alternatives considered and rejected:**

*Keep the allowlist as the operative file, generated from the catalog.* This also yields one
authority and requires no change to the lane's file reading. Rejected because it adds a derived
artifact that must be regenerated and kept in sync, and because a generated file that looks
hand-editable invites hand-editing — the same drift risk in a new place.

*Leave all three surfaces and document precedence.* Cheapest, and rejected outright: it
institutionalises a contradiction that a consumer project would inherit, and leaves
`parallel.status` a detector with no consumer, violating `AID-v3-principles.md` §1.

*Make the scheduler overlay the single authority instead of the catalog.* The overlay is already
schema-versioned, approval-gated and fingerprint-bound, so this is a real candidate. Rejected
because the overlay is scheduler-private: the parallel lane, the audit and the catalog-approval
lifecycle would all have to learn a second config file, and the overlay carries no behavior claims,
no evidence references and no per-unit inventory — it is a promotion list, not a portfolio record.
The chosen direction keeps the overlay's fingerprint-binding idea and moves it into the catalog as
`parallel.provenance.source_sha256`.

*Re-run the parallel pilot from zero and discard P071's evidence.* Rejected as waste. P071's runs
were real (1382 cases, twice, clean `git status`) and are cited with their audit id and step; this
plan migrates them with explicit provenance naming P071 Step 3 as the source, which is neither
discarding them nor laundering them into a schema field with invented origin.

## Architecture

**Existing components this plan extends.** `/aid-audit-tests` runs a fixed chain: the CLI parser
(`aid-audit-tests-cli-parse.sh`) resolves a canonical `project_root`; the Wave-0 scanner
(`aid-test-inventory.sh`) builds `inventory.json` and `test-catalog.proposed.yaml` via four
discovery adapters in `scripts/lib/aid-test-adapter-*.sh` behind the shared interface in
`aid-test-adapter-contract.sh`; `aid-test-audit-dispatch.sh` emits a bounded manifest of read-only
shard/specialist waves run through the `test-portfolio-analyst` agent card; and
`aid-audit-tests-finalize.sh` is the single mandatory closing entrypoint that chains
`aid-test-audit-consolidate.sh` → `lib/aid-test-audit-chat-summary.sh` →
`lib/aid-test-audit-write-plan-bridge.sh`.

**Where the new pieces attach.**

1. *Discovery layer.* A fifth adapter, `lib/aid-test-adapter-shell-suite.sh`, implements the same
   `aid-test-adapter-contract.sh` interface as the existing four and emits `sh:`-prefixed
   `run_unit_id`s. `aid-test-inventory.sh` sources it alongside the others and its existing
   collision check extends to the new namespace.

2. *Evidence layer (new, runner-owned).* Three new scripts sit behind the existing
   `aid-job.sh` receipt boundary and the `aid_test_audit_check_allowed` command allowlist, and each
   refuses to operate against a live checkout: `aid-test-audit-profile.sh` (cost root cause),
   `aid-test-resource-map.sh` (static source-aware resource inspection, no execution), and
   `aid-test-parallel-pilot.sh` (bounded serial-vs-parallel comparison in a disposable clone).

3. *Decision layer (new).* `lib/aid-test-audit-decision.sh` writes and reads a single consolidated
   artifact validated against `defaults/schemas/test-audit-decision.schema.json`.
   `aid-test-audit-consolidate.sh` produces it; `aid-test-audit-chat-summary.sh` renders it;
   `aid-test-audit-write-plan-bridge.sh` refuses on `audit_status: incomplete`.

4. *Consumption layer (reconciliation).* `test-catalog.schema.json` gains a provenance sub-block
   under each run unit's existing `parallel` object. `aid-bats-parallel-lane.sh` switches its
   pool-eligibility source from the text allowlist to that field, and the allowlist file is retired.

**Data flow, end to end.** `/aid-audit-tests --mode full` → parser → inventory (5 adapters, 136
files) → dispatch manifest with every `run_unit_id` assigned → shards emit one terminal disposition
each → resource map + profiler + pilot produce cited evidence → consolidator reconciles counts and
writes the decision artifact → renderer emits six-part chat text → PM approves catalog/mapping
through the existing sanctioned scripts → `aid-bats-parallel-lane.sh` and P069's
`aid-test-scheduler.sh` read the approved provenance-bound field → `aid-run-gates.sh` dispatches →
per-unit receipts → execution ledger proves no unit ran twice.

**Authority boundary, unchanged by this plan.** No script in the evidence or decision layer writes
`.aid-o/config/test-catalog.yaml`, `execution.yaml`, `scheduler.mode`, or any quarantine block.
Approval remains `aid-test-catalog-approve.sh` plus the separate
`aid-test-catalog-confirm-mapping.sh` gate.

## Data Model

### Consolidated decision artifact (`aid-test-audit-decision-v1`)

Written to `.aid-o/work/test-audits/<audit-id>/decision.json`, validated by
`defaults/schemas/test-audit-decision.schema.json` with `additionalProperties: false` at every level.

| Field | Type | Invariant |
|---|---|---|
| `schema_version` | string | Exactly `aid-test-audit-decision-v1` |
| `audit_status` | enum | `complete` or `incomplete` |
| `current_runtime.kind` | enum | `measured`, `lower_bound`, `unknown` |
| `current_runtime.duration_ms` | integer or null | Null exactly when `kind` is `unknown` |
| `current_runtime.scope` | array of `run_unit_id` | Non-empty; every id resolves in the inventory |
| `actions[].action` | enum | `fix`, `merge`, `remove`, `split`, `parallelize`, `keep_serial`, `measure` |
| `actions[].targets` | array of stable ids | Non-empty; each is a `run_unit_id` or a declared gate id |
| `actions[].priority` | enum | `critical`, `high`, `medium`, `low` |
| `actions[].reason` | string | 1–500 characters, no absolute paths |
| `actions[].evidence_refs` | array of strings | Non-empty; each resolves to a file under the audit dir |
| `actions[].impact.kind` | enum | `measured`, `estimated`, `unknown` |
| `actions[].impact.before_ms` / `after_ms` | integer or null | Both null when `kind` is `unknown`; both non-null when `measured` |
| `actions[].impact.assumptions` | array of strings | Non-empty exactly when `kind` is `estimated` |
| `parallelization.lanes[].lane_id` | string | Unique within the artifact |
| `parallelization.lanes[].disposition` | enum | `proposed_parallel`, `keep_serial`, `blocked_pending_fix`, `context_required` |
| `parallelization.lanes[].run_unit_ids` | array | Non-empty; disjoint across lanes |
| `parallelization.lanes[].resource_basis` | array of controlled vocabulary | From the resource-namespace vocabulary below |
| `parallelization.smallest_safe_pilot` | object | Structured command reference plus pass criteria |
| `unresolved[].run_unit_id` | string | Resolves in the inventory |
| `unresolved[].missing_proof` | enum | Controlled reason vocabulary, not free text |
| `unresolved[].next_measurement` | string | Names a bounded operation this plugin can actually run |
| `portfolio_coverage.inventory_count` | integer | Equals discovered unit count |
| `portfolio_coverage.assigned_count` | integer | Equals dispatch-manifest assignment count |
| `portfolio_coverage.disposition_count` | integer | Equals terminal disposition record count |
| `portfolio_coverage.missing_run_unit_ids` | array | Empty is required for `audit_status: complete` |
| `portfolio_coverage.duplicate_run_unit_ids` | array | Empty is required for `audit_status: complete` |
| `portfolio_change.*` | object | Current/proposed counts, keep/rewrite/merge/remove id sets, runtime before/after, `impact_kind` |

**Rejected by schema:** unknown fields at any level, absolute paths in any string field, a NAMED and
enumerated set of credential shapes, and any shell snippet longer than 200 characters. Human prose
lives in the rendered report and evidence files, never in a durable protocol field.

The credential list is deliberately narrow and is stated in full rather than as a promise: AWS
access key ids, GitHub and Slack tokens, a PEM private-key header, and an inline `key=value`
credential assignment whose value is at least 12 characters. It is NOT general secret detection —
that is a guarantee no regex can keep, and claiming it in the one artifact this plan is trying to
make checkable would be exactly the kind of overclaim the plan exists to remove. The threshold is
set so that ordinary prose ("the api_key is unset", "token handling is covered elsewhere") is not
rejected, because a reason field that fires on the word "token" pushes authors into vaguer reasons.
Anything broader belongs in the evidence files, which are not public-safe protocol fields.

### Terminal disposition record

One per discovered `run_unit_id`, emitted by a shard, stored in that shard's wave artifact and
reconciled by the consolidator.

| Field | Type | Invariant |
|---|---|---|
| `run_unit_id` | string | Exactly one record per discovered id |
| `disposition` | enum | `keep`, `fix`, `rewrite_unit`, `merge`, `split`, `remove`, `quarantine`, `keep_serial`, `parallelize`, `measure` |
| `behavior_claim` | string | 1–300 chars; names the invariant or historical regression protected |
| `failure_signal` | string | 1–300 chars; the concrete signal the test emits when the behavior breaks |
| `falsification` | object | `method` (`mutation`, `revert`, `input_probe`, `unproved`) plus `evidence_ref` when not `unproved` |
| `uniqueness` | enum | `unique`, `overlaps`, `unproved`; `overlaps` requires non-empty `overlaps_with[]` |
| `layer` | enum | `unit`, `contract`, `integration`, `e2e` |
| `cheaper_layer_possible` | enum | `yes`, `no`, `unproved`; `yes` requires naming the target layer |
| `cost.kind` | enum | `measured`, `lower_bound`, `unknown` |
| `cost.duration_ms` | integer or null | Null exactly when `kind` is `unknown` |
| `confidence` | enum | `high`, `medium`, `low` |

**Coverage-reducing rule:** a `remove`, `merge` or `rewrite_unit` disposition requires
`falsification.method` other than `unproved` and a resolvable `evidence_ref`. A `keep` disposition
requires either `uniqueness: unique` with evidence, or an explicit `uniqueness: unproved`, which the
renderer then surfaces under "What is not proved yet".

### Catalog `parallel` provenance block

Added to each run unit's existing `parallel` object in `test-catalog.schema.json`.

| Field | Type | Invariant |
|---|---|---|
| `parallel.status` | enum (unchanged) | `safe`, `constrained`, `exclusive`, `unknown` |
| `parallel.provenance.source_sha256` | string or null | SHA-256 of the run unit's source file content at verification time |
| `parallel.provenance.evidence_ref` | string or null | Audit id plus artifact path, or a named prior plan step |
| `parallel.provenance.verified_at` | RFC3339 string or null | When the two-part evidence was completed |
| `parallel.provenance.method` | enum or null | `resource_map_plus_pilot`, `migrated_p071_step3`, `manual_pm` |
| `parallel.provenance.resource_digest` | string or null | SHA-256 over the unit's sorted resource-kind/namespace pairs from Step 14, used by the two-tier reversion below |

**Reversion invariant, two-tier.** Any status other than `unknown` requires all four provenance
fields to be non-null. A reader that recomputes `source_sha256` and finds a mismatch does NOT
immediately revert the unit; it re-runs the cheap, static resource map (Step 14) against the new
content and compares the resulting resource set to `provenance.resource_digest`:

- resource set unchanged → the hash is refreshed in place, `verified_at` is updated, and the status
  is retained. The expensive pilot is not re-run, because nothing that could affect cross-process
  safety changed.
- resource set changed, or the resource map cannot classify the new content → the unit reverts to
  `unknown` and needs a fresh pilot before it can be pooled again.

**Why two tiers rather than a blanket revert.** Measured on this repository: of the 72 currently
pooled bats files, 30 changed in the last 7 days, 58 in the last 30 days, and all 72 within 90 days
(`git log --since=… -- <file>` per file). A blanket content-hash revert would therefore empty the
parallel pool within roughly a month of ordinary development and silently return the suite to fully
sequential execution — the exact outcome this plan exists to prevent, arrived at by a mechanism
meant to protect it. The resource digest is what makes the guard track cross-process safety rather
than tracking edits.

### Resource-namespace vocabulary

Controlled strings used by `resource_basis[]` and by the resource map. Resource kinds: `temp_path`,
`fixed_path`, `working_dir`, `git_repo`, `git_worktree`, `aid_state`, `lock`, `port`, `socket`,
`process_group`, `cache`, `external_service`. Namespaces: `per-test`, `per-run`, `shared`,
`unknown`. A resource is recorded as the pair, so `fixed_path/shared` and `temp_path/per-test` are
distinct facts rather than one blended judgement.

## Testing Strategy

**Test layers.** Each new script gets a Bats suite under
`plugins/aid-orchestrator/scripts/tests/bats/` covering its own contract, plus integration suites
under `plugins/aid-orchestrator/scripts/tests/` for cross-script chains. Every acceptance clause in
this plan maps to at least one named test.

**Fail-closed fixtures are the core of this plan's testing.** For each "cannot" in the requirements
there is a fixture that attempts it and asserts a non-zero exit with a distinct code: a
portfolio-wide `unknown` handed to the write-plan bridge; a shard emitting zero records for an
assigned unit; a shard dropping one assigned unit; a shard duplicating a unit; a `remove`
disposition with `falsification.method: unproved`; an `estimated` impact with an empty
`assumptions[]`; a `measured` impact with a null `before_ms`; a catalog entry with
`parallel.status: safe` and a null provenance field; and a pooled file whose `source_sha256` no
longer matches.

**Real-execution tests are separated from fixtures and never conflated.** The pilot runner, the
profiler and the Slice-6 campaign execute real commands. Their tests assert on receipt structure and
on comparison logic using recorded receipts; the *actual* multi-hour campaign is Step 27's own
deliverable and is reported as measured or reported as not done, never inferred from a fixture pass.

**Regression protection for existing behavior.** The existing `static` / `measure` / `full` modes,
resume state machine, command allowlist and job-receipt guarantees keep their current suites green;
`test-aid-test-audit-*.bats` and `test-integration-e2e-audit-pipeline.sh` are extended, not replaced.

**Aggregate-run policy.** Per this plan's constraints, no full aggregate suite run follows every
step. Targeted suites run per step; one aggregate candidate run happens once, on the frozen final
revision, under the then-current quarantine policy.

## Constraints

1. The audit remains on-demand. It is never dispatched after an EPIC, a plan, a release or a
   scheduler invocation, and it carries no FSM/gate/CI wiring — the existing
   `test_audit_never_auto_invoked` enforcement row stays satisfied.
2. No test file is edited, deleted, split, merged, quarantined or parallelised by any code path this
   plan adds.
3. Diagnostic runs and pilots refuse to share a live checkout with an active gate run; a disposable
   root is required, not preferred.
4. `dispatch.max_parallel` is untouched. Audit shard concurrency (`--max-agents`) and test worker
   count remain separate, explicitly named settings.
5. No full aggregate run after every step. One aggregate candidate run, on a frozen final revision.
6. P069's scheduler contract is either unchanged or explicitly re-grounded and amended in Step 25;
   it is never changed implicitly by a schema addition.
7. Plugin maintenance obligations from `CLAUDE.md` apply: both CHANGELOGs identical, all 8 version
   locations in sync, an enforcement-registry row per new detection capability, `Last Updated`
   refreshed on revised skills and commands, and `aid-lint-skill.sh` clean on every new or
   substantially revised skill and command file.
8. This plan runs in `plan_branch` mode (`lifecycle_strict: true`); EPICs merge into the plan branch
   and only the plan releases, once, at its own boundary.
9. Files written under `docs/plans/` acquire a `YYYY-MM-DD-` filename prefix at write time (every
   tracked file there carries one). A Files entry naming the undated form therefore resolves to the
   dated file on disk; when a step reports its deliverable, it must cite the real dated path rather
   than the name the plan used, or the reference points at nothing. Step 1's own deliverable is
   `docs/plans/2026-08-03-P072-consumer-inventory.md`.

## Resources Verification

| Resource | Status | Evidence |
|---|---|---|
| `plugins/aid-orchestrator/scripts/aid-test-inventory.sh` | exists | 216 lines, sources 4 adapters |
| `plugins/aid-orchestrator/scripts/lib/aid-test-adapter-contract.sh` | exists | shared adapter interface |
| `plugins/aid-orchestrator/scripts/aid-test-audit-consolidate.sh` | exists | 231 lines |
| `plugins/aid-orchestrator/scripts/aid-audit-tests-finalize.sh` | exists | 96 lines, sources chat-summary + write-plan-bridge |
| `plugins/aid-orchestrator/scripts/lib/aid-test-audit-chat-summary.sh` | exists | current 5-part renderer |
| `plugins/aid-orchestrator/scripts/lib/aid-test-audit-write-plan-bridge.sh` | exists | current bridge validator |
| `plugins/aid-orchestrator/scripts/aid-bats-parallel-lane.sh` | exists | 328 lines, P071 |
| `plugins/aid-orchestrator/defaults/config/bats-parallel-safe-allowlist.txt` | exists | 72 non-comment entries |
| `plugins/aid-orchestrator/defaults/schemas/test-catalog.schema.json` | exists | reserves `sh:` at line 135 |
| `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` | exists | distributed registry |
| `docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml` | exists | internal registry |
| `docs/extending-aid.md` | exists | contributor reference |
| `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` | exists | result grammar at line 213 |
| `plugins/aid-orchestrator/scripts/tests/test-semantic-review.sh` | exists | emits `=== Results:` at line 220 |
| `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` | exists | asserts all 8 version locations agree and both CHANGELOGs mention the version |
| `plugins/aid-orchestrator/scripts/tests/bats/test-helpers.bash` | exists | `setup_test_evidence_dir` at line 11 — the per-test isolation helper |
| `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` | exists | `compose_execution_yaml` at line 344 |
| `plugins/aid-orchestrator/scripts/lib/aid-test-audit-command-allowlist.sh` | exists | `aid_test_audit_check_allowed` at line 100 |
| `plugins/aid-orchestrator/scripts/tests/bats/test-aid-audit-tests-finalize.bats` | absent | created in Step 21 |
| `lib/aid-test-adapter-shell-suite.sh` | absent | created in Step 7 |
| `defaults/schemas/test-audit-decision.schema.json` | absent | created in Step 2 |
| `lib/aid-test-audit-decision.sh` | absent | created in Step 2 |
| `aid-test-audit-profile.sh` | absent | created in Step 12 |
| `lib/aid-test-timing-bats.sh` | absent | created in Step 11 |
| `aid-test-resource-map.sh` | absent | created in Step 14 |
| `aid-test-parallel-pilot.sh` | absent | created in Step 15 |
| `bats` | available | 1.8.2, per `aid-test-adapter-contract.sh` comment |
| `jq` | available | used throughout existing audit scripts |
| `yq` | available | used by catalog approval scripts |

## Implementation Steps

**EPIC 1: Steps 1-6 — Decision contract and fail-closed readiness**

### Step 1: Consumer inventory of audit verdicts and `--write-plan`

**Objective:** Produce a written, verified list of every code path and document that reads an audit
verdict, the consolidated findings file or the write-plan brief, so no later step changes a contract
a hidden consumer depends on.

**Files:**
- Create: `docs/plans/2026-08-03-P072-consumer-inventory.md` — the verified consumer list with one command and one output excerpt per entry, force-added so it survives a merge

**Architecture Context:** The finalize chain (`aid-audit-tests-finalize.sh` → consolidate → chat
summary → write-plan bridge) is the only sanctioned closing path, but the artifacts it produces
(`consolidated-findings.json`, `implementation-plan-brief.{json,md}`, the durable chat record) are
read by scripts and by the controller skill outside that chain. This step establishes the true
consumer set before Steps 2 and 3 add a field that any of them may need to tolerate.

**Implementation Detail:**
1. `grep -rn "consolidated-findings\|implementation-plan-brief\|remediation recommended\|needs measurement" plugins/ docs/ --include=*.sh --include=*.md --include=*.json` and record every hit with file and line.
2. For each hit, classify it as producer, consumer or documentation, and record whether it reads the verdict string, the findings array, or the brief.
3. `grep -rn "write_plan_bridge\|aid_test_audit_write_plan_bridge_check" plugins/` to find every caller of the bridge validator.
4. Record for each consumer whether an added top-level `audit_status` field would break it — specifically whether it validates with `additionalProperties: false` against a schema that does not yet know the field.
5. Record the P069 scheduler's read surface: `grep -n "test-catalog\|parallel" plugins/aid-orchestrator/scripts/aid-test-scheduler.sh` and note which catalog fields it reads today.

**Error Handling:** If a grep returns zero matches for a term this plan assumes exists (for example
`implementation-plan-brief`), the document records the zero-match result verbatim rather than
omitting the row; a silently absent consumer is exactly the blind spot this step exists to close, and
a zero-match finding changes later steps rather than being ignored.

**Edge Cases:**
- A consumer references the artifact only through a variable holding the filename, so a literal grep
  misses it — additionally grep for the containing directory name `test-audits` and reconcile the
  two result sets.
- A test fixture references a verdict string and would fail on a new field even though no production
  consumer would — classify it separately so Step 3 knows which fixtures need updating versus which
  contracts need preserving.

**Dependencies:**
- Depends on: ---
- Blocks: Step 2 — the schema must not add a field that an unlisted consumer rejects

**Acceptance Criteria:**
- [ ] `docs/plans/2026-08-03-P072-consumer-inventory.md` exists, is git-TRACKED (force-added past `.gitignore`'s `docs/` rule), and lists every consumer with a `file:line` reference
- [ ] Every listed entry carries the exact command run and an output excerpt, never an unsupported claim
- [ ] The document explicitly states, per consumer, whether adding a top-level `audit_status` field breaks it
- [ ] P069's `aid-test-scheduler.sh` catalog read surface is recorded with `file:line` references

**Effort:** S
**AID Role:** architect

---

### Step 2: Consolidated decision schema, writer and reader

**Objective:** Add the strict `aid-test-audit-decision-v1` schema and a deterministic library that
writes and reads the decision artifact, rejecting every malformed shape rather than coercing it.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/schemas/test-audit-decision.schema.json` — the strict decision artifact schema described in this plan's Data Model
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-audit-decision.sh` — write/read/validate helpers sourced by the consolidator and the renderer
- Modify: `plugins/aid-orchestrator/defaults/config/test-audit.yaml` — add the six `decision.*` keys every later step reads, with defaults
- Modify: `plugins/aid-orchestrator/defaults/schemas/test-audit-config.schema.json` — declare the six new keys so a malformed value fails at load, not at use
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-test-audit-config.sh` — expose the six keys through the existing loader with the same hardcoded-default convention
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-decision.bats` — schema acceptance and rejection cases for every invariant in the Data Model table
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-config.bats` — default values, schema rejection of out-of-range values, and byte-identity with the loader defaults

**Architecture Context:** This is the Decision layer named in the Architecture section. It sits
between the consolidator (which produces the artifact) and both the renderer and the write-plan
bridge (which consume it). It follows the same sourced-library convention as the existing
`lib/aid-test-audit-*.sh` files: no top-level `set -euo pipefail`, pure helpers, atomic
tmp-file-then-`mv` writes matching `aid-test-inventory.sh`'s existing discipline.

**Implementation Detail:**
1. Write the JSON Schema with `"additionalProperties": false` at every object level and
   `"required"` lists matching the Data Model table exactly.
2. Encode the conditional invariants with JSON Schema `if`/`then`: `impact.kind: measured` requires
   non-null `before_ms` and `after_ms`; `impact.kind: estimated` requires a non-empty `assumptions`
   array; `impact.kind: unknown` requires both millisecond fields null and forbids a non-empty
   `assumptions`; `current_runtime.kind: unknown` requires `duration_ms: null`.
3. Encode `audit_status: complete` as requiring `portfolio_coverage.missing_run_unit_ids` and
   `portfolio_coverage.duplicate_run_unit_ids` to be empty arrays.
4. Add a string pattern rejecting absolute paths (`^/`) and Windows-style roots in every free-text
   field, and a `maxLength` of 200 on any field that may carry a command fragment.
5. Implement `aid_test_audit_decision_write <decision_json> <output_path>`: validate against the
   schema first, then write atomically; a validation failure returns non-zero and writes nothing.
6. Implement `aid_test_audit_decision_read <path>`: re-validate on read and return non-zero on a
   file that no longer satisfies the schema, so a hand-edited artifact cannot be consumed.
7. Implement `aid_test_audit_decision_lane_units <path>`: return the union of all
   `parallelization.lanes[].run_unit_ids`, used by the disjointness check in Step 4.
8. Define all eight configuration keys this plan introduces in one place, because
   `defaults/config/test-audit.yaml` today holds exactly three keys
   (`budget_minutes_default`, `max_read_only_audit_agents`, `allowed_runners`) and no later step
   would otherwise be scoped to write it: `decision.max_unresolved_fraction` (default `0.25`, read by
   Step 4), `decision.profile_budget_minutes` (default `20`, Step 12),
   `decision.profile_log_max_bytes` (default `10485760`, Step 12),
   `decision.rootcause_tie_tolerance` (default `0.1`, Step 13), `decision.pilot_noise_ms`
   (default `2000`, Step 15), `decision.chat_render_max_ids` (default `25`, Step 19) and
   `decision.prompt_max_bytes` (default `65536`, Step 6) and
   `decision.provenance_recheck_budget_ms` (default `5000`, Step 16). Each is
   added to `test-audit-config.schema.json` with its type and range, and exposed through
   `lib/aid-test-audit-config.sh` with the same hardcoded-default-mirrors-the-file convention
   `/aid-init` already relies on for the existing three.

**Error Handling:** A schema validation failure returns exit code 3 with the failing JSON pointer on
stderr and writes no output file, so a partially valid artifact never lands on disk. A missing schema
file returns exit code 2 and names the expected path rather than silently skipping validation — a
validator that cannot find its schema must not report success.

**Edge Cases:**
- An artifact whose `lanes[].run_unit_ids` overlap between two lanes is schema-valid in isolation
  (JSON Schema cannot express cross-array disjointness); the reader enforces disjointness in bash and
  returns exit code 4 naming both lane ids.
- An empty `actions[]` array is legal — a genuinely healthy portfolio proposes nothing — and must
  not be conflated with `audit_status: incomplete`.
- An `evidence_refs[]` entry pointing outside the audit directory is rejected with the offending
  value quoted, preventing an evidence reference from escaping the audit root.

**Dependencies:**
- Depends on: Step 1
- Blocks: Step 3 — the bridge cannot refuse an `incomplete` artifact before the artifact exists

**Acceptance Criteria:**
- [ ] `test-audit-decision.schema.json` rejects an unknown top-level field with a non-zero exit
- [ ] `impact.kind: measured` with a null `before_ms` is rejected; `impact.kind: estimated` with an empty `assumptions[]` is rejected
- [ ] `audit_status: complete` with a non-empty `missing_run_unit_ids` is rejected
- [ ] `aid_test_audit_decision_write` writes nothing on a validation failure, verified by asserting the output path does not exist after a failed call
- [ ] `aid_test_audit_decision_read` returns non-zero on an artifact edited after writing
- [ ] Two lanes sharing a `run_unit_id` return exit code 4 naming both lane ids

**Effort:** M
**AID Role:** backend

---

### Step 3: `audit_status` semantics and the fail-closed write-plan refusal

**Objective:** Make an `incomplete` decision artifact mechanically unable to become a remediation
plan, while leaving every existing verdict string readable by the consumers Step 1 recorded.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-test-audit-write-plan-bridge.sh` — add the `audit_status` check to `aid_test_audit_write_plan_bridge_check` before its existing verdict and staleness checks
- Modify: `plugins/aid-orchestrator/scripts/aid-audit-tests-finalize.sh` (lines ~40-96) — accept a new `--mode` argument and pass it plus the decision artifact path through the chain to the bridge
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-write-plan-bridge.bats` — add refusal cases for `incomplete`, for a missing decision artifact, and for an artifact that fails re-validation

**Architecture Context:** The bridge is the single validator both `--write-plan` and the recognized
same-conversation continuation resolve to, and it already returns a `{ready:false, reason:<string>}`
shape that blocks the controller from invoking `/aid-plan write`. Adding `audit_status` there means
one check protects both entry points, matching the existing design where the bridge never invokes
the planner itself and only reports readiness.

**Implementation Detail:**
1. Add `audit_status` to the artifact produced by the consolidator and set it from the reconciliation
   result computed in Step 4; until Step 4 lands, the consolidator sets `incomplete` whenever the
   decision artifact is absent, which is the safe direction.
2. In `aid_test_audit_write_plan_bridge_check`, load `decision.json` via
   `aid_test_audit_decision_read` and return `{ready:false, reason:"audit_incomplete"}` when
   `audit_status` is `incomplete`, before any other check runs.
3. Scope the requirement to `full` mode. `aid-audit-tests-finalize.sh` currently accepts
   `--audit-id --wave-artifacts-dir --dispatch-manifest --output-dir --catalog --write-plan` and no
   mode, so the bridge cannot today distinguish "static audit, no decision by design" from "full
   audit, decision lost". Add `--mode static|measure|full` to finalize and thread it to the bridge.
   In `full` mode, a missing decision artifact returns
   `{ready:false, reason:"decision_artifact_missing"}` — the absence of a decision is not a decision.
   In `static` and `measure` modes the bridge keeps its existing verdict-only path unchanged, so a
   working capability is not removed as a side effect of this plan; the Scope section's promise that
   static and measure are untouched is thereby kept mechanically, not only in prose.
4. Return `{ready:false, reason:"decision_artifact_invalid"}` when `aid_test_audit_decision_read`
   returns non-zero, quoting the reader's own exit code.
5. Keep every existing check and its existing reason string unchanged so the consumers Step 1
   recorded continue to read what they read today.

**Error Handling:** If the decision artifact exists but its `audit_status` field is absent or holds a
value outside the enum, the bridge returns `{ready:false, reason:"decision_artifact_invalid"}`
rather than defaulting to either status; an unreadable status is treated as no authorization, never
as authorization.

**Edge Cases:**
- `--mode full --write-plan` on an audit whose decision artifact is missing refuses; the same
  invocation in `static` or `measure` mode reaches its existing verdict-only outcome, asserted by
  both cases so the mode split cannot regress into a blanket refusal.
- A resumed audit (`--resume <audit-id>`) reaches finalize with a decision artifact written by an
  earlier plugin version whose `schema_version` differs — the reader rejects it on the version field
  and the bridge reports `decision_artifact_invalid`, so a stale artifact cannot authorize a plan.
- A project has `review_checkpoints.cp1_plan_review: false`; the bridge refusal is independent of
  CP1 and still applies.

**Dependencies:**
- Depends on: Step 2
- Blocks: Step 4 — reconciliation sets the status this step enforces

**Acceptance Criteria:**
- [ ] A decision artifact with `audit_status: incomplete` makes `aid_test_audit_write_plan_bridge_check` return `ready:false` with reason `audit_incomplete`
- [ ] A missing decision artifact returns `ready:false` with reason `decision_artifact_missing`, not a pass
- [ ] An artifact failing re-validation returns `ready:false` with reason `decision_artifact_invalid`
- [ ] Every pre-existing bridge refusal reason string is unchanged, verified by the existing suite passing without modification to its assertions
- [ ] `--write-plan` on a `static`- or `measure`-mode audit reaches its existing verdict-only outcome and can still return `ready:true`, verified by the existing suite passing without modification to its assertions
- [ ] `--write-plan` on a `full`-mode audit with no decision artifact returns `decision_artifact_missing`

**Effort:** M
**AID Role:** backend

---

### Step 4: Mandatory terminal disposition and deterministic reconciliation

**Objective:** Replace the shard contract's optional findings with exactly one terminal disposition
per assigned `run_unit_id`, and make the consolidator fail closed when inventory, assignment and
disposition counts do not reconcile.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-test-audit-consolidate.sh` (lines ~1-231) — add the three-way reconciliation and set `audit_status` from its result
- Modify: `plugins/aid-orchestrator/defaults/schemas/test-audit-wave-artifact.schema.json` — add the required `dispositions[]` array with the record shape from this plan's Data Model
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-consolidate.bats` — add reconciliation cases for zero records, a dropped unit, a duplicated unit, and an all-unknown portfolio

**Architecture Context:** The consolidator already fails closed when a wave artifact is missing,
extra, or mismatched against the dispatch manifest, so the reconciliation machinery has a natural
home and an established failure convention. This step extends that check from artifact-level
presence to unit-level completeness, which is the difference between "every shard reported" and
"every test was decided".

**Implementation Detail:**
1. Read the discovered unit set from `inventory.json` and the assigned unit set from the dispatch
   manifest; compute `inventory_count` and `assigned_count`.
2. Collect every `dispositions[].run_unit_id` across all wave artifacts; compute
   `disposition_count`.
3. Compute `missing_run_unit_ids` as inventory minus dispositions, and `duplicate_run_unit_ids` as
   any id appearing in more than one disposition record across all artifacts.
4. Set `audit_status: complete` only when all three counts are equal and both id lists are empty;
   otherwise set `incomplete` and populate the lists.
5. Set `audit_status: incomplete` additionally when the fraction of units whose `disposition` is
   `measure` and whose `cost.kind` is `unknown` exceeds the threshold in
   `defaults/config/test-audit.yaml` (new key `decision.max_unresolved_fraction`, defined in Step 2, default `0.25`),
   which is the rule that stops "83 units, all unknown" from being called a completed audit.
6. Write `portfolio_coverage` into the decision artifact from these computed values, never from a
   shard's self-reported count.
7. Emit `unresolved[]` entries for every unit whose disposition is `measure`, carrying that record's
   own `missing_proof` and `next_measurement`.

**Error Handling:** A wave artifact whose `dispositions[]` array is absent fails validation against
the updated wave-artifact schema before reconciliation runs, so the consolidator reports a schema
error naming the artifact rather than silently treating the shard as having decided nothing. A
disposition naming a `run_unit_id` absent from the inventory is a distinct failure (exit code 5)
reported with the offending id, because it means a shard invented a unit.

**Edge Cases:**
- Two shards each emit a disposition for the same unit because the dispatch manifest assigned it
  twice — reconciliation reports it under `duplicate_run_unit_ids` and the manifest bug surfaces
  rather than one record silently winning.
- A shard emits a disposition for a unit assigned to a different shard — this is caught by the
  cross-artifact duplicate check when both emitted, and by the invented-unit check when only the
  wrong shard emitted.
- `inventory_count` is zero because the scope resolved to an empty subdirectory — reconciliation
  passes trivially, so an explicit guard sets `audit_status: incomplete` with reason
  `empty_inventory` rather than reporting a complete audit of nothing.

**Dependencies:**
- Depends on: Step 3
- Blocks: Step 5 — disposition content rules extend the record shape this step makes mandatory

**Acceptance Criteria:**
- [ ] A wave artifact with zero disposition records for an assigned unit fails reconciliation with a non-zero exit
- [ ] Dropping one assigned unit populates `missing_run_unit_ids` and yields `audit_status: incomplete`
- [ ] Duplicating one unit across two artifacts populates `duplicate_run_unit_ids` and yields `audit_status: incomplete`
- [ ] A portfolio where every unit is `measure` with `cost.kind: unknown` yields `audit_status: incomplete`
- [ ] A disposition naming a unit absent from the inventory exits with code 5 and quotes the id
- [ ] An empty inventory yields `audit_status: incomplete` with reason `empty_inventory`

**Effort:** L
**AID Role:** backend

---

### Step 5: Disposition content requirements and falsification evidence

**Objective:** Require every disposition to name the behavior it protects and its failure signal, and
require a falsification check before any proposal that reduces coverage.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/schemas/test-audit-wave-artifact.schema.json` — add the content fields and the conditional falsification requirement
- Modify: `plugins/aid-orchestrator/scripts/aid-test-audit-consolidate.sh` — populate `portfolio_change` from the disposition set
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-consolidate.bats` — add rejection cases for unproved removal, unproved merge and unproved rewrite

**Architecture Context:** This turns the disposition from a label into an argument. It is what makes
the reduction hypothesis in the Goal testable: a `remove` that cannot say which retained test still
catches the defect is refused, and a `keep` that cannot name a unique signal is surfaced as unproved
rather than presented as a considered decision. The current catalog's 83 empty `behavior_claims`
arrays are the measured baseline this replaces.

**Implementation Detail:**
1. Add `behavior_claim`, `failure_signal`, `falsification`, `uniqueness`, `overlaps_with`, `layer`
   and `cheaper_layer_possible` to the disposition record schema with the types in the Data Model.
2. Encode with JSON Schema `if`/`then`: `disposition` in `[remove, merge, rewrite_unit]` requires
   `falsification.method` not equal to `unproved` and a non-empty `falsification.evidence_ref`.
2a. State the relationship to the EXISTING mechanism explicitly, because one already ships: the
   wave-artifact schema already requires a `falsification_check` string on findings, and
   `aid-test-audit-consolidate.sh:159` already dies with "a remove/quarantine finding for '<id>' has
   no falsification_check — rejected before report". That check is retained unchanged for FINDINGS.
   The new structured `falsification` object lives on DISPOSITIONS, which findings do not have. A
   disposition and a finding covering the same unit must not disagree: the consolidator rejects a
   `remove` disposition whose unit also carries a finding with an empty `falsification_check`, and
   the two mechanisms are documented as findings-level and portfolio-level rather than as one
   superseding the other.
3. Encode: `uniqueness: overlaps` requires a non-empty `overlaps_with[]` whose entries are
   `run_unit_id` strings.
4. Encode: `cheaper_layer_possible: yes` requires a `target_layer` field from the same enum as
   `layer` and different from it.
5. In the consolidator, build `portfolio_change` by partitioning dispositions: `keep[]`,
   `rewrite_unit[]`, `merge_groups[][]` (grouped by shared `overlaps_with` membership), `remove[]`;
   set `current_run_units` from the inventory and `proposed_run_units` as
   `current_run_units - |remove| - (merged units beyond one per group)`.
6. Set `portfolio_change.impact_kind` to `measured` only when every unit contributing to
   `runtime_before_ms` has `cost.kind: measured`; to `lower_bound`-derived `estimated` when any is
   `lower_bound`; and to `unknown` when any contributing unit's cost is unknown.

**Error Handling:** A `remove` disposition whose `falsification.evidence_ref` names a path that does
not exist under the audit directory is rejected with exit code 6 quoting the reference, because an
unresolvable evidence reference is indistinguishable from no evidence and must not be trusted on the
strength of being a non-empty string.

**Edge Cases:**
- Three units mutually reference each other through `overlaps_with` — the merge grouping must produce
  one group of three, not three groups of two, so grouping uses connected components over the
  overlap relation rather than pairwise expansion.
- A unit proposes `merge` but names an overlap partner whose own disposition is `remove` — the
  consolidator reports this as a contradiction (exit code 7) rather than producing a merge group
  whose survivor is scheduled for deletion.
- A `keep` with `uniqueness: unproved` is legal and must not fail reconciliation; it flows into the
  renderer's "What is not proved yet" section instead.

**Dependencies:**
- Depends on: Step 4
- Blocks: Step 6 — the specialist prompts must instruct agents to produce these exact fields

**Acceptance Criteria:**
- [ ] A `remove` disposition with `falsification.method: unproved` is rejected with a non-zero exit
- [ ] A `merge` disposition with an empty `falsification.evidence_ref` is rejected
- [ ] A `remove` whose `evidence_ref` path does not exist exits with code 6 quoting the reference
- [ ] Three mutually overlapping units produce exactly one merge group of three
- [ ] A merge naming a partner marked `remove` exits with code 7
- [ ] A `keep` with `uniqueness: unproved` reconciles successfully and appears in the unresolved set
- [ ] The pre-existing findings-level `falsification_check` rejection at `aid-test-audit-consolidate.sh:159` still fires, verified by the existing case passing unchanged
- [ ] A `remove` disposition whose unit carries a finding with an empty `falsification_check` is rejected as a disagreement between the two levels

**Effort:** L
**AID Role:** backend

---

### Step 6: Specialist prompt updates — parallel safety, adversarial review, shard, consolidator

**Objective:** Update the four dispatched prompts so agents produce terminal dispositions with
evidence and challenge the specific reasoning failures the first P066 audit exhibited.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/prompts/test-audit-shard-auditor-prompt-v1.md` — replace optional findings with one mandatory terminal disposition per assigned unit
- Modify: `plugins/aid-orchestrator/defaults/prompts/test-audit-parallel-safety-prompt-v1.md` — require a resource assessment and a named bounded proof instead of a bare classification
- Modify: `plugins/aid-orchestrator/defaults/prompts/test-audit-adversarial-review-prompt-v1.md` — add the five named challenge classes
- Modify: `plugins/aid-orchestrator/defaults/prompts/test-audit-consolidator-prompt-v1.md` — require root-cause actions with evidence levels
- Modify: `plugins/aid-orchestrator/agents/test-portfolio-analyst.md` — state the terminal-disposition obligation on the agent card itself
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-prompts-golden.bats` — update golden assertions to the new required sections

**Architecture Context:** These prompts are the instruction surface for the shard and specialist
waves the dispatch manifest schedules. The agent card is the system-prompt surface a dispatched
subagent resolves from the installed plugin, so an obligation stated only in a prompt template can be
missed if the card contradicts it; both are updated together to keep one statement of the contract.

**Implementation Detail:**
1. In the shard prompt, replace the optional-findings instruction with: emit exactly one disposition
   record per assigned `run_unit_id`, including when the answer is `keep`; a unit you did not inspect
   is `measure` with a named `missing_proof`, never silence.
2. Add to the shard prompt the exact field list from the Data Model disposition table, with a worked
   example showing a `keep` with `uniqueness: unproved` and a `remove` with a mutation-based
   falsification.
3. In the parallel-safety prompt, state that `safe`/`constrained`/`exclusive`/`unknown` is evidence,
   not a verdict; require a resource assessment naming resource kind and namespace per the controlled
   vocabulary; and require either a proposed lane with its resource basis or a named bounded proof.
4. Add to the parallel-safety prompt the explicit instruction that a grep hit alone cannot label a
   resource shared, and that a per-test `mktemp` helper counts as positive evidence only after its
   callers and the files that deviate from it have been read — this is the false-lock-positive class
   the first P066 audit produced.
5. In the adversarial prompt, add five named challenge classes: resource scope claimed wider or
   narrower than the source supports; claimed runner capability not grounded in the installed
   version; "transaction isolation means safe" reasoning; membership mismatch between serial and
   parallel runs; and a saving claimed as `measured` without two comparable runs.
6. In the consolidator prompt, require every action to carry an `impact.kind` and forbid asserting
   that splitting a file is faster on the basis of file length alone.
7. Refresh `**Last Updated:**` on every modified prompt and on the agent card, and run
   `aid-lint-skill.sh` over the agent card.

**Error Handling:** The golden test asserts on required section headings rather than full prose, so a
wording improvement does not fail the suite while a removed obligation does. If a prompt file grows
past `decision.prompt_max_bytes` (added alongside the other keys in Step 2), the test fails with the measured
size, because a prompt silently truncated at dispatch would drop the obligation this step adds.

**Edge Cases:**
- A dispatched subagent resolves its card from a stale installed plugin cache rather than the working
  tree, so an obligation added here is invisible to it — the shard prompt therefore restates the
  disposition contract in full rather than referring to the card, and the dispatch manifest carries
  the contract inline.
- An agent returns dispositions for units outside its assignment — the Step 4 reconciliation catches
  this, and the prompt states plainly that a unit outside your assignment must not be reported.

**Dependencies:**
- Depends on: Step 5
- Blocks: Step 21 — end-to-end fixtures assert on artifacts these prompts produce

**Acceptance Criteria:**
- [ ] Each of the four prompts contains the new required section, asserted by the golden test
- [ ] The shard prompt contains a worked `keep` example and a worked `remove` example with falsification
- [ ] The parallel-safety prompt states the grep-alone prohibition verbatim
- [ ] The adversarial prompt names all five challenge classes
- [ ] The golden-prompt test asserts the modified agent card carries the terminal-disposition obligation verbatim
- [ ] `**Last Updated:**` is 2026-08-02 or later on every modified file

**Effort:** M
**AID Role:** docs-writer

---

**EPIC 2: Steps 7-10 — Complete discovery**

### Step 7: `sh:` shell-suite adapter and shebang-correct runner classification

**Objective:** Make the 36 genuine shell test suites real `run_units` via a fifth adapter, and route
the 7 Bats-syntax `test-*.sh` files to the Bats adapter so no file is run by the wrong runner.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-adapter-shell-suite.sh` — discovery adapter emitting `sh:`-prefixed run units
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-test-adapter-bats.sh` (lines ~55-65) — widen discovery from the `*.bats` glob to include `test-*.sh` files carrying a Bats shebang
- Modify: `plugins/aid-orchestrator/scripts/aid-test-inventory.sh` (lines ~27-40) — source the new adapter and include it in the discovery sweep
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-adapter-shell-suite.bats` — classification, id derivation, collision and non-suite-rejection cases

**Architecture Context:** `test-catalog.schema.json` already reserves the naming convention
`sh:<relative-path-without-extension>` in its `run_unit` documentation at line 135, so this adapter
implements a contract the schema anticipated rather than inventing one. It implements the same
interface as the four existing adapters in `aid-test-adapter-contract.sh`, so `aid-test-inventory.sh`
consumes it without special-casing and the existing `run_unit_id` collision check covers the new
namespace automatically. The Bats adapter's own discovery at
`aid-test-adapter-bats.sh` line 60 is `find … -name '*.bats'`, which is why the 7 Bats-syntax `.sh`
files are invisible today; `run-all-tests.sh` line 140 already classifies by shebang
(`head -1 "$suite" | grep -q 'bats'`), so this step makes the adapters agree with the runner the
project actually uses rather than inventing a new rule.

**Implementation Detail:**
1. Discover candidates with `find <scope> -type f -name 'test-*.sh'` relative to the canonical
   `project_root` the CLI parser resolved, excluding anything under `node_modules` and under a
   `fixtures/` directory.
2. Classify each candidate by its shebang line, never by its executable bit and never by filename
   alone: a shebang matching `bats` belongs to the Bats adapter; a shebang matching
   `^#!.*\b(bash|sh)\b` belongs to this adapter; a file with neither is skipped and recorded in a
   `skipped[]` list with its reason, never silently dropped. The executable-bit test is deliberately
   not used — 6 of this repository's 7 Bats-syntax `.sh` files are non-executable, and
   `test-scope-check.sh` is executable, so the bit correlates with nothing.
3. Hand Bats-shebang candidates to `aid-test-adapter-bats.sh`, which emits them as ordinary
   `bats:<relative-path-without-extension>` run units with `command.argv` of
   `["bats", "<relative-path>"]` — the invocation `run-all-tests.sh` line 140 already uses for them.
4. Derive this adapter's own `run_unit_id` as `sh:` plus the repo-relative path with the `.sh`
   extension removed, using the shared `adapter_json_escape` helper for the JSON string, matching how
   the bats adapter builds its own ids.
5. Build the `command.argv` for a genuine shell suite as `["bash", "<relative-path>"]`, so a measured
   command is the command the project actually runs.
6. Set `test_level: suite`, `parallel.status: unknown` with all four provenance fields null, and
   `isolation` fields `unknown`, matching what the bats adapter emits before any evidence exists.
7. Emit `source_paths` and `production_surfaces` as the single script path, consistent with the bats
   adapter's current output shape for a file-level unit.

**Error Handling:** A candidate whose path contains a character outside the `run_unit_id` charset
that `adapter_validate_audit_id`-style validation permits is rejected with its path quoted rather
than emitted with a mangled id, because a mangled id silently breaks the reconciliation in Step 4. A
`find` that returns zero candidates is legal (a project with no shell suites) and produces an empty
array, not an error.

**Edge Cases:**
- A file named `test-helpers.sh` that defines functions and runs nothing is discovered by the glob
  but is not a suite — the shebang classification skips it and records the skip reason, which is what
  keeps the count honest rather than inflated.
- A `test-*.sh` file carries a Bats shebang but is non-executable, which is true of 6 of this
  repository's 7 — it must still be routed to the Bats adapter, asserted explicitly, because an
  executable-bit test would have dropped all six.
- `test-scope-check.sh` carries a Bats shebang and IS executable — it must be routed to the Bats
  adapter too, not admitted as a shell suite, which is what an executable-bit test would have done.
- Two shell suites in different directories share a basename (`a/test-x.sh` and `b/test-x.sh`) —
  because the id is derived from the full relative path, they do not collide; the test asserts this
  explicitly because a basename-derived id would have collided.

**Dependencies:**
- Depends on: Step 6
- Blocks: Step 10 — reconciliation needs all five adapters emitting before it can de-duplicate

**Acceptance Criteria:**
- [ ] Running `aid-test-inventory.sh` against this repository discovers exactly 36 `sh:` run units
- [ ] The same run discovers 100 `bats:` run units — 93 from `*.bats` plus the 7 Bats-shebang `.sh` files
- [ ] Each of the 7 named Bats-shebang `.sh` files emits `command.argv` of `["bats", <path>]`, never `["bash", <path>]`
- [ ] `test-scope-check.sh` (Bats shebang, executable) is emitted as a `bats:` unit, not an `sh:` unit
- [ ] A file with neither shebang is excluded and appears in `skipped[]` with a reason
- [ ] Two same-basename suites in different directories produce two distinct `run_unit_id`s
- [ ] Every emitted `sh:` unit validates against `test-catalog.schema.json` without a schema change to the id pattern
- [ ] A project with zero shell suites produces an empty array and exit code 0

**Effort:** L
**AID Role:** backend

---

### Step 8: Disposable-clone configuration precondition

**Objective:** Stop a disposable-clone audit from silently losing every declared-command gate because
the gitignored `.aid-o/config/` was never copied into the clone.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-audit-tests-cli-parse.sh` — detect a scope whose resolved root lacks `.aid-o/config/execution.yaml` while the invoking project has one, and fail with a distinct exit code and the exact copy command
- Modify: `plugins/aid-orchestrator/commands/aid-audit-tests.md` — document the disposable-clone precondition in the invocation section
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-audit-tests-cli.bats` — add the missing-config detection case and the correctly-prepared-clone pass case

**Architecture Context:** The CLI parser is already the single fail-loud validation point for every
malformed input, returning a distinct exit code per failure class and publishing the canonical
`project_root` every later stage must use. Detecting a structurally under-prepared clone belongs
there for the same reason a nonexistent scope does: it is a precondition failure, and every later
stage would otherwise produce a confidently wrong result.

**Implementation Detail:**
1. After resolving the canonical `project_root`, test for `${project_root}/.aid-o/config/execution.yaml`.
2. When it is absent, determine whether the current working directory is itself an AID project with
   that file present; if so, this is the disposable-clone case.
3. Fail with exit code 12 and a message naming both paths and the exact command to fix it:
   `cp -r <cwd>/.aid-o/config <project_root>/.aid-o/config`.
4. When neither location has the file, this is an un-initialized project rather than a clone problem.
   The parser has no un-initialized detection today — `grep -nEi 'aid-o|uninitial'
   aid-audit-tests-cli-parse.sh` returns zero matches and its documented exit codes are 0 and 2-10 —
   so this step defines the case for the first time: exit code 14 with a message naming
   `/aid-init` as the fix. Without this branch the both-absent case would fall into the exit-12 clone
   branch and print a `cp -r` command copying a directory that does not exist.
5. Add a `--allow-missing-config` flag that downgrades the exit-12 case to a recorded warning in
   `audit-state.json`, for the deliberate case of auditing a project that genuinely has no declared
   gates; the warning text states that declared-command gates will be absent from this audit.

**Error Handling:** If `.aid-o/config/` exists but `execution.yaml` within it is unreadable due to
permissions, the parser reports that distinctly (exit code 13) rather than treating it as absent,
because "cannot read" and "not there" call for different operator actions.

**Edge Cases:**
- The clone was prepared correctly but `execution.yaml` is a broken symlink pointing outside the
  clone — the readability test catches this as exit 13 rather than passing on the symlink's presence.
- The audit is run against a subdirectory scope (`path:<path>`) of a properly configured project, so
  the scope root has no `.aid-o/` of its own — the check tests the resolved `project_root`, not the
  scope path, so this legitimate case passes.

**Dependencies:**
- Depends on: Step 7
- Blocks: Step 24 — the real full audit runs in a disposable clone and would hit this gap

**Acceptance Criteria:**
- [ ] A clone without `.aid-o/config/execution.yaml`, invoked from a project that has one, exits 12 and prints the exact `cp -r` command
- [ ] A correctly prepared clone passes with exit code 0
- [ ] A project with no `.aid-o/config/execution.yaml` in either location exits 14 naming `/aid-init`, never exit 12 with a `cp -r` of a nonexistent directory
- [ ] `--allow-missing-config` downgrades exit 12 to a recorded warning naming the consequence
- [ ] An unreadable `execution.yaml` exits 13, distinct from 12

**Effort:** S
**AID Role:** backend

---

### Step 9: Canonical result emission across every uncounted suite

**Objective:** Make the aggregate runner count the real result of all seven suites it currently
records as `0/0`, by giving each a canonical result line rather than teaching the parser five
grammars.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (lines ~205-220) — one tested `parse_suite_result` function plus the `unparsed` state
- Modify: `plugins/aid-orchestrator/scripts/tests/test-semantic-review.sh` + `plugins/aid-orchestrator/scripts/tests/test-instruction-consistency.sh` — emit the canonical line alongside their existing decorated one
- Modify: `plugins/aid-orchestrator/scripts/tests/test-control-boundary.sh` + `plugins/aid-orchestrator/scripts/tests/test-instruction-sweep.sh` — emit the canonical line alongside their `<name>: OK` / `<name>: N failure(s)` output
- Modify: `plugins/aid-orchestrator/scripts/tests/test-generation-finalize.sh` + `plugins/aid-orchestrator/scripts/tests/test-cp1-grounding.sh` + `plugins/aid-orchestrator/scripts/tests/test-plan-quality-enforcement.sh` — emit the canonical line from their exit-code-driven assertion counts
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-run-all-tests-result-grammar.bats` — parser cases per grammar, the skipped variant, an empty suite and the `unparsed` failure

**Architecture Context:** `run-all-tests.sh` is the aggregate collector behind the
`gate:shell_pipeline_smoke` gate, and its per-suite result parsing at line 213 greps `^Results:`
expecting `N/T passed, M failed`. Seven non-Bats suites emit nothing that matches, so all seven are
recorded as `0/0` today — not one, as the design document assumed. Their conventions are genuinely
different: `=== Results: N passed, M failed ===` (`test-semantic-review.sh:220`),
`Instruction Consistency: N passed, M failed, W warnings` (`test-instruction-consistency.sh:290`),
`<name>: OK` / `<name>: N failure(s)` (`test-control-boundary.sh:100,103`,
`test-instruction-sweep.sh:105`), and pure exit-code-driven assertion output with no summary at all
(`test-generation-finalize.sh`, `test-cp1-grounding.sh`, `test-plan-quality-enforcement.sh:167`).
Teaching one parser five grammars would leave a sixth to be invented later; emitting one canonical
line from each suite converges them instead.

**Implementation Detail:**
1. Extract the current result parsing into a named function `parse_suite_result` taking the suite
   output and echoing `passed total failed skipped`.
2. Keep grammar A (`Results: N/T passed, M failed[, W skipped]`) as the single canonical grammar,
   anchored at line start, unchanged from today.
3. Retain tolerance for grammar B (`=== Results: N passed, M failed ===`, optional leading `=== `,
   `total` derived as `N + M`) so a suite that emits only the decorated line still counts; this is
   the compatibility path, not the target state.
4. Add a canonical `Results: N/T passed, M failed` emission to each of the seven suites, keeping
   every existing human-facing line untouched. For the three exit-code-driven suites, count their
   own assertions: each already tracks pass and fail per check, and a suite with no counters emits
   `Results: 1/1 passed, 0 failed` on success and `Results: 0/1 passed, 1 failed` on failure, which
   is honest at suite granularity and never claims a per-case count it does not have.
5. When neither grammar matches, record the suite as `unparsed` with its exit code preserved, rather
   than as `0/0` — a suite whose output the collector cannot read is a distinct, visible state.
6. Make the aggregate run fail when any suite is `unparsed`. Because item 4 converts all seven first,
   this rule turns red only on a genuinely new grammar, never on the existing tree. The step's own
   acceptance requires a full `run-all-tests.sh` invocation showing zero `unparsed` suites before
   this rule is enabled.

**Error Handling:** A suite that exits non-zero and emits no result line at all is recorded as
`unparsed` with its exit code, and the aggregate reports it as a failure; the previous behavior of
recording `0/0` made a crashed suite and a passing-but-unparsed suite indistinguishable.

**Edge Cases:**
- A suite emits both grammars (which `test-semantic-review.sh` will after this step) — the parser
  takes the canonical grammar A line and ignores the decorated one, asserted by a test that feeds
  both and checks the parsed numbers come from A.
- Enabling item 6 before item 4 has converted all seven would turn `gate:shell_pipeline_smoke` red on
  six suites this step otherwise fixes — the acceptance criteria therefore require the zero-`unparsed`
  measurement to be captured before the failing rule is enabled, and the two land in one commit.
- A suite legitimately runs zero tests because every case was filtered out — it emits
  `Results: 0/0 passed, 0 failed`, which parses successfully and is distinct from `unparsed`.
- A suite's result line appears inside quoted output from a nested invocation — anchoring grammar A
  at line start and requiring grammar B's `=== ` prefix keeps a nested echo from being taken as the
  outer result.

**Dependencies:**
- Depends on: Step 8
- Blocks: Step 12 — the profiler's cost attribution reads aggregate results

**Acceptance Criteria:**
- [ ] All seven named suites emit a canonical `Results: N/T passed, M failed` line, verified by grepping each suite's real output
- [ ] `run-all-tests.sh` reports `test-semantic-review.sh`'s real passed and failed counts, never `0/0`
- [ ] A full `run-all-tests.sh` invocation reports zero `unparsed` suites, and that measurement is captured before the fail-on-unparsed rule is enabled
- [ ] Both grammars parse correctly in the unit test, including the skipped-count variant
- [ ] A suite emitting neither grammar is recorded as `unparsed` and fails the aggregate run
- [ ] A suite emitting both grammars parses from the canonical grammar A line
- [ ] `Results: 0/0 passed, 0 failed` parses successfully and is distinct from `unparsed`

**Effort:** L
**AID Role:** qa

---

### Step 10: Cross-runner inventory reconciliation

**Objective:** Make a repository-wide inventory reconcile against the real file count across all five
adapters without double-counting a file that two adapters can both claim.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-test-inventory.sh` (lines ~140-200) — add cross-runner de-duplication and a reconciliation summary
- Modify: `plugins/aid-orchestrator/defaults/schemas/test-audit-inventory.schema.json` — add the `reconciliation` block recording per-runner counts and resolved overlaps
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-inventory.bats` — overlap resolution, per-runner counts and the total-count assertion

**Architecture Context:** A gate run unit's `source_paths` is NOT its test target — it is the file
that declares the gate. All 8 `declared-command` units in the current approved catalog share the
single `source_paths` value `.aid-o/config/execution.yaml`, verified by
`yq -r '.run_units[] | select(.runner=="declared-command") | .source_paths[0]' | sort | uniq -c`
returning `8 .aid-o/config/execution.yaml`. A naive path-identity map would therefore see eight
same-runner units claiming one path and, under a same-runner tie-break rule, fail this very
repository. The real membership relationship a gate has with the tests it runs lives in its
`command.argv`, not in `source_paths`, and that is what this step must read.

**Implementation Detail:**
1. Build the path-identity map over `bats`, `sh` and `package` units only. `declared-command` units
   are excluded by construction: their `source_paths` names the declaring config file, so they can
   never legitimately participate in test-file identity.
2. For a path claimed by more than one of the included runners, apply a fixed precedence: `package`
   outranks `sh`, because a package-script invocation is what the project actually runs; the losing
   unit is dropped from `run_units` and recorded in `reconciliation.overlaps[]` with both ids and the
   applied rule. `bats` and `sh` cannot collide after Step 7's shebang classification, and a
   collision between them is reported as an adapter bug rather than resolved.
3. Derive `reconciliation.contains[]` from each declared gate's `command.argv`, not from its
   `source_paths`: resolve the argv's script path and, when that script is itself an aggregate
   runner (`run-all-tests.sh`) or a pool runner (`aid-bats-parallel-lane.sh`), record the gate as
   containing the run units those scripts dispatch. This is the relation Step 12's
   `duplicate_membership` attribution and Step 26's ledger both consume, so it must have a real
   derivation rather than an assumed one.
4. Emit `reconciliation.per_runner_counts` and `reconciliation.total_run_units`, plus
   `reconciliation.files_seen` as the count of distinct test-file source paths, excluding the
   declaring config file.
5. Fail closed with exit code 8 when `total_run_units` plus dropped overlaps does not equal the sum
   of per-runner emissions, because an arithmetic mismatch means a unit vanished silently.

**Error Handling:** If two units of the same included runner claim one path, the inventory fails with
exit code 9 naming both ids; this is an adapter bug and must not be resolved by an arbitrary
tie-break that hides it. Declared-command units cannot reach this branch, because item 1 excludes
them before the map is built — which is what keeps this repository's 8 gate units from tripping it.

**Edge Cases:**
- `gate:shell_pipeline_smoke`'s command is `bash …/run-all-tests.sh`, which itself invokes every
  shell suite — this is the `contains` relation derived in item 3, recorded rather than treated as 36
  duplicates, and Step 26's ledger consumes it.
- `gate:bats_all`'s command invokes `aid-bats-parallel-lane.sh`, which dispatches Bats units from the
  catalog — the same `contains` derivation applies, and it is what makes the `bats_all` versus
  `shell_pipeline_smoke` overlap detectable at all.
- A declared gate command uses a template placeholder (`{base_commit}`) so its argv target cannot be
  resolved statically — the unit stays `context_required`, contributes no `contains[]` entry, and is
  excluded from path-overlap resolution rather than being matched against a literal path.
- A symlinked test file resolves to the same real path as its target — path resolution uses the
  canonical real path so the pair is detected as one file, asserted by a fixture that creates the
  symlink.

**Dependencies:**
- Depends on: Step 9
- Blocks: Step 24 — the real full audit's coverage claim rests on this reconciliation

**Acceptance Criteria:**
- [ ] Inventory against this repository reports 136 distinct test-file source paths (100 bats + 36 sh), with `.aid-o/config/execution.yaml` excluded from `files_seen`
- [ ] The 8 declared-command units do NOT trip exit 9, verified by a real run against this repository's own approved catalog
- [ ] `reconciliation.contains[]` is derived from `command.argv` and records `gate:shell_pipeline_smoke` containing the shell suites and `gate:bats_all` containing the pooled bats units
- [ ] A template-placeholder gate command contributes no `contains[]` entry and stays `context_required`
- [ ] An arithmetic mismatch between per-runner emissions and the final count exits 8
- [ ] Two same-runner units of an included runner claiming one path exit 9 naming both ids
- [ ] A symlink and its target resolve to one file

**Effort:** L
**AID Role:** backend

---

**EPIC 3: Steps 11-13 — Cost diagnosis**

### Step 11: Ground the Bats timing capability and build the timing adapter

**Objective:** Establish what per-test timing the installed Bats version actually exposes and wrap it
in a fixture-tested adapter, without inventing a flag or parsing decorative terminal output.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-timing-bats.sh` — version-gated timing adapter producing per-test durations
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-timing-bats.bats` — parsing against recorded fixture output, version gating, and truncated-output handling

**Architecture Context:** `aid-test-adapter-contract.sh` already establishes the convention of
version-gating a runner capability rather than assuming it: its `adapter_supports_list_mode` comment
records that Bats 1.8.2 has no `--list` flag and that a future version may flip this, version-gated
and never assumed. This adapter follows that exact convention for timing. P071's diagnostic pass
already used `bats --timing` for real against this installed version, so the capability is grounded
in a run that happened rather than in documentation.

**Implementation Detail:**
1. Resolve the installed version with `bats --version` and parse the semantic version; record it in
   every emitted timing artifact so a profile is always attributable to a runner version.
2. Confirm `--timing` support for the resolved version by running it against a two-case fixture and
   asserting that per-case duration annotations appear; store that fixture's recorded output as the
   parser's test input so the parser is tested without invoking Bats.
3. Parse per-case durations into `{test_name, duration_ms}` records, keyed by the `@test` name as
   emitted, and attach the owning `run_unit_id`.
4. When the resolved version does not support timing, return a capability-absent result that the
   profiler converts into a file-level lower bound, never into a fabricated per-test figure.
5. Emit setup and teardown attribution only when the runner's output distinguishes them; when it does
   not, emit a single `body_plus_fixture` bucket and say so explicitly rather than splitting on a
   guess.

**Error Handling:** A truncated or interleaved output stream (a run killed at its deadline) yields
whatever complete records were parsed plus a `truncated: true` marker and the byte offset where
parsing stopped; a partial profile is reported as partial and never padded to look complete.

**Edge Cases:**
- Two `@test` cases share a name within one file, so name-keyed records collide — records carry an
  ordinal index alongside the name, and the test asserts both are retained.
- A test name contains the delimiter the output format uses — the parser splits on the fixed column
  position the recorded fixture establishes, not on the first occurrence of the delimiter.
- The runner writes timing to stderr rather than stdout on this version — the adapter captures both
  streams and the fixture records which one carried the data for the resolved version.

**Dependencies:**
- Depends on: Step 10
- Blocks: Step 12 — the profiler consumes this adapter's records

**Acceptance Criteria:**
- [ ] The adapter records the resolved Bats version in every emitted artifact
- [ ] Per-case durations parse correctly from the recorded fixture without invoking Bats in the test
- [ ] An unsupported version yields a capability-absent result, not a fabricated per-test figure
- [ ] Truncated output yields the parsed prefix plus `truncated: true` and the stop offset
- [ ] Two same-named cases in one file both survive parsing, distinguished by ordinal

**Effort:** M
**AID Role:** backend

---

### Step 12: Bounded diagnostic profiler with streamed evidence

**Objective:** Build the runner-owned profiler that attributes a high-cost unit's time to a named
cause, streams its output so a slow run is observable before its deadline, and records an honest
partial result on timeout.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-test-audit-profile.sh` — bounded profiling operation with streamed evidence and complete or partial receipts
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-test-audit-measure.sh` — route profiling commands through the existing allowlist check before dispatch
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-profile.bats` — allowlist refusal, live-checkout refusal, deadline partial receipt and cause attribution

**Architecture Context:** The profiler is an Evidence-layer component and obeys the same boundaries
as the existing measurement path: every command passes `aid_test_audit_check_allowed` before it
reaches `aid-job.sh`, and `aid-job.sh` owns process-group, deadline and receipt semantics. It adds
one requirement the current measurement path does not have — incremental evidence persistence — so a
run that will exceed an hour is observable long before its deadline.

**Implementation Detail:**
1. Select profiling targets as the highest-cost units from existing measurement data, capped by
   `decision.profile_budget_minutes`, defined in Step 2.
2. Refuse to run unless the target root is a disposable clone or fixture: assert the root differs
   from the canonical `project_root` the CLI parser published, and exit 10 naming both paths when it
   does not.
3. Stream stdout and stderr to `.aid-o/work/test-audits/<audit-id>/profiles/<run_unit_id>.log` with
   line-buffered appends, so the file grows during the run rather than at its end.
4. Attribute time into the buckets the runner can actually distinguish:
   `cost_rises_across_run`, `duplicate_membership`, `test_body`, `undecidable`.
   IMPLEMENTATION CORRECTION (2026-08-03): the plan originally named
   `fixture_growth` here, and the first implementation used it. Bats reports one
   duration per case; a rising curve therefore establishes that later cases cost
   more than earlier ones, and nothing about WHY. `fixture_growth` asserted a
   mechanism the measurement cannot see — and in the very suite it was pointed
   at, that mechanism does not exist, because `setup_test_evidence_dir` mktemps a
   fresh root and git-inits a fresh repository per case. The bucket is named for
   the measurement instead, and the finer buckets the plan listed
   (`setup_teardown`, `subprocess_git`, `retry_backoff`, `explicit_wait`) are NOT
   emitted at all: Bats does not separate setup from body from teardown, so any
   split across them would be invented. Those signals are recorded under
   `source_signals` as counts, never as an attributed share of milliseconds.
5. Attribute `duplicate_membership` by consulting Step 10's `reconciliation.contains[]` rather than
   by re-deriving membership.
6. On deadline expiry, write a receipt with `complete: false`, the elapsed wall clock, the buckets
   attributed so far, and a `lower_bound_ms` equal to elapsed time.
7. Emit a root-cause hypothesis only when at least one bucket holds a cited majority of attributed
   time; otherwise emit `measure` naming which bucket is undecidable and the next bounded probe.

**Error Handling:** A profiling command not present in the approved catalog or the project's real
`execution.yaml` is refused by `aid_test_audit_check_allowed` before any process starts, with exit
code 11 and the rejected command quoted; the profiler never constructs a command of its own.

**Edge Cases:**
- The target unit produces no timing records because the runner lacks the capability — the profiler
  emits a file-level `lower_bound_ms` and attributes nothing, rather than distributing total time
  across buckets by proportion.
- The run is cancelled by the operator rather than by its deadline — the receipt records
  `complete: false` with reason `cancelled`, distinct from `deadline`, because the two justify
  different next actions.
- The streamed log grows past `decision.profile_log_max_bytes` — the profiler truncates from the
  middle, records both retained ranges and the dropped byte count, and never silently discards the
  tail that contains the failure.

**Dependencies:**
- Depends on: Step 11, Step 10
- Blocks: Step 13 — the consolidator turns these profiles into actions

**Acceptance Criteria:**
- [ ] A profiling run against the live checkout exits 10 naming both paths
- [ ] A command absent from the allowlist exits 11 with the command quoted, before any process starts
- [ ] The evidence log is non-empty and growing while a run is still in flight, asserted by reading it mid-run
- [ ] A deadline-expired run writes a receipt with `complete: false` and a `lower_bound_ms` equal to elapsed time
- [ ] A run whose per-case durations rise across the run is attributed to `cost_rises_across_run`,
      with a confidence no higher than `medium`, and never to a named mechanism the timing cannot see
- [ ] A run with no dominant bucket emits `measure` naming the undecidable bucket and the next probe

**Effort:** L
**AID Role:** backend

---

### Step 13: Root-cause actions in the consolidator, dogfooded on the boundary suite

**Objective:** Turn profiles into named root-cause actions with honest evidence levels, and prove it
by diagnosing this repository's own most expensive suite before anyone proposes splitting it.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-test-audit-consolidate.sh` — map profile receipts to `actions[]` entries with `impact.kind` set from receipt completeness
- Create: `docs/plans/P072-boundary-suite-diagnosis.md` — the recorded diagnosis of `test-aid-plan-final-boundary.bats`'s AC5 path with its cited timing evidence
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-consolidate.bats` — profile-to-action mapping cases including partial receipts

**Architecture Context:** This closes the Decision layer's dependency on the Evidence layer: the
consolidator already reconciles counts from Step 4 and builds `portfolio_change` from Step 5, and now
also converts profile receipts into ranked actions. The dogfood target is chosen deliberately —
`test-aid-plan-final-boundary.bats` is one of the two files `gate:bats_boundary` isolates precisely
because it is too expensive to bound, and the design record states it ran over an hour without
completing while becoming progressively slower in its AC5 lifecycle section.

**Implementation Detail:**
1. Map a receipt with `complete: true` and a dominant bucket to an action whose `reason` names the
   bucket. `impact.kind` is `estimated` (with its assumption stated) only for `duplicate_membership`,
   where the saving follows from a configuration fact; otherwise `unknown`. IMPLEMENTATION
   CORRECTION (2026-08-03): the plan said `measured`, which the schema reserves for two comparable
   runs. One run of a suite measures its current cost, not a before-and-after pair, so `measured`
   here would have been a saving nobody observed.
2. Map a receipt with `complete: false` to an action with `impact.kind: unknown`, `before_ms` set to
   the receipt's `lower_bound_ms` and `after_ms` null; never present a lower bound as a measured
   before-and-after pair.
3. Map a `cost_rises_across_run` attribution to a `measure` action — not `fix`, and not `split`.
   IMPLEMENTATION CORRECTION (2026-08-03): the plan originally said `fix`, on the reasoning that
   splitting a file whose cost grows with accumulated state moves the growth rather than removing
   it. That reasoning is sound but its premise is not established by the measurement: a rising curve
   is equally consistent with later cases simply being heavier work, and those two call for opposite
   remedies. Only the fresh-root/reordered probe the receipt names separates them, so until it runs
   the honest action is to measure.
4. Map a `duplicate_membership` attribution to a `fix` action naming both gate surfaces, consuming
   Step 10's `contains[]` record.
5. Run the profiler against `test-aid-plan-final-boundary.bats` in a disposable clone with a bounded
   sub-budget, capture the streamed evidence, and record in the diagnosis document which bucket
   dominates its AC5 section, with per-case durations quoted from the receipt.
6. State in the diagnosis document whether the evidence supports a split, a fix, or neither, and say
   plainly when the run did not complete within its budget.

**Error Handling:** If the dogfood run does not complete within its sub-budget — the expected outcome
for a suite that previously ran over an hour — the diagnosis document records the partial attribution
and the lower bound explicitly and states that the split question remains open; it does not extend
the budget silently until a confident answer appears.

**Edge Cases:**
- The dominant bucket is `test_body`, meaning the suite is expensive because the behavior it tests is
  expensive — the correct action is `keep_serial`, not `split`, and the mapping asserts this.
- Two buckets tie within `decision.rootcause_tie_tolerance`, defined in Step 2 — the consolidator emits `measure` naming
  both, rather than picking the first.
- The profile is for a unit whose disposition from Step 5 is already `remove` — the action mapping
  suppresses a cost action for a unit proposed for deletion, because optimising a test scheduled for
  removal is wasted work, and records the suppression.

**Dependencies:**
- Depends on: Step 12
- Blocks: Step 19 — the renderer's "Test time" section reads these actions

**Acceptance Criteria:**
- [ ] A complete receipt with a dominant bucket produces an action naming that bucket, with
      `impact.kind: estimated` only where an assumption is stated and `unknown` otherwise
- [ ] A partial receipt produces `impact.kind: unknown` with `before_ms` from `lower_bound_ms` and `after_ms` null
- [ ] A `cost_rises_across_run` attribution maps to `measure` — never to `fix`, never to `split`
- [ ] `docs/plans/P072-boundary-suite-diagnosis.md` exists and quotes per-case durations from a real receipt
- [ ] The diagnosis document states explicitly whether the run completed within its budget
- [ ] A tie between two buckets emits `measure` naming both

**Effort:** L
**AID Role:** backend

---

**EPIC 4: Steps 14-18 — Resource evidence, pilot, and authority reconciliation**

### Step 14: Source-aware resource-map builder

**Objective:** Replace grep-only parallel-safety reasoning with a source-aware map recording each
resource and its namespace, so a shared-state claim rests on read source rather than on a pattern
match.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-test-resource-map.sh` — static resource inspection emitting resource and namespace pairs per run unit
- Create: `plugins/aid-orchestrator/defaults/schemas/test-resource-map.schema.json` — strict schema for the emitted map
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-resource-map.bats` — namespace classification, helper-following, and false-positive cases

**Architecture Context:** This is the component that prevents the false-lock-positive class the first
P066 audit produced. It executes nothing — it reads source — so it sits outside the job and receipt
boundary that the profiler and pilot require, and it produces the `resource_basis[]` values the
decision artifact's lanes cite.

**Implementation Detail:**
1. For each run unit, read its source file and every file it sources, following `source` and `.`
   directives up to a depth cap recorded in the output, so a helper's isolation guarantee is
   attributed to its callers.
2. Classify each detected resource into the kind and namespace vocabulary from the Data Model: a
   `mktemp`-derived path used inside a per-test `setup` is `temp_path/per-test`; a literal path under
   the repository is `fixed_path/shared` unless it is written only under a `mktemp` root.
3. Record `git_repo` and `git_worktree` mutations by detecting `git` invocations whose working
   directory is not a `mktemp` root.
4. Record `aid_state` for any read or write under `.aid-o/`, and `lock` for any use of the project's
   locking helpers, resolved by following the helper rather than by matching the word.
5. Emit, per resource, the file and line that justifies it, so every entry is checkable.
6. Emit `namespace: unknown` when the classification cannot be made from source, and never emit
   `shared` on the strength of a pattern match alone; the schema requires a justifying `file:line`
   for every `shared` classification.

**Error Handling:** A `source` directive whose target cannot be resolved (a computed path) is recorded
as an `unresolved_source` entry with the directive's `file:line`, and every resource classification
for that unit is capped at `unknown`, because a unit with unreadable dependencies cannot be proven
isolated.

**Edge Cases:**
- A file uses the shared `setup_test_evidence_dir` helper, which is the isolation guarantee P066's
  audit confirmed — the builder follows the helper and records `temp_path/per-test` with the helper's
  own `file:line` as justification, which is what makes it positive evidence rather than an
  assumption.
- A file uses the helper but also writes one literal path for a deliberate cross-test fixture — the
  builder emits both entries, and the unit is not classified isolated on the strength of the helper
  alone, which is exactly the exceptional case the design warns about.
- A resource string is built by variable interpolation so no literal path appears — the builder emits
  `fixed_path/unknown` with the interpolation site's `file:line` rather than omitting the resource.

**Dependencies:**
- Depends on: Step 13
- Blocks: Step 15 — the pilot selects its lane only after the resource map exists

**Acceptance Criteria:**
- [ ] Every emitted resource carries a justifying `file:line`
- [ ] A `shared` classification without a justifying `file:line` is rejected by the schema
- [ ] A unit using the per-test `mktemp` helper is classified `temp_path/per-test` with the helper's own location cited
- [ ] A unit using the helper plus one literal shared path emits both entries and is not classified isolated
- [ ] An unresolvable `source` directive caps that unit's classifications at `unknown`
- [ ] The builder executes no test command, asserted by running it with a command allowlist that would reject any execution

**Effort:** L
**AID Role:** backend

---

### Step 15: Bounded disposable-clone parallel-pilot runner

**Objective:** Build the pilot that compares a candidate lane serially and concurrently in a
disposable clone, with receipts, leak checks and a repeat policy, producing a proposal and never a
configuration change.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-test-parallel-pilot.sh` — bounded serial-versus-parallel comparison with receipts and leak checks
- Create: `plugins/aid-orchestrator/defaults/schemas/test-parallel-pilot.schema.json` — strict schema for the pilot receipt
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-parallel-pilot.bats` — membership mismatch, verdict mismatch, leak detection, repeat policy and live-checkout refusal

**Architecture Context:** The pilot is the second of the two evidence kinds a durable promotion
requires, the first being Step 14's resource map. It runs through `aid-job.sh` for process-group and
deadline semantics and through the command allowlist for command selection, and it writes only into
the audit evidence directory. It produces a proposal consumed by Step 18; it never writes the catalog.

**Implementation Detail:**
1. Refuse unless the target root is disposable, using the same assertion and exit code as Step 12's
   profiler, and additionally refuse when a gate run is in flight against the same root.
2. Run the selected membership serially, recording the ordered result set, aggregate verdict,
   duration and a command fingerprint.
3. Run the identical membership concurrently at the declared worker count, recording the same fields
   plus the worker count and the resource namespace the run was given.
4. Compare: membership must match exactly; the aggregate verdict must match; no case may pass
   serially and fail concurrently or the reverse.
5. Run the leak check after each run: `git status --short` must be empty in the disposable root, and
   no file may have been created outside the declared disposable root, checked by comparing a
   pre-run and post-run inventory of the parent directory.
6. Repeat according to `--repeat N`, requiring every repetition to satisfy every criterion; a single
   failing repetition ends the pilot with `promotion: refused` and the failing repetition's index.
7. Compute the measured benefit as serial duration minus parallel duration and record it; when the
   benefit is within noise as defined by `decision.pilot_noise_ms`, defined in Step 2, record
   `promotion: safe_not_worthwhile` rather than proposing a lane.

**Error Handling:** A concurrent run that fails while the serial run passed produces
`promotion: refused` with the differing case names, and the pilot does not retry; the design rule is
that failure keeps units serial rather than being retried until green, and the receipt records the
attempt so a later reader sees the refusal rather than only an absence.

**Edge Cases:**
- The parallel run is faster but one case's result differs in a way the aggregate verdict hides (a
  skip becoming a pass) — comparison is over the ordered per-case result set, not the aggregate
  alone, so this is caught.
- The disposable clone shares a git object store with the origin repository through a linked
  worktree, so a mutation escapes the clone — the pre-run and post-run parent inventory catches
  writes outside the root, and the pilot refuses a root that is a linked worktree of the invoking
  repository.
- The lane contains one unit only, so concurrency cannot help — the pilot records
  `promotion: safe_not_worthwhile` with the measured equality rather than proposing a single-unit
  lane.

**Dependencies:**
- Depends on: Step 14
- Blocks: Step 16 — the provenance block records this pilot's receipt as its evidence

**Acceptance Criteria:**
- [ ] A pilot against the live checkout refuses with the same exit code as the profiler's live-checkout refusal
- [ ] A membership mismatch between the serial and parallel runs yields `promotion: refused` naming the differing units
- [ ] A case passing serially and failing concurrently yields `promotion: refused` naming the case, with no retry attempted
- [ ] A non-empty `git status --short` after either run yields `promotion: refused` with the dirty paths listed
- [ ] One failing repetition out of `--repeat 3` yields `promotion: refused` with the failing index
- [ ] A benefit within `pilot_noise_ms` yields `promotion: safe_not_worthwhile`, not a proposed lane
- [ ] A linked worktree of the invoking repository is refused as a pilot root

**Effort:** L
**AID Role:** backend

---

### Step 16: Catalog `parallel` provenance block with content binding

**Objective:** Extend the catalog schema so a non-`unknown` parallel status must carry its evidence,
its verification time, its method and the source hash it was verified against — and reverts to
`unknown` when that hash no longer matches.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/schemas/test-catalog.schema.json` — add the `parallel.provenance` object and the conditional requirement
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-catalog-provenance.sh` — hash computation, verification and reversion helpers
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-catalog-provenance.bats` — missing-provenance rejection, hash-mismatch reversion and method-enum cases

**Architecture Context:** This is the field that ends the two-authority contradiction described in
the Context section. It makes `parallel.status` mean something a reader can check, which turns it
from a detector with no consumer into the single eligibility source Step 17 wires the lane to, in
line with `AID-v3-principles.md` §1.

**Implementation Detail:**
1. Add `provenance` to the existing `parallel` object with the four fields from the Data Model, each
   nullable, plus a JSON Schema `if`/`then` requiring all four to be non-null when `status` is not
   `unknown`.
2. Constrain `method` to `resource_map_plus_pilot`, `migrated_p071_step3` or `manual_pm`, so the
   origin of every promotion is machine-readable and a migrated entry is never indistinguishable from
   a freshly piloted one.
3. Implement `aid_test_catalog_provenance_hash <run_unit_id> <catalog> <project_root>`: compute the
   SHA-256 over the concatenated contents of the unit's `source_paths` in their catalog order, so a
   multi-file unit binds all of its sources.
4. Implement `aid_test_catalog_provenance_verify <run_unit_id> <catalog> <project_root>`: recompute
   and compare, echoing `match`, `mismatch` or `missing_source`.
5. Implement `aid_test_catalog_provenance_effective_status`: echo the recorded status on `match`; on
   `mismatch`, recompute the resource digest via Step 14's builder and echo the recorded status when
   the digest is unchanged (refreshing `source_sha256` and `verified_at` as a side effect) or
   `unknown` when it changed; echo `unknown` on `missing_source`. This is the single function every
   consumer calls, so the reversion rule cannot be forgotten by a caller reading the raw field.
5a. Keep the digest recomputation cheap enough to sit on the hot path: it is a static source read
   with no test execution, and the lane batches it across all units in one pass rather than shelling
   out per unit. When the recomputation cannot be completed within
   `decision.provenance_recheck_budget_ms` (an eighth key added in Step 2, default `5000`), the
   function fails closed to `unknown` for the units it did not reach, never silently retains a status
   it did not verify.
6. Add a schema-version bump on `test-catalog.schema.json` and keep the previous version readable, so
   a catalog approved before this change loads with all-null provenance and a uniform `unknown`
   effective status rather than failing.

**Error Handling:** A `source_paths` entry that no longer exists yields `missing_source`, and the
effective status is `unknown`; a deleted source file must never leave a unit pooled on the strength
of a hash computed over content that is gone.

**Edge Cases:**
- No run unit in this repository has more than one `source_paths` entry today (`yq -r
  '.run_units[].source_paths | length' | sort | uniq -c` returns `83 1`), so the multi-file hashing
  path and its ordering sensitivity are forward-looking and covered by synthetic fixtures only; the
  step records that explicitly rather than implying real coverage.
- A unit's `source_paths` order changes between catalog generations without any content change — the
  hash is computed over catalog order, so this changes the hash and reverts the unit to `unknown`;
  the test asserts this deliberately, because a reversion that costs one re-verification is the safe
  direction.
- A file's content changes only in a comment — the hash changes, the resource digest does not, so the
  unit keeps its status and the hash is refreshed. This is the case that makes the two-tier design
  necessary: a blanket revert here would cost a pilot for a comment.
- A file's edit both changes a comment AND adds a lock — the digest changes, so the unit reverts; the
  test asserts the digest, not the hash, is what decides.
- A catalog written by the previous schema version carries no `provenance` key at all — the loader
  treats it as all-null and effective `unknown`, asserted against a fixture copy of the current
  83-unit catalog.

**Dependencies:**
- Depends on: Step 15
- Blocks: Step 17 — the lane reads the effective status this step defines

**Acceptance Criteria:**
- [ ] `parallel.status: safe` with any null provenance field is rejected by the schema
- [ ] A source change that does NOT change the resource digest retains the recorded status and refreshes the hash in place, asserted by editing a comment in a pooled fixture file
- [ ] A source change that ADDS a fixed port or a shared path changes the resource digest and reverts the unit to `unknown`, asserted by a fixture that makes exactly that edit
- [ ] Against this repository's own 72 pooled files, a simulated week of edits (30 files touched) leaves the pool non-empty, asserted by a fixture replaying real commit ranges
- [ ] A deleted source path yields `missing_source` and an effective status of `unknown`
- [ ] `method` outside the three-value enum is rejected
- [ ] A pre-change catalog fixture loads with all-null provenance and uniform effective `unknown`
- [ ] A comment-only source change reverts the unit to effective `unknown`

**Effort:** M
**AID Role:** backend

---

### Step 17: Migrate the allowlist into the catalog and retire the text file

**Objective:** Make `aid-bats-parallel-lane.sh` read pool eligibility from the catalog's
provenance-bound effective status, migrate P071's real 72-file evidence with explicit attribution,
and remove the competing text authority.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-bats-parallel-lane.sh` (lines ~9-30 + ~195-260) — replace the allowlist source with the catalog effective status and update the classification-model header comment
- Create: `plugins/aid-orchestrator/scripts/aid-test-catalog-migrate-p071-allowlist.sh` — one-shot, idempotent migration writing the 72 entries with `method: migrated_p071_step3`
- Modify: `plugins/aid-orchestrator/defaults/config/bats-parallel-safe-allowlist.txt` — replace its content with a retirement notice naming the catalog as the authority
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-bats-parallel-lane.bats` — catalog-driven partition, reversion behavior, and refusal when the catalog is unapproved

**Architecture Context:** The lane already loads the catalog and already refuses to run when its
top-level `status` is not `approved`, deriving its complete file list from it; the only thing it
declines to read is `parallel.status`. Switching the eligibility source is therefore a change of
which field is consulted in a file already open, not a new dependency. The three-bucket partition and
the fail-closed default — anything not explicitly proven safe runs sequentially — are preserved
exactly.

**Implementation Detail:**
1. In the lane, replace the allowlist read with a per-unit call to
   `aid_test_catalog_provenance_effective_status`; a unit whose effective status is `safe` enters the
   parallel pool, and every other value places it in the sequential bucket.
2. Keep the boundary bucket exactly as it is: the two named boundary files stay out of the pool
   regardless of their catalog status, because their exclusion is a cost decision, not a safety one.
3. Keep every existing fail-closed path validation — nonexistent files, paths escaping the repository
   root, arguments beginning with `-`, and duplicate catalog entries — unchanged and still executed
   before any `bats` invocation.
4. Rewrite the script's classification-model header comment to state that the catalog's
   provenance-bound effective status is now the eligibility source, replacing the sentence that says
   the field is never consulted.
5. In the migration script, read the 72 paths from the retiring allowlist, resolve each to its
   `run_unit_id`, and write `status: safe` with `method: migrated_p071_step3`, `evidence_ref` naming
   `audit-20260802-070629` and P071 Step 3, `verified_at` set to P071's release date, and
   `source_sha256` computed at migration time.
6. Make the migration refuse when a listed path has no catalog run unit, naming the path, rather than
   creating an entry the inventory does not know about.
7. Replace the allowlist file's content with a retirement notice stating that the catalog is now the
   authority and that this file is no longer read, keeping the path present so an operator who opens
   it learns where to look instead of finding nothing.
8. Correct the denominator while migrating. The allowlist's provenance header states that P066's
   audit "read all 83 bats files"; the catalog holds 74 bats run units and the tree holds 100 real
   Bats run units, so 83 is wrong in both directions. The migrated `evidence_ref` records the real
   figures — 72 files piloted out of 74 catalog bats units, against a tree of 100 — and notes the
   header's error rather than reproducing it. Migrating the wrong number verbatim would launder an
   error into a durable schema field, which this plan's own Approach section forbids.

**Error Handling:** If the migration runs against a catalog whose schema predates Step 16, it exits
with the expected and found schema versions rather than writing provenance fields the schema does not
define. If the lane finds zero units with effective status `safe`, it runs everything sequentially
and says so — an empty pool is a valid, safe state, not an error.

**Edge Cases:**
- A file on the retiring allowlist has been edited since P071 verified it, so the migrated
  `source_sha256` binds current content while the evidence describes the older content — the
  migration recomputes the hash at migration time and records `verified_at` as P071's date, and the
  script prints a warning listing every file whose content changed since P071's release so the PM can
  decide whether to re-pilot; the warning names files, it does not silently exclude them.
- The catalog contains a `safe` unit that is not a bats file (a future `sh:` promotion) — the lane
  filters to bats units before partitioning, so a non-bats unit never enters a `bats -j` pool.
- Two catalog entries resolve to the same file path — the existing duplicate-entry validation already
  fails closed here and is asserted to still do so after the source change.

**Dependencies:**
- Depends on: Step 16
- Blocks: Step 18 — lane consolidation writes proposals against this single authority

**Acceptance Criteria:**
- [ ] The lane's parallel pool is derived from the catalog effective status, asserted by a fixture catalog that changes the partition
- [ ] A unit whose source hash no longer matches falls into the sequential bucket, not the pool
- [ ] The migration writes 72 entries with `method: migrated_p071_step3` and an `evidence_ref` naming `audit-20260802-070629`, P071 Step 3, and the corrected denominator (72 of 74 catalog bats units, tree of 100)
- [ ] The migrated `evidence_ref` does not repeat the allowlist header's "83 bats files" figure
- [ ] The migration is idempotent: a second run produces a byte-identical catalog
- [ ] A listed path with no catalog run unit fails the migration naming the path
- [ ] The allowlist file contains only a retirement notice and is read by no script, asserted by a repository-wide grep for its filename returning only the notice and this plan's own references
- [ ] Every pre-existing lane path validation still fails closed, asserted by the existing cases passing unchanged

**Effort:** L
**AID Role:** backend

---

### Step 18: Consolidate pilots into lanes and dogfood a representative lane

**Objective:** Turn resource maps and pilot receipts into named lanes, serial exceptions and blocked
prerequisites in the decision artifact, and reproduce comparable serial and parallel evidence for one
representative lane of this repository.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-test-audit-consolidate.sh` — build `parallelization.lanes[]` and `smallest_safe_pilot` from resource maps and pilot receipts
- Create: `docs/plans/P072-representative-lane-evidence.md` — the recorded serial and parallel evidence for the dogfooded lane
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-consolidate.bats` — lane construction, disjointness, and blocked-prerequisite cases

**Architecture Context:** This completes the Decision layer's parallelization section. Lanes are
proposals written into the decision artifact and rendered for a human; nothing here writes the
catalog, changes `scheduler.mode`, or approves a mapping. The separation is what keeps the audit a
recommendation, as the Scope section requires.

**Implementation Detail:**
1. Group units into candidate lanes by compatible resource basis: units whose resources are all
   `per-test` or `per-run` namespaced may share a lane; a unit with any `shared` resource forms its
   own `keep_serial` entry naming that resource.
2. Set a lane's disposition to `proposed_parallel` only when a pilot receipt for that exact membership
   reports `promotion: proposed` with the repeat policy satisfied.
3. Set `blocked_pending_fix` when the resource map identifies a specific removable conflict (a fixed
   path or port) and name the conflict in the lane's `resource_basis`.
4. Set `context_required` for units whose command carries an unresolved template placeholder, keeping
   them out of both the pool and the serial-with-reason bucket, since they were never actually
   evaluated.
5. Enforce lane disjointness before writing, using `aid_test_audit_decision_lane_units` from Step 2.
6. Populate `smallest_safe_pilot` with the smallest membership whose pilot would settle the largest
   number of currently unresolved units, and its pass criteria.
7. Dogfood: select a representative lane from this repository's bats units, run the pilot serially and
   concurrently in a disposable clone, and record both durations, both verdicts, the membership and
   the leak-check results in the evidence document. State explicitly that the result covers the
   piloted membership only.

**Error Handling:** A pilot receipt whose membership does not exactly match the lane it would promote
is refused with both memberships listed; a lane may not be promoted on evidence gathered for a
different set, which is one of the five adversarial challenge classes Step 6 added.

**Edge Cases:**
- A unit qualifies for two candidate lanes by resource compatibility — the grouping assigns it to
  exactly one lane deterministically by sorted `run_unit_id`, so repeated runs produce identical
  lanes and the disjointness check never fires on a grouping artifact.
- Every unit has a shared resource, so no lane can be proposed — the artifact carries zero
  `proposed_parallel` lanes and the renderer reports that parallelism is not currently supportable,
  which is a valid complete result rather than an incomplete one.
- The dogfooded lane shows a real but small benefit — the evidence document records the measured
  numbers and the `safe_not_worthwhile` conclusion rather than promoting on principle.

**Dependencies:**
- Depends on: Step 17
- Blocks: Step 19 — the renderer's parallel and serial sections read these lanes

**Acceptance Criteria:**
- [ ] A lane reaches `proposed_parallel` only with a matching pilot receipt satisfying the repeat policy
- [ ] A pilot receipt with a different membership than the lane is refused with both memberships listed
- [ ] A unit with a `shared` resource yields `keep_serial` naming that resource
- [ ] A template-placeholder command yields `context_required`, not `keep_serial`
- [ ] Lane assignment is deterministic across repeated runs on identical input
- [ ] `docs/plans/P072-representative-lane-evidence.md` records both durations, both verdicts, the membership and the leak-check result
- [ ] The evidence document states that its result covers only the piloted membership

**Effort:** L
**AID Role:** backend

---

**EPIC 5: Steps 19-23 — Human decision handoff and documentation**

### Step 19: Six-part decision-first renderer

**Objective:** Replace the five-part findings handoff with a deterministic six-part decision summary
that answers what to do before it presents any evidence.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-test-audit-chat-summary.sh` — replace the reasons-first renderer with the mandatory six-section ordering plus a technical evidence appendix
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-chat-summary.bats` — section ordering, the incomplete lead, the no-removal sentence and the named-set rendering

**Architecture Context:** The renderer is the second stage of the mandatory finalize chain and
persists the durable record as a side effect, failing closed if that persist fails. Its output is
presented verbatim as the command's final turn, so its ordering is the user-visible contract this
plan changes.

**Implementation Detail:**
1. Emit sections in this exact order: what to do now; what to fix, merge, split or remove; what can
   run in parallel; what must remain serial; test time now and after the proposed work; what is not
   proved yet; technical evidence.
2. For `audit_status: incomplete`, make the first section the smallest bounded next diagnostic action
   taken from `parallelization.smallest_safe_pilot` or from the highest-priority `measure` action, and
   do not emit a suggestion to create a remediation plan.
3. In the fix-merge-split-remove section, render the named id sets from `portfolio_change` — `keep`,
   `rewrite_unit`, `merge_groups`, `remove` — with counts, never a severity-ranked five-item list.
4. When `portfolio_change.remove` is empty, emit exactly: `No test is recommended for removal on
   current evidence.`
5. In the test-time section, render `runtime_before_ms` and `runtime_after_ms` with the
   `impact_kind` label attached, so an estimated saving is never presented as a measured one.
6. In the not-proved section, render every `unresolved[]` entry with its `missing_proof` and
   `next_measurement`, plus every `keep` whose `uniqueness` is `unproved`.
7. Keep the durable record persist and its fail-closed behavior exactly as they are today.

**Error Handling:** A decision artifact that fails re-validation on read causes the renderer to fail
closed with the reader's exit code rather than rendering a partial summary, because a summary
rendered from an artifact that no longer validates would present unchecked content as a decision.

**Edge Cases:**
- Every section is empty because the portfolio is healthy and fully parallel — the renderer still
  emits all six headings with an explicit statement under each, since a missing heading reads as an
  omission rather than as a finding of nothing.
- The id sets are large enough that verbatim rendering would exceed `decision.chat_render_max_ids`, defined in Step 2 — the renderer emits the first N ids per set with an exact remaining count and a
  path to the full list, and never silently truncates without the count.
- `audit_status` is `complete` but `unresolved[]` is non-empty, which is legal below the threshold —
  the not-proved section renders them and the first section still gives a recommended action.

**Dependencies:**
- Depends on: Step 18
- Blocks: Step 21 — the end-to-end fixtures assert on rendered output

**Acceptance Criteria:**
- [ ] The six sections plus the evidence appendix render in the mandatory order for a complete audit
- [ ] An incomplete audit leads with a bounded next diagnostic action and never suggests creating a remediation plan
- [ ] An empty `remove` set renders the exact no-removal sentence
- [ ] An `estimated` saving renders with its label attached, distinguishable from a measured one
- [ ] A healthy portfolio still renders all six headings with explicit statements
- [ ] Truncated id sets render an exact remaining count and a path to the full list
- [ ] A decision artifact failing re-validation makes the renderer fail closed

**Effort:** M
**AID Role:** backend

---

### Step 20: Command documentation, agent card and help text

**Objective:** Make the expected result of a full audit clear before dispatch, so an operator knows a
terminal disposition per unit is the normal outcome rather than a surprise.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-audit-tests.md` — document `audit_status`, the terminal-disposition contract, the six-part handoff and the reconciled parallel authority
- Modify: `plugins/aid-orchestrator/agents/test-portfolio-analyst.md` — align the card with the Step 6 prompt obligations
- Test: `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` — confirm the revised command file still lints clean
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-prompts-golden.bats` — assert the agent card carries the terminal-disposition section

**Architecture Context:** The command file is the contract document an operator and the controller
both read, and it currently states that `safe|constrained|exclusive|unknown` is a descriptive finding
that no scheduler consumes — a sentence that P069 and this plan both make false. Correcting it is
part of the requirement that documentation, prompts, schemas, renderer and tests all state the same
authority boundary.

**Implementation Detail:**
1. Replace the parallel-safety section's closing claim that this classification is consumed by
   nothing with an accurate statement: the provenance-bound effective status is consumed by
   `aid-bats-parallel-lane.sh` and by P069's scheduler, and promotion requires a resource map plus a
   pilot.
2. Add an `audit_status` subsection stating that `incomplete` blocks `--write-plan` and the
   same-conversation continuation, and naming the three refusal reasons.
3. Replace the chat-handoff section's five-part description with the six-part ordering.
4. Add a disposable-clone subsection documenting the Step 8 precondition and the `--allow-missing-config`
   flag with its stated consequence.
5. Update the agent card so the terminal-disposition obligation appears on the card itself, since a
   dispatched subagent may resolve the card from an installed plugin cache.
6. Refresh `**Last Updated:**` on both files. Run `aid-lint-skill.sh` over the command file only:
   `commands/aid-audit-tests.md` is NOT on `test-skill-lint.sh`'s GRANDFATHERED list and already
   exits 0 today, so the obligation is to keep it clean, not to bring it to standard. The agent card
   is deliberately out of that gate's scope — `test-skill-lint.sh` states it iterates
   `skills/*.md` + `commands/*.md` ONLY — and linting it would demand a `user_invocable:` field that
   is meaningless for a dispatched agent, so the card is verified by the golden-prompt test instead.

**Error Handling:** If `aid-lint-skill.sh` regresses to a non-zero exit on the command file after
revision, the revision is corrected rather than the file being added to the GRANDFATHERED list —
adding it would be a regression in the opposite direction from this plan's documentation obligation.

**Edge Cases:**
- A future contributor adds `agents/*.md` to the lint gate's scope, at which point the card would
  fail on frontmatter fields it has no reason to carry — the golden-prompt assertion added here is
  independent of that gate, so this step's guarantee survives such a change.
- A reader consults only the README and never the command file — the README capability entry, written
  in Step 23, states the recommendation-only boundary explicitly rather than deferring to the
  command file.

**Dependencies:**
- Depends on: Step 19
- Blocks: Step 22 — the enforcement registry cites these documented surfaces

**Acceptance Criteria:**
- [ ] The command file no longer claims the parallel classification is consumed by nothing
- [ ] The command file documents `audit_status`, the three refusal reasons and the six-part handoff
- [ ] The disposable-clone precondition and `--allow-missing-config` are documented with the stated consequence
- [ ] The agent card states the terminal-disposition obligation in full
- [ ] `aid-lint-skill.sh` continues to exit zero on `commands/aid-audit-tests.md` after revision
- [ ] The golden-prompt test asserts the agent card carries the terminal-disposition section
- [ ] No file is added to `test-skill-lint.sh`'s GRANDFATHERED list by this step

**Effort:** M
**AID Role:** docs-writer

---

### Step 21: End-to-end fixtures for five report shapes

**Objective:** Prove the whole finalize chain produces the right artifact and the right rendered text
for a complete audit, an incomplete audit, a no-removal audit, a serial-only audit and a
proven-parallel audit.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/test-integration-e2e-audit-pipeline.sh` — add the five report-shape scenarios end to end
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/audit-report-shapes/` — the five fixture input sets
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-audit-tests-finalize.bats` — chain-level assertions per shape

**Architecture Context:** The existing integration suite already verifies that a missing durable
record or an incomplete wave set makes the handoff mechanically unreachable. These scenarios extend
it from reachability to correctness of the decision itself, exercising consolidate, render and bridge
in one chain per shape rather than testing each script alone.

**Implementation Detail:**
1. Complete shape: every unit has a disposition, counts reconcile, at least one action carries
   `impact.kind: measured`; assert `audit_status: complete` and that the bridge returns `ready:true`.
2. Incomplete shape: one assigned unit has no disposition; assert `audit_status: incomplete`, that
   the bridge returns `audit_incomplete`, and that the rendered text leads with a bounded next action.
3. No-removal shape: every disposition is `keep` or `fix`; assert the exact no-removal sentence
   renders and that `portfolio_change.remove` is empty.
4. Serial-only shape: every unit has a `shared` resource; assert zero `proposed_parallel` lanes, a
   `keep_serial` entry per unit naming its resource, and `audit_status: complete`.
5. Proven-parallel shape: a lane with a matching pilot receipt satisfying `--repeat 2`; assert
   `proposed_parallel`, that the catalog is byte-identical before and after the audit, and that no
   `execution.yaml` was written.
6. Assert in every shape that no file outside the audit evidence directory was created or modified,
   by comparing a pre-run and post-run inventory of the fixture project root.

**Error Handling:** A scenario that leaves the fixture project dirty fails with the dirty paths
listed, because a test suite that tolerates its own leakage cannot assert that the audit does not
write outside its evidence directory.

**Edge Cases:**
- The proven-parallel shape's pilot needs a real concurrent run, which is slower than the other
  scenarios — it uses a two-unit fixture whose cases sleep for a bounded, recorded duration, so the
  scenario is real without being expensive.
- A shape passes for the wrong reason because its fixture is under-specified (for example, no-removal
  passes because there are no units at all) — each fixture asserts a non-zero unit count first.

**Dependencies:**
- Depends on: Step 20
- Blocks: Step 22 — the enforcement registry rows reference these tests as their verification

**Acceptance Criteria:**
- [ ] All five shapes run end to end through `aid-audit-tests-finalize.sh` and assert both artifact and rendered text
- [ ] The incomplete shape's bridge call returns `audit_incomplete` and the render leads with a bounded action
- [ ] The proven-parallel shape leaves the catalog byte-identical and writes no `execution.yaml`
- [ ] Every shape asserts a non-zero unit count before its shape-specific assertion
- [ ] Every shape asserts no file was created or modified outside the audit evidence directory

**Effort:** L
**AID Role:** qa

---

### Step 22: Enforcement registry rows for every new detection capability

**Objective:** Record each new enforcement introduced by this plan with its type, source,
instruction, severity and surface, so no detector ships without a named consumer.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — add the distributed rows
- Modify: `docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml` — add the internal rows
- Modify: `docs/extending-aid.md` — document the new enforcement surfaces for contributors
- Test: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-test-audit.sh` — assert each new row exists with a resolvable source and a named test

**Architecture Context:** The project's contribution rules require every new detection capability to
be registered with its enforcement mechanism named at design time, anchored to the P026 incident
where a working detector flagged correctly and was merged past because nothing was wired. Each row
added here names the exact script and exit code that enforces it and the test that proves it.

**Implementation Detail:**
0. Register NINE enforcements, not five. Four of them are enforced by steps that land after this
   one (Steps 8, 9, 10 and 26), so they are recorded with `status: planned` and flipped to `active`
   in Step 27 — the project's own established convention for a control whose reader does not yet
   exist, rather than either omitting the row or claiming an enforcement that is not there.
1. Add `test_audit_incomplete_blocks_write_plan` — enforced by
   `lib/aid-test-audit-write-plan-bridge.sh` returning `ready:false`, verified by the Step 21
   incomplete shape.
2. Add `test_audit_disposition_reconciliation` — enforced by `aid-test-audit-consolidate.sh` exit
   codes 5 and the `incomplete` status, verified by the Step 4 cases.
3. Add `test_audit_coverage_reduction_requires_falsification` — enforced by the wave-artifact schema
   conditional, verified by the Step 5 rejection cases.
4. Add `test_audit_parallel_promotion_requires_provenance` — enforced by
   `test-catalog.schema.json`'s conditional and `aid_test_catalog_provenance_effective_status`,
   verified by the Step 16 cases.
5. Add `test_audit_pilot_requires_disposable_root` — enforced by the Step 15 refusal exit code,
   verified by the live-checkout refusal case.
6. Add `test_audit_clone_config_precondition` (`status: planned`) — enforced by
   `aid-audit-tests-cli-parse.sh` exit 12/13/14 from Step 8, verified by that step's cases.
7. Add `test_audit_aggregate_unparsed_fails` (`status: planned`) — enforced by `run-all-tests.sh`
   failing the aggregate on any `unparsed` suite from Step 9.
8. Add `test_audit_inventory_arithmetic_guard` (`status: planned`) — enforced by
   `aid-test-inventory.sh` exit 8 and exit 9 from Step 10.
9. Add `test_execution_no_double_dispatch` (`status: planned`) — enforced by
   `aid-test-execution-ledger.sh close` from Step 26, whose production consumer is
   `aid-run-gates.sh` calling `close` at run end. This row exists specifically so the ledger does not
   ship as a detector read only by its own test.
10. Update the existing `test_audit_never_auto_invoked` row's surface list if this plan adds a new
    entrypoint, and state explicitly in the row that it does not.
11. For each row, record the recovery behavior: what an operator does when the enforcement fires.

**Error Handling:** The registry test fails when a row names a script or exit code that does not
exist, so a row cannot document an enforcement that was planned and never wired — which is the exact
failure mode the registry exists to prevent.

**Edge Cases:**
- A row's enforcement lives in a sourced library rather than an executable script — the row names the
  function as well as the file, since a library path alone is not locatable by a reader.
- The distributed and internal registries drift because a row was added to one only — the test
  asserts the new rows exist in both, matching how the project keeps both CHANGELOGs identical.

**Dependencies:**
- Depends on: Step 21
- Blocks: Step 23 — documentation cites the registered enforcements; Step 27 flips the four `planned` rows

**Acceptance Criteria:**
- [ ] Nine new rows exist in both registries with type, source, instruction, severity, surface and status
- [ ] The five rows whose enforcement already landed are `active`; the four whose enforcement lands in Steps 8, 9, 10 and 26 are `planned`, never `active`
- [ ] Each `active` row names a script or function and an exit code that exist, asserted by the registry test
- [ ] The registry test rejects an `active` row whose named exit code does not exist, and accepts a `planned` row whose does not yet
- [ ] Each row records its recovery behavior
- [ ] The registry test fails when a row names a nonexistent exit code, asserted by a deliberately broken fixture row
- [ ] `test_audit_never_auto_invoked` remains satisfied and its row states that this plan adds no entrypoint

**Effort:** M
**AID Role:** architect

---

### Step 23: Contributor documentation and authority-boundary reference

**Objective:** Document the reconciled parallel-safety authority, the decision artifact and the new
enforcement surfaces for contributors, without touching any version or CHANGELOG file — those move to
Step 27, after the last code change lands.

**Files:**
- Modify: `docs/extending-aid.md` — document the decision artifact, the provenance-bound catalog field and the nine new enforcement surfaces
- Modify: `plugins/aid-orchestrator/README.md` — describe the decision-quality audit and the single parallel-safety authority in the capability list
- Create: `docs/plans/P072-authority-boundary.md` — one reference page stating, for each of the three pre-existing surfaces, what it is after this plan
- Test: `plugins/aid-orchestrator/scripts/tests/test-instruction-consistency.sh` — assert no surviving document claims the parallel classification is consumed by nothing

**Architecture Context:** The Constraints section requires documentation, prompts, schemas, renderer,
enforcement registry and tests to state the same authority boundary. Three documents currently state
the opposite of what this plan makes true, and `test-instruction-consistency.sh` is the existing
mechanical guard for exactly this class of drift, so it is the right place to pin the corrected
statement rather than relying on a reviewer noticing.

**Implementation Detail:**
1. Write the authority-boundary reference: the catalog `parallel` block with provenance is the single
   computation; `aid-bats-parallel-lane.sh` and `aid-test-scheduler.sh` both consume it through
   `aid_test_catalog_provenance_effective_status`; the text allowlist is retired; the scheduler
   overlay is subordinate — provenance wins wherever it has an opinion, and the overlay resolves
   only the never-verified case where provenance has none.
   *(AMENDED 2026-08-04 by PM decision — recorded in `docs/plans/P069-recontract-check.md` §4a.
   The original wording was "may only narrow, never widen".)*
2. Update `docs/extending-aid.md` with the decision artifact's schema name, the disposition contract
   and each new enforcement's surface and recovery behavior.
3. Update the plugin README capability entry, stating the recommendation-only boundary explicitly
   rather than deferring to the command file.
4. Add an assertion to `test-instruction-consistency.sh` that no file under `plugins/` claims the
   parallel classification has no consumer, so the sentence this plan falsifies cannot reappear.

**Error Handling:** If the new consistency assertion fires against a file this plan did not plan to
touch, that file is corrected in this step rather than added to an exclusion list, because an
exclusion list is how the contradictory sentence survived three releases in the first place.

**Edge Cases:**
- A historical document (an archived plan under `docs/plans/archive/`) legitimately records the old
  boundary as it was at the time — the assertion scopes to `plugins/` and the live `docs/` tree, not
  to archived records, which must not be rewritten.
- The reference page and `extending-aid.md` drift from each other — the page is the single source and
  `extending-aid.md` links to it rather than restating the rules.

**Dependencies:**
- Depends on: Step 22
- Blocks: Step 24 — the real full audit is read against a documented boundary

**Acceptance Criteria:**
- [ ] `docs/plans/P072-authority-boundary.md` states, for each of the three pre-existing surfaces, its post-plan status
- [ ] No file under `plugins/` claims the parallel classification is consumed by nothing, asserted by the new `test-instruction-consistency.sh` check
- [ ] `docs/extending-aid.md` documents all nine new enforcement surfaces with their recovery behavior
- [ ] The consistency assertion scopes to `plugins/` and live `docs/`, leaving `docs/plans/archive/` untouched, asserted by a fixture archived file carrying the old sentence

**Effort:** M
**AID Role:** docs-writer

---

**EPIC 6: Steps 24-28 — Whole-path wiring and outcome proof**

### Step 24: One real full audit and its sanctioned approval

**Objective:** Run a real `--mode full` audit of this repository through the ordinary user path and
approve its catalog and mapping through the existing sanctioned scripts, producing the artifact the
remaining steps consume.

**Files:**
- Create: `docs/plans/P072-real-audit-record.md` — the recorded audit id, invocation, decision summary and approval evidence
- Test: `plugins/aid-orchestrator/scripts/tests/test-integration-self-host-audit.sh` — extend the self-host integration check to assert the new coverage and reconciliation figures

**Architecture Context:** This is the first step that exercises everything the previous five EPICs
built as one chain, against a real 136-file portfolio rather than a fixture. It runs in a disposable
clone prepared per Step 8's precondition, and its approval uses `aid-test-catalog-approve.sh` plus
the separate `aid-test-catalog-confirm-mapping.sh` gate, unchanged by this plan.

**Implementation Detail:**
1. Prepare a disposable clone and copy `.aid-o/config/` into it per the Step 8 precondition.
2. Run `/aid-audit-tests repo --mode full --budget-minutes N` with a budget recorded in the audit
   record, and capture the six-part rendered output verbatim.
3. Record the reconciliation figures: `inventory_count`, `assigned_count`, `disposition_count`, and
   the per-runner counts from Step 10, and confirm the inventory covers all 136 files.
4. Record how many units reached each disposition, and how many remain `measure` with their named
   next probes.
5. Approve the resulting catalog with `aid-test-catalog-approve.sh` and separately confirm the
   mapping with `aid-test-catalog-confirm-mapping.sh`, capturing both reviewed-diff hashes.
6. Record whether `audit_status` is `complete` or `incomplete` and, when incomplete, state which
   threshold or reconciliation caused it without adjusting the threshold to obtain a better outcome.

**Error Handling:** If the audit returns `incomplete`, the record documents it as the result and the
remaining steps proceed against whatever units did reach a durable disposition; the audit is not
re-run with relaxed thresholds to manufacture a `complete` status, because that would defeat the
entire mechanism this plan builds.

**Edge Cases:**
- The audit exceeds its budget mid-way — the resume path is used to continue rather than restarting,
  and the record notes the resume, since restarting would discard completed evidence.
- The approval step rejects the catalog because a `run_unit_id` drifted between generation and
  approval — the record documents the drift and the re-run rather than force-approving.

**Dependencies:**
- Depends on: Step 23
- Blocks: Step 25 — the scheduler consumes this approved artifact

**Acceptance Criteria:**
- [ ] `docs/plans/P072-real-audit-record.md` records the audit id, the exact invocation and the verbatim six-part output
- [ ] The recorded inventory covers 136 source files across five runners
- [ ] `inventory_count`, `assigned_count` and `disposition_count` are recorded and stated as reconciling or not
- [ ] The catalog approval and the separate mapping confirmation are both recorded with their reviewed-diff hashes
- [ ] An `incomplete` result is recorded as the result, with no threshold adjusted to change it

**Effort:** L
**AID Role:** qa

---

### Step 25: Feed the approved artifact to the P069 scheduler through the real gate runner

**Objective:** Prove that the approved decision drives real scheduled execution through generated
`execution.yaml` and `aid-run-gates.sh`, not through a direct scheduler invocation.

**Files:**
- Create: `docs/plans/P069-recontract-check.md` — the re-grounding of P069's scheduler contract against this plan's final schema, with the backward-compatibility verdict
- Modify: `plugins/aid-orchestrator/scripts/aid-test-scheduler.sh` (lines ~204-230) — replace the raw `parallel.status` read and subordinate the overlay to the provenance-bound effective status
- Test: `plugins/aid-orchestrator/scripts/tests/test-integration-scheduler-catalog-consumption.sh` — assert the scheduler's selection matches the approved effective statuses

**Architecture Context:** P069 shipped the scheduler, its 3-stage rollout gate and the
`aid-run-gates.sh` dispatch with exit-3 and exit-11 escalation. This plan changes the meaning of a
field the scheduler may read, so the Constraints section requires P069 to be re-grounded against the
final schema before any consumption, and the change held for a separate amendment if backward
compatibility cannot be proved.

**Implementation Detail:**
1. Re-read `aid-test-scheduler.sh`'s catalog access using the Step 1 consumer inventory as the
   starting list, and record every field it reads with `file:line`.
2. Determine whether a catalog carrying the new `provenance` object still validates and loads for the
   scheduler unchanged; record the verdict with the command run and its output.
3. The change is known to be necessary, not conditional: `aid-test-scheduler.sh:226` reads
   `($ru.parallel.status) as $catalog_status` directly, inside a single jq program over the whole
   catalog. Because `aid_test_catalog_provenance_effective_status` is a bash function that cannot be
   called from inside jq, pre-compute an `id -> effective_status` map in bash (one pass over the
   catalog, batch-hashing the source files) and pass it to the existing jq program as
   `--argjson eff`, replacing `$catalog_status` with a lookup into that map. The jq program's shape
   is otherwise unchanged.
4. Subordinate the overlay rather than removing it: `aid-test-scheduler.sh:227-228` currently lets an
   approved overlay entry's `promoted_status` override the catalog.
   **AMENDED 2026-08-04 by PM decision.** The original text required the overlay to "only narrow,
   never widen". That rule cannot be implemented against the overlay as it exists: `promoted_status`
   admits only `safe` and `constrained`, both more permissive than `unknown`, and the schema states
   the array is never read to demote. Narrow-only would therefore not restrict the overlay, it would
   delete it, while leaving the schema, the approval script and the field names describing a
   mechanism that no longer does anything.

   The contract actually implemented, and the one this plan now requires:
   **provenance wins wherever it has an opinion; the overlay resolves only the case where it has
   none.** Concretely — a unit REVOKED by a source-hash or resource-digest mismatch can never be
   promoted by an overlay entry, because provenance has an opinion about it and that opinion is
   `unknown`. A unit that was NEVER verified has no provenance opinion, and an approved overlay entry
   may still promote it. This preserves what the original rule was protecting (an overlay must not
   contradict a content check) and keeps the overlay's real use.

   Making the overlay demote as well is a change to the overlay schema and its approval flow, and is
   deliberately deferred to a separate P069 amendment rather than smuggled into the resolver.
4. Configure the disposable project's generated `execution.yaml` through the real
   `compose_execution_yaml` path rather than by hand-editing, and confirm the configured mode is
   still `sequential` by default.
5. Advance the rollout stage only through the existing 3-stage gate with its required divergence
   evidence; do not bypass it for this proof.
6. Run `aid-run-gates.sh` with the configured profile and capture per-unit receipts.

**Error Handling:** If backward compatibility cannot be proved — a catalog with provenance fails to
load for the scheduler — the change is held and recorded as a required P069 amendment rather than
being shipped with an untested scheduler interaction, exactly as the Constraints section requires.

**Edge Cases:**
- The rollout gate refuses to advance because this repository has no qualifying divergence evidence
  bundles — the proof runs at `sequential` and records that scheduled concurrency could not be
  demonstrated here, which is an honest partial result rather than a bypassed gate.
- The generated `execution.yaml` differs from this repository's own gitignored one, so the proof runs
  against different gates than the self-host configuration — the record names both and states which
  was used.

**Dependencies:**
- Depends on: Step 24
- Blocks: Step 26 — the ledger is keyed by the receipts this step produces

**Acceptance Criteria:**
- [ ] `docs/plans/P069-recontract-check.md` records every scheduler catalog read with `file:line` and a backward-compatibility verdict with its command output
- [ ] The configured mode is verified to remain `sequential` by default in the generated configuration
- [ ] The rollout stage is advanced only through the existing 3-stage gate, or the proof runs at `sequential` and says so
- [ ] `aid-run-gates.sh` produces per-unit receipts for the configured profile
- [ ] `aid-test-scheduler.sh` no longer reads `parallel.status` directly; the effective-status map is asserted to revert a hash-mismatched unit to `unknown`
- [ ] An approved overlay entry cannot promote a unit whose effective status is `unknown`, asserted by a fixture that tries
- [ ] An approved overlay entry can still narrow `safe` to `exclusive`, asserted by a fixture
- [ ] The effective-status map is computed in one pass, asserted by counting `yq` invocations in a traced run

**Effort:** L
**AID Role:** backend

---

### Step 26: Execution ledger proving no unit runs twice

**Objective:** Capture a ledger keyed by candidate SHA, command fingerprint and `run_unit_id` that
fails when the same unit is executed by two overlapping gate surfaces.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-test-execution-ledger.sh` — ledger writer, `open`/`close` lifecycle and double-execution check
- Create: `plugins/aid-orchestrator/defaults/schemas/test-execution-ledger.schema.json` — strict ledger schema
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` — open the ledger at run start, append entries for gates whose command directly invokes a runner, close and evaluate at run end
- Modify: `plugins/aid-orchestrator/scripts/aid-bats-parallel-lane.sh` — append one entry per bats unit it dispatches, in both the pool and sequential buckets
- Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` — append one entry per suite it dispatches
- Modify: `plugins/aid-orchestrator/scripts/aid-test-scheduler.sh` — append one entry per scheduled execution unit
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-execution-ledger.bats` — duplicate detection, fingerprint distinctness and the contains-relationship case

**A live double execution this ledger must catch, and would have missed as first designed.**
`gate:bats_fsm`'s command is `bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` —
a direct runner invocation that passes through none of the three fan-out points. That same file is
line 34 of the parallel-safe allowlist, so `gate:bats_all` runs it too, and the `full`, `release` and
`p064-closure` profiles each include both gates. **`test-aid-fsm.bats` therefore executes twice on
every full and every release gate run today.** Instrumenting only the three fan-out points would have
recorded one entry for it and reported zero duplicates — the ledger would have certified as clean the
exact defect it exists to detect. A fourth emission path is therefore required, not optional.

**Architecture Context:** The gate runner cannot see run units for fan-out commands.
`aid-run-gates.sh`'s ordinary path is
`run_gate()` at line ~139, which takes a gate name and an opaque command string and executes it with
`timeout … bash -c "$command"` — it has no `run_unit_id` parameter and no knowledge of what the
command fans out to. `gate:bats_all` runs up to 100 Bats units inside one command
(`aid-bats-parallel-lane.sh`), and `gate:shell_pipeline_smoke` runs every suite inside one command
(`run-all-tests.sh`), so a ledger appended from the gate runner would record roughly nine entries per
run — one per gate — and could never detect the `bats_all` versus `shell_pipeline_smoke` overlap it
exists to find. Instrumentation therefore belongs at the three real dispatch points, with the gate
runner owning only the ledger's lifecycle. The scheduler is the third point because P069's
`targeted_tests` path at `aid-run-gates.sh` lines ~218-289 bypasses `run_gate()` entirely and
dispatches through `aid-test-scheduler.sh` as a subprocess returning one aggregate batch result.

**AMENDED 2026-08-04 by PM decision — the containment exemption is withdrawn.**
The plan originally said Step 10's `contains[]` relation would let the check distinguish a legitimate
membership (`gate:bats_all` contains the units the lane runs) from a genuine overlap. It was built,
and it immediately silenced the real defect: `gate:bats_fsm` runs `test-aid-fsm.bats` directly while
`gate:bats_all` runs it in the pool, and "the pool gate contains it" turned a genuine double
execution into zero duplicates.

The exemption answers a question that does not arise. Each dispatch point appends once per execution
it ACTUALLY performs, so two entries under two gate ids are two executions; containment would only
matter if one execution were recorded twice, and none is. `--contains` is still accepted and recorded
so a reader can see what the membership relation was, but **it never suppresses a finding.**

What DOES excuse a repeat is a declaration made at the time it happened: `execution_kind`
(`normal` | `retry` | `escalation`), set by the code path that caused the repeat. Those are reported
as `deliberate_repeats` — visible, because a rerun still costs wall clock — and do not fail the run.
Silence is not a declaration: the default is `normal`, so a forgotten mark stays a defect.

**Implementation Detail:**
1. `aid-run-gates.sh` calls `aid-test-execution-ledger.sh open --candidate-sha <sha> --run-id <id>`
   before the first gate and `close` after the last, and `close` runs the duplicate evaluation. The
   ledger path is exported so the three dispatch points append to the same file.
2. Each dispatch point appends one entry per unit it actually dispatches, with the candidate SHA, the
   command fingerprint, the `run_unit_id` and the gate id it is running under. A dispatch point
   invoked outside a gate run (a developer running `run-all-tests.sh` by hand) finds no exported
   ledger path and appends nothing, which must not be an error.
2a. `aid-run-gates.sh` additionally appends entries itself for any gate whose command is a DIRECT
   runner invocation it can resolve statically — a command whose argv is `bats <path…>` or
   `bash <test-script>` naming files that resolve to catalog run units. This is the fourth emission
   path, and it is what makes `gate:bats_fsm` visible. Resolution reuses Step 10's argv logic rather
   than a second parser. A gate command that resolves to nothing (`docs_updated`'s inline git
   pipeline, `ui_calibration_signoff`'s `jq`, `plan_diff`'s null command) appends nothing, which is
   correct — those gates execute no test unit.
3. Detect a double execution as two entries sharing candidate SHA and `run_unit_id` with different
   gate ids. **AMENDED 2026-08-04:** there is NO containment exclusion — see above. The only split is
   between undeclared repeats (`duplicates`, fail the run) and repeats whose executions declared
   themselves `retry`/`escalation` (`deliberate_repeats`, reported and not failed).
4. Report a detected double execution with both gate ids and the unit, and exit non-zero, so the
   campaign in Step 28 fails rather than silently double-counting its wall clock.
5. Make the ledger append atomic under concurrency, since the scheduler dispatches units in parallel;
   use the same tmp-file-then-`mv` plus lock discipline the existing queue writer uses.
6. Emit a summary at the end of a campaign: units dispatched, distinct units, duplicates detected.

**Error Handling:** A ledger append that fails to acquire its lock within the timeout fails the gate
run rather than skipping the append, because a ledger with silent gaps cannot support the claim that
no unit ran twice.

**Edge Cases:**
- The same unit legitimately runs twice under different candidate SHAs across a campaign — the key
  includes the SHA, so this is not a duplicate, asserted by a fixture with two SHAs.
- A gate re-runs a unit after an escalation (P069's exit-3 or exit-11 path re-runs as a `--profile
  full` subprocess) — the escalation is recorded with its own gate id and marked as an escalation, so
  it is reported as a deliberate re-run rather than as an overlap defect.
- Two gates run the same file through different commands (one with a filter, one without) — the
  fingerprints differ, and the check reports it as an overlap anyway, because the unit's test cases
  are being executed twice regardless of the command shape.

**Dependencies:**
- Depends on: Step 25
- Blocks: Step 27 — the campaign's no-double-execution claim rests on this ledger

**Acceptance Criteria:**
- [ ] **AMENDED 2026-08-04.** The original criterion required a real `--profile full` run to REPORT `test-aid-fsm.bats` as executed twice. It did, which is how the live duplicate was found — but leaving that as the acceptance criterion would mean shipping a plan whose success condition is that the repository still wastes the run. Split in two:
  - [ ] The detector's red proof is preserved in a FIXTURE (`test-aid-test-execution-ledger.bats` case 1 — the same two gate ids, asserted to exit 7), so removing the live duplication cannot blind the check
  - [ ] The live duplication is REMOVED — `bats_fsm` is dropped from the `full` and `release` profiles, which already run that file through `bats_all` — and a real `aid-run-gates.sh --profile full` run then reports ZERO duplicates
- [ ] A real `aid-run-gates.sh` run produces one ledger entry per dispatched run unit, not one per gate — asserted by comparing the entry count against the lane's own reported partition sizes
- [ ] A gate whose command resolves to no test unit (`docs_updated`, `ui_calibration_signoff`) appends nothing and does not fail
- [ ] Two entries sharing candidate SHA and `run_unit_id` under different gate ids are reported as a duplicate with both gate ids
- [ ] **AMENDED 2026-08-04 — inverted.** A pair recorded in `contains[]` IS still reported as a duplicate: containment never suppresses a finding, asserted by a fixture that supplies a matching `--contains` file and still expects exit 7
- [ ] The same unit under two candidate SHAs is not reported as a duplicate
- [ ] A P069 escalation re-run is recorded and marked as an escalation, not as an overlap defect — via `execution_kind`, set on the escalation subprocess through `AID_EXECUTION_KIND`, and asserted both ways (a declared repeat passes, an undeclared one still exits 7)
- [ ] The scheduler appends one entry per unit BEFORE launching it, and a failed append cancels that dispatch rather than running a unit no ledger will record
- [ ] Invoking `run-all-tests.sh` by hand with no exported ledger path appends nothing and exits zero
- [ ] Concurrent appends produce no lost entries, asserted by a fixture dispatching in parallel
- [ ] A lock acquisition timeout fails the gate run rather than skipping the append

**Effort:** L
**AID Role:** backend

---

### Step 27: Version freeze and release

**Objective:** Freeze a released artifact that actually contains every code change this plan makes,
so Step 28's fresh-project proof installs the thing under test rather than a version predating the
ledger, the scheduler change and the whole-path script.

**Files:**
- Modify: `CHANGELOG.md` — add the release entry in the project's mandated format
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — the byte-identical copy of that entry
- Modify: `README.md` — update the Roadmap section with the new version line
- Modify: `plugins/aid-orchestrator/README.md` — update the plugin version line
- Modify: `.claude-plugin/marketplace.json` + `plugins/aid-orchestrator/.claude-plugin/plugin.json` — bump both version fields in each
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` + `docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml` — flip the four `planned` rows from Step 22 to `active`
- Test: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — assert the eight version locations agree and that both CHANGELOGs mention the new version

**Architecture Context:** The CHANGELOG header is this project's single source of truth for the plugin
version, and the eight-location registry in `CLAUDE.md` and `defaults/policies/release-policy.yaml`
defines every file that must agree with it. This step sits after Steps 25 and 26 deliberately: those
steps modify `aid-test-scheduler.sh`, `aid-run-gates.sh`, `aid-bats-parallel-lane.sh` and
`run-all-tests.sh` and create `aid-test-execution-ledger.sh`, none of which would be present in an
artifact released earlier. Constraint 8 also requires a `plan_branch` plan to release once, at its own
boundary, not at a step two thirds of the way through.

**Implementation Detail:**
1. Write the CHANGELOG entry under `Added`, `Changed`, `Fixed` and `Removed` headings in that order,
   each item as `- **Name** — one specific sentence`.
2. Record under `Removed` that the hand-maintained parallel-safe allowlist is retired in favour of the
   provenance-bound catalog field, naming both.
3. Record under `Changed` that the scheduler overlay is now subordinate to the catalog's effective
   status, so a consumer project reading the CHANGELOG learns the precedence changed.
4. Copy the entry verbatim into the plugin CHANGELOG and verify byte equality with `diff`.
5. Bump the two `marketplace.json` fields, the `plugin.json` field, and the two README version lines
   to the same version as the CHANGELOG header.
6. Update the root README Roadmap section, keeping the three most recent versions.
7. Flip the four enforcement rows Step 22 recorded as `planned` — the disposable-clone precondition,
   the aggregate `unparsed` failure, the inventory arithmetic guard and the execution ledger — to
   `active`, now that Steps 8, 9, 10 and 26 have all landed, and re-run the registry test.
8. Run `verify-version-files.sh <new_version> --baseline 2.68.0` and paste its output into the step's
   evidence.

**Error Handling:** If `diff` between the two CHANGELOGs reports any difference, the step fails rather
than reconciling automatically, because an automatic reconciliation could silently pick the wrong
side of a genuine editorial divergence. If any row is still `planned` after item 7, the release is
blocked: a released artifact must not carry a detector whose enforcement it does not contain.

**Edge Cases:**
- A version location's regex pattern in `release-policy.yaml` no longer matches its file because the
  surrounding prose changed — `verify-version-files.sh` catches this and the pattern is corrected,
  not the file reshaped to satisfy a stale pattern.
- Another plan lands a CHANGELOG entry between this step's write and the plan's release — the entry
  is rebased under a new header rather than merged into the other plan's section.
- A `planned` row's enforcement did land but its named exit code changed during implementation — the
  row is corrected to the real exit code before being flipped, never flipped over a stale reference.

**Dependencies:**
- Depends on: Step 26
- Blocks: Step 28 — the fresh project installs this exact released artifact

**Acceptance Criteria:**
- [ ] Both CHANGELOGs are byte-identical, asserted by `diff` returning no output
- [ ] All eight version locations show the same version, asserted by `verify-version-files.sh` exiting zero against the new version with `--baseline 2.68.0`
- [ ] The CHANGELOG `Removed` section names the retired allowlist and the replacing catalog field, and `Changed` names the scheduler-overlay subordination
- [ ] The root README Roadmap lists the three most recent versions with this one marked current
- [ ] Zero enforcement rows remain `planned`, asserted by the registry test
- [ ] The released tree contains `aid-test-execution-ledger.sh` and the Step 25 scheduler change, asserted by inspecting the tagged revision

**Effort:** M
**AID Role:** release

---

### Step 28: E2E pipeline verification — fresh project, real path, measured wall clock

**Objective:** Verify the complete capability end to end in a fresh disposable project using the
released plugin, and report the actual before and after wall clock for the release campaign — or
report plainly that the campaign was not run.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/test-integration-e2e-whole-path.sh` — the fresh-project end-to-end verification
- Create: `docs/plans/P072-campaign-ledger.md` — the campaign record with measured wall clock and the double-execution verdict
- Test: `plugins/aid-orchestrator/scripts/tests/test-integration-e2e-whole-path.sh` — the scenario assertions listed below

**Scenario coverage:** the scenarios below exercise every layer this plan touches in one run —
discovery, decision, approval, scheduling, gate dispatch, receipts and the ledger.

**Architecture Context:** This is the proof the Goal names and the one the design document's exit
criterion 11 makes load-bearing. It runs from a fresh or disposable project using the released plugin
and the real generated configuration path, because component unit tests and a synthetic scheduler
fixture do not demonstrate that the parts connect.

**E2E Scenarios:**

1. *Ordinary user command produces a complete decision.* In a fresh project initialized with
   `/aid-init` and containing a small known test portfolio, run `/aid-audit-tests repo --mode full
   --budget-minutes N`. Assert: `decision.json` validates; `audit_status` is `complete`;
   `inventory_count` equals the known file count; every unit has exactly one disposition.
2. *Approval activates real scheduled execution.* Approve the catalog and confirm the mapping through
   the sanctioned scripts. Assert: the generated `execution.yaml` still declares `sequential` before
   any opt-in; after the rollout gate is satisfied, `aid-run-gates.sh` dispatches approved units
   concurrently and produces one receipt per unit.
3. *Unknown units stay serial.* Include one unit whose source is modified after verification so its
   provenance hash mismatches. Assert: its effective status is `unknown` and it appears in the
   sequential bucket, never in the pool.
4. *Verdicts match the sequential baseline.* Run the same membership sequentially and through the
   scheduler. Assert: identical per-case result sets and identical aggregate verdicts.
5. *No unit runs twice.* Assert: the Step 26 ledger reports zero duplicates across the campaign,
   excluding recorded `contains[]` relationships and marked escalations.
6. *Measured wall clock is reported.* Assert: `docs/plans/P072-campaign-ledger.md` contains a
   before and after wall-clock figure, each labelled `measured`, or an explicit statement that the
   campaign was not run and the acceleration claim is therefore not supported.

**Implementation Detail:**
1. Build the fresh project from the released plugin as an ordinary consumer would, not from the
   working tree, so the proof covers what a user installs.
2. Use a small known portfolio whose file count and expected results are fixed in the fixture, so
   scenario 1's assertion is exact rather than approximate.
3. Record the wall clock for the sequential baseline and for the scheduled run separately, each with
   the membership it covered.
4. Write the campaign record with both figures, the ledger summary and the double-execution verdict.

**Error Handling:** If the multi-hour campaign cannot be completed in the available window, the
campaign record states that explicitly under scenario 6 and the plan's release notes repeat it; the
combined P066, P069, P071 and P072 line of work is then not described as delivering test-suite
acceleration, per this plan's own exit criteria.

**Edge Cases:**
- The fresh project's rollout gate cannot be satisfied because it has no divergence evidence — the
  proof records scenarios 1, 3, 4 and 5 at `sequential` and states that scenario 2's concurrency half
  was not demonstrated, rather than bypassing the gate.
- The released plugin lags the working tree because Step 27's release has not propagated to the local
  plugin cache — the proof forces a cache refresh first and records the resolved version. This is a
  cache problem only because Step 27 now sits after every code change; were the release still at
  Step 23, no cache refresh could recover code that was never in the released artifact, and the
  scenario-5 ledger assertion would be unprovable by construction.

**Dependencies:**
- Depends on: Step 27
- Blocks: none — this is the plan's final step and its outcome proof

**Acceptance Criteria:**
- [ ] All six scenarios pass on a single full run with 0 failures, or any not-demonstrated scenario is recorded with its reason
- [ ] The fresh project is built from the released plugin and the resolved version is recorded
- [ ] A provenance-mismatched unit is verified to appear in the sequential bucket, never in the pool
- [ ] Scheduled and sequential runs produce identical per-case result sets and aggregate verdicts
- [ ] The ledger reports zero duplicates, excluding recorded `contains[]` relationships and marked escalations
- [ ] `docs/plans/P072-campaign-ledger.md` reports measured before and after wall clock, or states plainly that the campaign was not run

**Effort:** L
**AID Role:** e2e

---

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Switching the lane's eligibility source breaks this repository's own `bats_all` gate | Medium | High | The migration writes the same 72 files that are pooled today, so the partition is unchanged on day one; Step 17 asserts the partition against a fixture catalog and keeps every existing path validation |
| The provenance hash reverts many units at once after an unrelated refactor, silently serialising the suite | Medium | Medium | The lane reports its partition sizes on every run, and Step 17's acceptance requires an empty pool to be stated rather than silent; re-verification is a bounded pilot, not a re-audit |
| P069's scheduler cannot load a catalog carrying provenance | Low | High | Step 25 re-grounds before consumption and holds the change as a separate P069 amendment if compatibility cannot be proved |
| The multi-hour campaign is deferred again, as it was in P069 | High | Medium | Exit criterion 12 makes the acceleration claim conditional on it; the campaign record must state plainly that it was not run, which keeps the debt visible rather than absorbed |
| The boundary suite diagnosis does not complete within its sub-budget | High | Low | Step 13 plans for the partial outcome explicitly: the diagnosis records the lower bound and states the split question remains open |
| A dispatched shard resolves a stale agent card from the plugin cache and ignores the terminal-disposition obligation | Medium | Medium | Step 6 restates the contract in the shard prompt and inline in the dispatch manifest rather than relying on the card, and Step 4's reconciliation fails the audit if dispositions are missing |
| Schema strictness rejects a legitimate artifact shape discovered only in the real audit | Medium | Medium | Step 24 runs the real audit before the E2E proof, so a strictness defect surfaces against real data while there is still a step to fix it in |
| Step 26's first real ledger run reports the known `test-aid-fsm.bats` duplicate and is mistaken for a ledger bug | Medium | Low | The duplicate is documented in Step 26 as a pre-existing, measured condition of the `full`/`release`/`p064-closure` profiles, and Step 26's acceptance requires the ledger to REPORT it; removing the duplicate is a separate decision this plan does not take |

## Success Criteria

1. `/aid-audit-tests --mode full` cannot present a materially unknown portfolio as remediation-ready:
   an `incomplete` decision artifact is refused by the write-plan bridge with a named reason.
2. Every remediation-ready audit carries a schema-valid decision artifact and a six-part
   decision-first summary.
3. Every discovered run unit has exactly one terminal disposition, and inventory, assignment and
   disposition counts reconcile — across all 136 test files: 100 Bats run units (93 `.bats` plus the
   7 Bats-shebang `.sh` files) and 36 genuine shell suites.
4. Cost findings name a grounded root cause or an explicitly bounded next probe, never a bare
   file-level timeout.
5. Exactly one parallel-safety COMPUTATION exists — the catalog's provenance-bound effective status.
   The text allowlist is retired, and the P069 scheduler overlay survives only as a subordinate
   narrowing filter that can never promote a unit the catalog does not already call safe. P071's real
   72-file evidence is preserved under `method: migrated_p071_step3` with a corrected denominator.
6. A source change to a pooled file demonstrably reverts it to `unknown` and moves it out of the pool.
7. Parallel recommendations name lanes, serial exceptions and evidence, and activate no scheduling.
8. P069's scheduler contract is unchanged, or explicitly re-grounded and amended with its verdict
   recorded.
9. Documentation, prompts, schemas, renderer, enforcement registry and tests all state the same
   authority boundary, with nine new enforcement rows in both registries and zero rows left
   `planned` at release.
10. A fresh-project end-to-end run proves the approved audit result is consumed through the real gate
    runner, with identical verdicts to the sequential baseline and zero double executions — or the
    record states plainly which scenarios were not demonstrated and why, in which case consumption
    through the real gate runner is NOT claimed as proven.
11. The campaign record reports measured before and after wall clock, or states plainly that the
    campaign was not run — in which case this line of work is not described as delivering test-suite
    acceleration.

## Next Steps

1. CP1 review of this plan, including the mandatory codebase grounding pass with evidence per item.
2. C0 cross-provider review, required because this plan declares `risk: high`.
3. EPIC generation via `/aid-plan epic .aid-o/plans/P072-test-audit-decision-quality.md`.
4. Execution via `/aid-run`, one EPIC at a time, with targeted tests per step and a single aggregate
   candidate run on the frozen final revision.
