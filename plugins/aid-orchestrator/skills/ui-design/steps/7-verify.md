---
name: ui-design-step-7
description: /aid-ui step 7 - verification gate, fix and rerun, the PM's page review and exceptions on the studio page, the project design standard, finish
user_invocable: false
---

# Krok 7 - Ověření a převzetí

**Vrstva dílny (P113):** `references/local/kontrola-postup.md` má přednost před výběrem vzorku: brána jde přes každou stránku a každou šířku a doplňuje dnešní řádky, nenahrazuje je. Místo: `web`; předání (`handover`) jde jen s verdiktem místa `web`.

**Last Updated:** 2026-10-03

## Cíl

Brána prošla na zaznamenaném buildu, PM ve studiu schválil každou stránku
(a výjimky), projekt má design standard a `aid-ui-state.sh finish` prošel.

## Vstupy

Zaznamenaný build, `coverage/checks.yaml`, `DESIGN.md`,
`/opt/eco/docs/docs/ecosystem/specs/design-system-standard.md`
a `frontend-build-standard.md` (čti živě).

## Postup

1a. Kontrola textů (před bránou, po každé změně textu, faktů nebo podkladů):
   - `aid-ui-verify.sh <project> --copy-subject .aid-ui/copy/subject.json` (texty všech stránek
     na 390 a 1440 px, jazyk, právní stránky);
   - `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-copy.py" bundle <project> --subject .aid-ui/copy/subject.json`
     → vypíše adresář běhu `<run>` (jen pravidla, převzaté copy-editing a cro, podklady, fakta, texty);
   - `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-copy.py" run <run>` → Codex jen pro čtení, `run.json`
     zapíše skript. Exit 1 (Codex neodpověděl): `aid-emit-dispatch.sh start --focus copy-review-standin
     --agent-id aid-orchestrator:review --evidence-dir <run>` (absolutní cesta), podagent Claude s čistým
     kontextem dostane jen `<run>/prompt.md` a soubory běhu a zapíše odpověď do souboru MIMO `<run>`
     (soubor navíc v adresáři běhu kontrola odmítne),
     `aid-emit-dispatch.sh complete --focus copy-review-standin --output-file <odpověď> --evidence-dir <run>`,
     pak `aid-ui-copy.py run <run> --stand-in <odpověď> --reason "<proč ne Codex>"`;
   - Codex bez odpovědi (kvóta, výpadek): `aid-ui-copy.py run` to zapíše jako neúspěšný pokus; pak
     `aid-emit-dispatch.sh start --focus copy-review-standin --agent-id aid-orchestrator:reviewer-light
     --evidence-dir <run>`, JEDEN podagent Claude s čistým kontextem (model sonnet) dostane jen
     `<run>/prompt.md` a soubory běhu a zapíše odpověď MIMO běh (scratchpad), `aid-emit-dispatch.sh
     complete --focus copy-review-standin --output-file <odpověď> --evidence-dir <run>`, nakonec
     `aid-ui-copy.py run <run> --stand-in <odpověď> --reason "<proč Codex neodpověděl>"`.
   - `aid-ui-state.sh copy-record <project> <run>` → verdikt po stránkách (ověřený a přepočtený skriptem).
     Stránka FAIL: oprav texty (krok 6, `build-record`) a znovu od subjektu. Po třetí neúspěšné kontrole
     stránky ve stejné řadě (stejná fakta a podklady) otázka `exception` ve studiu
     (`target` = `{"check":"copy_review","page":"<stránka>",…}` jako u ostatních řádků brány,
     důvod = komentář PM). Stránka v jazyce bez příručky projde jen takovou výjimkou. Řádek brány
     `copy_review` zůstane neprošlý; `finish` a stránka pro zákazníka výjimku přečtou a stránka ji
     vypíše mezi „Výjimkami schválenými zadavatelem“ s důvodem, takže důvod piš srozumitelně pro zákazníka.
1b. Verdikt PM k textům (po kontrole textů, před schvalováním stránek): otázka `copy_verdict` ve studiu
   (`target` = `copy@<sha256 souboru .aid-ui/copy/subject.json>`, `body` = co texty říkají a kde je PM
   najde v náhledu, `outcome` jednou větou). `approve` = přijato beze změn; `return` s komentářem =
   PM vypíše věty, které chce jinak → zapracuj je v kroku 6 a pusť kontrolu textů znovu (bod 1a), pak
   otázku znovu. Po `approve` `aid-ui-state.sh confirm-content <project> --answer <id>`: položky plánu
   obsahu se zdrojem `docs/content/copy.json` (texty) přejdou na `confirmed_client` - schválení textů
   PM je potvrzení klienta (jen `approve`; `return` = texty se mění), bez něj `finish` položky
   v `draft` nepustí. Položku bez textového zdroje, kterou uzavřela odpověď na údaj (IČO), potvrdí
   `confirm-content <project> --item <id> --fact <klíč registru> --answer <id otázky facts>`: položka
   musí klíč jmenovat (v id nebo potřebě) a otázka se musela ptát na registr v dnešní podobě
   (`target docs/content/facts.yaml@<sha>` = aktuální soubor); jinou odpověď na údaj příkaz odmítne. Odpověď a vypsané věty zapiš do těla kapitoly `obsah`.
