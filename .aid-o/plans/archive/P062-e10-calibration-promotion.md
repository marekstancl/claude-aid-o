---
id: P062
type: plan
status: cancelled
closed: 2026-08-29
closure: "PM 2026-08-29: E10 se dělat nebude, E11 také ne. Měřicí nástroje z v2.95.0 odstraněny (v2.95.3). Téma kontrol se řeší mimo tento plán, po částech."
created: 2026-07-12
author: PM + AI
phase_of: AID Control System v2 (roadmap E10 — Kalibrace + dual-run metriky + speed + promotion decision table)
roadmap_ref: docs/plans/AID-control-system-v2-roadmap.md
design_ref: docs/AID-control-system-v2-unified-refactor-PLAN.md (master §10 E10 + §11-12)
brief_ref: .aid-o/work/interim-P062.md (PM 11-bodový scope-extension brief, 2026-07-12)
depends_on: "TVRDÉ preconditions (§Preconditions, přepsané re-groundem 2026-08-14). P061 je UZAVŘENÝ (2026-08-14, E1-E5 dodané mimo D5, které je odloženo jako IMP-506) — tím padá původní zámek. Zbývající tvrdé podmínky jsou IMP-179, IMP-201 a rozpočet merge cesty; viz §Re-grounding."
risk: high
write_only_until: "ZRUŠENO 2026-08-15. P061 padl 2026-08-14; poslední brána startu je PM revize re-groundu + lint/CP1/nezávislé ověření (§Preconditions A). IMP-179, IMP-201 a bookkeeping NEJSOU brány startu — vyrábí je EPIC 1 — jsou to brány promotion (§Preconditions B)."
regrounded: 2026-08-14
regrounding_method: "dva nezávislé průchody (controller + Codex nad stejným faktickým podkladem), sloučené; body, které měřil jen jeden z nich, jsou označené"
---

# Plan: E10 — Kalibrace, dual-run metriky, rychlost a datově podložená promotion rozhodnutí

## Re-grounding — čti první, přebíjí vše starší

> **Dva průchody, druhý je poslední (PM 2026-08-15: „uděláme jeden a poslední").**
> **14. 8.** se srovnala rozhodnutí, podmínky a dvě kritéria, která procházela
> naprázdno. **15. 8.** se dodělalo všechno, co první průchod vědomě nechal
> otevřené: zbývajících deset přejímacích kritérií, zastaralé měřicí jednotky
> uvnitř kroků 5 a 9, spotřebované číslo verze v kroku 11, otevřená vidlička
> v kroku 2 a zrušení zámku write-only. **Po tomhle průchodu už v tomhle plánu
> není nic, co by čekalo na další re-ground.** Zbývá lint, CP1/C0, nezávislé
> ověření a generování EPICů.
>
> Průchod z 14. 8. vznikl ze dvou nezávislých čtení (controller + Codex) nad
> stejným faktickým podkladem; u nálezů, které měl jen jeden z nich, je to
> napsané u nich.

Plán je z 12. 7. Od té doby přibylo třicet vydání a **zmizel celý subsystém,
o který se opíral**. Tahle sekce je autoritativní; kde se rozchází se zbytkem
dokumentu, platí ona. Vznikla dvěma nezávislými průchody nad stejným faktickým
podkladem — controllerovým a Codexovým — a je jejich sloučením. U bodů, které
našel jen jeden z nich, je to napsané.

### Co bylo změřeno, ne dovozeno

| | |
|---|---|
| Verze repozitáře | v2.86.1; plán míří na v2.56.0 |
| Tag `v2.56.0` | **existuje** a patří dávnému nesouvisejícímu vydání |
| Ze čtyř skriptů, které plán vytváří | neexistuje **žádný** |
| Z pěti sad, které jmenují AC | existuje **jedna** (`test-release-policy.bats`) |
| C4 content-verdict | v `aid-release-policy.sh` **není**, jak plán sám říká |
| Skutečné dispatche C3 | **13** záznamů `c3-dispatch.json`, 22 `codex-last-message.json` |
| Verdikty C3 v evidenci | **21 unverifiable, 5 fail, 2 pass** (28 celkem) |
| Merge cesta | 72 sad, **18 min 07 s** proti rozpočtu 10 min |
| Plný portfolio běh | 234 sad, ~7 h, patří nočnímu běhu |

### A — co je dnes nepravdivé nebo projde naprázdno

1. **Precondition 1 je nepravdivá už ve své formulaci.** Žádá šest mergnutých
   EPICů P061 a `grep -c 'E-061-[1-6]_6' == 6`. D1 plánu P061 vždycky říkal
   E1-E5 povinné, E6 backlog; P068 amendment navíc počítání EPIC-vydání zrušil.
   **Nahradit** trvalým uzavíracím záznamem P061 + výslovnou výjimkou IMP-506.
2. **AC11 projde naprázdno.** `grep '## [2.56.0]' CHANGELOG.md` je **dnes
   pravda** — z historie. Ta půlka AC je splnitelná bez jediného řádku E10.
   Druhá půlka (`plugin.json == 2.56.0`) je naopak nesplnitelná bez zpětného
   kroku. **Nahradit** politikou: E10 dostane nově alokované vydání a AC ověří,
   že v NĚM vznikl vlastní CHANGELOG a registry záznam.
3. **AC12 projde naprázdno.** Měřeno: nula smazání od `v2.55.0`. Je to pravda
   dnes, kdy z E10 neexistuje nic — takže to nedokazuje, že E10 legacy zachoval.
   Navíc to visí na 31 vydání starém tagu. **Nahradit** kotvou na výchozí commit
   samotného běhu E10.
4. **AC5 a AC10 měří přítomnost řetězce ve skriptu**, ne že se něco změřilo
   nebo rozhodlo. AC1/4/6/7/9 jsou kontroly existence artefaktu — projdou nad
   čistým preflightem stejně jako nad špinavým *(nález Codexova průchodu)*.
5. **AC2/3/8 dokazují jen, že nějaké testy proběhly** (`1..N` + exit 0). AC3
   může projít, i když IMP-201 zůstane provozně nevyřešený; AC8 počítá jména
   testů obsahující slova, ne pět skutečných stavů *(Codex)*.
6. **D2 slibuje důkaz rychlosti risk-profilů, který je pro Fast Mode
   nedosažitelný.** IMP-506: `/aid-do` nespouští žádný AID skript, takže
   nevydává žádné profilové události. E10 nemůže měřit, co neexistuje.

### B — vstupy, které přestaly existovat

7. **D2/D9/AC5/AC9 stojí na P066/P069 scheduleru a paralelismu. P078 to
   odstranil** (v2.82.0), PM celou linku zrušil 9. 8. po naměřeném zrychlení
   3-6 %. **Náhradní vstupy:** testovací patra T0/T1/T2, runtime baseline z
   P063 (`lib/aid-gate-runtime-baseline.sh`) a hranice plan-final z P068 —
   drahé brány se platí jednou za plán, ne jednou za EPIC.
8. **„Full-suite per EPIC" jako měřicí jednotka neplatí.** Jednotky jsou dnes
   tři: merge cesta (T0+T1), plan-final brány, noční portfolio.
9. **D6/AC3 citují červencový stav IMP-201.** Srpnový je horší a konkrétnější:
   *ověřeno reálné, nenaplánované, pending*, latentní jen proto, že
   `release-decision-policy.yaml` je `observe` — **a ožívá přesně ve chvíli,
   kdy E10 přepne na blocking.**

### C — co plán neobsahuje a obsahovat musí

10. **Rozpočtová brána před promotion.** Merge cesta je **81 % nad rozpočtem**
    dřív, než E10 přidalo cokoli. Plán, který má prokázat „nejsme pomalí",
    nesmí tenhle výchozí stav mlčky znormalizovat. Rozhodovací tabulka
    potřebuje šestý výsledek: `cannot-promote — runtime-budget-failed`.
11. **Oddělit přírůstkovou cenu E10 od té výchozí** — jinak si E10 buď přičte
    18 minut, které nezpůsobilo, nebo v nich schová svoje vlastní náklady
    *(Codex)*.
12. **Provenience fixtur místo jejich počtu.** Každá fixtura pojmenuje zdrojový
    incident, třídu selhání, jestli je to positive/negative control, očekávaný
    starý i nový výsledek — a u nedoložených případů se vyloučí s poznámkou,
    nikdy nedomýšlí *(Codex; navazuje na D3)*.
13. **Rozdělit rozhodovací tabulku podle IMP-179.** Kontroly stojící na výstupu
    subagentů (Auditor/Curator/Verifier) jsou nezpůsobilé k blocking promotion,
    dokud je IMP-179 otevřený; nezávisle podložené kontroly se posuzují zvlášť.
14. **Vzít v úvahu, co C3 dnes reálně vydává** *(měřeno controllerem; Codex tenhle
    údaj neměl a správně napsal, že se nedá předpokládat)*. Roadmapová podmínka
    „nenulový `c3_hook_fired`" je **splněná** — třináct skutečných dispatchů
    není nula. Zároveň z toho ale plyne nový problém, který plán nezná:
    **75 % zaznamenaných verdiktů C3 je `unverifiable`** (21 z 28; k tomu 5 fail
    a 2 pass). Kalibrační dataset pro C3 by tedy z velké části tvořilo
    „nedalo se rozhodnout". To není důkaz, že C3 chytá vady — a promotion C3 na
    blocking se o takový dataset nesmí opřít. E10 musí `unverifiable` sledovat
    jako **vlastní metriku**, ne ho počítat mezi ne-fail.
15. **D7 má reálnou práci, ne hypotetickou** *(měřeno controllerem)*: běhy
    `R-E045-1`, `R-E049-1` a `R-E057-2` jsou ve stavu `DONE` a přitom mají kroky
    se stavem `pending`. Přesně ten nepořádek, který D7 odmítá měřit.
16. **Měřicí vstupy, které mezitím vznikly a plán o nich neví:** deník
    naměřených dob (`lib/aid-test-durations.sh`), přiřazení pater
    (`aid-test-tier-assign.sh`), noční záznamy
    `/opt/eco/data/aid-nightly/aid-orchestrator/<datum>.json` a počítadlo tokenů
    (`lib/aid-token-count.sh`). `aid-control-metrics.sh` je má **konzumovat**,
    ne si měření vymýšlet znovu.

### D — co přežívá beze změny (a proto se nepřepisuje)

D1 (nejdřív měř, pak promuj), D3 (držet doložené incidenty a nevymýšlet
nedoložené), D4 (pět stavů C4, waiver viditelný a neprocházející), D5 (IMP-179
tvrdý blokér), D7 (preflight jako prerekvizita), D8 (tabulka per kontrola —
nově se šestým výsledkem z bodu 10), D10 (E10 nemaže, maže až E11), D11
(bez mechanického důkazu je nezávislost `unverifiable`/`context_only`).
D6 platí **silněji** než v červenci, protože IMP-201 je mezitím potvrzený.

### Co re-ground NEudělal

Nepřegeneroval EPICy a nespustil nic. Nepřepisoval kroky EPIC 1-5 řádek po
řádku — přepsaná jsou rozhodnutí, podmínky a acceptance criteria, protože to
jsou místa, kde se plán buď spustí, nebo prohlásí za hotový. Kroky se srovnají
až po tvojí revizi téhle sekce, aby se nesrovnávaly dvakrát.

> **Scope honesty (čti první):** E10 NENÍ „zapneme blocking a hotovo". E10 je **měřicí,
> kalibrační a rozhodovací** fáze. Nejdřív se na reálných datech PROKÁŽE, že nové C0-C4 kontroly
> (a) chytají historické známé vady, (b) neblokují legitimní změny, (c) za jakou cenu (čas / LLM
> dispatch / test běhy), a (d) které legacy kontroly mají nulovou unique detekci. Teprve na základě
> těchto dat se rozhodne, co se smí stát blokující autoritou a co se ještě NESMÍ zapnout. Současně
> E10 hlídá **rychlost** — jinak postavíme bezpečnější, ale nepoužitelně pomalý AID.
>
> **Původní E10 = kalibrace kvality. Tento E10 = kalibrace kvality + rychlosti + promotion
> bezpečnosti na základě reálných incidentů** (PM brief 2026-07-12; není změna směru, je to
> zpřesnění podle toho, co jsme mezitím zjistili v praxi).
>
> **⚠️ WRITE-ONLY ZRUŠENO (2026-08-15).** P061 je uzavřený od 14. 8., takže zámek,
> který tady stál, padl. Poslední brána startu je PM revize sekce `## Re-grounding`
> plus lint/CP1/nezávislé ověření. **Pozor na záměnu:** IMP-179, IMP-201 a čistý
> bookkeeping nejsou brány startu — vyrábí je EPIC 1 tohohle plánu — jsou to brány
> promotion, viz §Preconditions B.

## Klíčová rozhodnutí (PM-potvrzená, brief 2026-07-12)

- **D1 (E10 ≠ jen promotion):** E10 nejdřív MĚŘÍ + PROKÁŽE (chytání historických vad, ne-blokování
  legitimních změn, cena, nulová-unique-detekce legacy), teprve pak promuje. Promotion je výstup
  dat, ne cíl sám o sobě.
- **D2 (P061 gate-profily = vstup/precondition):** risk-based profily jsou součást cílového
  zrychlení. E10 NESMÍ znovu zafixovat full-suite-per-EPIC jako default; MUSÍ měřit wall-clock
  před/po profilech a potvrdit, že rizikové změny pořád eskalují na full/release profil.
  **P061 uzavřen 2026-08-14 → zámek padl.** Výjimka: Fast Mode nevydává profilové
  události (IMP-506), takže se vykáže jako `not_measurable`, ne jako naměřená nula.
- **D3 (rozšířený kalibrační dataset):** původní E-047-1/4/5 + E-044 + P045 ZŮSTÁVAJÍ. + nové
  reálné incidenty (§Context; každý s honest grounding statusem): OBS-20260711-01/IMP-201 (stale
  evidence-pack po trailing commitu), OBS-20260711-02 (CP2 míjí e2e), OBS-20260708-04 (steps[]
  pending), queue/active stale (OBS-20260709-06), + PM-cited-ungrounded (yq --profile bypass P061
  E2, audit-log dirty-tree) — ty se GROUNDUJÍ při EPIC 1/3, jinak vyjmou; NEVYMÝŠLET detaily.
- **D4 (C4 content-verdict blocking):** dnes C4 umí hlavně presence/freshness. E10 přidá
  content-verdict: REQUIRED input present+valid-JSON, ale OBSAHOVĚ failující → NESMÍ pustit release.
  C4 rozlišuje **čtyři pozorování + rozhodnutí**: `input_state` ∈ {missing, stale, invalid,
  present_but_failing, present_ok} a odděleně `verdict` ∈ {…, waived}. **Oprava kategorie
  (C0/Codex 2026-08-15):** původní znění vyjmenovalo `waived` jako pátý stav vedle čtyř
  pozorování — waiver je ale rozhodnutí o vstupu, ne jeho pozorovaný stav. Detail v Step 8.
  **Waiver NEmění fail→pass** — jen ho viditelně povolí jako waiver (blocker zůstává, release_ready
  logika nezměněná; navazuje na P060 Krok 8 waived semantiku).
- **D5 (IMP-179 = HARD blocker promotion):** dokud subagenti Auditor/Curator/Verifier mohou běžet
  ze stale plugin cache / stale `agents/*.md`, E10 NESMÍ zapnout blocking založený na jejich
  výstupech. Plán MUSÍ dodat **mechanický důkaz** aktuálnosti instrukcí: dispatch-time freshness
  hash check NEBO povinný restart/plugin-refresh gate NEBO jiný mechanický důkaz. Textové „agent má
  použít aktuální instrukce" NESTAČÍ.
- **D6 (IMP-201 před C4 blocking):** D4 CP3-Freshness-Exception nemá ekvivalent pro gates/evidence
  pack → C4 by false-blockl legitimní trailing docs/comment commit. E10 buď **zavře IMP-201**
  (bounded rozšíření D4 freshness-exception na `aid-evidence-verify.sh`/`aid-release-policy.sh`),
  NEBO **explicitně drží C4 v observe** pro tento typ případů (žádné tiché false-block).
- **D7 (bookkeeping hygiene preflight = prerequisite):** E10 kalibrace nesmí měřit bordel
  v bookkeeping vrstvě. Před promotion MUSÍ být dořešené NEBO explicitně vyjmuté: audit-log
  dirty-tree self-block (`aid-fsm init --force`), `fsm-state.steps[].status` pending po DONE,
  oficiální reporty untracked/stale, queue/active stale po merge. Samostatný preflight, který
  BLOKUJE postup do promotion, pokud to není clean/excluded.
- **D8 (rozhodovací tabulka per mechanismus):** pro každý C0-C4 check E10 vyprodukuje řádek:
  `promote_to_blocking` / `keep_observe` / `keep_dual_run` / `defer` / `remove_or_alias_in_E11_candidate`.
  Podloženo daty: chycené failure classes, počet false positives, cena času, unique detekční
  hodnota vs legacy. Bez datového podkladu se rozhodnutí nezapíše.
- **D9 (rychlost = acceptance criterion):** povinné metriky (dispatch count/EPIC, LLM/model calls,
  test/gate wall-clock, čas full suites, úspora risk-profile selectoru, medián EPIC gate cyklu po
  P061). **Bez těchto dat E10 NENÍ hotové** — nemáme důkaz, že v2 není jen další pomalá vrstva.
- **D10 (E10 NEmaže legacy):** odstranění/redukce = E11. E10 jen vytvoří datové rozhodnutí, co může
  jít v E11 pryč / na alias. Výjimka: prokazatelná dekorace ŠKODÍCÍ měření → `disabled-for-calibration`,
  ale VÝSLOVNÉ PM rozhodnutí (ne automaticky).
- **D11 (Codex/cross-provider independence nesmí být fingovaná):** není-li Codex CLI /
  cross-provider dispatch mechanicky dostupný+doložený → audit report `unverifiable` nebo
  `context_only`. „Host má codex binary" ≠ důkaz, že konkrétní audit reálně běžel přes Codex.
- **D12 (roadmap preconditions převzaty):** roadmap E10 tvrdé preconditions (IMP-179 [=D5];
  nenulový `c3_hook_fired` = C3 gate reálně naskočil; P060 DONE) jsou SPLNĚNÉ/pokryté nebo ověřené
  v §Preconditions. IMP-177 „c3_hook_fired end-to-end metric" je součást EPIC 2 (per roadmap anchor
  `2f86e3c`).

