# P084 — referenční sada pro klasifikaci pásma ceremonie

**Účel.** Plán P084 stojí na premise, že *cesta v `Files:` je použitelná náhrada
za skutečný dosah plánu*. Tenhle dokument tu premisu buď doloží, nebo ji vyvrátí.
Je to ruční štítkování dvaceti tří skutečných plánů tohoto repozitáře, zapsané
**dřív, než nad nimi poprvé běžel klasifikátor**, plus kontrolní skript, který
štítky a klasifikaci porovná.

**Jak číst.** Každý řádek je jeden plán. Sloupec *ruční pásmo* je úsudek člověka
nad seznamem cest, které plán deklaruje — ne výstup nástroje. Sloupec *proč* jmenuje
cestu, která o štítku rozhodla.

**Fixtures.** `.aid-o/` je v `.gitignore`, skutečné plány tedy v repozitáři nejsou.
Každý řádek proto odkazuje na fixture v
`plugins/aid-orchestrator/scripts/tests/fixtures/plan-risk/`, který reprodukuje
frontmatter `id` a **všechny** `Files:` bullety zdrojového plánu. Frontmatter
`risk:` se **záměrně nereprodukuje** — sada zkouší mapu cest, a povýšení
frontmatterem má vlastní případ (`test-cp1-gate-risk.bats`, AC3).

**Kontrola:**

```bash
bash plugins/aid-orchestrator/scripts/tests/check-classification-reference.sh \
     docs/plans/P084-classification-reference.md
```

Skript hlásí zvlášť **podcenění** — klasifikátor skončil NÍŽ než ruční štítek.
To je jediná chyba, která škodí: ceremonie vypadne tam, kde je potřeba. Opačný
směr (klasifikátor výš než štítek) je jen drahý, ne nebezpečný, ale i ten se
hlásí. Směr rozhoduje pořadí pásem, ne to, jaký štítek řádek nese — `medium`
ručně a `light` strojově je podcenění stejně jako `full` → `light`.

## Sada

| Fixture | Zdrojový plán | Ruční pásmo | Proč (cesta, která rozhoduje) |
|---|---|---|---|
| ref-P061 | P061-gate-profiles-test-cost-reduction | full | `scripts/aid-fsm.sh`, `scripts/aid-run-gates.sh`, `scripts/aid-release.sh` |
| ref-P062 | P062-e10-calibration-promotion | full | `scripts/aid-release-policy.sh` — rozhoduje o vydání |
| ref-P068 | P068-plan-final-release-boundary | full | `scripts/aid-fsm.sh`, `scripts/aid-plan-fsm.sh`, `scripts/aid-release.sh` |
| ref-P069 | P069-scheduler-gate-integration | full | `scripts/aid-run-gates.sh` + generační řetězec |
| ref-P080 | P080-entrypoint-ux-help-handoffs | full | `scripts/aid-fsm.sh` — přes valnou většinu textových změn |
| ref-P081 | P081-test-tier-pilot | full | `scripts/aid-plan-to-epic.sh`, `scripts/lib/aid-scoping.sh` |
| ref-P082 | P082-backlog-truth-and-live-holes | full | `scripts/aid-fsm.sh`, `scripts/aid-plan-to-epic.sh` |
| ref-P083 | P083-ten-verified-defects | full | `scripts/aid-fsm.sh`, `scripts/aid-run-gates.sh`, `scripts/aid-release.sh` |
| ref-P033 | P033-aid-v3-session-b | full | `scripts/aid-fsm.sh` |
| ref-P035 | P035-gates-cp1-grounding-fixes | full | `scripts/aid-fsm.sh`, `scripts/aid-run-gates.sh` |
| ref-P036 | P036-plan-quality-enforcement | full | `skills/plan-writing.md` — kontrakt, proti kterému se plán píše |
| ref-P037 | P037-anti-fabrication-plan-ac-diff | full | `scripts/aid-fsm.sh`, `scripts/aid-run-gates.sh` |
| ref-P038 | P038-tiered-severity-merge-blocking | full | `scripts/aid-fsm.sh` |
| ref-P040 | P040-dispatch-lifecycle | full | `scripts/aid-fsm.sh`, `scripts/aid-json-to-run.sh` |
| ref-P044 | P044-preconditions-registry-bats-helpers | full | `scripts/aid-fsm.sh` |
| ref-P045 | P045-simplifier-reporter-plan-boundary | full | `scripts/aid-fsm.sh` |
| ref-P048 | P048-ui-design-to-code-fidelity-mvp | full | `scripts/gates/ui-contract-check.sh`, `lib/ui-fidelity/package.json` |
| ref-P030 | P030-enforcement-improvements | full | `scripts/aid-fsm.sh` — jinak čistě textový plán |
| ref-P027 | P027-visual-assets | full | `skills/plan-writing.md` — dokumentační plán, který mění kontrakt |
| ref-P017 | P017-flow-optimization | medium | `defaults/policies/dispatch-config.yaml`, `defaults/templates/plan.schema.json` |
| ref-P039 | P039-section-validation | light | jen `agents/`, `commands/`, `skills/` + vydávací soubory |
| ref-P015 | P015-quality-and-robustness | light | jen `commands/`, `skills/`, `CLAUDE.md` |
| ref-P029 | P029-visual-companion | full | `skills/plan-writing.md` — ruční štítek to nejdřív přehlédl, viz níže |

## Co z toho plyne (premisa)

**Rozložení pásem:** 20× `full`, 1× `medium`, 2× `light` na 23 plánech.

Premisa **drží, ale slabě**, a přesně o tom je ten poměr. Cesty dokážou pásma
rozlišit — tři plány (P039, P015, P017) vypadnou pod `full`, přestože dnešní
textový scan by je označil high-risk, a tři jiné (P027, P029, P036) naopak
`full` být mají a mají to z jediné cesty, kterou by čtenář titulku plánu
nečekal: mění `skills/plan-writing.md`, tedy kontrakt, proti kterému se píší
všechny další plány. To je ten rozdíl, kvůli kterému má klasifikace z cest
smysl.

**Jeden ruční štítek byl špatně, a stojí za to říct který.** P029
(„visual companion") jsem při ručním průchodu označil `light` — je to plán
o skillech. Přehlédl jsem, že mezi jeho pěti soubory je i
`skills/plan-writing.md`. Klasifikátor to nepřehlédl. Je to jediný rozchod
z 23 řádků a je poučný v tom směru, který se od strojové kontroly čeká:
člověk čte titulek plánu, mapa čte seznam cest.

Zároveň je z toho vidět strop úspory: populace plánů tohoto repozitáře je
infrastrukturní a **valná většina na stavový automat, běžec bran nebo vydání
skutečně sahá**. Kdo od P084 čeká, že se ceremonie zlevní většině plánů, čeká
špatně — zlevní té menšině, která si to zaslouží, a přestane lhát o zbytku.

**Vychýlení, které se tímhle nedá odstranit:** všech 23 plánů je z jednoho
repozitáře, který sám sebe orchestruje. Na spotřebitelském projektu (aplikace,
ne nástroj) by rozložení vypadalo jinak; tenhle dokument o něm nic netvrdí.

## Údržba

Přibude-li do mapy `defaults/policies/risk-paths.yaml` řádek, patří sem řádek
i sem — a naopak. Kontrolní skript volá sada `test-cp1-gate-risk.bats` (patro t0), takže běží na
merge cestě — rozchod mapy a štítků spadne, ne se prosadí.
