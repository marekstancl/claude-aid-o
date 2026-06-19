# AID `/aid-plan --epic` + `/aid-run` — konsolidovaná analýza (Claude × Codex)

**Datum:** 2026-06-19
**Vznik:** dva nezávislí agenti (Claude Opus 4.8, Codex) analyzovali stejné zadání —
proč generování EPICů a start běhu trvá desítky minut místo desítek vteřin, proč
„někdy chybí commit" a „někdy se udělá branch dřív, než má". Tři kola vzájemného
adversariálního review. Tento dokument slučuje výsledek: ověřené příčiny, shody,
rozcházení (a jak se vyřešila) a sjednocený plán oprav.

Všechna tvrzení jsou ověřena proti zdroji (file:line). Reprodukovatelný případ:
`/aid-plan --epic P044` v projektu WAN — agent ~20 min hledal cestu k pluginu,
hádal CLI argumenty a nakonec ručně vyráběl CP1-deep evidence.

---

## Část 1 — Ověřené příčiny

| # | Příčina | Důkaz (file:line) | Dopad |
|---|---------|-------------------|-------|
| C1 | **Nejednotné CLI.** Command sám říká `epic` (subcommand), ale skills, co na něj předávají, říkají `--epic`. Komentář ve skriptu odkazuje smazaný `/aid-plan-epic`. | `commands/aid-plan.md:19,28` (`epic`) vs `skills/plan-writing.md:1021,1055`, `skills/brainstorming.md:17,380`, `skills/pipeline.md:1162` (`--epic`); `scripts/aid-auto-pipeline.sh:16` (`/aid-plan-epic`) | Agent neví, který tvar je správný → zkouší naslepo |
| C2 | **Cesta k pluginu není deterministická.** „Mode: Generate EPIC" říká `bash {plugin_path}/...`, ale nevysvětlí, jak `{plugin_path}` zjistit. Kanonický resolver existuje jen v `aid-run.md`. | `commands/aid-plan.md:343` vs `commands/aid-run.md:89-93` | Agent globuje cache, najde 6 verzí, vybere naslepo |
| C3 | **Implicitní cwd + nedokumentované argumenty.** Skript běží relativně k cwd a chce `--plan/--queue-mode/--plugin-dir`; nemá `--help` ani `--check`. | `scripts/aid-auto-pipeline.sh:137` (evidence relativně k cwd) | Agent hádá `--project-dir`, `--help` (oba odmítnuty) |
| C4 | **`/aid-plan --deep` neexistuje.** CP1 gate při selhání radí spustit režim, který v pluginu není definovaný. | `scripts/aid-cp1-gate.sh:200` (žádný `--deep` handler nikde) | Agent začne ručně syntetizovat 4 evidence soubory |
| C5 | **CP1-deep evidence vzniká pozdě / vedle.** Gate kontroluje 4 strukturované soubory v `evidence/<plan>/cp1-deep/`, ale review se historicky ukládalo do `cp1-review-<plan>.md` — jiný soubor. | `scripts/aid-cp1-gate.sh` (kontrola 4 souborů) | Vysoce rizikové plány gate blokuje, i když review prošlo |
| C6 | **Generace předčasně vytváří task branch.** `/aid-plan --epic` → `aid-auto-pipeline.sh` → `aid-json-to-run.sh` Step 18 volá `aid-fsm.sh init`, který přes `checkout -b` vytvoří ref `task/E-xxx/main`. Autoři to vědí a obcházejí save/restore-HEAD hackem (komentář je navíc nepřesný). | `scripts/aid-json-to-run.sh:622` (init) + `:663-670` (restore hack), `scripts/aid-fsm.sh:1683` (`checkout -b`) | Branch ref vzniká ve fázi, kde se nic neimplementuje |
| C7 | **Dokumentace si protiřečí.** `pipeline.md:139` tvrdí „PRE-FLIGHT branch nevytváří", o 11 řádků níž `pipeline.md:150` i kód tvrdí opak. | `skills/pipeline.md:139` vs `:150` + `aid-fsm.sh:1683` | Agent neví, čemu věřit |
| C8 | **Branch se vytvoří PŘED kontrolou dirty tree.** V `cmd_init` je branch operace dřív než guard nepřevzatých změn. | `scripts/aid-fsm.sh:1669-1707` (branch) před `:1709` (dirty guard) | „Branch dřív než má, pak ho pojistky nepustí" |
| C9 | **Per-step commit není vynucený.** `increment-step` ověřuje jen, že verify soubor obsahuje řetězec 7+ hex znaků — ne že commit reálně existuje, je na správné branchi nebo je nový. | `scripts/aid-fsm.sh:~2105` | Krok lze „uzavřít" bez skutečného commitu = „chybí commit" |
| C10 | **Generační pipeline není atomická ani idempotentní.** EPIC/JSON/run/queue se zapisují postupně; selhání uprostřed nechá poloviční stav, další pokus pak opravuje půlku. | `scripts/aid-auto-pipeline.sh` (sekvenční zápisy do counter/queue/tasks/runs bez transakce). **Důkazní povinnost:** fault-injection test — selhání ve fázi 2 NESMÍ změnit counter, queue ani publikovat artefakty. (Pozn.: dříve uváděné WAN adresáře `P033`/`P037`/`P038` jsou mockup adresáře, NE trosky pipeline — důkaz byl chybný, mezera je ale reálná podle struktury skriptu.) | Částečné běhy mohou nechat counter/queue/artefakty v nekonzistentním stavu |
| C11 | **Generace nedělá žádný commit a kontrakt to ani nepožaduje.** | `commands/aid-plan.md:335` (6 obecných bodů, commit nezmíněn) | Artefakty zůstanou necommitnuté, není definováno kdo/kdy je commitne |

