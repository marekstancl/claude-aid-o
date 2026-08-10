# UI Design-to-Code Fidelity — návrh a směr (Trať A)

**Datum:** 2026-06-21
**Revize:** 2026-06-21 — zapracován review nezávislého agenta + rozhodnutí Marka: Playwright
povinný (bez vlastního nástroje a fallbacku), MVP rozsah a patra ověření, `affected` množina,
determinismus, bezpečnost screenshotů, jediný zdroj pravdy.
**Autor:** Claude (na žádost Marka) — konsolidace z review Deep brainstormingu + nezávislého
agenta + rozhodnutí Marka
**Status:** **Plan-ready** směr a rozsah — základ pro executable AID plán.
**Souvislost:** Vyčleněno z [`AID-BRAINSTORM-deep-mode-review.md`](AID-BRAINSTORM-deep-mode-review.md)
§6 jako samostatný projekt. Deep brainstorming (Trať B) na tuhle trať závisí svou UI větví,
ne naopak.

> **Co tenhle dokument řeší:** dnes AI mock relativně dobře nakreslí, ale implementace
> z něj nedostane jednoznačnou informaci **co přesně změnit a co přesně nesmí změnit** — a
> navíc sama o sobě tvrdí, že „výsledek odpovídá", i když neodpovídá. To je aktuální, denní
> bolest. Tento dokument popisuje, jak ten řetězec **návrh UI → implementace UI → vizuální
> ověření** opravit spolehlivě a mechanicky.

---

## 0. Verdikt v jedné větě

Problém už není v kvalitě renderu, ale v **předání mocku implementátorovi a v ověření** — a
celý dnešní řetězec navíc stojí na tom, že baseline mock je **agentem překreslený ze čtení
kódu, ne odsnímaný z běžící stránky**, takže i kdyby implementace seděla s mockem, mock ≠
skutečná aplikace.

---

## MVP — rozsah, patra ověření a cíl (rozhodnuto)

**Buildovatelné MVP je jeden flow na jeden druh změny.** Šest bodů z review nezávislého
agenta jsou z větší části „rozhodnout/specifikovat", ne „postavit" — proto je MVP malé.

### Rozsah změn (in / out)

| In scope (MVP) | Out of scope (zatím static-mock cesta) |
|----------------|----------------------------------------|
| Vizuální delta na **existující komponentě**: styl, text, ikona, velikost, pozice, lokální layout | Strukturální redesign, nová komponenta, přestavba React stromu, komplexní interakce |
| Stabilní route + deterministický datový stav | Změny závislé na nestabilním/nereprodukovatelném stavu |

Důvod hranice: mechanika „proposed = živý DOM + delta" platí jen pro vizuální delty. U změny
DOM struktury framework okamžitě překreslí a manipulaci smaže — tam MVP nejde a jde se manuální
static-mock cestou.

### Patra ověření (kde se zastavit ve v1)

Flow je vždy stejný; liší se jen kolik z ověření je automatické:

| Patro | Co automatizuje | Efort | Stav |
|-------|-----------------|-------|------|
| **A** | nic — baseline z Playwrightu + kontrakt + zauzdřený implementátor, porovnání **okem** | S | průchozí stav, ne cíl |
| **B** | + **regression guard** na `locked` oblastech (collateral damage mechanicky); delta okem | M | **← cíl MVP** |
| **C** | + měření **uvnitř** delty (cross-viewport, in-mask intent) | L | koncový stav, ne MVP |

