# AID Control System v2 - E0 Control Topology Challenge

**Status:** E0 deliverable k PM schválení (povinné PŘED formálním AID plánem a před E1)
**Datum:** 2026-06-22
**Autor:** PM + AI
**Vstup:** `docs/AID-control-system-v2-unified-refactor-PLAN.md` §3.0 (5-mechanismový model C0-C4) a §E0
**Doprovodné artefakty:** `docs/design/control-topology.yaml`, `docs/design/failure-mode-control-matrix.json`
**Runtime dopad:** žádný (čistě design + rozhodnutí)

---

## 0. Účel a co E0 dokazuje (lidská řeč)

**Jednou větou:** E0 dokazuje daty, že cílový kontrolní systém potřebuje právě pět mechanismů (C0-C4), že každá známá historická chyba má v něm právě jednoho primárního majitele, a že přepsat CP1-CP6 do šesti nových systémů by bylo zbytečné zdvojení - a tím to zastavuje dřív, než se to stane.

**Proč E0 existuje.** Hlavní riziko refaktoru kontrolního systému není "málo kontrol". Je to **tichý nárůst kontrol bez nárůstu jistoty** - víc agentů, kteří čtou stejný diff se stejnou premisou a navzájem si potvrzují stejný omyl (correlated self-confirmation). E0 je adversariální brzda: každý mechanismus, mode, lens i agent dispatch musí projít **Control Necessity Testem** (§3.0 master plánu), jinak se nepřidá nebo se sloučí.

**Co E0 produkuje (tři artefakty):**
1. **Failure-mode → control matrix** - každá známá failure class → nejčasnější levný majitel C0-C4 → trigger → evidence → stop condition → negativní fixture (`failure-mode-control-matrix.json`).
2. **Control topology** - mechanismy, modes, lenses, compatibility aliasy, risk profily, dispatch budget (`control-topology.yaml`).
3. **Tento dokument** - overlap matrix dnešních kontrol, dispozice (keep/merge/convert/utility/remove) per checkpoint, cost model, negativní design fixtures, positive controls, a verdikt nad předběžným cílem.

**Co E0 NEdělá.** Neimplementuje. Nemění FSM ani skripty. Nevytváří formální AID plán. To přijde až po schválení tohoto E0 verdiktu.

---

## 1. Metoda: failure-class-first, ne checkpoint-first

E0 se nenavrhuje otázkou "jak vylepšit CP1-CP6". Návrhová osa je obrácená:

1. **Vyjmenuj odlišné failure classes** ze všech zdrojů (Doc-1, Doc-2, P048, reálné incidenty E-047-1/4/5, E-044, P045 + systémové díry dnešní implementace).
2. **Pro každou najdi nejčasnější levný enforcement point** - kdo ji umí chytit nejdřív a nejlevněji (plan-time > deterministicky > sémanticky > nezávislý audit).
3. **Přiřaď právě jednoho primárního majitele** mezi C0-C4. Sekundární catch je povolen, ale musí být explicitně označen jako *defense-in-depth*, ne jako druhá autorita.
4. **Aplikuj Control Necessity Test** na každý mechanismus/mode/lens. Co neprojde, se nepřidá nebo sloučí.

**Hierarchie levnosti enforcementu** (čím dřív vlevo, tím levněji a dřív):

```
C0 plan-time   >   C1 deterministic   >   C2 semantic LLM   >   C3 independent audit
(před psaním)      (skript, exit code)    (reviewer engine)      (fresh adversarial agent)
```

Pravidlo: **failure class patří nejlevnějšímu majiteli, který ji umí spolehlivě chytit.** Sémantický reviewer (C2) se nepoužije na to, co deterministicky chytí C1; C1 se nepoužije na to, co lze odmítnout už v plánu (C0).

---

## 2. Inventář failure classes

Konsolidace všech známých tříd selhání, na kterých se topologie testuje. ID `FC-NN` se používá v matici (`failure-mode-control-matrix.json`).

### 2.1 Plan-time třídy (nelze chytit po implementaci levně)

| ID | Failure class | Zdroj |
|---|---|---|
| FC-01 | Cyklus v grafu kroků skrytý mezi `Depends on` a prózou | P045 |
| FC-02 | Jeden identifier ve více sémantických doménách (index/ordinal/slot) | P045 |
| FC-03 | Reuse komponenty s vedlejšími efekty (immediate POST, reset) | P045 |
| FC-04 | Plánované volání/ORM pole neexistuje nebo patří jinému modelu | P045 |
| FC-05 | Unversioned dependency resolve na špatný major + version-specific API | P045 |
| FC-06 | Fail-open idempotency vs duplicate-proof success kritérium | P045 |
| FC-07 | Rozpor authority matrix (user decision vs spec vs plan vs AC vs runtime baseline) | Doc-1 §5.4 DG-12 |
| FC-08 | Producer-consumer ordering: consumer čte kontrakt dřív, než ho producer definuje | Doc-1 §6.1, E-047-1 |
| FC-09 | Kontrakt z brainstorm/Writer/Visual Companion se ztratí cestou k implementátorovi | systémová díra |

