---
id: P068
type: regular
status: draft
created: 2026-07-20
author: PM + AI
---

# Plan: Plan-Final Release Boundary and Cutover

## Plan Type

This plan is type: `regular`. It is the **second of two plans** derived from
`docs/plans/AID-plan-level-release-boundary-roadmap.md` (PM-approved
2026-07-12).

The roadmap was first written as one 20-step plan. Seven cross-provider
reviews each found real HIGH defects in it, several introduced by the
previous round's own fixes — the signal was not a fixed bug count but a
document too large for one review pass to ground end to end. PM decision
(2026-07-20): split along the dependency direction.

- **P064 — Plan Branch Substrate and EPIC Integration** (steps 1-9):
  produces every shared contract — parent plan FSM, locks, durable operation
  record, plan boundary manifest, branch lineage, EPIC-to-plan merge,
  plan-aware queue, boundary-split gate profiles, and the silencing of the
  per-EPIC release stack. At its end, EPICs flow into `plan/Pxxx` and nothing
  is released.
- **P068 (this plan)** — steps 10-20 of the original, renumbered 1-11:
  everything that turns a plan branch into a release candidate and gets it
  safely into the target branch.

P068 consumes P064's contracts and produces no new shared contract flowing
backwards.

**This plan was authored while P064 was still landing**, which is an execution
precondition, not a reviewing instruction: P064 is now DONE and merged, and every
artifact this plan consumes exists at v2.62.1. P064's EPIC 1 delivers the
substrate incrementally, so at any given review some artifacts already exist
(`lib/aid-plan-manifest.sh`, `lib/aid-lock.sh`,
`test-aid-plan-release-boundary.bats`) while others do not yet
(`aid-plan-fsm.sh`, `lib/aid-queue-write.sh`). Until P064 is DONE and merged,
the full set of contracts this plan consumes is not verifiable against real
code, and a review will accurately report whichever pieces are still absent.
`## Next Steps` therefore requires a full re-grounding pass against the
post-P064 tree before EPIC generation, and P068 must not execute until P064
is DONE and merged. Nothing here asks a reviewer to treat an absent artifact
as satisfied. It must not start until P064 is DONE and merged, so its acceptance
criteria can be grounded against functions that exist rather than promised
ones.

This plan file carries no `mode:` key. Plan mode is declared in the
git-tracked lifecycle manifest `.aid-lifecycle/manifests/<plan_id>.yaml`,
never in `.aid-o/plans/**` — that tree is intentionally gitignored
(`.gitignore:95-98`) and `git ls-files .aid-o/` returns nothing, so nothing
under it can be durable authority.

## Stakeholder Brief

P064 made `plan/Pxxx` the place EPICs land. This plan makes that branch
releasable. It takes a plan whose EPICs are all merged, synchronises the
target branch into it, prepares the version and changelog, and freezes one
immutable candidate commit. Against exactly that commit it runs one full gate
profile, one plan-level semantic review, one independent audit, the Curator,
the Simplifier and the Reporter — each once, for the whole plan rather than
once per EPIC — then asks C4 for a release decision and the PM for an
authorization bound to that exact candidate and target head. Only then does a
compare-and-swap merge move the target branch, create one tag, push once, and
close the plan with a durable lifecycle receipt. It also performs the
cutover: stamping in-flight plans as legacy, flipping the default for new
plans, sweeping every agent-facing instruction so no obsolete per-EPIC
release text survives, and proving the whole path on a real dogfood run. The
main risks are that any fix during review invalidates the frozen candidate
and restarts the cycle, and that the target branch can move while the PM is
deciding — both are handled by binding every artifact to an exact SHA and by
a merge that loses rather than forces when reality has changed.

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

## Goal

Turn a completed plan branch into exactly one reviewed, authorized release:
one frozen candidate, one full gate run, one pass of each specialist, one C4
decision, one PM authorization bound to exact SHAs, one compare-and-swap
merge, at most one tag (none when the plan resolves to no version bump), and
one atomic close backed by a durable lifecycle receipt.

## Scope

### In scope

- `plan-finalize` with its stages: target synchronization, version and
  changelog preparation, candidate freeze, immutable run allocation.
- Exactly one resolved `release` gate profile run against the frozen
  candidate, with explicit plan-final inputs to the gate runner.
- Plan-level review orchestration: C2 final review over
  `plan_base_commit..candidate_sha`, C3 audit, Curator, Simplifier, Reporter,
  and any registered plan-boundary utility — each once, with `PLAN_FIX`
  invalidation when a fix changes the candidate.
- Plan-mode C4 (`aid-release-policy.sh --plan …`) with identity binding, plus
  the plan-level PM summary and decision file.
- `plan-merge-to-main`: compare-and-swap merge, tree verification, lifecycle
  delivery bindings in one pass, one tag, one push.
- Plan-close as a real mechanical gate, with split
  `plan-review-complete` / `plan-close-complete` markers and the bridge to
  the `.aid-lifecycle/` receipt world.
- Crash, conflict, hotfix and abort resilience across every transaction
  boundary this plan adds.
- Cutover: in-flight inventory, the default mode flip to `plan_branch`, and
  the `defaults/hooks/pre-push` exemption.
- Documentation and amendments: `skills/pipeline.md`, `commands/aid-run.md`,
  P061 D8, P062 preconditions, the Control System v2 roadmap E9.5 entry, the
  control topology T2 row, and the enforcement registry rows for the
  mechanisms this plan builds.
- The agent-facing instruction sweep with its inventory, denylist and
  allowlist.
- One end-to-end dogfood on a real multi-EPIC plan whose payload changes
  tracked files.

### Out of scope

- Everything P064 delivers. This plan modifies none of P064's contracts; if a
  contract turns out to be wrong, that is a P064 defect fixed there, not
  worked around here.
- Cross-plan train releases, multi-plan batching, partial deploy channels,
  advanced protected-branch integration and automatic rollback orchestration
  (roadmap D4).
- Mid-plan migration of an in-flight plan (roadmap D11).
- Promotion of any C0-C4 finding from `observe`/`dual_run` to `blocking`,
  including today's `head_match: unknown`. That authority stays with E10
  (roadmap D10). The exception is P064/P068-owned identity — candidate,
  target and manifest binding — which hard-blocks regardless of policy mode.
- Deletion of any legacy check. This plan relocates; E11 removes (roadmap D5).

## Carried Findings — Open Input, Not Settled Work

Three findings from the C0 cross-provider reviews of the original combined
plan land here unresolved. They are inputs to this plan's design, and each
must be closed by a named step before P068 is considered complete.

**CF1 — `epic-complete --abandon` has no executable lifecycle path.**
An abandoned or superseded EPIC must be re-scoped in the git-tracked
lifecycle manifest, because `aid_plan_closure_state`
(`lib/aid-lifecycle.sh:774-808`) requires every `scope: required` entry to
carry a delivery binding and an accepted review — an abandoned EPIC will
never have either, so leaving it `required` pins the plan at `active` forever
and the mandatory receipt can never be written. But
`_aid_lc_require_target_branch` (`lib/aid-lifecycle.sh:36-50`) refuses every
lifecycle write unless HEAD is the target branch, and `epic-complete` runs on
a task branch. P064 therefore records abandonment in the runtime manifest
only. This plan must define the executable path — a deferred re-scope applied
during `plan-merge-to-main`, or an explicit target-branch handoff — and prove
it atomic with the runtime state update.

**CF2 — the dogfood payload must change tracked files.**
An earlier design used `.aid-o/plans/**` as the dogfood payload. That tree is
gitignored, so the run could never demonstrate a merge, a release commit, a
tag or a close: there would be nothing tracked to merge, and a no-bump
preparation creates no commit at all. The dogfood subject must make a real,
small, tracked change under `plugins/aid-orchestrator/` — a fixture, doc or
test-only change that requires a normal commit, release, tag and close. It
must not be a pending real fix that should not wait for this plan.

**CF3 — `plan-graph.json` is required by C0 but cannot exist pre-generation.**
The C0 plan review seals `.aid-o/work/evidence/<plan_id>/c0/plan-graph.json`
as an input and treats its absence as blocking, but the graph is produced by
`aid-c0-contract.sh contract <plan.json>` and `plan.json` only exists after
EPIC generation. Six consecutive C0 runs on the combined plan returned
`unverifiable` for this reason alone. This plan must either declare the graph
optional at plan-review time or generate it from the plan document, and the
fix belongs to the C0 bridge rather than to any consumer of it.

> **Re-grounding note (2026-07-24, revised after C0).** Observed repository state,
> stated declaratively — this note prescribes no review treatment and cannot relax
> any mandatory C0 input or dependency check:
>
> - `_c0_manifest_entry` (`lib/aid-c0-plan-review.sh:~242`) seals an absent input
>   as a zero-byte manifest entry (empty-string sha256, size 0) rather than
>   failing; `test-c0-plan-review.bats` carries an absent-graph fixture.
> - **No `plan-graph.json` producer exists at plan-review time, and no step of this
>   plan creates one.** The graph is produced by `aid-c0-contract.sh` from
>   `plan.json`, which exists only after EPIC generation. Consequently the
>   graph-based acyclicity / output-producer analysis has no graph artifact to run
>   over. That is a **C0-input-contract gap owned by the C0 bridge (P065), not by
>   P068**; it is recorded in the backlog and is not claimed to be resolved here.
> - Step 1's scope regarding the bridge is therefore limited to: (a) plugin-relative
>   contract-path resolution (`lib/aid-c0-plan-review.sh:~305-308`), and (b)
>   recording `plan_graph: absent_pre_generation` in place of the opaque zero-byte
>   seal, so an unproduced graph is distinguishable from a truncated one. The
>   absent-graph fixture is extended, not re-added.

## Handoff carried into P068 from P064 / Phase 1 (2026-07-24)

These are open inputs the re-grounding carries forward. They are not settled
work of this plan unless a named step owns them.

- **IMP-266 — Option B is RATIFIED (2026-07-24).** `merged_to_plan` is
  deliberately terminal and is NEVER reversed in place. P068 must not assume,
  add, or rely on any in-tool reopen of `merged_to_plan`. An incorrect entry is
  corrected by the documented, PM-authorized recovery ceremony
  (`docs/plans/2026-07-24-IMP-266-merged-to-plan-recovery-CEREMONY.md`): a new corrective
  EPIC and/or the non-destructive `plan-state --repair` + `--attest-source-ref`
  path, recorded in the git-tracked lifecycle manifest and op log. **CF1**
  (abandoned/superseded EPIC lifecycle path) and Step 6's close/abort design must
  compose with this ceremony, not with any reverse transition.
- **Local evidence trust boundary.** Every fail-closed check P068 builds on (step
  binding, C3 ac_source/receipt, waiver, candidate/target SHA binding) is a
  **consistency check within the local AID trust model** — it proves an artifact
  is internally consistent with its named command, reviewed HEAD, and named
  log/plan location. It is NOT cryptographic provenance against an actor who can
  directly edit the evidence files (plan.json, verify files, receipts, the
  manifest); such an actor is out of scope. P068's acceptance language must claim
  consistency, not tamper-proof provenance.
- **Phase-1 fail-closed boundaries (v2.62.1) are the substrate P068 sits on:**
  increment-step strict-by-default binding (IMP-263), C3 canonical AC-source +
  named-log receipt (IMP-269), waiver re-validation with no current-HEAD fallback
  (IMP-270), cancel-before-PID job handshake (IMP-262), fail-closed
  lineage/attestation (IMP-265/258/267), read-time freshness (IMP-264). Every
  P068 reference must match these contracts, not the pre-hardening ones.
- **git-identity remedy is a push-time decision, NOT a P068 blocker.** 38 pre-fix
  local commits carry the wrong Git identity; whether to rewrite them is deferred
  to push time and does not block P068 locally. P068 stays on local `main`;
  nothing here is pushed.

## Architecture

### What this plan adds

Every component below is either new, or an extension of something P064
created. Nothing here redefines a P064 contract.

- **`scripts/aid-plan-fsm.sh`** *(extended)* — gains `plan-finalize`,
  `plan-merge-to-main`, `plan-close-check` and `inventory`. P064 created the
  script, its dispatch, `plan-state` and the four EPIC-facing commands.
- **`scripts/aid-release-policy.sh`** *(extended)* — gains a flag-driven plan
  mode beside the untouched positional EPIC mode
  (`aid-release-policy.sh:9,466-477`), rolling up per-EPIC inputs and reading
  the plan-final run directory instead of deriving a plan number from an EPIC
  id (`:309-318`).
- **`scripts/aid-release.sh`** *(restructured)* — gains subcommand dispatch
  plus `prepare-plan` and `tag-plan`, so version preparation and publication
  are separate transactions. It has no `main()` today: `BUMP_TYPE` comes from
  `${1:?}` at `:28` and the whole body runs at source time.
- **`scripts/aid-run-gates.sh`** *(extended)* — gains additive
  `--base-commit` and `--plan-path` flags. Without them a plan-final run
  supplies neither substitution token, `plan_diff` receives `--plan null`,
  takes its Fast Mode skip at `aid-plan-diff.sh:51-72`, and the single
  release gate run for the whole plan verifies nothing.
- **`scripts/aid-pm-brief.sh`** *(extended)* — renders a plan-level brief
  from a plan-mode decision.
- **`scripts/aid-plan-close-check.sh`** *(extended)* — gains the plan-branch
  checks and the receipt reconciliation.
- **`scripts/aid-fsm.sh`** *(one seam)* — `cmd_plan_close` at `:4428-4522`
  delegates to the plan layer for `plan_branch` plans. P064 owns the other
  five seams.
- **`defaults/hooks/pre-push`** *(exempted)* — the branch-agnostic
  version-bump guard blocks any push carrying `feat:` or `fix:` commits since
  the last tag with no `release:` commit (`pre-push:36-49`). A plan branch
  accumulates exactly that by design until the candidate freeze, so `plan/*`
  and `task/*` need an exemption. This is a different file from
  `defaults/hooks/pre-commit`, whose governance block already no-ops on
  `plan/*`.
- **New checks** — `scripts/tests/test-instruction-sweep.sh` with its
  allowlist, and `scripts/tests/test-control-boundary.sh` with its baseline
  fixture.

### The plan-final cycle

```text
plan-finalize P068
  → acquire plan lock                              [PLAN_SYNC]
  → verify every EPIC merged (ancestry, not bookkeeping)
  → merge recorded target branch into plan/Pxxx
  → prepare version + CHANGELOG on plan/Pxxx
  → freeze candidate_sha + target_head_sha
  → open immutable run dir R-Pxxx-final-N          [PLAN_GATES]
  → run exactly one resolved `release` profile
  → C2 final review over plan_base_commit..candidate_sha
  → C3 audit, Curator, Simplifier, utilities       [PLAN_REVIEW]
  → any candidate-changing fix                     → [PLAN_FIX] → refreeze
  → Reporter (last, after the final non-mutating pass)
  → plan-mode C4 + relocated legacy release checks
  → PM plan-final summary                          [AWAITING_PM]

plan-merge-to-main P068
  → verify PM decision binds candidate_sha + target_head_sha
  → compare-and-swap merge into the target branch  [PLAN_MERGING]
  → verify tree, write lifecycle bindings, tag once, push once
  → close marker only after the receipt commits    [CLOSED]
```

The plan state machine, its transition table and the operation record are
P064's; this plan drives them through the states from `PLAN_SYNC` onward.

## API Design

### `aid-plan-fsm.sh` — subcommands added by this plan

P064 creates the script, its dispatch and the four EPIC-facing commands. This
plan adds the release half. All accept `--project-root <path>` and `--op-id
<id>`, all are idempotent, and all use P064's exit-code contract extended with two
values this plan adds: `0` success or already-converged, `1` precondition
failure, `2` usage, `3` lock not acquired, `4` Git conflict, `5` state/Git
divergence needing manual reconciliation, `7` review outputs not yet present
(`plan-finalize --stage review` blocks the controller, which dispatches the
agents and re-runs the stage), and `99` the test-only crash seam
(`AID_PLAN_FSM_CRASH_AFTER`, never reachable without that variable). The
controller treats `7` as "dispatch and retry", not as failure.

```bash
aid-plan-fsm.sh plan-finalize <plan_id> [--stage sync|freeze|gates|review|c4|summary] [--resume]
aid-plan-fsm.sh plan-merge-to-main <plan_id> --decision-file <path>
aid-plan-fsm.sh plan-close-check <plan_id>
aid-plan-fsm.sh inventory [--apply]
```

`plan-finalize` without `--stage` runs the stages in order and stops at the
first that cannot complete, printing which one and why. Stage 7 (`awaiting
PM`) is not a stage: the runner exits after `summary` and only
`plan-merge-to-main` resumes the transaction.

### `aid-release-policy.sh` — plan mode

The positional EPIC mode (`<epic_id> <run_id> [--out <path>]`,
`aid-release-policy.sh:9,466-477`) is untouched. Plan mode is selected by
`--plan`:

```bash
aid-release-policy.sh --plan <plan_id> \
  --run <plan_final_run_id> \
  --candidate-sha <sha> \
  --target-ref <branch> \
  --target-head-sha <sha> \
  --evidence-dir .aid-o/work/evidence/<plan_id>/<plan_final_run_id>
```

Missing any of those flags in plan mode is a usage error (exit 2).

### `aid-release.sh` — plan-aware subcommands

```bash
aid-release.sh prepare-plan <plan_id> --bump auto|patch|minor|major --plan-branch plan/<plan_id> [--dry-run]
aid-release.sh tag-plan <plan_id> --merge-sha <sha> --version <X.Y.Z>
```

