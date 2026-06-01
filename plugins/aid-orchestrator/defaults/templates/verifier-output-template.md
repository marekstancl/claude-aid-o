<!-- TEMPLATE — Strip HTML comments when filling. FSM preconditions enforced by aid-fsm.sh fsm_check_* functions. -->

<!--
  VERIFIER OUTPUT TEMPLATE
  ========================
  OVERWRITTEN by the verifier subagent after pre-filter dispatch. The pre-filter
  (aid-prefilter.sh) creates the initial skeleton with `verdict: pending` for
  RUN / FAIL / FULL_REVIEW classifications; the verifier MUST replace it with
  `verdict: pass | fail` plus findings, or the FSM rejects the run.

  SAVE LOCATIONS (variant-specific, FSM checks the filename pattern):

    Variant            Path                                                                 FSM check
    -----------------  -------------------------------------------------------------------  --------------------------------------
    CP2 per-step       .aid-o/work/evidence/{epic_id}/{run_id}/verifier-output-step-{N}.md  cmd_increment_step → fsm_check_verifier_output
    CP3 code-review    .aid-o/work/evidence/{epic_id}/{run_id}/verifier-output-cp3-code-review.md
                                                                                            check_preconditions EXECUTE:GATES → fsm_check_verifier_output
    CP3 security       .aid-o/work/evidence/{epic_id}/{run_id}/verifier-output-cp3-security.md
                                                                                            check_preconditions EXECUTE:GATES → fsm_check_verifier_output
    CP4 curator-validation .aid-o/work/evidence/{epic_id}/{run_id}/verifier-output-cp4-curator-validation.md
                                                                                            cmd_done_advance review→release → fsm_check_cp4_curator_validation (FSM-ENFORCED, full mode)

  GRANDFATHERING: pre-deploy EPICs (state.yaml.created_at < AID_DEPLOY_DATE)
  skip ALL verifier-output FSM checks via fsm_check_grandfather. Post-deploy
  EPICs are strict.

  STRIP ALL HTML COMMENT BLOCKS (including this header and every
  "ABSOLUTELY REQUIRED" marker) BEFORE COMMITTING THE FILE.

  CRITICAL FORMAT RULE: The `_generated_by:`, `classification:`, `verdict:`,
  and (SKIP-only) `reason:` lines MUST be at LINE START (no leading whitespace,
  no markdown blockquote, no comment marker before them). The FSM uses
  `grep -q '^_generated_by:'` etc. — anchored to start-of-line.

  -----------------------------------------------------------------------------
  VARIANT SELECTOR (which template body to use)
  -----------------------------------------------------------------------------
  Pick the variant block below that matches your dispatch filename:
    A. CP2 per-step          → verifier-output-step-{N}.md       (classification: SKIP | RUN | FAIL)
    B. CP3 code-review       → verifier-output-cp3-code-review.md (classification: FULL_REVIEW)
    C. CP3 security          → verifier-output-cp3-security.md    (classification: FULL_REVIEW)
    D. CP4 curator-validation → verifier-output-cp4-curator-validation.md (classification: FULL_REVIEW; FSM DOES enforce — fsm_check_cp4_curator_validation in cmd_done_advance, full mode)

  All four share the SAME header block (below). Only the `# {Variant Heading}`,
  the dispatch_label format inside `_generated_by:`, and the focus of "Findings"
  differ per variant. The variant-specific guidance is annotated inline.
  -----------------------------------------------------------------------------
-->

_generated_by: aid-orchestrator:verifier@{dispatch_label}
<!-- ABSOLUTELY REQUIRED — FSM precondition fails (fsm_check_verifier_output
     line ~146) if no line starts with `_generated_by:`. The pre-filter writes
     a placeholder `aid-pre-filter.sh@v<X.Y.Z>`; the verifier MUST overwrite
     it to prove a verifier subagent actually ran (anti-fabrication).

     dispatch_label convention (DIFFERS PER VARIANT — empirical from real
     evidence files in .aid-o/work/evidence/E-035-2_2/):
       A. CP2 per-step:    CP2-step{N}-epic{M}        e.g. CP2-step3-epic2
       B. CP3 code-review: CP3-code-review-epic{M}    e.g. CP3-code-review-epic2
       C. CP3 security:    CP3-security-epic{M}       e.g. CP3-security-epic2
       D. CP4 curator:     CP4-curator-epic{M}        e.g. CP4-curator-epic2

     Pre-filter placeholder values (e.g. `aid-pre-filter.sh@v2.18.0`) indicate
     the verifier was never dispatched and will be REJECTED by the FSM. -->

_generated_at: {ISO 8601 UTC, e.g. 2026-05-31T14:23:45Z}
<!-- Pre-filter convention; not directly grep-checked by FSM but used by the
     compliance evaluator (verifier_provenance check). Format: output of
     `date -u +%Y-%m-%dT%H:%M:%SZ`. Timezone MUST be `Z` (UTC).
     Local-timezone offsets break lex compare in fsm_check_grandfather. -->

