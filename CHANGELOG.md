# Changelog

All notable changes to the AID Orchestrator plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [3.11.0] — Unreleased

Převzetí kroku na pozadí (PM 25. 10. 2026, volba 1A): sloučení a testy kroku může hlavní okno běhu pustit na pozadí a mezitím pracovat dál. Mechanika je ověřená testy a testbedem (stejný výsledek jako ruční převzetí, chyby zastaví); kolik času to na skutečném běhu ušetří, se změří na prvním živém plánu. Zadání: `docs/plans/2026-10-25-prevzeti-kroku-na-pozadi.md`.

### Added
- **Převzetí kroku na pozadí** (`scripts/aid-step-land.sh`): mechanickou část převzetí vráceného kroku – ověření návratu, commit, ve vlně sloučení, příkazy akceptačních bodů a měření bodů zadání – dělá skript na pozadí a řadič mezitím přijímá další návraty, posílá agenty na další kroky a vede revize (`AID-WAIT: převzetí kroku N`). Dosud na to řadič čekal v popředí (WAN P115: 53 ze 180 minut). Sloučení vlny se sestaví mimo větev plánu a ta se posune až po zelených kontrolách; při neúspěchu zůstane plán beze změny a strom kroku na své větvi. Skript nic neopravuje (žádné rozšíření rozsahu, změna kontraktu, přejmenování ani opakování) – rozhoduje řadič jako dosud. Každý akceptační bod, jehož text začíná příkazem v backticku, musí dostat právě ten příkaz (`--check "<n>:<příkaz>"`, prostředí zvlášť `--env`). Po opravě z revize kroku `--recheck` pustí tytéž kontroly nad novým HEAD. Záznam `steps/<krok>/land.json`, plné výstupy v `land-logs/`. Zámek převzetí `.aid-o/work/locks/` je běhový soubor (`defaults/.gitignore`, `/aid-init` ho doplní).
- **`increment-step` ověří záznam převzetí** (`lib/aid-land-record.sh`, odmítnutí `land_record_invalid`): krok se záznamem neposune, když v něm chybí příkazový bod, některý neprošel, převzetí ještě běží, patří jinému běhu nebo kroku, za převzetím přibyl commit, změnil se kontrakt či návrat, commity v záznamu neexistují nebo k sobě nesedí (sloučení vlny není to, které git pro jeho rodiče spočítá; sériový commit nesedí na základu; `--recheck` nezačíná od výsledku skutečného převzetí). Začátek a výsledek každého převzetí jde do časové osy běhu: krok, jehož převzetí začalo, se bez záznamu neposune ani po jeho smazání. Krok, který se na pozadí nepřebíral, jde dál ruční cestou jako dosud.

### Changed
- **Konec tahu s otevřeným krokem** (`turn_step_open`) pustí `AID-WAIT:`, když na pozadí ještě běží převzetí právě tohoto kroku (`aid-step-land.sh <stav> <index>`) nebo jeho agent (výzva s hlavičkou jeho kontraktu); jiná úloha na pozadí otevřený krok neomluví. Odmítnutí jmenuje převzetí na pozadí.

### Fixed
- **Kontrola na konci tahu rychlejší** (Stop hook AID): dvě čtečky přepisu sezení četly celý soubor nástrojem `jq` při každém konci tahu – na 186 MB přepisu WANu 13 s. Poslední zpráva se čte od konce, úlohy na pozadí jen z řádků, které je můžou nést (předvýběr podle názvů klíčů a vět, které Claude Code nikdy neescapuje). Syntetický přepis 25 000 řádků: asi 6 s → pod 1 s se shodnými verdikty (`scripts/tests/bench/stop-hook-bench.sh` porovná s libovolnou starší verzí a cíl vynutí); 40 výřezů skutečného přepisu: 0 rozdílů. Vědomé rozdíly jen u poškozeného přepisu: poškozený řádek **před** poslední zprávou modelu už pravidla neslepí (dosud je vypnul pro celé sezení) a při hledání úloh na pozadí se poškozený řádek přeskočí, místo aby skryl všechny řádky za sebou; poškozený řádek za poslední zprávou je chyba jako dřív.
- **Volba bez hodnoty se nezacyklí**: `shift 2` s jedním zbylým argumentem nic neposune; skript bez `set -e` se pak točil donekonečna na 100 % CPU (`aid-plan-check.sh <plan> --json`, WAN P115: 11 minut), skript s `set -u` spadl na `$2: unbound variable` bez vysvětlení. Před každým `shift 2` ve skriptech pluginu teď stojí kontrola dvou zbylých argumentů, ještě než se hodnota přečte: skript skončí kódem 2 s větou, kterou volbu doplnit; uvnitř funkce se vrátí 2 a volajícího neukončí, i když je skript načtený jiným (`return 2 2>/dev/null || exit 2`). Hlídá to `scripts/tests/lib/opt-value-guard.py` (umí i `--fix`) přes test `test-opt-value-guard.bats`.

## [3.10.1] — 2026-10-25

Studio `/aid-ui` hodnotí strukturu na kostře, ne na starém webu.

### Fixed
- **Stálá adresa kostry servíruje jen kostru**: builder píše celý strom (u aplikace každou obrazovku modelu) vždy znovu do `.aid-ui/skeleton/site/` a `aid-ui-serve.sh skeleton` servíruje tu složku; role struktury, jejich snímky, nezávislý ověřovatel i `skeleton-check` vidí jen kostru, ať je v `site/` cokoli (Coufal 17. 10.: role hodnotily starý web). `site/` zůstává základem stavby.
- Přestavba kostry už neodsune stránku, kterou kostra nikdy nepsala (stará stránka, která ze stromu odešla, zůstává v `site/`).
- **Brány nad fakty a právem nejde obejít „nejde posoudit“**: brána s `required: true` (pravdivost tvrzení, nic neznámého ani vymyšleného, odborné a regulované pojmy, fakta mimo registr; u aplikace důvěra v data a čísla) při kritériu, které role nemohla posoudit, směr zastaví; ostatní brány (třeba fotky, které ještě nejsou) se přeskočí jako dřív. Platí pro nově zmrazená měřítka; běžící smyčka si nese brány ze svého zmrazení.
- **Verdikt struktury webu stojí i na servírované kostře**: otisk místa `struktura` zahrnuje `.aid-ui/skeleton/site/`, takže přestavěná kostra s jiným obsahem (třeba po změně registru faktů) verdikt zneplatní. U aplikace ne: její kostra vzniká jen z modelu, který otisk už má, a schválení modelu kostru mění.

## [3.10.0] — 2026-10-24

Automatické stránky AID jdou vypnout a na požádání poslat přes share (PM 22.–24. 10. 2026: stránky po sepsání plánu a na konci PM nechce dostávat sám od sebe; když je chce, přepíná účty Claude a artefakt vidí jen v jednom).

### Added
- **Vypínač `AID_PM_PAGES=off`**: AID stránky plánu, uzávěru a brainstormu jen vykreslí do souboru (kontroly ho čtou) a sám nic nezveřejní (`none <stránka>`); do chatu jde jen karta. Na požádání PM se stránka zveřejní příkazem s `--on-request`. Bez vypínače beze změny.
- **`scripts/aid-pm-page-publish.sh`** zveřejní stránku, kterou AID vyrobí pro PM (plán po CP1, uzávěr, brainstorm). Bez nastavení vypíše `artifact <stránka>` a stránka je claude.ai artefaktem jako dosud. S nastavením `AID_PM_PAGE_PUBLISHER` (cesta ke spustitelnému souboru, nikdy příkaz pro shell; nepovinně `AID_PM_PAGE_PUBLISHER_SUBCOMMAND`) pošle stránku té službě s klíčem `<projekt>-<otisk>/<plán>/<druh>`, názvem, jménem projektu a logem a vypíše `link <odkaz>`; řadič přidá pod kartu řádek `Stránka: <odkaz>`, při selhání `Stránka se nezveřejnila: <důvod>` (nikdy tiše artefakt). Protokol pro vlastní službu je v hlavičce skriptu.
- **Záznam o doručení** `<stránka>.published.json` (otisk stránky, klíč, druh, čas — nikdy odkaz, ten nese klíč PM a patří jen do chatu). S nastavenou službou (a bez `AID_PM_PAGES=off`) ho chtějí kontrola stránky plánu, stránky uzávěru i `aid-brainstorm-state.sh approve`: vykreslená, ale nedoručená stránka se nepočítá. S `AID_PM_PAGES=off` se doručení nevyžaduje.

### Changed
- **Jeden pokyn ke zveřejnění** na všech místech, kde řadič stránku zveřejňuje (`communication.md`, `pipeline.md`, `brainstorming.md`, `aid-plan.md` ×2, `aid-run.md`); `test-communication-wiring.sh` hlídá všech pět míst a že stará věta nikde nezůstala.
- **Schválení brainstormu chce jeho stránku** (`brainstorm-summary-artifact.html`), ne libovolný `.html` v adresáři běhu.

## [3.9.2] — 2026-10-23

### Fixed
- **Popis brány je ve výsledku brány**: `description` z `execution.yaml` se zapíše do řádku brány (`gates_report.json`), takže selhaná brána říká lidsky, co hlídá. Dosud ho šablona psala a nic nečetlo (noční sada `test-execution-yaml-readers` červená od 3.7.0).
- Kontrola plánu čte projektové kontroly (`plan_checks`) ve dvou krocích, takže je kontrola čtenářů klíčů nepovažuje za čtení klíče `command` z nejvyšší úrovně konfigurace (ten skutečně nikdo nečte).

## [3.9.1] — 2026-10-23

Opravy z hlášení projektů (ACTA, agents, WAN, Trading) a noční běh zase zelený tam, kde ho rozbila 3.7.0 a 3.8.0. Každá oprava má test, který bez ní padá.

