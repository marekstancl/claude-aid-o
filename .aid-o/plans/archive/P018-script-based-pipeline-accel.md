---
id: P018
type: plan
status: done
created: 2026-02-28
author: PM + AI
---

# Plan: Script-Based Pipeline Acceleration

## Context

The `/aid-plan-epic` pipeline currently uses LLM for all operations — including deterministic tasks like parsing plan.md sections, filling EPIC templates, generating plan.json from structured data, and creating run.md files. For a plan with 3 phases, this takes 15+ minutes: EPIC generation (15-30s × 3), plan.json creation (5-10s × 3), and run.md generation (10-20s × 3). Every operation involves LLM inference even though the inputs are structured (plan.md follows a strict template enforced by plan-writing skill) and the outputs are templated (EPIC template, plan.schema.json, run-*.md).

P018 INTERIM brainstorming identified a key pivot: replace LLM with bash/jq scripts for all deterministic operations. LLM retains orchestration (PM dialog, error reporting, FIRST AID offer) and validation (output verification). The pipeline shrinks from 15+ minutes to ~5 seconds for 3 EPICs.

This is a high-impact change affecting 21 files across commands, skills, agents, and templates. The EPIC must be developed on a feature branch with full test pass before merge to main.

**Predecessor:** P018 INTERIM brainstorming (8 steps completed, all sections approved)

## Goal

Replace all deterministic operations in the `/aid-plan-epic` pipeline with bash scripts, reducing pipeline execution time from 15+ minutes to ~5 seconds for a typical 3-phase plan while maintaining full backward compatibility with plan.json schema, epic-queue.yaml format, and all downstream consumers (Controller, agents, gates).

## Scope

**In scope:**
- 5 bash scripts in `plugins/aid-orchestrator/scripts/` implementing the full Plan→EPIC→json→run→queue pipeline
- Rewrite of `commands/aid-plan-epic.md` from 530-line LLM-driven flow to ~150-line script-orchestrated flow
- New mandatory Dependencies section in EPIC template (`defaults/templates/epic.md`)
- Auto-queue integration with 3 PM-selectable modes (chain, separate, custom)
- Removal of embedded plan generation from `commands/aid-run-epic.md`
- New "Deterministic Work Detection" audit type in `agents/auditor.md`
- Documentation consistency pass across 21 affected files (Tier 1-4)
- Fixture, integration, and regression tests for all scripts
- FIRST AID discoverability fix (offered in aid-plan-epic Step 6 output)

**Out of scope:**
- Fast mode (direct development without orchestration) — backlog
- Solo EPIC flow (ad-hoc EPIC without plan) — backlog, linked to fast mode
- History cleanup (archive pruning of early EPICs/runs) — backlog
- Additional script candidates beyond `/aid-plan-epic` pipeline — discovered via new auditor check
- GUI changes (Pipeline Theater, dashboard) — separate plan (P016)
- Multi-queue system (`--queue <name>` for parallel FIRST AID sessions) — separate plan
- Runtime dispatch optimizations — P017 scope

**Dependencies:**
- None — P018 is self-contained. Scripts use only bash 4.0+, jq, sed, awk, date.

## Approach

### Option A: Script-First Pipeline (Chosen)

One orchestration bash script (`aid-auto-pipeline.sh`) calls 3 conversion scripts (plan→epic, epic→json, json→run) plus queue add. LLM only: (1) asks PM queue mode, (2) runs script, (3) validates output, (4) reports to PM. `aid-plan-epic.md` reduces from 530 to ~150 lines.

**Pros:**
- 15+ min → ~5s for entire pipeline
- Deterministic, reproducible outputs
- Simpler aid-plan-epic.md (fewer LLM instructions = fewer errors)
- Scripts testable outside LLM (dry run, CI)

**Cons:**
- New code to maintain (bash/jq)
- Edge cases in plan.md parsing (non-standard formatting)

### Option B: Template-Instruction Reduction (Rejected)

No scripts — simplify LLM instructions with "copy, don't rewrite" rules. Rejected because LLM latency remains (45-90s per EPIC), outputs are non-deterministic, and the fundamental problem (LLM doing copy-paste work) is unresolved.

### Option C: Hybrid — Script for json+run, LLM for EPIC (Rejected)

Script covers only EPIC→json and json→run. Rejected because the slowest step (Plan→EPIC × N at 15-30s each) stays on LLM. Half-measure that doesn't resolve the main bottleneck.

**Decision:** Option A — scripts for all deterministic operations, LLM for orchestration and validation only.

## Architecture

### Pipeline Overview

```
PM: /aid-plan-epic .aid-o/01-plans/P018-pipeline-accel.md

LLM Step 1: Validate input (is Plan.md? exists?)
LLM Step 2: Parse plan → count phases, display summary
LLM Step 3: Ask PM queue mode (chain/separate/custom)
LLM Step 4: Run script:
  bash plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh \
    --plan <path> --queue-mode <mode> --plugin-dir <path>

Script (2-5s):
  aid-plan-to-epic.sh × N  → .aid-o/02-epics/E-018-{1..N}_N-*.md
  aid-epic-to-json.sh × N  → .aid-o/04-engine/evidence/E-018-*/plan.json
  aid-json-to-run.sh  × N  → .aid-o/04-engine/runs/R-018-*-*.md
  aid-queue-add.sh × N     → epic-queue.yaml updated

LLM Step 5: Validate output (files exist, schema valid)
LLM Step 6: Report to PM + offer FIRST AID
```

### Components

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| `aid-auto-pipeline.sh` | Orchestration script | `scripts/` | Calls conversion scripts, returns JSON manifest |
| `aid-plan-to-epic.sh` | Conversion script | `scripts/` | Plan.md → EPIC.md (template fill) |
| `aid-epic-to-json.sh` | Conversion script | `scripts/` | EPIC.md → plan.json + plan_progress.json |
| `aid-json-to-run.sh` | Generation script | `scripts/` | plan.json → run.md (template fill) |
| `aid-queue-add.sh` | Queue script | `scripts/` | Adds EPIC entry to epic-queue.yaml |
| `aid-plan-epic.md` | Command (rewrite) | `commands/` | LLM orchestration: PM dialog, script call, reporting |

### Data Flow

```
Plan.md ─────────────────────────────────────┐
EPIC template (defaults/templates/epic.md) ──┤
plan.schema.json ────────────────────────────┤
run template (defaults/templates/run-*.md) ──┤── aid-auto-pipeline.sh
epic-queue.yaml (current state) ─────────────┤
counter.yaml ────────────────────────────────┘
                                              │
                                              ▼
                          N × EPIC.md, plan.json, run.md
                          + updated epic-queue.yaml
                          + updated counter.yaml
                          + JSON manifest on stdout
```

### JSON Manifest (stdout from aid-auto-pipeline.sh)

```json
{
  "plan_id": "P018",
  "epics": [
    {
      "id": "E-018-1_3",
      "path": ".aid-o/02-epics/E-018-1_3-pipeline-accel.md",
      "plan_json": ".aid-o/04-engine/evidence/E-018-1_3/R-018-1_3-1/plan.json",
      "run": ".aid-o/04-engine/runs/R-018-1_3-1-pipeline-accel.md",
      "queue_status": "queued",
      "depends_on": []
    }
  ],
  "duration_ms": 4200
}
```

### Queue Integration

Two entry paths into queue — both must work:

| Path | Who | How |
|------|-----|-----|
| Auto (script) | `/aid-plan-epic` → `aid-auto-pipeline.sh` → `aid-queue-add.sh` | Script adds N EPICs, `depends_on` from EPIC Dependencies section |
| Manual | PM → `/aid-epic-queue add <path>` | Unchanged — PM manually adds EPIC with optional `--depends-on` |

Queue modes from `/aid-plan-epic` Step 3:

| Mode | Behavior |
|------|----------|
| `chain` (default) | E-018-1→2→3, sequential depends_on chain |
| `separate` | Each EPIC independent, no depends_on |
| `custom` | LLM asks PM for specifics (cross-plan deps, partial chains) |

No changes to: `epic-queue.yaml` format, `epic-queue.md` skill, `aid-epic-queue.md` command, queue safety guards.

## Implementation Steps

**EPIC 1: Steps 1-6 — Scripts**

### Step 1: Design Script Interfaces and Contracts

**Objective:** Define the input/output contracts, error codes, and JSON manifest schema for all 5 scripts before implementation begins.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/README.md` — script documentation with interface contracts, usage examples, dependency requirements
- Create: `plugins/aid-orchestrator/scripts/lib/common.sh` — shared functions (YAML parsing, error formatting, prerequisite checks)

**Architecture Context:**
All 5 scripts share common operations: YAML frontmatter parsing, error output formatting, prerequisite validation (bash version, jq availability), and path resolution. The `lib/common.sh` library centralizes these to avoid duplication. Each script sources this library as its first action. The README documents contracts that `aid-plan-epic.md` relies on for Step 4-5 (script invocation and output validation).

**Implementation Detail:**
`lib/common.sh` functions:
- `parse_frontmatter(file)` — extracts YAML between `---` markers using `sed -n '/^---$/,/^---$/p'`, returns key=value pairs. Handles multi-line values by joining continuation lines.
- `extract_section(file, header)` — extracts content between two H2 (`##`) headers using `awk '/^## {header}/,/^## [^#]/'`. Returns section body without the header line.
- `extract_subsection(file, h2, h3)` — same logic for H3 within H2 boundary.
- `slugify(text)` — lowercase, replace spaces/special chars with hyphens, truncate to 40 chars: `echo "$text" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40`
- `check_prerequisites()` — verify bash 4.0+, jq available, required paths exist. Exit 1 with human-readable error if any check fails.
- `error_exit(msg, code)` — print JSON error to stderr: `{"error": "$msg", "code": $code}`, exit with code.
- `iso_timestamp()` — `date -u +%Y-%m-%dT%H:%M:%SZ`

