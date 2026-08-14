# AID Pipeline Scripts

Bash scripts that implement the AID Plan-to-Execution pipeline. Each script
handles one transformation step, and `aid-auto-pipeline.sh` orchestrates them
all in sequence.

```
Plan.md --> EPIC.md --> plan.json --> run.md --> queue.yaml
          (1)         (2)          (3)         (4)
                  aid-auto-pipeline.sh = readiness + 1+2 + finalizer + 3+4
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

## Data Flow Diagram

```
                       aid-auto-pipeline.sh
          +-------------------------------------------------+
          |                                                 |
          v                                                 |
   +------------+     +----------------+     +-------------+|    +---------------+
   | Plan.md    |---->| EPIC.md        |---->| plan.json   |--->| receipt       |
   | (.aid-o/   |  1  | (.aid-o/       |  2  |             ||  3 | (.aid-o/      |
   |  plans/)   |     |  tasks/)       |     |             ||    |  work/evidence/|
   +------------+     +----------------+     +-------------+|    +---------------+
                                                            |
                                                            |                 |
                                                            v                 v
                                                     run.md + FSM       queue.yaml
```

Where the numbered arrows correspond to:

1. `aid-plan-to-epic.sh` — Plan.md to EPIC.md
2. `aid-epic-to-json.sh` — EPIC.md to plan.json
3. `aid-generation-finalize.sh` — verifies all phases and writes one receipt
4. `aid-json-to-run.sh` — plan.json to run.md + FSM init (after receipt)
5. `aid-queue-add.sh` — EPIC to queue.yaml entry (after receipt)

---

## Scripts

### 1. aid-plan-to-epic.sh

**Purpose:** Convert a Plan.md file into one or more EPIC.md files, one per
phase defined in the plan.

#### Arguments

| Flag | Required | Description |
|------|----------|-------------|
| `--plan <path>` | Yes | Path to the source Plan.md file |
| `--phase <N>` | Yes | Phase number to extract (1-based index) |
| `--total <T>` | Yes | Total number of phases in the plan |
| `--epic-template <path>` | Yes | Path to the EPIC template file (.aid-o/config/templates/epic.md) |
| `--output-dir <path>` | Yes | Directory where the generated EPIC file is written |
| `--counter-yaml <path>` | Yes | Path to the EPIC counter YAML file for auto-incrementing EPIC IDs |
| `--project-root <path>` | No | Authoritative AID workspace for generation evidence when the plan itself lives outside `.aid-o/plans/` |

#### stdin / stdout Contract

- **stdin:** Not used.
- **stdout:** Absolute path to the generated EPIC file.

  ```
  /project/.aid-o/tasks/E-018-1_3.md
  ```

- **stderr:** JSON error on failure (see Exit Codes).

#### Behavior

1. Reads `--plan` and extracts frontmatter (plan ID, title, metadata).
2. Extracts the phase-specific section from the plan's `## High-Level Steps`
   table (row matching `--phase`).
3. Reads the EPIC template and fills placeholders:
   - `plan_ref` set to the plan filename
   - `plan_epics_total` set to `--total`
   - EPIC ID auto-incremented from `--counter-yaml`
   - Context, Goal, Scope, and Steps sections populated from plan content
4. Writes the completed EPIC to `--output-dir`.
5. Prints the output path to stdout.

#### Exit Codes

| Code | Condition |
|------|-----------|
| 0 | EPIC generated successfully |
| 1 | Plan is malformed (missing frontmatter, no steps table, phase out of range) |
| 2 | Missing dependency (bash/jq) |
| 3 | Plan file not found, template not found, output dir not writable |

#### Usage Example

```bash
./aid-plan-to-epic.sh \
  --plan .aid-o/plans/2026-02-28-pipeline-scripts.md \
  --phase 1 \
  --total 3 \
  --epic-template .aid-o/config/templates/epic.md \
  --output-dir .aid-o/tasks \
  --counter-yaml .aid-o/work/epic-counter.yaml
```

#### Phase Marker Format

`aid-plan-to-epic.sh` uses a bash regex to identify phase boundaries in the plan file:

```
^\*\*EPIC[[:space:]]+([0-9]+)(:[[:space:]]+Steps[[:space:]]+([0-9]+)-([0-9]+))?
```

This matches two forms:

| Form | Example | Behaviour |
|------|---------|-----------|
| With step range | `**EPIC 1: Steps 1-6 — Title**` | Phase gets steps M through P explicitly |
| Without step range | `**EPIC 1**` | Steps are assigned by document order (everything after the marker until the next marker) |

If **no markers are present at all**, the script divides steps evenly across the total number of phases (remainder steps are distributed to earlier phases).

Only lines that match the regex are treated as markers. Common mistakes that cause silent parse failure:

- Using `## Phase N` (heading syntax) instead of `**EPIC N**`
- Using `**Phase 1: Steps 1-4**` (keyword `Phase` instead of `EPIC`)
- Omitting the colon: `**EPIC 1 Steps 1-4**` instead of `**EPIC 1: Steps 1-4**`

The authoritative format reference is `skills/plan-writing.md` → **Phase Markers** section.

#### Portability Notes

- Uses `sed` for text replacement — avoids GNU-only flags (`-i` differs between
  BSD and GNU; uses temp file + mv instead).
- All awk usage is POSIX-compliant (no gawk extensions).

---

### 2. aid-epic-to-json.sh

**Purpose:** Parse an EPIC.md file and produce a `plan.json` (execution plan),
plus initialize an evidence directory for the run.

#### Arguments

| Flag | Required | Description |
|------|----------|-------------|
| `--epic <path>` | Yes | Path to the EPIC.md file |
| `--schema <path>` | Yes | Path to plan.schema.json for validation |
| `--output-dir <path>` | Yes | Directory where plan.json and evidence/ are written |
| `--plan-source <path>` | No | Path to the source Plan.md (populates `source_plan` in plan.json) |

#### stdin / stdout Contract

- **stdin:** Not used.
- **stdout:** JSON manifest describing generated artifacts:

  ```json
  {
    "plan_json": ".aid-o/work/runs/R-E018-1/plan.json",
    "run_id": "R-E018-1",
    "evidence_dir": ".aid-o/work/runs/R-E018-1/evidence"
  }
  ```

- **stderr:** JSON error on failure.

#### Behavior

1. Reads the EPIC frontmatter to extract `status`, `plan_ref`, `runs_total`.
2. Parses the `## Steps (Role Pipeline)` table into structured step objects.
3. Builds a dependency graph from the "Depends On" column.
4. Detects parallel groups from the "Parallel Group" column.
5. Auto-generates analysis groups for steps matching policy rules (e.g.,
   security review after backend steps).
6. Reads `## DoD Gates` to populate the `gates` array.
7. Constructs the plan.json object conforming to `plan.schema.json`.
8. Validates the generated JSON against the schema using `jq`.
9. Creates the evidence directory.
10. Prints the JSON manifest to stdout.

#### Exit Codes

| Code | Condition |
|------|-----------|
| 0 | plan.json generated and validated |
| 1 | EPIC is malformed (missing Steps table, invalid dependencies, cycle detected) |
| 2 | Missing dependency (bash/jq) |
| 3 | EPIC file not found, schema file not found, output dir not writable |

#### Usage Example

```bash
./aid-epic-to-json.sh \
  --epic .aid-o/tasks/E-018-1_3.md \
  --schema .aid-o/config/templates/plan.schema.json \
  --output-dir .aid-o/work/runs/R-E018-1 \
  --plan-source .aid-o/plans/2026-02-28-pipeline-scripts.md
```

#### Portability Notes

- JSON construction uses `jq` exclusively (no hand-assembled JSON strings).
- Schema validation uses `jq` to verify required fields and types — not a full
  JSON Schema validator, but sufficient for structural correctness.
- Dependency cycle detection implements Kahn's algorithm in bash/awk.

---

### 3. aid-json-to-run.sh

**Purpose:** Generate a run.md file from a plan.json, filling a run template
with frontmatter, phase sections, and dependency information.

#### Arguments

| Flag | Required | Description |
|------|----------|-------------|
| `--plan-json <path>` | Yes | Path to the plan.json file |
| `--run-template <path>` | Yes | Path to the run template (e.g., run-new-feature.md) |
| `--epic <path>` | Yes | Path to the source EPIC.md (for context and metadata) |
| `--output-dir <path>` | Yes | Directory where the run.md file is written |
| `--run-id <R-xxx>` | Yes | Run identifier (e.g., R-E018-1) |

#### stdin / stdout Contract

- **stdin:** Not used.
- **stdout:** Absolute path to the generated run file.

  ```
  /project/.aid-o/work/runs/R-E018-1/2026-02-28-new-feature-pipeline-scripts.md
  ```

- **stderr:** JSON error on failure.

#### Behavior

1. Reads `--plan-json` to extract steps, dependencies, and parallel groups.
2. Reads `--epic` to extract Goal, Context, Scope, and Acceptance Criteria.
3. Reads `--run-template` as the structural skeleton.
4. Fills run frontmatter:
   - `id` from `--run-id`
   - `run_id` as date-slugified identifier
   - `epic_id` from plan.json `epic_id`
   - `epic_file` from `--epic` path
   - `plan_ref` from plan.json
   - `orchestrated: true`
5. Generates one Phase section per plan.json step, populating:
   - Goal (from step objective)
   - Agent / Role
   - Inputs (from step inputs + dependency outputs)
   - Outputs (from step outputs)
   - Constraints (from step constraints + allowed/forbidden paths)
   - Acceptance criteria (from step acceptance_criteria)
6. Generates the Dependencies table from plan.json dependencies.
7. Writes the completed run file.
8. Prints the output path to stdout.

#### Exit Codes

| Code | Condition |
|------|-----------|
| 0 | Run file generated successfully |
| 1 | plan.json is invalid (missing steps, malformed structure) |
| 2 | Missing dependency (bash/jq) |
| 3 | Input file not found, output dir not writable |

#### Usage Example

```bash
./aid-json-to-run.sh \
  --plan-json .aid-o/work/runs/R-E018-1/plan.json \
  --run-template .aid-o/config/templates/run-new-feature.md \
  --epic .aid-o/tasks/E-018-1_3.md \
  --output-dir .aid-o/work/runs/R-E018-1 \
  --run-id R-E018-1
```

#### Portability Notes

- Template placeholder replacement uses `sed` with `|` as delimiter to avoid
  conflicts with `/` in file paths.
- Generates valid markdown tables using `printf` formatting.

---

### 4. aid-queue-add.sh

**Purpose:** Add an EPIC entry to the `queue.yaml` file for queued
execution. Validates against duplicates and runs cycle detection on the
dependency graph.

#### Arguments

| Flag | Required | Description |
|------|----------|-------------|
| `--epic-id <E-xxx>` | Yes | EPIC identifier to enqueue |
| `--epic-path <path>` | Yes | Path to the EPIC.md file |
| `--priority <level>` | No | Priority level: `critical`, `high`, `medium` (default), `low` |
| `--depends-on <list>` | No | Comma-separated list of EPIC IDs this EPIC depends on |
| `--queue-yaml <path>` | Yes | Path to the queue.yaml file |

#### stdin / stdout Contract

- **stdin:** Not used.
- **stdout:** Confirmation string:

  ```
  queued:E-018-1_3
  ```

- **stderr:** JSON error on failure.

#### Behavior

1. Validates `--epic-id` format (must match `E-` prefix pattern).
2. Reads existing `--queue-yaml` (creates if absent).
3. Checks for duplicate entries — exits with code 1 if EPIC already queued.
4. If `--depends-on` is specified, validates that all dependency EPIC IDs exist
   in the queue or are already completed.
5. Runs Kahn's algorithm for topological cycle detection on the full queue
   dependency graph (including the new entry). Exits with code 1 if a cycle
   is detected.
6. Appends the new entry to the queue YAML with atomic write (write to temp
   file, then `mv` to target — prevents partial writes on failure).
7. Prints confirmation to stdout.

#### Queue Entry Format

Each entry in `queue.yaml`:

```yaml
queue:
  - epic_id: E-018-1_3
    epic_path: .aid-o/tasks/E-018-1_3.md
    priority: medium
    status: pending         # pending | running | completed | failed (`queued` is read-only legacy input)
    depends_on: []
    added_at: 2026-02-28T14:30:00Z
```

#### Exit Codes

| Code | Condition |
|------|-----------|
| 0 | EPIC queued successfully |
| 1 | Duplicate EPIC, dependency cycle detected, invalid EPIC ID format |
| 2 | Missing dependency (bash/jq) |
| 3 | Queue file not writable, EPIC file not found |

#### Usage Example

```bash
./aid-queue-add.sh \
  --epic-id E-018-1_3 \
  --epic-path .aid-o/tasks/E-018-1_3.md \
  --priority medium \
  --depends-on E-017-1_1,E-017-2_1 \
  --queue-yaml .aid-o/config/queue.yaml
```

#### Portability Notes

- YAML generation uses `printf` and string concatenation — no external YAML
  library required.
- Atomic write via temp file + `mv` is POSIX-portable and prevents corruption.
- Kahn's algorithm is implemented in awk for performance (no subshell loops).

---

### 5. aid-auto-pipeline.sh

**Purpose:** Master orchestration script that runs the full Plan-to-Queue
pipeline. It generates EPICs and plan.json files for all phases, verifies the
complete package and writes a receipt, then creates runs and queue entries.

#### Arguments

| Flag | Required | Description |
|------|----------|-------------|
| `--plan <path>` | Yes | Path to the source Plan.md file |
| `--queue-mode <mode>` | No | How to set up queue dependencies between generated EPICs. One of: `chain` (default), `separate`, `custom` |
| `--plugin-dir <path>` | No | Path to the AID plugin directory (auto-detected if not set) |
| `--depends-on <list>` | No | Comma-separated EPIC IDs for custom dependencies (only with `--queue-mode custom`) |

**Queue Modes:**

| Mode | Behavior |
|------|----------|
| `chain` | Each EPIC depends on the previous one: E1 -> E2 -> E3. Default. |
| `separate` | All EPICs are independent — no inter-EPIC dependencies. |
| `custom` | Uses `--depends-on` to set the same dependencies on all generated EPICs. |

#### stdin / stdout Contract

- **stdin:** Not used.
- **stdout:** JSON manifest summarizing all generated artifacts:

  ```json
  {
    "plan_id": "P018",
    "plan_path": ".aid-o/plans/2026-02-28-pipeline-scripts.md",
    "epics": [
      {
        "epic_id": "E-018-1_3",
        "epic_path": ".aid-o/tasks/E-018-1_3.md",
        "plan_json": ".aid-o/work/runs/R-E018-1/plan.json",
        "run_path": ".aid-o/work/runs/R-E018-1/2026-02-28-new-feature-pipeline-scripts.md",
        "run_id": "R-E018-1",
        "queue_status": "pending"
      },
      {
        "epic_id": "E-018-2_3",
        "epic_path": ".aid-o/tasks/E-018-2_3.md",
        "plan_json": ".aid-o/work/runs/R-E018-2/plan.json",
        "run_path": ".aid-o/work/runs/R-E018-2/2026-02-28-new-feature-pipeline-scripts.md",
        "run_id": "R-E018-2",
        "queue_status": "pending"
      }
    ],
    "queue_mode": "chain",
    "duration_ms": 4200
  }
  ```

- **stderr:** JSON error on failure; progress messages prefixed with `[INFO]`.

#### Behavior

1. Validates the plan file exists and has valid frontmatter.
2. Counts total phases from the `## High-Level Steps` table.
3. Locates the AID plugin directory (templates, schemas) from `--plugin-dir`
   or by walking up from the script location.
4. For each phase (1..N), generates EPIC.md and plan.json and performs the
   per-EPIC contract check. It does not initialise FSM or mutate the queue.
   a. Calls `aid-plan-to-epic.sh` to generate the EPIC.
   b. Calls `aid-epic-to-json.sh` to generate plan.json + progress.
5. Calls `aid-generation-finalize.sh`; missing/duplicate/tampered phases or a
   graph disagreement abort before any FSM init or queue mutation.
6. Creates runs, initialises FSM and queues EPICs using the verified receipt.
7. Constructs dependency chains according to `--queue-mode`.
8. Measures total wall-clock time and prints the JSON manifest to stdout.

#### Exit Codes

| Code | Condition |
|------|-----------|
| 0 | All phases processed and queued successfully |
| 1 | Plan is malformed, or a sub-script returned validation error |
| 2 | Missing dependency (bash/jq) |
| 3 | Plan file not found, plugin directory not found |

#### Usage Example

```bash
# Default chain mode — each EPIC depends on the previous
./aid-auto-pipeline.sh \
  --plan .aid-o/plans/2026-02-28-pipeline-scripts.md

# All EPICs independent (can run in parallel)
./aid-auto-pipeline.sh \
  --plan .aid-o/plans/2026-02-28-pipeline-scripts.md \
  --queue-mode separate

# Custom dependencies
./aid-auto-pipeline.sh \
  --plan .aid-o/plans/2026-02-28-pipeline-scripts.md \
  --queue-mode custom \
  --depends-on E-017-1_1

# Explicit plugin directory
./aid-auto-pipeline.sh \
  --plan .aid-o/plans/2026-02-28-pipeline-scripts.md \
  --plugin-dir plugins/aid-orchestrator
```

#### Portability Notes

- Measures duration using bash `SECONDS` variable (available since bash 2.0)
  and converts to milliseconds via `$(( SECONDS * 1000 ))`.
- Sub-script invocation uses `"$(dirname "$0")/aid-plan-to-epic.sh"` for
  reliable relative path resolution.
- Progress messages go to stderr (`[INFO]` prefix) to keep stdout clean for
  the JSON manifest.

---

## Shared Library: lib/common.sh

All pipeline scripts source `lib/common.sh` at startup. This file provides 7 shared
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

Every pipeline script begins with:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
check_prerequisites
```

---

## JSON Manifest Schema

The `aid-auto-pipeline.sh` stdout produces a JSON manifest. Its schema:

```json
{
  "type": "object",
  "required": ["plan_id", "plan_path", "epics", "queue_mode", "duration_ms"],
  "properties": {
    "plan_id": {
      "type": "string",
      "description": "Plan identifier extracted from the plan frontmatter",
      "examples": ["P018"]
    },
    "plan_path": {
      "type": "string",
      "description": "Path to the source Plan.md file"
    },
    "epics": {
      "type": "array",
      "description": "One entry per generated EPIC (one per plan phase)",
      "items": {
        "type": "object",
        "required": ["epic_id", "epic_path", "plan_json", "run_path", "run_id", "queue_status"],
        "properties": {
          "epic_id": {
            "type": "string",
            "description": "Generated EPIC identifier",
            "examples": ["E-018-1_3"]
          },
          "epic_path": {
            "type": "string",
            "description": "Path to the generated EPIC.md file"
          },
          "plan_json": {
            "type": "string",
            "description": "Path to the generated plan.json"
          },
          "run_path": {
            "type": "string",
            "description": "Path to the generated run.md file"
          },
          "run_id": {
            "type": "string",
            "description": "Run identifier",
            "examples": ["R-E018-1"]
          },
          "queue_status": {
            "type": "string",
            "enum": ["queued", "failed"],
            "description": "Whether the EPIC was successfully queued"
          }
        }
      }
    },
    "queue_mode": {
      "type": "string",
      "enum": ["chain", "separate", "custom"],
      "description": "Queue dependency mode used"
    },
    "duration_ms": {
      "type": "integer",
      "description": "Total wall-clock time in milliseconds"
    }
  }
}
```

---

## Directory Structure

After running the full pipeline, the workspace looks like:

```
.aid-o/
  plans/
    2026-02-28-pipeline-scripts.md          # Source plan (input)
  tasks/
    E-018-1_3.md                            # Generated EPIC (phase 1)
    E-018-2_3.md                            # Generated EPIC (phase 2)
    E-018-3_3.md                            # Generated EPIC (phase 3)
  config/
    templates/
      epic.md                               # EPIC template (input)
      plan.schema.json                      # JSON schema (input)
      run-new-feature.md                    # Run template (input)
    queue.yaml                              # Execution queue
  work/
    epic-counter.yaml                       # Auto-increment counter
    runs/
      R-E018-1/
        plan.json                           # Execution plan
        fsm-state.yaml                      # FSM state
        2026-02-28-new-feature-*.md         # Run file
        evidence/                           # Evidence directory
      R-E018-2/
        ...
      R-E018-3/
        ...
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

| Suite | Script Under Test | Tests | Focus |
|-------|-------------------|-------|-------|
| `test-plan-to-epic.sh` | `aid-plan-to-epic.sh` | 20 | Phase extraction, section content, error handling |
| `test-epic-to-json.sh` | `aid-epic-to-json.sh` | 10 | JSON generation, step parsing, cycle detection |
| `test-json-to-run.sh` | `aid-json-to-run.sh` | 10 | Run file generation, phase sections, error handling |
| `test-queue-add.sh` | `aid-queue-add.sh` | 10 | Queue operations, duplicate detection, dependencies |
| `test-full-pipeline.sh` | `aid-auto-pipeline.sh` | 16 | End-to-end pipeline integration |
| `test-regression.sh` | `aid-auto-pipeline.sh` | 10 | Structural equivalence of pipeline output |

### Test Fixtures

Test fixtures are stored in `tests/fixtures/` and include sample Plan.md and
EPIC.md files used by all test suites. Fixtures are read-only during testing
(each test creates its own temp directory for output).
