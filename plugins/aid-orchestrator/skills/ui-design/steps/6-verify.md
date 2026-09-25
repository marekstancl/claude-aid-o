---
name: ui-design-step-6
description: /aid-ui step 6 - Impeccable finish review, ecosystem pre-deploy check, and the PM's acceptance
user_invocable: false
---

# Krok 6 - Ověření

**Last Updated:** 2026-09-25

## Cíl

Ověřený vzhled a kapitoly schválené PM (případně zákazníkem).

## Vstupy

`.impeccable/review/*.png`, `DESIGN.md`, `.impeccable/design.json`,
`docs/design/design-standard.md`, „Kontrola před nasazením" z
`/opt/eco/docs/docs/ecosystem/specs/design-system-standard.md`.

## Postup

1. `aid-ui-state.sh require-direction <project>` - exit 1 → stop, jdi na krok 3.
2. Závěrečná revize Impeccable platí jen tehdy, když existují čerstvé
   `.impeccable/review/*.png` (novější než poslední změna kódu), `DESIGN.md`
   i `.impeccable/design.json` a ani jeden z těch dvou souborů se od poslední
   revize nezměnil (změna snímky zneplatní). Platí-li vše, revizi neopakuj;
   v každém jiném případě ji spusť přes Skill `impeccable`.
3. Kontrola před nasazením: mobil + desktop podle platformního kontraktu;
   prázdný, chybový a načítací stav; klávesnice a viditelný focus; žádné
   ad-hoc varianty komponent - grep na natvrdo zapsané barvy (`#hex`, `rgb(`,
   `hsl(`) ve všech zdrojích včetně statického HTML/CSS; povolené jsou jen
   definice tokenů, i když projekt pojmenuje soubor tokenů jinak než `tokens.css`.
4. Jen při `options.seo`: z kořene projektu
   `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-seo-check.py" <výstup buildu> --brief docs/seo/brief.md --json .aid-ui/seo/check.json`
   (`--base-url <produkční URL>`, když ji `PRODUCT.md` uvádí). Výstup buildu je
   složka (Next.js `out/`, Astro `dist/`, statické HTML); u aplikace
   renderované na serveru ulož každou potvrzenou stránku přes `curl` do
   `.aid-ui/seo/` a zkontroluj tu složku. Stránku, kterou PM ze seznamu
   vyřadil, nejdřív odeber z `docs/seo/brief.md`. Souhrn (řádky `BLOCKER`
   a `WARN`, počet `OK`) do souboru v `.aid-ui/` a
   `aid-ui-state.sh body <project> seo --file <soubor>`. `BLOCKER` (exit 1)
   převzetí zastaví; do známého dluhu jde jen na výslovné slovo PM.
5. Kapitola `schvaleni` (tělo přes `aid-ui-state.sh body <project> schvaleni --file <soubor>`):
   tabulka kapitol se stavem a nálezy kontroly; kapitola, která zůstane `ceka`
   (např. `logo` bez balíčku), je v ní „nepoužito".
6. PM převezme, převezme se známým dluhem (dluh vypsaný v kapitole `schvaleni`),
   nebo řekne „vrať krok N" (`/aid-ui N`).
7. Po převzetí `aid-ui-state.sh chapter <project> <id> schvaleno --by PM`
   pro každou převzatou kapitolu, `schvaleni` jako poslední.
8. `aid-ui-state.sh finish <project>` - běh končí.

## Co PM rozhoduje

Převzetí, převzetí se známým dluhem (včetně SEO `BLOCKER`), nebo krok k opakování.

## Zápis

Kapitola `schvaleni`, při `options.seo` kapitola `seo`, stavy kapitol.

Cesta k zákazníkovi (jen text pro PM, skill nic nevystavuje ani neposílá):
`aid-ui-serve.sh brand docs/brand` + pravidlo Cloudflare Access pro e-mail
zákazníka, nebo tisk do PDF. Servírovaná složka neobsahuje nic cizího.
Schválení e-mailem → `aid-ui-state.sh chapter <project> <id> schvaleno --by <zákazník>`.

## Když krok selže

Nález kontroly → ukaž ho PM s krokem, který ho opraví; nic se neschvaluje.

**Last Updated:** 2026-09-25
