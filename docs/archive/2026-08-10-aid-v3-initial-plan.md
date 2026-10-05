# AID v3 — Průběžný pracovní dokument

**Stav:** Active — Session A+B deployed | **Aktualizováno:** 2026-05-08
**Účel:** Živý dokument zachycující motivaci, chybějící funkce a architektonická rozhodnutí pro AID v3 redesign.
**Není:** Finální spec. Je: PM zápisník pro iterativní upřesňování.

---

## Implementation Log

| Datum | Session | Plán | Verze | Body z §0 / §2 | Stav |
|---|---|---|---|---|---|
| 2026-05-04 | Krok 0 — diagnostic | `AID-v3-diagnostic-findings.md` | — | §0 Krok 0 | ✅ DONE |
| 2026-05-04 | Krok 1 — sub-agent isolation | `AID-v3-subagent-isolation-test.md` | — | §2 bod **f** | ✅ DONE — sub-agenti izolovaní, lze používat |
| 2026-05-06 | Session A — Foundation Hardening | P032 (archived) | v2.16.0 / v2.16.1 | §0 Krok 2 (AID-002), Krok 3 (AID-012), §2 bod **c** část compliance | ✅ DEPLOYED + measured |
| 2026-05-06 | v2.17.0 polish | (CHANGELOG) | v2.17.0 | CP1 codebase grounding (Completeness Gate #17), `--reflect` flag | ✅ DEPLOYED |
| 2026-05-08 | Session B — CP2/CP3 enforcement | P033 | v2.18.0 (tag) | §2 bod **a** část epic-summary, AID-003/004 | 🟡 TAG PUSHED — main neproveden, GH Release zatím chybí, měření neproběhlo |

---

## 0. Kde začít — před implementací analýza, pak tři kroky

> Cíl není reimplementovat celý AID. Cíl je aby agenti dělali co mají. Všechno ostatní je sekundární.

---

### Krok 0 — Diagnostická analýza (před čímkoli jiným, ~3h) — ✅ DONE 2026-05-04

> Výstup: `docs/plans/AID-v3-diagnostic-findings.md` (baseline) + `AID-v3-diagnostic-findings-post-A.md` (post-Session-A round 0.b). Identifikováno 4 systematických gaps → vstup pro Session A scope.

**Než se cokoliv implementuje:** Projít existující výstupy agentů a porovnat je s aktuálním kódem AID. Cíl: zjistit které konkrétní FSM kroky jsou pravidelně ignorovány, proč, a navrhnout cílené řešení — ne obecné.

**Co analyzovat:**
- Existující `timeline.jsonl` soubory z proběhlých EPICů — které FSM transitions reálně proběhly vs. které měly proběhnout
- `step-N-verify.md` soubory — jsou AC checklisty vyplněné smysluplně nebo šablonovitě? Koreluje čas vzniku s reálnou prací?
- `gates_report.json` soubory — jsou generované `aid-run-gates.sh` nebo ručně zapsané?
- `final_report.md` a `audit-report.yaml` — jaké finding kategorie se opakují přes více EPICů?
- Git log — odpovídají commit hashe v verify souborech reálným commitům?
- `self_audit.json` pokud existuje — co agent sám přiznal

**Co hledat — vzory:**
| Vzor | Pravděpodobná příčina | Pravděpodobné řešení |
|---|---|---|
| CP2 verifier nikdy nevolán | Chybí v dispatch instrukci nebo je vnímán jako volitelný | Enforcement v pipeline.md, ne jen popis |
| gates_report.json stejný obsah přes EPICy | Ručně zapsaný, nikdy nespuštěn | execution.yaml + wiring aid-run-gates.sh |
| verify soubor vznikl < 30s po dispatch | Šablonovité vyplnění bez práce | Timestamp analýza + CP2 jako gate pro verify |
| Context Components 3/10 místo 10/10 | Agent dostává ad-hoc prompt | Rewrite context assembly v pipeline.md §4 |
| Audit findings stejná kategorie 3+ EPICy | Systematická mezera, ne náhoda | Cílený fix pro tu konkrétní kategorii |
| step.outputs neodpovídají diffu | Agent změnil scope bez deklarace | Adversarial commit message + scope check |

**Výstup analýzy:** Krátký dokument (1-2 strany) se seznamem konkrétně ignorovaných FSM kroků, frekvencí a navrženými řešeními. Tento dokument pak nahradí obecné priority níže — budou cílené na reálné failure módy tohoto konkrétního AID setupu, ne na teoretické.

**Kdo to dělá:** Orchestrátor dostane jako vstup existující výstupy EPICů + aktuální AID kód. Úkol: "Porovnej co AID říká že se má dít vs. co se reálně stalo. Identifikuj vzory. Navrhni konkrétní opravy." Výstup cross-validovat s PM.

---

### Krok 1 — Verifikace sub-agentů (2h, empirický test) — ✅ DONE 2026-05-04

> Výstup: `docs/plans/AID-v3-subagent-isolation-test.md` (T1–T12). Sub-agenti mají izolovaný kontext window i token budget, hlavní okno není kontaminované. Lze používat pro multi-EPIC workflow. → bod f) RESOLVED.

