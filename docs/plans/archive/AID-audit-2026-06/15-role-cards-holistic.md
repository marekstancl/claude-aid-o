# role-cards.md — holistic review (H1, 2026-06-03)

Evidence-backed via 3 parallel Explore agents + direct verification. This is the
binding analysis for the role-cards.md overhaul. Decisions D1-D5 below gate the edits.

## How role-cards.md is consumed (the contract)

- Implementer dispatch (pipeline.md §4, implementer.md): controller reads the role's
  card → injects Identity / Capabilities / Constraints (and Improvement Hints on retry)
  into the agent prompt; reads `**Model:**` for the Agent tool model tier.
- Verifier dispatch: reads the focus card (Identity / Scope / Key checks / Output / Do NOT).
- `**Model:**` is declared the SINGLE SOURCE OF TRUTH by planner.md:145 + implementer.md:13.

## Finding 1 — MODEL selection is decided in 4 disagreeing places

| Source | What it says | Status |
|--------|--------------|--------|
| role-cards.md `**Model:**` per role | claimed single source of truth | live, read at dispatch |
| orchestration.yaml `models:` (L15-18) | opus[architect,backend,frontend], sonnet[qa,security,docs-writer,curator,auditor,implementer,verifier], haiku[gate-fixer] | **incomplete + conflicting, never grep-read at dispatch** |
| plan.json `model` field (plan.schema.json:83-87, optional haiku\|sonnet\|opus) | optional per-step | planner.md:143 says "model is NOT in plan.json" — schema contradicts |
| pipeline.md:228-229 | "model from step.model OR plan.json `role_assignments` OR orchestration.yaml role tiers" | **`role_assignments` does NOT exist anywhere (phantom); "role tiers" = misnamed `models:` block** |

orchestration.yaml `models:` block omits domain, observability, release, e2e, and all 3
VULCAN roles; conflates verifier focuses (qa, security) with implementer roles. No script reads it.

**Definitive "what model when" (from role-cards.md = the live source):**
- **opus:** architect, backend, frontend, e2e(role)
- **sonnet:** domain, observability, docs-writer, release, security(role), all verifier focuses
  (qa, security, docs-review, code-review, e2e-focus, section-review, cross-section-review),
  langgraph, python-async, sql-isolation; auditor/curator/verifier (frontmatter)
- **haiku:** gate-fixer (frontmatter)

## Finding 2 — e2e: BOTH cards are currently unreachable

- "Focus: e2e" (L315, Playwright, sonnet): GHOST. verifier.md focus list has only 6 (no e2e);
  `aid-emit-dispatch.sh:61` allowlist regex `^cp[1-4](...)?$` structurally rejects focus=e2e.
- "## e2e" (L459, 5-layer real-infra, opus): referenced by pipeline.md:259 as an implementer
  ROLE — BUT `e2e` is NOT in plan.schema.json role enum nor aid-epic-to-json.sh:723 valid_roles
  (architect, domain, backend, frontend, qa, security, observability, docs, release). So the
  epic-to-json script would REJECT a `role: e2e` step. e2e is aspirational, not wired.
- P022 lesson (CHANGELOG): Playwright ACs were substituted with backend introspection w/o
  user-facing verification → DO NOT substitute UI proof with API checks; escalate instead.
- Existing PW guidance: pipeline.md:291-293 "Compiles ≠ looks right; screenshot vs mockup."

## Finding 3 — role NAME mismatches (enforcement vs cards)

- **`docs` vs `docs-writer`:** schema enum + aid-epic-to-json valid_roles use **`docs`**;
  role-cards.md + orchestration.yaml use **`docs-writer`**. A `role: docs` step finds no
  matching card. Real defect.
- **qa & security are dual:** both are valid STEP roles (schema/script) AND verifier focuses
  (role-cards). qa as a step role has NO implementer card — only a verifier-focus card
  (read-only shape). security has both an implementer role card (L207) and a focus card (L259).

## Finding 4 — structural / decorative

- **Max Parallel:** dead — orchestration.yaml:23 `max_parallel: 1` enforces sequential
  (pipeline.md:566 "TEMPORARY: Sequential execution enforced"). Present on 8 implementer roles,
  absent on VULCAN roles + all verifier focuses.
- **Two footers / two dates:** L9 `Last Updated 2026-03-16` + L491 `Last Updated 2026-03-19`
  (+ a `Replaces:` line scoped only to the tail). One file, two metadata owners.
- **Inconsistent card schema:** implementer cards = Identity/Capabilities/Constraints/Hints/
  Model/MaxParallel; focus cards = Identity/Scope/Output/KeyChecks/Model(+Do NOT on some).
  No Input field on verifier focus cards despite agent-protocol Input contract.

## Dropped learnings to home (original H1 ask)

- **#10** (qa mock-vs-real): "Verify 'LLM/service returns X' isn't a mock before blaming env;
  reconcile auditor vs FSM compliance.json single-writer." → qa card key-check.
- **#15** (verifier behavior-vs-AC): "Verifier distinguishes 'behavior covered' from literal-AC-met
  and reports drift." → code-review + qa cards.
- **#20** (qa env gotchas): "Specify test package in dispatch; gates install deps first; separate
  Vitest/Playwright patterns; reset Zustand store per test." → qa card preconditions.
- #17 (architect file-ownership) already propagated (L30). #5 (inline-mode provenance) homes in
  pipeline.md/agent-protocol, not role-cards.

## Decisions needed (D1-D5) — see chat digest
D1 model SoT · D2 e2e (step-role vs verifier-focus vs both) · D3 docs/docs-writer rename ·
D4 qa/security dual-nature card shape · D5 Max Parallel keep-with-note vs remove.
