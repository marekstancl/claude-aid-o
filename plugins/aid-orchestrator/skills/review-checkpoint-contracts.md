---
name: review-checkpoint-contracts
description: Per-checkpoint contracts for AID review agents — high-risk patterns, diff scopes, behavior_trace gate, CP1-deep 3-lens adjudicator
user_invocable: false
---

# Review Checkpoint Contracts

Defines the per-checkpoint contract for AID review agents. Referenced by agent prompts.
Additive to the canonical verifier output format (`agents/verifier.md`).

**Last Updated:** 2026-06-29

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

### C0 Observe Lenses — Adjudicator Addendum (append-only, E4)

When 5 C0 lens files (`c0-lens-{name}.md`) are present in `.aid-o/work/evidence/{plan_id}/c0/`:
- Record their `stop_rule_blockers` and `findings` in the adjudicator verdict as **advisory** observations
- Do NOT include C0 lens blockers in `accepted_blockers` — they are observe-only in E4
- Do NOT change the pass/fail verdict based on C0 lens findings
- Add a field `c0_lens_observations: [{lens, blockers_count, confidence}]` to the verdict (optional field)

The 3 existing lenses (L1/L2/L3) and their blocking behavior are UNCHANGED.

## C0 Semantic Lenses (Observe, E4)

Dispatched by the orchestrator in the CP1-deep flow alongside L1/L2/L3. All 5 lenses are **observe-only in E4** — their `stop_rule_blockers` are advisory, not blocking. Blocking promotion: E10.

Each lens writes to `.aid-o/work/evidence/{plan_id}/c0/c0-lens-{name}.md` and MUST contain:
- `stop_rule_blockers:` at line-start (list; advisory in E4 — recorded in adjudicator verdict as observe, NOT counted in `accepted_blockers`)
- `findings:` list (any severity)
- `confidence: high|medium|low`

### Lens: reuse_compat

**Focus:** Detect incompatible component reuse — where a step plans to reuse a component in a way that breaks its existing contract, interface, or invariants.

**What to look for:**
- A step reuses a function, class, or module but requires it to behave differently from its current documented behavior
- A step imports/calls a shared component but the plan changes that component's signature/return type for another step concurrently
- Reuse that would require the shared component to carry contradictory state

**Output file:** `c0-lens-reuse_compat.md`
**Required fields:** `stop_rule_blockers:` (line-start), `findings:`, `confidence:`
**Observe semantics:** findings are advisory in E4; `stop_rule_blockers` recorded in adjudicator verdict as advisory only, NOT counted in `accepted_blockers`

### Lens: planned_call_feasibility

**Focus:** Detect plan steps that call an output, function, or API of another step that does not appear feasible to produce given the step's scope.

**What to look for:**
- Step B calls `step_A.output.field_X` but Step A's scope/artifacts don't mention producing field_X
- Step B assumes a specific API endpoint exists that no step in the plan creates
- A downstream step depends on a runtime artifact (file, DB row, service endpoint) whose producer step doesn't clearly emit it

**Output file:** `c0-lens-planned_call_feasibility.md`
**Required fields:** `stop_rule_blockers:` (line-start), `findings:`, `confidence:`
**Observe semantics:** advisory in E4

### Lens: dep_api_grounding

**Focus:** Detect cases where the plan builds on a dependency's API that doesn't match the actual version or documented interface.

**What to look for:**
- Plan references a library method/parameter that was added/removed in a version not in the project's dependency spec
- Plan assumes an external API response shape that differs from the documented API for the version range in use
- Plan calls a deprecated method that may be removed

**Output file:** `c0-lens-dep_api_grounding.md`
**Required fields:** `stop_rule_blockers:` (line-start), `findings:`, `confidence:`
**Observe semantics:** advisory in E4

### Lens: idempotency_matrix

**Focus:** Detect non-idempotent mutations against at-most-once acceptance criteria.

**What to look for:**
- A step performs a state mutation (INSERT, file write, external API call) but the plan's AC requires at-most-once execution, yet the step has no idempotency guard (ON CONFLICT IGNORE, file existence check, deduplication key)
- A step that may be retried (retry logic mentioned in plan) but whose mutation is non-idempotent
- Batch operations with no cursor/offset tracking that would re-process on retry

**Output file:** `c0-lens-idempotency_matrix.md`
**Required fields:** `stop_rule_blockers:` (line-start), `findings:`, `confidence:`
**Observe semantics:** advisory in E4

### Lens: authority_runtime_matrix

**Focus:** Detect mutations that cross ownership or tenant boundaries without explicit authorization.

**What to look for:**
- A step writes to a resource (DB table, file path, service endpoint) that is owned by another component/tenant without explicit cross-boundary authorization in the plan
- A step reads/modifies data of a different user/tenant using a service account that implies cross-tenant access
- A step escalates privileges beyond what the plan's stated execution context allows

**Output file:** `c0-lens-authority_runtime_matrix.md`
**Required fields:** `stop_rule_blockers:` (line-start), `findings:`, `confidence:`
**Observe semantics:** advisory in E4

## C2 Semantic Review — Lens Catalog

C2 produces auditovatelnou semantic evidence alongside the existing `.md` gate output (dual-emit, D1).
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
