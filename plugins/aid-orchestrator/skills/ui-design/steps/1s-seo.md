---
name: ui-design-step-1s
description: /aid-ui sub-step 1s - SEO brief per the ecosystem SEO standard with the page list the PM confirms on the studio page
user_invocable: false
---

# Krok 1s - SEO zadání

**Last Updated:** 2026-09-28

## Cíl

Běží jen při `options.seo`. Projekt má `docs/seo/brief.md` podle SEO
standardu a seznam stránek potvrzený PM ve studiu; struktura (krok 2)
a stavba (krok 6) z něj vycházejí. Kapitola `seo` to nese.

## Vstupy

`PRODUCT.md`, `docs/product-vision.md` (je-li), `variant`, standard
`/opt/eco/docs/docs/ecosystem/specs/seo-audit-agent-standard.md` a složka
`/opt/eco/docs/docs/ecosystem/specs/seo/` (čti živě, nekopíruj).

## Postup

1. `docs/seo/brief.md` v pořadí standardu: indexovatelnost, pak obsah
   a struktura (záměr, dotazy, seznam stránek s H1, title a meta
   description), pak entita, strukturovaná data a připravenost na AI
   vyhledávání. U každé položky „fakt" nebo „odhad"; dotaz je odhad, pokud
   ho nedal PM. Hledanost nevymýšlej.
   - Seznam stránek je markdown tabulka s hlavičkou `| URL | H1 |` (první
     sloupec URL začínající `/`, druhý H1, další libovolné); z ní čte
     `aid-ui-seo-check.py --brief` a H1 v buildu se musí shodovat přesně:

     | URL | H1 | title | meta description | hlavní dotaz |
     |---|---|---|---|---|
     | / | Pekárna U Mlýna | Pekárna U Mlýna - chleba z kvásku | Kváskový chleba z Brna. | pekárna brno (odhad) |

   - `webapp` s veřejným jen přihlášením: brief pokrývá jen veřejné stránky.
   - Existující web: současné URL k zachování (přesměrování) patří do otázky.
   - `variant.local` = `false` → lokální SEO „nepoužito".
2. Otázka `seo_brief` ve studiu: `body` = seznam stránek (URL, H1, hlavní
   dotaz, fakt/odhad) a URL k zachování; `target` = `docs/seo/brief.md@<sha256
   souboru>`. `return` s komentářem → uprav brief, otevři znovu (nejvýš dvě
   kola, pak nabídni jen domovskou stránku jako minimum - nikdy bez PM).
3. Po `approve` tělo kapitoly (potvrzené stránky s H1, co je odhad) do
   souboru v `.aid-ui/`, `aid-ui-state.sh body <project> seo --file <soubor>`,
   pak `aid-ui-state.sh chapter <project> seo navrh`.

## Co PM rozhoduje

Seznam stránek a URL k zachování - ve studiu.

## Zápis

`docs/seo/brief.md`, kapitola `seo`.

## Když krok selže

Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4; bez potvrzeného seznamu krok 2
nezačne.

**Last Updated:** 2026-09-28
