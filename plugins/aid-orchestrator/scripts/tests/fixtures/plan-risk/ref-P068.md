---
id: REF-P068
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P068-plan-final-release-boundary.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P068

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage sync` and `--stage freeze`.
- Modify: `plugins/aid-orchestrator/defaults/schemas/plan-boundary-manifest.schema.json` — declare `candidate_frozen_at` (RFC 3339 UTC string, nullable) beside the existing `candidate_sha` in the RUNTIME plan-boundary manifest, with the same nullability rule so the pair is legal only together.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` — initialize, validate, atomically set and atomically clear `candidate_frozen_at` in the same write that sets or clears `candidate_sha` (this library owns `candidate_sha`; the timestamp must never be written or cleared independently of it).
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — this plan's mandatory integration suite; every later step extends it.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh` (lines ~242-360) — re-grep by symbol first; resolve plugin-relative contract paths, and refine the already-non-blocking absent-graph handling to record `plan_graph: absent_pre_generation` in place of the current opaque zero-byte seal. This step improves how an unproduced graph is represented; it does not add a graph producer and makes no claim about how a review must treat its absence.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-c0-plan-review.bats` (lines ~383) — re-grep by symbol; extend the golden manifest fixture and expected `input_hash` for the `absent_pre_generation` `plan_graph` shape and the plugin-relative contract paths. The absent-graph fixture already exists — extend it, do not re-add it.
- Modify: `.github/workflows/ci.yml` (lines ~7-30) — add a `plan-final-tests` job for the new suite with its own timeout and `yq`.
- Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (lines ~49-57) — add the new suite to the dedicated-CI-job exclusion list P064 introduced.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~26-380) — restructure into subcommand dispatch and add `prepare-plan`, which edits version files without committing a tag or sweeping unrelated changes.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC1 freeze/invalidation and AC6 tag-once cases.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage gates`.
- Modify: `.aid-o/config/execution.yaml` — add a `release_quarantine` gate profile: every gate in `release` EXCEPT `bats_all` (i.e. `bats_fsm`, `shell_pipeline_smoke`, `plan_diff`, `docs_updated`). The existing `bats_all_quarantine` profile is EPIC-boundary-scoped and omits `shell_pipeline_smoke`, so it cannot serve a plan-final release run without silently dropping a non-quarantined release gate.
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (lines ~177-260) — add the additive `--base-commit` and `--plan-path` flags so a plan-final run can supply the substitution tokens an EPIC state file would otherwise provide.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC2 gate-report assertions.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage review`, including the required-output contract and the invalidation trigger.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~996-1090) — rewrite the DONE closure checklist and the C+A execution model for the plan-final boundary.
- Modify: `plugins/aid-orchestrator/defaults/schemas/delivery-gate.schema.json` — allow `identity.epic_id` to be string-or-null so the plan-level aggregate (`epic_id: null`, `plan_id` set) is schema-valid; today it requires a string.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC3 dispatch-count and invalidation cases.
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~460-530) — add the flag-driven plan mode alongside the untouched positional EPIC mode.
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~300-370) — make `compute_reporter` and `compute_simplifier` plan-boundary-aware instead of gating on the EPIC `ca-review-complete` marker.
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~518-554) — resolve the `plan_review` input from the plan's own C0 review in plan mode instead of from `epic_input.md` frontmatter.
- Modify: `plugins/aid-orchestrator/defaults/schemas/release-decision.schema.json` — widen the `blockers[].input_id` enum for plan-mode inputs and per-EPIC roll-up blockers.
- Modify: `plugins/aid-orchestrator/scripts/aid-pm-brief.sh` (lines ~40-160) — render a plan-level brief from a plan-mode decision.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage c4` and `--stage summary`.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC4 identity cases.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-merge-to-main`.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~360-380) — add the `tag-plan` subcommand and make tagging idempotent.
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-push` (lines ~30-50) — exempt `plan/*` and `task/*` branches from the version-bump push block.
- Create: `plugins/aid-orchestrator/defaults/schemas/pm-plan-decision.schema.json` — the PM authorization contract validated before any merge action.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~36-50, ~470-700) — teach the five binding-path functions a plan-mode that advances the target ref by plumbing (`commit-tree` + CAS `update-ref`) instead of requiring a checkout, so delivery bindings and the receipt commit in one post-merge pass even when the target branch is checked out in another worktree.
- Modify: `plugins/aid-orchestrator/defaults/schemas/plan-lifecycle-manifest.schema.json` — widen `declared_epics[].scope` from `[required, backlog]` to include `abandoned` and `superseded`, and add a top-level `status` property (`active | closed | aborted`); the schema is `additionalProperties: false`, so neither the CF1 re-scope nor the abort record can produce a valid manifest without both changes. (`candidate_frozen_at` is deliberately NOT added here — it is a RUNTIME plan-boundary-manifest field owned by Step 1; see below.)
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~730-808) — exclude the two new scopes from the closure predicate's required set.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC5 and AC6 cases.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-close-check` and the close transaction.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-close-check.sh` (lines ~440-515) — add the plan-branch checks and the receipt reconciliation.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~322-373) — give `aid_lifecycle_plan_close` and its receipt commit the same plumbing plan-mode Step 5 adds to the binding path, so the receipt is committed by `commit-tree` + CAS `update-ref` onto the target ref without a checkout — the close path must work when the target branch is checked out in another worktree.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-state.sh` — add `plan-close` to the operation-record `command` enum so the close transaction is reconcilable like every other.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~4428-4522) — make `cmd_plan_close` delegate to the plan layer for `plan_branch` plans.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC7 corruption and resume cases.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — add the `inventory` subcommand and the mode default.
- Create: `plugins/aid-orchestrator/defaults/policies/plan-boundary-policy.yaml` — the mode default, the lock lease seconds and the plan-final profile floor.
- Test: `plugins/aid-orchestrator/defaults/templates/plan.md` (lines ~10-20) — verify the existing `lifecycle_strict: true` emission still holds; no edit expected.
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (lines ~250-290) — call `plan-start` for new plans and stamp `mode` into the lifecycle manifest it already writes.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC8 mode cases.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add the AC9 resilience matrix.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — add the `AID_PLAN_FSM_CRASH_AFTER` test seam.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — replace the per-EPIC release narrative (re-grounded 2026-07-24: the `legacy_epic_release_mode` ritual is now at ~lines 1739-1883, heading ~:1821; the per-EPIC C+A dispatch model at ~:1132-1187) with the mode-conditional plan-final narrative, and correct the stale cross-plan enforcement claims (now at ~:1087 and ~:1211, not the old 1069-1070). Re-grep by heading text before editing — pipeline.md grew to ~2336 lines since the draft.
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~290-330) — same change at command level, including PM summary options.
- Modify: `.aid-o/plans/P061-gate-profiles-test-cost-reduction.md` (lines ~62-66) — amend D8 with the supersession note (workspace-local; see the durability note below).
- Modify: `.aid-o/plans/P062-e10-calibration-promotion.md` (lines ~10-20) — amend the E10 precondition and the "all 6 EPICs" wording (workspace-local; see the durability note below).
- Modify: `docs/plans/AID-control-system-v2-roadmap.md` — record the P061 D8 supersession and the P062 precondition change (workspace-local; `docs/` is gitignored, so this edit serves local readers and is not the durable assertion — see the durability note).
- Modify: `docs/design/AID-control-system-v2-control-topology.md` — amend the T2 row (workspace-local, same durability caveat).
- Modify: `docs/plans/AID-control-system-v2-roadmap.md` (lines ~140-160) — insert the E9.5 phase between E9 and E10.
- Modify: `docs/design/AID-control-system-v2-control-topology.md` (lines ~355-370) — amend the T2 row and the dispatch budget accounting.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — add the remaining P064 enforcement rows.
- Modify: `docs/extending-aid.md` — document the plan-boundary layer for contributors.
- Create: `plugins/aid-orchestrator/scripts/tests/test-control-boundary.sh` — assert every AC11 claim mechanically, not just three greps.
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/control-boundary-baseline.yaml` — the checked-in pre-P064 snapshot of every policy `enforcement:` and `head_match_policy:` value that the check compares against.
- Create: `plugins/aid-orchestrator/scripts/tests/test-instruction-sweep.sh` — grep denylist over agent-facing surfaces plus the inventory completeness check. The `test-` prefix is required: `run-all-tests.sh:65` discovers only `test-*.sh`, so a `*-check.sh` name would never run as a standing CI guard (§1: a detector nothing runs is decoration).
- Create: `plugins/aid-orchestrator/scripts/tests/instruction-sweep-allow.txt` — reasoned `path:pattern` allowlist for legitimate mentions.
- Create: `plugins/aid-orchestrator/reference/instruction-surface-inventory.md` — the surface inventory with a per-surface disposition, under `plugins/aid-orchestrator/reference/`, a non-`docs`-named tracked directory (`.gitignore:87`'s unanchored `docs/` would otherwise ignore it), so the sweep check can rely on it in CI and on a clean checkout.
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` — make the plan-mode declaration and the plan-final boundary explicit where the command describes plan lifecycle.
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — document the lifecycle `mode` field and the hook reinstall requirement.
- Modify: `plugins/aid-orchestrator/commands/aid-status.md` — surface plan state, mode and candidate SHA alongside EPIC state.
- Modify: `plugins/aid-orchestrator/commands/aid-do.md` — state that Fast Mode does not create or release a plan branch.
- Modify: `plugins/aid-orchestrator/README.md` — update the lifecycle description to the plan-level model.
- Modify: `README.md` — same, for the repository-level description.
- Modify: `CLAUDE.md` — update the release workflow section, which currently documents a per-push release ritual.
- Modify: `plugins/aid-orchestrator/skills/run-management.md` — make the plan lifecycle and `active.md` guidance mode-aware.
- Modify: `plugins/aid-orchestrator/skills/agent-protocol.md` — add the agent handoff contract phrasing.
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` — make the documentation-step rule and the plan lifecycle references mode-aware.
- Modify: `plugins/aid-orchestrator/skills/role-cards.md` — relocate the Auditor, Curator, Simplifier and Reporter role cards to the plan-final boundary.
- Modify: `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md` — record the CP3 relocation from EPIC completion to plan final.
- Modify: `plugins/aid-orchestrator/commands/aid-verify-plan.md` — align the CP1 review contract with the plan-level boundary.
- Modify: `plugins/aid-orchestrator/commands/aid-verify-implementation.md` — align the DONE review contract with the plan-level boundary.
- Modify: `plugins/aid-orchestrator/agents/auditor.md` + `plugins/aid-orchestrator/agents/curator.md` — state that dispatch is plan-final, once per plan.
- Modify: `plugins/aid-orchestrator/agents/simplifier.md` + `plugins/aid-orchestrator/agents/reporter.md` — confirm the plan-final boundary and the protocol-v2 delivery artifact.
- Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (lines ~49-57) — register the new check so it runs with the suite.
- Create: `plugins/aid-orchestrator/reference/P068-plan-branch-dogfood-report.md` — the recorded end-to-end run with commands, SHAs and counts, plus the subject-selection authorization as its first section, under `plugins/aid-orchestrator/reference/`, a non-`docs`-named tracked directory (`.gitignore:87`'s unanchored `docs/` matches `plugins/aid-orchestrator/docs/` too, so the report must avoid any `docs`-named dir).
- Modify: `.aid-o/config/counter.yaml` — reserve `P067` for the dogfood subject plan.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add the AC10 invocation-count assertions over structured logs.
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — add the release entry.
- Modify: `CHANGELOG.md` — identical copy of the plugin CHANGELOG entry.
