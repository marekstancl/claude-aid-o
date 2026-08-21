# AID — přepracování plánovacího řetězce (roadmapa)

**Datum:** 2026-08-16
**Autoři:** PM (Marek) + Claude (Opus 5), oponentura měření: Codex
**Typ:** roadmapa / MVP plán — NENÍ executable, nemá P-číslo, neběží přes FSM
**Zdroj:** `.aid-o/work/interim-PLANNING-STACK-REWORK.md` (plný zápis sezení,
rozhodnutí R1–R9, dobrané otázky Q3/Q4/Q5)
**Realizace:** 3 executable plány (níže), každý s vlastní ceremonií a groundingem

> Pravidlo pro navazující plány: před napsáním každého z nich si plánovač
> MUSÍ přečíst aktuální stav kódu, srovnat ho s touto roadmapou a přizpůsobit
> plán realitě — ne roadmapu. Co se mezitím změnilo, se zapíše.

---

## 1. Vize (ZÁVAZNÁ pro všechny tři plány)

Spor návrhu nebo implementace s vizí se neřeší tichým kompromisem — jde PM
jako rozhodnutí ve formátu V7. Každý bod nese zkoušku; bod bez zkoušky do
vize nepatří.

**V0 — Proč.** Plán, podle kterého poběží vývoj, má být lepší, kvalitnější a
cílenější — včetně cílených testů — a přitom rychlejší a levnější: tokeny se
nesmí utápět v opravách a kontrolních kolech, která nic nenajdou. Plán je
jediné místo, ze kterého agent bere pravdu, a jediné, ze kterého PM chápe, co
se bude dít.

**V1 — Cena ceremonie je úměrná dosahu změny, ne délce textu.**
Zařazení plánu se určuje z deklarovaného seznamu `Files:`, ne z prózy.
*Zkouška:* rozdělení rizika na živých plánech přestane být „skoro vše high";
plán typu „srovnej texty nápovědy" neaktivuje CP1-deep ani C0.

**V2 — Nic se nevymýšlí, co už existuje.**
Před návrhem nové komponenty/dialogu/skriptu/helperu se doloží, že v kódu
není stejná nebo podobná věc; když je, použije se nebo rozšíří. Platí i pro
kontrolory.
*Zkouška:* každý krok zakládající NOVOU věc nese doložený výsledek hledání
(kde se hledalo, co se našlo, proč to nestačí). Bez toho krok neprojde.

**V3 — Standardy ano, ale ne slepě.**
Váže-li se na oblast standard z `/ecosystem/specs/`, plán ho jmenuje a řídí
se jím; nevá­že-li se, neuvádí se nic. Ve standardu může být šotek — odchýlit
se smíme, nikdy mlčky: odchylka nese důvod a je podnětem k opravě standardu.
*Zkouška:* plán o testech jmenuje `test-standard`, o stránce pro PM
`artifact-standard`, o nápovědě `help-authoring-standard`; plán bez vazby
sekci nemá; odchylka bez důvodu neprojde.

**V4 — Testy se navrhují, ne odpočítávají.**
Plán rozhoduje, jaké chování ověřit a ve kterém patře (T0/T1/T2), podle
měřené ceny a dosahu. Povinnost „ke každému kroku jeden test" končí.
Nejlevnější a nejvítanější pohyb je přidat případ do existující sady.
*Zkouška:* počet testů přestane růst lineárně s počtem kroků; merge cesta
zůstane v rozpočtu (T0 < 2 min, T1 < 10 min).

**V5 — Souběh je vlastnost návrhu — a cílem je co nejvíc souběhu.**
Plán dopředu deklaruje, které kroky sahají na oddělené soubory a smí běžet
souběžně. `max_parallel: 1` je brzda, ne cíl: padne, až bude bezpečnost
doložená, a plány na to budou připravené beze změny.
*Zkouška:* každý krok má skupinu souběhu (nebo `---`); dva kroky ve stejné
skupině nemají průnik v `Files:`; ověřuje stroj. Konečná zkouška: zvednutí
`max_parallel` nevyžaduje přepsání plánů.

