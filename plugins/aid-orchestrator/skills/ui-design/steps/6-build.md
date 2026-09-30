---
name: ui-design-step-6
description: /aid-ui step 6 - build from the chosen direction, structure and content plan into the project's site folder per the frontend-design snapshot and the standards, then build-record
user_invocable: false
---

# Krok 6 - Stavba

**Last Updated:** 2026-09-30

## Cíl

Web nebo aplikace postavená ze zvoleného směru, struktury a obsahového plánu
do `<project>/site/` (nebo do vlastního výstupu buildu projektu) podle
standardů; build zaznamenaný `build-record`.

## Vstupy

Odpověď `direction` a stránka směru z `.aid-ui/directions/`, `structure`,
`content_plan`, `docs/content/facts.yaml`, `docs/seo/brief.md`, brand
balíček, `references/adopted/frontend-design-SKILL.md`,
`/opt/eco/docs/docs/ecosystem/specs/frontend-build-standard.md` (FB-1..FB-20),
u aplikace `webapp-tasks-states-standard.md` (UA-1..UA-11) - čti živě.

## Postup

1. Postav každou stránku ze `structure` (u aplikace každý tok se všemi jeho
   stavy) podle snímku frontend-design a standardů. Texty jen z obsahového
   plánu a registru faktů, psané podle „Jak psát vizi, slogany a texty"
   (`steps/1v-vision.md`); položka `deferred_by_pm` dostane viditelně
   prázdné místo podle standardu, nikdy zástupný text.
2. Výstup: `<project>/site/`, nebo vlastní složka buildu projektu (Next.js
   `out/`, Astro `dist/`) - mimo `docs/` a `.aid-ui/`.
3. SEO: title, meta description, H1 a strukturovaná data z `docs/seo/brief.md`
   (H1 přesně podle tabulky).
4. Obrázky: `aid-ui-tool.sh webp <src> <out.webp> <šířka> [kvalita]` pro
   každý obrázek; limit 200 kB hlídá nástroj (exit 1 → menší šířka nebo
   kvalita).
5. Písma: build servíruj lokálně jen na 127.0.0.1 - volný port
   `port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')`,
   `python3 -m http.server --bind 127.0.0.1 --directory <složka buildu> "$port" &`
   (zapamatuj `pid=$!`), `aid-ui-tool.sh glyph http://127.0.0.1:$port/<stránka>`
   pro každou stránku, pak `kill "$pid"`; exit 1 → oprav písmo.
6. Česká typografie v generátoru (šablona nebo skript, který HTML píše):
   nezlomitelná mezera po jednopísmenných předložkách a spojkách
   (k s v z o u a i, i velká), jen v textu mimo značky:
   ```python
   def nbsp(html):
       fix = lambda m: re.sub(r'(?<=[\s>(])([ksvzouaiKSVZOUAI]) ', r'\1&nbsp;', m.group(0))
       return re.sub(r'>[^<]+<', fix, html)
   ```
7. Tokeny a brand stránka: `DESIGN.md` projektu podle postaveného vzhledu,
   `aid-ui-design-to-css.sh DESIGN.md docs/brand/tokens.css`, písma
   `aid-ui-state.sh fonts <project> <URL Google Fonts nebo docs/brand/fonts/*.css>`,
   role `aid-ui-state.sh roles <project> bg=<c>,ink=<c>,accent=<c>,display=<t>,body=<t>`.
8. `aid-ui-state.sh build-record <project> <složka buildu>`, hned potom
   `aid-ui-state.sh decide <project> --step "Stavba" --title "Web postaven"
   --outcome "Postaveno <N> stránek podle vybraného vzhledu" --why "<název vybraného
   vzhledu>" --source .aid-ui/build.json` (N = počet stránek buildu; 2-4 „stránky").
9. Snímky pro kapitolu `ukazky`: `lib/ui-fidelity/ui-capture.mjs` do
   `.aid-ui/capture/<viewport>/`, do `docs/brand/assets/` jen PNG.
   Těla kapitol `barvy`, `typografie`, `komponenty`, `ukazky` do souborů
   v `.aid-ui/` a `aid-ui-state.sh body <project> <id> --file <soubor>`
   (`index.html` ručně needituj; `style` jen s `var(--…)` tokeny), pak
   `aid-ui-state.sh chapter <project> <id> navrh`.

## Co PM rozhoduje

Nic nového; otázka, která při stavbě vznikne (chybějící fakt), jde do
studia jako `facts` a stavba té části čeká.

## Zápis

Složka buildu, `DESIGN.md`, `docs/brand/{tokens.css,roles.css,assets/*.png}`,
`build` ve stavu (jen skript), kapitoly `barvy`, `typografie`, `komponenty`,
`ukazky`.

## Když krok selže

`build-record` odmítne složku (leží v projektu, v `docs/` nebo `.aid-ui/`)
→ jiná složka. `aid-ui-design-to-css.sh` nebo `roles` skončí 1 → `ERROR:`
PM; krok se neposouvá.

**Last Updated:** 2026-09-30
