# CP1-deep L1 (behavior) — P080 (iteration 2)

_generated_by: aid-orchestrator:verifier@cp1-lens-L1
_generated_at: 2026-08-11T09:12:00Z
Reviewed-Head: cd1ab4af145b5272b200741ed41818ae058b2a18

iteration: 2
plan_reviewed: .aid-o/plans/P080-entrypoint-ux-help-handoffs.md (718 lines)
plan_tracking_note: |
  `git check-ignore -v .aid-o/plans/P080-entrypoint-ux-help-handoffs.md` -> `.gitignore:98 **/.aid-o/`;
  `git ls-files` on it returns nothing. The revised plan is UNTRACKED, so Reviewed-Head does not bind
  its content and no iteration-1 vs iteration-2 diff exists. All resolution checks below are therefore
  content-level against the live file plus repo commands, not diff-level.

stop_rule_blockers:
  - id: L1-B8
    step: 14 / plan-level AC7
    derived_from: AB-3 (half-applied)
    claim: "The Czech-mandate relaxation is enforced by a grep pattern that matches only 2 of the 4 hardcoded lines, and the plan-level AC7 was never widened at all — so both ACs go green while the mandate survives in `aid-verify-plan.md` AND at the second line of BOTH files."
    evidence: |
      (a) Plan-level AC7 unchanged. Plan lines 697-703 still read:
          cmd: "bash -c '! grep -n \"in \\*\\*Czech\\*\\*\" plugins/aid-orchestrator/commands/aid-verify-implementation.md'"
          AB-3's required_revision was explicit: 'Plan-level AC7 cmd becomes: bash -c '"'"'! grep -rn "in \*\*Czech\*\*"
          plugins/aid-orchestrator/commands/'"'"''. Step 14's own AC (plan line 537) WAS widened; the plan-level AC was not.
      (b) The pattern itself under-matches — the asterisks precede "in" on the second occurrence in each file:
          $ grep -rn 'in \*\*Czech\*\*' plugins/aid-orchestrator/commands/ | wc -l   -> 2
            aid-verify-plan.md:33            "delivered in **Czech** (see protocol)"
            aid-verify-implementation.md:59  "delivered in **Czech** (see protocol)"
          $ grep -rn -i 'czech' plugins/aid-orchestrator/commands/aid-verify-*.md   -> 4
            + aid-verify-plan.md:122            "5–10 sentences **in Czech**."
            + aid-verify-implementation.md:149  "5–10 sentences **in Czech**."
          The literal is `**in Czech**`, not `in **Czech**`. Both my iteration-1 evidence and the adjudicator's
          `verified_by` (which used a case-insensitive `czech` grep but transcribed the AB-3 command as the
          asterisk-form) propagated this error into the revision.
    impact: "Even the widened Step 14 AC passes with the two `5–10 sentences **in Czech**` lines still in place — the exact lines that bind the ACTUAL summary the PM reads. A non-Czech PM running /aid-verify-plan or /aid-verify-implementation still receives a Czech summary, and the plan's Success Criterion 4 plus AC7 both certify the opposite. The plan-level AC additionally never inspects aid-verify-plan.md at all."
    fix: "Replace the pattern in BOTH ACs (plan line 701 and Step 14 line 537) with a form that matches all four lines, e.g. `bash -c '! grep -rniE \"\\*\\*(in )?czech\\*\\*|in \\*\\*czech\\*\\*\" plugins/aid-orchestrator/commands/'`, and restate the plan-level AC7 at directory scope. Verify the chosen pattern returns 4 at HEAD before adopting it."

  - id: L1-B9
    step: 11
    derived_from: AB-6 (revision introduced a rule the corrected input cannot satisfy)
    claim: "The AB-6 revision correctly repointed the input to `gates_report.json`, but the card-selection rule it added — 'only `fail` on a REQUIRED gate selects the Blocked card' — is not derivable from that file: gate rows carry no `required` field, and the renderer signature declares no second input."
    evidence: |
      Plan line 406 signature: `aid_gate_outcome_render <gates_report_json> <run_dir> [waiver_dir]`.
      Plan line 413: "Card rule: only `fail` on a REQUIRED gate selects the Blocked card".
      $ grep -n 'gates_json+=' plugins/aid-orchestrator/scripts/aid-run-gates.sh
        every row shape is {gate, result, exit_code, duration_ms, output, attempts[, reason]} —
        :1937, :1961, :2014, :2432 all confirm; NO `required` key on any row.
      $ grep -n 'required=' plugins/aid-orchestrator/scripts/aid-run-gates.sh
        :1945 `required=$(yq ".gates.\"${gate_name}\".required // false" "$execution_yaml")` — required-ness is
        read from execution.yaml at run time and consumed only to set the envelope's `overall`:
        :2001 / :2261 / :2338 `if required then overall="fail"`.
      $ grep -n 'report=' aid-run-gates.sh (envelope, ~:2443)
        report="{\"epic_id\":…,\"overall\":\"${overall}\",\"completed_at\":…,\"gates\":${gates_json}}"
        -> `.overall` is the ONLY place required-gate semantics survive into the artifact, and it already
        encodes the waiver rule (:2145 "a required gate reported `waived` never flips overall to fail").
    impact: "Implemented literally, the renderer must either (a) read `execution.yaml` — an input the step does not declare, breaking its own pure-function contract, or (b) treat every `fail` row as blocking. Under (b) a run with a `required: false` gate failing renders the **Blocked** card at the GATES boundary while the FSM's own `overall` is `pass` and the pipeline advances to DONE — the PM is told the run is blocked by a gate that was never blocking. This is the same class the step exists to kill (a recommendation rendered as fact)."
    fix: "Name `.overall` as the card selector in Step 11: Blocked when `.overall == \"fail\"`, Finished otherwise; per-row `result` drives only the core table (`pass|fail|skip|profile_excluded`), and the waived list comes from the report's own `waived_gates[]` (see L1-F13). Add a fixture: a report with `overall: pass` and one non-required `fail` row selects the Finished card with the failure listed in the core table."

