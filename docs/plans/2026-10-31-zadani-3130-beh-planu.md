# AID 3.13.0 – běh plánu bez ručních obchvatů (zadání)

Zdroj: rozbor plugin issues 31. 10. 2026, volby PM 3A-9A, 11A, 12B (body 12.1-12.4).
Živý seznam: `docs/plans/2026-10-31-roadmapa-plugin-issues.md`.

## Proč

Ve WANu (P114-P118, 25.-30. 10. 2026) se běh plánu opakovaně zasekl na místech, kde musel agent nástroj
obejít ručně. Stálo to zmrazení navíc, kola revize navíc a rozhodnutí zástupce navíc. Jeden zásek
(spor po pozdějším commitu) skončil kartou pro PM, kterou PM mít nechtěl. Cíl: tyhle cesty projdou bez obchvatu
a bez PM. Pojistky zůstanou, změní se jen místa, kde AID odmítá oprávněnou věc nebo odmítá pozdě.

## Co se staví (každý bod = jeden krok, revize po kroku)

Verze 7 po šesti kolech revize Codexem 31. 10. 2026 (značky [R1]-[R12], druhé kolo [R…b], třetí [R…c], čtvrté [R…d], páté [R…e], šesté [R…f]).

**Z3 – převzetí kroku a jména testů** (`scripts/aid-step-land.sh` ř. ~140-160 **a** `scripts/lib/aid-land-record.sh`
ř. ~48, která totéž kontroluje znovu v `increment-step` [R2]).
Jedna sdílená funkce rozhodne, jestli je bod příkazový, podle **záměru textu, ne podle dostupnosti programu**
[R1, R1b]. Pravidla v pořadí, první, které sedí, platí:
1. Text v backticku obsahuje mezeru, lomítko nebo začíná `JMÉNO=hodnota `: je to příkaz (`./check.sh`,
   `scripts/check.sh`, `VAR=v cmd`, `pytest -q x`, `make test`).
2. Jedno slovo bez mezery a lomítka je **vždy jméno**, ne příkaz (`test_regime_x`, `a::b`, `check.sh`, `pytest`).
   Nezáleží na tom, co je nainstalované [R1c]. Plán, který chce spustit samotný program, napíše jeho příkaz
   s argumentem nebo s cestou. Kontrola plánu (`aid-plan-lint.sh`) na jednoslovný bod začínající backtickem
   upozorní („jméno, ne příkaz“).
Klasifikaci počítá jedna funkce a záznam převzetí ji nese, takže `increment-step` rozhoduje stejně.

Pro příkazový bod platí, že chybějící program znamená selhání ověření, ne přeřazení. Nepříkazový bod se ověří
jako ostatní nepříkazové (záznam).

Náhrada příkazu: stávající `--check <k>:<příkaz>`. Když se příkaz liší od plánu, je povinný `--reason "<proč>"`
a záznam převzetí nese `{ac, plan_cmd, given_cmd, reason}`. `aid-land-record.sh` takový záznam přijme
a `increment-step` ho vypíše. Náhrada smí měnit prostředí, ne tvrzení bodu, a revize kroku ji vidí.

**Z4 – jména testů už v kontrole kroku** [R3; po revizi kroku 31. 10. změněno]
`aid-step-check.sh` použije existující `aid_test_names_plan_refs` (`lib/aid-test-tier.sh`), stejný kód jako brána
uzávěru, a to přesně nad úsekem, který revize hodnotí: `base..HEAD`, v `--worktree` neuložená změna proti HEAD
včetně nových souborů. Nalezené jméno **kontrolu kroku odmítne dřív, než začne kolo** (`step_test_named_after_plan`,
`agent_fix`), stejně jako to dělá brána. Původní návrh dávat jméno do kola jako nález kontroly kroku revize
kroku zamítla: takový nález v dalším kole nikdo nepotvrdí, kolo by se zaseklo, různé názvy v jednom souboru by
splynuly a nález by přebil bezpečnostní revizi.

**Z5 – prostředí stromů plánu a kroků** (`aid-plan-fsm.sh` ř. ~1075, `lib/aid-parallel*.sh`) [R4, R4b]
Do `project.yaml` přibudou dva klíče, oba s výchozí hodnotou `[]`:

- `worktree.copy_untracked: [".env", …]`:
  - cesty jsou relativní k repu a po kanonizaci leží uvnitř hlavního checkoutu i nového stromu, symlinky ven se
    odmítnou;
  - zdroj musí být neverzovaný a ignorovaný;
  - cíl smí chybět, jinak se přeskočí s hláškou a nic se nepřepíše;
  - opakované založení je idempotentní.
- `worktree.setup: ["cd ui && npm ci --prefer-offline", …]`: příkazy, které se po založení pustí **v novém
  stromu**. Závislosti tak jsou vlastní kopie, nic se nesdílí s hlavním checkoutem a zámkový soubor řeší
  instalátor. Selhání nezastaví běh: zapíše se do záznamu stromu, hláška řekne, který příkaz selhal,
  a kontrola kroku ho ukáže. Doba běhu se zapíše.

