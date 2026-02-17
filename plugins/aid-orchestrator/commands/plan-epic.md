Parse an EPIC file and generate a Plan JSON + Session file for the Controller state machine.

This command is the entry point to orchestration — it reads an EPIC, analyzes its steps and dependencies, and produces a validated execution plan that `/run-epic` will follow.

## Usage

```
/plan-epic <path-to-epic-file>
```

**Examples:**
```
/plan-epic .aid-o/02-epics/E-20260216-c2d1-user-auth.md
/plan-epic workspace/workflow/epics/active/EPIC-TEST-0001-DUMMY.md
```

## Prerequisites

- `.aid-o/` workspace must exist (run `/aid-init` first)
- EPIC file must follow the epic template format

## Flow

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

Generate a Plan JSON object with these fields:

```json
{
  "epic_id": "{extracted from step 1}",
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
      "forbidden_paths": ["{from EPIC Scope → Forbidden zones}"]
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
       "step_1_architect": "pending",
       "step_2_domain": "pending"
     },
     "current_step": null,
     "gates": {},
     "escalations": []
   }
   ```
5. Copy EPIC to evidence: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/epic_input.md`

### Step 5: Generate Session File

1. Generate session ID: `S-{YYYYMMDD}-{4char-hash}`
2. Use template from `.aid-o/03-config/templates/session-new-feature.md`
3. Fill in frontmatter:
   ```yaml
   id: S-{YYYYMMDD}-{hash}
   type: new-feature
   status: active
   priority: high
   started: {YYYY-MM-DD}
   epic_id: {epic_id}
   epic_session: 1
   orchestrated: true
   ```
4. Generate phases from plan steps — each step becomes a phase in the session file
5. Save to: `.aid-o/04-engine/sessions/S-{YYYYMMDD}-{hash}-{topic}.md`

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
- `skills/epic-orchestration.md` — Section "2. PLANNING" (plan generation rules, evidence structure)
- `.aid-o/03-config/templates/plan.schema.json` — Plan JSON schema (includes `analysis_groups`)
- `.aid-o/03-config/templates/session-new-feature.md` — Session file template
- `.aid-o/03-config/policies/decision-policies.yaml` — Architecture principles for step ordering
- `.aid-o/03-config/policies/gates.yaml` — Available gates

## Important

- **NEVER modify the original EPIC file** — it is the source of truth, only copy it to evidence
- If `$ARGUMENTS` is empty, look for EPICs in `.aid-o/02-epics/` and list them for selection
- If a Plan JSON already exists for this EPIC, ask: "Plan already exists (version {N}). Create new version? (Y/N)"
- The plan is a **proposal** — PM reviews it in `/run-epic` (PLAN_REVIEW state) before execution begins
- Budget defaults: `max_llm_cost_usd: 50`, `max_retries_per_gate: 3` (unless EPIC specifies otherwise)
