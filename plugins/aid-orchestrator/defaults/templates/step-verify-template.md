<!-- TEMPLATE — Strip HTML comments when filling. FSM preconditions enforced by aid-fsm.sh fsm_check_* functions. -->

<!--
  STEP VERIFICATION TEMPLATE
  ==========================
  Written by the implementer agent (or controller after agent dispatch) AFTER a
  step completes and BEFORE running `aid-fsm.sh increment-step`.

  Save location: .aid-o/work/evidence/{epic_id}/{run_id}/step-{N}-verify.md
  Enforced by:   plugins/aid-orchestrator/scripts/aid-fsm.sh cmd_increment_step
                 (six preconditions, stable failure-reason identifiers below)

  STRIP ALL HTML COMMENT BLOCKS (including this header and every
  "ABSOLUTELY REQUIRED" marker) BEFORE COMMITTING THE FILE. The FSM does not
  care about comments, but cargo-cult markers in evidence dilute the audit
  trail and the auditor agent flags them.

  Six FSM preconditions are checked. Each mandatory section below is annotated
  with the exact regex the FSM applies and the failure_reason string it emits.
  Grandfathering: pre-deploy EPICs (fsm-state.yaml.created_at < AID_DEPLOY_DATE)
  skip the verifier-output co-file check; ALL six step-verify checks below
  always run regardless of deploy date.
-->

# Step {N} Verification — {step_title}

## Step
<!-- One-line restatement of plan.json step.objective. Not FSM-checked; the
     verifier subagent uses this as the "what was supposed to happen" anchor.
     Concrete example:
       Add JWT expiry validation to the auth middleware (plan.json step 3.dod[0]). -->
Add JWT expiry validation to the auth middleware (plan.json step 3.objective).

## Files Modified
<!-- Newline-separated list of files actually changed in this step's commit(s).
     Not FSM-checked, but the CP2 pre-filter and code-review verifier match
     this against plan.json step.outputs / step.forbidden_paths.
     Format: `- <repo-relative path>` plus optional indented sub-bullets. -->
- src/middleware/auth.ts
  - Added `validateExpiry(token)` helper, called from `requireAuth` chain
- tests/middleware/auth.test.ts
  - Added 3 cases: expired token rejects, fresh token passes, malformed exp claim rejects

## Acceptance Criteria
<!-- ABSOLUTELY REQUIRED — FSM precondition fails with `verify_no_ac_checklist`
     if no line matches BRE pattern `- \[x\]` (lowercase x, bracketed).
     Enforced via `grep -c '- \[x\]' >= 1` in cmd_increment_step.

     One line per AC in plan.json step.dod. Mark `- [x]` when PASS, `- [ ]`
     when not yet met, or remove the line entirely if the AC was withdrawn
     (note in "Plan Discrepancy Noted" below). At least ONE `- [x]` must
     remain or the FSM rejects the increment. -->
- [x] Expired tokens (exp < now) return HTTP 401 — PASS (evidence: `npm test -- auth.test.ts`, 3/3 green)
- [x] Fresh tokens (exp > now) pass through to next handler — PASS (evidence: integration test `/api/me` round-trip)
- [x] Malformed `exp` claim (non-numeric) returns HTTP 400 — PASS (evidence: unit test `rejects malformed exp`)

## Plan Discrepancy Noted
<!-- Optional. Use when implementation deviated from plan AC text (e.g. plan
     said "out of 20" but actual baseline was 23). Plain prose, no checklist.
     Write `None` when the implementation matches plan verbatim. -->
None — implementation matches plan AC verbatim.

## Visual Check
<!-- OPTIONAL. Include ONLY if the step has `visual_refs` in plan.json.
     Skip the section entirely (do not leave empty headers) for backend, script,
     or docs steps. For frontend steps with visual_refs, follow the 5-aspect
     table from pipeline.md §4 Visual Verification Protocol:
       - mockup_path:  from plan.json step.visual_refs[].path
       - screenshot:   evidence/{epic_id}/{run_id}/screenshots/step_{N}_actual.png
       - aspects:      layout, colors, typography, spacing, content (MATCH / PARTIAL / MISS)
     The current step is backend-only; section omitted. -->

