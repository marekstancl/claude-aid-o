# Extending AID — a contributor reference for enforcements

This is the one place that answers: *"I want to add a new agent / gate / check /
audit signal — where does each piece go, and what makes it real instead of
decoration?"* It distils the binding conventions from
[`docs/plans/AID-v3-principles.md`](plans/AID-v3-principles.md) §1 and the P041
governance recommendation
([`docs/plans/AID-audit-2026-06/03-governance-recommendation.md`](plans/AID-audit-2026-06/03-governance-recommendation.md)),
and uses **P045 (Simplifier + Reporter)** as the end-to-end worked example.

The two binding rules behind everything below:

- **Principle #1 — Detector without Enforcement is Decoration.** A check that
  fires but blocks nothing trains the PM and the agent to ignore it. Name the
  enforcement mechanism at design time, never "later".
- **Candidate Principle #5 — Enforcement without Instruction is Cargo Cult.** The
  inverse: every enforcement needs a matching LLM-facing instruction in the
  type's canonical home, or the rule is rediscovered by failure each time.

---

## Where each enforcement type lives (the type→instruction-home table)

Every enforcement has a `type` (1–15) and exactly one canonical place where its
human/LLM-facing instruction (its "cedule") must live. This is the binding
convention from governance Component 2 — authors never have to wonder where the
instruction goes:

| Type | Enforcement | Canonical instruction home |
|------|-------------|----------------------------|
| 1 | FSM-precondition (orchestrator) | `skills/pipeline.md` (state/transition sections) |
| 2 | FSM-precondition (subagent output) | `agents/verifier.md` **or** `skills/agent-protocol.md` |
| 3 | Dispatch-wrapper | `skills/pipeline.md` §4 Dispatch Protocol |
| 4 | Structural-check | `skills/pipeline.md` (relevant §) or the generating script's header |
| 5 | Pre-filter-regex | `defaults/pre-filter-rules.yaml` (self) + `pipeline.md` §13 |
| 6 | Schema-validator (plan) | `skills/plan-writing.md` + `skills/planner.md` |
| 7 | Command-orchestration-rule | `commands/<cmd>.md` |
| 8 | Hook-enforcement | `defaults/hooks/*` + `agent-protocol.md` git discipline |
| 9 | YAML-policy-driven | the policy YAML (self) + `pipeline.md` if FSM-consumed |
| 10 | Template-shaped | the template (self) + consumer skill |
| 11 | Audit-log invariant | `agent-protocol.md` "P040 audit events" table |
| 12 | Skill-loaded-protocol | the skill itself |
| 13 | Agent-contract | `agents/<agent>.md` or `skills/role-cards.md` |
| 14 | Test-regression-gate | the `test-*.sh` itself |
| 15 | Stack-gate-binding | `defaults/execution-stacks/<lang>.yaml` |

`surface` (separate from type) splits drift risk: `llm-facing` enforcements
**require** an instruction in their home; `internal-guard` mechanisms (nonces,
flocks, source-only helpers) may set `instruction: n/a`.

---

## Checklist to add an enforcement

Do all five in the **same change** that introduces the check — "register +
document" is definition-of-done, not later cleanup:

1. **Add a registry entry** in
   `docs/plans/AID-audit-2026-06/enforcement-registry.yaml` with
   `id` / `type` / `source` / `instruction` / `severity` / `surface` / `status`.
   The `instruction` field forces the enforcement to name *where* its cedule is;
   a blank `instruction` on an `llm-facing` entry is exactly the GAP class.
2. **Put the instruction in the type's canonical home** from the table above.
3. **Declare `severity` and `surface`.** Per AID-v3-principles.md §1 tiered
   severity, new checks default to `advisory` (logged, not blocking) and are
   auto-promoted to `blocking` only after empirical validation (≈N=5 consecutive
   EPICs with no `--force` for that check, or explicit PM promotion with reason).
   `surface` is `llm-facing` or `internal-guard`.
