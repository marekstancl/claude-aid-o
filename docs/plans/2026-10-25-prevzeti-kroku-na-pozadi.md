# AID 3.11.0 – převzetí kroku na pozadí

PM 25. 10. 2026, volba 1A (v podobě „mechanika na pozadí, rozhodování zůstává v hlavním okně“).
Vývoj mimo AID (`/opt/eco/CLAUDE.md`), větev `feat/prevzeti-na-pozadi` (od 3.10.0) v repu
`aid-orchestrator`; Z4 větev `feat/aid-progress-hotove-kroky` v repu `services`. Revizor Codex.
Vydání jen na slovo PM.

Verze 3 – zapracováno 14 nálezů první revize zadání a 8 nálezů druhé (Codex, 25. 10. 2026,
`.aid-o/work/evidence/prevzeti-na-pozadi/brief-review.md`, `brief-review-2.md`); značky `[R<n>]`.

## Proč

Od 17. 10. 2026 (rozšíření Claude Code 2.1.301) běží každý agent na pozadí a hlavní okno běhu
(kontrolér) končí tah řádkem `AID-WAIT`. PM to vnímá jako zastavenou práci. Měřením (WAN P115,
25. 10. 2026, sezení `888f7139`) se ukázalo:

1. **Kontrolér čeká v popředí na vlastní dlouhé příkazy.** Za 3 hodiny 53 minut: commit
   a sloučení kroku, testy akceptačních bodů na sloučené větvi (až 10 min), kontrola plánu.
   Celou tu dobu nepřevezme hotového agenta a nepustí dalšího. Živé měření 14:31–14:58
   ukázalo totéž (14:43–14:46 a 14:52–14:54 žádný agent).
2. **`aid-plan-check.sh <plan> --json` bez hodnoty se zacyklí na 100 % CPU** (`shift 2` při
   jednom zbylém argumentu nic neposune). V P115 to stálo 11 minut. Ověřeno: `timeout 5 bash
   aid-plan-check.sh /dev/null --json` → 124. Vzor `X="${2:-}"; shift 2` je v dalších skriptech.
3. **Stop hook AID trvá 7,5–13 s** na každém konci tahu (`aid-hook.sh Stop`, log rozšíření,
   sezení s ~22 000 řádky).
4. **Blok průběhu (mod `aid-progress`) ukazuje „krok 4/12 · 27 %“**, i když jsou kroky 1–3
   a 8 hotové: počítá `current_step`.

Vliv okna v popředí na rychlost se v datech nepotvrdil (agenti se hlásí do minuty, 785/785;
živý test bez okna 27 min plynulý) – není předmětem změny.

## Co se staví

### Z1 – Převzetí kroku na pozadí (hlavní část)

**Výchozí fakta (ověřeno v kódu):** `increment-step` vyžaduje `reviewed_commit == HEAD`
(`aid-fsm.sh` `_increment_binding_verified`, ř. ~4513 a ~5045) a kroky se zvyšují v pořadí,
takže kroky se **převezmou v pořadí** a další převzetí začne až po `increment-step` předchozího.
Paralelní zůstává implementace v pracovních stromech kroků (vlny) – to, co převzetí na pozadí
uvolní, je kontrolér: během převzetí smí přijímat návraty, chystat a pouštět agenty dalších kroků
a vést kola revize. Na tom stojí přínos. Vazba `reviewed_commit == HEAD` se **nemění** [R2].

Nový skript `scripts/aid-step-land.sh <state_file> <step_index> --check "<AC#>:<příkaz>" …
[--timeout <s>]` udělá jen mechanickou část převzetí a nic neopravuje.

**Transakční model – cesta vlny (krok ve vlastním stromu `step/<id>`)** [R1, R4, R5]:
1. Ověří předpoklady: `step_index == current_step`, krok má `contract.json`, strom plánu je čistý,
   pro tento plán neběží jiné převzetí (zámek, viz níž). Jinak skončí bez jakékoli změny.
2. Vytáhne a ověří návrat (`aid_dispatch_contract_extract` + `_validate`). Odmítnutí → záznam, konec.
3. Commitne ve stromu kroku (`aid_dispatch_contract_commit`); „nic ke commitu“ se zaznamená
   a pokračuje se jako dnes.
