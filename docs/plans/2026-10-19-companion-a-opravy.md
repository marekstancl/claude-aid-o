# Zadání: companion jako hotová stavebnice + opravy z projektů (19. 10. 2026)

Stav: verze 3.1 (po revizích Codexem 1, 2 a 3, `review-3.md` bez blockeru, dvě upřesnění doplněna; `review.md`, `review-2.md`; `.aid-o/work/evidence/companion/zadani/review.md`; odpovědi v §8 a §9). Stavba mimo AID podle „Vývoj mimo AID“ (`/opt/eco/CLAUDE.md`),
worktree `.aid-worktrees/companion`, větev `feat/companion-a-opravy` od main 3.6.0.

## 1. Zadání PM (doslova, 19. 10. 2026)

> ok zaměřil bych se primálně na companion a zjednodušil jej taby server agenti nemuseli stavět, měli jasnou
> konstru do které jen doplní co je třeba, viz půj poslední companion ve WANU a poznakty k tomu
>
> musíme to udělat blbuvzdoré a jednoduché na použití pro agenta, a dát mu jen jasný istrukce jak pracovat a
> dělat co na co jej potřebuju a to je návrh UI, dle existujících vzorů a pravidel atd... nechci aby ztrácel čas
> a já platil tokeny za neustále tvoření nástrojů
>
> celkově bych toho přiřadil co nejvíc co dává smysl opravi
>
> vše musí být ověřeno nezávysle

**Co je v sázce:** companion je jediné místo, kde PM vybírá podobu obrazovek. Dnes se nespustí vůbec (od 2.118.0),
odpovědi PM se agentovi nezapíšou a každý agent si stránku, focení i rozjezd staví znovu (WAN 18.–19. 10.: šest
verzí generátoru, vlastní běhač focení a smyšlená data, pět ručních kroků rozjezdu). PM za to platí tokeny a čas
a dvakrát vrátil stránku jen kvůli podobě („scrolovat doprava“, „strašně přiblížená“).

## 2. Co je dnes (ověřeno v kódu a datech 19. 10. 2026)

- `lib/brainstorm-server/index.js:7` načítá `./confirm-store`, který smazal commit 8d2ba434 (28. 9.); do main se
  vrátil sloučením 9ec230a3 (12. 10., 2.118.0). `node index.js` → `Cannot find module './confirm-store'`.
  Řádky 135–136 navíc volají nedefinované `originHost` a `CONFIRM_HOSTS` (POST `/aid/keep` by spadl).
- Testy companionu (`test-companion-start.bats`, t2) nahrazují `index.js` atrapou; skutečný server nespouští nic.
- Server zapisuje do `.events` jen události s polem `choice` (`index.js` ws handler); `confirm` a `note` jdou jen
  do logu. WAN `companion/3662074-1792345221`: log 58 choice + 2 confirm + 1 note, `.events` 1 řádek; poznámka
  PM „je to hnus“ a obě odeslání se k agentovi nedostala. Nová stránka `.events` maže (chokidar `add`).
- S podkladem (`--plan` + `proposal.json`) adresa `/` skládá „DNES“ ze snímku z doby brainstormu vedle návrhu
  (vždy 2×1280 px vedle sebe); WAN proto posílal `/screen`. Relativní cesty podkladu se berou vůči cwd.
- `lib/ui-fidelity/ui-capture.mjs` fotí jeden prvek jedné adresy; neumí kliknutí (otevřít okno), přihlášení
  (localStorage), víc snímků za běh ani mobil v jednom běhu, mocky jen jako statický JSON. WAN si proto napsal
  `capture_p110.mjs` + `fixtures_p110.mjs` (68 + 118 řádků).
- Návod `skills/visual-companion/SKILL.md` (504 řádků) popisuje čtyři různé postupy (fragmenty s CSS třídami,
  kopie `baseline.html`, skládání podkladu, P087 proposal) a žádný z nich WAN nepoužil.
- V `project.yaml` je v oddílu `ui` dnes jen `responsive`; kde je UI, jak se spouští a kde jsou sdílené komponenty,
  konfigurace neříká.
- Externí evidence (mimo toto repo). Postup, který u PM prošel (WAN P110, 19. 10.): kopie UI aplikace mimo repo (`scratchpad/p110/proto/ui`,
  vite :4510), varianty za přepínačem `?v=` postavené jen ze sdílených komponent, snímky Playwrightem nad
  smyšlenými daty, stránka ve třech sloupcích (`gen_p110v6.py`) + upřesnění PM v
  `/opt/eco/projects/wan/.aid-o/work/aid-plugin-issues.md` (19. 10., „stránka companionu s bočním menu“).

