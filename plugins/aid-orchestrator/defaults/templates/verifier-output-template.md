<!-- TEMPLATE — Strip HTML comments when filling. FSM preconditions enforced by aid-fsm.sh fsm_check_* functions. -->

<!--
  VERIFIER OUTPUT TEMPLATE
  ========================
  Written by the verifier subagent at CP4 (the curator-validation review),
  the ONE checkpoint that still uses this file since P094: the step (CP2),
  EPIC (CP3) and fast-mode (CP6) reviews are reviewer rounds whose answers
  follow defaults/schemas/review-finding.schema.json.

  SAVE LOCATION (FSM checks the filename):

    CP4 curator-validation .aid-o/work/evidence/{epic_id}/{run_id}/verifier-output-cp4-curator-validation.md
                                                                                            cmd_done_advance review→release → fsm_check_cp4_curator_validation (FSM-ENFORCED, full mode)

  GRANDFATHERING: pre-deploy EPICs (fsm-state.yaml.created_at < AID_DEPLOY_DATE)
  skip ALL verifier-output FSM checks via fsm_check_grandfather. Post-deploy
  EPICs are strict.

  STRIP ALL HTML COMMENT BLOCKS (including this header and every
  "ABSOLUTELY REQUIRED" marker) BEFORE COMMITTING THE FILE.

  CRITICAL FORMAT RULE: The `_generated_by:`, `classification:`, `verdict:`,
  and (SKIP-only) `reason:` lines MUST be at LINE START (no leading whitespace,
  no markdown blockquote, no comment marker before them). The FSM uses
  `grep -q '^_generated_by:'` etc. — anchored to start-of-line.

  -----------------------------------------------------------------------------
  VARIANT
  -----------------------------------------------------------------------------
    D. CP4 curator-validation → verifier-output-cp4-curator-validation.md (classification: FULL_REVIEW; FSM DOES enforce — fsm_check_cp4_curator_validation in cmd_done_advance, full mode)

  Older variants A–C (CP2 per-step, CP3 code-review, CP3 security) were retired
  by P094; the guidance below that still names them describes what
  fsm_check_verifier_output accepts, not a place to write them.
  -----------------------------------------------------------------------------
-->

_generated_by: aid-orchestrator:verifier@{dispatch_label}
<!-- ABSOLUTELY REQUIRED — FSM precondition fails (fsm_check_verifier_output
     line ~146) if no line starts with `_generated_by:`. Nothing writes a
     placeholder any more (the pre-filter is gone since P094); the verifier
     writes this line itself to prove a verifier subagent actually ran.

     dispatch_label convention (DIFFERS PER VARIANT — empirical from real
     evidence files in .aid-o/work/evidence/E-035-2_2/):
       D. CP4 curator:     CP4-curator-epic{M}        e.g. CP4-curator-epic2

     A placeholder value the verifier did not write is REJECTED by the FSM. -->

_generated_at: {ISO 8601 UTC, e.g. 2026-05-31T14:23:45Z}
<!-- ABSOLUTELY REQUIRED — FSM precondition fails (fsm_check_verifier_output,
     E-046-1_3 Step 2) if missing or empty. The verifier MUST write a real
     timestamp; a blank or placeholder value is REJECTED.
     Format: `date -u +%Y-%m-%dT%H:%M:%SZ`. Timezone MUST be `Z` (UTC).
     Local-timezone offsets break lex compare in fsm_check_grandfather. -->

classification: {SKIP|RUN|FAIL|FULL_REVIEW}
<!-- ABSOLUTELY REQUIRED — FSM precondition fails (fsm_check_verifier_output
     line ~147) if no line starts with `classification:`. Case-sensitive.

     Allowed values (the FSM still accepts all four; CP4 writes FULL_REVIEW):
       SKIP         — nothing was reviewed. `reason:` REQUIRED below.
       RUN / FAIL   — legacy per-step values; no live checkpoint writes them.
       FULL_REVIEW  — the CP4 review of the applied curator + auditor changes.

     Unknown values fail the FSM check; do not invent new classifications. -->