Zjistit jestli sub-agenti mají vlastní izolovaný kontext a nežerou hlavní okno. Binární výsledek — buď je to použitelný nástroj nebo ne. Bez tohoto nelze dělat žádná architektonická rozhodnutí o multi-EPIC workflow. → viz bod f)

---

### Krok 2 — Opravit Context Assembly (AID-002, ~4h) — ✅ DONE Session A v2.16.0

> Implementováno v P032 (archived). Pipeline §4 přepsaná, dispatch handoff strukturovaný (10/10 Context Components místo ad-hoc).

Největší příčina ignorování kroků: agent při dispatchi nedostane kompletní instrukce a vymyslí si zkratku. Jedna změna v pipeline.md §4. Nejvyšší ROI ze všech změn v tomto dokumentu — přímá příčina většiny failure módů identifikovaných v Kroku 0. → viz bod a) + f)

---

### Krok 3 — Self-audit FSM checklist (AID-012, ~6h) — ✅ DONE Session A v2.16.0

> `compliance.json` per EPIC + `aid-compliance-report.sh` aggregator. Round 0.b post-Session-A měření odhalilo force_override 40% bypass → Session B mitigation.

Na konci každého EPICu agent dostane FSM seznam a přizná co nedělal a proč. Okamžitý feedback loop pro iteraci — vidíš vzor, opravíš konkrétní místo. Krok 0 ukázal kde jsou díry, Krok 3 zajistí že je uvidíš i v budoucnu automaticky. → viz bod c)

---

**Po Krocích 1-3:** Počkej 2-3 EPICy. Vyhodnoť jestli se chování změnilo. Pak teprve přidávej další vrstvy z tohoto dokumentu.

---

## 1. Hlavní problém — proč AID v3

Agent v průběhu EXECUTE fáze systematicky přeskakuje nebo obchází kroky definované v AID procesu — Context Assembly komponenty, CP2/CP3 verifiery, gate skripty. Výsledkem je, že AID pipeline formálně "proběhne", ale reálně nebyla dodržena. Toto je největší aktuální slabina systému.

**Charakter problému:** Není to jednorázový bug. Je to kontinuální arms race mezi disciplínou procesu a optimalizačním tlakem agenta na "task done". Nelze to vyřešit jednou provždy — lze to kontinuálně mitigovat. AID v3 přistupuje k problému z opačné strany než v2: místo "řekneme agentovi co musí dělat" → "agent musí explicitně reportovat co nedělal, a my ho chytíme".

**Dvě kořenové příčiny (potvrzeno self-auditem):**
1. Agent při dispatchi nedostane kompletní kontext → vymyslí si zkratku (→ fix: AID-002)
2. Neexistuje mechanismus kde agent přizná odchylky → odchylky jsou neviditelné (→ fix: AID-012)

---

## 2. Chybějící nebo nedostatečné funkce

Seřazeno podle průběhu flow (od plánování po uzavření EPICu).

---

### b) Definition of Done per task — chybí v plánování

