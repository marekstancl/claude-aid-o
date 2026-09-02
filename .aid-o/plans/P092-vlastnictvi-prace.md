---
id: P092
type: plan
status: on_hold
created: 2026-08-31
author: PM + AI
risk: high
source_interim: .aid-o/work/interim-P092.md
hold_reason: "PM 2026-08-31: „za mě to aktuálně docela funguje, čili plán sepíšeme (…) ale dáme jej zatím k ledu.\" Vydané opravy (v2.95.11) bolest odstranily; tenhle plán odstraňuje příčinu."
---

# P092 - kdo tu práci dělá: vlastnictví místo odhadu

> Shrnutí pro PM se renderuje (`aid_plan_summary_render`), nepíše se sem (V6).

**Vize:** `.aid-o/work/interim-P092.md` §Vize (V1-V4), schválená formou návrhu
2026-08-31; PM ji potvrdí při rozmrazení spolu se třemi rozhodnutími níže.

## Context

V projektu, kde běží víc oken nad týmž repozitářem, hooky říkaly oknu A, ať
dodělá nebo opraví práci okna B. Třikrát za tři dny, pokaždé jiné pravidlo:

| kdy | pravidlo | co hlásilo cizímu oknu |
|---|---|---|
| 28. 8. | `milestone_artifact_rendered` | přerenderovat stránku plánu P062, který měnilo jiné okno |
| 30. 8. | `queue_continuation_notice` | všechny otevřené plány v projektu, na každém tahu |
| 31. 8. | `turn_step_open` | dodělat `step_1_backend` (E-020-2_3), dispatchnutý ve 4:19 jiným během |

**Příčina je jedna a je to chybějící pojem, ne chybná podmínka: AID nikde
nezaznamenává, kdo práci začal.** Každé pravidlo si to proto domýšlí, a každé
jinak — doloženo grepem 2026-08-31:

| pravidlo | čím dnes odpovídá na „je to moje?" |
|---|---|
| `aid-artifact-obligation.sh` | časem (`find -newer`) **i** textem přepisu |
| `aid-queue-continuation.sh` | textem přepisu |
| `aid-hook-rules-turn.sh` | zapsaným vlastníkem (rozdělaná oprava, necommitnutá) |

V jednom okně je odhad podle času vždy správný — všechno, co se pohnulo, pohnul
ten jediný, kdo tam byl. Ve dvou oknech je vždy špatný: **„stalo se to po mém
startu" není „udělal jsem to já".**

Opravovalo se to po jednom pravidle, pokaždé jinou náhražkou (čas → zmínky
v přepisu → parsované zápisy → whitelist shellových forem). U jednoho z nich
pět kol nezávislého posudku vyrobilo pět užších verzí a pět nových
protipříkladů, poslední `echo "tee .aid-o/plans/P900.md"`. **Statická inspekce
tuhle otázku nikdy nezavře, protože se hádá o něčem, co lze zapsat.**

Nezávislý posudek (Codex, 2026-08-31) základ potvrdil — *„recording dispatch
provenance is the right foundation"* — a přidal tři výhrady, které tenhle plán
řeší jmenovitě: druhá nezávislá vada u fronty (Krok 4), rozdíl mezi „kdo
dispatchl" a „kdo dokončí" (Krok 5), a ztráta rozdělané práce bez podpisu
(Krok 4, přehled na startu).

## Goal

Otázku „je tahle rozdělaná práce moje?" zodpovídá **zápis**, ne odhad, a
odpovídá na ni **jedno místo**, které používají všechna tři pravidla. Cizí ani
nepodepsaná práce se přitom neztratí.

## Scope

**In:** zápis vlastníka při dispatchi; sdílená odpověď na otázku vlastnictví;
převedení všech tří pravidel na ni; přehled cizí a nepodepsané práce na začátku
session; vědomé převzetí práce; registr a dokumentace.

