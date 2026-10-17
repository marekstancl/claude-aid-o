---
name: ui-design-step-1i
description: /aid-ui sub-step 1i - brand brief, three logo concepts made by the adopted logo-design method (method receipt first) that the PM chooses on the studio page, icons rendered through the Playwright MCP, and the checked brand package
user_invocable: false
---

# Krok 1i - Identita a brand balíček

**Vrstva dílny (P113):** `references/local/logo-postup.md` má přednost před fázemi 2–4b (koncepty, generování, kurátorství) a `references/local/pohyb-znacky.md` doplňuje bod 5 o animované logo. **Obrazový model kreslí skici, výslednou značku stav geometricky v kódu** (pravidlo fáze 4 „celé logo kreslí obrazový model“ platí pro skici, ne pro výslednou značku). Karty směrů: `aid-ui-tool.sh logo-sheet --cards`. Místa: `logo` (otázka `identity`) a `pohyb` (guard na `build-record`), kola `aid-ui-quality.py round <projekt> --place logo|pohyb`.

**Last Updated:** 2026-10-07

## Cíl

Běží jen při `options.identity` = `"new"` (nové logo) nebo `"package"`
(existující symbol, jen balíček). Projekt má zadání
`docs/design/brief-logo-favicon.md`, symbol zvolený PM ve studiu a brand
balíček, který prošel kontrolou výstupu šablony; kapitola `logo` to nese.
`variant.brand` = `none` → jen favicona (body 6-7), žádné logo.

## Vstupy

`PRODUCT.md`, `docs/product-vision.md`, šablona
`references/standards/brand-brief-prompt.md` (kopie v pluginu),
`references/brand-icons.js`, `scripts/aid-ui-ico.py`, existující balíček
z inventury kroku 0.

## Převzatý postup na logo

Nové logo vzniká **jen** podle převzatého skillu `references/adopted/logo-design/`
(github.com/kaankiziltug/logo-design-skill, MIT, snímek commitu `0ecf52e`; registr
`references/adopted-sources.md`). Nikdy ne po vlastním citu: 7. 10. 2026 PM zamítl tři
koncepty pro Coufal Clinic nakreslené bez postupu. Soubory snímku:

- vstup a fáze: `references/adopted/logo-design/SKILL.md`, `references/adopted/logo-design/references/process.md`
- zadání a slovní mapa: `references/adopted/logo-design/references/discovery-brief.md`
- typ značky: `references/adopted/logo-design/references/mark-types.md`
- stavba: `references/adopted/logo-design/references/svg-construction.md`,
  `references/adopted/logo-design/references/visual-techniques.md`, `references/adopted/logo-design/references/principles.md`
- barva a písmo (fáze 7): `references/adopted/logo-design/references/color.md`,
  `references/adopted/logo-design/references/typography.md`, `references/adopted/logo-design/references/identity-system.md`
- test, kritika, předání: `references/adopted/logo-design/references/testing-checklist.md`,
  `references/adopted/logo-design/references/critique.md`, `references/adopted/logo-design/references/redesign.md`,
  `references/adopted/logo-design/references/presentation-delivery.md`
- knihovna log (`references/adopted/logo-design/references/library-guide.md`) popisuje, co snímek nenese:
  1 432 log cizích firem (`references/adopted/logo-design/TRADEMARKS.md`) - podbody skillu s
  `search_library.py`, `--refs-industry` a `--refs` se vynechají a zápis kapitoly to řekne
- skripty (Python 3 bez závislostí; `svglib.py` je jejich společná knihovna):
  `references/adopted/logo-design/scripts/svglib.py`, `references/adopted/logo-design/scripts/svg_audit.py`,
  `references/adopted/logo-design/scripts/preview_sheet.py`, `references/adopted/logo-design/scripts/concept_sheet.py`,
  `references/adopted/logo-design/scripts/render_png.py` (hledá Chromium v PATH; bez něj
  `aid-ui-tool.sh png`), `references/adopted/logo-design/scripts/export_variants.py`,
  `references/adopted/logo-design/scripts/presentation_board.py`
