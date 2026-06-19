# Review Checkpoint Contracts

Defines the per-checkpoint contract for AID review agents. Referenced by agent prompts.
Additive to the canonical verifier output format (`agents/verifier.md`).

**Last Updated:** 2026-06-19

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

## CP6 Contract (Advisory)

Focus: retrospective quality review
Scope: merged diff (advisory — not blocking FSM)
Required fields: standard verifier fields + `checkpoint: cp6`
High-risk gate: NOT enforced (advisory only)
Note: CP6 is never promoted to blocking — it is intentionally light.