**Out:** pronájem vlastnictví s vypršením a stabilní identifikátor běhu vedle
session (Codexův návrh — vypršení znamená znovu hlídat čas, tedy návrat k tomu,
co se odstraňuje); vlastnictví u čehokoliv jiného než rozdělané práce (souborů,
větví, front); změna toho, CO pravidla hlásí — mění se jen KOMU.

## Standards (V3)

| Standard | Proč se váže | Odchylka |
|---|---|---|
| `/ecosystem/specs/agent-hooks/` | plán mění tři hooková pravidla | žádná |
| `/ecosystem/specs/test-standard` | nové sady a jejich patra | žádná |
| `/ecosystem/specs/artifact-standard` | Krok 4 mění, komu stránka milníku chodí | žádná - mění se adresát, ne obsah ani kostra |
| `/ecosystem/specs/ci-versioning-standard` | Krok 6 zapisuje do obou CHANGELOGů a plán se vydává | žádná |
| `/ecosystem/specs/documentation-placement` | Krok 6 píše do `docs/extending-aid.md` | žádná - dokumentace pro přispěvatele do pluginu, zůstává v repu |

## Reuse check - souhrn

| Co by šlo napsat nově | Co existuje | Rozhodnutí |
|---|---|---|
| odpověď „je to moje?" | nic sdíleného; tři vlastní verze ve třech pravidlech | **založit jedno místo**, tři kopie zrušit |
| identita session | `CLAUDE_CODE_SESSION_ID` v prostředí; v hooku `.session_id` a jméno souboru přepisu | převzít, nezavádět vlastní |
| kde se dispatch zaznamenává | `contract.json` (`lib/aid-dispatch-contract.sh`) | přidat pole, nezakládat druhý záznam |
| paměť „řekni to jednou" | `aid_session_once` (`lib/aid-session-store.sh`) | používat beze změny |

## Implementation Steps

**EPIC 1: Steps 1-3 - Zápis a jedno místo, které se ptá**

### Step 1: Vlastník se zapisuje při dispatchi

**Objective:** každá dispatchnutá práce nese session, která ji vydala.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-dispatch-contract.sh` — `dispatched_by_session` v kontraktu, mimo hash verze
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-dispatch-contract.bats` (tier: t0) — pole se zapíše, chybějící identita je null, hash verze se nemění

**Reuse check:** searched: `grep -rln 'contract.json\|aid_dispatch_contract_allowed' plugins/aid-orchestrator/scripts` → several matching `aid-dispatch-contract.sh` `aid-hook-rules-turn.sh` `aid-fsm.sh` — kontrakt kroku je jediné místo, kde se dispatch dnes zaznamenává; přidává se do něj pole, druhý záznam se nezakládá.

**Architecture Context:**
Tohle je jediný krok, který něco NOVÉHO zapisuje; zbytek plánu jen přestává
hádat. Pole stojí **mimo hash verze kontraktu** schválně: dva shodné balíčky
vydané různými okny jsou tatáž instrukce a agent nesmí dostat hlášku, že mu
zadání zestaralo, protože ho vydalo jiné okno.

**Parallel group:** ---

**Implementation Detail:**
`aid_dispatch_contract_build` zapíše `dispatched_by_session` z
`CLAUDE_CODE_SESSION_ID` (fallback `AID_SESSION_ID`). Prázdná hodnota se zapíše
jako `null` — „nevím" je platná odpověď a nesmí se tvářit jako identita.

**Error Handling:** proměnná chybí → `null` a kontrakt vznikne; dispatch se kvůli
identitě nikdy nezastaví.

**Edge Cases:**
- Subagent s vlastní identitou → zapíše se jeho; posuzuje se shoda, ne původ.
- Obnovená session s jiným id → kontrakt zůstává cizí, dokud se nepřevezme (Krok 5).
- Kontrakt z doby před tímhle krokem → pole nemá; řeší Krok 4.

**Dependencies:**
- Depends on: none
- Blocks: Step 2

**Tests:** rozšíření existující sady o tři případy.