> **C9 ≠ C11.** Jsou to DVA různé commity: **generační** (artefakty EPICu — C11)
> a **per-step exekuční** (kód během `/aid-run` — C9). „Někdy chybí commit" se
> týká obou. Žádný z nich není dnes vynucený.

---

## Část 2 — Kde se shodujeme (konvergovaný základ)

Po třech kolech jsou tyto body společné a považujeme je za uzavřené:

1. **CLI sjednotit na jeden tvar** — doporučení `--epic` (píšou tak skills i uživatel). (C1)
2. **Cestu plugin/project root určuje skript, ne agent** — žádné globování cache, žádný výběr verze. (C2)
3. **`--help` a `--check`** na `aid-auto-pipeline.sh`. (C3)
4. **`/aid-plan --deep` vyřešit** — buď implementovat jako reálný režim, nebo smazat a opravit hlášku gate. (C4)
5. **CP1-deep posunout na čas psaní/review plánu** (cílový stav = „varianta A"). Při `--epic` s chybějící evidencí → **tvrdý stop**, nikdy ruční syntéza. (C5)
6. **Branch oddělit od FSM init** — init smí zapsat `fsm-state.yaml`, ale git operaci ne. (C6, C7)
7. **Dirty-tree check PŘED branch operaci** — samostatný bug, opravit nezávisle na všem ostatním. (C8)
8. **Per-step commit reálně vynutit** v `increment-step`. (C9)
9. **Existují dva commit kontrakty** (generační + exekuční), oba je nutné definovat. (C9 + C11)
10. **Atomicita + idempotence generace** je reálná mezera — staging → validace → publish, idempotentní podle `plan_id + phase`. (C10)

---

## Část 3 — Kde jsme se rozcházeli a jak se to vyřešilo

| Téma | Claude původně | Codex | Výsledek (shoda) |
|------|----------------|-------|------------------|
| **Kdy vytvořit branch** | „líně, až s prvním commitem" | „při READY→EXECUTE, před první implementační změnou" | **Codex má pravdu.** Kdyby se čekalo až na commit, agent už upravuje soubory na main. Branch vzniká při přechodu READY→EXECUTE, po kontrole čistého stromu. |
| **Plugin resolver** | „zkopírovat instrukce z aid-run.md do aid-plan.md" | „nekopírovat — jeden sdílený resolver skript pro oba příkazy" | **Codex má pravdu.** Kopie = další duplicita. Sdílený skript. |
| **Legacy plány bez evidence (varianta B)** | „když existuje PASS review, vygenerovat z něj 4 stuby" | „odmítnout — starý review ≠ tři nezávislé čočky; stuby jen obcházejí gate" | **Codex má pravdu.** Pro legacy: znovu spustit CP1-deep, NEBO explicitní auditovatelný PM waiver — nikdy falešná evidence. (Claude k tomu sám dospěl ve finále.) |
| **Priorita atomicity** | P1/P2 (idempotence levně teď, plná atomicita později) | „zásadní mezera" | **Vyřešeno.** Atomicita zařazena jako krok #5 — **explicitně PŘED generation commitem** (#6), jinak by commit stál nad částečně mutující pipeline. |
| **Priorita CLI sjednocení** | brzy (levné, vysoká hodnota) | původně poslední | **Vyřešeno ve prospěch Claude.** CLI + sdílený resolver zařazeny jako krok #1 (levné, odblokují vše ostatní). |

> Žádný z původních rozporů nezůstal otevřený na úrovni faktů. Zbývají jen dvě
> **rozhodnutí pro PM** (Část 4), kde nejde o správnost, ale o politiku/přísnost.

---

## Část 4 — Rozhodnutí PM (ROZHODNUTO 2026-06-19)

**R1 — Legacy high-risk backlog — ROZHODNUTO: strict default + explicitní waiver.**
Default = tvrdý stop (legacy high-risk plán neprojde bez CP1-deep evidence).
Únikem je **explicitní, auditovatelný PM waiver**, který MUSÍ být navázaný na:
- konkrétní **hash plánu** (content hash souboru plánu),
- **review soubor** (cesta k `cp1-review-<plan>.md`),
- **verdikt PASS**,
- **důvod**,
- **čas** (ISO 8601),
- **PM autorizaci** (identita schvalovatele).

**Jakákoliv změna plánu waiver zneplatní** (změní se hash → waiver neplatí → znovu
stop). Nikdy fabrikovaná evidence ani auto-stuby.

**R2 — Generation commit — ROZHODNUTO: jeden automatický commit, přísně omezený.**
`/aid-plan --epic` je **dokumentovaně souhlas s jedním přesně omezeným commitem**
(orchestrátorové artefakty nejsou produkční kód). Pravidla:
- **právě jeden** generation commit, **nikdy push**;
- stagovat **pouze cesty z manifestu**, NIKDY `git add -A`;
- flag **`--no-commit`** pro výjimky (artefakty zůstanou necommitnuté).

**Proč auto-commit, ne „necommitovat":** kdyby generace nechala artefakty
necommitnuté, `/aid-run` narazí na clean-tree guard a zasekne se. Necommitnutý
stav tedy aktivně rozbíjí navazující běh — proto je jeden řízený commit správné
default chování, ne uvolnění pravidla bez důvodu.

---

## Část 5 — Sjednocený plán realizace (pořadí)

> **Klíčové pravidlo pořadí:** atomicita (#5) MUSÍ být před generation commitem (#6),
> jinak commit kontrakt staví nad stále částečně mutující pipeline.

1. **Sdílený resolver + jednotné CLI + `--help` + read-only `--check`** — plugin/project root určí skript; sjednotit syntaxi na `--epic`; přidat nápovědu a suchý běh.
2. **CP1-deep při plan review + legacy waiver** — cílový stav varianta A; vyřešit `/aid-plan --deep` (implementovat NEBO smazat + opravit hlášku v `aid-cp1-gate.sh:200`); legacy → re-review nebo explicitní waiver (R1).
3. **Oddělit FSM init od git mutací** — `aid-json-to-run.sh`/`cmd_init` přestane mutovat git; `fsm-state.yaml` se smí zapsat. Smazat save/restore hack (`aid-json-to-run.sh:663-670`).
4. **Dirty-tree check před branch operací READY→EXECUTE** (`aid-fsm.sh` — přehodit pořadí).
5. **Atomicita + idempotence** — staging → validace → publish; idempotentní podle `plan_id + phase`. Důkaz fault-injection testem (viz C10).
6. **Generation commit nad atomickým výsledkem** — jeden commit dle R2 (manifest-only staging, nikdy push, `--no-commit` výjimka).
7. **Per-step commit enforcement** v `increment-step` (kontrakt viz Příloha).
8. **Dokumentace a regresní testy.**

---

## Příloha — cílové kontrakty toku (přijato od Codexe)

### `/aid-plan --epic`
1. Sjednocená syntaxe `/aid-plan --epic P044` (i cesta k souboru).
2. Deterministicky vyřešit plán, project root, plugin root (sdílený resolver).
3. Read-only preflight (`--check`).
4. CP1-deep musí být hotové z plan-review fáze; legacy absence → re-review nebo explicitní waiver.
5. Atomicky vygenerovat EPICy/JSONy/run/queue (staging → validace → publish).
6. **Neinicializovat FSM s git mutací, nevytvářet task branch.**
7. Validovat manifest.
8. Vytvořit přesně jeden generation commit (dle R2 — stagovat jen cesty z manifestu, nikdy `git add -A`, nikdy push; `--no-commit` výjimka).
9. Ověřit invariant větve/HEADu:
   - **název aktuální branche zůstane stejný** (žádné přepnutí, žádná task branch);
   - při commitu se **HEAD posune právě o jeden commit**;
   - s `--no-commit` zůstane **HEAD SHA stejný**.

### `/aid-run`
1. Inicializovat READY **bez branch mutace**.
2. Po schválení READY→EXECUTE zkontrolovat čistý strom.
3. **Teprve teď** vytvořit task branch.
4. Před každým krokem uložit `step_start_head`.
5. Při `increment-step` ověřit VŠE:
   - přesný `commit:` hash ve verify souboru,
   - `git cat-file -e <hash>^{commit}` (commit reálně existuje),
   - commit je dosažitelný z HEAD,
   - `HEAD != step_start_head` (krok něco skutečně commitnul),
   - aktuální branch odpovídá FSM stavu.

Tím se z dnešních „detektorů" (kontrola hex řetězce, kontrola přítomnosti verify
souboru) stanou skutečná **vynucení** — v souladu s principem #1
(`docs/plans/AID-v3-principles.md`): *Detector without Enforcement is Decoration.*
