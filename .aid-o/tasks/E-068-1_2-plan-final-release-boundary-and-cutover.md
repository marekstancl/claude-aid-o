---
status: active
plan_ref: .aid-o/plans/P068-plan-final-release-boundary.md
plan_epics_total: 2
runs_total: 1
runs_completed: 0
---

# EPIC: E-068-1_2 --- Plan-Final Release Boundary and Cutover

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

This EPIC covers Phase 1 of 2 from plan P068.

## Goal

Turn a completed plan branch into exactly one reviewed, authorized release:
one frozen candidate, one full gate run, one pass of each specialist, one C4
decision, one PM authorization bound to exact SHAs, one compare-and-swap
merge, at most one tag (none when the plan resolves to no version bump), and
one atomic close backed by a durable lifecycle receipt.

Phase 1/2 deliverables:
- Step 1: Bring the recorded target branch into the plan branch, prepare
version metadata, and freeze one immutable candidate bound to an observed
target head.
- Step 2: Run one resolved `release` profile against the frozen
candidate and produce a `gates_report.json` that proves no required gate was
excluded and no broad suite ran twice.
- Step 3: Run the C2 final review, the C3 audit, the Curator, the
Simplifier, the registered plan utilities and the Reporter exactly once each
against the frozen candidate, with every output landing outside the candidate
tree.
- Step 4: Produce one plan-mode `release-decision.json` bound to the
candidate and target SHAs, and a PM summary that can never imply an
intermediate EPIC was released.
- Step 5: Merge only the approved candidate into only the expected
target head, verify the resulting tree, and publish exactly once.
- Step 6: Make plan-close a real gate that can only pass after the merge
or a recorded abort, and that reconciles the legacy marker world with the
`.aid-lifecycle/` receipt world.


## Scope

### Allowed files/paths
- `.github/workflows/ci.yml (lines ~7-30)`
- `plugins/aid-orchestrator/defaults/schemas/delivery-gate.schema.json`
- `plugins/aid-orchestrator/defaults/schemas/plan-lifecycle-manifest.schema.json`
- `plugins/aid-orchestrator/defaults/schemas/pm-plan-decision.schema.json`
- `plugins/aid-orchestrator/defaults/schemas/release-decision.schema.json`
- `plugins/aid-orchestrator/scripts/aid-fsm.sh (lines ~4428-4522)`
- `plugins/aid-orchestrator/scripts/aid-plan-close-check.sh (lines ~440-515)`
- `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh`
- `plugins/aid-orchestrator/scripts/aid-pm-brief.sh (lines ~40-160)`
- `plugins/aid-orchestrator/scripts/aid-release-policy.sh (lines ~300-370)`
- `plugins/aid-orchestrator/scripts/aid-release-policy.sh (lines ~460-530)`
- `plugins/aid-orchestrator/scripts/aid-release-policy.sh (lines ~518-554)`
- `plugins/aid-orchestrator/scripts/aid-release.sh (lines ~26-380)`
- `plugins/aid-orchestrator/scripts/aid-release.sh (lines ~360-380)`
- `plugins/aid-orchestrator/scripts/aid-run-gates.sh (lines ~177-260)`
- `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh (lines ~242-360)`
- `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh (lines ~322-373)`
- `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh (lines ~36-50, ~470-700)`
- `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh (lines ~730-808)`
- `plugins/aid-orchestrator/scripts/lib/aid-plan-state.sh`
- `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats`
- `plugins/aid-orchestrator/scripts/tests/bats/test-c0-plan-review.bats (lines ~383)`
- `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh (lines ~49-57)`
- `plugins/aid-orchestrator/skills/pipeline.md (lines ~996-1090)`
- `plugins/aid-orchestrator/defaults/hooks/pre-push (lines ~30-50)`

### Forbidden zones
- <!-- No forbidden zones specified in plan -->

## Artifacts

- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage sync` and `--stage freeze`.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — this plan's mandatory integration suite; every later step extends it.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh` (lines ~242-360) — re-grep by symbol first; resolve plugin-relative contract paths, and refine the already-non-blocking absent-graph handling to record `plan_graph: absent_pre_generation` in place of the current opaque zero-byte seal. Absence is already non-blocking (see the CF3 re-grounding note); this step improves the semantics, it does not fix a block.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-c0-plan-review.bats` (lines ~383) — re-grep by symbol; extend the golden manifest fixture and expected `input_hash` for the `absent_pre_generation` `plan_graph` shape and the plugin-relative contract paths. The absent-graph fixture already exists — extend it, do not re-add it.
- Modify: `.github/workflows/ci.yml` (lines ~7-30) — add a `plan-final-tests` job for the new suite with its own timeout and `yq`.
- Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (lines ~49-57) — add the new suite to the dedicated-CI-job exclusion list P064 introduced.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~26-380) — restructure into subcommand dispatch and add `prepare-plan`, which edits version files without committing a tag or sweeping unrelated changes.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC1 freeze/invalidation and AC6 tag-once cases.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage gates`.
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
- Modify: `plugins/aid-orchestrator/defaults/schemas/plan-lifecycle-manifest.schema.json` — widen `declared_epics[].scope` from `[required, backlog]` to include `abandoned` and `superseded`, add a top-level `status` property (`active | closed | aborted`), and add `candidate_frozen_at` (RFC 3339 UTC string) as the authoritative freeze-time source Step 1 writes and this step validates `decided_at` against; the schema is `additionalProperties: false`, so none of the CF1 re-scope, the abort record, or the freeze timestamp can produce a valid manifest without these changes.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~730-808) — exclude the two new scopes from the closure predicate's required set.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC5 and AC6 cases.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-close-check` and the close transaction.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-close-check.sh` (lines ~440-515) — add the plan-branch checks and the receipt reconciliation.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~322-373) — give `aid_lifecycle_plan_close` and its receipt commit the same plumbing plan-mode Step 5 adds to the binding path, so the receipt is committed by `commit-tree` + CAS `update-ref` onto the target ref without a checkout — the close path must work when the target branch is checked out in another worktree.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-state.sh` — add `plan-close` to the operation-record `command` enum so the close transaction is reconcilable like every other.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~4428-4522) — make `cmd_plan_close` delegate to the plan layer for `plan_branch` plans.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC7 corruption and resume cases.


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