## Verification
<!-- Optional but strongly recommended for non-trivial steps. Bash commands
     that PM or the verifier can re-run to confirm the AC. Each command should
     be deterministic, safe to re-run, and explicit about expected output. -->
```bash
npm test -- tests/middleware/auth.test.ts
# expected: 3 passing, 0 failing
```

## Commit
<!-- ABSOLUTELY REQUIRED — FSM precondition fails with `verify_no_commit_ref`
     if no token in the file matches ERE pattern `[a-f0-9]{7,}` (7+ hex chars).
     Enforced via `grep -cE '[a-f0-9]{7,}' >= 1` in cmd_increment_step.

     One short SHA + commit subject per commit produced by this step. If the
     step produced multiple commits (rare — usually a scope-leak signal), list
     each. Use ≥7-char SHA; full 40-char also fine.

     WARNING: The regex matches ANY 7+ hex sequence, so a literal placeholder
     like `abcdef0` will satisfy the FSM but indicate an unfilled template.
     The auditor agent flags literal `abcdef0` / `{abcdef0}` strings. -->
3f2a91c — feat(auth): add JWT expiry validation to requireAuth middleware

## Memory Used
<!-- ABSOLUTELY REQUIRED — FSM precondition fails with `verify_no_memory_used`
     if no line matches ERE pattern `^## Memory Used` (line-start anchored).
     Enforced via `grep -qE '^## Memory Used'` in cmd_increment_step.

     List vulcan-memory entries that informed the implementation. Acceptable
     `N/A` template: `N/A — <concrete reason no memory query was applicable>`.
     DO NOT write bare `N/A` without a reason; auditors flag it as cargo-cult. -->
- entry_id: brain/auth-middleware-pattern-2026-04 — JWT validation conventions in this repo (used for: aligned with existing `requireAuth` chain order, no novel pattern introduced)

## Memory Written
<!-- ABSOLUTELY REQUIRED — FSM precondition fails with
     `verify_no_memory_written` if no line matches ERE pattern
     `^## Memory Written` (line-start anchored).
     Enforced via `grep -qE '^## Memory Written'` in cmd_increment_step.

     List new vulcan-memory entries proposed for storage. Type ∈
     {brain, ideas, reflection, skills, projects}; see ~/.claude/CLAUDE.md.
     Curator phase dedupes via vulcan-find before vulcan-store.
     Acceptable `N/A` template: `N/A — <concrete reason no new pattern emerged>`. -->
N/A — mechanical addition following the existing requireAuth chain pattern; no new architectural decision warranted a memory entry.

## Result: PASS
<!-- ABSOLUTELY REQUIRED — FSM precondition fails with `step_verify_not_pass`
     if the string `## Result: PASS` is absent.
     Enforced by a case-insensitive substring match in cmd_increment_step
     (P079 Step 4). Note the two casing conventions this file spans: this
     HEADING is canonical uppercase, while `verdict:` lines in verifier
     output are canonical lowercase (`verdict: pass|fail`). Both parsers now
     accept either casing, so following one convention into the other field
     no longer costs a rejected review — write the canonical form anyway.

     Replace with `## Result: FAIL` ONLY to deliberately keep the file for
     forensic purposes (in which case do NOT run increment-step — fix the AC
     and rewrite this file to PASS).

     PASS preconditions (judgment, not regex):
       - all AC above marked [x]
       - all visual aspects (if applicable) MATCH or PARTIAL with PM-approved deviation
       - commit reference present and points to the step's actual work
       - Memory Used / Memory Written each have either an entry or N/A-with-reason -->