## 3. Co se staví

### 3A. Companion: agent implementuje jen varianty a jejich data, všechno ostatní je hotové

**Co je práce agenta a co ne.** Práce agenta = návrh UI: přečíst pravidla a sdílené komponenty, postavit
varianty jako skutečný kód ze sdílených komponent v kopii aplikace, napsat smyšlená data, seznam snímků
a `navrh.json`. Všechno ostatní (server, porty, kopie aplikace, běh prohlížeče, focení, stránka, kontrola
stránky, odpovědi, `proposal.json`) dělá plugin. Agent nesmí vytvořit žádný jiný soubor než ve variantách
kopie aplikace, `mocks.json`, `shots.json` a `navrh.json`. Uvnitř `<P>/` to vynucuje `show` (seznam povolených
souborů); mimo `<P>/` je to pravidlo návodu, které ověřuje záznam příkazů nezávislého agenta (AC9) – nástroj
nevidí, co agent vytvoří jinde, a netvrdí to.

Jeden příkaz `scripts/aid-companion.sh <krok> --plan <P> [--project-dir <root>]`, všechno ukládá do
`.aid-o/work/companion/<P>/` (stálá složka plánu, přes kola i restarty):

| Krok | Co udělá |
|---|---|
| `up` | spustí server companionu (slot 3930–3949, `--host 0.0.0.0 --url-host` podle hostu, stejná verze pluginu); běží-li už server téhož plánu z téže verze, znovu ho použije; z jiné verze ho zastaví a spustí nový; vypíše adresu pro PM |
| `proto` | zkopíruje `ui.dir` (bez `node_modules`, `dist`, `.git` a provozních cest níže) do `<P>/proto/` a hned zapíše obsahový manifest kopie (`proto-manifest.json`: cesta → sha256); `node_modules` napojí symlinkem na projektové; spustí `ui.dev_cmd` (pole argumentů, `{port}` = volný port jen na 127.0.0.1, PM prototyp neotvírá) ve vlastní skupině procesů (`setsid`); čeká na HTTP 200 z `ui.ready_path` (výchozí `/`, limit 90 s) a ověří (`ss -ltnp`), že port drží proces z té skupiny – jinak skupinu ukončí a odmítne; zapíše skupinu, port a adresu; repo projektu zůstane čisté; nepodporované uspořádání (workspace, pnpm bez `node_modules` v `ui.dir`) odmítne se jménem příčiny |
| `shots` | podle `shots.json` nafotí každý snímek ve všech zobrazeních projektu (`ui.responsive`: počítač 1280×800 a telefon 390×844) nad `mocks.json`; vypíše každé API volání bez mocku a skončí chybou, když nějaké bylo |
| `show` | zkontroluje `navrh.json` (schéma), snímky, komponenty a soubory, vyrobí stránku `navrh-<kolo>.html` ze šablony, nafotí ji v 1440×900 a 390×844 a ověří: celá stránka se neposouvá do strany ani dolů (dlouhý obsah se posouvá jen uvnitř svého sloupce), ovládací prvky (body, možnosti, přepínač, poznámka, Předchozí/Další, Odeslat) jsou vidět a klikatelné, žádný obrázek nechybí; zapíše `proposal.json`; vypíše adresu |
| `answers` | vypíše poslední stav voleb a poznámek PM pro dané kolo (`--kolo`, výchozí poslední) a s `--history` všechny události |
| `down` | zastaví server tohoto plánu a skupinu procesů prototypu, ale jen když sedí zapsaná identita: PGID, PID vedoucího procesu s jeho časem startu (`/proc/<pid>/stat`) a příkaz; při nesouladu nic nezabije a řekne proč |

**Formáty (JSON Schema v `lib/brainstorm-server/schemas/`, příklady v návodu, chyby jmenují pole):**
- `mocks.json` – pole `{method?, path (glob na pathname), query? (podmnožina parametrů, přesná shoda hodnot),
  status?, body, headers?}`; první shoda vyhrává. Zachytávají se jen požadavky na `ui.api_prefix` (povinný klíč,
  např. `/api/`) a na `ui.api_origins[]`; moduly, assety a HMR prototypu jdou dál bez zásahu. API volání bez
  shody dostane 404 a jde do výpisu. Žádné `.mjs`, žádné funkce.
