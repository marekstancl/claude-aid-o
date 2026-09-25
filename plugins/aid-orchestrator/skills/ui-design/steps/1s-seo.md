---
name: ui-design-step-1s
description: /aid-ui sub-step 1s - SEO brief with the page list the PM confirms on a companion page, or store listing copy for mobile apps
user_invocable: false
---

# Krok 1s - SEO zadání

**Last Updated:** 2026-09-25

## Cíl

Běží jen při `options.seo`. Projekt má `docs/seo/brief.md` a seznam stránek
potvrzený PM (`choices.pages`); směr (krok 3) a stavba (krok 4) z nich
vycházejí. U `product_type: mobile` místo toho `docs/seo/store-listing.md`.
Kapitola `seo` to nese.

## Vstupy

`PRODUCT.md`, `docs/product-vision.md` (je-li), standard
`/opt/eco/docs/docs/ecosystem/specs/seo-audit-agent-standard.md` a složka
`/opt/eco/docs/docs/ecosystem/specs/seo/` (čti živě, nekopíruj).

## Postup

1. `product_type: mobile` → `docs/seo/store-listing.md`: název, podtitul,
   popis, klíčová slova, popisky snímků obrazovky. Seznam stránek neběží;
   pokračuj bodem 5.
2. `docs/seo/brief.md` v pořadí standardu: nejdřív indexovatelnost, pak
   obsah a struktura (záměr, dotazy, seznam stránek s H1, title a meta
   description), pak entita, strukturovaná data a připravenost na AI
   vyhledávání. U každé položky „fakt" nebo „odhad"; dotaz je odhad, pokud
   ho nedal PM. Hledanost nevymýšlej.
   - Seznam stránek je markdown tabulka s hlavičkou `| URL | H1 |`: první
     sloupec URL začínající `/`, druhý H1, další sloupce libovolné. Jiné
     tabulky (přesměrování) krok 6 nečte. Z ní čte krok 6
     (`aid-ui-seo-check.py --brief`) a H1 v buildu se musí shodovat přesně:

     | URL | H1 | title | meta description | hlavní dotaz |
     |---|---|---|---|---|
     | / | Pekárna U Mlýna | Pekárna U Mlýna - chleba z kvásku | Kváskový chleba z Brna. | pekárna brno (odhad) |
     | /o-nas | O nás | O nás - Pekárna U Mlýna | Kdo peče váš chleba. | (odhad) |

   - Webová aplikace s veřejným jen přihlášením: brief pokrývá jen veřejné
     stránky, obrazovky aplikace ne.
   - Existující web: současné URL k zachování (přesměrování) dej PM
     k potvrzení.
   - Lokální SEO: bez adresy a otevírací doby v `PRODUCT.md` napiš
     „nepoužito".
3. Obrazovka visual-companion `pages-<n>.html` (nový soubor na každé kolo):
   karta `data-choice` s `data-multiselect` pro každou stránku (URL, H1,
   hlavní dotaz); tlačítko `data-confirm`.
4. Hned po zápisu obrazovky otevři kolo před potvrzením PM:
   `aid-ui-state.sh await-choice <project> --kind pages --screen pages-<n>.html --page-url http://localhost:<port>/`.
   Skončí exit 1 „no confirm on ... yet" - to je v pořádku, kolo je otevřené.
   Pak pošli PM odkaz na stránku a až PM napíše, že potvrdil, spusť stejný
   příkaz znovu. Potvrzení z doby před otevřením kola skript odmítne.
5. Tělo kapitoly do souboru v `.aid-ui/` (potvrzené stránky s H1, nebo
   texty store listingu; co je odhad) a
   `aid-ui-state.sh body <project> seo --file <soubor>`, pak
   `aid-ui-state.sh chapter <project> seo navrh`.

## Co PM rozhoduje

Seznam stránek a URL k zachování. Úprava v chatu → nový `pages-<n>.html`,
nejvýš dvě kola.

## Zápis

`docs/seo/brief.md` nebo `docs/seo/store-listing.md`, `choices.pages`
(jen skript), kapitola `seo`.

## Když krok selže

- `await-choice` skončí `ERROR:` po potvrzení PM → ukaž ho PM; kolo zůstává otevřené, krok 2
  se nepustí.
- Po dvou kolech bez potvrzeného seznamu → polož poslední obrazovku
  `pages-<n>.html` jen s domovskou stránkou (a tlačítkem potvrzení), v chatu
  řekni, že je to minimum pro pokračování, a zapiš ji stejně jako v bodě 4
  (otevři kolo před potvrzením PM, po potvrzení znovu):
  `aid-ui-state.sh await-choice <project> --kind pages --screen pages-<n>.html --page-url http://localhost:<port>/`.
  Bez potvrzení PM běh zůstává v kroku 1 - brána kroku chce `choices.pages`,
  když je SEO zapnuté. Nikdy bez PM. V těle kapitoly `seo` napiš, že seznam
  stránek byl zúžen na domovskou.

**Last Updated:** 2026-09-25