Napojování `node_modules` symlinkem se nedělá: sdílené soubory by šly měnit z obou stran. Nápověda `/aid-run`
řekne, že se měří ve stromu plánu.

**Z6 – konec tahu při čekání na revizory a opraváře na pozadí** (`lib/aid-hook-rules-turn.sh` ř. ~205-216,
`scripts/aid-emit-dispatch.sh`) [R5, R5b]
1. `aid-emit-dispatch.sh start` nonce vypíše (`nonce=<…> evidence=<dir>`). Stávající události časové osy
   (`verifier_dispatch_start/complete/cancel`, které čtou `_bracket_last` a `_dispatch_recorded`) **zůstanou
   pod svými jmény** a jen přibude pole `nonce` [R5c]. `complete` a `cancel` dostanou `--nonce`, které uzavře
   přesně ten záznam. **Všechny pokyny k dispatchi** (revizoři kroků a CP7, opraváři, zástupce v
   `commands/aid-run.md` a ve výstupech `prepare`) nonce ze `start` předají do `complete` a `cancel` [R5d].
   Bez `--nonce` platí dnešní chování jen pro starší volání. `AID-WAIT` uzná jen dispatch, jehož `start` nonce
   vypsal.
2. Opravář kroku dostane vlastní zaměření `fix-cp2-<krok>-r<kolo>` (opravář CP7 `fix-cp7-r<kolo>`) a pokyn
   v `commands/aid-run.md` ho uzavře do závorky start/complete jako ostatní dispatche.
3. `AID-WAIT` uzná dispatch k otevřenému kroku, když platí všechno:
   - výstup `start` s nonce a adresářem evidence je ve výsledku nástroje v přepisu **tohoto sezení** [R5c];
   - záznam s **přesně tímto** nonce v evidenci patří k otevřenému kroku a běhu a nemá `complete` ani `cancel`;
   - start je mladší než jeho `expected_duration_max` (jinak výchozí strop).

   Starší nonce se nikdy nepočítá, ani když nový skončil. Jiné volání na pozadí krok dál neomlouvá. Pravidlo se
   vejde do rozpočtu hooku.

**Z7 – `--also-steps`** [R6]
(a) `fix-check` při `fixes == any` nesloží `any,<kroky>`: nechá `any` a kroky zapíše jen do `fix-diff.json`.
(b) `finalize --also-steps` už funguje (`cmd_finalize` volá `_check_fix`), jen to nikde není napsané. Proto
dokumentace v `commands/aid-run.md` a `skills/pipeline.md` a regresní test (záznam ve `finalize.json`).

**Z8 – obnova `plan-merge-to-main`** (`cmd_plan_merge_to_main` ř. ~5769, `lib/aid-lifecycle.sh`) [R7-R9b]
Druhé spuštění po pádu pozná, že sloučení i lifecycle commit existují, a dokončí jen chybějící krok (označení
vydání). Kontroly rodičů a stromu sloučení zůstávají. Hlavní checkout se srovná na tip větve přes
`_aid_lc_sync_checkout_of`, upravené takto:
- selhání kvůli překrývající změně se **vrátí** jako chyba (dnes helper vrátí úspěch) a obnova se zastaví
  s výpisem souborů;
- záložní větev smí přidat do indexu jen vygenerované neverzované záznamy uzávěru (`.aid-lifecycle/**`), nic jiného;
- rozpracované, staged (s jiným obsahem než pracovní kopie) i neverzované změny zůstanou beze změny.

Verze a záměr vydání jsou ze záznamu ověřeného zmrazením (Z9).

**Z9 – záměr vydání a verze souběžných plánů** (`plan-finalize --stage freeze`, `plan-merge-to-main`)
[R8, R8b, R9c]
O záměru vydání rozhoduje **jen `prepare-plan`**, jako dnes (`_release_parse_args_and_resolve_bump`, včetně
`version: none` i `--bump none` = už připravené vydání). Zmrazení ani sloučení ho nepočítají znovu.
`release-prep.json` k záměru (`intent` release|none, `bump`, `version` = verze vydání nebo `none`) přidá
`candidate_version` (číselná verze, kterou kandidát v tu chvíli nese: první záznam `CHANGELOG.md` a manifest),
commit a strom kandidáta [R9e].
- **Obnova záznamu bez zvýšení verze** [R9d, R9e]: `prepare-plan --rebind` znovu přečte verzi, kterou kandidát nese.
  Když se rovná `candidate_version`, jen přiváže záznam k novému stromu. Záměr (`release` i `none`), verze
  i `bump` zůstanou a nic se nezvedne. Když se liší, odmítne (`release_prep_version_changed`, `agent_fix`).
  U záměru `release` napíše `next:` `prepare-plan --bump none` (vezme verzi kandidáta jako připravenou) nebo
  vrácení změny. U `none` [R9f] napíše `prepare-plan --rebind --adopt-version`: převezme novou
  `candidate_version`, ale záměr `none` i `version: none` zůstanou a automatické rozhodování o zvýšení se znovu
  nepouští. Druhá cesta je vrácení změny. `--adopt-version` se záměrem `release` odmítne.
