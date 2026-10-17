---
name: ui-design-step-4
description: /aid-ui step 4 - the agent finds gallery or app-store references and shows six cards on the studio page, the PM picks one to three
user_invocable: false
---

# Krok 4 - Vzory

**Vrstva dílny (P113):** `references/local/vzhled-postup.md` má přednost: vzhled vychází ze značky a sdělení, cizí weby jsou jen inspirace (dílna našla opsaný cizí web). Místo: `vzhled`.

**Last Updated:** 2026-09-28

## Cíl

PM ve studiu vybral 1-3 vzory a jejich vypočtené styly leží v `.aid-ui/refs/`.

## Vstupy

`PRODUCT.md` (obor, tón, publikum), `variant`, vize, `references/genericity-rubric.md`.

## Postup

1. PM dal vzory jako URL → přeskoč galerie, jdi na bod 5 s nimi.
2. Z varianty, oboru, tónu a publika sestav hledání. Přes Playwright MCP
   jen veřejné stránky: godly.website, awwwards.com/websites,
   onepagelove.com, minimal.gallery, saasframe.io. `webapp` a `pwa`:
   kandidátní aplikace najdi sám - Google Play
   (`https://play.google.com/store/search?q=<záměr>&c=apps`) a webové
   hledání; snímky z veřejných stránek Google Play / App Store ber jako
   vzory. 403/429/captcha, regionální blok nebo souhlasová zeď → zapiš
   „<stránka>: blokováno" a přeskoč; nikdy neobcházej.
3. Vyber 12 kandidátů, otevři samotné weby (u aplikací stránky v obchodě),
   vyfoť první obrazovku do `<project>/.aid-ui/refs/`.
4. Vyřaď nefunkční a generické podle `references/genericity-rubric.md`.
   Méně než šest použitelných → řekni PM kolik a proč a nabídni re-roll
   (nejvýš dvakrát) nebo vlastní URL.
5. Šest karet otázky `references` ve studiu (4 blízko záměru, 2 odvážnější
   mimo obor): `preview` = zmenšený snímek pod `.aid-ui/studio/`
   (`aid-ui-tool.sh webp`), `url` = adresa vzoru, `thesis` = co převzít,
   `uniqueness` = čím se vzor liší od šablony; id karet v otázce jsou
   neprázdná a různá. Než otázku otevřeš, zapiš nástrojem Write
   `<project>/.aid-ui/refs.json` = pole právě ukázaných karet
   `[{"id":<id karty>,"url":<url karty>,"why":<thesis karty>}]` (jiné klíče ne;
   skript zápis odmítne, když se refs neshodují s kartami, které studio PM
   ukázalo v okamžiku odpovědi - `cards` odpovědi, ne pozdější payload;
   počet, id, `url`, `thesis`); `target` = `sha256:` +
   `jq -S -c -j . <project>/.aid-ui/refs.json | sha256sum`. PM vybere vzor
   (`choose`, `choice` = id karty).
6. U vybraných: `browser_evaluate` s `getComputedStyle` na
   `body, h1, h2, p, a, button` (písma, škála, barvy, zaoblení, mezery)
   → `<project>/.aid-ui/refs/<n>.json`. Jen inspirace.
7. **Pohyb vzoru pozoruje nástroj, ne agent** (po `set refs --answer`, pro vybraný vzor):
   `bash "$AID_PLUGIN_PATH/scripts/aid-ui-tool.sh" motion <url vzoru> <project>/.aid-ui/refs/<id>.motion.json --pages 8`
   (Chromium 1440×900; scénáře načtení, druhé načtení, posun až dolů, najetí a zaměření
   prvků, klik na první vnitřní odkaz; `--pages 8` = i prvních osm podstránek vzoru z menu a patičky
   dostane načtení, posun a najetí - PM 11. 10. 2026, 2B: pohyb celého vzoru, ne jen úvodní stránky;
   každá položka záznamu říká v `pages`, kde běžela). Záznam pohybu si vyžádej i u DRUHÉHO vzoru,
   který PM jmenoval jako zdroj pohybu níž na stránce (soupis v kroku 5 smí u `replace` uvést `from`). Záznam říká, co se **skutečně spustilo**: každý
   keyframe se scénářem, místem (`hero` / `below` / `overlay`), délkou, opakováním
   a četností (`every_load` / `first_load_only`), každý přechod (vlastnost, scénář), přechod
   mezi stránkami (knihovna, co odjíždí, co přijíždí) a `coverage` - co nástroj nevidí
   (cizí stylesheety, iframy, shadow DOM, chyby). Nic z CSS cizího webu se nedomýšlí.
   `coverage` s nepokrytými zdroji řekni PM větou u vzoru. Ze záznamu krok 5 staví soupis
   pohybu (`aid-ui-motion.py inventory`); bez záznamu vybraného vzoru soupis nevznikne.

## Co PM rozhoduje

1-3 vzory, re-roll, nebo vlastní URL - ve studiu.

## Zápis

`aid-ui-state.sh set <project> refs "$(cat <project>/.aid-ui/refs.json)" --answer <id>`
(`picked` doplní skript podle volby PM; soubor neměň mezi otevřením otázky a zápisem);
kapitola `smer`: odkazy + věta ke každému, pak
`aid-ui-state.sh chapter <project> smer navrh`. Screenshoty nikdy do `docs/brand/`.

## Když krok selže

Všechny galerie blokované → řekni PM, požádej o URL. Chybí Playwright →
stop s instalací (`SKILL.md` Start). Odpověď chybí → čekání na pozadí
podle `SKILL.md` „Jak se ptá PM", bod 4.

**Last Updated:** 2026-09-28
