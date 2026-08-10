---
status: ready-for-p064-plan-writing
created: 2026-07-12
last_reviewed: 2026-07-12
review_basis: five independent SOL reviews + repository-grounded reconciliation
owner: PM
scope: AID Orchestrator control-flow roadmap
---

# AID Plan-Level Release Boundary Roadmap

## Executive Summary

AID must stop treating every EPIC as a mini-release. The target model is:

```text
EPIC = work increment
PLAN = release / review / full-validation unit
```

Today the process spends too much time at every EPIC boundary: broad gates,
Auditor, Curator, C4 and PM merge handling repeat per EPIC, while evidence
repair and plan-close drift add more work later. Simplifier, Reporter and
plan-close are already intended as plan-boundary activities; P064 keeps them
there and makes that boundary mechanically real. The current mixture creates
long wall-clock time, repeated report/evidence churn, and plans that are
technically "done" in parts but operationally not closed.

The new model introduces a plan branch and a plan-final boundary:

```text
main
  -> plan/Pxxx
       -> task/E-xxx-1_n
       -> task/E-xxx-2_n
       -> ...
  -> plan-final gates/review/release decision
  -> merge plan/Pxxx -> main
```

Per EPIC work remains protected by targeted/risk-based checks. Full gates and
the specialist review stack move to the end of the plan.

## Non-Negotiable Decisions

### D1. Plan Is The Release Unit

The plan, not the EPIC, is the default release boundary.

- EPICs are implementation slices.
- EPICs merge into the plan branch.
- The plan branch merges to `main` only after plan-final gates, plan-final
  specialist reviews, the currently authoritative release decision, and PM
  approval bound to the exact candidate and target SHAs.

### D2. Auditor / Curator / Simplifier / Reporter Run Only At Plan Final

Auditor, Curator, Simplifier, and Reporter must not run by default at EPIC
boundaries.

They run at the end of the whole plan.

No "recommended per-EPIC specialist review" escape hatch by default. If a PM
explicitly asks for an exceptional mid-plan specialist review, it must be
recorded as a PM exception, not treated as normal pipeline behavior.

Rationale: these specialists are expensive, mutate evidence, create review
loops, and currently contribute to the snowball effect. Their value is highest
when reviewing the full plan outcome.

### D3. Full Tests Run At Plan Final By Default

Full gates are plan-final by default.

Per EPIC:

- run targeted / standard checks according to risk,
- do not run `bats_all` / full test suites by default,
- do not run release-equivalent gates by default.

If an EPIC appears to require full tests before plan final, the agent must stop
and ask the PM:

```text
I recommend running full tests for this EPIC because: <specific reason>.
This is not the default path. Confirm?
```

No silent escalation to full tests at every EPIC boundary.

P061 risk detection remains mandatory, but its output is split by boundary:

- `epic_required_profile` selects targeted/standard checks needed before merge
  into the non-released plan branch,
- `plan_final_required_profile` accumulates the strongest required final
  profile across all EPICs,
- a resolver result of `full` or `release` raises the plan-final floor; it does
  not silently start a full suite at the EPIC boundary,
- if the agent believes full validation is required before merging an EPIC into
  the plan branch, it must request explicit PM confirmation and record the
  decision.

Unknown production surfaces fail closed: they require safe targeted critical
checks and raise the plan-final floor to `full` or `release`. They do not become
a reason to reintroduce full-suite-per-EPIC automatically.

### D4. Keep The First Version Simple

Do not solve every future branch/release mode in the first implementation.

Required first version:

- plan branch mode,
- a durable parent plan state machine,
- EPIC branches merge into plan branch,
- one plan-final release profile that subsumes the full gate floor,
- plan-final specialist reviews,
- plan-mode C4 evidence at plan final,
- plan-close consistency as a real gate.

Out of first version:

- cross-plan train releases,
- multi-plan batching,
- partial deploy channels,
- advanced protected branch integration,
- automatic rollback orchestration.

### D5. Replace The Old EPIC Release Ritual, Do Not Layer On Top

P064 must remove the old default behavior where every EPIC behaves like a
release. It must not add a plan branch while still running the full
Auditor/Curator/Simplifier/Reporter/C4/PM-release stack at every EPIC boundary.

The old flow may remain only as an explicitly named compatibility mode:

```text
legacy_epic_release_mode
```

New multi-EPIC plans must default to:

```text
plan_branch
```

This is a cadence cutover, not an early deletion of legacy detection. Until E10
calibration and E11 cutover:

- legacy checks with unproven replacement coverage remain available,
- they run once at plan final rather than once per EPIC,
- plan-mode C4 runs in its current policy mode (`observe`/`dual_run`) alongside
  the plan-final legacy release decision,
- E10 decides which C0-C4 mechanisms may become blocking,
- E11 removes or aliases legacy checks whose unique detection value is proven
  to be zero.

### D6. P064 Is A Required Bridge Before E10

E10 must not promote the control system while the release cadence is still
EPIC-centered. P064 is therefore an E9.5 bridge between current E9 work and E10
promotion.

### D7. One-EPIC Plans Still Use The Same Model

A one-EPIC plan is still a plan:

```text
task/E-xxx-1_1 -> plan/Pxxx -> main
```

Do not special-case one-EPIC plans back into direct EPIC-to-main release unless
the plan explicitly uses `legacy_epic_release_mode`.

### D8. Freeze One Candidate And Invalidate On Every Change

Plan-final validation is always bound to an immutable `candidate_sha` and the
observed `target_head_sha` of `main`.

- Version/changelog preparation happens before the candidate is frozen.
- Gates, reviews, C4 and PM decision name the same `candidate_sha`.
- Any code, config, test, generated file or release-metadata change after the
  freeze invalidates all plan-final evidence and returns the plan to
  `PLAN_FIX`.
- Plan-final evidence and human summaries are written outside the candidate Git
  tree. Producing evidence must not move `candidate_sha` or dirty the product
  worktree.
- Curator/Auditor/Simplifier fixes are never patched into an already approved
  candidate. After an accepted fix, the plan must rerun the required plan-final
  cycle against a new candidate SHA.
- If `main` advances before merge, authorization is stale and plan-final must
  synchronize, refreeze and rerun.

### D9. Release, Version, Tag And Push Happen Once Per Plan

Intermediate EPIC completion must not run `aid-release.sh`, create a release
commit, tag, push or refresh plugin cache.

