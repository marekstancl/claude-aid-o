---
id: P998
type: regular
status: draft
created: 2026-09-17
author: PM + AI
risk: high
lifecycle_strict: true
depends_on_plans: []
---
<!-- Fixture: verbatim copy of ACTA .aid-o/plans/P025-katalog-druhu-rady-typ-dd-export.md at ACTA commit 9b68f91c98a0 (2026-09-17), id changed to P998. ACTA itself is not modified. -->

# Plan: Katalog druhů dokladu, číselné řady jako entita, daňový profil dokladu a export ZIP druh/typ DD pro DUNU

## Plan Type

This plan is type: `regular` (per frontmatter `type:` field).

| Type | Description | Activates |
|------|-------------|-----------|
| `regular` | Feature additions, new capabilities | Standard checks #1-18 + 17e |

## Ceremony band

Plán deklaruje pět Alembic migrací (`backend/db/versions/0037_*.py` až `0041_*.py`, navazují na `0036_vat_category_non_payer.py` z větve `feat/neplatce-kategorie`), takže se klasifikuje jako `full` a nese všechny povinnosti: Architecture Context, Error Handling, Edge Cases, Parallel group, `verification_pattern` u plánových AC a kolo C0 cross-provider review. Klasifikaci provádí gate:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh" --plan .aid-o/plans/P025-katalog-druhu-rady-typ-dd-export.md --classify-only
```

Frontmatter `risk: high` je záměrné: plán mění, ze které řady a v jakém okamžiku dostane účetní doklad číslo, a to je rozhodnutí, na které navazuje účetnictví klienta.

## Context

Účetní kancelář importuje doklady z ACTA do DUNY přes ISDOC. Nápověda DUNY (`docs/plans/analyzy/2026-09-16-druh-typ-dd-rada/01-duna-napoveda-vynatky.md`) a importní dialog „Převod XML do tvaru vydané faktury" (screenshot PM 17. 9. 2026) ukazují, že DUNA chce pro celou importovanou dávku **druh dokladu** (třímístný kód, který určuje skupinu evidence FV/FP, číselnou řadu, kontaci a předvyplněný typ daňového dokladu) a **typ daňového dokladu** (D1, U1, U8, ZZ, NE, OS…, který určuje řádky přiznání k DPH, kontrolní a souhrnné hlášení). U přijaté faktury k tomu přistupuje **nárok na odpočet** (1 plný, 3 krácený, 5 poměrný, 0 bez nároku, 4 jiné) a příznak **samovyměření DPH**, podle kterého DUNA hromadně generuje záznamy P/U/X.

ACTA dnes (ověřeno v kódu 16. 9. 2026):

- Druh dokladu je jeden na dvojici (klient, směr) v `client_document_defaults` (`backend/acta/docdefaults/models.py:33-77`), výchozí `44`/`53`, zapisuje se do `fields.druh_dokladu` (`backend/acta/extraction/fields.py:698-720`) a do ISDOC nejde nikam. Sedm druhů z DUNY klienta Michaely Štanclové (501, 502, 503, 504, 53, 532, 533) ACTA vyrobit neumí.
- Číselná řada je klíčovaná `(client_id, doc_type, direction, year)` (`backend/acta/sequences/models.py:19-48`), takže dva druhy nemůžou sdílet řadu a jeden směr nemůže mít dvě řady faktur. Čtecí maska čísla z faktury je jedna na (klient, směr) (`docdefaults/models.py:68-71`); faktura z druhé Míšiny řady (`3000526`) proto dostala číslo z čítače.
- Typ daňového dokladu, nárok ani samovyměření v modelu dokladu neexistují (`grep -rn "tax_doc_type" backend/acta` → 0). Daňová kategorie P016 (13 hodnot včetně `domestic_non_payer` z větve `feat/neplatce-kategorie`, `backend/acta/documents/models.py:59-73`) je obecná a jedna kategorie míří na několik typů DD.
- Export ZIP dělí doklady do jedné úrovně složek podle potvrzené kategorie (`backend/acta/export/isdoc_zip.py:25-41`), nepotvrzené do `k_rucnimu_posouzeni`. Návod pro účetní neexistuje, `_report.txt` obsahuje jen vynechané a nepotvrzené doklady (`backend/acta/export/router.py:118-166`).
- ISDOC parser čte `LocalReverseCharge` a `LocalReverseChargeFlag` (`backend/acta/extraction/isdoc_parser.py:119-132`), builder je nikdy nezapisuje (`backend/acta/documents/isdoc.py`), takže doklad v přenesené daňové povinnosti odchází do DUNY jako běžná faktura.
- Číslo z čítače se přiděluje při vytěžení (`backend/acta/jobs/extraction.py:1148-1160`); změna směru nebo klienta před schválením číslo stornuje a přidělí nové (`backend/acta/documents/router.py:611-660`, `:744-822`), takže v řadě vzniká evidovaná díra.

Dvě nezávislé analýzy (`02-analyza-codex.md`, `03-analyza-claude.md`) potvrdily směr a opravily původní návrh v pěti bodech, které tento plán přebírá: druh dokladu se navrhuje primárně z (směr, typ písemnosti) a teprve pak z kategorie; typ DD je návrh s výchozí hodnotou a varováním, ne pevná tabulka; samovyměření a nárok jsou odvozené příznaky; export musí odpovídat tomu, že DUNA importuje jednu složku jako jednu dávku s druhem i typem DD; číslo při schválení jde až jako poslední krok a jen pro vydané doklady z čítače.

Rozhodnutí PM (16. a 17. 9. 2026, `04-stav-a-rozhodnuti.md`): pořadí realizace model → daňový profil → export; export ve dvou úrovních druh / typ DD; katalog obecný se šablonami per účetní program, adaptéry pro Pohodu a ABRU až s prvním klientem; ISDOC `ID` u vydané faktury zůstává Číslo ACTA (evidenční číslo pro kontrolní hlášení ověřuje účetní).

## Goal

Účetní nastaví u klienta jednou tabulku druhů dokladu s řadami a výchozím typem daňového dokladu, ACTA pak každému dokladu navrhne druh, typ DD, nárok a samovyměření, účetní to potvrdí schválením, a export ZIP vyjde ve složkách druh / typ DD s návodem, které účetní importuje do DUNY dávku po dávce bez ručního třídění.

## Scope

**In scope:**
- Číselná řada jako entita s vlastním kódem a názvem, klíč `(client_id, code, year)`; více druhů může sdílet řadu; migrace stávajících řad s odvozeným kódem.
- Katalog druhů dokladu per klient (`client_document_kinds`): kód, název, směr, typy písemnosti, podmínky (kategorie, povaha plnění, samovyměření), řada, zdroj čísla a čtecí maska, výchozí typ DD; resolver „nejkonkrétnější shoda"; migrace dnešního `client_document_defaults` do výchozích řádků katalogu a zrušení staré tabulky.
- Pole „účetní program" u klienta a šablony katalogu (DUNA úplná, Pohoda a ABRA Flexi jen se strukturou bez adaptéru).
- Daňový profil dokladu: sloupce `tax_doc_type`, `tax_deduction`, `self_assessment`, `tax_profile_state`, `tax_profile_warnings`; mapovací adaptér pro DUNU s výchozí hodnotou, alternativami a varováním; generický adaptér pro klienty bez nastaveného programu a pro ostatní programy: navrhuje samovyměření a nárok, typ DD nechává prázdný, stav `proposed` („navrženo bez typu"), schválení ho potvrdí a export dá doklad do `<druh>/_bez_typu/` (rozhodnutí PM 2B, 17. 9. 2026).
- Znovuotevření schváleného dokladu: změna směru, klienta nebo druhu u dokladu ve stavu `reviewed` ho vrátí do `to_review` (nový přechod stavového stroje), protože mění druh, řadu i daňový profil, tedy vše, co schválení potvrzuje (rozhodnutí PM 1C).
- Změna druhu u vydaného dokladu, jehož číslo je odvozené z čísla faktury: číslo se stornuje a odvodí znovu maskou a řadou nového druhu (rozhodnutí PM 3A); číslo z čítače u přijatého dokladu se při změně druhu nemění a detail na nesoulad upozorní.
- Druh dokladu jako pole s návrhem v detailu dokladu, typ DD / nárok / samovyměření jako pole s návrhem; schválení dokladu potvrdí kategorii, druh i daňový profil v jedné transakci.
- Sloupce druh, typ DD, nárok, samovyměření a Číslo ACTA v CSV a XLSX (append-only).
- Export ZIP ve dvou úrovních `<druh>/<typ DD>/`, samovyměření jako `<druh>/<typ DD>_SAMOVYMERENI/`, nepotvrzené a vydané bez čísla do `_NEIMPORTOVAT/…`, soubor `_navod.txt` (složka → druh, řada, typ DD, nárok, samovyměření, počet, varování).
- `LocalReverseChargeFlag` v ISDOC u řádků rozpisu DPH v tuzemském reverse charge.
- Číslo z čítače při schválení pro vydané doklady (přepínač v konfiguraci), náhled čísla před schválením; vydaný doklad bez čísla jde v ZIPu do `_NEIMPORTOVAT/bez_cisla` a export jednoho dokladu vrací 409.
- Nápověda (Číselné řady, Archiv a export) a Docusaurus stránka pro účetní; backlog B-130, B-072, B-031.
- Jednorázový skript, který existujícím dokladům doplní návrh daňového profilu (dry-run, `--apply`).

**Out of scope:**
- Adaptéry Pohoda XML a ABRA Flexi REST. První verze exportuje jen ISDOC; šablony katalogu pro tyto programy vznikají, adaptér až s prvním klientem (rozhodnutí PM 4A).
- Kód plnění pro souhrnné hlášení, kód předmětu plnění u §92a, majetek do ř. 47, krácený a poměrný nárok, zvláštní režimy ZP/ZR/ZL, opravy I1/I2. Z dokladu neplynou; zůstávají účetní v DUNĚ a plán je jmenuje v `_navod.txt` jako varování.
- Změna ISDOC `ID` u vydané faktury (Číslo ACTA zůstává; PM 17. 9. 2026 rozhodl nechat, dokud DUNA neumí oddělit interní číslo od evidenčního).
- Řešení kategorie `mixed` v exportu jinak než „vždy ruční" (složka `_NEIMPORTOVAT/k_rucnimu_posouzeni`).
- Vyplnění číselníku důvodů osvobození (`docs/plans/P016-osvobozeni-duvody.md`, verze 0). Blokuje návrh kategorie u osvobozených plnění; je to vstup od účetní, ne kód.
- Úklid 508 testovacích klientů „E2E P018 …" a oprava úklidu v e2e testu (rozhodnutí PM 6A, řeší se samostatně přes `/aid-do`).
- Přečíslování historických dokladů. Čísla už přidělená zůstávají; nové chování platí pro doklady schválené po nasazení.

## Approach

### Option A: Katalog druhů jako samostatná tabulka s podmínkami a resolverem, řada jako entita s kódem (zvoleno)

Nová tabulka `client_document_kinds` nese řádky katalogu; resolver vybere nejkonkrétnější shodu podle (směr, typ písemnosti, kategorie, povaha plnění, samovyměření). Řada dostane kód a přestane být klíčovaná typem písemnosti. Daňový profil dokladu má vlastní sloupce a adaptér per účetní program. Dnešní `client_document_defaults` se zmigruje do výchozích řádků katalogu a zruší; služba `docdefaults` zůstane jako tenký adaptér nad katalogem, aby dnešní volající nemuseli měnit tvar volání dřív, než je Step 5 přepíše: pět volání `resolve_defaults_safe` (`jobs/extraction.py:1032`, `documents/derived_fields.py:75`, `documents/bundle.py:131`, `documents/router.py:673`, `documents/router.py:790`) a jedno `get_document_defaults` (`sequences/service.py:243`).

**Pros:**
- Přesně kopíruje, jak DUNA a ABRA druh dokladu chápou (číselník s vazbou na řadu a předvyplněný typ DD); Pohoda a Money se na to mapují přes „členění DPH".
- Jedna tabulka, kterou účetní vidí celou; žádné skryté vazby mezi třemi obrazovkami.
- Migrace dat je jednoznačná: jeden dnešní řádek = jeden výchozí řádek katalogu.

**Cons:**
- Pět migrací a změna klíče řady; migrace řad je nejrizikovější část plánu (řeší Step 1 s backfillem, kontrolou kolizí a testem nad kopií schématu).

### Option B: Rozšířit `client_document_defaults` o další sloupce (kategorie, řada, typ DD) a nechat řady, jak jsou

**Pros:** menší migrace, žádná nová tabulka.
**Cons:** zamítnuto. Unikátní klíč `(client_id, direction)` dovoluje jeden řádek na směr, takže sedm druhů vydaných faktur nejde zapsat bez rozbití klíče; a řada zůstává klíčovaná typem písemnosti, takže 501 a 53 (obě „faktura", obě FV1) by nemohly sdílet řadu a 502 by nemohla mít FV2. Rozšíření by tedy stejně skončilo u nové tabulky, jen s horším jménem.

### Option C: Neřešit model, jen export: složky z kategorie + `_navod.txt`, druh a typ DD dopočítat při exportu z kategorie

**Pros:** nejrychlejší, žádná migrace.
**Cons:** zamítnuto PM (rozhodnutí 4B: model napřed). Kategorie nerozliší zboží od služby (501 vs 53) ani více řad jednoho klienta; účetní by nemohla druh před schválením změnit a export by ho pokaždé dopočítal znovu, takže dva exporty téhož dokladu by mohly skončit v různých složkách.

### Decision

**Chosen:** Option A. **Rationale:** jediná varianta, která pokryje sedm druhů ze snímku DUNY, více řad jednoho klienta a potvrzení druhu účetní před exportem. Cena je v migracích, které plán izoluje do Step 1 (0037), Step 3 (0038), Step 4 (0039, 0040) a Step 7 (0041) s testy nad kopií schématu.

## Architecture

### Komponenty

```
backend/acta/sequences/            řada = entita (code, name, mask, year, next_number)
  models.py  service.py  router.py  mask.py

backend/acta/doctypes/             NOVÝ: katalog druhů dokladu per klient
  models.py      ClientDocumentKind (tabulka client_document_kinds)
  service.py     resolve_document_kind(), list/upsert/delete, apply_template()
  templates.py   šablony DUNA / Pohoda / ABRA Flexi (Python konstanty, ne YAML — žádný nový loader)
  router.py      /api/v1/clients/{client_id}/document-kinds

backend/acta/docdefaults/          ZŮSTÁVÁ jako adaptér: ResolvedDefaults se plní z výchozího
  service.py                       řádku katalogu; models.py a router.py se ruší ve Step 3,
                                   tabulka client_document_defaults až migrací 0040 ve Step 4

backend/acta/taxprofile/           NOVÝ: daňový profil dokladu
  models.py      TaxProfileProposal (dataclass), konstanty typů DD DUNA s českými názvy
  duna.py        mapování (směr, kategorie, povaha plnění, země dodavatele) → návrh
  generic.py     adaptér pro pohoda/abra_flexi/money/other: jen samovyměření + nárok
  service.py     refresh_tax_profile(session, doc, client) — návrh, nikdy přepis potvrzeného
  router.py      PATCH /api/v1/documents/{doc_id}/tax-profile, GET /api/v1/tax-doc-types

backend/acta/documents/
  models.py           + tax_doc_type, tax_deduction, self_assessment, tax_profile_state, tax_profile_warnings
  status_router.py    schválení potvrdí kategorii + druh + daňový profil + přidělí číslo (vydané z čítače)
  vat_category_on_approval.py  → confirm_proposals_on_approval() rozšířeno o druh a daňový profil
  derived_fields.py   druh z resolveru katalogu
  isdoc.py            LocalReverseChargeFlag
  router.py           změna směru/klienta: před schválením číslo nepřiděluje (vydané z čítače)

backend/acta/export/
  isdoc_zip.py   složky <druh>/<typ DD>/, _SAMOVYMERENI, _NEIMPORTOVAT, název souboru z Čísla ACTA u vydané
                 POZOR: build_isdoc i documents_to_isdoc_zip volá i převodník FlexiBee
                 (backend/acta/convert/service.py) s duck-typed dokladem bez direction,
                 acta_sequence_number a vat_breakdown → nové čtení jen přes getattr(…, None)
  manifest.py    NOVÝ: _navod.txt
  router.py      layout=flat|category|kind_taxtype (výchozí flat), alias split_by_category → category, report
  csv.py xlsx.py nové sloupce (append-only)

frontend/src/components/client/
  ClientSequences.tsx        kód + název řady
  ClientDocumentKinds.tsx    NOVÝ: tabulka katalogu + „Předvyplnit podle programu"
  (ClientDocumentDefaults.tsx se ruší)
frontend/src/components/documents/
  DocumentKindField.tsx      NOVÝ: druh jako pole s návrhem (vzor VatCategoryField)
  TaxProfileFields.tsx       NOVÝ: typ DD / nárok / samovyměření jako pole s návrhem
  ExportButton.tsx           přepínač rozvržení ZIPu
```

### Tok dat po změně

Pořadí se MĚNÍ ve VŠECH čtyřech cestách, kde se určuje druh a přiděluje číslo (extrakce, změna klienta, změna směru, split balíku). Dnes je číslo dřív než druh a (u extrakce a změny směru) dřív než klasifikace: `jobs/extraction.py:1032 → 1155 → 1181`, `documents/router.py:645 → 688`, `:807 → 840 → 901`, `documents/bundle.py:167 → 198`. Nové jednotné pořadí:

```
0. storno starého čísla (jen změna směru/klienta)   void_sequence_number(…, sequence_code z fields_meta._acta_number)
1. protistrana a přepisy jmen                        sync_counterparty, jako dnes
2. klasifikace kategorie                             reclassify_document(trigger=…)      → vat_category_proposed
3. daňový profil (od Step 8)                         refresh_tax_profile(doc, client)    → tax_doc_type, tax_deduction,
   │                                                                                        self_assessment, state, warnings
4. druh dokladu                                      apply_direction_derived_fields → (events, kind)
   │                                                 resolve_document_kind(client, směr, typ písemnosti,
   │                                                   kategorie, supply_kind, self_assessment)
   │                                                 fields.druh_dokladu = kind.code ; fields_meta.druh_dokladu =
   │                                                   {kind_code, kind_name, state: proposed, matched_by}
   ├─ 4a. typ DD z druhu (od Step 8)                 apply_kind_tax_doc_type(doc, kind): když kind.tax_doc_type a profil
   │                                                   není confirmed/overridden → tax_doc_type = kind.tax_doc_type
   │                                                   (self_assessment se NEMĚNÍ → žádný cyklus profil↔druh)
   ▼
5. číslo                                             resolve_acta_number(…, sequence_code=kind.sequence_code,
                                                       number_source=kind.number_source, read_mask=kind.number_read_mask)
                                                       invoice_number          → hned (převod z čísla na faktuře)
                                                       sequence, přijatá       → hned
                                                       sequence, vydaná        → None + meta „deferred_to_approval"
                                                                                  (jen když je zapnutý přepínač, Step 14)

přepočet druhu i mimo tyto cesty: reclassify_document (všech šest volajících), confirm/override kategorie,
změna supply_kind, rozpisu DPH a pole → na konci vždy krok 4 + 4a; když se tím u vydaného dokladu před schválením
změní řada nebo čtecí maska a číslo je odvozené z faktury (source invoice_number | sequence_fallback) → storno
a nové odvození (krok 5)

