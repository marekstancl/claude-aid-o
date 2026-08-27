---
id: P089
type: plan
status: done
created: 2026-08-25
author: PM + AI
risk: high
source_interim: .aid-o/work/interim-ARTEFAKTY-PIPELINE.md
source_handoff: docs/plans/handoff-release-scope-guard.md
---

# P089 - artefakty podle fáze a release guard podle souborů

> Shrnutí pro PM se renderuje (`aid_plan_summary_render`), nepíše se sem (V6).

**Vize:** `docs/plans/AID-planning-stack-rework-roadmap.md` §1, závazná.

## Context

Tři nezávislé věci, které čekaly na stejné okno. Každá má doložený spouštěč.

**1. Artefakty.** PM o stránce z bran: „hodnota artefaktu 0". Doloženo na ní:
dlaždice hlásily „6/9 prošlo", ačkoliv selhalo **nula** bran - tři jen neběžely;
jádro jen přepsalo dlaždice do věty a nikdy neřeklo, které brány běžely a co
ověřily; bloky 5 a 7 nesly **třikrát tutéž cestu k souboru**, kterou ekosystémový
standard výslovně zakazuje; a „nic se ode mě nečeká" stálo přímo nad příkazem
k ručnímu spuštění. Vynucuje se dnes **jediná věc a jen u plánu** (`Stop` pravidlo
`plan_artifact_rendered`): že stránka vznikla. Co je na ní, nekontroluje nic.

**2. Release guard.** Pre-push pojistka rozhoduje podle **nálepky commitu**, ne
podle toho, co se změnilo: `fix(testy):` blokne push, i když se aplikace
nezměnila (WAN, třikrát za den), a `chore:` může změnit aplikaci a projde bez
vydání. Ověřeno v kódu: `defaults/hooks/pre-push:86-91` testuje `^feat`, `^fix`,
`^release:` - bez dvojtečky, takže `fixup!` matchne taky. Táž logika je
zduplikovaná v `aid-release.sh:122-147`.

**3. Fronta - vyjmuta do P090.** Pokračování v autonomním režimu bylo součástí
tohohle plánu, dokud CP1-deep neukázalo, že mechanismus, na kterém stálo,
nefunguje: dispatcher druhé odmítnutí `Stop` propustí a `queue_claim_next` si
položku přepne na `running`, takže pojistka by vzápětí neměla co najít. To se
neopraví větou v plánu, chce to vlastní návrh - **P090** (PM 2026-08-26).

## Goal

Stránka nese to, co její fáze dluží, a nemůže si odporovat; a vydání se odvozuje
z dotčených souborů, ne ze slibu v commit zprávě.

## Scope

**In:** kontrakt artefaktů per typ + úprava ekosystémového standardu; oprava
zbylých tří rendererů; stránka dokončeného EPICu; release guard podle souborů
se sdílenou knihovnou a CI fasádou; IMP-517.

