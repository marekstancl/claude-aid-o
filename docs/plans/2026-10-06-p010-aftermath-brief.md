# Zadání: po P010 — zavření plánu rozhodnutím, kola bez patu, měření regresí ze zavírání (AID 2.114.0)

**Vznik:** 6. 10. 2026, z nových zápisů v `aid-plugin-issues.md` projektů agents (30. 9.–6. 10.), aid-orchestrator (30. 9.–4. 10.) a wan (6. 10.). Kroky 12–13 (visual companion) přidal PM 6. 10.: „opravit teď v tomhle kole“. PM rozhodl 6. 10.: 1A (celý balík v jednom vydání), 2A (pravidlo + měření, bez tvrdého stropu), 3A (Codex zůstává, kde je; měření níže).
**Staví se mimo AID** (CLAUDE.md „Vývoj mimo AID“): worktree mimo `.aid-worktrees/` plánů, Codex revize zadání a každého kroku, dokumentace s každým krokem, revize celého diffu, T0+T1 + dotčené sady, testbed, vydání jen na slovo PM.

## Proč (co se stalo)

- P010 (agents) se po dvanácti kolech CP7 nedal zavřít: dva nálezy Codexu zůstaly `major` (jeden autor vyvrátil měřením, druhý PM odložil do backlogu B-225) a `plan-finalize --stage decide` nemá žádnou cestu, jak nález vyřídit jinak než opravou. Kód se slil ručně, FSM tvrdí `PLAN_REVIEW`.
- V témže zavírání čtyři z posledních nálezů zavedl opravář při opravě předchozího; plugin to má v datech (`fix-class.json`, předchozí kandidát), ale nesčítá.
- Limit účtu shodil všechny role kola najednou; `retry` chce sebrané kolo a `dispatch` odmítá podruhé, takže roli bez odpovědi nejde znovu spustit, dokud neodpoví ostatní.
- Controller rozeslal brackety pro tři role, kolo mělo jednu; dva starty bez `complete` jde vyřídit jen `--force` nebo vymyšleným výstupem.
- Konec plánu projde bez jediného změřeného kritéria: `plan-diff` bere jen `## Acceptance|Success Criteria` + `- [ ] AC<N>:`; kroková kritéria (`**Acceptance Criteria:**` v krocích, u P010 ~57 proti 13) ignoruje beze slova, `produce` zapíše `status: pass` / `aggregation: prose_only` a karta `decide` o tom mlčí. Codex to čtyřikrát za sebou hlásil jako blocker.
- Menší potvrzené mezery z našich běhů (P106, P108): fix-check bere za „jmenující“ jen blocker/major s krokem; readiness nemá `--project-root`; název s `/aid-ui` je odmítnut jako cesta; companion po aktualizaci pluginu padne na chybějících `node_modules`; kritik zahodí běh, když se plán upraví před `aid_critic_check`; `approve` chce stránku brainstormu, kterou krok 10 nejmenuje.

## Měření 3A: Codex v P010 (evidence agents, 13 kol CP3 + 21 pokusů CP7)

| | role na Codexu | blocker+major | z toho opraveno | z toho zamítnuto na formě | běhů bez odpovědi |
|---|---|---|---|---|---|
| CP3 | epic_security | 23 | 17 (74 %) | 0 | 2/13 (timeout) |
| CP7 | final_generalist | 18 | 0 | 18 (100 %) | 5/21 (3× limit, 2× exit 1) |

Role na Claude pro srovnání: CP3 epic_behaviour 11/15 opraveno (73 %), epic_generalist 11/13 (85 %). Čas odpovědi Codexu (mtime promptu → mtime odpovědi): CP3 1–4 min, CP7 1–5 min (jednou 12); role na Claude 4–6 min. Tvrzení „10–17 min na kolo“ soubory nepotvrzují. Nálezy se mezi rolemi nepřekrývají (každý nález má jednoho reportéra), takže „unikátní pro Codex“ nic neříká.

