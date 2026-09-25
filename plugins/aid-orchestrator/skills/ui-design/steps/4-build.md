---
name: ui-design-step-4
description: /aid-ui step 4 - Impeccable builds from the locked direction, DESIGN.md becomes the brand page tokens
user_invocable: false
---

# Krok 4 - Stavba

**Last Updated:** 2026-09-25

## Cíl

Vzhled postavený ze zamčeného směru, `DESIGN.md` zapsaný a brand stránka
přebírá postavený vzhled.

## Vstupy

`## Direction contract` od Impeccable, zaznamenaný směr (`state.json.direction`).

## Postup

1. `aid-ui-state.sh require-direction <project>` - exit 1 → stop, jdi na krok 3
   (otevřené kolo: znovu otevři to kolo).
2. Skill `impeccable` new-work, pokračuj ze zamčeného `## Direction contract`.
   Při `options.images` klíč jako v kroku 1. `direction.build_path` je `comp`
   → Impeccable po zamčení spustí kompoziční kolo (vybraný comp a dvě varianty).
   To kolo i každou další `serve-question`: `aid-ui-serve.sh forward <p>`, PM dej
   URL a klíč, pak `aid-ui-state.sh await-choice <project> --kind composition --imp "$IMP" --key <k> --page-url <url>`;
   exit 3 → re-roll a znovu, exit 1 s otevřeným kolem → MUST 1. `step 5` skript
   odmítne, dokud kompozice není zaznamenaná. Code-led (`code`): kompoziční
   kolo neběží. O schválení compu rozhoduje příznak Impeccable v sidecaru;
   náš záznam říká, že PM odpověděl.
   Při `choices.pages` postav každou potvrzenou stránku; title, meta
   description, H1 a strukturovaná data ber z `docs/seo/brief.md`.
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
   a zapiš je `aid-ui-state.sh body <project> <id> --file <soubor>` (`index.html` ručně needituj).
   Tělo se kontroluje proti povolenému seznamu značek, atributů a adres (bez komentářů,
   bez `<script>`, `on…=` a `<section>`); `style` projde jen s tokeny projektu,
   např. `style="background: var(--color-x)"`:
   - `barvy`: vzorník `.swatch` pro každou `--color-*` z `tokens.css` (barva přes `style` s `var(--color-…)`), u každé jméno a hodnota,
   - `typografie`: ukázka textu pro každou roli písma (display, body) jejím písmem, velikostí a váhou (`style` s `var(--…)` tokeny),
   - `ukazky`: oba snímky z `assets/` jako `<img>` s popiskem viewportu.
8. Teprve pak `aid-ui-state.sh chapter <project> <id> navrh` pro `barvy`, `typografie`, `ukazky`.
9. Přestavba po dřívějším schválení:
   `aid-ui-state.sh reset-approvals <project> barvy typografie komponenty ukazky`.
10. Při `options.images` po stavbě `aid-ui-state.sh spend <project>` a PM řekni
    počet obrázků (a cenu, jen když ji skript vypíše).

## Co PM rozhoduje

Kompozici (comp-led) a jiné otázky Impeccable (MUST 1).

## Zápis

Kód projektu (Impeccable), `DESIGN.md`, `docs/brand/{tokens.css,roles.css,assets/*.png}`,
`.aid-ui/capture/`, odkazy na písma, těla a stav kapitol `barvy`, `typografie`, `ukazky`.

## Když krok selže

`aid-ui-design-to-css.sh` nebo `roles` skončí 1 → ukaž `ERROR:` PM,
předchozí `tokens.css` zůstává; krok se neposouvá.

**Last Updated:** 2026-09-25