4. **Sestaví kandidáta mimo větev plánu:** v odpojeném (detached) stavu ve stromu kroku
   z `base = HEAD plánu` udělá `git merge --no-ff --no-edit step/<id>` – stejný tvar historie
   jako dnešní `aid_parallel_merge` (první rodič = plán). Konflikt → `merge --abort`, záznam se
   seznamem souborů, konec; reset kroku na nový základ (`aid_parallel_step_reset`) a nové zadání
   dělá **kontrolér** podle dnešního postupu a `defaults/policies/auto-recovery.yaml` [R4].
5. Spustí kontroly na kandidátovi (cwd = strom kroku, který je k testům připravený, protože v něm
   agent testoval). Každá kontrola má časový limit (výchozí 1800 s) a při překročení se ukončí
   celá skupina procesů [R13]. První neúspěch → záznam, konec; větev plánu se nepohnula.
6. Když je `HEAD` plánu pořád `base`, posune větev plánu na kandidáta (`git merge --ff-only`,
   strom plánu je čistý). Když se mezitím pohnul (nemá se stát, převzetí jdou v pořadí) → záznam
   `base_moved`, konec bez změny plánu. Teprve po úspěšném posunu se odstraní strom kroku (jako
   dnes jen čistý).
7. **Návrat stromu kroku** [R15]: při každém neúspěchu po kroku 4 (`merge_conflict`, `check_failed`,
   timeout, `base_moved`) skript vrátí strom kroku na větev `step/<id>` (`git checkout step/<id>`;
   kandidát byl odpojený, větev kroku se nezměnila) a ověří, že strom je čistý a na větvi. Oprava
   agentem i nové převzetí tak pracují na `step/<id>` jako dnes. Test: opakované převzetí po
   `check_failed` a po `base_moved` projde a výsledná historie je stejná jako na první pokus.

**Sériová cesta** (krok pracoval přímo ve stromu plánu, dnešní chování): commit vzniká na
`plan/<id>` jako dnes, pak kontroly. Neúspěch kontroly commit nevrací – stejně jako dnes, kdy
kontrolér krok vrátí k opravě; krok se neposune (`increment-step` odmítne). Přínos je tu menší
(další sériový krok stejně čeká), ale postup je jeden [R1, R5].

**Co se kontroluje – úplnost** [R3]:
- `--check` nese číslo akceptačního bodu (`AC#` = pořadí v `plan.json .steps[N].acceptance_criteria`).
- Akceptační bod, jehož text **začíná příkazem v backticku** (např. „`scripts/pytest.sh …` passes“),
  je **příkazový** a musí být v záznamu se svým příkazem; ostatní body (zjištění revize, vizuální
  kontrola, posouzení) posuzuje kontrolér v `step-N-verify.md` jako dnes.
- Kontrola z příkazu: příkaz bodu = **první úsek v backticku** v textu bodu. `--check "<AC#>:<příkaz>"`
  musí mít příkaz **znak po znaku shodný** (po oříznutí okrajových mezer). Proměnné prostředí, které
  projekt k testům potřebuje (např. `WAN_TEST_DOCKER_MODE=run`), se předávají zvlášť
  `--env NAME=hodnota` (opakovatelně, zapsané v záznamu) – nikdy jako součást příkazu. Každé `AC#`
  v záznamu nejvýš jednou (duplicita → skript i `increment-step` odmítnou) [R3].
- **Oprava po revizi (CP2):** když opravář po kole revize commitne, `HEAD` se pohne. Kontrolér pak
  pustí `aid-step-land.sh … --recheck` (na pozadí): bez návratu a sloučení spustí tytéž kontroly
  nad aktuálním `HEAD` plánu a zapíše nový záznam s `landed_sha = HEAD` (`path: recheck`).
  Kontrola kroku samotná `HEAD` nepohne [R2]. Kvalita tím vzroste: dnes se akceptační body po
  opravě znovu nepouštějí povinně.
