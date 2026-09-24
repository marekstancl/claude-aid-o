---
name: ui-design-step-5
description: /aid-ui step 5 - complete DESIGN.md and the project's design standard per the ecosystem checklist
user_invocable: false
---

# Krok 5 - Standard

**Last Updated:** 2026-09-24

## Cíl

Úplný `DESIGN.md` a `docs/design/design-standard.md` projektu podle
ekosystémového checklistu.

## Vstupy

`DESIGN.md`, postavený kód, `/opt/eco/docs/docs/ecosystem/specs/design-system-standard.md`
(čteno živě; chybí → jmenuj to PM a poznamenej v kapitole `platformy`).

## Postup

1. `aid-ui-state.sh require-direction <project>` - exit 1 → stop, jdi na krok 3.
2. Skill `impeccable` `document` (scan mode).
3. `docs/design/design-standard.md`: odkaz na `DESIGN.md` a jen to, co v něm
   chybí - platformní kontrakt, přístupnost, pravidla textů.
4. Kapitola `komponenty`: živá tlačítka, pole a stavy (default, hover, focus,
   disabled, error) z `tokens.css`; kapitola `platformy`: platformní tabulka.
   Obě `aid-ui-state.sh chapter <project> <id> navrh`.
5. `aid-ui-design-to-css.sh DESIGN.md docs/brand/tokens.css`.
6. Kapitoly se změněným obsahem: `aid-ui-state.sh reset-approvals <project> <id>...`.

## Co PM rozhoduje

Nic.

## Zápis

`DESIGN.md` (Impeccable), `docs/design/design-standard.md`, `docs/brand/tokens.css`,
kapitoly `komponenty`, `platformy`.

## Když krok selže

Impeccable `document` skončí chybou → ukaž ji PM; krok se neposouvá.

**Last Updated:** 2026-09-24
