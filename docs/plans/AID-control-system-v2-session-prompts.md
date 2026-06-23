# AID Control System v2 - Session Prompts for Claude Code

> Každý blok spusť v novém Claude Code okně až po dokončení a schválení předchozích prerequisites.
> Před psaním executable plánu vždy přečti aktuální kód, roadmapu, master design a E0 topologii.
> Nevytvářej dopředu plány pro další fáze. Každý výstup je jeden `.aid-o/plans/P{NNN}-*.md` plán.
> Nové FSM preconditiony jsou policy-gated. Výchozí režim je `observe`, pokud prompt explicitně neuvádí schválenou kalibraci a promotion.

## E1 - Protokol v2 a schémata

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E1: Protokol v2 a schémata

Napiš jeden executable plán pouze pro E1. Nejprve porovnej aktuální schemas/templates/registry s roadmapou a masterem; nepředpokládej, že pojmenovaný soubor existuje nebo je funkční.

Goal:
- Zavést protokol v2, type-specific schemas, deterministické finding ID a per-run protocol lock bez změny runtime chování.

CREATE nebo po ověření ekvivalentu MODIFY:
- defaults/schemas/aid-protocol-v2.schema.json
- defaults/schemas/{contract-manifest,plan-review,plan-graph,review-profile,delivery-gate,semantic-review,acceptance-evidence,gates-report,audit-input-manifest,audit,curator,invalidation-map,ui-verdict,delivery-report,waiver,release-decision,pm-decision-brief}.schema.json
- scripts/tests/test-protocol-v2.sh

MODIFY:
- defaults/enforcement-registry.yaml (kanonický soubor, ne superseded seed)
- docs/extending-aid.md
- relevantní template registry nalezené při grounded průzkumu

References:
- docs/plans/AID-control-system-v2-roadmap.md: Data Model, E1
- docs/AID-control-system-v2-unified-refactor-PLAN.md §5, §7, §10 E1
- docs/design/control-topology.yaml

Rules:
- Obálka bez type-specific payloadu nesmí projít.
- Žádná runtime/FSM změna.
- Legacy evidence zůstává read-only.
- Plán musí obsahovat negative fixtures pro chybějící HEAD/action_owner a subject-hash invalidaci.
```

## E2 - C1 core a FSM state hardening

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E2: C1 core a FSM state hardening

Napiš jeden executable plán pouze pro E2. Prerequisite: E1 implementována a schema testy PASS.

Goal:
- Implementovat C1 DG-01..12 a policy-gated false-DONE rozhodnutí v observe režimu.

CREATE:
- scripts/aid-delivery-gate.sh
- scripts/lib/aid-delivery-profile.sh
- defaults/policies/delivery-gate.yaml
- defaults/templates/delivery-gate-template.json
- scripts/tests/test-delivery-gate.sh

MODIFY:
- scripts/aid-fsm.sh
- scripts/aid-run-gates.sh
- skills/run-management.md
- defaults/enforcement-registry.yaml
- scripts/tests/bats/test-aid-fsm.bats

References:
- roadmap E2
- master §6.2, §9.1, §10 E2
- Doc-1 DG-01..12

Rules:
- Live default `enforcement: observe`; selhání zapíše `would_block`, ale nezastaví reálný přechod.
- Fixture s `enforcement: blocking` musí prokázat zastavení false-DONE.
- Shell exec používá argv arrays a propaguje skutečný exit code.
- Zahrnout FC-11, FC-14, zero-tests a stale-HEAD negative fixtures.
```

## E3 - Adaptivní review profil

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E3: Adaptivní review profil

Napiš jeden executable plán pouze pro E3. Prerequisite: E1; E2 může běžet paralelně pouze bez konfliktu v souborech.

Goal:
- Vytvořit deterministický profile resolver: plan-time surfaces UNION candidate-time diff surfaces, nikdy užší přepočet.

CREATE:
- defaults/policies/review-profiles.yaml
- defaults/templates/review-profile-template.json
- focused profile resolver test fixtures

MODIFY:
- scripts/aid-prefilter.sh
- scripts/aid-fsm.sh (jen policy-gated observe validace required_lenses)
- defaults/enforcement-registry.yaml

References:
- roadmap E3
- master §3.0, §6.2, §10 E3
- control-topology.yaml risk_profiles a FC-41

