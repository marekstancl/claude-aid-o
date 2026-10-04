---
name: ui-design
description: Steps of /aid-ui - variant, product (vision, logo, SEO), structure, content plan, references, three directions as real pages, build and verification, every PM choice on the studio page
user_invocable: false
---

# ui-design

**Last Updated:** 2026-09-28

Vede PM od varianty produktu přes produkt, strukturu, obsahový plán, vzory
a tři směry jako skutečné stránky až k postavenému a ověřenému webu nebo
aplikaci; výsledky skládá do brand stránky projektu (`<project>/docs/brand/`).
Každou volbu a každé schválení dělá PM na stránce studia; bez zaznamenané
odpovědi se nic nerozhodne (vynucuje `aid-ui-state.sh`, ne jen tento text).

---

## When to Invoke

- `/aid-ui [step]` (`commands/aid-ui.md`) - jediný vstup.

Do NOT invoke for:

- běhy AIDu (`/aid-run`, `/aid-plan`, `/aid-do`) - skill se do nich nezapojuje;
- backend, hosting, 3D, video.

---

## Hranice

- Nezapojuje se do běhů AIDu; nic sám veřejně nevystavuje ani neposílá.
- Neobchází blokace galerií; cizí screenshoty nejdou do gitu ani zákazníkovi.
- Stav `docs/design/brand-state.json` píše jen `aid-ui-state.sh`.

## Start (každé spuštění)

1. Projekt = kořen repa, ve kterém PM `/aid-ui` volá (`git rev-parse --show-toplevel`).
2. Prohlížeč - skutečné volání: `mcp__plugin_playwright_playwright__browser_navigate`
   na `about:blank`. Selže → nástroje kroků běží přes `aid-ui-tool.sh` (Node
   Playwright, sám si doinstaluje `lib/ui-fidelity`); řekni to PM. Krok 1i
   (ikony) a krok 4 (vzory) MCP potřebují; bez něj stop s pokynem
   `/plugin install playwright@claude-plugins-official` (MCP hledá značkový Chrome →
   `PLAYWRIGHT_MCP_BROWSER=chromium` do `env` v `~/.claude/settings.json`
   a `npx @playwright/mcp install-browser chrome-for-testing`).
3. Standardy čti živě, nikdy z kopie: `/opt/eco/docs/docs/ecosystem/specs/`
   (`frontend-build-standard.md` FB-1..FB-20, `webapp-tasks-states-standard.md`
   UA-1..UA-11, `design-system-standard.md`, SEO standard). Chybí některý →
   jmenuj ho PM a poznamenej v kapitole, které se týká.
4. Postup stavby: `references/adopted/frontend-design-SKILL.md` (snímek
   frontend-design) a řemeslné minimum `references/adopted/impeccable-craft-floor.md`;
   generické vzory vyřazuje `references/genericity-rubric.md`.

## Kroky a části (jak o nich mluvit)

