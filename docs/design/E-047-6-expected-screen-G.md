# E-047-6_7 — Expected Screen G v2 (PLAN-FIRST, hand-built over real data)

**Supersedes v1** (the v1 EPIC-frontier audit is kept as §Appendix). Manually derived
from all six projects' real `.aid-o` by per-project evidence agents (fsm-state + git +
plan frontmatter + `active.md`/`SESSION-CONTEXT` ledgers + task-archive location). This
is the oracle Marek approves BEFORE any read-model change. No code.

**Managerial unit = PLAN.** Project → its plans → plan state & purpose → EPICs (drill-down).

## Three findings that reshape the read-model (binding)

1. **fsm-state alone is unreliable.** krok P014, vulcan P044/P045/P049, wan legacy plans:
   work is merged in **git** while `fsm-state` still reads READY/pending. Evidence must be
   **multi-source** — fsm-state + git close/merge commits + plan `status:` frontmatter +
   `work/active.md`/`SESSION-CONTEXT.md` ledgers + task-archive location. When sources
   conflict or are missing → `stav nelze ověřit`, never a guessed active/done.
2. **"EPICs done but task not archived" = closure debt, NOT active work.** ~12 wan plans
   sit here. The cockpit must show this as `dokončeno, neuzavřeno` (housekeeping), never as
   the current frontier.
3. **Evidence completeness is first-class.** `úplná` / `částečná` / `chybí` per plan;
   low-trust plans stay visible but out of urgent actions.

## Plan state set (evidence-based; age never sets state)

`aktivně se vyvíjí` · `připraven ke spuštění` · `čeká na rozhodnutí` (DONE review, no
pm_decision) · `blokovaný` (ESCALATION / frontier blocking failure / open P0) ·
`plánovaně pozastavený` (explicit marker only) · `rozpracovaný – stav nelze ověřit` ·
`dokončeno, neuzavřeno` (EPICs released, task not archived) · `dokončený` · `opuštěný/historický`.
`stale` is only a FLAG on `aktivně se vyvíjí` where movement was expected.

---

## SCREEN G — first viewport = portfolio of 6 projects (plan-first)

Per project: human state + its OPEN plans (with what each delivers, state, frontier EPIC,
last activity, next step), and per-plan decisions/blockers/risks + data trust. Done/historical
plans collapse into one count per project. "Na čem se právě pracuje" is ONE slice below this.

### Portfolio

| Projekt | Lidský stav | Otevřené plány (stav) | Dokončené/archiv | Data |
|---|---|---|---|---|
| **sousto-na-miru** 🟠 | 1 plán běží, ale 3 týdny stojí; jediný LIVE prod web | **P009 Security Hardening** — `aktivně se vyvíjí` ⚠️stale | 7 done | částečná |
| **wan** 🔵 | 1 reálná frontier + 1 rozhodnutí; velká closure-debt + legacy ocas | **P045 Nová smlouva** — `aktivně se vyvíjí` (frontier); **P039 model dokumentu** — `čeká na rozhodnutí` | 15 done · ~12 dokončeno-neuzavřeno · 14 nelze ověřit | smíšená |
| **krok** 🟡 | 1 plán dokončován, 2 čekají na merge | **P014 AI pipeline** — `aktivně se vyvíjí` (E-014-7_7 Docusaurus); **P010**, **P012** — `čeká na rozhodnutí` | 7 done · 3 nelze ověřit | částečná (git≠fsm) |
| **acta** 🟡 | NENÍ klid — 1 plán připraven ke spuštění | **P007 Spolehlivý příjem faktur** — `připraven ke spuštění` (E-007-4_4 nikdy neběžel) | 6 done | úplná (frontier EPIC chybí) |
| **aid-orchestrator** 🟡 | 1 plán v reopen (tento) + 1 ready | **P047 Cockpit MVP1** — `aktivně se vyvíjí` (REOPEN); **P048 fidelity** — `připraven ke spuštění` | 10 done · 44 archiv · 2 nelze ověřit | smíšená |
| **vulcan** 🟢/⚠️ | EPIC pipeline klidná, ale otevřený **P0 bezpečnostní blocker** mimo plány | **B-140** (RLS leak, P0) — `blokovaný` riziko; P048 DR `připraven`; 4 stuby `nelze ověřit` | 32 done · 16 archiv | nízká (API progressPct klame; git autoritativní) |

### Co čeká na mě (rozhodnutí) — vždy připojené k projektu+plánu

| Projekt / plán | Rozhodnutí | Možnosti | Důkaz |
|---|---|---|---|
| krok / P010 Quick Wins | EPIC hotový (13/13), čeká na merge | merge / fix / abort | `work/evidence/P010/run-p010-001/state.yaml` DONE done_phase=review, bez pm_decision |
| krok / P012 Process Editor Deep | EPIC hotový (16/16), čeká na merge | merge / fix / abort | `work/evidence/P012/run-p012-001/state.yaml` DONE review |
| wan / P039 model dokumentu | E-039-2_2 hotový, čeká na merge (audit 83/100) | merge / fix / abort | `work/evidence/E-039-2_2/.../fsm-state.yaml` DONE review |

> Pozn.: krok P014/E-014-1_7 je v FSM `review`, ale git ukazuje merge → **konflikt důkazů**, klasifikovat jako „nelze ověřit rozhodnutí", ne čisté čekající rozhodnutí.

### Co je skutečně zablokované / riziko — připojené k projektu+plánu

