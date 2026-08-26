---
id: P090
type: plan
status: draft
created: 2026-08-26
author: PM + AI
risk: high
source_plan: .aid-o/plans/P089-artefakty-release-guard-fronta.md
---

# P090 - fronta, která nezastaví

> Shrnutí pro PM se renderuje (`aid_plan_summary_render`), nepíše se sem (V6).

**Vize:** `docs/plans/AID-planning-stack-rework-roadmap.md` §1, závazná.

## Context

Vyděleno z P089 dne 26. 8. 2026 (PM), protože ceremonie CP1-deep ukázala, že
mechanismus, na kterém tam pokračování fronty stálo, **nedrží**. Tři fakta, každé
ověřené v kódu, ne odhadnuté:

**1. Hook turn neudrží.** `aid-hook.sh:316-318`: přijde-li `Stop` s příznakem
`stop_hook_active: true`, **žádné pravidlo už turn odmítnout nesmí** - zapíše se
`degraded` a projde. Turn se tedy dá zadržet nanejvýš jednou; druhý pokus končí
tak jako tak. Pojistka postavená na hooku by dělala míň, než slibuje.

**2. Zeptat se fronty dnes znamená si ji vzít.** `queue_claim_next` vybere
položku a rovnou jí zapíše `status=running` a `started_at`
(`aid-queue-write.sh`, tělo funkce). Neexistuje způsob, jak se **jen podívat**,
co je na řadě. Hook, který by se ptal, by frontu spotřeboval - a kdyby pak turn
přece skončil, položka zůstane `running` bez běhu.

**3. Do fronty se z cesty merge zapisovat nesmí.** `aid-plan-fsm.sh:89-92`
říká doslova, že **ani `epic-start`, ani `epic-merge-to-plan` neprovádí zápis do
fronty**: manifest je autorita nad stavem EPICu, fronta je odvozený pohled, a ta
jednosměrná hrana je tam schválně, aby nevznikl cyklus producent/konzument.
Původní návrh v P089 chtěl nárokování zavěsit právě na `epic-merge-to-plan` -
tedy přesně proti tomuhle rozhodnutí.

PM: „auto režim - očekávám, že přijdu k PC a je hotovo." Tenhle plán to dodává
mechanismem, ne pojistkou.

## Goal

Plán v autonomním režimu doběhne sám: po dokončeném EPICu se pokračuje dalším,
aniž by si na to musel někdo vzpomenout, a aniž by se kvůli tomu porušila
hranice mezi manifestem a frontou.

## Scope

**In:** dotaz na frontu bez nároku; pokračovací smyčka v controlleru; chování
po přerušeném běhu; hookové pravidlo jako připomínka v mezích toho, co
dispatcher dovolí; registr a dokumentace.

**Out:** změna autority nad stavem EPICu (manifest zůstává); zápis do fronty
z `epic-start`/`epic-merge-to-plan`; souběžný běh víc plánů naráz (P087);
artefakty a release guard (P089).

## Standards (V3)

| Standard | Proč se váže | Odchylka |
|---|---|---|
| `/ecosystem/specs/agent-hooks/` | EPIC 2 přidává hookové pravidlo | žádná |
| `/ecosystem/specs/test-standard` | nové sady a jejich patra | žádná |
| `/ecosystem/specs/ci-versioning-standard` | Krok 6 zapisuje do obou CHANGELOGů a plán se vydává | žádná - vydává se běžnou ceremonií, verze se posouvá až při vydání |
| `/ecosystem/specs/documentation-placement` | Krok 6 píše do `docs/extending-aid.md` | žádná - je to dokumentace pro přispěvatele do pluginu, zůstává v repu, ne v Docusaurusu |
| `/ecosystem/specs/artifact-standard` | plán sám renderuje stránku pro PM | žádná - profily per typ řeší P089, tenhle plán jen konzumuje, co bude platit |

## Reuse check - souhrn