Jediný zdroj číslování a smyslu je mapa `sections.json`: šest kroků studia
(Druh webu, Zadání a obsah, Vzory, Vzhled, Stavba, Kontrola) a jejich části v pořadí, každý krok i část s `why` (proč),
`goal` (cíl - podle čeho PM pozná, že je to dobře), `feeds` (k čemu výsledek poslouží dál) a část
navíc s `you` (co od PM chce). Studio je ukazuje samo (server čte mapu a stav). PM i ve zprávách
v chatu mluv jen takhle: „Krok 2 z 6: Zadání a obsah · část 5 z 6: Stránky a jejich části"
(části se počítají všechny v pořadí mapy, i vynechané - studio je ukazuje přeškrtnuté jako „vynecháno"). Nikdy vnitřní čísla souborů (0-7, 1p, 1v, 1i, 1s) ani zkratky
typu „2.5". Cíl a smysl nepiš do jednotlivých otázek - patří kroku a části a studio je ukáže.

| Soubor kroku (vnitřní) | Krok pro PM | Část |
|---|---|---|
| `steps/0-start.md` | 1 Druh webu | Co stavíme a co připravit |
| `steps/1-product.md`, `steps/1p-sources.md` | 2 Zadání a obsah | Podklady |
| `steps/1v-vision.md` | 2 Zadání a obsah | Vize a slogany |
| `steps/1i-identity.md` | 2 Zadání a obsah | Logo |
| `steps/1s-seo.md` | 2 Zadání a obsah | Hledání na Googlu |
| `steps/2-structure.md` | 2 Zadání a obsah | Stránky a jejich části |
| `steps/3-content-plan.md` | 2 Zadání a obsah | Obsah stránek |
| `steps/4-references.md` | 3 Vzory | Vzory |
| `steps/5-directions.md` | 4 Vzhled | Tři návrhy vzhledu |
| `steps/6-build.md` | 5 Stavba | Stavba webu |
| `steps/7-verify.md` bod 1a, 1b | 6 Kontrola | Kontrola textů |
| `steps/7-verify.md` bod 1-3 | 6 Kontrola | Technická kontrola |
| `steps/7-verify.md` bod 4 | 6 Kontrola | Pravidla vzhledu |
| `steps/7-verify.md` bod 5 | 6 Kontrola | Schválení stránek |
| `steps/7-verify.md` bod 6-9 | 6 Kontrola | Předání |

## Jak se ptá PM (studio)

Jediný způsob, jak se PM na cokoli ptát nebo mu dát cokoli ke schválení:

1. Zapiš nebo obnov `<project>/.aid-ui/studio/payload.json`:
   `now` (`title`, `text` = co právě děláš, např. „Připravuji tři návrhy vzhledu…";
   obnov ho při každé změně, stránka ho ukazuje vždy a sama bez otázek jen jeho),
   `steps[]` nepiš: kroky, části a jejich stav bere studio z mapy `sections.json` a ze stavu
   (`decide --step` dál bere název kroku z mapy), `questions[]`
   (`id`, `kind`, `part` = id části z mapy (povinné u `facts` a u druhu, který patří víc částem;
   jinak ho studio odvodí), `target`, `opened_at` = teď v ISO, `title`, `prompt`, `body`,
   `next` = co uděláš po schválení, `outcome` = výsledek po schválení jednou větou
   (povinné u všech druhů kromě výběru z karet, viz níže); volitelně `eyebrow` = nadpis
   nad otázkou místo výchozího podle druhu, u `set options` (druh variant) „Co připravit"),
   `cards[]` (`id`, `question`, `title`, `preview` = PNG/JPEG/WebP pod
   `.aid-ui/studio/`, `thesis`, `palette[]`, `risk`, `uniqueness`; volitelně
   `eyebrow` = řádek nad názvem karty, `tags[]` = štítky vedle palety, `url`
   u referencí, a další textová pole, která se ukážou na rubu karty „Detaily").
   Druhy otázek: variant, vision, identity, seo_brief, structure, task_map,
   content_plan, defer_content, facts, references, direction, approve_page,
   exception, coverage_drift, design_standard, handover, sources (krok 1p: jedno schválení
   seznamu podkladů `manifest@<sha>`, nebo průzkumu `online@<projekt>`), product_context (krok 1p: schválení dokumentu o produktu),
   copy_verdict (verdikt PM k textům webu), notifications (PWA: posílá aplikace
   oznámení, o jakých událostech a proč; když ano, obrazovka přihlášení k odběru a karta povolení
   se stavy jako snímek - `pwa-notifications-standard`).
   Na co PM odpovídá textem nebo potvrzením (fakta k ověření, souhlasy, kontrola názvu),
   polož jako otázku `facts` s `outcome` a **třemi kartami s návrhy odpovědi**: první je doporučená
   (studio ji tak označí), vlastní odpověď dá PM přes „Žádná mi nesedí" → „Použít moji odpověď" (`return` s komentářem); každá karta má `source`
   z mapy `sources` (z čeho návrh vychází: `product-marketing:jobs|objections|switching|customer-language|proof`,
   `copywriting:before-writing`, `podklady`, `registr`, nebo `odhad` = tvůj odhad, který PM potvrdí).
   Otázku samotnou ber z převzatého postupu, který `source` jmenuje (product-marketing: za co si
   firmu zákazníci najímají, tři nejčastější námitky, co je žene od dnešního stavu, co je táhne, co je
   drží, čeho se bojí, jejich doslovná slova; copywriting: účel stránky, publikum, nabídka, odkud
   lidé přicházejí), nikdy z vlastní hlavy. Studio otázku `facts` bez tří karet s `source` odmítne;
   pravdivost zdroje neověří - to je na tobě. Co zvládneš sám (rešerše názvu v rejstříku a na
   webu, dohledání údaje), udělej předem a PM dej rozhodnutí nad výsledkem („Našel jsem
   tyto podobné názvy: … Ponechat Needless?"), ne úkol „zkontrolujte". Jeden slovník
   stavu: „návrh (náhled) hotový" → „před zveřejněním zbývá" → „zveřejněný"; nepiš
   „předán", „spuštěn".

   **Jak napsat otázku.** `title` = krátká lidská otázka (do ~12 slov). `body[]` =
   2–4 krátké věty: co navrhuješ, proč (odkud to víš, např. „z vašeho zadání")
   a co to znamená pro web. `next` = co uděláš po schválení. Vykej. Zakázané:
   názvy souborů, technické zkratky bez vysvětlení (404, SEO, JSON…),
   angličtina, „Souhlasí?".
   - Špatně: „Needless: prezentační web (jedna stránka + 404), značka existuje
     (znak N, písma Archivo a Caveat), místní firma z Mohelnice. Souhlasí?"
   - Dobře: `title` „Jaký web pro Needless postavíme?", `body` „Navrhuji jednu
     delší stránku, na které návštěvník během pár vteřin pozná, co děláte a pro
     koho, a může vám rovnou napsat." „Vycházím z vašeho zadání, kde je jedna
     stránka a vlastní stránka pro neexistující adresu.", `next` „Připravím
     zadání pro vyhledávače a obsah stránky." (`next` se ukáže až po schválení,
     proto začíná tím, co udělám, ne „Po schválení…")
   **Jak napsat `outcome`.** Platný výsledek, ne další krok ani průběh; srozumitelný bez
   otázky; do 120 znaků; bez „Schváleno", „Doplním", „Takhle". U výběru z karet (druh
   s `choose`) ho nepiš: stránka ukáže název vybrané karty z uložené odpovědi, aby text
   nemohl odporovat tomu, co PM vybral.
   - Špatně: „Schváleno." · „Doplním to do vize." · „Takhle budou stránky poskládané."
   - Dobře: „Klasický web se samostatnou stránkou pro každé téma." · „Sedm stránek, každá
     odpovídá na jednu věc, kterou lidé hledají." · „Texty všech stránek schváleny; čtyři
     údaje zbývá ověřit."
   V žádném textu, který PM uvidí (otázky, karty, `outcome`, `now`, záznamy `decide`), nepoužívej: agent, kapitola, kolo,
   převzetí, payload, standard (kromě odkazu na report), skill.
   Studio ukazuje běh jako šest kroků pod sebou: u každého výsledek jednou větou a kdo
   rozhodl (PM, AI, nebo oba). Detail kroku otevře jeho rozhodnutí a karty, ze kterých PM
   vybíral; čekající otázka je uvnitř svého kroku. Každou přijatou odpověď si studio samo
   uloží i s otázkou, kartami a kopií náhledů do `.aid-ui/studio/history.jsonl`; ten
   záznam je jen pro zobrazení, nečti ho jako rozhodnutí.

   **Když rozhoduje agent sám.** Když krok rozhoduje sám (fakt z PRODUCT.md, volba podle
   standardu, výsledek stavby), zapíše to hned příkazem `aid-ui-state.sh decide <project>
   --step "<název kroku>" --title "<co>" --outcome "<výsledek jednou větou>" --why "<odkud
   to plyne>" [--source <soubor>]`; bez zápisu rozhodnutí neexistuje. `outcome` platí
   stejná pravidla jako u otázek (do 120 znaků, `title` do 80, `why` do 300). `decide`
   nic nemění ve stavu: fakt nebo volbu dál zapisuje její vlastní příkaz, `decide` jen
   zaznamená, že ji udělal agent. Opakovaný krok, který rozhodne totéž (stejný krok,
   `title` a `outcome`), dostane exit 0 a druhý záznam nevznikne. Exit 1/2 zastaví krok
   jako každý jiný příkaz stavu. Kde přesně krok volá `decide`, říká jeho `Postup`.
2. `target` je to, co PM schvaluje: u `set variant|options|structure|content-plan|refs`
   `sha256:` + `jq -S -c -j . <<<"$json" | sha256sum` přesně toho JSON, který
   pak zapíšeš (JSON vždy v souboru pod `.aid-ui/` psaném nástrojem Write,
   do příkazu jako `"$(cat <soubor>)"`); u převzetí kapitoly
   `aid-ui-state.sh chapter-target <project> <id>` (váže id kapitoly i její
   uložené tělo, odpověď pro jinou kapitolu neplatí), u převzetí všech kapitol
   najednou (`handover`, krok 7) `aid-ui-state.sh chapter-all-target <project>`;
   u ostatních druhů podle
   hlavičky `aid-ui-state.sh`.
3. `aid-ui-serve.sh studio <project>` (spustí nebo použije běžící studio)
   vypíše jednorázový odkaz `URL: http://<host>:3915/?k=<kód>`; ten dej PM
   (jen při první otázce běhu nebo po restartu studia - stránka ukazuje další
   otázky sama).
4. Na odpověď čekej sám, PM nemá psát do chatu: spusť na pozadí
   (`run_in_background`) `until aid-ui-state.sh record-answer <project> --question <id> ||
   aid-ui-state.sh changes <project>; do sleep 5; done` a ukonči tah; po jeho dokončení pokračuj.
   Smyčka skončí odpovědí, nebo tím, že PM u některé uložené odpovědi stiskl „Změnit": `changes`
   vypíše novou otázku `<id>.c<n>` (stejný druh, cíl, část, text, karty). Přidej ji do payloadu
   i s kartami, počkej na její odpověď a proveď mutaci kroku znovu s `--answer <nové id>`. Když ji
   skript odmítne, protože běh už pokročil (např. `set options` jen v prvním kroku), vrať běh
   `aid-ui-state.sh step` na vnitřní krok té části, zopakuj ji a vše, co z ní plyne, a pokračuj.
   Zodpovězené otázky z payloadu nemaž: po `record-answer` jim nastav `"done": true`
   a `"answer_title"` (co PM vybral, slovy), studio je ukazuje jako „Uloženo" s tlačítkem
   „Změnit". Kartu PM vybere klikem kamkoli na ni a potvrdí jedním tlačítkem pod kartami („Potvrdit: název"); klik na kartu nic nepošle. Více otevřených
   otázek = jedna smyčka na každou. Napíše-li PM mezitím do chatu, zkus
   `record-answer` hned; exit 1 = odpověď ještě není.
5. Rozhodnutí `approve`/`choose` → mutace s `--answer <id>` (jen tam, kde
   krok nějakou jmenuje). Po `choose` je vybraná karta ta s `id` = `choice`
   zaznamenané odpovědi (`jq '.answers["<id>"].choice' brand-state.json`)
   mezi `cards` téže odpovědi - snímkem karet, jak je studio PM ukázalo
   v okamžiku odpovědi (`jq '.answers["<id>"].cards' brand-state.json`,
   uložil ho `record-answer`), nikdy znovu z payloadu (ten se mohl
   od odpovědi změnit); do stavu nebo těla kapitoly jde obsah té karty beze
   změny (`thesis`, `url`, `palette`, náhled), nikdy karta jiné otázky.
   Náhled zkopíruj, jen když `sha256sum` souboru = `preview_sha256` karty;
   jinak se od odpovědi změnil a otázku otevři znovu.
   `return` → PM vrací s komentářem; oprav a otevři
   otázku znovu (nové `opened_at`). `reroll`/`reroll_safer`/`reroll_bolder`
   („Navrhnout jiné možnosti" = ve stejném duchu, komentář PM je nepovinný a řídí nové návrhy; Bezpečnější / Odvážnější jen u vzhledu, loga a sloganu) → odpověď
   nese `next_question`; vytvoř nové karty podle komentáře a zapiš je pod tím
   id do payloadu.

## Směrování

- Bez argumentu: krok = `jq .step <project>/docs/design/brand-state.json` (soubor
  chybí → krok 0).
- `/aid-ui <n>` (číslo kroku pro PM 1-6) → vnitřní krok podle tabulky výše (1→0, 2→1, 3→4, 4→5,
  5→6, 6→7), `aid-ui-state.sh step <project> <vnitřní>`, pak ten krok.
- Načti jen soubor kroku a proveď ho. Po úspěchu kroků 0-6
  `aid-ui-state.sh step <project>` s číslem následujícího kroku; krok 7 končí
  `aid-ui-state.sh finish <project>`.
- `brand-state.json.finished` vyplněné → běh je hotový; nabídni krok
  k opakování (`/aid-ui <n>`; krok zpět vynuluje `finished`).
- Selže skript: ukaž PM jeho řádek `ERROR:`, krok neposouvej.

| Krok | Soubor |
|---|---|
| 0 | `steps/0-start.md` - varianta, inventura, kontrola pokrytí |
| 1 | `steps/1-product.md` (+ `steps/1p-sources.md`, `steps/1v-vision.md`, `steps/1i-identity.md`, `steps/1s-seo.md`) |
| 2 | `steps/2-structure.md` - stránky, role, toky |
| 3 | `steps/3-content-plan.md` - obsah a fakta |
| 4 | `steps/4-references.md` - vzory |
| 5 | `steps/5-directions.md` - tři směry jako stránky |
| 6 | `steps/6-build.md` - stavba |
| 7 | `steps/7-verify.md` - ověření, schválení, `finish` |

Skripty (`$AID_PLUGIN_PATH/scripts/`): `aid-ui-state.sh` (jediný zapisovatel
stavu a těl kapitol v `docs/brand/index.html`), `aid-ui-serve.sh`,
`aid-ui-coverage.sh`, `aid-ui-tool.sh` (`glyph`, `webp`, `verify`, `measure`, `wordmark`, `png`),
`aid-ui-design-to-css.sh`, `aid-ui-ico.py`, `aid-ui-seo-check.py` (SEO a AI, krok 1s a brána),
`aid-ui-brand-package.py` (balíček značky), `aid-ui-design-standard.py` (design standard, krok 7),
`aid-ui-vision-check.py` (vize), `aid-ui-customer-page.py` (stránka pro zákazníka po bráně, krok 7 bod 7b),
`aid-ui-sources.py` (podklady, krok 1p), `aid-ui-copy.py` (kontrola textů, krok 7 bod 1a; texty stránek dává
`aid-ui-verify.sh <project> --copy-subject`).

## Zprávy PM

Formát podle `/opt/eco/CLAUDE.md` „Jak agent píše Markovi": česky, lidsky,
jedno rozhodnutí = jedna otázka ve studiu s doporučením; chat nese shrnutí
a odkaz.

---

## MUST Rules

1. Never without the PM: every choice and approval (variant, vision, slogan,
   logo, SEO pages, structure, content plan, references, direction, pages,
   exceptions) is the PM's. A missing answer ends the turn with a background
   wait for it ("Jak se ptá PM", step 4); no step proceeds unattended and no step writes state directly.
2. Answers come only through `aid-ui-state.sh record-answer`, and a mutation
   that needs the PM takes `--answer <id>`; an answer read from chat is never
   a decision.
3. Ecosystem standards are read live from `/opt/eco/docs/docs/ecosystem/…` on
   every run; a missing one is named to the PM and noted on the brand page.
4. The build follows the frontend-design snapshot
   `references/adopted/frontend-design-SKILL.md`; no other design tool.
5. No invented facts (prices, addresses, references, numbers, quotes): a fact
   comes from the PM or the project and is listed in `docs/content/facts.yaml`.
   No placeholders (lorem ipsum, "Váš text", fake logos) in anything the PM
   sees or the build ships; missing material goes through step 3.
6. Step 0 runs `aid-ui-coverage.sh check`; exit 1 or 2 stops the run.
7. Gallery blocks (403/429/captcha) are never bypassed. Third-party screenshots
   live only in `<project>/.aid-ui/refs/` (gitignored, outside `docs/brand/`)
   and are deleted after step 5.
8. Chapter bodies are written only by `aid-ui-state.sh body <project> <id> --file <html>`;
   nothing internal lives in the served `docs/brand/`.
9. A page is "reviewed" only with a `copy_review` pass of the independent copy review (step 7
   point 1a: `aid-ui-copy.py`, verdict computed by the script, `aid-ui-state.sh copy-record`) or a
   PM exception; the agent never reviews its own copy, never writes a run's `run.json` or answer by
   hand, and writes copy only by the adopted method (`references/copy-rules.md`, `copy-<jazyk>.md`).
11. Steps and parts are named only by the map `sections.json` ("Krok N z 6: … · část M z K: …"); internal
   step numbers never reach the PM. A `facts` question carries `part` and at least three cards, each
   with a `source` from the map; the studio refuses the payload otherwise.
10. A decision a step makes without the PM (only where its `Postup` says so) is recorded
   at once with `aid-ui-state.sh decide` ("Když rozhoduje agent sám"); an unrecorded
   agent decision does not exist for the PM.

---

## Completeness Gate

Před posunem kroku:

- [ ] každá otázka kroku má zaznamenanou odpověď (`jq .answers <state>`) a její mutace prošla;
- [ ] každá kapitola, kterou krok mění, má tělo přes `aid-ui-state.sh body` a stav přes `aid-ui-state.sh chapter`;
- [ ] PM dostal v chatu shrnutí a odkaz (studio nebo `aid-ui-serve.sh brand docs/brand`);
- [ ] v `docs/brand/` není nic cizího (screenshoty galerií jen v `.aid-ui/refs/`).

---

## Reference Files

- `steps/0-start.md` … `steps/7-verify.md` - postup kroků (tabulka výše).
- `references/adopted/frontend-design-SKILL.md`, `references/adopted/impeccable-craft-floor.md`.
- `references/genericity-rubric.md` - vyřazení generických vzorů a směrů.
- `references/adopted/marketingskills/` - převzaté postupy textů (product-marketing, copywriting,
  copy-editing, customer-research, cro; MIT, commit `dda3841`, `MANIFEST`); kdo je čte, říká
  `references/adopted-sources.md`.
- `references/copy-rules.md`, `references/copy-cs.md`, `references/copy-sk.md`, `references/copy-en.md` -
  pravidla textů AID a jazykové příručky; `references/copy-review.schema.json` - tvar odpovědi revizora.
- `references/brand-icons.js` - vykreslení ikon (krok 1i).
- `coverage/{map,checks,sources}.yaml` - pokrytí standardů.
- `brand-page/` - šablona brand stránky a `state.template.json`.

**Last Updated:** 2026-09-28
