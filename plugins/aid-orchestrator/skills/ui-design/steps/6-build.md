---
name: ui-design-step-6
description: /aid-ui step 6 - build from the chosen direction, structure and content plan into the project's site folder per the frontend-design snapshot and the standards, then build-record
user_invocable: false
---

# Krok 6 - Stavba

**Vrstva dílny (P113):** stavba doplňuje živou kostru v `site/` (`aid-ui-serve.sh skeleton`), nezačíná z prázdné složky; pohyb značky zapoj podle `references/local/pohyb-znacky.md` (na webu ≤ 1 s, jméno hned). `build-record` vyžaduje verdikt místa `pohyb` (nebo výjimku PM bez pohybu). Místo: `pohyb`. Kolo místa: `aid-ui-quality.py round <projekt> --place pohyb`.

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

Nejdřív `aid-ui-state.sh context-check <project>`; neprojde → zpět na krok 1p (`steps/1p-sources.md`).

**Postup před stavbou (P108, 10. 10. 2026; pilot Coufal: stavba psaná z hlavy = 6/10).**
`aid-ui-state.sh method <project> build` vypíše převzatý postup (frontend-design, převzatý
craft floor, tento krok, živý frontend-build standard) a zapíše stvrzenku; `build-record` bez
stvrzenky z posledních 12 h odmítne. Stavba nese pohyb vybraného směru beze změn: tytéž
keyframes a přechody, které soupis `.aid-ui/motion.json` jmenuje (krok 5 bod 4m), včetně pohybu
pod úvodem, při najetí myší a mezi stránkami. Úvodní overlay (je-li) má atribut `data-aid-intro`
a skončí do 10 s - brána měří a fotí až po doběhnutí animací (řádek `motion_settled`), takže
vyplutí přes `opacity` je v pořádku; nikdy pohyb neosekávej kvůli bráně, oprav bránu. Četnost
úvodu podle soupisu (`every_load` jako vzor, `first_load_only` jen s důvodem, který PM viděl).

1. Postav každou stránku ze `structure` (u aplikace každý tok se všemi jeho
   stavy) podle snímku frontend-design a standardů. Texty jen z obsahového
   plánu a registru faktů, psané podle „Jak psát vizi, slogany a texty"
   (`steps/1v-vision.md`): postup `references/adopted/marketingskills/copywriting/SKILL.md`,
   stavba textu podle `references/adopted/marketingskills/copywriting/references/copy-frameworks.md`,
   přechody mezi sekcemi podle `references/adopted/marketingskills/copywriting/references/natural-transitions.md`.
   Před bránou každou stránku projdi podle `references/adopted/marketingskills/copywriting/references/ai-tells.md`
   a `references/copy-<jazyk>.md` (oddíl Fráze prozrazující AI text) a nálezy oprav. Jazyk bez
   příručky: `copy-rules.md` a převzatá anglická pravidla; kontrola textů ho pustí jen s výjimkou PM.
   Položka `deferred_by_pm` dostane viditelně prázdné místo podle standardu, nikdy zástupný text.
2. Výstup: `<project>/site/`, nebo vlastní složka buildu projektu (Next.js
   `out/`, Astro `dist/`) - mimo `docs/` a `.aid-ui/`.
3. SEO: title, meta description, H1 a strukturovaná data z `docs/seo/brief.md`
   (H1 přesně podle tabulky). Každá indexovatelná stránka má JSON-LD: typ stránky
   (`WebPage`, `AboutPage`, `ContactPage`…) s `publisher` = organizace a `dateModified`;
   organizace (název = `brand` z faktů, IČO v `identifier`, ne v `taxID`, to je DIČ; ulice
   jen u místní firmy) stejně na všech stránkách. Stránka se službami nese `Service` pro každou službu
   (`provider` = organizace, `areaServed` z faktů o spádové oblasti, `url` sekce nebo stránky služby), stránka
   jedné služby svůj `Service`; každá vnořená stránka `BreadcrumbList` podle navigace (P113a, technik Coufal 13. 10.;
   chybějící drobečky hlásí `aid-ui-seo-check.py` jako WARN `breadcrumbs`). `robots.txt`: vlastní skupina
   `User-agent` pro každého robota z `coverage/ai-crawlers.json` podle „Politika AI robotů"
   v briefu (`Allow: /` nebo `Disallow: /`), vyhledávače povolené; `llms.txt` jen při
   `llms.txt: ano`. Kontroluje `aid-ui-seo-check.py --ai` (řádek brány `ai_search`).
   Brief nemá oddíl „Politika AI robotů" → stavba AI pravidla nepíše a vrací se do kroku
   1s k otázce PM; oddíl nikdy nedopisuj sám.