- `shots.json` – `{base: "proto"|<url>, storage: {localStorage: {}, cookies: []}, shots: [{name, path,
  steps: [...], capture: "viewport"|"full"|{element: <selektor>}, only?: ["desktop"|"mobile"]}]}`;
  kroky `goto`, `click`, `fill`, `select`, `hover`, `press`, `wait` (ms | `{for: <selektor>}` | `"network"`);
  selektor `{role, name}` | `{testid}` | `{text}` | `{css}`; selektor musí najít právě jeden prvek, jinak chyba
  s počtem. Nepodporované (nové okno, iframe, nahrání souboru) odmítne a řekne, ať to agent zapíše do
  aid-plugin-issues.md.
- `navrh.json` – `plan`, `kolo`, `rozhodnuto[]`, `body[]` → `id`, `title`, `otazka`, `doporuceni` (klíč jedné
  z možností), `proc`, `soulad_s_pravidly[]` (`{pravidlo: <soubor#oddíl>, jak}` – deklarace agenta),
  `minule[]` (snímky minulého kola nebo dnešního stavu), `moznosti[]` → `klic` (A, B, C… od A, unikátní),
  `nazev`, `popis`, `soubory[]` (cesty vůči `proto/`, které možnost změnila nebo přidala), `postaveno_z[]`,
  `nove[]` (`{komponenta, duvod}`), `snimky[]` → `popisek`, `shot` (jméno ze `shots.json`); na nejvyšší úrovni
  `spolecne[]` = soubory sdílené více možnostmi (např. přepínač `?v=`). Cesty jen uvnitř `<P>/`.

**Podle existujících vzorů – vynuceno kódem:** `show` porovná `<P>/proto/` s manifestem z doby kopie (ne
s živým `ui.dir`); ignoruje provozní cesty (`node_modules`, `dist`, `.vite`, `vite-cache`, `.next`, `.turbo`,
`*.log`, `*.tsbuildinfo`). Každý změněný, přidaný nebo smazaný soubor musí být v `soubory[]` právě jedné
možnosti, nebo ve `spolecne[]`. Komponenty v `postaveno_z` musí být staticky importované (ESM `import … from`)
v souborech té možnosti a import musí vést do souboru pod `ui.components`; rozlišují se relativní cesty, aliasy
z `tsconfig.json`/`jsconfig.json` `compilerOptions.paths` a `index.*` složky (barrel). Import, který tímto
nejde dohledat (dynamický, balík, workspace), u jména v `postaveno_z` odmítne s hláškou, kterou cestu nenašel –
nikdy tiše neprojde. Nový soubor komponenty mimo `ui.components` musí být v `nove[]` s důvodem a stránka ho PM
ukáže štítkem „nová komponenta: <důvod>“. Pravidlo pro „nový soubor komponenty“: KAŽDÝ přidaný soubor s příponou
`.tsx`, `.jsx`, `.vue` nebo `.svelte` (i pod `ui.components`) musí být v `nove[]` (`komponenta` = cesta vůči
`proto/`); ostatní přidané soubory (`.ts`, styly, data) stačí uvést v `soubory[]`. Soulad s pravidly UI kód nehlídá: stránka ukáže `soulad_s_pravidly`
pod nadpisem „Agent uvádí, z jakých pravidel vychází“ – deklarace, ne kontrola.

**Šablona stránky (pevná)** = WAN v6 + upřesnění PM 19. 10.: celá na jednu obrazovku, tři sloupce (vlevo body
s „zvoleno X“ a „Podle pravidel“, uprostřed náhled se záložkami snímků, vpravo otázka, možnosti s popisem
a „Postaveno z“, štítek doporučení, zdůvodnění); poznámka a Předchozí/Další přilepené u spodní hrany pravého
sloupce; možnosti od A v každém kole, minulé kolo je pilulka „Minulé kolo“; náhled nikdy větší než skutečnost
(počítač max 960 px, telefon 390 px, klik = skutečná velikost); dlouhý text se posouvá uvnitř sloupce, stránka
jako celek nikdy; přepínač Počítač/Telefon; klávesy ↑↓;
„Odeslat volby a poznámky“ s počtem „Zvoleno n z m“; bod bez snímků bez prostředního sloupce. Snímky jako
soubory (`/companion/<P>/...`), ne base64.

