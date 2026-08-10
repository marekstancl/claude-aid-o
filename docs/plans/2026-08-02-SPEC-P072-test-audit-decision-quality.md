---
type: spec
title: Test-Audit Decision Quality, Diagnostic Depth and Whole-Path Proof
prepared: 2026-08-02
supersedes_design_doc: docs/plans/2026-08-02-IMP-TEST-AUDIT-DECISION-QUALITY-AND-DIAGNOSTICS.md
base: main @ db1aad9 (v2.68.0)
absorbs: P070 (draft, never shipped)
depends_on_shipped: [P066 (v2.65.0-v2.66.2), P069 (v2.67.0), P071 (v2.68.0)]
---

# Spec: Test-Audit Decision Quality, Diagnostic Depth and Whole-Path Proof

## 0. Status of this document

This is the **re-grounded** specification for the design document
`docs/plans/2026-08-02-IMP-TEST-AUDIT-DECISION-QUALITY-AND-DIAGNOSTICS.md`. That document
was written against `main` at v2.66.2 and explicitly deferred implementation
until "P069 is merged or frozen" (its §9). **P069 merged and released as
v2.67.0 on 2026-08-02, and P071 released as v2.68.0 the same day.** The
deferral condition has been satisfied, so this spec re-grounds the design
against what actually shipped and hands it to plan writing.

Every number in §1 was measured against the working tree at `db1aad9` on
2026-08-02, not copied from the design document. Where the design document's
figures were wrong, the corrected figure is used and the discrepancy is noted.

## 1. Grounded baseline (measured 2026-08-02, HEAD db1aad9)

| Fact | Measured | Design doc claimed |
|---|---|---|
| Bats files in tree | **93** | 76 |
| Named `@test` cases | **2105** | 1,936 |
| Standalone shell suites (`test-*.sh`) | **43** | 39 |
| Total test files | **136** | 115 |
| Approved catalog `run_units` | **83** | 83 ✓ |
| — of which `runner: bats` | **74** | — |
| — of which `runner: declared` | **8** | — |
| — of which `runner: package` | **1** | — |
| Catalog `parallel.status: unknown` | **83 / 83** | "every one" ✓ |
| Catalog `behavior_claims: []` (empty) | **83 / 83** | not stated |
| Catalog `confidence: low` | **83 / 83** | not stated |
| Catalog `generated_at` | 2026-07-30T13:41:15Z | — |
| Bats files covered by catalog | **74 of 93** (19 uncovered) | not stated |
| Shell suites covered by catalog | **0 of 43** | "39 invisible" |

**Reading of this baseline.** The approved catalog covers **74 of 136 real test
files (54%)**, carries **zero** behavior claims, and knows **nothing** about
parallel safety for any unit. It has drifted 19 bats files behind the tree in
three days. This is stronger evidence for the design document's core thesis
than the figures it used, and it is the honest starting point.

## 2. What shipped since the design document was written

### 2.1 P069 — scheduler (v2.67.0, `status: done`)

Shipped: `aid-test-scheduler.sh`, `aid-run-gates.sh` scheduler dispatch with
exit-3/exit-11 escalation to a `--profile full` subprocess,
`execution-unit.schema.json` + membership verification, `concurrency_context`
on gate runtime baselines, `aid-select-tests.sh --emit-units`, a 3-stage
rollout gate (`sequential` → `observe_parallel` → `parallel`) requiring 3
qualifying divergence-evidence artifacts per stage, and a PM
quarantine-decision-record mechanism.

Explicitly **not** shipped, by standing PM decision: the real multi-hour
sequential+scheduled measurement campaign for this repository. The evidence
collector is unit-tested against synthetic fixtures only. **No real bundle
exists.** This is the same debt the design document's exit criterion 11 names.

### 2.2 P071 — parallel bats lane (v2.68.0, released; plan file still marked `draft`)

Shipped: `aid-bats-parallel-lane.sh` (three-bucket partition: parallel pool /
sequential / boundary), `defaults/config/bats-parallel-safe-allowlist.txt`
(**72 approved-safe bats files**), a new `required: false` `gate:bats_boundary`
for the 2 too-expensive boundary files, `aid-self-host-migrate-p071-gates.sh`,
`gate:plan_diff` timeout 120→300, and the `aid-plan-diff.sh` `overall_verdict`
vocabulary fix.

