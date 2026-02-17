---
id: S-20260217-e7b3
type: new-feature
status: active
priority: high
started: 2026-02-17
epic_id: ADO-0001
epic_session: 4
epic_file: workspace/workflow/epics/active/EPIC-ADO-0001-BUILD-ORCHESTRATOR.md
plan_ref: workspace/workflow/plans/P-20260216-b3a1-aid-v2-workspace-agents-memory.md
ai_agent: Claude Opus 4.6
branch: session/S-20260217-e7b3-worker-agents
previous_session: workspace/sessions/active/S-20260216-c8d2-gates-engine-retry.md
---

# Session 4: Worker Agenti + Curator + Auditor + Scanner

## Objective

Implementovat kompletní agentní vrstvu AID orchestrátoru: 9 role-agentů (worker agents),
3 nové specialisty (Curator, Auditor, Project Scanner), skill pro improvement notes,
a aktualizovat playbooks o improvement_notes sekci.

Na konci session musí:
- 9 role-agentů existovat v `agents/` s jasnou identitou, capabilities, constraints a output format
- Každý role-agent produkovat `improvement_notes` jako součást výstupu
- Curator agent sbírat postřehy, deduplikovat, navrhovat vylepšení → backlog.md
- Auditor agent provádět 5 typů auditu s trend trackingem
- Project Scanner agent analyzovat projekt (quick + deep) → project-profile.yaml
- `skills/improvement-proposals.md` definovat standardní formát a collection protocol
- Všech 9 playbooks aktualizováno o `## Improvement Notes` sekci
- `plugin.json` registrovat 12 nových agentů + 1 nový skill

## Context / Prerekvizity

Session 1 dodala:
- Plugin scaffold, `defaults/playbooks/` (9 playbooks: architect, domain, backend, frontend, qa, security, observability, docs, release)
- `defaults/policies/decision-policies.yaml` — auto_decisions, escalation_triggers

Session 2 dodala:
- `commands/run-epic.md` — state machine loop s DISPATCH state (dispatchuje role agenty)
- `commands/run-step.md` — single step dispatch s agent assignment
- `commands/plan-epic.md` — Plan JSON generace s `agent_role` per step

Session 3 dodala:
- `agents/gate-fixer.md` — vzorový agent format (Identity, Capabilities, Constraints, Output Format, Workflow)
- `skills/gates-engine.md`, `skills/retry-engine.md` — gates a retry protocol

**Existující utility agenti (5):** code-reviewer, docs-reviewer, quality-gates-runner, session-validator, lessons-extractor
**Existující specialist agent (1):** gate-fixer

**Klíčový design:** Role-agenti jsou dispatchováni z `run-epic.md` DISPATCH state a `run-step.md`.
Každý step v Plan JSON má `agent_role` field. Orchestrátor čte agentův `.md` file a dispatchuje
ho přes Task tool s kontextem (EPIC, step spec, allowed_paths, playbook reference).

## Deliverables

- [ ] `skills/improvement-proposals.md` — Standardní format, collection protocol, deduplication
- [ ] `agents/architect.md` — Architect role agent
- [ ] `agents/domain.md` — Domain Expert role agent
- [ ] `agents/backend.md` — Backend Developer role agent
- [ ] `agents/frontend.md` — Frontend Developer role agent
- [ ] `agents/qa.md` — QA Engineer role agent
- [ ] `agents/security.md` — Security Specialist role agent
- [ ] `agents/observability.md` — Observability Engineer role agent
- [ ] `agents/docs-writer.md` — Documentation Writer role agent
- [ ] `agents/release.md` — Release Engineer role agent
- [ ] Update 9 playbooks — přidat `## Improvement Notes` sekci
- [ ] `agents/curator.md` — Curator agent (postřehy → backlog → proposals)
- [ ] `agents/auditor.md` — Auditor agent (5 typů auditu + trend tracking)
- [ ] `agents/project-scanner.md` — Project Scanner agent (quick + deep)
- [ ] Update `plugin.json` — registrace 12 nových agentů + 1 nový skill
- [ ] Update `commands/aid-help.md` — přidat nové agenty do přehledu
- [ ] Cross-reference verification — všechny registrace konzistentní

## Phases

### Phase 1: Improvement Proposals Skill — `skills/improvement-proposals.md`

**Cíl:** Definovat standardní formát pro `improvement_notes`, collection protocol, deduplication pravidla, a integraci s backlog.md. Tento skill je prerekvizita pro role agenty i Curatora.

**Skill musí definovat:**

1. **Improvement Notes Format (YAML):**
   ```yaml
   improvement_notes:
     - type: refactoring|performance|security|architecture|dx
       area: "cesta/k/souboru-nebo-modulu"
       observation: "Popis problému — co agent viděl"
       suggestion: "Konkrétní návrh řešení"
       priority: low|medium|high
       source_agent: "{agent_role}"
       source_step: "{step_id}"
   ```

2. **Kdy agent zapisuje improvement_notes:**
   - Vidí kód, který by šel zlepšit, ale není v scope jeho tasku
   - Najde potenciální bezpečnostní riziko mimo svůj scope
   - Identifikuje architekturní pattern, který by měl být konzistentnější
   - Vidí duplicitní kód, který by šel zrefaktorovat
   - Zaregistruje DX problém (chybějící typy, nejasné API, chybějící docs)
   - **NESMÍ** zapisovat notes o svém vlastním tasku (to řeší v implementaci)

