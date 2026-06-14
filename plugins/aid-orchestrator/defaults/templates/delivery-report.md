<!--
  Delivery Report Template — filled by the Reporter agent at the plan boundary.
  FIXED FORM: keep every section, in this order, with this formatting.
  FREE CONTENT: the Reporter decides depth and length per section — no length cap.
  LANGUAGE: render section headings + prose in the project document_language
  (config/language.yaml); preserve structure and order exactly. English shown here
  is the canonical reference.
  The frontmatter is machine-read by fsm_check_delivery_report_present — do not rename keys.
-->
---
_generated_by: aid-orchestrator:reporter@{agent_id}
_generated_at: "{ISO 8601}"
plan_id: "{plan_id}"
epics: ["{epic_id}", ...]
test_outcome: pass | partial | no-runtime
_test_evidence:
  # ≥1 path REQUIRED, relative to this run's evidence dir. Each MUST exist on disk —
  # the FSM precondition rejects the release if a referenced artifact is missing.
  - "reporter/{artifact-file}"
---

# Delivery Report — {plan title}

_Plan {plan_id} · EPIC(s) {epic_ids} · {date}_

## 1. What was delivered

<!-- Plain language, feature by feature. No jargon — translate technical terms.
     This is what the PM reads first to understand what changed. -->

## 2. How to try it

<!-- Concrete, copy-pasteable: the exact commands, URLs, or click-paths the PM
     can use to see each delivered piece working. One block per feature. -->

## 3. What I verified

<!-- What the Reporter actually ran/clicked and the observed result. Reference each
     artifact in _test_evidence by name (screenshot, exit-code transcript). State the
     test mode used: UI (Playwright), smoke (CLI/API), or no-runtime (test-suite). -->

## 4. Auditor verdict

<!-- One line: score + headline finding. Pulled verbatim-condensed from audit-report.md. -->

## 5. Curator verdict

<!-- One line: what was applied vs deferred. Pulled from curator-report.md. -->

## 6. Cleanup (Simplifier)

<!-- Done / Skipped / Recommendation — from simplifier-report.md.
     - **Done:** per item, what was simplified and why
     - **Skipped:** per item, why it was left alone
     - **Recommendation:** how to proceed with any deferred (L-effort) items -->

## 7. Heads-up

<!-- Caveats, deferred L-items, known risks, anything that did NOT get done.
     If everything is clean, say so in one line. -->
