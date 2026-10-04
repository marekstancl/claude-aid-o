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

1. Nejdřív `steps/1p-sources.md` (Podklady), ještě než se na cokoli o produktu zeptáš:
   `PRODUCT.md` je jeden z jeho zdrojů, samostatná otázka na `PRODUCT.md` už není. Když
   `PRODUCT.md` chybí, krok 1p vezme ostatní podklady a na chybějící údaje se zeptá otázkou `facts`.
2. Po schválení dokumentu o produktu (`aid-ui-state.sh context-check <project>` projde) tělo
   kapitoly `produkt` (pro koho, co dělá, co nabízí, čím se liší, tón - z
   `docs/content/product-context.md`) do souboru v `.aid-ui/`,
   `aid-ui-state.sh body <project> produkt --file <soubor>` a
   `aid-ui-state.sh chapter <project> produkt navrh`.
3. (Bez otázky navíc: pravdu o produktu PM potvrdil schválením dokumentu v 1p.)
4. Pak v tomto pořadí zapnuté části: `1v` (`steps/1v-vision.md`,
   `options.vision`), `1i` (`steps/1i-identity.md`, `options.identity`),
   `1s` (`steps/1s-seo.md`, `options.seo`). Vize jde první, tón značky
   plyne z ní.

## Co PM rozhoduje

Potvrdí pravdu o produktu schválením dokumentu o produktu v kroku 1p, nebo ho vrátí s opravou.

## Zápis

`PRODUCT.md`, kapitola `produkt`.

## Když krok selže

Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4; krok se neposouvá.

**Last Updated:** 2026-09-28
