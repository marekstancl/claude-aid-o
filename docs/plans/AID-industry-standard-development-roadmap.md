# AID Industry-Standard Development Roadmap

**Created:** 2026-07-10  
**Purpose:** dostat AID z tezkeho self-host "kontroly vseho porad" rezimu do rychlejsiho, rizikove rizeneho vyvojoveho workflow bez ztraty kvality.  
**Status:** roadmap / navazny podklad po P060/P061

## Jednou vetou

AID se ma chovat vic jako dobry engineering workflow: rychla lokalni smycka pro bezne zmeny,
cilene testy podle rizika, full kontrola na release hranicich, kratke PM vystupy, meritelne
naklady a jasne rozhodnuti, ktere stare kontroly se po C0-C4 vypinaji.

## Proc to resime

Soucasny AID je uzitecny v tom, ze chyta false-green, stale evidence, neprokazane review a
procesni chyby. Zaroven je ale prilis pomaly:

- casto pousti siroke testy i pro male zmeny,
- opakuje LLM review/fix-loop prilis casto,
- vyrabi moc dlouhe reporty,
- casto regeneruje nebo opravuje evidence,
- stare CP vrstvy a nove C0-C4 vrstvy bezi vedle sebe,
- agent pak casto optimalizuje na projiti procesem misto na jednoduchou dodavku.

Cil neni vypnout kvalitu. Cil je presunout kvalitu do mensiho poctu jasnych, meritelnych a
risk-based mechanismu.

## Cilovy stav

### 1. Fast path vs release path

Ne kazda zmena ma prochazet stejnym rezimem.

| Typ prace | Cilovy proces |
|---|---|
| `tiny` | issue / kratke zadani, targeted test, final diff review |
| `small` | kratky plan, targeted tests, jedna nezavisla review |
| `normal` | AID plan, C0-C4 podle profilu, standard gates |
| `critical` | full AID process, full tests, C3/C4 release policy |
| `release` | full suite, release decision, PM brief |

### 2. Risk-based testy

Testy se nepousti podle zvyku, ale podle rizika a dotcenych souboru.

| Faze | Cilovy profil |
|---|---|
| krok implementace | targeted tests |
| bezny EPIC gate | standard profile |
| high-risk EPIC | full profile |
| plan boundary | full profile |
| release/tag | release profile |
| docs-only | quick profile |

Full suite nema zmizet. Ma se presunout tam, kde dava smysl.

### 3. Kratsi feedback loop

Agent ma dostat rychlou odpoved:

- co je rozbite,
- ktery test to dokazal,
- co je nutne opravit,
- co je pouze backlog.

Ne 4 stranky review textu, pokud staci jeden konkretni blocker.

### 4. Jedna release autorita

Cilovy stav po E10/E11:

- C4 `release-decision.json` je jediny release verdikt.
- Stare CP/Auditor/Curator/Reporter/Simplifier vrstvy bud:
  - nahrazuje C0-C4,
  - zustavaji jen jako utility,
  - nebo se vypinaji.
- Zadna kontrola nema zustat jen proto, ze historicky existuje.

### 5. PM vystup kratky, technicky detail oddeleny

PM potrebuje:

- co se dodalo,
- co je riziko,
- co je blokujici,
- co mam rozhodnout,
- merge / fix / abort doporuceni.

Technicky detail ma byt dostupny, ale nema byt primarni vystup.

## Roadmapa

## Phase 0 - Baseline mereni

**Cil:** prestat hadat, kde AID ztraci cas.

Merit pro kazdy EPIC:

- cas testu/gates,
- cas LLM agentu,
- pocet review dispatchu,
- pocet fix-loopu,
- cas evidence regenerace,
- cas cekani na PM,
- pocet stale evidence incidentu,
- pocet false-green incidentu,
- pocet manual correction incidentu.

**Vystup:** `aid-runtime-cost-report.json` + kratke PM shrnuti.

