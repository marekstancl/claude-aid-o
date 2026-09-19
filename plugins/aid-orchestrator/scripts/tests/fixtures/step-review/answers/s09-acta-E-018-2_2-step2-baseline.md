_generated_by: aid-orchestrator:verifier@s09-acta-E-018-2_2-step2
_generated_at: 2026-09-19T00:00:00Z
classification: FULL_REVIEW
verdict: pass
findings:
  - severity: low
    file: frontend/e2e/help-structure.spec.ts
    line: 1
    description: >
      step_outputs lists this file as "Modify: ... rozšířit o kontrolu nových sekcí",
      but the diff (33602252..4e00c720) does not touch it at all — it only adds
      backend/tests/e2e/test_p018_full.py and frontend/e2e/p018-regression.spec.ts.
      Checked at commit 4e00c720: the file is already registry-driven
      (`for (const cfg of HELP_SECTIONS) ...`), and HELP_SECTIONS
      (frontend/src/config/helpSections.ts) already contains the new section ids
      (vychozi-hodnoty, cislovani, cislo-z-faktury, formaty, deklarace-smeru), so
      structural coverage of the new sections exists without an edit to this file.
      Content-level assertions (the actual wording about druh 53, čtecí maska,
      ZIP) are correctly added in the new p018-regression.spec.ts instead.
      Functionally the AC ("kontrola nových sekcí") appears satisfied, but the
      step_outputs instruction to modify help-structure.spec.ts was not literally
      followed — worth a one-line note in the step record so it isn't read as an
      omission later.
    recommendation: >
      No code change required. If the step record/PR description claims
      help-structure.spec.ts was modified, correct that claim to say coverage
      was achieved via the pre-existing registry-driven contract test plus the
      new p018-regression.spec.ts file.
  - severity: info
    file: (n/a — DoD gate commands)
    line: 0
    description: >
      DoD requires running `run_py_test_gate.sh -q`, `ruff check .`, `acta-ui npm
      run build`, and `npx tsc --noEmit` against a live stack. This review is
      diff-only/read-only (git show at commit 4e00c720, no execution, no stack
      available) per the verifier's mandate, so these gate runs could not be
      independently confirmed. Static checks that could be done from the repo
      were performed instead: the new backend test file compiles
      (py_compile OK), imports (COUNTERPARTY_ICO, E2EClientCtx, db_row,
      invoice_pdf, meta_of, stack, test_client, wait_for_review) all exist in
      test_issued_pipeline_p018.py, the `stack` marker is registered in
      backend's pytest config and excluded from the default gate run
      (`addopts = "-m 'not stack'"`), matching the AC that DB tests aren't
      silently skipped in the gate while stack tests stay out of it.
    recommendation: >
      Confirm via the run log/evidence for this step (outside this diff) that
      the four gate commands were actually executed and passed; this review
      cannot substitute for that execution evidence.

Verified against forbidden paths — none touched:
  - backend/acta/documents/isdoc.py: no diff.
  - No changes to received-invoice numbering/masks, ZIP-of-ZIP handling,
    other archive formats, issued-invoice auto-approval, email dedup, LiteLLM
    pricing/models, or derivation of ACTA number from invoice number on the
    received side. Scenario 4 in the new backend test explicitly asserts the
    received side keeps sequence-based numbering (acta_sequence_number ==
    "FAP-2026/0001", source == "sequence"), consistent with this constraint
    rather than violating it.

Summary:
  - Both files in step_outputs that were expected to be newly created
    (backend/tests/e2e/test_p018_full.py, frontend/e2e/p018-regression.spec.ts)
    are present, syntactically valid, tagged/scoped correctly (pytest.mark.stack;
    Playwright content assertions with specific, non-generic strings per the
    file's own mutation-testing rationale), and cover scenario 4 (regression,
    received invoices untouched) and scenario 5 (negative, viewer role rejected
    at API level with 403, not just hidden in UI) as required.
  - No forbidden paths were modified.
  - One deviation from step_outputs (help-structure.spec.ts not edited) is
    functionally covered by pre-existing generic registry-driven coverage;
    downgraded to a low-severity note rather than a fail.