## Stakeholder Brief

Za posledních 9 fází jsme postavili kontrolní systém C0-C4, ale skoro všechno běží v režimu
„pozoruj a loguj" — starý systém pořád rozhoduje. Nikdo zatím nedokázal ČÍSLY, že nový systém
chytá vady stejně dobře jako starý + nezávislý audit, ani kolik to stojí času. E10 to má prokázat:
vezme známá historická selhání (E-047, E-044, P045) i čerstvé reálné incidenty (stale evidence-pack,
CP2 míjí e2e, gate-profile bypass, bookkeeping stale), pustí je proti novému systému a změří —
kolik chytí, kolik zbytečně zablokuje, za jakou cenu. Souběžně E10 zohlední P061 gate-profily
(vznikly kvůli brutální pomalosti testů) a měří rychlost jako tvrdé acceptance kritérium. Výstup
E10 je **rozhodovací tabulka**: pro každý check datové rozhodnutí promote/observe/dual-run/defer/
E11-remove-candidate. Blocking se zapne JEN tam, kde to data unesou a jen po vyřešení tvrdých
preconditions (stale agent instrukce IMP-179, stale evidence-pack IMP-201, bookkeeping hygiene).
E10 nic legacy nemaže — to je E11. Hodnota E10: poprvé rozhodujeme o bezpečnosti a rychlosti AID
podle dat, ne podle víry.

## Context

Stav (grounded 2026-07-12; detail + honest grounding statusy v `.aid-o/work/interim-P062.md`):
- **Roadmap E10** (docs/plans/AID-control-system-v2-roadmap.md:236-242): core = kompozitní
  regression fixtures E-047/E-044/P045; `aid-control-metrics.sh` (false-DONE/false-positive/náklady);
  dual-run new-vs-old; numerické budget stropy (T6); promotion observe→blocking + negative fixtures
  + positive controls. Tvrdé preconditions: IMP-179 + cache drift; nenulový `c3_hook_fired`; P060 DONE.
- **Verze (přepsáno re-groundem 2026-08-14):** repozitář je na **v2.86.1**, ne na v2.55.0.
  P060 = v2.54.0 DONE, P059 = v2.53.0 — to platí. **E10 už necílí na žádné konkrétní číslo:**
  v2.56.0 je dávno spotřebované jiným vydáním, takže by pin buď procházel naprázdno, nebo
  nutil krok zpátky. Vydání se alokuje při release boundary a ověřuje
  `verify-version-files.sh`.
