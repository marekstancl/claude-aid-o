---
id: P-20260216-b3a1
type: design
status: approved
created: 2026-02-16
author: PM + AI
epic_ref: EPIC-ADO-0001
---

# Plan: AID v2 — Workspace Redesign, New Agents, Memory

## Context

Session 1 of EPIC-ADO-0001 is complete — plugin scaffold `ado-orchestrator`
exists with 5 utility agents, 9 commands, 4 skills, policies, templates,
playbooks. This plan defines the next evolution: rebranding, workspace
restructure, new agents, memory system.

## Decision Record

### D-001: Rebranding ADO → AID

- **Old:** ADO (AI Development Orchestrator), `ado-orchestrator`, `workspace/`
- **New:** AID (AI Development aid), `aid-orchestrator`, `.aid-o/`
- **Reason:** "Aid" = pomoc/asistence. Skrytý root dir (tečka prefix) nezavazí v projektu.
  Číselné prefixy oddělují PM zónu od AI zóny.

### D-002: Workspace Structure `.aid-o/`

```
.aid-o/
  01-plans/                          # PM + AI brainstorming → plány
    archive/                         #   dokončené plány
  02-epics/                          # PM + AI detail → zadání
    archive/                         #   dokončené epicy
  03-config/                         # PM-customizable konfigurace
    policies/
      gates.yaml
      decision-policies.yaml
    templates/
      plan.md                        # NOVY template (chybel)
      epic.md
      session-bug-fix.md
      session-new-feature.md
      session-refactoring.md
      session-exploration.md
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
  04-engine/                         # AI interni
    sessions/
      archive/
    memory/
      active-work.md                 # Current state, handoff (z existujiciho)
      project-profile.yaml           # Quick scan vysledek
      decisions.yaml                 # Historie klicovych rozhodnuti
    backlog.md                       # (drive bugs.md — sirsi scope)
    lessons-learned.md
    command-history.md
    evidence/                        # Audit trail per EPIC run
```

**Key rules:**
- Soubory lezi primo v adresari (bez `active/` podslozek)
- Hotove → presun do `archive/`
- PM pracuje s `01-plans/` a `02-epics/`
- AI interni = `04-engine/`
- `03-config/` = PM customizable, ale zridka

### D-003: Naming Conventions (vse s hash)

| Typ | Format | Priklad |
|-----|--------|---------|
| Plan | `P-{YYYYMMDD}-{4char-hash}-{topic}.md` | `P-20260216-b3a1-mvp-roadmap.md` |
| Epic | `E-{YYYYMMDD}-{4char-hash}-{topic}.md` | `E-20260216-c2d1-user-auth.md` |
| Session | `S-{YYYYMMDD}-{4char-hash}-{topic}.md` | `S-20260216-a1f0-foundation.md` |

### D-004: Curator Agent

**Role:** Sbira postrehy z agentu, deduplikuje, brainstormuje, navrhuje vylepseni.

**Timing:** Automaticky po kazdem `session-end`.

**Input:** `improvement_notes` ze vsech step outputs (standardni YAML format v kazdem agentu):

```yaml
improvement_notes:
  - type: refactoring|performance|security|architecture|dx
    area: "cesta/k/souboru"
    observation: "Popis problemu"
    suggestion: "Navrh reseni"
    priority: low|medium|high
```

**Flow:**
```
session-end
  → Curator sbira improvement_notes z evidence/
  → Cte existujici backlog.md + lessons-learned.md
  → Deduplikuje (neopakuje zname)
  → Nove postrehy → backlog.md
  → Brainstorming: navrhne konkretni akce
  → Posle navrhy Orchestratoru
    ├── Orchestrator ZAMITNE → zaloguje do backlog.md (status: rejected)
    │     + Slack PM (info: zamitnuty navrh + duvod)
    └── Orchestrator SCHVALI → vytvori proposal
          → Slack PM (proposal k rozhodnuti)
            ├── PM SCHVALI → Orchestrator vytvori novy Epic
            ├── PM ODLOZI → backlog.md (status: deferred)
            └── PM ZAMITNE → backlog.md (status: pm-rejected)
```

**Backlog.md struktura:**
```markdown
# Backlog

## Active Proposals (ceka na PM)
| ID | Type | Area | Suggestion | Priority | Source | Status |

## Deferred
| ID | Type | Area | Suggestion | Reason | Date |

## Rejected
| ID | Type | Area | Suggestion | Rejected by | Reason | Date |

## Implemented
| ID | Type | Area | Epic Ref | Date |
```

### D-005: Audit Agent

**Role:** Komplexni audit projektu po kazdem dokoncenen Epicu.

**Timing:** Automaticky po Epic DONE (post-merge).

**5 typu auditu** (templates existuji v stávajícím setupu):
1. **Code audit** — kvalita, patterns, duplicity, complexity
2. **Security audit** — vulnerabilities, secrets, OWASP
3. **Docs audit** — aktualnost dokumentace, chybejici docs
4. **Frontend audit** (pokud relevantni)
5. **Database audit** (pokud relevantni)

**Flow:**
```
Epic DONE → Gates pass → PM approval → merge
  → Audit agent bezi (post-merge)
  → Audit report → evidence/{epic_id}/audit-report.md
  → Findings → Orchestrator validuje
    ├── Orchestrator schvali → Curator zpracuje do backlogu
    └── Orchestrator zamitne → zaloguje + Slack PM (info)
  → Summary → Slack PM
```

