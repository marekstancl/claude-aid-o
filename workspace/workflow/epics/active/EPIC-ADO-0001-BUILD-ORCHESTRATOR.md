# EPIC: ADO-0001 — Build AID Orchestrator (Marketplace Plugin)

## Kontext

Existuje fungující single-agent framework (Agent Skills v4.0 pro C.I.C.E.R.O.)
s 5 subagenty, 8 commands, 11 skills, session managementem a quality gates.

Cílem je evoluce do Controller + Workers architektury jako **instalovatelný
Claude Code plugin** (`aid-orchestrator`), který lze použít na jakémkoliv projektu.
Orchestrátor autonomně řídí specializované agenty, kontroluje výstupy, provádí
gates a eskaluje na PM přes Slack jen když si neví rady.

Referenční dokumentace: `docs/MULTIAGENT_GUIDE.md`
Zdrojové materiály: `_unzipped/ado_starter_kit/`, `_unzipped/ai_dev_orchestrator_docs/`
Design plan: `workspace/workflow/plans/P-20260216-b3a1-aid-v2-workspace-agents-memory.md`

## Cíl

Postavit marketplace s pluginem `aid-orchestrator`, který:
1. Se nainstaluje přes `claude plugin install aid-orchestrator`
2. Příkazem `/aid-init` vytvoří `.aid-o/` strukturu v projektu
3. `/aid-setup` provede onboarding (nový i existující projekt)
4. Vezme Epic → vygeneruje Plan → dispatche agenty → gates → evidence
5. Curator sbírá postřehy → Orchestrátor validuje → PM přes Slack
6. Audit agent po každém Epicu → trend tracking
7. Qdrant MCP pro dlouhodobou vektorovou paměť

## Výstupní struktura — Plugin

```
ai-orchestrator/                       # Marketplace root
  marketplace.json                     # Registr pluginů
  plugins/
    aid-orchestrator/                  # Plugin: AID Orchestrator
      .claude-plugin/
        plugin.json                    # Plugin manifest
      agents/
        # 9 role-agents
        architect.md
        domain.md
        backend.md
        frontend.md
        qa.md
        security.md
        observability.md
        docs-writer.md
        release.md
        # 5 utility agents (přenesené z claude/)
        code-reviewer.md
        docs-reviewer.md
        quality-gates-runner.md
        session-validator.md
        lessons-extractor.md
        # 3 noví agenti
        curator.md                     # NOVÝ: sbírá postřehy, navrhuje vylepšení
        auditor.md                     # NOVÝ: milestone audit po Epicu
        project-scanner.md             # NOVÝ: quick/deep analýza projektu
      commands/
        # Nové AID commands
        aid-init.md                    # Vytvoří .aid-o/ strukturu
        aid-setup.md                   # NOVÝ: interaktivní onboarding
        aid-help.md                    # NOVÝ: self-knowledge, jak AID funguje
        plan-epic.md                   # Epic → Plan JSON + Session file
        run-epic.md                    # Hlavní orchestrační loop
        run-step.md                    # Manuální spuštění jednoho kroku
        epic-status.md                 # Zobrazení stavu
        # Přenesené z claude/
        quality-gates.md
        session-start.md
        session-end.md
        handoff.md
        audit.md
        coding-standards.md
        testing.md
        docs-protocol.md
      skills/
        epic-orchestration.md          # Controller state machine
        improvement-proposals.md       # NOVÝ: standardní format pro improvement_notes
        agent-core.md                  # Přenesený (zjednodušený)
        quality-gates.md               # Přenesený (zjednodušený)
        session-management.md          # Přenesený (zjednodušený)
      defaults/                        # Výchozí soubory pro /aid-init
        policies/
          gates.yaml
          decision-policies.yaml
        templates/
          plan.md                      # NOVÝ: plan template
          epic.md
          plan.schema.json
          session-bug-fix.md           # Přenesené z existujících
          session-new-feature.md
          session-refactoring.md
          session-exploration.md
        playbooks/
          architect.md ... release.md  # 9 role playbooks
      README.md
```

## Výstupní struktura — Co `/aid-init` vytvoří v projektu

