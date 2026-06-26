# AID Evidence Lifecycle & Current-State Foundation

## Účel dokumentu

Tento dokument je předání kontextu pro sepsání a následnou realizaci nového
prerequisite plánu pro AID Cockpit. Řeší chybějící architektonickou vrstvu mezi
historickou evidencí AID a manažerským Cockpitem.

Dokument není implementační plán ani souhlas s pokračováním E-047-6_7. Nový
detailní plán musí teprve vzniknout, projít kontrolou a stát se blocking dependency
pro pokračování E-047-6_7.

**Rozhodnutí:**

- E-047-6_7 je pozastavený, nikoliv zrušený.
- E-047-7_7 zůstává pozastavený.
- Commit `3b40e88` a rozpracovaný Screen G zůstávají nemergnuté a nesmějí se
  zahodit ani dále propagovat do ostatních obrazovek.
- Před další produktizací Cockpitu musí vzniknout deterministic current-state
  foundation.
- LLM není součástí tohoto scope.

## Související dokumenty

- `docs/AID-Cockpit-spec.md` - původní Cockpit specifikace.
- `.aid-o/plans/P047-aid-cockpit-mvp1.md` - implementační plán Cockpitu.
- `docs/design/E-047-6-productization-addendum.md` - REOPEN addendum pro
  produktizaci E-047-6_7.
- `docs/design/E-047-6-expected-screen-G.md` - ručně sestavený plan-first oracle
  nad reálnými daty všech šesti projektů.

## Proč současný plán nestačí

P047 předpokládá, že Cockpit dokáže aktuální provozní stav odvodit z existujících
`.aid-o` stop. Scanner považuje projekt za aktivní už při existenci aktivního tasku
nebo evidence directory a vybírá latest run převážně z časových údajů. Reálná data
ukázala, že tento předpoklad neplatí.

Evidence dobře odpovídá na otázku **co se někdy stalo**, ale ne vždy na otázku
**co právě platí**. Cockpit proto zaměnil historický inventář za aktuální práci:

- desítky historických READY runů označil jako připravenou práci,
- archivované EPICy zobrazil jako active runs,
- staré failure artefakty zobrazil jako aktuální blokace,
- closure debt zaměnil za aktivní vývoj,
- plánům odvozoval nesprávný progress,
- stejné technické signály seskupil přes nesouvisející historické plány,
- nedokázal spolehlivě určit aktuální projekt, plán ani execution frontier.

REOPEN addendum zlepšuje `BriefItem`, lifecycle problémů, texty a UI hierarchii,
ale stále pouze interpretuje existující evidenci. Neobsahuje:

- systematický evidence audit a reconciliation,
- autoritativní current-state kontrakt,
- sidecar current-state index/manifest,
- backfill současného stavu všech projektů,
- změny AID producenta evidence,
- trvalé lifecycle události a closure vazby,
- rollout a provozní enforcement.

## Ověřené nálezy z reálných dat

Ručně sestavený oracle nad všemi šesti projekty doložil následující:

1. **FSM samotné není autoritativní.** U některých plánů git dokládá merge, zatímco
   `fsm-state.yaml` stále ukazuje READY, review nebo pending.
2. **Mtime není lifecycle.** Dotknutí historického run directory nesmí znovu
   aktivovat dokončenou práci.
3. **Neaktivní task není automaticky archivovaný.** Archivace vyžaduje explicitní
   důkaz; absence z active task setu není důkaz historie.
4. **Dokončené EPICy bez uzavření tasku jsou closure debt.** Nejde o aktivní
   frontier ani o spolehlivě uzavřený plán.
5. **Poslední EPIC neurčuje stav projektu.** Projekt může mít více otevřených plánů,
   připravený plán, pozastavenou práci nebo projektový blocker mimo plán.
6. **Plan completion nelze odvodit pouze z merge commitu.** Merge jednoho EPICu
   nedokazuje dokončení celého plánu.
7. **Některé plány jsou dlouhodobě rozpracované oprávněně.** Stáří samo neurčuje
   stav; `stale` smí být pouze qualifier tam, kde se očekával pohyb.
8. **Chybějící evidence není fail ani dokončení.** Takový plán musí zůstat viditelný
   jako `unknown` / `stav nelze ověřit`.
