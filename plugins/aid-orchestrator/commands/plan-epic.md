---
name: plan-epic
description: Generate Plan JSON from EPIC or Plan specification
user_invocable: true
---

Parse an EPIC **or Plan** file and generate a Plan JSON + Session file for the Controller state machine.

This command is the entry point to orchestration — it reads an EPIC (or auto-converts a Plan to an EPIC), analyzes its steps and dependencies, and produces a validated execution plan that `/run-epic` will follow.

## Usage

```
/plan-epic <path-to-epic-or-plan-file>
```

**Examples:**
```
/plan-epic .aid-o/02-epics/E-20260216-c2d1-user-auth.md          # EPIC input (standard)
/plan-epic .aid-o/01-plans/2026-02-19-aido-v040.md                # Plan input (auto-converts to EPIC)
/plan-epic workspace/workflow/epics/active/EPIC-TEST-0001-DUMMY.md
```

## Prerequisites

- `.aid-o/` workspace must exist (run `/aid-init` first)
- Input file must be an EPIC (preferred) or a Plan (auto-converted to EPIC)

## Flow

### Step 0.5: Input Format Detection

Before validating EPIC sections, detect whether the input file is a Plan or an EPIC.

1. Read the input file at the given path
2. Detect format using this heuristic (first match wins):
   a. **Frontmatter check:** If YAML frontmatter contains `type: plan` → Plan format
   b. **Header check:** If first H1 header starts with `# Plan:` → Plan format.
      If first H1 header starts with `# EPIC:` → EPIC format
   c. **Section fingerprinting:** Scan for section headers:
      - If file contains BOTH `## DoD Gates` AND (`## Steps (Role Pipeline)` OR `## Steps`) → EPIC format
      - If file contains ANY of (`## High-Level Steps`, `## Approach`, `## Success Criteria`,
        `## Task Order`) AND lacks `## DoD Gates` → Plan format
   d. **Ambiguous:** Ask PM: "This file doesn't match the standard Plan or EPIC format.
      Is this a (P)lan or an (E)PIC?"

3. If EPIC format detected → proceed to Step 1 (no change to existing flow)
4. If Plan format detected → proceed to Step 0.7 (Plan-to-EPIC conversion)

### Step 0.7: Plan-to-EPIC Conversion

When a Plan file is provided instead of an EPIC, auto-generate an EPIC using the
EPIC Subagent Prompt Template from `skills/brainstorming.md`.

1. Read the plan file content (already loaded)
2. Read `skills/brainstorming.md` Section "EPIC Subagent Prompt Template"
3. Read `.aid-o/04-engine/memory/project-profile.yaml` for tech stack context
4. Read `.aid-o/03-config/templates/epic.md` for the EPIC template structure
5. Determine output language:
   - Read `.aid-o/03-config/language.yaml` → `document_language` (default: `EN`)
6. Extract plan_id:
   - From frontmatter `id` field if present (e.g., `P-20260218-v020`)
   - From filename if no frontmatter (e.g., `2026-02-19-aido-v040` → `P-20260219`)
   - Fallback: `P-{YYYYMMDD}-{4char-hash}`
7. Generate EPIC using the EPIC Subagent Prompt Template:
   - Substitute `{plan_content}` with the plan file content
   - Substitute `{project_profile_yaml}` with the project profile
   - Substitute `{epic_template}` with the EPIC template
   - Substitute `{document_language}` with the resolved language
   - Substitute `{plan_id}` with the extracted plan ID
8. Generate EPIC ID: `E-{YYYYMMDD}-{4char-hash}`
9. Generate topic slug from plan title (lowercase, hyphens, max 40 chars)
10. Save EPIC to `.aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md`
11. Present to PM:
    ```
    Input detected as a Plan (not an EPIC).
    ====================================
    Plan: {plan_file_path}
    Generated EPIC: .aid-o/02-epics/E-{id}-{topic}.md

    The EPIC was auto-generated from your plan using the standard template.
    Review it below, then I'll proceed with plan generation.

    [Show EPIC summary: Goal, Scope, Steps count, DoD Gates]

    Proceed with plan generation? (Y/N/Edit)
    ```