### 2.2 Deterministické delivery třídy (skript, exit code)

| ID | Failure class | Zdroj |
|---|---|---|
| FC-10 | Leaf package projde, root build selže | E-047-1 |
| FC-11 | Odstraněná závislost se zbývajícím produkčním importem (multer) | E-047-1 |
| FC-12 | Public kontrakt prázdný/placeholder, ale další fáze ho importuje (EpicSpec) | E-047-1 |
| FC-13 | Dependency tree nekonzistentní pod deklarovaným runtime (@types/express) | E-047-1 |
| FC-14 | Vacuous typecheck (jen shim/vite-env.d.ts) | E-047-1 |
| FC-15 | Framework-major upgrade → runtime regrese při startu (Express 4→5 route) | E-047-1 |
| FC-16 | Build-config reference na chybějící package (Vite manualChunks Radix) | E-047-1 |
| FC-17 | Leaf suites projdou, root command exit 1 (zero-test workspace) | E-047-1 |
| FC-18 | Compile OK, ale proces nenastartuje | E-047-1 |
| FC-19 | Path traversal sibling-prefix (evidence-secret) | E-047-1 |
| FC-20 | Feature exportovaná a unit-tested, ale shell ji nemountuje (unreachable) | E-047-5 |
| FC-21 | Generated link `/plan/` vs router `/plans/` (route nonconformance) | E-047-5 |
| FC-22 | DONE/release při pending child step, active counter, `compliance.overall:fail` | E-047-5 |
| FC-23 | Vizuální delta neaplikována / locked region změněn (P048 mechanical) | P048 |

### 2.3 Sémantické cross-boundary třídy (LLM reviewer)

| ID | Failure class | Zdroj |
|---|---|---|
| FC-24 | Transaction boundary: cleanup kolem flush, commit jinde (MinIO/SQL) | E-044 |
| FC-25 | Field lineage: výběr kontraktu nederivuje/nepersistuje DeliveryPoint | E-044 |
| FC-26 | Chybějící negative case: `moved_away` kontrakty přijaté přes zákaz | E-044 |
| FC-27 | Operation order / resource bound: 20MB guard až po načtení celého uploadu | E-044 |
| FC-28 | Requirement/test drift: test změní schválené 403 na 401 | E-044 |
| FC-29 | Response shape: server `message` vs UI `detail` (real provider→consumer) | E-044, E-047-5 |
| FC-30 | UI lifecycle: zavření modalu ponechá file/hidden state | E-044 |
| FC-31 | AC-to-test identity: "8 scénářů" ale dva povinné nahrazeny snazšími | E-044 |
| FC-32 | False empty/not-found: API outage → "Projekt nenalezen" | E-047-5 |
| FC-33 | Fallback existuje jen jako izolovaný hook, mounted app ho nevolá | E-047-5 |
| FC-34 | Data drop: analytics dropne reálné záznamy, synthetic fixtures projdou | E-047-4 |
| FC-35 | frontend_user_outcome: UI vypadá správně, ale nad reálnými daty neposkytuje hodnotu | P048 integrace, E-047-4/5 |

### 2.4 Systémové / proces třídy

| ID | Failure class | Zdroj |
|---|---|---|
| FC-36 | Auditor skóre přebije blocker (High finding ne-blocking) | dnešní `auditor.md:582` |
| FC-37 | Auditor neběží z čistého kontextu (korelace s implementátorem) | Doc-2 §8 |
| FC-38 | Curator má de-facto merge-influence (auto-approve) | dnešní `curator.md` |
| FC-39 | CP5 čte jediný boolean, neagreguje delivery/acceptance evidence | dnešní `aid-fsm.sh` |
| FC-40 | Reporter self-report test outcome bez runner provenance | dnešní `reporter.md` agent_tool |
| FC-41 | Review profil počítán jen z plánu, ne ze skutečného diffu | systémová díra |
| FC-42 | Stale evidence vázaná na jiný HEAD projde jako blokující precondition | Doc-1 §3.4 |
| FC-43 | `--force` vyrobí falešné `*_ready:true` bez auditovaného waiveru | Doc-1 §11.2 |
| FC-44 | PM dostane neúplný/optimistický handoff (blocker zamlčen prózou) | Doc-2, master §7.6 |

**Celkem 44 odlišných failure classes.** Plná matice (majitel, trigger, evidence, stop condition, negativní fixture, defense-in-depth) je v `failure-mode-control-matrix.json`. Sekce 3 shrnuje rozdělení.

---

## 3. Failure-mode → control matrix (souhrn)

Rozdělení 44 tříd podle primárního majitele. Detail per třída v JSON.

