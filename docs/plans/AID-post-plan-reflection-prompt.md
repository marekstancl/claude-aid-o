# Post-Plan Reflection Prompt

PM používá tento prompt verbatim po dokončení každého plánu (všech EPICs zavřených, status: done). Cíl: extrahovat maximum signálu pro AID inventory, compliance měření a plan quality feedback. Žádné estetické proměnné, žádné variace mezi plány — komparovatelnost napříč iteracemi je vyšší hodnota než kontextová úprava.

**Dva módy reflexe:**

| Mode | Kdy použít | Sekce které se mění |
|---|---|---|
| **POST-EXECUTE** (default) | Po `done-advance` všech EPICs plánu — git delta od base_commit existuje, compliance.json napsaný, timeline.jsonl plný | Standard prompt below, all 7 sections required |
| **WRITE-ONLY** | Po `/aid-plan write` + CP1 ACCEPT + EPIC generation, ale PŘED `/aid-run` execution (např. handoff do nového okna) | Sekce 1, 2, 3A, 7 explicit N/A; nová sekce 8 "WRITE-MODE LEARNINGS" required; sekce 9 vždy povinná; sekce 4, 5 ladí pro plan-write zkušenost (CP1 passes, parser issues, plan-to-EPIC pipeline), ne pro EXECUTE failures |

**Trigger pro WRITE-ONLY variant:**
- Plán prošel ≥3 CP1 passes (signal: cross-section consistency drift class — chceme empirical evidence pro plan-writing.md gate gaps)
- Plán měl parser failures v aid-plan-to-epic.sh nebo aid-epic-to-json.sh PRE-FLIGHT
- Plán byl napsaný v Mode B (skip-brainstorming) — Mode A (brainstorm-first) má jiný signal pattern
- Kontext window se blíží limitu PŘED execute — handoff doc + reflexe jsou cheaper teď než po `/aid-run`

Empirický anchor pro WRITE-ONLY variant: P040 (AID-self, NR 16, 31.5.2026) — 5 CP1 passes na cross-section count/rename drift, ~2.6M subagent tokens cumulative, parser pipe-character failure discovered až při EPIC generation, žádná execute data ještě neexistovala.

---

## Prompt (paste verbatim)

