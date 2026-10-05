# Kritické posouzení: AID Orchestrator vs. holý Claude Code

**Datum:** 2026-03-03
**Metoda:** Deep research 6 paralelními agenty + validace 5 specializovanými review agenty
**Autor:** Claude Opus 4.6

**Fáze 1:** 6 agentů (architektura, orchestrace, skills/agenti, integrace, QA, value-add analýza)
**Fáze 2:** 5 validačních agentů (Devil's Advocate, Industry Expert, Tech Debt Auditor, UX/DX Expert, Business/ROI Analyst)

---

## Fakta v číslech

| Metrika | Hodnota |
|---------|---------|
| Celkem souborů | ~1 138 |
| Řádků kódu/instrukcí | ~230 000 |
| Z toho Markdown (prompty, instrukce) | ~127 000 řádků (55 %) |
| Z toho TypeScript (GUI + server) | ~33 000 řádků |
| Z toho Bash (pipeline skripty) | ~6 800 řádků |
| Agentů | 18 |
| Skills | 27 |
| Příkazů | 14 |
| YAML konfiguračních souborů | 10 |
| Playbook souborů | 11 |
| Celkem prompt tokenů systému | ~300 000 |
| Commitů | 293 za 14 dní |
| Tagovaných verzí | 15 (v0.4.2 → v1.7.0) |
| Vlastní audit skóre | 30/100 (FAIL) |

---

## Architektura (shrnutí)

### Core abstrakce
- **Plan** (P-NNN) → specifikace záměru
- **EPIC** (E-{plan}-{phase}_{total}) → konkrétní pracovní jednotka
- **Run** (R-{epic}-{run}) → strukturovaný log exekuce
- **Step** → jeden agent s jednou rolí
- **Phase/Wave** → topologicky seřazené skupiny kroků

### 11-stavový FSM
```
IDLE → PLANNING → PLAN_REVIEW → EXECUTING ←── NEXT_PHASE ←── PHASE_CHECK
                                   │                                │
                                   └──(all steps done)──► GATES → GATE_RETRY
                                                              │
                                                         CURATOR_RESOLVE
                                                              │
                                                         PM_APPROVAL
                                                              │
                                                            DONE
```

### 18 agentů
- **9 rolí:** architect, domain, backend, frontend, qa, security, observability, docs-writer, release
- **6 utility:** code-reviewer, docs-reviewer, gate-fixer, lessons-extractor, run-validator, quality-gates-runner
- **3 specialisté:** curator, auditor, project-scanner

### Tech stack
- Plugin: Markdown instrukce + Bash 4.0+ skripty (jq, sed, awk)
- GUI server: TypeScript/Express/WebSocket (port 9911)
- GUI frontend: React 19, Zustand, Tailwind, Radix UI, Recharts, Playwright
- Volitelné: Qdrant MCP, Slack MCP, Context7 MCP

---

## Co AID skutečně přináší nad holý Claude Code

### 1. Persistentní stavový automat s evidence trail (unikátní)
Když Claude Code session spadne nebo se vyčerpá context window, máš nula. AID ukládá:
- `stage_log.jsonl` — každý state transition s timestampem
- `plan_progress.json` — obnovitelný stav across sessions
- `steps/step_N_role/output.md`, `prompt.md`, `diff.patch`, `review.md` per krok
- `gates_report.json`, `pm_plan_approval.json`, `pm_decision.json`, `final_report.md`

**Claude Code tohle nemá a nebude mít.** Pokud session zemře uprostřed 8-step pipeline, AID umožní pokračovat přesně tam, kde skončil.

### 2. Dependency-graph paralelní dispatch (unikátní)
- Kahnův algoritmus pro topologický sort v bash skriptech
- Detekce cyklů v dependency grafu
- Git worktree per paralelní agent
- Dry-run merge conflict detection před commitnutím do paralelní exekuce
- Scope isolation (allowed_paths / forbidden_paths per step)

**Claude Code umí spustit paralelní agenty, ale neřeší závislosti mezi nimi, nedetekuje konflikty, a neisoluje file scope.**

### 3. Curator + Lessons feedback loop (unikátní)
- Automatický sběr `improvement_notes` ze všech agentů
- Deduplikace proti backlogu
- 3-tier auto-evaluace: YAML pravidla → Qdrant historická rozhodnutí → default
- Inline fix pro S/M effort proposals, backlog pro L
- Cross-session, cross-project učení přes Qdrant

**Claude Code má memory, ale ne strukturovaný improvement loop.**

### 4. Token cost observability (unikátní)
- Odhad tokenů per dispatch, agregace per role/model/step
- Trend analýza přes Qdrant across EPICs a projektů
- BMK-001 baseline: 6-step EPIC = 3,5M tokenů, ~$95, 140 min

**Claude Code nedává žádnou viditelnost do nákladů sub-agentů.**

### 5. FIRST AID s principiální eskalací (unikátní)
- 16-trigger eskalační matice (E1-E16)
- Eskalační budget (max 3 per session, konfigurovatelný)
- Rozlišení agent-resolvable vs. human-required
- Permission sandwich: backup settings → elevate → run → restore
- Credit exhaustion detection (6 regex patterns)
- Slack notifikace pro PM (volitelné)

**Claude Code nemá strukturovaný autonomní mód.**

### 6. Web dashboard s real-time pipeline vizualizací (unikátní)
- React 19 GUI na portu 9911
- WebSocket streaming `stage_log.jsonl` events
- Kanban board pro EPIC queue
- Evidence Vault pro prohlížení per-step artefaktů
- Pipeline Theater pro live sledování exekuce
- AI Companion (Vercel AI SDK adapter)
- Docker single-image deployment

---

## Co AID duplikuje (Claude Code už umí nativně)

| AID komponenta | Claude Code ekvivalent | Redundance |
|---|---|---|
| `plan_progress.json` tracking | TodoWrite | Částečná (AID je persistent) |
| Agent dispatch přes Task | Task/Agent tool s `model` param | Nízká (AID přidává kontext assembly) |
| Quality gates | Hooks systém | Částečná (AID přidává retries + fix agenty) |
| 14 custom příkazů | Slash commands v CLAUDE.md | Nízká (AID je strukturovanější) |
| Brainstorming flow | Plan mode + AskUserQuestion | **Vysoká** |
| Git worktree izolace | `using-git-worktrees` superskill | Částečná |
| CLAUDE.md injekce | CLAUDE.md project instructions | **Identická** |

---

## Kritické problémy

### 1. Neúnosná komplexita pro běžné úlohy
2-3hodinový feature vyžaduje: brainstorm → plan → EPIC → pipeline skript → plan review → execute. To je **4+ CLI příkazy a 30-60 minut overhead** než se napíše první řádek kódu. Pro 80 % denní práce je to zbytečné.

### 2. Kognitivní zátěž: 15+ konceptů
Plan, EPIC, Run, Step, Phase, Wave, Gate, Curator, Escalation, FIRST AID, aspirin/steroids, dispatch-config, context scope, plan.json schema, EPIC ID formát (`E-015-1_2` = plan 15, phase 1 of 2)... Nový uživatel musí absorbovat malou encyklopedii.

### 3. Údržbová zátěž
- 8 souborů musí být synchronizovaných při každém releasu
- "Last Updated" patičky v každém skill souboru
- 10 YAML politik per projekt
- Vlastní audit dal projektu **30/100** — dokumentace 21/100, process 35/100
- README GUI obsahoval Gemini boilerplate (opraven až ve v1.7.0)

### 4. Žádné CI pro testy
88+ bash testů + 31 Vitest souborů existují — ale **jediný GitHub Actions workflow pouze deployuje Docusaurus docs**. Testy se nikdy nepouštějí automaticky v CI.

### 5. Nevalidovaný ROI
BMK-001 baseline: 6-step EPIC = 3,5M tokenů, ~$95, 140 minut. Ale **neexistuje kontrolní srovnání** s manuálním Claude Code. Tvrzení "šetří čas" je nepodložené daty.

### 6. Objem promptových instrukcí: ~300K tokenů
Systém je z 95 % Markdown instrukce pro LLM. Načítají se on-demand (dobrý design), ale controller agent přečte 10-20K tokenů skill souborů per state transition. Overhead je inherentní multi-agent orchestraci, ale 27 skills je příliš mnoho.

### 7. 293 commitů za 14 dní = rushed development
Průměr 21 commitů/den od jednoho developera. Rychlost je impresivní, ale ukazuje na potenciální technický dluh — potvrzeno audit skóre 30/100.

---

## Srovnávací tabulka: AID vs. holý Claude Code

| Scénář | Holý Claude Code | AID Orchestrator |
|--------|-----------------|------------------|
| Jednoduchý bugfix (< 1h) | Okamžitý start, 0 overhead | Overkill — 30 min setup |
| Feature 2-4h | Plan mode → implementace | Overhead převyšuje benefit |
| Feature 1-2 dny, 4-8 kroků | Manuální koordinace, riziko ztráty kontextu | **Sweet spot AID** — FSM, evidence, resume |
| Noční autonomní běh, 3+ EPICs | Nemožné — vyžaduje přítomnost | **Hlavní use case AID** — FIRST AID mode |
| Multi-agent paralelismus s dependencies | Manuální, error-prone | **Silná stránka** — DAG + worktrees |
| Cross-session knowledge | Memory soubory, manuální | Qdrant + lessons, automatické |
| Audit trail & compliance | Žádný | Kompletní evidence store |

---

## Doporučení pro budoucí směr

### Varianta A: Radikální zjednodušení (doporučeno)

Zachovat **3 unikátní jádra**, zahodit zbytek:

1. **Evidence engine** — `stage_log.jsonl` + `plan_progress.json` + per-step artifacts. Extrahovat jako **standalone lightweight plugin** (~5 skill souborů místo 27).

2. **DAG pipeline skripty** — 5 bash skriptů pro Plan→EPIC→JSON→Run. Deterministic, testované. Ponechat.

3. **FIRST AID controller s eskalační maticí** — Zjednodušit z 11 stavů na 6-7 (IDLE → PLANNING → EXECUTING → GATES → ESCALATION → DONE).

**Zahodit:**
- 18 hardcoded agentů → dynamické role prompty z `project-profile.yaml`
- 11 playbooks → spojit s agent definicemi (duplicita)
- Brainstorming skill → Claude Code Plan mode je dostatečný
- Slack MCP integration → okrajový use case
- Token estimator skill → přibližné a nepřesné
- 10 YAML policy souborů → 1-2 maximálně

**Cílový stav:** 5-8 skill souborů, 3-5 příkazů, 0 playbooks, ~30K tokenů instrukcí místo 300K.

### Varianta B: Pivotovat na GUI dashboard

GUI (`aid-gui` + `aid-server`) je technicky solidní — React 19, Zustand, Recharts, WebSocket. Odpojit od plugin systému, udělat standalone vizualizační produkt. Plugin by byl jen data provider.

### Varianta C: Archivovat a čerpat z lessons learned

Projekt splnil účel: prozkoumal multi-agent orchestraci přes Claude Code plugin systém. Výsledky přenést do existujících workflow (CICERO framework), AID archivovat.

---

## Verdikt

**AID není koš.** Obsahuje 3-4 genuinely inovativní komponenty (evidence trail, DAG dispatch, feedback loop, autonomní mód), které Claude Code nemá a nebude mít v dohledné době. Bash pipeline skripty jsou reálný, testovaný engineering.

**Ale AID je 5× větší, než potřebuje být.** 300K tokenů instrukcí, 18 agentů, 27 skills, 14 příkazů — enterprise orchestrační platforma pro jednoho developera. 80 % komplexity slouží 20 % use cases.

**Doporučení: Varianta A** — extrahovat 3 unikátní jádra do lightweight pluginu, zbytek archivovat nebo (GUI) oddělit jako standalone projekt.

---

## Příloha: Evidence

### Zpracované plány a EPICs
- 21+ archivovaných plánů (P001-P021)
- 20+ archivovaných EPICs
- Projekt používá sám sebe k vlastnímu vývoji od v0.9

### Lessons learned (vybrané, z 30 záznamů)
- "Parallel dispatch (QA + docs) saves ~15 min vs sequential"
- "When architect step produces thorough ADRs, backend steps succeed on first attempt with 0 retries"
- "Session resume across context compaction works — EPIC state machine is fully recoverable"
- "Claude API 500 errors: switch dispatch model to sonnet immediately"

### Vlastní audit
- Celkové skóre: 30/100 (FAIL)
- Dokumentace: 21/100
- Process: 35/100
- Nalezené problémy: 3× path traversal vulnerability (opraveno v1.7.0), Gemini boilerplate README (opraveno v1.7.0)

### Test coverage
- 31 Vitest souborů (frontend + server)
- 88+ bash testů (pipeline skripty)
- 1 Playwright E2E test
- 0 CI workflows pro automatické spuštění testů

---
---

# FÁZE 2: Validace a kritické přezkoumání

*5 nezávislých validačních agentů přezkoumalo výše uvedený assessment. Následují jejich zjištění.*

---

## Validátor 1: Devil's Advocate

### Korekce původního assessmentu

**Assessment podcenilo redundanci.** Několik položek označených jako "nízká redundance" by mělo být "vysoká":
- Agent dispatch přes Task → Claude Code Task tool dělá totéž, "kontext assembly" je 50 řádků promptu, ne celý skill
- 14 custom příkazů → slash commands v CLAUDE.md dělají totéž
- Git worktree izolace → Claude Code má nativní EnterWorktree tool

**Assessment podhodnotil tokeny.** Skutečnost je ~424K tokenů (ne 300K) — podhodnocení o 40 %. Včetně pluginového Markdownu bez CHANGELOG a testů.

### Fatální architektonické problémy

**FSM v Markdownu není FSM.** 11-stavový automat implementovaný jako Markdown instrukce pro LLM není deterministický. LLM může (a bude) dělat chyby ve state transitions. To není "stavový automat" v engineering smyslu — je to **prompt, který doufáme, že LLM následuje**.

**Scope isolation je trust-based, ne enforced.** `allowed_paths` / `forbidden_paths` jsou jen instrukce pro LLM. Agent MŮŽE modifikovat soubory mimo povolené cesty — prompt ho jen "prosí," aby to nedělal.

### Opomenuté problémy

1. **OpenAI API klíč v `.env` souboru na disku** — `.env` není trackován v gitu, ale soubor fyzicky existuje. Security incident.
2. **NIH syndrom** — token estimator místo tiktoken, FSM v Markdownu místo XState, evidence store místo SQLite, queue místo Redis/BullMQ. Claude Code plugin systém není navržen pro takto komplexní orchestraci.
3. **Schizofrenie identity: Plugin vs. Aplikace** — tvrdí se "Claude Code plugin", ale obsahuje Express server, React 19 GUI, Docker deployment, Docusaurus web. To není plugin, to je aplikace s plugin interfacem.
4. **Duplicitní example soubory** ve dvou umístěních s různým obsahem.

### Upravený verdikt

**Assessment byl o stupeň příliš laskavý.** "AID je 5× větší než potřebuje být" je eufemismus. AID je **10× větší a postavený na špatné platformě** pro tento typ orchestrace. Markdown-instrukce-driven FSM není engineering, je to **doufání, že LLM bude následovat instrukce**.

**Doporučení:** Varianta C+ (archivovat s selektivní extrakcí bash pipeline skriptů a GUI jako standalone projektu).

---

## Validátor 2: Industry Expert (AI orchestrace)

### Srovnání s existujícími frameworky

| Framework | Architektura | Srovnání s AID |
|-----------|-------------|----------------|
| **LangGraph** | Stavový graf v Pythonu, checkpointing, resumable | AID dělá totéž, ale v Markdownu místo kódu |
| **CrewAI** | Role-based multi-agent, sekvenční/paralelní | AID kopíruje pattern (9 rolí) |
| **AutoGen** | Multi-agent konverzace | AID nemá inter-agent komunikaci |
| **Temporal** | Deterministický workflow engine, replay | AID evidence trail je primitivní verze |
| **Prefect/Airflow** | DAG orchestrace s retry, monitoring | AID bash skripty jsou zjednodušená verze |

**AID reimplementuje známé patterny z workflow orchestrace, ale v Markdown instruktech místo kódu.** Evidence trail je standardní praxe v Temporal/Prefect — AID ji jen aplikuje na AI agenty.

### "Prompt as code" — dlouhodobá životaschopnost

**95 % Markdown instrukce je fundamentální riziko:**
- Žádná typová bezpečnost
- Žádné testy na instrukce (bash testy testují skripty, ne skills)
- Závislost na specifickém chování LLM, které se mění měsíčně
- Nelze refaktorovat s toolingem (rename, find references)

### Tržní pozice

Pro open-source projekt: cílová skupina ~500-2 000 lidí globálně. Příliš komplexní pro mainstream, příliš specifické pro enterprise. Fundamentálně personal productivity tool, který se negeneralizuje.

---

## Validátor 3: Tech Debt Auditor

### Kritický nález: 49 cyklických závislostí

Dependency graf mezi 28 skills obsahuje **49 cyklů**. Vybrané:

| Cyklus | Soubory |
|--------|---------|
| 2-uzlový | `brainstorming` ↔ `workflow-intelligence` |
| 2-uzlový | `epic-orchestration` ↔ `cost-optimization` |
| 2-uzlový | `epic-state-machine` ↔ `epic-queue` |
| 2-uzlový | `first-aid-controller` ↔ `gate-evaluation` |
| 2-uzlový | `dispatch-protocol` ↔ `epic-state-machine` |
| 2-uzlový | `planner` ↔ `brainstorming` |
| 2-uzlový | `retry-engine` ↔ `gates-engine` |
| 13-uzlový | `agent-core` → `analysis-merge` → `planner` → ... → zpět na `agent-core` |

**Důsledek: Skills nejsou modulární. Nelze "extrahovat 3 jádra" bez přepsání většiny obsahu.** Varianta A z původního assessmentu je rewrite from scratch, ne refaktoring.

### Mrtvý kód

- **3 playbooks bez agenta:** `docs-generic.md` (0 referencí), `docs-docusaurus.md` (jen kopírován), `e2e.md` (agent `e2e` neexistuje, ale planner generuje kroky s role `e2e`)
- **Nekonzistentní struktura:** Role agenti mají Identity→Capabilities→Constraints, utility agenti mají zcela jinou strukturu
- **2 zdroje pravdy pro model assignment:** agent frontmatter `model:` vs `dispatch-config.yaml`
- **7 z 28 skills chybí povinná "Last Updated" patička**

### Klíčový nález: Curator feedback loop nefunguje

Z `auto-mode-state.yaml`:
- `total_curator_proposals: 10`
- `total_curator_implemented: 0`
- `total_curator_deferred: 10`

**Za 4 EPICy systém implementoval 0 z 10 návrhů Curatora.** Feedback loop — prezentovaný jako jedna z "unikátních hodnot" — v praxi nefunguje.

### Velikost souborů

| Skill | KB | Červená vlajka |
|-------|-----|----------------|
| `planner.md` | 84 KB | ANO |
| `knowledge-acquisition.md` | 76 KB | ANO |
| `workflow-intelligence.md` | 40 KB | Hraniční |
| `memory-mcp.md` | 40 KB | Hraniční |

### Config sprawl

`/aid-init` nakopíruje do projektu **55 souborů** (~7 910 řádků konfigurace). Pro typický projekt je to disproportionální.

---

## Validátor 4: UX/DX Expert

### First-time experience: 10 kroků k prvnímu výsledku

1. Nainstalovat Claude Code
2. `/plugin marketplace add`
3. `/plugin install`
4. `/aid-init` → 44+ souborů v projektu
5. `/aid-setup` → interaktivní dialog
6. `/aid-brainstorm` → 8-krokový dialog (10+ zpráv)
7. Zkontrolovat Plan
8. `/aid-plan-epic` → generuje 3 soubory
9. Zkontrolovat EPIC
10. `/aid-run-epic` → teprve teď se začíná pracovat

**30-60 minut než se napíše první řádek kódu.**

### Srovnání: "Přidej login button"

| | AID Orchestrator | Bare Claude Code |
|---|---|---|
| Čas | 45-90 minut | 2-3 minuty |
| Příkazy | 4+ CLI příkazy | 1 zpráva |
| Soubory konfigurace | 44+ | 0 |
| Koncepty k pochopení | 15+ | 0 |

### Klíčové UX problémy

1. **Žádný "easy mode"** — neexistuje cesta jak říci AIDu "prostě to udělej" bez Plan/EPIC/Run ceremoniálu
2. **Terminologie jako bariéra** — "CURATOR_RESOLVE", "PHASE_CHECK", "aspirin/steroids" nejsou intuitivní
3. **Konfigurační tsunami** — 44 souborů při inicializaci je zahlcující
4. **Chybí srovnání s alternativou** — dokumentace nikde neříká "pro jednoduché tasky prostě použijte Claude přímo"

### Kde AID vyhrává

- Noční autonomní běh (FIRST AID) — nezastupitelný
- Evidence trail pro audit/compliance
- Multi-day features s obnovou po pádu session
- Paralelní agenti s dependency management

### Verdikt UX experta

**"80 % denní práce solo developera padá do kategorie, kde AID přináší pouze zápornou hodnotu."** Sweet spot je 1-2 denní feature nebo noční autonomní běh.

---

## Validátor 5: Business/ROI Analyst

### Náklady na vývoj

| Položka | Odhad |
|---------|-------|
| Lidské hodiny | 150-180h za 14 dní |
| Lidská práce (@ $60/h) | $9 000-10 800 |
| LLM (MAX plan) | $200/měsíc |
| **Celkový sunk cost** | **~$9 200-11 200** |

### Měsíční údržba

| Položka | Měsíční náklad |
|---------|---------------|
| Údržba (45-85h @ $60/h) | $2 700-5 100 |
| MAX plan | $200 |
| Krizové updaty (CC se mění) | $480-960 |
| **Celkem** | **$3 380-6 260/měsíc** |

### Kritické zjištění: 100 % self-referenčních EPICů

Z 33 archivovaných plánů a 46 archivovaných EPICů:
- P001-P003: Release protokol, refactoring, FIRST AID → **vnitřní infrastruktura AID**
- P004: Brainstorming enhancement → **AID**
- P005 (A-D): GUI dashboard → **AID**
- P006-P021: Pipeline fixes, hardening, security → **vše pro AID**

**Ani jeden plán neřešil externí softwarový produkt.** Projekt tráví veškerou energii na sebe sama — **perpetuum mobile bez externího výstupu**.

### Token tracking feature: implementována, nikdy použita

Feature implementovaná v E-017 (usage_summary, usage object). Po kontrole **všech** plan_progress.json a stage_log.jsonl: **nulová usage data**. LLM instrukce ignoruje.

### Sunk cost trap diagnostika

| Indikátor | Přítomen? |
|-----------|-----------|
| Rostoucí komplexita bez externího užití | **ANO** |
| Projekt pracuje sám na sobě | **ANO** |
| Feature creep (voice dictation, AI Companion) | **ANO** |
| Nedokončené implementace | **ANO** |
| Rush development (293 commitů/14 dní) | **ANO** |
| Dokument ukazuje na budoucí hodnotu, žádní reální uživatelé | **ANO** |

**Verdikt: Klasický sunk cost trap.** Pokračovat má smysl POUZE po radikálním řezu a POUZE pokud se systém osvědčí na **externím projektu** během 2-4 týdnů.

---

## Konsenzus validátorů

### Na čem se shodli všichni (5/5):

1. **Assessment byl příliš laskavý** — redundance je vyšší, komplexita závažnější
2. **49 cyklických závislostí** znemožňuje modulární extrakci (Varianta A je rewrite, ne refaktoring)
3. **0 externích uživatelů, 100 % self-referenčních EPICů** — žádná validace reálné hodnoty
4. **FSM v Markdownu není deterministický** — je to prompt, ne engine
5. **Údržba (~$3-6K/měsíc) pravděpodobně převyšuje přínos**

### Na čem se neshodli:

| Otázka | Devil's Advocate | Industry Expert | Tech Debt | UX Expert | Business |
|--------|-----------------|-----------------|-----------|-----------|----------|
| Archivovat? | C+ (archiv + extrakce) | Spíš ano | Neutrální | Ne (zachovat FIRST AID) | Ano, pokud ne rewrite |
| Bash skripty mají hodnotu? | Ano | Ano | Ano | Ano | Ano |
| GUI má hodnotu? | Oddělit | Commodity | Neutrální | Ano jako standalone | Nízká |
| Evidence trail unikátní? | Ne (Temporal dělá totéž) | Standardní praxe | Ano | Ano | Ano |

### Upravené doporučení po validaci

**Původní doporučení "Varianta A" (radikální zjednodušení) je nerealistické** kvůli 49 cyklickým závislostem. Modularní extrakce by vyžadovala rewrite.

**Revidované doporučení:**

**Varianta C+ (Archivovat s cílenou extrakcí):**

1. **Zachovat:** 5 bash pipeline skriptů + 92 testů (skutečný, deterministický, testovaný kód)
2. **Oddělit:** GUI (aid-gui + aid-server) jako standalone vizualizační projekt
3. **Přenést:** Lessons learned (30 záznamů) + architektonické vzory do CICERO
4. **Archivovat:** Vše ostatní (27 skills, 18 agentů, 14 příkazů, 10 politik, 11 playbooks)
5. **Validovat:** Použít extrahované komponenty na externím projektu do 2-4 týdnů

**Klíčový test:** Pokud bash skripty + zjednodušený evidence engine nepřinesou měřitelnou hodnotu na CICERO projektu do 4 týdnů, archivovat kompletně.

---
---

# FÁZE 3: Korekce na základě reálných dat

*Po zveřejnění assessmentu majitel projektu napadl 2 klíčová tvrzení. 3 verifikační agenti prošli skutečné soubory a stage logy. Následují korekce.*

---

## Korekce 1: Curator FUNGUJE — tvrzení "0 implemented" je NEPRAVDIVÉ

**Původní tvrzení (Validátor 3):** "Za 4 EPICy systém implementoval 0 z 10 návrhů Curatora."

**Zdroj chyby:** Validátor četl jeden soubor (`auto-mode-state.yaml` nebo jeden `curator_resolve_report.json` se stavem pending) místo celé evidence.

**Reálná data ze stage_logů a backlogu:**

| Zdroj | Implemented |
|-------|-------------|
| `backlog.md` sekce `## Implemented` | **21 záznamů** |
| `curator_resolve_report` E-016-1_3 | 4 (IMP-049–052, effort S) |
| `curator_resolve_report` E-016-3_3 | 2 (IMP-067, IMP-069, effort S) |
| `curator_resolve_report` E-20260224-fa01 | 5 (IMP-033–040, effort S) |
| Přímé stage_log záznamy `curator_fix_*` | min. 15 direct fixes |

**Konkrétní příklady implementovaných oprav (ze stage_log.jsonl):**
- `curator_fix_IMP-067`: "Fixed stepsTotal in pipeline.ts — now derives from per-EPIC aggregate"
- `curator_fix_IMP-069`: "Fixed notification click nav — replaced pushState+PopStateEvent with window.location.href"
- Security: path traversal CWE-22 v audit.ts, epics.ts, evidence.ts (detekováno a opraveno)

**Správné hodnocení:** Curator byl aktivován ve 10+ CURATOR_RESOLVE stavech, implementoval minimálně 21 oprav (backlog) / 15 přímých fixů (stage_log). Feedback loop **funguje**. Kritika "0 implemented" byla postavena na špatných datech.

---

## Korekce 2: AID STAVĚL EXTERNÍ PROJEKTY — "100% self-referential" je NEPRAVDIVÉ

**Původní tvrzení (Validátor 5):** "Ani jeden plán neřešil externí softwarový produkt — perpetuum mobile bez externího výstupu."

**Reálná data:**

```
find /opt/_home/small-personal-projetcs/ -name ".aid-o" -type d
→ /opt/_home/small-personal-projetcs/ai-orchestrator/.aid-o  (self-dev)
→ /opt/_home/small-personal-projetcs/assignment2/.aid-o      (EXTERNAL)
→ /opt/_home/small-personal-projetcs/assignment1/.aid-o      (EXTERNAL)
```

**assignment2 — Trading Analysis Agent (LangGraph + MCP + Qdrant + Streamlit):**
- Stage log: `FIRST-AID-FA-20260228T210000Z`, trvání 1h 5m, 7 kroků, 0 eskalací
- Výstup: **34 souborů, 2140 řádků Python kódu, 50/50 testů prošlo**
- Projekt je školní zadání, zcela nezávislý na AID infrastruktuře

**assignment1:** Aktivní EPIC `E-001-1_1-crypto-macro-intelligence-agent` — zatím ve frontě.

**Správné hodnocení:** AID byl použit na minimálně 2 externích projektech. "Dogfooding" přes self-development byl záměrný testovací přístup (validní strategie), ale vedlejším produktem jsou i reálné projekty.

---

## Korekce 3: Přesnost ostatních numerických tvrzení

| Tvrzení | Verdict | Realita |
|---------|---------|---------|
| "49 cyklických závislostí" | **PŘESTŘELENO** | 36 ověřitelných obousměrných odkazů (49 nelze reprodukovat) |
| "88+ bash testů" | **ZASTARALÉ** | 92 testů (číslo správné pro mezistav, finální = 92) |
| "55 souborů při /aid-init" | **ZAVÁDĚJÍCÍ** | defaults/ má 55 souborů, aid-init kopíruje ~40 (vynechává examples/) |
| "planner.md 84 KB" | **PŘIBLIŽNĚ SPRÁVNÉ** | 85 070 bajtů = 83 KB (binary) — marginální chyba zaokrouhlení |
| "293 commitů za 14 dní" | **POTVRZENO** | Přesně 293, vše od autora marekstancl, žádné AI-generated commits |
| "token tracking nikdy použita" | **POTVRZENO** | 0 usage dat v 32 stage_log.jsonl + všech plan_progress.json |

---

## Upravený konsenzus po korekcích

### Co zůstává v platnosti:

1. **FSM v Markdownu není deterministický** — stále platí (token tracking feature to dokládá: instrukce implementována, LLM ji ignoruje)
2. **36 cross-reference cyklů** — modulární extrakce je stále náročná, jen ne tak extrémní jako tvrdil "49 cyklů"
3. **UX overhead** — 10 kroků k prvnímu výsledku, 30-60 min setup pro jednoduché tasky — stále platí
4. **"Prompt as code" risk** — závislost na LLM chování stále platí

### Co bylo opraveno:

1. ~~"Curator nefunguje"~~ → **Curator funguje, 21 implementovaných oprav, automatické S/M fixes v FIRST AID**
2. ~~"100% self-referential EPICs"~~ → **Minimálně 2 externí projekty (assignment1, assignment2), trading agent se 2140 řádky kódu a 50 testy**
3. ~~"Sunk cost trap bez externího výstupu"~~ → **Dogfooding je validní strategie; projekt generoval reálné artefakty**
4. ~~"49 cyklů"~~ → **36 obousměrných odkazů** (závěr o obtížné modulární extrakci stále platí, jen méně dramaticky)

### Revidované doporučení

Původní **Varianta C+** (archivovat) byla částečně postavena na nepravdivých předpokladech. Se správnými daty:

**Varianta A/C hybrid:**
- Curator funguje → stojí za zachování
- FIRST AID se 0 eskalacemi na externím projektu → prokázal reálnou hodnotu
- Evidence trail (stage_log, plan_progress) → klíčová hodnota pro obnovu session
- 36 cross-reference cyklů → zjednodušení je náročnější než refaktoring, ale ne nemožné

**Realistický path forward:** Provoz v aktuální formě pro komplexní projekty (1+ den), zjednodušený vstup pro menší tasky. Neochratovat za každou cenu — ale neArchivovat jen proto, že validátoři nezkontrolovali všechna data.