**Odpovědi:** stránka posílá `choice`, `note`, `confirm`. Server je zapisuje jen připisováním do
`<P>/answers.jsonl` (`{v:1, plan, kolo, page, event_id, submission_id?, at, type, bod, volba?, text?}`),
nic nemaže. `answers` z nich skládá poslední stav (poslední volba bodu, poslední poznámka, poslední odeslání).
Soubor smí zapsat i agent, takže `answers.jsonl` je podklad pro agenta, NIKDY důkaz volby PM pro bránu (tak
jako dnes: úložiště potvrzení v paměti serveru (`confirm-store`) od P103 žádná brána nečte). Stránka i hlášení
`answers` to říkají; volbu, na které stojí brána, dál nese karta PM (`aid_pm_card_check`).

**Server a zpětná kompatibilita:** pryč `require('./confirm-store')` a `confirms.clear`; `originHost` a
`CONFIRM_HOSTS` dostanou definici (ochrana `/aid/keep` zůstává). Starý režim zůstává beze změny pro stránky
mimo stavebnici: nejnovější `.html` v `screen_dir`, fragmenty v rámu, `/screen`, `data-confirm` z helperu
(potvrzení jdou do `.events` jako dřív a navíc do `answers.jsonl`). Skládání „DNES“ vedle návrhu na `/` se
použije jen pro stránku, která není ze stavebnice. Cesty podkladu v `proposal.json` se čtou od kořene projektu.

**Konfigurace projektu:** `project.yaml` → `ui.dir`, `ui.components`, `ui.rules[]` (cesty vůči kořeni
projektu), `ui.dev_cmd` (pole argumentů s `{port}`), `ui.ready_path`, `ui.api_prefix`, `ui.api_origins[]`. Chybí-li klíč, krok odmítne s přesným
řádkem YAML k doplnění. `/aid-init` je navrhne z detekce (Vite: `vite.config.*`; `components/shared|ui`) a
zapíše jen po potvrzení jako ostatní návrhy.

**Návod (`skills/visual-companion/SKILL.md`)** přepsaný na jeden postup: (1) přečti `ui.rules` a komponenty
v `ui.components`, sepiš inventář dat a komponent; (2) `up` + `proto`; (3) varianty v `<P>/proto/` jen ze
sdílených komponent za `?v=<klic>`; (4) `mocks.json` + `shots.json` + `shots`; (5) `navrh.json` + `show`;
(6) adresa PM; (7) `answers`; další kolo = `kolo+1`, minulé snímky do `minule`. Pravidlo: **žádné vlastní
nástroje – chybí-li něco, zapiš to do aid-plugin-issues.md a použij nejbližší krok.** Fragmentový režim se
popisuje jen jednou větou (zůstává pro jiné obrázky než UI).

**Vlastnictví souborů kvůli P116:** stavebnice žije v nových souborech (`scripts/aid-companion.sh`,
`lib/brainstorm-server/{kit,shots}.*`, `schemas/`, šablona) a v `lib/brainstorm-server/index.js`, `helper.js`,
`skills/visual-companion/`. Nesahá na `lib/ui-fidelity/*`, `lib/aid-ui-studio/*`, `skills/ui-design/*`,
`commands/aid-ui.md`. Sdílené soubory (CHANGELOG, `aid-help.md`, registr, verze) se před sloučením přenesou
přes rebase na tehdejší main.

### 3B. Opravy z projektů

Seznam podle ověření na main 3.6.0 (tabulka v §7, matice reprodukcí `.aid-o/work/evidence/companion/repro.md`:
ID → příkaz → SHA → výstup před → výstup po). Do balíku jde jen položka, která (1) se na main skutečně
projevuje, (2) má jasnou opravu bez produktové volby PM, (3) nesahá do studia `/aid-ui` (P116 běží souběžně
na větvi `feat/p116-studio-aplikace`). Každá oprava začíná testem, který zopakuje nahlášený případ a před
opravou spadne.

## 4. Mimo rozsah

- Studio `/aid-ui` a jeho tření (P108/P113a záznamy) – P113 je přestavěl, P116 na něm pracuje.
- Obecné úpravy kontroly návrhu brainstormu mimo `proposal.json` zápis.
- Položky, které chtějí produktovou volbu PM (vyjmenované v §7 jako „volba PM“).

## 5. Pravidla

- Vývoj mimo AID: zadání → revize Codexem → kroky, každý s revizí Codexem (při limitu Claude agent s čistým
  kontextem) → revize celku → T0 + T1 + přímo dotčené sady + zkušební projekt nad `git archive`.
