---
name: ui-design-step-1i
description: /aid-ui sub-step 1i - brand brief, three logo concepts made by the adopted logo-design method (method receipt first) that the PM chooses on the studio page, icons rendered through the Playwright MCP, and the checked brand package
user_invocable: false
---

# Krok 1i - Identita a brand balíček

**Last Updated:** 2026-10-07

## Cíl

Běží jen při `options.identity` = `"new"` (nové logo) nebo `"package"`
(existující symbol, jen balíček). Projekt má zadání
`docs/design/brief-logo-favicon.md`, symbol zvolený PM ve studiu a brand
balíček, který prošel kontrolou výstupu šablony; kapitola `logo` to nese.
`variant.brand` = `none` → jen favicona (body 6-7), žádné logo.

## Vstupy

`PRODUCT.md`, `docs/product-vision.md`, šablona
`/opt/eco/docs/docs/ecosystem/templates/brand-brief-prompt.md` (čti živě),
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

## Postup

1. Existující balíček → nic nekopíruj podruhé; doplň jen chybějící soubory
   (seznam z `--verify`, bod 6) přímo do něj.
2. Nové logo jen s vizí (krok 1v nebo existující vize); bez ní → řekni PM,
   že logo bez vize nevzniká, a nabídni `"package"`.
3. Zadání: část 1 šablony vyplň z vize a `PRODUCT.md`, část 2 zkrať na
   kontexty použití projektu; ulož `docs/design/brief-logo-favicon.md`.
   Chybí-li údaj, zeptej se PM (`facts`), nedoplňuj domněnkou.
4. `"package"` → symbol je dané SVG; pokračuj bodem 5. `"new"` → nejdřív
   `aid-ui-state.sh method <project> identity`, pak fáze 1-6 převzatého skillu
   (`references/adopted/logo-design/SKILL.md` „Design workflow"), vše v `.aid-ui/logo/`:
   - fáze 1: brief = zadání z bodu 3 + seznam předpokladů (`discovery-brief.md` §5);
   - fáze 2: klišé oboru vypsaná výslovně do `koncepty.md` (zub, úsměv, kříž, zelená
     lékárna…) jako zakázaná bez nové formy; slovní mapa (`discovery-brief.md` §6: název,
     nabídka, přídavná jména, slib → podstatná jména, metafory, opaky; průniky označit);
     aspoň dva typy značek podle `mark-types.md` §12;
   - fáze 3: 8-12 konceptů po jedné větě napříč typy značek do `koncepty.md`, každý
     s bodováním (jasnost, odlišnost, jednoduchost, relevance, síla v malé velikosti); tři
     nejsilnější a nejodlišnější se staví, ostatní zůstávají v souboru jako zamítnuté;
   - fáze 4: u každého nejdřív stavba slovy (tvary, poloměry, úhly, mřížka), pak SVG černě
     na bílé podle `svg-construction.md`: `viewBox="0 0 256 256"`, málo bodů, úhly
     0/15/30/45/60/90°, díry přes `fill-rule="evenodd"`, žádný `<text>`; verze
     `a-v1.svg`, `a-v2.svg`… se nepřepisují;
   - fáze 5 aspoň dvakrát: `python3 references/adopted/logo-design/scripts/svg_audit.py a.svg b.svg c.svg`
     a `python3 references/adopted/logo-design/scripts/preview_sheet.py a.svg b.svg c.svg -o preview.html`
     (bez `--refs-industry`, knihovna není), snímek stránky přes `aid-ui-tool.sh`; co padá,
     oprav (měřítko 16-24 px, optické korekce, rovnováha, zrcadlení a otočení, písmenový
     test, spoje) a pusť znovu - `testing-checklist.md`;
   - fáze 6: `python3 references/adopted/logo-design/scripts/concept_sheet.py a.svg b.svg c.svg --names … --notes … --recommend N --greyscale -o .aid-ui/studio/logo-koncepty.png`
     (`render_png.py` potřebuje Chromium v PATH; jinak náhledy přes `aid-ui-tool.sh png`) a
     náhled každého konceptu (16, 32, 180 px a plná velikost, světlý i tmavý podklad) jako
     PNG pod `.aid-ui/studio/`;
   - tři karty otázky `identity`: `thesis` = koncept jednou větou, `method` = typ značky
     a odkud (např. „mark-types.md: letterform; koncept 7 z koncepty.md"), `uniqueness` =
     proti klišé oboru a konkurenci ze zadání, `risk` = poctivé riziko (čitelnost v 16 px,
     podobnost), `source` = `podklady`; první je doporučená. Re-roll nejvýš dvakrát (zpět
     do fáze 3-5); pak PM dodá symbol sám (`"package"`). Fáze 7 (kit) = body 5-8 níže, až
     po volbě PM.
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
