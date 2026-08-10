---
id: P019
type: plan
status: done
created: 2026-02-28
author: PM + AI
---

# P019 — Post-Session Quality & Pipeline Hardening

## Context

FIRST AID session FA-20260228T080115Z completed 5 EPICs (Plans P017+P018) with 100% gate pass rate and 0 escalations. The `/aid-analytics` post-session report identified 5 improvement recommendations across quality, reliability, and efficiency. These range from critical pipeline script bugs that cause test failures with non-numeric plan IDs to low-priority parallelism tuning. This plan addresses all 5 recommendations in priority order.

## Goal

Harden the AID pipeline scripts, add test infrastructure, activate the Curator in FIRST AID, refine EPIC scope declarations, and improve plan-to-EPIC conversion robustness — so the next FIRST AID session runs with higher reliability and observability.

## Scope

**In-scope:**
- Fix 3 known pipeline script bugs (EPIC ID regex, dependency parser, README field name)
- Extend dependency parser with range notation support (`Steps 1-14` → individual step numbers) and cross-phase dependency stripping
- Document phase marker format (`**EPIC N: Steps M-P — Title**`) in `skills/plan-writing.md` so LLM-generated plans always use the correct format
- Create `run-all-tests.sh` aggregator script
- Update `gates.yaml` to use `run-all-tests.sh` as the default `tests_pass` command
- Wire `tests_pass` gate into the gate evaluation flow for this project
- Investigate and fix Curator non-activation in FIRST AID mode
- Add `### Allowed files/paths` granularity guidance to EPIC template
- Update existing tests to cover the bug fixes
- Wire the parallel EPIC dispatch protocol (designed in `aid-first-aid.md` sections 3.1-3.5) into `first-aid-controller.md` so the Controller reliably activates independence detection during QUEUE_PROCESSING
- Update CHANGELOG and docs

**Out-of-scope:**
- Adding new test frameworks (vitest, pytest) — existing bash tests are sufficient
- Rewriting the parallel dispatch detection algorithm (already designed in `aid-first-aid.md` sections 3.1-3.5)
- Modifying the 11-state FSM or adding new states
- GUI or frontend changes

## Approach

*Phase 1 (EPIC 1/2): Pipeline Bug Fixes + Test Runner + Plan Format Docs* — Fix the 3 script bugs, extend the dependency parser with range/cross-phase support, document phase marker format in `plan-writing.md`, create `run-all-tests.sh`, update `gates.yaml`, add/update tests to cover fixes. This is the critical path — the bugs block non-numeric plan IDs and the test runner is a prerequisite for the `tests_pass` gate.

*Phase 2 (EPIC 2/2): Curator Activation + Scope Refinement + Parallel Dispatch Integration + Final Docs* — Diagnose why Curator proposals were 0 in the FIRST AID session, fix the root cause, update the EPIC template with scope granularity guidance, wire the parallel EPIC dispatch protocol into `first-aid-controller.md`, and update documentation.

**Alternatives considered:**
- *Single EPIC* — rejected because Phase 2 (Curator investigation) may require reading runtime logs and the fix could be in skill files vs. agent files. Keeping it separate reduces blast radius.
- *3 EPICs (one per priority tier)* — rejected as over-split. The LOW recommendation (#5) is guidance-only and fits naturally into Phase 2's scope refinement work.

## Implementation Steps

**EPIC 1: Steps 1-5 — Pipeline Bug Fixes, Dependency Parser Enhancements, and Test Runner**

### Step 1: Fix EPIC ID Regex in aid-auto-pipeline.sh

**Objective:** Allow `aid-auto-pipeline.sh` to extract EPIC IDs from filenames that contain non-numeric plan ID prefixes (e.g., `E-TEST-001-1_1`).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (line ~254) — relax the EPIC ID regex to accept alphanumeric plan ID segments
- Test: `plugins/aid-orchestrator/scripts/tests/test-full-pipeline.sh` — add test case with non-numeric plan ID fixture

**Architecture Context:**
`aid-auto-pipeline.sh` is the master orchestration script that calls 4 sub-scripts in sequence. At line 254, after `aid-plan-to-epic.sh` generates an EPIC file, the pipeline extracts the EPIC ID from the generated filename using regex `(E-[0-9]+-[0-9]+_[0-9]+)`. This regex requires purely numeric segments after the `E-` prefix, which fails for plan IDs like `P-TEST-001` that produce EPIC filenames like `E-TEST-001-1_1-minimal-test-plan.md`. The sub-scripts themselves handle non-numeric IDs fine — only this extraction regex is the bottleneck.

**Implementation Detail:**
Change the regex on line 254 from:
```bash
if [[ "$epic_basename" =~ (E-[0-9]+-[0-9]+_[0-9]+) ]]; then
```
to:
```bash
if [[ "$epic_basename" =~ (E-[A-Za-z0-9]+-[0-9]+_[0-9]+) ]]; then
```
This allows the plan ID segment (between `E-` and the first `-N_M` suffix) to contain letters, digits, and hyphens. The phase/total suffix (`-[0-9]+_[0-9]+`) remains strictly numeric since that's structurally required.

Verify the change doesn't break existing numeric plan IDs by running the full test suite — all existing tests use numeric IDs (P018, P099) and must continue to pass.

**Error Handling:**
- If the regex still fails to match (truly malformed filename), the existing `error_exit` call on line 257 remains as the fallback. No change needed to error handling — only the regex pattern changes.

**Edge Cases:**
- EPIC filename `E-TEST-001-1_1-minimal-test-plan.md` — must extract `E-TEST-001-1_1` (currently fails, this fix resolves it)
- EPIC filename `E-018-2_3-script-pipeline-commands.md` — must still extract `E-018-2_3` (existing numeric format, must not regress)
- EPIC filename with hyphens in slug `E-MY-PROJECT-1_2-some-feature.md` — must extract `E-MY-PROJECT-1_2`

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] Regex `(E-[A-Za-z0-9]+-[0-9]+_[0-9]+)` correctly extracts `E-TEST-001-1_1` from `E-TEST-001-1_1-minimal-test-plan.md`
- [ ] All 16 existing integration tests in `test-full-pipeline.sh` continue to pass
- [ ] New test case in `test-full-pipeline.sh` verifies extraction with a non-numeric plan ID fixture

