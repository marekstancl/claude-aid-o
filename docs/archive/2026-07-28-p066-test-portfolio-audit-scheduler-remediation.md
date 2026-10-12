> **ARCHIVED 2026-08-10.** Superseded by the cancellation of the entire
> test-parallelism line (PM 2026-08-09, IMP-469 rejected) and its removal in
> P078 (v2.82.0). The scheduler, parallel lane, rollout gate, divergence check
> and the acceleration campaign this document serves no longer exist. Kept as
> historical record only — do not use it to plan work.

status: draft — grounded roadmap, NOT yet an executable AID plan
created: 2026-07-28
author: PM (interim brief 2026-07-17) + AI (grounding + roadmap synthesis 2026-07-28)
plan_id_reservation: P066 (`.aid-o/config/counter.yaml`)
type: roadmap (3+ phases → lives in `docs/plans/`, consumes no plan ID yet)
grounded_against: main @ `67cc1e6` (repo currently released as v2.64.0)

# P066 — Test Portfolio Audit, Isolated Runner, Scheduler and Remediation

## What this document is, and is not

This is the Phase 5 deliverable requested by
`docs/plans/2026-07-23-POST-P064-TO-E10-EXECUTION-CHECKLIST.md`: a **grounded, reviewable
roadmap** that converts the interim brief
(`.aid-o/work/interim-P066-test-portfolio-audit-and-parallel-execution.md`,
2026-07-17, 597 lines — still the primary source of PM decisions, cross-checked
below) into something concrete enough for the PM to approve or redirect.

It is **not**:
- an executable `.aid-o/plans/P066-*.md` plan (no plan ID is consumed here;
  that step runs `/aid-plan write` against this document *after* PM approval,
  per the roadmap-vs-executable convention in `skills/plan-writing.md`);
- a decision to run `/aid-run`, generate EPICs, or change quarantine policy —
  none of that happens until the PM approves this roadmap and a subsequent
  `/aid-plan write` + CP1 pass produces the real executable plan;
- a claim that any test is safe to parallelize. Every parallel-safety claim
  below is explicitly `unknown` unless it cites a grounded fact.

All facts below were gathered read-only against the current checkout. Every
claim is tagged `[FACT: path:line]` (verified) or `[HYPOTHESIS]` (not yet
proven — needs PM decision or a measurement step in the executable plan).
No broad test suite was executed to produce this document, per the mandate.

---

## 1. Grounding — what actually exists today

### 1.1 Test entry point inventory

- `[FACT]` `plugins/aid-orchestrator/scripts/tests/` contains **35** `test-*.sh`
  files plus **53** `test-*.bats` files under `scripts/tests/bats/` — **88**
  discovered entry points total.
- `[FACT: plugins/aid-orchestrator/scripts/tests/run-all-tests.sh:56-63]`
  `run-all-tests.sh` hardcodes a `DELEGATED_SUITES` exclusion list of exactly
  two bats files, each owned by its own dedicated CI job:
  `test-aid-plan-release-boundary.bats` → `plan-boundary-tests`,
  `test-aid-plan-final-boundary.bats` → `plan-final-tests`. So
  `run-all-tests.sh` actually executes **86** of the 88 suites (35 `.sh` + 51
  `.bats`) and prints, rather than silently drops, a `DELEGATED:` line for the
  other two.
- `[FACT: run-all-tests.sh:139-157]` A missing `bats` binary is a **hard
  failure**, not a silent skip, unless `AID_ALLOW_MISSING_BATS=1` is set
  explicitly — this repo already treats "looked green because it never ran"
  as unacceptable for this one failure mode. The audit/scheduler must not
  regress that guarantee for any other runner.
- `[FACT: .github/workflows/ci.yml]` 6 CI jobs, no matrix/parallelism anywhere
  in the file: `bash-tests` (`run-all-tests.sh --verbose`, 20 min budget),
  `plan-boundary-tests` and `plan-final-tests` (the two delegated suites,
  15 min budget each, run alone), `vitest`, `build-check`, `security-regression`.
  **CI never runs the literal `bats_all` gate command or `plan_diff`** — it
  runs a functional superset via three separate jobs instead.

### 1.2 `bats_all` — what it is and why it is quarantined

- `[FACT: .aid-o/config/execution.yaml:9-34]` The `bats_all` gate's
  `original_command` is **`bats plugins/aid-orchestrator/scripts/tests/bats/`**
  — a direct `bats` invocation against the *entire* `bats/` directory. This is
  a **different command** from `run-all-tests.sh`: it includes all 53 `.bats`
  files, including the two heavy suites CI deliberately delegates out. So the
  quarantined `bats_all` gate is strictly heavier than anything CI runs today
  as one unit.