### 2.3 P070 — shell-suite discovery (`status: draft`, NEVER SHIPPED)

Confirmed unshipped: `scripts/lib/` contains exactly four adapters —
`bats`, `contract`, `declared-command`, `package-script`. There is **no `sh:`
adapter**, although `test-catalog.schema.json` already reserves the
`sh:<relative-path-without-extension>` naming convention. P070's second item
(disposable-clone `.aid-o/config/` copy precondition) is also unshipped.

**Decision for this spec: P070 is absorbed, not depended upon.** The design
document's Slice 5 item 19 said "fold or depend explicitly on the P070
shell-discovery work; do not silently assume it shipped." It did not ship, and
43 shell suites cannot be reconciled without it. Absorbing it removes a
cross-plan dependency on a draft that nobody owns.

## 3. THE CENTRAL RE-GROUNDING FINDING — two competing parallel-safety authorities

This did not exist when the design document was written and it changes the
shape of the work.

P071 shipped a **hand-maintained flat text file** as the operative
parallel-safety authority. `aid-bats-parallel-lane.sh` states in its own header
comment that the catalog's `parallel.status` field "is NEVER consulted as a
pool-eligibility signal (it is `unknown` for every run_unit today; that field
is not consulted by this allowlist at all)".

Meanwhile the allowlist's own provenance header records that the 72-file set
**was** independently verified twice: (1) P066's audit `audit-20260802-070629`
read all 83 bats files directly and confirmed the shared
`setup_test_evidence_dir`/`mktemp`-per-test isolation helper; (2) P071 Step 3
ran that exact 72-file set via `bats -j 4` twice for real — 1382 `@test` cases,
0 failures, `git status --short` empty both times.

**So the two kinds of evidence the design document's D3 demands were already
produced — and then written to a file with no schema, no provenance binding, no
expiry and no re-validation.** The durable, schema-bound protocol field still
says `unknown` for all 83 units.

Consequences that this plan must resolve:

1. **Evidence exists but is not durable.** A real source-read + repeated
   parallel pilot produced a result that the catalog cannot express. The
   feedback loop from audit evidence back to `parallel.status` is missing.
2. **The allowlist drifts silently.** A file on the list that is later edited
   to bind a fixed port, write a shared path or take a lock stays on the list.
   Nothing re-validates it. Nothing binds an entry to a content hash.
3. **Two authorities disagree by construction.** The catalog says `unknown`
   for 83 units; the allowlist says pool-safe for 72. Both are "approved". A
   consumer project inheriting this pattern has no way to know which wins.
4. **This is exactly the failure mode `AID-v3-principles.md` §1 names.** The
   catalog's `parallel.status` is currently a detector with no consumer — a
   field every audit populates and no execution path reads. Principle #1:
   *Detector without Enforcement is Decoration*.

The plan must therefore **reconcile these two surfaces into one authority with
provenance**, not merely add a third evidence producer alongside them.

## 4. Confirmed still-open defects

| Defect | Verified | Evidence |
|---|---|---|
| `audit_status` / consolidated decision schema | **absent everywhere** | no match in `plugins/` for `audit_status`; no `aid-test-audit-decision` schema |
| Cost root-cause profiler | absent | no such script |
| Source-aware resource-map builder | absent | no such script |
| Bounded disposable-clone pilot runner | absent as a capability | P071 did it by hand, once |
| Chat renderer | 5-part, in `lib/aid-test-audit-chat-summary.sh` | spec requires 6-part decision-first |
| `test-semantic-review.sh` reported as `0/0` | **still real** | script emits `=== Results: N passed, M failed ===`; `run-all-tests.sh:213` greps `^Results:` and expects `N/T passed` |
| Shell-suite discovery | absent | 4 adapters, none for `sh:` |
| Shard may emit zero findings for an assigned unit | current released contract | P066 shard contract |

## 5. Product outcome (unchanged in intent from the design document)

`/aid-audit-tests --mode full` becomes a decision-quality audit: a
deterministic, machine-readable decision artifact plus a human chat handoff
answering, in this order:

1. What should be done now?
2. What can be fixed, merged, split or removed — with named targets?
3. What can run concurrently now, after a small repair, or only after proof?
4. What must remain serial and why?
5. How long do tests take now, and what after each proposed change?
6. What has the audit not proved yet?

The output remains a **recommendation only**. It never edits a test, changes a
gate, approves a catalog mapping or activates P069 scheduling.

## 6. Requirements

### R1 — classification is evidence, not a final answer

`safe`/`constrained`/`exclusive`/`unknown` remain evidence labels, not a
sufficient result. A portfolio-wide `unknown`, or a material portion left
unknown, yields `audit_status: incomplete`, never `remediation_recommended`.

An individual `unknown` is valid only when its record names: the run unit, the
sources/resources inspected, the exact missing proof, and the smallest
permitted measurement or source inspection that would resolve it.

Template-dependent gates (commands containing `{base_commit}`, `{plan_path}`)
may remain `context_required`; they are never falsely tested in a synthetic
context and never promoted to a parallel lane from static prose.

### R2 — every recommendation carries an explicit evidence level

`measured` (completed comparable runs) / `estimated` (transparent assumptions)
/ `unknown` (no numerical benefit claimed). An audit must never imply that
splitting a file is faster because the file is long. It first diagnoses whether
time belongs to shared setup, teardown, retry/waiting, subprocesses, repeated
fixture creation, duplicate gate membership, or the tested behavior itself.

### R3 — parallel promotion requires two kinds of evidence, recorded durably

Promotion from `unknown`/`constrained` to a proposed parallel lane needs both:
(a) a concrete resource assessment for every included unit, and (b) a bounded,
repeatable parallel pilot in a disposable clone/worktree, compared against the
same membership and verdict run serially.

The pilot never runs two aggregate actions against the live checkout. It has a
declared worker count, command fingerprint, environment, resource namespace,
repeat count, deadline and receipts. Failure, mismatch or leaked state keeps
the units serial; it never silently retries until green.

**New, from §3:** the result of (a)+(b) MUST land in the catalog's own
`parallel` block with provenance — the evidence reference, the source content
hash it was verified against, and the audit id. An entry whose source file
hash no longer matches its recorded provenance reverts to `unknown` rather than
remaining silently trusted.

### R4 — one parallel-safety authority, not two

`aid-bats-parallel-lane.sh`'s allowlist and the catalog's `parallel.status`
must be reconciled into a single authority. The plan must either (i) migrate
the 72-file allowlist into provenance-bound catalog entries and make the lane
read the catalog, or (ii) keep the allowlist as the operative file but make it
a **generated, hash-bound artifact** derived from the catalog, never
hand-edited. The plan chooses one and states why; shipping both as
independently hand-maintained authorities is not an acceptable outcome.

Whichever is chosen, P071's existing 72-file evidence must be **preserved, not
re-earned** — it was really produced (1382 cases, twice, clean `git status`).
Discarding it and re-running the pilot from zero is waste; laundering it into a
schema field without recording that it came from P071 Step 3 is dishonest.

### R5 — no implicit scheduler authority

P069 must consume only a catalog mapping that was explicitly approved and,
where scheduling is requested, backed by current pilot evidence. A new audit
recommendation or a chat response cannot change `scheduler.mode`, change a gate
command, or remove a quarantine. P069's shipped 3-stage rollout gate is
unchanged by this plan unless it is explicitly re-grounded and amended.

### R6 — bounded diagnosis

Full mode has a user-supplied overall budget. Diagnostic profiling and pilots
reserve a bounded sub-budget. When it expires, the report says `incomplete` and
records completed evidence; it never converts time exhaustion into a confident
remediation claim.

### R7 — a full audit is a total portfolio decision, not a sparse findings list

In `full` mode every discovered `run_unit_id` MUST have exactly one terminal
disposition record, even when that disposition is `keep`. Silence cannot
distinguish "healthy and uniquely useful" from "never inspected".

Each disposition records at minimum:

- the behavior/invariant or historical regression the unit claims to protect;
- the concrete failure signal, and the cheapest falsification or mutation that
  would prove the test detects it;
- whether that signal is unique, overlaps named units, or remains unproved;
- layer fitness (`unit`, `contract`, `integration`, `e2e`) and whether the same
  signal can be preserved at a cheaper layer;