**Acceptance:**

- u kazdeho EPICu je videt, kam se ztratil cas,
- report rozlisuje testy vs LLM review vs evidence vs PM wait,
- nejdrazsi 3 kategorie jsou explicitne uvedene.

## Phase 1 - P061 Gate Profiles

**Cil:** prestat poustet full/broad testy pro kazdou beznou zmenu.

Navazuje na: `.aid-o/work/interim-P061-gate-profiles.md`

Povinne dodat:

- profile-aware `aid-run-gates.sh`,
- default profily `quick / targeted / standard / full / release`,
- targeted test selector,
- phase/risk resolver,
- `gates_report.json` rika, co se spustilo a proc,
- ordinary EPIC nepousti `shell_pipeline_smoke`,
- ordinary EPIC nepousti `bats_all`, pokud neni risk-upgraded.

**Ocekavany efekt:**

- gates median pro bezny EPIC pod 150s,
- usetreni gates casu 40-60 % u beznych EPICu,
- u malych/docs zmen az 60-80 % gates casu.

**Acceptance:**

- prvni 3 bezne EPICy po P061 maji meritelne kratsi gates,
- high-risk zmena se automaticky zvedne na `full`,
- zadny skip neni tichy.

## Phase 2 - Evidence Finalization Automation

**Cil:** odstranit rucni/stale evidence kolecka.

Dodat jeden prikaz:

```bash
aid-finalize-evidence <epic> <run> --at-head
```

Ma udelat:

- regenerovat deterministic artefakty,
- overit `head_sha`,
- rict, ktere LLM artefakty jsou stale,
- redispatchnout jen ty, jejichz vstupni diff se zmenil,
- vyrobit jeden final evidence report.

**Acceptance:**

- stale evidence uz neni objevovana az PM/Codexem,
- evidence pack ma jasne `fresh/stale/needs_redispatch`,
- LLM redispatch se nedela zbytecne, pokud se vstup nezmenil.

## Phase 3 - Review Budget And Loop Limits

**Cil:** zastavit nekonecne review/fix-loopy.

Pravidla:

- CP/review loop max 2 automaticke iterace,
- po 2 iteracich PM escalation,
- blocker vs non-blocker rozlisit explicitne,
- low/medium navrhy do backlogu, pokud nesouvisi s release safety,
- zadny dalsi rewrite bez PM rozhodnuti.

**Acceptance:**

- kazdy loop ma rozpocet,
- reviewer nemuze donekonecna rozsirovat scope,
- PM vidi "proc jsme zastavili a co je rozhodnuti".

## Phase 4 - PM Summary Contract

**Cil:** zkratit vystupy do lidskeho formatu.

Kazdy DONE/PM vystup musi mit:

1. Co se dodalo.
2. Co je blokujici.
3. Co zustava jako riziko.
4. Co se overilo.
5. Co ma PM rozhodnout.
6. Doporuceni: merge/fix/abort.

Limit:

- PM summary max 10-15 radku,
- technicky detail jako priloha/evidence,
- zadne dlouhe procesni romany v primarnim vystupu.

**Acceptance:**

- PM bez cteni artefaktu pochopi stav do 60 sekund,
- report stale odkazuje na evidence pro detail.

## Phase 5 - Work Classification

**Cil:** male veci nedelat jako velke release projekty.

Zavest klasifikaci:

```yaml
work_class:
  tiny
  small
  normal
  critical
  release
```

Priklady:

- docs typo -> `tiny`
- izolovany test fix -> `small`
- novy feature modul -> `normal`
- FSM/release/evidence -> `critical`
- verze/tag -> `release`

**Acceptance:**

- kazdy plan/EPIC ma work_class,
- work_class ovlivni test profil, review hloubku a reportovani,
- critical zustava prisne, tiny/small je rychle.

## Phase 6 - C0-C4 Cutover And Legacy Removal