README.md documents for each script: name, purpose, arguments (--flag descriptions), stdin/stdout contract, exit codes (0=success, 1=validation error, 2=missing dependency, 3=file I/O error), examples.

**Error Handling:**
- If `jq` is not available: `check_prerequisites` prints install instructions for macOS (`brew install jq`) and Linux (`apt install jq`), exits with code 2.
- If bash version < 4.0: prints version requirement, exits with code 2. Detected via `${BASH_VERSINFO[0]}`.

**Edge Cases:**
- Plan.md frontmatter with Windows line endings (CRLF) — `parse_frontmatter` strips `\r` before processing.
- Plan.md with empty sections (H2 header followed immediately by another H2) — `extract_section` returns empty string, caller decides if this is an error.
- Multiple `---` markers in plan body (e.g., in code blocks) — `parse_frontmatter` only reads between the FIRST two `---` lines.

**Dependencies:**
- No dependencies — this is the first step.
- Blocks: Steps 2, 3, 4, 5 (all scripts source lib/common.sh)

**Acceptance Criteria:**
- [ ] `lib/common.sh` contains all 7 functions listed above with correct behavior
- [ ] `README.md` documents all 5 scripts with full interface contracts
- [ ] `check_prerequisites()` correctly detects missing jq and bash <4.0
- [ ] `parse_frontmatter` correctly extracts YAML from plan.md with CRLF line endings

**Effort:** M
**AID Role:** architect

---

### Step 2: Implement aid-plan-to-epic.sh

**Objective:** Create the script that converts a Plan.md file into N EPIC.md files by extracting plan sections and filling the EPIC template.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` — main conversion script (~150-200 lines)
- Modify: `plugins/aid-orchestrator/defaults/templates/epic.md` (lines ~77-81) — add structured Dependencies section with Internal/External/Queue subsections

**Architecture Context:**
This script is the first stage in the pipeline. It reads a plan.md (whose format is enforced by the plan-writing skill), counts phases from the Implementation Steps section, then for each phase extracts relevant steps and fills the EPIC template. The filled EPIC becomes input for `aid-epic-to-json.sh`. The new Dependencies section in the EPIC template enables automatic `depends_on` population in the queue.

**Implementation Detail:**
Script arguments: `--plan <path> --phase <N> --total <T> --epic-template <path> --output-dir <path> --counter-yaml <path>`

Algorithm:
1. Source `lib/common.sh`
2. Parse plan.md frontmatter → extract `id` field (e.g., `P018`). Extract plan number: `plan_num=$(echo "$plan_id" | sed 's/^P//')`
3. Generate EPIC ID: `E-${plan_num}-${phase}_${total}` (e.g., `E-018-1_3`)
4. Generate topic slug from plan H1 title: `title=$(grep '^# Plan:' "$plan" | sed 's/^# Plan: //')` then `slug=$(slugify "$title")`
5. Extract Implementation Steps section: `extract_section "$plan" "Implementation Steps"`
6. Parse step headers: `grep '^### Step' "$steps_content"` — each `### Step N:` line with its content
7. Filter steps for this phase: Steps are grouped by EPIC phase markers in the plan. Detect phase boundaries by looking for `**EPIC {N}**` or `**Phase {N}**` markers in the plan. If no explicit markers: divide steps evenly across phases.
8. For each phase-step, extract: Objective (first bold line after header), Files (bullet list after `**Files:**`), AID Role (line starting with `**AID Role:**`), Acceptance Criteria (checkbox list after `**Acceptance Criteria:**`)
9. Build EPIC sections:
   - Context: `extract_section "$plan" "Context"` + append `"\n\nThis EPIC covers Phase ${phase} of ${total} from plan ${plan_id}."`
   - Goal: `extract_section "$plan" "Goal"` scoped to phase steps
   - Scope Allowed: aggregate all `Create:` and `Modify:` paths from phase steps' Files sections. Extract directories: `dirname "$path" | sort -u`
   - Scope Forbidden: `extract_section "$plan" "Scope"` → extract "Out of scope" bullets, convert to forbidden paths
   - Constraints: `extract_section "$plan" "Constraints"`
   - DoD Gates: default `tests_pass`, `lint_pass`, `security_scan_pass`, `docs_updated` — or parse from plan if specified
   - AC: aggregate per-step acceptance criteria, prefix with `[role]` from step's AID Role
   - Steps table: build pipe-delimited table from phase steps: `| # | Role | Objective | Depends On | Parallel Group |`
   - Artifacts: extract from step outputs, prefix with type (endpoint:, model:, component:, config:, doc:)
10. Dependencies section (NEW):
    - Internal: if `phase > 1` → `E-${plan_num}-$((phase-1))_${total}` with reason "Previous phase must complete first"
    - External: parse plan `## Dependencies` section for cross-plan references matching `P\d{3}` or `E-\d{3}` patterns
    - Queue Implications: `depends_on: ["{internal_dep_id}", "{external_dep_id}"]` (list all resolved dependency IDs)
11. Fill EPIC template using sed: read template, replace `{{EPIC_ID}}`, `{{TITLE}}`, `{{CONTEXT}}`, `{{GOAL}}`, `{{SCOPE_ALLOWED}}`, `{{SCOPE_FORBIDDEN}}`, `{{ARTIFACTS}}`, `{{CONSTRAINTS}}`, `{{DOD_GATES}}`, `{{AC}}`, `{{DEPENDENCIES}}`, `{{STEPS_TABLE}}`, `{{PLAN_REF}}`, `{{PLAN_EPICS_TOTAL}}`
12. Write to `${output_dir}/${epic_id}-${slug}.md`
13. Increment epic counter in counter.yaml (only for ad-hoc — plan-linked EPICs derive ID from plan)
14. Echo file path to stdout

EPIC template modification — add after the existing `## Dependencies` placeholder (line ~77):
```markdown
## Dependencies

### Internal (same plan)
<!-- Auto-generated: previous phases from this plan -->
{{INTERNAL_DEPS}}

### External (other plans/EPICs)
<!-- From plan Dependencies section — cross-plan deps -->
{{EXTERNAL_DEPS}}

### Queue Implications
<!-- Auto-generated: aggregation for aid-queue-add.sh -->
depends_on: {{DEPENDS_ON_LIST}}
```

**Error Handling:**
- Plan.md missing frontmatter `id` field: exit 1 with `"Plan file missing 'id' field in frontmatter. Expected: id: P{NNN}"`
- Plan.md missing Implementation Steps section: exit 1 with `"Plan file missing '## Implementation Steps' section"`
- Phase number out of range (phase > total or phase < 1): exit 1 with `"Phase ${phase} out of range (1-${total})"`
- EPIC template file not found: exit 2 with path and suggestion to run `/aid-init`

**Edge Cases:**
- Plan with single phase (total=1): EPIC ID becomes `E-{NNN}-1_1`, no internal dependencies, Dependencies section has only External (if any) or is empty (`depends_on: []`)
- Plan steps without explicit phase markers: divide steps evenly. If 7 steps and 3 phases → phases of 3, 2, 2 steps.
- Plan with empty Dependencies section: External deps empty, only Internal deps (if multi-phase)
- Step Objective containing pipe characters `|` (breaks table): escape pipes in Objective when building Steps table

**Dependencies:**
- Depends on: Step 1 — sources `lib/common.sh` for parsing functions
- Blocks: Step 6 (orchestrator calls this script), Step 3 (epic-to-json reads generated EPIC)

**Acceptance Criteria:**
- [ ] Given a multi-phase plan.md, produces N EPIC.md files with correct IDs (E-{plan}-{phase}_{total})
- [ ] Each generated EPIC contains all required sections: Context, Goal, Scope, Artifacts, Constraints, DoD Gates, AC, Dependencies, Steps
- [ ] Dependencies section correctly populates Internal (previous phase) and Queue Implications (depends_on list)
- [ ] EPIC template in `defaults/templates/epic.md` has the new Dependencies structure

**Effort:** L
**AID Role:** backend

---

### Step 3: Implement aid-epic-to-json.sh

