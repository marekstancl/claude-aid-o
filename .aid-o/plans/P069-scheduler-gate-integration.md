---
id: P069
type: regular
status: done
created: 2026-07-28
author: PM + AI
lifecycle_strict: true
depends_on_plans: [P066]
risk: high
---

# Plan: Test Scheduler and Real Gate-Runner Integration (P069)

## Plan Type

`regular` — new distributable AID plugin capability, directly extending P066's already-shipped
catalog/config contract. `risk: high`: this plan modifies `aid-run-gates.sh` (the FSM-adjacent gate
execution path) and `aid-select-tests.sh`'s execution behavior, and changes how a consumer
project's real `execution.yaml` (generated via `compose_execution_yaml`) can dispatch tests — this
is a genuine, not merely adjacent, match to `review-checkpoint-contracts.md`'s FSM/gate-config
high-risk pattern.

## Context

**This is the second half of a split.** The original monolithic P066 draft bundled a test-portfolio
auditor with a parallel scheduler in one 28-step plan. Three independent Codex C0 plan reviews
(2026-07-28) found, with escalating severity, that the scheduler/integration half never actually
wired into `aid-run-gates.sh` or the real `/aid-init` config-generation path
(`compose_execution_yaml` + `defaults/execution-stacks/*.yaml`, verified this session — **not**
`plugins/aid-orchestrator/defaults/execution.yaml`, which the original draft mistakenly targeted
and which is never copied into a consumer project). PM decision: split, ship the audit-only half as
P066, and scope this plan to build only what actually makes tests schedulable and gate-runner-
integrated for real, against P066's already-stable, already-CP1-reviewed catalog/config contract.

This plan's central obligation, stated by the PM verbatim: its main E2E acceptance criterion must
prove the REAL path — **configured profile → gate runner → selected execution units → scheduler →
per-unit receipts → the same aggregated verdict** — never merely a config file, documentation, or a
registry row standing in for that path.

## Goal

Ship an opt-in, resource-aware, deterministic test scheduler that a consumer project's real gate
runner can dispatch through — reusing P066's catalog (`parallel.status`/`isolation` findings) and
`aid-job.sh` (process-group/deadline/receipt semantics), defaulting to `sequential` (today's exact
behavior) everywhere until a project explicitly opts in, with a proven, mechanically-checked
sequential-vs-scheduled divergence gate before any promotion beyond `sequential`.

## Scope

**In scope:**
- `aid-job.sh`-based, formally schema-defined, reusable "execution unit" abstraction (distinct from
  P066's own one-off, sequential-only measurement runner).
- A deterministic batch scheduler consuming P066's catalog `parallel.status`/`isolation` fields.
- Refactoring `aid-select-tests.sh` so it can **emit a selected set as execution units** for the
  scheduler to run, instead of always running the selection directly inline (its current
  behavior, preserved as the default when no scheduler is configured).
- Real modification of `aid-run-gates.sh` to detect a scheduler-eligible gate group and dispatch it
  through the scheduler instead of (or in addition to) its current one-gate-at-a-time loop.
- Real modification of the config-generation path a consumer project actually uses:
  `defaults/execution-stacks/*.yaml` + `compose_execution_yaml`
  (`scripts/lib/aid-init-execution-yaml.sh:293`) — not the plugin's own dogfood-only
  `defaults/execution.yaml`.
- An explicit, non-invasive upgrade command for a project whose `execution.yaml` ALREADY exists
  (the common case — `/aid-init` never rewrites an existing file) — sharing one renderer with
  fresh generation, never a second, divergent implementation.
- `sequential` → `observe_parallel` → `parallel` rollout, gated by a mechanically-checked
  membership/verdict divergence comparison.
- The actual, evidence-backed remediation of this repository's own `bats_all`
  quarantine — the first real consumer of everything this plan builds. `plan_diff` has no
  `quarantine:` block and a different (timeout-architecture, not scheduling) root cause — it is
  explicitly out of this plan's scope (Step 15).

**Out of scope:**
- Anything P066 already owns (catalog schema, adapters, `/aid-audit-tests` command, chat handoff,
  catalog approval boundary) — this plan consumes those as a stable, already-shipped dependency
  (`depends_on_plans: [P066]`), never redefines them. **Narrowed explicitly after a real C0
  authority_runtime_matrix-lens finding (CP1-deep re-run) found this line in tension with Step
  11's own, deliberate modification of `aid-test-catalog-approve.sh`**: "never redefines" means
  this plan never changes what `mapping_approval.status: approved` MEANS, never changes P066's
  approval schema, and never bypasses P066's own catalog/mapping-confirmation gates — it does NOT
  mean this plan cannot add a strictly additive pre-approval check (Step 11's zero-gap
  re-verification hook) on top of that unchanged boundary. Step 11 itself now states this
  reconciliation explicitly, matching the pattern already used for the `resource_locks` (Step 1)
  and `scheduler.mode` (Step 13) authority tensions elsewhere in this plan.
- Removing the `bats_all` quarantine block itself — a PM action, taken only after
  reviewing this plan's own remediation evidence (Constraint 9).

## Approach

### Option A: Build directly on P066's shipped catalog/config, with the real integration points
grounded against `aid-run-gates.sh`/`compose_execution_yaml` from the start (Recommended)

**Pros:** avoids the exact mistake three C0 rounds found in the monolithic draft — this plan is
written against real, already-verified integration points, not assumed ones. `depends_on_plans:
[P066]` lets the FSM refuse EPIC init here until P066 is closed, so the catalog/config contract
this plan reads is guaranteed stable, not still-being-designed.

**Cons:** this plan cannot start (EPIC init) until P066 merges — an explicit, accepted sequencing
cost.

### Option B: Build the scheduler against a hypothetical/parallel catalog contract, decoupled from
P066's actual schema

**Cons:** this is close to what already failed — a scheduler designed against an assumed contract
drifts from the real one. **Rejected.**

### Option C: Skip `aid-run-gates.sh`/`compose_execution_yaml` integration; ship the scheduler as a
standalone script a project can invoke manually

**Cons:** this is exactly the "config/documentation/registry row substituting for real
integration" pattern the PM explicitly rejected in the split instructions. A scheduler nothing in
the real gate-execution path ever calls is decoration. **Rejected.**

### Decision

**Chosen:** Option A. **Rationale:** matches explicit PM direction; grounds every integration claim
against code already read this session, not assumed.

## High-Level Steps

| # | Step | Description | Estimated Effort |
|---|------|-------------|-----------------|
| 1-4 | EPIC 1 — Execution units on `aid-job.sh` | Formal, reusable execution-unit schema/wrapper (distinct from P066's one-off runner), streamed logs, process groups, deadlines, terminal receipts | L |
| 5-8 | EPIC 2 — Deterministic scheduler | Batch planner consuming P066's catalog, isolation-experiment protocol (disposable worktree only), sequential-vs-scheduled divergence gate, deterministic report merge | L |
| 9-11 | EPIC 3 — `aid-select-tests.sh` refactor | Selector emits execution units instead of always running them directly; default behavior unchanged when no scheduler is configured | M |
| 12-15 | EPIC 4 — Real gate-runner and config-path integration | `aid-run-gates.sh` scheduler dispatch, `execution-stacks/*.yaml` + `compose_execution_yaml` real wiring, rollout gating | L |
| 16-19 | EPIC 5 — Rollout, remediation, and full-path E2E | sequential→observe_parallel→parallel activation, `bats_all` remediation evidence (`plan_diff` out of scope), the mandatory full-path E2E | L |

## Constraints

1. **Unknown isolation ⇒ sequential, always.** No two aggregate test/gate actions run concurrently
   against the same live checkout. Any experiment promoting a catalog entry from `unknown`/
   `constrained` to `safe` runs exclusively inside a disposable `git worktree`/clone with its own
   declared-resource namespace — never the live project tree.
2. This plan reuses P066's catalog contract byte-for-byte (`command` discriminated union,
   `parallel.*`/`isolation.*` fields, `runtime.fingerprint`) — it does not redefine or fork any of
   these fields. A schema change needed here that P066 didn't anticipate is a blocking finding
   against THIS plan, resolved by a minor, backward-compatible schema addition, never a silent
   reinterpretation of an existing field.
3. **Execution units are a formal, reusable, scheduler-consumed abstraction** — distinct from
   P066's own one-off `aid-test-audit-measure.sh` (which stays as P066's sequential-only tool for
   its own measurement needs and is not modified by this plan).
4. **No second job/process supervisor.** Execution units call `aid-job.sh`'s existing, real CLI
   (`run --jobs-dir <dir> --id <id> --deadline <seconds> --label <text> -- <argv-or-bash-c>`, real
   terminal states `terminal_pass|terminal_fail|timed_out|cancelled`) exactly as verified this
   session — never a reimplementation.
5. **Real integration, not a config/documentation stand-in.** The main E2E acceptance criterion of
   this plan (Step 19) MUST demonstrate the real path: configured profile → `aid-run-gates.sh` →
   selected execution units (via the refactored `aid-select-tests.sh`) → scheduler → per-unit
   receipts → the same aggregated verdict `aid-run-gates.sh` already produces today. A test that
   only checks a config file's shape, a doc's wording, or an enforcement-registry row's presence
   does not satisfy this constraint.
6. **The real config-generation path is `defaults/execution-stacks/*.yaml` +
   `compose_execution_yaml`** (`scripts/lib/aid-init-execution-yaml.sh:293`, called from
   `commands/aid-init.md:109` and `aid-fsm.sh:2686`) — never
   `plugins/aid-orchestrator/defaults/execution.yaml` alone, which is this plugin's own dogfood
   config and is never copied into a consumer project.
7. **Scheduler batches only proven-independently-executable units.** A catalog entry and a
   schedulable execution unit are not automatically the same thing — every unit needs its own
   stable runner command/filter and a verified membership check.
8. Rollout is strictly staged: `sequential` (unchanged behavior, default) → `observe_parallel` →
   `parallel`. **Narrowed explicitly after a real C0 review found "always cross-checked against the
   identical sequential run" contradicted Step 14's real dispatch (which does not re-run sequential
   on every ordinary gate invocation, since that would double the cost of every single gate run
   forever and defeat the purpose of scheduling at all)**: the cross-check is REQUIRED to unlock
   and to REMAIN unlocked, never on every ordinary dispatch. Concretely — `observe_parallel`/
   `parallel` are unlocked (Step 13) only by 3 independent, currently-matching (commit +
   catalog-fingerprint-set) divergence-check artifacts (Step 7); those artifacts are produced by a
   separate, explicit, periodic/PM-scheduled `aid-test-schedule-divergence-check.sh` invocation
   (never invoked automatically by ordinary gate runs), and become stale (forcing a fall back to
   `sequential`) the moment the catalog fingerprint set changes. An ordinary `aid-run-gates.sh`
   dispatch in an unlocked mode trusts that currently-valid, already-proven evidence — it does not
   re-derive it per run. One config flip reverts to `sequential` with no catalog migration
   required.
9. This plan produces `bats_all` remediation **evidence** (measured before/after,
   isolation proof, membership/verdict comparison) — actually removing the `quarantine:` block in
   `.aid-o/config/execution.yaml` remains a PM action taken after reviewing that evidence, never an
   automatic side effect of this plan merging.
10. No broad full-suite rerun and no two aggregate test/gate actions against one mutable worktree
   during analysis or review of this plan itself.
