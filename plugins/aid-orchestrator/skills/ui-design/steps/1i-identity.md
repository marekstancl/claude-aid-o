---
name: ui-design-step-1i
description: /aid-ui sub-step 1i - brand brief, three SVG logo concepts the PM chooses on the studio page, icons rendered through the Playwright MCP, and the checked brand package
user_invocable: false
---

# Krok 1i - Identita a brand balíček

**Last Updated:** 2026-10-03

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

## Postup

1. Existující balíček → nic nekopíruj podruhé; doplň jen chybějící soubory
   (seznam z `--verify`, bod 6) přímo do něj.
2. Nové logo jen s vizí (krok 1v nebo existující vize); bez ní → řekni PM,
   že logo bez vize nevzniká, a nabídni `"package"`.
3. Zadání: část 1 šablony vyplň z vize a `PRODUCT.md`, část 2 zkrať na
   kontexty použití projektu; ulož `docs/design/brief-logo-favicon.md`.
   Chybí-li údaj, zeptej se PM (`facts`), nedoplňuj domněnkou.
4. `"package"` → symbol je dané SVG; pokračuj bodem 5. `"new"` → tři koncepty
   jako SVG (geometrický nebo typografický symbol, čtvercový `viewBox`) do
   `.aid-ui/logo/`; náhled každého (16, 32, 180 px a plná velikost, světlý
   i tmavý podklad) jako PNG pod `.aid-ui/studio/`; tři karty otázky
   `identity` (`thesis` = myšlenka symbolu, `uniqueness` = odlišnost od značek
   v oboru). Re-roll nejvýš dvakrát; pak PM dodá symbol sám (`"package"`).
5. Symbol = karta `choice` ze snímku `cards` zaznamenané odpovědi, ne
   z payloadu, a jen se shodným `preview_sha256` (`SKILL.md` „Jak se ptá PM",
   bod 5). Balíček do `docs/design/brand-package/` podle části 2 šablony:
   `symbol/` (color, black, white, color-on-dark), `source/` (master se
   živým textem + název a licence fontu), vedle distribuční verze s textem
   převedeným na křivky, `brand-brief.md`, `README.md`; `logo/` a `lockup/`
   jen pro kontexty ze zadání: symbol s názvem (hlavička, e-mailový podpis, PDF,
   nabídka, vizitka, tisk) → `logo/` s názvem barevně, u webu nebo tmavého kontextu
   i na tmavém, u tisku i černě, vždy SVG + PNG; PWA → `lockup/` světlý a tmavý.
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

**Last Updated:** 2026-10-03
