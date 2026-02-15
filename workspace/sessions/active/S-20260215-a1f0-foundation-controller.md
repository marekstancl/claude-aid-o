---
id: S-20260215-a1f0
type: new-feature
status: active
priority: high
started: 2026-02-15
epic_id: ADO-0001
epic_session: 1
epic_file: workspace/workflow/epics/active/EPIC-ADO-0001-BUILD-ORCHESTRATOR.md
ai_agent: Claude Opus 4.6
branch: session/2026-02-15-foundation-controller
---

# Session 1: Plugin Scaffold + Controller State Machine

## Objective

Vytvořit marketplace plugin strukturu `ado-orchestrator`, přenést existující
claude/ setup do plugin formátu, vytvořit orchestrační skill s Controller
state machine logikou, decision policies, templates a `/ado-init` command.

Na konci session musí:
- Plugin struktura být kompletní
- `/ado-init` vytvořit workspace v cílovém projektu
- Orchestrační skill se načíst bez chyb

## Deliverables

- [ ] `marketplace.json` — registr pluginů
- [ ] `plugins/ado-orchestrator/.claude-plugin/plugin.json` — plugin manifest
- [ ] `plugins/ado-orchestrator/agents/` — přenesení existujících 5 utility agentů
- [ ] `plugins/ado-orchestrator/commands/ado-init.md` — workspace scaffold command
- [ ] `plugins/ado-orchestrator/commands/` — přenesení existujících 8 commands
- [ ] `plugins/ado-orchestrator/skills/epic-orchestration.md` — Controller state machine
- [ ] `plugins/ado-orchestrator/skills/` — přenesení existujících skills (zjednodušené)
- [ ] `plugins/ado-orchestrator/defaults/policies/decision-policies.yaml`
- [ ] `plugins/ado-orchestrator/defaults/policies/gates.yaml`
- [ ] `plugins/ado-orchestrator/defaults/templates/epic.md`
- [ ] `plugins/ado-orchestrator/defaults/templates/plan.schema.json`
- [ ] `plugins/ado-orchestrator/defaults/playbooks/` — 9 role playbooks
- [ ] `plugins/ado-orchestrator/README.md`
- [ ] CLAUDE.md pro projekt

## Phases

### Phase 1: Marketplace + Plugin Scaffold

**Agent:** hlavní session (manuálně)

**Úkol:**
- Vytvořit `marketplace.json` s registrací ado-orchestrator pluginu
- Vytvořit `plugins/ado-orchestrator/.claude-plugin/plugin.json` (manifest):
  - name, version, description
  - registrace agents, commands, skills
- Vytvořit adresářovou strukturu pluginu:
  ```
  plugins/ado-orchestrator/
    .claude-plugin/plugin.json
    agents/
    commands/
    skills/
    defaults/
      policies/
      templates/
      playbooks/
  ```
- Přenést existující claude/ setup do plugin struktury:
  - `claude/agents/*.md` → `plugins/ado-orchestrator/agents/`
    (code-reviewer, docs-reviewer, quality-gates-runner, session-validator, lessons-extractor)
  - `claude/commands/*.md` → `plugins/ado-orchestrator/commands/`
    (quality-gates, session-start, session-end, handoff, audit, coding-standards, testing, docs-protocol)
  - `claude/skills/` → `plugins/ado-orchestrator/skills/`
    (agent-core, quality-gates, session-management — zjednodušené)
- Vytvořit CLAUDE.md s instrukcemi pro ADO projekt
- Vytvořit/aktualizovat .gitignore

**Acceptance:**
- [ ] marketplace.json existuje a je validní JSON
- [ ] plugin.json obsahuje name, version, description, registrace
- [ ] Všech 5 utility agentů přeneseno do agents/
- [ ] Všech 8 existujících commands přeneseno
- [ ] Skills přeneseny (zjednodušené verze)
- [ ] CLAUDE.md existuje

**Status:** pending

---

### Phase 2: Templates + Policies + Playbooks

**Agent:** hlavní session (manuálně)

**Úkol:**
- Vytvořit `defaults/templates/epic.md` — EPIC šablona (dle ado_starter_kit/03)
- Vytvořit `defaults/templates/plan.schema.json` — JSON schema (dle ado_starter_kit/04)
- Vytvořit `defaults/policies/gates.yaml` — gates konfigurace (dle ado_starter_kit/05):
  - min 4 gates: tests_pass, lint_pass, security_scan, docs_updated
  - retry config (max_retries: 3, backoff)
  - pass/fail thresholds
- Vytvořit `defaults/policies/decision-policies.yaml` — PM decision rules:
  - quality_thresholds (min review score, coverage, security)
  - architecture_principles (YAGNI, contract-first, tenant isolation)
  - acceptable_debt vs. not_acceptable
  - escalation_triggers (kdy Slack PM)
  - auto_decisions (co orchestrátor rozhodne sám)
- Vytvořit 9 role playbooks v `defaults/playbooks/`:
  - architect.md, domain.md, backend.md, frontend.md
  - qa.md, security.md, observability.md, docs.md, release.md
  - Každý playbook: role, responsibilities, inputs, outputs, quality criteria