verdict: {pass|fail|skip|pending}
<!-- ABSOLUTELY REQUIRED FOR RUN/FAIL/FULL_REVIEW — FSM precondition fails
     (fsm_check_verifier_output lines ~155-160) if the line is missing OR if
     `verdict: pending` is left unchanged after dispatch.

     Variant D (FULL_REVIEW, CP4):    verifier writes `verdict: pass | fail`;
                                      FSM-enforced via fsm_check_cp4_curator_validation
                                      → fsm_check_verifier_output (wired E-046-1_3 Step 2).

     Allowed values: pass | fail | skip. Convention: lowercase. -->

reason: {free-text justification — REQUIRED ONLY for classification=SKIP}
<!-- ABSOLUTELY REQUIRED ONLY WHEN classification=SKIP — FSM precondition fails
     (fsm_check_verifier_output line ~153) if SKIP classification is set
     without a line-start `reason:` field.

     Example for SKIP: `reason: diff under trivial_threshold (2 files, 8 lines)`
     For RUN / FAIL / FULL_REVIEW this field is optional; omit it entirely. -->

# Additive Fields (v2.35+) — present only when applicable
<!-- ADDITIVE ONLY: these fields extend (never replace) the above top-level fields.
     The existing `_generated_by`/`_generated_at`/`classification`/`verdict` greps
     at line-start still work because these fields are at top-level, not nested.

     HIGH-RISK GATE (aid-fsm.sh fsm_check_verifier_output):
       When `behavior_trace_required: true`, the FSM checks `behavior_trace_count > 0`.
       This is structural/non-emptiness only — trace quality is NOT evaluated by the gate.

     Emit these fields when dispatched with checkpoint context (CP2, CP3, CP4, CP6).
     For trivial/SKIP diffs, emit `behavior_trace_required: false` + reason instead. -->

checkpoint: {cp2|cp3|cp4|cp6}
<!-- Which checkpoint this output belongs to. Drives diff scope (see review-checkpoint-contracts.md):
       cp2 — HEAD~1..HEAD (step diff)
       cp3 — base_commit..HEAD (full EPIC diff)
       cp4 — applied curator/auditor diff
       cp6 — advisory; no FSM enforcement -->

focus: {code-review|security|behavior-trace}
<!-- Review lens applied. One of the focus types from agents/verifier.md.
     For CP3: two separate outputs (code-review + security), each with its own focus. -->

behavior_trace_count: 0
<!-- Number of request paths traced. MUST be > 0 when `behavior_trace_required: true`.
     Set to 0 only for trivial/SKIP diffs (no handler changes) with
     `behavior_trace_required: false` + `behavior_trace_skip_reason`. -->

behavior_trace_required: {true|false}
<!-- true  — diff matched a high-risk pattern; FSM enforces count > 0
     false — diff is trivial/SKIP; `behavior_trace_skip_reason` MUST be set
     Omit this field for RUN/SKIP where no high-risk pattern was detected (defaults to false). -->

behavior_trace_skip_reason: "{why no trace needed — REQUIRED when behavior_trace_required: false}"
<!-- Example: "no handler patterns in diff"
     Example: "classification SKIP — docs/config only, no executable code changed"
     REQUIRED only when `behavior_trace_required: false`. -->

behavior_trace:
<!-- Optional array of traced request paths. Present when checkpoint is cp2 or cp3
     AND the diff adds/modifies a handler. Each entry traces one request path end-to-end. -->
  - request: "{HTTP method + path, e.g. POST /api/login}"
    path: "{handler → service → db/sink, e.g. handler → auth_service.verify() → db.query()}"
    sink: "{final outcome type, e.g. JWT token returned | auth error raised}"
    branches:
      - name: "{branch label, e.g. success}"
        outcome: "{HTTP status + body summary, e.g. 200 + JWT}"
      - name: "{branch label, e.g. invalid_password}"
        outcome: "{HTTP status + body summary, e.g. 401 AuthError}"
      - name: "{branch label, e.g. user_not_found}"
        outcome: "{HTTP status + body summary, e.g. 401 AuthError}"

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