**Závěr:** v CP3 je Codex stejně užitečný a stejně rychlý jako role na Claude; v CP7 nepřinesl jediný přijatý nález, protože všech 18 padlo na formě (důkaz mimo repozitář kandidáta, typicky `/opt/eco/docs`), a přesto blokovaly rozhodnutí. Codex se nikam nepřesouvá; opravuje se cesta pro nález zamítnutý na formě (bod 1) a zapisuje se počet nálezů Codexu zamítnutých na formě do souhrnu kola, aby bylo vidět, jestli to po opravě evidence rule přetrvá.

## Co se změní (kroky)

Každý krok s kódem: jeden bats případ na pravidlo (odmítací cesta) + řádek v CHANGELOG + řádek v registru vynucení (jen pro skutečně vynucované pravidlo) + dokumentace (skill/command, Docusaurus `/aid/`). Čistě dokumentační krok (9) má jen CHANGELOG a kontrolu konzistence instrukcí (`test-instruction-consistency.sh`), žádný test ani registr (Codex).

### Krok 1 — `dispute` pro CP7 (aid-review-round.sh)
- `dispute --checkpoint cp7 --evidence-dir … --round N --fingerprint F --reason "…" [--pm accepted|rejected --finding-card <karta>]` se chová jako u CP2/CP3: bez `--pm` → `disputed`; `--pm accepted` → `fixed` se záznamem `dispute.pm` (karta musí nález citovat, PM musí odpovědět po kartě — stejná kontrola jako dnes); `--pm rejected` → `open`.
- Platí i pro nález se stavem `form_invalid` (dnes blokuje `decide` a nejde vyřídit).
- `plan_final_review_equivalent` / `decide` pak nález se stavem `fixed` přes dispute neblokuje (ověřit, že čte stav z merged.json, ne z `reviewer-*.json`).
- Dokumentace: `commands/aid-run.md` (konec plánu), `skills/step-review-roles.md` (co se stane s nálezem), Docusaurus stránka plan-final.
- Codex (revize zadání): kontrola karty platí jen pro `MODE=step` — ověřeno: CP7 je `MODE=step` (řádek 128), kontrola tedy platí; test přesto pokryje obě chybějící doložení (bez karty, bez odpovědi PM po kartě).
- AC: plán s jedním `major` ve stavu `form_invalid` v posledním kole CP7 se po `dispute --pm accepted` dostane přes `decide`; bez karty nebo bez odpovědi PM dispute odmítne.

### Krok 2 — `retry` v nesebraném kole (aid-review-round.sh)
- `retry --role R` v kole bez `collect.json` projde jen při přesně určeném stavu role: R je v `reviewers_expected` kola, `reviewer-R.json` neexistuje nebo je prázdný (prázdný soubor = revizor nic nenapsal), a buď `codex-R.usage.json` říká `answered: false`, nebo role nemá v bracketu `complete`. Otevřený `start` bez `complete` retry uzavře událostí `cancel` s důvodem `retry` (krok 3), aby nový bracket nestál vedle starého. Role mimo kolo, role s odpovědí (i bez bracketu — to řeší dnešní cesta po `collect`) → odmítnuto.
- Chování po průchodu stejné jako dnes (re-probe Codexu, nebo nový bracket pro Claude).
- AC: kolo, kde Codex skončil `rate_limited` a ostatní role neodpověděly, dovolí `retry` té role; role s odpovědí a role mimo kolo jsou odmítnuty; otevřený start je po retry zrušený, ne sirotčí.

### Krok 3 — `start` odmítne cizí fokus, `cancel` uzavře start (aid-emit-dispatch.sh, aid-fsm.sh, aid-review-round.sh)
- `start --focus F --evidence-dir D`: když `D/round.json` existuje a role odvozená z F (`cp3-epic-security` → `epic_security`) není v `reviewers_expected`, odmítne s výpisem rolí kola. Bez `round.json` (dispatch mimo kolo) beze změny.
- `cancel --focus F --evidence-dir D --reason "…"` (důvod ≥ 20 znaků) zapíše událost `cancel` k otevřenému startu do `pending-dispatches.jsonl` i do timeline (`verifier_dispatch_cancel`). Význam ve VŠECH čtečkách bracketu (vyjmenovat grepem při stavbě; dnes známé: `fsm_check_orphan_dispatches` v aid-fsm.sh, `_dispatch_recorded` a kontrola `dispatch_orphan_complete` v aid-review-round.sh): zrušený start není sirotek, ale také NENÍ `complete` — odpověď role se zrušeným startem nemá původ a `close` ji dál odmítá (Codex: cancel nesmí prokázat doručení odpovědi). `close` zrušené starty jmenuje v souhrnu.
- Dokumentace: hlavička skriptu, `commands/aid-run.md` (bracket), Docusaurus dispatch.
- AC: start pro roli mimo kolo spadne hned; zrušený start nezablokuje `close`; `cancel` bez startu nebo bez důvodu odmítnut.

