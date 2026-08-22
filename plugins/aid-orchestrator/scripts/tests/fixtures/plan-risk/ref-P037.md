---
id: REF-P037
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P037-anti-fabrication-plan-ac-diff.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P037

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (přidat log_event volání před/po dispatch bodů v sekcích CP1 brainstorm Step 9, CP1 write Step 9 (added by P036), CP2 per-step (lines ~395-415), CP3 parallel (lines ~425-440), retry dispatches in CP2/CP3 fix loops)
- Modify: `plugins/aid-orchestrator/defaults/orchestration.yaml` (merge new fields into existing `dispatch:` block at lines 21-24 — currently has `strategy`, `max_parallel`, `worktree_base`; append `mode`, `inline_signature_format`, `timeline_window_seconds`)
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` (line 213-220 — "Plugin Discovery" section; extend the YAML template block to include `dispatch_mode: subagent`; append new section "Dispatch Mode Configuration" after Plugin Discovery section around line 225)
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (function `evaluate_compliance_checks` lines 254-377, extend verifier_outputs section lines 287-348)
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (function `write_compliance_json` lines 379-490, propagate new provenance fields through jq composition)
- Modify: `plugins/aid-orchestrator/scripts/aid-compliance-backfill.sh` (insert new `backfill_provenance()` function between `generate_pre_compliance()` (ends line 148) and `main()` (starts line 150); add **standalone outer loop (Step C)** AFTER existing Step A+B outer loops close at line 214 — uses own `find compliance.json` iteration, does NOT reference `run_dirs` local var from inner Step A/B loops)
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-anti-fabrication.bats`
- Modify: `CHANGELOG.md` (root, insert new `## [2.20.1]` section at line 6 — directly after format header, before existing `## [2.20.0]`)
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` (line 6 — byte-identical copy of root entry insertion)
- Modify: `.claude-plugin/marketplace.json` (JSON fields `metadata.version` + `plugins[0].version` — both → 2.20.1)
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` (line 3 — `"version": "2.20.0"` → `"version": "2.20.1"`)
- Modify: `plugins/aid-orchestrator/README.md` (regex `**Plugin:** 2.20.0` → `**Plugin:** 2.20.1`)
- Modify: `README.md` (Roadmap section line + tagline line, both regex `v2.20.0` → `v2.20.1`)
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.md` (append `## Acceptance Criteria` section after existing `## Resources Verification`, before `## Implementation Steps`)
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~680-690, after Check #19 EVALUATION block, add new sub-check #20 with sub-rules 20a/20b/20c, update EVALUATION counter `out of 24` → `out of 27`)
- Create: `plugins/aid-orchestrator/scripts/aid-plan-diff.sh` (new file, executable bash)
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (`cmd_init` function at line **653** — add optional `--plan <path>` named flag AFTER existing 7 positional args using `${8:-}`/`${9:-}` detection pattern alongside current `--force` check; write `plan_path:` line to fsm-state.yaml template with realpath-normalized absolute path or literal `null` for Fast Mode/manual EPICs)
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (add new `resolve_placeholders()` helper function before `run_gate()` invocation in `run_all_gates()` at line 84; add header docs section listing valid tokens; integrate fail-loud unknown-token check)
- Modify: `plugins/aid-orchestrator/defaults/execution.yaml` (TWO edits: (a) clean legacy `{base}` token at lines 28-29 in `docs_updated` gate → rename to `{base_commit}` to match scope_check convention; (b) append `plan_diff:` gate entry after `scope_check:` block, around line 38 after current scope_check end)
- Modify: `.aid-o/config/execution.yaml` (this project — append `plan_diff:` gate block mirroring defaults entry; AID dogfoods itself)
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (function `evaluate_compliance_checks` lines 254-377 — add plan_ac_match evaluation block, extend jq object output)
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (function `write_compliance_json` lines 446-468 — extend overall aggregation to include plan_ac_match)
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-plan-ac-diff.bats`
- Modify: `CHANGELOG.md` (root, insert new `## [2.20.2]` section at line 6 — directly after format header, before existing `## [2.20.1]`)
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` (line 6 — byte-identical copy of root entry)
- Modify: `.claude-plugin/marketplace.json` (JSON fields `metadata.version` + `plugins[0].version` — both → 2.20.2)
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` (line 3 — `"version": "2.20.1"` → `"version": "2.20.2"`)
- Modify: `plugins/aid-orchestrator/README.md` (regex `**Plugin:** 2.20.1` → `**Plugin:** 2.20.2`)
- Modify: `README.md` (Roadmap section + tagline regex `v2.20.1` → `v2.20.2`)
