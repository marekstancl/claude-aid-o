# Changelog

All notable changes to the AID Orchestrator plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [2.32.0] — 2026-06-15

### Added
- **Real-scale Visual Companion mockups** — when building UI on an existing frontend, the companion records the real dimensions (container/column widths, row heights, font sizes, spacing, breakpoints) from the live code and reproduces them 1:1, so a mockup reflects what actually fits on screen instead of an arbitrarily-scaled sketch.

### Changed
- **Visual Companion canvas always white** — the browser companion frame no longer follows OS dark mode (white page background, `color-scheme: light`, dark-mode media query removed), so mockups are always judged on the same white canvas the target UI uses.

### Fixed
- **pre-commit hook shebang** — the generated FSM-guard pre-commit hook had no shebang, so git ran it under `/bin/sh` (dash on Debian) where its bash syntax (`[[ ]]`, `< <(find …)`) failed and blocked every commit, forcing `--no-verify`; it now starts with `#!/usr/bin/env bash` and `/aid-init` retrofits the shebang onto hooks installed before the fix.

## [2.31.0] — 2026-06-14

### Added
- **Simplifier + Reporter at Plan Boundary** — two plan-boundary specialist agents run after a plan's last EPIC: the Simplifier proposes reuse/dedup/clarity refinements over the whole plan diff (S/M auto-applied through the gate-fixer → CP4 revert-on-fail rail, L deferred to the PM summary), and the Reporter tests the delivered functionality and writes a plain-language `.aid-o/reports/{plan_id}-delivery.md` from a fixed 7-section template, condensing the Auditor and Curator verdicts and leaving ≥1 on-disk test artifact as anti-fabrication proof. The new `delivery_report_present` compliance check (advisory, severity-routed) verifies the report's presence and on-disk `_test_evidence` at the plan boundary and rides the existing done-advance gate (`null` before the boundary, so it never false-blocks a non-final EPIC). Both agents are config-toggled and inert until a project re-inits.
- **Contributor guide (docs/extending-aid.md)** — a single reference documenting where each enforcement type lives (the type→instruction-home convention), the checklist to add one, the severity-layer vs hard-die FSM precondition patterns, the agent_tool dispatch-mode reality, and the P045 Simplifier + Reporter worked example.

## [2.29.4] — 2026-06-12

### Fixed
- **Force-Path Recovery Alert** — compliance blocks cleared via PM `--force` override never emitted the ✅ resolution alert because the force branch of done-advance skipped the entire P042 recovery block; recovery emission now lives in a shared helper (`fsm_emit_compliance_recovery`) called from both the clean re-run and the force-override paths, so every 🛑 blocked alert is paired with a ✅ regardless of how the block was cleared.
- **aid-init dispatch_mode Template** — the `/aid-init` plugin-discovery step still wrote `dispatch_mode: subagent` into `config/plugin.yaml` on every run, overriding the P043 `agent_tool` default and reintroducing guaranteed `verifier_provenance` false-positive blocks; the template now writes `agent_tool` and the dispatch-mode docs describe all three modes including the false-positive failure class.

## [2.29.3] — 2026-06-12

### Added
- **Check-severity sync guard** — new `test-check-severity-sync.sh` suite fails when a compliance check emitted by the FSM has no entry in `defaults/check-severity.yaml`, closing the trap where an unregistered check silently defaults to advisory and can never block
- **Compliance recovery alert documentation** — pipeline.md §7 now documents the P042 block/recovery Telegram alert pair, the `fsm_done_advance_recovered` dedup marker, and the `alert_on_compliance_recovery` config gate

### Changed
- **Accurate provenance aggregate in agent_tool mode** — compliance.json now reports `provenance_aggregate: "agent_tool"` instead of the misleading `"mixed"` when verifier dispatch runs via the CC Agent tool (non-blocking behavior unchanged)
- **dispatch_mode default single-sourced** — `defaults/orchestration.yaml` `dispatch.mode` is now the single source of the default (`agent_tool`, with all three modes documented); aid-fsm.sh resolves project `plugin.yaml` → plugin `orchestration.yaml` → hard fallback, removing the stale `subagent` doc/code drift
- **FSM internals simplification** — pure-bash `yaml_field()` reader replaces 51 copy-pasted `grep|awk` field reads (~100 fewer process forks per FSM run); repeated-fail counters, CP3 verifier-output evaluation, and the increment-step precondition fail ritual each consolidated into single helpers; shared `die()` moved to `lib/aid-stage-log.sh`; step-verify content checks read the file once; behavior unchanged (all 18 suites + 115 bats tests pass)

## [2.29.2] — 2026-06-10

### Changed
- **Visual Companion — current state mandatory in mockups** — when proposing UI changes to an existing component/page, the companion must always render the current look alongside the proposed changes (side-by-side or inline delta); showing only the new design in isolation is now explicitly prohibited; applies both in the "Read the Code First" refactoring flow and as a general design tip

## [2.29.1] — 2026-06-09

### Fixed
- **verifier_provenance false-positive blocking** — `dispatch_mode` defaulted to `subagent`, which requires `verifier_dispatch_start/complete` timeline events that the CC Agent tool never writes; every EPIC in standard AID self-hosted operation was therefore permanently blocked on `verifier_provenance`; the default is now `agent_tool` (set `dispatch_mode: subagent` in `.aid-o/config/plugin.yaml` to opt into strict interval-bracket provenance enforcement); a new `verify_provenance` branch returns a non-blocking `"agent_tool"` signal so `provenance_aggregate` never escalates to `"unverifiable"` in this mode

## [2.29.0] — 2026-06-07

### Added
- **Compliance recovery alert** — when a `done-advance review→release` succeeds with zero blocking failures for an EPIC that previously emitted a `🛑 release blocked` alert, AID now emits a `✅ compliance cleared, release unblocked` Telegram alert and writes an `fsm_done_advance_recovered` timeline event (dedup marker, observable test signal); controlled by `alert_on_compliance_recovery` config gate (default on)

## [2.28.3] — 2026-06-06

### Fixed
- **Self-referential dependencies** — a step whose dependency range covered its own number (e.g. "Steps 4-6" on step 6) produced a meaningless self-edge that downstream cycle detection rejected; self-references are now dropped during dependency remapping
- **Task-keyword dependencies** — `Depends on: Task N` / `Tasks M-N` lines were silently ignored because the parser only recognized "Step", even though `## Task N:` step headers are accepted; the dependency parser now treats the Task keyword the same as Step
- **Clean-tree guard vs. runtime queue** — the FSM init clean-tree guard aborted on any tracked change including AID's own `.aid-o/config/queue.yaml`, which the auto-pipeline mutates between phases, breaking multi-phase auto runs in projects where that file is tracked; the guard now excludes the runtime queue file
- **/aid-init .gitignore backfill** — `.gitignore` setup skipped the entire AID block when any `.aid-o/` entry already existed, so projects initialized before a later ignore entry (e.g. the runtime queue file) never received it; setup now appends individual missing lines on upgrade

## [2.28.2] — 2026-06-06

### Fixed
- **EPIC dependency renumbering** — when slicing a multi-EPIC plan into per-EPIC files, the Steps table renumbered each EPIC's steps locally (1..N) but the Depends On column kept the plan's global step numbers, producing dangling references like "step 2 depends on 4" in a 3-step EPIC that crashed dependency validation in `aid-epic-to-json.sh`; intra-EPIC dependencies (and the Goal step list) are now remapped to EPIC-local numbering

## [2.28.1] — 2026-06-04

### Fixed
- **FSM force-transition crash** — `aid-fsm.sh transition --force` aborted under `set -u` with "project_root: unbound variable" because `fsm_emit_audit_log` read the variable before its guarded fallback, breaking the manual-override escape hatch
- **CI bash test coverage** — the FSM, release, and integration test suites were silently skipped in CI (no `bats` installed) and had drifted stale against new preconditions; CI now installs `bats`, the four affected suites are repaired, and the FSM precondition layer gained real red/green coverage so it cannot be weakened unnoticed

## [2.28.0] — 2026-06-04

### Added
- **Skill & command authoring standards** — `skill-writing.md` and `command-writing.md` promoted to live skills, with `aid-lint-skill.sh` + `test-skill-lint.sh` enforcing the mechanical subset (pre-existing files grandfathered until revised)
- **Frontend Visual Anchoring enforcement** — `increment-step` hard-fails a frontend step that has `visual_refs` but whose output lacks a `## Visual Anchoring` section

### Changed
- **Model single source of truth** — model tier lives only in `role-cards.md`; removed the conflicting `orchestration.yaml` models block and the phantom `role_assignments` reference
- **role-cards.md holistic unification** — `e2e` is now a real step role with one rich card; `docs` renamed to `docs-writer` everywhere; `qa` gets a full card; structure and footer unified
- **Curator is propose-only** — curator recommends a disposition, the orchestrator applies fixes at every effort (S/M/L), and CP4 reviews the applied changes (reordered to run after the apply)
- **auditor.md overhaul** — scorable A–J categories, corrected scoring math, pre-merge timing
- **planner.md rewrite** — documents the real two-script pipeline (no fictional intelligent planner)
- **Config-policy single-sourcing** — escalation triggers and `skill_conflicts` deduplicated to one authoritative source; pre-filter regexes single-sourced to `pre-filter-rules.yaml`; `not_acceptable` patterns routed to real enforcement or explicitly marked advisory

### Fixed
- **Verifier provenance false-positives** — interval-bracket window replaces the ±60s test that flagged honest runs; fails closed when the severity registry can't be read; renamed the verdict to the honest `unverifiable` and added an explicit anti-fabrication instruction to the orchestrator
- **aid-run.md fiction + task→epic terminology** — removed non-existent state transitions / branch / merge-target claims
- **role_overrides downgraded to advisory** — the global `Bash(*)` permission made per-role scoping non-enforcing; the false security claim was removed
- **deserialize_dangerous pre-filter rule** — a `(?!_safe)` lookahead (unsupported by bash ERE) made the rule silently never match; rewritten ERE-safe
- **Honest phase-end note** — `run-management.md` no longer claims the controller auto-enforces the PM-GO boundary

### Removed
- **Unread config** — `orchestration.yaml` `models:` block and `release.skip_when`, and the `execution.yaml` global `retry:` block — read by nothing (per-gate `max_retries` is the only retry knob)

## [2.27.0] — 2026-06-02

### Changed
- **FSM state file unified to `fsm-state.yaml`** — retired the parallel `state.yaml` step-array that `aid-epic-to-json.sh` wrote but nothing read; every script, doc, template, and test now refers to the single FSM state file `fsm-state.yaml`, with the legacy `state.yaml` name kept only as a read fallback for in-flight pre-migration runs.

### Fixed
- **`/aid-stop` + `/aid-run --resume` state handling** — `/aid-stop` dropped the invented `session.*` schema, now reads the real `fsm-state.yaml` fields and logs the stop event through the canonical timeline helper; `--resume` reads `fsm-state.yaml`.

### Removed
- **Queue `pause` / `resume` / `reorder` subcommands** — removed from `/aid-status` and help; documented but never backed by any script (archived, restorable).

## [2.26.0] — 2026-06-01

### Changed
- **Documentation hygiene** — stripped version-stamped headings (e.g. `(NEW v2.16.0 — P032)`) from pipeline.md, agent-protocol.md, and related skills/commands; refreshed stale `Last Updated` dates; reconciled the brainstorming severity-enum claim and the aid-status `{epic_id}` naming drift.

### Fixed
- **aid-help level detection** — counted `state: DONE` in `state.yaml` (never written by the FSM), so every user showed Level 0; now reads `fsm-state.yaml`.
- **aid-init pre-push hook docs** — clarified pre-push uses its own marker `AID-ORCHESTRATOR-PREPUSH-START` (not the pre-commit marker), preventing duplicate hook blocks on re-run.
- **CP4 curator-validation filename** — verifier-output-template + verifier.md now name the FSM-required `verifier-output-cp4-curator-validation.md`; corrected the false "FSM does NOT enforce" note.
- **implementer model selection** — replaced the duplicated, incomplete model-tier list with a pointer to role-cards.md (single source of truth covering all roles).
- **brainstorming prior-work scan** — globbed nonexistent `.aid-o/epics/`; now `.aid-o/tasks/`.

### Removed
- **aid-research command + knowledge/Context7 layer** — removed the never-wired on-demand research command, its knowledge-base template, the integrations `knowledge:` config, the `context_scope.knowledge` plan-schema flag, and all orphaned Context7 references; archived to `docs/plans/AID-audit-2026-06/removed/` (restorable). The layer had no producer wired and no consumer.

## [2.25.0] — 2026-05-31

### Added
- **aid-emit-dispatch.sh wrapper** — new bash CLI with `start` and `complete` subcommands the orchestrator MUST call before/after every `Agent({subagent_type, prompt})` dispatch; writes `verifier_dispatch_start`/`_complete` events to timeline.jsonl plus tracks state in pending-dispatches.jsonl per evidence dir.
- **fsm_check_orphan_dispatches function** — reconciliation backstop in cmd_increment_step that refuses step transitions when pending-dispatches.jsonl shows a start event older than expected_duration_max without matching complete.
- **fsm_check_cp4_curator_validation function** — precondition in cmd_done_advance review→release that requires verifier-output-cp4-curator-validation.md when curator-report.md exists and any commit in `base_commit..HEAD` range touches production code paths. Mode-aware: skips with `cp4_skipped_streamlined_advisory` audit event when streamlined_mode is true.
- **fsm_check_streamlined_integration_review function** — precondition in cmd_done_advance review→release that, when streamlined_mode is true, requires all three of `verifier-output-cp3-code-review.md`, `verifier-output-cp3-security.md`, `gates_report.json` present in the evidence dir.
- **fsm_check_streamlined_abandoned function** — abandoned-but-shipped detector in cmd_done_advance that fires when streamlined_mode is true and timeline.jsonl has fewer than 3 events.
- **--streamlined CLI flag in cmd_init** — first-class lightweight execution mode that writes `streamlined_mode: true` into fsm-state.yaml and propagates through cmd_increment_step / cmd_done_advance / write_compliance_json.
- **coverage_mode + skipped_dimensions fields in compliance.json** — honest accounting of which dimensions were intentionally skipped per the streamlined contract. Field name `coverage_mode` (not `mode`) avoids collision with the existing fsm-state.yaml `mode` (manual/auto execution mode).
- **Four blocking checks in defaults/check-severity.yaml** — `dispatch_orphan_complete`, `cp4_curator_validation`, `streamlined_abandoned`, `streamlined_integration_review`, all severity blocking per AID-v3-principles.md §1 with explicit PM promotion (NR 8-14 empirical evidence across 4 projects).
- **cp4_production_paths field in defaults/execution.yaml** — configurable glob alternation for CP4 trigger detection; `/aid-init` stack-scan in `scripts/lib/aid-init-execution-yaml.sh` auto-populates project-specific defaults.
- **aid-json-to-run.sh Step 18 auto-init** — calls `aid-fsm.sh init` after run.md generation when fsm-state.yaml is absent, eliminating state.yaml vs fsm-state.yaml confusion (NR 10/12/14 anchor). Accepts a `--streamlined` passthrough (threaded from `/aid-run --streamlined` and `aid-auto-pipeline.sh`) that forwards to `cmd_init` so the auto-initialized state carries `streamlined_mode: true` — without it the streamlined activation switch would be unreachable.
- **test-aid-emit-dispatch.bats** — eleven fixtures: the original eight (start-only, start+complete pair, orphan complete, ceiling clamp, concurrent flock, missing output_file, malformed agent_id, inode-swap race) plus three CP3-security fixtures (`--focus` injection rejected by allowlist, jq-escaped pending construction, per-start nonce prevents ledger double-clear).