- one of `keep`, `fix`, `rewrite_unit`, `merge`, `split`, `remove`,
  `quarantine`, `keep_serial`, `parallelize`, or a bounded `measure` action;
- evidence/confidence plus the current measured cost or an honest lower bound.

Inventory count, assigned-unit count and terminal-disposition count MUST match
exactly. Missing, duplicate or silently dropped units make the audit
`incomplete`.

**Grounding note:** all 83 current catalog entries carry `behavior_claims: []`
and `confidence: low`. R7 is therefore a change from a measured 0% baseline,
not an incremental improvement.

### R8 — reduction and retained value are first-class outcomes

The audit must actively test the hypothesis that the portfolio is too large. It
groups tests by protected invariant/failure signal and names: duplicate or
overlapping tests that can be merged; expensive e2e cases rewritable as cheaper
unit/contract tests while retaining a small representative e2e set; tests for
removed/obsolete behavior or source-text implementation details; aggregate
gates executing work already covered by other gates; and genuinely
unique/security-critical tests that must remain.

A remove/merge/rewrite proposal requires a falsification check or mutation
showing which retained test still catches the claimed defect. A `keep` decision
must name its unique signal or explicitly admit that uniqueness is unproved.

### R9 — complete discovery

Bats, standalone shell suites, declared gates/package scripts and CI-only
suites must reconcile without double-counting. This requires the `sh:` adapter
absorbed from P070 (§2.3). A repository-wide audit claim is not permitted while
43 of 136 test files are structurally invisible.

The disposable-clone `.aid-o/config/` precondition (P070 item 1) is also
absorbed: a disposable-clone audit currently loses every declared-command gate
silently.

### R10 — whole-path proof

`/aid-audit-tests` → complete inventory (including shell suites) → one
disposition per unit → decision summary/remediation brief → explicit
catalog/mapping approval → P069 scheduler selection → real `aid-run-gates.sh`
dispatch → per-unit receipts → final gate verdict.

The proof runs from a fresh/disposable project using the released plugin and
the real generated configuration path. It must show that the configured mode
actually leaves `sequential`, that approved units run concurrently, unknown
units remain serial, and that no test executes twice through overlapping
`bats_all`, `bats_boundary`, aggregate, `plan_diff` or release surfaces.
Component unit tests or a synthetic scheduler fixture do not satisfy this.

## 7. Contract changes

### 7.1 Consolidated decision artifact

A versioned, strict schema for a *consolidated* decision artifact — not an
overloading of every specialist wave artifact with global conclusions:

```yaml
schema_version: aid-test-audit-decision-v1
audit_status: complete | incomplete
current_runtime:
  kind: measured | lower_bound | unknown
  duration_ms: integer | null
  scope: named catalog/run-unit membership
actions:
  - action: fix | merge | remove | split | parallelize | keep_serial | measure
    targets: [stable run_unit_id or gate id]
    priority: critical | high | medium | low
    reason: bounded human text
    evidence_refs: [receipt/path/id]
    impact:
      kind: measured | estimated | unknown
      before_ms: integer | null
      after_ms: integer | null
      assumptions: [stable, controlled strings]
parallelization:
  lanes:
    - lane_id: stable identifier
      disposition: proposed_parallel | keep_serial | blocked_pending_fix | context_required
      run_unit_ids: [stable ids]
      resource_basis: [controlled resource identifiers]
      evidence_refs: [refs]
  smallest_safe_pilot: structured command/reference and pass criteria
unresolved:
  - run_unit_id: stable id
    missing_proof: controlled reason
    next_measurement: named bounded operation
portfolio_coverage:
  inventory_count: integer
  assigned_count: integer
  disposition_count: integer
  missing_run_unit_ids: [stable ids]
  duplicate_run_unit_ids: [stable ids]
portfolio_change:
  current_run_units: integer
  proposed_run_units: integer
  keep: [stable ids]
  rewrite_unit: [stable ids]
  merge_groups: [[stable ids]]
  remove: [stable ids]
  runtime_before_ms: integer | null
  runtime_after_ms: integer | null
  impact_kind: measured | estimated | unknown
```

The schema rejects unknown fields, free-form absolute paths, secrets and
unbounded shell snippets. Human prose belongs in the rendered report and
evidence, not in a durable public-safe protocol field.