### Krok 4 — fix-check: minor a plán-level jmenují krok (aid-review-round.sh `_open_fix_list`)
- Minor nálezy s krokem jmenují svůj krok stejně jako blocker/major.
- Plán-level nález (step null) blocker/major: fix list = `any`. Nový tvar musí znát parser `aid-plan-check.sh` (`FIX_STEPS` z `--fixes`, řádek ~527): `any` = každý krok je ve fix listu, C4 (dotčený krok) a C5 (přidané Files/AC/kroky) se nehlásí, všechny ostatní kontroly běží. Důvod: oprava plán-level nálezu nutně dopadne do některého kroku. Když jsou otevřené jen minory bez kroku → `none` jako dnes.
- `_check_fix` volá i `finalize` (řádek ~1022) — test pokryje i tuhle cestu (finalize po plán-level nálezu).
- `--also-steps` z 2.113.0 zůstává pro případ „krok B opakuje hodnotu z kroku A“.
- AC: kolo s plán-level majorem + minorem na kroku 5 pustí úpravu kroku 5 bez `--also-steps`; kolo jen s majorem na kroku 2 dál odmítne úpravu kroku 5; `finalize` s fix listem `any` projde beze změny chování ostatních kontrol.

### Krok 5 — readiness `--project-root` (aid-generation-readiness.sh)
- Stejný přepínač a sémantika jako `aid-plan-check.sh`: existence cest se ověřuje proti danému stromu. `/aid-plan` ho předává, když plán má `depends_on_plans` a worktree závislosti existuje.
- AC: plán odkazující soubor, který je jen ve worktree P103, projde readiness s `--project-root` na ten worktree a spadne bez něj.

### Krok 6 — lomítko v názvu není cesta (lib/aid-artifact-render.sh `_aid_artifact_looks_like_path`)
- Cesta musí mít aspoň dvě složky nebo příponu: `/aid-ui studio` ne, `/opt/eco` ano, `./x.sh` ano, `lib/a.sh` ano.
- AC: název „the /aid-ui studio“ v bloku 5 projde; `/opt/eco/docs/x.md` je dál odmítnut.

### Krok 7 — companion si doinstaluje `node_modules` (lib/brainstorm-server/start-server.sh)
- Před startem: když chybí `node_modules/express`, spustí `npm install --no-audit --no-fund` v adresáři serveru a zapíše to do `.server.log`; když instalace selže, vypíše JSON s chybou a přesným příkazem místo „failed to start within 5 seconds“.
- AC: start bez `node_modules` doběhne (test s přejmenovaným adresářem a `npm` nahrazeným stubem, který složku vytvoří); selhání `npm` vrátí JSON s příkazem.

