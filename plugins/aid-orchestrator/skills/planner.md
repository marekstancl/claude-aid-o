# Planner — Plan Generation from EPIC

**Version:** 0.1.0
**Skill:** planner
**Dependencies:** epic-orchestration

---

## TL;DR

This skill defines how the Planner converts an EPIC specification into a validated Plan JSON.
The Planner builds a dependency graph from EPIC steps, detects parallel groups via topological
sort, applies default ordering rules when the EPIC is underspecified, and auto-generates
`analysis_groups` for multi-perspective review of security-sensitive, high-complexity, or
contract-changing steps.

**Input:** EPIC file (role + objective + depends_on per step)
**Output:** Plan JSON conforming to `plan.schema.json` (steps, dependencies, parallel_groups, analysis_groups, gates, budget)

---

## 1. Dependency Graph Construction

**Input:** EPIC steps (role + objective + depends_on)
**Output:** DAG (directed acyclic graph) of steps

### Algorithm

```
1. PARSE EPIC steps → list of (step_id, role, objective, depends_on[])
   step_id format: step_{N}_{role}, N = sequential (1, 2, 3...)

2. BUILD adjacency list (before → after):
   For each step S, for each dep in S.depends_on: add edge dep → S.step_id

3. VALIDATE:
   a. No cycles — topological sort (Kahn's). If fewer nodes sorted than total → FAIL
      Error: "Circular dependency detected involving steps: {cycle members}"
   b. All references exist — every dep must be a known step_id
      Error: "Step {S.step_id} depends on unknown step: {dep}"
   c. No self-dependencies — step_id NOT in own depends_on
      Error: "Step {S.step_id} depends on itself"

4. OUTPUT dependencies[] for Plan JSON:
   For each edge: { "before": "{id}", "after": "{id}", "reason": "{why}" }
```

### Example — 7-Step EPIC to Dependency Graph

**EPIC steps:**

| Step | Role | Objective | Depends On |
|------|------|-----------|------------|
| 1 | architect | Define API contracts and ADRs | — |
| 2 | domain | Define domain entities and invariants | step_1_architect |
| 3 | backend | Implement REST API endpoints | step_2_domain |
| 4 | frontend | Implement UI components | step_1_architect |
| 5 | qa | Write integration tests | step_3_backend |
| 6 | security | Security review of backend | step_3_backend |
| 7 | docs | Write API documentation | step_3_backend, step_4_frontend |

**Adjacency list (before → after):**

```
step_1_architect → [step_2_domain, step_4_frontend]
step_2_domain    → [step_3_backend]
step_3_backend   → [step_5_qa, step_6_security, step_7_docs]
step_4_frontend  → [step_7_docs]
```

**Resulting `dependencies` array:** 7 edges matching the adjacency list above, each with `before`, `after`, and `reason` fields per plan.schema.json.

---

## 2. Parallel Group Detection

**Input:** dependency graph (adjacency list from Section 1)
**Output:** `parallel_groups[]` array

### Algorithm

```
1. LEVEL ASSIGNMENT via topological sort:
   level(S) = 0 if S.depends_on is empty
   level(S) = max(level(dep) for dep in S.depends_on) + 1

2. GROUP by level → level_groups = { level: [step_ids] }

3. FILTER: for each level with 2+ steps:
   Verify no inter-dependencies (no edge between candidates)
   If verified → parallel group. Single-step levels → no entry.

4. OUTPUT: array of arrays, each inner array has 2+ step IDs
```

### Example — Levels from the 7-Step Dependency Graph

```
Level 0: [step_1_architect]                               ← no deps
Level 1: [step_2_domain, step_4_frontend]                 ← parallel group
Level 2: [step_3_backend]                                 ← sequential
Level 3: [step_5_qa, step_6_security, step_7_docs]        ← parallel group
         (step_7_docs: max(level(step_3), level(step_4)) + 1 = max(2,1)+1 = 3)
```

Result: `parallel_groups: [["step_2_domain","step_4_frontend"], ["step_5_qa","step_6_security","step_7_docs"]]`
Single-step levels (0 and 2) produce no parallel group entries.

---

## 3. Default Ordering Rules

When the EPIC does not fully specify step ordering, apply these defaults based on role priority.

### Priority Table

