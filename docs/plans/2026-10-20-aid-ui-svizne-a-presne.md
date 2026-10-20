# Zadání: /aid-ui svižné a přesné (P118, verze 2, 20. 10. 2026; PM 20. 10.: 1A hlášení po kole neblokuje, 2A stavba na větvi P116, vydání spolu jako 3.8.0)

Verze 2 zapracovává dva nezávislé posudky verze 1 (Codex; Claude Opus s čistým kontextem, který měřil v kódu, datech
pilotu a přepisu sezení). Co z kterého posudku je, uvádí sloupec „zdroj“ v oddíle Změny.

## Proč (naměřeno na pilotu P116, Trading F1, místo struktura, 6 kol, 18.–20. 10. 2026)

| co | naměřeno |
|---|---|
| kolo 5 → 6 nástěnně | 6 h; z toho 3 h 21 min čekání na PM (pravidlo „stop po každém kole“), 2,5 h aktivní práce |
| brána kostry (`--precheck`) | 51–54 min na běh, 384 kombinací stránka × stav × šířka × 6 kontrol = 2112 výsledků; 4 běhy v kole (2 zabité po změně modelu, 1 červený vlastní chybou, 1 zelený) |
| jeden řádek brány | ~8 s; z toho hlášené kontroly ~1,9 s (načtení + stav 0,65 s, axe 1,2 s); **zbytek ~70–75 % jsou kontroly, které nikdo nečte** (animace 3 s, 4–5 dalších kontextů, ustálení, scroll, snímek) |
| cena smyčky | 264 USD; výrobce (agent) 92 %; mezi koly 5 a 6: 107 tahů, průměr 605 tis. tokenů kontextu na tah; v témže sezení se vyvíjel i plugin |
| kolo rolí | 4–6 min, 2–3 USD |
| nálezy rolí kol 1–6 | 94: 76 řemeslo, 15 fakt, 3 volba; 8 regresí oprav; v kole 6 ~10 ze 14 strojově zjistitelných (počty proti seznamu, slovník, nápověda slibuje, co obrazovka nemá, text modelu ≠ kostra…) |
| vlastní hodnocení výrobce | vždy „9“, role 4,9–8,8 |
| ověřovatel (Sonnet) | našel věcné chyby proti kódu (nejisté vstupy, BE, odmítnutý SL), ale „žádný rozpor“ v 11:14 a role pak 14 nálezů, 4 major |

Příčiny:
1. **Brána měří, co nikdo nechce.** `pageRows` spustí celou stránkovou sadu, když je mezi pojmenovanými kontrolami axe;
   `applies()` neověřuje `want()`. Výsledky se zahodí. (Není to N/A ani nový kontext na řádek – ty stojí ~0 a ~90 ms.)
2. **Celá brána po každé změně**, i když se změnil jeden text; běh nad zastaralou verzí se neukončí sám.
3. **Výrobce pracuje v obřím kontextu a míchá do běhu vývoj pluginu.**
4. **Většina nálezů jsou rozpory uvnitř modelu** (čísla, počty, pojmy, sliby), které jde vyloučit stavbou a lintem;
   menšina jsou věcné chyby proti kódu (model nevzniká z toho, co appka dělá).
5. **Kontroly kvality nejsou spolehlivé:** vlastní známky výrobce, ověřovatel na slabém modelu bez paměti nálezů,
   řádky stavů v bráně ověřují přítomnost textu, ne chování; precheck je vázaný jen na model, ne na kostru a plugin.
6. **Znovuotevření smaže rolím paměť**; kolo bez rolí by pustilo regrese oprav.
7. **Čekání na PM je v čase kola** a hlášení po kole smyčku zastaví.

## Cíl (měřitelný, oddělený od čekání na PM)

Kolo = od verdiktu rolí N do verdiktu N+1, bez čekání na PM (to se měří a hlásí zvlášť).

| | dnes | cíl |
|---|---|---|
| celá brána kostry F1 (p95 z 5 běhů za studena, eco-dev) | 51–54 min | ≤ 5 min |
| brána po změně jedné obrazovky (text / stav) | 51 min | ≤ 1 min; změna sdíleného shellu/CSS spustí všechny dotčené řádky |
| kolo oprav (medián) | 2,5 h aktivně | ≤ 20 min: výrobce ≤ 6, lint+verify ≤ 3, celá brána ≤ 5, role ≤ 6 |
| cena místa struktura (bez vývoje pluginu, ceníkový ekvivalent) | 264 USD | ≤ 40 USD |
| první kolo, obě role (medián 3 slepých hodnocení) | 5,8 / 4,9 | ≥ 8,5 |
| kola do uzavření místa | 6+ | ≤ 2 |
| známé otevřené rozpory nad verzí jdoucí k rolím | 5–15 | 0 (lint + verify); 100 % záchyt zasazené sady |

## Změny

