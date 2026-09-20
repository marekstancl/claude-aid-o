---
name: review-checkpoint-contracts
description: Per-checkpoint contracts for AID review agents — plan review pointer, diff scopes, behavior_trace gate, CP2 to CP6
user_invocable: false
---

# Review Checkpoint Contracts

Defines the per-checkpoint contract for AID review agents. Referenced by agent prompts.
Additive to the canonical verifier output format (`agents/verifier.md`).

**Last Updated:** 2026-09-20

## False-Green Guardrails

These guardrails apply to plan and implementation reviews in addition to the
per-checkpoint rules below:

- DONE review must not be based on "tests pass" alone. It must include an
  independent runtime path check through the real caller path used by
  production, FSM, CLI, API, or the user flow.
- Any AC that says "always", "all", "each", "never", or similar must define
  the exact universe it ranges over, such as "all documents" vs "documents with
  `client_id`". Ambiguous universes are not objectively verifiable.
- Eval/evidence artifacts must state which part of the pipeline they actually
  execute and which parts they do not. A partial pipeline run must not be
  presented as full coverage.
- Every new integration function must have at least one caller-flow test. A
  unit test of the helper itself is insufficient for integration claims.

## High-Risk Pattern Detection

Since P094 the patterns live in one place: `aid-step-check.sh` scans the diff
and records `security.matched_rules` (the rules of `defaults/pre-filter-rules.yaml`,
which add the security reviewer to the round) and `handler_patterns` (routes,
auth, schema/validation, migrations, FSM, security sinks, payment, dependency
manifests) in `step-check.json`. The reviewer prompt shows both; a reviewer
never re-derives them.

## Per-Checkpoint Diff Scope

`step-check.json.range` (and `range_source`) is the diff a round reviews:
`<previous step commit>..HEAD` for cp2, `base_commit..HEAD` for cp3, the
working tree for cp6, `plan_base_commit..candidate_sha` for cp7.

## Structural Gate: behaviour trace

When `step-check.json.handler_patterns` is non-empty, a generalist's blocker or
major finding must carry a `behaviour_trace` (request → handler → service →
sink, branches with outcomes) as `skills/step-review-roles.md` requires; the
adjudicator rejects such a finding without one (`trace_missing`). The gate is
structural: it checks presence, never trace quality.

## The Two Test Questions (CP2 and CP3, both mandatory)

Review has always asked the first one. The second is what stops a portfolio
growing forever, and it is answered with the SAME weight as the first.

1. **Is anything added here untested?** — a missing test is a finding.
2. **Is each added test the cheapest sufficient proof — does an existing test
   already cover it?** — a REDUNDANT test is a finding of the same weight as a
   missing one. Five places in this process add tests and, before the reaper,
   none removed any; a review that only ever asks question 1 is one of those
   five places.

**"It is probably covered somewhere" is not a valid answer to question 2.** The
answer NAMES the covering test — file and case — or it concedes the test is
needed. An unnamed claim of coverage is how a duplicate suite gets waved
through, and it costs the portfolio the same as the duplicate it excuses.

A new suite must also carry a tier tag (`# aid-tier: t0|t1|t2`) matching what
its plan declared; `aid-test-tier-lint.sh` is the mechanical half, and review
is where an over-cheap or over-expensive CHOICE gets questioned.

## CP2, CP3 and CP6 Contracts — Step, EPIC and Fast-Mode Review

These three checkpoints are one mechanism: reviewer roles from
`skills/step-review-roles.md` answer from the shared template
(`defaults/prompts/review-prompt-v1.md`) in the shape of
`defaults/schemas/review-finding.schema.json`, and the deterministic
adjudicator keeps only findings with a command and a `path:line` (or
`<sha>:path:line`) evidence. What differs is the diff each one reviews:

| Checkpoint | Diff under review | Roles | Blocks |
|---|---|---|---|
| CP2 | the step: last `step_commit` → HEAD (else `base_commit` → HEAD) | `step_generalist`, plus `step_security` when the step check reports a security pattern | `increment-step` |
| CP3 | the EPIC: `base_commit` → HEAD | `epic_generalist`, `epic_behaviour`, `epic_security` | EXECUTE → GATES |
| CP6 | the `/aid-do` working tree | `step_generalist` (+ `step_security`) | nothing (advisory) |

The two test questions above are asked by every generalist role; the behaviour
trace is required from a generalist's blocker or major finding whenever the
step check reports a handler pattern. The controller's procedure, command by
command, is the "Step review (CP2) and EPIC review (CP3)" section of
`commands/aid-run.md`; the round evidence is described there and in
`skills/step-review-roles.md`.

## CP1 Contract — Plan Review

Plan review is not a verifier dispatch. Six reviewer roles answer from one
template, in at most two rounds by default, and a deterministic adjudicator
merges what survives the evidence rule:

- the roles, their questions, the evidence rule and the answer shape:
  `skills/plan-review-roles.md` (schema `defaults/schemas/review-finding.schema.json`, shared with CP2/CP3/CP6);
