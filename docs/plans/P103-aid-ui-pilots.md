# P103 Step 9: zpětná kontrola a piloty `/aid-ui` (akceptační záznam)

Jednou větou: nová brána `/aid-ui` Truhlárnu Dub zamítla na všech čtyřech
známých vadách (písmo, logo, zástupné texty, těžké obrázky); piloty Needless (web)
a Objednávky (aplikace) prošly celým tokem na studiu až po `finish`; produktový verdikt PM čeká.

Summary (EN, for the plan AC check): Truhlárna Dub: FAIL as expected (glyph_coverage, brand_assets, no_placeholders, image_weight all fail); Needless: technical PASS, PM verdict pending; Objednávky: technical PASS with two PM exceptions, PM verdict pending.

Zapsáno 2026-09-28. Testovaný kód: worktree `.aid-worktrees/plan-P103`,
větev `task/E-103-3_3/main`.

## Truhlárna Dub (zpětná kontrola)

| | |
|---|---|
| Co běželo | brána `aid-ui-verify.sh` na kopii webu z `.aid-o/work/P103-zkouska/truhlarna-p102/site/` (stav založený, build zapsaný), 5 stránek × chromium/webkit × 390/768/1440 px |
| Výsledek | **FAIL** (očekávaný), exit 3 |
| Řádky celkem | 420: pass 288, fail 99, not_covered 30, warn 3 |

Padající kontroly (jedna ukázka detailu na kontrolu):

| Kontrola | Řádků | Detail |
|---|---|---|
| `glyph_coverage` | 3 | `/postup/` nadpis „Od zaměření po montáž": 3 znaky v systémovém Liberation Sans, zbytek v Karantině (písmo nemá českou diakritiku) |
| `brand_assets` | 30 | „not from the brand package: inline `<svg>` in a.brand" na každé stránce - logo nakreslené v hlavičce ručně, ne symbol z brand balíčku |
| `no_placeholders` | 6 | `/kontakt/`: text „fiktivn…" a `mailto:dilna@example.invalid` |
| `image_weight` | 30 | `/assets/plates/table-plate.png` je PNG a má 1751 kB, `/assets/plates/paper.png` je PNG |
| `required_files` | 30 | chybí `404.html`, žádný `og:image` |

Nepokryté: `facts_match` (30 řádků) - projekt nemá `docs/content/facts.yaml`,
není s čím fakta porovnat. Varování: `lighthouse_mobile` na úvodní stránce,
výkon 70/100 (3 řádky).

Oprava brány, kterou kontrola odhalila: `brand_assets` dřív kontroloval jen
loga v `<img>` a favikony, takže ručně nakreslené SVG logo v hlavičce prošlo.
Teď se kontroluje každé logo (obrázek i vložené SVG uvnitř odkazu na úvod nebo
prvku pojmenovaného logo/brand) a vložené SVG se porovná tvarem (viewBox
a geometrie tvarů, bez barev, mezer a id) s každým SVG v brand balíčku.
První běh brány před opravou hlásil `brand_assets` pass, druhý běh po opravě fail.

Výjimky udělené PM: žádné.

## Needless (web)

Projekt: kopie vstupů `/opt/eco/projects/bez-rutiny-codex` v `.aid-o/work/P103-pilot/needless` (skutečný projekt se nemění).
Varianta: klasický vícestránkový web, nová identita, místní firma, vize + logo + SEO.