`prepare-plan` edits version files and the CHANGELOG on the plan branch and
exits without tagging or pushing, staging only the explicit version-file list
— never `git add -u`. It must **not** run `aid-release.sh`'s existing Layer-2
FSM guard (`aid-release.sh:91-115`), which scans every evidence dir for an
EXECUTE/GATES/READY run and exits 1: in `plan_branch` mode a plan-final run
legitimately coexists with EPIC runs in various states, and no EPIC reaches
`done_phase: release` because the release moved to the plan. `prepare-plan`
runs its own gate instead — it requires the plan to be in `PLAN_SYNC` with
every EPIC merged and the target branch synchronised (the manifest state
after Step 1's sync stage) — and skips the EPIC-scoped guard. It cannot
require a frozen `candidate_sha`, because the freeze happens *after*
`prepare-plan`: the version commit `prepare-plan` makes on the plan branch is
part of the candidate, so the candidate is frozen at the plan branch head
that `prepare-plan` produced, not before it. The legacy
`auto|patch|minor|major` entry point keeps that guard unchanged. `tag-plan` is idempotent: an existing tag pointing at
`--merge-sha` exits 0; one pointing elsewhere exits 1.

### `aid-run-gates.sh` — plan-final inputs

Two additive flags, so a plan-final run can supply the substitution tokens an
EPIC state file would otherwise provide:

```bash
aid-run-gates.sh run-all <execution_yaml> <plan_id> <plan_final_run_id> \
  --report-file <path> --profile release \
  --base-commit <plan_base_commit> --plan-path <abs path to plan file>
```

Absent both flags the runner falls back to `--state-file` exactly as today,
so every existing caller is unaffected.

### PM decision artifact — validated, not ad-hoc

`plan-merge-to-main` requires a PM authorization artifact; nothing else
authorizes a merge, so it gets the same contract discipline as every other
release-critical input.

- **Canonical path:**
  `.aid-o/work/evidence/<plan_id>/<plan_final_run_id>/pm-plan-decision.json`
  — inside the immutable plan-final run, so an authorization can never be
  reused across runs or attempts.
- **Schema:** `defaults/schemas/pm-plan-decision.schema.json`, created by
  Step 5, `additionalProperties: false`, every field below required. It is
  deliberately distinct from `pm-decision-brief.schema.json`, which describes
  a *generated brief* — an output of the machinery — whereas this is a *human
  authorization* consumed by it.
- **Producer:** written by the PM, or by the controller transcribing an
  explicit PM decision. Never by `plan-finalize`: a run that produced its own
  authorization would be authorizing itself.
- **Validation:** `plan-merge-to-main` validates against the schema before any
  Git action and exits 1 on failure, naming the offending field.

```json
{
  "plan_id": "P0xx",
  "plan_final_run_id": "R-P0xx-final-1",
  "decision": "MERGE",
  "candidate_sha": "<40-hex>",
  "target_ref": "main",
  "target_head_sha": "<40-hex>",
  "decided_at": "2026-07-20T10:00:00Z",
  "decided_by": "PM"
}
```

`decision` is one of `MERGE`, `FIX`, `ABORT`. Any mismatch between the
artifact's `candidate_sha`/`target_head_sha` and observed reality exits 1 with
the target branch unchanged. `decided_at` must be no earlier than the candidate
freeze — an authorization predating the candidate it claims to approve is
rejected.

**Authoritative freeze-time source (added 2026-07-24 after C0 HIGH).** The draft
validated `decided_at` against "the candidate freeze recorded in the manifest",
but no such timestamp existed in the plan-boundary manifest schema and no step
wrote one, so the check was unimplementable as specified. One authoritative
source is now defined: **Step 1's freeze stage writes `candidate_frozen_at`
(RFC 3339 UTC) into the RUNTIME plan-boundary manifest atomically, in the same
write that sets `candidate_sha`** (owned by `lib/aid-plan-manifest.sh`, declared in
`plan-boundary-manifest.schema.json`), and Step 5 reads exactly that runtime field
— not the `.aid-lifecycle` manifest, which is a separate artifact that cannot
establish atomicity with the candidate write. Validation rules, all fail-closed:
`candidate_frozen_at` absent or not a valid RFC 3339 UTC timestamp → exit 1
(never "assume old enough"); `decided_at` malformed → exit 1;
`decided_at < candidate_frozen_at` → exit 1 with the target branch unchanged. A
freeze that rewrites `candidate_sha` (a `PLAN_FIX` refreeze) rewrites
`candidate_frozen_at` in the same atomic write, so a decision authorising the
previous candidate can never satisfy the new one.

**Non-merge decisions clear the candidate before leaving the state.** A `FIX`
transitions to `PLAN_FIX` and a stale-authorization advance transitions to
`PLAN_SYNC`; both call `plan_final_invalidate` first with their target state (`PLAN_FIX` or `PLAN_SYNC`), because P064's data
model forbids a non-null `candidate_sha` outside
`PLAN_GATES|PLAN_REVIEW|AWAITING_PM|PLAN_MERGING|CLOSED`, so a candidate
carried into `PLAN_FIX` or `PLAN_SYNC` would be a schema-invalid manifest. An
`ABORT` reads the candidate into the abort record first (below), then
transitions to `ABORTED` with the candidate cleared. So no non-merge branch
leaves a candidate stranded in an illegal state.

## Artifact Ownership Rule

Every artifact this plan promises falls into exactly one of three classes,
and the class determines what the plan must declare. This rule exists because
the C0 cross-provider review repeatedly found artifacts promised in prose
with no owning step — a class of defect, not a set of instances.

| Class | Definition | What the plan must declare |
|---|---|---|
| **Authored** | A file P064 writes into the repository: script, library, schema, fixture, policy, allowlist, CI job, test | A `Create:` or `Modify:` Files entry in exactly one owning step, and a step-level acceptance criterion |
| **Runtime** | A file produced when the machinery runs: the plan manifest, plan state, operation record, plan-final evidence, gate report, review artifacts, release decision, markers, the lifecycle manifest and receipt | No Files entry — it does not exist at authoring time. Its shape is specified in `## Data Model` or `## API Design`, and a step-level AC asserts the producing command emits it |
| **Referenced** | A file that already exists and P064 only reads: `defaults/policies/*.yaml`, the existing bats suites, `.aid-o/config/policies/release-policy.yaml`, `lib/aid-gate-runtime-baseline.sh` | No Files entry. Cited with `file:line` where a claim is made about its behaviour |

A step may not introduce an authored artifact in prose alone. If a later
revision names a new script or fixture, it gets a Files entry in the same
edit or it does not belong in the plan.

## Test Execution Cadence and Quarantine (re-grounded 2026-07-24, v2.62.1)

This section is binding on every step that runs gates or tests. It reflects the
state of the suite at v2.62.1, not the pre-P064 assumptions the draft was first
written against (2026-07-20, before the 2026-07-23 quarantine and Phase 1).

### Quarantine — `bats_all` only (corrected 2026-07-24 after C0)

**Exactly one gate carries a declared quarantine: `bats_all`.** In
`.aid-o/config/execution.yaml` it has a real `quarantine:` block
(`enabled: true`, `authorized_by: "PM 2026-07-23"`, `tracked_by: "P066"`), its
command is replaced with a fail-fast (`exit 86`), and it stays `required: true`
so an automatic full/release run fails fast instead of silently treating it as a
pass. The quarantine is interim, until the P066 test-audit/scheduler work.

**`plan_diff` is NOT quarantined.** It carries no `quarantine:` block: it is an
ordinary deterministic gate, `required: false` in `execution.yaml`, whose
`pass_criteria` accepts exit 0 or the exit-2 Fast-Mode skip. The
`timeout_policy_block` it hit during E-064-2_2 was a *runtime outcome of that
run*, not a declared quarantine. This plan therefore treats `plan_diff` as an
ordinary release gate that Step 2 additionally makes plan-required, and
`--plan-path` is what makes its evaluation real. (An earlier draft of this
section wrongly generalised both gates as quarantined; the C0 review caught it.)

**Mechanism.** The runner has no quarantine awareness — `aid-run-gates.sh`
contains no exclusion or substitution logic, and this plan does not add any
(its only runner changes are the additive `--base-commit` / `--plan-path`
flags). The sanctioned path is the one the config's own quarantine comment
states: **run a pre-declared profile that excludes the quarantined gate**
(`bats_all_quarantine` already exists in the `gate_profiles` table), verify every
included gate, then record an explicit audited PM waiver for the excluded one.
There is no runner-level "subtract every `quarantine.enabled` gate" step.

While a gate is quarantined:

- Neither may EVER be reported as `pass`. Their honest states are `waived`,
  `profile_excluded`, `timeout_policy_block`, or `fail` — never green.
- A quarantined required gate MUST NOT be silently dropped so that
  `overall: pass` hides it. When it is waived, the waiver is gate-scoped
  (`aid-gate-waiver.sh`, IMP-270): bound to the exact candidate HEAD + command
  fingerprint, re-validated by the FSM at read time, and **fail-closed on a
  missing/malformed report `revision.head_sha` — no fallback to the current
  HEAD** (commit 6751157). The waiver reports the gate as `waived`, never `pass`.
- **Targeted evidence is allowed only as a MARKED substitute**, never a disguised
  green. A revision-bound, command-fingerprinted targeted-run receipt (the
  IMP-269 channel: `.log` named, `log_sha256` = the log's recomputed hash,
  `command_sha256` = sha256(.command), head fields == the reviewed candidate) may
  stand in for a quarantined broad gate at C3 — sealed into the manifest as
  hash-bound evidence and labelled a targeted substitute. A quarantined broad
  gate with no consumable channel leaves the plan-final result `unverifiable`
  (distinct from `fail`); `unverifiable` is never promoted to a blocking `pass`.
- When P066 lifts the quarantine, the same gate runs normally in the release
  profile and this substitution path is inert — the plan is written to be correct
  in both states.

### Cadence

- **Targeted first.** Each step proves itself with the narrowest suite covering
  its own change, at the reviewed HEAD, with a HEAD-bound receipt. Broad/expensive
  gates are not run per iteration.
- **Expensive gates once, on the frozen candidate.** The single `release`-derived
  profile run happens exactly once against the immutable `candidate_sha` (Step 2).
  A candidate-changing fix triggers `PLAN_FIX` and a refreeze; the expensive run
  is not repeated on an un-frozen, still-mutating branch.
- **No concurrent gates over a mutating worktree.** Gate runs and specialist
  reviews execute serially against one frozen tree; two suites must never run
  against the same live repo at once, and no gate runs while the worktree can
  still change under it (the freeze is the barrier). This mirrors the
  controller-owned job supervisor (`aid-job.sh`, IMP-262): one owned job, a
  durable terminal receipt, `.aid-o/` excluded from the tree fingerprint.

## Implementation Steps

> **Re-grounding note on line citations (2026-07-24, v2.62.1).** This plan was
> drafted 2026-07-20; Phase 1 then edited `aid-fsm.sh`, `lib/aid-lifecycle.sh`,
> `skills/pipeline.md` and others, so **every `file:line` citation below predates
> those edits and MUST be re-grepped by symbol name before an edit lands** — the
> target still exists but has moved. The largest shifts a verification pass
> confirmed: `cmd_plan_close` is now at `aid-fsm.sh:~5405` (the old `:4428-4522`
> now holds unrelated compliance-advance code); the C4 dual-run emitter is at
> `aid-fsm.sh:~3798-3877` (old `:4141-4194`); and every `lib/aid-lifecycle.sh`
> citation is uniformly ~+95 lines low (e.g. `aid_plan_closure_state` 774-808 →
> ~869-901; `aid_lifecycle_plan_close` 361-373 → ~452-467;
> `aid_lifecycle_record_delivery` 644-652 → ~748-785). Also note
> `plan_final_invalidate` (Step 5 error handling) does **not** exist in the tree —
> it is a helper THIS plan creates, not a P064 primitive. The plan's own
> instruction-sweep and edits already assume re-grep-by-pattern; this note makes
> the expectation explicit rather than trusting the stale line numbers.

**EPIC 1: Steps 1-6 — Plan final (freeze, gates, reviews, C4, release, close)**

### Step 1: Plan-final sync, version preparation and candidate freeze

**Objective:** Bring the recorded target branch into the plan branch, prepare
version metadata, and freeze one immutable candidate bound to an observed
target head.

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

**Architecture Context:** This opens the plan-final cycle in
`## Architecture` → Data flow. The order is load-bearing: sync before
version preparation, version preparation before freeze, so that the frozen
candidate already contains the release metadata and nothing needs to be
committed after the reviews start (roadmap D8, D9).

**CF3 is refined here (its blocking half is already resolved in code).**
`aid-c0-plan-review.sh` seals `<evidence_dir>/c0/plan-graph.json` into its input
manifest; the graph is produced by `aid-c0-contract.sh contract <plan.json>`, and
`plan.json` exists only after EPIC generation, so a pre-generation review can
never supply it. In the draft's era this returned `unverifiable`. **At v2.62.1 it
no longer does:** `_c0_manifest_entry` seals an absent input as a zero-byte
manifest entry (empty-string sha256, size 0) rather than failing, so a
pre-generation C0 review already proceeds. This step therefore does not fix a
block — it **refines the semantics**: it records `plan_graph: absent_pre_generation`
in place of the current opaque zero-byte seal, so the reviewer can tell a
legitimately-not-yet-generated graph from a truncated one. Because this changes
the `plan_graph` manifest entry from a zero-byte seal to a status string, it
shifts every sealed `input_hash` and updates the golden fixture at
`scripts/tests/bats/test-c0-plan-review.bats` (re-grep ~:383); the same step
extends that fixture and its expected hash. The absent-graph case already exists —
it is extended for the new status shape, not re-added.

The same step fixes a second bridge defect found by the same review: the
contract extractor greps for `defaults/(schemas|policies)/…` tokens and then
tests them relative to the repository root
(`lib/aid-c0-plan-review.sh:305-308`), so every plugin-relative path — which
is where all of this repository's schemas and policies actually live, under
`plugins/aid-orchestrator/defaults/` — fails the existence test and is
silently dropped. The manifest therefore seals an empty `contracts` array
even for a plan citing a dozen schemas, and the reviewer sees none of them.
The extractor is changed to resolve a token against the repository root
**and** against each plugin directory, sealing whichever exists. When the
graph does exist — any post-generation review — it is sealed and checked
exactly as today. This is a fix to the C0 bridge (P065's machinery), not to a
P064 contract.

**Implementation Detail:** `--stage sync` verifies every manifest EPIC has
status `merged_to_plan`, `abandoned` or `superseded` (a `pending` or
`running` EPIC exits 1 naming it), then merges the recorded
`target_branch` into the plan branch with `git merge --no-ff` — a merge, not
a rebase, so resume and audit stay deterministic (roadmap resolved decision
4). A conflict transitions to `CONFLICT` and exits 4. On success the state
moves to `PLAN_SYNC`.

`--stage freeze` runs in a fixed order that the `prepare-plan` guard depends
on: the plan is already in `PLAN_SYNC` (from `--stage sync`); `prepare-plan`
makes the version commit on the plan branch; the candidate is then frozen at
the resulting plan branch head and the state moves to `PLAN_GATES`. So
`prepare-plan` runs while the state is still `PLAN_SYNC` and never requires a
`candidate_sha` that does not yet exist. **The freeze write is atomic and
two-field: `candidate_sha` and `candidate_frozen_at` (RFC 3339 UTC) are written
into the RUNTIME plan-boundary manifest in the same operation**, by
`lib/aid-plan-manifest.sh` — the library that already owns `candidate_sha` — and
declared in `plan-boundary-manifest.schema.json` beside it. That runtime field is
the authoritative freeze-time source Step 5 validates `decided_at` against (see
*PM decision artifact*). It is deliberately NOT placed in the `.aid-lifecycle`
manifest: that is a different artifact with its own write path, and it cannot
establish atomicity with the runtime candidate write. A `PLAN_FIX` refreeze
rewrites both fields together and an invalidation clears both together, so a
decision bound to the previous candidate can never satisfy the new one and a
candidate can never exist without its freeze time. `aid-release.sh prepare-plan
<plan_id> --bump auto --plan-branch plan/<plan_id>` applies the version-file
edits driven by
`.aid-o/config/project.yaml` `versioning.files[]` and the CHANGELOG entry,
commits them on the plan branch with message
`release: prepare v<version> for <plan_id>`, and exits without tagging or
pushing.

Two facts about `aid-release.sh` make this a restructure rather than an
insertion. It has no `main()` and no subcommand dispatch: `BUMP_TYPE` is
taken from `${1:?...}` at `:28` and the entire body from `:38` to `:380`
executes unconditionally at source time. Adding subcommands means wrapping
the existing body in a function invoked by a dispatch block, preserving the
current `auto|patch|minor|major` interface exactly as the legacy entry point.
And its staging is `git add "${UPDATED[@]}"` followed by an unqualified
`git add -u` at `:373`, which stages every modified tracked file in the
worktree. In the legacy per-EPIC flow that is merely untidy; for a frozen
candidate it is a correctness defect, because unrelated dirt would become
part of the reviewed and tagged commit. `prepare-plan` stages only the
explicit version-file list and the CHANGELOG, and fails if any other tracked
file is modified.

Then the runner records
`candidate_sha = git rev-parse plan/<plan_id>` and
`target_branch_head_at_candidate_freeze = git rev-parse <target_branch>`,
allocates `plan_final_attempt + 1`, creates
`.aid-o/work/evidence/<plan_id>/R-<plan_id>-final-<N>/`, writes both values
plus `plan_final_run_id` and `plan_final_evidence_dir` into the manifest, and
transitions to `PLAN_GATES`.

Invalidation is a single function,
`plan_final_invalidate <plan_id> <reason> <target_state>`: it clears
`candidate_sha`, `target_branch_head_at_candidate_freeze`,
`plan_final_run_id` and `plan_final_evidence_dir` from the manifest, records
the reason, and transitions to the caller-supplied `<target_state>` — `PLAN_FIX`
for a review fix, `PLAN_SYNC` for a stale-authorization or conflict
resynchronisation (both legal from `AWAITING_PM` per P064's transition
table). The target state is a parameter precisely because the same field
clearing serves two recovery paths that land in different states; an earlier
draft hard-coded `PLAN_FIX` and could not express the resync path. Prior run directories are
never deleted or overwritten — each retry gets a new `R-<plan_id>-final-<N>`
(roadmap resolved decision 8).

**Error Handling:** If `prepare-plan` fails partway (a version file edit
succeeds, the CHANGELOG edit fails), it leaves the working tree dirty and
exits non-zero; `--stage freeze` refuses to freeze a dirty tree, so no
candidate is recorded. If the target branch has advanced between `sync` and
`freeze`, the freeze is **refused**: the runner logs
`target_drift_during_freeze` and returns the plan to `PLAN_SYNC` so the drift
is merged in before a candidate is frozen. Recording the newer head and
freezing anyway would bind a candidate that does not contain the drift (a
hotfix, typically) to a target head that does — the compare-and-swap in
Step 5 would still be exact, and would still merge a candidate missing the
hotfix. An earlier draft specified exactly that in Error Handling while the
Edge Cases and the step's acceptance criteria specified the opposite; the C0
cross-provider review caught the contradiction. `PLAN_SYNC → PLAN_SYNC` is a
legal transition precisely for this loop (see `## Data Model`).

**Edge Cases:**
- An `abandoned` EPIC with no PM reason recorded — `sync` exits 1; abandonment
  requires a recorded reason (roadmap §12).
- Version bump resolves to "no bump" (only `chore:`/`docs:` commits, per
  `aid-release.sh:38-45`) — `prepare-plan` makes no commit, and the candidate
  is simply the current plan head; this is legal and the test covers it.
- A hotfix lands on the target branch after `sync` but before `freeze` — the
  merge already happened, so the candidate does not contain the hotfix; the
  runner detects the drift by comparing the recorded head against the current
  one and returns to `PLAN_SYNC` rather than freezing a stale candidate.
- `--stage freeze` re-run after a crash — reconcile returns `git_applied` for
  the prepare commit; the existing commit is reused rather than duplicated.

**Dependencies:**
- Depends on: **P064** Step 6 (proven EPIC merges) and **P064** Step 3
  (manifest fields). No dependency inside this plan.
- Blocks: Step 2, Step 3, Step 4, Step 5.

**Acceptance Criteria:**
- [ ] A plan citing `defaults/schemas/*.json` paths that exist under
      `plugins/aid-orchestrator/` produces a non-empty `contracts` array in
      the sealed manifest.
- [ ] CF3 refinement delivered, asserted on the bridge rather than on a review
      verdict (its blocking half — absence making the review `unverifiable` — is
      already resolved in code, so this asserts the semantic improvement): with no
      `plan-graph.json` present, `build-manifest` records
      `plan_graph: absent_pre_generation` **instead of** the current zero-byte
      seal with the empty-file SHA; with a graph present, it is sealed and hashed
      exactly as today. (The overall review status is not asserted — a review can
      legitimately be `unverifiable` for unrelated reasons such as provider
      availability, so it is not a deterministic signal.)
- [ ] `--stage sync` refuses to proceed while any EPIC is `pending` or
      `running`, naming it.
- [ ] After `--stage freeze`, `candidate_sha` and
      `target_branch_head_at_candidate_freeze` are both exact 40-hex values in
      the manifest and a new immutable run directory exists.
- [ ] The same freeze write records `candidate_frozen_at` as a valid RFC 3339
      UTC timestamp in the RUNTIME plan-boundary manifest, atomically with
      `candidate_sha`; a refreeze rewrites both together and an invalidation
      clears both together — the manifest is never valid with one field set and
      the other absent, in either direction.
- [ ] A candidate change after freeze transitions the plan to `PLAN_FIX` and
      clears all four plan-final fields.
- [ ] A second freeze creates `R-<plan_id>-final-2` and leaves
      `R-<plan_id>-final-1` byte-identical.
- [ ] Target-branch advance between sync and freeze returns the plan to
      `PLAN_SYNC` instead of freezing.

**Effort:** L
**AID Role:** backend

### Step 2: Exactly one plan-final gate profile run

**Objective:** Run one resolved `release` profile against the frozen
candidate and produce a `gates_report.json` that proves no required gate was
excluded and no broad suite ran twice.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage gates`.
- Modify: `.aid-o/config/execution.yaml` — add a `release_quarantine` gate profile: every gate in `release` EXCEPT `bats_all` (i.e. `bats_fsm`, `shell_pipeline_smoke`, `plan_diff`, `docs_updated`). The existing `bats_all_quarantine` profile is EPIC-boundary-scoped and omits `shell_pipeline_smoke`, so it cannot serve a plan-final release run without silently dropping a non-quarantined release gate.
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (lines ~177-260) — add the additive `--base-commit` and `--plan-path` flags so a plan-final run can supply the substitution tokens an EPIC state file would otherwise provide.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC2 gate-report assertions.

**Architecture Context:** The gate runner
(`scripts/aid-run-gates.sh run-all`, signature at
`aid-run-gates.sh:177-203`) is reused with one contract extension: it must
accept plan-final base and plan inputs explicitly. It is invoked once per
plan with a plan-scoped report path and the profile resolved from the
manifest floor rather than from an EPIC's diff.

**Implementation Detail:** The stage checks out `candidate_sha` in a detached
state or verifies the plan branch head still equals it, resolves the profile
as `gate_profile_max(plan_final_required_profile, release)` (the resolver and
the `gate_profiles` table, including `release` as a strict superset of
`full`, are delivered by **P064** Step 8; this plan only consumes them). **When a
gate in the resolved profile carries a declared `quarantine:` block, the stage
runs the pre-declared release-derived substitute profile that excludes exactly
that gate and retains every other release gate** — at v2.62.1 that is the
`release_quarantine` profile this step adds (`release` minus `bats_all`). It is
NOT `bats_all_quarantine`: that profile is EPIC-boundary-scoped and omits
`shell_pipeline_smoke`, so using it for a plan-final run would silently drop a
non-quarantined release gate and fail this stage's own post-run assertion. This
is a profile selection, not a runner-level transformation: `aid-run-gates.sh` has
no quarantine awareness and this plan adds none. It then invokes:

```bash
aid-run-gates.sh run-all .aid-o/config/execution.yaml <plan_id> <plan_final_run_id> \
  --report-file .aid-o/work/evidence/<plan_id>/<run_id>/gates_report.json \
  --profile release \
  --base-commit <plan_base_commit> \
  --plan-path <abs path to the plan file>
```

`--base-commit` and `--plan-path` are **new flags this step adds**, and
without them the plan-final gate run is silently vacuous. `aid-run-gates.sh`
substitutes `{base_commit}` and `{plan_path}` into gate commands
(`:91-102`) and today sources both **only** from `--state-file`
(`:194-260`), which is an EPIC-scoped artifact a plan-final run does not
have. Supplying neither means `plan_diff` receives `--plan null`, takes its
documented Fast Mode graceful skip at `aid-plan-diff.sh:51-72` (exit 2), and
`execution.yaml`'s `pass_criteria` for that gate explicitly accepts exit 2 —
so the single release gate run for the whole plan would report success while
verifying nothing about the plan's acceptance criteria. The C0
cross-provider review found this; four same-provider rounds did not.

The flags are additive and optional, so every existing EPIC-scoped caller is
unaffected: when they are absent the runner falls back to `--state-file`
exactly as today.

**A required gate may not be satisfied by a skip — and `plan_diff` is made
required here.** In `execution.yaml` today `plan_diff` is `required: false` and
its Fast-Mode exit 2 counts as an accepted *pass*, so an assertion over
`result: skip` alone would not bind. The plan-final runner therefore treats
`plan_diff` as a plan-required gate for the release profile regardless of its
`execution.yaml` default (recorded in the manifest's plan-required gate set, the
mechanism P064 Step 8 established), and asserts its `result` is `pass` with a
non-empty diff evaluation over the plan file — an exit-2 Fast-Mode skip against
`--plan null` fails the stage. `plan_diff` carries no `quarantine:` block and is
**not** subject to the substitute path; the `--plan-path` flag (above) is what
makes a real evaluation possible. Note
`--report-file` is also mandatory: `aid-run-gates.sh` only writes the report when
that flag is supplied, and the default path it would otherwise compute assumes an
EPIC evidence layout.

**Data model — `quarantine_substitutes[]` in the plan-final gate report.** When a
quarantined broad gate is satisfied by a marked targeted substitute, the stage
records it in a top-level `quarantine_substitutes[]` array in `gates_report.json`
(runtime artifact — no Files entry; produced by `plan-finalize --stage gates`).
Each entry has at minimum:

```json
{
  "gate_id": "bats_all",
  "targeted_substitute": "accepted",
  "receipt_path": "gates/bats_all-substitute.receipt.json",
  "receipt_sha256": "sha256:<64-hex>",
  "command_sha256": "sha256:<64-hex>",
  "base_sha": "<40-hex plan_base_commit>",
  "head_sha": "<40-hex, MUST equal candidate_sha>",
  "substitute_scope": "targeted bats suites covering the candidate range, in place of the quarantined bats_all aggregate",
  "exit_code": 0,
  "failed": 0
}
```

Binding rules the stage enforces (fail the stage otherwise):
- **Same-gate only.** A substitute is accepted only for the `gate_id` it names;
  one receipt can never satisfy a different gate. The stage matches
  `quarantine_substitutes[].gate_id` to the quarantined gate id exactly.
- **`head_sha == candidate_sha`.** The receipt (and this entry) must be bound to
  the frozen candidate; any other head fails. `base_sha` must equal
  `plan_base_commit`. `receipt_sha256` must equal the sealed receipt file's hash
  and `command_sha256` must equal sha256 of the recorded command (the IMP-269
  receipt contract).
- **Genuine green substitute.** `exit_code: 0` and `failed: 0` — a substitute may
  only stand in for a broad gate when its own targeted run actually passed.
- **Waiver is separate.** A gate-scoped waiver (`revision.head_sha`-bound,
  fail-closed) remains a distinct PM risk-acceptance record; it never appears in,
  and never replaces, a `quarantine_substitutes[]` entry.
- **Broad gate stays quarantined.** The broad gate's own row in `gates` stays
  `waived` / `profile_excluded` / `unverifiable` — the substitute never rewrites
  it to `pass`.

After the run the stage asserts, from the report itself: `profile` is the
resolved release-derived profile (`release`, or its quarantine-substitute when
gates are quarantined); `revision.head_sha == candidate_sha`; `excluded_gates`
contains no gate that is `required: true` in `execution.yaml` or listed in any
EPIC's `plan.json.gates[]` **except a gate whose `quarantine.enabled: true`,
which is expected to be excluded/waived and must instead carry its marked
targeted-substitute evidence (never `pass`)**; `_command_log` is non-empty and
every entry has a non-null `duration_ms`; and every non-quarantined gate id in
the release include list appears in `gates` with a result other than
`profile_excluded`. Any assertion failure exits 1 and the plan stays in
`PLAN_GATES`. On success the stage
records `state_committed` and transitions `PLAN_GATES → PLAN_REVIEW` (a
P064-legal edge); a resume after the gate report is written but before the
transition re-reads the passing report and completes only the transition, so
the gates are not re-run.

The no-duplicate-broad-run assertion is structural: because `release` is
defined as a superset of `full` (Step 8), the runner is invoked exactly once,
and the test asserts the count of `gate_runner_start` timeline events for the
plan-final run is exactly one.

**Error Handling:** A gate that fails leaves `overall: fail` in the report;
the stage exits 1 and the plan stays in `PLAN_GATES` so the PM sees a
failing candidate rather than a silently retried one. A gate that hits the
repeated-timeout policy block from P063
(`scripts/lib/aid-gate-runtime-baseline.sh` via
`aid-run-gates.sh:418-438`) surfaces as a fail with the
`timeout_policy_block` reason preserved in the report — the plan-final runner
does not retry it.

**Edge Cases:**
- `plan_final_required_profile` already equals `release` — the max is
  `release`, one run, no change.
- A plan-declared gate that exists in no profile include list — recorded as a
  mandatory plan-final gate by Step 8 and appended to the run's include set;
  its absence from the report is an assertion failure.
- The candidate contains no changes relative to the target branch (an empty
  plan) — gates still run; an empty plan is a PM decision, not a gate
  decision.
- `bats` not installed — the gate command fails loudly rather than skipping;
  the roadmap's acceptance section is explicit that a missing Bats is a
  failure, not a green skip, and `.github/workflows/ci.yml` already installs
  it for this reason.

**Dependencies:**
- Depends on: **P064** Step 8 (profile table and accumulated floor), and
  Step 1 here (frozen candidate).
- Blocks: Step 4 (C4 requires the gate report).

**Acceptance Criteria:**
- [ ] The plan-final `gates_report.json` carries the resolved release-derived
      `profile` (`release`, or its quarantine-substitute when gates are
      quarantined) and `revision.head_sha` equal to `candidate_sha`.
- [ ] No gate that is `required: true` or plan-declared appears in
      `excluded_gates`, **except a `quarantine.enabled` gate**, which may be
      excluded/waived and instead carries its marked targeted-substitute evidence.
- [ ] No quarantined gate (`bats_all` — the only one at v2.62.1) is reported
      `pass`; each is `waived`/`profile_excluded`/`unverifiable` and **carries its
      marked targeted-substitute receipt as the verification signal**. A
      gate-scoped waiver (`revision.head_sha`-bound, fail-closed) may
      *additionally* record PM risk-acceptance where the gate would otherwise
      block, but never substitutes for the targeted evidence: a waiver alone, with
      no substitute receipt, does **not** satisfy the gate. Never green.
- [ ] Every quarantined gate satisfied by a substitute has a matching
      `quarantine_substitutes[]` entry carrying `gate_id`, `targeted_substitute`,
      `receipt_path` + `receipt_sha256`, `command_sha256`, `base_sha`,
      `head_sha == candidate_sha`, `substitute_scope`, `exit_code: 0` and
      `failed: 0`; the stage rejects a substitute whose `gate_id` does not match
      the quarantined gate (one receipt cannot satisfy another gate) or whose
      `head_sha != candidate_sha`, and never rewrites the broad gate's own row to
      `pass`.
- [ ] The substitute profile is release-derived: `release_quarantine` contains
      every gate in `release` except `bats_all`, and the plan-final report shows
      each of them with a real result — no non-quarantined release gate (notably
      `shell_pipeline_smoke`) is dropped by the substitution.
- [ ] Exactly one `gate_runner_start` event exists for the plan-final run —
      no second broad run under a `full` label.
- [ ] `plan_diff` runs for real against the plan file and the candidate range —
      it does not receive `--plan null` and does not take its Fast Mode exit-2
      skip. (`plan_diff` is not quarantined; it has no substitute path.)
- [ ] A `result: skip` on any non-quarantined gate that is `required: true`
      fails the stage rather than counting as satisfied.
- [ ] Existing EPIC-scoped `aid-run-gates.sh` callers are unaffected when the
      new flags are absent; `test-aid-run-gates.bats` stays green.

**Effort:** M
**AID Role:** qa

### Step 3: Plan-level review orchestration and PLAN_FIX invalidation

**Objective:** Run the C2 final review, the C3 audit, the Curator, the
Simplifier, the registered plan utilities and the Reporter exactly once each
against the frozen candidate, with every output landing outside the candidate
tree.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage review`, including the required-output contract and the invalidation trigger.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~996-1090) — rewrite the DONE closure checklist and the C+A execution model for the plan-final boundary.
- Modify: `plugins/aid-orchestrator/defaults/schemas/delivery-gate.schema.json` — allow `identity.epic_id` to be string-or-null so the plan-level aggregate (`epic_id: null`, `plan_id` set) is schema-valid; today it requires a string.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC3 dispatch-count and invalidation cases.

**Re-grounded (2026-07-24):** `acceptance-evidence.schema.json` needs **no**
change — it declares no `identity` block (it references the `aid-protocol-v2`
envelope, reference-only, not a resolved `$ref`), and in that envelope
`identity.epic_id` is already `["string","null"]`, so the plan-level acceptance
aggregate (`epic_id: null`) is already valid. Only `delivery-gate.schema.json`
(above) requires the string-or-null widening — that schema does require
`identity.epic_id` as a string.

**Architecture Context:** The shell FSM does not dispatch LLM agents; it
declares which outputs must exist, validates them, and blocks until they do.
That division already exists for C3 (`aid-fsm.sh:3939-4107` validates a
dispatch record the controller produced) and is preserved here. What changes
is the subject: the review range is `plan_base_commit..candidate_sha`, not an
EPIC diff.

**Implementation Detail:** The stage writes a
`review-requirements.json` into the plan-final run directory listing each
required output with its expected path, artifact type and subject binding,
then blocks with exit 7 (`awaiting_review_outputs`) until they exist. The
controller dispatches the agents and re-runs the stage. Required outputs in
the run directory:

| Output | Type | Binding checked |
|---|---|---|
| `semantic-review-final.json` | `semantic_review` | `revision.head_sha == candidate_sha`, range covers `plan_base_commit..candidate_sha` |
| `audit-report.json` | `audit_report` | `reviewed_head == candidate_sha`, `input_manifest_hash` present |
| `curator-report.json` | `curator` | `audit_report_ref` sha256 matches the audit report |
| `simplifier-report.md` | markdown | `Head:` provenance line equals `candidate_sha` |
| `delivery-report.json` | `delivery_report` | `identity.plan_id`, `revision.head_sha == candidate_sha` |
| `review-profile.json` | `review_profile` | produced by `aid-prefilter.sh profile` over `plan_base_commit..candidate_sha`; arms the C3 gate |
| `delivery-gate.json` | `delivery_gate` | aggregated from `epic_runs[].evidence_dir`; `identity.epic_id: null` (schema widened to string-or-null this step), `identity.plan_id` set, `sources[]` lists contributing EPICs |
| `acceptance-evidence.json` | `acceptance_evidence` | aggregated the same way; a missing per-EPIC contribution is a blocker naming that EPIC |

The Reporter is dispatched only after the final non-mutating pass: the stage
refuses to accept `delivery-report.json` if any later-recorded operation
changed the candidate. Its authoritative output is the protocol-v2 JSON in
the run directory; the human `.aid-o/reports/<plan_id>-delivery.md` remains a
projection and is explicitly not release authority.

Every registered plan-boundary utility (today: the Scanner memory scan
described at `skills/pipeline.md:1073-1086`) runs once and is counted in
`utilities_run[]` in the manifest. Any tracked write produced by a utility or
a specialist fix is treated as a candidate-changing fix: the stage calls
`plan_final_invalidate` with the reason, and the plan returns to `PLAN_FIX`.
Detection is a `git rev-parse plan/<plan_id>` comparison against
`candidate_sha` at the start of every stage invocation, plus a
`git status --porcelain` check for uncommitted tracked changes.

**Error Handling:** A missing required output exits 7 with the list of what
is missing — a state the controller resolves by dispatching, not an error. A
present-but-stale output (wrong head, wrong plan, wrong subject hash) exits 1
and names the mismatch; it is never accepted with a warning, because a stale
review is exactly the failure this boundary exists to prevent. An output that
fails `aid-protocol-validate.sh` exits 1 with the validator's exit code
echoed.

**Edge Cases:**
- An accepted Curator fix that changes the candidate — invalidation fires,
  gates and all reviews must re-run against a new candidate; the test proves
  the full loop, not just the transition.
- The Reporter runs, then a Simplifier fix is accepted — the delivery
  artifact is invalidated with the rest; Reporter must re-run last.
- An EPIC evidence pack copied into the plan-final run directory to satisfy a
  requirement — subject and identity validation fails because
  `identity.plan_id` is absent or wrong.
- A specialist writes only to the run directory (the normal case) — no
  candidate change, no invalidation; the test asserts `candidate_sha` is
  unchanged after a full review pass.
- C3 applicability: for a low-risk plan the single plan-level Auditor
  dispatch is still recorded, but C3 blocking semantics stay governed by
  `defaults/policies/c3-audit-policy.yaml` — P064 does not expand them.

**Dependencies:**
- Depends on: Step 1 (candidate), Step 2 (gates precede reviews).
- Blocks: Step 4 (C4 consumes these artifacts).

**Acceptance Criteria:**
- [ ] The C2 final review's recorded range covers a defect seeded in the
      first EPIC and detected after the last EPIC is integrated.
- [ ] Auditor, Curator, Simplifier and Reporter each dispatch exactly once on
      the final successful attempt, and every other enabled plan utility is
      counted explicitly.
- [ ] A missing, stale, wrong-plan or wrong-candidate output cannot satisfy
      the stage.
- [ ] The plan-final run contains `review-profile.json`, `delivery-gate.json`
      and `acceptance-evidence.json` bound to the plan (not an EPIC), so
      `check_required_present` and `_c3_gate_active` in plan-mode C4 have a
      satisfiable input path.
- [ ] A full review pass leaves `candidate_sha` and the product worktree
      unchanged.
- [ ] An accepted fix that changes the candidate transitions to `PLAN_FIX`
      and invalidates the gate report and every review output.

**Effort:** L
**AID Role:** architect

### Step 4: Plan-mode C4 release decision and plan-level PM summary

**Objective:** Produce one plan-mode `release-decision.json` bound to the
candidate and target SHAs, and a PM summary that can never imply an
intermediate EPIC was released.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~460-530) — add the flag-driven plan mode alongside the untouched positional EPIC mode.
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~300-370) — make `compute_reporter` and `compute_simplifier` plan-boundary-aware instead of gating on the EPIC `ca-review-complete` marker.
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~518-554) — resolve the `plan_review` input from the plan's own C0 review in plan mode instead of from `epic_input.md` frontmatter.
- Modify: `plugins/aid-orchestrator/defaults/schemas/release-decision.schema.json` — widen the `blockers[].input_id` enum for plan-mode inputs and per-EPIC roll-up blockers.
- Modify: `plugins/aid-orchestrator/scripts/aid-pm-brief.sh` (lines ~40-160) — render a plan-level brief from a plan-mode decision.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-finalize --stage c4` and `--stage summary`.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC4 identity cases.

**Architecture Context:** C4 is EPIC-scoped end to end today: two positional
arguments, an evidence directory hardwired to
`.aid-o/work/evidence/<epic>/<run>` (`aid-release-policy.sh:485`), and a
Reporter input whose plan number is derived from the EPIC id
(`aid-release-policy.sh:309-318`). Plan mode replaces the resolution layer
while reusing every `compute_*` function.

**Implementation Detail:** Flag parsing sets `MODE=plan` when `--plan` is
present. In plan mode: `EVIDENCE_DIR` comes from `--evidence-dir`;
`identity` becomes `{project_id, plan_id, run_id, epic_id: null, step_id: null}`;
and the rolled-up inputs iterate `epic_runs[].evidence_dir` from the
manifest, treating any EPIC whose contribution is missing as a blocker
naming that EPIC.

**The plan-final run must produce every required input, or C4 blocks
forever.** `check_required_present` (`aid-release-policy.sh:164-172`)
hard-blocks on a missing `review-profile.json`, `delivery-gate.json` or
`acceptance-evidence.json`, and `_c3_gate_active` (`:198-201`) early-returns
*inactive* without `review-profile.json` — which would silently demote the
Auditor and Curator to advisory at the one boundary where this plan makes
them mandatory. The mechanism differs by input, because two of the three existing producers
are EPIC-shaped and cannot run plan-level: `aid-delivery-gate.sh` requires
`--epic <id>` and stamps `identity.epic_id`, and `aid-acceptance-evidence.sh`
reconstructs from a generated `plan.json`. So Step 3 produces the three
required inputs into the plan-final run directory as follows, and lists all
three in its output table:

- **`review-profile.json`** — produced plan-level by running the existing
  `aid-prefilter.sh profile` (`aid-prefilter.sh:351,388`) over the plan diff
  `plan_base_commit..candidate_sha`. This is a genuine producer run, not a
  roll-up, and it arms the C3 gate (`_c3_gate_active` reads exactly this
  file).
- **`delivery-gate.json`** and **`acceptance-evidence.json`** — **aggregated**,
  not re-produced: the runner reads each `epic_runs[].evidence_dir`'s
  per-EPIC artifact (already produced during that EPIC) and merges them into
  one plan-level artifact with `identity.epic_id: null`, `identity.plan_id`
  set, and a `sources[]` list of the contributing EPIC run ids. A missing
  per-EPIC contribution is a blocker naming that EPIC. The aggregation is a
  new helper in the plan-final runner, not a call to the EPIC-shaped
  producers, so no producer is asked to run in a mode it does not support.

Three further `compute_*` functions cannot be reused as they stand, and
pretending otherwise would silently produce a permissive decision:

- `compute_reporter` (`:305-338`) and `compute_simplifier` (`:344-366`) both
  gate on `${EVIDENCE_DIR}/ca-review-complete` and return
  `not_applicable / "not_plan_boundary"` when it is absent. In plan mode that
  marker does not exist by construction, so both would report a
  non-blocking `not_applicable` — exactly inverting their purpose at the one
  boundary where they are mandatory. In plan mode the boundary condition is
  the plan-final run itself: the Reporter input reads
  `delivery-report.json` from the run directory and the Simplifier input
  reads `simplifier-report.md` from the run directory, and a missing or
  stale artifact is a blocker, not a skip. `compute_reporter` additionally
  derives the plan number from the EPIC id via
  `[[ "$EPIC_ID" =~ ^E-([0-9]+) ]]` (`:309-318`), which has no meaning when
  `EPIC_ID` is null.
- `plan_review` (`:518-554`) resolves through `epic_input.md` frontmatter to
  find `plan_ref`. In plan mode there is no `epic_input.md`; the input
  resolves directly to the plan's own
  `.aid-o/work/evidence/<plan_id>/c0-plan-review.json` — the canonical path
  `aid-c0-plan-review.sh` actually writes. The EPIC-mode code this replaces
  reads `<evidence>/c0/plan-review.json` (`aid-release-policy.sh:528`), which
  the C0 producer does not write; plan mode must not inherit that path, and
  EPIC mode is left untouched so no existing behaviour changes. Left unchanged this
  required input would be permanently missing and `release_ready` could
  never become true.

`release-decision.schema.json` constrains `blockers[].input_id` to a closed
12-value enum, so plan-mode inputs and per-EPIC roll-up blockers would fail
schema validation. A finite enum cannot be "widened" to cover
`epic_rollup:<epic_id>` for arbitrary future EPIC IDs — an earlier draft
claimed exactly that, which is not expressible. The field becomes a closed
`oneOf` instead:

```json
"input_id": {
  "oneOf": [
    { "enum": ["review_profile", "delivery_gate", "semantic_review_final",
               "acceptance_evidence", "gates_report", "plan_review",
               "verification_report", "curator_report", "audit_report",
               "invalidation_map", "reporter", "simplifier",
               "delivery_report"] },
    { "type": "string", "pattern": "^epic_rollup:E-[0-9]{3}-[0-9]+_[0-9]+$" }
  ]
}
```

This stays closed — a typo in a canonical id still fails, and a malformed
EPIC id in a roll-up blocker still fails — while admitting any well-formed
EPIC. Fixtures cover both branches plus one invalid EPIC id.

Before reading anything, plan mode validates identity: the manifest at
`.aid-o/work/plan-state/<plan_id>/plan-boundary-manifest.json` must declare
the same `plan_id`, the same `plan_final_run_id`, and a `candidate_sha`
matching `--candidate-sha`; `--target-head-sha` must equal the recorded
`target_branch_head_at_candidate_freeze`. A mismatch exits 1 regardless of
any policy mode — this is a P064-owned identity invariant, not an E10 finding
promotion (roadmap D10). Passing an EPIC evidence directory therefore fails
even if it is a complete, valid EPIC pack, and so does a copy or symlink of
one placed at the plan path.

The relocated legacy release checks run in the same stage, once, and their
result is recorded alongside the C4 decision. Before E10, C4 keeps its
configured mode from `defaults/policies/release-decision-policy.yaml`
(`enforcement: observe` today) and emits dual-run evidence exactly as
`aid-fsm.sh:4141-4194` does for EPICs.

`--stage summary` renders the PM plan-final summary with the sections
required by roadmap §8: what the plan delivered, which EPICs ran, what was
skipped at EPIC level and why, plan-final gate results, the specialist review
summary, remaining backlog, and the merge decision. It prints
`reviewed_candidate_sha`, `approved_target_sha`, the final main merge SHA
(null until Step 5) and the release/tag status as four distinct labelled
fields, and transitions the plan to `AWAITING_PM`.

**Error Handling:** Missing required flags in plan mode exit 2 with usage. A
manifest that cannot be read exits 1 — plan mode never falls back to EPIC
resolution. If `aid-evidence-verify.sh` (invoked as the
`verification_report` input at `aid-release-policy.sh:557`) cannot run
against the plan run directory, the input is recorded as a blocker rather
than skipped.

**Edge Cases:**
- Retry after a `PLAN_FIX` — the new run id is `R-<plan_id>-final-2`; the
  decision written into run 1 remains on disk and is never overwritten.
- A waiver file in the plan run directory — handled by the existing waiver
  loop (`aid-release-policy.sh:629-671`), which flips an input row to
  `waived` without changing `release_ready`; unchanged semantics.
- `autonomous_mode: true` in `.aid-o/config/permissions.yaml` — sets
  `merge_mode: auto` as today, but plan mode still requires the PM decision
  file at Step 5; autonomy does not remove the authorization artifact.
- An advisory input missing (`invalidation_map`) — does not block, mirroring
  `aid-release-policy.sh:572-577`.

**Dependencies:**
- Depends on: Step 2 (gate report), Step 3 (review artifacts).
- Blocks: Step 5 (the merge requires a decision bound to this run).

**Acceptance Criteria:**
- [ ] Every plan-mode input names the plan id, run id, candidate SHA, target
      ref and target head SHA.
- [ ] C4 consumes the run-scoped `delivery-report.json`, not a committed
      Markdown projection or the legacy `ca-review-complete` marker.
- [ ] Passing an EPIC evidence directory, or a copy of a valid EPIC pack
      placed at the plan path, fails identity validation.
- [ ] A retry writes `R-<plan_id>-final-2` and leaves run 1 untouched.
- [ ] The PM summary distinguishes reviewed candidate, approved target, final
      merge SHA and tag status as separate fields.

**Effort:** L
**AID Role:** backend

### Step 5: Compare-and-swap merge to main, one tag, one push

**Objective:** Merge only the approved candidate into only the expected
target head, verify the resulting tree, and publish exactly once.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-merge-to-main`.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~360-380) — add the `tag-plan` subcommand and make tagging idempotent.
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-push` (lines ~30-50) — exempt `plan/*` and `task/*` branches from the version-bump push block.
- Create: `plugins/aid-orchestrator/defaults/schemas/pm-plan-decision.schema.json` — the PM authorization contract validated before any merge action.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~36-50, ~470-700) — teach the five binding-path functions a plan-mode that advances the target ref by plumbing (`commit-tree` + CAS `update-ref`) instead of requiring a checkout, so delivery bindings and the receipt commit in one post-merge pass even when the target branch is checked out in another worktree.
- Modify: `plugins/aid-orchestrator/defaults/schemas/plan-lifecycle-manifest.schema.json` — widen `declared_epics[].scope` from `[required, backlog]` to include `abandoned` and `superseded`, and add a top-level `status` property (`active | closed | aborted`); the schema is `additionalProperties: false`, so neither the CF1 re-scope nor the abort record can produce a valid manifest without both changes. (`candidate_frozen_at` is deliberately NOT added here — it is a RUNTIME plan-boundary-manifest field owned by Step 1; see below.)
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~730-808) — exclude the two new scopes from the closure predicate's required set.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC5 and AC6 cases.

**Architecture Context:** This is the only place in AID where `main` moves
under the new model. It replaces the prose merge at
`skills/pipeline.md:1571` and the version/tag ceremony that
`aid-release.sh:377` performs per EPIC today.

**Implementation Detail:** The command reads the decision file, then asserts
in order: `decision == "MERGE"`; `plan_id` matches; `plan_final_run_id`
matches the manifest; `candidate_sha` equals both the file's value and the
current `plan/<plan_id>` head; `target_head_sha` equals both the file's value
and the current target-branch head. Any mismatch exits 1 with `main`
unmoved — that includes the case where the target branch advanced while the
PM was deciding, which additionally records `stale_authorization` and returns
the plan to `PLAN_SYNC`.

On success the merge is **published atomically first, then the lifecycle
commit is layered on top** — the two operations are separated precisely
because they have conflicting requirements. The merge must not check out the
target branch (a `git checkout` + head check + `git merge` leaves a TOCTOU
window in which another process moves the ref between check and merge); the
lifecycle write must be on the target branch
(`_aid_lc_require_target_branch`, `lib/aid-lifecycle.sh:36-50`, tests
`git branch --show-current`). The sequence resolves both:

1. `plan_op_begin` with `expected_before_sha` = target head → build the merge
   commit in isolation (first parent `target_head_sha`, second parent
   `candidate_sha`) without moving any ref → publish with
   `git update-ref refs/heads/<target_branch> <new_merge_sha> <target_head_sha>`,
   which fails atomically if the ref no longer points at the expected old
   value → `plan_op_mark_git_applied`. **The release is now published** and
   the CAS window is closed.
2. Only then write the lifecycle commit — **delivery bindings and the CF1
   re-scope, not the receipt** — via plumbing, never a checkout. The receipt
   is Step 6's (`plan-close`): the split is deliberate so a single owner
   writes each artifact. Step 5 makes the plan *closable* (every required EPIC
   delivered and reviewed, abandoned ones re-scoped); Step 6 verifies closure
   and commits the receipt. A `git checkout
   <target_branch>` from the plan worktree fails when the target branch is
   already checked out in another linked worktree (the normal case: the
   controller runs EPICs in per-branch worktrees), and Git refuses the same
   branch in two worktrees. So the commit is built with `git commit-tree`
   (parent = the published merge commit) and published with
   `git update-ref refs/heads/<target_branch> <lifecycle_commit>
   <merge_commit>` — a compare-and-swap from the merge commit, using no
   worktree and no `HEAD`. This requires P068 to add a plan-mode to
   `_aid_lc_isolated_commit`/`_aid_lc_require_target_branch`
   (`lib/aid-lifecycle.sh:36-50`) that advances the target ref by plumbing
   instead of asserting `git branch --show-current == target`; the safety
   invariant it enforces (the commit lands on the target branch) is satisfied
   by construction because `update-ref` writes exactly that ref. If the
   process dies here the merge stands; `plan-close-check` on resume first
   re-applies any missing delivery binding and abandoned/superseded re-scope
   idempotently (bringing closure state out of `active`), then commits the
   receipt — never a bare receipt over unbound deliveries.

Between publish (stage 1) and the lifecycle commit (stage 2), tree identity
is verified by comparing `git rev-parse <merge_commit>^{tree}` against the
expected merged tree, and `git merge-base --is-ancestor <candidate_sha>
<target_branch>` confirms the candidate is now reachable. The lifecycle
delivery bindings (below) are written in stage 2 on the checked-out target
branch → **conditionally** tag → push according to project policy →
`plan_op_commit` and transition to `PLAN_MERGING`.

**Tagging is conditional on a version bump.** `prepare-plan --bump auto` may
resolve to no bump (only `chore:`/`docs:` commits since the last tag), making
no version commit; the candidate's version then equals the already-released
one, and calling `tag-plan --version <that version>` would fail because a tag
for it already exists on an older commit. So `prepare-plan` records the
resolved version — or the literal `none` — in the plan-final run's
`release-prep.json`, and `plan-merge-to-main` runs
`aid-release.sh tag-plan <plan_id> --merge-sha <merge_commit> --version <v>`
only when a new version was prepared. A no-bump plan merges and closes with
no new tag: a legal, tested outcome, not a `tag-plan` failure.

**CF1 closes here.** Abandoned and superseded EPICs are re-scoped in the
lifecycle manifest as part of this command, not at `epic-complete`. P064
records the terminal status in its runtime manifest only, because
`_aid_lc_require_target_branch` (`lib/aid-lifecycle.sh:36-50`) refuses
lifecycle writes off the target branch and `epic-complete` runs on a task
branch. This command already runs on the target branch, so it is the first
point where the write is legal. Before binding deliveries it rewrites each
abandoned or superseded EPIC's `scope` in
`.aid-lifecycle/manifests/<plan_id>.yaml` to `abandoned` or `superseded`,
so `aid_plan_closure_state` stops counting them as required. The **PM reason
does not go into the git-tracked manifest**: the manifest schema is
`additionalProperties: false` and `aid_lifecycle_publicsafe_check` rejects a
free-text `reason` key, so a reason field there would fail validation. The
reason is recorded in the runtime plan-state and the operation log (which
already carry PM decisions); the manifest carries only the `scope` value.
The schema today permits only `required` and `backlog` for
`declared_epics[].scope`
(`plan-lifecycle-manifest.schema.json`), so this step widens that enum and
teaches the closure predicate to exclude the two new values — this schema is
lifecycle-layer, not one of P064's contracts, so extending it here does not
violate the no-backward-flow rule — otherwise an
abandoned required EPIC pins the plan at `active` forever and the receipt can
never be written. The re-scope and the delivery bindings are one commit, so
the closure denominator and the deliveries can never disagree.

**Lifecycle delivery bindings are written here, in one pass.** In the legacy
flow each EPIC's binding is written by `aid_lifecycle_record_delivery`
immediately after that EPIC's merge into the target branch
(`lib/aid-lifecycle.sh:644-652`), and the function hard-refuses to run
anywhere except the target branch (`:658`). In `plan_branch` mode no EPIC
ever merges into the target branch, so that call site disappears — and
without a replacement `aid_lifecycle_plan_close` (`:361-373`) would refuse
forever, because it requires every `scope: required` EPIC to be both
delivered (a `delivery_sha`, `:737-743`) and review-accepted (`:746-752`).
This is the first moment a real target-branch merge SHA exists, so it is the
correct place: after the merge and tree verification, the command iterates
`epic_runs[]` from the manifest and binds every non-abandoned EPIC with
`delivery_sha` set to the plan merge commit, taking the review verdict from
the plan-level `audit-report.json` and `curator-report.json` in the
plan-final run directory. That substitution is semantically right rather than
a workaround: in the new model the review genuinely happens once for the
whole plan, so a per-EPIC verdict derived from a per-EPIC audit report no
longer exists to be read.

Five functions on the binding path need a plan-mode, not just
`aid_lifecycle_record_delivery`; an implementer who edits only that
function's range produces a binder that still cannot bind:

| Function | Line | Why it blocks in plan mode |
|---|---|---|
| `_aid_lc_find_delivery_merge` | `:509-517` | `git log <target> --merges --grep "<epic_id>"` — the only merge reaching the target branch is `merge(plan): <plan_id>`, which names no EPIC id, so it returns empty |
| `_aid_lc_epic_reviewed_head` | `:474-480` | reads a per-EPIC `audit-report.json` that Step 9 no longer produces → unverifiable |
| `_aid_lc_epic_review_status` | `:490-502` | same file → returns `none` |
| `_aid_lc_can_bind` | `:526-537` | aggregates the three above |
| `aid_lifecycle_bind_delivery` | `:542-558` | accepts no merge SHA |

In plan mode the merge SHA is supplied explicitly by the caller, and the
reviewed head and review status come from the plan-final run's
`audit-report.json` and `curator-report.json`. The target-branch guard
(`:36-50`) and every legacy code path are unchanged. The bindings are written
before the tag so that a crash between them cannot produce a tagged release
with no closure path.

**The pre-push guard needs an exemption, not a whitelist entry.**
`defaults/hooks/pre-push` is a separate file from `pre-commit` and is
branch-agnostic: it blocks any push carrying `feat:` or `fix:` commits since
the last tag with no `release:` commit among them (`pre-push:36-49`). A plan
branch accumulates precisely that from its first EPIC until the Step 1
freeze, so in `plan_branch` mode every push of a `task/*` or `plan/*` branch
would be blocked, and the remedy the hook prints — run `aid-release.sh auto`
— is the per-EPIC ceremony this plan exists to remove. The exemption reads
the branch being pushed and exits 0 for `plan/*` and `task/*`, leaving the
guard fully active for the target branch, which is the only branch where a
premature release is possible in the new model.

`tag-plan` is idempotent: if the tag exists and points at `--merge-sha`, exit
0 without acting; if it exists and points elsewhere, exit 1. The push step is
guarded the same way — it checks whether the remote ref already contains the
merge commit before pushing.

`defaults/hooks/pre-commit` needs no change. Its governance dispatch fires
only on an exact `branch:` match against a run state file
(`defaults/hooks/pre-commit:185-188`) or on the literal target-branch name
(`:237`, `:244`); a `plan/*` branch matches neither, so the
`release: prepare` commit on the plan branch is already ungoverned. This was
verified rather than assumed — an earlier draft listed a `pre-commit` edit
that would have been a no-op.

**Error Handling:** A merge conflict against the target branch transitions to
`CONFLICT`, aborts the merge, and exits 4. `CONFLICT` is not terminal: the
operator resolves it by re-synchronising the target branch into the plan
branch (`plan-finalize --stage sync`), which necessarily produces a new plan
branch head — so the resolution **invalidates the frozen candidate** and
returns the plan to `PLAN_SYNC` via `plan_final_invalidate <plan_id> <reason> PLAN_SYNC`. There is no path from `CONFLICT` straight back
to a merge against the old candidate; the most expensive branch in the design
is stated rather than left implicit. `main` is left at its original
SHA and the test asserts that. A tree verification failure after a successful
merge is a hard exit 5 with instructions to inspect manually — the command
does not attempt an automatic reset, because history on the target branch may
already be published (roadmap §12: published history is repaired by a new
revert or hotfix, never a destructive reset).

**Edge Cases:**
- Crash after `git merge` but before the tag — reconcile returns
  `git_applied`; the resumed run skips the merge, verifies the merge commit,
  and proceeds to the idempotent tag.
- Crash after the tag but before the push — the tag check finds the existing
  correct tag and exits 0; the push guard finds the remote does not have it
  and pushes once.
- A decision file for a different plan or a different run id — exits 1 before
  any Git action.
- `decision: "FIX"` or `"ABORT"` — the command refuses to merge; `FIX`
  transitions to `PLAN_FIX`, `ABORT` transitions to `ABORTED` with the
  terminal reason recorded and `main` unchanged.
- Missing or malformed decision file — exits 1, `main` unchanged.

**Dependencies:**
- Depends on: Step 4 (decision bound to the run).
- Blocks: Step 6 (close follows the merge).

**Acceptance Criteria:**
- [ ] Missing, `FIX`, `ABORT`, stale, malformed, wrong-plan, wrong-candidate
      and wrong-target decisions each exit non-zero with the target branch
      unchanged.
- [ ] A decision artifact that fails `pm-plan-decision.schema.json`, or whose
      `decided_at` precedes the RUNTIME plan-boundary manifest's
      `candidate_frozen_at`, is rejected before any Git action.
- [ ] The freeze-time validation is fail-closed on every degenerate input: a
      manifest missing `candidate_frozen_at`, a `candidate_frozen_at` that is not
      valid RFC 3339 UTC, and a malformed `decided_at` each exit 1 with the
      target branch unchanged (never "assume old enough"). A decision bound to a
      pre-refreeze candidate fails against the rewritten `candidate_frozen_at`.
- [ ] A concurrent target-branch advance loses the compare-and-swap and
      forces revalidation — asserted by moving the target ref between the
      head check and the publish, which `git update-ref <new> <expected-old>`
      must reject.
- [ ] The merge commit is built without moving any ref; a failed
      `update-ref` publish leaves the target branch byte-identical.
- [ ] The lifecycle commit advances the target ref by plumbing after the
      merge is published — it succeeds with the target branch checked out in
      another worktree, and a crash between publish and lifecycle commit is
      resolved on resume by re-applying any missing binding and then
      committing the receipt, never a second merge.
- [ ] No intermediate EPIC creates a version commit or tag. A plan with a
      version bump creates exactly one tag on the final merge commit; a
      no-bump plan creates none and `tag-plan` is not called.
- [ ] Resume after each transaction boundary creates no duplicate merge,
      release commit or tag.
- [ ] Pushing `plan/*` or `task/*` with `feat:`/`fix:` commits and no
      `release:` commit succeeds; pushing the target branch in the same state
      is still blocked by `defaults/hooks/pre-push`.
- [ ] Every abandoned or superseded EPIC is re-scoped in the lifecycle
      manifest in the same commit as the delivery bindings, and
      `aid_plan_closure_state` no longer counts it as required (CF1).
- [ ] After the merge, every non-abandoned EPIC has a `delivery_sha` binding
      in `.aid-lifecycle/manifests/<plan_id>.yaml` pointing at the plan merge
      commit, and `aid_plan_closure_state` no longer reports `active`.

**Effort:** L
**AID Role:** backend

### Step 6: Plan-close mechanical gate bridging markers and lifecycle receipts

**Objective:** Make plan-close a real gate that can only pass after the merge
or a recorded abort, and that reconciles the legacy marker world with the
`.aid-lifecycle/` receipt world.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — implement `plan-close-check` and the close transaction.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-close-check.sh` (lines ~440-515) — add the plan-branch checks and the receipt reconciliation.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~322-373) — give `aid_lifecycle_plan_close` and its receipt commit the same plumbing plan-mode Step 5 adds to the binding path, so the receipt is committed by `commit-tree` + CAS `update-ref` onto the target ref without a checkout — the close path must work when the target branch is checked out in another worktree.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-state.sh` — add `plan-close` to the operation-record `command` enum so the close transaction is reconcilable like every other.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~4428-4522) — make `cmd_plan_close` delegate to the plan layer for `plan_branch` plans.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC7 corruption and resume cases.

**Architecture Context:** Two plan-state systems exist today and neither
reads the other: the `ca-review-complete` marker plus the gitignored
`.aid-o/reports/*` (written by `cmd_plan_close` at `aid-fsm.sh:4428-4522`)
and the git-tracked `.aid-lifecycle/manifests|receipts` layer
(`lib/aid-lifecycle.sh`, canonical state resolver `aid_plan_closure_state` at
`:774-808`). PM directive: P064 must connect them explicitly.

The close transaction is a durable operation like any other: it acquires the
plan lock, records `plan-close` in the operation log under the key
`plan-close:<plan_id>:-:<attempt>:<plan_id>`, and follows the same
`intent → git_applied → state_committed` sequence — `git_applied` is stamped
when the lifecycle receipt (or abort record) commits, `state_committed` when
the marker is written. A crash between them is reconciled by finding the
committed receipt and writing only the marker. P064's operation-record
contract enumerates its own six commands; this step adds `plan-close` to that
enum and extends `lib/aid-plan-state.sh` accordingly — an additive change to
a P064 artifact, declared here rather than silently assumed.

**Implementation Detail:** Marker semantics are split so a closed plan cannot
be reported before the release happened:

- `.aid-o/work/plan-state/<plan_id>/plan-review-complete` — written at the
  end of Step 3 when all plan-final reviews are complete and the PM decision
  is still pending.
- `.aid-o/work/plan-state/<plan_id>/plan-close-complete` — written only after
  the PM decision exists, the merge or abort state is recorded, and the
  lifecycle receipt is committed.

`plan-close-check` verifies, in order: every EPIC has a terminal status;
every non-abandoned EPIC's merge commit is an ancestor of the plan branch;
the plan-final run directory contains the gate report and every required
review artifact bound to `candidate_sha`; no `DONE` EPIC state file has a
pending step (reusing the existing check at
`aid-plan-close-check.sh:370-401`); the queue and `active.md` are consistent
with the manifest; a plan-mode C4 decision exists for the same candidate and
the currently authoritative legacy release path passed; the PM decision
exists; the plan branch is an ancestor of the target branch when the decision
was `MERGE`; the tag state matches project policy; no `MERGE_HEAD` remains;
no operation record is left at `intent` or `git_applied`; and **no lock is
currently held**.

That last condition is about a *held* lock, not about a sidecar file
existing. `flock` releases an advisory lock when the descriptor closes, not
when the file is unlinked, so the `.lock` sidecars Step 1 creates persist on
disk for the life of the workspace by design — this repository already
carries such files under `.aid-o/metrics/`. Requiring their absence would
make plan-close unsatisfiable for every plan that ever ran a transaction. The
check therefore attempts a non-blocking `flock -n` acquire on each relevant
sidecar and fails only when the lock is still held by a live process, naming
that process. An earlier draft said "no `MERGE_HEAD`, lock file or
transaction intent remains", which read as file absence; the C0
cross-provider review caught the contradiction against Step 1.

**Owned-lock exception (added 2026-07-24 after C0 HIGH).** The close transaction
itself acquires the plan lock first, so a naive "no relevant lock is held" probe
would contend with its *own* descriptor and always fail — and releasing it before
the receipt and marker commit would destroy the transaction boundary the step
exists to provide. The check therefore **excludes exactly one lock: its own.**
The close transaction retains its lock FD and records that sidecar's identity
(canonical path, plus the FD it holds); the contention probe skips that one path
and `flock -n`-probes every *other* relevant sidecar. The exclusion is by exact
canonical path, not by "any lock this process holds", so a *different* lock held
by the same process still blocks. The lock is released only after the receipt and
the close marker are durably committed. Tests: (a) close succeeds while the
transaction holds its own plan lock; (b) close is blocked, naming the holder, when
a *separate* live process holds any other relevant sidecar; (c) close is blocked
when a different lock is held by the same process, proving the exclusion is
path-scoped rather than process-scoped.

The receipt bridge: after those checks pass, the close transaction commits
`.aid-lifecycle/receipts/<plan_id>.yaml` via `aid_lifecycle_plan_close`
(`lib/aid-lifecycle.sh:361-373`) **in the plan-mode plumbing path Step 5
establishes** — `commit-tree` plus a CAS `update-ref` onto the target ref,
with no checkout. Without that, the receipt commit reaches
`_aid_lc_isolated_commit` → `_aid_lc_require_target_branch` and refuses
whenever the target branch is checked out in another worktree, which is the
normal multi-worktree case; the plumbing mode is what makes AC7's close path
executable there. Only if that commit succeeds does
the transaction write `plan-close-complete` and transition the plan to
`CLOSED`.

For a `plan_branch` plan the receipt is **mandatory**, not best-effort. The
delivery bindings it depends on are written by Step 5 in one post-merge
pass, so by the time close runs, `aid_plan_closure_state` must be resolvable
to `delivered-but-unreconciled` (the normal pre-close state once every
required EPIC is delivered and review-accepted) or, on a resumed close,
`closing_pending_commit`; if it still reports `active`, that means a required
EPIC is undelivered and close exits 1 rather than declaring a plan closed
with no durable proof. `closing_pending_commit` is *not* the normal
pre-close state — it is returned only when an uncommitted receipt already
exists on disk (`lib/aid-lifecycle.sh:806-807`), i.e. after an interrupted
close — so requiring it would make a first, clean close impossible. Note that `aid-auto-pipeline.sh:259-278`
already creates a lifecycle manifest for new plans, so the
`lifecycle_manifest_absent` path is not an escape hatch for plans created
under the new model — it applies only to legacy-mode plans that pre-date the
lifecycle layer, where close completes with that reason recorded.

For plan mode, report freshness means the protocol-v2 delivery artifact is
bound to `candidate_sha`. The human Markdown projection is checked for
existence and freshness where the report-storage mode makes that meaningful
(`aid-plan-close-check.sh:158-163` already detects the gitignored case) but
can never make close pass on its own.

**Error Handling:** Any single failed check exits 1 naming the check; close
is never partially applied. On resume, the command revalidates Git, the
manifest, the PM decision, the evidence, the queue and the active state
rather than trusting an existing marker — an existing `plan-close-complete`
whose preconditions no longer hold is reported as `close_marker_invalid` and
exits 1.

**Edge Cases:**
- Unknown or unresolvable ancestry (a rewritten or missing ref) — blocks;
  unknown is never treated as merged.
- A plan closed by abort — `plan-close-complete` is written with the terminal
  reason and no merge or tag assertion; the target branch must be unchanged.
  **An aborted plan writes no lifecycle receipt.** `aid_lifecycle_plan_close`
  (`lib/aid-lifecycle.sh:361-373`) refuses while any required EPIC is
  undelivered, which is always true before a merge, so demanding a receipt
  here would make abort unclosable. Instead the close transaction writes an
  abort record — plan id, terminal reason, the candidate that was abandoned,
  and the unchanged target head — into the plan-final run directory and marks
  the lifecycle manifest `status: aborted` — a top-level property this step
  adds to `plan-lifecycle-manifest.schema.json`, which is
  `additionalProperties: false` and has no `status` today, so writing it
  without the schema change would produce an invalid manifest. The
  mandatory-receipt rule applies
  to `MERGE` decisions only; the C0 review flagged the earlier wording, which
  demanded a receipt on every close path.
- A stale `ca-review-complete` marker from legacy mode present on a
  plan-branch plan — reported and ignored for authority; the test asserts it
  cannot substitute for `plan-close-complete`.
- Crash after the receipt commit but before the marker write — resume finds
  the committed receipt, skips the commit, and writes the marker.
- `.aid-lifecycle` receipt commit fails because the working tree is dirty —
  exits 1; per `lib/aid-lifecycle.sh:692-698` a failed receipt commit must
  not be treated as done.

**Dependencies:**
- Depends on: Step 5 (merge or abort must precede close).
- Blocks: Step 11 (the dogfood run must close cleanly).

**Acceptance Criteria:**
- [ ] Individually removing or corrupting EPIC ancestry, the manifest, the
      gate report, a required review, the C4 decision, the PM decision, the
      merge or abort record, the queue state, the active state, the tag
      record or the final SHA binding each blocks close.
- [ ] Unknown ancestry blocks rather than passing.
- [ ] Re-running after a simulated crash reconciles state and writes exactly
      one atomic, head-bound close marker.
- [ ] A plan whose `.lock` sidecar files exist but are not held closes
      successfully; a plan whose lock is held by a live process is blocked
      with that process named.
- [ ] The owned-lock exception holds: close succeeds while the close
      transaction itself holds the plan lock (its own sidecar is excluded from
      the contention probe by exact canonical path); close is blocked when a
      separate live process holds any other relevant sidecar; and close is
      blocked when a *different* lock is held by the same process — proving the
      exclusion is path-scoped, not process-scoped. The lock is released only
      after the receipt and close marker are durably committed.
- [ ] `plan-close-complete` is absent until the final merge or a recorded
      abort exists.
- [ ] A committed `.aid-lifecycle` receipt is present after close for every
      `plan_branch` plan closed by a `MERGE` decision; a merged plan whose
      delivery bindings are missing exits 1 instead of closing. A plan closed
      by `ABORT` writes the abort record and `status: aborted` instead, and
      is not required to produce a receipt.

**Effort:** L
**AID Role:** backend

**EPIC 2: Steps 7-11 — Cutover, documentation, instruction sweep, dogfood**

### Step 7: In-flight inventory and default mode flip

**Objective:** Stamp every active plan with an explicit mode, make
`plan_branch` the default for new plans, and refuse to operate on a plan
whose mode is missing or mixed.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — add the `inventory` subcommand and the mode default.
- Create: `plugins/aid-orchestrator/defaults/policies/plan-boundary-policy.yaml` — the mode default, the lock lease seconds and the plan-final profile floor.
- Test: `plugins/aid-orchestrator/defaults/templates/plan.md` (lines ~10-20) — verify the existing `lifecycle_strict: true` emission still holds; no edit expected.
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (lines ~250-290) — call `plan-start` for new plans and stamp `mode` into the lifecycle manifest it already writes.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add AC8 mode cases.

**Architecture Context:** Roadmap D11 and §13 bound the migration
deliberately: no algorithm, just an inventory and an explicit stamp. This is
the step that flips the default, and it is deliberately last among the
mechanical steps so that nothing defaults to the new mode before the
end-to-end path exists.

**Implementation Detail:** `aid-plan-fsm.sh inventory` scans
`.aid-o/plans/P*.md` and `.aid-o/config/queue.yaml` for plans with at least
one EPIC that is not terminal, prints a table of plan id, EPIC statuses and
current mode, and with `--apply` writes `mode: legacy_epic_release_mode`
into each plan's **lifecycle manifest**,
`.aid-lifecycle/manifests/<plan_id>.yaml` — the git-tracked authority (see
`## Architecture`). A plan that already has a lifecycle manifest (every plan generated by
`aid-auto-pipeline.sh`, which writes one with `schema_version`, `repo_id`,
`plan_id` and `declared_epics`) gets `mode` added to that valid manifest. A
legacy plan with **no** manifest and no parseable EPIC declarations cannot be
given a schema-valid manifest — `plan-lifecycle-manifest.schema.json` is
`additionalProperties: false` and requires those four fields — so inventory
does not fabricate an invalid one: it stamps `mode` into the runtime
plan-state file and records the plan as `legacy-unverifiable`, exactly the
state `aid_plan_closure_state` already returns for such plans. No invalid
manifest is ever written. It never creates a plan branch for a legacy plan and never
migrates a plan mid-run.

New plans get the key at creation: `aid-auto-pipeline.sh` already writes a
lifecycle manifest (`:259-278`), and this step adds `mode` to what it writes,
defaulting to `plan_branch` per `defaults/policies/plan-boundary-policy.yaml`.
The `mode` property is added to the schema by **P064** Step 3; this step sets
the value. An unknown mode value fails schema validation at plan creation
rather than at branch time.

**The default flip must close the manifest-write escape hatch first.** Today
`aid-auto-pipeline.sh:265-278` fails closed only when the plan declares
`lifecycle_strict: true`; otherwise a failed manifest write emits a loud WARN
and proceeds with no manifest. That is correct for legacy plans, but once
`default_mode: plan_branch` is active it becomes exactly the silent downgrade
`## Architecture` forbids: no manifest means no mode declaration, which means
the plan runs legacy while everyone believes it is plan-branch. This step
therefore makes the WARN path fail closed whenever the resolved default mode
is `plan_branch`. `defaults/templates/plan.md:14` already emits
`lifecycle_strict: true` for new plans, so that half is verified rather than
changed. The mode driving the decision comes from
`defaults/policies/plan-boundary-policy.yaml`, not from the manifest that
just failed to write, which avoids a chicken-and-egg;
`AID_LIFECYCLE_MIGRATION=1` survives as an explicit, logged override. The
flip and the escape-hatch closure land together; neither is correct alone.

**The default flip is guarded on the gate table existing.** `plan_branch`
mode's gates stage resolves against a `gate_profiles` table, and P064 adds
that table only to this repository's self-host `.aid-o/config/execution.yaml`,
not to the `defaults/execution.yaml` that `/aid-init` distributes — so a
consumer project upgrading the plugin would flip to `plan_branch` with no
table and its gates stage would resolve against nothing. Step 7 therefore
makes the default conditional: `aid-auto-pipeline.sh` (and `/aid-init`)
resolve `default_mode` to `plan_branch` only when a `gate_profiles` block is
present in the project's `execution.yaml`, and fall back to
`legacy_epic_release_mode` with a logged `plan_branch_unavailable:
no_gate_profiles` otherwise. The self-host repo has the table (P064 Step 8),
so it flips; a fresh consumer does not until it runs the profile bootstrap.
`defaults/policies/plan-boundary-policy.yaml` carries three keys:
`default_mode: plan_branch`, `lock_lease_seconds: 10`, and
`plan_final_profile_floor: release`. Until this step, the default in the code
is `legacy_epic_release_mode`; this step changes the default and adds the
policy file so a target project can opt out.

`aid-auto-pipeline.sh` gains a call to `plan-start` when generating EPICs for
a plan that has no plan state, stamping the default mode. Existing behaviour
for plans already stamped legacy is unchanged.

**Error Handling:** A plan whose EPICs disagree about mode (some stamped,
some not) exits 1 with `mixed_mode` before any mutation. A plan id that
matches no plan file exits 1. `--apply` on a plan that already has a mode is
a no-op, not an error.

**Edge Cases:**
- A plan with all EPICs terminal but no close marker — listed in the
  inventory as `unclosed_legacy` and stamped legacy; P064 does not force it
  through the new path.
- A brand-new plan created after the flip — gets `plan_branch` with no
  operator action.
- A plan explicitly opted out via the policy file — respected; the mode is
  read from policy, not hard-coded.
- One-EPIC plans — no special case; they follow `task → plan → main` like any
  other, per roadmap D7.

**Dependencies:**
- Depends on: **P064** Step 7 (queue carries `plan_id` and `merge_target`),
  and Step 6 here (the full release path exists before the default flips).
- Blocks: Step 11 (dogfood needs the default in place).

**Acceptance Criteria:**
- [ ] A new one-EPIC plan follows `task → plan → main`, and the task branch
      is not an ancestor of the target branch before final authorization.
- [ ] Existing active plans are inventoried and stamped
      `legacy_epic_release_mode` without migration.
- [ ] New plans default to `plan_branch` when the project's `execution.yaml` has a `gate_profiles` block, and fall back to `legacy_epic_release_mode` with a logged `plan_branch_unavailable: no_gate_profiles` otherwise (Step 7).
- [ ] Missing, unknown or mixed mode exits non-zero before mutation.

**Effort:** M
**AID Role:** backend

### Step 8: Crash, conflict, hotfix and abort resilience fixtures

**Objective:** Prove that every transaction boundary converges after a crash
and that conflicts, hotfixes and aborts never produce a false completion.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add the AC9 resilience matrix.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — add the `AID_PLAN_FSM_CRASH_AFTER` test seam.

**Architecture Context:** Every command in this plan is specified as
`intent → git_applied → state_committed` (see `## Data Model` → Operation
record). This step is where that specification becomes an executable matrix
rather than a claim, covering each command at each boundary.

**Implementation Detail:** `aid-plan-fsm.sh` gains a single test seam:
when `AID_PLAN_FSM_CRASH_AFTER` is set to a phase name (`intent`,
`git_applied`), the command exits with code 99 immediately after recording
that phase. The seam is inert when the variable is unset, and the test
asserts that the seam does not exist in any code path reachable without it.

The matrix runs, for each of `epic-merge-to-plan`, `plan-finalize --stage
freeze` and `plan-merge-to-main`: crash after `intent` then resume (expect no
Git effect and a clean retry); crash after `git_applied` then resume (expect
the Git effect to be reused, state written, no duplicate). Conflict cases:
an EPIC-to-plan merge conflict and a target-branch merge conflict, each
asserting `CONFLICT` state, no recorded completion, and an unchanged target
branch. A hotfix case: a commit landing on the target branch after `sync`,
asserting the plan resynchronizes before it can freeze. An abort case:
`decision: "ABORT"` before the merge, asserting the target branch is
unchanged, the plan branch and evidence are preserved, and the terminal
reason is recorded.

Test fixtures use the existing helpers: `setup_test_evidence_dir` from
`scripts/tests/bats/test-helpers.bash:11-30` for a real temp repository on
`main`, and `mock_git_worktree` (`test-helpers.bash:37-66`) for the linked
worktree cases, both of which create real Git state rather than mocking it.

**Error Handling:** A resume that finds Git and state on opposite sides of a
boundary it cannot reconcile (for example a recorded merge commit that does
not exist) exits 5 and prints the exact reconciliation the operator must
perform. It never guesses.

**Edge Cases:**
- Crash during the tag step — covered by the Step 5 idempotent tag path; the
  matrix asserts no second tag.
- Crash while holding the lock — `flock` releases on process death, so the
  next command acquires it; the stale pid inside the lock file is
  informational.
- Two crashes in a row at the same boundary — the second resume behaves
  identically to the first; the matrix runs the resume twice.
- Published-history rollback — asserted as a new revert commit on the target
  branch, never a history rewrite; the test checks the target branch's first
  parent chain still contains the merge commit.

**Dependencies:**
- Depends on: **P064** Step 6 (`epic-merge-to-plan`), and Steps 1 and 5 here
  (candidate freeze and the CAS merge) — the three transactional commands.
- Blocks: Step 11 — the dogfood run should not be the first place a resume is
  exercised.

**Acceptance Criteria:**
- [ ] An EPIC merge conflict enters `CONFLICT` and records no completion.
- [ ] A pre-merge abort leaves the target branch unchanged and records
      terminal evidence.
- [ ] A hotfix on the target branch forces resynchronization before candidate
      freeze.
- [ ] Failure after the final Git merge but before the queue and close update
      is reconciled on resume.
- [ ] Published rollback uses a new revert commit, never a history rewrite.

**Effort:** M
**AID Role:** qa

### Step 9: Documentation, amendments and enforcement registry

**Objective:** Update every document that currently advertises the per-EPIC
release model, and record every new enforcement in the registry.

**Files:**
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

**Architecture Context:** MUST rule 16 of `skills/plan-writing.md` requires a
documentation step for any plan that changes workflow, and the roadmap's
"Required Documentation / Plan Updates" section names each amendment. The
enforcement registry requirement comes from `CLAUDE.md`: every new detection
capability must be registered with its type, source, instruction, severity
and surface, and its enforcement mechanism named at design time.

**Implementation Detail:** The P061 D8 amendment adds, verbatim:
`D8 superseded by P064 for post-P064 execution. EPIC-boundary full gates are
not the permanent model.` Its Bootstrap Fast Lane section
(`P061…md:177-230`) gains a note that its EPIC-boundary full-suite
requirement applies to P061's own construction only and is not a precedent.

The P062 amendment replaces `write_only_until: "P061 DONE+merged (all 6
EPICs)"` (`P062…md:13`) with a precondition naming P061 E1-E5, an explicit
done-or-defer disposition for E6 (which P061 itself defines as backlog at
`P061…md:704-706`), P064 DONE and merged, and at least one multi-EPIC plan
completed through `plan_branch` mode, with any deferral requiring a PM-signed
reason.

The Control System v2 roadmap gains `E9.5 / P064: Plan-Level Release
Boundary` between the E9 and E10 entries (`AID-control-system-v2-roadmap.md:144-149`)
with the reason: do not promote C4/E10 while the release cadence is still
EPIC-centred.

The topology amendment (`AID-control-system-v2-control-topology.md:364`)
distinguishes "one Auditor dispatch per plan" from "C3 independence is
blocking for every profile", and the dispatch budget section (`:258-269`)
changes from per-EPIC to per-plan accounting.

Registry rows (re-grounded 2026-07-24 against the current registry). **Three of
the rows the original draft listed as "new" ALREADY EXIST** — added by P064 /
Phase 1 — so this step VERIFIES/RECONCILES them, it does not re-add them
(re-adding a duplicate `id` is a hazard the acceptance below explicitly guards):
`plan_boundary_manifest`, `plan_branch_merge_target`, and
`plan_close_mechanical_check` are all present today. The **five genuinely new
rows this step adds** are `plan_final_gate_required`,
`plan_final_specialist_review`, `epic_specialist_review_exception`,
`plan_candidate_identity_binding` and `plan_merge_cas`. Each new row carries
`type`, `source` as `file:line`, `instruction`, `severity`, `surface`, `status`
and `verdict`, following the schema at `defaults/enforcement-registry.yaml:15-38`.
A blocking row whose `source: file:line` does not yet exist is exactly what the
honesty rule below forbids, so each new row is added in the same step that builds
its enforcing code.

Row severity must be honest, per AID-v3 principle §1 — a detector without
enforcement is decoration, and a registry row claiming enforcement that does
not exist is worse than no row. Rows backed by a script that exits non-zero are
`severity: blocking, status: active` with the enforcing `file:line` as `source`:
the two new ones here (`plan_candidate_identity_binding`, `plan_merge_cas`,
plus `plan_final_gate_required`), and the three pre-existing rows this step only
verifies (`plan_branch_merge_target`, `plan_boundary_manifest`,
`plan_close_mechanical_check`) whose blocking status is confirmed unchanged. `epic_specialist_review_exception` is a `pipeline.md` prose rule
with no validator, so it is recorded as `severity: advisory, surface:
llm-facing` — not blocking. `plan_final_specialist_review` is blocking only
for the artifact-presence and head-binding checks the Step 3 runner
actually performs; the dispatch-count assertion is test-enforced, not
runtime-enforced, and the row says so.

One enforcement gap is recorded rather than hidden: nothing in the FSM
compels a plan to reach `plan-finalize` at all. A PM who never runs it simply
has an open plan. The enforcement that does exist is negative and sufficient
for the release boundary — no path merges the plan branch to the target
branch except `plan-merge-to-main`, which requires a PM decision bound to a
frozen candidate — so an unfinalized plan cannot release. The row for this is
`advisory` and its description states the negative form.

`test-control-boundary.sh` exists because an earlier draft verified AC11
with three `grep -q` calls — one P061 phrase, one roadmap phrase and one
policy file — while AC11 claims far more. The C0 cross-provider review
flagged the gap. The check asserts every clause of AC11 against the **tracked**
enforcement registry, where each amendment is recorded as a row: the P061 D8
supersession note; the P062 precondition amendment naming P061 E1-E5, the E6
disposition and P064; the `E9.5` phase note; the topology T2 distinction
between one plan-final Auditor dispatch and blocking C3 independence; that
every `defaults/policies/*.yaml` `enforcement:` and `head_match_policy:`
value is byte-identical to its pre-P064 baseline (a checked-in fixture, so a
silent promotion fails); and that each relocated legacy control still exists.
It does not read the `docs/` or `.aid-o/` plan files, which are gitignored;
those edits are advisory and the registry rows are the durable assertion. Each clause reports its own pass or fail so a failure
names which claim broke.

**Durability note.** `.aid-o/` is gitignored (`git ls-files .aid-o/` returns
nothing), so an amendment written only into `.aid-o/plans/P061-*.md` or
`P062-*.md` is workspace-local and cannot serve as durable, reviewable
completion evidence. The plan-file edits are still made — they are what the
next reader of those plans sees locally — but the **machine-checkable**
assertion in AC11 targets only the one tracked, non-ignored surface,
`plugins/aid-orchestrator/defaults/enforcement-registry.yaml`.
`test-control-boundary.sh` reads that registry and nothing under `docs/` or
`.aid-o/`, so it behaves identically on a clean checkout; the plan-file edits
under those trees are advisory.

**Error Handling:** The registry rows are verified by the existing
`scripts/tests/bats/test-registry-ttl.bats` shipped-registry assertions
(required-key set, value shape, totals coherence); a row missing a required
key fails that suite. Documentation changes are verified by
`scripts/tests/test-instruction-consistency.sh` and
`scripts/aid-lint-skill.sh` via `scripts/tests/test-skill-lint.sh`.

**Edge Cases:**
- A skill file that is grandfathered in the lint test's exclusion list —
  `pipeline.md` is substantively revised here, so if it is grandfathered it
  must be removed from the GRANDFATHERED list per the `CLAUDE.md` rule.
- The registry's header total (`enforcements: 314` at
  `defaults/enforcement-registry.yaml:45` as of v2.62.1 — the draft's `293`
  predated P064/Phase-1 rows) — recomputed with `yq '.enforcements|length'`,
  not hand-incremented. Adding the five new rows takes it to 319.
- P062 is `write_only_until` its preconditions are met — amending it does not
  make it executable and must not change its status.

**Dependencies:**
- Depends on: **P064** Steps 5 and 9, and Steps 3 and 6 here (the
  enforcements being documented must exist and have known `file:line`
  anchors).
- Blocks: Step 10 — the instruction sweep builds on these updates.

**Acceptance Criteria:**
- [ ] `skills/pipeline.md` and `commands/aid-run.md` contain no instruction
      that a per-EPIC release review is the default, and the stale cross-plan
      enforcement claim is corrected.
- [ ] The P061 D8 and P062 precondition amendments are recorded in the
      **tracked** enforcement registry
      (`defaults/enforcement-registry.yaml`) and verified by
      `test-control-boundary.sh`; the corresponding `.aid-o/plans/` and
      `docs/` plan-file edits are made for local readers but are advisory,
      since both trees are gitignored.
- [ ] The Control System v2 roadmap E9.5 entry is recorded as a tracked
      registry note; the `docs/` roadmap edit is advisory.
- [ ] The five genuinely-new rows (`plan_final_gate_required`,
      `plan_final_specialist_review`, `epic_specialist_review_exception`,
      `plan_candidate_identity_binding`, `plan_merge_cas`) are added, and the
      three pre-existing rows (`plan_boundary_manifest`,
      `plan_branch_merge_target`, `plan_close_mechanical_check`) each appear
      exactly once (no duplicate `id`), all with every required key; the
      advisory plan-finalize gap row is recorded.
- [ ] `bash plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` passes.

**Effort:** M
**AID Role:** docs-writer

### Step 10: Agent-facing instruction sweep

**Objective:** Inventory every surface an agent actually reads or acts on,
make each lifecycle instruction mode-aware, and prove mechanically that no
unqualified per-EPIC release instruction survives.

**Files:**
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

**Architecture Context:** P064 changes what agents are supposed to *do* at
every boundary, and agents act on prose. The enforcement work in Steps 5 to
15 constrains the scripts, but nothing stops an agent from following an
obsolete instruction that still says "merge `task/E-*` to main" and reaching
the same wrong outcome through the prose path. This step closes that gap the
same way the rest of the plan closes code gaps — with a mechanical check, not
a promise. It is deliberately separate from Step 9, which updates the two
primary documents and the registry; this step is the exhaustive sweep across
every remaining surface.

**Implementation Detail:** The inventory enumerates every agent-facing
surface and assigns each exactly one disposition — `update`, `verified` (read,
found already correct, no change) or `no-scope` (explicitly out of scope,
with a reason). A surface with no disposition fails the check. The minimum
inventory:

| Surface | Expected disposition |
|---|---|
| `plugins/aid-orchestrator/skills/pipeline.md` | update (Steps 9, 10) |
| `plugins/aid-orchestrator/commands/aid-run.md` | update (Step 9) |
| `plugins/aid-orchestrator/commands/aid-plan.md` | update |
| `plugins/aid-orchestrator/commands/aid-init.md` | update |
| `plugins/aid-orchestrator/commands/aid-status.md` | update |
| `plugins/aid-orchestrator/commands/aid-do.md` | update |
| `plugins/aid-orchestrator/commands/aid-verify-plan.md` | update (CP1 review contract) |
| `plugins/aid-orchestrator/commands/aid-verify-implementation.md` | update (DONE review contract) |
| `plugins/aid-orchestrator/commands/aid-setup.md`, `aid-help.md` | verified or update |
| `plugins/aid-orchestrator/commands/aid-audit.md` | verified or update |
| `plugins/aid-orchestrator/commands/aid-stop.md` | verified or update |
| `plugins/aid-orchestrator/skills/run-management.md` | update |
| `plugins/aid-orchestrator/skills/agent-protocol.md` | update |
| `plugins/aid-orchestrator/skills/planner.md` | verified or update |
| `plugins/aid-orchestrator/skills/plan-writing.md` | update (MUST rule 16 documentation step) |
| `plugins/aid-orchestrator/skills/role-cards.md` | update (specialist dispatch relocation) |
| `plugins/aid-orchestrator/skills/{brainstorming,memory,memory-mcp,command-writing,skill-writing}.md` | verified or update |
| `plugins/aid-orchestrator/skills/setup/*.md` and `skills/visual-companion/SKILL.md` | verified — the completeness glob MUST recurse into skill subdirectories or these escape the sweep |
| `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md` | update (CP3 relocation) |
| `plugins/aid-orchestrator/agents/*.md` (8 agents: auditor, curator, gate-fixer, implementer, project-scanner, reporter, simplifier, verifier) | update for auditor, curator, simplifier, reporter; verified for the rest |
| `docs/extending-aid.md` | update (Step 9) |
| `CLAUDE.md` | update |
| `README.md`, `plugins/aid-orchestrator/README.md` | update |
| `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` | update (Step 9) |
| `.aid-o/config/execution.yaml` | update (Step 8) |
| `plugins/aid-orchestrator/defaults/hooks/pre-commit`, `pre-push` and their docs | update (Step 5) |
| release/changelog policy texts (`.aid-o/config/policies/release-policy.yaml` — note this file lives in the workspace, not under `defaults/policies/`, where no `release-policy.yaml` exists — and the CHANGELOG rules in `CLAUDE.md`) | update |
| prompt templates under `defaults/templates/**` and `defaults/prompts/**` mentioning merge, release, DONE, plan close, C3, C4 or delivery — inside the mechanical scope, individually dispositioned; `verifier-output-template.md:21` is a known `update` | update or verified, individually |

**Scope is instruction surfaces, not history.** The check runs over
`plugins/aid-orchestrator/{skills,commands,agents,defaults/templates,defaults/prompts}/**`
(recursing into `skills/setup/` and `skills/visual-companion/`) plus four
explicitly named files: `CLAUDE.md`, `README.md`,
`plugins/aid-orchestrator/README.md` and `docs/extending-aid.md`.
`defaults/templates/` and `defaults/prompts/` are inside the mechanical scope,
not merely listed in the inventory: they are rendered verbatim into agent
prompts, so an obsolete lifecycle reference there reaches an agent exactly
like one in a skill. `defaults/templates/verifier-output-template.md:21`
carries `cmd_done_advance review→release` today — an arrow form the ASCII
denylist patterns do not match, so the check's `done-advance review release`
pattern is extended to `done[-_ ]advance review\s*(→|->|to)?\s*release` to
cover both renderings. Everything else under `docs/` is out of scope and
the check must say so rather than silently skipping it, because `docs/`
is overwhelmingly history and specification, not instruction: at HEAD,
`docs/plans/archive/**` alone contributes 12 `aid-release.sh` hits from a raw
agent transcript, `docs/plans/2026-06-29-BACKLOG.md` contributes 24 `plan-close` hits,
and `docs/plans/AID-plan-level-release-boundary-roadmap.md` — this plan's own
source specification — contributes 11. None of those can carry a mode fork,
and none of them instructs an agent. Running the denylist across all of
`docs/` would produce 157 hits, the overwhelming majority unsatisfiable, and
would reproduce the exact "detector fires, nobody can satisfy it" outcome
this step exists to prevent. `CHANGELOG.md` is out of scope for the same
reason and is recorded as `no-scope` with that rationale.

`test-instruction-sweep.sh` then runs two mechanical checks over that scope.
First, an inventory completeness check: every file in scope must appear in
the inventory with a disposition, so a newly added surface cannot silently
escape the sweep. Second, a denylist of obsolete unqualified patterns:

```text
# run with: grep -nE  (all patterns are ERE)
git merge task/                      # any per-EPIC merge instruction
aid-release\.sh                      # any release invocation
done-advance review release          # per-EPIC release transition
plan-close                           # close outside a plan-final fork
```

Every pattern was derived from the text that actually exists, not from what
the obsolete instruction was assumed to look like. This matters: an earlier
draft of this step used `git merge task/E-[^ ]* (into )?main`, which matches
**nothing** in the repository, because the real instructions are templated —
`skills/pipeline.md:1571` reads
``git merge task/{epic_id}/main --no-ff`` and `commands/aid-run.md:324`
reads the same. A denylist that cannot see the two lines this plan explicitly
sets out to replace would let AC12 pass green with the obsolete instruction
fully intact — a detector without enforcement, which principle §1 of
`docs/plans/AID-v3-principles.md` forbids.

Baseline hit counts, measured at HEAD over the scope defined above (run the
same commands to reproduce; a divergence means the surfaces moved, not that
the check is wrong):

| Pattern | Hits in scope |
|---|---|
| `git merge task/` | 2 |
| `aid-release\.sh` | 6 |
| `done-advance review release` | 8 |
| `plan-close` | 13 |
| **Total** | **29** in the plugins tree, plus 1 in `CLAUDE.md` and 5 in `docs/extending-aid.md` |

One pattern from the earlier draft is deleted rather than kept as decoration:
`release after each EPIC` matches nothing repo-wide.

A match is a failure unless it is suppressed by one of exactly two
mechanisms — there is no third, informal one:

1. **Mode fork** — a `legacy_epic_release_mode` or `plan_branch` marker
   within the 15 preceding lines, which is how a legitimately mode-qualified
   instruction passes.
2. **Explicit allowlist** — a `# sweep-allow: <reason>` entry in
   `instruction-sweep-allow.txt`, keyed by `path:pattern` (not by line
   number, which would rot on every edit). The allowlist is part of the
   inventory review, so adding an entry is a visible decision rather than a
   silent skip, and the check prints every allowlisted hit it suppressed.

The three known legitimate mentions get allowlist entries with their reason:
`commands/aid-init.md:468` (documents the pre-push hook's own remedy text —
the hook really does print `aid-release.sh auto` at
`defaults/hooks/pre-push:42,44`), `skills/pipeline.md:987` (describes the
release guard's refusal behaviour, not an instruction to release), and
`skills/role-cards.md:340` (names the script as the release role's tool). An
earlier draft listed "record it in the inventory" as a third disposition
without specifying how an inventory entry suppresses a denylist hit — it did
not, and those three lines would have failed the check no matter what the
inventory said.

The check is honest about being lexical, not semantic: it catches the worst
obsolete text, not every possible paraphrase, and its output says so.

**Mode-aware instruction rule.** Every text describing lifecycle carries an
explicit fork rather than a single narrative:

```text
legacy_epic_release_mode: EPIC completes, releases, and merges to the target
                          branch — the pre-P064 behaviour, unchanged.
plan_branch:              EPIC merges into plan/Pxxx. Release, Auditor,
                          Curator, Simplifier, Reporter, C4 and the merge to
                          the target branch happen once, at plan final.
```

**Agent handoff contract.** `skills/agent-protocol.md` gains the exact
sentences an agent reports at each boundary, because most of the confusion
during P065 was not wrong code but unexplained state:

| Moment | What the agent must tell the user |
|---|---|
| After EPIC merge into the plan branch | "EPIC merged into `plan/Pxxx`. The plan stays open and the target branch is unchanged. No release decision has run." |
| Before candidate freeze | "Freezing the release candidate now — after this, any change invalidates the plan-final evidence and restarts the cycle." |
| After plan-final gates | "This is the single release gate run for the whole plan, at candidate `<sha>`." |
| Before merge to the target branch | "Waiting for a PM decision bound to candidate `<sha>` and target head `<sha>`. On approval: merge, tag, lifecycle receipt." |
| After merge | "Plan closed. Merge `<sha>`, tag `v<x.y.z>`, receipt committed at `.aid-lifecycle/receipts/<plan_id>.yaml`." |

**Backward compatibility text.** The inventory documents, in the plan
lifecycle sections of `pipeline.md` and `aid-run.md`, that P061, P062, P063,
P065 and every other in-flight or completed plan runs
`legacy_epic_release_mode` unless explicitly migrated; that P064 does not
retroactively alter their history or their evidence; that new plans created
after the Step 7 cutover default to `plan_branch`; and that a missing mode
or a missing runtime manifest fails closed rather than open.

**Error Handling:** The check exits 1 with the file, line and matched pattern
for each violation, and exits 2 when a surface is missing from the inventory,
so the two failure classes are distinguishable. It exits 0 with a count of
surfaces checked when clean. Because it is registered in
`run-all-tests.sh`, a regression in a later EPIC surfaces as a test failure
rather than as a stale instruction nobody reads.

**Edge Cases:**
- A legitimate mention of the old flow inside a legacy-mode fork or a
  historical note — allowed by the 15-line qualification window; the check's
  own test fixture covers both the qualified and unqualified form.
- A CHANGELOG entry describing past per-EPIC behaviour — `CHANGELOG.md` is
  history, not instruction, and is `no-scope` in the inventory with that
  reason.
- A new command or skill added by a later EPIC — the completeness check fails
  until it is given a disposition.
- An agent file that mentions release only in a plan-final context — passes
  the denylist and is marked `verified` rather than `update`.
- A pattern appearing inside a fenced code block that documents the legacy
  path — treated identically to prose; if it needs to survive, it needs the
  mode fork marker.

**Dependencies:**
- Depends on: Step 9 (the primary documents are updated there; this step
  sweeps everything else and adds the mechanical guard).
- Blocks: Step 11 — the dogfood run's fresh-agent simulation reads these
  surfaces.

**Acceptance Criteria:**
- [ ] Every agent-facing surface has a disposition of `update`, `verified` or
      `no-scope` in the inventory, and a surface with no disposition fails
      the check with exit 2.
- [ ] `test-instruction-sweep.sh` exits 0 over the repository, and exits 1
      with file, line and pattern when a fixture reintroduces an unqualified
      obsolete instruction.
- [ ] Every lifecycle instruction that survives carries an explicit
      `legacy_epic_release_mode` versus `plan_branch` fork.
- [ ] The agent handoff contract is present in `skills/agent-protocol.md`
      with all five boundary messages.
- [ ] The backward compatibility statement names P061, P062, P063 and P065 as
      legacy and states that P064 does not alter their history.
(The fresh-agent simulation is a Step 10 report deliverable, not part of
      this AC — it is manual and cannot be mechanically verified, so it is
      recorded in the dogfood report's `## Fresh-agent simulation` section as
      supporting evidence and asserted nowhere as an executable criterion.)

**Effort:** L
**AID Role:** docs-writer

### Step 11: End-to-end dogfood on a real multi-EPIC plan

**Objective:** Prove the whole path on a real plan run through `plan_branch`
mode, and produce the cadence metrics that show the change actually happened.

**Files:**
- Create: `plugins/aid-orchestrator/reference/P068-plan-branch-dogfood-report.md` — the recorded end-to-end run with commands, SHAs and counts, plus the subject-selection authorization as its first section, under `plugins/aid-orchestrator/reference/`, a non-`docs`-named tracked directory (`.gitignore:87`'s unanchored `docs/` matches `plugins/aid-orchestrator/docs/` too, so the report must avoid any `docs`-named dir).
- Modify: `.aid-o/config/counter.yaml` — reserve `P067` for the dogfood subject plan.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — add the AC10 invocation-count assertions over structured logs.
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — add the release entry.
- Modify: `CHANGELOG.md` — identical copy of the plugin CHANGELOG entry.

**Architecture Context:** P064 itself is implemented in legacy mode, because
the mechanism does not exist until EPIC 1 and 2 land. The dogfood therefore
runs on a separate, small follow-up plan (PM decision), exercising
`plan-start` through `plan-close-complete` on real branches in this
repository.

**Dogfood bootstrap topology (added 2026-07-24 after C0 HIGH) — resolves the
chicken-and-egg.** Before P068 is released, `main` does not yet contain
`plan-finalize` / `plan-merge-to-main`, and `aid-plan-fsm.sh` explicitly refuses
`--mode plan_branch` while they are absent. That creates a cycle the draft left
open: a P067 branch cut from `plan/P068` would carry P068's *unapproved*
implementation commits into `main` when the dogfood merges, while a P067 branch
cut from `main` would lack the commands the dogfood needs. Neither is acceptable.
The dogfood therefore uses an explicit **two-checkout isolation**:

1. **Tool worktree (P068 candidate, never merged by the dogfood).** A separate
   `git worktree` of the P068 candidate provides the *executables only*. Every
   dogfood command is invoked as
   `<p068-worktree>/plugins/aid-orchestrator/scripts/aid-plan-fsm.sh … --project-root <dogfood-checkout>`,
   so the new commands exist without their commits being present in the tree the
   dogfood merges.
2. **Dogfood checkout (clean, `main`-based).** P067's plan branch and EPIC
   branches are cut from `main`, contain only P067's own small tracked payload,
   and are what actually merges to `main`.
3. **Isolation proof, asserted not assumed.** Before the dogfood merge:
   `git log --oneline main..plan/P067` contains only P067 payload commits and
   **zero** P068 implementation commits, verified by asserting the P068 candidate
   commit range is disjoint from `main..plan/P067`
   (`git merge-base --is-ancestor` on each P068 commit must fail). The report
   records both SHAs and the command output.
4. **Resynchronise after.** Once the dogfood advances `main`, `plan/P068` is
   re-synchronised onto the new `main` (its own Step 1 `--stage sync`), so P068's
   candidate is re-frozen against reality rather than a pre-dogfood `main`.

This keeps the release boundary honest: the tool under test never smuggles itself
into the target branch as a side effect of testing itself.

**Implementation Detail:** Before anything else, reinstall the Git hooks in
the working repository. `defaults/hooks/pre-push` and
`defaults/hooks/pre-commit` are templates that `/aid-init` copies into
`.git/hooks/`; the copies in `.git/hooks/` are not updated when the templates
change, so the dogfood would otherwise run against the old, unexempted
pre-push guard and be blocked on its first push — reproducing the exact
failure Step 5 fixes. The report records the hook file hashes before and
after so a stale hook cannot be mistaken for a passing exemption.

**Dogfood subject selection is bounded, not deferred to taste.** A candidate
plan qualifies only if it meets every criterion: exactly 2 or 3 EPICs; no
EPIC touching a high-risk path from `lib/aid-gate-profile.sh:193-201`; no
dependency on another open plan; entirely inside this repository; and total
estimated effort at or below `M` per EPIC. If no existing open plan qualifies
— and at the time of writing none does, since P061 E4-E5, P062 and P065 each
fail at least one criterion — this step authors the subject plan through the
normal path (`/aid-plan write`) from a specification fixed here, so the
fallback is a bounded deliverable rather than an unspecified future choice:

> **Subject plan `P067-plan-branch-dogfood`** — type `regular`, mode
> `plan_branch`, two EPICs, no high-risk paths, **payload entirely in tracked
> files under `plugins/aid-orchestrator/`**, run with an explicit
> `--bump patch` so the release and tag path is genuinely exercised (a
> docs-only `--bump auto` would resolve to no bump and create no tag, which
> would not test the release transaction the dogfood exists to prove).
> Allocate its id from
> `counter.yaml` at the time (`P067` is reserved for it there; if the counter
> has moved on, take the next free id and record the substitution in the
> authorization artifact).
> **EPIC 1 (2 steps):** add a contributor reference page
> `plugins/aid-orchestrator/reference/artifact-types.md` listing every protocol-v2
> `artifact_type`, its producer script and its output path. A docs page under
> the plugin tree is **not** high-risk: `lib/aid-gate-profile.sh:193-201`
> matches only `aid-fsm.sh`, `aid-run-gates.sh`, `aid-release-policy.sh`,
> `aid-evidence-verify.sh`, `defaults/schemas/*`, `defaults/policies/*` and
> `agents/*.md` — none matches `docs/*.md`. A new `defaults/schemas/*` file
> was considered and rejected precisely because that glob makes it high-risk,
> which would disqualify the dogfood subject. AC: the page lists every enum
> member and `aid-lint-skill.sh` passes.
> **EPIC 2 (2 steps):** document the plan-branch lifecycle in
> `plugins/aid-orchestrator/README.md`. The subcommand names
> (`plan-finalize`, `plan-merge-to-main`, `plan-close-check`, `inventory`)
> are written inside a `plan_branch`-marked block so they do not trip the
> instruction sweep's `plan-close` denylist, and the sweep allowlist gains an
> entry for the help text; AC: `aid-lint-skill.sh` passes and
> `test-instruction-sweep.sh` stays green.

Every file touched is tracked, so the run produces a real commit, a real
`release:` preparation, a real tag and a real close — which a `.aid-o/`-only
payload could not (that tree is gitignored; `git ls-files .aid-o/` returns
nothing, and a no-bump preparation makes no commit at all). This closes CF2.
Deliberately **not** used as the payload: the `c3_dispatch` schema fix found
during this plan's own review — that is a real defect on `main` and must not
wait for a dogfood.

Both EPICs are mechanical, low-risk, confined to this repository and
independently useful, so the dogfood exercises the machinery without
inventing throwaway work. `P067` is reserved for it in
`.aid-o/config/counter.yaml` as part of this step.

The authorization and the final report live in one tracked file, because
evidence that vanishes on a clean checkout cannot support an acceptance
criterion — and both `.aid-o/` (`.gitignore:98`) and `docs/`
(`.gitignore:87`) are ignored wholesale. The report is
`plugins/aid-orchestrator/reference/P068-plan-branch-dogfood-report.md` with the authorization as its
first section, and this step places it under the tracked plugin tree
(`plugins/aid-orchestrator/reference/`), a **non-`docs`-named** directory.
`.gitignore:87` is the unanchored pattern `docs/`, which matches a `docs`
directory at any depth — including `plugins/aid-orchestrator/docs/` — so the
plugin's own `docs/` would be ignored too; `reference/` matches no ignore
rule and tracks normally.

Step 9's amendments face the same constraint: `AID-control-system-v2-roadmap.md`
and `AID-control-system-v2-control-topology.md` live under `docs/`, which is
gitignored, so they cannot be clean, tracked evidence. The plan-file edits are
still made for local readers, but AC11's machine-checkable assertion targets
only the unambiguously tracked surface,
`plugins/aid-orchestrator/defaults/enforcement-registry.yaml`, verified by
`test-control-boundary.sh`. An amendment nobody can see on a clean checkout
is not treated as evidence. Working artifacts of the run may still land under
`.aid-o/work/evidence/P068/dogfood/`, but nothing there is the sole evidence
for an AC.

Selection is recorded before the run in the report's `## Authorization`
section, carrying the
chosen `plan_id`, the criteria evaluation for every candidate considered and
a PM `authorized_by` field. The run may not start without it, so "which plan
did we dogfood on, and why that one" is answerable from evidence rather than
memory.

Then, for the selected plan, declare `mode: plan_branch` in its lifecycle manifest
`.aid-lifecycle/manifests/<plan_id>.yaml` — never in the plan file, see
`## Constraints` — run it end to
end, and record in the report: the exact command sequence; `plan_base_commit`,
each `epic_base_commit`, each merge commit, `candidate_sha`,
`target_head_sha` and the final merge SHA; the plan-final `gates_report.json`
profile and duration; the dispatch count for each specialist; the C4 decision
and PM decision; and the tag created.

The metrics assertion runs over the structured invocation logs for a
three-EPIC fixture and asserts: broad release profile `3 → 1`;
Auditor, Curator, C4 and PM release decision `3 → 1` each; per-EPIC CP3 final
pair `3 → 0`, replaced by one plan-level C2 final review; Simplifier,
Reporter and plan-close `1 → 1`; version and tag exactly once; zero
intermediate legacy release-stack invocations; and every PM-approved
exception counted separately with its reason.

A rollback drill is performed and recorded: abort a plan-final run before the
merge, verify the target branch is unchanged and the plan branch and evidence
survive, then resume and complete.

**Error Handling:** If any stage of the dogfood fails, the failure and its
resolution are recorded in the report rather than removed — a dogfood that
hides a failure proves nothing. A failure that requires a code change returns
to the owning step; the dogfood is re-run from `plan-start` on a fresh plan
branch.

**Edge Cases:**
- The dogfood plan turns out to be single-EPIC — acceptable for the
  `task → plan → main` assertion but not for the cadence metrics; the metrics
  assertions run against the three-EPIC fixture regardless.
- A real conflict during the dogfood — recorded, resolved through the
  `CONFLICT` path, and the resolution commit triggers the checks again;
  this is a better outcome than a clean run.
- The dogfood reveals a missing enforcement — it is added to the registry and
  to the owning step before P068 is marked DONE.

**Dependencies:**
- Depends on: Steps 7, 8, 9 and 10 (default mode, resilience, documentation,
  instruction sweep).
- Blocks: nothing — this is the last step.

**Acceptance Criteria:**
- [ ] Dogfood isolation is proven, not assumed: every dogfood command runs from
      the separate P068 tool worktree via `--project-root <dogfood-checkout>`;
      `git log --oneline main..plan/P067` contains only P067 payload commits and
      zero P068 implementation commits (each P068 candidate commit fails
      `git merge-base --is-ancestor` against `plan/P067`); and `plan/P068` is
      re-synchronised onto the advanced `main` after the dogfood merge. The
      report records the SHAs and the command output.
- [ ] The dogfood report's `## Authorization` section exists and is committed
      before the run, naming the chosen plan, the per-candidate criteria
      evaluation and a PM `authorized_by` value.
- [ ] The chosen plan meets every eligibility criterion, or
      `P067-plan-branch-dogfood.md` was created to the scope fixed in this
      step.
- [ ] The Git hooks in `.git/hooks/` are reinstalled from the templates
      before the run, with before/after hashes recorded.
- [ ] At least one multi-EPIC plan completes using `plan_branch` mode, with
      every SHA recorded in the report.
- [ ] The Auditor, Curator, Simplifier and Reporter each ran exactly once, at
      plan final.
- [ ] Full gates ran once, at plan final; EPIC branches merged into the plan
      branch; the plan branch merged to the target branch after PM approval.
- [ ] The structured invocation logs show every cadence count required by
      AC10, with exceptions counted separately.
- [ ] The rollback drill is recorded and the target branch was never left in
      an inconsistent state.

**Effort:** L
**AID Role:** e2e

## Testing Strategy

One mandatory integration suite carries this plan:

```bash
command -v bats >/dev/null 2>&1 || exit 1
bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats
```

P064 created `test-aid-plan-release-boundary.bats` for the substrate and
integration half and must stay green throughout; this plan adds a second
suite for the release half rather than growing the first past the point where
one CI job can hold it. Both are excluded from the aggregate
`run-all-tests.sh` run and given dedicated CI jobs, for the reason P064
established: the `bash-tests` job is capped at `timeout-minutes: 5`
(`.github/workflows/ci.yml:24`) and its last green run used 264s.

A missing `bats` is a failure, not a skipped green run — and this is
**already true at HEAD**: `run-all-tests.sh:140-149` hard-fails unless
`AID_ALLOW_MISSING_BATS=1`, and the `DELEGATED_LOG` exclusion mechanism
already exists. Step 1 does not re-implement either; its only runner change
is to add `test-aid-plan-final-boundary.bats` to the existing exclusion list
so it does not also run inside the capped `bash-tests` job
(`.github/workflows/ci.yml:24`, ~264s of its 300s used). Claiming to add the
hard-fail would describe work already done.

The suite is discovered automatically by the runner's `bats/test-*.bats`
glob (`run-all-tests.sh:54-57`), but auto-discovery is not sufficient: the
`bash-tests` job is capped at `timeout-minutes: 5`
(`.github/workflows/ci.yml:24`) and the last green run of `main` spent 264s
in that step. Adding the repository's most expensive new suite to that job
would push unrelated suites over the limit. Step 1 therefore gives the suite
its own CI job with its own budget.

**Fixture strategy.** Every test uses a real temporary Git repository, not a
mock. `setup_test_evidence_dir` (`scripts/tests/bats/test-helpers.bash:11-30`)
already creates a temp project with `git init -b main` and an initial commit;
`build_default_init_args` (`:47-61`) supplies the real seven-positional
`cmd_init` signature so tests exercise the production path rather than a
parallel test mode; `mock_git_worktree` (`:69`) creates a real
`git worktree add` for the linked-worktree lineage cases.

**Spy strategy.** AC4 requires proving that callers do *not* fire. The suite
uses the logging-spy pattern from
`scripts/tests/bats/test-aid-c3-dispatch.bats:1059-1068`: a temp directory
prepended to `PATH` containing executables that append their argv to a log
file and then `exec` the real target where behaviour is still needed. Spied
targets: `aid-release.sh`, `git tag`, `git push`, and one marker script per
specialist dispatch. `legacy_epic_release_mode` is the positive inverse
fixture — the same assertions, expecting non-zero counts, so a spy that never
fires because it was wired wrong is caught.

**Test tiers.**

| Tier | Coverage | Where |
|---|---|---|
| Unit | lock, state transitions, operation reconcile, manifest validation, profile split | `test-aid-plan-release-boundary.bats`, isolated temp dirs, no Git needed for the pure-state cases |
| Integration | branch lineage, merge idempotence, queue claim, plan-final stages, CAS merge, close | same suite, real temp repositories |
| Contract | protocol-v2 registration and fixtures | `scripts/tests/test-protocol-validate.sh` including `--consistency` |
| Resilience | crash/resume matrix, conflict, hotfix, abort | same suite, driven by `AID_PLAN_FSM_CRASH_AFTER` |
| Metrics | cadence counts over structured logs | same suite, three-EPIC fixture |
| Instruction | agent-facing surface inventory + grep denylist | `scripts/tests/test-instruction-sweep.sh`, registered in `run-all-tests.sh` |
| Dogfood | real multi-EPIC plan | Step 11, recorded evidence |

**Regression protection for touched shared files.** `aid-fsm.sh`,
`aid-run-gates.sh` and `aid-release-policy.sh` are all on the high-risk path
list (`lib/aid-gate-profile.sh:193-201`), so every EPIC of this plan that
touches them resolves to at least `standard` at its own boundary and raises
the plan-final floor. Their existing suites — `test-aid-fsm.bats` (1919
lines), `test-release-policy.bats` (1221 lines),
`test-aid-run-gates.bats` (1643 lines), `test-queue-revalidation.bats`
(278 lines), `test-plan-close.bats` (292 lines),
`test-aid-plan-close-check.bats` (564 lines) — must stay green; each is
named in the acceptance criteria of the step that touches its subject.

**AC verification template.** Every `bats --filter` verification captures the
output, checks the exit code *and* asserts a non-zero `1..N` TAP plan line,
so a not-yet-written test can never be misreported as present. This is the
template P063 adopted after PM review and it is reused verbatim here.

**Quarantine-aware green bar (v2.62.1).** While the P066 quarantine holds, the
green bar for this plan is the **relevant targeted / non-quarantined suites**,
never the broad quarantined `bats_all` aggregate. Concretely: `test-aid-plan-final-boundary.bats`,
`test-aid-plan-release-boundary.bats`, and the touched-file suites named in each
step's acceptance criteria (`test-aid-fsm.bats`, `test-release-policy.bats`,
`test-aid-run-gates.bats`, `test-queue-revalidation.bats`, `test-plan-close.bats`,
`test-aid-plan-close-check.bats`, `test-c0-plan-review.bats`, and the two new
`test-instruction-sweep.sh` / `test-control-boundary.sh`) must pass at the
reviewed HEAD. The quarantined broad gates are **never asserted `pass`**: their
state is recorded honestly (`waived` / `profile_excluded` / `unverifiable`) and,
where a plan-required dimension is theirs, satisfied by a marked
targeted-substitute receipt (the `quarantine_substitutes[]` channel in Step 2's
gate report). No step's acceptance may read a quarantined broad gate as green,
and no substitute may be labelled a broad-suite pass. When P066 lifts the
quarantine, the broad gates run normally and this carve-out is inert.

## Success Criteria

- A four-EPIC plan run end to end invokes the broad gate profile once, the
  Auditor once, the Curator once, C4 once and the PM merge decision once,
  versus four times each before P064/P068.
- No EPIC branch reaches the target branch; only the plan branch does, after
  a PM decision bound to an exact candidate and target SHA.
- At most one version commit and one tag exist per plan (none for a no-bump plan), created on the final
  merge commit.
- A crash at any transaction boundary converges on resume without a duplicate
  merge, release commit, tag, queue transition or close marker.
- `plan-close-complete` cannot exist for a plan whose merge or abort has not
  happened. Every plan closed by `MERGE` has a committed `.aid-lifecycle/`
  receipt; a plan closed by `ABORT` has an abort record and
  `status: aborted` instead, because the receipt predicate can never be
  satisfied before a merge.
- Every C0-C4 policy mode in `defaults/policies/` is byte-identical before
  and after this plan, proven by `test-control-boundary.sh` rather than by
  review.
- No agent-facing surface instructs a per-EPIC release or a
  task-branch-to-target-branch merge outside an explicit
  `legacy_epic_release_mode` fork, proven by `test-instruction-sweep.sh`.
- The three carried findings are addressed by a named step: CF1 (abandon path)
  and CF2 (tracked dogfood payload) are closed; CF3's blocking half (graph
  absence) is already resolved in code, so its named step delivers only the
  semantic `absent_pre_generation` refinement.
- `test-aid-plan-final-boundary.bats` passes, `test-aid-plan-release-boundary.bats`
  from P064 stays green, and every relevant targeted / non-quarantined bats suite
  stays green. **While the P066 quarantine holds, the broad `bats_all` aggregate is
  NOT required green** — it is recorded honestly
  (`waived` / `profile_excluded` / `unverifiable`, never `pass`) with their marked
  targeted substitutes, per *Test Execution Cadence and Quarantine*.

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
## Acceptance Criteria

Plan-level acceptance criteria. AC1 through AC6 are the roadmap's AC1-AC11,
restated with executable verification patterns and renumbered for this plan;
the roadmap's AC1-AC5 are P064's. AC7 is added for the agent-facing
instruction sweep, which the roadmap did not anticipate but which a lifecycle
change of this size requires — agents act on prose, so an obsolete
instruction bypasses every mechanical enforcement in the steps below. Each
criterion maps to the step that owns it. Every `bats --filter` pattern
captures the output, checks the exit code *and* asserts a non-zero `1..N` TAP
plan line, so a not-yet-written test cannot be misreported as present.

- [ ] AC1: Candidate freeze and fix invalidation work — plan final
      synchronizes the recorded target branch, prepares version metadata and
      freezes exact SHAs; any subsequent candidate change invalidates gates,
      C2, C3, utility reports, C4 and the PM decision and transitions to
      `PLAN_FIX`; an accepted specialist fix proves the full rerun loop; and
      a target-branch advance during review blocks the merge. (Step 1,
      Step 3, Step 5)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC1:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC2: Exactly one real plan-final release profile runs — the plan-final
      `gates_report.json` proves the exact candidate SHA, profile `release`
      including the full floor, a non-empty command log with durations, all
      expected and plan-required gate ids executed, zero required gates in
      `excluded_gates`, and no duplicate second broad run under a `full`
      label. (Step 2)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC2:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC3: Plan-level reviews run once and against the full plan — the C2
      final review covers `plan_base_commit..candidate_sha` including a
      defect seeded in the first EPIC, each specialist dispatches exactly
      once on the final successful attempt, every other enabled plan utility
      is counted explicitly, outputs leave the candidate and worktree
      unchanged, and missing, stale, wrong-plan or wrong-candidate output
      cannot satisfy the runner. (Step 3)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC3:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC4: Plan-mode C4 uses identity, not directory names — every input
      names the plan id, final run id, candidate SHA, target ref and head and
      the protocol artifact type; C4 consumes the run-scoped delivery
      artifact; an EPIC evidence directory or a copied EPIC pack fails
      identity validation; a retry creates a new run directory; and P064-owned
      identity mismatch always blocks regardless of C4 policy mode.
      (Step 4)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC4:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC5: PM authorization and final merge are atomic — missing, `FIX`,
      `ABORT`, stale, malformed, wrong-plan, wrong-candidate and wrong-target
      decisions each exit non-zero leaving the target branch unchanged; only
      a fresh plan-scoped `MERGE` decision permits the compare-and-swap
      merge; and a concurrent target advance loses the swap. (Step 5)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC5:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC6: Release, version, tag and push occur once — no intermediate EPIC
      creates a version commit or tag, version preparation is part of the
      frozen candidate, the final merge verifies tree identity and creates one
      tag on the final merge commit with one push action, resume creates no
      duplicate, and pushing a `plan/*` branch does not trigger the
      premature-release path. (Step 1, Step 5)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC6:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC7: Plan close is truly final and recoverable — individually removing
      or corrupting EPIC ancestry, the manifest, the final gate report, a
      required review, the C4 decision, the PM decision, the merge or abort
      record, the queue state, the active state, the release or tag record
      and the final SHA binding each blocks close; unknown ancestry blocks;
      and re-running after a simulated crash writes exactly one atomic
      head-bound close marker only after the final merge or a recorded abort.
      (Step 6)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC7:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC8: Single-EPIC and in-flight modes are unambiguous and durable — a
      new one-EPIC plan follows `task → plan → main` and its task branch is
      not an ancestor of the target branch before final authorization;
      existing active plans are inventoried and stamped
      `legacy_epic_release_mode` in their git-tracked lifecycle manifests
      without migration; new plans default to `plan_branch` where `gate_profiles` exists (else legacy, logged); missing, unknown
      or mixed mode exits non-zero before mutation; and deleting
      `.aid-o/work/plan-state/<plan_id>/plan-boundary-manifest.json` does not
      downgrade a `plan_branch` plan to legacy, because mode is reloaded from
      `.aid-lifecycle/manifests/<plan_id>.yaml` or the command fails closed.
      (Step 5, Step 7)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC8:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC9: Conflict, abort, hotfix and resume paths preserve truth — an EPIC
      merge conflict enters `CONFLICT` and never records completion, a
      pre-merge abort leaves the target branch unchanged with terminal
      evidence, a hotfix forces resynchronization before freeze, failure after
      the final merge but before the queue and close update is reconciled on
      resume, and published rollback uses a new revert rather than a history
      rewrite. (Step 8)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC9:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC10: Decommissioning metrics prove the cadence change — for a
      three-EPIC fixture the structured invocation logs show the broad
      release profile at 1, Auditor, Curator, C4 and PM release decision at 1
      each, the per-EPIC CP3 final pair at 0 replaced by one plan-level C2
      final review, Simplifier, Reporter and plan-close at 1, version and tag
      exactly once, zero intermediate legacy release-stack invocations, and
      every PM-approved exception counted separately with its reason.
      (Step 11)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "out=$(bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats --filter 'AC10:'); ec=$?; [ $ec -eq 0 ] && echo \"$out\" | grep -qE '^1\\.\\.[1-9]'"
    expected_exit: 0
  ```

- [ ] AC11: The control-v2 boundary is preserved — P064 relocates legacy
      controls to plan final without deleting them, the existing C0-C4 policy
      modes are unchanged, and the topology T2 and P061/P062 amendments are present in the tracked
      enforcement registry and machine-checkable via `test-control-boundary.sh`
      before **P068** is marked DONE (the `docs/` plan-file edits are advisory,
      since `docs/` is gitignored). (Step 9)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "bash plugins/aid-orchestrator/scripts/tests/test-control-boundary.sh"
    expected_exit: 0
  ```

- [ ] AC12: Agent-facing lifecycle instructions are mode-aware and no
      obsolete per-EPIC release instruction remains unqualified — every
      command, skill, agent, doc and prompt surface carries a disposition of
      `update`, `verified` or `no-scope` in the instruction surface
      inventory; the grep denylist finds no unqualified
      `git merge task/{epic_id}/main`, per-EPIC `aid-release.sh`,
      `done-advance review release` or `plan-close` instruction outside an
      explicit mode fork; every new plan-level command is documented with
      purpose, preconditions, outputs and failure mode; the agent handoff
      contract is present; and the mechanical
      instruction sweep passes. The verification pattern below is the
      executable pass predicate; the fresh-agent simulation is a Step 10
      report deliverable recorded as supporting evidence, asserted nowhere as
      an automated criterion, so AC12 is self-contained. (Step 10)
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "bash plugins/aid-orchestrator/scripts/tests/test-instruction-sweep.sh"
    expected_exit: 0
  ```

## Next Steps

Current status (2026-07-24, v2.62.1):

1. **P064 and Phase 1 are DONE.** The plan-branch substrate P068 consumes exists
   and is merged; the Phase-1 fail-closed hardening (IMP-263/269/270/262 and the
   lineage/freshness batch) is released locally as v2.62.1.
2. **P068 has been re-grounded against local main at v2.62.1** — every consumed
   contract re-verified, the Step 2 quarantine collision, the Step 3 schema
   target and the Step 9 counts/rows corrected, and the cadence/quarantine and
   handoff sections added. `file:line` citations carry a re-grep note (they
   predate Phase 1's edits).
3. **CF3 is not a blocker.** A missing `plan-graph.json` no longer makes the C0
   review `unverifiable` (the bridge seals it as a zero-byte manifest entry), so
   P068 can run its own C0 today; Step 1 only *semantically refines* the absent
   case to `plan_graph: absent_pre_generation` and resolves plugin-relative
   contract paths.
4. **Next action, after explicit PM approval: regenerate the P068 EPICs** from
   this re-grounded plan, as a chain **EPIC 2 → EPIC 1** (EPIC 2, the cutover,
   depends on EPIC 1, the plan-final release). Nothing is generated, run, or
   pushed before that approval. On regeneration, still re-grep every `file:line`
   by symbol first, and pick the dogfood subject under CF2 (a small *tracked*
   change under `plugins/aid-orchestrator/`, recorded in the dogfood report's
   `## Authorization` section before the run).