Plan-final uses a two-phase release:

1. prepare version/changelog changes on `plan/Pxxx`, then freeze the candidate;
2. after PM approval, atomically merge the approved candidate into the expected
   `main` head, verify the resulting tree, create the tag on the final main
   merge commit, then push/refresh cache according to project policy.

All operations must be idempotent so a resumed run cannot create duplicate
release commits or tags.

### D10. P064 Changes Cadence, E10/E11 Change Control Authority

P064 hard-enforces only the new mechanical release-boundary invariants:

- branch lineage and clean integration worktree,
- exact candidate/target SHA binding,
- plan manifest identity,
- PM authorization,
- idempotent merge/close transaction.

Existing C0-C4 findings retain their current `observe|dual_run|blocking` policy
until E10. In particular, P064 must not globally promote today's
`head_match: unknown` behavior. Exact SHA is nevertheless mandatory for the new
plan manifest, candidate authorization and final merge transaction because
those are P064-owned identity invariants, not an E10 finding-policy promotion.

### D11. First-Version Concurrency And Migration Are Explicitly Bounded

- Existing in-flight plans continue as `legacy_epic_release_mode`; v1 does not
  migrate them mid-run.
- New plans created after cutover default to `plan_branch`.
- Multiple plan branches may exist, but v1 serializes plan-branch merges,
  plan-finalization and writes to shared queue/active state.
- Parallel EPIC implementation is not enabled by P064, but the manifest must
  not make it impossible later; dependencies and active EPICs are represented
  as collections rather than one irreversible global `current_epic` cursor.

## Current Problem

### Current Effective Model

Current AID behavior is still largely EPIC-centered:

```text
EPIC work
-> per-EPIC broad gates and CP3 final review
-> EPIC DONE/review
-> Auditor / Curator
-> C4 + PM merge decision
-> release/version/merge EPIC
-> Simplifier / Reporter / plan-close once at the final plan checkpoint
```

Plan-level machinery exists, but mostly as bookkeeping:

- `queue.yaml`,
- `active.md`,
- delivery/boundary reports,
- plan-close marker,
- evidence consistency checks.

It is not yet the primary release authority.

### Why This Is Slow

The current model repeats expensive work too often:

- full or broad gate runs at every EPIC boundary,
- Auditor/Curator/C4 and final CP3 review at every EPIC boundary,
- repeated stale evidence regeneration,
- repeated Curator/Auditor fix loops,
- repeated PM merge decisions,
- plan-close drift after the fact.

The root issue is cadence, not only timeout values.

P061 and P063 are necessary but not sufficient:

- P061 decides which gate profile to run.
- P063 records gate runtime baselines and prevents blind timeout retry loops.
- This roadmap decides when expensive validation should run.

Expected reduction for a normal four-EPIC plan after P061/P063/P064:

- broad full/release gate cadence: `4 -> 1`, except PM-approved exceptions,
- Auditor/Curator/C4/PM release cadence: `4 -> 1`,
- Simplifier/Reporter/plan-close: `1 -> 1` (correct placement, not a count saving),
- release commit/version/tag: `1 -> 1`, but only at the true plan boundary.

## Target Operating Model

### Step Level

Purpose: validate the local implementation slice.

Default checks:

- scope / allowed paths,
- CP2 or equivalent step verifier,
- targeted tests selected by changed paths,
- syntax / cheap deterministic checks relevant to the touched surface.

Must not run by default:

- full test suite,
- release-equivalent gates,
- Auditor,
- Curator,
- Simplifier,
- Reporter,
- C4 release decision.

### EPIC Level

Purpose: validate that one implementation slice is coherent enough to merge
into the plan branch.

Default checks:

- all steps completed,
- targeted or standard gate profile according to risk,
- plan-required gate floor if declared,
- evidence pack freshness for that EPIC,
- no scope/branch/evidence corruption,
- record the strongest accumulated `plan_final_required_profile`,
- merge EPIC branch into plan branch.

Must not run by default:

- full gate profile,
- release profile,
- the current two-reviewer CP3 full-EPIC final review,
- Auditor,
- Curator,
- Simplifier,
- Reporter,
- PM release decision.

Exceptional full tests:

- allowed only after explicit PM confirmation,
- must include reason,
- must be recorded in evidence as an exception.

The EPIC boundary may still run cheap, targeted semantic/wiring checks needed to
prove the slice is internally coherent. The old full-diff CP3 final review moves
to plan final; it must not survive under another alias as an unconditional
per-EPIC dispatch.

### Plan Final Level

Purpose: decide whether the whole plan is complete and can merge to `main`.

Required checks:

- all EPICs in the plan completed and merged into the plan branch,
- no EPIC branch left unmerged unless explicitly abandoned,
- plan branch is synchronized with the exact target `main` SHA,
- version/changelog preparation is complete,
- one immutable `candidate_sha` is frozen,
- exactly one resolved plan-final profile runs; `release` subsumes `full` and
  must not rerun the same broad suites a second time,
- plan-level C2 final semantic/integration review runs,
- C3 audit at plan level,
- Curator at plan level,
- Simplifier at plan level,
- Reporter at plan level,
- plan-mode C4 decision at plan level and, before E10 promotion, the relocated
  legacy plan-final release decision,
- plan-close consistency check,
- PM `MERGE / FIX / ABORT` decision.

Only after this can `plan/Pxxx` merge to `main`.

If any specialist-approved fix changes the candidate, plan final transitions to
`PLAN_FIX`; all head-bound evidence is invalidated and the gate/review cycle
starts again. Reporter runs only after the final non-mutating review pass.

## Branch Model

### Branches

```text
main
plan/Pxxx
task/E-xxx-1_n
task/E-xxx-2_n
...
```

### Flow

1. Plan starts.
2. AID creates `plan/Pxxx` from `main`.
3. AID records the plan branch and target SHAs in the parent plan state.
4. Each EPIC branch starts from the atomically observed current `plan/Pxxx`.
5. EPIC implementation runs on `task/E-xxx-y_n`.
6. EPIC boundary checks run in targeted/standard mode.
7. An idempotent transaction merges the EPIC branch into `plan/Pxxx`.
8. Queue/manifest state records `merged_to_plan` only after Git ancestry proves it.
9. Next dependency-ready EPIC starts from the updated plan head.
10. Last EPIC completes.
11. `main` is synchronized into the plan branch; conflicts return to integration.
12. Version metadata is prepared and `candidate_sha` is frozen.
13. Plan-final gates and reviews run against that exact SHA.
14. PM approves that candidate against the recorded target SHA.
15. An idempotent compare-and-swap transaction merges `plan/Pxxx` to `main`.
16. Tag/push/cache refresh run once, then the plan closes atomically.