| Priority | Role | Reason |
|----------|------|--------|
| 1 | architect | Contracts before implementation |
| 2 | domain | Needs contracts, before implementation |
| 3 | backend, frontend | Parallel — both depend on contracts |
| 4 | qa, security, observability | Parallel — all depend on implementation |
| 5 | docs | After implementation |
| 6 | release | Last — needs all gates to pass |

### Application Rules

```
RULE 1: EPIC explicit ordering ALWAYS overrides defaults.
RULE 2: No ordering specified → apply full default chain:
        architect → domain → [backend, frontend] → [qa, security, observability] → docs → release
RULE 3: Partial ordering → keep EPIC deps, fill missing from default table.
        Find unspecified step's role in priority table → add deps to nearest
        higher-priority role(s) present in the EPIC.
RULE 4: Role not in EPIC → skip (not all EPICs use all 9 roles).
RULE 5: Same-priority roles without explicit ordering → parallel group.
```

### Example — Partial Specification

EPIC defines: step_1_architect (no deps), step_2_backend (depends on step_1), step_3_frontend (no deps), step_4_qa (no deps). Defaults fill in: step_1 → step_3 (architect before frontend), step_2 → step_4 and step_3 → step_4 (implementation before QA). Result: backend and frontend become a parallel group.

---

## 4. Analysis Groups Generation (Auto-Trigger Rules)

Analysis groups enable multi-perspective review: multiple agents analyze the SAME step
from different angles, producing a consolidated analysis report.

For each step in the plan, evaluate all trigger rules below. A single step may match
multiple rules, generating multiple analysis groups.

### Rule A: Security-Relevant Step Detection

**Trigger conditions (ANY match):**

```
1. Objective contains ANY of these keywords (case-insensitive):
   auth, password, token, encryption, encrypt, decrypt, secret,
   permission, RBAC, CORS, CSRF, XSS, SQL, injection, certificate,
   OAuth, JWT, session, cookie, hash, salt, credential, ACL, firewall,
   TLS, SSL, HTTPS, sanitize, escape, vulnerability

2. Step role is "backend" AND objective mentions ANY of:
   auth, login, signup, register, database, user, account, password,
   token, session, permission, role, access

3. Step allowed_paths include ANY pattern matching:
   auth/, security/, middleware/auth*, **/auth.*, **/session.*
```

**Action:**

```json
{
  "id": "analysis_{N}_security_review",
  "target": "{step_id}",
  "agents": ["security"],
  "mode": "review",
  "merge_strategy": "union",
  "trigger": "auto"
}
```

### Rule B: High Complexity Detection

**Trigger conditions (ANY match):**

```
1. Step has 5+ entries in its "outputs" array

2. Objective contains ANY of (case-insensitive):
   refactor, migrate, migration, redesign, overhaul, rewrite,
   restructure, rearchitect, decompose, consolidate

3. Step touches 10+ files — determined by:
   Count distinct file patterns in allowed_paths (expand globs):
     "src/api/**/*.py" → count .py files matching the glob
     If glob count >= 10 OR 3+ distinct directory prefixes → trigger
```

**Action:**

```json
{
  "id": "analysis_{N}_architecture_review",
  "target": "{step_id}",
  "agents": ["architect"],
  "mode": "review",
  "merge_strategy": "weighted",
  "trigger": "auto"
}
```

### Rule C: Database Changes Detection

**Trigger conditions (ANY match):**

```
1. Objective contains ANY of (case-insensitive):
   migration, schema, database, table, index, query, SQL, ORM, model,
   entity, column, foreign key, constraint, trigger, stored procedure,
   Alembic, Prisma, Knex, Sequelize, TypeORM, Drizzle, Django ORM

2. Step allowed_paths include ANY pattern matching:
   migrations/, models/, schema/, database/, alembic/, prisma/,
   **/migrations/*, **/models/*, **/entities/*
```

**Action:**

```json
{
  "id": "analysis_{N}_db_validation",
  "target": "{step_id}",
  "agents": ["backend", "security"],
  "mode": "validation",
  "merge_strategy": "consensus",
  "trigger": "auto"
}
```

### Rule D: API Contract Changes

**Trigger conditions (ANY match):**

