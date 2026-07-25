---
status: active
plan_ref: .aid-o/plans/P068-plan-final-release-boundary.md
plan_epics_total: 2
runs_total: 1
runs_completed: 0
---

# EPIC: E-068-2_2 --- Plan-Final Release Boundary and Cutover

## Context

P064 delivers the integration half of the roadmap's model:
```text
EPIC = work increment        (P064)
PLAN = release / review unit (P068)
```
At P064's completion, `aid-plan-fsm.sh` exists with `plan-start`,
`epic-start`, `epic-complete`, `epic-merge-to-plan` and `plan-state`; the
plan boundary manifest, plan state file, operation record and lock helper
exist; the queue resolves dependencies against a declared merge target; gate
profiles are split by boundary and accumulate a plan-final floor; and
intermediate EPIC completion invokes no release-stack caller. What does not
exist is any way to release the result: no candidate freeze, no plan-final
gate run, no plan-level review stack, no plan-mode C4, no PM authorization,
no merge to the target branch, no tag, no close. A plan can be built but not
shipped. That is this plan's subject.
The cadence argument is unchanged from the roadmap: for a four-EPIC plan the
broad gate profile, the Auditor, the Curator, C4 and the PM merge decision
each run four times today and once after this plan. P061 decided *which*
profile to run and P063 gave gates a runtime memory; P064 and P068 decide
*when* expensive validation happens.

This EPIC covers Phase 2 of 2 from plan P068.

## Goal

Turn a completed plan branch into exactly one reviewed, authorized release:
one frozen candidate, one full gate run, one pass of each specialist, one C4
decision, one PM authorization bound to exact SHAs, one compare-and-swap
merge, at most one tag (none when the plan resolves to no version bump), and
one atomic close backed by a durable lifecycle receipt.

Phase 2/2 deliverables:
- Step 1: Stamp every active plan with an explicit mode, make
`plan_branch` the default for new plans, and refuse to operate on a plan
whose mode is missing or mixed.
- Step 2: Prove that every transaction boundary converges after a crash
and that conflicts, hotfixes and aborts never produce a false completion.
- Step 3: Update every document that currently advertises the per-EPIC
release model, and record every new enforcement in the registry.
- Step 4: Inventory every surface an agent actually reads or acts on,
make each lifecycle instruction mode-aware, and prove mechanically that no
unqualified per-EPIC release instruction survives.
- Step 5: Prove the whole path on a real plan run through `plan_branch`
mode, and produce the cadence metrics that show the change actually happened.


## Scope

### Allowed files/paths
- `.aid-o/config/counter.yaml`
- `.aid-o/plans/P061-gate-profiles-test-cost-reduction.md (lines ~62-66)`
- `.aid-o/plans/P062-e10-calibration-promotion.md (lines ~10-20)`
- `CHANGELOG.md`
- `CLAUDE.md`
- `README.md`
- `docs/design/AID-control-system-v2-control-topology.md`
- `docs/design/AID-control-system-v2-control-topology.md (lines ~355-370)`
- `docs/extending-aid.md`
- `docs/plans/AID-control-system-v2-roadmap.md`
- `docs/plans/AID-control-system-v2-roadmap.md (lines ~140-160)`
- `plugins/aid-orchestrator/CHANGELOG.md`
- `plugins/aid-orchestrator/README.md`
- `plugins/aid-orchestrator/agents/auditor.md + plugins/aid-orchestrator/agents/curator.md`
- `plugins/aid-orchestrator/agents/simplifier.md + plugins/aid-orchestrator/agents/reporter.md`
- `plugins/aid-orchestrator/commands/aid-do.md`
- `plugins/aid-orchestrator/commands/aid-init.md`
- `plugins/aid-orchestrator/commands/aid-plan.md`
- `plugins/aid-orchestrator/commands/aid-run.md (lines ~290-330)`
- `plugins/aid-orchestrator/commands/aid-status.md`
- `plugins/aid-orchestrator/commands/aid-verify-implementation.md`
- `plugins/aid-orchestrator/commands/aid-verify-plan.md`
- `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`
- `plugins/aid-orchestrator/defaults/policies/plan-boundary-policy.yaml`
- `plugins/aid-orchestrator/reference/P068-plan-branch-dogfood-report.md`
- `plugins/aid-orchestrator/reference/instruction-surface-inventory.md`
- `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh (lines ~250-290)`
- `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh`
- `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats`
- `plugins/aid-orchestrator/scripts/tests/fixtures/control-boundary-baseline.yaml`
- `plugins/aid-orchestrator/scripts/tests/instruction-sweep-allow.txt`
- `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh (lines ~49-57)`
- `plugins/aid-orchestrator/scripts/tests/test-control-boundary.sh`
- `plugins/aid-orchestrator/scripts/tests/test-instruction-sweep.sh`
- `plugins/aid-orchestrator/skills/agent-protocol.md`
- `plugins/aid-orchestrator/skills/pipeline.md`
- `plugins/aid-orchestrator/skills/plan-writing.md`
- `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md`
- `plugins/aid-orchestrator/skills/role-cards.md`
- `plugins/aid-orchestrator/skills/run-management.md`

