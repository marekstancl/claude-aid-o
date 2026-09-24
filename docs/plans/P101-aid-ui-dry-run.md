# P101 Step 7: zkušební běh `/aid-ui` (akceptační záznam)

Jednou větou: skill `/aid-ui` prošel na fiktivním klientovi (Kavárna Lípa)
všemi třemi scénáři A, B a C; A až po opravě tisku PDF, pět nálezů
z prvního běhu je opraveno a živě ověřeno, čtyři meze zůstávají zapsané.

Summary (EN, for the plan AC check): Scenario A: pass with a known limit (lead direction follows the picks, catalogue challengers do not), Scenario B: pass, Scenario C: pass; steps 5-6: pass.

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
| Výsledek | **PASS s mezí**: přidělený (vedoucí) směr drží volby klienta, šest challengerů z katalogu, které rozdal Impeccable, je nedrží (`concept-seed` nemá vstup pro připnutý brief), viz Známé meze. První PDF **FAIL** (14 stran, Ukázky přetekly na strany 9-13); po opravě tiskového CSS nový render **PASS** (10 stran = titul + 9 kapitol, jedna kapitola na stranu) |
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

## Běh 3 - kroky 5 a 6

| | |
|---|---|
| Co běželo | `/aid-ui` bez argumentu → směrování ze `state.json.step` = 5, načten jen `steps/5-standard.md`; krok 5 (standard), pak krok 6 (ověření) |
| Krok 5 | **PASS**: vytvořen `docs/design/design-standard.md`, vyplněny kapitoly `komponenty` a `platformy`, `tokens.css` přegenerován (beze změny); `roles` znovu spuštěn z mapy ve `state.json` exit 0; negativní zkouška (přejmenovaný token) exit 1 s hláškou o chybějícím tokenu `lipa-green` |
| Krok 6 | **PASS**: důkaz závěrečné revize (`.impeccable/review/*.png`) je; kontrola před nasazením našla dva nálezy - dotykové cíle na mobilu 20-27 px < 44 px, focus obrys na papíře 1,85:1 < 3:1 - tester je za fiktivního klienta převzal jako známý dluh; osm kapitol `schvaleno --by PM`, logo `ceka` (brand balíček neexistuje); konečný `state.json.step` = 6 |
| PDF | `brand-final.pdf`, 11 stran |
| Čas | krok 5 19:58:14-20:00:33 (cca 2,5 min), krok 6 20:00:33-20:02 (cca 1,5 min + PDF) |
| Rozhodnutí PM | krok 5: 1 (merge v dokumentu Impeccable); krok 6: 1 (převzetí) |

## Kontrola verzí

`verify-version-files.sh 2.106.0 --baseline 2.105.2` → `OVERALL: PASS — all 8 canonical version-file locations agree on 2.106.0`. Spustil controller na kandidátovi plánu `2a02d5d5` dne 2026-09-24. Verze 2.105.0 z plánu už je vydaná na main; větev plánu vydává 2.106.0 přes prepare-plan.

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

Chyby textu skillu z běhu 3 (neopraveno, v backlogu jako IMP-660 pro pilot Needless / P102):
1. `steps/5-standard.md:215` „Co PM rozhoduje: Nic", ale Impeccable `document` (ř. 200) se při existujícím DESIGN.md ptá refresh/overwrite/merge a na North Star.
2. `steps/5-standard.md:203-204` chce živá tlačítka a pole se stavy, prezentační web žádná nemá; neříká, zda vymyslet vzor, nebo psát „nemá".
3. Krok 5 bod 4 a krok 6 bod 4 neříkají, jak se píše tělo kapitoly do `docs/brand/index.html` (`chapter` mění jen stav).
4. `steps/5-standard.md:206` relativní cesty u `aid-ui-design-to-css.sh`, neříká, že se spouští z kořene projektu.
5. `steps/5-standard.md:211` bod 7 je v běžném toku no-op a neříká, které kapitoly myslí.
6. `SKILL.md:108-109` „Po úspěchu `step <n+1>`" po kroku 6 dává `step 7` → exit 2; chybí konec toku.
7. `steps/6-verify.md:250-251` nejasné, zda změna DESIGN.md/design.json v kroku 5 zneplatní revizní PNG.
8. `steps/6-verify.md:257` a `:276` si odporují; chybí cesta „převzít se známým dluhem".
9. `steps/6-verify.md:253-255` bez výjimky pro statickou stránku; grep barev neodhalí web s vlastními názvy tokenů mimo `tokens.css`.
10. `steps/6-verify.md:258` neříká, zda kapitola `schvaleni` schvaluje sebe a co s `logo` ve stavu `ceka`.
11. `SKILL.md:90-94` Playwright MCP selhal, skill neříká cestu k záložnímu Node Playwrightu.
12. `aid-ui-serve.sh brand` servíruje celé `docs/brand/` včetně interního `state.json`.

## Důkazy

Adresář `/opt/eco/projects/aid-orchestrator/.aid-o/work/evidence/E-101-2_2/R-E101-2/steps/step_1_qa/`:
- `part1-notes.md` - scénář B, scénář A kroky 0-3, detektor, galerie, Mobbin
- `part2-notes.md` - scénář C, krok 4, PDF, živá kontrola F1
- `brand-before.png`, `brand-after.png` - brand stránka před a po kroku 4
- `brand.pdf` (14 stran, první běh), `brand-fixed.pdf` (10 stran, po opravě)
- `part3-notes.md` - běh 3, kroky 5 a 6
- `brand-final.pdf` (11 stran, po kroku 6)
- `f1-question.png`, `f1-after-click.png` - stránka směru přes VPN adresu a po kliku

Oprava: commity `9d46d3a7..1c5b24d9` na větvi `task/E-101-2_2/main` (`aid-ui-serve.sh`, `aid-ui-state.sh`, `SKILL.md`, `base.css`, `steps/2-references.md`, `3-direction.md`, `4-build.md` + bats testy).