- `increment-step` u kroku se záznamem odmítne, když: záznam chybí nebo nepatří k témuž plánu, běhu,
  kroku a commitu (`landed_sha == reviewed_commit == HEAD`); některý příkazový bod v záznamu chybí;
  některá kontrola neprošla; celkový stav není `landed`; hash kontraktu nebo návratu nesedí s diskem;
  commity `step_sha`, `base_sha`, `landed_sha` neexistují; u cesty vlny `landed_sha` nemá rodiče
  `base_sha` (první) a `step_sha` (druhý) nebo jeho strom není shodný se stromem, který vrátí
  `git merge-tree --write-tree base_sha step_sha` (eco-dev má git 2.39.5; starší git bez `--write-tree` → skript skončí `precondition_failed` s větou, co chybí); u `recheck` `landed_sha` není potomkem posledního
  záznamu `landed` téhož kroku [R7].

**Záznam `steps/<step>/land.json`** [R7, R13]: zapsaný atomicky (dočasný soubor + `mv`), pevné schéma
`version: 1` s `epic_id` (identifikátor běhu plánu, např. `E-115-1_1`; dřív v zadání `plan_id`), `run_id`, `step_index`, `step_id`, `contract_sha256`, `return_sha256`,
`path` (`wave`/`serial`), `step_sha`, `base_sha`, `landed_sha`, `checks[]` (`ac`, `command`, `exit`,
`duration_s`, `timed_out`, `output_tail` = posledních 4 000 bajtů s redakcí tajemství stejnou funkcí
jako souhrn bran (`aid_gate_outcome_redact`, `lib/aid-gate-outcome-summary.sh`), `log` = cesta k plnému logu v evidenci, i ten projde redakcí před zápisem a do gitu nejde –
evidence `.aid-o/work` je mimo verzování), `status`
(`landed`/`return_rejected`/`merge_conflict`/`check_failed`/`base_moved`/`precondition_failed`/`interrupted` –
zastavení signálem nebo chybou: `trap` ukončí skupinu procesů kontroly, vrátí strom kroku a zapíše stav; po `kill -9`
strom opraví další převzetí, zámek zanikne s procesem a kontroly ho nedědí),
`reason`, `at`. Plný log patří do evidence, ne do gitu.

**Zámek** [R6]: `aid_lock_acquire` (`lib/aid-lock.sh`, flock na postranním souboru
`<state_root>/.aid-o/work/locks/land-<plan>.lock`). Flock se uvolní i při pádu procesu, takže
neexistuje zatuchlý zámek. Drží se po celou dobu skriptu: jedno převzetí naráz. Založení
stromu dalšího kroku zámek **nebere** – větev plánu se pohne jen atomickým posunem v kroku 6,
takže strom vzniká vždy z ověřeného stavu. Druhé spuštění čeká nejvýš `--lock-wait` (výchozí
5 s), pak skončí `precondition_failed` s větou „převzetí kroku N běží“. Funkce knihovny, které
skript volá, zámek samy neberou (žádná reentrance).

**Kontrolér:** pouští skript přes `Bash` s `run_in_background: true` a končí tah
`AID-WAIT: převzetí kroku N`. Po notifikaci přečte `land.json`. Při `landed` napíše
`step-N-verify.md` (příkazové body cituje ze záznamu, ostatní posoudí), pustí kontrolu kroku
a kolo revize (CP2) a pak `increment-step`. Při neúspěchu rozhoduje jako dnes. Ruční cesta
(vše v popředí) zůstává platná pro krok bez záznamu.

**Stop hook** [R8]: požadované verdikty, ověřené integračním testem Stop události:
otevřený krok + poslední řádek `AID-WAIT` + živá úloha převzetí na pozadí → tah smí skončit
(`auto_continuation` i `turn_step_open` ho pustí); úloha doběhla a notifikace je v přepisu → tah
skončit nesmí; `AID-WAIT` bez živé úlohy → odmítnuto; úloha běží, ale bez `AID-WAIT` → odmítnuto
s výzvou. Když `turn_step_open` dnes živou úlohu převzetí nezná, naučí se ji stejným
`_aid_qc_bg_pending`.

**Zachované předpoklady `increment-step`** [R9] – žádný se neobchází, každý má test, že s převzetím
na pozadí platí dál: nové ověření návratu proti kontraktu, vazba kroku (5 polí, `AID_STEP_BINDING`
strict i legacy), vizuální ukotvení u frontendových kroků, kolo CP2 (`cp2/step-N/rounds.json`),
idempotentní token a opakované volání (`already_applied`), krok bez commitu.