3. **Collection Protocol (pro Curatora):**
   ```
   1. Po každém session-end:
      - Čti evidence/{epic_id}/{run_id}/steps/*/step_output.json
      - Extrahuj improvement_notes ze všech step outputs
      - Merguj do jednoho seznamu
   2. Čti existující backlog.md
   3. Čti existující lessons-learned.md
   4. Deduplication:
      - Porovnej (type + area + observation) s existujícími entries
      - Pokud existuje → přidej source_agent/step jako nový zdroj (víc agentů vidí totéž = vyšší priorita)
      - Pokud nový → přidej do pending queue
   5. Priority escalation:
      - 3+ agentů reportuje stejný problém → auto-escalate priority na high
      - security typ → minimum priority medium
   ```

4. **Backlog.md Format:**
   ```markdown
   # Backlog

   ## Active Proposals (čeká na PM)
   | ID | Type | Area | Suggestion | Priority | Sources | Status |
   |-----|------|------|-----------|----------|---------|--------|
   | IMP-001 | refactoring | src/auth/ | Extract token logic | high | architect,backend | pending |

   ## Deferred
   | ID | Type | Area | Suggestion | Reason | Date |

   ## Rejected
   | ID | Type | Area | Suggestion | Rejected by | Reason | Date |

   ## Implemented
   | ID | Type | Area | Epic Ref | Date |
   ```

5. **ID Schema:** `IMP-{NNN}` — auto-incrementing, nikdy se nereusuje

**Reference soubory:**
- Plan `D-004` (Curator Agent — flow)
- Plan `D-010` (Improvement Notes Skill — formát)
- `defaults/policies/decision-policies.yaml` (auto_decisions)

**Acceptance:**
- [ ] YAML formát pro improvement_notes je kompletně specifikován
- [ ] Collection protocol jasně definuje kroky pro Curatora
- [ ] Deduplication pravidla pokrývají exact match i similar match
- [ ] Backlog.md formát s ID schema definován
- [ ] Priority escalation pravidla definována

---

### Phase 2: 9 Role Agentů — `agents/{role}.md`

**Cíl:** Vytvořit 9 role-agent definic. Každý agent má jasnou identitu, capabilities, constraints, output formát a workflow. Agenti jsou dispatchováni orchestrátorem přes Task tool.

**Společná struktura (pro všech 9 agentů):**

```markdown
# {Role Name} Agent

**Role:** {one-line mission}
**Type:** Role agent — dispatched by Controller during EPIC execution.
**Playbook:** `defaults/playbooks/{role}.md`

---

## Identity
"You are the **{Role}** agent..." — kdo jsi, co děláš, co NEDĚLÁŠ.

## Capabilities
Konkrétní seznam toho, co agent umí (per-role specific).

## Constraints — CRITICAL
- Scope enforcement: ONLY modify `allowed_paths` from step spec
- NEVER modify `forbidden_paths`
- NEVER implement outside your role boundary
- ...per-role specific constraints

## Input
Co agent dostává od orchestrátoru (step spec, EPIC context, etc.)

## Output Format
```yaml
step_output:
  step_id: "{step_id}"
  agent: "{role}"
  status: "completed|partial|blocked"
  artifacts:
    - path: "path/to/created/file"
      description: "What this file is"
  summary: "One paragraph of what was done"
  improvement_notes:        # POVINNÉ — vždy přítomné (může být prázdný list)
    - type: ...
      area: ...
      observation: ...
      suggestion: ...
      priority: ...
```

## Workflow
1. RECEIVE step spec from orchestrator
2. READ playbook (defaults/playbooks/{role}.md)
3. READ relevant context (EPIC, existing code, prior steps)
4. EXECUTE task per playbook
5. RECORD improvement_notes (co viděl mimo svůj scope)
6. OUTPUT step_output YAML block
```

**9 agentů a jejich specifika:**

#### 2a. `agents/architect.md` — Architect Agent
- **Mission:** Design API/event contracts, write ADRs, define module boundaries
- **Capabilities:** ADR writing, OpenAPI spec, event schema, boundary definition, dependency analysis
- **Specific constraints:** NEVER write implementation code, only contracts/specs
- **Key output:** ADR markdown, OpenAPI YAML, boundary diagrams (Mermaid)
- **Improvement focus:** architecture, refactoring patterns

#### 2b. `agents/domain.md` — Domain Expert Agent
- **Mission:** Model business domain, define entities/aggregates, validate business rules
- **Capabilities:** Domain modeling (DDD), entity/aggregate design, business rule validation, ubiquitous language
- **Specific constraints:** NEVER mix domain logic with infrastructure, maintain clean domain layer
- **Key output:** Domain model files, entity definitions, validation rules
- **Improvement focus:** architecture, dx (domain clarity)

#### 2c. `agents/backend.md` — Backend Developer Agent
- **Mission:** Implement server-side logic, APIs, data access, integrations
- **Capabilities:** API implementation, DB queries, service layer, middleware, error handling
- **Specific constraints:** Follow API contracts from architect, respect domain model
- **Key output:** Source files (controllers, services, repositories, middleware)
- **Improvement focus:** performance, refactoring, security (backend-specific)