**Acceptance Criteria:**
- [ ] AC1 — kontrakt nese `dispatched_by_session` s identitou okna, které ho vydalo
- [ ] AC2 — bez identity je pole `null` a dispatch proběhne
- [ ] AC3 — hash verze kontraktu se přidáním pole nezmění

**Effort:** S
**AID Role:** backend

### Step 2: Jedno místo, které odpovídá „je to moje?"

**Objective:** existuje sdílená funkce, kterou se ptají všechna pravidla.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-ownership.sh` — `aid_owner_of`, `aid_is_mine`, `aid_session_self`
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-ownership.bats` (tier: t0) — shoda, neshoda, chybějící pole, chybějící identita

**Reuse check:** searched: `find plugins/aid-orchestrator/scripts/lib -name 'aid-ownership.sh'` → none — sdílená odpověď neexistuje; tři pravidla mají tři vlastní verze (`aid-artifact-obligation.sh` dokonce dvě naráz), a právě to je příčina, kterou plán odstraňuje.

**Architecture Context:**
Tři odpovědi na jednu otázku jsou důvod, proč se každé pravidlo rozbilo zvlášť
a proč každá oprava vyrobila jiný protipříklad. Jedno místo znamená, že další
pravidlo si čtvrtou odpověď **nemá kde vymyslet**.

**Parallel group:** ---

**Implementation Detail:**
- `aid_session_self <event_json>` — identita tohohle okna: `.session_id`
  z události, jinak jméno souboru přepisu bez přípony. Prázdné = „nevím".
- `aid_owner_of <contract.json>` — `dispatched_by_session`, nebo prázdno.
- `aid_is_mine <owner> <self>` — 0 při shodě. **Prázdný vlastník i prázdná
  identita vracejí 1** (není moje): přisvojit si cizí práci je horší chyba než
  o vlastní práci mlčet, a mlčení má záchytku v Kroku 4.

**Error Handling:** nečitelný kontrakt → „není moje" a zapíše se to; nikdy se
z chyby čtení nestane vlastnictví.

**Edge Cases:**
- Kontrakt bez pole → není ničí; přehled v Kroku 4 ho ukáže.
- Událost bez `session_id` i bez přepisu → „nevím" → nic není moje.
- Dvě okna se stejnou identitou → nemůže nastat; identitu vydává harness.

**Dependencies:**
- Depends on: Step 1
- Blocks: Steps 3-5

**Tests:** nová sada `test-ownership.bats` (t0) — čtyři případy, včetně obou
prázdných stran.

**Acceptance Criteria:**
- [ ] AC4 — shoda vlastníka a identity je „moje", neshoda není
- [ ] AC5 — prázdný vlastník ani prázdná identita nikdy nevrátí „moje"
- [ ] AC6 — nečitelný kontrakt vrací „není moje" a řekne to

**Effort:** M
**AID Role:** backend

### Step 3: Dvě pravidla o krocích se ptají jí

**Objective:** `turn_step_open` a `turn_write_scope` přestanou počítat čas.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-hook-rules-turn.sh` — `aid_turn_open_steps` filtruje podle vlastníka, `mtime >= since` mizí
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-hook-rules-turn.bats` (tier: t0) — cizí krok, vlastní krok, nepodepsaný krok

**Reuse check:** searched: `grep -n 'mtime >= since' plugins/aid-orchestrator/scripts/lib/aid-hook-rules-turn.sh` → one match — časové okno je tady jediné a nahrazuje se dotazem z Kroku 2; rozdělaná (necommitnutá) verze téhle změny z 31. 8. se použije jako výchozí bod, ne jako hotová věc.

**Architecture Context:**
Tohle je pravidlo, které PM naposledy vyzvalo k dodělání cizího kroku, takže je
to referenční případ. `turn_write_scope` používá tutéž funkci pro výběr
otevřených kroků, takže se opravuje spolu s ním — jinak by jedno soudilo podle
vlastníka a druhé podle času.

**Parallel group:** vlna-2