classification: {SKIP|RUN|FAIL|FULL_REVIEW}
<!-- ABSOLUTELY REQUIRED — FSM precondition fails (fsm_check_verifier_output
     line ~147) if no line starts with `classification:`. Case-sensitive.

     Allowed values, mapped to variant:
       SKIP         — variant A only. Pre-filter found no diff or only trivial
                      changes; no verifier ran. `reason:` REQUIRED below.
       RUN          — variant A only. Pre-filter clean, verifier dispatched
                      with focus=code-review.
       FAIL         — variant A only. Pre-filter matched security keyword,
                      verifier dispatched with focus=security.
       FULL_REVIEW  — variants B, C, D. Full EPIC diff (no pre-filter); both
                      code-review and security paths run independently.

     Unknown values fail the FSM check; do not invent new classifications. -->

verdict: {pass|fail|skip|pending}
<!-- ABSOLUTELY REQUIRED FOR RUN/FAIL/FULL_REVIEW — FSM precondition fails
     (fsm_check_verifier_output lines ~155-160) if the line is missing OR if
     `verdict: pending` is left unchanged after dispatch.

     Per-variant rules:
       Variant A (SKIP):                pre-filter writes `verdict: skip` —
                                        leave it; no verifier dispatch needed.
       Variant A (RUN/FAIL):            pre-filter writes `verdict: pending`;
                                        verifier MUST overwrite with `pass` or `fail`.
       Variants B, C (FULL_REVIEW):     verifier writes `verdict: pass | fail` directly.
       Variant D (FULL_REVIEW, CP4):    verifier writes `verdict: pass | fail`;
                                        not FSM-enforced but auditor flags missing field.

     Allowed values: pass | fail | skip. Convention: lowercase. -->

reason: {free-text justification — REQUIRED ONLY for classification=SKIP}
<!-- ABSOLUTELY REQUIRED ONLY WHEN classification=SKIP — FSM precondition fails
     (fsm_check_verifier_output line ~153) if SKIP classification is set
     without a line-start `reason:` field.

     Example for SKIP: `reason: diff under trivial_threshold (2 files, 8 lines)`
     For RUN / FAIL / FULL_REVIEW this field is optional; omit it entirely. -->

matched_rules: ["{rule_id_1}", "{rule_id_2}"]
<!-- Optional. Pre-filter writes this with the rule IDs that triggered
     RUN/FAIL classification (e.g. `["security_keyword:secret_pattern"]`).
     The verifier should leave it untouched. Not FSM-checked. -->

# {Variant Heading}
<!-- Pick the heading that matches your variant — this is the ONLY place where
     the four variants visibly diverge in body shape. Pre-deploy EPICs that
     skip FSM enforcement still benefit from these headings for audit clarity.

     A. CP2 per-step:    # CP2 Step {N} Review — focus: {code-review|security}
     B. CP3 code-review: # CP3 Code Review — EPIC {epic_id} full-diff
     C. CP3 security:    # CP3 Security Review — EPIC {epic_id} full-diff
     D. CP4 curator:     # CP4 Curator Review — EPIC {epic_id} memory + reflection
-->

**Branch:** {git branch or task/EPIC label, e.g. task/E-036-1_1}
**Commit(s):** {short SHA or SHA range, e.g. 3f2a91c..b7e0d12}
**Scope:** {what was reviewed — DIFFERS PER VARIANT}
<!-- Scope conventions per variant:
       A. CP2 per-step:    files modified in step {N} (from step-{N}-verify.md "Files Modified")
       B. CP3 code-review: `git diff {base}..HEAD` across the full EPIC
       C. CP3 security:    `git diff {base}..HEAD` across the full EPIC, focus on
                           secrets / authz / injection / dep-vuln surface
       D. CP4 curator:     plan.json + run.md + all step-{N}-verify.md outputs;
                           focus on memory deduplication + reflection notes
-->
**Forbidden paths touched:** {none — verified | LIST violations | N/A for CP4}

## Findings
<!-- For verdict=pass: write `None.` or a one-line summary of clean review.
     For verdict=fail: numbered list. Each finding MUST have:
       severity:       critical | high | medium | low | info
       area:           file:line, file path, or "EPIC-wide"
       finding:        1-2 sentence description
       recommendation: actionable fix (or `auto_fixable: true` if gate-fixer
                       can handle it without escalation)

     Variant-specific focus:
       A. CP2 per-step    — scope: step-N diff. Bias toward simplicity / DoD match.
       B. CP3 code-review — scope: full EPIC diff. Bias toward maintainability,
                            naming, dead code, test coverage gaps, plan compliance.
       C. CP3 security    — scope: full EPIC diff. Bias toward secrets, authz
                            bypass, injection, unsafe deps, regression on existing
                            security tests.
       D. CP4 curator     — scope: memory + reflection. Bias toward duplicate
                            vulcan-memory entries, missing N/A justifications,
                            reflection notes that should be promoted to skills/.

     The CP2/CP3 fix loop runs max 2 iterations. Critical/high non-auto-fixable
     findings escalate to E7 (PM review). -->
None.

## Verdict (1-2 sentences)
<!-- Required by agents/verifier.md §Output Format. Plain prose; restates the
     `verdict:` header field with an evidence anchor. -->
PASS — diff implements all plan.json step DoD items, no forbidden paths touched, all 3 unit tests added and green.