| Primární majitel | Failure classes | Počet | Zdůvodnění "nejčasnější levný point" |
|---|---|---|---|
| **C0 Plan Contract Gate** | FC-01..FC-08 | 8 | Jen plan-time; po implementaci už je oprava drahá (redesign za běhu) |
| **C1 Delivery Engine** | FC-10..FC-23, FC-29, FC-33, FC-34, FC-40, FC-41 | 19 | Deterministicky prokazatelné exit kódem/probe nebo candidate-time diffem; LLM by jen draze opakoval |
| **C2 Semantic Review Engine** | FC-09, FC-24..FC-28, FC-30..FC-32, FC-35 | 10 | Vyžaduje úsudek nad spotřebou kontraktu nebo chováním; deterministicky neuchopitelné |
| **C3 Independent Audit** | FC-37 (+ replay vzorku z C0-C2 u high profilu) | 1 primární | Nezávislá refutace korelovaného PASS; jiný vstup, jiný kontext |
| **C4 Release Policy** | FC-36, FC-38, FC-39, FC-42, FC-43, FC-44 | 6 | Deterministická agregace release stavu a dvoufázová ochrana PM handoffu; jediná release autorita |

**Defense-in-depth (sekundární catch, NE druhá autorita):**

| Failure class | Primární | Sekundární (defense-in-depth) | Proč obojí |
|---|---|---|---|
| FC-20 unmounted shell | C1 DG-13 (deterministic reachability) | C2 frontend_user_outcome | C1 chytí "není namountováno", C2 chytí "namountováno, ale nedává hodnotu" |
| FC-33 fallback | C1 DG-16 (forced-failure probe) | C2 behavior trace | C1 chytí "fallback se nespustil", C2 chytí "spustil, ale stav je nečestný" |
| FC-34 data drop | C1 DG-17 (independent oracle/no-drop) | C2 frontend_user_outcome | C1 chytí kardinalitu, C2 chytí význam nad reálnými daty |
| FC-36 score-vs-blocker | C4 (mechanická derivace blocking) | C3 (nezávislý nález) | C4 vynutí, C3 nezávisle potvrdí |

**Klíčové pozorování pro topologii:** žádná failure class nemá dva *primární* majitele. Kde se objevuje sekundární catch, je to vědomá defense-in-depth s jiným vstupem/úhlem - ne duplicitní reviewer nad stejným vstupem. To je přesně hranice, kterou Control Necessity Test hlídá.

---

## 4. Definice mechanismů C0-C4 a průchod Necessity Testem

Každý mechanismus prochází 7 body Control Necessity Testu (§3.0). Zde shrnuto; per-mode/lens detail v `control-topology.yaml`.

### C0 Plan Contract Gate
- **Unikátní failure class:** neproveditelný/nejednoznačný plán (FC-01..08). **Nelze chytit levněji později** - po implementaci je to redesign za běhu.
- **Pozn. k FC-09:** C0 vytváří pouze prerequisite - existenci a hash kontraktního manifestu. Primární důkaz spotřeby (item→change/evidence, restatement neplatí) vlastní C2 `mode=local` v EXECUTE a FSM jej vynucuje před `increment-step`.
- **Trigger:** před EPIC generací (FSM precondition).
- **Modes:** `structural` (deterministické: graf, identifier domény, schema completeness) + `semantic` (LLM plan review nad codebase groundingem).
- **Stop condition:** libovolný stop-rule blocker → EPIC generace blokována.
- **Negativní fixture:** P045 kompletní plán (všechny soubory existují) musí selhat na graph/identifier/reuse/call/dep/idempotency.
- **Positive control:** čistý jednoduchý plán bez cyklů a s existujícími voláními projde bez blocku.
- **Nezávislost:** ano - jediný mechanismus s přístupem k záměru před kódem.
- **Necessity verdikt:** PASS (keep_as_mechanism).

### C1 Delivery Engine
- **Unikátní failure class:** revize nejde sestavit/spustit/mechanicky prokázat, oracle odhalí ztrátu dat nebo candidate-time profil neodpovídá skutečnému diffu (FC-10..23, FC-29, FC-33, FC-34, FC-40, FC-41). **Deterministické** - LLM by jen draze a nespolehlivě opakoval exit kód/probe.
- **Trigger:** D0 po posledním kroku, D1 po fixech; per-check `required_when` dle profilu.
- **Pluginy/lenses:** build, typecheck, test, dep-consistency, removed-dep, runtime-startup, route-resolve, build-config-resolve, reachability, wire-shape, forced-failure fallback, `frontend_visual_fidelity` (P048), acceptance-struct, state-consistency (DG-07). Projektové gates jsou pluginy C1.
- **Profil resolver:** sdílená deterministická služba bez vlastní rozhodovací autority vytvoří plan-time profil; C1 jej nad candidate diffem přepočítá jako union. Nový surface profil rozšíří a invaliduje dotčené důkazy; C4 kontroluje freshness výsledného profilu.
- **Stop condition:** required check fail/unverifiable → `delivery_ready:false`.
- **Negativní fixture:** multer (FC-11), vacuous typecheck (FC-14), unmounted (FC-20).
- **Positive control:** docs-only změna → relevantní checks skip s důvodem, žádný blok.
- **Necessity verdikt:** PASS (keep_as_mechanism; je to nová deterministická vrstva, kterou dnešní systém nemá).

