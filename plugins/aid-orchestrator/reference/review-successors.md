# Review mechanisms: today → successor (P094)

**P094 Step 12.** One row per registry id retired or removed by the step and
EPIC review rebuild, and one per mechanism that had no registry row of its own.
The successor column names an ACTIVE registry id, a file, or the literal
`none (PM 2026-09-19 7A)` — the PM's decision that the invalidation map goes
with no replacement. `scripts/tests/test-review-successors.sh` checks that every
id present in `scripts/tests/fixtures/review-successors/registry-ids-pre-P094.txt`
and absent or retired in the live registry has a row here whose successor is
an active id or that literal.

## Registry ids

| Removed or retired id | Successor | Note |
|-----------------------|-----------|------|
| `plan_review_config_valid` | `review_config_valid` | one config reader for every checkpoint (Step 2) |
| `plan_review_finding_evidence` | `review_adjudicator_evidence` | one answer contract, `defaults/schemas/review-finding.schema.json` (Step 2) |
| `cp2_verifier_output` | `fsm_review_round_required` | `cp2/step-N/rounds.json` at HEAD (Step 8) |
| `cp3_integration_precond` | `fsm_review_round_required` | `cp3/rounds.json` with a closed passing round (Step 8) |
| `cp3_generated_by` | `fsm_review_round_required` | the round index is the evidence (Step 8) |
| `cp3_head_freshness` | `fsm_review_round_head_bound` | `round.json.head_sha`, D4 exception kept (Step 8) |
| `verifier_provenance` | `review_dispatch_recorded` | an answer counts only inside its dispatch bracket (Step 6); a stubbed round never advances (`fsm_review_round_head_bound`) |
| `provenance_aggregate_fabricated` | `review_dispatch_recorded` | same removal |
| `aid_do_prefilter_fixloop` | `aid_do_review_advisory` | fast mode on the same mechanism (Step 9) |
| `prefilter_fail_rules` | `step_check_security_rules` | `security.matched_rules` in `step-check.json` adds the security reviewer (Step 3) |
| `prefilter_skip_rules` | `step_check_range` | the step check decides `skip`, bound to HEAD and its timeline event (Step 3, `fsm_review_round_skip_bound`) |
| `prefilter_conservative_default` | `step_check_range` | an undeterminable range is a refusal (Step 3) |
| `cp2_step_range` | `step_check_range` | range from the previous step commit (Step 3) |
| `c2_dual_emit` | `epic_review_semantic_final` | the cp3 close writes `<run>/semantic-review-final.json` (Step 7); the verifier keeps the plan-final producer |
| `invalidation_map_observe` | none (PM 2026-09-19 7A) | removed entirely |
| `invalidation_map_expected` | none (PM 2026-09-19 7A) | removed entirely |
| `behavior_trace_high_risk_gate` | `review_adjudicator_trace` | narrowed to CP4 in the registry; at cp2/cp3 the adjudicator rejects a generalist blocker/major on a handler pattern without a `behaviour_trace` (Step 5) |
| `verifier_output_template` | `verifier_output_template` | kept, CP4 only |
| `verifier_verdict_contract` | `verifier_verdict_contract` | kept, CP4 only |

## Mechanisms without a registry row of their own

| Today (before P094) | Successor |
|---------------------|-----------|
| `aid-prefilter.sh classify` (pre-filter classification, `verifier-output-step-N.md` seed) | `scripts/aid-step-check.sh` → `step-check.json`, `rounds.json` for skip/no_change |
| trivial skip (`skip_trivial`, `trivial_threshold`) | `step_check_range` (`skip_threshold` in `review-checkpoints.yaml`, scope and pattern conditions) |
| verifier focuses `code-review` / `security` at cp2/cp3 | `skills/step-review-roles.md` roles (`step_generalist`, `step_security`, `epic_generalist`, `epic_behaviour`, `epic_security`) |
| verifier output header (`_generated_by`, `_generated_at`, `classification`, `verdict`) | `reviewer-<role>.json` per `review-finding.schema.json`; `measurement.json` per round |
| `Reviewed-Head:` | `round.json.head_sha` (`fsm_review_round_head_bound`) |
| step binding (IMP-263 in `step-N-verify.md`) | kept as is (increment-step still validates it) |
| behaviour trace fields (`behavior_trace_required`, `behavior_trace_count`) | `behaviour_trace` on a finding; `handler_patterns` in `step-check.json` (`review_adjudicator_trace`) |
| fix loop and gate-fixer at CP2/CP3 (`fix_loop.max_iterations`) | the step's role fixes (`fix_of:`), confirmation round, `rounds_default`; the gate-fixer keeps GATES and CP4 |
| E7 (verifier review failed after 2 fix-loop iterations) | the PM card after the last allowed round; `override` records the PM's words (`review_round_override_recorded`) |
| `dispatch_mode: subagent` wrappers for cp2/cp3 | the adapter's dispatch bracket for every claude reviewer (`review_dispatch_recorded`) |
| C2 `local` / `wiring` / `behavior` emits | none at cp2 (the round's findings are the evidence); the plan-final `final` mode stays with the verifier |
| invalidation map (`aid-invalidation-map.sh`, `gate_fixer_fix_applied`) | none (PM 2026-09-19 7A) |
| `verify_provenance`, `provenance_aggregate`, `cp2_per_step_provenance` | `review_dispatch_recorded`; compliance reports `cp2_rounds` / `cp3_round` |
| CP3 `semantic-review-final.json` | kept at the run root, written by the cp3 close (`epic_review_semantic_final`) |
| CP6 verifier (`/aid-do`) | `aid_do_review_advisory` |
| streamlined skip of cp2 | kept: increment-step skips the cp2 round in streamlined mode; done-advance needs the cp3 index |
| routing of open findings (`aid_finding_route`, instruction) | `review_open_findings_routed` (mechanical, in `close`) |
| carried obligations (`aid_obligation_add`, instruction) | `review_open_findings_routed` (a cp2 finding a later step covers) |
| `review-profile.json` producer (the retired pre-filter's `profile` subcommand) | `scripts/aid-review-profile.sh` (split out in Step 14; same output) |
