---
id: P071
type: regular
status: done
created: 2026-08-02
author: PM + AI
lifecycle_strict: true
depends_on_plans: [P066]
---

> **Closure (2026-08-09):** Shipped as v2.68.0 (merge efbc673); administratively closed 2026-08-08 (stranded EPIC_INTEGRATION pre-P073, no receipt — see plan-state/P071/operations.jsonl)

# Plan: Test Portfolio Audit — Cost & Parallel-Execution Remediation

## Plan Type

This plan is type: `regular` (config/timeout fixes + new parallel-execution capability for the
existing bats test runner; no auth/schema/migration/security-sensitive surface touched).

## Context

Generated via `/aid-audit-tests repo --mode full`'s sanctioned write-plan handoff
(`audit-20260802-070629`), after the PM explicitly rejected the audit's own default output
(`unknown` parallel-safety for all 87 run_units, bare timeouts with no root-cause) as
non-actionable and requested a deeper diagnostic pass BEFORE any plan was written. That diagnostic
pass (same session, real command execution — `bats --timing`, real background measurement runs,
a disposable local clone, direct source reads of all 83 bats files) produced 5 concrete,
evidence-backed `fix` items, now consolidated into
`.aid-o/work/test-audits/audit-20260802-070629/implementation-plan-brief.md`. This plan traces
every step to that brief; it never re-litigates the audit's own scope (P066: capability only, no
scheduler — that remains P069's job).

## Goal

Fix the concrete, real cost/timeout/scheduling problems the diagnostic pass found in this
project's own test-gate configuration and enable safe cross-file parallel execution of the bulk
of the bats portfolio, without touching the 2 run_units still too expensive/unstable to schedule
confidently.

## Scope

**In scope (each item traces to one `implementation-plan-brief.md` row):**
- `gate:plan_diff` — `timeout_seconds: 120` is contradicted by the project's own recorded incident
  (a 34-minute wall-clock, exit-124 timeout run cited in `execution.yaml`'s `p064-closure`
  profile rationale) — but that citation attributes the 34 minutes to `plan_diff` AND
  `shell_pipeline_smoke` COMBINED, not `plan_diff` alone (Wave 3 adversarial correction). Resolve
  the attribution, then set an evidence-based timeout.
- `gate:shell_pipeline_smoke` — named "smoke" but its real command
  (`bash plugins/aid-orchestrator/scripts/tests/run-all-tests.sh`) runs the FULL aggregate test
  suite (`timeout_seconds: 1900`, ~31.6 min) — rename or re-scope so the name matches what it does.
- `gate:bats_all` — currently a deliberate quarantine stub (`exit 86`, no real execution at all)
  with no working replacement. Real diagnostic verification this session (disposable local clone,
  `bats -j4` over 10 representative files: 147/147 tests passed, 0 failures, no leaked state,
  44.79s vs a ~147s serial baseline — 3.3x) confirms most of the portfolio is safe to run
  concurrently. Enable real parallel execution for the confirmed-safe subset.
- `test-aid-plan-final-boundary.bats` — does not complete within 1 hour of wall-clock (245 tests,
  only 104 completed; per-test cost accelerates from ~5s early in the file to 40-53s later,
  concentrated in the file's AC5 section — 39 of 245 tests, all doing real git
  merge/tag/lifecycle-receipt-commit operations). Root-cause the acceleration and fix it, or, if
  the cause turns out to be inherent to AC5's real git operations rather than a defect, document
  that explicitly and give it a permanently dedicated, non-blocking CI lane.

**Out of scope:**
- Any scheduler/gate-integration work generally (P069's job, `depends_on_plans: [P066]` already
  there — this plan does not duplicate it).
- `test-aid-plan-release-boundary.bats` — real, complete measurement this session shows 42.9
  minutes, 267/267 passed; no defect found, no fix needed. It gets a dedicated CI lane as part of
  Step 3's scheduling change, but no code change of its own.