### Krok 8 — kritik: úprava plánu před `check` nezahodí běh (lib/aid-critic.sh, commands/aid-plan.md)
- `aid_critic_check` ověřuje formu odpovědi a reakce autora (prompt jmenuje cestu plánu, kritik ho čte z disku při běhu; otisk plánu je v `prepare.json`); když se plán na disku od `prepare` změnil, zapíše tuhle revizi rovnou jako `plan_sha256_revised` (jediná povolená revize) a vypíše to; následný `rebind` pak odmítne jako dnes („already rebound once“).
- Codex namítá, že odpověď kritika je vázaná na kritizovanou verzi. Proč je to přesto totéž jako dnešní check → rebind: check dnes ověřuje FORMU odpovědi a odpovědi autora (nadpisy, počet položek, řádky odpovědi, soubor u přijaté položky), ne obsah proti plánu; obsahově je odpověď v obou pořadích vázaná na plán z `prepare.json` (otisk zapsaný při přípravě) a autor plán změnil jednou po ní. Rozdíl je jen v pořadí dvou příkazů, a právě to pořadí dnes stojí jeden běh kritika. Zapsat do hlavičky `aid-critic.sh`.
- `commands/aid-plan.md` 8a: pořadí „check → úprava → rebind, nebo úprava → check (revize se zapíše při checku)“ jednou větou.
- AC: plán změněný mezi `prepare` a `check` projde checkem s `plan_sha256_revised` a `check.json` nese oba otisky; druhá změna + `rebind` odmítnuto; packet CP1 bere `critic-response.md` i pro revizi zapsanou checkem (hash `plan_sha256_revised`).

### Krok 9 — stránka brainstormu v kroku 10 (commands/aid-plan.md)
- Krok 10 jmenuje `aid_brainstorm_summary_render` před `approve` a říká, proč (approve bez stránky odmítne). Jen dokumentace.

### Krok 10 — konec plánu říká, co nezměřil (aid-plan-diff.sh, aid-plan-fsm.sh produce + decide)
- `aid-plan-diff.sh`: do `summary.unmeasured` přidá `step_bullets` = počet odrážek pod `**Acceptance Criteria:**` v krocích, které parser nebere, `summary_prose` = počet rozparsovaných souhrnných kritérií bez vzoru a `summary_unparsed` = souhrnné odrážky bez značky `AC<N>:`, které parser nebere. Při graceful skip (žádný vzor) totéž (jména klíčů upřesněna při stavbě).
- `produce`: do `acceptance-evidence.json` zapíše `verdict.unmeasured: {summary_prose: N, step_bullets: M}` a vypíše jednu větu („změřeno 0 ze 13 souhrnných kritérií, 57 krokových odrážek neměřeno“).
- `decide`: karta pro PM nese tu větu jako řádek; `status: pass` zůstává (PM varianta A pro P010 — doklad je v CP2 kolech), jen už ne potichu.
- `aid-release-policy.sh` (řádek ~255) dnes u `prose_only` říká „kritéria posoudily recenze“; jeho zdůvodnění ponese tatáž čísla („0 ze 13 souhrnných změřeno, 57 krokových odrážek neměřeno“), aby karta a politika neříkaly dvě věci. Počty odrážek jsou míra toho, co nástroj nezměřil, ne důkaz splnění — tak to i pojmenovat (`unmeasured`, ne `unmet`).
- AC: plán bez vzorů dostane v evidence `unmeasured` s nenulovými čísly, věta je v kartě i ve zdůvodnění release policy; plán, kde všechna kritéria mají vzor a prošla, má `unmeasured` nulové.

### Krok 11 — 2A: pravidla zavírání + měření regresí ze zavírání (commands/aid-run.md, aid-review-round.sh close u CP7)
- Pravidla do `commands/aid-run.md` (sekce oprav po kole a konce plánu): (a) opravovat po třídách nálezů, ne po nálezech — jedno kolo potvrzení na dávku; (b) opravář před commitem vyjmenuje všechny volající měněné funkce a každé místo, kde platí pravidlo, které oprava zavádí (`graphify explain` nebo grep), a napíše to do commit message; (c) doporučení pro agenta, ne brána pluginu (2A: bez tvrdého stropu): když třetí kolo CP7 za sebou hlásí nález na řádcích změněných až při zavírání, agent neopravuje, sepíše nálezy do backlogu a dá PM kartu zavřít / pokračovat / odložit.
- `close` u CP7 spočítá a zapíše do `measurement.json` `closing: {attempt, minutes_since_first_freeze, findings_on_lines_changed_at_close, codex_form_invalid}`. Codex: soubor změněný od prvního kandidáta ještě nedokazuje, že nález vznikl opravou — proto se měří na řádcích, ne na souborech: první citace nálezu `path:N[-M]` → `git blame -L N,M HEAD -- path`; nález se počítá, když commit řádku NENÍ předkem prvního kandidáta (= řádek napsalo zavírání). První kandidát z řetězu `fix-class.json` → `previous_run_dir`. Citace bez řádku se nepočítá a je vykázána zvlášť (`uncited_lines`). Pojmenování říká, co to je: korelace s řádky ze zavírání, ne rozsudek. `codex_form_invalid` = nálezy role na Codexu ve stavu `form_invalid`. Souhrn `close` vypíše řádek „zavírání: pokus N, M min, nálezy na řádcích ze zavírání: R“.
- AC: kolo CP7 nad druhým kandidátem s nálezem citujícím řádek napsaný opravou má hodnotu 1; nález citující řádek starší než první kandidát 0; nález bez čísla řádku jde do `uncited_lines`.

