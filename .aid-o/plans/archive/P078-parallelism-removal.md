
> **Closure (2026-08-10):** implemented, merged to `main` and released as **v2.82.0**. Archived from the active plan set.
# P078 — Remove the test-parallelism machinery

## Plan Type

Removal / simplification. No new capability; the deliverable is a smaller,
cheaper, sequential-only test execution path with every instruction surface,
schema, template and registry row telling the truth about it.

## Context

PM cancelled the entire test-parallelism line on 2026-08-09 (recorded in
`.aid-o/work/interim-P077.md`; P077 allocated-then-cancelled, counter not
reused). Measured economics: sequential 153 min vs scheduled 144 min (~6 %
saved; only 54/181 units proven safe, the critical path owned by suites that
are not among them), qualification ~15 h of compute, HEAD-bound evidence
expiring on every commit. Decisive extra: a substantial share of portfolio
cost is tests that test the parallelism machinery itself.

PM scope instruction (chat, 2026-08-09): remove scheduler, divergence check,
rollout gate, parallel lane wrapper, their tests, enforcement-registry rows,
parallel sections of instruction surfaces (plugin README, aid-audit-tests.md,
test-portfolio-analyst.md), and return `gate:bats_all` / `gate:bats_boundary`
to a plain bats run.

**Sequencing (PM, re-grounded 2026-08-10):** the original P076 gate is
SATISFIED — P076 and P079 are merged; the base is current main (v2.81.0 line,
HEAD `5c24406`). P079 moved the ground: `aid-run-gates.sh` gained
`_gates_state_path` (`:103`, all evidence paths through the state root) and
the scheduler block now sits at `:1448-1560` (source `:65-66`, merge-row call
`:1543`, trailing comment `:1771`); `run-all-tests.sh` `DELEGATED_SUITES` has
6 entries mapped 1:1 onto ci.yml jobs (enforced by
`test-run-all-delegation.sh`); the content scan gained 2 checks and the
registry ~10 rows, so EVERY line reference below is re-verified against
current HEAD at the grounding-refresh step before dispatching.

**PM scope tightening (2026-08-10):** removal only, NO redesign. Gate
profiles are NOT reorganized — a separate tiering plan will do that; this
plan only deletes dead entries/references. Catalog parallel fields: PM
delegated the call — this plan removes them (Ring 2), an audit must not
advertise dead data. Process: after every EPIC a Codex review of that EPIC's
diff; a PM whole-diff review at the end; release as a minor bump from current
head.

Groundings: `.aid-o/work/interim-P077.md` (2 Explore agents + 2 Codex rounds)
**plus an adversarial coverage review of this plan (Explore agent,
2026-08-09)** which found the surfaces in Steps R1-7..R1-10, the schema list,
the kept-suite breakage list and the registry-path correction — all folded in
below.

## Goal

After this plan merges:
- no parallel dispatch path exists anywhere in the plugin — tests run
  sequentially, by design, documented as such;
- `/aid-init` and the upgrade path stop seeding scheduler/parallel config into
  consumer projects;
- the portfolio is measurably cheaper (several deleted suites are among the
  most expensive the audit measured);
- no instruction file, registry row, schema, template, gate command or config
  key refers to scheduling, lanes, rollout modes or divergence evidence;
- the audit keeps what the PM wants from it: content quality, duplicate-run
  detection, naming, measured durations and honest timeouts.

## Scope — Ring 1 (PM-ordered core + directly-coupled surfaces)

### R1-1 Scripts (delete)
- `plugins/aid-orchestrator/scripts/aid-test-scheduler.sh`
- `plugins/aid-orchestrator/scripts/aid-test-schedule-divergence-check.sh`
- `plugins/aid-orchestrator/scripts/aid-test-divergence-campaign.sh`
- `plugins/aid-orchestrator/scripts/aid-scheduler-rollout-gate.sh`
- `plugins/aid-orchestrator/scripts/aid-bats-parallel-lane.sh`
- `plugins/aid-orchestrator/scripts/aid-scheduler-overlay-approve.sh`
- `plugins/aid-orchestrator/scripts/aid-test-parallel-pilot.sh` (coverage
  review: only consumer is parallel promotion, `commands/aid-audit-tests.md:175`)
