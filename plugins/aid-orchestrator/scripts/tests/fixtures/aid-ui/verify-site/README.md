Gate fixture (test-aid-ui-verify.bats). `site/` = two pages with one planted defect per
check; copying `fixed/` over it gives a clean site. `project/` = the project files the
gate reads (facts register, brand package). Planted: index.html - no_overflow, one_line_controls,
facts_match (999 Kč), axe (img without alt), image_weight (PNG), no_overlap (.prekryv pulled over the H1); o-nas/index.html -
glyph_coverage (monospace), no_placeholders (lorem), brand_assets (drawn logo),
links_resources (/neni.html), required_files (no og:image), seo (noindex), brand_consistency (its header lacks index.html's inline mark). Neither site page
names an IČO (business_minimum); the fixed pages carry it in a shared footer.
Fonts: Geist (SIL OFL 1.1). The red lazy image at the bottom of index.html proves the
screenshot is taken after scrolling.

## Klíč zasazených vad dílny (P113, krok 7)

Třináct druhů vad, které dílna zasadila do kopie hotového webu (F6, kontrola-postup.md), a řádek brány, který každou musí
nahlásit. Tvar řádku: `- dílna <id> <popis> | <řádek brány> | <stránka> | <slovo v detailu>`. Test `all-pages: planted`
je čte a vypíše `dílna: N/13`. Vadu V4 dílny (doporučení obcí bez souhlasu) žádný řádek brány nenajde - patří kontrole
textů (copy_review, model); místo ní je tu chybějící `meta viewport` (oprava 55), kterou dílna našla na jednosouborovém
náhledu. Stránka `vady/` nese vady, které dosavadní sada neměla; `fixed/vady/` je její čistá kopie.

- dílna V1 kontrast textu pod 4,5:1 | axe | vady/index.html | color-contrast
- dílna V2 obsahový obrázek bez popisu | axe | index.html | image-alt
- dílna V3 vymyšlený údaj mimo registr | facts_match | index.html | 200 klientům
- dílna V5 přetečení na telefonu | no_overflow | index.html | sideways
- dílna V6 mrtvý odkaz | links_resources | o-nas/index.html | neni.html
- dílna V7 rozmazaný obrázek | image_weight | index.html | rozmazaný
- dílna V8 animace řízená skriptem | motion_settled | vady/index.html | skriptová animace
- dílna V9 formulář bez informace o údajích | business_minimum | vady/index.html | personal data
- dílna V10 cizí požadavek před souhlasem | privacy_before_consent | vady/index.html | third-party
- dílna V11 malá dotyková plocha | touch_targets | vady/index.html | under 44 px
- dílna V12 druhé H1 | a11y_basics | vady/index.html | h1
- dílna V13 nekontrastní fokus | a11y_basics | index.html | focus ring under 3:1
- dílna V14 chybí meta viewport | mobile_native | vady/index.html | meta viewport
