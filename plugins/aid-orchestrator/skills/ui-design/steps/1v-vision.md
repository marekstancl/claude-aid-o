---
name: ui-design-step-1v
description: /aid-ui sub-step 1v - product vision, brand tone and a slogan the PM confirms on a companion page
user_invocable: false
---

# Krok 1v - Vize, tón a slogan

**Last Updated:** 2026-09-25

## Cíl

Běží jen při `options.vision` = true. Projekt má vizi produktu
(`docs/product-vision.md`), odstavec o tónu a slogan potvrzený PM; kapitola
`vize` to nese.

## Vstupy

`PRODUCT.md`, existující vize (`docs/product-vision.md` nebo stránka
v Docusauru), šablona `/opt/eco/docs/docs/ecosystem/templates/product-vision-prompt.md`
a `/opt/eco/docs/docs/ecosystem/specs/voice-standard.md` (obojí čti živě,
nekopíruj).

## Postup

1. Vize už existuje → shrň ji a nech PM potvrdit, nepřepisuj ji.
2. Jinak z šablony vyber povinné body, které `PRODUCT.md` nevyplní, a polož
   je v jedné zprávě (nejvýš osm otázek). Vyplní-li `PRODUCT.md` všechno,
   jen potvrzení. Nezodpovězené otázky polož znovu jen ty; odpověď nikdy
   nedoplňuj domněnkou.
3. Zapiš `docs/product-vision.md` (jen vrstva 1, fakta oddělená od hypotéz
   podle šablony) a odstavec o tónu (tón plyne z vize).
4. Pět sloganů v jazyce projektu (`voice-standard.md`) na obrazovku
   visual-companion `slogan-<n>.html` (nový soubor na každé kolo): karty
   `data-choice` bez `data-multiselect`, pole `data-confirm-text` pro vlastní
   slogan, tlačítko `data-confirm`.
5. Hned po zápisu obrazovky otevři kolo před potvrzením PM:
   `aid-ui-state.sh await-choice <project> --kind slogan --screen slogan-<n>.html --page-url http://localhost:<port>/`.
   Server obrazovek (pokud ještě neběží) spusť přesně jako krok 2 (`steps/2-references.md`, včetně příznaků pro přístup přes VPN).
   Skončí exit 1 „no confirm on ... yet" - to je v pořádku, kolo je otevřené.
   Pak pošli PM odkaz na stránku a až PM napíše, že potvrdil, spusť stejný
   příkaz znovu. Potvrzení z doby před otevřením kola skript odmítne.
6. Tělo kapitoly do souboru v `.aid-ui/` (jádro vize, tón, zvolený slogan,
   seznam zamítnutých) a
   `aid-ui-state.sh body <project> vize --file <soubor>`, pak
   `aid-ui-state.sh chapter <project> vize navrh`.

## Co PM rozhoduje

Odpovědi na otázky vize a jeden slogan. „jiné: <slovy>" → pět nových
sloganů na novém `slogan-<n>.html`, nejvýš dvě kola, pak PM napíše vlastní
do pole na stránce.

## Zápis

`docs/product-vision.md`, `choices.slogan` (jen skript), kapitola `vize`.
Projekt v angličtině: slogany a text kapitoly anglicky, zprávy PM česky.

## Když krok selže

`await-choice` skončí `ERROR:` po potvrzení PM → ukaž ho PM; kolo zůstává otevřené, krok 2
se nepustí.

**Last Updated:** 2026-09-25
