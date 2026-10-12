---
zadani: P109
verze: 6
datum: 2026-10-09
autor: PM + AI
roadmapa: P109 → vydání 1 (tento soubor), vydání 2 „levnější run“ (P110), vydání 3 „bez EPICů“ (P111)
---

# P109 - plán drží zadání (vydání 1 roadmapy po experimentu P014)

Stav: **zadání pro plán**, 9. 10. 2026; verze 6 po dvou kolech kritika a dvou kolech kontroly plánu (AC4 říká, proti čemu brána kritika ověřuje bez kola)
(body „hotovo“ používají gramatiku, kterou plugin už má - `AC<n>` + `verification_pattern` - místo
nové; AC1, AC2, AC6, AC7, AC8 a AC10 říkají jen to, co mechanismus umí a co měření spustí).
Tvar souboru je převzatý ze společného zadání experimentu P014
(`docs/reference/2026-10-08-experiment-p014-zkousky/zadani-zuzene.md`), protože rameno A s ním
dodalo 9/9 a plán, který ho přepsal, 7/9. Tenhle soubor je první „zadání jako soubor“ a zároveň
vzor pro šablonu, kterou vydání 1 zavede.

## 1. Co PM chce

Doslova, 9. 10. 2026:

> „potřebuju aktuální /aid-run cestu zjednodušit tak, aby nestála tolik, ale dodala stejný výsledek
> jako cesta A … některé věci zbytečně … generování epiců a celkově ten epic rozpad … prvoproblém …
> špatně napsanej ten plán, nebo že ho špatně kontrolujeme, nebo že ho špatně revidujeme.“

> „What the fuck? Ty chceš zrušit plánování? A brainstorming? … Hlavně to zadání pro P14, pro Áčko,
> to proběhlo AID brainstormingem.“

> „potřebuju, aby ten aid prostě mi dodal … guard rails … ani mi nevadí, že to bude třeba o hodinu
> trvat dýl … stoprocentní kvalitu.“

> „Hlavně vše musí být zdokumentované (odstraňujeme EPICy): vnitřní dokumentace AID pluginu musí
> reflektovat všechny změny, včetně problémových cest, aby agenti, kteří vyvíjejí, věděli, co mají
> během vývoje dělat. … Žádné nové věci nesmí být jen dekorativní, protože víme, že to nefunguje.
> Pokud něco přidáváme nebo ubíráme, musí to být správně zadrátované.“

> „P109 nebude obsahovat vše: roadmapa a pak tři plány.“ — a k rozsahu 9. 10. 2026:
> „klidně to pak můžeme změřit čili 1b a 2a“ (1B: do vydání 3 přibývá druhá ověřovací úloha
> z druhé strany hranice; 2A: pořadí vydání 1 → 2 → 3 zůstává).

Jak to chápu: plánování a brainstorm zůstávají, protože právě ony dodaly zadání, se kterým rameno A
vyhrálo. Co se mění, je cesta od zadání k běhu: plán nesmí zadání přepsat, každá kontrola plánu
musí zadání vidět, a to, co AID hlídá za PM (pět mantinelů), musí mít mechanismus a dokumentaci
uvnitř pluginu. Vydání 1 dělá jen tu část, která se týká plánu a jeho kontroly; levnější běh
a odstranění EPICů jsou vydání 2 a 3 s vlastním zadáním.

**Co je v sázce:** každý další plán AID. Když plán zadání přepíše a nikdo to nevidí, PM platí
celý běh (v P014 150 USD a 6,5 h) za výsledek, který nechtěl, a sám pak hledá, kde se bod ztratil.
Když vydání 1 zadání udrží, má každý další plán levnější kontrolu (jedno kolo místo tří) a PM
důkaz, že mantinely drží bez něj.

Roadmapa (schválená vize `.aid-o/work/brainstorm/P109/vision.md`, V1-V7; stav mechanismů po každém
vydání v `.aid-o/work/interim-P109.md` „Stav po každém vydání“):

