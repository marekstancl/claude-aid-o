# Planner — Plan Generation from EPIC

**Skill:** planner
**Dependencies:** epic-orchestration

---

## TL;DR

This skill defines how the Planner converts an EPIC specification into a validated Plan JSON.
The Planner builds a dependency graph from EPIC steps, detects parallel groups via topological
sort, applies default ordering rules when the EPIC is underspecified, applies granularity
heuristics (G1: layer splitting, G2: module splitting) to decompose coarse-grained steps,
and auto-generates `analysis_groups` for multi-perspective review of security-sensitive,
high-complexity, or contract-changing steps.

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

## 2. Wave Assembly

**Input:** dependency graph (adjacency list from Section 1)
**Output:** `waves[]` array (ordered list of step groups, each wave runs in parallel)

### Algorithm

```
1. LEVEL ASSIGNMENT via topological sort (unchanged):
   level(S) = 0 if S.depends_on is empty
   level(S) = max(level(dep) for dep in S.depends_on) + 1

2. GROUP by level → level_groups = { level: [step_ids] }

3. FILE CONFLICT CHECK:
   For each level, verify no two steps share allowed_paths.
   IF overlap detected:
     → separate conflicting steps into sequential sub-waves
     → log: "Wave split due to file conflict: {step_A} and {step_B} share {paths}"

4. WAVE FORMATION:
   For each level with 1+ steps (after conflict resolution):
     IF level has <= 4 steps:
       → single wave containing all steps
     IF level has 5+ steps:
       → split into sub-waves of max 4 steps each
       → priority: keep same-domain steps together within sub-wave
       → sub-wave order: lower step numbers first

5. OUTPUT: waves[] array (each wave = array of step_ids)
   waves[0] = [step_1_architect]
   waves[1] = [step_2_domain, step_3a_backend]
   waves[2] = [step_3b_backend, step_4_frontend]  ← cross-domain parallel
   waves[3] = [step_5_qa, step_6_security, step_7_docs]

6. BACKWARD COMPATIBILITY:
   parallel_groups = waves with 2+ steps (for plan.json schema)
   Single-step waves produce no parallel_groups entry.

7. POST_WAVE_WIRING_CHECK (for each wave with 2+ steps):
   → see Section 2a below
```

### Example — Waves from the 7-Step Dependency Graph

```
Level 0: [step_1_architect]                    → wave 0 (1 step)
Level 1: [step_2_domain, step_4_frontend]      → wave 1 (2 steps — parallel)
Level 2: [step_3_backend]                      → wave 2 (1 step)
Level 3: [step_5_qa, step_6_security, step_7_docs] → wave 3 (3 steps — parallel)

Result: waves = [[step_1], [step_2, step_4], [step_3], [step_5, step_6, step_7]]
Parallel groups: [[step_2, step_4], [step_5, step_6, step_7]]
```

---

## 2a. POST_WAVE_WIRING_CHECK

After assembling each parallel wave (group of steps with the same dependency set that
can run concurrently), check for shared file conflicts:

### Algorithm

```
For each wave W in waves[] where len(W) >= 2:

  1. COLLECT allowed_paths from all steps in W:
     all_paths = { step_id: step.allowed_paths for step in W }

  2. FIND shared files — paths appearing in 2+ steps' allowed_paths:
     shared = []
     For each path P across all_paths values:
       contributors = [step_id for step_id, paths in all_paths if P in paths]
       IF len(contributors) >= 2:
         shared.append({ "path": P, "contributors": contributors })

  3. IF shared is non-empty:
     a. Auto-generate a wiring step inserted immediately after the parallel wave:
        {
          "id": "step_{N}_wiring",
          "role": "backend",
          "objective": "Wire parallel outputs: integrate shared files modified by parallel steps",
          "wiring": true,
          "wiring_context": {
            "shared_files": ["{path}" for each shared entry],
            "contributing_steps": [unique step_ids from all shared contributors],
            "expected_actions": [
              "Merge changes from all contributing steps",
              "Resolve any conflicts in shared files",
              "Ensure consistent state across integrated files"
            ]
          },
          "inputs": ["Outputs from {contributing_steps}"],
          "outputs": ["Integrated shared files with consistent state"],
          "constraints": [
            "Integrate, don't rewrite from scratch",
            "Run type-check/lint after integration",
            "Preserve all changes from contributing steps"
          ],
          "allowed_paths": ["{shared_files}"],
          "forbidden_paths": [],
          "acceptance_criteria": [
            "All shared files are internally consistent",
            "Changes from all contributing steps are preserved",
            "Type-check/lint passes after integration"
          ]
        }

     b. Add dependencies: wiring step depends on ALL steps in the wave.
        For each step_id in W:
          dependencies.append({ "before": step_id, "after": "step_{N}_wiring",
                                "reason": "Wiring step integrates parallel outputs" })

     c. Re-wire downstream dependencies: any step that originally depended on
        a wave step now depends on the wiring step instead.
        For each dep in dependencies where dep.before in W and dep.after not in W:
          dep.before = "step_{N}_wiring"

     d. Log: "Wiring step generated for wave {wave_index}: {len(shared)} shared
        files across {len(contributing_steps)} steps"

  4. IF shared is empty:
     No wiring step needed. Continue to next wave.
```

### Wiring Step ID Assignment

The wiring step receives the next sequential step number after the last step in the
wave. Example: if wave contains `step_2_backend` and `step_3_frontend`, the wiring
step is `step_4_wiring`. Subsequent step IDs are NOT renumbered — the wiring step
is inserted with a new ID and the dependency graph is updated accordingly.

### Example — Wiring Step for Shared Files

```
Wave 1: [step_2_backend, step_3_frontend]
  step_2_backend.allowed_paths:  ["src/api/", "src/shared/types.ts"]
  step_3_frontend.allowed_paths: ["src/ui/", "src/shared/types.ts"]

  Shared files: ["src/shared/types.ts"]
  → Generate step_4_wiring:
    wiring: true
    wiring_context:
      shared_files: ["src/shared/types.ts"]
      contributing_steps: ["step_2_backend", "step_3_frontend"]
      expected_actions: ["Merge type definitions from both steps", "Resolve any conflicts", "Ensure consistent state"]
    allowed_paths: ["src/shared/types.ts"]

  Dependencies added:
    step_2_backend → step_4_wiring (wiring integrates parallel outputs)
    step_3_frontend → step_4_wiring (wiring integrates parallel outputs)

  Downstream re-wiring:
    step_5_qa originally depended on step_2_backend → now depends on step_4_wiring
    step_6_docs originally depended on step_3_frontend → now depends on step_4_wiring
```

---

## 2b. Step Decomposition — Layer-Based Splitting

Step Decomposition runs BEFORE dependency resolution and wave assembly.
It converts coarse EPIC steps into finer-grained sub-steps when this
enables new parallelism opportunities.

### EPIC Type Guard

Layer-based decomposition applies to DEVELOPMENT EPICs only.
Detect EPIC type from typed artifacts (see EPIC template):

- **Development**: artifacts contain `endpoint:`, `model:`, `component:`
  → apply full layer-based decomposition below
- **Documentation**: artifacts are all `doc:`
  → decompose by TOPIC instead of layer (split "write all docs" into
    "API docs", "user guide", "architecture docs" if they have different deps)
- **Infrastructure/Config**: artifacts are `config:` or devops-oriented
  → decompose by SCOPE (e.g., "CI pipeline" vs "deployment config" vs "monitoring")
- **Mixed**: combination of types
  → apply layer decomposition to dev steps, topic/scope to non-dev steps

### Algorithm (Development EPICs)