**Kde v flow:** Fáze 2 — Plan Writing
**Problém:** Acceptance Criteria existují, ale nejsou strukturované jako závazný a verifikovatelný checklist. Agent je může "splnit" textově bez reálné verifikace. DoD chybí jako explicitní, povinná kategorie per task.
**Co chceme:** Při tvorbě plánu vznikne pro každý task strukturovaný DoD s povinnými kategoriemi: co musí fungovat (ideálně jako spustitelný test), jaké soubory musí existovat, co nesmí být v diffu (out_of_scope), a prostor pro odůvodnění odchylky pokud nastane.
**Status:** 🟡 ČÁSTEČNĚ — Session A přidala AC checklists do plan-writing.md (Completeness Gate). Strukturované DoD kategorie (`out_of_scope`, `files_must_exist`, `runnable_test`) jako závazné YAML pole zatím **nejsou** — agent je generuje volně textem. Pro Session D nebo samostatnou iteraci.

---

### a) Automatický handoff po dokončení EPICu — chybí

**Kde v flow:** EXECUTE → Orchestrátor (hlavní okno)  
**Problém:** Po dokončení práce v sub-okně (Agent tool dispatch nebo manuální sub-okno) nemá orchestrátor strukturovaný přehled o tom, co proběhlo. Handoff dnes chybí nebo je neformální — orchestrátor dostane jen návratovou zprávu nebo nic.  
**Co chceme:** Po každém EPICu automaticky vznikne `handoff.json` (nebo ekvivalentní strukturovaný blok) obsahující:
- co bylo hotovo vs. plánováno
- které AC prošly / neprošly
- které FSM kroky byly přeskočeny a proč
- změněné soubory a commit hash
- bloky pro další EPIC
- doporučená návazná akce (continue / escalate / revise plan)

Tento handoff je vstupem pro orchestrátora v dalším turnu — ne jen archiv.
**Status:** 🟡 ČÁSTEČNĚ — Session B (IMP-090) přidala `epic-summary.md` s 5 sekcemi (✅ shipped / ⚠️ warnings / ❌ deferred / 📋 PM next actions / 🔍 honest signal). Pokrývá human-readable handoff. Strukturovaný `handoff.json` pro orchestrátor strojový read zatím chybí — pravděpodobně přijde v Session C (memory) jako vstup pro Plan Lessons.

---

### f) ⚠️ KRITICKÉ — Verifikace izolace sub-agentů + kvalita handoffu oběma směry

**Kde v flow:** Prerekvizita pro jakékoli využití sub-agentů  
**Proč kritické:** Bez verifikace že sub-agenti fungují korektně musí být sub-agenti z AID eliminováni úplně. To by zásadně omezilo paralelizaci a workflow.

**Co musí platit aby sub-agenti mohli být použiti:**

1. **Izolovaný kontext** — sub-agent má vlastní context window, nesdílí ho s hlavním oknem. Chovají se jako by PM spustil druhé okno manuálně.
2. **Nulová kontaminace hlavního okna** — tool calls a výstupy sub-agenta nejsou viditelné v kontextu orchestrátora (pouze finální text result).
3. **Kompletní instrukce při dispatchi** — sub-agent dostane při spuštění vše co potřebuje: playbook, EPIC kontext, task specifikaci, handoff info z předchozího EPICu, permissions, standards. Žádné "zbytkové vědomosti" z hlavního okna.
4. **Handoff oběma směry:**
   - **Orchestrátor → Sub-agent:** strukturovaný dispatch handoff (co dělat, co je kontext, co je DoD, co nesmí dělat)
   - **Sub-agent → Orchestrátor:** strukturovaný výstupní handoff (co bylo uděláno, odchylky, bloky, doporučení)

**Co verifikovat empiricky před implementací:**
- Jsou tool calls sub-agenta viditelné v hlavním kontextu? (dle CC docs: ne — jen text result)
- Tokeny sub-agenta se počítají do hlavního okna? (nutno empiricky ověřit)
- Context pollution test: sub-agent dostane "secret phrase", ověřit že hlavní okno ji nevidí