**V6 — Plán je pro agenta, artefakt pro člověka.**
Z plánu ven vše psané pro lidské čtení; pro PM se renderuje artefakt se
stropy vynucenými v kódu.
*Zkouška:* plán se zmenší a žádná informace, kterou agent při dispatchi
dostává, se neztratí; artefakt drží stropy ekosystémové kostry.

**V7 — Každé rozhodnutí: shrnutí, možnosti, doporučení, proč — VYNUCENĚ.**
Turn žádající rozhodnutí bez možností se odmítne, ne pokárá. Psáno lidsky;
technické identifikátory (cesty, hashe, čísla řádků) jsou na vyžádání a pro
agenty, ne pro PM.
*Zkouška:* karta se skládá z dat deterministickým rendererem; chybějící
možnosti = chyba renderu; v kartě není technický identifikátor, který PM
k rozhodnutí nepotřebuje.

**V8 — Návrh vzniká sporem dvou modelů, ne monologem jednoho.**
Brainstorming vede hlavní agent, oponuje mu model z jiné platformy (dnes
Codex — volba modelu je nastavení, ne architektura). Shoda se sepíše bez
ptaní; rozpor jde PM podle V7. Oponent není razítko — hledá, kde se hlavní
agent mýlí.
*Zkouška:* doložitelné, které závěry byly shodné a které sporné; PM viděl
jen sporné.