- `[FACT: .aid-o/metrics/gate-runtime-baselines.yaml:348-469]` Measured
  `bats_all` samples (20 total, 18 non-censored): durations from 947,165 ms
  (~15.8 min) to 4,237,933 ms (~70.6 min, `exit_code: 1`); `p50_ms: 1,745,316`
  (~29.1 min), `p95_ms`/`max_ms: 4,237,933` (~70.6 min); the gate's own
  `timeout_seconds` was raised twice across the series (2400s → 3600s →
  7200s) because runs kept exceeding it; two censored `exit 124` samples at
  ~2400s. This is measured confirmation of the quarantine comment's "50-95
  minutes" and "~70 minutes" figures.
- `[FACT: execution.yaml:9-34, quoted verbatim]` Quarantine reason: *"Two
  overlapping E-064-2_2 runs shared the live repository; one failed only
  after ~70 minutes without streaming the failing test, and a retry was still
  running against the same mutable state."* The gate stays `required: true`
  and its `command:` is replaced with an immediate `exit 86` — a hard fail,
  never a silent pass, unless a quarantine-aware profile or an audited
  `--force` waiver is used.
- `[HYPOTHESIS]` No incident log/evidence file corroborating the exact
  "shared the live repository" mechanism was found under `.aid-o/work/evidence/`.
  Given that the dominant test-isolation pattern
  (`test-helpers.bash:setup_test_evidence_dir()` → per-test `mktemp -d`) *does*
  give each `@test` its own working directory, the more likely reading is that
  two whole-suite `bats_all` invocations were running concurrently against the
  same production checkout (reading, not necessarily corrupting, the same
  `AID_PLUGIN_PATH`) while at least one test file's setup/teardown raced on a
  resource outside its own mktemp scope. **This distinction matters for the
  fix** (audit-and-lock a specific resource vs. simply never allow two whole-
  suite runs concurrently) and is listed as an open PM/engineering item below
  (§6, item O1).
- `[FACT]` No docker/docker-compose invocation and no fixed-port literal was
  found in any of the 88 test entry points. `flock`/`.lock` usage exists in 7
  bats files; the 3 directly inspected in the grounding pass (`test-cp1-ledger.bats`,
  `test-aid-plan-final-boundary.bats`, `test-aid-plan-release-boundary.bats`)
  lock a per-test path inside the mktemp root, not a shared fixed path. The
  remaining 4 (`test-aid-emit-dispatch.bats`, `test-aid-gitignore-backfill.bats`,
  `test-invalidation-map.bats`, `test-aid-fsm.bats`) were only grep-matched,
  not read line-by-line — **this full 7-file lock-target audit is required
  work in E1** (§4), not assumed safe here.

### 1.3 `plan_diff` — what it is and why it times out

- `[FACT: plugins/aid-orchestrator/scripts/aid-plan-diff.sh]` Parses a plan's
  `## Acceptance Criteria` `verification_pattern` blocks and runs each one.
  For `type: cmd` patterns, each AC gets its own internal
  `AID_PLAN_DIFF_AC_TIMEOUT` (default 120s) `timeout ... bash -c "$cmd"`, run
  **sequentially in a single loop** — no parallelism, no backgrounding.
- `[FACT: .aid-o/plans/P064-plan-branch-substrate.md:1993-2045]` The plan
  recorded in the current baseline has 5 ACs, and every one of them shells out
  to `bats … test-aid-plan-release-boundary.bats --filter 'AC…'` — i.e. each
  of the 5 sequential AC checks reloads and parses a **7,142-line, 267-test**
  bats file just to run a filtered subset.
- `[FACT: execution.yaml:40-51]` The `plan_diff` **gate's own outer
  `timeout_seconds` is 120** — identical to the *per-AC* internal default.
  With 5 sequential nested-bats AC checks, the outer 120s budget can be
  exhausted by roughly two slow checks before the loop even reaches AC 3-5.
  This is a direct, code-level explanation for the observed `exit 124`, not a
  vague "it's just slow."