**Objective:** Create the script that converts an EPIC.md file into a validated plan.json, plan_progress.json, and evidence directory structure.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh` — EPIC to JSON conversion (~200-300 lines)

**Architecture Context:**
This script replaces the core of `/aid-plan-epic` Steps 3-7 — the most complex part of the pipeline. It implements the algorithm currently documented in `skills/planner.md`: dependency graph construction, parallel group detection via topological sort, and analysis group auto-triggers. The output plan.json must conform 100% to `defaults/templates/plan.schema.json` because the Controller, all agents, and FIRST AID read it during execution.

**Implementation Detail:**
Script arguments: `--epic <path> --schema <path> --output-dir <path> --plan-source <path-to-plan.md>`

Algorithm:
1. Source `lib/common.sh`
2. Parse EPIC frontmatter: `epic_id` (from filename regex `E-\d{3,}-\d+_\d+`), `plan_ref`, `plan_epics_total`
3. Parse Steps table: `awk` to find `| # | Role | Objective | Depends On | Parallel Group |` header, then read subsequent `|`-delimited rows. For each row, extract fields by splitting on `|` and trimming whitespace.
4. Generate step IDs: `step_${N}_${role}` where N is the step number and role is lowercase
5. Build dependencies array:
   - Parse "Depends On" column per step. Value is either `—` (none), a role name (find step with that role), or `step_N_role` (direct reference)
   - For each dependency: `{"before": "${dep_step_id}", "after": "${step_id}", "reason": "Declared in EPIC steps table"}`
6. Build parallel_groups array:
   - Parse "Parallel Group" column. Value is either `—` (none) or a group name like `group-1`
   - Collect all step_ids with same group name into an array: `["step_3_backend", "step_4_frontend"]`
   - Only include groups with 2+ members