1. Brána: `aid-ui-verify.sh <project>` → `.aid-ui/verify/result.json`,
   pak `aid-ui-state.sh gate-record <project> .aid-ui/verify/result.json`.
   Řádek `motion_settled` (každá stránka): brána měří a fotí až po doběhnutí konečných animací
   a zmizení úvodu `data-aid-intro` (strop 10 s; fail = úvod nebo animace neskončily). Řádek
   `motion_fidelity` (jeden za web): brána sama pozoruje úvodní stránku (`aid-ui-motion.mjs`)
   a kontroluje ji soupisem `.aid-ui/motion.json`; fail vyjmenuje pohyby vzoru, které v buildu
   neběžely - oprav build (krok 6), ne soupis; bez vybraného vzoru N/A.
   Řádek `brand_package` (jeden za celý projekt) hlásí chybějící části brand balíčku
   podle `aid-ui-brand-package.py`: doplň je v kroku 1i; u balíčku od klienta otázka
   `exception` s `target` = `aid-ui-state.sh brand-waive-target <project>` a po `approve`
   `aid-ui-state.sh brand-waive <project> --answer <id>` (platí jen pro přesně tyto chybějící
   části).
2. Otevřený řádek (fail, not_covered, warn mimo `warn_only`) → oprav kód,
   kromě `design_standard_doc` a `customer_page`: ty jsou při prvním běhu otevřené
   záměrně a řeší je body 4 a 7b;
   znovu `aid-ui-state.sh build-record` a bránu (bod 1). Opakuj, dokud
   zbývají jen řádky, které oprava neřeší.
3. Zbylý řádek, který PM přijme: otázka `exception` ve studiu (`target` =
   selektor jako JSON: `check`, `page`, `viewport`, `browser`, `role`,
   `state`; klíč vynechaný nebo `"*"` = všechno, obě podoby se berou stejně); důvod = komentář PM. Po `approve`
   `aid-ui-state.sh exception <project> --check <c> [--page …] --answer <id>`.
   **Víc řádků najednou (milník, P113a bod 8):** všechny výjimky jednoho okruhu jako jedna otázka `exception`
   s `items` (`[{id, title, target}]`, `target` položky = její selektor jako JSON) a `target` otázky
   `items@<sha položek>` (studio řekne správný sha, když nesedí). Po odpovědi každou schválenou položku zvlášť:
   `aid-ui-state.sh exception <project> --check <c> … --answer <id> --answer-item <položka>`; vrácená položka
   (komentář PM u ní) se neudělí.
