---
name: ui-design-step-6
description: /aid-ui step 6 - Impeccable finish review, ecosystem pre-deploy check, and the PM's acceptance
user_invocable: false
---

# Krok 6 - Ověření

**Last Updated:** 2026-09-24

## Cíl

Ověřený vzhled a kapitoly schválené PM (případně zákazníkem).

## Vstupy

`.impeccable/review/*.png`, `DESIGN.md`, `.impeccable/design.json`,
`docs/design/design-standard.md`, „Kontrola před nasazením" z
`/opt/eco/docs/docs/ecosystem/specs/design-system-standard.md`.

## Postup

1. `aid-ui-state.sh require-direction <project>` - exit 1 → stop, jdi na krok 3.
2. Závěrečná revize Impeccable proběhla: čerstvé `.impeccable/review/*.png`
   (novější než poslední změna kódu), `DESIGN.md` a `.impeccable/design.json`
   existují. Změnil se `DESIGN.md` nebo `.impeccable/design.json` po poslední
   revizi → snímky neplatí, spusť novou závěrečnou revizi přes Skill `impeccable`.
   Jinak ji spusť také.
3. Kontrola před nasazením: mobil + desktop podle platformního kontraktu;
   prázdný, chybový a načítací stav; klávesnice a viditelný focus; žádné
   ad-hoc varianty komponent - grep na natvrdo zapsané barvy (`#hex`, `rgb(`,
   `hsl(`) ve všech zdrojích včetně statického HTML/CSS; povolené jsou jen
   definice tokenů, i když projekt pojmenuje soubor tokenů jinak než `tokens.css`.
4. Kapitola `schvaleni` (tělo přes `aid-ui-state.sh body <project> schvaleni --file <soubor>`):
   tabulka kapitol se stavem a nálezy kontroly; kapitola, která zůstane `ceka`
   (např. `logo` bez balíčku), je v ní „nepoužito".
5. PM převezme, převezme se známým dluhem (dluh vypsaný v kapitole `schvaleni`),
   nebo řekne „vrať krok N" (`/aid-ui N`).
6. Po převzetí `aid-ui-state.sh chapter <project> <id> schvaleno --by PM`
   pro každou převzatou kapitolu, `schvaleni` jako poslední.
7. `aid-ui-state.sh finish <project>` - běh končí.

## Co PM rozhoduje

Převzetí, převzetí se známým dluhem, nebo krok k opakování.

## Zápis

Kapitola `schvaleni`, stavy kapitol.

Cesta k zákazníkovi (jen text pro PM, skill nic nevystavuje ani neposílá):
`aid-ui-serve.sh brand docs/brand` + pravidlo Cloudflare Access pro e-mail
zákazníka, nebo tisk do PDF. Servírovaná složka neobsahuje nic cizího.
Schválení e-mailem → `aid-ui-state.sh chapter <project> <id> schvaleno --by <zákazník>`.

## Když krok selže

Nález kontroly → ukaž ho PM s krokem, který ho opraví; nic se neschvaluje.

**Last Updated:** 2026-09-24