### Why Plan Branch Is Worth The Change

Git itself is not the hard part. The conceptual model is simpler than today's
mini-release-per-EPIC behavior.

The implementation complexity exists because current AID code assumes:

```text
task/E-* -> main
```

The new model requires:

```text
task/E-* -> plan/Pxxx -> main
```

Affected areas:

- `aid-fsm.sh init`,
- branch clean-tree guard,
- base commit calculation,
- queue dependency revalidation,
- evidence freshness,
- `done-advance`,
- C4 release policy,
- task branch cleanup,
- `active.md`,
- plan-close,
- generated PM summaries.

This is a large but necessary architectural change.

### Durable Parent Plan State

P064 adds a parent plan state, separate from each EPIC's existing FSM. Minimum
states:

```text
OPEN
EPIC_INTEGRATION
PLAN_SYNC
PLAN_GATES
PLAN_REVIEW
PLAN_FIX
AWAITING_PM
PLAN_MERGING
CLOSED
ABORTED
CONFLICT
```

The parent state owns the plan branch, target branch, candidate SHA, target SHA,
EPIC membership/status, plan-final run and merge/close transaction. EPIC FSMs
remain responsible for step execution and local evidence.

Every mutating lifecycle command uses a durable operation record:

```text
intent -> git_applied -> state_committed
```

On resume it must inspect Git refs, `MERGE_HEAD`, existing merge commits and the
operation record, then converge idempotently. It must never repeat a merge,
release commit, tag, queue transition or close marker merely because the prior
process crashed after performing Git work.

For v1, shared plan-finalization and queue writes are serialized by a lock/lease.
This is intentionally simpler than attempting optimistic multi-writer support.

## Control System V2 Mapping

### C0 Plan Contract

C0 must know:

- plan id,
- plan branch name,
- EPIC list,
- EPIC order,
- dependency graph and active EPIC set,
- total EPIC count,
- which EPICs are pending/running/merged/abandoned/superseded,
- plan-final gate policy,
- whether plan branch mode is enabled.

Required new/updated artifact:

```text
plan-boundary-manifest.json
```

This must be a protocol-v2 artifact with schema validation, `revision.head_sha`,
freshness checks, and a type-specific contract. The JSON below shows its
type-specific payload; the standard protocol-v2 envelope (`protocol_version`,
`artifact_type`, `identity`, `revision`, `status`, `provenance`) is mandatory.
It is an enforcement input, not a Reporter markdown summary.

Minimum fields:

```json
{
  "plan_id": "P064",
  "plan_branch": "plan/P064",
  "target_branch": "main",
  "plan_base_commit": "<sha>",
  "target_branch_head_at_start": "<sha>",
  "target_branch_head_at_candidate_freeze": "<sha-or-null>",
  "plan_branch_head": "<sha>",
  "candidate_sha": "<sha-or-null>",
  "plan_state": "EPIC_INTEGRATION",
  "epics": ["E-064-1_4", "E-064-2_4", "E-064-3_4", "E-064-4_4"],
  "active_epics": ["E-064-2_4"],
  "total_epics": 4,
  "is_plan_final": false,
  "mode": "plan_branch",
  "epic_required_profile": "standard",
  "plan_final_required_profile": "release",
  "epic_runs": [
    {
      "epic_id": "E-064-1_4",
      "run_id": "R-E064-1",
      "task_branch": "task/E-064-1_4/main",
      "epic_base_commit": "<plan-head-at-epic-start>",
      "epic_merge_commit": "<sha-or-null>",
      "evidence_dir": ".aid-o/work/evidence/E-064-1_4/R-E064-1",
      "status": "merged_to_plan"
    }
  ],
  "plan_final_run_id": "R-P064-final-1",
  "plan_final_evidence_dir": ".aid-o/work/evidence/P064/R-P064-final-1"
}
```

The type-specific schema must enforce legal state transitions, unique ordered
EPIC IDs, status enums, SHA formats, path containment, dependency consistency,
`merged_to_plan` ancestry, candidate/target binding and conditions under which
plan-final fields may be non-null. A copied EPIC pack placed under a plan path
is invalid because identity and subject scope do not match.

Runtime plan state and the mutable manifest live in an ignored AID work
directory and are written atomically. They must not dirty the product worktree.
Every plan-final attempt receives a new immutable run directory; retries never
overwrite prior evidence.

Old files such as `.aid-o/reports/Pxxx-boundary.md` may remain human reports,
but they are not enforcement inputs.

Authoritative plan-final outputs live in the immutable run evidence directory
and do not enter the candidate Git tree. Reporter must dual-emit a protocol-v2
delivery artifact there; C4 consumes that artifact, not a commit-dependent
Markdown file or `ca-review-complete` marker. Human Markdown reports are
projections. A project may publish them after release through a separate
metadata/evidence channel, but that publication cannot alter or authorize the
reviewed candidate.

### C1 Deterministic Gates

C1 must resolve profiles by boundary without duplicating broad suites:

```yaml
step: targeted
epic: targeted|standard
plan_final: release
```

`release` is the single final profile and includes all gates required by `full`
plus release-only checks. It is not `full` followed by another execution of the
same suites.

Per-EPIC deterministic risk analysis still applies, but it strengthens local
targeted/standard checks and the accumulated plan-final floor separately. A
plan-declared gate remains mandatory; it must either run locally because it is
an EPIC integration requirement, or be recorded as a mandatory plan-final gate.
No required gate may disappear as `profile_excluded`.

Discretionary full gates outside the resolver/plan-floor contract need explicit
PM confirmation.

### C2 Semantic Review

C2 final review runs at plan final by default over
`plan_base_commit..candidate_sha`.

Local C2 checks that are required to validate wiring, behavior, or an
acceptance contract inside an EPIC remain local checks. P064 moves the expensive
final semantic review cadence, not every small semantic/wiring assertion.

The current two-agent CP3 full-EPIC review is part of this final C2 cadence and
must be removed from default EPIC completion. Per-EPIC final semantic review is
exceptional and PM-approved only.

