---
name: ui-design-step-1i
description: /aid-ui sub-step 1i - brand brief, three SVG logo concepts the PM confirms on a companion page, and the checked brand package
user_invocable: false
---

# Krok 1i - Identita a brand balíček

**Last Updated:** 2026-09-25

## Cíl

Běží jen při `options.identity` = `"new"` (nové logo) nebo `"package"`
(zamčený existující symbol, jen balíček). Projekt má vyplněné zadání
`docs/design/brief-logo-favicon.md`, symbol potvrzený PM a brand balíček,
který prošel kontrolou výstupu šablony; kapitola `logo` to nese.

## Vstupy

`PRODUCT.md`, `docs/product-vision.md` (z kroku 1v, jinak existující vize),
šablona `/opt/eco/docs/docs/ecosystem/templates/brand-brief-prompt.md` (čti
živě, nekopíruj), `references/brand-icons.js`, `scripts/aid-ui-ico.py`.

## Postup

1. Zadání: část 1 šablony vyplň z vize a `PRODUCT.md` (tón plyne z vize),
   část 2 zkrať na kontexty použití projektu; ulož
   `docs/design/brief-logo-favicon.md`. Chybí-li údaj, zeptej se PM,
   nedoplňuj domněnkou.
2. `"package"` (šablona „Zamčené vstupy") → žádné koncepty, symbol je dané
   SVG; pokračuj bodem 5.
3. Tři koncepty jako SVG (geometrický nebo typografický symbol, čtvercový
   `viewBox`) do `.aid-ui/logo/`. Obrazovka visual-companion `logo-<n>.html`
   (nový soubor na každé kolo): tři karty `data-choice` bez
   `data-multiselect`, v každé symbol v 16, 32, 180 px a v plné velikosti,
   na světlém i tmavém podkladu; tlačítko `data-confirm`.
4. Po potvrzení PM
   `aid-ui-state.sh await-choice <project> --kind logo --screen logo-<n>.html --page-url http://localhost:<port>/`.
5. Balíček do `docs/design/brand-package/` podle části 2 šablony:
   `symbol/` (color, black, white, color-on-dark), `source/` (master se
   živým textem + název a licence fontu), vedle distribuční verze s textem
   převedeným na křivky, `brand-brief.md`, `README.md`; `logo/` a `lockup/`
   jen pro kontexty ze zadání.
6. Ikony: `references/brand-icons.js` zkopíruj do `.aid-ui/brand-icons.js`
   a vyplň v něm jen cesty: absolutní cestu k SVG symbolu s křivkami,
   případně k mikrovariantě, a k `docs/design/brand-package/icons/`. SVG do
   skriptu nikdy nevkládej, skript si ho přečte sám. Každá cesta musí
   odpovídat `^/[A-Za-z0-9._/-]+$` (bez uvozovek, mezer a `${`), jinou
   nevyplňuj. Spusť přes
   `mcp__plugin_playwright_playwright__browser_run_code_unsafe` s `filename`. Pak
   `python3 scripts/aid-ui-ico.py <icons>/favicon.ico <icons>/favicon-16.png <icons>/favicon-32.png <icons>/favicon-48.png`
   a `python3 scripts/aid-ui-ico.py --verify <icons>` (exit 0 = kompletní).
7. Kontrola výstupu podle šablony (oddíl „Kontrola výstupu"): čitelnost
   v reálných velikostech na světlém i tmavém (16 px nečitelné →
   zesílená mikrovarianta pro 16/32 px, master beze změny, znovu bod 6),
   validní SVG se skutečným poměrem 1:1 a bez rastrových vložek, bezpečné
   SVG (`--verify` z bodu 6 odmítne `favicon.svg` se script, foreignObject,
   iframe, atributem on…, nebo href, který nezačíná `#`), licence
   fontu, odlišnost od značek v oboru (obrazové vyhledání je ruční úkol
   PM - napiš mu to), úplnost vůči kontextům použití.
8. Ikony, které stránka značky ukazuje, zkopíruj do `docs/brand/assets/`.
   Tělo kapitoly do souboru v `.aid-ui/` (zvolený symbol, ikony v reálných
   velikostech, výsledek kontroly, zamítnuté koncepty) a
   `aid-ui-state.sh body <project> logo --file <soubor>`, pak
   `aid-ui-state.sh chapter <project> logo navrh`.

## Co PM rozhoduje

Údaje do zadání, jeden ze tří konceptů a obrazové vyhledání podobných značek.
„jiné: <slovy>" v chatu → tři nové koncepty na novém `logo-<n>.html`, nejvýš
dvě kola; pak PM dodá symbol sám (cesta `"package"`).

## Zápis

`docs/design/brief-logo-favicon.md`, `docs/design/brand-package/`,
`choices.logo` (jen skript), `docs/brand/assets/`, kapitola `logo`.

## Když krok selže

- `await-choice` skončí `ERROR:` → ukaž ho PM; kolo zůstává otevřené, krok 2
  se nepustí.
- Playwright MCP chybí nebo nezapíše soubory → požádej PM o ikony z ručního
  nástroje podle seznamu z `--verify`, kapitolu `logo` nech `ceka` a v jejím
  těle napiš, co chybí.
- `--verify` skončí 1 → jmenuje chybějící nebo špatně velký soubor; oprav ho,
  kapitola nejde do `navrh`, dokud `--verify` neprojde.

**Last Updated:** 2026-09-25