```
For each step S in the parsed EPIC:
  1. EVALUATE split criteria (ALL must be true):
     a. S spans 2+ distinct layers (data, schema, API, service, UI, test, config)
     b. S produces 5+ files (estimated from objective + allowed_paths)
     c. Splitting enables at least 1 new parallel pairing with another domain
     d. Each resulting sub-step would produce 3+ files

  2. IF all criteria met → DECOMPOSE:
     a. Identify layers present in S.objective and S.outputs
     b. Create sub-steps following Layer Hierarchy (below)
     c. Sub-step ID format: step_{N}{letter}_{role}
        (e.g., step_3a_backend, step_3b_backend, step_3c_backend)
     d. Sub-step dependencies:
        - First sub-step inherits ALL of original step's depends_on
        - Each subsequent sub-step depends on its predecessor
        - Steps that depended on the ORIGINAL now depend on the LAST sub-step
     e. Sub-step allowed_paths: subset of original, scoped to layer

  3. IF criteria not met → keep as single step (no change)
```

### Layer Hierarchy (earlier layers first)

| Priority | Layer | Typical Files |
|----------|-------|---------------|
| 1 | data | models, migrations, database setup, ORM entities |
| 2 | schema | validation schemas, DTOs, type definitions, Pydantic/Zod |
| 3 | API | routers, controllers, endpoints, middleware |
| 4 | service | business logic, utilities, helpers, domain services |
| 5 | UI | components, pages, layouts, styles |
| 6 | test | unit tests, integration tests (per-layer) |
| 7 | config | configuration, deployment, CI, environment |

Adjacent layers (e.g., data+schema) CAN be merged into one sub-step
if they're tightly coupled and splitting them would create trivially
small steps (< 3 files each).

### Example — Backend CRUD decomposition

```
BEFORE (1 monolithic step):
  step_3_backend: "Implement REST API with models, schemas, routers, tests"
  depends_on: [step_2_domain]
  → Frontend (step_4) must wait for ALL of this to finish

AFTER (3 focused sub-steps):
  step_3a_backend: "Database models + Pydantic schemas" (data + schema layers)
    depends_on: [step_2_domain]
    outputs: models/*.py, schemas/*.py
  step_3b_backend: "API routers + business logic" (API + service layers)
    depends_on: [step_3a_backend]
    outputs: routers/*.py, services/*.py
  step_3c_backend: "Backend unit + integration tests" (test layer)
    depends_on: [step_3a_backend, step_3b_backend]
    outputs: tests/api/*.py, tests/models/*.py

  step_4_frontend: "React components + pages"
    depends_on: [step_1_architect]  ← NOTE: depends on architect, NOT backend!
    → Frontend starts AS SOON AS architect finishes, parallel with backend

Net effect: frontend starts 1-2 waves earlier.
```

### When NOT to decompose

- Step produces fewer than 5 files total → too small to split meaningfully
- All files are tightly coupled (one endpoint = model + schema + router + test) → splitting breaks cohesion
- Splitting would create more than 4 sub-steps for a single role → diminishing returns
- The EPIC already has 15+ steps → more steps adds overhead, not speed
- Step is a leaf node with no downstream dependents → splitting doesn't enable new parallelism
- EPIC type is documentation/infrastructure and step doesn't span multiple independent topics → topic-based split not applicable

### Step Granularity Heuristics

The following named heuristics help the Planner identify coarse-grained steps that
should be split. They run as part of Step Decomposition (the algorithm above) and
provide structured trigger conditions. Heuristics are **advisory** -- the Planner
MAY override a heuristic if splitting would be counterproductive (e.g., breaking
cohesion, exceeding 4 sub-steps, or adding overhead to a small EPIC). When overriding,
the Planner MUST log the override reason in plan metadata.

```
HEURISTIC G1 — Layer Splitting
  TRIGGER: Single step modifies files across 3+ architectural layers
           (layers: data, schema, API, service, UI, test, config — see Layer Hierarchy above)
  ACTION:  Split into one step per layer group, with dependencies following
           the natural data flow:
             data → schema → API/service → UI → test → config
           Adjacent layers MAY be merged when tightly coupled (< 3 files each).
  DEPENDENCIES:
           First sub-step inherits the original step's depends_on.
           Each subsequent sub-step depends on its predecessor.
           Downstream steps that depended on the original now depend on the LAST sub-step.
  OVERRIDE CONDITIONS (skip split if ANY is true):
           - Total estimated files < 5 (step too small to benefit)
           - Split would produce > 4 sub-steps (diminishing returns)
           - All files are tightly coupled around a single feature slice
             (one endpoint = model + schema + router + test)
           - EPIC already has 15+ steps (overhead exceeds parallelism gain)
  LOG:     "G1 applied to {step_id}: split into {N} sub-steps across layers {layer_list}"
           OR "G1 override for {step_id}: {reason}"
```

**Example — G1 Layer Splitting (before/after):**

```
BEFORE (1 coarse step touching 4 layers):
  step_3_backend: "Implement user registration with models, validation,
                   service logic, and API endpoint"
    depends_on: [step_2_domain]
    allowed_paths: [src/models/, src/schemas/, src/services/, src/routers/]
    → Touches: data, schema, service, API (4 layers) → G1 triggers

AFTER (3 focused sub-steps, adjacent layers merged):
  step_3a_backend: "Define user model and migration"
    depends_on: [step_2_domain]
    allowed_paths: [src/models/]
    layers: data

  step_3b_backend: "Implement registration service and validation schemas"
    depends_on: [step_3a_backend]
    allowed_paths: [src/services/, src/schemas/]
    layers: service + schema (merged — tightly coupled validation logic)

  step_3c_backend: "Create registration endpoint and route"
    depends_on: [step_3b_backend]
    allowed_paths: [src/routers/]
    layers: API

  Dependency chain: step_2_domain → step_3a → step_3b → step_3c
  Net effect: downstream steps needing only data models can depend on step_3a
  instead of waiting for the entire backend implementation.
```

```
HEURISTIC G2 — Module Splitting
  TRIGGER: Single step modifies files across 3+ independent modules
           (modules = bounded functional areas with separate directories or namespaces,
            e.g., auth/, billing/, notifications/, inventory/, reporting/)
  DETECTION: Count distinct top-level module directories in step's allowed_paths
             and objective references. Modules are "independent" when they:
             a. Have separate directory trees (src/auth/ vs src/billing/)
             b. Do not share mutable state or database tables
             c. Communicate only through well-defined interfaces (events, APIs)
  ACTION:  Split into one step per module. Assign dependencies:
           - If modules are independent (no shared state) → sub-steps are PARALLEL
             (all inherit original step's depends_on, none depends on siblings)
           - If modules have ordering constraints (e.g., auth before billing
             because billing needs user context) → chain sub-steps accordingly
  DEPENDENCIES:
           Independent modules: all sub-steps share the original depends_on.
           Dependent modules: chain in natural order, first inherits original depends_on.
           Downstream steps that depended on the original now depend on ALL sub-steps
           (or on a wiring step if sub-steps produce shared outputs).
  OVERRIDE CONDITIONS (skip split if ANY is true):
           - Modules share significant mutable state (splitting would require
             constant cross-step coordination)
           - Step implements a cross-cutting concern that spans modules by nature
             (e.g., "add logging to all modules", "apply rate limiting everywhere")
           - Total estimated files < 5 (step too small to benefit)
           - Fewer than 3 truly independent modules (2 modules rarely justifies split)
  LOG:     "G2 applied to {step_id}: split into {N} module sub-steps {module_list},
            parallelized: {yes|no}"
           OR "G2 override for {step_id}: {reason}"
```

**Example — G2 Module Splitting (before/after):**

```
BEFORE (1 coarse step touching 3 independent modules):
  step_4_backend: "Implement webhook handlers for auth, billing, and notifications"
    depends_on: [step_3_backend]
    allowed_paths: [src/auth/, src/billing/, src/notifications/, src/webhooks/]
    → Touches: auth, billing, notifications (3 modules) → G2 triggers
    → Modules are independent: separate directories, no shared state

AFTER (3 parallel module sub-steps):
  step_4a_backend: "Implement auth webhook handler"
    depends_on: [step_3_backend]
    allowed_paths: [src/auth/, src/webhooks/auth.py]

  step_4b_backend: "Implement billing webhook handler"
    depends_on: [step_3_backend]
    allowed_paths: [src/billing/, src/webhooks/billing.py]

  step_4c_backend: "Implement notifications webhook handler"
    depends_on: [step_3_backend]
    allowed_paths: [src/notifications/, src/webhooks/notifications.py]

  All three sub-steps share the same depends_on → they form a PARALLEL GROUP.
  Wave assembly places them in the same wave: [step_4a ‖ step_4b ‖ step_4c]
  Net effect: 3x parallel execution instead of sequential within one agent.
```