#### 2d. `agents/frontend.md` — Frontend Developer Agent
- **Mission:** Implement UI components, pages, client-side logic
- **Capabilities:** Component development, state management, routing, API integration, responsive design
- **Specific constraints:** Follow design system/style guide, use API contracts from architect
- **Key output:** Components, pages, hooks, styles, tests
- **Improvement focus:** performance, dx, refactoring (frontend-specific)

#### 2e. `agents/qa.md` — QA Engineer Agent
- **Mission:** Write tests, validate quality, ensure coverage
- **Capabilities:** Unit tests, integration tests, E2E tests, test data generation, coverage analysis
- **Specific constraints:** NEVER modify implementation code (only tests), tests must be deterministic
- **Key output:** Test files, test fixtures, coverage reports
- **Improvement focus:** refactoring (test structure), dx (test clarity)

#### 2f. `agents/security.md` — Security Specialist Agent
- **Mission:** Audit security, fix vulnerabilities, implement security controls
- **Capabilities:** OWASP analysis, secret scanning, input validation, auth/authz review, dependency audit
- **Specific constraints:** NEVER introduce security workarounds, ALWAYS document security decisions
- **Key output:** Security findings, fixes, security-related code changes
- **Improvement focus:** security (primary), architecture (auth patterns)

#### 2g. `agents/observability.md` — Observability Engineer Agent
- **Mission:** Add logging, metrics, tracing, health checks, alerting
- **Capabilities:** Structured logging, metrics instrumentation, distributed tracing, health endpoints, dashboard config
- **Specific constraints:** Minimal performance impact, structured logs only (no console.log), follow correlation ID pattern
- **Key output:** Logging setup, metrics config, health endpoints, dashboards
- **Improvement focus:** performance (observability overhead), dx (debugging capability)

#### 2h. `agents/docs-writer.md` — Documentation Writer Agent
- **Mission:** Write and update documentation — API docs, guides, changelogs
- **Capabilities:** API documentation, user guides, developer guides, CHANGELOG, README updates, JSDoc/docstring
- **Specific constraints:** NEVER write inaccurate docs, all code examples must be tested/verified, maintain existing doc structure
- **Key output:** Markdown docs, CHANGELOG entries, inline docs
- **Improvement focus:** dx (documentation gaps), architecture (undocumented patterns)

#### 2i. `agents/release.md` — Release Engineer Agent
- **Mission:** Prepare releases — versioning, changelog, migration scripts, deployment config
- **Capabilities:** SemVer versioning, changelog generation, migration script writing, CI/CD config, deployment manifest
- **Specific constraints:** NEVER skip version bump, ALWAYS document breaking changes, migration scripts must be reversible
- **Key output:** Version files, CHANGELOG, migration scripts, deployment configs
- **Improvement focus:** dx (release process), architecture (deployment patterns)

**Reference soubory:**
- `agents/gate-fixer.md` — vzorový agent format (Identity, Capabilities, Constraints, Output, Workflow)
- `defaults/playbooks/*.md` — role playbooks (reference pro capabilities)
- `skills/improvement-proposals.md` (Phase 1) — improvement_notes format
- `commands/run-step.md` — jak orchestrátor dispatchuje agenty
- `skills/epic-orchestration.md` — DISPATCH state

**Acceptance:**
- [ ] 9 agent souborů existuje v `agents/`
- [ ] Každý agent má: Identity, Capabilities, Constraints, Input, Output Format, Workflow
- [ ] Každý agent output obsahuje povinný `improvement_notes` field
- [ ] Scope enforcement (allowed_paths/forbidden_paths) ve všech agentech
- [ ] Každý agent referencuje svůj playbook
- [ ] Agent constraints odpovídají roli (architect NEVER implements, qa NEVER modifies impl)
- [ ] Formát konzistentní s gate-fixer.md (zachovat styl)

---

### Phase 3: Playbook Updates — `defaults/playbooks/*.md`

**Cíl:** Přidat `## Improvement Notes` sekci do všech 9 playbooks, aby agenti věděli JAK a KDY zapisovat improvement_notes.

**Nová sekce (přidat na konec každého playbooku):**

```markdown
## Improvement Notes

During your work, record observations about code/architecture outside your current scope.

**Format:** (per `skills/improvement-proposals.md`)
```yaml
improvement_notes:
  - type: refactoring|performance|security|architecture|dx
    area: "path/to/module"
    observation: "What you observed"
    suggestion: "What should be done"
    priority: low|medium|high
```

**When to record:**
- Code that could be improved but is NOT in your current task scope
- Patterns that violate project conventions
- Security risks you notice but aren't tasked to fix
- Missing documentation for important features
- Performance bottlenecks you observe

**When NOT to record:**
- Issues you're actively fixing (that's your task)
- Style preferences without objective backing
- Suggestions that would require complete rewrite
```

**Role-specific guidance per playbook:**