### 7.2 Outcome semantics

Keep the existing finding severities. Add `audit_status` **alongside**, not in
place of, the current verdict so existing consumers remain readable:

| Condition | Verdict | `audit_status` |
|---|---|---|
| Evidence supports a ranked remediation proposal | existing remediation verdict | `complete` |
| Portfolio healthy within requested scope | existing clean/measurement verdict | `complete` |
| Material cost/isolation question unresolved | no remediation-ready verdict | `incomplete` |
| Audit interrupted | existing interrupted state | `incomplete` |

CP1 and `--write-plan` must reject an `incomplete` decision artifact. This is
not a new generic gate; it applies only when an audit is represented as ready
to create a remediation plan.

### 7.3 Human renderer contract

Replace the capped generic `Reasons`-first handoff with a deterministic
decision-first renderer. Headings are localisable; the ordering is mandatory:

```text
What to do now
What to fix, merge, split or remove
What can run in parallel
What must remain serial
Test time: now and after the proposed work
What is not proved yet
Technical evidence
```

For `incomplete`, lead with the smallest bounded next diagnostic action; do not
tell the user merely to "create a remediation plan." If no deletion is
supported, say "No test is recommended for removal on current evidence."

## 8. Diagnostic design

### 8.1 Cost root-cause profiler

A runner-owned profiling operation for the highest-cost units selected by
existing measurement data. It must: run only allowlisted/discovered commands
through the existing job/receipt boundary; execute in a disposable clone or
fixture, never the live checkout; preserve stdout/stderr incrementally so a
slow run is observable before its deadline; use a runner-native,
version-grounded per-test timing capability where one exists (for Bats, ground
the installed version and its stable timing interface first — P071 already used
`bats --timing` for real, so ground against that, do not invent a flag);
otherwise use a fixture-tested adapter that attributes setup, test body and
teardown without parsing unstable presentation-only output; record a partial
profile honestly after timeout/cancellation; and emit a root-cause hypothesis
only with cited timing/source evidence.

Output distinguishes: setup/teardown accumulation, subprocess or git cost,
retry/backoff, explicit wait/sleep, fixture-history growth, duplicate
membership, and test-body cost. It may recommend `measure` only when it names
which one is undecidable and the next bounded probe.

### 8.2 Resource-map builder

Replace grep-only parallel safety with a source-aware resource map. Each run
unit is inspected for declared and inferred use of: temporary/fixed paths and
working directories; git repository/worktree mutations; `.aid-o` state and
locks; ports, sockets and network services; process groups/child processes;
caches; and database/container/external-service state.

The result records both the resource and its namespace (`per-test`, `per-run`,
`shared`, `unknown`). Existing isolated helpers — specifically the
`setup_test_evidence_dir`/`mktemp`-per-test helper P066's audit already
confirmed — count as positive evidence only after their callers and exceptional
files have been read. A grep hit alone cannot label a resource shared; this
directly prevents the false-lock-positive class seen in the first P066 audit.

### 8.3 Parallel pilot

The audit selects a small representative lane only after the resource map. The
pilot records serial baseline, parallel membership, worker count, fingerprints,
result sets, duration and post-run leak checks. Promotion requires all of: same
selected membership; same aggregate verdict and no new flaky failure; no
resource leak or mutation outside the disposable root; repeated success per the
requested `--repeat` policy; and a meaningful measured benefit, or an explicit
conclusion that parallelism is safe but not worthwhile.

The pilot produces a **proposal**, not an approved scheduler configuration.

## 9. Delivery slices

Slice numbering in the design document collided (three separate items numbered
6, two numbered 10). Items below are numbered continuously and uniquely.

### Slice 1 — decision contract and fail-closed readiness

1. Ground released P066 artifacts and P069's final public catalog contract.
   Record every consumer of audit verdicts and `--write-plan`.
2. Add the strict consolidated decision schema, deterministic writer/reader and
   public-safe validation.
3. Add `audit_status: incomplete` semantics; block `--write-plan` when the
   artifact cannot support a decision.
4. Update the parallel-safety specialist instruction: classification is
   evidence; it must inspect resources and propose lanes/serial exceptions or a
   specific bounded proof.
5. Update the adversarial specialist instruction to challenge resource scope,
   claimed runner availability, false "transaction isolation means safe"
   reasoning, membership mismatch and invented savings.