**V9 — Detektor bez vynucení je dekorace.** (AID-v3 princip #1)
Každá nová kontrola má už při návrhu pojmenovaný mechanismus vynucení (FSM
předpoklad / tvrdý pád mimo běh / potvrzení PM).
*Zkouška:* každá nová schopnost je v enforcement registry s typem, zdrojem,
závažností a povrchem.

**V10 — Proudy se neperou o strom.**
Víc plánů a brainstormingů běží současně, každý ve své pracovní kopii.
*Zkouška:* dva brainstormingy a dvě generování naráz skončí bez zásahu do PM
checkoutu a bez vzájemného přepisu.

**V11 — Nejmenší věc, která to splní.**
Agenti systematicky overgenerují — vrstva navíc, nový soubor místo rozšíření,
nechtěná konfigurovatelnost. Plán je místo, kde se to zastaví. Platí i na
plán samotný: dlouhý plán není lepší plán.
*Zkouška:* krok zakládající nový soubor/abstrakci nese důvod, proč nestačilo
rozšířit existující; slučitelné kroky jsou sloučené; reviewer smí vrstvu
navíc zamítnout jako nález, ne jako názor.

**V12 — Práce není hotová, dokud o ní neví nápověda a dokumentace.**
Plán měnící chování dodává konkrétní instrukce pro nápovědu klientského
projektu (existuje-li) a interní dokumentaci v Docusaurus (existuje-li) —
soubor, sekce, obsah. Snímky obrazovky mají uvedený funkční postup generování.
Co projekt má (nápověda? Docusaurus? nástroj na snímky?) zjišťuje
`/aid-init`/`/aid-setup`, plán se na výsledek odkazuje.
*Zkouška:* plán měnící uživatelské chování má krok s konkrétní cestou do
nápovědy i dokumentace (nebo doloží, že projekt ani jedno nemá); postup na
snímky jde spustit, jak je napsaný.

**V13 — Kontroly kontrolují to, co plán definuje — po generování i za vývoje.**
Všech šest kontrolních bodů (CP1–CP6) a pět vrstev (C0–C4) se srovná s novým
kontraktem plánu; jinak kontrolují včerejší pravidla.
*Zkouška:* každý nový povinný prvek plánu má pojmenované místo, které ho
kontroluje po generování, a místo za běhu (nebo zapsaný důvod, proč druhé
není potřeba). Prvek bez obojího je dekorace (V9).

**Co vize NEslibuje:** okamžité zapnutí souběžného běhu agentů (brzda padne
až po doložení bezpečnosti); vlastní webovou aplikaci pro artefakty (teď se
generuje stránka do dnešní kostry); že AID přestane psát dlouhé dokumenty —
jen je nebude psát pro člověka.

---

## 2. Měření, o které se roadmapa opírá (2026-08-14)

Šest živých plánů (P073, P074, P076, P079, P080, P083); oponentura měření:
dva nezávislé běhy Codexu. Plný zápis včetně oprav vlastního měření
v interim §5a. Co rozhodlo:

| Zjištění | Číslo | Důsledek |
|---|---|---|
| Test položek ≈ počet kroků, plán co plán | 10–21 Test na 10–19 kroků, 6/6 plánů | testy vznikají z povinnosti, ne z potřeby → V4 |
| Prakticky každý plán je high-risk | zásahy vzorů 5–33; P080 („texty nápovědy") 13, první zásah = odkaz v hlavičce | klasifikace z prózy je rozbitá → nejdřív oprava klasifikace, pak odstupňování |
| Ceremonie u velkého plánu má hodnotu | P080: **18** skutečných vad zachyceno před implementací (adjudicator `resolution_verification`) | kola se odstupňují, NERUŠÍ |
| Ceremonie u malého plánu je ztráta | P079: 1 nález, 0 přijato, ~9 min; P076: 3 nálezy, 0 přijato, ~32 min | plná ceremonie jen pro velký dosah |
| Náklad kol nedělá čtení, ale zamítnuté nálezy | P080: 8 zamítnutých blokátorů; P083: 3 kola, 0 přijatých | experiment Q7 míří na nálezy bez důkazu |
| `reuse_compat` lens už umí najít duplicity | P080 nález AB-2 („plán zná 4 kopie, reálně 6 v 5 souborech") | V2 = rozšíření existujícího, ne nový mechanismus |
| Žádnou povinnost nelze obhájit jako univerzální | chybí kontrafaktuál (co by uteklo bez ní) | povinnosti se odstupňují A DÁL MĚŘÍ, neruší natvrdo |

**Čísla, která se dnes nesbírají a plán 1 jejich sběr zavádí:** přijaté
nálezy per vrstva; escape rate (vady prošlé do implementace); kolik povinných
testů kdy spadlo na skutečné regresi; kolik completeness gate + linty reálně
zastavily (dnes 0 doložených záznamů).

---

## 2a. Průřezová pravidla pro P1–P3 (z oponentury Codexu, 2026-08-16)

1. **Registrace vynucení (V9):** každá nová kontrola, lint, povinné pole či
   dispatch guard z P1–P3 se při implementaci zapíše do
   `defaults/enforcement-registry.yaml` s typem / zdrojem / závažností /
   povrchem. Plán, který zavádí kontrolu bez záznamu, neprojde CP1.
2. **Dvojí kontrolní místo (V13):** každý nový povinný prvek plánu (pole
   znovupoužití, vazba na standard, instrukce nápovědy, skupina souběhu,
   karta rozhodnutí…) jmenuje už v textu svého plánu, KDO ho kontroluje po
   generování a KDO za běhu vývoje — nebo zapíše důvod, proč druhé není
   potřeba.
3. **Operacionalizace V11:** P1 přidá do plan-writing kontraktu pravidla
   minimality (nový soubor/abstrakce jen s důvodem; slučitelné kroky
   sloučené) a do kontraktu posudků právo zamítnout vrstvu navíc jako
   nález. Bez tohoto by V11 zůstalo přáním.

## 3. Plán 1 — Cílenost a riziko (ubírá)

**Cíl:** ceremonie a povinnosti úměrné dosahu; klasifikace ze skutečnosti.

Rozsah:
1. **Riziko z `Files:`, ne z prózy** (IMP-499) — `aid-cp1-gate.sh` scanuje
   deklarovaný seznam souborů. Teprve pak odstupňování: plná ceremonie
   (FSM/brány/release) → střední (testy, konfigurace) → lehká (texty).
2. **Odstupňování povinností** (IMP-500) — z měření §2: co je univerzální
   (Files, kritéria), co podle dosahu (Test položky, C0 kolo, počet posudků),
   co letí. **Revize celku:** každá stávající sekce šablony a povinnost
   skillu si obhájí místo, jinak letí (rozhodnutí PM u Q5). Pravidlo sporu
   s §2 („odstupňovat, nerušit natvrdo"): default je odstupňovat + dál měřit;
   ÚPLNÉ odstranění povinnosti jde per položka PM ke schválení (V7) — týká se
   hlavně sekcí psaných pro člověka, které nahrazuje artefakt.
3. **Testy podle V4** — Test položka jen tam, kde plán ověřuje chování;
   patra podle `test-standard`; přidání do existující sady jako preferovaný
   pohyb; zdůvodnění u t2.
4. **Lidské sekce ven, artefakt dovnitř** (Q5/A) — kritérium řezu:
   konzumuje to dispatch? Stakeholder Brief a human summary bloky se
   nerenderují do plánu, ale artefaktem (`aid-artifact-render.sh`, nový
   volající). Lint drží hranici zpět.
5. **Srovnání kontrolorů** (V13) — všech 7 plan-time míst (Completeness
   Gate, plan-lint, generation-readiness, C0 kontrakt, CP1 gate + deep,
   test-tier-lint, plan-diff) zná nový kontrakt. K tomu **inventura dopadů
   na runtime kontrolní body** (CP2–CP6, C1–C4): P1 sepíše, které z nich
   čtou pole plánu, jež P1 mění, a srovná je; prvky přidávané v P2/P3 si
   runtime kontrolu přinesou samy (viz Průřezová pravidla).
6. **Sběr chybějících čísel** (§2 dole) — aby příští revize měla data.
   Navíc cena plánovacího řetězce per plán (tokeny + čas psaní/posudků
   před a po změně) — jediný přímý důkaz V0.
7. **Experiment Q7 (NEROZHODNUTO, zadání):** na jednom živém plánu porovnat
   varianty kontroly A (rozřezat) / B (víc průchodů) / C (mapovací průchod +
   cílený s povinným důkazem). Metriky: nálezy celkem, přijaté, kola oprav;
   kontrolní údaj: najde-li varianta nález typu AB-2 (viditelný jen přes
   celek). Vítěz se zadrátuje až PO experimentu.

**Neudělá:** nové povinnosti (to je plán 2), změny brainstormingu (plán 3).

## 4. Plán 2 — Podklady (přidává)

**Cíl:** plán vychází ze skutečného kódu, standardů a deklaruje souběh.

Rozsah:
1. **Znovupoužití** (Q3/C): pole doloženého hledání jen u kroků zakládajících
   novou věc (lint: příkaz + výstup, ne próza); hledání už v brainstormingu;
   `reuse_compat` lens přeorientovaná na posouzení doložení; čtyři výsledky
   hledání (nic / jeden vzor / víc shodných → kanonický + důvod / bordel).
   **Bordel:** sjednotit hned, když je uvnitř `Files:` plánu A sjednocení
   nezvětší krok nad rámec jeho odhadu (V11 pojistka proti vnucenému
   refaktoru); jinak backlog s konkrétním seznamem míst; hraniční případ
   → PM (V7).
   **Pojistka: plán nikdy nepřidá N+1. variantu.** (Důkaz nutnosti: 9 ležících
   dedup položek z E-047 v backlogu.)
2. **Standardy** (Q4/B+PM): mapa oblastí → standardů žije JEN v Docusaurus
   (živá stránka, založí se v rámci plánu), AID drží odkaz a čte aktuální
   stav. Lint vynucuje minimum z mapy proti `Files:`; model smí přibrat víc.
   C0/CP1 dostávají odkaz do dispatche. **Mapa je index, ne pravidla:**
   při rozporu mapy se standardem platí standard a rozpor se hlásí jako
   podnět k opravě mapy (analogie V3 pro šotka). `/aid-init`/`/aid-setup`
   se ptá: „máte standardy a kde?" — projekt bez nich povinnost nemá.
3. **Nápověda + dokumentace + snímky** (V12): konkrétní instrukce v plánu;
   zjišťování vybavení projektu v init/setup; funkční postup na snímky
   (`lib/ui-fidelity/ui-capture.mjs` jako základ, doinstalace popsaná).
4. **Deklarace souběhu** (V5): skupiny souběhu u kroků; strojová kontrola
   disjunktnosti `Files:`; při `max_parallel: 1` dokumentace a příprava.
   (Q6 detail — co přesně se s deklarací děje za brzdy — rozhodne plán 2.)

## 5. Plán 3 — Dva agenti a komunikace (mění, kdo to plní)

**Cíl:** brainstorming jako spor dvou modelů; výstupy pro PM vynuceně lidské.

Rozsah:
1. **Codex oponent** (V8, IMP-086, deep-mode konsensus K1–K3): jeden flow,
   profil intenzity; oponent dostává totéž zadání; shoda se sepíše, rozpor
   jde PM podle V7; doložitelnost shody/sporu. Stavební kameny existují:
   `aid-audit-independence.sh` (ověření Codexu), C0 codex dispatch,
   pracovní vzor invokace (stdin + `-o`).
2. **Vize jako krok brainstormingu** (R6/R7): z prvních podnětů, forma
   teze + zkouška, PM schvaluje; povinná u roadmap a děleného díla,
   vynechaná u krátkého plánu. Schválení vize PM je vědomá výjimka z V8
   („shoda se sepíše bez ptaní") — vizi schvaluje PM vždy, i když se na ní
   oba modely shodnou; tak to R6 určuje.
3. **Artefaktový výstup brainstormingu** (V6): stránka místo prózy;
   run-scoped artefakty (`work/brainstorm/{run_id}/`, konsensus K3),
   atomická promoce po schválení.
4. **Vynucená karta rozhodnutí** (V7, IMP-495): deterministický renderer
   karty; turn bez možností se odmítá; lidský jazyk, technika na vyžádání.
5. **Pracovní kopie pro brainstorming a generování** (V10): dnes má worktree
   jen implementace; rozšířit na generování a brainstorm. Souvisí IMP-497
   (nastavení bran z hlavního stromu vs. kód z větve) — vyřešit spolu.
6. **Hooková vrstva AID** (IMP-509) — PRVNÍ položka P3, jinak vznikne deset
   různých skriptů. Jeden vstupní bod `scripts/aid-hook.sh <event>`
   deklarovaný v `hooks/hooks.json`; kontext z JSON na stdin (`cwd`,
   `agent_type`, `session_id`); pravidla v `defaults/hook-registry.yaml`.
   Povinné: fail-open default, časový rozpočet, deklarované vlastnictví
   (controller / subagent / obojí — plugin hooky běží I v subagentech),
   escape hatch `AID_HOOKS_OFF=1` s auditem, zápis do enforcement registry
   (V9), pravidlo testovatelné z fixtures bez živé session.

   **ZÁVAZNÝ POŽADAVEK — znovupoužitelnost (V2, V11).** Vrstva se navrhuje
   jako mechanismus pro celý AID, ne jako obsluha karty rozhodnutí. Přidání
   dalšího chování NESMÍ znamenat nový skript ani nový záznam v
   `hooks/hooks.json` — znamená **řádek v `hook-registry.yaml` plus fixture**.
   *Zkouška (ověřuje se na druhém a třetím spotřebiteli, ne na prvním):*
   body 7 a 8 níže se implementují BEZ jediné změny v `aid-hook.sh`; kdyby si
   kterýkoli z nich vynutil zásah do vstupního bodu, je vrstva navržená špatně
   a přepracuje se, ne obchází. Druhá zkouška: pravidlo pro událost, kterou
   AID dnes nepoužívá (např. `PostToolUse`), se dá přidat jen zápisem do
   registru a doplněním deklarace události.

   **Vstup pro návrh:** analýza sedmi tříd použití napříč AIDem
   (`docs/plans/2026-06-29-BACKLOG.md`, sekce „Analýza: kde jinde v AID mají
   hooky přidanou hodnotu") — doručení protokolu subagentovi, kontrola výstupu
   agenta, zákaz akce v daném stavu, kontinuita kontextu, konec turnu,
   životní cyklus prostředí, telemetrie. Vrstva musí unést všech sedm, i když
   se v P3 postaví jen tři. **Součástí implementace je revize 92 aktivních
   vnitřních strážců:** které z nich jsou po zavedení hooku redundantní (V11 —
   cílem je i úbytek kontrol, nejen přírůstek).
7. **Kontinuita přes kompakci** (IMP-510): `PreCompact` uloží kapsli
   (komunikační kontrakt, FSM stav, další povolený krok, cesty k artefaktům),
   `SessionStart` s matcherem `compact|resume|fork` ji vloží zpět. Stav se
   čte relativně k worktree, ne z hlavního stromu.
8. **Vynucení karty rozhodnutí** (IMP-511, vynucovací polovina IMP-495):
   `Stop` hook odmítne turn, který žádá rozhodnutí bez možností / doporučení /
   důvodu — exit 2 + konkrétní důvod. **Podmínka pořadí:** až PO rendereru
   karty z bodu 4; hook validuje strojově čitelný artefakt, NIKDY volnou prózu
   transcriptu (jinak falešná zamítnutí a smyčka). Fail-closed → escape hatch
   povinný. Do stejného pravidla patří i tři pravidla převzatá z i-have-adhd
   skillu: stav („krok N z M") každý turn, konkrétní časový odhad, strop
   5 položek v chatu.

**Ověřeno 2026-08-16** (dokumentace Claude Code): `Stop` hook umí zabránit
ukončení turnu a vrátit modelu důvod (exit 2 nebo `decision: block` +
`reason`); `SessionStart`/`UserPromptSubmit` vkládají stdout do kontextu;
plugin deklaruje hooky v `hooks/hooks.json` a **hooky pluginu běží i uvnitř
subagentů**. Zbytek hookových příležitostí mimo tuto roadmapu je v backlogu
jako IMP-509..516.

## 6. Session prompty

Každý plán se píše příkazem `/aid-plan write` nad touto roadmapou, v novém
okně, postupně (P1 → P2 → P3). Závazná hlavička každého promptu:

> Nejdřív grounding: přečti aktuální stav kódu a skillů, srovnej s roadmapou
> `docs/plans/AID-planning-stack-rework-roadmap.md` a s interim
> `.aid-o/work/interim-PLANNING-STACK-REWORK.md`; co se rozchází, přizpůsob
> realitě a rozdíl zapiš. Vize (§1) je závazná — spor jde PM podle V7.

- **P1:** `/aid-plan write docs/plans/AID-planning-stack-rework-roadmap.md — Plán 1: cílenost a riziko`
  Kontext: §3; měření §2; IMP-499/500; Q5 dodatek (revize celku); experiment Q7 jako měřený krok.
- **P2:** `/aid-plan write docs/plans/AID-planning-stack-rework-roadmap.md — Plán 2: podklady`
  Kontext: §4; rozhodnutí Q3/Q4 v interim §7; V12; 9 dedup položek E-047 jako testovací materiál.
- **P3:** `/aid-plan write docs/plans/AID-planning-stack-rework-roadmap.md — Plán 3: dva agenti a komunikace`
  Kontext: §5; deep-mode konsensus (LOCKED) `docs/plans/AID-BRAINSTORM-deep-mode-review.md`;
  IMP-086; IMP-495; IMP-497; communication.md (čtyři karty) jako výchozí stav.

---

**Backlog položky, které tato roadmapa pokrývá:** IMP-499, IMP-500, IMP-495,
IMP-503 (částečně — artefaktová stránka), IMP-086, IMP-497 (v P3), plus dvě
nové věci bez ID (znovupoužití, mapa standardů). Při zahájení každého plánu
se dotčené položky označí v backlogu jako scheduled.