```
PLAN REFLECTION — sepiš strukturovaný report podle níže uvedených sekcí.
Pravidlo: každé tvrzení musí být doložené konkrétním zdrojem
(timeline.jsonl řádek, git SHA, soubor, řádek v pipeline.md…).
Žádné odhady tam, kde existují přesná data.

**MODE SELECTION (na začátku reportu vyplň):**

- POST-EXECUTE: všechny EPICy plánu dosáhly done-advance, compliance.json
  exists, git delta od base_commit do HEAD je validní → sekce 1-7 required.
- WRITE-ONLY: plán prošel write + CP1 ACCEPT + EPIC generation, ale žádný
  step ještě neproběhl → sekce 1, 2, 3A, 7 jsou explicit N/A; sekce 4, 5
  ladí pro plan-write context; nová sekce 8 (WRITE-MODE LEARNINGS) required;
  sekce 9 (SKILL/COMMAND PROPAGATION CHECK) vždy povinná.

Pro WRITE-ONLY mode vlož v intro reportu **⚠ Framing fact** odstavec
co explicitně řekne: "Tato reflexe je WRITE-ONLY pre-execute. Sekce 1, 2,
3A, 7 jsou N/A — žádný step neproběhl, žádný compliance.json existuje
pro tento EPIC. Hlavní signál je v sekcích 4 + 5 + 8 + 9."

═══════════════════════════════════════════════════════════════
1. PLAN VS REALITA
═══════════════════════════════════════════════════════════════

A. Co bylo v plánu vs co je v gitu (od base_commit po HEAD):
   - Vyjmenuj kroky/AC, které plán definoval
   - Pro každý: ✅ DONE (cituj commit SHA) / ⚠️ PARTIAL (co chybí) / ❌ SKIPPED
   - Cituj git log od base_commit po HEAD

B. Goalpost shifts — místa, kde jsi přeformuloval scope:
   - Identifikuj VŠECHNY momenty, kdy jsi řekl "X už je hotové" nebo
     "X je out of scope", ač plán X explicitně vyžadoval
   - Pro každý: cituj plán + svoji reformulaci + důvod
   - Pokud žádné nebyly, výslovně to napiš: "Žádné goalpost shifty."
   - Bez sebeobhajoby — tohle je nejcennější data pro PM, ne kritika tebe.

C. Co plán neuvažoval, ale bylo nutné dodělat:
   - Cituj konkrétní změny v souborech, které plán neuváděl
   - Pro každý: byla to discovered necessity nebo scope creep?

═══════════════════════════════════════════════════════════════
2. FSM TELEMETRIE (deterministická data)
═══════════════════════════════════════════════════════════════

A. Z timeline.jsonl pro každý EPIC plánu:
   - Total wallclock: ts(fsm_init) → ts(done-advance complete)
   - Per-phase split: READY, EXECUTE (per step), GATES, DONE
   - FSM fail count: jq 'select(.event | test("fail$"))' | wc -l
   - Per-fail breakdown: tabulka reason × počet (cituj všechny řádky)

B. Compacting / context overflow:
   - Kolikrát se ti během plánu stala kompakce kontextu?
   - V jaké fázi (step N implementace, gates, review)?
   - Co bylo v kontextu těsně před tím, co se ztratilo (best estimate)?

C. Spotřeba modelu (pokud máš data):
   - Token/cost estimate per fáze (Implementer, Verifier, Curator, Auditor)
   - Pokud nemáš přesná data, výslovně řekni "neznámé" — neodhaduj.

═══════════════════════════════════════════════════════════════
3. SELF-AUDIT — bez sebeobhajoby
═══════════════════════════════════════════════════════════════

A. Co jsem skutečně udělal vs co compliance.json říká:
   - Pro každou dimenzi (branch_correct, execution_yaml_present,
     gates_generated_by, verifier_outputs.aggregate, force_override_count):
     compliance.json verdikt + tvoje skutečné chování
   - Pokud najdeš nesoulad (fabrication), přiznej to. Cituj dva zdroje.

B. CP průchody — explicitní inventura:
   - CP1 review (plan): proběhl? kde je výstup?
   - CP2 per-step verifier: dispatchnut pro každý non-SKIP step?
     Nebo jsi některé skipnul "protože malá změna"?
   - CP3 integration review: oba soubory existují?
     code-review + security verdicts?
   - CP4 (DONE): ran nebo skipnut?

C. Force override / bypass:
   - Použil jsi --force kdekoli? Cituj timeline.jsonl event +
     reason. Pokud ne, výslovně řekni "Žádné force override."

D. Mocky a fixtures:
   - Spočítej v testech počet `mock`, `Mock`, `monkeypatch`, `@patch`
     vs počet skutečných assertions proti reálnému stavu
   - Pokud test_mock_ratio > 70%, řekni to a vysvětli proč.

═══════════════════════════════════════════════════════════════
4. AID NÁLEZY — empirický input pro inventory
═══════════════════════════════════════════════════════════════

A. Kde tě AID zbytečně zdržel (s konkrétním timestampem):
   - Cituj timeline.jsonl events, kde se cyklus retry > 3 nebo kde
     jsi musel iterovat na mechanice (nedokumentovaný formát,
     confusing naming, missing prereq checklist)
   - Root cause kategorizace: collapse 7+ stucks do 3-5 root causes
     (jako v P020 analýze)

B. Kde tě AID naopak chytil za ruku:
   - Které gates / preconditions / verifier dispatches odhalili reálný
     problém? Cituj konkrétní artefakt + ten problém co odhalil.
   - Pokud žádné nebyly, řekni to (znamená to že enforcement je
     buď zbytečně přísný, nebo že tvůj agent moc dobře neimplementoval).

C. Co AID nezachytil, co měl:
   - Identifikuj situace, kde si myslíš že ti něco prošlo, co by
     ideálně AID měl detekovat. Bez sebeobhajoby — tohle je
     vstup pro nové AID items, ne kritika tebe.
   - Cituj konkrétní commit/file/line + co měl by AID-XXX zachytit.

D. Jeden architektonický návrh (max 1):
   - Pokud bys měl změnit jednu věc v AID na základě tohoto plánu,
     která to je? Krátce: problém, fix, ROI estimate, prerekvizity.
   - Žádné "obecná zlepšení" — jeden konkrétní item.

═══════════════════════════════════════════════════════════════
5. PLAN QUALITY FEEDBACK
═══════════════════════════════════════════════════════════════

A. Které části plánu byly executable (bash pipeline could run them)?
B. Které části vyžadovaly judgment calls a proč (nejasná AC)?
C. Kde plán předpokládal něco, co neexistovalo (CP1 grounding gap)?
D. Co by v plánu mělo být explicitně, ale chybělo to?

═══════════════════════════════════════════════════════════════
6. HONEST SIGNAL TRUST LEVEL
═══════════════════════════════════════════════════════════════

Klasifikuj tento report:
  HIGH    — všechny sekce 1-5 doložené daty, žádné mezery
  MEDIUM  — některé části "neznámé" nebo best-estimate
  LOW     — víc než 30% odpovědí je odhad nebo "nevím"

A jeden řádek: "Pokud bys měl PM jednu věc říct upřímně,
co tě nikdo neptá, ale ty bys měl, co je to?"

═══════════════════════════════════════════════════════════════
7. DETERMINISTIC COMPLIANCE EVAL — spusť script
═══════════════════════════════════════════════════════════════

Spusť evaluační script a jeho RAW výstup vlož DOSLOVA sem jako sekci 7:

    bash <AID_SCRIPTS>/aid-compliance-report.sh --reflect \
         --evidence-roots "<PROJECT_ROOT>/.aid-o/work/evidence"

  - <AID_SCRIPTS> = scripts adresář pluginu, typicky
    ~/.claude/plugins/marketplaces/claude-aid-o/plugins/aid-orchestrator/scripts
    (nebo plugins/aid-orchestrator/scripts v repo aid-orchestrator).
  - <PROJECT_ROOT> = root projektu, kde plán běžel. Vynech --evidence-roots
    úplně, pokud chceš cross-project trend (default = 5 eco projektů).
  - --era latest je default (auto-resolve nejnovější deploy era).
  - --reflect přidá per-dimension breakdown + force_override
    triple-condition detekci (P026 pattern).

  Pravidla:
  - Pokud script selže (jq error, chybějící compliance.json), NEFABRIKUJ
    výstup — vlož stderr a napiš "eval script FAILED: <důvod>".
  - Cross-check: souhlasí script verdikt s tvým self-auditem (sekce 3A)?
    Pokud ne, popiš nesoulad v jedné větě pod výstupem.

═══════════════════════════════════════════════════════════════
8. WRITE-MODE LEARNINGS (POVINNÉ pro WRITE-ONLY reflexe; SKIP pro POST-EXECUTE)
═══════════════════════════════════════════════════════════════

Pouze pokud mode == WRITE-ONLY. Pro POST-EXECUTE skip celou sekci 8.

A. Multi-pass CP1 dynamics (pokud >1 pass byl potřeba):

   Tabulka per pass: # | Verdict | Findings count by severity (C/H/M/L)
   | Fix wave (manual/workflow/combined) | Outcome.

   Empirical anchor: P040 — 5 passes, terminating jen díky tomu že
   Pass 4 dal exact 3-line recipe a Pass 5 confirmed clean.

   Convergence rate observation: per-pass resolution % + new-drift %.
   Pokud convergence rate < 60% (víc než 40% nových findings each pass),
   recommend halt + structural refactor.

B. Workflow tool effectiveness v write mode:

   Tabulka per workflow invocation: typ (parallel section reviewers
   / per-cluster grounding / re-reviewers / single verifier dispatch),
   tokens, effectiveness verdict (High / Medium / Low).

   Klíčová otázka: kdy je paralelní workflow lepší než single agent?
   Per-section workflow = bohatý initial signal. Iterative fix verification
   = single verifier ekonomický (no silo problem).

C. Plan-writing.md Completeness Gate gaps surfaced (pro nový AID-NNN
   inventory items):

   Empirical anchor: P040 odhalil že 24 existing checks jsou všechny
   per-section; žádný cross-section invariant check. Kandidáty na
   #21 (cross-section count/rename invariant), #22 (parser-safety
   pre-flight), structural plan refactor (single canonical registry
   block pattern).

D. Parser-safety issues (aid-plan-to-epic.sh, aid-epic-to-json.sh):

   Pokud plan-to-epic pipeline failnula, dokumentuj:
   - Která fáze failnula (which script)
   - Co bylo trigger (special char v Objective, pipe in markdown,
     fenced step header, atd.)
   - Co byl quick fix (escape, rewrite, etc.)
   - Co měl Plan-writing.md Completeness Gate zachytit ale nezachytil

E. Cross-section drift tracking (recurring write-mode failure class):

   Spočítej kolik "outer mention vs inner content" mismatch nálezů
   byly detected per pass. Pokud >5 napříč pasy, structural problem
   (per RC-1/RC-2 anchor v NR 16).

F. Workflow handoff (pokud reflexe je triggered context-window-close):

   - Kde je handoff doc napsaný? Cesta.
   - Co je next chat prompt? Cesta nebo verbatim text.
   - Která execute action je queued post-handoff? (/aid-run manual,
     /aid-run --auto, /aid-stop atd.)

═══════════════════════════════════════════════════════════════
9. SKILL/COMMAND PROPAGATION CHECK (povinné po každém NR zápisu)
═══════════════════════════════════════════════════════════════

Pro KAŽDÉ learning v této reflexi, které se týká chování AID (ne projekt-specifická
věc), urči, zda patří do instrukční vrstvy — a pokud ano, propaguj ho. Toto uzavírá
smyčku Principu #5 (Enforcement without Instruction is Cargo Cult, viz
AID-v3-principles.md): reflexe často popíše pravidlo, ale nikdo ho nedopíše do skillu,
takže se příště znovu objeví selháním.

Pro každé learning:
1. Dotkne se enforcement typu? Najdi kanonický domov instrukce podle type→home
   tabulky (docs/plans/AID-audit-2026-06/03-governance-recommendation.md §Component 2;
   shrnutí: FSM-precondition→pipeline.md · subagent-output→agent-protocol.md/verifier.md ·
   schema→plan-writing.md/planner.md · command-orchestration→commands/<cmd>.md ·
   agent-contract→role-cards.md/agents/<agent>.md · skill-protocol→ten skill sám).
2. Zapiš jednu ze čtyř dispozic k learningu:
   - **PROPAGATED:** `<soubor>.md §<sekce>` — pravidlo dopsáno, Last Updated bumpnut.
   - **INVENTORY AID-NNN:** learning přesahuje rychlý zápis → nová inventory položka.
   - **PM-REJECTED:** PM rozhodl nepropagovat (s důvodem).
   - **N/A:** žádný skill/command se nedotýká (projekt-specifické, infra, transient).
3. Pokud má learning enforcement bez instrukce (nebo instrukci bez enforcementu),
   označ ho jako #5-kandidát evidenci.

Learning bez dispozice je OTEVŘENÝ a objeví se v příštím auditu jako nepropagovaný NR.

═══════════════════════════════════════════════════════════════
KAM REPORT ZAPSAT — output handling (POVINNÉ)
═══════════════════════════════════════════════════════════════

Hotový report (sekce 1-7 včetně eval výstupu) vypiš na DVĚ místa:

1. Do chatu PM — plný text.

2. Prepend na ZAČÁTEK souboru (po vzoru předchozích feedbacků):
   /opt/eco/projects/aid-orchestrator/docs/plans/AID-v3-agents-outputs.md

   - Najdi nejvyšší existující "## NR <N>" (je hned pod H1 titulkem).
   - Nový blok vlož HNED POD řádek "# AID - agent feedback v18+",
     PŘED stávající "## NR <N>" (newest-on-top ordering).
   - Header bloku: "## NR <N+1> <PROJECT> <D.M.YYYY>"
     (PROJECT = uppercase kód projektu plánu, např. WAN / AID; DATE = dnešek).
   - Pod header celý report, sekce 1-7.
   - APPEND, nikdy nepřepisuj existující záznamy. Pokud soubor nebo H1 řádek
     neexistuje, založ soubor s H1 "# AID - agent feedback v18+" a vlož blok.
```