**Example — G2 with dependent modules (sequential):**

```
BEFORE:
  step_5_backend: "Implement order processing across auth, inventory, and billing"
    depends_on: [step_4_backend]
    allowed_paths: [src/auth/, src/inventory/, src/billing/]
    → Touches 3 modules, BUT billing depends on inventory (stock check before charge)

AFTER (3 sub-steps, partially chained):
  step_5a_backend: "Implement auth context for order flow"
    depends_on: [step_4_backend]
    allowed_paths: [src/auth/]

  step_5b_backend: "Implement inventory reservation"
    depends_on: [step_4_backend]      ← parallel with step_5a (independent)
    allowed_paths: [src/inventory/]

  step_5c_backend: "Implement billing charge after inventory check"
    depends_on: [step_5b_backend]     ← sequential after inventory (shared state)
    allowed_paths: [src/billing/]

  Wave assembly: [step_5a ‖ step_5b] → [step_5c]
  Net effect: auth and inventory parallelize; billing waits for inventory only.
```

### Heuristic Interaction Rules

```
1. G1 and G2 are MUTUALLY EXCLUSIVE per step:
   - If a step triggers BOTH G1 (3+ layers) and G2 (3+ modules), apply G2 FIRST.
   - Then evaluate each G2 sub-step for G1 applicability (a module sub-step
     may still span multiple layers within that module).
   - Rationale: module boundaries are coarser and produce more parallelism
     than layer boundaries within a single module.

2. Heuristic evaluation runs ONCE per step during Step Decomposition (Section 2b,
   step 2.2 in the master procedure). Sub-steps produced by G2 are re-evaluated
   for G1 in the same pass. No recursive re-evaluation beyond one level.

3. Total sub-steps from G1 + G2 combined MUST NOT exceed 6 for a single original
   step. If combined splitting would exceed 6, prefer the heuristic that produces
   more parallelism and skip the other.
```

---

## 2c. Critical Path Analysis (opt-in, 7+ steps)

Critical path analysis is activated when total_steps >= 7. For smaller EPICs,
the overhead of analysis exceeds the benefit.

### Step 1: Compute Critical Path

Critical path = longest chain through DAG measured by step count.

```
Algorithm:
  1. For each step S in topological order:
     dist(S) = 0 if S.depends_on is empty
     dist(S) = max(dist(dep) + 1 for dep in S.depends_on)
  2. critical_path_length = max(dist(S) for all S)
  3. Backtrack from maximum → identify all steps on critical path
  4. critical_path_ratio = critical_path_length / total_steps
```

### Step 2: Dependency Relaxation (if ratio > 0.6)

If more than 60% of steps are on the critical path, the DAG is too sequential.
Apply relaxation rules to shorten it.

For each dependency edge ON the critical path, evaluate these rules.

NOTE: Rules R1-R5 are DEVELOPMENT-SPECIFIC. For non-dev EPICs (docs, infra),
CPA still computes critical path and ratio, but relaxation rules don't apply
(no domain-specific heuristics). For mixed EPICs, apply rules only to dev steps.

#### Development Relaxation Rules

```
RULE R1: "Frontend doesn't need Domain"
  IF: step_{N}_frontend depends on step_{M}_domain
  AND: step_{M}_domain produces only data models (no API contracts)
  AND: step_{1}_architect produced API contracts
  THEN: relax → frontend depends on architect instead of domain
  REASON: Frontend builds against API contracts, not domain internals

RULE R2: "QA can start with partial implementation"
  IF: step_{N}_qa depends on ALL implementation steps
  AND: implementation steps are in different domains (backend vs frontend)
  THEN: split QA into domain-specific sub-steps:
    step_{N}a_qa depends on backend steps only
    step_{N}b_qa depends on frontend steps only
  REASON: Backend tests don't need frontend code and vice versa

RULE R3: "Docs can start after architect"
  IF: step_{N}_docs depends on all implementation steps
  AND: architect step produced contracts/ADRs
  THEN: split docs:
    step_{N}a_docs "API documentation" depends on architect (start early!)
    step_{N}b_docs "Usage guides" depends on implementation (late)
  REASON: API docs come from contracts, not from reading implementation

RULE R4: "Security review of auth can run early"
  IF: step_{N}_security depends on ALL backend steps
  AND: one backend step is specifically auth/security-focused
  THEN: security depends on auth step only (not all backend)
  REASON: Security review of auth doesn't need CRUD endpoints

RULE R5: "Layer split enables cross-domain parallel"
  IF: step on critical path spans 2+ layers
  AND: splitting would allow another domain to start earlier
  THEN: recommend decomposition (Section 2b)
  NOTE: Bridge between decomposition and relaxation — if decomposition
  was skipped for this step, reconsider here.
```

### Step 3: Safety Net

```
EVERY relaxation MUST be:
  a. LOGGED in plan metadata:
     {"relaxation": "R1", "original_edge": "domain→frontend",
      "relaxed_to": "architect→frontend",
      "reason": "frontend needs API contracts only, not domain models"}
  b. VISIBLE in PLAN_REVIEW output:
     "Relaxed: frontend starts after architect (not after domain)
      — needs API contracts only"
  c. REJECTABLE by PM at PLAN_REVIEW — PM can reject individual relaxations
  d. RECOVERABLE at runtime — if agent fails due to missing dependency
     (detected at PHASE_CHECK):
     → Controller re-dispatches with original (non-relaxed) dependency
     → Log: "Relaxation R1 failed for step_X — re-run with full deps"
     → This counts against the step's retry limit (not a new mechanism)
```

### Step 4: Re-optimization

```
After applying relaxations:
  1. Re-build DAG with relaxed edges
  2. Re-level (topological sort)
  3. Re-assemble waves (Section 2)
  4. Verify: new critical_path_ratio < original ratio
     IF NOT improved: revert ALL relaxations (they didn't help)
  5. Log delta:
     "Critical path reduced from {old} to {new} steps ({percent}% shorter)"
     "Relaxations applied: {count} ({rule_ids})"
```

---

## 3. Default Ordering Rules

When the EPIC does not fully specify step ordering, apply these defaults based on role priority.

### Priority Table

| Priority | Role | Reason |
|----------|------|--------|
| 1 | architect | Contracts before implementation |
| 1.5 | docker (conditional) | Infrastructure before implementation; only when docker_recommended (Section 7.4) |
| 2 | domain | Needs contracts, before implementation; parallel with docker when both present |
| 3 | backend, frontend | Parallel — both depend on contracts (and docker step when present) |
| 4 | qa, security, observability | Parallel — all depend on implementation |
| 5 | docs | After implementation |
| 6 | release | Last — needs all gates to pass |

### Application Rules

```
RULE 1: EPIC explicit ordering ALWAYS overrides defaults.
RULE 2: No ordering specified → apply full default chain:
        architect → [docker, domain] → [backend, frontend] → [qa, security, observability] → docs → release
        (docker step only present when docker_recommended == true per Section 7.4)
RULE 3: Partial ordering → keep EPIC deps, fill missing from default table.
        Find unspecified step's role in priority table → add deps to nearest
        higher-priority role(s) present in the EPIC.
RULE 4: Role not in EPIC → skip (not all EPICs use all 9 roles).
        Docker step is only present when injected by Section 7.4 rules.
RULE 5: Same-priority roles without explicit ordering → parallel group.
        Docker and domain run in parallel when both are present (both depend on architect).
RULE 6: EPIC explicit backend→frontend (or frontend→backend) ordering is PRESERVED.
        If the EPIC author wrote depends_on making one sequential after the other,
        the Planner MUST NOT override this into a parallel group. Rule 1 applies.
```

