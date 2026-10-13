# AID Scripts

Bash scripts behind the AID commands. Since 3.0.0 (P114) a plan runs straight
from its file: `aid-plan-fsm.sh plan-run P<NNN>` builds `plan.json` of the whole
plan with the shared reader (`lib/aid-plan-json.sh`), seals CP1 and starts ONE
run on `plan/<id>` (`aid-fsm.sh init --direct`). The EPIC generators, the
generation pipeline and the queue were removed; see the CHANGELOG (3.0.0) for
the way out of an old EPIC run.

```
plan.md ──plan-run──► plan.json (lib/aid-plan-json.sh) ──► fsm-state.yaml on plan/<id>
```

## Prerequisites

| Dependency | Minimum Version | Check Command |
|------------|----------------|---------------|
| bash | 4.0+ | `bash --version` |
| jq | 1.6+ | `jq --version` |
| sed | any (BSD or GNU) | `sed --version 2>/dev/null \|\| echo BSD` |
| awk | any (POSIX) | `awk --version 2>/dev/null \|\| echo BSD` |
| date | any (BSD or GNU) | `date --version 2>/dev/null \|\| echo BSD` |

Install `jq` if missing:

```bash
# macOS
brew install jq

# Debian / Ubuntu
sudo apt install jq

# Fedora / RHEL
sudo dnf install jq
```

All scripts source `lib/common.sh`, which runs `check_prerequisites()` at the
top of each script. If bash < 4.0 or jq is absent, the script exits
immediately with code 2 and printed install guidance.

## Exit Codes

| Code | Meaning | Example |
|------|---------|---------|
| 0 | Success | Script completed normally |
| 1 | Validation error | Malformed EPIC, missing required section, schema mismatch |
| 2 | Missing dependency | bash < 4.0, jq not installed |
| 3 | File I/O error | Input file not found, output directory not writable |

All non-zero exits print a JSON object to stderr:

```json
{"error": "descriptive message", "code": 1}
```

## Shared Library: lib/common.sh

Scripts that parse plans source `lib/common.sh` at startup. This file provides 7 shared
functions and must never be executed directly (it contains a guard that exits
with an error if run as a standalone script).

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `parse_frontmatter` | `parse_frontmatter <file>` | Extract YAML frontmatter as key=value pairs |
| `extract_section` | `extract_section <file> <header>` | Extract H2 section body by header name |
| `extract_subsection` | `extract_subsection <file> <h2> <h3>` | Extract H3 subsection within an H2 |
| `slugify` | `slugify <text>` | Convert text to lowercase hyphenated slug (max 40 chars) |
| `check_prerequisites` | `check_prerequisites` | Verify bash >= 4.0 and jq availability |
| `error_exit` | `error_exit <msg> <code>` | Print JSON error to stderr and exit |
| `iso_timestamp` | `iso_timestamp` | Return current UTC ISO 8601 timestamp |

### Sourcing Pattern

A script that uses it begins with:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
check_prerequisites
```

---

## Testing

All pipeline scripts have comprehensive test suites located in `tests/`. A
master test runner executes all suites and reports unified results.

### Writing a test that can fail

A green test that could never have gone red is worse than no test: it spends
the time and buys the confidence without doing the work. Four rules, each of
them a live incident:

1. **A test must FAIL when its subject is absent.** Delete the function under
   test and the case must go red — not skip, not pass.
2. **`skip` is legal only when it is counted and rendered as skipped**, never
   as passed, and never keyed on whether the subject exists. Key it on a
   platform or environment fact instead (`[ -d /proc ]`, a missing binary). A
   deliberate exception is recorded in place:
   `# content-scan: allow existence-skip — <reason>`.
3. **An assertion must read a DIFFERENT surface than the one that wrote the
   claim.** Asserting that a report says "pass" because the same run wrote
   "pass" into it proves only that a string round-tripped.
4. **`grep -c` under `set -e` needs a guard** (`|| true`): it exits 1 when it
   counts zero, so the assignment kills the suite before it prints anything —
   and a suite that dies early still reports the cases it already ran as green.