- Testy nikdy nevolají skutečný model. Testy serveru companionu spouštějí skutečný `index.js`.
- Dokumentace ve stejném kroku: CHANGELOG, `aid-help`, Docusaurus `/aid/`, registr.
- Merge, tag, push jen na pokyn PM.

## 6. Hotovo, když

- [ ] AC1: test spustí skutečný `index.js` přes `aid-companion.sh up`, pošle websocketem `choice`, `note`,
  `confirm` (dvakrát za sebou, dvě kola) a ověří je v `answers.jsonl` i ve výstupu `answers` (poslední stav
  i `--history`); druhé `up` za běhu vrátí stejný PID a port; po `down` a novém `up` běží nový proces
  a `answers.jsonl` zůstal celý.
- [ ] AC2: `navrh.json` z dat WAN P110 (2 body, 3 možnosti, 8 snímků) projde `show` (jen místně, snímky WAN
  do veřejného repa nejdou); Playwright test šablony nad vzorovými daty ověří: stránka se v 1440×900 neposouvá
  ani s textem 3× delším (posouvá se sloupec), náhled ≤ 960 / ≤ 390 px, klik ukáže skutečnou velikost, přepínač
  Počítač/Telefon, ↑↓, „Zvoleno n z m“, pilulka „Minulé kolo“, přilepená poznámka a Předchozí/Další, bod bez
  snímků bez prostředního sloupce, štítek nové komponenty, snímky jako soubory. PM stránku s daty P110 viděl
  a řekl ano; schválený snímek se uloží jako referenční.
- [ ] AC3: `show` odmítne (každé zvlášť, s polem v hlášce): chybějící povinné pole, doporučení bez možnosti,
  duplicitní klíč, klíč nezačínající od A, `shot` bez snímku, cestu mimo `<P>/` (`../`), komponentu
  v `postaveno_z`, kterou soubory možnosti neimportují z `ui.components`, nedohledatelný import u jména
  v `postaveno_z`, přidaný `.tsx/.jsx/.vue/.svelte` soubor bez `nove[]`, změněný soubor kopie, který není v `soubory[]` ani
  ve `spolecne[]`, a soubor uvedený u dvou možností. A PŘIJME: import přes relativní cestu, přes alias
  z `tsconfig` a přes `index.ts` složky; provozní soubory dev serveru po startu prototypu nevadí.
- [ ] AC4: `shots` nad vzorovou aplikací v testech (statická stránka + `fetch` na API) nafotí dva snímky
  v jednom běhu na počítači i telefonu s každým druhem kroku a selektoru; test ověří obsah snímků (prvek
  otevřený kliknutím, text vyplněný přes `fill`, data z mocku, jiné rozložení na telefonu), přihlášení přes
  `localStorage`, výpis všech API volání bez mocku (assety a moduly prototypu ve výpisu nejsou) a chybu
  u selektoru se dvěma shodami.
- [ ] AC5: `proto` s chybějícím klíčem odmítne s řádkem YAML; s vyplněnými spustí kopii Vite aplikace z testů
  mimo repo (git status projektu čistý), počká na 200, ověří vlastníka portu a `down` zastaví jen svou skupinu
  (cizí proces na stejném rozsahu portů běží dál); obsazený port cizím procesem po startu → odmítnutí; po pádu
  prototypu a znovupoužití PID jiným procesem `down` nic nezabije (test s podvrženým záznamem identity).
- [ ] AC6: `proposal.json` ze `show` projde `aid_ui_proposal_check` a brána návrhu brainstormu ho přijme.
- [ ] AC7: starý režim: test fragmentu, celé HTML stránky, `/screen`, `data-confirm` z helperu a spuštění
  bez projektu (standalone) se chová jako na 2.117.0.
- [ ] AC8: `/aid-init` u projektu s Vite navrhne `ui.dir`, `ui.components`, `ui.dev_cmd`, `ui.ready_path`.
- [ ] AC9: nezávislý agent (Claude s čistým kontextem, jen nový návod) na kopii vzorové aplikace s hotovým
  zadáním návrhu dojde od `up` po adresu stránky; záznam jeho příkazů neobsahuje vytvoření jiného souboru než
  v kopii aplikace, `mocks.json`, `shots.json`, `navrh.json`.