Rules:
- Neznámý produkční surface = unverifiable, ne docs_only.
- Změna profilu invaliduje neúplné starší evidence.
- T1 omezuje rozhodovací kola; T6 samostatně eviduje model calls/tokens/time.
- Zahrnout docs-trivial-hidden-behavior a E-044-must-classify-high fixtures.
```

## E4 - C0 a contract handoff producer

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E4: C0 a contract handoff producer

Napiš jeden executable plán pouze pro E4. Prerequisites: E1 a E3.

Goal:
- Implementovat C0 plan gate, hashovaný contract manifest a consumption-proof producer/hook bez předstírání C2 validace.

MODIFY:
- plugins/aid-orchestrator/skills/brainstorming.md
- plugins/aid-orchestrator/skills/plan-writing.md
- plugins/aid-orchestrator/commands/aid-plan.md
- plugins/aid-orchestrator/skills/agent-protocol.md
- plugins/aid-orchestrator/agents/implementer.md
- scripts/aid-fsm.sh
- defaults/enforcement-registry.yaml

CREATE:
- plan-graph/identifier-domain/contract-manifest helpery a test fixtures v existující repo konvenci zjištěné při průzkumu

References:
- roadmap E4
- master §6.1, §9.1, §10 E4
- Doc-1 §6.1, Doc-2 §7 a §11.2-11.7
- P045 negative fixture

Rules:
- C0 vlastní FC-01..08; C0 pouze vytváří hash prerequisite pro FC-09.
- E4 consumption stav je pending/unverifiable; autoritativní C2 local validace vznikne až E5.
- FSM precondition je policy-gated observe; blocking chování pouze ve fixture.
- Restatement není consumption proof.
```

## E5 - C2 Semantic Review Engine

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E5: C2 Semantic Review Engine

Napiš jeden executable plán pouze pro E5. Prerequisites: E1-E4.

Goal:
- Sloučit CP2/IR-1/IR-2/CP3 do jednoho C2 enginu s modes local/wiring/behavior/final a dokončit FC-09 consumption validaci.

MODIFY:
- plugins/aid-orchestrator/skills/review-checkpoint-contracts.md
- plugins/aid-orchestrator/agents/verifier.md
- plugins/aid-orchestrator/skills/pipeline.md
- plugins/aid-orchestrator/commands/aid-run.md
- scripts/aid-fsm.sh
- defaults/policies/review-checkpoints.yaml
- defaults/enforcement-registry.yaml

CREATE/MODIFY:
- defaults/templates/acceptance-evidence-template.json
- semantic review merge/accounting helper a focused tests podle zjištěné repo konvence

References:
- roadmap E5
- master §3.0, §6.3, §9.1, §10 E5
- Doc-1 §6.3, Doc-2 §4-6

Rules:
- Jeden mode = jedna autorita, ne nutně jedno model call.
- Každý fan-out call eviduje provider/model/tokens/time.
- Findings = deterministic lossless union; severity se nesmí snížit.
- Wiring precondition je policy-gated do E10.
- E-044 C2 fixture pokrývá transaction/field-lineage/AC identity/requirement drift. Response shape FC-29 patří C1/E6.
```

## E6 - C1 DG-13 až DG-18

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E6: C1 DG-13 až DG-18

Napiš jeden executable plán pouze pro E6. Prerequisites: E1-E5.

Goal:
- Doplnit deterministické production reachability, wire shape, route, fallback, oracle/no-drop a acceptance structure probes.

MODIFY:
- scripts/aid-delivery-gate.sh
- defaults/policies/delivery-gate.yaml
- scripts/tests/test-delivery-gate.sh
- defaults/enforcement-registry.yaml

References:
- roadmap E6
- master §6.2, §10 E6
- Doc-1 DG-13..18
- E-047-4, E-047-5 a E-044 response-shape fixtures

Rules:
- FC-29, FC-33 a FC-34 mají primárního vlastníka C1.
- Synthetic fixture sama nestačí pro DG-17; oracle musí být nezávislý na implementaci.
- Výchozí enforcement zůstává observe do E10.
```

## E7 - P048 frontend větev

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E7: P048 frontend větev

Napiš jeden executable plán pro E7 rozdělený na E7A, E7-CAL a E7B. Prerequisites: E3 pro E7A; E6 + úspěšná E7-CAL pro E7B.

Nejdřív agent navrhne 2-3 reálné historické UI failure cases a PM je musí potvrdit před E7A. Před generací kroků proveď append-only amendment P048, který superseduje původní Step 8 a zamkne E7A→E7-CAL→E7B.