**Výstup verifikace:** Zapsat jako behavioral contract do `plugin.yaml`. Pokud verifikace selže → sub-agenti se nepoužívají dokud není vyřešeno.
**Status:** ✅ DONE 2026-05-04 — `docs/plans/AID-v3-subagent-isolation-test.md` (T1–T12). Sub-agenti mají izolovaný kontext window i token budget; kontaminace hlavního okna nulová; tool calls neviditelné v parent kontextu (jen text result). Lze používat. Behavioral contract zatím není v `plugin.yaml` formálně zapsán — postačuje doc reference.

---

### c) Self-learning per PLAN ID + aktivní FSM compliance check

**Kde v flow:** Průběžně v EXECUTE + na konci každého EPICu  
**Problém:** Chybí persistentní paměť na úrovni plánu. Každý EPIC začíná bez vědomí co se dělo v předchozích. Lessons learned se neukládají systematicky. Navíc: neexistuje mechanismus kdy agent explicitně potvrdí nebo odmítne co ze svého FSM checklistu splnil.

**Co chceme — dvě složky:**

**Složka 1 — Plan Lessons (Qdrant, per PLAN ID):**  
Implementer, Curator a Auditor průběžně zapisují strukturované záznamy pod konkrétním PLAN ID:
- co fungovalo / nefungovalo
- security patterny k opakování / vyvarování
- architektonická rozhodnutí která vznikla implicitně
Tyto záznamy jsou injectovány do kontextu každého dalšího dispatch v rámci stejného plánu.

**Složka 2 — FSM Compliance Self-Audit (per EPIC):**  
Na konci každého EPICu (před přechodem do GATES) agent dostane kompletní FSM checklist a krok po kroku odpoví: udělal / neudělal / proč ne / co by zlepšil. Výstup je strukturovaný (`self_audit.json`), ne volný text.

> ⚠️ Toto není jen self-learning — viz bod d) níže. Self-audit je vstup pro aktivní orchestraci, ne jen archiv.

**Status:** 🟡 ČÁSTEČNĚ — **Složka 2 (FSM Compliance Self-Audit)** ✅ DONE Session A v2.16.0 (`compliance.json` per EPIC + 17 dimenzí, post-Session-B nová object-schema verifier_outputs). **Složka 1 (Plan Lessons v Qdrant)** ❌ OTEVŘENÁ — to je primary scope **Session C**. Existující draft: `.aid-o/plans/P031-agent-memory-qdrant.md`.

---

### d) Orchestrátor aktivně řídí na základě handoffů — ne jen plácá do backlogu

**Kde v flow:** Po každém EPICu (DONE → orchestrátor → další EPIC)  
**Problém:** I kdyby self-audit a handoff existovaly, orchestrátor v hlavním okně by je musel aktivně číst a reagovat. Aktuálně orchestrátor nemá mechanismus pro:
- detekci odchylky od plánu
- okamžitou opravu (re-task, revize scope) před dalším EPICem
- rozlišení "dát do backlogu" vs. "opravit teď"

**Co chceme:**  
Orchestrátor po každém EPICu povinně přečte handoff (a), self-audit výstup (c), Curator a Auditor nálezy (e) a provede vyhodnocení:

- **Odchylka od plánu?** → rozhodne: opravit okamžitě (extra EPIC nebo re-run) / přijmout jako deviation s dokumentací / eskalovat na PM
- **Bloky pro další EPIC?** → upraví dispatch handoff pro následující sub-okno
- **Pattern odchylky přes více EPICů?** → navrhne PM úpravu zbývajícího plánu

**Klíčový princip:** Orchestrátor není pasivní koordinátor. Je to aktivní kontrolní bod. Backlog slouží pro věci které počkají — ale odchylky od plánu musí být řešeny aktivně, ne odkládány.

**Implementačně:** `/aid-reflect` command — volaný automaticky po každém `done-advance`, výstup jde do PM Summary.
**Status:** 🟡 ČÁSTEČNĚ — `aid-compliance-report.sh --reflect` (v2.17.0) existuje jako manuální PM nástroj s pattern detection (✅ / ⚠️ INVESTIGATE / 🔴 SYSTEMATIC). Auto-trigger po každém EPICu = **IMP-085** (proposed, ~2h). Active orchestrátor reaction loop (re-task / revize scope / eskalace) zatím není — to je samostatná iterace.