| Co by šlo napsat nově | Co existuje | Rozhodnutí |
|---|---|---|
| výběr dalšího EPICu vč. závislostí | `queue_claim_next` v `lib/aid-queue-write.sh` | **rozdělit** na dotaz a nárok, ne psát druhý výběr |
| tvar obsluhy hookového pravidla | `lib/aid-decision-card.sh`, `lib/aid-artifact-obligation.sh` | převzít |
| pokračování po ztrátě kontextu | `resume_artifact` + odvozený `awaiting_host_resume` (`aid-fsm.sh:343-345`) | **využít**, nezavádět druhý |
| záznam o tom, co se stalo | timeline (`.aid-o/work/evidence/<plan>/timeline.jsonl`) | zapisovat tam |

## Implementation Steps

**EPIC 1: Steps 1-4 - Pokračování je kód**

### Step 1: Zeptat se fronty, aniž bych si ji vzal

**Objective:** existuje read-only dotaz „co by bylo na řadě", který nic nemění.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-queue-write.sh` — `queue_peek_next`, sdílený výběr s `queue_claim_next`
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-queue-peek.bats` (tier: t0) — dotaz nemění stav, shoda s nárokem, blokovaná závislost, prázdná fronta

**Reuse check:** searched: `grep -n '^queue_[a-z_]*()' plugins/aid-orchestrator/scripts/lib/aid-queue-write.sh` → several matching `queue_claim_next` `queue_get_status` `queue_set_status` `queue_get_deps` — výběr dalšího EPICu i s vyhodnocením závislostí v knihovně **je**, chybí jen varianta, která nezapisuje; druhý výběr by byl druhá autorita nad toutéž otázkou.

**Architecture Context:**
Dnešní `queue_claim_next` dělá dvě věci naráz: vybere a zabere. Dokud jsou
srostlé, nemůže se nikdo zeptat, aniž by rozhodl. Rozdělení je předpokladem
všeho ostatního v tomhle plánu - hook i smyčka se potřebují **ptát**.

**Parallel group:** ---

**Implementation Detail:**
Výběr (pořadí, filtr podle plánu, vyhodnocení závislostí přes
`git merge-base --is-ancestor`) se vytáhne do sdílené vnitřní funkce. `peek`
vrací tentýž trojí výsledek jako `claim` - `<epic_id>` / `blocked:<id>:<důvod>`
/ `none` - a **nesahá na soubor**. `claim` zůstane beze změny navenek: vybere
totéž a zapíše `status=running` a `started_at`.
**Opraví se i rozpor v dokumentaci téhož souboru:** hlavička u tabulky stavů
tvrdí, že `running` píše `aid-plan-fsm.sh epic-start`, kdežto zapisuje ho tělo
`queue_claim_next`. Komentář se srovná s kódem.

**Error Handling:** zámek fronty nedostupný → `peek` selže hlášeně, nikdy
nevrátí `none` jako by fronta byla prázdná; tichá záměna „nevím" za „nic tu
není" je přesně to, co by pokračování zabilo.

**Edge Cases:**
- Ručně upravená fronta → `peek` čte tytéž netrusted vstupy a přeskočí
  nevalidní `epic_id` stejně jako `claim`.
- Položka `running` bez živého běhu → `peek` ji nevrací; je to stav pro
  člověka, ne pro smyčku.
- Fronta bez položek daného plánu → `none`.

**Dependencies:**
- Depends on: none
- Blocks: Steps 2-5

**Tests:** nová sada `test-queue-peek.bats` (t0) — čtyři případy; klíčový je
„dvojí `peek` vrátí totéž a soubor se nezměnil".

**Acceptance Criteria:**
- [ ] AC1 — `peek` vrátí tentýž výsledek jako `claim`, ale nezmění ani bajt fronty
- [ ] AC2 — nedostupný zámek se hlásí jako chyba, ne jako prázdná fronta
- [ ] AC3 — komentář o tom, kdo píše `running`, souhlasí s kódem

**Effort:** M
**AID Role:** backend

### Step 2: Dotaz na další EPIC jako příkaz

**Objective:** controller se může zeptat jedním příkazem a odpověď je v timeline.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — podpříkaz `next-epic <plan_id>`
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-next-epic.bats` (tier: t0) — tři výsledky, zápis do timeline, neznámý plán

**Reuse check:** searched: `grep -n 'epic-merge-to-plan\|cmd_epic' plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` → several matching the plan-FSM dispatcher — příkazová vrstva nad plánem existuje a nový podpříkaz do ní patří; nová CLI se nezakládá.