**Acceptance:**
- [ ] Plan JSON schema je validní JSON Schema draft 2020-12
- [ ] EPIC šablona obsahuje všechny povinné sekce
- [ ] Decision policies pokrývají: thresholds, principles, escalation, auto
- [ ] Gates policy definuje min 4 gates + retry config
- [ ] Všech 9 playbooks vytvořeno s konzistentní strukturou

**Status:** pending

---

### Phase 3: `/ado-init` Command + Controller State Machine

**Agent:** hlavní session (manuálně)

**Úkol:**

**A) `/ado-init` command:**
- Vytvořit `commands/ado-init.md` který:
  - Vytvoří workspace strukturu v cílovém projektu:
    ```
    workspace/
      active-work.md
      session-log.md
      command-history.md
      lessons-learned.md
      bugs.md
      sessions/{active,completed}/
      workflow/epics/{active,completed}/
      workflow/plans/
    policies/
      gates.yaml
      decision-policies.yaml
    templates/
      epic.md
      plan.schema.json
    playbooks/
      architect.md, domain.md, ...
    evidence/
      .gitkeep
    ```
  - Zkopíruje soubory z `defaults/` do cílového projektu
  - Vytvoří README s vysvětlením struktury
  - Je idempotentní (nemaže existující soubory)

**B) Controller State Machine skill:**
- Vytvořit `skills/epic-orchestration.md` obsahující:
  - State machine definice:
    ```
    IDLE → PLANNING → PLAN_REVIEW → EXECUTING → PHASE_CHECK
      → NEXT_PHASE / RETRY → GATES → GATE_RETRY / ESCALATION
      → PM_APPROVAL → DONE / REJECTED
    ```
  - Jak číst EPIC a generovat Plan JSON
  - Jak dispathnout agenty (sekvenčně i paralelně)
  - Jak předávat kontext mezi fázemi (výstup agenta N → vstup agenta N+1)
  - Jak provádět phase acceptance checks (dle decision-policies.yaml)
  - Jak spouštět gates a vyhodnocovat pass/fail
  - Retry loop logika (max 3, pak escalation)
  - Evidence logging (co zaznamenat v každém stavu)
  - Session file auto-generace z EPIC + Plan
  - Branch management (branch per parallel agent)

**Acceptance:**
- [ ] `/ado-init` command vytvoří kompletní workspace strukturu
- [ ] Command je idempotentní
- [ ] Skill se načte bez chyb
- [ ] instructions.md obsahuje kompletní state machine
- [ ] Pokrývá: planning, execution, checking, retry, escalation, evidence
- [ ] Referuje decision-policies.yaml a gates.yaml

**Status:** pending

---

### Phase 4: Smoke Test

**Agent:** hlavní session (manuálně)

**Úkol:**
- Vytvořit dummy EPIC: `workspace/workflow/epics/active/EPIC-TEST-0001-DUMMY.md`
  - Jednoduchý scope (1 soubor)
  - 2-3 kroky (architect, backend, qa)
  - Všechny gates
- Otestovat `/ado-init`:
  1. Spustit v testovacím adresáři
  2. Ověřit že se vytvoří kompletní workspace struktura
  3. Ověřit že soubory z defaults/ jsou zkopírovány
- Ručně projít orchestrační flow:
  1. Načíst EPIC
  2. Vygenerovat Plan JSON (ručně, dle schema)
  3. Projít state machine stavy (simulace)
  4. Ověřit že decision policies pokrývají rozhodnutí
  5. Ověřit evidence structure
- Zdokumentovat co funguje a co chybí

**Acceptance:**
- [ ] Dummy EPIC existuje a je validní dle šablony
- [ ] `/ado-init` vytvoří workspace v testovacím projektu
- [ ] Plan JSON validní dle schema
- [ ] State machine flow dává smysl end-to-end
- [ ] Evidence directory vytvořena
- [ ] Seznam TODO pro Session 2 zdokumentován

**Status:** pending

---

## DoD Gates

- [ ] Všechny deliverables existují
- [ ] Plugin struktura kompletní (marketplace.json + plugin.json)
- [ ] `/ado-init` vytvoří workspace v testovacím projektu
- [ ] Plan JSON schema validní
- [ ] Decision policies kompletní
- [ ] Orchestrační skill se načte bez chyb
- [ ] Smoke test prošel
- [ ] Dokumentace aktualizována (MULTIAGENT_GUIDE.md pokud potřeba)

## Session Log

| Čas | Událost |
|-----|---------|
| 2026-02-15 | Session file vytvořen |
| 2026-02-15 | Session file aktualizován pro marketplace/plugin strukturu |

## Notes

- Toto je "bootstrap" session — stavíme orchestrátor, který bude řídit
  budoucí sessions. Proto vše děláme manuálně.
- Od Session 2 začneme orchestrátor postupně používat sám na sebe.
- Existující agenti (code-reviewer, quality-gates-runner, docs-reviewer,
  session-validator, lessons-extractor) se přenášejí do pluginu beze změny.
- Existující commands a skills se přenášejí do pluginu (skills zjednodušené).
- Plugin musí být self-contained — žádné externí závislosti.
- `/ado-init` vytváří doporučenou workspace strukturu a kopíruje defaults.