12. If PM says Y → proceed to Step 1 with the newly generated EPIC file path
13. If PM says N → stop, tell PM to edit EPIC manually and re-run
14. If PM says Edit → PM modifies sections inline, then proceed to Step 1

IMPORTANT: The generated EPIC is a DRAFT. PM reviews it before plan generation
proceeds. This ensures the Plan-to-EPIC conversion quality is validated.

### Step 1: Load and Validate EPIC

1. Read the EPIC file at the given path
2. Validate required sections exist:
   - **Goal** — what must be true when complete
   - **Scope** — allowed files/paths, forbidden zones
   - **Constraints** — budget, patterns, requirements
   - **DoD Gates** — which quality gates apply
   - **Acceptance Criteria** — specific, testable criteria
3. If any section is missing, **STOP** and report:
   ```
   ERROR: EPIC validation failed
   ================================
   File: {path}
   Missing sections:
   - Goal (required)
   - Acceptance Criteria (required)

   Fix the EPIC file and re-run /plan-epic.
   Template: .aid-o/03-config/templates/epic.md
   ```
4. Extract `epic_id` from filename:
   - `EPIC-TEST-0001-DUMMY.md` → `TEST-0001`
   - `E-20260216-c2d1-user-auth.md` → `E-20260216-c2d1`
   - Fallback: use full filename without `.md`

### Step 2: Analyze Steps, Dependencies, and Parallel Groups

> **Reference:** Read `skills/planner.md` for the complete algorithm (dependency graph, parallel groups, ordering rules).

1. Find the **Steps** section in the EPIC (may be called "Steps", "Steps (Role Pipeline)", or "Sessions")
2. For each step, extract:
   - **Role** — must be one of: `architect`, `domain`, `backend`, `frontend`, `qa`, `security`, `observability`, `docs`, `release`
   - **Objective** — what the step must accomplish
   - **Dependencies** — which steps must complete first (from "Depends On" column)
   - **Parallel Group** — which steps can run concurrently (from "Parallel Group" column)
3. If EPIC has explicit steps table → use it directly
4. If EPIC has only Sessions section → extract roles from session descriptions, apply default ordering

**Dependency Graph Construction** (per `skills/planner.md` Section 1):
1. Parse steps into (step_id, role, objective, depends_on[])
2. Build adjacency list (before → after)
3. Validate: no cycles (topological sort must succeed), all refs exist, no self-deps

**Parallel Group Detection** (per `skills/planner.md` Section 2):
1. Topological sort → level assignment (Level 0 = no deps, Level N = all deps at lower levels)
2. Steps at same level with no inter-dependencies → parallel group
3. Single-step levels → sequential (no parallel_groups entry)

**Default Ordering Rules** (per `skills/planner.md` Section 3):
- Architect ALWAYS first (contracts before implementation)
- Domain after Architect (needs contracts)
- Backend + Frontend in parallel (both depend on contracts)
- QA + Security + Observability in parallel (all depend on implementation)
- Docs after implementation steps
- Release last (needs all gates to pass)

If the EPIC explicitly defines a different order → respect it (EPIC overrides defaults).

### Step 2.5: Generate Analysis Groups

> **Reference:** Read `skills/planner.md` Section 4 for auto-trigger rules.

After building steps + dependencies + parallel_groups, generate analysis groups:

1. **Apply auto-trigger rules** to each step:
   - **Security-relevant:** step objective mentions auth/token/encryption/SQL/injection/etc → add `security` review (union)
   - **High complexity:** step has 5+ outputs or mentions refactor/migrate/redesign → add `architect` review (weighted)
   - **Database changes:** step mentions migration/schema/database/model → add `backend` + `security` validation (consensus)
   - **API contract changes:** step role is architect, outputs include OpenAPI/contract/ADR → add `backend` + `frontend` validation (union)

2. **Check EPIC for manual analysis_groups** — the EPIC may explicitly define analysis groups
3. **Merge auto + manual:** manual groups take precedence on conflict (same target + same agents → keep manual)
4. **Assign IDs:** `analysis_{N}_{purpose}` (e.g., `analysis_1_security_review`)
5. **Validate:** all targets reference existing steps, all agents are valid roles, agents != target step's own role
6. Add `analysis_groups` array to Plan JSON (empty array `[]` if no triggers matched)