### C3 Independent Audit

C3 / Auditor dispatches exactly once at plan final. This is an intentional P064
cadence decision. Applicability remains profile-aware until E10:

- high/mixed/security/data-loss/release-process plans require full C3
  independence according to the existing topology,
- other plans still receive the one PM-requested plan-level Auditor pass, but
  C3 blocking semantics are not silently expanded before E10.

P064 must amend topology decision T2 and the dispatch budget to distinguish
"one Auditor dispatch per plan" from "C3 independence is blocking for every
profile". Supporting roles remain utilities, not release authorities.

No default per-EPIC C3 run. A mid-plan C3 run is a PM exception and must be
recorded as such.

### C4 Release Decision

C4 produces one plan-mode release decision at plan final.

It must evaluate the plan branch, not each EPIC branch.

Required plan-mode contract:

```bash
aid-release-policy.sh --plan P064 \
  --run R-P064-final-1 \
  --candidate-sha <sha> \
  --target-ref main \
  --target-head-sha <sha> \
  --evidence-dir .aid-o/work/evidence/P064/R-P064-final-1
```

The plan-mode contract must define required/profile-gated/advisory inputs,
per-EPIC roll-up, profile-hash aggregation, invalidation, waiver scope and exact
plan identity. Reporter/Simplifier applicability is derived from plan-final
configuration and plan-review state, not the old EPIC `ca-review-complete`
marker.

Plan-mode Reporter input is a protocol-v2 delivery artifact inside the current
plan-final run. The old committed `.aid-o/reports/Pxxx-delivery.md` check is a
legacy-mode compatibility path, not plan-mode authority.

An EPIC evidence pack must not satisfy plan-final C4. Before E10, C4 obeys its
existing observe/dual-run/blocking policy while the relocated legacy release
checks remain active once at plan final. After E10 promotion, C4
`release_ready:true` becomes the single eligibility authority. P064 always
hard-blocks candidate/target/manifest identity mismatch independently of C4
policy.

## Required AID Changes

### 1. Plan Branch Lifecycle

Add deterministic commands/helpers for:

- `plan-start`: create `plan/Pxxx` from target branch,
- `epic-start`: create `task/E-*` from current `plan/Pxxx`,
- `epic-complete`: finish EPIC work without release-to-main,
- `epic-merge-to-plan`: merge task branch into plan branch,
- `plan-finalize`: run plan-final gates/reviews/C4/PM summary,
- `plan-merge-to-main`: merge plan branch to target branch after PM approval.

Do not hide this inside prose instructions only.

All six commands must be idempotent, accept/derive an operation ID, acquire the
appropriate plan/shared-state lock, and persist `intent -> git_applied ->
state_committed`. Repeating a command after a crash must reconcile existing Git
and state rather than perform the action twice.

Negative requirements:

- `task/E-*` for a plan-branch plan fails if it was created from `main` instead
  of the atomically observed current `plan/Pxxx`,
- a task created from a stale plan head fails before work starts,
- resume and linked-worktree execution perform the same branch/base checks as a
  fresh start,
- branch origin is recorded by `epic-start`; first-EPIC equality between main
  and plan SHA must not make a manually created branch look authoritative.

### 2. Plan Boundary Manifest

Add a machine-readable manifest that survives context loss.

Producer:

- generated from plan/EPIC chain,
- refreshed when EPICs are generated,
- updated on each EPIC merge into plan branch.
- updated atomically only after Git proves the merge result.

Consumer:

- FSM,
- gate resolver,
- plan-final runner,
- C4 release policy,
- reporter.

The manifest is not trusted merely because a file exists. Each consumer must
validate protocol type, plan identity, mode, canonical path, current operation
state and the relevant exact SHA.

### 3. FSM Boundary Awareness

FSM must distinguish:

```text
step boundary
epic boundary
plan-final boundary
release boundary
```

Today too much behavior is tied to EPIC boundary. The new behavior must be
explicit.

Do not overload the EPIC `done-advance review -> release` state with plan state.
Add a durable parent plan FSM and split responsibilities:

- intermediate EPIC completion: validate EPIC and merge to plan branch,
- plan-final release: run plan-level C4, PM decision, and merge to main.

Intermediate EPIC completion must not require EPIC-scoped C4 release decision,
plan-level PM release decision, or the specialist stack.

The plan FSM must include explicit `PLAN_FIX`, `CONFLICT`, `ABORTED` and
`PLAN_MERGING` transitions. A fix commit invalidates the current candidate and
all downstream evidence. A conflict never counts as a completed merge.

### 4. EPIC Merge Target

Change EPIC release flow:

```text
task/E-* -> plan/Pxxx
```

not:

```text
task/E-* -> main
```

At EPIC completion, AID should report:

```text
EPIC complete and merged into plan/Pxxx.
Plan remains open.
No plan-final release decision has run yet.
```

Evidence must record:

- source task branch,
- plan branch before merge,
- plan branch after merge,
- merge commit,
- EPIC evidence dir,
- whether the EPIC was merged, abandoned, or superseded.

`merged_to_plan` is set only when the EPIC merge commit/tree is an ancestor of
the declared plan branch. `state: DONE`, a deleted task branch, or queue
`status: completed` is not sufficient merge evidence.

### 5. Plan-Final Runner

Add a plan-final command or FSM subflow:

```bash
aid-fsm plan-finalize Pxxx
```

or equivalent.

Responsibilities:

- acquire the plan-finalization lock,
- verify all EPICs merged into plan branch,
- synchronize the recorded target `main` into the plan branch,
- prepare version/changelog metadata without tagging or pushing,
- freeze `candidate_sha` and `target_head_sha`,
- create a new immutable plan-final run,
- run exactly one resolved `release` profile,
- run plan-level C2 final review,
- request and validate Auditor, Curator and Simplifier outputs through the
  orchestrator/controller (the shell FSM does not fabricate LLM dispatch),
- run any enabled plan-boundary utility such as Scanner exactly once; a tracked
  write from any utility is treated as a candidate-changing fix,
- return to `PLAN_FIX` and invalidate evidence if an approved fix changes HEAD,
- dispatch Reporter only after the final non-mutating review pass; its
  authoritative output stays in the immutable evidence run and cannot mutate
  the candidate,
- run relocated legacy release checks once and plan-mode C4 in its configured
  policy mode,