`aid-test-content-scan.sh` checks rules 2 and 4 mechanically
(`existence_keyed_skip`, `set_e_grep_count`); rules 1 and 3 need a reader and
are the reason this section exists.

### Test tiers — where a new suite goes (P081)

**Every suite declares its tier in its leading comment block**, once:

```bash
#!/usr/bin/env bats
# aid-tier: t1
```

| Tier | Cost per case | Whole-tier budget | Runs |
|------|---------------|-------------------|------|
| `t0` | under 2 s | under 2 min | merge path |
| `t1` | under 30 s | under 10 min | merge path — this is what blocks a merge |
| `t2` | more, **or cross-component at any cost** | none | nightly only |

Tier follows measured cost and scope, never importance. A suite with no
resolvable subject file is cross-component and therefore `t2` however cheap it
is. `aid-test-tier-assign.sh` proposes tiers from the durations journal and
enforces the aggregate budgets; `aid-test-tier-lint.sh` fails a suite with no
tag, with two tags, with a plan number in its filename, or with a tier cheaper
than its newest measurement supports. Inside a tiered tree the RUNNER refuses to
run at all while any suite is untagged — an untagged suite under `--tier` is a
suite that silently never runs.

Placement is unchanged: `tests/test-*.sh` and `tests/bats/test-*.bats`, both
discovered by the globs below. The tier is a tag precisely so nothing moves.

### Running All Tests

```bash
# From the scripts directory
./tests/run-all-tests.sh

# From the repository root
bash plugins/aid-orchestrator/scripts/tests/run-all-tests.sh

# What the merge path actually runs
./tests/run-all-tests.sh --tier t0 && ./tests/run-all-tests.sh --tier t1

# What the nightly runs: the WHOLE portfolio (no --tier), refreshing every
# suite's measured duration. Hours, not minutes — this is not a local command.
./tests/run-all-tests.sh --timing

# With full output from each suite. NOTE: no --tier means the FULL portfolio
# (hours). For local verification use the merge-path command above.
./tests/run-all-tests.sh --verbose
```

### Test Runner Options

| Flag | Description |
|------|-------------|
| `--verbose`, `-v` | Show full output from each test suite (individual PASS/FAIL lines) |
| `--list` | Enumerate discovered suites with their tier, run nothing |
| `--tier <t0\|t1\|t2>` | Run only suites declaring that tier; skipped-by-tier counts are printed, never silent |
| `--timing` | Record one duration per suite into `.aid-o/work/test-durations.jsonl` (opt-in; without it the run is byte-identical to before) |
| `--include-delegated` | **Deprecated, accepted as a no-op.** Delegation was removed 2026-08-14 — an untiered run is already the full portfolio |
| `--help`, `-h` | Show usage information |

### Test Runner Output

**Compact mode** (default) shows one summary line per suite:

```
========================================================================
  AID Pipeline Tests
========================================================================

Discovered 6 test suite(s)

----------------------------------------------------------------------
Suite 1/6: test-epic-to-json
----------------------------------------------------------------------
  [PASS] 10/10 passed, 0 failed

----------------------------------------------------------------------
Suite 2/6: test-full-pipeline
----------------------------------------------------------------------
  [PASS] 16/16 passed, 0 failed

...

========================================================================
  Summary
========================================================================

  Suites:  6/6 passed, 0 failed
  Tests:   76/76 passed, 0 failed
  Total:   76 tests across 6 suites

RESULT: PASS
```

**Verbose mode** (`--verbose`) additionally prints every individual test line
(PASS/FAIL) from each suite.

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All suites passed |
| 1 | One or more suites failed |

### Test Suites

The suites live in `tests/` (bats under `tests/bats/`); `tests/run-all-tests.sh --tier t0|t1|t2` runs one tier.

### Test Fixtures

Test fixtures are stored in `tests/fixtures/` and include sample Plan.md and
EPIC.md files used by all test suites. Fixtures are read-only during testing
(each test creates its own temp directory for output).
