# AID 3.14.0 – stránka průběhu roadmapy a spolehlivý companion (zadání)

Zdroj: rozbor plugin issues 31. 10. 2026, volby PM 10A a C1-C8 (`docs/plans/2026-10-31-roadmapa-plugin-issues.md`),
nález z 1. 11. (jména testů s číslem verze). Studio `/aid-ui` je mimo rozsah (PM 31. 10.: „Studio věci nechci řešit“).

## Proč

1. **Roadmapa (přání PM 30. 10.):** u práce rozdělené do víc plánů PM neví, kde jsme, dokud se nezeptá. Ve WANu
   si agent stránku „Provize – kde jsme“ (`cc/wan/provize-stav`) udržuje ručně a nic nehlídá, že ji další plán
   obnoví. PM ji chce **povinně** u každé roadmapy, obnovenou každým plánem a každým `/aid-do` na téže věci.
2. **Companion (WAN P113, P117, P119, 22.-31. 10.):** v P119 agent stavěl náhled 19 minut, zhruba polovinu na
   obcházení kitu, a odevzdal ho s oknem uříznutým vpravo; orchestrátor ho poslal PM bez prohlédnutí snímků.
   Čtyři překážky kitu se opakují ve dvou až třech plánech (potvrzené chyby).
3. **Jména testů:** standard testů (PM 31. 10.) chce jméno = co test hlídá, nikdy původ. 113 případů v AID nese
   ve jménu číslo verze nebo odkaz na hlášení projektu („3.13.0: …“, „v2.95.5 (WAN #1): …“), kontrola `test_named_after_plan` je nechytá.

## Co se staví (každý bod = jeden krok, revize po kroku)

**R – stránka průběhu roadmapy** (bod 10) [R1-R8]

- **Které plány:** nové pole zadání `roadmapa_dokument: <cesta k dokumentu roadmapy od kořene projektu>`.
  Dosavadní `roadmapa:` zůstává volný text (P113, P114, P117 tam mají větu i cestu s komentářem) a nic nevynucuje,
  stará zadání se nepřepisují (jejich `zadani_sha256`). Lint upozorní (WARN `roadmap_document_unnamed`), když
  `roadmapa:` obsahuje cestu k dokumentu, který stránku má, a `roadmapa_dokument` chybí. `plan-writing.md`:
  dílčí plán roadmapy pole vyplní povinně.
- **Identita:** `init` zapíše do dokumentu řádek `<!-- aid-roadmap-page: id=<slug>-<8 hex> -->` (slug z názvu,
  `[a-z0-9-]`, 8 hex náhodně). Opakovaný `init` id i data ponechá (idempotentní). Jiný dokument se stejným id
  (zkopírovaný řádek) → odmítnutí; záznam drží cestu dokumentu. Přejmenování dokumentu id nemění.
- **Data `<dokument bez .md>.prubeh.json`** (verzovaná, vedle dokumentu). Schéma: `nazev` (titulek stránky,
  1-60 znaků), `stav_k` (`RRRR-MM-DD`), `jednou_vetou` (neprázdný), seznamy `hotovo[{co, lidsky, kde}]`,
  `dal[{co, kdy?}]`, `cisla[{co, hodnota}]`, `chybi[{co, od_koho}]` smí být prázdné, položka má každé pole
  neprázdné; `posledni_zmena: {kdo: P<n>|aid-do|init, co}`. Neznámé pole = chyba. Agent píše jen tenhle soubor.
- **`scripts/aid-roadmap-page.sh`:**
  - `init <dokument> --title "<téma>"` (autor `init`); `publish <dokument> (--plan P<n> | --aid-do)`, bez jednoho
    z nich odmítne; `--plan` musí sedět s `posledni_zmena.kdo`, `--aid-do` s `kdo == aid-do`.
  - Data se načtou **jednou**: z těch bajtů se spočítá `data_sha256`, vykreslí stránka a zveřejní (změna souboru
    během publikování se neprojeví, záznam nese hash toho, co bylo zveřejněno).
  - **Hranice cest (jedna funkce pro init, publish, lint i uzávěr):** dokument, data, vykreslená stránka a složka
    záznamů se převedou na skutečnou cestu (u nového souboru jeho rodič) a musí ležet uvnitř projektu, resp. state
    rootu; cíl zápisu ani žádný jeho rodič nesmí být symlink (ani visící); zápis přes dočasný soubor a přejmenování
    ve stejné složce. Testy i přímým voláním skriptu, s mezerou a `$`, `;`, `` ` `` ve jménu, `../`, symlinkem
    a visícím symlinkem; po testu se mimo projekt nic nezměnilo.
  - Záznam ve state rootu `.aid-o/work/roadmap-pages/<id>/history.jsonl` (přidává se, nikdy nepřepisuje)
    + `current.json`; řádek `{kdo, data_sha256, dokument, at, vysledek: link|local|failed, duvod?}`.
- **Zveřejnění:** `aid-pm-page-publish.sh --kind roadmap --roadmap <id>`, klíč `<project-id>/roadmap-<id>/roadmap`.
  Zveřejní se **i při `AID_PM_PAGES=off`** (povinná stránka, přání PM 30. 10.; ostatní druhy dál ne).
  `local` jen když vydavatel není nastaven; selhání vydavatele je `failed` a exit 1, nikdy `local`.
- **Uzávěr (`plan-close`), matice:** kontrola platí pro řádný uzávěr sloučeného plánu (cesta do `CLOSED` po
  `plan-merge-to-main`) a běží před prvním zápisem uzávěru. Projde, když `history.jsonl` má řádek
  `kdo == P<n>`, `vysledek ∈ {link, local}` a `data_sha256` = blob `.prubeh.json` v **commitu sloučení plánu**
  (ne na dnešním konci větve: pozdější plán P901 smí stránku obnovit a P900 se pak uzavře stále). Jinak
  `REFUSED (roadmap_page_not_refreshed)` + `next:`. `ABORTED`, administrativní uzávěr a opakovaný uzávěr
  `CLOSED` kontrolu nespouští; `--force` ji přeskočí s důvodem v záznamu uzávěru (jako ostatní kontroly uzávěru).
  Návrat po přerušeném uzávěru kontrolu zopakuje.
- **Kořeny:** `roadmapa_dokument` je relativní ke kořeni repa plánu; `publish` čte data z kopie, ve které běží
  (i worktree plánu), záznam píše do state rootu (`aid_state_root`), uzávěr čte data z commitu sloučení; zadání odtud, kde ho čte dnešní FSM (verzované i neverzované zadání pod `.aid-o/`, ověřené proti `zadani_sha256`), regresní případ pro neverzované zadání.
- **Lint:** `roadmap_page_missing` (dokument bez řádku stránky nebo bez dat) a `roadmap_path_invalid` v běžném
  lintu plánu (zadání se tam čte) i v `--zadani`.
- `/aid-do` nad položkou roadmapy: pokyn `publish --aid-do` (**jen pokyn**, `/aid-do` nemá zadání; tak to
  řekne i dokumentace).

**Při stavbě 1. 11. (R):** uzávěr uzná data z commitu sloučení **nebo** z dnešního konce cílové větve (plán, který
zapíše změnu dat až po sloučení, ji jinak nemá kam dát); pořadí P900 → P901 → uzávěr P900 proto drží jen pro data
zapsaná před sloučením. Doklad o doručení, který zapisuje vydavatel vedle stránky (`page.html.published.json`), jde
dál přes `>` bez ochrany proti odkazu (složku záznamů hlídá skript stránky). Administrativní uzávěr kontrolu nepouští
(kód), test na něj chybí — sada administrativního uzávěru staví plán bez plan-final, se zadáním roadmapy nepočítá.

**K1 – náhled bez ořezu** (C1, přání PM 31. 10.) [R9, R10, R17]

1. **Měření** v `shots` po krocích snímku, **před** úpravami pro snímek z K3, jen na viditelných prvcích
   (nenulový obdélník, ne `display:none`/`visibility:hidden`), tolerance 1 px, osa vodorovná:
   a) stránka je širší než okno prohlížeče;
   b) okno (`[role=dialog]`, `[role=alertdialog]`, `dialog[open]`) přesahuje okraj obrazovky;
   c) viditelný potomek okna přesahuje jeho levou nebo pravou hranu a není uvnitř vlastního posouvacího prvku
      (`overflow-x: auto|scroll`) – takový obsah okno ořízne;
   d) potomek okna s `overflow-x: hidden|clip` a `scrollWidth > clientWidth`; jednořádkový text s
      `text-overflow: ellipsis` a záměrně posouvací prvky (`auto|scroll`) projdou.
2. Výsledek `shots/<zobrazení>/<jméno>.check.json`: `{png_sha256, viewport, shot_sha256 (hash položky shots.json),
   clipped: [{pravidlo, prvek (role, jméno, třída), presah_px}]}`. PNG se zapisuje přes dočasný soubor; když snímek
   selže, starý PNG i jeho kontrola se smažou (zastaralý snímek nepřežije). Když běh skončí na nenamockovaném
   volání, kontroly snímků z toho běhu se zapíší jako neplatné (`mocks_missing`) a `show` je odmítne.
3. `show` odmítne: chybějící, nečitelnou nebo nesouhlasící kontrolu (hash PNG, zobrazení, položka `shots.json`)
   u každého použitého snímku a každého dlužného zobrazení; ořez ve snímku možnosti (`moznosti[].snimky`) s výpisem
   snímku, zobrazení a prvku. Ořez v `minule[]` projde jen se zápisem ve `vady_aplikace: [{snimek, popis}]`;
   stránka návrhu ho ukáže jako blok „Vada dnešní aplikace“.
4. `navrh.json` povinně `prohlidka_snimku` (neprázdný text). `show` vypíše `look:` = snímky s okny.
5. Skill: agent si každý snímek prohlédne dřív, než napíše `navrh.json`; vadu existující komponenty opraví ve
   variantě, nebo ji uvede ve `vady_aplikace`. Orchestrátor před odkazem PM otevře `check-*.png` a snímky z `look:`.
6. Společné napodobeniny v `test-companion-kit.bats` (`_proposal`, umělé PNG) dostanou platné kontroly
   a `prohlidka_snimku`; chybějící kontrola je samostatný negativní případ, ne výjimka validátoru.

**K2 – kopie aplikace** (C2, C3, C8 část 1) [R11-R13]

1. **Styly oken (C2):** `proto` zapíše do kopie blok kitu v `proto/.gitignore` (mezi značkami `# aid-companion`):
   `!*/` a pak znovu vyloučené běhové adresáře z `RUNTIME`. Existující `.gitignore` aplikace zůstane, blok se
   připojí; existující kopie bez bloku ho dostane při dalším `proto`. Blok nepočítá jako změna varianty
   (porovnání s manifestem ho vynechá). Funkční důkaz (Tailwind v kopii generuje styly okna) je AC10 na WANu,
   v pluginu Tailwind není.
2. **`copy_extra` (C3):** jedna sdílená funkce spočítá a ověří cílové **soubory** (dnešní kontroly: tajné soubory,
   symlinky, mimo repo, kolize s kitem). `proto` ji volá **před** vrácením běžící kopie: chybějící doplní, změněný
   zdroj zkopíruje znovu, odebranou položku smaže (je kitová); seznam s hashi zapíše do manifestu (`extra`).
   `show` povolí právě tyto soubory: v jejich rodičovských složkách prohlédne každou položku a cokoli jiného odmítne.
3. **Zastaralá kopie a `--refresh` (C8):** `proto` nad existující kopií porovná soubory `ui.dir` s manifestem a před
   vrácením kopie vypíše, kolik se jich změnilo (`stale: N`). `proto --refresh`: zastaví běžící prototyp stejnou
   ověřenou cestou jako `down` (K4), přesune kopii, její manifest a `shots/` do jedné odkladní složky
   `old/<čas>-<pid>/` (jméno se nesmí opakovat, existující → odmítne; `old/` je povolená položka kitu a `show` ji
   nečte), založí novou kopii a spustí ji. Selže-li nový start, stará
   kopie zůstane stranou a chyba řekne kde.

**K3 – snímky** (C4, C7) [R14]

1. **Celá stránka (C4):** `capture: "full"` – prvky s `position: fixed|sticky` po dobu snímku `static`;
   `capture: {scroll}` – uvolní i předky s `overflow: hidden` nebo pevnou výškou. Návrat stylů vždy ve `finally`.
2. **Síťová chyba (C7):** jednotka opakování je snímek × zobrazení. Jen chyba navigace `net::ERR_*` se zopakuje
   jednou, v novém kontextu se stejnými cookies a `localStorage` ze `shots.json` (stav z prvního pokusu se nepřenese),
   se seznamem nenamockovaných volání vráceným na stav před snímkem.
   Druhé selhání a jakákoli jiná chyba sadu zastaví jako dnes; hotové snímky zůstanou.
   `shots --only <jméno>[,<jméno>]`: jen jmenované (jiné jméno odmítne), ostatní snímky a jejich kontroly se nemění.

**K4 – start, stop a skill** (C5, C6, C8 část 2) [R15]

1. **Start bez brainstormu (C5):** chyba `up` (`start-server.sh` ř. 94) i skill řeknou celý příkaz
   `aid-brainstorm-state.sh init <P> --scope user_visible --topic-kind ui --no-worktree`.
2. **`--configLoader runner` (C6):** skill: nejdřív výchozí načítání; runner jen pro konfiguraci bez `__dirname`.
3. **`down` (C8):** prototyp se pozná podle záznamu: číselné `pid` a `pgid` větší než 1, `pgid == pid` (vedoucí
   skupiny, kterou kit spustil), shodný čas startu – **ne** podle jména programu (`npx` běží jako `npm exec`).
   SIGTERM skupině, do 5 s čekat na prázdnou skupinu, pak SIGKILL; záznam se smaže, až je skupina pryč a port
   zavřený, jinak zůstane s hláškou. Test: dev server spuštěný přes obal s jiným jménem a potomkem; port zavřený,
   potomek mrtvý, cizí skupina žije; dnešní negativní test recyklovaného pid zůstane.

**J – jména testů bez čísla verze** [R16]

- Zakázáno ve jménu `@test` (jedna gramatika): úvodní verze `^v?[0-9]+\.[0-9]+(\.[0-9]+)?[: ]` („3.13.0: …“,
  „v2.95.5 (WAN #1): …“), verze v závorce `\(v?[0-9]+\.[0-9]+(\.[0-9]+)?\)`, odkaz na hlášení projektu v závorce
  (`(WAN …)`, `(agents …)`, `(ACTA …)`, `(APPS …)`) a dnešní odkazy na plán (`P<n>`, `IMP-`). Povolená je verze jako
  předmět testu uvnitř věty („a 3.13 record“, „a 1.1 record“).
- Audit: `grep -rhE '^@test "(v?[0-9]+\.[0-9]+(\.[0-9]+)?[: ]|[^"]*\(v?[0-9]+\.[0-9]+(\.[0-9]+)?\)|[^"]*\((WAN|agents|acta|ACTA|APPS)[^)]*\))' scripts/tests/bats`
  před (1. 11.: 113) a po (0). Přejmenovat na to, co případ hlídá.
- `aid_test_names_plan_refs` (`lib/aid-test-tier.sh`) chytí obě nové podoby v nových jménech; test povoleného
  i zakázaného tvaru včetně `v`.

## Dokumentace a úklid (v kroku, kterého se týká)

- R: `skills/pipeline.md` (dvě nové třídy odmítnutí), `commands/aid-plan.md` + `skills/plan-writing.md` (init při
  zápisu roadmapy), `commands/aid-do.md` (publish), `defaults/templates/zadani.md` (pole `roadmapa:` už není bez
  účinku), `defaults/.gitignore` + blok v `commands/aid-init.md` + `test-gitignore-runtime` (`roadmap-pages`),
  README pluginu (nový skript).
- K1-K4: `skills/visual-companion/SKILL.md` (nová pole `navrh.json`, `--only`, `--refresh`, kontrola ořezu,
  start bez brainstormu, runner).
- Nové sady testů pojmenované podle předmětu (`test-roadmap-page.bats`), změny companionu jako nové případy do
  `test-companion-kit.bats`; žádné jednorázové kontroly v repu.

## Co se nemění

- Studio `/aid-ui`, stránky plánu, uzávěru a brainstormu (dál vypnuté, na požádání přes share).
- Kit se dál spouští jedním příkazem; agent dál píše jen `mocks.json`, `shots.json`, `navrh.json` a varianty,
  nově navíc `.prubeh.json` u roadmapy.
- Plán bez `roadmapa:` se chová jako dnes.

## Hotovo, když

- AC1 (R): `init` na zkušebním dokumentu založí data a řádek se stránkou, druhý `init` nic nezmění; `publish --plan
  P900` zapíše řádek historie; `<script>` z dat je na stránce escapovaný; zkopírovaný řádek id v jiném dokumentu
  odmítne. Nová sada `test-roadmap-page.bats`.
- AC2 (R): hranice cest – přímé volání s `../`, symlinkem, visícím symlinkem a jmény s mezerou a `$;\``; mimo
  projekt se nic nezmění; lint plánu i `--zadani` hlásí `roadmap_page_missing` a `roadmap_path_invalid`; staré tvary
  `roadmapa:` (P113, P114, P117) projdou beze změny.
- AC3 (R): `plan-close` řádného uzávěru odmítne bez obnovené stránky a projde po `publish`; pořadí P900 → P901 →
  uzávěr P900 projde; `failed` se nepočítá; ABORTED, administrativní a opakovaný uzávěr beze změny; `--force`
  zapíše důvod. Registr odmítnutí a jeho test zelené.
- AC4 (R): `--kind roadmap` zveřejní i při `AID_PM_PAGES=off`, ostatní druhy ne; selhání vydavatele = exit 1
  a `failed`.
- AC5 (K1): vzorová stránka v sadě kitu: správné okno projde, skryté okno se nehodnotí, posouvací tabulka v okně
  projde, ořez v okně a přetečení na telefonu se nahlásí; `show` odmítne ořez v možnosti, chybějící a zastaralou
  kontrolu; `vady_aplikace` projde a blok je na stránce (Playwright).
- AC6 (K2): blok `.gitignore` v nové i existující kopii, původní `.gitignore` aplikace zachovaný; `copy_extra`
  přidané, změněné i odebrané po prvním `proto` se srovná a `show` odmítne nepovolený soubor vedle povoleného;
  `--refresh` běžící kopie zastaví starou skupinu a odloží kopii, manifest i snímky, opakované `--refresh` nekoliduje
  a `--refresh` → `shots` → `show` projde.
- AC7 (K3): `capture: full` na stránce s pevnou lištou má lištu jednou; styly se vrátí i po selhání snímku;
  napodobená síťová chyba prvního pokusu se zopakuje (i po kroku, který změnil cookie nebo úložiště), druhá
  a nesíťová chyba ne; po nenamockovaném volání `show` snímky odmítne; `--only` nechá ostatní snímky.
- AC8 (K4): viz K4.3.
- AC9 (J): audit vrátí 0; kontrola jmen odmítne nový `3.14.0: …` i `(v3.14.0)` a pustí „a 3.13 record“.
- AC10 (WAN, **podmínka vydání**, provádí agent vydání před sloučením): plugin z archivu vydávaného commitu
  (`AID_PLUGIN_PATH` na něj) nad WAN kolem companionu (P119 nebo nové `P9xx` bez worktree): `up`, `proto`, `shots`,
  `show` bez obchvatu; okna v kopii mají zaoblení a šířku jako v aplikaci (počítaný styl dialogu = aplikace);
  ořez okna převodu klienta (`OwnerReassignDialog`) je nahlášený. Do WAN repa se nic necommitne, běhové soubory
  v `.aid-o/work/companion/` se po ověření smažou. Neúspěch = oprava, ne vydání.
- AC11: T0 + T1 zelené, dotčené sady T2 zelené (vyjmenované v hlášení, včetně napodobenin), testbed
  `bin/verify.sh --plugin <archiv vydávaného commitu>` zelený s commitem v hlášení, `verify-version-files.sh 3.14.0`
  PASS, CHANGELOG, roadmapa HOTOVO.

## Pořadí kroků

J (mechanické, malé) → K4 → K2 → K3 → K1 → R. Companion jde od nejmenšího, protože K1 stojí na snímcích z K3;
R je největší a nezávislý.