### Step 3: Build Plan JSON

Read `.aid-o/03-config/templates/plan.schema.json` for the schema definition.

**Source Plan Resolution (Variant B):**

Before building plan.json, check if the EPIC has a source plan:

1. Read EPIC frontmatter → extract `plan_ref` field
2. If `plan_ref` is set and not null:
   a. Resolve plan file path:
      - If relative: resolve against `.aid-o/01-plans/`
      - If absolute: use as-is
   b. Verify file exists and is readable
   c. Set `source_plan` in plan.json to the resolved path
   d. Read plan file content for step enrichment (see below)
3. If `plan_ref` is null or missing:
   a. Set `source_plan: null` in plan.json
   b. Skip enrichment (standard flow)

Generate a Plan JSON object with these fields:

```json
{
  "epic_id": "{extracted from step 1}",
  "source_plan": "{path to source .md plan file, or null if no plan_ref}",
  "version": 1,
  "created_at": "{ISO 8601 timestamp}",
  "steps": [
    {
      "id": "step_{N}_{role}",
      "role": "{role}",
      "objective": "{from EPIC step}",
      "inputs": ["{EPIC spec}", "{outputs from dependency steps}"],
      "outputs": ["{expected artifacts}"],
      "constraints": ["{from EPIC Constraints + Scope}"],
      "allowed_paths": ["{from EPIC Scope → Allowed files/paths}"],
      "forbidden_paths": ["{from EPIC Scope → Forbidden zones}"],
      "acceptance_criteria": ["{verifiable criteria derived from EPIC + step objective}"]
    }
  ],
  "dependencies": [
    {
      "before": "step_{N}_{role}",
      "after": "step_{M}_{role}",
      "reason": "{why this ordering}"
    }
  ],
  "parallel_groups": [
    ["step_3_backend", "step_4_frontend"]
  ],
  "analysis_groups": [
    {
      "id": "analysis_1_security_review",
      "target": "step_3_backend",
      "agents": ["security"],
      "mode": "review",
      "merge_strategy": "union",
      "trigger": "auto"
    }
  ],
  "gates": ["{from EPIC DoD Gates}"],
  "budget": {
    "max_llm_cost_usd": "{from EPIC Constraints, default 50}",
    "max_retries_per_gate": 3
  }
}
```

**Note:** `analysis_groups` may be an empty array `[]` if no auto-trigger rules matched and EPIC didn't specify any. This is valid — plans without analysis groups work normally.

**Step ID format:** `step_{N}_{role}` where N is sequential (1, 2, 3...).

**Inputs/Outputs derivation:**
- Step 1 (architect): inputs = ["EPIC specification"], outputs = contracts/ADRs
- Steps depending on architect: inputs include architect's outputs
- QA/Security: inputs include implementation outputs
- Docs: inputs include all previous outputs

**Acceptance criteria derivation:**
- From EPIC acceptance criteria (mapped to relevant steps)
- From step objective (decomposed into verifiable checks)
- From step outputs (each output = one criterion: "artifact exists and is complete")
- Keep criteria specific and testable — "API docs cover all new endpoints" not "docs are good"

**Self-validation** (per `skills/planner.md` Section 6): After generating, verify:
- All `step.id` values are unique
- All `step.role` values are valid enum values
- All dependency `before`/`after` reference existing step IDs
- All parallel_groups reference existing step IDs
- No circular dependencies (DAG validation)
- Gates values are valid enum values from schema
- All `analysis_groups[].target` reference existing step IDs
- All `analysis_groups[].agents` are valid role enum values
- All `analysis_groups[].merge_strategy` are: union|consensus|weighted
- All `analysis_groups[].mode` are: review|audit|validation
- No duplicate analysis_group IDs
- Analysis group agents != target step's agent role (no self-review)

If validation fails → fix and regenerate (do not present invalid plan).

**Source Plan Step Enrichment (Variant B):**

When building each step in plan.json AND `source_plan` is available:

For each step S:
  1. Find matching plan task section (by objective keywords or Plan Task ID in objective)
  2. If matched:
     a. Enrich `inputs`: add specific files mentioned in plan task
     b. Enrich `outputs`: add specific files/artifacts from plan task
     c. Enrich `constraints`: add per-task constraints from plan
     d. Enrich `acceptance_criteria`: add verifiable criteria from plan task
  3. If not matched: use EPIC-derived data only (no error)

IMPORTANT: Enrichment is ADDITIVE — EPIC-derived data is the base,
plan task detail supplements it. Never override EPIC constraints with plan data.

### Step 4: Save Plan JSON

1. Generate `run_id`: `run_{YYYYMMDD}_{4char-hash}` (hash from `echo $(date +%s%N | md5sum | head -c 4)`)
2. Create evidence directory: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/`
3. Save plan to: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json`
4. Initialize progress tracker: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan_progress.json`:
   ```json
   {
     "epic_id": "{epic_id}",
     "run_id": "{run_id}",
     "state": "PLANNING",
     "started_at": "{ISO 8601}",
     "steps": {
       "step_1_architect": {
         "status": "pending",
         "review_cycles": 0,
         "last_review": null
       },
       "step_2_domain": {
         "status": "pending",
         "review_cycles": 0,
         "last_review": null
       }
     },
     "current_step": null,
     "gates": {},
     "escalations": []
   }
   ```
5. Copy EPIC to evidence: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/epic_input.md`

### Step 5: Generate Session File (Session Creation Protocol)

The session file is the human-readable operational document for this EPIC run.
It must be **detailed enough** that any agent reading it understands the full scope,
their role, inputs/outputs, and acceptance criteria — without needing to parse plan.json.

#### 5a. Gather Sources

Before creating the session file, read ALL of the following:

1. **EPIC file** (already loaded from Step 1) — goal, scope, constraints, affected areas
2. **Plan JSON** (generated in Step 3) — steps, dependencies, parallel_groups, analysis_groups, gates, budget
3. **Plan file** (`.aid-o/01-plans/` or `workspace/workflow/plans/` if referenced in EPIC) — broader project context
4. **Previous session** (if `epic_session > 1`) — what was delivered, lessons learned
5. **Relevant source code** — scan inputs/outputs from plan steps, read key files to understand current state
6. **Decision policies** (`.aid-o/03-config/policies/decision-policies.yaml`) — auto_decisions, escalation_triggers

#### 5b. Create Session File

1. Generate session ID: `S-{YYYYMMDD}-{4char-hash}`
2. Use template from `.aid-o/03-config/templates/session-new-feature.md` (or type-appropriate template)
3. Fill in frontmatter:
   ```yaml
   id: S-{YYYYMMDD}-{hash}
   type: new-feature
   status: active
   priority: {from EPIC}
   started: {YYYY-MM-DD}
   epic_id: {epic_id}
   epic_session: {N}
   plan_ref: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
   source_plan: {from plan.json source_plan field, or null}
   orchestrated: true
   ```

#### 5c. Map Plan JSON to Session Phases

For EACH step in plan.json, create a Phase in the session file:

1. `step.objective` → **Phase Goal** — expand the objective into a full paragraph explaining what the phase accomplishes and why
2. `step.role` → **Agent / Role** — the agent role that will execute this phase
3. `step.inputs` → **Inputs** — translate file paths to readable descriptions with paths
4. `step.outputs` → **Outputs** — describe expected deliverables with file paths
5. `step.constraints` → **Constraints** — list as bullet points
6. `step.allowed_paths` + `step.forbidden_paths` → add to Constraints as scope boundaries
7. Check `analysis_groups` — if this step is the target of an analysis group, add to the phase: "Post-phase review: {agent roles} will perform {mode} analysis (merge strategy: {merge_strategy})"
8. Create **Acceptance** checklist from outputs (each output = one checkbox) + constraints that can be verified

**Source Plan Phase Enrichment (Variant B):**

When creating each Phase AND `source_plan` is available in plan.json:

1. Read the matching plan task section
2. Use plan task's detailed description to expand Phase Goal:
   - Instead of just restating the step objective, include WHY this phase
     matters, WHAT specific changes are expected, and KEY decisions from the plan
3. Add to Phase Inputs: "Source plan: {source_plan} (Task {X})"
4. Add to Phase Constraints: any specific implementation constraints from the plan task
   that aren't captured in plan.json (e.g., "never overwrite existing rules — append only")

