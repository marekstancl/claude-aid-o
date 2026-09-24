---
name: ui-design-step-4
description: /aid-ui step 4 - Impeccable builds from the locked direction, DESIGN.md becomes the brand page tokens
user_invocable: false
---

# Krok 4 - Stavba

**Last Updated:** 2026-09-24

## Cíl

Vzhled postavený ze zamčeného směru, `DESIGN.md` zapsaný a brand stránka
přebírá postavený vzhled.

## Vstupy

`## Direction contract` od Impeccable, zaznamenaný směr (`state.json.direction`).

## Postup

1. `aid-ui-state.sh require-direction <project>` - exit 1 → stop, jdi na krok 3
   (otevřené kolo: znovu otevři to kolo).
2. Skill `impeccable` new-work, pokračuj ze zamčeného `## Direction contract`.
   Fáze 1 je code-led, kompoziční kolo neběží; kdyby běželo, platí MUST 1.
3. Dokumentátor Impeccable zapíše `DESIGN.md`.
4. `aid-ui-design-to-css.sh DESIGN.md docs/brand/tokens.css`.
5. Z `DESIGN.md` vyber role (pozadí, text, akcent; display a body písmo):
   `aid-ui-state.sh roles <project> bg=<c>,ink=<c>,accent=<c>,display=<t>,body=<t>`.
6. Ukázky: `lib/ui-fidelity/ui-capture.mjs` pro každý viewport z
   `aid_ui_proposal_viewports <project>` (`scripts/lib/aid-ui-proposal.sh`),
   obrázky do `docs/brand/assets/`.
7. `aid-ui-state.sh chapter <project> <id> navrh` pro `barvy`, `typografie`, `ukazky`.
8. Přestavba po dřívějším schválení:
   `aid-ui-state.sh reset-approvals <project> barvy typografie komponenty ukazky`.

## Co PM rozhoduje

Nic, kromě otázek Impeccable (MUST 1).

## Zápis

Kód projektu (Impeccable), `DESIGN.md`, `docs/brand/{tokens.css,roles.css,assets/}`,
kapitoly `barvy`, `typografie`, `ukazky`.

## Když krok selže

`aid-ui-design-to-css.sh` nebo `roles` skončí 1 → ukaž `ERROR:` PM,
předchozí `tokens.css` zůstává; krok se neposouvá.

**Last Updated:** 2026-09-24