- the controller's procedure, command by command: "Plan review (CP1)" in
  `commands/aid-plan.md`;
- the rounds, the adjudicator and the round evidence under
  `.aid-o/work/evidence/<plan_id>/cp1/`: `scripts/aid-review-round.sh --plan`
  and `scripts/aid-review-adjudicate.sh`;
- the gate before EPIC generation: `scripts/aid-cp1-gate.sh`, which reads only
  that round evidence.

**Where the gate is called from — once per TRANSACTION, never once per phase.** A plan's generation is one transaction. `scripts/aid-auto-pipeline.sh` calls this gate exactly ONCE per plan, before any EPIC, `plan.json`, run, FSM state or queue entry exists, and seals the decision into `.aid-o/work/evidence/<plan_id>/generation/generation-authority.json`. Every phase then VERIFIES that sealed authority (schema, self-hash, plan bytes, target head, phase range, re-derived ids) instead of re-running the gate. A standalone `scripts/aid-plan-to-epic.sh` invocation — one given neither `--generation-authority` nor `--transaction` — still runs the full gate per invocation; that is the only surface where a per-invocation gate call remains.

## C2 Semantic Review — Lens Catalog

C2 produces auditable semantic evidence at the plan-final boundary.
Evidence format: `semantic-review-final.json` wrapping findings via `aid-finding-merge.sh`.

### Dispatch contract

| Mode | When dispatched | Producer |
|------|----------------|----------|
| `final` | the plan-final boundary (`aid-plan-fsm.sh plan-finalize`) | the verifier, filling the generated envelope |

The `local`, `wiring` and `behavior` modes went with P094: a step's or an
EPIC's semantic evidence is the reviewer round's merged findings, and the cp3
`close` writes the per-EPIC `semantic-review-final.json` itself.

**No-mega-prompt rule (D2):** Verifier dispatches C2 with a profile-selected subset of lenses, not all 12 at once. The `review-profile.required_lenses[]` field governs which lenses run per dispatch.

### 12 C2 Semantic Lenses

These lenses are SEMANTIC (C2). Shape/wire/structural checks are C1 (E6) — NOT C2 lenses (D4).

| Lens ID | Name | Mode(s) | FC | What it checks |
|---------|------|---------|-----|----------------|
| `requirement_test_drift` | Requirement/test drift | local, final | FC-28 | Test changes approved contract/status (e.g. 403→401 without PM approval) |
| `transaction_boundary` | Transaction boundary | behavior, wiring | FC-24 | Cleanup wraps commit correctly; MinIO/SQL transaction order |
| `field_lineage` | Field lineage | behavior, wiring | FC-25 | Field derived from request is persisted/propagated to storage and read path |
| `negative_case` | Negative case coverage | final | FC-26 | Prohibition invariants have negative tests; "accepted when should be rejected" |
| `operation_order_resource_bound` | Operation order / resource bound | behavior, wiring | FC-27 | Size/MIME guards fire before full read; operation ordering correct |
| `false_empty_distinction` | False empty distinction | behavior, wiring | FC-32 | Error/offline/not-found/empty remain semantically distinct; no broad catch converts failure to false empty |
| `ac_to_test_identity` | AC-to-test identity | final | FC-31 | Tests are falsifiable claims for ACs; scenarios not silently replaced |
| `contract_consumption` | Contract consumption | local | FC-09 | Contracts from brainstorm/Writer don't get lost to implementor |
| `fallback_resilience` | Fallback resilience | behavior, final | — | Fallbacks tested by forcing primary failure; degradation and recovery observable |
| `integration_oracle` | Integration oracle | behavior, final | — | Output compared with independent oracle; negative mutation proof present |
| `ui_lifecycle` | UI lifecycle | behavior | FC-30 | Modal/component close/reopen retains or correctly resets state |
| `frontend_user_outcome` | Frontend user outcome | behavior | FC-35 | Looks correct over real data, not mocked; user-visible outcomes verified |

**C1/structural checks excluded (D4):** Delivery gate presence, producer-consumer file contracts, build config resolution, route registration, import resolution — these belong to C1/E6, not C2.

### Lens Output per Finding

Each C2 finding carries:
```yaml
fingerprint: "sha256:<64hex>"  # aid-finding-fingerprint.sh fingerprint <project_id> semantic_review <check_id> <target_path> <finding_class>
severity: critical|high|medium|low|info
lens: <lens_id from table above>
check_id: "<string>"   # short ID like RD-001, TX-001 etc.
target_path: "<file path being analyzed>"
finding_class: "<category string>"
status: open|resolved|deferred
detail: "<human-readable explanation>"
```

## Plan-boundary note

Under `plan_branch` the whole delivery is read once per plan, by the whole-plan
round (CP7) against the frozen candidate (`commands/aid-run.md`, "Closing a plan
(plan-final)"). CP2 and CP3 remain per EPIC in both modes. Mode is read from the
plan's committed lifecycle manifest, never inferred.