- `plugins/aid-orchestrator/scripts/aid-test-isolation-experiment.sh` (P069
  Step 6; orphaned once overlay-approve dies) **plus** its runner-bucket
  registration `scripts/tests/run-all-tests.sh:156` — deleting the script
  without the bucket entry breaks the aggregate runner
- `plugins/aid-orchestrator/scripts/aid-test-catalog-migrate-p071-allowlist.sh`
  (sole purpose: migrate the parallel allowlist into `parallel.provenance`)
- `plugins/aid-orchestrator/scripts/aid-self-host-migrate-p071-gates.sh`
  (migrates gates ONTO the deleted lane wrapper)
- `plugins/aid-orchestrator/scripts/lib/aid-test-scheduler-report.sh` —
  sourced unconditionally at `aid-run-gates.sh:65-66`, called at `:311`;
  remove lib + source + call together (post-P076 lines re-verified)
- `plugins/aid-orchestrator/scripts/lib/aid-test-lane-input-validate.sh` —
  sourced at `aid-test-audit-consolidate.sh:44`; goes with the consolidate
  `parallelization` block (see R1-6)
- Note: the overlay CONFIG file named in the first draft
  (`.aid-o/config/test-scheduler-parallel-overlay.yaml`) does not exist —
  the real artifacts are proposed overlays written by the isolation
  experiment, plus the schema (R1-4).

### R1-2 Tests (delete)
- bats: `test-aid-test-scheduler`, `test-aid-test-scheduler-report`,
  `test-aid-test-schedule-divergence-check`, `test-aid-test-divergence-campaign`,
  `test-aid-scheduler-rollout-gate`, `test-aid-bats-parallel-lane`,
  `test-aid-scheduler-overlay-approve`, `test-aid-run-gates-scheduler-dispatch`,
  `test-aid-test-parallel-pilot`, `test-aid-catalog-parallel-authority`,
  `test-compose-execution-yaml-scheduler-block`,
  `test-aid-test-isolation-experiment`,
  `test-aid-gate-runtime-baseline-concurrency` (whole subject is
  observe_parallel baseline partitioning)
- sh: `test-integration-parallel-authority-e2e.sh`,
  `test-integration-scheduler-catalog-consumption.sh`,
  `test-enforcement-registry-scheduler.sh`,
  `test-integration-e2e-full-path-proof.sh` (drives divergence-check +
  rollout gate + scheduler end-to-end; its schema goes in R1-4)
- Payoff note: `test-aid-run-gates-scheduler-dispatch` and
  `test-aid-test-divergence-campaign` both measured >300 s.
- **Red-suite rule (PM 2026-08-10):** the currently-red suites from the
  latest measurement belong to the removed line and are deleted with it. At
  the grounding-refresh step, enumerate the red set from the current
  measurements/CI verbatim and cross-check each member against this plan's
  delete list; any red suite that is NOT parallel-line machinery (e.g. a
  plan-mode boundary suite) is flagged at CP1 instead of silently deleted —
  red is not by itself a deletion criterion, membership in the removed line is.

### R1-2b Delegation map + CI job parity (new after P079)
`run-all-tests.sh` `DELEGATED_SUITES` maps suites 1:1 onto ci.yml job names
and `test-run-all-delegation.sh` fails on any mismatch. Deleting
`test-aid-test-isolation-experiment.bats` therefore REQUIRES removing its map
entry (`["test-aid-test-isolation-experiment.bats"]="isolation-experiment-tests"`)
AND the `isolation-experiment-tests` job from `.github/workflows/ci.yml` in
the same commit. This is removal of a dead job, not a CI redesign — the PM's
"nothing added to CI" stands; the other 5 delegation entries are untouched.

### R1-3 Gate runner + gates + init templates (post-P076 file state)
- `aid-run-gates.sh` (post-P079 locations): excise the P069 Step 13/14 block —
  `run_scheduled_targeted_tests()` + rollout-gate consultation, now at
  `:1448-1560` — plus the peripheral plumbing: the
  `scheduler_report_merge_gate_row` call (`:1543`), the lib source
  (`:65-66`), the `gate_concurrency_context` plumbing, the
  `grep -v 'aid-bats-parallel-lane'` command filter, and the scheduler
  mention in the `:1771` comment. `_gates_state_path` (`:103`) and the
  state-root path scheme are P079 machinery and are NOT touched.
  `targeted_tests` returns to plain `run_gate()`.
