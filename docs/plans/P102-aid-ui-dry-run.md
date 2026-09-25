# P102 Step 9: zkušební běh `/aid-ui` s volitelnými částmi (akceptační záznam)

Jednou větou: na fiktivním klientovi (Truhlárna Dub) prošly scénáře D, E, F
a G - **PASS**. Scénář D byl nejdřív jen částečný (F1 opravené uprostřed
běhu, Playwright MCP tehdy nešel spustit); controller pak MCP rozchodil,
ověření přes MCP našlo chybu F9, ta je opravená a D prošel (25. 9. 11:15 UTC).

Summary (EN, for the plan AC check): Scenario D: pass (end to end 0-6 with finish and PDF; earlier partial because F1 needed a fix mid-run and the Playwright MCP could not start; the controller then ran the real MCP on 2026-09-25 11:10-11:15 UTC, it found F9, fixed and re-verified), Scenario E: pass, Scenario F: pass, Scenario G: pass.

Zapsáno 2026-09-25. Testovaný kód: worktree `.aid-worktrees/plan-P102`,
větev `task/E-102-3_3/main` (s necommitnutými opravami F1-F3 od controlleru).
Scratch projekt: `<scratchpad>/dryrun/truhlarna` (mimo repo), kopie pro
opakování F1 `<scratchpad>/dryrun/truhlarna-copy`. Všechny volby PM udělal
tester za fiktivního klienta a jsou tak v poznámkách označené. MUST 3 (kroky
2-3 se v automatickém běhu nespouštějí) je pro tento zkušební běh zrušené
stejně jako v P101: „PM" je tester, který stránky otevírá a kliká.

**Playwright MCP v bězích 1 a 2 (historie):** tehdy se na hostu nespustil
(`Chromium distribution chrome is not found at /opt/google/chrome/chrome`,
bez sudo), prohlížečové kroky jely přes Node Playwright s Chromiem z
`~/.cache/ms-playwright` (moduly z `node_modules` repa přes `NODE_PATH`),
`references/brand-icons.js` přes harness `run-snippet.js`. Transport MCP
(`browser_run_code_unsafe` s `filename`) controller ověřil až potom - viz
„Ověření přes Playwright MCP" (našel F9, opraveno).

Běhy (UTC):
- **Běh 1** 07:39-07:57: kroky 0-4 až po responzivní bránu, scénáře E, F, G;
  pak předání controlleru (vynucené), který opravil F1-F3.
- **Běh 2** cca 08:05-08:17 (začátek odhadnutý, nezapsaný): jedno kolo oprav po revizi, dokumentátor, konec
  kroku 4, kroky 5 a 6, `finish`, PDF, opakování F1, `spend --also`.

## Scénář D - všechny čtyři části zapnuté, kroky 0 až 6