### C2 Semantic Review Engine
- **Unikátní failure class:** implementátor neprokáže spotřebu kontraktu nebo chování odporuje schválenému outcome napříč hranicemi (FC-09, FC-24..28, FC-30..32, FC-35). Vyžaduje úsudek - deterministicky neuchopitelné.
- **Trigger + modes:** jeden engine, jedno schema, čtyři režimy podle assembly pointu:
  - `local` (CP2 alias) - jen když profil/kontrakt vyžaduje, step diff;
  - `wiring` (IR-1 alias) - první runnable vertical slice;
  - `behavior` (IR-2 alias) - feature-complete candidate;
  - `final` (CP3 alias) - full diff + D0 + acceptance-evidence.
- **Lenses (sdílené napříč módy, aktivované profilem):** behavior trace, transaction boundary, field lineage, negative-case, operation-order, requirement-drift, UI-lifecycle, AC-to-test identity, false-empty distinction, fallback semantics, `frontend_user_outcome`.
- **Stop condition:** Critical/High finding → block + fix loop; mode-specific assembly point.
- **Sekvenční enforcement (mode=wiring):** nevyřešený Critical/High z `wiring` **blokuje increment-step pro následující kroky** téhož EPICu (FSM precondition, ne jen end-state check). Bez toho by `wiring` degradoval na další final review na konci a ztratil by smysl rané detekce.
- **Klíčové omezení:** strop rozhodovacích kol a provozní náklad jsou dvě různé veličiny. Jeden C2 mode = jedna rozhodovací autorita a jedno `semantic-review.json`, ale každé dílčí LLM volání se samostatně měří (`model_calls`, tokeny, wall time). Lenses se mohou fan-outovat, ne však zmizet pod označením "jedna autorita". Sloučení findings je deterministický bezztrátový union podle stabilních ID; agregátor nesmí snížit závažnost ani zahodit konflikt. Překročení profilového resource budgetu znamená `budget_exceeded` a PM waiver, ne tiché vynechání required lens.
- **Negativní fixture:** E-044 (transaction boundary, field lineage, AC-to-test, requirement drift). Response shape FC-29 ověřuje C1 DG-14.
- **Positive control:** lokální interní refactor s passing testy → 1 final review, žádné spurious blocky.
- **Necessity verdikt:** PASS jako jeden engine; CP2/IR-1/IR-2/CP3 jako samostatné systémy = REJECT (merge_as_mode).

### C3 Independent Audit
- **Unikátní failure class:** korelovaný PASS u rizikové dodávky - nikdo nezávisle nezkusil claim vyvrátit (FC-37). **Jiný vstup** (input manifest bez prior PASS shrnutí) **a jiný kontext** (fresh adversarial agent).
- **Trigger:** jen risk-triggered profily (high/mixed/security/data-loss/release-process). NE pro docs/low.
- **Kritický předpoklad risk-gatingu (oprava po topology challenge):** třídy, které dnes unikly i přes zelené testy (E-044: db mutation + object store + cross-layer response + persistence), **musí klasifikovat jako high**, jinak by medium profil ztratil jediný nezávislý sémantický check. Sdílený profile resolver a jeho candidate-time C1 enforcement (FC-41) proto mapují `data-loss | persistence-side-effect | cross-boundary` → high. E-044 je negative fixture, který to ověřuje.
- **Stop condition:** nezávisle potvrzený Critical/High → block.
- **Negativní fixture:** dodávka, kde všechny C0-C2 PASS, ale C3 replay highest-risk trace odhalí drop/wire/wiring defekt.
- **Positive control:** low-risk změna → C3 se vůbec nespustí (dispatch budget).
- **Nezávislost:** minimálně oddělený kontext/proces + hashed input manifest. C3 je provider-neutral a reportuje `independence_level: context_only|cross_model|cross_provider` spolu s provider/model provenance. Pro high-risk profil je preferovaný jiný provider/model než implementátor; profil může `cross_provider` vyžadovat a při nedostupnosti vrátit `unverifiable`, ne předstírat plnou nezávislost. Referenční cross-model/cross-provider backend je Codex CLI přes `codex exec`, ale smí se použít pouze když jej adapter mechanicky detekuje (`command -v codex`, `codex exec --help` / sanity run, auth OK). Nerozhoduje introspekce modelu typu "jsem CLI/IDE"; rozhoduje schopnost spustit samostatný `codex exec --ephemeral --sandbox read-only --ask-for-approval never` proces a získat schema-valid výstup svázaný s input manifestem.
- **Necessity verdikt:** PASS (keep_as_mechanism, ale risk-gated - ne always-on).

### C4 Release Policy
- **Unikátní failure class:** release přes neúplnou/stale evidence nebo přetrvávající blocker (FC-36, FC-38, FC-39, FC-42, FC-43, FC-44). **Deterministická agregace**, žádný LLM úsudek.
- **Dvě sekvenční precondition bez cyklu:** (A) C4 vytvoří `release-decision.json` jen z profile-required evidence; (B) PM brief generator z něj a ze stejné evidence vytvoří `pm-decision-brief.json`; (C) FSM nabídne MERGE pouze při `release_ready:true` **a** úspěšném `aid-pm-brief.sh --validate`. PM brief není vstupem do výpočtu `release_ready`, takže nevzniká cyklus `release-decision → brief → release-decision`.
- **Trigger:** před nabídkou MERGE.
- **Stop condition:** chybějící/stale required evidence nebo libovolný blocker → `release_ready:false`.
- **Negativní fixture:** parent DONE při pending child step / `compliance.overall:fail` → `release_ready:false`.
- **Positive control:** kompletní čistá evidence na current HEAD → `release_ready:true`.
- **Nezávislost:** ano - jediná release eligibility autorita.
- **Necessity verdikt:** PASS (keep_as_mechanism; CP5 = kompatibilní alias, ne LLM review).