11. **CI budget for new bats suites (added after a real L3 lens finding, CP1-deep re-run).**
   `.github/workflows/ci.yml`'s `bash-tests` job runs on a `timeout-minutes: 20` budget over every
   non-delegated bats suite via `run-all-tests.sh`. Every new bats suite this plan adds that
   creates real git worktrees/disposable clones, or exercises multi-attempt/budget logic (Steps
   1/6/7 in particular), MUST do one of: (a) scope its own fixtures to trivially small
   attempt-counts/timeouts (seconds, not this plan's own production defaults of up to 3600s), and
   state this explicitly as an acceptance criterion; or (b) be added to `run-all-tests.sh`'s
   `DELEGATED_SUITES` map with its own dedicated, separately-budgeted CI job — the exact precedent
   already set for `test-aid-plan-release-boundary.bats`/`test-aid-plan-final-boundary.bats`. The
   actual added wall-clock cost to the shared `bash-tests` job must be measured before this plan's
   own release, confirming the existing 20-minute budget still holds.

## Resources Verification

### Existing Resources (re-verified 2026-08-02 against `main@281f87f`, v2.66.2 — P066 fully merged)

- [x] `aid-job.sh` real CLI and terminal-state vocabulary (same facts as P066's Resources
  Verification — re-verified here since this plan builds the reusable execution-unit wrapper P066
  explicitly does not).
- [x] `aid-run-gates.sh`: `run_all_gates()` (line 186 — unchanged, re-confirmed) is a single
  sequential `while read gate_name` loop over `yq '.gates | keys | .[]'`; confirmed zero existing
  parallel-dispatch code (no `xargs -P`/background/`wait` construct beyond an advisory string
  label) — this plan adds real scheduling logic, it does not activate dormant plumbing.
  `resolve_placeholders()` at line 105 and the `gate_baseline_update` call site at line 457
  (Steps 12/14's citations) both re-confirmed at their originally-cited line numbers, byte-exact.
- [x] `defaults/execution-stacks/*.yaml` (`bash.yaml`, `go.yaml`, `python.yaml`, `rust.yaml`,
  `typescript.yaml`) — each a flat `gates:` block; `compose_execution_yaml`
  (`scripts/lib/aid-init-execution-yaml.sh:293`, re-confirmed at this exact line) concatenates the
  detected stacks' blocks into a fresh project's `.aid-o/config/execution.yaml`, called from
  `commands/aid-init.md:109` and `aid-fsm.sh:2686` — this is the real generation path, confirmed by
  direct read.
- [x] `aid-select-tests.sh` (367 lines, unchanged): `map_path_to_tests()` now at line 158 (was 154 —
  1-line drift, unrelated churn; `is_production_surface()` at 215) currently *runs* its selected
  tests directly (`bats "$abs_test_path"` at line 293 / `bash "$abs_test_path"` at line 301) —
  confirmed this plan's refactor (emit execution units instead of always running inline) is a real,
  necessary code change, not cosmetic.
- [x] `aid-gate-runtime-baseline.sh`'s `concurrency_context` extension point is NOT yet built by
  P066 (P066 has no scheduler to annotate against) — this plan owns adding
  `concurrency_context: sequential|observe_parallel|parallel` to that library, confirmed as a gap
  neither plan has yet filled.

### P066 Dependency — now VERIFIED against the real, merged artifacts (re-grounded 2026-08-02)

**P066 is now `status: done`, merged to `main` (v2.65.0 through v2.66.2), and archived to
`.aid-o/plans/archive/`.** Every item below was PENDING/unverified at this plan's original
authoring (2026-07-28, against a still-`draft` P066) and has now been re-read against the ACTUAL
shipped code — not this plan's memory of P066's draft. Two real drifts were found and are recorded
here rather than silently carried forward:

- `plugins/aid-orchestrator/defaults/schemas/test-catalog.schema.json` — **VERIFIED unchanged**:
  the `command` discriminated union, `parallel.*`, `isolation.*`, and `runtime.fingerprint` fields
  this plan depends on all match exactly what P066 shipped — no drift, no blocking finding.
- `plugins/aid-orchestrator/scripts/aid-test-catalog-approve.sh` — **DRIFTED, this plan's Step 11
  updated accordingly.** P066's own EPIC 3 whole-diff review (a real PM-found gap, fixed before
  release) removed the script's `--approved-path` override entirely — the approved catalog target
  is now always the fixed, non-configurable `${project_root}/.aid-o/config/test-catalog.yaml`. Step
  11's modification approach (extend the approval action to also run the selector-snapshot script)
  is unaffected by this, but is now written against the real, current signature
  (`--proposed <path> --project-root <path>`), not the plan-draft-era assumption.
- `plugins/aid-orchestrator/scripts/lib/aid-test-audit-config.sh` (`load_test_audit_config`) —
  **VERIFIED unchanged**: still the real function at this path, referenced only for the
  `test-audit.yaml`/`execution.yaml` authority split (Constraint — Step 13); not called by any
  script this plan creates.
- **New P066 artifact this plan should be aware of but does not need to modify:**
  `aid-audit-tests-finalize.sh` (P066 Step 24) — the one mandatory production entrypoint chaining
  consolidate → chat-summary → write-plan-bridge. Unrelated to this plan's gate-runner/scheduler
  integration surface (`aid-run-gates.sh`, `aid-select-tests.sh`, `compose_execution_yaml`) — no
  overlap, no action needed, noted here only so a future reader doesn't assume this plan is unaware
  of it.
- **The naming correction this plan already made once (Step 1) but did not apply consistently is
  now fixed throughout**: every other reference to the old `selector_mappings[]` name (Steps 10/11,
  the Step 17 E2E scenario, and the Risks table) has been corrected to the real, shipped field name
  `source_pattern_mappings[]`.
- **The "88 `run_units`" figure cited in the original draft (Steps 15/17, Plan Assumptions) was
  already stale by P066's own release** — this repo's real catalog has 83 run_units as of P066's
  release (verified directly, P066 Step 21's own self-host audit found this exact drift). Every
  reference has been corrected to re-derive the count from the live catalog at measurement time,
  never a hardcoded constant — the fact that P066's own number drifted before this plan even started
  is itself the argument for never hardcoding it here either.

### Plan Assumptions

- [x] No new backlog IDs.
- [x] New test file basenames checked against P066's real, current `run_units` count (83 in this
  repo as of P066's release, `.aid-o/config/test-catalog.yaml` — never hardcoded; re-derive from
  the live catalog at implementation time, since this count is project-specific and already drifted
  once between P066's own authoring and its release) + this plan's own new
  files — no collision.
- [x] No database fields touched.
- [x] No file removed. `aid-run-gates.sh` and `aid-select-tests.sh` are modified, not replaced;
  `execution-stacks/*.yaml` files gain new optional gate entries, existing entries unchanged.

### Resolution

- [x] All items VERIFIED or mapped to an explicit Create/Modify step below.
- [x] This plan's dependency on P066's schema is declared in frontmatter (`depends_on_plans:
  [P066]`). **Re-grounding note (2026-08-02):** P066 is now genuinely `status: done`/merged, so
  the dependency's SUBSTANCE is satisfied. However, P066 was developed manually, outside
  `/aid-run` — it was never `cmd_init`'d, so no `.aid-lifecycle/manifests/P066.yaml` exists for
  the FSM's own dependency-gate check to find. Whoever runs `/aid-plan epic` for this plan should
  verify directly whether `aid-fsm.sh init`'s `depends_on_plans` check treats "no manifest found"
  as satisfied, as blocking, or as an error — this plan's own dependency is REALLY satisfied
  either way (P066's code is in `main`), but the mechanical gate-check behavior for a
  manually-closed, manifest-less dependency has not been verified and may need a small, explicit
  workaround (e.g., a stub manifest) if it fails closed on "unknown."

## Implementation Steps

**EPIC 1: Steps 1-4 — Execution units on `aid-job.sh`**

### Step 1: Formal execution-unit schema and `aid-job.sh` wrapper

**Objective:** Define the reusable, scheduler-consumed execution-unit contract — distinct from
P066's one-off sequential measurement runner.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/schemas/execution-unit.schema.json` — `unit_id`
  (**identifier mapping fixed explicitly, twice now — first after a real C0 review found this plan
  alternating between ambiguous "catalog `test_id`" and `entries[].id`, then again after PM
  feedback found the granularity itself was wrong (one catalog entry per `@test`, ~1,610, instead
  of per schedulable command, 88) — P066's schema is now fixed as `run_units[]` (88, file-level,
  never per-`@test`) with `run_unit_id` as the one identifier, and a separate
  `source_pattern_mappings[]` array (renamed from `selector_mappings[]`) for routing, with its own
  `target_run_unit_ids[]` field and its own `mapping_approval` confirmation gate**: `unit_id`
  ALWAYS references a P066 catalog `run_units[].run_unit_id` value directly — never a
  `source_pattern_mappings[]` row, which is a separate routing-table concept P066/Step 10 consume
  on their own; one `run_units[].run_unit_id` maps to exactly one `unit_id` unless `dedup: true`,
  below), `command` (reuses P066's exact discriminated union, never redefined),
  `deadline_seconds`, `resource_locks[]` (names matching the `execution.yaml`
  `test_audit.scheduler.resource_locks` map — **authority resolved explicitly after a real C0
  review found a genuine contradiction**: P066's `test-audit.yaml` schema reserves a root
  `resource_locks` field but nothing reads or writes it; since resource locking is a
  gate-runtime/scheduling concern exactly like `scheduler.mode`, not an audit-time concern, this
  plan defines it ONLY as a new sibling key inside the SAME `test_audit.scheduler` block Step 12
  already adds to `execution.yaml` — `test_audit.scheduler.resource_locks: {}` — never in
  `test-audit.yaml`. P066's reserved-but-unused root field is explicitly superseded and never
  read by this plan), `parallel_eligible` (boolean, derived from the referenced catalog entry's
  `parallel.status`), `membership_verified` (boolean, always `false` until Step 2 sets it — see
  Step 2 for the producer contract), `dedup` (boolean,
  default `false` — **field and ownership added after a real C0 review found Step 2 required this
  annotation but no schema field or producer was ever assigned**: `dedup` is set to `true` ONLY by
  Step 2's membership verifier, and ONLY when two different `run_units[].run_unit_id` values both resolve to
  byte-identical `command` AND the catalog itself carries a `recommendation: merge` finding
  (from a prior `/aid-audit-tests` run) explicitly naming both IDs as an intentional duplicate —
  never set from command-identity alone, and never settable by any other producer), `membership_
  binding` (**object field added after a real C0 planned_call_feasibility-lens finding (CP1-deep
  re-run) found Steps 2/5/9 all treat this as an established field of "Step 1's schema" while Step
  1 itself never listed it** — `{catalog_fingerprint, verified_at, verifier_run_id}`, optional/
  nullable, `null` until Step 2's membership verifier populates it — same ownership pattern as
  `dedup` immediately above: this field exists in the schema from Step 1 onward, but only Step 2 is
  ever permitted to write a non-null value into it)
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-execution-unit.sh` — given one execution
  unit, calls `aid-job.sh run --jobs-dir <dir> --id <job-id> --deadline <seconds> --label
  test-scheduler -- "${argv[@]}"` (argv-type) or `... -- bash -c "$shell"` (shell-type); streams
  `stdout_path` immediately; normalizes real terminal `state` values into a scheduler-shaped receipt
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-execution-unit.bats` — a hung
  fixture reaches `state:timed_out` with its process group reaped (via `cmd_wrap`'s existing
  closing `kill -KILL -"$mypgid"`); streamed log visible before exit; two units started
  back-to-back get distinct job IDs and never collide on `aid-job.sh`'s job-record paths

**Architecture Context:** This is the abstraction P066 explicitly deferred — reusable, scheduler-
consumed, batch-eligible, unlike P066's own single-command-at-a-time tool.

**Implementation Detail:** No new process-group/kill logic — `aid-job.sh`'s existing mechanisms are
used exactly as verified this session.

**Error Handling:** A deadline-killed unit's receipt records the real `state:timed_out`.

**Edge Cases:**
- A unit referencing a `parallel_eligible: true` catalog entry whose `isolation.lock_usage[]` is
  non-empty is still scheduled — `parallel_eligible` is informational; the scheduler (Step 5) is
  what actually enforces isolation, not this wrapper.

**Dependencies:**
- Depends on: ---
- Blocks: Step 2 — the scheduler dispatches batches of these units

**Acceptance Criteria:**
- [ ] A hung fixture reaches `state:timed_out` at its exact deadline with zero orphaned descendants
- [ ] Streamed log content is readable while the job is still running
- [ ] `aid-job.sh` itself is not modified — only its existing CLI is called
- [ ] `command` matches P066's discriminated union exactly (schema cross-reference, not a fork)

**Effort:** L
**AID Role:** backend

---

### Step 2: Execution-unit membership verification

**Objective:** Prove a catalog `run_units[].run_unit_id` and a schedulable execution unit are not automatically
the same thing (Constraint 7) — every unit must resolve to a stable, verified runner command/filter,
and produce the exact `membership_verified` stamp Step 5 later requires.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-execution-unit-membership.sh` — given a
  selected set of catalog `run_units[].run_unit_id` values, resolves each to exactly one execution unit's
  `command`, fails if an id resolves to zero or more than one unit, and fails if two different ids
  resolve to byte-identical commands without an explicit `dedup: true` annotation (Step 1's field,
  set only per that step's precondition). **`membership_verified` stamp, defined explicitly after a
  real C0 review found Step 5 required it with no producer or persisted shape**: on successful
  resolution, this script sets each unit's `membership_verified: true` (Step 1's schema field) AND
  writes a `membership_binding` object alongside it in the SAME unit record —
  `{catalog_fingerprint: <the resolved run_units[].run_unit_id's runtime.fingerprint>, verified_at,
  verifier_run_id}` — binding the verification to the exact catalog state it was checked against;
  Step 9's `--emit-units` output preserves both fields byte-for-byte (it does not strip or
  regenerate them); Step 5 rejects any unit where `membership_verified` is `false`/absent OR where
  `membership_binding.catalog_fingerprint` does not match the unit's own current
  `runtime.fingerprint` (a stale binding is rejected exactly like a missing one)
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-execution-unit-membership.bats` — one
  clean 1:1 resolution case produces `membership_verified: true` with a matching
  `membership_binding`; a zero-resolution case (fails); a many-resolution case without dedup
  (fails); an intentional dedup case (passes); a unit whose catalog entry's fingerprint changed
  after verification is rejected downstream as stale (Step 5's own test covers the rejection; this
  test proves the binding is written correctly for that later check to use)

**Architecture Context:** Closes the "two shards contain the same stable test ID" and "membership
must be verified, not assumed" requirements before the scheduler (Step 5) ever batches anything.

**Implementation Detail:** Pure resolution logic — no execution happens in this step.

**Error Handling:** Any ambiguous resolution halts with the exact `run_unit_id` and candidate count
named.

**Edge Cases:**
- A `run_unit_id` referencing a Bats file with a `--filter` pattern matching zero current tests (stale
  reference after a source file changed) — fails loudly, not silently zero-width.

**Dependencies:**
- Depends on: Step 1 — verifies membership for the units Step 1's wrapper executes
- Blocks: Step 5 — the scheduler consumes only membership-verified units

**Acceptance Criteria:**
- [ ] A `run_unit_id` resolving to zero or multiple units fails loudly, naming the candidates
- [ ] An intentional dedup case passes only with the explicit `dedup: true` annotation

**Effort:** M
**AID Role:** backend

---

### Step 3: `concurrency_context` extension to P063's baseline library

**Objective:** Add the concurrency-context annotation neither this plan nor P066 has yet built, so
scheduler contention never silently corrupts sequential baselines.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-gate-runtime-baseline.sh` (lines ~37-52) — in
  `gate_baseline_update()` (line ~269), add an optional 7th argument `concurrency_context`
  (`sequential|observe_parallel|parallel`, defaulting to `sequential` when omitted — the exact
  vocabulary Step 14's caller uses) to the real, verified `gate_baseline_update(gate_name,
  command_template, resolved_command, exit_code, duration_ms, timeout_seconds)` function (confirmed
  6-positional-arg signature at `lib/aid-gate-runtime-baseline.sh:269`), stored on each recorded
  sample. **Persisted-shape and reader-API contract, added after a real C0 review found "add a
  field to samples" cannot represent multiple percentile series without breaking existing
  consumers**: the existing TOP-LEVEL per-gate fields (`p50_ms`, `p90_ms`, `p95_ms`, `max_ms`,
  `last_duration_ms`, `last_exit_code`, `policy_result`, etc.) are UNCHANGED in meaning and
  continue to be computed from `sequential`-context samples ONLY. **`recent_samples` segregation,
  corrected after a real C0 reuse_compat-lens finding (CP1-deep re-run) found the ORIGINAL "purely
  additive, no code change" claim false against the real `gate_baseline_policy_check`
  (`lib/aid-gate-runtime-baseline.sh:484-512`): that function does NOT read the top-level
  percentile fields at all — it scans the raw `.recent_samples[-$k:]` window directly. A
  non-sequential sample appended into that SAME shared FIFO array would silently enter this
  window and could flip `gate_baseline_policy_check`'s block/no-block verdict relative to a
  sequential-only history, contradicting the "identical decision" claim.** The fix: a sample whose
  `concurrency_context` is `observe_parallel`/`parallel` is NEVER appended to the existing
  `.recent_samples` array at all — it is appended ONLY to a new, separate, additive sibling array,
  `.recent_samples_by_context.observe_parallel[]` / `.recent_samples_by_context.parallel[]`, from
  which the new `percentiles_by_context: {observe_parallel: {p50_ms,p90_ms,p95_ms,max_ms,
  samples_count}, parallel: {...}}` object is computed. `.recent_samples` itself, and every
  existing reader of it (`gate_baseline_policy_check`'s last-k window,
  `aid-run-gates.sh:470-481`'s timeout/recommendation logic, `gate_baseline_report_json`/
  `gate_baseline_show`), is therefore genuinely untouched BY CONSTRUCTION — not merely by
  intention — since a non-sequential sample is structurally routed to a different array from the
  moment it is recorded, never merged into or filtered out of the shared one after the fact
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-runtime-baseline-concurrency.bats`
  — mixed-context samples produce correct, separate `percentiles_by_context` entries computed
  ONLY from `.recent_samples_by_context.*`, while `.recent_samples` itself is asserted BYTE-
  IDENTICAL before/after a non-sequential sample is recorded (not merely "produces the same
  decision" — the array's own content never changes), proving segregation by construction; a
  pre-migration baseline file (no `concurrency_context`, no `recent_samples_by_context`) reads as
  implicitly `sequential`, fully backward compatible; every existing reader function
  (`gate_baseline_policy_check` and the `aid-run-gates.sh:470-481` timeout logic) is re-run
  unmodified against a mixed-context fixture and produces the identical decision it would have
  before this step — now a genuine consequence of `.recent_samples` being untouched, not an
  assertion needing separate proof; the extended function signature is backward-compatible — an
  existing caller passing only 6 args still works, defaulting to `sequential`

**Architecture Context:** Prevents exactly the risk both the original roadmap and this plan's own
Constraint 8 name: parallel contention silently corrupting a baseline a human or gate later trusts
as "the sequential number" — by construction, since the existing top-level fields never include a
non-sequential sample at all.

**Implementation Detail:** Fingerprint scheme is untouched — only percentile bucketing/storage
changes, and only additively.

**Error Handling:** A baseline file without `concurrency_context` support, or without any
`percentiles_by_context` object at all, remains fully readable by every existing function
(additive, optional field/object).

**Edge Cases:**
- A gate's `command_template` change (fingerprint changes) still resets its percentile series
  exactly as today — concurrency segmentation doesn't change this existing behavior.

**Dependencies:**
- Depends on: ---
- Blocks: Step 14 — **corrected after a real L2 lens finding (CP1-deep re-run): the actual consumer
  of this step's new 7th `gate_baseline_update` argument is Step 14's call site, not Step 8 (Step 8's
  own text never reads `concurrency_context`/`percentiles_by_context`) — the dependency edge is
  fixed to point at the real consumer**

**Acceptance Criteria:**
- [ ] Existing top-level percentile fields remain computed from `sequential` samples only, byte-
  identical to pre-this-step behavior on a sequential-only fixture
- [ ] `percentiles_by_context` is a purely additive sibling object, never replacing or renaming an
  existing field
- [ ] Every existing reader function produces an identical decision on a mixed-context fixture as
  it would have before this step
- [ ] Pre-migration baseline files remain readable, treated as `sequential`

**Effort:** M
**AID Role:** backend

---

### Step 4: Deterministic report shape for execution-unit receipts

**Objective:** Define the one canonical, deterministically-ordered receipt/report shape every later
step (scheduler, gate-runner integration) emits and consumes — before either exists.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/schemas/execution-unit-receipt.schema.json` — per-unit
  receipt (`unit_id`, `job_id`, `state`, `duration_ms`, `concurrency_context`, `co_scheduled_with[]`,
  `stdout_path`, `exit_code`) and a batch-level wrapper (`batch_id`, `units[]`, `started_at`,
  `ended_at`)
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-execution-unit-receipt-schema.bats` —
  minimal-valid + invalid fixtures; two receipts sets built from reordered input serialize to
  byte-identical output when sorted by `unit_id`

**Architecture Context:** Pins the shape Step 5 (scheduler) and Step 12 (gate-runner integration)
both target, avoiding a repeat of the schema-negotiated-mid-flight problem the original monolithic
draft had.

**Implementation Detail:** Sort key is `unit_id`, not arrival/completion order.

**Error Handling:** N/A beyond schema validation.

**Edge Cases:** N/A.

**Dependencies:**
- Depends on: Step 1 — receipts wrap the terminal states that step's wrapper produces
- Blocks: Step 5 — the scheduler's batch planner emits this exact shape

**Acceptance Criteria:**
- [ ] Schema validates a minimal-valid and an invalid fixture
- [ ] Reordered input serializes to byte-identical output when sorted by `unit_id`

**Effort:** S
**AID Role:** architect

---

**EPIC 2: Steps 5-8 — Deterministic scheduler**

### Step 5: Deterministic batch scheduler (sequential default)

**Objective:** Build the batch planner consuming P066's catalog `parallel.status`/`isolation`
fields and this plan's own membership-verified execution units — shipped behind a `sequential`
default.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/schemas/scheduler-parallel-overlay.schema.json` —
  **new, defined HERE (not in Step 6) so Step 6's producer has an already-fixed contract to write
  against — added after a real, CRITICAL C0 finding (5th cross-provider Codex round) found no
  durable promotion artifact was ever defined at all, so nothing could ever move a unit off
  `unknown`.** `{schema_version, status: proposed|approved, overlay: [{run_unit_id,
  promoted_status: safe|constrained, catalog_fingerprint_at_promotion (the exact
  `runtime.fingerprint` this run_unit_id had in the catalog at promotion time — the staleness key
  this step's own scheduler checks), promoted_at, evidence_run_id (the specific isolation-
  experiment invocation that produced this promotion — Step 6 is its producer)}]}`. Deliberately
  SEPARATE from and ADDITIVE to `.aid-o/config/test-catalog.yaml` — never a modification to P066's
  own `parallel.status` field or approval semantics (Constraint 2; same authority-resolution
  pattern as `resource_locks` in Step 1 and the catalog-approval-boundary reconciliation in Step
  11): the catalog's own `parallel.status` remains P066's field, untouched; this overlay is the
  ONLY place an `unknown` → `safe`/`constrained` promotion is ever recorded
- Create: `plugins/aid-orchestrator/scripts/aid-scheduler-overlay-approve.sh` — the mandatory,
  PM-invoked approval gate for the schema above (mirroring P066's `aid-test-catalog-approve.sh` +
  `aid-test-catalog-confirm-mapping.sh` pattern exactly, never a novel mechanism): displays every
  proposed promotion (`run_unit_id`, `promoted_status`, the `evidence_run_id` backing it) as a
  reviewable diff with a `reviewed_diff_hash`; on a matching `--confirm-overlay <hash>`
  invocation, copies the reviewed overlay to the canonical, force-tracked
  `.aid-o/config/test-scheduler-parallel-overlay.yaml` (`git add -f`, same mechanism/rationale as
  every other new evidence artifact this plan force-tracks) with `status: approved`. A promotion
  whose `catalog_fingerprint_at_promotion` no longer matches the CURRENT catalog's
  `runtime.fingerprint` for that `run_unit_id` is rejected at approval time, named explicitly — a
  stale promotion (the underlying test changed since the isolation experiment ran) can never be
  silently approved
- Create: `plugins/aid-orchestrator/scripts/aid-test-scheduler.sh` — **effective-status
  resolution**: for each unit, the EFFECTIVE `parallel.status` this scheduler batches by is: the
  approved `test-scheduler-parallel-overlay.yaml`'s `promoted_status` for that `run_unit_id`, IF an
  approved entry exists AND its `catalog_fingerprint_at_promotion` matches the unit's CURRENT
  catalog `runtime.fingerprint`; otherwise the catalog's own `parallel.status` value, unchanged
  (this repo's real catalog today has every unit at `unknown`, so this scheduler correctly
  produces N sequential size-1 batches until Step 6's overlay approves at least one promotion —
  this is the expected, safe starting state, not a defect). `unknown` (whether from the catalog
  directly or from a missing/stale overlay entry) ⇒ always its own
  sequential batch; `constrained` ⇒ batched only respecting named `exclusive_resources` locks
  (cross-referenced against `execution.yaml`'s `test_audit.scheduler.resource_locks` map — see
  Step 1's corrected authority resolution; never `test-audit.yaml`); `exclusive` ⇒ always alone;
  global process/CPU budget and per-runner worker
  budget, avoiding double-oversubscription against a runner's own internal workers
  (`parallel.internal_parallelism`, P066's field). Requires every input unit to carry Step 2's
  membership-verification stamp — a unit without it is rejected before batching, never silently
  scheduled (**dependency correction, added after a real C0 review found Step 2 was not a
  declared predecessor despite this requirement**). **Process-lifecycle/cancellation protocol,
  added after a real C0 review found none was specified**: this script writes every unit's
  `aid-job.sh` job record under one scheduler-owned directory
  (`.aid-o/work/test-audits/<run-id>/scheduler-jobs/`) per invocation, installs a `TERM`/`INT` trap
  for its own lifetime, and — on receiving either signal (the caller, `aid-run-gates.sh`, sends
  this on its own `timeout`/interrupt) — calls `aid-job.sh cancel --jobs-dir <that directory> --id
  <id>` for every still-outstanding unit in the current batch, waits for each to reach a terminal
  receipt, and only then re-raises the signal/exits; a new dispatch is refused while any prior
  batch's jobs directory still has non-terminal entries. **Job-id retry-scoping, added after a real
  C0 idempotency-lens finding (CP1-deep re-run) found no defined job-id shape for a GATE-LEVEL
  retry of the same unit set** (Step 8's own text has `aid-run-gates.sh`'s `max_retries` loop
  re-invoking this whole scheduled dispatch under the SAME `run-id`): every unit's `aid-job.sh`
  `--id` is composed as `<run-id>-<unit_id>-attempt<N>`, where `attempt<N>` starts at `attempt1` and
  increments once per full re-dispatch of the same `run-id`'s scheduled batch — never reusing a
  prior attempt's job-id for the same unit, so a retried dispatch can never collide with or
  overwrite a prior attempt's terminal `aid-job.sh` receipt in the same `scheduler-jobs/` directory
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-scheduler.bats` — an all-
  `unknown` catalog (no overlay) produces N sequential size-1 batches; a mixed `safe`/`constrained`/
  `exclusive` set (via an approved overlay) produces the expected batch shape; a resource-lock
  conflict forces separate batches; global budget never exceeded; a unit lacking Step 2's
  membership stamp is rejected before batching; **an E2E case where a real `unknown` unit becomes
  schedulable in a multi-unit batch after Step 6's promotion + this step's own approval script**
  (proving the effective-status resolution genuinely reads the overlay, not merely the catalog); a
  proposed-but-NOT-approved overlay entry is never read as authoritative; a stale
  (`catalog_fingerprint_at_promotion` mismatched) approved entry falls back to the catalog's own
  value, identically to no entry at all; **sending `TERM` to the scheduler mid-batch results in
  every outstanding unit reaching a terminal `aid-job.sh` receipt (via real `cancel`) before the
  scheduler process exits, verified via `/proc` — zero orphaned process groups**; **two dispatches
  of the same `run-id` (simulating a gate-level retry) produce distinct job-ids for the same
  `unit_id` (`attempt1` vs `attempt2`), and the first attempt's terminal receipt is never
  overwritten or read as the second attempt's result**
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-scheduler-overlay-approve.bats` — a
  reviewed, hash-confirmed approval force-tracks `test-scheduler-parallel-overlay.yaml` (verified
  via `git ls-files --error-unmatch` in a disposable fixture repo, same pattern as
  `test-catalog-force-tracked.bats`); a stale-fingerprint promotion is rejected at approval time,
  naming the specific `run_unit_id`

**Architecture Context:** New code — `aid-run-gates.sh` has zero existing parallel-dispatch logic;
nothing here "unlocks" dormant plumbing (Resources Verification).

**Implementation Detail:** With `test_audit.scheduler.mode: sequential` (the shipped default), every
batch executes as a size-1 sequential batch regardless of computed `parallel.status` — this same
code path is what `observe_parallel`/`parallel` modes later reuse, never a second "real" scheduler
behind the sequential one.

**Error Handling:** A catalog entry with a `parallel.status` value outside the schema enum is a
scheduler-level hard failure. A dispatch attempt while a prior batch's jobs directory still has
non-terminal entries fails closed, naming the stuck `unit_id`(s), rather than silently starting a
second overlapping batch.

**Edge Cases:**
- Two differently-named `exclusive_resources` that resolve to the same physical resource — out of
  this step's automatic detection scope; flagged as a known limitation requiring canonical resource
  naming in project config, not silently handled.
- A `TERM` received AFTER all units already reached a terminal state (race with normal completion)
  — the trap handler finds nothing outstanding and exits immediately, not an error.

**Dependencies:**
- Depends on: Step 2 — every batched unit must carry Step 2's membership-verification stamp; Step 4 — batches are composed of and emit the receipt shape defined there
- Blocks: Step 6 — the isolation-experiment protocol promotes entries this scheduler batches

**Acceptance Criteria:**
- [ ] With `mode: sequential` (default), every batch executes size-1 regardless of computed
  `parallel.status`
- [ ] `unknown` never appears in a multi-entry batch, in any mode
- [ ] A resource-lock conflict is never scheduled into the same batch
- [ ] A unit with `membership_verified: false`/absent is rejected before batching
- [ ] A unit with a stale `membership_binding.catalog_fingerprint` (not matching its current
  `runtime.fingerprint`) is rejected before batching, identically to a missing stamp
- [ ] A `TERM`/`INT` signal mid-batch results in every outstanding unit reaching a real, terminal
  `aid-job.sh` receipt via `cancel`, with zero orphaned process groups (verified via `/proc`)
- [ ] A promoted, approved, non-stale overlay entry genuinely changes a unit's effective batching
  status — proven by an E2E case where a real `unknown` unit becomes schedulable in a multi-unit
  batch after promotion + approval, never merely asserted
- [ ] A proposed-but-unapproved overlay entry is never read as authoritative
- [ ] A stale (fingerprint-mismatched) approved overlay entry falls back to the catalog's own
  value, identically to no entry at all
- [ ] The approval script force-tracks the approved overlay and rejects a stale promotion at
  approval time, naming the specific `run_unit_id`

**Effort:** L
**AID Role:** backend

---

### Step 6: Isolation-experiment protocol (disposable worktree only)

**Objective:** Implement the specific, fixed protocol that promotes a test from `unknown`/
`constrained` to `safe`/`constrained` — strictly inside disposable, isolated worktrees/clones
(Constraint 1) — writing to the overlay schema/approval gate Step 5 already defines. **Split from
the durable-persistence design after a real, CRITICAL C0 finding (5th cross-provider Codex round)
found the ORIGINAL Step 6 promoted a unit to `safe` with no defined output shape, writer, or
scheduler-readable location at all** — against this repo's own real catalog (83 run_units, every
one currently `parallel.status: unknown`), Step 5 as originally written could therefore NEVER
schedule more than one unit per batch, since nothing ever changed any unit's status from
`unknown`. The fix's schema/approval-gate half now lives in Step 5 (the consumer, so the contract
is fixed before this step's producer is written against it); this step is purely the producer.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-test-isolation-experiment.sh` — runs a candidate N
  times (N=5, project-configurable) concurrently with proposed batch-mates, exclusively inside a
  `git worktree add`-created disposable path (a distinct, test-scheduler-owned instance, never
  sharing a worktree with an implementer-agent dispatch), destroyed unconditionally at experiment
  end; promotes to `safe`/`constrained` only on zero shared-state assertion failures and no
  timing-order dependence across all N runs; writes proposed overlay entries — conforming to Step
  5's `scheduler-parallel-overlay.schema.json` — to the gitignored
  `.aid-o/work/test-audits/<run-id>/scheduler-overlay.proposed.json` (`status: proposed`,
  mirroring P066's own catalog `proposed`/`approved` file-location convention exactly), including
  the promoted unit's CURRENT catalog `runtime.fingerprint` as `catalog_fingerprint_at_promotion`
  and this experiment's own run-id as `evidence_run_id`. Never auto-approved — Step 5's
  `aid-scheduler-overlay-approve.sh` is the only path to `status: approved`
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-isolation-experiment.bats` — a
  genuinely isolated pair promotes to `safe`; a pair sharing an undeclared resource fails promotion
  with the specific shared-state failure named; the experiment's working directory is verified to
  never be the repo root; the written proposed-overlay entry validates against Step 5's schema and
  its `catalog_fingerprint_at_promotion` matches the real catalog entry's `runtime.fingerprint` at
  the moment of promotion

**Architecture Context:** The mechanical implementation of "no design may claim parallel-safe
without attached isolation evidence" — this plan's single most important invariant — completed end
to end together with Step 5: evidence (this step) → proposed overlay (this step) → PM-reviewed
approval (Step 5's `aid-scheduler-overlay-approve.sh`) → the one artifact Step 5's scheduler is
actually allowed to read as an override on top of P066's own catalog field.

**Implementation Detail:** Disposable-worktree creation failure (disk space, git version) fails
closed as `unknown` — never falls back to probing the live tree. This step never writes to
`.aid-o/config/test-scheduler-parallel-overlay.yaml` (the approved, force-tracked path) directly —
only to its own gitignored proposed-file; Step 5's approval script is the sole writer of the
approved path.

**Error Handling:** N/A beyond the above.

**Edge Cases:**
- A test whose behavior depends on absolute repository path behaves differently inside the
  disposable worktree — a legitimate `constrained`/`unknown` finding (undeclared path dependency),
  not an experiment bug.
- A catalog re-scan that changes a run_unit_id's `runtime.fingerprint` (the underlying command
  changed) automatically invalidates any existing approved overlay entry for that unit at the NEXT
  approval/read (Step 5 enforces this) — this step's own job is only ever to attach the CURRENT
  fingerprint at promotion time, never to detect staleness itself.

**Dependencies:**
- Depends on: Step 5 — experiments run against the scheduler's actual proposed batch, and this
  step's output must conform to the overlay schema/approval gate Step 5 defines
- Blocks: Step 7 — the divergence gate consumes both experiment and scheduler output

**Acceptance Criteria:**
- [ ] Every `safe`/`constrained` promotion traces to a specific isolation-experiment run with its
  evidence
- [ ] The experiment never executes against the live project checkout — enforced and tested
- [ ] A shared-undeclared-resource pair fails promotion with the specific failure named
- [ ] The written proposed-overlay entry validates against Step 5's `scheduler-parallel-overlay.
  schema.json` and carries a real, current `catalog_fingerprint_at_promotion`

**Effort:** L
**AID Role:** qa

---

### Step 7: Sequential-vs-scheduled divergence gate

**Objective:** Mechanically block promotion beyond `observe_parallel` on any membership or verdict
divergence.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/schemas/divergence-evidence.schema.json` — **new,
  added after a real C0 review found Step 14 depends on this step's "most recent result" with no
  durable artifact ever defined.** `run_id` (**tightened after a real C0 idempotency-lens finding
  (CP1-deep re-run): MUST be a genuinely collision-safe UUID — never "a monotonic counter,"
  which a naive directory-scan implementation could compute identically under two concurrent
  invocations against the same commit, silently overwriting a `retained, never-overwritten`
  artifact**), `catalog_fingerprint_set` (sha256 over the sorted set of every compared unit's
  `runtime.fingerprint` — this is what Step 13 checks for staleness), `commit_sha`, `worktree_kind`
  enum `disposable_clone` (never `live`), `mode_tested` enum `observe_parallel|parallel`,
  `selected_unit_ids[]`, `sequential_verdicts[]` (`{unit_id, result}`), `scheduled_verdicts[]`
  (same shape), `membership_diff[]` (empty if identical), `verdict_diff[]` (empty if identical),
  `pass` (boolean — true only if both diffs are empty), `evaluated_at`
- Create: `plugins/aid-orchestrator/scripts/aid-test-schedule-divergence-check.sh` — runs the same
  selected set both sequentially and via the scheduler on the same commit, inside a FRESH disposable
  clone per invocation (never reusing a prior run's worktree — this is what makes each run a
  genuinely independent trial, not a repeated read of the same result); compares membership and
  verdicts field-by-field; writes the schema above to
  `.aid-o/work/evidence/scheduler-divergence/<commit_sha>-<mode_tested>-<run_id>.json` (retained,
  never auto-pruned, never overwritten — each invocation gets its own file, using `mkdir`-based
  exclusive creation of a same-named lock directory as an atomicity guard, so a genuine UUID
  collision — vanishingly unlikely but not impossible — fails loudly instead of silently
  overwriting); any difference blocks promotion for that run, naming the exact unit/field, and is
  still written with `pass:false`. **Force-tracked into git, added after a real L3 lens finding
  (CP1-deep re-run) found every new evidence-artifact family in this plan targeted a path under
  the blanket-gitignored `.aid-o/` tree with no force-add wiring, unlike P066's own established,
  tested precedent** (`aid-test-catalog-approve.sh`'s `git add -f`, verified by
  `test-catalog-force-tracked.bats`): this script runs `git -C <project_root> add -f -- <the
  exact written path>` immediately after each successful, schema-valid write — the same, single
  mechanism P066 already ships, never a second, divergent force-tracking implementation. If
  `project_root` is not a git repository, the script writes the artifact and logs "not a git
  repository, evidence written but not tracked" (matching `aid-test-catalog-approve.sh`'s own
  documented non-git-repo behavior), never a hard failure
- Create: `plugins/aid-orchestrator/scripts/aid-test-divergence-campaign.sh` — **bounded orchestrator,
  added after PM feedback found accumulating the required 3 (or 6, across both stages) qualifying
  runs had no budget and risked becoming an unbounded, hours-long blocking loop.** Given a target
  `mode_tested` and a required qualifying count (3, matching Step 13), repeatedly invokes
  `aid-test-schedule-divergence-check.sh` (each call a genuinely fresh disposable clone) until
  EITHER 3 qualifying (`pass:true`, matching commit+fingerprint) runs are collected, OR a hard
  budget is exhausted — `max_attempts` (default 6 — twice the required count, tolerating some
  transient failures without being unbounded) AND `max_wall_clock_seconds` (default 3600 — one
  hour), whichever limit is hit first. On success, exits 0 and prints the 3 qualifying `run_id`s.
  On budget exhaustion without 3 qualifying passes, exits a distinct, non-zero code and writes
  `.aid-o/work/evidence/scheduler-divergence/campaign-<mode_tested>-<started_at>.json` —
  `{campaign_status: "evidence_incomplete", attempts_made, qualifying_runs_collected,
  budget_exhausted_reason: "max_attempts"|"max_wall_clock"}` — a terminal, PM-visible state,
  never a retry loop the caller has to interrupt manually. A single individual divergence check
  disagreeing (genuine `pass:false`, a real finding) counts against `max_attempts` but is never
  itself treated as `evidence_incomplete` — that state is reserved for "ran out of budget before
  collecting enough evidence," not for "found a real problem". **This campaign artifact is ALSO
  force-tracked via the same `git add -f` mechanism**, for the same reason as the per-invocation
  divergence artifacts above
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-schedule-divergence-check.bats`
  — identical-membership/identical-verdict case passes and writes `pass:true`; an injected
  single-unit-verdict difference blocks promotion, naming that unit, and writes `pass:false` with
  the diff populated; three consecutive invocations produce three distinct, non-overwriting
  `run_id`-keyed files; the written artifact validates against the schema above; **the written
  artifact is confirmed force-tracked (`git ls-files --error-unmatch`) in a disposable fixture repo
  replicating this repo's own blanket `.aid-o/` ignore — mirroring
  `test-catalog-force-tracked.bats`'s exact pattern**; **two genuinely concurrent invocations
  against the same commit (dispatched via background jobs, not sequential) produce two distinct,
  non-colliding files, proving the UUID/atomicity fix actually prevents the collision the
  idempotency-lens finding identified**
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-divergence-campaign.bats` — a
  campaign that collects 3 qualifying passes within budget exits 0; a campaign whose fixture always
  fails exhausts `max_attempts` and writes `campaign_status: "evidence_incomplete"` with
  `budget_exhausted_reason: "max_attempts"`, never looping past the configured limit; a campaign
  whose fixture is artificially slowed exhausts `max_wall_clock_seconds` instead, with the matching
  reason — both cases exit promptly, never blocking indefinitely

**Architecture Context:** The mandatory rollout gate (Constraint 8) — no promotion beyond
`sequential`/`observe_parallel` without this check passing on real data — now bounded so acquiring
that evidence is itself a terminating, PM-visible operation, never an open-ended retry loop.

**Implementation Detail:** Both runs happen inside the same disposable-worktree discipline as
Step 6 — never the live tree.

**Error Handling:** A budget-exhausted campaign is a distinct, terminal `evidence_incomplete`
outcome — Step 13's rollout gate treats it identically to "insufficient qualifying evidence" (forced
to `sequential`), but the campaign artifact itself preserves WHY (ran out of attempts vs. ran out
of time) for a human to decide whether to simply re-run the campaign or investigate flakiness
first.

**Edge Cases:**
- A campaign interrupted (process killed) mid-run leaves whatever qualifying artifacts it already
  collected in place (Step 7's own files are independently retained) — a subsequent campaign
  invocation counts pre-existing qualifying artifacts toward the same target before launching new
  attempts, never discarding real prior evidence.

**Dependencies:**
- Depends on: Step 6 — compares against the isolation-experiment's proposed batches
- Blocks: Step 8 — the report merge includes this gate's result

**Acceptance Criteria:**
- [ ] Identical membership/verdicts passes and writes a schema-valid `pass:true` artifact
- [ ] A single injected verdict difference blocks promotion, naming the exact unit/field, and
  writes a schema-valid `pass:false` artifact with the diff populated
- [ ] The artifact is written to a `run_id`-unique, retained path keyed by
  `commit_sha`/`mode_tested`/`run_id`, never overwritten and never auto-pruned
- [ ] Three consecutive invocations against the same commit produce three distinct files, each
  from a genuinely fresh disposable clone
- [ ] A bounded campaign collecting 3 qualifying passes within budget exits 0
- [ ] A campaign that exhausts `max_attempts` or `max_wall_clock_seconds` writes
  `campaign_status: "evidence_incomplete"` with the specific exhausted-budget reason, and exits
  promptly — never blocks past the configured limit

**Effort:** M
**AID Role:** qa

---

### Step 8: Deterministic report merge and cancellation policy

**Objective:** One deterministic combined report regardless of batch completion order, and the
required-gate-failure cancellation policy.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-scheduler-report.sh` — merges per-batch
  receipts (Step 4's schema) into ONE row of `aid-run-gates.sh`'s real, verified per-gate shape
  (**explicit adapter table added after a real C0 review found this mapping only asserted, never
  defined** — the real fields, confirmed at `aid-run-gates.sh:386,407,420,551`, are
  `{gate, result, reason?, exit_code, duration_ms, output, attempts}`): the scheduled
  `targeted_tests` gate's single row is synthesized from ALL its execution units' receipts as
  follows — `result`: `"pass"` only if every unit's `state` is `terminal_pass`; `"fail"` if any
  unit's `state` is `terminal_fail`/`timed_out`/`cancelled`, or if any unit could not be resolved
  to a terminal receipt at all. **Non-terminal detection, corrected after a real C0
  dep_api_grounding-lens finding (CP1-deep re-run) found `aid-job.sh cmd_collect`'s real
  non-terminal vocabulary is bifurcated, not uniformly `"lost"`**: `cmd_collect` always exits `3`
  when no terminal `result.json` exists, but the emitted `state` is `"in_flight"` (the owned
  process is still alive) or `"lost"` (the owned process is gone with no terminal record) —
  classification here is keyed off `cmd_collect`'s EXIT CODE (`3` = not yet terminal, covering
  BOTH `in_flight` and `lost` substates), never a literal string match on `"lost"` alone, so an
  `in_flight` unit at report-merge time is aggregated as `result:"fail"` exactly like a `lost` one
  — never silently excluded or treated as pass); `exit_code`: `0` if `result:pass` else `1`;
  `duration_ms`: wall-clock span from the earliest unit start to the latest unit end;
  `output`: a summary line naming the unit(s) that caused a non-pass result; `attempts`: `1` (retry
  semantics are the gate's own `max_retries` loop calling this whole scheduled dispatch again, not
  a per-unit retry inside this adapter). Units are sorted by stable `unit_id` before this
  aggregation, so two runs with reordered batch completion produce a byte-identical single row.
  A required-gate failure (this synthesized row) prevents batch N+1 from starting while
  already-dispatched batch-N work finishes (`fail_policy: stop_next_batch`, the default)
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-scheduler-report.bats` — two
  runs with reordered batch completion produce a byte-identical synthesized gate row; a required-
  gate failure in an early batch blocks a later batch while the concurrently-running batch's units
  still complete and are recorded; an unresolved unit in EITHER real non-terminal substate
  (`state:"in_flight"` or `state:"lost"`, both `cmd_collect` exit code `3`) is aggregated as
  `result:"fail"`, never silently excluded from the row

**Architecture Context:** Preserves `aid-run-gates.sh`'s existing required/advisory/skip verdict
model exactly — this step's whole job is producing ONE real-shaped gate row per scheduled batch,
so the rest of `aid-run-gates.sh`'s existing report/waiver/profile logic treats it exactly like any
other gate's row, never a parallel reporting format.

**Implementation Detail:** The adapter table above is the single source of truth for
scheduler-receipt → gate-row translation — no other step reinterprets this mapping.

**Error Handling:** A unit whose job record cannot be found at all (not merely non-terminal) is
also aggregated as `result:"fail"` with `output` naming the missing `unit_id` — never silently
omitted from the row.

**Edge Cases:**
- Two batches completing at the same instant — the stable `unit_id` sort guarantees deterministic
  aggregation regardless.

**Dependencies:**
- Depends on: Step 7 — includes the divergence-check result in the merged report
- Blocks: none (EPIC 2 closing step)

**Acceptance Criteria:**
- [ ] The synthesized gate row matches `aid-run-gates.sh`'s real field shape exactly
  (`gate/result/reason?/exit_code/duration_ms/output/attempts`), verified against the actual
  script's own row-assembly code, not an assumed shape
- [ ] Reordered batch completion produces a byte-identical synthesized row
- [ ] A required-gate failure blocks the next batch while already-running units are preserved
- [ ] An unresolved unit — `cmd_collect` exit code `3`, in EITHER real substate (`state:"in_flight"`
  or `state:"lost"`) — is aggregated as `result:"fail"`, matching `aid-job.sh`'s real "no evidence,
  never a definitive outcome" semantics — never silently dropped and never treated as pass

**Effort:** M
**AID Role:** backend

---

**EPIC 3: Steps 9-11 — `aid-select-tests.sh` refactor**

### Step 9: Selector emits execution units instead of always running them inline

**Objective:** Refactor `aid-select-tests.sh` so it CAN hand its selected set to the scheduler as
execution units, while its default (no-scheduler-configured) behavior stays exactly what it is
today — direct execution.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-select-tests.sh` (lines ~265-313) — add
  `--emit-units <file>` as an ADDITIONAL flag, combined with the script's existing, unchanged,
  mutually-exclusive `--base <ref>`/`--paths-file <file>` selection input (**exact invocation
  specified after a real C0 review found the combination was never spelled out**: the full
  supported invocation is `aid-select-tests.sh --base <ref> --emit-units <output-file>` or
  `aid-select-tests.sh --paths-file <file> --emit-units <output-file>` — `--emit-units` never
  replaces or implies a selection-input flag, it only changes what happens AFTER selection).
  When `--emit-units` is present: instead of running `bats`/`bash` directly, resolves the selected
  set through Step 2's membership verifier and writes execution units (Step 1's schema) to
  `<output-file>`; preserves the exact existing exit-code contract (`0/1/3/10`) — an exit-3
  unknown-production-path case still exits 3 even with `--emit-units` given, writing no units file;
  `--emit-units` is opt-in, never the default
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-select-tests-emit-units.bats` — the
  default (no flag) path matches pre-refactor behavior exactly on `exit_status`, `selected_tests`,
  `reasoning`, and `test_results`, compared via a normalized projection that excludes only the
  `_generated_at` timestamp field (**stated explicitly, not "byte-for-byte," after a real C0 review
  found the script's own JSON output includes a timestamp**); `--emit-units` produces
  membership-verified units matching the same selection; exit codes `0/1/3/10` unchanged in the
  default path

**Architecture Context:** This is the real, necessary code change P066 explicitly deferred — the
selector genuinely gains a second mode, not merely a doc reference to one.

**Implementation Detail:** `--emit-units` never itself invokes `aid-test-scheduler.sh` — it only
produces the file; the caller (Step 12's gate-runner integration) decides whether to schedule it.

**Error Handling:** `--emit-units` combined with an unknown-production-path case (exit 3) still
fails loudly — emitting units never silently reinterprets D-selector-1's fail-loud contract.

**Edge Cases:**
- `--emit-units` with zero selected tests writes an empty, schema-valid units file, not an error.

**Dependencies:**
- Depends on: Step 2 — resolves selected tests through the membership verifier
- Blocks: Step 12 — the gate-runner integration calls `--emit-units` when scheduling is enabled

**Acceptance Criteria:**
- [ ] The default (no-flag) path matches pre-refactor `aid-select-tests.sh` output exactly, per the
  normalized (timestamp-excluded) comparison above, for every currently-mapped case
- [ ] `--emit-units` produces membership-verified units for the identical selection
- [ ] Exit codes `0/1/3/10` are unchanged in the default path

**Effort:** L
**AID Role:** backend

---

### Step 10: Catalog↔selector convergence — approved-mapping-only, fail-closed on any gap

**Objective:** Complete the convergence P066 explicitly deferred: `aid-select-tests.sh` reads
P066's catalog `source_pattern_mappings[]` as its data source ONLY when
`mapping_approval.status == approved` (P066's Step 17 gate — never merely catalog-file presence),
with the existing hardcoded mapping as a **permanent** fallback for un-approved/absent-mapping
projects (never removed — the same script ships to every consumer project). **Escalation
behavior, added after PM feedback found the prior design risked a "green no-op"**: a changed
production-surface path that the approved mapping does not cover is NEVER silently treated as
"non-production, zero tests selected, pass" — it produces the same `unverifiable`/escalate outcome
as today's D-selector-1 `unknown_production` case, forcing a fall-back to the broader `full`
profile rather than a false green on `targeted` (corrected alongside Step 14's own escalation-target fix — see Step 14 for why `full`, not `standard`, is the real superset).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-select-tests.sh` (lines ~154-221) — `map_path_to_
  tests()`'s data source becomes: IF `.aid-o/config/test-catalog.yaml` exists AND its
  `mapping_approval.status == "approved"`, read `source_pattern_mappings[]` (P066's schema field,
  each row itself also `status: approved` — Step 17's per-row flip) as the real routing table.
  **Classification logic, corrected after a real, HIGH C0 finding (5th cross-provider Codex
  round) found the original design required a "mapping's own declared `production_surfaces`
  glob" field that does not exist anywhere in `test-catalog.schema.json`'s real
  `source_pattern_mapping` definition (`match_type`, `path_pattern`, `target_run_unit_ids`,
  `classification`, `precedence`, `status` — verified directly, no such field) — this step is
  rewritten to use ONLY those existing fields, no schema change of any kind**: for a changed path,
  evaluate every approved row's `match_type`/`path_pattern` (exact/prefix/glob, in `precedence`
  order) to find the first ROW that matches. If a matching row's `classification` is
  `unknown_production`, exit 3 (`unknown_production`), exactly like today's D-selector-1, never
  reclassified as "docs/non-production." If a matching row's `classification` is `production`,
  select its `target_run_unit_ids[]`. If a matching row's `classification` is
  `docs_non_production`, treat as non-production (no tests selected, exit 0). If NO row matches
  the changed path AT ALL, that is a separate, new outcome — see the `exit 11` bullet below —
  never silently folded into any of the three matched-row cases above. **Only** if the catalog is
  absent OR `mapping_approval.status != "approved"` does the script fall back to the existing
  hardcoded `case` statement, loudly logged as `catalog_fallback: true`
- Modify: `plugins/aid-orchestrator/scripts/aid-select-tests.sh` — same region; add a new exit
  path, `exit 11` (**new code, distinct from the existing `0/1/3/10` contract — never reuses `3`,
  which already has the specific "unknown production path under the HARDCODED mapping's own
  production surface" meaning**): "approved mapping present, but NO row's `match_type`/
  `path_pattern` matches this changed path at all" — i.e., the mapping genuinely has no opinion,
  determined purely by "zero rows matched," never by a separate glob field. This is reported to
  the caller (Step 14) as `mapping_gap`, distinct from `unknown_production`, and both cause the
  SAME externally-visible effect (escalate to `full` profile — see Step 14) but are logged with
  different reasons for a human to later resolve
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-select-tests-catalog-convergence.bats`
  — an approved-mapping path produces identical results to the pre-convergence hardcoded mapping
  for every existing case (regression); an UN-approved catalog (`mapping_approval.status:
  proposed`) exercises the permanent fallback exactly as if the catalog were absent; a changed path
  matching zero rows exits `11` (`mapping_gap`), never a silent zero-selection pass; a changed path
  matching a `docs_non_production`-classified row exits 0 with zero tests selected (a real, distinct
  case from `mapping_gap`); the 5 known gaps still exit `3` (`unknown_production`); classification
  is proven driven ONLY by `match_type`/`path_pattern`/`classification` — no schema field beyond
  P066's own already-shipped `source_pattern_mapping` definition is read anywhere in this step

**Architecture Context:** P066's Step 17 mapping-confirmation gate is what this step actually reads
— catalog presence or the whole-file `proposed`/`approved` tracking state is never sufficient by
itself; only the mapping-specific `mapping_approval.status: approved` unlocks real selection.

**Implementation Detail:** The fallback is never removed — matching P066's own corrected Constraint
4 reasoning (this is the identical script file shipped to every consumer project).

**Error Handling:** A catalog file present but with `mapping_approval.status != "approved"`
(including a missing `mapping_approval` object entirely) is treated exactly like catalog-absent —
the fallback fires, loudly logged — never a malformed-catalog error and never a partial read of
unconfirmed mapping rows.

**Edge Cases:**
- The 5 known selector gaps (`aid-plan-fsm.sh` etc., already surfaced as `recommendation:fix`
  findings by P066's Step 17) remain `unknown_production` classifications in the catalog — this
  step does not silently resolve them; they still produce exit 3 (D-selector-1) until a human maps
  them.
- **For any consumer project other than `aid-orchestrator` itself**, the hardcoded `case`-statement
  fallback is a structural no-op, not a meaningful safety net (its patterns name only THIS plugin's
  own scripts) — every changed path in such a project's own source tree, while the mapping remains
  un-approved, lands on the existing "non-production, no-op" classification branch. Real, useful
  selection for such a project begins only once it populates, reviews, and explicitly confirms its
  OWN mapping via P066's `/aid-audit-tests` + `aid-test-catalog-confirm-mapping.sh` flow — this is
  the documented bootstrap order, not a defect of this step. Once approved, ANY gap in that
  approved mapping's own coverage is `mapping_gap` (exit 11), never a silent pass.

**Dependencies:**
- Depends on: Step 9 — builds on the `--emit-units` refactor
- Blocks: Step 11 — the closing step force-verifies this repo's own catalog is populated for real

**Acceptance Criteria:**
- [ ] An approved-mapping path is a regression match to the pre-convergence hardcoded mapping for
  every existing case
- [ ] An un-approved catalog (mapping not confirmed) exercises the permanent fallback exactly as if
  absent, with a loud log event
- [ ] A changed path outside an approved mapping's coverage exits `11` (`mapping_gap`), never a
  silent zero-selection pass
- [ ] The 5 known gaps still produce exit 3, never silently resolved by this step

**Effort:** L
**AID Role:** backend

---

### Step 11: Populate this repository's own `source_pattern_mappings[]` as real, executable routing data

**Objective:** Close the loop for this repo's own dogfood: convert P066's read-only informational
snapshot into the real, PM-approved routing table this plan's Step 10 now executes.

**Authority-boundary reconciliation, added after a real C0 authority_runtime_matrix-lens finding
(CP1-deep re-run) found no such note existed here, unlike every other similar tension in this
plan** (`resource_locks` in Step 1, `scheduler.mode` in Step 13): this step modifies
`aid-test-catalog-approve.sh`, which the Scope section names as part of P066's "catalog approval
boundary" — deliberately, not accidentally. The distinction: this step adds a strictly additive
PRE-approval check (running the selector-snapshot script and requiring zero-gap agreement before
the approval write happens) — it never changes what `mapping_approval.status: approved` MEANS,
never changes P066's own catalog-approval schema, and never bypasses or shortcuts P066's own
mapping-confirmation gate (`aid-test-catalog-confirm-mapping.sh`, untouched). "Never redefines P066's
approval boundary" (Scope) means exactly that semantic contract stays fixed — not that no file
under that boundary may ever gain an additional precondition.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-test-catalog-approve.sh` — the P066 script;
  re-grounded against its ACTUAL shipped signature (`--proposed <path> --project-root <path>` only
  — the E3 whole-EPIC-3 fix-loop removed `--approved-path` entirely; the approved catalog target is
  now always the fixed `${project_root}/.aid-o/config/test-catalog.yaml`). Extend the PM-invoked
  approval action to additionally run P066's own read-only selector-snapshot script
  (`aid-test-catalog-selector-snapshot.sh`, now repurposed as real seed data, not merely
  informational) and re-verify zero-gap agreement before approving. Note: mapping confirmation
  itself stays a SEPARATE, later step — `aid-test-catalog-confirm-mapping.sh` (also re-grounded
  during P066: now takes `--project-root`, not `--catalog`, and re-stages via `git add -f` after its
  own write) — this step only seeds `source_pattern_mappings[]` rows as `status: proposed`; it does
  not itself confirm them
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-selector-mappings-real-seed.bats` —
  approving this repo's catalog produces `source_pattern_mappings[]` rows that Step 10's convergence
  actually reads and that reproduce every current `aid-select-tests.sh` selection result

**Architecture Context:** Closes P066's own Step 17 forward-reference ("captured as read-only
informational snapshot data; the follow-up plan may later choose to make it executable").

**Implementation Detail:** No new parsing logic — reuses P066's existing snapshot script, only its
consumption changes (from informational-only to real seed).

**Error Handling:** A gap found at approval time (new path added since P066's original snapshot)
blocks approval, named explicitly.

**Edge Cases:** N/A beyond the above.

**Dependencies:**
- Depends on: Step 10 — the convergence logic this step's seed data feeds
- Blocks: none (EPIC 3 closing step)

**Acceptance Criteria:**
- [ ] This repository's own approved catalog's `source_pattern_mappings[]` reproduces every current
  `aid-select-tests.sh` selection result exactly
- [ ] A newly-introduced gap at approval time blocks approval, named explicitly

**Effort:** S
**AID Role:** backend

---

**EPIC 4: Steps 12-15 — Real gate-runner and config-path integration**

### Step 12: Real config-generation path integration — the `targeted_tests` gate and scheduler block

**Objective:** Make BOTH a real selector-backed gate AND the scheduler config actually reachable by
a consumer project — for a FRESH project, through the path it actually uses
(`defaults/execution-stacks/*.yaml` + `compose_execution_yaml`, never the plugin's own dogfood-only
`defaults/execution.yaml`), and — **scope widened a second time, after PM feedback found existing
projects had no path to this config at all** — for an EXISTING project's already-generated
`execution.yaml`, through a new, explicit, non-invasive upgrade command sharing the identical
renderer. **Scope widened the first time after a real C0 review found none of the 5 stack files
define any selector-backed gate at all** — without this, there is no gate anywhere for a scheduler
to ever dispatch through in any project, fresh or existing.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (lines ~104-119) — in
  `resolve_placeholders()`, add `{plugin_path}` as a new recognized substitution token
  (**distributable-invocation fix, added after a real C0 review found generated gate commands
  would reference a bare
  script name with no PATH entry pointing at it**), resolved from `.aid-o/config/plugin.yaml`'s
  `plugin_path` field (the absolute path `/aid-init` already discovers and writes, per
  `commands/aid-init.md:326-337`) — falls back to `$AID_PLUGIN_PATH` if the config file is absent;
  an unresolvable plugin path is the same fail-loud "unknown token" error the function already
  raises for any other unresolvable placeholder. **Exact resolution mechanism, named explicitly
  after two independent lens findings (L2 feasibility, C0 dep_api_grounding — both CP1-deep
  re-run) found this step didn't pin down HOW `resolve_placeholders()` would gain this new
  dependency**: the real, current `resolve_placeholders()` (`aid-run-gates.sh:105-122`) is a pure
  string-substitution function taking 5 positional args (`cmd, epic, run, base, plan`) with no
  config-file/env-reading logic of its own, called from ONE site (line ~415). This step gives it a
  6th positional argument, `plugin_path`, resolved ONCE by `run_all_gates()` (reading
  `.aid-o/config/plugin.yaml`/`$AID_PLUGIN_PATH` itself, exactly mirroring how `base_commit`/
  `plan_path` are already resolved by the caller today) and passed in at the existing call site —
  `resolve_placeholders()` itself gains ZERO new file/env-reading logic; it remains a pure
  substitution function over one additional argument, never a function that reads its own
  environment
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` (lines ~293) — in
  `compose_execution_yaml`, after composing the per-stack `gates:` blocks, additionally render TWO
  stack-independent additions into every generated `execution.yaml`: (a) a `targeted_tests` gate
  entry — `command: "{plugin_path}/scripts/aid-select-tests.sh --base {base_commit}"` (the
  `{plugin_path}` token, never a bare command name — mirroring this repo's own real, already-
  working self-host gate's command, but resolvable outside this repo), `required: false`; and (b) a
  `test_audit.scheduler` block, defaulting to `mode: sequential` and an empty
  `resource_locks: {}` map (the one authoritative location for both fields — see Step 1/Step 5's
  corrected authority resolution; `test-audit.yaml`'s reserved root `resource_locks` field is never
  read or written here). Both are additive to every generated project file, never altering an
  existing stack's `gates:` block
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh`
  (`render_gate_profiles_block`) — add the new `targeted_tests` gate to the generated `targeted`
  profile's `include[]` list (the profile that already exists in every generated project)
- Create: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh`
  (new function `render_test_audit_scheduler_block`) — **factored out explicitly, added after PM
  feedback found existing projects had no path to this new config at all** (fresh `/aid-init` on a
  brand-new project is the ONLY path the original draft supported; every project that already has
  an `execution.yaml` — meaning almost every real consumer project — would never receive the
  `targeted_tests` gate or the scheduler block, since `/aid-init` deliberately never rewrites an
  existing `execution.yaml`). This function renders EXACTLY the same `targeted_tests` gate +
  `test_audit.scheduler` block text that `compose_execution_yaml` (above) already emits for a fresh
  project — used by BOTH the fresh-generation path above and the new upgrade command below, so the
  two paths can never drift into two different renderings of the "same" block
- Create: `plugins/aid-orchestrator/scripts/aid-init-upgrade-test-audit.sh` — the explicit,
  non-invasive upgrade path for an EXISTING project's `execution.yaml`: (1) parses the existing
  file with `yq`, detects whether a `targeted_tests` gate and/or `test_audit.scheduler` block are
  already present (by key, not by exact text — a hand-edited `scheduler.mode` value still counts
  as "already present," never overwritten); (2) for whichever piece is missing, calls the SAME
  `render_test_audit_scheduler_block` function used by fresh generation, and prints a concrete,
  human-readable diff (`--- current\n+++ proposed`) of exactly what would be appended — no other
  line of the file is touched, ever; (3) computes `diff_hash` (sha256 of the exact proposed
  addition); (4) writes ONLY on an explicit `--confirm-upgrade <diff_hash>` invocation whose hash
  matches what was just shown — a missing or mismatched hash refuses and re-prints the diff,
  identical in spirit to Step 17's mapping-confirmation gate in P066; (5) the write is a pure
  append (mirroring `commands/aid-init.md`'s existing `append_gate_profiles_block` precedent) —
  every byte of the file before the append point is preserved exactly
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-compose-execution-yaml-scheduler-block.bats`
  — a fresh `/aid-init` run on each of the 5 stacks produces both the `{plugin_path}`-qualified
  `targeted_tests` gate (in the generated `targeted` profile) and a `test_audit.scheduler.mode:
  sequential` block; `resolve_placeholders` correctly substitutes `{plugin_path}` from a fixture
  `plugin.yaml`; re-running `/aid-init` on an already-customized project's `execution.yaml` never
  overwrites either a hand-edited `scheduler.mode` or a hand-edited `targeted_tests` gate; the
  fresh-generation block text and the upgrade-command's rendered block text (from
  `render_test_audit_scheduler_block`) are byte-identical, proving one shared renderer, not two
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init-upgrade-test-audit.bats` — a
  fixture `execution.yaml` that already has hand-edited, unrelated gates (and, in one case, an
  already-hand-edited `test_audit.scheduler.mode: observe_parallel`) is upgraded: every byte outside
  the appended block is verified byte-identical before/after; the diff preview is shown before any
  write; a missing/wrong `--confirm-upgrade` hash writes nothing; a correct hash appends exactly the
  missing piece(s) and never touches an already-present `test_audit.scheduler` block, hand-edited
  or not

**Architecture Context:** Directly resolves the two most severe C0 findings together — the old
draft (a) modified a file consumer projects never receive and referenced a script with no
resolvable path outside this repo, and (b) had no real gate for the scheduler to ever dispatch
through; this step fixes all three in the one real generator function plus the one real
placeholder-resolution function.

**Implementation Detail:** Both renders are additive-only, following the same non-destructive
principle as the existing `gate_profiles` append logic in `commands/aid-init.md`. `{plugin_path}`
resolution reuses the exact discovery `/aid-init` already performs — no new plugin-location logic
is invented.

**Error Handling:** A project whose `execution.yaml` already has a `targeted_tests` gate or a
`test_audit.scheduler` block (from a prior `/aid-init` run) is never overwritten — idempotent
re-run. An unresolvable `{plugin_path}` (missing `plugin.yaml` AND missing `$AID_PLUGIN_PATH`) fails
the gate closed with the same explicit "unknown token" message pattern as any other unresolved
placeholder — never silently runs a bare, unqualified command name.

**Edge Cases:**
- A project with zero detected stacks (the `${#clean_stacks[@]} == 0` case
  `aid-init-execution-yaml.sh` already handles) still gets both additions, since neither is
  stack-specific.
- **Consumer-project catalog bootstrap, stated honestly after a real C0 review found the "fresh
  consumer project" premise itself incomplete**: `aid-select-tests.sh`'s hardcoded
  `map_path_to_tests()` classification is inherently `aid-orchestrator`-specific (its `case`
  patterns name THIS plugin's own scripts under `scripts/`/`defaults/`) — for any OTHER consumer
  project, every one of that project's own changed paths falls to the "non-production, no-op"
  branch, so the `targeted_tests` gate silently selects nothing until that project has run its own
  `/aid-audit-tests` → catalog-approval flow (P066) at least once. This is not a bug this step
  fixes; it is the real, honest bootstrap order — the `targeted_tests` gate is added to every
  project unconditionally (harmless no-op until a catalog exists), and Step 19's E2E scenario
  explicitly runs that bootstrap first rather than assuming a fresh project already has useful
  routing data.

**Dependencies:**
- Depends on: Step 9 — the `targeted_tests` gate's command is `aid-select-tests.sh`, whose `--emit-units` mode that step adds
- Blocks: Step 13 — the rollout gate governs the `execution.yaml` config this step generates

**Acceptance Criteria:**
- [ ] A fresh `/aid-init` on every one of the 5 stacks produces a real, `{plugin_path}`-qualified
  `targeted_tests` gate in the generated `targeted` profile, plus a `test_audit.scheduler.mode:
  sequential` block
- [ ] Re-running `/aid-init` never overwrites an already-customized `scheduler.mode` or an
  already-customized `targeted_tests` gate
- [ ] The zero-detected-stacks case still receives both additions
- [ ] `{plugin_path}` resolves correctly from a fixture `.aid-o/config/plugin.yaml` and fails closed
  (never runs a bare command) when both it and `$AID_PLUGIN_PATH` are absent
- [ ] An EXISTING project's `execution.yaml` can be upgraded via the new explicit command: the diff
  preview is shown before any write, the write happens only on a matching `--confirm-upgrade` hash,
  and every byte outside the appended block is preserved exactly
- [ ] The fresh-generation and upgrade paths render byte-identical block text from the one shared
  `render_test_audit_scheduler_block` function

**Effort:** L
**AID Role:** backend

---

### Step 13: Rollout activation gate

**Objective:** Wire the staged rollout (Constraint 8) so a project can only reach `observe_parallel`/
`parallel` after Step 7's divergence gate has passed on that project's own real data, with ONE
authoritative config source.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-scheduler-rollout-gate.sh` — reads EVERY divergence-
  evidence artifact under `.aid-o/work/evidence/scheduler-divergence/` matching the CURRENT commit,
  the CURRENT catalog fingerprint set, AND — **mode-staging fix, added after a real C0 review found
  3 `observe_parallel`-tested artifacts could incorrectly unlock `parallel` directly, skipping the
  required staged rollout** — a `mode_tested` matching a STRICT staging rule: unlocking
  `observe_parallel` requires 3 qualifying artifacts with `mode_tested: observe_parallel`;
  unlocking `parallel` requires BOTH the 3 qualifying `observe_parallel` artifacts (proving the
  prior stage already passed) AND 3 SEPARATE qualifying artifacts with `mode_tested: parallel` —
  `observe_parallel` evidence alone never unlocks `parallel`, and `parallel`-mode evidence without
  prior qualifying `observe_parallel` evidence is also insufficient (Step 7's `worktree_kind` and
  `mode_tested` fields, already in the schema, are what this check reads — no schema change
  needed, only this gate's comparison logic). A mismatch on commit, fingerprint, OR the staging
  rule above is treated as absent; fewer than the required count for the TARGET configured mode is
  forced to `sequential`. **Configuration authority, resolved explicitly after a real C0 review
  found two incompatible mode sources named**: the ONE authoritative mode value is
  `execution.yaml`'s `test_audit.scheduler.mode` (the same file Step 12 writes into and
  `aid-run-gates.sh` already reads for everything else) — P066's `test-audit.yaml` remains
  authoritative only for its own audit-time settings (`budget_minutes_default`,
  `max_read_only_audit_agents`, `allowed_runners`), never for `scheduler.mode`, which this plan owns
  exclusively in `execution.yaml`. This script is a pure function called directly by Step 14's
  `aid-run-gates.sh` change, BEFORE that code path decides whether to invoke the scheduler — it is
  never a standalone check nothing calls
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-scheduler-rollout-gate.bats` — a
  config claiming `observe_parallel` with zero matching artifacts is forced back to `sequential`,
  with an explicit warning; with exactly 2 matching `pass:true` artifacts (one short of the
  required 3) is ALSO forced to `sequential`, naming the shortfall; with 3 matching `pass:true`
  `observe_parallel`-tested artifacts is allowed through to `observe_parallel`; **3 qualifying
  `observe_parallel`-tested artifacts alone, with a config claiming `parallel`, is forced back to
  `observe_parallel` (not `parallel`) — proving cross-mode evidence reuse is rejected**; only with
  3 qualifying `observe_parallel` artifacts AND 3 separate qualifying `parallel`-tested artifacts is
  `parallel` allowed; a config with only STALE (fingerprint-mismatched) artifacts, however many, is
  treated as zero qualifying, never stale-but-acceptable; a single `pass:false` among the candidate
  set disqualifies that artifact from the count, never averaged with passing ones

**Architecture Context:** Prevents a project from configuring its way past the divergence gate by
simply editing a YAML file — the gate is enforced in code, called from the one real dispatch point
(Step 14), not merely documented as a recommendation.

**Implementation Detail:** The fingerprint-set check ties the divergence evidence to the exact
catalog state it was measured against — a catalog change invalidates prior evidence.

**Error Handling:** Missing/stale evidence fails closed to `sequential`, never fails open to
`observe_parallel`/`parallel`.

**Edge Cases:**
- Evidence measured against a since-changed catalog fingerprint is treated as absent, not stale-
  but-acceptable.

**Dependencies:**
- Depends on: Step 12 — reads the `execution.yaml` config that step generates; **Step 7 (added
  after a real C0 finding, 5th cross-provider Codex round, found this edge missing) — this gate
  reads divergence-evidence artifacts Step 7's scripts are the sole producer of**
- Blocks: Step 14 — the gate-runner dispatch calls this gate before scheduling

**Acceptance Criteria:**
- [ ] A config claiming `observe_parallel`/`parallel` with fewer than 3 qualifying (passing,
  commit-and-fingerprint-matching, mode-`mode_tested`-matching, distinctly-`run_id`'d) divergence
  artifacts for the TARGET mode is forced to `sequential` behavior, with an explicit warning naming
  the shortfall
- [ ] 3 qualifying `observe_parallel`-tested artifacts unlock `observe_parallel` but never `parallel`
- [ ] `parallel` requires 3 qualifying `observe_parallel`-tested artifacts AND 3 separate qualifying
  `parallel`-tested artifacts — cross-mode evidence substitution is rejected and tested explicitly
- [ ] `execution.yaml`'s `test_audit.scheduler.mode` is confirmed (grep-verified) as the only mode
  source this gate or Step 14 ever reads — `test-audit.yaml` is never consulted for this key

**Effort:** M
**AID Role:** security

---

### Step 14: `aid-run-gates.sh` scheduler dispatch

**Objective:** The step three C0 rounds found missing entirely: make `aid-run-gates.sh` actually
call Step 13's rollout gate and, when it unlocks, dispatch the real `targeted_tests` gate (Step 12)
through the scheduler.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (lines ~186) — in `run_all_gates()`,
  when the running gate is `targeted_tests` (the real gate Step 12 adds to generated projects),
  call Step 13's `aid-scheduler-rollout-gate.sh` FIRST; only if it returns an unlocked mode
  (`observe_parallel`/`parallel`), call the exact, fully-specified command (**added after a real C0
  review found the invocation incomplete**) `{plugin_path}/scripts/aid-select-tests.sh
  --base "$base_commit_resolved" --emit-units
  ".aid-o/work/evidence/${epic_id}/${run_id}/gates/targeted-units.json"` (`$base_commit_resolved`
  is the SAME variable `run_all_gates()` already resolves at lines ~308-320 for the `{base_commit}`
  token — no new resolution logic). **Escalation handling, added after PM feedback found a coverage
  gap could otherwise pass silently with zero selected tests**: exit codes `3` (`unknown_production`)
  and `11` (`mapping_gap`, Step 10's new code) are NEVER treated as an ordinary gate failure and
  NEVER as a pass. **Result-value contract, corrected after a real, MEDIUM C0 finding (5th
  cross-provider Codex round) found the ORIGINAL design's new `result: "escalated"` value would
  break the EXISTING, real gate-result contract and its own real test
  (`test-aid-run-gates.bats`'s "run-all targeted_tests gate: unknown production path (D-selector-1
  unverifiable) surfaces as plain gate result 'fail' — no new result value") — that existing test
  is preserved byte-for-byte, never migrated: `targeted_tests`'s row keeps the EXISTING
  `result: "fail"` (never a new `"escalated"` enum value), with `reason` naming the exact exit
  code and path that triggered it exactly as it already does today. Escalation is recorded as
  PURELY ADDITIVE metadata instead — a new, optional sibling field on that SAME row,
  `escalation: {triggered: true, exit_code: 3|11, path: "<the triggering path>"}` — never a
  replacement for `result`, so no existing reader of `result` (test, waiver logic, FSM, release
  policy) needs to learn a new enum value it doesn't already handle.** `aid-run-gates.sh`
  additionally runs the full **`full`** profile's
  gate set once, within this same invocation, as the trustworthy substitute — the run's overall
  verdict is never a bare pass on `targeted` alone when `escalated` fired. **Escalation TARGET
  profile, corrected after a real L1 lens finding (CP1-deep re-run) found `standard` is (a) never
  generated by `compose_execution_yaml`/`render_gate_profiles_block` for any real consumer project
  (only `targeted`/`full` are emitted) and (b) even in THIS repo's own hand-crafted
  `execution.yaml`, `standard` already includes `targeted_tests` itself, making "escalate from
  targeted to standard" a self-referential no-op exactly where `standard` happens to exist at
  all — escalation now always targets `full`, which genuinely runs the unconditional broader gate
  set (matching this repo's own documented `quick < targeted < standard < full < release` rank
  order, where `full` — not `standard` — is the real superset of `targeted_tests`'s coverage), and
  is guaranteed to exist for every project `/aid-init` ever generates.** Only on
  `aid-select-tests.sh` exit 0 is the written `targeted-units.json` passed to `aid-test-scheduler.sh`
  (Step 5) instead of the single sequential command execution; a genuine command failure (exit `1`
  or `10`) is still treated exactly like today's gate-command failure — otherwise (rollout gate
  returns `sequential`, the default), behavior is completely unchanged from today.

  **Escalation re-run merge mechanism, added after a real L1 lens finding found none was
  specified** (a real risk against the existing `processed == gate_count` integrity assert at
  `aid-run-gates.sh:579`): the escalation's `full`-profile re-run is a SECOND, entirely separate
  `run_all_gates()`-style pass, invoked with `--profile full` against the SAME `epic_id`/`run_id`,
  producing its OWN complete `gates_json` object. The two objects are merged by a new,
  named function `merge_escalation_report(targeted_gates_json, full_gates_json)`
  (`lib/aid-run-gates-report.sh`, new file) that: (1) takes every gate row from the `full` pass
  verbatim (this becomes the actual verdict-bearing report — `full`'s own `processed`/`gate_count`
  bookkeeping is internally self-consistent because it is one complete, uncontaminated
  `run_all_gates()` invocation), and (2) adds a SEPARATE, additive top-level key,
  `escalation: {triggered_by: "targeted_tests", reason: "<exit code + path>",
  targeted_run: <targeted_gates_json>}`, preserving the original `targeted` attempt's own report
  as an informational nested object, never merged row-by-row into the same gate namespace and
  never touching the `full` pass's own `processed`/`gate_count` invariant. This means the existing
  integrity assert continues to apply to exactly one real, complete profile run's rows at a time —
  never a hybrid of two passes' rows sharing one namespace
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (line ~457) — at the existing
  `gate_baseline_update` call site. **Call-site wiring, added after a real C0 review found Step
  3's schema extension had no caller ever passing it.** Pass the resolved mode
  (`sequential`/`observe_parallel`/`parallel`, from this same step's rollout-gate result) as the
  new 7th argument on every `gate_baseline_update` call — not only for `targeted_tests`, so a
  future scheduler-eligible gate never silently records `sequential` context by omission; every
  other gate's call (unaffected by this plan) passes `sequential` explicitly, matching its true
  execution mode
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates-scheduler-dispatch.bats` —
  with the rollout gate returning `sequential` (the default, no divergence evidence yet),
  `aid-run-gates.sh`'s behavior and output for `targeted_tests` are provably unchanged from
  pre-this-step (compared via a normalized projection excluding wall-clock timestamps/durations —
  **corrected after a real C0 review found "byte-for-byte" untestable given real timestamp
  fields**; every other field must match exactly); with the rollout gate unlocked (real, passing
  divergence evidence present), the scheduler path actually executes and its merged report appears
  correctly folded into `gates_report.json`; a scheduled `targeted_tests` run's baseline sample is
  recorded with `concurrency_context: observe_parallel` (or `parallel`), never silently defaulting
  to `sequential`, verified by reading the real baseline file after the run; an
  `aid-select-tests.sh` fixture exiting `3` or `11` produces the EXISTING `result: "fail"` for
  `targeted_tests` (never a new enum value — `test-aid-run-gates.bats`'s existing
  "unknown production path... surfaces as plain gate result 'fail'" test is re-run unmodified and
  still passes) with the new additive `escalation: {triggered:true, exit_code, path}` sibling
  field populated, AND a real, executed `full`-profile gate set within the same run — never a
  bare pass with zero units selected

**Architecture Context:** This is the constraint 5 obligation made concrete — the exact place the
prior three C0 rounds found never existed — now correctly gated by Step 13's rollout check rather
than a bare config read.

**Implementation Detail:** Every gate not named `targeted_tests` is entirely unaffected by this
change — the modification is scoped to the one real gate Step 12 adds.

**Error Handling:** A scheduler-path failure (e.g., `aid-test-scheduler.sh` crashes) is treated
exactly like a gate-command failure today — reported, retried per the gate's own `max_retries`,
never silently swallowed.

**Edge Cases:**
- A project with an unlocked mode but no populated catalog — `aid-select-tests.sh --emit-units`
  falls back per Step 10's permanent-fallback logic, and the scheduler receives the
  hardcoded-mapping-derived units, unchanged in membership from today's direct-run behavior.

**Dependencies:**
- Depends on: Step 13 — calls the rollout gate before any scheduling decision; **Step 3 (added
  after the same L2 lens finding above) — this step's `gate_baseline_update` call site is the real
  consumer of Step 3's new 7th `concurrency_context` argument; Step 3 must land first**; **Step 5,
  Step 8, and Step 9 (added after a real C0 finding, 5th cross-provider Codex round, found these
  edges missing despite this step directly invoking all three) — this step calls Step 5's
  `aid-test-scheduler.sh`, folds in Step 8's `merge_escalation_report`/report-adapter output, and
  invokes Step 9's `aid-select-tests.sh --emit-units`; all three must exist before this step's own
  dispatch logic can be implemented**
- Blocks: Step 15 — the remediation evidence bundle exercises this real dispatch path

**Acceptance Criteria:**
- [ ] With the rollout gate returning `sequential` (default), `aid-run-gates.sh`'s
  `targeted_tests` behavior matches pre-this-step exactly on every field except wall-clock
  timestamps/durations (an explicit, defined normalized comparison — never an unqualified
  "byte-for-byte" claim)
- [ ] With the rollout gate unlocked, the scheduler path actually executes and its merged report is
  correctly folded into `gates_report.json`
- [ ] Every gate other than `targeted_tests` is completely unaffected by this change
- [ ] A scheduled `targeted_tests` sample is recorded with the real `concurrency_context` it ran
  under; every other gate's sample is recorded with `concurrency_context: sequential` explicitly
- [ ] Exit `3`/`11` from `aid-select-tests.sh` produces the EXISTING `result: "fail"` (never a new
  enum value) with the additive `escalation: {...}` field populated, and a real, executed
  `full`-profile substitute within the same run — never a silent pass with zero units

**Effort:** L
**AID Role:** backend

---

### Step 15: `bats_all` remediation evidence (this repository) — `plan_diff` explicitly out of scope

**Objective:** Produce the actual measured evidence for lifting this repository's own `bats_all`
quarantine — the first real consumer of everything Steps 1-14 built. **Scope narrowed after a real
C0 review found `bats_all` and `plan_diff` were conflated as one problem**: only `bats_all` carries
a `quarantine:` block in `.aid-o/config/execution.yaml`; `plan_diff` has none, and its documented
root cause (its outer gate timeout equals its own internal per-AC timeout, so nested `bats`
invocations exhaust the budget — see `docs/plans/P066-test-portfolio-audit-scheduler-remediation.md`
§1.3) is an `aid-plan-diff.sh` timeout-architecture problem, not a scheduling/parallelism problem —
nothing in this plan touches `aid-plan-diff.sh`, its timeout, or its `execution.yaml` gate
definition. Removing `bats_all`'s `quarantine:` block itself remains a separate PM action
(Constraint 9); `plan_diff`'s remediation is out of this plan's scope entirely and belongs to a
separately grounded fix (its own small, targeted change to `aid-plan-diff.sh`'s timeout handling,
not a P069 deliverable).

**Files:**
- Create: `plugins/aid-orchestrator/defaults/schemas/quarantine-remediation-evidence.schema.json`
  — **new, named artifact added after a real C0 review found Step 18's `evidence_ref` had no
  defined producer.** `gate_id: "bats_all"`, `membership_agreement` (`{run_units_expected,
  run_units_observed, cross_check_sources[]}` — `run_units_expected` is ALWAYS re-derived from the
  live `.aid-o/config/test-catalog.yaml` at measurement time, never a hardcoded constant: this
  plan's own re-grounding pass found P066's originally-planned "88" had already drifted to 83 by
  P066's own release, confirming a fixed number in a schema/plan is unreliable by construction),
  `shared_state_findings[]`, `streamed_diagnostics_
  proof` (boolean + example log path), `resume_without_orphan_proof` (boolean + evidence path),
  `measured_runtime_ms` (real, not invented), `plan_diff_scope_note` (fixed string confirming
  out-of-scope), `evaluated_at`
- Test: `plugins/aid-orchestrator/scripts/tests/test-integration-quarantine-remediation-evidence.sh`
  — in a disposable clone, runs this repo's real, current `run_units` set (83 as of P066's release
  — read from the live catalog at run time, never hardcoded) sequentially and via
  `observe_parallel`, collects Step 7's divergence result, Step 3's concurrency-annotated timing,
  and the 7-file lock-audit result (from P066 Step 7) into a schema-valid evidence bundle, written
  to the fixed, retained path
  `.aid-o/work/evidence/quarantine-remediation/bats_all-<commit_sha>.json` (this exact path is what
  Step 18's `evidence_ref` cites), addressing every `bats_all`-specific quarantine-exit criterion
  from the original roadmap (`docs/plans/P066-test-portfolio-audit-scheduler-remediation.md` §6):
  membership agreement, no shared-state corruption, streamed failure diagnostics, resume-without-
  orphan/duplicate, and a measured, PM-reviewable runtime figure (replacing the ~29-70 min baseline
  with real post-remediation data). The bundle explicitly states `plan_diff` is out of scope and
  unaddressed by this plan, rather than silently omitting it. **Force-tracked into git immediately
  after the write (same `git add -f` mechanism and same L3-lens-finding rationale as Step 7's
  divergence artifacts above)** — confirmed by the same `git ls-files --error-unmatch` check
  pattern, so this bundle survives a fresh checkout for Step 18's later `evidence_ref` lookup

**Architecture Context:** This is the plan's payoff for the `bats_all` half of the incident this
session started from — real measured evidence, not a repeated assertion that things should be
faster. `plan_diff` remains genuinely unresolved after this plan and must be named as such, not
implied fixed.

**Implementation Detail:** No target runtime number is asserted as a pass/fail AC here — the
evidence bundle reports the real measured number for PM review, per this plan's own Constraint 9
and the original roadmap's correction that the "≤20 min" figure is the PM's own bar to ratify, not
an invented AC.

**Error Handling:** Any divergence or shared-state finding from Steps 6/7 is included in the bundle
as a blocking finding for quarantine-lift, not silently smoothed over.

**Edge Cases:** N/A beyond the above.

**Dependencies:**
- Depends on: Step 14 — requires the rollout gate to have genuinely unlocked `observe_parallel` for this repository's own real run
- Blocks: Step 17 — the E2E's full-path proof is exercised on this same real data

**Acceptance Criteria:**
- [ ] The evidence bundle addresses every `bats_all`-specific quarantine-exit criterion from the
  original roadmap explicitly, with real measured data, not assertions
- [ ] No invented runtime target is asserted as this plan's own AC — the real number is reported for
  PM ratification
- [ ] Any divergence/shared-state finding is included as a blocking item, not smoothed over
- [ ] The bundle explicitly states `plan_diff` is out of scope for this plan, never silently
  omitted or implied resolved

**Effort:** M
**AID Role:** qa

---

**EPIC 5: Steps 16-19 — Rollout, close-out, and full-path E2E**

### Step 16: Docs and enforcement registry for this plan's real integration points

**Objective:** Document and register the real code paths this plan adds — not a repeat of P066's
own already-registered guards.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — add rows (full required
  field set: `id`/`type`/`source`/`description`/`instruction`/`severity`/`surface`/`status`/
  `verdict`/`test`) for: `id: scheduler_unknown_parallelism_sequential` (source: Step 5's scheduler;
  severity: blocking; surface: internal-guard), `id: scheduler_rollout_requires_divergence_evidence`
  (source: Step 13's rollout gate; severity: blocking; surface: internal-guard), `id:
  scheduler_no_second_job_supervisor` (source: Constraint 4 + Step 1; severity: advisory; surface:
  internal-guard)
- Modify: `plugins/aid-orchestrator/README.md` — document the scheduler's opt-in config and rollout
  stages
- Test: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-scheduler.sh` — each row's
  `source` resolves to real code; full required field set present

**Architecture Context:** Same registry-completeness discipline P066's own Step 19 established.

**Implementation Detail:** N/A.

**Error Handling:** N/A.

**Edge Cases:** N/A.

**Dependencies:**
- Depends on: Step 14 — documents the real gate-runner dispatch and rollout gate together
- Blocks: Step 17 — the E2E proof exercises the fully-documented, registry-complete plan

**Acceptance Criteria:**
- [ ] All 3 new rows exist with resolving `source` citations and the full required field set

**Effort:** S
**AID Role:** backend

---

### Step 17: E2E — the mandatory full real-path proof

**Objective:** Per the PM's explicit instruction, prove the REAL path end-to-end: configured
profile → gate runner → selected execution units → scheduler → per-unit receipts → the same
aggregated verdict. Config, documentation, or a registry row never substitute for this proof.
**Moved earlier in EPIC 5 after a real C0 review found the original ordering circular** — this
step's evidence must exist BEFORE the PM quarantine-lift decision (Step 18) can honestly cite it.

**Files:**
- Create: `.aid-o/work/evidence/e2e-full-path-proof/<run_id>.json` — named output artifact, added
  after a real C0 review found Step 18's `e2e_evidence_ref` had no defined producer; one file
  per E2E run, containing: `scenario` (`observe_parallel_full_path|sequential_regression|
  self_host_bundle_refresh`), `pass` (boolean), `stages_verified[]` (the named real stages from the
  scenario below, each with its own pass/fail), `commit_sha`, `evaluated_at`. The most recent
  `observe_parallel_full_path` file with `pass:true` at the plan's release commit is what Step 18's
  `e2e_evidence_ref` cites. **Force-tracked into git immediately after each write (same `git add -f`
  mechanism and rationale as Step 7/15's evidence artifacts — a real L3 lens finding, CP1-deep
  re-run, found this exact path family among those with no force-tracking wiring at all)**,
  verified the same way, so Step 18's `e2e_evidence_ref` lookup works from a fresh checkout too.

**E2E Scenarios:**
- A freshly `/aid-init`-ed fixture project (one of the 5 stacks, containing real fixture tests of
  its own — not this plugin's tests). Step order, spelled out to avoid any ambiguity: (1) the
  fixture project FIRST runs the real P066 `/aid-audit-tests` bootstrap (its own audit → catalog
  proposal → explicit approval/force-track via `aid-test-catalog-approve.sh`), producing a real,
  approved `run_units[]` catalog for the fixture's own tests. **Mapping-generation scope, narrowed
  after a real, HIGH C0 finding (5th cross-provider Codex round) found P066's
  `aid-test-catalog-selector-snapshot.sh` is dogfood-only — it parses THIS plugin's own
  `aid-select-tests.sh` case statement by its hardcoded `PLUGIN_PREFIX`, and has no generic,
  per-project mapping-generation mechanism at all; building one is real, separate scope this plan
  does not take on.** `source_pattern_mappings[]` for this fixture project is therefore seeded
  DIRECTLY as reviewed test-fixture data (a small, hand-authored set of rows matching the fixture's
  own real file layout, e.g. `path_pattern: "src/**", target_run_unit_ids: [...]`) — NOT via
  automatic per-project discovery, which does not exist for a generic consumer project in this or
  P066's own scope. This seed data is still pushed through the REAL, unmodified approval machinery:
  `aid-test-catalog-approve.sh` (force-tracks the catalog) then
  `aid-test-catalog-confirm-mapping.sh` (the real, separate mapping-confirmation gate, hash-checked,
  never bypassed) — so Step 10's convergence reads a genuinely `mapping_approval.status: approved`
  catalog with real, non-fallback `source_pattern_mappings[]`, even though the ROWS themselves were
  seeded as reviewed fixture data rather than machine-discovered. (2) Only after step (1) completes, the fixture's
  generated `execution.yaml` has its `test_audit.scheduler.mode` field manually set to the single
  value `observe_parallel` (never any other value at this point in the scenario). (3) Step 13's
  rollout gate is satisfied via 3 real, independent Step 7 divergence-check passes on that
  fixture's own test set, each with `mode_tested: observe_parallel` matching the configured mode.
  (4) The real CLI is run: `aid-run-gates.sh run-all .aid-o/config/execution.yaml <epic_id> <run_id>
  --profile targeted --base-commit <fixture-base-sha>` — `{plugin_path}`-qualified
  `aid-select-tests.sh --emit-units` (Step 9) is genuinely invoked and genuinely selects that
  fixture project's OWN tests (not merely falling through to a no-op), its output genuinely flows
  into `aid-test-scheduler.sh` (Step 5), which genuinely dispatches real `aid-job.sh`-backed
  execution units (Step 1), producing real per-unit receipts (Step 4/8), which are folded into
  `gates_report.json` — and the aggregated pass/fail verdict is identical to what running the same
  selected tests sequentially, outside the scheduler, produces.
- **Negative/regression scenario:** the identical fixture with `scheduler.mode: sequential` (the
  shipped default) produces `aid-run-gates.sh` behavior matching pre-this-plan output exactly on
  every field except wall-clock timestamps/durations (the same normalized comparison Step 14
  defines — never an unqualified "byte-for-byte" claim) — proving zero-behavior-change is real, not
  just claimed.
- Against `aid-orchestrator` itself (disposable clone), Step 15's evidence bundle is regenerated
  once more at this plan's own release commit, confirming the full path holds on this repo's real,
  current `run_units` set (read from the live catalog at that time, never a hardcoded count).
- **Existing-project upgrade scenario:** a fixture project with a hand-edited `execution.yaml`
  (predating this plan, with unrelated hand-added gates) runs the Step 12 upgrade command; the diff
  preview is shown, confirmed, and only the missing block is appended — every pre-existing byte is
  verified unchanged, and the resulting file's `targeted_tests` gate is then exercised through the
  same real dispatch path as the fresh-project scenario above.
- **Mapping-gap escalation scenario:** the same fixture project, with an approved mapping that does
  NOT cover a deliberately-introduced changed path, produces the EXISTING `result: "fail"` (never
  a new enum value) with the additive `escalation: {...}` field populated for `targeted_tests`,
  and a real, executed `full`-profile substitute — never a silent pass with zero units selected.

**Acceptance Criteria:**
- [ ] The fixture project's own bootstrap (audit → catalog → approval, PLUS the real, unmodified
  mapping-confirmation gate over reviewed, hand-authored fixture mapping rows — never automatic
  per-project discovery, which is explicitly out of this plan's scope) runs first and produces a
  catalog whose `source_pattern_mappings[]` actually route to that project's own tests — verified by
  selecting a non-empty, non-fallback unit set, not merely reaching the fallback branch
- [ ] The rollout gate is satisfied via 3 real, independent, distinctly-`run_id`'d divergence passes
  — never a single run
- [ ] The `observe_parallel` scenario is proven with real command execution at every named stage
  (`{plugin_path}`-qualified `aid-select-tests.sh --emit-units` → `aid-test-scheduler.sh` →
  `aid-job.sh`-backed receipts → `gates_report.json`), not a mocked or config-only substitute for
  any stage
- [ ] The aggregated verdict from the scheduled run is identical to the same selection's sequential
  verdict
- [ ] The `sequential`-mode regression scenario matches pre-this-plan `aid-run-gates.sh` behavior on
  the normalized (timestamp-excluded) projection defined in Step 14
- [ ] This repo's own evidence bundle (Step 15) is confirmed current as of this plan's release
  commit
- [ ] The existing-project upgrade scenario preserves every pre-existing byte and the upgraded
  gate is exercised through the same real dispatch path
- [ ] The mapping-gap scenario produces the EXISTING `result: "fail"` (never a new enum value)
  with the additive `escalation: {...}` field populated, plus a real executed `full`-profile
  substitute, never a silent zero-unit pass
- [ ] Fix loop: any failure is fixed and re-verified (max 3 cycles)

**Dependencies:**
- Depends on: Step 15 — re-confirms and extends that step's evidence bundle
- Blocks: Step 18 — the PM decision cites this step's evidence alongside Step 15's

**Effort:** L
**AID Role:** e2e

---

### Step 18: PM review of quarantine-lift evidence

**Objective:** Present Step 15's remediation bundle AND Step 17's E2E evidence to the PM as the
explicit decision point for removing `execution.yaml`'s `quarantine:` block — never an automatic
side effect of this plan merging (Constraint 9). **Reordered after Step 17 by a real C0 review**:
this step now runs after all its cited evidence exists, closing the circular reference an earlier
draft had.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/schemas/quarantine-decision.schema.json` — **new,
  added after a real C0 review found no durable decision artifact was ever defined for a step
  whose whole point is a PM decision record.** `gate_id` (`"bats_all"` — this schema is
  intentionally single-gate, matching Step 15's now-narrowed scope), `evidence_ref` (the exact
  path `.aid-o/work/evidence/quarantine-remediation/bats_all-<commit_sha>.json`, Step 15's real
  named artifact), `e2e_evidence_ref` (the exact path
  `.aid-o/work/evidence/e2e-full-path-proof/<run_id>.json` for the most recent `pass:true`
  `observe_parallel_full_path` run, Step 17's real named artifact), `decision` enum
  `lift|keep|defer`, `reviewed_by`, `decided_at`, `rationale`, `supersedes` (optional string —
  the prior record's `decided_at` this record explicitly replaces, added for the supersession
  guard below; absent on a gate's first-ever decision record)
- Create: `plugins/aid-orchestrator/scripts/aid-quarantine-decision-record.sh` — validates BOTH
  `evidence_ref` and `e2e_evidence_ref` exist and are schema-valid before writing a
  schema-valid decision document to `.aid-o/work/evidence/quarantine-decisions/bats_all-<decided_
  at>.json` ONLY on an explicit PM-provided `--decision lift|keep|defer --reviewed-by <name>
  --rationale <text>` invocation — never automatically, never inferred from evidence content alone.
  **Force-tracked into git immediately after the write** (same mechanism/rationale as Steps 7/15/17
  above — a real L3 lens finding, CP1-deep re-run, found this artifact family also had no
  force-tracking wiring). **Supersession guard, added after a real C0 idempotency-lens finding
  (CP1-deep re-run) found no protection against two independent, conflicting decision records for
  the SAME `gate_id`** (the file is keyed by `decided_at`, a timestamp, not by `gate_id` alone, so
  nothing previously stopped a second invocation from silently coexisting as an equally-
  authoritative record): before writing, this script now checks
  `.aid-o/work/evidence/quarantine-decisions/` for any EXISTING record with the same `gate_id`. If
  one exists, the new invocation is REFUSED unless it is explicitly given
  `--supersede <prior-decided_at>` naming the exact prior record being replaced — the superseded
  record is never deleted, only the new record's own `supersedes: <prior-decided_at>` field marks
  it as the current authoritative one for that `gate_id`. A bare re-invocation with no
  `--supersede` and an existing record present fails closed, naming the conflicting prior record.
- Test: `plugins/aid-orchestrator/scripts/tests/test-integration-quarantine-pm-decision.sh` —
  confirms both Step 15's and Step 17's evidence are presented as standalone artifacts; a
  schema-valid decision record is producible only via explicit PM input to the script above; no
  code path in this plan writes to `.aid-o/config/execution.yaml`'s `quarantine:` block
  automatically, even when a `decision:lift` record exists — the record is evidence for a
  PM/implementer to act on separately, never a self-executing trigger; **the written record is
  confirmed force-tracked in a disposable fixture repo (same pattern as Step 7/15/17); a second
  invocation for the same `gate_id` without `--supersede` is refused, naming the existing record; a
  correct `--supersede <prior-decided_at>` invocation succeeds and the new record's own
  `supersedes` field names the prior one**

**Architecture Context:** The explicit PM checkpoint the original roadmap's §6 quarantine-exit
criteria always required — now backed by a real, schema-defined, durable artifact rather than an
unverifiable "presentation," and correctly sequenced after both evidence sources exist.

**Implementation Detail:** The decision record and the actual `execution.yaml` edit are two
separate, sequential human actions — this step produces only the record.

**Error Handling:** A `decision-record` invocation missing any required field fails closed —
no partial record is ever written.

**Edge Cases:** N/A beyond the above.

**Dependencies:**
- Depends on: Step 15 — the remediation bundle; Step 17 — the E2E evidence
- Blocks: Step 19 — release close-out follows the PM decision, not the other way around

**Acceptance Criteria:**
- [ ] A schema-valid decision record is producible only via explicit PM-provided
  `--decision/--reviewed-by/--rationale` input, never inferred automatically, and references both
  Step 15's and Step 17's evidence
- [ ] No code path in this plan modifies `execution.yaml`'s `quarantine:` block, even given an
  existing `decision:lift` record
- [ ] A decision-record invocation missing a required field fails closed, writing nothing
- [ ] The written decision record is force-tracked into git and survives a fresh-checkout check
- [ ] A second invocation for a `gate_id` that already has a decision record is refused unless
  given a correct `--supersede <prior-decided_at>`, which then succeeds and records the
  supersession explicitly

**Effort:** S
**AID Role:** architect

---

### Step 19: Docs, registry, and version close-out

**Objective:** Standard release bookkeeping — now correctly the LAST step, after the E2E proof and
the PM's quarantine decision both exist, **reordered by a real C0 review** that found version/
release bookkeeping preceding its own evidence nonsensical.

**Files:**
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` + `CHANGELOG.md` — new version entry, `Added`
  section covering the scheduler, `aid-run-gates.sh`/`compose_execution_yaml` integration, and the
  `bats_all` remediation evidence bundle (`plan_diff` explicitly out of scope), and a note of
  Step 18's PM decision outcome. **Version-selection rule**: MINOR bump from CHANGELOG.md's own
  current `## [X.Y.Z]` header, read at implementation time (this plan releases strictly after
  P066, so the real baseline at implementation time is whatever P066's own release left behind —
  never a number invented now)
- Modify: `plugins/aid-orchestrator/README.md` + `README.md` — version-file registry sync (8
  locations)
- Test: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — the existing checker
  (P063 Step 4), invoked as `verify-version-files.sh <target> --baseline <real-current-header>`,
  both computed per the rule above at implementation time

**Architecture Context:** Standard AID plan release-bookkeeping step — sequenced last so the
release always reflects a real PM decision, never precedes it.

**Implementation Detail:** N/A.

**Error Handling:** N/A.

**Edge Cases:** N/A.

**Dependencies:**
- Depends on: Step 18 — the PM decision this release reflects
- Blocks: none (plan closing step)

**Acceptance Criteria:**
- [ ] All 8 version-file locations synchronized and verified
- [ ] Both CHANGELOGs carry an identical new entry

**Effort:** S
**AID Role:** release

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| P066's `source_pattern_mappings[]` schema (informational-only there) needs a minor addition once this plan makes it executable | medium | low | Constraint 2 requires any such addition to be backward-compatible, never a fork |
| The isolation-experiment protocol (Step 6) proves more expensive than budgeted | medium | medium | N is project-configurable; Step 15's real dogfood measures actual cost before any promotion is claimed |
| `aid-run-gates.sh`'s scheduler-dispatch branch (Step 14) introduces a regression in the untouched, non-`targeted_tests` gate path | low | high | Step 14's own AC requires a normalized (timestamp-excluded) behavior proof for every other gate type |
| **RESOLVED 2026-08-02** — P066 was not yet merged/closed at authoring time | n/a (closed) | n/a | P066 is now `status: done`, merged to `main` (v2.65.0–v2.66.2). This plan's Resources Verification section was re-grounded against the real, merged artifacts (2 real drifts found and fixed: `aid-test-catalog-approve.sh`'s `--approved-path` removal, and the stale "88 run_units"/`selector_mappings[]` naming) |
| P066 has no `.aid-lifecycle` manifest (never `cmd_init`'d) — `depends_on_plans: [P066]`'s FSM gate-check behavior against a manifest-less, manually-closed dependency is unverified | medium | low | Verify directly when running `/aid-plan epic` for this plan (see Resolution section); the dependency's real substance is satisfied regardless (P066's code is in `main`) |

## Success Criteria

- A configured project can genuinely run its selected tests through the scheduler, end-to-end,
  through `aid-run-gates.sh` — proven by Step 19, not asserted by documentation.
- `sequential` remains the default everywhere; no project's behavior changes until it explicitly
  opts in, and the rollout gate (Step 14) enforces this in code.
- `aid-select-tests.sh`'s default behavior is an exact regression match to today; its new
  `--emit-units` mode is additive.
- This repository's own `bats_all` quarantine has a real, measured evidence bundle ready for PM
  review — removing the quarantine block itself remains the PM's own action. `plan_diff` is
  explicitly named as unresolved and out of this plan's scope, never implied fixed.
- No second job/process supervisor exists anywhere in the plugin.

## Next Steps

- [x] P066 is merged and closed (2026-08-02) — this plan's blocking dependency is satisfied.
- [x] Re-grounded this plan's Resources Verification, Step 11, and every `88 run_units`/
  `selector_mappings[]` reference against P066's real, merged artifacts (2026-08-02) — see the
  "P066 Dependency" section above for the 2 real drifts found and fixed.
- [x] PM authorized direct implementation outside the AID FSM pipeline ("oprav to a dál už
  nebudeme kontrolovat a jdeme rovnou na vývoj... ok jdi na to") — the EPIC-generation path below
  was superseded by this decision and was never taken.
- [x] All 19 steps implemented directly, each with real tests run to green, a genuine `codex exec`
  review against the real diff with every finding fixed, and a per-step commit; each of the 5
  EPICs additionally got its own whole-diff review hunting cross-step integration gaps (all real
  findings fixed). Released as v2.67.0 (2026-08-02).
- [x] This repository's own `bats_all` real, multi-hour measurement campaign remains DEFERRED per
  an explicit PM decision — Steps 15/17/18 are unit-tested against synthetic fixtures only; no
  fabricated passing result was ever produced for it. Running that campaign for real, and the PM's
  actual lift/keep/defer decision it would enable, is left to a dedicated future session.
- ~~PM reviews this re-grounded plan~~ — superseded, see above.
- ~~Verify `depends_on_plans: [P066]`'s FSM gate-check behavior~~ — moot: P066's real code was
  already in `main` and this plan was never run through the FSM/EPIC-generation path.
- ~~Run `aid-plan-lint.sh` / dispatch CP1/C0 / generate EPICs via `/aid-plan epic`~~ — not
  applicable; this plan was implemented directly, not through EPIC generation.

---

**Last Updated:** 2026-08-02 (re-grounded against P066's real, merged artifacts, then revised
after a full CP1-deep dispatch (L1/L2/L3 + 5 C0 lenses) found 3 real blocking issues — Step 14's
escalation target/merge design, Step 3→14 dependency graph, gitignored-evidence force-tracking —
and 5 real advisory issues — Step 3's recent_samples contamination, Step 1's missing
membership_binding field, Step 8's in_flight/lost vocabulary + Step 12's {plugin_path} mechanism,
Step 7's run_id/Step 5's job-id/Step 18's decision-supersession idempotency gaps, and Step 11's
catalog-approval-boundary reconciliation — all fixed in this same revision pass; L1/L2/L3 re-
verified as resolved. A 5th real cross-provider Codex round (PM-authorized fresh override) then
found 5 more real issues — no durable "safe" promotion artifact/reader (CRITICAL — new
`scheduler-parallel-overlay` schema + approval gate added to Step 5, producer added to Step 6);
Step 17's E2E assumed a generic consumer-project mapping-generation mechanism P066 never built
(narrowed to reviewed fixture-seeded mapping data through the real approval/confirmation gates);
Step 10 required a `production_surfaces` glob field that doesn't exist in the real schema
(rewritten using only real, existing fields); more missing dependency edges (Step 13→7, Step
14→5/8/9); and a new `result:"escalated"` value that would have broken the existing, real
`test-aid-run-gates.bats` contract (reverted to the existing `result:"fail"` plus an additive
`escalation` field) — all 5 fixed in this same pass. Per PM instruction, no further CP1/C0 review
rounds; this plan proceeds directly to manual implementation. See
`.aid-o/work/evidence/P069/cp1-deep/` and `.aid-o/work/evidence/P069/c0-plan-review.json` for the
full review evidence trail)