#### 5d. Fill Remaining Sections

- **Objective:** 3-5 sentences from EPIC goal + scope. Include success criteria.
- **Context:** Reference previous sessions (if epic_session > 1), current code state, what was delivered before.
- **Scope:** IN list from EPIC scope (min 3 items), OUT list from EPIC constraints/exclusions (min 2 items).
- **Dependencies:** Table from plan.json `dependencies` array — "Phase X depends on Phase Y because Z".
- **Quality Gates:** List from plan.json `gates` array + relevant entries from decision-policies.yaml.
- **Session Log:** Initialize with `| {date} | Session created from EPIC {epic_id}, {step_count} phases planned |`

#### 5e. Quality Check

Before saving, verify the session file contains:
- [ ] Objective: 3+ sentences (not just a one-liner)
- [ ] Context: references to previous work or "greenfield" statement
- [ ] Scope: IN list (3+ items) and OUT list (2+ items)
- [ ] Phases: each phase has all 6 subsections (Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance)
- [ ] Dependencies: table with at least one entry (or "No inter-phase dependencies" for single-step plans)
- [ ] Quality Gates: at least one gate listed
- [ ] Session Log: initialized

If any check fails, fix before proceeding.

#### 5f. Save

Save to: `.aid-o/04-engine/sessions/S-{YYYYMMDD}-{hash}-{topic}.md`

### Step 6: Present Output

```
Plan Generated for EPIC: {epic_id}
====================================
Steps: {count}
Parallel groups: {count}
Analysis groups: {count}
Dependencies: {count}
Roles: {comma-separated list}
Gates: {comma-separated list}
Budget: ${max_cost}

Step sequence:
  1. [architect] {objective}
  2. [domain] {objective} (depends on: step 1)
  3. [backend] {objective} (depends on: step 2) ← parallel group 1
  4. [frontend] {objective} (depends on: step 1) ← parallel group 1
  5. [qa] {objective} (depends on: step 3) ← parallel group 2
  6. [security] {objective} (depends on: step 3) ← parallel group 2
  7. [docs] {objective} (depends on: step 3)

Analysis groups:
  - analysis_1_security_review: [security] → step_3_backend (auto, union)
  - analysis_2_db_validation: [backend, security] → step_3_backend (auto, consensus)

Files created:
  - Plan: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
  - Progress: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan_progress.json
  - EPIC copy: .aid-o/04-engine/evidence/{epic_id}/{run_id}/epic_input.md
  - Session: .aid-o/04-engine/sessions/{session_file}

Next: Run `/run-epic {epic_id}` to start execution
      or `/run-step {epic_id} step_1_architect` for manual step execution
```

If no analysis groups were generated, omit the "Analysis groups" section from output.

## Reference Files

- **`skills/planner.md`** — Planner skill: dependency graph, parallel groups, auto-triggers, analysis groups generation
- **`skills/brainstorming.md`** — EPIC Subagent Prompt Template (used for Plan-to-EPIC conversion in Step 0.7)
- `skills/epic-orchestration.md` — Section "2. PLANNING" (plan generation rules, evidence structure)
- `.aid-o/03-config/templates/plan.schema.json` — Plan JSON schema (includes `analysis_groups`)
- `.aid-o/03-config/templates/session-new-feature.md` — Session file template
- `.aid-o/03-config/policies/decision-policies.yaml` — Architecture principles for step ordering
- `.aid-o/03-config/policies/gates.yaml` — Available gates

## Important

- **NEVER modify the original EPIC file** — it is the source of truth, only copy it to evidence
- If `$ARGUMENTS` is empty, list files from BOTH `.aid-o/02-epics/` (marked as `(EPIC)`) AND `.aid-o/01-plans/` (marked as `(Plan)`) for selection
- If a Plan JSON already exists for this EPIC, ask: "Plan already exists (version {N}). Create new version? (Y/N)"
- The plan is a **proposal** — PM reviews it in `/run-epic` (PLAN_REVIEW state) before execution begins
- Budget defaults: `max_llm_cost_usd: 50`, `max_retries_per_gate: 3` (unless EPIC specifies otherwise)