### Krok 12 — companion: pevný port z rozsahu AID, žádný náhodný (lib/brainstorm-server/start-server.sh, stop-server.sh)
Proč: PM z notebooku přes VPN neotevře náhodný vysoký port (49152–65535, dnes losovaný v `index.js:9`, start ho nepředává); porty z rozsahů projektů procházejí. Zápisy agents 6. 10. (P013) a WAN 6. 10. (helpdesk), oba „ERR_ADDRESS_UNREACHABLE / connection refused“, oba skončily obejitím přes Artifact. Že rozsah 3900–3999 přes VPN prochází, je **ověřený provozní předpoklad** (studio na 3915/3916 PM používá denně), ne vlastnost tohoto kódu — tak to říká i dokumentace.
- Nový přepínač `--port <N>`. Při vazbě mimo loopback (`--host` ≠ 127.0.0.1) se port losuje jen z **companion slotů 3910, 3912** (`AID_COMPANION_PORTS`, rozsah AID 3910–3919; 3911 cockpit, 3913–3917 studio /aid-ui); první volný. Port mimo 3900–3999 při vazbě mimo loopback odmítnut s vysvětlením. Loopback běh smí dál losovat vysoký port.
- Obsazený slot se **nepřebírá** (Codex: souběžné relace PM jsou dnes možné jen díky náhodným portům). Všechny sloty obsazené → odmítnout a vypsat, kdo je drží (`ss -ltnp`: PID, příkaz, stáří), s přesným příkazem `stop-server.sh <screen_dir>` pro companiony tohoto pluginu a s `--port` pro výjimku.
- Po startu `curl` na vytištěnou adresu (`http://<url-host>:<port>/`) z hostitele; neúspěch = chyba v JSON, ne URL. JSON nese `bind_host`, `url_host`, `port` a větu „otevři z notebooku na VPN“. Průchod z klienta na VPN kód doložit neumí: AC níže má ruční ověření PM (verification-only).
- `stop-server.sh --stale [hours] --project-dir <root>`: zastaví companiony **tohoto projektu** (`.aid-o/work/companion/*/.server.pid`) starší než N hodin (výchozí 24), a jen když PID běží `node index.js` z `lib/brainstorm-server` tohoto nebo cache pluginu (kontrola `/proc/<pid>/cmdline` a `cwd`); nic jiného nezabíjí. Skill ho jmenuje v kroku úklidu. Dnes na eco-dev běží 12 companionů starých 1–48 dní.
- Dokumentace: skill (Starting a Session a Standalone 3b: vzdálená relace = `--host 0.0.0.0 --url-host 10.20.20.22`, port se neřeší), Docusaurus `/aid/` companion, **guardrails G-008 port mapa** (3910/3912 companion, 3911 cockpit, 3915 studio, 3916 brand, 3917 náhled — dnes mapa zná jen 3911).
- AC: start s `--host 0.0.0.0` bez `--port` poslouchá na 3910, druhý start na 3912, třetí odmítnut se jmény držitelů; `--port 50000` s `--host 0.0.0.0` odmítnut; `--stale` zastaví jen companiony projektu a jen procesy `index.js` (cizí PID v `.server.pid` nechá); ruční: PM otevře URL z notebooku na VPN (verification-only, delete before plan-final).

