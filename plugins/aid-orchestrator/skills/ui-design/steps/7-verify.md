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
6. `aid-ui-coverage.sh report <project>` → `docs/design/soulad-se-standardy.md`;
   položky s dispozicí `agent:` po ověření
   `aid-ui-state.sh attest <project> <item id> --note <co bylo ověřeno>`.
7. SEO (jen `options.seo`):
   `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-seo-check.py" <složka buildu> --brief docs/seo/brief.md --json .aid-ui/seo/check.json`;
   souhrn do kapitoly `seo` přes `aid-ui-state.sh body <project> seo --file <soubor>`.
8. Kapitola `schvaleni` (tělo přes `aid-ui-state.sh body <project> schvaleni --file <soubor>`):
   stránky se schválením, výjimky s důvodem, souhrn souladu; pak
   `aid-ui-state.sh chapter <project> <id> schvaleno --by PM` pro každou
   převzatou kapitolu, `schvaleni` poslední.
9. `aid-ui-state.sh finish <project>` - běh končí. Odmítne → jmenuje, co
   chybí (neschválená stránka, řádek bez výjimky, položka obsahu mimo
   `confirmed_client`/`deferred_by_pm`, změna pokrytí); vrať se k bodu,
   který to řeší.

## Co PM rozhoduje

Výjimky, schválení každé stránky, design standard - ve studiu. Krok
k opakování (`/aid-ui <n>`) kdykoli.

## Zápis

`gate`, `exceptions`, `approvals`, `attestations` ve stavu (jen skript),
`DESIGN.md`, standard v Docusauru, kapitoly `seo`, `schvaleni`.

Cesta k zákazníkovi (jen text pro PM, skill nic nevystavuje):
`aid-ui-serve.sh brand docs/brand` + pravidlo Cloudflare Access pro e-mail
zákazníka, nebo tisk do PDF.

## Když krok selže

Brána nebo skript skončí chybou → `ERROR:` PM s krokem, který to opraví;
nic se neschvaluje. Odpověď chybí → odkaz na studio a konec tahu.

**Last Updated:** 2026-09-28