```
1. Step role is "architect"

2. Step outputs array includes ANY of (case-insensitive):
   OpenAPI, swagger, contract, ADR, API spec, API specification,
   endpoint definition, route definition, schema definition,
   interface definition, protobuf, GraphQL schema, gRPC

3. Objective mentions ANY of:
   API contract, API design, interface, endpoint, route, schema
```

**Action:**

```json
{
  "id": "analysis_{N}_api_contract_validation",
  "target": "{step_id}",
  "agents": ["backend", "frontend"],
  "mode": "validation",
  "merge_strategy": "union",
  "trigger": "auto"
}
```

### Rule E: Manual Override from EPIC

```
1. EPIC MAY explicitly define analysis_groups in its specification.
   Look for a section named "Analysis Groups" or "Multi-Perspective Analysis"
   or an `analysis_groups:` YAML/JSON block in the EPIC.

2. Manual groups from EPIC take PRECEDENCE over auto-generated groups.

3. DEDUPLICATION rules:
   If auto-generated and manual target the SAME step with the SAME agents:
     → Keep the manual group (discard auto)
   If auto-generated and manual target the SAME step with DIFFERENT agents:
     → Keep both (they serve different perspectives)
   If auto-generated targets a step NOT covered by any manual group:
     → Keep the auto group

4. Manual groups use trigger: "manual" in the output.

5. Manual groups may use ANY valid agents, mode, and merge_strategy —
   they are not constrained by the trigger keyword lists above.
```

### Merge Strategies Reference

| Strategy | Behavior | Use When |
|----------|----------|----------|
| `union` | Collect ALL findings from all agents, deduplicate identical items | Broad coverage needed (security review, contract validation) |
| `consensus` | Keep only findings reported by 2+ agents | High confidence needed (DB changes that must be agreed upon) |
| `weighted` | All findings kept, but weight by role expertise (security agent findings on security issues rank higher) | Complex review where some agents have domain authority |

---

## 5. Analysis Group ID Format

```
Format:  "analysis_{N}_{purpose}"
N:       sequential integer (1, 2, 3...), assigned by step order then rule order (A-E)
purpose: slug from trigger rule — A→security_review, B→architecture_review,
         C→db_validation, D→api_contract_validation, E→{custom from EPIC}
```

**Examples:** `analysis_1_api_contract_validation`, `analysis_2_security_review`, `analysis_3_db_validation`, `analysis_4_architecture_review`, `analysis_5_auth_deep_review` (manual).

**Uniqueness:** No duplicate IDs. On collision, append `_2`, `_3`, etc.

---

## 6. Plan JSON Validation (Extended)

After assembling the Plan JSON, run ALL validations below. If any fails, fix the plan
and re-validate. Never output an invalid plan.

### Existing Validations (from epic-orchestration.md)

| Rule | Check |
|------|-------|
| V-01 | All step.id values unique |
| V-02 | All step.role in valid enum (9 roles) |
| V-03 | All dependency before/after reference existing step IDs |
| V-04 | All parallel_groups reference existing step IDs |
| V-05 | No circular dependencies (topological sort succeeds) |
| V-06 | Gates in valid enum (tests_pass, lint_pass, security_scan_pass, docs_updated) |
| V-07 | Budget max_llm_cost_usd >= 0 |
| V-08 | Budget max_retries_per_gate in [0, 5] |

### New Validations for analysis_groups

| Rule | Check | Error Template |
|------|-------|----------------|
| V-09 | `.target` references existing step ID | "Analysis group {id} targets unknown step: {target}" |
| V-10 | `.agents` values are valid role enum | "Analysis group {id} has invalid agent role: {role}" |
| V-11 | `.merge_strategy` is `union\|consensus\|weighted` | "Analysis group {id} has invalid merge_strategy: {value}" |
| V-12 | `.mode` is `review\|audit\|validation` | "Analysis group {id} has invalid mode: {value}" |
| V-13 | `.trigger` is `auto\|manual` | "Analysis group {id} has invalid trigger: {value}" |
| V-14 | No duplicate analysis_group IDs | "Duplicate analysis_group ID: {id}" |
| V-15 | Agents must NOT include target step's own role (no self-review) | "Analysis group {id} includes self-review: agent '{role}' same as target {target}" |
| V-16 | `analysis_groups` is OPTIONAL (missing/empty = valid, treat as `[]`) | — |
| V-17 | Required fields: id, target, agents, mode, merge_strategy, trigger | "Analysis group at index {i} missing required field: {field}" |
| V-18 | `.agents` has at least 1 entry | "Analysis group {id} has empty agents list" |

