---
name: ui-design-step-7
description: /aid-ui step 7 - verification gate, fix and rerun, the PM's page review and exceptions on the studio page, the project design standard, finish
user_invocable: false
---

# Krok 7 - Ověření a převzetí

**Last Updated:** 2026-09-28

## Cíl

Brána prošla na zaznamenaném buildu, PM ve studiu schválil každou stránku
(a výjimky), projekt má design standard a `aid-ui-state.sh finish` prošel.

## Vstupy

Zaznamenaný build, `coverage/checks.yaml`, `DESIGN.md`,
`/opt/eco/docs/docs/ecosystem/specs/design-system-standard.md`
a `frontend-build-standard.md` (čti živě).

## Postup

1. Brána: `aid-ui-verify.sh <project>` → `.aid-ui/verify/result.json`,
   pak `aid-ui-state.sh gate-record <project> .aid-ui/verify/result.json`.
2. Otevřený řádek (fail, not_covered, warn mimo `warn_only`) → oprav kód,
   znovu `aid-ui-state.sh build-record` a bránu (bod 1). Opakuj, dokud
   zbývají jen řádky, které oprava neřeší.
3. Zbylý řádek, který PM přijme: otázka `exception` ve studiu (`target` =
   selektor jako JSON: `check`, `page`, `viewport`, `browser`, `role`,
   `state`, vynechané `"*"`); důvod = komentář PM. Po `approve`
   `aid-ui-state.sh exception <project> --check <c> [--page …] --answer <id>`.
4. Kontrola stránek: pro každou stránku buildu otázka `approve_page`
   (`target` = `<stránka>@<otisk>` z `build.fingerprints`, snímek jako
   karta); po `approve`
   `aid-ui-state.sh approve-page <project> <stránka> --answer <id>`.
   Změna buildu schválení té stránky zruší.
5. Projektový design standard: `DESIGN.md` doplněný o platformní kontrakt,
   přístupnost a pravidla textů, a stránka standardu projektu v Docusauru
   (`/opt/eco/docs/docs/<projekt>/`) odkazující na `DESIGN.md`. Otázka
   `design_standard` ve studiu; `return` → oprav a otevři znovu.
6. `aid-ui-coverage.sh report <project>` → `docs/design/soulad-se-standardy.md`
   a `docs/design/soulad-summary.json`; položky s dispozicí `agent:` po ověření
   `aid-ui-state.sh attest <project> <item id> --note <co bylo ověřeno>`
   a report znovu. Kapitola `kvalita`: počty z `soulad-summary.json`
   (`counts`: použito = klíče `použito…` + `ověřil agent`, `nepoužito`,
   `neověřeno`, a `generated_at`) a z `docs/design/brand-state.json`
   (`gate.run_at`, otevřené výjimky = `exceptions[]` bez `resolved` po
   `selector.check` a `selector.page`) vypiš
   `jq -c '{counts, generated_at}' <project>/docs/design/soulad-summary.json`
   a `jq -c '{run_at: .gate.run_at, open: [.exceptions[] | select(.resolved == null) | .selector | {check, page}]}' <project>/docs/design/brand-state.json`,
   z nich napiš nástrojem Write `<project>/.aid-ui/kvalita.html` (`<dl>` počtů
   a tabulka výjimek podle kontroly a stránky) a
   `aid-ui-state.sh body <project> kvalita --file <project>/.aid-ui/kvalita.html`,
   pak `aid-ui-state.sh chapter <project> kvalita navrh`.
7. SEO (jen `options.seo`):
   `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-seo-check.py" <složka buildu> --brief docs/seo/brief.md --json .aid-ui/seo/check.json`;
   souhrn do kapitoly `seo` přes `aid-ui-state.sh body <project> seo --file <soubor>`.
8. Kapitola `schvaleni` (tělo přes `aid-ui-state.sh body <project> schvaleni --file <soubor>`):
   stránky se schválením, výjimky s důvodem, souhrn souladu. Převzetí
   kapitoly = otázka ve studiu druhu podle hlavičky `aid-ui-state.sh`
   (vize → `vision`, logo → `identity`, seo → `seo_brief`, struktura →
   `structure`, obsah → `content_plan`, produkt → `variant`, smer →
   `direction`, ostatní → `design_standard`) s `target` =
   `aid-ui-state.sh chapter-target <project> <id>`; po `approve`
   `aid-ui-state.sh chapter <project> <id> schvaleno --by PM --answer <id otázky>`
   pro každou převzatou kapitolu, `schvaleni` poslední. Změna těla po
   otevření otázky → otázka znovu.
9. `aid-ui-state.sh finish <project>` - běh končí. Odmítne → jmenuje, co
   chybí (neschválená stránka, řádek bez výjimky, položka obsahu mimo
   `confirmed_client`/`deferred_by_pm`, změna pokrytí); vrať se k bodu,
   který to řeší.

## Co PM rozhoduje

Výjimky, schválení každé stránky, design standard - ve studiu. Krok
k opakování (`/aid-ui <n>`) kdykoli.

## Zápis

`gate`, `exceptions`, `approvals`, `attestations` ve stavu (jen skript),
`DESIGN.md`, standard v Docusauru, kapitoly `kvalita`, `seo`, `schvaleni`.

Cesta k zákazníkovi (jen text pro PM, skill nic nevystavuje):
`aid-ui-serve.sh brand docs/brand` + pravidlo Cloudflare Access pro e-mail
zákazníka, nebo tisk do PDF.

## Když krok selže

Brána nebo skript skončí chybou → `ERROR:` PM s krokem, který to opraví;
nic se neschvaluje. Odpověď chybí → odkaz na studio a konec tahu.

**Last Updated:** 2026-09-28
