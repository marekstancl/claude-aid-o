# Test-Audit Decision Quality and Diagnostic Depth

**Status:** proposed implementation plan; write-only design work, no production
implementation authorized by this document yet.
**Prepared:** 2026-08-02.
**Base:** `main` at v2.66.2 (`281f87f`).
**Relationship:** follow-up to released P066. It must not modify the active
P069 scheduler branch. P069 may consume only catalog entries that remain
backward-compatible and explicitly approved after this work.

## 1. Why this follow-up exists

P066 correctly found that AID's test portfolio is expensive, but its original
contract could finish with an output such as “87 units are `unknown`” followed
by a generic `remediation recommended` verdict. That is an inventory of
uncertainty, not an audit that helps a project owner decide what to do.

The completed deep dogfood audit shows the intended standard instead:

- name the concrete bottleneck, not merely a timed-out file;
- distinguish a test/gate defect, stale configuration, duplicate work and an
  intentional serial lane;
- prove a parallel candidate by a bounded run in a disposable clone;
- state when parallelism cannot improve total wall time because one serial
  bottleneck dominates; and
- show current time, measured lower bound and any future estimate honestly.

Example evidence from the AID dogfood audit is deliberately treated as a
*reference case*, not as a universal result for consumer projects:

- `test-aid-plan-final-boundary.bats` ran for more than one hour without
  completing and became progressively slower in its AC5 lifecycle section;
- `test-aid-plan-release-boundary.bats` completed in about 42.9 minutes;
- a representative ten-file Bats pilot passed 147/147 serially and with
  `-j4`, reducing 147 seconds to 44.79 seconds in an isolated clone; and
- two boundary suites remain dedicated lanes until their own root causes are
  fixed. Parallelising other work does not shorten a wall clock dominated by
  either one.

The standard must be distributable: an audit may reach “no evidence supports
removal” or “parallelism is not yet proven” for another project. It must still
explain why and provide the smallest bounded way to settle the question.

## 2. Product outcome

`/aid-audit-tests --mode full` becomes a decision-quality audit, not an
unbounded investigation and not an automatic change mechanism.

It produces a deterministic, machine-readable decision summary and a human
chat handoff answering these questions in this order:

1. What should be done now?
2. What can be fixed, merged, split or removed — with named targets?
3. What can run concurrently now, after a small repair, or only after proof?
4. What must remain serial and why?
5. How long do tests take now, and what after each proposed change?
6. What has the audit not proved yet?

The output is a recommendation only. It never edits a test, changes a gate,
approves a catalog mapping or activates P069 scheduling. A user can accept its
recommended next action in ordinary language; a later `/aid-plan` invocation
creates a normal, separately reviewed remediation plan.

## 3. Non-negotiable decisions

### D1 — classification is evidence, not a final answer

`safe`, `constrained`, `exclusive` and `unknown` remain useful evidence
labels. They are not a sufficient final result. A portfolio-wide `unknown`
outcome, or a material portion of the portfolio left unknown, yields
`audit_status: incomplete`, not `remediation_recommended`.

An individual `unknown` is valid only when its report records:

- the named run unit;
- sources/resources inspected;
- the exact missing proof; and
- the smallest permitted measurement or source inspection needed to resolve
  it.

Template-dependent gates, for example commands containing `{base_commit}` or
`{plan_path}`, may remain `context_required`; they are not falsely tested in a
synthetic context and are never promoted to a parallel lane from static prose.

### D2 — recommendations have an explicit evidence level

Every proposed action carries one of:

- `measured` — backed by completed comparable runs;
- `estimated` — a transparent estimate with its assumptions; or
- `unknown` — no numerical benefit claimed.

An audit must never imply that splitting a file is faster merely because the
file is long. It first diagnoses whether time belongs to shared setup,
teardown, retry/waiting, subprocesses, repeated fixture creation, duplicate
gate membership or the tested behavior itself.

### D3 — parallel promotion requires two kinds of evidence

Static source inspection builds a resource map; it does not by itself prove
cross-process safety. Promotion from `unknown`/`constrained` to a proposed
parallel lane needs:

1. a concrete resource assessment for every included unit; and
2. a bounded, repeatable parallel pilot in a disposable clone/worktree,
   compared with the same membership and verdict run serially.

The pilot never runs two aggregate actions against the live checkout. It has a
declared worker count, command fingerprint, environment, resource namespace,
repeat count, deadline and receipts. Failure, mismatch or leaked state keeps
the units serial; it does not silently retry until green.

### D4 — no implicit scheduler authority

P069 must consume only a catalog mapping that was explicitly approved and,
where scheduling is requested, backed by current pilot evidence. A new audit
recommendation or a chat response cannot change `scheduler.mode`, change a
gate command or remove a quarantine.

### D5 — bounded diagnosis

Full mode has a user-supplied overall budget. Diagnostic profiling and pilots
reserve a bounded sub-budget. When it expires, the report says `incomplete`
and records completed evidence; it does not convert time exhaustion into a
confident remediation claim.

### D6 — a full audit is a total portfolio decision, not a sparse findings list

The released P066 shard contract permits an auditor to emit zero findings for
an assigned unit. That is acceptable for a findings collector but not for a
full portfolio audit: silence cannot distinguish "healthy and uniquely useful"
from "never inspected". In `full` mode every discovered `run_unit_id` MUST have
exactly one terminal disposition record, even when the disposition is `keep`.

The disposition records, at minimum:

- the behavior/invariant or historical regression the unit claims to protect;
- the concrete failure signal and the cheapest falsification or mutation that
  would prove the test detects it;
- whether that signal is unique, overlaps named units, or remains unproved;
- layer fitness (`unit`, `contract`, `integration`, `e2e`) and whether the same
  signal can be preserved at a cheaper layer;
- `keep`, `fix`, `rewrite_unit`, `merge`, `split`, `remove`, `quarantine`,
  `keep_serial`, `parallelize` or a bounded `measure` action; and
- evidence/confidence plus the current measured cost or honest lower bound.

The inventory count, assigned-unit count and terminal-disposition count MUST
match exactly. Missing, duplicate or silently dropped units make the audit
`incomplete`. A portfolio-wide `unknown`, or 83 `unknown` units accompanied by
only a handful of cost findings, can never be called a completed audit.

### D7 — reduction and retained value are first-class outcomes

The audit must actively test the hypothesis that the portfolio is too large.
It cannot assume every historical regression deserves another permanent full
workflow test. It groups tests by protected invariant/failure signal and names:

- duplicate or overlapping tests that can be merged;
- expensive end-to-end cases that can be rewritten as cheaper unit/contract
  tests while retaining a small representative end-to-end set;
- tests for removed/obsolete behavior or source-text implementation details;
- aggregate gates that execute work already covered by other gates; and
- genuinely unique/security-critical tests that must remain.

A remove/merge/rewrite proposal requires a falsification check or mutation
showing which retained test still catches the claimed defect. Conversely, a
`keep` decision must name its unique signal or explicitly admit that uniqueness
is unproved. The final decision artifact reports portfolio size and runtime
before and after the proposed work, with every saving labelled measured,
estimated or unknown.

### D8 — capability, scheduler and gate wiring must be proven as one path

P066 producing a catalog, P069 shipping a scheduler and a later remediation
shipping a runner are not success independently. The follow-up must prove the
real installed path from end to end:

`/aid-audit-tests` -> complete inventory (including standalone shell suites) ->
one disposition per unit -> decision summary/remediation brief -> explicit
catalog/mapping approval -> P069 scheduler selection -> real
`aid-run-gates.sh` dispatch -> per-unit receipts -> final gate verdict.

The proof runs from a fresh/disposable project using the released plugin and
the real generated configuration path. It must show that the configured mode
actually leaves `sequential`, that approved units run concurrently, unknown
units remain serial, and no test is executed twice through overlapping
`bats_all`, aggregate, `plan_diff` or release surfaces. Component unit tests or
a synthetic scheduler fixture do not satisfy this requirement.

