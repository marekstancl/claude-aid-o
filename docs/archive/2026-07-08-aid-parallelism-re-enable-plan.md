# AID Parallelism Re-Enable Plan

Status: draft / roadmap note
Created: 2026-07-08
Owner: AID Control System v2 / future speed work
Suggested future plan id: P061 or later

## Stakeholder Brief

AID dnes zamerne bezi implementacne sekvencne. Neni to nahodny bug, ale ochranny rezim po predchozich selhanich paralelniho dispatch modelu: mega-commity, placeholder verify soubory, memory bypass, nejasne vlastnictvi souboru a nedostatecne overeni po kazdem agentovi.

Cil neni vratit paralelismus "prepnout jeden config". Cil je znovu zavest rychlost po vrstvach tak, aby regresni riziko zustalo nulove. Paralelismus se smi vratit pouze tam, kde je deterministicky dokazatelne, ze nemuze obejit evidence, memory, scope, commit discipline ani release rozhodnuti.

## Current State

Runtime implementacni paralelismus je vypnuty:

- `plugins/aid-orchestrator/defaults/orchestration.yaml` ma `dispatch.strategy: sequential` a `dispatch.max_parallel: 1`.
- `plugins/aid-orchestrator/skills/pipeline.md` explicitne rika, ze vsechny implementacni kroky bezi jeden po druhem bez ohledu na `parallel_groups`.
- `plugins/aid-orchestrator/skills/role-cards.md` ponechava per-role `Max Parallel`, ale oznacuje je jako aspiracni metadata, protoze globalni strop je 1.
- `docs/plans/BACKLOG.md` eviduje E171 jako prerequisite pro znovuotevreni paralelniho dispatch modelu.

Paralelni struktury v systemu stale existuji:

- `plan.json` umi `parallel_groups`.
- frontmatter/queue umi EPIC dependencies (`depends_on`).
- CP3 umi paralelni read-only verifikaci code-review + security.
- analyzy/per-step plan reviews lze posilat paralelne, pokud jen ctou a zapis vysledku je oddeleny.

To znamena: AID dnes umi paralelismus reprezentovat, ale nebezpecne casti runtime paralelismu jsou uspane.

## Why Parallelism Was Disabled

Historicke duvody pro `max_parallel: 1`:

1. Mega-commity: vice agentu pracovalo najednou a controller ztracel moznost validovat a commitovat kazdy krok samostatne.
2. Placeholder evidence: verifier vystupy mohly byt pritomne formalne, ale obsahove neprokazovaly realnou kontrolu.
3. Memory bypass: agenti nedostali konzistentni memory/context pred dispatch nebo nebylo dolozitelne, co skutecne dostali.
4. Scope collisions: paralelni agenti mohli sahat do stejnych souboru bez deterministickeho merge guardu.
5. Nejasna release autorita: pred C4 nebyl jeden agregovany release verdict, ktery by paralelni vysledky sjednotil.
6. Stale plugin/cache problem: subagenti mohou bez reseni IMP-179 bezet podle starych instrukci.

Tyto duvody jsou stale validni, dokud je nezavrou Control System v2 a navazujici speed/safety prace.

## Non-Goals

Tento dokument neschvaluje okamzite zapnuti `max_parallel > 1`.

Mimo scope:

- okamzite paralelni psani do stejneho checkoutu,
- obchazeni C0-C4 evidence vrstvy kvuli rychlosti,
- paralelni merge bez worktree izolace,
- snizeni poctu kontrol bez nahrady v C4 release-decision,
- zrychleni za cenu "acceptable regression".

Regrese musi zustat 0.

## Required Preconditions

Paralelismus implementacnich agentu se nesmi zapnout, dokud nejsou splnene tyto podminky:

1. E9/P059 hotove: C3 activation + C4 dual-run produkuje `release-decision.json`.
2. E10/P060 hotove nebo minimalne kalibracni data dostupna: C3 hook fired v zivych runech, C4 dual-run divergence logy existuji.
3. IMP-179 vyresen nebo explicitne blokovan: dispatchnuty subagent dolozi verzi/hash instrukci, ktere skutecne dostal.
4. Evidence verifier umi rozlisit fresh/stale evidence a bezi po kazdem EPICu.
5. Plan-diff nesmi skipovat plan kvuli `plan_path: null`, pokud existuje `plan_ref` v queue/epic_input.
6. Scope/contract gate umi chytat nejen "path-like", ale i spatne relativni cesty a fragmenty bez repo prefixu.
7. Worktree/branch isolation je implementovane a testovane pro write agents.
8. Merge dry-run + file ownership conflict guard je blokujici.
9. Memory/context injection je zaznamenana per dispatch a overitelna.
10. Release rozhodnuti zustava jedine: C4/legacy dual-run v observe, pozdeji C4 blocking.