**Effort:** S
**AID Role:** backend

---

### Step 2: Fix Dependency Parser in aid-plan-to-epic.sh

**Objective:** Make the dependency parser in `aid-plan-to-epic.sh` correctly extract step numbers even when trailing descriptive text follows the step reference, support range notation (`Steps 1-14`), and strip cross-phase dependencies that are implicit in chain queue mode.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (lines ~394-401) — strip trailing text after step number extraction, add range expansion, add cross-phase dependency stripping
- Test: `plugins/aid-orchestrator/scripts/tests/test-plan-to-epic.sh` — add test cases for trailing text, range notation, and cross-phase stripping

**Architecture Context:**
`aid-plan-to-epic.sh` parses plan step sections and extracts dependency declarations from lines like `- Depends on: Step 1 — provides the base configuration`. The awk script at lines 394-401 uses `gsub(/Step /, "", $0)` to remove the "Step " prefix and `gsub(/[()]/, "", $0)` to strip parentheses, but it has three problems discovered during P020 pipeline execution:

1. **Trailing text:** A line like `Step 1 — provides the base configuration` produces `1 — provides the base configuration` instead of just `1`.
2. **Range notation:** Plans generated by the LLM sometimes use `Steps 1-14` or `Steps 1, 2, ..., 14` to express dependencies on all prior steps. The parser does not expand ranges — it passes the raw string downstream, causing `aid-epic-to-json.sh` validation to fail with "unresolvable dependency".
3. **Cross-phase references:** When a step in EPIC 2 (e.g., Step 15 renumbered to Step 1) says `Depends on: Steps 1-14`, those steps belong to EPIC 1 and don't exist in EPIC 2's scope. In chain queue mode, cross-phase dependencies are implicit (EPIC 2 waits for EPIC 1 to complete). The parser should detect and strip such references, emitting no dependency for the step within its EPIC.

**Implementation Detail:**

**Part A — Trailing text stripping (existing bug):**
After the existing `gsub` calls in the awk script (line 398-399), add a line to extract only the leading numeric value:
```awk
# After gsub(/[()]/, "", $0)
# Strip trailing text after the step number(s)
# "1 — provides base config" → "1"
# "1, 2 — both needed" → "1, 2"
gsub(/[[:space:]]*[-—].*/, "", $0)
# Also strip any trailing non-numeric, non-comma, non-space chars
gsub(/[^0-9, \-]/, "", $0)
# Trim whitespace
gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
```

**Part B — Range expansion:**
After extracting the raw dependency string, check for range patterns and expand:
```bash
# Expand range notation: "1-14" → "1, 2, 3, ..., 14"
# Called after awk extraction, before validation
expand_dep_ranges() {
  local input="$1"
  local result=""
  # Split on comma
  IFS=',' read -ra parts <<< "$input"
  for part in "${parts[@]}"; do
    part="$(echo "$part" | xargs)"  # trim
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local start="${BASH_REMATCH[1]}"
      local end="${BASH_REMATCH[2]}"
      for ((i=start; i<=end; i++)); do
        [[ -n "$result" ]] && result+=", "
        result+="$i"
      done
    else
      [[ -n "$result" ]] && result+=", "
      result+="$part"
    fi
  done
  echo "$result"
}
```

**Part C — Cross-phase dependency stripping:**
After expanding ranges, filter out step numbers that fall outside the current EPIC's step range. The function receives the EPIC's first and last step numbers (derived from the phase marker `**EPIC N: Steps M-P**`):
```bash
# Strip dependencies outside this EPIC's step range
# E.g., EPIC 2 covers Steps 15-15; dep "1, 2, ..., 14" → empty
strip_cross_phase_deps() {
  local deps="$1"
  local epic_first="$2"
  local epic_last="$3"
  local result=""
  IFS=',' read -ra nums <<< "$deps"
  for num in "${nums[@]}"; do
    num="$(echo "$num" | xargs)"
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= epic_first && num <= epic_last )); then
      [[ -n "$result" ]] && result+=", "
      result+="$num"
    fi
  done
  echo "$result"
}
```
If after stripping all dependencies are removed (empty string), the step gets an empty `depends_on` array — which is correct for chain queue mode where EPIC sequencing handles the dependency.

**Error Handling:**
- If the dependency line contains no recognizable step number after stripping, the awk script prints an empty string. The consuming code in `aid-epic-to-json.sh` already handles empty dependency arrays gracefully (step gets no `depends_on` entries).
- If range notation has start > end (e.g., `14-1`), produce empty expansion and log a warning to stderr.

**Edge Cases:**
- `Depends on: Step 1 — provides the base configuration` → extracts `1`
- `Depends on: Step 1, Step 3 — both provide inputs` → extracts `1, 3`
- `Depends on: Step 2` (no trailing text) → extracts `2` (no regression)
- `No dependencies — can start independently` → awk `Depends on:` match fails, prints nothing (correct)
- `Depends on: Steps 1-14 — all changes must be complete` → range expands to `1, 2, 3, ..., 14`; if current EPIC covers Steps 15-15, all are stripped → empty deps
- `Depends on: Steps 1, 2, 3, 4, 5, 6, 7` (explicit list) → works as before (no range to expand)
- `Depends on: Step 1, Steps 3-5` (mixed format) → extracts `1, 3, 4, 5`
- `Depends on: Steps 14-1` (reversed range) → warning, empty expansion

**Dependencies:**
- No dependencies — can start independently (parallel with Step 1)

**Acceptance Criteria:**
- [ ] Dependency parser extracts `1` from `Depends on: Step 1 — provides the base configuration`
- [ ] Dependency parser extracts `1, 3` from `Depends on: Step 1, Step 3 — both needed`
- [ ] Range `Steps 1-14` expands to `1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14`
- [ ] Cross-phase stripping: for EPIC covering Steps 15-15, dependency `1, 2, ..., 14` becomes empty
- [ ] Mixed format `Step 1, Steps 3-5` produces `1, 3, 4, 5`
- [ ] Reversed range `Steps 14-1` produces warning and empty expansion
- [ ] All 10 existing unit tests in `test-plan-to-epic.sh` continue to pass
- [ ] New test cases in `test-plan-to-epic.sh` verify: trailing text stripping, range expansion, cross-phase stripping