### Parallel Group Assignment Rules

After the dependency graph is resolved and levels are assigned (Section 2), the Planner
applies these rules to determine which steps run in the same wave. These rules codify the
parallelism strategy that the Wave Assembly algorithm (Section 2) uses during level grouping.

```
PARALLEL RULE 1: Foundation steps run first (wave 0 / sequential).
  architect and domain steps MUST complete before implementation steps begin.
  Architect is always wave 0. Domain is wave 1 (or wave 0 alongside architect
  only if it has no dependency on architect — rare).

PARALLEL RULE 2: After architect+domain complete, backend and frontend steps
  CAN be parallelized into the same wave.
  CONDITIONS (ALL must be true):
    a. Both steps' dependencies are satisfied (architect and/or domain complete)
    b. Their allowed_paths DO NOT overlap (no shared files)
    c. The EPIC does not specify explicit ordering between them (Rule 1 / Rule 6)
  IF conditions met → assign to same wave (parallel group).
  IF allowed_paths overlap → assign sequentially; the step with more
    dependencies on prior outputs goes first. Log:
    "Backend/frontend sequential due to shared paths: {overlapping_paths}"
  IF EPIC specifies explicit ordering → respect it (no override).

PARALLEL RULE 3: Verification steps (qa, security, observability, e2e) run
  after their implementation dependencies, and CAN be parallelized with each
  other in the same wave.

PARALLEL RULE 4: Within the same role, steps are sequential by default.
  Two backend steps or two frontend steps run in sequence unless the EPIC
  explicitly marks them as independent (no cross-dependency, non-overlapping
  allowed_paths).

PARALLEL RULE 5: docs steps run after implementation. release runs last.
  These follow strict priority ordering and are never parallelized with
  implementation steps.
```

#### File Scope Overlap Detection

To evaluate PARALLEL RULE 2 condition (b), the Planner compares allowed_paths:

```
OVERLAP_CHECK(step_A, step_B):
  """Detect file scope conflicts between two parallel steps.
  Returns: CONFLICT | SAFE
  Principle: Conservative — when in doubt, return CONFLICT (prefer false positive over false negative)."""

  INPUT: step_A.files[] and step_B.files[] — each entry is a file path (exact or glob pattern)
         Only "Create" and "Modify" entries participate. "Read" and "Test" entries are excluded
         (reading and testing are safe in parallel).

  1. EXTRACT writable paths:
     writable_A = [f.path for f in step_A.files if f.action in ("Create", "Modify")]
     writable_B = [f.path for f in step_B.files if f.action in ("Create", "Modify")]
     IF either list is empty → return SAFE (no write conflicts possible)

  2. NORMALIZE all paths:
     - Strip leading "./" or "/" (make relative to project root)
     - Normalize path separators to "/"
     - Case-insensitive comparison (accommodates macOS/Windows filesystems)

  3. For each pair (path_A from writable_A, path_B from writable_B):

     Case A — BOTH EXACT PATHS (no *, no **):
       IF lowercase(path_A) == lowercase(path_B) → CONFLICT
       ELSE → this pair is SAFE

     Case B — ONE GLOB, ONE EXACT:
       Test: does the exact path match the glob pattern?
       Glob matching rules:
         "*"  → matches any characters EXCEPT "/" (single directory level)
         "**" → matches zero or more path segments including "/" (recursive)
         "?"  → matches exactly one character except "/"
       Examples:
         "src/api/*.py" matches "src/api/auth.py" → CONFLICT
         "src/api/*.py" does NOT match "src/api/routers/auth.py" (no recursive)
         "src/api/**/*.py" matches "src/api/routers/auth.py" → CONFLICT
         "src/**" matches "src/any/nested/file.ts" → CONFLICT
       IF match → CONFLICT
       ELSE → this pair is SAFE

     Case C — BOTH GLOBS:
       Conservative heuristic (exact glob intersection is computationally expensive):
       1. Extract the fixed prefix of each glob (everything before the first * or **):
          "src/api/**/*.py" → prefix = "src/api/"
          "src/models/**/*.py" → prefix = "src/models/"
       2. IF neither prefix starts with the other → SAFE
          (different directory trees cannot overlap)
          "src/api/" and "src/models/" → SAFE
       3. IF one prefix starts with the other (or prefixes are identical):
          Check file extension filters (if present):
          "src/api/**/*.py" and "src/api/**/*.ts" → SAFE (different extensions)
          "src/api/**/*.py" and "src/api/**/*.py" → CONFLICT (same extension)
          "src/api/**/*" and "src/api/**/*.py" → CONFLICT (wildcard includes .py)
       4. IF ambiguous after prefix and extension checks → CONFLICT (conservative)

  4. IF any pair produces CONFLICT → return CONFLICT
  5. IF all pairs are SAFE → return SAFE

  NOTE: False positive (marking safe steps as conflicting) causes sequential execution —
  slower but correct. False negative (marking conflicting steps as safe) causes file
  corruption — fast but broken. Always prefer false positive.
```

### Example — Parallel Backend + Frontend

```
EPIC steps (no explicit backend→frontend ordering):
  step_1_architect: depends_on: []
  step_2_domain:    depends_on: [step_1_architect]
  step_3_backend:   depends_on: [step_2_domain]
    allowed_paths: ["src/api/", "src/services/", "src/models/"]
  step_4_frontend:  depends_on: [step_1_architect]
    allowed_paths: ["src/ui/", "src/components/", "src/pages/"]

Level assignment (Section 2):
  step_1_architect: level 0
  step_2_domain:    level 1
  step_3_backend:   level 2  (depends on domain at level 1)
  step_4_frontend:  level 1  (depends on architect at level 0)

Without PARALLEL RULE 2, frontend would run in wave 1 alongside domain,
and backend would run alone in wave 2. This is valid but suboptimal
when frontend COULD wait and run alongside backend.

PARALLEL RULE 2 evaluation:
  - step_3 deps satisfied after wave 1 (domain). step_4 deps satisfied after wave 0 (architect).
  - Overlap check: src/api/ ∩ src/ui/ = empty → NO conflict.
  - EPIC has no explicit ordering between step_3 and step_4.
  - Frontend has no dependency on domain → it CAN start at wave 1.
  - But grouping it with backend at wave 2 is ALSO valid (all deps satisfied).
  → Planner decision: Level assignment governs. Frontend stays at its natural level.
    Wave assembly produces:

Wave assembly (natural levels):
  wave 0: [step_1_architect]
  wave 1: [step_2_domain, step_4_frontend]  ← parallel (both at level 1)
  wave 2: [step_3_backend]

NOTE: PARALLEL RULE 2 does NOT delay steps to create artificial groupings.
It ensures that when backend and frontend ARE at the same level (same
dependency depth), they get grouped into the same wave instead of being
split sequentially. The level assignment from Section 2 determines natural
placement; PARALLEL RULE 2 prevents the Planner from SPLITTING same-level
backend+frontend into separate waves due to conservative heuristics.
```

### Example — Backend + Frontend at Same Level (Decomposed)

```
After step decomposition (Section 2b), backend is split:
  step_3a_backend: "Database models + schemas"  depends_on: [step_2_domain]
  step_3b_backend: "API routers + services"     depends_on: [step_3a_backend]
  step_4_frontend:                              depends_on: [step_1_architect]

Level assignment:
  step_3a_backend: level 2
  step_3b_backend: level 3
  step_4_frontend: level 1

But with dependency relaxation R1 (Section 2c), frontend depends on architect
only. After domain+backend-data complete in wave 1-2, step_3b_backend and
step_4_frontend can be in the same wave:

Wave assembly (after decomposition + relaxation):
  wave 0: [step_1_architect]
  wave 1: [step_2_domain, step_4_frontend]
  wave 2: [step_3a_backend]
  wave 3: [step_3b_backend]

OR with aggressive parallelism (frontend starts earlier):
  wave 0: [step_1_architect]
  wave 1: [step_2_domain, step_3a_backend]     ← domain ‖ backend-data
  wave 2: [step_3b_backend, step_4_frontend]   ← backend-API ‖ frontend (PARALLEL RULE 2!)

PARALLEL RULE 2 applies at wave 2: step_3b_backend and step_4_frontend:
  - Both deps satisfied (architect for frontend, backend-data for backend-API).
  - Overlap check: src/api/ ∩ src/ui/ = empty → NO conflict.
  → Result: assigned to same wave.
```