The self-host grounding baseline must be re-measured at implementation time.
As of 2026-08-02 the working tree contains 76 Bats files with 1,936 named Bats
cases plus 39 standalone shell suites (115 test files total), while the
approved catalog still exposes only 83 run units and marks every one of them
`parallel.status: unknown`. That is direct evidence that discovery,
decision-quality audit and scheduling are not yet connected as a usable whole.

## 4. Required contract changes

Ground exact file names and existing schema versions before implementation;
the current implementation includes the dedicated test-portfolio analyst,
parallel-safety prompt, wave-artifact schema, consolidator and deterministic
chat summary renderer.

### 4.1 Consolidated decision artifact

Introduce a versioned, strict schema for a *consolidated* decision artifact.
Do not overload every specialist wave artifact with global conclusions. At a
minimum it contains:

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

### 4.2 Outcome semantics

Keep the existing finding severities. Add `audit_status` alongside, not in
place of, the current verdict so existing consumers remain readable:

| Condition | Verdict | `audit_status` |
|---|---|---|
| Evidence supports a ranked remediation proposal | existing remediation verdict | `complete` |
| Portfolio is healthy within the requested scope | existing clean/measurement verdict | `complete` |
| Material cost/isolation question remains unresolved | no remediation-ready verdict | `incomplete` |
| Audit interrupted | existing interrupted state | `incomplete` |

CP1 and `--write-plan` must reject an `incomplete` decision artifact. This is
not a new generic gate: it applies only when an audit is being represented as
ready to create a remediation plan.

### 4.3 Human renderer contract

Replace the capped generic `Reasons`-first handoff with a deterministic
decision-first renderer. The exact headings are localisable, but the ordering
is mandatory:

```text
What to do now
What to fix, merge, split or remove
What can run in parallel
What must remain serial
Test time: now and after the proposed work
What is not proved yet
Technical evidence
```

For `incomplete`, lead with the smallest bounded next diagnostic action; do
not tell the user merely to “create a remediation plan.” If no deletion is
supported, say “No test is recommended for removal on current evidence.”

## 5. Diagnostic design

### 5.1 Cost root-cause profiler

Add a runner-owned profiling operation for the highest-cost units selected by
the existing measurement data. It must:

- run only allowlisted/discovered commands through the existing job/receipt
  boundary;
- execute in a disposable clone or fixture, never the live checkout;
- preserve stdout/stderr incrementally in an evidence file so a slow run is
  observable before its deadline;
- use a runner-native, version-grounded per-test timing capability where one
  exists; otherwise use a tested wrapper that attributes setup, test body and
  teardown without parsing unstable presentation-only output;
- record a partial profile honestly after timeout/cancellation; and
- emit a root-cause hypothesis only with cited timing/source evidence.

For Bats, grounding must first establish the installed Bats version and its
stable timing interface. Do not invent a `bats` flag or scrape undocumented
terminal formatting. A missing native facility is a reason to build a small,
fixture-tested Bats adapter rather than a brittle generic parser.

The profiler's output distinguishes: setup/teardown accumulation, subprocess
or git cost, retry/backoff, explicit wait/sleep, fixture-history growth,
duplicate membership and test-body cost. It may recommend `measure` only when
it names which one is undecidable and the next bounded probe.

### 5.2 Resource-map builder

Replace grep-only parallel safety with a source-aware resource map. Each run
unit is inspected for declared and inferred use of:

- temporary/fixed paths and working directories;
- git repository/worktree mutations;
- `.aid-o` state and locks;
- ports, sockets and network services;
- process groups/child processes;
- caches; and
- database/container/external-service state.

The result records both the resource and its namespace (`per-test`,
`per-run`, `shared`, `unknown`). Existing isolated helpers, such as a per-test
`mktemp` + own git repository helper, count as positive evidence only after
their callers and exceptional files have been read. A grep hit alone cannot
label a resource shared; this directly prevents the false-lock-positive class
seen in the first P066 audit.

### 5.3 Parallel pilot

The audit selects a small representative lane only after the resource map.
The pilot records serial baseline, parallel membership, worker count,
fingerprints, result sets, duration and post-run leak checks. Promotion
requires all of:

- same selected membership;
- same aggregate verdict and no new flaky failure;
- no resource leak or mutation outside the disposable root;
- repeated success according to the requested `--repeat` policy; and
- a meaningful measured benefit, or an explicit conclusion that parallelism
  is safe but not worthwhile.

The pilot produces a **proposal**, not an approved scheduler configuration.

## 6. Delivery slices

### Slice 1 — decision contract and fail-closed readiness

1. Ground released P066 artifacts and the final P069 public catalog contract.
   Record every consumer of audit verdicts and `--write-plan`.
2. Add the strict consolidated decision schema, deterministic writer/reader
   and public-safe validation.
3. Add `audit_status: incomplete` semantics and block `--write-plan` when the
   artifact cannot support a decision.
4. Update the parallel-safety specialist instruction: classification is
   evidence; it must inspect resources and propose lanes/serial exceptions or
   a specific bounded proof.
5. Update the adversarial specialist instruction to challenge resource scope,
   claimed runner availability, false “transaction isolation means safe”
   reasoning, membership mismatch and invented savings.
6. Change shard output from optional findings to a mandatory terminal
   disposition for every assigned `run_unit_id`; add deterministic reconciliation
   of inventory, shard assignment and disposition counts.
7. Require behavior claim, failure signal, uniqueness/overlap, layer fitness and
   falsification evidence for every keep/remove/merge/rewrite decision.

**Acceptance:** fixtures prove that a portfolio-wide `unknown`, a missing
parallel decision, an unmeasured claimed saving and an incomplete result cannot
be handed to `/aid-plan write` as a remediation-ready audit. A shard that emits
zero records, drops one assigned unit, duplicates a unit or marks every unit
unknown fails reconciliation rather than producing a sparse green report.

### Slice 2 — cost diagnosis

6. Ground runner timing capabilities and select the smallest stable adapter
   design; add no generic shell parsing.
7. Build the bounded diagnostic profiler with streamed evidence and complete/
   partial receipts.
8. Teach the consolidator to turn profiles into named root-cause actions,
   retaining uncertainty where evidence is incomplete.
9. Dogfood against the actual AID high-cost Bats units. Diagnose the
   progressively expensive `test-aid-plan-final-boundary.bats` AC5 path before
   proposing split/parallel work for it.
10. Normalise the declared result grammar used by the aggregate runner, or
    explicitly support every retained grammar with a tested adapter. This folds
    the verified `test-semantic-review.sh` defect into this work: it emits
    `=== Results: N passed, M failed ===`, while `run-all-tests.sh` currently
    accepts only `Results: N/T passed, M failed` and consequently reports the
    suite as `0/0`. Accurate portfolio cost and membership evidence cannot be
    built on a silently uncounted successful suite.

**Acceptance:** a timed-out file produces an honest lower bound and a
root-cause-specific next probe, not a terminal generic `measure` finding.
The aggregate result collector reports the semantic-review fixture's real
count, never `0/0`.

### Slice 3 — resource evidence and parallel pilot

10. Build the source-aware resource-map builder and stable resource namespace
   vocabulary.
11. Build the bounded disposable-clone parallel-pilot runner and receipts.
12. Consolidate pilots into named proposed lanes, serial exceptions and blocked
   prerequisites. Do not alter P069 scheduler mode or catalog approval.
13. Dogfood a representative AID Bats lane, reproducing comparable serial and
   parallel evidence. Do not claim whole-suite safety from a sample.

**Acceptance:** a known per-test isolated lane can become
`proposed_parallel` only with repeatable pilot proof; a fixed-path/port/
worktree conflict remains `keep_serial` or `blocked_pending_fix` with its exact
reason.

### Slice 4 — human decision handoff and documentation

14. Replace the final chat renderer with the mandatory six-part decision
summary and retain raw evidence below it.
15. Update `/aid-audit-tests` help, agent card and prompt templates so the
normal expected result is clear before dispatch.
16. Add end-to-end fixtures for complete, incomplete, no-removal, serial-only
and proven-parallel reports.
17. Update enforcement registry for the new `--write-plan` incomplete refusal
and for any pilot-promotion enforcement. Document its exact surface and
recovery behavior; a detector with no consumer is not acceptable.
18. Render exact named `keep`, `rewrite`, `merge`, `remove`, parallel and serial
sets plus current/proposed portfolio size and runtime. Never collapse this to
a five-item severity list.