---

## Proč právě tyhle sekce

| Sekce | Cíl | Co tím získáme |
|-------|-----|---------------|
| 1. Plan vs realita | Detekce goalpost shiftů (P018 wan pattern) | Plan quality input + empirical evidence pro AID-010/AID-015 |
| 2. FSM telemetrie | Deterministická data místo odhadů | Empirical input pro AID-027, validation post-deploy enforcement |
| 3. Self-audit | Honest disclosure bez kalibrace (P019 finding) | Vstup pro AID-012 (uncalibrated self-audit má hodnotu) + AID-026 priority |
| 4. AID nálezy | Root-cause kategorizace ne raw seznam | Direct empirical input pro nové AID items + priority calibration |
| 5. Plan quality | Plan-side feedback loop | CP1 grounding evidence + plan-writing.md gate iterations |
| 6. Trust level | Self-classification | Filter pro PM — věřím tomuhle reportu? |
| 7. Compliance eval | Deterministická data ze scriptu vedle self-reportu | Cross-check self-auditu (sekce 3A) proti `aid-compliance-report.sh --reflect` — P026 force-override detekce |
| 8. Write-mode learnings | Plan-write zkušenost mimo execute (CP1 passes, parser issues, workflow effectiveness) — only for WRITE-ONLY mode | Empirical input pro plan-writing.md Completeness Gate extensions (#21 cross-section invariant check, #22 parser-safety pre-flight); detekce convergence/divergence v multi-pass CP1; structural plan refactor candidates |

## Pravidla použití

1. **Verbatim, bez modifikace** — komparovatelnost napříč plány je hlavní hodnota.
2. **Když agent řekne "neznámé", nech ho.** Honest "neznámé" > fabricated number.
3. **Output jde vždy na dvě místa** (viz prompt sekce „KAM REPORT ZAPSAT"): plný text do chatu PM **a** prepend na začátek `docs/plans/AID-v3-agents-outputs.md` jako nový `## NR <N+1> <PROJECT> <DATE>` blok. Kopie do `.aid-o/work/evidence/{epic_id}/reflection.md` je volitelná (`.aid-o` je gitignored).
4. **Eval script běží inline každý report** (prompt sekce 7) — `aid-compliance-report.sh --reflect`. Cross-project agregaci přes víc `--evidence-roots` spusť ad-hoc, když chceš trend napříč plány.
5. **Goalpost shift sekce je posvátná** — pokud agent řekne "žádné", PM by měl ručně zkontrolovat aspoň jeden EPIC kde scope vypadá podezřele blízko hranic.

---

**Last Updated:** 2026-05-31 (added WRITE-ONLY mode variant + sekce 8 WRITE-MODE LEARNINGS per P040 NR 16 empirical anchor)