**Effort:** M
**AID Role:** backend

---

### Step 3: Fix README Field Name Mismatch (queued_at vs added_at)

**Objective:** Align the `scripts/README.md` documentation with the actual implementation so the queue entry field name is consistent.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/README.md` (line ~360) — change `queued_at` to `added_at` in the Queue Entry Format example
- Test: `plugins/aid-orchestrator/scripts/tests/test-regression.sh` (lines ~599-618) — tighten test D4 to expect only `added_at` instead of accepting both field names

**Architecture Context:**
`aid-queue-add.sh` (line 449) writes `added_at: "$timestamp"` in the queue YAML entry. However, `scripts/README.md` (line 360) documents the field as `queued_at`. The regression test D4 currently accepts either field name as a workaround. After fixing the README, the test should be tightened to only accept `added_at`, which is the actual field name used by the implementation and by all existing queue entries in `.aid-o/04-engine/epic-queue.yaml`.

**Implementation Detail:**
1. In `scripts/README.md`, line 360, change:
   ```yaml
   queued_at: 2026-02-28T14:30:00Z
   ```
   to:
   ```yaml
   added_at: 2026-02-28T14:30:00Z
   ```

2. In `test-regression.sh`, lines ~611-618, simplify the dual-field check to only look for `added_at`:
   ```bash
   timestamp_count="$(grep -c "added_at:" "$QUEUE_FILE" 2>/dev/null || echo 0)"
   timestamp_field="added_at"
   ```
   Remove the `elif grep -q "queued_at:"` fallback branch entirely.

**Error Handling:**
- No runtime error handling needed — this is a documentation and test fix only. The implementation (`aid-queue-add.sh`) is already correct and does not change.

**Edge Cases:**
- Existing queue files (`.aid-o/04-engine/epic-queue.yaml`) already use `added_at` — no migration needed
- The `skills/epic-queue.md` skill also uses `added_at` — already consistent

**Dependencies:**
- No dependencies — can start independently (parallel with Steps 1-2)

**Acceptance Criteria:**
- [ ] `scripts/README.md` Queue Entry Format example shows `added_at` (not `queued_at`)
- [ ] `test-regression.sh` test D4 only checks for `added_at` field
- [ ] All 20 regression tests pass after the change

**Effort:** S
**AID Role:** backend

---

### Step 4: Create run-all-tests.sh Aggregator Script

**Objective:** Create a single-command test runner that executes all 6 test scripts and reports unified pass/fail results.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` — master test runner script
- Modify: `plugins/aid-orchestrator/scripts/README.md` (add section after "Directory Structure") — document the test runner

**Architecture Context:**
The scripts/tests/ directory contains 6 test scripts: `test-plan-to-epic.sh` (10 tests), `test-epic-to-json.sh` (10 tests), `test-json-to-run.sh` (10 tests), `test-queue-add.sh` (10 tests), `test-full-pipeline.sh` (16 tests), `test-regression.sh` (20 tests). Each script follows the same pattern: `set -uo pipefail`, counters `TESTS_RUN`/`TESTS_PASSED`, and exits 0 if all pass, 1 if any fail. Currently there is no way to run all 76 tests with a single command. The `tests_pass` gate in `gates.yaml` needs a single command to invoke.

**Implementation Detail:**
Create `run-all-tests.sh` with the following structure:
```bash
#!/usr/bin/env bash
# =============================================================================
# run-all-tests.sh — Run all AID pipeline test suites
#
# Usage:
#   ./run-all-tests.sh [--verbose]
#
# Runs all test scripts in order: unit tests first (4 scripts), then
# integration (1 script), then regression (1 script).
#
# Exit codes: 0=all suites passed, 1=one or more suites failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE="${1:-}"

SUITES=(
  "test-plan-to-epic.sh"
  "test-epic-to-json.sh"
  "test-json-to-run.sh"
  "test-queue-add.sh"
  "test-full-pipeline.sh"
  "test-regression.sh"
)

SUITES_RUN=0
SUITES_PASSED=0
SUITES_FAILED=0
TOTAL_TESTS=0
TOTAL_PASSED=0

for suite in "${SUITES[@]}"; do
  suite_path="$SCRIPT_DIR/$suite"
  if [[ ! -x "$suite_path" ]]; then
    echo "SKIP  $suite (not found or not executable)"
    continue
  fi

  SUITES_RUN=$((SUITES_RUN + 1))
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  SUITE: $suite"
  echo "═══════════════════════════════════════════════════════"

  if output="$("$suite_path" 2>&1)"; then
    SUITES_PASSED=$((SUITES_PASSED + 1))
    status="PASS"
  else
    SUITES_FAILED=$((SUITES_FAILED + 1))
    status="FAIL"
  fi

  # Extract test counts from suite output (last line pattern: "N/M tests passed")
  suite_total="$(echo "$output" | grep -oE '[0-9]+/[0-9]+ tests passed' | tail -1 || true)"
  if [[ -n "$suite_total" ]]; then
    passed="${suite_total%%/*}"
    total="${suite_total#*/}"
    total="${total%% *}"
    TOTAL_TESTS=$((TOTAL_TESTS + total))
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
  fi

  if [[ "$VERBOSE" == "--verbose" ]] || [[ "$status" == "FAIL" ]]; then
    echo "$output"
  fi

  echo "  [$status] $suite ${suite_total:+(${suite_total})}"
done

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  SUMMARY"
echo "═══════════════════════════════════════════════════════"
echo "  Suites: $SUITES_PASSED/$SUITES_RUN passed"
echo "  Tests:  $TOTAL_PASSED/$TOTAL_TESTS passed"
echo "═══════════════════════════════════════════════════════"

if [[ "$SUITES_FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
```