### Changed
- **cmd_increment_step preconditions** — added Component B orphan-dispatch backstop after the existing memory_used/memory_written/verifier_output checks; conditionally skips the per-step verifier_output check when streamlined_mode is true.
- **cmd_done_advance review→release preconditions** — added Component D streamlined_integration_review check, streamlined_abandoned check, and Component C CP4 enforcement (mode-aware in streamlined); all wired before the existing curator-report check; cites AID-v3-principles.md §1.
- **write_compliance_json schema** — emits top-level coverage_mode and skipped_dimensions fields; backward-compatible (legacy compliance.json without these reads as coverage_mode "full", skipped_dimensions []). The `mode` → `coverage_mode` rename is a breaking change for any downstream consumer that read the v0 draft.
- **fsm-state.yaml unified schema** — absorbs the legacy state.yaml steps[] array; backward-compat dual-file reader preserved.
- **skills/pipeline.md** — new §4 Dispatch Protocol subsection documenting the mandatory aid-emit-dispatch.sh wrapper chain; PRE-FLIGHT auto-init note.
- **skills/agent-protocol.md** — reference tables for the new audit events and check-severity entries.
- **commands/aid-run.md, commands/aid-plan.md, commands/aid-do.md** — --streamlined flag documentation and advisory trigger criteria.

## [2.24.0] — 2026-05-31

### Added
- **FSM Artifact Templates (`step-verify-template.md` + `verifier-output-template.md`)** — two new templates in `defaults/templates/` document the exact section/field schema enforced by `aid-fsm.sh` preconditions. `step-verify-template.md` lists the six required sections (Acceptance Criteria with `- [x]` checkboxes, Commit with 7+ hex SHA, Memory Used, Memory Written, Files, Result: PASS) each annotated with the failing `cmd_increment_step` reason. `verifier-output-template.md` is a single file covering all four CP variants (CP2 per-step, CP3 code-review, CP3 security, CP4 curator) with line-start `_generated_by:` / `classification:` / `verdict:` fields tied to `fsm_check_verifier_output`. Empirically motivated: WAN P027 EPIC 1 had 11 FSM precondition failures (5 from undocumented step-verify schema, 3 from undocumented `_generated_by` schema) while EPIC 2 had 0 — proving the schema is learnable, so it should be documented up-front rather than discovered through failure (NR 10 §4D, NR 12 §4A, NR 14 RC1).