**Acceptance:** the rendered output gives an ordinary-language recommended
next action without requiring the user to remember a command. A five-item raw
technical list cannot be rendered as the only final handoff.

### Slice 5 — whole-path wiring and outcome proof

19. Complete discovery before claiming a repository-wide audit: Bats,
    standalone shell suites, declared gates/package scripts and CI-only suites
    must reconcile without double-counting. Fold or depend explicitly on the
    P070 shell-discovery work; do not silently assume it shipped.
20. Run one real full audit and approve its catalog/mapping through the public
    sanctioned flow.
21. Feed that exact approved artifact to the released P069 scheduler through
    generated `execution.yaml` and `aid-run-gates.sh`, not a direct scheduler
    invocation.
22. Capture an execution ledger keyed by candidate SHA, command fingerprint and
    `run_unit_id`; fail if the same unit is executed twice by overlapping gate
    surfaces.
23. Record before/after wall-clock and membership for the complete release
    campaign. The implementation is not successful merely because individual
    scripts and schemas pass their own tests.

**Acceptance:** in a disposable fresh project the ordinary user command
produces a complete decision, a PM-approved mapping activates real scheduled
execution, unknown units stay serial, all verdicts match the sequential
baseline, no unit runs twice and the measured end-to-end wall-clock is reported.

## 7. Whole-system safety checks

- The audit remains on-demand. It never runs after every EPIC, release or
  scheduler invocation.
- No test is deleted, quarantined, split or parallelised automatically.
- Existing `static`, `measure`, `full`, resume, command allowlist and job
  receipt guarantees remain covered by regression tests.
- Diagnostic runs and pilots cannot share a live checkout with an active gate
  run; refuse or require a disposable root.
- `dispatch.max_parallel` for code-writing agents is untouched. Audit shard
  concurrency and test worker count are separate, explicitly named settings.
- No full aggregate `bats_all` run follows every slice. Use targeted tests per
  slice; run an aggregate candidate only once, on a frozen final revision and
  under the then-current quarantine policy.
- Before any schema extension P069 consumes, re-ground P069 against the final
  schema. If backwards compatibility cannot be proved, hold the change for a
  separate P069 amendment rather than silently changing scheduler meaning.

## 8. Exit criteria

This follow-up is ready to release only when all are true:

1. `/aid-audit-tests` cannot present a materially unknown portfolio as a
   remediation-ready audit.
2. Every remediation-ready audit has a strict decision artifact and a
   decision-first human summary.
3. Cost findings identify a grounded cause or explicitly bounded next proof,
   not merely a file-level timeout.
4. Parallel recommendations name lanes, serial exceptions and evidence; they
   never activate scheduling.
5. AID dogfood demonstrates both an honest incomplete result and a proven
   parallel pilot, without claiming that either generalises beyond its evidence.
6. P069's approved scheduler contract is unchanged or has been explicitly
   re-grounded and amended.
7. Documentation, prompts, schemas, renderer, enforcement registry and tests
   all state the same authority boundary.
8. Every discovered run unit has exactly one terminal disposition; inventory,
   assignment and disposition counts reconcile, including standalone shell
   suites.
9. The report names concrete keep/rewrite/merge/remove candidates and protects
   every coverage-reducing proposal with falsification/mutation evidence.
10. A fresh-project E2E proves the approved audit result is consumed by P069
    through the real gate runner, not merely written to files.
11. The final campaign ledger proves no test unit ran twice and reports actual
    before/after wall-clock. Until this passes, the combined P066/P069 follow-up
    must not be described as delivering test-suite acceleration.

## 9. Sequencing

Planning/grounding may happen now in an isolated documentation worktree. Do
not implement against P069's active branch. Once P069 is merged or frozen,
re-ground the narrow P066↔P069 contract, convert this document into the
executable plan, and implement it as a dedicated maintenance stream. The
broader `/aid-help`/`init`/`setup` UX work remains a separate plan derived from
the interim note; it is intentionally not hidden inside this test-audit work.