- produce PM plan-final summary,
- block until a plan-scoped PM decision bound to candidate and target SHAs,
- atomically merge only that candidate into only that expected target head,
- tag/push/cache-refresh once according to project policy,
- close the plan only after Git and state reconciliation succeeds.

The plan-final evidence dir must be separate from EPIC evidence:

```text
.aid-o/work/evidence/Pxxx/R-Pxxx-final-N/
```

An optional `current-plan-final-run` pointer may identify the latest attempt,
but prior attempts are immutable and remain auditable.

### 6. Specialist Dispatch Rules

Default:

```text
Auditor / Curator / Simplifier / Reporter = plan-final only
```

Remove language that implies these are normal per-EPIC release steps.

Also remove or redirect the current unconditional per-EPIC CP3 full-diff pair,
EPIC-scoped C4 invocation, EPIC PM release summary and `aid-release.sh` caller.
Poison/spying tests must prove these callers are not invoked in `plan_branch`
mode. Their compatibility path remains available only in
`legacy_epic_release_mode`.

If a PM manually asks for a mid-plan specialist review, record it as:

```text
mid_plan_specialist_review_exception
```

It must not become the default.

### 7. Plan-Close Consistency

Plan-close must be a real mechanical gate.

It must verify:

- all EPICs are done,
- all EPIC branches are merged to plan branch,
- plan branch has plan-final evidence,
- no `DONE` fsm-state has pending steps,
- reports are fresh,
- queue/active state is consistent,
- plan-mode C4 decision exists and the currently authoritative release path
  passed for the same candidate,
- PM decision exists,
- plan branch merged to main if final release was approved.
- release/tag state is consistent with project policy,
- no unfinished `MERGE_HEAD`, lock or transaction intent remains.

For plan mode, report freshness means the protocol-v2 delivery artifact is
bound to the candidate SHA. A human Markdown projection is not release
authority and cannot make close pass by itself.

Plan-close marker semantics must be split or ordered so they cannot report a
closed plan before release is truly done:

- `plan-review-complete`: plan-final reviews are complete, PM decision pending
  or merge not yet performed,
- `plan-close-complete`: PM approved or aborted, merge/abort state is recorded,
  queue/active/report/FSM state is consistent.

If a single marker is kept, it must only be written after C4, PM decision, and
the final merge/abort state are complete.

Marker creation must be atomic and bound to the final plan and target SHAs.
Unknown/unresolvable ancestry blocks. On resume, the command revalidates Git,
manifest, PM decision, evidence, queue and active state rather than trusting an
existing marker.

### 8. PM Summary

PM summary must be plan-level by default.

Required sections:

- what the whole plan delivered,
- which EPICs ran,
- what was skipped at EPIC level and why,
- plan-final gates result,
- plan-final specialist review summary,
- remaining backlog,
- merge decision.

The summary must distinguish `reviewed_candidate_sha`, `approved_target_sha`,
final main merge SHA and release/tag status. It must never imply that an
intermediate EPIC was released.

### 9. Queue And Dependency Semantics

Queue state must distinguish at least:

```text
pending
running
merged_to_plan
released_to_main
abandoned
superseded
blocked
```

Same-plan dependency readiness is proven against the declared `plan/Pxxx`
target. Cross-plan release dependencies are proven against `main`. The target
must come from plan state, not the current checkout and not a hard-coded
`main|master|HEAD` fallback.

Required behavior:

- atomic claim of the next dependency-ready EPIC,
- no lost updates to queue/active/manifest,
- stale claim recovery after process death,
- no `merged_to_plan` based only on DONE bookkeeping,
- a failed/aborted plan pauses dependent cross-plan work,
- queue pickup occurs only after the corresponding transaction reaches
  `state_committed`.

### 10. Target Drift, Hotfixes And Conflicts

Hotfixes land on `main` first. Every active plan records that target drift and
must synchronize before candidate freeze. Synchronization/conflict-resolution
commits invalidate prior plan-final evidence.

The final merge is compare-and-swap:

- expected old main SHA equals the PM-approved `target_head_sha`,
- plan branch head equals the PM-approved `candidate_sha`,
- otherwise merge returns non-zero without moving `main`.

EPIC-to-plan conflicts enter `CONFLICT`; no merge/status/queue completion is
recorded while `MERGE_HEAD` or unmerged paths exist. Abort/retry is deterministic
and any resolution commit triggers the appropriate checks again.

### 11. Release And Versioning Integration

Add plan-aware release interfaces instead of letting `aid-release.sh` discover
an arbitrary EPIC state file. The interface receives explicit plan state,
candidate SHA and target SHA.

Update:

- `aid-release.sh` or its replacement,
- `aid-run.md` and pipeline release callers,
- pre-push hook behavior on `plan/*`,
- version/changelog preparation,
- tag and push timing,
- plugin-cache refresh instructions.

Pushing a plan branch must not force a premature release commit or tag.

### 12. Failure, Abort And Manual Recovery

First-version automatic rollback remains out of scope, but manual recovery is
specified:

- before main merge: abort leaves main unchanged, preserves plan branch and
  evidence, and records terminal reason;
- after main merge: published history is repaired by a new revert/hotfix, never
  destructive reset;
- failure after Git merge but before state update is reconciled idempotently on
  resume;
- abandoned/superseded EPICs require PM-approved reason and dependency impact;
- partial EPIC commits remain isolated unless deliberately merged into the plan
  branch.

### 13. In-Flight Cutover Rule

At P064 activation, run an inventory of active plans:

- existing active/DONE-review plans are stamped
  `legacy_epic_release_mode` and finish through the old path,
- newly created plans default to `plan_branch`,
- missing or mixed mode fails before mutation,
- v1 offers no mid-plan migration command.

This bounded rule replaces a complex migration algorithm while keeping every
active plan explicit.

## Required Documentation / Plan Updates

### Update P061

P061 currently contains Bootstrap Fast Lane D8:

```text
targeted per step, but full suite at every EPIC boundary
```

This must be amended.

New intended state:

- P061 E3 may still run under current bootstrap rules if P064 is not yet
  implemented.
- P061 E4-E5 should run under the new P064 plan-level model if P064 is
  implemented first.
- Full gates move from every EPIC boundary to plan-final boundary by default.
- Per-EPIC full gates require explicit PM confirmation.
- P061 risk detection produces separate EPIC integration and accumulated
  plan-final floors; a high-risk result must not silently restore full tests at
  every EPIC boundary.