```
cílový-projekt/
  .aid-o/
    01-plans/                          # PM + AI brainstorming
      archive/
    02-epics/                          # PM + AI detailní zadání
      archive/
    03-config/                         # PM-customizable
      policies/
        gates.yaml
        decision-policies.yaml
      templates/
        plan.md
        epic.md
        plan.schema.json
        session-bug-fix.md
        session-new-feature.md
        session-refactoring.md
        session-exploration.md
      playbooks/
        architect.md ... release.md
    04-engine/                         # AI interní
      sessions/
        archive/
      memory/
        active-work.md
        project-profile.yaml
        decisions.yaml
      backlog.md
      lessons-learned.md
      command-history.md
      evidence/
```

## Naming konvence

| Typ | Format | Příklad |
|-----|--------|---------|
| Plan | `P-{YYYYMMDD}-{4char-hash}-{topic}.md` | `P-20260216-b3a1-mvp-roadmap.md` |
| Epic | `E-{YYYYMMDD}-{4char-hash}-{topic}.md` | `E-20260216-c2d1-user-auth.md` |
| Session | `S-{YYYYMMDD}-{4char-hash}-{topic}.md` | `S-20260216-a1f0-foundation.md` |

## Scope

### Allowed files/paths
- plugins/aid-orchestrator/
- marketplace.json
- docs/
- workspace/

### Forbidden zones
- Žádné (nový projekt)

## Constraints
- Žádný externí framework (vše nativně v Claude Code plugin systém)
- Decision policies musí pokrývat 90%+ rozhodnutí bez PM
- Evidence by design — každý run produkuje audit trail
- Plugin musí být self-contained (žádné externí závislosti kromě Qdrant MCP)
- Existující agenti/commands/skills z claude/ se přenesou do pluginu
- Plan + Epic = PM + AI spolupráce; Session a dál = AI autonomně
- Vše prochází Orchestrátorem před PM
- Vše na PM jde přes Slack (i zamítnutí = info)

## DoD Gates
- Plugin se nainstaluje bez chyb
- `/aid-init` vytvoří kompletní `.aid-o/` strukturu
- `/aid-setup` provede onboarding (nový + existující projekt)
- Dummy EPIC projede celým pipeline end-to-end
- Všech 9 role-agentů funguje + improvement_notes
- Curator flow: postřehy → Orchestrátor → PM
- Audit agent: post-Epic audit report
- Gates engine vyhodnotí pass/fail + retry
- Evidence store kompletní
- Qdrant MCP memory funguje
- Dokumentace aktualizována

---

## Sessions

### Session 1: Plugin Scaffold + Controller State Machine ✅ (+ doplnění)

**Stav:** Hotová. Nutné doplnit rename ADO → AID a novou `.aid-o/` strukturu.

**Původní deliverables (DONE):**
- marketplace.json, plugin.json, agents/, commands/, skills/
- epic-orchestration.md (500 lines, 11 states)
- policies, templates, playbooks
- ado-init.md, README.md, CLAUDE.md

**Doplnění (z Plan P-20260216-b3a1):**
- [ ] Rename `ado-orchestrator` → `aid-orchestrator` (všechny soubory + reference)
- [ ] Rename `/ado-init` → `/aid-init`
- [ ] Aktualizovat `/aid-init` pro novou `.aid-o/` strukturu
- [ ] Přidat `defaults/templates/plan.md` (chybějící plan template)
- [ ] Přidat session templates do defaults/templates/
- [ ] Aktualizovat marketplace.json, plugin.json, CLAUDE.md

**Acceptance doplnění:**
- Všechny reference na "ado" přejmenovány na "aid"
- `/aid-init` vytvoří `.aid-o/` strukturu (01-plans, 02-epics, 03-config, 04-engine)
- Plan template existuje

---

### Session 2: EPIC Runner Commands + AID Commands

**Stav:** Hotová ✅. Session file: `workspace/sessions/completed/S-20260216-f47a-runtime-commands.md`

**Cíl:** 4 orchestrační commands + 2 nové AID commands.

**Deliverables:**
- `commands/plan-epic.md` — Epic → Plan JSON + Session file
- `commands/run-epic.md` — hlavní orchestrační loop (state machine)
- `commands/run-step.md` — manuální spuštění jednoho kroku
- `commands/epic-status.md` — zobrazení stavu pipeline
- `commands/aid-setup.md` — interaktivní onboarding (nový + existující projekt)
- `commands/aid-help.md` — self-knowledge, příkazy, workflow
- Aktualizace `plugin.json` — registrace 6 nových commands