| | |
|---|---|
| Co běželo | krok 0 (`init`, šablona, `product_type presentation`, `options {vision:true, identity:"new", seo:true, images:true}`, brand na :3916) → krok 1 (`PRODUCT.md` ve tvaru Impeccable init s klíčem v prostředí, `IMAGE_GEN_AVAILABLE`; postup stavby comp-first) → 1v (vize, 5 sloganů, `await-choice slogan`) → 1i (zadání, 3 SVG koncepty, `await-choice logo`, balíček, ikony, `aid-ui-ico.py`) → 1s (`docs/seo/brief.md`, 5 stránek, `await-choice pages`) → krok 2 (vzory jako URL od PM, 3 weby vyfoceny + `getComputedStyle`) → krok 3 (surface brief, `concept-seed` f4c04df1, 4 compy, `await-direction` → `assigned`, `build_path comp`) → krok 4 (kompoziční kolo, Impeccable build-phase comps/spec/plates/hero/sections/motion/responsive, revize, dokumentátor, `design-to-css`, `fonts`, `roles`, ukázky, těla) → krok 5 → krok 6 (`seo-check`, `schvaleni`, `schvaleno --by PM`, `finish`) |
| Co bylo vidět | každá zapnutá část zapsala svou volbu jen přes skript (`choices.slogan` = 1, `logo` = 3, `pages` = 5 stránek, `composition` = comp-1); krok 2 skript pustil až se všemi třemi volbami; `brand-state.json.finished` = `2026-09-25`; brand stránka: 11 kapitol, všechna těla neprázdná (kontrola značek `body:<id>` v načtené stránce), písma Karantina a Archivo Narrow načtená (`document.fonts`), žádná odpověď ≥ 400; `state.json` i `../design/brand-state.json` přes server 404 |
| PDF | `brand-final.pdf`, 12 stran A4 (titul + 11 kapitol, jedna na stranu), 10 obrázků |
| Ikony | `brand-icons.js` zapsal `favicon-16/32/48.png`, `apple-touch-icon.png` 180, `icon-192/512.png`, `icon-maskable-512.png`, `favicon.svg`; `aid-ui-ico.py` → `favicon.ico` 16/32/48; `--verify` všech 9 OK, exit 0. Master v 16 px slévá prstence → mikrovarianta pro 16/32 px (bod 7 šablony). Kapitola Logo ukazuje ikony ve skutečných velikostech |
| SEO v kroku 6 | viz scénář G; kapitola `seo` nese souhrn 0 BLOCKER / 5 WARN / 43 OK |
| Výsledek | **PASS** (od 25. 9. 11:15 UTC; předtím ČÁSTEČNĚ ze tří důvodů). (1) F1 opraveno a čistý průchod ověřen (08:14:26-29, jedno potvrzení); (2) dispozice `fix` od revize Impeccable se týká cvičného webu, ne skillu - skill ji správně vedl cestou „převzetí se známým dluhem“ (kapitola `schvaleni`); (3) Playwright MCP ověřen controllerem po rozchození MCP na eco-dev (viz „Ověření přes Playwright MCP“) |
| Čas | krok 0 07:39-07:40; krok 1 s 1v/1i/1s 07:40-07:43:35; krok 2 07:43:35-07:44:23; krok 3 07:44:23-07:48:26; krok 4 07:48:26-07:57 + 08:05-08:14:36 (build-phase, 2 revize, dokumentátor); krok 5 08:14:36-08:14:56; krok 6 08:14:56-08:15:29; PDF do 08:17 |
| Rozhodnutí PM (tester za klienta) | 12: údaje do `PRODUCT.md` a vize, comp-first, slogan 1, logo 3 (Letokruhy), 5 stránek, 2 vzory (+1 nevybraný), směr „Katalog ÚLUV" (přidělený), kompozice comp-1, v kroku 5 ponechat `DESIGN.md` od dokumentátora, převzetí se známým dluhem v kroku 6 |
| Utracené obrázky | viz „Obrázky a cena" |

Revize Impeccable (finish reviewer, Sonnet):
- 1. kolo: `fix`, pět bodů: kótovací čáry u tabule stolu, celostránková shoda
  0,7971 (drift), chybí linka pod hlavičkou, značka v hlavičce malá, čtyři
  vnitřní stránky nevyfocené.
- Jedno kolo oprav (kóty jako CSS čáry s koncovými čárkami, linka 1 px,
  značka větší, snímky všech stránek), 2. kolo: linka a snímky **vyřešeno**,
  kóty **částečně**, shoda (0,8025) a velikost značky **nevyřešeno**; nové
  nálezy: tlačítko na Kontaktu se láme na dva řádky, vnitřní stránky řídké,
  „O nás" jedna věta. Dispozice znovu `fix`; podle pokynu controlleru se dál
  neopravovalo, vše je v kapitole `schvaleni` jako známý dluh.

### Ověření přes Playwright MCP (controller, 25. 9. 11:10-11:15 UTC)

- MCP na eco-dev nestartoval (hledal značkový Chrome v `/opt/google/chrome`).
  Rozchozeno bez sudo: PM zvolil `PLAYWRIGHT_MCP_BROWSER=chromium` v
  `~/.claude/settings.json`, prohlížeč doinstalován `npx @playwright/mcp
  install-browser chrome-for-testing` do `~/.cache/ms-playwright`.
- Skutečný `@playwright/mcp` 1.64 (stdio, nástroj `browser_run_code_unsafe`
  s `filename`) odhalil vadu, kterou běh přes Node Playwright neukázal:
  kód běží v sandboxu bez `require`/`process`/dynamického importu, takže
  `brand-icons.js` spadl na `import('node:fs')` (**F9**). Opraveno: skript
  nepoužívá žádné Node API, SVG čte přes `page.goto('file://…')`, PNG zapisuje
  `page.screenshot({path})`, `favicon.svg` kopíruje agent (`cp`); test ho
  spouští ve `vm` jen s `page`.
- Opravený skript přes MCP na logu Letokruhy: 7 PNG zapsáno, `aid-ui-ico.py`
  → `favicon.ico` 16/32/48, `--verify` 9× OK, exit 0. Ikony v evidenci
  `steps/step_1_qa/mcp-icons/`.

## Scénář E - obrazovka sloganu zavřená bez potvrzení