**Trend tracking:** Kazdy audit se porovnava s predchozim (score, pocet findings).

### D-006: Project Scanner Agent

**Role:** Analyza projektu — quick scan pro onboarding, deep scan pro milestones.

**Dva rezimy:**
1. **Quick scan** (pri onboardingu):
   - Tech stack, struktura adresaru, hlavni frameworky
   - Build system, test framework, CI/CD
   - Vysledek: `project-profile.yaml`
   - Trvani: minuty

2. **Deep analysis** (milestone/on-demand):
   - Vse vyse + code quality metriky, architekturni patterns
   - Dependencies audit, security scan, tech debt odhad
   - Trvani: delsi

### D-007: `/aid-setup` Command

**Ucel:** Prvni kontakt uzivatele s AID — analyza + interaktivni setup.

**Flow:**
1. Analyzuje projekt (package.json, pyproject.toml, Dockerfile, .git...)
2. Detekuje tech stack, build system, test framework
3. Vypise co AID potrebuje k fungovani
4. Nabidne interaktivni setup v chatu:
   - VS Code settings.json
   - CLAUDE.md generace
   - `.aid-o/` inicializace (vola `/aid-init` vnitrne)
   - Naplni `project-profile.yaml`
5. Generuje README sekci "Working with AID"

**Dva scenare:**
- **Novy projekt** → brainstorming, scaffold, Plan → Epic
- **Existujici projekt** → quick scan, optional deep analysis

### D-008: `/aid-help` Command

**Ucel:** Self-knowledge — AID vi vse o sobe a vysvetli uzivateli.

**Obsah:**
- Dostupne prikazy s popisem
- Workflow: Plan → Epic → Session
- Jak psat Epic
- Jak spustit orchestraci
- Kde najit vystupy
- FAQ

### D-009: Memory System

**A) File-based (v `.aid-o/04-engine/memory/`):**
- `active-work.md` — current state, handoff, recent sessions
- `project-profile.yaml` — tech stack, architektura (z Project Scanner)
- `decisions.yaml` — klicova rozhodnuti (ADR-lite format)

**B) MCP Vector DB (Qdrant):**
- Dlouhodoba semanticka pamet pres sessions
- Code patterns, architekturni znalosti
- Historicke kontexty rozhodnuti
- Semanticke vyhledavani ("jak jsme resili autentizaci?")

### D-010: Improvement Notes Skill

**Ucel:** Standardni format pro agenty — jak zapisovat postrehy.

Vsichni 9 role-agentu dostanou v playbooku sekci `## Improvement Notes`.

```yaml
improvement_notes:
  - type: refactoring|performance|security|architecture|dx
    area: "cesta/k/souboru"
    observation: "Popis problemu"
    suggestion: "Navrh reseni"
    priority: low|medium|high
```

## Workflow Principles

1. **Plan + Epic = PM + AI spoluprace** (brainstorming, detaily)
2. **Session a dal = AI autonomne** (PM jen Slack approve/escalation)
3. **Vse prochazi Orchestratorem** (Curator→Orchestrator→PM, Auditor→Orchestrator→PM)
4. **Vse na PM jde pres Slack** (i zamitnutí = info)
5. **Inkrementalni znalosti** (quick scan → deep later, lessons rostou)

## Impact on EPIC-ADO-0001

### Nova/zmenena polozky:

**Agenti:**
- +1 Curator agent
- +1 Auditor agent
- +1 Project Scanner agent
- Vsech 9 role-agentu: pridat `improvement_notes` sekci do playbooks

**Commands:**
- Rename `/ado-init` → `/aid-init`
- +1 `/aid-setup`
- +1 `/aid-help`

**Skills:**
- +1 `improvement-proposals` skill

**Struktura:**
- `workspace/` → `.aid-o/` (kompletni restrukturizace)
- Vsechny cesty v commands, skills, policies se musi aktualizovat

**Plugin:**
- Rename `ado-orchestrator` → `aid-orchestrator`
- Aktualizovat marketplace.json, plugin.json

**Memory:**
- Novy MCP server pro Qdrant vector memory

## Session Impact Analysis

### Session 1 (DONE — nutne doplnit):
- Rename plugin `ado-orchestrator` → `aid-orchestrator`
- Rename vsech intern referencí
- Aktualizovat `/ado-init` → `/aid-init` s novou `.aid-o/` strukturou
- Pridat Plan template do defaults/templates/

### Session 2 (Commands — rozsirit):
- Puvodni: plan-epic, run-epic, run-step, epic-status
- Pridat: `/aid-setup`, `/aid-help`

### Session 3 (Gates — beze zmeny)

### Session 4 (Agenti — rozsirit):
- Puvodni: 9 role-agentu + playbooks
- Pridat: Curator agent, Auditor agent, Project Scanner agent
- Playbooks: pridat `improvement_notes` sekci

### Session 5 (Planner — beze zmeny)

### Session 6 (Slack — beze zmeny, ale zohlednit Curator/Auditor Slack flow)

### Session 7 (E2E — zahrnout nove agenty a flow)

### Session 8 (NOVA — Memory MCP):
- Qdrant MCP server setup
- Vector memory integration
- Semanticke vyhledavani