### Forbidden zones
- <!-- No forbidden zones specified in plan -->

## Artifacts

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


## Constraints

**Ordering.** P064 must be DONE and merged before this plan starts; every
contract in `## Architecture` is P064's output. P063 is DONE (`.aid-o/work/evidence/E-063-1_1/R-E063-1/fsm-state.yaml`
reports `state: DONE`, `done_phase: release`) and P061 E1-E3 are DONE, which
satisfies the roadmap's Phase 1 and Phase 2 preconditions. P061 E2's state
file records `done_phase: review` rather than `release`; its code is merged
and its enforcement is live, so this is a bookkeeping tail, not a functional
gap. P061 E4 and E5 remain open and are explicitly not P064's responsibility:
this plan bootstraps only the `gate_profiles` block the plan-final cadence
requires (Step 8), not P061 E4's `gate_profile_defaults` or generic
`/aid-init` distribution, and not P061 E5's `/aid-do` risk escalation.
**Envelope naming.** The protocol envelope uses `schema_version: "aid-2.0"`
and `control_protocol: "aid-2.0"`. There is no `protocol_version` field in
this system; any artifact or code introducing one is wrong.
**Enforcement registry location.** The canonical registry is
`plugins/aid-orchestrator/defaults/enforcement-registry.yaml` (1341 lines / 314
rows at v2.62.1, git-tracked). The copy under `docs/plans/archive/AID-audit-2026-06/` is a
superseded seed and states so in its own header; it must not be edited as
canonical.
**Plan-close systems must be connected, not replaced.** P064 must not
silently overwrite the legacy marker and report world with the
`.aid-lifecycle/` receipt world. Step 6 reconciles them explicitly, and a
plan without a lifecycle manifest still closes.
**Queue statuses are script-written.** `merged_to_plan`, `released_to_main`
and every other status transition is written by
`lib/aid-queue-write.sh` under a lock. Manual YAML edits are not an accepted
mechanism, and hand-edited values must not be able to unblock a dependency.
**The default flip happens here, and late.** The default mode stays
`legacy_epic_release_mode` through this plan's EPIC 1. It flips to
`plan_branch` in Step 7, after the end-to-end release path exists and before
the dogfood exercises it.
**Mode is declared in the git-tracked lifecycle manifest.** Plan mode is
declared in `.aid-lifecycle/manifests/<plan_id>.yaml`, not in
`.aid-o/plans/**`. The `.aid-o/` tree is intentionally gitignored and cannot
be used as durable authority — verified, not assumed:
`git check-ignore -v .aid-o/plans/P064-plan-level-release-boundary.md`
resolves to `.gitignore:98`, and `git ls-files .aid-o/` returns zero files.
Runtime plan-state manifests under `.aid-o/work/plan-state/**` are caches
derived from the lifecycle manifest plus local execution state. If a plan
declares `mode: plan_branch` in lifecycle but the runtime manifest is
missing, commands MUST fail closed and instruct the operator to run the
sanctioned reconcile command
(`aid-plan-fsm.sh plan-state <plan_id> --repair`).
**Gate profile config is runtime config, not identity.**
`.aid-o/config/execution.yaml` is likewise gitignored, so the `gate_profiles`
table added in Step 8 is not visible to a remote reviewer or to CI. This is
acknowledged rather than fixed: gates for this repository run locally, CI
runs only the bats suites, and every test builds its own `execution.yaml`
fixture. Gate profile configuration is not a plan's identity or release
mode, so the durability argument that applies to `mode` does not apply
here.
**Git hooks are copies, not symlinks.** `defaults/hooks/pre-push` and
`pre-commit` are templates installed into `.git/hooks/` by `/aid-init`.
Changing a template does not change an installed hook, so the hooks must be
reinstalled before the dogfood run (Step 11) and in any project adopting the
new mode.
**Control authority is unchanged.** P064 changes cadence and branch
authority. Every C0-C4 finding keeps its current `observe`, `dual_run` or
`blocking` policy, including `head_match: unknown`. E10 owns promotion; E11
owns removal. The only exception is P064-owned identity — candidate, target
and manifest binding — which hard-blocks regardless of policy mode, because
it is an invariant of the new boundary rather than a finding.
**Evidence must not move the candidate.** Producing plan-final evidence must
leave `candidate_sha` and the product worktree unchanged. Any tracked write
from a specialist or a utility is a candidate-changing fix and triggers
`PLAN_FIX`.
**Concurrency.** v1 serializes plan-finalization and shared queue, active and
manifest writes behind a lock. Multiple plan branches may exist; their
finalizations do not overlap.
**Evidence-verifier scope.** `scripts/aid-evidence-verify.sh` discovers
artifacts with two finds: `-maxdepth 1` at `:249-252` and
`-mindepth 2 -maxdepth 2` at `:255-257`. Because the depth-1 sweep exists,
the verifier must be handed the **plan-final run directory**
(`.aid-o/work/evidence/<plan_id>/<run_id>/`), not the plan directory. Handing
it the plan directory would sweep every retained superseded run —
`R-Pxxx-final-1` alongside `R-Pxxx-final-2` — into one verification, which is
exactly the stale-evidence confusion the immutable-run rule exists to
prevent, and would contradict the requirement that a retry never consumes a
prior attempt's artifacts.
**No `depends_on_plans` frontmatter.** Declaring upstream plans would trigger
the lifecycle hard-block at `aid-fsm.sh:2178-2199` against plans that pre-date
the lifecycle layer and can therefore never be `closed`.