schválení (PATCH status → reviewed), doklad načtený SELECT … FOR UPDATE
   1. confirm_proposals_on_approval: kategorie (jako dnes) + daňový profil (proposed → confirmed, i „bez typu")
      + druh (state confirmed); 409 při rozdílu proti tomu, co klient viděl (expected_*)
   2. vydaná z čítače bez čísla → resolve_acta_number(…, assign_now=True) v téže transakci, VŽDY když číslo chybí
      (nezávisle na přepínači; přepínač řídí jen odklad při vytěžení)
   3. transition_document(reviewed)
   Zkratka review-and-archive návrhy NEPOTVRZUJE (nemá verzi, důvod v status_router.py:188-198 platí dál),
   ale body zámek + 2 provede.

změna směru, klienta nebo druhu u dokladu ve stavu reviewed → doklad se vrací do to_review (nový přechod
   reviewed → to_review), druh a profil jdou zpět na proposed, číslo se stornuje a přidělí při novém schválení

export ZIP (layout = kind_taxtype, posílá ho frontend výslovně; bez parametru zůstává plochý archiv)
   <kind.code>_<slug(kind.name)>/<tax_doc_type>/FA_<Číslo ACTA nebo číslo faktury>.isdoc
   <kind.code>_<slug>/<tax_doc_type>_SAMOVYMERENI/…          (self_assessment = true)
   <kind.code>_<slug>/_bez_typu/…                             (potvrzený profil bez typu DD: generický adaptér
                                                               nebo ruční změna bez typu)
   _NEIMPORTOVAT/k_rucnimu_posouzeni/…                        (kategorie nebo daňový profil nepotvrzený, mixed)
   _NEIMPORTOVAT/bez_cisla/…                                  (vydaná bez Čísla ACTA)
   _navod.txt, _report.txt
```

### Hranice generické vs. specifické pro program

Generický model ACTA (platí pro každý účetní program): směr, typ písemnosti, daňová kategorie P016, povaha plnění, samovyměření ano/ne, nárok plný/bez, katalog druhů (kód a řada jsou texty, které si účetní opíše ze svého programu). Specifické per program: šablona katalogu (`doctypes/templates.py`) a mapování kategorie → typ DD (`taxprofile/duna.py`; pro Pohodu by šlo o „členění DPH", pro ABRU o „řádek přiznání"; oba jsou mimo rozsah, adaptér `generic.py` pro ně vrací jen samovyměření a nárok). Výběr adaptéru řídí `clients.accounting_system`.

## Data Model

### `client_sequences` (změna, migrace 0037)

- `code`: VARCHAR(8) NOT NULL, CHECK `code ~ '^[A-Za-z0-9]{1,8}$'`. Kód řady, jak ho účetní zná z programu (`FV1`, `PF`, `FAV`).
- `name`: TEXT NULL. Popis pro UI („Vydané faktury do ČR").
- `doc_type`, `direction`: zůstávají NOT NULL jako **výchozí přiřazení** (pro katalogový řádek se `sequence_code IS NULL` a pro výchozí masku nové řady), ale přestávají být součástí unikátního klíče.
- `mask`, `year`, `next_number`, `created_at`, `updated_at`: beze změny.
- Unikátní klíč: `uq_client_sequences_client_code_year (client_id, code, year)`; starý `uq_client_sequences_client_doc_dir_year` se ruší.
- Backfill kódu: `prijata` → faktura `FAP`, dobropis `DOB`, zalohova `ZAL`, jine `DOK`; `vydana` → `FAV`, `DOV`, `ZAV`, `DKV` (tytéž prefixy jako `DEFAULT_MASKS` / `DEFAULT_MASKS_ISSUED` v `backend/acta/sequences/mask.py:25-51`). Kolize po backfillu (stejný klient, kód a rok dvakrát) je v dnešním klíči nemožná, migrace to přesto ověří dotazem a při nálezu selže s výpisem řádků.
- Invariant: `next_number` nikdy neklesá jinak než ručním PATCH; `sequence_number_taken` (`sequences/service.py:30-63`) zůstává jedinou definicí obsazenosti.

### `client_document_kinds` (nová tabulka, migrace 0038)

- `id`: UUID PK.
- `client_id`: UUID FK `clients.id` ON DELETE CASCADE, NOT NULL.
- `code`: VARCHAR(8) NOT NULL, CHECK `code ~ '^[A-Za-z0-9]{1,8}$'` (DUNA: „libovolné třímístné označení"; dnešní CHECK `^[0-9]{1,4}$` z `docdefaults/models.py:50-53` se tím ruší).
- `name`: TEXT NOT NULL.
- `direction`: ENUM `invoicedirection` NOT NULL (existující typ, `create_type=False`).
- `doc_types`: ARRAY(ENUM `documenttype`) NOT NULL, DEFAULT `'{faktura}'`. Prázdné pole zakázáno CHECK `cardinality(doc_types) > 0`.
- `vat_categories`: ARRAY(VARCHAR(40)) NULL. NULL = libovolná kategorie. Hodnoty z `VAT_CATEGORIES` (`documents/models.py:59-73`, 13 hodnot), validuje router; kód nikde neopisuje seznam kategorií, čte konstantu.
- `supply_kinds`: ARRAY(VARCHAR(8)) NULL. NULL = libovolná; hodnoty z `SUPPLY_KINDS` (`documents/models.py:110`).
- `self_assessment`: BOOLEAN NULL. NULL = libovolné; TRUE = jen doklady se samovyměřením; FALSE = jen bez.
- `sequence_code`: VARCHAR(8) NULL. NULL = řada podle typu písemnosti (dnešní chování: `FAP/DOB/ZAL/DOK` resp. `FAV/DOV/ZAV/DKV`).
- `number_source`: VARCHAR(16) NOT NULL DEFAULT `'sequence'`, CHECK IN (`'sequence'`, `'invoice_number'`).
- `number_read_mask`: VARCHAR(64) NULL; CHECK `number_source = 'sequence' OR number_read_mask IS NOT NULL`.
- `tax_doc_type`: VARCHAR(4) NULL. Výchozí typ DD pro tento druh v programu klienta (přebije mapování z kategorie, když je vyplněný).
- `priority`: INTEGER NOT NULL DEFAULT 100. Nižší číslo vyhrává při stejné konkrétnosti.
- `is_default`: BOOLEAN NOT NULL DEFAULT FALSE. NEJVÝŠ jeden na (client_id, direction): partial unique index `uq_client_document_kinds_default (client_id, direction) WHERE is_default`. Klient bez výchozího řádku je platný stav (resolver padá na vestavěné 44/53). Router (Step 4) označí první založený druh směru za výchozí automaticky, pokud směr žádný výchozí nemá.
- `created_at`, `updated_at`: TIMESTAMPTZ.
- Unikátní: `uq_client_document_kinds_client_code (client_id, code)`.
- Migrace dat: každý řádek `client_document_defaults` → jeden řádek katalogu s `code = COALESCE(druh_dokladu, '44'|'53')`, `name = 'Výchozí přijaté'|'Výchozí vydané'`, `doc_types = všechny čtyři`, `vat_categories = NULL`, `supply_kinds = NULL`, `self_assessment = NULL`, `sequence_code = NULL`, `number_source`, `number_read_mask` zkopírované, `is_default = TRUE`. Migrace 0038 starou tabulku NEMAŽE. Samostatná migrace 0040 ve Step 4 ji po kontrole, že každý její řádek má protějšek v katalogu, PŘEJMENUJE na `client_document_defaults_legacy` (`ALTER TABLE … RENAME TO`); data tak zůstanou v databázi bez zápisu do `audit_log` (migrace v ACTA do `audit_log` nezapisují, viz zdůvodnění v `backend/db/versions/0034_drop_field_confidence.py:11-15`) a downgrade je jen přejmenování zpět, takže nenarazí na CHECK `^[0-9]{1,4}$` staré tabulky u alfanumerických kódů. Fyzické smazání legacy tabulky je mimo rozsah (budoucí úklidová migrace).

### `clients` (změna, migrace 0039)

- `accounting_system`: VARCHAR(16) NULL, CHECK IN (`'duna'`, `'pohoda'`, `'abra_flexi'`, `'money'`, `'other'`). NULL = neurčeno; adaptér daňového profilu se pak chová jako `other`.

### `documents` (změna, migrace 0041)

- `tax_doc_type`: VARCHAR(4) NULL. Kód typu daňového dokladu v programu klienta (DUNA: `D1`, `U1`, …). NULL = ACTA nic nenavrhla nebo účetní nerozhodla.
- `tax_deduction`: VARCHAR(1) NULL, CHECK IN (`'1'`, `'3'`, `'5'`, `'0'`, `'4'`). Jen u přijatých; u vydaných vždy NULL (CHECK `direction = 'prijata' OR tax_deduction IS NULL` se nepřidává, protože `direction` může být NULL v době zápisu; hlídá to `taxprofile/service.py`).
- `self_assessment`: BOOLEAN NULL. TRUE = doklad vstupuje do samovyměření.
- `tax_profile_state`: VARCHAR(16) NOT NULL DEFAULT `'not_run'`, CHECK IN (`'not_run'`, `'proposed'`, `'needs_review'`, `'confirmed'`, `'overridden'`). Stejná sémantika jako `vat_category_state` (`documents/models.py:97-103`).
- `tax_profile_warnings`: JSONB NOT NULL DEFAULT `'[]'`. Pole textů pro účetní („D1 je výchozí; při splátkovém kalendáři nad 10 tis. Kč použijte DS").
- Druh dokladu zůstává v `fields.druh_dokladu`; `fields_meta.druh_dokladu` dostane klíče `kind_code` (str), `kind_name` (str, název druhu v okamžiku určení; z něj čte `DocumentOut.document_kind.name`), `state` (`proposed` | `confirmed` | `manual`), `matched_by` (str, např. `direction+doc_type+vat_category`). Žádný nový sloupec.
- Index: `ix_documents_tax_profile_state (tax_profile_state)` pro filtr „doklady bez rozhodnutého typu".

### Číselník typů DD DUNA (`taxprofile/models.py`, Python konstanta)

`DUNA_TAX_DOC_TYPES: dict[str, str]` s kódem a českým názvem pro uskutečněná plnění (D1, D2, D7, D9, DS, DZ, E2, E3, E4, E5, E6, E8, EX, I1, I2, MT, NE, OS, PO, U1, U3, U5, U6, U7, U8, ZL, ZP, ZR, ZV, ZZ, C1, C2, EQ, EU, ES, SH) a přijatá plnění (D1, D2, D3, DS, DZ, M1, I1, I2, EX, E9, IM, M4, M7, ZM, ZO, ZV, NE, OS, PO, EU) a samovyměření (U1, U2, U3, U4, U6, C1, C2, IM, MT, M2, M3, M4, M5, M6, ZZ, M8). Seznam členských států EU se NEZAKLÁDÁ znovu: používá se `EU_MEMBER_ALPHA2` z `backend/acta/registry/classifier.py:86`. Texty se přebírají doslova z `docs/plans/analyzy/2026-09-16-druh-typ-dd-rada/01-duna-napoveda-vynatky.md`: vysvětlivky uskutečněných plnění řádky 51-87, vysvětlivky přijatých plnění řádky 125-143 (řádky 92-124 jsou tabulka směřování do řádků přiznání, ta se nepřebírá), vysvětlivky samovyměření řádky 195-210. Typ `D4` (vypořádání DPH na výstupu §91) je ve vysvětlivkách, ale ne v tabulce směřování; do číselníku se zařadí s poznámkou „jen ruční volba".

## API Design

### Číselné řady (změna, `backend/acta/sequences/router.py`)

- `GET /api/v1/clients/{client_id}/sequences` → 200 `[SequenceConfigOut]`; `SequenceConfigOut` nově nese `code: str`, `name: str | null`.
- `POST /api/v1/clients/{client_id}/sequences` body `{code?: str, name?: str, doc_type: str, direction: str, year: int, mask?: str, start_number?: int}` → 201; `code` je VOLITELNÝ, výchozí `legacy_sequence_code(doc_type, direction)`, aby dnešní volající bez kódu (frontend do Step 6, testy, e2e specy) fungovali beze změny; 422 `Kód řady musí být 1 až 8 písmen nebo číslic.` (kontrola regexem v routeru, ne `Field(pattern=…)`, protože Pydantic v2 vrací anglickou hlášku); 409 `Řada {code} pro rok {year} už existuje.`
- `PATCH /api/v1/clients/{client_id}/sequences/{sequence_id}` body `{name?: str, mask?: str, next_number?: int}` → 200. `code` se PATCHem nemění (je součást klíče a odkazuje na něj katalog); změna kódu = nová řada.
- `DELETE …/{sequence_id}` → 204; 409 `Na řadu odkazuje druh dokladu {code}.` když existuje `client_document_kinds.sequence_code = code` téhož klienta.

### Katalog druhů (nový, `backend/acta/doctypes/router.py`, prefix `/api/v1/clients/{client_id}/document-kinds`)

- `GET` → 200 `[DocumentKindOut]` seřazené podle `direction, priority, code`; 404 klient neexistuje; čtení smí každý přihlášený včetně role `viewer` (stejně jako dnešní GET řad a nastavení, které UI viewerovi ukazuje jen pro čtení); zápisy jen `accountant`/`admin` (403 pro `viewer`), 401 bez přihlášení.
- `POST` (jen `accountant`/`admin`, `viewer` 403) body `DocumentKindIn {code, name, direction, doc_types: [str], vat_categories?: [str] | null, supply_kinds?: [str] | null, self_assessment?: bool | null, sequence_code?: str | null, number_source: 'sequence' | 'invoice_number', number_read_mask?: str | null, tax_doc_type?: str | null, priority?: int, is_default?: bool}` → 201 `DocumentKindOut`; 422 s hláškou: kód (`Kód druhu musí být 1 až 8 písmen nebo číslic.`), neznámá kategorie (`Neznámá daňová kategorie: {x}.`), neznámá povaha plnění, `number_source = invoice_number` u přijatého směru (`Odvození Čísla ACTA z čísla faktury lze zapnout jen u vydaných dokladů.`, převzato z `docdefaults/router.py:49-52`), chybějící čtecí maska, neplatná čtecí maska (`validate_read_mask`, `sequences/mask.py:217`); 409 duplicitní kód nebo druhý `is_default` pro směr.
- `PUT /{kind_id}` stejné tělo → 200; stejné chyby.
- `DELETE /{kind_id}` → 204; 409 `Výchozí druh nelze smazat, nejdřív označte jiný.` když `is_default`.
- `POST /apply-template` body `{system: 'duna' | 'pohoda' | 'abra_flexi', mode: 'add_missing' | 'replace'}` → 200 `{created: int, skipped: [code], skipped_defaults: [code], deleted: [code], sequences_missing: [{code, suggested_mask: str | null, same_mask_as: str | null}]}`. `add_missing` nikdy nepřepíše existující kód; `replace` smaže řádky, na které neodkazuje žádný doklad ve stavu `to_review` (jinak 409 s výčtem kódů). Šablona řady NEZAKLÁDÁ: kódy a masky řad v DUNĚ klienta jsou vstup od účetní (otevřená otázka č. 4 v `04-stav-a-rozhodnuti.md`), proto endpoint jen vrátí, které kódy řad druhy potřebují, s navrženou maskou, a u každé řekne, zda už klient má řadu se stejnou maskou pod jiným kódem (`same_mask_as`), aby nevznikly dva čítače renderující totéž číslo. Existující `is_default` se nemění; šablonový výchozí řádek se vloží s `is_default = FALSE`, když směr výchozí už má.
- Každý zápis do katalogu jde do `audit_log`: `document_kind_created`, `document_kind_updated` (old/new po polích), `document_kind_deleted`, `document_kinds_template_applied` (system, mode, created, skipped).
- `POST /preview` body `{direction, doc_type, vat_category?: str | null, supply_kind?: str | null, self_assessment?: bool | null, invoice_number?: str | null}` → 200 `{kind_code, kind_name, matched_by, sequence_code, number_preview: str | null, tax_doc_type: str | null}`. Nahrazuje `docdefaults/router.py:217` preview; u `invoice_number` renderuje maskou cílové řady jako dnes (`sequences/service.py:265-350`).

### Daňový profil dokladu (nový, `backend/acta/taxprofile/router.py`)

- `PATCH /api/v1/documents/{doc_id}/tax-profile` body `{version: int, tax_doc_type?: str | null, tax_deduction?: str | null, self_assessment?: bool | null, reason: str}` → 200 `DocumentOut`; 409 `Version conflict` (stejný vzor jako `status_router.py:101`); 422 `Nárok se u vydaných dokladů nevyplňuje.`, `Neznámý typ daňového dokladu {x} pro program {system}.`, `Důvod změny je povinný.` (min 3 znaky), 422 u archivovaného dokladu (stejná hláška a kód jako `_require_editable` ve `vat_category_router.py:78`); 403 role `viewer`; 401 bez přihlášení. Pole se rozlišují přes `model_fields_set` (neposlané pole se nemění, poslané `null` hodnotu maže). Zapíše `tax_profile_state = 'overridden'`, audit `tax_profile_overridden` (old/new pro každé změněné pole), `version += 1`.
- `GET /api/v1/tax-doc-types?system=duna` → 200 `{issued: [{code, label}], received: [...], self_assessment: [...]}`; jiný nebo chybějící `system` → prázdná pole; 401 bez přihlášení.
- `DocumentOut` (`backend/acta/documents/schemas.py:30-80`) nově nese `tax_doc_type`, `tax_deduction`, `self_assessment`, `tax_profile_state`, `tax_profile_warnings`, `document_kind: {code, name, state, matched_by} | null`.

### Schválení (změna, `backend/acta/documents/status_router.py`)

- `PATCH /api/v1/documents/{doc_id}/status` body `StatusPatch` dostane `expected_kind_code: str | null`, `expected_tax_doc_type: str | null` vedle dnešního `expected_vat_category_proposed` (`status_router.py:48`). Rozdíl proti aktuálnímu návrhu → 409 `Návrh druhu dokladu se mezitím změnil ({old} → {new}). Načtěte doklad znovu.` (totéž pro typ DD). Odpověď `{ok, status, version, acta_sequence_number}`. `POST /api/v1/documents/{doc_id}/review-and-archive` návrhy nepotvrzuje (beze změny), jen přidělí číslo vydanému dokladu z čítače (Step 14).
- `GET /api/v1/documents/{doc_id}/number-preview` (vzniká ve Step 8, protože ho volá detail ve Step 9) → 200 `{number: str | null, source: 'assigned' | 'preview' | 'invoice_number' | 'none', sequence_code: str | null, note: str | null}`; 401 bez přihlášení, 404 doklad neexistuje; čtení smí každá role. `preview` renderuje `render_mask(seq.mask, year, month, seq.next_number)` bez posunu čítače; `none` u dokladu bez směru nebo klienta.

### Export (změna, `backend/acta/export/router.py:21-40`)

- `GET /api/export?format=isdoc&client_id=…&layout=flat|category|kind_taxtype` (nový parametr, výchozí `flat` = dnešní chování volání bez parametru); `split_by_category=true` se přijímá jako alias `layout=category` (dnešní složky podle kategorie), aby se stávajícím volajícím nezměnila struktura archivu. `kind_taxtype` posílá frontend výslovně (Step 13). Hlavičky: `X-Export-Skipped` (beze změny), `X-Export-Unresolved` (počet v `_NEIMPORTOVAT`), nově `X-Export-No-Number` (vydané bez čísla).
- `GET /api/v1/documents/{doc_id}/export/isdoc` (`documents/router.py:416-450`): vydaný doklad bez Čísla ACTA → 409 `Vydaný doklad nemá Číslo ACTA — schvalte ho, číslo se přidělí při schválení.`

## Implementation Steps

**EPIC 1: Steps 1-6 — Model: řady jako entita a katalog druhů dokladu**

### Step 1: Řada dostane kód a název, klíč (klient, kód, rok)

**Objective:** Migrace 0037 a služba řad, ve které je řada identifikovaná kódem a více druhů ji může sdílet, se zachováním všech dnešních čísel a chování přijatých řad.

**Files:**
- Create: `backend/db/versions/0037_sequence_code.py` — `down_revision = "0036"` (migrace `0036_vat_category_non_payer.py` z větve `feat/neplatce-kategorie`, viz `## Migration Plan`); přidá `code`, `name`, backfill kódu z (doc_type, direction), nový unikátní klíč `(client_id, code, year)`, zrušení starého klíče, CHECK na kód; downgrade obrací pořadí.
- Modify: `backend/acta/sequences/models.py` (lines ~19-48) — sloupce `code`, `name`, nový `UniqueConstraint`, CHECK; `__init__` doplní `code = legacy_sequence_code(doc_type, direction)`, když ho volající nepředá (dnešní přímé konstrukce `ClientSequence(...)` v testech a ve službě tak projdou).
- Modify: `backend/acta/sequences/mask.py` (lines ~25-66) — `legacy_sequence_code(doc_type, direction) -> str` (FAP/DOB/ZAL/DOK, FAV/DOV/ZAV/DKV) a `default_mask_for_code(code, doc_type, direction)`; dnešní `default_mask_for` zůstává a volá se z nové funkce.
- Modify: `backend/acta/sequences/service.py` (lines ~66-140, 142-203, 205-350, 353-405) — `_load_or_create_sequence(session, client_id, code, year, *, doc_type, direction)` hledá podle `(client_id, code, year)`; při založení nového roku kopíruje masku z nejnovějšího řádku téhož kódu, jinak `default_mask_for_code`; `get_next_sequence_number`, `resolve_acta_number` a `void_sequence_number` dostanou parametr `sequence_code: str | None` (None = `legacy_sequence_code(doc_type, direction)`, aby dnešní volající prošli beze změny).
- Modify: `backend/tests/sequences/test_service.py` (lines ~385-400, 540-560) — test `test_model_unique_key_includes_direction` (řádek 387) přepsat na nový klíč `uq_client_sequences_client_code_year (client_id, code, year)`; nové případy na konci: dva kódy v jednom směru mají oddělené čítače; nový rok kopíruje masku z předchozího roku téhož kódu; `void_sequence_number(…, sequence_code='FV2')` se dotkne řádku řady `FV2` a řadu `FAV` téhož klienta nechá beze změny (nad skutečnými řádky `client_sequences`, ne přes mock — dnešních osm testů storna funkci jen mockuje).
- Modify: `backend/tests/sequences/test_resolve_acta_number.py` (lines ~660-680) — nové případy na konci: `resolve_acta_number(…, sequence_code=None)` dává stejné číslo jako dnes; `sequence_code='FV1'` bere číslo z řady `FV1` a telemetrie nese `sequence_code`.
- Modify: `backend/tests/scripts/test_fix_issued_invoices_p018.py` (lines ~170-190, 640-650) — surové `INSERT INTO client_sequences` na řádcích 178, 187 a 647 doplnit o sloupec `code` (po migraci 0037 je NOT NULL).
- Test: `backend/tests/migrations/test_migration_0037.py` (tier: t1) — upgrade nad kopií schématu s řádky pro všechny čtyři typy a oba směry: kódy FAP/DOB/ZAL/DOK/FAV/DOV/ZAV/DKV, unikátní klíč existuje, starý neexistuje; downgrade vrací klíč; simulovaná kolize (dva řádky se stejným budoucím kódem vložené přes SQL) migraci zastaví s výpisem.

**Reuse check:** searched: `find backend/db/versions -name "*sequence*"` → several matching `0016_client_sequences.py`, `0017_document_sequence_number.py`, `0019_client_sequence_mask.py`, `0024_sequence_direction.py`, `0027_unique_sequence_number.py` — jsou to historické migrace téže tabulky; nová migrace na ně navazuje (`down_revision = "0036"`) a přebírá z `0019` vzor „přidat sloupec, backfill, zpřísnit NOT NULL", ale žádná z nich sloupec `code` nezavádí.

**Parallel group:** wave-1

**Architecture Context:** Řada je základ, na který ukazuje katalog druhů (Step 3 přes `sequence_code`) a ze kterého bere číslo schválení (Step 14). Musí být hotová první, protože `resolve_acta_number` je jediné místo automatického přidělení čísla (`sequences/service.py:205`) a všech pět volání přes ni jde: extrakce (`jobs/extraction.py:1155`), změna klienta (`documents/router.py:645`), změna směru (`documents/router.py:807`), split balíku (`documents/bundle.py:167`) a přečíslovací skript (`scripts/fix_issued_invoices_p018.py:672`, který volá i `void_sequence_number` na řádku 663). Viz `## Architecture` → Komponenty.

**Implementation Detail:**
Migrace 0037 v pořadí: (1) `ADD COLUMN code VARCHAR(8) NULL, name TEXT NULL`; (2) `UPDATE client_sequences SET code = CASE direction WHEN 'vydana' THEN CASE doc_type WHEN 'faktura' THEN 'FAV' WHEN 'dobropis' THEN 'DOV' WHEN 'zalohova' THEN 'ZAV' ELSE 'DKV' END ELSE CASE doc_type WHEN 'faktura' THEN 'FAP' WHEN 'dobropis' THEN 'DOB' WHEN 'zalohova' THEN 'ZAL' ELSE 'DOK' END END`; (3) kontrola `SELECT client_id, code, year, count(*) … GROUP BY 1,2,3 HAVING count(*) > 1` → při nálezu `raise RuntimeError` s výpisem; (4) `ALTER COLUMN code SET NOT NULL`, CHECK `ck_client_sequences_code_format`; (5) `DROP CONSTRAINT uq_client_sequences_client_doc_dir_year`, `CREATE UNIQUE CONSTRAINT uq_client_sequences_client_code_year`. Downgrade: obnoví starý klíč (selže, pokud mezitím vznikly dvě řady jednoho typu ve směru; hláška to řekne), smaže CHECK a sloupce.

Služba: signatura `_load_or_create_sequence(session, client_id, code, year, *, doc_type, direction)`; `SELECT … WHERE client_id AND code AND year FOR UPDATE`; při `None`: `prev = SELECT … WHERE client_id AND code ORDER BY year DESC LIMIT 1`; `mask = prev.mask if prev else default_mask_for_code(code, doc_type, direction)`; `INSERT` v SAVEPOINTu jako dnes (`service.py:97-138`). `get_next_sequence_number(session, client_id, doc_type, year, month, direction=None, *, sequence_code=None)` a `resolve_acta_number(…, sequence_code=None)`: `code = sequence_code or legacy_sequence_code(doc_type, direction or "prijata")`. `void_sequence_number(…, sequence_code=None)` totéž. Telemetrie `_acta_number` ve `fields_meta` (`jobs/extraction.py:1155-1160`) dostane klíč `sequence_code`.

**Error Handling:**
- Kolize kódů při migraci → migrace selže před `SET NOT NULL`, databáze zůstává v původním stavu (Alembic běží v transakci), hláška vypíše `client_id, code, year`.
- `IntegrityError` při souběžném založení řady → dnešní SAVEPOINT cesta (`service.py:118-138`) beze změny, jen dotaz na znovunačtení používá kód.
- `sequence_code` odkazuje na kód bez řádku pro daný rok → řada se založí (kopie masky z předchozího roku), zaloguje se `warning` „řada {code} pro rok {year} založena automaticky".

**Edge Cases:**
- Klient má pro rok 2026 řadu `FAV` i katalogový druh s `sequence_code = 'FV1'` → dvě nezávislé řady, každá s vlastním čítačem; číslo z `FAV` se nikdy nepřidělí dokladu druhu s `FV1`.
- Rok se překlopí (první doklad roku 2027) → nová řada `FV1/2027` s maskou zkopírovanou z `FV1/2026`, `next_number = 1`.
- Ručně přetočený `next_number` zpět → `sequence_number_taken` (`service.py:30-63`) posune na první volné číslo jako dnes; kontrola je per klient, ne per kód, protože partial unique index z migrace 0027 je na `(client_id, acta_sequence_number)`.
- Downgrade po vzniku dvou řad téhož typu ve směru → selže s hláškou; to je záměr, downgrade nesmí tiše sloučit čítače.

**Dependencies:**
- Depends on: none
- Blocks: Step 2 (API a UI potřebují `code`), Step 3 (katalog odkazuje na `sequence_code`), Step 5, Step 14

**Acceptance Criteria:**
- [ ] `alembic upgrade head` na kopii dev schématu projde a `SELECT count(*) FROM client_sequences WHERE code IS NULL` vrátí 0.
- [ ] `backend/tests/sequences/test_service.py` obsahuje test, že `get_next_sequence_number(…, sequence_code='FV1')` a `get_next_sequence_number(…, sequence_code='FAV')` pro téhož klienta a směr vrací čísla ze dvou čítačů (1 a 1), a prochází.
- [ ] `test_migration_0037.py` ověří upgrade i downgrade a simulovanou kolizi; suite `pytest -q backend/tests/migrations` je zelená.
- [ ] Dnešní testy v `backend/tests/sequences/` procházejí beze změny OČEKÁVANÝCH ČÍSEL (volání bez `sequence_code`); jediný vědomě přepsaný test je test unikátního klíče modelu.
- [ ] `bash backend/scripts/run_py_test_gate.sh tests/sequences tests/migrations tests/scripts` je zelený (takto se pytest v projektu pouští; nové DB testy používají `tests.db_guard.skip_or_fail_without_db`, vlastní `pytest.skip` kvůli chybějící DB je zakázaný).
- [ ] Test storna nad skutečnými řádky dokazuje, že `void_sequence_number(…, sequence_code='FV2')` nemění `next_number` ani `updated_at` řady `FAV`.

**Effort:** M
**AID Role:** backend

### Step 2: Kód a název řady v API

**Objective:** API řad vrací `code` a `name`, přijímá volitelný kód při založení a hlídá duplicitu `(kód, rok)`; dnešní volající bez kódu fungují beze změny.

**Files:**
- Modify: `backend/acta/sequences/router.py` (lines ~45-100, 153-212, 213-254) — `SequenceConfigOut.code/name`; `SequenceConfigCreate.code: str | None`, `name: str | None`; kontrola kódu regexem `^[A-Za-z0-9]{1,8}$` v těle handleru s českou hláškou; výchozí kód `legacy_sequence_code(doc_type, direction)`; 409 na duplicitu `(code, year)`; `SequenceConfigPatch.name`. Kontrola odkazu z katalogu při DELETE přibude ve Step 4 (katalog do té doby neexistuje).
- Modify: `backend/tests/sequences/test_router.py` (lines ~590-605) — nové případy na konci: POST bez kódu založí řadu s legacy kódem; neplatný kód → 422 s českou hláškou; duplicitní kód+rok → 409; GET vrací `code` a `name`.

**Parallel group:** wave-2

**Architecture Context:** Router jen zpřístupňuje, co Step 1 zavedl v modelu. Kód řady je to, na co katalog druhů (Step 3, Step 4) odkazuje, proto musí být v API dřív než katalog v UI. Frontendová část (sloupce Kód a Název v nastavení klienta) je ve Step 6, aby tento krok zůstal čistě backendový; do té doby frontend řady zakládá bez kódu a backend doplní legacy kód.

**Implementation Detail:**
Třída těla POST se jmenuje `SequenceConfigCreate` (`sequences/router.py:~60`). `code = (body.code or "").strip() or legacy_sequence_code(body.doc_type, body.direction)`; `if not re.fullmatch(r"[A-Za-z0-9]{1,8}", code): raise HTTPException(422, "Kód řady musí být 1 až 8 písmen nebo číslic.")`. Před INSERT: `SELECT id FROM client_sequences WHERE client_id AND code AND year` → 409 `Řada {code} pro rok {year} už existuje.` `_to_out` (`router.py:78`) přidá `code`, `name`.

**Error Handling:**
- 422 neplatný kód → česká hláška z handleru (ne anglický `string_pattern_mismatch` z Pydanticu).
- 409 duplicitní kód a rok → hláška s kódem a rokem; nic se nezapíše.

**Edge Cases:**
- Dva klienti používají stejný kód `FV1` → povoleno, kód je unikátní jen v rámci klienta a roku.
- Kód s malými písmeny `fv1` → přijme se a uloží tak, jak byl zadán; porovnání v katalogu je citlivé na velikost.
- POST bez kódu pro (faktura, vydaná), když řada `FAV` pro ten rok už existuje → 409 (stejné chování jako dnešní duplicita typu a směru, jen s novou hláškou).

**Dependencies:**
- Depends on: Step 1
- Blocks: Step 4, Step 6

**Acceptance Criteria:**
- [ ] `POST /api/v1/clients/{id}/sequences` bez `code` vrátí 201 a řada má legacy kód; s neplatným kódem vrátí 422 s českou hláškou; s duplicitním `(code, year)` vrátí 409 (testy v `test_router.py`).
- [ ] `GET /api/v1/clients/{id}/sequences` vrací u každé řady `code` a `name`.
- [ ] `frontend/e2e/client-detail.spec.ts` a ostatní dnešní volající POST řad bez kódu fungují beze změny (žádný soubor mimo Files tohoto kroku se nemění).

**Effort:** S
**AID Role:** backend

### Step 3: Tabulka a resolver katalogu druhů; `docdefaults` se mění na adaptér nad katalogem, jeho model a router končí

**Objective:** Katalog druhů existuje v databázi s daty přenesenými ze starého nastavení, resolver vybere pro doklad nejkonkrétnější druh, dnešní volající `docdefaults.service` dostávají stejný tvar odpovědi z výchozího řádku katalogu a do staré tabulky už nic nezapisuje.

**Files:**
- Create: `backend/acta/doctypes/__init__.py` — prázdný.
- Create: `backend/acta/doctypes/models.py` — `ClientDocumentKind` (sloupce níže v Implementation Detail); konstanty `BUILTIN_KIND_CODE = {"prijata": "44", "vydana": "53"}` a `KIND_CODE_UNKNOWN_DIRECTION = "44"` přesunuté z `backend/acta/docdefaults/models.py:19-22`.
- Create: `backend/acta/doctypes/service.py` — `ResolvedKind`, `resolve_document_kind`, `resolve_kind_safe`, `list_kinds`, `upsert_kind`, `delete_kind`.
- Create: `backend/db/versions/0038_document_kinds.py` — `down_revision = "0037"`; tabulka, indexy, CHECKy, kopie dat z `client_document_defaults` (stará tabulka se NEMAŽE, to dělá 0040 ve Step 4).
- Modify: `backend/acta/docdefaults/models.py` (lines ~1-77) — smazat (`git rm`); model `ClientDocumentDefaults` po tomto kroku nikdo nepoužívá.
- Modify: `backend/acta/docdefaults/router.py` (lines ~1-260) — smazat (`git rm`); endpoint `/document-defaults` končí tady, aby mezi Step 3 a Step 4 neexistoval zapisovatel do staré tabulky.
- Modify: `backend/acta/main.py` (lines ~18-25, 160-190) — odstranit import (řádek 21) a `include_router(docdefaults_router)` (řádek 184); registrace metadat nového modelu pro Alembic se dělá v `backend/db/env.py` (další bullet), ne v `main.py`.
- Modify: `backend/db/env.py` (lines ~5-15) — import `ClientDocumentDefaults` z `acta.docdefaults.models` (řádek 11) nahradit importem `ClientDocumentKind` z `acta.doctypes.models`; bez toho po smazání modelu spadne KAŽDÝ příkaz `alembic` (upgrade, downgrade, migrační testy, start kontejneru).
- Create: `backend/tests/doctypes/__init__.py` — prázdný; všechny testové adresáře projektu jsou balíčky a nová suita opakuje basename `test_router.py` (už je v `tests/sequences/` a `tests/registry/`), bez balíčku pytest shodí CELOU kolekci na „import file mismatch".
- Modify: `backend/acta/docdefaults/service.py` (lines ~1-200) — `get_document_defaults`, `list_document_defaults`, `resolve_defaults_safe` čtou výchozí řádek katalogu (`is_default` pro směr) přes `doctypes.service` a vracejí `ResolvedDefaults` beze změny tvaru; `_resolve(row: ClientDocumentDefaults | None, …)` na řádku 55 se přepíše na `ResolvedKind`; `upsert_document_defaults` se odstraní. Konstanty `BUILTIN_DRUH_DOKLADU` a `DRUH_DOKLADU_UNKNOWN_DIRECTION` adaptér importuje z `acta.doctypes.models` pod starými jmény a `builtin_druh_dokladu` v něm zůstává, takže testy volající `docdefaults_service.builtin_druh_dokladu` běží beze změny; `test_direction_change_numbering.py` (Step 5) nahradí monkeypatch `get_document_defaults` (ř. ~207-218) patchem `resolve_kind_safe`.
- Modify: `backend/acta/extraction/fields.py` (lines ~5-12, 440-450) — import `DRUH_DOKLADU_UNKNOWN_DIRECTION` z `acta.docdefaults.models` (řádek 9) nahradit `KIND_CODE_UNKNOWN_DIRECTION` z `acta.doctypes.models`.
- Test: `backend/tests/doctypes/test_resolver.py` (tier: t0) — konkrétnost: řádek s kategorií vyhraje nad výchozím; dva stejně konkrétní rozhodne `priority`; `sequence_code = NULL` dává legacy kód; bez řádků vestavěné 44/53; filtr `self_assessment`; neznámý směr → vestavěné 44.
- Test: `backend/tests/migrations/test_migration_0038.py` (tier: t1) — kopie dvou řádků `client_document_defaults` (jeden s `invoice_number` + maskou, jeden s vlastním druhem `77`) do katalogu, `is_default` nastaveno, stará tabulka stále existuje; downgrade maže jen katalog.
- Modify: `backend/tests/docdefaults/test_docdefaults_api.py` (lines ~1-400) — smazat (`git rm`); testy API se přesouvají do nové suity routeru katalogu ve Step 4.
- Modify: `backend/tests/extraction/test_duna_fields.py` (lines ~10-25) — import `ClientDocumentDefaults` (řádek 18) nahradit `ClientDocumentKind`; fixtury zakládají výchozí řádek katalogu.
- Modify: `backend/tests/sequences/test_resolve_acta_number.py` (lines ~1-80) — fixtura nastavení klienta zakládá výchozí řádek katalogu místo řádku `client_document_defaults`.
- Modify: `backend/tests/e2e/test_p018_full.py` (lines ~1-200) — příprava nastavení klienta přes `doctypes.service.upsert_kind` místo `PUT /document-defaults` a místo zápisu do staré tabulky; scénář oprávnění (viewer nesmí měnit nastavení) se přesouvá do `backend/tests/doctypes/test_router.py` ve Step 4. Test má marker `stack`.
- Modify: `backend/tests/e2e/test_issued_pipeline_p018.py` (lines ~1-200) — příprava nastavení klienta přes `doctypes.service.upsert_kind` místo zápisu do `client_document_defaults`. Test má marker `stack`.
- Modify: `backend/tests/scripts/test_fix_issued_invoices_p018.py` (lines ~1-80) — fixtura nastavení přes katalog (brána skriptu na existenci tabulky se mění ve Step 4).

**Reuse check:** searched: `grep -rl "document_kind" backend/acta` → none

**Parallel group:** wave-1b

**Architecture Context:** Katalog je druhá noha modelu vedle řad (Step 1). Resolver je jediné místo, kde se rozhoduje o druhu; ve Step 5 ho začnou volat extrakce, přepočet odvozených polí, změna směru/klienta a split balíku, ve Step 4 náhled v API. Adaptérová vrstva `docdefaults.service` existuje proto, aby Step 3 šel dokončit dřív, než Step 5 přepíše pět volání `resolve_defaults_safe` a jedno `get_document_defaults`: `ResolvedDefaults(druh_dokladu, number_source, number_read_mask, configured)` se plní z `ResolvedKind` výchozího řádku. Test `backend/tests/migrations/test_0030_client_document_defaults.py` model neimportuje, ale dělá `upgrade head` (řádek ~118) a ověřuje tabulku na hlavě; v tomto kroku ještě prochází (0038 tabulku nemaže), Step 4 ho upraví spolu s migrací 0040.

**Implementation Detail:**
Tabulka `client_document_kinds`: `id` UUID PK; `client_id` UUID FK `clients.id` ON DELETE CASCADE NOT NULL; `code` VARCHAR(8) NOT NULL CHECK `code ~ '^[A-Za-z0-9]{1,8}$'`; `name` TEXT NOT NULL; `direction` ENUM `invoicedirection` (`create_type=False`) NOT NULL; `doc_types` ARRAY(ENUM `documenttype`) NOT NULL DEFAULT `'{faktura}'` CHECK `cardinality(doc_types) > 0`; `vat_categories` ARRAY(VARCHAR(40)) NULL; `supply_kinds` ARRAY(VARCHAR(8)) NULL; `self_assessment` BOOLEAN NULL; `sequence_code` VARCHAR(8) NULL (NULL = řada podle typu písemnosti přes `legacy_sequence_code` ze Step 1); `number_source` VARCHAR(16) NOT NULL DEFAULT `'sequence'` CHECK IN (`'sequence'`,`'invoice_number'`); `number_read_mask` VARCHAR(64) NULL CHECK `number_source = 'sequence' OR number_read_mask IS NOT NULL`; `tax_doc_type` VARCHAR(4) NULL; `priority` INTEGER NOT NULL DEFAULT 100; `is_default` BOOLEAN NOT NULL DEFAULT FALSE; `created_at`, `updated_at` TIMESTAMPTZ; unikátní `(client_id, code)`; partial unique `(client_id, direction) WHERE is_default`.
Resolver: `rows = SELECT * FROM client_document_kinds WHERE client_id = :c AND direction = :d AND :doc_type = ANY(doc_types)`; v Pythonu filtr `vat_categories IS NULL OR vat_category IN vat_categories` (kategorie = `doc.vat_category or doc.vat_category_proposed`), totéž pro `supply_kinds` a `self_assessment`; skóre = počet vyplněných podmínkových sloupců (0–3); výběr `max(score)`, pak `min(priority)`, pak `code`; `matched_by = "+".join(vyplněné podmínky)`; žádná shoda → řádek `is_default` pro směr (`matched_by = "default"`); žádný → `ResolvedKind(code=BUILTIN_KIND_CODE[direction], name="Vestavěný", sequence_code=None, number_source="sequence", number_read_mask=None, tax_doc_type=None, configured=False, matched_by="builtin")`. `direction is None` → `KIND_CODE_UNKNOWN_DIRECTION` (dnešní chování, `docdefaults/service.py:76-90`). `resolve_kind_safe` obalí dotaz SAVEPOINTem a při výjimce vrátí vestavěný druh s warningem (vzor `docdefaults/service.py:resolve_defaults_safe`).
Migrace 0038: `CREATE TABLE`; `INSERT INTO client_document_kinds (…) SELECT gen_random_uuid(), client_id, COALESCE(druh_dokladu, CASE direction WHEN 'vydana' THEN '53' ELSE '44' END), CASE direction WHEN 'vydana' THEN 'Výchozí vydané' ELSE 'Výchozí přijaté' END, direction, ARRAY['faktura','dobropis','zalohova','jine']::documenttype[], NULL, NULL, NULL, NULL, number_source, number_read_mask, NULL, 100, TRUE, now(), now() FROM client_document_defaults`; kontrola `count(*)` obou tabulek se musí rovnat, jinak `RuntimeError`. Downgrade: `DROP TABLE client_document_kinds`.

**Error Handling:**
- Tabulka `client_document_kinds` na hostu bez migrace → `resolve_kind_safe` vrátí vestavěný druh a zaloguje warning; vytěžení nespadne.
- Počet zkopírovaných řádků nesouhlasí → migrace selže, transakce se vrátí, stará tabulka je netknutá.
- Dva řádky `is_default` pro jeden směr → partial unique index odmítne INSERT; router (Step 4) překládá na 409.

**Edge Cases:**
- Klient má výchozí řádek pro `vydana`, ale ne pro `prijata` → přijatý doklad dostane vestavěné `44`, `configured = False`.
- Klient měl ve staré tabulce vlastní druh `77` → migrace založí řádek `77` s `is_default = TRUE`; šablona (Step 4) ho nepřepíše.
- Doklad má kategorii `mixed` → žádný řádek s `vat_categories` ji nemá (router ji do podmínek nepustí), padá na výchozí řádek; export ho stejně dá do `_NEIMPORTOVAT`.
- `doc_type` je NULL (vytěžení typ neurčilo) → resolver hledá s `'faktura'` (dnešní fallback `doc.doc_type or "faktura"` v `documents/router.py:616`).
- Frontend mezi Step 3 a Step 6 volá zrušený `/document-defaults` → karta „Výchozí hodnoty dokladů" ukáže chybu načtení; EPIC 1 se proto nasazuje jako celek (viz `## Constraints`).

**Dependencies:**
- Depends on: Step 1 — `sequence_code` odkazuje na kód řady a `legacy_sequence_code` na fallback; migrace 0038 navazuje na 0037
- Blocks: Step 4, Step 5, Step 7

**Acceptance Criteria:**
- [ ] `test_resolver.py` pokrývá šest případů z Files a prochází.
- [ ] Po `alembic upgrade 0038` nad kopií dev schématu se `SELECT count(*) FROM client_document_kinds WHERE is_default` rovná počtu řádků `client_document_defaults` a stará tabulka stále existuje (test 0038).
- [ ] `docker exec -w /app/backend acta-api python -m pytest -q tests --collect-only` skončí bez collection erroru (žádný test neimportuje smazaný `acta.docdefaults.models`, nový adresář je balíček).
- [ ] `docker exec -w /app/backend acta-api alembic upgrade head` a `alembic downgrade 0037` projdou (důkaz, že `db/env.py` nezávisí na smazaném modelu).
- [ ] Ruční běh testů se značkou `stack`, které výchozí pytest vyřazuje (`backend/pyproject.toml:41`, `addopts = "-m 'not stack'"`): `docker exec -w /app/backend acta-api python -m pytest -m stack -q tests/e2e/test_p018_full.py tests/e2e/test_issued_pipeline_p018.py` je zelený; výstup se přiloží do evidence kroku. `--collect-only` hlídá jen importy, ne chování.
- [ ] `backend/tests/documents/test_derived_fields_all_paths.py` a `test_direction_change_derived_fields.py` procházejí beze změny (adaptér `docdefaults.service` drží tvar `ResolvedDefaults`).
- [ ] `grep -rn "upsert_document_defaults\|docdefaults.models\|docdefaults_router" backend/acta backend/db backend/scripts` vrací 0 řádků.

**Effort:** L
**AID Role:** backend

### Step 4: API katalogu, pole „účetní program", šablony DUNA / Pohoda / ABRA a odstavení staré tabulky

**Objective:** Účetní může katalog spravovat přes API s auditní stopou, klient má pole účetního programu, jedním voláním se katalog předvyplní šablonou programu, a stará tabulka `client_document_defaults` je po kontrole smazaná.

**Files:**
- Create: `backend/db/versions/0039_client_accounting_system.py` — `down_revision = "0038"`; `clients.accounting_system` VARCHAR(16) NULL s CHECK IN (`'duna'`,`'pohoda'`,`'abra_flexi'`,`'money'`,`'other'`).
- Create: `backend/db/versions/0040_rename_client_document_defaults_legacy.py` — `down_revision = "0039"`; preflight (každý řádek staré tabulky má výchozí protějšek v katalogu, jinak `RuntimeError` s výpisem) + `ALTER TABLE client_document_defaults RENAME TO client_document_defaults_legacy` (včetně přejmenování jejích constraintů, aby jména nekolidovala při pozdějším downgrade 0030); downgrade přejmenuje zpět. Žádný zápis do `audit_log`.
- Modify: `backend/acta/clients/models.py` (lines ~33-40) — sloupec `accounting_system`.
- Modify: `backend/acta/clients/schemas.py` (lines ~97, 127, 169) — `accounting_system: Literal['duna','pohoda','abra_flexi','money','other'] | None` v Create/Update/Out.
- Modify: `backend/acta/clients/service.py` (lines ~205-215) — zápis pole při create/update.
- Create: `backend/acta/doctypes/templates.py` — `TEMPLATES: dict[str, list[KindTemplate]]` (obsah v Implementation Detail).
- Create: `backend/acta/doctypes/router.py` — endpointy katalogu (úplný kontrakt v Implementation Detail).
- Modify: `backend/acta/doctypes/service.py` (lines ~1-200) — `apply_template(session, client_id, system, mode)`, `preview_kind(...)`, automatické `is_default` pro první druh směru.
- Modify: `backend/acta/main.py` (lines ~18-25, 160-190) — import a registrace `doctypes.router`.
- Modify: `backend/acta/sequences/router.py` (lines ~255-290) — `delete_sequence`: `SELECT count(*) FROM client_document_kinds WHERE client_id = :c AND sequence_code = :code` → 409 `Na řadu odkazuje druh dokladu {code}.` při > 0.
- Modify: `backend/scripts/fix_issued_invoices_p018.py` (lines ~90-100, 360-380) — brána `assert_docdefaults_deployed` (řádek 367) hledá `to_regclass('client_document_kinds')` místo `client_document_defaults`; import `get_document_defaults` zůstává (adaptér ze Step 3).
- Modify: `backend/tests/scripts/test_fix_issued_invoices_p018.py` (lines ~80-140) — test brány nad novou tabulkou.
- Test: `backend/tests/doctypes/test_router.py` (tier: t1) — CRUD, `viewer` smí GET a nesmí zápis (403), cizí `kind_id` → 404, `DELETE`/změna kódu druhu s doklady ke kontrole → 409, `replace` zapíše `document_kind_deleted` pro každý smazaný řádek, 422 hlášky, 409 duplicitní kód a druhý default, první druh směru se stane výchozím, audit záznamy, `apply-template duna add_missing` založí 8 druhů, vrátí `sequences_missing` a při druhém volání `created = 0`, klient s vlastním výchozím `77` si ho po šabloně ponechá, `replace` odmítne s 409 při dokladu `to_review` na druhu, `preview` s `invoice_number` vrátí `2600241` pro masku `10{NNN}{YY}` a řadu `{YY}{NNNNN}`.
- Test: `backend/tests/migrations/test_migration_0040.py` (tier: t1) — preflight zastaví přejmenování, když řádek staré tabulky nemá protějšek v katalogu; úspěšný běh: stará tabulka pod starým jménem neexistuje, `client_document_defaults_legacy` má stejný počet řádků; downgrade ji vrátí pod původním jménem i po použití šablony s alfanumerickými kódy.
- Modify: `backend/tests/migrations/test_0030_client_document_defaults.py` (lines ~110-130) — `upgrade head` (řádek ~118) nahradit `upgrade 0039`, protože od 0040 tabulka pod původním jménem neexistuje; test dál ověřuje migraci 0030 nad izolovaným schématem.
- Modify: `backend/tests/sequences/test_router.py` (lines ~590-605) — DELETE řady, na kterou odkazuje druh, vrátí 409.
- Modify: `backend/tests/clients/test_clients_api.py` (lines ~1-32) — `accounting_system` v create/patch, 422 pro neznámou hodnotu.

**Reuse check:** searched: `grep -rl "accounting_system" backend/acta frontend/src` → none

**Parallel group:** wave-2b

**Architecture Context:** Router zpřístupňuje katalog ze Step 3 a šablony jsou první místo, kde se projeví hranice generické vs. specifické: šablona je per účetní program, resolver program nezná. Náhled nahrazuje dnešní `docdefaults/router.py` preview (zrušený ve Step 3) a musí zůstat věrný tomu, jak se odvozené číslo renderuje: maskou CÍLOVÉ řady (`sequences/service.py:265-350`), ne čtecí maskou. Smazání staré tabulky je tady, až po Step 3, kdy do ní nikdo nezapisuje.

**Implementation Detail:**
API (prefix `/api/v1/clients/{client_id}/document-kinds`, role `_require_admin_or_accountant` vzor `sequences/router.py:35`, klient `_resolve_client` vzor `sequences/router.py:111`):
- `GET` → 200 `[DocumentKindOut]` seřazené `direction, priority, code`; 404 klient neexistuje; čtení smí i role `viewer` (dnešní GET řad a nastavení to dovolují také); 401 bez přihlášení.
- `POST` (jen `accountant`/`admin`, `viewer` 403) body `DocumentKindIn {code, name, direction, doc_types: [str], vat_categories?: [str] | null, supply_kinds?: [str] | null, self_assessment?: bool | null, sequence_code?: str | null, number_source: 'sequence' | 'invoice_number', number_read_mask?: str | null, tax_doc_type?: str | null, priority?: int, is_default?: bool}` → 201; 422 `Kód druhu musí být 1 až 8 písmen nebo číslic.`, `Neznámá daňová kategorie: {x}.` (hodnoty z `VAT_CATEGORIES` v `documents/models.py:54-67` bez `mixed`), `Neznámá povaha plnění: {x}.` (`SUPPLY_KINDS`, `documents/models.py:110`), `Odvození Čísla ACTA z čísla faktury lze zapnout jen u vydaných dokladů.`, `Pro odvození z čísla faktury je potřeba čtecí maska.`, chyba `validate_read_mask` (`sequences/mask.py:217`); 409 `Druh {code} už existuje.`, `Směr už má výchozí druh {code}.`. Když směr žádný výchozí druh nemá, první založený druh dostane `is_default = TRUE` i bez požadavku.
- `PUT /{kind_id}` stejné tělo → 200; stejné chyby; 404 cizí klient.
- `DELETE /{kind_id}` → 204; 409 `Výchozí druh nelze smazat, nejdřív označte jiný.`
- `POST /apply-template` body `{system, mode}` → 200 `{created, skipped, skipped_defaults, deleted, sequences_missing}`; 422 `Šablona pro program {system} neexistuje.`; 409 u `replace` s výčtem kódů druhů, na kterých jsou doklady `to_review`.
- `POST /preview` body `{direction, doc_type, vat_category?, supply_kind?, self_assessment?, invoice_number?}` → 200 `{kind_code, kind_name, matched_by, sequence_code, number_preview: str | null, tax_doc_type: str | null, note: str | null}`; u `invoice_number` renderuje maskou cílové řady; když řada pro kód neexistuje, `number_preview = null` a `note`.
- Audit: `document_kind_created`, `document_kind_updated` (old/new po polích), `document_kind_deleted` (`old` = JSON celého řádku), `document_kinds_template_applied` (`new` = JSON `{system, mode, created, skipped, skipped_defaults, deleted}`); režim `replace` navíc zapíše `document_kind_deleted` pro KAŽDÝ smazaný řádek, aby smazaný katalog měl stopu; `entity_type="client"`, `entity_id=client_id`. Vlastnictví: `PUT` i `DELETE /{kind_id}` načítají řádek přes `WHERE id = :kind_id AND client_id = :client_id` (vzor `_load_owned_sequence`, `sequences/router.py:123`) → cizí `kind_id` = 404. `PUT` se změnou `code` a `DELETE` vracejí 409 `Na druhu {code} jsou doklady ke kontrole.`, když existuje doklad `to_review` s `fields->>'druh_dokladu' = code` (stejný dotaz jako u `replace`).
Šablona DUNA (`TEMPLATES["duna"]`): přijaté `44` „Přijatá faktura" (výchozí, všechny čtyři typy písemnosti, `sequence_code="PF"`, navržená maska `FAP-{YYYY}/{NNNN}`); vydané `53` „Vystavená faktura – služby" (výchozí, `faktura`, `domestic_standard`, `service`, `FV1`, `D1`), `501` „zboží do ČR" (`domestic_standard`, `goods`, `FV1`, `D1`), `502` „zboží EU plátci DPH" (`eu_goods_supply`, `goods`, `FV2`, `U1`), `503` „zboží mimo EU" (`export_goods`, `goods`, `FV3`, `EX`), `504` „zboží EU neplátci" (`eu_goods_supply`, `goods`, `FV4`, `DZ`, `priority=200`, poznámka v `name`: „odběratel neplátce, vybrat ručně"), `532` „služby do EU" (`eu_service_reverse_charge`, `service`, `FV2`, `U8`), `533` „služby mimo EU" (`out_of_scope`, `service`, `FV3`, `MT`). Navržené masky řad (`suggested_mask`): `FV1 {YY}{NNNNN}`, `FV2 4{YY}{NNNNN}`, `FV3 3{YY}{NNNNN}`, `FV4` bez návrhu (`null`: ze snímku DUNY tvar nejde vyčíst a stejná maska jako `FV1` by vyrobila dva čítače renderující totéž číslo) — jsou to odhady ze snímku DUNY, proto je šablona jen VRACÍ v `sequences_missing` a řady nezakládá. `same_mask_as` se počítá proti existujícím řadám klienta I proti ostatním položkám `sequences_missing`. Pohoda: `FV` (vydané, výchozí), `FP` (přijaté, výchozí), bez `tax_doc_type`. ABRA Flexi: `FAKTURA` → kód `FAV` a `FAP` (kód max 8 znaků), bez `tax_doc_type`.
`apply_template`: pro každý `KindTemplate`: existuje kód → `skipped`; jinak INSERT s `is_default = template.is_default AND směr ještě výchozí nemá`. `sequences_missing`: pro každý odlišný `sequence_code` šablony bez řádku `client_sequences (client_id, code, year = aktuální)` → `{code, suggested_mask, same_mask_as}` kde `same_mask_as = SELECT code FROM client_sequences WHERE client_id AND year AND mask = suggested_mask LIMIT 1`. `replace`: `SELECT k.code FROM client_document_kinds k WHERE k.client_id = :c AND EXISTS (SELECT 1 FROM documents d WHERE d.client_id = k.client_id AND d.status = 'to_review' AND d.fields->>'druh_dokladu' = k.code)` → 409; jinak DELETE řádků klienta a INSERT šablony.
Migrace 0040: `missing = SELECT d.client_id, d.direction FROM client_document_defaults d LEFT JOIN client_document_kinds k ON k.client_id = d.client_id AND k.direction = d.direction AND k.is_default WHERE k.id IS NULL` → při nálezu `RuntimeError` s výpisem; jinak `ALTER TABLE client_document_defaults RENAME TO client_document_defaults_legacy` a přejmenování constraintů `uq_client_document_defaults_client_direction`, `ck_client_document_defaults_*` s příponou `_legacy`.

**Error Handling:**
- `system` mimo šablony → 422; nic se nezapíše.
- `replace` s dokladem k revizi na některém druhu → 409 s výčtem kódů, nic se nemaže.
- Preflight 0040 najde řádek bez protějšku → migrace selže před přejmenováním, tabulka i katalog zůstávají.
- Skript `fix_issued_invoices_p018.py` na hostu bez migrace 0038 → brána vrátí exit 2 s hláškou jako dnes, jen s novým názvem tabulky.

**Edge Cases:**
- Klient má `accounting_system = NULL` a účetní zavolá `apply-template duna` → povoleno; šablona pole u klienta nemění.
- Klient má z migrace výchozí `53` → `add_missing` ho přeskočí (stejný kód), ostatních 7 založí; výchozí zůstává původní řádek včetně jeho čtecí masky.
- Klient má z migrace výchozí `77` → šablonový `53` se vloží s `is_default = FALSE`; odpověď to uvede v `skipped_defaults: ["53"]` (klíč je součástí kontraktu odpovědi).
- `DELETE` nebo `PUT` s cizím `kind_id` (druh jiného klienta) → 404; test v `test_router.py`.
- Míšin klient má řadu `FAV` s maskou `{YY}{NNNNN}` → `sequences_missing` pro `FV1` vrátí `same_mask_as = "FAV"`; UI (Step 6) nabídne „připojit druhy k řadě FAV" místo založení druhé řady se stejnou maskou.
- `PUT` mění `sequence_code` u druhu, na kterém jsou doklady `to_review` s náhledem čísla → povoleno; číslo ještě přidělené není (Step 14), náhled se přepočítá.

**Dependencies:**
- Depends on: Step 2, Step 3
- Blocks: Step 5, Step 6

**Acceptance Criteria:**
- [ ] `backend/tests/doctypes/test_router.py` prochází včetně idempotence `apply-template`, zachování vlastního výchozího `77`, `sequences_missing.same_mask_as` a `preview` `2600241`.
- [ ] `GET /openapi.json` neobsahuje cestu `/api/v1/clients/{client_id}/document-defaults` a obsahuje `/document-kinds`.
- [ ] `PATCH /api/v1/clients/{id}` s `accounting_system: 'duna'` se uloží a vrátí; `'sap'` vrátí 422.
- [ ] `alembic upgrade head` a `downgrade 0038` pro 0039 a 0040 projdou nad kopií schématu; `test_migration_0040.py` dokazuje preflight, přejmenování i downgrade po použití šablony.
- [ ] DELETE řady, na kterou odkazuje druh, vrátí 409 s kódem druhu (`backend/tests/sequences/test_router.py`).
- [ ] Po CRUD operaci nad katalogem existuje v `audit_log` řádek s odpovídající akcí (test v `test_router.py`).

**Effort:** L
**AID Role:** backend

### Step 5: Jednotné pořadí klasifikace → druh → číslo ve všech čtyřech cestách a přepočet druhu po změně kategorie

**Objective:** Extrakce, změna klienta, změna směru i split balíku běží v pořadí (storno) → protistrana → klasifikace → druh → číslo; druh se přepočítá i po každé změně kategorie nebo povahy plnění; číslo bere řadu a čtecí masku z druhu; ručně zvolený druh se nepřepisuje; změna druhu u dokladu s číslem odvozeným z faktury číslo odvodí znovu.

**Files:**
- Modify: `backend/acta/jobs/extraction.py` (lines ~1025-1040, 1085-1195) — určení druhu z řádků 1032-1037 se RUŠÍ a přesouvá ZA blok klasifikace (`reclassify_document`, dnes ~1170-1185, který zůstává za `sync_counterparty` ~1091, protože klasifikace protistranu čte); blok čísla (dnes 1141-1169) se přesouvá ZA určení druhu. Výsledné pořadí: protistrana → klasifikace → druh → číslo.
- Modify: `backend/acta/documents/derived_fields.py` (lines ~40-100) — signatura `-> tuple[list[dict[str, Any]], ResolvedKind]`; místo `resolve_defaults_safe` (řádek 75) volá `resolve_kind_safe`; pravidlo chráněného druhu a fallback (Implementation Detail).
- Modify: `backend/acta/documents/service.py` (lines ~584-598) — `patch_document_field` pro `field_key == "druh_dokladu"`: vedle `edited_by_user = True` zapíše `state = "manual"`, `kind_code`, `kind_name`; když je doklad `reviewed`, vrátí ho do `to_review` (Step 14 zavádí přechod; do té doby 409 `Druh schváleného dokladu nelze měnit.`); po změně zavolá `renumber_if_series_changed` (níže).
- Modify: `backend/acta/extraction/fields.py` (lines ~698-720) — `apply_duna_document_type(doc, druh_dokladu, *, kind_code=None, kind_name=None, matched_by=None, state='proposed')` zapisuje nové klíče meta do NOVÉHO dictu (ne mutací).
- Modify: `backend/acta/documents/router.py` (lines ~600-700, 740-910) — změna klienta: dnešní pořadí `resolve_acta_number` (645) → `sync_counterparty` → `apply_direction_derived_fields` (688) se mění na storno → `sync_counterparty` → `apply_direction_derived_fields` → `resolve_acta_number`; změna směru: dnešní `resolve_acta_number` (807) → `apply_direction_derived_fields` (840) → `reclassify_document` (901) se mění na storno → `sync_counterparty` → `reclassify_document` → `apply_direction_derived_fields` → `resolve_acta_number`. Obě cesty rozbalují tuple a předávají `sequence_code`/`number_source`/`read_mask` z `kind`; storno předává `sequence_code` přečtený z `fields_meta._acta_number.sequence_code` (fallback `legacy_sequence_code` pro čísla přidělená před P025); audit `sequence_number_set` se při odkladu (`None`) nezapisuje a `_record_acta_number_meta` dostane jen telemetrii.
- Modify: `backend/acta/documents/bundle.py` (lines ~125-205) — `apply_direction_derived_fields` (dnes řádek 198) se volá PŘED `resolve_acta_number` (dnes 167); `resolve_defaults_safe` na řádku 131 mizí; tuple a `None` jako výše.
- Modify: `backend/acta/registry/subject_link.py` (lines ~265-330) — na konci `reclassify_document` (po `_apply_updates`, když se návrh kategorie změnil) zavolat přepočet druhu `apply_direction_derived_fields` a `renumber_if_series_changed`; tím se druh přepočítá u všech šesti volajících `reclassify_document` (extrakce, `fields_router.py:248`, `documents/service.py:621`, `documents/router.py:901`, `line_router.py:337`, `registry/service.py`).
- Modify: `backend/acta/documents/vat_category_router.py` (lines ~156-243, 244-330) — po `confirm` i `override` kategorie totéž (přepočet druhu + `renumber_if_series_changed`), protože tyto cesty `reclassify_document` nevolají.
- Modify: `backend/acta/sequences/service.py` (lines ~205-350) — `resolve_acta_number(…, sequence_code=None, number_source=None, read_mask=None, assign_now=False) -> tuple[str | None, dict]`; nová funkce `renumber_if_series_changed(session, doc, kind) -> dict | None`.
- Modify: `backend/scripts/fix_issued_invoices_p018.py` (lines ~655-700) — volání `resolve_acta_number` na řádku 672 předává `sequence_code` z `resolve_kind_safe` a `assign_now=True` (skript přečíslovává doklady, které účetní už viděla a schválila ve výpisu dry-runu; bez toho by se po zapnutí přepínače ve Step 14 tiše změnil v no-op); `void_sequence_number` na řádku 663 dostává `sequence_code` z telemetrie dokladu.
- Modify: `backend/acta/documents/schemas.py` (lines ~30-80) — `DocumentOut.document_kind: {code, name, state, matched_by} | null` čtené z `fields.druh_dokladu` a `fields_meta.druh_dokladu` (`name` z `kind_name`); `number_assignment: 'assigned' | 'deferred' | 'invoice_number' | 'none'` z `fields_meta._acta_number`; `number_series_mismatch: bool` (číslo z čítače je z jiné řady, než na kterou ukazuje druh).
- Modify: `backend/acta/config.py` (lines ~40-60) — `SEQUENCE_ASSIGN_AT_APPROVAL: bool = False`.
- Modify: `backend/tests/documents/test_derived_fields_all_paths.py` (lines ~60-360) — mocky `apply_direction_derived_fields` a `resolve_kind_safe` v novém tvaru (tuple); nové případy: druh z katalogového řádku s kategorií na všech třech cestách; doklad s `edited_by_user=True` bez `state` se nepřepisuje; ruční druh přes `patch_document_field` dostane `state='manual'`; druh, jehož kód v katalogu už není → výchozí druh směru + varování v událostech.
- Modify: `backend/tests/documents/test_direction_change_derived_fields.py` (lines ~95-110, 220-235, 370-385) — mocky `resolve_defaults_safe` na řádcích 103, 227 a 378 nahradit `resolve_kind_safe`; návratová hodnota tuple.
- Modify: `backend/tests/documents/test_direction_change_numbering.py` (lines ~90-364) — mocky v novém tvaru; nové případy nad skutečnými řádky `client_sequences`: pořadí při změně směru je storno → klasifikace → druh → číslo (číslo jde z řady druhu určeného PO překlasifikaci); `_acta_number.sequence_code` nese kód řady druhu; storno čísla z řady `FV2` se dotkne `FV2`, ne `FAV`; druh se čtecí maskou `30{NNN}{YY}` dá z `3000526` číslo `42600005` pro řadu `4{YY}{NNNNN}` a posune čítač na 6; `None` z `resolve_acta_number` se zapíše jako odklad bez pádu a bez auditu `sequence_number_set`.
- Modify: `backend/tests/documents/test_split_direction.py` (lines ~1-99) — mocky v novém tvaru; dítě balíku dostane druh z katalogu dominantního klienta a číslo z řady tohoto druhu.
- Modify: `backend/tests/documents/test_vat_category_decision.py` (lines ~1000-1095) — nový případ: override kategorie na `eu_goods_supply` u vydané faktury přepočítá druh na `502` a číslo odvozené z faktury se přerenderuje maskou řady druhu `502`.
- Modify: `backend/tests/extraction/test_direction_ordering.py` (lines ~1-60, konec souboru) — nové případy pořadí v extrakci nad SDÍLENÝM harnessem z `backend/tests/extraction/test_extract_document_integration.py` (docstring řádky 10-12 varuje před jeho kopírováním): přijatý doklad s kategorií `domestic_reverse_charge` dostane číslo z řady druhu, který má tuto kategorii v podmínce.
- Modify: `backend/tests/extraction/test_extract_document_integration.py` (lines ~1-120) — očekávání pořadí volání v harnessu podle nového pořadí (protistrana → klasifikace → druh → číslo).
- Modify: `backend/tests/sequences/test_resolve_acta_number.py` (lines ~543-556) — `_fake` v `_stub_resolve` přijme nové keyword argumenty (`sequence_code`, `number_source`, `read_mask`, `assign_now`) a vrací `(number, meta)`; bez toho volání s novými argumenty spadne na `TypeError`.
- Modify: `backend/tests/documents/test_field_edit.py` (lines ~390-470) — harness `_run_patch` očekává nové pořadí auditů (storno → protistrana → klasifikace → druh → číslo) a fake funkce mají nové signatury (`apply_direction_derived_fields` vrací tuple, `resolve_acta_number` s novými argumenty).
- Modify: `backend/tests/registry/test_subject_link.py` (lines ~480-640) — `reclassify_document` nově na konci volá přepočet druhu a `renumber_if_series_changed`; testy je mockují (`monkeypatch`), jinak by sahaly do DB a katalogu.

**Parallel group:** wave-3

**Architecture Context:** Tohle je místo, kde se model (Step 1, Step 3, Step 4) potká s dnešními cestami přidělování. Dnes se číslo přiděluje dřív než druh ve VŠECH čtyřech cestách, a druh se po vytěžení přepočítává jen při změně směru, klienta a u splitu; kategorie tedy nemůže ovlivnit druh ani řadu, a právě to má katalog umožnit (řada 30 klienta podle kategorie). `apply_direction_derived_fields` má tři volající (`bundle.py:198`, `router.py:688`, `router.py:840`), kteří dnes iterují přímo návratovou hodnotu, a potřebuje `supplier_obj` ze `sync_counterparty`, proto musí `sync_counterparty` zůstat před ní. Přepínač `SEQUENCE_ASSIGN_AT_APPROVAL` vzniká tady vypnutý, aby EPIC 1 šel nasadit bez změny okamžiku číslování; Step 8 do pořadí vloží daňový profil mezi klasifikaci a druh. Extrakce běží v kontejneru `acta-worker`, změny směru a klienta v `acta-api`; po nasazení se restartují oba.

**Implementation Detail:**
`derived_fields.py`: `kind = await resolve_kind_safe(session, client_id, direction=direction, doc_type=doc.doc_type or "faktura", vat_category=doc.vat_category or doc.vat_category_proposed, supply_kind=(doc.fields or {}).get("supply_kind"), self_assessment=getattr(doc, "self_assessment", None), log_ref=ref)`; `protected = druh_meta.get("edited_by_user") or druh_meta.get("state") == "manual"` (stav `reviewed` druh NEZAMYKÁ: dnešní změna směru/klienta u `reviewed` je povolená a přepočítává druh, což zůstává; zámek přes znovuotevření přináší až Step 14) — původní verze podmínky: `... or doc.status in ("reviewed", "archived")`; pokud `not protected and (kind.code != old_druh or druh_meta.get("kind_code") != kind.code)` → `apply_duna_document_type(doc, kind.code, kind_code=kind.code, kind_name=kind.name, matched_by=kind.matched_by)` + událost `druh_dokladu_rederived`. Když je druh chráněný, vrací se `kind` dohledaný podle AKTUÁLNÍHO kódu dokladu (`SELECT … WHERE client_id AND code = fields.druh_dokladu`); když takový řádek v katalogu není (druh byl smazán nebo přejmenován), vrací se výchozí druh směru a do událostí jde `druh_dokladu_kind_missing` s varováním, číslo pak jde z řady výchozího druhu.
`resolve_acta_number`: `code = sequence_code or legacy_sequence_code(doc_type, direction or "prijata")`; `src = number_source or defaults.number_source`; `mask = read_mask if read_mask is not None else defaults.number_read_mask`; odklad: `if settings.SEQUENCE_ASSIGN_AT_APPROVAL and direction == "vydana" and src == "sequence" and not assign_now: return None, {"source": "deferred", "reason": "deferred_to_approval", "sequence_code": code}`. Telemetrie vždy nese `sequence_code`. Volající a jejich zpracování `None`: extrakce, `bundle.py`, `router.py` (obě cesty) zapíšou `acta_sequence_number = None` + telemetrii, bez auditu `sequence_number_set`; skript volá s `assign_now=True`, takže `None` nedostane.
`renumber_if_series_changed(session, doc, kind)`: jen když `doc.status in ("new","extracting","to_review")`, `doc.direction == "vydana"`, doklad číslo má a `fields_meta._acta_number.source in ("invoice_number", "sequence_fallback")`, a `(kind.sequence_code or legacy) != meta.sequence_code` nebo se liší čtecí maska → `void_sequence_number(…, sequence_code=meta.sequence_code)` + audit `sequence_voided`, pak `resolve_acta_number(…)` s hodnotami z `kind` + audit `sequence_number_set`. U čísla z čítače (`source == "sequence"`, přijaté doklady) se NIC nemění; `DocumentOut.number_series_mismatch` to jen označí pro detail (Step 9).

**Error Handling:**
- Resolver nedostupný (chybějící tabulka) → vestavěný druh, warning, číslo z legacy kódu; vytěžení pokračuje.
- Klasifikace selže (výjimka v `reclassify_document`) → dnešní chování: spolknuto v `begin_nested`, stav `not_run`; druh se určí bez kategorie, číslo z řady takto určeného druhu.
- Čtecí maska druhu nepřečte číslo faktury → fallback na čítač řady druhu (dnešní `sequence_fallback`, `sequences/service.py:320-338`) s `attempted` v telemetrii; `needs_review` jen při kolizi jako dnes.
- Nové odvození čísla po změně druhu koliduje s obsazeným číslem → dnešní fallback na čítač cílové řady + `needs_review`; staré číslo zůstává stornované s auditem.

**Edge Cases:**
- Doklad bez klienta (Nezařazeno) → resolver vrací vestavěný druh podle směru, číslo se nepřiděluje (podmínka `doc.client_id is not None`, `jobs/extraction.py:1141-1145`).
- Doklad z doby před nasazením má `edited_by_user=True` a žádné `state` → bere se jako ruční, druh se nepřepíše.
- Faktura `3000526` dostala při vytěžení výchozí druh `53` (čtecí maska `10{NNN}{YY}` ji nepřečte → číslo z čítače, `source = sequence_fallback`); účetní změní druh na `532` se čtecí maskou `30{NNN}{YY}` → staré číslo se stornuje v řadě `FV1`, nové se odvodí jako `42600005` v řadě `FV2`.
- Přijatý doklad, kterému override kategorie změní druh PO přidělení čísla z čítače → číslo zůstává, `number_series_mismatch = true`, detail upozorní; vědomé: přečíslování přijatých z čítače by dělalo díry.
- Dítě balíku vzniklo bez klienta a při dopárování má kategorii `not_run` → druh z výchozího řádku; po klasifikaci se přepočítá přes `reclassify_document`.

**Dependencies:**
- Depends on: Step 1, Step 3, Step 4 — šablona a API katalogu nejsou nutné pro kód, ale testy zakládají druhy přes `doctypes.service`
- Blocks: Step 7, Step 8, Step 9, Step 14

**Acceptance Criteria:**
- [ ] `test_direction_ordering.py` dokazuje, že přijatý doklad s kategorií `domestic_reverse_charge` dostane číslo z řady druhu s touto kategorií v podmínce.
- [ ] `test_direction_change_numbering.py` dokazuje nové pořadí u změny směru (číslo z řady druhu určeného po překlasifikaci), storno ve správné řadě a případ `30{NNN}{YY}` → `42600005`.
- [ ] `test_vat_category_decision.py` dokazuje, že override kategorie přepočítá druh a číslo odvozené z faktury se přerenderuje.
- [ ] `grep -rn "resolve_defaults_safe" backend/acta/documents backend/acta/jobs` vrací 0 řádků.
- [ ] S `SEQUENCE_ASSIGN_AT_APPROVAL=False` (výchozí) dostane vydaný doklad z čítače číslo při vytěžení jako dnes (`backend/tests/documents/test_workflow.py` beze změny očekávání).
- [ ] Ruční běh `docker exec -w /app/backend acta-api python -m pytest -m stack -q tests/e2e/test_p018_full.py tests/e2e/test_issued_pipeline_p018.py` je zelený (testy se značkou `stack` výchozí běh vyřazuje).

**Effort:** L
**AID Role:** backend

### Step 6: Nastavení klienta: tabulka katalogu druhů a účetní program

**Objective:** Účetní vidí v nastavení klienta jednu tabulku druhů (kód, název, směr, typy písemnosti, podmínky, řada, čtecí maska, typ DD), přidá nebo upraví řádek, předvyplní katalog šablonou programu a u klienta zvolí účetní program.

**Files:**
- Create: `frontend/src/api/documentKinds.ts` — typy `DocumentKind`, `DocumentKindIn`, hooky `useDocumentKinds`, `useUpsertDocumentKind`, `useDeleteDocumentKind`, `useApplyKindTemplate`, `usePreviewKind`.
- Create: `frontend/src/components/client/ClientDocumentKinds.tsx` — tabulka (řádek = druh; sloupce Kód, Název, Směr, Písemnosti, Podmínky, Řada, Číslo z faktury, Typ DD, Výchozí), inline editace v dialogu, tlačítko „Předvyplnit podle programu" (výběr `duna`/`pohoda`/`abra_flexi`, režim „jen doplnit chybějící" / „nahradit"), zkušební panel „Vyzkoušet" (směr, písemnost, kategorie, zboží/služba, číslo faktury → druh, řada, náhled čísla, typ DD).
- Modify: `frontend/src/api/sequences.ts` (lines ~1-61) — typy `code`, `name` u řady a v těle založení.
- Modify: `frontend/src/components/client/ClientSequences.tsx` (lines ~51-200, 300-450) — sloupce Kód a Název v tabulce řad; pole Kód (předvyplněné `legacyCodeFor(docType, direction)`, editovatelné) a Název ve formuláři „Přidat řadu"; hlášky 409 a 422 z backendu pod polem Kód.
- Modify: `frontend/src/pages/help/CiselneRadyPage.tsx` (lines ~36-48) — sekce `k-cemu-jsou`: věta o kódu řady a o tom, že více druhů může jednu řadu sdílet.
- Create: `frontend/src/components/client/__tests__/documentKinds.test.ts` — testy lokálního náhledu masky a `legacyCodeFor` pro všech osm kombinací (nahrazuje rušený `documentDefaults.test.ts`).
- Modify: `frontend/src/pages/ClientDetail.tsx` (lines ~110-120) — `ClientDocumentKinds` místo `ClientDocumentDefaults`.
- Modify: `frontend/src/components/clients/ClientForm.tsx` (lines ~30-60, 160-170, 290-305) — select „Účetní program" (DUNA, Pohoda, ABRA Flexi, Money, jiný) vedle „Typ účetnictví".
- Modify: `frontend/src/types/client.ts` (lines ~55-70) — `accounting_system`.
- Modify: `frontend/src/api/clients.ts` (lines ~1-104) — pole `accounting_system` v create/update.
- Modify: `frontend/src/components/client/ClientDocumentDefaults.tsx` (lines ~1-349) — smazat (`git rm`).
- Modify: `frontend/src/api/documentDefaults.ts` (lines ~1-168) — smazat (`git rm`).
- Modify: `frontend/src/components/client/__tests__/documentDefaults.test.ts` (lines ~1-120) — smazat (`git rm`); obsah přechází do nového `documentKinds.test.ts`.
- Modify: `frontend/src/components/client/maskPreview.ts` (lines ~1-80) — přesun `deriveLocalPreview` z rušeného `documentDefaults.ts` a nová funkce `legacyCodeFor(docType, direction)` (FAP/DOB/ZAL/DOK, FAV/DOV/ZAV/DKV).
- Modify: `frontend/e2e/issued-invoice-fixes.spec.ts` (lines ~310-480) — mock `/document-defaults/vydana/preview` → `/document-kinds/preview`, PUT `/document-defaults/vydana` → POST/PUT `/document-kinds`, hláška „Druh dokladu musí být 1 až 4 číslice." → „Kód druhu musí být 1 až 8 písmen nebo číslic.", selektory karty → řádek tabulky katalogu a dialog.
- Modify: `frontend/src/lib/format.ts` (lines ~46-77) — label pole `druh_dokladu` „Druh dokladu" zůstává; přidat labely pro `tax_doc_type`, `tax_deduction`, `self_assessment` (použije Step 9).

**Reuse check:** searched: `find frontend/src -name "ClientDocumentKinds*"` → none

**Parallel group:** wave-3

**Architecture Context:** UI pro katalog ze Step 3 a 4. Nahrazuje dvě karty `ClientDocumentDefaults` (jeden druh na směr) jednou tabulkou; `ClientSequences` (Step 2) zůstává pod ní, protože řada je samostatná entita a katalog na ni jen odkazuje výběrem z existujících kódů.

**Implementation Detail:**
Tabulka: `useDocumentKinds(clientId)`; řádky seřazené backendem. Dialog řádku: `code` (input, regex hlídá backend, front jen `maxLength=8`), `name`, `direction` (radio), `doc_types` (checkboxy 4), `vat_categories` (multi-select ze `VAT_CATEGORY_LABELS` (`frontend/src/types/document.ts:133`) bez `mixed`, prázdné = libovolná), `supply_kinds` (checkboxy zboží/služba/smíšené/neurčeno, prázdné = libovolná), `self_assessment` (tri-state: libovolné / jen se samovyměřením / jen bez), `sequence_code` (select z kódů řad načtených přes `useQuery(['sequences', clientId], () => fetchSequences(clientId))`, stejně jako `ClientSequences.tsx:81` — hook `useSequences` v projektu neexistuje — + volba „podle typu písemnosti"), `number_source` + `number_read_mask` (jen u vydaných, s lokálním náhledem z `maskPreview.ts`), `tax_doc_type` (textový input max 4 znaky; nabídku z číselníku DUNA doplní Step 9, až bude existovat endpoint ze Step 8), `priority`, `is_default`. Chyby 409/422 se zobrazí pod polem podle klíče z `detail`. Tlačítko šablony volá `POST /apply-template`, po úspěchu invaliduje `document-kinds` a zobrazí `sequences_missing`: pro každou chybějící řadu tlačítko „Založit řadu {code} s maskou {suggested_mask}" (otevře formulář řad ze Step 2 s předvyplněnými hodnotami) a, když `same_mask_as` není null, volbu „Připojit druhy k existující řadě {same_mask_as}" (PUT druhů se `sequence_code = same_mask_as`). „Vyzkoušet" volá `POST /preview` a ukazuje `kind_code → sequence_code → number_preview → tax_doc_type`.

**Error Handling:**
- 409 z DELETE výchozího → toast s hláškou backendu.
- 409 z `replace` (doklady ke kontrole na některém druhu) → dialog vypíše kódy z odpovědi a nabídne „jen doplnit chybějící".
- Síťová chyba při načtení → skeleton + tlačítko Zkusit znovu (vzor `ClientSequences.tsx:81-90`).

**Edge Cases:**
- Klient bez jediného řádku → prázdná tabulka s výzvou „Předvyplnit podle programu" a vysvětlením, že do té doby platí vestavěné 44/53.
- Řádek s `vat_categories` obsahující kategorii, kterou účetní později v P016 přejmenuje → backend vrátí 422 při PUT; tabulka řádek zobrazí s varováním „neznámá kategorie".
- Mobil (P019): tabulka je v `overflow-x-auto`, dialog přes celou šířku; žádná nová stránka.

**Dependencies:**
- Depends on: Step 2, Step 4 — kód řady v API (Step 2), endpointy katalogu a šablon (Step 4)
- Blocks: Step 9

**Acceptance Criteria:**
- [ ] V nastavení klienta je tabulka druhů, dialog uloží řádek a chyby 409/422 se zobrazí u pole (vitest `documentKinds.test.ts` pro `legacyCodeFor` a lokální náhled; ruční ověření v Playwright Step 16).
- [ ] Tlačítko „Předvyplnit podle programu" pro DUNA založí 8 druhů a vypíše chybějící řady FV1–FV4 a PF s navrženou maskou (ověřeno v Step 16 nad vlastním klientem).
- [ ] `frontend/e2e/issued-invoice-fixes.spec.ts` prochází proti novým endpointům.
- [ ] `grep -rn "ClientDocumentDefaults\|documentDefaults" frontend/src` vrací 0 řádků.
- [ ] Formulář klienta uloží „Účetní program" a zobrazí ho po znovunačtení.

**Effort:** L
**AID Role:** frontend
**UI Change Mode:** `existing_ui`
**UI Change Contract:** `path: .aid-o/work/evidence/P025/ui/step-06-delta-contract.json | sha256: to-be-computed-at-dispatch | schema_version: 1.0.0 | viewports: desktop, mobile`

**EPIC 2: Steps 7-10 — Daňový profil dokladu: typ DD, nárok, samovyměření**

### Step 7: Sloupce daňového profilu, adaptér DUNA a generický adaptér

**Objective:** Doklad má sloupce daňového profilu a čistá funkce z (směr, kategorie, povaha plnění, země dodavatele, program) vrátí návrh typu DD, nároku a samovyměření s alternativami a varováním.

**Files:**
- Create: `backend/db/versions/0041_document_tax_profile.py` — `down_revision = "0040"`; sloupce `tax_doc_type` VARCHAR(4) NULL, `tax_deduction` VARCHAR(1) NULL CHECK IN ('1','3','5','0','4'), `self_assessment` BOOLEAN NULL, `tax_profile_state` VARCHAR(16) NOT NULL DEFAULT 'not_run' CHECK IN ('not_run','proposed','needs_review','confirmed','overridden'), `tax_profile_warnings` JSONB NOT NULL DEFAULT '[]'; index `ix_documents_tax_profile_state`.
- Modify: `backend/acta/documents/models.py` (lines ~205-245) — sloupce + konstanty `TAX_PROFILE_STATES`, `TAX_DEDUCTIONS = ("1","3","5","0","4")`.
- Create: `backend/acta/taxprofile/__init__.py` — prázdný.
- Create: `backend/tests/taxprofile/__init__.py` — prázdný; bez balíčku by `test_router.py` a `test_service.py` kolidovaly basename s `tests/sequences/` a pytest by shodil celou kolekci.
- Create: `backend/acta/taxprofile/models.py` — `TaxProfileProposal` (dataclass: `tax_doc_type: str | None, alternatives: list[str], tax_deduction: str | None, self_assessment: bool | None, state: str, warnings: list[str]`), `DUNA_TAX_DOC_TYPES` (kód → český název, tři skupiny). Seznam států EU se nezakládá: `from acta.registry.classifier import EU_MEMBER_ALPHA2` (`classifier.py:86`).
- Create: `backend/acta/taxprofile/duna.py` — `propose(direction, vat_category, supply_kind, supplier_country, client_vat_subject_type) -> TaxProfileProposal` podle tabulky v Implementation Detail; `client_vat_subject_type` je výsledek existující funkce `resolve_vat_subject_type(profiles, on_date)` (`backend/acta/registry/classifier.py:937`) nad `client.vat_profiles` k datu DUZP; hodnota `'unknown'` nebo prázdné profily se předají jako `None` (vyhodnocení intervalu platnosti se NEPÍŠE podruhé).
- Create: `backend/acta/taxprofile/generic.py` — `propose(...)` vrací `self_assessment` a `tax_deduction` podle kategorie a směru (stejná pravidla jako DUNA), `tax_doc_type=None`, `state='proposed'` když je kategorie známá a slučitelná se směrem (stav „navrženo bez typu", schválení ho potvrdí, export → `<druh>/_bez_typu/`), jinak `needs_review`, `warnings=["Program {system} nemá v ACTA číselník typů daňového dokladu; typ vyplňte v účetním programu."]`.
- Create: `backend/acta/taxprofile/service.py` — `adapter_for(accounting_system) -> module`, `refresh_tax_profile(session, doc, client, *, trigger, force_status=False) -> bool` (zapisuje jen když `tax_profile_state in ('not_run','proposed','needs_review')` a `doc.status in ('new','extracting','to_review')`; `force_status=True` obchází JEN podmínku na `status`, nikdy stavy `confirmed`/`overridden`, a smí ho použít výhradně backfill skript ze Step 10), audit `tax_profile_proposed`.
- Test: `backend/tests/taxprofile/test_duna_mapping.py` (tier: t0) — parametrizovaná tabulka všech položek `VAT_CATEGORIES` (13, parametrizace `@pytest.mark.parametrize` přímo nad konstantou, ne nad opsaným seznamem, aby nová kategorie test shodila) × 2 směry + neplátce + země mimo EU pro službu (U4) + neslučitelné kombinace (varování, `state='needs_review'`).
- Test: `backend/tests/taxprofile/test_service.py` (tier: t0) — `refresh` nepřepíše `confirmed`/`overridden`; nepřepíše `reviewed` doklad; s `force_status=True` zapíše návrh i u `reviewed`/`archived`, ale `confirmed`/`overridden` nechá; `generic` adaptér pro `pohoda` a pro klienta bez programu dává `state='proposed'` s `tax_doc_type=None`.
- Test: `backend/tests/migrations/test_migration_0041.py` (tier: t1) — upgrade/downgrade, výchozí `tax_profile_state = 'not_run'` u existujících řádků.

**Reuse check:** searched: `grep -rl "tax_doc_type" backend/acta` → none

**Parallel group:** wave-4

**Architecture Context:** Daňový profil je třetí osa vedle druhu a řady (`## Architecture` → Tok dat). Adaptér per program je jediné místo, kde se DUNA kódy vyskytují; resolver druhu (Step 3) je nezná. `refresh_tax_profile` respektuje stejný lifecycle jako klasifikace kategorie (spec P016 §9: po schválení žádný automatický přepis).

**Implementation Detail:**
Tabulka DUNA (výchozí typ / alternativy / nárok / samovyměření / varování):
- vydaná: `domestic_standard` → `D1` / [`DS`,`D9`,`D2`,`D7`] / — / ne / „DS u splátkového kalendáře nad 10 tis. Kč, D9 u prodeje dlouhodobého majetku"; `domestic_reverse_charge` → `ZZ` / [] / — / ne / „doplňte kód předmětu plnění v DUNĚ"; `eu_goods_supply` → `U1` / [`U5`,`C1`,`C2`,`PO`,`E4`] / — / ne / „kód plnění pro souhrnné hlášení doplňte v DUNĚ"; `eu_service_reverse_charge` → `U8` / [`MT`] / — / ne / „MT, pokud místo plnění není podle §9 odst. 1"; `export_goods` → `EX` / [`E6`] / — / ne / „datum přechodu přes celnici doplňte v DUNĚ"; `domestic_exempt_with_credit` → `None` / [`E2`,`E3`,`E5`] / — / ne / `state='needs_review'`, „vyberte podle titulu osvobození"; `domestic_exempt_no_credit` → `D2` / [`D7`] / — / ne; `oss_foreign_vat` → `None` / [`ES`,`EQ`,`EU`] / — / ne / `needs_review`; `out_of_scope` → `OS` / [`MT`] / — / ne; `domestic_non_payer` → `NE` / [] / — / ne, když `client_vat_subject_type == 'non_payer'` (klient-neplátce vystavuje doklad bez DPH); u klienta plátce nebo bez profilu → `None` / [] / — / ne / `needs_review`, „kategorie „plnění od neplátce" u vydaného dokladu plátce: ověřte daňové postavení klienta"; `mixed` → `None` / [] / — / ne / `needs_review`, „smíšený doklad se v DUNĚ zadává ručně"; `eu_goods_acquisition`, `import_goods` → `None` / [] / — / ne / `needs_review`, „kategorie neodpovídá vydanému dokladu, zkontrolujte směr". Klient neplátce: `NE` se navrhne JEN když `client_vat_subject_type == 'non_payer'` (výslovný řádek `ClientVatProfile` platný k DUZP); sloupec `Client.vat_payer` se nečte, protože je NOT NULL DEFAULT false a „neplátce" je v něm výchozí stav, ne tvrzení účetní (`backend/acta/clients/models.py:35`). Klient bez platného profilu → mapování podle kategorie + varování „u klienta není vyplněné daňové postavení".
- přijatá: `domestic_standard` → `D1` / [`DS`,`M1`] / `1` / ne / „M1 u majetku do ř. 47; krácený nárok 3 nebo poměrný 5 určí účetní"; `domestic_reverse_charge` → `ZZ` / [`M8`] / `1` / **ano**; `eu_goods_acquisition` → `U1` / [`M2`,`C1`,`C2`,`PO`] / `1` / **ano**; `eu_service_reverse_charge` → `U2` / [`U4`,`M3`,`M6`] / `1` / **ano** / „U2 = služba podle §9 odst. 1 od osoby registrované v členském státě; u služby podle §10–10d a §10j (nemovitost, přeprava, kultura) vyberte U4" (země dodavatele se pro volbu NEPOUŽÍVÁ: DUNA typy definuje pravidlem místa plnění, ne sídlem, a spec P016 §3.3 zakazuje odvozovat režim ze země; když `supplier_country` není v `EU_MEMBER_ALPHA2`, přidá se jen varování „dodavatel mimo EU: ověřte U2/U4"); `import_goods` → `None` / [`IM`,`EX`,`OS`] / `1` / **ano** / `needs_review`, „dovoz se v DUNĚ řeší přes JSD; typ potvrďte s účetní"; `domestic_exempt_no_credit` → `D2` / [`D3`] / `0` / ne; `domestic_exempt_with_credit` → `None` / [`D1`,`D3`] / `None` / ne / `needs_review`; `oss_foreign_vat` → `None` / [`EU`,`OS`] / `None` / ne / `needs_review`; `out_of_scope` → `OS` / [`NE`] / `0` / ne; `domestic_non_payer` → `NE` / [`OS`] / `0` / ne / „doklad od neplátce: bez DPH a bez nároku na odpočet"; `mixed` → `None` / [] / `None` / `None` / `needs_review`, „smíšený doklad se v DUNĚ zadává ručně"; `eu_goods_supply`, `export_goods` → `None` / [] / `None` / `None` / `needs_review`, „kategorie neodpovídá přijatému dokladu, zkontrolujte směr".
- kategorie `None` (klasifikátor `needs_review` nebo `not_run`) → `TaxProfileProposal(None, [], None, None, 'needs_review', ["Bez daňové kategorie nelze typ daňového dokladu navrhnout."])`.
V adaptéru DUNA je `state` = `proposed` když `tax_doc_type` není None, jinak `needs_review`; v generickém adaptéru je `proposed` i bez typu (viz Files). `refresh_tax_profile`: klienta předává volající (`await session.get(Client, doc.client_id)`; vztah `doc.client` v modelu neexistuje), `adapter = duna if client.accounting_system == 'duna' else generic`; `proposal = adapter.propose(...)`; když se `(tax_doc_type, tax_deduction, self_assessment, state, warnings)` liší od uložených → zapsat, `flag_modified` není potřeba (skalární sloupce + JSONB přiřazení celého listu), audit `tax_profile_proposed` s `old/new` JSON; vrací `True` při změně. `self_assessment` se předává zpět do resolveru druhu (Step 5 čte `doc.self_assessment`), proto pořadí v extrakci: klasifikace → refresh daňového profilu → přepočet druhu (Step 8 to napojí).

**Error Handling:**
- Neznámý `accounting_system` (NULL nebo `other`) → generický adaptér, žádná chyba.
- Doklad bez klienta → `refresh_tax_profile` vrátí `False` a nic nezapíše (bez programu není adaptér).
- Sloupce chybí (host bez migrace 0041) → SAVEPOINT tady nepomůže, protože sloupce jsou ORM-mapované na `documents` a spadl by už SELECT dokladu; spoléhá se na to, že entrypoint kontejnerů `acta-api` i `acta-worker` pouští `alembic upgrade head` před startem. Uvedeno v `## Migration Plan`.

**Edge Cases:**
- Přijatá faktura od dodavatele z Velké Británie (mimo EU) se službou → `U2` s alternativou `U4` a varováním „dodavatel mimo EU: ověřte U2/U4"; `supplier_country` z `f_supplier_country` (`documents/models.py:171-175`), NULL → `U2` s varováním „země dodavatele není známa".
- Vydaná faktura klienta s profilem `non_payer` platným k DUZP → `NE`, i když kategorie říká `domestic_standard`; varování „klient je neplátce". Klient s `vat_payer = False` a BEZ řádku `ClientVatProfile` → `D1` podle kategorie + varování o nevyplněném postavení (nikdy `NE`).
- Kategorie potvrzená účetní jinak než návrh (`overridden`) → profil se přepočítá z potvrzené kategorie (trigger ve Step 8), stav zůstává `proposed` dokud účetní neschválí.
- Doklad už `confirmed` a účetní změní kategorii přes `/vat-category/override` → profil se nepřepíše sám; UI (Step 9) ukáže varování „typ DD byl potvrzen pro jinou kategorii".

**Dependencies:**
- Depends on: Step 3, Step 5 — resolver čte `self_assessment` z dokladu
- Blocks: Step 8, Step 9, Step 10, Step 12

**Acceptance Criteria:**
- [ ] `test_duna_mapping.py` má parametrizovaný případ pro každou položku `VAT_CATEGORIES` v obou směrech (dnes 13 × 2 = 26 řádků, parametrizace nad konstantou) plus pojmenované případy: klient `non_payer` → `NE`; `domestic_non_payer` přijatá → `NE` a nárok `0` bez samovyměření; `domestic_non_payer` vydaná u klienta plátce → `needs_review`; klient bez profilu → ne `NE`; `import_goods` přijatá → `self_assessment is True`; služba od dodavatele mimo EU → `U2` + varování; a prochází.
- [ ] `test_service.py` dokazuje, že `refresh_tax_profile` nezmění doklad ve stavu `confirmed`, `overridden`, `reviewed` ani `archived`.
- [ ] `alembic upgrade head` nad kopií schématu: `SELECT count(*) FROM documents WHERE tax_profile_state <> 'not_run'` vrátí 0 před spuštěním backfillu (Step 10); migrace je `0041`.
- [ ] `grep -n "D1\|U1" backend/acta/doctypes/service.py` vrací 0 řádků (kódy DUNA jen v `taxprofile/`).

**Effort:** L
**AID Role:** backend

### Step 8: Návrh při vytěžení a překlasifikaci, potvrzení schválením, ruční změna profilu

**Objective:** Daňový profil se navrhne po klasifikaci a po každé změně kategorie, směru nebo povahy plnění; schválení potvrdí kategorii, druh i profil v jedné transakci; účetní může profil změnit s důvodem.

**Files:**
- Modify: `backend/acta/jobs/extraction.py` (lines ~1140-1195) — do pořadí ze Step 5 vložit mezi klasifikaci a druh volání `refresh_tax_profile(session, doc, client, trigger="extraction")`, aby resolver druhu viděl `doc.self_assessment`.
- Modify: `backend/acta/registry/subject_link.py` (lines ~265-330) — na konci `reclassify_document` po `_apply_updates` zavolat `refresh_tax_profile(..., trigger=trigger)`; import lokálně (cyklus `taxprofile` → `documents.models` je jednosměrný).
- Modify: `backend/acta/documents/vat_category_router.py` (lines ~156-243, 244-330) — po `confirm` i `override` zavolat `refresh_tax_profile(..., trigger="vat_category")`.
- Modify: `backend/acta/documents/router.py` (lines ~895-905) — po změně směru ZA voláním `reclassify_document(db, doc, trigger="direction")` na řádku 901 (ne u řádku 840, tam je ještě stará kategorie) zavolat `refresh_tax_profile(…, trigger="direction")` a znovu přepočet druhu.
- Modify: `backend/acta/documents/fields_router.py` (lines ~244-256) — po `patch_tax_inputs` totéž (`trigger="tax_inputs"`).
- Modify: `backend/acta/documents/vat_category_on_approval.py` (lines ~37-119) — přejmenovat na `confirm_proposals_on_approval(session, doc, *, actor_id, now, expected_proposed, expected_kind_code, expected_tax_doc_type, tax_doc_type_sent: bool)`: (1) kategorie jako dnes; (2) druh: `fields_meta.druh_dokladu.state = 'confirmed'`, `confirmed_at`, 409 `ProposalChangedError` když `expected_kind_code` je vyplněné a liší se od `fields.druh_dokladu`; (3) profil: `tax_profile_state 'proposed' → 'confirmed'` JEN když klient pole `expected_tax_doc_type` poslal (`'expected_tax_doc_type' in body.model_fields_set`; hodnota smí být `null` u profilu bez typu) a shoduje se s `doc.tax_doc_type`, jinak 409; bez poslaného pole se profil nepotvrzuje (stejná přísnost jako u kategorie, `vat_category_on_approval.py`); pořadí provedení je kategorie → profil → druh; `needs_review` profil zůstává `needs_review` (schválení ho nepotvrzuje, doklad půjde do `_NEIMPORTOVAT`); audit `document_kind_confirmed_on_approval`, `tax_profile_confirmed_on_approval`. Starý název zůstává jako alias na jeden release (`confirm_proposed_on_approval = confirm_proposals_on_approval`).
- Modify: `backend/acta/documents/status_router.py` (lines ~40-60, 128-160) — `StatusPatch.expected_kind_code`, `expected_tax_doc_type`; volání nové funkce v `patch_status`. Zkratka `review_and_archive` (`status_router.py:171-225`) se NEMĚNÍ: návrhy dál nepotvrzuje, protože nepřijímá verzi a nemůže doložit, že účetní návrh viděla (komentář `status_router.py:188-198`); doklad schválený zkratkou s profilem `proposed` skončí v exportu v `_NEIMPORTOVAT`, dokud účetní profil nepotvrdí ručně.
- Create: `backend/acta/taxprofile/router.py` — `PATCH /api/v1/documents/{doc_id}/tax-profile` a `GET /api/v1/tax-doc-types?system=duna` (úplný kontrakt v Implementation Detail); role, načtení dokladu a kontrolu editovatelnosti PŘEBÍRÁ z `backend/acta/documents/vat_category_router.py` (`_require_role` :57, `_load` :64, `_require_editable` :78) importem, nepíše je podruhé.
- Modify: `backend/acta/taxprofile/service.py` (lines ~1-120) — nová funkce `apply_kind_tax_doc_type(doc, kind) -> bool`: když `kind.tax_doc_type` není None a `doc.tax_profile_state in ('not_run','proposed','needs_review')` → `doc.tax_doc_type = kind.tax_doc_type`, `state = 'proposed'`, do `tax_profile_warnings` přidá „typ převzat z druhu {code}"; `self_assessment` ani `tax_deduction` nemění (žádný cyklus profil↔druh). Tím sloupec katalogu `tax_doc_type` („přebije mapování z kategorie") dostává producenta.
- Modify: `backend/acta/documents/derived_fields.py` (lines ~86-100) — po určení druhu zavolat `apply_kind_tax_doc_type(doc, kind)`; platí i pro ruční změnu druhu přes `patch_document_field`.
- Modify: `backend/acta/documents/router.py` (lines ~416-450) — nový čtecí handler `GET /{doc_id}/number-preview` → 200 `{number, source: 'assigned' | 'preview' | 'invoice_number' | 'none', sequence_code, note}`, 401 bez přihlášení, 404 doklad neexistuje; je tady (ne ve Step 14), protože ho volá detail dokladu ve Step 9.
- Modify: `backend/acta/clients/service.py` (lines ~205-260) — po změně `accounting_system` klienta přepočítat daňový profil všech jeho dokladů ve stavu `to_review` (`refresh_tax_profile(…, trigger="accounting_system")`), jinak by rozpracované doklady zůstaly s návrhem bez typu DD.
- Modify: `backend/acta/main.py` (lines ~18-25, 160-190) — import a registrace `taxprofile.router`.
- Modify: `backend/acta/documents/schemas.py` (lines ~30-80) — pole profilu v `DocumentOut`.
- Test: `backend/tests/taxprofile/test_router.py` (tier: t1) — PATCH s důvodem → `overridden` + audit; bez důvodu 422; nárok u vydané 422; verze 409; archivovaný 422; `viewer` 403; neposlané pole se nemění; `GET /tax-doc-types`; `GET /number-preview` pro doklad s číslem (`assigned`), bez čísla (`preview`, čítač se neposune) a bez směru (`none`).
- Modify: `backend/tests/documents/test_vat_category_decision.py` (lines ~1000-1095) — nové případy na konci: schválení potvrdí druh i profil (i profil „bez typu" z generického adaptéru); bez poslaného `expected_tax_doc_type` se profil nepotvrdí; kategorie potvrzená předem tlačítkem (stav `confirmed`) nebrání potvrzení druhu a profilu; druh s vyplněným `tax_doc_type` v katalogu přebije typ z kategorie (tuzemská faktura s ručně zvoleným druhem `502` dostane `U1`); 409 při změněném `expected_kind_code`; `needs_review` profil zůstává po schválení `needs_review`; zkratka `review-and-archive` druh ani profil NEpotvrzuje.
- Modify: `backend/tests/documents/test_tax_inputs_api.py` (lines ~650-696) — nový případ na konci: změna `supply_kind` spustí překlasifikaci a po ní přepočet profilu (`U1` ↔ `U8` u vydané EU faktury při přepnutí zboží/služba).

**Reuse check:** searched: `find backend/acta -name "tax*router.py"` → none

**Parallel group:** wave-5

**Architecture Context:** Napojení Step 7 na životní cyklus dokladu. Schválení je už dnes okamžik potvrzení kategorie (`status_router.py:128-141`); plán k němu přidává druh a profil, aby účetní potvrzovala jedním úkonem tři věci, které vidí vedle sebe (Step 9). Pořadí po tomto kroku ve všech čtyřech cestách ze Step 5: klasifikace → profil → druh (+ typ DD z druhu) → číslo, protože katalog může mít podmínku na samovyměření a řada plyne z druhu.

**Implementation Detail:**
`confirm_proposals_on_approval`: transakce volajícího; pořadí kategorie → profil → druh (druh závisí na `self_assessment`, které profil právě potvrdil, ale hodnotu nemění). Pro druh: `meta = dict(doc.fields_meta.get("druh_dokladu", {}))`; `if expected_kind_code is not None and expected_kind_code != (doc.fields or {}).get("druh_dokladu"): raise ProposalChangedError("Návrh druhu dokladu se mezitím změnil …")`; `meta["state"] = "confirmed"; meta["confirmed_at"] = now.isoformat()`; zápis přes nový dict (JSONB dirty-tracking, komentář `bundle.py:177-179`). Pro profil (JEDINÉ pravidlo, shodné s Files): `tax_doc_type_sent = "expected_tax_doc_type" in body.model_fields_set` určí volající; `if doc.tax_profile_state == "proposed" and tax_doc_type_sent: if expected_tax_doc_type != doc.tax_doc_type: raise ProposalChangedError("Návrh typu daňového dokladu se mezitím změnil …"); doc.tax_profile_state = "confirmed"` — `None` poslané výslovně tedy potvrzuje profil bez typu (generický adaptér, rozhodnutí 2B), nepolané pole profil nechává `proposed`. Tři osy (kategorie, druh, profil) se vyhodnocují každá zvlášť; dnešní časný `return` v `vat_category_on_approval.py` (když kategorie není `proposed`, např. účetní ji potvrdila předem tlačítkem) se nahrazuje větvením jen pro osu kategorie, jinak by se druh a profil nepotvrdily. API kontrakt: `PATCH /api/v1/documents/{doc_id}/tax-profile` body `{version: int, tax_doc_type?: str | null, tax_deduction?: str | null, self_assessment?: bool | null, reason: str}` → 200 `DocumentOut`; 409 `Version conflict`; 422 `Nárok se u vydaných dokladů nevyplňuje.`, `Neznámý typ daňového dokladu {x} pro program {system}.`, `Důvod změny je povinný.` (min 3 znaky), `Doklad nemá klienta, program pro typ dokladu není znám.`, 422 u archivovaného dokladu (z `_require_editable`); 403 role `viewer`; 401 bez přihlášení; 404 doklad neexistuje. Neposlaná pole se nemění (`model_fields_set`). `GET /api/v1/tax-doc-types?system=duna` → 200 `{issued: [{code, label}], received: [...], self_assessment: [...]}` z `DUNA_TAX_DOC_TYPES`; jiný `system` → 200 s prázdnými poli. `PATCH /tax-profile`: načíst doklad (vzor `vat_category_router._load`), kontrola verze a role, validace hodnot (typ DD proti `DUNA_TAX_DOC_TYPES` jen když `client.accounting_system == 'duna'`), zápis polí, `tax_profile_state = 'overridden'`, `tax_profile_warnings = []`, `version += 1`, audit per pole, `refresh_tax_profile` se po override NEvolá.

**Error Handling:**
- `ProposalChangedError` → 409 s textem, transakce se vrátí (stejná cesta jako dnes `status_router.py:139-140`).
- `refresh_tax_profile` selže (výjimka adaptéru) → zachytit, zalogovat `error` s `doc.id`, klasifikace ani schválení nespadnou; profil zůstane v předchozím stavu.
- PATCH profilu na dokladu bez klienta → 422 `Doklad nemá klienta, program pro typ dokladu není znám.`

**Edge Cases:**
- Účetní schválí doklad s profilem `needs_review` (např. osvobozené plnění bez titulu) → schválení projde (kategorie potvrzena), profil zůstává `needs_review`, export ho dá do `_NEIMPORTOVAT/k_rucnimu_posouzeni` s důvodem „typ daňového dokladu nerozhodnut".
- Účetní změní kategorii přes override po schválení (dnes povoleno u `reviewed`, `_EDITABLE_STATUSES`) → profil se nepřepočítá (stav `confirmed`), UI varuje; ruční PATCH profilu je cesta k opravě.
- Dva klienti současně schvalují týž doklad → druhý dostane 409 verze (dnešní `status_router.py:101`).
- `expected_kind_code` je `None` (starý frontend) → druh se potvrdí bez kontroly shody; kategorie má stejné chování dnes (`vat_category_on_approval.py`: bez `expected_proposed` se nepotvrzuje), tady je to záměrně měkčí, protože druh má vždy hodnotu (vestavěnou), a zapisuje se do auditu `expected_missing=True`.

**Dependencies:**
- Depends on: Step 5, Step 7 — jednotné pořadí a přepočet druhu po změně kategorie (Step 5), sloupce a adaptéry profilu (Step 7)
- Blocks: Step 9, Step 12, Step 14

**Acceptance Criteria:**
- [ ] `test_vat_category_decision.py` dokazuje, že po `PATCH status reviewed` má doklad `tax_profile_state = 'confirmed'` a `fields_meta.druh_dokladu.state = 'confirmed'`, a že `expected_kind_code` s jinou hodnotou vrátí 409.
- [ ] `test_tax_inputs_api.py` dokazuje přepočet `U1` ↔ `U8` po změně `supply_kind` u vydané EU faktury.
- [ ] `test_router.py` (taxprofile) prochází pro všech pět chybových cest.
- [ ] `review-and-archive` druh ani profil nepotvrzuje a doklad po ní zůstává s `tax_profile_state = 'proposed'` (test v `test_vat_category_decision.py`).

**Effort:** M
**AID Role:** backend

### Step 9: Detail dokladu: druh jako pole s návrhem, typ DD / nárok / samovyměření

**Objective:** Účetní vidí v pravém panelu detailu druh dokladu, typ daňového dokladu, nárok a samovyměření jako běžná pole se štítkem původu (návrh ACTA / potvrzeno / změnila účetní), může je změnit a schválení je potvrdí; před schválením vidí náhled čísla.

**Files:**
- Create: `frontend/src/api/taxProfile.ts` — `usePatchTaxProfile`, `useTaxDocTypes(system)`, typy.
- Modify: `frontend/src/types/document.ts` (lines ~230-245) — pole profilu a `document_kind` v typu `Document`.
- Create: `frontend/src/components/documents/DocumentKindField.tsx` — `FieldRow` „Druh dokladu": hodnota `code · name`, štítek stavu (`návrh ACTA` / `potvrzeno` / `změnila účetní`), rozbalovací seznam druhů klienta z `useDocumentKinds` (Step 6) filtrovaný směrem; změna → `PATCH /api/v1/documents/{doc_id}/fields/druh_dokladu` s tělem `{value, version}` přes existující hook `usePatchField` (`frontend/src/api/documents.ts:232`, argumenty `{id, field, value, version}`); backend (Step 5) k tomu zapíše `state='manual'`; jen role `accountant`/`admin`, ne u `archived`.
- Create: `frontend/src/components/documents/TaxProfileFields.tsx` — tři `FieldRow`: „Typ daň. dokladu" (select z číselníku DUNA s alternativami nahoře, u jiných programů input), „Nárok" (jen přijaté: 1/3/5/0/4), „Samovyměření" (ano/ne); štítek stavu a varování: `tax_profile_warnings` (pole textů) se mapuje na `ReviewReason[]` tvaru `{field: 'tax_doc_type', source: 'validation_warning', message: text}` (typ `ReviewReason` v `frontend/src/types/document.ts:56-60`; `source` musí být z unionu `ReviewSource` na řádku 54: `validation | checker | validation_warning | flags | candidate_first`) a předá existující komponentě FieldWarningPopover, jejíž soubor se nemění; změna otevře dialog s důvodem a volá `usePatchTaxProfile`.
- Modify: `frontend/src/pages/DocumentDetail.tsx` (lines ~45-56, 813-860, 440-490) — `druh_dokladu` vyjmout z `LEFT_FIELDS` a vykreslit `DocumentKindField` pod `VatCategoryField`, pod ním `TaxProfileFields`; řádek „Číslo ACTA" ukazuje u dokladu bez čísla náhled z `GET /number-preview` (endpoint ze Step 8) s popiskem „přidělí se při schválení" a u `doc.number_series_mismatch` varování „číslo je z jiné řady, než na kterou ukazuje druh"; `approve()` posílá `expectedKindCode` a `expectedTaxDocType`; hláška 409 z backendu se zobrazí a doklad se znovu načte.
- Modify: `frontend/src/api/documents.ts` (lines ~140-165) — `expected_kind_code`, `expected_tax_doc_type` v `useApproveDocument`; `useNumberPreview(docId)`.
- Modify: `frontend/src/components/documents/VatCategoryField.tsx` (lines ~1-40) — štítek původu přesunout do sdílené komponenty OriginBadge (Create níže), aby tři pole měla jeden štítek.
- Create: `frontend/src/components/documents/OriginBadge.tsx` — štítek původu (`návrh ACTA`, `návrh ACTA · nejistý`, `potvrzeno`, `změnila účetní`, `ACTA nic nenavrhla`) vyjmutý z `VatCategoryField.tsx`.
- Modify: `frontend/src/components/client/ClientDocumentKinds.tsx` (lines ~1-60) — pole `tax_doc_type` v dialogu druhu dostane nabídku (`datalist`) z `useTaxDocTypes(client.accounting_system)`; bez programu DUNA zůstává volný text.
- Test: `frontend/src/components/documents/__tests__/TaxProfileFields.test.tsx` (tier: t0) — render pro přijatou (tři řádky) a vydanou (dva řádky, nárok chybí), štítek podle stavu, varování se zobrazí.

**Reuse check:** searched: `grep -rl "TaxProfile" frontend/src` → none

**Parallel group:** wave-6

**Architecture Context:** UI vrstva nad Step 7 a 8. Pravý panel detailu byl 31. 8. přestavěn na `FieldRow` s kategorií jako běžným polem (`VatCategoryField.tsx`); druh a profil kopírují tentýž vzor, aby účetní viděla všechna tři daňová rozhodnutí vedle sebe a potvrdila je jedním schválením.

**Implementation Detail:**
`DocumentKindField`: `kind = doc.document_kind`; rozbalovací seznam používá tři pásma jako `VatCategoryField` (hledání, seznam, poznámka), položky `code · name · řada sequence_code`; výběr → `usePatchField().mutate({id: doc.id, field: 'druh_dokladu', value: code, version: doc.version})`; backend `documents/service.py` zapisuje `edited_by_user` a od Step 5 i `state='manual'`. `TaxProfileFields`: select typu DD má skupiny „Navrženo", „Alternativy", „Ostatní"; číselník z `GET /api/v1/tax-doc-types?system=duna` (endpoint ze Step 8, vrací `{issued, received, self_assessment}` jako pole `{code, label}`). Náhled čísla: `useNumberPreview` se volá jen když `doc.direction === 'vydana' && !doc.acta_sequence_number`. `approve(archive)`: `expectedKindCode: doc.document_kind?.code ?? null`, `expectedTaxDocType: doc.tax_profile_state === 'proposed' ? doc.tax_doc_type : null`.

**Error Handling:**
- 409 při schválení (druh nebo typ se změnil) → toast s textem backendu, `refetch()`, tlačítko schválit zůstává.
- 422 z PATCH profilu (nárok u vydané) → hláška u pole; formulář se nezavře.
- `number-preview` selže → řádek ukáže „náhled nedostupný", schválení není blokované.

**Edge Cases:**
- Klient bez katalogu → seznam druhů obsahuje jen vestavěný `44`/`53` s poznámkou „nastavte katalog u klienta".
- Program klienta není DUNA → typ DD je volný text, nárok a samovyměření fungují stejně.
- Doklad `archived` → všechna tři pole jen ke čtení (stejně jako kategorie dnes).
- Mobil: pole jsou `FieldRow`, žádné nové rozložení; dropdown má `allowOverflow` (oprava z 31. 8.).

**Dependencies:**
- Depends on: Step 6, Step 8
- Blocks: Step 16

**Acceptance Criteria:**
- [ ] `TaxProfileFields.test.tsx` prochází (přijatá 3 řádky, vydaná 2 řádky, štítky, varování).
- [ ] `grep -n "druh_dokladu" frontend/src/pages/DocumentDetail.tsx` ukazuje, že pole už není v `LEFT_FIELDS` a vykresluje se přes `DocumentKindField`.
- [ ] Schválení posílá `expected_kind_code` a `expected_tax_doc_type` (test hooku v `frontend/src/api/__tests__/`).
- [ ] Řádek „Číslo ACTA" pro doklad bez čísla vykreslí náhled a text „přidělí se při schválení" (vitest s mockem `useNumberPreview`; do zapnutí přepínače ve Step 14 takové doklady v provozu nevznikají, celý tok ověří Step 16).

**Effort:** L
**AID Role:** frontend
**UI Change Mode:** `existing_ui`
**UI Change Contract:** `path: .aid-o/work/evidence/P025/ui/step-09-delta-contract.json | sha256: to-be-computed-at-dispatch | schema_version: 1.0.0 | viewports: desktop, mobile`

### Step 10: Sloupce v CSV a XLSX a jednorázové doplnění návrhů profilu

**Objective:** CSV a XLSX nesou druh, typ DD, nárok, samovyměření a Číslo ACTA; existující doklady dostanou návrh daňového profilu skriptem s dry-runem.

**Files:**
- Modify: `backend/acta/export/csv.py` (lines ~90-125) — `HEADERS` na konec: `druh_dokladu`, `typ_danoveho_dokladu`, `narok`, `samovymereni`, `stav_danoveho_profilu`, `cislo_acta`; hodnoty přes `field_str`/`attr_str`; `samovymereni` jako `ano`/`ne`/prázdné.
- Modify: `backend/acta/export/xlsx.py` (lines ~39-120) — stejné sloupce ve stejném pořadí.
- Modify: `backend/tests/export/test_export.py` (lines ~600-649) — nové případy na konci: hlavičky se porovnají se zmrazeným seznamem dnešních 25 názvů (`id` … `stav_klasifikace`, `backend/acta/export/csv.py:90-107`) následovaným šesti novými; hodnoty pro doklad s profilem.
- Create: `backend/scripts/backfill_tax_profile.py` — dva režimy: výchozí „návrh" a `--confirm-approved` (popsán níže); POVINNÉ `--client-id` (vzor `fix_issued_invoices_p018.py:938`: potvrzení místo účetní se nikdy nedělá přes všechny klienty najednou); dry-run výchozí, `--apply`, `--expected-count`, `--limit`; auditní aktér `AuditActor(actor_id="backfill_tax_profile", actor_type="script")` (stejná hodnota jako v `fix_issued_invoices_p018.py`); vybírá doklady s `tax_profile_state = 'not_run'` a klientem, volá `refresh_tax_profile(trigger="backfill")` bez ohledu na `status` (historické `reviewed`/`archived` doklady návrh dostanou, stav zůstane `proposed`, nic se nepotvrzuje), audit `tax_profile_backfilled`; docstring podle vzoru `backend/scripts/backfill_vat_category.py:1-45`.
- Test: `backend/tests/scripts/test_backfill_tax_profile.py` (tier: t1) — dry-run nic nezapíše (rollback), `--expected-count` nesouhlasí → exit 3, režim „návrh" s `--apply` zapíše `proposed` a nikdy `confirmed`; režim `--confirm-approved` potvrdí jen doklady `reviewed`/`archived` s potvrzenou kategorií a profilem `proposed`, `needs_review` nechá být, zapíše audit `tax_profile_confirmed_by_backfill`.

**Reuse check:** searched: `find backend/scripts -name "backfill_tax_profile*"` → none

**Parallel group:** wave-6

**Architecture Context:** CSV/XLSX je kontrolní výstup pro účetní vedle ISDOC; sloupce se přidávají jen na konec (poziční parsery, `csv.py:80-89`). Skript uzavírá díru, že doklady z doby před migrací 0041 by neměly návrh ani potvrzení, a používá stejnou službu jako živý provoz (Step 7), ne vlastní logiku.

**Implementation Detail:**
`documents_to_csv` (`csv.py:121`): za `stav_klasifikace` přidat `field_str(doc, "druh_dokladu")`, `attr_str(doc, "tax_doc_type")`, `attr_str(doc, "tax_deduction")`, `{True: "ano", False: "ne", None: ""}[doc.self_assessment]`, `attr_str(doc, "tax_profile_state")`, `attr_str(doc, "acta_sequence_number")`. Skript: `SELECT d FROM documents d JOIN clients c WHERE d.deleted_at IS NULL AND d.tax_profile_state = 'not_run' AND d.client_id IS NOT NULL ORDER BY created_at`; pro každý `refresh_tax_profile(session, doc, client, trigger="backfill", force_status=True)` (parametr zavádí Step 7 právě pro tento skript); souhrn `stav/typ` jako v `backfill_vat_category.py:151-153`. Režim `--confirm-approved`: `SELECT … WHERE status IN ('reviewed','archived') AND vat_category_state IN ('confirmed','overridden') AND tax_profile_state = 'proposed'`; dry-run vypíše pro každý doklad název souboru, kategorii, druh, navržený typ DD, nárok a samovyměření (tento výpis schvaluje účetní, stejně jako u `fix_issued_invoices_p018.py`); s `--apply --expected-count N` nastaví `tax_profile_state = 'confirmed'`, `fields_meta.druh_dokladu.state = 'confirmed'` a zapíše audit `tax_profile_confirmed_by_backfill` s `actor_type='script'`. Bez tohoto režimu by po nasazení EPICu 3 spadl každý historický schválený doklad (včetně 79 přečíslovaných vydaných faktur Michaely Štanclové, jejichž re-export je rozhodnutí PM) do `_NEIMPORTOVAT`, protože potvrzení dělá jen schválení a to už u nich proběhlo.

**Error Handling:**
- Doklad bez klienta → přeskočen s výpisem.
- Adaptér vyhodí výjimku → doklad přeskočen, běh pokračuje, součet přeskočených v souhrnu.
- `--expected-count` nesedí → exit 3 bez zápisu.

**Edge Cases:**
- Doklad `archived` z roku 2025 s kategorií `confirmed` → dostane `proposed` profil; export ho dá do `_NEIMPORTOVAT`, dokud se profil nepotvrdí režimem `--confirm-approved` (PATCH profilu u archivovaného dokladu vrací 422), protože schválení už proběhlo. Skript to vypíše v souhrnu jako „vyžaduje ruční potvrzení: N".
- Doklad bez kategorie → profil `needs_review` s varováním; do CSV jde prázdný typ a stav `needs_review`.
- Sloupce v XLSX jsou stringy, `cislo_acta` se nesmí formátovat jako číslo (`2600241` by Excel zobrazil bez problému, ale `FAV-2026/0001` ne; sjednotit na text).

**Dependencies:**
- Depends on: Step 7, Step 8
- Blocks: Step 16

**Acceptance Criteria:**
- [ ] `test_export.py` porovná hlavičky CSV se zmrazeným seznamem dnešních 25 názvů + 6 nových v uvedeném pořadí.
- [ ] `test_backfill_tax_profile.py` prochází (dry-run rollback, exit 3, režim „návrh" jen `proposed`, režim `--confirm-approved` jen nad schválenými doklady s potvrzenou kategorií).
- [ ] Dry-run skriptu nad kopií dev databáze vypíše souhrn a `SELECT count(*) FROM documents WHERE tax_profile_state <> 'not_run'` je po něm stále 0.

**Effort:** M
**AID Role:** backend

**EPIC 3: Steps 11-16 — Export ZIP druh/typ DD, reverse charge v ISDOC, číslo při schválení**

### Step 11: `LocalReverseChargeFlag` v ISDOC u tuzemského reverse charge

**Objective:** Řádek rozpisu DPH s režimem `reverse_charge_domestic` odchází v ISDOC s `LocalReverseChargeFlag=true` v `TaxSubTotal/TaxCategory`, aby DUNA doklad nepřijala jako běžnou fakturu.

**Files:**
- Modify: `backend/acta/documents/isdoc.py` (lines ~280-310) — v `TaxSubTotal/TaxCategory` hned za `Percent` (`isdoc.py:302-303`; builder tam dnes zapisuje POUZE `Percent`) přidat `LocalReverseChargeFlag` = `true` pro skupinu sazby, která má v `vat_breakdown` řádek s `mode == 'reverse_charge_domestic'`; u ostatních element vynechat (ne `false`), aby se dnešní výstup nezměnil.
- Modify: `backend/tests/export/test_isdoc_schema.py` (lines ~150-200) — nové případy na konci: doklad s `vat_breakdown=[{rate: 21, base: 1000, vat: 0, mode: 'reverse_charge_domestic'}]` validuje proti XSD a obsahuje `LocalReverseChargeFlag` s textem `true`; totéž se sazbou zapsanou jako `Decimal('21.00')` a jako řetězec `"21"`; doklad bez režimu element neobsahuje a výstup je bajtově shodný se snapshotem pořízeným před změnou.
- Modify: `backend/tests/extraction/test_isdoc_parser.py` (lines ~520-554) — nový případ na konci: výstup builderu s `LocalReverseChargeFlag` parser přečte jako `reverse_charge_domestic` se zdrojem `isdoc_structured`.
- Modify: `backend/tests/convert/test_convert_service.py` (lines ~1-60) — nový případ: převod FlexiBee přes `build_isdoc` s dokladem bez atributu `vat_breakdown` dává bajtově stejný výstup jako před změnou.

**Parallel group:** wave-7

**Architecture Context:** Uzavírá asymetrii parser/builder: parser čte kontejnery `ClassifiedTaxCategory` a `TaxCategory` (`backend/acta/extraction/isdoc_parser.py:87`, `:119-132`), builder příznak nikdy nepíše. Element `LocalReverseChargeFlag` je v XSD v `TaxCategoryType` (`backend/tests/extraction/fixtures/isdoc-invoice-6.0.2.xsd:1980`), booleovský a bez povinného kódu předmětu plnění, který ACTA nemá; plný `LocalReverseCharge` s povinným `LocalReverseChargeCode` (XSD `:1384`) je proto mimo rozsah.

**Implementation Detail:**
Pořadí elementů `TaxCategoryType` podle XSD (řádky 1961-1985): `Percent`, `TaxScheme?`, `VATApplicable?`, `LocalReverseChargeFlag?`. Builder zapisuje jen `Percent`, takže nový element jde hned za něj a pořadí schématu je splněné. V `build_isdoc` při skládání `TaxSubTotal` (`isdoc.py:280-305`): `rc_rows = [r for r in (getattr(document, "vat_breakdown", None) or []) if r.get("mode") == "reverse_charge_domestic"]` (přes `getattr`: `build_isdoc` volá i převodník FlexiBee, `backend/acta/convert/service.py`, s duck-typed dokladem, který `vat_breakdown` nemá); pro každou skupinu `g`: `cat = _sub(sub, "TaxCategory"); _sub(cat, "Percent", _pct(g["rate"])); if any(_rates_equal(r.get("rate"), g["rate"]) for r in rc_rows): _sub(cat, "LocalReverseChargeFlag", "true")`. Porovnání sazeb VÝHRADNĚ přes `_rates_equal` importovaný z `backend/acta/export/csv.py:32` (řetězcové `str(rate)` by selhalo na `21` vs `Decimal('21.00')` vs `"21"`, což jsou tvary, které v `vat_breakdown` reálně jsou).

**Error Handling:**
- `vat_breakdown` prázdné nebo bez `mode` → element se nepřidá; výstup identický s dneškem.
- Schema validace selže (špatné pořadí) → test `test_isdoc_schema.py` to zachytí před merge.

**Edge Cases:**
- Doklad má dvě sazby, jen jedna v reverse charge → flag jen u jejího `TaxCategory`.
- Režim `reverse_charge_cross_border` → flag se NEpřidává (ISDOC `LocalReverseCharge*` je tuzemský režim §92a; přeshraniční se v DUNĚ řeší typem DD a samovyměřením).
- `mode_confirmed=False` (jen návrh AI) → flag se přidá stejně; režim v `vat_breakdown` je to, co doklad tvrdí (spec P016 §3.1); upozornění nese `_navod.txt` (Step 12) u dokladů s nepotvrzeným režimem.

**Dependencies:**
- Depends on: none
- Blocks: Step 16

**Acceptance Criteria:**
- [ ] `test_isdoc_schema.py` má tři případy s `LocalReverseChargeFlag` (int, `Decimal`, řetězec) validující proti XSD a prochází.
- [ ] Round-trip test v `test_isdoc_parser.py` prochází.
- [ ] `bash backend/scripts/run_py_test_gate.sh tests/convert tests/export` je zelený (převodník FlexiBee sdílí `build_isdoc`).
- [ ] Pro doklad bez reverse charge je výstup `build_isdoc` bajtově shodný se snapshotem.

**Effort:** S
**AID Role:** backend

### Step 12: Export ZIP ve dvou úrovních druh / typ DD, samovyměření, `_NEIMPORTOVAT`, `_navod.txt`

**Objective:** ZIP s ISDOC má složky `<druh>/<typ DD>/`, samovyměření ve vlastní podsložce, nepotvrzené doklady a vydané bez čísla v `_NEIMPORTOVAT`, a `_navod.txt` říká účetní, co s kterou složkou v DUNĚ udělat.

**Files:**
- Modify: `backend/acta/export/isdoc_zip.py` (lines ~19-94) — `_kind_folder(doc)`, `_taxtype_folder(doc)`, `_placement(doc) -> tuple[str, str | None, str | None]` (složka 1. úrovně, 2. úrovně, důvod pro `_NEIMPORTOVAT`), nová veřejná funkce `isdoc_entry_basename(doc) -> str` (u vydané `acta_sequence_number`, jinak číslo faktury, jinak prvních 8 znaků id), kterou používá `_entry_name` i stažení jednoho dokladu (Step 14), `documents_to_isdoc_zip(..., layout='flat'|'category'|'kind_taxtype')` (`category` = dnešní chování, na které míří alias `split_by_category=true`; `flat` = výchozí).
- Create: `backend/acta/export/manifest.py` — `build_navod(placements: list[Placement], kinds_by_code: dict, sequences_by_code: dict, tax_doc_type_names: dict) -> bytes` generuje `_navod.txt`.
- Modify: `backend/acta/export/router.py` (lines ~21-40, 97-170) — parametr `layout: Literal['flat','category','kind_taxtype'] = 'flat'`, alias `split_by_category=true` → `category`, načtení katalogu a řad klienta (`doctypes.service.list_kinds`, `sequences` SELECT), sestavení `_navod.txt`, hlavičky `X-Export-Unresolved` (počet v `_NEIMPORTOVAT/k_rucnimu_posouzeni`) a `X-Export-No-Number` (počet v `_NEIMPORTOVAT/bez_cisla`), `_report.txt` zachován.
- Modify: `backend/acta/export/service.py` (lines ~77-95) — řazení exportu: `acta_sequence_number ASC NULLS LAST, f_issue_date ASC NULLS LAST, created_at ASC`. Dnes je druhým klíčem jen `created_at` (`export/service.py:88-91`), takže doklady bez čísla jdou podle času nahrání; s číslem při schválení jich přibude a pořadí podle data vystavení je pro účetní čitelnější. Lexikografické řazení čísel (B-072) tím zůstává otevřené.
- Modify: `backend/tests/export/test_isdoc_zip.py` (lines ~480-529) — nové případy na konci: volání bez `layout` dává plochý archiv jako dnes; `split_by_category=true` dává dnešní složky podle kategorie; profil `overridden` bez typu DD → `<druh>/_bez_typu/`; dva druhy × dva typy DD → čtyři složky; samovyměření `44_prijate/U2_SAMOVYMERENI/`; doklad s profilem `needs_review` → `_NEIMPORTOVAT/k_rucnimu_posouzeni/`; vydaný bez čísla → `_NEIMPORTOVAT/bez_cisla/`; `layout=flat` dává plochý archiv; `_navod.txt` obsahuje řádek pro každou složku s počtem; kolize názvů v různých složkách se nepřejmenovávají.
- Test: `backend/tests/export/test_manifest.py` (tier: t0) — obsah `_navod.txt` pro tři složky, včetně varování a části `_NEIMPORTOVAT`.
- Modify: `backend/tests/convert/test_convert_service.py` (lines ~60-120) — nový případ: převod FlexiBee přes `documents_to_isdoc_zip` s duck-typed dokladem bez `direction` a `acta_sequence_number` projde a názvy položek jsou jako dnes.

**Reuse check:** searched: `grep -rl "_navod" backend/acta` → none

**Parallel group:** wave-7b

**Architecture Context:** Export je místo, kde se model (druh, řada) a daňový profil (typ DD, samovyměření) promítnou do toho, co účetní v DUNĚ zadává na dávku: importní dialog chce druh + typ DD, samovyměření se v DUNĚ zaškrtává hromadně na importované faktury. Jedna složka 2. úrovně = jeden import. `_NEIMPORTOVAT` nahrazuje dnešní `k_rucnimu_posouzeni` v kořeni (`isdoc_zip.py:22`), aby bylo z názvu jasné, že se to do DUNY nedává.

**Implementation Detail:**
Všechna NOVÁ čtení atributů dokladu v `isdoc_zip.py` jdou přes `getattr(doc, …, None)`: `documents_to_isdoc_zip` volá i převodník FlexiBee (`backend/acta/convert/service.py:99`) s duck-typed dokladem bez `direction`, `acta_sequence_number` a sloupců daňového profilu; převodník používá jen `layout='flat'`, kde se `_placement` nevolá, ale `isdoc_entry_basename` ano. `_placement(doc)`: (1) `doc.direction == 'vydana' and not doc.acta_sequence_number` → `("_NEIMPORTOVAT", "bez_cisla", "vydaný doklad bez Čísla ACTA")`; (2) `not doc.vat_category or doc.vat_category == 'mixed' or doc.tax_profile_state not in ('confirmed','overridden')` → `("_NEIMPORTOVAT", "k_rucnimu_posouzeni", důvod: "kategorie nepotvrzena" | "smíšený doklad" | "typ daňového dokladu nerozhodnut")`; (3) jinak `kind_code = fields.druh_dokladu`, `kind_name = kinds_by_code.get(code).name or ""`, složka 1 = `_UNSAFE_NAME.sub("_", f"{kind_code}_{slug(kind_name)}")` (slug: ascii, mezery → `_`, max 40 znaků); složka 2 = `tax_doc_type` + (`_SAMOVYMERENI` když `doc.self_assessment`); `tax_doc_type is None` u potvrzeného profilu nastane u klienta bez programu DUNA (generický adaptér, stav „navrženo bez typu" potvrzený schválením) a když účetní profil přepsala a typ nevyplnila (`overridden`) → složka `_bez_typu` a v `_navod.txt` řádek „Typ daňového dokladu: NEVYPLNĚN, doplňte v DUNĚ ručně". `isdoc_entry_basename(doc)`: `doc.acta_sequence_number if doc.direction == 'vydana' and doc.acta_sequence_number else (doc.f_invoice_number or str(doc.id)[:8])`. `_navod.txt` (UTF-8 s BOM kvůli Poznámkovému bloku ve Windows, řádky `\r\n`): hlavička s datem, klientem, počtem dokladů; pro každou složku 1./2. úrovně: `SLOŽKA: 502_zbozi_EU/U1/` · `Druh dokladu v DUNĚ: 502 (Vystavená faktura – zboží EU plátci DPH)` · `Číselná řada: FV2, maska 4{YY}{NNNNN}` · `Typ daňového dokladu: U1 – Dodání zboží do jiného členského státu §64` · `Nárok: —` (u přijatých hodnota) · `Samovyměření: NE / ANO – po importu zaškrtněte Samovyměření DPH a spusťte hromadné generování` · `Počet dokladů: 7` · `Upozornění:` seznam unikátních `tax_profile_warnings` dokladů ve složce; část `_NEIMPORTOVAT` vypíše doklady s důvodem (název souboru, číslo, důvod); závěr: „Doklady s nepotvrzeným režimem DPH na řádku: N (viz _report.txt)". Router: `kinds_by_code` z `list_kinds(session, client_id)`, `sequences_by_code` z `SELECT code, mask FROM client_sequences WHERE client_id AND year = current_year`, názvy typů z `taxprofile.models.DUNA_TAX_DOC_TYPES` když `client.accounting_system == 'duna'`, jinak jen kód. Název složky druhu se bere z `fields_meta.druh_dokladu.kind_name` uloženého při určení druhu; `kinds_by_code` je jen záloha, a kód, který v katalogu už není (smazaný nebo přepsaný šablonou), dostane složku `<kód>_` a řádek varování v `_navod.txt` — export nikdy nespadne na chybějícím druhu.

**Error Handling:**
- Druh dokladu odkazuje na kód, který v katalogu už není → složka `<code>_neznamy_druh/`, varování v návodu „druh {code} není v katalogu klienta".
- Řada pro kód neexistuje pro aktuální rok → v návodu „řada {code}: maska neznámá (řada pro rok ještě nevznikla)".
- `_navod.txt` nejde sestavit (výjimka) → export selže 500 a nic se nedoručí (stejná politika jako `_report.txt`, komentář `router.py:170-180`: radši žádný export než export bez stopy).

**Edge Cases:**
- `layout=flat` (i volání bez parametru) → jeden adresář jako dnes; `_navod.txt` se NEgeneruje, aby se dnešním volajícím obsah archivu nezměnil; `_report.txt` jako dnes.
- Dvě faktury se stejným Číslem ACTA v různých složkách nemohou nastat (partial unique index 0027); stejné číslo faktury u přijatých od dvou dodavatelů v jedné složce → dnešní přípona `_<id>` (`isdoc_zip.py:55-58`).
- Doklad `overridden` profil s `self_assessment = None` (účetní nevyplnila) → bere se jako `False`, varování v návodu.
- Nulový počet importovatelných dokladů → ZIP obsahuje jen `_navod.txt`, `_report.txt` a `_NEIMPORTOVAT`; hlavičky říkají proč.

**Dependencies:**
- Depends on: Step 7, Step 8
- Blocks: Step 13, Step 14, Step 16

**Acceptance Criteria:**
- [ ] Export potvrzeného dokladu, jehož druh byl mezitím smazán nebo nahrazen šablonou, projde: složka `<kód>_`, varování v `_navod.txt` (test v `backend/tests/export/test_manifest.py`).
- [ ] `test_isdoc_zip.py` pokrývá všechny případy vyjmenované ve Files a prochází; `bash backend/scripts/run_py_test_gate.sh tests/convert` je zelený.
- [ ] `test_manifest.py` prochází a `_navod.txt` obsahuje pro každou složku šest řádků (složka, druh, řada, typ DD, nárok/samovyměření, počet).
- [ ] `GET /api/export?format=isdoc&split_by_category=true` vrací stejnou strukturu jako `layout=category` a volání bez parametru vrací plochý archiv bez `_navod.txt` (testy v `test_isdoc_zip.py`).
- [ ] Doklad s profilem `overridden` bez typu DD je ve složce `<druh>/_bez_typu/` a `_navod.txt` u ní říká, že typ se doplní v DUNĚ (test).
- [ ] Název souboru vydané faktury v ZIPu je `FA_2600241.isdoc` pro doklad s tímto Číslem ACTA (test).

**Effort:** L
**AID Role:** backend

### Step 13: Export ve frontendu: rozvržení ZIPu a hlášení

**Objective:** Tlačítko exportu nabízí rozvržení „Složky pro DUNU (druh / typ dokladu)" jako výchozí a „Bez složek", a po exportu ukáže počty z hlaviček včetně dokladů bez čísla.

**Files:**
- Modify: `frontend/src/components/documents/ExportButton.tsx` (lines ~30-60, 120-160) — místo checkboxu „Rozdělit dle kategorie" select rozvržení (`kind_taxtype` výchozí, `flat`), parametr `layout`, hlášení `X-Export-Unresolved` a `X-Export-No-Number` v toastu („12 dokladů je ve složce _NEIMPORTOVAT: 9 bez rozhodnutí, 3 vydané bez čísla").
- Test: `frontend/src/components/documents/__tests__/ExportButton.test.tsx` (tier: t0) — parametr `layout=kind_taxtype` v URL jako výchozí volba, `layout=flat` po přepnutí, toast s počty.
- Modify: `frontend/e2e/vat-category.spec.ts` (lines ~285-300) — aserce na checkbox „Rozdělit dle kategorie" (řádek 294) nahradit asercí na select rozvržení s volbou „Složky pro DUNU (druh / typ dokladu)".
- Modify: `frontend/src/pages/help/ArchivExportPage.tsx` (lines ~109-150) — sekce `isdoc`: popis dvou úrovní složek, `_navod.txt`, `_NEIMPORTOVAT`; text drží slovník z profilu nápovědy (help-profile v Docusaurusu).
- Modify: `frontend/src/config/helpSections.ts` (lines ~171-186) — sekce `isdoc` dostane klíčová slova `druh dokladu`, `typ daňového dokladu`, `návod`, `neimportovat`.

**Parallel group:** wave-8

**Architecture Context:** Tenká UI vrstva nad Step 12. Checkbox „Rozdělit dle kategorie" (`ExportButton.tsx:147`) mizí, protože kategorie už není osa, podle které DUNA importuje.

**Implementation Detail:**
`ExportButton`: stav `layout: 'kind_taxtype' | 'flat'` (výchozí `kind_taxtype`, uložený v `localStorage` klíč `acta.export.layout` s try/catch); `params.set('layout', layout)` místo `split_by_category` (`ExportButton.tsx:51`); po `fetch` číst `response.headers.get('X-Export-Unresolved')` a `'X-Export-No-Number'`, toast: `${unresolved + noNumber} dokladů je ve složce _NEIMPORTOVAT (${unresolved} bez rozhodnutí, ${noNumber} vydaných bez čísla). Otevřete _navod.txt.`

**Error Handling:**
- Hlavičky chybí (starší backend) → toast bez počtů.
- Export vrátí 4xx → dnešní chybová hláška beze změny.

**Edge Cases:**
- CSV/XLSX → select rozvržení skrytý (parametr se u nich ignoruje, `router.py:32-39`).
- Nula dokladů v `_NEIMPORTOVAT` → toast jen „Export hotov".

**Dependencies:**
- Depends on: Step 12
- Blocks: Step 16

**Acceptance Criteria:**
- [ ] `ExportButton.test.tsx` prochází (URL obsahuje `layout=kind_taxtype`, toast s počty).
- [ ] `grep -n "split_by_category" frontend/src` vrací 0 řádků.
- [ ] Sekce nápovědy `archiv-export#isdoc` popisuje složky druh/typ DD a `_navod.txt` (Playwright `help-structure.spec.ts` ověří, že kotvy z `helpSections.ts` existují).

**Effort:** S
**AID Role:** frontend
**UI Change Mode:** `existing_ui`
**UI Change Contract:** `path: .aid-o/work/evidence/P025/ui/step-13-delta-contract.json | sha256: to-be-computed-at-dispatch | schema_version: 1.0.0 | viewports: desktop, mobile`

### Step 14: Číslo z čítače při schválení u vydaných dokladů, náhled a blokace exportu bez čísla

**Objective:** Vydaný doklad s druhem číslovaným z čítače dostane Číslo ACTA až při schválení, v téže transakci jako potvrzení druhu; před schválením je k dispozici náhled; export vydaného dokladu bez čísla je blokovaný.

**Files:**
- Modify: `backend/acta/documents/vat_category_router.py` (lines ~70-90) — `PATCH /tax-profile` přijme i archivovaný doklad, jehož profil je `proposed` (jen potvrzení, žádná jiná změna), takže doklad archivovaný zkratkou review-and-archive jde potvrdit a odejít z `_NEIMPORTOVAT`.
- Modify: `backend/acta/config.py` (lines ~40-60) — `SEQUENCE_ASSIGN_AT_APPROVAL: bool = True` (přepínač ze Step 5 se zapíná; `deploy/.env` může vrátit `False`).
- Modify: `backend/acta/documents/status_router.py` (lines ~90-105, 120-165, 171-225) — doklad se v `patch_status` i v `review_and_archive` načítá se zámkem řádku (`SELECT … FOR UPDATE`, nová funkce `service.get_document_for_update`), aby souběh dvou schválení téhož dokladu neposunul čítač dvakrát (dnes je `status_router.py:97-101` check-then-act bez zámku a zkratka verzi nekontroluje vůbec); nová funkce `_assign_deferred_number(db, doc, now)` běží VŽDY, když vydanému dokladu z čítače číslo chybí, nezávisle na přepínači (přepínač řídí jen odklad při vytěžení; po jeho vypnutí tak doklady vytěžené v době zapnutí číslo při schválení dostanou): `if doc.direction == 'vydana' and doc.acta_sequence_number is None and doc.client_id is not None: kind = resolve_kind_safe(...)` (pro chráněný druh podle aktuálního kódu, stejně jako Step 5); `if kind.number_source == 'sequence': number, meta = await resolve_acta_number(db, doc.client_id, doc.doc_type or 'faktura', year, month, 'vydana', doc.f_invoice_number, document_id=doc.id, sequence_code=kind.sequence_code, number_source='sequence', assign_now=True)`; zápis čísla, telemetrie a audit `sequence_number_set`. Volá se v `patch_status` po `confirm_proposals_on_approval` a před `transition_document` pro `reviewed`/`archived`, a v `review_and_archive` před přechodem (zkratka návrhy nepotvrzuje, ale číslo přidělit musí, jinak by vydaný doklad zůstal bez čísla navždy; číslo jde z řady aktuálního druhu). Odpověď nese `acta_sequence_number`.
- Modify: `backend/acta/documents/router.py` (lines ~416-460, 530-560, 715-735) — ISDOC export jednoho dokladu: 409 `Vydaný doklad nemá Číslo ACTA — schvalte ho, číslo se přidělí při schválení.` (u dokladu `to_review`) a jméno staženého souboru (řádek 455) přes `isdoc_entry_basename(doc)` ze Step 12; změna klienta (guard na řádku 534) a změna směru (guard na řádku 717) u dokladu ve stavu `reviewed`: doklad se v téže transakci vrací do `to_review` (rozhodnutí PM 1C), `fields_meta.druh_dokladu.state` a `tax_profile_state` jdou z `confirmed` na `proposed`, číslo se stornuje a nové se přidělí při novém schválení; audit `review_reopened` s důvodem `direction_changed` | `client_changed`. U `archived` zůstává dnešní 409.
- Modify: `backend/acta/documents/state_machine.py` (lines ~16-25, 54-60) — nový přechod `"reviewed": {"archived", "to_review"}`; `transition_document(session, doc, new_status, actor_id=None, *, reason: str | None = None, **extra_fields)` — `reason` je VÝSLOVNÝ keyword argument, protože dnešní `**extra_fields` (řádek 59) by ho jinak zapsal jako atribut dokladu; přechod do `to_review` z `reviewed` smí jen volání s `reason` z množiny `direction_changed`, `client_changed`, `kind_changed` (žádné obecné tlačítko „vrátit ke kontrole"); u přechodu z `reviewed` se stornuje číslo z čítače (viz `## Otevřené body pro implementaci`, bod 1).
- Modify: `backend/tests/extraction/test_idempotence.py` (lines ~28-32) — `test_no_back_transitions_from_reviewed` očekává `{"archived", "to_review"}` a nový případ: `transition_document(..., new_status="to_review")` z `reviewed` bez `reason` vyhodí `InvalidStateError`.
- Modify: `backend/acta/documents/service.py` (lines ~584-598) — změna druhu přes `patch_document_field` u dokladu `reviewed`: místo dočasného 409 ze Step 5 doklad znovu otevře (`kind_changed`).
- Modify: `backend/scripts/reextract_schema_failed.py` (lines ~65-80) — podmínka „má Číslo ACTA → řešit ručně" platí jen pro přijaté a pro vydané s `invoice_number`; vydaný z čítače bez čísla se re-extrahuje normálně.
- Modify: `frontend/src/pages/help/CiselneRadyPage.tsx` (lines ~158-210) — sekce `kdy-se-cislo-prideli`: vydané z čítače při schválení, přijaté a odvozené z faktury hned; sekce `zmena-smeru-cisla`: před schválením žádné storno u odložených.
- Test: `backend/tests/documents/test_number_at_approval.py` (tier: t1) — vydaný z čítače: po vytěžení `None`, `number-preview` vrací `preview` s číslem `N`, po schválení `acta_sequence_number` = totéž `N` a `next_number` posunut; dva doklady schválené po sobě dostanou `N`, `N+1` bez díry; změna druhu před schválením mění řadu v náhledu bez storna; přijatý doklad dostává číslo při vytěžení jako dnes; vydaný s `invoice_number` dostává číslo při vytěžení; `SEQUENCE_ASSIGN_AT_APPROVAL=False` vrací dnešní chování u nových dokladů a doklad bez čísla z doby zapnutí číslo při schválení dostane; souběh dvou schválení téhož dokladu (dvě session, `asyncio.gather`) spotřebuje jedno číslo; změna směru u `reviewed` dokladu ho vrátí do `to_review` a po novém schválení má číslo z nové řady; ISDOC export vydaného bez čísla → 409; `review-and-archive` přidělí číslo a druh ani profil nepotvrdí; stažený soubor vydané faktury se jmenuje `FA_<Číslo ACTA>.isdoc`.
- Modify: `backend/tests/documents/test_direction_change_numbering.py` (lines ~300-364) — nové případy na konci, nad skutečnými řádky `client_sequences` (ne přes mock `void_sequence_number`): vydaný odložený doklad při změně na přijatý dostane číslo z přijaté řady hned; zpět na vydaný → storno v přijaté řadě a odklad; vydaný doklad s číslem z řady `FV2` se při změně směru stornuje ve `FV2` a řada `FAV` zůstane beze změny.

**Parallel group:** wave-8

**Architecture Context:** Poslední krok podle rozhodnutí PM (číslo při schválení jen pro vydané z čítače, až po katalogu a potvrzeném druhu, s blokací exportu bez čísla). `resolve_acta_number` zůstává jediným místem přidělení; mění se jen okamžik volání pro jednu třídu dokladů. Přepínač umožňuje vrátit dnešní chování bez nasazení.

**Implementation Detail:**
Náhled: `seq = SELECT … FROM client_sequences WHERE client_id AND code = kind.sequence_code or legacy AND year = (f_issue_date or today).year` bez `FOR UPDATE`; `number = render_mask(seq.mask, year, month, seq.next_number)` pokud řádek existuje, jinak `render_mask(default_mask_for_code(...), year, month, 1)` s `note = "řada pro rok ještě nevznikla, náhled používá výchozí masku"`; `source='preview'`; kolize s obsazeným číslem se v náhledu neřeší (přidělení ji přeskočí, `service.py:170-195`), `note` to říká. Ve schválení: rok a měsíc z `f_issue_date` jako v `documents/router.py:616-618`; při `SequenceExhaustedError` → 409 `Nelze přidělit číslo z řady {code}: {důvod}` a schválení se neprovede (rollback). Hlídat, že `confirm_proposals_on_approval` proběhne dřív (druh je potvrzený, tedy řada je konečná). `service.get_document_for_update(db, doc_id, actor_id)`: stejný dotaz jako `get_document` s `.with_for_update()`.

**Error Handling:**
- Řada vyčerpaná / kolize po 1000 pokusech → 409, doklad zůstává `to_review`, audit nic nezapíše.
- Klient bez katalogu → vestavěný druh, `sequence_code = None` → legacy `FAV`; číslo se přidělí při schválení z `FAV`.
- Přepínač vypnutý → nové doklady dostávají číslo při vytěžení jako dnes; doklady vytěžené v době zapnutí (bez čísla) ho dostanou při schválení, protože `_assign_deferred_number` na přepínač nehledí; test pokrývá obě větve.

**Edge Cases:**
- Doklad byl vytěžen před nasazením (má číslo z čítače) → nic se nemění, schválení číslo nepřiděluje (podmínka `acta_sequence_number is None`).
- Účetní ručně zapíše číslo před schválením (`PATCH acta_sequence_number`, `router.py:854-893`) → schválení respektuje ruční číslo.
- Doklad `reviewed`, kterému účetní změní směr na vydaný → vrátí se do `to_review`, staré číslo se stornuje ve své řadě, nové vznikne při novém schválení; doklad tedy nikdy nezůstane schválený bez čísla.
- Dva souběžné požadavky na schválení téhož dokladu → druhý čeká na zámek řádku, po uvolnění vidí změněnou verzi a dostane 409; čítač se posune jednou.
- Rok vystavení 2025, schválení v 2026 → řada roku 2025 (podle `f_issue_date`), stejně jako dnes v extrakci.

**Dependencies:**
- Depends on: Step 5, Step 8, Step 12 — odklad v `resolve_acta_number` (Step 5), potvrzení druhu před číslem (Step 8), `isdoc_entry_basename` a `_NEIMPORTOVAT/bez_cisla` (Step 12)
- Blocks: Step 16

**Acceptance Criteria:**
- [ ] Archivovaný doklad s profilem `proposed` jde potvrdit přes `PATCH /tax-profile` a příští export ho dá mimo `_NEIMPORTOVAT`; jiná změna archivovaného dokladu vrací 422 dál (test v `backend/tests/documents/test_vat_category_decision.py`).
- [ ] `test_number_at_approval.py` prochází pro všechny případy z Files včetně souběhu a znovuotevření.
- [ ] Ruční běh `docker exec -w /app/backend acta-api python -m pytest -m stack -q tests/e2e/test_p018_full.py tests/e2e/test_issued_pipeline_p018.py` je zelený po zapnutí přepínače (číslo při schválení mění, co tyto testy vidí).
- [ ] `test_direction_change_numbering.py` prochází s novými případy odložení.
- [ ] `grep -n "SEQUENCE_ASSIGN_AT_APPROVAL: bool = True" backend/acta/config.py` vrátí 1 řádek.
- [ ] `GET /api/v1/documents/{id}/export/isdoc` pro vydaný doklad bez čísla vrací 409 (test v `backend/tests/documents/test_archive_download.py` nebo `test_number_at_approval.py`).

**Effort:** L
**AID Role:** backend

### Step 15: Nápověda, Docusaurus a backlog

**Objective:** Účetní má v nápovědě a v Docusaurusu popis katalogu druhů, daňového profilu a exportu pro DUNU; backlog odráží, co plán uzavřel.

**Files:**
- Modify: `frontend/src/pages/help/CiselneRadyPage.tsx` (lines ~83-135, 211-256) — nová sekce `katalog-druhu` (co je druh dokladu, jak ACTA navrhuje, šablona programu, více řad jednoho klienta na příkladu řad 10 a 30), aktualizace `cislo-z-faktury` (čtecí maska je u druhu).
- Modify: `frontend/src/config/helpSections.ts` (lines ~105-112, 153-170) — u `vydane-faktury` sekci `vychozi-hodnoty` přejmenovat na „Druh dokladu a katalog" s klíčovými slovy `druh dokladu`, `katalog`, `53`; u `ciselne-rady` nová sekce `katalog-druhu` s klíčovými slovy `druh dokladu`, `typ daňového dokladu`, `nárok`, `samovyměření`, `šablona`, `duna`.
- Modify: `frontend/src/pages/help/PrijateFakturyPage.tsx` (lines ~120-220) — odstavec o třech polích v detailu (druh, typ daňového dokladu, nárok a samovyměření) a o tom, co schválení potvrzuje.
- Modify: `frontend/src/pages/help/VydaneFakturyPage.tsx` (lines ~170-230) — odstavec o polích druh a typ daňového dokladu v detailu; sekci `vychozi-hodnoty` (řádek 193), která dnes popisuje zrušenou kartu „Výchozí hodnoty dokladů", přepsat na katalog druhů.
- Modify: `/opt/eco/docs/docs/acta/druh-dokladu-a-export-duna.md` — stránka pro účetní (od 17. 9. existuje, doplnit): osy druh / typ DD / řada, tabulka mapování kategorie → typ DD (obě strany), samovyměření, dvě úrovně složek, `_navod.txt`, `_NEIMPORTOVAT`, kdy vzniká číslo; podklady analýzy jmenuje prostým textem (cesta v repu ACTA), NE markdown odkazem: Docusaurus by na odkazu mimo svůj strom shodil build. Tři soubory tohoto kroku leží v JINÉM git repozitáři (`/opt/eco/docs`), mimo worktree plánu; commitují se tam zvlášť a jejich SHA se zapíše do evidence kroku.
- Modify: `/opt/eco/docs/sidebars.ts` (lines ~1-80) — nová stránka do sekce ACTA (sidebar je ruční, bez toho stránka nebude v navigaci).
- Modify: `/opt/eco/docs/docs/acta/zpracovani-prijatych-dokladu.md` (lines ~150-155, 185-195) — evidenční číslo „z řady druhu dokladu", export „složky pro DUNU"; odkaz na novou stránku.
- Modify: `/opt/eco/docs/docs/acta/help-profile.md` (lines ~55-60) — řádek 7 `ciselne-rady` doplnit o katalog druhů.
- Modify: `docs/plans/BACKLOG.md` (lines ~126-139, 1368-1378, 2017-2024) — B-130 → done (P025 Step 5), B-072 → poznámka „Číslo ACTA v CSV od P025 Step 10, lexikografické řazení zůstává", B-031 → zůstává `todo` s poznámkou „zdroj čísla per druh vyřešen P025; parsování čísla z názvu souboru a validace proti vytěženému zůstává", B-073 → poznámka „katalog druhů audit má (P025 Step 4), řady stále ne"; nová položka „Kód plnění SH a kód předmětu plnění §92a" jako budoucí rozšíření daňového profilu.
- Modify: `CHANGELOG.md` (lines ~1-20) — záznam pro příští verzi podle konvence repa.


**Parallel group:** wave-9

**Architecture Context:** Plán mění, co účetní vidí v detailu, v nastavení klienta i v exportu, takže nápověda (§1a help-profile: 100 % pokrytí z kódu) i Docusaurus (`/acta`) musí změnu popsat. Registry sekcí v `helpSections.ts` je zdroj pravdy pro kotvy (CLAUDE.md projektu).

**Implementation Detail:**
Texty drží slovník `help-profile.md` (doklad, přijatá faktura FAP, vydaná FAV, Číslo ACTA, nikdy `direction`, `druh_dokladu`, názvy tabulek). Docusaurus stránka: frontmatter jako `zpracovani-prijatych-dokladu.md:1-9`, sekce: „Tři osy", „Katalog druhů u klienta" (screenshot přes `frontend/e2e/screenshots.mjs` nad vlastním testovacím klientem, ne nad daty Míši), „Co ACTA navrhne a co potvrdíte", „Export pro DUNU krok za krokem" (importní dialog: druh + typ DD podle názvu složky), „Kdy doklad dostane číslo".

**Error Handling:**
- Kotva v nápovědě bez sekce v registru → `help-structure.spec.ts` selže; oprava před merge.

**Edge Cases:**
- Docusaurus build na eco-dev (`acta-docs` :3227) → ověřit `npm run build` v `/opt/eco/docs`, aby odkaz na novou stránku nebyl mrtvý.
- Screenshot nesmí obsahovat reálná data klientů (help-profile).
- Přejmenovaná sekce `vychozi-hodnoty` má v registru nový label, ale stejné `id` → staré odkazy `/napoveda/vydane-faktury#vychozi-hodnoty` fungují dál; `help-structure.spec.ts` by změnu `id` odhalil jako mrtvou kotvu.

**Dependencies:**
- Depends on: Step 9, Step 13, Step 14
- Blocks: Step 16

**Acceptance Criteria:**
- [ ] `frontend/e2e/help-structure.spec.ts` prochází s novou sekcí `katalog-druhu`; spouští se RUČNĚ příkazem z `frontend/e2e/README.md` (CI Playwright nepouští a brána `ts_e2e` je v karanténě, `.aid-o/config/execution.yaml:131`), výstup se přiloží do evidence kroku.
- [ ] `test -f /opt/eco/docs/docs/acta/druh-dokladu-a-export-duna.md`, stránka je v `/opt/eco/docs/sidebars.ts`, `cd /opt/eco/docs && npm run build` projde a změny jsou commitnuté v repu `docs` (SHA v evidenci kroku).
- [ ] `grep -n "B-130" docs/plans/BACKLOG.md` ukazuje status done s odkazem na P025 a B-031 zůstává `todo`.

**Effort:** M
**AID Role:** docs-writer

### Step 16: E2E Pipeline Verification

**Objective:** Ověřit celý tok nad vlastním testovacím klientem: šablona DUNA → vytěžení dvou dokladů → návrh druhu a profilu → schválení s přidělením čísla → export ZIP se složkami a návodem.

**E2E Scenarios (from design):**
1. Založit klienta „E2E P025 …" s `accounting_system=duna`, `POST /document-kinds/apply-template {duna, add_missing}` → 8 druhů a `sequences_missing` s kódy FV1–FV4 a PF; test pak řady FV1 (`{YY}{NNNNN}`), FV2 (`4{YY}{NNNNN}`) a PF (`FAP-{YYYY}/{NNNN}`) založí SÁM přes `POST /sequences`, takže očekávaná čísla plynou z masek testu, ne ze šablony.
2. Nahrát vydanou fakturu (PDF s 21 % DPH, tuzemský odběratel, číslo `10990126`) → po vytěžení `document_kind.code = '53'` (služba) nebo `'501'` (zboží podle `supply_kind`), `tax_doc_type = 'D1'`, `tax_profile_state = 'proposed'`, `acta_sequence_number = null`, `number-preview` vrací `2600001`.
3. Změnit druh v detailu na `501` → náhled zůstává `2600001` (stejná řada FV1); změnit na `502` → náhled `42600001`.
4. Schválit → `acta_sequence_number = '42600001'`, `tax_profile_state = 'confirmed'`, `fields_meta.druh_dokladu.state = 'confirmed'`; druhé schválení jiného dokladu téhož druhu → `42600002`.
5. Nahrát přijatou fakturu od dodavatele z EU (služba, reverse charge text) → `self_assessment = true`, `tax_doc_type = 'U2'`, `tax_deduction = '1'`, číslo `FAP-2026/0001` hned; doklad SCHVÁLIT (jinak má profil `proposed` a export ho dá do `_NEIMPORTOVAT`).
6. Export ISDOC `layout=kind_taxtype` → ZIP obsahuje `502_*/U1/FA_42600001.isdoc`, `44_*/U2_SAMOVYMERENI/FA_<číslo dodavatele>.isdoc`, `_navod.txt` se dvěma složkami, `_report.txt`; neschválený třetí doklad je v `_NEIMPORTOVAT/k_rucnimu_posouzeni/`; vydaný neschválený v `_NEIMPORTOVAT/bez_cisla/`.
7. Negativní: schválení s neaktuálním `expected_kind_code` → 409; export jednoho vydaného dokladu bez čísla → 409; `DELETE` řady FV2 s druhem 502 → 409.
8. Úklid: smazat doklady a klienta v `afterAll`, ověřit 404 (vzor `frontend/e2e/vat-category.spec.ts` po opravě z 31. 8.).

**Files:**
- Create: `frontend/e2e/document-kinds-export.spec.ts` (tier: t2) — scénáře 1–8 přes API + UI (Playwright), vlastní PDF přes sdílený `makePdf`; tier t2, protože je cross-component nad celým Docker stackem s vytěžením přes LLM. Spec běží jen v projektu `chromium` (`test.skip(testInfo.project.name !== 'chromium', …)`, jinak by `npm run e2e` pustil pět LLM vytěžení třikrát) a nastavuje `test.describe.configure({ timeout: 300_000 })`.
- Create: `frontend/e2e/helpers/pdf.ts` — `makePdf` přesunutý z `vat-category.spec.ts`.
- Modify: `frontend/package.json` (lines ~20-60) — `devDependencies`: `jszip` `3.10.1` (pin bez stříšky) pro rozbalení ZIPu v e2e testu; dnes v projektu žádná ZIP knihovna není.
- Modify: `frontend/package-lock.json` (lines ~1-40) — zámek po `npm install --save-dev --save-exact jszip@3.10.1`.
- Modify: `frontend/e2e/vat-category.spec.ts` (lines ~60-110) — import `makePdf` z helperu.
- Modify: `frontend/e2e/README.md` (lines ~1-40) — poznámka, že spec `document-kinds-export.spec.ts` vyžaduje `SEQUENCE_ASSIGN_AT_APPROVAL=true` u služby `acta-api` (výchozí hodnota od Step 14; `deploy/docker-compose.e2e.yml` definuje jen runner `acta-e2e`, API běží z `deploy/docker-compose.yml` + override, takže se přepínač v e2e compose nastavit nedá).

**Reuse check:** searched: `find frontend/e2e -name "document-kinds*"` → none

**Parallel group:** wave-10

**Architecture Context:** Poslední krok posledního EPICu. V ACTA neexistuje žádný „noční tier" ani CI běh Playwrightu a brány `ts_e2e`/`ts_e2e_pwa` jsou v karanténě (`.aid-o/config/execution.yaml:131`, `:158`), takže spec se pouští RUČNĚ: `cd deploy && docker compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.e2e.yml --profile tools run --rm acta-e2e "cd /work && npm ci --no-audit --no-fund && npx playwright test --project=chromium document-kinds-export.spec.ts"` (`npm ci` je nutné: runner má vlastní volume `node_modules` a novou závislost `jszip` by jinak neviděl). Výstup běhu se uloží do evidence kroku jako náhradní doklad (substitute receipt) pro plan-final. Ověřuje řetězec ze `## Architecture` → Tok dat od šablony po ZIP.

**Implementation Detail:**
API volání přes `apiFetch` vzor z `vat-category.spec.ts:60-65`; ZIP se stáhne přes `request.get('/api/export?format=isdoc&layout=kind_taxtype&client_id=…')` a rozbalí knihovnou `jszip` (`await JSZip.loadAsync(await response.body())`). Kontrola `_navod.txt` na řetězce `SLOŽKA: 502_` a `Samovyměření: ANO`.

**Error Handling:**
- Vytěžení trvá déle než 240 s → `expect.poll` timeout, test selže s posledním stavem (vzor `vat-category.spec.ts:171-178`).
- Úklid selže → `afterAll` shodí běh (žádné tiché zbytky).

**Edge Cases:**
- Spuštění dvakrát po sobě → `beforeAll` uklidí klienty s prefixem `E2E P025` z přerušeného běhu.
- LLM vrátí `supply_kind = 'unknown'` → druh padne na výchozí `53`; scénář 2 to přijme (`53` nebo `501`) a scénář 3 druh nastaví explicitně.
- Běh proti hostu s `SEQUENCE_ASSIGN_AT_APPROVAL=false` → scénář 2 by dostal číslo už při vytěžení; proto `beforeAll` po vytěžení prvního vydaného dokladu ověří `GET /number-preview` → `source: 'preview'`; při `source: 'assigned'` test skončí hláškou „acta-api běží se SEQUENCE_ASSIGN_AT_APPROVAL=false, nastavte true v deploy/.env".

**Dependencies:**
- Depends on: Step 9, Step 10, Step 11, Step 13, Step 14, Step 15
- Blocks: none

**Acceptance Criteria:**
- [ ] All scenarios pass on a single full run with 0 failures
- [ ] At least 1 negative/edge case scenario included (scénář 7 má tři)
- [ ] Infrastructure started and healthy before test execution (`acta-api`, `acta-worker`, `acta-ui`, `infra-postgres`)
- [ ] Fix loop: any failures fixed and re-verified (max 3 cycles per check)

**Effort:** M
**AID Role:** e2e

### Vlny

| Wave | Steps | Waits for | Why |
|---|---|---|---|
| 1 | 1 | — | řady (`sequences/*`, migrace 0037) |
| 1b | 3 | 1 | katalog (`doctypes/*`, `docdefaults/*`, migrace 0038 navazuje na 0037); Step 3 závisí na Step 1, proto ne ve stejné vlně |
| 2 | 2 | 1 | API řad (`sequences/router.py`, `test_router.py`) |
| 2b | 4 | 2, 3 | API katalogu, šablony, migrace 0039 a 0040; sahá do `sequences/router.py` a `test_router.py`, které mění i Step 2 |
| 3 | 5, 6 | 2b | backend napojení (`documents/*`, `jobs/extraction.py`, `registry/subject_link.py`, `sequences/service.py`, `config.py`) vs. frontend katalogu a řad (`frontend/src/*`, `frontend/e2e/issued-invoice-fixes.spec.ts`) |
| 4 | 7 | 3 | migrace 0041 a `taxprofile/*` |
| 5 | 8 | 4 | triggery a schválení (`status_router.py`, `vat_category_on_approval.py`, `subject_link.py`, `jobs/extraction.py`) |
| 6 | 9, 10 | 5 | frontend detailu vs. `export/csv.py`, `export/xlsx.py`, skript |
| 7 | 11 | 6 | `documents/isdoc.py`, `tests/export/test_isdoc_schema.py`, `tests/convert/test_convert_service.py` |
| 7b | 12 | 7 | `export/isdoc_zip.py`, `export/manifest.py`, `export/router.py`, `export/service.py`; sdílí s Step 11 soubor `tests/convert/test_convert_service.py`, proto vlastní vlna |
| 8 | 13, 14 | 7b | `ExportButton.tsx`, `ArchivExportPage.tsx`, `frontend/e2e/vat-category.spec.ts` (řádky 285-300) vs. `status_router.py`, `documents/router.py`, `CiselneRadyPage.tsx` |
| 9 | 15 | 8 | dokumentace |
| 10 | 16 | 9 | E2E (`frontend/e2e/vat-category.spec.ts` řádky 60-110: import `makePdf`) |

Sdílená rozhraní mezi kroky v různých vlnách (pro kontrolu, že žádná dvojice není ve stejné vlně): `PATCH /api/v1/documents/{doc_id}/status` mění Step 8 (vlna 5) a Step 14 (vlna 8); `resolve_acta_number` mění Step 1 (vlna 1) a Step 5 (vlna 3); `backend/acta/config.py` Step 5 (vlna 3) a Step 14 (vlna 8); `backend/acta/main.py` Step 3 (1b), Step 4 (2b) a Step 8 (5).

## Migration Plan

| Migrace | Krok | Co dělá | Downgrade | Pojistka |
|---|---|---|---|---|
| `0036_vat_category_non_payer` | mimo plán (větev `feat/neplatce-kategorie`, sloučit před startem) | 13. kategorie `domestic_non_payer` | mimo plán | plán na ni navazuje, nemění ji |
| `0037_sequence_code` | Step 1 | `client_sequences.code`, `name`, backfill kódu, nový unikátní klíč `(client_id, code, year)` | obnoví starý klíč; selže s hláškou, pokud mezitím vznikly dvě řady téhož typu ve směru | kontrola kolizí před `SET NOT NULL`, test nad kopií schématu |
| `0038_document_kinds` | Step 3 | tabulka `client_document_kinds`, kopie dat z `client_document_defaults` (stará tabulka zůstává) | `DROP TABLE client_document_kinds` | kontrola rovnosti počtů řádků |
| `0039_client_accounting_system` | Step 4 | `clients.accounting_system` NULL + CHECK | `DROP COLUMN` | — |
| `0040_rename_client_document_defaults_legacy` | Step 4 | preflight + `RENAME TO client_document_defaults_legacy` | přejmenuje zpět | preflight „každý řádek má výchozí protějšek v katalogu"; data se nemažou |
| `0041_document_tax_profile` | Step 7 | pět sloupců daňového profilu na `documents` + index | `DROP COLUMN` × 5 | výchozí `not_run`, žádný přepis dat |

Pořadí nasazení = pořadí EPICů; každý EPIC se nasazuje jako celek. Kontejnery `acta-api` i `acta-worker` pouštějí `alembic upgrade head` v entrypointu před startem aplikace a po nasazení se restartují OBA (extrakce běží ve workeru, schvalování a změny směru v API; oba čtou nové sloupce `documents`). `backend/db/env.py` musí po Step 3 importovat `ClientDocumentKind` místo smazaného modelu, jinak žádná migrace neproběhne. Data po nasazení: EPIC 1 nic nepřepisuje (klient bez katalogu má vestavěné 44/53 jako dnes); EPIC 2 vyžaduje ruční kroky z `## Next Steps` (program klienta, backfill návrhů, potvrzení schválených); EPIC 3 zapíná přepínač `SEQUENCE_ASSIGN_AT_APPROVAL`, který lze v `deploy/.env` vrátit na `false` bez nasazení (doklady bez čísla z doby zapnutí ho dostanou při schválení).

## Testing Strategy

**Které chování plán ověřuje.** (1) Druh dokladu se vybírá jako nejkonkrétnější řádek katalogu podle (směr, typ písemnosti, kategorie, povaha plnění, samovyměření) a bez katalogu padá na dnešní 44/53. (2) Řada je identifikovaná kódem: dva druhy sdílí čítač, dva kódy v jednom směru mají čítače oddělené, nový rok kopíruje masku. (3) Číslo odvozené z faktury se renderuje maskou řady druhu, včetně druhé řady klienta (`30{NNN}{YY}` → `42600005`). (4) Mapování kategorie → typ DD DUNA dává pro každou položku `VAT_CATEGORIES` (13) v obou směrech definovaný návrh, nárok a samovyměření, a nikdy nepřepíše potvrzený profil ani schválený doklad. (5) Schválení potvrdí kategorii, druh a profil najednou a u vydaného z čítače přidělí číslo v téže transakci; dva po sobě schválené doklady nemají díru. (6) ZIP má složky `<druh>/<typ DD>`, samovyměření zvlášť, `_NEIMPORTOVAT` pro nerozhodnuté a vydané bez čísla, `_navod.txt` s řádkem na složku. (7) ISDOC s `LocalReverseChargeFlag` validuje proti XSD a parser ho přečte zpět. (8) Migrace 0037, 0038, 0040 a 0041 mají upgrade i downgrade nad kopií schématu a 0040 nesmaže starou tabulku, dokud každý její řádek nemá protějšek v katalogu. (9) Storno čísla se provede v řadě, ze které číslo pochází (kód řady), ověřeno nad skutečnými řádky, ne mockem. (10) V extrakci běží klasifikace před určením druhu a přidělením čísla.

**Proč tato chování.** Každé mění rozhodnutí, na které navazuje účetnictví klienta: ze které řady číslo, jaký druh a typ DD do DUNY, kdy číslo vznikne. Chyba se neprojeví v ACTA, ale až v přiznání k DPH klienta; proto se testují hranice (fallbacky, potvrzené stavy, dvě řady, dva směry), ne jen šťastná cesta.

**Kde ověření je.** Přednostně v existujících suitách: `backend/tests/sequences/test_service.py`, `test_resolve_acta_number.py`, `test_router.py` (řady); `backend/tests/documents/test_derived_fields_all_paths.py`, `test_direction_change_numbering.py`, `test_split_direction.py`, `test_vat_category_decision.py`, `test_tax_inputs_api.py` (cesty přidělování a schválení); `backend/tests/export/test_isdoc_zip.py`, `test_isdoc_schema.py`, `test_export.py` (export); `backend/tests/extraction/test_isdoc_parser.py` (round-trip). Nové suity jsou rozhodnutí, ne zvyk: `backend/tests/doctypes/test_resolver.py` (t0) a `test_router.py` (t1) pro nový modul katalogu; `backend/tests/taxprofile/test_duna_mapping.py`, `test_service.py` (t0), `test_router.py` (t1) pro nový modul profilu; `backend/tests/migrations/test_migration_0037.py`, `test_migration_0038.py`, `test_migration_0040.py`, `test_migration_0041.py` (t1) podle vzoru `backend/tests/sequences/test_migration_0019.py`; pořadí kroků extrakce hlídá rozšířený existující `backend/tests/extraction/test_direction_ordering.py` (t1) nad sdíleným harnessem z `test_extract_document_integration.py`; `backend/tests/export/test_manifest.py` (t0); `backend/tests/documents/test_number_at_approval.py` (t1), protože okamžik přidělení je nové chování bez domovské suity; `backend/tests/scripts/test_backfill_tax_profile.py` (t1); frontend `TaxProfileFields.test.tsx`, `ExportButton.test.tsx` (t0); `frontend/e2e/document-kinds-export.spec.ts` (t2: cross-component nad Dockerem s LLM; v ACTA žádný noční běh ani CI Playwright neexistuje, spec se pouští ručně příkazem uvedeným ve Step 16 a jeho výstup je náhradní doklad pro plan-final). Značky `tier:` jsou v ACTA jen popisky (pytest zná jediný marker `stack`); každý nový DB test používá `tests.db_guard.skip_or_fail_without_db` a vlastní `pytest.skip` kvůli chybějící DB je zakázaný (vzorec B-046: zelená brána, která nic netestuje). Testy se značkou `stack` výchozí běh vyřazuje, proto mají Step 3, Step 5 a Step 14 v AC jejich ruční příkaz. Testy `backend/tests/docdefaults/test_docdefaults_api.py` a `frontend/.../documentDefaults.test.ts` se ruší, protože ruší svůj předmět (Step 3, 6).

## Constraints

- Sloupce CSV jen na konec (poziční kontrakt, `backend/acta/export/csv.py:80-89`).
- Spec P016 §3.3: režim DPH se neodvozuje ze sazby, země, DIČ ani registru. Plán se toho drží: samovyměření a typ DD se odvozují z potvrzené či navržené **kategorie**, ne z těchto vstupů; `NE` pro klienta neplátce vychází VÝHRADNĚ z výslovného daňového profilu klienta (`ClientVatProfile.vat_subject_type = 'non_payer'` platného k DUZP, vyhodnoceno existující funkcí `resolve_vat_subject_type(profiles, on_date)` v `backend/acta/registry/classifier.py:937`), nikdy ze sloupce `Client.vat_payer` (NOT NULL DEFAULT false) a nikdy z registru protistrany.
- Po schválení žádný automatický přepis kategorie, druhu ani profilu (spec P016 §9); backfill v režimu „návrh" zapisuje jen `proposed`. Jediná výjimka je režim `--confirm-approved`, který potvrzuje profil u dokladů, jež účetní už schválila, a to po klientech (`--client-id`) a jen podle výpisu, který účetní odsouhlasila.
- Změna řazení exportu (druhý klíč `f_issue_date`) platí i pro CSV, XLSX a plochý ZIP: pořadí řádků u dokladů bez čísla se účetní změní; obsah ani struktura ne.
- Předpoklad startu: větev `feat/neplatce-kategorie` (migrace `0036_vat_category_non_payer.py`, kategorie `domestic_non_payer`, klasifikátor R12/R12x) je sloučená do `main` DŘÍV, než vznikne větev plánu; migrace plánu na ni navazují (`down_revision = "0036"`) a dev DB už na `0036` stojí. Bez sloučení `alembic heads` ukáže dvě hlavy a EPIC 1 nejde nasadit.
- Ruční příkazy v AC (testy se značkou `stack`, Playwright, `alembic` nad kopií schématu) se pouštějí z kořene worktree plánu, ne z hlavního checkoutu; příkazy přes `docker exec acta-api` platí až po nasazení větve na eco-dev (`docker compose up -d --build` z worktree, `.env` se do worktree kopíruje z `deploy/`), jinak běží proti starému kódu a projdou zeleně naprázdno.
- ACTA běží jako jeden kontejner `acta-api` (žádné rolling nasazení) a EPIC se nasazuje jako celek. Uvnitř EPICu 1 přesto platí pořadí: Step 3 zruší zapisovatele do `client_document_defaults` (router) a data zkopíruje (0038), teprve Step 4 tabulku po kontrole smaže (0040). Nové sloupce se přidávají jako NULL nebo s DEFAULT. Pořadí nasazení = pořadí EPICů.
- Volání `GET /api/export?format=isdoc` bez parametru `layout` vrací po změně totéž co dnes (plochý archiv); nové rozvržení si frontend žádá výslovně.
- Frontend musí zůstat použitelný na tabletu a telefonu (P019): žádná nová stránka, tabulky v `overflow-x-auto`, pole jako `FieldRow`.
- Přepínač `SEQUENCE_ASSIGN_AT_APPROVAL` umožňuje vrátit dnešní okamžik číslování bez nového nasazení.
- Dokumentace pro účetní bez interních názvů (`docs/acta/help-profile.md` slovník).

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Migrace 0037 změní klíč řady a rozbije přidělení čísla na produkci | low | high | test nad kopií schématu (Step 1), `sequence_code=None` = legacy kód, žádné číslo se nemění, downgrade ověřený |
| Katalog navrhne špatný druh a účetní ho přehlédne | medium | high | druh je pole s viditelným štítkem „návrh ACTA", schválení vyžaduje `expected_kind_code` (409 při změně), `_navod.txt` opakuje druh u složky |
| Šablona DUNA navrhne masky řad, které v DUNĚ klienta neplatí | medium | medium | šablona řady nezakládá, jen navrhuje (`sequences_missing`); masky potvrzuje účetní; E2E si řady zakládá sám |
| Mapování kategorie → typ DD DUNA je v některé buňce věcně špatně | medium | high | tabulka je data v jednom souboru, testovaná řádek po řádku; návrh vždy s alternativami a varováním; před ostrým nasazením předat tabulku účetní k odsouhlasení (mimo plán, PM) |
| Číslo při schválení: doklad, který se nikdy neschválí, číslo nedostane a účetní ho nenajde podle čísla | low | low | seznam podle čísla neřadí ani nehledá (`filters.py`); `_NEIMPORTOVAT/bez_cisla` a náhled v detailu |
| DUNA vezme Číslo ACTA jako evidenční číslo do kontrolního hlášení | medium | high | mimo rozsah plánu (rozhodnutí PM 17. 9.), ověřuje účetní; plán nemění dnešní `ID` |
| `apply-template replace` smaže druhy s historickými doklady | low | medium | 409 při dokladech `to_review`; archivované doklady drží kód v `fields`, export ho označí „neznámý druh" místo pádu |
| E2E test závisí na LLM (`supply_kind`) | medium | low | scénář přijímá obě hodnoty a druh nastavuje explicitně |

## Otevřené body pro implementaci

Rozhodnutí PM 17. 9. 2026: plán se dál nereviduje (dvě kola oprav nekonvergovala, každá oprava přidala nový mechanismus a s ním nové hrany). Body níže našlo potvrzovací kolo (`.aid-o/work/evidence/P025/konvergence/mereni.md`, „10 blokujících shluků") a řeší se PŘI IMPLEMENTACI daného kroku: implementer si je přečte před krokem, drží uvedené pravidlo a v CP2 doloží testem. Pravidlo pro všechny: nepřidávat další mechanismy; kde plán nabízí dvě verze, platí ta níže.

1. **Změna druhu / směru / klienta u schváleného dokladu (Step 14, EPIC 3).** Platí: znovuotevření (`reviewed → to_review`) VŽDY stornuje číslo z čítače (`void_sequence_number` s kódem řady z `fields_meta._acta_number.sequence_code`) a nové číslo vzniká při novém schválení; číslo odvozené z faktury se jen přerenderuje (`renumber_if_series_changed`). Tok dat v `## Architecture` a Step 14 se čtou takto, ne jako dvě různé věci. Test: `test_number_at_approval.py` – znovuotevřený doklad nemá číslo, čítač po novém schválení bez díry.
2. **`renumber_if_series_changed` (Step 5).** Přerenderuje JEN číslo se `source == "invoice_number"`; `sequence_fallback` a čísla z čítače nechává (jinak každý běh spálí číslo). Ruční PATCH čísla zapíše do `fields_meta._acta_number` `manual = True` a `sequence_code` (dnes chybí, proto je nutné to doplnit v `patch_document_field`) a funkce ruční číslo nikdy nepřepíše. Doklad bez `sequence_code` v telemetrii (starší doklady) se nepřerenderuje, jen dostane `number_series_mismatch = True`. Funkce je idempotentní: druhé volání se stejným druhem nic nezmění (test v `test_direction_change_numbering.py`).
3. **Chráněný druh a směr (Step 5).** Resolver i kontrola „druh ještě existuje v katalogu" vždy hledají s `direction`; chráněný je jen druh `edited_by_user`/`manual`, stav `reviewed` druh nezamyká (změna směru u schváleného dokladu druh přepočítá jako dnes výchozí druh). Zámek přes znovuotevření je až Step 14.
4. **Zámek řádku (Step 5 a Step 14).** `SELECT … FOR UPDATE` (`service.get_document_for_update`) používá KAŽDÉ místo, které číslo přiděluje nebo stornuje: schválení, zkratka, změna směru, změna klienta, znovuotevření, archivace. `PATCH /documents/{id}` (změna směru/klienta) navíc kontroluje `version` jako `patch_status`; pokud dnešní handler `version` nepřijímá, přidá se jako volitelné pole a bez něj se chová jako dnes.
5. **Typ DD z druhu (Step 8).** Jediná funkce `recompute_after_classification(session, doc, client, *, trigger)` v `taxprofile/service.py` v pořadí: `refresh_tax_profile` (adaptér, dá `self_assessment`) → přepočet druhu (`apply_direction_derived_fields`) → `apply_kind_tax_doc_type` (typ z druhu přebije mapování) → `renumber_if_series_changed`. Volají ji všechny spouštěče (extrakce, `reclassify_document`, confirm/override kategorie, změna programu klienta) a ruční změna druhu v `patch_document_field` volá `apply_kind_tax_doc_type` také; `refresh_tax_profile` tedy nikdy nezůstane posledním zapisovatelem typu. Step 5 a Step 8 se tímto pořadím srovnávají.
6. **`expected_tax_doc_type` (Step 8).** Platí verze v Implementation Detail Step 8 (`tax_doc_type_sent` z `model_fields_set`, `None` poslané výslovně potvrzuje profil bez typu). Frontend (Step 9) pole posílá vždy, i s hodnotou `null`.
7. **Testy mimo Files** – doplněny do Files Step 5 a Step 14 (`test_resolve_acta_number.py`, `test_field_edit.py`, `test_subject_link.py`, `test_idempotence.py`, `transition_document(reason=)`). Implementer před CP2 každého kroku pouští celou suite `backend/tests`, ne jen soubory z Files.
8. **Ruční příkazy v AC** – viz `## Constraints`: z worktree plánu, `docker exec` až po nasazení větve.
9. **Potvrzení při schválení bez časného `return`** – zapracováno do Implementation Detail Step 8.
10. **Migrace a 13. kategorie** – vyřešeno v této verzi plánu (0037–0041, `domestic_non_payer` ve Step 7).

## Success Criteria

- Klient Michaely Štanclové má po `apply-template duna` sedm druhů vydaných faktur; řady účetní založí nebo připojí podle nabídky `sequences_missing` (masky potvrdí ona, šablona je jen navrhuje); vydaná faktura do EU pak dostane návrh druhu `502`, řady `FV2` a typu `U1` a po schválení číslo z masky řady `FV2`.
- Účetní importuje ZIP do DUNY složku po složce a v dialogu opíše druh a typ DD z názvu složky; samovyměření pozná podle názvu složky a `_navod.txt`.
- Žádný schválený vydaný doklad z čítače nemá po nasazení díru v řadě způsobenou změnou druhu před schválením.
- Všechny suity z `## Testing Strategy` zelené; `frontend/e2e/document-kinds-export.spec.ts` projde na jeden běh.

## Resources Verification

*(universal)*

### Existing Resources (must exist in codebase)

- [ ] Functions/helpers: `resolve_acta_number`, `get_next_sequence_number`, `void_sequence_number`, `sequence_number_taken`, `_load_or_create_sequence` (`backend/acta/sequences/service.py:30,66,142,205,353`); `default_mask_for`, `render_mask`, `validate_mask`, `parse_mask`, `validate_read_mask` (`backend/acta/sequences/mask.py:57,73,88,157,217`); `resolve_defaults_safe`, `get_document_defaults`, `list_document_defaults` (`backend/acta/docdefaults/service.py`; `upsert_document_defaults` tamtéž dnes existuje a Step 3 ho ruší); `apply_duna_document_type` (`backend/acta/extraction/fields.py:698`); `apply_direction_derived_fields` (`backend/acta/documents/derived_fields.py`); `confirm_proposed_on_approval`, `ProposalChangedError` (`backend/acta/documents/vat_category_on_approval.py:37,41`); `reclassify_document`, `_apply_updates` (`backend/acta/registry/subject_link.py:240,265`); `build_isdoc`, `_build_lines`, `_emit_party` (`backend/acta/documents/isdoc.py`); `documents_to_isdoc_zip`, `_category_folder`, `_entry_name` (`backend/acta/export/isdoc_zip.py:25,44,63`); `documents_to_csv`, `_rates_equal`, `field_str`, `attr_str` (`backend/acta/export/csv.py`); `documents_to_xlsx` (`backend/acta/export/xlsx.py:39`); `get_export_documents`, `record_export_events`, `get_line_items_map` (`backend/acta/export/service.py`); `transition_document`, `VatCategoryUndecidedError` (`backend/acta/documents/state_machine.py:54,31`); `_require_admin_or_accountant` (`backend/acta/sequences/router.py:35`; kopie v `backend/acta/docdefaults/router.py:60` zaniká se souborem ve Step 3); `resolve_vat_subject_type` (`backend/acta/registry/classifier.py:937`); `usePatchField` (`frontend/src/api/documents.ts:232`).
- [ ] File paths: všechny `Modify:` cesty v krocích existují (ověřeno 16.–17. 9. 2026 při analýze); `Create:` cesty neexistují (Reuse check u každého kroku).
- [ ] Ports: žádný nový port.
- [ ] Services / containers: `acta-api`, `acta-worker` (extrakce), `acta-ui`, `infra-postgres` (běží na eco-dev).
- [ ] External commands: `alembic`, `pytest`, `ruff`, `npm`, `npx playwright` (v obrazech `acta-api` / `acta-ui`).
- [ ] Knihovny: `jszip` 3.10.1 (nová dev závislost frontendu, Step 16).
- [ ] Environment variables: `SEQUENCE_ASSIGN_AT_APPROVAL` (nová, Step 5, výchozí `False`, Step 14 `True`), `ACTA_E2E_EMAIL`, `ACTA_E2E_PASSWORD` (existují v `deploy/.env`).

### Plan Assumptions

- [ ] Backlog IDs: plán jmenuje B-130, B-072, B-031 (existují v `docs/plans/BACKLOG.md`); žádné `T-NNN`.
- [ ] Test directory paths: nové suity `backend/tests/doctypes/`, `backend/tests/taxprofile/`, `backend/tests/migrations/`, `backend/tests/scripts/` MAJÍ sourozence se stejným basename (`test_router.py`, `test_service.py` jsou i v `tests/sequences/` a `tests/registry/`); kolizi řeší `__init__.py` v nových adresářích (Step 3, Step 7), stejně jako u všech dnešních testových adresářů (ověřeno `find backend/tests -name "test_resolver*"`, `-name "test_migration_0037*"` → nic; `backend/tests/sequences/test_migration_0019.py` je vzor, ne kolize).
- [ ] DB field semantics: `Document.tax_profile_state`, `Document.acta_sequence_number`, `ClientSequence.next_number` jsou uložené sloupce (žádný computed).
- [ ] File removal claims (všechny mají vlastní `Modify: … smazat` bullet: Step 3 a Step 6): `backend/acta/docdefaults/models.py`, `backend/acta/docdefaults/router.py`, `backend/tests/docdefaults/test_docdefaults_api.py`, `frontend/src/components/client/ClientDocumentDefaults.tsx`, `frontend/src/api/documentDefaults.ts` dnes existují (ověřeno `ls`).

### Resolution

- [ ] All items VERIFIED OR mapped to a Create step in this plan
- [ ] PM acknowledges any ABSENT items as out-of-scope risks (with rationale)

## Acceptance Criteria

*(universal; `verification_pattern` bloky jsou povinné pro band `full`)*

- [ ] AC1: Řada má sloupec `code` v modelu.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "backend/acta/sequences/models.py"
    regex: "code: Mapped\\[str\\]"
  ```

- [ ] AC2: Katalog druhů existuje jako modul s resolverem.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "grep -q 'def resolve_document_kind' backend/acta/doctypes/service.py"
    expected_exit: 0
  ```

- [ ] AC3: Stará tabulka nastavení druhu je z modelu pryč.
  ```yaml
  verification_pattern:
    type: must_not_exist
    file: "backend/acta/docdefaults/models.py"
  ```

- [ ] AC4: Doklad má sloupce daňového profilu.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "backend/acta/documents/models.py"
    regex: "tax_profile_state"
  ```

- [ ] AC5: Mapování DUNA nabízí u přijaté přeshraniční služby `U2` s alternativou `U4`.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "backend/acta/taxprofile/duna.py"
    regex: "U2.*U4"
  ```

- [ ] AC6: Schválení potvrzuje druh i profil.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "backend/acta/documents/status_router.py"
    regex: "expected_kind_code"
  ```

- [ ] AC7: Export generuje `_navod.txt`.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "backend/acta/export/router.py"
    regex: "_navod\\.txt"
  ```

- [ ] AC8: ISDOC builder zapisuje `LocalReverseChargeFlag`.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "backend/acta/documents/isdoc.py"
    regex: "LocalReverseChargeFlag"
  ```

- [ ] AC9: Číslo při schválení je zapnuté přepínačem.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "backend/acta/config.py"
    regex: "SEQUENCE_ASSIGN_AT_APPROVAL: bool = True"
  ```

- [ ] AC10: Pět migrací existuje.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "test -f backend/db/versions/0037_sequence_code.py -a -f backend/db/versions/0038_document_kinds.py -a -f backend/db/versions/0039_client_accounting_system.py -a -f backend/db/versions/0040_rename_client_document_defaults_legacy.py -a -f backend/db/versions/0041_document_tax_profile.py"
    expected_exit: 0
  ```

- [ ] AC11: Frontend už nepoužívá staré nastavení druhu.
  ```yaml
  verification_pattern:
    type: must_not_exist
    file: "frontend/src/components/client/ClientDocumentDefaults.tsx"
  ```

- [ ] AC12: Nápověda má sekci katalogu druhů.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "frontend/src/config/helpSections.ts"
    regex: "katalog-druhu"
  ```

## Next Steps

- [ ] Sloučit větev `feat/neplatce-kategorie` do `main` (migrace 0036, kategorie `domestic_non_payer`) a teprve potom založit větev plánu
- [ ] Create Epic(s) from this plan (chain: EPIC 1 → 2 → 3)
- [ ] Implementer čte `## Otevřené body pro implementaci` před Step 5, 8 a 14; body se uzavírají testem v CP2, ne další revizí plánu
- [ ] PM předá účetní tabulku mapování kategorie → typ DD (Step 7) k věcnému odsouhlasení před nasazením EPICu 2
- [ ] Commitnout podklady `docs/plans/analyzy/2026-09-16-druh-typ-dd-rada/` spolu s plánem (dnes nejsou v gitu a plán i dokumentace na ně odkazují); `01-duna-napoveda-vynatky.md` jsou výňatky z nápovědy výrobce, repo je privátní
- [ ] Po nasazení EPICu 1 nastavit klientovi Michaely Štanclové účetní program DUNA, spustit `apply-template duna` a nastavit druh 532 se čtecí maskou `30{NNN}{YY}` (uzavře B-130)
- [ ] Před backfillem daňového profilu (EPIC 2) ověřit, že každý klient s DUNOU má `accounting_system = 'duna'`; klient bez programu dostává návrh bez typu DD
- [ ] Po nasazení EPICu 2 spustit `scripts/backfill_tax_profile.py` (dry-run, pak `--apply`), potom režim `--confirm-approved`: dry-run výpis předat účetní k odsouhlasení, pak `--apply --expected-count N` (bez toho historické schválené doklady skončí v exportu v `_NEIMPORTOVAT`)
- [ ] Před zapnutím šablony DUNA u klienta Michaely Štanclové získat od účetní kódy a masky řad v DUNĚ (otázka č. 4 v `04-stav-a-rozhodnuti.md`)

---

**Last Updated:** 2026-09-17 (v5: migrace přečíslované na 0037–0041 za `0036_vat_category_non_payer`, 13. kategorie, testy mimo Files doplněny, otevřené body z potvrzovacího kola předány implementaci – rozhodnutí PM „podchytit při vývoji"; v4 po formální bráně CP1-light + CP1-deep, rozhodnutí PM 1C/2B/3A; v3 po konvergenční recenzi: `.aid-o/work/evidence/P025/konvergence/`)