| Playbook | Focus areas |
|----------|------------|
| architect.md | architecture patterns, module boundaries, contract violations |
| domain.md | domain model leaks, business rule inconsistencies |
| backend.md | performance issues, error handling gaps, security patterns |
| frontend.md | accessibility issues, performance (bundle size, re-renders), UX patterns |
| qa.md | untestable code, missing test infrastructure, flaky test patterns |
| security.md | OWASP findings, secret management, auth gaps |
| observability.md | missing metrics, unstructured logs, tracing gaps |
| docs.md | outdated docs, missing API docs, broken examples |
| release.md | deployment risks, missing migrations, version inconsistencies |

**Acceptance:**
- [ ] Všech 9 playbooks má `## Improvement Notes` sekci
- [ ] Každý playbook má role-specific guidance (focus areas)
- [ ] Format je konzistentní s `skills/improvement-proposals.md`

---

### Phase 4: Curator Agent — `agents/curator.md`

**Cíl:** Vytvořit Curator agenta — sbírá improvement_notes z agentů, deduplikuje proti existujícímu backlogu, brainstormuje řešení, a navrhuje vylepšení Orchestrátoru.

**Agent musí definovat:**

1. **Identity:**
   - "You are the **Curator** agent. You collect improvement observations from all worker agents,
     analyze patterns, deduplicate against known issues, and propose concrete improvements
     to the Orchestrator."
   - Type: Specialist agent (not role agent — runs post-session, not per-step)

2. **Timing:** Automaticky po každém `session-end` (volaný z session-management.md nebo run-epic.md POST_PROCESSING)

3. **Input:**
   - `evidence/{epic_id}/{run_id}/steps/*/step_output.json` → improvement_notes
   - `.aid-o/04-engine/backlog.md` → existující entries
   - `.aid-o/04-engine/lessons-learned.md` → historické znalosti

4. **Workflow:**
   ```
   1. COLLECT improvement_notes z všech step outputs v posledním runu
   2. DEDUPLICATE proti backlog.md (dle type + area + observation similarity)
      - Exact match → přidej source (víc zdrojů = vyšší signál)
      - Similar match → merguj, uprav priority pokud víc zdrojů
      - New → přidej do pending queue
   3. ANALYZE patterns:
      - 3+ notes na stejný area → "hotspot" — zvýšit prioritu
      - Security typ → minimum medium priority
      - Opakující se across sessions → persistent issue
   4. BRAINSTORM concrete actions:
      - Pro každý nový/escalated note → navrhnout konkrétní akci
      - Odhadnout effort (small/medium/large)
      - Identifikovat závislosti na jiných changes
   5. UPDATE backlog.md:
      - Přidej nové entries s IMP-{NNN} ID
      - Aktualizuj existující entries (nové zdroje, priority changes)
   6. GENERATE proposals pro Orchestrátor:
      - Vyber notes s priority high nebo s 3+ zdroji
      - Formátuj jako proposal s cost/benefit analýzou
   7. OUTPUT curator report
   ```

5. **Output Format:**
   ```yaml
   curator_report:
     session_id: "{session_id}"
     notes_collected: {N}
     notes_new: {N}
     notes_deduplicated: {N}
     notes_escalated: {N}
     hotspots:
       - area: "src/auth/"
         note_count: 4
         types: [security, refactoring, architecture]
     proposals:
       - id: "IMP-{NNN}"
         title: "Extract authentication middleware"
         type: refactoring
         area: "src/auth/"
         rationale: "4 agents noted duplicated auth logic across 3 routes"
         proposed_action: "Create shared auth middleware, refactor routes"
         effort: small|medium|large
         priority: high
         sources: [backend, security, architect]
     backlog_updates:
       added: [{id, type, area}]
       escalated: [{id, old_priority, new_priority}]
       deduplicated: [{id, merged_with}]
   ```

6. **Orchestrátor Integration:**
   ```
   Curator → curator_report → Orchestrátor
     Orchestrátor evaluuje proposals:
     ├── ZAMÍTNE → backlog.md (status: orchestrator-rejected, důvod)
     │     + info pro PM (Slack v Session 6, chat nyní)
     └── SCHVÁLÍ → proposal pro PM
           + PM rozhodne (Slack v Session 6, chat nyní):
             ├── PM SCHVÁLÍ → nový Epic
             ├── PM ODLOŽÍ → backlog.md (status: deferred)
             └── PM ZAMÍTNE → backlog.md (status: pm-rejected)
   ```

7. **Constraints:**
   - NEVER modifikuje kód — pouze analyzuje a navrhuje
   - NEVER escaluje přímo na PM — vše přes Orchestrátor
   - ALWAYS zachovává historii v backlog.md (nikdy nesmaže entries)
   - Priority escalation rules jsou striktní (viz improvement-proposals.md)

**Reference soubory:**
- Plan `D-004` (Curator Agent — kompletní flow)
- `skills/improvement-proposals.md` (Phase 1) — collection protocol
- `skills/session-management.md` — session-end flow
- `skills/epic-orchestration.md` — POST_PROCESSING state

**Acceptance:**
- [ ] Curator agent definice pokrývá celý collection → deduplication → proposal flow
- [ ] Output format strukturovaný (curator_report YAML)
- [ ] Backlog.md update logic jasně definovaná
- [ ] Orchestrátor integration flow definován
- [ ] Constraints zabraňují přímé PM komunikaci
- [ ] Hotspot detection logic definována (3+ notes = hotspot)