### Krok 13 — companion: obrazovku o existující aplikaci skládá server nad jejím skutečným snímkem (start-server.sh, nový lib/brainstorm-server/basis.js, scripts/lib/aid-ui-proposal.sh, aid-brainstorm-state.sh, skills/visual-companion/SKILL.md)
Proč: PM opakovaně dostává návrh „od oka“ — jiné prvky, jiné odsazení, zakázané ikony — místo skutečného stavu aplikace s doplněnou změnou. Pravidlo ve skillu existuje (sekce „Refactoring or Redesigning Existing UI“, 60 řádků uprostřed 452), brána existuje (`aid-brainstorm-state.sh enter-phase design` chce `proposal.json` se základem), ale obě stojí mimo cestu: agent u P013 (scope user_visible, kind ui) `enter-phase` nikdy nezavolal; u WAN helpdesku byl běh `roadmap`, brána se netýkala (topic_kind se ptá jen u user_visible). Companion sám nechce nic a zobrazí cokoli.
- **Jedna sdílená kontrola vstupního podkladu** `aid_ui_proposal_basis_check <proposal.json> <root>` v `aid-ui-proposal.sh` (Codex: brána dnes ověřuje jen typ základu a neprázdné viewporty, snímky ne; plná `aid_ui_proposal_check` chce už hotové `proposed`, před návrhem nepoužitelná): základ `live-screen` → `baseline.png` existuje a je neprázdný pro každý viewport, který projekt dluží; základ `design-system` → nese označení NO LIVE BASELINE a důvod. Volá ji `enter-phase design` (místo dnešního jq) i `start-server.sh`.
- `start-server.sh --project-dir <root>` vyžaduje `--plan <id>` a čte `.aid-o/work/brainstorm/<id>/state.yaml`. Prázdný `topic_kind` → odmítne s příkazem `aid-brainstorm-state.sh topic-kind <id> ui|other --reason` — tím se zavře únik přes scope `roadmap`: u každého companionu v projektu agent řekne, zda jde o obrazovku existující aplikace, a „other“ nese důvod, který stránka návrhu ukáže. `topic_kind: ui` → podklad podle sdílené kontroly, jinak odmítnutí s příkazem `aid_ui_proposal_build`. Standalone demo (`/visual-companion` bez `--project-dir`, soubory v /tmp) zůstává bez brány; skill to říká v Standalone bodu 3b a v Starting a Session (všechna tři uvedená volání se upraví, migrační AC níže).
- **Server skládá stránku sám** (Codex: značka v HTML nic nedokazuje): v UI běhu dostane `BRAINSTORM_BASIS=<proposal.json>`; `basis.js` servíruje snímky pod `/basis/<viewport>/baseline.png` a pro `/` sestaví rozložení „dnes → návrh“: levý sloupec = skutečný snímek viewportu v reálném měřítku (šířka z `proposal.json`), pravý = obrazovka agenta ve stejné šířce; přepínač viewportů, když jich projekt dluží víc. Při základu `design-system` server místo snímku ukáže pruh NO LIVE BASELINE s důvodem z `marked`. Agent to nemůže vynechat ani přepsat; `isFullDocument` obrazovky se v UI běhu vkládá do pravého sloupce. Mimo UI běh se `/` nemění.
- `aid_ui_proposal_build` dnes při zadané obrazovce bez čitelných fixture dat tiše přejde na `design-system` (řádek ~123): nově to zapíše do `marked` jmenovitě („obrazovka zadána, fixture data nečitelná: <cesta>“), aby PM viděl proč není snímek. Zákaz cizích ikon a obrázků textový filtr ověřit neumí → zůstává pravidlem skillu a otázkou revize návrhu (CP1 role generalist_a: „staví návrh na komponentách a tokenech aplikace z `design_system`?“).
- Skill: první sekce po úvodu = tvrdý krok „Existující UI: nejdřív podklad z aplikace“ (≈10 řádků: `topic-kind` → `aid_ui_proposal_build` → `start-server.sh --plan` → server ukáže dnes vedle návrhu), stávající dlouhá sekce se zkrátí na to, co podklad nevyřeší (inventura dat, otázka PM).
- Souběh s větví plan/P103 (mění `index.js`, ruší confirm-store): nová logika v `basis.js`, v `index.js` tři řádky (require, route, volání v `/`); P103 se rebasuje na main před svým vydáním a po rebase projde ruční seznam: start, zobrazení obrazovky, potvrzení, reload přes WebSocket. Zapsat do `.aid-o/work/P108-STAV…` / plan P103 poznámky.
- Dokumentace: Docusaurus `/aid/` companion + brainstorming; CHANGELOG; registr (pravidlo vynucené serverem a startem).
- AC: UI běh bez `proposal.json` → start odmítnut s příkazem; `proposal.json` live-screen bez `baseline.png` → odmítnut sdílenou kontrolou (stejně v `enter-phase design`); UI běh s podkladem → `/` nese levý sloupec se snímkem a pravý s obrazovkou, `/basis/desktop/baseline.png` vrací soubor; design-system → pruh NO LIVE BASELINE s důvodem; `topic_kind` prázdný → odmítnuto s příkazem; `topic_kind: other` → `/` beze změny; `--project-dir` bez `--plan` → odmítnuto; standalone bez `--project-dir` → beze změny; všechna volání `start-server.sh` ve skillu a v `commands/aid-plan.md` mají `--plan` (test konzistence instrukcí).