- šablony: `references/adopted/logo-design/templates/brand-guidelines-template.md`,
  `references/adopted/logo-design/templates/presentation-spec.example.json`

Stvrzenka: `aid-ui-state.sh method <project> identity` vypíše vstup, process, mark-types,
svg-construction a testing-checklist a zapíše `.aid-ui/method/identity.json`; bez ní studio otázku
`identity` odmítne (`SKILL.md` „Jak se ptá PM", bod 0).

## Rozcestník (co se staví, rozhoduje krok, ne PM)

`python3 scripts/aid-ui-logo-route.py <project> --write` přečte stav a zapíše
`.aid-ui/logo/route.json`: situaci, sloty směrů, kontexty a bodování. Nic z toho se PM neptá
(PM 7. 10. 2026: „to musí říkat ten skill"). Studio pak otázku `identity` přijme jen s jednou kartou
na každý slot (`slot` na kartě). Situace, první shoda platí:

| Situace | Kdy (ze stavu) | Směrů | Sloty (id = stálé označení; každý jiná stavba) |
|---|---|---|---|
| assets | `options.identity` = `package` | 0 | žádný: existující symbol, jen kit (body 5-8) |
| app | `variant.type` = `webapp` nebo `pwa` | 3 | L písmeno (jedna iniciála) nebo monogram (dvě a víc), S abstraktní glyf, P obrazový; symbol první, nápis vedle |
| redesign | `variant.type` = `web` a stažený starý web (`.aid-ui/old-site/*/fetch.json` se stránkou 200) | 5 | R oživení dnešního loga (jen s použitelným `.aid-ui/logo/dnesni-logo.*`: SVG nebo rastr ≥ 400 px; jinak R = nápis navazující barvou a písmem), W nápis, WC nápis + oborový znak v nové formě vepsaný do písmene, WM nápis + monogram/písmeno, WP nápis + obrazový symbol z metafory (bez oboru, bez iniciály) |
| new | `variant.type` = `web`, bez starého webu | 3 | W nápis, WC nápis + znak v písmeni (místní služba: oborový), WP nápis + obrazový symbol |

Pravidla, která route.json nese:
- **Pár vždy:** každý směr = logo s názvem (vodorovné; stojaté jen když ho kontext chce) + symbol +
  malý řez pro 16 px. U nápisového směru (W) je symbol mikroznačka odvozená z iniciál a je tak
  označená - nikdy se nezamění za hlavní myšlenku směru. Písmo názvu se vybírá **tady**: tři
  kandidáti z Google Fonts (OFL, latin-ext), každý ověřený `aid-ui-tool.sh glyph --sample <rodina>
  "<název a všechna písmena jazyka webu>"`, obodovaní proti tónu vize; každý směr má jedno písmo
  s důvodem v `koncepty.md`; písmo vítězného směru přebírá krok Vzhled jako dané (role `display`).
- **Oborový znak:** `variant.local` = true → slot WC nese oborový znak povinně, v nové formě
  (zásada 4 skillu „svěží forma známého znaku"; kreslené klišé je diskvalifikace); jinak znak z vize.
- **Kontexty:** testovací kontexty situace (web: hlavička, záložka 16 px, avatar, tisk; app: ikona
  aplikace, záložka, hlavička, avatar) sjednocené se seznamem „Kde bude značka žít" ze zadání;
  `aid-ui-tool.sh logo-sheet --spec .aid-ui/logo/sheet.json` vykreslí každý směr ve všech
  (`.aid-ui/studio/logo-<slot>.png`) a přehled `logo-prehled.png` s policí konkurence.
- **Police konkurence** (náhrada za nepřevzatou knihovnu): loga konkurentů ze zadání z jejich webů
  do `.aid-ui/refs/competitors/` + `manifest.json` (název, URL, soubor, `state`
  available | header-shot | unavailable | not_provided, selektor). Logo = `<img>` s „logo"
  v src/alt v hlavičce, inline SVG hlavičky, ikona ≥ 192 px, jinak snímek hlavičky; bez jediného
  dostupného je police `not_provided` a přehled to napíše, nic se nevymýšlí. Složka se maže až po
  `record-answer` otázky `identity` (do té doby je důkazem), jako ostatní cizí snímky nikdy do
  `docs/`.
- **Bodování a první karta (deterministické):** nejdřív brány - `svg_audit.py` bez FAIL, test 16 px
  (posouzený), úplný pár, splněný druh slotu, žádné nepřetvořené klišé, licence a latin-ext písma;
  diskvalifikovaný směr nelze doporučit (vrací se do fáze 3-5, jen ten slot, nejvýš dvakrát; pak
  zůstane v `koncepty.md` jako neúspěšný s důvodem a karta nese `risk` „neprošel: …"). Pak pět
  kritérií skillu 0-4 (jasnost myšlenky, odlišnost, jednoduchost, relevance = pochopení v kontextu
  názvu a nabídky, ne podoba s piktogramem, síla v malé velikosti) s důkazem u každého; váhy ze
  situace (web: relevance ×2; app: malá velikost ×2); bonus kontinuity +1 jen slotu R, jen
  s vyjmenovanými zachovanými prvky a jen když registr faktů dokládá recenze ≥ 20 nebo jméno ≥ 3
  roky (`route.json` → `continuity_bonus.eligible`; `null` = nedoloženo, bez bonusu). Nejvyšší
  součet = první karta (`recommend` v sheet.json), shoda: vyšší odlišnost, pak méně bodů křivky
  (`svg_audit`), pak pořadí slotů. Tabulka s body a důkazy je v `koncepty.md`; id slotů se nemění,
  mění se jen pořadí karet.
- **Chybějící vstup** (vize, zadání, název v registru faktů): krok nepokládá otázku, kapitola `logo`
  zůstane `ceka` s důvodem v těle a krok skončí jmenovanou blokací - ne obecným „zeptej se PM".

## Postup

1. Existující balíček → nic nekopíruj podruhé; doplň jen chybějící soubory
   (seznam z `--verify`, bod 6) přímo do něj.
2. Nové logo jen s vizí (krok 1v nebo existující vize); bez ní → řekni PM,
   že logo bez vize nevzniká, a nabídni `"package"`.
3. Zadání: část 1 šablony vyplň z vize a `PRODUCT.md`, část 2 zkrať na
   kontexty použití projektu; ulož `docs/design/brief-logo-favicon.md`.
   Chybí-li údaj, zeptej se PM (`facts`), nedoplňuj domněnkou.
4. `"package"` → symbol je dané SVG; pokračuj bodem 5. `"new"` → nejdřív
   `aid-ui-state.sh method <project> identity` a `aid-ui-logo-route.py <project> --write`
   (Rozcestník výše: situace, sloty, kontexty, bodování), pak fáze 1-6 převzatého skillu
   (`references/adopted/logo-design/SKILL.md` „Design workflow") pro **každý slot** route.json,
   vše v `.aid-ui/logo/`:
   - fáze 1: brief = zadání z bodu 3 + seznam předpokladů (`discovery-brief.md` §5);
   - fáze 2: klišé oboru vypsaná výslovně do `koncepty.md` (zub, úsměv, kříž, zelená
     lékárna…) jako zakázaná bez nové formy; slovní mapa (`discovery-brief.md` §6: název,
     nabídka, přídavná jména, slib → podstatná jména, metafory, opaky; průniky označit);
     aspoň dva typy značek podle `mark-types.md` §12;
   - fáze 3: 8-12 konceptů po jedné větě do `koncepty.md`, každý přiřazený slotu route.json
     a obodovaný (jasnost, odlišnost, jednoduchost, relevance, síla v malé velikosti); do každého
     slotu jde jeho nejsilnější koncept, ostatní zůstávají v souboru jako zamítnuté; slot R začíná
     auditem dnešního loga podle `references/adopted/logo-design/references/redesign.md`
     (co má hodnotu, co zachovat - vyjmenovat);
   - fáze 4 - **celé logo kreslí obrazový model, ne ty** (PM 7. 10. 2026: značky psané jako
     souřadnice SVG byly „výsměch"; 8. 10.: černé symboly bez názvu byly ikonky aplikace -
     pravidlo skillu „nejdřív černě, jen symbol" je pro ruku designéra, modelu se jako omezení
     nedává): do `.aid-ui/logo/gen.json` napiš `mode: "full"`, `name` (jméno značky), `tagline`
     (obor · město, když ho brief chce), `two_step: true` (nejdřív samotný symbol = hotová ikona,
     pak nápis složený kolem přesně toho symbolu - PM 8. 10. 2026: nejlepší z tří zkoušených
     promptů), `typography` (písmo jménem „v duchu …", s licencí k sazbě v bodě 5), `colors`
     (přesné HEX: značka, název, jeden akcent, bílé pozadí), `references` (≤ 16: 6-10 skutečných
     log stejného oboru z přehledů + ukázka, kterou PM poslal jako „takhle ano", viz níže) a pro
     každý slot **zadání art directora** jednou až dvěma větami (anglicky, vlastními slovy: stavba
     značky - co čte první a co druhé, z čeho je sestavená, co musí přežít v 16 px; jméno, obor,
     město - nikdy fakta, ceny, lidi ani text z podkladů; jen tohle a šablony skriptu odcházejí
     k OpenAI), `n` 3-5, `quality` high, `size` 1536×1024 pro lockup. Jednoslovné popisy
     („moderní, čisté") dávají klipart - zadání musí mluvit jako brief od studia: mřížka, jeden
     tah, pravé kruhy, optické korekce, clear space, laťka „co by předložil senior designér".
     `mode: "mark"` (černý symbol, průhledné pozadí) jen pro favicon-first situaci app; `python3 scripts/aid-ui-logo-gen.py <project> --spec .aid-ui/logo/gen.json --dry-run`
     (prompty do `gen/plan.json`, zkontroluj je), pak naostro s klíčem jen pro ten příkaz:
     `export OPENAI_API_KEY="$(grep -m1 '^OPENAI_API_KEY=' /opt/eco/services/.env | cut -d= -f2- | tr -d "\"'")"`
     v téže shellové větě (klíč se nikam nezapisuje, skript ho z chyb maže); `--max-cost` 3 USD
     (medium ≈ 0,04 USD za obrázek; 5 × 6 ≈ 1,3 USD), bez retry, stav v `gen/gen.json`. Běh jiný
     než `succeeded` = doplň jen chybějící sloty (`--force` jen pro přepsání, jinak nic nepřepíše).
   - reference: když PM pošle vlastní ukázku („takhle ano"), ulož ji do `.aid-ui/refs/inspirace/`
     (manifest: od PM, datum) a dej ji jako první referenci; ostatní najdi v přehledech oboru
     (ne u konkurence) a ukaž PM v companionu, generuje se bez čekání (2B), PM je může vyměnit.
   - fáze 4b - **kurátorství** (tvoje práce, podle `testing-checklist.md` a varovných signálů
     skillu jako síta, ne jako omezení kreslení): kontaktní arch `aid-ui-tool.sh logo-sheet
     --contact .aid-ui/logo/gen --out …`, každou variantu si zobraz a zapiš do `gen/vyber.json`
     `{"<slot>": {"chosen": "<soubor>", "rejected": [{"file": …, "reason": …}]}}` - vyřazuje
     zkomolený nebo jiný název, víc než dvě barvy, stín, přechod nebo mockup, klišé bez nové
     formy, symbol nečitelný v malém, nápadná podoba se známou značkou; z každého slotu právě
     jedna; zkomolený text ve všech variantách slotu = re-roll slotu v kvalitě `high`.
     **Karty u `mode full` nesou vygenerovanou kompozici** (rastr, štítek „koncept od modelu";
     `logo-sheet` to dovolí jen s `concept: true` u směru): PM posuzuje hotový dojem, ne
     stavební kámen; ikona v prohlížeči, na telefonu a avatar vzniknou až z vybraného směru.
   - fáze 4c - **vektor** (u `mode full` až po volbě PM, pro zvolený směr; u `mode mark` před
     kartami): `aid-ui-tool.sh vectorize gen/<zvolený>.png <slot>-symbol.svg` (z kompozice
     nejdřív vyřízni symbol: `--crop x,y,w,h` není, použij `Pillow` v `pyvec` venv na výřez
     podle oka a zapiš souřadnice do `koncepty.md`); název se sází znovu skutečným písmem
     (bod 5, `wordmark`), barvy se vezmou z obrázku (dva nejčastější odstíny mimo bílou);
     (binarizace, vtracer; parametry v komentáři SVG; `--speckle`, `--corner` když je tvar
     roztřepený), potom `svg_audit.py` bez FAIL (složitost smí být INFO; při stovkách bodů zvyš
     `--length`), vykreslení 16/32 px a pohled; nesedí-li vektor na koncept (ořez, slitý otvor),
     změň parametry, ne koncept. **Souměrnost (P113a, PM 13. 10. 2026):** `vectorize` vypíše řádek `SYMMETRY`
     a zapíše `<symbol>.svg.json`; pod 0,92 `logo-sheet` značku odmítne, dokud směr neuvede záměr
     (`"asymmetry": "<proč>"`). Nezáměrně křivá značka (useknuté konce, vlnitý obrys) se opraví: jiný koncept, jiný výřez
     nebo parametry, ne vysvětlení. Karta volby značky nese i značku samotnou zvětšenou na 512 px
     (`aid-ui-tool.sh png <symbol>.svg <out>.png 512` jako `preview2`), ať klient posoudí tvar, ne jen 16 px.
     Upřesnění už zvolené značky (např. když ji souměrnost zastaví až po předání) je otázka `identity` s cílem
     `logo:refine:<slot>[@štítek]`: dvě a více variant téhož směru, každá karta se `slot`, a karta „ponechat
     současnou“ s nameranou souměrností jako rizikem. Malý řez pro 16 px uděláš stejně z téhož PNG s vyšším
     `--speckle`, nebo rukou zjednodušením cest. Rukou psané SVG zůstává jen pro mikroznačku
     z iniciál (slot W) a drobné úpravy vektoru.
   - **logo s názvem** (`<slot>-lockup.svg`, výška 256: symbol z vektoru + název písmem slotu;
     v konceptu smí být živý `<text>` s rodinou z Google Fonts, do křivek jde až v bodě 5);
     u `mode full` je lockup na kartě sama kompozice modelu (`lockup` = její PNG). Verze se
     nepřepisují (`-v1`, `-v2`). PNG koncepty v `gen/` smaž po `record-answer` otázky
     `identity` kromě zvoleného (gen.json a vyber.json zůstávají jako záznam).
   - fáze 5 aspoň dvakrát: `python3 references/adopted/logo-design/scripts/svg_audit.py a.svg b.svg c.svg`
     a `python3 references/adopted/logo-design/scripts/preview_sheet.py a.svg b.svg c.svg -o preview.html`
     (bez `--refs-industry`, knihovna není), snímek stránky přes `aid-ui-tool.sh`; co padá,
     oprav (měřítko 16-24 px, optické korekce, rovnováha, zrcadlení a otočení, písmenový
     test, spoje) a pusť znovu - `testing-checklist.md`;
   - fáze 6: `.aid-ui/logo/sheet.json` (formát v hlavičce `lib/ui-fidelity/aid-ui-logo-sheet.mjs`:
     název, písma, směry se `slot` jako `id`, `recommend` = vítěz bodování, konkurence
     z `manifest.json`) a `aid-ui-tool.sh logo-sheet --spec .aid-ui/logo/sheet.json` →
     `.aid-ui/studio/logo-<slot>.png` (hlavička webu, záložka 16 px, ikona na telefonu, avatar,
     vizitka černobíle) a `logo-prehled.png` (všechny směry vedle sebe, doporučený označený,
     police konkurence); doplňkově `concept_sheet.py` skillu, když je k dispozici renderer;
   - **dvě brány u `mode full`:** 1) otázka na směr (karty níže nesou koncept modelu), 2) po volbě
     se směr přestaví (fáze 4c, bod 5: symbol vektor, název skutečným písmem - podtitul vždy znovu
     sazbou, model ho komolí - barvy = dva nejčastější odstíny mimo neutrály) a jde jako **druhá
     otázka `identity`** s jednou kartou: přestavěné logo v hlavičce, záložce, na telefonu, jako
     avatar, na vizitce, v barvě, černě a reverzně; kit (body 5-8) až po jejím `approve`.
     Selhání přestavby (symbol nejde oddělit, audit FAIL, nečitelné v 16 px) = nová karta téhož
     směru z další varianty slotu, nikdy obejití volby PM. Re-roll kvůli zkomolenému názvu nejvýš
     jednou na slot (`high`, samostatný spec s jedním slotem a malým `n`, zbývající rozpočet
     z `gen.json`); dál se název sází. Stažení otázky = odstranění z payloadu (odpovědi a historie
     zůstávají), nová otázka dostane nové id.
   - karty otázky `identity`, **jedna na slot**, v pořadí bodování (první = `recommend`):
     `slot` = id slotu, `preview` = `logo-<slot>.png`, `thesis` = směr jednou větou,
     `method` = druh slotu a typ značky s odkazem na postup (např. „mark-types.md §4 letterform;
     slot WM, koncept 7 z koncepty.md"), `uniqueness` = proti klišé oboru a konkurenci z police,
     `risk` = poctivé riziko (čitelnost v 16 px, podobnost, kontext, kde je slabší), `source` =
     `podklady`. Re-roll PM: jen slot, kterého se komentář týká, stejný druh, nejvýš dvakrát; pak
     slot zůstane s `risk` „neprošel" a nabídka pokračuje bez něj (PM nic nedodává - balíček od
     klienta je volba kroku 0, ne náhradní cesta). Fáze 7 (kit) = body 5-8 níže, po volbě PM.
5. Symbol = karta `choice` ze snímku `cards` zaznamenané odpovědi, ne
   z payloadu, a jen se shodným `preview_sha256` (`SKILL.md` „Jak se ptá PM",
   bod 5). Balíček do `docs/design/brand-package/` podle části 2 šablony:
   `symbol/` (color, black, white, color-on-dark), `source/` (master se
   živým textem + název a licence fontu), vedle distribuční verze s textem
   převedeným na křivky, `brand-brief.md`, `README.md`; `logo/` a `lockup/`
   jen pro kontexty ze zadání: symbol s názvem (hlavička, e-mailový podpis, PDF,
   nabídka, vizitka, tisk) → `logo/` s názvem barevně, u webu nebo tmavého kontextu
   i na tmavém, u tisku i černě, vždy SVG + PNG; PWA → `lockup/` světlý a tmavý.
   Logo s názvem a jeho zdroj vyrábí `aid-ui-tool.sh wordmark --spec .aid-ui/wordmark.json` (z kořene projektu;
   `font` = všechny soubory písma webu, latin i latin-ext, aby šla čeština)
   (symbol z `symbol/` + název písmem webu, výška symbolu = 1,3× výška písmen podle
   `brand-brief.md`; zapíše `source/<base>-master.svg` s živým textem, písmem a licencí,
   `source/<base>-master-outlines.svg` v křivkách a `logo/<base>-<varianta>.svg`; formát
   specifikace je v hlavičce `scripts/aid-ui-wordmark.py`). PNG každé varianty:
   `aid-ui-tool.sh png logo/<soubor>.svg logo/<soubor>.png 1200`. Písmo webu se určuje
   ve výběru vzhledu (krok 5), takže logo s názvem vzniká po něm, nejpozději v kroku 6.
   Co přesně je povinné, vypíše `python3 scripts/aid-ui-brand-package.py <project>`
   (seznam se odvozuje z varianty, `options.identity` a oddílu „Kontexty použití"
   zadání; exit 1 = co chybí). Rozšířená sada (sociální sítě, tiskoviny, e-mailový
   podpis jako hotový soubor) se nevyrábí, dokud ji PM po schválení značky nechce.
6. Ikony: každé SVG pro skript nejdřív projde kontrolou
   `python3 scripts/aid-ui-ico.py --check-svg <symbol.svg> .aid-ui/logo/symbol.checked.svg`
   (mikrovarianta stejně do `micro.checked.svg`). Exit 1 → `WRONG` s důvodem;
   SVG oprav a zkontroluj znovu. `references/brand-icons.js` zkopíruj do
   `.aid-ui/brand-icons.js` a vyplň jen cesty: absolutní cesty ke
   `*.checked.svg` a k `docs/design/brand-package/icons/`, každá odpovídá
   `^/[A-Za-z0-9._/-]+$`. SVG do skriptu nevkládej, skript si ho přečte sám.
   Spusť přes `mcp__plugin_playwright_playwright__browser_run_code_unsafe`
   s `filename` (zapíše PNG). Pak
   `cp .aid-ui/logo/symbol.checked.svg <icons>/favicon.svg`,
   `python3 scripts/aid-ui-ico.py <icons>/favicon.ico <icons>/favicon-16.png <icons>/favicon-32.png <icons>/favicon-48.png`
   a `python3 scripts/aid-ui-ico.py --verify <icons>` (exit 0 = kompletní).
   Varianta `pwa`: ikony pro instalaci (192, 512, maskable) jsou povinné.
7. Kontrola výstupu podle šablony (oddíl „Kontrola výstupu"): čitelnost
   v 16 px na světlém i tmavém (nečitelné → zesílená mikrovarianta pro
   16/32 px, znovu bod 6), validní SVG 1:1 bez rastrových vložek, jen
   bezpečné tvary (to hlídá `--check-svg`), licence fontu, odlišnost od
   značek v oboru (obrazové vyhledání je ruční úkol PM - napiš mu to),
   úplnost vůči kontextům použití.
8. Ikony pro stránku značky zkopíruj do `docs/brand/assets/`. Tělo kapitoly
   (symbol, ikony v reálných velikostech, výsledek kontroly, zamítnuté
   koncepty) do souboru v `.aid-ui/`,
   `aid-ui-state.sh body <project> logo --file <soubor>`, pak
   `aid-ui-state.sh chapter <project> logo navrh`.

## Co PM rozhoduje

Údaje do zadání, jeden ze tří konceptů (ve studiu) a obrazové vyhledání
podobných značek.

## Zápis

`docs/design/brief-logo-favicon.md`, `docs/design/brand-package/`,
`docs/brand/assets/`, kapitola `logo`.

## Když krok selže

- Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4.
- Playwright MCP chybí nebo nezapíše soubory → požádej PM o ikony z ručního
  nástroje podle seznamu z `--verify`, kapitolu `logo` nech `ceka` a v jejím
  těle napiš, co chybí.
- `--verify` skončí 1 → jmenuje chybějící nebo špatně velký soubor; kapitola
  nejde do `navrh`, dokud neprojde.
- `aid-ui-brand-package.py` skončí 1 → doplň jmenovanou část. U balíčku, který dodal
  klient (`identity: "package"`) a část v něm chybí (typicky verze v křivkách), otázka
  `exception` ve studiu s `target` = `aid-ui-state.sh brand-waive-target <project>` (důvod =
  komentář PM), po `approve` `aid-ui-state.sh brand-waive <project> --answer <id>`; výjimka
  platí jen pro přesně ten seznam chybějících částí, bez ní brána (řádek `brand_package`)
  neprojde.

**Last Updated:** 2026-10-07