Make the script executable with `chmod +x`.

Add a section to `scripts/README.md` before the "## Shared Library" section:
```markdown
## Running Tests

Run all test suites with the aggregator script:

```bash
./scripts/tests/run-all-tests.sh            # summary only
./scripts/tests/run-all-tests.sh --verbose   # full output from each suite
```

Individual suites can also be run directly:

```bash
./scripts/tests/test-plan-to-epic.sh    # 10 unit tests
./scripts/tests/test-epic-to-json.sh    # 10 unit tests
./scripts/tests/test-json-to-run.sh     # 10 unit tests
./scripts/tests/test-queue-add.sh       # 10 unit tests
./scripts/tests/test-full-pipeline.sh   # 16 integration tests
./scripts/tests/test-regression.sh      # 20 regression tests
```
```

**Error Handling:**
- If a suite script is missing or not executable, skip it with a `SKIP` message and continue to the next suite. Do not fail the runner because one suite is absent.
- If a suite hangs (no built-in timeout — the `tests_pass` gate in `gates.yaml` has `timeout_seconds: 300` which covers the total gate execution time).

**Edge Cases:**
- Suite outputs "0/0 tests passed" (empty test file) — counts as pass (0 failures)
- Suite has no "N/M tests passed" line in output — TOTAL_TESTS and TOTAL_PASSED are not incremented for that suite, but pass/fail is still determined by exit code
- Run from any working directory — `SCRIPT_DIR` resolution handles relative invocation

**Dependencies:**
- Depends on: Step 1, Step 2, Step 3

**Acceptance Criteria:**
- [ ] `run-all-tests.sh` executes all 6 suites and exits 0 when all pass
- [ ] `run-all-tests.sh` exits 1 when any suite fails
- [ ] Summary line shows correct total counts (76+ tests across 6 suites)
- [ ] `--verbose` flag shows full output from each suite
- [ ] Script is executable (`chmod +x`)
- [ ] `scripts/README.md` documents the test runner with usage examples

**Effort:** M
**AID Role:** backend

---

### Step 5: Update gates.yaml for tests_pass Gate

**Objective:** Configure the `tests_pass` gate to use `run-all-tests.sh` as the default command, replacing the placeholder `pytest` command.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/policies/gates.yaml` (lines ~6-10) — update `tests_pass` command and description
- Modify: `.aid-o/03-config/policies/gates.yaml` (lines ~6-10) — same update in the project-level config

**Architecture Context:**
`gates.yaml` defines quality gates that the Controller evaluates in the GATES state (see `skills/gate-evaluation.md`). The `tests_pass` gate is already defined with `required: true` and `command: "pytest -q --tb=short"`. This project does not use pytest — the tests are bash scripts in `plugins/aid-orchestrator/scripts/tests/`. The gate command needs to point to `run-all-tests.sh` created in Step 4. Both the default template (`defaults/policies/gates.yaml`) and the project-level config (`.aid-o/03-config/policies/gates.yaml`) must be updated.

**Implementation Detail:**
In both files, update the `tests_pass` gate:
```yaml
gates:
  tests_pass:
    description: "All pipeline tests pass (unit + integration + regression)"
    required: true
    command: "./plugins/aid-orchestrator/scripts/tests/run-all-tests.sh"
    timeout_seconds: 300
    pass_criteria: "exit code 0"
```

Also update `lint_pass` and `security_scan_pass` gates: since this project doesn't use ruff or bandit, set both to `required: false` to avoid false failures. The gates already have a `when` conditional pattern — add `when: "python files changed"` to both:
```yaml
  lint_pass:
    description: "Code passes linting and formatting checks"
    required: false
    command: "ruff check . && ruff format --check ."
    timeout_seconds: 120
    pass_criteria: "exit code 0"
    when: "python files changed"

  security_scan_pass:
    description: "No high/critical security findings"
    required: false
    command: "bandit -q -r . -ll"
    timeout_seconds: 180
    pass_criteria: "exit code 0, no HIGH or CRITICAL findings"
    when: "python files changed"