## Re-Enable Strategy

Paralelismus se vraci po vrstvach od nejbezpecnejsi po nejrizikovejsi.

### Layer 0: Measurement First

Pred jakymkoliv zrychlovanim merit aktualni baseline:

- wall-clock cas celeho EPICu,
- cas per step,
- cas CP2/CP3/CP4/Auditor/Curator,
- cas gates/test/typecheck/build,
- pocet LLM dispatchu,
- pocet fix-loopu,
- pocet stale evidence incidentu,
- pocet false-green / manual correction incidentu,
- pocet scope violations,
- pocet merge conflicts.

Vystup: `parallel-readiness-report.json` nebo podobny artefakt. Bez baseline nelze dokazat, ze paralelismus pomohl a neoslabil kvalitu.

### Layer 1: Parallel Read-Only Reviews

Nejdrive paralelizovat jen cteni:

- CP3 code-review + security,
- plan review lenses,
- independent implementation review,
- evidence pack verification,
- C3 audit probes, pokud jen ctou,
- UI screenshot/verdict analyzy, pokud nepisou do produkcnich souboru.

Podminky:

- kazdy reviewer zapisuje vlastni artefakt,
- zadny reviewer nema write scope do implementace,
- agregace je deterministicka,
- missing reviewer output = fail/unverifiable, nikdy pass.

Tohle ma nejlepsi pomer rychlost/riziko.

### Layer 2: Parallel Deterministic Scripts

Druha vrstva jsou skripty bez LLM:

- test suites,
- lint,
- typecheck,
- build,
- protocol validation,
- contract validation,
- delivery gate subchecks.

Podminky:

- vystupy maji oddelene soubory,
- exit kody jsou zachovane,
- souhrn umi rozlisit fail/skip/unverifiable,
- timeout nepretavi required check na pass,
- performance telemetry se zapisuje (`duration_ms` per check).

Tohle muze zrychlit pipeline bez zvyseni LLM rizika.

### Layer 3: Parallel Planning / Analysis Agents

Paralelne mohou bezet analyzy, ktere navrhuji, ale neimplementuji:

- per-step plan review agenti,
- adversarial reviewers,
- risk/lens classifiers,
- design auditors.

Podminky:

- kazdy agent dostane fresh context,
- vystup je strukturovany,
- implementator nesmi brat jeden agent PASS jako autoritu,
- konsolidator musi uvest neshody a rozhodnuti.

Tato vrstva uz se v praxi pouziva a funguje dobre, pokud je explicitne oddelena od implementace.

### Layer 4: Parallel Write Agents in Worktrees

Teprve po predchozich vrstvach lze testovat paralelni implementaci.

Minimalni model:

- kazdy agent dostane vlastni git worktree nebo branch,
- kazdy agent ma striktni `allowed_paths`,
- shared files jsou zakazane nebo vyzadujou explicitni wiring step,
- kazdy agent po sobe spousti local step verification,
- controller po navratu agenta provede scope-check, evidence-check, commit,
- merge probe bezi pred sloucenim do task branch.

Zakaz:

- vice write agentu ve stejnem checkoutu,
- agenti upravuji stejny soubor bez explicitniho post-wave integration kroku,
- controller slouci vystupy bez rerun relevantnich checku.

### Layer 5: Parallel EPICs

Paralelni EPICy jsou rizikovejsi nez paralelni kroky, protoze maji sirsi blast radius.

Povolitelne pouze kdyz:

- `depends_on` je prazdne nebo splnene,
- file ownership mezi EPICy je disjunktni,
- oba EPICy maji vlastni branch/worktree,
- C4 release-decision umi agregovat a odlisit jejich evidence,
- plan-level closure umi poznat, ze jeden EPIC stale bezi.

Typicky vhodne:

- docs-only EPIC vs independent UI fixture EPIC,
- read-only audit EPIC vs implementation EPIC,
- dva projekty v ruznych repozitarich.

Typicky nevhodne:

- dva EPICy upravuji `aid-fsm.sh`,
- jeden EPIC meni schema, druhy na nem zalezi,
- jeden EPIC meni agents/skills, druhy dispatchuje ty same subagenty.

## Safety Gates Before Any Write Parallelism

