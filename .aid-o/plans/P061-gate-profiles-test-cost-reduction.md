---
id: P061
type: regular
status: closed
closed: 2026-08-14
closure_denominator: "E1-E5 required, E6 backlog (D1 wording, never six-of-six). Closed with E5 HALF delivered: D6 yes, D5 no — see Uzavření below. PM decision 2026-08-14, recorded as risk acceptance, not as delivery."
created: 2026-07-10
author: PM + AI
phase_of: AID Control System v2 (post-P060 speed/safety block; runs after P060, before or alongside E10 calibration per roadmap precondition)
roadmap_ref: docs/plans/AID-control-system-v2-roadmap.md
design_ref: .aid-o/work/interim-P061-gate-profiles.md (interim design; 3-agent independent adversarial review 2026-07-10, PM revision incorporating all 6 blockers, 1-agent independent confirmation of the revision 2026-07-10)
depends_on: "TVRDÁ precondition: P060 (E-060-1_2 + E-060-2_2) DONE + merged do main. STAV K 2026-07-10 (CP1-deep adjudikace): SPLNĚNO — `git merge-base --is-ancestor 87c4a9b HEAD` a `git merge-base --is-ancestor 4b51860 HEAD` oba potvrzeny jako ancestor, `CHANGELOG.md:6` obsahuje `## [2.54.0]`. Precondition 1 splněna, EPIC 1 může startovat."
risk: high
revision: v1.1 (2026-07-10 — CP1-deep adjudikace: verdict revise → 3 přijaté blokery (AB1 /aid-do post-impl disposition, AB2 plan_final dead-config rozpor, AB3 D6 chybějící behaviorální test) zapracovány; Precondition 1 status opraven ze zastaralého NENAPLNĚNO na SPLNĚNO)
---

# Plan: P061 — Risk-based gate profily a redukce nákladů na testy

## Uzavření (2026-08-14) — čti první

**P061 je uzavřený.** Ne proto, že se dodalo všechno, ale proto, že PM přijal
jeden jmenovaný zbytek. Rozdíl je zapsaný, ne zaokrouhlený.

**Jmenovatel.** D1 tohoto plánu vždycky říkal E1-E5 povinné, E6 backlog.
P062 ve své hlavičce tvrdí „všech šest EPICů" — **to je chyba P062**, ne
nesplněná podmínka P061. Při re-groundu P062 se opraví tam; nikdy se neuspokojí
nafouknutým počtem mergů.

**Stav po EPICech, ověřený proti kódu 2026-08-14 (v2.86.1), ne proti dokumentu:**

| EPIC | Rozhodnutí | Stav | Důkaz v kódu |
|---|---|---|---|
| E1 | D2 substrát + podlaha z plánu | dodáno | `lib/aid-gate-profile.sh`; registry `gate_profile_include`, `plan_gate_floor` |
| E2 | D4 risk-upgrade jako **vynucená** podmínka | dodáno | registry `risk_upgrade` — `GATES→DONE` riziko přepočítá a odmítne slabší profil, nejen doporučí |
| E3 | targeted selector | dodáno | `scripts/aid-select-tests.sh` |
| E4 | D3 + D9 distribuce a bezpečný upgrade | dodáno | `lib/aid-init-execution-yaml.sh` (`render_gate_profiles_block`, `append_gate_profiles_block`); odmítnutý upgrade nemění bajty (P080 krok 8). D3 drží **v tom smyslu, který D3 zakazuje**: žádný dodávaný seznam bran ani profilů neobsahuje self-host bránu — `defaults/execution.yaml` ani `defaults/execution-stacks/*` ta jména nenesou vůbec. Pod `defaults/` přežívají už jen v próze: popis v jednom schématu, jeden komentář, řádky registru a přejmenovávací seznam. Členství to není |
| E5 | D6 reálné místo spuštění profilu `release` | **dodáno** | `aid-plan-fsm.sh:4530` vyřeší `max(plan_final_required_profile, release)` a `:4619` ten profil **skutečně pustí** — `aid-run-gates.sh run-all … --profile "$effective_profile"`, a když spadne, plán zůstane v `PLAN_GATES`. Není to jen resolve. Plán připouštěl dvě cesty (`aid-release.sh` **nebo** pojmenovaná FSM release fáze); dodala se ta druhá |
| E5 | D5 `/aid-do` no-bypass | **NEDODÁNO → IMP-506** | Silněji než jen výčtem volajících: `/aid-do` **nespouští žádný AID skript** — v `commands/aid-do.md` není jediné volání `*.sh`. Nemůže se tedy ke sdílenému vyhodnocovači dostat ani nepřímo. Eskaluje podle velikosti úkolu, ne podle rizika |
| E6 | C1/FSM dedup | backlog, dle D1 | — |

**Jak byla ta tabulka prověřena.** Nezávislé cross-model kolo (Codex,
2026-08-14) dostalo tvrzení i důkazy a **tři ze čtyř označilo za silnější, než
co důkaz unese** — přesně to riziko, kvůli kterému se plány zavírají pohodlným
čtením. Kontrola tří napadených bodů dopadla takto: D6 vyšlo **silněji**, než
bylo napsáno (profil se nejen vyřeší, ale opravdu spustí, a jeho pád plán
zastaví), D5 taky **silněji** (`/aid-do` nespouští žádný skript, takže nejde
o neúplný výčet volajících), a D3 se **zúžilo na to, co doopravdy platí**:
členství v dodávaných seznamech, ne nepřítomnost tří řetězců kdekoli pod
`defaults/`. Znění výše je opravené na tuhle úroveň. Ta námitka byla správná
i tam, kde výsledek nakonec vyšel v náš prospěch.

**Co uzavření NEtvrdí.** Netvrdí, že Fast Mode měří riziko. Dokud platí
IMP-506, je vynucení rizika obejitelné volbou příkazu — `/aid-do` místo
`/aid-run`. Je to zapsané jako přijaté riziko PM, ne jako hotová práce, a
`AID-v3-principles.md` §1 na to má jméno: detektor bez vynucení na jedné ze
dvou vstupních cest.

**Co uzavření odemyká.** P062/E10 měl v hlavičce zámek „write-only, dokud není
P061 DONE+merged". Tím zámek padá — ale re-ground P062 musí ten zámek přepsat
poctivě: jmenovatel na E1-E5 a IMP-506 jako pojmenovaný vstup do kalibrace
(Fast Mode neposkytuje risk-profile události, které D9 chce měřit).

> **Závazná acceptance věta (čti první):**
> **„P061 smí zrychlit běžný gate cyklus JEN tehdy, když ochrany (plan-gate floor, automatický
> risk-upgrade na `full`, žádný self-host gate leak do consumer defaults, `/aid-do` no-bypass,
> reálný `release` invocation point, enforcement registry řádek) existují a mají test DŘÍV, než se
> libovolný default oslabí. Bootstrap Fast Lane smí zrychlit VÝSTAVBU P061 samotného, nikdy ne na
> úkor EPIC-boundary plné sady (`bats_fsm`+`bats_all`) nebo pre-merge `release` sady."**
>
> **Lidsky:** P061 mění gate systém, který rozhoduje, co je "hotovo". Přesně proto se to nesmí
> stavět narychlo bez záchranné sítě. Tenhle plán řeší napětí mezi "P061 má zrychlit testování" a
> "P061 se sám musí stavět bezpečně" tak, že staví ochrany PŘED zrychlením — a i "rychlý" bootstrap
> režim výstavby má povinné plné kontrolní body, ne nekonečné zrychlování.

## Klíčová rozhodnutí

- **D1 (pořadí je neměnné):** EPIC 1 (substrát + floor) → EPIC 2 (resolver) → EPIC 3 (selector) →
  EPIC 4 (self-host defaults weaken) → EPIC 5 (`/aid-do` + release invocation) → EPIC 6/backlog
  (C1/FSM dedup). EPIC 4 nesmí startovat před merge EPIC 2 A EPIC 3. Žádná zkratka „přeskoč rovnou
  na EPIC 4, ať je to rychle vidět" — to je přesně ten blokér, který PM revize opravila.