- `[FACT: gate-runtime-baselines.yaml:2-93]` 14 samples, 8 non-censored:
  `p50_ms: 7,444`; `p90_ms`/`p95_ms`/`max_ms: 68,472` among non-timeout runs;
  the **6 most recent consecutive samples (2026-07-17 → 2026-07-23) are all
  `exit_code: 124` at ~120,000 ms**, `policy_result: timeout_policy_block`,
  `operator_action: increase_timeout_or_background`. Note that unlike
  `bats_all`, `plan_diff` carries **no `quarantine:` block** in
  `execution.yaml` — it is `required: false` by an unrelated original design
  note (predates the plan-level AC convention) and its real command still
  runs on every `standard`/`full`/`release` gate invocation today. Its
  non-passing state is evidenced only by this timeout series, not by a
  declared quarantine object — the two gates need **separate** exit-criteria
  treatment in §6, not one shared "remove the quarantine block" step.
- `[HYPOTHESIS — flagged discrepancy]` The checklist's phrase "plan_diff …
  34 min of wall clock with no verdict" (`execution.yaml:224-227`,
  `p064-closure` profile comment) is **not reproduced by any single plan_diff
  sample** in the baseline file (all cap at the 120s outer timeout). The more
  likely reading is that "34 min" describes a *different, now-excluded* gate
  pairing (`shell_pipeline_smoke`, whose own budget is 1900s ≈ 31.7 min) in
  one historical run, not a single `plan_diff` invocation. **This needs the
  PM/writer to confirm the source of the "34 min" figure before the executable
  plan cites it** (§6, item O2) — the roadmap does not repeat it as fact.

### 1.4 Root causes, mapped to the incident language in the brief

| Named root cause (PM brief) | Grounded evidence | Status |
|---|---|---|
| Unknown aggregate membership | `bats_all`'s literal command (`bats .../bats/`) silently differs from what CI/`run-all-tests.sh` actually exercises (53 vs 51 files) — nobody reading `execution.yaml` alone would know this without cross-referencing `run-all-tests.sh`'s `DELEGATED_SUITES` | **Confirmed** |
| Shared mutable state | Per-test `mktemp` isolation is real for the pattern inspected, but 4 of 7 lock-using files are unaudited, and the quarantine incident's exact mechanism is unconfirmed | **Partially confirmed, partially open** (O1) |
| Invisible in-flight output | `run-all-tests.sh` captures each suite's full output into a shell variable and only prints it in `--verbose` mode or after the suite finishes (`suite_output="$(...)" && ...`) — a hung/slow suite produces **zero visible output** until it exits or is killed | **Confirmed** |
| Orphan processes | No process-group ownership, deadline enforcement or child-reaping logic exists anywhere in `run-all-tests.sh` or `aid-plan-diff.sh` — a `timeout`-killed `bats` process's own children are not confirmed reaped | **Confirmed absent (needs explicit test in E1)** |
| Uncontrolled parallelism | `aid-run-gates.sh` has **zero** existing parallel-dispatch code (`run_all_gates()` is a single sequential `while read` loop; the only "parallel"-adjacent hits are an advisory string label, not execution logic) | **Confirmed — there is no scheduler to disable; one must be built new** |

### 1.5 Reusable infrastructure (must not be duplicated)

- `[FACT]` **P061 selector** (`scripts/aid-select-tests.sh`, 367 lines): a
  hardcoded path→test mapping (not config-driven, not naming-convention
  inference), `git diff`-based change detection, exit codes `0/1/3/10` (3 =
  "unknown production path — fail loud, never silently skip" — D-selector-1).
  Already has a test-isolation seam precedent: `AID_SELECT_TESTS_PLUGIN_ROOT`
  lets fixtures redirect execution to a mktemp root. **The audit catalog and
  the selector must converge on one path→test mapping, not two.**
- `[FACT]` **P063 baseline writer** (`scripts/lib/aid-gate-runtime-baseline.sh`,
  731 lines): `command_fingerprint` (sha256), FIFO 20-sample history,
  percentile stats over non-censored samples only, `flock`-guarded atomic
  writes, fail-open on metrics-write failure. Already called from
  `aid-run-gates.sh` (`gate_baseline_policy_check`, lines 470-481) — this
  integration is **live today**, not dormant. `run_mode_recommended` is
  advisory text only; nothing currently acts on it.
- `[FACT]` **Implementer concurrency is untouched by this work**:
  `dispatch.max_parallel: 1` lives in
  `plugins/aid-orchestrator/defaults/orchestration.yaml:20-23` and is enforced
  today only as an LLM-facing instruction (`enforcement-registry.yaml:232`,
  `type: 9`, no code reads it) — it governs code-editing agents, not test
  execution, and the interim brief's constraint ("MUST NOT weaken
  `dispatch.max_parallel`") is satisfied by simply never touching this key. A
  *different*, unrelated `dispatch.worktrees.max_parallel: 4`
  (`.aid-o/config/policies/dispatch-strategy.yaml:27`) governs git-worktree
  count and must not be confused with either the above or the new
  read-only-audit-concurrency setting this plan introduces.