9. **Projektové problémy mohou být mimo plánovou strukturu.** Příkladem je vulcan
   `B-140`, P0 cross-tenant RLS leak nalezený v backlogu.
10. **Backlog, audit, Reporter a Simplifier jsou manažerské vstupy.** Nesmějí být
    redukovány na technický drill-down bez vazby na projekt/plán.

## Produktová potřeba

Primární mentální model uživatele je:

`projekt -> jeho plány -> co plán dodává -> stav plánu -> až potom fáze a EPICy`

Cockpit musí pro každý projekt a plán rychle odpovědět:

- Co projekt a plán dodává?
- Které plány jsou otevřené a v jakém jsou stavu?
- Na kterém plánu se právě pracuje?
- Je plán aktivní, připravený, blokovaný, pozastavený nebo neověřitelný?
- Jaká je aktuální fáze, poslední významná aktivita a další krok?
- Co čeká na rozhodnutí uživatele?
- Co skutečně blokuje dodávku?
- Jak dopadl poslední audit a jaký je trend?
- Jaké jsou hlavní auditní nálezy a doporučené opravy?
- Co přibylo nebo se změnilo v backlogu?
- Existuje plan-bound Reporter/Simplifier výstup a co říká?
- Jak úplná a důvěryhodná jsou data?

EPIC, FSM, CP1-CP6, raw eventy a evidence jsou drill-down. Nejsou primární jednotkou
portfolia.

## Cílová architektura

### 1. Historická evidence

Existující `.aid-o` evidence zůstává auditním a analytickým zdrojem. Foundation ji
nesmí destruktivně přepisovat, mazat ani vydávat odhad za původní skutečnost.

Historická evidence nadále slouží pro:

- audit a provenance,
- timeline a technický detail,
- retry/failure analytics,
- plan outcome analytics,
- lessons learned,
- zpětné dohledání rozhodnutí.

### 2. Reconciliation vrstva

Sdílený deterministic reconciler sestaví z dostupných zdrojů kanonický pohled.
Musí být použitelný jako:

- read-only audit/dry-run nástroj,
- backfill generátor current-state sidecaru,
- validační oracle pro producenta,
- fallback pro legacy projekty, nikdy však jako skrytá UI heuristika.

Reconciler musí pracovat se strukturovanými facts a explicitními konflikty. Nesmí
mít jedno globální pravidlo typu "git vždy vítězí" nebo "latest mtime vždy vítězí".
Precedence je signal-specific.

### 3. Autoritativní current-state

AID musí udržovat strojově čitelný, verzovaný current-state artifact pro každý
projekt. Přesnou cestu a formát vybere nový plán, ale ownership je závazný:

- zapisuje jej AID orchestrator / lifecycle producer,
- Cockpit jej pouze čte,
- reconciliation/backfill jej smí vytvořit nebo opravit pouze s provenance,
- chybějící nebo konfliktní stav je `unknown`, nikdy odhadovaný positive state.

### 4. Producent lifecycle událostí

Po rollout musí být current-state aktualizován při každé relevantní změně. Jinak
jednorázový úklid během několika týdnů znovu degraduje.

## Kanonické entity a stavy

Nový plán musí definovat machine enums oddělené od českých display labels.
Minimální domény:

### Project lifecycle

- `active`
- `paused`
- `idle`
- `blocked`
- `archived`
- `unknown`

Projekt může mít nula až více otevřených plánů a nula až více project-level
concerns mimo plán.

### Plan lifecycle

- `planned`
- `ready`
- `active`
- `waiting_decision`
- `blocked`
- `paused`
- `completed_unclosed`
- `completed`
- `abandoned`
- `historical`
- `unknown`

`stale` není plan lifecycle. Je to qualifier aktivního plánu, u kterého se
očekával pohyb a nebyl zaznamenán.

### EPIC/run lifecycle

Musí rozlišovat alespoň queued/ready/active/gates/waiting-decision/blocked/
completed/abandoned/superseded/archived/unknown. Přesné mapování na FSM a legacy
formáty musí být součástí plánu.

### Problem lifecycle

- `active`
- `resolved`
- `historical`
- `unknown`