---

## 5. Overlap matrix dnešních kontrol

Pro každý dnešní checkpoint/agent: vstupy, výstupy, historicky unikátní nález (co reálně chytil, co jiné nechytily) a kde se překrývá.

| Dnešní kontrola | Vstupy dnes | Výstup | Historicky unikátní nález | Překryv s |
|---|---|---|---|---|
| CP1 (+ deep L1/L2/L3) | plan obsah, codebase grounding | docs-review + adjudikátor | "named helper neexistuje" (P035), flow trace branch (P046) | nikdo jiný (jediný plan-time) |
| CP2 | step diff `HEAD~1..HEAD` | verifier pass/fail | lokální AC drift jednoho kroku | C2 final (širší scope) |
| CP3 code-review | full EPIC diff | verifier | integrované invarianty | C2 wiring/behavior, Auditor |
| CP3 security | full EPIC diff | verifier | OWASP nad diffem | C2 (security lens), C1 dep audit |
| IR-1/IR-2 (návrh Doc-1) | profil, prior IR | delta review | wiring/behavior na assembly pointu | C2 (jiný mode), CP3 |
| CP4 | applied C+A diff | verifier | regrese z auto-fixu | žádný unikátní nález - je to re-validace |
| CP5 | `blocking_findings` boolean | done-advance gate | nic (čte jeden boolean) | agregaci nedělá nikdo |
| Auditor | D0/gates/diff, 10 kategorií | audit-report + blocking | outcome/process napříč kategoriemi | C2 (částečně), project gates |
| Curator | step notes, backlog | proposals + disposition | dedup, lessons | žádná correctness autorita |
| Reporter | evidence | delivery report + test_outcome | runtime smoke (když reálně běží) | žádná correctness autorita |
| Simplifier | plan diff | proposals | zbytečná složitost | žádná correctness autorita |
| project gates | diff | gates_report | projekt-specifická policy | C1 plugins |
| Delivery Gate (Doc-1 návrh) | diff, profil | delivery-gate.json | build/runtime/wire deterministicky | C1 (JE C1) |
| P048 mechanical | UI contract, capture | verdict.json | visual fidelity | C1 plugin |

**Závěr overlap matice:** jediné kontroly s unikátním nezdvojeným nálezem jsou CP1 (plan-time), Auditor (nezávislý outcome), Delivery Gate (deterministická delivery) a agregace (kterou dnes nedělá nikdo). Všechno ostatní (CP2, CP3 code/security, IR-1/2, CP4, P048 mechanical, project gates) sdílí failure class nebo vstup s jiným - tedy kandidát na merge/convert, ne samostatný mechanismus.

---

## 6. Dispozice per dnešní checkpoint/agent

Explicitní rozhodnutí `keep_as_mechanism | merge_as_mode | convert_to_plugin | utility_only | remove` (E0 acceptance kritérium).

| Dnešní | Dispozice | Cíl v v2 | Zdůvodnění |
|---|---|---|---|
| CP1 | **keep_as_mechanism** | C0 | jediný plan-time majitel; unikátní failure class |
| CP1 deep L1/L2/L3 | **merge_as_mode** | C0 `semantic` lenses | zůstávají jako lenses uvnitř C0, ne 3 systémy |
| CP2 | **merge_as_mode** | C2 `mode=local` | žádná unikátní failure class mimo C2; jen scope |
| CP3 code-review | **merge_as_mode** | C2 `mode=final` | integrace = C2 final mode |
| CP3 security | **merge_as_mode** + **convert_to_plugin** | C2 security lens (risk-based) + C1 dep-audit plugin (deterministic) | sémantika do C2, deterministická dep část do C1 |
| IR-1 / IR-2 | **merge_as_mode** | C2 `mode=wiring` / `mode=behavior` | jeden engine, jiný assembly point |
| CP4 | **convert_to_plugin** | invalidace + re-run C1/C2 (žádný nový reviewer) | nemá unikátní nález; je to re-validace |
| CP5 | **keep_as_mechanism** (alias) | C4 Release Policy | agregace, ale deterministická, ne LLM |
| CP6 | **merge_as_mode** | fast profil C1/C2/C4 | žádná vlastní review implementace |
| Auditor | **keep_as_mechanism** (risk-gated) | C3 | nezávislý outcome; ale jen risk-triggered |
| Curator | **utility_only** | návrhy/backlog/lessons | bez correctness/release autority |
| Reporter | **utility_only** | komunikace + runtime smoke jako C1 plugin input | bez correctness/release autority |
| Simplifier | **utility_only** | plan-boundary údržba | volitelná, bez autority |
| project gates | **convert_to_plugin** | C1 pluginy | feed do delivery evidence, ne paralelní release |
| Delivery Gate (návrh) | **keep_as_mechanism** | C1 engine | nová deterministická vrstva |
| P048 mechanical | **convert_to_plugin** | C1 `frontend_visual_fidelity` | + C2 `frontend_user_outcome` lens |