---

### e) Curator a Auditor na silnějším modelu než implementer

**Kde v flow:** DONE review fáze  
**Problém:** Curator a Auditor plní adversarial roli (judge, reviewer) ale aktuálně běží na stejném nebo slabším modelu než implementer (defendant). Judge slabší než defendant = systematické blind spoty v review.

**Navrhované přerozdělení modelů:**

| Role | Aktuální | Navrhovaný | Důvod |
|---|---|---|---|
| architect | opus | opus | Strategická rozhodnutí |
| backend | opus | sonnet | Implementace — Sonnet 4.6 je silný na kód |
| frontend | opus | sonnet | Stejný argument |
| security verifier | sonnet | opus | Adversarial role — hledá chyby |
| auditor | sonnet | opus | Judge musí být silnější než defendant |
| curator | sonnet | opus | Strategická rozhodnutí o fixech |
| verifier CP3/CP4 | sonnet | opus | Integration + curator review — méně časté, kritické |
| verifier CP2 | sonnet | sonnet | Per-step, časté dispatche — Sonnet stačí |
| qa | sonnet | sonnet | Psaní testů |
| gate-fixer | haiku | haiku | Mechanická aplikace |
| docs-writer | sonnet | sonnet | Kvalita > rychlost |

**Poznámka:** Cost dopad pravděpodobně neutrální až mírně nižší — implementer (90% dispatchů) jde dolů, adversarial role (10% dispatchů) jde nahoru.
**Status:** ❌ OTEVŘENÉ — AID-014, neimplementováno. Bod **f** (sub-agent isolation) je vyřešen, takže prerekvizita splněna. Kandidát pro **Session D**.

---

### g) Security scan skill na konci celého Plánu

**Kde v flow:** PLAN BOUNDARY CHECKPOINT  
**Problém:** Per-EPIC security review existuje (CP3 security verifier + Auditor sekce F). Ale cross-EPIC bezpečnostní problémy nejsou pokryty — například auth helper zavedený v EPICu 1 a nesprávně použitý v EPICu 3.

**Co chceme:** Dedikovaný skill `skills/security-plan-review.md` volaný po posledním EPICu plánu. Scope: kompletní diff od začátku plánu. Focus: auth/authz flow across EPICů, injection patterny (exec/eval/SQL/template), secrets exposure, cross-EPIC API contract breaks, regrese security fixů z předchozích plánů.

Výstup: `security_plan_report.md`. Blocking findings blokují merge plánu.
**Status:** ❌ OTEVŘENÉ — kandidát pro **Session E** (společně s bodem h, code quality skill).

---

### h) Code quality / simplify skill po každém EPICu

**Kde v flow:** DONE review (paralelně s Curator + Auditor)  
**Problém:** Není mechanismus pro průběžnou kontrolu kvality kódu a technického dluhu na úrovni EPICu.

**Co chceme:** Skill který po každém EPICu projde diff od posledního merge commitu a zkontroluje:
- dead code a unused imports
- duplicitní logiku
- over-engineered řešení (zbytečná komplexita)
- naming konzistence
- tech debt flagging

Výstup: doporučení v PM Summary. **Není blokující** — PM rozhodne co adresovat okamžitě a co odložit.
**Trigger:** Planner určuje zda se skill spustí (ne každý EPIC musí být code-heavy).
**Status:** ❌ OTEVŘENÉ — kandidát pro **Session E** (společně s bodem g, security plan review).

---

## 3. Architektonická rozhodnutí (platná od v3)

### 3.1 Zrušení full-auto režimu — přechod na SEMI-AUTO

**Rozhodnutí (PM):** Full-auto režim je pozastaven. Nová maximální granularita automatického běhu je **1 EPIC**. Po každém EPICu bez výjimky proběhnou:
- všechny kontroly (Curator, Auditor, self-audit, gates)
- PM review výstupu

Auto-merge bez PM review **není povoleno** v žádném případě.