---

### Phase 5: Auditor Agent — `agents/auditor.md`

**Cíl:** Vytvořit Auditor agenta — provádí komplexní audit projektu po každém dokončeném Epicu.

**Agent musí definovat:**

1. **Identity:**
   - "You are the **Auditor** agent. You perform comprehensive post-Epic audits to assess
     project health, identify trends, and ensure quality standards are maintained."
   - Type: Specialist agent (runs post-Epic, not per-step)

2. **Timing:** Automaticky po Epic DONE (post-merge) — volaný z epic-orchestration.md DONE state

3. **5 Typů Auditu:**

   **A) Code Audit:**
   - Kvalita kódu: patterns, anti-patterns, duplicity, complexity
   - Metriky: LOC, cyklomatická komplexita, duplicity ratio
   - Doporučení: refactoring targets, pattern violations
   - Nástroje: custom analysis (grep patterns, file analysis)

   **B) Security Audit:**
   - OWASP Top 10 check
   - Hardcoded secrets scan
   - Dependency vulnerabilities (known CVEs)
   - Auth/authz review
   - Input validation review
   - Nástroje: pattern matching, dependency check

   **C) Documentation Audit:**
   - API docs vs actual endpoints (drift detection)
   - README aktualnost
   - Missing docs for new features
   - Broken links, outdated examples
   - CHANGELOG completeness

   **D) Frontend Audit (conditional — pokud projekt má frontend):**
   - Accessibility check (basic a11y patterns)
   - Bundle size analysis
   - Performance patterns (unnecessary re-renders, missing lazy loading)
   - Component structure consistency

   **E) Database Audit (conditional — pokud projekt má DB):**
   - Migration consistency
   - Index coverage for queries
   - N+1 query patterns
   - Schema documentation

4. **Audit Report Format:**
   ```yaml
   audit_report:
     epic_id: "{epic_id}"
     timestamp: "{ISO 8601}"
     auditor: "auditor-agent"
     project_score:
       overall: {0-100}
       code_quality: {0-100}
       security: {0-100}
       documentation: {0-100}
       frontend: {0-100}|null       # null pokud N/A
       database: {0-100}|null       # null pokud N/A
     findings:
       critical:
         - area: "src/auth/login.py"
           type: security
           finding: "SQL injection via unsanitized user input"
           recommendation: "Use parameterized queries"
       high:
         - area: "src/api/"
           type: code_quality
           finding: "3 endpoints missing error handling"
           recommendation: "Add try/except with proper error responses"
       medium: [...]
       low: [...]
     trend:
       previous_score: {0-100}|null  # null pokud první audit
       score_delta: {+/-N}|null
       new_findings: {N}
       resolved_findings: {N}
       persistent_findings: {N}
     summary: "One paragraph executive summary"
     recommended_actions:
       - priority: critical|high
         action: "Fix SQL injection in login endpoint"
         estimated_effort: small|medium|large
   ```

5. **Trend Tracking:**
   - Načíst předchozí audit report z `evidence/{previous_epic_id}/audit-report.md`
   - Porovnat scores (overall + per-category)
   - Identifikovat: zlepšení, zhoršení, persistentní problémy
   - Score trend → do audit report `trend` sekce

6. **Integration Flow:**
   ```
   Epic DONE → merge
     → Auditor agent běží (post-merge)
     → audit_report → evidence/{epic_id}/audit-report.md (YAML + Markdown)
     → findings → Orchestrátor validuje
       ├── Orchestrátor schválí → Curator zpracuje do backlogu
       └── Orchestrátor zamítne → zaloguje + info PM
     → Summary → PM (chat nyní, Slack v Session 6)
   ```

7. **Constraints:**
   - NEVER modifikuje kód — pouze audituje a reportuje
   - ALWAYS porovnává s předchozím auditem (trend tracking)
   - Critical findings → ALWAYS reportuje (nikdy nepřeskočí)
   - Conditional audity (frontend, database) → spouští JEN pokud relevantní
   - Scores musí být reprodukovatelné (jasná metodika)

**Reference soubory:**
- Plan `D-005` (Audit Agent — kompletní spec)
- `skills/epic-orchestration.md` — DONE state (kde se audit spouští)
- `defaults/policies/gates.yaml` — security scan patterns (reuse)
- Existující audit templates z C.I.C.E.R.O. (pokud relevantní)

**Acceptance:**
- [ ] Auditor agent definice pokrývá 5 typů auditu
- [ ] Audit report format s scoring (0-100) a findings per severity
- [ ] Trend tracking — porovnání s předchozím auditem
- [ ] Conditional audity (frontend/database) s jasnou podmínkou
- [ ] Integration flow: Auditor → Orchestrátor → Curator/PM
- [ ] Constraints zabraňují modifikaci kódu

---

### Phase 6: Project Scanner Agent — `agents/project-scanner.md`

**Cíl:** Vytvořit Project Scanner agenta — analyzuje projekt ve dvou režimech: quick scan (onboarding) a deep analysis (milestones).

**Agent musí definovat:**

