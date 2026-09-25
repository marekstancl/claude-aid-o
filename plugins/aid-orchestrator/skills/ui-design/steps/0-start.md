---
name: ui-design-step-0
description: /aid-ui step 0 - product type, inventory of what the project already has, the optional parts, and the brand page skeleton
user_invocable: false
---

# Krok 0 - Start

**Last Updated:** 2026-09-25

## Cíl

Typ produktu je zvolený, víme, co projekt už má, PM zvolil volitelné části
kroku 1 a brand stránka `docs/brand/` existuje a běží.

## Vstupy

Projekt: `docs/design/*brand-package*`, `PRODUCT.md`, `DESIGN.md`, `.impeccable/`,
běžící web (`docker ps` podle názvu projektu), zamítnuté návrhy.

## Postup

1. Existuje `docs/design/brand-state.json` → nic nepřepisuj, pokračuj krokem z něj.
   Migrace (migration) z P101 - existuje jen staré `docs/brand/state.json` →
   nejdřív `aid-ui-state.sh init <project>`: přesune stav do
   `docs/design/brand-state.json`, doplní kapitoly a značky do `index.html`;
   pak pokračuj krokem z něj. Body 3-4 (šablona přes `index.html`) se při
   pokračování nikdy nedělají.
2. Inventura: co z Vstupů existuje. Na zamítnuté návrhy se ptej jen, když
   z repa není jasné, které to jsou. `DESIGN.md` z dřívějšího nástroje
   **není** zvolený směr.
3. `aid-ui-state.sh init <project>`.
4. Zkopíruj `brand-page/{index.html,base.css,tokens.css,roles.css}` do
   `docs/brand/`; `__PROJECT__` nahraď názvem projektu (HTML-escapovaným).
5. Do `.gitignore` projektu přidej `.aid-ui/` a `.aid-o/work/companion/`
   (jen chybějící řádky).
6. Brand balíček existuje → tělo kapitoly `logo` s logem do souboru v `.aid-ui/`,
   `aid-ui-state.sh body <project> logo --file <soubor>` a
   `aid-ui-state.sh chapter <project> logo navrh`.
7. `aid-ui-serve.sh brand docs/brand` → URL pro PM.

## Co PM rozhoduje

1. Typ produktu: `presentation` / `webapp` / `mobile` / `combo`, s doporučením
   podle inventury. Zápis `aid-ui-state.sh set <project> product_type '"<typ>"'`.
   Režim Impeccable plyne z tabulky v `SKILL.md`.
2. Volitelné části (běží v kroku 1 před vzory), jedna otázka, u každé
   doporučení z inventury:
   - vize a slogany (`vision`) - doporuč, když projekt nemá vizi produktu;
   - identita (`identity`) - `"new"` (nové logo) doporuč, když chybí brand
     balíček; existuje balíček se zamčeným symbolem → `"package"` (logo se
     nevybírá); jinak `false`;
   - SEO (`seo`) - doporuč u prezentačních webů a webových aplikací s veřejnými
     stránkami;
   - obrázkové návrhy (`images`) - jen když PM chce vidět návrhy jako obrázky.

   Zápis `aid-ui-state.sh set <project> options '{"vision":…,"identity":…,"seo":…,"images":…}'`
   ještě v kroku 0; od kroku 1 skript volby odmítne. Každá zapnutá část má
   svou volbu PM (slogan, logo, seznam stránek) a bez ní skript nepustí krok 2.

## Zápis

`docs/design/brand-state.json` (init, `product_type`, `options`), `docs/brand/*`, `.gitignore`, kapitola `logo`.

## Když krok selže

Ukaž PM řádek `ERROR:` skriptu; krok se neposouvá.

**Last Updated:** 2026-09-25