- **C4 dnes** (`aid-release-policy.sh`, P059 + P060 Krok 8): 12 vstupů, presence/freshness/at-head
  (head_match), missing required → blocked. **Content-verdict blocking záměrně NENÍ** (P059 D-decision,
  „deferred to E10"). `RELEASE_DECISION_POLICY=observe` default (dual-run neblokuje). → D4.
- **P061 gate-profily** (UZAVŘENO 2026-08-14, E1-E5 dodané mimo D5): substrate + plan-gate floor
  (`plan_gate_profile_excluded`, `--profile` flag na aid-run-gates.sh, `gate_profiles` v projektu).
  E6 byl vždycky backlog; D5 odloženo jako IMP-506. E10 měří rychlost s/bez profilů, ale
  **jen na `/aid-run`** — Fast Mode do měření nevstupuje. → D2, D9.
- **Firmně doložené kalibrační incidenty:** OBS-20260711-01 (BACKLOG:1934) = IMP-201 (stale
  evidence-pack po verified-cosmetic trailing commitu → C4 by false-blockl; live-caught na AID
  E-061-1_6, positive control); OBS-20260711-02 (BACKLOG:2002, CP2 scope míjí full e2e, stale
  assertion 1 step nedetekován); OBS-20260708-04 (BACKLOG:783, steps[].status pending po DONE);
  OBS-20260709-06 (queue/active stale po merge, částečně P060); IMP-179 (BACKLOG:1209/1521 +
  .aid-o/work/backlog.md, stale agent instrukce, session+cache vrstva).
- **PM-citované, ZATÍM NEDOLOŽENÉ v committed ledgeru (honest flag — NEVYMÝŠLET):** (a) audit-log
  dirty-tree self-block při `aid-fsm init --force` (grep BACKLOG/backlog.md = 0); (b) yq `--profile`
  injection/selection bypass z P061 E2 (E2 je od té doby mergnutý, R-E061-2 evidence existuje, grep = 0). Oba se
  GROUNDUJÍ při EPIC 1 (a) / EPIC 3 (b); nedoloží-li se konkrétní incident, VYJMOUT z datasetu
  s poznámkou, ne fabrikovat.

## Goal

Na reálných datech prokázat, že C0-C4 kontroly chytají historické i čerstvé vady, neblokují
legitimní změny a za jakou cenu (kvalita + rychlost); vyřešit tvrdé preconditions (IMP-179
mechanicky, IMP-201, bookkeeping hygiene); přidat C4 content-verdict blocking (5 stavů, waiver
visible-not-pass); a vyprodukovat datově podloženou **rozhodovací tabulku** per C0-C4 check
(promote/observe/dual-run/defer/E11-remove-candidate). Promotion observe→blocking JEN pro checky,
které kalibraci projdou a mají splněné brány promotion (§Preconditions B). Žádné mazání
legacy (E11).

## Scope

**In scope:** `aid-e10-preflight.sh` (bookkeeping hygiene gate); IMP-179 mechanický freshness důkaz
(dispatch-time hash / refresh gate); IMP-201 resolution (D4-extension) nebo observe-hold;
`aid-control-metrics.sh` (kvalita + rychlost metriky); kompozitní regression fixtury (původní +
grounded nové); dual-run new-vs-old harness + divergence klasifikace; C4 content-verdict blocking
(5 stavů) v `aid-release-policy.sh`; P061 gate-profile speed kalibrace; per-control rozhodovací
tabulka; promotion mechanismus (per-check policy flip, jen pro schválené); Codex independence
honesty guard; registry/version/CHANGELOG; bats red-green.

**Out of scope (E11 nebo mimo):** mazání/redukce legacy kontrol (E11); FC-38 Curator auto-approve
neutralizace (E10 promotion sousedí, ale samotná neutralizace = cutover); B-008 base-side range;
nové C2 lenses; jakákoli změna, která P061 gate-profile mechaniku přepisuje (E10 ji jen měří/používá,
neopravuje — P061 doména); executable run před P061 DONE.

## Preconditions (TVRDÉ — brány A pro start běhu, brány B pro promotion)

**Přepsáno re-groundem 2026-08-14, rozděleno 2026-08-15.** Původní znění (šest
mergnutých EPICů, cíl v2.56.0) je zachované v git historii tohoto souboru;
nepřepisuje se zpětně, ale neplatí.

> **Dvě různé brány, které se předtím pletly do jedné.** První průchod
> re-groundu je vypsal jako jeden seznam, takže to četlo, jako by se běh nesměl
> ani spustit, dokud není vyřešený IMP-179 a IMP-201. **To je špatně, a byla to
> moje chyba** — IMP-179 řeší EPIC 1 Step 2 a IMP-201 EPIC 1 Step 3, tedy sám
> tenhle plán. Nemůžou být podmínkou svého vlastního vzniku. Seznam se proto
> dělí na to, co musí platit, **než se běh spustí**, a na to, co musí platit,
> **než se cokoli přepne na blokující** — což je úplný závěr běhu.

### A — než se běh spustí (musí platit dnes)

1. **P061 uzavřený** — SPLNĚNO 2026-08-14. Ověření je uzavírací záznam plánu
   (`.aid-o/plans/P061-*.md`, sekce `## Uzavření`, `status: closed`), **ne**
   počet mergů: `plan_branch` mergne EPIC do větve plánu a vydává jen plán, a
   D1 plánu P061 vždycky říkal E1-E5, ne šest ze šesti. **Výslovná výjimka:**
   D5 nedodáno (IMP-506), takže Fast Mode nevydává profilové události a
   **není předmětem měření E10**. Nesmí se to vydávat za změřenou nulu.
2. **P060 DONE** — SPLNĚNO (`## [2.54.0]`, tag v2.54.0).
3. **Checkout main, clean**; roadmap + BACKLOG čitelné z disku.
4. **PM přečetl `## Re-grounding`** a plán prošel lint + CP1/C0 + nezávislým
   ověřením. Tohle je jediná zbývající brána startu.

### B — než se cokoli přepne na blokující (závěr běhu, EPIC 5 Step 11)

Tyhle body **neblokují start**. Blokují promotion, a EPIC 1 je z velké části
právě prací na nich.

5. **Bookkeeping hygiene** (D7) — `aid-e10-preflight.sh` vrací clean NEBO PM
   položky výslovně vyjme. Dnes clean NENÍ: `R-E045-1`, `R-E049-1`, `R-E057-2`
   jsou `DONE` s kroky ve stavu `pending` (změřeno 2026-08-14).
6. **IMP-179 mechanický důkaz** (D5, dodává EPIC 1 Step 2) — bez něj **žádná** blocking promotion
   kontroly stojící na výstupu subagenta. Nezpůsobilé kontroly se v rozhodovací
   tabulce označí, ne vynechají.
7. **IMP-201 rozhodnut** (D6, dodává EPIC 1 Step 3) — buď opraveno a otestováno proti doloženému
   případu trailing commitu, nebo C4 výslovně **drží observe** pro freshness a
   content blocking. Procházející test výjimky sám o sobě nestačí: IMP-201 je
   ověřeně reálný a ožívá ve chvíli, kdy E10 přepne na blocking.
8. **Rozpočet merge cesty rozhodnut** (nová podmínka) — merge cesta je
   18 min 07 s proti rozpočtu 10 min, tedy **81 % nad**, ještě než E10 cokoli
   přidá. Před promotion musí padnout jedno ze tří: rozpočet se zvedne cestou
   vlastníka standardu, merge cesta se zmenší, nebo se výjimka výslovně
   zapíše. E10 tenhle stav nesmí mlčky znormalizovat. **Tohle je jediná
   z brán B, kterou nevyrábí sám běh — potřebuje tvoje rozhodnutí.**

---

## EPIC 1 — Preflight & tvrdé preconditions (Steps 1-3)

**EPIC 1: E10 preflight & hard preconditions (Steps 1-3)**

### Step 1: Bookkeeping hygiene preflight (aid-e10-preflight.sh)

**Dependencies:** none — první krok plánu

> **Vyrábí artefakt `e10-preflight.json`** v run evidence: `{verdict: clean|excluded_by_pm,
> checked: [...], exclusions: [{item, reason}]}`. AC1 ho čte. (C0 nález 2026-08-15: kritéria
> jmenovala artefakty, které žádný krok nevyráběl.)

**Objective:** Samostatný preflight, který PROKÁŽE, že bookkeeping vrstva není stale, jinak
BLOKUJE postup do kalibrace/promotion — E10 nesmí měřit bordel (D7).

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-e10-preflight.sh` — kontroluje 4 třídy: (a)
  audit-log dirty-tree self-block při `aid-fsm init --force` (**GROUND FIRST:** doložit reálný
  incident/repro z aktuálního probe; nedoloží-li se, položku vyjmout s poznámkou, ne fabrikovat);
  (b) `fsm-state.steps[].status` pending po DONE (OBS-20260708-04); (c) oficiální reporty
  untracked/stale (`.aid-o/reports/*`, delivery/boundary); (d) queue/active stale po merge
  (OBS-20260709-06, `git merge-base --is-ancestor` per blocked dep). Výstup: `e10-preflight.json`
  (per-třída clean|dirty|excluded + důvod). Exit ≠ 0 při dirty bez PM-exclude.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-e10-preflight.bats` — red-green:
  dirty fixture per třída → exit ≠ 0 + dirty řádek; clean → exit 0; PM-excluded → exit 0 + excluded řádek.

**Acceptance Criteria:**
- [ ] Preflight detekuje každou ze 4 tříd na fixtuře (grounded třídy) → exit ≠ 0; clean → exit 0.
- [ ] PM-exclude mechanismus: explicitně vyjmutá třída → exit 0 + `excluded` řádek s důvodem (ne tichý pass).
- [ ] `e10-preflight.json` per-třída status; dirty bez exclude blokuje (promotion gate to čte).
- [ ] Audit-log dirty-tree třída: buď doložený repro + test, NEBO explicitní `not_grounded` skip s poznámkou (žádná fabrikace).

**Effort:** M
**AID Role:** backend

### Step 2: IMP-179 mechanický freshness důkaz agent instrukcí

**Dependencies:** none — nezávislý na Step 1 (jiná vrstva: dispatch, ne bookkeeping)

> **Vyrábí artefakt `agent-freshness.json`**:
> `{preflight_ran: bool, trees_checked: [...], skewed_trees: [...], stale_count: N,
> scope_note: "..."}`. AC2 ho čte.
>
> **Pole jsou přejmenovaná proti prvnímu návrhu, a to je ta oprava.** Původně tu stálo
> `dispatches_checked` a `stale: [{role, ...}]`, jenže žádný dispatch se nepozoruje — v
> default režimu dispatchuje controller přes `Agent()` bez shellu. Pole slibující počet
> zkontrolovaných dispatchů by bylo over-claim zabudovaný do schématu, tedy přesně tam, kde
> ho nikdo nekontroluje. Měří se stromy, tak se tak jmenují. `scope_note` cestuje i se
> zeleným výsledkem, protože u selhání ho stejně nikdo znovu nečte.
>
> `preflight_ran: false` je vlastní stav: „neproběhlo srovnání" není totéž co „nic není
> zastaralé".

**Objective:** Mechanicky prokázat, že dispatchovaný subagent (Auditor/Curator/Verifier) dostal
AKTUÁLNÍ instrukce (agents/*.md + plugin cache), jinak žádný blocking promotion na jejich výstupech
(D5 hard blocker). Textové „agent má použít aktuální" nestačí.

**Files:**
> **Producent OPRAVEN (C0 nález 2026-08-15).** Krok chtěl hash „při dispatchi" a jmenoval
> `aid-fsm.sh` — jenže ten výstupy jen KONZUMUJE. V default režimu `agent_tool` dispatchuje
> controller přímo přes `Agent()` (`skills/pipeline.md:874`), žádný shell mezi tím není, takže
> hash při dispatchi tam shellem zachytit NELZE. `aid-emit-dispatch.sh` existuje, ale jede jen
> v režimu `subagent` a žádný hash instrukcí nenese.
>
> **Co ale JDE mechanicky a řeší skutečnou příčinu IMP-179:** ta vada nikdy nebyla „agent
> dostal jiný soubor", byla to **zastaralá cache pluginu**. A na to už existuje
> `lib/aid-cache-preflight.sh` (P060 Krok 5), který porovnává běžící verzi a hash stromu
> `scripts/` proti repozitáři a tvrdě staví běh při `skew_dogfood`. **Jeho vlastní hlavička
> říká, že `agents/`, `skills/` a `defaults/` nepokrývá a že tyhle třídy zůstávají blokerem
> E10** — tenhle krok je tam, kde se to dopisuje.
>
> **Poctivý rozsah, který se NESMÍ přehnat:** dokazuje se, že cache, ze které controller běží,
> odpovídá repozitáři v okamžiku kontroly. NEdokazuje se, co dostalo jednotlivé volání
> `Agent()`. Ten rozdíl se napíše do výstupu, ne zamlčí.

- Modify: `plugins/aid-orchestrator/scripts/lib/aid-cache-preflight.sh` — rozšířit pokrytí ze
  samotného `scripts/` na `agents/` (a `skills/`, `defaults/`), stejným deterministickým
  tree-hashem a stejnou trojicí stavů `ok|skew_consumer|skew_dogfood`. Žádná nová knihovna:
  díra je pojmenovaná v hlavičce toho souboru a zavírá se tam, kde je. **Mechanismus ROZHODNUT (re-ground 2026-08-15, poslední průchod): varianta A** —
  dispatch-time hash check, detekce v režimu observe, a promotion-gate čte nenulový
  stale-count. Fork se zavírá tady, ne až při vettingu: B (povinný restart/plugin-refresh
  před blocking) sahá na hostitele, kterého AID neovládá, což zakazuje D5 vstupního
  dokumentu; C je A plus B. A je jediná varianta, kterou AID umí sám prokázat.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — hook v místě, kde se výstup
  Auditor/Curator/Verifier KONZUMUJE, volá rozšířený preflight; skew → `agent_instructions_stale`
  event, promotion-gate ho počítá.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-cache-preflight.bats` — red-green
  **tam, kde ta rodina žije**, ne v nové sadě: strom `agents/` rozejitý s cache → hard stop, který
  ten strom pojmenuje; všechny stromy shodné → průchod (jinak je „zastaví se na rozdílu"
  splnitelné tím, že se to zastaví vždycky); artefakt nese `preflight_ran`, `skewed_trees` a
  poctivý rozsah.
  **Nová `test-agent-freshness.bats` se nevytváří** — původní znění tohohle řádku ji jmenovalo
  a odporovalo tím AC2 níže (závěrečný audit 2026-08-15). Kontrola se dopsala do existující
  cache preflight, takže testy patří k ní.

**Acceptance Criteria:**
- [ ] Rozšířený preflight detekuje skew ve stromu `agents/` stejně tvrdě jako dnes ve `scripts/` (red-green: rozejít cache a repo → `skew_dogfood`, hard stop).
- [ ] Shodná cache → žádný stale event (kontrola nesmí pálit naprázdno).
- [ ] Promotion-gate: nenulový stale-count v datech → BLOKUJE promotion agent-output kontrol (Auditor/Curator/Verifier) na blocking (D5).
- [ ] Pokrytí je poctivé a NAPSANÉ ve výstupu: kryje shodu cache s repozitářem pro `scripts/`+`agents/`(+`skills/`,`defaults/`); NEdokazuje, co dostalo konkrétní volání `Agent()`. Over-claim = red.

**Effort:** L
**AID Role:** backend

### Step 3: IMP-201 resolution (D4-extension) nebo explicit C4 observe-hold

**Dependencies:** none — nezávislý na Steps 1-2

> **Vyrábí artefakt `imp201-decision.json`** v run evidence:
> `{decision: "fixed"|"observe_hold", reason: "<>=20 znaků>",
> trailing_commit_case_covered: bool, c4_freshness_enforcement: "observe"|"blocking"}`.
> AC3 ho čte a rozlišuje obě větve. Zelený test výjimky sám o sobě rozhodnutí NENÍ.
> (C0 nález 2026-08-15.)

**Objective:** Zavřít stale-evidence-pack false-block třídu (OBS-20260711-01): D4
CP3-Freshness-Exception nemá ekvivalent pro gates/evidence pack → jakmile C4 enforcuje, false-blockne
legitimní trailing docs/comment commit. E10 buď zavře IMP-201, nebo explicitně drží C4 v observe
pro tento typ (D6). NIKDY tiché false-block.

**Files:**
> **ROZHODNUTO: observe-hold, IMP-201 se pod E10 NEOPRAVUJE** (cross-model adjudikace
> 2026-08-15, eskalováno podle zadání PM). Oprava znamená vytáhnout D4 klasifikátor do
> sdílené funkce a zavolat ho z **blokující preconditiony uvnitř `aid-fsm.sh`** — a zároveň
> rozšířit *povolující* výjimku na release bráně. Taková mezera má promotion **zabránit**,
> ne se v něm svézt.
>
> **Co to stojí, napsané a ne zamlčené:** C4 freshness nesmí být pro třídu trailing commitu
> v E10 promován na blocking. V rozhodovací tabulce z toho je výslovné nepromování
> s pojmenovanou podmínkou uzavření, ne tiché observe.
>
> Původní znění tohohle kroku (rozšíření `aid-evidence-verify.sh` + `aid-release-policy.sh`)
> zůstává jako popis toho, co IMP-201 zavře — až se to bude dělat, mimo E10.
- Modify: `plugins/aid-orchestrator/defaults/policies/release-decision-policy.yaml` — pokud se
  IMP-201 nezavře do promotion, `evidence_pack_freshness_policy: observe` pro trailing-commit třídu
  (explicitní observe-hold, ne tiché false-block); rozhodnutí resolve-vs-hold = PM fork.
- Create: `plugins/aid-orchestrator/scripts/aid-e10-imp201-decision.sh` — rozhodnutí se
  **odvozuje z repozitáře**, netvrdí: IMP-201 je zavřený právě tehdy, když
  `aid-release-policy.sh` konzultuje sdílený klasifikátor. Ručně psaný soubor s rozhodnutím
  by rok po opravě pořád říkal `observe_hold` — a po refaktoru, který sdílení odstraní, by
  pořád říkal `fixed`. Skript navíc ODMÍTNE zapsat `observe_hold`, který politika nedrží.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-e10-imp201-decision.bats` —
  red-green: bez sdíleného klasifikátoru → `observe_hold`; s ním → `fixed` samo od sebe;
  rozpor mezi rozhodnutím a politikou → odmítnuto; dodávaná politika ten klíč opravdu nese.

**Acceptance Criteria:**
- [ ] `imp201-decision.json` nese `observe_hold` s důvodem ≥20 znaků a s dopadem na promotion; `trailing_commit_case_covered: false`.
- [ ] Rozhodnutí se odvozuje: zavedení sdíleného klasifikátoru překlopí artefakt na `fixed` bez ruční editace (test).
- [ ] `observe_hold` při politice ≠ `observe` je ODMÍTNUT (exit 2) — záznam nesmí tvrdit hold, který nikdo nedrží.
- [ ] Produkční trailing commit → pack STALE (fail-closed; exception se nesmí zneužít na produkční změnu).
- [ ] Alternativa observe-hold: pokud PM zvolí nezavírat IMP-201, C4 pro tuto třídu je explicitně `observe` (žádné tiché false-block; dokumentováno v policy).
- [ ] Reprodukce původního OBS-20260711-01 case (E-061-1_6 trailing `25bff3e`): před fixem C4-enforce by blokoval, po fixu ne.

**Effort:** M
**AID Role:** backend

---

## EPIC 2 — Měřicí instrumentace (Steps 4-5)

**EPIC 2: E10 measurement instrumentation (Steps 4-5)**

### Step 4: aid-control-metrics.sh — kvalitní metriky (detekce, false-DONE, false-positive)

**Dependencies:** Steps 1-3 (preflight musí být clean nebo vyjmutý, jinak metriky měří nepořádek)

> **Konflikt pořadí VYŘEŠEN (C0 nález 2026-08-15).** Krok deklaroval jako vstup „dataset
> EPIC 3", tedy výstup kroku 6, který je v pořadí AŽ ZA NÍM — plán tím sám sobě odporoval.
> Rozdělení: **tenhle krok staví a testuje NÁSTROJ** na vlastních malých fixturách (jeho
> AC to tak už formulovaly: „na fixture datasetu"). **Spuštění nad kalibračním datasetem**
> je až po kroku 6 a jeho výsledek konzumuje krok 10. Plan-level `control-metrics.json`
> v `evidence/P062/e10/` proto vzniká po kroku 6, ne tady; AC4/AC5 jsou plan-level, ne
> hranice tohohle kroku.

**Objective:** Nástroj, který z run-evidence spočítá KVALITU kontrol: kolik failure classes který
C0-C4 check chytil, false-DONE (prošlo a nemělo), false-positive (blokoval zbytečně), per-control
unique detekci vs legacy (D1, D8 podklad). + ověří nenulový `c3_hook_fired` (roadmap precondition,
IMP-177 end-to-end).

**Files:**
> **Jedno schéma, ne tři pravopisy (C0 nález 2026-08-15).** Krok 4, krok 10 a AC4 pojmenovávaly
> tatáž pole třemi způsoby (`caught_classes` vs `caught`, `false_done` vs `false_positives`,
> `cost` vs `cost_seconds`), takže krok 10 nemohl spolehlivě konzumovat krok 4 a AC mohlo projít
> nad jiným tvarem, než tabulka potřebuje. **Kanonický tvar je níže a je závazný pro kroky 4, 5,
> 9, 10 i pro AC4/AC5/AC9.**

- Create: `plugins/aid-orchestrator/defaults/schemas/control-metrics.schema.json` — verzované
  schéma artefaktu. Per kontrola: `control` (id), `caught_classes[]`, `false_done`,
  `false_positives`, `cost_seconds`, `unique_detection_vs_legacy`. Plan-level: `speed{...}`
  (pole viz krok 5), `profile_calibration{...}` (krok 9),
  `c3_verdict_mix{pass,fail,unverifiable}`.
- Create: `plugins/aid-orchestrator/scripts/aid-control-metrics.sh` — vstup: run-evidence dirs
  + timeline events; výstup: `control-metrics.json` **validovaný proti tomu schématu**.
  Deterministické (žádný LLM).
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-control-metrics.bats` — red-green na
  fixture evidence: check který chytil známou vadu → caught; check který pustil → false_done; +
  `c3_hook_fired` count nenulový na fixture s live C3 runem.

**Acceptance Criteria:**
- [ ] Na fixture datasetu: `control-metrics.json` per-check caught_classes / false_done / false_positive spočítané deterministicky.
- [ ] `c3_hook_fired` count nenulový na fixtuře s reálným C3 runem (IMP-177 end-to-end ověření, roadmap precondition 2).
- [ ] Unique-detection vs legacy: pro každý check spočítá, kolik vad chytil, co legacy nechytil (podklad D8 tabulky).
- [ ] Metriky reprodukovatelné (rerun = stejná čísla; žádná mutable/gitignored závislost bez pinnutí — poučení z IMP-182 input_hash).

**Effort:** L
**AID Role:** backend

### Step 5: Speed metriky (dispatch/LLM/merge cesta/plan-final/noční/medián)

**Dependencies:** Step 4 (rozšiřuje aid-control-metrics.sh o speed sekci)

**Objective:** Rychlost jako tvrdé acceptance kritérium (D9). Bez těchto dat E10 NENÍ hotové —
jinak nemáme důkaz, že v2 není jen další pomalá vrstva.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-control-metrics.sh` (+ lib) — speed sekce:
  dispatch count/EPIC, LLM/model calls (z timeline dispatch eventů), a wall-clock ve
  **třech jednotkách, které dnes existují** (re-ground 2026-08-14): merge cesta (T0+T1),
  plan-final brány a noční portfolio. „Čas full suites per EPIC" jako jednotka **padá** —
  P068 platí drahé brány jednou za plán, ne za EPIC. Úspora risk-profile selectoru se měří
  proti runtime baseline z P063, ne proti neexistujícímu full-suite-per-EPIC běhu.
  **Přírůstek E10 se vykazuje odděleně od výchozího stavu**, jinak si E10 přičte 18 minut,
  které nezpůsobilo, nebo v nich schová vlastní náklady. Zdroj: timeline timestamps, gate
  report durations, `lib/aid-test-durations.sh`, noční záznamy
  `/opt/eco/data/aid-nightly/aid-orchestrator/<datum>.json`, `lib/aid-gate-runtime-baseline.sh`,
  `lib/aid-token-count.sh`. Fast Mode profilové události **nejsou vstup** (IMP-506) — vykáže se
  jako `not_measurable`, nikdy jako naměřená nula.
- Modify: FSM/gate-runner instrumentace (pokud chybí timestamp granularita) — zajistit, že timeline
  nese dispatch start/end + gate durations (navazuje na aid-run-gates.sh duration_ms).
- Create/extend: `test-control-metrics.bats` — red-green: speed sekce spočítá dispatch count +
  wall-clock z fixture timeline; profile-úspora = full - profile delta > 0 na fixtuře.

**Acceptance Criteria:**
- [ ] `control-metrics.json` speed sekce: dispatch_count, llm_calls, merge_path_seconds, plan_final_seconds, nightly_seconds, profile_savings, median_gate_cycle — všechny spočítané z reálných evidence timestampů.
- [ ] Přírůstek E10 je vykázaný odděleně od výchozího stavu (`baseline_seconds` a `e10_added_seconds` jako dvě různá pole).
- [ ] Profile-úspora měřitelná proti P063 baseline, ne proti full-suite-per-EPIC.
- [ ] Fast Mode je `not_measurable` s odkazem na IMP-506, ne 0.
- [ ] Speed metriky jsou POVINNÉ acceptance: chybí-li kterákoli → E10 metrics report `incomplete` (D9, ne tichý pass).

> **Vyrábí `merge-path-budget.json`** v run evidence: `{measured_seconds, budget_seconds,
> over_budget_pct, decision: "budget_raised"|"path_reduced"|"exception_recorded",
> decided_by, reason}`. Krok naměří a předvyplní `measured_seconds`; pole `decision`
> vyplní PM u brány §Preconditions B/8 — je to jediná brána, kterou běh sám nevyrobí.
> AC14 ho čte. (C0 nález 2026-08-15.)

**Effort:** M
**AID Role:** backend

---

## EPIC 3 — Kalibrační dataset + dual-run (Steps 6-7)

**EPIC 3: Calibration dataset + dual-run (Steps 6-7)**

### Step 6: Kompozitní regression fixtury (původní + grounded nové)

**Dependencies:** none — fixtury stojí samostatně

> **Vyrábí `fixtures/e10-calibration/manifest.json`** — provenience, ne počet. Každá položka:
> `{path, source_incident, failure_class, control: "positive"|"negative", expected_old,
> expected_new, grounded: bool, excluded_reason?}`. Nedoložená fixtura se VYLOUČÍ s důvodem,
> nikdy nedomýšlí (D3). AC6 čte manifest a ověří, že každá `grounded` položka má existující
> soubor. (C0 nález 2026-08-15.)

**Objective:** Dataset známých vad, proti kterému se měří (D3). Každá fixtura deklaruje, KTERÁ
vrstva ji má chytit (C1 deterministicky / C2 sémanticky / C3 audit / C4 agregace) — jinak je
„chycení" neověřitelné.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/e10-calibration/` — fixtury:
  **původní** (E-047-1, E-047-4, E-047-5, E-044, P045 — reálná historická selhání);
  **nové grounded** (OBS-20260711-01 stale evidence-pack; OBS-20260711-02 CP2-míjí-e2e;
  OBS-20260708-04 steps[] pending; OBS-20260709-06 queue/active stale);
  **PM-cited (GROUND FIRST, jinak vyjmout):** yq `--profile` bypass z P061 E2 (doložit z R-E061-2
  audit/finding), audit-log dirty-tree (doložit z probe). Každá fixtura: `expected_catcher: <layer>`
  + `failure_class`.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-e10-calibration-dataset.bats` —
  každá fixtura projde příslušnou vrstvou a je CHYCENA očekávaným catcherem; nechycená → red.

**Acceptance Criteria:**
- [ ] Původní dataset (E-047-1/4/5, E-044, P045) jako fixtury, každá s `expected_catcher` + `failure_class`.
- [ ] Grounded nové incidenty (OBS-20260711-01/02, OBS-20260708-04, OBS-20260709-06) jako fixtury.
- [ ] PM-cited (yq bypass, audit-log dirty): buď doložená fixtura z reálné evidence, NEBO explicitní `not_grounded` skip s poznámkou v datasetu (žádná fabrikace).
- [ ] Každá fixtura je chycena deklarovaným catcherem; negative control (typická regrese) MUSÍ failovat na správné vrstvě.

**Effort:** L
**AID Role:** qa

### Step 7: Dual-run new-vs-old harness + divergence klasifikace

**Dependencies:** Step 6 (dual-run potřebuje kalibrační dataset)

**Objective:** Pustit dataset (i běžné EPICy) oběma cestami — nový C0-C4 vs starý CP/legacy — a
klasifikovat divergence (D1). Navazuje na P059 dual-run substrát (`release_policy_dual_run`,
`divergence_class`).

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-dual-run.sh` — pro dataset/run porovná nový verdikt
  (C0-C4) vs legacy verdikt; klasifikuje: `agree`, `new_stricter`, `legacy_stricter`,
  `verification_only` (git-dirty šum, z P059), `new_unique_catch`, `legacy_unique_catch`. Výstup
  `dual-run-report.json`. Filtruje `verification_only` ať netopí signál (P059 poučení).
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-dual-run.bats` — red-green: fixtura
  kde nový chytí a legacy ne → `new_unique_catch`; kde legacy chytí a nový ne → `legacy_unique_catch`
  (kritický pro D8 „nemazat legacy s unique detekcí"); shoda → `agree`.

**Acceptance Criteria:**
- [ ] Dual-run porovná nový vs legacy verdikt per fixture/run → `dual-run-report.json` s divergence třídou.
- [ ] `legacy_unique_catch` je detekován (legacy chytil, co nový ne) — kritické: takový legacy check se v D8 NESMÍ označit E11-remove.
- [ ] `verification_only` (git-dirty) je odfiltrován ať netopí signál (P059 poučení).
- [ ] Dataset z EPIC 3 projde dual-runem; výstup je vstup pro control-metrics (Step 4) a decision table (Step 10).

**Effort:** L
**AID Role:** backend

---

## EPIC 4 — C4 content-verdict + gate-profile kalibrace (Steps 8-9)

**EPIC 4: C4 content-verdict + gate-profile calibration (Steps 8-9)**

### Step 8: C4 content-verdict blocking (5 stavů + waiver visible-not-pass)

**Dependencies:** none — C4 content-verdict je samostatná změna release-policy

> **Vyrábí `c4-content-verdict.json`** v run evidence: `{states_exercised: [...],
> waived_verdict_exercised: bool, waived_blocks_release: bool,
> present_but_failing_blocks_release: bool}` — důkaz, že se stavy opravdu odehrály za běhu, ne
> že o nich existuje test. AC8 ho čte.
>
> **Pozor na tu záměnu kategorie (C0 nález 2026-08-15):** `states_exercised` obsahuje **pět
> `input_state` hodnot včetně `present_ok`** — a `waived` mezi nimi NENÍ, protože je to
> verdikt, ne stav. Waiver se dokazuje odděleně přes `waived_verdict_exercised`. První verze
> AC8 vyžadovala `waived` mezi stavy a `present_ok` vynechávala, tedy si odporovala se svým
> vlastním krokem.

**Objective:** C4 dnes umí hlavně presence/freshness. E10 přidá content-verdict: REQUIRED input
present+valid-JSON ale OBSAHOVĚ failující → NESMÍ pustit release (D4). Navazuje na P060 Krok 8
head_match/waived semantiku.

**Files:**
> **Reprezentace ROZHODNUTA (C0 nález, Codex adjudikace 2026-08-15): nové pole
> `input_state` vedle `verdict`, nikoli rozšíření `verdict`.**
>
> C0 ukázal, proč to nejde napsat do `verdict`: waiver mapuje na jednu řádku
> `inputs[]` a flipuje `blocked → waived`. Kdyby `verdict` nesl
> `present_but_failing`, waiver by na tu řádku přestal sedět; kdyby zůstal
> `blocked`, pět stavů se do jednoho pole nevejde.
>
> **A `waived` vůbec není stav vstupu — je to ROZHODNUTÍ o něm.** Plán ho
> vyjmenovával jako pátý stav vedle čtyř pozorování, což je záměna kategorie
> (Codex, 2026-08-15). Rozpad je proto tenhle:
>
> - `input_state` (pozorování): `missing` / `stale` / `invalid` /
>   `present_but_failing` / `present_ok`
> - `verdict` (rozhodnutí, enum se NEMĚNÍ): `pass` / `fail` / `blocked` /
>   `unverifiable` / `waived` / `advisory`
>
> Waiver dál klíčuje na `blocked`, dál nechává blocker stát a `release_ready`
> beze změny. Cena volby: jedno pole navíc a konzument musí číst obě, aby měl
> celý obrázek. **Podtržítková podoba `present_but_failing` je kanonická** —
> plán ji dřív psal dvěma způsoby.

- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` — per-input klasifikace
  do NOVÉHO pole `input_state` (pět hodnot výše). `present_but_failing` = present + valid,
  ale obsahový verdikt selhává (audit-report `blocking_findings`, gates_report `overall≠pass`,
  semantic-review-final fail). REQUIRED s `input_state: present_but_failing` → `verdict: blocked`
  → `release_ready=false`. **Waiver NEmění fail→pass**: `verdict` jde na `waived`, `input_state`
  zůstává, blocker stojí.
- Modify: `plugins/aid-orchestrator/defaults/schemas/release-decision.schema.json` — přidat
  do `inputs[]` povinné pole `input_state` s pětihodnotovým enumem. `verdict` enum se
  **nemění** (P060 poučení: neměnit enum, po kterém sahá waiver).
- Modify: `plugins/aid-orchestrator/scripts/aid-protocol-validate.sh` **(C0 nález 2026-08-15 —
  chybělo)** — `inputs[]` má ve schématu `additionalProperties: false`, takže nové povinné pole
  musí projít i autoritativním validátorem; ten dnes validuje jen `release_ready` a D11 pole,
  tvar `inputs[]` vůbec ne. Bez tohohle kroku by artefakt s chybějícím nebo poškozeným
  `input_state` prošel tím validátorem, který má být poslední instancí. Přidat kontrolu tvaru
  `inputs[]` (id, artifact, verdict, head_match, input_state) + protocol-v2 fixtury
  `release_decision` valid/invalid.
- Modify: `plugins/aid-orchestrator/defaults/policies/release-decision-policy.yaml` —
  `content_verdict_policy: observe|blocking` (default observe do promotion; E10 promotion ho flipne
  jen po kalibraci, D8).
- Create/extend: `test-release-policy.bats` — red-green: REQUIRED present+valid-but-content-fails →
  blocked (dnes by prošel = red); missing/stale/invalid rozlišené; waiver na failing input → verdikt
  `waived`, blocker ZŮSTÁVÁ, release_ready NEpřejde na true.

**Acceptance Criteria:**
- [ ] REQUIRED input present + valid JSON + obsahový verdikt fail → `input_state: present_but_failing` → `verdict: blocked` → release_ready=false (dnes prochází = red-green důkaz).
- [ ] `input_state` rozlišuje všechna čtyři pozorování + `present_ok`; každé má test. `waived` se testuje na `verdict`, protože to je rozhodnutí, ne pozorování.
- [ ] Waiver na failing input → `verdict: waived` PŘI ZACHOVANÉM `input_state: present_but_failing`, blocker ZŮSTÁVÁ, release_ready se NEZmění na pass (waiver = viditelné povolení, ne přepsání).
- [ ] `verdict` enum je bajtově nezměněný oproti výchozímu stavu (regresní test — rozšíření by rozbilo waiver mapování).
- [ ] `aid-protocol-validate.sh` ODMÍTNE `release_decision` artefakt s chybějícím nebo mimo-enum `input_state` (negativní fixtura); platný artefakt projde. Bez toho je nové povinné pole hlídané jen schématem, které autoritativní validátor nečte.
- [ ] `content_verdict_policy` default observe; blocking se zapne jen promotion krokem (Step 11) po kalibraci; stávající release-policy suite zelená.

**Effort:** L
**AID Role:** backend

### Step 9: P061 gate-profile speed kalibrace + escalation důkaz

**Dependencies:** Step 5 (měří přes speed sekci) + Step 6 (potřebuje dataset)

**Objective:** Potvrdit, že P061 risk-based profily reálně zrychlují A že rizikové změny pořád
eskalují na full/release profil (D2). E10 NESMÍ znovu zafixovat full-suite-per-EPIC default.

> **Re-ground 2026-08-15:** srovnávací základnou už NENÍ „full-suite per EPIC" — ten běh
> po P068 neexistuje, drahé brány se platí jednou za plán. Základnou je runtime baseline
> z P063 a naměřené doby pater. A tenhle krok měří jen `/aid-run`: Fast Mode do měření
> nevstupuje (IMP-506), takže „profily zrychlují" platí o jedné ze dvou vstupních cest a
> tak se to i napíše.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-control-metrics.sh` — profile-kalibrační sekce:
  wall-clock proti P063 baseline per risk level; escalation matrix (které změny → který profil).
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-e10-profile-calibration.bats` —
  red-green: low-risk change → light profil (rychlejší, měřitelná úspora); high-risk/security change
  → eskaluje na full/release profil (NESMÍ zůstat na light); default NENÍ full-suite-per-EPIC.

**Acceptance Criteria:**
- [ ] Profile speed delta měřená proti P063 runtime baseline, úspora > 0 doložená; rozsah platnosti (`/aid-run`, ne Fast Mode) je v tom výstupu napsaný.
- [ ] Escalation důkaz: high-risk/security change eskaluje na full/release profil (behaviorální test, ne konfigurace).
- [ ] Default NENÍ full-suite-per-EPIC (regrese by to znovu zafixovala = red).
- [ ] **Precondition guard:** P061 je uzavřený (2026-08-14), takže tenhle krok běží na živých datech, ne na fixtuře. Fixturová varianta zůstává jen jako fallback, když běh nemá dost vlastních dat.

**Effort:** M
**AID Role:** backend

---

## EPIC 5 — Rozhodovací tabulka + promotion (Steps 10-11)

**EPIC 5: Decision table + promotion (Steps 10-11)**

### Step 10: Per-control rozhodovací tabulka (datově podložená)

**Dependencies:** Steps 4, 5, 7, 8, 9 (tabulka konzumuje control-metrics.json a dual-run-report.json)

**Objective:** Pro každý C0-C4 check vyprodukovat datové rozhodnutí (D8): promote_to_blocking /
keep_observe / keep_dual_run / defer / remove_or_alias_in_E11_candidate /
**cannot_promote_runtime_budget**. Podklad: EPIC 2 metriky + EPIC 3 dual-run.

> **Šestý výsledek (re-ground 2026-08-15, C0 nález).** `cannot_promote_runtime_budget`
> byl původně jen v AC13, takže krok o něm nevěděl a kritérium by nešlo splnit. Znamená:
> kontrola by jinak prošla, ale merge cesta je nad rozpočtem, takže se nezapíná, dokud
> nepadne rozhodnutí z §Preconditions B/8. Není to `defer` — u `defer` chybí data, tady
> data jsou a brání tomu rozpočet.
>
> **Metrika `unverifiable` u C3** patří sem taky, ne jen do AC13: tabulka nese pole
> `c3_verdict_mix` s počty pass/fail/unverifiable. Bez něj by C3 vyšlo jako „skoro nikdy
> neblokuje", což je ta past, kterou re-ground pojmenoval.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-e10-decision-table.sh` — vstup: control-metrics.json
  + dual-run-report.json; výstup: `e10-decision-table.json` + human `e10-decision-table.md`. Per
  check: rozhodnutí + podklad (kanonická pole ze schématu: `caught_classes`, `false_positives`,
  `cost_seconds`, `unique_detection_vs_legacy`) +
  `evidence_refs[]` (odkaz na artefakt, ze kterého to rozhodnutí vzniklo — bez něj se řádek
  nezapíše). Navíc plan-level pole `c3_verdict_mix {pass, fail, unverifiable}`. Řádek
  bez datového podkladu se NEZAPÍŠE (nebo `defer` s důvodem „insufficient data").
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-e10-decision-table.bats` — red-green:
  check s nulovou unique detekcí + má legacy dvojče → `remove_or_alias_in_E11_candidate`; check
  s unique detekcí + nízké FP → `promote_to_blocking` kandidát; nedostatek dat → `defer`.

**Acceptance Criteria:**
- [ ] `e10-decision-table.{json,md}` per C0-C4 check: 1 ze **6** rozhodnutí + datový podklad (4 pole: caught_classes, false_positives, cost, unique_detection_vs_legacy) + neprázdné `evidence_refs[]`; jedna kontrola právě jednou (bez duplicit).
- [ ] Plan-level `c3_verdict_mix` s počtem `unverifiable` je přítomný; C3 nesmí dostat `promote_to_blocking`, pokud `unverifiable` převažuje nad (pass+fail).
- [ ] `cannot_promote_runtime_budget` se použije, když kontrola prošla kalibrací, ale rozpočet merge cesty není rozhodnutý (§Preconditions B/8) — nezaměňovat s `defer` (tam chybí data).
- [ ] Check bez datového podkladu → `defer` s důvodem (NE promote naslepo).
- [ ] `remove_or_alias_in_E11_candidate` JEN pro check s prokázanou nulovou unique detekcí v dual-run datech (D8; legacy s unique catch se nikdy neoznačí).
- [ ] Tabulka je vstup pro E11 (D10: E10 rozhoduje, E11 provádí).

**Effort:** M
**AID Role:** backend

### Step 11: Promotion mechanismus + Codex honesty + registry/version

**Dependencies:** Step 10 (promuje se jen podle tabulky)

**Objective:** Zapnout blocking JEN pro checky, které tabulka (Step 10) schválila `promote_to_blocking`
A mají splněné preconditions (D1, D5, D6, D7). Legacy NETKNUTÉ (D10). Codex independence honesty (D11).

**Files:**
> **Mechanismus ROZHODNUT (C0 nález, Codex adjudikace 2026-08-15): per-control mapa
> UVNITŘ každého stávajícího policy souboru.**
>
> C0 ukázal díru: každý ten soubor má dnes JEDEN globální `enforcement: observe`, takže
> „zapneme jen schválené kontroly" nešlo ani zapsat, natož prokázat. Vybraná varianta
> nechává vlastnictví i čtenáře tam, kde jsou:
>
> ```yaml
> enforcement: observe            # default pro celý soubor, beze změny
> controls:
>   <control_id>:
>     enforcement: blocking       # zapíná se JEN kontrola, sourozenci dědí observe
> ```
>
> Zamítnuto: centrální promotion soubor (zavádí nový konfigurační subsystém napříč
> politikami) i promotion po celých souborech (nesplní kritérium „jen schválené").
> **Cena volby, pojmenovaná:** CP3 freshness není v žádném z těch souborů — je to
> route v `aid-fsm.sh` řízená prostředím — takže potřebuje vlastní obdobnou vazbu a
> **přes ty mapy ji promovat nejde**.

> **Bez inventáře to nejde spustit (C0 nález 2026-08-15).** `controls.<control_id>` byl
> zástupný symbol — plán nikde neřekl, jaká ID existují ani který čtenář je má číst. A
> `aid-fsm.sh` dnes čte globální `.enforcement` na PĚTI různých místech
> (`:5951`, `:6711`, `:6752`, `:6801`, `:7610`), každé pro jinou kontrolu. Bez mapy nelze
> prokázat ani „jen schválené se zapnuly", ani „nezapnutý sourozenec zůstal v observe".

- Create: `plugins/aid-orchestrator/defaults/policies/control-inventory.yaml` — kanonický
  seznam ID kontrol C0-C4, a ke každému: policy soubor, **konkrétní čtenář** (soubor:funkce)
  a jestli je promovatelná. CP3 freshness je v seznamu s `promotable: false` a důvodem
  (žije v `_cp3_freshness_route`, ne v policy souboru) — nezpůsobilost se zapíše, nezamlčí.
- Modify: příslušné policy soubory (`c3-audit-policy.yaml`, `release-decision-policy.yaml`,
  `delivery-gate.yaml`, `review-profiles.yaml`) — přidat `controls.<id>.enforcement` a naučit
  **každého z pěti čtenářů** brát per-control hodnotu s fallbackem na souborový default.
  Flip JEN pro checky se `promote_to_blocking` v rozhodovací tabulce.
> **Dva konzumenti, které tenhle krok DLUŽÍ krokům 1 a 3** (cross-model verifikace EPICu 1,
> 2026-08-15). Obojí je dnes producent bez konzumenta a bez tohohle zápisu by se to ztratilo:
>
> 1. **`aid-e10-preflight.sh` nikdo nespouští.** Krok 1 ho postavil a brána §Preconditions B/5
>    ho vyžaduje, ale volající neexistuje. Promotion krok ho MUSÍ spustit a odmítnout postup
>    při `dirty` i `unproven` — `unproven` obzvlášť, protože to znamená „nešlo se podívat".
> 2. **`evidence_pack_freshness_policy` nikdo nečte.** Krok 3 ten klíč zavedl jako záznam
>    drženého observe-holdu. Promotion krok ho MUSÍ číst a při `observe` **odmítnout** promovat
>    C4 freshness pro třídu trailing commitu — jinak je hold jen komentář v YAML.

- **Sémantika agregátu u C4 (výslovně, protože jinak per-control mapa nic neoddělí):** C4
  blokuje na agregátu `release_ready`, takže vstup patřící NEPROMOVANÉ kontrole nesmí
  `release_ready` shodit. Jeho `input_state` se zaznamená a `verdict` zůstane, ale do
  agregátu nevstupuje, dokud ta kontrola není promovaná. Bez tohohle pravidla by první
  promovaný sourozenec zablokoval release za všechny ostatní.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — CP3 freshness dostane tutéž
  per-control vazbu ve své vlastní route (`_cp3_freshness_route`), protože do policy map
  nespadá. Bez toho je CP3 nepromovatelná a tak se zapíše do tabulky.
- Flip je gated na §Preconditions B (preflight clean + IMP-179 mechanický důkaz +
  IMP-201 resolved/observe-hold + rozpočet rozhodnut).
- Modify: `plugins/aid-orchestrator/scripts/` audit dispatch (Auditor) — **Codex honesty guard
  (D11):** není-li Codex CLI/cross-provider mechanicky dostupný+doložený → audit report
  `unverifiable`/`context_only`; „host má codex binary" ≠ důkaz reálného Codex dispatchi.
- Modify: `enforcement-registry.yaml` (nové řádky: e10_preflight, agent_freshness_check,
  evidence_freshness_exception, content_verdict_5state, e10_decision_table + per-check promoted
  flags; totals sync); **vydání se alokuje až za běhu** — číslo `2.56.0` z původního znění je
  dávno spotřebované jiným vydáním, takže se nepinuje vůbec. Platí registr osmi míst z
  `CLAUDE.md` (sedm nese verzi, osmé je licenční řádek, u kterého se kontroluje PŘÍTOMNOST) a
  ověřuje ho `scripts/tests/verify-version-files.sh <nová_verze> --baseline <stará>`.
  CHANGELOG ×2 identické; roadmap E10→DONE poznámka + E11 vstup (decision table).
- **D10 guard:** žádný legacy check se v E10 nemaže; `disabled-for-calibration` JEN s explicitním
  PM rozhodnutím zapsaným v decision-table.

**Acceptance Criteria:**
- [ ] Promotion flip observe→blocking JEN pro checky se `promote_to_blocking` v decision-table A splněnými branami §Preconditions B; ostatní zůstávají observe/dual-run (test: check bez schválení zůstane observe, **i když je ve stejném policy souboru jako promovaný sourozenec** — to je ta vazba, kterou globální přepínač neuměl).
- [ ] `control-inventory.yaml` pokrývá každou kontrolu C0-C4 a každé ID má uvedeného konkrétního čtenáře; kontrola v rozhodovací tabulce, která v inventáři chybí, je red.
- [ ] Test PRO KAŽDÉHO z pěti čtenářů: promovaný a nepromovaný sourozenec se chovají nezávisle.
- [ ] Vstup nepromované kontroly NEshodí `release_ready` (test agregátu), ale jeho `input_state` je v artefaktu zapsaný.
- [ ] Promotion krok SPUSTÍ `aid-e10-preflight.sh` a odmítne postup při verdiktu `dirty` NEBO `unproven` (test obou větví). Producent z kroku 1 tím dostává konzumenta.
- [ ] Promotion krok ČTE `evidence_pack_freshness_policy`; při `observe` odmítne promovat C4 freshness pro třídu trailing commitu (test). Bez toho je observe-hold z kroku 3 jen komentář.
- [ ] Promotion je HARD-gated na preconditions: preflight dirty NEBO nenulový agent-stale-count NEBO nevyřešený IMP-201 → promotion NEproběhne (blocking-promotion na agent-checkách blokován D5).
- [ ] Codex honesty: bez mechanického důkazu Codex dispatchi → audit report `unverifiable`/`context_only` (ne falešné „independent").
- [ ] Legacy netknuté (D10): git diff neukazuje mazání legacy kontrol; `disabled-for-calibration` jen s PM podpisem v decision-table.
- [ ] Registry totals == length; `verify-version-files.sh <nová_verze> --baseline <stará>` končí 0 (osm míst v souladu, obě CHANGELOG sekce identické); roadmap E10 označen DONE + decision-table jako E11 vstup. Žádné číslo verze není v plánu napevno.

**Effort:** L
**AID Role:** release

---

## Jak se to spouští — pořadí a kdo je volající

**Doplněno 2026-08-15 při závěrečném auditu zadrátování.** Nástroje E10 **nemají
a nemají mít** volajícího ve FSM: E10 je kalibrační BĚH, ne fáze pipeline.
Volajícím je operátor (nebo controller) podle tohohle pořadí. Bez téhle sekce by
„je to zadrátované?" nešlo zodpovědět jinak než hledáním v kódu — a odpověď
„nikdo to nevolá" by vypadala jako vada místo jako záměr.

```text
1. aid-e10-preflight.sh                 → e10-preflight.json
   (brána: dirty i unproven zastaví běh)
2. aid-e10-imp201-decision.sh           → imp201-decision.json
3. aid-control-metrics.sh               → control-metrics.json
   (nad kalibračním datasetem z kroku 6; --ground-truth manifest)
4. aid-dual-run.sh --outcomes <měření>  → dual-run-report.json
   (exit 1 = legacy chytil, co nový ne — D8)
5. aid-e10-decision-table.sh            → e10-decision-table.{json,md}
6. aid-e10-promote.sh                   → dry run; --apply až po PM rozhodnutí
```

**Dva nástroje mají volajícího ve FSM a jsou tam schválně:** rozšířený
`lib/aid-cache-preflight.sh` (běží při každém init/resume) a per-control
resolver `lib/aid-control-enforcement.sh` (šest čtenářů). To jsou trvalé
mechanismy, ne kroky běhu.

`merge-path-budget.json` **nevyrábí žádný z nich** — pole `measured_seconds`
naplní krok 5 z naměřených dob, ale `decision` je tvoje. Je to jediná brána,
kterou běh sám nevyrobí.

## Plan-level evidence — kde leží artefakty celého plánu

**Zavedeno re-groundem 2026-08-15 (C0 nález, severity medium).** Kritéria dřív četla
`${AID_EPIC_ID}/${AID_RUN_ID}`, jenže tyhle proměnné patří JEDNOMU EPICu a plán nikde
neřekl, který z pěti má dodat artefakty platné pro celý plán. Kritérium závislé na
nepřiřazené proměnné se nedá spolehlivě splnit.

Artefakty na úrovni plánu proto mají **jedno pevné místo**:

```text
.aid-o/work/evidence/P062/e10/
```

Patří sem: `e10-preflight.json`, `agent-freshness.json`, `imp201-decision.json`,
`control-metrics.json`, `merge-path-budget.json`, `dual-run-report.json`,
`c4-content-verdict.json`, `e10-decision-table.{json,md}`.
Per-EPIC běhové artefakty zůstávají tam, kde jsou (`<epic>/<run>/`) — tohle je adresář
pro to, co se vyhodnocuje jednou za plán.

## Acceptance Criteria

Plan-diff-spustitelný formát (`- [ ] ACn:` + `type: cmd`). Před implementací vrací absent/fail
(artefakty vznikají až během runu), NIKDY skip.

> **Re-grounding, druhý a poslední průchod (2026-08-15).** V prvním průchodu
> byly přepsané jen AC11 a AC12 (procházela naprázdno) a přibyly AC13/AC14.
> **Zbytek se dodělal teď: AC1 až AC10 jsou přepsané všechny.**
>
> Co bylo špatně: byly to kontroly, jestli existuje soubor, jestli se skript dá
> naparsovat a jestli nějaká sada skončila nulou. Takové kritérium projde nad
> špinavým preflightem stejně jako nad čistým a nad nespuštěným dual-runem
> stejně jako nad spuštěným — dokazovalo, že práce **vznikla**, ne že něco
> **zjistila**.
>
> Nová podoba je u všech stejná: kritérium čte **artefakt vlastního běhu**
> (`.aid-o/work/evidence/<epic>/<run>/…`) a ptá se na výsledek. Preflight musí
> mít verdikt, a je-li to `excluded_by_pm`, musí mít u každé výjimky důvod.
> Freshness musí prokázat **oba směry** (stale i fresh), ne jen zelenou sadu.
> IMP-201 musí nést **rozhodnutí** — buď `fixed` s pokrytým případem trailing
> commitu, nebo `observe_hold` se zdůvodněním; zelený test výjimky sám o sobě
> rozhodnutí není. C4 musí mít **odehraných všech pět stavů** a doložit, že
> `waived` i `present_but_failing` release blokují. Fixtury nesou provenienci
> místo počtu. Dual-run musí mít verdikty pro obě strany. Rozhodovací tabulka
> musí mít jedno rozhodnutí na kontrolu, každé s odkazem na důkaz, a bez
> duplicit.
>
> **Po tomhle průchodu nezbývá v tomhle bloku nic k dodělání.**

- [ ] AC1: Bookkeeping preflight existuje a je spustitelný (EPIC 1 Step 1).
  ```yaml
  type: cmd
  cmd: "f=.aid-o/work/evidence/P062/e10/e10-preflight.json; test -f \"$f\" || exit 1; jq -e '.verdict | IN(\"clean\",\"excluded_by_pm\")' \"$f\" >/dev/null && jq -e '(.checked | length) >= 4' \"$f\" >/dev/null && jq -e 'if .verdict == \"excluded_by_pm\" then ((.exclusions // []) | length) > 0 and all(.exclusions[]; (.reason // \"\") | length >= 20) else true end' \"$f\" >/dev/null"
  expected_exit: 0
  ```
- [ ] AC2: IMP-179 freshness — rozšířený cache preflight kryje `agents/`, obě strany (skew i shoda) jsou dokázané, a artefakt nese poctivý rozsah (EPIC 1 Step 2). **Sada je `test-cache-preflight.bats`, ne nová `test-agent-freshness.bats`:** kontrola se dopsala tam, kde ta rodina žije, takže tam žijí i její testy.
  ```yaml
  type: cmd
  cmd: "b=plugins/aid-orchestrator/scripts/tests/bats/test-cache-preflight.bats; test -f \"$b\" || exit 1; rc=0; out=$(bats \"$b\" 2>&1) || rc=$?; test $rc -eq 0 || exit 1; echo \"$out\" | grep -qE '^1\\.\\.[1-9]' || exit 1; echo \"$out\" | grep -q 'agents/ tree that differs HARD STOPS' || exit 1; echo \"$out\" | grep -q 'every covered tree identical the run still passes' || exit 1; f=.aid-o/work/evidence/P062/e10/agent-freshness.json; test -f \"$f\" || exit 1; jq -e '.preflight_ran == true and (.trees_checked | index(\"agents\")) != null and .stale_count != null and ((.scope_note // \"\") | length) > 0' \"$f\" >/dev/null"
  expected_exit: 0
  ```
- [ ] AC3: IMP-201 evidence-freshness-exception suite zelená (EPIC 1 Step 3).
  ```yaml
  type: cmd
  cmd: "f=.aid-o/work/evidence/P062/e10/imp201-decision.json; test -f \"$f\" || exit 1; d=$(jq -r '.decision // \"\"' \"$f\"); case \"$d\" in fixed) b=plugins/aid-orchestrator/scripts/tests/bats/test-evidence-freshness-exception.bats; test -f \"$b\" || exit 1; rc=0; out=$(bats \"$b\" 2>&1) || rc=$?; test $rc -eq 0 && echo \"$out\" | grep -qE '^1\\.\\.[1-9]' && jq -e '.trailing_commit_case_covered == true' \"$f\" >/dev/null ;; observe_hold) jq -e '.c4_freshness_enforcement == \"observe\" and ((.reason // \"\") | length >= 20)' \"$f\" >/dev/null ;; *) exit 1 ;; esac"
  expected_exit: 0
  ```
- [ ] AC4: aid-control-metrics.sh existuje + kvalitní metriky suite zelená (EPIC 2 Step 4).
  ```yaml
  type: cmd
  cmd: "m=.aid-o/work/evidence/P062/e10/control-metrics.json; test -f \"$m\" || exit 1; jq -e '(.controls | length) >= 5 and all(.controls[]; (.control != null) and (.caught_classes != null) and (.false_done != null) and (.false_positives != null) and (.cost_seconds != null) and (.unique_detection_vs_legacy != null))' \"$m\" >/dev/null || exit 1; rc=0; bats plugins/aid-orchestrator/scripts/tests/bats/test-control-metrics.bats >/dev/null 2>&1 || rc=$?; test $rc -eq 0"
  expected_exit: 0
  ```
- [ ] AC5: Speed metriky přítomné ve výstupu (EPIC 2 Step 5) — control-metrics.json má speed sekci s 6 poli.
  ```yaml
  type: cmd
  cmd: "m=.aid-o/work/evidence/P062/e10/control-metrics.json; test -f \"$m\" || exit 1; jq -e '.speed | (.dispatch_count != null) and (.llm_calls != null) and (.merge_path_seconds > 0) and (.plan_final_seconds != null) and (.nightly_seconds != null) and (.median_gate_cycle != null) and (.baseline_seconds != null) and (.e10_added_seconds != null) and (.fast_mode == \"not_measurable\")' \"$m\" >/dev/null"
  expected_exit: 0
  ```
- [ ] AC6: Kalibrační dataset fixtury existují (původní + grounded nové) (EPIC 3 Step 6).
  ```yaml
  type: cmd
  cmd: "man=plugins/aid-orchestrator/scripts/tests/fixtures/e10-calibration/manifest.json; test -f \"$man\" || exit 1; jq -e '(.fixtures | length) >= 6 and all(.fixtures[]; (.source_incident // \"\") != \"\" and (.failure_class // \"\") != \"\" and (.control // \"\") | IN(\"positive\",\"negative\") and (.expected_old != null) and (.expected_new != null)) and all(.fixtures[]; .grounded == true or ((.excluded_reason // \"\") | length >= 10))' \"$man\" >/dev/null; r=$?; test $r -eq 0 && for fx in $(jq -r '.fixtures[] | select(.grounded == true) | .path' \"$man\"); do test -e \"plugins/aid-orchestrator/scripts/tests/fixtures/e10-calibration/$fx\" || exit 1; done"
  expected_exit: 0
  ```
- [ ] AC7: Dual-run harness + legacy_unique_catch detekce (EPIC 3 Step 7).
  ```yaml
  type: cmd
  cmd: "d=.aid-o/work/evidence/P062/e10/dual-run-report.json; test -f \"$d\" || exit 1; jq -e '(.pairs | length) > 0 and all(.pairs[]; (.old_result != null) and (.new_result != null) and (.divergence != null)) and (.legacy_unique_catch != null)' \"$d\" >/dev/null"
  expected_exit: 0
  ```
- [ ] AC8: C4 content-verdict 5-stav + waiver-visible-not-pass suite zelená (EPIC 4 Step 8).
  ```yaml
  type: cmd
  cmd: "c=.aid-o/work/evidence/P062/e10/c4-content-verdict.json; test -f \"$c\" || exit 1; jq -e '[.states_exercised[]] as $s | ([\"missing\",\"stale\",\"invalid\",\"present_but_failing\",\"present_ok\"] | all(. as $need | $s | index($need) != null)) and (.waived_verdict_exercised == true) and (.waived_blocks_release == true) and (.present_but_failing_blocks_release == true)' \"$c\" >/dev/null && rc=0; bats plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats >/dev/null 2>&1 || rc=$?; test $rc -eq 0"
  expected_exit: 0
  ```
- [ ] AC9: Gate-profile speed kalibrace + escalation suite zelená (EPIC 4 Step 9).
  ```yaml
  type: cmd
  cmd: "m=.aid-o/work/evidence/P062/e10/control-metrics.json; jq -e '.profile_calibration | (.baseline_source == \"p063\") and (.savings_seconds != null) and (.escalation_proven == true) and (.scope == \"aid_run_only\")' \"$m\" >/dev/null && rc=0; bats plugins/aid-orchestrator/scripts/tests/bats/test-e10-profile-calibration.bats >/dev/null 2>&1 || rc=$?; test $rc -eq 0"
  expected_exit: 0
  ```
- [ ] AC10: Rozhodovací tabulka generátor + 5 rozhodnutí (EPIC 5 Step 10).
  ```yaml
  type: cmd
  cmd: "t=.aid-o/work/evidence/P062/e10/e10-decision-table.json; test -f \"$t\" || exit 1; jq -e '(.controls | length) >= 5 and all(.controls[]; (.decision != null) and ((.evidence_refs // []) | length) > 0) and ((.controls | map(.control) | unique | length) == (.controls | length))' \"$t\" >/dev/null"
  expected_exit: 0
  ```
- [ ] AC11: Promotion gated na preconditions + Codex honesty + **vydání alokované za běhu**
  (EPIC 5 Step 11). **Přepsáno re-groundem 2026-08-14:** původní znění pinovalo
  `2.56.0` a jeho CHANGELOG půlka **procházela naprázdno** — `## [2.56.0]` je
  v souboru dávno, z nesouvisejícího vydání, takže AC bylo splněné bez jediného
  řádku E10, zatímco jeho `plugin.json` půlka byla bez zpětného kroku
  nesplnitelná. Číslo se proto nepinuje vůbec: AC ověří, že **verze v
  `plugin.json` je zároveň nejnovější hlavičkou CHANGELOGu** a že ta sekce
  jmenuje E10.
  ```yaml
  type: cmd
  cmd: "v=$(jq -r .version plugins/aid-orchestrator/.claude-plugin/plugin.json); test -n \"$v\" || exit 1; base=$(git merge-base origin/main HEAD 2>/dev/null || git merge-base main HEAD); old=$(git show \"$base\":plugins/aid-orchestrator/.claude-plugin/plugin.json | jq -r .version); bash plugins/aid-orchestrator/scripts/tests/verify-version-files.sh \"$v\" --baseline \"$old\" >/dev/null || exit 1; awk -v v=\"$v\" '$0 ~ \"^## \\\\[\"v\"\\\\]\"{f=1;next} f&&/^## \\[/{exit} f' CHANGELOG.md | grep -qiE 'E10|control-metrics|decision table|promotion'"
  expected_exit: 0
  ```
- [ ] AC12: Legacy netknuté (D10) — žádné mazání legacy kontrolních skriptů **za běhu E10**.
  **Přepsáno re-groundem 2026-08-14:** kotva `v2.55.0` je 31 vydání stará a dnes
  vrací nula smazání i ve stavu, kdy z E10 neexistuje **nic** — dokazovala tedy
  historii, ne chování E10. Kotvou je výchozí commit vlastního běhu.
  ```yaml
  type: cmd
  cmd: "base=$(git merge-base origin/main HEAD 2>/dev/null || git merge-base main HEAD); test -n \"$base\" || { echo 'AC12: no branch point to anchor on'; exit 1; }; del=$(git diff --name-only --diff-filter=D \"$base\"..HEAD -- plugins/aid-orchestrator/scripts/ plugins/aid-orchestrator/agents/ | wc -l); test \"$del\" -eq 0"
  expected_exit: 0
  ```
- [ ] AC13 (nové): Rozhodovací tabulka má pro každou kontrolu C0-C4 **právě jeden**
  výsledek z šesti, a `unverifiable` verdikty C3 se sledují zvlášť, ne jako ne-fail.
  Šestým výsledkem je `cannot_promote_runtime_budget` — merge cesta je dnes 81 %
  nad rozpočtem ještě před E10, a tabulka na to musí mít slovo.
  ```yaml
  type: cmd
  cmd: "t=.aid-o/work/evidence/P062/e10/e10-decision-table.json; test -f \"$t\" || exit 1; jq -e 'if (.controls|length) < 5 then false else ([.controls[].decision] | all(. as $d | [\"promote_to_blocking\",\"keep_observe\",\"keep_dual_run\",\"defer\",\"remove_or_alias_in_E11_candidate\",\"cannot_promote_runtime_budget\"] | index($d) != null)) end' \"$t\" >/dev/null && jq -e '.c3_verdict_mix.unverifiable != null' \"$t\" >/dev/null"
  expected_exit: 0
  ```
- [ ] AC14 (nové): Rozpočtové rozhodnutí je zapsané, ne obejité — evidence běhu
  obsahuje naměřenou dobu merge cesty a jedno ze tří rozhodnutí PM.
  ```yaml
  type: cmd
  cmd: "f=.aid-o/work/evidence/P062/e10/merge-path-budget.json; test -f \"$f\" && jq -e '.measured_seconds > 0 and (.decision | IN(\"budget_raised\",\"path_reduced\",\"exception_recorded\"))' \"$f\" >/dev/null"
  expected_exit: 0
  ```

## Rizika

| Riziko | P | Dopad | Mitigace |
|---|---|---|---|
| ~~P061 nedokončeno~~ → **ZAVŘENO 2026-08-14.** Zbytkové riziko: Fast Mode zůstává neměřený (IMP-506) | M | M | vykázat jako `not_measurable`, nikdy jako 0; rozsah („platí pro `/aid-run`") napsaný ve výstupu |
| Merge cesta je 81 % nad rozpočtem dřív, než E10 začne | **H** | **H** | brána promotion §Preconditions B/8 + šestý výsledek tabulky `cannot_promote_runtime_budget` + AC14; přírůstek E10 se vykazuje odděleně od výchozího stavu |
| C3 vydává ve 3 ze 4 případů `unverifiable` → promotion na základě „skoro neblokuje" | **H** | **H** | `unverifiable` je vlastní metrika, ne ne-fail (AC10 + decision table); C3 nesmí být promován na základě datasetu, kde převažuje „nedalo se rozhodnout" |
| PM-cited incidenty (yq bypass, audit-log) se nedoloží → fabrikace | M | H | honest `not_grounded` skip, ground-first při EPIC 1/3, ne vymýšlet (D3) |
| Promotion zapnutá dřív, než IMP-179/IMP-201 vyřešené → blocking na stale/false | M | H | HARD precondition gate (D5, D6); promotion krok čte preflight + freshness + IMP-201 status |
| Content-verdict blocking rozbije stávající release-policy suite | M | M | default observe, flip jen promotion krokem; schema enum ověřit (P060 poučení) |
| Speed metriky neúplné → E10 se prohlásí za hotové bez důkazu rychlosti | M | M | D9: chybějící metrika → metrics report `incomplete`, ne tichý pass |
| Legacy check s unique detekcí omylem označen E11-remove | L | H | dual-run `legacy_unique_catch` guard (Step 7 AC); D8 řádek podložený daty |
| Codex independence fingovaná | M | M | D11 honesty guard: bez mechanického důkazu → unverifiable/context_only |

## Proces po napsání (stav)

Napsáno /aid-plan write. Dále (stejný rigor jako P059/P060): per-step vetting (adversariální, 1
agent/step + koherence) → CP1-deep (high-risk: fsm/state, policy, release) → nezávislý
/aid-verify-plan (kompletní check-table) → fix. **EPIC-gen a `/aid-run` až po lint/CP1/ověření re-groundu**
— **splněno 2026-08-14.** Zbývá poslední krok procesu: lint + CP1/C0 + nezávislé ověření
nad re-groundovaným zněním, a pak generování EPICů.

## Amendment (P068, 2026-07-26) — E10 precondition

The "all 6 EPICs complete" precondition counted EPIC-level releases. Under
`plan_branch` an EPIC merges into the plan branch and only the plan releases, so
the precondition is the plans own close marker plus its committed lifecycle
receipt, not six EPIC releases. P062 remained `write_only_until` its
preconditions were met; this amendment did not make it executable and did not
change its status.

**Superseded 2026-08-15 by the second re-grounding.** The condition this
amendment describes is now SATISFIED: P061 closed on 2026-08-14 with its
durable closure record, and the `write_only_until` lock is lifted in the
frontmatter. The amendment is kept for provenance — it was right about the
mechanism, and the re-grounding's Precondition A/1 implements exactly what it
prescribed: read the plan's own closure record, never a merge count.

This file is gitignored, so this note is for local readers. The durable record
is in `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`.
