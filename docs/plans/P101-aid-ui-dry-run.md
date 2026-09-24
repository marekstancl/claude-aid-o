# P101 Step 7: zkušební běh `/aid-ui` (akceptační záznam)

Jednou větou: skill `/aid-ui` prošel na fiktivním klientovi (Kavárna Lípa)
všemi třemi scénáři A, B a C; A až po opravě tisku PDF, pět nálezů
z prvního běhu je opraveno a živě ověřeno, čtyři meze zůstávají zapsané.

Zapsáno 2026-09-24. Testovaný kód: worktree `.aid-worktrees/plan-P101`,
větev `task/E-101-2_2/main`. Všechny volby PM udělal tester za fiktivního
klienta a jsou tak v poznámkách označené. MUST 3 (kroky 2-3 se v automatickém
běhu nespouštějí) je pro tento zkušební běh zrušené, jak plán nařizuje.

Dva běhy:
- **Běh 1** 15:19-15:33 UTC: kroky 0-3, scénář B, galerie, detektor. Našel F1-F5.
- **Běh 2** 17:42-17:47 místního času (15:42-15:47 UTC), nová session: scénář C,
  krok 4, PDF, živá kontrola opravy F1.

## Scénář A - celá cesta krok 0 až 4

| | |
|---|---|
| Co běželo | krok 0 (inventura, stav, brand stránka na :3916), krok 1 (shrnutí `PRODUCT.md`), krok 2 (galerie, 12 kandidátů, rubrika vyřadila 6, obrazovka šesti karet), krok 3 (brief, Impeccable new-work, kolo směru), krok 4 (web, `DESIGN.md`, `tokens.css`, `roles.css`, ukázky, PDF) |
| Co bylo vidět | brand stránka se po kroku 4 změnila z neutrální (bílá, systémové písmo, prázdné Barvy/Typografie/Ukázky) na zelenou se zlatými odkazy a vyplněnými kapitolami; `tokens.css` 4× `--color-`, `roles.css` 1× `--brand-bg`; `state.json.step` = 5 |
| Výsledek | **PASS**. První PDF **FAIL** (14 stran, Ukázky přetekly na strany 9-13); po opravě tiskového CSS nový render **PASS** (10 stran = titul + 9 kapitol, jedna kapitola na stranu) |
| Čas | kroky 0-3 cca 14 min, krok 4 + PDF + F1 4 min 42 s |
| Rozhodnutí PM | 4 v krocích 0-3 (typ produktu, potvrzení shrnutí, 2 vzory, směr); krok 4 žádné |
| Blokované galerie | žádná (nikde 403/429/captcha); godly.website přesměruje na recent.design a hledání ignoruje, saasframe jen SaaS |
| Mobbin bez účtu | jen marketingová titulka, hledání i objevování přesměruje zpět; 0 použitelných obrazovek |
| Detektor | použitelný na 1 ze 3 webů (madie.es); tabkitchenbakery.com timeout, lepetitbleucafe.com hlavně šum kontrastu; bez `IMPECCABLE_BROWSER` nejede |

## Scénář B - stránka směru zavřená bez odpovědi