## DoD Gates

- docs_updated

## Acceptance Criteria

- [ ] [backend] A new one-EPIC plan follows `task → plan → main`, and the task branch
- [ ] [backend] Existing active plans are inventoried and stamped
- [ ] [backend] New plans default to `plan_branch` when the project's `execution.yaml` has a `gate_profiles` block, and fall back to `legacy_epic_release_mode` with a logged `plan_branch_unavailable: no_gate_profiles` otherwise (Step 7).
- [ ] [backend] Missing, unknown or mixed mode exits non-zero before mutation.
- [ ] [qa] An EPIC merge conflict enters `CONFLICT` and records no completion.
- [ ] [qa] A pre-merge abort leaves the target branch unchanged and records
- [ ] [qa] A hotfix on the target branch forces resynchronization before candidate
- [ ] [qa] Failure after the final Git merge but before the queue and close update
- [ ] [qa] Published rollback uses a new revert commit, never a history rewrite.
- [ ] [docs-writer] `skills/pipeline.md` and `commands/aid-run.md` contain no instruction
- [ ] [docs-writer] The P061 D8 and P062 precondition amendments are recorded in the
- [ ] [docs-writer] The Control System v2 roadmap E9.5 entry is recorded as a tracked
- [ ] [docs-writer] The five genuinely-new rows (`plan_final_gate_required`,
- [ ] [docs-writer] `bash plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` passes.
- [ ] [docs-writer] Every agent-facing surface has a disposition of `update`, `verified` or
- [ ] [docs-writer] `test-instruction-sweep.sh` exits 0 over the repository, and exits 1
- [ ] [docs-writer] Every lifecycle instruction that survives carries an explicit
- [ ] [docs-writer] The agent handoff contract is present in `skills/agent-protocol.md`
- [ ] [docs-writer] The backward compatibility statement names P061, P062, P063 and P065 as
- [ ] [e2e] Dogfood isolation is proven, not assumed: every dogfood command runs from
- [ ] [e2e] The dogfood report's `## Authorization` section exists and is committed
- [ ] [e2e] The chosen plan meets every eligibility criterion, or
- [ ] [e2e] The Git hooks in `.git/hooks/` are reinstalled from the templates
- [ ] [e2e] At least one multi-EPIC plan completes using `plan_branch` mode, with
- [ ] [e2e] The Auditor, Curator, Simplifier and Reporter each ran exactly once, at
- [ ] [e2e] Full gates ran once, at plan final; EPIC branches merged into the plan
- [ ] [e2e] The structured invocation logs show every cadence count required by
- [ ] [e2e] The rollback drill is recorded and the target branch was never left in


## Dependencies

### Internal (same plan)
- E-068-1_2 — Previous phase must complete first

### External (other plans/EPICs)
<!-- No external dependencies -->

### Queue Implications
depends_on: [E-068-1_2]

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | backend | Stamp every active plan with an explicit mode, make `plan_branch` the default for new plans, and ... | --- | --- |
| 2 | qa | Prove that every transaction boundary converges after a crash and that conflicts, hotfixes and ab... | --- | --- |
| 3 | docs-writer | Update every document that currently advertises the per-EPIC release model, and record every new ... | --- | --- |
| 4 | docs-writer | Inventory every surface an agent actually reads or acts on, make each lifecycle instruction mode-... | 3 | --- |
| 5 | e2e | Prove the whole path on a real plan run through `plan_branch` mode, and produce the cadence metri... | 2, 3 | --- |


## Step UI Contracts

<!-- No ui_change_mode fields in this plan -->
<!-- step-1: files=["Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — add the `inventory` subcommand and the mode default.","Create: `plugins/aid-orchestrator/defaults/policies/plan-boundary-policy.yaml` — the mode default, the lock lease seconds and the plan-final profile floor.","Test: `plugins/aid-orchestrator/defaults/templates/plan.md` (lines ~10-20) — verify the existing `lifecycle_strict: true` emission still holds; no edit expected.","Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (lines ~250-290) — call `plan-start` for new plans and stamp `mode` into the lifecycle manifest it already writes.","Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC8 mode cases."]; ac=["A new one-EPIC plan follows `task → plan → main`, and the task branch","Existing active plans are inventoried and stamped","New plans default to `plan_branch` when the project's `execution.yaml` has a `gate_profiles` block, and fall back to `legacy_epic_release_mode` with a logged `plan_branch_unavailable: no_gate_profiles` otherwise (Step 7).","Missing, unknown or mixed mode exits non-zero before mutation."] -->
<!-- step-2: files=["Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add the AC9 resilience matrix.","Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — add the `AID_PLAN_FSM_CRASH_AFTER` test seam."]; ac=["An EPIC merge conflict enters `CONFLICT` and records no completion.","A pre-merge abort leaves the target branch unchanged and records","A hotfix on the target branch forces resynchronization before candidate","Failure after the final Git merge but before the queue and close update","Published rollback uses a new revert commit, never a history rewrite."] -->
<!-- step-3: files=["Modify: `plugins/aid-orchestrator/skills/pipeline.md` — replace the per-EPIC release narrative (re-grounded 2026-07-24: the `legacy_epic_release_mode` ritual is now at ~lines 1739-1883, heading ~:1821; the per-EPIC C+A dispatch model at ~:1132-1187) with the mode-conditional plan-final narrative, and correct the stale cross-plan enforcement claims (now at ~:1087 and ~:1211, not the old 1069-1070). Re-grep by heading text before editing — pipeline.md grew to ~2336 lines since the draft.","Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~290-330) — same change at command level, including PM summary options.","Modify: `.aid-o/plans/P061-gate-profiles-test-cost-reduction.md` (lines ~62-66) — amend D8 with the supersession note (workspace-local; see the durability note below).","Modify: `.aid-o/plans/P062-e10-calibration-promotion.md` (lines ~10-20) — amend the E10 precondition and the \"all 6 EPICs\" wording (workspace-local; see the durability note below).","Modify: `docs/plans/AID-control-system-v2-roadmap.md` — record the P061 D8 supersession and the P062 precondition change (workspace-local; `docs/` is gitignored, so this edit serves local readers and is not the durable assertion — see the durability note).","Modify: `docs/design/AID-control-system-v2-control-topology.md` — amend the T2 row (workspace-local, same durability caveat).","Modify: `docs/plans/AID-control-system-v2-roadmap.md` (lines ~140-160) — insert the E9.5 phase between E9 and E10.","Modify: `docs/design/AID-control-system-v2-control-topology.md` (lines ~355-370) — amend the T2 row and the dispatch budget accounting.","Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — add the remaining P064 enforcement rows.","Modify: `docs/extending-aid.md` — document the plan-boundary layer for contributors.","Create: `plugins/aid-orchestrator/scripts/tests/test-control-boundary.sh` — assert every AC11 claim mechanically, not just three greps.","Create: `plugins/aid-orchestrator/scripts/tests/fixtures/control-boundary-baseline.yaml` — the checked-in pre-P064 snapshot of every policy `enforcement:` and `head_match_policy:` value that the check compares against."]; ac=["`skills/pipeline.md` and `commands/aid-run.md` contain no instruction","The P061 D8 and P062 precondition amendments are recorded in the","The Control System v2 roadmap E9.5 entry is recorded as a tracked","The five genuinely-new rows (`plan_final_gate_required`,","`bash plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` passes."] -->
<!-- step-4: files=["Create: `plugins/aid-orchestrator/scripts/tests/test-instruction-sweep.sh` — grep denylist over agent-facing surfaces plus the inventory completeness check. The `test-` prefix is required: `run-all-tests.sh:65` discovers only `test-*.sh`, so a `*-check.sh` name would never run as a standing CI guard (§1: a detector nothing runs is decoration).","Create: `plugins/aid-orchestrator/scripts/tests/instruction-sweep-allow.txt` — reasoned `path:pattern` allowlist for legitimate mentions.","Create: `plugins/aid-orchestrator/reference/instruction-surface-inventory.md` — the surface inventory with a per-surface disposition, under `plugins/aid-orchestrator/reference/`, a non-`docs`-named tracked directory (`.gitignore:87`'s unanchored `docs/` would otherwise ignore it), so the sweep check can rely on it in CI and on a clean checkout.","Modify: `plugins/aid-orchestrator/commands/aid-plan.md` — make the plan-mode declaration and the plan-final boundary explicit where the command describes plan lifecycle.","Modify: `plugins/aid-orchestrator/commands/aid-init.md` — document the lifecycle `mode` field and the hook reinstall requirement.","Modify: `plugins/aid-orchestrator/commands/aid-status.md` — surface plan state, mode and candidate SHA alongside EPIC state.","Modify: `plugins/aid-orchestrator/commands/aid-do.md` — state that Fast Mode does not create or release a plan branch.","Modify: `plugins/aid-orchestrator/README.md` — update the lifecycle description to the plan-level model.","Modify: `README.md` — same, for the repository-level description.","Modify: `CLAUDE.md` — update the release workflow section, which currently documents a per-push release ritual.","Modify: `plugins/aid-orchestrator/skills/run-management.md` — make the plan lifecycle and `active.md` guidance mode-aware.","Modify: `plugins/aid-orchestrator/skills/agent-protocol.md` — add the agent handoff contract phrasing.","Modify: `plugins/aid-orchestrator/skills/plan-writing.md` — make the documentation-step rule and the plan lifecycle references mode-aware.","Modify: `plugins/aid-orchestrator/skills/role-cards.md` — relocate the Auditor, Curator, Simplifier and Reporter role cards to the plan-final boundary.","Modify: `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md` — record the CP3 relocation from EPIC completion to plan final.","Modify: `plugins/aid-orchestrator/commands/aid-verify-plan.md` — align the CP1 review contract with the plan-level boundary.","Modify: `plugins/aid-orchestrator/commands/aid-verify-implementation.md` — align the DONE review contract with the plan-level boundary.","Modify: `plugins/aid-orchestrator/agents/auditor.md` + `plugins/aid-orchestrator/agents/curator.md` — state that dispatch is plan-final, once per plan.","Modify: `plugins/aid-orchestrator/agents/simplifier.md` + `plugins/aid-orchestrator/agents/reporter.md` — confirm the plan-final boundary and the protocol-v2 delivery artifact.","Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (lines ~49-57) — register the new check so it runs with the suite."]; ac=["Every agent-facing surface has a disposition of `update`, `verified` or","`test-instruction-sweep.sh` exits 0 over the repository, and exits 1","Every lifecycle instruction that survives carries an explicit","The agent handoff contract is present in `skills/agent-protocol.md`","The backward compatibility statement names P061, P062, P063 and P065 as"] -->
<!-- step-5: files=["Create: `plugins/aid-orchestrator/reference/P068-plan-branch-dogfood-report.md` — the recorded end-to-end run with commands, SHAs and counts, plus the subject-selection authorization as its first section, under `plugins/aid-orchestrator/reference/`, a non-`docs`-named tracked directory (`.gitignore:87`'s unanchored `docs/` matches `plugins/aid-orchestrator/docs/` too, so the report must avoid any `docs`-named dir).","Modify: `.aid-o/config/counter.yaml` — reserve `P067` for the dogfood subject plan.","Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add the AC10 invocation-count assertions over structured logs.","Modify: `plugins/aid-orchestrator/CHANGELOG.md` — add the release entry.","Modify: `CHANGELOG.md` — identical copy of the plugin CHANGELOG entry."]; ac=["Dogfood isolation is proven, not assumed: every dogfood command runs from","The dogfood report's `## Authorization` section exists and is committed","The chosen plan meets every eligibility criterion, or","The Git hooks in `.git/hooks/` are reinstalled from the templates","At least one multi-EPIC plan completes using `plan_branch` mode, with","The Auditor, Curator, Simplifier and Reporter each ran exactly once, at","Full gates ran once, at plan final; EPIC branches merged into the plan","The structured invocation logs show every cadence count required by","The rollback drill is recorded and the target branch was never left in"] -->

## Run Breakdown

### Run 1: Phase 2
**Goal:** Turn a completed plan branch into exactly one reviewed, authorized release:
one frozen candidate, one full gate run, one pass of each specialist, one C4
decision, one PM authorization bound to exact SHAs, one compare-and-swap
merge, at most one tag (none when the plan resolves to no version bump), and
one atomic close backed by a durable lifecycle receipt.
**Deliverables:** Phase 2 of 2 from plan P068

## Hints

- expected_steps: 5
- complexity: medium
- parallelism_potential: low

## Notes

<!-- Auto-generated by aid-plan-to-epic.sh from P068-plan-final-release-boundary.md on 2026-07-25 -->