`stale` je opět qualifier. Každý problém musí podporovat `resolvedBy`,
`supersededBy`, evidence references a konkrétní root-cause identity.

### Evidence quality

- `complete`
- `partial`
- `conflicting`
- `missing`

Confidence nesmí nahradit stav. Vyjadřuje pouze jistotu reconciliation výsledku.

## Koncept current-state artifactu

Nový plán musí navrhnout a verzovat minimálně následující obsah. Toto je koncept,
nikoliv předem zamčený TypeScript/YAML kontrakt:

```text
schemaVersion
generatedAt
producerVersion
project
  id, displayName, lifecycle, qualifiers, confidence
  lastMeaningfulActivity, nextExpectedAction
plans[]
  id, title, objective/deliverable
  lifecycle, qualifiers, confidence, evidenceQuality
  phase/progress, frontierEpics[], nextExpectedAction
  decisions[], blockers[], risks[]
  auditSummary, backlogSummary, deliverySummary, lessonsSummary
  lastMeaningfulActivity, evidenceRefs[]
projectConcerns[]
queue[]
aliases[]
dataQualityIssues[]
provenance[]
```

Počty, statusy a summary musí být reprodukovatelné z provenance. Pole bez důkazu
zůstává `null`/`unknown`.

## Source inventory a precedence

Audit musí inventarizovat minimálně:

- plan files a jejich frontmatter/Goal/Stakeholder Brief,
- aktivní i archivované task files,
- `fsm-state.yaml` a legacy state files,
- per-run timelines,
- queue a active/session ledgers,
- git commits/merge history,
- compliance, gates a checkpoint outputs,
- audit-reporty,
- Reporter/Simplifier outputs,
- project a plan backlog,
- lessons learned,
- project-level issues mimo plán.

Závazná pravidla:

1. Žádný jednotlivý zdroj není univerzálně autoritativní pro všechny otázky.
2. Mtime je freshness signal, nikoliv lifecycle důkaz.
3. Git merge dokládá změnu v gitu, ne automaticky dokončení plánu.
4. Archivovaný task je silný důkaz, že EPIC není current frontier; neříká sám o
   sobě, že celý plán byl úspěšně dokončen.
5. Absence aktivního tasku není důkaz archivace.
6. Plan frontmatter `status` je validní jen podle definované schema verze a musí se
   porovnat s execution evidence.
7. Explicitní uživatelský override musí mít autora, důvod, timestamp a provenance.
8. Konflikt zdrojů končí `unknown/conflicting`, dokud jej pravidlo nebo schválený
   override nerozhodne.
9. Dokončení plánu vyžaduje explicitní closure nebo splnění přesně definovaného
   evidence contractu pro všechny povinné části.
10. Project-level blocker nesmí být ztracen jen proto, že nemá `planId`.

Nový plán musí vytvořit signal-specific precedence matrix a testovací fixtures pro
každou významnou konfliktní kombinaci.

## Nedestruktivní evidence reconciliation

### Co se má udělat

- Klasifikovat projekty, plány, EPICy, runy a problémy.
- Identifikovat aliasy a duplicitní identity.
- Rozlišit active, closed, historical, legacy, test/stub a unknown data.
- Detekovat closure debt, orphan evidence a konfliktní stav.
- Vytvořit canonical alias map bez přepisování originálu.
- Vygenerovat dry-run report se všemi navrženými klasifikacemi.
- Automaticky přijmout pouze high-confidence případy s doloženým pravidlem.
- Nejasné případy předložit jako explicitní review queue.
- Uchovat provenance každé klasifikace a manuálního rozhodnutí.

### Co se nesmí udělat

- Mazat historickou evidenci.
- Přesouvat soubory bez schválené migrační strategie a rollbacku.
- Přepisovat původní auditní výsledky.
- Označit missing evidence jako pass/fail/completed.
- Použít větší číslo EPICu jako důkaz supersession.
- Označit plán completed jen proto, že poslední známý EPIC je merged.
- Skrýt closure debt nebo unresolved project-level concern.
- Vytvořit druhý Cockpit-specific resolver paralelně k foundation vrstvě.

## Změny producenta AID