**Důvod:** Bez aktivní PM kontroly po každém EPICu se odchylky kumulují a orchestrátor nemá možnost korigovat kurz.

---

### 3.2 Manuální režim — architektura oken

**Schéma:**

```
[Hlavní okno — Orchestrátor]
  Model: Opus (aktuálně)
  Role: plánování, koordinace, cross-EPIC kontrola, /aid-reflect
  Zodpovídá za: aktivní vyhodnocení handoffů, korekce plánu
        │
        │  automaticky generovaný dispatch handoff (text blok)
        │  PM copy-paste mezi chaty
        ▼
[Sub-okno — EPIC execution]
  Model: dle role (viz tabulka v bodě e)
  Scope: 1 EPIC, izolovaný kontext
  Dostane: kompletní dispatch handoff (instrukce + kontext + DoD + permissions)
  Vrátí: strukturovaný výstupní handoff (výsledky + odchylky + bloky)
        │
        │  automaticky generovaný výstupní handoff (text blok)
        │  PM copy-paste zpět do hlavního okna
        ▼
[Hlavní okno — Orchestrátor]
  Přečte výstupní handoff
  Spustí /aid-reflect
  Rozhodne: pokračovat / opravit / eskalovat
  Připraví dispatch handoff pro další EPIC
```

**Handoff formát:** Automaticky generovaný textový blok (ne JSON soubor pro PM). PM ho zkopíruje mezi chaty. Obsah je strukturovaný ale čitelný — PM vidí co předává.

**PM role v tomto modelu:** PM je vědomý přenašeč kontextu mezi okny. Není pasivní — čte handoff summary a může ho upravit nebo zastavit před předáním.

---

## 4. Otevřené otázky (REQUIRES PM DECISION)

| # | Otázka | Blokuje | Stav |
|---|---|---|---|
| Q1 | Verifikace sub-agent izolace — výsledek empirického testu? | Bod f, celý sub-agent model | ✅ ZODPOVĚZENO 2026-05-04 — izolovaný kontext, lze používat |
| Q2 | Verifier deprivation: total (jen diff + DoD) nebo nuanced (+ scope context)? | CP2/CP3 redesign | ✅ ZODPOVĚZENO Session B — **nuanced** (diff + DoD + step.outputs + step.forbidden_paths) |
| Q3 | Self-audit: spustit bez deterministic ground truth (calibrated: false) nebo čekat na bash compliance auditor? | Pořadí implementace | ✅ ZODPOVĚZENO Session A — bash auditor existuje (`evaluate_compliance_checks` + `aid-compliance-report.sh`) |
| Q4 | Model redistribuce: plošně najednou nebo postupně role po roli? | Cost, stabilita | ❌ OTEVŘENÉ — Session D |
| Q5 | Orphan sessions (MVP session prompts): zrušit nebo importovat přes aid-orphan-import.sh? | Čistota architektury | ❌ OTEVŘENÉ — drobnější housekeeping |
| Q6 | Telegram alert pro budget/escalation: na který chat? Ping interval? | AID-022, AID-023 | ✅ ZODPOVĚZENO Session A — `svc-mcp-tg-bot` MCP server na 8817, alert flow `try_telegram_alert` |
| Q7 | Code quality skill (bod h): běží po každém EPICu nebo jen na L/XL EPICy? | Scope implementace | ❌ OTEVŘENÉ — Session E |

---

## 5. Co zůstává z AID v2 beze změny

- FSM 6-state machine (PRE-FLIGHT → READY → EXECUTE → GATES → DONE → ESCALATION)
- Brainstorm + Plan Writing fáze (zachovány, DoD se přidá do plan-writing)
- PLAN BOUNDARY CHECKPOINT (zachován, rozšíří se o security skill a code quality)
- Curator + Auditor paralelní dispatch (zachován, mění se model)
- Forbidden Phrase Gate + Completeness Gate v plan-writing (zachovány)
- Scanner Memory Scan (zachován)
- Evidence-based FSM transitions (zachovány — základ celého systému)

---

*Dokument je živý. Každé PM rozhodnutí z oddílu 4 sem přijde jako záznam s datem.*