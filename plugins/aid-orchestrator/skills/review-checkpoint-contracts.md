---
name: review-checkpoint-contracts
description: Per-checkpoint contracts for AID review agents — plan review pointer, diff scopes, behavior_trace gate, CP2 to CP6
user_invocable: false
---

# Review Checkpoint Contracts

Defines the per-checkpoint contract for AID review agents. Referenced by agent prompts.
Additive to the canonical verifier output format (`agents/verifier.md`).

**Last Updated:** 2026-09-18

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

A diff is "high-risk" if it matches ANY of these patterns:

| Pattern | Regex | Category |
|---------|-------|----------|
| Auth handlers | `@app\.<method>\(\|@router\.<method>\(\|add_route\(\|def \w+\(.*request\|async def \w+\(.*request` | routes |
| Auth logic | `authenticate\|authorize\|verify_token\|check_permission\|require_auth` | auth |
| Schema/validation | `Schema\|Validator\|validate(\|marshmallow\|pydantic\|BaseModel` | validation |
| Migrations | `migrate\|alembic\|revision\|upgrade\|downgrade` | migrations |
| FSM/state | `fsm-state\|state_machine\|cmd_transition\|aid-fsm\.sh` | fsm |
| Security sinks | `exec(\|subprocess\|eval(\|pickle\|yaml\.load` | security |
| Payment | `stripe\|payment\|charge\|billing\|invoice` | payment |
| Dependency manifests | `requirements\.txt\|pyproject\.toml\|package\.json\|Gemfile` | deps |

## Per-Checkpoint Diff Scope

| Checkpoint | Diff Range | When dispatched |
|-----------|-----------|-----------------|
| CP2 | `HEAD~1..HEAD` (step diff) | After each EXECUTE step |
| CP3 | `base_commit..HEAD` (full EPIC) | After all steps, before GATES |
| CP4 | Applied curator/auditor diff | After C+A auto-fix in DONE review |
| CP6 | Advisory, separate from FSM | Post-merge retrospective (advisory only) |

## Structural Gate: behavior_trace_count

When the checkpoint's diff matches a high-risk pattern:
- `behavior_trace_count` MUST be > 0
- `behavior_trace_required: true` (must be set explicitly — gate only fires when this field is literally `"true"`; omitting it means no enforcement)
- Each traced path must name: request, path (handler→service→sink), sink, branches with outcomes

When diff is trivial (no high-risk patterns) or `classification: SKIP`:
- `behavior_trace_required: false`
- `behavior_trace_skip_reason: "<why no trace needed>"`
- `behavior_trace_count: 0` is acceptable

**Gate is structural and non-emptiness only.** It does NOT evaluate trace quality.
FSM enforcement: `fsm_check_verifier_output` validates `behavior_trace_count > 0`
when `behavior_trace_required: true` in the verifier output.

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

## CP2 Contract

Focus: `code-review` (default) or `security`
Scope: Step diff only (`HEAD~1..HEAD`)
Required fields: all standard verifier fields + `checkpoint: cp2`
High-risk gate: if diff matches patterns above, `behavior_trace_count > 0` required
Test questions: both of the above, on the step's own added tests

## CP3 Contract

Focus: `code-review` + `security` (parallel)
Scope: Full EPIC diff (`base_commit..HEAD`)
Required fields: all standard verifier fields + `checkpoint: cp3`
High-risk gate: same as CP2
Test questions: both of the above, across the EPIC's whole added test surface —
CP3 is the first point where two steps' suites can be seen to overlap

## CP4 Contract

Focus: `code-review` (applied C+A changes)
Scope: C+A applied diff (or full EPIC range if scope unclear)
Required fields: all standard verifier fields + `checkpoint: cp4`, `classification: FULL_REVIEW`
High-risk gate: if C+A applied changes touch high-risk patterns, trace required

## CP5 Contract

Focus: `blocking_findings` check (DONE sub-phase `review`)
Scope: reads structured `blocking_findings:` field from `audit-report.md` (top-level, not prose)
Enforcement: `aid-fsm.sh:cmd_done_advance()` — `blocking_findings: true` blocks the MERGE option in the PM summary
Required fields in audit-report: `blocking_findings: true|false` at line-start (not inside a heading or prose)
High-risk gate: NOT a diff gate — evaluates the audit report output, not the code diff
Note: CP5 is not a verifier dispatch. It is a structured field check inside `done-advance`.

## CP6 Contract (Advisory)

Focus: retrospective quality review
Scope: merged diff (advisory — not blocking FSM)
Required fields: standard verifier fields + `checkpoint: cp6`
High-risk gate: NOT enforced (advisory only)
Note: CP6 is never promoted to blocking — it is intentionally light.

## CP1 Contract — Plan Review

Plan review is not a verifier dispatch. Six reviewer roles answer from one
template, in at most two rounds by default, and a deterministic adjudicator
merges what survives the evidence rule:

- the roles, their questions, the evidence rule and the answer shape:
  `skills/plan-review-roles.md` (schema `defaults/schemas/plan-review-finding.schema.json`);
- the controller's procedure, command by command: "Plan review (CP1)" in
  `commands/aid-plan.md`;
- the rounds, the adjudicator and the round evidence under
  `.aid-o/work/evidence/<plan_id>/cp1/`: `scripts/aid-plan-review-round.sh`
  and `scripts/aid-plan-review-adjudicate.sh`;
- the gate before EPIC generation: `scripts/aid-cp1-gate.sh`, which reads only
  that round evidence.

**Where the gate is called from — once per TRANSACTION, never once per phase.** A plan's generation is one transaction. `scripts/aid-auto-pipeline.sh` calls this gate exactly ONCE per plan, before any EPIC, `plan.json`, run, FSM state or queue entry exists, and seals the decision into `.aid-o/work/evidence/<plan_id>/generation/generation-authority.json`. Every phase then VERIFIES that sealed authority (schema, self-hash, plan bytes, target head, phase range, re-derived ids) instead of re-running the gate. A standalone `scripts/aid-plan-to-epic.sh` invocation — one given neither `--generation-authority` nor `--transaction` — still runs the full gate per invocation; that is the only surface where a per-invocation gate call remains.

## C2 Semantic Review — Lens Catalog

C2 produces auditable semantic evidence alongside the existing `.md` gate output (dual-emit, D1).
Evidence format: `semantic-review-{mode}.json` wrapping findings via `aid-finding-merge.sh`.

### 4-Mode Dispatch Contract

| Mode | When dispatched | Typical trigger |
|------|----------------|-----------------|
| `local` | CP2 (per-step, contract/high-risk steps) | Pre-filter classification RUN on step diff |
| `wiring` | First runnable assembly slice | At least 2 inter-step contracts exist in diff + wiring surface detected |
| `behavior` | Feature-complete assembly point | All core behavior paths present in diff |
| `final` | CP3 (full EPIC diff) | EXECUTE→GATES transition |

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

Under `plan_branch` the Auditor, Curator, Simplifier and Reporter are
**plan-final** roles: dispatched once per plan, at the boundary, against the
frozen candidate. CP2 and CP3 remain per EPIC. Under
`legacy_epic_release_mode` the previous per-EPIC cadence is unchanged. Mode is
read from the plan's committed lifecycle manifest, never inferred.
