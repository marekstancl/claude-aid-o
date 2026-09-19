_generated_by: aid-orchestrator:verifier@s03-wan-E-084-1_1-step0
_generated_at: 2026-09-19T00:00:00Z
classification: FULL_REVIEW
verdict: fail
findings:
  - severity: medium
    file: docker-compose.yml:68-77
    description: >
      Change adds two new bind mounts (`./pyproject.toml:/pyproject.toml:ro`,
      `./CHANGELOG.md:/CHANGELOG.md:ro`) to the `wan-ui` service. This file is
      not listed in step_outputs (in-scope files are limited to
      `wan/api/scan.py`, `tests/integration/test_conflict_contract.py`,
      `tests/unit/test_om_ownership_conflict.py`, `ui/src/lib/validationInbox.ts`,
      `ui/src/hooks/useSessions.ts`, `ui/src/lib/validationInbox.test.ts`,
      `.aid-o/config/execution.yaml`). The change is unrelated to the conflict-
      shape unification objective of this step (it fixes a vitest config-load
      failure inside the `wan-ui` container).
    recommendation: >
      Move this fix to its own step/PR, or confirm with the plan owner that
      docker-compose.yml is meant to be in scope here; if intentional, the
      step_outputs list must be updated to say so.
  - severity: medium
    file: ui/vitest.config.ts:20-66
    description: >
      Adds `readAppVersionForTests()` / `loadChangelogForTests()` fallback
      wrappers around the existing `__APP_VERSION__` / `__CHANGELOG__` define
      block. Not listed in step_outputs and unrelated to the `conflicts[]`
      contract objective — it is a defensive fix for the same container-mount
      problem addressed in docker-compose.yml.
    recommendation: >
      Same as above — out-of-scope for this step's DoD; split into a separate
      change or explicitly amend scope.
  - severity: low
    file: ui/e2e/session-detail-om-transfer.spec.ts:266
    description: >
      Cosmetic comment edit (removes backticks around `mc rm`) inside a
      Python-in-JS-fixture docstring/comment, unrelated to any AC and not in
      step_outputs.
    recommendation: >
      Harmless, but should not have been bundled into this diff; drop from
      this step's patch or note it as an incidental cleanup explicitly.
  - severity: info
    file: wan/api/scan.py:4055-4225 (_build_om_conflict, _check_identity_conflicts)
    description: >
      AC1 verified: both `_check_identity_conflicts` (via new shared
      `_build_om_conflict` helper) and `_find_om_ownership_conflicts` now
      build the `conflicts[]` entry from the same function, producing the
      same 7 keys (`payload_ordinal`, `point_number`, `point_type`,
      `conflicting_dp_id`, `owner_person_id`, `owner_name`,
      `owner_birth_date_or_ico`). Confirmed statically and via the new test
      `test_both_gates_return_identical_conflict_shape`, which asserts
      `identity == ownership` directly.
    recommendation: none — meets AC1.
  - severity: info
    file: wan/api/scan.py:4183-4199, tests/integration/test_conflict_contract.py:258-281
    description: >
      AC2 verified: when the conflicting point number is only present in raw
      GDPR data (no matching entry in `body.delivery_points`),
      `payload_ordinal_by_number` has no entry for it and
      `_build_om_conflict` receives `payload_ordinal=None`; covered by
      `test_raw_only_conflict_has_null_payload_ordinal`.
    recommendation: none — meets AC2.
  - severity: info
    file: .aid-o/config/execution.yaml:191
    description: >
      AC3 verified: `tests/integration/test_conflict_contract.py` was appended
      to the `p079_moved_integration_tests` gate command, so the new file is
      actually collected/run by the curated gate list, not just present on
      disk.
    recommendation: none — meets AC3.
  - severity: info
    file: wan/api/scan.py (gate order in confirm_session, ~4762-4779)
    description: >
      Forbidden-path check: gate ordering (`_check_wanis_placeholder_access`
      → `_check_identity_conflicts` → `_check_om_ownership_conflicts`) is
      unchanged by this diff — read directly at the named commit, order
      matches the pre-existing sequence. No touch to the WANIS legacy
      collision step, no data-migration code, and no change to the
      `POST /persons/{id}/om-transfers` endpoint beyond what is already
      covered by validationInbox/useSessions typing changes for
      `conflicts[]`.
    recommendation: none — no forbidden-path violation found.
  - severity: info
    file: tests/unit/test_om_ownership_conflict.py:81-86
    description: >
      AC4-adjacent: this test (explicitly listed as an in-scope Modify) was
      updated in place to assert the new `payload_ordinal` key and the
      absence of `ordinal`, consistent with the DoD's stated rename. No other
      named identity-gate tests in step_outputs/forbidden_paths appear
      modified in the diff, which is consistent with "existing named identity
      gate tests pass unchanged" — but this verifier has no test-execution
      capability (read-only review of the diff/commit only), so AC4's runtime
      claim ("projít beze změny") is not itself executed/confirmed here.
    recommendation: >
      Confirm AC4 via the actual GATES run output (this step's evidence
      should also include a pytest run, not just a static diff review).