- `[FACT]` **`/aid-init` distribution model**: commands/skills/agents ship as
  plain plugin files (read live from the plugin install; no per-project copy
  step). Only `.aid-o/config/*` project files need the copy/merge treatment,
  and the established precedent for merging a new block into an
  already-customized `execution.yaml` is the `gate_profiles` additive-append
  pattern (`commands/aid-init.md:120-204`): presence-gated, additive-only,
  PM-confirmed, never reformats existing bytes. **A new `test_execution:` /
  audit-defaults config block must follow this exact precedent**, not the
  simpler copy-if-absent pattern used for standalone files.
- `[FACT]` **Agent roster**: 8 existing agent cards; `auditor.md` is
  EPIC-merge-lifecycle-specific (dispatched serially from FSM `DONE`, before
  Curator, adversarial-PASS-claim framing) — not a natural fit for an
  on-demand, multi-shard, read-only test auditor. `/aid-audit` itself has
  **no companion skill file** — it is a command that delegates straight to an
  agent card. **Precedent supports: new command → new dedicated agent
  card(s), not a forced skill file**, though prompt-template/scheduler
  mechanics not tied to one agent role may still warrant a skill for the
  scheduler/runner side.

---

## 2. Product shape — distributed capability, not a self-host script

Per PM direction, P066 is **not** self-host-only. The product is a
distributable AID plugin capability usable by any consumer project via
`/aid-init`; `aid-orchestrator` is the first dogfood target and reference
implementation, never a hardcoded assumption baked into the contract.

### 2.1 User-facing command

```text
/aid-audit-tests [repo|path:<path>|runner:<id>]
  [--mode static|measure|full]
  [--budget-minutes N]
  [--max-agents N]
  [--repeat N]
  [--write-plan]
  [--resume <audit-id>]
```

- `static` (default): inventory + source/config analysis only, **no test
  execution**.
- `measure`: run configured test commands under a hard wall-clock/process
  budget to collect real timing/outcome data.
- `full`: `measure` + bounded flake/order/isolation probes; **requires**
  `--budget-minutes`.
- `--write-plan`: hands the consolidated brief to the sanctioned
  `/aid-plan write` flow. Without this flag, only reports are produced — no
  plan file is ever created as a side effect.
- `--resume <audit-id>`: idempotently continues an interrupted audit from its
  durable state file, never re-dispatching completed shards.
- Unknown option, nonexistent `scope`, missing `--budget-minutes` for `full`,
  a dirty/inconsistent resumed audit-state, or an untrusted/non-allowlisted
  diagnostic command → fail loudly, never silently degrade to a smaller scope.

### 2.2 Runner discovery — adapters, not a bats-specific list

The command's Wave 0 preflight must run a **deterministic scanner** with a
pluggable adapter interface, never a hardcoded bats-only enumeration:

- **Adapter contract** (per runner family): `discover() → list of
  {test_id, command, source_paths}`, `supports_list_mode: bool`,
  `supports_filter: bool`. Ship adapters for: Bats (uses `bats --list` where
  available, else static `@test` grep as a documented fallback), a
  package-script adapter (reads `package.json` `scripts.test*`/CI workflow
  files for Vitest/Jest/Playwright commands), and a generic
  "declared-command" adapter for anything already registered as a gate in
  `execution.yaml`/`gate_profiles`.
- **AID self-host is the Bats+shell dogfood case.** A consumer project with
  only Vitest/Playwright must get a working, if shallower, static/measure
  audit from the package-script + generic adapters alone — the contract fails
  if the only implemented adapter is Bats-specific.
- Discovery uncertainty is recorded as `unknown`, never silently promoted to
  `safe` for lack of a better answer — matching the PM brief's fixed rule.

### 2.3 Project-owned defaults (`/aid-init`-distributed)

New `defaults/config/test-audit.yaml` (name TBD by the executable plan),
merged into a consumer project's `.aid-o/config/` using the **same
additive-only, presence-gated, PM-confirmed pattern already used for
`gate_profiles`** (§1.5) — never overwritten on re-init, never silently
reformatted:

```yaml
test_audit:
  budget_minutes_default: 30
  max_read_only_audit_agents: 4     # separate from dispatch.max_parallel — never the same key
  allowed_runners: [bats, npm, vitest, playwright]
  resource_locks: {}                # project-declared exclusive resources (ports, DB, compose project)
  scheduler:
    mode: sequential                 # sequential | observe_parallel | parallel
    max_processes: 4
    unknown_parallelism: sequential  # never optimistic
    fail_policy: stop_next_batch
```