CREATE/MODIFY:
- lib/ui-fidelity/*.mjs
- scripts/gates/ui-contract-check.sh
- .aid-o/plans/P048-ui-design-to-code-fidelity-mvp.md (append-only amendment)
- plugins/aid-orchestrator/skills/visual-companion/SKILL.md
- plugins/aid-orchestrator/skills/role-cards.md
- plugins/aid-orchestrator/skills/agent-protocol.md
- plugins/aid-orchestrator/commands/aid-do.md
- scripts/aid-fsm.sh
- defaults/enforcement-registry.yaml

References:
- roadmap E7
- master §8, §10 E7
- P048

Rules:
- E7A nesmí zapnout blocking FSM.
- E7-CAL musí prokázat 2-3 PM-schválené reálné případy.
- Teprve E7B smí zapnout schválený step-local P048 block.
- P048 je C1 plugin + C2 lens, nikdy release autorita.
```

## E8 - C3 audit a affected re-run

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E8: C3 audit a affected re-run

Napiš jeden executable plán pouze pro E8. Prerequisites: E1-E6; E7 není nutné pro non-UI C3 adapter, ale UI audit fixtures čekají na E7B.

Goal:
- Implementovat provider-neutral C3, honest independence provenance, Curator sequencing a affected re-run bez CP4 review autority.

CREATE:
- scripts/lib/aid-review-provider.sh (provider-neutral adapter; uprav cestu jen pokud repo už má kanonický ekvivalent)
- audit input manifest/provenance focused tests

MODIFY:
- plugins/aid-orchestrator/agents/auditor.md
- plugins/aid-orchestrator/agents/curator.md
- plugins/aid-orchestrator/agents/gate-fixer.md
- plugins/aid-orchestrator/skills/pipeline.md
- plugins/aid-orchestrator/commands/aid-run.md
- scripts/aid-fsm.sh
- defaults/policies/review-checkpoints.yaml
- defaults/enforcement-registry.yaml

References:
- roadmap E8
- master §6.3, §10 E8
- control-topology.yaml C3
- official Codex CLI `codex exec` contract for the reference cross-provider adapter

Rules:
- Report fields: provider/model/process/input_manifest_hash/independence_level.
- Codex reference backend smí běžet jen jako samostatný `codex exec --ephemeral --sandbox read-only --ask-for-approval never` proces se schema-valid výstupem.
- Adapter detekuje Codex CLI mechanicky (`command -v codex`, `codex exec --help` nebo sanity run, auth available); nikdy podle self-claimu agenta o CLI/IDE povrchu.
- Nedostupná požadovaná úroveň = unverifiable.
- High finding mechanicky nastaví blocking_findings true.
- E8 neclaimuje C4 integration PASS; C4 vznikne až E9.
```

## E9 - C4 release a PM komunikace

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E9: C4 release a PM komunikace

Napiš jeden executable plán pouze pro E9. Prerequisites: E1-E8.

CREATE:
- scripts/aid-release-policy.sh
- scripts/aid-pm-brief.sh
- scripts/aid-reporter-run.sh
- defaults/templates/pm-summary-template.md

MODIFY:
- plugins/aid-orchestrator/agents/reporter.md
- plugins/aid-orchestrator/skills/pipeline.md
- plugins/aid-orchestrator/skills/run-management.md
- plugins/aid-orchestrator/commands/aid-run.md
- plugins/aid-orchestrator/commands/aid-do.md
- scripts/aid-fsm.sh
- scripts/aid-release.sh
- scripts/tests/bats/test-aid-fsm.bats
- defaults/enforcement-registry.yaml

References:
- roadmap E9
- master §5, §6.3, §7.6, §10 E9
- control-topology.yaml C4 pm_handoff_sequence

Rules:
- Sekvence bez cyklu: C4 evidence→release-decision; brief z release-decision+evidence; FSM offer vyžaduje release_ready+HEAD+valid brief.
- pm_brief_is_release_input=false.
- Waiver nikdy nepřepíše FAIL/UNVERIFIABLE na PASS.
- Obecný v2 release gate zůstává policy-gated do E10/E11.
```

## E10 - Kalibrace a dual-run metriky

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E10: Kalibrace a dual-run metriky

Napiš jeden executable plán pouze pro E10. Prerequisites: E1-E9 implementované v observe/dual-run, E7-CAL dokončená pro UI větev.

CREATE:
- scripts/tests/test-control-system-v2-regression.sh
- scripts/aid-control-metrics.sh
- historické sanitized fixtures podle repo konvence

MODIFY:
- defaults/policies/delivery-gate.yaml
- defaults/policies/review-checkpoints.yaml
- promotion tooling nalezené při grounded průzkumu
- defaults/enforcement-registry.yaml

References:
- roadmap E10
- master §10 E10, §11, §12

Rules:
- Kalibrovat E-047-1/4/5, E-044 a P045 jako kompozitní negative fixtures.
- Měřit false blocks, escaped defects, model calls/tokens/time a unique detections.
- Promotion vyžaduje negative fixtures, positive controls, reprezentativní sample a PM klasifikaci; samotný počet override nestačí.
- Výstup přesně určí, které checks mohou přejít do blocking v E11.
```

## E11 - Cutover a zjednodušení

```text
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E11: Cutover a zjednodušení

Napiš jeden executable plán pouze pro E11. Prerequisite: E10 data a explicitní PM promotion rozhodnutí.

Goal:
- Zapnout pouze zkalibrované checks, zachovat rollback a odstranit jen daty prokázané duplicity.

MODIFY:
- defaults/policies/delivery-gate.yaml
- defaults/policies/review-checkpoints.yaml
- scripts/aid-fsm.sh
- plugins/aid-orchestrator/skills/pipeline.md
- compatibility alias wiring nalezené při průzkumu
- docs/extending-aid.md
- defaults/enforcement-registry.yaml

References:
- roadmap E11
- master §9, §10 E11, §11-12
- E10 control-metrics.json a promotion decision

Rules:
- Legacy evidence se nemigruje sémanticky.
- Každý blocking check má rollback na observe bez mazání evidence.
- Redundance se odstraní pouze při prokázané nulové unique detection.
- CP aliasy jsou read-only compatibility, dokud data nepovolí jejich odstranění.
```