6. Change shard output from optional findings to a mandatory terminal
   disposition per assigned `run_unit_id`; add deterministic reconciliation of
   inventory, shard assignment and disposition counts.
7. Require behavior claim, failure signal, uniqueness/overlap, layer fitness and
   falsification evidence for every keep/remove/merge/rewrite decision.

**Acceptance:** fixtures prove that a portfolio-wide `unknown`, a missing
parallel decision, an unmeasured claimed saving and an incomplete result cannot
be handed to `/aid-plan write` as remediation-ready. A shard that emits zero
records, drops one assigned unit, duplicates a unit, or marks every unit
unknown fails reconciliation rather than producing a sparse green report.

### Slice 2 — complete discovery (absorbed P070)

8. Build the `sh:` shell-suite discovery adapter against the naming convention
   `test-catalog.schema.json` already reserves. All 43 standalone suites become
   real `run_units`.
9. Reconcile bats/shell/declared/package discovery without double-counting; the
   19 bats files currently missing from the catalog must appear.
10. Fix the disposable-clone `.aid-o/config/` precondition so a disposable-clone
    audit no longer silently loses every declared-command gate.
11. Normalise the declared result grammar used by the aggregate runner, or
    explicitly support every retained grammar with a tested adapter. Folds the
    verified `test-semantic-review.sh` defect: it emits
    `=== Results: N passed, M failed ===` while `run-all-tests.sh:213` accepts
    only `Results: N/T passed, M failed`, so the suite reports as `0/0`.
    Accurate portfolio cost and membership evidence cannot be built on a
    silently uncounted successful suite.

**Acceptance:** a repository-wide inventory reconciles to the real measured
file count with no double-counting; the aggregate result collector reports the
semantic-review fixture's real count, never `0/0`.

### Slice 3 — cost diagnosis

12. Ground runner timing capabilities (start from P071's real `bats --timing`
    usage) and select the smallest stable adapter design; add no generic shell
    parsing.
13. Build the bounded diagnostic profiler with streamed evidence and
    complete/partial receipts.
14. Teach the consolidator to turn profiles into named root-cause actions,
    retaining uncertainty where evidence is incomplete.
15. Dogfood against the actual AID high-cost units. Diagnose the progressively
    expensive `test-aid-plan-final-boundary.bats` AC5 path before proposing
    split or parallel work for it.

**Acceptance:** a timed-out file produces an honest lower bound and a
root-cause-specific next probe, not a terminal generic `measure` finding.

### Slice 4 — resource evidence, pilot, and authority reconciliation

16. Build the source-aware resource-map builder and a stable resource-namespace
    vocabulary.
17. Build the bounded disposable-clone parallel-pilot runner and its receipts.
18. **Reconcile the two parallel-safety authorities per R4.** Choose migration
    or generation, state why, and preserve P071's real 72-file evidence with
    explicit provenance rather than re-earning or laundering it.
19. Add provenance binding per R3: an entry whose source content hash no longer
    matches its recorded evidence reverts to `unknown`.
20. Consolidate pilots into named proposed lanes, serial exceptions and blocked
    prerequisites. Do not alter P069 scheduler mode or catalog approval.
21. Dogfood a representative lane, reproducing comparable serial and parallel
    evidence. Do not claim whole-suite safety from a sample.

**Acceptance:** a known per-test-isolated lane becomes `proposed_parallel` only
with repeatable pilot proof; a fixed-path/port/worktree conflict remains
`keep_serial` or `blocked_pending_fix` with its exact reason. Editing a
pooled file's source so it binds a fixed port demonstrably reverts it to
`unknown` instead of leaving it silently pooled.

### Slice 5 — human decision handoff and documentation

22. Replace the final chat renderer with the mandatory six-part decision summary
    and retain raw evidence below it.
23. Update `/aid-audit-tests` help, agent card and prompt templates so the
    normal expected result is clear before dispatch.
24. Add end-to-end fixtures for complete, incomplete, no-removal, serial-only
    and proven-parallel reports.
25. Update the enforcement registry for the new `--write-plan` incomplete
    refusal, for pilot-promotion enforcement and for provenance reversion.
    Document each exact surface and recovery behavior; a detector with no
    consumer is not acceptable.
