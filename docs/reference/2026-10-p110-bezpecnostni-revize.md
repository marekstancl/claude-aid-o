# P110 — bezpečnostní revize zúžení revizí (AID 2.116.0)

provider: claude (záskok za Codex — nezávislý agent s čistým kontextem; Codex měl vyčerpaný limit do 14. 10. 2026; PM 10. 10. 2026 „1B“: nezávislý Claude agent je odpovídající náhrada, jak to plugin dělá od P095)
model: claude-opus-5-5
datum: 2026-10-10
vstup: diff zúžení (politika revizí, čtečka konfigurace, kola revize, balíky, role, FSM, kontrola kroku, lifecycle) proti `main` 8126f4d9, zadání `.aid-o/plans/P110-zadani.md`; otázky role `step_security` a „co CP3 chytalo a kde se to chytá teď“.

## Nálezy

1. [blocker] Běh v režimu `legacy_epic_release_mode` nebo bez plánu s vypnutým CP3 projde až do vydání bez revize, když jsou všechny kroky pod prahem přeskočení (1A): `fsm_check_review_round` u cp3 vrací 0 a CP7 běží jen v `plan_branch`; routovaný blocker se uzavře libovolným textem (`aid_finding_resolve`).
2. [major] (1A) Bezpečnostní vzory nevidí typické díry a shoda se vzorem obsluhy (`handler_patterns`) verdikt neměnila: nová routa, `bash -c "$x"`, `eval "$x"`, `execSync(\`…${x}\`)` prošly jako `skip`; vstup v jednom malém kroku a jeho nebezpečné použití v dalším nevidí nikdo.
3. [major] Kontrolní seznam `final_generalist` v CP7 neměl injection přes víc kroků, cestu od volajícího a symlinky při mazání ani padělanou evidenci — třídy, které CP3 v P101/P102 skutečně našlo.
4. [major] `full_when` se jen zapíše do `round.json agents`, nevynutí: záznam dispatche typ podagenta nenese a `close` ho neporovná.
5. [major] Body kroku se čtou ze souboru plánu bez vazby na plán, ze kterého vznikl EPIC: controller může kritérium změkčit (`cmd: "true"`) nebo smazat a krok pak nic neměří.
6. [major] Kartu PM jde padělat (citace bodu + jakýkoli prompt PM po mtime souboru, mtime jde posunout); zamítnutý blocker pak s vypnutým CP3 nikdo znovu neuvidí.
7. [major] Zbylá nebo nově vzniklá složka `cp3/` s vypnutým CP3 schová před CP7 nálezy, které nechaly otevřené revize kroků (EPIC vypadá jako zrevidovaný s 0 nálezy).
8. [minor] Lifecycle s vypnutým CP3 bral jako záznam revize EPICu jen poslední krok: `fail` v dřívějším kroku zapsal `accepted`.
9. [minor] `record-tests` zapíše jako spuštěné všechny testy podle globů, i když běžec dostal výběr (`pytest -m smoke`) — štítek bez důkazu.
10. [minor] Základ rozsahu kroku je poslední `step_commit` v `timeline.jsonl`, kam píše i controller; podvržená událost zmenší krok pod práh (starší chování, vyšší práh ho zhoršuje).

## Co CP3 chytalo a kde se to chytá teď

- Injection, cesty, XSS v kroku nad prahem bez vzoru: lehký `step_security`; pod prahem nic (1A), ale krok se vzorem obsluhy už se nepřeskočí (nález 2) a nový vzor `shell_string_exec` vede k plnému revizorovi.
- Injection přes víc kroků: v `plan_branch` otázka 7 `final_generalist` (doplněná, nález 3); mimo `plan_branch` viz nález 1.
- Únik údajů do logu, hranice účtů, osobní údaje: kontrolní seznam CP7 (`plan_branch`).
- Opravy routovaných a přenesených blockerů a nálezy zamítnuté PM: balík CP7 (`epic-findings.json` `cp3: off`, stav `dismissed_by_pm`).
- Brány chytají jen to, co testy spustí; body kroku jen to, co tvrdí plán vázaný otiskem (nález 5).

## Vyřízení

1. Čeká na rozhodnutí PM (karta 10. 10. 2026: legacy a běh bez plánu s vypnutým CP3 — ponechat EPIC revizi s jednou bezpečnostní rolí, odmítnout vydání, nebo přijmout).
2. Opraveno v kroku 1/6 (commit dále): krok se shodou na `handler_patterns` je vždy `review` (`aid-step-check.sh`); nový bezpečnostní vzor `shell_string_exec` (`bash|sh -c`, `eval` proměnné, `exec`/`execSync` řetězce, `child_process`). Sčítání po sobě jdoucích malých kroků odmítnuto: dělení kroků řeší nález 1 a CP7.
3. Opraveno v kroku 4: otázka 7 `final_generalist` doplněná o injection napříč rozsahem (sledovat každý nový vstup k sinkům), cesty a symlinky, padělanou důvěru.
4. Odloženo do backlogu IMP-691 (stejná úroveň důvěry jako dnešní bracket dispatche, který zapisuje controller; skutečné vynucení patří do hooku).
5. Opraveno v kroku 2: `plan.json` nese `source_plan_sha256` plánu, ze kterého vznikl; `increment-step` měří jen z nezměněného plánu, jinak odmítne. Izolace na úrovni kroku zůstává mimo (plán: izolovaný je uzávěr).
6. Odloženo do backlogu IMP-692 (starší než P110); zmírněno v kroku 4: nálezy zamítnuté PM jdou do balíku CP7 jako `dismissed_by_pm`.
7. Opraveno v kroku 4: s vypnutým CP3 se složka `cp3/` nečte a bere se nejnovější běh.
8. Opraveno v kroku 6: rozhodují všechny kroky posledního běhu — jeden `fail` = `rejected`, jiný stav než pass/skip/no_change = `unverifiable`.
9. Opraveno v kroku 5: `record-tests` odmítne výběr testů v celém textu příkazu (i uvnitř `bash -c '…'` a přilepený k hodnotě, `-mfoo`, `-k=x`) a při nastaveném `PYTEST_ADDOPTS`/`BATS_TEST_FILTER`/`GOFLAGS`; `python -m pytest` výběr není. Hranice (automatická kontrola commitu 8fb38a15): je to seznam zakázaných voleb, skript-obal může testy vybrat i tak; úplný důkaz dává jen evidence, kterou zapisuje sám běžec (`run-all-tests.sh --evidence-file`, `aid-select-tests.sh`) — poznámka u IMP-691. `-t` (jest) zůstává zakázaný i za cenu falešného poplachu u jiných nástrojů (druhá kontrola commitu).
10. Odloženo do backlogu IMP-693 (starší chování).