- [ ] AC10: každá oprava z §7 má řádek v matici reprodukcí a test nad nahlášeným případem, který na main 3.6.0
  (5b9e9e2c) spadne a po opravě projde; nereprodukovaná položka se vyřadí a zapíše proč.
- [ ] AC11: revize Codexem (zadání, každý krok, celek) v `.aid-o/work/evidence/companion/`; T0 + T1 + dotčené
  sady zelené; zkušební projekt nad `git archive` zelený.

## 7. Opravy (ověřeno na main 3.6.0, 19. 10. 2026)

Ověření: vlastní čtení kódu (F1–F3, F7, F8) a samostatný ověřovací agent (Sonnet, jen čtení, reprodukce v /tmp,
bez volání modelu) pro ostatní. Každá položka dostane test, který na 3.6.0 spadne (AC8).

| # | Co se opraví | Zdroj | Ověření na 3.6.0 | Oprava |
|---|---|---|---|---|
| F1 | `plan-close` zruší pracovní kopii i se změněnými a neuloženými soubory | WAN 19. 10. | `aid-plan-fsm.sh:1441` `worktree remove --force` (voláno až po definitivním uzavření, kolem 6881) | kontrola `git status --porcelain` v přípravné fázi PŘED jakoukoli nevratnou změnou stavu uzávěru; při změnách odmítne se seznamem; zahodit jen `--discard-worktree-changes`, ověřeno ve stejné přípravné fázi |
| F2 | kontrola kroku spadne (128, bez hlášky) na souboru mimo git | APPS 16. 10. | `lib/aid-repo-roots.sh:69` roura pod pipefail; funkce má podle svého popisu vrátit „nic“ | funkce vrátí nic; kontrola kroku takový soubor vypíše jako `outside_git` (neověřitelný) v hlášce i v `step-check.json` a revizoři ho vidí v podkladu – nic se tiše nepřeskakuje; deklarované `repo_roots` dál fail-closed |
| F3 | delegovaný Codex nezapíše verdikt (sandbox jen pro čtení) | APPS 16. 10. | `lib/aid-delegate.sh:69` „Write your verdict … to <file>“; `_codex_run` už ukládá poslední zprávu přes `-o` do téhož souboru | pokyn „vrať verdikt jako jediný JSON objekt v poslední zprávě, nic nezapisuj“ pro Codex; pro náhradníka Clauda pokyn beze změny |
| F4 | delegovaný verdikt zablokuje `plan-finalize --stage decide` | WAN 18. 10. | `aid-review-round.sh:1499-1500` + `lib/aid-stage-log.sh:145-170`, reprodukce rc=1 (potvrdil i Codex 2) | po poslední úpravě verdiktu zapsat jeho cestu do `stage-writes.jsonl`; test pro verdikt od Codexu i od náhradníka |
| F5 | citace nálezu neprojde bránou CP1 (zpětné uvozovky) nebo kontrolou fragmentů (uvozovka po `>`) | AID 17. 10., WAN 18. 10. | (a) `aid-cp1-gate.sh:240,256` `_norm`; (b) `gates/aid-contract-validate.sh:312` maskuje vyváženou citaci jen po mezeře/`(`, takže `>>'consumption'` z WAN P109 (6c4dc643) dá lichý počet | (a) `_norm` maže zpětné uvozovky a uvozovky na obou stranách; (b) maskování citace i po interpunkci |
| F6 | `/aid-init` dá testové bráně výchozí limit 60 s a release bez `plan_diff` | APPS 16. 10. | `lib/aid-init-execution-yaml.sh` – `timeout_seconds: 900` má jen `check_ui_handover` (ř. 84); testové brány ze `defaults/execution-stacks/*.yaml` limit nemají | `timeout_seconds: 900` u testových bran (jako studio), `plan_diff` v release; reprodukce vygenerováním pro python stack |
| F7 | kritikův návrh rozsahu označen jako prázdný | share 14. 10. | `lib/aid-critic.sh:277` (≤2 řádky bez odrážky = prázdné); share `P001/critic/plan-run1` | prázdné jen bez textu nebo s větou, že změnu rozsahu nenavrhuje (pevný vzor); jinak se ukáže PM – zbytečný řádek na kartě je menší škoda než ztracený návrh |
| F8 | podklady testů v `docs/` ignoruje git; místní zbloudilý `plugins/aid-orchestrator/.aid-o` v hlavní kopii kazí zkušební projekt | AID 14. 10. | `.gitignore:87`; složka existuje jen v hlavní kopii (ignorovaná) | výjimka `.gitignore` pro podklady testů + test, že žádný sledovaný test neodkazuje na ignorovaný podklad; hledání pracovního prostoru nebere kořen uvnitř `plugins/`; místní složku zabalím a odstraním mimo commit |
| F9 | `prepare` připraví kolo nad plánem, který neprošel readiness | AID 10. a 11. 10. | `aid-review-round.sh:419-445` čte jen existenci `plan-check.json` | číst výsledek, odmítnout `plan_not_ready` s `next:` |
| F10 | brána CP1 počítá za kolo i odložený adresář (`round-2.unprepared-<čas>`) | AID 9. 10. | `aid-cp1-gate.sh:183-186` bere číslo za POSLEDNÍ pomlčkou, takže `round-2.unprepared-1791560907` → kolo 1791560907 (+ 130, review-round 359/365/396/971/1348, review-summary 71) | celé jméno adresáře `^round-[0-9]+$` PŘED vytažením čísla, ve všech vyjmenovaných čtečkách; ostatní hlásit |
| F11 | `aid_critic_check` láme řádek na `\|` | AID 11. 10. | `lib/aid-critic.sh:293` `awk -F'\|'` | `\|` nahradit zástupným znakem před dělením |
| F12 | kontrola rozdílů nevidí kódy odmítnutí přes `_pr_refuse` | AID 12. 10. | `test-review-round-fsm.bats:97,106`; 23 volání, 4 literály | sken čte i `_pr_refuse <kód>` |
| F13 | v popisu souborů chybí `Delete:` | AID 13. 10. | `lib/aid-scoping.sh:189,501`, `aid-plan-lint.sh:724,978` | štítek `Delete:`; kontrola kroku ověří, že sledovaná cesta po kroku neexistuje a smazání je v diffu (ne konkrétní příkaz) |
| F14 | rozhodčí nechá ve worktree soubory, krok pak neprojde | APPS 15. 10. | `defaults/templates/adjudicator-delegated.md` | pokyn „nic nenechávej“ + `delegate` porovná `git status` před a po náhradníkovi a odmítne jen novou deltu |
| F15 | zavádějící „not committed here“ u cizího repa s platným `repo_commits` | APPS 15. 10. | `lib/aid-dispatch-contract.sh:491` | hlášku vynechat pro cesty v repu z `repo_commits` |
| F16 | návrh `project_tests` z `/aid-init` neodpovídá skutečným testům | AGENTS 12. 10. | `lib/aid-init-execution-yaml.sh:116-136,360-372` | vzory z existujících souborů; „0 souborů“ nenavrhovat |
| F17 | zavádějící „brief has no Co je v sázce“ | AGENTS 12. 10. | `lib/aid-critic.sh:136-139` | hláška říká, že odstavec má jen řádek ceny |
| F18 | `prepare-plan` nemá „verze už je připravená“ | WAN 18. 10. | `aid-release.sh:1098-1130` | `--bump none`: verze nad posledním tagem a sekce CHANGELOG musí existovat, jinak odmítne |
| F19 | `amend-scope` nemá cestu pro rozhodnutí PM | APPS 15. 10. | `aid-fsm.sh:5509-5516` | `--pm-card <karta>` přes `aid_pm_card_check`, zapsáno jako `pm_decision` |
| F20 | noční červená `test-run-all-tests-result-grammar` | noc 15.–19. 10. | případy 29–30, `test-zadani-lint` je od 3.4.0 v T1 | zastaralý podklad testu: T0 případ na `test-static` |
| ~~F21~~ | VYŘAZENO: noční červená `test-recovery-adjudicate` | noc 18.–19. 10. | lokálně zelená, na 5b9e9e2c nejde spolehlivě zopakovat | do backlogu: nejdřív uložit noční prostředí, které pád zopakuje, pak rozhodnout, zda řádek na stderr je šum |