| | |
|---|---|
| Co běželo | `slogan-1.html` na visual-companion (:61573); „PM" otevřel stránku, klikl na kartu 2 a zavřel ji bez tlačítka Potvrdit; `await-choice --kind slogan --screen slogan-1.html` |
| Co bylo vidět | `await-choice` exit 1: „no confirm on slogan-1.html yet; the round stays open"; `choice_pending = {kind: slogan, key_or_screen: slogan-1.html}`, `choices = {}`; `step 2` exit 1 („a choice is open and unanswered: slogan … vision is on and no slogan is chosen …"); log serveru má jen `click`, žádný `confirm` |
| Výsledek | **PASS** |
| Čas | 07:40:45-07:40:47 |
| Rozhodnutí PM | 0 v tomto kole; pak 1 (slogan 1, zapsán 07:40:56) |

## Scénář F - kompoziční kolo zavřené bez odpovědi

| | |
|---|---|
| Co běželo | krok 4, build path `comp`: tři kompozice (comp-1 = compem zvoleného směru, comp-2 a comp-3 nové) přes Impeccable `serve-question --start`, `aid-ui-serve.sh forward` → :3915; `await-choice --kind composition --imp … --key 8eecb983`; „PM" stránku otevřel a zavřel bez volby |
| Co bylo vidět | exit 1: „the page closed without the PM's answer; the round stays open: URL http://127.0.0.1:3915/ key 8eecb983"; `choice_pending = {kind: composition, key_or_screen: 8eecb983}`; `step 5` exit 1: „a choice is open and unanswered: composition …; the build path is comp and no composition is chosen (step 4)" |
| Výsledek | **PASS** |
| Čas | 07:50:00-07:50:18 |
| Rozhodnutí PM | 0 v tomto kole; po znovuotevření 1 (comp-1, `COMPOSITION: comp-1`, 07:50:34) |

## Scénář G - `aid-ui-seo-check.py` na postaveném webu

| | |
|---|---|
| Co běželo | `python3 aid-ui-seo-check.py site --brief docs/seo/brief.md --json .aid-ui/seo/check.json` (statický web, 5 stránek, `robots.txt`, `sitemap.xml`, JSON-LD `LocalBusiness`); znovu v kroku 6; negativní zkouška na kopii webu |
| Co bylo vidět | exit 0: 0 BLOCKER, 5 WARN (canonical chybí - produkční doména zatím není), 43 OK, všech 5 H1 ze zadání `brief-h1` OK. Kopie se špatným H1 na `/o-nas` a `noindex` na `/postup`: exit 1, `BLOCKER postup/index.html noindex` a `BLOCKER /o-nas brief-h1 expected 'O nás', got ['O dílně']` |
| Výsledek | **PASS** |
| Čas | 07:56:56 (+ 08:15 v kroku 6) |
| Rozhodnutí PM | 0 (5 WARN převzaty jako dluh v kroku 6) |

## Obrázky a cena

- 7 placených generací, vše `gpt-image-2.5-flare` přes `impeccable
  generate-image` (klíč jen v prostředí Impeccable, nikde nevypsán): 6 ×
  medium 1536 × 1024 (4 compy směru: assigned, pick, busytown, canon;
  2 kompozice: comp-2, comp-3) a 1 × high 1280 × 1024 (tabule stolu, plate).
- Cena v USD **neznámá**: sidecary Impeccable ani odpověď `generate-image`
  cenu nenesou, `spend` proto zapisuje `usd: null`; ceník modelu
  gpt-image-2.5-flare jsme neověřovali a odhad bychom si vymýšleli.
- `spend` před opravou: 7 záznamů, z toho comp-1 dvakrát (kopie
  `decision/assigned.png`) a bez plate → špatně (F2, F3).
- `spend --also assets/plates` po opravě: na hlavním projektu „2 new,
  1 duplicate, 9 recorded" - starý duplicitní záznam z doby před opravou
  zůstává (skript staré záznamy nepročišťuje); na kopii s prázdným
  `image_spend` „8 new, 1 duplicate, 8 recorded": 7 s modelem = přesně
  7 generací + `paper.png` (dlaždice ořezu compu, bez modelu, nic nestála).

## Nálezy

- **F1 (opraveno, znovu ověřeno):** 1v/1i/1s říkaly spustit `await-choice`
  až „po potvrzení PM", ale první volání teprve otevírá kolo a bere jen
  potvrzení novější než kolo. Živě na `logo-1.html`: potvrzení 07:41:42,
  kolo 07:41:44 → odmítnuto „predates this round", PM musel potvrdit znovu.
  Oprava (controller): kroky teď kolo otevřou hned po zápisu obrazovky
  (očekávaný exit 1), pak PM potvrdí, pak stejný příkaz znovu. Opakování na
  kopii projektu 08:14:26-08:14:29 (`pages-2.html`): otevření exit 1, jedno
  potvrzení PM, druhé volání exit 0 `CHOICE pages: ["/","/zakazky","/kontakt"]`.