### Example — Sequential Due to Shared Files

```
EPIC steps:
  step_3_backend:   allowed_paths: ["src/api/", "src/shared/types.ts"]
  step_4_frontend:  allowed_paths: ["src/ui/", "src/shared/types.ts"]

PARALLEL RULE 2 evaluation:
  - Overlap check: src/shared/types.ts in both → CONFLICT (writable).
  → Result: sequential. Backend first (more deps on domain output), then frontend.
  → Alternative: parallelize + auto-generate wiring step (Section 2a).
    Planner chooses wiring step when both steps are large (5+ files each)
    and the shared file set is small (< 3 files). Otherwise sequential.
```

### Example — Explicit EPIC Ordering Preserved

```
EPIC steps (PM explicitly ordered frontend after backend):
  step_3_backend:   depends_on: [step_2_domain]
  step_4_frontend:  depends_on: [step_3_backend]   ← explicit!

PARALLEL RULE 2 does NOT apply — condition (c) fails.
Rule 1 / Rule 6: EPIC explicit ordering preserved.
→ Result: sequential. step_3 in wave 2, step_4 in wave 3.
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
   Count distinct file patterns in allowed_paths (resolve glob patterns):
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
| V-16 | `plan.gates` MUST contain ALL gates from `gates.yaml` where `required: true` | "Missing required gate: {gate_name}. Gates.yaml requires it but plan.json omits it" |
| V-17 | `analysis_groups` is OPTIONAL (missing/empty = valid, treat as `[]`) | — |
| V-18 | Required fields: id, target, agents, mode, merge_strategy, trigger | "Analysis group at index {i} missing required field: {field}" |
| V-19 | `.agents` has at least 1 entry | "Analysis group {id} has empty agents list" |

### Validations for optimization_metrics

| Rule | Check | Error Template |
|------|-------|----------------|
| V-20 | `optimization_metrics` present in plan.json | "Plan missing optimization_metrics" |
| V-21 | `critical_path_ratio` <= 1.0 | "Invalid critical_path_ratio: {value}" |
| V-22 | `wave_count` > 0 | "Plan has no waves" |
| V-23 | All relaxations reference valid step IDs | "Relaxation references unknown step: {id}" |

### Validation Order

```
Run validations in order V-01 through V-23.
Stop on FIRST failure — report the error, fix, re-validate from V-01.
Rationale: later validations may depend on earlier ones passing
(e.g., V-09 depends on V-01 having established valid step IDs).
```

---

## 7. Complete Plan Generation Flow

This is the master procedure the Planner follows when `/aid-plan-epic` is invoked.

```
 1. RECEIVE EPIC file → validate sections → extract epic_id:
      a. REQUIRED: Goal, Scope (with ≥1 path), DoD (≥1 gate), AC (≥3 criteria)
      b. RECOMMENDED: Artifacts (typed), Context (with stack info), Hints
      c. If Artifacts are untyped → infer types from text (best effort)
      d. If Steps are missing → planner generates from Artifacts + AC (normal flow)
      e. If Steps present → treat as constraints, validate deps, allow planner to add/split
      f. If Scope has only directories (no files) → planner infers files from Artifacts
      g. WARNING (not blocking): If AC < 5 or Artifacts empty → flag in PLAN_REVIEW
         as "Low-detail EPIC — plan quality may be reduced. Consider adding typed artifacts."
 2. PARSE steps → extract (role, objective, depends_on[], outputs[], paths, constraints) → assign step_ids
 2.1. AUTO-SCAFFOLD DETECTION (Section 7.3):
      Check project-profile.yaml → if uninitialized → generate step_0_scaffold → PM confirms
 2.1b DOCKER/MCP STEP INJECTION (Section 7.4):
      Check brainstorming plan for docker_recommended → if true → inject Docker step
      If MCP servers recommended → merge MCP config into Docker step
      If workflow project → add workflow-intelligence.md template constraints
 2.2. STEP DECOMPOSITION (Section 2b):
      a. Detect EPIC type from artifacts (dev / docs / infra / mixed)
      b. For each step, evaluate granularity heuristics:
         - G2 (Module Splitting): 3+ independent modules → split by module, parallelize
         - G1 (Layer Splitting): 3+ architectural layers → split by layer group
         - G1 and G2 are mutually exclusive per step; G2 takes priority
         - Sub-steps from G2 are re-evaluated for G1 (one level only)
         - Non-dev steps: topic-based (docs) or scope-based (infra) splitting
      c. IF heuristic triggers → decompose into sub-steps
      d. Update step list with sub-steps (original step replaced)
      e. Log: decompositions_applied, sub_steps_created, epic_type,
              heuristics_applied (G1/G2 per step), heuristics_overridden
 3. RESOLVE ordering:
      explicit deps → use as-is | partial → fill from defaults (Section 3) | none → full defaults
 4. BUILD dependency graph → adjacency list → dependencies[] with reasons (Section 1)
 5. VALIDATE graph → no cycles, all refs exist, no self-deps → FAIL if invalid
 6. WAVE ASSEMBLY (replaces "DETECT parallel groups"):
      a. Level assignment via topological sort
      b. File conflict check — separate conflicting steps
      c. Group same-level steps into candidate waves
      d. Split waves with 5+ steps into sub-waves of max 4
      e. Output: waves[] array + parallel_groups (backward compat)
      f. POST_WAVE_WIRING_CHECK per wave (Section 2a):
         - Collect allowed_paths from all steps in each multi-step wave
         - Find shared files (paths in 2+ steps)
         - IF shared files found → auto-generate wiring step after wave
         - Re-wire downstream dependencies through wiring step
      g. Log: wave_count, max_wave_size, parallel_step_count, wiring_steps_generated
 6.1. CRITICAL PATH ANALYSIS (opt-in, Section 2c):
      IF total_steps >= 7:
        a. Compute critical path (longest DAG chain)
        b. IF critical_path_ratio > 0.6:
           → For dev EPICs: apply relaxation rules R1-R5
           → For non-dev EPICs: CPA data only, no relaxation rules
           → Re-level and re-assemble waves
           → Verify improvement, revert if no gain
        c. Log critical path to plan metadata:
           "critical_path": [step_ids on path]
           "critical_path_ratio": 0.57
           "relaxations_applied": [{rule, edge, reason}]
 7. GENERATE analysis_groups:
      a. Apply Rules A-D to each step → auto entries
      b. Parse EPIC manual analysis_groups → manual entries
      c. Merge: manual wins on conflict, both kept if different agents, auto kept if uncovered
      d. Assign sequential IDs (Section 5)
      e. Apply V-15: remove self-review agents, drop empty groups
 8. GENERATE relevant_files per step (Section 7.1):
      For each step, infer which files the agent needs to READ based on:
      a. Outputs from dependency steps (files created/modified by prior steps)
      b. Architect's file manifest (if available from step_1 output)
      c. Step's allowed_paths (entry points like main.py, app.py, etc.)
      d. Step's role-specific conventions (e.g., backend needs models/, schemas/)
 9. ASSEMBLE Plan JSON:
      { epic_id, version: 1, created_at, steps, dependencies,
        parallel_groups, analysis_groups, gates, budget }
10. COST ESTIMATES — conditional on billing_mode (see Section 8 below)
11. RUN BOUNDARIES:
      a. Apply wave-based run boundary algorithm (Section 11)
      b. Write ## Run Breakdown into EPIC file
      c. Set EPIC frontmatter: runs_total: N
      d. Log: run_count, steps_per_run[]
12. VALIDATE → V-01 through V-23 → fix + re-validate on failure (max 3 attempts → escalation)
13. OUTPUT → save plan.json + plan_progress.json + epic_input.md to evidence dir → present summary
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