Už opravené (ověřeno, nic se nedělá): Stop hook přes 5 s (dec58e71), přímý plán chce „EPIC 1“ (P114, 547a4107),
cizí repo bez `repo_roots` (P112, 26c50440).

**Volba PM (do balíku až po odpovědi):**
- V1 karta uzávěru a otevřené nálezy (WAN 19. 10.): smí jedna odpověď PM na kartu uzávěru znamenat i přijetí
  otevřených nálezů, které karta vypíše s otisky (A), nebo musí být nálezy na zvláštní kartě (B)?
- V2 prostředí pro měření bodů kroku (WAN 18. 10.): projekt deklaruje proměnné a limit pro měření kroku
  novým klíčem v `execution.yaml` (A), nebo se použije `verification_env` uzávěru (B)?
- V3 stránka plánu pro PM je anglicky (AID 9. 10.): plán nese krátké shrnutí v jazyce PM, lint ho vyžaduje
  a stránka ho čte (A), přeloží ho model (B), nebo projekt nastaví jazyk dokumentů (C)?

Mimo balík: noční `test-aid-ui-skill-rules` a `test-aid-ui-sources` (studio, P116).

## 8. Revize zadání Codexem 1 (19. 10. 2026) – co se s nálezy stalo

- 1 F1 místo a přepínač: přijato (ř. 1441, `--discard-worktree-changes`, odmítá i změny sledovaných souborů).
- 2 zastaralé položky: F4 NEPŘIJATO – `aid-review-round.sh:1499-1500` zapisuje `merged/measurement/round/rounds/
  semantic-review-final`, verdikt `adjudicator-delegated-<fp16>.json` v seznamu není (ověřovací agent to
  reprodukoval: `aid_stage_writes_verify` rc=1). F10 NEPŘIJATO – `n="${n##*-}"` bere číslo za poslední pomlčkou,
  `round-2.unprepared-1791560907` se počítá. F5b upřesněno (skutečná příčina = maskování po `>`, reprodukce
  z WAN 6c4dc643). F6 upřesněno (900 má jen brána studia). F8 upřesněno (složka je místní, ignorovaná).