Nový plán musí přesně identifikovat všechny skripty, hooks a FSM přechody, které
current-state vytvářejí nebo mění. Producent musí zapisovat jednoznačné lifecycle
události alespoň pro:

- project/plan activation a pause/resume,
- plan ready/start,
- EPIC/run start,
- FSM transition,
- decision requested a decision recorded,
- blocker/problem opened,
- blocker/problem resolved,
- gate/compliance/audit closure relevantní pro aktuální problém,
- EPIC completion,
- plan completion a explicit closure,
- abort/abandon,
- archive,
- supersession včetně vazby na původní entitu,
- queue insert/remove/reorder.

Události musí mít stabilní entity IDs, timestamp, actor, reason, source/evidence
references, schema version a idempotency identity. Zápis current-state musí být
atomický nebo bezpečně rekonstruovatelný po přerušení.

Producer enforcement musí zabránit dokončení/archive přechodu bez povinných closure
dat nebo musí stav explicitně označit jako `completed_unclosed`/partial. Nesmí
potichu vytvořit falešné `completed`.

## Backlog, audit a výstupy rolí

Foundation musí podporovat plan-first Cockpit, ale nesmí vynucovat nepravdivé
vazby:

- Backlog item se připojí k plánu pouze při doloženém `planId`/EPIC/context vztahu.
- Nezařazený backlog zůstává project-level.
- P0/project concern zůstává viditelný i bez plánu.
- Plan audit summary musí rozlišit boundary audit, aggregate audit, poslední audit,
  trend a chybějící audit.
- Reporter/Simplifier výstupy se vážou k plánu pouze s doloženou membership.
- Chybějící role output je missing evidence, ne pozitivní výsledek.
- Backlog delta a audit recommendations nesmějí být prezentovány jako aktuální
  blocker bez lifecycle/action pravidla.

## Dopad na Cockpit

Po dokončení foundation E-047-6_7 pokračuje nad kanonickým current-state:

1. Screen G je portfolio šesti projektů a jejich otevřených plánů.
2. Projekt je primární skupina, plán primární manažerská jednotka.
3. Každý plán ukazuje, co dodává, lifecycle, data quality, poslední významnou
   aktivitu, další krok, rozhodnutí, blokace, audit a backlog summary.
4. EPICy a FSM jsou drill-down.
5. Current decisions/blockers se počítají pouze z current-state, ne přes celý
   historický inventář.
6. Historical analytics čte historickou evidence vrstvu, nikoliv pouze current
   manifest.
7. Chybějící current-state je viditelné `unknown`, ne fallback na mtime odhad.
8. Kvalita dat je jeden přehledný souhrn s drill-downem, ne několik stran falešných
   operativních problémů.

Existing F1 `managerial-model.ts` je prototyp prezentačního modelu. Nesmí se stát
novým zdrojem lifecycle pravdy. Po foundation se musí přepojit na kanonické facts,
nebo nahradit.

## Navržené pořadí nového plánu

Detailní plán má být samostatný a reviewable. Doporučené EPICy/fáze:

### Fáze 1 - Evidence readiness audit

- Kompletní inventory šesti projektů.
- Machine report + human-readable report.
- Plan-first oracle se zdrojovými referencemi.
- Seznam aliasů, konfliktů, closure debt, legacy/stub a unknown případů.
- Baseline metriky a explicitní seznam manuálních rozhodnutí.

### Fáze 2 - Current-state a lifecycle contract

- Entity schemas, enums, qualifiers a nullability.
- Source-specific precedence matrix.
- Completion/closure/supersession pravidla.
- Artifact ownership, cesta, formát, schema versioning a migration strategy.
- Contract tests a fixtures pro konfliktní evidence.

### Fáze 3 - Shared reconciler a dry-run tooling

- Jediný sdílený reconciler.
- Read-only scan a report.
- Provenance/confidence.
- Alias resolution.
- Review queue a manual override mechanism.
- Negative controls dokazující, že mtime/FSM/git samostatně nevytvoří false state.

### Fáze 4 - Producer lifecycle enforcement

- Integrace do AID FSM/scripts/hooks.
- Atomic current-state updates.
- Problem/decision open-close vazby.
- Plan closure, abandon, archive a supersession.
- Queue ownership a pořadí.
- Recovery po přerušeném zápisu.