## 7.1 Relevant Files Generation per Step

For each step in the plan, generate a `relevant_files` list that tells the dispatched
agent which files to read FIRST. This eliminates exploratory Glob/Grep operations and
significantly reduces agent execution time and token consumption.

### Algorithm

```
For each step S in plan.steps:
  relevant_files = []

  1. DEPENDENCY OUTPUTS:
     For each dep in S.depends_on:
       dep_step = lookup(dep)
       Add dep_step's expected output files to relevant_files
       Format: "{file_path} ({description} -- from {dep_step.step_id})"

  2. ARCHITECT MANIFEST (if step_1_architect produced a file manifest):
     If architect output includes a file manifest or directory structure:
       Filter files relevant to S.role from the manifest
       Add filtered files to relevant_files

  3. ENTRY POINTS from allowed_paths:
     For each path in S.allowed_paths:
       If path is a file (not directory): add it
       If path is a directory: add conventional entry points:
         - Python: __init__.py, main.py, app.py, conftest.py
         - JS/TS: index.ts, App.tsx, main.ts
         - Config: pyproject.toml, package.json, tsconfig.json

  4. ROLE-SPECIFIC CONVENTIONS:
     backend: models/, schemas/, routers/ entry files from allowed_paths
     frontend: components/, pages/, services/ entry files
     qa: existing test files in tests/ directory (for pattern matching)
     security: middleware/auth*, endpoints with auth logic
     domain: existing models/, entities/ files
     docs: README, CHANGELOG, existing docs structure

  5. DEDUPLICATE and LIMIT:
     Remove duplicate paths
     Limit to 15 files max (prioritize: deps > manifest > entry points > conventions)
```

### Output Format in plan.json

```json
{
  "step_id": "step_3_backend",
  "role": "backend",
  "objective": "Implement REST API endpoints",
  "allowed_paths": ["app/routers/", "app/services/", "app/main.py"],
  "relevant_files": [
    "app/models/bookmark.py (ORM model -- from step_2_domain)",
    "app/schemas/bookmark.py (Pydantic schemas -- from step_2_domain)",
    "contracts/openapi/bookmarks.yaml (API contract -- from step_1_architect)",
    "app/main.py (FastAPI app entry point)"
  ]
}
```

### When relevant_files Cannot Be Determined

If the Planner cannot infer relevant_files for a step (e.g., first EPIC run with no
existing code), set `relevant_files: []`. The agent will fall back to Glob/Grep
exploration within allowed_paths. This is acceptable but suboptimal.

---

## 7.2 E2E Step (Playwright)

The Planner adds an E2E testing step when ALL of the following conditions are met:

1. `project-profile.yaml` indicates `has_frontend: true` (or `architecture.app_type: web-app`)
2. Playwright MCP is configured (available in MCP tools)
3. EPIC includes frontend implementation or UI changes

### E2E Step Configuration

```json
{
  "step_id": "step_{N}_e2e",
  "role": "e2e",
  "objective": "Browser-level E2E testing of critical user flows with Playwright",
  "depends_on": ["{frontend_step_id}", "{backend_step_id}"],
  "outputs": ["e2e_test_results", "screenshots"],
  "acceptance_criteria": [
    "Critical user flows pass in browser",
    "Screenshots captured as evidence",
    "No broken navigation or form submission errors"
  ],
  "playbook": "e2e.md",
  "model": "sonnet"
}
```

### Placement Rules

- **Dependencies:** Depends on frontend + backend implementation steps (both must complete)
- **Parallel group:** Runs alongside QA, Security, and Docs (same level in DAG)
- **Agent:** Uses QA agent with E2E playbook override (`playbook: "e2e.md"`)
- **Model:** Sonnet (browser interactions are structured, do not require Opus)

### When NOT to Add E2E Step

If any of the three conditions above are NOT met, do NOT add an E2E step. No warning
is needed -- the Planner simply skips it. The absence of Playwright MCP or frontend
files is a normal, valid configuration.

---

## 7.3 Auto-Scaffold Detection

Check if the project needs scaffolding before EPIC execution begins. This step
runs between PARSE (step 2) and RESOLVE ordering (step 3) in the plan generation flow.

### Algorithm

```
1. Read `project-profile.yaml` → check `initialized` field
2. If `initialized: false` OR project-profile has no `tech_stack.test` configured:
   - Detect needed scaffold from `tech_stack.languages`:
     - Python:  `python -m venv .venv && pip install -r requirements.txt`
     - Node.js: `npm init -y && npm install`
     - Go:      `go mod init {module_name}`
     - Rust:    `cargo init`
   - Generate "step_0_scaffold":
     {
       "step_id": "step_0_scaffold",
       "role": "architect",
       "objective": "Initialize project structure, virtual environment, and dependencies",
       "depends_on": [],
       "outputs": ["project scaffold", "dependency manifest", "test configuration"],
       "acceptance_criteria": [
         "Project structure matches conventions",
         "Dependencies installed and importable",
         "Test runner configured and executable"
       ]
     }
   - Insert as first step (all other steps depend on it)

3. If `initialized: true` AND test framework configured: skip scaffold step

4. Present scaffold plan to PM for confirmation:
   ```
   Auto-scaffold detected: {language} project needs initialization.
   Step 0 will set up: {scaffold_description}
   Include this step? (Y/N)
   ```
   If PM says N: skip scaffold step, proceed with existing steps.
```

### Dependency Wiring

When step_0_scaffold is included:
- All existing steps that had no dependencies (`depends_on: []`) now depend on `step_0_scaffold`
- Steps that already have dependencies are NOT modified (their transitive dependency
  through other steps is sufficient)
- This ensures scaffold completes before any implementation begins

---

## 7.4 Docker/MCP Step Injection

When the brainstorming plan recommends Docker, the Planner injects a "Docker Compose setup"
step into the plan. MCP server configuration is always part of this Docker step -- never a
separate step. This section defines when and how the Docker step is injected, and where it
sits in the dependency graph.

### Injection Rules

```
WHEN: Generating plan steps from the approved brainstorming plan/EPIC.

IF brainstorming plan includes docker_recommended == true:
  1. ADD a "Docker Compose setup" step to the plan:
     - step_id: step_{N}_docker (N assigned by position in sequence)
     - role: backend
     - objective: "Create Docker Compose configuration for the project"
     - outputs: ["docker-compose.yml", ".env.example"]
     - constraints: ["Follow platform-specific Docker template from
       workflow-intelligence.md if workflow project"]
     - Position: AFTER architect step, BEFORE other backend steps
       (see Step Ordering below)

  2. IF MCP servers were recommended in brainstorming:
     - MCP server configuration is PART of the Docker step (never a separate step)
     - Update Docker step objective to:
       "Create Docker Compose configuration for the project, including
        MCP server containers"
     - Add to outputs: ["mcp-config.json"]
     - The Docker step's acceptance_criteria MUST include:
       "MCP server containers defined in docker-compose.yml with correct
        port mappings and environment variables"

  3. IF workflow project detected (from project-profile.yaml or brainstorming):
     - Docker Compose template comes from workflow-intelligence.md platform knowledge
     - Docker step constraints add:
       "Include platform-specific services from workflow-intelligence.md
        (vectorstore, workers, message broker, etc.)"
     - Docker step relevant_files includes:
       "workflow-intelligence.md (platform Docker template reference)"

  4. IF docker_recommended == false OR not present:
     - Do NOT add a Docker step
     - Do NOT generate docker-compose.yml in any step's outputs
     - Do NOT mention Docker anywhere in the plan

  5. IF brainstorming plan includes constraint "PM decided: no Docker":
     - Do NOT add a Docker step regardless of other signals
     - Respect PM decision unconditionally
```

### Step Ordering