- 3 „agent si dál staví“: částečně. Mocky jen JSON (bez `.mjs`), pevné formáty a kroky – přijato. Deklarativní
  varianty místo kódu NEPŘIJATO: varianta postavená ze skutečných komponent v kopii aplikace je návrh UI sám,
  tedy práce, kterou PM po agentovi chce; deklarace by návrh odtrhla od skutečných komponent.
- 4 vynucení vzorů: přijato pro komponenty (skutečné importy ve změněných souborech, nové komponenty
  viditelné PM); otisk přečtených pravidel NEPŘIJATO (dokládal by otevření souboru, ne dodržení).
- 5–7, 9–13, 16, 19: přijato (konfigurační kontrakt, schémata, model odpovědí, AC, matice reprodukcí, starý
  režim, záznam příkazů agenta).
- 8 `confirm-store`: přijato – starý `data-confirm` zůstává a má test (AC7).
- 14: F2, F6, F13, F14 přijato a přepsáno; F3 upřesněno (verdikt jde přes `-o`, jen pokyn byl špatně);
  F7 přijato s vědomou volbou (falešně neprázdná úroveň 2 je menší škoda než ztracený návrh).
- 15 P116: přijato – seznam vlastnictví souborů, žádný zásah do `lib/ui-fidelity`.
- 17 porty: vyřešeno jinak – prototyp otevírá jen fotografovací prohlížeč na 127.0.0.1, takže dostane volný
  místní port mimo rozsah VPN a se studiem se nepotká.
- 18 formulace: přijato.

## 9. Revize zadání Codexem 2 (19. 10. 2026) – co se s nálezy stalo

- 1, 2, 3 (F4, F10, varianty jako kód): Codex odmítnutí potvrdil; F4 a F10 přeformulovány přesně podle něj,
  nadpis §3A opraven.
- 4 pravidla: přijato – `soulad_s_pravidly[]` jako deklarace agenta, stránka to tak i nazve.
- 5 proces prototypu: přijato – `setsid`, ověření vlastníka portu, `down` jen ověřenou skupinu.
- 6 soubory možností: přijato – `soubory[]` a `spolecne[]`.
- 7 importy: přijato – relativní, aliasy z `tsconfig`/`jsconfig`, barrel; nedohledatelné jméno odmítne s cestou.
- 8 porovnání kopie: přijato – manifest při kopii, seznam provozních cest.
- 9 vejde se: přijato – stránka se neposouvá, sloupce ano.
- 10 zákaz souborů: přijato – uvnitř `<P>/` kód, mimo něj pravidlo + AC9, bez přehnaného tvrzení.
- 11 mocky: přijato – `ui.api_prefix`, `ui.api_origins[]`, glob na pathname, query jako podmnožina.
- 12 AC1: přijato – rozděleno.
- 13 F1 pořadí: přijato – přípravná fáze před nevratnou změnou.
- 14 F21: přijato – vyřazeno do backlogu.