- **F2 (opraveno):** `spend` počítal kopii téhož obrázku dvakrát - teď
  dedup podle sha256 (ověřeno: „1 duplicate"). Otevřené: záznam zapsaný
  před opravou se nepročistí.
- **F3 (opraveno):** `spend` neviděl plate mimo `.impeccable/mocks/` - teď
  `--also <dir>`, `4-build.md` předává `--also assets/plates`. Otevřené:
  do výčtu jde i obrázek, který se negeneroval (dlaždice papíru), rozlišuje
  ho jen `model: null`.
- **F4 (neopraveno):** distribuční lockup s písmem převedeným na křivky
  nevznikl - na hostu není fontTools/opentype a plán nedovoluje novou
  závislost; balíček má jen master s živým textem (zapsáno v README balíčku
  a v kapitole Logo).
- **F5 (mimo AID):** Impeccable `visualize.md` má `DESIGN.md` jako
  předpoklad kompozičního kola, `new-work.md` ho ale píše až na konci.
- **F6 (opraveno 25. 9., dříve neopraveno):** `6-verify.md` bod 2 zneplatní revizi, když se
  `DESIGN.md`/`design.json` změnily po posledních snímcích - jenže
  dokumentátor Impeccable je píše vždy až po revizi, takže podmínka v
  běžném toku nikdy neplatí. Tester revizi potřetí nespouštěl (pokyn
  controlleru: jedno kolo), zapsáno jako dluh. Oprava: revizi zneplatní jen
  změna kódu (včetně tokenů a CSS buildu) po snímcích; `DESIGN.md`
  a `design.json` zapsané dokumentátorem po revizi ji nezneplatní.
- **F7 (opraveno 25. 9., dříve neopraveno):** `aid-ui-serve.sh stop brand` spuštěný mimo adresář
  projektu skončil bez chyby a server nechal běžet; z kořene projektu
  zastavil. Tichý no-op. Oprava: `start` zapíše ukazatel na složku úloh
  (`~/.cache/aid-ui/<id úlohy>`), `stop` podle něj najde a zastaví server
  odkudkoli; test v `test-aid-ui-serve.bats`.
- **F8 (opraveno 25. 9., dříve drobnost):** tělo kapitoly přepsané po `schvaleno` (barvy, ukázky,
  směr - odstranění `loading="lazy"`, bez kterého celostránkový snímek
  obrázky nevykreslil) nechá stav `schvaleno`; `body` schválení neruší.
  Oprava: `body`, které změní obsah schválené kapitoly, ji vrátí na `navrh`
  a vypíše, že schválení zrušilo; stejné tělo stav nechá; test
  v `test-aid-ui-state.bats`.
- **F9 (opraveno 25. 9., našlo ověření přes MCP):** `brand-icons.js` pod
  skutečným `@playwright/mcp` spadl na `import('node:fs')` - sandbox
  nemá `require`/`process`/dynamický import. Oprava: skript nepoužívá Node
  API, SVG čte přes `page.goto('file://…')`, PNG píše `page.screenshot`,
  `favicon.svg` kopíruje agent; test ho spouští ve `vm` jen s `page`.
  Znovu ověřeno přes MCP (7 PNG, `--verify` 9× OK).
- Ostatní meze: font-match bez prohlížeče (Impeccable nenašel Playwright
  z projektu) vzal Karantinu z katalogu bez řazení; motion bez podpisové
  interakce; `ui-capture.mjs` najde Playwright jen přes `node_modules`
  nadřazeného repa (jako v P101); obrazové vyhledání podobných značek je
  ruční úkol PM a neproběhlo; `impeccable document` v kroku 5 se znovu
  nespouštěl (dokumentátor psal `DESIGN.md` o minuty dřív ze stejného
  buildu, PM-tester zvolil ponechat).

## Důkazy

Adresář `/opt/eco/projects/aid-orchestrator/.aid-o/work/evidence/E-102-3_3/R-E102-3/steps/step_1_qa/`:
- `E-slogan-closed.png`, `D-slogan-confirmed.png`, `D-logo-1.png`,
  `D-logo-1-reconfirm.png` (F1 živě), `D-pages-1.png`, `F1-pages-2.png`
  (opravený tok)
- `D-direction-page.png`, `D-direction-locked.png`, `assigned.png`,
  `model-pick.png`, `challenger-busytown.png`, `canon.png`
- `F-composition-page.png`, `D-composition-locked.png`, `comp-1..3.png`
- `hero-side-by-side.png`, `final-diff-report.json`, `site-desktop.png`,
  `site-mobile.png`, `desktop-{zakazky,postup,o-nas,kontakt}.png`
- `seo-check.json`, `seo-negative.txt`
- `DESIGN.md`, `brand-state-final.json`, `brand-final.pdf` (12 stran),
  `brand-final.png`