### Fixed
- **`aid-plan-to-epic.sh` step counter fenced-block bug** — parser regex `^###?[[:space:]]+(Step|Task)[[:space:]]+([0-9]+)` previously matched `### Step N:` headers inside fenced code blocks, so any plan *about AID itself* that quoted AID step syntax got mis-counted and the pipeline crashed with `objective too short` errors. Fix tracks fence depth (toggle on lines matching `^[[:space:]]*````) across four scan sites: `has_impl_steps` awk quick-check, main step-numbering while-loop, `extract_step_content()` awk helper, and the objective-fallback awk. `aid-epic-to-json.sh` confirmed unaffected (parses EPIC table rows, not plan.md headers). New `test-aid-plan-to-epic-fence.bats` fixture reliably fails pre-fix and passes post-fix. Empirical anchor: AID-self P039 (v2.23.0 brainstorming plan) tripped this bug — NR 14 §4D.
- **`defaults/policies/permissions.yaml` stale MCP refs (action required: re-run `/aid-setup permissions`)** — the autonomous preset whitelist referenced MCP servers that no longer exist in current eco infrastructure: `qdrant-memory__*`, `shared-docker__*`, `shared-minio__*`, `shared-postgres__*`, `shared-playwright__*`, `shared-telegram__*`. Replaced with the actual running set: `vulcan-memory__{find,store,list}` (excluding destructive `vulcan-delete`), `eco-admin__*` 12 GREEN read-only tools (YELLOW writes intentionally excluded — require Telegram approval per ADR-17 D-077), `claude_ai_Google_Drive__*` 6 read-only ops. Kept `shared-github`, `shared-sequential-thinking`, `svc-mcp-tg-bot__send_message`, `plugin_context7_context7`, and `qdrant-brain` (back-compat with `skills/memory-mcp.md` contract). Playwright explicitly NOT auto-allowed — opt-in via per-project `settings.local.json`. Empirical anchor: NR 11 manual audit. **Existing projects that already ran `/aid-setup` retain stale entries in their local `.claude/settings.local.json` and should re-run `/aid-setup permissions` to refresh.**

## [2.23.0] — 2026-05-31

### Added
- **Section-Review Validate-Then-Verify** — brainstorming Step 6 sections now run a Sonnet `section-review` critic followed by an Opus ground-truth re-grep, presenting the PM a claim-verification table (validator claim → real command + output → ✓/✗) before approval; Step 7 adds a `cross-section-review` consistency check over the assembled plan.

### Fixed
- **Verifier focus card naming** — the `security-review` card in `role-cards.md` is renamed to `security` to match the canonical focus name used plugin-wide (orchestration tier, CP3 dispatch, planner, aid-run, epic templates); resolves a latent card-name mismatch with the registry.

## [2.22.3] — 2026-05-14

### Fixed
- **`skills/brainstorming.md` references to renamed visual-companion path** — v2.22.1 moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` but left two stale `skills/visual-companion.md` references in `brainstorming.md` (lines 107 and 258). The `test-instruction-consistency` bash suite caught it (`✗ Referenced file MISSING`) and CI went red since v2.22.1's push. Both references updated to the directory form.

## [2.22.2] — 2026-05-14

### Changed
- **Visual Companion — explicit remote-host networking + read-first-before-redesign rule** — Standalone Invocation Step 3 now mandates picking server bind mode (`127.0.0.1` for local agent / `0.0.0.0 --url-host <IP>` for remote SSH-VPN setup) BEFORE starting the server, with detection cues (`$SSH_CONNECTION` env, `hostname -I`) and a direct ask-PM fallback. Previously the remote case was a buried footnote, leaving the agent to start a loopback-only server that PM's browser couldn't reach. Plus new "Refactoring or Redesigning Existing UI — Read the Code First" section: when PM references an existing component / screenshot / page name, agent MUST ask "should I read the current implementation first?" and produce a structured data-inventory in chat before any mockup. Saves the iteration cycles where mockups get drawn against guessed data shapes and need full rewrite after the real component is read.

## [2.22.1] — 2026-05-13

### Fixed
- **Visual Companion skill discovery (hotfix v2.22.0)** — moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` directory structure. Claude Code's plugin loader only recognizes skills as user-invokable (slash-callable) when they live in `skills/<name>/SKILL.md` form; flat files are loaded for in-plugin reference but never registered as `/<name>` slash commands regardless of any `user_invocable` frontmatter flag. v2.22.0 release flipped the flag and added the standalone section but kept the flat-file shape, so `/visual-companion` did not appear in the command palette. This release fixes the structure only — no content changes.

## [2.22.0] — 2026-05-13

### Changed
- **Visual Companion skill is now user-invocable** — `/visual-companion` slash command opens a standalone demo session for verifying the browser round-trip (server start, HTML push, click capture, events read) without going through the full `/aid-plan brainstorm` flow. Skill frontmatter flipped `user_invocable: false → true` and a new "Standalone Invocation" section was added with explicit start/stop steps, npm-install first-run handling, and node_modules fallback path. Skill remains backward-compatible with the existing brainstorming integration — per-question gate behavior inside `/aid-plan brainstorm` is unchanged.

## [2.21.1] — 2026-05-13

### Fixed
- **`try_telegram_alert` test-mode guard** — `AID_TEST_MODE=1` env var short-circuits the helper before any `jq` or `curl` invocation, so bats fixtures and smoke tests no longer fire real-world Telegram alerts. Discovered post-P038 ship: cmd_done_advance blocking precondition (Step 3) and 3 other call sites previously emitted ~30 alerts during fixture development with `E-TEST-038: 1 blocking compliance failure(s)`. Shared bats `setup_test_evidence_dir` (test-helpers.bash) and `test-tiered-severity.bats` `setup()` now export the guard. Convention: any future side-effect helper (mail/Slack/webhook) should mirror this pattern.

## [2.21.0] — 2026-05-13

### Added
- **Tiered severity registry** — `.aid-o/config/check-severity.yaml` declares each compliance check as `blocking` or `advisory`; shipped by `/aid-init` with initial bootstrap per AID-v3-principles.md §1
- **`failures[]` array in compliance.json** — every release writes per-check failure entries with severity, evidence, and promoted_at, enabling deterministic blocking decisions
- **`aid-fsm.sh promote-check`** — explicit advisory→blocking promotion with mandatory ≥20-char reason and forensic audit-log entry
- **`aid-fsm.sh check-promotion-candidates`** — read-only scan of audit-log.jsonl identifying advisory checks that meet the AID-v3-principles.md §1 promotion criterion (force_override_rate < 0.05 across N≥5 EPICs)
- **`aid-promote-checks.sh`** — PM-facing markdown report wrapping the candidate scan
- **`test-tiered-severity.bats`** — 6 fixtures covering blocking-blocks, advisory-passes, --force-with-audit, short-reason-rejection, promote-check, and candidate identification

### Changed
- **`cmd_done_advance review→release`** — now refuses transition when any compliance failure has `severity: blocking`; structured error message includes per-failure evidence and copy-paste `--force --reason --blocked-checks` override snippet; per AID-v3-principles.md §1 "Detector without Enforcement is Decoration", this is the first concrete application of the principle and closes the P026 (WAN, 2026-05-13) failure mode
- **`fsm_handle_force_override`** — accepts new `--blocked-checks "<comma-list>"` flag; propagates to both timeline.jsonl and audit-log.jsonl
- **`aid-audit-log.sh cmd_append`** — new `--<key>-array "a,b,c"` flag-suffix convention emits JSON arrays in output entries; dash-to-underscore JSON key normalization for compatibility
- **`pipeline.md §7 DONE State`** — new "Tiered Severity Enforcement" sub-section documenting the override flow, the severity table, and the promotion ceremony
- **`write_compliance_json`** — populates `failures[]` array using check-severity.yaml registry; backward compatible (empty array when no failures)

## [2.20.2] — 2026-05-12

### Added
- **Plan-AC Diff Gate (P037 Phase 2, AID-010)** — new deterministic gate `plan_diff` in `execution.yaml` runs `aid-plan-diff.sh` after EXECUTE→GATES. Script parses plan-level `## Acceptance Criteria` section, executes each `verification_pattern` (3 types: `cmd`, `must_not_exist`, `must_contain` with any-match regex semantics) against codebase HEAD, emits `plan-diff.json` with per-AC verdict. Fail if ≥1 AC absent.
- **`aid-plan-diff.sh` Standalone Script** — new 281-line bash script under `plugins/aid-orchestrator/scripts/`. Standalone testable lifecycle (own provenance fields `_generated_by: aid-plan-diff.sh@v2.20.2`, own timeline events `plan_diff_start`/`plan_diff_complete`). 4 exit codes: 0 (all present), 1 (≥1 absent), 2 (graceful skip — Fast Mode or no AC section), 10 (input validation).
- **Plan Template AC Block** — `defaults/templates/plan.md` extended with `## Acceptance Criteria` section template using executable `verification_pattern` blocks (3 example patterns: cmd, must_not_exist, must_contain). New plans (P038+) gain plan-level AC verification by default.
- **Completeness Gate Sub-Check #20** — `plan-writing.md` Completeness Gate added 3 sub-rules (20a/20b/20c) enforcing `verification_pattern` block on every AC for new plans; legacy plans (P001-P036) without AC section skip the check (no violation). EVALUATION counter updated `out of 24` → `out of 27`.
- **`compliance.json plan_ac_match` Dimension** — `evaluate_compliance_checks` reads `plan-diff.json`, sets `checks.plan_ac_match: true | false | null`. False forces `compliance.overall: "fail"`; null = graceful skip for legacy plans or missing plan-diff.json.
- **`{plan_path}` Placeholder Token** — `aid-run-gates.sh` `resolve_placeholders()` helper substitutes 4 known tokens (`{plan_path}`, `{epic_id}`, `{run_id}`, `{base_commit}`) in gate commands via bash parameter expansion. `cmd_init` writes `plan_path:` field to state.yaml (realpath-normalized absolute path or literal `null` for Fast Mode EPICs). Unknown `{<token>}` triggers fail-loud exit — silent pass-through is a debug trap.
- **Plan-AC Diff Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-plan-ac-diff.bats` (8 tests covering all 3 pattern types, fail path, Fast Mode null + empty, legacy skip, resolve_placeholders + cmd_init replicas). Full bats suite now 52/52 ok.

### Changed
- **`aid-run-gates.sh` Gate Command Resolution** — gate commands now pass through `resolve_placeholders()` before `bash -c` execution. Exit code 2 counts as pass when gate's `pass_criteria` mentions "exit 2" (graceful-skip pattern).
- **`defaults/execution.yaml`** — legacy `{base}..HEAD` tokens in `docs_updated` gate renamed to `{base_commit}..HEAD` (aligning with `scope_check` convention; required for resolve_placeholders fail-loud safety). New `plan_diff:` gate entry appended after `scope_check:` (required: true, max_retries: 0, pass_criteria documents exit 0 or exit 2).

### Fixed
- **Goalpost Shift Detection** — Five EPICs (P019 F1+F2 frontend migration, P021 F4 backlog collision, P022 F6 Playwright→backend substitution, P023 F7 five concurrent shifts) previously passed to DONE without detection because gates didn't check plan AC reality vs implementation. Phase 2 `plan_diff` gate catches this class — every new plan with `verification_pattern` blocks gets per-AC executable verification on codebase HEAD before GATES→DONE.
- **`cp2_per_step_provenance` Type Mismatch (IMP-100)** — backfill in `aid-compliance-backfill.sh` previously wrote scalar string `"unknown"` for `cp2_per_step_provenance`, while the live writer in `aid-fsm.sh evaluate_compliance_checks` emits a JSON array (one entry per CP2 step). Type drift created silent correctness risk for queries doing `| length`. Backfill now writes `["unknown"]` (single-element array) to match live writer shape. Other 3 fields (cp3_*, provenance_aggregate) remain scalar — consistent with live writer.
- **`backfill_provenance` Silent Error Conflation (IMP-102)** — previously returned exit 1 for both "already-present skip" (normal) and "jq failure" (corrupted compliance.json). Step C caller incremented skip-count for both, masking real errors. Function now returns 0 (fixed), 1 (jq failure with stderr WARN), 2 (idempotent skip); caller case-statements on exit code and reports backfilled/skipped/errors separately in summary heredoc.
- **`verify_provenance` Unused `step_n` Parameter (IMP-103)** — `$3` was received in signature but never referenced in body. Renamed to `_step_n` with code comment explaining intentional retention for future per-step forensic attribution. Positional API stable (no call-site changes needed).
- **CLI Dispatcher Help Message Clarity (IMP-104)** — `aid-stage-log.sh` dispatcher previously listed `log_event`, `log_info`, `log_warn`, `log_error` uniformly in help text, leading users to expect timeline writes from all four. Comment + help message now distinguish: only `log_event` writes to timeline; `log_info`/`log_warn`/`log_error` are stderr-only severity-prefixed echoes.
- **`aid-fsm.sh` Missing `BASH_SOURCE` Guard** — top-level case dispatcher previously exited 1 on unknown args even when the file was sourced (e.g. from bats test fixtures), killing the test process. Dispatcher now wrapped in `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` (same pattern as `aid-stage-log.sh` fix from v2.20.1). Sourcing for testing purposes works cleanly. Existing `_load_aid_fsm` shim in `test-anti-fabrication.bats` becomes redundant but harmless.

## [2.20.1] — 2026-05-12

### Added
- **Verifier Provenance Verification (P037 Phase 1, AID-038)** — `aid-fsm.sh evaluate_compliance_checks` cross-references each `verifier-output-*.md` `_generated_by` field against `timeline.jsonl` `verifier_dispatch_start`/`_complete` events within a ±60s window for subagent mode, or validates `main-context@<commit-sha>` format with SHA verification for inline mode. Detected fabrication forces `compliance.overall: "fail"`.
- **Timeline Dispatch Events** — `pipeline.md` now instructs LLM to emit `verifier_dispatch_start` and `verifier_dispatch_complete` events with payload `{agentId, focus, step_n, evidence_dir, ts}` around every CP1/CP2/CP3 verifier `Agent()` call.
- **Honest Mode for No-Subagent Projects** — `.aid-o/config/plugin.yaml` new field `dispatch_mode: subagent | inline` (default subagent). Inline mode requires `_generated_by: main-context@<git-HEAD-sha>` format for verifier outputs; compliance check validates format + SHA existence rather than timeline match.
- **CLI Dispatcher for aid-stage-log.sh** — library now supports `bash aid-stage-log.sh <fn> <args>` invocation in addition to existing source-mode usage. Guard via `BASH_SOURCE[0] == ${0}` keeps source-mode behavior unchanged. Required so `pipeline.md` and `aid-plan.md` LLM-rendered docs can invoke `log_event` directly without a separate source step. Unknown function exits 1 with stderr help message listing available functions.
- **Anti-Fabrication Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-anti-fabrication.bats` (4 tests): verified subagent dispatch produces `provenance_aggregate: all_verified`; missing timeline events produce `fabricated` + `overall: fail`; inline mode with valid SHA produces `all_inline` + `pass`; CLI dispatcher regression test.

### Changed
- **`evaluate_compliance_checks` Schema** — `verifier_outputs` object now carries three new `*_provenance` fields (`cp2_per_step_provenance`, `cp3_code_review_provenance`, `cp3_security_provenance`) plus aggregate `provenance_aggregate: "all_verified" | "all_inline" | "mixed" | "fabricated" | "unknown"`. Pre-Phase-1 compliance.json files backfilled via `aid-compliance-backfill.sh` Step C (idempotent merge, adds `provenance: unknown` audit note attributing the migration to P037).

### Fixed
- **Compliance Telemetry Honesty** — post-Session-B telemetry (n=8 EPICs reporting 100% pass on all 4 dimensions) was previously vulnerable to fabricated `_generated_by` metadata. P023 reflection (NR 5, 2026-05-11) documented one such case in WAN project where agent wrote verifier outputs in main context but signed them as `aid-orchestrator:verifier@cp{2,3}-*`. Phase 1 enforcement detects this class of cheating.
- **`verify_provenance` TZ Bug** — jq <1.7 silently honors local TZ in `fromdateiso8601` even with `Z` suffix, producing a 1-hour offset on non-UTC hosts (CEST/PST/etc) and reading every dispatch as fabricated. Both `jq -s` invocations in `verify_provenance()` are now prefixed `TZ=UTC` so date parsing matches the `date -d`-derived `$min`/`$max` UTC epochs. Surfaced by Step 5 bats smoke test on CEST host.

## [2.20.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Check 17e (CLI Invocation Grounding)** — `plan-writing.md` Completeness Gate extended with 7th grounding category: for every cited `bash <script> <args>` in Implementation Detail blocks or step examples, verify the args against the actual script interface via `<script> --help` (preferred) or `head -100 <script>` (fallback). Mismatched signatures → REVISE_REQUIRED with suggested correction. Empirical: P035 C1 (2026-05-10) — plan cited a `--state-file` flag that did not exist in `aid-run-gates.sh` at write time; CP1 caught it on the 2nd pass.
- **Completeness Gate Check #19 (Design Defeat Detection)** — semantic LLM check active for plans with `type: bug-fix` in frontmatter. Reviewer answers Q1 (which precondition is being fixed?), Q2 (does the new code-path go through that same precondition?), Q3 (if not, is the bypass explicit + justified?). Q2:no + Q3:no → REVISE_REQUIRED. Pre-screening heuristic (mechanical) auto-activates #19 when goal/context contains fix/fail/bypass/precondition/validation AND the plan mutates `fsm-state.yaml` or `state.yaml` directly without a `cmd_<wrapper>` invocation. Heuristic explicitly EXCLUDES release/version mutations (CHANGELOG, README, marketplace.json, plugin.json, files in `release-policy.yaml` `version_files[]`) to prevent false positives on release plans. Empirical: P035 C2 — `yq -i '.state = "GATES"'` bypassed `cmd_transition()` and would have silently defeated the fix's own purpose.
- **Plan Type Taxonomy (`type:` frontmatter field)** — `defaults/templates/plan.md` now defines an enum `type: regular | bug-fix | refactor | docs` controlling which Completeness Gate checks activate per plan type. Default if missing: `regular`. Legacy `type: plan` (P001-P035 convention) treated as alias for `regular` — no migration required. Documented in new `## Plan Type` template section with a 4-row activation table.
- **`/aid-plan write` Mode Step 9 (CP1 Plan Quality Review)** — write mode extended from 8 to 9 steps; Step 9 mirrors brainstorm Step 9 (verifier dispatch with `docs-review` focus, codebase grounding pass, save review to `.aid-o/work/cp1-review-{plan_id}.md`). Activates #19 when `type: bug-fix` or pre-screening matches. Skip via `review_checkpoints.cp1_plan_review: false`. Closes the gap where plans written through `/aid-plan write` previously had no post-write quality review.
- **CP1 Verifier EVIDENCE REQUIREMENT** — Step 9 verifier prompt now requires concrete evidence (`command_run` + `output_excerpt`) before marking ANY item VERIFIED. Missing evidence → REJECTED with auto-retry; max 2 retries then ESCALATION. Applies to all #17 sub-checks + 17a-d + 17e + #19 (Q1/Q2/Q3 must cite plan path:line + codebase path:line). Empirical: P035 C3 — three bats helpers cited as "existing" from memory; none existed.
- **`test-plan-quality-enforcement.sh` Smoke Test** — bash smoke test exercising all 4 enforcement layers against a deliberately-defective fixture plan: layer 1 (extract `bash <script> --flag` + verify against real interface, with SKIP for already-shifted baseline), layer 2 (3-conjunctive heuristic positive + release-mutation negative control), layer 3 (count `^9.` in Mode: Write Plan section), layer 4 (header + field-name hits for EVIDENCE REQUIREMENT). Auto-discovered by `run-all-tests.sh`.

## [2.19.1] — 2026-05-10

### Fixed
- **`aid-release.sh` CHANGELOG-rename anomaly (IMP-093)** — observed 3× across v2.18.3 + v2.19.0 releases: when a `## [X.Y.Z]` header was pre-written for the upcoming release (PM/agent edited CHANGELOG before invoking script), the previous logic did a blind `sed`-replace on the newest header and silently collapsed the pre-written entry's history. Fix: detect actually-released version from `plugin.json`/`marketplace.json`/`package.json` (not CHANGELOG header) and route through new `update_changelog` helper that has 3 branches: (a) header matches new_version → skip rename (entry already correct), (b) header matches released version → bump existing header (existing behavior), (c) header is some other version → prepend new entry above (preserves history). 3 new bats assertions in `test-aid-release.bats` cover all 3 branches.

### Notes
- **README regex pattern mismatch** — second part of IMP-093 diagnosis showed that `.aid-o/config/project.yaml` regex patterns like `"Plugin: {VERSION}"` don't match actual content `**Plugin:** 2.X.Y` (markdown bold prefix missing in pattern). Consumer projects must update their `.aid-o/config/project.yaml` regex patterns to escape `**` for sed: e.g., `"\\*\\*Plugin:\\*\\* {VERSION}"`. This repo's `.aid-o/config/project.yaml` (gitignored) was updated locally; downstream projects need to edit theirs once if affected.

## [2.19.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Checks 17a–17d** — `plan-writing.md` Completeness Gate extended with 4 new grounding categories aimed at empirical gaps from P019/P021/P032: (17a) backlog ID grounding via whole-plan `\bT-[0-9]+\b` regex + `git log --since="24 hours ago" --grep` — empirical: P021 T-132/T-133 reserved by commit 1907e77 same morning; (17b) test directory convention via POSIX `find tests/ -type f -name "*<basename>*"` — empirical: P021 plan said `tests/integration/`, reality `tests/unit/`; (17c) DB-field semantics via `[A-Z][a-zA-Z]+\.[a-z_]+` regex + `grep` on models.py for stored Column vs `@property`/computed — empirical: P021 assumed automatic, reality stored Column; (17d) file removal grounding via `ls <path>` existence check — empirical: P019 `must_not_exist` file actually existed at EPIC end. EVALUATION counter bumped 18 → 22.
- **`commands/aid-plan.md` Step 9 Verifier Prompt Extension** — verifier dispatch prompt extended with extraction patterns and verification commands for the 4 new grounding categories. Each category gets explicit VERIFIED/ABSENT semantics and REVISE_REQUIRED conditions. Backlog ID ABSENT accepts "T-NNN to be allocated at plan-write time" as a plan-allocation candidate.
- **`defaults/templates/plan.md` Resources Verification Block** — new section between Constraints and Risks with 12 checkbox items: 6 (Existing Resources from #17) + 4 (Plan Assumptions from #17a-d) + 2 (Resolution gates). Auto-populated by `/aid-plan` Step 9 verifier dispatch; PM-visible manual review checklist. Detection scope clarified as whole-plan body scan — no `related_backlog` or similar field required.
- **`test-cp1-grounding.sh` Smoke Test** — bash smoke test that constructs a deliberately-broken plan with violations across all 4 sub-checks and verifies extraction patterns produce correct outputs. POSIX-only (`command -v find` guard, no `fd` dependency), trap-cleaned tmpdir, 5 PASS branches.

## [2.18.3] — 2026-05-10

### Added
- **`aid-fsm.sh advance-to-gates` Atomic Command** — single command runs gates and routes through `cmd_transition EXECUTE GATES` on success. Eliminates the `gates_no_generated_by` chicken-egg precondition fail (P020 8×, P021 4× — 12 friction events across 3 EPICs). Atomicity: state changes only on full success; gates failure leaves state at EXECUTE (never modified). No new state added — `VALID_STATES` and `VALID_TRANSITIONS` unchanged. Single source of truth for preconditions remains `check_preconditions` (`_generated_by`, `fsm_check_verifier_output`, `fsm_check_grandfather`).
- **Bats Coverage for advance-to-gates** — `test-aid-fsm.bats` expanded from 14 to 18 assertions covering all branches: success path, gates-fail path (state stays EXECUTE), missing CP3 outputs (cmd_transition rejects after gates pass), and aid-run-gates.sh env-var bypass behavior with and without `AID_GATES_TRIGGERED_BY_FSM=1`. New `test-helpers.bash` helpers: `seed_test_state_files`, `setup_passing_execution_yaml`, `setup_failing_execution_yaml`, `write_valid_verifier_output`.

### Changed
- **`aid-run-gates.sh` State Guard** — accepts env-var bypass `AID_GATES_TRIGGERED_BY_FSM=1` as the signal that the caller is `cmd_advance_to_gates`. Strict equality check (`=="1"`) prevents accidental bypass via truthy values. Manual two-step flow (state==GATES + run-all without env var) remains fully backward-compatible. Error message now hints at the atomic `advance-to-gates` alternative when state==EXECUTE without the env var.
- **`pipeline.md §5 GATES State`** — adds Recommended Flow (v2.18.3+) subsection documenting `aid-fsm.sh advance-to-gates`; preserves Manual Two-Step Flow subsection for debugging and crash recovery. Both flows fully documented with semantics, env-var signal, and timeline events.

### Fixed
- **`gates_no_generated_by` Precondition Fail Class** — empirical motivation for the atomic command: P020 had 8 such failures, P021 had 4 — 12 friction events across 3 EPICs from a single root cause (chicken-egg between gates runner state guard and transition's `_generated_by` check). Target post-deploy: 0 fails of this type.

## [2.18.1] — 2026-05-09

### Fixed
- **`aid-diagnostic.sh` 3 bugs** — (1) Branch hygiene now reads from `fsm-state.yaml` instead of `state.yaml` (which is the JSON steps array and has no `branch:` field); was reporting 88–100% "missing" for all projects. (2) Deploy era loop adds `post-session-b` so post-Session-B EPICs appear in the era distribution table — were previously silently dropped. (3) `collect_precondition_fail_reasons` → `collect_fsm_fail_reasons` extends jq filter to capture `fsm_increment_fail` and `fsm_done_advance_fail` in addition to `fsm_precondition_fail`; was missing 52% of all FSM fail events (the dominant category: `verify_no_*` format-discovery failures).

## [2.18.0] — 2026-05-08

### Added
- **CP2 Per-Step Verifier Pre-Filter** — `aid-prefilter.sh` classifies each step's git diff as `SKIP` (docs/config/test only, exit 0), `RUN` (code changed, exit 10), or `FAIL` (hardcoded secret/credential detected, exit 20). `cmd_increment_step` reads the classifier verdict and refuses to advance past a FAIL classification; SKIP bypasses CP2 verifier dispatch entirely. `pre-filter-rules.yaml` holds the rule set (docs patterns, secret patterns, code extensions). Closes the CP2 dead-weight problem where verifier was dispatched on pure-docs commits, burning tokens with no signal.
- **CP3 Integration Review Enforcement** — `EXECUTE→GATES` precondition now requires both `verifier-output-cp3-code-review.md` and `verifier-output-cp3-security.md` to exist in the evidence dir. Previously the transition was gated only on `current_step >= total_steps`. Missing CP3 outputs produce a specific precondition failure message listing which files are absent.
- **`fsm_handle_force_override` Unified Dispatcher** — replaces 4 inline `--force` bypass blocks with a single `fsm_handle_force_override from to reason state_file timeline_file` function. Validates `--reason` length ≥ 20 chars (short reasons rejected with exit 1 before any state mutation), emits `fsm_force_override` timeline event, writes to `aid-audit-log.sh` audit trail. Consistency: all force paths now go through identical logging — no more "force but no timeline event" edge cases.
- **`aid-audit-log.sh`** — standalone append-only audit log writer (`aid-audit-log.sh append <evidence_dir> <event_type> <json_payload>`). Writes to `evidence/{epic}/{run}/audit-log.jsonl`. Used by `fsm_handle_force_override` and available for future audit-requiring commands.
- **Verifier Nuanced Deprivation Context** — `agents/verifier.md` updated with classification-aware dispatch: verifier receives pre-filter classification + the specific diff that triggered RUN so it can focus on the actual change rather than the full step output. Adds step-level `## Memory Used` / `## Memory Written` enforcement to verifier output schema.
- **Compliance `verifier_outputs` Object Schema** — `compliance.json` now records per-step CP2 outcomes as an object (`{step_N: {classification, verdict, ts}}`). `evaluate_compliance_checks` validates presence and structure. `write_compliance_json` populates the field from step-verify evidence.
- **Compliance `deploy_era` Three-Tier Field** — `compliance.json` carries `deploy_era: pre-session-a | post-session-a | post-session-b` based on `DEPLOY_DATE` marker comparison. Enables longitudinal trend filtering: `--era post-session-b` sees only post-Session-B EPICs, `--era latest` auto-resolves to newest era present in evidence tree.
- **`aid-compliance-report.sh --era` + `--compare`** — `--era <name>` filters aggregated report to one deploy era; `--era latest` auto-resolves. `--compare ERA1,ERA2` produces side-by-side dimension table (pass/fail/null per era) for Session A → B delta analysis without Excel.
- **`aid-compliance-report.sh --reflect` `force_override` Extension** — `--reflect` pattern detection now includes `force_override` dimension: avg > 1 per EPIC → `🔴 SYSTEMATIC` banner. Average computed via integer arithmetic (`avg_x100 > 100`) to avoid floating-point dependency. Feeds the Session A → B "what holes remain" PM gate.
- **`aid-epic-summary.sh` Auto-Generated EPIC Summary (IMP-090 fold-in)** — `done-advance` hook calls `aid-epic-summary.sh generate <evidence_dir>` after `write_compliance_json`. Produces `<evidence_dir>/epic-summary.md` with 5 sections: ✅ Co bylo dodáno (git log since base_commit), ⚠️ Varování a přeskočené kroky (timeline events: branch mismatch, unusual branch, force override, repeated precondition fail, increment-step churn), ❌ Co se nestihlo (audit/curator blocking/L-effort findings), 📋 Co dělat dál PM akce (escalations, force override follow-up, L-effort proposals), 🔍 Honest signal trust level (HIGH/MEDIUM/LOW from compliance.json + branch heuristics). Best-effort: each section individually guarded with `|| true`; generation failure logs a warning and never blocks release flow. IMP-089 forward-compat: reads `branch_convention:` from `.aid-o/config/project.yaml` if present for feature-branch false-alarm suppression.
- **Plan-Writing Gate #18** — `plan-writing.md` Completeness Gate adds check #18: plans must not contain forbidden phrases that assert completeness without evidence ("already handles", "no changes needed", "existing implementation covers"). Accompanies Gate #17 (codebase grounding) from v2.17.0.
- **bats Suite Expanded to 33 Assertions** — 5 files: `test-aid-fsm.bats` (14, +5 CP2/force assertions), `test-aid-prefilter.bats` (6, NEW — SKIP/RUN/FAIL exit codes + output format), `test-aid-compliance.bats` (4, NEW — --era/--compare/--reflect triple-condition), `test-aid-epic-summary.bats` (2, NEW — 5-section headers + force_override timeline propagation), `test-aid-run-gates.bats` (7, unchanged from v2.16.0).

### Changed
- **pipeline.md §CP2 and §CP3** — full rewrite of both subsections to document v2.18.0 enforced protocol: pre-filter classifier, verifier dispatch conditions, CP2 evidence file naming (`verifier-output-step-N.md`), CP3 mandatory dual-file output schema, fix-loop (gate-fixer → verifier, max 2 iterations).
- **pipeline.md §force_override policy** — new subsection documenting `fsm_handle_force_override` contract: required fields, minimum reason length, audit trail, PM-only authorization, forbidden patterns.
- **pipeline.md Epic Summary** — new subsection documenting IMP-090 5-section schema, per-section data sources, trust level heuristics table, IMP-089 forward-compat note.
- **`aid-fsm.sh plan_json_hash` pipefail guard** — `grep '^plan_json_hash:'` with `set -eo pipefail` caused silent exit when field absent from `state.yaml`. Wrapped with `|| true` guard. Exposed by CP2 SKIP-classification test (step-verify without hash field).

### Fixed
- **`aid-stage-log.sh` JSON array/object prefix corruption** — `log_event` escaped payload before writing to `timeline.jsonl`; payloads starting with `[` or `{` (JSON arrays/objects) were double-escaped on the `data:` field. Added prefix detection: if payload starts with `[` or `{`, write `data: <payload>` verbatim; otherwise apply existing escape. Discovered during CP3 verifier-output path testing.

## [2.17.0] — 2026-05-06

### Added
- **CP1 Codebase Grounding Rule** — `plan-writing.md` Completeness Gate gains check #17 (16 → 17). Plans must verify every named external resource (functions, helpers, file paths, ports, services, commands, env vars) against the real codebase or running infra. Hand-wave like "presumably exists in some lib" or "should be available" is a hard fail. Addresses systematic CP1 blind spot identified in P032 retrospective: 5 PM-authorized resolutions (C1–C5 in P032) were all of this kind — reviewer cannot detect *absence* of helpers/files the plan presumes exist.
- **Verifier Codebase Grounding Pass** — `/aid-plan` Step 9 (CP1 review) verifier dispatch now MUST extract a flat list from the plan of every named function, helper, file path, port, service, command, and env var, and verify each against the real codebase / running infra (`grep`, `ls`, `docker ps`, `command -v`). Each item gets VERIFIED (with location) or ABSENT (mapped to a Create step). Plans with ABSENT items not mapped to Create steps → REVISE_REQUIRED.
- **`aid-compliance-report.sh --reflect`** — lightweight `/aid-reflect` (per AID-013). Per-dimension breakdown (pass / fail / null counts + 10-cell text bar chart) with pattern detection: 0 fails → ✅ green, 1 fail → ⚠️ INVESTIGATE (could be one-off), ≥ 2 fails → 🔴 SYSTEMATIC (hole in Session A enforcement). Recommended-next-action section addresses PM retrospective from P032: aggregate ≥ 80 % can hide a single dimension failing systematically; per-dimension trend is the actionable signal before Session B brainstorm.

## [2.16.1] — 2026-05-06

### Fixed
- **`aid-compliance-backfill.sh` aborts on legacy v1 evidence** — `set -euo pipefail` caused the backfill to abort on the first vulcan/sousto evidence dir whose `state.yaml` lacked a `branch:` field (`grep` returns 1 → pipefail propagates). Wrapped the `grep | awk` extraction (and the `jq | sort | head` pipeline in `backfill_state_created_at`) in `|| true`. Discovered during the v2.16.0 post-merge deploy run.
- **`aid-compliance-backfill.sh` corrupts legacy v1 JSON state files** — some pre-v2 evidence dirs store `state.yaml` as a JSON array of step objects (legacy `plan_progress.json` format). The backfill appended `created_at: <ts>` directly, breaking JSON validity (the line landed on the same line as the closing `]` because the file lacked a trailing newline). Added file-format detection: if the first non-blank char is `[` or `{`, log a warning and skip stamping. Plus a defensive `printf '\n'` guard before any append on YAML files. Live tree was repaired with `sed` post-incident; no data loss.

## [2.16.0] — 2026-05-05

### Added
- **Branch Enforcement in PRE-FLIGHT** — `aid-fsm.sh init` automatically creates `task/{epic_id}/main` from main/master/develop, detects mismatch with copy-paste fix, respects worktree mode. Closes AID-001 (65% of pre-Session-A state.yaml claimed `branch: main` with no actual task branch, breaking done-advance audit trail).
- **Real Gates Execution Provenance** — `aid-run-gates.sh` rewritten with yq parsing, emits `gate_runner_start` / `gate_runner_complete` timeline events and writes `_generated_by` / `_generated_at` / `_command_log` provenance fields into `gates_report.json`. EXECUTE→GATES precondition mechanically rejects hand-written reports.
- **Lazy execution.yaml Creation** — `aid-init` (and `aid-fsm.sh init` auto-recovery) generates per-project `execution.yaml` from auto-detected stacks (Python, TypeScript, Go, Rust, bash) with `# DEPENDENCY` hint comments per gate command. Closes AID-006 (71% of projects had no execution.yaml).
- **Compliance Telemetry** — `done-advance` writes per-EPIC `compliance.json` with 6-dimension schema (3 measured for Session A, 3 `null` for Sessions B/C). Standalone `aid-compliance-backfill.sh` for one-shot pre-deploy backfill (also stamps mid-FSM `state.yaml.created_at` per CP1 M2). Aggregator `aid-compliance-report.sh` produces pre vs post comparison with `--since` and `--era` filters.
- **svc-mcp-tg-bot MCP Server** — new Docker service in `services/mcp-tg-bot/` (FastMCP, stdio + HTTP transport on port 8817 — see Removed section for the legacy MCP that previously held this port). `send_message` tool with HTML parse_mode default. Token shared via `/opt/eco/services/.env`. Includes `docker-compose.snippet.yml` for PM to integrate into `/opt/eco/services/docker-compose.yml`.
- **FSM Repeated-Fail Telegram Alert** — `aid-fsm.sh` emits `fsm_precondition_repeated_fail` event and best-effort `try_telegram_alert()` HTTP POST to localhost:8817 when same precondition fails ≥ 3 times on the same EPIC.
- **Parametrized Diagnostic Script** — `aid-diagnostic.sh` reusable forensic analyzer (refactored from Krok 0 logic, supports `--evidence-root`, `--output md|json`, `--limit`).
- **bats Unit Test Suite** — 16 assertions across `test-aid-fsm.bats` (9), `test-aid-run-gates.bats` (3), `test-aid-init.bats` (4) covering all new FSM preconditions, gate runner provenance, and stack detection. Runs via `bats plugins/aid-orchestrator/scripts/tests/bats/`.
- **Dependency Pre-flight Script** — `aid-check-deps.sh` verifies `bash`, `git`, `jq`, `yq` (mikefarah variant only), plus optional `bats`, `direnv`, `docker`, `curl`. cmd_init now has fail-fast guard for `git` + `jq`.
- **README Requirements Section** — explicit dependency table in plugin README listing required runtime, optional dev, and optional Telegram-alerts tools with install commands per OS.
- **Worktree Development Guide** — plugin README section + committed `.envrc` with `AID_PLUGIN_PATH=$(pwd)/plugins/aid-orchestrator` and `PATH_add` for direnv-driven worktree workflows.
- **DEPLOY_DATE Marker File** — `plugins/aid-orchestrator/DEPLOY_DATE` (ISO 8601 UTC) consumed by `fsm_check_grandfather()` as the pre/post-Session-A threshold. Fallback chain: `AID_DEPLOY_DATE` env → `${AID_PLUGIN_PATH}/DEPLOY_DATE` → `${SCRIPT_DIR}/../DEPLOY_DATE`.

### Changed
- **pipeline.md** — three subsection rewrites: PRE-FLIGHT branch-enforcement catalog (5 HEAD states + 2 timeline events), GATES EXECUTE→GATES precondition with `_generated_by` requirement and grandfather caveat, DONE phase Compliance Telemetry section with 6-dimension table and null semantics caveat.
- **state.yaml schema** — adds `created_at` field (ISO 8601 UTC) used by grandfather logic for backward-compat with pre-deploy EPICs.
- **lib/aid-stage-log.sh** — new `log_info` / `log_warn` / `log_error` helpers with `[INFO]/[WARN]/[ERROR]` severity prefix on stderr (greppable, exported alongside `log_event`).
- **fsm_precondition_fail timeline event** — now carries `reason` field (set by individual precondition cases via `_PRECONDITION_FAIL_REASON`) so `fsm_count_recent_fails` can group repeated failures by failure type.
- **aid-fsm.sh::cmd_init** — overrides caller's `branch` arg ($5) with actual `git rev-parse --abbrev-ref HEAD` after PRE-FLIGHT enforcement so `state.yaml.branch` reflects post-enforcement reality (PM-authorized resolution C3).

### Fixed
- **Branch hygiene gap** — closes the 65% of pre-Session-A `state.yaml` files claiming `branch: main` with no actual task branch. New auto-checkout closes the loop with `done-advance` release sub-phase `git merge`.
- **Fake gates reports** — closes the 0% gate-runner execution evidence in 93 analyzed timelines. Provenance fields make hand-written reports mechanically detectable.
- **Missing execution.yaml** — closes the 5/7 (71%) projects lacking gate config, which forced agents into ad-hoc gate names per EPIC with no cross-project consistency.
- **Mid-FSM EPIC unblock (CP1 M2)** — backfill stamps `created_at:` into existing `state.yaml` from earliest timeline event ts, preventing the ~14 mid-FSM EPICs identified in diagnostic-findings from becoming unresumable post-deploy.
- **aid-run-gates.sh CLI parser** — fixed `${4:-default}` swallowing `--state-file` flag when caller skipped the optional 4th positional, which silently broke `gate_runner_start`/`gate_runner_complete` events for FSM-driven invocations. Regression test added to `test-run-gates.sh`.
- **Test suite git-context invariant** — `test-fsm.sh` and `test-integration-phase1.sh` setup() now `git init` their mktemp dirs so PRE-FLIGHT branch enforcement (new in this version) finds a working tree. Existing tests preserved without behavioral change.

### Removed
- **Legacy `svc-mcp-telegram` MCP (port 8817 takeover)** — the previous general-purpose Telegram MCP at localhost:8817 is decommissioned and replaced by `svc-mcp-tg-bot` on the same port. The old MCP exposed 9 tools (send_message, edit_message, search_dialogs, get_draft, set_draft, get_messages, media_download, message_from_link, delete_message) for general Telegram interaction; the new MCP exposes 1 tool (send_message) focused on AID-internal alerting. PM verified zero call sites in repo before removal (only permissions.yaml whitelist + docs entries referenced it). `defaults/policies/permissions.yaml` updated accordingly: 9 `mcp__shared-telegram__*` whitelist entries collapsed into 1 `mcp__svc-mcp-tg-bot__send_message` entry.

## [2.15.0] — 2026-03-25

### Added
- **Mechanically Enforced FSM** — `aid-fsm.sh transition` now verifies preconditions before allowing state changes: READY→EXECUTE requires `plan.json`, EXECUTE→GATES requires all steps complete, GATES→DONE requires `gates_report.json` with `overall: pass`, ESCALATION exits require `escalation_decision` set
- **`verify-state` Command** — new `aid-fsm.sh verify-state` returns current state + allowed transitions as JSON for LLM orientation
- **`set-field` Command** — new `aid-fsm.sh set-field` for structured state mutations (escalation decisions, custom fields)
- **FSM Audit Trail** — all `aid-fsm.sh` operations (transitions, precondition failures, force overrides) logged to `timeline.jsonl` via `aid-stage-log.sh`
- **`--force` Escape Hatch** — `aid-fsm.sh transition --force` bypasses preconditions with PM approval, logged as `fsm_force_override`
- **Gates State Check** — `aid-run-gates.sh --state-file` refuses to run unless FSM state is GATES
- **Gates Report Persistence** — `aid-run-gates.sh --report-file` auto-writes `gates_report.json` (required by GATES→DONE precondition)
- **Mechanical Enforcement Protocol** — new section in `aid-run.md` with 8 non-negotiable rules for FSM compliance
- **DONE Sub-Phases** — `done_phase: review → release` within DONE state, managed by `aid-fsm.sh done-advance` with evidence-based preconditions (curator-report, audit-report, pm_decision=merge)
- **Reserved Field Protection** — `set-field` rejects writes to `state` and `done_phase` (must use dedicated `transition`/`done-advance` commands)
- **Release Script FSM Guard** — `aid-release.sh` refuses release when `state.yaml` exists with `done_phase != release` (Layer 2 defense)
- **Git Pre-Commit Hook** — FSM guard on `task/*` and `epic/*` branches blocks commits in DONE/review and READY states (Layer 3 defense)
- **Hook Auto-Install** — `/aid-init` installs/upgrades pre-commit hook with marker-based append (coexists with existing hooks)
- **Step Verification Enforcement** — `increment-step` refuses to advance without `step-{N}-verify.md` evidence file (AC checklist + visual check)
- **Agent Dispatch Protocol** — 6 non-negotiable rules in pipeline.md: verbatim plan content, visual assets, post-step AC verification, visual verification for UI, resume-on-failure, visual context dispatch
- **Visual Companion** — browser-based HTML prototype viewer for brainstorming (opt-in, Node.js server adapted from Superpowers). Generates interactive mockups during design sections, saves approved HTML as 4th input type for visual assets pipeline. Per-question visual/text decision taxonomy.
- **Visual Assets Pipeline** — 4 input types (GitHub repo, AI Studio URL, PNG, Visual Companion) → unified `visual-spec.yaml` output; `visual_refs` field in plan.schema.json; visual dispatch protocol in pipeline.md §4; Visual Anchoring requirement in frontend role card; screenshot comparison protocol (MATCH/PARTIAL/MISMATCH); forbidden text-only UI descriptions in plan-writing.md
- **Plan-Level DONE Gate** — `aid-fsm.sh init` blocks cross-plan run if previous plan has unreviewed C+A findings (`ca-review-complete` marker required); enforces "dispatch per EPIC, validate per Plan" model
- **Step-Verify Content Validation** — `increment-step` now requires at least one `- [x]` AC checklist item and one commit hash (7+ hex chars); prevents minimal "Result: PASS" without substance
- **Plan.json Init Warning** — `aid-fsm.sh init` warns when plan.json steps lack `objective` field
- **Per-Project Agent Memory (Qdrant)** — 10-category deep codebase scan (architecture, API, data, UI, config, testing, conventions, security, DevOps/CI-CD, cross-cutting concerns); `memory-mcp.md` skill with entry schema, quality rules (≥20 word summary, real code examples, 5 rejection criteria), store/find protocol, supersede pattern; pipeline §4 memory READ (2-tier context injection ~1500 tokens); pipeline §7 Scanner dispatch at plan boundary; `memory_writes` mandatory in agent output; `## Memory Used` + `## Memory Written` enforced in step-verify by `increment-step`; Auditor Memory Health category (stale detection, conflict detection, coverage check); kondice flow (auditor flags → scanner verifies)

### Changed
- **FSM Valid States** — added ERROR to `VALID_STATES`; added `→ERROR` transitions from READY, EXECUTE, GATES, ESCALATION
- **Escalation Cleanup** — `escalation_decision` field auto-cleared when leaving ESCALATION state
- **Pipeline §3-§6** — each section now documents which FSM preconditions enforce correct behavior

### Fixed
- **Dead Cross-References** — replaced 20+ references to deleted v1 files (dispatch-protocol.md, epic-orchestration.md) with v2 equivalents across 11 files
- **v1 State Names** — replaced v1 FSM states (PM_APPROVAL, CURATOR_RESOLVE, PHASE_CHECK, IDLE) in pipeline.md; added v1 legacy headers to improvement-proposals.md and analytics.md
- **v1 Directory Paths** — updated CLAUDE.md workspace structure from v1 (01-plans/, 04-engine/) to v2 (plans/, work/)
- **Pre-Commit Hook** — removed dead case statement (non-functional code from refactoring)

## [2.6.0] — 2026-03-14

### Added
- **Standards Enforcement System** — two standard sets (`general.yaml` with 26 language-agnostic rules, `vulcan.yaml` with 22 ecosystem-specific rules + 4 severity overrides) selectable during `/aid-init`
- **Standards Gate** — new `standards_compliance` gate in `execution.yaml`, 100% deterministic (pattern/structural/file-exists rules only), custom/LLM rules are auditor-only advisory
- **Standards Audit Category** — new conditional category I) in auditor with full-codebase scan, severity-based scoring (cap 5 violations/rule), 15% weight when active
- **Standards Curator Integration** — hotspot detection (3+ violations of same rule = systemic), `source_type: standards` proposals with auto-approve for S-effort fixes
- **Standards Dispatch Context** — agents receive filtered standards in prompt (gate-blocking first, filtered by language), omitted when `standards.active == 'none'`

### Changed
- **Auditor Category Count** — 8→9 categories (5 mandatory + 4 conditional), weight redistribution when standards active (Code 30→25%, Security 30→27%, Docs 25→23%)
- **Agent Execution Summary** — includes `Standards violations noted: {count}` for trend tracking
- **Init Flow** — standards profile selection (general/vulcan/none) with `project.yaml → standards` config block

## [2.5.0] — 2026-03-13

### Added
- **Plugin Path Discovery** — `/aid-init` discovers and caches plugin installation path in `config/plugin.yaml`; Script Execution Protocol in `agent-core.md` teaches all agents how to resolve `scripts/X.sh` references
- **Brainstorming Question Format Template** — concrete format with Effort/Risk per option, recommendation with "Why not" reasoning, and webhook delivery example
- **Brainstorming Handoff Summary** — plan-writing presents decision summary + 6 options including `/aid-run --auto` with `autonomous_mode` prerequisite warning
- **Superpowers Conflict Resolution** — CLAUDE.md template includes conflict table (brainstorming, writing-plans, executing-plans → AID equivalents); 3 `skill_conflicts` entries in `orchestration.yaml`
- **Documentation Gate Enforcement** — path-pattern correlation: `docs_updated` gate fails only when API-path files changed without doc updates; auditor escalates missing API docs to high severity

### Changed
- **PRE-FLIGHT Plugin Verification** — `/aid-run` and `/aid-do` verify `plugin_path` on startup with cache invalidation fallback
- **Dispatch Context** — `agent-protocol.md` input format includes `plugin_path` for dispatched agents
- **Brainstorming Rule 8** — now explicitly requires effort estimate (S/M/L) and risk (L/M/H) per option

### Fixed
- **`/aid-plan-epic` stale references** — replaced with `/aid-plan --epic` across brainstorming, plan-writing, pipeline, and planner skills (command merged in v2.0)
- **`aid-plan.md` step count** — Steps 1-7 showed `/8` denominator instead of `/9` after CP1 review was added as Step 9

## [2.4.0] — 2026-03-12

### Added
- **PM Merge Decision Gate** — DONE state presents combined curator+auditor summary, PM explicitly chooses MERGE/FIX/ABORT before code reaches main
- **Parallel Curator+Auditor** — Both dispatch simultaneously in DONE state, reducing post-completion wait time
- **Auditor Auto-Fix** — S and M effort recommendations trigger gate-fixer dispatch pre-merge via new `recommended_fixes` output field
- **70/30 Design Principle** — Documented deterministic-first philosophy in pipeline §1: 70% bash, 30% LLM
- **Review Pre-Filter** — Bash regex checks (secrets, SQL injection, eval, debug) run before CP2/CP3/CP6 verifier dispatch, skipping LLM when unnecessary
- **Per-Escalation Templates (E1-E8)** — Each trigger shows specific context, findings, affected files, and available commands

### Changed
- **DONE State Flow** — Merge moved from step 3 to step 13 (after PM approval); prevents premature merge before review
- **Curator Auto-Evaluation** — Tier 2 default: M-effort proposals now auto-approved (was: deferred to PM)
- **PM Interaction Points** — Enhanced output at READY (gate details), CP1 (severity summary + 3 options), CP6 (evidence paths), scope warnings (actionable commands), and ESCALATION (per-type context blocks)
- **Auditor Dispatch Timing** — Now dispatched pre-merge in parallel with Curator (was: post-merge sequential)

## [2.3.0] — 2026-03-12

### Added
- **Review Checkpoints (CP1-CP6)** — Automatic verifier dispatch at 6 pipeline milestones: post-brainstorm plan review, per-step code review, pre-GATES integration review, curator proposal validation, auditor critical-finding gate, and post-/aid-do quick review
- **Fix Loop Protocol** — Verifier findings with Critical/High severity trigger gate-fixer dispatch + re-verification (max 2 iterations), replacing reactive gate-failure-only fixes
- **Critical Finding Gate (CP5)** — Auditor critical findings now block DONE state, triggering ESCALATION instead of proceeding to queue
- **Review Checkpoint Configuration** — New `review-checkpoints.yaml` policy file with per-checkpoint toggles, fix-loop settings, and trivial-skip threshold
- **Escalation triggers E7, E8** — Verifier review failure after fix loop; auditor critical security finding
- **Pipeline §13** — New Review Checkpoint Protocol section as authoritative reference

### Changed
- **Verifier agent** — Expanded from on-demand to automatic dispatch with fix-loop integration and checkpoint-specific context assembly
- **Gate-fixer agent** — Now accepts verifier review findings as input (source: `verifier_review`), not just gate failures
- **Auditor agent** — Critical findings produce `blocking_findings` flag that blocks DONE transition
- **Pipeline §4-§8** — Updated with review checkpoint dispatch points at EXECUTE, GATES, DONE, and FAST MODE

### Fixed
- **Broken cross-references** — Fixed 5 stale v2 migration references: auditor.md, gate-fixer.md, curator.md, planner.md pointed to non-existent `epic-orchestration.md`/`retry-engine.md`; pipeline.md referenced non-existent `dispatch-config.yaml`

## [2.2.0] — 2026-03-11

### Added
- **Context Persistence (Interim Document)** — `/aid-plan` now creates `.aid-o/work/interim-P{NNN}.md` at session start, updated after each step with full conversation detail; survives context window overflow and session interruptions; auto-deleted on plan completion
- **Concurrent brainstorm detection** — checks for existing interim docs before starting new brainstorm, offers resume or fresh start
- **ID Allocation Procedure** — documented read-increment-write protocol for counter.yaml in run-management ID System section

### Fixed
- **Dead `epic-orchestration.md` references** — updated brainstorming.md, plan-writing.md, and run-management.md to reference run-management ID System instead
- **Abort text accuracy** — "no files created" corrected to "no plan written, interim doc preserved"
- **plan-writing.md missing interim cleanup** — added MUST rule 15 to delete interim doc after successful plan write

## [2.1.1] — 2026-03-10

### Fixed
- **`.gitignore` missing from `/aid-init`** — Init now creates `.gitignore` appended to project root, ignoring runtime artifacts (evidence, quick logs, timeline.jsonl, queue.yaml) while keeping design artifacts versioned
- **Defaults `.gitignore` outdated** — Updated from v1 paths (`.aid-o/04-engine/`) to v2 structure

## [2.1.0] — 2026-03-10

### Changed
- **Brainstorming skill refactored** — 34% smaller (415→272 lines) with 8 new capabilities: scope decomposition, MoSCoW prioritization, risk assessment protocol, prior-plan lookup, pre-decided solution handling, context-loss recovery, workflow/AI questioning hint, Docker Compose recommendation
- **Design section templates extracted** — Moved to `defaults/templates/design-sections.md` as standalone reference, reducing brainstorming skill size while preserving all templates

### Removed
- **Obsolete planning docs** — Removed CRITICAL-ASSESSMENT.md and REDESIGN-PLAN-v2.md (completed, no longer relevant)

## [2.0.0] — 2026-03-03

### Breaking Changes
- **11-state LLM FSM → 6-state bash FSM** — States reduced from IDLE/PLANNING/PLAN_REVIEW/EXECUTING/PHASE_CHECK/NEXT_PHASE/GATES/GATE_RETRY/ESCALATION/CURATOR_RESOLVE/PM_APPROVAL/DONE to READY/EXECUTE/GATES/ESCALATION/DONE/ERROR. State transitions enforced by `aid-fsm.sh`, not LLM instructions.
- **27 skills → 8 skills** — Consolidated from 27 cross-referencing skills to 8 focused skills (agent-protocol, pipeline, planner, brainstorming, quality-gates, run-management, memory, role-cards). Removed: epic-orchestration, dispatch-protocol, gates-engine, retry-engine, first-aid-controller, auto-escalation, auto-done-state, parallel-dispatch, cost-optimization, epic-queue, slack-mcp, workflow-intelligence, and 15 others.
- **18 agents → 7 agents** — Consolidated from 18 role-based agents to 7 controller agents (implementer, verifier, gate-fixer, curator, auditor, project-scanner, run-validator). Removed: architect, backend, frontend, domain, qa, security, observability, docs-writer, release, code-reviewer, docs-reviewer, lessons-extractor, quality-gates-runner.
- **17 commands → 8 commands** — New unified commands: `/aid-do`, `/aid-plan`, `/aid-run`, `/aid-status`, `/aid-help`, `/aid-init`, `/aid-audit`, `/aid-stop`. Removed: `/aid-brainstorm`, `/aid-plan-epic`, `/aid-run-epic`, `/aid-first-aid`, `/aid-setup`, `/aid-epic-queue`, `/aid-epic-status`, `/aid-research`, and 9 others.
- **Directory structure** — `.aid-o/04-engine/` → `.aid-o/work/`, `.aid-o/02-epics/` → `.aid-o/tasks/`, `.aid-o/03-config/` → `.aid-o/config/`. Init creates 10 files (down from 40+).
- **10 policy YAMLs → 3** — `execution.yaml` (gates + dispatch), `project.yaml` (stack + preferences), `permissions.yaml` (agent permissions). Removed: decision-policies.yaml, dispatch-strategy.yaml, gates.yaml, memory-config.yaml, slack-config.yaml, and 5 others.

### Added
- **Fast Mode (`/aid-do`)** — < 2 min overhead for tasks < 2h. Creates Q-NNN.md quick log, skips full EPIC pipeline. Automatic scope detection.
- **Bash FSM (`aid-fsm.sh`)** — Deterministic 6-state finite state machine. States: READY → EXECUTE → GATES → DONE (happy path), with ESCALATION and ERROR branches. All transitions validated in bash, not LLM.
- **Bash gate runner (`aid-run-gates.sh`)** — Deterministic quality gate execution with JSON output, timeout handling, retry logic. Replaces LLM-manual gate evaluation.
- **Pipeline automation scripts** — `aid-auto-pipeline.sh` (orchestrator), `aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`. All deterministic operations moved from LLM to bash.
- **Stage logging (`aid-stage-log.sh`)** — Structured timeline.jsonl event logging with standardized format across all pipeline operations.
- **Token estimator (`aid-token-count.sh`)** — Character-based token estimation for prose/code/mixed content types.
- **`@aid/contract` package** — Shared TypeScript types for all `.aid-o/` data formats (AidFsmState, AidState, AidGatesReport, AidTimeline, etc.).
- **Progressive help (`/aid-help`)** — 4-level disclosure: Level 0 (cheat sheet), Level 1 (command detail), Level 2 (architecture), Level 3 (troubleshooting).
- **Scope check gate** — `scripts/gates/scope-check.sh` verifies implementation stays within EPIC-defined file scope.
- **173 tests across 13 suites** — Up from 88 tests / 6 suites in v1.7.0. Full coverage of FSM, gates, pipeline, stage logging, token counting, scope checking.

### Changed
- **~87% token reduction** — Plugin prompt tokens reduced from ~400K to ~50K by consolidating skills/agents/commands and moving deterministic logic to bash scripts.
- **`/aid-plan` merges 3 old commands** — Replaces `/aid-brainstorm` + `/aid-write-plan` + `/aid-plan-epic` into single progressive workflow.
- **`/aid-run` merges 2 old commands** — Replaces `/aid-run-epic` + `/aid-first-aid` with unified command supporting `--auto` flag.
- **`/aid-status` merges 2 old commands** — Replaces `/aid-epic-status` + `/aid-epic-queue` with combined view.
- **`/aid-init` merges `/aid-setup`** — Single idempotent init command creating 10-file `.aid-o/` structure with stack auto-detection.
- **Role cards consolidated** — All agent role definitions in single `role-cards.md` (8 roles + 4 focus cards) instead of 18 separate agent files.
- **Pipeline skill consolidated** — Single `pipeline.md` replaces 14 old orchestration skills, documenting all 6 FSM states.
- **Evidence paths** — `stage_log.jsonl` → `timeline.jsonl`, `plan_progress.json` → `state.yaml`.
- **aid-server paths** — Updated all Express routes and WebSocket handlers for v2 `.aid-o/` structure.

## [1.7.0] — 2026-02-28

### Added
- **Path Traversal Guards** — defense-in-depth (regex + resolve+startsWith) path validation on pipeline theater, evidence, and decision routes preventing CWE-22 filesystem traversal via `epicId`/`runId` parameters
- **GUI CORS Middleware** — `cors()` middleware on the aid-gui Express server with `AID_GUI_CORS_ORIGINS` env var support, defaulting to localhost:5173 and localhost:3000
- **Agent Name Frontmatter** — all 18 agent files now have `name:` field in YAML frontmatter matching the filename stem, enabling plugin validation
- **Master Test Runner** — `run-all-tests.sh` discovers and executes all test suites with unified pass/fail reporting (88 tests across 6 suites)
- **Curator Dispatch Regression Tests** — Suite F (5 tests) verifying unconditional Curator dispatch and state-entry logging in gate-evaluation.md and first-aid-controller.md
- **Phase Marker Documentation** — `plan-writing.md` Phase Markers subsection with exact format, rules, regex, and "do NOT use" examples for LLM-generated plans
- **PARALLEL_EXECUTING Sub-State** — `epic-state-machine.md` documents the FIRST AID parallel execution sub-state with activation criteria and safety limits
- **AI Companion Project Context** — system prompt auto-built from CLAUDE.md, package.json, pipeline state, EPIC queue, plans, decisions, ideas backlog, and project structure on every message
- **AI Companion Tool Use** — 7 tools (readFile, listDirectory, searchContent, readYaml, readEpic, readPlan, getPipelineState) giving the companion full codebase access with sandboxed paths and 8-step tool call limit
- **Voice Dictation Recording Bar** — waveform visualization via AudioContext AnalyserNode, elapsed timer, live interim text display (Web Speech API), and one-click stop-and-send flow
- **Whisper Auto-Detection** — background probe on mount detects Whisper availability; uses Web Speech API as primary (Czech `cs-CZ` support) with Whisper upgrade when OPENAI_API_KEY is set
- **FIRST AID Wrapper State Mapping** — FIRST_AID_INIT, QUEUE_PROCESSING, QUEUE_ADVANCE, FIRST_AID_COMPLETE mapped to medical labels (Triage, Operating, Next Patient, All Clear) with FSM colors and active state detection
- **Satellite Card Alternation** — Ward, Lab, Escalations, Vitals cards alternate between current and total values every 4 seconds with AnimatePresence transitions

### Changed
- **CORS Wildcard Handling** — `AID_CORS_ORIGINS=*` now correctly enables wildcard CORS instead of creating a single-element array `['*']`
- **Default Server Binding** — both aid-server and aid-gui default to `127.0.0.1` (loopback only) instead of `0.0.0.0`, preventing unintentional network exposure; Docker containers retain `0.0.0.0` via explicit env var
- **GUI README Replaced** — removed Gemini/AI Studio boilerplate, replaced with accurate AID Dashboard GUI documentation including local setup and aid-server dependency
- **Root README Version** — updated from v1.5.0 to v1.6.0
- **Brainstorming Step Count Standardized** — all documentation (README, Docusaurus, aid-help) now references 8-step brainstorming matching the actual skill lifecycle
- **aid-run-epic Prerequisites** — removed false auto-generation claim; `plan.json` must pre-exist via `/aid-plan-epic`
- **Zombie Backlog Cleanup** — moved 7 already-fixed entries (IMP-010/035/049/050/057/059/067) from Active to Implemented, correcting count from 62 to 55
- **EPIC ID Regex Hardened** — `aid-auto-pipeline.sh` now accepts alphanumeric plan IDs with internal hyphens (e.g., `E-TEST-001-1_2`)
- **Dependency Parser Enhanced** — `aid-plan-to-epic.sh` supports range expansion (`Steps 3-7`), trailing text stripping, cross-phase dependency filtering, and deduplication
- **Scope Generation Granularity** — `aid-plan-to-epic.sh` generates file-level paths in EPIC scope when plan steps have `**Files:**` sections, improving FIRST AID parallel detection accuracy
- **EPIC Template Scope Guidance** — template includes guidance comments encouraging file-level path declarations over broad directories
- **Curator Dispatch Made Unconditional** — `gate-evaluation.md` and `first-aid-controller.md` now mandate Curator dispatch at CURATOR_RESOLVE regardless of discovered_issues
- **QUEUE_PROCESSING Auto-Mode** — `first-aid-controller.md` includes parallel dispatch checklist cross-referencing `aid-first-aid.md` sections 3.1-3.5
- **Curator Auto-Defer Threshold Raised** — auto-mode now defers only effort:L proposals to backlog; effort:S and effort:M are fixed inline, increasing autonomous fix rate
- **Command Center State Labels** — all FSM states renamed to medical/hospital theme (On Call, Diagnosis, Prescription, Infusing, Vital Signs, Second Opinion, Lab Results, Doctor's Orders, Recovery, Discharged, Code Red)
- **Satellite Cards Data Sources** — Ward shows queue running+waiting / completed+failed; Lab shows gate runs+retries / audit score; Escalations shows budget usage / total escalations; Vitals shows steps executed / total events
- **EPIC Runs Display** — shows last 5 completed (most recent first) instead of first 5
- **Voice Flow Simplified** — removed confirm step; recording stops and sends directly (one action instead of three)
- **CommandPalette Voice** — transcript sends as message directly instead of inserting into filter input
- **Companion Open Speed** — status and sessions pre-fetched on project select; palette/panel opens instantly without network delay
- **Pipeline API Extended** — `/pipeline` endpoint returns full autoModeSession with escalation budget/count and aggregate counters (epicsCompleted, epicsFailed, totalStepsExecuted, totalGateRuns, totalGateRetries, totalEscalations)

### Fixed
- **WebSocket Replay Parsing** — `dispatchReplay()` now reads raw stage log entries directly instead of expecting non-existent `.entry` wrapper, fixing Pipeline Theater replay after reconnection
- **CSS Custom Property Generation** — `.replaceAll('_', '-')` replaces all underscores in FSM state names for correct CSS variable references (was `.replace` which only fixed the first)
- **Curator Input File References** — corrected from `step_output.json` to `output.md` + `diff.patch` matching actual agent output format
- **Queue Field Name** — `scripts/README.md` corrected `queued_at` to `added_at` matching actual queue schema
- **Queue Field Name Mismatch** — server returned `data.entries` but GUI expected `data.queue`, causing queue entries, elapsed time, and EPIC runs to never display
- **Topbar Voice Integration** — replaced inline mic recording logic (~90 lines) with shared VoiceButton component using `compact` prop

## [1.6.0] — 2026-02-28

### Added
- **Pipeline Scripts** — 5 bash scripts (`aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`, `aid-auto-pipeline.sh`) for deterministic Plan→EPIC→json→run→queue conversion replacing LLM-driven operations
- **Shared Script Library** — `scripts/lib/common.sh` with 7 portable bash functions (YAML parsing, section extraction, slugify, prerequisites check, error formatting, timestamps)
- **Script Documentation** — `scripts/README.md` with full interface contracts, argument tables, exit codes, data flow diagram, and JSON manifest schema for all 5 pipeline scripts
- **EPIC Template Dependencies Section** — structured Dependencies section with Internal/External/Queue subsections replacing flat placeholder
- **Deterministic Work Detection Audit** — new audit category I) scanning commands, skills, and agents for LLM-performed template filling, structured parsing, and file manipulation that could be replaced by scripts, with false positive filters and -10 cap scoring
- **Pipeline Test Suite** — 76 tests across 6 test scripts (40 unit, 16 integration, 20 regression) with 3 fixture plan files covering single-phase, multi-phase, and cross-plan dependency scenarios

### Changed
- **aid-plan-epic Command** — rewritten from 544-line LLM-driven flow to 235-line script-orchestrated 6-step flow delegating deterministic work to `aid-auto-pipeline.sh`
- **aid-run-epic Command** — inline plan generation removed; `plan.json` must pre-exist (created via `/aid-plan-epic`) with clear error message and actionable suggestion when missing
- **Documentation Consistency Pass** — 10+ skill/command files updated to reference script-based pipeline, removing references to inline plan generation

## [1.5.0] — 2026-02-28

### Added
- **Token Estimation Protocol** — new `skills/token-estimator.md` defining character-based heuristic for dispatch token counting with cl100k_base approximation and calibration process
- **Dispatch Configuration** — new `defaults/policies/dispatch-config.yaml` with 18 role-to-model tier mappings (3 opus, 11 sonnet, 4 haiku), per-tier context defaults, and advisory budget alerts
- **Plan Schema Extension** — `model` (enum: haiku/sonnet/opus) and `context_scope` (knowledge, memory, previous_outputs) optional fields per step in `plan.schema.json`
- **Planner Model Assignment** — planner reads `dispatch-config.yaml` and populates `model` + `context_scope` per step with fallback to opus/all-context when config is absent
- **Dispatch Usage Logging** — pre-dispatch token estimation and post-dispatch `usage` object in stage_log.jsonl with model, tokens, duration, context sources, and budget alerts
- **Usage Aggregation** — DONE state aggregates all dispatch_complete entries into `usage_summary` in plan_progress.json with breakdowns by model, role, and step
- **Model Tiering in Dispatch** — `step.model` passed to Task tool with 3-level fallback chain (step.model → dispatch-config.yaml → opus default)
- **Selective Context Injection** — knowledge, memory, and previous outputs conditionally injected based on `step.context_scope` with full backward compatibility
- **Dispatch Prompt Trimming** — EPIC context reduced to one-line goal + step-level paths instead of full EPIC specification
- **Token Efficiency Audit** — new `/aid-audit efficiency` type with per-role baseline comparison and 2x alert threshold (advisory, 0% weight)

### Changed
- **Dispatch Protocol** — model parameter wired into Task tool calls, context injection is conditional, prompt uses trimmed EPIC context
- **Parallel Dispatch** — model tiering support with per-agent model resolution

## [1.4.0] — 2026-02-27

### Added
- **GUI Dashboard** — full-featured web dashboard (`aid-gui` package) with Express backend, WebSocket real-time updates, and React 19 + Zustand 5 frontend
- **Ideas-to-Execution Kanban** — drag-and-drop board tracking ideas through exploration → planned → running → done lifecycle with auto-status from linked plans/EPICs
- **AI Companion Chat** — SSE-streaming chat panel with markdown rendering, session management, voice input (Web Speech API), and contextual hint buttons
- **EPIC Lifecycle Manager** — GUI-driven EPIC listing with frontmatter parsing, run/schedule actions, queue integration, and status-sorted display
- **Evidence Vault** — full-text grep search across evidence files (200-result cap, binary detection), date-grouped collapsible sidebar, and markdown preview toggle with DOMPurify sanitization
- **Pipeline Theater SVG Timeline** — Gantt-like horizontal timeline with color-coded role bars (architect/backend/frontend/qa/docs/security), replay controls (0.5x–4x speed), EPIC/run selector, and live auto-scroll mode
- **Decision Hub Notifications** — Web Audio API sound alerts (440Hz sine, 3s debounce) and browser Notification API for background tabs, with Sidebar badge pulse animation
- **Evidence Search API** — `GET /evidence/search?q=&limit=` endpoint with case-insensitive text matching, path traversal protection, and binary file skipping
- **Pipeline Theater API** — `GET /pipeline/theater/:epicId/:runId` endpoint merging plan.json + plan_progress.json + stage_log.jsonl into combined theater data
- **Companion Backend** — session-store with JSON persistence, auto-detect LLM adapter (Claude/OpenAI/Ollama/stub), SSE streaming endpoint, voice transcription proxy
- **WebSocket Infrastructure** — topic-based pub/sub (pipeline, stage_log, decisions, queue) with heartbeat, auto-reconnect (exponential backoff), and replay on reconnect
- **Test Suite** — 1014 Vitest tests across 31 files covering server routes, parsers, WebSocket, store slices, and API client

### Changed
- **Project structure** — added `packages/aid-gui/` (frontend) and `packages/aid-server/` (backend) as monorepo packages alongside the plugin

## [1.3.1] — 2026-02-27

### Fixed
- **Curator evidence path** — `step_output.json` replaced with `output.md` so Curator can actually read agent improvement notes
- **FIRST AID skill reference** — `skills/first-aid-mode.md` corrected to `skills/first-aid-controller.md` in `/aid-help`
- **Czech preset descriptions** — translated to English in `permissions.yaml` (aspirin and steroids descriptions)
- **Stale epic-breakdown.md references** — 6 references across 5 files replaced with `epic.md` (the actual template)

## [1.3.0] — 2026-02-27

### Added
- **Queue dependency ordering** — `depends_on` field in queue schema with Kahn's algorithm cycle detection; `next()` computes READY/WAITING/BLOCKED eligibility per entry
- **INTERMEDIATE_GUARDRAIL** — 3-check auto-approval gate (all_steps_done, no_gate_failures, evidence_complete) for intermediate EPICs in FIRST AID mode
- **Queue write ownership** — CONFLICT_CHECK as Step 0 in add()/start()/complete() operations; single-writer constraint during FIRST AID via auto-mode flag file
- **Canonical EPIC ID format** — formal `E-{plan_id}-{phase}_{total}` specification with validation regex and cross-referenced documentation
- **Untrusted field list** — 10 untrusted and 6 trusted fields enumerated in dispatch-protocol with rationale for each classification
- **OVERLAP_CHECK algorithm** — concrete pseudocode for 3 cases (exact-exact, glob-exact, glob-glob) replacing vague prose in planner
- **R1 dependency classification** — DATA MODEL and API CONTRACT type definitions with 5-step determination algorithm replacing subjective criteria
- **plan_ref keyword matching** — 4-step algorithm with extract/score/stopping-rule/confidence-check replacing vague Strategy 3 description
- **Setup re-run detection** — `/aid-setup` detects existing workspace and offers 6-option section menu for selective reconfiguration
- **Release count verification** — RELEASE_CHECK_COUNTS ensures CLAUDE.md command/skill counts stay in sync during releases
- **DEFAULT_BASELINE** — threshold 50/100 applied when no prior audit report exists for PM_APPROVAL auditor trend check

### Changed
- **adapt_example()** — simplified from 7-step function (422 lines) to 3-step (83 lines): path substitution, tool reference update, validation
- **Credit exhaustion detection** — 5 hardcoded strings replaced with 6 case-insensitive regex patterns and short-circuit evaluation

### Fixed
- **Escalation snapshot** — now correctly writes to `interrupted_step_context.json` instead of inconsistent field names

### Removed
- **`--dry-run` flag** — removed from `/aid-first-aid` command; deferred to backlog as standalone feature

## [1.2.0] — 2026-02-27

### Removed
- **Permission Sandwich** — removed `skills/permission-sandwich.md` (750 lines) and `defaults/policies/permissions-auto.yaml` (164 lines); FIRST AID no longer backs up, elevates, or restores permissions — requires Steroids 💉 preset instead

### Changed
- **Permission presets** — Safe removed, Recommended renamed to Aspirin 💊, Advanced renamed to Steroids 💉; two-preset system with deny-list protection
- **FIRST AID startup** — permission sandwich steps (backup, elevate) replaced by single Steroids preset verification check
- **FIRST AID completion** — permission restore removed; /aid-stop simplified to 3 steps (mode flag, wait, save progress)

### Fixed
- **Plan archival** — QUEUE_ADVANCE now uses queue as ground truth for plan archival instead of filesystem scanning; DONE state no longer attempts archival (single source)
- **Version bump detection** — uses plan-level completion (`plan_epics_total`) instead of queue position; solo plans always bump, multi-EPIC plans bump on last EPIC
- **Release sub-phase** — DONE state now explicitly calls RELEASE_SUB_PHASE with mandatory stage_log entry; skipping is no longer possible without audit trail
- **Queue removal** — `/epic-queue remove` sets status "removed" (not "completed"); context boundary tracking distinguishes session total from actually-executed EPICs

## [1.1.0] — 2026-02-27

### Added

- **Plan-Writing Skill** — new `skills/plan-writing.md` with two modes: Mode A (post-brainstorming) and Mode B (standalone `/aid-write-plan`); includes Forbidden Phrase Detection hard gate, Traceability Verification, 16-point Completeness Gate, and Post-Write Handoff offering EPIC creation
- **`/aid-write-plan` Command** — standalone plan writing command that delegates to the plan-writing skill; accepts topic argument or interactive input
- **Brainstorming Critical Rules Block** — 11 critical rules at the top of `aid-brainstorm.md` with primacy effect positioning to prevent instruction drift
- **Brainstorming Step Self-Checks** — each of the 8 brainstorming steps now has a mandatory self-check checklist (2-4 items) that must pass before transitioning to the next step
- **Brainstorming Progress Tracker** — mandatory `=== Step N/8: {Name} ===` output at the start of every brainstorming step for checkpoint enforcement
- **Brainstorming Approach Hard Gate** — RULE 9 enforces minimum 2 approaches before presenting to PM; RULE 10 prevents skipping approach exploration even for "obvious" topics
- **Brainstorming Completeness Gate** — Step 8 now enumerates all PM answers from Steps 3-6 and verifies each appears in the plan document before finalizing
- **adapt_example() Implementation** — 7-step function in knowledge-acquisition.md replaces path placeholders, updates framework versions, handles Docker sections, aligns platforms, merges constraints, adjusts step count, and writes adapted EPIC
- **Knowledge Results Display** — brainstorming Step 1 now shows PM what knowledge was found ("Found N relevant docs: [names]") or "No knowledge indexed yet"
- **`/aid-help knowledge` Topic** — lists all example EPICs by category, explains search flow (Context7 → Qdrant → static), and documents indexing and research triggers
- **RESUME_SESSION safety net** — QUEUE_PROCESSING next() now filters on `status in ["queued", "running"]` with preference for running entries, so an interrupted EPIC is automatically resumed even when the RESUME_SESSION reset was skipped
- **Permission snapshot and restore** — `auto-mode-state.yaml` gains an `original_permissions_snapshot` field; RESTORE_PERMISSIONS now uses a two-tier fallback (backup file, then inline snapshot) across all three restore paths (COMPLETE, /aid-stop, crash recovery)
- **Permission grant log** — `auto-mode-state.yaml` gains a `permissions.grant_log[]` audit trail field recording each dynamic permission grant with permission, source, actor, step_ref, timestamp, and reason; PHASE_CHECK permission learning dual-writes to both `learned_permissions[]` and `grant_log[]`
- **Multi-agent parallel execution** — QUEUE_PROCESSING gains a complete parallel dispatch protocol: independence detection via EPIC scope analysis, Task agent dispatch in worktree isolation, sequential merge with shared escalation budget, failure isolation per agent, and a safety cap of 3 concurrent agents
- **Untrusted content tags in dispatch templates** — all 10 user-supplied interpolation points in `aid-run-epic.md` dispatch prompts are wrapped in `<untrusted_content>` tags with source attributes; safety preamble added to both base and re-dispatch templates to prevent prompt injection
- **Hardened deny-list entries** — `Bash(rm -fr:*)` (reversed short flags) and `Bash(dd if=/dev/urandom:*)` added to the hard-deny list in `permission-sandwich.md` and `permissions-auto.yaml` with inline rationale comments and updated Section 3.4 rationale table
- **Planner parallelism rules** — 5 named Parallel Group Assignment Rules added to `planner.md`; backend and frontend agents can now parallelize after architect+domain steps when file scopes do not overlap; includes OVERLAP_CHECK algorithm and 3 worked examples
- **Planner granularity heuristics** — HEURISTIC G1 (Layer Splitting) and G2 (Module Splitting) added to `planner.md` Section 2b with before/after examples and interaction rules; steps spanning 3+ layers or 3+ modules are automatically split
- **Audit instruction quality checks** — Section G added to `auditor.md` with 5 checks for instruction file quality (intro presence, TODO/FIXME scan, frontmatter, cross-reference accuracy, files exceeding 800 lines); weighted at 10% and conditional on `plugins/aid-orchestrator/` existing

### Changed

- **Brainstorming modular split** — 1371-line `brainstorming.md` split into core (569 lines) + two sub-skills: `brainstorming-knowledge.md` (445 lines) for knowledge acquisition and file analysis, `brainstorming-workflow.md` (443 lines) for workflow detection and Docker/MCP rules
- **Brainstorming flow simplified** — reduced from 11 steps to 8 steps; EPIC creation removed from brainstorming entirely (now handled by `/aid-plan-epic` via plan-writing handoff)
- **Plan-writing delegation** — brainstorming Step 8 now delegates to `skills/plan-writing.md` instead of writing the plan inline; plan-writing skill handles quality gates, forbidden phrase detection, and completeness verification
- **FIRST AID disclaimer** — reframed from alarmist "USE AT YOUR OWN RISK" to "Experimental Autonomous Mode"; added explicit `/aid-stop` emergency stop reference and `/aid-epic-queue` for queue review so users know how to intervene safely
- **Setup MCP advanced permissions preset** — replaced the broad `mcp__*` wildcard with 7 explicit tool patterns (`mcp__shared-github__*(*)`, etc.) matching auto-mode format; updated setup wizard comparison matrix to reflect the change
- **Epic orchestration skill split** — 2300-line `epic-orchestration.md` split into 5 modular files: slim orchestrator (138 lines), `epic-state-machine.md` (602), `dispatch-protocol.md` (498), `gate-evaluation.md` (509), and `first-aid-controller.md` (577); pure refactoring with no logic changes
- **PLAN_REVIEW template enriched** — per-step detail table added to PLAN_REVIEW state with 7 columns (Files, Tech, AC count, Output, Deps) and 6 enforcement rules so plan review captures the full structure of each step
- **DONE state release logic consolidated** — release behavior now exists in exactly one place (`auto-done-state.md`); `first-aid-controller.md` DONE state delegates to `auto-done-state.md` for all release steps, eliminating duplication

## [1.0.0] — 2026-02-26

### Added

- **GitHub MCP in Setup Wizard** — `/aid-setup` now includes GitHub MCP as recommended option 6e with full setup flow covering detection, auth check, install, verification, and troubleshooting
- **Setup Completion Banner** — `/aid-setup` displays a professional styled ASCII art banner with AID branding after successful setup completion
- **Version Pre-check in Plan Epic** — `/aid-plan-epic` Step 0 reads the local plugin version, compares it with the latest GitHub release via `gh api`, and warns if outdated (non-blocking)
- **Help Workflow Examples** — `/aid-help examples` returns three step-by-step workflows: Greenfield Feature, Quick Fix, and Multi-Phase with FIRST AID
- **Autonomous Mode Commands in Help** — `/aid-help commands` now includes detailed entries for `/aid-first-aid` and `/aid-stop` under a new AUTONOMOUS MODE COMMANDS section

### Changed

- **Setup MCP Options** — re-lettered MCP sub-options so GitHub MCP is 6e, Auto-detect is 6f, and Custom is 6g; restructured Step 5b as Optional MCP Follow-up
- **Skill Count** — updated documented skills count from 20 to 21 in CLAUDE.md and README to include the previously unlisted `workflow-intelligence.md`

### Fixed

- **Stale Paths** — replaced three remaining `workspace/workflow/` references with `.aid-o/` equivalents in `planner.md`, `aid-plan-epic.md`, and `slack-mcp.md`
- **README Version** — synced README version from stale 0.9.2 to 0.9.3 (now bumped to 1.0.0 with this release)
- **Command Frontmatter** — verified all 13 commands have `user_invocable: true`

## [0.99.0] — 2026-02-26

### Added

- **AID Server** (`packages/aid-server`) — Express + WebSocket backend serving the AID GUI dashboard; 18 REST API endpoints covering projects, pipeline state, EPIC queue, decisions, evidence, audit, ideas, usage metrics, and knowledge; real-time WebSocket pub/sub with chokidar file watching on `.aid-o/`; topic-based subscriptions with heartbeat and idle timeout
- **Docker deployment** — multi-stage Dockerfile (gui-build → server-build → production) and docker-compose.yml; single `docker compose up --build` serves both GUI and API on port 3911; health check included
- **Docusaurus documentation site** — full docs site with architecture, configuration, contributing, troubleshooting, reference docs, and Getting Started guides; deployed to GitHub Pages via GitHub Actions; EN + CS locales
- **GUI frontend polish** — AI Companion panel, replay controls, error boundaries, production build optimization (FIRST AID EPIC session, 5 EPICs completed autonomously)

### Fixed

- **MDX expression errors** — escaped `{type: performance}` in `decision-policies.md` and `{message_type}`/`{action}` in `slack-integration.md` that broke Docusaurus MDX compilation
- **GitHub Pages config** — replaced all placeholder values in `docusaurus.config.ts` (`your-org` → `marekstancl`, `your-project` → `claude-aid-o`)
- **GUI Page Crashes** — added null guards to QueueScheduler, KnowledgeBase, and HealthObservatory to prevent TypeError crashes on empty data
- **WebSocket Connection** — connected useWebSocket hook in App.tsx so real-time events flow to all dashboard screens
- **CC Usage Gauge Visibility** — removed responsive hiding so CC Usage gauge is always visible in topbar, even when disconnected
- **Mobile Connection Banner** — removed `hidden md:flex` so connection status banner shows on mobile viewports
- **Project Selector Z-Index** — added z-50 to dropdown container so it renders above the sidebar overlay
- **Sidebar Responsive Collapse** — sidebar auto-collapses to icon mode on viewports below 768px with hamburger toggle and backdrop overlay
- **Pipeline Theater Empty State** — shows "No pipeline data" message instead of stale replay counter when no runs exist
- **SVG Path Animation Error** — suppressed motion.path rendering when no pipeline data is displayed, eliminating console errors
- **API JSON Fallback** — added /api/* catch-all route returning JSON 404 before static file fallback, preventing HTML responses for unknown API routes
- **Notification/Settings Buttons** — added "Coming soon" tooltips and safe click handlers to prevent crashes
- **Project Fetch Response Parsing** — fixed App.tsx legacy fetch that expected raw array but API returns `{ ok, data }` envelope, so currentProject was never set and WebSocket never connected
- **Health Observatory Audit Data** — fixed double-wrapping of audit reports array that caused latestAudit to be an array instead of an object, breaking score display
- **Health Check Route Collision** — moved Express health-check endpoint from `/health` to `/api/health` so the GUI's `/health` route (Health Observatory page) is served by the SPA fallback instead of returning raw JSON

### Changed

- **Default port** — server default port changed to 3911 (config.ts, Dockerfile, docker-compose.yml)
- **Version bump** — all packages bumped to 0.99.0 (aid-server, aid-gui, docs)

## [0.9.3] — 2026-02-25

### Fixed

- **GATES → CURATOR_RESOLVE transition** (`skills/epic-orchestration.md`) — GATES state now correctly transitions to CURATOR_RESOLVE instead of skipping directly to PM_APPROVAL; restores the full state machine flow (GATES → CURATOR_RESOLVE → PM_APPROVAL) so Curator proposals are processed for every EPIC
- **Qdrant config unification** — `memory-config.yaml` is now the single source of truth for `memory.enabled`; removed duplicate flag from `project-profile.yaml`; added non-blocking Qdrant startup probe in IDLE state for early availability detection

### Added

- **CURATOR_RESOLVE auto-mode conditionals** (`skills/epic-orchestration.md`) — in FIRST AID mode, effort:S proposals get inline fixes while effort:M/L are auto-deferred to backlog with urgency tags; failed inline fixes silently defer (non-blocking)
- **Credit exhaustion detection** (`skills/epic-orchestration.md`) — PHASE_CHECK now validates agent output before evaluation; detects 5 Claude Code credit error patterns via string matching; auto-pauses with `interrupted_step_context.json` + git stash; FIRST AID resume recovers interrupted steps
- **Wiring step generation** (`skills/planner.md`) — POST_WAVE_WIRING_CHECK detects shared files across parallel wave steps and auto-generates a wiring step with context (shared_files, contributing_steps, expected_actions); new `wiring` and `wiring_context` fields in `plan.schema.json`; EXECUTING state recognizes wiring steps with specialized dispatch prompt
- **EPIC & plan archival** (`skills/epic-orchestration.md`, `commands/aid-first-aid.md`) — DONE state archives completed EPICs to `02-epics/archive/`; QUEUE_ADVANCE archives plans when all plan EPICs complete; non-blocking with `mkdir -p` safety
- **FIRST AID ASCII art animations** (`commands/aid-first-aid.md`) — 4-frame syringe-themed startup animation, depleted-syringe completion banner with CURATOR FINDINGS summary, re-injection resume banner
- **CURATOR FINDINGS section** in FIRST AID completion report — shows implemented/deferred/rejected proposal breakdown with per-EPIC table

## [0.9.2] — 2026-02-24

### Added

- **FIRST AID Autonomous Mode** — `/aid-first-aid` starts autonomous EPIC queue execution with agent-driven quality checks replacing PM approval points; `/aid-stop` disengages immediately, restoring manual mode at the current natural pause point
- **Permission Sandwich** (`skills/permission-sandwich.md`) — automatic permission backup, elevation, and restoration for autonomous execution with crash recovery and permission learning; permissions are scoped to the auto-mode session and restored unconditionally on exit
- **Auto-Mode Escalation Protocol** (`skills/auto-escalation.md`) — 16 trigger conditions with severity classification, pause/resume flow, escalation budget tracking (max 3 before mandatory PM review), and `continue-manual` handoff option
- **Auto-Mode DONE State** (`skills/auto-done-state.md`) — automatic release decisions (defer intermediate, mandatory bump on last EPIC), queue transitions, and cross-EPIC summary aggregation to `auto-mode-state.yaml`
- **FIRST AID command** (`commands/aid-first-aid.md`) — PM-facing command to activate autonomous mode: queue confirmation, permission elevation, and auto-mode-state initialization
- **Aid-Stop command** (`commands/aid-stop.md`) — immediate autonomous mode stop command; safe mid-EPIC stop after current step completes

### Changed

- **PLAN_REVIEW** (`skills/epic-orchestration.md` Section 3) — auto-mode: schema, completeness, dependency graph, and run file quality validation replace PM prompt; validation failure triggers ESCALATION; manual mode unchanged
- **PHASE_CHECK** (`skills/epic-orchestration.md` Section 5) — auto-mode: adds one "fresh approach" retry cycle after `max_review_fix_cycles` exhausted before escalating; manual mode unchanged
- **ESCALATION** (`skills/epic-orchestration.md` Section 9) — auto-mode: pauses mode, saves progress snapshot, increments escalation counter, presents extended PM options including `continue-manual`; manual mode unchanged
- **PM_APPROVAL** (`skills/epic-orchestration.md` Section 11) — auto-mode: intermediate EPICs auto-approved; last/standalone EPIC auto-approved only after 4 guardrails pass (gates, no critical issues, escalation budget, auditor trend); rule teaching suppressed in auto-mode; manual mode unchanged
- **DONE state** (`skills/epic-orchestration.md` Section 12) — auto-mode: intermediate EPIC version bump auto-deferred, last EPIC auto-bumped; queue transition loads next EPIC automatically; auto-mode exits and restores permissions when queue is exhausted; manual mode unchanged

## [0.9.1] — 2026-02-24

### Added

- **Initial Analysis Phase** (`skills/brainstorming.md`) — mandatory structured analysis before questioning; 8-rule protocol with 4 required elements (topic understanding, key dimensions, potential challenges, clarification preview); PM confirmation gate; trivial topic escape hatch
- **Release Sub-Phase** (`skills/epic-orchestration.md`) — version bump detection and execution in DONE state; reads `release-policy.yaml` for CHANGELOG pattern, version files, multi-phase deferral; supports `json_field` and `regex` update strategies, git tagging, GitHub releases
- **Release policy config** (`defaults/policies/release-policy.yaml`) — configurable versioning: CHANGELOG header pattern, version file locations, update methods, multi-phase plan detection, git tag and GitHub release controls

### Changed

- **Questioning Protocol strengthened** (`skills/brainstorming.md`) — Rule 2 upgraded from "Prefer MULTIPLE CHOICE" to "ALWAYS use MULTIPLE CHOICE with recommendation"; added Rules 10-11 for structured directional options and contrastive reasoning
- **MUST Rules expanded** (`skills/brainstorming.md`) — 3 new entries (15-17): mandatory analysis before questions, options at every decision point, reasoning for alternatives
- **Command flow updated** (`commands/aid-brainstorm.md`) — 10-step → 11-step flow; new Step 2 (Analysis) inserted between Context and Questions; all subsequent steps renumbered with cross-references updated
- **DONE state enhanced** (`commands/aid-run-epic.md`) — Release Sub-Phase integrated before branch merge; DONE action items reordered (run file update → release → merge → archive)

### Fixed

- **Example EPIC lookup type filter** (`skills/brainstorming.md`) — changed from `"example_epic"` to `"example"` to match actual frontmatter in 19 example files
- **Example EPIC lookup scan** (`skills/brainstorming.md`) — changed from flat `defaults/examples/` to recursive `defaults/examples/**/*.md` to find files in subdirectories

## [0.9.0] — 2026-02-24

### Added

- **Plan-ref injection** (`skills/epic-orchestration.md`) — dispatch template now includes `plan_ref` with Source Plan Integration protocol: 3-strategy matching cascade (keyword → heading → sequential), 3000-line truncation guard, `<plan_context>` block in agent prompts
- **Sequential ID generation** (`skills/epic-orchestration.md`) — ID Format Specification for Plans (`P{NNN}`), EPICs (`E-{NNN}-{epic_run}_{plan_step}`), and Runs (`R-{NNN}-{epic_run}_{plan_step}-{run_seq}`); Counter File protocol (`counter.yaml`); atomic increment rules
- **Evidence Incomplete detection** (`agents/auditor.md` section F.5) — `evidence_incomplete` finding type with `-3` deduction per missing mandatory file; only checks completed steps
- **Mandatory Evidence Write Checklist** (`skills/epic-orchestration.md`) — Step Evidence File Types table listing mandatory vs optional evidence files per step

### Changed

- **SESSION → RUN terminology** — renamed across 45+ files: `session` → `run`, `session-management.md` → `run-management.md`, `session-validator.md` → `run-validator.md`, 4 template files renamed; `sessions/` directory → `runs/`
- **Flat evidence structure** (`commands/aid-run-epic.md`, `skills/epic-orchestration.md`) — removed 5 empty subdirectory creation (analysis/, discovered_issues/, parallel_groups/, prompts/, reviews/); evidence now written directly to `steps/step_{N}_{role}/`
- **Budget references removed** — removed budget estimation lines from `defaults/templates/epic.md`, `defaults/templates/epic-example.md`, `skills/brainstorming.md`
- **Auditor check #12 path updated** (`agents/auditor.md`) — `evidence/discovered_issues/` → `steps/step_{N}_{role}/discovered_issues.md`
- **Analysis-merge evidence paths** (`skills/analysis-merge.md`) — `evidence/{epic_id}/{run_id}/analysis/` → `steps/step_{target}_{role}/`

## [0.8.2] — 2026-02-23

### Fixed

- **Czech-language content removed** — translated all Czech text to English in `agents/lessons-extractor.md`, `skills/session-management.md`, `skills/agent-core.md`
- **Broken skill reference in `aid-epic-queue.md`** — `skills/aid-epic-queue.md` → `skills/epic-queue.md`, `aid-epic-queue.yaml` → `epic-queue.yaml`
- **Stale `workspace/workflow/` paths** — 12 legacy path references replaced with `.aid-o/` equivalents in `skills/session-management.md`
- **Stale command prefixes** — `/run-epic` → `/aid-run-epic`, `/plan-epic` → `/aid-plan-epic` in `skills/retry-engine.md`, `skills/planner.md`, `defaults/templates/epic-example.md`
- **Version mismatches** — header/footer versions aligned to 0.8.2 in `session-management.md`, `epic-orchestration.md`, `retry-engine.md`, `planner.md`, `agent-core.md`
- **Hardcoded Slack channel ID** — replaced `C0AFP2GP459` with `YOUR_CHANNEL_ID` placeholder in `commands/aid-setup.md`
- **Plugin README version** — updated from 0.4.1 to 0.8.2

### Added

- **Untrusted-content framing** — SECURITY section in `skills/epic-orchestration.md` documenting mandatory `<untrusted_content>` tags for user-provided content in dispatch prompts (CWE-77, OWASP LLM01)
- **Advanced preset warning** — explicit risk documentation and PM confirmation requirement in `defaults/policies/permissions.yaml`

### Changed

- **CLAUDE.md structure info** — corrected command count (10 → 11) and skill count (14 → 17); removed stale `docs/` directory reference
- **CHANGELOG alignment** — root and plugin `[0.8.1]` entries made identical per CLAUDE.md policy

## [0.8.1] — 2026-02-23

### Added

- **Process Audit type** (`agents/auditor.md` section F) — 6th audit type, always runs, with 13 checks across 4 categories: F.1 EPIC Lifecycle (3 checks), F.2 Evidence Completeness (6 checks), F.3 Cross-Validation (3 checks), F.4 Stage Log Integrity (1 check); deduction-based scoring (0-100); `process: {0-100}` field added to YAML output; 15% weight in Overall score; Score Overview template updated with Process row

### Changed

- **Audit weight redistribution** (`agents/auditor.md` weight table) — Documentation 20% → 25%, Process 15% added; total always-run audit types: 3 → 4; audit type count: 5 → 6

## [0.8.0] — 2026-02-23

### Added

- **CURATOR_RESOLVE state** — new state between GATES and PM_APPROVAL in the epic-orchestration state machine; auto-evaluates Curator proposals via 3-tier algorithm (YAML rules → Qdrant history → default), dispatches fix agents, writes lessons with 3-layer dedup
- **`curator_auto_rules`** in `decision-policies.yaml` — configurable auto-resolution rules for improvement proposals
- **PM override + rule teaching** at PM_APPROVAL — PM can override rejected proposals and teach new auto-rules that persist via YAML + Qdrant
- **Improvement Pipeline analytics** — Report Type 4 in `/aid-analytics` for curator pipeline metrics
- **3-layer Lessons-Extractor dedup** — text, semantic, and Qdrant cross-project deduplication

### Changed

- **State machine**: 11 → 12 states (CURATOR_RESOLVE inserted)
- **DONE state simplified**: Curator + Lessons-Extractor moved to CURATOR_RESOLVE
- **`backlog.md`**: PROP-* IDs migrated to IMP-{NNN} with legacy alias table
- 9 files updated across agents, skills, commands, and policies

## [0.7.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.6.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.5.0] — 2026-02-22

### Added

**Phase 1 — Research + Storage + Consumption:**
- **Knowledge acquisition skill** — new `skills/knowledge-acquisition.md` with Research, Storage, and Consumption protocols; Context7 MCP as primary source, WebSearch fallback, dual storage (per-project YAML index + global Qdrant), 4-gate quality protocol
- **Context7 MCP in `/aid-setup`** — Option 6b for framework documentation via MCP; auto-detection, verification, troubleshooting guide
- **Docker MCP elevated to recommended** — Option 6d in `/aid-setup`; auto-detection of Dockerfile/docker-compose.yml, dedicated install section
- **Documentation type in memory-mcp** — Type 6 with full metadata schema and 4-gate Documentation Quality Gate Protocol
- **Knowledge-Augmented Brainstorming** — `brainstorming.md` Step 1 and Step 3 integration with `knowledge_find()`; non-blocking with 5s timeout, graceful degradation
- **KNOWLEDGE CONTEXT block in agent-core** — 3-section block (Framework Documentation, Patterns, Lessons) with type-specific staleness thresholds (90/180/365 days)
- **`knowledge-base.yaml` template** — per-project reference index for documentation sources
- **Knowledge config in `memory-config.yaml`** — `knowledge:` root-level section with research, quality, and context7 subsections

**Phase 2 — On-Demand Research + Aging:**
- **`/aid-research` command** — on-demand research for specific frameworks/libraries; `--deep` mode for comprehensive documentation ingestion
- **Aging protocol** — TTL-based freshness weighting for all document types (90–365 days); stale/expired score multipliers (0.7/0.3); automatic exclusion after 180 days past TTL
- **Manual source addition** — conversational flow for adding documentation sources via URL or topic
- **Freshness weighting in `memory_find()`** — search results weighted by document age; stale chunks deprioritized automatically
- **Aging config in `memory-config.yaml`** — per-type TTL values, stale/expired weights, exclusion threshold

**Phase 3 — Auto-Extraction + Community Examples + Feedback:**
- **Example EPIC extraction protocol** — 7-stage `extract_example_epic()` function: eligibility check → extract → abstract → build text → PM approval → dedup → Qdrant storage; triggered in DONE state step 9b
- **`example_epic` document type** — Type 8 in memory-mcp.md with 11 metadata fields (frameworks, archetype, source_epic_id, complexity, roles, etc.); never-expire TTL; global project scope
- **Community example EPICs** — 3 curated templates in `defaults/examples/`: `langchain-rag-chatbot.md`, `fastapi-crud-service.md`, `react-dashboard.md`; placeholder paths, version ranges, standard EPIC template format
- **Example EPIC lookup in brainstorming** — Step 3 searches `defaults/examples/` + Qdrant for matching archetypes; PM offered: (A) Adapt, (B) Browse all, (C) Start fresh
- **Feedback tracking** — fire-and-forget `track_retrieval()` after `memory_find()`; tracks `times_retrieved` and `avg_retrieval_score` per framework in `knowledge-base.yaml`; deprecation signal after 180 days of zero retrievals
- **Feedback config in `memory-config.yaml`** — `feedback:` section with `track_retrieval`, `track_usefulness`, `deprecate_unused_after_days`

### Changed
- **Command prefix standardization** — 5 commands renamed to `aid-*` prefix (`run-epic` → `aid-run-epic`, etc.) for discoverability; 9 unused command files removed; 20+ cross-references updated
- **`/aid-plan-epic` UX text** — updated intro and Step 9 output for unified Plan→EPIC→Plan flow
- **`/aid-help` command description** — updated `/aid-plan-epic` entry to "Unified Plan→EPIC→Plan entry point"
- **DONE state in `epic-orchestration.md`** — new step 9b triggers example extraction after Curator; completion summary includes archetype when pattern is stored
- **`memory-mcp.md` document types** — expanded from 6 to 8 types (added Proposal, Example EPIC); feedback tracking hook in `memory_find()`
- **`brainstorming.md` non-blocking guarantee** — knowledge calls updated from 2 to 3 per session (Step 1 search + Step 3 knowledge + Step 3 examples); 7 new graceful degradation scenarios

## [0.4.2] — 2026-02-21

### Changed
- **`/plan-epic` step numbering** — renumbered all steps from fractional (0.5, 0.7, 2.5) to clean integers (1-9); internal cross-references updated
- **`/aid-brainstorm` step numbering** — renumbered Step 8b→9 and Step 9→10; new Step 10 presents interactive A-D handoff options (add items, all-phases EPIC, specific-phase EPIC, manual)
- **Cross-references** — updated plan-epic step references in run-epic.md (3 occurrences) and epic-orchestration.md (2 occurrences); updated aid-brainstorm.md and brainstorming.md internal refs

### Added
- **`/aid-init [path]` parameter** — documented optional path parameter in aid-init.md Usage section with examples for relative and absolute paths; updated aid-help.md entry
- **Phase selection** — plan-epic.md Step 2 now handles all-phases vs specific-phase EPIC generation when invoked from brainstorming with phase context
- **Re-opening protocol** — brainstorming.md documents how Option A (add items) works: load existing plan, display approved sections, return to Step 2, re-generate EPIC
- **Phase Selection section** — brainstorming.md EPIC Subagent Prompt Template includes phase handling for scoped EPIC generation

## [0.4.1] — 2026-02-20

### Added
- **`/aid-init` upgrade mode** — detects existing workspace, compares installed vs. plugin version, classifies files as NEW / UPGRADABLE / UNCHANGED / CUSTOM / PROTECTED, asks PM before updating
- **Config manifest** — `.aid-o/03-config/.aid-manifest.yaml` tracks installed plugin version and md5 checksums of all config files; enables safe detection of PM customizations
- **Dynamic defaults scanning** — `/aid-init` scans `defaults/` directories instead of hardcoded file list; new files in future versions are automatically included
- **`source_plan` in plan schema** — `defaults/templates/plan.schema.json` now includes the `source_plan` field for Variant B pipeline

### Changed
- **CHANGELOG format** — standardized all entries to `**Bold Name** — description` format; root and plugin CHANGELOGs are now identical
- **CLAUDE.md release protocol** — added CHANGELOG format standard, README Roadmap update rules, and 10-step release workflow
- **`/aid-init` description** — updated in `aid-help.md` to reflect upgrade capabilities

## [0.4.0] — 2026-02-20

### Added
- **Zero Detail Loss Pipeline (Variant B)** — EPIC references source plan via `plan_ref`; all pipeline stages (plan.json, session, agent dispatch) read both EPIC and source plan; agents receive `## Source Plan — Implementation Detail` sections
- **Wave-based execution model** — planner groups steps by DAG level into waves (max 4 per wave) for parallel execution; replaces flat parallel group detection
- **Step decomposition** — layer-based splitting of monolithic steps (data → schema → API → test) to enable cross-domain parallelism; supports dev, docs, and infra decomposition types
- **Critical path analysis** — opt-in for 7+ step EPICs; computes critical path ratio, applies 5 relaxation rules (R1–R5) to shorten it; PM can reject individual relaxations at PLAN_REVIEW
- **Parallelism-first optimization** — 5-priority strategy (parallelism > wave density > session compactness > quality > efficiency); plan quality metrics in `optimization_metrics`; validation rules V-20–V-23
- **`/plan-epic` accepts Plan files** — 3-tier format detection (frontmatter → header → section fingerprinting); auto-generates EPIC from Plan using EPIC Subagent Template
- **`/aid-brainstorm` inline execution** — Step 8b offers to generate Plan JSON + Session immediately after EPIC draft; Step 9 split into 9a (standard handoff) / 9b (full pipeline handoff)
- **Wave-based session boundaries** — sessions are contiguous sequences of waves; never split by domain or inside a wave
- **Shorthand commands** — all 18 commands have `user_invocable: true` frontmatter enabling `/aid-setup` instead of `/aid-orchestrator:aid-setup`
- **Setup followup** — after "All recommended", `/aid-setup` now offers additional options (CLAUDE.md, Slack, auto-detected MCPs)
- **Selective `.aid-o/` gitignore** — plans, EPICs, and config are versioned; engine artifacts (sessions, evidence) are ignored
- **Centralized Qdrant storage** — `~/.local/share/aid-orchestrator/qdrant-data` with `--scope user` for global MCP; migration check for old paths

### Changed
- **EPIC template** — typed artifacts (`endpoint:`, `model:`, `component:`), `plan_ref` enforcement, Hints section, Scope with specific file paths
- **EPIC Subagent Template** — frontmatter instructions, plan task ID preservation in steps, Variant B zero detail loss instruction
- **Planner input validation** — REQUIRED/RECOMMENDED checks with typed artifact inference
- **PLAN_REVIEW** — rich plan summary with wave execution plan, optimization metrics, session breakdown
- **EXECUTING state** — agent dispatch enriched with source plan sections
- **Plan generation flow** — 13-step procedure with decomposition (2.2), wave assembly (6), CPA (6.1), session boundaries (11)

## [0.3.0] — 2026-02-19

### Added
- **Execution Summary block** — mandatory in all agent outputs with timing, self-assessment, and Qdrant storage
- **Per-agent metrics** — step duration, complexity self-report, bottleneck flags stored to Qdrant
- **Cost optimization skill** — 4 axes: model selection, file scoping, dispatch prompt trimming, token tracking
- **EPIC completion summary** — 5 next-step options presented to PM at DONE state
- **Auto-archive** — multi-EPIC and multi-session counter awareness for session and EPIC files
- **Multi-session flow** — planner optimization engine for EPICs with 7+ steps
- **Diff patches** — `diff.patch` generation for every file-modifying step, saved to evidence store
- **Curator auto-invocation** — mandatory synchronous step in POST_PROCESSING
- **Chat-first `/aid-setup`** — detailed option presentation and guided configuration
- **Post-setup guidance** — `/aid-brainstorm` recommendation after onboarding
- **Playwright E2E agent** — optional parallel step, auto-added when frontend detected
- **Application type classification** — 11 types in project scanner (web-app, api-service, cli-tool, desktop-app, mobile-app, library, plugin, script, monorepo, erp-module, infrastructure)
- **Auto-scaffold** — generates starter files for uninitialized projects before EPIC execution
- **Cross-project knowledge** — Qdrant with `project_name` metadata tagging for multi-project memory
- **Backlog categorization** — by type (bug, enhancement, tech-debt, security, docs) and source agent
- **`/aid-analytics`** — orchestration performance analysis command and skill
- **Permission presets** — dual-write system keeping `.claude/settings.json` + `.aid-o` policies in sync
- **Git branch integration** — one branch per EPIC session, auto-create and auto-merge
- **Pre-Output Quality Check** — in all code-producing playbooks (ruff lint/format, debug artifact removal, import verification)

### Fixed
- **DONE state** — now writes lessons to `lessons-learned.md`, updates session status to `completed`, writes commands to `command-history.md`, writes final `stage_log` entry with `result: success`
- **Gate reconciliation** — `plan.json` gates now reconciled with `gates.yaml` definitions
- **Qdrant isolation** — writes now include `project_name` metadata for cross-project isolation
- **Slack MCP** — onboarding corrected to use `@anthropic/slack-mcp` package with proper scopes

### Changed
- **Agent model assignments** — QA, Security, Docs agents use Sonnet; utility agents use Haiku
- **Dispatch prompts** — trimmed to deps-only context, EPIC summary, and playbook reference
- **`/aid-help` examples** — updated with full-stack development examples
- **Memory search** — `top_k` reduced from 5 to 3 for relevance and cost optimization
- **Git Discipline** — section added to all 9 role playbooks

## [0.2.0] — 2026-02-18

### Added
- **`/aid-brainstorm`** — 9-step interactive brainstorming flow (context → questions → approaches → design → sections → approval → document → EPIC draft → handoff)
- **Brainstorming skill** — process rules, key principles, EPIC subagent prompt template
- **MCP server onboarding** — Qdrant local (no Docker), Slack opt-in, auto-detect, custom
- **Permission presets** — Safe / Recommended / Advanced in `/aid-setup`
- **Document language** — `language.yaml` configuration with ISO 639-1, default EN
- **Parallel isolation strategy** — `dispatch-strategy.yaml` with worktrees / branches / sequential
- **Git worktree support** — creation and cleanup logic for parallel agent dispatch
- **Qdrant orchestration logging** — dispatch and completion events with graceful JSONL fallback
- **Enriched `final_report.md`** — generation from Qdrant data
- **Lessons learned** — auto-collection and storage in Qdrant at EPIC completion
- **CLAUDE.md marker merge** — `<!-- AID-O START/END -->` markers in `/aid-init`
- **Interactive examples** — `/aid-help examples` with 3 project prompts

### Changed
- **`/aid-setup`** — includes 4 new configuration steps (MCP, permissions, language, isolation)
- **`/aid-init`** — copies `dispatch-strategy.yaml` and `language.yaml` to workspace
- **LLM cost estimates** — conditioned on `billing_mode: api` (hidden for subscription users)

### Removed
- **`examples/bookmark-manager/`** — replaced by interactive `/aid-brainstorm` prompts

## [0.1.0] — 2026-02-16

### Added
- **Initial release** — Controller + Workers architecture for Claude Code
- **17 slash commands** — `/aid-init`, `/aid-setup`, `/run-epic`, `/plan-epic`, etc.
- **18 agents** — 9 role + 3 specialist + 6 utility
- **13 skills** — epic orchestration, planner, gates engine, parallel dispatch, etc.
- **11 role playbooks** — customizable per project
- **Quality gates** — auto-retry (3x) and PM escalation
- **Slack MCP integration** — with chat fallback
- **Qdrant vector memory** — optional, with file-based fallback
- **EPIC queue** — autonomous sequential execution
- **Evidence trail** — `stage_log.jsonl`, gate reports, agent outputs