| Projekt / plán | Blokace / riziko | Důkaz |
|---|---|---|
| **vulcan / B-140** | 🔴 P0 cross-tenant RLS leak v `clavi.episodes` (mimo EPIC strukturu) | `docs/plans/BACKLOG.md` B-140, nalezeno při P054 curator review |
| sousto / P009 | 🟠 frontier stojí 3 týdny (E-009-1_2 EXECUTE 0/8 od 31.5.) — `stale` flag | `work/evidence/E-009-1_2/R-E009-1/fsm-state.yaml` + timeline bez pohybu |

Žádná tvrdá ESCALATION na žádném aktivním EPICu napříč projekty.

### Na čem se právě pracuje (JEDEN výřez pod portfoliem — genuine frontiers)

| Projekt / plán | Frontier EPIC | Stav | Další krok |
|---|---|---|---|
| wan / P045 | E-045-3_3 | EXECUTE (reaktivováno override 22.6. 04:25) | dokončit kroky 11-17, fix 8 nálezů |
| sousto / P009 | E-009-1_2 | EXECUTE 0/8 — stojí 3 týdny | odblokovat + krok 1/8 |
| krok / P014 | E-014-7_7 | READY (Docusaurus, nezačato) | spustit; E-014-1..6 už v gitu |
| acta / P007 | E-007-4_4 | READY — nikdy neběžel (Phase 4) | `/aid-run E-007-4_4` |
| aid-orchestrator / P047 | E-047-7_7 | READY (Phase 7) | tato productization (reopen) |

### Kde nemáme spolehlivá data (Kvalita dat — SBALENO, jeden souhrn)

- **~16 plánů `stav nelze ověřit`** — wan 14 legacy MVP1 (duben/květen, mimo moderní FSM), vulcan 4 stuby, krok 3 (brainstorm/queued/approved bez runů), aid-orch 2.
- **~12 wan plánů `dokončeno, neuzavřeno`** — EPICy released, task nearchivován = closure debt.
- **fsm-state ≠ git** u krok P014, vulcan P044/P045/P049, wan legacy → read-model nesmí věřit jen FSM.
- **Cockpit API `progressPct` klame** (vidí jen moderní fsm evidence) — u vulcan ukazuje 0-19 % na plánech, které git dokládá jako zavřené.
- Úklidový dluh: orphan/stale aktivní tasky (aid-orch E-019/020/021/041; acta P002 ERROR+dup; wan tasks nearchivovány).

---

## Per-project detail (drill-down — plán → fáze/EPICy → signály)

Plné per-plán tabulky (co dodává, stav, důkaz, aktivní EPICy, poslední aktivita, audit,
backlog, evidence completeness) jsou v agentních výstupech; shrnutí výše. Klíčové body:

- **sousto P009**: 6 potvrzených bezpečnostních slabin live webu, 2 ověřitelná nasazení; EPIC 1/2 běží (stojí), EPIC 2/2 čeká na dependency. Audit: bez. Navíc nenaplánovaný milník „P004 deploy + migrace před go-live".
- **acta P007**: extrakce vždy proběhne + párování dle IČO + ZIP příjem; EPIC 1-3 done+merged, **EPIC 4 task existuje, nikdy neběžel**. Audit E-007-3_4 89/100 pass.
- **wan P045**: 3-krokový průvodce Nová smlouva, N smluv v 1 atomické transakci; EPIC 1+2 merged, **EPIC 3 reaktivováno override** (fix 8 nálezů před merge). Audit 91/100.
- **vulcan**: 35/37 aktivních plánů done (git+fsm+ledger), ale **B-140 P0 RLS leak** otevřený v backlogu — to je skutečné aktuální riziko, ne plán.
- **krok P014**: 6 promptů LangGraph + nápověda + Docusaurus; E-014-1..6 v gitu (FSM stale), E-014-7_7 jediný reálně otevřený. CP1-deep pass.
- **aid-orch P047**: tento Cockpit; E-047-1..6 done+merged, E-047-7_7 reopen (Docker/compose, docs, E2E).

---

## Read-model implications (po schválení obsahu — pak kód)

1. **Entity = plán** (projekt → plán → stav → EPICy drill-down). Portfolio 6 projektů × jejich otevřené plány je primární view.
2. **Multi-source evidence reconciler**: fsm-state + git (merge/close commits) + plan frontmatter `status:` + `active.md`/`SESSION-CONTEXT` ledger + task-archive location. Konflikt/absence → `stav nelze ověřit`. NE věřit jen fsm-state ani API progressPct.
3. **Stavová sada** výše vč. `dokončeno, neuzavřeno` (closure debt) — odlišit od aktivní práce.
4. **Rozhodnutí/blokace/riziko vždy připojené ke konkrétnímu projektu+plánu** (+ konkrétní otázka a možnosti u rozhodnutí).
5. **Kvalita dat** = jeden sbalený souhrn (počty nelze-ověřit / closure-debt / fsm≠git), ne hlavní brief.
6. **EPICy/FSM/signály = drill-down**, ne základ navigace. Signály se počítají až uvnitř aktivní entity.
7. LLM smí později generovat lidská shrnutí plánů/auditů/backlogů, ale **stav plánu a jeho dokončení zůstává evidence-based** (deterministický reconciler, ne LLM).

---

## Appendix — v1 EPIC-frontier audit (approved as frontier audit, not as Screen G)

(Original v1 content — the three execution frontiers krok/sousto/wan — is retained as the
"Na čem se právě pracuje" slice above; v2 promotes PLAN as the primary unit per Marek's
correction. The v1 "3 quiet projects" claim is RETRACTED: acta P007 + aid-orch P047 are open,
vulcan carries the open P0 B-140.)