- `.aid-o/config/execution.yaml`: `gate:bats_all` / `gate:bats_boundary` back
  to direct `bats` commands (copy the exact file sets the lane resolved —
  boundary pair hard-coded at `aid-bats-parallel-lane.sh:74-77` — before
  deleting the script); remove the `test_audit.scheduler.mode` block (commit
  5f24304). **Profiles are NOT reorganized** (PM: a separate tiering plan
  will) — only dead references to deleted gates/scripts are dropped from
  them, membership and ordering otherwise untouched.
- **Consumer-facing generators (coverage review — without these, every
  `/aid-init` keeps re-seeding the machinery):**
  - `lib/aid-init-execution-yaml.sh:44-81,415,445-459` —
    `render_test_audit_scheduler_block()` and both call sites: remove;
  - `aid-init-upgrade-test-audit.sh` — remove the scheduler/parallel key
    seeding+migration (17 hits);
  - `defaults/config/test-audit.yaml:9,12,38,41` — drop `pilot_noise_ms`,
    `provenance_recheck_budget_ms` (lane-scoped) and scheduler header prose;
  - `defaults/config/bats-parallel-safe-allowlist.txt` — delete (already a
    retirement notice pointing at deleted scripts).
- `lib/aid-test-execution-unit.sh:73,79,89,114`: drop the
  `--label test-scheduler` and scheduler-batch comments (job runner itself
  stays).

### R1-4 Schemas (delete unless marked edit)
- delete: `divergence-evidence.schema.json`,
  `scheduler-parallel-overlay.schema.json`, `test-parallel-pilot.schema.json`,
  `test-resource-map.schema.json` (see R2-1 resolution),
  `e2e-full-path-proof.schema.json`
- edit (strip parallel fields, keep the rest):
  `execution-unit.schema.json` + `execution-unit-receipt.schema.json`
  (`parallel_eligible`, `resource_locks` — emitted at
  `aid-select-tests.sh:483,492-498`, see R1-5),
  `test-execution-ledger.schema.json` (remove `scheduler` from the emitter
  enum; `test-aid-test-execution-ledger.bats:142,188-193` edits with it),
  `test-audit-decision.schema.json` (lanes / `proposed_parallel`),
  `test-audit-wave-artifact.schema.json`, `test-audit-config.schema.json`,
  `test-audit-plan-brief.schema.json`,
  `test-audit-consolidated-findings.schema.json`,
  `quarantine-remediation-evidence.schema.json` (see R1-8).

### R1-5 Select-tests / resolver (decision resolved by coverage review)
`aid_test_catalog_effective_status_map`
(`lib/aid-test-catalog-provenance.sh:320-441`): after R1-1 its ONLY surviving
caller is `aid-select-tests.sh:496`, used exclusively to assign
`parallel_eligible` → **delete the function**, delete the `parallel_eligible`/
`resolved_locks` emission at `aid-select-tests.sh:483,492-498`, and edit the
KEPT suite `test-aid-select-tests-emit-units.bats` plus the two schemas
(R1-4) in the same step — a kept suite asserting a deleted field is a red
build, not a leftover.

### R1-6 Audit dispatch + consolidate (parallel_safety production wiring)
- `aid-test-audit-dispatch.sh:202,281-282` — remove the
  `{focus: "parallel_safety"}` wave;
- `defaults/prompts/test-audit-parallel-safety-prompt-v1.md` — delete;
- other prompts, edit in place: `test-audit-performance-cost-prompt-v1.md:75-76`,
  `test-audit-flake-isolation-prompt-v1.md:76,86-87`,
  `test-audit-shard-auditor-prompt-v1.md:56` (`parallelize` disposition enum),
  `test-audit-adversarial-review-prompt-v1.md:58`;
- `aid-test-audit-consolidate.sh`: remove the `parallelization` block and the
  `:44` source of the deleted lane-input validator;
- KEPT suites that assert these surfaces get edited in the same step:
  `test-aid-test-audit-prompts-golden.bats:113-128,189-196,234`,
  `test-aid-test-audit-dispatch.bats`, consolidate/decision suites touching
  lanes.