**Stav (krok 3, 25. 10.):** postaveno – `scripts/aid-step-land.sh`, `lib/aid-land-record.sh` (volá
`increment-step`, odmítnutí `land_record_invalid`), `turn_step_open` pouští `AID-WAIT` na živé volání na pozadí,
dokumentace `pipeline.md`, `aid-run.md` (16d), registry. Navíc proti verzi 3 (z revizí, 5 kol: Claude zástup
a Codex): převzetí měří i body zadání (`aid-plan-diff.sh --step N` nad sloučeným HEAD, `increment-step` výsledek
znovu použije); výstup kontrol jde do souboru (proces nechaný testem na pozadí nedrží rouru); procesy kontroly se
poznají podle tokenu `AID_LAND_TOKEN` v prostředí a po skončení kontroly i při úklidu se ukončí (TERM, pak KILL);
kontrola, která projde, ale změní sledované soubory nebo commitne, neprošla; před `landed` se ověří HEAD a čistý
strom; neúspěšný `--recheck` jde pustit znovu; odmítnuté převzetí (zámek, předpoklad) záznam nepřepíše.
Testy: `test-step-land.bats` (29), `test-hook-rules-turn.bats` (+4 verdikty).

**Stav (krok 5, 25. 10.):** testbed dráha `prevzeti_pilot` (`aid-testbed/bin/lane-prevzeti.sh`): dva klony téhož
plánu, A ruční převzetí, B na pozadí s vloženými chybami (výstup bez bloku `aid-return` → `return_rejected`,
konflikt → `merge_conflict`, padající bod → `check_failed`, `increment-step` pokaždé odmítne) – výsledné stromy
obou plánů shodné. AC1 (přepis řadiče: převzetí jen na pozadí) se offline změřit nedá – drží ho verdikty Stop hooku
v `test-hook-rules-turn.bats`. Dráha našla mezeru: po neúspěšné kontrole sériového kroku (commit kroku zůstává)
nešel `--recheck` – doplněno, `--recheck` naváže na commit kroku (test v `test-step-land.bats`).

**Stav (krok 4, 25. 10.):** mod `aid-progress` 0.8.0 – řádek `↳` (sbaleně za aktuálním krokem, blok zůstává na
3 řádcích; rozbaleně pod kroky); „žije“ = pod číslem procesu běží `aid-step-land.sh` s indexem tohoto kroku
(číslo procesu po pádu může dostat jiný proces). Revize: Claude zástup + Codex.

### Z2 – Argumenty bez hodnoty [R11]

**Odchylka od verze 3 (krok 1, 25. 10., po revizi kroku Codexem):** místo pomocné funkce v `common.sh`
stojí před každým `shift 2` kontrola, **ještě než se hodnota přečte** (jinak ji `set -u` předběhne):
`[[ $# -ge 2 ]] || { echo "<jméno>: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }` –
jedna akce pro každý kontext: ve funkci vrátí (skript jako `aid-fsm.sh` se i načítá a `exit` by ukončil
volajícího), na nejvyšší úrovni skončí (samotné `return` by se tam točilo dál – `aid-review-round.sh`,
3. kolo revize). U funkcí se dvěma povinnými parametry věta „needs 2 arguments, got N“. Místa, kde kontrola počtu už byla (`$# -ge 2`,
`_pfsm_require_optval`, `[[ -n "${2:-}" ]] ||`), zůstávají. Důvod odchylky: funkci by muselo nově
načítat přes sto skriptů. Vkládá a ověřuje jeden nástroj `scripts/tests/lib/opt-value-guard.py`
(`--fix` / kontrola); test `test-opt-value-guard.bats` (t0) ho volá a navíc spouští skutečné skripty:
`aid-plan-check.sh x --json` (bez `set -e`), `aid-job.sh run --id` (`set -u`, holé `$2`), knihovnu
spuštěnou i načtenou a funkci se dvěma parametry.

### Z3 – Rychlejší Stop hook AID [R12]