1. **Identity:**
   - "You are the **Project Scanner** agent. You analyze projects to understand their
     tech stack, architecture, conventions, and quality metrics. You produce structured
     profiles that inform other agents and the Orchestrator."
   - Type: Specialist agent (on-demand, not per-step)

2. **Dva režimy:**

   **A) Quick Scan (při onboardingu — `/aid-setup`):**
   - Detekce: tech stack, build system, test framework, CI/CD
   - Analýza: adresářová struktura, hlavní frameworky, package managers
   - Detekce: monorepo vs single repo, frontend/backend split
   - Výstup: `project-profile.yaml`
   - Trvání: rychlé (minuty)

   **Quick scan protocol:**
   ```
   1. READ root files: package.json, pyproject.toml, Cargo.toml, go.mod,
      Dockerfile, docker-compose.yml, .gitignore, README.md
   2. DETECT tech stack:
      - Language(s): JS/TS, Python, Rust, Go, Java, etc.
      - Framework(s): React, Next.js, Django, FastAPI, etc.
      - Build system: npm, yarn, pnpm, pip, cargo, etc.
      - Test framework: jest, pytest, etc.
      - CI/CD: GitHub Actions, GitLab CI, etc.
   3. ANALYZE directory structure:
      - src/, lib/, app/, pages/, components/, tests/, docs/
      - Identify architectural pattern (MVC, hexagonal, etc.)
   4. DETECT conventions:
      - Naming: camelCase, snake_case, kebab-case
      - File organization: by feature, by layer, hybrid
   5. OUTPUT project-profile.yaml
   ```

   **B) Deep Analysis (milestone/on-demand):**
   - Vše z quick scan PLUS:
   - Code quality metriky (LOC, complexity, duplicity)
   - Dependency audit (outdated, vulnerable, unused)
   - Architekturní patterns a anti-patterns
   - Tech debt odhad (high/medium/low areas)
   - Test coverage analýza
   - Security posture overview
   - Výstup: rozšířený `project-profile.yaml` + `deep-analysis-report.md`
   - Trvání: delší

3. **Project Profile Format:**
   ```yaml
   # project-profile.yaml
   project:
     name: "{project_name}"
     scan_type: "quick|deep"
     scanned_at: "{ISO 8601}"

   tech_stack:
     languages:
       - name: "TypeScript"
         version: "5.3"
         primary: true
       - name: "Python"
         version: "3.12"
         primary: false
     frameworks:
       - name: "Next.js"
         version: "14.x"
         type: "frontend"
       - name: "FastAPI"
         version: "0.109"
         type: "backend"
     build_system: "npm"
     test_framework: "jest + pytest"
     ci_cd: "GitHub Actions"
     package_managers: ["npm", "pip"]

   architecture:
     pattern: "monorepo|single|micro"
     structure: "by-feature|by-layer|hybrid"
     directories:
       source: ["src/", "app/"]
       tests: ["tests/", "__tests__/"]
       docs: ["docs/"]
       config: [".github/", "docker/"]
     frontend_backend_split: true

   conventions:
     naming: "camelCase|snake_case|kebab-case"
     file_organization: "by-feature"
     commit_style: "conventional|free-form"
     branch_strategy: "git-flow|trunk|github-flow"

   # Deep scan only:
   quality:                              # null for quick scan
     loc: {N}
     test_coverage: "{N}%"
     complexity:
       average: {N}
       hotspots: ["file1.py", "file2.ts"]
     duplicity: "{N}%"
     tech_debt: "low|medium|high"
     tech_debt_areas:
       - area: "src/legacy/"
         severity: high
         description: "Unmigrated jQuery code"
   ```

4. **Constraints:**
   - NEVER modifikuje soubory — pouze čte a analyzuje
   - Quick scan musí být rychlý — NEčte obsah všech souborů, jen klíčové
   - Deep analysis může číst více souborů ale s rozumným limitem
   - Výstup vždy do `.aid-o/04-engine/memory/project-profile.yaml`
   - Deep analysis report: `.aid-o/04-engine/evidence/{context}/deep-analysis-report.md`

5. **Integration:**
   - Volaný z `/aid-setup` (quick scan) — plan D-007
   - Volaný on-demand z Orchestrátoru (deep analysis po milestones)
   - Výstup čtený dalšími agenty pro kontext

**Reference soubory:**
- Plan `D-006` (Project Scanner Agent)
- Plan `D-007` (`/aid-setup` Command — volá scanner)
- `commands/aid-setup.md` — onboarding flow

**Acceptance:**
- [ ] Quick scan mode: detekuje tech stack, structure, conventions → project-profile.yaml
- [ ] Deep analysis mode: přidává quality metriky, dependencies, tech debt → extended profile + report
- [ ] project-profile.yaml formát kompletně specifikován
- [ ] Constraints: read-only, quick scan je rychlý
- [ ] Integration s `/aid-setup` definována

---

### Phase 7: Plugin Integration + Cross-references

**Cíl:** Registrovat všechny nové artefakty v plugin.json, aktualizovat aid-help.md a ověřit cross-reference konzistenci.

**Úkoly:**