**Phases (7):**
1. `/plan-epic` — EPIC Parser + Plan Generator
2. `/run-epic` — Orchestrační Loop (state machine)
3. `/run-step` — Manuální spuštění jednoho kroku
4. `/epic-status` — Zobrazení stavu pipeline
5. `/aid-setup` — Interaktivní onboarding
6. `/aid-help` — Self-Knowledge
7. Plugin Integration + Smoke Test

**Acceptance:**
- `/plan-epic` vytvoří validní Plan JSON z dummy EPICu (dle plan.schema.json)
- `/run-epic` implementuje state machine loop z epic-orchestration.md
- `/run-step` spustí jeden krok s mock agentem
- `/epic-status` zobrazí pipeline stav (steps, gates, budget)
- `/aid-setup` detekuje tech stack a nabídne setup
- `/aid-help` vypíše kompletní přehled AID fungování
- plugin.json registruje všech 15 commands
- Smoke test s EPIC-TEST-0001-DUMMY.md prošel

---

### Session 3: Gates Engine + Retry

**Stav:** Aktivní. Session file: `workspace/sessions/active/S-20260216-c8d2-gates-engine-retry.md`

**Cíl:** Gates engine (gates.yaml parsing + execution), pass/fail reports do evidence, retry loop s fix-agent dispatch (max 3 pokusy), escalation protocol. Koexistence s existujícím C.I.C.E.R.O. pre-commit gates systémem.

**Deliverables:**
- `skills/gates-engine.md` — Gates execution protocol (YAML parsing, command/rule execution, reporting)
- `skills/retry-engine.md` — Retry loop + failure analysis + fix-agent dispatch + escalation
- `agents/gate-fixer.md` — Specializovaný agent pro opravu failujících gates
- `commands/run-gates.md` — Standalone gates command (`/run-gates`, `--dry-run`)
- Update `commands/run-epic.md` — GATES + GATE_RETRY stavy s referencí na nové skills
- Update `plugin.json` — 1 nový command, 1 nový agent, 2 nové skills

**Phases (7):**
1. Gates Engine Skill — gates.yaml parsing, execution protocol, gates_report.json
2. Retry Engine Skill — retry loop, failure analysis, fix dispatch, escalation
3. Gate Fixer Agent — specializovaný fix agent s constraints
4. Run Gates Command — standalone `/run-gates` + `--dry-run`
5. Update run-epic.md — concrete GATES + GATE_RETRY implementation
6. Plugin Integration + Cross-references
7. Smoke Test (happy path, retry, escalation, conditional skip)

**Acceptance:**
- `gates-engine.md` parsuje gates.yaml a generuje `gates_report.json` s retry history
- `retry-engine.md` definuje failure analysis pro všech 6 gate typů + fix dispatch protocol
- `gate-fixer.md` má scope constraints (allowed/forbidden paths) + no-skip policy
- `/run-gates` spustí gates standalone s real-time progress
- `/run-gates --dry-run` zobrazí gates bez spuštění
- Failing gate → retry (gate-fixer) → re-run → pass (evidence recorded)
- Po 3 failech: escalation s PM options (skip/manual fix/abort)
- Evidence: `gates_report.json` + `gates/*.txt` + `gates/retry_*.md`
- `run-epic.md` GATES + GATE_RETRY odkazují na nové skills

---

### Session 4: Worker Agenti + Curator + Auditor + Scanner ✅

**Stav:** Hotová. Session file: `workspace/sessions/completed/S-20260217-e7b3-worker-agents-curator-auditor-scanner.md`

**Cíl:** 9 role-agentů + 3 noví specialisté.

**Deliverables:**
- 9 role agents: architect, domain, backend, frontend, qa, security, observability, docs-writer, release
- Curator agent + brainstorming flow
- Auditor agent + 5 typů auditu
- Project Scanner agent (quick + deep)
- `skills/improvement-proposals.md`
- Playbooks: přidat `improvement_notes` sekci

**Acceptance:**
- Každý role-agent produkuje výstup + improvement_notes
- Curator sbírá postřehy, deduplikuje, navrhuje
- Auditor generuje audit report
- Project Scanner vytvoří project-profile.yaml
- Scope enforcement funguje

---

