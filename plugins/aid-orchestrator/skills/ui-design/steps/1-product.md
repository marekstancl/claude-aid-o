---
name: ui-design-step-1
description: /aid-ui step 1 - product truth confirmed on the studio page, then the optional vision, identity and SEO brief
user_invocable: false
---

# Krok 1 - Produkt

**Last Updated:** 2026-09-28

## Cíl

`PRODUCT.md` říká pravdu o produktu a PM ji ve studiu potvrdil; pak proběhly
zapnuté volitelné části.

## Vstupy

`PRODUCT.md`, `variant` a `options` z `docs/design/brand-state.json`,
inventura z kroku 0.

## Postup

1. `PRODUCT.md` existuje → shrň ho (pro koho, co dělá, co nabízí, čím se
   liší, tón). Chybí → polož PM chybějící údaje jednou otázkou ve studiu
   (`kind` `facts`, nejvýš osm bodů) a z odpovědí `PRODUCT.md` napiš.
   Nic nedoplňuj domněnkou (MUST 5).
2. Shrnutí jako otázka `facts` ve studiu (`target` = `PRODUCT.md@<sha256
   souboru>`); `return` s komentářem → oprav `PRODUCT.md`, otevři znovu.
3. Po `approve` tělo kapitoly `produkt` do souboru v `.aid-ui/`,
   `aid-ui-state.sh body <project> produkt --file <soubor>` a
   `aid-ui-state.sh chapter <project> produkt navrh`.
4. Pak v tomto pořadí zapnuté části: `1v` (`steps/1v-vision.md`,
   `options.vision`), `1i` (`steps/1i-identity.md`, `options.identity`),
   `1s` (`steps/1s-seo.md`, `options.seo`). Vize jde první, tón značky
   plyne z ní.

## Co PM rozhoduje

Potvrdí pravdu o produktu, nebo ji vrátí s opravou.

## Zápis

`PRODUCT.md`, kapitola `produkt`.

## Když krok selže

Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4; krok se neposouvá.

**Last Updated:** 2026-09-28