4. Obrázky: `aid-ui-tool.sh webp <src> <out.webp> <šířka> [kvalita]` pro
   každý obrázek; limit 200 kB hlídá nástroj (exit 1 → menší šířka nebo
   kvalita).
3a. **Řemeslo podle převzatých dovedností (P113a, PM 13. 10. 2026; stvrzenka postupu stavby je vyžaduje):**
   pohyb stav podle `emil-skills/animate` (smí se to hýbat, účel, vlastnosti, křivka, délka, přerušení) a jeho
   receptů; před `build-record` projdi vlastní pohyb podle `review-animations` (standardy, verdikt);
   mobilní chování podle `mobile-native` (hover jen pro myš, `100dvh`, pole aspoň 16 px, výřez displeje);
   formuláře a texty z dat vyzkoušej nejhoršími daty podle `break-ui` (dlouhá jména, prázdná pole, extrémní
   čísla). Při rozporu platí design systém a brána (`reduced_motion`). Brána `mobile_native` (FB-33) měří hover jen
   pro myš (`@media (hover: hover)`), povolené přiblížení a písmo polí aspoň 16 px.
3b. **Dělicí čáry (FB-31):** svislá čára mezi sloupci nebo bloky dostane vnitřní odstup aspoň 16 px na obou
   stranách (padding u sloupce před čarou i za ní, nebo `gap` místo okraje). Text nikdy nezačíná těsně u čáry.
   Brána `text_clearance` to měří na každé stránce a šířce.
3d. **Výchozí součásti typu:** web lokální služby postaví součásti ze seznamu `components` v
   `critic/web-local.yaml` (volat z mobilní hlavičky, trasa z každé stránky, ceník a služby propojené,
   hodiny v patičce), pokud je `DESIGN.md` projektu výslovně nevylučuje s důvodem.
3c. **Základy přístupnosti (FB-32):** první prvek stránky s navigací je odkaz „Přeskočit na obsah“ (`#main`,
   vidět při zaměření); nadpisy jdou h1 > h2 > h3 bez skoku (skrytý h2 nad blokem s h3, když blok nemá
   vlastní); obrys zaměření v barvě s kontrastem aspoň 3:1 proti pozadí, na světlém i tmavém (dvoubarevný
   prstenec); při 320 px (přiblížení 400 %) nic nepřetéká do strany (logo, tabulky, dlouhá slova). Brána `a11y_basics`.
4a. **Fotka, kterou klient dodá později (FB-30, PM 1A):** žádná cizí fotka a žádný text „sem přijde
   fotka“. Místo ní rámeček z `docs/content/photos.yaml` (id, stránka, tvar, poměr):
   `<div class="aid-photo" data-aid-photo="<id>" aria-hidden="true"><svg data-aid-icon="camera" …ikona fotoaparátu…></svg></div>`
   se stylem `position:relative; overflow:hidden; aspect-ratio:<w>/<h>` (u `round` navíc
   `border-radius:50%`) a pozadím z tokenu. Ikona fotoaparátu nese `data-aid-icon="camera"`, bez ní brána rámeček nepozná. Dodaná fotka se jen vloží:
   `<img src=… alt="<co je na ní>" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">`
   a `aria-hidden` se z rámečku odebere. Brána `photo_slots` to zkouší vložením zkušební fotky.
   Má-li místo v `photos.yaml` `src` (klient vybral fotku, krok 3 bod 2c), stavba ji vloží s `alt` z `photos.yaml`
   a se `srcset` (`src_800` 800w, `src` 1600w) a `sizes`;
   brána prázdné místo s `src` hlásí jako selhání.
5. Písma: build servíruj lokálně jen na 127.0.0.1 - volný port
   `port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')`,
   `python3 -m http.server --bind 127.0.0.1 --directory <složka buildu> "$port" &`
   (zapamatuj `pid=$!`), `aid-ui-tool.sh glyph http://127.0.0.1:$port/<stránka>`
   pro každou stránku, pak `kill "$pid"`; exit 1 → oprav písmo.
5b. Co brána měří na každé stránce (stav to rovnou, ne až po bráně): barvy a písma jen
   z tokenů `DESIGN.md` (`token_usage`); ovládací prvky na mobilu aspoň 44 × 44 px včetně
   loga v hlavičce a odkazů menu (`touch_targets`); viditelný fokus u každého prvku, past
   na roboty s `tabindex="-1"` (`keyboard`); žádný pohyb při `prefers-reduced-motion`
   (`reduced_motion`); přilepený panel s přetékajícím obsahem má vlastní scroll a
   `overscroll-behavior: contain` (`sticky_panels`); před souhlasem žádný cizí požadavek
   ani cookie, písma a obrázky z vlastní domény (`privacy_before_consent`); PWA: fixní
   panely u okraje s `env(safe-area-inset-*)` (`safe_area`).