**Architecture Context:**
**Nesmí to být zápis do fronty z cesty merge.** `aid-plan-fsm.sh:89-92` říká, že
ani `epic-start`, ani `epic-merge-to-plan` do fronty nezapisují, protože manifest
je autorita a fronta odvozený pohled. `next-epic` je proto **čtení**, samostatný
podpříkaz, a nárok si dělá až `epic-start`, jak to platí dnes.

**Parallel group:** vlna-2

**Implementation Detail:**
`next-epic <plan_id>` vytiskne `<epic_id>` / `blocked:<id>:<důvod>` / `none`
a týž výsledek zapíše do timeline plánu, aby bylo zpětně vidět, **proč** se
pokračovalo nebo nepokračovalo. **Návratové kódy se přebírají z dnešní
konvence `claim-next`** (`pipeline.md:2580` má pro ni tabulku), aby se dvě
podobné otázky nechovaly různě - nález Codexu, že nepřiřazené kódy nutí volajícího
parsovat text:

| Exit | Význam |
|---|---|
| 0 | vytiskne `<epic_id>` - je co dělat |
| 1 | vytiskne `blocked:<id>:<důvod>` nebo `none` - není co nárokovat; není to chyba |
| 2 | chybné `plan_id` nebo použití |
| 3 | zámek nedostupný, nebo se nepodařil zápis do timeline - **nikdy se nesmí číst jako `none`** |

Řádek v timeline má tvar `{"event":"queue_peek","plan_id":…,"result":…,"at":…}`
a jde do `.aid-o/work/evidence/<plan_id>/timeline.jsonl`.

**Error Handling:** neznámý plán → chyba se jménem plánu; nikdy `none`.

**Edge Cases:**
- Plán bez fronty → `none` a řádek v timeline.
- Poslední EPIC → `none`; to je normální konec plánu, ne chyba.
- Blokovaná závislost → `blocked:` s důvodem, ať je vidět, na co se čeká.

**Dependencies:**
- Depends on: Step 1
- Blocks: Step 3

**Tests:** nová sada `test-next-epic.bats` (t0) — tři výsledky + timeline.

**Acceptance Criteria:**
- [ ] AC4 — každá odpověď i každá chybová cesta má kód podle tabulky výše a sada je tvrdí všechny
- [ ] AC5 — každá odpověď zanechá řádek v timeline
- [ ] AC6 — příkaz do fronty nezapisuje (test porovná soubor před a po)

**Effort:** M
**AID Role:** backend

### Step 3: Smyčka v controlleru