**Implementation Detail:**
`aid_turn_open_steps` dostane identitu okna a vrací jen kroky, jejichž kontrakt
ji nese. `mtime >= since` se odstraní úplně — ne obchází, odstraní. Kroky bez
vlastníka se nevracejí; ukáže je přehled z Kroku 4.

**Error Handling:** identitu nelze zjistit → nevrací se nic a řekne se proč;
pravidlo je `failure: closed`, takže mlčení je bezpečný konec, ne tichý průchod.

**Edge Cases:**
- Vlna víc kroků → posuzuje se každý kontrakt zvlášť.
- Krok dispatchnutý subagentem této session → vlastníkem je subagent; převzetí (Krok 5).
- Zápis mimo rozsah u cizího kroku → neposuzuje se; není čí.

**Dependencies:**
- Depends on: Step 2
- Blocks: none

**Tests:** rozšíření existující sady; klíčové jsou tři případy — cizí, vlastní,
nepodepsaný.

**Acceptance Criteria:**
- [ ] AC7 — krok dispatchnutý jiným oknem turn nezastaví
- [ ] AC8 — krok dispatchnutý tímhle oknem turn zastaví, ať je jakkoliv starý
- [ ] AC9 — v souboru nezůstane žádné porovnání času s началem session

**Effort:** M
**AID Role:** backend

**EPIC 2: Steps 4-6 - Nic se neztratí, a jde to převzít**

### Step 4: Přehled na začátku session, a fronta se ptá stejně

**Objective:** cizí a nepodepsaná práce je vidět tam, kde nepřekáží.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-queue-continuation.sh` — scope plánů z vlastnictví, přehled na `SessionStart` beze změny
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-artifact-obligation.sh` — dotaz z Kroku 2 místo času i textu přepisu
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-artifact-obligation.bats` (tier: t0) — cizí plán, vlastní plán, nepodepsaný v přehledu

**Reuse check:** searched: `grep -c 'find -newer\|grep -oE' plugins/aid-orchestrator/scripts/lib/aid-artifact-obligation.sh` → several matching both the time window and the transcript scan — tenhle soubor nese OBĚ náhražky naráz; obě se nahrazují jedním dotazem, nová logika nevzniká.

**Architecture Context:**
Codexova druhá výhrada: „kdo dispatchl" neodpovídá na otázku, za které PLÁNY
session odpovídá. Odpovídá se z téhož zápisu — plán, jehož běh session
dispatchla nebo jehož soubor zapsala — takže nepřibývá druhý mechanismus.
A jeho třetí výhrada (ztráta práce bez podpisu) se řeší tady: přehled na
`SessionStart` je nefiltrovaný, takže co je cizí nebo bez vlastníka, se ukáže
tam. Konec tahu zůstává tichý.

**Parallel group:** vlna-2

**Implementation Detail:**
Konec tahu: jen vlastní. Začátek session: všechno, co v projektu leží, včetně
nepodepsaného, jednou (`aid_session_once`). Formulace přehledu říká, že jde
o cizí práci a co s ní — ne že ji má čtenář dodělat.

**Error Handling:** dotaz na vlastnictví selže → na konci tahu ticho, v přehledu
se to uvede; nikdy se nevyzývá na základě chyby.

**Edge Cases:**
- Plán otevřený uprostřed session → přehled příštího startu (známá mez, ponechána).
- Projekt bez otevřených plánů → přehled se nerenderuje.
- Nepodepsaná práce → jen v přehledu, nikdy jako povinnost.

**Dependencies:**
- Depends on: Step 2
- Blocks: none

**Tests:** rozšíření obou existujících sad.

**Acceptance Criteria:**
- [ ] AC10 — na konci tahu se hlásí jen práce této session
- [ ] AC11 — přehled na začátku session ukáže i cizí a nepodepsanou práci
- [ ] AC12 — v `aid-artifact-obligation.sh` nezůstane časové okno ani hledání v přepisu

**Effort:** L
**AID Role:** backend

### Step 5: Převzetí práce, vědomé a zapsané

**Objective:** cizí nebo nepodepsanou práci si lze vzít za svou jedním příkazem.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — `adopt-step <epic> <run> <step> --reason <text>`
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-ownership.bats` (tier: t0) — převzetí zapíše vlastníka i důvod, bez důvodu se odmítne

