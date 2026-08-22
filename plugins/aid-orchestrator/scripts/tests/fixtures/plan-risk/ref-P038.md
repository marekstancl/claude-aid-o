---
id: REF-P038
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P038-tiered-severity-merge-blocking.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P038

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines 172-213) — extend `fsm_handle_force_override` argument parser
- Modify: `plugins/aid-orchestrator/scripts/aid-audit-log.sh` (lines 17-64) — extend `cmd_append` with `-array` flag-suffix convention
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-tiered-severity.bats` — fixtures 3+4 (force-override with --blocked-checks, force-override with --reason <20 chars rejection)
- Create: `plugins/aid-orchestrator/defaults/check-severity.yaml` — initial registry per "Data Model" section above
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (function `write_compliance_json`, lines 543-665) — add failures[] population logic before the final jq write at line 632
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — extend the existing defaults-copy section (pattern at lines 275-295 for pre-commit/pre-push hook copy: source = `{plugin_path}/defaults/check-severity.yaml`, target = `.aid-o/config/check-severity.yaml`, idempotency rule = do not overwrite if target file already exists). The /aid-init copy logic lives in the slash-command markdown body, NOT in `scripts/lib/aid-init-execution-yaml.sh` (that file is a stack-aware composer for `execution.yaml` only — topology mismatch for generic config copy).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-tiered-severity.bats` — fixture 1 (failures[] populated correctly for blocking check) + fixture 2 (advisory check produces failures[] entry but does not block)
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (function `cmd_done_advance`, lines 1453-1580) — inject new precondition before existing checks at line 1492
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-tiered-severity.bats` — fixtures 1 (blocking blocks), 2 (advisory does not block), 3 (--force --blocked-checks proceeds)
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — add `cmd_promote_check` function (~80 LoC) and `cmd_check_promotion_candidates` function (~120 LoC); add dispatcher case entries at lines 1588-1602
- Create: `plugins/aid-orchestrator/scripts/aid-promote-checks.sh` — thin wrapper rendering markdown table from check-promotion-candidates stdout
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-tiered-severity.bats` — fixtures 5 (promote-check mutates yaml + appends audit-log event), 6 (check-promotion-candidates identifies ready candidates)
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-tiered-severity.bats` — 6 fixtures with setup/teardown
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-helpers.bash` (lines TBD per Step 5 implementation grep) — add `_load_aid_fsm` shim equivalent if not already exported, and any new helpers (e.g., `make_evidence_dir_with_compliance`)
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~720-907 — §7 DONE State) — insert new sub-section "Tiered Severity Enforcement" before "C+A Execution Model" (line ~791)
- Modify: `plugins/aid-orchestrator/skills/agent-protocol.md` — add a short reference subsection (existence verified at CP1; no need to grep-locate)
- Modify: `CHANGELOG.md` (root) — new `## [2.21.0] — 2026-05-XX` section
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — byte-identical copy of root CHANGELOG entry (per CLAUDE.md release policy)
- Modify: `CHANGELOG.md` (root) — header date filled in (replace `2026-05-XX` with today's UTC date)
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — same date update
- Modify: `.claude-plugin/marketplace.json` — `metadata.version: "2.21.0"` and `plugins[0].version: "2.21.0"`
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — `"version": "2.21.0"`
- Modify: `plugins/aid-orchestrator/README.md` — `**Plugin:** 2.21.0`
- Modify: `README.md` (root) — Roadmap section new line `**v2.21.0** (current) — tiered severity + merge blocking (AID-038 Phase 2)` and long-form badge line update
