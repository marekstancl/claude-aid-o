# Postup: webová aplikace (druh `webapp`, P116)

Platí jen pro projekt, jehož varianta má `type: webapp`. Web (`web`) a instalovatelná aplikace (`pwa`) jdou beze změny
podle ostatních postupů. Ověřeno 18. 10. 2026 na vzorové aplikaci v testech a testbedu; pilot na skutečném projektu
doplní, co se ukáže (oddíl Pozorování).

**Nahrazuje:** ze `steps/0-start.md` výběr volitelných částí pro aplikaci (slogan, hledání, logo) a ze
`steps/2-structure.md` postup stromu stránek, drátěné modely a JSON struktury (`structure.json`).
**Platí dál:** krok 0 (volba varianty, inventura, podklady ke spuštění), texty, vzory, vzhled, stavba, kontrola
a předání; místa rozhodnutí a smyčka kvality (`aid-ui-quality.py round`), schvalování ve studiu.

## Proč jinak než web
Web se posuzuje podle toho, jestli zákazník najde, co hledá. Aplikace podle toho, jestli v ní člověk **dokončí svou
práci**, i když se cestou něco pokazí. Proto je jejím základem jeden popis obrazovek a úloh
(`docs/design/screens.json`), ze kterého se staví kostra, testy úloh pro bránu i předávací balík. Nic se pro
aplikaci nekopíruje: tytéž nástroje, větev podle druhu.

