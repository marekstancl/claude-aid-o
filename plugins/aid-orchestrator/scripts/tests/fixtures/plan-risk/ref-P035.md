---
id: REF-P035
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P035-gates-cp1-grounding-fixes.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P035

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh`:
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (řádky 114-122) — rozšířit FSM state check o env-var bypass
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (§5 GATES State sekce, řádek ~470, EXECUTE→GATES Precondition subsekce řádek ~499) — přidat doporučený flow před existing manual two-step instructions
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-helpers.bash` — append `seed_test_state_files`, `setup_passing_execution_yaml`, `setup_failing_execution_yaml` helpers (a `write_valid_verifier_output` pokud chybí)
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` — append 4 nové `@test` blocks za existing 14 v2.18.0 assertions
- Modify: `CHANGELOG.md` — přidat `## [2.18.2] — 2026-05-XX` entry s Added (advance-to-gates) a Changed (aid-run-gates.sh state acceptance) sekcemi
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identický CHANGELOG entry (must match)
- Modify: `.claude-plugin/marketplace.json` — `metadata.version` + `plugins[0].version` na "2.18.2"
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — `version` na "2.18.2"
- Modify: `plugins/aid-orchestrator/README.md` — `**Plugin:** 2.18.2`
- Modify: `README.md` — Roadmap entry `- **v2.18.2** (current) — gates chicken-egg hotfix...` + `Multi-agent orchestration plugin for [Claude Code]... v2.18.2`
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines 521-545, Completeness Gate #17 "Codebase Grounding" sekce) — přidat sub-checks 17a, 17b, 17c, 17d s konkrétními detection patterns + fail actions; updatovat EVALUATION counter na 22
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` — Step 9 verifier dispatch prompt section, přidat 4 nové extraction + verification kroky (currently lists 6 kategorií: function/helper, file path, port, service, command, env var)
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.md` — přidat novou sekci `## Resources Verification` mezi `## Constraints` a `## Risks` (logical place: po definici scope, před risk assessment)
- Create: `plugins/aid-orchestrator/scripts/tests/test-cp1-grounding.sh` — bash smoke test, který: (1) napíše dočasný plan.md s vědomými porušeními všech 4 sub-checks, (2) spustí `commands/aid-plan.md` Step 9 verifier dispatch jako simulated execution (or invoke real verifier if possible in test harness), (3) parsuje verifier output a ověří, že all 4 findings jsou flag-nuté
- Modify: tests/integration/test_canonical_view.py — add new test
- Test: tests/integration/test_canonical_view.py
- Modify: `CHANGELOG.md` — přidat `## [2.19.0] — 2026-05-XX` entry s Added (4 sub-checks + Resources Verification block) sekcí
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identický CHANGELOG entry
- Modify: `.claude-plugin/marketplace.json` — `metadata.version` + `plugins[0].version` na "2.19.0"
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — `version` na "2.19.0"
- Modify: `plugins/aid-orchestrator/README.md` — `**Plugin:** 2.19.0`
- Modify: `README.md` — Roadmap entry `- **v2.19.0** (current) — CP1 grounding extension...` + `Multi-agent orchestration plugin for [Claude Code]... v2.19.0`