| Vydání | Co dodá | Hotovo, když |
|---|---|---|
| 1 (tento soubor) | plán drží zadání: zadání jako soubor, lint, kritik povinný, CP1 se zadáním, změny po kole proti zadání, deník mimo cestu, dokumentace | body AC1-AC11 níže |
| 2 „levnější run“ (P110) | CP2 podle druhu kroku (fail-closed), brány s testy projektu, bez CP3 a integrační revize EPICu, uzávěr s měřičem a CP7 o dvou rolích, měřič hned po kroku, bezpečnostní revize nad smazanými kontrolami | úloha jako P014 projde během za ≤ 75 USD a ≤ 3,5 h aktivně při 9/9 a se všemi pěti mantinely spuštěnými; pořadí kvalita → čas → cena: běh s méně než 9/9 nebo s vynechaným mantinelem neprojde |
| 3 „bez EPICů“ (P111) | běh rovnou z plánu na větvi plánu, bez generace, fronty a merge EPICu; `repo_roots` a jeden manifest kandidáta přes repa; cesta zrušení plánu až do FSM a active-runs; inventura kontrol EPIC cesty před smazáním (přebírá P104) | `/aid-run P###` projde na plánu bez `.aid-o/tasks/`; generátory nejsou v pluginu; řádky skriptů a skillů před/po; zopakovaná úloha P014 a jedna vícerepová úloha (PM 1B) projdou s 9/9 |

## 2. Změřený výchozí stav (ověřeno v kódu pluginu 2.114.0 a v repu `main` 73f0f0c4, 9. 10. 2026)

- **Balík kontroly plánu (CP1) nese jen plán a kontrolní zprávy**, zadání PM v něm není:
  `plugins/aid-orchestrator/scripts/lib/aid-plan-review-packet.sh:33-74` (`aid_plan_review_packet_build`
  kopíruje `plan.md`, `plan-check.json`, `standards.md`, `lint.txt`, a `critic-response.md`, když kontrola
  kritika prošla). Žádná z šesti rolí (`skills/plan-review-roles.md:106-226`) se neptá na zadání.
- **Kritik není povinný**: `aid-cp1-gate.sh` (222 řádků) slovo „critic“ neobsahuje; `prepare` bez
  kontroly kritika jen zapíše větu do `critic-note.txt` (`aid-plan-review-packet.sh:63-78`). V P014
  kritik neběžel a nic to nezastavilo. Brána má dvě třídy selhání: `_fail` (přepsatelné `--force` při
  generaci) a `_hard` (nepřepsatelné), a při vypnuté kontrole plánu končí časným návratem (ř. 116).
- **Prompt kritika říká „zapiš soubor“** (`lib/aid-critic.sh:146-147`); Codex v read-only sandboxu
  ho nezapíše a `-o` uloží stížnost (9. 10. 2026, `.aid-o/work/aid-plugin-issues.md`). `aid_critic_prepare`
  čte interim (`## Zadání PM`, `## Účel a co je v sázce`), který se po CP1 maže.