Měřicí skript `scripts/tests/bench/stop-hook-bench.sh`: vygeneruje syntetický přepis
(25 000 řádků ve tvaru přepisu Claude Code, bez cizích dat), 1 zahřívací + 5 měřených běhů,
limit 30 s na běh, vypíše medián. Základ = implementace z `main` (`git show main:<soubory>` do
dočasného adresáře), nová implementace na téže sadě. Najde, kde čas vzniká, a zrychlí to.
Cíl: medián ≤ 2 s na eco-dev a aspoň 4× rychleji než základ. **Verdikty:** sada přepisů (běžný,
`AID-WAIT` s živou/mrtvou úlohou, karta, otevřený krok, poškozený řádek, prázdný přepis) – shodný
návratový kód, řádek `outcome=` i důvod u základu i nové verze **pro případy, které Z1 nemění**;
případy s převzetím na pozadí se ověřují proti verdiktům Z1 (AC6), ne proti základu [R12].

**Stav (krok 2, 25. 10.):** pořadí kroků změněno – Z3 před Z1 (malé, samostatné). Příčina ověřená:
`_aid_hrt_last_message` (`jq -s` přes celý přepis, 4,5 s na 186 MB) a `_aid_qc_bg_pending` (čtyři
průchody `jq`, 6,9 s). Oprava: čtení od konce (`tac | jq first(...)`) a předvýběr řádků `grep`em
(nadmnožina, JSON je kompaktní; test pokrývá i JSON s mezerami). Měření `stop-hook-bench.sh`: 6,11 s →
1,05 s (5,8×), 6/6 verdiktů shodných; 40 výřezů skutečného přepisu WAN: 0 rozdílů. **Vědomé změny (po revizi kroku 2):** poškozený řádek před poslední zprávou modelu už pravidla nevypne
(dřív `jq -s` selhal na celém souboru a pravidlo pustilo každý konec tahu); při hledání úloh na pozadí se
každý řádek posoudí sám (`fromjson?`) – poškozený se přeskočí, dřív `jq` skončil na prvním poškozeném a řádky
za ním neviděl. Předvýběr: `run_in_background`, `"(Agent|Task)"` a věty harnessu – Claude Code escapuje jen
uvozovky, zpětná lomítka a řídicí znaky, takže je to nadmnožina při jakémkoli odsazení (test s mezerami
i tabulátory). Měřicí skript vynutí cíl a skončí chybou při pádu nebo překročení limitu.

### Z4 – Blok průběhu počítá hotové kroky [R14]

Repo `services`, větev `feat/aid-progress-hotove-kroky`, vlastní commit a záznam v dokumentaci modu
(services nemá CHANGELOG; změna se zapíše do README modu a do Docusaurus
`/ecosystem/operations/claude-code-mody`). Hotový krok je dál jen převzatý (`current_step`), procenta se
nemění [R16]. Mod navíc ukáže kroky, jejichž agent už odevzdal (`output.md` v evidenci kroku), ale na
převzetí teprve čekají: „P115 · krok 4/12 · 27 % · odevzdáno a čeká na převzetí: 8“, Skript zapíše `land.json` hned na začátku se
stavem `running` a `pid` a na konci ho atomicky přepíše výsledkem. Mod podle toho ukáže: `running`
a proces žije → „přebírá se krok 4“; `landed` a krok ještě nepřevzatý → „krok 4 sloučen, čeká na
revizi“; neúspěšný stav → „převzetí kroku 4 neprošlo: <stav>“; `running` s mrtvým procesem →
„převzetí kroku 4 přerušeno“ [R16]. `increment-step` stav `running` odmítne. Funguje i se staršími verzemi AID
(bez `land.json` tento řádek chybí). Test modu: vlna s odevzdaným krokem 8 před krokem 4. Vydání pluginu na Z4 nečeká a naopak.

„Oba CHANGELOGy“ = `CHANGELOG.md` v kořeni repa a `plugins/aid-orchestrator/CHANGELOG.md`
(musí být shodné, CONTRIBUTING).

## Co se nemění (mimo rozsah)

- Výběr testů k bodům, rozhodování o neúspěchu, kola revize, uzávěr plánu – kontrolér.
- Pořadí převzetí a vazba `reviewed_commit == HEAD`.
- Přejmenování testů, které v P115 stálo ~10 min (plán pojmenoval testy číslem plánu, projektová
  kontrola to zakazuje) – do backlogu: kontrola plánu má znát pravidla jmen testů projektu.
- Upozornění „okno čeká na tebe“, probuzení po kliknutí na stránce, slib bez běžící práce – backlog
  (PM 2A, 25. 10.).
- Odpojování VS Code – mimo AID.

## Hotovo, když