**Žádná dnešní kontrola není `remove`d** - ale 9 z 16 je `merge_as_mode`/`convert_to_plugin`/`utility_only`, tedy přestávají být samostatné rozhodovací autority. To je jádro "5 mechanismů místo 13 vrstev / 6 nových systémů".

---

## 7. Cost model a dispatch budget

E0 acceptance kritéria omezují počet rozhodovacích kol per profil. Skutečný počet modelových volání a náklad měří `aid-control-metrics.sh` až v E10.

| Profil | C0 LLM kolo | C1 (deterministic) | C2 rozhodovací kola | C3 kolo | C4 (deterministic) | LLM autoritativních kol max | Očekávaný p50 / p95 |
|---|---|---|---|---|---|---|---|
| docs/trivial | 0 (jen struct) | 1 (link/struct) | **0** (skip s důvodem) | 0 | 1 | **0** | sekundy / <1 min |
| low, lokální | 1 | 1 (build/test) | **1** (final) | 0 | 1 | **2** | <1 min / minuty |
| medium / 1 hranice | 1 | 1 | **≤2** (wiring+final) | 0 | 1 | **≤3** | minuty / ~10 min |
| high / mixed / security / data-loss | 1 | průběžný | **≤3** (wiring+behavior+final) | **1** | 1 | **≤5** | ~10 min / ~25 min |

**Dva oddělené rozpočty:** (1) topology cap počítá rozhodovací kola: low ≤1 C2; medium ≤2; high ≤3 C2 + 1 C3. (2) resource budget počítá skutečná LLM volání, tokeny a wall time včetně lens fan-outů. E0 schvaluje první strop; číselný resource cap musí před cutoverem zkalibrovat E10 na reálných fixturech. Do té doby nelze tvrdit, že jedna autorita znamená jeden dispatch nebo nižší cenu. Žádná autorita nesmí být jeden obří prompt s 20+ lenses a fault injection najednou.

**Stav časových odhadů:** sloupce p50/p95 jsou **neověřený odhad**, ne naměřená data. Měří je až `aid-control-metrics.sh` v E10. Po opravě BREAK-1 je p95 vysokého profilu pravděpodobně **podhodnocený**, dokud se neměří reálná délka C2 s fan-outem lens evaluací nad živou fault injection.

**Srovnání s dneškem je zatím hypotéza.** Dnešní high cesta má typicky 9-12 LLM dispatchů. v2 omezuje počet rozhodovacích kol a odstraní paralelní release autority, ale lens fan-out může počet modelových volání znovu zvýšit. Tvrzení "levnější" smí vzniknout až z E10 telemetry nad stejnými fixturemi; E0 potvrzuje menší rozhodovací topologii, ne provozní úsporu.

---

## 8. Compatibility vrstva (číst staré CP názvy, nevytvořit novou autoritu)

E0 vyžaduje návrh, jak staré CP1-CP6 názvy číst, aniž pod nimi vznikne nová autorita.

**Princip:** CP názvy jsou **read-only aliasy** na C0-C4 modes/artefakty, ne samostatné enforcement entity.

- **Artefakty:** každý nese `artifact_type` (C0-C4 nativní) + volitelné `compat_alias` (`cp2`, `cp3`, `ir-1`...). GUI i FSM čtou `artifact_type`; `compat_alias` je jen pro lidskou orientaci a čtení staré evidence.
- **FSM preconditiony:** vázané na C0-C4 modes (`c2_mode=final` present & current), ne na soubor `verifier-output-cp3-code-review.md`. Stará jména se mapují přes tabulku v `control-topology.yaml` (`compatibility_aliases`).
- **Žádná nová autorita:** alias nesmí mít vlastní stop condition ani vlastní release vstup. `cp5` jako alias C4 nečte boolean - čte agregaci. `cp6` jako alias fast profilu nemá vlastní review engine.
- **Legacy evidence:** pre-v2 soubory (`verifier-output-cp3-*.md`) zůstávají čitelné read-only s `protocol_version: legacy`; nezakládají v2 autoritu (R8 forward-only).

---

## 9. Negativní design fixtures (duplicitní kontrola odmítnuta) + positive controls

E0 acceptance: nejméně jeden "duplicitní reviewer" odmítnut; nejméně jeden positive control per profil.

### 9.1 Negativní design fixtures (musí být ODMÍTNUTY)