| # | změna | zdroj |
|---|---|---|
| 0 | **Brána měří jen pojmenované kontroly.** `pageRows` volá jen kontroly z `checks.json` (`want(c) && applies(c,m)`); ustálení, animace, snímek, `moreRows` jen když je chce pojmenovaná kontrola. Odhad 51 → ~13 min sekvenčně. Test počítá provedené dílčí kontroly. | Claude K1 |
| 1 | **Souběh** N kontextů (adaptivně podle CPU/RAM, výchozí 6), řádky `parallel-safe` / `serial`; vlastní testovací data a přihlášení na pracovníka. Determinismus = shodné výsledky: 3 běhy při souběhu dají identický výsledek. Červený řádek se jednou přeměří samostatně a hlásí se oba výsledky; jednou za vydání (a v H1) se souběžný běh porovná se sekvenčním řádek po řádku; metrika nestálých řádků ve `status`; skupinové zámky pro řádky, které sdílejí data. | Codex 7, Claude V5 |
| 2 | **Přírůstek bezpečně.** Otisk řádku z deklarovaných vstupů před spuštěním: výřez modelu, scénář, všechny soubory, které stránka načítá (sdílené JS/CSS/shell), generátor kostry a scénářů, `aid-ui-verify.mjs`, `checks.json`, verze prohlížeče a axe, testovací přihlášení. Neznámý vstup = celý běh. Selhání se nikdy nepřebírá. Každý přírůstkový běh náhodně přeměří ~10 % převzatých řádků; nesoulad = celý běh a záznam „chybný převzatý výsledek“ (cíl 0). Celá brána bez převzetí před **každým** kolem rolí a před předáním. | Codex 1, Claude V4 |
| 3 | **Jeden neměnný artefakt kola.** Postavená kostra + scénáře + model dostanou id (otisk); lint, verify, brána a role běží nad stejným id. Běh brány se sám ukončí, když se během něj artefakt změní; nad starým id se nový běh nepustí. | Codex (rozpory), Claude K2 |
| 4 | **Lint modelu z tříd nálezů** v `aid-ui-screens.py check` (sekundy): (a) jedna sada ukázkových dat (obchody, pozice, položky), z níž jsou ukázky, počty a potvrzení šablony – rozpor nevznikne už stavbou (rozšíření `values`); (b) každý pojem z popisků je ve slovníku; (c) tvrzení nápovědy odkazuje na prvek obrazovky; (d) kostra kreslí text modelu doslova; (e) zápisová úloha má oprávnění a selhání sítě i serveru, každá akce má dostupnost ve všech režimech; (f) `purpose` nesmí nést čísla, časy ani pravidla; (g) **registr přijatých nálezů jako regresních kontrol** (selektor + očekávání), běží v `--quick` i v bráně. | Claude K4, V1 |
| 4b | **Trasovací matice, deterministicky** (`aid-ui-screens.py matrix --trace`): požadavek → úloha → kroky → obrazovky → stavy → scénář → řádek brány → výsledek. Lint odmítne požadavek bez úlohy či obrazovky, úlohu bez dosažitelného výsledku, zápisovou úlohu bez obnovy, stav bez řádku brány; matice je součástí podkladů rolí. | Codex 3 |
| 5 | **Fakta appky ze dvou extraktorů** (u existujícího kódu): `docs/design/app-facts.json`; Codex a Claude nezávisle; do faktů jde shoda, rozdíl je otevřená otázka (blokuje verzi 1). Fakt: druh (`observed_current` / `required_target` / `business_rule` / `assumption` / `unknown`), zdroj s druhem a pevnou předností – pro dnešní chování kód > rozhodnutí PM > runbook > roadmapa > zadání, pro cílové chování rozhodnutí PM > zadání > roadmapa; částečně se překrývající zdroje = dva fakty s podmínkami, rozpor stejné přednosti = otevřená otázka; podmínky (režim, událost, výsledek, nežádoucí výsledek), otisk zdrojového úseku (propadne při změně), citace. Chování v modelu jen ve strukturních polích (`states.*`, `failure_paths`, `then_mode`, `done_when`, `confirm*`, `modes`, `disabled_reason`, `values`) s `facts: [id]`; lint odmítne pole chování bez faktu. Zpětné pokrytí: relevantní požadavek podkladů je ve faktu, nebo výslovně vyloučen. | Codex 5, Claude V1, V2 |
| 6 | **Ověřovatel jako nástroj s původem.** `aid-ui-client.py verify <projekt> --place <p>`: pevný model (Codex, záskok Opus – ne Sonnet), vstupy jen od nástroje (artefakt, model, fakty, podklady), výsledek do přidávaného záznamu s otiskem artefaktu, vstupů, promptu, modelu a řádkem v `costs.jsonl`. `self` bere sjednocení otevřených bodů všech běhů nad tímtéž artefaktem; opakování nález nesmaže. Záznamy leží mimo projekt (`~/.local/state/aid-ui/verify/<otisk projektu>/`) a jsou podepsané klíčem mimo projekt (`~/.config/aid-ui/verify.key`, HMAC). Provoz: model a úsilí z cenové tabulky AID (zapsané v záznamu), časový limit 15 min, jedno opakování; neshoda Codex a Opus = sjednocení bodů; podklady jsou v promptu označené jako data, ne pokyny; strop ceny verify za místo 5 USD. Výrobce nic nepíše. Strukturní věci kontroluje lint (deterministicky), verify jen sémantické rozpory a chování proti faktům. Poctivě: brání nedopatření, ne úmyslu; `round` si sám přeměří ~20 náhodných řádků brány a ověří původ záznamu verify. | Codex 6, Claude V3, S3 |
| 7 | **Brána ověřuje chování, ne text.** Řádky stavů úloh kontrolují, co pole tvrdí: vypnuté tlačítko s důvodem (oprávnění, režim), `aria-busy`, zachovaný vstup, režim po úloze, souběh (`conflict` jako druh selhání). | Claude V7 |
| 8 | **Výrobce v čerstvém malém kontextu.** Opravy kola dělá podagent, který dostane jen artefakt, fakty, nálezy kola a výstup lintu/verify (cíl ≤ 100 tis. tokenů na tah); hlavní vlákno řídí a nečte výpisy brány. Během běhu se plugin nemění (verze pluginu v záznamu kola). | Claude K3, Codex 2 |
| 9 | **Delta kolo místo kola bez rolí.** Po opravách role s pamětí dostanou rozdíl a změněné obrazovky a hodnotí dotčená kritéria + jeden regresní průchod celku (~1 USD, 2–3 min). Známka se nepřenáší. Znovuotevření zachová paměť nálezů. | Codex 4, Claude V6 |
| 10 | **Vlastní známky výrobce pryč.** `self` = soupis požadavků + lint + verify bez otevřených bodů + zelená brána nad artefaktem. Levný „rubrikový předběh“ (stejná kritéria, jeden model) smí výrobci ukázat mezery, ale o průchodu nerozhoduje. | Codex 3, Claude S4 |
| 11 | **`--quick` po každé úpravě:** scénáře úloh, axe a klávesnice dotčených obrazovek ve všech jejich stavech, shell; změna sdíleného shellu/CSS přidá jednu obrazovku každého typu a mobil. O kole ani předání nerozhoduje. | Codex 8 |
| 12 | **Čas a cena po fázích ve `status`** (výrobce, lint, verify, brána, role, čekání na PM zvlášť), p50/p95, počet převzatých řádků a chybných převzetí, nestálé řádky; varování při překročení rozpočtu fáze. | Codex 2, Claude S1 |
| 13 | **Hlášení po kole neblokuje** (hlásit a pokračovat), pokud PM nezvolí jinak – viz rozhodnutí. | Claude K2 |