- [ ] AC1 [R10]: Testbed, dráha s vlnou tří kroků: v přepisu kontroléru jsou commit, sloučení
  i kontroly akceptačních bodů **jen uvnitř** volání `Bash` s `run_in_background: true`
  spouštějícího `aid-step-land.sh` (test prochází tool_use podle ID); mezi startem převzetí kroku N
  a jeho notifikací je v přepisu aspoň jedno spuštění agenta jiného kroku nebo kolo revize.
- [ ] AC2: **Kvalita beze změny** – tatáž dráha postaru (ruční převzetí) a ponovu: stejné kroky
  převzaté, `git diff` stromů výsledné větve plánu prázdný, stejné verdikty kontrol kroku a CP2.
  Vložené chyby ponovu: odmítnutý návrat, konflikt sloučení, padající kontrola, překročený limit
  kontroly → záznam s odpovídajícím stavem, větev plánu (cesta vlny) beze změny, `increment-step`
  odmítne.
- [ ] AC3 [R5]: Invarianty po fázích (testy): po `precondition_failed` a `return_rejected` beze
  změny gitu i FSM; po `merge_conflict` a `check_failed` (vlna) větev plánu, index, stav sloučení
  a FSM beze změny, commit kroku na `step/<id>` zůstává; po `landed` jen posun větve plánu
  a odstraněný čistý strom kroku. Vždy jen deklarované soubory evidence (`land.json`, logy).
  Skript nikdy nevolá `amend-scope`, `amend-contract` ani nic, co mění kontrakt, plán nebo FSM.
- [ ] AC4: `increment-step` odmítne krok se záznamem: chybějícím, cizím (plán/běh/krok/commit),
  s chybějícím příkazovým bodem, s červenou kontrolou, se změněným kontraktem nebo návratem,
  poškozeným JSON – každý případ test, který na `main` neexistuje a s opravou prochází.
- [ ] AC4b: `--recheck` po commitu opraváře: nový záznam nad `HEAD`, `increment-step` projde;
  bez `--recheck` po opravě odmítne (`landed_sha != HEAD`). Návrat stromu kroku po neúspěchu
  a opakované převzetí (Z1 bod 7) – test.
- [ ] AC5: Dva souběžné `aid-step-land.sh` na témž plánu – druhý skončí `precondition_failed`,
  nic se nepromíchá; zabitý proces převzetí zámek nedrží (další běh ho dostane).
- [ ] AC6: Stop hook – čtyři verdikty z Z1 integračním testem.
- [ ] AC7: Zachované předpoklady `increment-step` z Z1 – testy zelené s převzetím na pozadí.
- [ ] AC8: Z2 – statický test zelený (na `main` padá), `aid-plan-check.sh x --json` kód 2 do 1 s.
- [ ] AC9: Z3 – medián ≤ 2 s a ≥ 4× rychleji než základ; verdikty shodné se základem u případů,
  které Z1 nemění, a shodné se specifikací Z1 u případů s převzetím na pozadí.
- [ ] AC10: Z4 – test modu zelený (odevzdaný krok mimo pořadí, přebíraný krok, procenta beze
  změny), dokumentace modu upravená.
- [ ] AC11: Dokumentace ve stejném kroku jako kód: `skills/pipeline.md` (§Output verification,
  §Parallel groups), `commands/aid-run.md`, `defaults/hook-registry.yaml` a registr kontrol, oba
  CHANGELOGy, Docusaurus `/aid/` jen kde chování popisuje.
- [ ] AC12: T0 + T1 zelené, přímo dotčené sady zelené, testbed nad `git archive` prochází.
- [ ] AC13: Revize Codexem – zadání, každý krok, celek.

## Postup po krocích

1. Z2 – pomocná funkce, převod smyček, statický test, CHANGELOG.
2. Z1 – `aid-step-land.sh` (záznam, zámek, transakční model), testy AC3–AC5.
3. Z1 – `increment-step` se záznamem, Stop hook, zachované předpoklady (AC4, AC6, AC7),
   dokumentace postupu.
4. Z1 – testbed dráha, srovnání postaru/ponovu (AC1, AC2).
5. Z3 – měření a zrychlení Stop hooku.
6. Z4 – mod `aid-progress` (repo `services`).
7. Kontrola celku, testy, hlášení PM.
