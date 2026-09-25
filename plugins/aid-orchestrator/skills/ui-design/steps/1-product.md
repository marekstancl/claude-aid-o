---
name: ui-design-step-1
description: /aid-ui step 1 - PRODUCT.md confirmed or created through Impeccable init
user_invocable: false
---

# Krok 1 - Produkt

**Last Updated:** 2026-09-25

## Cíl

`PRODUCT.md` existuje a PM ho potvrdil.

## Vstupy

`PRODUCT.md` projektu, typ produktu a `options` z `docs/design/brand-state.json`.

## Postup

1. `PRODUCT.md` existuje → shrň ho do tří odrážek (pro koho, co dělá, tón).
2. Chybí → Skill `impeccable` s `init`; na chybějící údaje se ptá Impeccable.
3. Shrnutí vlož do kapitoly `produkt` a
   `aid-ui-state.sh chapter <project> produkt navrh`.
4. Pak v tomto pořadí zapnuté volitelné části: `1v` (`steps/1v-vision.md`,
   `options.vision`), `1i` (`steps/1i-identity.md`, `options.identity`),
   `1s` (`steps/1s-seo.md`, `options.seo`). Vize jde první, tón značky
   se odvozuje z ní.

## Co PM rozhoduje

Potvrdí shrnutí, nebo ho opraví (oprava jde do `PRODUCT.md`).

## Zápis

`PRODUCT.md` (jen Impeccable nebo oprava PM), kapitola `produkt`.

## Když krok selže

Impeccable `init` skončí chybou → ukaž ji PM, krok se neposouvá.

**Last Updated:** 2026-09-25