### Fáze 5 - Backfill a rollout na šest projektů

- Dry-run před každou změnou.
- Human approval nejasných případů.
- Vygenerování current-state pro všechny projekty.
- Reconciliation report before/after.
- Žádné destruktivní změny historické evidence.
- Ověření opakovaného běhu/idempotence.

### Fáze 6 - Foundation acceptance a Cockpit hand-back

- Runtime probe na všech šesti projektech.
- Porovnání s ručně schváleným plan-first oracle.
- Contract/API handoff pro E-047-6_7.
- P047 a E-047-6_7 dostanou explicitní completed dependency.
- Teprve poté se obnoví Screen G, F2 supersession a propagace do dalších obrazovek.

## Blocking acceptance kritéria foundation

1. Každý ze šesti projektů má kanonický stav s provenance a evidence quality.
2. Každý discoverable plán má lifecycle nebo explicitní `unknown`; žádný se
   neztratí jen kvůli chybějící evidenci.
3. Projekt podporuje více otevřených plánů současně.
4. Archivovaný task ani touched historical run se nemůže stát active frontier.
5. Mtime samo nikdy neurčuje lifecycle.
6. Git merge samo nikdy neurčuje completion celého plánu.
7. Closure debt je odlišen od active i completed.
8. Plánovaná pause je odlišena od stale; age samo nemění lifecycle.
9. Project-level concern bez plánu zůstává viditelný.
10. Alias/duplicate resolution je deterministické a doložené.
11. Konflikt zdrojů končí `unknown/conflicting`, ne náhodným vítězem.
12. Reconciliation nemaže ani nepřepisuje historickou evidenci.
13. Producer zapisuje start/finish/pause/resume/abort/archive/supersession a
    problem/decision closure.
14. Repeated producer/reconciler run je idempotentní.
15. Current-state všech šesti projektů odpovídá schválenému real-data oracle nebo
    má explicitně schválenou odchylku.
16. Cockpit může current-state přečíst bez vlastního multi-source lifecycle guessingu.
17. Chybějící current-state se zobrazí jako unknown, ne jako fallback positive.
18. Testy obsahují negative controls pro známé false-active a false-completed případy.

## Co je mimo scope

- LLM summary, LLM enrichment nebo agent rozhodující lifecycle.
- Přepis celého historického analytics modelu Cockpitu.
- Backlog write UI a uživatelské poznámky.
- Odstranění raw evidence nebo auditní historie.
- Kosmetické pokračování ostatních Cockpit obrazovek před foundation acceptance.
- Automatické rozhodování nejasných business stavů bez schváleného pravidla.

## Zacházení se současnou prací E-047-6_7

- Commit `3b40e88` zachovat nemergnutý.
- `docs/design/E-047-6-expected-screen-G.md` zachovat jako golden product oracle.
- `docs/design/E-047-6-productization-addendum.md` zachovat; nový foundation plán
  jej doplní, nikoliv přepíše.
- Nepropagovat F1 read-model do Screen B/Plan/C/D/E.
- Nezahazovat prezentační komponenty, textový playbook ani placeholder tests.
- Po foundation auditu rozhodnout, které kontrakty z F1 jsou znovupoužitelné.
- E-047-6_7 dokončit až nad current-state contractem a po novém live PM acceptance.

## Povinný výstup plánovacího agenta

Plánovací agent musí dodat implementačně připravený plán, nikoliv další obecnou
analýzu. Každý krok musí obsahovat:

- konkrétní objective,
- přesné soubory/moduly po předchozím repository research,
- ownership a hranice mezi pluginem, scripts, contractem a Cockpitem,
- input/output schema,
- source precedence a error handling,
- migration/backfill a rollback,
- real-data fixtures a independent oracle,
- negative controls,
- acceptance criteria,
- závislosti a pořadí,
- realistický effort/risk,
- explicitní ochranu existující nemergnuté práce.

Před sepsáním plánu musí agent ověřit reálné zdroje ve všech šesti projektech a
existující AID lifecycle writery. Nesmí předpokládat nový artifact path nebo script
ownership bez repository evidence.