### R1-7 Enforcement registry — CORRECT path:
`plugins/aid-orchestrator/defaults/enforcement-registry.yaml`
(the first draft's `docs/plans/AID-audit-2026-06/...` does not exist; the
dated copy lives in `docs/plans/archive/` and is historical — do not edit it).
- retire (registry's own convention for retired rows — match existing
  practice, do not invent): `scheduler_unknown_parallelism_sequential`
  (`:1445`), `scheduler_rollout_requires_divergence_evidence` (`:1456`),
  `test_audit_resource_map_shared_evidence` (`:1514`),
  `test_audit_pilot_evidence_bound` (`:1526`),
  `test_catalog_parallel_provenance_binding` (`:1538`),
  `test_lane_single_parallel_authority` (`:1550`),
  `test_audit_lane_membership_exact` (`:1562`);
- edit, keep: `scheduler_no_second_job_supervisor` (`:1467` — half its source
  is the surviving `aid-test-execution-unit.sh`),
  `test_execution_no_double_dispatch` (`:1646` — KEEP+EDIT; its `:1648`
  source names the deleted lane wrapper, its subject is the job runner);
- explicitly RETAIN (agent-dispatch parallelism, unrelated):
  `planner_parallel_conflict` (`:220`), `max_parallel_one` (`:266`) — and add
  both, plus `defaults/orchestration.yaml:22`, to the acceptance-grep
  allowlist (AC1).

### R1-8 Kept suites that would break (edit, not delete)
- `test-integration-e2e-whole-path.sh:28` (hard path to the lane wrapper);
- `test-integration-quarantine-remediation-evidence.sh:14-34,46-54,93,121,199,222`
  — its whole evidence protocol is the divergence check; REWRITE the fixture
  protocol onto a non-parallel remediation evidence type (quarantine itself
  stays; this suite backs kept registry rows);
- `test-integration-self-host-audit.sh:143` (asserts lane wrapper in the live
  gate command — flip to the plain-bats expectation);
- `test-aid-test-content-scan.bats:49` (fixture gate command uses the lane —
  swap for a neutral wrapper fixture; the overlap check itself stays);
- `test-integration-audit-report-shapes.sh:92-114` (resource-map/pilot
  fixtures — align with R2-1 resolution);