## Mimo rozsah

Měřítka rolí a jejich brány; vzhled a hotová aplikace pilotu (pokračují po vydání, už na nové smyčce); web-local
cesta kromě bodů 0–3 (brána je společná).

## Hotovo když (měří se, ne tvrdí)

- **H1 Brána** (benchmark: model a kostra F1 z 20. 10., commit pluginu zapsaný, eco-dev, 5 běhů za studena):
  celá p95 ≤ 5 min; výsledky šesti pojmenovaných kontrol shodné s dnešním během po řádcích (stejný pass/fail; nepojmenované kontroly se nespouštějí ani dnes nejsou ve výsledku); souběžný běh shodný se sekvenčním;
  3 běhy při souběhu identické; změna textu jedné obrazovky ≤ 1 min; změna sdíleného CSS spustí všechny dotčené řádky;
  vzorek převzatých řádků bez chybného převzetí.
- **H2 Záchyt:** verzovaná sada aspoň 12 zasazených vad, kterou připraví někdo jiný než autor verify (3 věcné z pilotu
  proti kódu, 6 rozporů tříd K4, 3 regrese oprav), dva běhy: lint + verify + brána najdou 100 %, falešné poplachy hlášené
  a ≤ 2.
- **H3 Fakta:** lint odmítne pole chování bez faktu a číslo v `purpose`; verify/fakta odmítnou zastaralý otisk zdroje,
  konflikt zdrojů a citaci, která tvrzení nedokládá (test se špatným výkladem).
- **H4 Původ:** `self`/`round` nepustí kolo bez záznamu verify nástroje nad tímtéž artefaktem; ručně napsaný ani starý
  záznam neplatí; opakovaný běh nález nesmaže.
- **H5 Konec do konce, dvakrát:** struktura F1 Trading od nuly (nová větev, výrobce bez paměti pilotu) **a** jedna
  neviděná aplikace; každá 3× (medián i nejhorší běh): první kolo obě role ≥ 8,5 (medián 3 slepých hodnocení), místo
  uzavřené ≤ 2 kola, kolo ≤ 20 min, cena místa ≤ 40 USD (ceníkový ekvivalent z cenové tabulky AID v den běhu, včetně extrakce faktů a verify, bez vývoje pluginu), 0 chybných převzetí.
- **H6** Sady T0/T1 a /aid-ui zelené; staré pravidlo vlastních známek (`SELF_MIN`, `fix_check`/`whole_check` psané
  výrobcem v SKILL.md a aplikace-postup.md) je pryč; SKILL, postup, Docusaurus `/aid/commands/aid-ui` a CHANGELOG
  popisují novou smyčku (revizor to kontroluje bod po bodu).