26. Render exact named `keep`/`rewrite`/`merge`/`remove`/parallel/serial sets
    plus current and proposed portfolio size and runtime. Never collapse this to
    a five-item severity list.

**Acceptance:** the rendered output gives an ordinary-language recommended next
action without requiring the user to remember a command. A five-item raw
technical list cannot be rendered as the only final handoff.

### Slice 6 — whole-path wiring and outcome proof

27. Run one real full audit and approve its catalog/mapping through the public
    sanctioned flow.
28. Feed that exact approved artifact to the released P069 scheduler through
    generated `execution.yaml` and `aid-run-gates.sh`, not a direct scheduler
    invocation.
29. Capture an execution ledger keyed by candidate SHA, command fingerprint and
    `run_unit_id`; fail if the same unit executes twice through overlapping gate
    surfaces (`bats_all`, `bats_boundary`, aggregate, `plan_diff`, release).
30. Record before/after wall-clock and membership for the complete release
    campaign. This is the campaign P069 deferred; it is not satisfied by
    synthetic fixtures.

**Acceptance:** in a disposable fresh project the ordinary user command produces
a complete decision, a PM-approved mapping activates real scheduled execution,
unknown units stay serial, all verdicts match the sequential baseline, no unit
runs twice, and the measured end-to-end wall-clock is reported.

## 10. Whole-system safety constraints

- The audit remains on-demand. It never runs after every EPIC, release or
  scheduler invocation.
- No test is deleted, quarantined, split or parallelised automatically.
- Existing `static`, `measure`, `full`, resume, command-allowlist and job-receipt
  guarantees remain covered by regression tests.
- Diagnostic runs and pilots cannot share a live checkout with an active gate
  run; refuse or require a disposable root.
- `dispatch.max_parallel` for code-writing agents is untouched. Audit shard
  concurrency and test worker count remain separate, explicitly named settings.
- No full aggregate run follows every slice. Use targeted tests per slice; run
  an aggregate candidate once, on a frozen final revision, under the
  then-current quarantine policy.
- Before any schema extension P069 consumes, re-ground P069 against the final
  schema. If backwards compatibility cannot be proved, hold the change for a
  separate P069 amendment rather than silently changing scheduler meaning.
- Plugin-maintenance obligations apply (project CLAUDE.md): both CHANGELOGs
  identical, all 8 version locations in sync, enforcement-registry rows for
  every new detection capability, `Last Updated` on revised skills, skill and
  command lint clean.

## 11. Exit criteria

1. `/aid-audit-tests` cannot present a materially unknown portfolio as a
   remediation-ready audit.
2. Every remediation-ready audit has a strict decision artifact and a
   decision-first human summary.
3. Cost findings identify a grounded cause or an explicitly bounded next proof,
   not merely a file-level timeout.
4. Parallel recommendations name lanes, serial exceptions and evidence; they
   never activate scheduling.
5. Exactly one parallel-safety authority exists, with provenance, and P071's
   real 72-file evidence is preserved within it rather than discarded or
   laundered.
6. AID dogfood demonstrates both an honest incomplete result and a proven
   parallel pilot, without claiming either generalises beyond its evidence.
7. P069's approved scheduler contract is unchanged, or explicitly re-grounded
   and amended.
8. Documentation, prompts, schemas, renderer, enforcement registry and tests all
   state the same authority boundary.
9. Every discovered run unit has exactly one terminal disposition; inventory,
   assignment and disposition counts reconcile, including the 43 shell suites.
10. The report names concrete keep/rewrite/merge/remove candidates and protects
    every coverage-reducing proposal with falsification/mutation evidence.
11. A fresh-project E2E proves the approved audit result is consumed by P069
    through the real gate runner, not merely written to files.
12. The final campaign ledger proves no test unit ran twice and reports actual
    before/after wall-clock. **Until this passes, the combined P066/P069/P071
    line of work must not be described as delivering test-suite acceleration.**

## 12. Explicit non-goals

- The broader `/aid-help`/`init`/`setup` UX work remains a separate plan.
- No change to `dispatch.max_parallel` or code-writing agent concurrency.
- No automatic remediation of any kind.
- No new consumer-project migration beyond what catalog schema evolution
  strictly requires.