1. **Aktualizovat `plugin.json`:**
   - Přidat 9 role agents: architect, domain, backend, frontend, qa, security, observability, docs-writer, release
   - Přidat 3 specialist agents: curator, auditor, project-scanner
   - Přidat 1 skill: improvement-proposals
   - Aktualizovat counts
   - **Výsledek:** 18 agents (6 utility + 3 specialist + 9 role), 16 commands, 7 skills

2. **Aktualizovat `commands/aid-help.md`:**
   - Přidat sekci "Worker Agents" s přehledem 9 role-agentů
   - Přidat sekci "Specialist Agents" (Curator, Auditor, Scanner)
   - Popsat improvement_notes flow
   - Popsat audit flow

3. **Aktualizovat `skills/epic-orchestration.md`:**
   - DISPATCH state — reference na nové role agenty
   - POST_PROCESSING state — přidat Curator invocation
   - DONE state — přidat Auditor invocation

4. **Cross-reference verification:**
   - Každý agent v plugin.json → soubor existuje
   - Každý skill v plugin.json → soubor existuje
   - Každý agent referencuje správný playbook → playbook existuje
   - improvement_notes formát konzistentní mezi: skill, agents, playbooks

**Acceptance:**
- [ ] plugin.json registruje 12 nových agentů + 1 nový skill
- [ ] aid-help.md zmiňuje všech 18 agentů + improvement_notes + audit flow
- [ ] epic-orchestration.md referencuje Curator (POST_PROCESSING) a Auditor (DONE)
- [ ] Všechny cross-reference konzistentní (žádné broken references)

---

### Phase 8: Smoke Test

**Cíl:** Ověřit kompletnost a konzistenci všech deliverables.

**Test scénáře:**

1. **File existence:** Všech 12 nových agent souborů existuje v agents/
2. **Plugin consistency:** plugin.json counts odpovídají skutečným souborům
3. **Format consistency:**
   - Každý role-agent má povinné sekce (Identity, Capabilities, Constraints, Input, Output, Workflow)
   - Každý role-agent output obsahuje improvement_notes field
   - Curator, Auditor, Scanner mají správný output format
4. **Playbook consistency:** Všech 9 playbooks má Improvement Notes sekci
5. **Cross-references:**
   - Role agents → playbooks (správné cesty)
   - Curator → improvement-proposals.md, backlog.md
   - Auditor → evidence paths, trend tracking
   - Scanner → project-profile.yaml
6. **Skill completeness:** improvement-proposals.md pokrývá format + collection + deduplication

**Acceptance:**
- [ ] 12 nových agent souborů existuje a není prázdných
- [ ] plugin.json registruje 18 agents, 16 commands, 7 skills
- [ ] 9 playbooks aktualizováno
- [ ] Cross-references bez broken linků
- [ ] Formáty konzistentní napříč agenty

---

## DoD Gates

- [ ] 9 role-agentů existuje v `agents/` s kompletní strukturou
- [ ] 3 specialist agenti (Curator, Auditor, Scanner) existují s kompletní spec
- [ ] `skills/improvement-proposals.md` definuje format + collection + deduplication + backlog
- [ ] Každý role-agent produkuje `improvement_notes` v output
- [ ] Curator flow: collect → deduplicate → analyze → propose → Orchestrátor
- [ ] Auditor flow: 5 audit typů + scoring + trend tracking + report
- [ ] Scanner flow: quick scan → project-profile.yaml, deep analysis → report
- [ ] 9 playbooks aktualizováno o Improvement Notes sekci
- [ ] `plugin.json` registruje 18 agents, 16 commands, 7 skills
- [ ] `aid-help.md` pokrývá nové agenty a flows
- [ ] `epic-orchestration.md` referencuje Curator (POST_PROCESSING) a Auditor (DONE)
- [ ] Cross-reference verification prošla (žádné broken links)
- [ ] Scope enforcement ve všech role-agentech (allowed_paths/forbidden_paths)

## Architectural Notes

### Agent Hierarchy

```
AID Orchestrátor (Controller)
  │
  ├── Role Agents (9) — dispatchováni per-step v EPIC execution
  │   ├── architect.md      → contracts, ADRs
  │   ├── domain.md         → domain model, entities
  │   ├── backend.md        → server-side implementation
  │   ├── frontend.md       → UI implementation
  │   ├── qa.md             → tests, coverage
  │   ├── security.md       → security audit, fixes
  │   ├── observability.md  → logging, metrics, tracing
  │   ├── docs-writer.md    → documentation
  │   └── release.md        → versioning, deployment
  │
  ├── Specialist Agents (3) — triggered by specific events
  │   ├── curator.md         → post-session (improvement notes → backlog)
  │   ├── auditor.md         → post-Epic (comprehensive audit)
  │   └── project-scanner.md → on-demand (project analysis)
  │
  └── Utility Agents (6) — support functions
      ├── code-reviewer.md
      ├── docs-reviewer.md
      ├── quality-gates-runner.md
      ├── session-validator.md
      ├── lessons-extractor.md
      └── gate-fixer.md
```

### Data Flow: Improvement Notes

```
Role Agent (per step)
  → step_output.improvement_notes (YAML)
    → evidence/{epic_id}/{run_id}/steps/{step}/step_output.json

Session End
  → Curator agent triggered
    → Reads all step_output.json improvement_notes
    → Deduplicates vs backlog.md
    → Proposes to Orchestrátor
      → Orchestrátor → PM (approve/defer/reject)
        → backlog.md updated
```

