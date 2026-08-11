## Measured tier assignment

- Measured on: `eco-dev`
- Newest measurement: `2026-08-11T03:11:43.623Z`
- Suites discovered: 202 — tiered 202, unmeasured 0
- T0: 27 suite(s), 117894 ms total
- T1: 14 suite(s), 559009 ms total
- T2: 161 suite(s), 24447934 ms total

| Suite | Runner | Subject | ms | Cases | ms/case | Tier | Reason | Demoted from |
|---|---|---|---|---|---|---|---|---|
| `test-aid-gate-runtime-report.bats` | bats | `scripts/aid-gate-runtime-report.sh` | 12339 | 12 | 1028 | **t0** | under 2s per case | - |
| `test-aid-test-execution-unit.bats` | bats | `scripts/lib/aid-test-execution-unit.sh` | 12017 | 11 | 1092 | **t0** | under 2s per case | - |
| `test-aid-gitignore-backfill.bats` | bats | `scripts/lib/aid-gitignore-backfill.sh` | 10512 | 16 | 657 | **t0** | under 2s per case | - |
| `test-aid-nightly-report.bats` | bats | `scripts/aid-nightly-report.sh` | 9862 | 11 | 896 | **t0** | under 2s per case | - |
| `test-aid-test-execution-ledger.bats` | bats | `scripts/aid-test-execution-ledger.sh` | 8468 | 21 | 403 | **t0** | under 2s per case | - |
| `test-aid-select-tests.bats` | bats | `scripts/aid-select-tests.sh` | 8381 | 27 | 310 | **t0** | under 2s per case | - |
| `test-aid-test-adapter-declared-command.bats` | bats | `scripts/lib/aid-test-adapter-declared-command.sh` | 5421 | 6 | 903 | **t0** | under 2s per case | - |
| `test-aid-test-adapter-bats.bats` | bats | `scripts/lib/aid-test-adapter-bats.sh` | 4917 | 9 | 546 | **t0** | under 2s per case | - |
| `test-aid-test-reaper.bats` | bats | `scripts/aid-test-reaper.sh` | 4815 | 10 | 481 | **t0** | under 2s per case | - |
| `test-aid-test-audit-profile-select.bats` | bats | `scripts/aid-test-audit-profile-select.sh` | 4666 | 15 | 311 | **t0** | under 2s per case | - |
| `test-aid-test-timing-bats.bats` | bats | `scripts/lib/aid-test-timing-bats.sh` | 4438 | 16 | 277 | **t0** | under 2s per case | - |
| `test-aid-test-tier-assign.bats` | bats | `scripts/aid-test-tier-assign.sh` | 3874 | 8 | 484 | **t0** | under 2s per case | - |
| `test-aid-emit-dispatch.bats` | bats | `scripts/aid-emit-dispatch.sh` | 3433 | 15 | 228 | **t0** | under 2s per case | - |
| `test-aid-obligations.bats` | bats | `scripts/lib/aid-obligations.sh` | 2569 | 10 | 256 | **t0** | under 2s per case | - |
| `test-aid-test-audit-command-allowlist.bats` | bats | `scripts/lib/aid-test-audit-command-allowlist.sh` | 2453 | 12 | 204 | **t0** | under 2s per case | - |
| `test-aid-test-tier-lint.bats` | bats | `scripts/aid-test-tier-lint.sh` | 2428 | 10 | 242 | **t0** | under 2s per case | - |
| `test-aid-init.bats` | bats | `commands/aid-init.md` | 2346 | 13 | 180 | **t0** | under 2s per case | - |
| `test-aid-execution-unit-membership.bats` | bats | `scripts/lib/aid-execution-unit-membership.sh` | 2326 | 9 | 258 | **t0** | under 2s per case | - |
| `test-aid-gate-profile.bats` | bats | `scripts/lib/aid-gate-profile.sh` | 1995 | 30 | 66 | **t0** | under 2s per case | - |
| `test-aid-test-adapter-package-script.bats` | bats | `scripts/lib/aid-test-adapter-package-script.sh` | 1882 | 5 | 376 | **t0** | under 2s per case | - |
| `test-aid-init-upgrade-test-audit.bats` | bats | `scripts/aid-init-upgrade-test-audit.sh` | 1666 | 11 | 151 | **t0** | under 2s per case | - |
| `test-aid-test-durations.bats` | bats | `scripts/lib/aid-test-durations.sh` | 1487 | 7 | 212 | **t0** | under 2s per case | - |
| `test-aid-test-content-scan.bats` | bats | `scripts/aid-test-content-scan.sh` | 1467 | 6 | 244 | **t0** | under 2s per case | - |
| `test-aid-release.bats` | bats | `scripts/aid-release.sh` | 1401 | 3 | 467 | **t0** | under 2s per case | - |
| `test-aid-test-audit-config.bats` | bats | `scripts/lib/aid-test-audit-config.sh` | 1205 | 6 | 200 | **t0** | under 2s per case | - |
| `test-aid-test-audit-report.bats` | bats | `scripts/aid-test-audit-report.sh` | 1005 | 5 | 201 | **t0** | under 2s per case | - |
| `test-aid-epic-summary.bats` | bats | `scripts/aid-epic-summary.sh` | 521 | 2 | 260 | **t0** | under 2s per case | - |
| `test-aid-run-gates.bats` | bats | `scripts/aid-run-gates.sh` | 127698 | 44 | 2902 | **t1** | under 30s per case | - |
| `test-aid-gate-waiver.bats` | bats | `scripts/aid-gate-waiver.sh` | 61360 | 24 | 2556 | **t1** | under 30s per case | - |
| `test-aid-test-audit-dispatch.bats` | bats | `scripts/aid-test-audit-dispatch.sh` | 58462 | 27 | 2165 | **t1** | under 30s per case | - |
| `test-aid-job.bats` | bats | `scripts/aid-job.sh` | 52888 | 21 | 2518 | **t1** | under 30s per case | - |
| `test-aid-test-audit-state.bats` | bats | `scripts/lib/aid-test-audit-state.sh` | 44295 | 18 | 2460 | **t1** | under 30s per case | - |
| `test-aid-test-adapter-shell-suite.bats` | bats | `scripts/lib/aid-test-adapter-shell-suite.sh` | 43463 | 25 | 1738 | **t1** | demoted: the T0 budget of 2 min was exceeded | t0 |
| `test-aid-test-audit-consolidate.bats` | bats | `scripts/aid-test-audit-consolidate.sh` | 28626 | 19 | 1506 | **t1** | demoted: the T0 budget of 2 min was exceeded | t0 |
| `test-aid-gate-runtime-baseline.bats` | bats | `scripts/lib/aid-gate-runtime-baseline.sh` | 27571 | 15 | 1838 | **t1** | demoted: the T0 budget of 2 min was exceeded | t0 |
| `test-aid-test-audit-measure.bats` | bats | `scripts/lib/aid-test-audit-measure.sh` | 25498 | 12 | 2124 | **t1** | under 30s per case | - |
| `test-aid-test-audit-chat-summary.bats` | bats | `scripts/lib/aid-test-audit-chat-summary.sh` | 24089 | 28 | 860 | **t1** | demoted: the T0 budget of 2 min was exceeded | t0 |
| `test-aid-test-audit-write-plan-bridge.bats` | bats | `scripts/lib/aid-test-audit-write-plan-bridge.sh` | 19891 | 21 | 947 | **t1** | demoted: the T0 budget of 2 min was exceeded | t0 |
| `test-aid-prefilter.bats` | bats | `scripts/aid-prefilter.sh` | 17420 | 23 | 757 | **t1** | demoted: the T0 budget of 2 min was exceeded | t0 |
| `test-aid-plan-close-check.bats` | bats | `scripts/aid-plan-close-check.sh` | 15145 | 23 | 658 | **t1** | demoted: the T0 budget of 2 min was exceeded | t0 |
| `test-aid-test-audit-decision.bats` | bats | `scripts/lib/aid-test-audit-decision.sh` | 12603 | 34 | 370 | **t1** | demoted: the T0 budget of 2 min was exceeded | t0 |
| `test-aid-plan-final-boundary.bats` | bats | `unresolvable` | 11963742 | 261 | 45838 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-plan-release-boundary.bats` | bats | `unresolvable` | 2729816 | 267 | 10224 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-supersede-generation.bats` | bats | `unresolvable` | 652024 | 13 | 50155 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-generation-resume.bats` | bats | `unresolvable` | 628604 | 12 | 52383 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-worktree-integration.bats` | bats | `unresolvable` | 571016 | 9 | 63446 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-test-inventory.bats` | bats | `scripts/aid-test-inventory.sh` | 507581 | 19 | 26714 | **t2** | demoted: the T1 budget of 10 min was exceeded | t1 |
| `test-aid-c3-dispatch.bats` | bats | `scripts/lib/aid-c3-dispatch.sh` | 454161 | 145 | 3132 | **t2** | demoted: the T1 budget of 10 min was exceeded | t1 |
| `test-c3-audit.bats` | bats | `unresolvable` | 423181 | 50 | 8463 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-c3-fix-loop.bats` | bats | `unresolvable` | 398406 | 33 | 12072 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-c0-plan-review.bats` | bats | `unresolvable` | 326527 | 72 | 4535 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-generation-authority.bats` | bats | `unresolvable` | 297235 | 11 | 27021 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-release-policy.bats` | bats | `unresolvable` | 294658 | 78 | 3777 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-test-audit-reconciliation.bats` | bats | `unresolvable` | 237956 | 66 | 3605 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-branch-restore.bats` | bats | `unresolvable` | 230608 | 8 | 28826 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-test-audit-profile.bats` | bats | `scripts/aid-test-audit-profile.sh` | 219292 | 21 | 10442 | **t2** | demoted: the T1 budget of 10 min was exceeded | t1 |
| `test-review-equivalence.bats` | bats | `unresolvable` | 202695 | 27 | 7507 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-roots-worktree.bats` | bats | `unresolvable` | 186368 | 32 | 5824 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-supersede-recovery.bats` | bats | `unresolvable` | 162655 | 27 | 6024 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-worktree-enforcement.bats` | bats | `unresolvable` | 148650 | 24 | 6193 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-drift-equivalence.bats` | bats | `unresolvable` | 145780 | 20 | 7289 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-service.bats` | bats | `scripts/lib/aid-service.sh` | 142821 | 31 | 4607 | **t2** | demoted: the T1 budget of 10 min was exceeded | t1 |
| `test-aid-fsm.bats` | bats | `scripts/aid-fsm.sh` | 139889 | 109 | 1283 | **t2** | demoted: the T1 budget of 10 min was exceeded | t1 |
| `test-worktree-teardown.bats` | bats | `unresolvable` | 113296 | 15 | 7553 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-audit-tests-finalize-production.bats` | bats | `unresolvable` | 111504 | 33 | 3378 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-epic-chain-freshness.bats` | bats | `unresolvable` | 108351 | 9 | 12039 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-protected-surface.bats` | bats | `unresolvable` | 107524 | 19 | 5659 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-status-two-streams.bats` | bats | `unresolvable` | 105825 | 28 | 3779 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-reporter-boundary.bats` | bats | `unresolvable` | 93370 | 20 | 4668 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-resume-command.bats` | bats | `unresolvable` | 90913 | 11 | 8264 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-full-pipeline.sh` | sh | `unresolvable` | 90569 | 1 | 90569 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-evidence-verify.sh` | sh | `unresolvable` | 88097 | 1 | 88097 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-tiered-severity.bats` | bats | `unresolvable` | 88087 | 17 | 5181 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-service-lifecycle.bats` | bats | `unresolvable` | 85983 | 12 | 7165 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-worktree-create.bats` | bats | `unresolvable` | 85295 | 16 | 5330 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-c3-activation.bats` | bats | `unresolvable` | 83277 | 32 | 2602 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-recovery-ladder.bats` | bats | `unresolvable` | 80310 | 19 | 4226 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-lock-target-audit.bats` | bats | `unresolvable` | 78331 | 2 | 39165 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-generation-labels.bats` | bats | `unresolvable` | 77654 | 15 | 5176 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-routed-findings.bats` | bats | `unresolvable` | 71312 | 11 | 6482 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-gate-background.bats` | bats | `unresolvable` | 66821 | 8 | 8352 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-authority-verify.bats` | bats | `unresolvable` | 66624 | 14 | 4758 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-scoped-preflights.bats` | bats | `unresolvable` | 64311 | 8 | 8038 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-selector-snapshot-readonly.bats` | bats | `unresolvable` | 60630 | 7 | 8661 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-lifecycle-e2e.bats` | bats | `unresolvable` | 60549 | 18 | 3363 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-fsm.sh` | sh | `unresolvable` | 60496 | 27 | 2240 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-owned-jobs-integration.bats` | bats | `unresolvable` | 57236 | 4 | 14309 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-contract-validate.bats` | bats | `unresolvable` | 56892 | 21 | 2709 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-cp1-ledger.bats` | bats | `unresolvable` | 55339 | 53 | 1044 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-c3-advisory.bats` | bats | `unresolvable` | 54391 | 17 | 3199 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-integration-self-host-audit.sh` | sh | `unresolvable` | 53100 | 1 | 53100 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-protocol-validate.sh` | sh | `unresolvable` | 52922 | 1 | 52922 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-owned-jobs-review-regressions.bats` | bats | `unresolvable` | 52852 | 11 | 4804 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-auto-resume-artifact.bats` | bats | `unresolvable` | 50973 | 12 | 4247 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-regression.sh` | sh | `unresolvable` | 47633 | 1 | 47633 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-force-framework-integration.bats` | bats | `unresolvable` | 45327 | 14 | 3237 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-worktree-topology.bats` | bats | `unresolvable` | 43847 | 8 | 5480 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-drift-worktree.bats` | bats | `unresolvable` | 40485 | 6 | 6747 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-recovery-adjudicate.bats` | bats | `unresolvable` | 38926 | 25 | 1557 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-active-index.bats` | bats | `unresolvable` | 35839 | 11 | 3258 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-generation-finalize.sh` | sh | `unresolvable` | 34543 | 1 | 34543 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-integration-e2e-audit-pipeline.sh` | sh | `unresolvable` | 31067 | 1 | 31067 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-force-commands.bats` | bats | `unresolvable` | 28668 | 19 | 1508 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-generation-parsers.bats` | bats | `unresolvable` | 28059 | 21 | 1336 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-delivery-gate.sh` | sh | `unresolvable` | 28051 | 1 | 28051 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-integration-phase1.sh` | sh | `unresolvable` | 27996 | 7 | 3999 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-force.bats` | bats | `unresolvable` | 24729 | 23 | 1075 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-pm-brief.bats` | bats | `unresolvable` | 23430 | 23 | 1018 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-service-declaration.bats` | bats | `unresolvable` | 20137 | 13 | 1549 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-run-gates.sh` | sh | `unresolvable` | 19286 | 15 | 1285 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-active-runs-map.bats` | bats | `unresolvable` | 18797 | 15 | 1253 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-to-epic.sh` | sh | `unresolvable` | 16630 | 1 | 16630 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-run-all-tests-result-grammar.bats` | bats | `unresolvable` | 16366 | 29 | 564 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-integration-audit-report-shapes.sh` | sh | `unresolvable` | 16173 | 1 | 16173 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-c0-contract.sh` | sh | `unresolvable` | 15591 | 1 | 15591 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-run-mode-advice.bats` | bats | `unresolvable` | 15159 | 4 | 3789 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-watchdog-stall.bats` | bats | `unresolvable` | 15140 | 6 | 2523 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-lifecycle-reconcile.bats` | bats | `unresolvable` | 13465 | 14 | 961 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-json-to-run.sh` | sh | `unresolvable` | 13065 | 1 | 13065 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-catalog-confirm-mapping.bats` | bats | `unresolvable` | 12382 | 8 | 1547 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-epic-to-json-regression.sh` | sh | `unresolvable` | 10978 | 1 | 10978 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-epic-to-json.sh` | sh | `unresolvable` | 10866 | 1 | 10866 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-run-gates-worktree-paths.bats` | bats | `unresolvable` | 10406 | 6 | 1734 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-alloc-lock.bats` | bats | `unresolvable` | 10072 | 13 | 774 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-force-init-passthrough.sh` | sh | `unresolvable` | 10069 | 1 | 10069 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-select-tests-catalog-convergence.bats` | bats | `unresolvable` | 9731 | 11 | 884 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-committed-source.bats` | bats | `unresolvable` | 9505 | 18 | 528 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-force-anomalies.bats` | bats | `unresolvable` | 9276 | 19 | 488 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-close.bats` | bats | `unresolvable` | 9025 | 17 | 530 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-cache-preflight.bats` | bats | `unresolvable` | 8814 | 13 | 678 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-dep-grammar.bats` | bats | `unresolvable` | 8786 | 26 | 337 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-fsm-dg07-observe.bats` | bats | `unresolvable` | 8518 | 2 | 4259 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-enforcement-registry-test-audit.sh` | sh | `unresolvable` | 8323 | 1 | 8323 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-review-profile.sh` | sh | `unresolvable` | 8126 | 1 | 8126 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-selector-mappings-real-seed.bats` | bats | `unresolvable` | 7839 | 6 | 1306 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-check-severity-sync.sh` | sh | `unresolvable` | 7804 | 1 | 7804 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-c3-audit-prompt.bats` | bats | `unresolvable` | 7432 | 17 | 437 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-release-changelog-entry.bats` | bats | `unresolvable` | 7296 | 15 | 486 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-e2e-evidence-clean.bats` | bats | `unresolvable` | 6869 | 13 | 528 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-test-audit-prompts-golden.bats` | bats | `unresolvable` | 6780 | 18 | 376 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-cp1-gate.sh` | sh | `unresolvable` | 6692 | 1 | 6692 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-run-all-timing.bats` | bats | `unresolvable` | 6382 | 6 | 1063 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-nightly-reminder.bats` | bats | `unresolvable` | 6325 | 8 | 790 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-commit-guard.bats` | bats | `unresolvable` | 5710 | 20 | 285 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-invalidation-map.bats` | bats | `unresolvable` | 5508 | 10 | 550 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-audit-tests-cli.bats` | bats | `unresolvable` | 5456 | 32 | 170 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-semantic-review.sh` | sh | `unresolvable` | 5390 | 1 | 5390 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-ui-calibration-verify.bats` | bats | `unresolvable` | 5385 | 15 | 359 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-generation-readiness.sh` | sh | `unresolvable` | 5184 | 1 | 5184 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-release.sh` | sh | `unresolvable` | 4948 | 10 | 494 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-catalog-force-tracked.bats` | bats | `unresolvable` | 4916 | 8 | 614 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-pm-override.bats` | bats | `unresolvable` | 4847 | 17 | 285 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-tier-declaration.bats` | bats | `unresolvable` | 4794 | 8 | 599 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-select-tests-emit-units.bats` | bats | `unresolvable` | 4762 | 8 | 595 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-test-catalog-schema.bats` | bats | `unresolvable` | 4696 | 14 | 335 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-lint.bats` | bats | `unresolvable` | 4691 | 19 | 246 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-selector-honesty-check.bats` | bats | `unresolvable` | 4574 | 7 | 653 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-queue-revalidation.bats` | bats | `unresolvable` | 4549 | 8 | 568 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-compliance.bats` | bats | `unresolvable` | 4462 | 4 | 1115 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-anti-fabrication.bats` | bats | `unresolvable` | 3963 | 6 | 660 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-integration-remediation-handoff.sh` | sh | `unresolvable` | 3873 | 1 | 3873 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-execution-unit-receipt-schema.bats` | bats | `unresolvable` | 3868 | 11 | 351 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-run-all-delegation.sh` | sh | `unresolvable` | 3527 | 1 | 3527 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-release-detection.bats` | bats | `unresolvable` | 3387 | 6 | 564 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-diff.sh` | sh | `unresolvable` | 2817 | 1 | 2817 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-cp3-freshness.bats` | bats | `unresolvable` | 2765 | 9 | 307 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-lifecycle.bats` | bats | `unresolvable` | 2734 | 15 | 182 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-fsm-step-render.bats` | bats | `unresolvable` | 2580 | 9 | 286 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-run-all-tier-filter.bats` | bats | `unresolvable` | 2264 | 7 | 323 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-plan-to-epic-fence.bats` | bats | `unresolvable` | 2243 | 2 | 1121 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-ac-diff.bats` | bats | `unresolvable` | 2074 | 8 | 259 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-auto-recovery-policy.bats` | bats | `unresolvable` | 2070 | 12 | 172 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-queue-add.sh` | sh | `unresolvable` | 1919 | 1 | 1919 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-ancillary-classifier.bats` | bats | `unresolvable` | 1819 | 18 | 101 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-stage-log.sh` | sh | `unresolvable` | 1809 | 10 | 180 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-ui-fidelity-e2e.sh` | sh | `unresolvable` | 1727 | 1 | 1727 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-control-boundary.sh` | sh | `unresolvable` | 1621 | 1 | 1621 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-fsm-ui-fidelity.sh` | sh | `unresolvable` | 1425 | 1 | 1425 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-delivery-report.bats` | bats | `unresolvable` | 1384 | 6 | 230 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-behavior-trace.bats` | bats | `unresolvable` | 1372 | 6 | 228 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-registry-ttl.bats` | bats | `unresolvable` | 1360 | 13 | 104 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-release-seal.bats` | bats | `unresolvable` | 1353 | 6 | 225 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-hooks-worktree.bats` | bats | `unresolvable` | 1295 | 6 | 215 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-token-count.sh` | sh | `unresolvable` | 875 | 10 | 87 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-skill-lint.sh` | sh | `unresolvable` | 815 | 1 | 815 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-instruction-sweep.sh` | sh | `unresolvable` | 812 | 1 | 812 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-init-test-audit-config.bats` | bats | `unresolvable` | 779 | 5 | 155 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-tier-gate-routing.bats` | bats | `unresolvable` | 724 | 7 | 103 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-scope-check.sh` | sh | `unresolvable` | 706 | 5 | 141 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-delivery-profile.sh` | sh | `unresolvable` | 654 | 1 | 654 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-aid-test-portfolio-analyst-focus.bats` | bats | `unresolvable` | 604 | 7 | 86 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-owned-jobs-docs-closure.bats` | bats | `unresolvable` | 589 | 10 | 58 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-pipeline-c3-dispatch.bats` | bats | `unresolvable` | 552 | 13 | 42 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-instruction-closure.bats` | bats | `unresolvable` | 541 | 6 | 90 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-deferred-work-registration.bats` | bats | `unresolvable` | 414 | 7 | 59 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-instruction-consistency.sh` | sh | `unresolvable` | 378 | 1 | 378 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-ci-floor.bats` | bats | `unresolvable` | 328 | 4 | 82 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-run-mode-field.bats` | bats | `unresolvable` | 276 | 4 | 69 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-writing-rules.bats` | bats | `unresolvable` | 244 | 6 | 40 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-release-policy-surface-check.bats` | bats | `unresolvable` | 219 | 7 | 31 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-plan-quality-enforcement.sh` | sh | `unresolvable` | 58 | 1 | 58 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
| `test-cp1-grounding.sh` | sh | `unresolvable` | 41 | 1 | 41 | **t2** | unresolvable subject — cross-component by the standard scope rule | - |
