---
name: aid-plan-epic
description: Generate EPICs, Plan JSON, and Run files from a Plan specification
user_invocable: true
---

Parse a **Plan** file, generate EPICs (one per phase), plan.json, run.md, and queue entries — all in one command. Deterministic operations are delegated to bash pipeline scripts; the LLM handles only PM dialog, script invocation, output validation, and reporting.

## Usage

```
/aid-plan-epic <path-to-plan-file>
```

**Examples:**
```
/aid-plan-epic .aid-o/01-plans/P005-C-aid-gui-backend.md
/aid-plan-epic .aid-o/01-plans/2026-02-28-pipeline-scripts.md
```

Only Plan files are accepted. Solo EPIC input is not supported — use `/aid-run-epic` directly for existing EPICs.

## Prerequisites

- `.aid-o/` workspace must exist (run `/aid-init` first)
- Input file must be a Plan (frontmatter `type: plan` or H1 starts with `# Plan:`)
- `jq` must be installed (`brew install jq` on macOS, `apt install jq` on Linux)

## Flow

### Step 0: Version Pre-check

Before doing anything else, check whether the local plugin version matches the
latest published release. This is a **non-blocking warning** — the command always
continues to Step 1 regardless of the result.

1. **Read local version:**
   - Parse `plugins/aid-orchestrator/.claude-plugin/plugin.json`
   - Extract the `version` field (e.g., `"0.9.3"`)
   - Prefix with `v` for display (e.g., `v0.9.3`)

2. **Fetch latest release from GitHub:**
   - Run: `gh api repos/marekstancl/claude-aid-o/releases/latest --jq '.tag_name'`
   - This returns the tag name of the latest release (e.g., `v0.10.0`)

3. **Compare versions:**
   - Strip the `v` prefix from both versions for comparison
   - Split on `.` and compare numerically: major, then minor, then patch
   - Determine: outdated (local < latest), up-to-date (equal), or ahead (local > latest)

4. **Display result:**

   **If outdated** (local < latest):
   ```
   Version Check
   ====================================
   Local:   v{local_version}
   Latest:  v{latest_version}
   Status:  ⚠ Update available

   Run: claude plugin update aid-orchestrator@claude-aid-o
   ====================================
   ```

   **If up to date or ahead** (local >= latest):
   ```
   Version Check: v{local_version} (up to date)
   ```

5. **Error handling — skip gracefully:**
   If the `gh` command fails for any reason (not installed, not authenticated,
   network offline, no releases exist, API rate-limited), do NOT abort. Instead
   display:
   ```
   Version check skipped (gh API unavailable)
   ```
   Then proceed to Step 1 normally.

After displaying the version check result, proceed to Step 1.

### Step 1: Validate Input

1. If `$ARGUMENTS` is empty (no path provided):
   - List files from `.aid-o/01-plans/` for selection
   - Present the list to PM and ask them to choose a Plan file
2. Read the file at the given path
3. Validate it is a Plan file:
   - **Frontmatter check:** YAML frontmatter contains `type: plan` — valid Plan
   - **Header check:** First H1 header starts with `# Plan:` — valid Plan
   - If neither matches: **STOP** and display:
     ```
     ERROR: Expected Plan file.
     ================================
     File: {path}

     This file does not appear to be a Plan. Only Plan files are accepted.
     Run /aid-brainstorm to create a plan first.
     ```

### Step 2: Plan Analysis

1. Parse frontmatter to extract `id` (plan_id) and `title`
   - If `id` is missing: extract from filename `P{NNN}` pattern
   - If title is missing: extract from H1 header
2. Count phases by scanning the `## High-Level Steps` table rows (or equivalent phase markers in `## Implementation Steps`)
3. Display summary to PM:
   ```
   Plan {plan_id}: {title}, {N} phases
   ```

### Step 3: Queue Mode Selection

Present PM with queue dependency options:

```
How should these {N} EPICs be queued?

  (A) Single queue, chain: E-{id}-1 -> 2 -> ... -> N  (Recommended)
  (B) Separate queue per EPIC (all independent, can run in parallel)
  (C) Custom (I'll ask for dependency specifics)
```

- If PM selects **(A)**: set `queue_mode=chain`
- If PM selects **(B)**: set `queue_mode=separate`
- If PM selects **(C)**: ask PM for custom `depends_on` configuration (comma-separated EPIC IDs), then set `queue_mode=custom` with the provided dependencies

### Step 4: Execute Pipeline Script