**Kdo rozhodoval:** krok 0 a fakta k vizi PM ve studiu (28. 9. odpoledne). Od kroku 1v dál
rozhodoval agent z pověření PM („vše vyber ty", 28. 9. 2026 večer), vždy kliknutím na stránce
studia (Playwright), takže každé rozhodnutí prošlo `record-answer` a mutací s `--answer`.
Produktový verdikt dává PM.

| Krok | Na studiu | Rozhodnutí (id odpovědi) |
|---|---|---|
| 0 | druh webu, co připravit | PM: web, nová značka, místní; vize, logo, SEO (q-web2, q-prepare2) |
| 1 | shrnutí produktu, fakta k vizi | PM: approve s body do vize (q-facts, q-vision-facts) |
| 1v | 5 sloganů jako karty | „Méně rutiny. Prototyp za pár dní." (q-slogan, spojuje dosavadní motto s novým) |
| 1i | 3 symboly s náhledy 16/32/180 px na světlém i tmavém | N jedním tahem s tečkou (q-logo); balíček + ikony `--verify` OK |
| 1s | 7 stránek s nadpisy a hledáním | schváleno (q-seo) |
| 2 | náčrty 8 stránek v galerii | schváleno (q-structure) |
| 3 | texty 8 stránek v galerii; portrét | schváleno (q-content); portrét odložen (q-portrait, `deferred_by_pm`) |
| 4 | 12 kandidátů, 6 vyřazeno, 6 karet | 37signals (q-refs) |
| 5 | 3 směry jako skutečné stránky (1440 + 390) | Zásady (q-direction) |
| 6 | - | build `site/` generátorem z `copy.json` |
| 7 | 7 stránek ke schválení, design standard, převzetí 14 kapitol | vše schváleno (q-page2-0..6, q-design-standard2, q-adopt-*) |

**Brána (poslední běh, build 0676bfb8):** 756 řádků: pass 735, warn 21, fail 0. Varování = jen
Lighthouse „osvědčené postupy" 79, protože náhled běží přes HTTP na adrese VPN (na 127.0.0.1 je 100).
Cestou brána chytila: znak „→" mimo písmo (FB-2) a po doplnění kontrol FB-21..24 nic dalšího.
SEO kontrola se zadáním: 90 OK, 0 varování.

**Soulad se standardy:** 293 položek: ověřil skript 42, ověřil agent 86, rozhodl PM 28,
nepoužito 120, neověřeno 17 (8 podmíněných výjimek nepotřeba, Lighthouse, a 8 skutečných mezer:
sestava loga s názvem, obrazové vyhledání podobných značek, úplnost vůči kontextům použití,
mapa úloh kontaktního formuláře, validátor strukturovaných dat, zápis do přehledu vizí,
výsledek brány ve studiu). `finish` prošel 28. 9. 2026.

**Opravy nástroje z pilotu (ve větvi):** brand stránka ve vzhledu studia a jako jeho záložka;
pravidla psaní vize, sloganů a textů v kroku 1v; agent čeká na odpověď sám (PM nepíše do chatu);
galerie pro schválení struktury a obsahu; adresa místo názvu souboru; kontroly FB-21..24;
design standard před schvalováním stránek.

**Výjimky udělené PM:** žádné.

**Otevřené před spuštěním:** portrét, souhlasy klientů s ukázkami, ověřit 4 údaje doplněné agentem
(odpověď do 2 pracovních dnů, návštěva ve firmě, uchování zpráv 12 měsíců), obrazové vyhledání
podobných značek, sestava loga s názvem pro e-mail a PDF.

**Verdikt:** technicky PASS (brána, schválení, `finish`); produktový verdikt PM čeká.

## Objednávky (webová aplikace)

Projekt: `.aid-o/work/P103-pilot/objednavky`, vymyšlený klient Truhlárna Dub (značka z P102), ukázková data
označená v aplikaci i v README. Varianta: aplikace s přihlášením, existující značka, vize/logo/SEO vynechané
(interní nástroj). Všechna rozhodnutí udělal agent z pověření PM („vše vyber ty", 28. 9. 2026) kliknutím ve studiu.

| Krok | Na studiu | Rozhodnutí |
|---|---|---|
| 0 | co stavíme, co připravit | aplikace s přihlášením, existující značka; vize, logo, SEO vynechány s důvodem (q-variant, q-options) |
| 1 | shrnutí produktu | schváleno (q-product) |
| 2 | 5 náčrtů obrazovek + 3 úlohy × 7 stavů v galerii | schváleno (q-structure, q-taskmap) |
| 3 | texty obrazovek a hlášek, 6 ukázkových zakázek | schváleno (q-content) |
| 4 | 12 kandidátů (Google Play + nástroje), Jobber blokován (403, neobcházeno), 6 karet | Things (q-refs) |
| 5 | 3 směry hlavní obrazovky | Týden (q-direction) |
| 6 | - | statické obrazovky + app.js, data v prohlížeči, přepínač stavů `?sim=` |
| 7 | 2 výjimky, design standard s mapou úloh, 4 obrazovky, 14 kapitol | vše schváleno (q-ex-seo2, q-ex-biz2, q-design-standard, q-page2-0..3, q-adopt-*) |

**Brána (poslední běh):** 4 716 řádků (4 obrazovky + 3 úlohy × 7 stavů × 2 role, × 3 šířky × 2 prohlížeče):
pass 4 152, warn 12 (Lighthouse), fail 552 = jen `seo` a `business_minimum`, obě pod výjimkou PM.
Scénáře `.aid-ui/scenarios/{seznam,nova,faze}.mjs` projdou každou úlohu ve všech stavech za obě role.
Cestou brána chytila: přetečení hlavičky vedoucího na 390 px, čas v hlášce o konceptu mimo registr faktů.

**Výjimky udělené PM:**
- `seo` (všechny obrazovky) - q-ex-seo2: „Interní aplikace za přihlášením; vyhledávače ji indexovat nemají (standard FB-14 pro interní nástroj)."
- `business_minimum` (všechny obrazovky) - q-ex-biz2: „Interní aplikace dílny, formuláře vyplňuje jen dílna, žádný sběr údajů od veřejnosti; klient je vymyšlený a IČO nemá."
(první dvojice q-ex-seo/q-ex-biz propadla změnou buildu, jak má.)

**Soulad se standardy:** 328 položek: ověřil skript 45, ověřil agent 69, rozhodl PM 20, výjimka PM 13,
nepoužito 177, neověřeno 4 (Lighthouse, obrazové vyhledání značky, úplnost balíčku, výsledek brány ve studiu).
`finish` prošel 28. 9. 2026.

**Chyby nástroje, které pilot našel a opravil (ve větvi):** `gate-record` bral stav úlohy zapsaný jako objekt
celý místo id (odmítal každý výsledek aplikace); brána hlásila jako rozbité písmo přerušené přesměrováním na přihlášení
a obrázek z mezipaměti jako neznámý typ; zpráva o souladu ukazovala položky s výjimkou jako „nesplněno" a nebrala
v úvahu části vynechané v kroku 0; studio ukazovalo technické názvy kontrol.

**Verdikt:** technicky PASS (brána s výjimkami, schválení, `finish`); produktový verdikt PM čeká.