```

**Error Handling:**
- If `run-all-tests.sh` is not found at the configured path, the gate command will exit with a non-zero code and the Controller will treat it as a gate failure — triggering retry and then escalation. This is the correct behavior (missing test runner = test failure).

**Edge Cases:**
- EPIC that changes only markdown (no script changes) — `tests_pass` still runs (it's `required: true`). This is intentional: even doc-only changes should not break existing tests.
- EPIC in a different project using AID — the `defaults/policies/gates.yaml` template now ships with `run-all-tests.sh` as the default command. Projects without this script will need to customize `gates.yaml` during `/aid-setup`. This is acceptable — `gates.yaml` is always project-customized.

**Dependencies:**
- Depends on: Step 4

**Acceptance Criteria:**
- [ ] `defaults/policies/gates.yaml` `tests_pass.command` is `./plugins/aid-orchestrator/scripts/tests/run-all-tests.sh`
- [ ] `.aid-o/03-config/policies/gates.yaml` `tests_pass.command` matches the defaults
- [ ] `lint_pass` and `security_scan_pass` gates are set to `required: false` with `when` condition
- [ ] Gate evaluation in a test EPIC run executes `run-all-tests.sh` and reports pass/fail correctly

**Effort:** S
**AID Role:** backend

---

**EPIC 2: Steps 6-10 — Curator Activation, Scope Refinement, Parallel Dispatch Integration, Phase Marker Docs, and Final Documentation**

### Step 6: Investigate and Fix Curator Non-Activation

**Objective:** Diagnose why the Curator agent produced 0 proposals during FIRST AID session FA-20260228T080115Z and ensure it activates correctly in future sessions.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (CURATOR_RESOLVE section, lines ~169-192) — fix any conditional that skips Curator dispatch
- Modify: `plugins/aid-orchestrator/skills/gate-evaluation.md` (CURATOR_RESOLVE section, lines ~308-325) — verify dispatch conditions are correct
- Test: `plugins/aid-orchestrator/scripts/tests/test-regression.sh` — add test verifying Curator dispatch instructions are present in gate-evaluation.md

**Architecture Context:**
The CURATOR_RESOLVE state in `gate-evaluation.md` dispatches both the Curator agent and the Lessons-Extractor agent in parallel after all gates pass. The `first-aid-controller.md` defines auto-mode behavior: effort:S proposals are auto-implemented, effort:M/L are deferred to backlog. Session FA-20260228T080115Z shows `total_curator_proposals: 0` across all 5 EPICs. Possible causes: (a) the CURATOR_RESOLVE state was skipped entirely, (b) the Curator agent was dispatched but found nothing, or (c) there is a conditional in the auto-mode path that short-circuits Curator dispatch.

**Implementation Detail:**
1. Read the CURATOR_RESOLVE section in `gate-evaluation.md` fully. Check if there's a condition that skips Curator dispatch (e.g., "if no discovered issues from PHASE_CHECK, skip Curator"). If found, remove the skip condition — the Curator should always run, even when PHASE_CHECK found no issues, because it performs broader code review beyond step-specific outputs.

2. Read the CURATOR_RESOLVE auto-mode behavior in `first-aid-controller.md` fully. Verify that mode == "auto" does not bypass Curator dispatch (it should dispatch the same as manual mode, only the proposal evaluation differs).

3. Check the evidence from the session: look at the stage_log.jsonl entries for each EPIC's CURATOR_RESOLVE transition. If the state was reached but Curator returned 0 proposals, that's valid behavior (no improvements found). If the state was never reached (jumped from GATES directly to PM_APPROVAL or DONE), that's the bug.

4. The most likely root cause: the Controller in FIRST AID mode may have transitioned from GATES → PM_APPROVAL without passing through CURATOR_RESOLVE. This could happen if the state machine transition logic in `first-aid-controller.md` DONE State section jumps ahead. Fix by ensuring the state transition chain is: GATES (pass) → CURATOR_RESOLVE → PM_APPROVAL → DONE.

5. Add a log entry at CURATOR_RESOLVE entry point so future sessions have evidence of whether Curator ran:
   ```json
   {"state": "CURATOR_RESOLVE", "action": "curator_dispatch_start",
    "details": "Dispatching Curator + Lessons-Extractor in parallel",
    "result": "pending"}
   ```

**Error Handling:**
- If the Curator agent fails during dispatch (timeout, model error), the existing escalation mechanism in `gate-evaluation.md` handles it — the failure triggers ESCALATION state with retry.
- If the fix changes the state transition path, verify that the evidence directory structure still receives `curator_resolve_report.json` in the expected location.

**Edge Cases:**
- Curator genuinely finds 0 proposals (valid for small, well-scoped EPICs) — the fix should ensure Curator runs but accept 0 proposals as a valid outcome
- Multiple EPICs in sequence (FIRST AID mode) — Curator should run independently for each EPIC, not accumulate state across EPICs
- EPIC with 0 discovered issues from PHASE_CHECK — Curator should still run (it reviews the full diff, not just PHASE_CHECK findings)

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] CURATOR_RESOLVE state is reached for every EPIC that passes GATES (verified by reading the state transition logic)
- [ ] No conditional in `first-aid-controller.md` or `gate-evaluation.md` skips Curator dispatch when `discovered_issues` is empty
- [ ] Evidence log entry added at CURATOR_RESOLVE entry point for observability
- [ ] Regression test verifies CURATOR_RESOLVE dispatch instructions exist in gate-evaluation.md

**Effort:** M
**AID Role:** backend

---

### Step 7: Add EPIC Scope Granularity Guidance to Template

**Objective:** Update the EPIC template and FIRST AID parallel detection documentation to encourage finer-grained `Allowed files/paths` declarations, enabling better cross-EPIC parallelism detection.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/epic.md` — add guidance comments in the `### Allowed files/paths` and `### Forbidden zones` sections
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (scope generation section, lines ~606-612) — generate per-step file paths in allowed section instead of broad directory paths
- Modify: `plugins/aid-orchestrator/commands/aid-first-aid.md` (Section 3.1 Independence Detection Algorithm, step d) — add guidance note about scope granularity

**Architecture Context:**
FIRST AID's parallel detection algorithm (`aid-first-aid.md` Section 3.1) checks `Allowed files/paths` overlap between candidate EPICs. During session FA-20260228T080115Z, E-017 and E-018 could not run in parallel because both had `skills/` and `commands/` as allowed paths — even though E-017 modified `skills/planner.md` and `skills/gate-evaluation.md` while E-018 modified `skills/epic-orchestration.md` and `commands/aid-plan-epic.md` (no actual overlap). Finer scope declarations would have enabled parallelism.

**Implementation Detail:**
1. In `defaults/templates/epic.md`, add guidance comments in the Scope section:
   ```markdown
   ### Allowed files/paths
   <!-- List specific file paths when possible (e.g., `skills/planner.md`)
        instead of broad directories (e.g., `skills/`). This enables FIRST AID
        to detect independent EPICs for parallel execution. Use directory paths
        only when the EPIC genuinely needs to modify any file in that directory. -->
   - `{specific_file_1}`
   - `{specific_file_2}`

   ### Forbidden zones
   <!-- Files/directories this EPIC must NOT modify. Be specific — broad
        forbidden zones (e.g., `skills/`) block parallelism with other EPICs
        that legitimately need different files in that directory. -->
   - `{specific_forbidden_1}`
   ```

2. In `aid-plan-to-epic.sh`, update the scope generation to produce per-file paths from the plan step's Files section when available, falling back to directory paths when the plan doesn't specify individual files:
   - Parse each step's `**Files:**` section for concrete file paths
   - Deduplicate and list individual files in `### Allowed files/paths`
   - Only use directory paths for steps that specify patterns (e.g., `tests/**/*.sh`)

3. In `aid-first-aid.md` Section 3.1 step d, add a guidance note:
   ```markdown
   NOTE: If scope overlap is detected due to broad directory declarations
   (e.g., both EPICs list `skills/`), log a recommendation:
   "Consider using specific file paths in Allowed files/paths for better
   parallelism detection. Broad directory paths reduce parallelism opportunities."
   ```