**Cil:** prestat vrstvit stare a nove kontroly.

Pro kazdy legacy mechanismus rozhodnout:

| Mechanismus | Dispozice |
|---|---|
| CP1 | replace_by_C0 / keep_alias_only / remove |
| CP2 | replace_by_C2/targeted tests / keep_risk_gated / remove |
| CP3 | replace_by_C3 / keep_for_high_risk / remove |
| CP4 | replace_by_deterministic_validation / remove |
| CP5 | replace_by_C4 release decision |
| CP6 | replace_by_summary/reporting utility |
| Auditor | C3 utility or remove authority |
| Curator | backlog utility only or remove authority |
| Reporter | PM brief utility only |
| Simplifier | optional utility by threshold |

**Acceptance:**

- E11 neni hotove, dokud celkovy pocet autorit neklesne,
- stare nazvy mohou zustat jako read-only aliasy, ne jako dalsi gate,
- PM vidi pred/po pocet dispatchu a cas.

## Phase 7 - Read-Only Parallelism

**Cil:** zrychlit bez rizika paralelniho psani.

Povolit paralelne pouze:

- read-only plan review,
- independent implementation review,
- evidence verification,
- C3 audit readers,
- deterministic checks bez sdileneho zapisu.

Zakaz zatim:

- paralelni write agents ve stejnem checkoutu,
- paralelni merge bez worktree izolace.

**Acceptance:**

- vystupy maji oddelene artefakty,
- missing reviewer output = unverifiable/fail, nikdy pass,
- agregace je deterministicka.

## Phase 8 - Write Parallelism Pilot

**Cil:** az po stabilizaci rychlejsiho workflow zkusit paralelni implementaci.

Pouze pilot:

- dva write agents,
- disjunktni allowed_paths,
- vlastni worktree/branch,
- merge dry-run,
- file ownership guard,
- full evidence pred merge.

**Acceptance:**

- konflikt stejnych souboru blokuje merge,
- write outside scope blokuje merge,
- zadny mega-commit,
- cleanup worktrees po abortu.

## Co nedelat

- Nepreskakovat P060, pokud E10 meri na jeho datech.
- Nepridavat dalsi hygienicke bloky bez hard blockeru.
- Nepoustet full suite jen proto, ze "tak jsme to delali".
- Nedelat LLM rozhodnuti tam, kde staci skript.
- Nezrychlovat tak, ze zmizi evidence.
- Nenechat stare CP a nove C0-C4 bezet trvale vedle sebe.

## Jak pozname, ze jsme bliz industry standardu

Metriky:

- bezny EPIC ma kratsi gates,
- full suite bezi hlavne na full/release/high-risk,
- pocet LLM review dispatchu na bezny EPIC klesa,
- pocet fix-loopu klesa,
- PM summary je kratke,
- stale evidence incidenty klesaji,
- release rozhodnuti je jedno,
- stare kontroly jsou odstranene nebo zmenene na alias/utility.

Cilove hodnoty po P061 + E11:

- bezny EPIC gates median pod 150s,
- 20-40 % zrychleni bezneho AID pruchodu,
- 40-60 % zrychleni gate casti,
- zadny narust false-green incidentu,
- mene aktivnich release autorit nez pred C0-C4.

## Doporucene poradi

1. Dodelat P060.
2. P061 gate profiles / targeted tests / risk resolver.
3. Evidence finalization command.
4. Review loop budget.
5. PM summary contract.
6. Work classification.
7. E10 kalibrace.
8. E11 cutover a legacy removal.
9. Read-only parallelism.
10. Write parallelism pilot.

## Bottom Line

AID nema byt pomaly ritual. Ma byt engineering system, ktery podle rizika vybere spravne kontroly,
rychle ukaze chyby a pred releasem poskytne silnou jistotu. Industry-standard smer neni "mene
kvality", ale "stejna nebo vetsi jistota za mensi runtime cenu".