**Reuse check:** searched: `grep -n 'reason' plugins/aid-orchestrator/scripts/aid-fsm.sh` → several matching the audited-repair commands (`--supersede-epic`, `--recreate-worktree`) — tvar „operace s povinným zdůvodněním, zapsaná do auditu" v tomhle repozitáři existuje a přebírá se; nový druh příkazu nevzniká.

**Architecture Context:**
Codexova první výhrada: kdo práci začal, nemusí být ten, kdo ji dokončí — okno
zaniká, práce se obnovuje. Bez převzetí by cizí krok nešlo dodělat nikdy, což je
horší vada než ta původní. **Vypršení vlastnictví se vědomě nezavádí:** znamenalo
by hlídat čas, tedy přesně to, co tenhle plán odstraňuje.

**Parallel group:** ---

**Implementation Detail:**
`adopt-step` přepíše `dispatched_by_session` na identitu volajícího a zapíše
řádek do auditu s důvodem (min. 20 znaků, jako ostatní auditované opravy).
Bez `--reason` se odmítne. Nic jiného se nemění — převzetí je zápis, ne migrace.

**Error Handling:** kontrakt neexistuje → chyba se jménem cesty; identita chybí
→ odmítnutí (převzít práci „nikým" nedává smysl).

**Edge Cases:**
- Převzetí vlastního kroku → projde a zapíše se; není to chyba.
- Dvě okna převezmou týž krok → poslední zápis platí a oba jsou v auditu.
- Krok už dokončený → převzetí projde; vlastnictví není zámek.

**Dependencies:**
- Depends on: Step 2
- Blocks: none

**Tests:** rozšíření sady z Kroku 2 o dva případy.

**Acceptance Criteria:**
- [ ] AC13 — převzetí zapíše novou identitu i důvod do auditu
- [ ] AC14 — bez důvodu se převzetí odmítne
- [ ] AC15 — bez převzetí se cizí práce nestane vlastní, ať uplyne jakkoliv dlouhá doba

**Effort:** M
**AID Role:** backend

### Step 6: Registr, dokumentace, CHANGELOG

**Objective:** co se zavedlo, je dohledatelné jinde než v kódu.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádky pro zápis vlastníka, sdílený dotaz a převzetí
- Modify: `plugins/aid-orchestrator/defaults/hook-registry.yaml` — u všech tří pravidel pole `scope` s tím, čí práci soudí
- Modify: `docs/extending-aid.md` — jak se odpovídá na „je to moje?" a proč ne časem
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` + `CHANGELOG.md` — shodné záznamy

**Reuse check:** searched: `grep -c '^    not_guaranteed:' plugins/aid-orchestrator/defaults/enforcement-registry.yaml` → several matching rows (26) — pole „co nezaručuje" je zavedené a jen se vyplní; kanonický název je `not_guaranteed`.

**Architecture Context:**
Poslední článek. Tenhle plán ruší tři náhražky a nahrazuje je jedním zápisem;
kdyby to nebylo zapsané, příští pravidlo si vymyslí čtvrtou — což je přesně
historie, kvůli které plán vznikl.

**Parallel group:** ---

**Implementation Detail:**
Každý nový mechanismus dostane řádek se stupněm vynucení a větou
`not_guaranteed`. U zápisu vlastníka ta věta říká, že **neřeší, kdo práci
dokončí** — jen kdo ji začal. `extending-aid.md` dostane odstavec „proč se
vlastnictví neodvozuje z času", aby to nikdo nezavedl zpět.

**Error Handling:** řádek bez `instruction` je nepřípustný; kryje existující
kontrola úplnosti registru.

**Edge Cases:**
- Konzument s jedním oknem → chování se pro něj nemění; stojí za to to napsat.
- Vypnuté hooky → registr uvádí, že pravidla neběží.

**Dependencies:**
- Depends on: Steps 1-5
- Blocks: none

**Tests:** žádná nová sada — registr i CHANGELOGy kryjí existující kontroly
úplnosti (`test-enforcement-registry-cites.sh`, kontrola shody obou CHANGELOGů).

**Acceptance Criteria:**
- [ ] AC16 — každý nový mechanismus má řádek se stupněm a větou `not_guaranteed`
- [ ] AC17 — všechna tři hooková pravidla mají v registru `scope`
- [ ] AC18 — oba CHANGELOGy nesou shodný záznam

**Effort:** S
**AID Role:** docs-writer

## Parallel plan

| Pořadí | Krok | Proč až tady |
|---|---|---|
| 1 | 1 | zápis vlastníka je předpoklad všeho |
| 2 | 2 | sdílená odpověď nad tím zápisem |
| 3 | 3 + 4 | dvě nezávislé skupiny pravidel, různé soubory |
| 4 | 5 | převzetí nad hotovým vlastnictvím |
| 5 | 6 | registr a dokumentace nad hotovým celkem |

Kroky 3 a 4 jsou jediná skutečná vlna: sahají na jiné soubory a obě stojí jen
na Kroku 2. Zbytek je řetěz.

## Testing Strategy

**Co se ověřuje a proč:** zápis vlastníka (na něm stojí všechno), sdílená
odpověď včetně obou prázdných stran (tam vznikaly protipříklady), tři pravidla
v obou směrech — cizí mlčí, vlastní hlásí — a převzetí.

**Co se neověřuje novými testy:** registr a dokumentace (Krok 6 — kryjí
existující kontroly úplnosti).

**Patra:** všechny nové sady `t0`; žádná nezakládá git repozitáře.
**Nové sady: 1**, **rozšířené: 4**. Šest kroků, pět testových zásahů.

## Risks

| Riziko | P | Dopad | Zmírnění |
|---|---|---|---|
| Nepodepsaná práce z doby před plánem se přestane hlásit | **V** | střední | přehled na začátku session ji ukazuje; Krok 4 to testuje jmenovitě |
| Identita session se u obnoveného okna změní a práce osiří | S | střední | převzetí jedním příkazem (Krok 5); vlastnictví není zámek |
| Vznikne čtvrtá odpověď na tutéž otázku | S | vysoký | jedno místo + řádek v registru + odstavec v `extending-aid.md`, proč ne časem |
| Subagent má vlastní identitu a jeho krok vypadá jako cizí | **V** | nízký | posuzuje se shoda, ne původ; převzetí to řeší a je zapsané v edge cases Kroku 1 |

## Success Criteria

- [ ] SC1 — otázku „je to moje?" zodpovídá jedno místo a tři pravidla se ho ptají
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-ownership.bats"
  expected_exit: 0
```
- [ ] SC2 — cizí krok turn nezastaví, vlastní ano
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-hook-rules-turn.bats"
  expected_exit: 0
```
- [ ] SC3 — v hookových pravidlech nezůstane odvozování vlastnictví z času
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -c '! grep -rn \"find -newer\\|mtime >= since\" plugins/aid-orchestrator/scripts/lib/aid-artifact-obligation.sh plugins/aid-orchestrator/scripts/lib/aid-hook-rules-turn.sh'"
  expected_exit: 0
```

## Next Steps

**Plán je u ledu (PM 2026-08-31).** Vydané opravy v2.95.11 bolest odstranily
náhražkami; tenhle plán odstraňuje příčinu. Při rozmrazení nejdřív potvrdit tři
rozhodnutí z `.aid-o/work/interim-P092.md` §Rozhodnutí a teprve pak spustit
ceremonii — ta se u odloženého plánu vědomě neběžela, protože se měří znění,
které se do té doby může změnit.
