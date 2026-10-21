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
3b. **Fakta appky jako první (aplikace s kódem, P118):** `aid-ui-client.py facts <projekt>` - Codex a Claude Opus
   souběžně a nezávisle vytěží z kódu, plánů, rozhodnutí a runbooků, co appka opravdu dělá (asi 7 minut); soudce
   (Codex) vidí oba seznamy naráz a spáruje fakta, která tvrdí totéž, i když mají jiné id nebo jiný rozsah řádků.
   Do `docs/design/app-facts.json` jde jako dohodnuté jen to, co řekli oba (citace ověřená v souboru); dohodnutá fakta
   přežijí další běh. Fakt, který našel jen jeden čtenář, je `unconfirmed` - informuje, nic neblokuje; potřebuje-li
   ho úloha, `facts --focus "<otázka se soubor:řádek>"` ho nechá dočíst. Dva fakty, které si odporují, jsou otevřená
   otázka (`spor-<id>`): lint model nepustí, dokud ji `--drop <id> --reason "<jak to podle zdroje je>"` vědomě
   neuzavře. Každá zapisující úloha modelu odkazuje na fakta, o která se opírá (`facts: [id]`), nebo - je-li to
   chování, které appka dnes nemá - na požadavek ze soupisu (`new: <id požadavku>`); fakt, jehož citace ze zdroje
   zmizí, lint hlásí jako zastaralý.
4. Model zapiš nástrojem Write do `docs/design/screens.json` (tvar `references/screens.schema.json`) a zkontroluj:
   `aid-ui-screens.py check <projekt>` (exit 0).
   Kontrola obsahuje lint z tříd nálezů pilotu P116 (P118): částka, R, procento, páka či mez (znaky, čas, počet)
   napsaná přímo místo pojmenované hodnoty (`values`), pole, jehož nápověda slibuje mez, kterou nemá, číslo nebo čas v účelu obrazovky, zapisující úloha bez stavu oprávnění nebo bez cesty selhání
   sítě i serveru (kromě úlohy, která na server nesahá: selhání „nenastává“). Lint běží v sekundách; co projde, se
   nemusí honit v bráně ani v kole rolí.
5. Kostra: `aid-ui-serve.sh skeleton <projekt>` postaví z modelu proklikávací aplikaci na stálé adrese: navigace,
   každá obrazovka s přepínačem stavů (`?stav=empty|loading|error|filled`), akce vedou na své obrazovky, mazání přes
   potvrzení. Dokud vlastník model neschválí, nese každá stránka pruh „model čeká na schválení vlastníkem".
5a. **Lišta aplikace** (STOP, Panika, režim - co je na každé obrazovce) je obrazovka s `shell: true`: její akce kostra
   vykreslí na každé stránce, krok úlohy na ní smí stát odkudkoli.
5a2. **Po každé úpravě modelu nebo kostry** `aid-ui-verify.sh <projekt> --quick` (stejné řádky jako předběžná brána,
   jen na nejširší šířce, asi minuta); o kole ani předání nerozhoduje.
5b. **Před kolem rolí** (SKILL.md „Verze 1 je kompletní“): lint bez nálezu, `aid-ui-client.py verify <projekt> --place
   struktura --web <adresa kostry>` bez otevřeného rozporu a se všemi opravami minulého kola viděnými, `aid-ui-verify.sh
   <projekt> --precheck` zelené nad modelem teď a `aid-ui-quality.py self <projekt> --place struktura --file
   <kontrola.json>` (soupis požadavků).
6. Kolo místa `struktura` (`aid-ui-quality.py round <projekt> --place struktura --web <adresa kostry>`): role
   proklikávají kostru a čtou model. Klient-role je vlastník produktu a klíčový uživatel, postavená z kódu a zadání
   projektu.
6a. **Co hodnotitelé nechali na klientovi** (nález s `owner: client`, položky readiness) dodá klient-role hned po
   kole: `aid-ui-client.py supply <projekt> --place struktura` (smyčka bez toho další kolo nepustí, decision `supply`).
   Fakt ze souborů projektu se zdrojem `soubor:řádek` a doslovnou citací, kterou kód v souboru najde; volba vlastníka
   jen druhu jméno, výchozí hodnota, pořadí, výběr z možností, s důvodem; co v podkladech není (peníze, termíny,
   právo, osobní údaje, dnešní postup) = `missing` pro PM. Nález, na který klient odpověděl, převezmi (triage) a oprav
   podle odpovědi; hodnotitelé odpovědi vidí v podkladech místa. Co rozhodl klient-agent bez PM:
   `aid-ui-client.py decided <projekt>` - patří do závěrečného hlášení.
