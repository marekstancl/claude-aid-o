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
   Písma projektu: `aid-ui-state.sh fonts <project> <URL Google Fonts>`
   (jen `https://fonts.googleapis.com/…`), nebo vlastní písma zkopíruj do
   `docs/brand/fonts/` s CSS `@font-face` a `aid-ui-state.sh fonts <project> docs/brand/fonts/<soubor>.css`.
5. Z `DESIGN.md` vyber role (pozadí, text, akcent; display a body písmo):
   `aid-ui-state.sh roles <project> bg=<c>,ink=<c>,accent=<c>,display=<t>,body=<t>`.
6. Ukázky: `lib/ui-fidelity/ui-capture.mjs` pro každý viewport z
   `aid_ui_proposal_viewports <project>` (`scripts/lib/aid-ui-proposal.sh`),
   `--output-dir <project>/.aid-ui/capture/<viewport>/` (mimo git, neservíruje se).
   Do `docs/brand/assets/` zkopíruj jen PNG snímky, `baseline-computed.json` tam nepatří.
7. Napiš těla kapitol `barvy`, `typografie`, `ukazky` do souborů v `.aid-ui/`
   a zapiš je `aid-ui-state.sh body <project> <id> --file <soubor>` (bez
   `<script>`, `on…=` a `<section>`; `index.html` ručně needituj):
   - `barvy`: vzorník `.swatch` pro každou `--color-*` z `tokens.css`, u každé jméno a hodnota,
   - `typografie`: ukázka textu pro každou roli písma (display, body) jejím písmem, velikostí a váhou,
   - `ukazky`: oba snímky z `assets/` jako `<img>` s popiskem viewportu.
8. Teprve pak `aid-ui-state.sh chapter <project> <id> navrh` pro `barvy`, `typografie`, `ukazky`.
9. Přestavba po dřívějším schválení:
   `aid-ui-state.sh reset-approvals <project> barvy typografie komponenty ukazky`.

## Co PM rozhoduje

Nic, kromě otázek Impeccable (MUST 1).

## Zápis

Kód projektu (Impeccable), `DESIGN.md`, `docs/brand/{tokens.css,roles.css,assets/*.png}`,
`.aid-ui/capture/`, odkazy na písma, těla a stav kapitol `barvy`, `typografie`, `ukazky`.

## Když krok selže

`aid-ui-design-to-css.sh` nebo `roles` skončí 1 → ukaž `ERROR:` PM,
předchozí `tokens.css` zůstává; krok se neposouvá.

**Last Updated:** 2026-09-24