**Error Handling:**
- If a plan step has no `**Files:**` section, the scope generator falls back to the existing behavior (directory-level paths from the plan's Scope section). This is not an error — it's the expected degradation for steps that don't specify concrete files.

**Edge Cases:**
- Plan step lists files with glob patterns (`tests/**/*.sh`) — use the pattern as-is in allowed paths (the parallel detection algorithm handles glob intersection)
- Plan step lists only "Create:" files (new files in new directories) — these directories don't exist yet, so forbidden zone checks for other EPICs won't find them; this is safe for parallel execution
- EPIC generated from a plan with no Implementation Steps (only High-Level Steps table) — fall back to directory-level scope from the plan's Scope section

**Dependencies:**
- No dependencies — can start independently (parallel with Step 6)

**Acceptance Criteria:**
- [ ] EPIC template includes guidance comments for file-level scope declarations
- [ ] `aid-plan-to-epic.sh` generates per-file paths in `### Allowed files/paths` when plan steps have `**Files:**` sections
- [ ] Generated EPICs list specific files (e.g., `skills/planner.md`) instead of broad directories (e.g., `skills/`) when source data is available
- [ ] `aid-first-aid.md` includes the scope granularity recommendation note

**Effort:** M
**AID Role:** backend

---

### Step 8: Update Documentation and CHANGELOG

**Objective:** Update CHANGELOG, README, and affected skill/command `Last Updated` dates to reflect all changes in this plan.

**Files:**
- Modify: `CHANGELOG.md` — add entries for all changes under `## [Unreleased]`
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical to root CHANGELOG
- Modify: `plugins/aid-orchestrator/scripts/README.md` — verify test runner documentation from Step 4 is complete
- Modify: `plugins/aid-orchestrator/defaults/policies/gates.yaml` — verify `Last Updated` or version comment
- Modify: Any skill/command files modified in Steps 6-7, 9-10 — update `**Last Updated:** 2026-02-28` footer

**Architecture Context:**
Per CLAUDE.md rules: both CHANGELOGs must be identical, every modified skill file must have its `Last Updated` date bumped, and the CHANGELOG format follows Keep a Changelog with `- **Bold Name** — description` entries. This step ensures documentation consistency across all changes in this plan.

**Implementation Detail:**
Add CHANGELOG entries under `## [Unreleased]`:
```markdown
### Fixed
- **Pipeline EPIC ID Regex** — `aid-auto-pipeline.sh` now accepts non-numeric plan ID segments in EPIC filenames (e.g., `E-TEST-001-1_1`)
- **Dependency Parser Trailing Text** — `aid-plan-to-epic.sh` strips trailing descriptive text after step references in dependency declarations
- **Dependency Parser Range Notation** — `aid-plan-to-epic.sh` expands `Steps 1-14` range notation to individual step numbers and strips cross-phase references in chain queue mode
- **README Field Name** — `scripts/README.md` queue entry example corrected from `queued_at` to `added_at` (matches implementation)
- **Curator Non-Activation** — ensured CURATOR_RESOLVE state is always reached in FIRST AID mode regardless of discovered issues count

### Added
- **Test Runner Aggregator** — `run-all-tests.sh` runs all 6 test suites with unified pass/fail reporting and `--verbose` flag
- **Phase Marker Documentation** — `plan-writing.md` now documents the exact `**EPIC N: Steps M-P — Title**` format required by pipeline scripts
- **EPIC Scope Granularity** — template and `aid-plan-to-epic.sh` now generate per-file scope declarations for better FIRST AID parallelism detection
- **Parallel EPIC Dispatch Integration** — `first-aid-controller.md` now includes QUEUE_PROCESSING auto-mode section with independence detection checklist and cross-references to the full protocol

### Changed
- **tests_pass Gate** — default command updated from `pytest` to `run-all-tests.sh`; lint and security gates marked conditional on Python files
```

Update `Last Updated` footer in all modified files to the current date.

**Error Handling:**
- No runtime error handling — this is documentation only.

**Edge Cases:**
- If Step 6 (Curator investigation) reveals no code change is needed (Curator worked but genuinely found 0 proposals), the CHANGELOG "Fixed" entry changes to "Investigated" with the finding documented.
- If the CHANGELOG `## [Unreleased]` section doesn't exist, create it above the `## [1.6.0]` entry.

**Dependencies:**
- No dependencies within this EPIC (step ordering ensures prior steps complete first)

**Acceptance Criteria:**
- [ ] Root `CHANGELOG.md` has all entries under `## [Unreleased]` matching the template above
- [ ] `plugins/aid-orchestrator/CHANGELOG.md` is identical to root
- [ ] All modified skill/command files have `Last Updated` bumped to current date
- [ ] `scripts/README.md` includes the test runner section

**Effort:** S
**AID Role:** docs

---

### Step 9: Document Phase Marker Format in plan-writing.md

**Objective:** Add explicit documentation of the required phase marker format to `skills/plan-writing.md` so that LLM-generated plans always produce markers the pipeline scripts can parse.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` — add a "Phase Markers" subsection in the Plan Document Structure section specifying the exact format
- Modify: `plugins/aid-orchestrator/scripts/README.md` — add phase marker format reference in the aid-plan-to-epic.sh section

**Architecture Context:**
`aid-plan-to-epic.sh` detects phase boundaries using the regex `^\*\*EPIC[[:space:]]+([0-9]+)(:[[:space:]]+Steps[[:space:]]+([0-9]+)-([0-9]+))?`. This means the plan must contain markers in the exact format `**EPIC N: Steps M-P — Title**` (bold, starts with EPIC, followed by number, colon, step range, em-dash, title). During P020 pipeline execution, the LLM generated `### Phase N:` headers which failed parsing (3 pipeline retries). The plan-writing skill (`skills/plan-writing.md`) does not document this format — it only describes step content structure. Adding the format explicitly prevents future LLMs from guessing wrong.

**Implementation Detail:**
1. In `skills/plan-writing.md`, locate the Plan Document Structure section (where `## Implementation Steps` format is described). Add a "Phase Markers (Multi-EPIC Plans)" subsection containing:
   - Explanation that multi-phase plans need marker lines before each phase's first step
   - Required format: bold line starting with `EPIC` followed by number, colon, step range, em-dash, title — i.e. `**EPIC {N}: Steps {first}-{last} — {title}**`
   - Example showing EPIC 1 with Steps 1-5 followed by EPIC 2 with Steps 6-8
   - Rules: sequential numbering from 1, inclusive step ranges, marker on own line before first `### Step`, single-phase plans need no markers
   - "Do NOT use" section listing formats that fail: `### Phase 1:`, `## Phase 1`, unbolded `Phase 1: Steps 1-5`

2. In `plugins/aid-orchestrator/scripts/README.md`, in the `aid-plan-to-epic.sh` section, add a "Phase Marker Format" note documenting the detection regex (`^\*\*EPIC[[:space:]]+...`) and referencing `skills/plan-writing.md` for full documentation.

NOTE: When writing the actual content, the example markers must NOT appear as bare `**EPIC N:` lines in the plan-writing.md file itself outside of indented/fenced blocks, to avoid being parsed as real phase markers by the pipeline script.

**Error Handling:**
- No runtime error handling — this is documentation only. The actual parser behavior doesn't change; this step ensures the input is correct.

**Edge Cases:**
- Plan with a single phase (1 EPIC) — no markers needed, document this explicitly
- Plan with 10+ phases — EPIC number can be multi-digit (regex `[0-9]+` handles this)
- Plan where last EPIC has a single step (e.g., `Steps 15-15`) — valid, document as example

**Dependencies:**
- No dependencies — can start independently (parallel with Steps 1-3)

**Acceptance Criteria:**
- [ ] `skills/plan-writing.md` contains a "Phase Markers" subsection with the exact format, rules, and "do NOT use" examples
- [ ] `scripts/README.md` documents the regex and references `plan-writing.md`
- [ ] The documented format matches the regex in `aid-plan-to-epic.sh` line ~144-162
- [ ] Single-phase plans are documented as not needing markers

**Effort:** S
**AID Role:** docs

---

### Step 10: Wire Parallel EPIC Dispatch into first-aid-controller.md

**Objective:** Integrate the parallel EPIC dispatch protocol (fully designed in `commands/aid-first-aid.md` sections 3.1-3.5) into `skills/first-aid-controller.md` so the Controller reliably activates independence detection and parallel worktree execution during the QUEUE_PROCESSING state.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` — add QUEUE_PROCESSING auto-mode section with parallel dispatch cross-reference and condensed protocol
- Modify: `plugins/aid-orchestrator/commands/aid-first-aid.md` — add Core Instruction bullet referencing `first-aid-controller.md` for QUEUE_PROCESSING auto-mode overrides
- Modify: `plugins/aid-orchestrator/skills/epic-state-machine.md` — add `PARALLEL_EXECUTING` sub-state to the state diagram if not already present

**Architecture Context:**
The parallel EPIC dispatch algorithm exists in `commands/aid-first-aid.md` section 3 (Multi-Agent Parallel Execution): `DETECT_INDEPENDENT_EPICS()` checks scope overlap and declared dependencies, `PARALLEL_DISPATCH()` spawns isolated Task agents in git worktrees, `PARALLEL_COORDINATION()` merges results sequentially, and safety guards enforce `MAX_PARALLEL_AGENTS=3`.

However, `skills/first-aid-controller.md` — the skill the Controller reads for auto-mode behavior at each state — does not mention QUEUE_PROCESSING or parallel dispatch. It only covers PLAN_REVIEW, PHASE_CHECK, ESCALATION, CURATOR_RESOLVE, PM_APPROVAL, and DONE. During the session FA-20260228T080115Z, the Controller processed all 5 EPICs sequentially despite E-017-1_2 and E-018-1_3 having no declared dependencies between them and potentially non-overlapping scopes. The parallel detection was never triggered.

The fix: add a QUEUE_PROCESSING section to `first-aid-controller.md` that:
1. Explicitly activates the independence detection algorithm
2. Provides a condensed decision tree (so the Controller doesn't skip the 200-line section 3 in the command file)
3. Cross-references the full protocol in `aid-first-aid.md` for edge cases

**Implementation Detail:**
1. In `first-aid-controller.md`, add a new section between the existing "How the Controller Reads Mode" section and "PLAN_REVIEW — Auto-Mode Behavior":

   The new section is: `## QUEUE_PROCESSING — Auto-Mode Behavior`

   Content:
   ```
   ## QUEUE_PROCESSING — Auto-Mode Behavior

   IF mode == auto:
     1. After selecting the next EPIC (aid-first-aid.md step 2):
        → Call DETECT_INDEPENDENT_EPICS(selected_epic, queue)
          (full algorithm: aid-first-aid.md section 3.1)
     2. IF candidates >= 2:
        → Log: "Detected {N} independent EPICs for parallel execution"
        → Call PARALLEL_DISPATCH(candidates)
          (full protocol: aid-first-aid.md section 3.2)
        → Call PARALLEL_COORDINATION(agents)
          (merge protocol: aid-first-aid.md section 3.3)
        → Perform WORKTREE_CLEANUP
          (safety: aid-first-aid.md section 3.4)
        → Transition to QUEUE_ADVANCE
     3. IF candidates == 1:
        → Log: "No independent EPICs — sequential execution"
        → Continue to step 4 (Escalation Budget) and step 5 (Execute EPIC)

   IMPORTANT — Independence detection checklist:
     a. Read candidate EPIC files from queue entry paths
     b. Extract "### Allowed files/paths" and "### Forbidden zones" sections
     c. Check: no declared depends_on between candidates
     d. Check: no file scope overlap (directory prefix intersection)
     e. Check: no cross-forbidden zone violations
     f. MAX_PARALLEL_AGENTS = 3 (process remaining in next iteration)
     g. Missing/empty scope → exclude from parallel (fall back to sequential)

   ELSE (mode == manual):
     {QUEUE_PROCESSING does not apply in manual mode — manual mode uses
      /aid-run-epic for individual EPIC execution}
   ```

2. In `commands/aid-first-aid.md`, in the "Core Instruction" section (line ~47), add a 4th skill to the reading list:
   ```
   4. `skills/first-aid-controller.md` — auto-mode overrides for all states including QUEUE_PROCESSING parallel dispatch
   ```

3. In `skills/epic-state-machine.md`, check if `PARALLEL_EXECUTING` sub-state is documented. If not, add a note in the QUEUE_PROCESSING state description:
   ```
   NOTE: In auto-mode, QUEUE_PROCESSING may enter a PARALLEL_EXECUTING
   sub-state when multiple independent EPICs are detected. See
   skills/first-aid-controller.md QUEUE_PROCESSING section and
   commands/aid-first-aid.md section 3 for the full protocol.
   ```

**Error Handling:**
- If independence detection fails (file read error, YAML parse error), fall back to sequential execution. This is the existing safety behavior from `aid-first-aid.md` section 3.4 (UNCERTAIN_SCOPE_FALLBACK).
- If worktree creation fails (disk space, git error), fall back to sequential. Log the error and continue.

**Edge Cases:**
- All queued EPICs are chained (each depends on the previous) — independence detection finds 0 candidates beyond the first → sequential execution (no change from current behavior)
- All queued EPICs are independent with granular scopes — up to 3 run in parallel, rest wait for next QUEUE_PROCESSING iteration
- EPIC file missing or unreadable during scope extraction — skip that candidate, continue detection with remaining
- Mix of independent and dependent EPICs — only the independent subset is dispatched in parallel; dependent EPICs wait in the queue

**Dependencies:**
- No dependencies within this EPIC (step ordering ensures prior steps complete first)

**Acceptance Criteria:**
- [ ] `first-aid-controller.md` has a `## QUEUE_PROCESSING — Auto-Mode Behavior` section with independence detection checklist and parallel dispatch cross-references
- [ ] `aid-first-aid.md` Core Instruction reading list includes `first-aid-controller.md`
- [ ] `epic-state-machine.md` documents `PARALLEL_EXECUTING` sub-state or note
- [ ] The condensed protocol in `first-aid-controller.md` is consistent with the full protocol in `aid-first-aid.md` sections 3.1-3.5
- [ ] No changes to the algorithm itself — only cross-referencing and reinforcement in the auto-mode skill

**Effort:** M
**AID Role:** backend

---

## Testing Strategy

**Unit tests:** Steps 1-3 each add a targeted test case to the relevant test script. Step 2 adds additional tests for range expansion, cross-phase stripping, and mixed format. Total: 6+ new unit tests across 3 scripts.

**Integration tests:** Step 4 creates `run-all-tests.sh` which serves as both the test runner and an integration test of the test infrastructure itself. Running it validates that all 76+ tests pass together.

**Regression tests:** Step 3 tightens the existing regression test D4. Step 6 adds a structural regression test for CURATOR_RESOLVE presence.

**Gate validation:** Step 5 updates `gates.yaml` — the next EPIC run will exercise the `tests_pass` gate with the real test runner.

**Parallel dispatch validation:** Step 10 adds cross-references and a condensed protocol to `first-aid-controller.md`. Acceptance is verified by reading the skill file and confirming consistency with `aid-first-aid.md` sections 3.1-3.5. Functional validation occurs during the next FIRST AID session.

**Coverage target:** All bug fixes have explicit test coverage including the dependency parser range/cross-phase enhancements. The test runner covers all suites. No untested code paths are introduced.

## Constraints

- No new dependencies (no npm packages, no Python tools) — all fixes are in existing bash scripts and markdown files
- All bash changes must remain POSIX-compatible where possible (existing scripts use bash 4.0+ features, so bash 4.0 is the minimum)
- CHANGELOG format must follow Keep a Changelog standard per CLAUDE.md rules
- Both CHANGELOGs (root and plugin) must be identical at all times

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Regex change in Step 1 matches unintended patterns | Low | Medium | New regex only relaxes the plan-ID segment; phase/total suffix stays strict. Tested against existing fixtures. |
| Curator investigation (Step 6) reveals deeper architectural issue | Medium | Medium | If root cause is in the FSM logic rather than a simple conditional, the fix may expand. Capped by EPIC scope — worst case, file a follow-up EPIC. |
| `run-all-tests.sh` test count extraction fails on some test outputs | Low | Low | Fallback: pass/fail still determined by exit code. Count is cosmetic. Tested against all 6 existing suite output formats. |
| Scope refinement in Step 7 changes generated EPIC format | Low | Medium | Changes are additive (more specific paths). Parallel detection algorithm handles both granular and broad paths. No breaking change. |
| Parallel dispatch wiring (Step 10) introduces inconsistency with command file | Low | Low | Step 10 is cross-referencing only — no algorithm changes. Acceptance criteria require consistency check against aid-first-aid.md sections 3.1-3.5. |

## Success Criteria

- [ ] All 3 pipeline script bugs are fixed with test coverage
- [ ] Dependency parser supports range notation (`Steps 1-14`) and strips cross-phase references
- [ ] Phase marker format (`**EPIC N: Steps M-P — Title**`) is documented in `plan-writing.md`
- [ ] `run-all-tests.sh` passes all suites (76+ tests) in a single invocation
- [ ] `gates.yaml` `tests_pass` gate command points to `run-all-tests.sh`
- [ ] Curator dispatch path verified to be reachable in FIRST AID mode
- [ ] EPIC template encourages file-level scope declarations
- [ ] Parallel EPIC dispatch is wired into `first-aid-controller.md` with QUEUE_PROCESSING auto-mode section
- [ ] `aid-first-aid.md` Core Instruction includes `first-aid-controller.md` in the reading list
- [ ] CHANGELOG and documentation are complete and consistent

## Next Steps

After plan approval:
1. Run `/aid-plan-epic .aid-o/01-plans/P019-post-session-quality-hardening.md` to generate EPICs
2. Run `/aid-epic-queue` to verify queue
3. Run `/aid-first-aid` or `/aid-run-epic` to execute
