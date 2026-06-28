---
name: review-checkpoint-contracts
description: Per-checkpoint contracts for AID review agents — high-risk patterns, diff scopes, behavior_trace gate, CP1-deep 3-lens adjudicator
user_invocable: false
---

# Review Checkpoint Contracts

Defines the per-checkpoint contract for AID review agents. Referenced by agent prompts.
Additive to the canonical verifier output format (`agents/verifier.md`).

**Last Updated:** 2026-06-28

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

## CP2 Contract

Focus: `code-review` (default) or `security`
Scope: Step diff only (`HEAD~1..HEAD`)
Required fields: all standard verifier fields + `checkpoint: cp2`
High-risk gate: if diff matches patterns above, `behavior_trace_count > 0` required

## CP3 Contract

Focus: `code-review` + `security` (parallel)
Scope: Full EPIC diff (`base_commit..HEAD`)
Required fields: all standard verifier fields + `checkpoint: cp3`
High-risk gate: same as CP2

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

## CP1-deep Contract (High-Risk Plans)

Triggered when: plan matches any high-risk pattern OR plan frontmatter has `risk: high`.
Skip when: plan matches no high-risk patterns AND `risk: low` (or `risk: medium` — default skips CP1-deep unless pattern match).

### 3 Lenses (dispatched in parallel, per plan taxonomy)

| Lens | File | Focus | Stop-Rule Criteria |
|------|------|-------|-------------------|
| L1 behavior | `cp1-lens-L1-behavior.md` | request→branch→sink flow, undeclared outcomes, user-visible regressions, edge cases | any finding showing a handler branch is undeclared or produces an unintended user-visible outcome |
| L2 feasibility | `cp1-lens-L2-feasibility.md` | touched files, output contracts, parser/producer ordering, implementation feasibility | any finding showing a consumer reads a field before the producer emits it, or a file-contract is violated |
| L3 enforcement | `cp1-lens-L3-enforcement.md` | gitignored artifacts, remote CI visibility, test runner execution, release/CI breakage | any finding showing an artifact is unreachable in CI, a test does not actually run, or a release gate is broken |

Each lens produces (required fields — gate rejects empty files or files without `stop_rule_blockers:`):
- `stop_rule_blockers: []` — issues that should BLOCK EPIC generation (required field at line-start)
- `findings: []` — all issues (any severity)
- `confidence: high|medium|low`

**L3 is the class that caught gitignored CI artifacts and non-executing tests** — it is the enforcement/visibility dimension, distinct from L1 user-flow and L2 contract correctness.

### Adjudicator Contract

Reviews all 3 lens outputs. Accepts a `stop_rule_blocker` ONLY if it has:
- Command or artifact reference (e.g., function name, file path, SQL query, config key)
- File:line evidence OR explicit quote from the plan

Rejects blockers that are: vague ("might have security issues"), hypothetical without plan grounding, or duplicates across lenses.

Produces (required fields — gate rejects empty files or files without `verdict:`):
- `verdict: pass|revise|fail` (required field at line-start)
- `accepted_blockers: []`
- `rejected_blockers: []` (with rejection_reason per entry)
- `revision_count: N` (cumulative)

### Revision Loop

- `verdict: revise` + `revision_count < 2` → auto-revise plan targeting accepted_blockers → re-run CP1-deep
- `revision_count >= 2` + accepted_blockers survive → **PM escalation** (not pass, not auto-revise)
- `accepted_blockers: []` AND `verdict: pass` → EPIC generation proceeds

### Evidence Requirements

Before EPIC generation for a high-risk plan, all 4 files must exist, be non-empty, and contain required fields in `.aid-o/work/evidence/<plan_id>/cp1-deep/`:
- `cp1-lens-L1-behavior.md` — must contain `stop_rule_blockers:` at line-start
- `cp1-lens-L2-feasibility.md` — must contain `stop_rule_blockers:` at line-start
- `cp1-lens-L3-enforcement.md` — must contain `stop_rule_blockers:` at line-start
- `cp1-adjudicator.md` — must contain `verdict:` at line-start

Gate enforcement: `scripts/aid-cp1-gate.sh` validates presence of all 4 files and absence of unresolved accepted blockers before allowing EPIC generation. Called as subprocess by `scripts/aid-plan-to-epic.sh`.