### 2.4 Project artifacts

```text
.aid-o/work/test-audits/<audit-id>/
  audit-state.yaml            # resumable state machine
  timeline.jsonl               # every event, streamed, never buffered-only-in-memory
  inventory.json                # deterministic scanner output
  test-catalog.proposed.yaml    # canonical per-test/suite identity + metadata (see §3)
  shards.json
  measurements.jsonl
  agents/
    <shard-id>-portfolio.json
    performance.json
    flake-isolation.json
    parallel-safety.json
    coverage-traceability.json
    adversarial-review.json
  consolidated-findings.json
  test-portfolio-report.md
  implementation-plan-brief.md   # only consumed by --write-plan; never a plan itself
```

### 2.5 Explicit separation of authority

1. **Audit** reads and recommends. It never edits, deletes, quarantines or
   renames a test, and never toggles `execution.yaml` quarantine state.
2. **PM** approves or rejects every recommendation, in particular any test
   removal, coverage reduction, or gate downgrade to advisory/skip.
3. **The generated remediation plan** (a distinct, repository-specific
   AID plan — e.g. a future "P067-style" plan; the exact ID is allocated at
   `--write-plan` time, not fixed here) is what actually fixes tests/CI/infra,
   through the normal AID plan/run lifecycle with its own CP1/CP2/gates.

### 2.6 User documentation requirements (must ship with the command)

The executable plan must produce user-facing docs answering, in plain
language:
- What `/aid-audit-tests` measures, in each mode.
- What it **never** does on its own (no edits, no deletes, no quarantine
  toggles, no production behavior changes).
- How to read `safe|constrained|exclusive|unknown` parallel-safety verdicts:
  `safe` = no shared mutable resource *and* proven by an isolation experiment,
  not merely "ran fine once together"; `constrained` = safe only behind named
  resource locks; `exclusive` = never share a scheduling slot; `unknown` =
  insufficient evidence — schedule sequentially, always, never optimistic.

---

## 3. Canonical test catalog

Every test/suite gets a stable identity independent of file path alone (one
file can hold many tests; one parameterized test can produce many cases):

```yaml
id: bats:test-c3-audit
runner: bats
command: bats plugins/aid-orchestrator/scripts/tests/bats/test-c3-audit.bats
source_paths: [plugins/aid-orchestrator/scripts/tests/bats/test-c3-audit.bats]
production_surfaces: [plugins/aid-orchestrator/scripts/aid-fsm.sh, plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh]
test_level: integration
risk_tags: [release, provenance, security]
profiles: [targeted, standard, full, release]
behavior_claims: ["C3 provenance tampering blocks under blocking enforcement"]
runtime: {fingerprint: "sha256:...", p50_ms: 0, p95_ms: 0}   # reuses P063 fingerprint scheme, not a new one
parallel: {status: unknown, exclusive_resources: [], max_workers: 1, internal_parallelism: false}
isolation: {temp_workspace: unknown, fixed_ports: [], shared_paths: []}
recommendation: keep     # keep|fix|split|merge|remove|quarantine|measure
confidence: low
```

Ownership decisions the executable plan must fix:
- The catalog and the **P061 selector's** path→test mapping must converge on
  one source of truth — the selector's existing hardcoded `case` statement
  either becomes catalog-derived, or the catalog imports the selector's
  mapping as a seed; they must never diverge silently.
- `runtime.fingerprint`/percentiles reuse **P063's exact fingerprint scheme**
  (`sha256:<12 hex>` of `gate_name:command_template`) — no parallel fingerprint
  format.
- The catalog is project-specific and git-tracked only after PM-approved
  remediation; raw runtime observations stay gitignored evidence/metrics,
  matching how `gate-runtime-baselines.yaml` is already handled.

---

## 4. Isolated runner and deterministic scheduler

### 4.1 Isolated runner (fixes "invisible output" + "orphan processes")

Every test/suite invocation, in every mode, gets:
- **Its own process group** (`setsid`/`setpgid` equivalent), so a deadline
  kill terminates the whole tree, not just the direct child — closing the
  confirmed-absent guarantee in §1.4.
- **Streamed stdout/stderr to a per-run log file** as it happens, not
  buffered only in a shell variable until the process exits — closing the
  confirmed "invisible in-flight output" gap in `run-all-tests.sh`'s current
  `suite_output="$(...)"` pattern.
- **An explicit deadline**, derived from the P063 baseline
  (`timeout_recommended_seconds`) when available, else a conservative
  project/config default — never the bare 120s currently shared by
  `plan_diff`'s outer gate timeout and its own internal per-AC timeout.