Required amendment:

```text
D8 superseded by P064 for post-P064 execution.
EPIC-boundary full gates are not the permanent model.
```

Specific sequencing:

- P061 E3 may complete as bootstrap selector work before P064.
- P061 E4-E5 are a PM-approved dogfood exception: after P064 lands, they should
  run under plan-branch/plan-final cadence.
- P061 E6 is explicitly backlog/optional in the current P061 source. Record a
  disposition; do not pretend it is a required sixth executable EPIC.
- Any P061 language that implies full suites at every EPIC boundary is
  superseded after P064.

### Update P062 / E10

E10 must not promote the old per-EPIC heavy model.

Required amendment:

```text
E10 promotion is blocked until plan-level release boundary is either:
1. implemented, or
2. explicitly deferred by PM with a written reason.
```

Recommended: do not run E10 until P064 is implemented and dogfooded on at
least one multi-EPIC plan.

Hard precondition for E10:

```text
P061 E1-E5 DONE + merged; P061 E6 has an explicit done/defer disposition;
P064 DONE + merged; and at least one multi-EPIC plan completed through
plan_branch mode. Any deferral requires a PM-signed reason.
```

P062's current wording "all 6 P061 EPICs" must be amended because P061 itself
defines EPIC 6 as backlog rather than part of its executable release chain.

E10 calibration must compare the intended plan-final cadence. It must not
calibrate or promote a temporary per-EPIC heavy mode.

### Update P063

P063 remains valid.

Optional amendment:

```text
P063 runtime baselines are used by plan-final gates as well as EPIC gates.
```

Do not expand P063 into plan-branch work.

### Update Control System V2 Roadmap

Insert this roadmap as a new phase between current P063/P061 continuation and
E10 promotion:

```text
E9.5 / P064: Plan-Level Release Boundary
```

Reason:

```text
Do not promote C4/E10 while release cadence is still EPIC-centered.
```

This update must be made in the Control System v2 roadmap before P062/E10 is
run, otherwise the roadmap still advertises a direct E9 -> E10 promotion path.

Also amend the canonical topology/constraints:

- distinguish one plan-final Auditor dispatch from risk-gated C3 independence,
- record the PM cadence decision without silently promoting C3 blocking for
  low-risk profiles,
- update dispatch budgets from per-EPIC to per-plan accounting,
- state that P064 relocates legacy checks but E10/E11 still own control
  promotion/removal.

### Update `aid-run.md` / Pipeline Docs

Replace language implying per-EPIC release review is default.

New language:

```text
EPIC completion validates and merges work into the plan branch.
Plan-final performs release review and PM merge decision.
```

Update all active callers and wording, not only the narrative:

- CP3 full-diff dispatch,
- Auditor/Curator dispatch,
- `done-advance review release`,
- C4 invocation,
- PM summary options,
- `aid-release.sh`, branch merge and queue pickup,
- pre-push release guard,
- plan-close ordering.

### Update Enforcement Registry

Add enforcement rows for:

- `plan_branch_merge_target`,
- `plan_boundary_manifest`,
- `plan_final_gate_required`,
- `plan_final_specialist_review`,
- `plan_close_mechanical_check` if not already active,
- `epic_specialist_review_exception`.

### Explicit Decommission / Relocation Map

P064 is incomplete until every current expensive caller has one named outcome:

| Current behavior | `plan_branch` outcome | Compatibility outcome |
|---|---|---|
| Per-step CP2/local checks | retain targeted | retain |
| Per-EPIC CP3 full-diff pair | relocate to plan-final C2 | retain in legacy mode |
| Per-EPIC broad gates | targeted/standard only; accumulate final floor | retain in legacy mode |
| Per-EPIC Auditor/Curator | relocate to one plan-final dispatch | retain in legacy mode |
| Per-EPIC C4 | plan-mode once at final | retain in legacy mode |
| Per-EPIC PM MERGE/FIX/ABORT | remove; EPIC only completes into plan branch | retain in legacy mode |
| Per-EPIC release/version/tag | remove; prepare/tag once at plan final | retain in legacy mode |
| Simplifier/Reporter | remain once at plan final | existing plan checkpoint |
| Scanner/other registered plan utility | remain once at plan final; tracked writes invalidate candidate | existing plan checkpoint |
| plan-close | move after C4, PM and final merge/abort | existing legacy ordering |

Poison/spying tests must verify zero `plan_branch` invocations of every row marked
"relocate" or "remove" at intermediate EPIC completion.

## Recommended Implementation Order

Current known state:

- P061 E1 done.
- P061 E2 done or effectively ready.
- P061 E3-E5 not complete; E6 is backlog/optional.
- P062 / E10 written but not executed.
- P063 written and in review.
- hotfixes for plan-close/audit-log are done or being merged.

Recommended order:

### Phase 0 — Stabilize Current Work

1. Finish and merge current P061 E2 branch cleanly.
2. Include hotfixes:
   - audit-log clean-tree guard,
   - plan-close-check wiring,
   - reporter-disabled narrow skip fix.
3. Ensure plugin cache is in sync.

Exit criteria:

- current branch clean,
- P061 E2 merged or consciously paused,
- hotfixes not stranded on a temporary branch.

### Phase 1 — Finish P063

Implement P063 gate runtime baselines.

Reason:

- helps immediately with timeout/retry pain,
- useful for plan-final gates,
- does not conflict with plan branch work.

Exit criteria:

- runtime baselines written,
- timeout policy block works,
- `.aid-o/metrics/` gitignored/backfilled,
- CLI available.

### Phase 2 — Finish P061 E3

Implement targeted test selector.

Reason:

- P064 depends on targeted/standard EPIC checks being credible,
- without E3, "lighter EPIC checks" are not trustworthy enough.

Exit criteria:

- changed path -> selected tests is deterministic,
- unknown production path fails/recommends upgrade,
- selector output appears in evidence.

### Phase 3 — Implement P064

Implement this roadmap as an executable plan.

Core deliverables:

- parent plan FSM and idempotent transaction substrate,
- plan branch lifecycle,
- plan boundary manifest,
- plan-aware queue/dependency handling,
- EPIC -> plan branch merge,
- branch/resume/worktree enforcement,
- plan-final runner,
- candidate freeze, invalidation and target-drift handling,
- exactly one release profile invocation,
- plan-mode C4 release policy,
- plan-final specialist dispatch,
- plan-aware release/version/tag/push integration,
- plan-close mechanical gate,
- docs/instructions update.