**Objective:** po dokončeném EPICu se pokračuje dalším bez zásahu člověka.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-plan-continue.sh` — spustitelný vstupní bod: celá posloupnost po merge v jednom příkazu
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` — kontrakt volajícího: po dokončeném EPICu se volá tenhle příkaz
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — kroky 16a/16b popisují skutečné chování místo ručního postupu
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-plan-continue.bats` (tier: t0) — celá posloupnost, konec na `none`, zastavení na `blocked:`, závislost bez `merge_target`, opakované spuštění

**Reuse check:** searched: `grep -n claim-next plugins/aid-orchestrator/skills/pipeline.md` → several matching the 16a/16b block, incl. the exit-code table at `:2580` and the note *„no production caller invokes them yet"* — posloupnost i její kódy jsou popsané, chybí **program**, který je provede; tenhle krok ho dodává, nová logika fronty nevzniká.

**Architecture Context:**
Tady je **skutečná záruka** tohohle plánu, a proto **nesmí žít v próze**
(nález Codexu, přijat): kdyby se posloupnost jen popsala v `aid-run.md`, byl by
to zase návod, který se prosí - a test by nikdy nedokázal, že ho někdo dodržel.
Vstupní bod je **skript**, takže se dá spustit i otestovat od začátku do konce.
Dokumentace je jeho kontrakt volajícího, ne jeho implementace.

Posloupnost je přesně ta, kterou dnes `pipeline.md` předepisuje člověku
(16a → 16b): **`set-status <hotový EPIC> merged_to_plan` → `claim-next <plán>`
→ `epic-start <nárokovaný EPIC>`**. Codexův nález, že *„`epic-start` nárok
nedělá"*, je doložený: `aid-plan-fsm.sh` do fronty nezapisuje a knihovní funkce
nemají produkčního volajícího (`pipeline.md`: „no production caller invokes them
yet"). Původní znění tohohle kroku tvrdilo opak; opraveno.

**Parallel group:** ---

**Implementation Detail:**
`aid-plan-continue.sh <plan_id> <hotový_epic_id>` udělá čtyři věci v tomhle pořadí
a na každé se dá zastavit:
1. **zrcadlení** - `set-status <hotový_epic_id> merged_to_plan`; exit 1 (terminální
   stav) znamená, že fronta a manifest si odporují: **stop a report**, nikdy ruční
   srovnání;
2. **dotaz** - `aid-plan-fsm.sh next-epic <plan_id>` z Kroku 2: co by bylo na řadě,
   beze změny stavu, s řádkem v timeline. Odpoví-li `none` nebo `blocked:`, končí
   se **tady** a fronta se nikdy nenárokovala. Tím je Krok 2 skutečně použitý -
   původní znění ho deklarovalo jako závislost a nevolalo (nález Codexu);
3. **nárok** - `claim-next <plan_id>`; vrátí-li něco jiného než dotaz v kroku 2,
   platí nárok a rozdíl se zapíše (mezi dotazem a nárokem se fronta mohla změnit);
4. **start** - `epic-start` právě nad tím EPICem, který krok 3 nárokoval.

Na `none` skript **plán neuzavírá sám**: vytiskne, že je plán vyčerpaný, a jmenuje
posloupnost, kterou uzavření v tomhle repozitáři vyžaduje - `plan-finalize`,
`plan-merge-to-main`, `plan-close` (nález Codexu: původní znění tvrdilo, že
`none` plán uzavře, což žádný z těch kroků nedělal).

Exit 3 kdekoliv v řetězu → **opakovat později**, nikdy nepokračovat. Je-li krok 3
neúspěšný po úspěšném nároku, položka zůstane `running` bez běhu; skript to
**pojmenuje** a smíří stav zpět na `pending`, aby si ji mohl vzít další pokus.
Skript je idempotentní: druhé spuštění nad týmž hotovým EPICem zrcadlení
přeskočí a chová se jako první dotaz.
Strop na počet pokračování za turn drží volající (`aid-run.md`) a zapisuje ho do
timeline, aby vadná fronta nevyrobila nekonečný běh.

**Error Handling:** kterýkoliv článek selhal → **nepokračuje se** a řekne se to;
nikdy se nepokračuje „jako by prošel".

**Kam tenhle krok nedosáhne, a proč to tu stojí** (nález Codexu, přijat):
`epic-start` **EPIC nespouští** - registruje větev a záznam v manifestu. Vlastní
práci EPICu dělá agent, a toho žádný shellový skript nespustí. `aid-plan-continue.sh`
tedy dodá **připravený stav a jméno EPICu, který je na řadě**; pokračovat musí
controller, který běží. Plán proto neslibuje, že se práce rozběhne bez živého
controllera - slibuje, že **nikdo si nemusí pamatovat** posloupnost, že se na ni
nedá zapomenout uprostřed a že když turn skončí, je zapsané, co bylo na řadě.
Tohle je mez, ne vada; překonat by ji šlo jen externím runnerem, což je vlastní
rozhodnutí a v tomhle plánu není.

**Edge Cases:**
- Manuální režim → smyčka se nespustí, controller se zeptá PM.
- Plán uzavřen mezitím ručně → `next-epic` vrátí `none`.
- Dva plány naráz → smyčka se týká jen vlastního plánu.

**Dependencies:**
- Depends on: Step 2
- Blocks: none

**Tests:** nová sada `test-plan-continue.bats` (t0) — pět případů nad připravenou
frontou: celá posloupnost, `none`, `blocked:`, **závislost bez `merge_target`**
(kde se na `running` předchůdce čeká trvale, pokud se stav nezrcadlí) a druhé
spuštění nad týmž EPICem.

**Acceptance Criteria:**
- [ ] AC7 — jeden příkaz provede zrcadlení → nárok → start a test to dokládá od začátku do konce, ne z prózy
- [ ] AC8 — `blocked:` i `none` končí bez chyby a `none` **vydá doporučení uzavřít plán** jmenovitě těmi příkazy, které to dnes dělají (`plan-finalize`, `plan-merge-to-main`, `plan-close`); samo uzavření zůstává rozhodnutím controllera, skript ho neprovádí
- [ ] AC9 — `pipeline.md` už netvrdí, že pokračování je ruční, a poznámka „no production caller" mizí, protože volající existuje
- [ ] AC9b — selhal-li start po úspěšném nároku, položka se vrátí na `pending` a je to zapsané

**Effort:** L
**AID Role:** backend

### Step 4: Když se běh přeruší

**Objective:** po ztrátě kontextu nebo pádu je zpětně jasné, kde se má pokračovat.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-continue.sh` — producent **i konzument**: na začátku běhu vodítko přečte, na konci zapíše
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-continue-artifact.bats` (tier: t0) — zápis, chybějící soubor, poškozený soubor, zastaralé vodítko

**Reuse check:** searched: `grep -rn '_resume_artifact_write\|aid-auto-resume' plugins/aid-orchestrator/scripts` → several matching `aid-run-gates.sh:991,1014` (producent, schéma `aid-auto-resume/1`, payload o bráně) a `aid-fsm.sh:343-345` (konzument) — existující artefakt **má svého producenta i svoje schéma a je o branách, ne o frontě**; rozšiřovat ho by znamenalo měnit schéma, které čte někdo jiný. Proto vlastní, malý artefakt s jasným producentem.

**Architecture Context:**
Smyčka z Kroku 3 běží uvnitř turnu. Když turn skončí jinak, než měl - ztráta
kontextu, timeout, rozhodnutí modelu - musí být po obnově vidět, co bylo na řadě.
**Nesahá se přitom na `aid-auto-resume/1`** (nález Codexu): ten artefakt píše
`aid-run-gates.sh` o rozdělané bráně a čte ho `aid-fsm.sh`; přilepit do něj
odpověď fronty by změnilo schéma cizímu čtenáři. Nový artefakt má vlastní
schéma `aid-plan-continue/1`, vlastního producenta (skript z Kroku 3) a je
**vodítko, ne autorita**.

**Parallel group:** ---

**Implementation Detail:**
**Producent i konzument je týž skript** (nález Codexu: artefakt bez čtenáře
nezpůsobí obnovu ničeho). Při každém spuštění `aid-plan-continue.sh` vodítko
nejdřív přečte - když ukazuje na EPIC, který ještě není hotový, ohlásí to
a **nezrcadlí** stav; teprve pak pokračuje obvyklou posloupností a na konci
vodítko přepíše.

`.aid-o/work/evidence/<plan_id>/continue-state.json`, schéma `aid-plan-continue/1`,
pole: `plan_id`, `last_completed_epic`, `last_result`, `at`. Píše se **atomicky**
(zápis do dočasného souboru a přejmenování), aby přerušení nezanechalo půlku.
Po obnově se **znovu zeptáme** - vodítko říká, kde jsme skončili, ne co dělat;
mezitím se mohlo změnit, co je mergnuté. Položka `running` bez živého běhu se
nesmí tiše sebrat: hlásí se člověku, protože je to buď pád, nebo cizí běh.

**Error Handling:** artefakt chybí nebo je poškozený → obnova pokračuje dotazem
na frontu a zapíše, že vodítko chybělo; neplatný obsah se nikdy neinterpretuje
zpola.

**Edge Cases:**
- Turn skončil přesně mezi merge a dotazem → po obnově se prostě zeptáme.
- Artefakt ukazuje na EPIC, který je mezitím hotový → dotaz vrátí další.
- Víc přerušení za sebou → poslední odpověď přepisuje předchozí.

**Dependencies:**
- Depends on: Step 3
- Blocks: none

**Tests:** nová sada `test-continue-artifact.bats` (t0) — čtyři případy: zápis
a jeho atomicita, chybějící soubor, poškozený soubor, vodítko na EPIC, který je
už hotový.

**Acceptance Criteria:**
- [ ] AC10 — po obnově je vidět, co bylo na řadě, i když artefakt chybí
- [ ] AC11 — vodítko se ověřuje dotazem, nepoužívá se slepě
- [ ] AC12 — položka `running` bez běhu se hlásí, nesebere se
- [ ] AC12b — `aid-auto-resume/1` zůstává beze změny; nový artefakt má vlastní schéma

**Effort:** M
**AID Role:** backend

**EPIC 2: Steps 5-6 - Připomínka a dohledatelnost**

### Step 5: Hookové pravidlo v mezích toho, co dispatcher dovolí

**Objective:** konec turnu s nedokončeným plánem se aspoň pojmenuje.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/hook-registry.yaml` — pravidlo `queue_continuation_notice` pro `Stop`
- Create: `plugins/aid-orchestrator/scripts/lib/aid-queue-continuation.sh` — obsluha pravidla
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-queue-continuation.bats` (tier: t0) — připravený EPIC, prázdná fronta, manuální režim, izolace dvou plánů

**Reuse check:** searched: `grep -rln 'aid_hook_rule' plugins/aid-orchestrator/scripts/lib` → several matching `aid-decision-card.sh` `aid-artifact-obligation.sh` `aid-continuity-capsule.sh` — tvar obsluhy pravidla je ustálený a přebírá se.

**Architecture Context:**
**Vědomě stupeň 3, ne 2.** `aid-hook.sh:316-318` při `stop_hook_active: true`
odmítnutí zakazuje - pravidlo, které by se tvářilo jako závora, by lhalo hned
napodruhé. Skutečné pokračování dodává Krok 3; tohle je záchranná síť, která
řekne, co zůstalo rozdělané.

**Parallel group:** vlna-2

**Implementation Detail:**
Pravidlo se ptá **`peek`**, nikdy `claim` - připomínka nesmí frontu spotřebovat.
Aktivuje se jen v autonomním režimu; posuzuje se pole `auto_controller` ze
záznamů běhu v tomhle workspace (`aid-fsm.sh:345-346`, uzavřený slovník
`active manual blocked_for_pm`), čtené **ze souboru**, ne z prostředí. Hláška
jmenuje plán i EPIC. Záznamy `manual` a `blocked_for_pm` se ignorují, takže
manuální práce v projektu, kde souběžně běží autonomní plán, se neblokuje kvůli
cizímu záznamu.

**Error Handling:** frontu ani záznamy nelze přečíst → pravidlo mlčí a zapíše
to; připomínka na základě nejistoty by jen šuměla.

**Edge Cases:**
- Manuální režim → pravidlo se neaktivuje.
- `stop_hook_active: true` → dispatcher pravidlo stejně nepustí; sada to
  ověřuje, aby nikdo příště nečekal víc.
- Fronta blokovaná nemergnutou závislostí → připomínka řekne proč.

**Dependencies:**
- Depends on: Step 1
- Blocks: none

**Tests:** nová sada `test-queue-continuation.bats` (t0) — čtyři případy včetně
izolace dvou souběžných plánů.

**Acceptance Criteria:**
- [ ] AC13 — pravidlo používá `peek`; po jeho běhu je fronta beze změny
- [ ] AC14 — v manuálním režimu mlčí a manuální turn neblokuje ani při cizím autonomním běhu
- [ ] AC15 — při `stop_hook_active` se neuplatní a je to otestované, ne jen napsané

**Effort:** M
**AID Role:** backend

### Step 6: Registr, dokumentace, CHANGELOG

**Objective:** co tenhle plán zavedl, je dohledatelné jinde než v kódu.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádky pro dotaz, smyčku a připomínku
- Modify: `docs/extending-aid.md` — jak pokračování funguje a co která vrstva zaručuje
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` + `CHANGELOG.md` — shodné záznamy
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-queue-registry-rows.bats` (tier: t0) — tři řádky, jejich stupně, `not_guaranteed`, shoda CHANGELOGů

**Reuse check:** searched: `grep -c '^    not_guaranteed:' plugins/aid-orchestrator/defaults/enforcement-registry.yaml` → several matching rows (26) — pole „co nezaručuje" je zavedené a jen se vyplní; kanonický název je `not_guaranteed`.

**Architecture Context:**
Tenhle plán má tři vrstvy s velmi různou silou: dotaz (čtení), smyčka (kód
rozhoduje) a připomínka (jen řekne). Kdyby je registr nerozlišil, četlo by se to
jako tři záruky - a příště by na tu nejslabší někdo spoléhal.

**Parallel group:** ---

**Implementation Detail:**
Každá vrstva dostane řádek se stupněm vynucení a větou `not_guaranteed`.
U připomínky ta věta výslovně říká, že **turn nezadrží** a proč
(`stop_hook_active`). `extending-aid.md` dostane odstavec o tom, kde smyčka
začíná a kde končí.

**Error Handling:** řádek bez `instruction` je nepřípustný; kryje existující
kontrola úplnosti registru.

**Edge Cases:**
- Vypnuté hooky → připomínka neběží; registr to říká.
- Konzument bez autonomního režimu → smyčka se ho netýká.

**Dependencies:**
- Depends on: Steps 1-5
- Blocks: none

**Tests:** nová sada `test-queue-registry-rows.bats` (t0) — tvrdí **jmenovitě**,
že tři nové řádky existují, mají svůj stupeň a neprázdné `not_guaranteed`, že
u připomínky je v té větě `stop_hook_active`, a že obě sekce CHANGELOGu pro tuhle
verzi jsou znak po znaku shodné. Nález Codexu, přijat: `test-enforcement-registry-cites.sh`
ověřuje **rozřešitelnost citací a jedinečnost id**, ne existenci konkrétních řádků,
a kontrola verzí je release-boundary skript, ne člen sady - původní znění se
opíralo o kontroly, které tohle netvrdí.

**Acceptance Criteria:**
- [ ] AC16 — každá ze tří vrstev má řádek se stupněm a větou `not_guaranteed`
- [ ] AC17 — u připomínky je napsáno, že turn nezadrží, a proč
- [ ] AC18 — oba CHANGELOGy nesou shodný záznam

**Effort:** S
**AID Role:** docs-writer

## Parallel plan

| Vlna | Kroky |
|---|---|
| 1 | 1 (sám, `---`) |
| 2 | 2, 5 |
| 3 | 3 (sám, `---`) |
| 4 | 4 (sám, `---`) |
| 5 | 6 (sám, `---`) |

Krok 1 je předpoklad všeho ostatního, proto stojí sám. Kroky 2 a 5 na něm stojí
oba a navzájem si nesahají na soubory. Zbytek drží řetěz: příkaz → smyčka →
obnova → zápis.

## Testing Strategy

**Co se ověřuje a proč:** dotaz bez vedlejšího účinku (na tom stojí celý plán),
příkazová vrstva a její tři odpovědi, pokračovací smyčka (chování, kvůli kterému
plán vznikl), chování po přerušení a hookové pravidlo včetně toho, že při
`stop_hook_active` neplatí.

**Co se neověřuje novými testy:** nic. Původní znění tvrdilo, že registr
a CHANGELOGy kryjí existující kontroly; Codex ukázal, že netvrdí to, co by
musely, a Krok 6 proto dostal vlastní sadu.

**Patra:** všechny nové sady `t0`; žádná nezakládá git repozitáře ani neběží déle
než jednotky sekund. **Nové sady: 6**, **rozšířené: 0**. Šest kroků, šest testových
zásahů.

## Risks

| Riziko | P | Dopad | Zmírnění |
|---|---|---|---|
| Smyčka se zacyklí na vadné frontě | S | vysoký | strop na počet pokračování za turn, zapsaný do timeline |
| `peek` a `claim` se rozejdou | S | vysoký | výběr je jedna sdílená funkce, ne dvě kopie; test porovnává obě odpovědi |
| Připomínka se bude číst jako záruka | **V** | střední | stupeň 3 v registru + věta „turn nezadrží" + test na `stop_hook_active` |
| Autonomní režim se určí špatně a smyčka poběží v manuálním | S | střední | zdroj pravdy je `auto_controller` ze záznamu běhu, čtený ze souboru; izolační test |

## Success Criteria

- [ ] SC1 — dotaz na frontu nemění frontu
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-queue-peek.bats"
  expected_exit: 0
```
- [ ] SC2 — po dokončeném EPICu pokračuje plán sám
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-plan-continue.bats"
  expected_exit: 0
```
- [ ] SC3 — připomínka frontu nespotřebuje a při `stop_hook_active` neplatí
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-queue-continuation.bats"
  expected_exit: 0
```

## Next Steps

Implementace po EPICech. EPIC 1 je to, co PM chtěl („přijdu k PC a je hotovo");
EPIC 2 je záchranná síť a dohledatelnost.
