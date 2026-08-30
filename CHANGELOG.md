# Changelog

All notable changes to the AID Orchestrator plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [2.95.9] — 2026-08-30

### Changed
- **Zápis problému pluginu nese verzi pluginu** — formát má řádek `**Plugin:** vX.Y.Z` (hlavička říká, kde verzi přečíst), soubor se při založení orazítkuje verzí, která ho vytvořila, připomínkový hook aktuální verzi vypíše a sběrný skript ji dá do nadpisu v inboxu. Za měsíc tak jde říct, zda byl bod zapsán před opravou nebo po ní – z data se to dovodit nedalo.

### Removed
- **Sběr compliance napříč projekty** — `aid-compliance-report.sh` (srovnání „ér“ před/po Session A/B z května, `--reflect` nad nadužíváním `--force`) a jednorázový `aid-compliance-backfill.sh`: čtyři měsíce je nikdo nezavolal a nadužívání `--force` se dnes čte z audit logu a ze souboru problémů pluginu. Zápis `compliance.json` po každém EPICu zůstává – čte ho kontrola P042 a C4.

## [2.95.8] — 2026-08-29

### Fixed
- **`transition` a delivery gate měřily HEAD hlavního repa, ne pracovní kopie běhu** — `cmd_transition` se nyní (stejně jako `advance-to-gates`) přesměruje do worktree plánu dřív, než cokoli čte; CP3 čerstvost tak porovnává správné revize. `aid-delivery-gate.sh` rozlišuje strom, který měří (`AID_GIT_TREE`, jinak cwd), od stavového kořene s evidencí; už neodvozuje kořen z vlastního instalačního adresáře, takže jde spustit i z worktree.
- **`targeted_tests` už nehlásí pass nad nulou testů** — mimo vlastní repozitář pluginu je výběr testů NEAKTIVNÍ: vrátí `relevance: inactive`, exit 2, a brána to zapíše jako skip (renderer konzumentského `execution.yaml` dostal `pass_criteria` s „exit 2 = skip"). Projekt s dřívější konfigurací bez té věty uvidí poctivý fail řádek brány (`required: false`, celkový výsledek nemění) — přidat větu, nebo namapovat svůj produkční povrch (backlog).
- **Validátor výstupu verifiéra poradí, když soubor leží v kořeni** — při „file missing" zkontroluje `cwd/<název>` a řekne, kam ho přesunout; nikdy ho odtud nepřijme. Dispatch pojmenovává výstup absolutní cestou (`agents/verifier.md`, `skills/pipeline.md`).

## [2.95.7] — 2026-08-29

### Added
- **`aid-fsm.sh rebase-plan`** — schválená cesta, jak přijmout plán přegenerovaný uprostřed EPICu: uzná ho jen když rozpracovaný krok i všechny hotové kroky odpovídají snímku z `init` (`step-hashes.json`), přerazítkuje otisk a zapíše od/do/důvod do `plan-rebase.json`, timeline i auditu; `base_commit` ani `current_step` nemění. Dosud dva projekty přepisovaly `plan_json_hash` ručně.

### Fixed
- **`--force` u `increment-step` už nepřeskočí samotnou evidenci kroku** — soubor `step-N-verify.md` a jeho struktura se kontrolují vždy; force obchází ostatní podmínky kroku (scope, vazbu evidence, kontrakt, vizuální a revizní kontroly) jako dřív. Dřív force zamaskoval krok, jehož verifikace se vůbec nezapsala (agents P001).
- **Pre-filter nepřepíše dokončený report verifiéra** — hotový report předchozí iterace (verdict pass/fail) se odsune na `verifier-output-step-N.iter-<čas>.md` místo přepsání; nálezy iterace 1 už nemizí.
- **`increment-step` bez argumentu** vypíše usage (exit 2) místo pádu na `$1: unbound variable`.
- **Report bran neříká „explicit --profile flag", když profil odvodil FSM** — `aid-run-gates.sh` má `--profile-reason` a `advance-to-gates` mu předá skutečný důvod (`FSM auto-resolved profile <name>`).
- **`aid-prefilter.sh classify` vypíše výsledek** — jedna řádka `classify: RUN|SKIP|FAIL step=N reason=… (exit K)` přes společný helper, dřív jen soubor a exit kód.

### Changed
- **Chyby verifikačního souboru se hlásí najednou** — všech pět strukturálních kontrol se posbírá a vypíše jedním hlášením (každá se svým auditním kódem), ne po jedné na každé spuštění.
- **`advance-to-gates` při selhání řekne důvod, ne 300 řádků JSON** — výpis reportu jde do souboru, na terminál jde verdikt, seznam spadlých bran a cesta k reportu; varování hooku o prázdném scope říká, že jde o `plan.json` a že kroky jsou číslované od nuly.
- **CP3 šablona uvádí `classification: FULL_REVIEW`** — validátor to pole vyžaduje, šablona i hláška ho dosud zamlčely (tři zbytečná kola verifiérů v agents); a návod k psaní plánu říká, že krok smí záviset jen na nižším čísle.

## [2.95.6] — 2026-08-29

### Added
- **Soubor pro problémy pluginu vzniká sám** — `.aid-o/work/aid-plugin-issues.md` (jeden na projekt, pro všechny jeho plány) založí `plan-start` i `aid-fsm.sh init` ze šablony, která má v hlavičce pravidla kdy a jak psát; agent píše do existujícího souboru, do chybějícího ne.
- **Připomínka na konci tahu** — Stop hook `plugin_issues_reminder` (stupeň 3, nikdy neodmítá) řekne jednou za session: „AID N× odmítl nebo byl obejit a soubor se nezměnil — pokud šlo o chybu pluginu, zapiš ji"; nová událost připomínku znovu otevře. Zápis se nevynucuje (PM: chybějící zápis nic nestojí).
- **Řádek ve `/aid-status` a věta v kartě uzávěrky** — počet zápisů a poslední změna; při uzávěrce plánu kolikrát AID během jeho EPICů odmítl nebo byl obejit.
- **Sběr na straně vlastníka** — `bin/aid-plugin-issues-collect.sh` projde `/opt/eco/projects/*/.aid-o/work/aid-plugin-issues.md`, nepřevzaté body slepí do `docs/plans/plugin-issues-inbox.md` a v projektech je označí `PŘEVZATO <datum>`; nic se nemaže, soubor zůstává záznamem projektu.

### Changed
- **Pravidlo pro agenty zpřesněno** — každý `--force` a `amend-scope` kvůli chybě AID je zápis; nálezy Codexu o pluginu přepisuje controller (Codex běží jen pro čtení).

## [2.95.5] — 2026-08-29

### Added
- **`aid-fsm.sh amend-scope`** — jediná schválená cesta, jak uprostřed kroku rozšířit seznam souborů, které smí agent měnit: jeden příkaz upraví `plan.json`, přerazítkuje `plan_json_hash` a zapíše `steps/<id>/scope-amendment.json` (kontrakt kroku zůstává, validátor ho sjednotí), s důvodem v timeline i auditu. Do té doby hlídač commitů chtěl úpravu `plan.json`, kterou kontrola otisku trestala. Postup pro agenty je v `skills/agent-protocol.md`, pro controller v `commands/aid-run.md` (pravidlo 16b) a `skills/pipeline.md`.

### Fixed
- **`plan-start` už nechce ruční commit plánu na `main`** — když je checkout na `main`, uloží soubor plánu sám stejným izolovaným commitem jako manifest (jen ta jedna cesta, index se nesahá); z jiné větve to řekne a nechá to na tobě. Souběh více plánů zůstává bezpečný, každý plán zapisuje jen svůj soubor.
- **Uzávěrka plánu vyžadovala brány, které žádný běh nevybírá** — plan-final počítal jako povinnou každou bránu s `required: true` v celém `execution.yaml`, i tu, kterou žádný profil nezahrnuje (noční sada ve WANu); teď jsou povinné jen brány z rozlišeného profilu plus nastřádané z manifestu a `plan_diff`. Čtyři hotové plány ve WANu tím přestanou stát.
- **`plan_diff` blokoval plán bez strojových vzorů** — když plán nemá žádný `verification_pattern`, skip brány je pravdivý výsledek („nic strojově ověřitelného") a uzávěrka ho uzná; šablona ani lint vzory nevyžadují, uzávěrka nemá chtít víc.

## [2.95.4] — 2026-08-29

### Fixed
- **Merge plánu tiše vrácený dalším commitem** — `plan-merge-to-main` i plumbing lifecycle commit posouvaly `main` jen v refu; checkout, který má `main` vykoupnutý, zůstal na stavu před merge a nejbližší obyčejný commit merge vrátil (stalo se ve WAN dvakrát). Nový helper `_aid_lc_sync_checkout_of` ten checkout dotáhne dvoustromovým `read-tree` (lokální úpravy nepřepíše) a když nemůže, hlasitě řekne, co spustit před dalším commitem.
- **Prázdný scope po posledním kroku** — pre-commit hook po dokončení posledního kroku pouštěl vše (okno pro opravy po CP3); nyní kontroluje proti sjednocení `allowed_paths` všech kroků, stejně jako v GATES.
- **Stará `fsm-state.yaml` přežila regeneraci** — `aid-json-to-run.sh` přeskakoval init podle existence souboru; při jiném `total_steps` teď odmítne s instrukcí místo tichého přeskočení.
- **„Model at capacity" hlášeno jako `rate_limited`** — Codex transport rozlišuje přechodný výpadek (`capacity`, zkus za chvíli) od vyčerpaného limitu (`rate_limited`, čekej na reset) v C0 i C3.
- **`aid-fsm.sh init` padal na `$6: unbound variable`** — s méně než sedmi argumenty vypíše usage a skončí kódem 2.

### Changed
- **Rozpočet C0 revizí je vidět dopředu** — CP1 brána vypíše „N z M kol zbývá" před každým kolem, ne až po vyčerpání.
- **Pět hlášek a dokumentů** — lineage odmítnutí nabízí nejkratší bezpečnou cestu (`git branch -d` + `epic-start`), `--output-dir` u `aid-epic-to-json.sh` se popisuje jako kořen workspace `.aid-o`, hláška `increment-step` uvádí číslo kroku v plánu (1-based) vedle FSM (0-based), patička lintu říká, že paralelní skupiny blokují v readiness, a `plan-writing.md` popisuje obnovení plánu psaného pod starší verzí (bez `--fix`, záměrně).
## [2.95.3] — 2026-08-29

### Removed
- **Měřicí nástroje E10** — `aid-e10-preflight.sh`, `aid-control-metrics.sh`, `aid-dual-run.sh`, `aid-e10-decision-table.sh`, `aid-e10-promote.sh`, `aid-e10-imp201-decision.sh`, schéma `control-metrics.schema.json`, inventář `control-inventory.yaml` a kalibrační fixtury odstraněny; PM 2026-08-29 rozhodl, že kalibrační kampaň E10 ani slučovací fáze E11 nebudou, plán P062 uzavřen jako zrušený. Sdílený resolver `aid-control-enforcement.sh` zůstává (čte ho FSM i generátor) a má vlastní test `test-control-enforcement.bats`; klíč `controls.<id>.enforcement` nastavuje PM ručně.

## [2.95.2] — 2026-08-28

<!-- two sessions released under this number the same day; both bodies below shipped in v2.95.2 -->

### Fixed
- **Zápis se počítá jen tam, kam opravdu míří** — pravidlo rozeznávalo „tahle session plán zapsala" řádkovým grepem, takže `cat plán.md | tee jinam` platilo za zápis do plánu a `{"name": "Write"}` s mezerou za klíčem se naopak minulo. Přepis se nyní **parsuje**: berou se jen cesta z editačního nástroje a shellový příkaz, `content` nikdy, a zápisová forma musí být ve stejném segmentu příkazu jako cesta k plánu.
- **Čtení plánu není práce na něm** — `cat .aid-o/plans/P900.md` zakládalo povinnost vyrenderovat stránku. Nově platí jen whitelist zápisových forem (`sed -i`, `tee`, přesměrování, `cp`/`mv`, otevření pro zápis).
- **Dvě změny v jedné sekundě umlčely druhý nález** — paměť „řekni to jednou za session" klíčovala na `mtime` se sekundovým rozlišením. Klíč nyní nese **obsahový hash** zdroje, takže plán opravený a vzápětí znovu změněný se ohlásí znovu.

### Changed
- **Mez metody je napsaná v kódu, ne zamlčená** — statickou inspekcí shellového řetězce nelze rozhodnout, co příkaz zapíše (`echo "tee …/P900.md"` se stále počítá). Zavře to jedině skutečný záznam zápisu; zapsáno jako IMP-529 a poznámka je na místě, kde by to někdo chtěl zase zužovat.


### Added
- **Role kroku se kontroluje už v lintu plánu** — `aid-plan-lint.sh` odmítne `**AID Role:**` mimo uzavřený číselník (typicky `fullstack`, `devops`, `docs`) se stejnou gramatikou hlavičky jako generátor, takže plán už nespadne až uprostřed generování EPICů.
- **`{evidence_dir}` v příkazu brány** — `aid-run-gates.sh` doplní adresář evidence běhu odvozený ze stavového kořene, takže brána spuštěná z worktree plánu najde evidenci bez projektového triku v `execution.yaml`.
- **Problémy AID samotného mají své místo** — agenti i controller zapisují chyby pluginu (brána odmítne platný stav, skript spadne, hláška lže) do `.aid-o/work/aid-plugin-issues.md` místo projektového backlogu; pravidlo v `skills/agent-protocol.md`, `commands/aid-run.md` a `commands/aid-plan.md`.

### Fixed
- **Karta uzávěru plánu neměla řádek `Důvod:`** — `aid_plan_close_render` vykreslil rozhodovací kartu, kterou Stop hook téhož pluginu odmítl jako neúplnou; řádek s důvodem doporučení se nyní vypisuje.
- **`aid-evidence-verify.sh` psal report do kořene souborového systému** — bez nalezeného balíku evidence a bez `--out` skončil na `/verification-report.json`; nyní odmítne s jasnou hláškou.
- **Zavádějící hláška při generování mimo cílovou větev** — místo rady „spusť z worktree plánu" (stav, který už platil) říká, že plán a manifest musí být commitnuté na cílové větvi a jak to udělat.

### Changed
- **Dokumentace sedmi nálezů z WAN** — `output.md` píše výhradně controller, kroky se v evidenci číslují od nuly, obálku vygenerovaných skeletů smí měnit jen payload (a jak se z toho vzpamatovat), stránka PM stárne s každou úpravou plánu, `--recreate-worktree` neobnoví smazanou větev, verifiér smí ignorovat varování hooku na svůj evidence soubor, značka `nightly:` v `execution.yaml` není mechanismus (profil je jediná autorita).
## [2.95.1] — 2026-08-28

### Fixed
- **Milníkové pravidlo hlásilo cizí plány dál** — oprava ve 2.95.0 brala za „plán téhle session" každé `P###` v transkriptu, jenže o plánu se dá celý den mluvit, aniž by se na něj sáhlo: v tomhle repozitáři bylo P062 v přepisu 299×, zatímco ho měnilo jiné okno. Nově se počítá jen id, které se v přepisu objeví u **zápisu** souboru plánu (Write/Edit, `sed -i`, otevření pro zápis, přesměrování); pouhé čtení ani zmínka povinnost nezakládá.
- **Týž nález se opakoval na každém tahu** — i správná výtka přestane být čtená, když ji člověk vidí celý den. Pravidlo si v úložišti session pamatuje, co už řeklo, a řekne to **jednou za session** na každý plán a milník zvlášť.
- **Test CHANGELOGu se vázal na nejnovější sekci** — a rozbil se, jakmile nad ní přibyla další; teď je připnutý k vydání, které popisuje.

## [2.95.0] — 2026-08-28

### Added
- **E10 — kalibrace a povyšování kontrol podle měření** — šest nástrojů, které nahrazují dohad čísly: `aid-e10-preflight.sh` (tvrdé podmínky), `aid-control-metrics.sh` (kvalita detekce C0-C4), `aid-dual-run.sh` (nová vrstva proti staré nad kalibračními fixturami), `aid-e10-decision-table.sh` (jedno rozhodnutí na kontrolu, šest možných výsledků), `aid-e10-promote.sh` (povýšení schválených kontrol na blokující) a `aid-e10-imp201-decision.sh`. Rozhodnutí je klíčované řádkem kontroly, ne kontrolou, takže jedno schválení nepřeklopí několik z nich.
- **Stránka říká, co se dodalo** — profily `epic_done` a `plan_done` nyní vyžadují `deliverables`; stránka dokončeného EPICu je čte z `final_report.md` nebo `epic-summary.md` (číslovaný i odrážkový seznam, odkazy se rozbalují na text) a nadpis se řídí typem artefaktu. Bez zdroje se stránka nevyrenderuje.
- **`plan-state --set-autonomy auto|manual`** — orazítkuje plán založený před P090, aby pokračování nemuselo pokaždé odvozovat režim z konfigurace projektu.

### Fixed
- **Krok s výstupem v jiném repozitáři** — očekávaný artefakt se skládal jako `${root}/${cesta}`, takže absolutní cesta se slepila za kořen stromu a krok byl odmítnut, přestože oba soubory na disku byly (nahlásil WAN jako blokující).
- **Plán se v autonomním režimu zastavoval po každém EPICu** — chybějící pole `autonomy` u plánu založeného před P090 se četlo jako „manuální", takže projekt s `autonomous_mode: true` po každém merge tiše stál. Chybějící pole nyní spadne zpět na nastavení projektu a řekne to.
- **Hooky hlásily cizí práci všem oknům** — milníkové pravidlo soudilo plány podle času (`find -newer`), takže v jednom projektu dostalo každé okno výzvu dorenderovat stránku plánu, který měnilo okno jiné. Nově se soudí jen plány, které session sama zmínila; u běhu se plán odvodí z EPIC id.
- **Prošlá brána nechávala po sobě stránku, o kterou nikdo nestál** — WAN jich za dva dny vyrobil 17 pro jednu, kterou PM chtěl. Stránku nyní renderuje jen běh, který blokuje; karta do chatu se tiskne dál, takže se výsledek hlásí vždy.
- **Nadpis „delivered" se hledal jako podřetězec** — `## Not delivered` i `## Undelivered items` by se publikovaly jako to, co EPIC dodal.

### Changed
- **Registr pravidel a specifikace šablon dohnaly kód** — milníkové pravidlo nese pole `scope` s tím, čí plány soudí a proč se ustoupilo od časového okna; `artifact-templates-spec.md` popisuje `{{prose:deliverables_heading}}` a tři nadpisy podle typu; `commands/aid-run.md` říká, kdy orazítkovat zděděný plán.
- **Pole „co nezaručuje" má v registru jediný název** — `not_guaranteed` (26 řádků); tři řádky používaly `does_not_guarantee`.

## [2.94.0] — 2026-08-27

> A plan with six EPICs used to need someone to remember to start the second one. Now four
> layers do it, and they are four because they are not equally strong.

### Added
- **`queue_peek_next` — asking the queue no longer means taking it** — `queue_claim_next` used to select and write `status=running` in one breath, so a turn that merely wondered what was next left an EPIC marked running with nothing running. Selection is now one shared function that `peek` reads and `claim` writes through, so the two can never drift; a lock `peek` cannot take is an error, never the empty-queue answer.
- **`aid-plan-fsm.sh next-epic <plan_id>`** — the read as a command, with `claim-next`'s own exit codes and a line in the plan's timeline for every answer, so why a plan continued — or stopped — is recoverable afterwards. It refuses a plan this repository never started rather than reporting it exhausted.
- **`scripts/aid-plan-continue.sh` — the continuation is a program** — proof, mirror, ask, claim, start, in that order, stopping at the first link that fails. `epic-merge-to-plan` calls it itself after a successful merge whenever the plan runs autonomously, with no flag to remember; `--no-continue` turns it off and `--continue` forces it for a manual plan. Link 0 is a real `git merge-base --is-ancestor` check, because a queue entry with no `merge_target` is judged by its status alone and an unearned `merged_to_plan` there would falsely unblock its dependent.
- **`autonomy` on the plan, not on the run** — `plan-start` writes it into `plan-state.yaml` (`--autonomy auto|manual`, otherwise resolved fail-closed from `permissions.yaml`). The run record's `auto_controller` cannot serve: a run deletes its own entry before its EPIC merges, so at merge time there is nothing left to read. Absence reads as manual, so every plan created earlier is unchanged.
- **`continue-state.json` (schema `aid-plan-continue/1`)** — written atomically at the end of every run, including the ones that failed, and read at the start of the next. It carries the plan's position plus `job_id`, `jobs_dir`, `job_fingerprint` and `spawned_count`, because after an interruption nothing else knows this plan's own job and a cap that resets on restart is not a cap. A guidance, not an authority: the next run reads it and then asks the queue anyway.
- **Starting the next EPIC as a supervised job (off by default)** — with `autonomy.spawn_next_epic: true` the claimed EPIC runs as `claude -p "/aid-run --auto --epic <id>"` under `aid-job.sh`, with a deadline and a collectable terminal result. The job id is pre-allocated and handed to the session in its own environment, so the "is a job already running" check can exclude the job the caller is running inside — without that the chain would stop at length one and nothing would restart it. The decision and the launch sit inside one hold of the JOBS directory's lock (not the queue's — nothing there touches the queue, and holding it would block every other plan's `peek-next` while one session starts). Default off, because sessions that start sessions are a decision about money and trust.
- **`autonomy.max_spawned_epics` / `autonomy.spawn_deadline_sec`** — read from `project.yaml` the way P089 reads its own keys: a missing key defaults and says so, a present-but-unusable one is an error naming the key. The cap is per plan, not per workspace.
- **Two hook rows — a reminder that says what is unfinished** — on `Stop` it names every autonomous plan that still has work, on `SessionStart` it reads back the guidance an interrupted run left, which after a dead controller is that guidance's only reader. Deliberately degree 3: the dispatcher strips any refusal from a Stop rule once `stop_hook_active` is set, so a barrier here would hold exactly once and then go quiet.

### Changed
- **`skills/pipeline.md` step 16 and `commands/aid-run.md`** — they described a sequence a controller had to perform; they now describe a program that performs it, and the "no production caller invokes them yet" note is gone because a caller exists.
- **An entry left at `running` is reported, never collected** — by name, on every path that gets past the mirror, with the human-invoked `aid-plan-continue.sh --reclaim <epic_id>` that releases it. It is either a crash between claim and start or somebody else's live run, and taking a live run's entry out from under it is worse than waiting.

### Fixed
- **`aid-job.sh`'s deadline timer orphaned a `sleep` for the whole deadline** — cancelling the timer killed the subshell, not the `sleep` running inside it, so a job that finished in a second left an hour-long process behind: 43 of them after a single test run. The subshell now backgrounds its sleep and takes it down on TERM, with no new dependency.
- **`aid-job.sh` leaked the caller's file descriptors into every job it started** — it detached with `setsid` and redirected only stdin/stdout/stderr, so the wrapper and its deadline watchdog (a `sleep <deadline>` that lives for the whole deadline, an hour by default) inherited everything else. A caller holding an flock kept holding it for the job's lifetime; a caller whose output was read through a pipe never reached EOF. Measured, not theorised: a test suite finished every case and then sat for fifteen minutes with no children, because six `sleep 3600` processes held fd 3. Five scripts already call `aid-job.sh run` and each had the same latent hazard, so the fix is in the supervisor's own detach rather than in one caller.
- **`lib/aid-queue-write.sh`'s status table credited the wrong writer** — it said `aid-plan-fsm.sh epic-start` writes `running` and `epic-merge-to-plan` writes `merged_to_plan`. Neither ever did: the plan FSM does not touch the queue at all, by the design decision recorded ten lines above it.

## [2.93.1] — 2026-08-26

> The nightly's wave of eighteen, and the check that was meant to prevent the next one — which
> turned out to be a check that could not fail.

### Added
- **`scripts/tests/lib/aid-test-plan-fixture.sh` — THE one place a fixture seeds a plan** — it satisfies every generation precondition at once (a real `execution.yaml`, the plan committed where the workspace tracks it, the PM page rendered and current), so a fourth is one edit there rather than fifteen. Three landed in three weeks and each broke the same ~15 `t2` fixtures, because nothing runs those to completion. It never switches a gate off: a fixture that skips a precondition proves only that skipping works.
- **`test-plan-fixture-contract.bats` (T1, the merge path)** — it seeds through that helper and runs the REAL generator with every argument, requires success, and asserts the EPIC exists. A fourth precondition now fails at merge in one place.

### Fixed
- **Eighteen suites the nightly reported** — the generation family (44 failures to 0), plus `init-idempotency`, `auto-recovery-policy` and the handoff renderer's goldens.
- **`auto-recovery.yaml` no longer carries line numbers** — nothing outside one test read them, they drifted twice in five days (once by 110 lines), and the schema's own description had said for months that anchors are what the test asserts while requiring the field anyway. The schema now refuses their return, and every anchor is unique in its file — unique *and* moving with the code, where the line number was unique and rotting.
- **`/aid-init`'s declared product and its test agree again** — the document was right: `counter.yaml` joined the ten in v2.89.2, when a fresh workspace could not allocate its first plan id.
- **The handoff goldens follow P089 Step 3** — regenerated deliberately, after confirming the new gates page carries more than the old one. The one assertion that needed real work: "a waived gate must never read as passed" hunted the English word `waived` on a page that is Czech throughout, and now holds on the surface that exists — the tile must name the waiver and the verified count must exclude it.

### Changed
- **An AID alert names its project** — `Scope: wan-aid-beh`, source `AID · wan`. The plugin is installed per project, so without it two identically-shaped messages from two repositories are indistinguishable; `Host` is the machine, not the project.

## [2.93.0] — 2026-08-26

> A page carries what its phase owes and cannot contradict itself, and a release is required by what changed rather than by what a commit message promised.

### Added
- **`scripts/tests/lib/aid-test-plan-fixture.sh` — THE one place a fixture seeds a plan** — it satisfies every generation precondition at once (a real `execution.yaml`, the plan committed where the workspace tracks it, the PM page rendered and current), so a fourth precondition is one edit there instead of fifteen. Three times in three weeks a fail-closed precondition was added, the merge-path fixtures were updated and the ~15 `t2` ones were not — surfacing in a nightly days later and repaired file by file.
- **`test-plan-fixture-contract.bats` (T1, the merge path)** — it seeds through that helper and then runs the REAL generator, so a fourth precondition fails at merge in one place rather than at night in fifteen. A grep rule would have caught none of the three.
- **Artifact profiles** — `defaults/artifact-profiles.yaml` declares what each of the five page types owes (brainstorming, plan, gates, finished EPIC, closed plan) and `aid_artifact_render` refuses a page that does not carry it; a new type is a section in that file, never a branch in the renderer.
- **State-derived wording** — a type marked `outcome_from_state` hands the renderer four counts and the renderer composes the result, verified and did-not-run tiles from them, dropping whatever the caller wrote — so "6 of 9 passed" beside zero failures can no longer be written rather than merely being discouraged.
- **A page for a finished EPIC** — `lib/aid-epic-summary-page.sh`, rendered by `cmd_done_advance` on the review→release edge, says what the EPIC delivered, what the audit found and **which backlog items the Curator filed and why**; a missing audit or curator report is named on the page instead of being implied away.
- **Release scope decided by files** — `lib/aid-release-scope.sh` lists the commits since the last tag reachable from the judged commit, removes those carrying a `No-Release: <reason>` footer, takes the union of the paths the rest touched, and decides that set against `versioning.release_exempt_paths` and `versioning.app_paths`; `fix(tests):` over test files no longer blocks and `chore:` over application code no longer passes.
- **A CI facade for the same verdict** — `scripts/aid-release-check.sh` prints the verdict and the commits behind it into a build log and always exits 0, and `.github/workflows/ci.yml` runs it; the hook is the only thing that blocks.
- **Anti-drift gate over Dockerfiles** — `scripts/gates/release-paths-drift.sh` compares `COPY`/`ADD` sources against the two declared path lists, because the config and the image are two claims about the same thing; advisory, and wired here as `check_release_paths` in the `full` and `release` profiles so a disagreement is reported without stopping the run.
- **A suite named only in prose is reported** — `aid-plan-lint.sh` flags a test suite named in `## Testing Strategy`, declared in no `Test:` bullet and absent from the repository, advisorily (IMP-517).

### Changed
- **The page obligation covers three milestones** — `plan_artifact_rendered` becomes `milestone_artifact_rendered` and refuses a turn that finished a written plan, an EPIC's review or a closed plan without its page; a step, and a failed step, owe nothing.
- **The gates page** — four closed categories (verified, failed, did not run, waived), the headline is how many FAILED, the core names which gates ran and what each verified, a gate the harness stopped before it ran is counted as "did not run" and the page names the reason, and when nothing is expected the next-steps list is empty so no command stands beside "nothing is expected".
- **Blocks 5 and 7 carry names** — the closing page and the brainstorming page stopped carrying file paths in their link blocks; the paths live in the provenance footer, where they already were.
- **`aid-release.sh` has no second copy of the rule** — it asks the same library before reading any commit subject, and commits the scope exempted no longer choose the bump type either.
- **`/aid-setup scan` owns the two release-path lists** — `/aid-init` seeds them for a new workspace and never mutates an existing config, so an already-initialised project gets them from the scan module.

### Fixed
- **Every generation-driving suite is generation-ready again** — `generation-authority` 6 failures to 0, `generation-resume` 10 to 0, `authority-verify` 14 to 0, `supersede-generation` 12 to 0. Three of them were not missing a file: they edit their plan and then assert their own refusal, and an edited plan leaves its PM page stale, so generation refused THAT first. They re-seed after editing — what a person must do in production.
- **A waived gate counted twice** — a row reported `fail` while `waived_gates` named it was counted once as a failure and once as a waiver; a rejected waiver is now removed from the waiver set entirely, so a rejection no longer reads as a waiver.
- **A milestone record that names nothing** — a finished review with no usable EPIC id, or a closed plan with no plan id, used to buy its way out of the page obligation as "not applicable"; both are findings now, and `release_pending` / `CLOSED_PENDING` no longer match the milestone words by prefix.
- **The push range was measured from HEAD** — with a later tag on HEAD the range for an older pushed commit came out empty and the push passed unjudged; the start is now the last tag reachable from the commit being pushed, and an untagged repository gets an explicit `no_tag` verdict instead of an accidentally empty range.
- **Stale expectations in the artifact renderer suite** — four cases had been red since v2.91.0 (three over a link that stopped carrying an arrow, one over a vendored CSS digest that changed without either signature being updated).

## [2.92.1] — 2026-08-26

> AID had two alert senders and neither obeyed the ecosystem alert standard, so a reader had
> to ask whether a message was about the plan they had running or about last night's tests.

### Added
- **`lib/aid-alert.sh` — the one way AID speaks to a human** — it composes nothing itself and delegates to the ecosystem's shared `send_alert()`, spending the standard's `state` field on the reader's actual question: `BĚŽÍCÍ PLÁN` (scope `aid-beh`, the EPIC named first in `Co`) or `NOČNÍ TESTY` (scope `aid-testy`). Every `Akce` carries a deadline, because at a project the action is a decision rather than a command.
- **`/aid/alerty`** — the catalogue of all seven messages AID can send: when each arrives, how urgent it is and whether you must react, with the standard's "what an alert is NOT" table at the top (where the worktree hook notice belongs).

### Changed
- **The nightly separates "the result is bad" from "nothing was measured"** — `nightly-red` and `nightly-neuplny`, two IDs at two severities. A run cut short is no longer announced as a result, and becoming incomplete is itself a reason to speak.

### Removed
- **`aid-fsm.sh`'s own transport** — it POSTed free text straight to the MCP bot on `localhost:8817`, a second transport as well as a second format. All six call sites go through the shared sender; a loud shim remains so an unconverted caller is visible rather than silent.

### Fixed
- **An undelivered alert is no longer recorded as sent** — the first cut always returned 0, which disabled the very mechanism that re-sends a failed message the next night. Delivery status is reported now, and the FSM discards it explicitly so a transition never fails over telemetry.
- **A fixture can no longer reach the real Telegram** — the `AID_ALERT_FORCE` hatch is gone; test mode refuses the production library instead, so a suite that forgot to stub reaches nothing at all.

## [2.92.0] — 2026-08-25

> Agents run at the same time where the plan allows it, three hook rules and a gate check that P086 left out, and a UI proposal the PM can judge.

### Added
- **Dispatch contract** — every dispatched step that declares paths gets a versioned packet built by code from `plan.json` (objective, allowed paths, dependencies, expected artifacts, acceptance criteria, UI contract, its own evidence directory) and must return an `aid-return` block; the return is judged against the packet and the disk (version, promised artifacts present, every changed file declared, out-of-scope files named, no evidence in another step's directory), and `increment-step` refuses to advance a contracted step without an accepted return.
- **Per-step evidence and commit under concurrency** — `aid-fsm.sh step-evidence-dir` gives each step its own `steps/<step_id>/` at the state root and the controller commits each accepted return itself, one at a time — the protocol against a mega-commit; the FSM guarantee is that a contracted step never advances on an unvalidated, unfinished (blocked, failed gate) or rejected return.
- **Shared interfaces as a second disjointness dimension** — a step may declare `**Shared interfaces:**` and `aid-plan-parallel-check.sh` treats two steps of one wave naming the same interface (normalised) as a collision; `--group` judges one wave, which is how the dispatch decision asks.
- **The brake is lifted** — `orchestration.yaml` `dispatch.max_parallel` is a real ceiling (default 3, `strategy: worktrees`); `lib/aid-parallel-dispatch.sh` decides `concurrent slots=N` or `serial: <reason>` and never refuses a run, gives each step a worktree on `step/<step_id>` at the current base, merges returns one at a time, and turns a conflict into an aborted merge, an untouched tree, a reset and a repeated step.
- **Two turn rules** — `turn_step_open` (Stop, fail-closed) refuses to end a turn on a step this session dispatched and did not advance unless the last message is a Decision or Blocked card; `turn_write_scope` (PreToolUse, fail-open) names a Write/Edit outside the open step's paths before it lands, as feedback, because the catch cannot see a shell redirection and must not be sold as a guard.
- **Gate scripts from the branch** — a gate whose command names a repo-relative script the candidate tree lacks fails by name with no fallback to the primary checkout; configuration stays at the state root, and the registry records why that half is deliberately not built.
- **Worktree registry read back** — `aid-plan-fsm.sh worktrees` and a SessionStart notice report recorded trees that are gone or left behind by a closed plan, each with its audited command; nothing removes a tree.
- **UI proposals built from the application** — `lib/aid-ui-proposal.sh` starts from the real screen captured per viewport on fixture data (no fixture, no capture) or from the design system inventoried from the tree, marked as having no live baseline; `ui.responsive` in `project.yaml` (default true) makes desktop and mobile owed and a missing viewport stops the build naming it; both models get the same brief.

### Changed
- **`defaults/orchestration.yaml`** — `dispatch.strategy: worktrees`, `dispatch.max_parallel: 3`, `dispatch.worktree_base: .aid-worktrees`; an already-initialised project keeps its own copy (`strategy: sequential`, `max_parallel: 1`, i.e. the brake) until `/aid-init` upgrades it — nothing runs concurrently there until it does.
- **Every surface that described the brake** — `pipeline.md` §4/§10, `aid-run.md`, `aid-plan.md`, `role-cards.md` and `plan-writing.md` describe the wave decision instead of "TEMPORARY: sequential".
- **Decision-card labels** — `blocked` joins the per-language labels so the Stop rule recognises a Blocked card in the PM's language.
- **Enforcement registry** — `max_parallel_one` is retired with its replacement guards named; `plan_parallel_group_disjoint` records the interface dimension and the runtime consumer; nine new rows carry a degree and a "what this does not guarantee" line, including the known boundary that disjoint paths and interfaces do not guarantee disjoint effect.

## [2.91.0] — 2026-08-25

### Added
- **A plan's page says what the plan delivers** — the new "Co plán dodá" block lists every step, grouped by its EPIC, in the step's own `**Objective:**` sentence (the plan contract defines that field as "what this step produces or changes"), with its acceptance-criteria count beside it. No cap and no collapsed tail: on a ten-step plan the hidden part is exactly the part the reader opened the page to judge. A deliberate, recorded deviation from the artifact standard's "one A4, detail separately", taken because the short page named a plan's ceremony band and its risk count and never what the plan would do.
- **An invalid AID role is named on the page as a defect, with its cost** — a step declaring a role outside the valid set now reads "VADA: role … v AID neexistuje — generace EPIKŮ ji odmítne", instead of being listed as if it were a role. P087 spent a full generation run discovering that `docs` is not `docs-writer`.

### Fixed
- **A detail arrow that promised navigation nowhere** — the renderer appended " →" even with no href, and the plan caller passed a filesystem path as the label. A published page cannot link to a local file, so the honest form is no block at all; the path survives in the provenance footer, which already names the source.
- **Blocks 5 and 7 carried paths where the standard demands names** — the link now reads "Plán P087 — …", the plan's own title.
- **Two of four tiles carried the same number** — "Kroků 10" beside "Rozsah 10 kroků"; the tiles are now four distinct figures, and the one that reported the ceremony band no longer calls itself "Výsledek", because a band is process, not outcome.

## [2.90.2] — 2026-08-25

### Fixed
- **A plan title with a dash or diacritics produced an EPIC filename nothing could reproduce** — the title extractor matched the dash with an awk bracket expression, and awk bracket sets are BYTE sets: `[—–-]` consumed the first byte of a three-byte em dash and left the other two in the title, which reached the filename. P087 generated `E-087-1_2-\200\224-paraleln-….md`, whose recorded `epic_path` then differed byte for byte from the file on disk, and the generation receipt failed as "missing EPIC evidence" — naming the wrong thing entirely. The extractor now alternates (`(—|–|-)`), and `slugify` runs under `LC_ALL=C` end to end so a slug is ASCII by construction whatever a caller hands it, filename and JSON value agreeing byte for byte. Regression suite `test-slug-nonascii.bats`.

## [2.90.1] — 2026-08-24

> What the first real planning session found about the release before it.

### Fixed
- **An enforcement demanded something the renderer refuses to produce** — the `Stop` rule wanted a rendered PM page for every plan written in a session, and `aid_plan_summary_render` refuses a plan with no `## Goal` because a page whose core block is empty is worse than none. For such a plan the two mechanisms contradicted each other and left the session with a finding nobody could act on. The rule now ASKS the renderer (`aid_plan_summary_renderable`, one authority, two callers) instead of keeping a second copy of its rule: a plan that cannot be rendered owes no page, and the reason is recorded.
- **`user_visible` was unreachable from the flow it was written for** — v2.90.0 widened the vision to anything a user notices and taught `aid-brainstorm-state.sh` the new scope, but `commands/aid-plan.md` still offered the old three. Observed live: the flow filed a new CLI flag as `single_plan`, which is how the vision quietly stops being owed.
- **The workspace pins a plugin version and old copies stay on disk** — so "the file is there" was never "the file is current". A session on 2026-08-24 ran its first commands against 2.89.1 while 2.90.0 was installed, and the v2.89.3 resolution block checked only existence. It now compares the pinned path against the version `installed_plugins.json` actually records and prefers the installed one.

### Changed
- **The testbed no longer makes the enforcement it verifies cry wolf** — `bin/verify.sh` re-seeds its fixture plans on every run, so their pages were older than the plans by construction and the next real session was met with findings about them. It renders their pages after seeding, and clears the scratch brainstorm runs its own checks create.

## [2.90.0] — 2026-08-24

> Brainstorming stopped interrogating and started arguing with itself.

### Changed
- **Brainstorming interrupts the PM twice, not five times** — the nine-step flow asked at five places (confirm understanding, three to seven questions one at a time, choose an approach, approve each section, final approval) and MUST rules 1, 4, 5 and 6 prescribed exactly that. P086 then added an opponent whose whole purpose was to REMOVE questions — what two models agree on is recorded without asking — and nobody switched the old interrogation off, so the two stacked. Steps 3 to 7 are now the models' work: approaches, design and section validation run without stopping, agreements go straight into the interim, and disagreements are collected for the result. Section validation itself is unchanged; what is gone is asking the PM to sign off each one. Two planned stops remain, both named in the plan's own Goal: the one at the start, and the scope list before the plan is written. Saying "once" and delivering two is the kind of claim this release exists to stop making.
- **Only five kinds of question reach the PM** — what it is for, who for, how much risk they accept, whether backwards compatibility may break, and anything irreversible. Everything else the two models settle, **including what they disagree about**: a dispute over method or shape is decided between them and the artifact records the choice and the loser's objection. Forwarding every disagreement was the old interrogation under a new name — two models can disagree about anything, and "the opponent disagreed" is not by itself a reason to spend the PM's attention. A sixth kind is not caution, it is the interrogation returning one question at a time.
- **An unanswered question is no longer turned into an assumption** — the flow asks again, shortened, for the unanswered parts only. Silence becoming an assumption is how the autonomous half decides precisely what the PM was supposed to.
- **The vision is owed by anything a user will notice** (`--scope user_visible`), not only by a roadmap or work split across plans. The old rule keyed on plan COUNT, which is a proxy for what actually matters: whether the two sides can afford to have meant different things.
- **The opponent gets the brief, not the main model's conclusions** — handing it your positions anchors it, and an opponent that agrees because it was told what to think is a second opinion in name only.

### Added
- **The decision card takes a batch** — the single stop asks everything at once, and the one-question card had nothing to open a batch with, so the `Stop` rule looked at a page of real decisions and reported "the turn does not ask for a decision". A batch renders each question through the single-card path, so an incomplete item is refused **by its position** — "question 2 of 3 has no reason" can be fixed, "the batch is incomplete" cannot — and a batch of one really is just a card, header and all omitted. Validation is per item, not by counting labels: a reason belonging to another question must not cover for a missing one.
- **A run does not close without a record of the opponent** — a monologue closes fine (`unreached`); what cannot happen is closing with no record at all, because then "two models went over this" is a sentence nobody can check. The record carries the model and provider, so two instances of one model agreeing can be told apart afterwards from two models agreeing. It does NOT prove a second platform was called or that it is independent, and the registry row says so.
- **Three attempts means three** — the first version wrote `ask_pm: (n <= cap)`, which let a fourth attempt through while the text promised three. Now the third failure is the last, and the cap stops the ATTEMPT rather than only the asking — the first fix stopped it asking while a fourth call still reached the opponent, which is a counter wearing the word cap: an unreachable opponent is presented to the PM as a decision (their choice over a silent monologue) until the cap is spent, and the record carries the run it belongs to, so a file dropped into the directory — or copied from another run — no longer closes it. Codex returned 529 three times in a row on the day this was written; without the cap a provider having a bad afternoon becomes a loop of interruptions, which is worse than the monologue it was avoiding.
- **A scope list before the plan is written** — what the plan will deliver and, more importantly, what it deliberately leaves out. Registered as `planned`/degree 4: it is a chat checkpoint with no file to check afterwards, and inventing a receipt whose only purpose is to be checked would be the decoration P086 spent eleven steps removing.
- **`/aid-help brainstorm`** — the mode, its five question kinds, its two exceptions, and what it does not buy you.

## [2.89.3] — 2026-08-24

> Commands that could not be run as written.

### Fixed
- **Every command in nine instruction files referenced a variable nothing sets** — 84 runnable commands across `commands/aid-help.md`, `aid-status.md`, `aid-init.md`, `aid-plan.md`, `aid-stop.md`, `skills/plan-writing.md`, `brainstorming.md`, `pipeline.md` and `agents/auditor.md` are written as `$AID_PLUGIN_PATH/scripts/…`, and nothing anywhere exports it — not the plugin, not the workspace, not the settings of the repository AID is developed in. Copied and run as written, every one of them fails with "file not found". It survived because a model reading the instruction usually works the path out for itself, so the instruction looks like it works. Each file now resolves it once, from the workspace record, using the same source `commands/aid-run.md` §PRE-FLIGHT already used — the convention existed and these nine files simply did not follow it. Found by the first real `/aid-plan` run in a project that had never had one.
- **`skills/plan-writing.md` and `skills/brainstorming.md` are no longer grandfathered** — both now lint clean against `skills/skill-writing.md` and are removed from the exception list in `scripts/tests/test-skill-lint.sh`, so the standard is enforced on them from here.

## [2.89.2] — 2026-08-24

> A brand-new project could not be given its first plan id.

### Fixed
- **A fresh workspace could not allocate its first plan id** — `/aid-init` never created `.aid-o/config/counter.yaml` (it is absent from that command's own product list, which said nine files), and `aid-fsm.sh alloc` refuses without it with "run /aid-init first" — the command that had just run. Every new project hit a circle on its very first plan. Found by the first REAL `/aid-plan` run in a brand-new project, which is the only place it can appear: every workspace that has ever had a plan already has the file. The allocator now seeds the counter at 0 when the workspace demonstrably holds no plans and no tasks, and `/aid-init` lists the file among its product (ten files, fourteen items). The refusal itself is unchanged where it protects something: a workspace that HAS ids and lost its counter is still refused, because an invented counter would restart at 0 and collide with them — and the message now says how to restore it instead of pointing back at `/aid-init`.

## [2.89.1] — 2026-08-24

> A refusing Stop rule that never let the session end.

### Fixed
- **A `Stop` rule could refuse the same turn forever** — a refusal sends the model back to work, and when it does not satisfy the rule the next `Stop` refuses again. Measured, not theorised: the first live run of v2.89.0 against a real Claude Code session wrote a plan without its page and was refused **ten times** before the session was killed by hand. The harness marks that state with `stop_hook_active` (false on the first `Stop`, true on every one after a hook sent the model back — captured from Claude Code 2.1.238), and no rule may refuse a turn carrying it. Honoured in the dispatcher rather than in each handler: it is a property of the event, not of any rule, and a rule author who forgot it would ship the loop again.
- **The plan-lint suite has been red since v2.88.2** — that release deliberately turned "the reuse-evidence replay could not resolve a project root" from a silent skip into a blocking violation, and two cases write their fixture plan into a bare tmpdir, so they have failed on their environment rather than on the Files grammar they test. The fixture was what was stale: `setup()` now creates the plan-state marker `lib/aid-roots.sh` documents for exactly this. The suite is `aid-tier: t2`, so this was red in the nightly portfolio and never on the merge path.

## [2.89.0] — 2026-08-24

> The layer that turns asking into enforcing, and a brainstorm that argues with itself.

### Added
- **A harness hook layer with one entry point and one registry** — `scripts/aid-hook.sh` is the only place AID talks to an agentic CLI's lifecycle, and new behaviour is a row in `defaults/hook-registry.yaml`, never an edit to the script. AID had 31 harness events available and used none; the 40 `blocking` `llm-facing` rules in the enforcement registry were enforced by asking the model to read them. Fail-open is the default, only a `failure: closed` row may stop a turn, a rule's clock is capped to what is left of the whole-dispatch budget, and three escape hatches (`AID_HOOKS_OFF`, `AID_HOOKS_OFF_RULES=<id>`, `disabled: true`) are all audited. An unreadable registry runs no rule — never all of them.
- **A canary, because nothing else may claim hooks run here** — `scripts/aid-hook-verify.sh --canary` runs a real short session and requires AID's own canary rule to have left a *successful* record; the dispatcher audits a crashed rule too, so counting audit lines would let a broken layer certify itself. Codex trust states `untrusted` **and** `modified` are both refused (checking only the first lets an edited hook through) and the bypass flag is never used. Until the canary passes, every fail-closed rule degrades to fail-open and says so.
- **The decision card is built, not imitated** — `scripts/lib/aid-decision-card.sh` assembles card 2 of `skills/communication.md` from data and refuses data with fewer than two options, no recommended option, or a recommendation without a reason. Labels are per-language data in `defaults/decision-card-labels.yaml`, so the card still renders in the PM's language. `scripts/aid-turn-gate.sh` re-checks the written card after the CLI returns, and a `Stop` rule catches the same defect one turn earlier where that event exists.
- **A session keeps its bearings across a compaction** — `PreCompact` writes the plan phase, the live runs with the transitions the FSM itself reports, the working tree and a pointer to the communication contract into the session store *outside every working tree*; `SessionStart` injects it back on a continuation, always with its age on the face of it. Registered at degree 3 — a delivery, not a guarantee.
- **Brainstorming and generation get their own working copies** — `aid-plan-fsm.sh plan-scratch <id> --phase brainstorm|generation`, so two planning streams stop sharing one index and one HEAD. The tree is isolated; state deliberately is not.
- **A vision step with a transition behind it** — `scripts/aid-brainstorm-state.sh` holds whether a roadmap's (or multi-plan work's) vision is approved, and the later phases ask it. A vision point with nothing that could show it false is refused by name. A single short plan has no vision step and the skip is recorded with its reason.
- **An opponent from another platform, inside the design rather than after it** — `scripts/lib/aid-brainstorm-opponent.sh` gives a second model the same brief; what both hold is written without troubling the PM, and disputes reach the PM as decisions with both positions and what it costs to get wrong. An opponent that cannot be reached, fails, or answers outside the required shape is recorded as unreached and the brainstorm continues as a monologue that says so — prose that could not be parsed is never consent.
- **A brainstorm ends in a page** — `scripts/lib/aid-brainstorm-summary.sh` renders it from the run's own files; absence is named rather than left blank, and working artifacts stay in `work/brainstorm/<id>/` until the PM accepts the run.
- **A subagent is told when its protocol is not the repository's** — measured, then wired: `SubagentStart` injection reaches a subagent only inside `hookSpecificOutput.additionalContext` (bare stdout runs, reports success and delivers nothing — Claude Code 2.1.238). On that basis `subagent_protocol_notice` tells a role agent that its installed protocol and this checkout's copy differ, and gives both paths. It delivers a POINTER, never the file: injecting a working tree's file into an agent's instructions would let a checkout write them. IMP-179 had bitten three times. Write-up: `docs/plans/P086-subagent-protocol-probe.md`.

### Changed
- **A plan without its rendered PM page no longer generates EPICs** — `plan_artifact_rendered` leaves `planned` after two months and becomes a hard, band-independent precondition in `aid-plan-to-epic.sh`. Existing projects will see generation refuse until the page is rendered; the refusal carries the exact command.
- **Every new enforcement row carries its degree and what it does not guarantee** — the ecosystem scale (1 code decides / 2 code checks the answer / 3 code delivers data / 4 prose) is now a registry field, and `docs/extending-aid.md` requires it of any new hook rule. A row without a degree has not said whether it enforces or merely delivers.
- **Every injection is wrapped in the envelope the harness actually reads** — the probe above exposed a latent defect in this very release: the continuity capsule emitted bare text on `SessionStart` and may never have been delivered at all. `scripts/aid-hook.sh` now wraps each dispatch's injection once, in the dispatcher, since two handlers each emitting their own JSON object would concatenate into nothing valid.
- **What the review of this release found, and what it changed** — a pointer telling a subagent to *follow* a checkout's file hands whoever controls the checkout the same channel as injecting the file would, one step removed; the notice now reports the divergence and asks for nothing. The brainstorm promotion rule was walkable by passing the renderer another path, so it is enforced from both ends: `approve` refuses a run with no rendered page, and the renderer refuses to write an unaccepted run's page outside its working directory. Every write of `dispute.json` is checked — "the artifact records that the opponent was not reached" has to be a fact about a file.
- **The hook layer got cheaper in the hot path, and one of its own guards was leaking** — a dispatch read the registry once instead of six times per rule, refuses the cheap cases before parsing the event payload, and reads the trust file only when a matching rule could block: a `Stop` dispatch went from ~600ms to ~340ms, and an event nobody registered for from a parse to ~32ms. The per-rule clock became a watchdog rather than a 100ms poll — and the watchdog inherited stdout, so a caller reading the dispatch through a pipe waited out the full timeout on every rule (five seconds each, measured in the suite). Its descriptors are closed now. The continuity capsule builds its arrays in one pass instead of one `jq` per element and asks the FSM once per distinct state rather than once per run.
- **One home for "where does a sentence end"** — the first-sentence and count-normalising helpers were about to exist twice, once per PM-page renderer. They live in `lib/aid-artifact-render.sh`, which every such caller already sources, so two pages cannot start cutting text differently after one of them is adjusted.
- **`AC19` is recorded as not delivered, with its reason** — gate configuration read from the branch is blocked by two measured facts (`.aid-o/` never reaching a linked worktree, and configuration read out of a working tree making a downloaded repository able to run code). Registered as `gate_config_from_branch`, `status: planned`, rather than described as delivered by the phase worktrees, which do not do it.

### Fixed
- **The retired-command check reported a live script as a retired command** — `test-instruction-consistency.sh` matched `/aid-brainstorm` with a `\b` boundary, and `-` is a word boundary to grep, so the new `scripts/aid-brainstorm-state.sh` path counted as a reference to the command retired in v2.0. The boundary now excludes name characters; a genuine reference is still caught (verified against a fixture).

## [2.88.2] — 2026-08-23

### Fixed
- **Two obligations could switch themselves off in silence** — an unresolvable project root skipped the reuse-evidence replay and the documentation-surface check without a word, which is the fail-open direction the whole band model exists to avoid; both now say what they could not verify, blocking for a `lifecycle_strict` plan.
- **The band matrix authors read was missing a row the lint enforces** — `## Standards` was graded by `aid-plan-lint.sh` but absent from the obligations table in `skills/plan-writing.md`, so an author obeying the table would never write it. The new `test-band-table-agreement.bats` fails when the two tables drift again.

## [2.88.1] — 2026-08-23

### Changed
- **Standards path patterns moved into the map** — `scripts/lib/aid-standards-map.sh` carried its own area→tag table, which encoded this ecosystem's tag names and this repository's layout: in a project with its own map nothing matched, nothing was derived, and `plan_standards_named` sat in the enforcement registry as `blocking` while being unable to fire. The patterns now live in the map's own `tag_paths` block and the reader has no table at all, so a project is judged by its own layout.
- **A map without `tag_paths` is a broken configuration** — deliberately not a silent fallback to a built-in table, which would map this repository's paths onto a foreign project's tags. Same treatment for a map declaring a `schema_version` this reader does not know: refused loudly, blocking for a `lifecycle_strict` plan, rather than read hopefully.

### Fixed
- **A path cannot dodge its standard by spelling** — `././docs/x.md` and `a/../docs/x.md` are normalised before matching, because the Files-shape predicate tolerates those forms and an unmatched pattern is an obligation that quietly disappears.
- **`tag_paths` is validated by shape, not by size** — `tag_paths: "oops"` has a non-zero length and would have passed a length test, produced no patterns, and answered "nothing applies"; it is now refused as the broken configuration it is, as is a tag whose pattern list is empty.
- **A `tag_paths` key missing from the map's tag vocabulary is reported** — patterns under an unknown tag can never yield a standard, so it is the same map defect the unknown-tag check already reported for `standards[]`, wearing a different hat. A pattern written with `**` is reported the same way: bash already crosses `/` with a single `*`, so it works, but whoever wrote it expected a different language.

## [2.88.0] — 2026-08-22

### Added
- **Reuse check per founding step** — a step whose `Files:` carry a `Create:` bullet owes a `**Reuse check:**` field naming the read-only search it ran and which of four results it got, and `aid-plan-lint.sh` REPLAYS that command and compares the file count with the claim, so `none` over a search that finds something today is a blocking finding and a command that no longer runs is refused as stale evidence. Required in every band, `light` included, because founding a duplicate component is exactly what a small plan does.
- **`scripts/lib/aid-reuse-verdict.sh`** — the grammar, the replay and the N+1 rule in one place: a plan never adds one more variant of something that exists, and a step that declared conflicting patterns and founds another anyway must argue for it in writing. The verdict decides between unifying now (every conflicting site already lies inside the plan's declared paths) and filing a backlog item that LISTS the sites.
- **`reuse_evidence` C0 lens** — judges what the replay deliberately cannot: whether the search was wide enough. Its findings stay observe-only, but `aid-cp1-gate.sh` requires the file to exist in band `full`, because a lens whose absence stops nothing is a lens nobody has to run. It is a sibling of `reuse_compat`, which answers a different question and is unchanged.
- **`scripts/lib/aid-standards-map.sh`** — derives the ecosystem standards binding a plan's declared paths from the LIVE standards map (path in `project.yaml → standards.map_path`), and `aid-plan-lint.sh` compares them with what the plan's `## Standards` section names. The map is read, never copied; a project without one owes nothing and the lint records that it asked nothing; a map configured but unreadable is reported as the broken environment it is, not rounded down to "no standards". `--self-test` re-checks the derivation against the live map for three control paths.
- **`scripts/aid-plan-parallel-check.sh`** — each step declares a `**Parallel group**`, and two steps in one wave must not name the same file. `Parallel Group` has been written into `plan.json` since P039 with nothing ever producing or checking a value; this is the other half. Advisory while writing, blocking inside `aid-generation-readiness.sh`.
- **A documentation step where there is somewhere to write** — a plan that changes behaviour a user meets must declare a path under the project's in-app help or documentation site, recorded once by `/aid-init` and `/aid-setup` in `project.yaml → documentation`. A project with neither surface owes nothing, and the lint says so.

### Changed
- **The PM page carries two more counted facts** — the standards the plan names and how many of its founding steps carry a reuse search, both read out of the plan and both absent rather than empty when there is nothing to say.
- **One reader for a plan's step structure** — `lib/aid-scoping.sh` gained `_aid_plan_step_bounds`, `_aid_plan_step_field`, `_aid_files_bullet_verb` and `_aid_backtick_paths`, which the plan lint, the reuse verdict and the parallel check all share instead of each parsing the plan again.

### Fixed
- **The band requirements table could fail open** — when `yq` errored, `_cp1_band_flags` returned fewer values than the gate reads, leaving the tail empty, and an empty flag reads as "not required" everywhere below. The count is now padded to the fail-closed default.
- **`aid_plan_summary_render` skipped annotated headings** — sections were matched by exact equality, so a real plan's `## Standards (V3)` was invisible to the page rendered from it.

## [2.87.0] — 2026-08-22

### Added
- **Plan ceremony bands** — the CP1 gate classifies a plan as `full`, `medium` or `light` from the paths its steps declare in their `Files:` blocks, read with the shared scoping parser against the new curated map `defaults/policies/risk-paths.yaml`, instead of grepping the whole plan document for eight content patterns (measured on six live plans: 5 to 33 hits each, so every plan was high-risk and the ceremony was proportional to nothing). Release files are excluded before matching, `risk: high` still raises a band, nothing lowers one but the declared paths, and every uncertainty — no declared path, no map, an unparseable map, no `yq` — resolves to `full`.
- **A requirements table the gate actually reads** — `defaults/policies/review-checkpoints.yaml` gained `review_checkpoints.ceremony_bands`, mapping each band to the CP1-deep lenses, the C0 cross-provider round and the CP1 ledger; `aid-cp1-gate.sh` reads it, so the band a session dispatches for and the band the gate checks can never be two different things.
- **`scripts/lib/aid-plan-band.sh`** — one classifier with two consumers, the gate and the plan lint. The lint sources it rather than shelling out to the gate, because "the CP1 gate is consulted exactly once per plan" is an invariant the generation suites assert by counting gate invocations.
- **`scripts/lib/aid-plan-summary.sh`** — renders the PM's page for a freshly written plan from the plan's own facts (steps, declared files, roles, band, risks all counted, never asserted) through the existing artifact renderer, and `/aid-plan` publishes it after the write.
- **Plan-scoped telemetry** — `aid_plan_timeline` in `lib/aid-stage-log.sh` gives band classifications and lint refusals a home under `evidence/<plan_id>/`; the empty `.aid-o/work/timeline.jsonl` turned out to be a missing home for plan-time events, not a broken writer.
- **Reference set and checker** — `docs/plans/P084-classification-reference.md` labels 23 real plans by hand and `scripts/tests/check-classification-reference.sh`, called from the new `test-cp1-gate-risk.bats`, fails when the map and the labels disagree.

### Changed
- **Plan obligations follow the band** — `skills/plan-writing.md` splits universal from band-scoped obligations and records a verdict for every one of the 28 Completeness Gate checks; `aid-plan-lint.sh` enforces the split (`full`/`medium` owe Architecture Context, Error Handling and Edge Cases per step, `light` owes none of them, and a bare `**Field:**` label satisfies nothing), blocking for `lifecycle_strict` plans and advisory for legacy ones.
- **Tests are designed, not counted** — a step no longer needs a `Test:` bullet; the plan owes a `## Testing Strategy` section with content instead, naming which behaviour it verifies, why that one and where the verification goes. A NEW suite still must declare its tier, unchanged.
- **The PM summary left the plan** — `## Stakeholder Brief` and its three siblings are refused by the lint and MUST rule 17 now forbids writing any human-audience summary into a plan, because that page is rendered from the plan instead.
- **A passing lint is no longer silent in generation** — `aid-generation-readiness.sh` printed lint output only on failure, which made "a loud legacy advisory" silent everywhere the lint is actually reached.

### Fixed
- **The band table could not be switched off** — reading a `false` requirement through yq's `//` alternative operator turned every disabled requirement back on, the same falsy-alternative trap the gate already documents for `jq`.
- **The band classifier could fail open** — a missing or unparseable path map, a host without `yq`, a plan that declares no file, or an unknown band in the requirements table now all resolve to `full`. The prose-scan fallback was removed outright rather than kept as a safety net: it answered `light` for a plan that declares `aid-run-gates.sh` but says nothing alarming in prose.
- **A second, hidden plan classifier could deadlock a `full` plan** — `lib/aid-c0-plan-review.sh` carried a verbatim copy of the deleted whole-document scan and used it to decide whether to dispatch the Codex review at all. A `full`-band plan whose prose matched none of the eight patterns (one in five of the hand-labelled reference plans) had its review skipped, its skipped report refused by `verify`, and the gate blocking on the report nothing would produce. It now asks the same classifier the gate does.
- **`docs/security/*.md` was mistaken for security code** — the consumer-project categories (auth, request surface, payments, migrations) require a code extension, so a documentation plan is no longer pushed into the full ceremony by a directory name.
- **`## Testing Strategy` was checked with a regex mawk does not support** — the `{1,6}` interval was read literally, so the check silently found "content" in every plan.

## [2.86.5] — 2026-08-16

### Fixed
- **The EPIC templates no longer hand a project gate names it may not define** — `defaults/templates/epic.md` shipped a fixed DoD-gate list (`tests_pass`, `lint_pass`, `security_scan_pass`, `docs_updated`); the generator stopped hardcoding those names in v2.85.1 (IMP-503), but anyone writing an EPIC from the template re-introduced the same `undefined_gate` outage by hand. The template now carries the derivation rule and the `yq` command to read the project's real gates instead of a list, and `epic-example.md` says in-line that its five names are the shipped defaults and are not to be copied by a project that renamed them. The command reads the config at the project state root (the file the runner reads), not the nearest `.aid-o` to the author's shell, which in a worktree is a second way into the same outage (IMP-497).

## [2.86.4] — 2026-08-15

> The first measured merge path, and the two things that follow from measuring it.

### Fixed
- **Four suites declared a tier their own measurement forbids** — including the worst offender, `test-tier-ci-topology-guard.bats`, tagged `t0` on the day it was written and measuring 143 s over 10 cases against a tier budget of two minutes. Tier follows measured cost; the tags move, not the rule. T0 drops from 6.1 min to 2.3.

### Changed
- **The merge-path CI job gets 30 minutes, declared as a debt rather than a budget** — the measured merge path is 20.3 min against a 20-minute ceiling, so the job cancelled and CI went red. Raising the ceiling unblocks work and changes nothing about affordability: T1 alone is 18 min against a 10-minute budget, and the standard's answer is that something leaves the merge path.

## [2.86.3] — 2026-08-15

> The first nightly to run to the end reported 17 failed suites. Eleven were fixes that had
> not been pushed; the rest were the night's own environment — and one was a job budget this
> plugin's own new step had blown.

### Fixed
- **An env var the nightly exports no longer decides what five suites assert** — `AID_DURATIONS_DIR` overrides the state root, and bats inherits it, so the durations, reaper, tier-assign, tier-lint and run-all-timing suites asserted state-root behaviour while the library wrote to the shared host path: green locally, red every night. Each already unset `AID_PROJECT_ROOT` for the same reason.
- **The nightly checks out full history** — `fetch-depth: 50` was chosen for the selector honesty check; `test-watchdog-stall` pins a behaviour to a commit 203 back and failed with "invalid object name" every night. A depth picked for one reader silently breaks the next.
- **The isolation run has its own job** — as a step it pushed the portfolio job to 358 minutes against GitHub's 360-minute ceiling, so the night ended `cancelled` with its own `timeout-minutes: 120` never reached.

## [2.86.2] — 2026-08-14

> Everything here was already broken on main and invisible for the same reason: the suites
> that cover it are T2, and the nightly that runs them had not completed since 2026-08-11.
> Found by simulating the nightly instead of waiting for it.

### Fixed
- **A task branch that is behind is not automatically a branch that is honest** — `epic-start`'s fast-forward (P079 Step 3) ran before the lineage check and swallowed the case that check existed for: a branch whose actual base no longer matches its recorded `epic_base_commit` was silently repaired *and* its recorded base rewritten, erasing the one record that showed the move. It now refuses, keeping the existing "lineage broken" wording and mutating nothing.
- **`epic-start` declines a terminal EPIC** — `merged_to_plan`, `abandoned` and `superseded` have no outgoing edge, so starting one would reconcile a branch whose commits the plan already carries.
- **A nested checkout no longer breaks or doubles suite discovery** — the 2026-08-11 fix hand-listed `.aid-worktrees/`; the next occurrence came from `.claude/worktrees/`, which that list had never heard of. Both adapters now prune every dot-directory below the search root. The bats adapter had no exclusions at all, so a nested checkout silently doubled the portfolio there instead of refusing.
- **Two fixtures the IMP-503 sweep missed** — `test-full-pipeline.sh` (14 of 18 cases failing) and `test-regression.sh` (every structural case silently skipping, reported as "0/0") build a workspace without `.aid-o/config/execution.yaml`, which DoD-gate resolution has required since v2.85.1.
- **The plan-close renderer's "incomplete" case asserts the shipped contract** — it drove the renderer with an empty `summary_for_pm` and expected a page with a prose-missing alarm; that fixture is invalid (`summary_for_pm` is machine-constructed here, and its `communication_status: "degraded"` is not in the schema's enum). The case now asserts the refusal; the generic alarm remains exercised at the generic renderer.

## [2.86.1] — 2026-08-14

> One awk line that made a merge-path check vacuous on the machine people run it on, and
> impossible on the machine that gates the merge.

### Fixed
- **The publication-wiring check works the same in both places** — `_section_end` used the ERE interval `{1,6}`, which mawk 1.3.4 (the awk on this project's host) does not support, so every section ran to end of file and the check could not fail locally; where intervals *are* supported, `exit` still ran the `END` block, so the function printed two numbers, `sed` got a malformed range and the check could not pass in CI. Found by simulating the nightly rather than waiting for it.

## [2.86.0] — 2026-08-14

> The merge path stopped being a merge path: five T2 suites had dedicated jobs on every
> push, two of them needing hours against a 35-minute limit, so CI had been red on every
> commit for days. This release puts the tier tag back in charge, and makes the most
> expensive suite in the portfolio 3.2x cheaper by building its fixture once instead of 198
> times.

### Added
- **`test-tier-ci-topology.sh`** — a T0 guard that fails when a suite tagged `t2` is named by a job in a push/PR-triggered workflow, when the nightly has no untiered run, or when any discovered suite is run by nothing at all. It parses workflows with `yq` and refuses rather than guesses on indirection it cannot follow (`workflow_call`, `workflow_run`, expression-built commands).
- **`test-tier-ci-topology-guard.bats`** — the topology guard's own regression suite: ten fixture workflows proving it catches a t2 suite named on push, `--tier t2`, an untiered run, a tier hidden behind a line continuation, a bats glob over the suite directory, and a tier-filtered nightly — and that `chmod +x`, `--only` and `--list` are not mistaken for portfolio runs.
- **`aid-bats-permute.sh`** — writes a seeded case-order permutation of a bats suite, so "the cases still pass in a different order" is checkable on bats 1.8.2, which has no shuffle. It proves its output is a permutation (line multiset + case-name set) before writing it.
- **Snapshot fixtures in the plan-final boundary suite** — each distinct fixture is built once per file through the same builder as before and restored as a byte copy per case, with the shell state a copy cannot carry (exported env, cwd, and bats' `run` globals) re-established explicitly. Four cases assert the layer's own guarantees, including a built-vs-restored shape comparison and a contamination sentinel.

### Changed
- **The nightly re-runs the snapshot suite in a permuted case order** — seeded by the run number, reported as a warning rather than a job failure. Building a fixture once and restoring it per case is the classic way to make a suite quietly order-dependent, and bats 1.8.2 has no shuffle of its own.
- **Delegation is removed; the tier tag is the only authority for where a suite runs** — the five `DELEGATED_SUITES` entries and their dedicated CI jobs are gone. `--tier t0`/`--tier t1` select the merge path, an untiered run is the whole portfolio, and the five suites (all `t2`) now run only in the nightly, as the ecosystem test standard requires. `--include-delegated` is accepted as a deprecated no-op for one release.
- **The `dg04` delivery check runs T0+T1** — it invoked the runner with no tier filter under a 300-second timeout, which after the delegation removal would have meant the full portfolio and a false red every time.

### Fixed
- **The plan-final boundary suite runs in 62 minutes instead of 199** — measured before and after on this host, over the 261 cases that existed on both sides (the file now carries 266: four assert the snapshot layer itself, and one old case became two). 198 of them rebuilt an entire plan lifecycle per case (69 s of fixture per case: 42 s to build the plan, 13 s to merge it, 14 s to seal its evidence).
- **A required gate reporting `skip` is tested against a path that exists** — the old case gave a profile-included gate a null command, which v2.85.1 made the runner refuse earlier as a configuration error, leaving the assertion unreachable. It is now two cases: the configuration refusal, and the stage refusing a report in which a required gate says `skip`.
- **The nightly-workflow drift test says what is wrong instead of dying** — it concatenated all three of the nightly's runner invocations and asserted the blob carried no `--tier`, so it broke the day per-tier measurement was added, and it failed with `fail: command not found` (bats has no such builtin) rather than a message. It now judges the portfolio invocation, with comments stripped.

## [2.85.1] — 2026-08-14

> Ten defects that survived a live-code re-verification of the backlog (P083), plus a
> same-day fix for a fail-closed DoD-gate check that broke six test fixtures on the way in.

### Changed
- **Gate profiles must define a command for every gate they include** — `aid-run-gates.sh` now refuses, by name, an active `--profile` whose `include[]` lists a gate with no `command:` in `execution.yaml`, instead of silently recording a `skip/no_command` row that never touches the run's overall result. Breaking for consumers mid-rollout of the test-tier standard: if your `execution.yaml` has a profile-included gate with no command, add one or drop the gate from the profile before upgrading.
- **The gate-runtime baseline library is sequential-only** — the parallel-scheduler concurrency contexts P078 already removed the scheduler for are deleted from `aid-gate-runtime-baseline.sh` rather than kept as permanently-empty fields; a caller passing one now gets a named refusal instead of a silently dead branch.
- **The C0 plan-review prompt stops asking for an artifact it doesn't have** — its dependency/scope check now reads each step's own `Dependencies:` block instead of the whole-plan source graph, which this review almost always runs before that graph is produced.

### Fixed
- **A streamlined-mode EPIC advances past review without a force waiver** — `fsm_check_streamlined_integration_review` accepts the gates report at either the canonical `gates/` subdirectory or the legacy flat path the plan-final stage still writes, instead of only the one every other reader uses.
- **Multi-line acceptance criteria survive EPIC generation intact** — the two copy-pasted awk blocks that only matched flush-left bullets and silently dropped every indented continuation line are replaced by one shared extractor, in both the human-readable EPIC section and the machine-read `ac[]`.
- **A rolled-back release restores every file it touched** — `aid-release.sh`'s bookkeeping no longer records an edit `update_changelog`'s pre-written-entry branch didn't make, correctly dedupes a file with two version fields (e.g. `marketplace.json`) instead of dropping it from the rollback set entirely, and names a file it could not restore instead of reporting silent success.
- **A configured version pattern that matches nothing is reported by name, not counted as an update** — the regex version-updater now distinguishes "changed" / "already current" / "miss" (by probing for the new version before substituting, since `sed`'s exit code cannot tell a no-op apart from a genuine miss) instead of unconditionally printing `Updated`.
- **Review-signal toggles no longer resolve to "enabled" when they cannot be read** — `_aid_read_toggle` is rewritten in bash's own `[[ =~ ]]` (no `grep -P`, which exits 2 and was read as "enabled" on any grep without PCRE support) and now reports an unreadable or malformed toggle as its own state: the FSM's plan-boundary checks fail closed to enabled, and `aid-release-policy.sh` reports `toggle_unreadable` — and blocks release on it — instead of flattening it into `disabled`.
- **`/aid-init` emits the full gate-profile ladder** — a stack-detected workspace now gets `quick`, `targeted`, `standard`, `full` and `release` instead of only `targeted` and `full`, so a fresh project can satisfy the shipped `plan_final_profile_floor: release` instead of aborting on an empty `release` profile. On the existing-project upgrade path every profile is filtered to gates the target `execution.yaml` actually defines, so the appended block can never name an undefined gate — including when that file fails to parse as YAML at all, and when the compose target isn't the CWD-relative default path.
- **The self-host `plan_diff` gate has a command again** — restored (a first-time addition, not a restoration: it was never present in 16 tracked commits) with `required: false` for the duration of this plan; a profile-included gate with no command is now a runner-level refusal everywhere, not just here.
- **`aid-plan-to-epic.sh`'s DoD-gate fail-closed check (IMP-503) no longer breaks isolated test fixtures** — six existing suites spun up a project directory without a real `execution.yaml`/state-root marker, which the new refusal correctly caught; each now carries the minimal fixture the check requires.
- **All 46 backlog entries the 2026-08-11 live-code verification touched carry a dated verdict** in `docs/plans/2026-06-29-BACKLOG.md`, replacing stale annotations rather than stacking beside them.

## [2.85.0] — 2026-08-12

> The front door tells the truth. `/aid-help` is now generated from a machine-
> readable index that a test refuses to let drift, every file `/aid-init` and
> `/aid-setup` write has exactly one declared owner, and every message AID
> leaves a PM with at a boundary comes from one contract and three
> deterministic renderers instead of whatever each surface improvised.

### Added
- **Machine-readable help index** — `defaults/help-index.yaml` is the authority on every surface the plugin ships (command, file, topic, audience, disposition, purpose, what it writes, and its final turn); `lib/aid-help-index.sh` is the one reader, and `commands/aid-help.md` is regenerated from it rather than maintained beside it.
- **Help coverage test** — a new public command fails the suite until it is intentionally indexed and routed to a help topic. Silence is not a pass: a command a user cannot find is a command that does not ship.
- **Enforcement-registry cite validation** — every `source:`/`instruction:` cite in the enforcement registry must resolve to a real file, and every row id must be unique. A row pointing at a deleted file still looked wired while enforcing nothing, which is the "detector without enforcement" failure hiding inside the file that exists to make enforcement auditable.
- **One read-only configuration summary** — `scripts/aid-config-summary.sh` renders the effective configuration once and both `/aid-init` and `/aid-setup` present it verbatim. Read-only is proved rather than declared: the suite snapshots the whole tree around an invocation, runs against a write-protected tree, and greps the source for any write.
- **Init idempotency harness** — `scripts/tests/test-init-idempotency.sh` pins the SCRIPTED substrate of the re-run contract (execution.yaml composition, `.gitignore` backfill, the base manifest, a declined `gate_profiles` upgrade). It deliberately does not cover the prose-executed steps such as hook installation, which have no shipped library to drive, and says so in its own header.
- **Communication contract** — `skills/communication.md` defines the four PM decision cards, the output-product table, the ordering rule and the language rule ONCE; `scripts/tests/test-communication-wiring.sh` checks that every PM-facing boundary references it and that no other file redefines a card.
- **Deterministic handoff renderers** — `lib/aid-gate-outcome-summary.sh` (the gates boundary) and `lib/aid-plan-close-summary.sh` (the plan-final boundary) render the card and an artifact body from canonical evidence only. Numbers are counted, never asserted; both fail closed when a canonical input is missing rather than narrating around the gap.
- **Artifact rendering layer** — `lib/aid-artifact-render.sh` plus `defaults/templates/artifact-outcome.html` fill the ecosystem artifact skeleton deterministically: a placeholder grammar with single-pass substitution, the standard's brevity caps enforced in code with a counted overflow line, and secret redaction applied before a byte is written and counted in the provenance footer. The renderers write a body and print a card — publication through the Artifact tool remains the controller's live act.
- **Golden handoff harness** — `scripts/tests/test-integration-handoff-rendering.sh` drives all three renderers over checked-in fixtures for five delivery cases, asserting the card comes first, the blocks stay in the standard's order, a raw technical list is never the only output, and no secret survives the page, the card or the fallback card.
- **Artifact-template spec page, authored for handoff** — `defaults/templates/artifact-templates-spec.md` carries the 7-block mapping table and the placeholder grammar, ready for the PM to publish into the ecosystem docs.

### Changed
- **Init/setup ownership is declared per file** — every file the two commands write now names one owner at its write site, including the two that have a second writer that is not `/aid-setup` (`plugin.yaml`, repaired by `/aid-run`'s pre-flight; `check-severity.yaml`, mutated by `aid-fsm.sh promote-check`) and `project.yaml`'s delegated scanner writer. The fresh-init product is counted once and every other mention refers back to it.
- **Boundary card shapes** — the DONE-review and escalation surfaces lead with the outcome instead of a metrics header, and the two verify commands drop their hardcoded language mandate in favour of the contract's rule.
- **Step rendering has one authority** — the rule that turns the FSM's 0-based `current_step` into a human "Plan Step N of T" lived as six full copies across five files. `skills/pipeline.md` keeps the only definition and the other five carry a reference. The human form is appended after the machine values, so every machine-parsed seam is byte-unchanged.
- **Release ceremony calls its own checker** — the pre-push check in `CLAUDE.md` now runs `scripts/tests/verify-version-files.sh` instead of four eyeball greps. It stays a release-boundary invocation and not a CI gate, because the 8 version locations legitimately diverge mid-development.

### Fixed
- **`/aid-help` stated things that were not true** — a `--mode` value the parser rejects, "the only" nine FSM transitions where there are thirteen, and a config-file count the same file contradicted four sections later.
- **A fresh workspace could not open the permissions menu** — init's template carried no `active_preset` while setup's first read expects one, so setup fell back before it could show anything. The key is seeded, and the one surface still listing preset names by hand (two of which existed nowhere in the policy file) now cites the file instead.
- **`active_preset: autonomous` next to `autonomous_mode: false`** — a contradiction on its face, previously improvised differently by three surfaces. Two cases, two fixed strings, used verbatim by init, setup's permissions module and the config summary.
- **Eight dangling enforcement-registry rows** — cites pointing at files that had been deleted, renamed or moved out of the shipped tree; each is now repointed to the surface that really carries the rule, or marked `status: dead` with the reason it died.
- **Ninety test assertions that could never fail** — bash exempts a `!`-inverted command from `set -e` and bats inherits the exemption, so `! grep -q needle file` reported `ok` with the needle present. The idiom was carrying the negatives whose entire value is the negative: no secret leaks, no external URL, no pass label on a waived gate. `refute_grep` replaces it, distinguishing "no match" from "grep errored" so an unreadable file cannot pass as a refutation; 31 occurrences are converted and the remaining 59 are recorded as backlog work with the lint that prevents a recurrence.
- **The chat card never inherited the page's redaction** — the artifact body passed through the renderer's secret detector and the card did not, so six passthrough values could carry a token into the PM's chat: a failing gate's reproduction command and exit code, blocker reasons, the gates report path, the tag status and both evidence fields.
- **Boundary renderers were described as failing closed and did not** — the gate renderer accepted a report with no gate data and announced "0 of 0 passed"; the plan-close renderer accepted a `plan_summary` whose nine keys were all present and all null, and rendered a complete "ready to close" page of invented defaults. Both now validate the values and types they read, not merely that the keys exist.
- **A configuration value set to `false` wore the unset value's face** — `active_preset`, the dispatch mode and a manifest's mode each collapsed an explicit `false` into the wording reserved for "this key predates the feature", which is the more permissive reading. The summary also attributed a policy default to a file it had failed to open, and silently ignored an unparseable project override.
- **Artifact writes were neither atomic nor permission-preserving** — a failed write left a truncated page published at the destination, and switching to a temp file and rename then demoted an existing page from 0640 to 0600 and gave a first render 0600 instead of the umask.
- **A detail link could hide an executable scheme behind leading whitespace** — browsers trim it, the relative-only check did not.

## [2.84.0] — 2026-08-11

### Added
- **Gate name lint** — `aid-gate-name-lint.sh` enforces that a gate's name says what it checks and how much: a kind prefix from a fixed vocabulary, no tool name (the tool gets swapped and the name starts lying), a word of totality only when the command really covers that universe, and no outcome word. Wired as the required `lint_gate_names` gate in every merge-path profile; existing names are grandfathered in `scripts/tests/gate-name-allowlist.txt` with their proposed replacements recorded, because renaming is ~575 literal occurrences and needs an alias period for consumers.

### Changed
- **Gate profiles per phase** — `gate_profile_defaults` was absent, so every gate ran on every phase, including the whole 13-minute T0+T1 merge path at the end of every EPIC. A step now runs `targeted` and an EPIC runs `standard`; the full sweep stays at plan-final, where a merge into main actually happens.
- **CI concurrency and path filters** — a new push cancels the superseded run for the same ref, and commits touching only `.aid-o/plans` or `.aid-o/work` no longer trigger the test path. Verified file by file that no suite reads either from the real repository; `docs/**` is deliberately still covered because a suite reads the real backlog.
- **Hosted shadow run of the merge path** — a non-blocking `merge-path-hosted-shadow` job measures whether T0+T1 pass off the self-hosted machine, so the eventual move is decided by evidence rather than by assumption.

### Fixed
- **Shell-suite discovery trips over a sibling worktree** — AID creates plan and frozen-CP3 worktrees INSIDE the repository it is working on, and the shell-suite adapter scanned them: their dotted paths yield ids outside the stable-id charset, and that refusal killed discovery for the whole portfolio. A second window with a plan checked out was enough to turn the merge path red on work unrelated to either session. `.aid-worktrees/` and `.git/` are now excluded, with the reason recorded in the code.

## [2.83.1] — 2026-08-11

### Fixed
- **A Quarantined Test Could Never Get an Owner** — `add` is deliberately a no-op once an entry is open, so a weekly flake cannot reset its own 14-day deadline; but the nightly was the only automatic producer and always passed an empty owner, and there was no other way in. Every entry was ownerless for ever and escalated weekly with no way to acknowledge it. `aid-test-quarantine.sh assign <suite> <owner>` sets the owner on an open entry without touching its `opened` date, so taking ownership never buys extra days.
- **A Retry Could Launder a Real Failure Into a Green Night** — the nightly re-ran a failed suite with bare `bats`, outside the runner’s working directory, delegation handling, fd discipline and exported environment; a suite that fails only under runner conditions passed standalone, was filed flaky instead of failed and dropped out of the report, so the night read green while a real regression sat in the tree. The retry now re-invokes the runner for that one suite, and with no reachable runner the suite stays failed rather than being quarantined silently.

### Added
- **`run-all-tests.sh --only <suite>`** — runs exactly one suite under the runner’s own conditions, which is what makes an honest retry possible.

## [2.83.0] — 2026-08-11

> The full test portfolio is off the merge path. AID is the ecosystem's pilot
> for `/ecosystem/specs/test-standard`: every suite now declares a tier that was
> assigned from a measured duration, merges run only T0+T1, and the whole
> portfolio runs once a night where it delays nobody. The portfolio also gains
> a budget on the way in and a reaper on the way out — the first mechanism in
> this repo that ever proposed removing a test.

### Added
- **Per-suite timing pipeline** — `run-all-tests.sh --timing` finally gives the
  shipped-but-uncalled `bats --timing` parser a portfolio caller, and appends
  one duration record per suite to a journal under the state root; the flag is
  opt-in and a run without it is byte-identical to before.
- **Measured tier assignment** — `aid-test-tier-assign.sh` proposes a tier for
  every suite from its measured cost AND its scope, and ENFORCES the standard's
  aggregate budgets by demoting the most expensive member while T0 exceeds
  2 min or T1 exceeds 10 min, printing every demotion with its reason.
- **Tier tags and their lint** — every suite declares `# aid-tier: t0|t1|t2` in
  its header; `aid-test-tier-lint.sh` fails a missing, duplicated, unknown or
  too-cheap tag, and a filename carrying a plan, EPIC or task number.
- **Tier-aware runner** — `run-all-tests.sh --tier` runs exactly one tier,
  reports what it skipped, and refuses to run at all while any suite in an
  already-tiered tree carries no tag.
- **Nightly portfolio job** — a `schedule:`-triggered workflow (this repo had no
  scheduled trigger at all), `aid-nightly-report.sh` writing a durable result to
  a shared host path, one Telegram message on a NEW failure with a streak count
  for known ones, and `aid-test-quarantine.sh` giving a flaky suite its own
  aged, owned, deadline-carrying state.
- **The nightly result where work starts** — one derived line in `/aid-status`
  and at `/aid-plan` orientation, including "not run since <date>" when the
  nightly itself has quietly stopped.
- **Selector honesty check** — `aid-selector-honesty-check.sh` replays the last
  merges through `aid-select-tests.sh --dry-run` and reports every nightly
  failure the merge gate would have missed, in three classes; `mapped_but_thin`
  is the one that matters once the merge path narrows.
- **A budget on the way in** — a plan's `Test:` bullet naming a NEW suite must
  declare `(tier: t0|t1|t2)` or generation refuses; an existing suite needs
  nothing, and a project with no tiers is unaffected.
- **A reaper on the way out** — `aid-test-reaper.sh` proposes deletions monthly
  with a reason per row and no quota, deletes nothing itself, and names the one
  input it does not yet have.
- **Review's second question** — CP2 and CP3 now ask whether each added test is
  the cheapest sufficient proof, with a redundant test weighing the same as a
  missing one and "it is probably covered somewhere" ruled out as an answer.

### Changed
- **The merge path no longer runs the full portfolio** — `bats_all` is the
  T0+T1 selection with a 900 s cap bounded by the tier budgets rather than by
  hope; `shell_pipeline_smoke` and `bats_boundary` left every merge-path profile
  and run in the nightly, and `release_quarantine` is once again exactly
  `release` minus the quarantinable gate.
- **Six suites renamed after what they prove** — the plan numbers move into
  their headers, `git mv` keeps the history the reaper's age signals depend on,
  and the migration allowlist is empty rather than merely tolerated.
- **`aid-select-tests.sh --dry-run`** — reports its selection and runs nothing,
  so the merge path can be audited for merges that already happened; unlike
  `--emit-units` it needs no catalog and therefore works inside a CI checkout.
- **The shipped `execution.yaml` template teaches tiers** — consumer projects
  inherit a T0+T1 merge gate and a commented nightly, and an untiered project
  behaves exactly as it did.

### Fixed
- **Two suites that had been red on `main`** — `test-integration-self-host-audit`
  asserted a `bats_all` command shape this release replaces, and
  `test-integration-e2e-audit-pipeline` still expected the two chat sections
  P078 deleted with the parallelism line, renumbering the rest.

## [2.82.0] — 2026-08-10

> The test-parallelism line is over. Measured on this repository's own
> portfolio: 3-6 % saved on a full run, ~15 h of compute to qualify the
> evidence, and that evidence invalidated by every commit — while the
> machinery's own test suites were among the most expensive units the audit
> had ever measured. A feature that costs more test time than it saves is
> not a feature. Removal only: nothing about how tests run changed except
> that they now only run one way.

### Removed
- **The Test Scheduler And Its Rollout** — `aid-test-scheduler.sh`, `aid-scheduler-rollout-gate.sh`, `aid-test-schedule-divergence-check.sh`, `aid-test-divergence-campaign.sh`, `aid-scheduler-overlay-approve.sh`, `aid-test-isolation-experiment.sh` and the scheduler dispatch path inside `aid-run-gates.sh`; `targeted_tests` runs through the ordinary gate path like every other gate, and the gate-runtime baseline records `sequential` because that is now the only truth it can record.
- **The Parallel Lane And Its Evidence Chain** — `aid-bats-parallel-lane.sh`, `aid-test-parallel-pilot.sh`, `aid-test-resource-map.sh`, `lib/aid-test-catalog-provenance.sh`, `aid-test-catalog-apply-evidence.sh`, the two P071 migrations, and the `parallel` block itself — gone from the catalog schema, from this repository's catalog (181 units) and from every scanner that emitted it.
- **Parallel Surfaces In The Audit** — the `parallel_safety` analyst wave and its prompt, the decision artifact's `parallelization` object (lanes, `smallest_safe_pilot`) and the lane-disjointness invariant behind it, the chat summary's two lane sections (six parts become four), and the report's parallel-safe headline stat, per-group column and "parallelism" savings lever. An audit no longer classifies, proposes or advertises concurrency.
- **Consumer-Facing Scheduler Config** — `/aid-init` and `aid-init-upgrade-test-audit.sh` stop writing a `test_audit.scheduler` block into generated projects; `defaults/config/test-audit.yaml` loses its lane-scoped keys. Projects keep the change-based `targeted_tests` selector, which was never about parallel execution.
- **The Quarantine Remediation Cluster** — `aid-quarantine-decision-record.sh`, its evidence collector and both schemas: the bundle's whole content was divergence evidence produced by the deleted check.
- **Five Enforcement Rows** — `test_audit_resource_map_shared_evidence`, `test_audit_pilot_evidence_bound`, `test_catalog_parallel_provenance_binding`, `test_lane_single_parallel_authority`, `test_audit_lane_membership_exact` plus the two scheduler rows, retired as `removed_scoped` records rather than deleted, and the catalog-approve revocation guard whose subject no longer exists.

### Changed
- **`gate:bats_all` And `gate:bats_boundary` Run Plain `bats`** — the same partition the lane used to resolve (the two boundary suites keep their own gate and their own budget), now as a direct invocation. Gate profiles are untouched; a separate tiering plan will reorganize those.
- **Instruction Surfaces Tell The Truth** — the plugin README's scheduler section is one paragraph saying tests run sequentially and why; `commands/aid-audit-tests.md`, the analyst card and `docs/extending-aid.md` lose their parallel-safety contracts; `docs/plans/P072-authority-boundary.md` is archived with a header saying what it now is. The instruction-consistency guard that once banned "no scheduler consumes this" is inverted to ban the opposite claim, so the truthful sentence is the one that passes.

### Fixed
- **`gate:bats_all` Vanished From Double-Execution Accounting** — with the lane deleted, its replacement command names no literal `.bats` path (the shell expands the glob at dispatch), so the execution ledger recorded nothing for 159 files and would have reported zero duplicates for a portfolio it never accounted. `_gate_bats_units()` now expands globs and honours the command's own exclusion filter, and `aid-test-inventory.sh` recognises the same shape for `reconciliation.contains[]` — the two derivations agree by construction. Found by Codex review of the removal diff.
- **The Adapter Emitted A Field Its Schema Rejects** — `lib/aid-test-adapter-contract.sh` still wrote a `parallel` block into every scanned run unit after the schema dropped it, which would have failed every fresh inventory.
- **A Sequential Receipt Could Claim Concurrent Peers** — `co_scheduled_with` is constrained to empty now that `concurrency_context` has one legal value.
- **An Orphaned Suite Would Have Merged Red** — `test-aid-self-host-migrate-p071-gates.bats` tested a script this plan deleted: 13 of 13 cases exit 127, inside a required gate and a CI job. Deleted with its catalog run unit. The same class in fixtures: nine suites still wrote the `parallel` block the catalog schema no longer admits — harmless only until something validated them, which one suite already did (`test-selector-mappings-real-seed`, 6/6 → 2/6). Both found by PM whole-diff review.
- **The Catalog Still Listed 24 Deleted Suites** — stripping the `parallel` block left the approved catalog structurally valid but factually stale: 24 run units whose files Ring 1 deleted, 18 exact mappings to those files, and `gate:bats_all`/`gate:bats_boundary` still declaring the deleted lane command. Any audit, profile or selection touching them would have resolved a nonexistent path. Found by Codex review of the removal diff.
- **The Receipt Producer Could Emit What Its Schema Rejects** — `execution_unit_receipt` still took a caller-supplied `concurrency_context` and `co_scheduled_with`; both are now fixed at `sequential`/empty, matching the narrowed schema instead of drifting from it.
- **The Audit State Guard Still Expected A Deleted Wave** — `_tas_expected_focuses_for_status` listed `parallel_safety` among the dispatching-phase focuses that dispatch no longer produces.
- **`test-run-all-delegation.sh` Was Committed Non-Executable** — a P079 file-mode slip its own adapter guard was already failing on `main`; unrelated to this plan, fixed in passing.

## [2.81.0] — 2026-08-10

### Added
- **Durable carried obligations** — a deferral a run decides to make is recorded in an append-only journal in the state root's plan-state directory, which outlives every worktree, and `aid-plan-close-check.sh` refuses to close a plan while a `release_blocker` is open; the previous improvised file lived inside the plan worktree, was erased with it, and had no reader anywhere in the codebase.
- **Routed review findings** — a finding no remaining step may fix gets a recorded route (a later step, a later EPIC, or a backlog IMP), and `done-advance` both refuses over an open one and reconciles the canonical CP3 review artifact against the journal, so an out-of-scope finding nobody recorded fails by fingerprint instead of living in prose.
- **Chained task branch reconciliation** — an EPIC whose branch was cut before its predecessors merged is fast-forwarded to the live plan head under the plan lock, with the manifest's `epic_base_commit` and the fsm-state's `base_commit` moving with it, and a genuinely diverged branch is refused by name with both heads.
- **Vacuous-green test checks** — the content scanner reports an unguarded `grep -c` under `set -e` (it exits 1 on zero matches and kills the suite while the cases already run still read as green) and a `skip` keyed on whether the subject under test exists, with an authoring rule for the shapes that need a reader.
- **Delegated-suite ownership test** — every suite the aggregate runner delegates must have exactly one CI job that runs it on an uncommented line, because a delegated suite whose job disappears stops being run by anything while the inline run gets faster.

### Fixed
- **Gates run in the plan's own tree** — `advance-to-gates` redirects into the plan's execution worktree like every other plan-linked tree command, so gate commands stop running against `main` and reporting a confident green about code they never saw.
- **Gate evidence lands where the run can find it** — the runner's timeline, report path, execution ledger, waivers, row checkpoints and project config resolve through the state root while the gate commands keep running in the candidate tree; previously those writes were guarded by directory checks that turned a worktree run's evidence into silence.
- **A verdict is not rejected for its casing** — `verdict: PASS` and `## Result: pass` mean what they say; genuinely unknown values still fail loudly.
- **A dropped Files bullet is named** — a bullet the generator cannot parse stops generation instead of silently narrowing the step's scope, the plan lint blocks the same two shapes so it still predicts generation, and a path named only in a bullet's description is reported as an advisory.
- **The plugin's own work is not a stale cache** — the cache preflight downgrades to a warning inside a registered plan worktree whose diff touches `plugins/`, and keeps the hard stop everywhere else, including a worktree the plan's record does not claim.
- **A released version's CHANGELOG heading is immutable** — `aid-release.sh` refuses to retitle an entry whose version is already tagged and prepends a new one instead, at both update sites, and fails closed when it cannot tell.

### Changed
- **`shell_pipeline_smoke` delegation** — the three heaviest P076 suites (service library, service lifecycle, P076 integration) move to their own CI jobs, and `run-all-tests.sh` gains a `--list` mode that enumerates without running anything.
- **CHANGELOG identity is tested** — `verify-version-files.sh` compares the two CHANGELOGs' sections for the version being released byte for byte; the repository rule that they are always identical had never had a test.
- **One prefilter seeding rule** — `aid-prefilter.sh classify` runs for every step with no step-0 special case, stated in the pipeline instruction and pinned by a shape test.

## [2.80.0] — 2026-08-10

> **Version set by hand, deliberately (PM decision 2026-08-10).** `aid-release.sh` must not
> be allowed to derive this heading: `_release_probe_first` matches only numeric
> `## [X.Y.Z]` headings, so an unversioned pending section makes it return the LAST SHIPPED
> version, judge it current, and `sed`-rename that released heading into the new one —
> absorbing its history while leaving this entry unversioned. A no-config fallback applies
> the same blind `sed` to the plugin CHANGELOG, so byte-identity holds and both files are
> corrupted identically, which is why the byte-identity test cannot catch it. Writing
> `2.80.0` here first removes the trigger: the probe now finds a numeric heading that is
> NOT the current version. Tracked as IMP-482 (canonical; this branch's duplicate is 489).

### Added
- **Background gates over an owned job supervisor** — a gate declaring `run_mode: background` runs through `aid-job.sh` (process-group ownership, PID-reuse defeat, a durable HEAD/tree-bound receipt) while the runner still polls it to completion inside the same invocation, so an interrupted session's rerun RE-ATTACHES to the surviving job — found by deterministic id, validated against the command fingerprint and start HEAD — instead of re-running a thirty-minute suite, while command drift cancels, archives and starts fresh.
- **Durable gate-row checkpoints** — a completed background gate's row is written atomically to `<evidence>/gates_rows/<gate>.json` and restored by a resumed invocation, inside an envelope bound to the run's head, tree, canonical directory and a per-run 0600 key, so a hand-written or copied row is refused rather than replayed as a passing required gate.
- **The continuation artifact and `aid-fsm.sh resume`** — `auto_resume_required.json` is written BEFORE a background job spawns (`job_id: pending`, atomically rewritten with the real id after the spawn) and deleted only on a clean terminal collect, so a controller dying in any window leaves the pointer; `resume` claims it exactly once (`mv -n` plus a source-gone post-check), collects the referenced job's terminal result, records it as a durable gate row and prints what it found, what it recorded and the next action — it is read-only while the job is still in flight, and never fabricates a result.
- **`auto_controller` on the active-runs entry, rendered by `/aid-status`** — `active`, `manual` and `blocked_for_pm` are stored values; `awaiting_host_resume` is never stored and is DERIVED at read time from the two facts a dead controller provably left behind (its continuation artifact is still on disk, and no liveness signal is recent enough), with the map writer rejecting the value by name and the render answering `liveness?` rather than guessing when the derivation cannot run.
- **A derived stall verdict** — `aid-fsm.sh active-runs stalled` holds the one rule (the newer of the entry's `updated_at` and the run timeline's newest event, against `AID_ACTIVE_RUN_STALL_SEC`, default 2100 s), which `/aid-status` renders as a `STALLED?` marker plus the recovery command; nothing writes a stall flag anywhere.
- **Declared services** — an optional `services:` block in `execution.yaml` (a `start_cmd` that must remain the foreground process of its job, `probe_cmd`, `stop_cmd`, separate startup and lifetime budgets, `restart_authorized`, `port_env`) with a JSON schema and a fail-closed validator, plus `lib/aid-service.sh` bringing services up and down THROUGH `aid-job.sh`: bind-probed per-run ports, an eagerly written registry, acquire-once before the gate loop and release-once after the report, a crash sweep on the next run's entry, and an ownership claim that stops a second runner tearing down a live run's services.
- **`needs_services` on a gate** — a gate names the declared services it requires healthy; an unknown name is a hard error at run-all entry, and an unhealthy service fails THAT gate fast with `service_unhealthy` while every other gate still runs.
- **`auto-recovery.yaml` — one machine-readable recovery policy** — seven stop classes, each with allowed actions drawn from a closed set of six reversible ones, attempt and wall-clock budgets, a named real emitter site and the `adjudicate → escalation → pm_force` terminus, alongside a schema that turns an unknown action name into a load error and a table declaring every pre-existing retry loop the ladder deliberately does NOT govern.
- **The adjudication library** — `lib/aid-recovery-adjudicate.sh` formalizes the dispatch convention `aid-run.md` had prescribed as temporary: a fact pack in, one allowlisted action out, with the set of returnable values computed from constants in the LIBRARY before the reply exists, the `ACTION:` line parsed rather than scanned, exactly one retry, and every ambiguity ending at `escalate` — a value that is deliberately not in the action vocabulary and that no caller can execute.
- **The recovery ladder** — `lib/aid-recovery-ladder.sh` records every attempt in a per-run append-only JSONL, counting and appending in one locked critical section, failing closed to adjudication on an unreadable policy, and defending the budget against a silent reset with a hash chain plus a high-water mark; three mechanical emitters (gate timeout, lost job, unhealthy service) write from real code paths, and the terminus stamps `auto_controller: blocked_for_pm` through the single map writer.
- **Shared libraries and one new subcommand** — `lib/aid-gate-row.sh` (the single job-result-to-gate-row mapping), `lib/aid-resume-artifact.sh` (one definition of the continuation artifact's name), `lib/aid-env-name-denylist.sh` (one `port_env` denylist for both authorities) and a read-only `aid-job.sh fingerprint`, each replacing a constant or a mapping that had already begun to exist twice.
- **The controller boundary as one shared contract** — `skills/agent-protocol.md` states it once (no detached processes, no FSM mutation, no commits unless delegated, no stale results, no controller-owned file edits) and all nine agent cards reference that section, with a structural test that fails if a card carries a divergent copy or merely quotes it.
- **Five deferred items recorded as backlog entries** — IMP-484 (fire-and-return async gates), IMP-485 (services to resource-map classification), IMP-486 (foreground `timeout -k` hardening), IMP-487 (visual-companion server onto `lib/aid-service.sh`) and IMP-488 (a host push-continuation adapter), each naming what shipped instead and the hook point it would extend.

### Changed
- **`run_mode` is a documented per-gate key** — every gate's value is validated before any command is spawned, so a typo fails loudly naming the gate; the shipped template documents the field and no template gate sets it, and this repository's own two long suites are the only gates anywhere that declare `background`.
- **The runtime-baseline recommendation gained its first consumer, deliberately observe-only** — one `gate_run_mode_advice` timeline event per over-threshold gate that declares no `run_mode`, carrying the measured p95 and the exact one-line edit; flipping stays the PM's decision, and the advice exists only as that timeline event — it writes no gate row, changes no gate verdict and no exit code, and an unreadable baseline yields no advice and no failure (`test-run-mode-advice.bats`, four cases over the real gate runner).
- **A background gate's result answers for the tree it came from** — a REPLAYED result (a job already terminal when this invocation re-attached) must still be current or the gate genuinely re-runs, while a job this invocation spawned or watched to completion keeps the command's exit code as the verdict and merely records `tree_moved_during_run`.
- **`/aid-status`, `/aid-run`, `/aid-help` and the e2e role card** — status renders the controller state, the stall marker and the resume line, byte-locked against the published example render; `aid-run.md` documents the four controller states, why one of them can never be stored, and the resume flow as the AUTO contract's single carve-out from do-not-pause; the e2e card's infrastructure prose becomes "declare it", and the no-arbitrary-sleeps rule finally names its alternative — `probe_cmd`.
- **The AUTO controller loop has a mechanical liveness step** — `pipeline.md` now specifies `aid-job.sh watchdog` after each dispatch or gate action, `busy` meaning keep polling, and `resume_needed` routing into the recovery ladder, with a failed watchdog invocation logged and skipped rather than blocking gates.

### Fixed
- **The dangling permissions-defaults reference** — `/aid-run`'s S/M/L tier text pointed at permission keys that do not exist; it now names `auto-recovery.yaml` as the defaults authority, while the one reference that turned out to be live (`autonomous_mode`, read by `aid-release-policy.sh`) was left alone and is pinned by a test instead of assumed.
- **The invisible dead controller** — a run whose controller had died was indistinguishable from one making progress: no surface said so, and nothing pointed at the work still on disk. The derived stall verdict, the always-present continuation artifact and the single-use `resume` command close that gap end to end.
- **Unbacked measurement claims in this repository's own gate configuration** — the `bats_all` rationale quoted 1556 s and 1602 s as measured figures although neither has any record (both recorded samples exited 124 at the 600 s cap); the rationale now rests on what is on record — this gate has never completed, so its cost is unknown and known to be large.
- **A teardown refusal that asserted a cause it could not know** — the FSM's service sweep and the gate runner's release both reported any refused teardown as "another process holds this run's claim and is alive", although that refusal also covers a missing `jq`, a missing `yq` and an unreadable service declaration; both now defer to the library's own named line instead of naming a cause of their own.

## [2.79.3] — 2026-08-08

### Fixed
- **Scheduler Dispatch Dies On a Real Catalog** — `aid-test-scheduler.sh` passed the whole approved catalog (181 units, >1 MB as JSON) to jq via `--argjson`, exceeding Linux's 128 KB per-argument limit the moment the catalog was real — the observe_parallel divergence campaign could therefore never dispatch; the catalog now travels via a temp file and `--slurpfile`, the same fix this class of overflow already required in the resource map, the consolidator and the write-plan bridge.

## [2.79.2] — 2026-08-08

### Fixed
- **C4 Plan-Diff Vocabulary Mismatch Blocked Every Real Plan** — the plan-mode C4 release decision required plan-diff's overall_verdict to be present/absent, a vocabulary the producer only uses one level down (per-AC); the real overall vocabulary is pass/fail/partial/skipped, so every genuine plan-diff — verdict "pass" included — was blocked as "not bound to the frozen plan candidate"; the checker now speaks the producer's language (armed AC lens demands pass/fail; partial/skipped stay non-blocking only when no lens is armed, and never report as a pass). Found by finally reading the CI red streak: AC4 of the plan-final boundary suite had been failing since the vocabularies diverged.

## [2.79.1] — 2026-08-08

### Changed
- **P075 Remediation Rode Along (attribution)** — the P075 test-audit remediation steps implemented in this worktree (inventory bats_boundary reconciliation, resource-map string-literal guard, catalog npm:test build dependency + per-workspace split, CI jsonschema installs, live --state-file check) were swept into the v2.79.0 and v2.79.1 release commits by their `git add -A`; all 50 affected suite tests verified green post-push. Recorded here so the CHANGELOG matches what actually shipped.

### Fixed
- **Audit-Scoped Findings No Longer Block the Write-Plan Handoff** — the bridge required every cited run_unit_id to resolve in the current catalog, but findings about the audit run itself (`audit:<id>` — fabricated measured costs, missing repeat-run evidence) can never — correctly — appear in a catalog of test suites, so ANY audit with at least one audit-level finding was permanently blocked; audit-scoped ids are now exempt from catalog resolution while gate/suite ids stay strictly checked (found live by the WAN consumer, regression-tested).

## [2.79.0] — 2026-08-08

> "K čemu ty sady vlastně jsou a proč je máme?" had no answer in any artifact.
> Now it is a section: every gate named, its purpose derived from what it
> actually runs, EPIC codenames get purpose-based rename proposals.

### Added
- **Suite Overview Section (3b · Sady jmenovitě)** — the report lists every gate with its mechanically derived purpose (dominant topics of the files it runs), file and case counts, profile membership, and flags: no-op commands (`true`), required-but-in-no-profile orphans, and EPIC codenames (p070…) with purpose-based rename proposals (e.g. `p077_confirmations → cancel_confirmation`).
- **Gate File Resolution** — the scan resolves which test files each gate runs through explicit arguments, whole-argument directory expansion, bare js/ts runner conventions, and pytest markers — substrings of listed file paths never expand to their parent directory.
- **IMP-469 Backlog Entry** — standalone parallel test runner so the proven-safe lanes speed up ANY caller (agent, CI, terminal), not only the AID gate runner; recorded with enforcement named at design time.

## [2.78.0] — 2026-08-08

> A verification agent with a one-line prompt out-delivered this audit by
> asking "what exists" where the audit asked "what do gates run". Its edge is
> now mechanical: the audit reads CI, reads through wrappers, and prices tests
> apiece.

### Added
- **CI Test-Execution Check** — the scan reads CI workflow files and reports whether any of them actually runs a test, with commented-out test steps quoted as evidence; a project whose merges verify nothing gets a critical banner in the report headline (found live: a consumer CI whose pytest step had been commented out for a week).
- **Unrun Test Files In the Headline** — the count of test files no gate ever runs, out of the total on disk, is a headline stat instead of a buried table row.
- **Per-Test Cost Column** — the groups table shows seconds per test case where both cost and case counts are known, making "run the cheap unit tests more often" a number instead of an instinct.

### Fixed
- **Wrapper-Aware, Marker-Exact Reachability** — gate wrapper scripts are read one level deep but only their runner-invoking lines count (a registry checker that merely LOOPS over test paths no longer marks them as run), and a marker-filtered pytest gate grants reachability only to files carrying the marker, never by path overlap; on the consumer project this moved the unrun-files count from a false 364, then a false 22, to 162 — independently verified as 153 backend files plus 9 playwright scenarios.
- **Re-Measurements Replace Censored Receipts** — the report derives totals, censored counts and the top-10 from the LAST measurement per unit, so a suite re-measured at a higher deadline replaces its timed-out receipt instead of being double-counted next to it.

## [2.77.4] — 2026-08-08

> The owner asked "kolik testů máme" and the WAN report answered with a dash:
> the case counter only knew bats, in a pytest project. Counting is now
> runner-aware, like every other collector already had to learn to be.

### Fixed
- **Case Counter Counts Every Runner** — test-case counting now covers pytest functions and js/ts `it()`/`test()` cases in addition to bats `@test`, with a per-runner breakdown in the headline stat (WAN: dash → 6603 cases) and a static-lower-bound caveat for parametrized pytest tests.
- **Gate Names Never Masquerade As Case Counts** — gate unit ids are names, not file paths; the report no longer substring-matches them against test files, which had produced accidental case counts on gate rows.
- **Group Case Mapping Uses the Full File List** — the report mapped suite case counts from only the top-15 files of the scan; the scan now emits the full per-file list and the report consumes it, so group case columns no longer undercount.

### Changed
- **Groups Legend Explains Unmapped Cases** — when every group shows zero mappable cases (gates calling tests through opaque wrappers), the groups table says so and points to the portfolio total instead of leaving a silent dash.

## [2.77.3] — 2026-08-08

> An independent review of a real consumer report found the technical core
> correct — and two numbers whole sections stood on provably wrong, because
> the content scanner was written for bats and pointed at a pytest project.
> Every finding of that review lands here.

### Fixed
- **The scanner reads tests of every runner** — py/ts/tsx test files join bats in reference detection, and sources are matched by dotted module form too (`wan/api/scan.py` ↔ `wan.api.scan`), so a file 42 tests import is no longer "untested". The review's exact counterexamples now pass.
- **Unreachable test files are found across runners** — reachability walks gate commands' path tokens and pytest markers; the review's 153-file hole this check previously reported as "0" now surfaces, labelled as candidates where an opaque wrapper gate cannot be read.
- **Fabricated "measured" costs are arithmetic now, not diligence** — every disposition claiming `cost.kind: measured` is compared against the actual measurement receipt; mismatches and claims with no receipt render as a critical row. Caught 3 of the review's 5 on the spot (the other two sit inside a 10 % tolerance).
- **A green zero must mean "checked and clean", never "not applicable"** — bats-only checks on a bats-less project render "nehodnoceno" instead of an ok-pill zero, which the review rightly read as a contradiction.
- **The sources section stops naming a catalog that does not exist** — it now states whether an approved catalog was actually read, and that a zero parallel column is correct when none exists.
- **Reliability measures today's gates** — history of gates deleted from the current `execution.yaml` moves to a labelled footnote instead of rendering "0 % — dead" over a renamed gate, and every row carries this run's own outcome, so a gate that failed today cannot appear as 100 %.

## [2.77.2] — 2026-08-08

### Fixed
- **The report page was unreadable in mixed themes** — tokens flipped to dark while the page ground stayed light, producing black tiles on a white page. Background now binds to both `html` and `body`, so the artifact wrapper's own reset cannot split the themes.
- **"Kolik testů" finally answers in test CASES, not suites** — a mechanical counter totals `@test` cases per file (3 179 on this repository) and the groups table carries a per-group case column; where cases are uncountable (a gate wrapping an opaque command) the page says so instead of passing the suite count off as the test count.
- **An empty parallelism lever must name its blocker** — "nothing runs in parallel" with no cause read as "parallelisation is impossible"; the lever now aggregates the blocking resources from lanes and unresolved entries and names the one whose fix opens the pool, and when it cannot name one it says that is the audit's gap, not the portfolio's state.
- **Naming conventions are measured** — dominant name prefixes and the files outside any recognised pattern (50 on this repository), with the rename candidates listed in content-scan.json.

## [2.77.1] — 2026-08-08

### Fixed
- **Merges v2.76.1 into the 2.77 line** — the publish-the-page mandate embedded in the rendered summary; see v2.76.1 below. No behaviour beyond it.

## [2.77.0] — 2026-08-07

> P074 gave each plan its own worktree, and in doing so exposed something older:
> `epic-start` — the command that registers an EPIC's task branch with lineage —
> had been built, tested and documented, and never given a caller. Nobody noticed
> while everything ran in one checkout, because the lineage check was never
> reached there. The moment a plan implemented in its own tree, generation
> refused on a branch nothing had registered. This wires it, and restores every
> tree an init moves.

### Added
- **`epic-start` in the generation chain** — each EPIC's `task/<epic>/main` is registered with lineage back to `plan/<id>` before `init` needs it, for plan_branch plans. The mode is read from the plan's committed lifecycle manifest, never from the default-mode resolver, which answers a different question and downgrades to legacy without a gate_profiles table — that split would put generation and init on two different authorities. A standalone caller deriving neither flag gets the same registration, so it does not depend on who invoked the script.

### Fixed
- **A refusing `init` no longer parks you on a task branch** — `aid-json-to-run.sh` runs under `set -euo pipefail`, so a failing init aborted the script and skipped the branch-restore block directly below it, leaving the operator's checkout on the `task/<epic>/main` that init had auto-created on its way to refusing. The status is captured, the branch handed back, and only then is the failure reported.
- **Multi-phase generation completes** — `init` leaves the plan's worktree on that phase's task branch, and the pre-existing restore only ever inspected the caller's checkout, which does not move for a redirected init. Phase 2 then met a worktree still on phase 1's branch and hard-failed the cross-EPIC mismatch. The plan worktree is now returned to `plan/<id>` after each init; without it the wiring closed phase 1 only, and every real plan is multi-phase.

## [2.76.1] — 2026-08-08

### Fixed
- **Showing the report page to the owner no longer depends on an agent's obedience** — the page was generated on disk every run and the owner kept receiving the text wall, because publishing it was an instruction in a command doc the presenting agent never re-read. The mandate now travels INSIDE the rendered summary itself, as its first banner, naming the exact report path: an agent that pastes the block verbatim — which is the one behaviour agents demonstrably exhibit — pastes the order to publish the page first. The same instruction-without-enforcement defect this whole line of work exists to remove, rebuilt at the last step in front of the owner, now removed there too.
## [2.76.0] — 2026-08-07

> The owner's question was exact: "do we even have the data to fill the
> contract Codex expanded?" For most of it, yes — it was sitting in git and in
> the gate-run history, uncollected. Now it is collected every run.
> (Version 2.75.0 is a concurrent session's tag on another branch; skipped.)

### Added
- **Risk coverage collector** — every tracked source file no test references, churn-weighted from git history. "Unreferenced" is a necessary condition of no coverage, not proof, and the page says so. First run on this repository: 273 unreferenced files, led by one changed 8 times in 90 days.
- **Reliability collector** — gate pass rates from the real run history in `gate-runtime-baselines.yaml`. First run surfaced a gate with a 0 % pass rate over 14 recorded runs that nobody had noticed. Suite-level flakiness stays a named open gap until `--repeat` runs exist.
- **Trend between rounds** — every report writes `round-summary.json` and the next report leads with the diff: examined up or down, measured cost, censored count. Rounds stop being isolated snapshots.
- **Test freshness and ownership** — last meaningful change and top author per test file, from git.

### Changed
- **The canonical report grows to eleven sections** — Rizika and Spolehlivost join the nine, each with its collector, and the section list in the command contract is updated to match.

## [2.75.0] — 2026-08-07

> You could only work on one thing at a time. Not because AID said so, but
> because everything shared one checkout: opening a plan refused on an unrelated
> uncommitted edit, starting an EPIC moved the branch under whatever you were
> reading, and a second plan could not be written while the first was being
> implemented. Generation had the same shape one level down — a killed run
> regenerated from the top, asked for the same approval again, and died on its
> own duplicate. This release gives each plan its own execution tree and turns
> generation into a transaction you can resume.

### Added
- **Per-plan execution worktrees** — `plan-start` creates `.aid-worktrees/plan-<id>` checked out on `plan/<id>` and records it; every plan-linked command re-executes itself there rather than borrowing the tree you are standing in, so implementing one plan never moves the branch you are planning the next one on. A broken or unrecorded worktree refuses and names the audited repair instead of quietly falling back.
- **Locked plan-ID and EPIC-ID allocation** — `aid-fsm.sh alloc plan-id` / `alloc epic-id` serialize on a counter lock and rewrite only the digits, so two sessions can no longer mint the same id; every comment byte in `counter.yaml` survives.
- **Active-runs map** — `.aid-o/work/active-runs.json` holds one entry per live run instead of a single slot that only ever remembered the most recent one, and the main-branch guard reads all of them; `active-runs prune` removes entries whose run is gone or terminal and names what it removed.
- **Generation as one resumable transaction** — a `transaction.json` binds the plan bytes, the target head and the phase count into one identity, and every phase's status is DERIVED by re-hashing its outputs and reading queue membership rather than stored. A killed generation re-verifies what survived and continues from there; an already-queued entry is adopted, never duplicated.
- **One generation authority per plan** — CP1 runs once for the whole generation and seals a `generation-authority.json` receipt the per-phase converter verifies, instead of asking for the same approval at every phase.
- **Public `--force --reason` for generation** — the override an operator actually needs is a documented flag with a ≥20-character reason and the full three-record audit, replacing the undocumented environment variable it used to take.
- **`supersede-generation --plan --reason`** — an audited way to retire an incomplete transaction whose plan has changed underneath it. It archives, and deliberately deletes nothing.
- **Shared root resolver** — `lib/aid-roots.sh` separates the STATE root (one `.aid-o`, resolved through the git common directory) from the INVOKE root (the tree a command operates on), so state never forks per worktree.
- **`work/active.md` as a generated index** — written by named writers from live state instead of being hand-maintained prose that drifted.

### Changed
- **Preflights scoped to what a command actually touches** — `plan-start`, `epic-start` and `plan-merge-to-main` no longer refuse on a repo-wide dirty tree, because none of them can be harmed by one; `plan-start` instead asserts exactly its two tracked lifecycle paths are clean before any mutation. `epic-merge-to-plan` and the plan-finalize stages keep the check, evaluated against the tree they really check out, with that tree named in the refusal.
- **`/aid-status` shows both streams** — one block per active plan with its worktree, its EPIC rows and its queue rows, a `Closing:` bucket, and a deterministic next-EPIC rule; the plan-less layout is unchanged for projects that have no plan open.
- **Git hooks resolve the state root** — the pre-commit guard reads `.aid-o` through the git common directory, so a commit made from inside a plan worktree is guarded exactly like one made from the primary checkout instead of silently unguarded.
- **`/aid-run` selects among multiple active runs** — with more than one live stream it asks which, rather than assuming the only one it can see is the one you meant.

### Fixed
- **Adjudicator empty-list parse** — an empty adjudication list was read as malformed input; a genuinely nested key now fails loudly with the key named instead of being silently accepted.
- **Escaped-pipe table split** — a step table cell containing an escaped `|` was split into the wrong number of columns and the row was padded with `---` to hide it; the splitter now walks the escape grammar and fails with the arity it actually found.
- **Target-branch diagnosis** — an unresolvable target branch exited with a bare code and no advice; it now says which branch could not be resolved and what to do about it.
- **Stale `queue_status` in the generation receipt** — every EPIC stayed at the `pending_receipt` placeholder forever because nothing rewrote it after queueing.
- **Contract-gate SIGPIPE reported as a malformed contract** — a probe taking SIGPIPE on a large contract aborted the gate, and the abort was reported as the contract being invalid; the failure now names itself.
- **Unreadable plan-state diagnosed as a killed plan-start** — with `yq` missing, "the plan records no worktree" and "the record could not be read" were the same answer, so the crash-window refusal fired and told the operator their plan-start had died mid-transaction. Cannot-read is now distinct from definitively-none and falls back to the physical evidence; `plan-state --repair` also restores the worktree pointer it used to leave behind, or says plainly that it could not and names the command that does.

### Known limitation

P074 supports concurrent plan generation while another plan executes, but does
not yet support *starting* a newly generated plan's EPIC while another stream is
live. Legacy-mode generated EPICs may leave the primary checkout on
`task/<epic>/main`; plan-branch generated EPICs require `aid-fsm.sh epic-start`
before `init` and are not currently started by the generation pipeline. Both
paths are pinned by the two-stream integration fixture with their exact
production messages, so the day either is wired the pin goes red.

## [2.74.0] — 2026-08-06

> The report page had sections the audit collected no data for: duplicates,
> weak oracles, gate double-runs had been found exactly once, by hand, after
> the owner asked where they were. The lesson of the whole week, applied to
> content: what can be computed is computed, every run, and depth is never
> traded for the illusion of coverage.

### Added
- **`aid-test-content-scan.sh` — deterministic content checks in every audit.** Duplicate test-case names across files, weak oracles (≥80 % bare exit-code asserts, validator suites marked legitimate rather than hidden), gate overlap candidates (a file reachable from a direct gate and a pool gate — the double-run cost), and test files no inventory unit references. Runs at finalize with no LLM involved; the report's quality and levers sections consume it, so they are never a template over a void. On this repository it mechanically reproduced every hand-made finding: both duplicate pairs, all four weak oracles, the fsm double-run and the pool overlap.

### Changed
- **Depth over coverage — the sampling rule for shard analysts.** Skimming every assigned unit produced 176 of 181 "keep — unproved" twice, and the owner correctly called that worthless. Each analyst now deep-inspects a named sample (the larger of 5 units or 10 % of the shard, prioritized by cost, size, cluster representatives and content-scan flags), emits a `deep_sample` finding naming what it actually read, and abstains honestly on the rest — which the report counts as NOT examined. The examined count grows monotonically across rounds instead of resetting.
- **Censored measurements get one bounded retry.** A flat 300 s deadline censored the six most expensive suites across two full audits, leaving the portfolio's true cost unknown. Every timed-out unit is re-measured once at 4× the deadline, bounded by remaining budget; what still times out is reported as a lower bound with the retry recorded.

## [2.73.0] — 2026-08-06

> Four days of audits produced fragments — a count here, a cost there, each
> shown only after the owner complained about its absence. The requirement was
> always the opposite: one page, every section, every time, automatically.

### Added
- **`aid-test-audit-report.sh` — the ONE fixed-form report page every full audit produces.** Nine canonical sections: hlavní čísla, prověřenost, skupiny, co žere čas, kolik ušetříme čím, kvalita, akce a plán, nedokázáno, zdroje. The contract is completeness: a section whose data is missing still renders and says what is missing and why, because an absent section reads as "nothing to see here". A "keep" with unproved falsification is counted and displayed as **not examined**, never as health — the number the six-part summary used to hide is the second stat on the page. Generated automatically at the end of every full audit (a presentation failure warns loudly but never eats a completed audit), and the controller must publish it as an Artifact and lead the closing message with its link — the page is the audit's answer; the text block is the durable record.

## [2.72.4] — 2026-08-06

### Fixed
- **The ranked "Proposed changes" section rendered empty over 33 real actions** — the sort piped into a literal priority array before reading `.priority`, so jq indexed an array with a string and the one section this whole feature exists for silently died (`Cannot index array with string "priority"`). Bind first, then index; a regression test now asserts the section renders with critical first.

## [2.72.3] — 2026-08-06

> Two consumer audits independently hit — and one independently diagnosed, down
> to the schema rule — the next boundary: the consolidator smuggled analysts'
> risk notes into `impact.assumptions`, and the impact contract rightly forbids
> prose on an unknown impact with no number. 25 of 26 real actions failed on
> exactly that pattern.

### Fixed
- **Risk gets its own field instead of violating the impact contract** — a proposal's `risk_note` now lands in `action.risk` (bounded, rendered under the proposal), because it is a consequence of the change, not an assumption about a number. `unknown` impacts carry empty assumptions, as the schema always demanded.
- **A finding-level "measured" honestly maps to "estimated"** — a single number is a single run, not a before/after comparison; the mapping now states that instead of claiming a measurement. This is the same upgrade an adversarial wave demanded of a fabricating analyst in a real consumer audit — the schema was on its side all along.
- **The final bounding pass enforces the whole impact contract for every producer** — unknown-with-no-number drops its prose, an estimate with no stated assumptions gains its basis note, a "measured" with a missing endpoint is downgraded to an estimate with that stated. Producers that do not exist yet are covered by the same wall.

## [2.72.2] — 2026-08-06

> A consumer project (WAN) ran a full audit to the end — three agent waves,
> real measurements — and finalization died on format: the wave prompts said
> "quote the claim", the analysts wrote annotated citations, and the
> findings-to-actions wiring added in 2.71.0 copied that prose verbatim into
> decision fields whose schema demands bare paths and bounded text. Complete,
> valuable content; zero decision artifact.

### Fixed
- **Analyst prose is normalized at the schema boundary instead of killing the audit** — the schema stays strict on purpose (no secrets in prose, no unbounded text, evidence as bare artifact paths); the consolidator now extracts the bare path from an annotated citation (the annotation lives on in the finding text, where it belongs), truncates over-long reasons honestly, and rewrites an absolute path run in prose as relative. The refs survive; the run survives; nothing is silently dropped.
- **The prompts stop inviting the collision** — all six analyst prompts now state that `evidence_refs` are bare paths and that quotes belong in the claim text, naming the real consumer failure so the instruction carries its reason.

## [2.72.1] — 2026-08-05

### Fixed
- **Merges v2.71.1's renderer honesty fixes into the 2.72 line** — v2.72.0 was cut from a branch that predates them, so a summary could still read "all fine" over its own high findings there. No new behaviour beyond v2.71.1; see that entry below.

## [2.72.0] — 2026-08-05

> Three EPICs of loosening. AID was refusing work it had no physical reason to
> refuse: a completed plan-level review died to an audit-log append, a PM whose
> run went stale had no supported way forward except hand-deleting state, and a
> release could ship a changelog entry that said nothing. None of those are
> safety — they are bookkeeping obstacles wearing safety's clothes. Every
> loosening here is paired with an audited receipt, so what used to be
> unrecorded surgery is now a decision with a name on it.

### Added
- **PM force backdoor** — every plan-level precondition is classified `forceable` or `hard` at its call site; a forceable one can be passed with `--force --force-reason "<why>"`, which writes a waiver receipt BEFORE the command proceeds and refuses the force outright if the receipt cannot be written. Identity, evidence integrity and PM authorization are `hard` and cannot be forced at all.
- **PM-override grant for C3** — a single-use, PM-signed artifact claimed with `mv -n` plus a mandatory source-gone post-check, because coreutils 9.1 exits 0 when `mv -n` skips the move. One PM decision authorises one action and never a second.
- **`plan-finalize --stage accept-ancillary`** — records that a plan head which differs from the frozen candidate only in ancillary paths still describes the reviewed delivery. It writes one receipt, binds it in the manifest, and leaves `candidate_sha` byte-identical.
- **`plan-state --supersede-epic`** — an audited transaction that retires a stale EPIC FSM run and authorises exactly ONE re-initialisation, replacing the hand-deletion of state files it used to take.
- **Committed-source preflight** — plan generation refuses to bind a whole lifecycle to plan bytes that exist in exactly one worktree, before any git mutation.

### Changed
- **CP1 review budget raised to 5 sessions** — three was measured to be the wrong number; legacy ledgers keep their old cap and migrate on the next locked write, so no in-flight review changes shape underneath its author.
- **Review equivalence replaces any-movement invalidation** — the drift detector, the review pre/post checks, the C4 decision and the merge all accept a head at a receipted accepted head as well as at the candidate. A plan frozen before this release keeps the old any-movement rule byte for byte.
- **Freeze stores the protected path surface** — every step's `allowed_paths`, the source plan, the lifecycle manifest and the close-consumed receipts, in the same atomic write as the candidate. A set that cannot be completed is recorded as PARTIAL and equivalence is simply unavailable.
- **One ancillary classifier** — four verbatim copies of the same exception regex became one library with a MANDATORY mode argument, so no caller can silently inherit a wider exception set, and an unreadable policy fails closed to the legacy paths.
- **Step rendering and dependency grammar** — an unparseable dependency token is now a hard failure at generation time instead of a silently dropped edge that produces a plausible, wrong run order.

### Fixed
- **Version-stamped heading in aid-audit-tests.md** — v2.71.0 shipped a heading carrying its own version number, which the repository's own skill linter forbids; the whole suite was red until it was dropped.
- **Release script silent aborts** — a `grep | head -1` probe took SIGPIPE on large inputs (measured 20/20 at ~290KB) and the aborted probe read as a clean absence, so the release silently skipped work it believed unnecessary.
- **Placeholder release entries** — a release whose CHANGELOG section for the new version is empty or a placeholder is refused; the entry is the only human-readable record of what shipped.
- **Reporter plan-boundary contradiction** — a Reporter round no longer moves the candidate it is reporting on.
- **Branch-restore continuation** — a failed branch restore stops the run instead of continuing on whatever branch the worktree happens to be on, where every subsequent command succeeds while operating on the wrong branch.

## [2.71.1] — 2026-08-05

> A real full audit rendered "Keep as-is (162), Remove: none, nothing parallel"
> while its own Technical evidence listed five high findings — the summary told
> the owner everything was fine, in layout if not in words, and he rightly
> called it worthless. The looks-clean-over-problems defect this renderer
> exists to prevent, committed by the renderer itself.

### Fixed
- **Section 2 can no longer stay silent over its own evidence** — findings that recommend a change but carry no ready-made proposal now render in the decision section as a ranked "Needs work" list with severity and unit, instead of appearing only in the technical appendix below the fold.
- **"Nothing runs in parallel" now says how much is unlockable** — when the same artifact lists units blocked by a FIXABLE resource, the count and the pointer render in the same breath; bare "nothing" read as "parallelism is impossible here" over seventy fixable units.
- **The verdict must be presented in the user's own language, never softer than the evidence** — the six-part block stays verbatim as the durable record, but the controller now must precede it with a short summary in the language the user speaks, leading with what is wrong: finding counts by severity, fixable-blocker count, gates that never complete. The lead may never claim less work than the findings imply.
## [2.71.0] — 2026-08-05

> Until now the audit classified, measured and proved — and then told the owner
> "fix" with no object. The analysts were required to record every resource with
> file:line and forbidden from concluding anything with it: their instructions
> allowed exactly two endings, a lane or a measurement. This release adds the
> third ending the whole exercise was for.

### Added
- **Findings carry concrete remediation proposals** — the exact change with file:line ("a.bats:359 writes under a fixed path; allocate a per-test temp dir"), an effort bucket built from counted facts (S/M/L/decision-required, with a separate verify bucket, because a delete is S to perform and L to verify and the verify cost is the one that decides), and a benefit that is measured, extrapolated, estimated or **unknown** — unknown being a normal answer an honest audit gives often. Time benefits count only on the critical path: 30s saved beside a 5-minute serial test saves nothing.
- **Both directions, not just subtraction** — an audit that can only shrink a suite monotonically degrades safety. New recommendation values: `add` (a missing error-path test — benefit is risk, not seconds), `strengthen` (a weak oracle gets a real assertion instead of deletion), `rewire` (a gate that runs a unit twice, a unit no gate runs, a timeout below real runtime).
- **Guards on everything destructive** — remove/merge are always decision-required; "asserts nothing" must survive checking exit-code semantics and custom helpers; a duplication claim must name its basis, never file-name similarity; a test born in a bugfix commit is presumptively load-bearing; the adversarial wave now verifies proposals like findings and flags a confident number whose evidence tier cannot support it.
- **Proposals have identity and memory** — a stable `proposal_id`, a declined ledger (`.aid-o/config/test-audit-decisions.yaml`) so a declined proposal is marked and never re-litigated, and `conflicts_with` cross-references on both sides of contradicting advice ("share the setup" vs "isolate per test"), computed as well as declared.
- **The proposals reach the artifacts people read** — findings' proposals become `decision.json` actions (a bare verb without a proposal deliberately does not), ride into the remediation brief the plan is generated from, and render as a ranked, capped list — the artifact keeps everything, the render shows the top slice, because an audit emitting four hundred proposals has produced zero.

## [2.70.8] — 2026-08-05

### Changed
- **The audit now offers the catalog approval instead of leaving it on the floor** — it produces a proposed catalog and, by design, never writes the approved one; that boundary is right, because the catalog is an execution allowlist. What was wrong is that finishing the job then required knowing two script names. The controller now says what the catalog holds, asks whether to approve it, runs both steps on a plain yes, and names anything the approval would revoke before asking. Only then does it offer the remediation plan — first make the tests run right, then decide what to fix.

## [2.70.7] — 2026-08-05

> The audit could prove which tests are safe to run side by side, and had no way
> to write that down. The proof landed in `decision.json` and the catalog — the
> file every consumer reads — came out with every unit `unknown` regardless.

### Added
- **`aid-test-catalog-apply-evidence.sh` — the missing link between what the audit proves and what the catalog says.** It promotes the units of every `proposed_parallel` lane to `parallel.status: safe`, bound to the content they were verified against, and carries forward evidence the previously approved catalog already held for units whose content has not moved. Carrying forward is safe by construction: every entry is bound to a source hash and a resource digest, so anything whose file changed fails its own binding and reverts to `unknown` with no list to maintain. It runs automatically at the end of every full audit; before this, the only path from evidence to catalog was a one-shot migration written for P071's text allowlist, and everything else was manual.

### Changed
- **A bare `/aid-audit-tests` asks instead of assuming** — it used to fall back to `static`, which answers a different question than the one most people are asking, while `full` refused to start without a budget nobody remembers. The controller now offers the recommended run (full, 180 minutes) in one sentence and accepts a plain yes. Explicit arguments still win.

## [2.70.6] — 2026-08-05

> Found by a real full audit of this repository: 174 run units and 158 447 bytes
> of findings were enough to kill the only mandatory closing step, so a
> completed audit produced no decision artifact at all.

### Fixed
- **Consolidation died on any portfolio big enough to matter** — `--argjson` puts a whole JSON value in ONE command-line argument, and Linux caps a single argument at 128 KB (`MAX_ARG_STRLEN`) no matter how large `ARG_MAX` is. The findings set, the aggregated resource maps, the pilots, the inventory, the keep/rewrite/remove sets, the lanes and the profile actions all scale with the portfolio and all went through argv, so `aid-test-audit-consolidate.sh` failed with "Argument list too long" — and because it is the only mandatory closing step and fails closed, the audit ended with nothing. Every value that grows with the portfolio is now read from a file. This is the same defect fixed in `aid-test-resource-map.sh` in 2.70.2 and not swept for at the time; the regression test builds a 226 KB artifact, and its own fixture hit the limit first, which is a fair measure of how easy it is to reach.

## [2.70.5] — 2026-08-05

### Fixed
- **An audit that loses its own evidence now survives it** — a real full audit had its entire output tree deleted during a cost-profiling run: inventory, catalog, eight agent artifacts, measurements, 112 resource maps, and finalize then had nothing to read. 2.70.3 reduced the exposure and added a detector, but detecting a loss still costs the operator the run. The tree is now copied before the profiled command starts and restored if anything disappears, so the audit keeps its evidence and continues; the receipt records `evidence_loss_restored` so a restored run is never mistaken for a quiet one. **The cause of the deletion is still not identified** — every `rm` in the production scripts, `TEST_PROJECT_ROOT`, `git clean`/`reset --hard` and `aid-job.sh --repo` were ruled out — so this is a safety net, not a fix.

## [2.70.4] — 2026-08-04

> A third real audit found the profiler emitting receipts that failed its own
> schema while reporting success, so consolidation rejected all of them and the
> audit died with no artifact naming the cause. Two of the three blockers were
> introduced by this plan's own earlier releases.

### Fixed
- **The profiler wrote receipts its own schema rejects, and exited 0 doing it** — `job.jobs_dir` was added in 2.70.3 without checking the schema, which declares `additionalProperties: false` on `job`, and the no-per-case-timing branch emitted `timing: {}` where `cases`/`planned`/`truncated` are required. Both are fixed, and the profiler now validates its own receipt and fails with exit 14 rather than moving the failure three steps downstream where no field can be named.
- **`evidence_refs` had two different contracts on either side of a wave boundary** — the wave-artifact schema set no `minItems` while the consolidated-findings schema requires 1, so an agent could hand in an artifact that passed its own validation and then killed consolidation with an internal error naming neither the finding nor the field. The producer is held to the strictest consumer's rule: a finding with no evidence is not a finding.
- **A run unit could carry two different commands and be profiled against the wrong one** — measurement reads `execution.yaml`, the profiler reads the catalog. Where they disagreed, this repository measured a 25-minute pool runner and then "diagnosed" a quarantine stub that exits in three seconds, recording `complete: true`: the check meant to prove the slow suite was diagnosed was satisfied by evidence that it never ran. Divergence is now refused with exit 15.
- **Four test fixtures invented their own inventory shape** — `run_units[]` where the scanner and the schema say `entries[]`. One was found by an audit and three more by the inventory validation added in 2.70.1, which had left two suites red across three releases because its effect was never run against every consumer.
- **A gate run's stdout is a JSON document, and 2.70.3 wrote a warning across it** — the "this run is not accounted by a ledger" notice went to stderr, which merges into stdout for any caller capturing both, so the report became unparseable and four gate-runner tests went red. The notice is now a field on the report (`_execution_ledger.accounted: false` with its reason), which is durable, machine-readable, and cannot corrupt the contract it is describing.
- **A selector fixture asserted that an unbound `safe` is parallel eligible** — since P072 a status with no provenance object resolves to `unknown`, because a status nothing verified is a claim rather than evidence. The fixture had been asserting the opposite of what the product does.
- **A suite asserted renderer wording removed when the six-part summary landed** — `finalize-production` had been checking for "audit NOT complete" and "Units left undecided" since that rewrite. Aligned to what the renderer actually prints.

## [2.70.3] — 2026-08-04

> A second real audit lost its own evidence: the entire
> `.aid-o/work/test-audits/<id>/` tree — inventory, catalog, eight agent
> artifacts, measurements, 112 resource maps — disappeared during a cost
> profiling run, and the finalize step then had nothing to read. Ninety minutes
> of work, gone, with no error.

### Fixed
- **The cost profiler wrote into the audit's own evidence tree, and that tree vanished during a profiling run** — the mechanism was not identified, so this fixes what can be fixed and refuses to let it be silent again. Job records now live inside the disposable clone instead of `--output-dir`: the profiler had no reason to write there, since the only thing the audit needs back is the receipt. And the audit's file list is recorded before the profiled command runs and checked after — anything that disappeared is named and the run exits 13, because an audit that quietly loses its own evidence reports a smaller portfolio than it examined with nothing to show anything is missing.
- **The slowest unit in the portfolio was the one guaranteed never to be profiled** — `profile-select` took only `terminal_pass`/`terminal_fail`, on the reasoning that an unfinished job has no duration worth ranking. That is backwards for a timeout: exhausting a deadline is a lower bound and the strongest cost signal there is. `timed_out` units are selected now and carry `measurement_kind: "lower_bound"` so they can never be read as a measurement; `lost` and `cancelled` stay out, because those have an absence rather than a duration.

## [2.70.2] — 2026-08-04

> A second real audit run got further and hit the next wall: the resource map
> crashed on this repository's two largest test files. Not a defect of the
> audited project — a defect of the plugin doing the auditing.

### Fixed
- **`Argument list too long` killed the resource map on large files** — the assembled document was passed to `jq` with `--argjson`, which puts the whole JSON in ONE command-line argument, and Linux caps a single argument at 128 KB (`MAX_ARG_STRLEN`) no matter how large `ARG_MAX` is. This repository's two biggest test files produce maps above that, so the script died and wrote nothing. The three unbounded values are read from files via `--slurpfile` now, and the same treatment is applied to the catalog's `source_pattern_mappings`, which scales with the selector rather than with anything bounded.

## [2.70.1] — 2026-08-04

> The first real `--mode full` audit of this repository reached a terminal state
> without producing a decision. It found three independent blockers, each fatal
> on its own, plus five smaller real defects. This release is those fixes.
>
> Live acceptance remains pending: the audit still has to complete, and the
> consumer E2E from an installed plugin has not run.

### Fixed
- **`--mode full` could never finish on real data** — the consolidator read `.run_units[]` from the inventory while the scanner and the inventory schema both say `entries[]`, so every full audit died at consolidation. The regression suite missed it because its fixture was hand-written in the invented shape, which is why the consolidator now schema-validates the inventory before reading a field: a fixture that makes up its own contract proves only that two pieces of test code agree.
- **The cost profiler refused every gate unit** — it rewrote a gate's shell-form command into `bash -c …` to hand it to the job supervisor, then asked an allowlist that compared shell-form objects for exact equality. Same command, allowed as shell, refused as argv, exit 11, no receipt — and since the selector always picks the most expensive unit, and that is always a gate, it failed every time. The allowlist now compares the canonical execution form, which widens nothing.
- **`bats --timing` was inserted into the wrong argv slot** for shell-form commands, producing `bash --timing -c …`. Those units get a file-level lower bound instead, the same fallback as any runner that cannot report per case.
- **A freshly-proposed catalog could not be approved** — the scanner wrote `source_pattern_mappings: []` unconditionally while the approver re-derived the real map from a fresh selector snapshot and refused anything that did not reproduce it. Both now call one shared derivation.
- **Approving a scan silently revoked parallel-safety evidence** — a scan classifies every unit `unknown`, so approving one over a catalog carrying real pilot evidence discarded it: 65 units out of the pool and a 24-minute concurrent run back to serial, with nothing announcing it. Approval now names what would be revoked and requires `AID_CATALOG_ACCEPT_REVOCATION=1`.
- **Seven entrypoint scripts were committed non-executable** — invoked as the docs write them, without a `bash` prefix, they exited 126. Six command-file references named scripts that only exist under `scripts/lib/`. Both are now checked by a suite.
- **A missing golden directory minted a new baseline** — `test-epic-to-json-regression.sh` recorded whatever the code currently produced and reported `0/0` with exit 0, so a broken refactor became the expected result in any checkout without the fixtures. It now fails; regenerating requires `AID_REGENERATE_GOLDEN=1`.
- **The resource map read jq's `. as $x` as a shell `source`** — dot-space at the start of a line matched the source-directive rule, producing `as` as a file to resolve, which inflated `unresolved_sources` and helped hold maps at `capped_at_unknown`.

## [2.70.0] — 2026-08-04

> Superseded by 2.70.1, which fixes three defects that made `--mode full`
> unable to finish on real data. Live acceptance is still pending — the real
> full audit (Step 24) has not completed and the consumer E2E from an installed
> candidate has not run (`docs/plans/P072-real-audit-record.md`) — and nothing
> in this line of work may be described as delivering test-suite acceleration,
> because the measurement campaign has not been run either
> (`docs/plans/P072-campaign-ledger.md`).

### Added
- **Source-aware resource map, parallel pilot and provenance-bound catalog** — parallel safety now rests on two kinds of evidence: a map read from source that cites `file:line` for every resource it records, and a pilot that runs a lane's exact membership serially and concurrently in a disposable clone. A promoted `parallel.status` carries where it came from and is bound to the unit's whole dependency closure, so a shared helper acquiring a lock reverts it on its own.
- **Execution ledger (`aid-test-execution-ledger.sh`)** — records one entry per run unit actually dispatched during a gate run and fails when the same unit ran under two gates. Four emission paths — the bats lane, the aggregate runner, the scheduler, and the gate runner itself for directly-invoked commands: without that fourth one it would have certified this repository's own double execution as clean. It is fail-closed throughout: inside an accounted run, a failed open, a failed append, a missing ledger file or an unevaluable close each fail the gate run, because a ledger with a gap reports zero duplicates exactly like a clean one.
- **Deliberate repeats are declared, not inferred** — an execution can record itself as `retry` or `escalation`, and P069's escalation subprocess marks everything beneath it that way. Those are reported separately as `deliberate_repeats` rather than failing the run, while an undeclared repeat is still a double execution — the default is `normal`, so forgetting to mark one is never a free pass.
- **Decision artifact for full audits** — `decision.json` (`aid-test-audit-decision-v1`) carries one terminal disposition per run unit, the portfolio arithmetic, the proposed actions with their impact, and the parallelization lanes. `--write-plan` is gated on it.
- **Cost profiler and deterministic profile selection** — a bounded per-unit diagnosis that runs only against a disposable clone, only through `aid-job.sh`, and reports a lower bound rather than an extrapolation when it does not finish. Which units owe a profile is a policy, and finalization fails when a selected one has no receipt.
- **Five report shapes end to end** plus a clean-clone authority E2E, both driving the real production entrypoint rather than library functions.

### Changed
- **`test-aid-fsm.bats` no longer runs twice per full and release gate run** — `bats_fsm` is dropped from those two profiles, which already run that file through `bats_all`'s pool. This was the live duplication the execution ledger found; the detector's red proof moves into a fixture so removing the waste does not blind the check.
- **Frozen portfolio counts replaced by reconciliation** — the shell-adapter check asserted "exactly 36 suites, 7 declined", which this plan's own new suites made stale. It now asserts that every `test-*.sh` present is accounted for exactly once, discovered or declined with a reason.
- **One authority over parallel safety** — `aid-bats-parallel-lane.sh`, `aid-test-scheduler.sh` and `aid-select-tests.sh` all resolve through `aid_test_catalog_effective_status_map`. The separate text allowlist is retired to a notice, and P071's evidence is migrated with `method: migrated_p071_step3` — except for files changed since P071 verified them, which stay `unknown` and are named rather than re-blessed.
- **The scheduler overlay is subordinate to provenance** — it may still promote a unit nobody has assessed, and can no longer rescue one whose content moved after it was verified. A contract change from P069, recorded with its reasoning in `docs/plans/P069-recontract-check.md`.
- **The audit's chat handoff leads with the decision** — six sections and a technical appendix, replacing a verdict followed by a severity-ranked findings list. A full audit with no decision artifact, or with one that does not validate, now refuses rather than rendering "No action needed".
- **`run-all-tests.sh` result parsing** — suite results are read token-by-token against the shapes this repository's suites really print; anything ambiguous is `unparsed` and fails the aggregate instead of counting as zero tests.

### Fixed
- **The parallel-safety resolver was unusable on the hot path** — 101s to partition this repository's own pool, because it re-parsed the catalog and shelled out to the map builder once per unit. One batch pass with a shared budget: 60s.
- **An incomplete audit could render as "Verdict: clean"** — the renderer classified from findings alone, so an audit that never finished looked like one that found nothing.
- **Profile ingestion failed open** — a corrupt, foreign or tampered receipt became an empty action list, which reads exactly like "nothing needed doing". Every lane and profile input is now schema-validated and bound to its audit.
- **Three shipped documents described `parallel.status` as having no consumer** — which stopped being true once the lane and the scheduler both began resolving through it. The sentence is corrected in all three and pinned by `test-instruction-consistency.sh` so it cannot reappear.

## [2.69.0] — 2026-08-02

### Fixed
- **Files/Scope path parser no longer silently narrows multi-path entries** — `lib/aid-scoping.sh`'s shared cleaner (`_aid_split_path_entry`) now fails loudly on any unparsed remainder after a Files/Scope entry's path list (comma-separated, conjunction-joined, or otherwise ambiguous), instead of silently keeping only the paths found before the ambiguous text. Applies uniformly to the per-step scoping block, the legacy flattened `## Scope > Allowed files/paths` broadcast fallback, the generation-time preflight (`aid-plan-to-epic.sh`), and the D5 contract gate — closing the gap where a malformed multi-path entry could authorize a narrower `allowed_paths` set than the plan actually declared.

## [2.68.0] — 2026-08-02

### Added
- **`aid-bats-parallel-lane.sh`** — replaces the self-host `gate:bats_all` quarantine stub with a real, explicit-allowlist-based parallel bats runner: an approved-safe allowlist (`defaults/config/bats-parallel-safe-allowlist.txt`, opt-in, tracked) gates which bats files enter the `bats -j N` pool; anything not on the allowlist (a brand-new file, or the catalog's still-`unknown` `parallel.status`) runs sequentially instead of being silently skipped or auto-parallelized. Fail-closed path validation rejects nonexistent files, paths escaping the repo root, arguments starting with `-`, and duplicate catalog entries before any `bats` invocation.
- **`gate:bats_boundary`** — a new, separate `required: false` gate for the 2 bats files (`test-aid-plan-final-boundary.bats`, `test-aid-plan-release-boundary.bats`) too expensive to pool or bound with a short timeout; wired into the `full`/`release` gate profiles so it is actually reachable by a real profiled run.
- **`aid-self-host-migrate-p071-gates.sh`** — an idempotent `apply`/`verify` migration script + hashed local receipt so this repo's own gitignored `.aid-o/config/execution.yaml` gate changes survive a clean re-init instead of silently vanishing; a live-guard bats test asserts the real, current execution.yaml satisfies all migrations.

### Fixed
- **`gate:plan_diff` timeout** — was a bare, unexplained `120`; now `300`, traceable to this gate's own historical baseline data, with the prior "34 min of wall clock" incident's attribution to `plan_diff` vs. `shell_pipeline_smoke` explicitly documented as unresolved (the config file predates this attempt's git history and is itself gitignored).
- **`gate:shell_pipeline_smoke` naming** — its description now states plainly that it runs the full aggregate suite (~32 min), not a fast/partial smoke check.
- **`aid-plan-diff.sh` `overall_verdict` vocabulary mismatch blocked `plan-finalize`** — `aid-plan-diff.sh` has always emitted `pass|fail|partial|skipped`, but three consumers (`aid-plan-fsm.sh`'s `--stage inputs` and `--stage review` C3-input checks, and `aid-c3-dispatch.sh`'s `build-manifest` gate) expected `present|absent|skipped` instead — a vocabulary that field never actually carries. Any plan with a required AC lens (`ac_to_test_identity`/`requirement_test_drift`) armed therefore always failed `plan-finalize`, regardless of whether its ACs actually passed. Fixed all three consumers to recognize the real `pass|fail|partial` values, translating to each consumer's own existing downstream vocabulary where one already existed (`aid-c3-dispatch.sh`'s `plan_diff_status` and the plan-boundary-manifest's `plan_diff_verdict` both keep their `present|absent|skipped` enum — only input recognition changed). Also corrected a stale `_generated_by: v2.20.2` version stamp in `aid-plan-diff.sh` to the current version.

## [2.67.0] — 2026-08-02

### Added
- **Test scheduler (opt-in, staged Constraint-8 rollout)** — a new `aid-test-scheduler.sh` batches and dispatches `targeted_tests` execution units as real, tracked async jobs (`aid-job.sh`) instead of one sequential process; enabled only after a project passes a 3-stage rollout gate (`sequential` → `observe_parallel` → `parallel`), each requiring 3 qualifying, full-catalog-covering divergence-evidence artifacts — `sequential` remains every project's default until it explicitly opts in.
- **`aid-run-gates.sh` scheduler dispatch + escalation** — `targeted_tests` now dispatches through the scheduler when a project's rollout stage allows it; an unverifiable (exit 3) or mapping-gap (exit 11) result automatically re-runs as a separate `--profile full` subprocess, never in-process, whose report becomes the verdict-bearing result.
- **Execution-unit membership + concurrency-context evidence** — `execution-unit.schema.json`, membership verification, and `concurrency_context` on `gate-runtime-baseline.yaml` give every scheduled unit a real, schema-bound identity and shared-state accounting.
- **`aid-select-tests.sh --emit-units`** — a new selector output mode the scheduler consumes directly, additive to (and behaviorally identical to) the existing default selection path.
- **`bats_all` quarantine remediation evidence collector + E2E full-path proof** — a collector (`test-integration-quarantine-remediation-evidence.sh`) now packages this repository's own `bats_all` divergence measurements (membership agreement, shared-state findings, streamed diagnostics, resume-without-orphan, measured — never invented — runtime) into a schema-valid bundle once the real, multi-hour sequential+scheduled measurement campaign has been run; that campaign itself remains deferred for this repository (unit-tested against synthetic fixtures only, per a standing PM decision), so no real bundle ships in this release yet. A genuine 10-stage E2E proof exercising the real configured-profile → gate-runner → scheduler → receipts path end-to-end DOES ship, in disposable fixtures. `plan_diff` is explicitly named as unresolved and out of this plan's scope.
- **PM quarantine-decision-record mechanism** — a schema-valid lift/keep/defer decision record, producible only via explicit PM input, citing both evidence bundles above; superseding an existing decision requires naming the current record exactly (fork- and race-proof via a per-gate lock), and no code path ever writes to `execution.yaml`'s `quarantine:` block automatically.

### Changed
- **Enforcement registry + docs** — 3 new scheduler-related enforcement rows and a new README section document the `test_audit.scheduler.mode` config knob and the rollout/escalation behavior above.

## [2.66.2] — 2026-08-02

### Added
- **Formal Curator adjudication of Auditor findings (D5, IMP-468)** — a raw Auditor blocker (severity critical/high) can no longer be waved off by a bare `curator.blocking_findings: false`; the Curator must record a schema-bound `curator.adjudications[]` entry per finding, exactly bound to the audit report hash, candidate and run. Enforced at both the plan-final review boundary and, for the first time, the `.aid-lifecycle` classifier (previously blind to adjudications, permanently misclassifying a legitimately adjudicated plan as rejected) — via a new shared resolver, `lib/aid-adjudication.sh`.
- **Plan-final C3 dispatch identity + AC-verdict pinning (D2, IMP-464)** — the shared C3 bridge now carries a plan-shaped identity (`AID_C3_PLAN_ID`) instead of misreading the plan-final run directory as an EPIC id, and pins `plan-diff.json`'s hash (`AID_PLAN_DIFF_SHA256`) so C3 cannot dispatch over evidence that drifted from what `--stage inputs` sealed. `audit-input-manifest.json` is now a required `--stage review` output, chained to `audit-report.json`'s claimed input hash.

### Fixed
- **Durable close-evidence receipt published atomically (D1, IMP-466)** — the plan-final close-evidence receipt is now sealed and pushed to the remote alongside `main` in one atomic transaction, not as an afterthought after `main` is already public; a fresh clone that has lost its local runtime evidence can recover and close a plan using only what was pushed. Two related recovery-path gaps (repair/recovery incorrectly requiring the never-pushed `plan/<id>` branch to exist) were also closed.
- **Plan-final review TOCTOU closed (D3, IMP-465)** — `--stage review` now snapshots every required output once, before validating any of them, so a file cannot be swapped between being validated and being sealed into the durable receipt.
- **Receipt inventory frozen per schema version (D4, IMP-467)** — the plan-final receipt's required-output inventory check no longer re-derives its expected list from the live plugin code (which would retroactively invalidate receipts sealed by an older version); it is now a literal, versioned list, restored at every verification and recovery site including one that had been missed.
- **C3 dispatch false-negative on a missing jq binding** — a missing `jq --arg` binding in the shared C3 bridge's report writer made every C3 dispatch (not only plan-final) silently fall back to an `outcome: "invalid_output"` unverifiable report instead of a clean pass/fail one; found via full-suite regression while validating the above.

## [2.65.0] — 2026-07-30

### Added
- **`/aid-audit-tests` — test portfolio audit capability** — deterministically inventories a project's test portfolio (Bats, package-script/CI, and declared-gate run_units), optionally measures a bounded subset safely via the approved-catalog-only command allowlist, and ends every run with a mandatory 5-part plain-language chat recommendation. Static mode never executes tests; measure/full modes run only commands already present in the target project's real `execution.yaml` or an approved test catalog — never free-form output.
- **Test catalog `proposed`→`approved` lifecycle** — `aid-test-catalog-approve.sh` force-tracks a reviewed catalog into git at the fixed canonical `.aid-o/config/test-catalog.yaml` path; a separate, mandatory `aid-test-catalog-confirm-mapping.sh` gate (with a reviewed-diff hash) is required before `source_pattern_mappings[]` may be treated as authoritative — approving the catalog file never implies approving the routing map.
- **Chat-first recommendation and sanctioned `/aid-plan write` handoff** — every completed audit's final turn contains a verdict, up to 5 evidenced reasons, what changed, a next action, and residual risk; a same-conversation "vytvoř plán oprav" reply (or `--write-plan`) resolves to one shared, fail-closed validator before the controller ever invokes `/aid-plan write` for real.
- **`/aid-init` distribution of `test-audit.yaml`** — the new project-level audit config is now installed copy-if-absent, byte-identical to its hardcoded loader defaults.
- **Self-host dogfood + generated remediation plan** — `/aid-audit-tests` was run against `aid-orchestrator` itself in a disposable clone, producing this repository's first real approved test catalog (83 run_units) and a separate, generated remediation plan (P070) tracing every item to a specific finding.
- No scheduler, batching, or `aid-run-gates.sh`/`aid-select-tests.sh` execution-path integration ships in this release — that is the dependent P069 plan's job, against this release's own shipped, stable catalog/config contract.

## [2.64.0] — 2026-07-28

### Added
- **Plan-global generation receipt** — a hash-bound receipt now proves that every generated EPIC package, its contract evidence and its plan JSON still match the reviewed source plan before strict execution may begin.

### Changed
- **Two-stage EPIC generation** — the pipeline now generates and validates every phase before it creates any run, FSM state or queue entry, so a normal plan no longer needs a PM override for an artefact that generation itself must create.
- **Source dependency graph** — C0 now receives a provisional, source-plan graph built by the same fail-closed parser used by the generator, while its per-EPIC graph remains a separate sealed input.

### Fixed
- **Generation integrity** — ambiguous dependencies, comma-separated multi-path `Files:` entries, drifted generated dependencies and incomplete multi-phase evidence now fail before execution instead of being silently accepted or overwritten.

## [2.63.2] — 2026-07-27

### Fixed
- **test-fsm's increment-step assertions** — they expected the pre-IMP-263 bare number, which the CI step timeout had hidden since 2026-07-23.

### Changed
- **Backlog records P068 as done** — released as 2.63.0, live-verified by the P077 dogfood, with the three `before P068` prerequisites marked satisfied against the code that satisfies them, and IMP-280 added: a dogfood must not run in a linked worktree sharing refs with the repository it tests.

## [2.63.1] — 2026-07-27

### Fixed
- **P064 fixtures under the completion gate** — the suite merged EPICs straight from `running`, which is the hole the gate closes; its seed now completes the EPIC it creates and the three cases that need an unfinished one say so explicitly.
- **Project-root resolution for linked worktrees** — an explicitly named `--project-root` is honoured only when the plan runtime state actually lives there, so an ordinary worktree still shares the main checkout's state while a separate dogfood checkout resolves to its own.
- **CI bash-test timeout** — the suite outgrew its five-minute step and timed out at 55 of 84; raised to twenty.

## [2.63.0] — 2026-07-26

### Added
- **Plan-final release boundary** — a plan in `plan_branch` mode now releases exactly once, at its own boundary: one gate profile run against a frozen candidate, one specialist review, one PM authorization bound to that candidate, one compare-and-swap merge to the target branch, at most one tag, and a committed lifecycle receipt without which the plan cannot be declared closed.
- **`plan-close` as a real gate** — the close transaction verifies EPIC terminality, EPIC merge ancestry, the gate report, every review output re-hashed against its record, the C4 and PM decisions, the merge record and its ancestry, the tag state, `MERGE_HEAD`, unfinished operation records and held locks before it writes anything, and only then commits the receipt and the head-bound marker.
- **`aid-plan-fsm.sh inventory`** — enumerates every plan with its declared mode, EPIC counts and disposition, and with `--apply` stamps unstamped plans `legacy_epic_release_mode` without migrating them or creating a branch.
- **`defaults/policies/plan-boundary-policy.yaml`** — the default mode, lock lease and plan-final profile floor, as a file a project can override rather than a constant it cannot.
- **`AID_PLAN_FSM_CRASH_AFTER` test seam and the AC9 resilience matrix** — every transaction boundary is exercised by real process death and asserted to converge without a duplicate merge, tag or receipt.
- **`test-control-boundary.sh` and `test-instruction-sweep.sh`** — mechanical guards that the plan boundary changed WHEN reviews run rather than whether existing enforcements enforce, and that no unqualified per-EPIC release instruction survives on an agent-facing surface.
- **Agent handoff contract** — `skills/agent-protocol.md` states the five boundary messages an agent working inside a plan-branch plan may rely on.

### Changed
- **Default mode for new plans is `plan_branch`** — guarded on the project declaring a `gate_profiles` table, falling back to `legacy_epic_release_mode` with a logged `plan_branch_unavailable: no_gate_profiles` otherwise, so a consumer project cannot flip to a mode whose gates would resolve against nothing.
- **Specialist cadence** — Auditor, Curator, Simplifier and Reporter are plan-final roles under `plan_branch`, dispatched once per plan against the frozen candidate; CP2 and CP3 remain per EPIC.
- **Lifecycle manifest write is fail-closed under `plan_branch`** — a manifest that cannot be written no longer degrades to a warning, because no manifest means no declared mode, which means the plan runs legacy while everyone believes otherwise.

### Fixed
- **`pre-push` exemption checked only the local ref** — `git push origin plan/P068:main` slipped the guarded target branch through; both sides of the refspec are now checked.
- **Stale-authorization guard could be disarmed by history** — any recorded `resulting_sha` disarmed it, so a rewound target branch let a publish land against a head the PM never approved.
- **Abort close was single-shot** — the abort's own lifecycle commit advances the target branch, which the check read as a violation, making every re-run including crash recovery permanently refused.
- **Fail-open paths closed** — a missing frozen target head, an absent tag record, an unrecognised closure state and a missing lifecycle manifest each block instead of passing.
- **The plan was closed before its evidence was checked** — `cmd_plan_close` ran the irreversible plan-layer close ahead of the required Curator/Auditor report gate, so a missing report failed only after the plan was already closed in the books.
- **The declared mode was written but never committed** — the stamp lived in the worktree while the git-tracked authority carried none.

## [2.62.1] — 2026-07-24

### Fixed
- **IMP-263 increment-step is now fail-closed** — strict binding is the default for a new (non-grandfathered) run so unbound evidence is rejected without any env, a partial binding (any missing field) is rejected instead of skipping the id/hash/commit checks, and a hand-inserted transition-ledger row can no longer masquerade as crash recovery: self-heal runs only when the live step-verify carries a complete, plan/HEAD-verified binding matching the ledger row.
- **IMP-269 C3 fail-closed checks the AC source location and receipt consistency** — `ac_source: plan` is earned only by a file under the canonical `.aid-o/plans`/`.aid-o/tasks` tree (any other in-repo file downgrades to `final_report_fallback`); a git-tracked plan is read from the reviewed HEAD, while a gitignored `.aid-o` plan is a canonical worktree artifact sealed into the bundle; and a targeted-run receipt is checked for consistency with its named command, the reviewed HEAD, and a named in-repo log (`log_sha256` must equal that log's recomputed hash). This is consistency-checking, not cryptographic provenance against an actor who can directly edit the evidence files — such an actor is outside this local AID trust model.
- **IMP-270 waiver re-validation cannot fall back to the current HEAD** — a report that declares a waived gate but omits or malforms its `revision.head_sha` now fails closed immediately instead of passing an empty HEAD to the waiver tool, which would have validated the waiver against whatever was checked out rather than the reviewed revision.
- **IMP-262 cancel-before-PID race closed** — a cancel landing before the job wrapper records its pid/pgid is no longer lost: cancel drops a durable request marker and the wrapper self-cancels at entry and immediately before exec, so a job can never start after a cancellation is recorded.

## [2.62.0] — 2026-07-24

### Added
- **Controller-owned background job supervisor (`aid-job.sh`)** — opt-in `run|status|collect|cancel|watchdog|redgreen` giving a long-running command a durable identity and a terminal result a resumed controller can collect without `tail -f`, a notification, or the launcher staying alive; `/proc` starttime pins process identity against PID reuse, `collect` returns `in_flight` never a pass, and `redgreen` stores revision-bound paired receipts that reject a fabricated pass. Advisory/opt-in — no FSM or gate path depends on it.
- **Gate-scoped single-use waiver (`aid-gate-waiver.sh`)** — a per-gate waiver bound to project/epic/run/exact-HEAD/gate-id/command-fingerprint that reports a failed required gate as `waived` (never `pass`) for exactly one gate, replacing the broad FSM `--force` that skipped every precondition; the FSM re-validates each waived row at read time and fails closed on a bare `waived`.
- **C3 test-evidence channel** — `build-manifest` seals a validated, HEAD-bound targeted-run receipt into `evidence_hashes`, so a truthful targeted suite at the reviewed HEAD is consumable rather than forcing a false `unverifiable`.

### Changed
- **Idempotent, step-bound `increment-step`** — step-verify evidence carries a binding (step index/id, plan-step hash, reviewed commit, idempotency token) validated against the live plan before any mutation, a durable ledger makes advancement replay-safe (`status=already_applied` on replay), and machine-readable `status=` stdout replaces the bare number the controller once misread as an error.
- **One committed-tree mode authority** — `cmd_init` now resolves plan mode through the same fail-closed committed-manifest resolver as `done-advance`; missing `yq`, an unparseable manifest or an unknown mode resolve to `unresolved`, never silently to legacy.
- **PM-brief evidence freshness is computed at read time** — the brief no longer echoes a frozen `head_is_current`; it preserves the referenced SHA and reports freshness by comparing it to the current HEAD, so a post-generation commit reads as stale.

### Fixed
- **C3 AC source is explicit and enforced** — the manifest records `ac_source` (`plan|final_report_fallback|stub`); when a run requires an AC lens and the source is not the real plan the build fails closed, and pointing the AC file at (or a byte-identical copy of) `final_report.md` is downgraded rather than laundered into a `plan` classification.
- **Fail-closed lineage** — an omitted lineage argument now defaults to `unproven` (was `proven`), `--repair` on a healthy manifest is a byte-identical no-op that preserves attestation, repair per-write failures propagate instead of being swallowed, and attestation re-derives ancestry from Git and fails closed when it cannot be proven. Repair still never mints `proven`.
- **Plan mode must be explicit at `plan-start`** — an omitted `--mode` is a usage error and `plan_branch` is hard-refused until the P068 plan-final commands exist (the self-asserted `--allow-incomplete-plan-final` bypass was removed as unauthenticated).
- **Queue `merge_target` is authorized, not just parsed** — a dependency's owning plan is derived from its epic id, not read from the same hand-editable `plan_id` field, so `plan_id: P999` + `merge_target: plan/P999` can no longer self-authorize an ancestry anchor; a declared `plan_id` that disagrees with the derivation is refused.
- **`grep -oP` portability guard is repo-wide** — the epic-id derivation is pure bash and a scanner refuses any new non-comment `grep -oP` under `scripts/` outside an explicit allowlist, so the portability defect cannot move between files and stay green.
- **Enforcement-registry honesty** — writer-only controls whose P068 reader does not exist yet are recorded `planned`/`unmapped`, not `active`.

## [2.61.0] — 2026-07-23

### Added
- **`epic-complete` and `epic-merge-to-plan` (`aid-plan-fsm.sh`)** — an EPIC is finalized and integrated into `plan/Pxxx` inside one reconcilable transaction, where Git ancestry is the only accepted proof that the work landed and a manifest `lineage: proven` is the only accepted authority to record it; `state: DONE`, a deleted task branch and a queue entry claiming completion are explicitly not proof, `merged_to_plan` is terminal, and the target branch is never read or written.
- **`lib/aid-queue-write.sh` — the single queue writer** — enum-validated status transitions, an atomic next-EPIC claim performed inside one lock hold, structural validation of every appended entry block, and the new `plan_id` / `merge_target` fields; `queued` stays accepted on read so entries written by older plugin versions remain parseable.
- **Boundary-split gate profiles** — `gate_profile_resolve` gained a `boundary` parameter so an EPIC boundary caps at `standard` while the unbounded result is preserved out of band as the accumulated plan-final floor; the self-host `gate_profiles` table is activated with `docs_updated` in every include list.
- **Five canonical enforcement registry rows** for the EPIC-boundary cap, the plan-final gate record, the `plan_branch` release skip, the unresolved-mode block and the single mode authority.

### Changed
- **Dependency readiness proves ancestry against a declared `merge_target`** instead of guessing `main|master|HEAD`, which reported an EPIC merged into `plan/Pxxx` but not yet released as blocked forever; for an entry carrying a `merge_target` the evidence-based fallback chain is unreachable, so a hand-edited `completed` status can no longer unblock dependent work — a queue entry is a derived view, never evidence.
- **The per-EPIC release stack is structurally silent in `plan_branch` mode** — `cmd_done_advance` resolves the plan's declared mode and skips every stage named in one `AID_PLAN_BRANCH_SKIPPED_STAGES` constant, emitting that list in the timeline; an unresolvable mode is a hard block rather than a fallback, because falling back would merge an individual EPIC into the target branch.
- **One mode authority** — both mode resolvers read the declared lifecycle manifest from the target branch's committed tree; the gitignored runtime manifest is no longer a mode input, an uncommitted or unreadable declaration is `unresolved` rather than an answer, and each resolver keeps its own fail-safe direction (gate routing degrades toward more gates, release routing hard-blocks).
- **`skills/pipeline.md` and `commands/aid-run.md`** carry the mode fork, a full exit-code table for the two new commands, and an honest statement of which parts are wired versus documented.

### Fixed
- **Queue write injection via `awk -v`** — `awk -v` is not a literal channel on either mawk or gawk, so a two-character backslash-n in a free-text reason smuggled a second assignment into the write payload and landed an entry on a terminal status the caller never requested, destroying a neighbouring key and leaving the file unparseable as YAML while the reader kept consuming it; attacker-influenced values now travel through `ENVIRON`, the parse layer aborts the whole write on a malformed payload, and reasons plus ids read back out of the file are charset-validated.
- **The queue append door** — `aid-queue-add.sh` interpolated every argument-reachable field unvalidated, and matched `depends_on` with a BRE instead of a literal so `--depends-on 'E-81.'` bound a dependency on an id that does not exist.
- **Plan id derivation no longer depends on `grep -oP`** — `-P` is a GNU-grep build option that fails outright rather than failing to match, which wrote `plan_id: null` and silently stopped a multi-EPIC plan after its first EPIC on any host without PCRE support.
- **Contract twins agree** — writer and reader resolve a dependency's branch by one rule validated with `git check-ref-format`, so a git-legal branch name can no longer be unclaimable through the queue while the FSM reports it ready.

## [2.60.1] — 2026-07-22

### Changed
- **AUTO liveness and controller ownership contract** — autonomous runs now retain controller
  ownership through a terminal outcome instead of stopping on recoverable technical forks or
  indefinite "waiting" states. Technical recovery is routed to bounded Codex adjudication; PM
  escalation is reserved for decisions that require new authority.
- **Background-job and test-evidence discipline** — instructions now forbid `tail -f` completion
  watchers, require explicit job identity/deadlines, bind test claims to the reviewed revision and
  command, prevent pre-fix aggregate results from proving post-fix code, and avoid duplicate full
  suites.
- **Agent role boundaries** — the controller owns FSM changes, commits, aggregate gates, and
  evidence finalization; implementers run targeted work without orphaning jobs, and verifiers use
  immutable isolated revisions. Instruction-consistency tests protect these contracts from drift.

## [2.60.0] — 2026-07-20

### Added
- **C0 plan-review — pre-EPIC cross-provider review (`aid-c0-plan-review.sh`)** — before a
  risky plan is even turned into an EPIC, a real independent Codex CLI review of the plan
  itself now runs (mirrors the C3 bridge's `build-manifest`/`dispatch`/`verify` shape, same
  transport, different target and schema). High-risk plans get a bounded, ledger-tracked
  fix→reverify loop (same-hash re-dispatch guard in both legacy and `AID_C0_ATTEMPT`
  attempt-explicit modes); Codex-reported `unverifiable` and content-invalid responses
  (hash/head mismatch, C3-shaped output, missing `action_owner`) are both treated as
  untrusted and correctly propagate a non-zero exit from `cmd_dispatch`, never masked as a
  clean pass.
- **CP1 revision-limit ledger (`aid-cp1-ledger.sh`)** — mechanically enforces how many
  revision rounds a plan gets during C0 review (previously only written down in
  documentation, never enforced by code). Full ledger-file invariant validation (attempt
  counts, fixed policy max, plan-id match, ordered attempts_log), `flock`-protected
  read-modify-write on increment (concurrent-safe), and a real single-use PM-override
  artifact (`cp1-pm-escalation-override.json`, atomically claimed and consumed) for
  authorized bounded-loop bypasses — replacing an earlier bare-env-var bypass.
- **Bounded C3 fix→reverify loop (`c3/attempt-NN/` + `c3/loop-summary.json`)** —
  `AID_C3_ATTEMPT`-driven per-attempt evidence layering, terminal-outcome tracking (an
  ALLOWLIST of recognized terminal values — any unrecognized/corrupted outcome is treated as
  terminal too, fail-closed), a controller-judged `escalate` subcommand for conflicting
  findings, and a `c3_fix_loop` policy (`max_rechecks: 2`) in `c3-audit-policy.yaml`.
- **Advisory Claude fallback for C3 (`c3_advisory` audit mode)** — when Codex is genuinely
  unavailable (down, rate-limited, no auth), the system runs a same-provider Claude fallback
  review instead of silently skipping. Always honestly labelled "advisory, not independent"
  and never satisfies `c3_required` (D7 echo-only) — policy default flipped
  `c3_on_unavailable: unverifiable → degraded_advisory`.
- **Versioned `c3-audit-prompt-v2.md`** (v1 frozen) — explicitly separates always-allowed
  read-only operations from `allowed_recheck_commands` (narrowly scoped to re-executing a
  named test/gate command), fixing IMP-245 (an empty `allowed_recheck_commands` list read
  over-conservatively as "no commands allowed at all," blocking even Codex's always-required
  basic repo reads — found via 2 consecutive real dogfood runs).
- **Full protocol-v2 envelope on `c3-dispatch.json`** (`aid-protocol-validate.sh`,
  `aid-c3-dispatch.sh`) — `c3_dispatch` added to `VALID_ARTIFACT_TYPES` /
  `TYPE_PAYLOAD_MAP`, and `_write_dispatch_json` now emits `control_protocol`, `identity`,
  `subject.subject_hash`, and the correct `provenance.dispatch_mode: deterministic` (was
  incorrectly hardcoded to the C3-domain value `cross_provider`, conflating the envelope's
  "how was this artifact produced" concept with C3's own
  `independence.achieved_independence_level`). Closes a gap that had silently affected every
  EPIC's evidence pack in this plan, discovered only while exercising a real end-to-end
  Curator/CP4/delivery-gate closure for the first time.

### Changed
- **FSM `done-advance` C3/C0 hooks harden against the bounded-loop bypass class** — the
  same-hash re-dispatch guard now applies in both legacy and `AID_C0_ATTEMPT` modes; a shared
  `pm_override_claimed_this_call` flag prevents one claimed PM-override artifact from being
  consumed twice when both C0 guards fire on the same dispatch call.
- **`cmd_done_advance` (`aid-fsm.sh`) gained a directional phase-edge check** —
  `review → release` is now the ONLY legal `done_phase` forward edge; a prior gap let
  `release → review` regress the phase backward with no negative test catching it.
- **`review-profiles.yaml` surface coverage improved** — `e2e/evidence/**` fixtures now
  classify as low-risk (were previously falling through to `unverifiable`, over-triggering
  C3 review on test fixture churn).
- **CI `bash-tests`** (carried from 2.58.4, first released here) — the SIGPIPE flake in
  `test-regression.sh`'s `grep -q` usage is fixed across all eight affected sites.

### Fixed
- **CRITICAL: `aid-c3-dispatch.sh verify` did not bind `audit-report.json`'s own semantic
  fields to the raw Codex response** — `status`/`review_status`/`outcome`/
  `unverifiable_reasons` were unbound, so a hand-edited `unverifiable → pass` flip on a
  committed report still verified clean and could have let `done-advance`'s merge gate
  wrongly advance under `enforcement: blocking`. Fixed with one shared
  `_derive_report_semantics` function used by both the writer and the verifier, additive
  binding checks, and an FSM-level rejection test. Independently re-verified 3 times (CP2
  security re-review + 2 fresh CP3 passes) before merge.
- **`cmd_dispatch` (`aid-c0-plan-review.sh`) returned exit 0 for a transport-genuine but
  content-invalid C0 review response** — the final exit-code decision checked only the
  transport-level `$outcome`, never the already-computed `$presp_rc` or the written report's
  own `review_status`. A hash/head mismatch, schema-invalid output, or Codex itself honestly
  reporting `unverifiable` all still returned exit 0, letting a caller treat an untrustworthy
  review as a clean pass. Found by this EPIC's own 12th live Codex CLI DONE-review audit
  against its evolving HEAD; fixed by checking `presp_rc`/`review_status` before returning 0,
  matching the pattern the ledger-increment gate already used.
- **A real Codex session UUID was briefly committed** during this plan's EPIC-4 CRITICAL-
  bypass fix cycle; already resolved via a PM-directed history rewrite (git plumbing, object
  pruned) before this release.

This release ships the full **C3 Cross-Provider Dispatch Bridge** plan (P065, 7 EPICs,
E-065-1_7 → E-065-7_7): C3's dispatch/validate/normalize/verify core (2.59.0) is now joined
by real merge-gate enforcement, the advisory fallback, the bounded fix→reverify loop, and the
plan-time C0 counterpart with its own revision-limit ledger — the first time AID's
"independent cross-provider audit" claim is backed by an actually-independent, actually-
verified second opinion end to end. Enforcement stays staged at `observe`, not `blocking`,
for both C3 and the CP1 ledger; full production promotion is a separate, deliberately
deferred decision (P062/E10). E-065-7_7 (the final EPIC) merged as an explicit PM-authorized
risk-accepted override rather than a green `aid-release-policy.sh` gate — see
`.aid-o/work/evidence/E-065-7_7/R-E065-7/merge-decision.md` for the full reasoning.

## [2.59.0] — 2026-07-15

### Added
- **C3 cross-provider dispatch bridge** — `aid-c3-dispatch.sh` performs the real independent audit that E8 only detected the feasibility of, using a genuinely different vendor (Codex) instead of an in-process Claude call. `build-manifest` assembles a hash-manifested audit brief (changed files + risk profile + rendered prompt); `dispatch` invokes the Codex CLI as a fresh subprocess, always probed as `cross_provider` and non-sticky, then crosses the untrusted-response trust boundary (schema-validate hardened against a multi-document-JSON bypass, normalize, write report or write-unverifiable); `verify [--reference]` re-binds the written `audit-report.json` to the raw Codex output and confirms it describes HEAD (provenance + faithful-transform proof). Independence comes from the vendor split and a fresh process, not a filesystem sandbox — Codex reads the repo read-only.
- **Versioned C3 prompt template and deterministic renderer** — `c3-audit-prompt-v1.md` plus `aid-render-prompt.sh` render the same brief from the same run facts every time (the prompt is versioned data, not an ad-hoc string), alongside `c3-codex-response.schema.json` as the external-response contract that routes any off-shape reply to unverifiable rather than a coerced pass.
- **`c3_executor` audit policy** — `c3-audit-policy.yaml` gains an executor-first block with a `cross_provider` probe and `c3_on_unavailable: unverifiable`, so an unavailable executor degrades fail-closed (blocking for C3-required profiles) rather than silently skipping; the `degraded_advisory` disposition ships in a later phase of this plan.

### Changed
- **FSM `done-advance` C3 hook now enforces the provenance + faithful-transform chain** — the hook shells out to `aid-c3-dispatch.sh verify`, making the full report↔raw binding a real, deterministic, merge-blocking capability in code rather than prose. Shipped enforcement stays `observe`; blocking activation is decided at a later milestone (E10) after calibration, matching every other C-stage gate's promotion pattern.
- **`pipeline.md` `c3` audit dispatch uses the real bridge** — the `c3` audit mode now calls `build-manifest`/`dispatch`/`verify` instead of an in-process Claude `Agent()` audit; `legacy_health` mode is unchanged, and `agents/auditor.md` was synced (`C3.1a` state-matrix mirror, `C3.2` scoped to `legacy_health`).

## [2.58.4] — 2026-07-14

### Fixed
- **CI `bash-tests` SIGPIPE flake in `test-regression.sh`** — the CI job had been failing for several releases on the F1 check `echo "$done_section" | grep -q 'C+A Execution Model'`. `done_section` is the whole ~36 KB §7 DONE of `pipeline.md`; `grep -q` exits on the first match and closes the pipe, so `echo` takes a `SIGPIPE` (141) and — under the suite's `set -uo pipefail` — the pipeline returns non-zero, flipping the `if` to false and falsely reporting the (present) section as missing. Reproduced locally at ~1-in-5 runs, deterministic on the CI runner. Fixed by feeding grep via a here-string (`grep -q PATTERN <<< "$var"`) so there is no early-exiting pipe reader; applied to all eight `echo "$var" | grep` sites in that suite. Other suites share the pattern only on small (sub-pipe-buffer) variables that cannot trigger the race, so they were left unchanged.

## [2.58.3] — 2026-07-14

### Added
- **Plan-time Files-shape lint (`aid-plan-lint.sh`)** — malformed `**Files:**` entries are now caught when the plan is written, not phase-by-phase during EPIC generation. A plan whose Files entries would break the generation-time D5 `allowed_paths_shape` gate (a bold-wrapped bullet, a parenthetical-only bullet, a prose-only entry, a word before the backtick path, or a verb+path split across two lines) is rejected up front, with the exact `plan.md:line` and the canonical grammar to fix it. The lint runs at two points: automatically in `/aid-plan` right after the plan is written (early feedback, before CP1), and — the enforcement of record — as a deterministic hard pre-flight inside `aid-plan-to-epic.sh` that fail-fasts before any EPIC file is written or the plan counter is bumped, so it cannot be skipped the way an agent instruction can. Two-tier severity: ERROR (the shared cleaner yields no path or a bad-shape path — WILL break the gate) always blocks; STRICT (cleaner-OK but non-canonical) blocks `lifecycle_strict` plans and is a loud advisory for legacy plans, so already-working plans are never suddenly globally blocked.

### Changed
- **Single source of truth for Files parsing** — the lint, the generator (`aid-plan-to-epic.sh`), the JSON deriver (`aid-epic-to-json.sh`) and the D5 gate (`aid-contract-validate.sh`) now all share ONE extractor (`_aid_extract_files_bullets`), ONE path cleaner (`_aid_split_path_entry`) and ONE shape predicate (`_aid_path_shape_ok`) in `lib/aid-scoping.sh`. `aid-plan-to-epic.sh`'s own duplicated copy of the cleaner and its inline Files-extraction awk were removed and replaced by the shared functions (verified byte-identical generation), and the gate's inline shape check now calls the shared predicate. An integration test proves a lint-clean plan flows clean through `plan-to-epic → epic-to-json → contract gate`, so the lint and the generator provably cannot have a different reality.
- **Plan Files-entry grammar is documented + enforced** — `skills/plan-writing.md` now states the canonical Files grammar (`- <Create|Modify|Test|Rewrite>: \`path\` [ + \`path\`]* [(lines ~N-M)] [— prose]`) with explicit NEVER rules, and `commands/aid-plan.md` runs the lint before CP1 in both brainstorm and write modes.

## [2.58.2] — 2026-07-14

### Fixed
- **Untracked manifest is no longer overwritten (parity with the receipt guard)** — `aid_lifecycle_ensure_manifest` previously wrote the manifest straight over the worktree path, so a foreign untracked `.aid-lifecycle/manifests/P<NN>.yaml` could be clobbered (the receipt path already guarded this, the manifest did not). The manifest is now built into a temp file first; an existing untracked manifest is re-committed ONLY when it is byte-identical to the freshly-generated canonical one (our own interrupted-run artifact), and a differing untracked manifest is refused fail-closed (rc 4), never overwritten.
- **Receipt-commit failure no longer returns success** — after the last required EPIC, both `record-delivery` and `plan-reconcile --apply` attempted the closure-receipt commit but, on failure, continued to the status echo and exited 0. The derived state never lied as `closed`, but automation received a false success while the closure receipt was not durable. A receipt-commit failure now propagates a non-zero return (rc 5) while the stdout state line stays honest. (Includes a fix to a bash `[[ … ]] && { … }`-as-last-statement gotcha that made a clean `plan-reconcile --apply` return 1.)
- **D1 dependencies are expressible on the normal path** — a plan can now declare `depends_on_plans:` in its frontmatter (added to the plan template) and `ensure_manifest` writes it into the tracked manifest at scaffold, so the D1 init gate actually hard-blocks on an unclosed structured dependency without a hand-crafted manifest. Legacy plans without frontmatter get an empty list, unchanged. Frontmatter extraction is mikefarah-yq safe (`// []`, not the jq-ism `[]?`) and tolerates leading blank lines before the opening `---` fence, so a stray blank line can never silently drop a declared dependency (a D1 gate fail-open).

## [2.58.1] — 2026-07-14

### Fixed
- **IMP-232 closure model wired into the runtime lifecycle** — v2.58.0 shipped the closure library/CLI but the normal AID flow never invoked it (it only wrote the legacy `ca-review-complete` marker), so no manifests/receipts or `closed` state were ever produced during real work, and the `aid-fsm.sh plan-reconcile` command the init advisory told users to run did not exist. This release completes the wiring, with one concrete, named, tested call path: (1) the pipeline creates a git-tracked lifecycle manifest — repo identity + manifest committed together — at official plan scaffold, so a new plan never waits for a manual reconcile to have a manifest; (2) a single post-merge hook `aid-fsm.sh plan-record-delivery <epic_id>` — a named, tested call path invoked as the pipeline's post-merge step (skills/pipeline.md step 15a, run on the target branch immediately after the agent-run branch merge, at the same enforcement level as that merge) — records the real merge SHA + review provenance and writes the closure receipt so the plan becomes `closed` when the last **required** EPIC is delivered + review-accepted; (3) `aid-fsm.sh plan-reconcile` / `plan-record-delivery` / `plan-state` now exist as real subcommands (no contradictory entrypoints); (4) every lifecycle commit uses a truly isolated git index (`GIT_INDEX_FILE` temp index) so the user's staged/working files are provably never touched — verified by index-fingerprint fault-injection tests, not just a clean worktree after recovery; (5) a merged EPIC whose historical review is unverifiable is recorded `delivery: delivered, review: unverifiable` — the plan stays `active`, never falsely closed and never presented as "accepted". Pre-merge `plan-close` still only verifies reviews + keeps the marker (no delivery SHA, no tracked commit on the task branch). End-to-end tested: manifest-at-scaffold, real-merge provenance recording, last-required→committed receipt→`closed`, clean-clone→same `closed`, P061-shaped delivered-but-unverifiable→`active`, and no lifecycle op changing the user's index at any interruption point.
- **Lifecycle isolated commit refuses UNSTAGED user collisions, not just staged ones** — the isolated commit builds its tree from the worktree files on disk, so an uncommitted user edit to an already-tracked `.aid-lifecycle/` manifest or receipt could previously be swept into AID's automatic commit if the user had not `git add`-ed it. The entry precheck now fail-closed refuses BOTH a staged lifecycle path AND an unstaged modification to a tracked lifecycle path, and this precheck runs before `bind_delivery` mutates the manifest in `record-delivery` and `plan-reconcile --apply` (not only inside the commit helper, which runs after AID has legitimately written its own content). Additionally, an untracked receipt already on disk from an interrupted run is only re-committed when it is byte-identical to the freshly-generated canonical receipt — a differing untracked receipt is treated as a user collision and refused, never overwritten. `record-delivery` now propagates ANY non-zero `ensure_manifest` result (including a refused collision) instead of only codes 2/3/5, so a non-durable/collided manifest can never fall through into a bind/commit. On refusal the user's edit, the index, and `HEAD` are left byte-identical.
- **Scaffold manifest enforcement is opt-in per plan, never silent** — the manifest-at-scaffold step splits by a new `lifecycle_strict: true` plan-frontmatter flag (added to the plan template, so new plans are strict by default): a strict plan whose EPIC declaration is ambiguous FAILS-CLOSED before any EPIC is generated (fix the `**EPIC N: …**` / `**EPIC N / Backlog: …**` grammar, or set `AID_LIFECYCLE_MIGRATION=1` for an explicit audited legacy run), while a legacy plan without the flag proceeds under a loud, logged migration (`[WARN] … AUDITED migration` + a `.aid-o/work/lifecycle-migration.log` marker) rather than a silent skip. This keeps pre-`lifecycle_strict` fixture plans and real legacy plans (table/`##`-header grammar) working without weakening the fail-closed guarantee for new plans.

## [2.58.0] — 2026-07-13

### Added
- **Canonical plan-level closure (IMP-232)** — a durable, evidence-anchored, PUBLIC-SAFE lifecycle model that replaces the scattered, gitignored per-EPIC `ca-review-complete` markers as the source of truth for "is this plan done?". Git-tracked `.aid-lifecycle/` artifacts (a stable repo-identity UUID, per-plan manifests, and closure receipts) survive a clean clone and the eco-dev↔eco-prod mirror, while all detailed evidence stays in gitignored `.aid-o/`. States: `active` / `delivered-but-unreconciled` / `closing_pending_commit` / `closed` / `legacy-unverifiable`, with a required-only denominator (backlog EPICs never block closing). `aid-lifecycle.sh` exposes read-only queries + artifact validation; `plan-close` (forward path) and `plan-reconcile` (`--dry-run`/`--apply`, legacy migration) are the mutating, metadata-only, fail-closed operations. A binding public-safe contract (JSON-Schema `additionalProperties:false` + a value/secret/abs-path/free-text-key net) gates every artifact before it is committed, so the tracked receipts carry only technical fields — never report bodies, findings, prompts, absolute paths, secrets, PII, or waiver reasons. `delivered` requires an unambiguous merge reachable from the configured `target_branch` bound to the EPIC via reviewed-head provenance (a well-named merge alone never closes a plan); a missing/ambiguous binding is `legacy-unverifiable`, never a guess.
- **Dependency-scoped init gate (D1)** — an independent plan's state NEVER hard-blocks another plan's `init`. The old global cross-plan `ca-review-complete` precondition (which blocked P065 because P061 was mid-flight) is removed. A hard block now occurs ONLY when the initializing plan declares a structured `depends_on_plans` target that is not closed (still `--force`-overridable and audited); legacy prose `depends_on` is advisory-only. A single actionable init advisory summarizes delivered-but-unreconciled plans (CI-suppressible), never per-EPIC. Branch-enforcement, clean-worktree, duplicate-state, and rogue-commit guards are unchanged.

### Changed
- **`per_step_scoping` gate precision** — a multi-step EPIC whose steps legitimately refine the SAME file(s) in sequence (distinct outputs) is no longer mis-flagged as the P057/P058 broadcast bug. The check is now authoritative-block-first: when the EPIC declares explicit per-step scope blocks, each generated step's `allowed_paths` must equal what its own block declares (via a shared `lib/aid-scoping.sh` cleaner, so the generator and the gate can't drift); degenerate blocks (identical files AND outputs) still fail (R7); and legacy inputs without per-step blocks fail only when BOTH `outputs` AND `allowed_paths` are identical across all steps. The genuine broadcast bug still fails.

### Fixed
- **`test-run-gates` cwd-isolation flake** — the gate-runner tests wrote their runtime `gate-runtime-baselines.yaml` into the shared `tests/` cwd, so an accumulated baseline could make `run-all` return non-zero and flake the whole suite (reproduced on a clean tree). The suite now runs from a throwaway isolated cwd.

## [2.57.2] — 2026-07-13

### Added
- **Audited cross-plan force-init passthrough (`--force-init-reason`)** — `aid-json-to-run.sh` and `aid-auto-pipeline.sh` gain an explicit, invocation-scoped `--force-init-reason "<why>"` flag that forwards the sanctioned `aid-fsm.sh init --force --reason` override to the FSM. It waives ONLY the plan-level DONE gate (the false-positive cross-plan `ca-review-complete` precondition raised when a different plan is intentionally in progress); all other init checks (branch enforcement, clean-worktree, duplicate-state) still run and are not masked. The FSM enforces a ≥20-char reason and records the override to the run timeline, the cross-EPIC audit log, and a waiver artifact. It is a CLI flag rather than an env var, so it cannot leak into unrelated inits.

### Fixed
- **`aid-epic-to-json.sh` Files-verb parser dropped `Test:`/`Rewrite:` labels into `allowed_paths`** — the label-strip step only removed `Create:`/`Modify:` prefixes, so a Files entry using the plan-template-sanctioned `Test:` or `Rewrite:` verb kept its label and produced a non-path-like `allowed_paths` entry (still carrying the `Test:`/`Rewrite:` prefix), breaking the pipeline `allowed_paths_shape` contract. All four verbs are now stripped.
- **`fsm_force_override` timeline event lost at `init` time** — the arg-parse loop reached `--force` before `cmd_init` created the evidence directory, so the timeline event was written into a nonexistent directory and silently dropped (the audit log and waiver survived because they `mkdir` first). The override is now recorded on all three surfaces (timeline + audit log + waiver).

## [2.57.1] — 2026-07-13

### Fixed
- **`aid-gate-runtime-baseline.sh` flaky `series_reset_at` on fast/CI runners** — `gate_baseline_update` and `gate_baseline_mark_policy_block` stamped `series_reset_at` with second-only precision; two calls landing in the same wall-clock second (routine on a fast machine or a GitHub Actions runner) produced an identical timestamp, spuriously failing `test-aid-gate-runtime-baseline.bats`'s AC3 regression ("command-template fingerprint change resets the series"). Added millisecond precision. Pre-existing flake, confirmed present on the CI run immediately prior to this fix; verified clean across 4 repeated local runs after the fix.

## [2.57.0] — 2026-07-12

### Added
- **Targeted Test Selector (P061 EPIC 3/6)** — `aid-select-tests.sh` maps changed paths to their corresponding test file(s) via a fixed Initial mapping and runs the union of them for real (not just a suggested command), replacing "run everything always" with deterministic, targeted coverage ahead of any self-host gate weakening (EPIC 4). Unknown production paths fail loud with a specific reason string (D-selector-1) rather than a silent skip. Registered as the `targeted_tests` gate definition in `execution.yaml` — defined only, not yet activated in any self-host `gate_profiles` (activation is EPIC 4, D1/D3).

### Fixed
- **`aid-select-tests.sh` CLI parser** — `--base`/`--paths-file`/`--evidence-file` now validate that a value actually follows the flag, returning the documented `exit 10` input-validation error instead of crashing with an unbound-variable error under `set -u` (e.g. `aid-select-tests.sh --base` with no argument).
- **Pre-commit commit-scope guard, main-fallback governance** — replaced an implicit, non-deterministic scan of every historical evidence directory with a single, explicit, FSM-managed active-run pointer. The old scan let a merged EPIC from weeks earlier (found: E-052-1_1) silently continue restricting every commit on `main` to its own stale version whitelist, with the specific historical EPIC selected depending on filesystem traversal order. `aid-fsm.sh`'s `cmd_init` now writes `.aid-o/work/active-run-pointer.json` on every run start — a single slot, always overwritten by the next run's init, self-expiring by construction. `defaults/hooks/pre-commit`'s main-fallback checks (the EXECUTE/GATES rogue-commit block and the DONE/release version whitelist) now read only this pointer, re-reading the pointed-to run's live state on every commit, and fail open on any invalid pointer (missing, malformed, or referencing a state file that no longer exists). The exact-branch-match path (a run governing its own task/epic branch) is unaffected — branch names are unique by construction and were never the buggy part. Consumer projects pick up the fixed hook on their next `/aid-init` refresh.

## [2.56.0] — 2026-07-12

P063 "Gate Runtime Baselines" (4 steps): AID runs gates against static,
human-guessed `timeout_seconds` values that never update as reality drifts.
This EPIC gives gates a real, self-updating runtime history — a percentile
library, live recording, a repeated-timeout enforcement hook, and a CLI to
read it back.

### Added
- **Gate runtime baseline library (`scripts/lib/aid-gate-runtime-baseline.sh`)** — records each gate run's duration/exit-code/timeout as a FIFO-windowed sample series (max 20, keyed by `gate_name`, reset on command-template fingerprint change), computes p50/p90/p95/max via nearest-rank percentiles over non-censored (non-timeout) samples only, and derives `timeout_recommended_seconds`/`run_mode_recommended` (background above a 10-minute p95) once enough real samples exist — atomic flock+tmpfile+validate writes, fail-open on any yq/jq error so a metrics write never blocks the real gate result.
- **`aid-run-gates.sh` integration + lazy gitignore backfill** — every gate run now feeds `gate_baseline_update`, and a one-time-per-clone `.git/info/exclude` backfill (`scripts/lib/aid-gitignore-backfill.sh`) keeps `.aid-o/metrics/` out of version control for existing projects that initialized before this EPIC (new projects already get it via shipped `defaults/.gitignore`).
- **Repeated-timeout policy block (`gate_timeout_policy_block`)** — `gate_baseline_policy_check` flags a gate whose last 3 recorded samples were ALL timeouts at/above its currently-configured `timeout_seconds`; a new `aid-fsm.sh` GATES:EXECUTE precondition refuses to keep retrying that gate (`retryable:false` + `operator_action`), closing the gap where that verdict was previously only a report field nobody read (AID-v3-principles.md §1 — Detector without Enforcement is Decoration).
- **`aid-gate-runtime-report.sh` CLI** — `[--project-root <path>] [gate_name]` reads Step 1's library directly (never re-deriving its percentile/formatting logic) to print one gate's p95/timeout/run-mode summary plus a data-sufficiency note, or every gate with recorded data when no gate name is given; project-root resolution follows the same resolve-then-`cd` idiom as `aid-plan-close-check.sh`.
- **`gate_runtime_baseline_advisory` enforcement-registry row** — documents the CLI as an advisory (non-blocking, non-FSM) reporting surface, distinct from Step 3's blocking `gate_timeout_policy_block` row.
- **`scripts/tests/verify-version-files.sh`** — dedicated checker for this project's 8-canonical-version-file release convention: asserts all 8 locations agree on one version, that it differs from the pre-release baseline, and that both `CHANGELOG.md` files mention it.

## [2.55.0] — 2026-07-11

P061 EPIC 1/6 (gate profile substrát + plan-gate floor): gates-enum unlock, `aid-run-gates.sh
--profile`, `aid-fsm.sh` plan-gate floor (`plan_gate_profile_excluded`), generic `gate_profiles`
substrate for new/existing projects, plus a mid-flight test-cost hotfix.

### Added
- **`--profile <name>` flag (`aid-run-gates.sh`)** — activates a named profile (`gate_profiles.<name>.include[]` from `execution.yaml`); gates outside it get `profile_excluded` (don't run, don't fail `overall`). New report fields: `profile`/`profile_source`/`profile_reason`/`excluded_gates`. Omitting `--profile` preserves prior behavior exactly.
- **Plan-gate floor (`aid-fsm.sh` GATES:DONE)** — cross-references `plan.json.gates[]` against `gates_report.json.excluded_gates[]`; any overlap blocks the transition with `plan_gate_profile_excluded` (never a silent skip). Malformed or wrong-shaped `plan.json.gates` (object instead of array) also fails loud (`plan_json_malformed`).
- **Gates-enum unlock (`plan.schema.json` + `aid-epic-to-json.sh`)** — `plan.json.gates[]` can now carry any gate name (was hardcoded to a 4-value enum); a previously dead validation no-op (`select(. == .)`, always true) now genuinely rejects malformed gate names.
- **Generic `gate_profiles` substrate for new projects (`/aid-init`)** — `compose_execution_yaml` emits a `gate_profile_defaults`/`gate_profiles` block per detected stack, using only that stack's own gate names, never self-host names (D3 consumer isolation).
- **Non-destructive existing-project upgrade (D9)** — `/aid-init` on a project with its own `.aid-o/config/execution.yaml` detects missing profile keys, reports the proposed block, and appends it only after explicit PM confirmation; pure-append implementation makes byte-preservation of hand-edited gate commands structural.
- **Release-policy surface-rule bootstrap check** — `scripts/tests/release-policy-surface-check.sh` (+ `test-release-policy-surface-check.bats`, 7 scenarios) gives P061's Bootstrap Fast Lane a small, explicit, testable rule for when the ~4-5 min `test-release-policy.bats` integration suite is required at step-level targeted testing (only when the diff touches release-policy surface) versus skippable for unrelated steps. Fail-safe default (no paths given) runs the suite. Does NOT change the EPIC-boundary/release-boundary requirement — `bats_all` still runs unconditionally there per D8.

### Fixed
- **`test-release-policy.bats` test-cost blocker** — the suite's 78 tests each ran the real `aid-evidence-verify.sh --at-head` subprocess (~9s/call against a real fixture), pushing the file past 5 minutes and blocking `bats_all` (and by extension this EPIC's own GATES phase) within its configured timeout. Added a double-gated test-only stub seam (`AID_TEST_MODE=1` AND `AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB=pass|fail|unverifiable`) to `aid-release-policy.sh`'s `run_verification_input()` so branch/logic tests can skip the subprocess; 4 tests (healthy real-pass, dirty-tree real-fail, stale-HEAD real-fail ×2) explicitly `unset` the stub and keep exercising the genuine subprocess end-to-end. Production/default behavior (both env vars unset) is unchanged — the real subprocess call is untouched. Suite time: ~18s/test (timing out past 300s+ overall, unreliable) → 4.6s/test for stubbed tests, ~4m50s reliable total for the full 78-test file.
- **`bats_all` gate timeout** — `.aid-o/config/execution.yaml`'s `bats_all` gate timeout raised from 1200s to 2400s to give the full suite (441 tests across ~30 files) realistic headroom; self-host config only, not shipped to consumer projects (D3).

## [2.54.0] — 2026-07-10

### Added
- **Gate-count integrity guard** — `aid-run-gates.sh` asserts gates-defined equals gates-processed before emitting `overall`, forcing `overall=fail` plus a nonzero exit on any mismatch so a lost or skipped gate can no longer silently pass, with the FSM GATES:DONE precondition loud-failing when jq is missing.
- **Undefined-gate reconciliation** — each `plan.json` gate is reconciled against `execution.yaml`, a declared-but-undefined gate emits a `result: fail / reason: undefined_gate` row that prevents `overall: pass`, and the FSM EXECUTE:GATES precondition requires a `plan_gates_reconciled` marker before advancing.
- **CP2 step-range prefilter** — the prefilter derives its diff range from the step boundary instead of `HEAD~1..HEAD`, hard-exiting on an undetermined range with a `CP2_RANGE_POLICY=observe` seam that downgrades to a `cp2_range_fallback` event.
- **CP3 head-freshness check** — GATES:DONE and done-advance compare the verifier-reviewed head against current HEAD and block on stale evidence by default, with a `CP3_FRESHNESS_POLICY=observe` seam and an explicit D4 exception event for allowed-scope gate-fix or test-only commits past the reviewed head.
- **Runtime cache preflight (IMP-179 partial)** — `scripts/lib/aid-cache-preflight.sh` compares the plugin version and a content-hash of `scripts/` against the running plugin cache, hard-stopping on the dogfood repo and recording the controller version into fsm-state/timeline on consumer repos, closing the scripts/version half of the subagent-cache-staleness gap.
- **Commit-path guard** — a `defaults/hooks/pre-commit` hook restricts orchestrated commits to the per-step `allowed_paths` and refuses when HEAD diverges from the fsm-state branch, with an FSM companion emitting `commit_scope_violation` telemetry and a `commit_guard_disclosure` event.
- **Queue dependency revalidation** — each `depends_on` dependency is re-checked via `git merge-base --is-ancestor` at EPIC start, failing loud on an unparseable queue or an unresolved dependency and otherwise recording advisory telemetry.
- **C4 head-match policy hook** — the release aggregator makes `head_match` consequential, staying observe (`c4_head_match_divergence` / `c4_head_match_unknown` events) until an E10 promotion of `head_match_policy` to blocking.
- **E11 enablement map** — `docs/plans/2026-06-29-BACKLOG.md` records which legacy CP mechanisms each P060 step makes removable or cutover-ready, plus the mandatory K4×K8 binding tying `head_match_policy: blocking` promotion to removal of the CP3 freshness branch.

### Changed
- **Enforcement registry** — 8 P060 rows added (271 to 279 total), covering the new gate-integrity, prefilter, freshness, cache-preflight, commit-path, queue, and C4 head-match mechanisms with their observe/blocking posture and OBS-ledger closures.

### Fixed
- **False-green and stale-evidence pipeline gaps** — closes the OBS-ledger family where a lost gate, an undefined gate, a wrong prefilter range, stale reviewer evidence, a stale plugin cache, an out-of-scope or wrong-branch commit, and an unrevalidated queue dependency could each pass the pipeline undetected.

## [2.53.0] — 2026-07-09

### Added
- **C4 Release Policy aggregator (E9, P059)** — `scripts/aid-release-policy.sh` deterministically aggregates the evidence pack (REQUIRED / profile-gated / advisory / conditional / optional inputs) into a protocol-v2 `release-decision.json`, deriving `release_ready` + `blockers[]` with no LLM, and fails closed on empty/unparseable inputs, a followed `plan_ref` hop, and an `--at-head` evidence mismatch (classified `fail`, never `unverifiable`).
- **PM decision brief generator** — `scripts/aid-pm-brief.sh` projects `release-decision.json` (and only that file) into a protocol-v2 `pm-decision-brief.json` plus a human `pm-summary.md`, echoing every review signal in full so an auto-merge is never silent, then patches `pm_brief_status` back into the decision.
- **FSM dual-run release hook** — `aid-fsm.sh done-advance review→release` runs C4 alongside the legacy checks in observe mode, emitting a `release_policy_dual_run` timeline event with an 8-value never-empty `divergence_class` taxonomy, a `release_policy_preempted` event when a hard-exit legacy gate fires first, a crash-safe fallback, force→waiver artifact writing, and an opt-in `RELEASE_DECISION_POLICY: enforcement: blocking` branch.
- **Protocol-v2 release artifacts** — `release_decision`, `pm_decision_brief`, and `waiver` schemas plus `aid-protocol-validate.sh` D11 field checks and a new `waiver` artifact type.
- **D11 release-decision state model** — `release-decision.json` now carries `pm_brief_required`/`pm_brief_status`, `evidence_verified_at_head`/`evidence_verification_status`, the Reporter/Simplifier CONDITIONAL 5-enum status, `merge_mode`, `delivered_summary_ref`, and `summary_for_pm`, all echoed 1:1 into the PM brief.
- **`scripts/lib/aid-review-signals.sh` shared substrate** — the Reporter/Simplifier enable-toggle + `_test_evidence` validation extracted so the C4 aggregator and the FSM compliance evaluators read identical signals.
- **Invalidation-map live caller (IMP-177 C3 activation)** — the observe-only `invalidation-map.json` producer is now wired into the live gate-fixer dispatch flow (previously test-only), closing the C3-activation half of IMP-177.
- **`docs/extending-aid.md` C4 + D11 contributor reference** — documents the release-policy aggregator, the dual-run hook, the D11 state model, and an explicit "What E9 core Does NOT Deliver" scope-honesty section (no structural merge-on-brief gate, observe-not-blocking default, IMP-179 subagent-cache staleness, IMP-191 fingerprint collision — all deferred).

### Changed
- **Reporter/Simplifier release gating is CONDITIONAL** — release readiness treats them as plan-boundary roles: `not_applicable` off the boundary, `disabled` when toggled off, `missing`→blocking on the boundary when enabled, `pass` when the artifact is present and valid.
- **`test-release-policy.bats` full Doc-1 §13.2 disposition** — the release-policy suite maps all 17 review-instruction fixtures plus 10 D11 negative fixtures (rows 18-27, names carrying `dual`/`waiver`/`d11`), with the 5 N/A/SKIP-REF rows documented in the file header.

## [2.52.0] — 2026-07-08

### Added
- **C3 Independent Audit (E8, P057)** — `agents/auditor.md` converts to dual-mode, selected by `audit_trigger.mode`: risk-gated, distrust-based `c3` (PASS is never the default) alongside the original trust-based `legacy_health` A-J audit kept as compat. C3 emits protocol-v2 `audit-report.json`/`audit-input-manifest.json` (type-named `.audit_report` key, findings top-level, `blocking_findings` boolean, `provider`/`model`/`process_id` echoed verbatim from the harness — never self-reported).
- **`aid-audit-independence.sh`** — detects the actually-achieved audit independence level (`context_only`/`cross_model`/`cross_provider`) against the level required by `c3-audit-policy.yaml` for the run's risk profile; detection-only, never dispatches a real `codex exec` audit; unconfirmable signals degrade to `unverifiable`, never a silent pass.
- **`c3-audit-policy.yaml`** — authoritative risk-profile → required-independence-level policy; only `high` (needs `cross_model`) and `unverifiable` (needs `cross_provider`) carry `c3_required: true`.
- **`aid-fsm.sh` C3 done-advance hook** — fail-closed release block on `blocking_findings`, unverifiable independence, missing/malformed provenance, or a stale audit `head_sha`; risk-gated to the `high`/`unverifiable` profiles only, with no `// false` fallback anywhere in the check.
- **Curator serial after C3 + content-ref sequencing guard** — `skills/pipeline.md` dispatches Auditor (C3) then Curator serially (was parallel); Curator dual-emits `curator-report.json` with `.curator.audit_report_ref` (sha256 of the actually-consumed `audit-report.json`), and a new `aid-fsm.sh` guard blocks unless that hash matches the current report — proving real consumption order, not just a shared commit. `recommended_disposition` merge-authority is untouched (deferred to E9).
- **`invalidation-map.json` observe-only producer** — `scripts/lib/aid-invalidation-map.sh` derives `affected_c1_checks[]` (deterministic subset, read from `delivery-gate.yaml` globs) and `affected_c2_modes[]` (conservative — any C2-touching change affects all modes) from an applied fix's changed paths, emitting the artifact plus a timeline event; registered as `invalidation_map_observe`; never triggers a re-run itself.
- **Behavioral red-green test suites** — `scripts/tests/bats/test-c3-audit.bats` (High→blocking, unavailable→unverifiable, no-provenance→fail, curator-before-audit→fail, each with a positive and negative control via subprocess `aid-fsm.sh`) and `scripts/tests/bats/test-invalidation-map.bats` (real producer execution against fixtures).
- **`docs/extending-aid.md` C3 Independent Audit (E8) section** — documents the full C3 pipeline plus an explicit "What E8 Does NOT Deliver" scope-honesty subsection (no real Codex dispatch, no auto re-run, no C4 consumption, merge-authority untouched, no cryptographic hash-equality binding — see `docs/plans/2026-06-29-BACKLOG.md` § "E8 Deferred").

## [2.51.0] — 2026-07-05

### Added
- **Per-step scoping HTML block (D2)** — `aid-plan-to-epic.sh` emits a `<!-- step-N: files=[...]; ac=[...] -->` block per step so `aid-epic-to-json.sh` scopes `outputs`/`allowed_paths`/`acceptance_criteria` per step instead of broadcasting flattened EPIC-level sections to every step, with legacy no-block EPICs keeping today's exact broadcast behavior.
- **Contract Validation Gate (D5)** — new blocking `scripts/gates/aid-contract-validate.sh` checks generated `plan.json` for per-step-scoping broadcast, AC pipe-split fragments, and prose-shaped `allowed_paths`, wired as the one blocking exception inside the observe-only C0 block of `aid-auto-pipeline.sh` and persisting `contract-validate.json` before aborting so a later phase's failure never hides behind an earlier phase's stale pass; registered as `contract_validation_gate` in `enforcement-registry.yaml`.
- **C0 Check 6 (`contract_validation`)** — `aid-c0-contract.sh`'s `review` subcommand reads (never re-runs) the persisted D5 gate result into the evidence pack.
- **`docs/extending-aid.md` section** — documents the D2 per-step scoping block and the D5 contract validation gate for contributors.

### Fixed
- **`aid-plan-diff.sh` false-green on `## Success Criteria` plans** — the AC-extraction awk used a range pattern whose terminator matched a `## Success Criteria` heading as an end-of-range marker, collapsing the whole section to `ac_count: 0` and silently skipping AC enforcement for every plan using that heading instead of `## Acceptance Criteria`; replaced with a flag-based block that recognizes both headings.
- **`ac_no_fragments` false-positive** — the D5 gate's quote-parity backstop no longer misfires on plural possessives (`users' permissions`) or on quotes inside balanced backtick spans (CP2 finding).
- **Self-consistency regen bugs** — per-step scoping line parsing now anchors on the last occurrence of the `ac=` delimiter instead of the first, and per-step Files-bullet extraction is top-level-only, fixing corruption when a plan's own text describes the block syntax it is itself written in.

### Changed
- **Minor version bump rationale** — this release is a `bug-fix`-type EPIC per its source plan, but bumps MINOR (2.50.1 → 2.51.0) rather than PATCH because it introduces a new blocking gate capability (Contract Validation Gate, D5), not just a fix.

## [2.50.1] — 2026-07-01

### Added
- **E7B existing_ui wiring** — Full pipeline support for modifying existing UI: `visual-companion/SKILL.md` phase-aware baseline capture, `role-cards.md` ui_change_contract constraint, `agent-protocol.md` branched reading order, `pipeline.md` envelope injection + mechanical verdict via `ui-compare.mjs`
- **ui_change_contract envelope transport** — `plan-writing.md` positive assertion rule; `aid-plan-to-epic.sh` encodes per-step contracts into EPIC HTML comments; `aid-epic-to-json.sh` decodes into `steps[].ui_change_contract` (T4 round-trip test proves chain)
- **FSM existing_ui guard** — `aid-fsm.sh cmd_increment_step` blocks with `frontend_visual_fidelity_block` when `ui_change_mode: existing_ui` and `steps/{id}/ui/verdict.json` is absent or result != pass; step-local only (D6 — delivery-gate/C4 aggregation deferred to E9)
- **ui_change_mode + ui_change_contract step fields** — `plan.schema.json` extended; `companion` added to `visual_assets.source_type` enum
- **ui-fidelity.schema.json result field** — `result: pass|fail|unverifiable` and `result_detail` added to verdict sub-document
- **frontend-user-outcome-contract.schema.json** — C2 lens schema for `frontend_user_outcome` (FC-35): persona, user_questions (1-5), actions, data_oracle, significant_states, success
- **`/aid-do` existing_ui redirect** — detects `--ui` flag or `existing_ui` in description, refuses with redirect to `/aid-run` (contract enforcement required); `--no-ui-check` bypass documented
- **test-fsm-ui-fidelity.sh** — 3 runtime tests: pass/fail/absent verdict; all 3 confirm guard fires (P026 pattern avoided)
- **test-ui-fidelity-e2e.sh** — 4 scenarios (happy/un-applied/collateral/capture-absent) + Playwright skip guard (exit 0 with message when browsers absent)

### Changed
- **enforcement-registry.yaml** — Added `frontend_visual_fidelity_block` row (entry 259); instruction now references `pipeline.md §4`
- **test-epic-to-json-regression.sh** — T4 added: full round-trip for existing_ui envelope
- **plan.schema.json golden** — `ui_change_mode: null, ui_change_contract: null` added to step objects

## [2.49.0] — 2026-06-30

### Added
- **E7-CAL Calibration Mechanism** — `ui-calibration-run.sh` runs 5 fixture cases (A/B/C hermetic + D-desktop/D-mobile real ScreenG via Playwright `page.route` mocks), persists 8 artifacts per case (baseline/regressed/rerun PNG + computed JSON + verdicts), writes `ui-calibration-record.json` with artifact map and D `real_surface` assertions proving live URL capture.
- **`ui-calibration-verify.sh`** — Standalone evidence verifier: checks PNG validity, JSON validity, verdict cross-check against record, D cases real_surface assertions (no `hermetic://` URL, no `DETERMINISTIC` text, correct viewport), rejects structurally incomplete records.
- **`screeng-capture.mjs`** — Playwright script capturing ScreenG in 3 states (regressed → baseline → rerun) in a single browser session using `page.route` API mocks.
- **`test-ui-calibration-verify.bats`** — 15 BATS tests preventing false-green calibration (missing PNG, hermetic URL, DETERMINISTIC text, wrong viewport, verdict mismatch, invalid JSON/PNG).
- **`ui-calibration-record.schema.json` v1.1.0** — `artifacts` object required per case; `real_surface` optional object for D cases.
- **`ui_calibration_result` gate** — Calls `ui-calibration-verify.sh`; auto-passes when no calibration record present (non-E7-CAL EPICs unaffected).
- **`ui_calibration_signoff` gate** — PM manual sign-off gate; auto-passes when no calibration record present.

### Fixed
- **`ui-compare.mjs` dimension mismatch reason** — Both `checkLockedCrops` and `checkOutsideMask` now emit `image_dimension_mismatch` (was `locked_violation` and `outside_mask_diff` respectively).

## [2.47.0] — 2026-06-30

### Added
- **E7A UI Fidelity Foundation** — Standalone `lib/ui-fidelity/` package with Playwright capture, pixelmatch comparison, typed contract schema, envelope validator, 5 calibration fixture sets (A/B/C hermetic + D-desktop/D-mobile hermetic), CI workflow, and `ui-contract-check.sh` gate script.

## [2.46.0] — 2026-06-30

### Added
- **DG-15 Route Resolve** — Literal link vs declared route-files probe (react-router/express); opt-in via delivery-map.yaml routes section; config_missing when framework unsupported or map absent
- **DG-17 Independent Oracle No-Drop** — Analytics output cardinality vs declared baseline; requires analytics_output_file + expected_cardinality; missing file → config_missing, not fake pass
- **DG-18 Acceptance Provenance** — FSM step-verify evidence adapter; surfaces acceptance history into delivery-gate.json; never emits fail (provenance-only)
- **delivery-map.schema.json** — JSON Schema for delivery-map.yaml (meta/routes/oracle_baselines, all optional)
- **aid-delivery-map.sh** — Accessor library for delivery-map.yaml with pinned exit-code contract (null → exit 2)
- **map_section_globs + has_acceptance_evidence** — Two new dispatcher condition types in aid-delivery-gate.sh

### Changed
- **enforcement-registry.yaml** — Added DG-15/17/18 rows (surface: delivery-gate, observe, planned E10); totals.enforcements corrected to 258

## [2.44.1] — 2026-06-29

### Fixed
- **`aid-acceptance-evidence.sh` + `aid-consumption-proof.sh` protocol-v2 envelopes** — both scripts now emit full protocol-v2 envelope (`schema_version`, `identity`, `subject`, `revision`, `status`, `verdict`, `provenance`); `revision.head_sha` carries the full 40-char git SHA (was short SHA, broke `--current-head` validation)
- **`aid-acceptance-evidence.sh` step naming** — verifier evidence files looked up as `step-1.md` (1-indexed, no zero-padding) instead of `step-00.md`; `ac_id` suffix changed from `_00` to `_1`
- **`aid-consumption-proof.sh` false-verified** — Strategy 2 (filename pattern fallback: `*contract*`/`*binding*`) removed; only Strategy 1 (grep for binding_id) is valid
- **`consumption_proof` protocol-v2 type registration** — added to `aid-protocol-validate.sh` + fixtures (`valid.json`, `invalid-missing-payload.json`)
- **Enforcement registry planned rows** — `semantic_wiring_would_block`, `c2_acceptance_deviation`, `c2_consumption_unresolvable` now carry `status: planned`, `deadline/deferred_until/promotion_phase: E10`
- **FC-24..28 fingerprints** — `fc{NN}neg` contained non-hex chars; fixed to `fc{NN}000...` (64 valid hex chars)
- **Evidence pack regenerated at HEAD** — `delivery-gate.json`, `acceptance-evidence.json`, `consumption-proof.json` regenerated; all pass `aid-protocol-validate --current-head --check-fingerprint`

### Added
- **E5 wiring-gate bats test** — `E5 wiring-gate observe: Critical finding logged but increment proceeds`; seeds Critical finding in `semantic-review-wiring.json`, asserts exit 0 + `semantic_wiring_would_block` in `timeline.jsonl`
- **T8 fingerprint schema validation** — `test-semantic-review.sh` T8 verifies `sha256:[0-9a-f]{64}` format per FC fixture
- **T9 mutation-survives + low-profile-no-local** — merge count dedup + final-only dispatch-mode tests
- **T10 `--current-head` regression guard** — both `aid-acceptance-evidence.sh` and `aid-consumption-proof.sh` output verified against `aid-protocol-validate --current-head` in test harness

## [2.44.0] — 2026-06-29

### Added
- **C2 Semantic Review Engine (observe)** — 4-mode dual-emit engine (local/wiring/behavior/final) producing auditable `semantic-review-{mode}.json` alongside the existing `.md` gate (D1 unchanged); 12-lens catalog from failure-mode-control-matrix FC-09, FC-24..28, FC-30..32, FC-35; no-mega-prompt rule (D2); observe-only (E5), blocking deferred to E10
- **Wiring-gate observe** — `cmd_increment_step` logs `semantic_wiring_would_block` on unresolved Critical/High wiring findings; `SEMANTIC_REVIEW_POLICY=blocking` enables E10 blocking path without code change
- **`aid-finding-merge.sh`** — lossless fingerprint-keyed merge: severity=max, detail=union sorted, conflicts in `merge_meta`; deterministic output
- **`aid-acceptance-evidence.sh`** — reconstructs `acceptance-evidence.json` from plan.json AC + LLM coverage signals (`## AC Coverage` block); ac_id=sha256[:12]_step_idx; D3: bash aggregates, LLM determines coverage
- **`aid-consumption-proof.sh`** — verifies contract-manifest.json bindings against evidence_dir (grep+filename); fail-safe: missing manifest → `unresolvable` + exit 0
- **`review-profile-check.sh` E5** — `completed_lenses` read from `lenses_run[]` union across `semantic-review-{mode}.json`; E3 backward-compat: no C2 files → same `COMPLETED_LENSES=""` behavior
- **FC-24..28 negative fixtures** — 5 runnable JSON fixtures for transaction_boundary, field_lineage, negative_case, operation_order_resource_bound, requirement_test_drift failure modes
- **`test-semantic-review.sh`** — 8-test harness covering merge, acceptance-evidence, consumption-proof, review-profile-check (E5+E3 backward-compat), fixture validity
- **Enforcement registry** — 9 new C2 entries covering wiring-gate, dual-emit, lens catalog, acceptance-evidence, consumption-proof, completed_lenses, requirement-drift, finding-merge, semantic-review-policy
- **`docs/extending-aid.md`** — C2 extension guide: how to add lenses, dual-emit protocol, fingerprint format, policy promotion path

## [2.43.0] — 2026-06-28

### Added
- **C0 Plan Contract Gate** — observe-only gate layer running in `aid-auto-pipeline.sh` after plan-graph extraction, producing `plan-graph.json`, `contract-manifest.json`, and `plan-review.json` with 5 semantic lenses (observe, E10 promotion target)
- **Shared Kahn topo-sort lib** — `scripts/lib/aid-plan-graph.sh` with `build_plan_graph` function and deterministic `topological_order` output; `aid-epic-to-json.sh` refactored to use it
- **C0 QA harness** — `test-c0-contract.sh` with 66 assertions across 7 fixture sets (clean, cycle, dup-id, p045-style, per-lens, blocking-mode, clean-low-risk)

## [2.42.1] — 2026-06-28

### Added
- **E3 Adaptive Review Profile Detector** — deterministic, LLM-free resolver (`aid-prefilter.sh profile`) computes surface→lens matrix from plan-time + candidate-time git diff union; emits `review-profile.json` with `required_lenses`, `profile_hash`, `risk_profile`, and IR cadence; FSM observe hook logs `missing_lenses` telemetry without blocking (promotion to blocking in E10); 6 surfaces, 5 risk profiles, 13-scenario test harness.

## [2.41.2] — 2026-06-28

### Fixed
- **CI: dg07/dg12 bash-test failures** — delivery-gate fixture `.aid-o/` trees were gitignored by `**/.aid-o/`; added exception in `.gitignore` matching the existing `mini/` pattern; fixture files (`fsm-state.yaml`, `execution.yaml`) are now tracked and available in CI.
- **CI: dg12 unverifiable on GitHub Actions** — `yq` was not installed in the `bash-tests` job; `dg12-authority.sh` fell through to exit=2 instead of parsing the authority YAML and returning exit=1; added `yq` install step.
- **CI: vitest `@aid/contract` resolution failure** — `dist/` is gitignored so `@aid/contract/dist/index.js` was absent in CI; added `npm run build -w @aid/contract` step before `npm test` in the vitest job.

## [2.41.1] — 2026-06-28

### Changed
- **False-Green Guardrails in Verify Commands + Contracts** — `aid-verify-implementation` and `aid-verify-plan` now enforce four additional review requirements: (1) mandatory "Independent runtime path check" output section — DONE review cannot be based on "tests pass" alone; (2) every AC using "always"/"all"/"each"/"never" must define its exact universe or the plan/AC is rejected as not objectively verifiable; (3) eval/evidence artifacts must name which pipeline slice they actually exercise; (4) every new integration function requires at least one caller-flow test, not just a unit test of the pure helper. Same four guardrails added to `review-checkpoint-contracts.md` so they apply to in-pipeline CP2–CP5 reviews, not only the manual verify commands.

## [2.41.0] — 2026-06-27

### Added
- **Evidence Pack Verifier CLI (E2.5)** — `aid-evidence-verify.sh <epic> <run> [--out <path>] [--at-head]` deterministically verifies a completed run's evidence pack: git cleanliness, artifact freshness (as-of-pack, ancestor-of-HEAD; strict `--at-head` mode for live DONE-review), protocol-v2 validation + finding fingerprints per artifact, TTL/registry guard, and observe-vs-blocking interpretation consistency; emits `verification-report.json` (protocol-v2, self-validated) + human summary; standalone CLI outside FSM.
- **`verification_report` Protocol-v2 Type** — 15th artifact type in `aid-protocol-v2.schema.json` enum + `VALID_ARTIFACT_TYPES` validator array + `TYPE_PAYLOAD_MAP` entry + `verification-report.schema.json` type schema.
- **Evidence Verifier QA** — 11 purpose-built fixtures (clean-pack, ancestor-pack, divergent-stale, inconsistent-head, invalid-artifact, enum-garbage, mixed-legacy, nondeterministic-fingerprint, dirty-git, ttl-violation, enforcement-absent) + `test-evidence-verify.sh` harness + golden sample; every check has positive and negative coverage.
- **Enforcement Registry** — 7 verifier checks registered in `defaults/enforcement-registry.yaml` (`surface: internal-guard`, `status: planned`, `deadline: 2027-06-01`); FSM wiring deferred to E9.

## [2.40.0] — 2026-06-26

### Added
- **C1 Delivery Engine** — `aid-delivery-gate.sh` + 12 DG check plugins (DG-01..12) producing protocol-v2 `delivery-gate.json`; observe mode (E2): writes `delivery_gate_would_block` telemetry, never blocks FSM transitions; blocking promotion deferred to E10.
- **Delivery Gate Policy** — `defaults/policies/delivery-gate.yaml` with profile detection (plugin-bash, npm-workspaces, unverifiable) and per-profile check commands; `skip_reason_allowlist` enforces closed vocabulary.
- **Profile Resolver** — `scripts/lib/aid-delivery-profile.sh`: `resolve_profile` + `select_commands` for deterministic argv-array dispatch (no eval).
- **DG-07 FSM Hook** — observe-mode hook in `cmd_done_advance` writes `delivery_gate_would_block` event to timeline; blocking branch is live code tested by `test-fsm-dg07-observe.bats`.
- **Full Delivery Gate Schema** — `defaults/schemas/delivery-gate.schema.json` expanded to full protocol-v2 payload covering `delivery_gate.{phase,profile,freshness,delivery_ready,checks[],summary}`.
- **QA Fixtures + Harness** — 10 per-DG fail/unverifiable fixtures, golden sample, 44-assertion `test-delivery-gate.sh`; every DG-01..12 check has at least one fixture proving it is not an untested decoration.
- **Gate Coverage Fields** — `aid-run-gates.sh` now emits `covered_paths`, `changed_paths_covered`, and `relevance` (direct|partial|none|unknown) in `gates_report.json`.
- **Enforcement Registry** — DG-07 FSM hook + DG-01/04/07/12 registered in `defaults/enforcement-registry.yaml` as observe-mode (status: planned, deadline: E10).

## [2.38.0] — 2026-06-23

### Added
- **`/aid-verify-plan` + `/aid-verify-implementation`** — two manual, PM-invoked commands that dispatch an independent fresh-context agent to adversarially review a plan before execution and an implementation after it claims DONE; each carries its full review protocol (false-green risks, producer-consumer contracts, runtime-not-statics, real-data oracle) and returns a severity-ranked verdict plus a Czech PM summary. Standalone tools outside the FSM (like `/aid-do`) — no `fsm-state.yaml`, no evidence dir, no pending-dispatches ledger.
- **AID Control System v2 protocol** — shared protocol v2 envelope (`aid-protocol-v2.schema.json`), 14 type-specific schemas, deterministic finding fingerprint helper (`aid-finding-fingerprint.sh`), and authoritative bash+jq validator (`aid-protocol-validate.sh`) with 11 blocking invariants (exit codes 2-13); schemas + validator + fixtures only — no runtime wiring (E2+).

### Fixed
- **Protocol v2 `control_protocol` enum** — validator now enforces enum membership (exit 8) in addition to field presence (exit 3); previously any non-`legacy` value (e.g. `"banana"`) passed as exit 0; fixture `invalid-bad-control-protocol.json` and consistency check added.

## [2.37.0] — 2026-06-21

### Added
- **Per-step Acceptance Criteria pre-flight** — `aid-epic-to-json.sh` hard-fails a multi-step EPIC that carries fewer acceptance criteria than steps, so every step has a contract the CP chain can verify (root cause of the E-047-4_7 cockpit REOPEN); override deliberately with `AID_ALLOW_SPARSE_AC=1`.

### Fixed
- **Plan→EPIC acceptance-criteria + role extraction** — `aid-plan-to-epic.sh` now reads acceptance criteria written as plain `-` bullets under `**Acceptance Criteria**` (with or without a colon) and the `**AID Role**` header without a colon; previously it matched only the `**Acceptance Criteria:**` + `- [ ]` + `**AID Role:**` forms, silently dropping every criterion (empty EPIC AC section) and defaulting every step to the `backend` role.
- **Compliance `overall` is severity-aware** — `write_compliance_json` now derives `overall` from blocking failures only (advisory-severity failures are recorded in `failures[]` for visibility but no longer flip it to `fail`), matching the `cmd_done_advance` release gate; previously a single advisory check such as `branch_correct:false` on a PM-controlled shared feature branch produced `overall:fail` even though the FSM correctly released, a self-contradictory record. The provenance-unverifiable integrity signal stays blocking.

## [2.36.2] — 2026-06-19

### Fixed
- **`aid-plan.md` stale CP1 lens names** — CP1-deep section updated from `security/correctness/architectural` to `L1-behavior/L2-feasibility/L3-enforcement`; evidence file table updated with correct filenames and required-field column (producer→consumer drift fix).
- **`aid-cp1-gate.sh` stale header comment** — file header comment updated to match L1/L2/L3 filenames and content requirements.

### Added
- **P046 boundary manifest and delivery report committed** — `.aid-o/reports/P046-boundary.md` and `.aid-o/reports/P046-delivery.md` now tracked in git; `.gitignore` glob fix (`.aid-o/*`) makes this possible.

## [2.36.1] — 2026-06-19

### Fixed
- **CP1-deep empty-file bypass** — `aid-cp1-gate.sh` previously accepted empty evidence files (only checked `-f`); gate now requires non-empty files (`-s`) and the required field at line-start (`stop_rule_blockers:` in lens files, `verdict:` in adjudicator); empty or structurally incomplete files now fail the gate.
- **CP1-deep lens taxonomy mismatch** — lenses renamed from `security/correctness/architectural` to `L1-behavior/L2-feasibility/L3-enforcement` per plan P046 taxonomy; L3 (enforcement/CI/artifact-visibility) is the class that catches gitignored artifacts and non-executing tests.
- **`/aid-init` `.gitignore` guidance** — instruction corrected to replace `.aid-o/` with `.aid-o/*` before adding `!.aid-o/reports/`; git cannot un-ignore content inside an ignored directory — the glob form is required.

## [2.36.0] — 2026-06-19

### Added
- **Behavior-first review contracts** — `skills/review-checkpoint-contracts.md` defines per-checkpoint diff scope, high-risk pattern table (8 categories: auth, routes, validation, migrations, FSM, security sinks, payment, deps), and structural gate rules for CP2/CP3/CP4/CP5/CP6 and CP1-deep.
- **`behavior_trace` structural gate** — `aid-fsm.sh:fsm_check_verifier_output()` rejects verifier outputs where `behavior_trace_required: true` but `behavior_trace_count` is 0 or missing; gate is opt-in and fires only when the verifier explicitly sets the flag.
- **Additive verifier output fields** — `verifier-output-template.md` gains optional top-level fields (`checkpoint`, `focus`, `behavior_trace_count`, `behavior_trace_required`, `behavior_trace`) that extend the output without displacing existing `_generated_by`/`classification`/`verdict` greps.
- **`aid-prefilter.sh --checkpoint` flag** — caller can now pass `--checkpoint <cp2|cp3|cp4|cp6>` to get checkpoint-specific diff scope; CP2 defaults to `HEAD~1..HEAD`, CP3 reads `base_commit` from `fsm-state.yaml`.
- **CP1 risk-scaling** — `aid-plan.md` gains a CP1 Mode Selection section defining CP1-light (standard checklist) vs CP1-deep (three-lens: security/correctness/architectural, adjudicator, max two revisions, PM escalation on unresolved stop-rules).
- **`aid-cp1-gate.sh`** — EPIC generation gate that reads plan frontmatter (`id`, `risk`), scans body for eight high-risk pattern categories, and verifies four evidence files (`cp1-deep/` directory) when risk is high; includes path-traversal guard on plan ID.
- **Enforcement homes reference** — `docs/extending-aid.md` gains an Enforcement Homes Reference section documenting where each enforcement mechanism lives (plan-close, FSM precondition, behavior_trace gate, CP5 blocking_findings, CI floor).
- **Two new enforcement registry entries** — `cp1_critical_path_flow_trace` (type lm_judgment_advisory, surface cp1) and `behavior_trace_high_risk_gate` (type fsm_precondition, surface cp2/cp3/cp4); both carry `deadline: 2026-09-01`, `status: active`, `verdict: ALIGNED`.
- **6 bats tests for behavior_trace gate** — `bats/test-behavior-trace.bats` covers count=0+required=true→fail, count=3+required=true→pass, required=false→pass, field absent→pass, count missing→fail, count=1→pass.

### Fixed
- **`.gitignore` negation pattern** — replaced `.aid-o/` directory exclude with `.aid-o/*` glob so `!.aid-o/reports/` negation works; git cannot un-ignore content inside an ignored directory.
- **CP1 gate `risk: low` precedence** — high-risk body pattern match now always triggers CP1-deep regardless of `risk: low` frontmatter; `risk: low` previously overrode the pattern scan (wrong behavior).
- **Frontmatter parser state machine** — `aid-cp1-gate.sh` parser now uses open/close `---` state machine; stops reading at opening marker, reads to closing marker, rejects plans with unclosed frontmatter instead of silently reading body as frontmatter.
- **Rule #21 `REVISE_REQUIRED` advisory label** — `plan-writing.md` rule #21 REVISE_REQUIRED outcome labeled "(advisory — see 21c, PM can override)" to match enforcement type; test-plan-writing-rules.bats updated (removed dead `FIXTURES_DIR` variable).

## [2.35.0] — 2026-06-18

### Added
- **`plan-close` FSM command** — enforces all four required reports (curator, auditor, simplifier, delivery) before writing the `ca-review-complete` marker; raw `touch` is explicitly forbidden and `pipeline.md §7` directs implementers to this command instead.
- **Toggle-skip for disabled specialists** — `simplifier.enabled:false` / `reporter.enabled:false` in `execution.yaml` exempts the corresponding report from `plan-close`; each skip is audited to `audit-log.jsonl` with specialist name and rationale.
- **`simplifier_report_present` compliance measurement** — `compliance.json` now carries `simplifier_report_present: null/true/false` (advisory severity); anchored for future enforcement promotion.
- **Boundary manifest (committed, CI-readable)** — Reporter writes `.aid-o/reports/{plan_id}-boundary.md` after every completed plan; carries provenance for all four required reports and is readable by CI without accessing gitignored evidence directories.
- **CI floor check** — `defaults/ci/plan-boundary-required-check.yml` (GitHub Actions) verifies that committed boundary manifests are complete; exits 0 gracefully when no manifests are present.
- **`/aid-audit` CI check residual** — `/aid-audit` verifies whether the boundary CI check is installed and explicitly surfaces the residual when it is not.
- **`/aid-init` optional CI check installation** — fresh or upgraded workspaces are offered the option to copy `plan-boundary-required-check.yml` to `.github/workflows/`.
- **Force-override audit enrichment** — `init --force` pre-scans to identify the blocking plan/EPIC and passes `--blocking-epic` / `--blocking-plan` to `fsm_handle_force_override`, writing both to `timeline.jsonl` and `audit-log.jsonl`.
- **13 new bats assertions** — `test-plan-close.bats` (9 tests: missing reports, toggle-skip, audit entry) and `test-ci-floor.bats` (4 tests: no manifests, valid manifest, incomplete manifest, missing delivery).
- **`_aid_read_toggle()` helper** — yq-free toggle detection extracted into a shared function, eliminating duplicated grep chains in `cmd_plan_close` and `fsm_eval_simplifier_present`.

## [2.34.2] — 2026-06-18

### Fixed
- **`plan_diff` evidence truthfulness** — gate runner recorded `result: "pass"` for exit-2 graceful skips (no AC blocks / legacy plan), making `gates_report.json` claim verification happened when it did not; changed to `result: "skip"` so evidence accurately reflects that the gate skipped rather than passed.
- **`review_result` instruction drift** — `role-cards.md` and `gate-fixer.md` still referenced the old nested `review_result.findings[]` contract after the Step 2 canonical-output migration; updated to top-level `findings:[]` per `agents/verifier.md`.

## [2.34.1] — 2026-06-18

### Fixed
- **`yaml_field()` quoted-empty bypass** — `_generated_by: ""` and `_generated_by: ''` returned a non-empty string (the literal quote characters), allowing fabricated empty fields to pass `[[ -z ]]` guards; fixed by stripping surrounding YAML quotes after whitespace trimming so quoted-empty collapses to empty and fails correctly.
- **Verdict whitelist missing** — only `pending` and empty were rejected from verifier output; any other non-standard scalar (e.g. `banana`) passed as a valid completed verdict; fixed by explicit `case` whitelist that accepts only `pass|fail`.
- **`blocking_findings` fail-closed on non-false values** — only exact scalar `true` was blocked; `maybe`, `"true"` (quoted), comment text, and any other non-empty value passed silently as clean; fixed to accept ONLY scalar `false` (after quote-stripping), treating everything else as blocking.
- **`cp4_curator_validation` registry anchor** — source line was `scripts/aid-fsm.sh:283`, actual function start is `:292`; corrected.
- **Enforcement registry seed header** — seed file still claimed "single source of truth / NOT yet promoted"; updated to "SUPERSEDED by E-046-1_3 Step 5" to match reality after promotion.

## [2.34.0] — 2026-06-18

### Added
- **Enforcement registry promoted to `defaults/`** — `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` is now git-tracked and shipped with the plugin; previously it lived only in a gitignored seed file, making it invisible to consumers and untestable in CI.
- **TTL guard for planned enforcement rows** — `scripts/aid-registry-ttl-guard.sh` exits non-zero when a `status: planned` registry row is past its `deadline` without a valid future `deferred_until` date; enforces the "Detector without Enforcement is Decoration" principle (§1) by making planned-but-never-wired items fail CI instead of silently rotting.
- **`deadline` / `deferred_until` / `deferred_by` / `deferred_reason` schema** — per-row TTL fields added to the registry schema so each planned enforcement can state when it must be wired and who deferred it if not yet done; P045 planned rows carry `deadline: 2026-09-30`.
- **`_generated_at` required in verifier output** — `fsm_check_verifier_output` now rejects files missing or empty on `_generated_at`, closing the anti-fabrication gap where a verifier's timestamp could be omitted without FSM consequence; `agents/verifier.md` output spec and the verifier output template updated to match.
- **`cp4_glob_evaluated` audit event wired** — the event was documented in `skills/agent-protocol.md` but never emitted; now emitted by `fsm_check_cp4_curator_validation` before the production-touch check, resolving the ORPHAN verdict in the enforcement registry.
- **Regression tests: cross-plan gate, `_generated_at`, CP4 content-validation, CP5 blocking_findings** — 19 new bats assertions in `test-aid-fsm.bats` (cross-plan E-→P gate, `_generated_at` enforcement, CP4 content), `test-tiered-severity.bats` (CP5 four-case matrix), and the new `test-registry-ttl.bats` (6 TTL guard assertions).
- **`run-all-tests.sh` discovers `bats/test-*.bats`** — the test runner now auto-discovers bats suites in the `bats/` subdirectory in addition to `test-*.sh`, so `test-registry-ttl.bats` and all other bats suites run in CI without manual registration.

### Changed
- **CP4 curator-validation content-validated** — `fsm_check_cp4_curator_validation` previously accepted any file at the expected path; it now routes through `fsm_check_verifier_output` and rejects files missing valid `_generated_by`, `_generated_at`, or `classification` fields.
- **`blocking_findings` reads canonical top-level field** — `done-advance review → release` now reads the auditor's `blocking_findings:` key via `yaml_field` (line-start match only) instead of `grep -ciE` on prose; fail-closed on absent field, immune to false-positives from negations or body text; `agents/auditor.md` output template updated to emit `blocking_findings:` as the first top-level key.
- **Cross-plan init gate fixed for `E-NNN` IDs** — the gate that blocks starting a new EPIC when the previous plan has unreviewed Curator/Auditor findings was silently dead because the plan-prefix derivation used `grep -oP '^P\d+'` which never matched `E-NNN` style IDs; fixed using `BASH_REMATCH[1]` on `E-([0-9]+)`.
- **Enforcement registry ORPHAN rows resolved** — `dispatch_completed_late` removed (unwireable in scope), `cp4_glob_evaluated` promoted to `status: active`, `cp4_template_stale_name` aligned; verdict distribution: ORPHAN 3 → 0, ALIGNED 71 → 73.

### Fixed
- **`test-tiered-severity.bats` fixture broken by fail-closed** — six existing tests that used a minimal `audit-report.md` without `blocking_findings:` now fail the Step 3 fail-closed precondition; fixture `setup()` updated to write `blocking_findings: false` at line-start so the tests exercise their intended provenance logic without triggering the new guard.
- **TTL guard quoted-date regex** — `aid-registry-ttl-guard.sh` regex for `deadline:` and `deferred_until:` now handles `"YYYY-MM-DD"` (quoted) in addition to unquoted values, matching the flow-style YAML format used by the registry.

## [2.33.1] — 2026-06-15

### Fixed
- **docs-writer step ID** — EPIC steps with the `docs-writer` role failed `plan.json` conversion because the role's hyphen broke the `step.id` pattern `^step_[a-z0-9_]+$`; the role is now sanitized (hyphen → underscore) when building the step ID, while `step.role` keeps its canonical hyphenated value, so docs-writer steps convert and dispatch correctly.

## [2.33.0] — 2026-06-15

### Added
- **dispatch_mode selection in /aid-init** — fresh init now asks which dispatch mode to use (agent_tool / inline / subagent) instead of silently writing a default, and re-runs preserve a manually-chosen mode instead of resetting it to `agent_tool` on every run — the silent-reset that caused P043/P044 provenance false-blocks.

### Fixed
- **done-advance critical-finding precondition** — the release precondition now reads the auditor's structured `blocking_findings` verdict instead of grepping report prose for `critical.*security`; the old grep false-positived on negations ("No Critical … security issue") and even on notes describing the false positive, blocking clean releases and pushing users to edit audit evidence to get through.

## [2.32.0] — 2026-06-15

### Added
- **Real-scale Visual Companion mockups** — when building UI on an existing frontend, the companion records the real dimensions (container/column widths, row heights, font sizes, spacing, breakpoints) from the live code and reproduces them 1:1, so a mockup reflects what actually fits on screen instead of an arbitrarily-scaled sketch.

### Changed
- **Visual Companion canvas always white** — the browser companion frame no longer follows OS dark mode (white page background, `color-scheme: light`, dark-mode media query removed), so mockups are always judged on the same white canvas the target UI uses.

### Fixed
- **pre-commit hook shebang** — the generated FSM-guard pre-commit hook had no shebang, so git ran it under `/bin/sh` (dash on Debian) where its bash syntax (`[[ ]]`, `< <(find …)`) failed and blocked every commit, forcing `--no-verify`; it now starts with `#!/usr/bin/env bash` and `/aid-init` retrofits the shebang onto hooks installed before the fix.

## [2.31.0] — 2026-06-14

### Added
- **Whisper transcription via LiteLLM proxy** — voice transcription routes through the LiteLLM AI gateway instead of calling OpenAI directly, so audio spend and routing flow through one gated proxy (D-082 F2).

### Removed
- **Orphaned docs-deploy workflow** — removed the stale Docusaurus deploy CI workflow; the docs were migrated to the central eco docs site.

## [2.30.0] — 2026-06-14

### Added
- **Simplifier + Reporter at Plan Boundary** — two plan-boundary specialist agents run after a plan's last EPIC: the Simplifier proposes reuse/dedup/clarity refinements over the whole plan diff (S/M auto-applied through the gate-fixer → CP4 revert-on-fail rail, L deferred to the PM summary), and the Reporter tests the delivered functionality and writes a plain-language `.aid-o/reports/{plan_id}-delivery.md` from a fixed 7-section template, condensing the Auditor and Curator verdicts and leaving ≥1 on-disk test artifact as anti-fabrication proof. The new `delivery_report_present` compliance check (advisory, severity-routed) verifies the report's presence and on-disk `_test_evidence` at the plan boundary and rides the existing done-advance gate (`null` before the boundary, so it never false-blocks a non-final EPIC). Both agents are config-toggled and inert until a project re-inits.
- **Contributor guide (docs/extending-aid.md)** — a single reference documenting where each enforcement type lives (the type→instruction-home convention), the checklist to add one, the severity-layer vs hard-die FSM precondition patterns, the agent_tool dispatch-mode reality, and the P045 Simplifier + Reporter worked example.

## [2.29.4] — 2026-06-12

### Fixed
- **Force-Path Recovery Alert** — compliance blocks cleared via PM `--force` override never emitted the ✅ resolution alert because the force branch of done-advance skipped the entire P042 recovery block; recovery emission now lives in a shared helper (`fsm_emit_compliance_recovery`) called from both the clean re-run and the force-override paths, so every 🛑 blocked alert is paired with a ✅ regardless of how the block was cleared.
- **aid-init dispatch_mode Template** — the `/aid-init` plugin-discovery step still wrote `dispatch_mode: subagent` into `config/plugin.yaml` on every run, overriding the P043 `agent_tool` default and reintroducing guaranteed `verifier_provenance` false-positive blocks; the template now writes `agent_tool` and the dispatch-mode docs describe all three modes including the false-positive failure class.

## [2.29.3] — 2026-06-12

### Added
- **Check-severity sync guard** — new `test-check-severity-sync.sh` suite fails when a compliance check emitted by the FSM has no entry in `defaults/check-severity.yaml`, closing the trap where an unregistered check silently defaults to advisory and can never block
- **Compliance recovery alert documentation** — pipeline.md §7 now documents the P042 block/recovery Telegram alert pair, the `fsm_done_advance_recovered` dedup marker, and the `alert_on_compliance_recovery` config gate

### Changed
- **Accurate provenance aggregate in agent_tool mode** — compliance.json now reports `provenance_aggregate: "agent_tool"` instead of the misleading `"mixed"` when verifier dispatch runs via the CC Agent tool (non-blocking behavior unchanged)
- **dispatch_mode default single-sourced** — `defaults/orchestration.yaml` `dispatch.mode` is now the single source of the default (`agent_tool`, with all three modes documented); aid-fsm.sh resolves project `plugin.yaml` → plugin `orchestration.yaml` → hard fallback, removing the stale `subagent` doc/code drift
- **FSM internals simplification** — pure-bash `yaml_field()` reader replaces 51 copy-pasted `grep|awk` field reads (~100 fewer process forks per FSM run); repeated-fail counters, CP3 verifier-output evaluation, and the increment-step precondition fail ritual each consolidated into single helpers; shared `die()` moved to `lib/aid-stage-log.sh`; step-verify content checks read the file once; behavior unchanged (all 18 suites + 115 bats tests pass)

## [2.29.2] — 2026-06-10

### Changed
- **Visual Companion — current state mandatory in mockups** — when proposing UI changes to an existing component/page, the companion must always render the current look alongside the proposed changes (side-by-side or inline delta); showing only the new design in isolation is now explicitly prohibited; applies both in the "Read the Code First" refactoring flow and as a general design tip

## [2.29.1] — 2026-06-09

### Fixed
- **verifier_provenance false-positive blocking** — `dispatch_mode` defaulted to `subagent`, which requires `verifier_dispatch_start/complete` timeline events that the CC Agent tool never writes; every EPIC in standard AID self-hosted operation was therefore permanently blocked on `verifier_provenance`; the default is now `agent_tool` (set `dispatch_mode: subagent` in `.aid-o/config/plugin.yaml` to opt into strict interval-bracket provenance enforcement); a new `verify_provenance` branch returns a non-blocking `"agent_tool"` signal so `provenance_aggregate` never escalates to `"unverifiable"` in this mode

## [2.29.0] — 2026-06-07

### Added
- **Compliance recovery alert** — when a `done-advance review→release` succeeds with zero blocking failures for an EPIC that previously emitted a `🛑 release blocked` alert, AID now emits a `✅ compliance cleared, release unblocked` Telegram alert and writes an `fsm_done_advance_recovered` timeline event (dedup marker, observable test signal); controlled by `alert_on_compliance_recovery` config gate (default on)

## [2.28.3] — 2026-06-06

### Fixed
- **Self-referential dependencies** — a step whose dependency range covered its own number (e.g. "Steps 4-6" on step 6) produced a meaningless self-edge that downstream cycle detection rejected; self-references are now dropped during dependency remapping
- **Task-keyword dependencies** — `Depends on: Task N` / `Tasks M-N` lines were silently ignored because the parser only recognized "Step", even though `## Task N:` step headers are accepted; the dependency parser now treats the Task keyword the same as Step
- **Clean-tree guard vs. runtime queue** — the FSM init clean-tree guard aborted on any tracked change including AID's own `.aid-o/config/queue.yaml`, which the auto-pipeline mutates between phases, breaking multi-phase auto runs in projects where that file is tracked; the guard now excludes the runtime queue file
- **/aid-init .gitignore backfill** — `.gitignore` setup skipped the entire AID block when any `.aid-o/` entry already existed, so projects initialized before a later ignore entry (e.g. the runtime queue file) never received it; setup now appends individual missing lines on upgrade

## [2.28.2] — 2026-06-06

### Fixed
- **EPIC dependency renumbering** — when slicing a multi-EPIC plan into per-EPIC files, the Steps table renumbered each EPIC's steps locally (1..N) but the Depends On column kept the plan's global step numbers, producing dangling references like "step 2 depends on 4" in a 3-step EPIC that crashed dependency validation in `aid-epic-to-json.sh`; intra-EPIC dependencies (and the Goal step list) are now remapped to EPIC-local numbering

## [2.28.1] — 2026-06-04

### Fixed
- **FSM force-transition crash** — `aid-fsm.sh transition --force` aborted under `set -u` with "project_root: unbound variable" because `fsm_emit_audit_log` read the variable before its guarded fallback, breaking the manual-override escape hatch
- **CI bash test coverage** — the FSM, release, and integration test suites were silently skipped in CI (no `bats` installed) and had drifted stale against new preconditions; CI now installs `bats`, the four affected suites are repaired, and the FSM precondition layer gained real red/green coverage so it cannot be weakened unnoticed

## [2.28.0] — 2026-06-04

### Added
- **Skill & command authoring standards** — `skill-writing.md` and `command-writing.md` promoted to live skills, with `aid-lint-skill.sh` + `test-skill-lint.sh` enforcing the mechanical subset (pre-existing files grandfathered until revised)
- **Frontend Visual Anchoring enforcement** — `increment-step` hard-fails a frontend step that has `visual_refs` but whose output lacks a `## Visual Anchoring` section

### Changed
- **Model single source of truth** — model tier lives only in `role-cards.md`; removed the conflicting `orchestration.yaml` models block and the phantom `role_assignments` reference
- **role-cards.md holistic unification** — `e2e` is now a real step role with one rich card; `docs` renamed to `docs-writer` everywhere; `qa` gets a full card; structure and footer unified
- **Curator is propose-only** — curator recommends a disposition, the orchestrator applies fixes at every effort (S/M/L), and CP4 reviews the applied changes (reordered to run after the apply)
- **auditor.md overhaul** — scorable A–J categories, corrected scoring math, pre-merge timing
- **planner.md rewrite** — documents the real two-script pipeline (no fictional intelligent planner)
- **Config-policy single-sourcing** — escalation triggers and `skill_conflicts` deduplicated to one authoritative source; pre-filter regexes single-sourced to `pre-filter-rules.yaml`; `not_acceptable` patterns routed to real enforcement or explicitly marked advisory

### Fixed
- **Verifier provenance false-positives** — interval-bracket window replaces the ±60s test that flagged honest runs; fails closed when the severity registry can't be read; renamed the verdict to the honest `unverifiable` and added an explicit anti-fabrication instruction to the orchestrator
- **aid-run.md fiction + task→epic terminology** — removed non-existent state transitions / branch / merge-target claims
- **role_overrides downgraded to advisory** — the global `Bash(*)` permission made per-role scoping non-enforcing; the false security claim was removed
- **deserialize_dangerous pre-filter rule** — a `(?!_safe)` lookahead (unsupported by bash ERE) made the rule silently never match; rewritten ERE-safe
- **Honest phase-end note** — `run-management.md` no longer claims the controller auto-enforces the PM-GO boundary

### Removed
- **Unread config** — `orchestration.yaml` `models:` block and `release.skip_when`, and the `execution.yaml` global `retry:` block — read by nothing (per-gate `max_retries` is the only retry knob)

## [2.27.0] — 2026-06-02

### Changed
- **FSM state file unified to `fsm-state.yaml`** — retired the parallel `state.yaml` step-array that `aid-epic-to-json.sh` wrote but nothing read; every script, doc, template, and test now refers to the single FSM state file `fsm-state.yaml`, with the legacy `state.yaml` name kept only as a read fallback for in-flight pre-migration runs.

### Fixed
- **`/aid-stop` + `/aid-run --resume` state handling** — `/aid-stop` dropped the invented `session.*` schema, now reads the real `fsm-state.yaml` fields and logs the stop event through the canonical timeline helper; `--resume` reads `fsm-state.yaml`.

### Removed
- **Queue `pause` / `resume` / `reorder` subcommands** — removed from `/aid-status` and help; documented but never backed by any script (archived, restorable).

## [2.26.0] — 2026-06-01

### Changed
- **Documentation hygiene** — stripped version-stamped headings (e.g. `(NEW v2.16.0 — P032)`) from pipeline.md, agent-protocol.md, and related skills/commands; refreshed stale `Last Updated` dates; reconciled the brainstorming severity-enum claim and the aid-status `{epic_id}` naming drift.

### Fixed
- **aid-help level detection** — counted `state: DONE` in `state.yaml` (never written by the FSM), so every user showed Level 0; now reads `fsm-state.yaml`.
- **aid-init pre-push hook docs** — clarified pre-push uses its own marker `AID-ORCHESTRATOR-PREPUSH-START` (not the pre-commit marker), preventing duplicate hook blocks on re-run.
- **CP4 curator-validation filename** — verifier-output-template + verifier.md now name the FSM-required `verifier-output-cp4-curator-validation.md`; corrected the false "FSM does NOT enforce" note.
- **implementer model selection** — replaced the duplicated, incomplete model-tier list with a pointer to role-cards.md (single source of truth covering all roles).
- **brainstorming prior-work scan** — globbed nonexistent `.aid-o/epics/`; now `.aid-o/tasks/`.

### Removed
- **aid-research command + knowledge/Context7 layer** — removed the never-wired on-demand research command, its knowledge-base template, the integrations `knowledge:` config, the `context_scope.knowledge` plan-schema flag, and all orphaned Context7 references; archived to `docs/plans/AID-audit-2026-06/removed/` (restorable). The layer had no producer wired and no consumer.

## [2.25.0] — 2026-05-31

### Added
- **aid-emit-dispatch.sh wrapper** — new bash CLI with `start` and `complete` subcommands the orchestrator MUST call before/after every `Agent({subagent_type, prompt})` dispatch; writes `verifier_dispatch_start`/`_complete` events to timeline.jsonl plus tracks state in pending-dispatches.jsonl per evidence dir.
- **fsm_check_orphan_dispatches function** — reconciliation backstop in cmd_increment_step that refuses step transitions when pending-dispatches.jsonl shows a start event older than expected_duration_max without matching complete.
- **fsm_check_cp4_curator_validation function** — precondition in cmd_done_advance review→release that requires verifier-output-cp4-curator-validation.md when curator-report.md exists and any commit in `base_commit..HEAD` range touches production code paths. Mode-aware: skips with `cp4_skipped_streamlined_advisory` audit event when streamlined_mode is true.
- **fsm_check_streamlined_integration_review function** — precondition in cmd_done_advance review→release that, when streamlined_mode is true, requires all three of `verifier-output-cp3-code-review.md`, `verifier-output-cp3-security.md`, `gates_report.json` present in the evidence dir.
- **fsm_check_streamlined_abandoned function** — abandoned-but-shipped detector in cmd_done_advance that fires when streamlined_mode is true and timeline.jsonl has fewer than 3 events.
- **--streamlined CLI flag in cmd_init** — first-class lightweight execution mode that writes `streamlined_mode: true` into fsm-state.yaml and propagates through cmd_increment_step / cmd_done_advance / write_compliance_json.
- **coverage_mode + skipped_dimensions fields in compliance.json** — honest accounting of which dimensions were intentionally skipped per the streamlined contract. Field name `coverage_mode` (not `mode`) avoids collision with the existing fsm-state.yaml `mode` (manual/auto execution mode).
- **Four blocking checks in defaults/check-severity.yaml** — `dispatch_orphan_complete`, `cp4_curator_validation`, `streamlined_abandoned`, `streamlined_integration_review`, all severity blocking per AID-v3-principles.md §1 with explicit PM promotion (NR 8-14 empirical evidence across 4 projects).
- **cp4_production_paths field in defaults/execution.yaml** — configurable glob alternation for CP4 trigger detection; `/aid-init` stack-scan in `scripts/lib/aid-init-execution-yaml.sh` auto-populates project-specific defaults.
- **aid-json-to-run.sh Step 18 auto-init** — calls `aid-fsm.sh init` after run.md generation when fsm-state.yaml is absent, eliminating state.yaml vs fsm-state.yaml confusion (NR 10/12/14 anchor). Accepts a `--streamlined` passthrough (threaded from `/aid-run --streamlined` and `aid-auto-pipeline.sh`) that forwards to `cmd_init` so the auto-initialized state carries `streamlined_mode: true` — without it the streamlined activation switch would be unreachable.
- **test-aid-emit-dispatch.bats** — eleven fixtures: the original eight (start-only, start+complete pair, orphan complete, ceiling clamp, concurrent flock, missing output_file, malformed agent_id, inode-swap race) plus three CP3-security fixtures (`--focus` injection rejected by allowlist, jq-escaped pending construction, per-start nonce prevents ledger double-clear).

### Changed
- **cmd_increment_step preconditions** — added Component B orphan-dispatch backstop after the existing memory_used/memory_written/verifier_output checks; conditionally skips the per-step verifier_output check when streamlined_mode is true.
- **cmd_done_advance review→release preconditions** — added Component D streamlined_integration_review check, streamlined_abandoned check, and Component C CP4 enforcement (mode-aware in streamlined); all wired before the existing curator-report check; cites AID-v3-principles.md §1.
- **write_compliance_json schema** — emits top-level coverage_mode and skipped_dimensions fields; backward-compatible (legacy compliance.json without these reads as coverage_mode "full", skipped_dimensions []). The `mode` → `coverage_mode` rename is a breaking change for any downstream consumer that read the v0 draft.
- **fsm-state.yaml unified schema** — absorbs the legacy state.yaml steps[] array; backward-compat dual-file reader preserved.
- **skills/pipeline.md** — new §4 Dispatch Protocol subsection documenting the mandatory aid-emit-dispatch.sh wrapper chain; PRE-FLIGHT auto-init note.
- **skills/agent-protocol.md** — reference tables for the new audit events and check-severity entries.
- **commands/aid-run.md, commands/aid-plan.md, commands/aid-do.md** — --streamlined flag documentation and advisory trigger criteria.

## [2.24.0] — 2026-05-31

### Added
- **FSM Artifact Templates (`step-verify-template.md` + `verifier-output-template.md`)** — two new templates in `defaults/templates/` document the exact section/field schema enforced by `aid-fsm.sh` preconditions. `step-verify-template.md` lists the six required sections (Acceptance Criteria with `- [x]` checkboxes, Commit with 7+ hex SHA, Memory Used, Memory Written, Files, Result: PASS) each annotated with the failing `cmd_increment_step` reason. `verifier-output-template.md` is a single file covering all four CP variants (CP2 per-step, CP3 code-review, CP3 security, CP4 curator) with line-start `_generated_by:` / `classification:` / `verdict:` fields tied to `fsm_check_verifier_output`. Empirically motivated: WAN P027 EPIC 1 had 11 FSM precondition failures (5 from undocumented step-verify schema, 3 from undocumented `_generated_by` schema) while EPIC 2 had 0 — proving the schema is learnable, so it should be documented up-front rather than discovered through failure (NR 10 §4D, NR 12 §4A, NR 14 RC1).

### Fixed
- **`aid-plan-to-epic.sh` step counter fenced-block bug** — parser regex `^###?[[:space:]]+(Step|Task)[[:space:]]+([0-9]+)` previously matched `### Step N:` headers inside fenced code blocks, so any plan *about AID itself* that quoted AID step syntax got mis-counted and the pipeline crashed with `objective too short` errors. Fix tracks fence depth (toggle on lines matching `^[[:space:]]*````) across four scan sites: `has_impl_steps` awk quick-check, main step-numbering while-loop, `extract_step_content()` awk helper, and the objective-fallback awk. `aid-epic-to-json.sh` confirmed unaffected (parses EPIC table rows, not plan.md headers). New `test-aid-plan-to-epic-fence.bats` fixture reliably fails pre-fix and passes post-fix. Empirical anchor: AID-self P039 (v2.23.0 brainstorming plan) tripped this bug — NR 14 §4D.
- **`defaults/policies/permissions.yaml` stale MCP refs (action required: re-run `/aid-setup permissions`)** — the autonomous preset whitelist referenced MCP servers that no longer exist in current eco infrastructure: `qdrant-memory__*`, `shared-docker__*`, `shared-minio__*`, `shared-postgres__*`, `shared-playwright__*`, `shared-telegram__*`. Replaced with the actual running set: `vulcan-memory__{find,store,list}` (excluding destructive `vulcan-delete`), `eco-admin__*` 12 GREEN read-only tools (YELLOW writes intentionally excluded — require Telegram approval per ADR-17 D-077), `claude_ai_Google_Drive__*` 6 read-only ops. Kept `shared-github`, `shared-sequential-thinking`, `svc-mcp-tg-bot__send_message`, `plugin_context7_context7`, and `qdrant-brain` (back-compat with `skills/memory-mcp.md` contract). Playwright explicitly NOT auto-allowed — opt-in via per-project `settings.local.json`. Empirical anchor: NR 11 manual audit. **Existing projects that already ran `/aid-setup` retain stale entries in their local `.claude/settings.local.json` and should re-run `/aid-setup permissions` to refresh.**

## [2.23.0] — 2026-05-31

### Added
- **Section-Review Validate-Then-Verify** — brainstorming Step 6 sections now run a Sonnet `section-review` critic followed by an Opus ground-truth re-grep, presenting the PM a claim-verification table (validator claim → real command + output → ✓/✗) before approval; Step 7 adds a `cross-section-review` consistency check over the assembled plan.

### Fixed
- **Verifier focus card naming** — the `security-review` card in `role-cards.md` is renamed to `security` to match the canonical focus name used plugin-wide (orchestration tier, CP3 dispatch, planner, aid-run, epic templates); resolves a latent card-name mismatch with the registry.

## [2.22.3] — 2026-05-14

### Fixed
- **`skills/brainstorming.md` references to renamed visual-companion path** — v2.22.1 moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` but left two stale `skills/visual-companion.md` references in `brainstorming.md` (lines 107 and 258). The `test-instruction-consistency` bash suite caught it (`✗ Referenced file MISSING`) and CI went red since v2.22.1's push. Both references updated to the directory form.

## [2.22.2] — 2026-05-14

### Changed
- **Visual Companion — explicit remote-host networking + read-first-before-redesign rule** — Standalone Invocation Step 3 now mandates picking server bind mode (`127.0.0.1` for local agent / `0.0.0.0 --url-host <IP>` for remote SSH-VPN setup) BEFORE starting the server, with detection cues (`$SSH_CONNECTION` env, `hostname -I`) and a direct ask-PM fallback. Previously the remote case was a buried footnote, leaving the agent to start a loopback-only server that PM's browser couldn't reach. Plus new "Refactoring or Redesigning Existing UI — Read the Code First" section: when PM references an existing component / screenshot / page name, agent MUST ask "should I read the current implementation first?" and produce a structured data-inventory in chat before any mockup. Saves the iteration cycles where mockups get drawn against guessed data shapes and need full rewrite after the real component is read.

## [2.22.1] — 2026-05-13

### Fixed
- **Visual Companion skill discovery (hotfix v2.22.0)** — moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` directory structure. Claude Code's plugin loader only recognizes skills as user-invokable (slash-callable) when they live in `skills/<name>/SKILL.md` form; flat files are loaded for in-plugin reference but never registered as `/<name>` slash commands regardless of any `user_invocable` frontmatter flag. v2.22.0 release flipped the flag and added the standalone section but kept the flat-file shape, so `/visual-companion` did not appear in the command palette. This release fixes the structure only — no content changes.

## [2.22.0] — 2026-05-13

### Changed
- **Visual Companion skill is now user-invocable** — `/visual-companion` slash command opens a standalone demo session for verifying the browser round-trip (server start, HTML push, click capture, events read) without going through the full `/aid-plan brainstorm` flow. Skill frontmatter flipped `user_invocable: false → true` and a new "Standalone Invocation" section was added with explicit start/stop steps, npm-install first-run handling, and node_modules fallback path. Skill remains backward-compatible with the existing brainstorming integration — per-question gate behavior inside `/aid-plan brainstorm` is unchanged.

## [2.21.1] — 2026-05-13

### Fixed
- **`try_telegram_alert` test-mode guard** — `AID_TEST_MODE=1` env var short-circuits the helper before any `jq` or `curl` invocation, so bats fixtures and smoke tests no longer fire real-world Telegram alerts. Discovered post-P038 ship: cmd_done_advance blocking precondition (Step 3) and 3 other call sites previously emitted ~30 alerts during fixture development with `E-TEST-038: 1 blocking compliance failure(s)`. Shared bats `setup_test_evidence_dir` (test-helpers.bash) and `test-tiered-severity.bats` `setup()` now export the guard. Convention: any future side-effect helper (mail/Slack/webhook) should mirror this pattern.

## [2.21.0] — 2026-05-13

### Added
- **Tiered severity registry** — `.aid-o/config/check-severity.yaml` declares each compliance check as `blocking` or `advisory`; shipped by `/aid-init` with initial bootstrap per AID-v3-principles.md §1
- **`failures[]` array in compliance.json** — every release writes per-check failure entries with severity, evidence, and promoted_at, enabling deterministic blocking decisions
- **`aid-fsm.sh promote-check`** — explicit advisory→blocking promotion with mandatory ≥20-char reason and forensic audit-log entry
- **`aid-fsm.sh check-promotion-candidates`** — read-only scan of audit-log.jsonl identifying advisory checks that meet the AID-v3-principles.md §1 promotion criterion (force_override_rate < 0.05 across N≥5 EPICs)
- **`aid-promote-checks.sh`** — PM-facing markdown report wrapping the candidate scan
- **`test-tiered-severity.bats`** — 6 fixtures covering blocking-blocks, advisory-passes, --force-with-audit, short-reason-rejection, promote-check, and candidate identification

### Changed
- **`cmd_done_advance review→release`** — now refuses transition when any compliance failure has `severity: blocking`; structured error message includes per-failure evidence and copy-paste `--force --reason --blocked-checks` override snippet; per AID-v3-principles.md §1 "Detector without Enforcement is Decoration", this is the first concrete application of the principle and closes the P026 (WAN, 2026-05-13) failure mode
- **`fsm_handle_force_override`** — accepts new `--blocked-checks "<comma-list>"` flag; propagates to both timeline.jsonl and audit-log.jsonl
- **`aid-audit-log.sh cmd_append`** — new `--<key>-array "a,b,c"` flag-suffix convention emits JSON arrays in output entries; dash-to-underscore JSON key normalization for compatibility
- **`pipeline.md §7 DONE State`** — new "Tiered Severity Enforcement" sub-section documenting the override flow, the severity table, and the promotion ceremony
- **`write_compliance_json`** — populates `failures[]` array using check-severity.yaml registry; backward compatible (empty array when no failures)

## [2.20.2] — 2026-05-12

### Added
- **Plan-AC Diff Gate (P037 Phase 2, AID-010)** — new deterministic gate `plan_diff` in `execution.yaml` runs `aid-plan-diff.sh` after EXECUTE→GATES. Script parses plan-level `## Acceptance Criteria` section, executes each `verification_pattern` (3 types: `cmd`, `must_not_exist`, `must_contain` with any-match regex semantics) against codebase HEAD, emits `plan-diff.json` with per-AC verdict. Fail if ≥1 AC absent.
- **`aid-plan-diff.sh` Standalone Script** — new 281-line bash script under `plugins/aid-orchestrator/scripts/`. Standalone testable lifecycle (own provenance fields `_generated_by: aid-plan-diff.sh@v2.20.2`, own timeline events `plan_diff_start`/`plan_diff_complete`). 4 exit codes: 0 (all present), 1 (≥1 absent), 2 (graceful skip — Fast Mode or no AC section), 10 (input validation).
- **Plan Template AC Block** — `defaults/templates/plan.md` extended with `## Acceptance Criteria` section template using executable `verification_pattern` blocks (3 example patterns: cmd, must_not_exist, must_contain). New plans (P038+) gain plan-level AC verification by default.
- **Completeness Gate Sub-Check #20** — `plan-writing.md` Completeness Gate added 3 sub-rules (20a/20b/20c) enforcing `verification_pattern` block on every AC for new plans; legacy plans (P001-P036) without AC section skip the check (no violation). EVALUATION counter updated `out of 24` → `out of 27`.
- **`compliance.json plan_ac_match` Dimension** — `evaluate_compliance_checks` reads `plan-diff.json`, sets `checks.plan_ac_match: true | false | null`. False forces `compliance.overall: "fail"`; null = graceful skip for legacy plans or missing plan-diff.json.
- **`{plan_path}` Placeholder Token** — `aid-run-gates.sh` `resolve_placeholders()` helper substitutes 4 known tokens (`{plan_path}`, `{epic_id}`, `{run_id}`, `{base_commit}`) in gate commands via bash parameter expansion. `cmd_init` writes `plan_path:` field to state.yaml (realpath-normalized absolute path or literal `null` for Fast Mode EPICs). Unknown `{<token>}` triggers fail-loud exit — silent pass-through is a debug trap.
- **Plan-AC Diff Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-plan-ac-diff.bats` (8 tests covering all 3 pattern types, fail path, Fast Mode null + empty, legacy skip, resolve_placeholders + cmd_init replicas). Full bats suite now 52/52 ok.

### Changed
- **`aid-run-gates.sh` Gate Command Resolution** — gate commands now pass through `resolve_placeholders()` before `bash -c` execution. Exit code 2 counts as pass when gate's `pass_criteria` mentions "exit 2" (graceful-skip pattern).
- **`defaults/execution.yaml`** — legacy `{base}..HEAD` tokens in `docs_updated` gate renamed to `{base_commit}..HEAD` (aligning with `scope_check` convention; required for resolve_placeholders fail-loud safety). New `plan_diff:` gate entry appended after `scope_check:` (required: true, max_retries: 0, pass_criteria documents exit 0 or exit 2).

### Fixed
- **Goalpost Shift Detection** — Five EPICs (P019 F1+F2 frontend migration, P021 F4 backlog collision, P022 F6 Playwright→backend substitution, P023 F7 five concurrent shifts) previously passed to DONE without detection because gates didn't check plan AC reality vs implementation. Phase 2 `plan_diff` gate catches this class — every new plan with `verification_pattern` blocks gets per-AC executable verification on codebase HEAD before GATES→DONE.
- **`cp2_per_step_provenance` Type Mismatch (IMP-100)** — backfill in `aid-compliance-backfill.sh` previously wrote scalar string `"unknown"` for `cp2_per_step_provenance`, while the live writer in `aid-fsm.sh evaluate_compliance_checks` emits a JSON array (one entry per CP2 step). Type drift created silent correctness risk for queries doing `| length`. Backfill now writes `["unknown"]` (single-element array) to match live writer shape. Other 3 fields (cp3_*, provenance_aggregate) remain scalar — consistent with live writer.
- **`backfill_provenance` Silent Error Conflation (IMP-102)** — previously returned exit 1 for both "already-present skip" (normal) and "jq failure" (corrupted compliance.json). Step C caller incremented skip-count for both, masking real errors. Function now returns 0 (fixed), 1 (jq failure with stderr WARN), 2 (idempotent skip); caller case-statements on exit code and reports backfilled/skipped/errors separately in summary heredoc.
- **`verify_provenance` Unused `step_n` Parameter (IMP-103)** — `$3` was received in signature but never referenced in body. Renamed to `_step_n` with code comment explaining intentional retention for future per-step forensic attribution. Positional API stable (no call-site changes needed).
- **CLI Dispatcher Help Message Clarity (IMP-104)** — `aid-stage-log.sh` dispatcher previously listed `log_event`, `log_info`, `log_warn`, `log_error` uniformly in help text, leading users to expect timeline writes from all four. Comment + help message now distinguish: only `log_event` writes to timeline; `log_info`/`log_warn`/`log_error` are stderr-only severity-prefixed echoes.
- **`aid-fsm.sh` Missing `BASH_SOURCE` Guard** — top-level case dispatcher previously exited 1 on unknown args even when the file was sourced (e.g. from bats test fixtures), killing the test process. Dispatcher now wrapped in `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` (same pattern as `aid-stage-log.sh` fix from v2.20.1). Sourcing for testing purposes works cleanly. Existing `_load_aid_fsm` shim in `test-anti-fabrication.bats` becomes redundant but harmless.

## [2.20.1] — 2026-05-12

### Added
- **Verifier Provenance Verification (P037 Phase 1, AID-038)** — `aid-fsm.sh evaluate_compliance_checks` cross-references each `verifier-output-*.md` `_generated_by` field against `timeline.jsonl` `verifier_dispatch_start`/`_complete` events within a ±60s window for subagent mode, or validates `main-context@<commit-sha>` format with SHA verification for inline mode. Detected fabrication forces `compliance.overall: "fail"`.
- **Timeline Dispatch Events** — `pipeline.md` now instructs LLM to emit `verifier_dispatch_start` and `verifier_dispatch_complete` events with payload `{agentId, focus, step_n, evidence_dir, ts}` around every CP1/CP2/CP3 verifier `Agent()` call.
- **Honest Mode for No-Subagent Projects** — `.aid-o/config/plugin.yaml` new field `dispatch_mode: subagent | inline` (default subagent). Inline mode requires `_generated_by: main-context@<git-HEAD-sha>` format for verifier outputs; compliance check validates format + SHA existence rather than timeline match.
- **CLI Dispatcher for aid-stage-log.sh** — library now supports `bash aid-stage-log.sh <fn> <args>` invocation in addition to existing source-mode usage. Guard via `BASH_SOURCE[0] == ${0}` keeps source-mode behavior unchanged. Required so `pipeline.md` and `aid-plan.md` LLM-rendered docs can invoke `log_event` directly without a separate source step. Unknown function exits 1 with stderr help message listing available functions.
- **Anti-Fabrication Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-anti-fabrication.bats` (4 tests): verified subagent dispatch produces `provenance_aggregate: all_verified`; missing timeline events produce `fabricated` + `overall: fail`; inline mode with valid SHA produces `all_inline` + `pass`; CLI dispatcher regression test.

### Changed
- **`evaluate_compliance_checks` Schema** — `verifier_outputs` object now carries three new `*_provenance` fields (`cp2_per_step_provenance`, `cp3_code_review_provenance`, `cp3_security_provenance`) plus aggregate `provenance_aggregate: "all_verified" | "all_inline" | "mixed" | "fabricated" | "unknown"`. Pre-Phase-1 compliance.json files backfilled via `aid-compliance-backfill.sh` Step C (idempotent merge, adds `provenance: unknown` audit note attributing the migration to P037).

### Fixed
- **Compliance Telemetry Honesty** — post-Session-B telemetry (n=8 EPICs reporting 100% pass on all 4 dimensions) was previously vulnerable to fabricated `_generated_by` metadata. P023 reflection (NR 5, 2026-05-11) documented one such case in WAN project where agent wrote verifier outputs in main context but signed them as `aid-orchestrator:verifier@cp{2,3}-*`. Phase 1 enforcement detects this class of cheating.
- **`verify_provenance` TZ Bug** — jq <1.7 silently honors local TZ in `fromdateiso8601` even with `Z` suffix, producing a 1-hour offset on non-UTC hosts (CEST/PST/etc) and reading every dispatch as fabricated. Both `jq -s` invocations in `verify_provenance()` are now prefixed `TZ=UTC` so date parsing matches the `date -d`-derived `$min`/`$max` UTC epochs. Surfaced by Step 5 bats smoke test on CEST host.

## [2.20.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Check 17e (CLI Invocation Grounding)** — `plan-writing.md` Completeness Gate extended with 7th grounding category: for every cited `bash <script> <args>` in Implementation Detail blocks or step examples, verify the args against the actual script interface via `<script> --help` (preferred) or `head -100 <script>` (fallback). Mismatched signatures → REVISE_REQUIRED with suggested correction. Empirical: P035 C1 (2026-05-10) — plan cited a `--state-file` flag that did not exist in `aid-run-gates.sh` at write time; CP1 caught it on the 2nd pass.
- **Completeness Gate Check #19 (Design Defeat Detection)** — semantic LLM check active for plans with `type: bug-fix` in frontmatter. Reviewer answers Q1 (which precondition is being fixed?), Q2 (does the new code-path go through that same precondition?), Q3 (if not, is the bypass explicit + justified?). Q2:no + Q3:no → REVISE_REQUIRED. Pre-screening heuristic (mechanical) auto-activates #19 when goal/context contains fix/fail/bypass/precondition/validation AND the plan mutates `fsm-state.yaml` or `state.yaml` directly without a `cmd_<wrapper>` invocation. Heuristic explicitly EXCLUDES release/version mutations (CHANGELOG, README, marketplace.json, plugin.json, files in `release-policy.yaml` `version_files[]`) to prevent false positives on release plans. Empirical: P035 C2 — `yq -i '.state = "GATES"'` bypassed `cmd_transition()` and would have silently defeated the fix's own purpose.
- **Plan Type Taxonomy (`type:` frontmatter field)** — `defaults/templates/plan.md` now defines an enum `type: regular | bug-fix | refactor | docs` controlling which Completeness Gate checks activate per plan type. Default if missing: `regular`. Legacy `type: plan` (P001-P035 convention) treated as alias for `regular` — no migration required. Documented in new `## Plan Type` template section with a 4-row activation table.
- **`/aid-plan write` Mode Step 9 (CP1 Plan Quality Review)** — write mode extended from 8 to 9 steps; Step 9 mirrors brainstorm Step 9 (verifier dispatch with `docs-review` focus, codebase grounding pass, save review to `.aid-o/work/cp1-review-{plan_id}.md`). Activates #19 when `type: bug-fix` or pre-screening matches. Skip via `review_checkpoints.cp1_plan_review: false`. Closes the gap where plans written through `/aid-plan write` previously had no post-write quality review.
- **CP1 Verifier EVIDENCE REQUIREMENT** — Step 9 verifier prompt now requires concrete evidence (`command_run` + `output_excerpt`) before marking ANY item VERIFIED. Missing evidence → REJECTED with auto-retry; max 2 retries then ESCALATION. Applies to all #17 sub-checks + 17a-d + 17e + #19 (Q1/Q2/Q3 must cite plan path:line + codebase path:line). Empirical: P035 C3 — three bats helpers cited as "existing" from memory; none existed.
- **`test-plan-quality-enforcement.sh` Smoke Test** — bash smoke test exercising all 4 enforcement layers against a deliberately-defective fixture plan: layer 1 (extract `bash <script> --flag` + verify against real interface, with SKIP for already-shifted baseline), layer 2 (3-conjunctive heuristic positive + release-mutation negative control), layer 3 (count `^9.` in Mode: Write Plan section), layer 4 (header + field-name hits for EVIDENCE REQUIREMENT). Auto-discovered by `run-all-tests.sh`.

## [2.19.1] — 2026-05-10

### Fixed
- **`aid-release.sh` CHANGELOG-rename anomaly (IMP-093)** — observed 3× across v2.18.3 + v2.19.0 releases: when a `## [X.Y.Z]` header was pre-written for the upcoming release (PM/agent edited CHANGELOG before invoking script), the previous logic did a blind `sed`-replace on the newest header and silently collapsed the pre-written entry's history. Fix: detect actually-released version from `plugin.json`/`marketplace.json`/`package.json` (not CHANGELOG header) and route through new `update_changelog` helper that has 3 branches: (a) header matches new_version → skip rename (entry already correct), (b) header matches released version → bump existing header (existing behavior), (c) header is some other version → prepend new entry above (preserves history). 3 new bats assertions in `test-aid-release.bats` cover all 3 branches.

### Notes
- **README regex pattern mismatch** — second part of IMP-093 diagnosis showed that `.aid-o/config/project.yaml` regex patterns like `"Plugin: {VERSION}"` don't match actual content `**Plugin:** 2.X.Y` (markdown bold prefix missing in pattern). Consumer projects must update their `.aid-o/config/project.yaml` regex patterns to escape `**` for sed: e.g., `"\\*\\*Plugin:\\*\\* {VERSION}"`. This repo's `.aid-o/config/project.yaml` (gitignored) was updated locally; downstream projects need to edit theirs once if affected.

## [2.19.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Checks 17a–17d** — `plan-writing.md` Completeness Gate extended with 4 new grounding categories aimed at empirical gaps from P019/P021/P032: (17a) backlog ID grounding via whole-plan `\bT-[0-9]+\b` regex + `git log --since="24 hours ago" --grep` — empirical: P021 T-132/T-133 reserved by commit 1907e77 same morning; (17b) test directory convention via POSIX `find tests/ -type f -name "*<basename>*"` — empirical: P021 plan said `tests/integration/`, reality `tests/unit/`; (17c) DB-field semantics via `[A-Z][a-zA-Z]+\.[a-z_]+` regex + `grep` on models.py for stored Column vs `@property`/computed — empirical: P021 assumed automatic, reality stored Column; (17d) file removal grounding via `ls <path>` existence check — empirical: P019 `must_not_exist` file actually existed at EPIC end. EVALUATION counter bumped 18 → 22.
- **`commands/aid-plan.md` Step 9 Verifier Prompt Extension** — verifier dispatch prompt extended with extraction patterns and verification commands for the 4 new grounding categories. Each category gets explicit VERIFIED/ABSENT semantics and REVISE_REQUIRED conditions. Backlog ID ABSENT accepts "T-NNN to be allocated at plan-write time" as a plan-allocation candidate.
- **`defaults/templates/plan.md` Resources Verification Block** — new section between Constraints and Risks with 12 checkbox items: 6 (Existing Resources from #17) + 4 (Plan Assumptions from #17a-d) + 2 (Resolution gates). Auto-populated by `/aid-plan` Step 9 verifier dispatch; PM-visible manual review checklist. Detection scope clarified as whole-plan body scan — no `related_backlog` or similar field required.
- **`test-cp1-grounding.sh` Smoke Test** — bash smoke test that constructs a deliberately-broken plan with violations across all 4 sub-checks and verifies extraction patterns produce correct outputs. POSIX-only (`command -v find` guard, no `fd` dependency), trap-cleaned tmpdir, 5 PASS branches.

## [2.18.3] — 2026-05-10

### Added
- **`aid-fsm.sh advance-to-gates` Atomic Command** — single command runs gates and routes through `cmd_transition EXECUTE GATES` on success. Eliminates the `gates_no_generated_by` chicken-egg precondition fail (P020 8×, P021 4× — 12 friction events across 3 EPICs). Atomicity: state changes only on full success; gates failure leaves state at EXECUTE (never modified). No new state added — `VALID_STATES` and `VALID_TRANSITIONS` unchanged. Single source of truth for preconditions remains `check_preconditions` (`_generated_by`, `fsm_check_verifier_output`, `fsm_check_grandfather`).
- **Bats Coverage for advance-to-gates** — `test-aid-fsm.bats` expanded from 14 to 18 assertions covering all branches: success path, gates-fail path (state stays EXECUTE), missing CP3 outputs (cmd_transition rejects after gates pass), and aid-run-gates.sh env-var bypass behavior with and without `AID_GATES_TRIGGERED_BY_FSM=1`. New `test-helpers.bash` helpers: `seed_test_state_files`, `setup_passing_execution_yaml`, `setup_failing_execution_yaml`, `write_valid_verifier_output`.

### Changed
- **`aid-run-gates.sh` State Guard** — accepts env-var bypass `AID_GATES_TRIGGERED_BY_FSM=1` as the signal that the caller is `cmd_advance_to_gates`. Strict equality check (`=="1"`) prevents accidental bypass via truthy values. Manual two-step flow (state==GATES + run-all without env var) remains fully backward-compatible. Error message now hints at the atomic `advance-to-gates` alternative when state==EXECUTE without the env var.
- **`pipeline.md §5 GATES State`** — adds Recommended Flow (v2.18.3+) subsection documenting `aid-fsm.sh advance-to-gates`; preserves Manual Two-Step Flow subsection for debugging and crash recovery. Both flows fully documented with semantics, env-var signal, and timeline events.

### Fixed
- **`gates_no_generated_by` Precondition Fail Class** — empirical motivation for the atomic command: P020 had 8 such failures, P021 had 4 — 12 friction events across 3 EPICs from a single root cause (chicken-egg between gates runner state guard and transition's `_generated_by` check). Target post-deploy: 0 fails of this type.

## [2.18.1] — 2026-05-09

### Fixed
- **`aid-diagnostic.sh` 3 bugs** — (1) Branch hygiene now reads from `fsm-state.yaml` instead of `state.yaml` (which is the JSON steps array and has no `branch:` field); was reporting 88–100% "missing" for all projects. (2) Deploy era loop adds `post-session-b` so post-Session-B EPICs appear in the era distribution table — were previously silently dropped. (3) `collect_precondition_fail_reasons` → `collect_fsm_fail_reasons` extends jq filter to capture `fsm_increment_fail` and `fsm_done_advance_fail` in addition to `fsm_precondition_fail`; was missing 52% of all FSM fail events (the dominant category: `verify_no_*` format-discovery failures).

## [2.18.0] — 2026-05-08

### Added
- **CP2 Per-Step Verifier Pre-Filter** — `aid-prefilter.sh` classifies each step's git diff as `SKIP` (docs/config/test only, exit 0), `RUN` (code changed, exit 10), or `FAIL` (hardcoded secret/credential detected, exit 20). `cmd_increment_step` reads the classifier verdict and refuses to advance past a FAIL classification; SKIP bypasses CP2 verifier dispatch entirely. `pre-filter-rules.yaml` holds the rule set (docs patterns, secret patterns, code extensions). Closes the CP2 dead-weight problem where verifier was dispatched on pure-docs commits, burning tokens with no signal.
- **CP3 Integration Review Enforcement** — `EXECUTE→GATES` precondition now requires both `verifier-output-cp3-code-review.md` and `verifier-output-cp3-security.md` to exist in the evidence dir. Previously the transition was gated only on `current_step >= total_steps`. Missing CP3 outputs produce a specific precondition failure message listing which files are absent.
- **`fsm_handle_force_override` Unified Dispatcher** — replaces 4 inline `--force` bypass blocks with a single `fsm_handle_force_override from to reason state_file timeline_file` function. Validates `--reason` length ≥ 20 chars (short reasons rejected with exit 1 before any state mutation), emits `fsm_force_override` timeline event, writes to `aid-audit-log.sh` audit trail. Consistency: all force paths now go through identical logging — no more "force but no timeline event" edge cases.
- **`aid-audit-log.sh`** — standalone append-only audit log writer (`aid-audit-log.sh append <evidence_dir> <event_type> <json_payload>`). Writes to `evidence/{epic}/{run}/audit-log.jsonl`. Used by `fsm_handle_force_override` and available for future audit-requiring commands.
- **Verifier Nuanced Deprivation Context** — `agents/verifier.md` updated with classification-aware dispatch: verifier receives pre-filter classification + the specific diff that triggered RUN so it can focus on the actual change rather than the full step output. Adds step-level `## Memory Used` / `## Memory Written` enforcement to verifier output schema.
- **Compliance `verifier_outputs` Object Schema** — `compliance.json` now records per-step CP2 outcomes as an object (`{step_N: {classification, verdict, ts}}`). `evaluate_compliance_checks` validates presence and structure. `write_compliance_json` populates the field from step-verify evidence.
- **Compliance `deploy_era` Three-Tier Field** — `compliance.json` carries `deploy_era: pre-session-a | post-session-a | post-session-b` based on `DEPLOY_DATE` marker comparison. Enables longitudinal trend filtering: `--era post-session-b` sees only post-Session-B EPICs, `--era latest` auto-resolves to newest era present in evidence tree.
- **`aid-compliance-report.sh --era` + `--compare`** — `--era <name>` filters aggregated report to one deploy era; `--era latest` auto-resolves. `--compare ERA1,ERA2` produces side-by-side dimension table (pass/fail/null per era) for Session A → B delta analysis without Excel.
- **`aid-compliance-report.sh --reflect` `force_override` Extension** — `--reflect` pattern detection now includes `force_override` dimension: avg > 1 per EPIC → `🔴 SYSTEMATIC` banner. Average computed via integer arithmetic (`avg_x100 > 100`) to avoid floating-point dependency. Feeds the Session A → B "what holes remain" PM gate.
- **`aid-epic-summary.sh` Auto-Generated EPIC Summary (IMP-090 fold-in)** — `done-advance` hook calls `aid-epic-summary.sh generate <evidence_dir>` after `write_compliance_json`. Produces `<evidence_dir>/epic-summary.md` with 5 sections: ✅ Co bylo dodáno (git log since base_commit), ⚠️ Varování a přeskočené kroky (timeline events: branch mismatch, unusual branch, force override, repeated precondition fail, increment-step churn), ❌ Co se nestihlo (audit/curator blocking/L-effort findings), 📋 Co dělat dál PM akce (escalations, force override follow-up, L-effort proposals), 🔍 Honest signal trust level (HIGH/MEDIUM/LOW from compliance.json + branch heuristics). Best-effort: each section individually guarded with `|| true`; generation failure logs a warning and never blocks release flow. IMP-089 forward-compat: reads `branch_convention:` from `.aid-o/config/project.yaml` if present for feature-branch false-alarm suppression.
- **Plan-Writing Gate #18** — `plan-writing.md` Completeness Gate adds check #18: plans must not contain forbidden phrases that assert completeness without evidence ("already handles", "no changes needed", "existing implementation covers"). Accompanies Gate #17 (codebase grounding) from v2.17.0.
- **bats Suite Expanded to 33 Assertions** — 5 files: `test-aid-fsm.bats` (14, +5 CP2/force assertions), `test-aid-prefilter.bats` (6, NEW — SKIP/RUN/FAIL exit codes + output format), `test-aid-compliance.bats` (4, NEW — --era/--compare/--reflect triple-condition), `test-aid-epic-summary.bats` (2, NEW — 5-section headers + force_override timeline propagation), `test-aid-run-gates.bats` (7, unchanged from v2.16.0).

### Changed
- **pipeline.md §CP2 and §CP3** — full rewrite of both subsections to document v2.18.0 enforced protocol: pre-filter classifier, verifier dispatch conditions, CP2 evidence file naming (`verifier-output-step-N.md`), CP3 mandatory dual-file output schema, fix-loop (gate-fixer → verifier, max 2 iterations).
- **pipeline.md §force_override policy** — new subsection documenting `fsm_handle_force_override` contract: required fields, minimum reason length, audit trail, PM-only authorization, forbidden patterns.
- **pipeline.md Epic Summary** — new subsection documenting IMP-090 5-section schema, per-section data sources, trust level heuristics table, IMP-089 forward-compat note.
- **`aid-fsm.sh plan_json_hash` pipefail guard** — `grep '^plan_json_hash:'` with `set -eo pipefail` caused silent exit when field absent from `state.yaml`. Wrapped with `|| true` guard. Exposed by CP2 SKIP-classification test (step-verify without hash field).

### Fixed
- **`aid-stage-log.sh` JSON array/object prefix corruption** — `log_event` escaped payload before writing to `timeline.jsonl`; payloads starting with `[` or `{` (JSON arrays/objects) were double-escaped on the `data:` field. Added prefix detection: if payload starts with `[` or `{`, write `data: <payload>` verbatim; otherwise apply existing escape. Discovered during CP3 verifier-output path testing.

## [2.17.0] — 2026-05-06

### Added
- **CP1 Codebase Grounding Rule** — `plan-writing.md` Completeness Gate gains check #17 (16 → 17). Plans must verify every named external resource (functions, helpers, file paths, ports, services, commands, env vars) against the real codebase or running infra. Hand-wave like "presumably exists in some lib" or "should be available" is a hard fail. Addresses systematic CP1 blind spot identified in P032 retrospective: 5 PM-authorized resolutions (C1–C5 in P032) were all of this kind — reviewer cannot detect *absence* of helpers/files the plan presumes exist.
- **Verifier Codebase Grounding Pass** — `/aid-plan` Step 9 (CP1 review) verifier dispatch now MUST extract a flat list from the plan of every named function, helper, file path, port, service, command, and env var, and verify each against the real codebase / running infra (`grep`, `ls`, `docker ps`, `command -v`). Each item gets VERIFIED (with location) or ABSENT (mapped to a Create step). Plans with ABSENT items not mapped to Create steps → REVISE_REQUIRED.
- **`aid-compliance-report.sh --reflect`** — lightweight `/aid-reflect` (per AID-013). Per-dimension breakdown (pass / fail / null counts + 10-cell text bar chart) with pattern detection: 0 fails → ✅ green, 1 fail → ⚠️ INVESTIGATE (could be one-off), ≥ 2 fails → 🔴 SYSTEMATIC (hole in Session A enforcement). Recommended-next-action section addresses PM retrospective from P032: aggregate ≥ 80 % can hide a single dimension failing systematically; per-dimension trend is the actionable signal before Session B brainstorm.

## [2.16.1] — 2026-05-06

### Fixed
- **`aid-compliance-backfill.sh` aborts on legacy v1 evidence** — `set -euo pipefail` caused the backfill to abort on the first vulcan/sousto evidence dir whose `state.yaml` lacked a `branch:` field (`grep` returns 1 → pipefail propagates). Wrapped the `grep | awk` extraction (and the `jq | sort | head` pipeline in `backfill_state_created_at`) in `|| true`. Discovered during the v2.16.0 post-merge deploy run.
- **`aid-compliance-backfill.sh` corrupts legacy v1 JSON state files** — some pre-v2 evidence dirs store `state.yaml` as a JSON array of step objects (legacy `plan_progress.json` format). The backfill appended `created_at: <ts>` directly, breaking JSON validity (the line landed on the same line as the closing `]` because the file lacked a trailing newline). Added file-format detection: if the first non-blank char is `[` or `{`, log a warning and skip stamping. Plus a defensive `printf '\n'` guard before any append on YAML files. Live tree was repaired with `sed` post-incident; no data loss.

## [2.16.0] — 2026-05-05

### Added
- **Branch Enforcement in PRE-FLIGHT** — `aid-fsm.sh init` automatically creates `task/{epic_id}/main` from main/master/develop, detects mismatch with copy-paste fix, respects worktree mode. Closes AID-001 (65% of pre-Session-A state.yaml claimed `branch: main` with no actual task branch, breaking done-advance audit trail).
- **Real Gates Execution Provenance** — `aid-run-gates.sh` rewritten with yq parsing, emits `gate_runner_start` / `gate_runner_complete` timeline events and writes `_generated_by` / `_generated_at` / `_command_log` provenance fields into `gates_report.json`. EXECUTE→GATES precondition mechanically rejects hand-written reports.
- **Lazy execution.yaml Creation** — `aid-init` (and `aid-fsm.sh init` auto-recovery) generates per-project `execution.yaml` from auto-detected stacks (Python, TypeScript, Go, Rust, bash) with `# DEPENDENCY` hint comments per gate command. Closes AID-006 (71% of projects had no execution.yaml).
- **Compliance Telemetry** — `done-advance` writes per-EPIC `compliance.json` with 6-dimension schema (3 measured for Session A, 3 `null` for Sessions B/C). Standalone `aid-compliance-backfill.sh` for one-shot pre-deploy backfill (also stamps mid-FSM `state.yaml.created_at` per CP1 M2). Aggregator `aid-compliance-report.sh` produces pre vs post comparison with `--since` and `--era` filters.
- **svc-mcp-tg-bot MCP Server** — new Docker service in `services/mcp-tg-bot/` (FastMCP, stdio + HTTP transport on port 8817 — see Removed section for the legacy MCP that previously held this port). `send_message` tool with HTML parse_mode default. Token shared via `/opt/eco/services/.env`. Includes `docker-compose.snippet.yml` for PM to integrate into `/opt/eco/services/docker-compose.yml`.
- **FSM Repeated-Fail Telegram Alert** — `aid-fsm.sh` emits `fsm_precondition_repeated_fail` event and best-effort `try_telegram_alert()` HTTP POST to localhost:8817 when same precondition fails ≥ 3 times on the same EPIC.
- **Parametrized Diagnostic Script** — `aid-diagnostic.sh` reusable forensic analyzer (refactored from Krok 0 logic, supports `--evidence-root`, `--output md|json`, `--limit`).
- **bats Unit Test Suite** — 16 assertions across `test-aid-fsm.bats` (9), `test-aid-run-gates.bats` (3), `test-aid-init.bats` (4) covering all new FSM preconditions, gate runner provenance, and stack detection. Runs via `bats plugins/aid-orchestrator/scripts/tests/bats/`.
- **Dependency Pre-flight Script** — `aid-check-deps.sh` verifies `bash`, `git`, `jq`, `yq` (mikefarah variant only), plus optional `bats`, `direnv`, `docker`, `curl`. cmd_init now has fail-fast guard for `git` + `jq`.
- **README Requirements Section** — explicit dependency table in plugin README listing required runtime, optional dev, and optional Telegram-alerts tools with install commands per OS.
- **Worktree Development Guide** — plugin README section + committed `.envrc` with `AID_PLUGIN_PATH=$(pwd)/plugins/aid-orchestrator` and `PATH_add` for direnv-driven worktree workflows.
- **DEPLOY_DATE Marker File** — `plugins/aid-orchestrator/DEPLOY_DATE` (ISO 8601 UTC) consumed by `fsm_check_grandfather()` as the pre/post-Session-A threshold. Fallback chain: `AID_DEPLOY_DATE` env → `${AID_PLUGIN_PATH}/DEPLOY_DATE` → `${SCRIPT_DIR}/../DEPLOY_DATE`.

### Changed
- **pipeline.md** — three subsection rewrites: PRE-FLIGHT branch-enforcement catalog (5 HEAD states + 2 timeline events), GATES EXECUTE→GATES precondition with `_generated_by` requirement and grandfather caveat, DONE phase Compliance Telemetry section with 6-dimension table and null semantics caveat.
- **state.yaml schema** — adds `created_at` field (ISO 8601 UTC) used by grandfather logic for backward-compat with pre-deploy EPICs.
- **lib/aid-stage-log.sh** — new `log_info` / `log_warn` / `log_error` helpers with `[INFO]/[WARN]/[ERROR]` severity prefix on stderr (greppable, exported alongside `log_event`).
- **fsm_precondition_fail timeline event** — now carries `reason` field (set by individual precondition cases via `_PRECONDITION_FAIL_REASON`) so `fsm_count_recent_fails` can group repeated failures by failure type.
- **aid-fsm.sh::cmd_init** — overrides caller's `branch` arg ($5) with actual `git rev-parse --abbrev-ref HEAD` after PRE-FLIGHT enforcement so `state.yaml.branch` reflects post-enforcement reality (PM-authorized resolution C3).

### Fixed
- **Branch hygiene gap** — closes the 65% of pre-Session-A `state.yaml` files claiming `branch: main` with no actual task branch. New auto-checkout closes the loop with `done-advance` release sub-phase `git merge`.
- **Fake gates reports** — closes the 0% gate-runner execution evidence in 93 analyzed timelines. Provenance fields make hand-written reports mechanically detectable.
- **Missing execution.yaml** — closes the 5/7 (71%) projects lacking gate config, which forced agents into ad-hoc gate names per EPIC with no cross-project consistency.
- **Mid-FSM EPIC unblock (CP1 M2)** — backfill stamps `created_at:` into existing `state.yaml` from earliest timeline event ts, preventing the ~14 mid-FSM EPICs identified in diagnostic-findings from becoming unresumable post-deploy.
- **aid-run-gates.sh CLI parser** — fixed `${4:-default}` swallowing `--state-file` flag when caller skipped the optional 4th positional, which silently broke `gate_runner_start`/`gate_runner_complete` events for FSM-driven invocations. Regression test added to `test-run-gates.sh`.
- **Test suite git-context invariant** — `test-fsm.sh` and `test-integration-phase1.sh` setup() now `git init` their mktemp dirs so PRE-FLIGHT branch enforcement (new in this version) finds a working tree. Existing tests preserved without behavioral change.

### Removed
- **Legacy `svc-mcp-telegram` MCP (port 8817 takeover)** — the previous general-purpose Telegram MCP at localhost:8817 is decommissioned and replaced by `svc-mcp-tg-bot` on the same port. The old MCP exposed 9 tools (send_message, edit_message, search_dialogs, get_draft, set_draft, get_messages, media_download, message_from_link, delete_message) for general Telegram interaction; the new MCP exposes 1 tool (send_message) focused on AID-internal alerting. PM verified zero call sites in repo before removal (only permissions.yaml whitelist + docs entries referenced it). `defaults/policies/permissions.yaml` updated accordingly: 9 `mcp__shared-telegram__*` whitelist entries collapsed into 1 `mcp__svc-mcp-tg-bot__send_message` entry.

## [2.15.0] — 2026-03-25

### Added
- **Mechanically Enforced FSM** — `aid-fsm.sh transition` now verifies preconditions before allowing state changes: READY→EXECUTE requires `plan.json`, EXECUTE→GATES requires all steps complete, GATES→DONE requires `gates_report.json` with `overall: pass`, ESCALATION exits require `escalation_decision` set
- **`verify-state` Command** — new `aid-fsm.sh verify-state` returns current state + allowed transitions as JSON for LLM orientation
- **`set-field` Command** — new `aid-fsm.sh set-field` for structured state mutations (escalation decisions, custom fields)
- **FSM Audit Trail** — all `aid-fsm.sh` operations (transitions, precondition failures, force overrides) logged to `timeline.jsonl` via `aid-stage-log.sh`
- **`--force` Escape Hatch** — `aid-fsm.sh transition --force` bypasses preconditions with PM approval, logged as `fsm_force_override`
- **Gates State Check** — `aid-run-gates.sh --state-file` refuses to run unless FSM state is GATES
- **Gates Report Persistence** — `aid-run-gates.sh --report-file` auto-writes `gates_report.json` (required by GATES→DONE precondition)
- **Mechanical Enforcement Protocol** — new section in `aid-run.md` with 8 non-negotiable rules for FSM compliance
- **DONE Sub-Phases** — `done_phase: review → release` within DONE state, managed by `aid-fsm.sh done-advance` with evidence-based preconditions (curator-report, audit-report, pm_decision=merge)
- **Reserved Field Protection** — `set-field` rejects writes to `state` and `done_phase` (must use dedicated `transition`/`done-advance` commands)
- **Release Script FSM Guard** — `aid-release.sh` refuses release when `state.yaml` exists with `done_phase != release` (Layer 2 defense)
- **Git Pre-Commit Hook** — FSM guard on `task/*` and `epic/*` branches blocks commits in DONE/review and READY states (Layer 3 defense)
- **Hook Auto-Install** — `/aid-init` installs/upgrades pre-commit hook with marker-based append (coexists with existing hooks)
- **Step Verification Enforcement** — `increment-step` refuses to advance without `step-{N}-verify.md` evidence file (AC checklist + visual check)
- **Agent Dispatch Protocol** — 6 non-negotiable rules in pipeline.md: verbatim plan content, visual assets, post-step AC verification, visual verification for UI, resume-on-failure, visual context dispatch
- **Visual Companion** — browser-based HTML prototype viewer for brainstorming (opt-in, Node.js server adapted from Superpowers). Generates interactive mockups during design sections, saves approved HTML as 4th input type for visual assets pipeline. Per-question visual/text decision taxonomy.
- **Visual Assets Pipeline** — 4 input types (GitHub repo, AI Studio URL, PNG, Visual Companion) → unified `visual-spec.yaml` output; `visual_refs` field in plan.schema.json; visual dispatch protocol in pipeline.md §4; Visual Anchoring requirement in frontend role card; screenshot comparison protocol (MATCH/PARTIAL/MISMATCH); forbidden text-only UI descriptions in plan-writing.md
- **Plan-Level DONE Gate** — `aid-fsm.sh init` blocks cross-plan run if previous plan has unreviewed C+A findings (`ca-review-complete` marker required); enforces "dispatch per EPIC, validate per Plan" model
- **Step-Verify Content Validation** — `increment-step` now requires at least one `- [x]` AC checklist item and one commit hash (7+ hex chars); prevents minimal "Result: PASS" without substance
- **Plan.json Init Warning** — `aid-fsm.sh init` warns when plan.json steps lack `objective` field
- **Per-Project Agent Memory (Qdrant)** — 10-category deep codebase scan (architecture, API, data, UI, config, testing, conventions, security, DevOps/CI-CD, cross-cutting concerns); `memory-mcp.md` skill with entry schema, quality rules (≥20 word summary, real code examples, 5 rejection criteria), store/find protocol, supersede pattern; pipeline §4 memory READ (2-tier context injection ~1500 tokens); pipeline §7 Scanner dispatch at plan boundary; `memory_writes` mandatory in agent output; `## Memory Used` + `## Memory Written` enforced in step-verify by `increment-step`; Auditor Memory Health category (stale detection, conflict detection, coverage check); kondice flow (auditor flags → scanner verifies)

### Changed
- **FSM Valid States** — added ERROR to `VALID_STATES`; added `→ERROR` transitions from READY, EXECUTE, GATES, ESCALATION
- **Escalation Cleanup** — `escalation_decision` field auto-cleared when leaving ESCALATION state
- **Pipeline §3-§6** — each section now documents which FSM preconditions enforce correct behavior

### Fixed
- **Dead Cross-References** — replaced 20+ references to deleted v1 files (dispatch-protocol.md, epic-orchestration.md) with v2 equivalents across 11 files
- **v1 State Names** — replaced v1 FSM states (PM_APPROVAL, CURATOR_RESOLVE, PHASE_CHECK, IDLE) in pipeline.md; added v1 legacy headers to improvement-proposals.md and analytics.md
- **v1 Directory Paths** — updated CLAUDE.md workspace structure from v1 (01-plans/, 04-engine/) to v2 (plans/, work/)
- **Pre-Commit Hook** — removed dead case statement (non-functional code from refactoring)

## [2.6.0] — 2026-03-14

### Added
- **Standards Enforcement System** — two standard sets (`general.yaml` with 26 language-agnostic rules, `vulcan.yaml` with 22 ecosystem-specific rules + 4 severity overrides) selectable during `/aid-init`
- **Standards Gate** — new `standards_compliance` gate in `execution.yaml`, 100% deterministic (pattern/structural/file-exists rules only), custom/LLM rules are auditor-only advisory
- **Standards Audit Category** — new conditional category I) in auditor with full-codebase scan, severity-based scoring (cap 5 violations/rule), 15% weight when active
- **Standards Curator Integration** — hotspot detection (3+ violations of same rule = systemic), `source_type: standards` proposals with auto-approve for S-effort fixes
- **Standards Dispatch Context** — agents receive filtered standards in prompt (gate-blocking first, filtered by language), omitted when `standards.active == 'none'`

### Changed
- **Auditor Category Count** — 8→9 categories (5 mandatory + 4 conditional), weight redistribution when standards active (Code 30→25%, Security 30→27%, Docs 25→23%)
- **Agent Execution Summary** — includes `Standards violations noted: {count}` for trend tracking
- **Init Flow** — standards profile selection (general/vulcan/none) with `project.yaml → standards` config block

## [2.5.0] — 2026-03-13

### Added
- **Plugin Path Discovery** — `/aid-init` discovers and caches plugin installation path in `config/plugin.yaml`; Script Execution Protocol in `agent-core.md` teaches all agents how to resolve `scripts/X.sh` references
- **Brainstorming Question Format Template** — concrete format with Effort/Risk per option, recommendation with "Why not" reasoning, and webhook delivery example
- **Brainstorming Handoff Summary** — plan-writing presents decision summary + 6 options including `/aid-run --auto` with `autonomous_mode` prerequisite warning
- **Superpowers Conflict Resolution** — CLAUDE.md template includes conflict table (brainstorming, writing-plans, executing-plans → AID equivalents); 3 `skill_conflicts` entries in `orchestration.yaml`
- **Documentation Gate Enforcement** — path-pattern correlation: `docs_updated` gate fails only when API-path files changed without doc updates; auditor escalates missing API docs to high severity

### Changed
- **PRE-FLIGHT Plugin Verification** — `/aid-run` and `/aid-do` verify `plugin_path` on startup with cache invalidation fallback
- **Dispatch Context** — `agent-protocol.md` input format includes `plugin_path` for dispatched agents
- **Brainstorming Rule 8** — now explicitly requires effort estimate (S/M/L) and risk (L/M/H) per option

### Fixed
- **`/aid-plan-epic` stale references** — replaced with `/aid-plan --epic` across brainstorming, plan-writing, pipeline, and planner skills (command merged in v2.0)
- **`aid-plan.md` step count** — Steps 1-7 showed `/8` denominator instead of `/9` after CP1 review was added as Step 9

## [2.4.0] — 2026-03-12

### Added
- **PM Merge Decision Gate** — DONE state presents combined curator+auditor summary, PM explicitly chooses MERGE/FIX/ABORT before code reaches main
- **Parallel Curator+Auditor** — Both dispatch simultaneously in DONE state, reducing post-completion wait time
- **Auditor Auto-Fix** — S and M effort recommendations trigger gate-fixer dispatch pre-merge via new `recommended_fixes` output field
- **70/30 Design Principle** — Documented deterministic-first philosophy in pipeline §1: 70% bash, 30% LLM
- **Review Pre-Filter** — Bash regex checks (secrets, SQL injection, eval, debug) run before CP2/CP3/CP6 verifier dispatch, skipping LLM when unnecessary
- **Per-Escalation Templates (E1-E8)** — Each trigger shows specific context, findings, affected files, and available commands

### Changed
- **DONE State Flow** — Merge moved from step 3 to step 13 (after PM approval); prevents premature merge before review
- **Curator Auto-Evaluation** — Tier 2 default: M-effort proposals now auto-approved (was: deferred to PM)
- **PM Interaction Points** — Enhanced output at READY (gate details), CP1 (severity summary + 3 options), CP6 (evidence paths), scope warnings (actionable commands), and ESCALATION (per-type context blocks)
- **Auditor Dispatch Timing** — Now dispatched pre-merge in parallel with Curator (was: post-merge sequential)

## [2.3.0] — 2026-03-12

### Added
- **Review Checkpoints (CP1-CP6)** — Automatic verifier dispatch at 6 pipeline milestones: post-brainstorm plan review, per-step code review, pre-GATES integration review, curator proposal validation, auditor critical-finding gate, and post-/aid-do quick review
- **Fix Loop Protocol** — Verifier findings with Critical/High severity trigger gate-fixer dispatch + re-verification (max 2 iterations), replacing reactive gate-failure-only fixes
- **Critical Finding Gate (CP5)** — Auditor critical findings now block DONE state, triggering ESCALATION instead of proceeding to queue
- **Review Checkpoint Configuration** — New `review-checkpoints.yaml` policy file with per-checkpoint toggles, fix-loop settings, and trivial-skip threshold
- **Escalation triggers E7, E8** — Verifier review failure after fix loop; auditor critical security finding
- **Pipeline §13** — New Review Checkpoint Protocol section as authoritative reference

### Changed
- **Verifier agent** — Expanded from on-demand to automatic dispatch with fix-loop integration and checkpoint-specific context assembly
- **Gate-fixer agent** — Now accepts verifier review findings as input (source: `verifier_review`), not just gate failures
- **Auditor agent** — Critical findings produce `blocking_findings` flag that blocks DONE transition
- **Pipeline §4-§8** — Updated with review checkpoint dispatch points at EXECUTE, GATES, DONE, and FAST MODE

### Fixed
- **Broken cross-references** — Fixed 5 stale v2 migration references: auditor.md, gate-fixer.md, curator.md, planner.md pointed to non-existent `epic-orchestration.md`/`retry-engine.md`; pipeline.md referenced non-existent `dispatch-config.yaml`

## [2.2.0] — 2026-03-11

### Added
- **Context Persistence (Interim Document)** — `/aid-plan` now creates `.aid-o/work/interim-P{NNN}.md` at session start, updated after each step with full conversation detail; survives context window overflow and session interruptions; auto-deleted on plan completion
- **Concurrent brainstorm detection** — checks for existing interim docs before starting new brainstorm, offers resume or fresh start
- **ID Allocation Procedure** — documented read-increment-write protocol for counter.yaml in run-management ID System section

### Fixed
- **Dead `epic-orchestration.md` references** — updated brainstorming.md, plan-writing.md, and run-management.md to reference run-management ID System instead
- **Abort text accuracy** — "no files created" corrected to "no plan written, interim doc preserved"
- **plan-writing.md missing interim cleanup** — added MUST rule 15 to delete interim doc after successful plan write

## [2.1.1] — 2026-03-10

### Fixed
- **`.gitignore` missing from `/aid-init`** — Init now creates `.gitignore` appended to project root, ignoring runtime artifacts (evidence, quick logs, timeline.jsonl, queue.yaml) while keeping design artifacts versioned
- **Defaults `.gitignore` outdated** — Updated from v1 paths (`.aid-o/04-engine/`) to v2 structure

## [2.1.0] — 2026-03-10

### Changed
- **Brainstorming skill refactored** — 34% smaller (415→272 lines) with 8 new capabilities: scope decomposition, MoSCoW prioritization, risk assessment protocol, prior-plan lookup, pre-decided solution handling, context-loss recovery, workflow/AI questioning hint, Docker Compose recommendation
- **Design section templates extracted** — Moved to `defaults/templates/design-sections.md` as standalone reference, reducing brainstorming skill size while preserving all templates

### Removed
- **Obsolete planning docs** — Removed CRITICAL-ASSESSMENT.md and REDESIGN-PLAN-v2.md (completed, no longer relevant)

## [2.0.0] — 2026-03-03

### Breaking Changes
- **11-state LLM FSM → 6-state bash FSM** — States reduced from IDLE/PLANNING/PLAN_REVIEW/EXECUTING/PHASE_CHECK/NEXT_PHASE/GATES/GATE_RETRY/ESCALATION/CURATOR_RESOLVE/PM_APPROVAL/DONE to READY/EXECUTE/GATES/ESCALATION/DONE/ERROR. State transitions enforced by `aid-fsm.sh`, not LLM instructions.
- **27 skills → 8 skills** — Consolidated from 27 cross-referencing skills to 8 focused skills (agent-protocol, pipeline, planner, brainstorming, quality-gates, run-management, memory, role-cards). Removed: epic-orchestration, dispatch-protocol, gates-engine, retry-engine, first-aid-controller, auto-escalation, auto-done-state, parallel-dispatch, cost-optimization, epic-queue, slack-mcp, workflow-intelligence, and 15 others.
- **18 agents → 7 agents** — Consolidated from 18 role-based agents to 7 controller agents (implementer, verifier, gate-fixer, curator, auditor, project-scanner, run-validator). Removed: architect, backend, frontend, domain, qa, security, observability, docs-writer, release, code-reviewer, docs-reviewer, lessons-extractor, quality-gates-runner.
- **17 commands → 8 commands** — New unified commands: `/aid-do`, `/aid-plan`, `/aid-run`, `/aid-status`, `/aid-help`, `/aid-init`, `/aid-audit`, `/aid-stop`. Removed: `/aid-brainstorm`, `/aid-plan-epic`, `/aid-run-epic`, `/aid-first-aid`, `/aid-setup`, `/aid-epic-queue`, `/aid-epic-status`, `/aid-research`, and 9 others.
- **Directory structure** — `.aid-o/04-engine/` → `.aid-o/work/`, `.aid-o/02-epics/` → `.aid-o/tasks/`, `.aid-o/03-config/` → `.aid-o/config/`. Init creates 10 files (down from 40+).
- **10 policy YAMLs → 3** — `execution.yaml` (gates + dispatch), `project.yaml` (stack + preferences), `permissions.yaml` (agent permissions). Removed: decision-policies.yaml, dispatch-strategy.yaml, gates.yaml, memory-config.yaml, slack-config.yaml, and 5 others.

### Added
- **Fast Mode (`/aid-do`)** — < 2 min overhead for tasks < 2h. Creates Q-NNN.md quick log, skips full EPIC pipeline. Automatic scope detection.
- **Bash FSM (`aid-fsm.sh`)** — Deterministic 6-state finite state machine. States: READY → EXECUTE → GATES → DONE (happy path), with ESCALATION and ERROR branches. All transitions validated in bash, not LLM.
- **Bash gate runner (`aid-run-gates.sh`)** — Deterministic quality gate execution with JSON output, timeout handling, retry logic. Replaces LLM-manual gate evaluation.
- **Pipeline automation scripts** — `aid-auto-pipeline.sh` (orchestrator), `aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`. All deterministic operations moved from LLM to bash.
- **Stage logging (`aid-stage-log.sh`)** — Structured timeline.jsonl event logging with standardized format across all pipeline operations.
- **Token estimator (`aid-token-count.sh`)** — Character-based token estimation for prose/code/mixed content types.
- **`@aid/contract` package** — Shared TypeScript types for all `.aid-o/` data formats (AidFsmState, AidState, AidGatesReport, AidTimeline, etc.).
- **Progressive help (`/aid-help`)** — 4-level disclosure: Level 0 (cheat sheet), Level 1 (command detail), Level 2 (architecture), Level 3 (troubleshooting).
- **Scope check gate** — `scripts/gates/scope-check.sh` verifies implementation stays within EPIC-defined file scope.
- **173 tests across 13 suites** — Up from 88 tests / 6 suites in v1.7.0. Full coverage of FSM, gates, pipeline, stage logging, token counting, scope checking.

### Changed
- **~87% token reduction** — Plugin prompt tokens reduced from ~400K to ~50K by consolidating skills/agents/commands and moving deterministic logic to bash scripts.
- **`/aid-plan` merges 3 old commands** — Replaces `/aid-brainstorm` + `/aid-write-plan` + `/aid-plan-epic` into single progressive workflow.
- **`/aid-run` merges 2 old commands** — Replaces `/aid-run-epic` + `/aid-first-aid` with unified command supporting `--auto` flag.
- **`/aid-status` merges 2 old commands** — Replaces `/aid-epic-status` + `/aid-epic-queue` with combined view.
- **`/aid-init` merges `/aid-setup`** — Single idempotent init command creating 10-file `.aid-o/` structure with stack auto-detection.
- **Role cards consolidated** — All agent role definitions in single `role-cards.md` (8 roles + 4 focus cards) instead of 18 separate agent files.
- **Pipeline skill consolidated** — Single `pipeline.md` replaces 14 old orchestration skills, documenting all 6 FSM states.
- **Evidence paths** — `stage_log.jsonl` → `timeline.jsonl`, `plan_progress.json` → `state.yaml`.
- **aid-server paths** — Updated all Express routes and WebSocket handlers for v2 `.aid-o/` structure.

## [1.7.0] — 2026-02-28

### Added
- **Path Traversal Guards** — defense-in-depth (regex + resolve+startsWith) path validation on pipeline theater, evidence, and decision routes preventing CWE-22 filesystem traversal via `epicId`/`runId` parameters
- **GUI CORS Middleware** — `cors()` middleware on the aid-gui Express server with `AID_GUI_CORS_ORIGINS` env var support, defaulting to localhost:5173 and localhost:3000
- **Agent Name Frontmatter** — all 18 agent files now have `name:` field in YAML frontmatter matching the filename stem, enabling plugin validation
- **Master Test Runner** — `run-all-tests.sh` discovers and executes all test suites with unified pass/fail reporting (88 tests across 6 suites)
- **Curator Dispatch Regression Tests** — Suite F (5 tests) verifying unconditional Curator dispatch and state-entry logging in gate-evaluation.md and first-aid-controller.md
- **Phase Marker Documentation** — `plan-writing.md` Phase Markers subsection with exact format, rules, regex, and "do NOT use" examples for LLM-generated plans
- **PARALLEL_EXECUTING Sub-State** — `epic-state-machine.md` documents the FIRST AID parallel execution sub-state with activation criteria and safety limits
- **AI Companion Project Context** — system prompt auto-built from CLAUDE.md, package.json, pipeline state, EPIC queue, plans, decisions, ideas backlog, and project structure on every message
- **AI Companion Tool Use** — 7 tools (readFile, listDirectory, searchContent, readYaml, readEpic, readPlan, getPipelineState) giving the companion full codebase access with sandboxed paths and 8-step tool call limit
- **Voice Dictation Recording Bar** — waveform visualization via AudioContext AnalyserNode, elapsed timer, live interim text display (Web Speech API), and one-click stop-and-send flow
- **Whisper Auto-Detection** — background probe on mount detects Whisper availability; uses Web Speech API as primary (Czech `cs-CZ` support) with Whisper upgrade when OPENAI_API_KEY is set
- **FIRST AID Wrapper State Mapping** — FIRST_AID_INIT, QUEUE_PROCESSING, QUEUE_ADVANCE, FIRST_AID_COMPLETE mapped to medical labels (Triage, Operating, Next Patient, All Clear) with FSM colors and active state detection
- **Satellite Card Alternation** — Ward, Lab, Escalations, Vitals cards alternate between current and total values every 4 seconds with AnimatePresence transitions

### Changed
- **CORS Wildcard Handling** — `AID_CORS_ORIGINS=*` now correctly enables wildcard CORS instead of creating a single-element array `['*']`
- **Default Server Binding** — both aid-server and aid-gui default to `127.0.0.1` (loopback only) instead of `0.0.0.0`, preventing unintentional network exposure; Docker containers retain `0.0.0.0` via explicit env var
- **GUI README Replaced** — removed Gemini/AI Studio boilerplate, replaced with accurate AID Dashboard GUI documentation including local setup and aid-server dependency
- **Root README Version** — updated from v1.5.0 to v1.6.0
- **Brainstorming Step Count Standardized** — all documentation (README, Docusaurus, aid-help) now references 8-step brainstorming matching the actual skill lifecycle
- **aid-run-epic Prerequisites** — removed false auto-generation claim; `plan.json` must pre-exist via `/aid-plan-epic`
- **Zombie Backlog Cleanup** — moved 7 already-fixed entries (IMP-010/035/049/050/057/059/067) from Active to Implemented, correcting count from 62 to 55
- **EPIC ID Regex Hardened** — `aid-auto-pipeline.sh` now accepts alphanumeric plan IDs with internal hyphens (e.g., `E-TEST-001-1_2`)
- **Dependency Parser Enhanced** — `aid-plan-to-epic.sh` supports range expansion (`Steps 3-7`), trailing text stripping, cross-phase dependency filtering, and deduplication
- **Scope Generation Granularity** — `aid-plan-to-epic.sh` generates file-level paths in EPIC scope when plan steps have `**Files:**` sections, improving FIRST AID parallel detection accuracy
- **EPIC Template Scope Guidance** — template includes guidance comments encouraging file-level path declarations over broad directories
- **Curator Dispatch Made Unconditional** — `gate-evaluation.md` and `first-aid-controller.md` now mandate Curator dispatch at CURATOR_RESOLVE regardless of discovered_issues
- **QUEUE_PROCESSING Auto-Mode** — `first-aid-controller.md` includes parallel dispatch checklist cross-referencing `aid-first-aid.md` sections 3.1-3.5
- **Curator Auto-Defer Threshold Raised** — auto-mode now defers only effort:L proposals to backlog; effort:S and effort:M are fixed inline, increasing autonomous fix rate
- **Command Center State Labels** — all FSM states renamed to medical/hospital theme (On Call, Diagnosis, Prescription, Infusing, Vital Signs, Second Opinion, Lab Results, Doctor's Orders, Recovery, Discharged, Code Red)
- **Satellite Cards Data Sources** — Ward shows queue running+waiting / completed+failed; Lab shows gate runs+retries / audit score; Escalations shows budget usage / total escalations; Vitals shows steps executed / total events
- **EPIC Runs Display** — shows last 5 completed (most recent first) instead of first 5
- **Voice Flow Simplified** — removed confirm step; recording stops and sends directly (one action instead of three)
- **CommandPalette Voice** — transcript sends as message directly instead of inserting into filter input
- **Companion Open Speed** — status and sessions pre-fetched on project select; palette/panel opens instantly without network delay
- **Pipeline API Extended** — `/pipeline` endpoint returns full autoModeSession with escalation budget/count and aggregate counters (epicsCompleted, epicsFailed, totalStepsExecuted, totalGateRuns, totalGateRetries, totalEscalations)

### Fixed
- **WebSocket Replay Parsing** — `dispatchReplay()` now reads raw stage log entries directly instead of expecting non-existent `.entry` wrapper, fixing Pipeline Theater replay after reconnection
- **CSS Custom Property Generation** — `.replaceAll('_', '-')` replaces all underscores in FSM state names for correct CSS variable references (was `.replace` which only fixed the first)
- **Curator Input File References** — corrected from `step_output.json` to `output.md` + `diff.patch` matching actual agent output format
- **Queue Field Name** — `scripts/README.md` corrected `queued_at` to `added_at` matching actual queue schema
- **Queue Field Name Mismatch** — server returned `data.entries` but GUI expected `data.queue`, causing queue entries, elapsed time, and EPIC runs to never display
- **Topbar Voice Integration** — replaced inline mic recording logic (~90 lines) with shared VoiceButton component using `compact` prop

## [1.6.0] — 2026-02-28

### Added
- **Pipeline Scripts** — 5 bash scripts (`aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`, `aid-auto-pipeline.sh`) for deterministic Plan→EPIC→json→run→queue conversion replacing LLM-driven operations
- **Shared Script Library** — `scripts/lib/common.sh` with 7 portable bash functions (YAML parsing, section extraction, slugify, prerequisites check, error formatting, timestamps)
- **Script Documentation** — `scripts/README.md` with full interface contracts, argument tables, exit codes, data flow diagram, and JSON manifest schema for all 5 pipeline scripts
- **EPIC Template Dependencies Section** — structured Dependencies section with Internal/External/Queue subsections replacing flat placeholder
- **Deterministic Work Detection Audit** — new audit category I) scanning commands, skills, and agents for LLM-performed template filling, structured parsing, and file manipulation that could be replaced by scripts, with false positive filters and -10 cap scoring
- **Pipeline Test Suite** — 76 tests across 6 test scripts (40 unit, 16 integration, 20 regression) with 3 fixture plan files covering single-phase, multi-phase, and cross-plan dependency scenarios

### Changed
- **aid-plan-epic Command** — rewritten from 544-line LLM-driven flow to 235-line script-orchestrated 6-step flow delegating deterministic work to `aid-auto-pipeline.sh`
- **aid-run-epic Command** — inline plan generation removed; `plan.json` must pre-exist (created via `/aid-plan-epic`) with clear error message and actionable suggestion when missing
- **Documentation Consistency Pass** — 10+ skill/command files updated to reference script-based pipeline, removing references to inline plan generation

## [1.5.0] — 2026-02-28

### Added
- **Token Estimation Protocol** — new `skills/token-estimator.md` defining character-based heuristic for dispatch token counting with cl100k_base approximation and calibration process
- **Dispatch Configuration** — new `defaults/policies/dispatch-config.yaml` with 18 role-to-model tier mappings (3 opus, 11 sonnet, 4 haiku), per-tier context defaults, and advisory budget alerts
- **Plan Schema Extension** — `model` (enum: haiku/sonnet/opus) and `context_scope` (knowledge, memory, previous_outputs) optional fields per step in `plan.schema.json`
- **Planner Model Assignment** — planner reads `dispatch-config.yaml` and populates `model` + `context_scope` per step with fallback to opus/all-context when config is absent
- **Dispatch Usage Logging** — pre-dispatch token estimation and post-dispatch `usage` object in stage_log.jsonl with model, tokens, duration, context sources, and budget alerts
- **Usage Aggregation** — DONE state aggregates all dispatch_complete entries into `usage_summary` in plan_progress.json with breakdowns by model, role, and step
- **Model Tiering in Dispatch** — `step.model` passed to Task tool with 3-level fallback chain (step.model → dispatch-config.yaml → opus default)
- **Selective Context Injection** — knowledge, memory, and previous outputs conditionally injected based on `step.context_scope` with full backward compatibility
- **Dispatch Prompt Trimming** — EPIC context reduced to one-line goal + step-level paths instead of full EPIC specification
- **Token Efficiency Audit** — new `/aid-audit efficiency` type with per-role baseline comparison and 2x alert threshold (advisory, 0% weight)

### Changed
- **Dispatch Protocol** — model parameter wired into Task tool calls, context injection is conditional, prompt uses trimmed EPIC context
- **Parallel Dispatch** — model tiering support with per-agent model resolution

## [1.4.0] — 2026-02-27

### Added
- **GUI Dashboard** — full-featured web dashboard (`aid-gui` package) with Express backend, WebSocket real-time updates, and React 19 + Zustand 5 frontend
- **Ideas-to-Execution Kanban** — drag-and-drop board tracking ideas through exploration → planned → running → done lifecycle with auto-status from linked plans/EPICs
- **AI Companion Chat** — SSE-streaming chat panel with markdown rendering, session management, voice input (Web Speech API), and contextual hint buttons
- **EPIC Lifecycle Manager** — GUI-driven EPIC listing with frontmatter parsing, run/schedule actions, queue integration, and status-sorted display
- **Evidence Vault** — full-text grep search across evidence files (200-result cap, binary detection), date-grouped collapsible sidebar, and markdown preview toggle with DOMPurify sanitization
- **Pipeline Theater SVG Timeline** — Gantt-like horizontal timeline with color-coded role bars (architect/backend/frontend/qa/docs/security), replay controls (0.5x–4x speed), EPIC/run selector, and live auto-scroll mode
- **Decision Hub Notifications** — Web Audio API sound alerts (440Hz sine, 3s debounce) and browser Notification API for background tabs, with Sidebar badge pulse animation
- **Evidence Search API** — `GET /evidence/search?q=&limit=` endpoint with case-insensitive text matching, path traversal protection, and binary file skipping
- **Pipeline Theater API** — `GET /pipeline/theater/:epicId/:runId` endpoint merging plan.json + plan_progress.json + stage_log.jsonl into combined theater data
- **Companion Backend** — session-store with JSON persistence, auto-detect LLM adapter (Claude/OpenAI/Ollama/stub), SSE streaming endpoint, voice transcription proxy
- **WebSocket Infrastructure** — topic-based pub/sub (pipeline, stage_log, decisions, queue) with heartbeat, auto-reconnect (exponential backoff), and replay on reconnect
- **Test Suite** — 1014 Vitest tests across 31 files covering server routes, parsers, WebSocket, store slices, and API client

### Changed
- **Project structure** — added `packages/aid-gui/` (frontend) and `packages/aid-server/` (backend) as monorepo packages alongside the plugin

## [1.3.1] — 2026-02-27

### Fixed
- **Curator evidence path** — `step_output.json` replaced with `output.md` so Curator can actually read agent improvement notes
- **FIRST AID skill reference** — `skills/first-aid-mode.md` corrected to `skills/first-aid-controller.md` in `/aid-help`
- **Czech preset descriptions** — translated to English in `permissions.yaml` (aspirin and steroids descriptions)
- **Stale epic-breakdown.md references** — 6 references across 5 files replaced with `epic.md` (the actual template)

## [1.3.0] — 2026-02-27

### Added
- **Queue dependency ordering** — `depends_on` field in queue schema with Kahn's algorithm cycle detection; `next()` computes READY/WAITING/BLOCKED eligibility per entry
- **INTERMEDIATE_GUARDRAIL** — 3-check auto-approval gate (all_steps_done, no_gate_failures, evidence_complete) for intermediate EPICs in FIRST AID mode
- **Queue write ownership** — CONFLICT_CHECK as Step 0 in add()/start()/complete() operations; single-writer constraint during FIRST AID via auto-mode flag file
- **Canonical EPIC ID format** — formal `E-{plan_id}-{phase}_{total}` specification with validation regex and cross-referenced documentation
- **Untrusted field list** — 10 untrusted and 6 trusted fields enumerated in dispatch-protocol with rationale for each classification
- **OVERLAP_CHECK algorithm** — concrete pseudocode for 3 cases (exact-exact, glob-exact, glob-glob) replacing vague prose in planner
- **R1 dependency classification** — DATA MODEL and API CONTRACT type definitions with 5-step determination algorithm replacing subjective criteria
- **plan_ref keyword matching** — 4-step algorithm with extract/score/stopping-rule/confidence-check replacing vague Strategy 3 description
- **Setup re-run detection** — `/aid-setup` detects existing workspace and offers 6-option section menu for selective reconfiguration
- **Release count verification** — RELEASE_CHECK_COUNTS ensures CLAUDE.md command/skill counts stay in sync during releases
- **DEFAULT_BASELINE** — threshold 50/100 applied when no prior audit report exists for PM_APPROVAL auditor trend check

### Changed
- **adapt_example()** — simplified from 7-step function (422 lines) to 3-step (83 lines): path substitution, tool reference update, validation
- **Credit exhaustion detection** — 5 hardcoded strings replaced with 6 case-insensitive regex patterns and short-circuit evaluation

### Fixed
- **Escalation snapshot** — now correctly writes to `interrupted_step_context.json` instead of inconsistent field names

### Removed
- **`--dry-run` flag** — removed from `/aid-first-aid` command; deferred to backlog as standalone feature

## [1.2.0] — 2026-02-27

### Removed
- **Permission Sandwich** — removed `skills/permission-sandwich.md` (750 lines) and `defaults/policies/permissions-auto.yaml` (164 lines); FIRST AID no longer backs up, elevates, or restores permissions — requires Steroids 💉 preset instead

### Changed
- **Permission presets** — Safe removed, Recommended renamed to Aspirin 💊, Advanced renamed to Steroids 💉; two-preset system with deny-list protection
- **FIRST AID startup** — permission sandwich steps (backup, elevate) replaced by single Steroids preset verification check
- **FIRST AID completion** — permission restore removed; /aid-stop simplified to 3 steps (mode flag, wait, save progress)

### Fixed
- **Plan archival** — QUEUE_ADVANCE now uses queue as ground truth for plan archival instead of filesystem scanning; DONE state no longer attempts archival (single source)
- **Version bump detection** — uses plan-level completion (`plan_epics_total`) instead of queue position; solo plans always bump, multi-EPIC plans bump on last EPIC
- **Release sub-phase** — DONE state now explicitly calls RELEASE_SUB_PHASE with mandatory stage_log entry; skipping is no longer possible without audit trail
- **Queue removal** — `/epic-queue remove` sets status "removed" (not "completed"); context boundary tracking distinguishes session total from actually-executed EPICs

## [1.1.0] — 2026-02-27

### Added

- **Plan-Writing Skill** — new `skills/plan-writing.md` with two modes: Mode A (post-brainstorming) and Mode B (standalone `/aid-write-plan`); includes Forbidden Phrase Detection hard gate, Traceability Verification, 16-point Completeness Gate, and Post-Write Handoff offering EPIC creation
- **`/aid-write-plan` Command** — standalone plan writing command that delegates to the plan-writing skill; accepts topic argument or interactive input
- **Brainstorming Critical Rules Block** — 11 critical rules at the top of `aid-brainstorm.md` with primacy effect positioning to prevent instruction drift
- **Brainstorming Step Self-Checks** — each of the 8 brainstorming steps now has a mandatory self-check checklist (2-4 items) that must pass before transitioning to the next step
- **Brainstorming Progress Tracker** — mandatory `=== Step N/8: {Name} ===` output at the start of every brainstorming step for checkpoint enforcement
- **Brainstorming Approach Hard Gate** — RULE 9 enforces minimum 2 approaches before presenting to PM; RULE 10 prevents skipping approach exploration even for "obvious" topics
- **Brainstorming Completeness Gate** — Step 8 now enumerates all PM answers from Steps 3-6 and verifies each appears in the plan document before finalizing
- **adapt_example() Implementation** — 7-step function in knowledge-acquisition.md replaces path placeholders, updates framework versions, handles Docker sections, aligns platforms, merges constraints, adjusts step count, and writes adapted EPIC
- **Knowledge Results Display** — brainstorming Step 1 now shows PM what knowledge was found ("Found N relevant docs: [names]") or "No knowledge indexed yet"
- **`/aid-help knowledge` Topic** — lists all example EPICs by category, explains search flow (Context7 → Qdrant → static), and documents indexing and research triggers
- **RESUME_SESSION safety net** — QUEUE_PROCESSING next() now filters on `status in ["queued", "running"]` with preference for running entries, so an interrupted EPIC is automatically resumed even when the RESUME_SESSION reset was skipped
- **Permission snapshot and restore** — `auto-mode-state.yaml` gains an `original_permissions_snapshot` field; RESTORE_PERMISSIONS now uses a two-tier fallback (backup file, then inline snapshot) across all three restore paths (COMPLETE, /aid-stop, crash recovery)
- **Permission grant log** — `auto-mode-state.yaml` gains a `permissions.grant_log[]` audit trail field recording each dynamic permission grant with permission, source, actor, step_ref, timestamp, and reason; PHASE_CHECK permission learning dual-writes to both `learned_permissions[]` and `grant_log[]`
- **Multi-agent parallel execution** — QUEUE_PROCESSING gains a complete parallel dispatch protocol: independence detection via EPIC scope analysis, Task agent dispatch in worktree isolation, sequential merge with shared escalation budget, failure isolation per agent, and a safety cap of 3 concurrent agents
- **Untrusted content tags in dispatch templates** — all 10 user-supplied interpolation points in `aid-run-epic.md` dispatch prompts are wrapped in `<untrusted_content>` tags with source attributes; safety preamble added to both base and re-dispatch templates to prevent prompt injection
- **Hardened deny-list entries** — `Bash(rm -fr:*)` (reversed short flags) and `Bash(dd if=/dev/urandom:*)` added to the hard-deny list in `permission-sandwich.md` and `permissions-auto.yaml` with inline rationale comments and updated Section 3.4 rationale table
- **Planner parallelism rules** — 5 named Parallel Group Assignment Rules added to `planner.md`; backend and frontend agents can now parallelize after architect+domain steps when file scopes do not overlap; includes OVERLAP_CHECK algorithm and 3 worked examples
- **Planner granularity heuristics** — HEURISTIC G1 (Layer Splitting) and G2 (Module Splitting) added to `planner.md` Section 2b with before/after examples and interaction rules; steps spanning 3+ layers or 3+ modules are automatically split
- **Audit instruction quality checks** — Section G added to `auditor.md` with 5 checks for instruction file quality (intro presence, TODO/FIXME scan, frontmatter, cross-reference accuracy, files exceeding 800 lines); weighted at 10% and conditional on `plugins/aid-orchestrator/` existing

### Changed

- **Brainstorming modular split** — 1371-line `brainstorming.md` split into core (569 lines) + two sub-skills: `brainstorming-knowledge.md` (445 lines) for knowledge acquisition and file analysis, `brainstorming-workflow.md` (443 lines) for workflow detection and Docker/MCP rules
- **Brainstorming flow simplified** — reduced from 11 steps to 8 steps; EPIC creation removed from brainstorming entirely (now handled by `/aid-plan-epic` via plan-writing handoff)
- **Plan-writing delegation** — brainstorming Step 8 now delegates to `skills/plan-writing.md` instead of writing the plan inline; plan-writing skill handles quality gates, forbidden phrase detection, and completeness verification
- **FIRST AID disclaimer** — reframed from alarmist "USE AT YOUR OWN RISK" to "Experimental Autonomous Mode"; added explicit `/aid-stop` emergency stop reference and `/aid-epic-queue` for queue review so users know how to intervene safely
- **Setup MCP advanced permissions preset** — replaced the broad `mcp__*` wildcard with 7 explicit tool patterns (`mcp__shared-github__*(*)`, etc.) matching auto-mode format; updated setup wizard comparison matrix to reflect the change
- **Epic orchestration skill split** — 2300-line `epic-orchestration.md` split into 5 modular files: slim orchestrator (138 lines), `epic-state-machine.md` (602), `dispatch-protocol.md` (498), `gate-evaluation.md` (509), and `first-aid-controller.md` (577); pure refactoring with no logic changes
- **PLAN_REVIEW template enriched** — per-step detail table added to PLAN_REVIEW state with 7 columns (Files, Tech, AC count, Output, Deps) and 6 enforcement rules so plan review captures the full structure of each step
- **DONE state release logic consolidated** — release behavior now exists in exactly one place (`auto-done-state.md`); `first-aid-controller.md` DONE state delegates to `auto-done-state.md` for all release steps, eliminating duplication

## [1.0.0] — 2026-02-26

### Added

- **GitHub MCP in Setup Wizard** — `/aid-setup` now includes GitHub MCP as recommended option 6e with full setup flow covering detection, auth check, install, verification, and troubleshooting
- **Setup Completion Banner** — `/aid-setup` displays a professional styled ASCII art banner with AID branding after successful setup completion
- **Version Pre-check in Plan Epic** — `/aid-plan-epic` Step 0 reads the local plugin version, compares it with the latest GitHub release via `gh api`, and warns if outdated (non-blocking)
- **Help Workflow Examples** — `/aid-help examples` returns three step-by-step workflows: Greenfield Feature, Quick Fix, and Multi-Phase with FIRST AID
- **Autonomous Mode Commands in Help** — `/aid-help commands` now includes detailed entries for `/aid-first-aid` and `/aid-stop` under a new AUTONOMOUS MODE COMMANDS section

### Changed

- **Setup MCP Options** — re-lettered MCP sub-options so GitHub MCP is 6e, Auto-detect is 6f, and Custom is 6g; restructured Step 5b as Optional MCP Follow-up
- **Skill Count** — updated documented skills count from 20 to 21 in CLAUDE.md and README to include the previously unlisted `workflow-intelligence.md`

### Fixed

- **Stale Paths** — replaced three remaining `workspace/workflow/` references with `.aid-o/` equivalents in `planner.md`, `aid-plan-epic.md`, and `slack-mcp.md`
- **README Version** — synced README version from stale 0.9.2 to 0.9.3 (now bumped to 1.0.0 with this release)
- **Command Frontmatter** — verified all 13 commands have `user_invocable: true`

## [0.99.0] — 2026-02-26

### Added

- **AID Server** (`packages/aid-server`) — Express + WebSocket backend serving the AID GUI dashboard; 18 REST API endpoints covering projects, pipeline state, EPIC queue, decisions, evidence, audit, ideas, usage metrics, and knowledge; real-time WebSocket pub/sub with chokidar file watching on `.aid-o/`; topic-based subscriptions with heartbeat and idle timeout
- **Docker deployment** — multi-stage Dockerfile (gui-build → server-build → production) and docker-compose.yml; single `docker compose up --build` serves both GUI and API on port 3911; health check included
- **Docusaurus documentation site** — full docs site with architecture, configuration, contributing, troubleshooting, reference docs, and Getting Started guides; deployed to GitHub Pages via GitHub Actions; EN + CS locales
- **GUI frontend polish** — AI Companion panel, replay controls, error boundaries, production build optimization (FIRST AID EPIC session, 5 EPICs completed autonomously)

### Fixed

- **MDX expression errors** — escaped `{type: performance}` in `decision-policies.md` and `{message_type}`/`{action}` in `slack-integration.md` that broke Docusaurus MDX compilation
- **GitHub Pages config** — replaced all placeholder values in `docusaurus.config.ts` (`your-org` → `marekstancl`, `your-project` → `claude-aid-o`)
- **GUI Page Crashes** — added null guards to QueueScheduler, KnowledgeBase, and HealthObservatory to prevent TypeError crashes on empty data
- **WebSocket Connection** — connected useWebSocket hook in App.tsx so real-time events flow to all dashboard screens
- **CC Usage Gauge Visibility** — removed responsive hiding so CC Usage gauge is always visible in topbar, even when disconnected
- **Mobile Connection Banner** — removed `hidden md:flex` so connection status banner shows on mobile viewports
- **Project Selector Z-Index** — added z-50 to dropdown container so it renders above the sidebar overlay
- **Sidebar Responsive Collapse** — sidebar auto-collapses to icon mode on viewports below 768px with hamburger toggle and backdrop overlay
- **Pipeline Theater Empty State** — shows "No pipeline data" message instead of stale replay counter when no runs exist
- **SVG Path Animation Error** — suppressed motion.path rendering when no pipeline data is displayed, eliminating console errors
- **API JSON Fallback** — added /api/* catch-all route returning JSON 404 before static file fallback, preventing HTML responses for unknown API routes
- **Notification/Settings Buttons** — added "Coming soon" tooltips and safe click handlers to prevent crashes
- **Project Fetch Response Parsing** — fixed App.tsx legacy fetch that expected raw array but API returns `{ ok, data }` envelope, so currentProject was never set and WebSocket never connected
- **Health Observatory Audit Data** — fixed double-wrapping of audit reports array that caused latestAudit to be an array instead of an object, breaking score display
- **Health Check Route Collision** — moved Express health-check endpoint from `/health` to `/api/health` so the GUI's `/health` route (Health Observatory page) is served by the SPA fallback instead of returning raw JSON

### Changed

- **Default port** — server default port changed to 3911 (config.ts, Dockerfile, docker-compose.yml)
- **Version bump** — all packages bumped to 0.99.0 (aid-server, aid-gui, docs)

## [0.9.3] — 2026-02-25

### Fixed

- **GATES → CURATOR_RESOLVE transition** (`skills/epic-orchestration.md`) — GATES state now correctly transitions to CURATOR_RESOLVE instead of skipping directly to PM_APPROVAL; restores the full state machine flow (GATES → CURATOR_RESOLVE → PM_APPROVAL) so Curator proposals are processed for every EPIC
- **Qdrant config unification** — `memory-config.yaml` is now the single source of truth for `memory.enabled`; removed duplicate flag from `project-profile.yaml`; added non-blocking Qdrant startup probe in IDLE state for early availability detection

### Added

- **CURATOR_RESOLVE auto-mode conditionals** (`skills/epic-orchestration.md`) — in FIRST AID mode, effort:S proposals get inline fixes while effort:M/L are auto-deferred to backlog with urgency tags; failed inline fixes silently defer (non-blocking)
- **Credit exhaustion detection** (`skills/epic-orchestration.md`) — PHASE_CHECK now validates agent output before evaluation; detects 5 Claude Code credit error patterns via string matching; auto-pauses with `interrupted_step_context.json` + git stash; FIRST AID resume recovers interrupted steps
- **Wiring step generation** (`skills/planner.md`) — POST_WAVE_WIRING_CHECK detects shared files across parallel wave steps and auto-generates a wiring step with context (shared_files, contributing_steps, expected_actions); new `wiring` and `wiring_context` fields in `plan.schema.json`; EXECUTING state recognizes wiring steps with specialized dispatch prompt
- **EPIC & plan archival** (`skills/epic-orchestration.md`, `commands/aid-first-aid.md`) — DONE state archives completed EPICs to `02-epics/archive/`; QUEUE_ADVANCE archives plans when all plan EPICs complete; non-blocking with `mkdir -p` safety
- **FIRST AID ASCII art animations** (`commands/aid-first-aid.md`) — 4-frame syringe-themed startup animation, depleted-syringe completion banner with CURATOR FINDINGS summary, re-injection resume banner
- **CURATOR FINDINGS section** in FIRST AID completion report — shows implemented/deferred/rejected proposal breakdown with per-EPIC table

## [0.9.2] — 2026-02-24

### Added

- **FIRST AID Autonomous Mode** — `/aid-first-aid` starts autonomous EPIC queue execution with agent-driven quality checks replacing PM approval points; `/aid-stop` disengages immediately, restoring manual mode at the current natural pause point
- **Permission Sandwich** (`skills/permission-sandwich.md`) — automatic permission backup, elevation, and restoration for autonomous execution with crash recovery and permission learning; permissions are scoped to the auto-mode session and restored unconditionally on exit
- **Auto-Mode Escalation Protocol** (`skills/auto-escalation.md`) — 16 trigger conditions with severity classification, pause/resume flow, escalation budget tracking (max 3 before mandatory PM review), and `continue-manual` handoff option
- **Auto-Mode DONE State** (`skills/auto-done-state.md`) — automatic release decisions (defer intermediate, mandatory bump on last EPIC), queue transitions, and cross-EPIC summary aggregation to `auto-mode-state.yaml`
- **FIRST AID command** (`commands/aid-first-aid.md`) — PM-facing command to activate autonomous mode: queue confirmation, permission elevation, and auto-mode-state initialization
- **Aid-Stop command** (`commands/aid-stop.md`) — immediate autonomous mode stop command; safe mid-EPIC stop after current step completes

### Changed

- **PLAN_REVIEW** (`skills/epic-orchestration.md` Section 3) — auto-mode: schema, completeness, dependency graph, and run file quality validation replace PM prompt; validation failure triggers ESCALATION; manual mode unchanged
- **PHASE_CHECK** (`skills/epic-orchestration.md` Section 5) — auto-mode: adds one "fresh approach" retry cycle after `max_review_fix_cycles` exhausted before escalating; manual mode unchanged
- **ESCALATION** (`skills/epic-orchestration.md` Section 9) — auto-mode: pauses mode, saves progress snapshot, increments escalation counter, presents extended PM options including `continue-manual`; manual mode unchanged
- **PM_APPROVAL** (`skills/epic-orchestration.md` Section 11) — auto-mode: intermediate EPICs auto-approved; last/standalone EPIC auto-approved only after 4 guardrails pass (gates, no critical issues, escalation budget, auditor trend); rule teaching suppressed in auto-mode; manual mode unchanged
- **DONE state** (`skills/epic-orchestration.md` Section 12) — auto-mode: intermediate EPIC version bump auto-deferred, last EPIC auto-bumped; queue transition loads next EPIC automatically; auto-mode exits and restores permissions when queue is exhausted; manual mode unchanged

## [0.9.1] — 2026-02-24

### Added

- **Initial Analysis Phase** (`skills/brainstorming.md`) — mandatory structured analysis before questioning; 8-rule protocol with 4 required elements (topic understanding, key dimensions, potential challenges, clarification preview); PM confirmation gate; trivial topic escape hatch
- **Release Sub-Phase** (`skills/epic-orchestration.md`) — version bump detection and execution in DONE state; reads `release-policy.yaml` for CHANGELOG pattern, version files, multi-phase deferral; supports `json_field` and `regex` update strategies, git tagging, GitHub releases
- **Release policy config** (`defaults/policies/release-policy.yaml`) — configurable versioning: CHANGELOG header pattern, version file locations, update methods, multi-phase plan detection, git tag and GitHub release controls

### Changed

- **Questioning Protocol strengthened** (`skills/brainstorming.md`) — Rule 2 upgraded from "Prefer MULTIPLE CHOICE" to "ALWAYS use MULTIPLE CHOICE with recommendation"; added Rules 10-11 for structured directional options and contrastive reasoning
- **MUST Rules expanded** (`skills/brainstorming.md`) — 3 new entries (15-17): mandatory analysis before questions, options at every decision point, reasoning for alternatives
- **Command flow updated** (`commands/aid-brainstorm.md`) — 10-step → 11-step flow; new Step 2 (Analysis) inserted between Context and Questions; all subsequent steps renumbered with cross-references updated
- **DONE state enhanced** (`commands/aid-run-epic.md`) — Release Sub-Phase integrated before branch merge; DONE action items reordered (run file update → release → merge → archive)

### Fixed

- **Example EPIC lookup type filter** (`skills/brainstorming.md`) — changed from `"example_epic"` to `"example"` to match actual frontmatter in 19 example files
- **Example EPIC lookup scan** (`skills/brainstorming.md`) — changed from flat `defaults/examples/` to recursive `defaults/examples/**/*.md` to find files in subdirectories

## [0.9.0] — 2026-02-24

### Added

- **Plan-ref injection** (`skills/epic-orchestration.md`) — dispatch template now includes `plan_ref` with Source Plan Integration protocol: 3-strategy matching cascade (keyword → heading → sequential), 3000-line truncation guard, `<plan_context>` block in agent prompts
- **Sequential ID generation** (`skills/epic-orchestration.md`) — ID Format Specification for Plans (`P{NNN}`), EPICs (`E-{NNN}-{epic_run}_{plan_step}`), and Runs (`R-{NNN}-{epic_run}_{plan_step}-{run_seq}`); Counter File protocol (`counter.yaml`); atomic increment rules
- **Evidence Incomplete detection** (`agents/auditor.md` section F.5) — `evidence_incomplete` finding type with `-3` deduction per missing mandatory file; only checks completed steps
- **Mandatory Evidence Write Checklist** (`skills/epic-orchestration.md`) — Step Evidence File Types table listing mandatory vs optional evidence files per step

### Changed

- **SESSION → RUN terminology** — renamed across 45+ files: `session` → `run`, `session-management.md` → `run-management.md`, `session-validator.md` → `run-validator.md`, 4 template files renamed; `sessions/` directory → `runs/`
- **Flat evidence structure** (`commands/aid-run-epic.md`, `skills/epic-orchestration.md`) — removed 5 empty subdirectory creation (analysis/, discovered_issues/, parallel_groups/, prompts/, reviews/); evidence now written directly to `steps/step_{N}_{role}/`
- **Budget references removed** — removed budget estimation lines from `defaults/templates/epic.md`, `defaults/templates/epic-example.md`, `skills/brainstorming.md`
- **Auditor check #12 path updated** (`agents/auditor.md`) — `evidence/discovered_issues/` → `steps/step_{N}_{role}/discovered_issues.md`
- **Analysis-merge evidence paths** (`skills/analysis-merge.md`) — `evidence/{epic_id}/{run_id}/analysis/` → `steps/step_{target}_{role}/`

## [0.8.2] — 2026-02-23

### Fixed

- **Czech-language content removed** — translated all Czech text to English in `agents/lessons-extractor.md`, `skills/session-management.md`, `skills/agent-core.md`
- **Broken skill reference in `aid-epic-queue.md`** — `skills/aid-epic-queue.md` → `skills/epic-queue.md`, `aid-epic-queue.yaml` → `epic-queue.yaml`
- **Stale `workspace/workflow/` paths** — 12 legacy path references replaced with `.aid-o/` equivalents in `skills/session-management.md`
- **Stale command prefixes** — `/run-epic` → `/aid-run-epic`, `/plan-epic` → `/aid-plan-epic` in `skills/retry-engine.md`, `skills/planner.md`, `defaults/templates/epic-example.md`
- **Version mismatches** — header/footer versions aligned to 0.8.2 in `session-management.md`, `epic-orchestration.md`, `retry-engine.md`, `planner.md`, `agent-core.md`
- **Hardcoded Slack channel ID** — replaced `C0AFP2GP459` with `YOUR_CHANNEL_ID` placeholder in `commands/aid-setup.md`
- **Plugin README version** — updated from 0.4.1 to 0.8.2

### Added

- **Untrusted-content framing** — SECURITY section in `skills/epic-orchestration.md` documenting mandatory `<untrusted_content>` tags for user-provided content in dispatch prompts (CWE-77, OWASP LLM01)
- **Advanced preset warning** — explicit risk documentation and PM confirmation requirement in `defaults/policies/permissions.yaml`

### Changed

- **CLAUDE.md structure info** — corrected command count (10 → 11) and skill count (14 → 17); removed stale `docs/` directory reference
- **CHANGELOG alignment** — root and plugin `[0.8.1]` entries made identical per CLAUDE.md policy

## [0.8.1] — 2026-02-23

### Added

- **Process Audit type** (`agents/auditor.md` section F) — 6th audit type, always runs, with 13 checks across 4 categories: F.1 EPIC Lifecycle (3 checks), F.2 Evidence Completeness (6 checks), F.3 Cross-Validation (3 checks), F.4 Stage Log Integrity (1 check); deduction-based scoring (0-100); `process: {0-100}` field added to YAML output; 15% weight in Overall score; Score Overview template updated with Process row

### Changed

- **Audit weight redistribution** (`agents/auditor.md` weight table) — Documentation 20% → 25%, Process 15% added; total always-run audit types: 3 → 4; audit type count: 5 → 6

## [0.8.0] — 2026-02-23

### Added

- **CURATOR_RESOLVE state** — new state between GATES and PM_APPROVAL in the epic-orchestration state machine; auto-evaluates Curator proposals via 3-tier algorithm (YAML rules → Qdrant history → default), dispatches fix agents, writes lessons with 3-layer dedup
- **`curator_auto_rules`** in `decision-policies.yaml` — configurable auto-resolution rules for improvement proposals
- **PM override + rule teaching** at PM_APPROVAL — PM can override rejected proposals and teach new auto-rules that persist via YAML + Qdrant
- **Improvement Pipeline analytics** — Report Type 4 in `/aid-analytics` for curator pipeline metrics
- **3-layer Lessons-Extractor dedup** — text, semantic, and Qdrant cross-project deduplication

### Changed

- **State machine**: 11 → 12 states (CURATOR_RESOLVE inserted)
- **DONE state simplified**: Curator + Lessons-Extractor moved to CURATOR_RESOLVE
- **`backlog.md`**: PROP-* IDs migrated to IMP-{NNN} with legacy alias table
- 9 files updated across agents, skills, commands, and policies

## [0.7.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.6.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.5.0] — 2026-02-22

### Added

**Phase 1 — Research + Storage + Consumption:**
- **Knowledge acquisition skill** — new `skills/knowledge-acquisition.md` with Research, Storage, and Consumption protocols; Context7 MCP as primary source, WebSearch fallback, dual storage (per-project YAML index + global Qdrant), 4-gate quality protocol
- **Context7 MCP in `/aid-setup`** — Option 6b for framework documentation via MCP; auto-detection, verification, troubleshooting guide
- **Docker MCP elevated to recommended** — Option 6d in `/aid-setup`; auto-detection of Dockerfile/docker-compose.yml, dedicated install section
- **Documentation type in memory-mcp** — Type 6 with full metadata schema and 4-gate Documentation Quality Gate Protocol
- **Knowledge-Augmented Brainstorming** — `brainstorming.md` Step 1 and Step 3 integration with `knowledge_find()`; non-blocking with 5s timeout, graceful degradation
- **KNOWLEDGE CONTEXT block in agent-core** — 3-section block (Framework Documentation, Patterns, Lessons) with type-specific staleness thresholds (90/180/365 days)
- **`knowledge-base.yaml` template** — per-project reference index for documentation sources
- **Knowledge config in `memory-config.yaml`** — `knowledge:` root-level section with research, quality, and context7 subsections

**Phase 2 — On-Demand Research + Aging:**
- **`/aid-research` command** — on-demand research for specific frameworks/libraries; `--deep` mode for comprehensive documentation ingestion
- **Aging protocol** — TTL-based freshness weighting for all document types (90–365 days); stale/expired score multipliers (0.7/0.3); automatic exclusion after 180 days past TTL
- **Manual source addition** — conversational flow for adding documentation sources via URL or topic
- **Freshness weighting in `memory_find()`** — search results weighted by document age; stale chunks deprioritized automatically
- **Aging config in `memory-config.yaml`** — per-type TTL values, stale/expired weights, exclusion threshold

**Phase 3 — Auto-Extraction + Community Examples + Feedback:**
- **Example EPIC extraction protocol** — 7-stage `extract_example_epic()` function: eligibility check → extract → abstract → build text → PM approval → dedup → Qdrant storage; triggered in DONE state step 9b
- **`example_epic` document type** — Type 8 in memory-mcp.md with 11 metadata fields (frameworks, archetype, source_epic_id, complexity, roles, etc.); never-expire TTL; global project scope
- **Community example EPICs** — 3 curated templates in `defaults/examples/`: `langchain-rag-chatbot.md`, `fastapi-crud-service.md`, `react-dashboard.md`; placeholder paths, version ranges, standard EPIC template format
- **Example EPIC lookup in brainstorming** — Step 3 searches `defaults/examples/` + Qdrant for matching archetypes; PM offered: (A) Adapt, (B) Browse all, (C) Start fresh
- **Feedback tracking** — fire-and-forget `track_retrieval()` after `memory_find()`; tracks `times_retrieved` and `avg_retrieval_score` per framework in `knowledge-base.yaml`; deprecation signal after 180 days of zero retrievals
- **Feedback config in `memory-config.yaml`** — `feedback:` section with `track_retrieval`, `track_usefulness`, `deprecate_unused_after_days`

### Changed
- **Command prefix standardization** — 5 commands renamed to `aid-*` prefix (`run-epic` → `aid-run-epic`, etc.) for discoverability; 9 unused command files removed; 20+ cross-references updated
- **`/aid-plan-epic` UX text** — updated intro and Step 9 output for unified Plan→EPIC→Plan flow
- **`/aid-help` command description** — updated `/aid-plan-epic` entry to "Unified Plan→EPIC→Plan entry point"
- **DONE state in `epic-orchestration.md`** — new step 9b triggers example extraction after Curator; completion summary includes archetype when pattern is stored
- **`memory-mcp.md` document types** — expanded from 6 to 8 types (added Proposal, Example EPIC); feedback tracking hook in `memory_find()`
- **`brainstorming.md` non-blocking guarantee** — knowledge calls updated from 2 to 3 per session (Step 1 search + Step 3 knowledge + Step 3 examples); 7 new graceful degradation scenarios

## [0.4.2] — 2026-02-21

### Changed
- **`/plan-epic` step numbering** — renumbered all steps from fractional (0.5, 0.7, 2.5) to clean integers (1-9); internal cross-references updated
- **`/aid-brainstorm` step numbering** — renumbered Step 8b→9 and Step 9→10; new Step 10 presents interactive A-D handoff options (add items, all-phases EPIC, specific-phase EPIC, manual)
- **Cross-references** — updated plan-epic step references in run-epic.md (3 occurrences) and epic-orchestration.md (2 occurrences); updated aid-brainstorm.md and brainstorming.md internal refs

### Added
- **`/aid-init [path]` parameter** — documented optional path parameter in aid-init.md Usage section with examples for relative and absolute paths; updated aid-help.md entry
- **Phase selection** — plan-epic.md Step 2 now handles all-phases vs specific-phase EPIC generation when invoked from brainstorming with phase context
- **Re-opening protocol** — brainstorming.md documents how Option A (add items) works: load existing plan, display approved sections, return to Step 2, re-generate EPIC
- **Phase Selection section** — brainstorming.md EPIC Subagent Prompt Template includes phase handling for scoped EPIC generation

## [0.4.1] — 2026-02-20

### Added
- **`/aid-init` upgrade mode** — detects existing workspace, compares installed vs. plugin version, classifies files as NEW / UPGRADABLE / UNCHANGED / CUSTOM / PROTECTED, asks PM before updating
- **Config manifest** — `.aid-o/03-config/.aid-manifest.yaml` tracks installed plugin version and md5 checksums of all config files; enables safe detection of PM customizations
- **Dynamic defaults scanning** — `/aid-init` scans `defaults/` directories instead of hardcoded file list; new files in future versions are automatically included
- **`source_plan` in plan schema** — `defaults/templates/plan.schema.json` now includes the `source_plan` field for Variant B pipeline

### Changed
- **CHANGELOG format** — standardized all entries to `**Bold Name** — description` format; root and plugin CHANGELOGs are now identical
- **CLAUDE.md release protocol** — added CHANGELOG format standard, README Roadmap update rules, and 10-step release workflow
- **`/aid-init` description** — updated in `aid-help.md` to reflect upgrade capabilities

## [0.4.0] — 2026-02-20

### Added
- **Zero Detail Loss Pipeline (Variant B)** — EPIC references source plan via `plan_ref`; all pipeline stages (plan.json, session, agent dispatch) read both EPIC and source plan; agents receive `## Source Plan — Implementation Detail` sections
- **Wave-based execution model** — planner groups steps by DAG level into waves (max 4 per wave) for parallel execution; replaces flat parallel group detection
- **Step decomposition** — layer-based splitting of monolithic steps (data → schema → API → test) to enable cross-domain parallelism; supports dev, docs, and infra decomposition types
- **Critical path analysis** — opt-in for 7+ step EPICs; computes critical path ratio, applies 5 relaxation rules (R1–R5) to shorten it; PM can reject individual relaxations at PLAN_REVIEW
- **Parallelism-first optimization** — 5-priority strategy (parallelism > wave density > session compactness > quality > efficiency); plan quality metrics in `optimization_metrics`; validation rules V-20–V-23
- **`/plan-epic` accepts Plan files** — 3-tier format detection (frontmatter → header → section fingerprinting); auto-generates EPIC from Plan using EPIC Subagent Template
- **`/aid-brainstorm` inline execution** — Step 8b offers to generate Plan JSON + Session immediately after EPIC draft; Step 9 split into 9a (standard handoff) / 9b (full pipeline handoff)
- **Wave-based session boundaries** — sessions are contiguous sequences of waves; never split by domain or inside a wave
- **Shorthand commands** — all 18 commands have `user_invocable: true` frontmatter enabling `/aid-setup` instead of `/aid-orchestrator:aid-setup`
- **Setup followup** — after "All recommended", `/aid-setup` now offers additional options (CLAUDE.md, Slack, auto-detected MCPs)
- **Selective `.aid-o/` gitignore** — plans, EPICs, and config are versioned; engine artifacts (sessions, evidence) are ignored
- **Centralized Qdrant storage** — `~/.local/share/aid-orchestrator/qdrant-data` with `--scope user` for global MCP; migration check for old paths

### Changed
- **EPIC template** — typed artifacts (`endpoint:`, `model:`, `component:`), `plan_ref` enforcement, Hints section, Scope with specific file paths
- **EPIC Subagent Template** — frontmatter instructions, plan task ID preservation in steps, Variant B zero detail loss instruction
- **Planner input validation** — REQUIRED/RECOMMENDED checks with typed artifact inference
- **PLAN_REVIEW** — rich plan summary with wave execution plan, optimization metrics, session breakdown
- **EXECUTING state** — agent dispatch enriched with source plan sections
- **Plan generation flow** — 13-step procedure with decomposition (2.2), wave assembly (6), CPA (6.1), session boundaries (11)

## [0.3.0] — 2026-02-19

### Added
- **Execution Summary block** — mandatory in all agent outputs with timing, self-assessment, and Qdrant storage
- **Per-agent metrics** — step duration, complexity self-report, bottleneck flags stored to Qdrant
- **Cost optimization skill** — 4 axes: model selection, file scoping, dispatch prompt trimming, token tracking
- **EPIC completion summary** — 5 next-step options presented to PM at DONE state
- **Auto-archive** — multi-EPIC and multi-session counter awareness for session and EPIC files
- **Multi-session flow** — planner optimization engine for EPICs with 7+ steps
- **Diff patches** — `diff.patch` generation for every file-modifying step, saved to evidence store
- **Curator auto-invocation** — mandatory synchronous step in POST_PROCESSING
- **Chat-first `/aid-setup`** — detailed option presentation and guided configuration
- **Post-setup guidance** — `/aid-brainstorm` recommendation after onboarding
- **Playwright E2E agent** — optional parallel step, auto-added when frontend detected
- **Application type classification** — 11 types in project scanner (web-app, api-service, cli-tool, desktop-app, mobile-app, library, plugin, script, monorepo, erp-module, infrastructure)
- **Auto-scaffold** — generates starter files for uninitialized projects before EPIC execution
- **Cross-project knowledge** — Qdrant with `project_name` metadata tagging for multi-project memory
- **Backlog categorization** — by type (bug, enhancement, tech-debt, security, docs) and source agent
- **`/aid-analytics`** — orchestration performance analysis command and skill
- **Permission presets** — dual-write system keeping `.claude/settings.json` + `.aid-o` policies in sync
- **Git branch integration** — one branch per EPIC session, auto-create and auto-merge
- **Pre-Output Quality Check** — in all code-producing playbooks (ruff lint/format, debug artifact removal, import verification)

### Fixed
- **DONE state** — now writes lessons to `lessons-learned.md`, updates session status to `completed`, writes commands to `command-history.md`, writes final `stage_log` entry with `result: success`
- **Gate reconciliation** — `plan.json` gates now reconciled with `gates.yaml` definitions
- **Qdrant isolation** — writes now include `project_name` metadata for cross-project isolation
- **Slack MCP** — onboarding corrected to use `@anthropic/slack-mcp` package with proper scopes

### Changed
- **Agent model assignments** — QA, Security, Docs agents use Sonnet; utility agents use Haiku
- **Dispatch prompts** — trimmed to deps-only context, EPIC summary, and playbook reference
- **`/aid-help` examples** — updated with full-stack development examples
- **Memory search** — `top_k` reduced from 5 to 3 for relevance and cost optimization
- **Git Discipline** — section added to all 9 role playbooks

## [0.2.0] — 2026-02-18

### Added
- **`/aid-brainstorm`** — 9-step interactive brainstorming flow (context → questions → approaches → design → sections → approval → document → EPIC draft → handoff)
- **Brainstorming skill** — process rules, key principles, EPIC subagent prompt template
- **MCP server onboarding** — Qdrant local (no Docker), Slack opt-in, auto-detect, custom
- **Permission presets** — Safe / Recommended / Advanced in `/aid-setup`
- **Document language** — `language.yaml` configuration with ISO 639-1, default EN
- **Parallel isolation strategy** — `dispatch-strategy.yaml` with worktrees / branches / sequential
- **Git worktree support** — creation and cleanup logic for parallel agent dispatch
- **Qdrant orchestration logging** — dispatch and completion events with graceful JSONL fallback
- **Enriched `final_report.md`** — generation from Qdrant data
- **Lessons learned** — auto-collection and storage in Qdrant at EPIC completion
- **CLAUDE.md marker merge** — `<!-- AID-O START/END -->` markers in `/aid-init`
- **Interactive examples** — `/aid-help examples` with 3 project prompts

### Changed
- **`/aid-setup`** — includes 4 new configuration steps (MCP, permissions, language, isolation)
- **`/aid-init`** — copies `dispatch-strategy.yaml` and `language.yaml` to workspace
- **LLM cost estimates** — conditioned on `billing_mode: api` (hidden for subscription users)

### Removed
- **`examples/bookmark-manager/`** — replaced by interactive `/aid-brainstorm` prompts

## [0.1.0] — 2026-02-16

### Added
- **Initial release** — Controller + Workers architecture for Claude Code
- **17 slash commands** — `/aid-init`, `/aid-setup`, `/run-epic`, `/plan-epic`, etc.
- **18 agents** — 9 role + 3 specialist + 6 utility
- **13 skills** — epic orchestration, planner, gates engine, parallel dispatch, etc.
- **11 role playbooks** — customizable per project
- **Quality gates** — auto-retry (3x) and PM escalation
- **Slack MCP integration** — with chat fallback
- **Qdrant vector memory** — optional, with file-based fallback
- **EPIC queue** — autonomous sequential execution
- **Evidence trail** — `stage_log.jsonl`, gate reports, agent outputs
## [2.46.0] — 2026-06-30

### Added
- **DG-15 Route Resolve** — Literal link vs declared route-files probe (react-router/express); opt-in via delivery-map.yaml routes section; config_missing when framework unsupported or map absent
- **DG-17 Independent Oracle No-Drop** — Analytics output cardinality vs declared baseline; requires analytics_output_file + expected_cardinality; missing file → config_missing, not fake pass
- **DG-18 Acceptance Provenance** — FSM step-verify evidence adapter; surfaces acceptance history into delivery-gate.json; never emits fail (provenance-only)
- **delivery-map.schema.json** — JSON Schema for delivery-map.yaml (meta/routes/oracle_baselines, all optional)
- **aid-delivery-map.sh** — Accessor library for delivery-map.yaml with pinned exit-code contract (null → exit 2)
- **map_section_globs + has_acceptance_evidence** — Two new dispatcher condition types in aid-delivery-gate.sh

### Changed
- **enforcement-registry.yaml** — Added DG-15/17/18 rows (surface: delivery-gate, observe, planned E10); totals.enforcements corrected to 258

## [2.44.1] — 2026-06-29

### Fixed
- **`aid-acceptance-evidence.sh` + `aid-consumption-proof.sh` protocol-v2 envelopes** — both scripts now emit full protocol-v2 envelope (`schema_version`, `identity`, `subject`, `revision`, `status`, `verdict`, `provenance`); `revision.head_sha` carries the full 40-char git SHA (was short SHA, broke `--current-head` validation)
- **`aid-acceptance-evidence.sh` step naming** — verifier evidence files looked up as `step-1.md` (1-indexed, no zero-padding) instead of `step-00.md`; `ac_id` suffix changed from `_00` to `_1`
- **`aid-consumption-proof.sh` false-verified** — Strategy 2 (filename pattern fallback: `*contract*`/`*binding*`) removed; only Strategy 1 (grep for binding_id) is valid
- **`consumption_proof` protocol-v2 type registration** — added to `aid-protocol-validate.sh` + fixtures (`valid.json`, `invalid-missing-payload.json`)
- **Enforcement registry planned rows** — `semantic_wiring_would_block`, `c2_acceptance_deviation`, `c2_consumption_unresolvable` now carry `status: planned`, `deadline/deferred_until/promotion_phase: E10`
- **FC-24..28 fingerprints** — `fc{NN}neg` contained non-hex chars; fixed to `fc{NN}000...` (64 valid hex chars)
- **Evidence pack regenerated at HEAD** — `delivery-gate.json`, `acceptance-evidence.json`, `consumption-proof.json` regenerated; all pass `aid-protocol-validate --current-head --check-fingerprint`

### Added
- **E5 wiring-gate bats test** — `E5 wiring-gate observe: Critical finding logged but increment proceeds`; seeds Critical finding in `semantic-review-wiring.json`, asserts exit 0 + `semantic_wiring_would_block` in `timeline.jsonl`
- **T8 fingerprint schema validation** — `test-semantic-review.sh` T8 verifies `sha256:[0-9a-f]{64}` format per FC fixture
- **T9 mutation-survives + low-profile-no-local** — merge count dedup + final-only dispatch-mode tests
- **T10 `--current-head` regression guard** — both `aid-acceptance-evidence.sh` and `aid-consumption-proof.sh` output verified against `aid-protocol-validate --current-head` in test harness

## [2.44.0] — 2026-06-29

### Added
- **C2 Semantic Review Engine (observe)** — 4-mode dual-emit engine (local/wiring/behavior/final) producing auditable `semantic-review-{mode}.json` alongside the existing `.md` gate (D1 unchanged); 12-lens catalog from failure-mode-control-matrix FC-09, FC-24..28, FC-30..32, FC-35; no-mega-prompt rule (D2); observe-only (E5), blocking deferred to E10
- **Wiring-gate observe** — `cmd_increment_step` logs `semantic_wiring_would_block` on unresolved Critical/High wiring findings; `SEMANTIC_REVIEW_POLICY=blocking` enables E10 blocking path without code change
- **`aid-finding-merge.sh`** — lossless fingerprint-keyed merge: severity=max, detail=union sorted, conflicts in `merge_meta`; deterministic output
- **`aid-acceptance-evidence.sh`** — reconstructs `acceptance-evidence.json` from plan.json AC + LLM coverage signals (`## AC Coverage` block); ac_id=sha256[:12]_step_idx; D3: bash aggregates, LLM determines coverage
- **`aid-consumption-proof.sh`** — verifies contract-manifest.json bindings against evidence_dir (grep+filename); fail-safe: missing manifest → `unresolvable` + exit 0
- **`review-profile-check.sh` E5** — `completed_lenses` read from `lenses_run[]` union across `semantic-review-{mode}.json`; E3 backward-compat: no C2 files → same `COMPLETED_LENSES=""` behavior
- **FC-24..28 negative fixtures** — 5 runnable JSON fixtures for transaction_boundary, field_lineage, negative_case, operation_order_resource_bound, requirement_test_drift failure modes
- **`test-semantic-review.sh`** — 8-test harness covering merge, acceptance-evidence, consumption-proof, review-profile-check (E5+E3 backward-compat), fixture validity
- **Enforcement registry** — 9 new C2 entries covering wiring-gate, dual-emit, lens catalog, acceptance-evidence, consumption-proof, completed_lenses, requirement-drift, finding-merge, semantic-review-policy
- **`docs/extending-aid.md`** — C2 extension guide: how to add lenses, dual-emit protocol, fingerprint format, policy promotion path

## [2.43.0] — 2026-06-28

### Added
- **C0 Plan Contract Gate** — observe-only gate layer running in `aid-auto-pipeline.sh` after plan-graph extraction, producing `plan-graph.json`, `contract-manifest.json`, and `plan-review.json` with 5 semantic lenses (observe, E10 promotion target)
- **Shared Kahn topo-sort lib** — `scripts/lib/aid-plan-graph.sh` with `build_plan_graph` function and deterministic `topological_order` output; `aid-epic-to-json.sh` refactored to use it
- **C0 QA harness** — `test-c0-contract.sh` with 66 assertions across 7 fixture sets (clean, cycle, dup-id, p045-style, per-lens, blocking-mode, clean-low-risk)

## [2.42.1] — 2026-06-28

### Added
- **E3 Adaptive Review Profile Detector** — deterministic, LLM-free resolver (`aid-prefilter.sh profile`) computes surface→lens matrix from plan-time + candidate-time git diff union; emits `review-profile.json` with `required_lenses`, `profile_hash`, `risk_profile`, and IR cadence; FSM observe hook logs `missing_lenses` telemetry without blocking (promotion to blocking in E10); 6 surfaces, 5 risk profiles, 13-scenario test harness.

## [2.41.2] — 2026-06-28

### Fixed
- **CI: dg07/dg12 bash-test failures** — delivery-gate fixture `.aid-o/` trees were gitignored by `**/.aid-o/`; added exception in `.gitignore` matching the existing `mini/` pattern; fixture files (`fsm-state.yaml`, `execution.yaml`) are now tracked and available in CI.
- **CI: dg12 unverifiable on GitHub Actions** — `yq` was not installed in the `bash-tests` job; `dg12-authority.sh` fell through to exit=2 instead of parsing the authority YAML and returning exit=1; added `yq` install step.
- **CI: vitest `@aid/contract` resolution failure** — `dist/` is gitignored so `@aid/contract/dist/index.js` was absent in CI; added `npm run build -w @aid/contract` step before `npm test` in the vitest job.

## [2.41.1] — 2026-06-28

### Changed
- **False-Green Guardrails in Verify Commands + Contracts** — `aid-verify-implementation` and `aid-verify-plan` now enforce four additional review requirements: (1) mandatory "Independent runtime path check" output section — DONE review cannot be based on "tests pass" alone; (2) every AC using "always"/"all"/"each"/"never" must define its exact universe or the plan/AC is rejected as not objectively verifiable; (3) eval/evidence artifacts must name which pipeline slice they actually exercise; (4) every new integration function requires at least one caller-flow test, not just a unit test of the pure helper. Same four guardrails added to `review-checkpoint-contracts.md` so they apply to in-pipeline CP2–CP5 reviews, not only the manual verify commands.

## [2.41.0] — 2026-06-27

### Added
- **Evidence Pack Verifier CLI (E2.5)** — `aid-evidence-verify.sh <epic> <run> [--out <path>] [--at-head]` deterministically verifies a completed run's evidence pack: git cleanliness, artifact freshness (as-of-pack, ancestor-of-HEAD; strict `--at-head` mode for live DONE-review), protocol-v2 validation + finding fingerprints per artifact, TTL/registry guard, and observe-vs-blocking interpretation consistency; emits `verification-report.json` (protocol-v2, self-validated) + human summary; standalone CLI outside FSM.
- **`verification_report` Protocol-v2 Type** — 15th artifact type in `aid-protocol-v2.schema.json` enum + `VALID_ARTIFACT_TYPES` validator array + `TYPE_PAYLOAD_MAP` entry + `verification-report.schema.json` type schema.
- **Evidence Verifier QA** — 11 purpose-built fixtures (clean-pack, ancestor-pack, divergent-stale, inconsistent-head, invalid-artifact, enum-garbage, mixed-legacy, nondeterministic-fingerprint, dirty-git, ttl-violation, enforcement-absent) + `test-evidence-verify.sh` harness + golden sample; every check has positive and negative coverage.
- **Enforcement Registry** — 7 verifier checks registered in `defaults/enforcement-registry.yaml` (`surface: internal-guard`, `status: planned`, `deadline: 2027-06-01`); FSM wiring deferred to E9.

## [2.40.0] — 2026-06-26

### Added
- **C1 Delivery Engine** — `aid-delivery-gate.sh` + 12 DG check plugins (DG-01..12) producing protocol-v2 `delivery-gate.json`; observe mode (E2): writes `delivery_gate_would_block` telemetry, never blocks FSM transitions; blocking promotion deferred to E10.
- **Delivery Gate Policy** — `defaults/policies/delivery-gate.yaml` with profile detection (plugin-bash, npm-workspaces, unverifiable) and per-profile check commands; `skip_reason_allowlist` enforces closed vocabulary.
- **Profile Resolver** — `scripts/lib/aid-delivery-profile.sh`: `resolve_profile` + `select_commands` for deterministic argv-array dispatch (no eval).
- **DG-07 FSM Hook** — observe-mode hook in `cmd_done_advance` writes `delivery_gate_would_block` event to timeline; blocking branch is live code tested by `test-fsm-dg07-observe.bats`.
- **Full Delivery Gate Schema** — `defaults/schemas/delivery-gate.schema.json` expanded to full protocol-v2 payload covering `delivery_gate.{phase,profile,freshness,delivery_ready,checks[],summary}`.
- **QA Fixtures + Harness** — 10 per-DG fail/unverifiable fixtures, golden sample, 44-assertion `test-delivery-gate.sh`; every DG-01..12 check has at least one fixture proving it is not an untested decoration.
- **Gate Coverage Fields** — `aid-run-gates.sh` now emits `covered_paths`, `changed_paths_covered`, and `relevance` (direct|partial|none|unknown) in `gates_report.json`.
- **Enforcement Registry** — DG-07 FSM hook + DG-01/04/07/12 registered in `defaults/enforcement-registry.yaml` as observe-mode (status: planned, deadline: E10).

## [2.38.0] — 2026-06-23

### Added
- **`/aid-verify-plan` + `/aid-verify-implementation`** — two manual, PM-invoked commands that dispatch an independent fresh-context agent to adversarially review a plan before execution and an implementation after it claims DONE; each carries its full review protocol (false-green risks, producer-consumer contracts, runtime-not-statics, real-data oracle) and returns a severity-ranked verdict plus a Czech PM summary. Standalone tools outside the FSM (like `/aid-do`) — no `fsm-state.yaml`, no evidence dir, no pending-dispatches ledger.
- **AID Control System v2 protocol** — shared protocol v2 envelope (`aid-protocol-v2.schema.json`), 14 type-specific schemas, deterministic finding fingerprint helper (`aid-finding-fingerprint.sh`), and authoritative bash+jq validator (`aid-protocol-validate.sh`) with 11 blocking invariants (exit codes 2-13); schemas + validator + fixtures only — no runtime wiring (E2+).

### Fixed
- **Protocol v2 `control_protocol` enum** — validator now enforces enum membership (exit 8) in addition to field presence (exit 3); previously any non-`legacy` value (e.g. `"banana"`) passed as exit 0; fixture `invalid-bad-control-protocol.json` and consistency check added.

## [2.37.0] — 2026-06-21

### Added
- **Per-step Acceptance Criteria pre-flight** — `aid-epic-to-json.sh` hard-fails a multi-step EPIC that carries fewer acceptance criteria than steps, so every step has a contract the CP chain can verify (root cause of the E-047-4_7 cockpit REOPEN); override deliberately with `AID_ALLOW_SPARSE_AC=1`.

### Fixed
- **Plan→EPIC acceptance-criteria + role extraction** — `aid-plan-to-epic.sh` now reads acceptance criteria written as plain `-` bullets under `**Acceptance Criteria**` (with or without a colon) and the `**AID Role**` header without a colon; previously it matched only the `**Acceptance Criteria:**` + `- [ ]` + `**AID Role:**` forms, silently dropping every criterion (empty EPIC AC section) and defaulting every step to the `backend` role.
- **Compliance `overall` is severity-aware** — `write_compliance_json` now derives `overall` from blocking failures only (advisory-severity failures are recorded in `failures[]` for visibility but no longer flip it to `fail`), matching the `cmd_done_advance` release gate; previously a single advisory check such as `branch_correct:false` on a PM-controlled shared feature branch produced `overall:fail` even though the FSM correctly released, a self-contradictory record. The provenance-unverifiable integrity signal stays blocking.

## [2.36.2] — 2026-06-19

### Fixed
- **`aid-plan.md` stale CP1 lens names** — CP1-deep section updated from `security/correctness/architectural` to `L1-behavior/L2-feasibility/L3-enforcement`; evidence file table updated with correct filenames and required-field column (producer→consumer drift fix).
- **`aid-cp1-gate.sh` stale header comment** — file header comment updated to match L1/L2/L3 filenames and content requirements.

### Added
- **P046 boundary manifest and delivery report committed** — `.aid-o/reports/P046-boundary.md` and `.aid-o/reports/P046-delivery.md` now tracked in git; `.gitignore` glob fix (`.aid-o/*`) makes this possible.

## [2.36.1] — 2026-06-19

### Fixed
- **CP1-deep empty-file bypass** — `aid-cp1-gate.sh` previously accepted empty evidence files (only checked `-f`); gate now requires non-empty files (`-s`) and the required field at line-start (`stop_rule_blockers:` in lens files, `verdict:` in adjudicator); empty or structurally incomplete files now fail the gate.
- **CP1-deep lens taxonomy mismatch** — lenses renamed from `security/correctness/architectural` to `L1-behavior/L2-feasibility/L3-enforcement` per plan P046 taxonomy; L3 (enforcement/CI/artifact-visibility) is the class that catches gitignored artifacts and non-executing tests.
- **`/aid-init` `.gitignore` guidance** — instruction corrected to replace `.aid-o/` with `.aid-o/*` before adding `!.aid-o/reports/`; git cannot un-ignore content inside an ignored directory — the glob form is required.

## [2.36.0] — 2026-06-19

### Added
- **Behavior-first review contracts** — `skills/review-checkpoint-contracts.md` defines per-checkpoint diff scope, high-risk pattern table (8 categories: auth, routes, validation, migrations, FSM, security sinks, payment, deps), and structural gate rules for CP2/CP3/CP4/CP5/CP6 and CP1-deep.
- **`behavior_trace` structural gate** — `aid-fsm.sh:fsm_check_verifier_output()` rejects verifier outputs where `behavior_trace_required: true` but `behavior_trace_count` is 0 or missing; gate is opt-in and fires only when the verifier explicitly sets the flag.
- **Additive verifier output fields** — `verifier-output-template.md` gains optional top-level fields (`checkpoint`, `focus`, `behavior_trace_count`, `behavior_trace_required`, `behavior_trace`) that extend the output without displacing existing `_generated_by`/`classification`/`verdict` greps.
- **`aid-prefilter.sh --checkpoint` flag** — caller can now pass `--checkpoint <cp2|cp3|cp4|cp6>` to get checkpoint-specific diff scope; CP2 defaults to `HEAD~1..HEAD`, CP3 reads `base_commit` from `fsm-state.yaml`.
- **CP1 risk-scaling** — `aid-plan.md` gains a CP1 Mode Selection section defining CP1-light (standard checklist) vs CP1-deep (three-lens: security/correctness/architectural, adjudicator, max two revisions, PM escalation on unresolved stop-rules).
- **`aid-cp1-gate.sh`** — EPIC generation gate that reads plan frontmatter (`id`, `risk`), scans body for eight high-risk pattern categories, and verifies four evidence files (`cp1-deep/` directory) when risk is high; includes path-traversal guard on plan ID.
- **Enforcement homes reference** — `docs/extending-aid.md` gains an Enforcement Homes Reference section documenting where each enforcement mechanism lives (plan-close, FSM precondition, behavior_trace gate, CP5 blocking_findings, CI floor).
- **Two new enforcement registry entries** — `cp1_critical_path_flow_trace` (type lm_judgment_advisory, surface cp1) and `behavior_trace_high_risk_gate` (type fsm_precondition, surface cp2/cp3/cp4); both carry `deadline: 2026-09-01`, `status: active`, `verdict: ALIGNED`.
- **6 bats tests for behavior_trace gate** — `bats/test-behavior-trace.bats` covers count=0+required=true→fail, count=3+required=true→pass, required=false→pass, field absent→pass, count missing→fail, count=1→pass.

### Fixed
- **`.gitignore` negation pattern** — replaced `.aid-o/` directory exclude with `.aid-o/*` glob so `!.aid-o/reports/` negation works; git cannot un-ignore content inside an ignored directory.
- **CP1 gate `risk: low` precedence** — high-risk body pattern match now always triggers CP1-deep regardless of `risk: low` frontmatter; `risk: low` previously overrode the pattern scan (wrong behavior).
- **Frontmatter parser state machine** — `aid-cp1-gate.sh` parser now uses open/close `---` state machine; stops reading at opening marker, reads to closing marker, rejects plans with unclosed frontmatter instead of silently reading body as frontmatter.
- **Rule #21 `REVISE_REQUIRED` advisory label** — `plan-writing.md` rule #21 REVISE_REQUIRED outcome labeled "(advisory — see 21c, PM can override)" to match enforcement type; test-plan-writing-rules.bats updated (removed dead `FIXTURES_DIR` variable).

## [2.35.0] — 2026-06-18

### Added
- **`plan-close` FSM command** — enforces all four required reports (curator, auditor, simplifier, delivery) before writing the `ca-review-complete` marker; raw `touch` is explicitly forbidden and `pipeline.md §7` directs implementers to this command instead.
- **Toggle-skip for disabled specialists** — `simplifier.enabled:false` / `reporter.enabled:false` in `execution.yaml` exempts the corresponding report from `plan-close`; each skip is audited to `audit-log.jsonl` with specialist name and rationale.
- **`simplifier_report_present` compliance measurement** — `compliance.json` now carries `simplifier_report_present: null/true/false` (advisory severity); anchored for future enforcement promotion.
- **Boundary manifest (committed, CI-readable)** — Reporter writes `.aid-o/reports/{plan_id}-boundary.md` after every completed plan; carries provenance for all four required reports and is readable by CI without accessing gitignored evidence directories.
- **CI floor check** — `defaults/ci/plan-boundary-required-check.yml` (GitHub Actions) verifies that committed boundary manifests are complete; exits 0 gracefully when no manifests are present.
- **`/aid-audit` CI check residual** — `/aid-audit` verifies whether the boundary CI check is installed and explicitly surfaces the residual when it is not.
- **`/aid-init` optional CI check installation** — fresh or upgraded workspaces are offered the option to copy `plan-boundary-required-check.yml` to `.github/workflows/`.
- **Force-override audit enrichment** — `init --force` pre-scans to identify the blocking plan/EPIC and passes `--blocking-epic` / `--blocking-plan` to `fsm_handle_force_override`, writing both to `timeline.jsonl` and `audit-log.jsonl`.
- **13 new bats assertions** — `test-plan-close.bats` (9 tests: missing reports, toggle-skip, audit entry) and `test-ci-floor.bats` (4 tests: no manifests, valid manifest, incomplete manifest, missing delivery).
- **`_aid_read_toggle()` helper** — yq-free toggle detection extracted into a shared function, eliminating duplicated grep chains in `cmd_plan_close` and `fsm_eval_simplifier_present`.

## [2.34.2] — 2026-06-18

### Fixed
- **`plan_diff` evidence truthfulness** — gate runner recorded `result: "pass"` for exit-2 graceful skips (no AC blocks / legacy plan), making `gates_report.json` claim verification happened when it did not; changed to `result: "skip"` so evidence accurately reflects that the gate skipped rather than passed.
- **`review_result` instruction drift** — `role-cards.md` and `gate-fixer.md` still referenced the old nested `review_result.findings[]` contract after the Step 2 canonical-output migration; updated to top-level `findings:[]` per `agents/verifier.md`.

## [2.34.1] — 2026-06-18

### Fixed
- **`yaml_field()` quoted-empty bypass** — `_generated_by: ""` and `_generated_by: ''` returned a non-empty string (the literal quote characters), allowing fabricated empty fields to pass `[[ -z ]]` guards; fixed by stripping surrounding YAML quotes after whitespace trimming so quoted-empty collapses to empty and fails correctly.
- **Verdict whitelist missing** — only `pending` and empty were rejected from verifier output; any other non-standard scalar (e.g. `banana`) passed as a valid completed verdict; fixed by explicit `case` whitelist that accepts only `pass|fail`.
- **`blocking_findings` fail-closed on non-false values** — only exact scalar `true` was blocked; `maybe`, `"true"` (quoted), comment text, and any other non-empty value passed silently as clean; fixed to accept ONLY scalar `false` (after quote-stripping), treating everything else as blocking.
- **`cp4_curator_validation` registry anchor** — source line was `scripts/aid-fsm.sh:283`, actual function start is `:292`; corrected.
- **Enforcement registry seed header** — seed file still claimed "single source of truth / NOT yet promoted"; updated to "SUPERSEDED by E-046-1_3 Step 5" to match reality after promotion.

## [2.34.0] — 2026-06-18

### Added
- **Enforcement registry promoted to `defaults/`** — `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` is now git-tracked and shipped with the plugin; previously it lived only in a gitignored seed file, making it invisible to consumers and untestable in CI.
- **TTL guard for planned enforcement rows** — `scripts/aid-registry-ttl-guard.sh` exits non-zero when a `status: planned` registry row is past its `deadline` without a valid future `deferred_until` date; enforces the "Detector without Enforcement is Decoration" principle (§1) by making planned-but-never-wired items fail CI instead of silently rotting.
- **`deadline` / `deferred_until` / `deferred_by` / `deferred_reason` schema** — per-row TTL fields added to the registry schema so each planned enforcement can state when it must be wired and who deferred it if not yet done; P045 planned rows carry `deadline: 2026-09-30`.
- **`_generated_at` required in verifier output** — `fsm_check_verifier_output` now rejects files missing or empty on `_generated_at`, closing the anti-fabrication gap where a verifier's timestamp could be omitted without FSM consequence; `agents/verifier.md` output spec and the verifier output template updated to match.
- **`cp4_glob_evaluated` audit event wired** — the event was documented in `skills/agent-protocol.md` but never emitted; now emitted by `fsm_check_cp4_curator_validation` before the production-touch check, resolving the ORPHAN verdict in the enforcement registry.
- **Regression tests: cross-plan gate, `_generated_at`, CP4 content-validation, CP5 blocking_findings** — 19 new bats assertions in `test-aid-fsm.bats` (cross-plan E-→P gate, `_generated_at` enforcement, CP4 content), `test-tiered-severity.bats` (CP5 four-case matrix), and the new `test-registry-ttl.bats` (6 TTL guard assertions).
- **`run-all-tests.sh` discovers `bats/test-*.bats`** — the test runner now auto-discovers bats suites in the `bats/` subdirectory in addition to `test-*.sh`, so `test-registry-ttl.bats` and all other bats suites run in CI without manual registration.

### Changed
- **CP4 curator-validation content-validated** — `fsm_check_cp4_curator_validation` previously accepted any file at the expected path; it now routes through `fsm_check_verifier_output` and rejects files missing valid `_generated_by`, `_generated_at`, or `classification` fields.
- **`blocking_findings` reads canonical top-level field** — `done-advance review → release` now reads the auditor's `blocking_findings:` key via `yaml_field` (line-start match only) instead of `grep -ciE` on prose; fail-closed on absent field, immune to false-positives from negations or body text; `agents/auditor.md` output template updated to emit `blocking_findings:` as the first top-level key.
- **Cross-plan init gate fixed for `E-NNN` IDs** — the gate that blocks starting a new EPIC when the previous plan has unreviewed Curator/Auditor findings was silently dead because the plan-prefix derivation used `grep -oP '^P\d+'` which never matched `E-NNN` style IDs; fixed using `BASH_REMATCH[1]` on `E-([0-9]+)`.
- **Enforcement registry ORPHAN rows resolved** — `dispatch_completed_late` removed (unwireable in scope), `cp4_glob_evaluated` promoted to `status: active`, `cp4_template_stale_name` aligned; verdict distribution: ORPHAN 3 → 0, ALIGNED 71 → 73.

### Fixed
- **`test-tiered-severity.bats` fixture broken by fail-closed** — six existing tests that used a minimal `audit-report.md` without `blocking_findings:` now fail the Step 3 fail-closed precondition; fixture `setup()` updated to write `blocking_findings: false` at line-start so the tests exercise their intended provenance logic without triggering the new guard.
- **TTL guard quoted-date regex** — `aid-registry-ttl-guard.sh` regex for `deadline:` and `deferred_until:` now handles `"YYYY-MM-DD"` (quoted) in addition to unquoted values, matching the flow-style YAML format used by the registry.

## [2.33.1] — 2026-06-15

### Fixed
- **docs-writer step ID** — EPIC steps with the `docs-writer` role failed `plan.json` conversion because the role's hyphen broke the `step.id` pattern `^step_[a-z0-9_]+$`; the role is now sanitized (hyphen → underscore) when building the step ID, while `step.role` keeps its canonical hyphenated value, so docs-writer steps convert and dispatch correctly.

## [2.33.0] — 2026-06-15

### Added
- **dispatch_mode selection in /aid-init** — fresh init now asks which dispatch mode to use (agent_tool / inline / subagent) instead of silently writing a default, and re-runs preserve a manually-chosen mode instead of resetting it to `agent_tool` on every run — the silent-reset that caused P043/P044 provenance false-blocks.

### Fixed
- **done-advance critical-finding precondition** — the release precondition now reads the auditor's structured `blocking_findings` verdict instead of grepping report prose for `critical.*security`; the old grep false-positived on negations ("No Critical … security issue") and even on notes describing the false positive, blocking clean releases and pushing users to edit audit evidence to get through.

## [2.32.0] — 2026-06-15

### Added
- **Real-scale Visual Companion mockups** — when building UI on an existing frontend, the companion records the real dimensions (container/column widths, row heights, font sizes, spacing, breakpoints) from the live code and reproduces them 1:1, so a mockup reflects what actually fits on screen instead of an arbitrarily-scaled sketch.

### Changed
- **Visual Companion canvas always white** — the browser companion frame no longer follows OS dark mode (white page background, `color-scheme: light`, dark-mode media query removed), so mockups are always judged on the same white canvas the target UI uses.

### Fixed
- **pre-commit hook shebang** — the generated FSM-guard pre-commit hook had no shebang, so git ran it under `/bin/sh` (dash on Debian) where its bash syntax (`[[ ]]`, `< <(find …)`) failed and blocked every commit, forcing `--no-verify`; it now starts with `#!/usr/bin/env bash` and `/aid-init` retrofits the shebang onto hooks installed before the fix.

## [2.31.0] — 2026-06-14

### Added
- **Whisper transcription via LiteLLM proxy** — voice transcription routes through the LiteLLM AI gateway instead of calling OpenAI directly, so audio spend and routing flow through one gated proxy (D-082 F2).

### Removed
- **Orphaned docs-deploy workflow** — removed the stale Docusaurus deploy CI workflow; the docs were migrated to the central eco docs site.

## [2.30.0] — 2026-06-14

### Added
- **Simplifier + Reporter at Plan Boundary** — two plan-boundary specialist agents run after a plan's last EPIC: the Simplifier proposes reuse/dedup/clarity refinements over the whole plan diff (S/M auto-applied through the gate-fixer → CP4 revert-on-fail rail, L deferred to the PM summary), and the Reporter tests the delivered functionality and writes a plain-language `.aid-o/reports/{plan_id}-delivery.md` from a fixed 7-section template, condensing the Auditor and Curator verdicts and leaving ≥1 on-disk test artifact as anti-fabrication proof. The new `delivery_report_present` compliance check (advisory, severity-routed) verifies the report's presence and on-disk `_test_evidence` at the plan boundary and rides the existing done-advance gate (`null` before the boundary, so it never false-blocks a non-final EPIC). Both agents are config-toggled and inert until a project re-inits.
- **Contributor guide (docs/extending-aid.md)** — a single reference documenting where each enforcement type lives (the type→instruction-home convention), the checklist to add one, the severity-layer vs hard-die FSM precondition patterns, the agent_tool dispatch-mode reality, and the P045 Simplifier + Reporter worked example.

## [2.29.4] — 2026-06-12

### Fixed
- **Force-Path Recovery Alert** — compliance blocks cleared via PM `--force` override never emitted the ✅ resolution alert because the force branch of done-advance skipped the entire P042 recovery block; recovery emission now lives in a shared helper (`fsm_emit_compliance_recovery`) called from both the clean re-run and the force-override paths, so every 🛑 blocked alert is paired with a ✅ regardless of how the block was cleared.
- **aid-init dispatch_mode Template** — the `/aid-init` plugin-discovery step still wrote `dispatch_mode: subagent` into `config/plugin.yaml` on every run, overriding the P043 `agent_tool` default and reintroducing guaranteed `verifier_provenance` false-positive blocks; the template now writes `agent_tool` and the dispatch-mode docs describe all three modes including the false-positive failure class.

## [2.29.3] — 2026-06-12

### Added
- **Check-severity sync guard** — new `test-check-severity-sync.sh` suite fails when a compliance check emitted by the FSM has no entry in `defaults/check-severity.yaml`, closing the trap where an unregistered check silently defaults to advisory and can never block
- **Compliance recovery alert documentation** — pipeline.md §7 now documents the P042 block/recovery Telegram alert pair, the `fsm_done_advance_recovered` dedup marker, and the `alert_on_compliance_recovery` config gate

### Changed
- **Accurate provenance aggregate in agent_tool mode** — compliance.json now reports `provenance_aggregate: "agent_tool"` instead of the misleading `"mixed"` when verifier dispatch runs via the CC Agent tool (non-blocking behavior unchanged)
- **dispatch_mode default single-sourced** — `defaults/orchestration.yaml` `dispatch.mode` is now the single source of the default (`agent_tool`, with all three modes documented); aid-fsm.sh resolves project `plugin.yaml` → plugin `orchestration.yaml` → hard fallback, removing the stale `subagent` doc/code drift
- **FSM internals simplification** — pure-bash `yaml_field()` reader replaces 51 copy-pasted `grep|awk` field reads (~100 fewer process forks per FSM run); repeated-fail counters, CP3 verifier-output evaluation, and the increment-step precondition fail ritual each consolidated into single helpers; shared `die()` moved to `lib/aid-stage-log.sh`; step-verify content checks read the file once; behavior unchanged (all 18 suites + 115 bats tests pass)

## [2.29.2] — 2026-06-10

### Changed
- **Visual Companion — current state mandatory in mockups** — when proposing UI changes to an existing component/page, the companion must always render the current look alongside the proposed changes (side-by-side or inline delta); showing only the new design in isolation is now explicitly prohibited; applies both in the "Read the Code First" refactoring flow and as a general design tip

## [2.29.1] — 2026-06-09

### Fixed
- **verifier_provenance false-positive blocking** — `dispatch_mode` defaulted to `subagent`, which requires `verifier_dispatch_start/complete` timeline events that the CC Agent tool never writes; every EPIC in standard AID self-hosted operation was therefore permanently blocked on `verifier_provenance`; the default is now `agent_tool` (set `dispatch_mode: subagent` in `.aid-o/config/plugin.yaml` to opt into strict interval-bracket provenance enforcement); a new `verify_provenance` branch returns a non-blocking `"agent_tool"` signal so `provenance_aggregate` never escalates to `"unverifiable"` in this mode

## [2.29.0] — 2026-06-07

### Added
- **Compliance recovery alert** — when a `done-advance review→release` succeeds with zero blocking failures for an EPIC that previously emitted a `🛑 release blocked` alert, AID now emits a `✅ compliance cleared, release unblocked` Telegram alert and writes an `fsm_done_advance_recovered` timeline event (dedup marker, observable test signal); controlled by `alert_on_compliance_recovery` config gate (default on)

## [2.28.3] — 2026-06-06

### Fixed
- **Self-referential dependencies** — a step whose dependency range covered its own number (e.g. "Steps 4-6" on step 6) produced a meaningless self-edge that downstream cycle detection rejected; self-references are now dropped during dependency remapping
- **Task-keyword dependencies** — `Depends on: Task N` / `Tasks M-N` lines were silently ignored because the parser only recognized "Step", even though `## Task N:` step headers are accepted; the dependency parser now treats the Task keyword the same as Step
- **Clean-tree guard vs. runtime queue** — the FSM init clean-tree guard aborted on any tracked change including AID's own `.aid-o/config/queue.yaml`, which the auto-pipeline mutates between phases, breaking multi-phase auto runs in projects where that file is tracked; the guard now excludes the runtime queue file
- **/aid-init .gitignore backfill** — `.gitignore` setup skipped the entire AID block when any `.aid-o/` entry already existed, so projects initialized before a later ignore entry (e.g. the runtime queue file) never received it; setup now appends individual missing lines on upgrade

## [2.28.2] — 2026-06-06

### Fixed
- **EPIC dependency renumbering** — when slicing a multi-EPIC plan into per-EPIC files, the Steps table renumbered each EPIC's steps locally (1..N) but the Depends On column kept the plan's global step numbers, producing dangling references like "step 2 depends on 4" in a 3-step EPIC that crashed dependency validation in `aid-epic-to-json.sh`; intra-EPIC dependencies (and the Goal step list) are now remapped to EPIC-local numbering

## [2.28.1] — 2026-06-04

### Fixed
- **FSM force-transition crash** — `aid-fsm.sh transition --force` aborted under `set -u` with "project_root: unbound variable" because `fsm_emit_audit_log` read the variable before its guarded fallback, breaking the manual-override escape hatch
- **CI bash test coverage** — the FSM, release, and integration test suites were silently skipped in CI (no `bats` installed) and had drifted stale against new preconditions; CI now installs `bats`, the four affected suites are repaired, and the FSM precondition layer gained real red/green coverage so it cannot be weakened unnoticed

## [2.28.0] — 2026-06-04

### Added
- **Skill & command authoring standards** — `skill-writing.md` and `command-writing.md` promoted to live skills, with `aid-lint-skill.sh` + `test-skill-lint.sh` enforcing the mechanical subset (pre-existing files grandfathered until revised)
- **Frontend Visual Anchoring enforcement** — `increment-step` hard-fails a frontend step that has `visual_refs` but whose output lacks a `## Visual Anchoring` section

### Changed
- **Model single source of truth** — model tier lives only in `role-cards.md`; removed the conflicting `orchestration.yaml` models block and the phantom `role_assignments` reference
- **role-cards.md holistic unification** — `e2e` is now a real step role with one rich card; `docs` renamed to `docs-writer` everywhere; `qa` gets a full card; structure and footer unified
- **Curator is propose-only** — curator recommends a disposition, the orchestrator applies fixes at every effort (S/M/L), and CP4 reviews the applied changes (reordered to run after the apply)
- **auditor.md overhaul** — scorable A–J categories, corrected scoring math, pre-merge timing
- **planner.md rewrite** — documents the real two-script pipeline (no fictional intelligent planner)
- **Config-policy single-sourcing** — escalation triggers and `skill_conflicts` deduplicated to one authoritative source; pre-filter regexes single-sourced to `pre-filter-rules.yaml`; `not_acceptable` patterns routed to real enforcement or explicitly marked advisory

### Fixed
- **Verifier provenance false-positives** — interval-bracket window replaces the ±60s test that flagged honest runs; fails closed when the severity registry can't be read; renamed the verdict to the honest `unverifiable` and added an explicit anti-fabrication instruction to the orchestrator
- **aid-run.md fiction + task→epic terminology** — removed non-existent state transitions / branch / merge-target claims
- **role_overrides downgraded to advisory** — the global `Bash(*)` permission made per-role scoping non-enforcing; the false security claim was removed
- **deserialize_dangerous pre-filter rule** — a `(?!_safe)` lookahead (unsupported by bash ERE) made the rule silently never match; rewritten ERE-safe
- **Honest phase-end note** — `run-management.md` no longer claims the controller auto-enforces the PM-GO boundary

### Removed
- **Unread config** — `orchestration.yaml` `models:` block and `release.skip_when`, and the `execution.yaml` global `retry:` block — read by nothing (per-gate `max_retries` is the only retry knob)

## [2.27.0] — 2026-06-02

### Changed
- **FSM state file unified to `fsm-state.yaml`** — retired the parallel `state.yaml` step-array that `aid-epic-to-json.sh` wrote but nothing read; every script, doc, template, and test now refers to the single FSM state file `fsm-state.yaml`, with the legacy `state.yaml` name kept only as a read fallback for in-flight pre-migration runs.

### Fixed
- **`/aid-stop` + `/aid-run --resume` state handling** — `/aid-stop` dropped the invented `session.*` schema, now reads the real `fsm-state.yaml` fields and logs the stop event through the canonical timeline helper; `--resume` reads `fsm-state.yaml`.

### Removed
- **Queue `pause` / `resume` / `reorder` subcommands** — removed from `/aid-status` and help; documented but never backed by any script (archived, restorable).

## [2.26.0] — 2026-06-01

### Changed
- **Documentation hygiene** — stripped version-stamped headings (e.g. `(NEW v2.16.0 — P032)`) from pipeline.md, agent-protocol.md, and related skills/commands; refreshed stale `Last Updated` dates; reconciled the brainstorming severity-enum claim and the aid-status `{epic_id}` naming drift.

### Fixed
- **aid-help level detection** — counted `state: DONE` in `state.yaml` (never written by the FSM), so every user showed Level 0; now reads `fsm-state.yaml`.
- **aid-init pre-push hook docs** — clarified pre-push uses its own marker `AID-ORCHESTRATOR-PREPUSH-START` (not the pre-commit marker), preventing duplicate hook blocks on re-run.
- **CP4 curator-validation filename** — verifier-output-template + verifier.md now name the FSM-required `verifier-output-cp4-curator-validation.md`; corrected the false "FSM does NOT enforce" note.
- **implementer model selection** — replaced the duplicated, incomplete model-tier list with a pointer to role-cards.md (single source of truth covering all roles).
- **brainstorming prior-work scan** — globbed nonexistent `.aid-o/epics/`; now `.aid-o/tasks/`.

### Removed
- **aid-research command + knowledge/Context7 layer** — removed the never-wired on-demand research command, its knowledge-base template, the integrations `knowledge:` config, the `context_scope.knowledge` plan-schema flag, and all orphaned Context7 references; archived to `docs/plans/AID-audit-2026-06/removed/` (restorable). The layer had no producer wired and no consumer.

## [2.25.0] — 2026-05-31

### Added
- **aid-emit-dispatch.sh wrapper** — new bash CLI with `start` and `complete` subcommands the orchestrator MUST call before/after every `Agent({subagent_type, prompt})` dispatch; writes `verifier_dispatch_start`/`_complete` events to timeline.jsonl plus tracks state in pending-dispatches.jsonl per evidence dir.
- **fsm_check_orphan_dispatches function** — reconciliation backstop in cmd_increment_step that refuses step transitions when pending-dispatches.jsonl shows a start event older than expected_duration_max without matching complete.
- **fsm_check_cp4_curator_validation function** — precondition in cmd_done_advance review→release that requires verifier-output-cp4-curator-validation.md when curator-report.md exists and any commit in `base_commit..HEAD` range touches production code paths. Mode-aware: skips with `cp4_skipped_streamlined_advisory` audit event when streamlined_mode is true.
- **fsm_check_streamlined_integration_review function** — precondition in cmd_done_advance review→release that, when streamlined_mode is true, requires all three of `verifier-output-cp3-code-review.md`, `verifier-output-cp3-security.md`, `gates_report.json` present in the evidence dir.
- **fsm_check_streamlined_abandoned function** — abandoned-but-shipped detector in cmd_done_advance that fires when streamlined_mode is true and timeline.jsonl has fewer than 3 events.
- **--streamlined CLI flag in cmd_init** — first-class lightweight execution mode that writes `streamlined_mode: true` into fsm-state.yaml and propagates through cmd_increment_step / cmd_done_advance / write_compliance_json.
- **coverage_mode + skipped_dimensions fields in compliance.json** — honest accounting of which dimensions were intentionally skipped per the streamlined contract. Field name `coverage_mode` (not `mode`) avoids collision with the existing fsm-state.yaml `mode` (manual/auto execution mode).
- **Four blocking checks in defaults/check-severity.yaml** — `dispatch_orphan_complete`, `cp4_curator_validation`, `streamlined_abandoned`, `streamlined_integration_review`, all severity blocking per AID-v3-principles.md §1 with explicit PM promotion (NR 8-14 empirical evidence across 4 projects).
- **cp4_production_paths field in defaults/execution.yaml** — configurable glob alternation for CP4 trigger detection; `/aid-init` stack-scan in `scripts/lib/aid-init-execution-yaml.sh` auto-populates project-specific defaults.
- **aid-json-to-run.sh Step 18 auto-init** — calls `aid-fsm.sh init` after run.md generation when fsm-state.yaml is absent, eliminating state.yaml vs fsm-state.yaml confusion (NR 10/12/14 anchor). Accepts a `--streamlined` passthrough (threaded from `/aid-run --streamlined` and `aid-auto-pipeline.sh`) that forwards to `cmd_init` so the auto-initialized state carries `streamlined_mode: true` — without it the streamlined activation switch would be unreachable.
- **test-aid-emit-dispatch.bats** — eleven fixtures: the original eight (start-only, start+complete pair, orphan complete, ceiling clamp, concurrent flock, missing output_file, malformed agent_id, inode-swap race) plus three CP3-security fixtures (`--focus` injection rejected by allowlist, jq-escaped pending construction, per-start nonce prevents ledger double-clear).

### Changed
- **cmd_increment_step preconditions** — added Component B orphan-dispatch backstop after the existing memory_used/memory_written/verifier_output checks; conditionally skips the per-step verifier_output check when streamlined_mode is true.
- **cmd_done_advance review→release preconditions** — added Component D streamlined_integration_review check, streamlined_abandoned check, and Component C CP4 enforcement (mode-aware in streamlined); all wired before the existing curator-report check; cites AID-v3-principles.md §1.
- **write_compliance_json schema** — emits top-level coverage_mode and skipped_dimensions fields; backward-compatible (legacy compliance.json without these reads as coverage_mode "full", skipped_dimensions []). The `mode` → `coverage_mode` rename is a breaking change for any downstream consumer that read the v0 draft.
- **fsm-state.yaml unified schema** — absorbs the legacy state.yaml steps[] array; backward-compat dual-file reader preserved.
- **skills/pipeline.md** — new §4 Dispatch Protocol subsection documenting the mandatory aid-emit-dispatch.sh wrapper chain; PRE-FLIGHT auto-init note.
- **skills/agent-protocol.md** — reference tables for the new audit events and check-severity entries.
- **commands/aid-run.md, commands/aid-plan.md, commands/aid-do.md** — --streamlined flag documentation and advisory trigger criteria.

## [2.24.0] — 2026-05-31

### Added
- **FSM Artifact Templates (`step-verify-template.md` + `verifier-output-template.md`)** — two new templates in `defaults/templates/` document the exact section/field schema enforced by `aid-fsm.sh` preconditions. `step-verify-template.md` lists the six required sections (Acceptance Criteria with `- [x]` checkboxes, Commit with 7+ hex SHA, Memory Used, Memory Written, Files, Result: PASS) each annotated with the failing `cmd_increment_step` reason. `verifier-output-template.md` is a single file covering all four CP variants (CP2 per-step, CP3 code-review, CP3 security, CP4 curator) with line-start `_generated_by:` / `classification:` / `verdict:` fields tied to `fsm_check_verifier_output`. Empirically motivated: WAN P027 EPIC 1 had 11 FSM precondition failures (5 from undocumented step-verify schema, 3 from undocumented `_generated_by` schema) while EPIC 2 had 0 — proving the schema is learnable, so it should be documented up-front rather than discovered through failure (NR 10 §4D, NR 12 §4A, NR 14 RC1).

### Fixed
- **`aid-plan-to-epic.sh` step counter fenced-block bug** — parser regex `^###?[[:space:]]+(Step|Task)[[:space:]]+([0-9]+)` previously matched `### Step N:` headers inside fenced code blocks, so any plan *about AID itself* that quoted AID step syntax got mis-counted and the pipeline crashed with `objective too short` errors. Fix tracks fence depth (toggle on lines matching `^[[:space:]]*````) across four scan sites: `has_impl_steps` awk quick-check, main step-numbering while-loop, `extract_step_content()` awk helper, and the objective-fallback awk. `aid-epic-to-json.sh` confirmed unaffected (parses EPIC table rows, not plan.md headers). New `test-aid-plan-to-epic-fence.bats` fixture reliably fails pre-fix and passes post-fix. Empirical anchor: AID-self P039 (v2.23.0 brainstorming plan) tripped this bug — NR 14 §4D.
- **`defaults/policies/permissions.yaml` stale MCP refs (action required: re-run `/aid-setup permissions`)** — the autonomous preset whitelist referenced MCP servers that no longer exist in current eco infrastructure: `qdrant-memory__*`, `shared-docker__*`, `shared-minio__*`, `shared-postgres__*`, `shared-playwright__*`, `shared-telegram__*`. Replaced with the actual running set: `vulcan-memory__{find,store,list}` (excluding destructive `vulcan-delete`), `eco-admin__*` 12 GREEN read-only tools (YELLOW writes intentionally excluded — require Telegram approval per ADR-17 D-077), `claude_ai_Google_Drive__*` 6 read-only ops. Kept `shared-github`, `shared-sequential-thinking`, `svc-mcp-tg-bot__send_message`, `plugin_context7_context7`, and `qdrant-brain` (back-compat with `skills/memory-mcp.md` contract). Playwright explicitly NOT auto-allowed — opt-in via per-project `settings.local.json`. Empirical anchor: NR 11 manual audit. **Existing projects that already ran `/aid-setup` retain stale entries in their local `.claude/settings.local.json` and should re-run `/aid-setup permissions` to refresh.**

## [2.23.0] — 2026-05-31

### Added
- **Section-Review Validate-Then-Verify** — brainstorming Step 6 sections now run a Sonnet `section-review` critic followed by an Opus ground-truth re-grep, presenting the PM a claim-verification table (validator claim → real command + output → ✓/✗) before approval; Step 7 adds a `cross-section-review` consistency check over the assembled plan.

### Fixed
- **Verifier focus card naming** — the `security-review` card in `role-cards.md` is renamed to `security` to match the canonical focus name used plugin-wide (orchestration tier, CP3 dispatch, planner, aid-run, epic templates); resolves a latent card-name mismatch with the registry.

## [2.22.3] — 2026-05-14

### Fixed
- **`skills/brainstorming.md` references to renamed visual-companion path** — v2.22.1 moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` but left two stale `skills/visual-companion.md` references in `brainstorming.md` (lines 107 and 258). The `test-instruction-consistency` bash suite caught it (`✗ Referenced file MISSING`) and CI went red since v2.22.1's push. Both references updated to the directory form.

## [2.22.2] — 2026-05-14

### Changed
- **Visual Companion — explicit remote-host networking + read-first-before-redesign rule** — Standalone Invocation Step 3 now mandates picking server bind mode (`127.0.0.1` for local agent / `0.0.0.0 --url-host <IP>` for remote SSH-VPN setup) BEFORE starting the server, with detection cues (`$SSH_CONNECTION` env, `hostname -I`) and a direct ask-PM fallback. Previously the remote case was a buried footnote, leaving the agent to start a loopback-only server that PM's browser couldn't reach. Plus new "Refactoring or Redesigning Existing UI — Read the Code First" section: when PM references an existing component / screenshot / page name, agent MUST ask "should I read the current implementation first?" and produce a structured data-inventory in chat before any mockup. Saves the iteration cycles where mockups get drawn against guessed data shapes and need full rewrite after the real component is read.

## [2.22.1] — 2026-05-13

### Fixed
- **Visual Companion skill discovery (hotfix v2.22.0)** — moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` directory structure. Claude Code's plugin loader only recognizes skills as user-invokable (slash-callable) when they live in `skills/<name>/SKILL.md` form; flat files are loaded for in-plugin reference but never registered as `/<name>` slash commands regardless of any `user_invocable` frontmatter flag. v2.22.0 release flipped the flag and added the standalone section but kept the flat-file shape, so `/visual-companion` did not appear in the command palette. This release fixes the structure only — no content changes.

## [2.22.0] — 2026-05-13

### Changed
- **Visual Companion skill is now user-invocable** — `/visual-companion` slash command opens a standalone demo session for verifying the browser round-trip (server start, HTML push, click capture, events read) without going through the full `/aid-plan brainstorm` flow. Skill frontmatter flipped `user_invocable: false → true` and a new "Standalone Invocation" section was added with explicit start/stop steps, npm-install first-run handling, and node_modules fallback path. Skill remains backward-compatible with the existing brainstorming integration — per-question gate behavior inside `/aid-plan brainstorm` is unchanged.

## [2.21.1] — 2026-05-13

### Fixed
- **`try_telegram_alert` test-mode guard** — `AID_TEST_MODE=1` env var short-circuits the helper before any `jq` or `curl` invocation, so bats fixtures and smoke tests no longer fire real-world Telegram alerts. Discovered post-P038 ship: cmd_done_advance blocking precondition (Step 3) and 3 other call sites previously emitted ~30 alerts during fixture development with `E-TEST-038: 1 blocking compliance failure(s)`. Shared bats `setup_test_evidence_dir` (test-helpers.bash) and `test-tiered-severity.bats` `setup()` now export the guard. Convention: any future side-effect helper (mail/Slack/webhook) should mirror this pattern.

## [2.21.0] — 2026-05-13

### Added
- **Tiered severity registry** — `.aid-o/config/check-severity.yaml` declares each compliance check as `blocking` or `advisory`; shipped by `/aid-init` with initial bootstrap per AID-v3-principles.md §1
- **`failures[]` array in compliance.json** — every release writes per-check failure entries with severity, evidence, and promoted_at, enabling deterministic blocking decisions
- **`aid-fsm.sh promote-check`** — explicit advisory→blocking promotion with mandatory ≥20-char reason and forensic audit-log entry
- **`aid-fsm.sh check-promotion-candidates`** — read-only scan of audit-log.jsonl identifying advisory checks that meet the AID-v3-principles.md §1 promotion criterion (force_override_rate < 0.05 across N≥5 EPICs)
- **`aid-promote-checks.sh`** — PM-facing markdown report wrapping the candidate scan
- **`test-tiered-severity.bats`** — 6 fixtures covering blocking-blocks, advisory-passes, --force-with-audit, short-reason-rejection, promote-check, and candidate identification

### Changed
- **`cmd_done_advance review→release`** — now refuses transition when any compliance failure has `severity: blocking`; structured error message includes per-failure evidence and copy-paste `--force --reason --blocked-checks` override snippet; per AID-v3-principles.md §1 "Detector without Enforcement is Decoration", this is the first concrete application of the principle and closes the P026 (WAN, 2026-05-13) failure mode
- **`fsm_handle_force_override`** — accepts new `--blocked-checks "<comma-list>"` flag; propagates to both timeline.jsonl and audit-log.jsonl
- **`aid-audit-log.sh cmd_append`** — new `--<key>-array "a,b,c"` flag-suffix convention emits JSON arrays in output entries; dash-to-underscore JSON key normalization for compatibility
- **`pipeline.md §7 DONE State`** — new "Tiered Severity Enforcement" sub-section documenting the override flow, the severity table, and the promotion ceremony
- **`write_compliance_json`** — populates `failures[]` array using check-severity.yaml registry; backward compatible (empty array when no failures)

## [2.20.2] — 2026-05-12

### Added
- **Plan-AC Diff Gate (P037 Phase 2, AID-010)** — new deterministic gate `plan_diff` in `execution.yaml` runs `aid-plan-diff.sh` after EXECUTE→GATES. Script parses plan-level `## Acceptance Criteria` section, executes each `verification_pattern` (3 types: `cmd`, `must_not_exist`, `must_contain` with any-match regex semantics) against codebase HEAD, emits `plan-diff.json` with per-AC verdict. Fail if ≥1 AC absent.
- **`aid-plan-diff.sh` Standalone Script** — new 281-line bash script under `plugins/aid-orchestrator/scripts/`. Standalone testable lifecycle (own provenance fields `_generated_by: aid-plan-diff.sh@v2.20.2`, own timeline events `plan_diff_start`/`plan_diff_complete`). 4 exit codes: 0 (all present), 1 (≥1 absent), 2 (graceful skip — Fast Mode or no AC section), 10 (input validation).
- **Plan Template AC Block** — `defaults/templates/plan.md` extended with `## Acceptance Criteria` section template using executable `verification_pattern` blocks (3 example patterns: cmd, must_not_exist, must_contain). New plans (P038+) gain plan-level AC verification by default.
- **Completeness Gate Sub-Check #20** — `plan-writing.md` Completeness Gate added 3 sub-rules (20a/20b/20c) enforcing `verification_pattern` block on every AC for new plans; legacy plans (P001-P036) without AC section skip the check (no violation). EVALUATION counter updated `out of 24` → `out of 27`.
- **`compliance.json plan_ac_match` Dimension** — `evaluate_compliance_checks` reads `plan-diff.json`, sets `checks.plan_ac_match: true | false | null`. False forces `compliance.overall: "fail"`; null = graceful skip for legacy plans or missing plan-diff.json.
- **`{plan_path}` Placeholder Token** — `aid-run-gates.sh` `resolve_placeholders()` helper substitutes 4 known tokens (`{plan_path}`, `{epic_id}`, `{run_id}`, `{base_commit}`) in gate commands via bash parameter expansion. `cmd_init` writes `plan_path:` field to state.yaml (realpath-normalized absolute path or literal `null` for Fast Mode EPICs). Unknown `{<token>}` triggers fail-loud exit — silent pass-through is a debug trap.
- **Plan-AC Diff Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-plan-ac-diff.bats` (8 tests covering all 3 pattern types, fail path, Fast Mode null + empty, legacy skip, resolve_placeholders + cmd_init replicas). Full bats suite now 52/52 ok.

### Changed
- **`aid-run-gates.sh` Gate Command Resolution** — gate commands now pass through `resolve_placeholders()` before `bash -c` execution. Exit code 2 counts as pass when gate's `pass_criteria` mentions "exit 2" (graceful-skip pattern).
- **`defaults/execution.yaml`** — legacy `{base}..HEAD` tokens in `docs_updated` gate renamed to `{base_commit}..HEAD` (aligning with `scope_check` convention; required for resolve_placeholders fail-loud safety). New `plan_diff:` gate entry appended after `scope_check:` (required: true, max_retries: 0, pass_criteria documents exit 0 or exit 2).

### Fixed
- **Goalpost Shift Detection** — Five EPICs (P019 F1+F2 frontend migration, P021 F4 backlog collision, P022 F6 Playwright→backend substitution, P023 F7 five concurrent shifts) previously passed to DONE without detection because gates didn't check plan AC reality vs implementation. Phase 2 `plan_diff` gate catches this class — every new plan with `verification_pattern` blocks gets per-AC executable verification on codebase HEAD before GATES→DONE.
- **`cp2_per_step_provenance` Type Mismatch (IMP-100)** — backfill in `aid-compliance-backfill.sh` previously wrote scalar string `"unknown"` for `cp2_per_step_provenance`, while the live writer in `aid-fsm.sh evaluate_compliance_checks` emits a JSON array (one entry per CP2 step). Type drift created silent correctness risk for queries doing `| length`. Backfill now writes `["unknown"]` (single-element array) to match live writer shape. Other 3 fields (cp3_*, provenance_aggregate) remain scalar — consistent with live writer.
- **`backfill_provenance` Silent Error Conflation (IMP-102)** — previously returned exit 1 for both "already-present skip" (normal) and "jq failure" (corrupted compliance.json). Step C caller incremented skip-count for both, masking real errors. Function now returns 0 (fixed), 1 (jq failure with stderr WARN), 2 (idempotent skip); caller case-statements on exit code and reports backfilled/skipped/errors separately in summary heredoc.
- **`verify_provenance` Unused `step_n` Parameter (IMP-103)** — `$3` was received in signature but never referenced in body. Renamed to `_step_n` with code comment explaining intentional retention for future per-step forensic attribution. Positional API stable (no call-site changes needed).
- **CLI Dispatcher Help Message Clarity (IMP-104)** — `aid-stage-log.sh` dispatcher previously listed `log_event`, `log_info`, `log_warn`, `log_error` uniformly in help text, leading users to expect timeline writes from all four. Comment + help message now distinguish: only `log_event` writes to timeline; `log_info`/`log_warn`/`log_error` are stderr-only severity-prefixed echoes.
- **`aid-fsm.sh` Missing `BASH_SOURCE` Guard** — top-level case dispatcher previously exited 1 on unknown args even when the file was sourced (e.g. from bats test fixtures), killing the test process. Dispatcher now wrapped in `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` (same pattern as `aid-stage-log.sh` fix from v2.20.1). Sourcing for testing purposes works cleanly. Existing `_load_aid_fsm` shim in `test-anti-fabrication.bats` becomes redundant but harmless.

## [2.20.1] — 2026-05-12

### Added
- **Verifier Provenance Verification (P037 Phase 1, AID-038)** — `aid-fsm.sh evaluate_compliance_checks` cross-references each `verifier-output-*.md` `_generated_by` field against `timeline.jsonl` `verifier_dispatch_start`/`_complete` events within a ±60s window for subagent mode, or validates `main-context@<commit-sha>` format with SHA verification for inline mode. Detected fabrication forces `compliance.overall: "fail"`.
- **Timeline Dispatch Events** — `pipeline.md` now instructs LLM to emit `verifier_dispatch_start` and `verifier_dispatch_complete` events with payload `{agentId, focus, step_n, evidence_dir, ts}` around every CP1/CP2/CP3 verifier `Agent()` call.
- **Honest Mode for No-Subagent Projects** — `.aid-o/config/plugin.yaml` new field `dispatch_mode: subagent | inline` (default subagent). Inline mode requires `_generated_by: main-context@<git-HEAD-sha>` format for verifier outputs; compliance check validates format + SHA existence rather than timeline match.
- **CLI Dispatcher for aid-stage-log.sh** — library now supports `bash aid-stage-log.sh <fn> <args>` invocation in addition to existing source-mode usage. Guard via `BASH_SOURCE[0] == ${0}` keeps source-mode behavior unchanged. Required so `pipeline.md` and `aid-plan.md` LLM-rendered docs can invoke `log_event` directly without a separate source step. Unknown function exits 1 with stderr help message listing available functions.
- **Anti-Fabrication Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-anti-fabrication.bats` (4 tests): verified subagent dispatch produces `provenance_aggregate: all_verified`; missing timeline events produce `fabricated` + `overall: fail`; inline mode with valid SHA produces `all_inline` + `pass`; CLI dispatcher regression test.

### Changed
- **`evaluate_compliance_checks` Schema** — `verifier_outputs` object now carries three new `*_provenance` fields (`cp2_per_step_provenance`, `cp3_code_review_provenance`, `cp3_security_provenance`) plus aggregate `provenance_aggregate: "all_verified" | "all_inline" | "mixed" | "fabricated" | "unknown"`. Pre-Phase-1 compliance.json files backfilled via `aid-compliance-backfill.sh` Step C (idempotent merge, adds `provenance: unknown` audit note attributing the migration to P037).

### Fixed
- **Compliance Telemetry Honesty** — post-Session-B telemetry (n=8 EPICs reporting 100% pass on all 4 dimensions) was previously vulnerable to fabricated `_generated_by` metadata. P023 reflection (NR 5, 2026-05-11) documented one such case in WAN project where agent wrote verifier outputs in main context but signed them as `aid-orchestrator:verifier@cp{2,3}-*`. Phase 1 enforcement detects this class of cheating.
- **`verify_provenance` TZ Bug** — jq <1.7 silently honors local TZ in `fromdateiso8601` even with `Z` suffix, producing a 1-hour offset on non-UTC hosts (CEST/PST/etc) and reading every dispatch as fabricated. Both `jq -s` invocations in `verify_provenance()` are now prefixed `TZ=UTC` so date parsing matches the `date -d`-derived `$min`/`$max` UTC epochs. Surfaced by Step 5 bats smoke test on CEST host.

## [2.20.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Check 17e (CLI Invocation Grounding)** — `plan-writing.md` Completeness Gate extended with 7th grounding category: for every cited `bash <script> <args>` in Implementation Detail blocks or step examples, verify the args against the actual script interface via `<script> --help` (preferred) or `head -100 <script>` (fallback). Mismatched signatures → REVISE_REQUIRED with suggested correction. Empirical: P035 C1 (2026-05-10) — plan cited a `--state-file` flag that did not exist in `aid-run-gates.sh` at write time; CP1 caught it on the 2nd pass.
- **Completeness Gate Check #19 (Design Defeat Detection)** — semantic LLM check active for plans with `type: bug-fix` in frontmatter. Reviewer answers Q1 (which precondition is being fixed?), Q2 (does the new code-path go through that same precondition?), Q3 (if not, is the bypass explicit + justified?). Q2:no + Q3:no → REVISE_REQUIRED. Pre-screening heuristic (mechanical) auto-activates #19 when goal/context contains fix/fail/bypass/precondition/validation AND the plan mutates `fsm-state.yaml` or `state.yaml` directly without a `cmd_<wrapper>` invocation. Heuristic explicitly EXCLUDES release/version mutations (CHANGELOG, README, marketplace.json, plugin.json, files in `release-policy.yaml` `version_files[]`) to prevent false positives on release plans. Empirical: P035 C2 — `yq -i '.state = "GATES"'` bypassed `cmd_transition()` and would have silently defeated the fix's own purpose.
- **Plan Type Taxonomy (`type:` frontmatter field)** — `defaults/templates/plan.md` now defines an enum `type: regular | bug-fix | refactor | docs` controlling which Completeness Gate checks activate per plan type. Default if missing: `regular`. Legacy `type: plan` (P001-P035 convention) treated as alias for `regular` — no migration required. Documented in new `## Plan Type` template section with a 4-row activation table.
- **`/aid-plan write` Mode Step 9 (CP1 Plan Quality Review)** — write mode extended from 8 to 9 steps; Step 9 mirrors brainstorm Step 9 (verifier dispatch with `docs-review` focus, codebase grounding pass, save review to `.aid-o/work/cp1-review-{plan_id}.md`). Activates #19 when `type: bug-fix` or pre-screening matches. Skip via `review_checkpoints.cp1_plan_review: false`. Closes the gap where plans written through `/aid-plan write` previously had no post-write quality review.
- **CP1 Verifier EVIDENCE REQUIREMENT** — Step 9 verifier prompt now requires concrete evidence (`command_run` + `output_excerpt`) before marking ANY item VERIFIED. Missing evidence → REJECTED with auto-retry; max 2 retries then ESCALATION. Applies to all #17 sub-checks + 17a-d + 17e + #19 (Q1/Q2/Q3 must cite plan path:line + codebase path:line). Empirical: P035 C3 — three bats helpers cited as "existing" from memory; none existed.
- **`test-plan-quality-enforcement.sh` Smoke Test** — bash smoke test exercising all 4 enforcement layers against a deliberately-defective fixture plan: layer 1 (extract `bash <script> --flag` + verify against real interface, with SKIP for already-shifted baseline), layer 2 (3-conjunctive heuristic positive + release-mutation negative control), layer 3 (count `^9.` in Mode: Write Plan section), layer 4 (header + field-name hits for EVIDENCE REQUIREMENT). Auto-discovered by `run-all-tests.sh`.

## [2.19.1] — 2026-05-10

### Fixed
- **`aid-release.sh` CHANGELOG-rename anomaly (IMP-093)** — observed 3× across v2.18.3 + v2.19.0 releases: when a `## [X.Y.Z]` header was pre-written for the upcoming release (PM/agent edited CHANGELOG before invoking script), the previous logic did a blind `sed`-replace on the newest header and silently collapsed the pre-written entry's history. Fix: detect actually-released version from `plugin.json`/`marketplace.json`/`package.json` (not CHANGELOG header) and route through new `update_changelog` helper that has 3 branches: (a) header matches new_version → skip rename (entry already correct), (b) header matches released version → bump existing header (existing behavior), (c) header is some other version → prepend new entry above (preserves history). 3 new bats assertions in `test-aid-release.bats` cover all 3 branches.

### Notes
- **README regex pattern mismatch** — second part of IMP-093 diagnosis showed that `.aid-o/config/project.yaml` regex patterns like `"Plugin: {VERSION}"` don't match actual content `**Plugin:** 2.X.Y` (markdown bold prefix missing in pattern). Consumer projects must update their `.aid-o/config/project.yaml` regex patterns to escape `**` for sed: e.g., `"\\*\\*Plugin:\\*\\* {VERSION}"`. This repo's `.aid-o/config/project.yaml` (gitignored) was updated locally; downstream projects need to edit theirs once if affected.

## [2.19.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Checks 17a–17d** — `plan-writing.md` Completeness Gate extended with 4 new grounding categories aimed at empirical gaps from P019/P021/P032: (17a) backlog ID grounding via whole-plan `\bT-[0-9]+\b` regex + `git log --since="24 hours ago" --grep` — empirical: P021 T-132/T-133 reserved by commit 1907e77 same morning; (17b) test directory convention via POSIX `find tests/ -type f -name "*<basename>*"` — empirical: P021 plan said `tests/integration/`, reality `tests/unit/`; (17c) DB-field semantics via `[A-Z][a-zA-Z]+\.[a-z_]+` regex + `grep` on models.py for stored Column vs `@property`/computed — empirical: P021 assumed automatic, reality stored Column; (17d) file removal grounding via `ls <path>` existence check — empirical: P019 `must_not_exist` file actually existed at EPIC end. EVALUATION counter bumped 18 → 22.
- **`commands/aid-plan.md` Step 9 Verifier Prompt Extension** — verifier dispatch prompt extended with extraction patterns and verification commands for the 4 new grounding categories. Each category gets explicit VERIFIED/ABSENT semantics and REVISE_REQUIRED conditions. Backlog ID ABSENT accepts "T-NNN to be allocated at plan-write time" as a plan-allocation candidate.
- **`defaults/templates/plan.md` Resources Verification Block** — new section between Constraints and Risks with 12 checkbox items: 6 (Existing Resources from #17) + 4 (Plan Assumptions from #17a-d) + 2 (Resolution gates). Auto-populated by `/aid-plan` Step 9 verifier dispatch; PM-visible manual review checklist. Detection scope clarified as whole-plan body scan — no `related_backlog` or similar field required.
- **`test-cp1-grounding.sh` Smoke Test** — bash smoke test that constructs a deliberately-broken plan with violations across all 4 sub-checks and verifies extraction patterns produce correct outputs. POSIX-only (`command -v find` guard, no `fd` dependency), trap-cleaned tmpdir, 5 PASS branches.

## [2.18.3] — 2026-05-10

### Added
- **`aid-fsm.sh advance-to-gates` Atomic Command** — single command runs gates and routes through `cmd_transition EXECUTE GATES` on success. Eliminates the `gates_no_generated_by` chicken-egg precondition fail (P020 8×, P021 4× — 12 friction events across 3 EPICs). Atomicity: state changes only on full success; gates failure leaves state at EXECUTE (never modified). No new state added — `VALID_STATES` and `VALID_TRANSITIONS` unchanged. Single source of truth for preconditions remains `check_preconditions` (`_generated_by`, `fsm_check_verifier_output`, `fsm_check_grandfather`).
- **Bats Coverage for advance-to-gates** — `test-aid-fsm.bats` expanded from 14 to 18 assertions covering all branches: success path, gates-fail path (state stays EXECUTE), missing CP3 outputs (cmd_transition rejects after gates pass), and aid-run-gates.sh env-var bypass behavior with and without `AID_GATES_TRIGGERED_BY_FSM=1`. New `test-helpers.bash` helpers: `seed_test_state_files`, `setup_passing_execution_yaml`, `setup_failing_execution_yaml`, `write_valid_verifier_output`.

### Changed
- **`aid-run-gates.sh` State Guard** — accepts env-var bypass `AID_GATES_TRIGGERED_BY_FSM=1` as the signal that the caller is `cmd_advance_to_gates`. Strict equality check (`=="1"`) prevents accidental bypass via truthy values. Manual two-step flow (state==GATES + run-all without env var) remains fully backward-compatible. Error message now hints at the atomic `advance-to-gates` alternative when state==EXECUTE without the env var.
- **`pipeline.md §5 GATES State`** — adds Recommended Flow (v2.18.3+) subsection documenting `aid-fsm.sh advance-to-gates`; preserves Manual Two-Step Flow subsection for debugging and crash recovery. Both flows fully documented with semantics, env-var signal, and timeline events.

### Fixed
- **`gates_no_generated_by` Precondition Fail Class** — empirical motivation for the atomic command: P020 had 8 such failures, P021 had 4 — 12 friction events across 3 EPICs from a single root cause (chicken-egg between gates runner state guard and transition's `_generated_by` check). Target post-deploy: 0 fails of this type.

## [2.18.1] — 2026-05-09

### Fixed
- **`aid-diagnostic.sh` 3 bugs** — (1) Branch hygiene now reads from `fsm-state.yaml` instead of `state.yaml` (which is the JSON steps array and has no `branch:` field); was reporting 88–100% "missing" for all projects. (2) Deploy era loop adds `post-session-b` so post-Session-B EPICs appear in the era distribution table — were previously silently dropped. (3) `collect_precondition_fail_reasons` → `collect_fsm_fail_reasons` extends jq filter to capture `fsm_increment_fail` and `fsm_done_advance_fail` in addition to `fsm_precondition_fail`; was missing 52% of all FSM fail events (the dominant category: `verify_no_*` format-discovery failures).

## [2.18.0] — 2026-05-08

### Added
- **CP2 Per-Step Verifier Pre-Filter** — `aid-prefilter.sh` classifies each step's git diff as `SKIP` (docs/config/test only, exit 0), `RUN` (code changed, exit 10), or `FAIL` (hardcoded secret/credential detected, exit 20). `cmd_increment_step` reads the classifier verdict and refuses to advance past a FAIL classification; SKIP bypasses CP2 verifier dispatch entirely. `pre-filter-rules.yaml` holds the rule set (docs patterns, secret patterns, code extensions). Closes the CP2 dead-weight problem where verifier was dispatched on pure-docs commits, burning tokens with no signal.
- **CP3 Integration Review Enforcement** — `EXECUTE→GATES` precondition now requires both `verifier-output-cp3-code-review.md` and `verifier-output-cp3-security.md` to exist in the evidence dir. Previously the transition was gated only on `current_step >= total_steps`. Missing CP3 outputs produce a specific precondition failure message listing which files are absent.
- **`fsm_handle_force_override` Unified Dispatcher** — replaces 4 inline `--force` bypass blocks with a single `fsm_handle_force_override from to reason state_file timeline_file` function. Validates `--reason` length ≥ 20 chars (short reasons rejected with exit 1 before any state mutation), emits `fsm_force_override` timeline event, writes to `aid-audit-log.sh` audit trail. Consistency: all force paths now go through identical logging — no more "force but no timeline event" edge cases.
- **`aid-audit-log.sh`** — standalone append-only audit log writer (`aid-audit-log.sh append <evidence_dir> <event_type> <json_payload>`). Writes to `evidence/{epic}/{run}/audit-log.jsonl`. Used by `fsm_handle_force_override` and available for future audit-requiring commands.
- **Verifier Nuanced Deprivation Context** — `agents/verifier.md` updated with classification-aware dispatch: verifier receives pre-filter classification + the specific diff that triggered RUN so it can focus on the actual change rather than the full step output. Adds step-level `## Memory Used` / `## Memory Written` enforcement to verifier output schema.
- **Compliance `verifier_outputs` Object Schema** — `compliance.json` now records per-step CP2 outcomes as an object (`{step_N: {classification, verdict, ts}}`). `evaluate_compliance_checks` validates presence and structure. `write_compliance_json` populates the field from step-verify evidence.
- **Compliance `deploy_era` Three-Tier Field** — `compliance.json` carries `deploy_era: pre-session-a | post-session-a | post-session-b` based on `DEPLOY_DATE` marker comparison. Enables longitudinal trend filtering: `--era post-session-b` sees only post-Session-B EPICs, `--era latest` auto-resolves to newest era present in evidence tree.
- **`aid-compliance-report.sh --era` + `--compare`** — `--era <name>` filters aggregated report to one deploy era; `--era latest` auto-resolves. `--compare ERA1,ERA2` produces side-by-side dimension table (pass/fail/null per era) for Session A → B delta analysis without Excel.
- **`aid-compliance-report.sh --reflect` `force_override` Extension** — `--reflect` pattern detection now includes `force_override` dimension: avg > 1 per EPIC → `🔴 SYSTEMATIC` banner. Average computed via integer arithmetic (`avg_x100 > 100`) to avoid floating-point dependency. Feeds the Session A → B "what holes remain" PM gate.
- **`aid-epic-summary.sh` Auto-Generated EPIC Summary (IMP-090 fold-in)** — `done-advance` hook calls `aid-epic-summary.sh generate <evidence_dir>` after `write_compliance_json`. Produces `<evidence_dir>/epic-summary.md` with 5 sections: ✅ Co bylo dodáno (git log since base_commit), ⚠️ Varování a přeskočené kroky (timeline events: branch mismatch, unusual branch, force override, repeated precondition fail, increment-step churn), ❌ Co se nestihlo (audit/curator blocking/L-effort findings), 📋 Co dělat dál PM akce (escalations, force override follow-up, L-effort proposals), 🔍 Honest signal trust level (HIGH/MEDIUM/LOW from compliance.json + branch heuristics). Best-effort: each section individually guarded with `|| true`; generation failure logs a warning and never blocks release flow. IMP-089 forward-compat: reads `branch_convention:` from `.aid-o/config/project.yaml` if present for feature-branch false-alarm suppression.
- **Plan-Writing Gate #18** — `plan-writing.md` Completeness Gate adds check #18: plans must not contain forbidden phrases that assert completeness without evidence ("already handles", "no changes needed", "existing implementation covers"). Accompanies Gate #17 (codebase grounding) from v2.17.0.
- **bats Suite Expanded to 33 Assertions** — 5 files: `test-aid-fsm.bats` (14, +5 CP2/force assertions), `test-aid-prefilter.bats` (6, NEW — SKIP/RUN/FAIL exit codes + output format), `test-aid-compliance.bats` (4, NEW — --era/--compare/--reflect triple-condition), `test-aid-epic-summary.bats` (2, NEW — 5-section headers + force_override timeline propagation), `test-aid-run-gates.bats` (7, unchanged from v2.16.0).

### Changed
- **pipeline.md §CP2 and §CP3** — full rewrite of both subsections to document v2.18.0 enforced protocol: pre-filter classifier, verifier dispatch conditions, CP2 evidence file naming (`verifier-output-step-N.md`), CP3 mandatory dual-file output schema, fix-loop (gate-fixer → verifier, max 2 iterations).
- **pipeline.md §force_override policy** — new subsection documenting `fsm_handle_force_override` contract: required fields, minimum reason length, audit trail, PM-only authorization, forbidden patterns.
- **pipeline.md Epic Summary** — new subsection documenting IMP-090 5-section schema, per-section data sources, trust level heuristics table, IMP-089 forward-compat note.
- **`aid-fsm.sh plan_json_hash` pipefail guard** — `grep '^plan_json_hash:'` with `set -eo pipefail` caused silent exit when field absent from `state.yaml`. Wrapped with `|| true` guard. Exposed by CP2 SKIP-classification test (step-verify without hash field).

### Fixed
- **`aid-stage-log.sh` JSON array/object prefix corruption** — `log_event` escaped payload before writing to `timeline.jsonl`; payloads starting with `[` or `{` (JSON arrays/objects) were double-escaped on the `data:` field. Added prefix detection: if payload starts with `[` or `{`, write `data: <payload>` verbatim; otherwise apply existing escape. Discovered during CP3 verifier-output path testing.

## [2.17.0] — 2026-05-06

### Added
- **CP1 Codebase Grounding Rule** — `plan-writing.md` Completeness Gate gains check #17 (16 → 17). Plans must verify every named external resource (functions, helpers, file paths, ports, services, commands, env vars) against the real codebase or running infra. Hand-wave like "presumably exists in some lib" or "should be available" is a hard fail. Addresses systematic CP1 blind spot identified in P032 retrospective: 5 PM-authorized resolutions (C1–C5 in P032) were all of this kind — reviewer cannot detect *absence* of helpers/files the plan presumes exist.
- **Verifier Codebase Grounding Pass** — `/aid-plan` Step 9 (CP1 review) verifier dispatch now MUST extract a flat list from the plan of every named function, helper, file path, port, service, command, and env var, and verify each against the real codebase / running infra (`grep`, `ls`, `docker ps`, `command -v`). Each item gets VERIFIED (with location) or ABSENT (mapped to a Create step). Plans with ABSENT items not mapped to Create steps → REVISE_REQUIRED.
- **`aid-compliance-report.sh --reflect`** — lightweight `/aid-reflect` (per AID-013). Per-dimension breakdown (pass / fail / null counts + 10-cell text bar chart) with pattern detection: 0 fails → ✅ green, 1 fail → ⚠️ INVESTIGATE (could be one-off), ≥ 2 fails → 🔴 SYSTEMATIC (hole in Session A enforcement). Recommended-next-action section addresses PM retrospective from P032: aggregate ≥ 80 % can hide a single dimension failing systematically; per-dimension trend is the actionable signal before Session B brainstorm.

## [2.16.1] — 2026-05-06

### Fixed
- **`aid-compliance-backfill.sh` aborts on legacy v1 evidence** — `set -euo pipefail` caused the backfill to abort on the first vulcan/sousto evidence dir whose `state.yaml` lacked a `branch:` field (`grep` returns 1 → pipefail propagates). Wrapped the `grep | awk` extraction (and the `jq | sort | head` pipeline in `backfill_state_created_at`) in `|| true`. Discovered during the v2.16.0 post-merge deploy run.
- **`aid-compliance-backfill.sh` corrupts legacy v1 JSON state files** — some pre-v2 evidence dirs store `state.yaml` as a JSON array of step objects (legacy `plan_progress.json` format). The backfill appended `created_at: <ts>` directly, breaking JSON validity (the line landed on the same line as the closing `]` because the file lacked a trailing newline). Added file-format detection: if the first non-blank char is `[` or `{`, log a warning and skip stamping. Plus a defensive `printf '\n'` guard before any append on YAML files. Live tree was repaired with `sed` post-incident; no data loss.

## [2.16.0] — 2026-05-05

### Added
- **Branch Enforcement in PRE-FLIGHT** — `aid-fsm.sh init` automatically creates `task/{epic_id}/main` from main/master/develop, detects mismatch with copy-paste fix, respects worktree mode. Closes AID-001 (65% of pre-Session-A state.yaml claimed `branch: main` with no actual task branch, breaking done-advance audit trail).
- **Real Gates Execution Provenance** — `aid-run-gates.sh` rewritten with yq parsing, emits `gate_runner_start` / `gate_runner_complete` timeline events and writes `_generated_by` / `_generated_at` / `_command_log` provenance fields into `gates_report.json`. EXECUTE→GATES precondition mechanically rejects hand-written reports.
- **Lazy execution.yaml Creation** — `aid-init` (and `aid-fsm.sh init` auto-recovery) generates per-project `execution.yaml` from auto-detected stacks (Python, TypeScript, Go, Rust, bash) with `# DEPENDENCY` hint comments per gate command. Closes AID-006 (71% of projects had no execution.yaml).
- **Compliance Telemetry** — `done-advance` writes per-EPIC `compliance.json` with 6-dimension schema (3 measured for Session A, 3 `null` for Sessions B/C). Standalone `aid-compliance-backfill.sh` for one-shot pre-deploy backfill (also stamps mid-FSM `state.yaml.created_at` per CP1 M2). Aggregator `aid-compliance-report.sh` produces pre vs post comparison with `--since` and `--era` filters.
- **svc-mcp-tg-bot MCP Server** — new Docker service in `services/mcp-tg-bot/` (FastMCP, stdio + HTTP transport on port 8817 — see Removed section for the legacy MCP that previously held this port). `send_message` tool with HTML parse_mode default. Token shared via `/opt/eco/services/.env`. Includes `docker-compose.snippet.yml` for PM to integrate into `/opt/eco/services/docker-compose.yml`.
- **FSM Repeated-Fail Telegram Alert** — `aid-fsm.sh` emits `fsm_precondition_repeated_fail` event and best-effort `try_telegram_alert()` HTTP POST to localhost:8817 when same precondition fails ≥ 3 times on the same EPIC.
- **Parametrized Diagnostic Script** — `aid-diagnostic.sh` reusable forensic analyzer (refactored from Krok 0 logic, supports `--evidence-root`, `--output md|json`, `--limit`).
- **bats Unit Test Suite** — 16 assertions across `test-aid-fsm.bats` (9), `test-aid-run-gates.bats` (3), `test-aid-init.bats` (4) covering all new FSM preconditions, gate runner provenance, and stack detection. Runs via `bats plugins/aid-orchestrator/scripts/tests/bats/`.
- **Dependency Pre-flight Script** — `aid-check-deps.sh` verifies `bash`, `git`, `jq`, `yq` (mikefarah variant only), plus optional `bats`, `direnv`, `docker`, `curl`. cmd_init now has fail-fast guard for `git` + `jq`.
- **README Requirements Section** — explicit dependency table in plugin README listing required runtime, optional dev, and optional Telegram-alerts tools with install commands per OS.
- **Worktree Development Guide** — plugin README section + committed `.envrc` with `AID_PLUGIN_PATH=$(pwd)/plugins/aid-orchestrator` and `PATH_add` for direnv-driven worktree workflows.
- **DEPLOY_DATE Marker File** — `plugins/aid-orchestrator/DEPLOY_DATE` (ISO 8601 UTC) consumed by `fsm_check_grandfather()` as the pre/post-Session-A threshold. Fallback chain: `AID_DEPLOY_DATE` env → `${AID_PLUGIN_PATH}/DEPLOY_DATE` → `${SCRIPT_DIR}/../DEPLOY_DATE`.

### Changed
- **pipeline.md** — three subsection rewrites: PRE-FLIGHT branch-enforcement catalog (5 HEAD states + 2 timeline events), GATES EXECUTE→GATES precondition with `_generated_by` requirement and grandfather caveat, DONE phase Compliance Telemetry section with 6-dimension table and null semantics caveat.
- **state.yaml schema** — adds `created_at` field (ISO 8601 UTC) used by grandfather logic for backward-compat with pre-deploy EPICs.
- **lib/aid-stage-log.sh** — new `log_info` / `log_warn` / `log_error` helpers with `[INFO]/[WARN]/[ERROR]` severity prefix on stderr (greppable, exported alongside `log_event`).
- **fsm_precondition_fail timeline event** — now carries `reason` field (set by individual precondition cases via `_PRECONDITION_FAIL_REASON`) so `fsm_count_recent_fails` can group repeated failures by failure type.
- **aid-fsm.sh::cmd_init** — overrides caller's `branch` arg ($5) with actual `git rev-parse --abbrev-ref HEAD` after PRE-FLIGHT enforcement so `state.yaml.branch` reflects post-enforcement reality (PM-authorized resolution C3).

### Fixed
- **Branch hygiene gap** — closes the 65% of pre-Session-A `state.yaml` files claiming `branch: main` with no actual task branch. New auto-checkout closes the loop with `done-advance` release sub-phase `git merge`.
- **Fake gates reports** — closes the 0% gate-runner execution evidence in 93 analyzed timelines. Provenance fields make hand-written reports mechanically detectable.
- **Missing execution.yaml** — closes the 5/7 (71%) projects lacking gate config, which forced agents into ad-hoc gate names per EPIC with no cross-project consistency.
- **Mid-FSM EPIC unblock (CP1 M2)** — backfill stamps `created_at:` into existing `state.yaml` from earliest timeline event ts, preventing the ~14 mid-FSM EPICs identified in diagnostic-findings from becoming unresumable post-deploy.
- **aid-run-gates.sh CLI parser** — fixed `${4:-default}` swallowing `--state-file` flag when caller skipped the optional 4th positional, which silently broke `gate_runner_start`/`gate_runner_complete` events for FSM-driven invocations. Regression test added to `test-run-gates.sh`.
- **Test suite git-context invariant** — `test-fsm.sh` and `test-integration-phase1.sh` setup() now `git init` their mktemp dirs so PRE-FLIGHT branch enforcement (new in this version) finds a working tree. Existing tests preserved without behavioral change.

### Removed
- **Legacy `svc-mcp-telegram` MCP (port 8817 takeover)** — the previous general-purpose Telegram MCP at localhost:8817 is decommissioned and replaced by `svc-mcp-tg-bot` on the same port. The old MCP exposed 9 tools (send_message, edit_message, search_dialogs, get_draft, set_draft, get_messages, media_download, message_from_link, delete_message) for general Telegram interaction; the new MCP exposes 1 tool (send_message) focused on AID-internal alerting. PM verified zero call sites in repo before removal (only permissions.yaml whitelist + docs entries referenced it). `defaults/policies/permissions.yaml` updated accordingly: 9 `mcp__shared-telegram__*` whitelist entries collapsed into 1 `mcp__svc-mcp-tg-bot__send_message` entry.

## [2.15.0] — 2026-03-25

### Added
- **Mechanically Enforced FSM** — `aid-fsm.sh transition` now verifies preconditions before allowing state changes: READY→EXECUTE requires `plan.json`, EXECUTE→GATES requires all steps complete, GATES→DONE requires `gates_report.json` with `overall: pass`, ESCALATION exits require `escalation_decision` set
- **`verify-state` Command** — new `aid-fsm.sh verify-state` returns current state + allowed transitions as JSON for LLM orientation
- **`set-field` Command** — new `aid-fsm.sh set-field` for structured state mutations (escalation decisions, custom fields)
- **FSM Audit Trail** — all `aid-fsm.sh` operations (transitions, precondition failures, force overrides) logged to `timeline.jsonl` via `aid-stage-log.sh`
- **`--force` Escape Hatch** — `aid-fsm.sh transition --force` bypasses preconditions with PM approval, logged as `fsm_force_override`
- **Gates State Check** — `aid-run-gates.sh --state-file` refuses to run unless FSM state is GATES
- **Gates Report Persistence** — `aid-run-gates.sh --report-file` auto-writes `gates_report.json` (required by GATES→DONE precondition)
- **Mechanical Enforcement Protocol** — new section in `aid-run.md` with 8 non-negotiable rules for FSM compliance
- **DONE Sub-Phases** — `done_phase: review → release` within DONE state, managed by `aid-fsm.sh done-advance` with evidence-based preconditions (curator-report, audit-report, pm_decision=merge)
- **Reserved Field Protection** — `set-field` rejects writes to `state` and `done_phase` (must use dedicated `transition`/`done-advance` commands)
- **Release Script FSM Guard** — `aid-release.sh` refuses release when `state.yaml` exists with `done_phase != release` (Layer 2 defense)
- **Git Pre-Commit Hook** — FSM guard on `task/*` and `epic/*` branches blocks commits in DONE/review and READY states (Layer 3 defense)
- **Hook Auto-Install** — `/aid-init` installs/upgrades pre-commit hook with marker-based append (coexists with existing hooks)
- **Step Verification Enforcement** — `increment-step` refuses to advance without `step-{N}-verify.md` evidence file (AC checklist + visual check)
- **Agent Dispatch Protocol** — 6 non-negotiable rules in pipeline.md: verbatim plan content, visual assets, post-step AC verification, visual verification for UI, resume-on-failure, visual context dispatch
- **Visual Companion** — browser-based HTML prototype viewer for brainstorming (opt-in, Node.js server adapted from Superpowers). Generates interactive mockups during design sections, saves approved HTML as 4th input type for visual assets pipeline. Per-question visual/text decision taxonomy.
- **Visual Assets Pipeline** — 4 input types (GitHub repo, AI Studio URL, PNG, Visual Companion) → unified `visual-spec.yaml` output; `visual_refs` field in plan.schema.json; visual dispatch protocol in pipeline.md §4; Visual Anchoring requirement in frontend role card; screenshot comparison protocol (MATCH/PARTIAL/MISMATCH); forbidden text-only UI descriptions in plan-writing.md
- **Plan-Level DONE Gate** — `aid-fsm.sh init` blocks cross-plan run if previous plan has unreviewed C+A findings (`ca-review-complete` marker required); enforces "dispatch per EPIC, validate per Plan" model
- **Step-Verify Content Validation** — `increment-step` now requires at least one `- [x]` AC checklist item and one commit hash (7+ hex chars); prevents minimal "Result: PASS" without substance
- **Plan.json Init Warning** — `aid-fsm.sh init` warns when plan.json steps lack `objective` field
- **Per-Project Agent Memory (Qdrant)** — 10-category deep codebase scan (architecture, API, data, UI, config, testing, conventions, security, DevOps/CI-CD, cross-cutting concerns); `memory-mcp.md` skill with entry schema, quality rules (≥20 word summary, real code examples, 5 rejection criteria), store/find protocol, supersede pattern; pipeline §4 memory READ (2-tier context injection ~1500 tokens); pipeline §7 Scanner dispatch at plan boundary; `memory_writes` mandatory in agent output; `## Memory Used` + `## Memory Written` enforced in step-verify by `increment-step`; Auditor Memory Health category (stale detection, conflict detection, coverage check); kondice flow (auditor flags → scanner verifies)

### Changed
- **FSM Valid States** — added ERROR to `VALID_STATES`; added `→ERROR` transitions from READY, EXECUTE, GATES, ESCALATION
- **Escalation Cleanup** — `escalation_decision` field auto-cleared when leaving ESCALATION state
- **Pipeline §3-§6** — each section now documents which FSM preconditions enforce correct behavior

### Fixed
- **Dead Cross-References** — replaced 20+ references to deleted v1 files (dispatch-protocol.md, epic-orchestration.md) with v2 equivalents across 11 files
- **v1 State Names** — replaced v1 FSM states (PM_APPROVAL, CURATOR_RESOLVE, PHASE_CHECK, IDLE) in pipeline.md; added v1 legacy headers to improvement-proposals.md and analytics.md
- **v1 Directory Paths** — updated CLAUDE.md workspace structure from v1 (01-plans/, 04-engine/) to v2 (plans/, work/)
- **Pre-Commit Hook** — removed dead case statement (non-functional code from refactoring)

## [2.6.0] — 2026-03-14

### Added
- **Standards Enforcement System** — two standard sets (`general.yaml` with 26 language-agnostic rules, `vulcan.yaml` with 22 ecosystem-specific rules + 4 severity overrides) selectable during `/aid-init`
- **Standards Gate** — new `standards_compliance` gate in `execution.yaml`, 100% deterministic (pattern/structural/file-exists rules only), custom/LLM rules are auditor-only advisory
- **Standards Audit Category** — new conditional category I) in auditor with full-codebase scan, severity-based scoring (cap 5 violations/rule), 15% weight when active
- **Standards Curator Integration** — hotspot detection (3+ violations of same rule = systemic), `source_type: standards` proposals with auto-approve for S-effort fixes
- **Standards Dispatch Context** — agents receive filtered standards in prompt (gate-blocking first, filtered by language), omitted when `standards.active == 'none'`

### Changed
- **Auditor Category Count** — 8→9 categories (5 mandatory + 4 conditional), weight redistribution when standards active (Code 30→25%, Security 30→27%, Docs 25→23%)
- **Agent Execution Summary** — includes `Standards violations noted: {count}` for trend tracking
- **Init Flow** — standards profile selection (general/vulcan/none) with `project.yaml → standards` config block

## [2.5.0] — 2026-03-13

### Added
- **Plugin Path Discovery** — `/aid-init` discovers and caches plugin installation path in `config/plugin.yaml`; Script Execution Protocol in `agent-core.md` teaches all agents how to resolve `scripts/X.sh` references
- **Brainstorming Question Format Template** — concrete format with Effort/Risk per option, recommendation with "Why not" reasoning, and webhook delivery example
- **Brainstorming Handoff Summary** — plan-writing presents decision summary + 6 options including `/aid-run --auto` with `autonomous_mode` prerequisite warning
- **Superpowers Conflict Resolution** — CLAUDE.md template includes conflict table (brainstorming, writing-plans, executing-plans → AID equivalents); 3 `skill_conflicts` entries in `orchestration.yaml`
- **Documentation Gate Enforcement** — path-pattern correlation: `docs_updated` gate fails only when API-path files changed without doc updates; auditor escalates missing API docs to high severity

### Changed
- **PRE-FLIGHT Plugin Verification** — `/aid-run` and `/aid-do` verify `plugin_path` on startup with cache invalidation fallback
- **Dispatch Context** — `agent-protocol.md` input format includes `plugin_path` for dispatched agents
- **Brainstorming Rule 8** — now explicitly requires effort estimate (S/M/L) and risk (L/M/H) per option

### Fixed
- **`/aid-plan-epic` stale references** — replaced with `/aid-plan --epic` across brainstorming, plan-writing, pipeline, and planner skills (command merged in v2.0)
- **`aid-plan.md` step count** — Steps 1-7 showed `/8` denominator instead of `/9` after CP1 review was added as Step 9

## [2.4.0] — 2026-03-12

### Added
- **PM Merge Decision Gate** — DONE state presents combined curator+auditor summary, PM explicitly chooses MERGE/FIX/ABORT before code reaches main
- **Parallel Curator+Auditor** — Both dispatch simultaneously in DONE state, reducing post-completion wait time
- **Auditor Auto-Fix** — S and M effort recommendations trigger gate-fixer dispatch pre-merge via new `recommended_fixes` output field
- **70/30 Design Principle** — Documented deterministic-first philosophy in pipeline §1: 70% bash, 30% LLM
- **Review Pre-Filter** — Bash regex checks (secrets, SQL injection, eval, debug) run before CP2/CP3/CP6 verifier dispatch, skipping LLM when unnecessary
- **Per-Escalation Templates (E1-E8)** — Each trigger shows specific context, findings, affected files, and available commands

### Changed
- **DONE State Flow** — Merge moved from step 3 to step 13 (after PM approval); prevents premature merge before review
- **Curator Auto-Evaluation** — Tier 2 default: M-effort proposals now auto-approved (was: deferred to PM)
- **PM Interaction Points** — Enhanced output at READY (gate details), CP1 (severity summary + 3 options), CP6 (evidence paths), scope warnings (actionable commands), and ESCALATION (per-type context blocks)
- **Auditor Dispatch Timing** — Now dispatched pre-merge in parallel with Curator (was: post-merge sequential)

## [2.3.0] — 2026-03-12

### Added
- **Review Checkpoints (CP1-CP6)** — Automatic verifier dispatch at 6 pipeline milestones: post-brainstorm plan review, per-step code review, pre-GATES integration review, curator proposal validation, auditor critical-finding gate, and post-/aid-do quick review
- **Fix Loop Protocol** — Verifier findings with Critical/High severity trigger gate-fixer dispatch + re-verification (max 2 iterations), replacing reactive gate-failure-only fixes
- **Critical Finding Gate (CP5)** — Auditor critical findings now block DONE state, triggering ESCALATION instead of proceeding to queue
- **Review Checkpoint Configuration** — New `review-checkpoints.yaml` policy file with per-checkpoint toggles, fix-loop settings, and trivial-skip threshold
- **Escalation triggers E7, E8** — Verifier review failure after fix loop; auditor critical security finding
- **Pipeline §13** — New Review Checkpoint Protocol section as authoritative reference

### Changed
- **Verifier agent** — Expanded from on-demand to automatic dispatch with fix-loop integration and checkpoint-specific context assembly
- **Gate-fixer agent** — Now accepts verifier review findings as input (source: `verifier_review`), not just gate failures
- **Auditor agent** — Critical findings produce `blocking_findings` flag that blocks DONE transition
- **Pipeline §4-§8** — Updated with review checkpoint dispatch points at EXECUTE, GATES, DONE, and FAST MODE

### Fixed
- **Broken cross-references** — Fixed 5 stale v2 migration references: auditor.md, gate-fixer.md, curator.md, planner.md pointed to non-existent `epic-orchestration.md`/`retry-engine.md`; pipeline.md referenced non-existent `dispatch-config.yaml`

## [2.2.0] — 2026-03-11

### Added
- **Context Persistence (Interim Document)** — `/aid-plan` now creates `.aid-o/work/interim-P{NNN}.md` at session start, updated after each step with full conversation detail; survives context window overflow and session interruptions; auto-deleted on plan completion
- **Concurrent brainstorm detection** — checks for existing interim docs before starting new brainstorm, offers resume or fresh start
- **ID Allocation Procedure** — documented read-increment-write protocol for counter.yaml in run-management ID System section

### Fixed
- **Dead `epic-orchestration.md` references** — updated brainstorming.md, plan-writing.md, and run-management.md to reference run-management ID System instead
- **Abort text accuracy** — "no files created" corrected to "no plan written, interim doc preserved"
- **plan-writing.md missing interim cleanup** — added MUST rule 15 to delete interim doc after successful plan write

## [2.1.1] — 2026-03-10

### Fixed
- **`.gitignore` missing from `/aid-init`** — Init now creates `.gitignore` appended to project root, ignoring runtime artifacts (evidence, quick logs, timeline.jsonl, queue.yaml) while keeping design artifacts versioned
- **Defaults `.gitignore` outdated** — Updated from v1 paths (`.aid-o/04-engine/`) to v2 structure

## [2.1.0] — 2026-03-10

### Changed
- **Brainstorming skill refactored** — 34% smaller (415→272 lines) with 8 new capabilities: scope decomposition, MoSCoW prioritization, risk assessment protocol, prior-plan lookup, pre-decided solution handling, context-loss recovery, workflow/AI questioning hint, Docker Compose recommendation
- **Design section templates extracted** — Moved to `defaults/templates/design-sections.md` as standalone reference, reducing brainstorming skill size while preserving all templates

### Removed
- **Obsolete planning docs** — Removed CRITICAL-ASSESSMENT.md and REDESIGN-PLAN-v2.md (completed, no longer relevant)

## [2.0.0] — 2026-03-03

### Breaking Changes
- **11-state LLM FSM → 6-state bash FSM** — States reduced from IDLE/PLANNING/PLAN_REVIEW/EXECUTING/PHASE_CHECK/NEXT_PHASE/GATES/GATE_RETRY/ESCALATION/CURATOR_RESOLVE/PM_APPROVAL/DONE to READY/EXECUTE/GATES/ESCALATION/DONE/ERROR. State transitions enforced by `aid-fsm.sh`, not LLM instructions.
- **27 skills → 8 skills** — Consolidated from 27 cross-referencing skills to 8 focused skills (agent-protocol, pipeline, planner, brainstorming, quality-gates, run-management, memory, role-cards). Removed: epic-orchestration, dispatch-protocol, gates-engine, retry-engine, first-aid-controller, auto-escalation, auto-done-state, parallel-dispatch, cost-optimization, epic-queue, slack-mcp, workflow-intelligence, and 15 others.
- **18 agents → 7 agents** — Consolidated from 18 role-based agents to 7 controller agents (implementer, verifier, gate-fixer, curator, auditor, project-scanner, run-validator). Removed: architect, backend, frontend, domain, qa, security, observability, docs-writer, release, code-reviewer, docs-reviewer, lessons-extractor, quality-gates-runner.
- **17 commands → 8 commands** — New unified commands: `/aid-do`, `/aid-plan`, `/aid-run`, `/aid-status`, `/aid-help`, `/aid-init`, `/aid-audit`, `/aid-stop`. Removed: `/aid-brainstorm`, `/aid-plan-epic`, `/aid-run-epic`, `/aid-first-aid`, `/aid-setup`, `/aid-epic-queue`, `/aid-epic-status`, `/aid-research`, and 9 others.
- **Directory structure** — `.aid-o/04-engine/` → `.aid-o/work/`, `.aid-o/02-epics/` → `.aid-o/tasks/`, `.aid-o/03-config/` → `.aid-o/config/`. Init creates 10 files (down from 40+).
- **10 policy YAMLs → 3** — `execution.yaml` (gates + dispatch), `project.yaml` (stack + preferences), `permissions.yaml` (agent permissions). Removed: decision-policies.yaml, dispatch-strategy.yaml, gates.yaml, memory-config.yaml, slack-config.yaml, and 5 others.

### Added
- **Fast Mode (`/aid-do`)** — < 2 min overhead for tasks < 2h. Creates Q-NNN.md quick log, skips full EPIC pipeline. Automatic scope detection.
- **Bash FSM (`aid-fsm.sh`)** — Deterministic 6-state finite state machine. States: READY → EXECUTE → GATES → DONE (happy path), with ESCALATION and ERROR branches. All transitions validated in bash, not LLM.
- **Bash gate runner (`aid-run-gates.sh`)** — Deterministic quality gate execution with JSON output, timeout handling, retry logic. Replaces LLM-manual gate evaluation.
- **Pipeline automation scripts** — `aid-auto-pipeline.sh` (orchestrator), `aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`. All deterministic operations moved from LLM to bash.
- **Stage logging (`aid-stage-log.sh`)** — Structured timeline.jsonl event logging with standardized format across all pipeline operations.
- **Token estimator (`aid-token-count.sh`)** — Character-based token estimation for prose/code/mixed content types.
- **`@aid/contract` package** — Shared TypeScript types for all `.aid-o/` data formats (AidFsmState, AidState, AidGatesReport, AidTimeline, etc.).
- **Progressive help (`/aid-help`)** — 4-level disclosure: Level 0 (cheat sheet), Level 1 (command detail), Level 2 (architecture), Level 3 (troubleshooting).
- **Scope check gate** — `scripts/gates/scope-check.sh` verifies implementation stays within EPIC-defined file scope.
- **173 tests across 13 suites** — Up from 88 tests / 6 suites in v1.7.0. Full coverage of FSM, gates, pipeline, stage logging, token counting, scope checking.

### Changed
- **~87% token reduction** — Plugin prompt tokens reduced from ~400K to ~50K by consolidating skills/agents/commands and moving deterministic logic to bash scripts.
- **`/aid-plan` merges 3 old commands** — Replaces `/aid-brainstorm` + `/aid-write-plan` + `/aid-plan-epic` into single progressive workflow.
- **`/aid-run` merges 2 old commands** — Replaces `/aid-run-epic` + `/aid-first-aid` with unified command supporting `--auto` flag.
- **`/aid-status` merges 2 old commands** — Replaces `/aid-epic-status` + `/aid-epic-queue` with combined view.
- **`/aid-init` merges `/aid-setup`** — Single idempotent init command creating 10-file `.aid-o/` structure with stack auto-detection.
- **Role cards consolidated** — All agent role definitions in single `role-cards.md` (8 roles + 4 focus cards) instead of 18 separate agent files.
- **Pipeline skill consolidated** — Single `pipeline.md` replaces 14 old orchestration skills, documenting all 6 FSM states.
- **Evidence paths** — `stage_log.jsonl` → `timeline.jsonl`, `plan_progress.json` → `state.yaml`.
- **aid-server paths** — Updated all Express routes and WebSocket handlers for v2 `.aid-o/` structure.

## [1.7.0] — 2026-02-28

### Added
- **Path Traversal Guards** — defense-in-depth (regex + resolve+startsWith) path validation on pipeline theater, evidence, and decision routes preventing CWE-22 filesystem traversal via `epicId`/`runId` parameters
- **GUI CORS Middleware** — `cors()` middleware on the aid-gui Express server with `AID_GUI_CORS_ORIGINS` env var support, defaulting to localhost:5173 and localhost:3000
- **Agent Name Frontmatter** — all 18 agent files now have `name:` field in YAML frontmatter matching the filename stem, enabling plugin validation
- **Master Test Runner** — `run-all-tests.sh` discovers and executes all test suites with unified pass/fail reporting (88 tests across 6 suites)
- **Curator Dispatch Regression Tests** — Suite F (5 tests) verifying unconditional Curator dispatch and state-entry logging in gate-evaluation.md and first-aid-controller.md
- **Phase Marker Documentation** — `plan-writing.md` Phase Markers subsection with exact format, rules, regex, and "do NOT use" examples for LLM-generated plans
- **PARALLEL_EXECUTING Sub-State** — `epic-state-machine.md` documents the FIRST AID parallel execution sub-state with activation criteria and safety limits
- **AI Companion Project Context** — system prompt auto-built from CLAUDE.md, package.json, pipeline state, EPIC queue, plans, decisions, ideas backlog, and project structure on every message
- **AI Companion Tool Use** — 7 tools (readFile, listDirectory, searchContent, readYaml, readEpic, readPlan, getPipelineState) giving the companion full codebase access with sandboxed paths and 8-step tool call limit
- **Voice Dictation Recording Bar** — waveform visualization via AudioContext AnalyserNode, elapsed timer, live interim text display (Web Speech API), and one-click stop-and-send flow
- **Whisper Auto-Detection** — background probe on mount detects Whisper availability; uses Web Speech API as primary (Czech `cs-CZ` support) with Whisper upgrade when OPENAI_API_KEY is set
- **FIRST AID Wrapper State Mapping** — FIRST_AID_INIT, QUEUE_PROCESSING, QUEUE_ADVANCE, FIRST_AID_COMPLETE mapped to medical labels (Triage, Operating, Next Patient, All Clear) with FSM colors and active state detection
- **Satellite Card Alternation** — Ward, Lab, Escalations, Vitals cards alternate between current and total values every 4 seconds with AnimatePresence transitions

### Changed
- **CORS Wildcard Handling** — `AID_CORS_ORIGINS=*` now correctly enables wildcard CORS instead of creating a single-element array `['*']`
- **Default Server Binding** — both aid-server and aid-gui default to `127.0.0.1` (loopback only) instead of `0.0.0.0`, preventing unintentional network exposure; Docker containers retain `0.0.0.0` via explicit env var
- **GUI README Replaced** — removed Gemini/AI Studio boilerplate, replaced with accurate AID Dashboard GUI documentation including local setup and aid-server dependency
- **Root README Version** — updated from v1.5.0 to v1.6.0
- **Brainstorming Step Count Standardized** — all documentation (README, Docusaurus, aid-help) now references 8-step brainstorming matching the actual skill lifecycle
- **aid-run-epic Prerequisites** — removed false auto-generation claim; `plan.json` must pre-exist via `/aid-plan-epic`
- **Zombie Backlog Cleanup** — moved 7 already-fixed entries (IMP-010/035/049/050/057/059/067) from Active to Implemented, correcting count from 62 to 55
- **EPIC ID Regex Hardened** — `aid-auto-pipeline.sh` now accepts alphanumeric plan IDs with internal hyphens (e.g., `E-TEST-001-1_2`)
- **Dependency Parser Enhanced** — `aid-plan-to-epic.sh` supports range expansion (`Steps 3-7`), trailing text stripping, cross-phase dependency filtering, and deduplication
- **Scope Generation Granularity** — `aid-plan-to-epic.sh` generates file-level paths in EPIC scope when plan steps have `**Files:**` sections, improving FIRST AID parallel detection accuracy
- **EPIC Template Scope Guidance** — template includes guidance comments encouraging file-level path declarations over broad directories
- **Curator Dispatch Made Unconditional** — `gate-evaluation.md` and `first-aid-controller.md` now mandate Curator dispatch at CURATOR_RESOLVE regardless of discovered_issues
- **QUEUE_PROCESSING Auto-Mode** — `first-aid-controller.md` includes parallel dispatch checklist cross-referencing `aid-first-aid.md` sections 3.1-3.5
- **Curator Auto-Defer Threshold Raised** — auto-mode now defers only effort:L proposals to backlog; effort:S and effort:M are fixed inline, increasing autonomous fix rate
- **Command Center State Labels** — all FSM states renamed to medical/hospital theme (On Call, Diagnosis, Prescription, Infusing, Vital Signs, Second Opinion, Lab Results, Doctor's Orders, Recovery, Discharged, Code Red)
- **Satellite Cards Data Sources** — Ward shows queue running+waiting / completed+failed; Lab shows gate runs+retries / audit score; Escalations shows budget usage / total escalations; Vitals shows steps executed / total events
- **EPIC Runs Display** — shows last 5 completed (most recent first) instead of first 5
- **Voice Flow Simplified** — removed confirm step; recording stops and sends directly (one action instead of three)
- **CommandPalette Voice** — transcript sends as message directly instead of inserting into filter input
- **Companion Open Speed** — status and sessions pre-fetched on project select; palette/panel opens instantly without network delay
- **Pipeline API Extended** — `/pipeline` endpoint returns full autoModeSession with escalation budget/count and aggregate counters (epicsCompleted, epicsFailed, totalStepsExecuted, totalGateRuns, totalGateRetries, totalEscalations)

### Fixed
- **WebSocket Replay Parsing** — `dispatchReplay()` now reads raw stage log entries directly instead of expecting non-existent `.entry` wrapper, fixing Pipeline Theater replay after reconnection
- **CSS Custom Property Generation** — `.replaceAll('_', '-')` replaces all underscores in FSM state names for correct CSS variable references (was `.replace` which only fixed the first)
- **Curator Input File References** — corrected from `step_output.json` to `output.md` + `diff.patch` matching actual agent output format
- **Queue Field Name** — `scripts/README.md` corrected `queued_at` to `added_at` matching actual queue schema
- **Queue Field Name Mismatch** — server returned `data.entries` but GUI expected `data.queue`, causing queue entries, elapsed time, and EPIC runs to never display
- **Topbar Voice Integration** — replaced inline mic recording logic (~90 lines) with shared VoiceButton component using `compact` prop

## [1.6.0] — 2026-02-28

### Added
- **Pipeline Scripts** — 5 bash scripts (`aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`, `aid-auto-pipeline.sh`) for deterministic Plan→EPIC→json→run→queue conversion replacing LLM-driven operations
- **Shared Script Library** — `scripts/lib/common.sh` with 7 portable bash functions (YAML parsing, section extraction, slugify, prerequisites check, error formatting, timestamps)
- **Script Documentation** — `scripts/README.md` with full interface contracts, argument tables, exit codes, data flow diagram, and JSON manifest schema for all 5 pipeline scripts
- **EPIC Template Dependencies Section** — structured Dependencies section with Internal/External/Queue subsections replacing flat placeholder
- **Deterministic Work Detection Audit** — new audit category I) scanning commands, skills, and agents for LLM-performed template filling, structured parsing, and file manipulation that could be replaced by scripts, with false positive filters and -10 cap scoring
- **Pipeline Test Suite** — 76 tests across 6 test scripts (40 unit, 16 integration, 20 regression) with 3 fixture plan files covering single-phase, multi-phase, and cross-plan dependency scenarios

### Changed
- **aid-plan-epic Command** — rewritten from 544-line LLM-driven flow to 235-line script-orchestrated 6-step flow delegating deterministic work to `aid-auto-pipeline.sh`
- **aid-run-epic Command** — inline plan generation removed; `plan.json` must pre-exist (created via `/aid-plan-epic`) with clear error message and actionable suggestion when missing
- **Documentation Consistency Pass** — 10+ skill/command files updated to reference script-based pipeline, removing references to inline plan generation

## [1.5.0] — 2026-02-28

### Added
- **Token Estimation Protocol** — new `skills/token-estimator.md` defining character-based heuristic for dispatch token counting with cl100k_base approximation and calibration process
- **Dispatch Configuration** — new `defaults/policies/dispatch-config.yaml` with 18 role-to-model tier mappings (3 opus, 11 sonnet, 4 haiku), per-tier context defaults, and advisory budget alerts
- **Plan Schema Extension** — `model` (enum: haiku/sonnet/opus) and `context_scope` (knowledge, memory, previous_outputs) optional fields per step in `plan.schema.json`
- **Planner Model Assignment** — planner reads `dispatch-config.yaml` and populates `model` + `context_scope` per step with fallback to opus/all-context when config is absent
- **Dispatch Usage Logging** — pre-dispatch token estimation and post-dispatch `usage` object in stage_log.jsonl with model, tokens, duration, context sources, and budget alerts
- **Usage Aggregation** — DONE state aggregates all dispatch_complete entries into `usage_summary` in plan_progress.json with breakdowns by model, role, and step
- **Model Tiering in Dispatch** — `step.model` passed to Task tool with 3-level fallback chain (step.model → dispatch-config.yaml → opus default)
- **Selective Context Injection** — knowledge, memory, and previous outputs conditionally injected based on `step.context_scope` with full backward compatibility
- **Dispatch Prompt Trimming** — EPIC context reduced to one-line goal + step-level paths instead of full EPIC specification
- **Token Efficiency Audit** — new `/aid-audit efficiency` type with per-role baseline comparison and 2x alert threshold (advisory, 0% weight)

### Changed
- **Dispatch Protocol** — model parameter wired into Task tool calls, context injection is conditional, prompt uses trimmed EPIC context
- **Parallel Dispatch** — model tiering support with per-agent model resolution

## [1.4.0] — 2026-02-27

### Added
- **GUI Dashboard** — full-featured web dashboard (`aid-gui` package) with Express backend, WebSocket real-time updates, and React 19 + Zustand 5 frontend
- **Ideas-to-Execution Kanban** — drag-and-drop board tracking ideas through exploration → planned → running → done lifecycle with auto-status from linked plans/EPICs
- **AI Companion Chat** — SSE-streaming chat panel with markdown rendering, session management, voice input (Web Speech API), and contextual hint buttons
- **EPIC Lifecycle Manager** — GUI-driven EPIC listing with frontmatter parsing, run/schedule actions, queue integration, and status-sorted display
- **Evidence Vault** — full-text grep search across evidence files (200-result cap, binary detection), date-grouped collapsible sidebar, and markdown preview toggle with DOMPurify sanitization
- **Pipeline Theater SVG Timeline** — Gantt-like horizontal timeline with color-coded role bars (architect/backend/frontend/qa/docs/security), replay controls (0.5x–4x speed), EPIC/run selector, and live auto-scroll mode
- **Decision Hub Notifications** — Web Audio API sound alerts (440Hz sine, 3s debounce) and browser Notification API for background tabs, with Sidebar badge pulse animation
- **Evidence Search API** — `GET /evidence/search?q=&limit=` endpoint with case-insensitive text matching, path traversal protection, and binary file skipping
- **Pipeline Theater API** — `GET /pipeline/theater/:epicId/:runId` endpoint merging plan.json + plan_progress.json + stage_log.jsonl into combined theater data
- **Companion Backend** — session-store with JSON persistence, auto-detect LLM adapter (Claude/OpenAI/Ollama/stub), SSE streaming endpoint, voice transcription proxy
- **WebSocket Infrastructure** — topic-based pub/sub (pipeline, stage_log, decisions, queue) with heartbeat, auto-reconnect (exponential backoff), and replay on reconnect
- **Test Suite** — 1014 Vitest tests across 31 files covering server routes, parsers, WebSocket, store slices, and API client

### Changed
- **Project structure** — added `packages/aid-gui/` (frontend) and `packages/aid-server/` (backend) as monorepo packages alongside the plugin

## [1.3.1] — 2026-02-27

### Fixed
- **Curator evidence path** — `step_output.json` replaced with `output.md` so Curator can actually read agent improvement notes
- **FIRST AID skill reference** — `skills/first-aid-mode.md` corrected to `skills/first-aid-controller.md` in `/aid-help`
- **Czech preset descriptions** — translated to English in `permissions.yaml` (aspirin and steroids descriptions)
- **Stale epic-breakdown.md references** — 6 references across 5 files replaced with `epic.md` (the actual template)

## [1.3.0] — 2026-02-27

### Added
- **Queue dependency ordering** — `depends_on` field in queue schema with Kahn's algorithm cycle detection; `next()` computes READY/WAITING/BLOCKED eligibility per entry
- **INTERMEDIATE_GUARDRAIL** — 3-check auto-approval gate (all_steps_done, no_gate_failures, evidence_complete) for intermediate EPICs in FIRST AID mode
- **Queue write ownership** — CONFLICT_CHECK as Step 0 in add()/start()/complete() operations; single-writer constraint during FIRST AID via auto-mode flag file
- **Canonical EPIC ID format** — formal `E-{plan_id}-{phase}_{total}` specification with validation regex and cross-referenced documentation
- **Untrusted field list** — 10 untrusted and 6 trusted fields enumerated in dispatch-protocol with rationale for each classification
- **OVERLAP_CHECK algorithm** — concrete pseudocode for 3 cases (exact-exact, glob-exact, glob-glob) replacing vague prose in planner
- **R1 dependency classification** — DATA MODEL and API CONTRACT type definitions with 5-step determination algorithm replacing subjective criteria
- **plan_ref keyword matching** — 4-step algorithm with extract/score/stopping-rule/confidence-check replacing vague Strategy 3 description
- **Setup re-run detection** — `/aid-setup` detects existing workspace and offers 6-option section menu for selective reconfiguration
- **Release count verification** — RELEASE_CHECK_COUNTS ensures CLAUDE.md command/skill counts stay in sync during releases
- **DEFAULT_BASELINE** — threshold 50/100 applied when no prior audit report exists for PM_APPROVAL auditor trend check

### Changed
- **adapt_example()** — simplified from 7-step function (422 lines) to 3-step (83 lines): path substitution, tool reference update, validation
- **Credit exhaustion detection** — 5 hardcoded strings replaced with 6 case-insensitive regex patterns and short-circuit evaluation

### Fixed
- **Escalation snapshot** — now correctly writes to `interrupted_step_context.json` instead of inconsistent field names

### Removed
- **`--dry-run` flag** — removed from `/aid-first-aid` command; deferred to backlog as standalone feature

## [1.2.0] — 2026-02-27

### Removed
- **Permission Sandwich** — removed `skills/permission-sandwich.md` (750 lines) and `defaults/policies/permissions-auto.yaml` (164 lines); FIRST AID no longer backs up, elevates, or restores permissions — requires Steroids 💉 preset instead

### Changed
- **Permission presets** — Safe removed, Recommended renamed to Aspirin 💊, Advanced renamed to Steroids 💉; two-preset system with deny-list protection
- **FIRST AID startup** — permission sandwich steps (backup, elevate) replaced by single Steroids preset verification check
- **FIRST AID completion** — permission restore removed; /aid-stop simplified to 3 steps (mode flag, wait, save progress)

### Fixed
- **Plan archival** — QUEUE_ADVANCE now uses queue as ground truth for plan archival instead of filesystem scanning; DONE state no longer attempts archival (single source)
- **Version bump detection** — uses plan-level completion (`plan_epics_total`) instead of queue position; solo plans always bump, multi-EPIC plans bump on last EPIC
- **Release sub-phase** — DONE state now explicitly calls RELEASE_SUB_PHASE with mandatory stage_log entry; skipping is no longer possible without audit trail
- **Queue removal** — `/epic-queue remove` sets status "removed" (not "completed"); context boundary tracking distinguishes session total from actually-executed EPICs

## [1.1.0] — 2026-02-27

### Added

- **Plan-Writing Skill** — new `skills/plan-writing.md` with two modes: Mode A (post-brainstorming) and Mode B (standalone `/aid-write-plan`); includes Forbidden Phrase Detection hard gate, Traceability Verification, 16-point Completeness Gate, and Post-Write Handoff offering EPIC creation
- **`/aid-write-plan` Command** — standalone plan writing command that delegates to the plan-writing skill; accepts topic argument or interactive input
- **Brainstorming Critical Rules Block** — 11 critical rules at the top of `aid-brainstorm.md` with primacy effect positioning to prevent instruction drift
- **Brainstorming Step Self-Checks** — each of the 8 brainstorming steps now has a mandatory self-check checklist (2-4 items) that must pass before transitioning to the next step
- **Brainstorming Progress Tracker** — mandatory `=== Step N/8: {Name} ===` output at the start of every brainstorming step for checkpoint enforcement
- **Brainstorming Approach Hard Gate** — RULE 9 enforces minimum 2 approaches before presenting to PM; RULE 10 prevents skipping approach exploration even for "obvious" topics
- **Brainstorming Completeness Gate** — Step 8 now enumerates all PM answers from Steps 3-6 and verifies each appears in the plan document before finalizing
- **adapt_example() Implementation** — 7-step function in knowledge-acquisition.md replaces path placeholders, updates framework versions, handles Docker sections, aligns platforms, merges constraints, adjusts step count, and writes adapted EPIC
- **Knowledge Results Display** — brainstorming Step 1 now shows PM what knowledge was found ("Found N relevant docs: [names]") or "No knowledge indexed yet"
- **`/aid-help knowledge` Topic** — lists all example EPICs by category, explains search flow (Context7 → Qdrant → static), and documents indexing and research triggers
- **RESUME_SESSION safety net** — QUEUE_PROCESSING next() now filters on `status in ["queued", "running"]` with preference for running entries, so an interrupted EPIC is automatically resumed even when the RESUME_SESSION reset was skipped
- **Permission snapshot and restore** — `auto-mode-state.yaml` gains an `original_permissions_snapshot` field; RESTORE_PERMISSIONS now uses a two-tier fallback (backup file, then inline snapshot) across all three restore paths (COMPLETE, /aid-stop, crash recovery)
- **Permission grant log** — `auto-mode-state.yaml` gains a `permissions.grant_log[]` audit trail field recording each dynamic permission grant with permission, source, actor, step_ref, timestamp, and reason; PHASE_CHECK permission learning dual-writes to both `learned_permissions[]` and `grant_log[]`
- **Multi-agent parallel execution** — QUEUE_PROCESSING gains a complete parallel dispatch protocol: independence detection via EPIC scope analysis, Task agent dispatch in worktree isolation, sequential merge with shared escalation budget, failure isolation per agent, and a safety cap of 3 concurrent agents
- **Untrusted content tags in dispatch templates** — all 10 user-supplied interpolation points in `aid-run-epic.md` dispatch prompts are wrapped in `<untrusted_content>` tags with source attributes; safety preamble added to both base and re-dispatch templates to prevent prompt injection
- **Hardened deny-list entries** — `Bash(rm -fr:*)` (reversed short flags) and `Bash(dd if=/dev/urandom:*)` added to the hard-deny list in `permission-sandwich.md` and `permissions-auto.yaml` with inline rationale comments and updated Section 3.4 rationale table
- **Planner parallelism rules** — 5 named Parallel Group Assignment Rules added to `planner.md`; backend and frontend agents can now parallelize after architect+domain steps when file scopes do not overlap; includes OVERLAP_CHECK algorithm and 3 worked examples
- **Planner granularity heuristics** — HEURISTIC G1 (Layer Splitting) and G2 (Module Splitting) added to `planner.md` Section 2b with before/after examples and interaction rules; steps spanning 3+ layers or 3+ modules are automatically split
- **Audit instruction quality checks** — Section G added to `auditor.md` with 5 checks for instruction file quality (intro presence, TODO/FIXME scan, frontmatter, cross-reference accuracy, files exceeding 800 lines); weighted at 10% and conditional on `plugins/aid-orchestrator/` existing

### Changed

- **Brainstorming modular split** — 1371-line `brainstorming.md` split into core (569 lines) + two sub-skills: `brainstorming-knowledge.md` (445 lines) for knowledge acquisition and file analysis, `brainstorming-workflow.md` (443 lines) for workflow detection and Docker/MCP rules
- **Brainstorming flow simplified** — reduced from 11 steps to 8 steps; EPIC creation removed from brainstorming entirely (now handled by `/aid-plan-epic` via plan-writing handoff)
- **Plan-writing delegation** — brainstorming Step 8 now delegates to `skills/plan-writing.md` instead of writing the plan inline; plan-writing skill handles quality gates, forbidden phrase detection, and completeness verification
- **FIRST AID disclaimer** — reframed from alarmist "USE AT YOUR OWN RISK" to "Experimental Autonomous Mode"; added explicit `/aid-stop` emergency stop reference and `/aid-epic-queue` for queue review so users know how to intervene safely
- **Setup MCP advanced permissions preset** — replaced the broad `mcp__*` wildcard with 7 explicit tool patterns (`mcp__shared-github__*(*)`, etc.) matching auto-mode format; updated setup wizard comparison matrix to reflect the change
- **Epic orchestration skill split** — 2300-line `epic-orchestration.md` split into 5 modular files: slim orchestrator (138 lines), `epic-state-machine.md` (602), `dispatch-protocol.md` (498), `gate-evaluation.md` (509), and `first-aid-controller.md` (577); pure refactoring with no logic changes
- **PLAN_REVIEW template enriched** — per-step detail table added to PLAN_REVIEW state with 7 columns (Files, Tech, AC count, Output, Deps) and 6 enforcement rules so plan review captures the full structure of each step
- **DONE state release logic consolidated** — release behavior now exists in exactly one place (`auto-done-state.md`); `first-aid-controller.md` DONE state delegates to `auto-done-state.md` for all release steps, eliminating duplication

## [1.0.0] — 2026-02-26

### Added

- **GitHub MCP in Setup Wizard** — `/aid-setup` now includes GitHub MCP as recommended option 6e with full setup flow covering detection, auth check, install, verification, and troubleshooting
- **Setup Completion Banner** — `/aid-setup` displays a professional styled ASCII art banner with AID branding after successful setup completion
- **Version Pre-check in Plan Epic** — `/aid-plan-epic` Step 0 reads the local plugin version, compares it with the latest GitHub release via `gh api`, and warns if outdated (non-blocking)
- **Help Workflow Examples** — `/aid-help examples` returns three step-by-step workflows: Greenfield Feature, Quick Fix, and Multi-Phase with FIRST AID
- **Autonomous Mode Commands in Help** — `/aid-help commands` now includes detailed entries for `/aid-first-aid` and `/aid-stop` under a new AUTONOMOUS MODE COMMANDS section

### Changed

- **Setup MCP Options** — re-lettered MCP sub-options so GitHub MCP is 6e, Auto-detect is 6f, and Custom is 6g; restructured Step 5b as Optional MCP Follow-up
- **Skill Count** — updated documented skills count from 20 to 21 in CLAUDE.md and README to include the previously unlisted `workflow-intelligence.md`

### Fixed

- **Stale Paths** — replaced three remaining `workspace/workflow/` references with `.aid-o/` equivalents in `planner.md`, `aid-plan-epic.md`, and `slack-mcp.md`
- **README Version** — synced README version from stale 0.9.2 to 0.9.3 (now bumped to 1.0.0 with this release)
- **Command Frontmatter** — verified all 13 commands have `user_invocable: true`

## [0.99.0] — 2026-02-26

### Added

- **AID Server** (`packages/aid-server`) — Express + WebSocket backend serving the AID GUI dashboard; 18 REST API endpoints covering projects, pipeline state, EPIC queue, decisions, evidence, audit, ideas, usage metrics, and knowledge; real-time WebSocket pub/sub with chokidar file watching on `.aid-o/`; topic-based subscriptions with heartbeat and idle timeout
- **Docker deployment** — multi-stage Dockerfile (gui-build → server-build → production) and docker-compose.yml; single `docker compose up --build` serves both GUI and API on port 3911; health check included
- **Docusaurus documentation site** — full docs site with architecture, configuration, contributing, troubleshooting, reference docs, and Getting Started guides; deployed to GitHub Pages via GitHub Actions; EN + CS locales
- **GUI frontend polish** — AI Companion panel, replay controls, error boundaries, production build optimization (FIRST AID EPIC session, 5 EPICs completed autonomously)

### Fixed

- **MDX expression errors** — escaped `{type: performance}` in `decision-policies.md` and `{message_type}`/`{action}` in `slack-integration.md` that broke Docusaurus MDX compilation
- **GitHub Pages config** — replaced all placeholder values in `docusaurus.config.ts` (`your-org` → `marekstancl`, `your-project` → `claude-aid-o`)
- **GUI Page Crashes** — added null guards to QueueScheduler, KnowledgeBase, and HealthObservatory to prevent TypeError crashes on empty data
- **WebSocket Connection** — connected useWebSocket hook in App.tsx so real-time events flow to all dashboard screens
- **CC Usage Gauge Visibility** — removed responsive hiding so CC Usage gauge is always visible in topbar, even when disconnected
- **Mobile Connection Banner** — removed `hidden md:flex` so connection status banner shows on mobile viewports
- **Project Selector Z-Index** — added z-50 to dropdown container so it renders above the sidebar overlay
- **Sidebar Responsive Collapse** — sidebar auto-collapses to icon mode on viewports below 768px with hamburger toggle and backdrop overlay
- **Pipeline Theater Empty State** — shows "No pipeline data" message instead of stale replay counter when no runs exist
- **SVG Path Animation Error** — suppressed motion.path rendering when no pipeline data is displayed, eliminating console errors
- **API JSON Fallback** — added /api/* catch-all route returning JSON 404 before static file fallback, preventing HTML responses for unknown API routes
- **Notification/Settings Buttons** — added "Coming soon" tooltips and safe click handlers to prevent crashes
- **Project Fetch Response Parsing** — fixed App.tsx legacy fetch that expected raw array but API returns `{ ok, data }` envelope, so currentProject was never set and WebSocket never connected
- **Health Observatory Audit Data** — fixed double-wrapping of audit reports array that caused latestAudit to be an array instead of an object, breaking score display
- **Health Check Route Collision** — moved Express health-check endpoint from `/health` to `/api/health` so the GUI's `/health` route (Health Observatory page) is served by the SPA fallback instead of returning raw JSON

### Changed

- **Default port** — server default port changed to 3911 (config.ts, Dockerfile, docker-compose.yml)
- **Version bump** — all packages bumped to 0.99.0 (aid-server, aid-gui, docs)

## [0.9.3] — 2026-02-25

### Fixed

- **GATES → CURATOR_RESOLVE transition** (`skills/epic-orchestration.md`) — GATES state now correctly transitions to CURATOR_RESOLVE instead of skipping directly to PM_APPROVAL; restores the full state machine flow (GATES → CURATOR_RESOLVE → PM_APPROVAL) so Curator proposals are processed for every EPIC
- **Qdrant config unification** — `memory-config.yaml` is now the single source of truth for `memory.enabled`; removed duplicate flag from `project-profile.yaml`; added non-blocking Qdrant startup probe in IDLE state for early availability detection

### Added

- **CURATOR_RESOLVE auto-mode conditionals** (`skills/epic-orchestration.md`) — in FIRST AID mode, effort:S proposals get inline fixes while effort:M/L are auto-deferred to backlog with urgency tags; failed inline fixes silently defer (non-blocking)
- **Credit exhaustion detection** (`skills/epic-orchestration.md`) — PHASE_CHECK now validates agent output before evaluation; detects 5 Claude Code credit error patterns via string matching; auto-pauses with `interrupted_step_context.json` + git stash; FIRST AID resume recovers interrupted steps
- **Wiring step generation** (`skills/planner.md`) — POST_WAVE_WIRING_CHECK detects shared files across parallel wave steps and auto-generates a wiring step with context (shared_files, contributing_steps, expected_actions); new `wiring` and `wiring_context` fields in `plan.schema.json`; EXECUTING state recognizes wiring steps with specialized dispatch prompt
- **EPIC & plan archival** (`skills/epic-orchestration.md`, `commands/aid-first-aid.md`) — DONE state archives completed EPICs to `02-epics/archive/`; QUEUE_ADVANCE archives plans when all plan EPICs complete; non-blocking with `mkdir -p` safety
- **FIRST AID ASCII art animations** (`commands/aid-first-aid.md`) — 4-frame syringe-themed startup animation, depleted-syringe completion banner with CURATOR FINDINGS summary, re-injection resume banner
- **CURATOR FINDINGS section** in FIRST AID completion report — shows implemented/deferred/rejected proposal breakdown with per-EPIC table

## [0.9.2] — 2026-02-24

### Added

- **FIRST AID Autonomous Mode** — `/aid-first-aid` starts autonomous EPIC queue execution with agent-driven quality checks replacing PM approval points; `/aid-stop` disengages immediately, restoring manual mode at the current natural pause point
- **Permission Sandwich** (`skills/permission-sandwich.md`) — automatic permission backup, elevation, and restoration for autonomous execution with crash recovery and permission learning; permissions are scoped to the auto-mode session and restored unconditionally on exit
- **Auto-Mode Escalation Protocol** (`skills/auto-escalation.md`) — 16 trigger conditions with severity classification, pause/resume flow, escalation budget tracking (max 3 before mandatory PM review), and `continue-manual` handoff option
- **Auto-Mode DONE State** (`skills/auto-done-state.md`) — automatic release decisions (defer intermediate, mandatory bump on last EPIC), queue transitions, and cross-EPIC summary aggregation to `auto-mode-state.yaml`
- **FIRST AID command** (`commands/aid-first-aid.md`) — PM-facing command to activate autonomous mode: queue confirmation, permission elevation, and auto-mode-state initialization
- **Aid-Stop command** (`commands/aid-stop.md`) — immediate autonomous mode stop command; safe mid-EPIC stop after current step completes

### Changed

- **PLAN_REVIEW** (`skills/epic-orchestration.md` Section 3) — auto-mode: schema, completeness, dependency graph, and run file quality validation replace PM prompt; validation failure triggers ESCALATION; manual mode unchanged
- **PHASE_CHECK** (`skills/epic-orchestration.md` Section 5) — auto-mode: adds one "fresh approach" retry cycle after `max_review_fix_cycles` exhausted before escalating; manual mode unchanged
- **ESCALATION** (`skills/epic-orchestration.md` Section 9) — auto-mode: pauses mode, saves progress snapshot, increments escalation counter, presents extended PM options including `continue-manual`; manual mode unchanged
- **PM_APPROVAL** (`skills/epic-orchestration.md` Section 11) — auto-mode: intermediate EPICs auto-approved; last/standalone EPIC auto-approved only after 4 guardrails pass (gates, no critical issues, escalation budget, auditor trend); rule teaching suppressed in auto-mode; manual mode unchanged
- **DONE state** (`skills/epic-orchestration.md` Section 12) — auto-mode: intermediate EPIC version bump auto-deferred, last EPIC auto-bumped; queue transition loads next EPIC automatically; auto-mode exits and restores permissions when queue is exhausted; manual mode unchanged

## [0.9.1] — 2026-02-24

### Added

- **Initial Analysis Phase** (`skills/brainstorming.md`) — mandatory structured analysis before questioning; 8-rule protocol with 4 required elements (topic understanding, key dimensions, potential challenges, clarification preview); PM confirmation gate; trivial topic escape hatch
- **Release Sub-Phase** (`skills/epic-orchestration.md`) — version bump detection and execution in DONE state; reads `release-policy.yaml` for CHANGELOG pattern, version files, multi-phase deferral; supports `json_field` and `regex` update strategies, git tagging, GitHub releases
- **Release policy config** (`defaults/policies/release-policy.yaml`) — configurable versioning: CHANGELOG header pattern, version file locations, update methods, multi-phase plan detection, git tag and GitHub release controls

### Changed

- **Questioning Protocol strengthened** (`skills/brainstorming.md`) — Rule 2 upgraded from "Prefer MULTIPLE CHOICE" to "ALWAYS use MULTIPLE CHOICE with recommendation"; added Rules 10-11 for structured directional options and contrastive reasoning
- **MUST Rules expanded** (`skills/brainstorming.md`) — 3 new entries (15-17): mandatory analysis before questions, options at every decision point, reasoning for alternatives
- **Command flow updated** (`commands/aid-brainstorm.md`) — 10-step → 11-step flow; new Step 2 (Analysis) inserted between Context and Questions; all subsequent steps renumbered with cross-references updated
- **DONE state enhanced** (`commands/aid-run-epic.md`) — Release Sub-Phase integrated before branch merge; DONE action items reordered (run file update → release → merge → archive)

### Fixed

- **Example EPIC lookup type filter** (`skills/brainstorming.md`) — changed from `"example_epic"` to `"example"` to match actual frontmatter in 19 example files
- **Example EPIC lookup scan** (`skills/brainstorming.md`) — changed from flat `defaults/examples/` to recursive `defaults/examples/**/*.md` to find files in subdirectories

## [0.9.0] — 2026-02-24

### Added

- **Plan-ref injection** (`skills/epic-orchestration.md`) — dispatch template now includes `plan_ref` with Source Plan Integration protocol: 3-strategy matching cascade (keyword → heading → sequential), 3000-line truncation guard, `<plan_context>` block in agent prompts
- **Sequential ID generation** (`skills/epic-orchestration.md`) — ID Format Specification for Plans (`P{NNN}`), EPICs (`E-{NNN}-{epic_run}_{plan_step}`), and Runs (`R-{NNN}-{epic_run}_{plan_step}-{run_seq}`); Counter File protocol (`counter.yaml`); atomic increment rules
- **Evidence Incomplete detection** (`agents/auditor.md` section F.5) — `evidence_incomplete` finding type with `-3` deduction per missing mandatory file; only checks completed steps
- **Mandatory Evidence Write Checklist** (`skills/epic-orchestration.md`) — Step Evidence File Types table listing mandatory vs optional evidence files per step

### Changed

- **SESSION → RUN terminology** — renamed across 45+ files: `session` → `run`, `session-management.md` → `run-management.md`, `session-validator.md` → `run-validator.md`, 4 template files renamed; `sessions/` directory → `runs/`
- **Flat evidence structure** (`commands/aid-run-epic.md`, `skills/epic-orchestration.md`) — removed 5 empty subdirectory creation (analysis/, discovered_issues/, parallel_groups/, prompts/, reviews/); evidence now written directly to `steps/step_{N}_{role}/`
- **Budget references removed** — removed budget estimation lines from `defaults/templates/epic.md`, `defaults/templates/epic-example.md`, `skills/brainstorming.md`
- **Auditor check #12 path updated** (`agents/auditor.md`) — `evidence/discovered_issues/` → `steps/step_{N}_{role}/discovered_issues.md`
- **Analysis-merge evidence paths** (`skills/analysis-merge.md`) — `evidence/{epic_id}/{run_id}/analysis/` → `steps/step_{target}_{role}/`

## [0.8.2] — 2026-02-23

### Fixed

- **Czech-language content removed** — translated all Czech text to English in `agents/lessons-extractor.md`, `skills/session-management.md`, `skills/agent-core.md`
- **Broken skill reference in `aid-epic-queue.md`** — `skills/aid-epic-queue.md` → `skills/epic-queue.md`, `aid-epic-queue.yaml` → `epic-queue.yaml`
- **Stale `workspace/workflow/` paths** — 12 legacy path references replaced with `.aid-o/` equivalents in `skills/session-management.md`
- **Stale command prefixes** — `/run-epic` → `/aid-run-epic`, `/plan-epic` → `/aid-plan-epic` in `skills/retry-engine.md`, `skills/planner.md`, `defaults/templates/epic-example.md`
- **Version mismatches** — header/footer versions aligned to 0.8.2 in `session-management.md`, `epic-orchestration.md`, `retry-engine.md`, `planner.md`, `agent-core.md`
- **Hardcoded Slack channel ID** — replaced `C0AFP2GP459` with `YOUR_CHANNEL_ID` placeholder in `commands/aid-setup.md`
- **Plugin README version** — updated from 0.4.1 to 0.8.2

### Added

- **Untrusted-content framing** — SECURITY section in `skills/epic-orchestration.md` documenting mandatory `<untrusted_content>` tags for user-provided content in dispatch prompts (CWE-77, OWASP LLM01)
- **Advanced preset warning** — explicit risk documentation and PM confirmation requirement in `defaults/policies/permissions.yaml`

### Changed

- **CLAUDE.md structure info** — corrected command count (10 → 11) and skill count (14 → 17); removed stale `docs/` directory reference
- **CHANGELOG alignment** — root and plugin `[0.8.1]` entries made identical per CLAUDE.md policy

## [0.8.1] — 2026-02-23

### Added

- **Process Audit type** (`agents/auditor.md` section F) — 6th audit type, always runs, with 13 checks across 4 categories: F.1 EPIC Lifecycle (3 checks), F.2 Evidence Completeness (6 checks), F.3 Cross-Validation (3 checks), F.4 Stage Log Integrity (1 check); deduction-based scoring (0-100); `process: {0-100}` field added to YAML output; 15% weight in Overall score; Score Overview template updated with Process row

### Changed

- **Audit weight redistribution** (`agents/auditor.md` weight table) — Documentation 20% → 25%, Process 15% added; total always-run audit types: 3 → 4; audit type count: 5 → 6

## [0.8.0] — 2026-02-23

### Added

- **CURATOR_RESOLVE state** — new state between GATES and PM_APPROVAL in the epic-orchestration state machine; auto-evaluates Curator proposals via 3-tier algorithm (YAML rules → Qdrant history → default), dispatches fix agents, writes lessons with 3-layer dedup
- **`curator_auto_rules`** in `decision-policies.yaml` — configurable auto-resolution rules for improvement proposals
- **PM override + rule teaching** at PM_APPROVAL — PM can override rejected proposals and teach new auto-rules that persist via YAML + Qdrant
- **Improvement Pipeline analytics** — Report Type 4 in `/aid-analytics` for curator pipeline metrics
- **3-layer Lessons-Extractor dedup** — text, semantic, and Qdrant cross-project deduplication

### Changed

- **State machine**: 11 → 12 states (CURATOR_RESOLVE inserted)
- **DONE state simplified**: Curator + Lessons-Extractor moved to CURATOR_RESOLVE
- **`backlog.md`**: PROP-* IDs migrated to IMP-{NNN} with legacy alias table
- 9 files updated across agents, skills, commands, and policies

## [0.7.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.6.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.5.0] — 2026-02-22

### Added

**Phase 1 — Research + Storage + Consumption:**
- **Knowledge acquisition skill** — new `skills/knowledge-acquisition.md` with Research, Storage, and Consumption protocols; Context7 MCP as primary source, WebSearch fallback, dual storage (per-project YAML index + global Qdrant), 4-gate quality protocol
- **Context7 MCP in `/aid-setup`** — Option 6b for framework documentation via MCP; auto-detection, verification, troubleshooting guide
- **Docker MCP elevated to recommended** — Option 6d in `/aid-setup`; auto-detection of Dockerfile/docker-compose.yml, dedicated install section
- **Documentation type in memory-mcp** — Type 6 with full metadata schema and 4-gate Documentation Quality Gate Protocol
- **Knowledge-Augmented Brainstorming** — `brainstorming.md` Step 1 and Step 3 integration with `knowledge_find()`; non-blocking with 5s timeout, graceful degradation
- **KNOWLEDGE CONTEXT block in agent-core** — 3-section block (Framework Documentation, Patterns, Lessons) with type-specific staleness thresholds (90/180/365 days)
- **`knowledge-base.yaml` template** — per-project reference index for documentation sources
- **Knowledge config in `memory-config.yaml`** — `knowledge:` root-level section with research, quality, and context7 subsections

**Phase 2 — On-Demand Research + Aging:**
- **`/aid-research` command** — on-demand research for specific frameworks/libraries; `--deep` mode for comprehensive documentation ingestion
- **Aging protocol** — TTL-based freshness weighting for all document types (90–365 days); stale/expired score multipliers (0.7/0.3); automatic exclusion after 180 days past TTL
- **Manual source addition** — conversational flow for adding documentation sources via URL or topic
- **Freshness weighting in `memory_find()`** — search results weighted by document age; stale chunks deprioritized automatically
- **Aging config in `memory-config.yaml`** — per-type TTL values, stale/expired weights, exclusion threshold

**Phase 3 — Auto-Extraction + Community Examples + Feedback:**
- **Example EPIC extraction protocol** — 7-stage `extract_example_epic()` function: eligibility check → extract → abstract → build text → PM approval → dedup → Qdrant storage; triggered in DONE state step 9b
- **`example_epic` document type** — Type 8 in memory-mcp.md with 11 metadata fields (frameworks, archetype, source_epic_id, complexity, roles, etc.); never-expire TTL; global project scope
- **Community example EPICs** — 3 curated templates in `defaults/examples/`: `langchain-rag-chatbot.md`, `fastapi-crud-service.md`, `react-dashboard.md`; placeholder paths, version ranges, standard EPIC template format
- **Example EPIC lookup in brainstorming** — Step 3 searches `defaults/examples/` + Qdrant for matching archetypes; PM offered: (A) Adapt, (B) Browse all, (C) Start fresh
- **Feedback tracking** — fire-and-forget `track_retrieval()` after `memory_find()`; tracks `times_retrieved` and `avg_retrieval_score` per framework in `knowledge-base.yaml`; deprecation signal after 180 days of zero retrievals
- **Feedback config in `memory-config.yaml`** — `feedback:` section with `track_retrieval`, `track_usefulness`, `deprecate_unused_after_days`

### Changed
- **Command prefix standardization** — 5 commands renamed to `aid-*` prefix (`run-epic` → `aid-run-epic`, etc.) for discoverability; 9 unused command files removed; 20+ cross-references updated
- **`/aid-plan-epic` UX text** — updated intro and Step 9 output for unified Plan→EPIC→Plan flow
- **`/aid-help` command description** — updated `/aid-plan-epic` entry to "Unified Plan→EPIC→Plan entry point"
- **DONE state in `epic-orchestration.md`** — new step 9b triggers example extraction after Curator; completion summary includes archetype when pattern is stored
- **`memory-mcp.md` document types** — expanded from 6 to 8 types (added Proposal, Example EPIC); feedback tracking hook in `memory_find()`
- **`brainstorming.md` non-blocking guarantee** — knowledge calls updated from 2 to 3 per session (Step 1 search + Step 3 knowledge + Step 3 examples); 7 new graceful degradation scenarios

## [0.4.2] — 2026-02-21

### Changed
- **`/plan-epic` step numbering** — renumbered all steps from fractional (0.5, 0.7, 2.5) to clean integers (1-9); internal cross-references updated
- **`/aid-brainstorm` step numbering** — renumbered Step 8b→9 and Step 9→10; new Step 10 presents interactive A-D handoff options (add items, all-phases EPIC, specific-phase EPIC, manual)
- **Cross-references** — updated plan-epic step references in run-epic.md (3 occurrences) and epic-orchestration.md (2 occurrences); updated aid-brainstorm.md and brainstorming.md internal refs

### Added
- **`/aid-init [path]` parameter** — documented optional path parameter in aid-init.md Usage section with examples for relative and absolute paths; updated aid-help.md entry
- **Phase selection** — plan-epic.md Step 2 now handles all-phases vs specific-phase EPIC generation when invoked from brainstorming with phase context
- **Re-opening protocol** — brainstorming.md documents how Option A (add items) works: load existing plan, display approved sections, return to Step 2, re-generate EPIC
- **Phase Selection section** — brainstorming.md EPIC Subagent Prompt Template includes phase handling for scoped EPIC generation

## [0.4.1] — 2026-02-20

### Added
- **`/aid-init` upgrade mode** — detects existing workspace, compares installed vs. plugin version, classifies files as NEW / UPGRADABLE / UNCHANGED / CUSTOM / PROTECTED, asks PM before updating
- **Config manifest** — `.aid-o/03-config/.aid-manifest.yaml` tracks installed plugin version and md5 checksums of all config files; enables safe detection of PM customizations
- **Dynamic defaults scanning** — `/aid-init` scans `defaults/` directories instead of hardcoded file list; new files in future versions are automatically included
- **`source_plan` in plan schema** — `defaults/templates/plan.schema.json` now includes the `source_plan` field for Variant B pipeline

### Changed
- **CHANGELOG format** — standardized all entries to `**Bold Name** — description` format; root and plugin CHANGELOGs are now identical
- **CLAUDE.md release protocol** — added CHANGELOG format standard, README Roadmap update rules, and 10-step release workflow
- **`/aid-init` description** — updated in `aid-help.md` to reflect upgrade capabilities

## [0.4.0] — 2026-02-20

### Added
- **Zero Detail Loss Pipeline (Variant B)** — EPIC references source plan via `plan_ref`; all pipeline stages (plan.json, session, agent dispatch) read both EPIC and source plan; agents receive `## Source Plan — Implementation Detail` sections
- **Wave-based execution model** — planner groups steps by DAG level into waves (max 4 per wave) for parallel execution; replaces flat parallel group detection
- **Step decomposition** — layer-based splitting of monolithic steps (data → schema → API → test) to enable cross-domain parallelism; supports dev, docs, and infra decomposition types
- **Critical path analysis** — opt-in for 7+ step EPICs; computes critical path ratio, applies 5 relaxation rules (R1–R5) to shorten it; PM can reject individual relaxations at PLAN_REVIEW
- **Parallelism-first optimization** — 5-priority strategy (parallelism > wave density > session compactness > quality > efficiency); plan quality metrics in `optimization_metrics`; validation rules V-20–V-23
- **`/plan-epic` accepts Plan files** — 3-tier format detection (frontmatter → header → section fingerprinting); auto-generates EPIC from Plan using EPIC Subagent Template
- **`/aid-brainstorm` inline execution** — Step 8b offers to generate Plan JSON + Session immediately after EPIC draft; Step 9 split into 9a (standard handoff) / 9b (full pipeline handoff)
- **Wave-based session boundaries** — sessions are contiguous sequences of waves; never split by domain or inside a wave
- **Shorthand commands** — all 18 commands have `user_invocable: true` frontmatter enabling `/aid-setup` instead of `/aid-orchestrator:aid-setup`
- **Setup followup** — after "All recommended", `/aid-setup` now offers additional options (CLAUDE.md, Slack, auto-detected MCPs)
- **Selective `.aid-o/` gitignore** — plans, EPICs, and config are versioned; engine artifacts (sessions, evidence) are ignored
- **Centralized Qdrant storage** — `~/.local/share/aid-orchestrator/qdrant-data` with `--scope user` for global MCP; migration check for old paths

### Changed
- **EPIC template** — typed artifacts (`endpoint:`, `model:`, `component:`), `plan_ref` enforcement, Hints section, Scope with specific file paths
- **EPIC Subagent Template** — frontmatter instructions, plan task ID preservation in steps, Variant B zero detail loss instruction
- **Planner input validation** — REQUIRED/RECOMMENDED checks with typed artifact inference
- **PLAN_REVIEW** — rich plan summary with wave execution plan, optimization metrics, session breakdown
- **EXECUTING state** — agent dispatch enriched with source plan sections
- **Plan generation flow** — 13-step procedure with decomposition (2.2), wave assembly (6), CPA (6.1), session boundaries (11)

## [0.3.0] — 2026-02-19

### Added
- **Execution Summary block** — mandatory in all agent outputs with timing, self-assessment, and Qdrant storage
- **Per-agent metrics** — step duration, complexity self-report, bottleneck flags stored to Qdrant
- **Cost optimization skill** — 4 axes: model selection, file scoping, dispatch prompt trimming, token tracking
- **EPIC completion summary** — 5 next-step options presented to PM at DONE state
- **Auto-archive** — multi-EPIC and multi-session counter awareness for session and EPIC files
- **Multi-session flow** — planner optimization engine for EPICs with 7+ steps
- **Diff patches** — `diff.patch` generation for every file-modifying step, saved to evidence store
- **Curator auto-invocation** — mandatory synchronous step in POST_PROCESSING
- **Chat-first `/aid-setup`** — detailed option presentation and guided configuration
- **Post-setup guidance** — `/aid-brainstorm` recommendation after onboarding
- **Playwright E2E agent** — optional parallel step, auto-added when frontend detected
- **Application type classification** — 11 types in project scanner (web-app, api-service, cli-tool, desktop-app, mobile-app, library, plugin, script, monorepo, erp-module, infrastructure)
- **Auto-scaffold** — generates starter files for uninitialized projects before EPIC execution
- **Cross-project knowledge** — Qdrant with `project_name` metadata tagging for multi-project memory
- **Backlog categorization** — by type (bug, enhancement, tech-debt, security, docs) and source agent
- **`/aid-analytics`** — orchestration performance analysis command and skill
- **Permission presets** — dual-write system keeping `.claude/settings.json` + `.aid-o` policies in sync
- **Git branch integration** — one branch per EPIC session, auto-create and auto-merge
- **Pre-Output Quality Check** — in all code-producing playbooks (ruff lint/format, debug artifact removal, import verification)

### Fixed
- **DONE state** — now writes lessons to `lessons-learned.md`, updates session status to `completed`, writes commands to `command-history.md`, writes final `stage_log` entry with `result: success`
- **Gate reconciliation** — `plan.json` gates now reconciled with `gates.yaml` definitions
- **Qdrant isolation** — writes now include `project_name` metadata for cross-project isolation
- **Slack MCP** — onboarding corrected to use `@anthropic/slack-mcp` package with proper scopes

### Changed
- **Agent model assignments** — QA, Security, Docs agents use Sonnet; utility agents use Haiku
- **Dispatch prompts** — trimmed to deps-only context, EPIC summary, and playbook reference
- **`/aid-help` examples** — updated with full-stack development examples
- **Memory search** — `top_k` reduced from 5 to 3 for relevance and cost optimization
- **Git Discipline** — section added to all 9 role playbooks

## [0.2.0] — 2026-02-18

### Added
- **`/aid-brainstorm`** — 9-step interactive brainstorming flow (context → questions → approaches → design → sections → approval → document → EPIC draft → handoff)
- **Brainstorming skill** — process rules, key principles, EPIC subagent prompt template
- **MCP server onboarding** — Qdrant local (no Docker), Slack opt-in, auto-detect, custom
- **Permission presets** — Safe / Recommended / Advanced in `/aid-setup`
- **Document language** — `language.yaml` configuration with ISO 639-1, default EN
- **Parallel isolation strategy** — `dispatch-strategy.yaml` with worktrees / branches / sequential
- **Git worktree support** — creation and cleanup logic for parallel agent dispatch
- **Qdrant orchestration logging** — dispatch and completion events with graceful JSONL fallback
- **Enriched `final_report.md`** — generation from Qdrant data
- **Lessons learned** — auto-collection and storage in Qdrant at EPIC completion
- **CLAUDE.md marker merge** — `<!-- AID-O START/END -->` markers in `/aid-init`
- **Interactive examples** — `/aid-help examples` with 3 project prompts

### Changed
- **`/aid-setup`** — includes 4 new configuration steps (MCP, permissions, language, isolation)
- **`/aid-init`** — copies `dispatch-strategy.yaml` and `language.yaml` to workspace
- **LLM cost estimates** — conditioned on `billing_mode: api` (hidden for subscription users)

### Removed
- **`examples/bookmark-manager/`** — replaced by interactive `/aid-brainstorm` prompts

## [0.1.0] — 2026-02-16

### Added
- **Initial release** — Controller + Workers architecture for Claude Code
- **17 slash commands** — `/aid-init`, `/aid-setup`, `/run-epic`, `/plan-epic`, etc.
- **18 agents** — 9 role + 3 specialist + 6 utility
- **13 skills** — epic orchestration, planner, gates engine, parallel dispatch, etc.
- **11 role playbooks** — customizable per project
- **Quality gates** — auto-retry (3x) and PM escalation
- **Slack MCP integration** — with chat fallback
- **Qdrant vector memory** — optional, with file-based fallback
- **EPIC queue** — autonomous sequential execution
- **Evidence trail** — `stage_log.jsonl`, gate reports, agent outputs
