# Changelog

All notable changes to the AID Orchestrator plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

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