7. Build analysis_groups array (auto-trigger rules from `skills/planner.md`):
   - For each step, check objective text against patterns:
     - `auth|token|encrypt|sql|inject|secret|password|credential` → add security review (mode: review, merge: union)
     - `migrat|schema|database|model` → add backend+security validation (mode: validation, merge: consensus)
     - Step has 5+ outputs (count items in Artifacts matching this step's files) → add architect review (mode: review, merge: weighted)
     - Step role is architect AND outputs contain "contract|ADR|OpenAPI" → add backend+frontend validation (mode: validation, merge: union)
   - Generate IDs: `analysis_${N}_${purpose}` where N is sequential
   - Validate: agent role != target step role (no self-review)
8. Extract per-step data from EPIC:
   - `allowed_paths`: from Scope → Allowed files/paths
   - `forbidden_paths`: from Scope → Forbidden zones
   - `constraints`: from Constraints section bullets
   - `acceptance_criteria`: from AC section, filtered by `[role]` prefix matching step role
   - `inputs`: EPIC spec + outputs from dependency steps
   - `outputs`: from Artifacts section matching step's role
9. Build gates array from DoD Gates section
10. Budget: `{"max_llm_cost_usd": 50, "max_retries_per_gate": 3}` (default, or parse from EPIC Constraints if specified)
11. Assemble full JSON object using `jq -n` with all variables:
    ```bash
    jq -n \
      --arg epic_id "$epic_id" \
      --arg source_plan "$plan_source" \
      --argjson steps "$steps_json" \
      --argjson deps "$deps_json" \
      --argjson parallel "$parallel_json" \
      --argjson analysis "$analysis_json" \
      --argjson gates "$gates_json" \
      --argjson budget "$budget_json" \
      '{epic_id: $epic_id, source_plan: $source_plan, version: 1, created_at: now|todate, steps: $steps, dependencies: $deps, parallel_groups: $parallel, analysis_groups: $analysis, gates: $gates, budget: $budget}'
    ```
12. Validate against schema: `jq --argjson schema "$(cat "$schema")" 'empty' <<< "$plan_json"` — if schema validation fails, collect specific field errors
13. Generate run_id: `R-${epic_id}-1`
14. Create evidence directory: `mkdir -p "${output_dir}/04-engine/evidence/${epic_id}/${run_id}"`
15. Save plan.json to evidence directory
16. Generate plan_progress.json: iterate steps, set all to `{"status": "pending", "review_cycles": 0, "last_review": null}`
17. Copy EPIC to evidence as `epic_input.md`
18. Output JSON to stdout: `{"plan_json": "<path>", "progress": "<path>", "run_id": "<run_id>", "evidence_dir": "<path>"}`

**Error Handling:**
- EPIC missing Steps table: exit 1 with `"EPIC file missing Steps (Role Pipeline) table"`
- Steps table has invalid role (not in enum: architect, domain, backend, frontend, qa, security, observability, docs, release): exit 1 listing invalid role and valid options
- Circular dependency detected during parallel group building: exit 1 with cycle path (e.g., `"Circular dependency: step_2_backend → step_3_frontend → step_2_backend"`)
- plan.json fails schema validation: exit 1 with specific field error from jq validation

**Edge Cases:**
- EPIC with no parallel groups (all sequential): `parallel_groups: []` — valid per schema
- EPIC with no analysis group triggers (no security/migration/complex steps): `analysis_groups: []` — valid per schema
- Step with "Depends On" referencing a role name instead of step ID: resolve by finding the step with that role. If multiple steps have same role, take the one with highest step number (latest in sequence).
- EPIC with legacy ID format (`E-YYYYMMDD-XXXX`): extract using broader regex, emit warning to stderr but continue

**Dependencies:**
- Depends on: Step 1 (lib/common.sh), Step 2 (generates EPIC files that this script reads)
- Blocks: Step 4 (json-to-run reads plan.json), Step 6 (orchestrator calls this script)

**Acceptance Criteria:**
- [ ] Generated plan.json validates against plan.schema.json with zero errors
- [ ] Dependencies array correctly represents all "Depends On" relationships from EPIC Steps table
- [ ] Parallel groups correctly group steps sharing the same "Parallel Group" value
- [ ] Analysis groups auto-trigger for steps with security/migration/complexity signals

**Effort:** L
**AID Role:** backend

---

### Step 4: Implement aid-json-to-run.sh

**Objective:** Create the script that generates a run.md file from plan.json and the run template.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-json-to-run.sh` — JSON to run.md conversion (~150-200 lines)

**Architecture Context:**
This script replaces `/aid-plan-epic` Step 8 (Run Creation Protocol). It reads plan.json (produced by aid-epic-to-json.sh), reads the EPIC file for context, and fills the run template. The run file is the human-readable operational document that agents and PM use to understand what each phase accomplishes. Each phase in the run file maps to a step in plan.json.

**Implementation Detail:**
Script arguments: `--plan-json <path> --run-template <path> --epic <path> --output-dir <path> --run-id <R-xxx>`

Algorithm:
1. Source `lib/common.sh`
2. Read plan.json via jq: extract `epic_id`, `source_plan`, steps array, dependencies, gates, budget
3. Read EPIC file: extract Goal (for Objective), Context, Scope sections
4. Read run template (`defaults/templates/run-new-feature.md`)
5. Build frontmatter:
   ```yaml
   id: {run_id}
   type: new-feature
   status: active
   priority: medium
   started: {YYYY-MM-DD}
   epic_id: {epic_id}
   epic_run: 1
   plan_ref: {path to plan.json}
   source_plan: {from plan.json source_plan field}
   orchestrated: true
   ```
6. Build Objective: 3-5 sentences from EPIC Goal + Scope IN items. Constructed by concatenating Goal section with first 3 IN-scope items as "Key deliverables: ..."
7. Build Context: "Generated from EPIC {epic_id}, plan {plan_id}. {step_count} phases planned."
8. Build Scope: IN list from EPIC Scope Allowed (min 3 items), OUT list from EPIC Scope Forbidden (min 2 items)
9. For EACH step in plan.json (using `jq -c '.steps[]'`), build a Phase section:
   - Phase number and name: `## Phase {N}: {step.objective | head -1 | truncate 60}`
   - Goal: step.objective (full text)
   - Agent/Role: step.role
   - Inputs: step.inputs formatted as bullet list with file paths
   - Outputs: step.outputs formatted as bullet list
   - Constraints: step.constraints + `Allowed paths: {step.allowed_paths}` + `Forbidden paths: {step.forbidden_paths}`
   - Check analysis_groups: if this step is target of any analysis group, append: `Post-phase review: {agent roles} will perform {mode} analysis (merge strategy: {merge_strategy})`
   - Acceptance: step.acceptance_criteria as checkbox list `- [ ] {criterion}`
10. Build Dependencies table from plan.json dependencies: `| Phase X | Phase Y | {reason} |`
11. Build Quality Gates from plan.json gates array
12. Init Run Log: `| {date} | Run created from EPIC {epic_id}, {step_count} phases planned |`
13. Assemble full run.md by concatenating all sections
14. Write to `${output_dir}/${run_id}-${slug}.md`
15. Echo file path to stdout

**Error Handling:**
- plan.json does not exist or is not valid JSON: exit 1 with `"plan.json not found or invalid JSON at: ${path}"`
- Run template not found: exit 2 with `"Run template not found at: ${path}. Run /aid-init to deploy templates."`
- Zero steps in plan.json: exit 1 with `"plan.json contains no steps"`

**Edge Cases:**
- Step with empty constraints array: Constraints section shows only allowed/forbidden paths
- Step with empty acceptance_criteria: Acceptance section shows single item: `- [ ] Step objective completed: {objective}`
- Single-step plan: Dependencies table shows "No inter-phase dependencies"
- Step objective longer than 60 characters for Phase header: truncate with `...`

**Dependencies:**
- Depends on: Step 1 (lib/common.sh), Step 3 (generates plan.json that this script reads)
- Blocks: Step 6 (orchestrator calls this script)

**Acceptance Criteria:**
- [ ] Generated run.md contains correct frontmatter with all required fields (id, type, status, epic_id, plan_ref, source_plan, orchestrated)
- [ ] Every step in plan.json maps to a Phase section with all 6 subsections (Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance)
- [ ] Dependencies table correctly lists all inter-phase dependencies from plan.json

**Effort:** M
**AID Role:** backend

---

### Step 5: Implement aid-queue-add.sh

**Objective:** Create the script that adds an EPIC entry to epic-queue.yaml with conflict detection and dependency validation.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-queue-add.sh` — queue add operation (~80-120 lines)

**Architecture Context:**
This script implements the `add()` operation from `skills/epic-queue.md` in bash. It must be 100% compatible with the existing queue format so that manual `/aid-epic-queue add` and script-generated entries coexist in the same YAML file. The script includes conflict detection (last_modified check), duplicate prevention, and Kahn's algorithm for cycle detection.

**Implementation Detail:**
Script arguments: `--epic-id <E-xxx> --epic-path <path> --priority <medium> --depends-on <E-xxx,E-yyy> --queue-yaml <path>`

Algorithm:
1. Source `lib/common.sh`
2. Read epic-queue.yaml. If file doesn't exist: create with `paused: false`, empty queue, current timestamp as last_modified.
3. Extract `last_modified` from file for conflict detection
4. Check duplicate: search queue entries for matching `epic_id` with status `queued` or `running`. If found: exit 1 with `"EPIC ${epic_id} already in queue (status: ${status})"`
5. If `depends_on` is non-empty, run dependency validation:
   a. Self-dependency check: if epic_id in depends_on list → exit 1
   b. Reference check: for each dep_id in depends_on, search queue entries. If dep_id not found anywhere (including completed) → exit 1 with suggestion to add it first
   c. Failed dependency warning: if dep_id status is "failed" → emit warning to stderr but continue (EPIC will be BLOCKED until resolved)
   d. Cycle detection — Kahn's algorithm in bash/jq:
      - Build adjacency list from ALL queue entries (not removed) + new entry
      - Compute in-degrees per node
      - Process nodes with in_degree=0 first (BFS)
      - If processed_count < total_nodes → cycle detected. Identify cycle members (nodes with remaining in_degree > 0)
      - Exit 1 with cycle path if detected
6. Append new entry to queue array:
   ```yaml
   - epic_id: "{epic_id}"
     path: "{epic_path}"
     priority: {priority}
     status: queued
     depends_on: [{depends_on list}]
     added_at: "{iso_timestamp}"
     started_at: null
     completed_at: null
   ```
7. Update `last_modified` to current timestamp
8. Write epic-queue.yaml (using a temp file + mv for atomic write)
9. Echo `"queued:${epic_id}"` to stdout

YAML manipulation via jq: convert YAML to JSON using a minimal bash YAML parser (queue format is simple enough — no nested objects beyond the entry level), manipulate in jq, convert back. Alternative: use `yq` if available, fallback to sed-based manipulation.

**Error Handling:**
- epic-queue.yaml locked or not writable: exit 3 with `"Cannot write to queue file: ${path}"`
- Conflict detection: if `last_modified` changed between read and write → exit 1 with `"Conflict detected: queue modified since last read. Re-read and retry."`
- Invalid priority value (not critical/high/medium/low): exit 1 with valid options

**Edge Cases:**
- First-ever queue add (file doesn't exist): create new file with correct structure
- Queue with all entries having status `removed` or `completed`: still works, new entry appends normally
- Empty depends_on string: treated as `depends_on: []` (no dependencies)
- EPIC path with spaces: properly quoted in YAML output

**Dependencies:**
- Depends on: Step 1 (lib/common.sh)
- Blocks: Step 6 (orchestrator calls this script)

**Acceptance Criteria:**
- [ ] Adds entry to epic-queue.yaml in correct format compatible with existing `epic-queue.md` operations
- [ ] Rejects duplicate EPIC IDs (same epic_id with status queued or running)
- [ ] Detects circular dependencies via Kahn's algorithm and rejects with descriptive error
- [ ] Atomic write (temp file + mv) prevents partial writes on error

**Effort:** M
**AID Role:** backend

---

### Step 6: Implement aid-auto-pipeline.sh

**Objective:** Create the master orchestration script that runs the full Plan→EPIC→json→run→queue pipeline for all phases.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` — orchestration script (~80-120 lines)

**Architecture Context:**
This is the single entry point called by `aid-plan-epic.md` Step 4. It reads the plan, determines phase count, calls the 4 conversion scripts in sequence for each phase, and outputs a JSON manifest summarizing all created artifacts. If any sub-script fails, the pipeline halts immediately (set -e) and reports the failure via stderr. LLM reads the manifest from stdout to validate and report to PM.

**Implementation Detail:**
Script arguments: `--plan <path> --queue-mode <chain|separate|custom> --plugin-dir <path> [--depends-on <custom-deps>]`

Algorithm:
1. Source `lib/common.sh` (resolved relative to script location: `${BASH_SOURCE[0]%/*}/lib/common.sh`)
2. `check_prerequisites` — verify bash, jq, all sub-scripts exist
3. Parse plan.md to determine phase count:
   - Search for explicit phase markers: `grep -c '^\*\*EPIC\|^\*\*Phase' "$plan"`
   - If no explicit markers: count steps (grep `^### Step`) and use plan's phase specification from `## Next Steps` or divide evenly into groups of ~5-7 steps
4. Resolve template paths:
   - `epic_template="${plugin_dir}/defaults/templates/epic.md"`
   - `plan_schema="${plugin_dir}/defaults/templates/plan.schema.json"`
   - `run_template="${plugin_dir}/defaults/templates/run-new-feature.md"`
   - `counter_yaml=".aid-o/03-config/counter.yaml"`
   - `queue_yaml=".aid-o/04-engine/epic-queue.yaml"`
5. Start timer: `start_ms=$(date +%s%3N)`
6. Initialize manifest JSON array: `epics_json="[]"`
7. Initialize `prev_epic_id=""` for chain mode
8. FOR phase in 1..N:
   a. Call `aid-plan-to-epic.sh`:
      ```bash
      epic_path=$("${script_dir}/aid-plan-to-epic.sh" \
        --plan "$plan" --phase "$phase" --total "$total" \
        --epic-template "$epic_template" --output-dir ".aid-o/02-epics" \
        --counter-yaml "$counter_yaml")
      ```
   b. Extract epic_id from generated filename
   c. Call `aid-epic-to-json.sh`:
      ```bash
      json_result=$("${script_dir}/aid-epic-to-json.sh" \
        --epic "$epic_path" --schema "$plan_schema" \
        --output-dir ".aid-o" --plan-source "$plan")
      ```
   d. Extract plan_json path and run_id from json_result
   e. Call `aid-json-to-run.sh`:
      ```bash
      run_path=$("${script_dir}/aid-json-to-run.sh" \
        --plan-json "$plan_json_path" --run-template "$run_template" \
        --epic "$epic_path" --output-dir ".aid-o/04-engine/runs" \
        --run-id "$run_id")
      ```
   f. Determine depends_on for queue based on mode:
      - `chain`: `depends_on="$prev_epic_id"` (empty for first phase)
      - `separate`: `depends_on=""`
      - `custom`: `depends_on="$custom_depends"` (from --depends-on arg)
      Also: read EPIC Dependencies → Queue Implications for external deps, append to depends_on
   g. Call `aid-queue-add.sh`:
      ```bash
      "${script_dir}/aid-queue-add.sh" \
        --epic-id "$epic_id" --epic-path "$epic_path" \
        --priority medium --depends-on "$depends_on" \
        --queue-yaml "$queue_yaml"
      ```
   h. Update `prev_epic_id="$epic_id"`
   i. Append entry to `epics_json` via jq
9. End timer: `duration_ms=$(( $(date +%s%3N) - start_ms ))`
10. Output final manifest JSON to stdout:
    ```bash
    jq -n --arg plan_id "$plan_id" --argjson epics "$epics_json" \
      --argjson duration "$duration_ms" \
      '{plan_id: $plan_id, epics: $epics, duration_ms: $duration}'
    ```

**Error Handling:**
- Sub-script failure: `set -e` causes immediate halt. The failed script's stderr propagates to aid-auto-pipeline.sh stderr. Stdout will be empty (no partial manifest), so LLM detects failure via non-zero exit code.
- Plan has 0 phases detected: exit 1 with `"Could not determine phase count from plan. Ensure Implementation Steps are marked with EPIC/Phase markers."`
- Template file not found: exit 2 with specific missing file path

**Edge Cases:**
- Plan with single phase: loop runs once, chain mode has no depends_on (same as separate)
- `date +%s%3N` not supported on older macOS: fallback to `date +%s` with second precision for duration
- Custom mode with empty --depends-on: treated as separate mode

**Dependencies:**
- Depends on: Steps 1-5 (all sub-scripts must exist)
- Blocks: Step 8 (aid-plan-epic.md calls this script)

**Acceptance Criteria:**
- [ ] Produces valid JSON manifest on stdout with correct epic count, file paths, and duration
- [ ] Chain mode creates sequential depends_on chain across phases
- [ ] Separate mode creates independent entries with no depends_on
- [ ] Pipeline halts on first sub-script failure with descriptive error on stderr

**Effort:** M
**AID Role:** backend

---

**EPIC 2: Steps 7-9 — Commands & Auditor**

### Step 7: Rewrite aid-plan-epic.md

**Objective:** Replace the 530-line LLM-driven command with a ~150-line script-orchestrated flow that uses bash scripts for all deterministic operations.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-plan-epic.md` (lines ~1-544) — complete rewrite of flow section

**Architecture Context:**
This is the central command in the AID pipeline — the entry point PM uses to convert a plan into executable EPICs. The rewrite removes 8 LLM-driven steps (format detection, EPIC generation, plan.json building, run file creation) and replaces them with a 6-step flow where LLM handles only: input validation, PM dialog (queue mode), script invocation, output validation, and reporting. This is the highest-impact change in the plan.

**Implementation Detail:**
New command structure (replacing entire Flow section):

```
Step 0: Version Pre-check
  (Unchanged from current — GitHub API check, non-blocking)

Step 1: Validate Input
  - Read file at given path
  - Check frontmatter for type: plan OR check H1 starts with "# Plan:"
  - If not a Plan: error: "Expected Plan file. Run /aid-brainstorm to create a plan first."
  - Solo EPIC input removed (not supported)
  - If no argument: list files from .aid-o/01-plans/ for selection

Step 2: Plan Analysis
  - Parse frontmatter → plan_id, title
  - Count phases (grep for EPIC/Phase markers in Implementation Steps)
  - Display: "Plan {plan_id}: {title}, {N} phases"

Step 3: Queue Mode Selection (NEW)
  - Present PM with options:
    "(A) Single queue, chain: E-{id}-1→2→...→N (Recommended)
     (B) Separate queue per EPIC
     (C) Custom (I'll ask for specifics)"
  - If C: ask PM for custom depends_on configuration
  - Map PM choice to --queue-mode parameter

Step 4: Execute Pipeline Script
  - Run: bash plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh \
      --plan <path> --queue-mode <mode> --plugin-dir plugins/aid-orchestrator
  - Capture stdout (JSON manifest) and exit code
  - If exit code != 0: display stderr error to PM, offer:
    "(R)etry / (M)anual review of error / (A)bort"

Step 5: Validate Output
  - Parse JSON manifest from stdout
  - For each EPIC entry: verify file exists at path
  - For each plan.json: run jq validate against plan.schema.json
  - If validation fails: report specific error, offer retry

Step 6: Report to PM
  - "{N} EPICs created and queued ({duration}s):"
  - List each EPIC: id, queue status, depends_on
  - "What's next?"
    (A) Start FIRST AID → /aid-first-aid
    (B) Review EPICs → [file paths]
    (C) Review plan.json → [file paths]
    (D) Done (EPICs queued, start later)
```

Remove from current command: Steps 1-8 (Input Format Detection, Plan-to-EPIC Conversion, Load and Validate EPIC, Analyze Steps, Generate Analysis Groups, Build Plan JSON, Save Plan JSON, Generate Run File). All of this is now in scripts.

Preserve: Step 0 (Version Pre-check), Step 9 presentation format (adapted for new output), Reference Files section (updated).

Update Reference Files section to include: `plugins/aid-orchestrator/scripts/README.md` — script interface contracts.

**Error Handling:**
- Script not found at expected path: check `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` exists before calling. If missing: "Pipeline scripts not found. Plugin may need update: claude plugin update aid-orchestrator@claude-aid-o"
- jq not available (script reports exit code 2): "Required dependency 'jq' not found. Install: brew install jq (macOS) or apt install jq (Linux)"
- Manifest JSON parse failure: "Script produced invalid output. Raw output: {first 500 chars}. Report this as a bug."

**Edge Cases:**
- PM selects custom queue mode but then says "actually just chain": map back to chain mode parameter
- Plan file path with spaces: properly quote in bash command
- Script returns 0 but manifest has 0 epics: validation catches this, report "Script produced no EPICs — check plan has Implementation Steps with phase markers"
- Plan.md with zero Implementation Steps passes validation but produces empty manifest: LLM detects this in Step 5 and reports "Plan has no implementation steps — nothing to generate"

**Dependencies:**
- Depends on: Step 6 (aid-auto-pipeline.sh must exist and work)
- Blocks: Steps 9, 10, 11, 12 (all downstream documentation references this command)

**Acceptance Criteria:**
- [ ] Command flow reduced from 9 LLM-driven steps to 6 (validate, analyze, ask, script, validate, report)
- [ ] Script invocation uses correct path and parameters
- [ ] Error handling covers: script not found, jq missing, script failure, validation failure
- [ ] Step 6 output includes FIRST AID offer (discoverability fix)

**Effort:** L
**AID Role:** backend

---

### Step 8: Update aid-run-epic.md — Remove Embedded Plan Generation

**Objective:** Remove the duplicate plan generation fallback from `/aid-run-epic` and require plan.json to already exist (created via `/aid-plan-epic`).

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-run-epic.md` (lines ~28-29, ~93-94) — remove inline plan generation, add plan.json requirement check

**Architecture Context:**
Currently `/aid-run-epic` has a fallback: if plan.json doesn't exist for the given EPIC, it runs the plan generation logic inline (duplicating `/aid-plan-epic` Steps 4-7). With scripts handling plan generation, this fallback would be inconsistent (LLM-driven vs script-driven). The clean solution is to require plan.json to exist, directing PM to run `/aid-plan-epic` first.

**Implementation Detail:**
In the IDLE state / initial validation section of aid-run-epic.md:

Replace the current plan generation fallback with:
```
1. Check if plan.json exists at .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
2. If plan.json exists → proceed to PLANNING state (validate and start)
3. If plan.json does NOT exist → error:
   "No plan.json found for {epic_id}.
    Run /aid-plan-epic first to generate the execution pipeline.

    Usage: /aid-plan-epic .aid-o/01-plans/{source_plan}"
4. If EPIC has plan_ref in frontmatter: include the plan path in the suggestion
```

Remove any section that says "if plan.json is missing, generate it inline" or "invoke planner skill directly."

**Error Handling:**
- EPIC exists but no evidence directory: `"Evidence directory not found for {epic_id}. Run /aid-plan-epic to generate plan.json, run.md, and evidence structure."`
- plan.json exists but fails schema validation: proceed with existing validation logic (unchanged)

**Edge Cases:**
- EPIC from before P018 (created by old LLM-driven pipeline): plan.json should already exist in evidence directory — no change for existing EPICs
- PM runs `/aid-run-epic` directly without `/aid-plan-epic`: clear error message with exact command to run

**Dependencies:**
- Depends on: Step 7 (aid-plan-epic.md rewrite must be done first so PM has the correct pipeline to generate plan.json)
- Blocks: Step 11 (docs update references this change)

**Acceptance Criteria:**
- [ ] `/aid-run-epic` no longer contains inline plan generation logic
- [ ] Clear error message when plan.json is missing, with actionable `/aid-plan-epic` suggestion
- [ ] Existing EPICs with valid plan.json work unchanged

**Effort:** S
**AID Role:** backend

---

### Step 9: Add Deterministic Work Detection to Auditor

**Objective:** Add a new audit type to the Auditor agent that detects commands and skills where LLM performs deterministic operations that could be replaced by scripts.

**Files:**
- Modify: `plugins/aid-orchestrator/agents/auditor.md` (after line ~58, after existing audit categories) — add new audit category H) Deterministic Work Detection

**Architecture Context:**
The Auditor agent runs post-EPIC and produces a health report. Adding "Deterministic Work Detection" as a new audit category enables the system to self-discover future script candidates beyond the `/aid-plan-epic` pipeline. This addresses the PM directive to have the auditor learn to detect this pattern, so future brainstormings have data about where scripts would help.

**Implementation Detail:**
Add new section after existing audit categories (A through G):

```markdown
### H) Deterministic Work Detection (ALWAYS runs)

Scan commands and skills for patterns where LLM performs operations
that could be replaced by deterministic scripts.

**Detection patterns:**

1. TEMPLATE FILLING — LLM instructions contain:
   - Keywords: "fill template", "substitute", "replace {{", "copy section from"
   - Pattern: instruction tells LLM to read a template file and replace placeholders
   - Signal: structured input → structured output with no creative judgment

2. STRUCTURED PARSING — LLM instructions contain:
   - Keywords: "parse YAML", "extract from table", "read frontmatter", "pipe-delimited"
   - Pattern: instruction tells LLM to read structured data and extract fields
   - Signal: regex/awk/jq could do the same extraction deterministically

3. FILE MANIPULATION — LLM instructions contain:
   - Keywords: "create directory", "copy file to", "save JSON to", "update YAML field"
   - Pattern: instruction tells LLM to perform file system operations
   - Signal: mkdir/cp/jq could do the same operation

**Scanning scope:** All files in commands/ and skills/ directories.

**False positive filters:**
- Skip instructions that DESCRIBE what a script does (references to scripts/)
- Skip instructions in "Reference" or "Important" sections (documentation, not execution)
- Skip instructions guarded by "if {condition}" that require judgment

**Output format:**
```
## Deterministic Work Candidates

Found {N} candidates where LLM performs deterministic operations:

| File | Section | Category | Description |
|------|---------|----------|-------------|
| {file} | {section header} | {TEMPLATE_FILLING|STRUCTURED_PARSING|FILE_MANIPULATION} | {what the LLM does that a script could do} |

Recommendation: Consider bash scripts for these operations.
Priority: {HIGH if found in frequently-executed commands, LOW if in rare paths}
```

**Scoring:** Each candidate counts as 1 point deduction from the Documentation Audit score (category C), capped at -10 points. This incentivizes converting candidates to scripts over time without making the audit punitive.
```

**Error Handling:**
- No candidates found: output "Deterministic Work Candidates: 0 found. All detected deterministic operations are already handled by scripts." — positive signal, not an error.
- Files in commands/ or skills/ not readable: skip with warning, do not fail the audit.

**Edge Cases:**
- False positive: instruction says "the script parses YAML" (describing script behavior, not LLM behavior) — filter catches "script" keyword in same paragraph
- Newly added script files in scripts/ directory: auditor should exclude references to these files from detection
- Command that mixes deterministic and creative work (e.g., "parse config then decide which approach"): only flag the deterministic part

**Dependencies:**
- Depends on: Step 7 (aid-plan-epic.md rewrite done, so auditor has a concrete example of the pattern to detect — and to NOT flag)
- Blocks: Step 11 (docs update mentions new audit type)

**Acceptance Criteria:**
- [ ] New audit category H) added to auditor.md with all 3 detection patterns
- [ ] False positive filters exclude references to existing scripts
- [ ] Scoring integration: candidates deduct from Documentation Audit score (capped at -10)