- The 2 severity-`low` items the diagnostic pass also found (a leftover fixed-path debug write in
  `test-aid-test-adapter-declared-command.bats:58`, and `gate:targeted_tests`'s stale "not yet
  activated" doc comment) — real but trivial, `keep`-adjacent housekeeping that does not meet this
  audit's own Medium+ actionable-brief threshold. Can be fixed ad-hoc without a plan.
- Re-running `/aid-audit-tests` itself, or changing anything about the audit command/pipeline
  (P066 is DONE/CLOSED; this plan only acts on ITS output).

## Approach

### Option A: Fix all 4 items in one plan, sequenced by dependency (Recommended)

The `gate:bats_all` parallel-execution fix (Step 3) needs to know the final boundary file's
disposition (Step 4) before it can decide that file's lane — either "give it a dedicated lane
forever" or "once fixed, fold it into the general parallel pool." Bundling keeps that dependency
visible in one plan instead of splitting it across two EPICs that would need to coordinate anyway.

**Pros:** one bounded review pass; the real ordering dependency (Step 4 informs Step 3's final
lane count) stays explicit instead of being coordinated across two separate plans.
**Cons:** Step 4 is the one item with a genuinely unknown root cause and unknown effort — bundling
means the whole plan's EPIC-close timing is coupled to that uncertainty.

### Option B: Split Step 4 (final-boundary root cause) into its own plan, ship Steps 1-3 first

**Pros:** Steps 1-3 are well-understood, bounded effort, and could close independently without
waiting on an open-ended investigation.
**Cons:** Step 3's parallel-execution design still needs *a* answer for the final-boundary file
even in the interim (dedicated-lane-forever is a valid interim answer) — so the coordination cost
doesn't actually disappear, it just moves to two plans' Next Steps instead of one plan's step
ordering.

### Decision

**Chosen:** Option A.
**Rationale:** Step 3 needs a concrete decision either way for the final-boundary file (dedicated
lane vs. eventually poolable); Option A keeps that decision, and the diagnostic evidence backing
it, in the same reviewable unit. Step 4 is timeboxed (see Step 4's Acceptance Criteria) precisely
so an unresolved root cause does not indefinitely block Steps 1-3 from being merged — the
timeboxed fallback for Step 4 is "dedicated lane, documented open root cause," which Step 3 can
consume either way.

## Implementation Steps

**EPIC 1: Steps 1-4 — Test Portfolio Cost & Parallel-Execution Remediation**

### Step 1: `gate:plan_diff` timeout attribution + fix

**Objective:** Resolve whether the recorded 34-minute/exit-124 incident belongs to `plan_diff`
alone or the combined `plan_diff`+`shell_pipeline_smoke` run, then set `plan_diff.timeout_seconds`
to an evidence-based value (currently an unexplained `120`). This step resolves BOTH brief items
targeting `gate:plan_diff` (`sha256:ff61e8949d17` timeout_consistency and `sha256:9c51ad9cd98c`
adversarial_evidence_overreach) — the second is a correction of the first's unsupported "17x
undersized" claim, and both are closed by the same attribution investigation.

**Files:**
- Modify: `.aid-o/config/execution.yaml` (lines ~40-51) — update `plan_diff.timeout_seconds` and
  the `p064-closure` profile rationale comment to name which gate(s) the 34-minute figure belongs
  to

**Architecture Context:** `execution.yaml` is the single source of truth for gate definitions
consumed by `aid-run-gates.sh`. `plan_diff` runs `aid-plan-diff.sh` to check plan-AC blocks against
codebase HEAD; its `timeout_seconds` bounds how long `aid-run-gates.sh` waits before declaring a
timeout (`exit 124`). No other script hardcodes this value. `plan_diff` is a `declared-command`
gate, not a bats file, so it stays outside Step 3's parallel `bats_all` pool entirely — Step 3's
own AC3 pattern must not accidentally match or alter this gate's command.

**Implementation Detail:**
1. `git log -p --follow -S "34 min of wall clock" -- .aid-o/config/execution.yaml` to find the
   commit that added the `p064-closure` profile rationale comment; read the commit message and any
   linked evidence for whether the 34-minute duration was `plan_diff` alone, `shell_pipeline_smoke`
   alone, or the sum of both running sequentially in that closure attempt.
2. If genuinely combined (most likely, per the current comment's plain-English phrasing "both...34
   min of wall clock with no verdict" describing the pair, not per-gate durations): set
   `plan_diff.timeout_seconds` to a value grounded in `plan_diff`'s own historical baseline
   (`.aid-o/metrics/gate-runtime-baselines.yaml` → `gates.plan_diff`, avg ~15.6s, max ~68.5s per
   this session's diagnostic pass) with headroom, e.g. `300` (≈4.4x the observed max) — not a
   round guess.
3. If genuinely attributable to `plan_diff` alone: set `timeout_seconds` to cover that duration
   with headroom instead (e.g. `2400`), and note in the comment that the incident was isolated to
   this gate.
4. Update the `p064-closure` rationale comment (or add a new comment directly on `plan_diff`) to
   state the resolved attribution explicitly, so a future reader never re-asks this question.

**Error Handling:** If `git log -S` finds no originating commit (comment predates trackable
history, or was written free-hand without a linked incident), fall back to the historical-baseline
value from `gate-runtime-baselines.yaml` (step 2's headroom formula) and record in the comment that
the 34-minute attribution could not be traced to a specific commit — an explicit "unknown, using
baseline+headroom" is acceptable and still resolves AC1 (the goal is no longer a bare unexplained
`120`, not a perfect historical reconstruction).

**Edge Cases:**
- Git history for `execution.yaml` was squashed/rebased and `-S` finds multiple candidate commits —
  use the earliest one that introduces the exact "34 min" phrase, not a later reformatting commit.
- `gate-runtime-baselines.yaml`'s `plan_diff` baseline itself contains censored (timed-out) samples
  — exclude `censored: true` entries when computing the max, per that file's own existing schema
  convention (already used elsewhere in this codebase).

**Dependencies:**
- Depends on: ---
- Blocks: none

**Acceptance Criteria:**
- [ ] `plan_diff.timeout_seconds` in `.aid-o/config/execution.yaml` is no longer `120`
- [ ] The `p064-closure` rationale comment (or a new comment on `plan_diff`) explicitly states
  which gate(s) the cited 34-minute incident belongs to
- [ ] The new timeout value is traceable to either a historical baseline figure or a git-history
  finding, not an arbitrary round number

**Effort:** S
**AID Role:** backend

---

### Step 2: `gate:shell_pipeline_smoke` naming/scope fix

**Objective:** Stop the gate's name from implying a fast/partial "smoke" check when its real
command runs the full aggregate test suite (`run-all-tests.sh`, `timeout_seconds: 1900`).

**Files:**
- Modify: `.aid-o/config/execution.yaml` (lines ~34-39) — rename `shell_pipeline_smoke` (e.g. to
  `shell_pipeline_full`) or, if renaming is judged too disruptive to existing profile references,
  add a `description:` field stating plainly that it runs the full aggregate suite, not a partial
  smoke check
- Modify: `.aid-o/config/execution.yaml` — update every `gate_profiles.*.include[]` list entry
  referencing `shell_pipeline_smoke` if renamed

**Architecture Context:** Gate names are referenced by exact string match in every
`gate_profiles.*.include[]` list in the same file; a rename requires updating every list entry
consistently, not just the gate's own key.

**Implementation Detail:**
1. `grep -n "shell_pipeline_smoke" .aid-o/config/execution.yaml` to enumerate every reference
   (gate definition + every profile include list).
2. Decide rename vs. description-only based on how many profile references exist (found this
   session: the gate definition itself plus profile include-list entries — confirm current count
   at implementation time since profiles may have changed since this plan was written).
3. If renaming: change the gate's own key AND every `include[]` string, in one commit, so no
   profile silently loses the gate mid-edit.
4. If description-only: add/update a `description:` field on the gate stating "Runs the full
   aggregate test suite via run-all-tests.sh (~32 min) — NOT a fast smoke check" so the name's
   misleading implication is corrected in the one place a reader would look.

**Error Handling:** If a rename breaks a profile reference this step's own grep didn't find (e.g.
a reference in a different config file outside `execution.yaml`), Step 3's own re-verification
(its Edge Cases) will catch it when re-running the full profile set — no separate fallback needed
since Step 3 already re-verifies profile behavior end-to-end.

**Edge Cases:**
- A rename could break an in-flight EPIC's queued gate reference (a `plan.json` capturing the old
  gate name) — grep `.aid-o/work/` and any queued `plan.json` files for the old name before
  committing the rename; if any are found, prefer the description-only fix instead to avoid
  breaking in-flight state.
- The description-only fix must not silently contradict the gate's own `note:` field if one
  already exists — read the current `note:` (if present) before adding a new `description:` so the
  two don't conflict.

**Dependencies:**
- Depends on: ---
- Blocks: none

**Acceptance Criteria:**
- [ ] The name or `execution.yaml` description of `gate:shell_pipeline_smoke` no longer implies a
  fast/partial check
- [ ] If renamed, every `gate_profiles.*.include[]` reference is updated consistently (verified by
  re-grepping for the old name — zero remaining hits)
- [ ] No in-flight `plan.json`/queue reference to the old name was left broken

**Effort:** S
**AID Role:** backend

---

### Step 3: Enable parallel execution for the safe portfolio subset

**Objective:** Replace the `gate:bats_all` quarantine stub (`exit 86`, no real execution) with a
real `bats -j N` invocation over the confirmed-safe ~81 non-boundary bats run_units, and give
`test-aid-plan-release-boundary.bats` and `test-aid-plan-final-boundary.bats` each a dedicated,
non-pooled lane.

**Files:**
- Modify: `.aid-o/config/execution.yaml` (lines ~1-10, `gate:bats_all` definition) — replace the
  `exit 86` stub command with a real `bats -j N <file-list>` invocation (or a wrapper script if the
  file list needs to be generated dynamically from the approved catalog)
- Create: `plugins/aid-orchestrator/scripts/aid-bats-parallel-lane.sh` — resolves the current
  approved catalog (`.aid-o/config/test-catalog.yaml`), partitions run_units into "safe pool"
  (parallel `-j N`) vs. "dedicated lane" (the 2 boundary files, run alone), and invokes `bats`
  accordingly
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-bats-parallel-lane.bats` — covers
  the partition logic (boundary files excluded from the pool, everything else included) and a
  real (not mocked) small-scale parallel invocation

**Architecture Context:** `gate:bats_all` is invoked by `aid-run-gates.sh` like any other
declared-command gate; this step changes ONLY that gate's command, not `aid-run-gates.sh` itself
or `aid-select-tests.sh` (both explicitly out of scope, inherited from P066/P070). The new
`aid-bats-parallel-lane.sh` script is a thin wrapper the gate's `command:` field invokes — it does
not become a second process supervisor (`aid-job.sh` is not reused here since `bats -j N` already
owns the parallel process lifecycle itself, unlike the sequential single-command-at-a-time model
`aid-job.sh` implements).

**Implementation Detail:**
1. `aid-bats-parallel-lane.sh` reads `.aid-o/config/test-catalog.yaml`, filters `run_units` to
   `runner == "bats"`, and partitions by a hardcoded exclusion list (the 2 boundary file paths,
   from this plan's own diagnostic evidence) into `$SAFE_POOL[]` and `$DEDICATED[]`.
2. Runs `bats -j "${N:-4}" "${SAFE_POOL[@]}"` for the pool (default `-j 4`, overridable via env var
   for CI tuning), THEN (sequentially, not concurrently with the pool) `bats "${DEDICATED[@]}"` for
   each boundary file in its own invocation.
3. Exit code is the logical AND of both phases (any failure in either phase fails the gate).
4. `-j N`'s actual value should default conservatively (4, matching this session's own verified
   sample) — do not default to the host's full core count without first re-verifying with the FULL
   ~81-file set (see Risks).

**Error Handling:** If the catalog is missing/malformed, fail loudly (matching this codebase's
established fail-closed convention — never silently fall back to a partial or empty file list). If
`bats -j` itself is unavailable (GNU parallel not installed on a given CI runner), fail loudly
naming the missing dependency rather than silently falling back to serial execution (a silent
fallback would make the gate's timing behavior unpredictably inconsistent across environments).

**Edge Cases:**
- A new bats file is added to the catalog after this step ships — it is automatically included in
  `$SAFE_POOL` unless explicitly added to the exclusion list; this is the correct default (new
  files start in the fast pool) but means the exclusion list must be revisited if a future file
  turns out to need a dedicated lane too.
- The approved catalog's `parallel.status` field (currently `unknown` for all 87 run_units per the
  audit) is NOT used as the partition signal — the exclusion list here is the 2 specific files this
  plan's own diagnostic verified, not a blanket read of that still-`unknown` field.
- Running the FULL ~81-file safe pool (not just the 10-file sample) for the first time may surface
  a resource collision the smaller sample didn't exercise — this step's own AC requires that full
  re-verification before shipping.

**Dependencies:**
- Depends on: ---
- Blocks: none

**Note (informational, not a formal step dependency):** Step 4's disposition for
`test-aid-plan-final-boundary.bats` does not gate this step — Step 3 ships with "dedicated lane"
as the safe default regardless of Step 4's outcome (see Implementation Detail step 2 above), so no
`Depends on:` declaration is needed. If Step 4 lands a real fix before this step ships, the file
can be folded into `$SAFE_POOL` as a follow-up adjustment, not a blocking prerequisite.

**Acceptance Criteria:**
- [ ] The command of `gate:bats_all` in `execution.yaml` invokes real parallel execution
  (`bats -j`), never the `exit 86` stub
- [ ] `aid-bats-parallel-lane.sh` excludes both boundary files from the parallel pool by default
- [ ] A full run over the ~81-file safe pool (not just a 10-file sample) passes with 0 failures and
  no leaked/mutated repo state
- [ ] `test-aid-bats-parallel-lane.bats` covers the partition logic and a real small-scale parallel
  invocation

**Effort:** M
**AID Role:** backend

---

### Step 4: Root-cause `test-aid-plan-final-boundary`'s unbounded/accelerating cost

**Objective:** Determine whether the file's accelerating per-test cost (observed this session:
~5s early in the file, 40-53s later, concentrated in its 39-test `AC5` section) is a real defect
in the test/fixture code or an artifact of this session's own environmental contention (other
background diagnostic work sharing the same host), and fix it if a real defect is found.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — only if
  a real defect is found and fixed (e.g. an unintended shared-state accumulation within AC5); no
  change if the investigation confirms the cost is inherent to AC5's real git operations
- Create: `.aid-o/work/evidence/P071/final-boundary-root-cause.md` — records the investigation's
  method, findings, and final disposition (fixed / confirmed-inherent-dedicated-lane), regardless
  of which outcome is reached — this file is what AC4 checks for

**Architecture Context:** `test-aid-plan-final-boundary.bats` uses the shared
`setup_test_evidence_dir`/`teardown_test_evidence_dir` helpers (`test-helpers.bash`) for per-test
isolation — a fresh `mktemp -d` + `git init` per test. `AC5`'s 39 tests additionally perform real
git merge/tag/lifecycle-receipt-commit operations on top of that per-test fixture.

**Implementation Detail:**
1. Reproduce under controlled conditions: run
   `timeout 3600 bats --timing --tap plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats`
   on a host with no other concurrent background load and a freshly-cleared `/tmp` (the diagnostic
   session that found this pattern had substantial other background work running concurrently on
   the same host — a real confound this step must control for).
2. Compare the reproduced per-test timing curve against this session's original observation (test
   #10≈5.5s, #50≈73s, #100≈52s). If the controlled re-run shows a materially flatter curve, the
   original acceleration was environmental — document this and move to step 4 below without a code
   fix. If the curve reproduces, proceed to step 3.
3. If reproduced: instrument `AC5`'s tests (temporary `set -x` / explicit `date` calls around the
   git merge/tag/commit operations) to find whether cost grows with test ordinal position due to
   shared/accumulating state (e.g. a `mktemp -d` not actually getting a fresh directory, disk/inode
   bloat from a prior test's incomplete cleanup, or a real algorithmic cost that scales with
   something that grows across the file such as git object count in a shared clone that ISN'T
   actually being reset per test despite calling `setup_test_evidence_dir`).
4. Fix the specific mechanism found in step 3, or, if the cost is confirmed to be an intrinsic
   property of real per-test git merge/tag/commit operations (i.e. every test's own git operations
   are independently expensive by design, not accumulating), no code fix is needed.
5. Write `.aid-o/work/evidence/P071/final-boundary-root-cause.md` with the method, findings, and
   final disposition either way.
6. This step's outcome never gates Step 3 — Step 3 ships with "dedicated lane" as its safe default
   regardless of what this step finds; a real fix found here can be folded into Step 3's
   `$SAFE_POOL` as a follow-up adjustment afterward, not as a blocking prerequisite.

**Error Handling:** If the timeboxed investigation (this step's own effort budget) does not
converge on a root cause, the accepted fallback is: document the inconclusive finding in
`final-boundary-root-cause.md`, and confirm Step 3's dedicated-lane treatment stands as the
permanent (not just interim) mitigation. This is an explicit, valid step completion per this
plan's own Constraints — never an indefinite extension.

**Edge Cases:**
- The controlled re-run itself might not fit within a reasonable step timebox if the file genuinely
  needs 1+ hours per attempt — budget for at most 2 full re-run attempts (one to confirm/deny the
  environmental hypothesis, one more only if the first attempt's own conditions were imperfectly
  controlled) before treating the investigation as timeboxed-out.
- If a fix is found and applied, it MUST be re-verified with a full run (not just the previously-
  slow AC5 subset) to confirm no regression in the file's other 206 tests.
- The step-3 instrumentation (temporary `set -x`/`date` calls) could itself perturb timing enough
  to mask or exaggerate the real signal — remove instrumentation and re-time cleanly before
  drawing a final conclusion, never conclude directly from an instrumented run's own numbers.

**Dependencies:**
- Depends on: ---
- Blocks: none

**Acceptance Criteria:**
- [ ] `.aid-o/work/evidence/P071/final-boundary-root-cause.md` exists and states a final
  disposition (fixed / confirmed-inherent-dedicated-lane / timeboxed-inconclusive-dedicated-lane)
- [ ] If a fix was applied, a full re-run of the file (not just AC5) confirms 0 regressions
- [ ] If no fix was applied, the evidence file explicitly confirms Step 3's dedicated-lane
  treatment is the accepted permanent mitigation, not a placeholder pending further work

**Effort:** M
**AID Role:** backend

## Constraints

- Never modify `aid-select-tests.sh` (inherited from P066/P070 — still out of scope for this
  plan; scheduling *which* tests to select is P069's job, this plan only changes *whether the
  ones already selected can run concurrently*).
- No new process supervisor — parallel execution in Step 3 uses `bats`'s own existing `-j N` /
  GNU-parallel integration (already present on the host, version 20221122 verified this session),
  never a hand-rolled scheduler.
- Step 4's investigation is timeboxed — if root cause is not found within the step's own effort
  budget, the fallback (documented finding + permanent dedicated lane, already Step 3's design)
  is accepted as the step's completion, not an open-ended extension.

## Resources Verification

### Existing Resources (must exist in codebase)

- [x] `.aid-o/config/execution.yaml` — holds `gate:plan_diff`, `gate:shell_pipeline_smoke`,
  `gate:bats_all` definitions and the `p064-closure` profile rationale comment cited above
  (verified: read directly this session, lines ~38-228)
- [x] `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` — the real command behind
  `gate:shell_pipeline_smoke` (verified: exists, header read this session)
- [x] `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — 245 tests,
  39 under `AC5` (verified: exists, `grep -c '@test "AC5'` = 39, this session)
- [x] `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats` — 267
  tests, real complete measurement 2572.99s this session (verified: exists, full run completed
  exit 0)
- [x] `bats` 1.8.2 with `-j`/GNU-parallel support, GNU parallel 20221122 — both present on the
  dev host (verified: `bats --version`, `parallel --version`, this session)
- [x] `.aid-o/work/test-audits/audit-20260802-070629/implementation-plan-brief.md` +
  `consolidated-findings.json` — the source evidence for all 4 steps (verified: exists, produced
  by this session's diagnostic pass + P066's own finalize chain)

### Plan Assumptions (must match reality)

- [x] `gate:bats_all`'s current command is exactly
  `echo 'BATS_ALL_QUARANTINED: PM approval required; run targeted/standard gates and record an
  explicit FSM waiver' >&2; exit 86` (verified: `.aid-o/config/execution.yaml`, this session) — it
  performs no real execution today, so Step 3 is additive (a working implementation where none
  exists), not a modification of working behavior.
- [x] No `test-*.sh` regex or file path referenced by this plan's steps has been renamed/removed
  since this session's diagnostic pass (same session, no intervening commits to these files).

### Resolution

- [x] All items verified against real, current codebase state this session — none absent.

## Acceptance Criteria

- [ ] AC1: `gate:plan_diff`'s `timeout_seconds` in `execution.yaml` is no longer the bare `120`
  value with an unresolved attribution question, and the profile rationale comment names which
  gate(s) the cited incident duration actually belongs to
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "[ \"$(yq -r '.gates.plan_diff.timeout_seconds' .aid-o/config/execution.yaml)\" != \"120\" ]"
    expected_exit: 0
  ```

- [ ] AC2: `gate:shell_pipeline_smoke`'s name or its `execution.yaml` description no longer implies
  a fast/partial "smoke" check
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "grep -B2 -A5 'shell_pipeline_smoke' .aid-o/config/execution.yaml | grep -qiE 'full (aggregate|suite)|renamed|rescoped'"
    expected_exit: 0
  ```

- [ ] AC3: `gate:bats_all` (or its replacement gate name) invokes real parallel execution rather
  than the `exit 86` quarantine stub
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "yq -o=json '.gates' .aid-o/config/execution.yaml | jq -e '[.[] | select(.command // \"\" | test(\"bats -j|bats.*--jobs\"))] | length > 0'"
    expected_exit: 0
  ```

- [ ] AC4: `test-aid-plan-final-boundary.bats`'s disposition is explicitly documented — either a
  real fix landed (file completes within a stated, evidence-based ceiling) or a root-cause finding
  + accepted dedicated-lane mitigation is recorded
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "find .aid-o/work/evidence -iname '*final-boundary*root-cause*' -o -iname '*final-boundary*disposition*' | grep -q ."
    expected_exit: 0
  ```

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Step 4's root cause turns out to be genuinely hard to isolate (real git-operation cost vs. environmental) | medium | medium | Timeboxed per Constraints; accepted fallback is documented-finding + dedicated lane, which Step 3 already designs for either way |
| Enabling `bats -j N` in Step 3 surfaces a real collision the 10-file diagnostic sample didn't exercise | low | medium | Step 3 must re-verify with the FULL ~81-file safe subset (not just the 10-file sample) before any CI wiring change ships, per this session's own brief evidence caveat |
| `gate:plan_diff` attribution investigation (Step 1) finds the 34-minute incident genuinely was `plan_diff` alone | low | low | No re-plan needed — that outcome still resolves AC1 (a confirmed, evidence-based timeout value either way) |

## Success Criteria

- All 4 `implementation-plan-brief.md` items reach a concrete, evidence-recorded resolution (fix
  landed, or — for Step 4 only — a documented root-cause finding with an accepted interim
  mitigation).
- The confirmed-safe ~81-file bats subset can run via a single real parallel invocation, verified
  against the FULL subset (not just this session's 10-file sample).
- No change to `aid-select-tests.sh` or any scheduler behavior (still P069's job).

## Next Steps

- [ ] PM reviews this plan.
- [ ] Run `aid-plan-lint.sh` and the normal CP1 review pass before any EPIC generation.
- [ ] Do not run `/aid-run` until EPICs exist and the CP1 outcome is reviewed.

---

**Last Updated:** 2026-08-02