**Out:** pokračování fronty v autonomním režimu (**P090**); stránka pro selhaný
krok (PM: „NECHCI ARTIFACT v tomto případě vůbec"); replan a incident jako typy
stránky (nastávají zřídka, obsah neznámý); paralelní běh agentů (P087); zapnutí
`versioning.source` u WANu (IMP-595, cizí plán).

## Standards (V3)

| Standard | Proč se váže | Odchylka |
|---|---|---|
| `/ecosystem/specs/artifact-standard` | EPIC 1 ho mění | **plánovaná odchylka je sám předmět práce**: dnešní kostra neumí per-typ povinnosti a PM ji označil za „trochu mimo"; změna se navrhuje do standardu, ne obchází |
| `/ecosystem/specs/ci-versioning-standard` | EPIC 2 mění, kdy se vydává | žádná |
| `/ecosystem/specs/agent-hooks/` | EPIC 1 rozšiřuje hookové pravidlo (Krok 6) | žádná |
| `/ecosystem/specs/test-standard` | nové sady a jejich patra | žádná |
| `/ecosystem/specs/documentation-placement` | EPIC 1 píše do Docusaurusu | žádná |

## Reuse check - souhrn

| Co by šlo napsat nově | Co existuje | Rozhodnutí |
|---|---|---|
| tvar rozhodnutí (problém → možnosti → doporučení → proč) | `/ecosystem/ai-agents/marek-rozhodovani.md`, zaveden PM 20. 8. | **převzít doslova**, nevymýšlet |
| forma „co která věc dluží" | `/ecosystem/ai-agents/definition-of-done.md` - obecné pravidlo + per typ odškrtnutelné položky | převzít formu |
| renderer stránek a jeho stropy | `lib/aid-artifact-render.sh` | rozšířit o profily, nezakládat druhý |
| hooková vrstva a registr pravidel | `scripts/aid-hook.sh` + `defaults/hook-registry.yaml` (v2.89.0) | přidat řádek |
| shoda cesty se seznamem | `_aid_in_scope` v `defaults/hooks/pre-commit` | převzít tvar |

## Implementation Steps

**EPIC 1: Steps 1-6 - Artefakty podle fáze**

### Step 1: Kontrakt artefaktů v ekosystémovém standardu

**Objective:** standard dostane per-typ povinnosti ve formě, kterou lze odškrtnout.

**Files:**
- Create: `docs/proposals/artifact-standard-profiles.md` — znění změny standardu (obecná pravidla + sekce per typ), připravené k publikaci

**Publikace do Docusaurusu je vědomě MIMO tento krok.** Původní znění deklarovalo
`Modify: /opt/eco/docs/...`, tedy soubor v **jiném git repozitáři**. Kontrakt kroku
(P087) ověřuje očekávané artefakty jako `${root}/${cesta}` a změny sbírá
`git -C "$root" status` — obojí nad repozitářem plánu
(`aid-dispatch-contract.sh:264,273`). Reprodukováno: krok deklarující existující
soubor `/opt/eco/docs/docs/ecosystem/specs/artifact-standard.md` skončí
`verdict: reject`, `reasons: ["expected artifacts are missing on disk: …"]`,
přestože soubor na disku je. Krok tedy nemůže uspět, ani když ho agent udělá
správně. Znění vzniká v repozitáři AID; PM (nebo samostatný běh v repozitáři
`docs`) ho publikuje — viz `## Next Steps`. Podpora druhého kořene v kontraktu je
zapsaná jako **IMP-519**, ne řešená tady.

**Reuse check:** searched: `grep -rln "definition-of-done" /opt/eco/docs/docs/ecosystem/ai-agents` → several matching `/opt/eco/docs/docs/ecosystem/ai-agents/definition-of-done.md` `recepty.md` `adding-an-agent.md` — the one this step reuses is `definition-of-done.md`; forma „obecné pravidlo + per typ výčet odškrtnutelných položek" v ekosystému existuje a přebírá se; nová forma se nevymýšlí.

**Architecture Context:**
Standard je jediná autorita pro tvar stránky; renderer ho implementuje. Proto se
mění nejdřív on a teprve pak kód - obráceně by vznikl kód, který standard
neuznává. Změna se týká i jiných projektů než AID, proto patří do Docusaurusu.

**Parallel group:** vlna-1

**Implementation Detail:**
Kostra zůstává sedmibloková. Přibývá: **`artifact_type` jako povinné pole** a
per typ výčet toho, co dluží blok 2 (dlaždice), 4 (jádro) a 6 (co se čeká).
Pět typů: brainstorming, plán, brány, dokončený EPIC, dokončený plán.
Blok 6 přebírá tvar rozhodnutí z `marek-rozhodovani.md` doslova (problém →
možnosti → doporučení → proč) a doplňuje **„co se stane, když nerozhodneš"**
(PM 2026-08-25; vlastník ani lhůta se neuvádí - vlastník je vždy PM).
Zapisuje se i pravidlo o odkazech: jména na stabilní cíle, nikdy cesty ani
příkazy.

**Error Handling:** stránka bez `artifact_type` je vada standardu i renderu -
popsáno na obou místech; typ mimo pětici je chyba, ne důvod k improvizaci.
Nepublikované znění je platný mezistav: Krok 2 implementuje kontrakt z tohoto
souboru, publikace ho nemění.

**Edge Cases:**
- Projekt bez některé fáze (nemá EPICy) → typ se prostě nepoužije.
- Nový typ v budoucnu → přidává se sekcí ve standardu, ne výjimkou v kódu.
- Konzument mimo eco → standard je veřejný, kontrakt platí stejně.

**Dependencies:**
- Depends on: none
- Blocks: Step 2 — renderer implementuje, co standard řekne

**Tests:** žádná nová sada — je to dokument. Soulad kódu se standardem hlídá
Krok 2 a jeho sada.

**Acceptance Criteria:**
- [ ] AC1 — standard obsahuje pět typů a u každého povinnosti bloků 2, 4 a 6
- [ ] AC2 — tvar rozhodnutí je převzatý z `marek-rozhodovani.md`, ne přepsaný
- [ ] AC3 — pravidlo „odkaz je jméno, ne cesta" je ve znění explicitní
- [ ] AC3b — znění je v repozitáři AID; publikace do Docusaurusu je uvedená v `## Next Steps` jako ruční, s důvodem

**Effort:** M
**AID Role:** docs-writer

### Step 2: Profily v rendereru

**Objective:** renderer odmítne vyrenderovat stránku, která nenese, co její typ dluží.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-artifact-render.sh` — `artifact_type` a per-typ povinná pole
- Create: `plugins/aid-orchestrator/defaults/artifact-profiles.yaml` — co který typ dluží
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-artifact-profiles.bats` (tier: t0) — chybějící povinnost, neznámý typ, vnitřní rozpor

**Reuse check:** searched: `find plugins/aid-orchestrator/defaults -name 'artifact-profiles.yaml'` → none — profily zatím neexistují; renderer má dnes jen jednu sadu pravidel pro všechny typy, proto nový soubor, ne rozšíření existujícího.

**Architecture Context:**
Stroj hlídá **přítomnost, tvar a vnitřní rozpory**, kvalitu posuzuje čtenář -
tuhle hranici zapisuje standard a renderer ji implementuje. Profil je data,
ne kód: nový typ je řádek v `artifact-profiles.yaml`, ne větev v rendereru.

**Parallel group:** ---

**Implementation Detail:**
`aid_artifact_render` přijme `artifact_type` a proti profilu ověří povinná pole.
Strojově kontrolovatelné rozpory (návrh Codexe, přijat). **Formulace se odvozuje
ze stavu, nekontroluje se próza** (druhý nález Codexu, přijat): volající předá
stav (`failed_count`, `not_run_count`, `attempt`) a renderer z něj větu složí -
tím je „nula selhání + jazyk selhání" nemožný stavem, ne detekcí slovníku, který
by nikdy nebyl úplný. Kontrolují se tedy rozpory mezi **poli**, ne slova: „nic se nečeká" nesmí stát vedle
neprázdného seznamu dalších kroků; sekce backlogu existuje jen při nenulovém
počtu položek; odkaz musí mít jméno a nesmí duplikovat cíl detailu; **cesta
k souboru v blocích 5 a 7 je chyba**.

**Error Handling:** chybějící povinnost → render selže se jménem typu i pole;
nikdy se nevyrenderuje stránka, která svůj typ nenaplňuje.

**Edge Cases:**
- Typ bez profilu → chyba, ne výchozí chování.
- Profil vyžaduje pole, které volající nezná → chyba u volajícího, ne tichý default.
- Starší volající bez `artifact_type` → přechodně se chová jako dnes a zapíše to.

**Dependencies:**
- Depends on: Step 1 — implementuje jeho kontrakt
- Blocks: Steps 3-5

**Tests:** nová sada `test-artifact-profiles.bats` (t0) — čtyři případy: chybějící
povinné pole, neznámý typ, rozpor „nula selhání + jazyk selhání", cesta v odkazech.

**Acceptance Criteria:**
- [ ] AC4 — stránka bez povinného pole svého typu se nevyrenderuje
- [ ] AC5 — formulace o výsledku se odvozuje ze stavu (`failed_count` a spol.), takže rozpor mezi počtem selhání a větou nemůže vzniknout; test dokládá obě větve
- [ ] AC6 — cesta k souboru v blocích 5 a 7 je odmítnuta

**Effort:** L
**AID Role:** backend

### Step 3: Stránka bran řekne, co se ověřilo

**Objective:** stránka bran odděluje „neběželo" od „selhalo" a říká, co ta ověření dokazují.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-gate-outcome-summary.sh` — dlaždice, jádro, odkazy podle profilu
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-outcome-summary.bats` — rozšířit o profil a o rozpor

**Reuse check:** searched: `grep -rln aid_artifact_render plugins/aid-orchestrator/scripts/lib` → several matching `aid-artifact-render.sh` `aid-plan-close-summary.sh` `aid-gate-outcome-summary.sh` `aid-plan-summary.sh` `aid-brainstorm-summary.sh` — renderer i vzor volajícího existují; mění se jen fakty, které tenhle volající skládá.

**Architecture Context:**
Tenhle volající vyrábí stránku, kterou PM označil za bezcennou - je to referenční
případ celého EPICu. Co se tady ukáže jako chybějící v profilu, patří zpět do
Kroku 2, ne do výjimky tady.

**Parallel group:** vlna-2

**Implementation Detail:**
Dlaždice: **kolik selhalo** (ne „prošlo X z Y"), doba běhu, kolik neběželo,
kolik pokusů. **Rozdíl „neběželo" × „selhalo" má mapování, ne odhad** (nález
Codexu, kolo 2): producent bran emituje `result` z uzavřené řady
(`pass|fail|skip|profile_excluded`) a infrastrukturní potíž dnes vypadá jako
`result: fail` s `reason` (např. `service_unhealthy`,
`aid-run-gates.sh:796,1971`). Mapování je proto výslovné a testované:
`skip`/`profile_excluded` → **neběželo**; `fail` s důvodem ze seznamu
infrastrukturních důvodů → **neběželo**, a stránka ten důvod jmenuje;
`fail` s **neznámým** důvodem → **selhalo**, s větou „důvod neznámý" -
konzervativně, protože tichý přesun mezi kategoriemi je horší než přiznaná
nejistota; **`waived` → vlastní kategorie „prominuto", nikdy ne „prošlo"**
(nález Codexu, kolo 3: `waived` je plnohodnotná hodnota `result`, runner ji píše
s `waiver_ref` a dnešní volající ji už teď čte jako přijaté riziko, ne jako
průchod). Dlaždice ji počítá zvlášť a jádro jmenuje, kdo prominutí schválil. Jádro: které brány běžely a co ověřily; u těch, co neběžely,
proč (mimo profil / přeskočeno / nespuštěno). Blok 6: rozhodnutí jen tehdy,
když je potřeba - jinak výslovné „nic se nečeká" bez příkazu vedle.

**Error Handling:** report bran nečitelný → stránka se nevyrenderuje a řekne to;
nikdy se nerenderuje stránka s dopočítanými čísly.

**Edge Cases:**
- Všechny brány přeskočené → dlaždice „0 selhalo" a jádro řekne, že se nic neověřilo.
- Brána spadla na infrastruktuře, ne na kódu → patří mezi „neběželo", ne „selhalo".
- Druhý pokus po opravě → uvede se, co se změnilo od minula.

**Dependencies:**
- Depends on: Step 2
- Blocks: none

**Tests:** rozšíření existující sady o dva případy: nula selhání nesmí vyrobit
jazyk selhání; neběžící brána se nezapočítá mezi selhané.

**Acceptance Criteria:**
- [ ] AC7 — dlaždice hlásí počet selhání, ne poměr prošlých
- [ ] AC8 — jádro jmenuje běžící brány a co ověřily
- [ ] AC9 — „nic se nečeká" nikdy nestojí vedle příkazu
- [ ] AC9b — `fail` s infrastrukturním důvodem se počítá jako „neběželo", `fail` s neznámým důvodem jako „selhalo"; obě větve mají fixture
- [ ] AC9c — `waived` má vlastní počet a nikdy se nezapočítá mezi prošlé

**Effort:** M
**AID Role:** backend

### Step 4: Stránka dokončeného EPICu

**Objective:** po dokončení EPICu vzniká stránka s tím, co dodal, co se pokazilo a jaké backlog položky vznikly.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-epic-summary-page.sh` — volající rendereru pro dokončený EPIC
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — `cmd_done_advance` volá renderer po dokončené revizi
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — render po dokončení revize

**Produkční volající je jmenovaný, ne popsaný** (nález Codexu): bez něj by Krok 6
vynucoval stránku, kterou nikdo nevyrábí — tedy pravidlo, které se prosí, přesně
to, co tenhle plán ruší u fronty. Místo je `cmd_done_advance` v `aid-fsm.sh`,
kde DONE fáze uzavírá revizi. Renderer píše tělo; publikaci dělá controller
(kontrakt šablon se nemění).

**Datový kontrakt stránky** (druhý nález Codexu — bez něj nemá Krok 6 podle čeho
poznat, že stránka je a je čerstvá):
- **vstupy:** `audit-report.md` (nálezy a `blocking_findings`) a report kurátora
  z evidence dir daného EPICu; chybí-li kterýkoliv, stránka vznikne a **pojmenuje
  ho jako chybějící**;
- **výstup:** `.aid-o/work/evidence/<plan_id>/<epic_id>/epic-summary-artifact.html`
  — tedy táž konvence jako `plan-summary-artifact.html`, aby `aid-artifact-obligation.sh`
  hledal jedním pravidlem, ne dvěma;
- **čerstvost:** stránka musí být novější než **poslední commit EPICu** (tentýž
  test „starší než zdroj", jaký dnes platí pro plán);
- **co čte Stop handler z Kroku 6:** existenci té cesty a její čas proti tomu
  commitu. Nic jiného; žádné parsování obsahu.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-epic-summary-page.bats` (tier: t0) — dodávka, nálezy, backlog položky, prázdný backlog

**Reuse check:** searched: `find plugins/aid-orchestrator/scripts/lib -name 'aid-epic-summary-page.sh'` → none — stránka pro dokončený EPIC neexistuje; `aid-epic-summary.sh` je něco jiného (markdown report do evidence, ne stránka pro PM) a zůstává.

**Architecture Context:**
**Toto je chybějící artefakt, na který došly oba modely nezávisle.** Backlog
položky vyrábí Curator při revizi hotového EPICu; dnes se o nich PM dozví jen
tak, že přibyly v `backlog.md`. Stránka je jediné místo, kde uvidí i **proč**
vznikly. Renderuje se **až když je fáze opravdu hotová** (PM: „až ve chvíli, kdy
je to opravdu hotové"), tedy po revizi, ne po posledním kroku.

**Parallel group:** vlna-2

**Implementation Detail:**
Dlaždice: doba, kroky, nálezy auditu podle závažnosti, nové backlog položky.
Jádro: co EPIC dodal lidsky; kde byly problémy a **proč** se staly; co našel
audit; **seznam backlog položek s důvodem vzniku**. Blok 6: mergnout / vrátit /
mergnout s výhradami - s doporučením a důvodem.

**Error Handling:** chybí report auditu nebo kurátora → stránka vznikne a
**pojmenuje, co chybí**; nikdy se netváří, že revize proběhla úplně.

**Edge Cases:**
- EPIC bez nálezů → sekce nálezů se nerenderuje, ne prázdná.
- Curator nezaložil nic → sekce backlogu se nerenderuje (profil to dovoluje).
- EPIC skončil neúspěšně → stránka to říká a rozhodnutí je jiné.

**Dependencies:**
- Depends on: Step 2
- Blocks: none

**Tests:** nová sada `test-epic-summary-page.bats` (t0) — čtyři případy: tři stavy
(s nálezy, bez nálezů, neúplná revize) a **jeden přes skutečnou cestu volajícího**
(`cmd_done_advance` → renderer), protože jednotkový test wrapperu integraci
nedokazuje (kontrakt CP: „every new integration function must have at least one
caller-flow test").

**Acceptance Criteria:**
- [ ] AC10 — stránka jmenuje backlog položky i s důvodem vzniku
- [ ] AC10b — stránka leží na `evidence/<plan_id>/<epic_id>/epic-summary-artifact.html` a je novější než poslední commit EPICu; přesně tohle čte pravidlo z Kroku 6
- [ ] AC11 — chybějící report se pojmenuje, nezamlčí
- [ ] AC12 — stránka vzniká po revizi, ne po posledním kroku, a vyrábí ji `cmd_done_advance`, ne návod

**Effort:** L
**AID Role:** backend

### Step 5: Zbylé dva renderery na profil

**Objective:** stránka uzávěrky a brainstormingu přestanou nést cesty a začnou plnit svůj profil.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-close-summary.sh` — profil, jména místo cest
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-brainstorm-summary.sh` — totéž
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-summary.sh` — deklaruje `artifact_type` (cesty opraveny v v2.91.0, typ ne)
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-brainstorm-summary.bats` — rozšířit o profil
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-close-summary.bats` — rozšířit o profil
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-summary.bats` — rozšířit o `artifact_type`

**Čtvrtý volající je tady, ne mimo plán** (nález Codexu, ověřeno):
`aid-plan-summary.sh:386` volá `aid_artifact_render outcome …` a v původním znění
nebyl v žádném kroku - AC14 přitom rangovalo přes všechny čtyři. Tím se universum
kritéria a deklarovaný rozsah srovnávají.

**Reuse check:** searched: `grep -rln 'links_json' plugins/aid-orchestrator/scripts/lib` → several matching `aid-plan-close-summary.sh` `aid-brainstorm-summary.sh` `aid-plan-summary.sh` — tutéž vadu s cestou místo jména nese každý volající; opravena je zatím jen v `aid-plan-summary.sh` (v2.91.0) a tenhle krok ji dorovnává u zbylých dvou.

**Architecture Context:**
Třída vady, ne tři samostatné chyby: čtyři volající, čtyři kopie téhož omylu.
Po tomhle kroku jsou všichni na profilu a další volající ho zdědí.

**Parallel group:** ---

**Implementation Detail:**
Uzávěrka: dlaždice verze, EPICy, doba od začátku plánu, otevřené položky; jádro
co je venku a co se odložilo kam. Brainstorming: dlaždice varianty, shody, spory,
otevřené neznámé; jádro problém, kritéria, varianty a důvod volby.

**Error Handling:** volající bez profilu → render selže (Krok 2), takže tenhle
krok nemůže zůstat nedodělaný a projít.

**Edge Cases:**
- Brainstorming bez sporů → sekce sporů se nerenderuje.
- Uzávěrka plánu bez odložených položek → totéž.
- Plán vydaný bez EPICů (dokumentační) → dlaždice to říká, ne nula bez kontextu.

**Dependencies:**
- Depends on: Step 2
- Blocks: none

**Tests:** rozšíření existující sady brainstormingu; uzávěrku kryje její vlastní
sada, doplní se o profil.

**Acceptance Criteria:**
- [ ] AC13 — žádný ze čtyř volajících nenese cestu v blocích 5 a 7 (universum: `aid-plan-summary.sh`, `aid-gate-outcome-summary.sh`, `aid-plan-close-summary.sh`, `aid-brainstorm-summary.sh` — čtyři existující volající `aid_artifact_render`; pátý přibývá Krokem 4)
- [ ] AC14 — všech pět volajících deklaruje `artifact_type`; po tomto kroku nezůstává **žádný produkční volající** na přechodné bezetypové větvi z Kroku 2 a test to dokládá
- [ ] AC15 — stropy zůstávají beze změny a jsou to tato čísla ze `aid-artifact-render.sh:123-127`: **5** položek, **3** další kroky, **5** odkazů, **220** znaků na větu, **320** znaků na shrnutí; test renderuje přes všech pět volajících fixture **nad limitem** a dokládá, že se ořízne

**Effort:** M
**AID Role:** backend

### Step 6: Vynucení stránky rozšířit z plánu na milníky

**Objective:** stránka musí vzniknout na konci každého milníku, ne jen u plánu.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/hook-registry.yaml` — pravidlo pokrývá i EPIC a plán jako celek
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-artifact-obligation.sh` — tři milníky místo jednoho
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-artifact-obligation.bats` (tier: t0) — tři milníky, krok bez povinnosti

**Reuse check:** searched: `find plugins/aid-orchestrator/scripts/lib -name 'aid-artifact-obligation.sh'` → one match `plugins/aid-orchestrator/scripts/lib/aid-artifact-obligation.sh` — pravidlo pro plán existuje od v2.89.0; rozšiřuje se o dva milníky, nové pravidlo nevzniká.

**Architecture Context:**
PM rozhodl, že artefakt patří **na konec milníku**: po plánu, po EPICu, po plánu
jako celku. Kroky ani selhání kroku stránku nemají. Tohle je vynucovací polovina
téhož rozhodnutí.

**Parallel group:** ---

**Implementation Detail:**
Pravidlo se aktivuje, když turn dokončil milník a jeho stránka chybí nebo je
starší než zdroj. Zůstává `failure: closed` a tedy vázané na kanárka.

**Error Handling:** nelze určit, jestli milník skončil → pravidlo se neaktivuje
a zapíše to; nikdy neblokuje turn na základě dohadu.

**Edge Cases:**
- Milník skončil neúspěšně → stránka se pořád vyžaduje, jen s jiným obsahem.
- Dva milníky v jednom turnu → vyžadují se obě stránky.
- Vypnuté hooky → registr zaznamená, že pravidlo neběželo.

**Dependencies:**
- Depends on: Steps 3-5 — nemá smysl vyžadovat stránku, kterou volající neumí vyrobit
- Blocks: none

**Tests:** rozšíření existující sady o dva případy (EPIC, plán jako celek).

**Acceptance Criteria:**
- [ ] AC16 — dokončený EPIC bez stránky turn zastaví
- [ ] AC17 — dokončený krok stránku nevyžaduje
- [ ] AC18 — pravidlo bez kanárka neblokuje

**Effort:** M
**AID Role:** backend

**EPIC 2: Steps 7-10 - Release guard podle souborů**

### Step 7: Sdílená knihovna rozsahu vydání

**Objective:** o vydání rozhoduje seznam dotčených souborů, ne nálepka commitu.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-release-scope.sh` — načtení konfigurace, shoda cest, klasifikace commitu, verdikt nad rozsahem
- Modify: `plugins/aid-orchestrator/skills/setup/project-scan.md` — modul, který konfiguraci projektu vlastní: doplní `versioning.release_exempt_paths` a `app_paths`, existující hodnoty **zachová**
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` — směrování na ten modul
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — nový workspace klíče dostane rovnou

**Pozn. (dva nálezy Codexu, oba ověřené):**
1. `plugins/aid-orchestrator/defaults/templates/project.yaml` **neexistuje** —
   v `defaults/templates/` žádný `project.yaml` není. Konfigurace je per-projekt
   `.aid-o/config/project.yaml`, zakládaná autodetekcí (`aid-init.md:179`).
2. `/aid-init` **existující konfiguraci nemění** — dělí se to tak, že init
   zakládá a migruje, kdežto mutace patří `/aid-setup` (`aid-init.md:10-13`).
   Kdyby klíče uměl jen init, každý **už existující** projekt - včetně tohohle -
   by zůstal navždy na fail-open nálepkové větvi.
3. Vlastníkem konfigurace uvnitř `/aid-setup` **není sám příkaz**, ale modul
   `skills/setup/project-scan.md` (nález Codexu, kolo 3: „the scan module owns
   project.yaml changes"). Proto se mění on - jinak by migrace neměla producenta
   a AC21c by se opíralo o cestu, kterou nikdo nepíše. Dva producenti, dva testy:
   čerstvý init a existující projekt bez obou klíčů.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-release-scope.bats` (tier: t1) — exempt-only, smíšený, patička, fail-open

**Reuse check:** searched: `grep -rln '_aid_in_scope' plugins/aid-orchestrator/defaults/hooks` → one match `plugins/aid-orchestrator/defaults/hooks/pre-commit` — shoda cesty se seznamem už v pre-commit hooku je a její tvar se přebírá; nová sémantika shody se nevymýšlí.

**Architecture Context:**
Knihovna je jediná autorita nad otázkou „vyžaduje tenhle rozsah vydání?".
Hook i `aid-release.sh` ji budou konzumovat, takže dnešní duplicita logiky
(`pre-push:86-91` a `aid-release.sh:122-147`) zaniká.

**Parallel group:** vlna-1

**Implementation Detail:**
Rozhoduje **agregátní diff** přes celý rozsah (`START..SHA`), ne per-commit -
tím je odolný proti mergům i revertům. **`START` je poslední verzovací tag**
(`git describe --tags --abbrev=0`), tedy ověřitelný stav vydání; není-li žádný,
je to kořen historie. **Nálepka `release:` hranici neurčuje** (nález Codexu,
kolo 2): kdokoliv může napsat commit s předmětem `release:` po aplikační změně
a tím ji z rozsahu odříznout - guard postavený na nálepce by ho pustil, což je
přesně ta vada, kvůli které se od nálepek odchází. Nálepka slouží dál jen
k přiřazení viny a k varování. Všechno v `release_exempt_paths` → projde.
Nálepka slouží jen k přiřazení viny a k varování, kdy `chore:` sahá na
`app_paths`. Patička `No-Release: <důvod>` vyjímá commit; kontroluje se neprázdnost, hodnota
je auditovatelnost. **Pořadí je určené a platí stejně v knihovně, v kopii v hooku
i v `aid-release.sh`** (nález Codexu — původní znění dovolovalo dvojí čtení):
1. z rozsahu `START..SHA` se vypíšou commity a **odeberou** se ty s patičkou `No-Release:`,
2. nad **zbylými** commity se udělá **sjednocení dotčených cest** —
   `git show --name-only --no-renames --first-parent -m <sha>` pro každý z nich,
   sečteno do jedné množiny,
3. nad tou množinou se rozhoduje podle `release_exempt_paths` a `app_paths`.

**Proč sjednocení cest a ne diff** (nález Codexu, kolo 3): po vyjmutí commitů už
zbytek není souvislý rozsah a `git diff` pro něj neexistuje; „agregátní diff"
by dvě implementace spočítaly různě. Sjednocení cest je jednoznačné a v každé
ze tří kopií vyjde stejně. Důsledky, které tím vědomě přijímáme a testujeme:
**revert** je normální commit a svoje cesty do množiny přidá (změna a její
vrácení tedy vydání pořád vyžadují — konzervativní směr); **merge** se hodnotí
po první větvi, takže se nezapočítají cesty, které do rozsahu přišly odjinud;
**překryv** vyjmutých a nevyjmutých commitů nad toutéž cestou vychází ve
prospěch nevyjmutého, protože cesta v množině je.
Důsledek, který je tím vědomě přijatý: commit s patičkou, který sáhne na aplikaci,
projde — patička je výslovné rozhodnutí člověka a zapíše se do varování, aby byla
dohledatelná. Testová matice Kroku 7 tyhle případy pokrývá jmenovitě: patička nad
aplikační cestou, smíšený rozsah, merge, revert.
**Bez `versioning.source`** - ve WANu je ta sekce prázdná záměrně a její
vyplnění by zablokovalo commity na main (IMP-595).

**Error Handling:** chybí `yq` nebo konfigurace → **fail-open na dnešní chování
podle nálepky** plus jeden řádek s hintem; žádný projekt se změnou nerozbije.

**Edge Cases:**
- Repozitář bez tagu → projde (zděděné chování, zdokumentovat).
- Lokální nepushnutý tag zúží rozsah → zděděné, zdokumentovat.
- Merge commit → `git show --name-only` u čistého merge nevypíše nic; proto agregát.

**Dependencies:**
- Depends on: none
- Blocks: Steps 8-9

**Tests:** nová sada `test-release-scope.bats` — **tier t1**, protože zakládá
dočasné git repozitáře s commity a tagy; měřeno v t0 by rozpočet neuneslo.

**Acceptance Criteria:**
- [ ] AC19 — push, kde jsou všechny změny v exempt cestách, projde
- [ ] AC20 — smíšený push vyžaduje vydání
- [ ] AC21 — bez `yq` se knihovna chová jako dnešní nálepková logika
- [ ] AC21b — podvržený `release:` commit po aplikační změně rozsah **nezúží**: push je stále odmítnut
- [ ] AC21c — už inicializovaný projekt, kterému oba klíče chybí, spadne do fail-open větve a řekne, jak je doplnit

**Effort:** L
**AID Role:** backend

### Step 8: Hook a jeho kopie

**Objective:** pre-push hook používá tutéž logiku a nikdy se od knihovny nerozejde.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-push` — vestavěná kopie funkcí mezi markery
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — sekce o pre-push
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-release-scope.bats` — rozšířit o „kopie == knihovna"

**Reuse check:** searched: `grep -rln 'AID-ORCHESTRATOR-PREPUSH-START' plugins/aid-orchestrator/defaults/hooks` → one match `plugins/aid-orchestrator/defaults/hooks/pre-push` — hook i jeho markery existují; mění se tělo mezi nimi.

**Architecture Context:**
Hook nemůže sourcovat plugin cache (běží v cizím repozitáři), takže funkce v něm
žijí jako kopie. **Dvě autority, které se můžou rozejít** - přesně ta třída, na
kterou v tomhle repu doplácíme opakovaně. Proto se test „kopie == knihovna"
píše jako první, ne poslední.

**Parallel group:** ---

**Implementation Detail:**
`plan/*` a `task/*` refy zůstávají vyjmuté (P068). Odmítnutí vypíše dnešní
hlášku plus rozpis viníků a hint na patičku `No-Release:`. Varování (`chore:`
sahá na aplikaci, zbytek po konfliktním merge) jdou na stderr a **neblokují**.

**Error Handling:** nečitelná konfigurace → fail-open jako v Kroku 7.

**Edge Cases:**
- Push víc refů naráz → posuzuje se každý zvlášť.
- `(delete)` ref → přeskočí se.
- Starý SHA (`HEAD~2:x`) → rozsah se odvozuje od něj, ne od HEAD.

**Dependencies:**
- Depends on: Step 7
- Blocks: none

**Tests:** rozšíření sady z Kroku 7 o test shody kopie s knihovnou a o dva
hookové případy, **plus fail-open větev měřená v kopii, ne jen v knihovně**
(čočka L3): projekt bez `yq` potkává fallback právě uvnitř hooku, a to je cesta,
kterou dnes chodí skoro každý konzument.

**Acceptance Criteria:**
- [ ] AC22 — kopie v hooku je shodná s knihovnou (test to hlídá)
- [ ] AC23 — `plan/*` a `task/*` zůstávají vyjmuté
- [ ] AC24 — odmítnutí vypíše, které commity ho způsobily

**Effort:** M
**AID Role:** backend

### Step 9: CI fasáda a odstranění duplicity ve vydávání

**Objective:** varování skončí v CI logu, kde se čtou, a `aid-release.sh` přestane mít vlastní kopii pravidel.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-release-check.sh` — týž verdikt, exit 0, výstup do logu
- Modify: `.github/workflows/ci.yml` — krok, který fasádu v CI opravdu spustí

**Bez CI, které ji volá, je fasáda jen skript** (nález Codexu, ověřeno: žádný
workflow v `.github/workflows/` dnes `aid-release*` nevolá). Cíl kroku je
„varování skončí v logu, kde se čte" — ten se nedá splnit deklarací. Workflow
tohohle repozitáře je zároveň vzor, který konzument okopíruje.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~122-147) — filtr přes knihovnu
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-seal.bats` — rozšířit o exempt fix

**Reuse check:** searched: `grep -rln 'HAS_FEAT' plugins/aid-orchestrator/scripts/aid-release.sh` → one match `plugins/aid-orchestrator/scripts/aid-release.sh` — duplicitní nálepková logika je doložená na tomto místě a nahrazuje se voláním knihovny z Kroku 7.

**Architecture Context:**
„Varování při pushi nikdo nečte" (handoff). CI fasáda je totéž rozhodnutí
vytištěné tam, kde zůstane. `aid-release.sh` musí používat tutéž knihovnu,
jinak by plán mohl projít pushem a přesto si vyžádat bump.

**Parallel group:** vlna-2

**Implementation Detail:**
`aid-release-check.sh` vrací vždy 0 a tiskne verdikt strojově čitelně.
`aid-release.sh auto`: plně exempt rozsah a commity s `No-Release:` neřídí bump;
po odfiltrování nic → „no bump needed" jako dnes. Chování
`_RELEASE_NOBUMP_HOOK` zůstává beze změny.

**Error Handling:** knihovna nedostupná → `aid-release.sh` se chová jako dnes
a řekne to.

**Edge Cases:**
- Všechny commity exempt → žádný bump, ne chyba.
- `feat!` s exempt cestami → stále bez bumpu, ale varování.
- CI bez konfigurace → fasáda vytiskne, že pravidla nejsou nastavená.

**Dependencies:**
- Depends on: Step 7
- Blocks: none

**Tests:** rozšíření existující release sady o dva případy.

**Acceptance Criteria:**
- [ ] AC25 — `aid-release.sh` nemá vlastní kopii nálepkové logiky
- [ ] AC26 — fasáda vrací 0 a tiskne verdikt, a `ci.yml` ji volá (test to tvrdí nad workflow souborem, ne nad skriptem)
- [ ] AC27 — exempt `fix:` neřídí bump

**Effort:** M
**AID Role:** backend

### Step 10: Anti-drift brána nad Dockerfily

**Objective:** seznam „co se dostane k uživateli" nesmí tiše zestárnout proti tomu, co se balí do obrazu.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/gates/release-paths-drift.sh` — kontrola COPY/ADD proti seznamům cest
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-release-paths-drift.bats` (tier: t0) — porušení i soulad nad fixture Dockerfilem

**Reuse check:** searched: `find plugins/aid-orchestrator/scripts/gates -name 'release-paths-drift.sh'` → none — taková brána neexistuje; `scope-check.sh` ve stejném adresáři řeší rozsah commitu, ne obsah obrazu.

**Architecture Context:**
Konfigurace cest je tvrzení o tom, co se dostane k uživateli. Dockerfile je
druhé tvrzení o tomtéž. Když se rozejdou, guard z Kroku 7 mlčky propustí změnu,
která se nasadí. Brána porovnává obě tvrzení.

**Parallel group:** vlna-2

**Implementation Detail:**
Vytáhne zdroje `COPY`/`ADD` (bez `--from=`) a tvrdí: žádný zdroj neleží celý
v `release_exempt_paths`; každý repozitářový zdroj je pokrytý `app_paths`.
V registru **advisory, dokud ji konzument nezapojí** - je to jeho volba, ne naše.
Řádek v registru to musí říct doslova: v **tomto** repozitáři není brána napojená
na žádný runner, takže její přítomnost není pokrytí (čočka L3; princip
„detektor bez vynucení je dekorace" žádá pojmenovat mechanismus, ne aby každý
detektor blokoval).

**Error Handling:** Dockerfile nečitelný → brána skončí chybou se jménem souboru,
ne tichým průchodem.

**Edge Cases:**
- Vícestupňový build → `--from=` zdroje se ignorují.
- `COPY . .` → posuzuje se celý kontext.
- Projekt bez Dockerfilu → brána se nezapojí.

**Dependencies:**
- Depends on: Step 7
- Blocks: none

**Tests:** nová sada `test-release-paths-drift.bats` (t0) — dva případy nad
fixture Dockerfilem.

**Acceptance Criteria:**
- [ ] AC28 — zdroj ležící celý v exempt cestách bránu shodí
- [ ] AC29 — zdroj mimo `app_paths` bránu shodí
- [ ] AC30 — projekt bez Dockerfilu bránu nespouští

**Effort:** M
**AID Role:** backend

**EPIC 3: Step 11 - Dohledatelnost**

### Step 11: Dokumentace, registr a IMP-517

**Objective:** nová pravidla jsou dohledatelná a nová testová sada nemůže vzniknout bez patra.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádky pro profily, milníkovou povinnost, release scope, **anti-drift bránu** a frontu
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-lint.sh` — IMP-517: sada jmenovaná jen v Testing Strategy
- Modify: `docs/extending-aid.md` — profily artefaktů a rozsah vydání
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` + `CHANGELOG.md` — shodné záznamy

**Reuse check:** searched: `grep -rln 'enforcement_degree' plugins/aid-orchestrator/defaults` → one match `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — pole pro stupeň vynucení zavedl P086 a jen se vyplňuje u nových řádků.

**Architecture Context:**
Poslední článek: co se vynucuje, musí být dohledatelné jinde než v kódu. IMP-517
sem patří, protože je to táž vrstva (lint plánu) a odkládal se právě do chvíle,
kdy se do ní bude sahat.

**Parallel group:** ---

**Implementation Detail:**
Každý nový mechanismus dostane řádek se stupněm vynucení a větou „co
nezaručuje" - **včetně anti-drift brány z Kroku 10** (nález Codexu: Krok 10
řádek vyžaduje, ale registr nebyl v jeho Files ani ve výčtu tady, takže AC37
nemělo z čeho platit). U ní řádek navíc říká, že v tomhle repozitáři není
napojená na žádný runner, takže její přítomnost není pokrytí. IMP-517: lint prohledá `## Testing Strategy` na jména sad, která
nejsou v žádném `Test:` bulletu a v repozitáři neexistují, a vyžádá buď bullet
s patrem, nebo větu, proč sada nevzniká - **poradně**, protože jméno v próze je
slabší signál než deklarovaná cesta.

**Error Handling:** řádek bez `instruction` je nepřípustný; kryje existující
kontrola úplnosti registru.

**Edge Cases:**
- Sada zmíněná v próze i v bulletu → bez nálezu.
- Jméno sady v příkladu uvnitř bloku kódu → nepočítá se.
- Projekt bez pater → IMP-517 se neaktivuje.

**Dependencies:**
- Depends on: Steps 1-10
- Blocks: none

**Tests:** rozšíření existující sady lintu o dva případy k IMP-517; registr
kryje existující kontrola úplnosti.

**Acceptance Criteria:**
- [ ] AC37 — každý nový mechanismus **z tohoto plánu** (profily, milníková povinnost, rozsah vydání, anti-drift brána, pokračování fronty) má řádek se stupněm a větou „co nezaručuje"
- [ ] AC38 — sada jmenovaná jen v próze je nahlášena poradně
- [ ] AC39 — oba CHANGELOGy nesou shodný záznam

**Effort:** M
**AID Role:** docs-writer

## Parallel plan

Rozvrh spočítaný z deklarovaných `Files:` a `Depends on:`, ověřený
`aid-plan-parallel-check.sh`.

| Vlna | Kroky |
|---|---|
| 1 | 1, 7 |
| 2 | 2, 8, 9, 10 |
| 3 | 3, 4, 5 |
| 4 | 6 (sám, `---`) |
| 5 | 11 (sám, `---`) |

**Opraveno po CP1-deep (čočka L2).** Původní rozvrh měl ve vlně 3 kroky
3, 4, 5, 6 a 13 - tedy Krok 6, který podle vlastní deklarace závisí na Krocích
3-5, a Krok 13, který závisí na Krocích 1-12, souběžně s prací, na které stojí.
`aid-plan-parallel-check.sh` to ohlásil jako PASS a nemýlil se: dokazuje jednu
vlastnost, totiž že dva kroky ve vlně nesdílejí soubor ani deklarované rozhraní
(`aid-plan-parallel-check.sh:170`). Deklaraci `Depends on:` nečte vůbec, takže
tuhle třídu chyby vidět nemůže - zapsáno jako **IMP-520**.

EPIC 1 a EPIC 2 jsou na sobě nezávislé - proto je v prvních vlnách kus z obou.
Uvnitř EPICu drží pořadí závislosti: znění → renderer → volající → vynucení;
knihovna → hook → fasáda. Krok 11 uzavírá oba.

## Testing Strategy

**Co se ověřuje a proč:** profily artefaktů (nový kontrakt, který bude platit
pro všechny stránky), stránka bran a stránka EPICu (dva referenční případy, na
kterých se pozná, jestli profil stačí), rozsah vydání (rozhodovací logika, kde
se dnes chybuje třikrát denně) a anti-drift brána.

**Co se neověřuje novými testy:** znění standardu (Krok 1 je dokument, soulad
kódu s ním hlídá Krok 2), registr a dokumentace (Krok 11 — kryjí existující
kontroly úplnosti).

**Patra:** všechny nové sady `t0` kromě `test-release-scope.bats`, která
zakládá dočasné git repozitáře s commity a tagy — ta je **`t1`** a je to jediná
sada tohoto plánu, která se na merge cestě projeví časem.
**Nové sady: 4**, **rozšířené: 5**. Jedenáct kroků, devět testových zásahů.

## Risks

| Riziko | P | Dopad | Zmírnění |
|---|---|---|---|
| Profil vynutí pole, které volající neumí naplnit, a zablokuje stránku | **V** | střední | Kroky 3-5 jsou referenční případy; co v nich chybí, patří zpět do profilu, ne do výjimky |
| Kopie funkcí v hooku se rozejde s knihovnou | S | vysoký | test „kopie == knihovna" se píše jako první, ne poslední |
| Krok 1 zůstane nepublikovaný a kontrakt bude platit jen uvnitř AID | **V** | nízký | je to vědomý mezistav; publikace je jmenovaný krok v `## Next Steps` a EPIC 1 nesmí tvrdit, že standard je venku |
| Dva EPICy v jednom plánu | S | nízký | jsou nezávislé a každý jde vydat zvlášť |

## Success Criteria

- [ ] SC1 — stránka, která nenese, co její typ dluží, se nevyrenderuje
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-artifact-profiles.bats"
  expected_exit: 0
```
- [ ] SC2 — push s výhradně exempt cestami projde, smíšený vyžaduje vydání
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-release-scope.bats"
  expected_exit: 0
```

## Next Steps

Implementace po EPICech; každý jde vydat samostatně. **Pokračování fronty
v autonomním režimu řeší P090**, oddělené 2026-08-26 poté, co CP1-deep ukázalo,
že mechanismus, na kterém tady stálo, nedrží.

**Ruční krok po EPICu 1 - publikace standardu: ✅ HOTOVO 2026-08-26.** Znění
z Kroku 1 vzniklo v repozitáři AID (`docs/proposals/artifact-standard-profiles.md`)
a PM ho na svoje rozhodnutí nechal přenést do
`/opt/eco/docs/docs/ecosystem/specs/artifact-standard.md`; docs nasazeny
z commitu `7baaaa3` a stránka ověřena. Kontrakt tím platí pro celý ekosystém,
ne jen uvnitř AID. Ruční to bylo proto, že kontrakt kroku umí ověřit jen
repozitář plánu (doloženo v Kroku 1) - zůstává jako **IMP-519**.
Podpora druhého kořene: **IMP-519**. Kontrola vln proti závislostem: **IMP-520**.