Pred zapnutim Layer 4 musi existovat blokujici testy:

1. Two agents edit disjoint files -> both merge cleanly.
2. Two agents edit same file -> merge blocked before commit to main task branch.
3. One agent writes outside allowed_paths -> blocked.
4. One agent produces missing/stale evidence -> blocked.
5. One agent skips memory/context proof -> blocked or unverifiable.
6. One agent emits placeholder verify -> blocked.
7. Parallel outputs merged -> CP2/CP3 relevant checks rerun.
8. C4 release-decision sees all parallel evidence inputs.
9. Force/waiver remains visible and never rewrites fail to pass.
10. Run can be aborted cleanly without orphaned worktrees.

## Acceptance Criteria for Re-Enabling

Parallelism can be promoted only if all are true:

- No false-green in calibration suite.
- No stale evidence accepted as current.
- No missing evidence treated as pass.
- No write outside allowed_paths.
- No undetected file conflict.
- No memory/context bypass.
- No uncommitted mega-commit containing multiple uncontrolled agent outputs.
- C4/legacy dual-run divergence explained or zero.
- Performance improves by a measured target, not by assumption.
- PM-visible summary clearly states what ran in parallel and what was sequential.

Suggested initial performance target:

- Layer 1-2: 20-40 percent wall-clock reduction on high-check EPICs.
- Layer 4 pilot: no performance target until safety is proven; success = zero regression.

## Rollout Plan

### P061-A: Parallelism Baseline and Report

Deliver:

- `aid-parallel-readiness.sh`
- baseline report from last N EPICs,
- duration extraction from gates/evidence,
- classification of what is parallel-safe today.

No behavior change.

### P061-B: Parallel Read-Only Reviews

Deliver:

- dispatcher support for parallel read-only groups,
- structured outputs per reviewer,
- deterministic aggregation,
- negative fixtures for missing reviewer output.

Observe first, then blocking if stable.

### P061-C: Parallel Deterministic Gates

Deliver:

- parallel gate runner for independent scripts,
- per-check `duration_ms`,
- timeout discipline,
- no pass on skip/unverifiable for required checks.

This is likely the fastest safe win.

### P061-D: Worktree Write-Agent Pilot

Deliver:

- one small pilot EPIC with 2 disjoint write agents,
- worktree isolation,
- merge dry-run,
- allowed_paths enforcement,
- C4 evidence aggregation.

Observe only. Do not make default.

### P061-E: Controlled Parallel Profile

Deliver:

- new policy profile, e.g. `dispatch.strategy: worktrees-observe`,
- max_parallel default 2,
- allow only roles/surfaces with proven safety,
- automatic fallback to sequential on any uncertainty.

## Suggested Policy Model

Do not replace `max_parallel: 1` globally at first.

Add profiles:

```yaml
dispatch:
  strategy: sequential
  max_parallel: 1

parallel_profiles:
  read_only_observe:
    enabled: true
    max_parallel: 4
    write_allowed: false

  deterministic_gates:
    enabled: true
    max_parallel: 4
    write_allowed: false

  worktree_write_observe:
    enabled: false
    max_parallel: 2
    isolation: worktree
    require_disjoint_allowed_paths: true
    require_merge_probe: true
```

Default remains sequential until promotion.

## Relation to Control System v2

Parallelism re-enable depends on Control System v2:

- C0/C1 define contracts and delivery evidence.
- C2/C3 provide semantic and independent audit evidence.
- C4 provides a single release decision and prevents "parallel chaos" from becoming "merge anyway".
- E10 calibration decides whether observe data are reliable enough.
- E11 cutover removes old duplicate gates only after the new release authority is proven.

Therefore parallel write agents should not be a P059 task. They are a post-E10/P060 or post-E11 speed/safety track.

## Open Questions

1. Should first write-agent pilot be inside aid-orchestrator or in a smaller consumer project?
2. Should parallel mode require explicit PM approval per EPIC at first?
3. Should stale plugin cache (IMP-179) block all parallel modes or only write-agent modes?
4. What is the minimum required telemetry for PM acceptance?
5. Should worktree cleanup be automatic or require explicit release finalization?

## Recommended Decision

Do not re-enable implementation parallelism now.

After P059/P060, create a dedicated speed/safety plan:

`P061 — AID Speed and Safe Parallelism`

Start with read-only and deterministic gate parallelism. Treat write-agent parallelism as a separate, observed pilot with worktree isolation. Promotion to default requires evidence, not confidence.