### Session 5: Planner + Paralelizace + Multi-Perspective Analysis

**Stav:** Aktivní. Session file: `workspace/sessions/active/S-20260217-1ffa-planner-parallelization.md`

**Cíl:** Automatická generace plánů, paralelní dispatch, branch management, multi-perspective analysis.

**Deliverables:**
- `skills/planner.md` — Planner skill (dependency graph, parallel groups, auto-triggers, analysis groups)
- `skills/parallel-dispatch.md` — Paralelní dispatch protocol (branch strategy, fork/merge, conflict detection)
- `skills/analysis-merge.md` — Analysis merge skill (3 strategie: union, consensus, weighted)
- Update `defaults/templates/plan.schema.json` — `analysis_groups` schema (backward compatible)
- Update `commands/plan-epic.md` — integrace Planner skill + analysis_groups generace
- Update `commands/run-epic.md` — analysis_groups dispatch v EXECUTING, merge v PHASE_CHECK
- Update `commands/run-step.md` — `--analysis-group` parametr
- Update `skills/epic-orchestration.md` — EXECUTING + PHASE_CHECK rozšíření
- Update `plugin.json` — 18 agents, 16 commands, 10 skills (3 nové)
- Update `commands/aid-help.md` — Planning + Parallelization + Analysis Groups

**Phases (10):**
1. Planner Skill — dependency graph, parallel groups, auto-triggers, analysis groups
2. Parallel Dispatch Skill — branch strategy, dispatch protocol, conflict detection
3. Analysis Merge Skill — 3 merge strategie + analysis_report format
4. Plan Schema Update — analysis_groups v plan.schema.json
5. Plan-Epic Command Update — integrace Planner skill
6. Run-Epic Command Update — analysis_groups dispatch + merge
7. Epic-Orchestration Skill Update — EXECUTING + PHASE_CHECK rozšíření
8. Run-Step Command Update — --analysis-group parametr
9. Plugin Integration + Cross-references
10. Smoke Test

**Acceptance:**
- Plan JSON validní dle schema (včetně `analysis_groups`)
- Paralelní kroky běží současně (branch per agent)
- `analysis_groups` dispatch: N agentů analyzuje stejný target → konsolidovaný `analysis_report`
- Merge strategie fungují (`union`, `consensus`, `weighted`)
- Auto-trigger pravidla v Planneru správně detekují security/complexity/DB kroky
- Branch management: sequential merge chain, parallel fork+merge, analysis read-only
- Backward compatible — Plan JSON bez analysis_groups zůstává validní

---

### Session 6: Slack + Autonomní Běh ✅

**Stav:** Hotová. Session file: `workspace/sessions/completed/S-20260217-d9c4-slack-autonomous-run.md`

**Cíl:** Slack MCP skill pro asynchronní PM komunikaci, přepojení všech PM touchpoints
(PLAN_REVIEW, ESCALATION, PM_APPROVAL, Curator proposals, Auditor summaries) z chat-based
na Slack-based, a Epic Queue pro automatický pickup dalšího EPICu po dokončení.

**Deliverables:**
- `skills/slack-mcp.md` — Slack MCP integration skill (message types, formatting, response parsing, timeout handling)
- `skills/epic-queue.md` — Epic Queue skill (queue management, auto-pickup, status tracking)
- `commands/epic-queue.md` — Epic Queue command (`/epic-queue list|add|next|pause|resume`)
- Update `commands/run-epic.md` — PLAN_REVIEW, ESCALATION, PM_APPROVAL → Slack MCP integration
- Update `skills/epic-orchestration.md` — State definitions aktualizovány pro Slack komunikaci + DONE → auto-pickup
- Update `agents/curator.md` — Orchestrátor→Slack flow pro proposals a rejection info
- Update `agents/auditor.md` — Orchestrátor→Slack flow pro audit summaries
- Update `commands/aid-help.md` — Slack integration + Epic Queue dokumentace
- Update `plugin.json` — 18 agents, 17 commands (+1 epic-queue), 12 skills (+2 slack-mcp, epic-queue)