- [ ] [backend] A plan citing `defaults/schemas/*.json` paths that exist under
- [ ] [backend] CF3 refinement delivered, asserted on the bridge rather than on a review
- [ ] [backend] `--stage sync` refuses to proceed while any EPIC is `pending` or
- [ ] [backend] After `--stage freeze`, `candidate_sha` and
- [ ] [backend] The same freeze write records `candidate_frozen_at` as a valid RFC 3339
- [ ] [backend] A candidate change after freeze transitions the plan to `PLAN_FIX` and
- [ ] [backend] A second freeze creates `R-<plan_id>-final-2` and leaves
- [ ] [backend] Target-branch advance between sync and freeze returns the plan to
- [ ] [qa] The plan-final `gates_report.json` carries the resolved release-derived
- [ ] [qa] No gate that is `required: true` or plan-declared appears in
- [ ] [qa] No quarantined gate (`bats_all` — the only one at v2.62.1) is reported
- [ ] [qa] Every quarantined gate satisfied by a substitute has a matching
- [ ] [qa] Exactly one `gate_runner_start` event exists for the plan-final run —
- [ ] [qa] `plan_diff` runs for real against the plan file and the candidate range —
- [ ] [qa] A `result: skip` on any non-quarantined gate that is `required: true`
- [ ] [qa] Existing EPIC-scoped `aid-run-gates.sh` callers are unaffected when the
- [ ] [architect] The C2 final review's recorded range covers a defect seeded in the
- [ ] [architect] Auditor, Curator, Simplifier and Reporter each dispatch exactly once on
- [ ] [architect] A missing, stale, wrong-plan or wrong-candidate output cannot satisfy
- [ ] [architect] The plan-final run contains `review-profile.json`, `delivery-gate.json`
- [ ] [architect] A full review pass leaves `candidate_sha` and the product worktree
- [ ] [architect] An accepted fix that changes the candidate transitions to `PLAN_FIX`
- [ ] [backend] Every plan-mode input names the plan id, run id, candidate SHA, target
- [ ] [backend] C4 consumes the run-scoped `delivery-report.json`, not a committed
- [ ] [backend] Passing an EPIC evidence directory, or a copy of a valid EPIC pack
- [ ] [backend] A retry writes `R-<plan_id>-final-2` and leaves run 1 untouched.
- [ ] [backend] The PM summary distinguishes reviewed candidate, approved target, final
- [ ] [backend] Missing, `FIX`, `ABORT`, stale, malformed, wrong-plan, wrong-candidate
- [ ] [backend] A decision artifact that fails `pm-plan-decision.schema.json`, or whose
- [ ] [backend] The freeze-time validation is fail-closed on every degenerate input: a
- [ ] [backend] A concurrent target-branch advance loses the compare-and-swap and
- [ ] [backend] The merge commit is built without moving any ref; a failed
- [ ] [backend] The lifecycle commit advances the target ref by plumbing after the
- [ ] [backend] No intermediate EPIC creates a version commit or tag. A plan with a
- [ ] [backend] Resume after each transaction boundary creates no duplicate merge,
- [ ] [backend] Pushing `plan/*` or `task/*` with `feat:`/`fix:` commits and no
- [ ] [backend] Every abandoned or superseded EPIC is re-scoped in the lifecycle
- [ ] [backend] After the merge, every non-abandoned EPIC has a `delivery_sha` binding
- [ ] [backend] Individually removing or corrupting EPIC ancestry, the manifest, the
- [ ] [backend] Unknown ancestry blocks rather than passing.
- [ ] [backend] Re-running after a simulated crash reconciles state and writes exactly
- [ ] [backend] A plan whose `.lock` sidecar files exist but are not held closes
- [ ] [backend] The owned-lock exception holds: close succeeds while the close
- [ ] [backend] `plan-close-complete` is absent until the final merge or a recorded
- [ ] [backend] A committed `.aid-lifecycle` receipt is present after close for every


## Dependencies

### Internal (same plan)
<!-- First phase --- no internal dependencies -->

### External (other plans/EPICs)
<!-- No external dependencies -->

### Queue Implications
depends_on: []

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | backend | Bring the recorded target branch into the plan branch, prepare version metadata, and freeze one i... | --- | --- |
| 2 | qa | Run one resolved `release` profile against the frozen candidate and produce a `gates_report.json`... | --- | --- |
| 3 | architect | Run the C2 final review, the C3 audit, the Curator, the Simplifier, the registered plan utilities... | 1, 2 | --- |
| 4 | backend | Produce one plan-mode `release-decision.json` bound to the candidate and target SHAs, and a PM su... | 2, 3 | --- |
| 5 | backend | Merge only the approved candidate into only the expected target head, verify the resulting tree, ... | 4 | --- |
| 6 | backend | Make plan-close a real gate that can only pass after the merge or a recorded abort, and that reco... | 5 | --- |


## Step UI Contracts