- **A terminal receipt**: exit code, duration, log path, resource usage,
  written durably even on kill/cancel/crash, so a failure identifies the
  exact suite/test **during** the run (streamed log), not only after an
  aggregate exits.

### 4.2 Deterministic scheduler

- Consumes the catalog's `parallel.status` + `isolation`/`resource_locks`
  fields and the selected test set from P061, and computes a batch plan
  **before** execution — never ad hoc.
- `parallel.status: unknown` → always sequential. This is non-negotiable per
  the PM brief and repeated here because it is the single most important
  invariant: **no batch may claim `safe` without a specific isolation
  experiment's evidence attached** (§4.3).
- `constrained` tests run concurrently only holding their named
  `exclusive_resources` lock; `exclusive` tests always run alone in their own
  batch.
- Enforces a global process/CPU budget and a per-runner worker budget,
  explicitly avoiding double oversubscription when a runner (pytest/Vitest/
  Bats) already uses internal parallel workers.
- A required-gate failure in batch N stops scheduling batch N+1 (already-
  running batch-N work finishes or is cleanly cancelled per an explicit
  policy); advisory-gate failures keep existing pass-through semantics
  unchanged (`aid-run-gates.sh`'s current required/advisory/skip verdict
  model, §1.5, is preserved byte-for-byte — the scheduler changes *when* and
  *how many at once* gates run, never what a result means).
- Produces one deterministic combined report regardless of completion order
  (sorted by stable test ID before serialization, not append-order).
- Rollout is config-gated (`test_audit.scheduler.mode`, §2.3):
  `sequential` (today's behavior, unchanged) → `observe_parallel` (computes
  and optionally executes batches, but always cross-checked against the
  sequential run, no release speed claim yet) → `parallel` (only after the
  divergence gate in §4.3 passes repeatedly). One config flip reverts to
  `sequential` with no catalog migration required.

### 4.3 Comparative proof — sequential vs scheduled

Before any promotion beyond `observe_parallel`:
- Run the same selected test set both ways on the same commit.
- Membership (which tests ran), verdicts (pass/fail/skip per test) and
  required-gate outcomes must be **identical**. Any divergence blocks
  promotion — this is mechanically checked, not eyeballed.
- A specific "isolation experiment" is what promotes a test from
  `unknown`/`constrained` to `safe`: running it concurrently with its
  proposed batch-mates N times, on a clean isolated resource set, with no
  shared-state assertion failures and no timing-order dependence — the exact
  protocol and N are fixed by the executable plan, not invented per audit run.

---

## 5. EPIC decomposition (for the eventual executable plan)

Preserves the interim brief's dependency order; the writer may refine
boundaries but not this sequencing:

1. **E1 — Contracts and deterministic inventory.** Schemas (catalog, audit
   state, timeline events), stable test-ID scheme, runner adapters (Bats +
   package-script + generic-declared-command), catalog proposal generation,
   resume/interrupt state machine, the full 7-file lock-target audit flagged
   in §1.2, fixtures. No LLM dispatch yet (Wave 0 only). **Forward-dependency
   note:** E1's resume/interrupt state machine can only be schema- and
   mock-tested here — it cannot be exercised against a real interrupted
   multi-wave dispatch until E2's shard dispatch exists. This is not a
   circular dependency (E1 still ships and is independently useful first),
   but the executable plan must schedule an E2-time regression test that
   re-validates E1's resume contract against real dispatch, not assume E1's
   unit-level tests alone prove it end-to-end.
2. **E2 — `/aid-audit-tests` command and versioned prompts.** Command UX,
   bounded read-only dispatch (Waves 1-3 from the interim brief: shard
   portfolio auditors → cross-cutting specialists → adversarial reviewer),
   prompt templates as versioned tracked files with golden-render tests,
   shard-overlap validation (two shards must never claim the same test ID).
3. **E3 — Specialist aggregation and sanctioned plan-writing handoff.**
   Deterministic consolidator (Wave 4), `--write-plan` invoking the real
   `/aid-plan write` path (never an ad hoc plan composed by the audit
   command itself), `test-portfolio-report.md` + `implementation-plan-brief.md`.
4. **E4 — Parallel scheduler substrate, observe mode only.** Deterministic
   batch planner, resource locks, budgets, per-test streamed logs/process-
   group ownership/deadlines (§4.1), deterministic report merge, the
   sequential-vs-scheduled divergence gate (§4.3). Ships behind
   `test_audit.scheduler.mode: sequential` default — no behavior change for
   any project until explicitly flipped.