### Krok 14 — HOTOVO značky a úklid (po vydání)
- Zápisy agents (11) a aid-orchestrator (8) a WAN (1) dostanou značku s verzí; na eco-dev se zastaví staré companiony (`--stale`) a agent oznámí PM, které porty se uvolnily.

## Revize zadání (Codex, 6. 10. 2026)

Kroky 12–13, šest nálezů, zapracované: průchod VPN jako provozní předpoklad + ruční ověření PM; žádné automatické převzetí portu, sloty 3910/3912, `--stale` jen pro projekt a jen procesy companionu; jedna sdílená kontrola podkladu pro bránu i start, `topic_kind` povinný pro každý companion v projektu (zavírá únik přes roadmap); server skládá „dnes → návrh“ sám místo kontroly značky v HTML; standalone demo bez `--project-dir` zůstává volné, všechna volání ve skillu se upraví; pořadí vůči P103 a ruční seznam po rebase. Neuznáno: „dokumentaci a mapu portů odložit“ — dokumentace je podle CLAUDE.md součást změny.

Kroky 1–11, osm nálezů, všechny zapracované výše: kontrola karty u CP7 (ověřeno, platí — MODE=step), přesný stav role pro `retry` + zrušení otevřeného startu, význam `cancel` ve všech čtečkách (není `complete`), `--fixes any` v parseru plan-check a cesta `finalize`, kritik (ponecháno, zdůvodnění v kroku 8), čísla neměřených kritérií i v release policy, metrika regresí na řádcích přes `git blame` místo souborů + pravidlo (c) jako doporučení, krok 9 bez testu a registru.

## Co se nemění (vědomě)
- Tvrdý strop kol a mutace produkčního kódu jako brána před kolem (PM 2A: nejdřív data z `regressions_at_close`).
- Celý `diff.patch` v potvrzovacím kole zůstává; škrt rozhodne inventura promptů (IMP-679).
- Volba poskytovatele per checkpoint (měření 3A to nepodporuje).
- CP7 fix jako delta bez nového `freeze` (velká změna, zápis 1. 10. bod 4) → backlog.
- Pravidlo evidence u CP7 pro cesty v jiném repu (zápis 4. 10. možnost 3) → po měření `codex_form_invalid`.
- Nestabilní smoke a widget test v repu agents: není vada pluginu.
- Tři zápisy /aid-ui (chat vs. studio, pevný port testů, karty q-variant): větev P103.

## Hotovo, když
- Všech 13 kroků má (kde je kód) test, CHANGELOG, registr a dokumentaci; whole-diff revize Codexem bez otevřeného nálezu; T0+T1 + dotčené sady zelené; `verify.sh --plugin` prošel; 8 míst verze = 2.114.0.
- Po vydání: HOTOVO značky v `agents` (11 zápisů), `aid-orchestrator` (8) a `wan` (1), backlog: CP7 delta bez freeze, evidence rule CP7 (po měření), IMP-679 doplněk o `diff.patch` v potvrzovacím kole.