### Fixed
- **Smazání přes `git rm` se dostane do commitu kroku** (WAN P113): 3.8.0 ho uznala při kontrole, ale commit kroku ho vynechal. Po commitu se ověří, že index na cestách kroku odpovídá HEAD, jinak to pomocník řekne a skončí chybou.
- **Řádek brány nese začátek i konec výstupu** (ACTA P026): dosud prvních 2 000 znaků, takže výsledek testů na konci chyběl; teď 1 000 + 3 000 znaků se značkou vynechání, jedno pravidlo pro všechny řádky.
- **Kolo kontroly plánu s otevřeným blockerem nebo majorem má verdikt `fail`** (ACTA P027): dosud `pass` v timeline i v záznamu kola.
- **`plan-run` nic nezapíše, dokud plán neprojde** (ACTA P027): stránka PM, připravenost a CP1 se ověří před transakcí, commitem plánu, stavem plánu i zámkem; odmítnutí `cp1_not_passed` (s označením, zda ho pokryje `--force`).
- **Verze z CHANGELOGu nečte ukázku v bloku kódu** (WAN P112, P113): `--bump none` bere nejvyšší verzi mimo bloky ``` a `~~~`, vydání dál horní sekci.
- **B10 („is to be removed“) jen pro soubor, který plán opravdu maže** (`must_not_exist`, `Delete:`), ne pro `must_contain` (ACTA P026).
- **Cesta API v textu kroku není soubor cizího repa** (WAN P113): bez přípony, neexistující a mimo `repo_roots` se přeskočí.
- **Dvě cesty v jedné odrážce `Files:`**: `` `a`; `b` `` platí jako `` `a` + `b` ``; řádek bez backticků s druhou cestou za `;` je chyba, ne tichá ztráta (agents P012).
- **Schválení vize, která už leží v `.aid-o/plans/<id>-vision.md`**, projde (WAN P113).
- **Složka v `Files:` (`dir/`) a pre-commit hook**: hook a kontrakt kroku mají jedno pravidlo rozsahu (`_aid_path_covers`), test drží obě kopie stejné (WAN P110, P112).
- **Administrativní uzavření plánu se smazanou větví** (WAN P082, P084, P094): sloučení dokládá zapsaný kandidát; bez větve i kandidáta se plán uzavře jako `closed_administrative` bez tvrzení o sloučení a bez potvrzení pro závislé plány.
- **`/aid-init` zapíše do `.gitignore` běhové soubory AID** (zámky, logy, ukazatele, cache, companion; Trading); test rozhodne každý soubor, který skripty v `.aid-o/work` píšou, jako běhový nebo verzovaný.
- Projektová politika, která sama uvádí roli `final_claims`, ji má jednou (3.8.0 ji přidala podruhé).
- Noční sady zase zelené: `test-review-config`, `test-recovery-ladder` (3.8.0), `test-plan-run`, `test-plan-tier-declaration`, `test-plan-fixture-contract`, `test-plan-review-acceptance` (od 3.7.0: testy zakládaly kolo kontroly nad plánem, který příprava kola odmítne; přehrávaný plán ACTA deklaruje repo dokumentace).

## [3.9.0] — 2026-10-23

Studio `/aid-ui` umí webové aplikace (P116) a je svižné a přesné (P118): obrazovky a úlohy místo stránek, kostra a testy úloh z jednoho modelu, předání jako zadání změn kódu; hodnocení bez vlastních známek výrobce, nezávislý ověřovatel s podpisem běží s rolemi, kontrola kostry 54 → 4 min, kolo rolí 6 h → 7 min. Ověřeno na aplikaci Trading od nuly: struktura přijatá (vlastník 9,0, odborník 8,0), PM vybral vzhled ze tří skutečných návrhů a celé UI (17 obrazovek) prošlo hodnocením.

### Added
- **Webová aplikace (`variant.type: webapp`)** jako vlastní cesta studia (`references/local/aplikace-postup.md`): model obrazovek a úloh `docs/design/screens.json` (schéma `references/screens.schema.json`), úlohy se sedmi stavy, výsledkem (`done_when`) a cestami selhání; kostra z modelu (`aid-ui-serve.sh skeleton`, :3918) s přepínačem stavů a režimů; brána úloh `app_flows`, `app_states`, `keyboard_flows`, `task_recovery` a řádky režimů; existující aplikace se zahraje a porovná (`aid-ui-baseline.py`); balík verze 2 a zadání změn kódu (`aid-ui-package.py zadani`).
- **Lint modelu** (`aid-ui-screens.py check`): částka, R, procento, páka i mez (znaky, čas, počet) napsaná přímo místo pojmenované hodnoty, číslo v účelu obrazovky, zapisující úloha bez oprávnění nebo bez cesty selhání sítě i serveru, pole slibující mez, kterou nemá, úloha nového chování bez požadavku (`new`).
- **Fakta appky** (`aid-ui-client.py facts`): Codex a Claude Opus souběžně a nezávisle, soudce páruje stejná tvrzení bez ohledu na id a řádky, dohodnutá fakta přežijí další běh, lint blokuje jen rozpory; povinná u existující aplikace.
- **Nezávislý ověřovatel** (`aid-ui-client.py verify`): nafotí každou adresu verze (i vypnuté akce, obsah polí a potvrzení slovy), Codex (záskok Opus) hledá rozpory a ověřuje opravy; podepsaný záznam mimo projekt. **Běží s rolemi v kole** (PM 21. 10., 1A), jeho rozpory a neviděné opravy jsou nálezy kola.
- **Klient-agent** dodá, co role nechaly na klientovi (`supply`), a schvaluje model aplikace za vlastníka; `aid-ui-client.py decided` vypíše, co rozhodl bez PM.
- **Delta kolo** po přijatém místě nad opravenou verzí; věcná chyba nalezená v delta kole dostane ještě jedno; `place-verdict --fixed-in` a `place-record` přestanou počítat věcnou chybu, kterou ověřovatel viděl opravenou.
- `aid-ui-verify.sh --quick` (nejširší šířka, ~3 min), pool pracovníků brány `AID_UI_GATE_WORKERS`, fáze kola a jejich čas ve `status`, zadání oprav pro výrobce v čerstvém kontextu (`aid-ui-quality.py brief`), výsledek rychlé kontroly v podkladech rolí (`testy-kostry.md`).

### Changed
- **Kolo hotové aplikace kolem 15 minut** (PM 23. 10., 1A): před kolem jen rychlá kontrola nad modelem a touto verzí webu (Trading 3,6 min), plná brána jednou před předáním; opravují se jen přijaté nálezy. Dřív 60-90 minut na cyklus.
- Brána aplikace neměří kontroly firemního webu (`web_only` v checks.yaml: IČO, značka, favicon, kontaktní formulář…), vnucené selhání není rozbitý odkaz, role dostanou výsledek brány v podkladech.
- **Výrobce si už nedává vlastní známky** (`SELF_MIN` pryč): `self` = soupis požadavků, lint a rychlá kontrola nad modelem teď.
- Kostra nabízí akci jen tam, kde dává smysl (bez záznamu, při načítání, obnova až po selhání; lišta nikdy), stav úlohy na obrazovce, kde nastává, vyplněné pole v chybě a selhání, filtr s vlastním formulářem, lišta s ukázkou podle režimu.
- Interní aplikace bez značky se hodnotí bez konkurentů; klient-agent odpovídá česky; `triage`/`fixed` najdou místo nálezu samy.

### Known limits
- IMP-704: pevné porty testů se srazí s nočním CI na tomtéž stroji (obejde se `AID_UI_TEST_PREVIEW_PORT`).
- Tabulka cen a Docusaurus `/aid/commands/aid-ui` popisují stav k vydání; měření H5 na druhé neviděné aplikaci neproběhlo.

## [3.8.0] — 2026-10-21

Plán dojede v `--auto` bez PM a uzávěr se netočí (P117, vstup WAN P109–P112: osm zastavení na PM za dva dny, uzávěr P111 čtyři pokusy a tři hodiny). Každé odmítnutí má třídu, která říká, kdo jedná; technická rozhodnutí v běhu dělá nezávislý zástupce, chráněné dopady pozná kód a jdou na PM; čemu jde předejít, zastaví kontrola plánu nebo start běhu; uzávěr opakuje jen to, co oprava zasáhla.

### Added
- **Registr odmítnutí** `defaults/refusal-classes.yaml`: každý kód, který plugin vypisuje, i každá podmínka `--blocked-checks` má třídu (`agent_fix`, `prevent`, `agent_fix_then_stand_in`, `stand_in`, `pm`, `incident`, `not_in_run`); každé odmítnutí ji vypíše (`class: …`), neznámý kód je `pm`.
- **Zástupce místo PM:** `scripts/aid-stand-in.sh ask|record` pro rozšíření rozsahu, krok bez změny, vizuální kontrolu, technicky selhané měření, přejmenování a blokovaný krok; Codex, při jeho výpadku Claude v závorce dispatch; povolení (`auth.json`) je svázané s návrhem, verdiktem, během a ledgerem a použije se jednou. Přijímají ho `amend-scope --stand-in`, `increment-step --stand-in`, `--defer-criterion … --stand-in` (jen technicky selhané měření, bod změří uzávěr znovu), `amend-contract --rename`, `step-redispatch`.
- **Chráněný dopad pozná kód** (`lib/aid-protected.sh`): zadání a plán, konfigurace AID, `protected_paths` projektu (výchozí `.env*`, `*secret*`, `*credential*`, `deploy/**`, produkční compose), cizí repo mimo `repo_roots`, placená nebo cizí služba, neznámý druh rozhodnutí – vše jde na kartu PM, ať zástupce říká cokoli.
- **`aid-fsm.sh amend-contract --rename old=new`:** čistá záměna cesty ve zmrazeném plánu (plan.json, kontrakt kroku, plán, zadání s verzí +1), obnovené otisky, zneplatněné měření a revize dotčených kroků, kontrola plánu a připravenost znovu, při selhání vše zpět.
- **`aid-fsm.sh step-redispatch`:** krok s blokovaným návratem znovu na povolení zástupce (jen v EXECUTE, svázané s otiskem toho návratu).
- **`aid-review-round.sh accept-risk`:** jedno rozhodnutí PM zavřít s otevřenými nálezy, svázané s kandidátem, kartou a celou sadou; `decide` ho odmítne, když se cokoli z toho změní (`accepted_risk_stale`).
- **Kontrola plánu:** projektové kontroly z `execution.yaml` `plan_checks:` nad cestami, které plán vytváří (B11); body `cmd`, jejichž program tu není nebo čtou proměnnou, kterou izolované měření nemá (B12, s ohledem na uvozovky, `$(…)`, `cd`, `env`, `timeout`); test jmenovaný plánem, který uzávěr neumí spustit (B13).
- **Start běhu** odmítne hostitele bez izolace dřív, než udělá první krok (`no_isolation`, `lib/aid-measure-env.sh`).
- **CP1 závislého plánu:** plán na jednom nesloučeném plánu se kontroluje v jeho pracovní kopii, vazba (plán, worktree, větev, HEAD) se drží v dalších kolech i při startu běhu (`dependency_*`).
- **Uzávěr:** potvrzovací kolo CP7 jen po prošlém plném kole a opravě čistě dokumentace (`lib/aid-docs-surface.sh`), jinak plné kolo; noční testy jmenované plánem pustí uzávěr sám (`execution.yaml` `plan_tests:`, `plan-tests.json` svázaný s kandidátem, plánem a konfigurací); role `final_claims` už v CP2 u kroku, který mění dokumentaci; nález, jehož citované řádky oprava změnila, jde do dalšího kola, ne rozhodčímu (`delegation_fix_pending`).
- **Companion:** `ui.copy_extra[]` (soubory repa mimo `ui.dir`, nikdy tajemství), `capture: {"scroll": …}`, `ui.first_shot_timeout_s` (1–120 s), návod pro Vite s `--configLoader runner`.
- **Cílené opravy místo `--force`:** `aid-emit-dispatch.sh repair` (poškozený záznam dispatch; záznam useknutý dřív, než jde poznat, že to nebyl start, nebo start s nečitelným jménem odmítne a nechá člověku), `cancel` (osiřelý start).

### Fixed
- **`expected_deletions` po commitu kroku** (regrese 3.7.0, WAN P112 stál na `--force`): smazání prokáže commit kroku; smazání přes `git rm` (připravené v indexu, soubor je ještě v HEAD) platí také (nalezeno pilotem testbedu); smazání hotové už před začátkem kroku (kontrakt ho zapíše jako `deleted_before_start`) se neuzná.
- **Commit kroku je transakční** (dočasný index; index uživatele se nikdy nezapíše) a `.aid-o/*` v návratu je hlasité odmítnutí, ne tiché zahození.
- **Jedno prostředí a jeden limit měření** pro krok, bránu i `produce` (`verification_env`, `_pd_effective_timeout`); výstup bodu, který selhal, se ukládá (8 KiB na proud) a tajemství i hesla v URL se redigují dřív, než cokoli jde na disk.
- **Delegace:** nový verdikt jen na nový důkaz, starý `superseded`, nejvýš jednou na nález a kolo (pak PM).
- Stop hook a `communication.md` jmenují `aid_decision_card_render`; `pipeline.md` zakazuje souběh kroků v jedné kopii.
- Zbytkový adresář testu `plugins/aid-orchestrator/2/` (od P094) smazán; citace v registru kontrol po přepisu companionu (noční sada padala na 3.7.0).

### Known limits
- Detektor chráněných dopadů vidí jen to, co návrh deklaruje (cesty, `external`); placené volání v kódu kroku, které návrh nezmíní, chytá revize kroku.
- „Profil uzávěru obsahuje testy plánu“ (bod 2 zadání) je řešený uzávěrem (`plan_tests`) a kontrolou B13, ne rozborem příkazů bran.
- `floor` limitu měření (P112) zvedá i vlastní `timeout:` bodu (vzorec zadání ho nezmínil; cesta přeměření P112 na něm stojí).
- Potvrzovací kolo CP7 a oprava CHANGELOG po CP7 se v testbedu offline neměří (modeloví revizoři); měří je testy `test-review-round.bats`.

## [3.7.0] — 2026-10-19

Companion jako hotová stavebnice a opravy z projektů: agent dodá varianty ze sdílených komponent a tři datové soubory, server, kopii aplikace, focení, stránku i odpovědi PM dělá jeden příkaz. Server companionu se od 2.118.0 vůbec nespustil a poznámky PM se agentovi nezapisovaly – obojí opraveno a hlídáno testem nad skutečným serverem. K tomu 20 oprav z deníků WAN, aidlab-apps, agents, share a AID, každá s testem, který na 3.6.0 padá.

### Added
- **`scripts/aid-companion.sh up|proto|shots|show|answers|down --plan <P>`** – jedna složka na plán (`.aid-o/work/companion/<P>/`): `up` spustí nebo znovu použije server téže verze pluginu, `proto` zkopíruje UI aplikace mimo repo a spustí vývojový server ve vlastní ověřené skupině procesů, `shots` nafotí počítač i telefon nad smyšlenými daty (kroky, selektory, přihlášení, mocky jen na API, volání bez mocku je chyba), `show` postaví pevnou stránku z `navrh.json` a sama ji zkontroluje, `answers` vypíše volby a poznámky PM.
- **Pevná stránka návrhu** podle PM (WAN 19. 10. 2026): jedna obrazovka, tři sloupce, náhled nikdy větší než skutečnost, přepínač počítač/telefon, minulé kolo, přilepená poznámka, „Zvoleno n z m“, textový bod bez náhledu.
- **„Podle existujících vzorů“ hlídá kód:** komponenty v `postaveno_z` musí soubory varianty skutečně importovat z `ui.components` (relativní cesty, aliasy z `tsconfig`, index), nový soubor komponenty jen v `nove[]` s důvodem (PM ho vidí označený), změněný soubor kopie musí patřit právě jedné možnosti.
- **`/aid-init` navrhne klíče `ui`** (`dir`, `components`, `dev_cmd`, `ready_path`, `api_prefix`) z `vite.config.*` / `next.config.*` (`lib/aid-ui-config.sh`).
- **Štítek `Delete:`** v popisu souborů kroku; kontrakt kroku ověří, že sledovaný soubor zmizel a krok ho uvedl v `deleted_files`.
- **`prepare-plan --bump none`** pro verzi, kterou už zvedl krok plánu (čte commitnutý CHANGELOG, nic necommituje).
- **`amend-scope --pm-card <karta>`**: rozšíření rozsahu na výslovné rozhodnutí PM, zapsané jako `pm_decision`.

### Fixed
- **Server companionu se spustí** (od 2.118.0 padal na chybějícím `confirm-store`); volby, poznámky i odeslání PM se zapisují do `answers.jsonl` a nemažou se; websocket přijme jen vlastní stránku.
- **`plan-close` nesmaže pracovní kopii se změnami** (WAN 19. 10. 2026) – odmítne před jakoukoli změnou stavu (`plan_close_worktree_dirty`), smazat jde jen výslovně (`--discard-worktree-changes`).
- **Delegace sporů:** Codex vrací verdikt poslední zprávou (sandbox jen pro čtení ho nezapsal), delegovaný verdikt CP7 nezablokuje uzávěr plánu, náhradník nesmí nechat soubory v pracovní kopii (`delegation_left_files`).
- **Kontrola plánu (CP1):** kolo se nepřipraví nad plánem, který neprošel připraveností (`plan_not_ready`); odložený adresář `round-N.x` není kolo; citace nálezu projde bránou i kontrolou fragmentů (zpětné uvozovky, uvozovka po `>>`).
- **Kritik:** návrh rozsahu v próze se už nehlásí jako prázdná úroveň 2; `\|` v buňce odpovědi nerozbije sloupce; odstavec „Co je v sázce“ jen s cenou se pojmenuje přesně.
- **Kontrola kroku** nespadne na souboru mimo git (`outside_git`, krok jde k revizi); u souborů cizího repa s platným `repo_commits` hlásí „committed there“.
- **`/aid-init`:** testové brány dostanou limit 900 s, `plan_diff` je definovaná; návrh `project_tests` vychází ze sledovaných testovacích souborů.
- Kontrola rozdílů mezi kódem a dokumentací vidí i kódy odmítnutí předané pomocnou funkcí; podklady testů ve složce `docs/` nejsou ignorované; kořen pluginu nikdy není kořen projektu; zastaralý podklad testu gramatiky výsledků (noční červená).

### Changed
- Návod `visual-companion` je jeden postup (134 řádků místo 504); starý režim stránek (fragmenty, `/screen`, `data-confirm`) server dál umí.

### Known limits
- Karta PM u `--pm-card` má stejnou slabinu jako ostatní karty (IMP-692): kdo umí zapsat soubor karty a událost hooku, umí ji padělat.
- `proto` neumí workspace/monorepo ani pnpm bez `node_modules` v `ui.dir`; `shots` neumí nové okno, iframe a nahrání souboru – obojí odmítne s výzvou zapsat případ.
- Vývojový server je v testech jednoduchý statický server; skutečný Vite ověřil nezávislý agent (AC9).
- Návrh klíčů `ui` při `/aid-init` je pokyn průvodce (`/aid-init` provádí agent); kód je `aid_ui_config_detect` s testem, samotné zapojení do průvodce test nemá.
- Převzetí portu cizím procesem mezi výběrem a startem vývojového serveru se odhalí (port musí patřit skupině procesů prototypu), ale deterministický test toho závodu není.

## [3.6.0] — 2026-10-18

Studio `/aid-ui` předává plánu a běhu (P115): převzetí webu zapíše jeden předávací balík, z balíku vznikne jedním příkazem zadání plánu nasazení, brána běhu pustí na doménu jen předaný web bez otevřeného kritického bodu, ostrý web má vlastní hodnocení a studio používá Codex a ceník AIDu místo vlastních kopií. Ověřeno na testovacím projektu a v testbedu (dráha `ui_package_to_gate`); skutečný web se tímto vydáním nenasazoval (PM 3A).

### Added
- **Předávací balík `docs/ui/predani.json`** (+ čitelný `predani.md`, schéma `skills/ui-design/references/handover-package.schema.json`, verze 1): web se seznamem souborů a otisky, zaznamenaná brána, schválené kapitoly, verdikty míst, úkoly zákazníka, otevřené body, podklady ke spuštění, kritéria `launch_only` a verdikt PM. Zapíše ho převzetí (`aid-ui-state.sh chapter-all`); balík, který nejde sestavit (chybí brána, web se po bráně změnil, otevřený bod bez textu), převzetí odmítne se jménem chybějící části a odpověď PM zůstane nepoužitá. `aid-ui-package.py build|check`.
- **Zadání plánu nasazení z balíku:** `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-package.py" zadani docs/ui/predani.json --plan-id P<NNN>` napíše zadání v šabloně a projde ho kontrolou; bod hotovo s vlastníkem (běh, klient, PM), příznakem „blokuje spuštění“ a příkazem k ověření za každý úkol zákazníka, krok spuštění (`references/local/spusteni.md`: nasadit přesně balík, HTTPS, bezpečnostní hlavičky, 404, citlivé soubory, DNS, e-mail, katalogy, přesměrování starých adres), podklad ke spuštění, otevřený bod a hodnocení po nasazení. `/aid-plan` bere balík jako vstup; kontrola plánu odmítne plán, který ztratí značku balíku (`ui_package_lost`).
- **Brána běhu `check_ui_handover`** (výchozí `execution.yaml`, všechny profily z `/aid-init`, upgrade ji přidá i existujícím projektům): plán bez `ui_package` přeskočí s důvodem; plán z balíku zastaví chybějící, upravený nebo zastaralý balík a otevřený kritický bod. Po zápisu `docs/ui/nasazeni.json` (adresa a popis hostingu) si brána sama vypíše soubory hostingu a pustí jen přesně soubory balíku (nic navíc ani odkaz, nic chybějícího, žádný jiný obsah), formulář, který hosting přijme (odeslaný na vlastní adresu webu), a kontrolu UI studia nad ostrou adresou (`aid-ui-verify.sh --base-url`, bez náhledu a bez zápisu).
- **Hodnocení po nasazení** ve vlastní smyčce: `aid-ui-quality.py launch <projekt> --url <ostrá adresa>` (a `--launch` u ostatních příkazů) v `.aid-ui/critic/launch/`, fáze `launch` hodnotí i kritéria, která čekala na nasazení; `launch-status --package docs/ui/predani.json` projde jen pro nasazenou adresu a web z balíku. Soubory hodnocení stavby se nemění.

### Changed
- **Jeden motor:** studio (`aid-ui-client.py`, `aid-ui-copy.py`) volá Codex přes `lib/aid-codex-transport.sh` (výběr instalace, model `CODEX_MODEL`, čtecí proces, snímky přes `AID_CODEX_IMAGES`, bez placených klíčů) a ceny tokenů i obrázků bere ze stejné tabulky jako revize (`defaults/prices.yaml` přes `aid_review_prices_file`, nově oddíl `images:`). Vlastní `TOKEN_PRICES` a ceník obrázků ve studiu zmizely; model, který tabulka nezná, má cenu `null` s varováním. Náhradní Claude teď stojí podle sdílené tabulky (Sonnet 2/10 USD za milion místo ručně zapsaných 3/15). Transport vždy předá `--skip-git-repo-check`.
- Cena obrázku z tabulky projektu může cenu pluginu jen zvýšit, nikdy snížit (strop rozpočtu na placené obrázky počítá skutečné peníze).
- Návod studia už neříká, že se do běhů nezapojuje; oddíl Předání popisuje jednu cestu studio → balík → plán → běh (`SKILL.md`, kroky 7 a 8, `/aid-ui`, `/aid-plan`, nápověda, Docusaurus).

### Kód
- Produkční kód +1446 / −89 řádků (bez testů): nový `aid-ui-package.py` (774 řádků: balík, zadání, brána, ostré body), zbytek napojení; `aid-ui-client.py` 810 → 833, `aid-ui-copy.py` 670 → 684, `lib/aid_ui_costs.py` 156 → 200 (čtení sdílené tabulky místo vlastní), `aid-ui-logo-gen.py` 392 → 390. Testy: nová sada `test-aid-ui-package.bats` (t1, 24 případů), případy `launch:` a `shared-motor:` v sadách studia, jeden případ se skutečným prohlížečem nad ostrou adresou (`test-aid-ui-verify.bats`).

### Known limits
- Formulář, který odesílá na cizí službu, brána neodesílá a jen ho jmenuje; jeho doručení ověřuje bod klienta „Příjem zpráv z formuláře“.
- Kontrolu UI nad ostrou adresou spouští brána celou (všechny řádky studia); v testech na cestě k merge je to náhrada, skutečný prohlížeč je v noční sadě.

## [3.5.0] — 2026-10-17

Studio `/aid-ui` podle dílny (P113): šest míst rozhodnutí, na každém hodnotí klient a odborník na Claude Opus s pamětí a postoupit pustí jen kód. Ověřeno na záznamech dílny (zasazené vady 13/13, brány loga 4/4) a během na Coufalovi: pohyb přijat, sdělení, logo, struktura a vzhled vrácené po vyčerpaných kolech; ověření hotového webu od nuly zůstává otevřené (`docs/reference/2026-10-p113-overeni-coufal.md`).

### Added
- **Šest míst rozhodnutí** (sdělení, logo, pohyb, struktura, vzhled, hotový web) s měřítky a branami v `critic/*.gates.yaml` (kritérium, `when`, `any_of`, vážené minimum, změřené limity pohybu, audit). Verdikt místa (`aid-ui-critic.py place-verdict`) se zapisuje do stavu (`aid-ui-state.sh place-record`); odpověď ve studiu i zápis buildu bez přijatého verdiktu místa, na kterém stojí, se odmítne. Pořadí rozhodování: fakta a zákon, pak vada řemesla od odborníka, pak volba klienta; výhrada jen tehdy, když bránu drží chybějící vstup klienta.
- **Klient a odborník na Opusu s pamětí** napříč místy: klient vidí svá dřívější hodnocení, své odpovědi ve studiu a zvlášť rozhodnutí PM; odpověď ze stránky PM se zapisuje jako `by: pm`, odpověď s tokenem agenta nikdy.
- **Kolo místa:** `aid-ui-quality.py round --place <místo>`, nejvýš tři opravná kola, kolo nevalidní odpovědi se nepočítá.
- **Postupy dílny jako vrstva s předností** (`references/local/`) a kopie standardů v pluginu (`references/standards/`); studio nečte `/opt/eco/docs`.
- **Živá kostra webu** na stálé adrese (`aid-ui-serve.sh skeleton`, port 3918), postavená ze schválené struktury a registru faktů; hotové stránky nepřepisuje.
- **`aid-ui-state.sh cycle`:** strojová část opravného cyklu jedním příkazem (záznam pohybu, build, kontrola textů, měření, brána, gate-check), stop na prvním neúspěchu (IMP-695).
- **Nástroje značky:** karty směrů pro role (`logo-sheet --cards`, skutečné kontexty, černobílá a inverzní varianta z balíku), nástroj pohybu loga (`aid-ui-logo-motion.py`: web do 1 s s názvem hned, video 2-3 s, konec bez švu, název v křivkách, kreslení jednou za návštěvu), měření pohybu po variantách (`aid-ui-tool.sh motion measure`, i pohyb řízený skriptem).
- Kontrola balíčku značky pro web chce `og-image.png`, `site.webmanifest`, `head-snippet.html` s absolutní adresou `og:image` a animaci loga (pokud PM nezapsal projekt bez pohybu).

### Changed
- **Brána hotového webu jde přes každou stránku a každou šířku** (320, 390, 768, 1024, 1440 px) bez vzorku (řádek `all_pages`); hustota obrázků podle skutečné šířky souboru, pohyb řízený skriptem, povinný viewport, jedno H1, dotykové plochy na šířkách dotykových zařízení, informace o osobních údajích u formuláře.
- **Stránku pro zákazníka dělá zápis brány** z právě zapisovaného výsledku, takže brána proběhne jedním průchodem (IMP-697).
- **Kontrolu textů zneplatní jen změna faktů, o které se stránka opírá** (IMP-696).
- Role se nejdřív ptají Opusu; Codex je záskok.

### Fixed
- Vady, které našel běh na Coufalovi: zhoršení nálezu sloučeného jako duplicita šlo zapsat jen u opravených; souhrn kola místa se směry padal; pohyb řízený skriptem se měřil jako „bez pohybu“; stránka pohybu měla vždy `lang="cs"`.
- Brána nad záznamy dílny našla napoprvé 8 z 13 zasazených vad; opraveno: počet s přívlastkem („přes 300 dokončených projektů“), obsahový obrázek s prázdným `alt`, informace o údajích jen v patičce, malé položky menu na tabletu, druhé H1 a nálezy SEO zadání připnuté ke všem stránkám.
- Stop hook `decision_card_complete` čte přepis od konce (dlouhé sezení přeteklo jeho 5 s).
- Testy studia nenechávají běžet servery (studio spuštěné v podprocesu `run`).
- Z celkové revize: svazek pro role nebere soubory přes odkaz ve složce, změřené limity pohybu se váží na otisk měřeného souboru, pohyb řízený skriptem se hlídá na každé šířce, `og:image` musí být https.

### Known limits
- Kostra se staví do `site/` a hotové stránky ponechává, takže u projektu s hotovým webem hodnotí role strukturu na starém webu (IMP-699); ověření studia od nuly zůstává otevřené (IMP-703).

## [3.4.0] — 2026-10-15

Testy před sloučením se vracejí pod 10 minut a patra odpovídají ekosystémovému standardu (PM 15. 10. 2026, 1A + 2A). Noc 15. 10. naměřila T0 252 s z 120 s a celou cestu 919 s z 600 s, ověřovací běh po změně 544 s (T0 + T1, 713 testů); kontrola pater to hlásila, ale běžela jen v branách plánů a ruční vydání od 3.0.0 ji obcházela.

### Changed
- **T0 jsou jen statické kontroly**, jak říká standard: nová sada `test-static.bats` (každý shell skript včetně hooků bez přípony, JavaScript, Python, JSON a YAML pluginu se dá načíst; chybějící soubor daného druhu nebo chybějící parser je pád) plus karty agentů. 51 sad chování, které v T0 byly jen proto, že byly levné, je v T1. Nástroj na přeřazení (`aid-test-tier-assign.sh`) už cenou T0 nenavrhuje. Tabulka pater v CONTRIBUTING.
- **22 sad jde do nočního běhu podle pravidla standardu** (přetečení patra: nejdražší sady mimo jádro), každá s řádkem v hlavičce, proč: 11 sad studia `/aid-ui` a companionu, deset menších pomocných sad a `test-epic-path-removed` (prochází dva stavové automaty). Čtyři sady, kterými prochází každý plán (sestavení `plan.json`, kontrola zadání, kritik, rozdíl kroku), jsou nově v jádru (`tier-core.txt`) a cestu k merge neopustí.
- Rozpočty kontroly pater jako součty sad: T0 30 s, T1 450 s, odvozeno z naměřené režie runneru v noci (1,5 s na sadu).
- Noční zpráva o rozpočtu jmenuje 5 nejdražších sad cesty k merge (poslední platné měření každé) a říká obě cesty ven; nečitelný deník měření řekne, místo aby ho zamlčela.

### Added
- `aid-release.sh` spustí před vydáním kontrolu pater projektu (brána `tier_lint` z jeho `execution.yaml`, pokud ji má) a při porušení nic nezmění; `--force` ji neobchází.
- Sada může v hlavičce jmenovat svůj předmět (`# aid-subject: <cesta v pluginu>`), když jméno sady neodpovídá souboru; přiřazení předmětu zná i skripty `.py` a `.mjs`. Dřív by 28 sad s jedním předmětem odešlo z cesty k merge jako „mezikomponentní“ jen kvůli jménu.

### Fixed
- Skrývání tajných údajů (`_aid_artifact_redact`) nejdřív zkusí všechny detektory jedním `grep` a celý průchod udělá jen při nálezu; `aid-ui-sources.py` drží pro celý běh jeden proces redakce. 55 ms na text → ~3 ms; sada zdrojů 90 → 20 s a stejně se zrychlilo každé vykreslení stránky a čtení zdrojů pro uživatele.
- Otisk pluginu v kontrole zastaralé kopie (`aid-cache-preflight.sh`) vynechává `scripts/tests`: žádný test z kopie neběží, byl to 626 z 802 souborů a úprava testu v repu AID zastavila každý běh jako „zastaralá kopie“.

## [3.3.0] — 2026-10-14

Noční běh hlásí, když testy před sloučením přetáhnou rozpočet (PM 14. 10. 2026, 2A). Do té doby se překročení jen zapisovalo do nočního výsledku: T0 bylo přes rozpočet 44 nocí po sobě a nikdo to nevěděl.

### Added
- Třetí zpráva AID `rozpocet-testu` (`aid_alert_test_budget` v `lib/aid-alert.sh`, rozsah `<projekt>-testy`, oblast AID, `warning` → K rozhodnutí): noc, kdy T0, T1 nebo celá cesta ke sloučení přetáhne rozpočet, pošle jednu zprávu s lidskou větou a v `akce` naměřené časy, kolikátá noc po sobě to je a co rozhodnout do týdne. Noc, kdy se vrátí pod rozpočet, pošle `ok` (`send_ok`), které případ uzavře. Stav epizody nese noční výsledek v poli `budget_episode`: noc bez změřených obou pater ho přenese a nic nepošle, druhý běh téže noci nic nepočítá ani neposílá, nečitelný předchozí výsledek se řekne ve zprávě o překročení a v noci pod rozpočtem pošle `ok`. `--t0-seconds`/`--t1-seconds` bez hodnoty skončí chybou (dřív se parser zacyklil). Na `critical` se vědomě nestupňuje (to je Poplach, pomalé testy nikdy); řádek `*:rozpocet-testu` v `infra-druhy.json` (repo `agents`).

### Changed
- `_aid_alert_send` předává oblast (`oblast`, 10. pole standardu). Hlídač druhů zpráv v `test-aid-alert.bats` kontroluje seznam ID zpráv, které knihovna posílá, a že `send_alert`/`send_ok` nevolá žádný jiný skript (dřív počítal jen jeden způsob odeslání a třetí druh by minul). Soupis `/aid/alerty`.

## [3.2.2] — 2026-10-14

Ceny bez koncových nul, aby AID počítal stejně s `jq` 1.6 i 1.7 (PM 14. 10. 2026).

### Fixed
- `aid_review_usd` a součty ceny kritika vracely číslo ve tvaru `%.4f` (`2.0000`). `jq` 1.7 zachovává zápis čísla, které dostane, takže v souhrnech a záznamech zůstalo `2.0000` místo `2` (s `jq` 1.6 se zápis sjednotil sám). Teď se koncové nuly odstraní u zdroje (`lib/aid-review-summary.sh`); hodnoty jsou stejné.

### Changed
- Na eco-dev běží testy a runnery s `jq` 1.7.1 (`~/.local/bin`): `jq` 1.6 z Debianu 12 stojí 34 ms na spuštění, 1.7.1 4,7 ms. T1 1 016 → 656 s, cesta ke sloučení 21,3 → 15,0 min. Postup a vrácení: runbook ekosystému, měsíční údržba; `/aid/testing`.

## [3.2.1] — 2026-10-14

Rychlejší noční běh testů, druhé kolo úklidu (PM 14. 10. 2026). Postaveno nad 3.2.0. Nic se nemění pro uživatele pluginu.

### Changed
- Noční úloha má vlastní časový strop 600 minut. Její výchozí strop 360 minut (žádný limit platformy) ji 12. a 13. 10. ukončil po 6 h 1 min a hlášení nevzniklo.
- Mechanismus „postav přípravek jednou, pro každý případ obnov kopii“ je sdílený (`scripts/tests/bats/snapshot.bash`, dřív jen uvnitř sady uzavření plánu). Selhání stavitele přípravku teď sadu zastaví, místo aby se uložil poloviční stav.
- `test-plan-final-decide`: projekt a konec plánu bez mezikroku se staví jednou na vstup a obnovují se (26,7 → 20,2 min na vytíženém stroji).
- `test-plan-run`: případy, které začínají úspěšným spuštěním plánu, obnoví jeho uloženou kopii včetně výstupu, místo aby ho opakovaly (23,9 → 17,4 min). Sada odmítne paralelní bats.
- `test-aid-ui-verify`: případ, který se ptá na jednu kontrolu brány, pustí jen tu kontrolu (`narrow`). Celou bránu (38 kontrol × 3 šířky × 2 prohlížeče) pouštějí jen dva případy, které se ptají na bránu jako celek. Nejdražší případ (kontrola textů) 8,3 → 2,7 min. Po 3.2.0 i případ pohybu (11,9 → 5,6 min) a loga (1,8 → 0,5 min).

### Fixed
- `scripts/aid-ui-coverage.sh` a `scripts/aid-ui-verify.sh` byly v gitu bez práva ke spuštění (od 2.118.0), takže přímé spuštění podle návodu skončilo chybou 126.
- Co noční běh 14. 10. hlásil červeně (poprvé s 3.0.0): `test-hooks-worktree` neměl vzorový běh v seznamu aktivních běhů, kde ho hlídač commitů od 2.118.1 hledá (hlídač sám funguje); `test-run-all-tests-result-grammar` jmenoval sadu smazanou v 3.1.1; `test-worktree-topology` testoval zakládání větví EPICů, které 3.0.0 odstranila (6 z 8 případů pryč, zbývá cizí pracovní kopie a běh bez plánu).

## [3.2.0] — 2026-10-14

Smyčka kvality /aid-ui (P113a): web po předání hodnotí dva nezávislí kritici, majitel a technik, s pamětí a cestou k 10; hodnotí se práce studia, ne to, co klient nedodal; nejvýš 3 kola oprav nebo oba 8,5, pak audit. Cena a čas každého kola včetně práce agenta. Postupy, které na pilotu Coufal chyběly, a „méně kol, víc rozdílů“ ve studiu.

### Added
- **Smyčka kvality po předání (`aid-ui-quality.py`)** (P113a kroky 1–3, 12. 10. 2026):
  - Zmrazený nezávislý kritik (`aid-ui-critic.py`) hodnotí živý web podle měřítka typu s kotvami 4/6/8/10 a odpovídá JSON podle schématu (`critic-retro.schema.json`). Práh zná jen kód.
  - Každá výtka se roztřídí (`accepted`, `rejected_with_reason`, `duplicate`, `blocked`, `superseded`). Oprava se zapíše s důkazem.
  - Před každým kolem projde `aid-ui-state.sh gate-check` (stejná kontrola jako `finish`).
  - Na konci audit slepými hodnoceními a `verdict.json` s tím, co blokuje zveřejnění. Smyčku lze znovu otevřít (`reopen`).
  - Studio ukazuje kola v panelu Hotovo.
- **Klient-agent a kritik v pluginu (`aid-ui-client.py`):**
  - Codex na předplatném. Při limitu, prázdné nebo neplatné odpovědi nastoupí nezávislý Claude se stejným zadáním a snímky. Klíče API se z prostředí textových procesů odstraní.
  - Kritik hodnotí jen adresu, která obsluhuje právě tento web, a jen se snímky každé stránky na 1440 i 390 px (nástroj snímků teď opravdu fotí mobil).
  - Kniha nákladů projektu `.aid-ui/costs.jsonl`. Placené API jen pro obrázky, se stropem 2 USD na projekt (`AID_UI_IMAGE_BUDGET_USD`), rezervace pod zámkem.
- **Nové řádky brány a standardy FB-29 až FB-33** (`frontend-build-standard.md`):
  - `task_test`: úkoly zákazníka v prohlížeči (cena, otevírací doba, objednání do dvou kroků),
  - `photo_slots`: místo pro fotku v přesném poměru, s ikonou a bez textu,
  - `form_delivery`: skutečné odeslání formuláře přes příjemce náhledu,
  - `text_clearance`: text nesmí být nalepený na dělicí čáru,
  - `a11y_basics`: odkaz na obsah, pořadí nadpisů, obrys zaměření 3:1, přetečení při 320 px, stejný text odkazu na různé cíle,
  - `mobile_native`.
- **Náhled s příjemcem formuláře (`aid-ui-preview.py`):** podle `.aid-ui/form.json` přijímá zprávy do `.aid-ui/inbox`. Má past na spam, kontrolu povinných polí a délky, opakování doručí jednou, omezení velikosti, počtu zpráv a schránky a v logu nejsou hodnoty.
- **Podklady ke spuštění hned po zadání (`aid-ui-launch.py`, otázka `launch_inputs`):**
  - karta podle typu (IČO, hodiny, ceník, fotky, právník, příjem formuláře, doména),
  - veřejné údaje se zdrojem a datem,
  - po potvrzení klienta do registru faktů, chybějící jako otevřené body s termínem (kritické blokují zveřejnění).
- **Fotky klienta ze starého webu (`aid-ui-photos.py`, otázka `photos`):** krok podkladů stahuje i obrázky starého webu. Agent je prohlédne, popíše a vyznačí lidi, klient vybere. Použitá fotka jde jako WebP 1600/800 px s popisem do místa pro fotku.
- **Logo:** `aid-ui-vectorize.py` měří souměrnost značky. List log odmítne značku pod 0,92 bez uvedeného záměru asymetrie.
- **Převzaté dovednosti emilkowalski/skills (MIT, 5 dovedností, `references/adopted/emil-skills/`):** kroky je vyžadují stvrzenkou postupu. Test hlídá, že žádná převzatá dovednost není mrtvá.
- **Studio:** zodpovězené otázky se jako historie znovu nekontrolují. `aid-ui-serve.sh` znovu použije běžící studio jen se stejným serverem pluginu.
- **Postupy, které na Coufalovi chyběly (5 ze 6 oprav kola 1 bylo „z hlavy“):**
  - **Krok 3, web lokální služby:**
    - stránka nebo sekce služby (Pro koho / Co zahrnuje / Jak postupujeme / Ceny z ceníku a odkazy; jen z faktů, chybějící průběh = otevřený bod klienta),
    - závěrečná výzva říká, co se stane po odeslání, a nabízí telefon,
    - nejsilnější ověřený důkaz stojí u hlavní výzvy úvodu.
  - **Krok 6:**
    - `Service` pro služby a `BreadcrumbList` na vnořených stránkách (`aid-ui-seo-check.py` hlásí chybějící drobečky jako WARN `breadcrumbs`; najde je i vnořené pod stránkou a chce aspoň dvě položky),
    - hlavní obraz první obrazovky bez výchozí neprůhlednosti a zpoždění; pohyb vzoru patří na doprovodný prvek. Brána to vynucuje: `first_paint_visible` selže, když největší obrázek první obrazovky začíná zprůhledněný nebo čeká na zpožděné prolnutí.
- **Méně kol, víc rozdílů (bod 8 zadání P113a):**
  - **Rozdíl:** otázka s `previous` (dřívější otázka stejného druhu na tentýž soubor nebo stránku) ukáže ve studiu
    i klientovi-agentovi jen to, co se změnilo: řádky souboru, nebo text stránky u schválení stránky. Celé znění je
    jen bez snímku předchozí verze, s vysvětlující větou. Snímky ukládá studio při prvním zobrazení otázky do
    `.aid-ui/studio/snapshots/`, jen ze souboru uvnitř projektu a jen když sedí jeho sha.
  - **Milník:** několik stránek nebo výjimek je jedna otázka s `items` (cíl `items@<sha položek>`).
    - `approve` schválí všechny, `return` vrátí jen jmenované položky s komentářem, ostatní se schválí.
    - Položka se spotřebuje `--answer <id> --answer-item <položka>` jen jednou.
    - Rozhodnutí položek se ověřují proti studiu, ne jen jejich otisk.
    - Studio odmítne víc než jednu otevřenou samostatnou otázku na schválení stránky.
    - Opakovaný milník ukáže rozdíl každé stránky zvlášť a u společného stylu odkaz na náhled.
  - Na Coufalu se schvalovaly stránky 21× a výjimky 9×. Slučování faktů, plánu obsahu a SEO je IMP-698.
- **Id výtek se nezdvojují:** předponu kola a role, kterou si kritik opsal z paměti, smyčka odřízne. Kdyby se dvě id jedné odpovědi tím shodla, zůstanou, jak byla.

### Changed
- **Dva kritici místo jednoho: majitel a technik** (PM 13. 10. 2026 po Coufalu, kde jeden technický kritik dal 7 kol 7,2-8,4 a web se viditelně skoro neměnil).
  - **Majitel** hodnotí dojem, výjimečnost proti konkurenci, fotky, prodejní texty, důvěru a cestu k objednání tak, jak ji vidí zákazník.
  - **Technik** hodnotí vyhledávače a hloubku obsahu, strukturovaná data, rychlost, přístupnost, mobil, doručení formuláře a připravenost ke spuštění. Dostává výsledky brány pro dané sestavení (`podklady/overenie.json`).
  - **Autorství měřítek:** `critic/web-local.owner.yaml` napsal Codex, `critic/web-local.tech.yaml` nezávislý Claude. Každý psal jen ze zadání role (`critic/role-briefs/`) a každé měřítko zrevidoval ten druhý. `critic/AUTHORS.yaml` drží autora, revizora a otisk. `freeze` odmítne měřítko, které otisku neodpovídá.
  - **Zmrazení:** jedno zmrazení drží obě role. Starší zmrazení s jedním kritikem se odmítne.
- **Práce studia, ne to, co klient nedodal:** drží-li kritérium dole jen otevřený bod klienta (`oi-…` v `podklady/overenie.json`, majitel je nově vidí taky), kritik dá vedle `score` (web teď) i `studio_score` s `limited_by`. Smyčka a audit počítají práci studia, `quality_now` a studio ukazují web, jak je. `limited_by` mimo otevřené body klienta je neplatná odpověď. `studio_score` pod `score` taky.
- **Fáze stavby:** před nasazením se kritéria `launch_only` (technik: bezpečnost a spuštění) nehodnotí vůbec. Kritik je nedostane a do známky se nepočítají. `freeze --phase launch` je vrátí.
- **Cesta k 10:** každé kritérium pod 10 nese `to_ten` (kroky studia a klienta: co, kde, jak to bude vypadat). Bez kroku je odpověď neplatná. `fix` u nálezu má být tak konkrétní, aby šel udělat bez dotazu.
- **Po každém kole hlášení PM:** návrhy kritiků, co a jak se udělalo, podle jakého postupu (nebo z hlavy a proč), známky, cena a čas (`steps/8-quality.md` bod 5).
  - `fixed` vyžaduje `--method`: krok, dovednost, nebo `z hlavy: <proč postup nebyl>`.
  - `round` vypíše pro hlášení opravy předchozího kola s postupem (`fixed_before`) a cestu k 10 od obou rolí.
- **Kritický otevřený bod klienta blokuje zveřejnění vždy:** verdikt auditu ho přidá do `publish_blocked_by`, i když ho kritici nevyjmenují.
- **Kritici si pamatují:** každá role dostane své nálezy z minulých kol a co se s nimi stalo. Vyřešený nebo zamítnutý nález smí zopakovat jen jako `regression_of` s důkazem, jiné id je neplatná odpověď. Audit paměť nedostává.
- **Majitel srovnává s konkurencí:** nový příkaz `aid-ui-client.py competitors` jednou za smyčku nafotí domovské stránky 3-5 konkurentů z `.aid-ui/critic/competitors.json`. Bez snímků 1440 a 390 aktuálního seznamu majitel nehodnotí.
- **Smyčka: nejvýš 3 kola oprav, nebo obě role ≥ 8,5** a žádné kritérium pod 7. Pak opravy končí a přijde audit: 3 slepá hodnocení od každé role. Za role platí medián ≥ 8,5, žádné hodnocení pod 8 a žádné kritérium pod 7.
  - **Zrušeno** pravidlo „+0,3 zlepšení“ a stagnace dvou kol. Šum kritika na stejném webu byl 0,6.
  - Web, jehož audit neprošel, už znovu cílem auditu není.
- **Cena a čas každého kola** v `loop.json` a ve studiu (panel Hotovo):
  - kritici,
  - kontrola textů (nově v knize nákladů: `copy:review`),
  - práce agenta, tedy tokeny z přepisu sezení Claude Code `CLAUDE_CODE_SESSION_ID` včetně podagentů, zapsané před každým kolem a auditem,
  - obrázky.

  Všechno v ceníkovém ekvivalentu, práce před první kolem zvlášť.
## [3.1.1] — 2026-10-13

Úklid nočního patra testů, první kolo (PM 13. 10. 2026, 1B). Nic se nemění pro uživatele pluginu; mění se, co hlídá noční běh, a tři nepravdy, které ty testy našly.

### Removed
- Osm celých sad, které hlídaly jen to, že nějaký plán proběhl, nebo text místo chování: `test-backlog-verdicts`, `test-deferred-work-registration`, `test-release-policy-surface-check` (i se skriptem `release-policy-surface-check.sh`), `test-aid-lock-target-audit`, `test-control-boundary.sh`, `test-review-successors.sh`, `test-integration-handoff-rendering.sh` (vzorové výstupy porovnávané znak po znaku, týdny červené bez povšimnutí, a integrační kontroly karet, které kryjí sady jednotlivých rendererů) a `test-registry-epic-inventory` (účetnictví P114). S nimi jejich vzorové soubory.
- 46 jednotlivých případů téhož druhu: hledání vět v návodech, čtení zdrojového textu místo spuštění, zmrazená porovnání s výstupem z doby před P076 (dvě vzájemné kopie), účetnictví plánů P073 a P076. Z kontroly souladu instrukcí oddíly, které jen hledaly vyřazené názvy (v1 stavy, staré příkazy, P094/P096/P097).
- Řádek registru `handoff_renderer_contract` je vyřazený (`removed_scoped`, náhrada `artifact_template_caps` + `artifact_secret_redaction`).

### Fixed
- Zásady automatické obnovy uváděly pro revizi kroku dvě kola; skutečné nastavení má od 2.116.0 jedno (`cp2_fix_loop`, dřív `cp2_cp3_fix_loop`).
- Řádek registru `plan_lint_epic_grammar` po 3.0.0 tvrdil, že kontrola blokuje, citoval neexistující text a jako nápravu radil psát značky EPICů — teď upozornění, správné citace a náprava „značku smazat“.
- `skills/pipeline.md` neuváděl přechod DONE → ERROR (ukončení běhu zaseklého v DONE, od 2.117.0).
- Sady kontroly plánu (`test-standards-map`, `test-plan-reuse-check`, `test-plan-writing-rules`) byly od 2.115.0 červené na zastaralých vzorových plánech bez zadání; vzorový plán teď dostane nejmenší platné zadání (`bind_plan_to_brief` v `test-helpers.bash`).

Velikost: 247 → 239 sad, 3 687 → 3 614 případů bats, testy a vzorové soubory o ≈ 3,6 tisíce řádků méně (≈ 3,5 %). Každá sada, kterou poslední noční běh (11. 10.) hlásil červeně — 12, některé 17 nocí po sobě — je zelená.

## [3.1.0] — 2026-10-13

Testy s hodnotou (PM 13. 10. 2026, 2A): plánový test se po plánu maže, trvalý test se jmenuje podle chování, které hlídá. Do té doby každý plán testy jen přidával — testy pluginu měly víc řádků než plugin a 654 z 3 678 případů neslo v názvu číslo plánu, nálezu nebo položky backlogu.

### Added
- **Kontrola názvů nových testů** (`aid_test_names_plan_refs`, `lib/aid-test-tier.sh`): případ přidaný od základu plánu nebo od posledního tagu, jehož název nese číslo plánu (`P111`), nálezu revize (`CP2 F3`) nebo položky backlogu (`IMP-612`), zastaví `plan-finalize --stage gates` i `aid-release.sh` (`test_named_after_plan`). Čte bats `@test`, pytest `def test_` a JS/TS `it|test|describe`; necommitnuté změny sledovaných souborů se počítají, protože by je vydání přibralo; diff, který nejde přečíst, odmítne stejně jako nález. Číslo kroku se nehlídá (`step 0` je v AIDu doménový pojem). Staré případy si název nechávají, dokud se nezmění jejich řádek s názvem. `aid-release.sh` kontroluje jako první krok (i v režimu `auto`, který jinak může skončit dřív), tedy před `--dry-run` a před změnou souborů; `--force` ji neobchází.

### Changed
- `skills/plan-writing.md`: Testing Strategy má čtvrtou otázku „Které testy plán maže?“; jednorázová kontrola žije ve vlastním souboru (značka verification-only platí pro celý soubor); výčet druhů, které jsou vždy jednorázové (důkaz, že krok proběhl, zmrazený seznam starých jmen, hlídač jakékoli změny, hledání věty v návodu, pokud ji kód necituje doslova).
- Revize kroku (`skills/step-review-roles.md` otázka 3, `skills/review-checkpoint-contracts.md`) se ptá i obráceně: který existující test změna zneplatnila — jmenuje se a maže v tomtéž kroku.
- `CONTRIBUTING.md`: solo stavba značí jednorázové testy stejně jako plán a vydání odmítne případ pojmenovaný po plánu. Docusaurus: ekosystémový testovací standard (pravidlo 2 platí i pro název případu, „Plánový test není trvalý“) a `/aid/testing` (oddíl Plánové a trvalé testy).

## [3.0.0] — 2026-10-13

Bez EPIC cesty (P114, vydání 3 roadmapy P109; PM 12. 10. 2026, 13. 10. 2026 1A). Plán běží jako jeden běh přímo ze souboru (`/aid-run P<NNN>` = `aid-plan-fsm.sh plan-run`, od 2.117.0); generátory EPICů, fronta, task větve, slučování EPICu do větve plánu a revize EPICu (CP3) jsou z pluginu pryč. Major verze: staré vstupy odmítnou s cestou ven, nic se tiše nechová jinak.

### Removed
- **Generování EPICů** — `aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`, `aid-auto-pipeline.sh` (i `supersede-generation`), `aid-generation-finalize.sh`, `aid-epic-summary.sh`, šablony `epic.md` a `run-*.md`; režim `/aid-plan epic`. Jedinou kontrolu, kterou držel jen generátor — stránku pro PM — přebírá `plan-run` (`plan_page_missing`, při každém spuštění i pokračování).
- **Fronta a pokračování** — `lib/aid-queue-write.sh`, `aid-plan-continue.sh`, `next-epic`, `queue-revalidate`, kontrola fronty v `aid-plan-close-check.sh` (Check 4), řádek fronty v `active.md`, fronta v `/aid-status` (souhrn, kandidát, `/aid-status queue …`), připomínka fronty při startu session. Nastavení `autonomy.spawn_next_epic`, `max_spawned_epics`, `spawn_deadline_sec` v `project.yaml` už nic nečte (lze smazat; `/aid-init` je nezapisuje).
- **Task větve a slučování EPICu** — `epic-start`, `epic-merge-to-plan`, `epic-base`; `init` bez `--direct` pro EPIC deklarovaného plánu, `done-advance` takového běhu; `epic-complete` bez `--direct` (a jeho `--supersede-by`, `--full-tests`). Zůstává `epic-complete --direct` (zápis přímého běhu, volá ho `done-advance --direct`) a `--abandon` (ukončení běhu). Běh bez plánu (EPIC id bez čísla plánu) zůstává jako zkušební běh testů FSM.
- **Revize EPICu (CP3)** — `--checkpoint cp3` (odmítne a jmenuje CP2 a CP7), role `epic_generalist`, `epic_behaviour`, `epic_security`, kontrola čerstvosti D4 (`CP3-Freshness-Exception`), rekonciliace sémantického souboru EPICu s rozsahem kroků. Každý krok má revizi (CP2), celý plán se čte jednou při uzávěru (CP7). Streamlined běh mimo `plan_branch` odmítne (`streamlined_cp3_off`): nic jiného by jeho kód nečetlo.

**Odmítnutí a cesta ven** (`epic_path_removed`, řádek v `skills/pipeline.md` §When AID refuses): `epic-start`, `epic-merge-to-plan`, `next-epic`, `epic-base`, `queue-revalidate`, `init` bez `--direct`, `done-advance` a `epic-complete` starého běhu, `plan-run` nad plánem generovaným po staru (soubor EPICu, nepřímý záznam v manifestu, transakce generace, vlastní záznamy ve frontě). Rozpracovaný starý běh se dokončí na 2.118.x (`plugin_path` připnutý na checkout 2.118.x), nebo se jeho plán uzavře (`aid-plan-fsm.sh plan-close P<NNN> --administrative --reason "<proč>"`, starý běh ukončí `epic-complete … --abandon`) a začne NOVÝ plán s novým číslem. Zbylý `.aid-o/config/queue.yaml` čte jen tohle odmítnutí `plan-run` — smažte ho, až žádný starý plán nepoběží. Projektový `review-checkpoints.yaml` s `cp3_integration_review` nebo blokem `epic_review` se načte s varováním „ignored legacy key“, ne s chybou.

### Changed
- `plan-run` odmítne `--reason` bez `--force`/`--restart`; stránku pro PM kontroluje při každém spuštění.
- Pravidlo Stop pro autonomní běh žije v `lib/aid-auto-continuation.sh` (`aid_hook_rule_auto_continuation_stop`), řádek registru `auto_continuation_notice`; pravidlo hooku si nechalo id `queue_continuation_notice`, takže `AID_HOOKS_OFF_RULES` i auditní řádky platí dál.
- Registr vynucení: řádky EPIC cesty vyřazené podle inventury P111 (`docs/reference/2026-10-p111-inventura-epic-cesty.md`, sloupec „P114“), nový `epic_path_removed`; 662 řádků, aktivních 466 (před 520).
- Texty pro agenty a dokumentace znají jednu cestu: `/aid-run`, `/aid-plan`, `/aid-status`, `/aid-help`, `/aid-stop`, skilly `pipeline`, `planner` (přepsaný na `plan-run`), `plan-writing` (značky `**EPIC N: Steps …**` se ignorují, lint je jmenuje jedním řádkem ADVISORY), `run-management`, `agent-protocol`, `role-cards`, `review-checkpoint-contracts`, `step-review-roles`; Docusaurus `/aid/commands/aid-run|aid-plan|aid-status`, `/aid/architecture/overview`, stránky `aid-epic-queue`, `aid-epic-status`, `aid-plan-epic`, `aid-run-epic` smazané.

### Fixed
- `done-advance` běhu bez plánu odmítal jako starou EPIC cestu (prázdné pole odpovědi resolveru se při čtení tabulátorem slilo) — chyba vzniklá a opravená během P114, s regresním případem.
- `plan-run` od 2.117.0 nekontroloval stránku pro PM (kontrolu držel jen generátor EPICů) — teď ji vyžaduje při každém spuštění i pokračování.
- Kapitola „Escalations settled by an independent agent“ (2.118.1) ležela uvnitř bloku, který `commands/aid-run.md` cituje bajt po bajtu z `scripts/lib/aid-review-adapter-claude.md`, takže `test-review-finding-schema` (t2) byl na 2.118.1 červený; kapitola stojí za blokem.
- Stav revize běhu pro lifecycle bere poslední běh (starý `audit-report.json` už nepřebije novější kola kroků).

Velikost (jen hlášení; `wc -l` jako v 2.118.1, testy navíc):

| Část | Před (2.118.1) | Po (3.0.0) |
|---|---|---|
| scripts (`scripts/*.sh`, `scripts/lib/*.sh`) | 76 377 | 66 080 |
| skills (`skills/*.md`, `skills/*/SKILL.md`) | 8 582 | 7 915 |
| commands | 6 114 | 5 563 |
| testy (`scripts/tests`, soubory / případy bats) | 283 / 4 047 | 258 / 3 685 |

Testbed: lane `generation_refuses_without_page` je teď `plan_run_refuses_without_page` na `plan-run` (repo testbedu nemá remote: commit 68ee406; testbed 42/42 na kandidátu). Testbed teď vykresluje stránku pro PM i v klonech přímého běhu (`plan-run` ji vyžaduje).

## [2.118.1] — 2026-10-13

Cizí repo do konce a eskalace na nezávislého agenta (P112, opravné vydání po prvním skutečném plánu na přímé cestě Agents P016; PM 12. 10. 2026 1A + 2A, 13. 10. 2026 delegace v `--auto`). Plán s druhým repem (`repo_roots`) dojde do rozhodnutí o vydání bez ručního sloučení a bez zastavení na PM kvůli vadě nástroje.

### Added
- **Jedno mapování cizích rep** — `lib/aid-repo-roots.sh` (`aid_rr_entries`, `aid_rr_path`, `aid_rr_text`, `aid_rr_resolve`, `aid_rr_rewrite_files`): kterému worktree patří cesta v deklarovaném repu, z plánu i z `plan.json`; čte ho kontrakt kroku, kontrola kroku, oba balíčky revize, měřič bodů i lint. Funkce mapování v kontraktu zmizely (přesunuté beze změny chování). Cesta v `repo_roots`, která není vrchol repa, je `repo_root_invalid`.
- **`plan-run --restart --reason`** — běh, který neudělal žádný krok, se odloží (abandon, auditní záznam jako `supersede-generation`, přesun do `.aid-o/work/superseded-runs/<plán>-<čas>/`) a plán se spustí znovu nad aktuálním plánem; po kroku `restart_after_step`, se špinavým worktree plánu `restart_plan_dirty`, cizího repa `restart_foreign_dirty`, s živým řadičem `restart_controller_live`; přerušený restart pokračuje týmž příkazem. Archivační a auditní pomocníci pipeline jsou knihovna `lib/aid-generation-authority.sh`.
- **Eskalace rozhoduje nezávislý agent** — v plánu `autonomy: auto` automaticky, v ručním po `aid-review-round.sh standing --plan <plán> --delegate --reason "<slova PM>"`: rozpor k nálezu (CP2/CP3/CP7) a každý blokující nebo závažný nález otevřený po posledním kole jde přes `aid-review-round.sh delegate` (`--pending`, `--fingerprint`, `--verdict`) — Codex přes runner kola, při jeho výpadku nezávislý Claude agent v závorce `adjudicator-delegated-<fp16>` (agent `claude:adjudicator-delegated`); kolo se neuzavře, dokud čeká verdikt. Verdikt třídy `brief|money|data` jde na kartu PM (`delegation_out_of_scope`), `--defer-criterion` delegáta nepřijme; verdikt bez původu je `delegation_missing`. Kniha `evidence/<plán>/delegated-disputes.jsonl`, karta i stránka uzávěru je vyjmenují. Šablona `defaults/templates/adjudicator-delegated.md`.
- Odmítnutí s `next:` a řádkem v `skills/pipeline.md`: `restart_after_step`, `restart_plan_dirty`, `restart_foreign_dirty`, `restart_controller_live`, `active_runs_write_failed`, `active_runs_unreadable`, `delegation_missing`, `delegation_out_of_scope`; registr vynucení +4 řádky (`foreign_review_reads_worktree`, `measure_timeout_unmeasured`, `plan_run_restart_no_step`, `delegated_escalation`), 661.

### Changed
- **Revize čte worktree** — balíček revize kroku nese `foreign-<name>.patch` z rozsahů, které ověřila kontrola kroku (`step-check.json` `other_repos`), `files.json` s cestami ve worktree a `packet.json`; balíček celého plánu nese každou cizí větev od zmrazeného základu; prompt jmenuje worktree a zakazuje živou kopii. Chybějící worktree = `foreign_worktree_missing`.
- **Měření bodů čte worktree** — `aid-plan-diff.sh` přepíše `file:` a cesty v `cmd` bodu do worktree plánu po kroku i při uzávěru (`--isolated`), takže brána `plan_diff` projde bez sloučení cizí větve.
- **Hook hlídá jen živý běh** — pre-commit bere běh větve jen z `active-runs.json` (odložená kopie stavu nikdy nehlídá; glob zůstal pro `run_abandoned`); nečitelná mapa na `plan/*` a `task/*` commit odmítne (`active_runs_unreadable`), jinde projde s řádkem. `init` bez záznamu v mapě selže (`active_runs_write_failed`), úklid mapy drží přímý běh do `DONE`/`release`. Projekty dostanou hook přes `/aid-init` (upgrade).
- **Lint odmítne nedeklarované cizí repo** — absolutní cesta v `Files` nebo v `file:`/`cmd` bodu do jiného git repa než projekt, které `repo_roots` nedeklaruje, je `foreign_repo_undeclared` už před CP1 (repa se porovnávají `--git-common-dir`, body čte parser měřiče).

### Fixed
- **Timeout je neměřený bod** — bod, který nedoběhne v limitu, nese `unmeasured: true`, `reason: timeout`, `timeout_s`; `increment-step` i uzávěr ho jmenují jako neměřený s limitem a radou (`AID_PLAN_DIFF_AC_TIMEOUT_FLOOR=<s>` pro přeměření, zvedne i vlastní `timeout:` bodu; příští plán dá bodu `timeout:`), ne jako chybějící změnu. Neměřené důvody jsou jedna konstanta (`lib/aid-unmeasured.sh`).
- Registr vynucení: dva řádky /aid-ui (2.118.0) citovaly neexistující soubory (`sections.json`, `gen.json`) — `test-enforcement-registry-cites` byl červený už na 2.118.0.

Velikost (jen hlášení):

| Část | Před | Po |
|---|---|---|
| scripts | 75 432 | 76 377 |
| skills | 8 563 | 8 582 |
| commands | 6 029 | 6 114 |

Testbed: lane `repo_roots` měří dva body v cizím repu (soubor i příkaz) a dojde přes `plan-finalize` k rozhodnutí o vydání s živou kopií cizího repa beze změny (repo testbedu nemá remote: commit c596889; testbed 42/42 na kandidátu).

## [2.118.0] — 2026-10-12

/aid-ui do vydání: P103 (produkční web, studio jako průběh stavby, brána nad buildem, stránka pro zákazníka, pohyb vzoru) a P108 (texty podle převzatých postupů, kontrola textů, design standard, předání). Nahoře opravy z testu s nezávislým klientem-agentem na Coufal Clinic (11.–12. 10. 2026, retro 3/10): obsah viditelný bez skriptu (FB-27), formulář (FB-28), schválení podle rozsahu změny, zadrátovaný záskok Claude za Codex, blokace publikace kritickými body.

### Added
- **FB-27: obsah je vidět bez skriptu, bez posunu a při omezeném pohybu** (retro klienta-agenta Coufal 11. 10. 2026: hotové stránky byly bez JS a před posunem prázdné, 957 kontrol to nechytilo). Brána má dva nové blokující řádky: `content_without_js` (stránka s vypnutým skriptem ukazuje každý obsahový text, který ukazuje stránka se skriptem po doběhnutí pohybu a posunu) a `first_paint_visible` (hned po načtení bez posunu je čitelný h1 a první blok, nic čitelného není zesláblé, totéž pod `prefers-reduced-motion`). Krok 6: skryté stavy pohybu jen pod `html.js`, odhalení hned po načtení. Standard FB-27, mapa pokrytí, fixture s nastraženou skrytou sekcí.
- **FB-28: formulář odesílá, nebo poctivě říká, co dělat** (retro klienta: formulář `mailto:` a bez odeslání). Nový řádek brány `form_states`: žádné `mailto:`, tlačítko zamčené během odesílání, chyba s klikacím telefonem/e-mailem v `role="status"`, úspěch s vlastní zprávou (koncový bod podvrhne brána 404 a 200). Chybějící koncový bod na hostingu = kritický otevřený bod.
- **Kritické otevřené body blokují publikaci** (H7): `open-item add --critical [--evidence]`, `open-item critical <id>`; blokaci nejde zrušit, bod končí jen jako `done --evidence` (bezpečnostní kontrola 12. 10.); `finish` běh uzavře, ale zapíše `publish_blocked_by` a vypíše PUBLISH BLOCKED; stránka pro zákazníka má nahoře „Publikace blokovaná“ a kritické body první.
- **Věty vrácené klientem se nesmí vrátit** (H6): `copy-record` vezme věty v uvozovkách z komentářů vrácených `copy_verdict` a stránku, kde se objeví kdekoli v subjektu (text, title, description, og, alt), shodí bez modelu.
- **Pohyb celého vzoru, ne jen úvodní stránky** (PM 11. 10. 2026, 2B): `aid-ui-tool.sh motion … --pages N` projde i prvních N podstránek vzoru (menu, patička; načtení, posun, najetí), každá položka záznamu nese `pages`, záznam `pages` a `coverage.pages`; soupis `aid-ui-motion.py` smí u položky `replace` uvést `from` = druhý vzor, který PM viděl - kontrola pohyb ověří v jeho záznamu (`.aid-ui/refs/<from>.motion.json`) i ve stavbě, souhrn ho ukáže jako „nahrazeno z <vzor>“. Testy v `test-aid-ui-motion*.bats`.
- **Ikony v záložce prohlížeče** (PM 11. 10. 2026, 1A): studio a companion nesou ikonu AID (`lib/aid-ui-studio/aid-icon.svg`, cesta `/favicon.svg`, companion ji vloží do každé stránky bez vlastní); kniha značky a stránka „co jste dostali“ nesou favicon klienta z balíčku značky (`docs/brand/favicon.svg` při každém přepisu stránky, `docs/zakaznik/www/favicon.svg` při generování). Studio: řádky odpovědí po konci běhu na celou šířku, u každého „Zobrazit“ (otázka, karty, odpověď z historie, jen ke čtení), „Změnit“ jen za běhu, tlačítko „Detail“ zrušeno.
- **`aid-ui-state.sh decide`**: rozhodnutí, které agent udělal bez PM, jde do stejného záznamu jako odpovědi PM (`by: "agent"`, krok, co, výsledek, proč, zdroj). Krok se zadává přesným názvem nebo id, platí limity 80/120/300 znaků. Stejné rozhodnutí zapsané podruhé je jedna událost. `--reconstructed --at` slouží pro zpětný zápis a stránka ho označí „doplněno zpětně“. Skill ho volá u faktů určených agentem (1v), po stavbě (6) a u doplňků design standardu (7); MUST Rule 9. Registr: `aid_ui_decide_refuses`, `aid_ui_outcome_length`, `aid_ui_steps_record_decisions`.
- **SEO pro AI vyhledávače (P103 rozšíření, K2).** Nový řádek brány `ai_search`: v SEO zadání je politika AI robotů, kterou volí PM (AI vyhledávání a citace / trénink), a `robots.txt` ji dodržuje s vlastní skupinou pro každého robota ze seznamu `coverage/ai-crawlers.json`; běžné vyhledávače nesmí být zablokované. Politika platí, jen když PM schválil právě tuto verzi zadání (odpověď `seo_brief` s otiskem souboru); jinak zpět do kroku 1s. Každá indexovatelná stránka má strukturovaná data se stránkou (`WebPage`…) a vydavatelem, vydavatel odpovídá registru faktů (pevné klíče `brand`, `ico`, `email`, `telephone`, `domain`; IČO v `identifier`, ne v `taxID`, to je DIČ; cizí organizace jako klienti se neporovnávají), hlavní text je v HTML bez JavaScriptu, žádný zákaz úryvků ani `llms.txt` bez rozhodnutí. Projekt bez SEO (`options.seo` false) má řádek N/A; nálezy za celý web jdou jen k domovské stránce a řádek běží v jednom prohlížeči. Pád kontroly je `not_covered`, ne výsledek. Brána nově předává kontrole SEO i zadání (tabulka stránek, H1) a fakta; dosud je nepředávala. Kontrola SEO navíc varuje u skrytého textu, stránky dál než 3 kliky nebo bez odkazu, stránky bez cesty ke kontaktu, téměř stejných stránek (kopie pro města), značky na začátku titulku a chybějícího hreflang u vícejazyčného webu. `--summary` zapíše čísla pro stránku zákazníka.
- **Cílený brand balíček (P103 rozšíření, K3).** Nový řádek brány `brand_package` a skript `aid-ui-brand-package.py`: co musí balíček obsahovat, se odvozuje z druhu projektu, z toho, zda vzniká značka, a z kontextů použití v zadání loga (standard: jen to, co projekt používá). Interní nástroj (`variant.brand` none) potřebuje jen favicon; jinak symbol ve čtyřech barevnostech, ikony (favicon.ico skutečně s 16/32/48 px), zásady a README, logo s názvem vždy (web, aplikace i PWA mají veřejnou tvář: barevně, u webu a PWA i na tmavém, u tisku černě) jako SVG i PNG a jeho zdroj s živým textem i ve verzi v křivkách (bez textu); u PWA maskovatelná ikona a světlý i tmavý lockup. Varianty se poznají podle celých slov cesty (`lockup/a/dark/x.svg` je tmavý, „mobile“ není bílá). Balíček od klienta bez některé části projde jen s výjimkou PM, která platí pro přesně ten seznam chybějících částí (`brand-waive-target` / `brand-waive`). Logo s názvem vyrábí `aid-ui-tool.sh wordmark` (symbol + název písmem webu i z víc souborů písma, např. latin + latin-ext pro češtinu; kerning z písma; viewBox podle skutečných obrysů, takže se háčky ani spodky písmen neuříznou; upravitelný zdroj s živým textem, verze v křivkách přes `fontTools` a varianty do `logo/`) a `aid-ui-tool.sh png` (PNG v Chromiu); `fontTools` a `brotli` (MIT) si nástroj při prvním použití nainstaluje do `~/.cache/aid-ui/pyfont`, nic do systému ani projektu. Kontroly za celý projekt mají v `checks.yaml` rozsah `scope: project` (jeden řádek) a `viewports` (podmnožina šířek). Dosud to jen „potvrdil agent" a Needless prošel bez loga s názvem a bez křivek. Rozšířená sada (sociální sítě, tiskoviny) až po schválení značky.
- **Texty webu podle převzatých marketingových postupů (P108, rozpracováno).** Krok 1: doslovný snímek pěti skillů z github.com/coreyhaines31/marketingskills (MIT, commit `dda3841`: product-marketing, copywriting, copy-editing, customer-research, cro; 14 souborů) v `skills/ui-design/references/adopted/marketingskills/`, `MANIFEST` s git blob id každého souboru, licence `LICENSES/MIT-marketingskills.txt`, registr převzatého se sloupcem „Čte ho"; test ověří shodu bajtů, chybějící i přebývající soubor, symlink a že čtenář soubor opravdu jmenuje. Krok 2: pravidla textů `references/copy-rules.md` (fakta jen z registru, hypotéza řídí jen tón, pořadí při rozporu, co blokuje v kontrole, kotvy skóre, právní stránky) a jazykové příručky `copy-cs.md`, `copy-sk.md`, `copy-en.md`; kroky 1v, 3 a 6 píšou podle převzatého copywritingu a rámců stránek z cro, krok 6 před bránou projde texty seznamem frází prozrazujících AI; krok 2 označí právní stránky `legal: true`. Krok 8: rozbor ostatních 45 skillů `docs/plans/P108-marketingskills-rozbor.md` (6 teď, 30 později, 9 nikdy). Krok 3: nový podkrok Podklady (`steps/1p-sources.md`, první bod kroku 1): `scripts/aid-ui-sources.py` vypíše soubory projektu a kandidátní rozhovory s agentem (jen zprávy člověka, úryvky s nahrazenými tajemstvími sdílenou tabulkou `_aid_artifact_redact`), rozhovor vstoupí až po schválení PM (otázka `sources`, cíl `<soubor>@<sha256>`); agent napíše `docs/content/product-context.md` (12 oddílů product-marketing se stavem a zdroji) a ptá se jen na chybějící, sporné a zastaralé údaje s ukázkou nalezeného; PM dokument schválí otázkou `product_context` a `aid-ui-state.sh context-check` ho hlídá v krocích 1v, 3 a 6. Nová kapitola `podklady`, nové druhy otázek `sources`, `product_context`, `copy_verdict`; samostatná otázka na `PRODUCT.md` v kroku 1 odpadá (je zdrojem podkladů). Krok 4: kontrola faktů (`facts_match`, nový modul `lib/ui-fidelity/aid-ui-facts.mjs`) chytí kromě telefonů, cen a časů i vymyšlené počty („200 klientům", „15 let"), procenta a e-maily; počet projde jen s položkou registru, která má stejné číslo jako celé číslo (2008 nekryje 200) a stejný význam (`klienti: 200` kryje „200 klientům", `tymy: 200` ne). Krok 5: nezávislá kontrola textů - `aid-ui-verify.sh <projekt> --copy-subject` vytáhne texty každé stránky (sjednocení 390 a 1440 px, jazyk, právní stránky; otisk jen z textu, ne z CSS), `scripts/aid-ui-copy.py` sestaví izolovaný balík (jen pravidla, převzaté copy-editing a cro, podklady, fakta, texty), spustí Codex jen pro čtení a zapíše `run.json` sám; záložní revizor Claude jen po neúspěšném pokusu Codexu a se záznamem spuštění; verdikt počítá skript (sedm průchodů, šest bodů cro, žádný blokující nález, žádná persona pod 5, tvrzení jen s klíčem faktu, příručka jazyka) a `aid-ui-state.sh copy-record` ho uloží po stránkách; schéma `references/copy-review.schema.json`; po třech neúspěšných kontrolách stránky ve stejné řadě rozhoduje PM výjimkou. Krok 6: nový řádek brány `copy_review` po stránkách (Chromium, 1440 px): projde jen se záznamem kontroly pro současný text stránky, současná fakta a schválené podklady; jinak řekne, co se změnilo, a bez záznamu je `not_covered`. Výjimka PM řádek nepřebarví, ale `finish` i stránka pro zákazníka ji přečtou (nový příkaz `aid-ui-state.sh exception-covered` se stejným párováním jako `finish`); stránka pro zákazníka už se kvůli přijaté výjimce nezastaví (mezera z K5), vypíše ji mezi „Výjimkami schválenými zadavatelem“ a v obsahu ukáže „N/N stránek prošlo nezávislou kontrolou textů“. Pět položek standardů o textech webu přeřazeno na `script:copy_review` (s revizí Codexu). Krok 1p v2 (po pilotu, 4. 10.): podklady i z dokumentů, které PM jmenuje (`--from`; redigované snímky, z HTML jen viditelný text, z PDF text přes pdftotext - bez něj je PDF v seznamu nepoužité s důvodem, sken bez textu také; u PDF se strop 2 MB měří na textu, ne na souboru; `--fetch-site <url>` stáhne živý web (úvod a odkazované stránky, `fetch.json` kdy a odkud) a seznam u každé stránky webu říká, zda je to živý web nebo záloha; průzkum na internetu je vždy samostatná otázka `online@<projekt>` a `context-check` bez její odpovědi (ano i ne) neprojde - skill nikdy nečte veřejný internet o firmě bez vědomí PM; interní soubory, symlinky a nečitelné formáty se vypíšou s důvodem a nečtou), a místo otázky za každý rozhovor jedna otázka na celý seznam (`manifest@<sha>`, neměnný snímek, škrtání `bez: <id>`, interní dokument jen přes `--request` a nové schválení); starý tvar souhlasu `<soubor>@<sha>` zrušen; `--purge` smaže snímky textů po schválení podkladů; dokument o produktu má oddíl vynechaných osobních a citlivých údajů a rozpory mezi podklady jako `rozpor`. Dokument o produktu dostane PM jako jeden návrh (postup product-marketing: návrh, pak „co je špatně, co chybí"), ne seznam otázek: rozpory a mezery jsou v textu jako „Ke kontrole" s návrhem, námitky a jazyk zákazníků agent nevymýšlí; studio vykreslí v textu otázky nadpisy, odrážky a tučné písmo (dosud ukazovalo hvězdičky). Kontrola textů už nečte jako text stránky prvek posunutý celý mimo stránku (past na spamovací roboty `left:-9999px` hlásila „Nevyplňujte" jako matoucí text); text jen pro čtečku uvnitř stránky čte dál. **Jedna mapa kroků a částí** (`skills/ui-design/sections.json`, po pilotu 4. 10.): studio ukazuje šest kroků jako „Krok N z 6" a v aktivním kroku jeho části se stavem (hotovo, teď, čeká, vynecháno) a u části, na které se pracuje, Proč, Cíl, K čemu dál a Co od vás - z nástroje, ne od agenta; každá otázka patří k části; vnitřní čísla kroků (0-7, 1p…) PM už nevidí a `/aid-ui <n>` bere čísla 1-6. Otázka na údaje má tři návrhy odpovědi se zdrojem (převzatý postup, podklady, registr, nebo přiznaný odhad), jinak ji studio odmítne. Kontrola textů: cílový i skeptický zákazník pod 7 = stránka neprojde (mimo právní stránku), chybějící skóre taky. Texty kroků a částí přepsány lidsky (O co jde, Co z toho bude, K čemu to poslouží, Co uděláte vy). **Kterákoli karta platí:** otázky na druh webu a volitelné části nesou na každé kartě `value` (JSON, který karta znamená) a cíl otázky je otisk mapy všech karet; `set variant|options` vezme hodnotu karty, kterou PM vybral (dosud šla zapsat jen doporučená karta, jiná volba PM byla odmítnuta). **Výběr, části kroku a změna odpovědi:** klik kamkoli na kartu ji vybere (rámeček a fajfka), odešle až „Další" vpravo v jediném řádku pod kartami (vlevo Bezpečněji, Znovu, Odvážněji a „Chci to jinak", které otevře okno na text - jako vlastní odpověď, nebo jako pokyn pro nové návrhy); stejný řádek mají i otázky bez karet („Ano, další", u stránky „V pořádku, další", souhlas s poznámkou přes okno); **rozvržení po pilotu 7. 10. (PM vybral ze čtyř návrhů v companionu):** hlavička na jeden řádek, pod ní pruh šesti kroků (u prohlíženého kroku (i) s tím, o čem je), pod pruhem jen jeden krok - u toho, na kterém se pracuje, hned řada částí jako pilulky (hotovo, teď, čeká, není potřeba) s Detailem vpravo, vždy na stejném místě; hotový nebo čekající krok má řádek s popisem, výsledkem a Detailem; klik na krok v pruhu ho ukáže (hotový rovnou s Detailem) a tlačítko vrátí ke kroku, na kterém se pracuje; nad otázkou nic, „Otázka k z n" vpravo u nadpisu, pod zadáním jeden odstavec o části (nové pole `text` v mapě, ručně napsané pro všech 15 částí); karty širší s delším textem; z části je vidět jedna otázka po druhé; **otázky části na jednom místě (7. 10. večer, PM: „vzhled ok, vrhni se do toho"):** nad otázkou žlutý řádek „Teď: <otázka>" a řádky otázek, které přijdou, pod prací blok „Hotové v této části" (fajfka, odpověď, Změnit - řádek vyjede nahoru a otázka se otevře nad prací jako „Teď"), rozpracovaná změna je v hotových jako „měníte - odpovídáte výše"; když pracuje agent a PM čeká, místo věty v rámečku ukazatel práce (kroužek, co agent dělá a co bude dál podle `now.title/text` v payloadu, běžící pruh); po odpovědi otázka odjede, řádek „Uloženo" probliká, další otázka přijede a po poslední se rozsvítí další část nebo krok (bez animací při omezeném pohybu); uložené odpovědi zůstávají v kroku jako „✓ Uloženo" s krátkým zvýrazněním a tlačítkem „Změnit", které otevře tutéž otázku znovu (`POST /change`, nová otázka `<id>.c<n>`; jen u otázek, které studio ještě ukazuje - agent je po zapsání nemaže, jen označí `done`); agent se o změně dozví slovesem `aid-ui-state.sh changes` ve své čekací smyčce a krok zopakuje. Schéma odpovědi kontroly textů se shoduje s pokynem revizorovi: bod se stavem `netyka_se` (právní stránka) potřebuje důvod a seznam nálezů mít nemusí; dosud schéma odmítlo jinak správnou odpověď Codexu. **Postup před výstupem (7. 10. odpoledne, PM: „všechno musí být zadrátovaný“):** mapa `sections.json` má registr `methods` - pro každý druh otázky soubory postupu (od kořene pluginu nebo živý standard pod `/opt/eco/docs/docs/ecosystem/`) a `receipt`, zda otázka nese výstup agenta; `aid-ui-state.sh method <projekt> <druh>` soubory vypíše (tak je agent čte) a zapíše stvrzenku `.aid-ui/method/<druh>.json` s otisky; studio (i `aid-ui-state.sh payload-check`, `server.py --check`) odmítne otevřenou otázku druhu s výstupem (product_context, facts, vision, identity, seo_brief, structure, task_map, content_plan, references, direction) bez stvrzenky z 12 h před jejím otevřením, se stvrzenkou na jiné soubory, nebo s kartou bez `method` (který soubor postupu a co z něj karta uplatňuje); hotová otázka projde jen se zaznamenanou odpovědí ve stavu, nic zpětně. Druh s `null` v mapě postup nemá: nelze ho položit, dokud PM nerozhodne otázkou `no_method` (nový druh; karty adopt / pm / without; `pm` = karty jen ze zdroje podklady) - „nemáme postup“ je otázka PM, ne tichý výstup. **Převzatý postup na logo:** doslovný snímek skillu github.com/kaankiziltug/logo-design-skill (MIT, commit `0ecf52e`; vstup, 14 referencí, 7 skriptů, 2 šablony, upozornění k ochranným známkám; 25 souborů, `MANIFEST` s git blob id, `LICENSES/MIT-logo-design.txt`, řádky registru převzatého) v `references/adopted/logo-design/`; knihovna 1 432 log cizích firem a skripty, které ji čtou, převzaty nejsou. Krok 1i staví logo jen tímto postupem: brief, klišé oboru, slovní mapa, aspoň dva typy značek, 8-12 konceptů po větě, tři nejsilnější v SVG černě, `svg_audit.py` a `preview_sheet.py` dvakrát, přehled `concept_sheet.py`; karty `identity` s `method` = typ značky a koncept (7. 10. PM zamítl tři koncepty pro Coufal Clinic kreslené bez postupu). Registr vynucení: `aid_ui_method_receipt`, `aid_ui_no_method_stop`, `aid_ui_logo_method` (585). Revize zadání Codexem: 11 nálezů zapracováno (done jen se zaznamenanou odpovědí, celý řetězec waiveru, tvar otázky `no_method`, cesty v mapě, `method` jmenuje soubor, `pm` ≠ `without`, jedna kopie pro otisk), 7 mimo model hrozeb (agent jako provozovatel může soubory padělat - stojí v `not_guaranteed`), 3 odmítnuty s důvodem (`evidence/P108/vyber-zmena/zadani.md`). **Rozcestník loga (7. 10. večer, PM: „to musí říkat ten skill, ne já“):** `scripts/aid-ui-logo-route.py <projekt> --write` spočítá ze stavu situaci (assets 0 / app 3 / přestavba 5 / nový 3 směry), sloty s pevným id a vlastní stavbou (u přestavby vždy oživení dnešního loga, je-li použitelné), kontexty (testovací podle situace + „Kde bude značka žít“ ze zadání), váhy bodování a doložitelnost bonusu kontinuity (registr faktů); studio odmítne otázku `identity` bez `route.json` nebo s jiným počtem karet než slotů (`slot` na kartě). Krok 1i: písmo názvu se volí v tomto kroku (tři kandidáti, `glyph` test), každý směr je pár logo s názvem + symbol + malý řez, police konkurence z jejich webů (`.aid-ui/refs/competitors/manifest.json`, stavy available / header-shot / unavailable / not_provided) místo nepřevzaté knihovny, brány před bodováním, re-roll jen vadného slotu, žádná náhradní cesta „PM dodá“. Nový nástroj `aid-ui-tool.sh logo-sheet --spec` (`lib/ui-fidelity/aid-ui-logo-sheet.mjs`): karta každého směru tam, kde bude žít (hlavička a hero, záložka 16 px, ikona na telefonu, avatar, vizitka černobíle) a přehled všech s policí konkurence; loga s názvem se vkládají jako SVG se živým textem, aby šla písma z Google Fonts. Registr vynucení `aid_ui_logo_route` (586). Revize Codexu (review8, 34 nálezů): zapracovány priority situací, nedosažitelná situace „jen mobil“ odstraněna, pole stavu s autoritou, sloty s jedinečnou stavbou, deterministické bodování s branami a tie-breakem, kontexty sjednocené, re-roll bez „PM dodá“; odmítnuto měření podobnosti kreseb (posuzuje checklist) a pevný vítěz v testu. **Symboly kreslí obrazový model (7. 10. večer, PM: A):** `scripts/aid-ui-logo-gen.py <projekt> --spec .aid-ui/logo/gen.json` pošle OpenAI `gpt-image-1` za každý slot rozcestníku N variant (pevná omezení: jeden černý plochý tvar na průhledném pozadí, bez textu, stínů a přechodů + druh slotu + věta konceptu; nic jiného z projektu neodchází), klíč jen z proměnné prostředí a v chybách smazaný, stropy 10 na slot, 60 na běh a `--max-cost` (3 USD; cena počítaná při odeslání), bez retry (timeout = „unknown, may have been billed“), PNG ověřené signaturou a 1024², nic se nepřepisuje bez `--force`, `--dry-run` píše jen `plan.json`; záznam `gen/gen.json` (verze, run id, sazebník s datem, prompty, requested/received, stavy succeeded/partial/failed). Agent varianty kurátoruje (`gen/vyber.json`, důvod u každé vyřazené) a zvolenou vektorizuje: `aid-ui-tool.sh vectorize` (`scripts/aid-ui-vectorize.py`: binarizace přes Pillow, vtracer ve venv `~/.cache/aid-ui/pyvec`, jedna sada černých cest, viewBox 256, parametry v komentáři; tvar pod 20 % plochy odmítne). Jen vektor jde do auditu, testu 16 px a na karty - `logo-sheet` odmítne jako symbol rastr i SVG s `<image>`/`<text>`/odkazem. Registr `aid_ui_logo_generated` (587). Revize Codexu (review9, 28 nálezů): 17 zapracováno (stropy ceny, stavy, offline, timeouty bez retry, validace odpovědi, bez přepisu, plan vs gen, vektor-only karty), 11 odmítnuto s důvodem (podepsané manifesty a serverová blokace mimo model hrozeb, hash wheelů, testy souběhu). **Zvětšený pohled po pilotu 9. 10.:** tlačítko druhého obrázku zůstávalo vidět i u karty bez něj (`.chip` nastavuje `display`, atribut `hidden` nestačil) a listování drželo „kontexty“ i na kartě, která je nemá - rozbitý obrázek (`/preview&n=2` 404); teď `.lb-bar [hidden]` skrývá, přepnutí platí jen pro kartu s druhým obrázkem a počítadlo říká „návrh 3 z 9“; šipky procházejí i galerii otázky potvrzované „Ano, další“ (rozložení stránek, texty) - dosud jen karty s výběrem, takže u rozložení stránek listovat nešlo. **Poznámky k jednotlivým stránkám (PM 9. 10.):** ve zvětšeném pohledu galerie (rozložení, texty) tlačítko „Chci jinak“ uloží poznámku k té stránce (figura dostane „· poznámka“), pod otázkou se objeví „Vrátit s poznámkami (N)“ a odešle je jako jedno vrácení s řádkem na stránku („Stránka „X“: …“) - agent předělá jen jmenované stránky; „Předchozí“ a „Další“ jsou přibité ke krajům lišty, ať je název jakkoli dlouhý. Tlačítko míry („jednodušeji / bohatěji“) záměrně není: rámec stránek z CRO míru nezná, agent by si ji vymýšlel. Revize Codexu (7 nálezů, vše zapracováno): poznámky žijí mimo překreslovanou část stránky (obnova stavu je nesmaže), okno poznámky píše do úložiště, ne do staré části, poznámku jde smazat, listování bere jen načtené obrázky, zaměření po zavření má náhradu, název stránky v řádku poznámky na jeden řádek, lišta se na úzké obrazovce zmenšuje. Lišta po PM (9. 10., A): uprostřed obrazovky s pevnou šířkou, „Předchozí“ a „Další“ hned u středového bloku, „stránka 3 z 9 · název“ zkrácený tečkami; všechny obrázky stejně široké, vyšší stránka se ve zvětšeném pohledu posouvá. **Mapa postupů (9. 10., PM: „ne vlastní tvorba“):** u obsahového plánu a vize přibyly do postupu převzatý copywriting (SKILL + rámce), pravidla textů a jazykové příručky (cs, sk) - krok 3 je vyžadoval, ale stvrzenka je nehlídala; otázka bez jejich přečtení teď neprojde. **Otázka na údaj (PM 9. 10., A):** `facts` a `no_method` se kreslí jako tři řádky pod sebou (doporučená předvybraná, jedna věta, drobný řádek riziko · z čeho) s tlačítky jen „Chci to jinak“ a „Další“; velké karty s rubrikami a Bezpečněji / Znovu / Odvážněji zůstávají u výběru vzhledu, vzorů a loga. **Předchozí rozhodnutí se nese dál (PM 9. 10.: „respektovat, co klient napíše, a mít to zadrátované“):** otázka na vzhled nese `prior` = zaznamenaná volba vzoru a slova PM, studio je ukáže nad otázkou, každá karta má `honours` (jak volbu ctí, jmenuje ji); bez toho studio otázku odmítne (`aid_ui_prior_decision`, 588). Tři směry vycházejí všechny z vybraného vzoru a liší se mírou (věrně / s obsahem navíc / odvážněji) - 9. 10. šly dva ze tří jinam a PM to právem vrátil. **Zadání pro vyhledávače:** kontrola AI připravenosti bere jako schválení i volbu karty na otázce svázané s přesně tímto zadáním (`choose` se stejným otiskem), ne jen `approve` - Coufal 9. 10. odpověděl kartou „osm stránek“ a brána zadání odmítla. Řádek brány `business_minimum` pozná odkaz na ochranu údajů i slovensky („ochrana osobných údajov“, `osobnych-udajov`, „spracúvanie“, „súkromie“). Kontrola textů bere odkaz revizora na bloky i jako seznam nebo rozsah (`b1,b3`, `b16-b19`), když všechny bloky na stránce jsou - Codex tak psal ve čtyřech bězích za sebou a stránky padaly na formu, ne na obsah. **Revize celku Codexem (12 nálezů, 6 zapracováno):** odpověď z historie se bere nejnovější podle času, ne poslední řádek; otázka na vzhled se odmítne i tehdy, když studio volbu vzoru drží, ale stav ji ještě nemá zapsanou, a zaznamenaná volba musí jmenovat kartu; řádková otázka nejde odkliknout do prázdna; popis serveru říká, odkud se odpovědi po restartu berou; slovenský odkaz na ochranu údajů i bez diakritiky; dokumentace říká přesně, co studio u `honours` hlídá (jméno volby, ne slova PM). Odmítnuto s důvodem: padělání historie (agent je provozovatel, mimo model hrozeb), `choose` jako schválení zadání (záměr), předpona vybrané karty v komentáři (strukturované pole je v backlogu). **Odpověď přežije restart studia:** `GET /answer` (a tím `set --answer`) bere po restartu i odpověď ze své vlastní historie (`history.jsonl`, kterou studio píše ke každé přijaté odpovědi, nově i s otiskem karet) - nikdy ze záznamu stavového skriptu, aby studio zůstalo nezávislou stranou ověření (bezpečnostní revize 9. 10.) - 9. 10. restart kvůli opravě vzhledu smazal schválení textů a `set content-plan` ho odmítlo. **Výjimka lidsky (PM 9. 10.: „proč tam jsou ty technický stačky vypsány“):** otázka `exception` ukazuje kontrolu českým jménem (Balíček značky, Kontrola textů, Pravidla vzhledu webu, Stránka pro zákazníka) a stránku; seznam chybějících položek z brány je složený za „chybí N položek“, ne vypsaný jako štítky. `aid-ui-state.sh exception` bere cíl otázky i bez klíčů, které jsou `*` (jak krok 7 slibuje); krok 7 říká, že na `_site` (soubory a 404) se stránková otázka neklade. **Schválené texty potvrzují obsah:** `aid-ui-state.sh confirm-content` převede položky plánu obsahu se zdrojem v textech na `confirmed_client` jen se schváleným verdiktem textů PM pro přesně tyto texty (jen `approve`; jednu položku bez textu potvrdí odpověď na údaj vázaná na klíč registru, který položka jmenuje, a na registr v dnešní podobě - revize Codexu: bez vazby by libovolná odpověď na údaj potvrdila libovolnou položku); dosud nebyla cesta, jak položky `draft` uzavřít, a `finish` by Coufal odmítl u 40 položek. Stránka pro zákazníka vypisuje v „Před spuštěním zbývá“ každou potřebu jednou (tři fotky s touž větou = jeden řádek). **Stavba podle vzoru a pohyb zadrátovaný (10. 10. 2026, PM 1A po Coufalovi 6/10: „web je nuda, animace chybí i níže“):** pohyb vzoru pozoruje nástroj za běhu, ne agent z CSS (`aid-ui-tool.sh motion`, `lib/ui-fidelity/aid-ui-motion.mjs`: načtení, druhé načtení = četnost, posun kolečkem až dolů, najetí a zaměření každého prvku, klik na vnitřní odkaz; každý keyframe, přechod, pohyb řízený skriptem i přechod stránky s místem hero / below / overlay, délkou a opakováním; knihovny Locomotive, Lenis, barba; `coverage` říká, co nástroj nevidí; schéma `references/motion-record.schema.json`). Soupis pohybu `.aid-ui/motion.json` (`scripts/aid-ui-motion.py inventory | check | summary | dirsha`): u každého pohybu vzoru převzat / nahrazen / vynechán s důvodem a lidským jménem, četnost úvodu podle vzoru (`first_load_only` jen s důvodem - 9. 10. PM úvod neviděl, protože agent sám zvolil „jednou za relaci“); kontrola proti pozorování směru i stavby (keyframe, který neběžel; vyplutí jen nahoře, když vzor má i dole; úvod, který při druhém načtení neběžel; cíl přechodu i se selektorem). Studio odmítne otázku `direction` bez soupisu (cíl `smer:<otisk>`, blok `motion` s větou a jmenovitými výjimkami nad kartami, karta `dir`) nebo se směrem, jehož pozorování vedle složky (otisk složky) soupis neprokáže - server kontrolu přepočítá sám, ručně napsaný výsledek nic neznamená; hotová otázka musí mít zapsanou odpověď o soupisu; bez vybraného vzoru se nic nevyžaduje. Krok Stavba má převzatý postup (`methods.build`: frontend-design, Impeccable craft floor, krok 6, živý frontend-build standard) a `build-record` odmítne bez stvrzenky z 12 h, bez volby směru nad soupisem v dnešní podobě a bez PASS kontroly nad pozorováním stavby s otiskem složky. Brána: řádek `motion_settled` (každá stránka: měří a fotí až po doběhnutí konečných animací, 500 ms klidu a zmizení úvodu `data-aid-intro` - jediný povolený způsob úvodu; strop 10 s) a `motion_fidelity` (brána stavbu pozoruje sama a kontroluje soupisem; bez vzoru N/A). **Konec běhu:** `aid-ui-state.sh links --web --customer` (obě 200) před otázkou `handover`, která obě adresy nese v textu a má tři karty převzít / s výhradou (studio si vyžádá, co vadí) / vrátit = hodnocení PM; `chapter-all` jen po poslední bráně nad stránkou pro zákazníka a zprávě souladu (9. 10. PM přebíral dvakrát); `gate-record` odmítne výsledek, který už je zapsaný (`--copy-subject` není běh brány a říká to); `finish` adresy ověří znovu a zapíše `finish.json`; studio ukáže panel **Hotovo** (věta z převzetí, Otevřít web, Co jste dostali, co zbývá, „Doplnit bod“). **Otevřené body a rozhodnutí:** `open-item add | done`, `open-items-sync` (body PM ze studia, `POST /open-item`), stránka pro zákazníka má oddíl „Co zbývá a co bylo rozhodnuto“ (otevřené body, odložený obsah se slovy PM, výjimky s důvodem, každé přijaté rozhodnutí s datem). Stará historie studia bez otisku karet: obnovená odpověď nese otisk karet z dnešního payloadu a `migrated: true`, stavový skript ji přijme jen při shodě s živě zapsaným otiskem. Záložní kontrola textů byla neprůchozí: `aid-emit-dispatch.sh` odmítal focus `copy-review-standin`, který `aid-ui-copy.py --stand-in` vyžaduje (10. 10. první výpadek Codexu); povoleno a krok 7 má přesný postup. Kontrola textů nečte písmena úvodního overlaye (`data-aid-intro`) jako text stránky. Studio a náhledy (`aid-ui-serve.sh`) žijí 7 dní místo 8 hodin - 10. a 11. 10. studio zmizelo přesně 8 h po startu (deadline jobu), zatímco PM měl otevřenou otázku „Předat web?“. Registr: `aid_ui_motion_observed`, `aid_ui_motion_inventory`, `aid_ui_build_method`, `aid_ui_motion_gate_rows`, `aid_ui_end_in_order`, `aid_ui_open_items`. Zadání `.aid-o/work/P108-stavba-zadani-2026-10-10.md`, revize zadání i částí 1-2 Codexem (15 + 12 nálezů; zapracováno: pozorování místo snímků, server přepočítá kontrolu, cíle se selektorem, `getAnimations()`, atomický zápis, migrace jen při shodě otisků; odmítnuto s důvodem: knihovny jako položky, selektor bez id, pevné písmo, sloučení focus do hover).
- **Stránka pro zákazníka (P103 rozšíření, K5).** Po zelené bráně vznikne `docs/zakaznik/index.html` (`aid-ui-customer-page.py`): nadpis „Nedostáváte jen vzhled webu.", soupis šesti oblastí (web, značka, viditelnost na Googlu a v AI vyhledávačích, pravidla rozvoje, obsah, marketing „připravujeme"), u každé čísla na očích a zbytek pod rozbalením; dlaždice SEO jsou vždy vidět. Každé číslo jde ze strojového zdroje, generátor odmítne bránu, která není zelená nebo je z jiného buildu. Nový řádek brány `customer_page` (stránka je z tohoto buildu a nemá interní slova; než vznikne, `not_covered`). Poslední čtyři položky mapy pokrytí převzaty skriptem.
- **Design standard projektu ve struktuře WANu, pracovně (P103 rozšíření, K4).** Krok 7 změří postavený web (`aid-ui-tool.sh measure`, i s přihlášením přes `--storage-state`: role tlačítek podle barev se stavy najetí, zaměření a zakázaný, výškou a písmem na 390/1440 px, pole formuláře, písmo, zlomy šířky i ve vnořených pravidlech, vrstvy, ikony, pohyb nad 10 ms; chyba jedné stránky se zapíše, neshodí měření) a `aid-ui-design-standard.py write` složí `docs/design/design-standard.md`: Značka, Tokeny (z `DESIGN.md`, ze kterého se generuje CSS), Komponenty (změřené, pojmenované tokeny), Vzory, Obsah a terminologie, Platformní kontrakt, Výjimky, Vynucení. Do Docusauru se nepíše nic, dokud PM standard neschválí. Tokeny se čtou přes `yq` stejně jako pro CSS; žádný oddíl `DESIGN.md` se neztratí (nezařazené jdou do „Ostatní z DESIGN.md“); u aplikace přibude oddíl Stavy úloh z mapy úloh. Nový řádek brány `design_standard_doc` hlídá oddíly a pododdíly tokenů, všechny tokeny oběma směry, že každá změřená barva je token, platformní řádky a že každá komponenta je zmíněná v platformním kontraktu; pád kontroly je `not_covered`, nikdy průchod. Po vygenerování standardu se brána pouští znovu. Dosud vznikal šestiřádkový odkaz na `DESIGN.md`.
- **Všechny standardy podle mapy pokrytí, kontrolované skriptem (P103 rozšíření, K1).** Mapa pokrytí (422 položek standardů) prošla rozřazením s nezávislou revizí: u webu skript 43 → 125 položek, PM 36 → 58, „jen tvrzení agenta" 94 → 8 (tam, kde skript neověří celé pravidlo), „netýká se" 120 → 102 (jen s důvodem, který platí i pro nový web); čtyři položky zákaznické stránky čekají na K5. Nové řádky brány: `token_usage` (každá barva a písmo na stránce je token `DESIGN.md`), `sticky_panels`, `keyboard` (Tab dosáhne každého ovládacího prvku a fokus je vidět), `reduced_motion`, `touch_targets` (44 px na mobilu), `safe_area` (PWA), `privacy_before_consent` (bez souhlasu žádný cizí požadavek ani cookie), `vision_doc` (`aid-ui-vision-check.py`) a `coverage`; řádek, který se stránky netýká, má v detailu „N/A“. Nový druh otázky `notifications` pro PWA. Design standard je vázaný na změřený build (`measure --build`).

### Changed
- **Schválení a výjimky podle rozsahu změny** (H4, retro: výjimka IČO obnovená 8×, schválení padala při změně společného stylu): inline `<style>`/`<script>` shodný na ≥ 2 stránkách je „společný styl“ s vlastním otiskem `build.shared` a schvaluje se jednou (`approve-page _shared`); otisk stránky je bez něj. Výjimka s `page: *` se váže na důvod kontroly (text detailu před „:“ nebo „(“), ne na otisky, a platí, dokud řádek padá ze stejného důvodu. `build-record` vypíše, která schválení nová stavba zrušila.
- **Studio odmítne karty vnořené v otázce** (H5): patří do `cards[]` s `question`; dřív je tiše zahodilo.
- **P106: studio /aid-ui jako průběh stavby.** Stránka studia ukazuje běh jako šest kroků pod sebou (Druh webu, Zadání a obsah, Vzory, Vzhled, Stavba, Kontrola). U každého je výsledek jednou větou a kdo rozhodl (PM, AI, oba). Detail otevře rozhodnutí kroku a karty, ze kterých PM vybíral, a čekající otázka stojí uvnitř svého kroku. Vzhled (paleta a karty Impeccable) zůstal ze schválené verze; logika odvození je ve vlastním bloku bez DOM a testuje se pod node.
- **Každá otázka nese `outcome`** (výsledek jednou větou, nejvýš 120 znaků, jinak 422). Server ho s `by: "pm"` zapisuje do `history.jsonl` pod zámkem souboru. Poškozený řádek historie se přeskočí a nevymaže ji celou, `/state` hlásí `history_lines`.

### Fixed
- **Záskok Claude za Codex je zadrátovaný** (PM 12. 10. 2026: „musí být zadrátované“): `aid-ui-copy.py run` po odmítnutí Codexu (limit, pád, prázdná nebo nepoužitelná odpověď) sám spustí nezávislý Claude Code s čistým kontextem nad stejným balíčkem (jen čtení, model `AID_UI_STANDIN_MODEL`, výchozí sonnet), uvnitř závorky dispatche, a zapíše `provider: claude` s důvodem; oba poskytovatelé selžou = kolo se nezapíše. Ruční `--stand-in` zůstává (`AID_UI_STANDIN=off`). Text nikdy nejde na API klíč; klíč čte jen generátor obrázků loga se svým stropem.
- **Kontrola textů čte i odpovědi v zavřených `<details>`** (klient-Codex, Coufal 11. 10. 2026): subjekt textů (`aid-ui-verify.sh --copy-subject`) před čtením otevře každé `details`, takže revizor nevidí „deset otázok, žiadne odpovede“ a nestrhne stránku za text, který nečetl. Test v `test-aid-ui-verify.bats`.
- **Design standard bez useknutých vět a s pohybem po prvcích** (klient vrátil standard: „nedokončené pravidlá značky, zoznam časov animácií nie je pravidlo“): zalomená odrážka z `brand-brief.md` je jedno pravidlo; oddíl Pohyb vypíše převzaté položky soupisu `.aid-ui/motion.json` jako tabulku pohyb / kde / spouštěč / trvání; měření bere za odstavec nejčastější styl `p`, ne první (úvodní odstavec 20 px pak nepopíral tělo 16 px). Testy v `test-aid-ui-design-standard.bats`.
- **Schválení textů se zapíše k položkám plánu obsahu.** `set content-plan` doplní položkám studia (`owner: agent`) zdroj `docs/content/copy.json`, podle kterého `confirm-content` potvrzuje texty; a `confirm-content` odmítne (a odpověď nespotřebuje), když není co potvrdit. Dřív plán bez zdrojů potvrdil 0 z 35 položek a schválení klienta propadlo.
- **Kontrola textů: odpověď s přebytečnou závorkou za hodnotou se čte, špatné vnoření se dál odmítá** (Coufal, kolo 4: 32 KB platného JSON a jedna `}` navíc).
- **Design standard: pohyb jako „prvek a co se stane - podnět - trvání“**, štítky převzatých položek ze sidecaru `.aid-ui/motion-labels.json` (štítek v soupisu by změnil jeho otisk a volbu směru), přechod stránky s trváním z vlastního záznamu buildu.
- **Měření počítá i ovladač, který existuje jen na mobilu** (tlačítko Menu mělo v tabulce rolí 0 výskytů a žádné stavy): role se počítá na šířce, kde je vidět, stavy se měří na první takové šířce. Řádek pohybu má jeden podnět (víc podnětů = víc řádků, podnět ten, při kterém nástroj pohyb na postaveném webu viděl); štítek ze sidecaru má přednost před štítkem v soupisu.
- **Měření webu pro design standard čte stav najetí a zaměření až po doběhnutí přechodu** (`aid-ui-tool.sh measure`): dřív snímek uprostřed 0,5 s přechodu barvy dal odstín, který žádný token nemá, a `aid-ui-design-standard.py check` ho hlásil jako MISSING. Test „measure reads a hover state at the end of its transition“.

### Removed
- Záložka Průběh, přehled výsledků („overview“: adresa webu, seznam úkolů, dlaždice) i pole `overview` v payloadu a jeho kontrola na serveru.
Velikost kódu (V6): `studio.html` + `server.py` + `aid-ui-state.sh` měly před P106 2 340 řádků, teď mají 2 321. Stránka ubrala 87 řádků, server a stavový skript přibraly 16 a 52 za zámek historie a příkaz `decide`.

## [2.117.0] — 2026-10-11

Běh rovnou z plánu (P111, první půlka vydání 3 roadmapy po experimentu P014; PM 2B: P111 přidává, P112 maže). Recenzovaný plán se spustí `/aid-run P<NNN>` jako jeden běh na větvi `plan/<id>` — bez EPIC souborů, fronty, task větví a merge EPICu; jiné repo je pracovní kopie (worktree), nikdy jeho živý checkout; zrušení plánu ukončí běh i ve FSM a v mapě běhů. Stará EPIC cesta (`/aid-run E-…`) funguje beze změny do P112. Stavěno mimo AID (PM 11. 10. 2026); revize po krocích Codex, při jeho vyčerpaném limitu nezávislý Claude agent s čistým kontextem.

### Added
- **Přímý start `aid-plan-fsm.sh plan-run P<NNN> [--auto]`** — povinnosti generace v jedné transakci pod zámkem generace (tentýž jako pipeline, takže se obě cesty vylučují), zapisované po stupních do jediného `generation/transaction.json` (`kind: plan_run`), takže přerušený start dokončí stejný příkaz: `plan-start` v režimu `plan_branch` s jediným deklarovaným během `E-<nnn>-1_1` (i v projektu bez `gate_profiles`), readiness, pečeť CP1, `plan.json` celého plánu, D5, `epic_input.md`, worktree cizích rep, záznam v manifestu (`direct: true`, bez task větve), kontrola účtenky (graf plánu, bajty plánu, otisk `plan.json`) a `aid-fsm.sh init … plan/<id> … --direct`. Odmítnutí: `plan_run_already_started`, `generation_already_started`, `plan_changed_since_seal`, `lifecycle_epics_mismatch` (oprava `plan-state --declare-epics`), `plan_json_unverified`, `plan_in_scratch_tree`, `generation_lock_held`, `plan_not_found`.
- **Jeden stavitel `plan.json`** — `lib/aid-plan-json.sh` (stavitel přesunutý z `aid-epic-to-json.sh` a čtečka kroků přesunutá z `aid-plan-to-epic.sh`); EPIC cesta volá tutéž knihovnu, golden výstup beze změny (a 80 porovnání starého a nového generátoru na skutečných plánech beze rozdílu). `plan.schema.json`: `direct`, `repo_roots`.
- **Větev plánu je větví běhu** — commit kroku přímého běhu na `plan/<id>` (jen pro běh, jehož stav říká `direct: true` a tu větev jmenuje); pre-commit hook hlídá větev až do `DONE`/`done_phase: release`; `done-advance review release <state> --direct` zapíše běh `merged_to_plan` na tipu `plan/<id>` a převede plán do `PLAN_SYNC` (přes `epic-complete --direct`) ještě před zápisem `release`; `epic-merge-to-plan` přímý běh odmítne (`direct_run_no_epic_merge`), `done-advance` bez/s `--direct` na nesedícím běhu `done_advance_needs_direct`; freeze odmítne přímý běh, který neprošel svým `done-advance`.
- **`repo_roots`** — hlavička plánu `repo_roots: [{name, path[, base_branch]}]` (lint: `repo_root_invalid`); `plan-run` založí, nebo při obnově převezme, worktree `<path>/.aid-worktrees/plan-<id>--<name>` na větvi `plan/<id>-<projekt>` a jedno mapování v `plan.json`. Kontrakt kroku pošle cizí soubor do worktree („never in <path>“), návrat jmenuje repo jménem, kontrola kroku i validátor návratu přijmou jen neprázdný rozsah dosažitelný z větve worktree (commit v živém checkoutu sdílí objekty, a přesto neprojde); krok jmenující nedeklarované repo nedostane kontrakt (`foreign_repo_undeclared`). Uzávěr zmrazí hlavy cizích větví, `produce`/`decide` odmítnou chybějící worktree, větev posunutou po zmrazení nebo nahlášený rozsah mimo ni (`foreign_branch_unverified`); rozhodnutí, karta PM a stránka uzávěru cizí větve vypíšou — mergne je PM ručně.
- **Zrušení až do konce** — `aid-fsm.sh abandon <state> --reason` (ERROR přes tabulku přechodů, `DONE:ERROR` jen z `done_phase: review`, `abandoned: true`, událost `abandoned`, záznam pryč z `active-runs.json`); `epic-complete --abandon` a `plan-close --administrative` to dělají jako jeden opakovatelný přechod manifest → FSM → mapa, administrativní uzávěr ještě před svými kontrolami i u plánu už zavřeného (tvar P080: běhy zůstaly READY). Hook odmítne commit na větvi opuštěného běhu (`run_abandoned`); prázdný důvod `abandon_needs_reason`. Staré běhy P080 (E-080-2_3, E-080-3_3) lze ukončit ručně: `aid-fsm.sh abandon <state> --reason …`.
- **Inventura EPIC cesty** — `docs/reference/2026-10-p111-inventura-epic-cesty.md`: 52 řádků registru vynucení s verdiktem (16 přechází, 24 zaniká v P112, 12 zůstává); podle ní P112 maže.

### Changed
- Pečeť CP1, její ověření, zámek a zapisovač transakce generace jsou knihovna `lib/aid-generation-authority.sh` (přesunuté beze změny; pipeline a generátor ji volají).
- `/aid-run P<NNN>` je výchozí cesta pro nový plán; `/aid-plan` končí „plán je připraven ke spuštění `/aid-run P<NNN>`“, režim Generate EPIC je stará cesta do P112. `/aid-status` ukáže přímý běh jako „běh 1/1 (přímý)“ a opuštěné běhy ani jejich položky fronty neukazuje.
- `skills/pipeline.md` §„When AID refuses“: 16 nových řádků s `next:`; kontrola souladu skenuje i `aid-plan-fsm.sh`, `aid-auto-pipeline.sh`, `lib/aid-dispatch-contract.sh`, `aid-plan-lint.sh` a pre-commit hook. Registr vynucení: 14 nových řádků (628). Docusaurus `/aid/` (aid-run, aid-plan, architektura) v repu docs. Testbed: lany `direct_run` (přímý běh na klonu testbedu: tři skutečné kroky, brány, `done-advance --direct` a uzávěr až k rozhodnutí AWAITING_PM, bez `--force`) a `repo_roots` (worktree cizího repa, odmítnutí nedeklarovaného repa a rozsahu z živého checkoutu při uzávěru).
- Generace zrychlená skoro zpět na 2.116.1: sdílená čtečka kroků a stavitel `plan.json` čtou krok jedním voláním `jq` místo jednoho na pole a lint spouští `yq` pro `repo_roots` jen tehdy, když hlavička to slovo obsahuje (fixture o třech fázích 62 s → 58 s, 2.116.1 55 s; test souběžné generace čekal na zámek 60 s a padal). Test souběhu má vlastní delší čekání, čekání na zámek zkouší samostatný test. Opravena zestárlá očekávaná hodnota v `test-plan-fixture-contract.bats` (šestý sloupec Zavírá od 2.115.0).

### Security
- Rozsah z cizího repa musí být neprázdný a dopředný (začátek předkem konce) — i na staré cestě s absolutní cestou; jinak by prázdný rozsah schoval cizí změnu před revizí (nález automatické bezpečnostní revize commitu).

### Velikost pluginu (řádky, `wc -l`)

| část | před | po |
|---|---|---|
| scripts | 73 115 | 74 076 |
| skills | 8 332 | 8 348 |
| commands | 5 896 | 6 003 |

Měřeno: `scripts/*.sh` + `scripts/lib/*.sh`, `skills/*.md` + `skills/*/SKILL.md`, `commands/*.md`. „Před“ je číslo zadání; na 2.116.1 je scripts přesně 73 128 (+13 z opravy 2.116.1). P111 přidává novou cestu vedle staré; ubírat bude P112 (V5 vize se měří po něm).

## [2.116.1] — 2026-10-11

Oprava po vydání 2.116.0 (nález automatické bezpečnostní kontroly pushe).

### Fixed
- **Revize kroků zastupují revizi EPICu jen při vypnutém CP3** — lifecycle (`_aid_lc_epic_review_file`) v 2.116.0 brala poslední kolo revize kroku jako záznam revize EPICu i u projektu, který CP3 zapnuté nechal a revizí EPICu neprošel; doručení takového EPICu pak prošlo jako zrevidované. Teď u zapnutého CP3 bez záznamu cp3 zůstává doručení neověřitelné, jako před 2.116.0.

## [2.116.0] — 2026-10-10

Levnější běh (P110, vydání 2 roadmapy po experimentu P014). Krok si koupí revizi podle druhu změny, body hotovo se spouští po každém kroku a v uzávěru izolovaně, uzávěr čte zadání se dvěma rolemi, brány musí doložit, že pustily testy projektu, CP3 je vypnuté jako výchozí a uzávěr vyčíslí, co stál běh a plán. V P014 šlo 54 min na revize kroků a EPICů, 64 min na tři pokusy uzávěru a dva body hotovo nikdo nespustil. Stavěno mimo AID (PM 10. 10. 2026); revize po každém kroku dělal Claude podagent s čistým kontextem, protože Codex měl vyčerpaný limit do 14. 10. 2026.

### Added
- **Revize kroku podle druhu změny** — `step_review` má jedno kolo, práh přeskočení 3 soubory / 120 řádků, `step_generalist` i `step_security` běží jako lehcí revizoři a `step_security` jako plný při verdiktu `review+security` (`full_when`); `round.json` `agents` zapíše volbu. Druhé kolo jen jako potvrzení opravy otevřeného blockeru nebo majoru (`second_round_when: open_finding_and_fix`; prompt nese jen `fix.patch` a otevřené nálezy) nebo jedno delta kolo po prošlém kole; třetí jen s přepisem nebo stálým pokynem PM. Projekt si staré chování podrží ve vlastní `review-checkpoints.yaml`.
- **Body hotovo po kroku** — `aid-plan-diff.sh --step N --plan-json` spustí body zadání, které krok zavírá (bod jmenovaný víc kroky až u posledního, napříč EPICy), a vlastní kritéria kroku `- [ ] [<role>]` s blokem; `prepare --checkpoint cp2` ho pustí před balíkem a revizor vidí naměřené verdikty. `increment-step` odmítne krok s bodem `absent` (`step_criteria_failed`, i s `--force`); jediná cesta ven je odpověď PM na kartě: `--defer-criterion AC<n> --reason … --finding-card <karta>` (`defer_refused`). Měření se přijme jen se svou událostí v timeline (otisk souboru). `plan.json` nese `plan_step`, blok smí nést `timeout:` (1–1800 s).
- **Izolovaný měřič uzávěru** — `aid-plan-diff.sh --isolated --cwd <kandidát>`: bez `verification_env:` každý bod v novém síťovém prostoru se zapnutým loopbackem, pod původním uid a ve vlastním prostoru procesů; s `verification_env:` s jeho proměnnými a sítí hostitele (`network: host (verification_env)`). Bod, který tak běžet nejde, je `absent` s důvodem (`no_isolation`, `env_stripped`, `no_verification_env`, `verification_env_unset`) a rozhodnutí o vydání ho jmenuje jako neměřený. Volá ho `plan-finalize --stage produce` i brána `plan_diff` šablony.
- **Uzávěr se zadáním a dvěma rolemi** — výchozí `final_review` má `final_criteria` (zadání bod po bodu proti izolovanému měření) a `final_generalist` (Codex: napříč EPICy, tvrzení v CHANGELOG/README a bezpečnostní a provozní seznam); `final_claims` zůstává volitelná. Balík i prompt nesou `zadani.md` přes sdílený resolver CP1 (`aid_plan_review_brief_resolve`, nové `zadani_file_missing`); `prepare` odmítne cizí zadání (`cp7_brief_sha_mismatch`) a neizolované měření (`cp7_measurement_stale`).
- **Brány s testy projektu** — `execution.yaml` `project_tests:` a brána `runs_project_tests: true`, která evidencí (`--evidence-file`) dokládá, co spustila; změna testů bez takové brány v profilu je `profile_skips_project_tests`, brána bez důkazu `project_tests_evidence_missing`, nespuštěné změněné testy `project_tests_not_selected`, sada vynechaná patrem `nightly_covers`; bez klíče jen rada `project_tests_undeclared`. `run-all-tests.sh --evidence-file`, `aid-run-gates.sh record-tests` (obal běžce celé sady) a `--lint-profiles`; `/aid-init` klíč zapíše podle zásobníků a existujícímu souboru ho nabídne; zásobník bash má bránu `bash_test`. Vzory umí `**/`.
- **Cena běhu a plánu** — `release-decision.json` `plan_summary.run_cost` (každé kolo každého běhu EPICů a pokusů uzávěru) a `plan_cost` (CP1 a kritik z událostí Codexu, u záskoku `null` s důvodem); karta, brief a stránka uzávěru mají řádky „Cena běhu“ a „Cena plánu“; nečitelné měření je `measurement_unreadable`.

### Changed
- **CP3 vypnuté jako výchozí** (PM 2B) — `cp3_integration_review: false`, blok `epic_review` jen jako komentář; přechody zapíšou `review_checkpoint_disabled`. Běh „streamlined“ (bez revizí kroků) s vypnutým CP3 projde jen v režimu `plan_branch` (čte ho CP7), jinak odmítnut — šel by ven nerevidovaný. Přepínače se čtou z kořene stavu. Kód CP3 odejde s EPICy ve vydání 3.
- **Kontrola karty PM sdílená** — `aid_pm_card_check` v `lib/aid-decision-card.sh` (citace jako celé slovo) pro `dispute --pm accepted` i odklad bodu.
- `skills/pipeline.md` §„When AID refuses“: 15 nových řádků s `next:`; test souladu skenuje i `aid-run-gates.sh`, `aid-plan-diff.sh` a `aid-release-policy.sh`. Registr vynucení: 10 nových řádků (614). Docusaurus `/aid/` (aid-run, mantinely) v repu docs.

### Fixed
- **Uzávěr čte řádek brány přes normalizovaný stav** (`aid-plan-fsm.sh` hledal neprošlou bránu přes `.value.result`; noční kontrola `P097 rows` byla červená už v `main`).
- **S vypnutým CP3 dostane uzávěr, co nechaly otevřené revize kroků** (`epic-findings.json` `cp3: "off"` s otevřenými blockery a majory posledního kola každého kroku) a revizor ho už nečte jako EPIC, který nikdo neviděl.

### Security
- **Bezpečnostní revize zúžení** (AC6, `docs/reference/2026-10-p110-bezpecnostni-revize.md`): nezávislý Claude agent s čistým kontextem jako záskok za Codex (limit do 14. 10. 2026; PM 1B). Deset nálezů, sedm opraveno: krok se vzorem obsluhy (routa, CLI vstup) se nepřeskočí a nový vzor `shell_string_exec` (`bash -c`, `eval` proměnné, `execSync`) vede k plnému revizorovi; kontrolní seznam CP7 má injection napříč kroky, cesty a symlinky a padělanou důvěru; body kroku se měří jen z plánu, ze kterého vznikl EPIC (`plan.json` `source_plan_sha256`); s vypnutým CP3 se zbylá `cp3/` nečte a uzávěr vidí i nálezy zamítnuté PM; lifecycle rozhoduje podle všech kroků běhu; `record-tests` odmítne běžec s výběrem testů. Tři do backlogu (IMP-691..693); běh starého režimu (historické plány) s vypnutým CP3 a malými kroky zůstává bez revize celku — vědomě přijato (PM 11. 10. 2026), nové plány běží v `plan_branch` a celek čte uzávěr.
- **Krok nikdy nečeká na Codex** — `skills/plan-writing.md` pravidlo 20: revizi přidělenou Codexu udělá při jeho nedostupnosti nezávislý Claude agent, jak to plugin dělá od P095.

### Velikost pluginu (řádky, `wc -l`)

| část | před | po |
|---|---|---|
| scripts | 72 060 | 73 115 |
| skills | 8 270 | 8 332 |
| commands | 5 796 | 5 896 |

Měřeno: `scripts/*.sh` + `scripts/lib/*.sh`, `skills/*.md` + `skills/*/SKILL.md`, `commands/*.md`. Přibylo kontrol a jejich testů; V7 roadmapy měří, necílí.

## [2.115.0] — 2026-10-09

Plán drží zadání (P109, vydání 1 roadmapy po experimentu P014). Zadání PM je soubor, plán nese jeho body doslova, kritik je povinný a generace ho nepřeskočí, každý revizor plánu čte zadání a stačí jedno kolo, oprava po kole i rozšíření rozsahu za běhu se k zadání vážou. V P014 plán bod 2 zadání vypustil a nic to neporovnalo; teď to odmítne lint, revizoři mají zadání před sebou a změna bodu je nová verze souboru zadání. Stavěno mimo AID (PM 9. 10. 2026), po každém kroku revize Codexem.

### Added
- **Zadání jako soubor** — `/aid-plan` (brainstorm krok 8 i Write) píše nejdřív `.aid-o/plans/P<NNN>-zadani.md` ze šablony `defaults/templates/zadani.md`: šest očíslovaných částí, odstavec „Co je v sázce“, body hotovo `- [ ] AC<n>:` s blokem `verification_pattern` v gramatice, kterou plugin už měl. `aid-plan-lint.sh --zadani` vypíše všechna zjištění najednou. Jeden čtecí kód zadání (`lib/aid-zadani.sh`) a jeden čtecí kód a validátor kritérií (`lib/aid-verification-pattern.sh`) pro spouštěč, kontrolu plánu A6, lint zadání i lint plánu.
- **Plán nese zadání** — lint odmítne plán, v jehož `## Acceptance Criteria` chybí nebo je přepsaný bod zadání (text i blok, stejný parser na obou stranách), bod, který nezavírá žádný krok (`**Zavírá:** AC<n>`), nesedící `zadani_verze`/`zadani_sha256`, návrhový oddíl bez `**Odvozeno z:** AC<n>`, a přísný plán bez zadání (`--only zadani` pouští jen tenhle průchod). `Zavírá:` jde přes šestý sloupec tabulky EPICu do `plan.json` jako `steps[].zavira`; `plan.json` nese `zadani` a `zadani_sha256`. Stránka PM ukáže body zadání s kroky, které je zavírají, a rozhodnutí označená `(mění výsledek pro uživatele)`.
- **Kritik povinný a nepřepsatelný** — `prepare --round 1` odmítne plán bez prošlé kontroly kritika pro plán, který kopíruje, a zapíše `critic_check_sha`; brána CP1 to kontroluje tvrdě (`--force` ani vypnutá revize to neodpustí), proti plánu, který vstoupil do kola 1, nebo bez kola proti plánu, jak je. Kritik nad plánem čte zadání ze souboru, ne z interimu; `aid_critic_dispatch` ho pouští přes sdílený transport Codexu s promptem „vypiš, nezapisuj“ a odpověď bez obou nadpisů úrovní je záskok (STAND-IN), ne kritika. Jeden verdikt `aid_critic_verdict` pro balík i bránu.
- **CP1 se zadáním a jedním kolem** — balík nese `zadani.md` a jeho otisk; první otázka každé ze šesti rolí je bod po bodu: zachovává / změkčuje / vypouští / odporuje (kromě „zachovává“ blocker); `zadani.md:<řádek>` je citovatelný. Výchozí počet kol je jedno; druhé bez přepisu PM jen po kole 1 s blockerem a prošlým `fix-check` (`second_round_when: blocker_and_fix_check`, jedna funkce pro `prepare` i bránu). Zadání změněné po kole 1 odmítne brána i příprava dalšího kola.
- **Změny po kole a za běhu proti zadání** — `fix-check` pustí průchod zadání z lintu: bod se mění jen novou verzí zadání (`verze` +1), jinak odmítnuto; revize se pak restartuje v novém pokusu (`prepare --round 1 --restart --reason`, staré kola v `cp1/attempt-<k>/`; nic se nepřesune, dokud nové kolo 1 nejde připravit). `amend-scope` u plánu vázaného na zadání chce v důvodu bod `AC<n>` aktuálního kroku (v GATES kteréhokoli), jinak odmítne, a zapíše ho jako `zadani_point`.
- **Pět mantinelů v Docusauru** (`/aid/architecture/mantinely`) a standard souboru zadání (`/aid/specs/zadani`).

### Changed
- **Sonda Codexu se zapisuje do kořene stavu** (z worktree plánu ho už nešpiní); **kontrola dvou kopií porovnává jen plán**, deník ne (agents P013-3/5/12); `/aid-init` zapíše `.gitattributes` s `merge=union` pro deník (P108 §17).
- **Hledání souboru plánu podle čísla vynechá soubor zadání** (`aid_plan_files`) — zadání leží vedle plánu pod stejným číslem; brána konce plánu by jinak mohla pustit kontrolu kritérií nad zadáním a projít naprázdno.
- `skills/pipeline.md` §„When AID refuses“: 11 nových řádků s `next:`; test souladu teď prochází i `aid-review-round.sh`, `aid-cp1-gate.sh` a balík. Registr vynucení: 14 nových řádků (604).
- Testbed: `plan-clean.md` nese vlastní zadání a jeho kolo CP1 zasévá kritika (repo testbedu, commit fbd3420). Dokumentace Docusauru v repu docs, commit f018e76. Roadmapa `docs/plans/2026-10-09-roadmapa-p109.md`; P104 archivován.

### Fixed
- Čtyři noční červené sady zelené: řádek `/critic` v rejstříku nápovědy (skill nebyl nikdy veřejný povrch), vzor odkazu na sdílenou sekci v testu karet agentů (formulace od 2.112.0), zastaralá citace `stop-server.sh` v registru, test stránky PM s rolí `docs`, platnou od 2.112.0.

### Velikost pluginu (řádky, `wc -l`)

| část | před | po |
|---|---|---|
| scripts | 71 195 | 72 060 |
| skills | 8 169 | 8 270 |
| commands | 5 699 | 5 796 |

Měřeno: `scripts/*.sh` + `scripts/lib/*.sh`, `skills/*.md` + `skills/*/SKILL.md`, `commands/*.md`. Přibylo hlavně kontrol a jejich testů; čistší plugin je cílem vydání 2 a 3 (V7 roadmapy: měří se, necílí).

## [2.114.0] — 2026-10-06

Co zbylo z P010 (agents) a z P106/P108: zavření plánu rozhodnutím, kola bez patu, měření, kolik toho zavírání samo rozbilo, a companion, který přes VPN naběhne a vždy ukáže skutečný stav aplikace vedle návrhu. Vše vynucené mechanismem; tvrdý strop kol a mutace jako brána zatím ne (PM 6. 10. 2026, 2A: nejdřív čísla).

### Added
- **`dispute --checkpoint cp7`** — nález závěrečné kontroly, který autor vyvrátil měřením, PM odložil do backlogu nebo rozhodčí zamítl na formě (`form_invalid`, důkaz mimo repozitář kandidáta), se vyřídí stejnou kartou a odpovědí PM jako u CP2/CP3; dispute zapíše své zápisy jako stage (`cp7-dispute-<odpověď>`), takže `plan-finalize --stage decide` čte rozhodnutí, ne „soubory změněné po close“. P010 (agents) se dvanáct kol nedal zavřít a skončil ručním merge s FSM v `PLAN_REVIEW`.
- **`retry` před `collect`** — role, která v kole nic nedala (bez souboru odpovědi; záznam Codexu `answered: false`, nebo bracket bez `complete`), jde pustit znovu hned; otevřený start se stáhne (`cancel`, důvod `retry`). Role s odpovědí, mimo kolo nebo s dokončeným bracketem je dál odmítnuta. Limit účtu shodil všechny role najednou a kolo stálo.
- **`aid-emit-dispatch.sh start` odmítne roli, kterou kolo nemá** (`reviewers_expected` v `round.json`; `round.json` bez seznamu rolí také odmítnut), a **`cancel --focus … --reason`** poctivě stáhne otevřený start: řádek `cancel` v ledgeru, událost `verifier_dispatch_cancel` v timeline, ŽÁDNÝ `complete` — odpověď podaná pod staženým startem nemá původ a `close` ji dál odmítá; `close` stažené starty jmenuje (`measurement.json` `cancelled_starts`). Platí poslední bracket: starý `complete` nedosvědčí soubor napsaný po novějším stažení.
- **Měření zavírání** — každý `close` u CP7 zapíše `closing` (pokus z řetězu `fix-class.json`, minuty od prvního zmrazení, počet vážných nálezů, jejichž první citovaný řádek napsalo až zavírání — `git blame` proti prvnímu kandidátovi, korelace, ne rozsudek —, necitované řádky, nálezy Codexu zamítnuté na formě) a vypíše řádek `closing: attempt N, M min …`. `aid-run.md` dostal pravidla zavírání: opravy po třídách, seznam volajících před commitem, po třetím pokusu, který se živí sám, karta PM místo další opravy (pravidlo pro controller, ne brána).
- **Konec plánu říká, co nezměřil** — `aid-plan-diff.sh` počítá `summary.unmeasured` (souhrnná kritéria bez vzoru, souhrnné odrážky bez značky `AC<N>:`, krokové odrážky pod `**Acceptance Criteria:**`), `produce` je zapíše do `acceptance-evidence.json` (`verdict.unmeasured`, `measured`) a vypíše, release policy je nese ve zdůvodnění a stránka pro PM má řádek „Acceptance criteria“. P010: 13 měřených proti ~57 krokovým, `status: pass` a nikdo si nevšiml.
- **Companion na pevném portu z rozsahu AID** — mimo loopback první volný z dvaceti slotů 3930–3949 (`AID_COMPANION_PORTS`; PM jich mívá deset najednou), `--port` mimo 3900–3999 odmítnut, obsazené sloty se nepřebírají (výpis držitelů s PID, stářím a příkazem k zastavení), po startu `curl` na vytištěnou adresu; `stop-server.sh --list` vypíše běžící companiony (plán, projekt, port, odkaz, stáří, držen), `--stale [h] --project-dir <root>` zastaví zapomenuté companiony jednoho projektu (jen `node index.js` z `brainstorm-server`, držené nechá). **Companion se vypne sám** po 12 h bez prohlížeče a bez nové obrazovky; tlačítko „Držet“ na stránce ho podrží (`.keep`), po 60 dnech od startu skončí tak či tak; soubory zůstanou (PM 6. 10. 2026: dva sloty málo, úklid sám). Náhodný vysoký port přes VPN neprošel dvakrát za den (agents P013, WAN helpdesk, 6. 10. 2026); že rozsah 3900–3999 prochází, je provozní fakt ověřený studiem, ne vlastnost kódu.
- **Companion skládá „dnes → návrh“ sám** — `--project-dir` vyžaduje `--plan`; běh musí říct `topic_kind ui|other` (zavírá únik přes scope `roadmap`); UI běh musí mít `proposal.json` z aplikace podle jedné sdílené kontroly `aid_ui_proposal_basis_check` (brána `enter-phase design` ji volá taky); server (`lib/brainstorm-server/basis.js`) servíruje snímky pod `/basis/<viewport>/baseline.png` a na `/` ukáže skutečný snímek v reálné šířce vedle obrazovky agenta ve stejné šířce (`/screen` v rámu, titulek záložky = plán · projekt), u základu `design-system` pruh NO LIVE BASELINE s důvodem. Agent skutečný stav nemůže vynechat. **Návrh vzniká v kopii skutečné stránky:** nástroj snímku ukládá i stránku tak, jak ji prohlížeč sestavil (`baseline.html`, styly vložené, skripty pryč, `<base>` na aplikaci), `proposal.json` ji nese (`page`), server ji dává na `/basis/<viewport>/page.html` a agent ji zkopíruje jako svou obrazovku a změnu doplní do ní místo kreslení (PM 6. 10. 2026, 1B). Skill má tvrdý krok „Existing UI: the basis from the application comes first“.
- **Companion si doinstaluje závislosti** — chybějící `node_modules` po aktualizaci pluginu `start-server.sh` nainstaluje a zapíše do `.server.log`; selhání vypíše přesný příkaz místo „failed to start within 5 seconds“.
- **`aid-generation-readiness.sh --project-root`** — plán stojící na větvi jiného plánu se kontroluje proti jeho worktree (plan-check to uměl, readiness ne; P106).
- **Kritik: úprava plánu před `aid_critic_check`** se zapíše jako ta jedna povolená revize (`plan_sha256_revised`, `revised_before_check: true`), `aid_critic_rebind` je pak odmítnut jako druhá; check, který padne na formě, revizi nezapisuje. P108: druhý běh kritika za ~115k tokenů kvůli pořadí dvou příkazů.

### Changed
- **Fix list po kole CP1** jmenuje krok každého otevřeného nálezu (i minor); otevřený plán-level blocker/major dává `any` (`aid-plan-check.sh --fixes any` vypne jen C4/C5). P106: tři minory jmenovaly krok 5 a oprava tam byla odmítnuta jako nevyžádaná.
- **Název s lomítkem není cesta** (`_aid_artifact_looks_like_path`: dvě složky, přípona nebo dotfile); „the /aid-ui studio“ už stránka plánu neodmítá.
- `commands/aid-plan.md` krok 10 jmenuje vykreslení stránky brainstormu před `approve`; krok 8a říká, že pořadí check/úprava/rebind nerozhoduje; readiness zná `--project-root`.
- Registr vynucení: devět nových řádků (590). Dokumentace Docusauru (`/aid/` aid-run, brainstorming, critic; mapa portů G-008) je v repu docs, commit 7c8450c.

## [2.113.0] — 2026-09-30

Pět pastí z projektu agents (P010 na 2.111.0), každá zavřená mechanismem, ne větou v návodu.

### Added
- **`close … --at <sha>`** — kolo kontroly kroku nebo EPICu, jehož nález controller opravil DŘÍV, než kolo zavřel, se zavře nad revizí, kterou revizoři viděli (jen otisk zapsaný v kole a jen dokud z něj HEAD vychází); oprava jde do potvrzovacího kola. Odmítnutí „head moved“ říká přesně tento příkaz. Dvakrát za den byla jediná cesta zakázaný `git reset --hard`.
- **`retry` pro platnou odpověď bez bracketu** — odpověď, kterou nikdo nedispatchnul (chybí start/complete), nemá původ, takže „zaplaceno jednou“ neplatí a role se rozešle znovu i s bracketem; `prepare` vypíše hotové příkazy bracketu pro každou roli, aby se kopírovaly a ne skládaly (a nikdy nedopisovaly po odpovědi).
- **`fix-check --also-steps N --reason "…"`** — následná úprava v kroku, který nález nejmenoval (krok B opakuje hodnotu, kterou oprava kroku A změnila), se přizná s důvodem; zapíše se do `fix-diff.json` a packet dalšího kola ji jmenuje. Bez důvodu odmítnuto; úprava mimo oba seznamy dál odmítnuta.
- **Kontrola dvojí kopie** — soubor pod `.aid-o` (plán, `aid-plugin-issues.md`), který existuje v hlavním checkoutu i ve worktree plánu s jiným obsahem, odmítne `prepare` a jmenuje obě cesty i tu novější (`aid_dotaid_twin_check` v `lib/aid-roots.sh`).
- **Nálezy lintu v packetu CP1** — každý prompt kontroly plánu nese oddíl „Plan lint“ s nálezy lintu, takže upozornění u plánu bez `lifecycle_strict` (P009: standard odvozený mapou, který plán necituje) dojde revizorům; generalist_a se na necitovaný standard ptá; příklad frontmatter v `plan-writing.md` nese `lifecycle_strict: true`.

### Fixed
- **Regrese 2.112.0 v testech**: dvě fixtures plánu (`multi-phase-plan*.md`, používá je deset sad včetně generačního řetězce z worktree) měly role architect a domain, které 2.112.0 odstranilo; jsou backend a dva vložené `sed` se klíčují na nadpis kroku místo na roli.

## [2.112.0] — 2026-09-30

Nezávislý kritik, Sonnet na psaní kódu, úklid karet agentů a měření toho, co revizoři dostávají (P107). Podnět PM 30. 9.: plány se při kontrole vždy zvětší (1 040 vážných nálezů CP1 za 33 kol, žádný neubírá), agenti navrhují testy „na kdejakou věc“ (+121 za 6 dní), a Sonnet 5.5 stačí na kód, ne na rozhodování a návrh UI.

### Added
- **Kritik ve dvou úrovních** (`skills/critic.md`, `lib/aid-critic.sh`) — na konci brainstormu nad návrhem a před CP1 nad plánem, vždy před Codexem. Prompt skládá kód z interim (`## Zadání PM` doslova, `## Účel a co je v sázce`; ceny se vypouštějí; „předpokládej, že se to staví“). Úroveň 1 = co opravit (autor každou výtku písemně přijme s tím, kde ověřil, nebo odmítne s důvodem); úroveň 2 = námět PM k rozsahu, nikdy verdikt „nestavět“. `aid_critic_check` odmítne odpověď bez obou nadpisů, s víc než pěti body, s verdiktem, nebo bez odpovědi na každý bod; odpověď se váže otiskem na plán i na kontrolu. Bez brány: CP1 jen ukáže, když kontrola neproběhla. Fokusy `critic-brainstorm|plan` v `aid-emit-dispatch.sh`. Interim se maže až po bráně CP1.
- **Otázka „co z plánu vypustit“ u každé role CP1** — major, když krok nebo odrážka jde vypustit bez ztráty akceptačního bodu (oprava = smazání). `enforcement_tests` chce jeden test na mechanismus a nehlásí test, který plán v `critic-response.md` odmítl s důvodem; odpověď kritikovi je součást packetu CP1 (jen s prošlou kontrolou) a jde citovat jako `critic-response.md:řádek`.
- **Značka ověřovacího testu** — `Test:` odrážka s „verification-only, delete before plan-final“ (ověřovací, smazat před koncem plánu) jmenuje jednorázovou kontrolu předpokladu; lint ji odmítne na jiném slovese, `plan-finalize --stage gates` odmítne kandidáta, kde soubor ještě existuje.
- **Role `docs`** (13 kroků ji v plánech používalo a generování je odmítalo); `docs-writer` zůstává jako starší zápis.
- **`aid-prompt-inventory.sh`** — za každou roli a kolo řádky promptu po oddílech a kolik nálezů který oddíl cituje (citace čte stejnou gramatikou jako rozhodčí). První zpráva `docs/plans/prompt-inventory-2026-10.md`; jen měří, škrty rozhodne PM (IMP-679).

### Changed
- **Sonnet na psaní kódu**: karty implementer (`sonnet`/`high`), implementer-light (`sonnet`/`medium`), gate-fixer (`sonnet`/`medium`); sedm rolí kroků říká `sonnet`; revizoři, reviewer-light a project-scanner zůstávají Opus. `Effort:` na kartě role jen volí lehkou/plnou kartu, rozpočet přemýšlení je `effort:` v hlavičce karty agenta. Návrh UI (`/aid-ui`, brainstorm) dělá session na Fable (`/model fable`); vývoj UI podle plánu na Sonnetu s prahem návratu (`docs/plans/P107-model-measurement.md`, výchozí hodnoty z P102/P103).
- **Pokyn opraváři** „test příkladu plus dvě varianty“ → „jeden test na pravidlo, druhý jen jinou cestou kódu“ (32 ze 125 testů od 2.107.0 vzniklo z něj); revizor kroku hlásí chybějící test jako major jen s jmenovaným akceptačním bodem, test bez bodu a chyby jako minor ke smazání.
- **Revizor EPICu** převzal simplifier: otázky 7–9 (duplicita napříč kroky, abstrakce s jedním volajícím, co vypustit nebo odložit); major když by diff byl materiálně kratší, strukturální změna jde do backlogu.
- **Karty agentů** přepsány do tvaru úkol / vstupy / výstup / pravidla s důvody (implementer, implementer-light, reviewer-light, gate-fixer, project-scanner 1 106 → 113 řádků); PM schválil rozpis změn pravidel (`docs/plans/P107-cards-rule-diff.md`). Paměťový sken projekt-scanneru přesunut beze změny do `reference/memory-scan-protocol.md` (IMP-682).
- Brainstorm: validace po oddílech (`section-review`, `cross-section-review`) nahrazena jedním během kritika; interim nese `## Zadání PM` a `## Účel a co je v sázce` (RULE 1a), rozpracovaný plán čekající na CP1 se neobnovuje jako brainstorm (RULE 6).

### Removed
- Karty **auditor**, **verifier** (šest čoček) a **simplifier**, příkaz **`/aid-audit`** (1 běh za historii), role **architect, domain, observability** (0 plánů), tři VULCAN overlaye — včetně odkazů v návodech, testech a registru (řádky `removed_scoped` s nástupci v `reference/review-successors.md`). `test-agent-cards.bats` hlídá hlavičky pěti zbylých karet.

## [2.111.0] — 2026-09-28

Opravy z běhu P103, kde automatický režim PM neustále zastavoval. Příčiny: lehcí revizoři četli jen zlomek dlouhého zadání a díry se našly až pozdě, session jela na starších kartách agentů, stálý pokyn PM „neptej se“ nešel zapsat a každý nález po posledním kole znamenal novou kartu.

### Added
- **Stálý pokyn PM pro plán** — `aid-review-round.sh standing --checkpoint cp2|cp3 --evidence-dir <run> --reason "<slova PM>"` se zapíše jednou na plán a dovolí každé revizi kroku i EPICu dvě kola „oprav a potvrď“ po vyčerpání rozpočtu, než se cokoli předá PM. Kolo, které znovu otevře tytéž nálezy, se odmítne (rozhodne PM). Kola pod pokynem nesou `standing: true`.
- **Upozornění na starou verzi pluginu** — háky při startu session a u každého promptu porovnají načtenou verzi s nainstalovanou a řeknou „spusť /reload-plugins“ (P103 jel na kartách 2.108.0 při nainstalované 2.109.0, opravář tak neznal pravidlo „oprav celou třídu“).

### Changed
- **Dlouhé zadání dostane plného revizora** — role s nízkým úsilím jde na `reviewer-light` jen do `light_max_prompt_lines` řádků zadání (výchozí 800), nad tím na `general-purpose`. Lehký revizor v P102/P103 přečetl kolem čtvrtiny a vrátil „bez nálezů“; plný četl celé.

### Fixed
- **Čekání na agenta na pozadí** — háky uznají `AID-WAIT` i u agenta spuštěného na pozadí bez výslovného příznaku.
- **Citace nálezu v akceptačním kritériu** — vyvážená fráze v apostrofech už není „fragment“ (dvě kontroly AID si odporovaly).
- **Balíček revize kroku** neuvádí úroveň testu z doby psaní plánu; platí hlavička sady.
- **Dokončení EPICu** nechce rozhodnutí u nálezu CP3, který revize sama uzavřela (opraven a potvrzen, nebo zamítnut PM).
- **Výpadek kontroly oprávnění Claude Code** — automatický běh počká a zopakuje příkaz (až 5×), místo aby zastavil kartou.

## [2.110.0] — 2026-09-28

Opravy z běhu agents P009. Hlavní: v projektech, které verzují stav plánů (acta, agents, wan), četla každá pracovní kopie plánu a EPICu nastavení ze své vlastní kopie větve místo z hlavního checkoutu. Změna nastavení během plánu se proto neprojevila; v P009 kvůli tomu neběžel bezpečnostní revizor kroku ani jednou (0 ze 7 kroků).

### Fixed
- **Pracovní kopie čte nastavení a evidenci z hlavního checkoutu.** Výjimka pro testovací projekty („adresář s vlastním `.aid-o/work/plan-state` je kořen sám sobě“) platila i pro pracovní kopie, protože acta, agents a wan mají `plan-state` ve verzování. Nově neplatí pro pracovní kopii (rozpozná se podle gitu); vnořené testovací adresáře ji mají dál. Týká se revize kroku a EPICu, kontroly kroku, revizního profilu, závazků a přesměrovaných nálezů.
- **Stránka plánu, brána kontroly plánu, evidence kola kontroly plánu a časová osa plánu** čtou a zapisují do hlavního checkoutu i pro plán otevřený z pracovní kopie. Stránka vykreslená z pracovní kopie už netvrdí „Revize plánu: ještě neproběhla“.
- **Stránka PM zastaralá jen kvůli času souboru.** Stránka si zapisuje otisk obsahu plánu (`<!-- aid-plan-sha256: … -->`) a kontrola porovnává otisky; čas souboru rozhoduje jen u starších stránek bez otisku. Checkout do nové pracovní kopie už generování nezastaví.
- **`amend-scope` po posledním kroku** řekne, který krok rozšířil („widening step N (id)“), a návod to popisuje.
- **Soubor z jiného repozitáře:** `aid-plan-lint.sh` hlásí absolutní cestu, kterou krok zmiňuje jen v textu a nemá ji v `Files:`; commit kroku u cizího souboru jmenuje repozitář, kam patří; pravidlo je v `pipeline.md`, `plan-writing.md` a `aid-run.md`.

## [2.109.0] — 2026-09-27

Méně kol revize tím, že se chyby opravují u zdroje. Rozbor P097, P101 a P102 našel 14 vážných nálezů až ve 2. a dalším kole. 12 z nich bylo bezpečnostních a 11 z 14 byla jen další varianta díry, kterou předchozí oprava ucpala pouze v hlášeném místě. Pokyn opraváři totiž zakazoval sáhnout na cokoli, co nález výslovně nejmenoval.

### Changed
- **Opravář opravuje pravidlo, ne příklad.** Vážný nález (blocker, major) nově nese pole `rule`: pravidlo, které porušuje, formulované tak, aby šlo zkontrolovat všude. Opravář ho opraví ve všech místech, kde může selhat, a to u kořene (seznam povoleného místo zakázaného, jedna kontrola, kterou projdou všechny cesty). Přidá test na příklad revizora a na další dvě varianty. Týká se všech šesti kopií pokynu: `agents/implementer.md`, `agents/implementer-light.md`, adaptér revize, `aid-run.md` (dvakrát: kroky a EPICy mají jeden společný blok, druhý je pro konec plánu) a `aid-plan.md`.
- **Potvrzovací kolo kontroluje pravidlo všude, ne jen citovaný řádek.** Varianta, kterou oprava minula, se vrací jako tentýž nález: stejné tvrzení, stejná první citace a za ní citace varianty. Pravidlo se přenáší do `merged.json`, do výpisu otevřených nálezů i do kontroly konce plánu.
- **Nález bez pravidla jde jednou zpět revizorovi.** Týká se CP2, CP3, CP6 a CP7, ne CP1. Jde to stejným jediným dotazem jako kontrola formy; druhá odpověď bez pravidla se přijme tak, jak je. Pole `rule` a pokyn k němu jsou přímo v zadání každého revizora (`review-prompt-v1.md`). Pole  a pokyn k němu jsou přímo v zadání každého revizora ().
- **Bezpečnostní revizor kontroluje každý revidovaný krok, se středním úsilím.** Dřív se zapínal jen při shodě se seznamem vzorů a dostaly ho 4 kroky z 16. Seznam nepozná webový server, cestu od volajícího ani text vykreslený jako HTML nebo SVG. Střední úsilí znamená, že místo agenta `reviewer-light` běží `general-purpose`. Odhad ceny: asi 12 běhů revizora navíc na plán velikosti P102, proti 5 kolům revize EPICu navíc (3 revizoři a opravář v každém). **Projekty s vlastním blokem `step_review`** (agents) to dostanou až po odebrání `when:` u `step_security`.
- **Implementér nejdřív napíše hranici důvěry.** Nový oddíl „Input from outside“ v `agents/implementer*.md`: co přichází zvenku, seznam povoleného, cesta se kontroluje až po převedení na skutečnou cestu, testy s nepřátelskými variantami.
- **Každé zadání revize začíná svou délkou a pokynem dočíst ho do konce.** Délka se zapisuje do `round.json` jako `prompt_lines`. V P102 mělo 66 ze 155 zadání přes 760 řádků a revizor EPICu přečetl „začátek a konec“ z 1780.

### Fixed
- **Stránka uzávěrky už netvrdí „hotovo“ před sloučením.** Počet hlášení počítá i nadpisy s datem a při nule vypíše jedno číslo místo „0 0“.
- **Prázdné `measurement.json`, když opravář neznal počet tokenů** (11 ze 140). Soubor se teď zapisuje najednou (atomicky).
- **Spouštěč bran už neumře potichu**, když výstup vybírání testů nejmenuje cestu.
- **Zápisy životního cyklu nesou `No-Release: AID lifecycle bookkeeping`**, takže je kontrola vydání před pushem neodmítne.
- **`dir/` v povolených cestách znamená adresář.** Dřív nezahrnul nic (4 ze 125 kontrol kroků falešně hlásily soubor mimo rozsah). Kontrola rozsahu `scope-check.sh` teď používá tentýž společný porovnávač.
- **`epic-complete` a sloučení EPICu vyžadují `done_phase: release`.** Samotný stav DONE nestačí; P102 sloučil EPIC, jehož přechod do fáze vydání selhal.
- **IMP-657: běh s `--auto` se zapíše jako automatický** i tehdy, když proměnná prostředí nedorazí. Všechna tři místa, která to zapisují, čtou stejnou funkci `aid_auto_run_declared`: proměnnou prostředí nebo `auto-mode-state.yaml`, přičemž zastavení od PM má přednost. Aby stav „auto“ nepřežil konec běhu, `--auto` teď jako poslední krok zapíše `auto-mode set manual`. Předtím by se další obyčejný `/aid-run` četl jako automatický. Aby stav „auto“ nepřežil konec běhu,  teď jako poslední krok zapíše . Předtím by se další obyčejný  četl jako automatický.

### Not in this release
- **Přenesené nálezy (obligations) se pořád samy neodškrtnou.** Rozbor ukázal, že navržená oprava by nikdy nezabrala: nález kroku N žádné pozdější kolo nekontroluje. Čeká na rozhodnutí PM.
- **Zpětný dotaz revizora na nedočtené zadání** se nepostavil. Revizor by jen napsal číslo řádku, takže by nic nedokazoval, a každý dotaz by znamenal nové spuštění celého zadání. Postavila se jen délka v zadání a `prompt_lines`.

## [2.108.0] — 2026-09-25

### Added
- **`/aid-ui` umí vizi a slogany (1v)** — otázky podle šablony vize, `vize.md` a pět sloganů; PM vybírá na stránce companionu, volbu bere jen `await-choice --kind slogan`.
- **Identita a balíček značky (1i)** — tři SVG koncepty loga, volba PM, pak ikony přes Playwright MCP (`brand-icons.js`) a `aid-ui-ico.py` (SVG jen přes allowlist).
- **SEO (1s a krok 6)** — SEO brief se seznamem stránek, který PM potvrdí; krok 6 pustí na hotovou stavbu `aid-ui-seo-check.py`.
- **Obrázkové komposice pod bránou PM** — cesta stavby, volba komposice a útrata za obrázky se zapisují; nic se nevybere bez PM.
- **Volby na kroku 0** — vize, identita, SEO a obrázky, každá s doporučením podle toho, co projekt už má; reference aplikací se berou ze stránek obchodů.

### Fixed
- **IMP-663: stránka značky má skutečné kapitoly** — těla kapitol jdou přes `body` s allowlistem, stav je mimo servírovanou složku (`docs/design/brand-state.json`), tok končí přes `finish`, stránka načte písma projektu a deset textových vad je opraveno.
- **Mobbin nahrazen**, patra testů přeznačena a sada ledgeru už nevidí prostředí brány.

## [2.107.1] — 2026-09-25

### Fixed
- **Administrativní uzavření ručně sloučeného plánu vydá potvrzenku.** Skutečný plán AID má zapsaný manifest životního cyklu. Ruční sloučení v něm žádnou dodávku nezapíše, takže uzavření dřív skončilo „active" a každý plán, který na něm závisí, se nedal spustit (P101 → P102, totéž P097). Když git prokáže, že větev plánu je v cílové větvi, potvrzenka označí každý EPIC bez přijaté revize `verdict: administrative` a výjimku uvede jen odkazem (hash sloučení a záznamu). Důvod od PM se nově ukládá do `plan-close-administrative.json`; dřív se jen vypsal. Plán, který sloučený není, dostane uzavření bez potvrzenky, nic se nepředstírá.
- **Výpis „co se nepotvrdilo" se už neusekne u prvního písmene „n"** (`[^\n]` v `grep -E`).

## [2.107.0] — 2026-09-24

### Added
- **Tabulka „When AID refuses"** — `skills/pipeline.md` má řádek pro každý důvod odmítnutí, na který agenti za poslední měsíc narazili (`tests/fixtures/refusals/measured-2026-09.tsv`): co znamená, zda je chybná práce nebo se posunul stav, příkaz, který pokračuje, a zda jde o rozhodnutí PM; nahrazuje starou „force_override Usage Policy" a test hlídá, aby tabulka a kód neodjely.
- **Spor o nález kroku i EPICu jde k PM** — `aid-review-round.sh dispute` funguje i na CP2/CP3; nález ve sporu blokuje dál a uvolní ho jen `--pm accepted` s kartou Rozhodnutí, která nález cituje, a s odpovědí PM zapsanou v auditu hooků po té kartě.
- **Administrativní uzavření plánu odkudkoli** — `plan-close --administrative --reason` uzavře plán sloučený mimo `plan-finalize` z libovolného otevřeného stavu (P097 stál v `PLAN_GATES`); dosud neprošlo ani vlastní kontrolou argumentů, takže nikdy nefungovalo.
- **Kontrola plánu pozná řádky EPIC, které start plánu odmítne** — `aid-plan-lint.sh` čte řádky `**EPIC N: …**` stejným parserem, jakým start plánu zapisuje manifest (plán bez nich, `**EPIC 1**` bez dvojtečky, číslování mimo 1..K); dřív plán prošel revizí i generováním a spadl až při startu s holým „rc=2", teď start i řekne proč. Návod k psaní plánu (`skills/plan-writing.md` §Phase Markers) už netvrdí, že jednofázový plán řádek nepotřebuje; parser přeskakuje ukázky v bloku kódu jako generátor.
- **Rozhodnutí PM ke sloučení zapíše příkaz** — `aid-plan-fsm.sh plan-record-decision <plan> MERGE|FIX|ABORT --by pm` uloží rozhodnutí ve tvaru, který sloučení přijme, do adresáře pokusu; karta uzávěrky ho uvádí před `plan-merge-to-main`. Dřív karta radila soubor, který sloučení odmítlo, a rozhodnutí se skládalo ručně podle schématu.
- **Kontrola kroku přes další repozitáře** — krok, který mění soubory v jiném deklarovaném repozitáři, vrací jejich rozsah (`repo_commits`) a kontrola kroku ho reviduje; repozitář bez vráceného rozsahu je nález, ne přeskočení.

### Changed
- **Každé odmítnutí, na které agenti narazili, končí řádkem `next:`** — příkaz se skutečnými cestami běhu, který pokračuje, a odkaz na řádek tabulky; `--force` jmenují jen řádky, kde jde o rozhodnutí PM.
- **Revizní kolo není slepá ulička** — krok, který se posune po prošlém kole, potvrdí delta kolo nad novými commity (nepočítá se do `rounds_default`, nechce override); kontrola kroku po uzavřeném kole už nevrátí „skip", který by nešel zapsat.
- **Nález vadný jen formou se neztratí** — rozhodčí ho nechá v seznamu jako `form_invalid` a verdikt kroku ho počítá jako otevřený.
- **Autor plánu pouští kontrolu, kterou pouští generování** — `/aid-plan` volá `aid-generation-readiness.sh`, která proběhne celá a vypíše všechny nálezy najednou; pravidlo patra nové sady je jedna funkce (`lib/aid-scoping.sh`), kterou volá lint i generátor.
- **Obnovení napůl dodaného plánu negeneruje dodané EPICy** — fáze, jejíž sloučení git prokáže, se zapíše jako `delivered` a znovu se negeneruje ani nezařazuje; prázdná generační transakce se po opravě plánu sama odloží se třemi auditními záznamy.
- **Rozsah pokrývá, co kroky legitimně dělají** — backlog a hlášení pro AID jdou commitnout vždy; `amend-scope` funguje i po posledním kroku a pro absolutní cesty, které plán deklaruje; návrat kroku umí deklarovat smazaný soubor.
- **Kandidát plánu se posuzuje tam, kde žije** — jeden resolver zaznamenaného worktree (`aid_plan_recorded_worktree`) místo tří kopií; čerstvost rozhodnutí v briefu PM, adresář evidence v `aid-plan-diff.sh` a `plan_path` ve stavu běhu vycházejí z něj, commit kroku jde jen na větev jeho EPICu a agent kroku větve nepřepíná.
- **Konec plánu převezme brány z běhu EPICu na stejném stromu** — brána s tokenem běhu (`{base_commit}` …) běží vždy znovu; běh bran, který spadl před reportem, už plán nezablokuje navždy.
- **Vizuální společník má dveře** — brainstorming s tématem pro uživatele říká, zda jde o obrazovku, a obrazovka se navrhuje z podkladu postaveného z aplikace; výjimka PM se zapíše i s důvodem, který stránka ukáže.
- **Uzavření plánu uklidí** — stromy a větve kroků, které sloučení obsahuje, a pracovní stromy brainstormingu a generování; co zůstalo, je jmenované v `cleanup.json`. Audit hooků se rotuje po 20 MB a časy plánu se přes rotaci čtou celé, nebo „neměřeno".
- **Konec tahu blokuje jen krok, který session sama spustila** — pravidlo `turn_step_open` pozná krok session podle hlavičky `Dispatch Contract (version …)` v jejím přepisu, ne podle času; dvě souběžné session v jednom projektu (tady P100 a P101) už jedna druhé konec tahu neodmítají.
- **Kontrola kroku hodnotí strom, ve kterém běh je** — `aid-step-check.sh` a `aid-review-round.sh` (cp2/cp3) bez `--project-root` diffují worktree, kde je vyzvednutá větev běhu, ne kopii, ze které je kontroler spustil (P101: kontrola z hlavní kopie zapsala „beze změn" a krok prošel bez revize); nastavení revize čtou z hlavní kopie a `increment-step` se přesměruje do worktree plánu jako ostatní přechody.
- **Revize plánu se ptá na pořadí za běhu a na převzaté předpoklady** — role `feasibility_deps` má dvě otázky navíc: kdy za běhu vzniká soubor, který krok čte, a zda je předpoklad převzatý z hlášení nebo backlogu ověřený příkazem v dnešním kódu.
- **Výpisy revize říkají, co se stalo** — kolo kontroly plánu hlásí „valid; open blockers: N" místo „pass"; řádek souhrnu hned za počtem kol uvede „codex→claude N×", když za Codex odpovídal Claude; revizor vidí číslo kroku z plánu (index v závorce); nález, který PM zamítl (`--pm accepted`), je ve výpisu i v `semantic-review-final.json` „dismissed by the PM", ne „fixed", a nepočítá se revizorovi jako opravený.
- **Revizor už nedostává falešné „zápis mimo rozsah"** — odpověď zapsaná do adresáře revizního kola (`evidence/…/cp2|cp3|cp6|cp7/…`) není zápis kroku.
- **Změna registru vynucení vybere 12 sad, ne celou sadu testů** — `aid-select-tests.sh` mapuje `defaults/enforcement-registry.yaml` na sady, které ho čtou.
- **Runner řekne, které testy spadly** — u červené sady vypíše každé `not ok` s pěti řádky pod ním (jinak konec výstupu), i bez `--verbose`.
- **`AID-WAIT:` platí i pro agenta na pozadí** — autonomní běh smí skončit tah, dokud agent nebo příkaz spuštěný na pozadí neohlásil konec.

### Fixed
- **Konec plánu kontroluje čistotu stromu plánu, ne hlavní kopie** — rozdělaná práce jiného okna v hlavní kopii už nezablokuje verdikt READY (poslední kus důvodu, proč P097, P099 a P101 končily ručně); totéž platí pro posouzení, zda se kandidát od revize změnil.
- **Čísla IMP přiděluje AID** — `aid-fsm.sh alloc imp-id` se zámkem, za nejvyšším číslem, které backlog už uvádí (ručně vybraná čísla se ve dvou oknech srazila třikrát); kontrola plánu B6 u citovaného IMP už nevaruje.
- **Spadlá brána na konci plánu jmenuje, co spadlo, a jak to zopakovat samostatně** (u testů i konkrétní sady).
- **`done-advance` přesune soubor EPICu do archivu sám**, až když ostatní podmínky projdou; zmizelo varování „review_profile unverifiable" u každého EPICu a rada smazat report bran, který neexistuje.
- **Bezpečnostní vzor `skipped_test` už nechytá `sys.exit(`**, kontrola plánu B3 nehlásí mazání souboru, který plán sám zakládá.
- **CONTRIBUTING: pořadí vydání, které pre-push pustí** (lokální značka → push main → ověření nainstalovaného pluginu → push značky → GitHub release s poznámkami z CHANGELOGu); hlášení pro AID se zapisují jedním blokem.
- **Upgrade `/aid-init` nezúží bránu EPICu** — starý `gate_profile_defaults.epic` (např. `full`) se přenese do `default_profile`; dřív se z něj stal `standard` a brána EPICu v agents prošla bez testů projektu (ACTA by na to narazila při dalším upgradu).
- **Po uzavření plánu zůstane index hlavní kopie čistý** — potvrzenka, která už leží na disku, se převezme; dřív se ukazovala jako smazaná a zároveň nová a další commit v main by ji tiše smazal.
- **Commit kroku nevynechá soubor potichu** — soubor, který projekt ignoruje (`docs/`), se commitne; soubor z jiného repozitáře se jmenuje s pokynem k `repo_commits`.
- **Nález přesunutý do backlogu už neblokuje EPIC** — platí poslední trasa nebo uzavření nálezu.
- **Konec plánu řekne, na které kontrole spadl** (např. `git_clean: …`); zámky v `.aid-o/config/*.lock` nejsou nepořádek ve stromu.
- **`prepare-plan --bump auto` se u plánu zeptá** místo tichého „žádné vydání": commity kroků nemají typ, ze kterého by šlo číslo odvodit. Návod k plánu: poslední krok píše obsah vydání, ne čísla verzí.
- **Brány spuštěné bez `--profile` to řeknou** a jmenují tabulku profilů (P101 tak běžel přes 20 min všechno); `aid-run.md` uvádí jako kanonickou cestu `advance-to-gates`.
- **Háček konce tahu přijme kartu podle `/opt/eco/CLAUDE.md`** (Rozhodnutí N, možnosti A/B, Doporučuju), ne jen kartu AIDu; falešné „mimo rozsah" u nové složky ve worktree zmizelo.
- **Drobnosti:** řádek zástupu za Codex uvádí focus; vzor `plan_diff` nerozlišuje velikost písmen; `run-all-tests.sh --only` bere název i bez přípony; test revizního kola kazí jen kopii schématu, nikdy strom pluginu.
- **Pre-push pozná `chore(release):`** — v projektu bez nastaveného verzování uzavře rozsah i commit ve tvaru conventional commits; `fix(release):` zůstává oprava.
- **Časy z auditu už neujíždějí o hodinu** — `jq` starší než 1.7 čte čas se `Z` v místním pásmu; výpočet času plánu (čekání na PM do „teď") a počet odmítnutí pro připomínku hlášení pro AID ho teď počítají v UTC, jako to FSM dělá od P037.

**Poznámka pro projekty:** commit hook se aktualizuje dalším `/aid-init`. `scripts/` pluginu má 176 581 řádků (před P100, tedy ve 2.106.0: 174 931): +1 650, z toho +873 v testech a +777 v pravidlech výše; žádná nová sada testů.

## [2.106.0] — 2026-09-24

### Added
- **`/aid-ui` - návrh vzhledu mimo AID pipeline** - provede typem produktu, najde šest referencí z galerií, směr vzhledu vybírá PM přes Impeccable (nikdy bez něj), pak designový standard, stavba, ověření a brandová stránka v `docs/brand/`.
- **`aid-ui-state.sh`** - jediný zapisovatel stavu brandové stránky a brána směru: kroky 4-6 odmítnou běžet bez zaznamenané odpovědi PM ze stránky Impeccable.
- **`aid-ui-serve.sh`** - stránka rozhodnutí i brandová stránka jsou dostupné přes VPN; stránka rozhodnutí přes proxy, která přepisuje Host/Origin, protože Impeccable přijímá jen 127.0.0.1.
- **`aid-ui-design-to-css.sh`** - převede tokeny z `DESIGN.md` (barvy, písmo, zaoblení, mezery) na CSS proměnné brandové stránky.
- **Řádek `aid_ui_direction_needs_pm` v registru vynucení** - pravidlo „směr jen s PM" je hlídané kódem, ne jen textem.

## [2.105.2] — 2026-09-24

### Fixed
- **Noční běh celý zelený** — dodělána poslední sada `test-aid-plan-release-boundary.bats` (74 padajících případů). Testy dostaly to, co od P094/P097 vyžaduje každý přechod EPICu (uzavřené revizní kolo EPICu, `--run-id`, tabulku profilů v projektu, `profile_table` v reportu bran); smazány případy zrušených věcí (zpráva kurátora, `blocking_findings` z audit-reportu, rozdíl starého a plánového režimu v požadovaném profilu, text dvojice ověřovatelů CP3 v návodech).

## [2.105.1] — 2026-09-24

### Fixed
- **Noční přehled jmenuje každou padající sadu** — runner vypíše „Failed suites:" vždy, i když běh ukončí neparsovatelná nebo zkrácená sada; dřív skončil dřív a noční přehled slil 21 padajících sad do jedné položky „(runner)" čtyři noci po sobě.
- **Noční běh skoro zelený** — z 21 padajících sad jich 20 prochází (zbývá část `test-aid-plan-release-boundary.bats`: testy staré vydávací cesty EPICu, kterou P096/P097 odstranily; roztřídí se v další verzi) po P094–P099: většinou testy, které neznaly nová pravidla (`epic-start` vyžaduje `--run-id`, `increment-step` i s `--force` chce ověření kroku, krok potřebuje uzavřené revizní kolo, runner odmítne neznapisovatelnou evidenci předem), testy smazaných věcí (C4, časové řady bran, `c3_cross_provider_dispatch`, `test-invalidation-map`) a pomocná funkce `_seed_closable`, kterou P096 smazal, zatímco ji 58 případů volalo.
- **Závěrečná revize plánu čte i sekci `## Acceptance Criteria`** — šablona plánu ji má, výběr kritérií pro cp7 (P096) bral jen kritéria u kroků a `## Success Criteria`, takže plán psaný podle šablony s kritérii jen v této sekci `--stage produce` odmítl („no acceptance or success criteria").
- **`/aid-status` ukazuje cestu k hlášením pro AID stejně odkudkoli** — z worktree plánu dřív absolutní cestu.
- **`release_quarantine` = `release` bez `bats_all`** — profil nedostal `check_release_paths`, když ho dostal `release`.
- **Nové typy agentů z P099 (`implementer-light`, `reviewer-light`) jsou v inventáři instrukčních ploch.**

### Changed
- **Dvě jednorázová přijetí nejsou sady** — `test-gates-replay.sh` → `acceptance-gates-replay.sh`, `test-step-review-acceptance.sh` → `acceptance-step-review.sh`; runner je nespouští (noc je zabíjela časovým limitem a hlásila jako neparsovatelné).

## [2.105.0] — 2026-09-24

### Changed
- **Merge cesta zpět v normě** — T0 + T1 se znovu vejdou do 10 minut skutečného běhu (ekosystémový standard testů), z 42,5 minuty (23. 9.). Patra 91 sad jsou přeznačená podle nočních měření: připnuté jádro a nejlevnější stráže zůstávají před mergem, zbytek běží v noci.
- **Kontrola pater hlídá součet** — `aid-test-tier-lint.sh` odmítne T0 nad 90 s a T1 nad 390 s naměřeného součtu (rozpočty v `lib/aid-test-tier.sh`, rezerva na režii runneru). Každá sada byla levná sama o sobě, zatímco merge cesta za měsíc narostla ze 17 na 42 minut, protože součet nikdo nehlídal. Brána `tier_lint` tohoto repa čte noční deník měření (místní se zastavil 14. 8.).
- **Jádro merge cesty** — `scripts/tests/tier-core.txt`: sady, které rozpočet nikdy nepošle do nočního běhu (stavový automat EPICu, brána revizí plánu, stav revizního kola, kontrola kroku, zadání agenta, pokračování fronty). Velký test revizních kol běží v noci.
- **Hlídač pater najde testovaný soubor i s předponou `aid-`** — dřív poslal 201 z 238 sad do T2 jen kvůli názvu.
- **Kontrola i hlídač pater čtou deník jednou** — 84 s → 19 s.
- **Skládání promptu revizora** — ~10 procesů místo ~30, výstup bajt po bajtu stejný; příprava revizního kola 3,6 s → 2,4 s. Chybové cesty skládání mají test.

### Fixed
- **Dvě sady červené v nočním běhu** — `test-generation-finalize.sh` (vzorový plán bez polí přísného režimu, bez souborů v repu a bez revize) a `test-selector-honesty-check.bats` (výběr testů je mimo repo pluginu vypnutý, test ho nepřepnul).

## [2.104.1] — 2026-09-24

### Changed
- **Codex revizor na `gpt-6-sol`, effort `medium`** (rozhodnutí PM) — `gpt-6-sol` jde od Codex CLI 0.156 i přes ChatGPT účet; AID si bere nejnovější instalaci Codexu sám. Na jednom balíku našel 1 ze 4 blokerů `gpt-5.6-terra` high, proto se na prvních pěti živých kolech porovná s terrou na stejném promptu (`docs/plans/P099-codex-model-check.md`). Cena `gpt-6-sol` je v `prices.yaml`.
- **Stránka plánu přijde až po revizích** — `/aid-plan` ji vykreslí a zveřejní, až plán projde branou kontroly plánu (`aid-cp1-gate.sh`), ne hned po napsání; PM čte plán jednou, kompletní. Hlídač stránek (`milestone_artifact_rendered`) stránku do té doby nechce.

## [2.104.0] — 2026-09-24

### Changed
- **Druhý revizor (Codex) odpovídá** — prompt jde do Codexu na stdin (argument padal na limitu délky příkazu u 189 kB CP1), odpověď bere AID z poslední zprávy a každé kolo bez odpovědi (chyba, žádný soubor, timeout, limit) automaticky dostane Claude zástupce; roli se zástupcem už `dispatch` znovu Codexu neplatí. Sonda Codexu se ptá modelu, na kterém role opravdu poběží. Model zůstává `gpt-5.6-terra` s effortem `high`: `gpt-6-sol` ChatGPT účet odmítá a `gpt-5.6-sol` na stejném balíku minul jeden ze čtyř blokerů (`docs/plans/P099-codex-model-check.md`).
- **Opus všude, effort podle role** — všichni agenti a Claude revizoři běží na Opus; bývalé Sonnet role s effortem `low` přes dva nové typy agentů (`implementer-light`, `reviewer-light`). Effort je v datech (`review-checkpoints.yaml` → `effort`, karta role → `**Effort:**`); `prepare` vypíše ke každé roli typ agenta a model. Karta role a pravidlo „nejmenší kód" jdou agentovi přímo v zadání (dispatch contract), s cestou k pluginu — v cizím projektu relativní cesta neexistovala.
- **Telegram jen dvakrát** — „agent stojí a čeká na tebe" (jednou za zastavení, i přes víc oken; tvoje odpověď ho znovu nabije) a „plán dodán" (jednou za plán, vynucené uzavření to řekne). Čtyři upozornění FSM a noční zpráva jsou pryč, události zůstávají v timeline a v nočním artefaktu; `/aid-status` ukazuje u noční řádky i překročený rozpočet merge cesty.
- **Autonomní běh se sám nezastaví** — Stop hook vrací session, která plán řídí (`/aid-run --auto` ji naváže přes `plan-state --bind-session`), zpět do práce, dokud nepředá kartou Rozhodnutí/Zastaveno, nečeká na běžící bránu (`AID-WAIT:`) nebo nevyčerpá `autonomy.continuation_budget` (40, tvoje odpověď ho vrací). Pravidlo odmítá i pod `stop_hook_active` (nový klíč registru `blocks_when_active`), jeho vlastní chyba tah nikdy neblokuje. `aid-hook-verify.sh --status` hlásí prošlý verdikt kanárku jako neplatný a `/aid-run --auto` ho obnoví — blokující pravidla hooků byla od 24. 8. potichu vypnutá.
- **Souběžné kroky opravdu běží** — generátor EPICu psal do sloupce `Parallel Group` vždy `---`, takže žádná vlna se nikdy nerozběhla; teď nese vlnu z plánu. Strop souběhu čte projekt (`.aid-o/config/orchestration.yaml`, `/aid-init` zapíše 3, `/aid-setup parallel` mění), jinak výchozí plugin; souhrn konfigurace ho ukáže se zdrojem.
- **Stránka plánu** — krok má svůj název a pod ním celý cíl, počet kritérií končí u dalšího nadpisu (poslední krok nepřebírá kritéria celého plánu), role s číslicí (`e2e`) se čte celá.
- **Renderer stránek je rychlejší** — ~15 volání `jq` místo ~79 na stránku (4,0 s → 2,3 s), výstup beze změny.
- **Merge cesta** — `test-tier-ci-topology-guard` a `test-aid-nightly-report` jdou do T2, `test-dod-gate-profile-agreement` z T0 do T1; odhad ~35 min z 42,5. Cíl 20 min vyžaduje zrychlit revizní engine (`docs/plans/P099-merge-path-2026-09.md`).
- **Nástroj Artifact je v autonomním presetu oprávnění** — zveřejnění stránky nečeká na potvrzení.
- **Sběr hlášení z projektů jen vypisuje** — `bin/aid-plugin-issues-collect.sh` ukáže otevřené body s řádkem a nic nezapisuje; rozhodnutí se píše do souboru projektu.

### Added
- **Kam šel čas** — stránka dodaného plánu ukazuje práci, revize, brány, čekání na PM a výpadky (`aid_plan_close_time`, z revizních kol, časových os EPICů a auditu hooků mimo strom).

### Removed
- **Stránka EPICu a stránka selhaných bran** — PM čte dvě stránky na plán: plán k rozhodnutí a dodaný plán. Renderer EPIC stránky, jeho sada, profily `gates`/`epic_done` a skládání dlaždic jen pro bránu jsou pryč; brána vypisuje jen kartu.
- **Klíč `notifications.telegram.alert_on_compliance_recovery`** — `/aid-init` ho nepíše, upgrade konfigurace odstraní celý blok.
- **`docs/plans/plugin-issues-inbox.md`** (90 kopií, 0 rozhodnutí) — poslední roztřídění je v `docs/plans/plugin-issues-triage-2026-09-23.md`.

**Poznámka pro projekty:** `scripts/` pluginu má 173 927 řádků (před plánem 175 429). Projekt s vlastním `review-checkpoints.yaml` si drží své modely; nový klíč `effort` je volitelný. `/aid-run --auto` musí po `/clear` nebo v novém okně session znovu navázat (dělá to sám v PRE-FLIGHT).

## [2.103.0] — 2026-09-23

### Changed
- **Gate row je jedna smlouva (verze 2)** — `status`/`reason` z uzavřeného slovníku (`exit_0`, `exit_<n>`, `job_timeout`, `job_lost`, `job_cancelled`, `not_in_profile`, `missing_script`, `vacuous_pass`, `reused_from`, `legacy_row`) nahrazují starý `result`; `required`/`required_source` je na každém řádku. `result` zůstává jedno vydání jako kompatibilní pole (odvozené).
- **Profily jsou seřazené seznamy** — `gate_profiles` s `default_profile` a `when_paths` na `full`, řešené na jednom místě (`lib/aid-gate-profile-select.sh`); vyhrává poslední (nejširší) profil, jehož `when_paths` sedí na změněnou cestu.
- **Timeouty jsou pevné** — `timeout_seconds` se už neřídí živým baseline; `aid-gate-runtime-baseline.sh propose` jen navrhuje číslo z historie, nikdy nezapisuje.
- **Upgrade konfigurace** — `aid-init-execution-yaml.sh upgrade` (hash-confirmed, atomický rename) převede starý `required_when` na `required: true`; zvednutí timeoutu gate znovu spustí, ne že znovu vyzvedne starou úlohu.

### Removed
- **`services:` a servisní vrstva, `required_when` a jeho knihovna, klasifikátor rizika `lib/aid-gate-profile.sh`, baseline-řízené timeouty, třída zotavení `SERVICE_UNHEALTHY` a `restart_service_once`** — nahrazeny výše. Runner nově ODMÍTÁ `required_when`, `needs_services`, `services:` a `gate_profile_defaults` (exit 2) s příkazem na upgrade (`bash $AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh upgrade <project root>`).

**Poznámka pro projekty:** spustit upgrade jednou na projekt (náhled, pak `--confirm-upgrade <hash>`), jinak další běh brány starou konfiguraci odmítne. Replay ukázal, že reálné vydání ACTA (P019) bylo dřív uzavřeno jako zelené s padajícím e2e gate, protože "required" žilo jen v `required_when` — u toho projektu teď taková brána selže tam, kde dřív tiše procházela.

## [2.102.0] — 2026-09-21

### Removed
- **Audit testového portfolia (`/aid-audit-tests`, P072) je pryč** — příkaz, agent `test-portfolio-analyst`, pět promptů, sedm schémat, konfigurace `config/test-audit.yaml`, osm skriptů, osm knihoven a 24 sad testů (55 souborů, ≈15 700 řádků); jediný ostrý běh 5. 8. 2026 nedal návrh, který by PM přijal, a paralelismus, o kterém měl rozhodovat, odstranil P078. Zůstává, co čte merge cesta: katalog testů (`aid-test-inventory.sh` → `aid-test-catalog-approve.sh`), patra a jejich nástroje, výběr testů. Deset řádků registru je `removed_scoped`; `/aid-init` zakládá devět souborů místo deseti; `/aid-help tests` popisuje patra místo auditu.

## [2.101.3] — 2026-09-21

### Removed
- **Telegram bot `svc-mcp-tg-bot` a vše, co na něj ukazovalo** — zdroj služby (`services/mcp-tg-bot/`) je z repa pryč; služba přijala za 30 dní dvě zprávy (podle `docker logs` z 21. 9. před smazáním) a AID posílá od 26. 8. přes sdílenou `send_alert()` (`lib/aid-alert.sh`). Blok `notifications.telegram`, který `/aid-init` zapisuje, má už jen jediný klíč, který někdo čte (`alert_on_compliance_recovery`); `enabled`, `chat_id`, `alert_threshold` a `alert_on_repeated_precondition_fail` neměly čtenáře. Z výchozích oprávnění zmizel nástroj `mcp__svc-mcp-tg-bot__send_message`, z kontroly závislostí a README docker jako „nasazení bota".

## [2.101.2] — 2026-09-20

### Changed
- **Kokpit má vlastní složku** — celý node workspace (`packages/`, `package.json` + lock, `tsconfig`, `vitest`, `Dockerfile`, `docker-compose.yml`) se přestěhoval z kořene do `cockpit/`; CI joby a kalibrační skript ukazují na novou cestu, jméno compose projektu je připnuté, takže běžící kontejner zůstává tentýž.

### Fixed
- **Odkazy na standardy psaní ukazují na existující soubory** — `skill-writing.md` a `command-writing.md` citovaly audit z června 2026 na cestě `docs/plans/AID-audit-2026-06/`, která od přesunu do `docs/plans/archive/` neexistovala; opraveno na skutečné umístění.

### Removed
- **Zbytky v kořeni veřejného repa** — dva obrázky produktizace (1 MB) bez jediného čtenáře a `audit-watchdog.sh` (pojistka pro `/aid-audit-tests`, který se od 5. 8. 2026 nespouští) jsou smazané; záznamy vlastních běhů (`.aid-o/work/evidence/`, 174 souborů, a pět `interim-*.md`) už nejsou v gitu — repo tím začalo dodržovat pravidlo, které `/aid-init` dává každému projektu (běhové artefakty se neverzují); na disku zůstávají.
- **CHANGELOG je zase čitelný** — záznamy verzí 0.1.0 až 2.89.3 (530 kB z 610) jsou přesunuté beze změny do `CHANGELOG-archive.md`, živý soubor nese 2.90.0 a novější; obě kopie (kořen i plugin) stejně.
- **Soukromý kontext už není v public repu** — `CLAUDE.md` a `.claude/settings.json` (interní hosty, cesty, oprávnění) přestaly být sledované; `.gitignore` je jako soukromé označoval už dřív, jen se to nedodržovalo. Pravidla pro přispěvatele, která v `CLAUDE.md` bydlela (co aktualizovat při změně pluginu, registr osmi míst s verzí, postup vydání, testbed, patra testů, problémy z projektů), se přestěhovala do sledovaného `CONTRIBUTING.md`, na který teď ukazují tři řádky registru a oba skilly psaní. Historie gitu má vše dál, čištění historie PM odmítl.

## [2.101.1] — 2026-09-20

### Changed
- **Záznam porovnání plánu netvrdí „prošlo", když část kritérií přeskočil** — jakékoli přeskočené kritérium dá `overall_verdict: partial` (nic to neodmítá, jen záznam přestal lhát a revizor kritérií to vidí), kritérium bez řádku výsledku `fail`; příkaz kritéria má zavřený vstup, takže už nesní kritéria za sebou; dřív stačilo jediné ověřené kritérium a čtyři z devíti nepřečtených vyšly zeleně (nalezeno čtením celku na ACTA a WAN).
- **Brána, která skončí úspěchem nad ničím, neprojde** — `run_gate` zapíše `fail` s důvodem `vacuous_pass`, když výstup sám říká „0 files checked", „collected 0 items", „no tests ran" prázdný plán TAP nebo „[no test files]"; počet nula CHYB zůstává výsledkem a jakýkoli kladný počet ve výstupu podezření ruší.
- **Nález zahozený jen kvůli formě se jednou vrátí revizorovi** — `collect` takovou odpověď vypíše jako neplatnou s důvodem `form: <id> missing_evidence …` a jde běžnou cestou `retry`; kolo se bez té role neuzavře, ani když splní minimum odpovědí; druhá vadná odpověď se přijme a nález se zahodí jako dřív.
- **Přepínače revizí čte jedna funkce** — `aid_review_switched_off` v `lib/aid-review-config.sh` nahradila tři kopie téže smyčky v řídicím skriptu, rozhodnutí o vydání a načítání konfigurace; výchozí soubor se všude bere z `AID_PLUGIN_PATH`, když je nastavená.

### Removed
- **Přepínač `head_match_policy`** — nečetl ho žádný kód; vstup pořízený na jiném commitu (výsledky bran, kontrola plánu) rozhodnutí o vydání blokuje bezpodmínečně už dnes a řádek registru `c4_head_match_policy` to teď říká jako `active`.

## [2.101.0] — 2026-09-20

### ⚠️ Změna chování — přečti před upgradem

**Konec plánu má čtyři kroky místo šesti a čte ho jedno kolo tří revizorů.**
`plan-finalize --stage` zná `freeze`, `gates`, `produce` a `decide`; staré názvy
(`sync`, `inputs`, `review`, `c4`, `summary`, `accept-ancillary`) končí kódem 2
a jmenují nástupce. **Plán rozpracovaný ve starém uzavírání se zavře znovu od
`--stage freeze`**; doklad verze 1 se při uzavření odmítne s tímto příkazem.
Celé dodání čte jednou kolo `cp7` (role kritérií, tvrzení a celku), oprava
razí další pokus a znovu se platí jen to, čeho se dotkla: brána, jejíž vstupy
ani definice se nepohnuly, se zkopíruje, role bez nálezu a bez dotčených vstupů
se přenese. Každé odmítnutí končí řádkem `next:` s dalším příkazem.

**Reportér, kurátor, smlouva auditora pro konec plánu, CP4, CP5, brána dodávky
C1 a srovnávací běh rozhodnutí jsou pryč.** Nález revize opravuje role, která
kód psala, a potvrzuje ho další kolo; stránku pro PM počítá `aid-pm-brief.sh`
a ukazuje pokusy, minuty a cenu uzavření. `plan-close` už nečeká na
`<plán>-delivery.md`. Klíče `reporter:`, `simplifier:`, `curator_auto_rules:`
a `cp4_production_paths:` v `execution.yaml` a přepínače `cp4_curator_validation`,
`cp5_critical_gate`, `simplifier_pass`, `delivery_report` už nic nečte — smějí
zůstat, jen nic nedělají. Volitelná kontrola CI `plan-boundary-required-check.yml`
hlídala soubory reportéra; v projektu ji smažte.

### Added
- **Kolo `cp7` — čtení celého plánu** — tři role (`final_criteria` na Opusu, `final_claims`, `final_generalist` na Codexu se zapsaným zástupem) čtou `plan_base..kandidát` jednou před rozhodnutím; přepínač `cp7_plan_final_review` se čte ze základny plánu, takže ho plán sám nevypne, a vypnuté kolo blokuje, dokud ho PM pro daného kandidáta nevzdá (`decide --waive-final-review --reason`).
- **Znovupoužití výsledků mezi pokusy** — `freeze` zapíše `fix-class.json` (co se změnilo a které vstupy revizí to zneplatňuje) a `gates` zkopíruje řádky bran s nezměněnými vstupy i definicí s poli `reused_from` a `reused_candidate`.
- **Záznam zápisů kroků** — `stage-writes.jsonl` drží otisk každého souboru, který krok napsal; vstup rozhodnutí upravený rukou `decide` odmítne jménem.
- **Profil revize s projektovou vrstvou** — výchozí povrchy plus `.aid-o/config/policies/review-profiles.yaml` projektu; platí přísnější z obou a vzory cest jsou ve stylu gitignore.
- **Otázka 7 revizorů kroku a žebřík „napiš nejméně kódu, který funguje"** — zbytečná složitost se hledá u každého kroku, ne jednou na konci plánu.
- **`lib/aid-codex-transport.sh`** — jediná cesta ke Codexu (čtecí sandbox, kořen v projektu, zavřený vstup) pod jménem, které říká, co to je; při načtení nemění volajícímu žádnou volbu ani proměnnou.

### Changed
- **Rozhodnutí o vydání čte menší uzavřenou sadu** — `gates_report`, `final_review` (u EPICu index `cp3`), `obligations`, profil revize, doklad kritérií, sémantický soubor kola a ověření evidence; v `done-advance` se loguje jako `release_decision` a blokuje jen s `enforcement: blocking`.
- **Účetní srovnání plánu a stránky o EPICu čtou záznam revizí** — `lib/aid-lifecycle.sh`, `lib/aid-epic-summary-page.sh` a `aid-epic-summary.sh` berou verdikt a otevřené nálezy z `cp7/rounds.json` a `cp3`; zpráva auditora se čte už jen u EPICů uzavřených dřív.
- **`aid-plan-close-check.sh` hlídá stav, ne zprávy** — zůstaly kontroly rozpracovaného DONE, fronty, závazků a hranice plánové větve.
- **Zadání revizorů říká, že `evidence` jsou jen odkazy** — poznámka za číslem řádku dřív potichu zahodila i pravdivý blokující nález.
- **`agents/auditor.md` a `agents/simplifier.md`** — audit zdraví projektu pro `/aid-audit` a agent na vyžádání; `agents/verifier.md` slouží už jen posuzování částí návrhu.

### Fixed
- **Odmítnutí `plan-finalize` před výběrem kroku nekončilo dalším příkazem** — špinavý strom, odpojená hlava a rozpracovaný merge teď také tisknou `next:`.
- **Porovnání cest v profilu revize bralo znaky regulárního výrazu doslova špatně** — `+`, závorky a `|` ve vzoru projektu se už nevykládají jako regex.
- **Blok s diffem v zadání revizora mohl ukončit řádek ze samotného diffu** — plot je z vlnovek.
- **Dva zastaralé testy a jedna základna** — `test-scoped-preflights` (chyběl `--run-id`), `test-control-boundary` (smazaná politika) a délka oddílu revizí v `test-instruction-consistency` byly červené už dřív.

### Removed
- **Reportér, kurátor a most auditu ke Codexu** — `agents/reporter.md`, `agents/curator.md`, `lib/aid-c3-dispatch.sh`, `lib/aid-audit-mode.sh`, `lib/aid-audit-independence.sh`, `lib/aid-review-signals.sh`, politika a prompty C3, šablona zprávy o dodání, příkaz `pm-override`, kontrola výstupu ověřovatele a jejich sady; 35 řádků registru je vyřazeno s nástupcem v `reference/review-successors.md`.
- **Brána dodávky C1** — nespustila jedinou kontrolu ve 101 ze 101 běhů projektů a jinde zdvojovala projektové brány; pravidlo o hodnotách `enforcement` zůstalo jako lint.
- **Kontroly zpráv při uzavření plánu, jejich kopie v `.aid-o/reports/` a kontrola CI nad nimi** — po reportérovi neměly co hlídat.
- **Šest schémat vyřazených artefaktů** — nic je nenačítalo; typy ve validátoru zůstávají, aby šla ověřit starší evidence.

## [2.100.0] — 2026-09-20

### ⚠️ Změna chování — přečti před upgradem

**Když Codex není k dispozici, odpoví místo něj Claude — automaticky a bez
otázky na PM.** Dostupnost se zjišťuje sondou (`aid_codex_probe`): binárku
vybírá podle verze, ne podle pořadí v PATH (na dev hostu starší instalace
stínila novější), a krátkým `codex exec` pozná i vyčerpaný limit účtu —
nainstalovaný Codex, který odmítá odpovídat, je přesně ten případ, který se
opravdu děje. Role, kterou žádný Codex nezvládne, dostane do záznamu
`fallback: claude` a controller dispatchne stejný prompt Claude agentovi.
**Kolo, jehož zástup nikdo nedispatchoval, je od této verze neplatné** (dřív
se uzavřelo jako „degraded" a druhý názor prostě chyběl): roli uvidíte jako
`missing`, dokud zástup neproběhne. Model zástupu je `stand_in_model`
v `review-checkpoints.yaml` (výchozí `opus` pro plán, `sonnet` pro krok
a EPIC). Oponent brainstormingu končí kódem 4 s pokynem `STAND-IN:` místo
monologu; jeho odpověď se vrací přes `--answer <soubor>`.

**`set-field` na čtyři pole, která jsou podmínkou přechodu** (`total_steps`,
`current_step`, `plan_json_hash`, `base_commit`) **vyžaduje `--reason`** delší
než dvacet znaků a rozlišitelnou časovou osu, jinak odmítne. Každé `set-field`
navíc zapíše řádek `field_set` (pole, stará hodnota, nová, důvod) všude,
kde se dá odvodit časová osa běhu.

### Added
- **Zástup za Codex** — `aid_codex_probe` a `aid_codex_binary` v `lib/aid-c3-dispatch.sh` rozhodují dostupnost jednou pro všechny čtyři volající; `AID_CODEX_BIN` pinuje binárku, když je pravidlo podle verze špatná odpověď.
- **`aid-fsm.sh auto-mode set|get`** — zapisovatel `.aid-o/work/auto-mode-state.yaml`, který dokumentace, `/aid-run --auto` i `/aid-stop` jmenovaly rok, aniž by ho kdokoli psal; `aid_autonomous_mode` zůstává jediným čtenářem a bere `mode: manual` nad exportovaným `AID_AUTO_MODE=1` — zastavení od PM vyhrává nad během, který zastavuje.
- **`--candidate <sha>` v `aid-evidence-verify.sh`** — commit, který se soudí, když hlava pracovního stromu je jinde (hranice plánu posílá zmrazeného kandidáta).
- **`replay-do` v `test-step-review-acceptance.sh`** — měřicí režim, který přehraje zaznamenaná kola revizorů přes adjudikátor aktuálního stromu.

### Changed
- **Rozhodčí revize bere, co revizor opravdu píše** — citace smí být rozsah `soubor:první-poslední` (otisk se váže na první řádek) a reprodukce smí být inline `bash -c '<roura>'`. Tělo je ohraničené: každý segment začíná čtecím slovesem, žádné sloveso se zápisovým režimem v seznamu není, a nový řádek, zpětné lomítko, přesměrování, substituce příkazu nebo procesu a jakýkoli `-i` přepínač odmítají. Nezávislá revize ukázala, že první návrh seznamu byl dekorace — patnáct konkrétních úniků je teď testem.
- **Doklad o akceptačních kritériích vzniká z brány, která je ověřila** — `acceptance-evidence.json` na úrovni plánu se staví z `plan-diff.json` `results[]` s verdiktem `verified`, `partial` nebo `prose_only`; blokuje jen `partial`, a jmenuje kritéria. `--stage inputs` čte přeskočený `plan_diff` stejně jako `--stage gates`.
- **`aid-evidence-verify.sh` hledá balík ve stavovém kořeni** — z plánovacího worktree, který vlastní `.aid-o/` nemá, už nehlásí „no evidence packs found"; `git_clean` počítá jen sledované soubory, protože runtime zapisuje nesledované adresáře do stromu, ve kterém běží.
- **`alloc plan-id` / `alloc epic-id` přeskočí číslo, které už soubor nese** — WAN dostal P106 dvakrát; číslo je zadarmo, kolize ne.

### Fixed
- **Zpráva C3, která si odporovala se surovým verdiktem Codexu, zůstávala na disku** — release brána čte soubor, ne surovou odpověď (ACTA: tři nálezy, dva vysoké, zpráva tvrdila nula). Neshoda teď zprávu odloží jako `audit-report.rejected.json` a nahradí ji `status: unverifiable` se surovým verdiktem; pod `--read-only`, který posílá FSM hook, se nepíše nic.
- **`aid-release-policy.sh` neříkal verifikátoru, který strom má soudit** — soudil adresář volajícího, takže cizí rozdělaná práce padala na účet tohoto běhu.
- **`fsm_check_review_round` bez `yq`** — přepínače se četly jako prázdné a pravidlo kola se vynucovalo ze souboru, který nikdo nepřečetl; teď hlasité `PRECONDITION FAIL`.
- **Zastaralé fixtury a základna registru** — základna regenerována (dvanáct řádků se posunulo bez deklarace), čtyři fixtury z doby před P093/P094 zelené, šablona CP4 už nepopisuje odstraněný pre-filter.

### Removed
- **`scripts/aid-acceptance-evidence.sh`** — neměl živého volajícího a četl `verifier-output-step-N.md`, které od P094 nikdo nepíše; jeho dva registrové řádky jsou retired s nástupcem a odstavec „AC↔Evidence" zmizel z `agents/verifier.md`.

## [2.99.0] — 2026-09-19

### ⚠️ Změna chování — přečti před upgradem

Každý krok běhu (`/aid-run`) a každý EPIC před branami teď prochází stejnou
kontrolou, jakou má od 2.98.0 plán: deterministická kontrola kroku
(`aid-step-check.sh`), pak kolo nezávislých revizorů (`aid-review-round.sh`,
role v `skills/step-review-roles.md`) a rozhodčí, který přijme jen nález
s čtecím příkazem a existujícím `soubor:řádek`. FSM čte jen index kola
(`cp2/step-N/rounds.json`, `cp3/rounds.json`) vázaný na HEAD: krok bez kola se
neuzavře, EPIC bez uzavřeného kola nejde do bran, ručně napsaný „skip" se
odmítne. Soubory `verifier-output-step-N.md` a `verifier-output-cp3-*.md` už
nic nečte; rozběhnutý EPIC ze starší verze dokončí své kroky až po doběhnutí
kontroly kroku pro aktuální krok (jeden příkaz, FSM ho vypíše). Opravy nálezů
dělá role, která krok psala, ne gate-fixer; po posledním povoleném kole `close`
otevřené nálezy zapíše do deníků (routované nebo nesené), takže se nic neztratí.
Projekt, který kontrolu nechce, ji vypne `review_checkpoints.cp2_step_review`,
`cp3_integration_review` nebo `cp6_fast_mode_review: false`.

### Added
- **Kontrola kroku bez modelu** — `aid-step-check.sh` spočítá rozsah diffu od hranice kroku, soubory mimo rozsah a zakázané cesty, bezpečnostní a handlerové vzory, testy a jejich patra, a rozhodne `skip` / `no_change` / `review` / `review+security`; verdikt zapíše do `step-check.json` s otiskem a událostí v timeline, na kterou se FSM váže.
- **Jeden motor kol pro všechny kontroly** — `aid-review-round.sh` obsluhuje plán (`--plan`), krok, EPIC i fast mode (`--checkpoint cp2|cp3|cp6`): balík (diff, DoD, deklarovaný rozsah, kontrola kroku), jeden prompt na roli ze sdílené šablony, dispatch Codexu, sběr, uzavření s tokeny a USD, potvrzovací kolo jen pro reportéry otevřených nálezů, pokyn PM k počtu kol. Odpověď revizora platí jen uvnitř zaznamenané závorky dispatchu.
- **Sdílený rozhodčí a jedna smlouva odpovědi** — `aid-review-adjudicate.sh` a `defaults/schemas/review-finding.schema.json` pro všechny checkpointy; nález na handlerovém vzoru bez stopy chování se odmítne; nálezy skriptu kontroly kroku vstupují do sloučeného seznamu.
- **Routování a nesení otevřených nálezů** — po posledním kole `close` sám zapíše nález mimo rozsah zbylých kroků do deníku routovaných nálezů (EPIC se bez rozhodnutí PM neuzavře) a nález, který pokryje pozdější krok, jako nesenou povinnost; cp3 uzavření píše `semantic-review-final.json` pro plánové spotřebitele.
- **Fast mode na tomtéž mechanismu** — `/aid-do` zakládá `evidence/do/<id>/`, kontroluje pracovní strom a vede kolo, poradně.
- **Ceník a cena kontroly** — `defaults/prices.yaml` (sazby s citovaným zdrojem a datem), `aid-review-summary.sh` počítá USD z tokenů pro `/aid-status` (dlaždice „Revize plánu" a „Revize kroků") i do `measurement.json`.
- **Tabulka nástupců a její test** — `reference/review-successors.md` a `test-review-successors.sh`: každé vyřazené vynucení má zapsaného nástupce.
- **Producent profilu jako vlastní skript** — `aid-review-profile.sh` (dřív podpříkaz pre-filtru), stejné argumenty a výstup.
- **Sabotážní kontroly v testbedu** — zakomitovaný secret, dotčená zakázaná cesta a čistá docs změna; první z nich odhalila dvě chyby kontroly kroku ještě před vydáním.

### Changed
- **FSM** — jedna precondition `fsm_check_review_round` pro cp2 i cp3 (index kola, HEAD, událost kontroly kroku, D4 výjimka pro testovací churn s trailerem zachována); compliance hlásí `cp2_rounds` / `cp3_round` místo provenance verifikátoru.
- **Instrukce** — `/aid-run` má jednu sekci „Step review (CP2) and EPIC review (CP3)" s doslovně citovanou instrukcí pro controller; skill pipeline, karta verifikátora (jen CP4 a plánový `final`), gate-fixer (`model: sonnet`, jen CP4), nápověda a smlouvy checkpointů ukazují na ni.
- **Registr vynucení** — 12 řádků vyřazeno s nástupci, 13 nových; klíč `verifier_provenance` vyřazen ze `check-severity.yaml`.
- **Akceptační sada kroku** — `test-step-review-acceptance.sh --mode new` vede 20 zaznamenaných diffů novým tokem; zaznamenané odpovědi se přehrávají bez modelu.

### Fixed
- **Bezpečnostní pravidla se nikdy neshodla s mezerou** — pravidla z `pre-filter-rules.yaml` používají `\s`, které bash `=~` nezná, a `@tsv` jim escapoval zpětná lomítka; aplikují se přes `grep -iE`, tedy i na `AWS_SECRET_ACCESS_KEY = "…"`.

### Removed
- **Starý řetězec kontroly kroku** — pre-filter (`aid-prefilter.sh classify`, trivial skip), soubory `verifier-output-step-N.md` a `verifier-output-cp3-*.md`, `Reviewed-Head`, `verify_provenance` a `provenance_aggregate`, smyčka oprav gate-fixerem a E7, wrappery `dispatch_mode: subagent` pro cp2/cp3, C2 emit `local|wiring|behavior`, invalidační mapa (`aid-invalidation-map.sh`, schéma, hook, FSM kontrola — rozhodnutí PM 7A, bez náhrady), skripty jen pro CP1 (`aid-plan-review-round.sh`, `-adjudicate.sh`, `-config.sh`, `-summary.sh`, adaptér, prompt, schéma) a jejich sady (`test-aid-prefilter`, `test-invalidation-map`, `test-behavior-trace`, `test-anti-fabrication`, `test-cp3-freshness`, pět `test-plan-review-*`).

## [2.98.0] — 2026-09-18

### ⚠️ Změna chování — přečti před upgradem

Každý plán teď před generováním EPICů potřebuje uzavřené kolo kontroly plánu
(šest revizorů, `commands/aid-plan.md` „Plan review (CP1)"). Pásma, která malé
plány pouštěla bez kontroly, už nejsou. Plán, který byl zkontrolovaný starým
řetězcem (`cp1-deep/`, Codex smyčka), projde novou kontrolou znovu; stará
evidence zůstává na disku jako historie. Autorita generace zapečetěná starší
verzí se po upgradu musí zapečetit znovu (`aid-auto-pipeline.sh supersede-generation`),
protože už nenese pole `band`. Projekt, který kontrolu plánu nechce, ji vypne
`review_checkpoints.cp1_plan_review: false`.

### Added
- **Kontrola plánu šesti revizory** — `aid-plan-review-round.sh` vede kola: jeden balík pro všechny (plán, výsledek deterministické kontroly, standardy projektu), šest rolí z jedné šablony (`skills/plan-review-roles.md`), revizor na Claude přes controller a na Codexu přes izolovaný spouštěč, sběr s minimem odpovědí, uzavření s naměřenými tokeny, kontrola opravy proti seznamu nálezů, spor s odpovědí PM, finalizace a zápis pokynu PM k počtu kol (výchozí dvě, třetí nebo jen jedno jen na jeho slova).
- **Rozhodčí skript nálezů** — `aid-plan-review-adjudicate.sh` bez modelu odmítne každý nález bez čtecího příkazu a existujícího `soubor:řádek` (důvod zapíše do `rejected.json`), stejné nálezy sloučí, spočítá výnos každé role a v dalším kole označí, co bylo opravené.
- **Potvrzovací kolo s kontextem** — revizoři druhého kola dostanou otevřené nálezy a diff opravy a hlásí jen neopravené a to, co oprava nově rozbila; ptá se jen rolí, kterých se oprava týká.
- **Cena kontroly v `/aid-status` a na stránce plánu** — řádek s počtem kol, tokeny, neznámými hodnotami a rolemi, které neodpověděly; dlaždice „Revize plánu" místo „Pásma".
- **Kontrola A11** — plán s `type: docs` (kontrolují ho jen dva revizoři) nesmí deklarovat kód.

### Changed
- **Brána CP1** — `aid-cp1-gate.sh` čte jen evidenci kol: kolo 1 uzavřené a platné, plán shodný s tím, co se kontrolovalo, druhé kolo při otevřených blokujících nálezech, každý otevřený blokující nález citovaný v kritériu přijetí svého kroku. Poškozená evidence a neplatná konfigurace se `--force` přebít nedají (exit 3).
- **Instrukce pro agenta** — `/aid-plan` má jednu sekci „Plan review (CP1)", kde je každý krok příkaz; `/aid-verify-plan` spouští jednoho revizora ručně; karta verifikátora, skill pipeline a nápověda odkazují na nový postup.
- **Hranice uzavření plánu** — vstup `plan_review` politiky vydání čte zapečetěnou autoritu generace místo souboru Codex smyčky.
- **Kontrola plánu po opravě** — `aid-plan-check.sh --fixes none`, v JSON změněné kroky a přidávky mimo seznam oprav; cesty evidence kontroly nejsou falešně hlášené jako chybějící soubory.
- **Testovací fixture** — sdílený pomocník zasévá skutečné kolo kontroly plánu, takže noční sady procházejí stejnou cestou jako produkce.

### Removed
- **Pásma ceremonie** — klasifikátor, mapa rizikových cest, tabulka pásem a `--classify-only`; každý plán má stejné povinnosti.
- **Starý řetězec kontroly** — ledger pokusů, C0 smlouva, Codex smyčka kontroly plánu, její prompt, politika, dvě schémata, texty devíti čoček, `pm-override grant c0` a jejich testy a fixture (5 601 → 1 847 řádků kódu a dat oblasti; v registru vynucení 12 řádků pryč a 7 nových).

## [2.97.0] — 2026-09-17

### Added
- **Deterministická kontrola plánu** — nový `scripts/aid-plan-check.sh` spustí lint a k němu všechno, co o plánu jde rozhodnout bez modelu: soudržnost plánu (graf závislostí bez cyklů a neexistujících kroků, číslování, kroky M/L se třemi kritérii a třemi hraničními případy, zakázané fráze včetně českých, cesty v kritériích deklarované, tvar `verification_pattern`, úprava souboru, který nikdo nezakládá, prázdné sekce, dvakrát zkopírovaný text bulletu, varování u velikosti), plán proti repu (cesty v próze existují nebo vznikají, rozsahy řádků a symboly u nich, mazané soubory existují a nikdo je dál nepoužívá, blok Resources Verification nelže o tom, co existuje, kritérium splněné už dnes, zakládaný soubor už existuje, kolize jmen testů) a po opravě (`--snapshot` + `--fixes`: nová tvrzení opravy proti kódu, zastaralá dvojčata, kroky mimo seznam oprav, a oprava, která PŘIDÁVÁ chování, se odmítne). Dva stupně jako u lintu: plán s `lifecycle_strict` blokuje vše, legacy plán jen to, co by rozbilo generování. Výstup i jako JSON s otiskem plánu. Vzniklo z pilotů ACTA P025 a Agents P005 (17. 9. 2026): 9 z 16 nálezů první kontroly byly věci pro skript, opravy vyráběly 19 až 45 % nových chyb a kola nekonvergovala, protože opravy přidávaly mechanismy.

### Changed
- **Brána před generováním** — `aid-generation-readiness.sh` po lintu spouští i `aid-plan-check.sh` a blokuje na jeho nálezech; každý nález má odkaz na kontrolu, kterou v pilotech dělal placený model.

## [2.96.1] — 2026-09-03

### Fixed
- **Připomínka otevřeného plánu chodila do každého okna** — konec tahu už mluvil jen o plánech z vlastního okna, ale start sezení hlásí celý projekt a jeho paměť „tohle už jsem řekl" byla vázaná na okno. Pět otevřených terminálů nad jedním projektem tedy znamenalo pětkrát tutéž větu. Paměť je nyní vázaná na projekt: první okno to řekne, ostatní mlčí, a znovu se to ozve, jakmile se plán skutečně pohne. Okno, které na plánu pracuje, ho slyší dál na konci každého tahu.
- **Dvě jména téhož adresáře měla každé vlastní paměť** — cesta se převádí na skutečný tvar, takže přístup přes symlink není nový projekt.
- **Neplatný kořen by umlčel všechny projekty najednou** — sdílený klíč se staví jen z existujícího adresáře; jinak zůstává klíč vázaný na okno, takže se připomínka nanejvýš zopakuje, nikdy neztratí.

## [2.96.0] — 2026-09-03

### ⚠️ Změna chování — přečti před upgradem

Od této verze **může brána, která dosud nikdy nic nezastavila, začít běh blokovat**.
Týká se to bran, které mají `required_when` a nemají `required`. Takové brány
runner dosud počítal jako nepovinné, takže jejich pád nikoho nezastavil.

Pokud má brána zůstat doporučující, dopiš jí do `.aid-o/config/execution.yaml`
jeden řádek — výslovné rozhodnutí vždy vyhrává nad odvozením:

```yaml
    required: false
```

Konfigurace projektů se nepřepisuje automaticky. Report u každé brány nově nese
`required_source` (`explicit` / `required_when` / `not_applicable` /
`legacy_default`), takže je dohledatelné, proč byla brána povinná.

### Added
- **`required_when` u bran se konečně čte** — klíč byl ve všech 14 branách všech 5 dodávaných šablon a v každém projektu, který kdy vznikl přes `/aid-init`; runner ho nečetl. Rozhoduje, zda brána na tenhle strom vůbec platí: výslovné `required:` má přednost, jinak rozhodne `required_when`, jinak zůstává původní `false`. Mluvnice je uzavřená (`always`, nebo `<maska> exists` spojené doslovným ` OR `) a ověří se u každé brány dřív, než se spustí jediný příkaz.
- **Administrativní zavření plánu** — `plan-close --administrative --reason "…"` zavře plán, který nikdy nevyrobil řetěz evidence: práci vyvinutou mimo AID, nebo plán uvízlý na vadě pluginu. Nezapisuje kandidáta, běh ani verdikt; zaznamená, co nešlo potvrdit, a nikdy nezní jako řádné uzavření. Odmítne se, když evidence existuje (i když říká „fail"), a nelze ho kombinovat s `--force`, který znamená opak.
- **`--tree` u ověření evidence** — kontrola dostane strom, který má posoudit, a report jmenuje, který to byl a odkud se vzal.

### Fixed
- **Padající test nechal běh projít ve všech projektech založených AIDem** — `required_when` runner neuměl přečíst, takže se u brány dosadilo „nepovinná". Spadlý pytest, ruff, mypy, eslint i tsc zapsaly `fail` a verdikt zůstal `pass`. Postižené projekty neudělaly nic špatně: jejich konfigurace byla bajt po bajtu ta, kterou jim AID vygeneroval.
- **Brána vložená do plánu, kterou profil vylučuje** — bránu vybírá generování z mapy `gates:`, ale přechod GATES→DONE ji posuzuje podle `gate_profiles:`. Shodu nikdo nekontroloval, takže běh zaplatil celý průchod branami a teprve pak byl odmítnut. Generování to nyní odmítne dřív, než se cokoli zapečetí.
- **Graf závislostí tiše zahodil vše kromě prvního `Depends on:`** — ořez lidského komentáře běžel od první pomlčky do konce a bral s sebou i následující deklarace. Pět kroků z jedenácti přišlo v reálném plánu o závislosti a rozpor se ukázal až o několik kroků dál.
- **`base_commit` z jiné větve zasekl plán po prvním EPICu** — zapisoval se z adresáře, kde běželo generování, tedy typicky hlava `main`. Nově se bere zapsaný řez EPICu z manifestu, jehož rodokmen se před odpovědí prokáže.
- **Stop hook radil zavřít plán, ve kterém se nic neudělalo** — prázdná fronta se nerozlišovala od vyčerpané, takže dvě minuty po založení plánu zněla rada „ještě zbývá zavřít".
- **Testovací sady padaly na zestárlých předpokladech** — čtyři sady měřily něco jiného, než tvrdily: „PATH bez codexu" ho od jeho globální instalace obsahoval, fixture nesplňovala požadavek na C0 čočku, který přibyl později, a zlatý otisk reportu porovnával naměřené doby běhu proti nulám.
- **Brány hlásily průchod, i když povinná brána spadla** — verdikt se nastavoval v sedmi větvích a běh, který neprošel žádnou z nich, zůstal „prošel". Nyní se odvozuje z řádků a řádek nese `required`. Verdikt, který nejde ověřit proti vlastním řádkům, je selhání.
- **Audit zahazoval nálezy** — porovnávala se hlava adresáře evidence, který leží v hlavním checkoutu, místo hlavy kandidáta. Codex vracel blokující nálezy a zapsalo se `unverifiable` s prázdným seznamem.
- **Ověření evidence se dívalo na hlavní checkout** — kandidát ve vlastní pracovní kopii se posuzoval podle cizí rozpracované práce.
- **Chyba nástroje vypadala jako průchod** — kontrola uzávěrky umírala na rozbitém YAML uprostřed běhu.
- **`epic-start` si vymýšlel ID běhu** — když běh existoval pod jiným ID, manifest ukazoval jinam než evidence a dokončení EPICu svůj běh nenašlo.
- **`plan-reconcile` prohlašoval každý EPIC za neověřitelný** — nezahajoval režim plánu, takže se reviewed-head četl z neexistující cesty.
- **Soubor s diakritikou v názvu byl odmítnut** — `git status` bez `core.quotepath=false` vrací escapovanou podobu, která se s deklarovanou cestou neshodne.
- **`amend-scope` po posledním kroku** — brána si vyžádá soubor mimo rozsah a dosud pro to nebyla cesta. Nově je povolen i ve fázi bran a zaznamenané řádky bran se odloží stranou, aby se nedaly přehrát.
- **Projekce delivery reportu přepsala skutečné poznámky prázdnou šablonou** — starší schéma má klíče jinde; neznámý tvar se nyní nerenderuje a řekne, co hledal.
- **Sběrač hlášení neviděl datované nadpisy** — devatenáct hlášení tři dny propadalo, zatímco hlásil „nic nového". Nadpis s hlubším nadpisem pod sebou je oddíl, ne položka.

### Changed
- **Odmítnutí obálky jmenuje pole, která se liší** — `status` a `verdict` v seznamu chráněných polí chyběly, ačkoliv chráněné jsou; šablona nyní nese seznam zamčených polí.
- **`aid-run.md` říká, co po volajícím chce** — že se fronta plní v předletové kontrole a že commit patří na větev, na kterou se autor musí přepnout. Obojí dosud nebylo napsané nikde a agenti byli káráni za jejich nesplnění.

## [2.95.11] — 2026-08-30

### Fixed
- **Připomínka o otevřeném plánu se řekne jednou, ne na každém tahu** — pravidlo četlo všechny záznamy plánů v projektu a jmenovalo je při každém konci tahu, včetně plánů, na kterých session nepracovala. V konzumentském projektu se čtyři otevřené plány hlásily dokola a agent na každou připomínku odpověděl „čekám na tebe": pravidlo, které se opakuje, naučí čtenáře přeskakovat i tu jednu větu, která měla význam.
- **Konec tahu mluví jen o plánech této session; začátek session o všech** — přehled celého workspace dává smysl na začátku, ne uprostřed práce na něčem jiném.
- **Paměť „řekni to jednou" nemá jak spolknout připomínku, kterou nikdo nedostal** — bez identity session se připomínka řekne (dřív by prázdný klíč znamenal jednu sdílenou paměť pro všechny); `transcript_path: ""` nyní správně přepadne na `session_id`; a značce v úložišti se věří jen tehdy, když do ní jde zapsat — jen-pro-čtení úložiště dřív mlčelo navždy, přestože se chování jmenovalo „fail-open".
- **Klíč session a přepis konverzace jsou dvě různé hodnoty** — `session_id`, které náhodou pojmenuje čitelný soubor, se už nečte jako přepis.

### Changed
- **`aid_session_once` je sdílená** — pravidlo „řekni to jednou za session" žije v session store, ne jako kopie v jednom pravidle; dvě kopie téže logiky by se rozešly.
- **Vědomá mez je napsaná v kódu i pojištěná testem** — plán otevřený uprostřed session, který tahle session nezmíní, se ohlásí až při příštím startu. Ztráta je ohraničená jednou session; opačná vada, cizí plán hlášený na každém tahu, je ta, kvůli které se připomínky přestaly číst.

## [2.95.10] — 2026-08-30

### Fixed
- **Uzávěrka hodnotila starou verzi plánu** — `plan-finalize --stage gates` i `--stage inputs` čtou zdrojový plán nejdřív z pracovní kopie kandidáta (plán, který si během práce upravil kritéria, je souzen podle toho, co upravil), teprve pak ze stavového kořene; brána `plan_diff`, profil revize i `plan-diff.json` tak hodnotí tentýž text. `--stage gates` před během vypíše, odkud plán i `execution.yaml` vzala (`--stage inputs` vypíše použitý plán) – konfigurace bran je vždy ze stavového kořene, kopie na plánové větvi se nečte (ACTA ztratila půl hodiny hledáním, proč úprava timeoutu „nefunguje").

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

Older entries (0.1.0 – 2.89.3) live in [CHANGELOG-archive.md](CHANGELOG-archive.md).