5. **E5 — Runtime wiring into P061 profiles / `aid-run-gates.sh`.**
   Selected-set consumption from the catalog, P063 timing feedback annotated
   with concurrency context (so parallel contention doesn't corrupt
   sequential baselines), stop/cancel/resume wiring, `/aid-init` distribution
   of the new config block (§2.3) via the `gate_profiles`-precedent additive
   merge.
6. **E6 — AID self-host dogfood, first remediation plan, calibrated
   activation.** Full self-audit of `aid-orchestrator`, generation (never
   silent execution) of the repository-specific remediation plan, sequential-
   vs-observe-parallel comparison on this real portfolio, the quarantine
   exit-criteria evidence pack (§6), docs/registry updates, release.

Bulk cleanup of AID's own 88 existing tests is **out of scope for E6 itself**
beyond whatever small fixes are needed to prove the command/scheduler work —
the actual cleanup is the separately generated, separately approved
remediation plan.

---

## 6. Quarantine exit criteria for `bats_all` and `plan_diff`

Do **not** restore the real commands merely because one run happens to pass.
All of the following must hold, with evidence attached to the plan-final
report:

- [ ] No configured test entry point is missing from the catalog (cross-check
  against `run-all-tests.sh` discovery, the `bats_all` literal command, CI's
  2 delegated jobs (`plan-boundary-tests`, `plan-final-tests`), and
  `aid-select-tests.sh`'s existing mapping — all four must agree on total
  membership).
- [ ] `plan_diff` is treated as its own exit-criteria item, separate from the
  `bats_all` `quarantine:` block: its outer/per-AC timeout coupling (§1.3) is
  fixed and its restored timeout/retry settings are measured, independent of
  whether/when the `bats_all` quarantine block is removed.
- [ ] No overlapping runner can mutate the same live state without a lock or
  an isolated workspace — the full 7-file lock-target audit from §1.2/E1 is
  closed, not merely sampled.
- [ ] A failure identifies the exact suite/test before the aggregate exits
  (streamed logs, §4.1), reproducibly demonstrated.
- [ ] Sequential and scheduled runs have identical membership and verdicts
  across the calibrated sample (§4.3), not a single lucky run.
- [ ] Cancellation/restart cannot orphan work or duplicate a run — proven with
  an explicit kill/resume test, not asserted.
- [ ] `plan_diff` no longer nests an opaque, unbounded-relative-to-its-own-
  gate-timeout `bats` invocation per AC against live mutable state; either its
  outer timeout is decoupled from the per-AC timeout with headroom, or the
  nested bats calls are replaced with the isolated runner from §4.1.
- [ ] A PM-approved measured runtime target is met. **Proposed target for the
  PM/writer to ratify**: AID self-host full-suite p95 ≤ 20 minutes on the
  reference host, without reduced coverage — this is a proposal carried
  forward from the checklist, not yet independently re-derived here; the
  writer must either re-justify it against the real ~29-70 min baseline
  measured in §1.2, or the PM must set a different number.
- [ ] Restored command/timeout/retry/concurrency settings are based on
  measured post-remediation data, not the pre-remediation guesses currently in
  `execution.yaml`.
- [ ] PM explicitly removes the `quarantine:` block from `execution.yaml`
  (the audit/scheduler work does not auto-remove it).

---

## 7. Mandatory guardrails (repeated here as binding constraints on the executable plan and on any audit/measure run)

- No broad full-suite rerun during analysis — `static` mode is the default;
  `measure`/`full` require explicit budget and never run the quarantined
  `bats_all` original command as a side effect of auditing it.
- No concurrent tests against the same mutable worktree without a scheduler
  that has *proven* isolation for that specific batch (§4.3) — "it happened
  to pass once concurrently" is never sufficient evidence.
- No removal, weakening, or "unnecessary" labeling of any test without
  reproducible evidence and explicit PM approval, routed through the
  generated remediation plan, never through the audit command directly.
- A failure must identify the exact suite/test during the run, not only at
  aggregate completion — enforced by the isolated runner's streamed logs
  (§4.1), which is a **new required capability**, not an assumption.
- No design may claim "parallel safe" without isolation evidence attached
  (§4.3) — `unknown` is always the fail-closed default.

---

## 8. Open items requiring an explicit PM decision (O-numbered)

- **O1 — `bats_all` incident root cause.** Was the 2026-07-23 quarantine
  incident genuine shared-mutable-state corruption (specific file/lock/port),
  or resource contention between two full-suite invocations reading the same
  checkout? No incident log was found to confirm either way (§1.2). This
  changes whether E1's fix is "add a specific lock" or "never allow two
  whole-portfolio runs concurrently regardless of per-test isolation." The
  writer should look for `.aid-o/work/evidence/E-064-2_2/` artifacts from that
  date before assuming either explanation.