- **Pořadí při zmrazení:**
  1. Záznam existuje a je čitelný, jinak `release_prep_stale` (`next:` `prepare-plan`).
  2. **Shoda verze** [R9e]: verze, kterou nese větev plánu, se rovná `candidate_version`, jinak
     `release_prep_version_changed` (viz výš). Tahle kontrola je před porovnáním s tagy, aby se nikdy nezvedalo
     podle zastaralé verze.
  3. Před `_pfsm_finalize_sync` (jinak přijde dřív konflikt v CHANGELOGu): má-li záměr `release`, verze se
     porovná číselně (`sort -V`) s nejvyšším tagem vydání projektu dosažitelným z cílové větve. Když není vyšší,
     zmrazení odmítne (`plan_version_not_above_target`, `agent_fix`, `next:` `prepare-plan --bump …`).
     Záměr `none` a projekt bez tagů projdou.
  4. `_pfsm_finalize_sync`.
  5. Vazba se ověří proti **konečnému** stromu po sloučení. Při jiném stromu zmrazení samo pustí `--rebind`
     (projde, jen když se verze nezměnila).

  Tím se chytí WAN P116: verze se po přípravě změnila na 0.46.0, záznam držel 0.45.0, a skončí to v bodě 2
  místo pádu při označení vydání.
- **Sloučení a jeho obnova** (Z8) berou verzi ze záznamu, který zmrazení ověřilo. Rozpor mezi záznamem
  a kandidátem je chyba, nikdy tichá náhrada.

Hlídání migrací patří do backlogu okna WANu.

**Z11 – spor po pozdějším commitu** (`aid-review-round.sh` ř. ~1705, `aid-review-adjudicate.sh`) [R10, R10b]
`delegate` u `delegation_fix_pending` zapíše ke sporu `dispute.handed_to_confirmation = {commit, reason, at}`.
Je to jen údaj o sporu: **nález zůstane otevřený a blokující**. Adjudikace při novém `collect` ten údaj zachová,
stejně jako `settled_by`. Kolo se pak uzavře obvyklou cestou nad zkontrolovaným commitem (`close --at <head kola>`,
protože HEAD se pohnul). U otevřeného blokujícího nálezu se uzavře jako neúspěšné. `next:` u delegate to řekne
přesně. Další kolo nález potvrdí nebo otevře nad změněným kandidátem. Kola navíc to nedává: po vyčerpání
rozpočtu platí dnešní cesta (`REVIEW_EXHAUSTED` → zástupce). Platí pro CP2 i CP7. **Po revizi kroku 31. 10.:** předání platí jen pro revizi kroku (CP2). V CP7 je oprava nový kandidát, takže zůstává původní odmítnutí a opravu posoudí potvrzení dalšího pokusu. Zástupce nikdy nesoudí opravu nad posunutým HEAD.

**Z12 – drobnosti**
1. `close --fixer` přijme roli s číslicí (`^[a-z][a-z0-9_-]*=`).
2. `amend-scope` bez zástupce [R11, R11b], **jen pro testovací soubory** (`test_*`, `*_test.*`, `*.test.*`, `*.spec.*`, `tests/`, `__tests__/`; zúženo po bezpečnostní kontrole 31. 10.: zmínka jiného souboru v bodu kroku neznamená svolení ho měnit), a jen pro kanonickou cestu bez symlinku ven:
   - pro cestu, kterou akceptační bod kroku jmenuje přesně (normalizovaná relativní cesta);
   - pro jméno souboru, které odpovídá **jedinému** souboru v celém repu (verzované i nové soubory kroku).

   Teprve pak se ověří rozsah kroku, chráněné dopady, zakázané cesty a cizí repozitáře, každá přidaná cesta zvlášť.
   Záznam se jmenuje `named_in_ac`.
3. Pokyn opraváři CP7 (`commands/aid-run.md` ř. ~980) dostane absolutní cestu `fix_of:` do state rootu a větu,
   že soubor leží mimo strom plánu.
4. `final_generalist` [R12, R12b]: odpověď dostane typované pole `security_and_operations` s položkou ke každé
   z devíti otázek bodu 7 v `skills/step-review-roles.md`:
   - položky jsou `personal_data`, `host_layout`, `ci_dependencies`, `docs_build`, `log_leaks`, `account_boundaries`,
     `injection`, `paths_deletion`, `forged_trust`;
   - každá má tvar `{answer: "none"|"checked"|"finding", note}`;
   - chybějící položka znamená `form_invalid` (role odpověď doplní), neznámá pole se dál odmítají;
   - zadání role tento tvar uvede, `collect` pole uloží.