- `test-instruction-consistency.sh:305-334` — **inverted guard**: it fails
  the build on exactly the "no scheduler consumes this" sentence class that
  the truth-telling rewrite would naturally produce. Word the R1-9 rewrites
  as positive statements ("tests run sequentially; parallel execution was
  removed in P078") and UPDATE this guard's banned-phrase list to keep
  guarding against decoration-prose without banning the removal notice.
  `commands/aid-audit-tests.md:20` already violates it and gets rewritten.

### R1-9 Instruction surfaces (corrected ranges)
- `plugins/aid-orchestrator/README.md:96-152` — both the "single parallel
  authority" claim (96-114) and the scheduler section (115-152) → one honest
  paragraph: sequential by design, removed in P078, PM decision 2026-08-09;
- `commands/aid-audit-tests.md` — `:20`, `:55`, `:61`, `:79`, `:166-197`
  (resource-map + pilot step 5c), `:270-300` (whole "Parallel-safety
  findings" section, not just 275-276), `:334`, `:362` ("Paralelně"
  headline), `:418`;
- `agents/test-portfolio-analyst.md:39`;
- `docs/extending-aid.md:1270,1279,1306-1310,1323-1341` — the five tabulated
  scheduler rows + the three-emitter ledger narrative (explicit edit step,
  not just an acceptance criterion);
- `docs/plans/2026-08-02-IMP-...-HANDOFFS.md` §18 — one line pointing here;
- CHANGELOGs (both, identical), version registry (8 files), README roadmap.

## Scope — Ring 2 (audit data contract; confirm at CP1)

### R2-1 Resource map — CONTRADICTION RESOLVED
The first draft deleted `aid-test-resource-map.sh` while keeping
`runtime.fingerprint` provenance — but `lib/aid-test-catalog-provenance.sh`
calls the resource map at `:121,169,351` for the closure/digest computation
that carry-forward depends on. Resolution: **keep the script**, narrow it —
strip the parallel-safety classification output, keep the file-closure/digest
core the provenance lib consumes; delete only its parallel-classification
tests, keep+edit `test-aid-test-resource-map.bats` for the digest core.
`test-resource-map.schema.json` shrinks accordingly (moved here from R1-4 if
CP1 trims Ring 2).
### R2-2 Catalog schema and data
Remove `parallel.*` from `defaults/schemas/test-catalog.schema.json` and from
the approved catalog (regenerate via audit tooling, never hand-edit entries).
`runtime.fingerprint` provenance STAYS. This moots the interim-P077 anomaly
(`status: proposed` after 5f24304 — the fail-closed lane it starved is gone).
### R2-3 Apply-evidence
`aid-test-catalog-apply-evidence.sh`: strip safe-lane promotion
(`resource_map_plus_pilot`); carry-forward of non-parallel evidence stays.
### R2-4 Report
`aid-test-audit-report.sh`: drop the "Paralelně" stat + column and the
"Paralelismus" lever row (+ bats assertions); freed space goes to the
durations/timeout story.
### R2-5 Lane measurement
`test-aid-test-audit-lanes.bats` + lane-based measurement path in the audit
measure step — measurement itself stays, sequential.

## Out of scope

- Splitting `test-aid-plan-final-boundary` (independent follow-up).
- IMP-471/472 (own small plan after P076, per interim-P077).
- WAN (leak-sweeper flock stays — correctness fix, not parallelism).
- `docs/plans/archive/**` and historical CHANGELOG entries (history is not
  rewritten; acceptance grep excludes them).
- `skills/pipeline.md` / `role-cards.md` / `planner.md` agent-dispatch
  parallelism (different subsystem; explicitly retained).

## Approach

Two rings, one EPIC each. Ring 1 = deletion + every directly-coupled edit
(schemas, kept suites, generators, registry) so the tree is green after the
single EPIC — no intermediate broken states. Ring 2 = audit data contract.
Every deletion step ends with: (a) `grep -rn` proving zero live references to
the deleted name outside CHANGELOG/archive (allowlist in AC1), (b) full
non-deleted suite set for touched components green, (c)
`test-instruction-consistency.sh` and the registry consistency suite green.

## Sequencing / process

1. Base = current main (v2.81.0 line, `5c24406`); P076/P079 gates satisfied.
2. Grounding refresh: re-verify every file:line against dispatch-time HEAD
   (cheap Explore pass); enumerate the red-suite set (R1-2 rule); registry
   row numbers re-located (P079 added ~10 rows, content scan 2 checks).
3. Ring 1 EPIC → **Codex review of the EPIC diff** → CP2 → Ring 2 EPIC →
   **Codex review of the EPIC diff** → **PM whole-diff review** → release
   (single minor bump from current head, Removed section per house format).
4. After Ring 2: regenerate the AID audit report from existing TAUD data so
   the published artifact stops advertising 54 parallel-safe lanes.

## Acceptance criteria (plan level)

- [ ] AC1: `grep -rni "scheduler|parallel|divergence|rollout|lane" plugins/aid-orchestrator/ docs/extending-aid.md` → only allowlisted hits: agent-dispatch rows (`planner_parallel_conflict`, `max_parallel_one`, `defaults/orchestration.yaml` `max_parallel`), unrelated words, archive/, CHANGELOG history, and the P078 removal notices themselves.
- [ ] AC2: `gate:bats_all` / `gate:bats_boundary` run plain `bats` and pass; `/aid-init` in a scratch project writes an execution.yaml with NO scheduler block.
- [ ] AC3: registry consistency suite green; zero scheduler-scoped active rows; retained rows edited per R1-7.
- [ ] AC4: `test-instruction-consistency.sh` green WITH its updated guard (R1-8).
- [ ] AC5: full remaining portfolio green (run-all-tests aggregate, minus deleted buckets).
- [ ] AC6: portfolio measured cost drops by at least the sum of the deleted suites' measured durations (next audit round's trend section is the receipt).
- [ ] AC7: CHANGELOGs, 8-file version registry, README roadmap per house rules.

## PM checkpoints

- **CP1 (before execution):** Ring 2 inclusion; R2-1 keep-narrowed resource
  map confirmed; quarantine-evidence rewrite approach (R1-8) confirmed.
- **CP2 (after Ring 1):** tree green, registry green — proceed to Ring 2 or
  stop with Ring 1 only.

---
*Written 2026-08-09 from `.aid-o/work/interim-P077.md` groundings (HEAD
d822957), revised same day after an adversarial coverage review (Explore
agent) that corrected the registry path, added 10 unnamed scripts/libs,
12 schema surfaces, the consumer-facing init generators, 11 kept-suite
breakages incl. the inverted instruction-consistency guard, and resolved the
resource-map contradiction. Implementation blocked until P076 merges.*
