---
name: ui-design-step-7
description: /aid-ui step 7 - verification gate, fix and rerun, the PM's page review and exceptions on the studio page, the project design standard, finish
user_invocable: false
---

# Krok 7 - Ověření a převzetí

**Last Updated:** 2026-10-03

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
   Řádek `brand_package` (jeden za celý projekt) hlásí chybějící části brand balíčku
   podle `aid-ui-brand-package.py`: doplň je v kroku 1i; u balíčku od klienta otázka
   `exception` s `target` = `aid-ui-state.sh brand-waive-target <project>` a po `approve`
   `aid-ui-state.sh brand-waive <project> --answer <id>` (platí jen pro přesně tyto chybějící
   části).
2. Otevřený řádek (fail, not_covered, warn mimo `warn_only`) → oprav kód,
   znovu `aid-ui-state.sh build-record` a bránu (bod 1). Opakuj, dokud
   zbývají jen řádky, které oprava neřeší.
3. Zbylý řádek, který PM přijme: otázka `exception` ve studiu (`target` =
   selektor jako JSON: `check`, `page`, `viewport`, `browser`, `role`,
   `state`, vynechané `"*"`); důvod = komentář PM. Po `approve`
   `aid-ui-state.sh exception <project> --check <c> [--page …] --answer <id>`.
4. Projektový design standard (před schvalováním stránek, protože jeho úpravy mění build): `DESIGN.md` doplněný o platformní kontrakt
   (řádky Předěl, Navigace, Dotyk/kurzor, Formuláře, Systémové okraje, Gesta; u aplikace
   i Okna), přístupnost, vzory a pravidla textů. Pak změř postavený web
   `aid-ui-tool.sh measure --build "$(aid-ui-state.sh build-id <složka buildu>)" <url náhledu> .aid-ui/measure.json <každá stránka>` a vygeneruj
   pracovní dokument ve struktuře WANu
   `python3 scripts/aid-ui-design-standard.py write <project> --measure .aid-ui/measure.json`
   → `docs/design/design-standard.md` (tokeny z `DESIGN.md`, role tlačítek a pole změřené,
   vzory a texty z `DESIGN.md`). Do Docusauru se **nic nepíše**, dokud PM standard
   neschválí; publikace je samostatný krok po schválení. Po `write` (a po každé změně
   `DESIGN.md`) **znovu bod 1** a `gate-record`: první běh brány dokument ještě neviděl, řádek
   `design_standard_doc` hlídá oddíly, tokeny, změřené barvy a platformní řádky. U aplikace
   za přihlášením měř s `--storage-state <stav testovacího účtu>`.
   Co do standardu
   doplníš sám podle standardu ekosystému, zapiš před otázkou: jedna skupina doplňků
   = jedno `aid-ui-state.sh decide <project> --step "Kontrola" --title "<skupina, např.
   Pravidla pro mobil>" --outcome "<co platí jednou větou>" --why "podle
   design-system-standard §<číslo>" --source DESIGN.md`, nikdy jeden souhrnný řádek.
   Otázka `design_standard` ve studiu (s `outcome`; `body` = co standard říká lidsky,
   odkaz na `docs/design/design-standard.md`); `return` → oprav a otevři znovu.
5. Kontrola stránek (až je build po bodu 4 konečný): pro každou stránku buildu otázka `approve_page`
   (`target` = `<stránka>@<otisk>` z `build.fingerprints`, snímek jako
   karta); po `approve`
   `aid-ui-state.sh approve-page <project> <stránka> --answer <id>`.
   Změna buildu schválení té stránky zruší.
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
7. SEO (jen `options.seo`): výsledek je už v bráně (bod 1: řádky `seo` a `ai_search`,
   čísla v `.aid-ui/verify/seo-summary.json`). Ruční běh stejně jako brána:
   `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-seo-check.py" <složka buildu> --brief docs/seo/brief.md --ai --state docs/design/brand-state.json --facts <facts.json z docs/content/facts.yaml> [--local] --json .aid-ui/seo/check.json`.
   `ai-policy` chybí nebo „brief is not the one the PM approved" → zpět do kroku 1s (otázka
   `seo_brief` znovu, politiku AI robotů rozhoduje PM; nikdy ji nedopisuj sám). Souhrn do
   kapitoly `seo` přes `aid-ui-state.sh body <project> seo --file <soubor>`.
8. Kapitola `schvaleni` (tělo přes `aid-ui-state.sh body <project> schvaleni --file <soubor>`):
   stránky se schválením, výjimky s důvodem, souhrn souladu; pak
   `aid-ui-state.sh chapter <project> schvaleni navrh`. Převzetí všech kapitol
   = **jedna** otázka ve studiu druhu `handover` (`title` „Předat web?", `body` = co
   dostáváte, po položkách lidsky, a co zbývá před zveřejněním; `outcome` „Návrh webu je
   dokončený; zveřejní se po doplnění …"; slovo „kapitola" v textu nepoužívej) s `target` =
   `aid-ui-state.sh chapter-all-target <project>`; po `approve`
   `aid-ui-state.sh chapter-all <project> --by PM --answer <id otázky>`.
   `return` s komentářem → uprav jmenované kapitoly a otázku polož znovu
   (nový target). Změna těla kterékoli kapitoly po otevření otázky → otázka
   znovu. Jednotlivé `chapter <id> schvaleno` zůstává pro kapitolu, kterou
   krok schvaluje sám.
9. `aid-ui-state.sh finish <project>` - běh končí. Odmítne → jmenuje, co
   chybí (neschválená stránka, řádek bez výjimky, položka obsahu mimo
   `confirmed_client`/`deferred_by_pm`, změna pokrytí); vrať se k bodu,
   který to řeší.

## Co PM rozhoduje

Výjimky, schválení každé stránky, design standard - ve studiu. Krok
k opakování (`/aid-ui <n>`) kdykoli.

## Zápis

`gate`, `exceptions`, `approvals`, `attestations` ve stavu (jen skript),
`DESIGN.md`, `docs/design/design-standard.md` (pracovní; Docusaurus až po schválení PM), kapitoly `kvalita`, `seo`, `schvaleni`.

Cesta k zákazníkovi (jen text pro PM, skill nic nevystavuje):
`aid-ui-serve.sh brand docs/brand` + pravidlo Cloudflare Access pro e-mail
zákazníka, nebo tisk do PDF.

## Když krok selže

Brána nebo skript skončí chybou → `ERROR:` PM s krokem, který to opraví;
nic se neschvaluje. Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4.

**Last Updated:** 2026-10-03