**Phases (8):**
1. Slack MCP Skill — message types, formatting, response parsing, timeouts
2. Run-Epic Slack Integration — PLAN_REVIEW, ESCALATION, PM_APPROVAL přepojení
3. Epic-Orchestration Skill Update — state definitions pro Slack
4. Curator Slack Integration — proposals + rejection info přes Slack
5. Auditor Slack Integration — audit summaries přes Slack
6. Epic Queue Skill + Command — queue management, auto-pickup
7. Plugin Integration + Cross-references
8. Smoke Test

**Acceptance:**
- Slack MCP skill definuje 7 message typů (Escalation, Plan Approval, Merge Approval, Proposal, Rejection Info, Audit Summary, Status Update)
- `run-epic.md` PLAN_REVIEW/ESCALATION/PM_APPROVAL používají Slack MCP místo chat
- Curator proposals jdou přes Slack (approve/defer/reject) + rejection info
- Auditor audit summaries jdou přes Slack (informational)
- Epic Queue: `/epic-queue add` → `/epic-queue list` → auto-pickup po DONE
- 2 EPICy v řadě projdou bez manuálního zásahu (queue-driven)
- Timeout handling: PM neodpoví → escalation reminder → configurable default action
- Backward compatible: pokud Slack MCP není configured → fallback na chat

---

### Session 6.5: Session File Detail Quality ✅

**Stav:** Hotová. Design: `docs/plans/2026-02-17-session-file-detail-quality-design.md`, Impl plan: `docs/plans/2026-02-17-session-file-detail-quality-impl.md`

**Cíl:** Zajistit, aby session files vytvořené přes `/session-start` (non-orchestrated) i `/plan-epic` (orchestrated) byly vždy maximálně detailní — s plným kontextem, phases, dependencies, quality gates.

**Problém:** Session files byly fádní a nedostatečné. Plan JSON (z Planner skill) je detailní a validovaný, ale detail se nepřenášel do session file. Templates měly generické placeholdery bez guidance, instrukce v commands nespecifikovaly minimum detail.

**Deliverables:**
- Rework 4 session templates (`session-new-feature.md`, `session-bug-fix.md`, `session-refactoring.md`, `session-exploration.md`) — guidance comments, MIN markers, 6-subsection Phase structure
- Expand `commands/plan-epic.md` Step 5 — Session Creation Protocol (sources, Plan JSON → Session Phases mapping, quality checklist)
- Update `skills/epic-orchestration.md` — PLANNING state quality check + Integration with Session Management section
- Rewrite `commands/session-start.md` — non-orchestrated Session Creation Protocol (sources including EPIC, decomposition rules, quality check)

**Acceptance:**
- Všechny 4 templates mají 7 povinných sekcí (Objective, Context, Scope, Phases, Dependencies, Quality Gates, Session Log)
- Každá Phase má 6 subsections (Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance)
- MIN markers konzistentní across all templates (Objective 3-5 vět, Scope IN 3+/OUT 2+, Acceptance 3+ items)
- plan-epic.md Step 5 obsahuje 8-krokový mapping Plan JSON → Session Phases
- session-start.md obsahuje Session Creation Protocol i pro non-orchestrated flow
- Cross-reference verification prošla (7 souborů konzistentních)

---

### Session 7: E2E Test + Hardening

**Cíl:** Reálný EPIC, edge cases, dokumentace.

**Acceptance:**
- Reálný EPIC projede kompletně
- Curator flow end-to-end (postřehy → backlog → PM)
- Audit report po Epicu
- Evidence kompletní

---

### Session 8: Memory MCP (Qdrant)

**Cíl:** Dlouhodobá vektorová paměť přes sessions.

**Deliverables:**
- Qdrant MCP server setup
- Vector memory integration do orchestrátoru
- Semantické vyhledávání
- Auto-indexing: decisions, lessons, code patterns

**Acceptance:**
- "Jak jsme řešili autentizaci?" → relevantní výsledky z historie
- Memory roste s každou session
- Backward compatible (file-based memory stále funguje jako fallback)

---

## Dependencies

```
Session 1 (scaffold + rename AID)
    ↓
Session 2 (commands + aid-setup + aid-help)
    ↓
Session 3 (gates + retry)
    ↓
Session 4 (9 agentů + curator + auditor + scanner)
    ↓
Session 5 (planner + parallel)
    ↓
Session 6 (slack + autonomie)
    ↓
Session 7 (E2E test)
    ↓
Session 8 (memory MCP — Qdrant)
```

Všechny sessions sekvenční (každá staví na předchozí).
