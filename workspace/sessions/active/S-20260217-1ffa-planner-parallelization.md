---
id: S-20260217-1ffa
type: new-feature
status: active
priority: high
started: 2026-02-17
epic_id: ADO-0001
epic_session: 5
epic_file: workspace/workflow/epics/active/EPIC-ADO-0001-BUILD-ORCHESTRATOR.md
plan_ref: workspace/workflow/plans/P-20260216-b3a1-aid-v2-workspace-agents-memory.md
ai_agent: Claude Opus 4.6
branch: session/S-20260217-1ffa-planner-parallelization
previous_session: workspace/sessions/completed/S-20260217-e7b3-worker-agents-curator-auditor-scanner.md
---

# Session 5: Planner + Paralelizace + Multi-Perspective Analysis

## Objective

Rozsidit Planner o automaticke generovani plan JSON s dependency grafem a parallel groups,
implementovat paralelni dispatch agentu v Controlleru, branch management (branch per agent +
conflict-free merge), a multi-perspective analysis (analysis_groups) — vice agentu analyzuje
stejny target z ruznych perspektiv s merge strategiemi.

Na konci session musi:
- `/plan-epic` automaticky generovat `analysis_groups` (auto-trigger pravidla)
- `plan.schema.json` podporovat `analysis_groups` top-level pole
- Controller (run-epic.md) EXECUTING state umět dispatchovat analysis_groups paralelne
- 3 merge strategie fungovat: `union`, `consensus`, `weighted`
- Konsolidovany `analysis_report` se ukladat do evidence
- Branch management: branch per agent, sequential merge chain, parallel fork+merge
- `skills/planner.md` — novy skill definujici Planner logiku (dependency graph, parallel groups, auto-triggers, analysis groups)
- `skills/parallel-dispatch.md` — novy skill pro paralelni dispatch protocol + merge
- `skills/analysis-merge.md` — novy skill pro multi-perspective merge strategie
- Vsechny existujici commands/skills aktualizovany o nove reference

## Context / Prerekvizity

Session 1 dodala:
- Plugin scaffold, `defaults/playbooks/` (9 playbooks)
- `defaults/policies/decision-policies.yaml` — auto_decisions, escalation_triggers

Session 2 dodala:
- `commands/plan-epic.md` — EPIC → Plan JSON (aktualne sekvencni logika + basic parallel_groups)
- `commands/run-epic.md` — state machine loop s EXECUTING state (basic sequential + parallel dispatch)
- `commands/run-step.md` — single step dispatch
- `defaults/templates/plan.schema.json` — Plan JSON schema (aktualne BEZ analysis_groups)

Session 3 dodala:
- `skills/gates-engine.md`, `skills/retry-engine.md` — gates + retry protocol
- `agents/gate-fixer.md` — fix agent

Session 4 dodala:
- 9 role agentu (`agents/{architect,domain,...,release}.md`)
- 3 specialist agenti (curator, auditor, project-scanner)
- `skills/improvement-proposals.md`
- `skills/epic-orchestration.md` aktualizovano o Curator + Auditor v DONE state
- `plugin.json` — 18 agents, 16 commands, 7 skills

**Klicove existujici soubory k modifikaci:**
- `commands/plan-epic.md` — rozsidit o analysis_groups generaci + auto-trigger pravidla
- `commands/run-epic.md` — rozsidit EXECUTING state o analysis_groups dispatch + merge
- `defaults/templates/plan.schema.json` — pridat `analysis_groups` do schema
- `skills/epic-orchestration.md` — rozsidit EXECUTING + PHASE_CHECK o analysis_groups handling
- `plugin.json` — registrovat nove skills

**Klicovy design (z Plan D-011):**
- `parallel_groups` = ruzni agenti delaji ruznou praci soucasne
- `analysis_groups` = ruzni agenti analyzuji STEJNY target z ruznych uhlu
- Auto-trigger: security-relevant step → security review, vysoka komplexita → architect review, DB zmeny → backend+security review

## Deliverables

- [x] `skills/planner.md` — Planner skill (dependency graph, parallel groups, auto-triggers, analysis groups generation)
- [x] `skills/parallel-dispatch.md` — Paralelni dispatch protocol (branch management, fork/merge, conflict detection)
- [x] `skills/analysis-merge.md` — Analysis merge skill (3 strategie: union, consensus, weighted)
- [x] Update `defaults/templates/plan.schema.json` — pridat `analysis_groups` schema
- [x] Update `commands/plan-epic.md` — integrace Planner skillu, analysis_groups generace
- [x] Update `commands/run-epic.md` — analysis_groups dispatch v EXECUTING, merge v PHASE_CHECK
- [x] Update `commands/run-step.md` — podpora `--analysis-group` parametru pro manual dispatch
- [x] Update `skills/epic-orchestration.md` — EXECUTING + PHASE_CHECK rozsireni o analysis_groups
- [x] Update `plugin.json` — registrace 3 novych skills
- [x] Update `commands/aid-help.md` — pridat Planner + Parallelization + Analysis Groups sekce
- [x] Cross-reference verification — vsechny registrace konzistentni