### Validation Order

```
Run validations in order V-01 through V-18.
Stop on FIRST failure — report the error, fix, re-validate from V-01.
Rationale: later validations may depend on earlier ones passing
(e.g., V-09 depends on V-01 having established valid step IDs).
```

---

## 7. Complete Plan Generation Flow

This is the master procedure the Planner follows when `/plan-epic` is invoked.

```
 1. RECEIVE EPIC file → validate sections (Goal, Scope, Constraints, DoD, AC) → extract epic_id
 2. PARSE steps → extract (role, objective, depends_on[], outputs[], paths, constraints) → assign step_ids
 3. RESOLVE ordering:
      explicit deps → use as-is | partial → fill from defaults (Section 3) | none → full defaults
 4. BUILD dependency graph → adjacency list → dependencies[] with reasons (Section 1)
 5. VALIDATE graph → no cycles, all refs exist, no self-deps → FAIL if invalid
 6. DETECT parallel groups → level assignment → group same-level → filter 2+ (Section 2)
 7. GENERATE analysis_groups:
      a. Apply Rules A-D to each step → auto entries
      b. Parse EPIC manual analysis_groups → manual entries
      c. Merge: manual wins on conflict, both kept if different agents, auto kept if uncovered
      d. Assign sequential IDs (Section 5)
      e. Apply V-15: remove self-review agents, drop empty groups
 8. ASSEMBLE Plan JSON:
      { epic_id, version: 1, created_at, steps, dependencies,
        parallel_groups, analysis_groups, gates, budget }
 9. VALIDATE → V-01 through V-18 → fix + re-validate on failure (max 3 attempts → escalation)
10. OUTPUT → save plan.json + plan_progress.json + epic_input.md to evidence dir → present summary
```

### Example — Auto-Generated analysis_groups for the 7-Step EPIC

Using the EPIC from Sections 1-2, the Planner auto-generates 4 groups:

| ID | Target | Rule | Trigger Reason | Agents | Mode | Strategy |
|----|--------|------|----------------|--------|------|----------|
| `analysis_1_api_contract_validation` | step_1_architect | D | architect role + outputs include OpenAPI | backend, frontend | validation | union |
| `analysis_2_security_review` | step_3_backend | A | objective mentions "auth" + "database" | security | review | union |
| `analysis_3_db_validation` | step_3_backend | C | objective mentions "database", paths include migrations/ | architect, security | validation | consensus |
| `analysis_4_architecture_review` | step_3_backend | B | step has 5 outputs | architect | review | weighted |

Note: Rule A did NOT fire for step_6_security because V-15 prevents self-review (security reviewing security).

---

## MUST Rules

1. **ALWAYS validate the dependency graph** before generating parallel groups or analysis groups
2. **ALWAYS apply default ordering** when EPIC does not fully specify dependencies
3. **EPIC explicit ordering ALWAYS overrides defaults** — never contradict the EPIC
4. **ALWAYS run all trigger rules** on every step — a step may match multiple rules
5. **MANUAL analysis groups ALWAYS win** over auto-generated on conflict
6. **NEVER allow self-review** — analysis group agents must not include the target step's role
7. **NEVER output an invalid Plan JSON** — validate before output, fix and re-validate on failure
8. **ALWAYS include a reason** for every dependency edge
9. **ALWAYS assign sequential analysis group IDs** — no gaps, no duplicates
10. **ALWAYS preserve EPIC-defined analysis groups** even if no auto-trigger rules match

---

## Reference Files

- `commands/plan-epic.md` -- command that invokes this skill
- `skills/epic-orchestration.md` -- PLANNING state references this skill (Section 2)
- `defaults/templates/plan.schema.json` -- Plan JSON schema (includes analysis_groups)
- `workspace/workflow/plans/P-20260216-b3a1-aid-v2-workspace-agents-memory.md` -- Plan D-011 (analysis_groups design decision)

---

**Version:** 0.1.0
**Last Updated:** 2026-02-17