<!-- No ui_change_mode fields in this plan -->
<!-- step-1: files=["Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage sync` and `--stage freeze`.","Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — this plan's mandatory integration suite; every later step extends it.","Modify: `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh` (lines ~242-360) — re-grep by symbol first; resolve plugin-relative contract paths, and refine the already-non-blocking absent-graph handling to record `plan_graph: absent_pre_generation` in place of the current opaque zero-byte seal. Absence is already non-blocking (see the CF3 re-grounding note); this step improves the semantics, it does not fix a block.","Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-c0-plan-review.bats` (lines ~383) — re-grep by symbol; extend the golden manifest fixture and expected `input_hash` for the `absent_pre_generation` `plan_graph` shape and the plugin-relative contract paths. The absent-graph fixture already exists — extend it, do not re-add it.","Modify: `.github/workflows/ci.yml` (lines ~7-30) — add a `plan-final-tests` job for the new suite with its own timeout and `yq`.","Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (lines ~49-57) — add the new suite to the dedicated-CI-job exclusion list P064 introduced.","Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~26-380) — restructure into subcommand dispatch and add `prepare-plan`, which edits version files without committing a tag or sweeping unrelated changes.","Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC1 freeze/invalidation and AC6 tag-once cases."]; ac=["A plan citing `defaults/schemas/*.json` paths that exist under","CF3 refinement delivered, asserted on the bridge rather than on a review","`--stage sync` refuses to proceed while any EPIC is `pending` or","After `--stage freeze`, `candidate_sha` and","The same freeze write records `candidate_frozen_at` as a valid RFC 3339","A candidate change after freeze transitions the plan to `PLAN_FIX` and","A second freeze creates `R-<plan_id>-final-2` and leaves","Target-branch advance between sync and freeze returns the plan to"] -->
<!-- step-2: files=["Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage gates`.","Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (lines ~177-260) — add the additive `--base-commit` and `--plan-path` flags so a plan-final run can supply the substitution tokens an EPIC state file would otherwise provide.","Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC2 gate-report assertions."]; ac=["The plan-final `gates_report.json` carries the resolved release-derived","No gate that is `required: true` or plan-declared appears in","No quarantined gate (`bats_all` — the only one at v2.62.1) is reported","Every quarantined gate satisfied by a substitute has a matching","Exactly one `gate_runner_start` event exists for the plan-final run —","`plan_diff` runs for real against the plan file and the candidate range —","A `result: skip` on any non-quarantined gate that is `required: true`","Existing EPIC-scoped `aid-run-gates.sh` callers are unaffected when the"] -->
<!-- step-3: files=["Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage review`, including the required-output contract and the invalidation trigger.","Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~996-1090) — rewrite the DONE closure checklist and the C+A execution model for the plan-final boundary.","Modify: `plugins/aid-orchestrator/defaults/schemas/delivery-gate.schema.json` — allow `identity.epic_id` to be string-or-null so the plan-level aggregate (`epic_id: null`, `plan_id` set) is schema-valid; today it requires a string.","Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC3 dispatch-count and invalidation cases."]; ac=["The C2 final review's recorded range covers a defect seeded in the","Auditor, Curator, Simplifier and Reporter each dispatch exactly once on","A missing, stale, wrong-plan or wrong-candidate output cannot satisfy","The plan-final run contains `review-profile.json`, `delivery-gate.json`","A full review pass leaves `candidate_sha` and the product worktree","An accepted fix that changes the candidate transitions to `PLAN_FIX`"] -->
<!-- step-4: files=["Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~460-530) — add the flag-driven plan mode alongside the untouched positional EPIC mode.","Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~300-370) — make `compute_reporter` and `compute_simplifier` plan-boundary-aware instead of gating on the EPIC `ca-review-complete` marker.","Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~518-554) — resolve the `plan_review` input from the plan's own C0 review in plan mode instead of from `epic_input.md` frontmatter.","Modify: `plugins/aid-orchestrator/defaults/schemas/release-decision.schema.json` — widen the `blockers[].input_id` enum for plan-mode inputs and per-EPIC roll-up blockers.","Modify: `plugins/aid-orchestrator/scripts/aid-pm-brief.sh` (lines ~40-160) — render a plan-level brief from a plan-mode decision.","Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage c4` and `--stage summary`.","Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC4 identity cases."]; ac=["Every plan-mode input names the plan id, run id, candidate SHA, target","C4 consumes the run-scoped `delivery-report.json`, not a committed","Passing an EPIC evidence directory, or a copy of a valid EPIC pack","A retry writes `R-<plan_id>-final-2` and leaves run 1 untouched.","The PM summary distinguishes reviewed candidate, approved target, final"] -->
<!-- step-5: files=["Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-merge-to-main`.","Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~360-380) — add the `tag-plan` subcommand and make tagging idempotent.","Modify: `plugins/aid-orchestrator/defaults/hooks/pre-push` (lines ~30-50) — exempt `plan/*` and `task/*` branches from the version-bump push block.","Create: `plugins/aid-orchestrator/defaults/schemas/pm-plan-decision.schema.json` — the PM authorization contract validated before any merge action.","Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~36-50, ~470-700) — teach the five binding-path functions a plan-mode that advances the target ref by plumbing (`commit-tree` + CAS `update-ref`) instead of requiring a checkout, so delivery bindings and the receipt commit in one post-merge pass even when the target branch is checked out in another worktree.","Modify: `plugins/aid-orchestrator/defaults/schemas/plan-lifecycle-manifest.schema.json` — widen `declared_epics[].scope` from `[required, backlog]` to include `abandoned` and `superseded`, add a top-level `status` property (`active | closed | aborted`), and add `candidate_frozen_at` (RFC 3339 UTC string) as the authoritative freeze-time source Step 1 writes and this step validates `decided_at` against; the schema is `additionalProperties: false`, so none of the CF1 re-scope, the abort record, or the freeze timestamp can produce a valid manifest without these changes.","Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~730-808) — exclude the two new scopes from the closure predicate's required set.","Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC5 and AC6 cases."]; ac=["Missing, `FIX`, `ABORT`, stale, malformed, wrong-plan, wrong-candidate","A decision artifact that fails `pm-plan-decision.schema.json`, or whose","The freeze-time validation is fail-closed on every degenerate input: a","A concurrent target-branch advance loses the compare-and-swap and","The merge commit is built without moving any ref; a failed","The lifecycle commit advances the target ref by plumbing after the","No intermediate EPIC creates a version commit or tag. A plan with a","Resume after each transaction boundary creates no duplicate merge,","Pushing `plan/*` or `task/*` with `feat:`/`fix:` commits and no","Every abandoned or superseded EPIC is re-scoped in the lifecycle","After the merge, every non-abandoned EPIC has a `delivery_sha` binding"] -->
<!-- step-6: files=["Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-close-check` and the close transaction.","Modify: `plugins/aid-orchestrator/scripts/aid-plan-close-check.sh` (lines ~440-515) — add the plan-branch checks and the receipt reconciliation.","Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~322-373) — give `aid_lifecycle_plan_close` and its receipt commit the same plumbing plan-mode Step 5 adds to the binding path, so the receipt is committed by `commit-tree` + CAS `update-ref` onto the target ref without a checkout — the close path must work when the target branch is checked out in another worktree.","Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-state.sh` — add `plan-close` to the operation-record `command` enum so the close transaction is reconcilable like every other.","Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~4428-4522) — make `cmd_plan_close` delegate to the plan layer for `plan_branch` plans.","Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC7 corruption and resume cases."]; ac=["Individually removing or corrupting EPIC ancestry, the manifest, the","Unknown ancestry blocks rather than passing.","Re-running after a simulated crash reconciles state and writes exactly","A plan whose `.lock` sidecar files exist but are not held closes","The owned-lock exception holds: close succeeds while the close","`plan-close-complete` is absent until the final merge or a recorded","A committed `.aid-lifecycle` receipt is present after close for every"] -->

## Run Breakdown

### Run 1: Phase 1
**Goal:** Turn a completed plan branch into exactly one reviewed, authorized release:
one frozen candidate, one full gate run, one pass of each specialist, one C4
decision, one PM authorization bound to exact SHAs, one compare-and-swap
merge, at most one tag (none when the plan resolves to no version bump), and
one atomic close backed by a durable lifecycle receipt.
**Deliverables:** Phase 1 of 2 from plan P068

## Hints

- expected_steps: 6
- complexity: medium
- parallelism_potential: low

## Notes

<!-- Auto-generated by aid-plan-to-epic.sh from P068-plan-final-release-boundary.md on 2026-07-24 -->