4. Projektový design standard (před schvalováním stránek, protože jeho úpravy mění build): `DESIGN.md` doplněný o platformní kontrakt
   (řádky Předěl, Navigace, Dotyk/kurzor, Formuláře, Systémové okraje, Gesta; u aplikace
   i Okna), přístupnost, vzory a pravidla textů. Pak změř postavený web: náhled po bráně
   neběží, spusť ho `aid-ui-serve.sh preview <složka buildu>` (adresa je v řádku `URL:`),
   po měření `aid-ui-serve.sh stop preview`;
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
   (`target` = `<stránka>@<otisk>` z `build.fingerprints`; klíč `_site` není stránka, na ten se neptej - stránka 404 a soubory jsou v něm a schválení nepotřebují; snímek jako
   karta); po `approve`
   `aid-ui-state.sh approve-page <project> <stránka> --answer <id>`.
   Změna buildu schválení té stránky zruší.
   **Po přestavbě (milník, P113a bod 8):** změněné stránky a společný styl (`_shared`) se ptají **jednou otázkou**
   `approve_page` s `items` (položka = stránka, `target` = `<stránka>@<otisk>`), ne otázkou na každou stránku.
   Když se otázka vrací k verzi, kterou klient už viděl, nese `previous` = id té otázky: studio i klient-agent
   pak dostanou jen rozdíl textu stránky (u souborových otázek jako SEO zadání rozdíl souboru). Schválení:
   `aid-ui-state.sh approve-page <project> <stránka> --answer <id> --answer-item <stránka>` pro každou
   schválenou položku; vrácenou oprav a polož novou otázku s `previous`.
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
7b. Stránka pro zákazníka (co všechno dostal: web, značka, viditelnost, pravidla rozvoje,
   obsah; marketing „připravujeme"): až je brána zelená a zapsaná (`gate-record`) a jediný
   otevřený řádek je `customer_page` (při prvním běhu `not_covered`, stránka ještě není),
   `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-customer-page.py" <project>` →
   `docs/zakaznik/index.html` + `www/` (`docs/zakaznik/index.html` ručně needituj, vždy znovu generátorem). Každé číslo bere ze stavu, výsledku brány, SEO
   souhrnu brány, `DESIGN.md`, registru faktů, textů, SEO zadání, design standardu
   a balíčku značky; nic se nepíše ručně. Odmítne (brána není zelená, jiný build) → bod 1.
   Pak bránu znovu (bod 1, `gate-record`): řádek `customer_page` hlídá, že stránka je
   z tohoto buildu a nemá interní slova. Odkaz na stránku pošli PM s náhledem.
7c. Pořadí konce je natvrdo (P108; 9. 10. PM přebíral dvakrát, protože poslední brána změnila čísla
   po jeho odpovědi): **poslední brána → `gate-record` → `aid-ui-coverage.sh report` → kapitoly
   `kvalita` a `schvaleni` → otázka `handover`.** `chapter-all-target` i `chapter-all` odmítnou,
   když zapsaná brána neprošla řádek `customer_page`, stránka `docs/zakaznik/index.html` není ta,
   nad kterou brána běžela (otisk zapsaný při `gate-record`), nebo zpráva souladu není z této brány
   (`gate_run_at`).
7d. Otevřené body a odkazy (P108): co po běhu zůstává otevřené, zapiš
   `aid-ui-state.sh open-item <project> add --text "<co>" --owner <PM|klient|agent> [--due <datum>]`
   (fotky, právník, doména, hosting…); PM si může bod přidat sám ve studiu („Doplnit bod" na panelu
   Hotovo) - před stránkou pro zákazníka a před `finish` je převezmi `aid-ui-state.sh open-items-sync
   <project>`. Stránka pro zákazníka má oddíl „Co zbývá a co bylo rozhodnuto" (otevřené body, odložený
   obsah se slovy PM, výjimky s důvodem, každé přijaté rozhodnutí s datem). Před otázkou `handover`:
   `aid-ui-state.sh links <project> --web <adresa náhledu webu> --customer <adresa stránky pro
   zákazníka>` - obě musí odpovědět 200 a servírovat přesně `index.html` zapsaného buildu a
   `docs/zakaznik/index.html` (náhledy na hostu studia; nasazení na doménu je mimo běh). Nová
   stavba nebo nová brána odkazy a `finish.json` zahodí.
8. Kapitola `schvaleni` (tělo přes `aid-ui-state.sh body <project> schvaleni --file <soubor>`):
   stránky se schválením, výjimky s důvodem, souhrn souladu; pak
   `aid-ui-state.sh chapter <project> schvaleni navrh`. Převzetí všech kapitol
   = **jedna** otázka ve studiu druhu `handover` (`title` „Předat web?", `body` = NEJVÝŠ tři krátké
   řádky: kde web je (obě adresy z `links.json` - studio je ukáže i jako tlačítka „Otevřít web"
   a „Co jste dostali" nad textem a adresy v textu jsou klikací; otázku bez nich odmítne), co zbývá
   před zveřejněním jednou větou, a výzva k volbě; žádný výčet všeho, co PM dostává - to má
   stránka pro zákazníka (PM 11. 10. 2026: „moc textu, odkazy nejdou kliknout"); `outcome` „Návrh webu je
   dokončený; zveřejní se po doplnění …"; slovo „kapitola" v textu nepoužívej) s `target` =
   `aid-ui-state.sh chapter-all-target <project>` a **třemi kartami** `value` `prevzit` („Převzít",
   8-10/10), `vyhrada` („Převzít s výhradou", 6-7/10; studio si vyžádá, co vadí), `vratit` („Vrátit")
   v tomto pořadí - PM tím dává hodnocení (`handover.verdict` a `rating` ve stavu, pak ve
   `finish.json`); po `choose` prevzit nebo vyhrada
   `aid-ui-state.sh chapter-all <project> --by PM --answer <id otázky>`; `vratit` chapter-all
   odmítne - oprav, co komentář jmenuje, a ptej se znovu.
   `return` s komentářem → uprav jmenované kapitoly a otázku polož znovu
   (nový target). Změna těla kterékoli kapitoly po otevření otázky → otázka
   znovu. Jednotlivé `chapter <id> schvaleno` zůstává pro kapitolu, kterou
   krok schvaluje sám.
9. `aid-ui-state.sh finish <project>` - běh končí: adresy z `links.json` musí znovu odpovědět 200,
   zapíše `.aid-ui/finish.json` (datum, adresy, verdikt PM) a studio ukáže panel **Hotovo**:
   větu z převzetí, „Otevřít web", „Co jste dostali", co zbývá a pole „Doplnit bod". Odmítne → jmenuje, co
   chybí (neschválená stránka, řádek bez výjimky, položka obsahu mimo
   `confirmed_client`/`deferred_by_pm`, změna pokrytí, chybějící nebo mrtvé odkazy); vrať se k bodu,
   který to řeší. Nikdy neukonči běh bez odkazu, na který PM klikne a web uvidí.

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