```
Docker step placement in the dependency graph:

  architect → Docker Compose setup → backend → frontend → ...

Dependency rules:
  a. Docker step depends_on: [step_{M}_architect]
     Reason: Docker Compose needs architecture decisions (services, ports,
     data stores) defined by the architect step before it can be configured.

  b. Backend steps depend_on: [step_{N}_docker]
     Reason: Backend implementation references docker-compose.yml for
     service names, ports, database connection strings, and environment
     variables.

  c. Frontend steps depend_on: [step_{N}_docker]
     Reason: Frontend container definition lives in docker-compose.yml.
     Frontend development server configuration references compose services.

  d. If step_0_scaffold exists:
     scaffold → architect → Docker → backend/frontend
     Docker step does NOT depend on scaffold directly (transitive through
     architect is sufficient).

  e. Domain step (if present) runs parallel with Docker step:
     architect → [domain ‖ Docker] → backend
     Domain does not need Docker. Docker does not need domain models.
     Both depend on architect. Backend depends on both.
```

### Example — Plan With Docker Step

```
EPIC with docker_recommended == true and MCP servers recommended:

  step_1_architect:  "Define API contracts and ADRs"
    depends_on: []

  step_2_docker:     "Create Docker Compose configuration, including MCP server containers"
    depends_on: [step_1_architect]
    role: backend
    outputs: [docker-compose.yml, .env.example, mcp-config.json]

  step_3_domain:     "Define domain entities and invariants"
    depends_on: [step_1_architect]

  step_4_backend:    "Implement REST API endpoints"
    depends_on: [step_2_docker, step_3_domain]

  step_5_frontend:   "Implement UI components"
    depends_on: [step_2_docker, step_1_architect]

Wave assembly result:
  wave 0: [step_1_architect]
  wave 1: [step_2_docker, step_3_domain]       ← parallel
  wave 2: [step_4_backend, step_5_frontend]    ← parallel
```

### Integration with Plan Generation Flow

Docker step injection runs at step 2.1 of the master procedure (Section 7), alongside
Auto-Scaffold Detection. The sequence is:

```
2.   PARSE steps
2.1. AUTO-SCAFFOLD DETECTION (Section 7.3)
2.1b DOCKER/MCP STEP INJECTION (this section):
     a. Check brainstorming plan for docker_recommended flag
     b. If true: generate Docker step, wire dependencies
     c. If MCP servers recommended: merge into Docker step
     d. If workflow project: add workflow-intelligence.md constraints
2.2. STEP DECOMPOSITION (Section 2b)
3.   RESOLVE ordering
```

The Docker step is injected BEFORE step decomposition so that decomposition rules
can evaluate it normally (though Docker steps rarely meet decomposition criteria
since they produce only 2-3 files).

---

## 8. LLM Cost Estimates — Conditional on Billing Mode

LLM cost estimates (e.g., `budget.max_llm_cost_usd` in Plan JSON, `LLM Cost: $X` in reports) are
only relevant when the user pays per-token via API. Users on subscription plans (Claude Pro, Team,
Enterprise) pay a flat fee regardless of token usage, making cost estimates misleading and irrelevant.

### Behavior

```
1. Read project profile from `.aid-o/03-config/project-profile.yaml`
   (or `.aid-o/03-config/policies/project-profile.yaml`)
2. Check `billing_mode` field:

   billing_mode: "api"          → INCLUDE cost estimates in plan + reports
   billing_mode: "subscription" → SKIP cost estimates entirely
   billing_mode: not set / null → SKIP cost estimates (default = subscription)

3. When SKIPPING cost estimates:
   a. Omit `budget.max_llm_cost_usd` from Plan JSON (or set to null)
   b. Omit "LLM Cost: $X" line from final_report.md summary
   c. Omit per-step cost columns from plan summary presented to PM
   d. Do NOT mention estimated costs in any PM-facing messages

4. When INCLUDING cost estimates (billing_mode: "api"):
   a. Estimate per-step token usage based on role complexity + input size
   b. Include `budget.max_llm_cost_usd` in Plan JSON
   c. Include "LLM Cost: ${estimated}" in final_report.md
   d. Show cost column in PM plan summary
```

### Validation Update

Validation rule V-07 (`budget.max_llm_cost_usd >= 0`) only applies when `billing_mode: "api"`.
When cost estimates are skipped, the budget field may be absent or have `max_llm_cost_usd: null` —
both are valid.

---

## 9. Plan and EPIC Frontmatter Counters

When generating plan and EPIC files, the Planner writes counters to their frontmatter
for lifecycle tracking (archive logic in `skills/epic-orchestration.md` DONE state).

### Plan Frontmatter (extended)

```yaml
# In .aid-o/01-plans/{plan}.md frontmatter:
status: active           # active | completed
epics_total: 3           # how many EPICs this plan spawns
epics_completed: 0       # incremented at each EPIC DONE
```

The Planner determines `epics_total` from the plan content (number of EPIC references or
explicit EPIC list). If only one EPIC: `epics_total: 1`. If plan does not reference
specific EPICs: `epics_total: 1` (default -- single EPIC assumed).

### EPIC Frontmatter (extended)

```yaml
# In .aid-o/02-epics/{epic}.md frontmatter:
status: active
plan_ref: bookmark-plan.md   # parent plan (null for standalone)
plan_epics_total: 3      # copied from plan for quick reference
runs_total: 1        # from Run Breakdown (1 = single run)
runs_completed: 0    # incremented at each run DONE
```

If EPIC has `## Run Breakdown` with N runs: `runs_total: N`.
Otherwise default `runs_total: 1`.

If EPIC is standalone (no parent plan): `plan_ref: null`, `plan_epics_total: null`.

---

## 10. Gate Inclusion (Step 3.gates)

The plan MUST include ALL gates from the project's `gates.yaml`:

1. Read `.aid-o/03-config/policies/gates.yaml`
2. For each gate definition:
   - If `required: true`: ALWAYS include in plan.json gates
   - If `required: false` AND `when` condition evaluates to true based on
     EPIC scope: include in plan.json gates
   - If `required: false` AND `when` condition evaluates to false: exclude
3. The plan.json `gates` array MUST match gates.yaml required gates exactly

**Validation rule V-16 (NEW):** `plan.gates` MUST contain ALL gates from
`gates.yaml` where `required: true`. Missing required gates = validation failure.

Example:
```yaml
# gates.yaml has:
tests_pass:     required: true    # MUST be in plan.json
lint_pass:      required: true    # MUST be in plan.json
security_scan:  required: true    # MUST be in plan.json
docs_updated:   required: true    # MUST be in plan.json
type_check:     required: false   # include IF frontend files in scope
build_pass:     required: false   # include IF frontend files in scope
```

```json
// plan.json gates (correct):
"gates": ["tests_pass", "lint_pass", "security_scan_pass", "docs_updated"]
// + conditionally: "type_check", "build_pass"
```

**NEVER** hardcode the gates list. ALWAYS read from gates.yaml.

---

## 11. Planner Optimization Strategy (Parallelism-First)

### Core Philosophy

The Planner's PRIMARY job is to minimize WALL-CLOCK TIME to EPIC completion.
Not step count. Not token count. WALL-CLOCK TIME.

```
Wall-clock time ≈ critical_path_length × avg_step_duration
                + run_transitions × ~2 min each
                + overhead (merges, phase checks, wave transitions)
```

### Optimization Priorities (in order)

1. **PARALLELISM** — minimize critical path length
   - Every step on the critical path is wall-clock time you can't avoid
   - Decompose steps to move work OFF the critical path (Section 2b)
   - Relax dependencies to shorten the critical path (Section 2c)
   - Target: critical_path_ratio < 0.5 (< half of steps on critical path)

2. **WAVE DENSITY** — maximize work per wave
   - Empty slots in a wave = wasted parallelism capacity
   - 4 agents in parallel ≈ same wall-clock time as 1 agent
   - Target: average wave utilization > 2.5 steps/wave

3. **RUN COMPACTNESS** — minimize run count
   - Each run transition costs: context reload + state verify ≈ 2 min
   - Fewer runs = less overhead
   - Target: total_steps / run_count >= 4