7. **Úlohy schvaluje vlastník** (PM 19. 10. 2026): klient-role, která hraje PM jako nezávislý agent v AID runu, nebo
   PM sám (jeho odpověď ji přebije). Otázka druhu `structure`, `part: obrazovky`,
   `target: docs/design/screens.json@<sha256 modelu teď>`. Odpověď agenta studia se nezapíše
   (`app_tasks_need_owner`). Schválení si stav pamatuje s otiskem modelu (`app.approved_model_sha`);
   `aid-ui-state.sh model-approved <projekt>` ověří, že model je ten schválený. Změněný model = kostra znovu jako
   návrh a nová otázka. Výchozí stav existující aplikace a zrušení její dnešní úlohy schvaluje dál jen PM (bod 2 a 4).

## 3. Texty, stavy a vzhled
Kroky 3-5 jako u webu, nad kostrou aplikace: texty obrazovek a všech stavů (hlášky chyb říkají, co se stalo a co dál),
vzory podle oboru aplikace, tři směry vzhledu jako skutečné stránky kostry. Místo `vzhled`.

## 4. Stavba - smlouva s bránou
Postavená aplikace drží dvě věci, na kterých stojí testy úloh a předání:
- každá akce modelu nese `data-aid-action="<obrazovka>.<akce>"` a kořen obrazovky `data-aid-screen="<obrazovka>"`;
- v testovacím režimu (`?aid-test=1`) obrazovka poslechne `?stav=` a ukáže ten stav;
- stav úlohy (`?stav=<úloha>.<stav>`: chyba validace, prázdno, načítání, selhání, oprávnění, obnova) se ukáže tam, kde
  nastává, v bloku `data-aid-task-state="<úloha>.<stav>"`: prázdno na obrazovce prvního kroku, ostatní na obrazovce prvního
  zapisujícího kroku (chyba pole u pole, ne na seznamu před ním);
- akce, která potřebuje záznam (odkaz na záznam, mazání, akce položky, cesta na obrazovku, jejíž prázdno nenastává), se
  v prázdnu, při chybě načtení a při načítání nenabízí; zapisující akce ne při načítání; akce jen pro obnovu (cíl
  `recover`, žádný běžný krok) se ukáže až po selhání;
- akce, která jde jen v některých režimech (`modes` v modelu), je v ostatních neaktivní s větou proč; režim pro test
  nastaví `?rezim=<režim>`.

Čísla v ukázkách, potvrzeních a výsledcích se píšou jako pojmenované hodnoty `{klíč}` (model `values`, každá se
zdrojem): jedno číslo je na jednom místě a čísla téhož obchodu si nemůžou odporovat. Nevratná akce nese texty svých
tlačítek (`confirm_yes`, `confirm_no`), pole své meze (`required`, `min`, `max`, `maxlength`, hláška `error`), odkaz
na záznam svůj parametr (`query`). Graf má v kostře datovou tabulku (`tables`: popisek, sloupce, řádky se stejným
počtem buněk), ne jen větu shrnutí. Akce jedné položky seznamu (Provést u nejistého signálu, Vyřídit u své položky) nese
`item` = řádek ukázky; kostra ji kreslí u něj i s jejími poli, ne pod celým seznamem.
Co platí jen v jednom režimu (stav na Režimu a burze, čekající vstup, který Vypnuto zruší), patří do `mode_sample`
(režim → řádky); kostra ho ukáže jen v tom režimu, ať si ukázka a režim neodporují.
Úloha, která mění režim (STOP, Panika, Vypnout), nese `then_mode` - kostra s výsledkem přepne i režim. Akce, která má smysl
až po jiné úloze (Vrátit po Zahodit), nese `after`. Odkaz ven (appka burzy) je `external`. Pole s rozepsaným textem,
který má přežít zavření karty, má `draft`. Selhání akce kostra ukáže textem `states.failure` její úlohy, ne chybou
načtení obrazovky (u výpadku sítě a odmítnutí serverem každým svým `failure_paths[].text`, je-li). Chování modelu (co appka dělá sama, třeba při odmítnutém SL) se kontroluje i proti plánu a roadmapě
projektu, ne jen proti zadání obrazovek (P116 kolo 5).

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