**Cíl MVP = patro B.** Nejmenší věc, co reálně uleví (auto-chytá nejzákeřnější fail —
collateral damage), ne jen přeorganizuje ruční práci. K Béčku se dojde přes Áčko (je to „B minus
guard"). C se staví až potom, samostatně.

---

## 1. Dvě nezávislé osy (ne tři uživatelské režimy)

Nebudujeme tři režimy, které by uživatel vybíral. Jsou tu **dvě nezávislé osy**:

| Osa | Varianty |
|-----|----------|
| Jak důkladně plánujeme | současný brainstorming / budoucí Deep (Trať B) |
| Obsahuje práce UI? | ano / ne |

**UI pravidla musí fungovat všude:** v `/aid-do`, v běžném plánu přes `/aid-run`, i jednou
v Deep brainstormingu. Jakmile úkol mění obrazovku, aktivuje se **stejný UI protokol** — je
jedno, jestli jde o čisté UI nebo o backend doplněný o UI.

`greenfield` / `redesign` / `existing_ui` **nejsou režimy, které vybíráš**. AID jen
automaticky pozná, zda existuje baseline, kterou musí zachovat:
- **existing_ui** — mění se existující obrazovka → tvrdý scoped-fidelity režim (jádro tohoto dokumentu).
- **redesign** — vědomá přestavba existující obrazovky → otevřené vizuální osy, ale stále s baseline kontextem.
- **greenfield** — nová obrazovka bez baseline → nesmí předstírat pixelovou shodu s neexistujícím stavem.

---

## 2. Proč to dnes nefunguje — ověřený audit

Ověřeno grepem v aktuálním checkoutu pluginu (2026-06-21):

| Vrstva | Co dnes existuje | Ověřená mezera |
|--------|------------------|----------------|
| Visual Companion (existing UI) | [`visual-companion/SKILL.md:88`](../../plugins/aid-orchestrator/skills/visual-companion/SKILL.md#L88): agent přečte kód a stránku **„render as it currently looks"** — překreslí HTML; rozměry „z kódu" (ř. 83, 342) | **Baseline mock je aproximace z překreslení, ne snímek běžící stránky.** Reálný vzhled vzniká z kaskády + design tokenů + komponentové knihovny — to čtením zdroje spolehlivě nezrekonstruuješ |
| Frontend implementátor | [`implementer.md`](../../plugins/aid-orchestrator/agents/implementer.md) je obecný — slovo „frontend" **neobsahuje vůbec**; frontend kartu bere z [`role-cards.md:136`](../../plugins/aid-orchestrator/skills/role-cards.md#L136) (Visual Anchoring) | Visual Anchoring tahá layout/barvy/typografii **z `visual-spec.yaml`** — který **nikdo negeneruje** (žádný `.sh` generátor/validátor). Implementátor kotví na neexistujícím artefaktu |
| Schéma mocků | `brainstorming.md` + `plan-writing.md` používají `source_type: companion` | [`plan.schema.json:237`](../../plugins/aid-orchestrator/defaults/templates/plan.schema.json#L237) enum = `["github","ai_studio","image"]` — **`companion` tam není** |
| Enforcement | FSM kontroluje přítomnost nadpisu `## Visual Anchoring`; pipeline dělá screenshot + semantické srovnání | Kontroluje **existenci nadpisu, ne věrnost**; `PARTIAL` může projít; nedostupný dev server dovolí vizuální kontrolu přeskočit (warn + skip) |
| `/aid-do` | Implementuje přímo, **bez FSM, role cards a `visual_refs`** | Nejčastější malé UI zásahy obchází celou vizuální pipeline — pouhá úprava `implementer.md`/pipeline/schématu je tedy neopraví |

**Důsledek:** „AI tvrdí, že to sedí" je problém na **dvou patrech** — implementace vs. mock,
a mock vs. realita. Opravit se musí obojí, jinak jen přesuneš lež o úroveň výš.

`frontend-design` je navíc **externě instalovaný skill, ne součást implementátorova kontraktu**
(v celém pluginu zmíněn jen jednou — [`brainstorming.md:111`](../../plugins/aid-orchestrator/skills/brainstorming.md#L111) jako fallback nabídka). Implementátorovi se **nedává a dávat nemá** — jeho
instrukce podporují kreativní redesign, implementátor potřebuje opačný režim: přesnost a zákaz
improvizace.

---

## 3. Krux: baseline musí vzniknout z běžící stránky

**Bez tohohle nemá smysl nic dalšího.** Pro `existing_ui` nesmí baseline (ani „proposed")
vznikat překreslením HTML ze čtení kódu. Musí vzniknout z **reálně vykreslené stránky**:

1. **Playwright** (povinný základ každého projektu — viz níže) **najede na cílový route/story**
   v reálné aplikaci.
2. Pořídí **baseline screenshot** + extrahuje **computed styles + geometrii** cílových prvků
   z živého DOM (ne hodnoty vyčtené ze zdroje).
3. „Proposed" = ten **reálný baseline s aplikovanou jen deltou** — DOM manipulací nad živou
   stránkou (platí pro vizuální delty v MVP rozsahu), ne čerstvě nakresleným HTML.

Teprve takový mock je **měřitelný** proti implementaci. Překreslený mock je měření proti
aproximaci a reprodukuje původní problém.

> **Playwright — rozhodnutí (Marek):** Playwright je **povinný základ každého projektu**, kde
> dává smysl. **Nezavádí se vlastní `aid-ui-capture` nástroj** ani se nepřidává browser
> automation do Companion node serveru — capture jsou přímá Playwright volání ve **verify
> kroku pipeline** (logicky oddělená vrstva, ne nový nástroj). Companion server zůstává jen
> prezentační (`express`/`ws`/`chokidar`). **Žádný fallback „když capture není"** — capture se
> předpokládá; jeho nedostupnost je BLOCKED, ne tichý skip.

---

## 4. Scoped fidelity — tvrdé 1:1 je na tom, co NEMĚNÍŠ

Plošné pixel-perfect celé stránky není cíl. Cíl je **scoped fidelity** nad **třemi množinami**
(ne dvěma — `affected` je nutná, jinak guard falešně padá na legitimním reflow):

- **`delta`** — přímo měněné prvky a vlastnosti. Odpovídají popisu delty a záměru mocku; mock je
  sám přibližný, autoritu na přesné hodnoty má **měřený text-delta**.
- **`affected`** — prvky, které se **legitimně posunou jako důsledek** delty (rozšíříš badge →
  sousední obsah se odsune). Nejsou přímo měněné, ale **nejdou pixelově zamknout**. Deklarují se
  jako **povolení/region** („tenhle sloupec se smí posunout horizontálně"), ne přesné pixely —
  skutečná hodnota se **změří při verify**. Kontrola: *pohnulo se jen jako důsledek delty, nic mimo*.
- **`locked`** — vše ostatní. **Tvrdé 1:1**, nulová regrese. To je nejzákeřnější fail (collateral damage).

> Pozor na inverzi: **nejpřísnější je `locked`** (nulový diff), volnější je `delta` (sedí
> s mockem v rámci tolerance). `affected` je třetí, samostatný typ kontroly mezi nimi.

| Prvek | Množina | Požadavek |
|-------|---------|-----------|
| Status badge | `delta` | barvu/šířku/text: zelená `#198754`, 84 px, „Zpracováno" |
| Sousední buňka v řádku | `affected` | smí se posunout horizontálně o šířku delty, nic víc |
| Výška řádku, sloupce, hover | `locked` | beze změny (tvrdé 1:1) |
| Toolbar mimo tlačítko | `locked` | beze změny |

---

## 5. Priorita zdrojů — text a mock mají různé role

Textový popis je **stejně důležitý jako mock** (Markův explicitní požadavek), a má to tvrdý
důvod: **text je přenositelný napříč rendering kontexty, screenshot z companion prostředí ne.**

| Zdroj | Autorita pro |
|-------|--------------|
| **Textový change list** | **co** je ve scope (delta) |
| **Mock screenshot** | **jak** to má vypadat — gestalt, layout, záměr |
| **HTML/CSS + computed styles** | **přesné hodnoty** (px, hex, spacing) |
| **Současná implementace** | **vše, co se nemění** |

**Rozpor text × mock → implementátor nehádá.** Musí se vyřešit **před** implementací (blokuje).

---

## 6. Povinné artefakty UI Change Contractu

Pro každý zásah do existující obrazovky vzniká — **automaticky, bez dotazu PM, zda smí číst
kód** (jen když cíl nelze jednoznačně najít, padne jedna blokující otázka):

1. **Baseline screenshot** — skutečné UI před změnou (z běžící stránky, viz §3).
2. **Mock screenshot** — zmrazený schválený návrh ve **stejném viewportu**, odvozený z reálného
   baseline + delta.
3. **Textový change list** — přesná autoritativní delta (selektor/komponenta, before, after,
   důvod, změnitelné vlastnosti, chování ve stavech hover/focus/loading/empty/error).
4. **`affected` manifest** — prvky s povoleným následným reflow + jeho mez (region/směr).
5. **LOCKED manifest** — vše mimo deltu a affected je neměnné; explicitně zamknout rozměry,
   pozici, spacing, typografii, barvy, ikony, border/radius, obsah, interakce, responsive chování
   (dle relevance prvku).
6. **Finální screenshot** — skutečná implementace po změně.
7. **Porovnání** — `locked` proti baseline (regrese), `affected` v mezích povolení, `delta`
   proti referenci (věrnost změny).

### Jediný zdroj pravdy

`ui-change-contract.yaml` je pro `existing_ui` **jediný autoritativní kontrakt.** Screenshots
a `computed.json` jsou **jen reference**, ne zdroj pravdy. `visual-spec.yaml` se pro
`existing_ui` **nepoužívá** (ui-change-contract ho nahrazuje) — drží se jen pro `greenfield`,
kde baseline neexistuje. Dva paralelní kontrakty pro stejné UI = drift, proto se vylučují.

Durable artefakt `ui-change-contract.yaml`, minimální tvar:

```yaml
mode: existing_ui            # greenfield | redesign | existing_ui
fidelity: exact              # exact (existing_ui) | guided (redesign/greenfield)
reference_commit: <sha>
viewports: [{name: desktop, width: 1280, height: 720}]
baseline:
  route: /target
  screenshot: baseline.png
  state_fixture: invoices-3-rows      # deterministický fixture, ne prod data (viz Bezpečnost)
  computed: baseline-computed.json    # computed styles z živého DOM, ne ze zdroje
implementation_reference: proposed-desktop.png
delta:
  - target: InvoiceTable > StatusBadge
    allowed_properties: [width, background-color, text]
    before: {width: 72px, background-color: "#6c757d", text: "Čeká"}
    after:  {width: 84px, background-color: "#198754", text: "Zpracováno"}
affected:
  - target: InvoiceTable > Row > Cell:next
    allow: {shift: horizontal, max_px: 12}   # smí se posunout jen o důsledek delty
locked:
  - target: InvoiceTable > Row
    properties: [height, padding, columns, hover, typography]
```

Schéma musí rozlišit `greenfield` / `redesign` / `existing_ui`. Tvrdý 1:1 (`fidelity: exact`)
se aktivuje pro `existing_ui`; `greenfield` nesmí předstírat shodu s neexistující baseline.

### Bezpečnost a uložení artefaktů

Screenshot reálné aplikace může obsahovat **osobní/produkční data** (u ACTA: faktury, IČO,
jména dodavatelů — navíc eco má GDPR guardrails). Proto:

- **Capture jen nad fixture/test daty**, ne nad produkcí (`state_fixture` je povinný pro `existing_ui`).
- Artefakty (screenshoty, `computed.json`) žijí v **run namespace** `.aid-o/work/.../ui/` a jsou
  **gitignored** by default.
- Do versioned plánu se promuje **jen `ui-change-contract.yaml`** (kontrakt s hodnotami), ne syrové
  screenshoty — pokud PM výslovně nepovolí konkrétní obrázek.
- Pro nevyhnutelně citlivé oblasti **redakce** (maskování) před uložením.

---

## 7. Role v cílovém flow

| Část | Úloha |
|------|-------|
| **`frontend-design`** | Navrhne vzhled **jen tam, kde je skutečně otevřený** (open vizuální osy). Nikdy nepřepisuje LOCKED baseline. Volitelný vstup po capability detection — správnost handoffu na něm nesmí záviset |
| **Visual Companion** | Ukáže návrh **v kontextu** současného UI (1:1 baseline + delta), získá schválení. Vyrobí decision-sheet i implementation-reference |
| **UI change brief** | Přesně předá, co se mění a co je zamčené (text change list + LOCKED) |
| **Frontend implementátor** | Implementuje **bez vlastní kreativity** — jen povolenou deltu, nedoplňuje chybějící detaily, neredesignuje |
| **Visual verifier** | **Mechanicky** porovná výsledek: oblast změny proti reference, zbytek proti baseline |

**LLM self-report je mimo trust path.** Existenci diffu rozhoduje **deterministické měření**
(geometrie, computed styles, obrazový diff). LLM smí jen **vysvětlit reziduální** sémantický
rozdíl, nikdy rozhodnout, **zda vůbec existuje**.

---

## 8. Mechanická kontrola — rozseknout na poloviny (a postavit determinismus první)

Poloviny kontroly jsou **drasticky jinak těžké**; nestavět najednou (mapuje na patra A/B/C):

- **(a) regression guard — `locked` mimo change mask == 0** (v rámci tolerance). *Snazší než
  in-mask intent*, **postav v MVP (patro B).** Chytá nejhorší fail (collateral damage).
- **(a') `affected` v mezích** — pohnulo se jen jako důsledek delty, do deklarovaného `max_px`/směru.
- **(b) in-mask intent — „změna odpovídá referenci"** — cross-viewport, mock je sám přibližný.
  **Těžké → patro C.** Zatím schvaluje **člověk** (PM potvrdí change region).

Pravidla tvrdého režimu (`fidelity: exact`, jen `existing_ui`):
- `locked` proti baseline **nulový** diff v rámci tolerance;
- `affected` pouze v deklarovaných mezích;
- `delta` proti `implementation_reference`;
- **`PARTIAL` není PASS**;
- nemožnost spustit UI nebo pořídit screenshot = **BLOCKED/ESCALATION**, ne `warn + skip`;
- kontrola běží ve **všech kontraktem uvedených viewportech** a relevantních stavech, ne fixně 1280×720.

### 8.1 Determinismus je prerekvizita, ne freebie

Pixel diff mimo masku **není automaticky „snadný"** — bez deterministického prostředí padá
náhodně. `state_fixture` a render-determinismus jsou **součást stavby guardu**, ne samozřejmost:

- stabilní data + autentizace (fixture, ne prod);
- vypnuté animace/transitions;
- fixní fonty, čas, locale, viewport;
- skryté kurzory, scrollbary, dynamické timestampy;
- stejný browser/OS rendering (jeden Playwright runtime);
- kalibrovaná tolerance (font antialiasing, subpixel).

Tohle nesmí zůstat jen v promptu — patří sem **deterministický capture/compare** (přímá
Playwright volání), validace `ui-change-contract.yaml` a regresní testy FSM.

---

## 9. Worked examples

### Backend + UI (badge v existující tabulce)
Požadavek: přidat backendový stav faktury a zobrazit ho jako badge v existující tabulce.
1. AID načte backendový model, API a současnou tabulku (z běžící stránky — §3).
2. Definuje nový stav + jeho API reprezentaci (backend kontrakt, oddělený).
3. Visual Companion zobrazí současnou tabulku **1:1**, pouze s navrženým badge.
4. PM schválí variantu badge — **neřeší znovu celou stránku**.
5. Implementátor dostane: změnit badge + datové napojení; zachovat výšku řádku, sloupce,
   typografii, spacing, ostatní barvy; konkrétní referenční mock.
6. Po implementaci: oblast badge proti schválenému návrhu; zbytek tabulky proti baseline.

**Backend a UI mohou být jeden úkol — jen musí mít oddělené kontrakty a ověření.**

### Čisté UI (rozložení tlačítek)
Stejné flow, odpadne backendová část:
`načíst současné UI → navrhnout deltu → schválit → implementovat → vizuálně porovnat`.

---

## 10. `/aid-do` — necentrovat, ale počítat s ním

Marek `/aid-do` používá **sporadicky**, takže ho **nestavíme do centra**. Navíc dnes obchází
plán, frontend kartu i vizuální pipeline, takže pro přesnou UI práci je teď spíš **horší volba**.

Smysl dostane **až později** pro malou, **už přesně navrženou** změnu:
> „Tady je schválený mock, screenshot a popis delty. Pouze to implementuj."

Pro UI vyžadující návrh nebo rozhodování dál použít normální flow s Visual Companion.

**Proporcionalita:** na jeden badge uvnitř backend úkolu může být interaktivní node-server
companion zbytečně těžký. Zvážit: companion na **genuine vizuální rozhodnutí**, statický
decision-sheet render na „schval tenhle jeden prvek". Nástroj má odpovídat velikosti delty.

---

## 11. Pořadí prací (cíl MVP = patro B)

Pořadí rozhodování (body z review nejsou stejně těžké):
1. **MVP scope** (rozhodnuto) — vizuální delta na existující komponentě; strukturální redesign mimo.
2. **Capture + determinismus** — jeden foundational kus (§3 + §8.1): Playwright baseline +
   `state_fixture` + render-determinismus. *Bez tohohle nemá smysl nic dalšího.*
3. **Kontrakt** — `ui-change-contract.yaml` s `delta`/`affected`/`locked`, jediný zdroj pravdy (§6).

Stavební pořadí:
1. **Patro A** — Playwright baseline + computed + kontrakt + zauzdřený implementátor; porovnání
   okem. Ověřit tvar kontraktu na **2–3 reálných nepovedených UI implementacích**.
2. **Patro B (cíl MVP)** — přidat **regression guard** na `locked` + `affected` v mezích +
   determinismus harness (§8, §8.1).
3. **`companion` do `source_type` enumu** + validátor `ui-change-contract.yaml` (§2, §6).
4. **Patro C** (post-MVP) — in-mask měření, cross-viewport (§8b).

---

## 12. Minimální změnová plocha v AIDu

- [`skills/visual-companion/SKILL.md`](../../plugins/aid-orchestrator/skills/visual-companion/SKILL.md) — baseline z běžící stránky, automatický read-first, baseline/delta/LOCKED protokol, dva výstupy (decision-sheet + implementation-reference).
- [`skills/brainstorming.md`](../../plugins/aid-orchestrator/skills/brainstorming.md) — UI klasifikace a předání contractu bez dalšího PM kola.
- [`skills/plan-writing.md`](../../plugins/aid-orchestrator/skills/plan-writing.md) — povinná UI Change Contract sekce a per-step traceability.
- [`skills/role-cards.md`](../../plugins/aid-orchestrator/skills/role-cards.md) + [`skills/agent-protocol.md`](../../plugins/aid-orchestrator/skills/agent-protocol.md) — implementátorova delta/LOCKED pravidla; zákaz redesignu.
- [`agents/implementer.md`](../../plugins/aid-orchestrator/agents/implementer.md) — frontend krok dostane UI change brief, ne obecné Visual Anchoring.
- [`skills/pipeline.md`](../../plugins/aid-orchestrator/skills/pipeline.md), FSM, šablony a [`plan.schema.json`](../../plugins/aid-orchestrator/defaults/templates/plan.schema.json) — `companion` enum, hard gate pro úplný contract a exact-fidelity verification.
- **`/aid-do`** — pro vizuální změnu napojit na společný UI protokol (později).
- **Testy:** schema `companion`, neúplný contract, collateral UI change, chybějící screenshot,
  exact mismatch, více viewportů, úspěšná scoped 1:1 implementace.

---

## 13. Otevřené body

- **Tolerance** regression guardu (font antialiasing, subpixel) — kalibrovat na reálných screenshotech.
- **`state_fixture` mechanika** — jak deterministicky dostat cílovou obrazovku do porovnatelného
  stavu napříč stacky (seed dat, route + mock API, story).
- **Compare knihovna** — pixelmatch vs. Playwright `toHaveScreenshot` (vestavěná tolerance/maskování).
- **`affected` mez** — jak deklarovat povolený reflow přenositelně (px vs. relativně k deltě).
- **Cross-component delty** — když změna zasáhne víc komponent najednou (sdílený design token).
- **Spuštění cílové app** — jak verify krok nastartuje aplikaci do testovatelného stavu (dev server, story).

---

*Tato trať je samostatně shippovatelná a má přednost před Deep brainstormingem (Markovo
rozhodnutí: UI bolí dnes, oprava poslouží i Deep režimu). Deep UI větev se povolí až po
napojení na tuto trať.*