Recommended internal P064 delivery order:

1. **P064-A substrate (legacy default):** parent FSM, schema/manifest, locks,
   transactions, branch and queue primitives. No cadence cutover yet.
2. **P064-B EPIC integration:** task-to-plan merge and intermediate completion;
   old release callers disabled only inside fixture-controlled `plan_branch` mode.
3. **P064-C plan final:** candidate freeze, release profile, C2/C3/utilities,
   plan-mode C4 dual-run, PM authorization, release/merge/close transaction.
4. **P064-D cutover and dogfood:** active-plan inventory, new-plan default flip,
   documentation, real multi-EPIC run, metrics and rollback drill.

P064 is not considered delivered after substrate-only phases. The feature flag
remains legacy-default until the end-to-end plan path passes.

Exit criteria:

- at least one multi-EPIC plan completes using plan branch mode,
- Auditor/Curator/Simplifier/Reporter run at plan final only,
- full gates run at plan final by default,
- EPIC branches merge into plan branch,
- plan branch merges to main after PM approval.
- crash/resume and target-drift fixtures converge correctly,
- release/version/tag occurs once,
- no old per-EPIC release caller fires in plan mode.

This phase must also disable or bypass the old default per-EPIC release ritual
for plan-branch plans. Leaving the old ritual active is a failure, even if the
new plan-final path also works.

### Phase 4 — Amend P061 and Continue E4-E5 Under New Model

Update P061 D8 and run remaining executable P061 EPICs with the plan-level cadence as an
explicit dogfood exception approved by PM.

Exit criteria:

- P061 E4-E5 do not reintroduce per-EPIC full-review cadence,
- P061 E6 has an explicit done/defer decision,
- self-host defaults are updated safely,
- `/aid-do` and release invocation are aligned with plan-final model.

### Phase 5 — Revisit P062 / E10

Only after P064 is working.

E10 should promote:

- C3/C4 controls,
- plan-final release boundary,
- evidence freshness,
- plan-close consistency,
- profile/risk behavior.

It must not promote the old per-EPIC heavy cadence.

## Acceptance Criteria For P064

The executable P064 plan must create one mandatory integration suite:

```bash
command -v bats >/dev/null 2>&1 || exit 1
bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats
```

The suite uses real temporary Git repositories/worktrees and spying executables.
Missing Bats is a failure, not a skipped green run. Every AC below maps to named
red-green tests with explicit commands, expected exit codes and structured
artifact assertions.

### AC1. Plan And EPIC Branch Lineage Is Exact

- `plan-start` creates `plan/P064` from the recorded target SHA.
- `epic-start` creates the task branch from the atomically observed current plan
  SHA and records source ref/SHA.
- A task started from `main`, a stale plan SHA, another plan or an unrecorded
  manual branch exits non-zero before state/evidence mutation.
- The same checks run on resume and in linked worktrees.

### AC2. EPIC Merge Is Idempotent And Main Is Untouched

- `epic-merge-to-plan` moves only `plan/P064`; `main` SHA remains unchanged.
- A crash after Git merge but before state update is resumed without a duplicate
  merge and converges to `merged_to_plan`.
- Dirty plan worktree, `MERGE_HEAD`, unmerged paths and stale expected plan SHA
  all block.
- `merged_to_plan` requires ancestry proof, not DONE/queue bookkeeping.

### AC3. Queue Uses The Declared Merge Target

- Same-plan dependencies resolve against `plan/P064`.
- Cross-plan released dependencies resolve against `main`.
- Deleted task branch without ancestry proof does not unblock.
- Two concurrent queue claims cannot both win or lose an entry.
- Failed/aborted plan pauses dependent cross-plan work.

### AC4. Old Per-EPIC Release Stack Is Actually Silent

Poison/spying executables replace:

- CP3 full-diff final pair,
- Auditor, Curator, Simplifier and Reporter,
- EPIC-scoped C4,
- PM release summary,
- `aid-release.sh`, tag/push/cache refresh.

Intermediate completion in `plan_branch` succeeds with zero spy invocations.
`legacy_epic_release_mode` is the positive inverse fixture. Local CP2 and
targeted semantic/wiring checks still execute.

### AC5. Risk Raises The Final Floor Without Silent Full EPIC Tests

- A high-risk EPIC runs the required targeted critical checks and records
  `plan_final_required_profile: release`.
- It does not invoke the full/release suite at EPIC boundary without a fresh
  PM exception record.
- A PM-approved mid-plan full run is visible as an exception and does not remove
  the mandatory final profile.
- Unknown production paths fail closed and cannot downgrade to docs/trivial.

### AC6. Candidate Freeze And Fix Invalidation Work

- Plan final synchronizes the recorded `main`, prepares version metadata and
  freezes exact `candidate_sha`/`target_head_sha`.
- Any subsequent candidate change invalidates gates, C2/C3, utility reports,
  C4 and PM decision and transitions to `PLAN_FIX`.
- Accepted Curator/Auditor/Simplifier fix proves the full rerun loop.
- Advancing `main` during review or PM wait blocks merge and requires resync and
  a new plan-final run.

### AC7. Exactly One Real Plan-Final Release Profile Runs

The plan-final `gates_report.json` must prove:

- exact candidate SHA,
- profile `release`, where release includes the full floor,
- non-empty command log and durations,
- all expected/plan-required gate IDs executed,
- zero required gates hidden in `excluded_gates`,
- no duplicate second broad run under a separate `full` label.

### AC8. Plan-Level Reviews Run Once And Against The Full Plan

- C2 final review covers `plan_base_commit..candidate_sha`, including a seeded
  defect in the first EPIC after the last EPIC is integrated.
- Auditor, Curator, Simplifier and Reporter each dispatch exactly once on the
  final successful attempt.
- Every other enabled plan-boundary utility is counted explicitly; none may run
  per EPIC under an unnamed alias.
- Their evidence outputs leave `candidate_sha` and product worktree unchanged;
  Reporter emits the authoritative protocol-v2 delivery artifact in the run
  directory.
- Required high-risk C3 independence is enforced according to current policy;
  lower-risk plan still records the single plan-level Auditor dispatch without
  silently promoting C3 blocking.
- Missing, stale, wrong-plan or wrong-candidate output cannot satisfy the plan
  final runner.