- **Plugin už má gramatiku strojově ověřitelného kritéria**: `- [ ] AC<n>: <text>` pod
  `## Acceptance Criteria` + blok ```` ```yaml verification_pattern: ```` (`type: cmd|must_not_exist|must_contain`,
  `cmd`, `expected_exit`, `file`, `regex`); `aid-plan-check.sh` A6 (ř. 278-296) ověřuje tvar,
  `aid-plan-diff.sh` je spouští na konci EPICu jako bránu `plan_diff` s limitem času na kritérium
  (ř. 91-97, 174-199). V P014 C stála brána „skipped, 27 odrážek neměřeno“, protože plán bloky neměl.
- **Lint plánu nesrovnává kritéria se zadáním**: `aid-plan-lint.sh` (772 řádků) kontroluje tvar
  Files, Reuse check, zakázané sekce (ř. 339), standardy a dokumentační plochy. Čtečka frontmatteru
  existuje jedna: `_aid_fm_get` (`lib/aid-roots.sh:248`).
- **„AID Role“ kroku jde do `plan.json` přes tabulku EPICu**: `aid-plan-to-epic.sh:901-906` čte
  pole z kroku a staví řádek tabulky (ř. 1166, hlavička ř. 1485, pět sloupců), `aid-epic-to-json.sh:214-222`
  tabulku čte s tvrdou kontrolou pěti sloupců; kořen `plan.json` nese `source_plan` (ř. 821-830).
- **Změna plánu po kole** (`aid-review-round.sh fix-check`, ř. 1120-1158) odmítne jen krok, Files
  a akceptační kritérium mimo seznam oprav. **Rozšíření rozsahu za běhu** (`aid-fsm.sh cmd_amend_scope`,
  ř. 5405-5549) chce důvod o 20 znacích, ve stavu GATES přiřadí rozšíření poslednímu kroku (ř. 5477-5481)
  a zapíše pole záznamů do `scope-amendment.json` (ř. 5515).
- **Výchozí počet kol CP1 jsou dvě** (`review-checkpoints.yaml:27`); smyčka brány odmítne každé kolo
  nad výchozí počet bez `override.json` (`aid-cp1-gate.sh:151-155`) a kolo 1 s otevřeným blockerem bez
  kola 2 (ř. 189). Čtečka politiky zná jen vyjmenované klíče (`lib/aid-review-config.sh:43`). V P014 stála
  tři kola 45 USD a 51 min a změkčení bodu 2 neviděla; zkouška P2 8. 10. s revizorem se zadáním ho našla.
- **Deník a sonda**: `aid-review-round.sh:387-400` odmítne `prepare`, když se `aid-plugin-issues.md`
  liší mezi kořenem stavu a pracovní kopií; cesta deníku už dnes vede do kořene stavu
  (`lib/aid-plugin-issues.sh:32-35`, `aid_state_path`), takže past je jen ta kontrola; sonda
  `lib/aid-codex-transport.sh:68` píše `codex-probe.json` do `${AID_PROJECT_ROOT:-$PWD}`, tedy do
  pracovní kopie. Zápisy: agents P013-3, P013-5, P013-12, 7. 10. 2026, P108 bod 17.
- **Kdo dnes připravuje kola bez kritika**: `test-review-round.bats:29-36` (pomocník `_plan`),
  `test-artifact-obligation.bats:39-43`, `test-generation-finalize.sh:60`, `test-roots-worktree.bats:71`,
  final-boundary, final-decide, round-fsm, consumers, generation-labels, plan-review-acceptance
  a testbed `/opt/eco/projects/aid-testbed/bin/verify.sh`; `aid-artifact-obligation.sh:110` pouští bránu
  při každé kontrole stránky.
- **Registr vynucení** má 590 řádků, pole `test:` s cestou `scripts/tests/…` (jen takové
  `test-enforcement-registry-cites.sh:427` ověřuje); `help-index.yaml` 228 řádků; fixture odmítnutí
  `scripts/tests/fixtures/refusals/measured-2026-09.tsv` má tři sloupce `count<TAB>event<TAB>snake_case`.
- **Velikost pluginu**: 71 195 řádků `scripts/*.sh` + `scripts/lib/*.sh`, 8 169 řádků `skills/`,
  5 699 řádků `commands/`; 215 sad bats; patro t0 běží 175 s při rozpočtu 120 s. Noční běh 9. 10. 2026:
  12 červených sad, všechny t2, mezi nimi `test-help-index-coverage`, `test-instruction-closure`,
  `test-enforcement-registry-cites`, `test-aid-plan-summary` (streak 3-9, „known“).
- **P104** (`.aid-o/plans/P104-milestones-instead-of-epics.md`, 27. 9. 2026, 8 kroků, draft) řeší běh
  z plánu po milnících *vedle* EPICů; CLAUDE.md nese odstavec „Odložená přestavba EPICů na milníky“.
- **Experiment P014** (agents, 7.-8. 10. 2026): A 9/9 za 1:06 a 44,5 USD; B 8/9; C 7/9 za 3:34
  aktivně a ~70 USD, plán před rameny ~3 h a ~80 USD. Příčiny v
  `docs/reference/2026-10-08-experiment-p014-analyza.md` §2.4 a §6.

## 3. Co udělat

Pořadí je doporučené; závislosti jsou u položek.

**(1) Zadání jako soubor.** Brainstorm i `/aid-plan write` začínají zápisem souboru
`.aid-o/plans/P<NNN>-zadani.md` se šesti částmi v tomhle pořadí: Co PM chce (doslova, s odstavcem
„Co je v sázce“), Změřený výchozí stav, Co udělat, Kde co je, Pravidla práce, Hotovo když. Každý
bod „hotovo“ je `- [ ] AC<n>: <text>` a pod ním blok `verification_pattern` v gramatice, kterou plugin
má (A6 v `aid-plan-check.sh`, běžec `aid-plan-diff.sh`). Šablona `defaults/templates/zadani.md`.
Lint (`aid-plan-lint.sh --zadani <soubor>`) odmítne soubor bez změřeného stavu, bez odstavce „Co je
v sázce“, bez bodu hotovo, s bodem bez `AC<n>`, s mezerou nebo duplicitou v číslování a s blokem,
který neprojde A6 (jedna implementace A6 v knihovně, obě kontroly ji volají).

**(2) Plán nese zadání doslova.** Plán má ve frontmatteru `zadani:` (cesta) a `zadani_sha256:`;
`## Acceptance Criteria` obsahuje každý bod `AC<n>` zadání stejným textem i blokem (přepsání,
sloučení a vynechání lint odmítne; plán smí body jen přidat od `AC<n+1>`); každý krok má pole
`**Zavírá:** AC<n>[, AC<m>]` a každý bod zavírá aspoň jeden krok; pole jde přes tabulku EPICu
(šestý sloupec) do `plan.json` jako `zavira`, a kořen `plan.json` nese `zadani` a `zadani_sha256`.
Oddíly Architecture, Data Model a API Design, pokud jsou, nesou `**Odvozeno z:** AC<n>` a rozhodnutí
měnící výsledek pro uživatele je označené `(mění výsledek pro uživatele)`; stránka PM obě věci
vypíše. Závisí na (1).

**(3) Kritik povinný a nepřepsatelný.** `aid-review-round.sh prepare --plan` kolo 1 odmítne bez
prošlé kontroly kritika pro plán, který do kola vstupuje, a zapíše otisk do manifestu kola; brána
CP1 to ověřuje jako nepřepsatelnou třídu (`_hard`) a před časným návratem při vypnuté kontrole
plánu; kola připravená staršími verzemi (bez otisku v manifestu) se zpětně nehlídají. Jeden verdikt
(`aid_critic_verdict`) sdílí balík i brána. Kritik nad plánem čte zadání ze souboru (ne z interimu),
Codex běží přes sdílený transport (`_run_codex_isolated`) s promptem „vypiš, nezapisuj“, záskok
(STAND-IN) při nenulovém kódu nebo méně než dvou nadpisech. Testy a testbed, které kola připravují,
dostanou jednoho sdíleného pomocníka pro zasetí prošlé kontroly.

**(4) CP1 se zadáním a kratší.** Balík nese `zadani.md` (cesta uvnitř projektu, jinak odmítne)
a jeho otisk; každá ze šesti rolí má jako první otázku „bod po bodu AC<n>: plán zachovává / změkčuje /
vypouští / odporuje?“ s důkazem `zadani.md:<řádek>` + `plan.md:<řádek>`; změkčení, vypuštění a rozpor
je blocker. Výchozí počet kol je jedno; kolo 2 je dovolené bez přepisu PM jen po kole 1 s otevřeným
blockerem a po `fix-check` (čtečka politiky zná klíč, smyčka brány to zná). Brána odmítne, když se
otisk zadání v balíku liší od souboru. Závisí na (1), (2), (3).

**(5) Změny po kole a za běhu proti zadání.** `fix-check` po kole pustí na opravený plán kontrolu
z (2) (jedna implementace): bod zadání se v plánu mění jen tak, že se změní soubor zadání
(`verze` +1, nový otisk ve frontmatteru) - jinak odmítne. U plánu vázaného na zadání (`plan.json`
nese `zadani_sha256`) `amend-scope` odmítne krok bez bodu i důvod bez `AC<n>` kroku (ve stavu GATES
sjednocení bodů všech kroků) a zapíše `AC<n>` do záznamu jako stopu; plán bez vazby zapíše `null`.
Závisí na (2).

**(6) Deník a sonda mimo cestu.** `codex-probe.json` se píše do kořene stavu; kontrola dvou kopií
deníku v `prepare` odpadá; `/aid-init` zapíše `.gitattributes` řádek `merge=union` pro deník
(funkce v `lib/aid-plugin-issues.sh`).

**(7) Dokumentace uvnitř pluginu a mimo něj.** `commands/aid-plan.md`, `skills/brainstorming.md`,
`skills/plan-writing.md`, `skills/pipeline.md` §„When AID refuses“ (každý nový odmítavý výstup
řádek s `next:`, fixture odmítnutí ve třech sloupcích), `defaults/help-index.yaml`, registr vynucení
(řádek s cestou k testu pro každý mechanismus), Docusaurus `/aid/commands/aid-plan`,
`/aid/skills/brainstorming`, `/aid/skills/critic`, nová stránka `/aid/specs/zadani` a tabulka pěti
mantinelů v `/aid/architecture/mantinely`. Roadmapa `docs/plans/2026-10-09-roadmapa-p109.md`; P104 do
`docs/archive` s hlavičkou; odstavec „Odložená přestavba“ z CLAUDE.md pryč. Pět nočních červených sad
z AC8 zelených před vydáním, bez odkladu.

**(8) Příprava vydání 2.115.0.** CHANGELOG s řádky skriptů, skillů a příkazů před a po, 8 míst
registru verzí (`verify-version-files.sh 2.115.0`), suchý běh vydávacího skriptu; tag a push vznikají
při uzávěru plánu na slovo PM (plán je `plan_branch`).

**Co do tohohle zadání nepatří** (vydání 2 a 3, vlastní zadání): spouštění bloků `verification_pattern`
po kroku a v uzávěru (dnes běží jen na konci EPICu), CP2 podle druhu kroku, brány s testy projektu,
CP3 a integrační revize EPICu, CP7 o dvou rolích, bezpečnostní revize nad smazanými kontrolami,
odstranění generace EPICů a fronty, `repo_roots`, cesta zrušení plánu do FSM, migrace starých EPIC
běhů (PM: dokončí mimo AID), paralelní vlny, „perky Claude Code“, /aid-do, /aid-ui, companion.

## 4. Kde co je

| Co | Kde |
|---|---|
| balík CP1 a prompt rolí | `plugins/aid-orchestrator/scripts/lib/aid-plan-review-packet.sh` (`aid_plan_review_packet_build` ř. 33, `aid_plan_review_prompt_render` ř. 119) |
| role CP1 a jejich otázky | `plugins/aid-orchestrator/skills/plan-review-roles.md` ř. 106-226 |
| kola revize | `plugins/aid-orchestrator/scripts/aid-review-round.sh` (`cmd_prepare` ř. 318, twin check ř. 387-400, `cmd_fix_check` ř. 1120) |
| brána CP1 | `plugins/aid-orchestrator/scripts/aid-cp1-gate.sh` (`_fail`/`_hard` ř. 89-90, časný návrat ř. 116, smyčka kol ř. 148-158, blocker bez kola 2 ř. 189) |
| kritik | `plugins/aid-orchestrator/scripts/lib/aid-critic.sh` (`_aid_critic_heading_count` ř. 70, `aid_critic_prepare` ř. 95, `aid_critic_check` ř. 169, `aid_critic_rebind` ř. 282), `skills/critic.md` |
| transport Codexu | `plugins/aid-orchestrator/scripts/lib/aid-codex-transport.sh` (`aid_codex_probe` ř. 61, sonda ř. 57-68, `_run_codex_isolated` ř. 115) |
| lint, kontrola plánu, běžec kritérií | `plugins/aid-orchestrator/scripts/aid-plan-lint.sh`, `aid-plan-check.sh` (A6 ř. 278-296), `aid-plan-diff.sh`, `aid-generation-readiness.sh` |
| čtečky | `plugins/aid-orchestrator/scripts/lib/aid-roots.sh` (`_aid_fm_get` ř. 248, `aid_state_root`), `lib/aid-scoping.sh` (`_aid_plan_section` ř. 224, `_aid_plan_step_field` ř. 329) |
| generace | `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (role ř. 901-906, řádek tabulky ř. 1166, hlavička ř. 1485), `aid-epic-to-json.sh` (tabulka ř. 214-222, kořen ř. 821-830), `defaults/templates/plan.schema.json` |
| rozšíření rozsahu za běhu | `plugins/aid-orchestrator/scripts/aid-fsm.sh` `cmd_amend_scope` ř. 5405-5549 (GATES ř. 5477-5481, záznam ř. 5515) |
| politika kol a její čtečka | `plugins/aid-orchestrator/defaults/policies/review-checkpoints.yaml` ř. 26-31, `scripts/lib/aid-review-config.sh` ř. 43 |
| deník | `plugins/aid-orchestrator/scripts/lib/aid-plugin-issues.sh` (`aid_plugin_issues_path` ř. 32) |
| stránka PM | `plugins/aid-orchestrator/scripts/lib/aid-plan-summary.sh` (`aid_plan_summary_render` ř. 266) |
| inventura promptů | `plugins/aid-orchestrator/scripts/aid-prompt-inventory.sh` (mapa citací ř. 51) |
| příkaz a skilly | `plugins/aid-orchestrator/commands/aid-plan.md`, `commands/aid-run.md`, `commands/aid-init.md`, `skills/brainstorming.md`, `skills/plan-writing.md`, `skills/pipeline.md` |
| registr, nápověda, fixture odmítnutí | `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`, `defaults/help-index.yaml`, `scripts/tests/fixtures/refusals/measured-2026-09.tsv` |
| testy | `plugins/aid-orchestrator/scripts/tests/bats/` (`test-plan-lint.bats` t2, `test-plan-check.bats` t2, `test-cp1-gate.bats` t1, `test-review-round.bats` t2, `test-critic.bats` t0, `test-codex-transport.bats`, `test-plugin-issues.bats`, `test-aid-fsm.bats`, `test-aid-plan-summary.bats` t2), `scripts/tests/test-epic-to-json.sh`, `scripts/tests/verify-version-files.sh`, `scripts/tests/run-all-tests.sh` |
| testbed | `/opt/eco/projects/aid-testbed/bin/verify.sh` (`--plugin <dir>`) |
| Docusaurus | `/opt/eco/docs/docs/aid/commands/aid-plan.md`, `/opt/eco/docs/docs/aid/skills/{brainstorming,critic}.md`, `/opt/eco/docs/docs/aid/architecture/`, `/opt/eco/docs/docs/aid/specs/` (dnes `artefakty.md`, `plan-ceremony-bands.md`) |
| roadmapa a P104 | `docs/plans/`, `.aid-o/plans/P104-milestones-instead-of-epics.md`, `CLAUDE.md` |
| pravidla přispívání a vydání | `CONTRIBUTING.md` (8 míst registru verzí, testbed, patra testů) |
| podklady | `docs/reference/2026-10-08-experiment-p014-analyza.md`, `docs/reference/2026-10-09-kam-s-aid.md`, `.aid-o/work/interim-P109.md`, `.aid-o/work/brainstorm/P109/`, `.aid-o/work/evidence/P109/cp1/round-1/merged.json` |

## 5. Pravidla práce

Platí `/opt/eco/CLAUDE.md` a `CONTRIBUTING.md` tohoto repa. Z nich pro tuhle práci nejvíc:

- **Běh přes AID** (`/aid-run`), ne mimo něj: tenhle plán je zkouška nové cesty.
- **Měř, nehádej.** Cesta, funkce ani řádek se neopisuje z paměti; každý mechanismus má test na
  odmítavé cestě a řádek v registru vynucení s cestou k testu.
- **Nic dekorativního.** Nová funkce, klíč nebo soubor má volajícího v kódu; věta v dokumentaci
  bez mechanismu se nepíše jako záruka. Co plugin už umí, se použije, ne vymyslí znovu.
- **Dokumentace je součást změny**: příkaz, skill, nápověda, Docusaurus a CHANGELOG ve stejném kroku
  jako kód.
- **Testy před vydáním**: T0 + T1 + dotčené sady; noční T2 jen na slovo PM. Nová sada nese patro.
- **Jeden revizor na kolo, Codex přes stdin a `-o`**; kolo se zavírá před opravou.
- **Merge, tag a push jen na slovo PM** (uzávěr plánu).

## 6. Hotovo, když

- [ ] AC1: `/aid-plan` (brainstorm i write) má jako první krok zápisu zadání `.aid-o/plans/P<NNN>-zadani.md` se šesti částmi a body `AC<n>` s blokem `verification_pattern`; `aid-plan-lint.sh --zadani` odmítne soubor bez změřeného stavu, bez odstavce „Co je v sázce“, bez bodu hotovo, s bodem bez `AC<n>`, s mezerou nebo duplicitou v číslování nebo s blokem mimo A6; a plán se `lifecycle_strict: true` bez `zadani:` neprojde kontrolou plánu (instrukce je vynucená až tam, ne při zápisu).
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "cd plugins/aid-orchestrator && bats scripts/tests/bats/test-zadani-lint.bats && bats scripts/tests/bats/test-plan-lint.bats --filter zadani-required"
    expected_exit: 0
  ```
- [ ] AC2: Lint odmítne plán, v jehož `## Acceptance Criteria` některý bod zadání není stejným textem a blokem (chybí, je přepsaný nebo sloučený), nebo který bod nezavírá žádným krokem; na dvojici zadání P014 + plán P014 skončí FAIL na bodu 2. Zeslabení nebo rozpor v textu kroku při zachovaném řádku lint nevidí - to je první otázka každé role CP1 (AC5) a je to blocker.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "cd plugins/aid-orchestrator && bats scripts/tests/bats/test-plan-lint.bats --filter zadani"
    expected_exit: 0
  ```
- [ ] AC3: Oddíly Architecture, Data Model a API Design plánu nesou `**Odvozeno z:** AC<n>`; každé rozhodnutí označené `(mění výsledek pro uživatele)` je na stránce PM v samostatném seznamu a stránka má tabulku bodů zadání s kroky, které je zavírají; lint odmítne oddíl bez řádku.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "cd plugins/aid-orchestrator && bats scripts/tests/bats/test-plan-lint.bats --filter odvozeno && bats scripts/tests/bats/test-aid-plan-summary.bats --filter zadani"
    expected_exit: 0
  ```
- [ ] AC4: `aid-review-round.sh prepare --plan` kolo 1 odmítne plán bez prošlé kontroly kritika pro plán vstupující do kola a zapíše otisk do manifestu kola; `aid-cp1-gate.sh` to ověřuje jako nepřepsatelné (`_hard`): proti otisku z manifestu kola 1, a když žádné kolo není (vypnutá kontrola plánu), proti aktuálnímu otisku plánu; kolo 1 připravené starší verzí (bez otisku) se nehlídá; `aid-critic.sh` spustí kritika přes sdílený transport Codexu a uloží odpověď, nebo vypíše řádek STAND-IN; kritik nad plánem čte zadání ze souboru.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "cd plugins/aid-orchestrator && bats scripts/tests/bats/test-critic.bats && bats scripts/tests/bats/test-cp1-gate.bats"
    expected_exit: 0
  ```
- [ ] AC5: Balík CP1 nese `zadani.md` (jen cesta uvnitř projektu) a jeho otisk, prompt každé role začíná otázkou bod po bodu (zachovává / změkčuje / vypouští / odporuje) a výchozí počet kol je jedno; brána po kole 1 bez blockeru projde, po kole 1 s blockerem a `fix-check` dovolí kolo 2 bez přepisu PM a odmítne, když se otisk zadání v balíku liší od souboru.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "cd plugins/aid-orchestrator && bats scripts/tests/bats/test-review-round.bats --filter zadani && bats scripts/tests/bats/test-cp1-gate.bats --filter round-2"
    expected_exit: 0
  ```
- [ ] AC6: `fix-check` pustí na opravený plán kontrolu z AC2 a odmítne změnu bodu zadání v plánu, která nejde ze změny souboru zadání (`verze` +1, nový otisk ve frontmatteru); u plánu vázaného na zadání (`plan.json` nese `zadani_sha256`, vyrobené generací ze souboru zadání) `amend-scope` odmítne krok bez bodu i důvod bez `AC<n>` kroku (ve stavu GATES sjednocení bodů všech kroků) a zapíše `AC<n>` do záznamu jako stopu (obsah rozšíření proti bodu posuzuje revize kroku, ne tenhle zápis); plán bez vazby zapíše stopu `null`.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "cd plugins/aid-orchestrator && bats scripts/tests/bats/test-review-round.bats --filter fix-check-zadani && bats scripts/tests/bats/test-aid-fsm.bats --filter amend-scope-zadani && bash scripts/tests/test-epic-to-json.sh"
    expected_exit: 0
  ```
- [ ] AC7: `codex-probe.json` vzniká v kořeni stavu i při volání z pracovní kopie; `prepare` se nezastaví o rozdíl dvou kopií deníku; `/aid-init` zapíše `merge=union` pro deník funkcí, která běží dvakrát beze změny.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "cd plugins/aid-orchestrator && bats scripts/tests/bats/test-codex-transport.bats scripts/tests/bats/test-plugin-issues.bats && bats scripts/tests/bats/test-review-round.bats --filter twin"
    expected_exit: 0
  ```
- [ ] AC8: Každý nový odmítavý výstup má řádek v `skills/pipeline.md` §„When AID refuses“ s `next:` a řádek ve fixture odmítnutí, každý mechanismus řádek v registru vynucení s cestou k testu, nápověda zná nové povrchy, Docusaurus má stránku zadání a tabulku pěti mantinelů; sady `test-help-index-coverage`, `test-instruction-closure`, `test-enforcement-registry-cites`, `test-aid-plan-summary` a `test-review-round-fsm` jsou na vydávaném commitu zelené.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "cd plugins/aid-orchestrator && for s in test-help-index-coverage test-instruction-closure test-enforcement-registry-cites test-aid-plan-summary test-review-round-fsm; do bash scripts/tests/run-all-tests.sh --only $s || exit 1; done"
    expected_exit: 0
  ```
- [ ] AC9: CHANGELOG 2.115.0 uvádí počet řádků `scripts/*.sh` + `scripts/lib/*.sh`, `skills/` a `commands/` před (71 195 / 8 169 / 5 699) a po vydání.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "grep -F '| scripts | 71 195 |' CHANGELOG.md"
    expected_exit: 0
  ```
- [ ] AC10: Vydání 2.115.0 je připravené: 8 míst registru verzí shodných (`verify-version-files.sh 2.115.0`), suchý běh vydávacího skriptu projde, testbed zelený na kandidátu (`aid-testbed/bin/verify.sh --plugin`); tag `v2.115.0` a push vznikají při uzávěru plánu na slovo PM.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "bash plugins/aid-orchestrator/scripts/tests/verify-version-files.sh 2.115.0 && bash plugins/aid-orchestrator/scripts/aid-release.sh minor --dry-run && bash /opt/eco/projects/aid-testbed/bin/verify.sh --plugin plugins/aid-orchestrator"
    expected_exit: 0
  ```
- [ ] AC11: P104 je v `docs/archive/` s hlavičkou „Archivováno 2026-10-… nahrazeno P109 a P111“, roadmapa je v `docs/plans/2026-10-09-roadmapa-p109.md` a CLAUDE.md odstavec „Odložená přestavba EPICů na milníky“ neobsahuje.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "test -f docs/archive/P104-milestones-instead-of-epics.md && test -f docs/plans/2026-10-09-roadmapa-p109.md && ! grep -q 'Odložená přestavba EPICů' CLAUDE.md"
    expected_exit: 0
  ```