### Data Flow: Post-Epic Audit

```
Epic DONE (post-merge)
  → Auditor agent triggered
    → Runs 5 audit types (2 conditional)
    → Generates audit_report (YAML + Markdown)
    → evidence/{epic_id}/audit-report.md
    → Compares with previous audit (trend)
    → Sends to Orchestrátor
      → Orchestrátor → Curator (findings → backlog)
      → Orchestrátor → PM (summary)
```

### Agent Output → Evidence Mapping

```
agents/{role}.md output:
  → step_output YAML block
    → evidence/{epic_id}/{run_id}/steps/{step_id}/
        step_output.json         # Full structured output
        artifacts/               # Created files (if any)

agents/curator.md output:
  → curator_report YAML
    → .aid-o/04-engine/backlog.md (updated)
    → evidence/{epic_id}/{run_id}/curator_report.json

agents/auditor.md output:
  → audit_report YAML + Markdown
    → evidence/{epic_id}/audit-report.md

agents/project-scanner.md output:
  → project-profile.yaml
    → .aid-o/04-engine/memory/project-profile.yaml
  → deep-analysis-report.md (deep mode only)
    → evidence/{context}/deep-analysis-report.md
```

## Session Log

| Čas | Událost |
|-----|---------|
| 2026-02-17 | Session file vytvořen, 8 phases definováno |
| 2026-02-17 | Phase 1 done: skills/improvement-proposals.md (320 lines — format, collection, dedup, backlog, proposals, orchestrator integration) |
| 2026-02-17 | Phases 2-6 dispatched in parallel via 5 subagents |
| 2026-02-17 | Phase 2 done: 9 role agents (architect, domain, backend, frontend, qa, security, observability, docs-writer, release) — each ~130-170 lines |
| 2026-02-17 | Phase 3 done: 9 playbooks updated with ## Improvement Notes section (role-specific guidance) |
| 2026-02-17 | Phase 4 done: agents/curator.md (240 lines — collect, dedup, analyze, propose, backlog management) |
| 2026-02-17 | Phase 5 done: agents/auditor.md (304 lines — 5 audit types, scoring 0-100, trend tracking, dual output) |
| 2026-02-17 | Phase 6 done: agents/project-scanner.md (246 lines — quick/deep modes, project-profile.yaml format) |
| 2026-02-17 | Phase 7 done: plugin.json (18 agents, 7 skills), aid-help.md (3 agent categories), epic-orchestration.md (Curator+Auditor in DONE) |
| 2026-02-17 | Phase 8 done: Smoke test — 159 checks, 0 failures, all cross-references valid |
| 2026-02-17 | **SESSION COMPLETED** |

## Notes

- Gate-fixer.md z Session 3 slouží jako vzorový formát pro agenty. Zachovat styl (Identity, Capabilities, Constraints, Output, Workflow).
- Playbooks již existují (Session 1). Tato session je pouze rozšiřuje o Improvement Notes — NEpřepisuje existující obsah.
- Curator a Auditor jsou "specialist" agenti — neběží per-step jako role agenti, ale na specifické eventy (session-end, epic-done).
- Project Scanner běží on-demand — primárně z `/aid-setup`, ale může být volaný i manuálně.
- Slack integrace pro Curator/Auditor přijde v Session 6. Nyní je komunikace s PM chat-based.
- `improvement_notes` je vždy přítomný field v output (může být prázdný list `[]`).

---

**Status:** completed
**Last Updated:** 2026-02-17
**Completion:** 100%

## Completion Summary

- **Duration:** 2026-02-17 (1 conversation)
- **Files created:** 13 (9 role agents + 3 specialist agents + 1 skill)
- **Files modified:** 13 (9 playbooks + plugin.json + aid-help.md + epic-orchestration.md + session file)
- **Total new lines:** ~3,500 (core deliverables)
- **Phases completed:** 8/8
- **What was accomplished:**
  - `skills/improvement-proposals.md` — Standard format, collection protocol, deduplication, backlog management, proposal generation, orchestrator integration (320 lines)
  - 9 role agents (`agents/{architect,domain,backend,frontend,qa,security,observability,docs-writer,release}.md`) — each with Identity, Capabilities, Constraints, Input, Output Format (with improvement_notes), Workflow
  - 9 playbooks updated — `## Improvement Notes` section with role-specific guidance added to all
  - `agents/curator.md` — Post-session specialist: collect, deduplicate, analyze patterns, propose improvements (240 lines)
  - `agents/auditor.md` — Post-Epic specialist: 5 audit types, scoring (0-100), trend tracking, dual output (304 lines)
  - `agents/project-scanner.md` — On-demand specialist: quick scan + deep analysis, project-profile.yaml (246 lines)
  - `plugin.json` — 18 agents, 16 commands, 7 skills registered
  - `commands/aid-help.md` — Updated agents topic with 3 categories (Role, Specialist, Utility)
  - `skills/epic-orchestration.md` — DONE state updated with Curator + Auditor POST-PROCESSING
  - Smoke test: 159 checks, 0 failures, all cross-references validated
