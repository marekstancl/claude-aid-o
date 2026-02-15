# EPIC: ADO-0001 — Build AI Development Orchestrator

## Kontext

Existuje fungující single-agent framework (Agent Skills v4.0 pro C.I.C.E.R.O.)
s 5 subagenty, 8 commands, 11 skills, session managementem a quality gates.

Cílem je evoluce do Controller + Workers architektury, kde orchestrátor
autonomně řídí 9 specializovaných agentů, kontroluje výstupy, provádí
gates a eskaluje na PM přes Slack jen když si neví rady.

Referenční dokumentace: `docs/MULTIAGENT_GUIDE.md`
Zdrojové materiály: `_unzipped/ado_starter_kit/`, `_unzipped/ai_dev_orchestrator_docs/`

## Cíl

Postavit plně funkční ADO, který:
1. Vezme Epic soubor
2. Vygeneruje Plan JSON (role, závislosti, paralelizace)
3. Vytvoří Session detailed file
4. Spustí pipeline: dispatche agenty po fázích
5. Kontroluje výstupy po každé fázi (acceptance checks)
6. Provede finální session gates
7. Při problémech: retry (max 3), pak Slack escalation
8. Archivuje evidenci

## Scope

### Allowed files/paths
- .claude/agents/
- .claude/commands/
- .claude/skills/epic-orchestration/
- templates/
- playbooks/
- policies/
- evidence/
- workspace/
- docs/

### Forbidden zones
- Žádné (nový projekt, vše je v scope)

## Constraints
- Žádný externí framework (vše nativně v Claude Code)
- Decision policies musí pokrývat 90%+ rozhodnutí bez PM
- Evidence by design — každý run musí produkovat audit trail
- Zpětná kompatibilita s existujícím claude/ setupem

## DoD Gates
- Dummy EPIC projede celým pipeline end-to-end
- Všech 9 agentů funguje a produkuje výstupy
- Gates engine vyhodnotí pass/fail
- Retry loop funguje (záměrně failing gate → fix → pass)
- Evidence store obsahuje kompletní audit trail
- Dokumentace aktualizována

---

## Sessions

### Session 1: Foundation + Controller State Machine (Phase 0 + A)

**Cíl:** Přenést existující claude/ setup, vytvořit orchestrační skill
s Controller state machine a evidence store.

**Deliverables:**
- .claude/ setup přenesený a funkční
- `skills/epic-orchestration/instructions.md` — state machine logika
- `policies/decision-policies.yaml` — rozhodovací pravidla orchestrátora
- `policies/gates.yaml` — gates konfigurace
- `templates/epic.md` — EPIC šablona
- `templates/plan.schema.json` — Plan JSON schema
- `evidence/` directory structure
- CLAUDE.md pro projekt

**Acceptance:**
- Orchestrační skill se načte bez chyb
- Decision policies pokrývají: quality thresholds, arch principles,
  escalation triggers, auto-decisions

---

### Session 2: EPIC Runner Commands (Phase B)

**Cíl:** Vytvořit 4 orchestrační commands.

**Deliverables:**
- `commands/plan-epic.md` — Epic → Plan JSON + Session file
- `commands/run-epic.md` — hlavní orchestrační loop
- `commands/run-step.md` — manuální spuštění jednoho kroku
- `commands/epic-status.md` — zobrazení stavu

**Acceptance:**
- `/plan-epic` na dummy EPIC vytvoří validní Plan JSON
- `/epic-status` zobrazí stav
- `/run-step` spustí jeden krok s mock agentem

---

### Session 3: Gates Engine + Retry (Phase C)

**Cíl:** Gates runner, pass/fail reporting, retry loop.

**Deliverables:**
- Rozšíření quality-gates-runner agenta o gates.yaml parsing
- Pass/fail report generace do evidence/
- Retry loop logika v orchestrátoru (max 3 pokusy)
- Fix instrukce generace pro failing gate

**Acceptance:**
- Záměrně failing gate → retry → agent opraví → pass
- Gates report uložen do evidence/
- Po 3 failech: escalation (zatím print, Slack v Session 6)

---

### Session 4: Worker Agenti (Phase D)

**Cíl:** 9 role-based agentů + playbooks.

**Deliverables:**
- `agents/architect.md` + `playbooks/architect.md`
- `agents/domain.md` + `playbooks/domain.md`
- `agents/backend.md` + `playbooks/backend.md`
- `agents/frontend.md` + `playbooks/frontend.md`
- `agents/qa.md` + `playbooks/qa.md`
- `agents/security.md` + `playbooks/security.md`
- `agents/observability.md` + `playbooks/observability.md`
- `agents/docs-writer.md` + `playbooks/docs.md`
- `agents/release.md` + `playbooks/release.md`

**Acceptance:**
- Každý agent se načte bez chyb
- Dummy EPIC → dispatch každého agenta → každý vrátí smysluplný výstup
- Scope enforcement funguje (agent nepíše mimo allowed paths)

---

### Session 5: Planner + Paralelizace (Phase E)

**Cíl:** Automatická generace plánů a paralelní dispatch agentů.

**Deliverables:**
- Plan generator v `/plan-epic` — automaticky odvodí role, závislosti,
  paralelní skupiny z EPIC constraints
- Scheduler logika — branch per parallel agent, merge po dokončení
- Plan JSON validace proti schema

**Acceptance:**
- EPIC bez hints → orchestrátor správně odvodí všechny role a pořadí
- Paralelní kroky běží současně (branch per agent)
- Merge proběhne bez konfliktů
- Plan JSON validní dle schema

---

### Session 6: Slack Integrace + Autonomní Běh (Phase F)

**Cíl:** Slack MCP server pro escalation, automatický pickup dalšího EPICu.

**Deliverables:**
- MCP server pro Slack (send_escalation, wait_for_reply, send_status)
- Integrace escalation triggers z decision-policies.yaml
- Epic queue — automatický pickup dalšího EPICu po dokončení
- Timeout handling (co když PM neodpoví)

**Acceptance:**
- Escalation → Slack zpráva přijde
- PM odpověď → orchestrátor pokračuje
- 2 EPICy v řadě bez manuálního zásahu (kromě Slack)

---

### Session 7: End-to-End Test + Hardening

**Cíl:** Reálný EPIC na reálném projektu, fix edge cases.

**Deliverables:**
- EPIC-ERP-0001 (reálný ERP modul) projede celým pipeline
- Edge case handling (agent crashne, prázdný výstup, conflict)
- Performance tuning (timeout per agent, paralelizace)
- Finální dokumentace aktualizace

**Acceptance:**
- Reálný EPIC: start → plan → 9 agentů → gates → evidence → done
- Žádný manuální zásah (kromě initial APPROVE a Slack escalations)
- Evidence store kompletní
- docs/MULTIAGENT_GUIDE.md aktualizován

---

## Dependencies

```
Session 1 (foundation)
    ↓
Session 2 (commands)
    ↓
Session 3 (gates + retry)
    ↓
Session 4 (9 agentů)
    ↓
Session 5 (planner + parallel)
    ↓
Session 6 (slack + autonomie)
    ↓
Session 7 (E2E test)
```

Všechny sessions jsou sekvenční — každá staví na předchozí.

## Hints
- skip_roles: [frontend] (ADO nemá UI — Phase G optional)
- Používat existující agenty z claude/ kde to dává smysl
  (code-reviewer, quality-gates-runner, docs-reviewer)
