---
name: ui-design-step-2
description: /aid-ui step 2 - the agent finds six gallery references, the PM picks one to three
user_invocable: false
---

# Krok 2 - Vzory

**Last Updated:** 2026-09-24

## Cíl

PM potvrdil 1-3 vzory a jejich vypočtené styly leží v `.aid-ui/refs/`.
V neinteraktivním běhu se krok nespouští (MUST 3).

## Vstupy

`PRODUCT.md` (obor, tón, publikum), typ produktu, `references/genericity-rubric.md`.

## Postup

1. PM dal všechny vzory jako URL → přeskoč galerie, jdi na bod 5 s nimi.
2. Z typu, oboru, tónu a publika sestav hledání. Projdi přes Playwright MCP jen
   veřejné stránky: godly.website, awwwards.com/websites, onepagelove.com,
   minimal.gallery, saasframe.io, mobbin.com (aplikace).
   403/429/captcha → zapiš „<galerie>: blokováno" a přeskoč; nikdy neobcházej.
3. Vyber 12 kandidátů, otevři samotné weby, vyfoť první obrazovku do
   `<project>/.aid-ui/refs/`.
4. Vyřaď nefunkční a generické podle `references/genericity-rubric.md`.
   Méně než šest použitelných → řekni PM kolik a proč, nabídni
   „jiné: <slovy>" (max. 2 nová kola) nebo vlastní URL.
5. Šest karet (4 blízko záměru, 2 odvážnější mimo obor, u každé jedna věta, co
   převzít) ve visual-companion (`skills/visual-companion/SKILL.md`):
   `start-server.sh --project-dir <project> --host 0.0.0.0 --url-host 10.20.20.22`.
6. Kliky PM jsou návrh: vyjmenuj vybrané karty v chatu, PM je potvrdí.
7. U potvrzených: `browser_evaluate` s `getComputedStyle` na
   `body, h1, h2, p, a, button` (písma, škála, barvy, zaoblení, mezery, pohyb)
   → `<project>/.aid-ui/refs/<n>.json`. Jen inspirace.

## Co PM rozhoduje

1-3 vzory (nebo „jiné", nebo vlastní URL).

## Zápis

`aid-ui-state.sh set <project> refs '[{"url":…,"why":…,"picked":true|false}]'`;
kapitola `smer`: odkazy + jedna věta ke každému, pak
`aid-ui-state.sh chapter <project> smer navrh`. Screenshoty nikdy do `docs/brand/`.

## Když krok selže

Všechny galerie blokované → řekni PM, požádej o URL. Chybí Playwright → stop
s instalací (`SKILL.md` Start).

**Last Updated:** 2026-09-24
