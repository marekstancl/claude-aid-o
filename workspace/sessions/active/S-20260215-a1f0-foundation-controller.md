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

# Session 1: Foundation + Controller State Machine

## Objective

Přenést existující claude/ setup do ai-orchestrator projektu,
vytvořit orchestrační skill s Controller state machine logikou,
decision policies a evidence store. Na konci session musí orchestrátor
umět načíst EPIC, vytvořit Plan JSON šablonu a projít state machine
flow (i s mock agenty).

## Deliverables

- [ ] .claude/ setup přenesený a funkční v ai-orchestrator/
- [ ] CLAUDE.md pro projekt
- [ ] `skills/epic-orchestration/instructions.md` — Controller state machine
- [ ] `skills/epic-orchestration/skill.json`
- [ ] `policies/decision-policies.yaml` — rozhodovací pravidla
- [ ] `policies/gates.yaml` — gates konfigurace
- [ ] `templates/epic.md` — EPIC šablona
- [ ] `templates/plan.schema.json` — Plan JSON schema
- [ ] `evidence/` directory s .gitkeep

## Phases

### Phase 1: Project Bootstrap (Phase 0)

**Agent:** hlavní session (manuálně)

**Úkol:**
- Přenést .claude/ z claude/ do ai-orchestrator/.claude/
  - agents/ (5 existujících)
  - commands/ (8 existujících)
  - skills/ (11 existujících)
  - hooks/pre-commit-guard.sh
  - settings.json, settings.local.json, project.json
- Aktualizovat project.json pro nový projekt (paths, name, conventions)
- Vytvořit CLAUDE.md s instrukcemi pro ADO projekt
- Vytvořit .gitignore
- Ověřit že Claude Code načte setup bez chyb

**Acceptance:**
- [ ] .claude/ struktura existuje a je kompletní
- [ ] project.json aktualizován pro ai-orchestrator
- [ ] CLAUDE.md existuje s run instrukcemi
- [ ] Nová Claude Code session načte skills bez chyb

**Status:** pending

---

### Phase 2: Templates + Policies

**Agent:** hlavní session (manuálně)

**Úkol:**
- Vytvořit `templates/epic.md` — EPIC šablona (dle ado_starter_kit/03)
- Vytvořit `templates/plan.schema.json` — JSON schema (dle ado_starter_kit/04)
- Vytvořit `policies/gates.yaml` — gates konfigurace (dle ado_starter_kit/05)
- Vytvořit `policies/decision-policies.yaml` — PM decision rules:
  - quality_thresholds (min review score, coverage, security)
  - architecture_principles (YAGNI, contract-first, tenant isolation)
  - acceptable_debt vs. not_acceptable
  - escalation_triggers (kdy Slack PM)
  - auto_decisions (co orchestrátor rozhodne sám)
- Vytvořit `evidence/` directory s README

**Acceptance:**
- [ ] Plan JSON schema je validní JSON Schema draft 2020-12
- [ ] EPIC šablona obsahuje všechny povinné sekce
- [ ] Decision policies pokrývají: thresholds, principles, escalation, auto
- [ ] Gates policy definuje min 4 gates + retry config

**Status:** pending

---

### Phase 3: Controller State Machine (epic-orchestration skill)

**Agent:** hlavní session (manuálně)

**Úkol:**
- Vytvořit `skills/epic-orchestration/skill.json`
- Vytvořit `skills/epic-orchestration/instructions.md` obsahující:
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
- Registrovat skill v project.json

**Acceptance:**
- [ ] Skill se načte bez chyb v Claude Code
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
- Ručně projít flow:
  1. Načíst EPIC
  2. Vygenerovat Plan JSON (ručně, dle schema)
  3. Projít state machine stavy (simulace)
  4. Ověřit že decision policies pokrývají rozhodnutí
  5. Ověřit evidence structure
- Zdokumentovat co funguje a co chybí

**Acceptance:**
- [ ] Dummy EPIC existuje a je validní dle šablony
- [ ] Plan JSON validní dle schema
- [ ] State machine flow dává smysl end-to-end
- [ ] Evidence directory vytvořena s požadovanými soubory
- [ ] Seznam TODO pro Session 2 zdokumentován

**Status:** pending

---

## DoD Gates

- [ ] Všechny deliverables existují
- [ ] .claude/ setup funkční (ověřeno načtením v nové session)
- [ ] Plan JSON schema validní
- [ ] Decision policies kompletní
- [ ] Smoke test prošel
- [ ] Dokumentace aktualizována (MULTIAGENT_GUIDE.md pokud potřeba)

## Session Log

| Čas | Událost |
|-----|---------|
| 2026-02-15 | Session file vytvořen |

## Notes

- Toto je "bootstrap" session — stavíme orchestrátor, který bude řídit
  budoucí sessions. Proto vše děláme manuálně.
- Od Session 2 začneme orchestrátor postupně používat sám na sebe.
- Existující agenti (code-reviewer, quality-gates-runner, docs-reviewer,
  session-validator, lessons-extractor) zůstávají beze změny.
