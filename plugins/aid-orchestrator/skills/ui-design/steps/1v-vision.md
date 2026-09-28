---
name: ui-design-step-1v
description: /aid-ui sub-step 1v - product vision, brand tone and a slogan the PM confirms on the studio page
user_invocable: false
---

# Krok 1v - Vize, tón a slogan

**Last Updated:** 2026-09-28

## Cíl

Běží jen při `options.vision`. Projekt má vizi (`docs/product-vision.md`),
odstavec o tónu a slogan potvrzený PM ve studiu; kapitola `vize` to nese.
Interní nástroj (`variant.brand` = `none`) může vizi vynechat - důvod do
kapitoly `vize`.

## Vstupy

`PRODUCT.md`, existující vize (`docs/product-vision.md` nebo stránka
v Docusauru), šablona `/opt/eco/docs/docs/ecosystem/templates/product-vision-prompt.md`
(čti živě), brand brief `docs/design/brand-package/brand-brief.md`, je-li.

## Postup

1. Vize existuje → shrň ji jako otázku `vision` ve studiu, nepřepisuj ji.
2. Jinak z šablony vyber povinné body, které `PRODUCT.md` nevyplní, a polož
   je jednou otázkou `facts` (nejvýš osm). Nezodpovězené polož znovu jen ty;
   nikdy nedoplňuj domněnkou.
3. Zapiš `docs/product-vision.md` (vrstva 1, fakta oddělená od hypotéz podle
   šablony). Tón odvoď z vize a z brand briefu (existuje-li); jeden odstavec.
4. Pět sloganů v jazyce projektu jako karty otázky `vision` (`thesis` =
   slogan, `uniqueness` = čím se liší od běžných v oboru); PM vybere kartu,
   vrátí s vlastním sloganem v komentáři, nebo požádá o nové (re-roll).
5. Po `choose`/`approve` tělo kapitoly (jádro vize, tón, zvolený slogan =
   `thesis` karty `choice` ze snímku `cards` odpovědi, ne z payloadu -
   `SKILL.md` „Jak se ptá PM", bod 5; zamítnuté) do souboru v `.aid-ui/`,
   `aid-ui-state.sh body <project> vize --file <soubor>`, pak
   `aid-ui-state.sh chapter <project> vize navrh`.

## Co PM rozhoduje

Odpovědi na otázky vize a slogan - ve studiu. Re-roll nejvýš dvakrát, pak
PM napíše vlastní do komentáře.

## Zápis

`docs/product-vision.md`, kapitola `vize`. Projekt v angličtině: slogany
a kapitola anglicky, zprávy PM česky.

## Když krok selže

Odpověď chybí → odkaz na studio a konec tahu.

**Last Updated:** 2026-09-28