## Phases

### Phase 1: Planner Skill — `skills/planner.md`

**Cil:** Definovat kompletni Planner logiku — jak se z EPIC generuje Plan JSON s dependency grafem, parallel groups a analysis groups. Toto je "mozek" planovani, na ktery se odkazuje `plan-epic.md`.

**Skill musi definovat:**

1. **Dependency Graph Construction:**
   ```
   Input: EPIC steps (role + objective + depends_on)
   Output: DAG (directed acyclic graph) of steps

   Algorithm:
   1. Parse EPIC steps → list of (step_id, role, objective, depends_on[])
   2. Build adjacency list (before → after)
   3. Validate: no cycles (topological sort must succeed)
   4. Validate: all referenced step IDs exist
   5. Validate: no self-dependencies
   6. Output: dependencies[] array for Plan JSON
   ```

2. **Parallel Group Detection:**
   ```
   Input: dependency graph
   Output: parallel_groups[] array

   Algorithm:
   1. Topological sort → level assignment:
      - Level 0: steps with no dependencies
      - Level N: steps whose ALL dependencies are level < N
   2. Steps at same level with no inter-dependencies → parallel group
   3. Single-step levels → sequential (no parallel group entry)
   4. Output: array of arrays [[step_a, step_b], [step_c, step_d]]
   ```