| | |
|---|---|
| Co běželo | kolo směru otevřené (`serve-question`, forward na :3915), `await-direction`; klient stránku 6 s držel a zavřel bez volby |
| Co bylo vidět | `await-direction` skončil exit 1: „the page closed without the PM's answer; the round stays open: URL http://10.20.20.22:3915/ key d61e62e7"; **`state.json.step` = 3**, `direction: null`, `direction_pending` s klíčem a URL; **`DESIGN.md` neexistuje**; `require-direction` exit 1; `step 4` odmítnut („run step 3 first") |
| Výsledek | **PASS** (s nálezy F1, F2, F3, opraveno) |
| Čas | 15:28:55-15:29:19 UTC |
| Rozhodnutí PM | 0 v tomto kole (odpověď nepřišla); po znovuotevření 1 (směr „Malovaná výloha") |
| Blokované galerie | netýká se |
| Mobbin bez účtu | netýká se |
| Detektor | netýká se |

## Scénář C - nová session pokračuje krokem 4

| | |
|---|---|
| Co běželo | nová session bez znalosti běhu 1; `/aid-ui` bez argumentu → směrování přečetlo `state.json.step` = 4, `require-direction` → `assigned`, exit 0; načten jen `steps/4-build.md` |
| Co bylo vidět | **na nic z kroků 0-3 se znovu neptal** (typ produktu, vzory i směr převzaty ze `state.json` a `## Direction contract` v briefu, seed eb60bfbe); rovnou stavba kroku 4 |
| Výsledek | **PASS** |
| Čas | 17:42:44-17:47:26 místního času (4 min 42 s včetně kroku 4, PDF a F1) |
| Rozhodnutí PM | 0 (krok 4 nic nerozhoduje; kvalitativní část dokumentátoru Impeccable vyplnil tester za klienta) |
| Blokované galerie | netýká se |
| Mobbin bez účtu | netýká se |
| Detektor | na vlastním webu 2 kola: kontrast zlata 4.0:1 opraven na 4.54:1, zbyl jen `cream-palette` (záměr kontraktu) |

## Nalezeno a opraveno

- F1: stránka Impeccable přes VPN adresu vracela 403 (socat nepřepsal Host/Origin) - forward je teď reverzní proxy ve stdlib Pythonu, která přepisuje Host/Origin/Referer; běh 2: `http://10.20.20.22:3915/` 200, klik zaznamenán, `--wait` vypsal `ANSWER`.
- F2: `await-direction` spouštěl Impeccable mimo adresář projektu a hlásil „server is gone" - skript teď dělá `cd` do projektu.
- F3: znovuotevřené kolo hned končilo „page closed" - postup je teď: dát PM URL a klíč, ukončit tah, `await-direction` až na jeho další zprávu.
- F4: server visual-companion z kroku 2 běžel dál - krok 3 ho teď zastavuje.
- F5: obrazovka karet ukazovala jako vybranou jen poslední - krok 2 teď používá `data-multiselect`.
- PDF 14 stran - `@media print img{max-height:100mm}` (120 mm dalo stále 11 stran); nový render 10 stran.
- Krok 4 neříkal naplnit těla kapitol Barvy/Typografie/Ukázky - teď říká.
- `ui-capture` psal vedlejší soubory na brand stránku - výstup jde do `.aid-ui/capture/`, do `docs/brand/assets/` jen PNG.
- `roles` aliasoval i nedefinované tokeny písma - teď jen definované přípony.
- Kontrola Playwrightu hlídala jen přítomnost nástroje - teď skutečné volání se záložním Node Playwrightem.

## Známé meze (neopraveno)

- Brand stránka nenačítá webová písma projektu: Gloock se zobrazí jako Georgia, kapitola Typografie neukazuje skutečné písmo.
- `ui-capture.mjs` najde `@playwright/test` jen přes `node_modules` nadřazeného repa; v nainstalovaném pluginu neověřeno.
- Hraniční případ plánu „Impeccable rozdává směry, které ignorují volby PM: zapsat jako selhání připnutého zadání z kroku 5, nepřijmout": **ČÁSTEČNĚ**. Přidělený (vedoucí) směr volby drží, protože ho krmí připnutý brief; všech 6 challengerů z katalogu je ignoruje (dva dokonce z režimu Operate při `--mode persuade`). Zapsáno jako selhání připnutého zadání, ne přijato.
- `concept-seed` nemá vstup pro připnutý brief, takže volby PM se do losování challengerů dostat nemohou.

## Důkazy

Adresář `/opt/eco/projects/aid-orchestrator/.aid-o/work/evidence/E-101-2_2/R-E101-2/steps/step_1_qa/`:
- `part1-notes.md` - scénář B, scénář A kroky 0-3, detektor, galerie, Mobbin
- `part2-notes.md` - scénář C, krok 4, PDF, živá kontrola F1
- `brand-before.png`, `brand-after.png` - brand stránka před a po kroku 4
- `brand.pdf` (14 stran, první běh), `brand-fixed.pdf` (10 stran, po opravě)
- `f1-question.png`, `f1-after-click.png` - stránka směru přes VPN adresu a po kliku

Oprava: necommitnutý diff ve worktree `plan-P101` (`aid-ui-serve.sh`, `aid-ui-state.sh`, `SKILL.md`, `base.css`, `steps/2-references.md`, `3-direction.md`, `4-build.md` + bats testy).