| Návrh kontroly | Důvod odmítnutí (Control Necessity Test) |
|---|---|
| **"CP3.5 security re-review"** čte stejný diff se stejnými vstupy jako C2 security lens | bod 1+7: žádná unikátní failure class, žádný nezávislý vstup - jen opakuje C2 premisu. **REJECT (merge into C2 lens).** |
| **"Druhý Auditor"** re-runuje stejné traces jako C3 nad stejným manifestem | bod 7: korelovaný, ne nezávislý - sdílí input manifest i premisu. **REJECT.** |
| **"CP2 pro každý krok vždy"** i u čistě interních kroků bez kontraktu | bod 2: levněji chytí C2 final nad full diffem; per-step dispatch bez kontraktu nemá unikátní nález. **REJECT (profil-gated mode=local).** |
| **"P048 jako samostatná FSM release autorita"** (původní Step 8) | bod 1: failure class už vlastní C1 (visual fidelity); druhá release autorita porušuje jedno-autorita invariant. **REJECT (convert_to_plugin).** |
| **"LLM Delivery reviewer"** který slovně potvrdí, že build prošel | bod 2: deterministicky levnější v C1; LLM nad exit kódem je čistá duplikace. **REJECT.** |

### 9.2 Positive controls (musí PROJÍT bez blocku)

| Profil | Positive control | Očekávání |
|---|---|---|
| docs/trivial | oprava překlepu v README | C2/C3 skip s důvodem, C1 link-check pass, `release_ready:true` |
| low | interní refactor helperu s passing testy, žádná hranice | 1 C2 final pass, žádný spurious block |
| medium | nový endpoint + jeho jediný klient, oba s testy | 2 C2 (wiring+final) pass, C3 se nespustí |
| high | cross-package realtime UI s reálnými daty, vše korektní | ≤3 C2 + 1 C3 pass, `release_ready:true` bez waiveru |

**Smysl positive controls:** prokázat, že minimalizace na 5 mechanismů **neblokuje legitimní změnu** - tedy že redukce nezvýšila false-positive rate.

### 9.3 Profilové negative fixtures (profil sám nesmí být díra)

Nejlevnější profil je díra, pokud ho stačí špatně oklasifikovat. Tyto fixtures to hlídají:

| Fixture | Scénář | Očekávání |
|---|---|---|
| `docs_trivial_hides_behavior` | změna označená docs/trivial skrytě mění behaviorální surface (např. upraví handler) | candidate-time profil (FC-41 union) **povýší profil a vynutí C2 dispatch**; `c2_authorities_max:0` platí jen když detektor nenajde behaviorální dopad |
| `e044_must_classify_high` | E-044 styl (db mutation + object store + cross-layer response + persistence) | profil = **high** (data + cross-boundary + persistence triggery) → dostane C3; kdyby spadlo do medium, ztratí jediný nezávislý sémantický check |

---

## 10. Verdikt nad předběžným cílem

E0 musí potvrdit nebo vyvrátit předběžný cílový verdikt z master plánu daty z matice a Necessity Testu.

| Předběžný cíl | E0 verdikt | Opora |
|---|---|---|
| CP1 → C0 Plan Contract Gate | **POTVRZENO** | jediný plan-time majitel FC-01..08; C0 navíc vytváří manifest prerequisite pro FC-09 |
| Delivery Gate + project gates + P048 mechanical → C1 plugins | **POTVRZENO** | sdílejí deterministické failure classes FC-10..23/29/33/34/40/41 |
| CP2 + IR-1 + IR-2 + CP3 → modes jednoho C2 | **POTVRZENO** | žádná z nich nemá unikátní nález mimo scope/assembly point |
| Auditor → C3 jen risk-triggered | **POTVRZENO s upřesněním** | unikátní (nezávislost), ale dispatch budget ho omezuje na high+ profily |
| CP4 → invalidace/re-run, žádný nový reviewer | **POTVRZENO** | overlap matice: CP4 nemá unikátní nález |
| CP5 → C4 deterministická Release Policy | **POTVRZENO** | agregaci dnes nedělá nikdo; musí být deterministická |
| CP6 → fast profil C1/C2/C4 | **POTVRZENO** | žádná vlastní review implementace |
| Curator/Reporter/Simplifier → utility | **POTVRZENO** | žádná correctness/release autorita |

**Celkový E0 verdikt:** předběžná topologie C0-C4 je **podmíněně potvrzena jako nejmenší dostatečná sada rozhodovacích mechanismů vzhledem k současnému katalogu 44 známých failure classes**. Není to důkaz úplnosti vůči dosud nepozorovaným vadám ani důkaz reálné detekční kvality. Ten vznikne až spuštěním negativních fixtures, positive controls a historických kalibračních případů v E10. Provozní náklad a tvrzení "levnější než dnes" zůstávají do té doby neověřené.

**Výsledek nezávislého Control Topology Challenge (adversariální review, 2026-06-22).** Topologie obstála, ale review odhalil 4 opravitelné vady, které jsou nyní zapracované a NEjsou topology-breaking:

1. **BREAK-1 (nejdůležitější):** "jeden C2 dispatch projde všechny lenses" byl skrytý mega-prompt porušující princip "žádný obří prompt". **Opraveno:** topology cap počítá rozhodovací kola, zatímco resource accounting samostatně měří všechna fan-out model calls/tokeny/čas; findings se slučují deterministicky beze ztrát. **Vyžaduje T6.**
2. **BREAK-2:** FC-09 (consumption proof) bylo chybně přiřazeno plan-time C0. **Opraveno:** C0 vlastní jen existenci/hash manifestu; spotřeba se vynucuje až increment-step (EXECUTE) přes C2 local.
3. **BREAK-3:** kolaps CP2/IR/CP3 do modes ztratil vlastnost "wiring blokuje další kroky uvnitř EPICu". **Opraveno:** přidán enforcement invariant `c2_wiring_blocks_subsequent_steps` (FSM precondition).
4. **BREAK-4:** FC-44 (neúplný PM handoff) nesmí vytvořit kruhovou závislost. **Opraveno:** C4 nejprve vypočte release eligibility, potom vznikne brief a FSM samostatně vynutí jeho deterministickou validaci před nabídkou MERGE.