4. **Wire the evaluator** — pick one of the three acceptable enforcement
   mechanisms and name it now, never "later":
   - FSM precondition block (refuses a state transition),
   - out-of-band hard fail (CI / pre-push hook / maintainer script the agent
     can't skip),
   - explicit PM confirmation gate with logged justification.
5. **Add a regression test** (a `test-*.sh` / bats case) so the check can't
   silently rot, and record it in the registry's `test:` field.

**What an instruction (cedule) must contain** — the 4-part minimal contract from
governance Component 2:

1. **The rule** — plain imperative ("gates_report.json must carry
   `_generated_by`").
2. **The trigger** — when the check fires (which transition / which diff / which
   output).
3. **The failure mode** — the exact reason string the user will see.
4. **The fix** — the copy-paste remediation (most `die()` messages already embed
   this).

---

## The FSM precondition pattern

There are two distinct shapes in `aid-fsm.sh`. Choose by whether you want a
promotable advisory signal or an immediate hard stop.

### Severity-layer (soft, advisory→promotable)

A top-level scalar in `evaluate_compliance_checks` whose **`false` value
`fsm_build_failures` turns into a failure entry**. The rule is simple: any
top-level boolean-`false` scalar becomes a failure (enriched with `severity` +
`promoted_at` from `check-severity.yaml`, defaulting to `advisory`); `null` and
`true` are ignored — `null` means "not applicable" and can never fail.

These failures are surfaced **only** at `cmd_done_advance review→release`, via
`_blocking_count` (it counts only `severity == "blocking"` failures; an advisory
failure is logged into `compliance.json` but release still proceeds).

- **Worked example:** `delivery_report_present` (the P045 check). Its helper
  `fsm_eval_delivery_report_present` (aid-fsm.sh ~:840) echoes a JSON literal:
  `null` before the plan boundary, `true` when the report exists and references
  ≥1 on-disk evidence artifact, `false` otherwise. Because it defaults to
  advisory, a missing report is logged but release still ships.
- **Prior art:** `dod_present` and `memory_substantive` — same soft scalar shape,
  same severity layer.

### Hard-die precondition

A `die()` / `exit 1` directly in a command path — no severity layer, no
override-by-default. Two repo examples:

- The **cross-plan init guard** (~aid-fsm.sh:1479–1501): `cmd_init` refuses to
  start a new plan when the previous plan has an `audit-report.md` but no
  `ca-review-complete` marker — `exit 1` with a remediation message.
- `fsm_check_cp4_curator_validation` (aid-fsm.sh:283) — requires the CP4 curator
  validation output when a curator commit touched production code; fails closed.

**When to choose which.** Use the severity-layer when the signal is new and you
want it advisory-then-promotable (the responsible default under §1's
tiered-severity caveat — hard-blocking on first deployment floods false
positives and trains reflexive `--force`). Use a hard-die only when an immediate
stop is correct regardless of empirical track record (an integrity invariant, a
structural impossibility).

**Plan-boundary vs per-EPIC placement.** A plan-level check must attach to the
`ca-review-complete` marker (the plan boundary), **not** to a per-EPIC
`done-advance`. `fsm_eval_delivery_report_present` returns `null` (not
applicable) until `ca-review-complete` exists in the EPIC's evidence dir —
that's what stops a plan-final check from false-blocking every non-final EPIC of
the plan.

---

## Dispatch-mode reality (agent_tool default)

`agent_tool` is the **default** dispatch mode (set in P043, commit `39a2b61`).
Resolution order: project `.aid-o/config/plugin.yaml` `dispatch_mode` → plugin
`defaults/orchestration.yaml` `dispatch.mode` → hard fallback `agent_tool`.

This matters for anti-fabrication. In `agent_tool` mode the CC Agent tool writes
**no timeline events**, so `verify_provenance` returns the non-blocking
`agent_tool` **sentinel** without checking — the timeline interval-bracket
(`verifier_dispatch_start`..`verifier_dispatch_complete`) only runs in
`subagent` mode. So in the default mode the anti-fabrication floor is:

- **structural-presence** checks (the output file actually exists),
- an **independent Auditor** pass, and
- **honest agent instructions** in `pipeline.md` (MUST-dispatch /
  MUST-NOT-self-review).

Hard, non-fabricatable provenance enforcement (the interval-bracket against a
real dispatch timeline) requires **opt-in `subagent` mode**. Don't design a new
check assuming the timeline is there by default — it isn't.

---

## Worked example: P045 Simplifier + Reporter

P045 added two plan-boundary agents end-to-end. Each artifact maps to its type
and canonical home:

- **Agent contracts (type 13).** `agents/simplifier.md` (propose-only; never
  edits code) and `agents/reporter.md` (tests the delivery, writes the report).
- **Template (type 10).** `defaults/templates/delivery-report.md` — the shape of
  `.aid-o/reports/{plan_id}-delivery.md`, including the `_test_evidence[]`
  frontmatter the structural check reads.
- **Orchestration (types 1/3).** `skills/pipeline.md` §4 (dispatch-wrapper:
  wrap reporter/simplifier dispatch by mode, emit `aid-emit-dispatch.sh`
  start/complete with `--focus reporter|simplifier`) and §7 DONE (the
  plan-boundary sequence: Simplifier after C+A fixes, Reporter last after CP4).
- **Structural check (type 4).** `fsm_eval_delivery_report_present` feeds the
  **severity layer** as `delivery_report_present` — advisory by default, surfaced
  only at `review→release`, `null` until the plan boundary.
- **Policy (type 9).** `check-severity.yaml` (the check's severity registry),
  `defaults/policies/review-checkpoints.yaml` (`simplifier_pass` /
  `delivery_report` toggles) and `execution.yaml`.
- **Dispatch guard.** `aid-emit-dispatch.sh` enforces a focus allowlist so
  `reporter` / `simplifier` are recognized dispatch foci.
- **Registry.** Entries for the new check and agents in
  `docs/plans/AID-audit-2026-06/enforcement-registry.yaml`.

**agent_tool caveat.** Because the default dispatch mode is `agent_tool`, the
Reporter's delivery report is held honest by structural presence + the
independent Auditor + the §7 dispatch instructions — not by timeline provenance.
The `delivery_report_present` check verifies the report exists and references a
real on-disk artifact; it does not (and cannot, in `agent_tool` mode) prove the
Reporter was independently dispatched. That hard guarantee needs `subagent` mode.

---

## Enforcement Homes Reference

When adding a new detection capability, register it in `defaults/enforcement-registry.yaml` with:
- `id`: unique snake_case identifier
- `type`: `fsm_precondition` | `lm_judgment_advisory` | `out_of_band_hard_fail` | `pm_confirmation_gate`
- `enforcement_mechanism`: the exact mechanism (see AID-v3-principles.md §1)
- `test_anchor`: path to the bats/sh test that proves it works
- `deadline`: ISO date after which the TTL guard flags it if not tested

### Plan Boundary Enforcement

- **plan-close gate**: `aid-fsm.sh:cmd_plan_close()` — enforces all 4 required reports (curator-report, audit-report, simplifier-report, delivery-report) before `ca-review-complete` marker. Bypass: toggle-skip pattern with PM rationale.
- **CI floor**: `defaults/ci/plan-boundary-required-check.yml` — GitHub Actions check for committed boundary manifests in `.aid-o/reports/`. Requires `!.aid-o/reports/` in `.gitignore` (see `commands/aid-init.md`).

### CP5 Contract

- **blocking_findings check**: `aid-fsm.sh:cmd_done_advance()` — reads `blocking_findings` field from `audit-report.md` as a structured top-level field (not prose). `blocking_findings: true` blocks the MERGE option in the PM summary.
- **Contract location**: `skills/review-checkpoint-contracts.md` §CP4 Contract.

### behavior_trace Enforcement

- **High-risk patterns**: 8 categories in `skills/review-checkpoint-contracts.md` (auth, routes, validation, migrations, fsm, security sinks, payment, dep manifests).
- **Structural gate**: `aid-fsm.sh:fsm_check_verifier_output()` — fires when `behavior_trace_required: true` explicitly set in verifier output. Returns non-zero if `behavior_trace_count == 0`.
- **Per-checkpoint diff scope**: `aid-prefilter.sh --checkpoint <cp2|cp3|cp4|cp6>` — CP2=step diff, CP3=base_commit..HEAD, CP4=applied C+A diff.

---

**Last Updated:** 2026-06-19