- **O2 — "34 min" figure provenance.** The `p064-closure` profile comment's
  "34 min of wall clock with no verdict" does not match any single recorded
  `plan_diff` sample (all cap at the 120s outer gate timeout) or any
  `bats_all` sample cleanly. It most plausibly describes a
  `shell_pipeline_smoke` (1900s budget) + `plan_diff` pairing from one
  historical run, but this is unconfirmed. The executable plan should either
  find the source or stop citing the figure as measured fact.
- **O3 — Full-suite p95 target.** The checklist proposes "≤ 20 minutes,"
  against a measured current p95 of ~70.6 minutes for the real `bats_all`
  command. That is a >3x reduction target. PM should confirm this number is
  still the intended bar (vs., e.g., a target expressed relative to the
  scheduler's parallelism budget) before the executable plan commits to it as
  an acceptance criterion.
- **O4 — Catalog/selector convergence ownership.** Should
  `aid-select-tests.sh`'s existing hardcoded mapping become
  catalog-*generated* (single source of truth = catalog), or does the catalog
  *import* the selector's existing mapping as its seed data with the selector
  script otherwise unchanged for now? Both keep them from diverging; they
  differ in which system the PM is committing to evolve first.
- **O5 — New agent card(s) vs. reuse.** Confirm the direction in §1.5/§5.2:
  new dedicated read-only agent card(s) for the audit roles (shard auditor,
  performance/flake/parallel-safety/coverage specialists, adversarial
  reviewer), distinct from `auditor.md`'s EPIC-merge-lifecycle role. This
  roadmap assumes yes; it is not yet an approved architectural decision.

None of O1-O5 block writing the executable plan in a way that resolves them
explicitly as plan preconditions/risks (per the PM brief's own instruction:
"unresolved conflicts become explicit plan risks or preconditions") — they
are listed here so the PM can pre-empt them if there is already a preferred
answer, rather than have the writer guess.

---

## 9. Cross-check against the interim brief

This roadmap does not replace
`.aid-o/work/interim-P066-test-portfolio-audit-and-parallel-execution.md`; it
grounds it. Every PM-fixed decision already recorded there (command name,
read-only/proposal-only agents, PM-gated removal, static default, unknown ⇒
sequential, separate audit-concurrency setting from `dispatch.max_parallel`,
P061/P063 reuse, observe-mode-first rollout) is preserved unchanged above. No
contradiction was found between the interim brief and the grounded facts in
this pass — the three disagreements worth flagging are cosmetic, not
substantive:

- The brief's own text paraphrases "`dispatch.max_parallel: 1`" correctly as
  the value in `defaults/orchestration.yaml`; a separate grounding pass in
  this session initially cross-referenced the *wrong* file
  (`.aid-o/config/policies/dispatch-strategy.yaml`, value `4`, a different
  key) before the second grounding pass corrected it. §1.5 above states the
  correct, final answer: the brief's constraint is about
  `defaults/orchestration.yaml`'s `dispatch.max_parallel: 1`, confirmed
  correct.
- The brief's illustrative scheduler config uses a flat `test_execution:` top
  key (§424-465 of the interim brief); this roadmap's §2.3 restructures it as
  `test_audit:` with a nested `scheduler:` sub-block, to fit the same key
  under the additive-merge precedent alongside audit-specific settings
  (`budget_minutes_default`, `max_read_only_audit_agents`,
  `allowed_runners`). This is a naming/shape choice for the writer to confirm
  or revert, not a discovered fact — flagged so the executable plan doesn't
  silently pick one over the other without the PM noticing the rename.
- The brief's illustrative catalog/prompt/config YAML snippets are directly
  reusable starting points (§2.3, §3 above quote them near-verbatim) — the
  executable plan should treat them as a strong first draft, not something to
  redesign from scratch.

---

## 10. Next step

PM reviews this roadmap and §8's O1-O5. On approval (with or without
resolving O1-O5 — they may be carried as explicit plan risks instead), the
next action is `/aid-plan write` against this document to produce the real
executable `.aid-o/plans/P066-*.md`, which then goes through CP1-deep (this
is a high-risk plan by the review-checkpoint-contracts.md patterns: it
touches gate/execution config, FSM-adjacent dispatch, and release-relevant
test infrastructure) before any EPIC generation. No EPICs, no `/aid-run`, and
no quarantine-policy change happen as part of this document.