4. **QUALITY** — ensure outputs meet acceptance criteria
   - Every step has clear, verifiable acceptance criteria
   - Dependencies are explicit — no implicit ordering assumptions
   - Security and QA steps always AFTER implementation
   - Gates validate cumulative quality

5. **EFFICIENCY** — avoid wasted work
   - No redundant steps (don't split what one agent can do well)
   - File scoping: relevant_files per step eliminates blind exploration
   - Dependency outputs are explicit — agents don't guess what prior steps produced

### Step Planning Rules (revised)

#### Universal Rules (all EPIC types)

1. **First step is always wave 0** — architect (dev), lead writer (docs), or scaffold (infra)
2. **Maximum wave size: 4 steps** — soft limit, Controller handles overflow gracefully
3. **NEVER create trivially small steps** (< 3 files) just for parallelism
4. **Prefer wider waves over more waves** — 1 wave of 4 > 2 waves of 2
5. **Verification/review steps ALWAYS after implementation/writing** — QA, security, review

#### Development-Specific Rules

6. **Backend + Frontend parallelize after architect+domain** when file scopes don't overlap.
   This is the #1 parallelism opportunity in most dev EPICs.
   Apply Parallel Group Assignment Rules (Section 3) — specifically PARALLEL RULE 2:
   - Contracts exist from architect → both can start
   - allowed_paths don't overlap → same wave (parallel)
   - allowed_paths overlap → sequential, or parallel + wiring step (Section 2a)
   - EPIC explicit backend→frontend ordering → sequential (Rule 1 / Rule 6 in Section 3)
7. **Decompose large steps** using granularity heuristics (Section 2b):
   - G1 (Layer Splitting): 3+ layers, 5+ files → split by layer group
   - G2 (Module Splitting): 3+ independent modules → split by module, parallelize
   WHEN this enables at least 1 new parallel pairing
8. **Domain can parallelize with backend's first sub-step** IF:
   - Domain produces models/entities
   - Backend first sub-step is data layer (schemas, DB setup)
   - They don't touch the same files (non-overlapping allowed_paths)

#### Non-Development Rules

9. **Independent topics ALWAYS parallelize** — "API docs" ‖ "User guide" if different sources
10. **Config steps parallelize when targeting different systems** — CI ‖ deployment ‖ monitoring

### Plan Quality Metrics

Every plan.json MUST include an `optimization_metrics` object:

```json
{
  "optimization_metrics": {
    "total_steps": 14,
    "wave_count": 8,
    "run_count": 3,
    "critical_path_length": 5,
    "critical_path_ratio": 0.36,
    "avg_wave_density": 1.75,
    "parallel_step_count": 10,
    "sequential_step_count": 4,
    "relaxations_applied": 2,
    "decompositions_applied": 1
  }
}
```

These metrics are:
- Shown in PLAN_REVIEW (so PM sees parallelism quality)
- Stored in evidence (for post-EPIC analysis)
- Fed to /aid-analytics (for cross-EPIC optimization tracking)
- Used by Planner self-improvement (compare metrics across EPICs via Qdrant)

### Run Split Decision (Wave-Based)

**Core principle:** Runs = contiguous sequences of waves that fit context window.
NEVER split by domain. NEVER split inside a wave.

#### Run Boundary Algorithm

```
1. Start with waves[] from Wave Assembly (Section 2)

2. Assign waves to runs greedily:
   run_steps = 0
   current_run = []

   FOR each wave W in waves[]:
     IF run_steps + len(W) <= MAX_STEPS_PER_RUN:
       current_run.append(W)
       run_steps += len(W)
     ELSE:
       Flush current_run → new run
       current_run = [W]
       run_steps = len(W)

3. Validate runs:
   a. NEVER split inside a wave (wave with 2+ steps = parallel group)
   b. Each run must contain at least 1 gate-worthy milestone
   c. First run always starts with architect
   d. Last run always ends with release (if present)
   e. Each run produces independently testable deliverables
```

#### MAX_STEPS_PER_RUN heuristic

| Total EPIC steps | Max per run | Rationale |
|------------------|-----------------|-----------|
| 1-6              | 6 (= 1 run) | Fits single context window |
| 7-10             | 6-7             | 2 runs, balanced |
| 11-15            | 6               | 2-3 runs |
| 16+              | 5-6             | 3+ runs, tighter bounds |

Note: "steps" counts sub-steps from decomposition (Section 2b).
A wave of 4 parallel steps counts as 4 steps for this limit.

#### Example — 14-step full-stack EPIC after optimization

Note: This example shows the result AFTER step decomposition has
split monolithic steps into sub-steps (e.g., step_3a, step_3b).

```
Waves (from Wave Assembly):
  wave 0: [step_1_architect]
  wave 1: [step_2_domain, step_3a_backend]
  wave 2: [step_3b_backend, step_4_frontend]         ← cross-domain parallel!
  wave 3: [step_5_backend_search, step_6_extension]
  wave 4: [step_7_frontend_pages]
  wave 5: [step_8_frontend_polish]
  wave 6: [step_9_qa, step_10_security, step_11_docs]
  wave 7: [step_12_release]

Runs (MAX_STEPS_PER_RUN = 6):
  Run 1 (waves 0-2, 6 steps):
    architect → [domain ‖ backend-data] → [backend-API ‖ frontend-scaffold]
    Milestone: working API + frontend scaffold

  Run 2 (waves 3-5, 4 steps):
    [search ‖ extension] → frontend-pages → frontend-polish
    Milestone: complete frontend + all features

  Run 3 (waves 6-7, 4 steps):
    [QA ‖ security ‖ docs] → release
    Milestone: validated + released

vs. OLD approach (sequential domains):
  Run 1: architect → domain → backend (all 5 steps sequentially)
  Run 2: frontend (all 4 steps sequentially)
  Run 3: QA → security → docs → release

Result: 3 waves of parallel work vs 0 in old approach.
```

### Run Breakdown Generation

The Planner writes `## Run Breakdown` into the EPIC file:

```markdown
## Run Breakdown

### Run 1: Core Implementation (waves 0-2, 6 steps)
**Goal:** Build working API with data model
**Waves:** wave 0 [architect] → wave 1 [domain ‖ backend-data] → wave 2 [backend-API ‖ frontend]
**Deliverables:** Working endpoints, database, basic UI

### Run 2: Quality & Release (waves 3-4, 4 steps)
**Goal:** Verify, secure, document, release
**Waves:** wave 3 [QA ‖ security ‖ docs] → wave 4 [release]
**Deliverables:** Test suite (90%+ coverage), security review, documentation
```

And sets EPIC frontmatter: `runs_total: 2`

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
11. **NEVER hardcode gates** — ALWAYS read from gates.yaml and include all required gates (V-16)
12. **ALWAYS write frontmatter counters** when creating plans (epics_total) and EPICs (runs_total)
13. **NEVER add Docker steps when docker_recommended is false or absent** — Docker is opt-in only (Section 7.4)
14. **NEVER create a separate MCP step** — MCP configuration is always part of the Docker step (Section 7.4)
15. **ALWAYS respect "PM decided: no Docker"** constraint — overrides docker_recommended flag
16. **ALWAYS check file scope overlap** before parallelizing backend + frontend — use OVERLAP_CHECK (Section 3) and respect EPIC explicit ordering (Application Rule 6)
17. **ALWAYS evaluate granularity heuristics G1 and G2** during Step Decomposition (Section 2b) — log applied heuristics or override reasons in plan metadata

---

## Reference Files

- `commands/aid-plan-epic.md` -- command that invokes this skill
- `skills/epic-orchestration.md` -- PLANNING state references this skill (Section 2)
- `skills/brainstorming.md` -- produces docker_recommended flag consumed by Section 7.4
- `skills/workflow-intelligence.md` -- platform-specific Docker Compose templates for workflow projects (Section 7.4)
- `defaults/templates/plan.schema.json` -- Plan JSON schema (includes analysis_groups)
- `.aid-o/01-plans/P-20260216-b3a1-aid-v2-workspace-agents-memory.md` -- Plan D-011 (analysis_groups design decision)

---

**Last Updated:** 2026-02-27