- **D2 (plan-gate floor + NOVĚ OBJEVENÝ prerequisite):** `plan.json.gates[]` musí být tvrdá podlaha
  (profil nesmí tiše vynechat plánem vyžádanou gate). **Ale:** dnešní `plan.schema.json` +
  `aid-epic-to-json.sh` mají `gates[]` napevno omezené na 4 obecné hodnoty
  (`tests_pass`/`lint_pass`/`security_scan_pass`/`docs_updated`) a **tiše zahazují** cokoli jiného
  při generování plan.json z EPIC.md. Self-host gate jména (`bats_all`, `bats_fsm`,
  `shell_pipeline_smoke`, budoucí `targeted_tests`) se do `plan.json.gates[]` touto cestou dnes
  nikdy nedostanou — takže "podlaha" by byla bez obsahu. Toto musí být první oprava v EPIC 1
  (viz Context/Grounding níže) — bez ní je EPIC 1 vlastní acceptance criterion netestovatelné.
- **D3 (consumer isolation):** `bats_fsm`/`bats_all`/`shell_pipeline_smoke`/`targeted_tests` nesmí
  jít do `plugins/aid-orchestrator/defaults/execution.yaml` (šablona kopírovaná `/aid-init` do
  každého nového projektu). Self-host membership žije jen v `.aid-o/config/execution.yaml`.