3. **Default Ordering Rules (when EPIC doesn't specify):**

   | Priority | Role | Reason |
   |----------|------|--------|
   | 1 | architect | Contracts before implementation |
   | 2 | domain | Needs contracts, before implementation |
   | 3 | backend, frontend | Parallel — both depend on contracts |
   | 4 | qa, security, observability | Parallel — all depend on implementation |
   | 5 | docs | After implementation |
   | 6 | release | Last — needs all gates to pass |

   EPIC explicit ordering ALWAYS overrides defaults.

4. **Analysis Groups Generation (auto-trigger pravidla):**
   ```
   Input: steps[] from Plan JSON
   Output: analysis_groups[] array

   Auto-trigger rules:
   A) Security-relevant step detection:
      - Step objective mentions: auth, password, token, encryption, secret, permission, RBAC, CORS, CSRF, XSS, SQL, injection
      - Step role is: backend (with DB/auth changes)
      → Add analysis_group: agents=["security"], mode="review", merge="union"

   B) High complexity detection:
      - Step has 5+ expected outputs
      - Step objective mentions: refactor, migrate, redesign, overhaul
      - Step touches 10+ files (from allowed_paths patterns)
      → Add analysis_group: agents=["architect"], mode="review", merge="weighted"

   C) Database changes detection:
      - Step objective mentions: migration, schema, database, table, index, query
      - Step allowed_paths include: migrations/, models/, schema/
      → Add analysis_group: agents=["backend", "security"], mode="validation", merge="consensus"

   D) API contract changes:
      - Step role is architect
      - Step outputs include: OpenAPI, swagger, contract, ADR
      → Add analysis_group: agents=["backend", "frontend"], mode="validation", merge="union"

   E) Manual override:
      - EPIC may explicitly define analysis_groups in its spec → preserve them
      - Manual groups take precedence over auto-generated
      - Deduplicate: if auto and manual target same step with same agents → keep manual
   ```

5. **Analysis Group ID Format:**
   ```
   "analysis_{N}_{purpose}"

   Examples:
   - analysis_1_security_review
   - analysis_2_architecture_review
   - analysis_3_db_validation

   N = sequential within the plan, purpose = descriptive slug
   ```

6. **Plan JSON Validation (extended):**
   ```
   Existing validations (keep):
   - All step IDs unique
   - All roles valid enum
   - All dependency before/after reference existing step IDs
   - All parallel_groups reference existing step IDs
   - No circular dependencies
   - Gates valid enum

   New validations:
   - All analysis_groups.target reference existing step IDs
   - All analysis_groups.agents are valid role enum values
   - All analysis_groups.merge_strategy are: union|consensus|weighted
   - All analysis_groups.mode are: review|audit|validation
   - No duplicate analysis_group IDs
   - Analysis group agents != target step agent (don't self-review)
   ```

**Reference soubory:**
- `commands/plan-epic.md` — existujici plan generace (Step 2-3)
- `skills/epic-orchestration.md` — PLANNING state + plan generation rules
- `defaults/templates/plan.schema.json` — current schema (bude rozsireno)
- Plan `D-011` — multi-perspective analysis design

**Acceptance:**
- [ ] Dependency graph algorithm jasne definovan (DAG, topological sort)
- [ ] Parallel group detection z levelu topologickeho sortu
- [ ] Default ordering rules s EPIC override
- [ ] 4+ auto-trigger pravidel pro analysis_groups (security, complexity, DB, API)
- [ ] Manual override pravidla pro analysis_groups z EPIC
- [ ] Plan JSON validation rozsirena o analysis_groups
- [ ] ID format pro analysis_groups definovan

---

### Phase 2: Parallel Dispatch Skill — `skills/parallel-dispatch.md`

**Cil:** Definovat protocol pro paralelni dispatch agentu — jak se vytvareji branches, jak se dispatchuji agenti soucasne, jak se merguji vysledky, a jak se detekuji konflikty.

**Skill musi definovat:**

1. **Branch Strategy:**
   ```
   Base branch: epic/{epic_id}/main (created at EPIC start from current main)

   Sequential step:
     1. Create branch: epic/{epic_id}/step_{N}_{role} FROM epic/{epic_id}/main
     2. Agent works on this branch
     3. After PHASE_CHECK pass: merge step branch → epic/{epic_id}/main
     4. Delete step branch

   Parallel group:
     1. All branches fork FROM epic/{epic_id}/main (same base)
     2. Each agent works on own branch
     3. After ALL agents in group complete + PHASE_CHECK:
        a. Merge branches one-by-one into epic/{epic_id}/main
        b. Order: by step number (lower first)
        c. If merge conflict → ESCALATION (with conflict details)
     4. Delete step branches

   Analysis group (differs from parallel!):
     1. Analysis agents DON'T write code — they produce reports
     2. No branch needed (read-only analysis)
     3. All analysis agents get snapshot of current epic/{epic_id}/main
     4. Outputs → evidence only (analysis_report), NOT merged into code

   Final:
     epic/{epic_id}/main → PR to main
   ```

2. **Parallel Dispatch Protocol:**
   ```
   For parallel_groups:
     1. Identify all steps in the group
     2. For each step:
        a. Create branch
        b. Prepare agent prompt (same as sequential)
        c. Include "PARALLEL CONTEXT" note:
           "Other agents working in parallel: {list of roles}.
            Your branch: epic/{epic_id}/step_{N}_{role}.
            Do NOT modify files outside your allowed_paths."
     3. Dispatch ALL agents in single message (multiple Task tool calls)
     4. Wait for ALL to complete
     5. Proceed to PHASE_CHECK for the group

   For analysis_groups:
     1. Wait until target step is "done" (from plan_progress.json)
     2. For each analysis agent:
        a. Prepare analysis prompt:
           "Analyze step {target} from {mode} perspective.
            Target step output: {evidence/steps/{target}/output.md}
            Target step diff: {evidence/steps/{target}/diff.patch}
            Your role: {agent_role} — focus on your domain expertise."
        b. Include merge strategy in prompt:
           "Merge strategy: {strategy}. Your findings will be combined with
            other perspectives using this strategy."
     3. Dispatch ALL analysis agents in single message
     4. Collect outputs → pass to merge skill
   ```

3. **Conflict Detection:**
   ```
   Types of conflicts:
   A) Git merge conflict — two agents modified same file/line
      → Detection: git merge --no-commit, check exit code
      → Resolution: ESCALATION with diff context

   B) Semantic conflict — no git conflict but incompatible changes
      → Detection: PHASE_CHECK looks for:
        - Contradictory API definitions
        - Incompatible type changes
        - Circular dependency introduction
      → Resolution: ESCALATION with both outputs for PM

   C) Scope violation in parallel — agent modified files outside allowed_paths
      → Detection: compare git diff against allowed_paths per agent
      → Resolution: auto-reject, re-dispatch (same as PHASE_CHECK in sequential)
   ```

4. **Parallel PHASE_CHECK Extensions:**
   ```
   For parallel groups (in addition to normal PHASE_CHECK):
   1. Run normal checks per agent (outputs present, scope respected)
   2. Check for cross-agent conflicts:
      a. Collect all modified files across all agents in group
      b. If any file modified by 2+ agents → potential conflict
      c. Try merge (dry-run):
         git merge --no-commit step_{a} step_{b}
         If fails → ESCALATION
         If succeeds → record "clean merge" in evidence
   3. Verify no agent overwrote another's expected outputs
   ```

5. **Evidence for Parallel Dispatch:**
   ```
   .aid-o/04-engine/evidence/{epic_id}/{run_id}/
     parallel_groups/
       group_{N}/
         dispatch_log.json          # When each agent was dispatched
         merge_log.json             # Merge order, conflict check results
         branch_status.json         # Branch names, creation/deletion times
   ```

**Reference soubory:**
- `skills/epic-orchestration.md` — existujici Agent Dispatch Protocol + Branch Management
- `commands/run-epic.md` — existujici EXECUTING state (parallel group handling)
- Plan `D-011` — analysis_groups vs parallel_groups distinction

**Acceptance:**
- [ ] Branch strategy jasne definovana (sequential merge chain, parallel fork+merge, analysis read-only)
- [ ] Parallel dispatch protocol pro parallel_groups i analysis_groups
- [ ] Conflict detection: git conflict + semantic conflict + scope violation
- [ ] PHASE_CHECK rozsireni pro paralelni groups
- [ ] Evidence struktura pro parallel dispatch
- [ ] Analysis groups explicite nemaji branch (read-only)

---

### Phase 3: Analysis Merge Skill — `skills/analysis-merge.md`

**Cil:** Definovat 3 merge strategie pro multi-perspective analysis a format konsolidovaneho analysis_report.

**Skill musi definovat:**

1. **Input Format (z analysis agentu):**
   ```yaml
   analysis_output:
     agent: "{role}"
     target_step: "step_{N}_{role}"
     mode: "review|audit|validation"
     findings:
       - severity: critical|high|medium|low|info
         category: "security|performance|architecture|correctness|style"
         location: "path/to/file:line"
         finding: "Description of what was found"
         recommendation: "What should be done"
         confidence: high|medium|low
     summary: "One-paragraph analysis summary"
     improvement_notes: [...]   # standard format from improvement-proposals.md
   ```

2. **Union Strategy (`union`):**
   ```
   Purpose: Collect ALL findings from all perspectives. No deduplication.
   Use when: You want comprehensive coverage (e.g., security review — miss nothing).

   Algorithm:
   1. Concatenate all findings from all agents
   2. Sort by severity (critical → info)
   3. Tag each finding with source agent
   4. No deduplication (same issue from 2 agents = 2 entries, both kept)
   5. Summary = all agent summaries concatenated with "---" separator

   Output: analysis_report with all findings preserved
   ```

3. **Consensus Strategy (`consensus`):**
   ```
   Purpose: Only keep findings that 2+ agents agree on. High confidence.
   Use when: You want noise-free results (e.g., DB validation — only confirmed issues).

   Algorithm:
   1. Collect all findings from all agents
   2. For each finding, compute similarity score with every other finding:
      - Same location (file:line ±5 lines) = +0.4
      - Same category = +0.3
      - Same severity (±1 level) = +0.2
      - Similar description (keyword overlap > 50%) = +0.1
   3. Findings with similarity >= 0.6 to at least 1 other finding → "consensus"
   4. Consensus findings: keep, merge descriptions, elevate to highest severity
   5. Non-consensus findings: include in separate "minority_findings" section
   6. Summary = synthesized from consensus findings only

   Output: analysis_report with consensus_items + minority_findings
   ```

4. **Weighted Strategy (`weighted`):**
   ```
   Purpose: Weight findings by agent expertise. Domain expert findings rank higher.
   Use when: You want prioritized results (e.g., architecture review).

   Default weights (by agent role):
   | Finding category | Primary expert (weight 1.0) | Secondary (0.7) | Others (0.4) |
   |------------------|-----------------------------|------------------|---------------|
   | security | security | backend | * |
   | performance | backend, frontend | observability | * |
   | architecture | architect | domain | * |
   | correctness | qa | backend, frontend | * |
   | style | docs-writer | frontend | * |

   Algorithm:
   1. Collect all findings from all agents
   2. For each finding:
      a. Determine category
      b. Look up agent's weight for that category
      c. Compute weighted_severity = base_severity * weight
         (critical=4, high=3, medium=2, low=1, info=0.5)
   3. Sort by weighted_severity descending
   4. Deduplicate: if same location+category, keep highest weighted version
   5. Summary = synthesized with weights considered

   Output: analysis_report with weighted_findings (includes weight info)
   ```

5. **Analysis Report Format (output):**
   ```yaml
   analysis_report:
     id: "analysis_{N}_{purpose}"
     target_step: "step_{M}_{role}"
     mode: "review|audit|validation"
     merge_strategy: "union|consensus|weighted"
     perspectives: {count}
     agents: ["security", "backend", "architect"]
     timestamp: "{ISO 8601}"

     # Union output:
     findings:
       - agent: "security"
         severity: critical
         category: security
         location: "src/auth/login.py:42"
         finding: "SQL injection via unsanitized user input"
         recommendation: "Use parameterized queries"
         confidence: high

     # Consensus output (additional fields):
     consensus_items:
       - finding: "SQL injection risk in login"
         agreed_by: ["security", "backend"]
         severity: critical       # elevated to highest
         location: "src/auth/login.py:42"
         merged_recommendation: "..."
     minority_findings:
       - agent: "architect"
         finding: "..."
         note: "Only one perspective reported this"

     # Weighted output (additional fields):
     weighted_findings:
       - finding: "..."
         agent: "security"
         category: security
         base_severity: high
         weight: 1.0
         weighted_severity: 3.0
         recommendation: "..."

     # Always present:
     merged_summary: "Executive summary of all perspectives combined"
     action_items:
       - priority: critical
         action: "Fix SQL injection in login endpoint"
         assigned_to: "backend"     # suggested fixer role
         source_analysis: "analysis_1_security_review"
     statistics:
       total_findings: {N}
       by_severity: { critical: N, high: N, medium: N, low: N, info: N }
       by_agent: { security: N, backend: N }
       consensus_rate: "{N}%"        # only for consensus strategy
   ```

6. **Orchestrator Integration:**
   ```
   EXECUTING (analysis_groups dispatch):
     1. Target step completes → PHASE_CHECK → NEXT_PHASE
     2. Check plan.analysis_groups for groups targeting this step
     3. If found → dispatch analysis agents (parallel-dispatch.md protocol)
     4. Collect outputs
     5. Call analysis-merge.md merge logic
     6. Save analysis_report to evidence
     7. If critical findings → ESCALATION (PM must acknowledge)
     8. If high findings → log warning, continue
     9. Continue to next step

   Evidence path:
     .aid-o/04-engine/evidence/{epic_id}/{run_id}/analysis/
       analysis_{N}_{purpose}/
         raw_{agent}.yaml           # Raw agent output
         analysis_report.yaml       # Merged report
   ```

**Reference soubory:**
- Plan `D-011` — merge strategie design
- `skills/improvement-proposals.md` — improvement_notes format (reuse)
- `agents/{role}.md` — agent output format

**Acceptance:**
- [ ] 3 merge strategie definovany: union, consensus, weighted
- [ ] Kazda strategie ma jasny algoritmus (kroky 1-N)
- [ ] Consensus similarity scoring definovan
- [ ] Weighted default weights tabulka
- [ ] analysis_report format kompletni (findings + consensus/weighted variants + action_items + statistics)
- [ ] Orchestrator integration flow definovan (EXECUTING → dispatch → merge → evidence)
- [ ] Evidence cesty pro analysis outputs

---

### Phase 4: Plan Schema Update — `defaults/templates/plan.schema.json`

**Cil:** Rozsidit Plan JSON schema o `analysis_groups` top-level pole.

**Zmeny:**

1. Pridat `analysis_groups` property:
   ```json
   "analysis_groups": {
     "type": "array",
     "description": "Multi-perspective analysis groups — multiple agents analyze the same target from different perspectives",
     "items": {
       "type": "object",
       "required": ["id", "target", "agents", "mode", "merge_strategy"],
       "properties": {
         "id": {
           "type": "string",
           "pattern": "^analysis_[0-9]+_[a-z_]+$",
           "description": "Unique analysis group identifier",
           "examples": ["analysis_1_security_review", "analysis_2_db_validation"]
         },
         "target": {
           "type": "string",
           "description": "Step ID being analyzed",
           "examples": ["step_3_backend"]
         },
         "agents": {
           "type": "array",
           "items": {
             "type": "string",
             "enum": ["architect", "domain", "backend", "frontend", "qa", "security", "observability", "docs", "release"]
           },
           "minItems": 1,
           "description": "Agent roles performing the analysis"
         },
         "mode": {
           "type": "string",
           "enum": ["review", "audit", "validation"],
           "description": "Analysis mode — review (findings), audit (scoring), validation (pass/fail)"
         },
         "merge_strategy": {
           "type": "string",
           "enum": ["union", "consensus", "weighted"],
           "description": "How to merge findings from multiple agents"
         },
         "trigger": {
           "type": "string",
           "enum": ["auto", "manual"],
           "default": "auto",
           "description": "Whether this group was auto-generated or manually specified in EPIC"
         }
       },
       "additionalProperties": false
     }
   }
   ```

2. Schema `additionalProperties` uz je false → neni treba menit
3. `analysis_groups` je OPTIONAL (ne v `required`) — plany bez analysis_groups jsou validni

**Acceptance:**
- [ ] `analysis_groups` property v schema s kompletni definici
- [ ] Pattern pro ID, enum pro agents/mode/merge_strategy/trigger
- [ ] analysis_groups je optional
- [ ] Schema validuje spravne (valid plan s i bez analysis_groups)

---

### Phase 5: Plan-Epic Command Update — `commands/plan-epic.md`

**Cil:** Rozsidit existujici `/plan-epic` command o integraci s Planner skillem a analysis_groups generaci.

**Zmeny v existujicim souboru:**

1. **Step 2 (Analyze Steps) — rozsirit:**
   - Pridat referenci na `skills/planner.md` pro dependency graph construction
   - Pridat referenci na `skills/planner.md` pro parallel group detection
   - Existujici "Default Ordering Rules" presunout jako referenci na Planner skill (DRY)

2. **Step 2.5 (NEW — Analysis Groups Generation):**
   ```
   After building steps + dependencies + parallel_groups:
   1. Read skills/planner.md Section 4 (Analysis Groups Generation)
   2. Apply auto-trigger rules to each step:
      - For each step, check objective + outputs + allowed_paths
      - Match against rules (security, complexity, DB, API)
      - Generate analysis_groups entries
   3. Check EPIC for explicit analysis_groups (manual override)
   4. Merge auto + manual (manual takes precedence)
   5. Validate: all targets reference existing steps, all agents valid
   6. Add to Plan JSON
   ```

3. **Step 3 (Build Plan JSON) — rozsirit:**
   - Plan JSON template pridat `analysis_groups` pole
   - Self-validation pridat analysis_groups checks

4. **Step 6 (Present Output) — rozsirit:**
   ```
   Analysis groups: {count}
     - analysis_1_security_review: [security] → step_3_backend (auto)
     - analysis_2_db_validation: [backend, security] → step_3_backend (auto)
   ```

**Acceptance:**
- [ ] plan-epic.md referencuje skills/planner.md pro logiku
- [ ] Analysis groups auto-generace integrovana do flow
- [ ] Manual override z EPIC respektovan
- [ ] Plan JSON output obsahuje analysis_groups
- [ ] Prezentace planu zobrazuje analysis groups

---

### Phase 6: Run-Epic Command Update — `commands/run-epic.md`

**Cil:** Rozsidit EXECUTING state o analysis_groups dispatch a PHASE_CHECK o analysis merge. Integrace s parallel-dispatch.md a analysis-merge.md skills.

**Zmeny v existujicim souboru:**

1. **EXECUTING state — rozsirit o analysis_groups dispatch:**

   Po existujicim textu pro "For a parallel group:" pridat:

   ```
   For an analysis group (post-step):
   1. After target step passes PHASE_CHECK:
      a. Read plan.analysis_groups filtered by target == just-completed step
      b. If none → skip (proceed normally)
      c. For each matching analysis_group:
         i. Read skills/parallel-dispatch.md Section 2 (analysis_groups dispatch)
         ii. Read skills/analysis-merge.md for merge protocol
         iii. Prepare analysis prompts per agent:
              - Include target step output (evidence/steps/{target}/output.md)
              - Include target step diff (evidence/steps/{target}/diff.patch)
              - Include merge strategy context
              - Include mode (review|audit|validation)
         iv. Dispatch ALL analysis agents in single message
         v. Collect outputs
         vi. Apply merge strategy (skills/analysis-merge.md)
         vii. Generate analysis_report
         viii. Save to evidence/analysis/analysis_{N}_{purpose}/
   2. If analysis_report has critical findings → ESCALATION
   3. If analysis_report has high findings → log warning, PM notification
   4. Proceed normally (PHASE_CHECK → NEXT_PHASE)
   ```

2. **PHASE_CHECK state — rozsirit o parallel conflict detection:**

   Pridat za existujici kontroly:
   ```
   For parallel groups (additional checks):
   1. Read skills/parallel-dispatch.md Section 3 (Conflict Detection)
   2. Check cross-agent file modifications
   3. Dry-run merge (git merge --no-commit)
   4. If conflict → ESCALATION with conflict details
   5. If clean → proceed to merge
   ```

3. **Branch Management section — rozsirit:**

   Nahradit existujici jednoduchou branch sekci referencí na `skills/parallel-dispatch.md` Section 1:
   ```
   Branch management: See skills/parallel-dispatch.md for complete protocol.

   Summary:
   - epic/{epic_id}/main branch created at start
   - Sequential: step branch → merge to epic/main after pass
   - Parallel: all fork from epic/main → merge sequentially after all pass
   - Analysis: no branches (read-only)
   - Final: epic/{epic_id}/main → PR to main
   ```

4. **Evidence per step — rozsirit:**
   ```
   For analysis groups (additional evidence):
   - evidence/{epic_id}/{run_id}/analysis/analysis_{N}_{purpose}/raw_{agent}.yaml
   - evidence/{epic_id}/{run_id}/analysis/analysis_{N}_{purpose}/analysis_report.yaml
   ```

**Acceptance:**
- [ ] EXECUTING state handleuje analysis_groups po target step completion
- [ ] Analysis dispatch pouziva parallel-dispatch.md protocol
- [ ] Merge pouziva analysis-merge.md protocol
- [ ] Critical findings → ESCALATION
- [ ] PHASE_CHECK rozsiren o parallel conflict detection
- [ ] Branch management referencuje parallel-dispatch.md
- [ ] Evidence cesty pro analysis outputs

---

### Phase 7: Epic-Orchestration Skill Update — `skills/epic-orchestration.md`

**Cil:** Rozsidit state machine o analysis_groups handling v EXECUTING a PHASE_CHECK states. Pridat novy "ANALYSIS" sub-flow.

**Zmeny v existujicim souboru:**

1. **State Machine diagram — rozsirit:**
   - EXECUTING → po step completion, check for analysis_groups → dispatch
   - PHASE_CHECK → add "analysis results" check

2. **State Definitions table — rozsirit:**
   - EXECUTING: pridat "Dispatch analysis_groups post-step" do Entry Action
   - PHASE_CHECK: pridat "Merge analysis results, check for critical findings" do Entry Action

3. **Section 4. EXECUTING — rozsirit:**
   Pridat za "3. For parallel group:":
   ```
   4. Post-step analysis (analysis_groups):
      a. After step passes PHASE_CHECK, check plan.analysis_groups
      b. If analysis group targets this step → dispatch analysis agents
      c. Protocol: skills/parallel-dispatch.md (analysis dispatch)
      d. Merge: skills/analysis-merge.md (merge strategy from plan)
      e. Save analysis_report to evidence
      f. Critical findings → ESCALATION
   ```

4. **Evidence Store Structure — rozsirit:**
   ```
   analysis/                    # Multi-perspective analysis results
     analysis_{N}_{purpose}/
       raw_{agent}.yaml
       analysis_report.yaml
   ```

5. **Agent Dispatch Protocol — rozsirit:**
   Pridat "Analysis Group Dispatch" sekci:
   ```
   Analysis Group Dispatch:
   1. Analysis agents are read-only — they don't modify code
   2. All agents get same target step context
   3. Dispatch via parallel Task tool calls
   4. Outputs merged per strategy in plan.analysis_groups
   5. Reference: skills/parallel-dispatch.md, skills/analysis-merge.md
   ```

6. **Integration with Session Management — rozsirit:**
   Pridat bod:
   ```
   5. On analysis complete: log analysis_report summary to session file
   ```

**Acceptance:**
- [ ] State machine diagram rozsiren o analysis flow
- [ ] EXECUTING state popisuje analysis_groups dispatch
- [ ] PHASE_CHECK state popisuje analysis merge
- [ ] Evidence store rozsiren o analysis/ adresar
- [ ] Agent Dispatch Protocol rozsiren o Analysis Group Dispatch

---

### Phase 8: Run-Step Command Update — `commands/run-step.md`

**Cil:** Pridat `--analysis-group` parametr pro manualni spusteni analysis group.

**Zmeny:**

1. **Usage rozsirit:**
   ```
   /run-step <epic-id> <step-id> [--analysis-group <group-id>]
   ```

2. **Novy flow pro --analysis-group:**
   ```
   If --analysis-group provided:
   1. Load Plan JSON
   2. Find analysis_group by group-id
   3. Verify target step is "done" (from plan_progress.json)
   4. Dispatch analysis agents per parallel-dispatch.md protocol
   5. Merge per analysis-merge.md
   6. Save analysis_report to evidence
   7. Present report to PM
   ```

**Acceptance:**
- [ ] --analysis-group parametr funguje
- [ ] Validace: target step musi byt "done"
- [ ] Dispatch + merge protocol pouzit

---

### Phase 9: Plugin Integration + Cross-references

**Cil:** Registrovat nove skills v plugin.json, aktualizovat aid-help.md, a overit cross-reference konzistenci.

**Ukoly:**

1. **Update `plugin.json`:**
   - Pridat 3 skills: planner, parallel-dispatch, analysis-merge
   - Vysledek: 18 agents, 16 commands, 10 skills

2. **Update `commands/aid-help.md`:**
   - Pridat "Planning & Parallelization" sekci:
     - Jak Planner generuje Plan z EPICu
     - Dependency graph + parallel groups
     - Analysis groups — multi-perspective analysis
     - 3 merge strategie (union, consensus, weighted)
     - Auto-trigger pravidla
   - Pridat "Branch Management" sub-sekci

3. **Cross-reference verification:**
   - skills/planner.md referencuje plan-epic.md, plan.schema.json
   - skills/parallel-dispatch.md referencuje run-epic.md, epic-orchestration.md
   - skills/analysis-merge.md referencuje parallel-dispatch.md, improvement-proposals.md
   - plan-epic.md referencuje skills/planner.md
   - run-epic.md referencuje skills/parallel-dispatch.md, skills/analysis-merge.md
   - epic-orchestration.md referencuje vsechny 3 nove skills
   - plan.schema.json analysis_groups enums = agents v agents/

**Acceptance:**
- [ ] plugin.json registruje 10 skills
- [ ] aid-help.md pokryva Planner + Parallelization + Analysis Groups
- [ ] Vsechny cross-reference konzistentni

---

### Phase 10: Smoke Test

**Cil:** Overit kompletnost a konzistenci vsech deliverables.

**Test scenare:**

1. **File existence:**
   - 3 nove skill soubory existuji v skills/
   - plan.schema.json obsahuje analysis_groups
   - Vsechny modifikovane soubory aktualizovany

2. **Schema validation:**
   - Plan JSON BEZ analysis_groups → validni (backward compatible)
   - Plan JSON S analysis_groups → validni
   - Plan JSON s nevalidnim analysis_group (bad enum, missing required) → nevalidni

3. **Format consistency:**
   - skills/planner.md definuje dependency graph + parallel groups + auto-triggers + analysis_groups
   - skills/parallel-dispatch.md definuje branch strategy + dispatch + conflict detection
   - skills/analysis-merge.md definuje 3 strategie + report format + orchestrator integration

4. **Cross-reference check:**
   - Kazdy novy skill referencuje spravne soubory
   - Kazdy modifikovany soubor referencuje nove skills
   - analysis_groups.agents enum = plan.schema.json step.role enum

5. **Integration check:**
   - plan-epic.md flow zahrnuje analysis_groups generaci
   - run-epic.md EXECUTING handleuje analysis_groups
   - epic-orchestration.md popisuje analysis flow
   - run-step.md podporuje --analysis-group

**Acceptance:**
- [ ] 3 nove skill soubory existuji a nejsou prazdne
- [ ] plan.schema.json backward compatible (plany bez analysis_groups validni)
- [ ] Formaty konzistentni napric skills
- [ ] Cross-reference bez broken linku
- [ ] Integrace kompletni (plan-epic → run-epic → orchestration)

---

## DoD Gates

- [x] `skills/planner.md` definuje dependency graph, parallel groups, auto-triggers, analysis_groups generaci
- [x] `skills/parallel-dispatch.md` definuje branch strategy, dispatch protocol, conflict detection
- [x] `skills/analysis-merge.md` definuje 3 merge strategie (union, consensus, weighted) + analysis_report format
- [x] `plan.schema.json` rozsiren o `analysis_groups` (backward compatible)
- [x] `plan-epic.md` integruje Planner skill + analysis_groups generaci
- [x] `run-epic.md` EXECUTING handleuje analysis_groups dispatch + merge
- [x] `run-step.md` podporuje `--analysis-group` parametr
- [x] `epic-orchestration.md` rozsiren o analysis flow v EXECUTING + PHASE_CHECK
- [x] `plugin.json` registruje 10 skills (3 nove)
- [x] `aid-help.md` pokryva Planning + Parallelization + Analysis Groups
- [x] Branch management: sequential merge chain, parallel fork+merge, analysis read-only
- [x] Auto-trigger pravidla: security, complexity, DB, API → analysis_groups
- [x] Cross-reference verification prosla

## Architectural Notes

### Skill Hierarchy — Planning Layer

```
skills/planner.md                    # HOW to build Plan JSON
  ├── Dependency graph construction
  ├── Parallel group detection
  ├── Auto-trigger rules
  └── Analysis groups generation

skills/parallel-dispatch.md          # HOW to execute parallel work
  ├── Branch strategy
  ├── Parallel dispatch protocol
  ├── Conflict detection
  └── PHASE_CHECK extensions

skills/analysis-merge.md             # HOW to merge multi-perspective results
  ├── Union strategy
  ├── Consensus strategy
  ├── Weighted strategy
  └── Analysis report format
```

### Data Flow: Plan Generation

```
EPIC file
  → /plan-epic command
    → skills/planner.md (dependency graph + parallel groups)
    → skills/planner.md (auto-trigger rules)
    → analysis_groups generated
    → Plan JSON validated against plan.schema.json
    → Evidence: plan.json
```

### Data Flow: Analysis Groups Execution

```
Step X completes → PHASE_CHECK pass
  → Check plan.analysis_groups targeting step X
  → If found:
    → skills/parallel-dispatch.md (analysis dispatch protocol)
    → N agents analyze step X output (parallel Task tools)
    → Collect N analysis_output YAML
    → skills/analysis-merge.md (apply merge_strategy)
    → Consolidated analysis_report
    → evidence/analysis/analysis_{N}_{purpose}/
    → Critical findings? → ESCALATION
    → Proceed to NEXT_PHASE
```

### Relationship: parallel_groups vs analysis_groups

```
parallel_groups:
  - WHO: Different agents doing DIFFERENT work
  - WHEN: During EXECUTING (concurrent steps)
  - OUTPUT: Code changes (branches + merge)
  - EXAMPLE: backend + frontend implement different features in parallel

analysis_groups:
  - WHO: Different agents analyzing SAME target
  - WHEN: After target step passes PHASE_CHECK
  - OUTPUT: Reports only (evidence, no code changes)
  - EXAMPLE: security + architect + backend review backend's auth implementation
```

## Session Log

| Cas | Udalost |
|-----|---------|
| 2026-02-17 | Session file vytvoren, 10 phases definovano |
| 2026-02-17 | Phase 1-3: 3 nove skill soubory vytvoreny paralelne (planner 429L, parallel-dispatch 590L, analysis-merge 447L) |
| 2026-02-17 | Phase 4: plan.schema.json rozsiren o analysis_groups (backward compatible) |
| 2026-02-17 | Phase 5: plan-epic.md aktualizovan — Step 2.5 analysis groups, Planner reference |
| 2026-02-17 | Phase 6: run-epic.md aktualizovan — EXECUTING analysis dispatch, PHASE_CHECK conflict detection |
| 2026-02-17 | Phase 7: epic-orchestration.md aktualizovan — analysis flow, evidence structure, error handling |
| 2026-02-17 | Phase 8: run-step.md aktualizovan — --analysis-group parametr + kompletni flow |
| 2026-02-17 | Phase 9: plugin.json (10 skills) + aid-help.md (planning topic) aktualizovany |
| 2026-02-17 | Phase 10: Smoke test — 7/7 PASS (existence, format, schema, cross-refs, plugin, help, consistency) |

## Notes

- Tato session NEIMPLEMENTUJE agenty — vyuziva existujicich 18 agentu z Session 4.
- Hlavni focus: skills (Planner + Parallel Dispatch + Analysis Merge), schema, a integrace do commands.
- `plan-epic.md` uz ma zaklad — tato session ho rozsiruje, ne prepisuje.
- `run-epic.md` uz ma EXECUTING state s basic parallel dispatch — tato session pridava analysis_groups handling.
- Backward kompatibilita je kriticka — Plan JSON bez analysis_groups MUSI zustat validni.
- Branch management je "best effort" — pokud git operace selzou, orchestrace pokracuje (log warning).
- Analysis agenti NIKDY nemodifikuji kod — jsou read-only. To je klicovy rozdil od parallel_groups.

---

**Status:** active
**Last Updated:** 2026-02-17
**Completion:** 100%