resolution_verification:
  - id: L1-B1
    adjudicated_as: AB-1
    status: RESOLVED
    check: |
      Plan Step 12 (lines 440-447) now declares `aid_plan_close_render <pm_decision_brief_json>
      <release_decision_json> <plan_id> <out_dir>`, splits the fact list brief-vs-plan_summary,
      rewrites the "reads ONLY the brief" sentence (line 445), replaces the invented options block with
      "DERIVED from merge_mode + release_ready" (line 447), and restates the fail-closed fixture (line 443).
      Verified the named fields really exist:
      $ grep -n 'plan_summary' plugins/aid-orchestrator/scripts/aid-pm-brief.sh -> :232
      $ sed -n '1106,1136p' plugins/aid-orchestrator/scripts/aid-release-policy.sh
        plan_summary = {plan_id, plan_final_run_id, reviewed_candidate_sha, approved_target_sha, target_ref,
        final_merge_sha, release_tag_status, epics[], plan_final_gates{report,result,quarantine_substitutes},
        specialist_review, remaining_backlog} — every SHA/tag/EPIC fact the step names is present.
      Residual: "gate totals" is not among them (see L1-F12). Not enough to reopen the blocker.

  - id: L1-B2
    adjudicated_as: AB-2
    status: RESOLVED
    check: |
      $ grep -rn 'Step rendering rule' plugins/aid-orchestrator/ | grep -v CHANGELOG
        -> 6 copies in 5 files: pipeline.md:1322, pipeline.md:2756, aid-run.md:402, aid-stop.md:119,
           aid-status.md:984, memory.md:28  (+ the test's own grep at test-fsm-step-render.bats:108)
      Plan Step 13 Files (lines 472-478) now names all six sites including aid-stop.md and memory.md,
      drops the numeric aid-fsm.sh anchors in favour of the literal, and states THREE call sites —
      matching `grep -n '_fsm_human_step' scripts/aid-fsm.sh` -> def :1132, calls :2858 :2870 :5246.
      The bats rewrite is now an explicit Files entry (line 478) naming BOTH the P073 five-surface block
      (:103-116) and the four verbatim assertions — confirmed present at
      `grep -n 'human: step' test-fsm-step-render.bats` -> :33 :41 :49 :76.
      The disambiguator is preserved as a hard requirement (line 480: "never a bare `Plan Step N of T`").
      AC (line 497) is now the repo-wide grep across commands/ + skills/. Arithmetic checks out:
      1 definition (pipeline:1322) + 5 references = the 6 real sites.

  - id: L1-B3
    adjudicated_as: AB-3
    status: PARTIAL
    check: |
      APPLIED: Step 14 Files gains aid-verify-plan.md lines 33/122 (plan line 513); Step 9's fragment list
      names both files (plan line 345); Step 14 AC3 (line 537) is directory-scoped.
      NOT APPLIED: plan-level AC7 (lines 697-703) is byte-unchanged, still single-file.
      NEWLY BROKEN: the grep literal in both ACs matches 2 of the 4 lines
      ($ grep -rn 'in \*\*Czech\*\*' commands/ | wc -l -> 2; $ grep -rni czech on the two files -> 4).
      Escalated as blocker L1-B8.

  - id: L1-B4
    adjudicated_as: AB-4
    status: RESOLVED
    check: |
      $ yq '.presets | keys' plugins/aid-orchestrator/defaults/policies/permissions.yaml -> ["autonomous"]
      $ grep -rn 'aspirin\|steroids' plugins/aid-orchestrator/{commands,skills,defaults}
        -> commands/aid-setup.md:80 ONLY.
      Plan Step 6 (lines 241-246) now states the measured fact, keeps skills/setup/permissions.md:60 as
      CORRECT, targets aid-setup.md:80 as the single stale surface, and AC (line 265) greps
      aspirin|steroids across commands/ + skills/ instead of banning the accurate "Two presets" line.
      The L1-F2 display rule is folded in at line 244 with its own AC at line 266 — but see L1-F14:
      that AC is not satisfiable against Step 7's spec as written.

  - id: L1-B5
    adjudicated_as: AB-5
    status: RESOLVED
    check: |
      $ grep -n '11 items\|10-file\|11 total\|Total:' commands/aid-init.md -> :3 (10-file), :16 (11 total),
        :35 (Total: 6 files + 5 empty directories = 11 items), :668 (**11 items**) — four statements, as measured.
      $ sed -n '114,124p' commands/aid-init.md -> execution.yaml composed at init (guarded only by
        "not already present"), i.e. eager, absent from the 11-item list.
      $ sed -n '577,583p' commands/aid-init.md -> "## Lazy-Created (NOT at init time)" whose first row is the
        init-eager execution.yaml — the self-contradiction is real and still present.
      Plan Step 5 (line 209) now mandates a recount with execution.yaml in the base manifest, separately
      labelled git-hook and conditional-write categories, all four count statements enumerated, and the
      Lazy-Created heading repair. Step 8 (line 315) consumes "the recomputed Step 5 base manifest"; Step 5
      AC1/AC2 (lines 230-231) match. Internally consistent.

  - id: L1-B6
    adjudicated_as: AB-6
    status: PARTIAL
    check: |
      APPLIED: Step 11 (lines 406, 411, 413) renames the input to `<gates_report_json>`, cites
      `<run_dir>/gates/gates_report.json` produced by aid-run-gates.sh, demotes aid-run-gates-report.sh to
      the escalation-shaped variant, specifies `jq 'to_entries'` over the `.gates` OBJECT and the
      pass|fail|skip|profile_excluded enum, and adds the skip/profile_excluded Finished-card AC (line 428).
      All verified: $ grep -n 'gates_report.json' aid-run-gates.sh -> :1629;
      $ grep -n '^[a-z_]*()' lib/aid-run-gates-report.sh -> merge_escalation_report() only;
      $ grep -n 'gates_json+=' aid-run-gates.sh -> object map, result values as enumerated.
      NOT CLOSED: the required-gate card rule the revision introduced is not derivable from that input —
      rows have no `required` key. Escalated as blocker L1-B9.

  - id: L1-B7
    adjudicated_as: AB-7
    status: RESOLVED
    check: |
      $ grep -n '^| Command\|10-file\|auto-configures' README.md plugins/aid-orchestrator/README.md
        -> README.md:66 (table header), :72 (10-file), :110 (auto-configures); plugin README: no match.
      $ sed -n '64,78p' README.md -> exactly 9 command rows; the 4 named additions bring it to 13.
      Plan Step 5 (line 212) now targets repo-root README.md with all three line anchors, states the
      Step 16 co-touch rule for :110, and AC (line 234) says "Repo-root README.md". Consistent.

  - id: L1-F1
    status: RESOLVED
    check: "$ grep -nE '[0-9]-part|four-part' commands/aid-audit-tests.md -> :50/:285/:331 four-part, :202 '5-part', no '6-part'. Plan line 514 states four-part with the exact line cites; AC (line 538) greps '5-part' == 0; the file is now in Step 14's Files list and Step 9's required-surface list (line 345)."
  - id: L1-F2
    status: PARTIAL
    check: "Display rule added at plan line 244 with AC at line 266, but Step 7's spec (line 283) hardcodes a DIFFERENT string. See L1-F14."
  - id: L1-F3
    status: RESOLVED
    check: "Plan line 478(b) explicitly rewrites the four :33/:41/:49/:76 assertions; line 480 preserves the is-next/complete disambiguator."
  - id: L1-F4
    status: RESOLVED
    check: "Plan line 472 drops every numeric aid-fsm.sh anchor, mandates literal location, and states three call sites — matches grep."
  - id: L1-F5
    status: RESOLVED
    check: "$ grep -n 'lazy-created' commands/aid-help.md -> :263 (execution.yaml, stale) and :264 (queue.yaml, true). Plan AC line 155 is narrowed to `execution.yaml.*lazy-created` with the rationale inline."
  - id: L1-F6
    status: RESOLVED
    check: "Plan AC2 (line 195) is now value-scoped ('no source:/instruction: VALUE ... outside a status: dead row') and explicitly excludes the :226 description."
  - id: L1-F7
    status: RESOLVED
    check: "$ grep -c 'awaiting_host_resume' commands/aid-help.md -> 1. Plan line 137 reframes Step 3 as a MOVE of shipped content; AC line 157 pins the literal at exactly one occurrence."
  - id: L1-F8
    status: UNRESOLVED
    check: |
      Plan line 508 still cites aid-run.md "(lines ~352-360)" for the DONE-review block and "(lines ~294-315)"
      for ESCALATION. $ sed -n '352,360p' commands/aid-run.md -> the EXECUTE "**Transition:**" bullets;
      $ sed -n '294,300p' -> "### State: READY".
      $ grep -n 'DONE REVIEW —\|Auditor Score:\|ESCALATION: {reason}' commands/aid-run.md -> :440, :443, :385.
      The revision fixed the pipeline.md anchors (lines 442, 509) but left aid-run.md's wrong ones; the
      literal-anchor fallback at line 523 only triggers on drift "beyond recognition". Carried as finding L1-F15.
  - id: L1-F9
    status: UNRESOLVED
    check: "Plan line 345 still greps only `Potřebuji tvoje rozhodnutí:`; $ grep -rn 'Potřebuji tvoje rozhodnutí' --include=*.md . -> no match at HEAD. No structural/English probe added. Carried as L1-F16 (low)."
  - id: L1-F10
    status: UNRESOLVED
    check: "$ grep -c 'help-authoring-standard' .aid-o/plans/P080-*.md -> 0. Carried as L1-F17 (low)."
  - id: L1-F11
    status: RESOLVED
    check: "Plan line 209 enumerates all four count statements including the frontmatter `description`; AC line 230 requires the description to agree with the surviving sentence."

findings:
  - id: L1-F12
    severity: medium
    step: 12
    finding: "Step 12 promises 'EPIC and gate totals' from `.release_decision.plan_summary`, but that object carries no gate totals — only a report path, a single `result` string and a quarantine list. A 'gates' tile will render `—` at the PM's plan-close moment."
    evidence: "Plan line 440. $ sed -n '1130,1134p' plugins/aid-orchestrator/scripts/aid-release-policy.sh -> `plan_final_gates: {report: $gpath, result: $gres, quarantine_substitutes: […]}`; $ sed -n '284,288p' scripts/aid-pm-brief.sh renders only Report + Result. EPIC count is derivable from `epics[]`; gate counts are not present anywhere in plan_summary."
    recommendation: "Restate the fact list as 'EPIC count (from `epics[]`) and the plan-final gate RESULT (`plan_final_gates.result`) plus quarantine-substitute count' — or, if a gate tile with counts is wanted, declare `plan_final_gates.report` as an explicitly permitted third read and say so in the cycle-break sentence."

  - id: L1-F13
    severity: medium
    step: 11
    finding: "Waiver facts are specified to come from an optional `[waiver_dir]` argument, but the gate report already carries a canonical `waived_gates[]` array — two sources that can disagree, with the optional one able to be absent entirely."
    evidence: "Plan lines 406, 413. aid-run-gates.sh ~:2513 comment: 'Always an array; empty when no gate was waived. A required gate reported `waived` never flips overall to fail, so this is the one place PM/release evidence can see, at a glance, that a required gate was accepted without…' — i.e. the report is the designated PM-visible waiver surface."
    recommendation: "Make `waived_gates[]` from the report the primary waiver source (it is always present and is the surface `overall` was computed against); keep `[waiver_dir]` only for receipt detail (verdict vocabulary), and state that a waiver appearing in one source but not the other is rendered with an explicit discrepancy line rather than silently preferred."

  - id: L1-F14
    severity: high
    step: 6 / 7
    finding: "The Step 6 first-run display AC cannot be satisfied by Step 7's renderer as specified — three different strings now exist across the two steps for two related display cases, and the AC pins the wrong one to the wrong case."
    evidence: |
      Plan line 244 (seeded pair): "autonomous (preset) — autonomous_mode: false until you enable it".
      Plan line 251 (missing key): "autonomous (implicit — key missing, will be written on first change)".
      Plan line 283 (Step 7 renderer spec): `active_preset // "autonomous (implicit)"` — a THIRD string, and it
      covers only the missing-key case.
      Plan line 266 (Step 6 AC): the seeded-pair wording "appears in aid-init.md AND in Step 7's renderer" —
      but Step 7's renderer spec has no seeded-pair branch at all, only the fallback.
    recommendation: "Split the two cases explicitly in both steps: (1) key present and `autonomous_mode: false` → render the line-244 wording; (2) key absent → render the line-251 wording verbatim (correct line 283's shorter `autonomous (implicit)` to match). Then scope AC line 266 to case (1) in aid-init.md and add a Step 7 bats case per branch."

  - id: L1-F15
    severity: medium
    step: 14
    finding: "aid-run.md's numeric anchors in Step 14 are still wrong post-P076 (carry-forward of L1-F8), while the same revision corrected the pipeline.md ones — the inconsistency makes it look deliberate."
    evidence: "Plan line 508 cites ~352-360 and ~294-315; repo has the DONE-review block at commands/aid-run.md:440-443 (`DONE REVIEW — {epic_id}` / `Auditor Score:`) and ESCALATION at :377-400 (`ESCALATION: {reason}` at :385). Lines 352-360 are EXECUTE transition bullets; 294-300 is `### State: READY`."
    recommendation: "Replace both aid-run.md ranges with the literals the step's own Error Handling already names (`DONE REVIEW —`, `Auditor Score:`, `ESCALATION: {reason}`), matching how lines 442 and 509 now handle pipeline.md."

  - id: L1-F16
    severity: high
    step: 3 / 5 / 6
    finding: "The CP1 grandfathering decision is written as a paragraph inside Step 3 that binds Steps 5 and 6, but neither Step 5 nor Step 6 (nor Step 3 itself) carries the AC it mandates — and EPIC generation slices the plan per step, so Steps 5-6 will never see the paragraph."
    evidence: "Plan lines 159 ('Steps 3 and 5-6 … Each of those steps therefore removes its file from the list and adds an AC that `scripts/aid-lint-skill.sh <file>` is clean'). Step 3 ACs: lines 152-157 — no lint AC. Step 5 ACs: lines 229-234 — none. Step 6 ACs: lines 263-266 — none. $ sed -n '32,52p' plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh confirms aid-help.md, aid-init.md and aid-setup.md are all on GRANDFATHERED."
    recommendation: "Move the decision into each of the three steps as an explicit Files entry (`scripts/tests/test-skill-lint.sh` — remove `<file>` from GRANDFATHERED) plus an AC (`bash scripts/aid-lint-skill.sh <file>` exits 0), or record the keep-grandfathered decision per step. A cross-step paragraph in one step's body is invisible to the other steps' dispatch context."

  - id: L1-F17
    severity: low
    step: 13
    finding: "Step 13's AC uses `grep -rc`, which emits per-file counts, not a single total — 'yields exactly one full definition plus five references' is not a check any command produces as written."
    evidence: "Plan line 497: `grep -rc 'Step rendering rule' plugins/aid-orchestrator/commands plugins/aid-orchestrator/skills` yields exactly one full definition plus five references."
    recommendation: "State two concrete commands: `grep -rc 'executing_step = min(current_step + 1, total_steps)' commands/ skills/ | grep -v ':0$'` returns exactly one file, and `grep -rho 'Step rendering rule' commands/ skills/ | wc -l` returns 6."

  - id: L1-F18
    severity: low
    step: 9
    finding: "Carry-forward of L1-F9 — the card-uniqueness assertion still greps a Czech literal that exists nowhere at HEAD, so it can only ever assert count==1 against the file Step 9 itself creates."
    evidence: "Plan line 345; $ grep -rn 'Potřebuji tvoje rozhodnutí' --include=*.md . -> no matches."
    recommendation: "Add a language-independent structural probe (the card's section-label sequence) alongside the literal."

  - id: L1-F19
    severity: low
    step: 3
    finding: "Carry-forward of L1-F10 — the ecosystem `help-authoring-standard.md` is still unmentioned; the plan cites only `specs/artifact-standard.md`."
    evidence: "Plan line 34 cites the artifact standard; `grep -c 'help-authoring-standard' <plan>` -> 0. /opt/eco/docs/docs/ecosystem/specs/help-authoring-standard.md exists."
    recommendation: "One sentence in Step 3's Architecture Context recording that the standard governs in-app web help and that the CLI layer adopts only its completeness rule."

  - id: L1-F20
    severity: low
    step: plan-level
    finding: "The plan document itself is untracked (matched by `.gitignore:98 **/.aid-o/`), which is the exact defect class AB-10 was raised about for Step 16's fallback deliverable."
    evidence: "$ git check-ignore -v .aid-o/plans/P080-entrypoint-ux-help-handoffs.md -> .gitignore:98 **/.aid-o/ ; $ git ls-files on the same path -> empty. By contrast `git ls-files .aid-o | wc -l` -> 165, so force-adding plans is the established practice in this repo."
    recommendation: "`git add -f` the plan (and this CP1 evidence set) so the revision loop's inputs and outputs are reviewable at a fixed SHA — otherwise Reviewed-Head certifies nothing about the document that was actually reviewed."

confidence: high