**Effort:** M
**AID Role:** backend

---

**EPIC 3: Steps 10-15 — Docs, Tests & Merge**

### Step 10: Tier 2 Documentation Updates — Significant Changes

**Objective:** Update the 5 files that require significant content changes to reflect the new script-based pipeline.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (lines ~1-10, TL;DR section) — add reference documentation header noting algorithm is implemented in scripts/
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md` (lines ~110-115, EPIC Subagent references) — remove or update EPIC Subagent Prompt Template references since script handles EPIC generation
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~520-556, Post-Write Handoff) — update `/aid-plan-epic` description to reflect new script-based flow
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (PLANNING state section) — add note that plan.json may be generated by scripts
- Modify: `plugins/aid-orchestrator/commands/aid-run-epic.md` (wherever it references plan generation) — ensure references align with Step 8 changes

**Architecture Context:**
These 5 files contain substantial sections that reference the old LLM-driven pipeline. Updating them ensures consistency: any agent or command reading these skills gets accurate information about how plan.json, EPIC files, and run files are created.

**Implementation Detail:**

**planner.md** — Add after TL;DR:
```markdown
> **Note:** The algorithm described in this skill is the reference specification.
> The production implementation is in `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh`.
> This skill document serves as the authoritative design reference for the script
> and for manual review of the algorithm's correctness.
```

**brainstorming.md** — In the section referencing "EPIC Subagent Prompt Template":
- If the section describes how to call LLM to generate EPIC from plan: replace with reference to `aid-plan-to-epic.sh` script
- Update Document Generation Protocol RULE 8 references to mention script-based pipeline
- Keep the template structure documentation (useful for understanding what the script generates)

**plan-writing.md** — Update Post-Write Handoff:
- Option A text: change from "Create EPIC from this plan → /aid-plan-epic" to include note that `/aid-plan-epic` now uses scripts for generation (~5s vs 15+ min)
- Keep all other options unchanged

**epic-orchestration.md** — In PLANNING state section, add:
```markdown
> **Pipeline change (P018):** plan.json, plan_progress.json, and evidence directory
> are now created by bash scripts (`scripts/aid-auto-pipeline.sh`) invoked from
> `/aid-plan-epic`. The Controller reads these artifacts identically regardless
> of whether they were generated by LLM or script.
```

**aid-run-epic.md** — Verify Step 8 changes are reflected. Remove any remaining references to "inline plan generation" or "if plan.json is missing, generate."

**Error Handling:**
- If a referenced section no longer exists (file was restructured): flag for manual review rather than attempting blind edit.

**Edge Cases:**
- planner.md is 88.9KB — ensure note is added near the top (TL;DR area) where readers encounter it first, not buried in the middle
- brainstorming.md EPIC Subagent Template may be referenced from other files — search for cross-references before removing
- epic-orchestration.md PLANNING state section was restructured since plan was written: locate by content pattern (search for "plan.json" or "PLANNING") instead of fixed line numbers

**Dependencies:**
- Depends on: Steps 7, 8 (command rewrites must be done so documentation references are accurate)
- Blocks: Step 11 (Tier 3 references depend on Tier 2 being correct)

**Acceptance Criteria:**
- [ ] planner.md has reference documentation header noting script implementation
- [ ] brainstorming.md no longer directs LLM to generate EPICs inline (references script)
- [ ] plan-writing.md Post-Write Handoff reflects script-based pipeline
- [ ] epic-orchestration.md PLANNING state notes script-generated artifacts
- [ ] No remaining references to "inline plan generation" in aid-run-epic.md

**Effort:** M
**AID Role:** docs

---

### Step 11: Tier 3 Documentation Updates — Reference Changes

**Objective:** Update all files with minor reference changes to ensure consistency with the new pipeline.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-brainstorm.md` (Step 8 handoff text) — update `/aid-plan-epic` reference
- Modify: `plugins/aid-orchestrator/commands/aid-write-plan.md` (post-completion text) — update `/aid-plan-epic` reference
- Modify: `plugins/aid-orchestrator/skills/run-management.md` (run file creation reference) — note scripts create run files
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (PLAN_REVIEW state) — verify plan.json source is agnostic (review only)
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (Source Plan Integration) — verify source_plan field handling is agnostic (review only)
- Modify: `plugins/aid-orchestrator/README.md` — update pipeline description
- Modify: `CHANGELOG.md` (root) — add P018 major change entry
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical entry
- Modify: `CLAUDE.md` (root and project) — verify Key Commands table is accurate

