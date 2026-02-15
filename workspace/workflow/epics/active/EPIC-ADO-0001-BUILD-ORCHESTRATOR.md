# EPIC: ADO-0001 — Build AI Development Orchestrator (Marketplace Plugin)

## Kontext

Existuje fungující single-agent framework (Agent Skills v4.0 pro C.I.C.E.R.O.)
s 5 subagenty, 8 commands, 11 skills, session managementem a quality gates.

Cílem je evoluce do Controller + Workers architektury jako **instalovatelný
Claude Code plugin**, který lze použít na jakémkoliv projektu. Orchestrátor
autonomně řídí 9 specializovaných agentů, kontroluje výstupy, provádí gates
a eskaluje na PM přes Slack jen když si neví rady.

Referenční dokumentace: `docs/MULTIAGENT_GUIDE.md`
Zdrojové materiály: `_unzipped/ado_starter_kit/`, `_unzipped/ai_dev_orchestrator_docs/`

## Cíl

Postavit marketplace s pluginem `ado-orchestrator`, který:
1. Se nainstaluje přes `claude plugin install ado-orchestrator`
2. Příkazem `/ado-init` vytvoří doporučenou workspace strukturu v projektu
3. Vezme Epic soubor → vygeneruje Plan JSON → dispatche agenty → gates → evidence
4. Funguje autonomně s Slack escalation pro PM

## Výstupní struktura

```
ai-orchestrator/                       # Marketplace root
  marketplace.json                     # Registr pluginů
  plugins/
    ado-orchestrator/                  # Plugin: AI Development Orchestrator
      .claude-plugin/
        plugin.json                    # Plugin manifest (name, version, ...)
      agents/                          # 9 role-agents + 5 utility agents
        architect.md
        domain.md
        backend.md
        frontend.md
        qa.md
        security.md
        observability.md
        docs-writer.md
        release.md
        code-reviewer.md              # Přenesený z claude/
        docs-reviewer.md              # Přenesený z claude/
        quality-gates-runner.md        # Přenesený z claude/
        session-validator.md           # Přenesený z claude/
        lessons-extractor.md           # Přenesený z claude/
      commands/
        ado-init.md                    # Vytvoří workspace strukturu v projektu
        plan-epic.md                   # Epic → Plan JSON + Session file
        run-epic.md                    # Hlavní orchestrační loop
        run-step.md                    # Manuální spuštění jednoho kroku
        epic-status.md                 # Zobrazení stavu
        quality-gates.md               # Přenesený z claude/
        session-start.md               # Přenesený z claude/
        session-end.md                 # Přenesený z claude/
        handoff.md                     # Přenesený z claude/
        audit.md                       # Přenesený z claude/
        coding-standards.md            # Přenesený z claude/
        testing.md                     # Přenesený z claude/
        docs-protocol.md              # Přenesený z claude/
      skills/
        epic-orchestration.md          # Controller state machine
        agent-core.md                  # Přenesený (zjednodušený)
        quality-gates.md               # Přenesený (zjednodušený)
        session-management.md          # Přenesený (zjednodušený)
      defaults/                        # Výchozí soubory pro /ado-init
        policies/
          gates.yaml
          decision-policies.yaml
        templates/
          epic.md
          plan.schema.json
        playbooks/
          architect.md
          domain.md
          backend.md
          frontend.md
          qa.md
          security.md
          observability.md
          docs.md
          release.md
      README.md
```

Co `/ado-init` vytvoří v cílovém projektu:

```
cílový-projekt/
  workspace/
    active-work.md
    session-log.md
    command-history.md
    lessons-learned.md
    bugs.md
    sessions/{active,completed}/
    workflow/epics/{active,completed}/
    workflow/plans/
  policies/                            # Zkopírováno z defaults/, přizpůsobitelné
    gates.yaml
    decision-policies.yaml
  templates/                           # Zkopírováno z defaults/
    epic.md
    plan.schema.json
  playbooks/                           # Zkopírováno z defaults/
    architect.md, domain.md, ...
  evidence/
    .gitkeep
```

## Scope

### Allowed files/paths
- plugins/ado-orchestrator/
- marketplace.json
- docs/
- workspace/

### Forbidden zones
- Žádné (nový projekt)

## Constraints
- Žádný externí framework (vše nativně v Claude Code plugin systém)
- Decision policies musí pokrývat 90%+ rozhodnutí bez PM
- Evidence by design
- Plugin musí být self-contained (žádné externí závislosti)
- Existující agenti/commands/skills z claude/ se přenesou do pluginu

## DoD Gates
- Plugin se nainstaluje bez chyb
- `/ado-init` vytvoří kompletní workspace strukturu
- Dummy EPIC projede celým pipeline end-to-end
- Všech 9 role-agentů funguje
- Gates engine vyhodnotí pass/fail + retry
- Evidence store kompletní
- Dokumentace aktualizována

---

## Sessions

### Session 1: Plugin Scaffold + Controller State Machine

**Cíl:** Vytvořit plugin strukturu, přenést existující setup,
vytvořit orchestrační skill a decision policies.

**Deliverables:**
- marketplace.json
- plugins/ado-orchestrator/.claude-plugin/plugin.json
- Přenesené agents/, commands/, skills/ v plugin struktuře
- skills/epic-orchestration.md — Controller state machine
- defaults/policies/decision-policies.yaml
- defaults/policies/gates.yaml
- defaults/templates/epic.md + plan.schema.json
- commands/ado-init.md
- README.md

**Acceptance:**
- Plugin struktura kompletní
- `/ado-init` vytvoří workspace v testovacím projektu
- Orchestrační skill se načte bez chyb

---

### Session 2: EPIC Runner Commands

**Cíl:** 4 orchestrační commands (plan-epic, run-epic, run-step, epic-status).

**Acceptance:**
- `/plan-epic` vytvoří validní Plan JSON z dummy EPICu
- `/run-step` spustí jeden krok s mock agentem

---

### Session 3: Gates Engine + Retry

**Cíl:** Gates runner, pass/fail report, retry loop (max 3).

**Acceptance:**
- Failing gate → retry → fix → pass
- Evidence uložena

---

### Session 4: 9 Worker Agentů + Playbooks

**Cíl:** Všech 9 role-based agentů s detailními playbooks.

**Acceptance:**
- Každý agent produkuje smysluplný výstup
- Scope enforcement funguje

---

### Session 5: Planner + Paralelizace

**Cíl:** Automatická generace plánů, paralelní dispatch, branch management.

**Acceptance:**
- Plan JSON validní dle schema
- Paralelní kroky běží současně

---

### Session 6: Slack + Autonomní Běh

**Cíl:** Slack MCP, escalation, epic queue.

**Acceptance:**
- Slack escalation funguje
- 2 EPICy v řadě bez manuálního zásahu

---

### Session 7: E2E Test + Hardening

**Cíl:** Reálný EPIC, edge cases, dokumentace.

**Acceptance:**
- Reálný EPIC projede kompletně
- Evidence kompletní

---

## Dependencies

Všechny sessions sekvenční (každá staví na předchozí).
