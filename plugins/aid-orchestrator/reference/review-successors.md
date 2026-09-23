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
| `c2_acceptance_evidence` | `acceptance_evidence_from_plan_diff` |
| `c2_acceptance_deviation` | `acceptance_evidence_from_plan_diff` |

# Plan-final mechanisms: today → successor (P096)

One row per registry id retired by the plan-final rebuild. A successor is an
ACTIVE registry id, or `none (…)` naming the recorded decision.

## Registry ids retired by P096

| Removed or retired id | Successor | Note |
|-----------------------|-----------|------|
| `DG-01-dependency-consistency` | `gates_overall_pass` | the project's own blocking gates (docs/plans/P096-delivery-gate-triage.md) |
| `DG-02-build` | `gates_overall_pass` | the project's `build` gate |
| `DG-03-typecheck` | `gates_overall_pass` | the project's `type_check` gate |
| `DG-04-test` | `gates_overall_pass` | the required `tests_pass` gate, which ran the same command |
| `DG-05-consumer-compile` | `gates_overall_pass` | the project's build gate |
| `DG-06-removed-dep` | `gates_overall_pass` | project gates, and the cp3 and cp7 diff reviews |
| `DG-07-fsm-hook` | `execute_gates_all_steps` | step completeness already blocks upstream |
| `DG-07-state-consistency` | `execute_gates_all_steps` | same; open dispatches and compliance are FSM preconditions of their own |
| `DG-08-runtime-env` | `gates_overall_pass` | npm-specific; a project that needs it declares a gate |
| `DG-09-static-coverage` | `gates_overall_pass` | the idea ("0 files checked is not a pass") is backlog IMP-618 |
| `DG-10-startup-smoke` | `gates_overall_pass` | a project gate |
| `DG-11-build-config` | `gates_overall_pass` | a project gate |
| `DG-12-authority` | `policy_enforcement_values_lint` | the two rules kept as a merge-path lint |
| `DG-15-route-resolve` | `gates_overall_pass` | needed a delivery map no project had |
| `DG-17-independent-oracle-nodrop` | `gates_overall_pass` | needed oracle baselines no project had |
| `DG-18-acceptance-struct` | `final_review_round_required` | provenance only; the `final_criteria` role ties criteria to executed tests |
| `ev-observe-blocking-interpretation` | none (P096 Step 8 triage) | read only the removed gate's output |
| `plan_final_specialist_review` | `final_review_round_required` | the whole-plan round reads what the four specialists read |
| `epic_specialist_review_exception` | `fsm_review_round_required` | no specialist is left to dispatch mid-plan; the EPIC owes its cp3 round |
| `done_advance_blocking_findings` | `fsm_review_round_required` | the EPIC round verdict replaced the auditor flag (CP5) |
| `c3_blocking_high_or_critical` | `final_review_round_required` | an open blocker of the whole-plan round blocks the decision |
| `c3_independence_unverifiable` | `codex_stand_in_recorded` | the second provider is the generalist role; a stand-in is recorded, never silent |
| `c3_provenance_required` | `final_review_head_bound` | the round is bound to the candidate and to a dispatch bracket |
| `c3_verify_mismatch_unverifiable` | `final_review_head_bound` | no transformed report exists any more; answers are read as written |
| `c3_cross_provider_dispatch` | `final_review_round_required` | the Codex transport now serves the review rounds |
| `c3_ac_source_binding` | `final_review_round_required` | the final_criteria role reads the plan criteria from the frozen plan file |
| `c3_gate_enforcement_toggle` | `final_review_round_required` | the round is required unless the PM waives it for the candidate |
| `review_profile_presence` | `release_decision_input_row_shape` | review-profile is a required input of the decision |
| `curator_content_ref_guard` | none (P096: a finding is fixed by the role that wrote the code; no proposals exist) | the curator and its sequencing are gone |
| `curator_auto_rules` | none (P096: a finding is fixed by the role that wrote the code; no proposals exist) | the auto-resolution rules had no other reader |
| `cp4_curator_validation` | `fsm_review_round_required` | no self-applied fix remains; a fix is confirmed by the next round |
| `cp4_glob_invalid` | `fsm_review_round_required` | same |
| `cp4_production_paths_ere` | `fsm_review_round_required` | same; the config key is gone |
| `streamlined_cp4_advisory` | `fsm_review_round_required` | same |
| `cp4_paths_layout_aware` | `fsm_review_round_required` | same; /aid-init no longer derives the glob |
| `cp4_glob_evaluated` | `fsm_review_round_required` | same |
| `cp4_template_stale_name` | `fsm_review_round_required` | same |
| `cp4_full_range_scan` | `fsm_review_round_required` | same |
| `verifier_output_template` | `fsm_review_round_required` | CP4 was its last user; round answers follow review-finding.schema.json |
| `verifier_verdict_contract` | `fsm_review_round_required` | same |
| `behavior_trace_high_risk_gate` | `review_adjudicator_trace` | the trace rule lives in the adjudicator of the rounds |
| `delivery_report_present` | none (P096: the PM page is computed from the release decision) | reporter removed |
| `delivery_report_test_evidence` | none (P096: the PM page is computed from the release decision) | reporter removed |
| `delivery_report` | none (P096: the PM page is computed from the release decision) | toggle removed with the reporter |
| `delivery_report_template` | none (P096: the PM page is computed from the release decision) | template removed with the reporter |
| `reporter_focus_allowlist` | none (P096: the PM page is computed from the release decision) | the two foci left the dispatch allowlist |
| `reports_scope_allowed` | none (P096: the PM page is computed from the release decision) | nothing writes .aid-o/reports any more |
| `simplifier_pass` | `step_review_needless_complexity` | question 7 of the step reviewers, asked on every step |
| `release_policy_dual_run` | none (P096: the legacy verdict it compared against is gone) | the decision is logged as release_decision |
| `release_policy_preempted` | none (P096: it corrected the dual run for sampling bias) | telemetry removed |
| `pm_override_single_use_claim` | none (P096: the C3 loop it overrode is gone) | plan review keeps its own override record |
| `review_signal_toggle_fail_closed` | none (P096: the reporter and simplifier toggles are gone) | library removed |
| `gate_required_when` | `execution_yaml_dead_keys_refused` | P097 Step 6: `required:` alone decides; a file still carrying `required_when` is refused with the upgrade command |
| `gate_needs_services_fail_fast` | `execution_yaml_dead_keys_refused` | P097 Step 6: the service lifecycle is gone; a gate carrying `needs_services` is refused |
| `gate_timeout_policy_block` | `gate_timeout_fixed` | P097 Step 5: the deadline is `timeout_seconds` and nothing else; no cross-run streak |
| `gate_runtime_baseline_advisory` | `gate_timeout_fixed` | P097 Step 5: the report proposes a number, never a run mode |
| `gate_baseline_sequential_only` | `gate_timeout_fixed` | P097 Step 5: no live baseline is written during a run, so nothing to serialize |
| `service_declaration_schema` | `execution_yaml_dead_keys_refused` | P097 Step 6: a `services:` key, empty or not, is refused with the upgrade command |
| `service_lifecycle_acquire_release` | none (P097 Step 6: the sweep only ever signalled service jobs; gates keep their one owner, aid-job.sh) | nothing replaces the sweep |
| `service_registry_eager_write` | none (P097 Step 6: no service is started by a run; the library leaves in Step 9) | unreachable from the runner |
| `service_teardown_declaration_preflight` | none (P097 Step 6: no service is stopped by a run; the library leaves in Step 9) | unreachable from the runner |