1. **Locate scripts:**
   - Check that `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` exists
   - If not found: **STOP** and display:
     ```
     Pipeline scripts not found. Plugin may need update:
     claude plugin update aid-orchestrator@claude-aid-o
     ```

2. **Run the pipeline:**
   ```bash
   bash plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh \
     --plan <path> \
     --queue-mode <mode> \
     --plugin-dir plugins/aid-orchestrator
   ```
   - If `queue_mode=custom`, also pass `--depends-on <comma-separated-ids>`

3. **Capture output:**
   - stdout contains the JSON manifest
   - stderr contains progress messages (`[INFO]`) and errors

4. **Handle exit codes:**

   | Exit Code | Action |
   |-----------|--------|
   | 0 | Success — proceed to Step 5 |
   | 1 | Validation error — display stderr error to PM |
   | 2 | Missing dependency — display: `"Required dependency 'jq' not found. Install: brew install jq (macOS) or apt install jq (Linux)"` |
   | 3 | File I/O error — display stderr error to PM |

5. **On non-zero exit:** offer PM recovery options:
   ```
   Pipeline failed (exit code {N}): {error message}

     (R) Retry
     (M) Manual review of error
     (A) Abort
   ```

### Step 5: Validate Output

1. Parse the JSON manifest from stdout
   - If JSON parse fails: **STOP** and display:
     ```
     Script produced invalid output. Raw output (first 500 chars):
     {first 500 chars of stdout}

     Report this as a bug.
     ```
2. Check the `epics` array is non-empty
   - If empty (0 epics): **STOP** and display:
     ```
     Script produced no EPICs — check plan has Implementation Steps with phase markers.
     ```
3. For each EPIC entry in the manifest:
   - Verify the file at `epic_path` exists
   - Verify the file at `plan_json` exists
   - Verify the file at `run_path` exists
4. For each `plan_json` path: validate the JSON against `plan.schema.json` using `jq`
   - If validation fails: report the specific error and path, offer retry

### Step 6: Report to PM

Display the pipeline results:

```
{N} EPICs created and queued ({duration}s):
====================================

| # | EPIC ID      | Queue Status | Depends On          |
|---|--------------|-------------|---------------------|
| 1 | E-{id}-1_{N} | queued      | (none)              |
| 2 | E-{id}-2_{N} | queued      | E-{id}-1_{N}        |
| 3 | E-{id}-3_{N} | queued      | E-{id}-2_{N}        |

Files created:
  EPICs:      {list of epic_path values}
  Plans:      {list of plan_json values}
  Runs:       {list of run_path values}

What's next?
  (A) Start FIRST AID           -> /aid-first-aid
  (B) Review EPICs              -> {epic_path list}
  (C) Review plan.json          -> {plan_json list}
  (D) Done (EPICs queued, start later)
```

## Reference Files

- **`plugins/aid-orchestrator/scripts/README.md`** — Pipeline script contracts, arguments, and JSON manifest format
- **`skills/planner.md`** — Planner skill: dependency graph, parallel groups, auto-triggers, analysis groups generation
- **`skills/brainstorming.md`** — EPIC Subagent Prompt Template (used by aid-plan-to-epic.sh)
- `skills/epic-orchestration.md` — Section "2. PLANNING" (plan generation rules, evidence structure)
- `.aid-o/03-config/templates/plan.schema.json` — Plan JSON schema (includes `analysis_groups`)
- `.aid-o/03-config/templates/run-new-feature.md` — Run file template
- `.aid-o/03-config/policies/decision-policies.yaml` — Architecture principles for step ordering
- `.aid-o/03-config/policies/gates.yaml` — Available gates

## Important

- **NEVER modify the original Plan file** — it is the source of truth
- **Solo EPIC input is not supported** — only Plan files are accepted; use `/aid-run-epic` directly for existing EPICs
- If `$ARGUMENTS` is empty, list files from `.aid-o/01-plans/` (marked as `(Plan)`) for selection
- If a queue entry already exists for any generated EPIC, the pipeline script handles deduplication (exit code 1 with descriptive error)
- The pipeline scripts handle all deterministic work: Plan-to-EPIC conversion, plan.json generation, run.md generation, and queue entry creation
- The LLM's role is: PM dialog (Steps 1-3), script invocation (Step 4), output validation (Step 5), and reporting (Step 6)
- Budget defaults: `max_llm_cost_usd: 50`, `max_retries_per_gate: 3` (unless EPIC specifies otherwise)