## 0. Druh a co se vynechá
- Varianta `{"type": "webapp", "brand": …, "local": false}`; běží-li aplikace už dnes, navíc `"existing": true`
  (zapne část „Výchozí stav aplikace").
- Volby kroku 1: `vision: false` (slogan aplikace nepotřebuje), `seo: false` (aplikace za přihlášením se nehledá),
  `identity: false` u `brand: existing` (balíček existuje) a `brand: none` (interní nástroj, síť LAN); u `brand: new`
  je logo místo jako u webu.
- **Každá vynechaná část má zapsaný důvod**, jinak stav nepustí aplikaci za krok 1 (`aid-ui-state.sh step 2` odmítne):
  `aid-ui-state.sh decide <projekt> --step <krok> --title přeskočeno --outcome "<část> přeskočena" --why "<důvod>"`
  pro každou z částí `vize`, `hledani`, `logo`, kterou volby vynechaly.
- Místa rozhodnutí aplikace: `struktura` (obrazovky a úlohy), `vzhled`, `web` (hotová aplikace). `sdeleni`, `logo`
  (kromě `brand: new`) a `pohyb` (kromě výslovného přání PM) se vynechávají.

## 1. Výchozí stav (jen existující aplikace, část „Výchozí stav aplikace")
1. `aid-ui-baseline.py list <projekt> --url <běžící aplikace>` napíše návrh seznamu dnešních úloh z navigace aplikace
   a dokumentace projektu do `.aid-ui/baseline/tasks.json` (každá úloha: kroky s adresou, akcí a vstupem, přihlášení,
   pozorovatelný výsledek). Návrh doplň a oprav podle toho, co lidé v aplikaci opravdu dělají.
2. PM seznam schválí ve studiu: otázka druhu `exception`, `part: vychozi-stav`, `target: baseline@<sha256 souboru>`.
   Platí jen odpověď PM (`app_owner_only`).
3. `aid-ui-baseline.py capture <projekt> --url <aplikace> [--login <uložené přihlášení prohlížeče>]` zahraje každou
   schválenou úlohu a zapíše výsledek a snímky; změněný seznam po schválení odmítne. Snímky jsou jen podklad pro PM.
4. Úlohu, která v nové podobě nebude, zruší jen PM: otázka `exception`, `target: task@<id>`, s důvodem v komentáři.

## 2. Obrazovky a úlohy (část „Obrazovky a úlohy", místo `struktura`)
0. **Soupis požadavků dřív než model** (SKILL.md „Verze 1 je kompletní“): každý bod zadání projektu, plánu fáze
   a podkladů UI se zdrojem `soubor:řádek`; každý dostane úlohu nebo obrazovku (`task:<id>`, `screen:<id>`), nebo
   `out_of_scope` s důvodem. Úloha, kterou zadání výslovně jmenuje (zavřít pozici, potvrdit nebo zahodit), v modelu
   nesmí chybět - pilot 18. 10. 2026: role ji našly v kole 1, protože soupis nebyl.
1. **Úlohy první.** Z kódu a zadání projektu (zadání, plán, cesty API) sepiš, co uživatel v aplikaci dělá. Ke každé
   úloze sedm stavů standardu Úlohy a stavy webové aplikace (UA-1): běžná cesta = kroky, k tomu chyba validace,
   prázdno, načítání, selhání, oprávnění a obnova po přerušení. Stav, který nenastane, se píše
   „nenastává, protože …" - nikdy se nevynechá.
2. **Obrazovky z úloh.** Každá obrazovka má účel, akce (s cílovou obrazovkou a druhem `navigate`, `submit`,
   `destructive`; mazání a nevratné akce s potvrzením) a čtyři stavy (prázdno, načítání, chyba, naplněno).
   Obrazovka bez úlohy se nenavrhuje.
3. **Výsledek každé úlohy** (`done_when`): obrazovka, na které úloha skončí, a text, který tam musí být. Úloha, která
   odesílá data, má cestu selhání (`failure_paths`: krok, druh selhání, vstup zůstane, akce obnovy), nebo
   „nenastává, protože …" ve stavu selhání. U existující aplikace úloha, která nahrazuje dnešní, nese `replaces`.
4. Model zapiš nástrojem Write do `docs/design/screens.json` (tvar `references/screens.schema.json`) a zkontroluj:
   `aid-ui-screens.py check <projekt>` (exit 0).
5. Kostra: `aid-ui-serve.sh skeleton <projekt>` postaví z modelu proklikávací aplikaci na stálé adrese: navigace,
   každá obrazovka s přepínačem stavů (`?stav=empty|loading|error|filled`), akce vedou na své obrazovky, mazání přes
   potvrzení. Dokud PM model neschválí, nese každá stránka pruh „model čeká na schválení vlastníkem".
5a. **Lišta aplikace** (STOP, Panika, režim - co je na každé obrazovce) je obrazovka s `shell: true`: její akce kostra
   vykreslí na každé stránce, krok úlohy na ní smí stát odkudkoli.
5b. **Před kolem rolí:** `aid-ui-verify.sh <projekt> --precheck` zelené nad modelem teď, vlastní projití obou měřítek
   (každé kritérium ≥ 9 s důkazem) a `aid-ui-quality.py self <projekt> --place struktura --file <kontrola.json>`.
6. Kolo místa `struktura` (`aid-ui-quality.py round <projekt> --place struktura --web <adresa kostry>`): role
   proklikávají kostru a čtou model. Klient-role je vlastník produktu a klíčový uživatel, postavená z kódu a zadání
   projektu. Její nálezy jdou PM na kartu jako podklad.
7. **Úlohy schvaluje vlastník produktu (PM), nikdo jiný.** Otázka druhu `structure`, `part: obrazovky`,
   `target: docs/design/screens.json@<sha256 modelu teď>`. Odpověď klient-role ani agenta se nezapíše
   (`app_tasks_need_owner`). Schválení si stav pamatuje s otiskem modelu (`app.approved_model_sha`);
   `aid-ui-state.sh model-approved <projekt>` ověří, že model je ten schválený. Změněný model = kostra znovu jako
   návrh a nová otázka PM. Deleguje-li PM schvalování na jmenovaného vlastníka, dá mu odkaz na svou stránku studia
   a zapíše to jako rozhodnutí (`decide`); jiná cesta, jak by odpověď někoho jiného platila za PM, není.

## 3. Texty, stavy a vzhled
Kroky 3-5 jako u webu, nad kostrou aplikace: texty obrazovek a všech stavů (hlášky chyb říkají, co se stalo a co dál),
vzory podle oboru aplikace, tři směry vzhledu jako skutečné stránky kostry. Místo `vzhled`.

## 4. Stavba - smlouva s bránou
Postavená aplikace drží dvě věci, na kterých stojí testy úloh a předání:
- každá akce modelu nese `data-aid-action="<obrazovka>.<akce>"` a kořen obrazovky `data-aid-screen="<obrazovka>"`;
- v testovacím režimu (`?aid-test=1`) obrazovka poslechne `?stav=` a ukáže ten stav;
- stav úlohy (`?stav=<úloha>.<stav>`: chyba validace, prázdno, načítání, selhání, oprávnění, obnova) se ukáže na obrazovce
  prvního kroku úlohy v bloku `data-aid-task-state="<úloha>.<stav>"`;
- akce, která jde jen v některých režimech (`modes` v modelu), je v ostatních neaktivní s větou proč; režim pro test
  nastaví `?rezim=<režim>`.

Čísla v ukázkách, potvrzeních a výsledcích se píšou jako pojmenované hodnoty `{klíč}` (model `values`, každá se
zdrojem): jedno číslo je na jednom místě a čísla téhož obchodu si nemůžou odporovat. Nevratná akce nese texty svých
tlačítek (`confirm_yes`, `confirm_no`), pole své meze (`required`, `min`, `max`, `maxlength`, hláška `error`), odkaz
na záznam svůj parametr (`query`). Graf má v kostře datovou tabulku (`tables`: popisek, sloupce, řádky se stejným
počtem buněk), ne jen větu shrnutí.

## 5. Brána
1. `aid-ui-flows.py generate <projekt>` napíše z modelu do `.aid-ui/scenarios/` jeden test na úlohu (kroky, pak
   výsledek `done_when`) a jeden na každou cestu selhání (vnucená chyba, vstup zůstal, obnova, výsledek). Úloha, která
   odesílá data a cestu selhání v modelu nemá, dostane vygenerovanou chybu sítě na posledním odeslání.
2. `aid-ui-verify.sh <projekt>` nejdřív ověří schválený model (`model-approved`) a scénáře si z něj vygeneruje sama,
   pak řádky `app_flows` (úloha doběhne k výsledku), `app_states` (každá obrazovka ve všech stavech, adresa obrazovky
   s `?aid-test=1&stav=<stav>`), `keyboard_flows` (úloha jen klávesami Tab a Enter) a `task_recovery` (vnucená chyba
   neztratí obrazovku ani vstup, nabídne obnovu a úloha i tak dojde k výsledku). Řádky úloh a stavů běží na 1440
   a 390 px v Chromiu (`app_rows` v `coverage/checks.yaml`); každý výsledek nese otisk modelu (`model_sha256`).
   Scénář jiného modelu brána odmítne. Obrazovka se otevírá na své adrese (`url` v modelu, jinak `/<id>/`).
   Každý řádek úlohy běží v čistém prohlížeči; aplikace za přihlášením dá bráně testovací přihlášení jako
   `.aid-ui/test-storage.json` (uložený stav prohlížeče Playwright, jen testovací účet).
3. Existující aplikace: `aid-ui-baseline.py compare <projekt>` - každá dnešní úloha má novou úlohu s `replaces`,
   která prošla poslední branou a končí stejným výsledkem (kromě úloh, jejichž zrušení PM schválil). Pouští ho sám
   balík při předání: bez toho se aplikace nepředá. Zadání změn kódu ho má jako bod nad výsledkem brány běhu.

## 6. Předání
Balík verze 2 nese model (`screens`, otisk a schválený otisk) a výsledky úloh (`task_results`, ověřené na kostře).
`aid-ui-package.py zadani` z něj napíše **zadání změn kódu**: první bod smlouva z oddílu 4, pak bod za každou úlohu
a za každou cestu selhání; ověří je brána běhu `check_ui_handover` v kódu projektu. Kód aplikace staví až plán
projektu z tohoto zadání, studio ho nemění.

## Pozorování (neověřeno)