**Architecture Context:**
These files contain textual references to the pipeline that need minor updates — a sentence here, a path there. Unlike Tier 2, these don't require understanding deep logic, just consistent terminology and accurate path references.

**Implementation Detail:**

**aid-brainstorm.md** — Step 8 handoff: no text change needed (already says "invoke plan-writing skill" which then offers `/aid-plan-epic`). Verify and confirm no change needed.

**aid-write-plan.md** — Post-completion: same as above. Verify plan-writing skill handoff is the reference, not direct pipeline description.

**run-management.md** — Find where run file creation is described. Add brief note: "Run files are created by `scripts/aid-json-to-run.sh` (invoked from `/aid-plan-epic`)."

**first-aid-controller.md** — PLAN_REVIEW state: review how it reads plan.json. It should be source-agnostic (reads JSON, doesn't care how it was created). Confirm no change needed.

**dispatch-protocol.md** — Source Plan Integration: review `plan_ref` and `source_plan` handling. These are JSON fields in plan.json — source-agnostic. Confirm no change needed.

**README.md** — Update the pipeline section to mention scripts. Add to plugin features: "Script-based pipeline acceleration — Plan→EPIC→json→run→queue in ~5 seconds"

**CHANGELOG.md** (both):
```markdown
## [X.Y.Z] — 2026-MM-DD

### Added
- **Script-Based Pipeline** — 5 bash scripts replace LLM-driven Plan→EPIC→json→run→queue generation, reducing pipeline time from 15+ minutes to ~5 seconds
- **Auto-Queue Integration** — `/aid-plan-epic` automatically queues all generated EPICs with PM-selectable modes (chain, separate, custom)
- **EPIC Dependencies Section** — new mandatory Dependencies section in EPIC template with Internal/External/Queue subsections for automatic queue depends_on population
- **Deterministic Work Detection** — new auditor check that identifies commands and skills where LLM performs operations replaceable by scripts

### Changed
- **`/aid-plan-epic` Command** — rewritten from 530-line LLM-driven flow to ~150-line script-orchestrated flow (LLM handles PM dialog and validation only)
- **`/aid-run-epic` Command** — removed embedded plan generation fallback; now requires plan.json from `/aid-plan-epic`
- **EPIC Template** — added structured Dependencies section (Internal, External, Queue Implications)

### Fixed
- **FIRST AID Discoverability** — `/aid-plan-epic` output now offers FIRST AID as next step
```

**CLAUDE.md** — Key Commands table: no name change (still `/aid-plan-epic`), verify description is accurate.

**Error Handling:**
- If first-aid-controller.md or dispatch-protocol.md reference plan.json creation method explicitly: change to source-agnostic language.

**Edge Cases:**
- CHANGELOG version number: leave as placeholder `[X.Y.Z]` — release step fills actual version
- README may have other pipeline descriptions in multiple sections: search entire file for "plan-epic" references
- first-aid-controller.md references plan.json creation method using LLM-specific language: update to source-agnostic wording

**Dependencies:**
- Depends on: Step 10 (Tier 2 must be done first for consistent references)
- Blocks: Step 14 (regression test validates all documentation is consistent)

**Acceptance Criteria:**
- [ ] All Tier 3 files reviewed; changes applied where needed, "no change needed" documented for files that are already source-agnostic
- [ ] CHANGELOG entry written in both root and plugin CHANGELOG (identical content)
- [ ] README updated with script-based pipeline feature description

**Effort:** M
**AID Role:** docs

---

### Step 12: Tier 4 Agent Review

**Objective:** Review all agents that read plan.json at runtime to confirm they are unaffected by the change from LLM-generated to script-generated plan.json.

**Files:**
- Review: `plugins/aid-orchestrator/agents/code-reviewer.md` — reads acceptance_criteria from plan step
- Review: `plugins/aid-orchestrator/agents/gate-fixer.md` — reads constraints from plan step
- Review: `plugins/aid-orchestrator/agents/lessons-extractor.md` — reads plan for context
- Review: `plugins/aid-orchestrator/agents/auditor.md` — reads plan.json for audit context (already modified in Step 9)
- Review: `plugins/aid-orchestrator/skills/epic-state-machine.md` — PLANNING state validates plan.json
- Review: `plugins/aid-orchestrator/commands/aid-epic-queue.md` — manual add must work with script-generated EPICs

**Architecture Context:**
These components consume plan.json at runtime. Since the plan.json schema is unchanged (same fields, same validation), they should work without modification. This step is a verification pass to confirm that assumption and document the review.

**Implementation Detail:**
For each file:
1. Search for references to `plan.json`, `plan_progress.json`, `plan_ref`, `source_plan`
2. Verify the reference reads JSON fields that exist in the schema (no assumptions about generation method)
3. Check if any reference mentions "LLM-generated" or "planner skill" in a way that creates a dependency on generation method
4. Document findings: "Reviewed {file} — {N} plan.json references found, all source-agnostic. No changes needed." OR "Reviewed {file} — line {X} references LLM generation. Changed to: {new text}."

For `aid-epic-queue.md`:
1. Test that manual `add` operation works with EPIC files containing the new Dependencies section
2. Verify the `depends_on` field format is compatible between script-generated and manual entries

**Error Handling:**
- If an agent assumes LLM-specific plan.json characteristics (e.g., a specific field ordering or comment in JSON): flag and fix.

**Edge Cases:**
- Agent reads plan.json field that scripts populate differently than LLM would (e.g., different `reason` text in dependencies): acceptable variation — agents should tolerate any valid string
- epic-state-machine.md validates plan.json against schema: since scripts validate against same schema, this is inherently compatible

**Dependencies:**
- Depends on: Steps 9, 10 (auditor already modified, Tier 2 docs done)
- No blocks — this is a verification step

**Acceptance Criteria:**
- [ ] All 6 files reviewed with documented findings
- [ ] Any source-specific references found and fixed
- [ ] Manual `/aid-epic-queue add` tested with script-generated EPIC format

**Effort:** S
**AID Role:** qa

---

### Step 13: Fixture and Unit Tests

**Objective:** Create test fixtures and unit tests for each of the 5 bash scripts.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/minimal-plan.md` — single-phase plan with minimum required sections
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/multi-phase-plan.md` — 3-phase plan with full sections, dependencies, and phase markers
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/plan-with-deps.md` — plan with cross-plan dependencies in Dependencies section
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/expected/` — directory with expected outputs for each fixture
- Create: `plugins/aid-orchestrator/scripts/tests/test-plan-to-epic.sh` — unit tests for aid-plan-to-epic.sh
- Create: `plugins/aid-orchestrator/scripts/tests/test-epic-to-json.sh` — unit tests for aid-epic-to-json.sh
- Create: `plugins/aid-orchestrator/scripts/tests/test-json-to-run.sh` — unit tests for aid-json-to-run.sh
- Create: `plugins/aid-orchestrator/scripts/tests/test-queue-add.sh` — unit tests for aid-queue-add.sh

**Architecture Context:**
Tests validate that scripts produce correct output for known inputs. Fixtures are minimal but complete plan.md files that exercise the parsing logic. Expected outputs are pre-generated files that script output is compared against. This test suite is the safety net that prevents plan.md format changes from silently breaking the pipeline.

**Implementation Detail:**

**minimal-plan.md** — A valid plan with: frontmatter (id: PTEST, type: plan), Context, Goal, Scope (IN/OUT), Approach (chosen only), 3 Implementation Steps (1 architect, 1 backend, 1 qa), Constraints, Risks, Success Criteria. Single phase (no EPIC/Phase markers).

**multi-phase-plan.md** — A valid plan with: same structure, 9 Implementation Steps split into 3 phases via `**EPIC 1: Steps 1-3**`, `**EPIC 2: Steps 4-6**`, `**EPIC 3: Steps 7-9**` markers. Steps include parallel groups and dependencies.

**plan-with-deps.md** — Same as multi-phase but Dependencies section includes: `- P017 / E-017-2_2 — dispatch-config.yaml required`

**test-plan-to-epic.sh**:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${SCRIPT_DIR}/tests/fixtures"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Test 1: Single-phase plan produces 1 EPIC with correct ID
result=$("${SCRIPT_DIR}/aid-plan-to-epic.sh" \
  --plan "${FIXTURES}/minimal-plan.md" --phase 1 --total 1 \
  --epic-template "${SCRIPT_DIR}/../defaults/templates/epic.md" \
  --output-dir "$TMPDIR" --counter-yaml "$TMPDIR/counter.yaml")
[[ -f "$result" ]] || { echo "FAIL: EPIC file not created"; exit 1; }
grep -q "E-TEST-1_1" "$result" || { echo "FAIL: Wrong EPIC ID"; exit 1; }
echo "PASS: Single-phase plan"

# Test 2: Multi-phase plan phase 2 has internal dependency on phase 1
# Test 3: Dependencies section populated for cross-plan deps
# Test 4: Empty Dependencies section produces depends_on: []
# Test 2: Multi-phase plan phase 2 has internal dependency
# Test 3: Dependencies section populated for cross-plan deps
# Test 4: Empty Dependencies section produces depends_on: []
# Test 5: Plan with CRLF line endings parses correctly
# Test 6: Step objective with pipe character does not break table
echo "All tests passed"
```

Similar structure for test-epic-to-json.sh (validates JSON against schema), test-json-to-run.sh (validates run.md sections), test-queue-add.sh (validates YAML manipulation, duplicate rejection, cycle detection).

**Error Handling:**
- Fixture files missing: test script exits immediately with descriptive error
- Expected output mismatch: diff output shown for debugging

**Edge Cases:**
- Tests run on macOS (BSD sed) and Linux (GNU sed): fixtures should work with both — test scripts use portable sed flags only
- counter.yaml doesn't exist at test start: test creates a temporary one
- Fixture plan.md modified after expected/ outputs generated: test fails with clear diff showing what changed, prompting fixture update

**Dependencies:**
- Depends on: Steps 1-6 (all scripts must be implemented)
- Blocks: Step 14 (integration tests build on unit tests passing)

**Acceptance Criteria:**
- [ ] 3 fixture plan files created covering: single phase, multi phase, cross-plan dependencies
- [ ] Each of the 4 script-specific test files has at least 4 test cases
- [ ] All tests pass on both macOS and Linux (portable bash/sed/awk)

**Effort:** M
**AID Role:** qa

---

### Step 14: Integration and Regression Tests

**Objective:** Create an end-to-end integration test and a regression test using a real existing plan.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/test-full-pipeline.sh` — end-to-end integration test
- Create: `plugins/aid-orchestrator/scripts/tests/test-regression.sh` — regression test against P017

**Architecture Context:**
Integration test validates the full aid-auto-pipeline.sh flow. Regression test compares script output against the existing LLM-generated E-017-1_2 to ensure the script produces equivalent (not necessarily identical) output. These tests are the final safety gate before merge.

**Implementation Detail:**

**test-full-pipeline.sh**:
1. Create temporary .aid-o/ structure (mimicking a real workspace)
2. Copy multi-phase-plan.md fixture as the input plan
3. Run aid-auto-pipeline.sh with `--queue-mode chain`
4. Validate:
   - JSON manifest on stdout is valid JSON with expected fields
   - N EPIC files exist at paths in manifest
   - N plan.json files validate against plan.schema.json
   - N run.md files have all required sections (frontmatter, Objective, Phases, Dependencies, Quality Gates, Run Log)
   - epic-queue.yaml has N entries with correct depends_on chain
   - counter.yaml was updated
   - Evidence directories created with plan.json, plan_progress.json, epic_input.md
5. Clean up temp directory

**test-regression.sh**:
1. Copy existing P017 plan (`P017-flow-optimization.md`) as input
2. Run aid-auto-pipeline.sh
3. Compare generated EPIC with existing `E-017-1_2-measure-and-build.md`:
   - Same number of steps in Steps table
   - Same roles in same order
   - Same allowed_paths (±path ordering)
   - Same DoD Gates
   - Acceptance Criteria count within ±20% (script may format differently)
4. Compare generated plan.json structure (not exact values):
   - Same step count
   - Same role set
   - Same dependency count
   - parallel_groups present if original had them
5. Report: "Regression test: {PASS|FAIL} — {details}"

Note: regression test expects SIMILAR output, not IDENTICAL. LLM-generated content has creative elements (reformulated goals, expanded descriptions) that scripts won't replicate exactly. The test validates structural equivalence.

**Error Handling:**
- P017 plan file not found: skip regression test with warning (may be in archive)
- Structural comparison finds major difference (e.g., different step count): FAIL with detailed diff

**Edge Cases:**
- P017 has 12 steps split into 2 EPICs: regression test should detect phase split correctly
- Plan format may have evolved since P017 was written: test should handle minor format variations (compare structure, not exact text)
- P017 plan file is in archive: test looks in both `.aid-o/01-plans/` and `.aid-o/01-plans/archive/` for the fixture

**Dependencies:**
- Depends on: Steps 1-6 (scripts), Step 13 (unit tests must pass first)
- Blocks: Step 15 (pre-merge validation requires all tests passing)

**Acceptance Criteria:**
- [ ] Integration test validates full pipeline output (EPICs, plan.json, run.md, queue entries, evidence structure)
- [ ] Regression test compares script output with existing E-017-1_2 and reports structural equivalence
- [ ] Both tests pass without manual intervention

**Effort:** M
**AID Role:** qa

---

### Step 15: Pre-Merge Validation and Cleanup

**Objective:** Run all tests, perform manual validation with a real plan, and verify all 21 affected files are consistent before merge.

**Files:**
- No new files created
- Review: all 21 affected files from Documentation Consistency Pass (Tier 1-4)

**Architecture Context:**
This is the final step before merging the feature branch to main. It combines automated test results with manual validation to ensure the entire pipeline works end-to-end. The constraint is explicit: no merge until all tests pass and manual validation confirms the pipeline works.

**Implementation Detail:**

**Automated validation:**
1. Run all unit tests: `bash scripts/tests/test-plan-to-epic.sh && bash scripts/tests/test-epic-to-json.sh && bash scripts/tests/test-json-to-run.sh && bash scripts/tests/test-queue-add.sh`
2. Run integration test: `bash scripts/tests/test-full-pipeline.sh`
3. Run regression test: `bash scripts/tests/test-regression.sh`
4. All must pass (exit 0)

**Manual validation:**
1. On the feature branch, run `/aid-plan-epic` with a real plan (P015, P016, or P017 — whichever is available and not yet has EPICs)
2. Verify:
   - PM sees queue mode question
   - Script executes in <10s
   - EPICs created with correct IDs and content
   - plan.json validates
   - run.md has complete sections
   - Queue entries visible via `/aid-epic-queue list`
3. Run `/aid-epic-queue add` manually with one of the generated EPICs → confirm it works (idempotent — should reject as duplicate)
4. Run `/aid-audit` → confirm new "Deterministic Work Detection" category appears in audit report

**Documentation checklist verification:**
Walk through each of the 21 files from Step 10-12:
- [ ] aid-plan-epic.md — rewritten (Step 7)
- [ ] planner.md — reference header added (Step 10)
- [ ] brainstorming.md — EPIC Subagent updated (Step 10)
- [ ] plan-writing.md — handoff updated (Step 10)
- [ ] epic-orchestration.md — PLANNING note added (Step 10)
- [ ] aid-run-epic.md — embedded generation removed (Step 8)
- [ ] epic.md template — Dependencies section added (Step 2)
- [ ] auditor.md — new audit type added (Step 9)
- [ ] aid-brainstorm.md — verified (Step 11)
- [ ] aid-write-plan.md — verified (Step 11)
- [ ] run-management.md — updated (Step 11)
- [ ] first-aid-controller.md — reviewed (Step 11)
- [ ] dispatch-protocol.md — reviewed (Step 11)
- [ ] README.md — updated (Step 11)
- [ ] CHANGELOG.md (both) — entries written (Step 11)
- [ ] CLAUDE.md — verified (Step 11)
- [ ] code-reviewer.md — reviewed (Step 12)
- [ ] gate-fixer.md — reviewed (Step 12)
- [ ] lessons-extractor.md — reviewed (Step 12)
- [ ] epic-state-machine.md — reviewed (Step 12)
- [ ] aid-epic-queue.md — reviewed (Step 12)

**Error Handling:**
- Test failure: do NOT merge. Fix the failing test, re-run all tests.
- Manual validation reveals issue: create targeted fix, re-run affected tests.

**Edge Cases:**
- Feature branch has diverged significantly from main: rebase before merge, re-run tests after rebase
- Manual test reveals edge case not covered by fixtures: add new fixture, add test, fix script, re-run
- Validation plan (P015/P016/P017) has been archived and is not in `.aid-o/01-plans/`: check `archive/` subdirectory for test inputs

**Dependencies:**
- Depends on: ALL previous steps (1-14)
- No blocks — this is the final step

**Acceptance Criteria:**
- [ ] All automated tests pass (unit + integration + regression)
- [ ] Manual `/aid-plan-epic` run succeeds with real plan on feature branch
- [ ] Manual `/aid-epic-queue add` works with script-generated EPIC
- [ ] All 21 files from documentation checklist verified
- [ ] Feature branch is ready for merge to main

**Effort:** M
**AID Role:** qa

## Testing Strategy

**Three-tier test approach:**

1. **Unit tests** (per-script) — 4 test files, each with 4-6 test cases validating individual script behavior against fixtures. Portable bash (macOS + Linux).

2. **Integration test** (full pipeline) — End-to-end test of aid-auto-pipeline.sh validating the entire artifact chain: EPICs, plan.json, run.md, queue entries, evidence directories.

3. **Regression test** — Comparison of script output with existing LLM-generated EPIC (E-017-1_2) to verify structural equivalence. Validates that the script produces functionally correct output that the Controller and agents can consume.

**Test location:** `plugins/aid-orchestrator/scripts/tests/`

**Pre-merge gate:** All 3 test tiers must pass + manual validation on feature branch.

## Constraints

- Feature branch only — no merge to main until all tests pass and manual validation confirms the pipeline works end-to-end
- plan.json backward compatibility — existing plan.json files must continue to work with Controller and all agents
- epic-queue.yaml backward compatibility — no format changes; manual `/aid-epic-queue add` must still work
- Scripts require only: bash 4.0+, jq, sed, awk, date — no pip, npm, or other package managers
- jq is the only "extra" dependency — scripts must detect its absence and error with install instructions
- plan-writing skill format must not be changed — scripts parse its output; they are versioned together in the plugin

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Plan.md parsing fragility (non-standard formatting) | Medium | High | Plan-writing skill enforces strict format. Scripts validate output. LLM reports specific parse errors to PM. |
| jq unavailable on target system | Medium | High | Script Step 0: detect jq, print install instructions, exit cleanly. aid-plan-epic.md Step 1 checks prerequisites. |
| Kahn's algorithm complexity in bash | Low | Medium | Typically 2-3 EPICs (simple graphs). Implementation via jq JSON manipulation. |
| 21 files consistency — something forgotten | Medium | Medium | Dedicated docs steps (10, 11, 12) with explicit checklists. Code-reviewer on docs step. Feature branch review before merge. |
| plan-writing skill changes format | Low | High | Script and plan-writing versioned together in plugin. Regression test with P017 fixture detects breaking changes. |
| Evidence directory structure mismatch | Low | High | Script creates identical structure as current LLM pipeline. Integration test verifies. |
| Counter.yaml race condition | Low | Medium | Pipeline is PM-initiated (never parallel). Script reads+increments+writes in single invocation. |
| Feature branch merge conflicts (long-lived branch) | Medium | Medium | 3-phase EPIC chain. Merge after each phase passes tests. Rebase before merge. |

## Success Criteria

- `/aid-plan-epic` with a 3-phase plan completes in <10 seconds (vs 15+ minutes today)
- All generated artifacts (EPIC, plan.json, run.md) are structurally valid and consumable by Controller and agents
- Existing `/aid-epic-queue add` manual workflow works unchanged
- All 21 affected files are consistent with the new pipeline
- Zero test failures (unit + integration + regression)
- `/aid-audit` reports "Deterministic Work Detection" findings

## Next Steps

- [ ] Create EPIC(s) from this plan → `/aid-plan-epic .aid-o/01-plans/P018-script-based-pipeline-accel.md`
- [ ] Backlog: Fast mode (direct development without orchestration, quality gates at end)
- [ ] Backlog: History cleanup (archive pruning of early EPICs E-001 through E-004)
- [ ] Backlog: Additional script candidates from auditor findings

---

**Last Updated:** 2026-02-28
