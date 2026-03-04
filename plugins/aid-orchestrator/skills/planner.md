# Planner — EPIC to Plan JSON

**Skill:** planner
**Dependencies:** epic-orchestration

---

## Purpose

The planner converts an EPIC specification into a `plan.json` execution artifact.
All deterministic computation is performed by `aid-epic-to-json.sh`. This skill
documents the contract — inputs, outputs, and the two decisions the LLM must make:
dependency graph validation and run splitting.

---

## Script Contract

Invoked from `pipeline.md` PRE-FLIGHT (§2):

```bash
aid-epic-to-json.sh <epic_file> <output_dir>
```

**Writes:**
- `plan.json` — step list with waves, dependencies, parallel_groups
- `state.yaml` — execution state tracker (all steps pending)
- `execution.yaml` — gates configuration derived from `gates.yaml`

**Exits non-zero on:**
- Circular dependencies (Kahn's sort detects cycle)
- Unknown step IDs referenced in `depends_on`
- No steps found in EPIC file
- Missing required EPIC sections (Goal, Scope, DoD)

The LLM does NOT generate plan.json inline. It invokes the script and reviews output.

---

## Input: EPIC Format

```markdown
## Steps

### step_1_architect
role: architect
objective: Define API contracts and ADRs
depends_on: []

### step_2_domain
role: domain
objective: Define domain entities and invariants
depends_on: [step_1_architect]

### step_3_backend
role: backend
objective: Implement REST API endpoints
depends_on: [step_2_domain]

### step_4_frontend
role: frontend
objective: Implement UI components
depends_on: [step_1_architect]

### step_5_qa
role: qa
objective: Write integration tests
depends_on: [step_3_backend]

### step_6_security
role: security
objective: Security review of backend
depends_on: [step_3_backend]

### step_7_docs
role: docs
objective: Write API documentation
depends_on: [step_3_backend, step_4_frontend]
```

**Step ID format:** `step_{N}_{role}` where N is sequential (1, 2, 3...)

---

## Output: plan.json

Full schema: `defaults/templates/plan.schema.json`

Abbreviated structure:

```json
{
  "epic_id": "EPIC-001",
  "version": 1,
  "created_at": "2026-03-03T00:00:00Z",
  "steps": [
    {
      "id": "step_1_architect",
      "role": "architect",
      "objective": "Define API contracts and ADRs",
      "depends_on": [],
      "allowed_paths": ["contracts/", "docs/adr/"],
      "model": "opus"
    }
  ],
  "dependencies": [
    { "before": "step_1_architect", "after": "step_2_domain", "reason": "domain needs contracts" }
  ],
  "waves": [
    ["step_1_architect"],
    ["step_2_domain", "step_4_frontend"],
    ["step_3_backend"],
    ["step_5_qa", "step_6_security", "step_7_docs"]
  ],
  "parallel_groups": [
    ["step_2_domain", "step_4_frontend"],
    ["step_5_qa", "step_6_security", "step_7_docs"]
  ],
  "gates": ["tests_pass", "lint_pass", "security_scan_pass", "docs_updated"]
}
```

**Model field:** assigned from `defaults/policies/role-cards.md` role tier, not dispatch-config.yaml.

---

## Dependency Graph Construction

The script builds a DAG (directed acyclic graph) from EPIC step `depends_on` fields.
Understanding this is necessary for the LLM to validate script output and catch
errors the script cannot detect from syntax alone (e.g., logically wrong dependencies).

**Algorithm (implemented in `aid-epic-to-json.sh`):**

```
1. PARSE EPIC steps → list of (step_id, role, objective, depends_on[])
2. BUILD adjacency list: for each dep in depends_on → add edge dep → step_id
3. VALIDATE:
   a. No cycles: Kahn's topological sort; cycle if fewer nodes sorted than total
   b. All references exist: every dep must be a known step_id
   c. No self-dependencies: step_id not in its own depends_on
4. ASSIGN levels: level(S) = 0 if depends_on empty;
                             max(level(dep)+1 for dep in depends_on) otherwise
5. ASSEMBLE waves: group same-level steps → split waves with 5+ into sub-waves of 4
6. OUTPUT dependencies[] and waves[] into plan.json
```

**From the 7-step EPIC example above:**

```
Level 0: [step_1_architect]                         → wave 0
Level 1: [step_2_domain, step_4_frontend]           → wave 1 (parallel)
Level 2: [step_3_backend]                           → wave 2
Level 3: [step_5_qa, step_6_security, step_7_docs]  → wave 3 (parallel)
```

---

## Parallel Group Detection

The script assigns steps to the same wave when they share the same dependency level.
Steps in the same wave run in parallel. The LLM must verify wave assignment is
sensible when reviewing plan.json — parallel steps must not write the same files.

**File conflict resolution:** if two same-level steps have overlapping `allowed_paths`,
the script places them in sequential sub-waves. The LLM should flag this in the
PLAN_REVIEW summary so the PM knows parallelism was reduced.

---

## Run Split Decision (LLM makes this call)

The script does not split runs — this is an LLM judgment call presented to the PM
before PRE-FLIGHT starts.

**Heuristic:**

```
IF plan.json has > 7 steps:
  Run 1: steps at level 0 + level 1 (waves 0-1) = foundation work
  Run 2: steps at level 2+ = implementation + verification
  SPLIT BOUNDARY: after the last wave where cumulative step count crosses 6

IF plan.json has <= 7 steps:
  Single run (no split needed)
```

**Split boundary rule:** Never split inside a wave. A wave with 2+ parallel steps
must stay in the same run.

**Present to PM before PRE-FLIGHT:**

```
Plan has 12 steps across 5 waves.
Proposed split into 2 runs:
  Run 1 (waves 0-2, 6 steps): architect → domain+frontend → backend
  Run 2 (waves 3-4, 6 steps): qa+security+docs → release
Proceed with 2 runs? (Y/N — default Y)
```

If PM declines: run all steps as a single run.

---

## Error Handling

| Script exit condition | LLM action |
|---|---|
| Circular dependency detected | Report cycle members to PM; ask to fix EPIC deps |
| Unknown step ID in depends_on | Show the bad reference; ask PM to correct EPIC |
| No steps found in EPIC | Check EPIC formatting — Steps section may be missing |
| Missing required EPIC section | Show which section is absent; do not proceed to plan |
| Non-zero exit, unknown reason | Show raw stderr; ask PM whether to retry or debug |

---

## Reference Files

- `commands/aid-plan-epic.md` — command that invokes this skill; orchestrates the script pipeline
- `scripts/aid-epic-to-json.sh` — script that generates plan.json and state.yaml
- `scripts/aid-auto-pipeline.sh` — master orchestrator (Plan → EPIC → plan.json → run.md → queue)
- `defaults/templates/plan.schema.json` — full plan.json JSON schema
- `skills/epic-orchestration.md` — PLANNING state references this skill (§2)
- `defaults/policies/role-cards.md` — model tier per role (architect=opus, qa=sonnet, etc.)

---

**Last Updated:** 2026-03-03