- **D4 (risk-upgrade má pojmenovaný mechanismus):** "high-risk upgraduje profil" není jen
  doporučení — je to FSM precondition v `GATES→DONE` (ne jen volba v `advance-to-gates`), s
  registry řádkem. Bez tohoto je to detektor bez vynucení (princip #1, `AID-v3-principles.md`).
- **D5 (`/aid-do` no-bypass):** Fast Mode používá STEJNÝ deterministický risk klasifikátor jako
  `/aid-run` (sdílená lib funkce z EPIC 2, ne duplicitní logika). Nízké riziko zůstává rychlé,
  vysoké riziko eskaluje na `/aid-run` nebo vyžaduje explicitní PM override evidenci.
- **D6 (release invocation je reálný, ne deklarativní):** profil `release` musí mít skutečné
  místo spuštění před tag/release — buď v `aid-release.sh`, nebo jako pojmenovaný FSM release
  precondition. Bez tohoto je `release` profil jen řádek v YAML, který nikdy nic nespustí.
- **D7 (registry):** každý nový detektor (profile selection, profile exclusion, plan-gate floor,
  risk-upgrade, `/aid-do` guard, release invocation) má řádek v enforcement registru s
  `type`/`source`/`instruction`/`severity`/`surface`. (Pozn.: `CLAUDE.md` odkazuje
  `docs/plans/AID-audit-2026-06/enforcement-registry.yaml`, který je dnes přesunutý do
  `docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml` — živý registr pro nové řádky
  je `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`, stejný soubor, který P060 Krok 9
  už rozšiřuje. P061 registry řádky patří tam.)
- **D8 (Bootstrap Fast Lane — dočasné, jen pro výstavbu P061):** Implementace P061 samotného
  neběží na plný `bats_all`+`shell_pipeline_smoke` po každém kroku. Běží na cílené testy per krok
  (viz vlastní sekce níže) s POVINNOU plnou sadou na hranicích EPICů a `release`-ekvivalentní sadou
  před finálním mergem do main. Tohle je politika pro TENTO plán, ne trvalá změna
  `execution.yaml` defaultů a ne precedens pro jiné plány.
- **D9 (project-level konfigurace a distribuce):** Profily jsou projektová konfigurace v
  `.aid-o/config/execution.yaml`, ne globální magie po update pluginu. Nové projekty je dostanou
  přes `/aid-init` composer (`defaults/execution-stacks/*` + `aid-init-execution-yaml.sh`), existující
  projekty se NESMÍ samovolně přepsat při update pluginu. P061 proto musí dodat bezpečný upgrade
  mechanismus/report: detekuj chybějící `gate_profile_defaults`/`gate_profiles`, nabídni PM
  nedestruktivní doplnění, nikdy nepřepiš ručně upravené gate příkazy. Jinak by P061 reálně
  zrychlil jen aid-orchestrator self-host a consumer projekty by zůstaly na starém chování.
- **D10 (co je už ověřené vs. co je nové v tomto dokumentu):** Design (profily, risk-upgrade
  pravidla, targeted mapping, EPIC pořadí, 6 PM ochran) prošel dvěma nezávislými koly review —
  považuj to za ověřené. **Nové a zatím neověřené** je: (a) gates-enum oprava (D2), (b) Bootstrap
  Fast Lane mechanismus (D8), (c) samotná formalizace do tohoto tvaru. Tyhle tři věci musí projít
  ještě jedním krátkým verify-plan kolem před GO (viz Validace níže) — nejsou automaticky kryté
  předchozím review, protože v předchozích kolech neexistovaly.

## Stakeholder Brief

AID dnes utrácí zbytečně moc wall-clock času na broad test suites na příliš mnoha místech.
Nezávisle přepočítáno ze 35-59 reálných `gates_report.json`: medián běhu GATES ~324-329s, P90
~466-469s. `shell_pipeline_smoke` sám o sobě ~7227-7527s napříč vzorkem a **timeoutuje nebo padá
v ~63 % běhů** navzdory tomu, že je `required:false`. `bats_all` ~3834-4939s. Cíl není "běžet
míň testů, protože nemáme trpělivost" — cíl je industry-standard risk-based test selection: běžet
nejmenší dostatečnou sadu pro riziko a fázi změny, plnou sadu rezervovat na vysoce rizikové a
release hranice.

Nezávislý posudek zaměřený přímo na srovnání s praxí (Google test-size taxonomie, ISTQB
risk-based testing, DORA trunk-based development) potvrdil, že tenhle směr JE industry-standard —
deterministické rozhodování (žádné LLM nerozhoduje o přeskočení) a asymetrie "review-profile smí
jen zpřísnit, nikdy oslabit" odpovídají praxi ve velkých systémech. Ruční tabulka soubor→test
místo grafové analýzy je na velikost tohoto repa přijatelný dluh, ne blokér.

## Context / Grounding

### Náklady (nezávisle přepočítáno 2026-07-10, dva agenti, konzistentní řádově)
- Medián GATES běhu: 324-329s. P90: 466-469s.
- `shell_pipeline_smoke`: 7227-7527s celkem, ~63 % běhů timeout (300s) nebo fail.
- `bats_all`: 3834-4939s celkem.
- `bats_fsm`: 911-985s celkem (nejlevnější z velké trojky, zůstává v `standard`).

### NOVĚ OBJEVENÉ: `plan.json.gates[]` dnes nemůže nést self-host gate jména

Toto zjištění vzniklo až při formalizaci tohoto plánu — ani interim dokument, ani žádné ze 4
předchozích nezávislých review kol ho nepokrylo, protože všechna se dívala na `execution.yaml` a
`aid-run-gates.sh`, ne na vrstvu, která `plan.json` vůbec VYRÁBÍ.

Ověřeno přímo v kódu:
- [`plugins/aid-orchestrator/defaults/templates/plan.schema.json`](plugins/aid-orchestrator/defaults/templates/plan.schema.json) —
  pole `gates[].items.enum` = přesně `["tests_pass","lint_pass","security_scan_pass","docs_updated"]`.
  Popisek pole tvrdí, že `aid-run-gates.sh` "reconciles each name against the gate definitions in
  execution.yaml" (naznačuje dynamickou validaci) — ale enum je natvrdo 4 hodnoty, popisek
  neodpovídá realitě.
- [`plugins/aid-orchestrator/scripts/aid-epic-to-json.sh:868`](plugins/aid-orchestrator/scripts/aid-epic-to-json.sh#L868) —
  `valid_gates="tests_pass lint_pass security_scan_pass docs_updated"` — stejná natvrdo daná
  čtveřice, použitá při extrakci `## DoD Gates` sekce z EPIC.md.
- Tamtéž o pár řádků dál: `if [[ "$is_valid" -eq 1 ]]; then ... fi` — gate jméno MIMO tuhle čtveřici
  je **tiše přeskočeno** (`is_valid=0` → žádný řádek do `gates_json`, žádná chyba, žádné varování).
- Stejný natvrdo daný seznam je i ve validačním jq filtru (`~:948`), použitý pro post-hoc kontrolu.

**Důsledek pro P061:** EPIC 1 vlastní acceptance criterion ("plán deklaruje
`gates:["bats_all"]`, aktivní profil ji vynechá → gate poběží nebo report failne s
`plan_gate_profile_excluded`; nikdy tichý zelený skip") je dnes **netestovatelný, protože
`plan.json` nemůže obsahovat `"bats_all"` vůbec** — zmizí dřív, než se k reconciliační logice
dostane.

**Nezávislé potvrzení:** P060 vlastní plán (`.aid-o/plans/P060-pre-e10-control-hygiene.md`,
Context sekce) dokládá totéž z druhé strany: *"všech 15 posledních plan.json v tomto repu
deklaruje gates:["docs_updated"]"* — `docs_updated` je JEDINÉ self-host gate jméno, které náhodou
leží uvnitř té čtveřice. Nikdy tam nebyl důvod zkusit `bats_all`, protože by zmizelo bez stopy.

**Rozsah mimo P061:** tohle není jen self-host bug. Jakýkoli consumer projekt s vlastním gate
jménem mimo tu čtveřici má stejnou tichou ztrátu. Oprava má hodnotu nezávisle na P061, ale P061 ji
potřebuje jako tvrdý prerequisite pro vlastní EPIC 1.

## Goal

Nahradit "spouštěj všechno vždy" deterministickým, rizikově řízeným výběrem testů — s tvrdou
podlahou pro plánem vyžádané gaty, automatickým zpřísněním pro rizikové změny, a beze zbytku
kontrolovaným `/aid-do` a release invocation bodem. Běžný EPIC GATES median pod 150s, bez ztráty
pokrytí rizikových změn.

## Scope

**In scope:** `aid-run-gates.sh`, `aid-fsm.sh` (`advance-to-gates` + `GATES→DONE` precondition),
`plan.schema.json` + `aid-epic-to-json.sh` (gates enum oprava), `.aid-o/config/execution.yaml`
(self-host defaults — POUZE po EPIC 2+3), `plugins/aid-orchestrator/defaults/execution.yaml`
(POUZE substrát, nikdy self-host gate jména), nový `scripts/aid-select-tests.sh`, nová
`scripts/lib/aid-gate-profile.sh`, `commands/aid-do.md`, `aid-release.sh` nebo named FSM release
precondition, `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`,
`scripts/lib/aid-init-execution-yaml.sh`, `defaults/execution-stacks/*.yaml`, a dokumentovaný
nedestruktivní upgrade/report pro existující projektové `.aid-o/config/execution.yaml`.

**Out of scope:** C1/FSM duplicate suppression (EPIC 6/backlog — je to follow-up, ne blokující),
plnohodnotné projekt-custom profile UI, změna E10/E11 release authority, LLM rozhodování o výběru
testů v v1. Jednoduchá nedestruktivní migrace/report profilů pro existující projekty JE in-scope
kvůli D9; není to UI.

## Preconditions (TVRDÉ — run nesmí začít, dokud vše neplatí)

1. **P060 DONE + merged do main.** STAV K 2026-07-10 (CP1-deep adjudikace): **SPLNĚNO.**
   Nezávisle ověřeno adjudikátorem: `git merge-base --is-ancestor 87c4a9b HEAD` (E-060-1_2 merge)
   a `git merge-base --is-ancestor 4b51860 HEAD` (E-060-2_2 merge) oba potvrzeny jako ancestor;
   `CHANGELOG.md:6` obsahuje `## [2.54.0]`. Původní "NENAPLNĚNO" status byl zastaralý k okamžiku
   psaní plánu — main mezitím postoupil.
2. Plugin cache stabilní (cache controller == post-merge main; force-refresh dle `CLAUDE.md`,
   pokud ne).
3. Checkout na main, clean.
4. **Gates-enum oprava (D2) je PRVNÍ commit EPIC 1**, ne paralelní vedlejší úkol — zbytek EPIC 1 na
   ní závisí.
5. **EPIC 4 nestartuje** dokud EPIC 2 A EPIC 3 nejsou merged do main a cache resynced proti
   post-EPIC-3 main.

## Bootstrap Fast Lane — implementační politika pro výstavbu P061

Platí VÝHRADNĚ pro implementaci EPICů 1-6 tohoto plánu. Není to změna `execution.yaml` defaultů a
není to precedens pro jiné plány.

**Krok-level (per commit uvnitř EPICu):**
- Spusť POUZE cílený bats soubor mapovaný na dotčený skript, podle mapovací tabulky z interim
  dokumentu (§Targeted Test Selector) — aplikováno ručně, dokud EPIC 3 nedodá automatizaci.
  Příklad: dotyk `aid-run-gates.sh` → `test-aid-run-gates.bats`; dotyk `aid-fsm.sh` →
  `test-aid-fsm.bats`.
- VŽDY navíc spusť `bats_fsm` bez ohledu na konkrétní mapování — je nejlevnější (911-985s/35-59
  běhů ≈ desítky sekund/běh) a P061 samo je FSM/gate-adjacent práce.
- Toto je již reálné zrychlení i pro rizikové soubory: dnešní default spouští CELOU `bats_all`
  (všechny bats soubory) na každý commit; cílený soubor je užší, ne nulový.

**EPIC-boundary (jednou, na konci každého z EPICů 1-6, před merge do main):**
- Spusť plnou sadu: `bats_fsm` + `bats_all` (full-ekvivalent). Bez výjimky — ani "fast lane" ani
  vysoké riziko soubor nesmí obejít tuhle hranici.

**Finální hranice (před mergem CELÉHO P061 plánu, po posledním EPICu):**
- Spusť `release`-ekvivalent: `bats_fsm` + `bats_all` + `shell_pipeline_smoke` (dej `smoke` větší
  timeout nebo běž na pozadí vzhledem k jeho 63% timeout rate — ale spusť ho, nepřeskakuj tiše).

**Evidence povinnost:** každý krok, který NEspustí `bats_all`, zapíše jednořádkové zdůvodnění do
step evidence (jaký cílený test běžel místo toho a proč) — ručně, dokud `profile_excluded`
mechanismus z EPIC 1 nexistuje. Jakmile EPIC 1 landne (`--profile` flag existuje), EPIC 2/3
mohou přejít z ruční konvence na reálný `--profile targeted`/`--profile standard` flag — to je
zároveň živé dogfooding vlastního výstupu EPIC 1, preferuj to nad ruční konvencí, jakmile je k
dispozici.

**Bez výjimky:** vysoce rizikové soubory (viz Risk Upgrade Rules v interim dokumentu — `aid-fsm.sh`,
`aid-run-gates.sh`, release-policy, evidence-verify, schemas, policies, agents) NEJSOU vyňaty z
EPIC-boundary požadavku. Fast lane zužuje krok-level náklady, nikdy neruší EPIC-boundary plnou sadu.

**Release-policy surface rule (přidáno 2026-07-11, po test-cost hotfixu `test-release-policy.bats`):**
`test-release-policy.bats` je i po zrychlení (viz CHANGELOG `[Unreleased]`) ~4-5 min real-fixture
integrační sada. Na **krok-level cíleném testu** (ne na EPIC-boundary!) se spouští JEN když krok
mění release-policy surface:
- `plugins/aid-orchestrator/scripts/aid-release-policy.sh`
- `plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats`
- `plugins/aid-orchestrator/scripts/aid-evidence-verify.sh`
- `plugins/aid-orchestrator/defaults/schemas/release*`
- `plugins/aid-orchestrator/defaults/schemas/aid-protocol-v2.schema.json`
- `plugins/aid-orchestrator/scripts/tests/fixtures/release-policy/**`

Bootstrap check (dočasný, ruční, dokud EPIC 3 nedodá `aid-select-tests.sh`):
`scripts/tests/release-policy-surface-check.sh <changed-path>...` — exit 0/"relevant" = spusť
sadu; exit 1/"not-relevant" = nespouštěj. Fail-safe default (žádné cesty na vstupu) = "relevant"
(spusť). Pokryto `test-release-policy-surface-check.bats` (7 scénářů vč. negativního
`aid-run-gates.sh` a pozitivního `aid-release-policy.sh` příkladu).

**Toto NEMĚNÍ EPIC-boundary ani release-boundary požadavek výše** — `bats_all` na hranici EPICu
běží vždy celý, bez ohledu na surface (D8 "bez výjimky" beze změny). Pravidlo šetří jen krok-level
cílené testy mezi jednotlivými commity uvnitř EPICu.

## Implementation Steps

**EPIC 1: Gate profile substrát + plan-gate floor (+ gates-enum prerequisite) (Steps 1-6)**

**Objective:** Přidat profile-aware spouštění gatů beze změny defaultního chování, dokud config
neopt-inuje — a NEJDŘÍV opravit `plan.json.gates[]`, aby vůbec mohlo nést netriviální jména.

> Poznámka k dekompozici (přidáno při EPIC generaci): EPICy 2-6 zůstávají v Files/Deliverables
> prose formě a dostanou vlastní `### Step N:` dekompozici až při generování jejich EPIC.md (D1 —
> sekvenční pořadí stejně brání startu EPICu 2 před merge EPICu 1, takže není důvod detailně
> specifikovat implementační kroky EPICů, které nemohou začít dřív).

### Step 1: Gates-enum oprava — plan.schema.json + aid-epic-to-json.sh (PRVNÍ commit, Precondition 4)

**Objective:** `plan.json.gates[]` musí umět nést libovolné gate jméno (ne jen tvrdou čtveřici) —
bez tohoto je zbytek EPICu 1 netestovatelný (viz Context/Grounding D2).

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.schema.json` — `gates[].items` z
  fixního `enum` na buď rozšířený enum (self-host + generický seznam), nebo (doporučeno) volný
  `string` s poznámkou, že skutečná validace je dynamická proti `execution.yaml` v
  `aid-run-gates.sh` (souhlasí s existujícím popiskem pole).
- Modify: `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh` (oba výskyty: extrakční filtr
  `~:868` i validační jq `~:948`) — jméno mimo (rozšířený) seznam už není tiše přeskočené, ale buď
  propuštěné do `gates_json` s pozdější dynamickou validací, nebo fail-loud s konkrétní chybou
  (NIKDY tichý `continue`). **Bonus nález z validace tohoto plánu:** post-hoc validační jq na
  `~:997` (`[valid_gates[] | select(. == .)]`) je dnes mrtvý no-op — `. == .` je vždy pravda
  (element porovnaný sám se sebou), takže "invalid gate" se nikdy nevyemituje bez ohledu na vstup.
  Oprav i tohle (mělo by být `select(. == $gate)` nebo ekvivalent proti skutečné hodnotě).
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — scénář: fixture
  EPIC.md s `## DoD Gates: - bats_all` → `plan.json` obsahuje `"bats_all"` v `gates[]`.

**Acceptance Criteria:**
- [ ] AC1 (plan-level, cmd-check): fixní 4-hodnotový enum v `plan.schema.json` odstraněný/rozšířený.
- [ ] Fixture roundtrip: EPIC.md s netriviálním gate jménem → `plan.json.gates[]` ho obsahuje.
- [ ] Mrtvý `select(. == .)` no-op opraven a skutečně zachytí invalid gate v testu.

**Effort:** S
**AID Role:** backend

### Step 2: aid-run-gates.sh — --profile flag, gate_profiles parsing, profile_excluded

**Objective:** Runner umí spustit jen podmnožinu gatů podle aktivního profilu a transparentně
zaznamenat, co vynechal a proč.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` — `--profile <name>` flag,
  `gate_profiles` parsing z `execution.yaml`, `profile_excluded` skip řádky, `profile`/
  `profile_source`/`profile_reason`/`excluded_gates` v `gates_report.json`. Neznámý profil /
  nedefinovaná gate v profilu = fail-loud (exit ≠ 0). Legacy `execution.yaml` bez `gate_profiles`
  → chování identické s dneškem (zpětná kompatibilita).
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — min. 3 nové
  scénáře pro `profile_excluded` (fixture s `shell_pipeline_smoke` vyňatým pod `standard` doběhne
  bez čekání na timeout; `required:false` gate uvnitř profilu pořád běží; vyňatá required gate
  nefailuje run, zapíše `profile_excluded`; neznámý profil/gate → exit ≠ 0).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádky pro
  `profile_selection`, `profile_exclusion`.

**Acceptance Criteria:**
- [ ] AC2 (plan-level, CHECKPOINT 1 dílčí): ≥3 nové `@test` scénáře pro `profile_excluded`.
- [ ] Legacy execution.yaml bez profilů → bit-identické chování s dneškem (regresní test).
- [ ] Registry řádky `profile_selection`, `profile_exclusion` existují.

**Effort:** M
**AID Role:** backend

### Step 3: aid-fsm.sh — plan-gate floor enforcement (plan_gate_profile_excluded)

**Objective:** `plan.json.gates[]` je tvrdá podlaha — profil nesmí tiše vynechat plánem
vyžádanou gate.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — plan-required floor: `plan.json.gates[]`
  se sloučí do aktivního profilu jako mandatory přídavek; pokud profil gate vynechává, buď se
  vynutí běh, nebo report failne s `plan_gate_profile_excluded` (nikdy tichý skip).
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — CHECKPOINT 1
  scénář: fixture plán deklaruje `gates:["bats_all"]`, aktivní profil ji vynechává → gate BUĎ
  proběhne vynuceně, NEBO report failne s `plan_gate_profile_excluded`.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádek pro
  `plan_gate_floor`.

**Acceptance Criteria:**
- [ ] **CHECKPOINT 1:** viz EPIC-level Acceptance níže — tenhle step ho dodává technicky.
- [ ] Registry řádek `plan_gate_floor` existuje a je pokrytý testem.

**Effort:** M
**AID Role:** backend

### Step 4: Dokumentace — pipeline.md, aid-run.md

**Objective:** `--profile` flag a floor chování jsou zdokumentované dřív, než EPIC 2/5 na nich
staví.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md`, `plugins/aid-orchestrator/commands/aid-run.md`
  — dokumentace `--profile` a floor chování.

**Acceptance Criteria:**
- [ ] `pipeline.md` a `aid-run.md` popisují `--profile` flag a floor sémantiku konzistentně s
  implementací Steps 2-3.

**Effort:** S
**AID Role:** docs-writer

### Step 5: Generický profilový substrát pro nové projekty

**Objective:** `/aid-init` na nový projekt vytvoří profily bez self-host gate jmen (D3).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh`, `plugins/aid-orchestrator/defaults/execution-stacks/*.yaml` — generický profilový substrát pro
  nové projekty. Musí používat jen gate jména, která daný stack composer opravdu vytvoří
  (`ts_test`, `py_test`, `go_test`, ...), nikdy self-host `bats_*`.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` — fixture scénář pro
  Acceptance Criteria níže.

**Acceptance Criteria:**
- [ ] Nový fixture TypeScript projekt přes `compose_execution_yaml` obsahuje profilový blok, ale
  neobsahuje `bats_fsm`, `bats_all`, ani `shell_pipeline_smoke`.
- [ ] AC7 (plan-level, negativní kontrola, prochází už dnes i po tomto stepu): plugin defaults
  nikdy neobsahují self-host gate jména.

**Effort:** M
**AID Role:** backend

### Step 6: Existující projekt — nedestruktivní upgrade/report (D9)

**Objective:** Existující projektový `execution.yaml` se při plugin update nepřepíše; upgrade
path je explicitní, reportovaný a PM-potvrzený.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-init.md`, `plugins/aid-orchestrator/commands/aid-setup.md`
  nebo přidat helper — existující projekt s vlastním `execution.yaml` dostane report +
  PM-confirmed nedestruktivní doplnění profilového bloku; plugin update sám od sebe existující
  config nepřepisuje.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` — fixture scénář pro
  Acceptance Criteria níže.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` — deterministické
  byte-preserving additive-merge funkce, reuse `detect_stacks`/`stack_gate_names` z Kroku 5.

**Acceptance Criteria:**
- [ ] Existující fixture `execution.yaml` s ručně upraveným gate příkazem není přepsaný; upgrade
  pouze navrhne/doplní chybějící profilový blok po PM potvrzení.

**Effort:** M
**AID Role:** backend

**Acceptance (EPIC-level, vč. MANDATORY CHECKPOINT 1):**
- [ ] Fixture s `shell_pipeline_smoke` vyňatým pod `standard` doběhne bez čekání na timeout.
- [ ] `required:false` gate uvnitř profilu pořád běží a zůstává advisory.
- [ ] Vyňatá required gate nefailuje run, ale zapíše `profile_excluded`.
- [ ] Neznámý profil → exit ≠ 0. Nedefinovaná gate v profilu → exit ≠ 0.
- [ ] Legacy `execution.yaml` bez profilů → chování identické s dneškem.
- [ ] **CHECKPOINT 1:** fixture EPIC.md s `## DoD Gates: - bats_all` vyrobí `plan.json` obsahující
  `"bats_all"` v `gates[]` (ne tiše prázdné). Fixture plán deklaruje `gates:["bats_all"]`, aktivní
  profil ji vynechává → gate BUĎ proběhne vynuceně, NEBO report failne s
  `plan_gate_profile_excluded` — nikdy tichý zelený skip.
- [ ] Nový fixture TypeScript projekt přes `compose_execution_yaml` obsahuje profilový blok, ale
  neobsahuje `bats_fsm`, `bats_all`, ani `shell_pipeline_smoke`.
- [ ] Existující fixture `execution.yaml` s ručně upraveným gate příkazem není přepsaný; upgrade
  pouze navrhne/doplní chybějící profilový blok po PM potvrzení.

**Fast-lane test pro tento EPIC:** `test-aid-run-gates.bats` + `bats_fsm` po každém commitu (oba
soubory jsou přímo dotčené); plný `bats_fsm+bats_all` na konci EPICu před merge.

---

**EPIC 2: Phase/risk profile resolver PŘED oslabením defaultů (Steps 7-8)**

**Objective:** Zvolit profil automaticky podle fáze a rizika — a udělat to DŘÍV, než cokoliv sníží
self-host defaulty (D1).

> **CP1-deep C0 nálezy (advisory, EPIC 1 review), povinné vyřešit v tomto EPICu, ne obejít:**
> (a) žádná EPIC/step tady definovaná hierarchie/pořadí mezi profily (`quick`/`targeted`/
> `standard`/`full`/`release`) pro CHECKPOINT 2's "profil ≥ risk-required profil" porovnání —
> Step 1 níže to musí explicitně definovat (ne nechat implicitní). (b) sdílený resolver musí mít
> jasně definovaný vstupní kontrakt, když `fsm-state.yaml` NEEXISTUJE (volání z budoucího EPIC 5
> `/aid-do`, které fázi/`done_phase` nemá) — nezávisle nalezeno 2× v CP1-deep review; Step 1 musí
> tenhle "no FSM state" case explicitně ošetřit (guard, ne crash), i když EPIC 5 samo přijde až
> později.

### Step 7: `aid-gate-profile.sh` — sdílená risk-klasifikační funkce + profile ordering

**Objective:** Vytvořit resolver, který ze changed paths + fáze/rizika vybere profil, s explicitní
hierarchií profilů a bezpečným chováním bez `fsm-state.yaml`.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-gate-profile.sh` — sdílená risk-klasifikační
  funkce (changed paths → risk level), volaná z `aid-fsm.sh` I z budoucího EPIC 5 `/aid-do`.
  Inputs: changed paths, `fsm-state.yaml` fáze/`done_phase` (POKUD existuje — guard, ne crash,
  když ne, viz CP1-deep nález (b) výše), final-EPIC/plan boundary marker (pokud dostupný — pozn.
  `plan.json` dnes NEMÁ epic-index/total-epics pole; pokud tahle signalizace není dodána,
  `plan_final` se v v1 NEPOUŽÍVÁ a spoléhá se na high-risk path upgrade + `release` boundary
  místo toho — rozhodni při implementaci, nevymýšlej fiktivní pole), manual env override,
  `review-profile.json` smí JEN zpřísnit, nikdy zmírnit. **Explicitní profile ordering** (CP1-deep
  nález (a)): definuj konkrétní hierarchii (např. `quick=0 < targeted=1 < standard=2 < full=3 <
  release=4`) jako pojmenovanou funkci/tabulku v tomhle souboru — to je jediné místo, které
  CHECKPOINT 2's "profil ≥ risk-required profil" porovnání může použít.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-profile.bats` — testy
  na resolver samotný (risk klasifikace, profile ordering porovnání, no-fsm-state guard).

**Acceptance Criteria:**
- [ ] Docs-only EPIC volí `quick`.
- [ ] Obyčejný script EPIC volí `standard`/`targeted+standard`.
- [ ] Release boundary volí `release`.
- [ ] Manual upward override funguje; manual downward override pro high-risk vyžaduje explicitní
  waiver/force evidenci.
- [ ] Profile ordering funkce/tabulka existuje a je otestovaná (`quick < targeted < standard <
  full < release`).
- [ ] Resolver volaný bez `fsm-state.yaml` (simulace `/aid-do` kontextu) nekrashuje, vrací
  definované chování (ne undefined/error).

**Effort:** M
**AID Role:** backend

### Step 8: `aid-fsm.sh` wiring — FSM vynucení risk-upgrade (D4) + registry

**Objective:** `advance-to-gates` volá resolver; `GATES→DONE` precondition FSM skutečně VYNUTÍ
profil ≥ risk-required (ne jen doporučí).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (`advance-to-gates`) — volá resolver ze
  Step 1; `GATES→DONE` precondition ověří, že použitý profil ≥ risk-required profil (pomocí
  ordering funkce ze Step 1) — ne jen že resolver vybral správně — FSM to i VYNUTÍ (D4).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádek pro risk-upgrade
  mechanismus (FSM precondition, ne jen advisory).
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — CHECKPOINT 2
  fixture (viz Acceptance níže).

**Acceptance Criteria:**
- [ ] Rizikový path nemůže dokončit pod `quick` nebo slabým `standard` omylem — FSM precondition to
  zablokuje, ne jen resolver doporučí.
- [ ] **CHECKPOINT 2:** fixture změna `aid-fsm.sh` NEBO `aid-run-gates.sh` → resolver vrací `full`;
  pokus o `GATES→DONE` s nižším profilem na této změně → FSM precondition fail (ne jen warning).
- [ ] Registry řádek pro risk-upgrade mechanismus existuje a je pokrytý testem.

**Effort:** M
**AID Role:** backend

**Acceptance (EPIC-level, vč. MANDATORY CHECKPOINT 2):**
- [ ] Docs-only EPIC volí `quick`.
- [ ] Obyčejný script EPIC volí `standard`/`targeted+standard`.
- [ ] Release boundary volí `release`.
- [ ] Manual upward override funguje; manual downward override pro high-risk vyžaduje explicitní
  waiver/force evidenci.
- [ ] Rizikový path nemůže dokončit pod `quick` nebo slabým `standard` omylem — FSM precondition to
  zablokuje, ne jen resolver doporučí.
- [ ] **CHECKPOINT 2:** fixture změna `aid-fsm.sh` NEBO `aid-run-gates.sh` → resolver vrací `full`;
  pokus o `GATES→DONE` s nižším profilem na této změně → FSM precondition fail (ne jen warning).
- [ ] Registry řádek pro risk-upgrade mechanismus existuje a je pokrytý testem.

**Fast-lane test pro tento EPIC:** `test-aid-gate-profile.bats` + `test-aid-run-gates.bats`
(integrace s floor z EPIC 1) + `bats_fsm` po každém commitu; plný `bats_fsm+bats_all` na konci
EPICu.

---

**EPIC 3: Targeted test selector (Steps 9-10)**

**Objective:** Nahradit "žádné pokrytí" cíleným, deterministickým pokrytím — než se cokoliv
self-host oslabí (proto před EPIC 4).

**Initial mapping** (z interim dokumentu, beze změny): `aid-run-gates.sh`→
`test-aid-run-gates.bats`; `aid-plan-diff.sh`→`test-plan-diff.sh`; `aid-release-policy.sh`→
release-policy bats filtr; `aid-fsm.sh`→`test-aid-fsm.bats`; `aid-prefilter.sh`→
`test-aid-prefilter.bats`; `aid-evidence-verify.sh`→`test-evidence-verify.sh`;
`defaults/schemas/**`→`test-protocol-validate.sh`; `defaults/policies/delivery-gate.yaml`→delivery
gate testy; `lib/ui-fidelity/**`→ui-fidelity testy.

**Neznámá produkční cesta — rozhodnutí (D-selector-1):** `aid-select-tests.sh` mapuje
`unverifiable` na `fail` přes non-zero exit code + čitelný `reason` string v JSON výstupu
("unverifiable: unknown production path <path> — upgrade to standard/full profile"). `aid-run-gates.sh`
si ponechává jen `pass`/`fail`/`skip` (žádná nová hodnota výsledku, žádný zásah do
`aid-run-gates.sh` samotného) — selector je jen další gate command, jehož exit code
`aid-run-gates.sh` už dnes umí zaznamenat.

### Step 9: `aid-select-tests.sh` — cílený test selector + vlastní testy

**Objective:** Vytvořit selector, který ze changed paths vybere a rovnou spustí odpovídající bats
testy podle Initial mapping výše, s deterministickým chováním pro neznámé produkční cesty
(D-selector-1) a pro docs-only změny.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-select-tests.sh` — čte changed paths (git diff
  proti base ref, nebo explicitní seznam na vstupu), aplikuje Initial mapping, vybrané testy
  ROVNOU spustí (gate command musí vracet reálný pass/fail exit code, ne jen vypsat příkaz),
  emituje JSON summary `{selected_tests: [...], reasoning: [...], exit_status}` na stdout i do
  evidence souboru. Neznámá produkční cesta mimo Initial mapping → non-zero exit + reason dle
  D-selector-1. Docs-only změna → exit 0, `selected_tests: []`, reasoning zaznamená proč se nic
  nespustilo.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-select-tests.bats` — testy na
  Initial mapping (každá produkční cesta → správný test soubor/filtr), unknown-path fail case
  (D-selector-1), docs-only no-op case, JSON výstup obsahuje `selected_tests` + `reasoning`.

**Acceptance Criteria:**
- [ ] **CHECKPOINT 3:** fixture změna `aid-plan-diff.sh` → selector vybere POUZE
  `test-plan-diff.sh` (ne celou `bats_all`, ne nic navíc).
- [ ] Změna `aid-release-policy.sh` vybere release-policy testy; změna `aid-fsm.sh` vybere FSM bats.
- [ ] Neznámá produkční cesta selže/unverifiable s recovery instrukcí "upgraduj na standard/full"
  (ne tichý skip) — dle D-selector-1.
- [ ] Docs-only cesta nevybere žádný těžký test a zaznamená zdůvodnění.
- [ ] JSON výstup selectoru obsahuje vybrané testy + zdůvodnění a je uložen do evidence.

**Effort:** M
**AID Role:** backend

### Step 10: `targeted_tests` gate definice v execution.yaml + integrační ověření

**Objective:** Zaregistrovat `targeted_tests` jako platnou gate definici, BEZ aktivace v self-host
`gate_profiles` (aktivace je EPIC 4, D1/D3), a ověřit end-to-end přes `aid-run-gates.sh`, že
CHECKPOINT 3 sedí i z pohledu gate runneru, ne jen samotného selectoru.

**Files:**
- Modify: `.aid-o/config/execution.yaml` — přidat `gates.targeted_tests` definici (command:
  cesta k `aid-select-tests.sh`), BEZ přidání `targeted_tests` do žádného
  `gate_profiles.*.include[]` (D3/D1 boundary — self-host aktivace čeká na EPIC 4).
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — integrační
  fixture: `aid-run-gates.sh` s gate `targeted_tests` skutečně zavolá `aid-select-tests.sh` a
  propaguje jeho pass/fail (vč. D-selector-1 unverifiable-jako-fail) do `gates_report.json`.

**Acceptance Criteria:**
- [ ] `targeted_tests` gate definice existuje v `execution.yaml` a `aid-run-gates.sh` ji najde a
  spustí.
- [ ] `targeted_tests` NENÍ součástí žádného aktivního self-host `gate_profiles.*.include[]`
  (D3/D1 — aktivace čeká na EPIC 4).
- [ ] Integrační test ověří, že `aid-run-gates.sh` volání gate `targeted_tests` propaguje
  selectoru pass/fail/unverifiable-jako-fail výsledek do `gates_report.json`.
- [ ] CHECKPOINT 3 end-to-end (přes `aid-run-gates.sh`, ne jen přímé volání selectoru): fixture
  změna `aid-plan-diff.sh` → `gates_report.json` řádek pro `targeted_tests` odráží pouze
  `test-plan-diff.sh`.

**Effort:** S
**AID Role:** backend

**Acceptance (EPIC-level, vč. MANDATORY CHECKPOINT 3):**
- [ ] **CHECKPOINT 3:** fixture změna `aid-plan-diff.sh` → selector vybere POUZE
  `test-plan-diff.sh` (ne celou `bats_all`, ne nic navíc).
- [ ] Změna `aid-release-policy.sh` vybere release-policy testy; změna `aid-fsm.sh` vybere FSM bats.
- [ ] Neznámá produkční cesta pod `targeted` profilem selže/unverifiable s recovery instrukcí (ne
  tichý skip).
- [ ] Docs-only cesta nevybere žádný těžký test a zaznamená zdůvodnění.
- [ ] Výstup selectoru je v evidenci — PM vidí, proč sada proběhla nebo neproběhla.

**Fast-lane test pro tento EPIC:** od tohoto bodu dogfooduj vlastní `--profile targeted`
(EPIC 1+2 už existují) místo ruční konvence, kde to jde; jinak `test-aid-select-tests.bats` +
`bats_fsm` po commitu; plný `bats_fsm+bats_all` na konci EPICu.

---

**EPIC 4: AID self-host default profily (AŽ PO resolveru a selectoru)**

**Objective:** Aplikovat rozumné defaulty na aid-orchestrator samotný — teprve když substrát,
resolver i selector existují (D1). Toto je EPIC, který reálně zrychlí běžné EPICy.

**Precondition specifická pro tento EPIC:** EPIC 2 A EPIC 3 merged do main; cache resynced proti
post-EPIC-3 main (jinak tenhle EPIC běží s pre-fix `aid-fsm.sh`/resolverem a je to přesně ta díra,
kterou PM revize opravila).

**Files:**
- Modify: `.aid-o/config/execution.yaml` — self-host `gate_profile_defaults` + `gate_profiles`.
- **Do NOT modify** `plugins/aid-orchestrator/defaults/execution.yaml` s `bats_fsm`/`bats_all`/
  jinými self-host-only jmény (D3).

**Self-host config (musí explicitně obsahovat `targeted`/`step` profil — poslední review kolo
našlo, že bez tohohle by `targeted_tests` gate z EPIC 3 seděl v nule aktivních self-host profilů a
nikdy by neběžel):**

> **CP1-deep adjudikace (AB2):** `plan_final: full` níže je záměrně přítomný jako
> forward-compatible klíč, ALE je to potenciálně mrtvá konfigurace — EPIC 2 ("Inputs pro
> resolver") výslovně připouští, že `plan_final` detekce se v v1 nemusí implementovat, pokud
> epic-index/total-epics signál není dodán (a `plan.json` dnes takové pole nemá — ověřeno
> `aid-epic-to-json.sh` neobsahuje `epic_index`/`total_epics`/`source_plan`). Pokud EPIC 2
> `plan_final` signalizaci nedodá, `plan_final: full` zůstává nedosažitelný — self-host se
> v takovém případě spoléhá výhradně na high-risk path upgrade (D4) + `release` boundary (D6),
> přesně jak EPIC 2 popisuje jako fallback. To NENÍ chyba configu, pokud implementace tuhle
> nedosažitelnost explicitně zdokumentuje (viz nová CHECKPOINT 4 podmínka níže) — je to chyba jen
> tehdy, když zůstane tichá a nezdokumentovaná.

```yaml
gate_profile_defaults:
  step: targeted
  epic: standard
  plan_final: full  # viz caveat výše — může být nedosažitelné, pokud EPIC 2 nedodá boundary signál
  release: release

gate_profiles:
  targeted:
    include: [plan_diff, targeted_tests, docs_updated]
  standard:
    include: [plan_diff, bats_fsm, targeted_tests, docs_updated]
  full:
    include: [plan_diff, bats_fsm, bats_all, docs_updated]
  release:
    include: [plan_diff, bats_fsm, bats_all, shell_pipeline_smoke, docs_updated]
```

**Acceptance (vč. MANDATORY CHECKPOINT 4):**
- [ ] **CHECKPOINT 4:** reálný/fixture `gates_report.json` z běžného (ne-rizikového) EPICu má
  `shell_pipeline_smoke` a `bats_all` v `excluded_gates`, `profile=="standard"`. Fixture
  vysoce-rizikového EPICu (dotyk `aid-fsm.sh`) má `profile=="full"`, `bats_all` NENÍ v
  `excluded_gates`.
- [ ] `targeted_tests` gate je aktivní alespoň v `targeted` a `standard` self-host profilech (ne
  definovaný, ale nikde použitý).
- [ ] `gates_report.json` vysvětluje vyňaté gaty (`profile`, `profile_source`, `profile_reason`,
  `excluded_gates`).
- [ ] **AB2 (plan_final reachability):** implementace EPIC 4 explicitně zdokumentuje (v kódu
  komentářem NEBO v `gates_report.json`/evidence), zda `plan_final: full` je v tomto self-hostu
  reálně dosažitelný (EPIC 2 dodal boundary signál) nebo záměrně inertní (self-host se spoléhá na
  high-risk upgrade + `release` boundary). Tichá, nezdokumentovaná nedosažitelnost = FAIL tohoto
  bodu, i kdyby zbytek CHECKPOINT 4 prošel.

**Fast-lane test pro tento EPIC:** dogfooduj `--profile full` na vlastní změny `execution.yaml`
(je to `defaults/policies/**`-adjacent, tedy high-risk podle vlastních pravidel); plný
`bats_fsm+bats_all` na konci EPICu.

---

**EPIC 5: `/aid-do` risk escalation + release profile invocation**

**Objective:** Zavřít oba bypass povrchy, než se P061 prohlásí za efektivní napříč AID.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-do.md` — risk check ve DVOU bodech, ne jednom
  (CP1-deep AB1 fix — původní "Step 3 volá na finální diff" tvrdilo paritu s `existing_ui`, ale
  `existing_ui` běží PŘED zápisem (Step 2) a diff-based check může běžet jen PO zápisu (po Step 3);
  tohle rozdíl musí být explicitní, ne implicitní):
  1. **Předběžný check (Step 2, PŘED implementací)** — stejná timing jako `existing_ui`: pokud
     task description explicitně jmenuje cílový soubor, který `aid-gate-profile.sh` klasifikuje
     jako high-risk, refuse-with-redirect na `/aid-run` okamžitě, žádný soubor se nezapíše (stejný
     vzor jako existující `existing_ui` refusal blok, beze změny jeho invariantů).
  2. **Post-implementation check (nový, mezi Step 4 a Step 5)** — na skutečný `git diff --stat`,
     protože skutečně dotčené soubory se mohou lišit od toho, co bylo poznatelné ze zadání v
     Step 2. Pokud tenhle pozdní check najde high-risk soubor, KTERÝ Step 2 nezachytil:
     **Step 7 (Git Commit) se PŘESKOČÍ** — working tree zůstává nekomitnutý (ne auto-revert),
     PM dostane stejné ESCALATION options jako u `existing_ui` (redirect na `/aid-run` se
     zachovaným diffem, nebo explicitní PM override evidence zapsaná do `Q-NNN.md` před tím, než
     smí commit proběhnout). Toto je EXPLICITNÍ, pojmenovaná výjimka z obecných invariantů
     "Git commit is mandatory" a "Escalation is advisory" v `aid-do.md` — ty dvě věty platí pro
     scope-overrun eskalaci (viz Auto-Escalation Triggers tabulka), NE pro D5 risk-guard, který je
     dle vlastní definice "no-bypass" (musí zůstat hard block, ne advisory).
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` NEBO `aid-fsm.sh` (release precondition)
  — skutečné spuštění/ověření `release` profilu před tag/release. Rozhodni při implementaci, který
  z obou je správné místo — ale musí to být JEDNO z nich, ne žádné.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádky pro oba mechanismy.

**Acceptance (vč. MANDATORY CHECKPOINT 5):**
- [ ] `/aid-do` na docs-only cestu neběží plný profil (zůstává rychlé).
- [ ] **CHECKPOINT 5a (pre-implementation, D5):** `/aid-do` se zadáním explicitně jmenujícím
  `aid-fsm.sh` (nebo jiný high-risk soubor z Risk Upgrade Rules) refuse-with-redirect PŘED Step 3
  — žádný soubor se nezapíše. Konkrétní test: sdílená risk-klasifikační funkce vrací `full`/
  high-risk pro `aid-fsm.sh` bez ohledu na volajícího (aid-fsm.sh i aid-do.md ji volají stejně) +
  `aid-do.md` dokumentuje/vynucuje eskalační krok (ověřitelné grepem na eskalační instrukci,
  stejný vzor jako existující `existing_ui` refusal blok).
- [ ] **CHECKPOINT 5b (post-implementation, D5 — AB1 fix):** fixture, kde high-risk soubor NENÍ
  poznatelný ze zadání (Step 2 projde), ale skutečný diff po Step 3/4 high-risk soubor obsahuje →
  Step 7 (Git Commit) se přeskočí, working tree zůstává nekomitnutý, PM dostane ESCALATION options
  (redirect na `/aid-run` se zachovaným diffem, nebo PM override evidence do `Q-NNN.md`). Test musí
  ověřit, že se NEPROVEDE automatický commit v tomhle scénáři (na rozdíl od scope-overrun
  eskalace, která zůstává advisory-only).
- [ ] **CHECKPOINT 5c (D6 — AB3 fix, behaviorální test analogický CHECKPOINT 2 pro D4):** fixture,
  kde `release` gate profil NEPROBĚHL nebo selhal → tag/release flow (`aid-release.sh` nebo
  pojmenovaný FSM release precondition, dle rozhodnutí z implementace) skončí s non-zero exit /
  odmítne pokračovat. Samotná existence řádku v `enforcement-registry.yaml` (AC8) NENÍ dostatečná
  — musí existovat skutečný negative-path test, stejně jako CHECKPOINT 2 má pro D4.
- [ ] Release/tag flow spustí nebo ověří `release` profil evidenci — ne nulová vazba.
- [ ] Registry řádky existují pro oba mechanismy.

**Fast-lane test pro tento EPIC:** `test-aid-gate-profile.bats` (sdílená funkce) + manuální
průchod `/aid-do` flow na fixture úkolech (nízké i vysoké riziko) + `bats_fsm` po commitu; plný
`bats_fsm+bats_all` na konci EPICu; **toto je zároveň finální EPIC před mergem celého P061 —
spusť `release`-ekvivalent (`bats_fsm+bats_all+shell_pipeline_smoke`) před mergem do main.**

---

**EPIC 6 / Backlog: C1/FSM duplicate suppression**

Není potřeba pro první vynucený speed win. Follow-up, pokud EPICy 1-5 jsou stabilní a rychlé.
Nepostponuj kvůli tomu jádro gate-profile změny.

**Acceptance:**
- [ ] Čerstvý `delivery-gate.json` na HEAD může potlačit ekvivalentní advisory FSM gate.
- [ ] Zastaralá delivery evidence nikdy nepotlačuje.
- [ ] Required `release` profil může vždy vynutit plný běh gate.

## Metrics

Před/po metriky:
- medián GATES trvání, P90 GATES trvání
- celkový čas `shell_pipeline_smoke`, celkový čas `bats_all`
- počet gatů vyňatých profilem, počet profile-upgrade na `full`
- false-green incidenty, gate-fix loop count

**Initial target:**
- Běžný EPIC GATES medián pod **150s** na prvních 3 post-P061 běžných EPICech (pokud nejsou
  vysoce rizikové a explicitně upgradované).
- `shell_pipeline_smoke` neběží v běžném EPIC profilu.
- `bats_all` neběží v běžném EPIC profilu, pokud není risk-upgradovaný na `full`.
- Žádný nárůst false-green incidentů.
- Všechny vynechané gaty mají explicitní skip řádek a důvod.

## Risks

| Riziko | Dopad | Mitigace |
|---|---|---|
| Slabý profil skryje regresi | High | high-risk path upgrade (FSM precondition) + targeted selector + `release` full profil |
| `plan.json.gates[]` floor je bez zubů kvůli gates-enum bugu | High (nově objevené) | oprava je první commit EPIC 1, samostatný CHECKPOINT 1 |
| Defaulty rozbijí consumer projekty | High | self-host jména jen v `.aid-o/config/execution.yaml`; `defaults/` zůstává generický (D3) |
| `/aid-do` obchází profily | High | sdílená risk-klasifikační funkce + eskalace/override (EPIC 5) |
| `release` profil je jen deklarace | High | pojmenovaný invocation point (EPIC 5) |
| EPIC 4 startuje před EPIC 2/3 | High | explicitní precondition v EPIC 4 + queue depends_on při generování EPIC.md |
| Bootstrap Fast Lane se stane trvalým zvykem i mimo P061 | Medium | explicitně scoped na tento plán (D8); po EPIC 3 dogfooduj reálný `--profile` místo ruční konvence |
| Gates-enum oprava má dopad mimo P061 (jiné plány/projekty) | Medium | to je bonus, ne riziko — ale otestuj zpětnou kompatibilitu se stávajícími plán.json soubory používajícími `docs_updated` |
| Příliš mnoho scope před E10 | Medium | substrát/resolver/selector před self-host aktivací; EPIC 6 je backlog |

## Acceptance Criteria (plan-level)

> Poznámka: většina těchto AC popisuje stav PO implementaci — dnes (pre-implementace) selžou (stejný
> vzor jako P060 AC8, "Binding dnes: 5<7 → pre-impl fail"). Výjimky: **AC7** je stojící negativní
> invariant (D3 consumer isolation) — prochází už dnes A musí procházet i po P061; to je správně,
> není to red-green pár. **AC5** má existence-guard právě proto, aby dnes (kdy self-host profil
> `standard.include` ještě neexistuje) korektně FAILOVALA, ne prošla naprázdno — bez guardu by
> prázdný yq výstup udělal AC vždy pravdivou bez ohledu na EPIC 4.

- [ ] AC1 (gates-enum, CHECKPOINT-prerequisite): fixní 4-hodnotový enum v `plan.schema.json` je
  odstraněný/rozšířený (doporučená cesta — volný `string` s dynamickou validací proti
  `execution.yaml` — by nikdy nevyrobila doslovné `"bats_all"` v samotném schématu, proto AC
  kontroluje odstranění restrikce, ne přítomnost konkrétního jména). Funkční roundtrip (fixture
  `## DoD Gates: - bats_all` → `plan.json` opravdu obsahuje `"bats_all"`) je CHECKPOINT 1 v EPIC 1
  step-level acceptance výše.
  ```yaml
  type: cmd
  cmd: "! grep -qE '\"enum\":\\s*\\[\\s*\"tests_pass\",\\s*\"lint_pass\",\\s*\"security_scan_pass\",\\s*\"docs_updated\"\\s*\\]' plugins/aid-orchestrator/defaults/templates/plan.schema.json"
  expected_exit: 0
  ```
- [ ] AC2 (CHECKPOINT 1): `test-aid-run-gates.bats` obsahuje min. 3 nové scénář-specifické testy
  pro `profile_excluded` a `plan_gate_profile_excluded`.
  ```yaml
  type: cmd
  cmd: "test $(grep -cE '^@test.*(profile_excluded|plan_gate_profile_excluded|plan.*floor)' plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats) -ge 3"
  expected_exit: 0
  ```
- [ ] AC3 (CHECKPOINT 2): `test-aid-gate-profile.bats` existuje a obsahuje min. 4 testy pro
  risk-upgrade (vč. FSM precondition enforcement, ne jen resolver volba).
  ```yaml
  type: cmd
  cmd: "test -f plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-profile.bats && test $(grep -cE '^@test.*(risk.upgrade|full|precondition)' plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-profile.bats) -ge 4"
  expected_exit: 0
  ```
- [ ] AC4 (CHECKPOINT 3): `aid-select-tests.sh` existuje a je spustitelný; test na
  `aid-plan-diff.sh` vybírá jen `test-plan-diff.sh`.
  ```yaml
  type: cmd
  cmd: "test -x plugins/aid-orchestrator/scripts/aid-select-tests.sh && test $(grep -cE '^@test' plugins/aid-orchestrator/scripts/tests/bats/test-aid-select-tests.bats) -ge 5"
  expected_exit: 0
  ```
- [ ] AC5 (CHECKPOINT 4): self-host `execution.yaml` má definovaný `standard` profil A ten
  neobsahuje `shell_pipeline_smoke` ani `bats_all` (existence guard první — bez něj by dnešní
  chybějící `gate_profiles.standard.include` udělal AC nesprávně zeleným už teď).
  ```yaml
  type: cmd
  cmd: "yq -e '.gate_profiles.standard.include' .aid-o/config/execution.yaml >/dev/null && ! yq '.gate_profiles.standard.include[]' .aid-o/config/execution.yaml | grep -qE 'shell_pipeline_smoke|bats_all'"
  expected_exit: 0
  ```
- [ ] AC6 (CHECKPOINT 5): sdílená risk-klasifikace pro `aid-fsm.sh` vrací high-risk/`full`
  nezávisle na volajícím; `aid-do.md` obsahuje eskalační instrukci pro high-risk cesty.
  ```yaml
  type: cmd
  cmd: "test -f plugins/aid-orchestrator/scripts/lib/aid-gate-profile.sh && grep -qiE 'escalat|redirect.*aid-run|PM override' plugins/aid-orchestrator/commands/aid-do.md"
  expected_exit: 0
  ```
- [ ] AC7 (consumer isolation, D3 — negativní kontrola): plugin defaults nikdy neobsahují
  self-host gate jména.
  ```yaml
  type: cmd
  cmd: "! grep -qE '\\bbats_fsm\\b|\\bbats_all\\b|\\bshell_pipeline_smoke\\b' plugins/aid-orchestrator/defaults/execution.yaml"
  expected_exit: 0
  ```
- [ ] AC8 (registry): enforcement registry obsahuje řádky pro všechny nové mechanismy z tohoto
  plánu (profile_selection, profile_exclusion, plan_gate_floor, risk_upgrade, aid_do_risk_guard,
  release_invocation).
  ```yaml
  type: cmd
  cmd: "for id in profile_selection profile_exclusion plan_gate_floor risk_upgrade aid_do_risk_guard release_invocation; do ID=$id yq -e '.enforcements[] | select(.id == env(ID))' plugins/aid-orchestrator/defaults/enforcement-registry.yaml >/dev/null || exit 1; done"
  expected_exit: 0
  ```
- [ ] AC9 (D6 behavioral enforcement, CP1-deep AB3 — registry row existence alone is NOT
  sufficient; a `status: planned`/fabricated-`source:` row would pass AC8 with zero guarantee
  anything is wired, matching L3's "Detector without Enforcement is Decoration" finding): a
  negative-path test/fixture exists that exercises the release-blocking behavior itself
  (CHECKPOINT 5c), not just the registry row.
  ```yaml
  type: cmd
  cmd: "grep -qiE 'release.*(profile|gate).*(not.*run|missing|fail)|release_invocation' plugins/aid-orchestrator/scripts/aid-release.sh plugins/aid-orchestrator/scripts/aid-fsm.sh 2>/dev/null && test $(grep -rlE '^@test.*release' plugins/aid-orchestrator/scripts/tests/bats/*.bats 2>/dev/null | wc -l) -ge 1"
  expected_exit: 0
  ```

## Success Criteria

- Běžný self-host EPIC GATES medián pod 150s, měřeno na prvních 3 post-P061 běžných EPICech.
- Žádný nárůst false-green incidentů oproti P060 baseline.
- Konzument (jiný projekt) s `execution.yaml` bez `gate_profiles` nezaznamená žádnou změnu chování.
- PM umí z `gates_report.json` vyčíst, co proběhlo, co ne, a proč — bez čtení kódu.

## Next Steps / Doporučené PM rozhodnutí

1. Potvrdit GO/REVISE na tento formální plán (viz zpráva k tomuto dokumentu).
2. Precondition 1 (P060 merged do main) je SPLNĚNA (ověřeno CP1-deep adjudikací 2026-07-10).
3. Vygenerovat EPIC.md pro EPIC 1 (`aid-plan-to-epic.sh`), spustit Bootstrap Fast Lane politiku
   popsanou výše.
4. EPIC 2 startuje až po merge EPIC 1; EPIC 4 startuje až po merge EPIC 2 A EPIC 3 (D1).
5. Před finálním mergem celého P061 do main: `release`-ekvivalentní plná sada (D8, finální hranice).

---

**Last Updated:** 2026-07-10

## Amendment (P068, 2026-07-26) — D8 superseded

D8 assumed the gate profile is resolved per EPIC at EPIC completion. Under
`plan_branch` the expensive profile runs ONCE, at the plan-final boundary,
against the frozen candidate (registry row `plan_final_gate_required`), and the
per-EPIC cap is the boundary cap (`gate_profile_epic_boundary_cap`). D8s
per-EPIC resolution survives only in `legacy_epic_release_mode`.

This file is gitignored, so this note is for local readers. The durable record
is in `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`.