### AC9. Plan-Mode C4 Uses Identity, Not Directory Names

- Every input names plan ID, final run ID, candidate SHA, target ref/SHA and
  protocol artifact type.
- C4 consumes the run-scoped Reporter delivery artifact, not a committed
  Markdown projection or legacy marker.
- Passing an EPIC evidence directory fails.
- Copying or symlinking a valid EPIC pack into the plan-final path still fails
  subject/identity validation.
- Retrying creates `R-P064-final-2`; it does not overwrite run 1.
- Before E10, C4 respects current policy mode and emits dual-run evidence;
  P064 does not silently promote content/freshness findings.
- P064-owned candidate/target/manifest identity mismatch always blocks.

### AC10. PM Authorization And Final Merge Are Atomic

For missing, `FIX`, `ABORT`, stale, malformed, wrong-plan, wrong-candidate and
wrong-target decisions, `plan-merge-to-main` exits non-zero and leaves `main`
unchanged. Only a fresh plan-scoped `MERGE` decision permits the compare-and-swap
merge. A concurrent `main` advance loses the CAS and forces revalidation.

### AC11. Release, Version, Tag And Push Occur Once

- No intermediate EPIC creates a version commit or tag.
- Version/changelog preparation is part of the frozen candidate.
- Final merge verifies tree identity, creates one tag on the final main merge
  commit and emits one push/cache-refresh action according to policy.
- Resume after each transaction boundary creates no duplicate release/tag.
- Pushing `plan/*` does not trigger the pre-push premature-release path.
- Optional publication of human reports cannot move the reviewed/tagged
  candidate or serve as release authorization.

### AC12. Plan Close Is Truly Final And Recoverable

Individually remove or corrupt: EPIC ancestry, manifest, final gate report,
required review, C4 decision, PM decision, merge/abort record, queue state,
active state, release/tag record and final SHA binding. Every mutation blocks
close. Unknown ancestry blocks. Re-running after a simulated crash reconciles
state and writes one atomic head-bound close marker only after final merge or
recorded abort.

### AC13. Single-EPIC And In-Flight Modes Are Unambiguous

- A new one-EPIC plan follows `task -> plan -> main`; task is not an ancestor of
  main before final authorization.
- Existing active plans are inventoried and stamped
  `legacy_epic_release_mode` without migration.
- New plans default to `plan_branch`.
- Missing, unknown or mixed mode exits non-zero before mutation.

### AC14. Conflict, Abort, Hotfix And Resume Paths Preserve Truth

- EPIC merge conflict enters `CONFLICT` and never records completion.
- Pre-main abort leaves main unchanged and records terminal evidence.
- Hotfix on main forces every affected active plan to resynchronize before
  candidate freeze.
- Failure after final Git merge but before queue/close update is reconciled on
  resume.
- Published rollback uses a new revert/hotfix, never history rewrite.

### AC15. Decommissioning Metrics Prove The Cadence Change

For an N=3 plan, structured invocation logs must show:

- broad release profile: `3 -> 1`,
- Auditor/Curator/C4/PM release decision: `3 -> 1`,
- per-EPIC CP3 final pair: `3 -> 0`, replaced by one plan-level C2 final review,
- Simplifier/Reporter/plan-close: `1 -> 1`,
- version/tag release: exactly once,
- zero intermediate legacy release-stack invocations,
- all PM-approved exceptions counted separately with reason.

### AC16. Control-v2 Boundary Is Preserved

- P064 relocates legacy controls to plan final but does not delete them.
- Existing C0-C4 policy modes remain unchanged unless a separately approved E10
  decision promotes them.
- The topology/T2 amendment and P061/P062 amendments are present and
  machine-checkable before P064 is marked DONE.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Parent FSM/transaction work is broader than a merge-target patch | High | deliver P064 in substrate/integration/final/cutover phases; no default flip before E2E pass |
| Crash leaves Git and AID state on opposite sides of a merge | High | operation records + idempotent reconciliation AC2/AC10/AC12 |
| Queue still reasons against `main` for same-plan EPICs | High | declared target per dependency + ancestry-only completion AC3 |
| Review fix makes prior plan-final evidence stale | High | immutable candidate + `PLAN_FIX` invalidation loop AC6 |
| Main advances while PM is deciding | High | bind decision to candidate+target SHA; CAS merge AC10 |
| P064 accidentally deletes legacy coverage before calibration | High | relocate once to plan final; removal remains E11 AC16 |
| P061 high-risk resolver restores full-suite-per-EPIC | High | split EPIC checks from accumulated final floor AC5 |
| Release/tag still fires from task or plan branch prematurely | High | two-phase plan release + pre-push update AC11 |
| Active legacy plan is half-migrated | High | no v1 migration; inventory and explicit mode AC13 |
| Concurrent writers corrupt queue/manifest | Medium | serialize v1 shared writes/finalization with lock/lease AC3/AC14 |
| Main does not receive intermediate EPIC commits | Medium | intentional; plan branch is the integration branch |
| Single-EPIC plans gain one internal branch | Medium | same mechanically tested path, no special bypass AC13 |

## Resolved Implementation Decisions

These are inputs to P064 plan writing, not open forks:

1. Plan branch name is exactly `plan/Pxxx`.
2. EPIC-to-plan merges use `--no-ff` and record pre/post SHAs.
3. Plan-to-main merge uses `--no-ff`, expected-target compare-and-swap and tree
   verification.
4. Target synchronization uses a merge of current `main` into the plan branch,
   not history-rewriting rebase, for deterministic resume/audit behavior.
5. `plan_branch` is mandatory for new plans after cutover, including one-EPIC
   plans.
6. Existing in-flight plans finish in explicit `legacy_epic_release_mode`; v1
   performs no mid-plan migration.
7. Shared queue/manifest/finalization mutations are serialized in v1.
8. Each plan-final retry gets a new immutable run directory.
9. One `release` profile subsumes the full profile; broad suites do not run
   twice.
10. P064 moves cadence and branch authority. E10/E11 retain ownership of
    control promotion and legacy-control removal.

## PM-Facing Summary

This roadmap changes AID from:

```text
many expensive EPIC mini-releases
```

to:

```text
cheap EPIC work increments + one serious plan-final release
```

That is the intended simplification.

P061 and P063 make checks smarter and less wasteful. This roadmap changes the
cadence so those smarter checks happen at the right boundary.
