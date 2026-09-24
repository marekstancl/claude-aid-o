---
name: ui-design-step-0
description: /aid-ui step 0 - product type, inventory of what the project already has, and the brand page skeleton
user_invocable: false
---

# Krok 0 - Start

**Last Updated:** 2026-09-24

## Cíl

Typ produktu je zvolený, víme, co projekt už má, a brand stránka `docs/brand/`
existuje a běží.

## Vstupy

Projekt: `docs/design/*brand-package*`, `PRODUCT.md`, `DESIGN.md`, `.impeccable/`,
běžící web (`docker ps` podle názvu projektu), zamítnuté návrhy.

## Postup

1. Existuje `docs/brand/state.json` → nic nepřepisuj, pokračuj krokem z něj.
2. Inventura: co z Vstupů existuje. Na zamítnuté návrhy se ptej jen, když
   z repa není jasné, které to jsou. `DESIGN.md` z dřívějšího nástroje
   **není** zvolený směr.
3. `aid-ui-state.sh init <project>`.
4. Zkopíruj `brand-page/{index.html,base.css,tokens.css,roles.css}` do
   `docs/brand/`; `__PROJECT__` nahraď názvem projektu (HTML-escapovaným).
5. Do `.gitignore` projektu přidej `.aid-ui/` a `.aid-o/work/companion/`
   (jen chybějící řádky).
6. Brand balíček existuje → vlož logo do kapitoly `logo` a
   `aid-ui-state.sh chapter <project> logo navrh`.
7. `aid-ui-serve.sh brand docs/brand` → URL pro PM.

## Co PM rozhoduje

Typ produktu: `presentation` / `webapp` / `mobile` / `combo`, s doporučením
podle inventury. Zápis `aid-ui-state.sh set <project> product_type '"<typ>"'`.
Režim Impeccable plyne z tabulky v `SKILL.md`.

## Zápis

`state.json` (init, `product_type`), `docs/brand/*`, `.gitignore`, kapitola `logo`.

## Když krok selže

Ukaž PM řádek `ERROR:` skriptu; krok se neposouvá.

**Last Updated:** 2026-09-24