Plus zpřesnění: FC-29 byla demotována na jediného deterministického majitele C1; FC-34 má rovněž primárního C1 oracle vlastníka; E-044 musí klasifikovat jako high (jinak ztratí C3); doplněny C1 pluginy pro path traversal a forced-failure fallback a profilové negative fixtures (§9.3).

**Upřesnění oproti předběžnému cíli:** C3 (Auditor) je explicitně **risk-gated** - na docs/low/medium profilech se nespouští vůbec, což předběžný cíl naznačoval ("risk-based") a E0 to kvantifikuje (jen high/mixed/security/data-loss/release-process).

---

## 11. Otevřené body k PM schválení (před E1 a formálním AID plánem)

E0 acceptance: "PM schválí topology verdict a dispatch budget před E1 a před vytvořením formálního AID plánu." Tyto body potřebují tvé OK:

**T1 - Stropy rozhodovacích kol.**
Low ≤1 C2, medium ≤2 C2, high ≤3 C2 + 1 C3. ⭐ **Doporučení: schválit jako topology cap s PM-waiver výjimkou; neoznačovat jej jako strop skutečných dispatchů nebo ceny.**
*Důvod: bez stropu se "ještě jeden reviewer pro jistotu" plíživě vrátí.*

**T2 - C3 risk-gating práh.**
C3 (Auditor) běží jen na high/mixed/security/data-loss/release-process. ⭐ **Doporučení: schválit; medium a níž bez C3.**
*Důvod: nezávislý audit je nejdražší; na low/medium ho deterministické C1 + C2 final pokryjí.*

**T3 - Defense-in-depth seznam.**
Čtyři dvojice primární+sekundární (FC-20/33/34/36) zůstávají jako vědomá defense-in-depth. FC-29 response shape má jediného majitele C1; C2 semantic lens lze vrátit až s negativním fixturem, který C1 shape probe prokazatelně nechytí. ⭐ **Doporučení: schválit 4 dvojice; další přidat jen přes Necessity Test.**
*Důvod: FC-29 dnes dokládá stejný `message` vs `detail` mismatch oběma vrstvami, tedy duplicitu, ne nezávislý úhel.*

**T4 - Compatibility vrstva: read-only aliasy.**
Staré CP názvy jako `compat_alias`, žádná vlastní autorita. ⭐ **Doporučení: schválit; FSM/GUI vážou na C0-C4, ne na CP soubory.**
*Důvod: jinak pod starými názvy tiše vznikne šestý systém - přesně to, čemu E0 brání.*

**T5 - Dispozice CP3 security (split).**
CP3 security se dělí: sémantika → C2 lens (risk-based), deterministická dep-audit část → C1 plugin. ⭐ **Doporučení: schválit split.**
*Důvod: dependency vulnerability scan je deterministický (C1), threat-model úsudek je sémantický (C2) - jiná failure class, jiný majitel.*

**T6 - Dvojí účetnictví: autorita i skutečný resource cost.**
Stropy rozhodovacích kol se počítají v C2 modes; současně se povinně eviduje každé modelové volání, tokeny a wall time uvnitř fan-outu. Merge findings je deterministický, bezztrátový a nesmí downgradeovat závažnost. ⭐ **Doporučení: schválit tuto upravenou variantu; původní T6 neschvalovat, protože schovával libovolný počet volání pod jednu autoritu.**

---

## 12. Co E0 NEřeší (a kdy se to řeší)

- **Konkrétní schémata artefaktů** - to je E1 (protokol v2), ne E0. E0 jen jmenuje, který mechanismus co produkuje.
- **Implementace skriptů** - žádná; E0 je rozhodnutí o topologii.
- **Per-fáze executable plány** - vznikají z formálního AID roadmap plánu PO schválení E0.
- **Kalibrace na reálných UI selháních (E7-CAL)** - zůstává podmínkou P048 wiringu, mimo E0.

---

## 13. Další krok

1. **PM schválí** E0 verdikt (sekce 10) + otevřené body T1-T6 (sekce 11).
2. Teprve potom **formální AID roadmap plán** (jeden dokument pro celý v2, fáze E0-E11 jako EPIC markery, session prompts per fáze - viz rozhodnutí o roadmap formě).
3. Až následně generovat skutečné EPICy a implementovat (E1 první).

Doprovodné strojové artefakty: `docs/design/control-topology.yaml`, `docs/design/failure-mode-control-matrix.json`.

---

*E0 přijato PM 2026-06-22. Žádná změna runtime chování; implementace pokračuje podle formální roadmapy.*
