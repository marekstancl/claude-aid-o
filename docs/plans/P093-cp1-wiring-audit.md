# P093 — wiring audit of the plan review (CP1) area

Date: 2026-09-18, branch `feat/p093-plan-review` after Steps 1 to 10.
Method: every file below was read for the enforcements its header claims
(`enforce`, `refuse`, `gate`, `block`, `fail-closed`); each claim was looked up in
`plugins/aid-orchestrator/defaults/enforcement-registry.yaml` by `source:` and
its `test:` checked to exist and to exercise the refusal. Rule applied:
`docs/plans/AID-v3-principles.md` §1 — a detector with no mechanism and no
breaking test is decoration.

Verdicts: `wired` (registry row + a test that breaks it), `decoration` (claimed,
not enforced or not tested), `not an enforcement` (the file enforces nothing),
`retiring` (removed by Steps 13 and 14 of this plan).

## Files this plan builds or rewrites

| File | Enforcement claimed | Registry row | Breaking test | Verdict |
|---|---|---|---|---|
| `scripts/lib/aid-plan-review-config.sh` | refuses a role set other than the six, a duplicate, an unknown provider, a banned model, out-of-range numbers | `plan_review_config_valid` | `test-plan-review-config.bats` | wired |
| `scripts/lib/aid-plan-review-packet.sh` | packet refused when `plan-check.json` does not match the plan; answer shape; per-finding proof | `plan_review_rounds_default` (prepare), `plan_review_finding_evidence` (proof) | `test-plan-review-round.bats`, `test-plan-review-schema.bats` | wired |
| `scripts/aid-plan-review-round.sh` | round beyond the default needs `override.json`; fix outside the fix list stops the next round; round invalid below `min_answers`; a reviewer never paid twice; close needs a value per claude role | `plan_review_rounds_default`, `plan_review_fix_no_new_behaviour` | `test-plan-review-round.bats` | wired |
| `scripts/aid-plan-review-adjudicate.sh` | a finding without a read-only command or an existing `path:line` is rejected | `plan_review_finding_evidence` | `test-plan-review-adjudicate.bats` | wired |
| `scripts/lib/aid-plan-review-summary.sh` | none (reports cost) | — | `test-plan-review-summary.bats` | not an enforcement |
| `scripts/aid-cp1-gate.sh` | round evidence required; open blockers quoted in acceptance criteria; hard conditions exit 3 | `cp1_round_evidence`, `cp1_open_blocker_needs_ac` | `test-cp1-gate.bats` | wired |
| `scripts/aid-plan-check.sh` | A-, B-, C-checks; A11 (docs type hides no code); `steps_changed` / `added_outside_fixes` for fix-check | `plan_check_internal`, `plan_check_grounding`, `plan_check_revision` | `test-plan-check.bats` | wired |
| `scripts/aid-generation-readiness.sh` | runs lint, plan check, parallel check before generation | `plan_check_internal` (enforced by it) | `test-generation-readiness.sh` | wired |
| `scripts/aid-auto-pipeline.sh` (CP1 part) | one gate call per generation; exit 2/3 and three identity strings are not forceable | `generation_cp1_once_per_plan`, `generation_failure_label_classification` | `test-generation-authority.bats`, `test-generation-labels.bats` | wired |
| `defaults/policies/review-checkpoints.yaml` | `plan_review` block read by the config library; `cp1_plan_review` switch read by the gate | `plan_review_config_valid` | `test-plan-review-config.bats`, `test-cp1-gate.bats` | wired |
| `skills/plan-review-roles.md`, `defaults/prompts/plan-review-prompt-v1.md`, `defaults/schemas/plan-review-finding.schema.json` | the contract the scripts read (role sections, template, patterns) | via the rows above | `test-plan-review-schema.bats` | wired |
| `scripts/lib/aid-plan-review-adapter-claude.md` | the controller procedure for claude reviewers; quoted verbatim by `commands/aid-plan.md` | — (an instruction; its absence is caught by the gate's round checks) | `test-plan-review-schema.bats` (verbatim inclusion, focus allowlist) | wired as instruction |

## Files that leave in Steps 13 and 14

| File | Enforcement claimed | Registry row | Verdict |
|---|---|---|---|
| `scripts/lib/aid-plan-band.sh`, `defaults/policies/risk-paths.yaml` | band classification; band-scoped plan obligations | `plan_ceremony_band`, `plan_band_obligations` | retiring (Step 13) |
| `scripts/lib/aid-cp1-ledger.sh` | 5-attempt C0 budget | none left in the gate since Step 7 | retiring (Step 14) |
| `scripts/aid-c0-contract.sh`, `defaults/policies/c0-contract.yaml` | C0 artifact producer, observe only | `c0_contract_producer` (verdict `unmapped`), `c0_would_block` (planned) | decoration today; retiring (Step 14) |
| `scripts/lib/aid-c0-plan-review.sh`, `defaults/prompts/c0-plan-review-prompt-v1.md`, `defaults/schemas/c0-plan-review.schema.json`, `defaults/schemas/plan-review.schema.json` | Codex plan review loop | none left in the gate since Step 7; `plan-review.schema.json` had no reader | decoration since Step 7; retiring (Step 14) |
| `skills/review-checkpoint-contracts.md` C0 sections | C0 lens contract | `c0_lens_*` (all `planned`) | decoration; retiring (Step 14) |

## Files outside this plan's changes

| File | Enforcement claimed | Registry row | Breaking test | Verdict |
|---|---|---|---|---|
| `scripts/lib/aid-c3-dispatch.sh` (`_run_codex_isolated`) | isolated read-only Codex launch | the C3 rows | `test-c3-audit.bats`; the plan review caller: `test-plan-review-round.bats` (stubbed codex) | wired |
| `scripts/lib/aid-audit-independence.sh` | fail-closed independence detection | `c3_independence_unverifiable` with `test: null` | exercised by `test-c3-audit.bats` and `test-brainstorm-opponent.bats`, not named by the row | wired, registry row incomplete → IMP-600 |
| `scripts/lib/aid-recovery-adjudicate.sh` | authority ceiling by construction | `recovery_adjudication_allowlist` | `test-recovery-adjudicate.bats` | wired |
| `scripts/lib/aid-routed-findings.sh` | routed findings block DONE | `routed_findings_block_done` | `test-routed-findings.bats` | wired |
| `skills/plan-writing.md` Rule #21 | handler branches declare outcomes (advisory) | `cp1_critical_path_flow_trace`: `severity: medium` (not in the registry's enum), `test_anchor` instead of `test`, deadline 2026-09-01 passed while `active` | none named | decoration by the registry's own schema → IMP-601 |

## Found outside the plan (backlog)

- IMP-600 — `c3_independence_unverifiable` names no test although two suites break it.
- IMP-601 — `cp1_critical_path_flow_trace` breaks the registry schema (severity, test field, expired deadline).
- IMP-602 — `test-generation-labels.bats` cases 3, 11 and 12 fail on `main` before P093 (verified by running the suite on the main checkout on 2026-09-18).
- IMP-603 — `test-enforcement-registry-test-audit.sh`: three pre-existing baseline mismatches (`commit_path_guard`, `plan_json_hash_tamper`, `reflect_systematic`).
- IMP-604 — nightly suites already red on `main` before P093 (plan-to-epic 2, worktree-integration 9, contract-validate 1, roots-worktree 2, generation-finalize, two suites past 15 min).
- The 21 older registry rows with `severity: fail` (not in the enum) are already known from the P093 brainstorm and go with IMP-601's registry clean-up.