6. Česká typografie v generátoru (šablona nebo skript, který HTML píše):
   nezlomitelná mezera po jednopísmenných předložkách a spojkách
   (k s v z o u a i, i velká), jen v textu mimo značky:
   ```python
   def nbsp(html):
       fix = lambda m: re.sub(r'(?<=[\s>(])([ksvzouaiKSVZOUAI]) ', r'\1&nbsp;', m.group(0))
       return re.sub(r'>[^<]+<', fix, html)
   ```
7. Logo s názvem (když ho balíček značky ještě nemá, krok 1i): po výběru vzhledu je
   písmo dané, vyrob ho teď `aid-ui-tool.sh wordmark --spec .aid-ui/wordmark.json`
   a PNG `aid-ui-tool.sh png` podle kroku 1i; doplň ho do kapitoly `logo`
   (`aid-ui-state.sh body`), jinak řádek `brand_package` v bráně selže.
   Tokeny a brand stránka: `DESIGN.md` projektu podle postaveného vzhledu,
   `aid-ui-design-to-css.sh DESIGN.md docs/brand/tokens.css`, písma
   `aid-ui-state.sh fonts <project> <URL Google Fonts nebo docs/brand/fonts/*.css>`,
   role `aid-ui-state.sh roles <project> bg=<c>,ink=<c>,accent=<c>,display=<t>,body=<t>`.
8. Pozorování pohybu stavby (před zápisem buildu):
   `aid-ui-tool.sh motion --dir <složka buildu> <project>/.aid-ui/build.motion.json`
   **FB-27 (12. 10. 2026, retro klienta Coufal: „prázdné stránky“):** skryté výchozí stavy pohybu
   (`opacity:0`, posun, ořez) piš jen pod `html.js` (`<script>document.documentElement.className+=" js"</script>`
   v `<head>`), pozorovatel odhalení se spouští hned po načtení s prahem 0 (i sekce, která do výřezu zasahuje kouskem, se odhalí bez kolečka - Coufal 12. 10.: práh 0,15 nechal zesláblé tabulky cenníku),
   při `prefers-reduced-motion` je vše čitelné hned. Brána to hlídá řádky `content_without_js` (bez skriptu
   stejné obsahové texty) a `first_paint_visible` (h1 a první blok čitelné hned po načtení, nic zesláblé);
   oba blokují.
   **Hlavní obraz první obrazovky** (největší fotka nad ohybem) nemá výchozí `opacity:0` ani zpoždění: zobrazí se
   hned, jinak se odkládá jeho vykreslení (LCP; technik Coufal 13. 10.: výkon 87). Pohyb vzoru, který na něm byl,
   přesuň na doprovodný prvek (text, štítek); kontrola pohybu stavby hlídá jen, že pohyb vzoru běží.
   **FB-28 formulář:** nikdy `action="mailto:"`; odeslání skriptem na koncový bod z `DESIGN.md`, tlačítko
   zamčené během odesílání, stav v `role="status"`, chyba s klikacím telefonem/e-mailem, úspěch se nepředstírá.
   Dokud koncový bod na hostingu neběží: `aid-ui-state.sh open-item <project> add --text "Koncový bod formuláře"
   --owner agent --critical --evidence "odeslání doručí zprávu"`. Brána: `form_states`.
   **Příjemce v náhledu (P113a):** `.aid-ui/form.json` `{"endpoint": "/api/…", "required": [pole…], "honeypot":
   "<skryté pole proti spamu>", "max_field": 2000}`; náhled (`aid-ui-serve.sh preview`) pak zprávy přijímá do
   `.aid-ui/inbox/` (jen vlastník, do logu nic z obsahu). Formulář má skryté pole proti spamu se stejným jménem.
   Brána `form_delivery` formulář skutečně vyplní a odešle a ověří doručení, odmítnutí neúplné zprávy, zahození
   spamu (i přes skutečný formulář) a jedno doručení při dvojím kliknutí. Příjemce na hostingu klienta se ověří až
   po nasazení; do té doby je to kritický otevřený bod (viz výše).
   (nástroj build servíruje sám a otisk složky zapíše sám);
   `build-record` pak sám pustí `aid-ui-motion.py check` nad tím záznamem a odmítne, když
   kterýkoli převzatý pohyb v buildu neběžel (vyjmenuje je) nebo build od pozorování změnil.
   `aid-ui-state.sh build-record <project> <složka buildu>`, hned potom
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
