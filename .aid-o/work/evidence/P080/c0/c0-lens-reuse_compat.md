# C0 lens: reuse_compat — P080 (observe, advisory)

_generated_by: aid-orchestrator:verifier@c0-lens-reuse_compat
_generated_at: 2026-08-11T04:29:00Z
Reviewed-Head: 6154ebd714cc69ffa4dd222542cf1e820e078ab8

<!--
Head note: during the review HEAD advanced 6154ebd -> cd1ab4a. The only change is
`docs/plans/2026-07-23-POST-P064-TO-E10-EXECUTION-CHECKLIST.md` (+18/-1); no file
cited below is touched, so every citation holds at both revisions.
-->

stop_rule_blockers:
  - id: C0-RC-1
    step: 13
    claim: "Collapsing the 'Step rendering rule' copies to one definition + references breaks a shipped test that requires the full rule text in FIVE files, and the plan only knows about four copies."
    evidence: |
      Real copies at HEAD (6, not 4): commands/aid-status.md:984, skills/pipeline.md:1322,
      skills/pipeline.md:2756, commands/aid-run.md:402, commands/aid-stop.md:119,
      skills/memory.md:28.
      Shipped guard: scripts/tests/bats/test-fsm-step-render.bats:100-115 loops over
      `commands/aid-status.md commands/aid-run.md commands/aid-stop.md skills/pipeline.md
      skills/memory.md` and asserts, per file, BOTH
        `grep -c 'Step rendering rule' >= 1` AND
        `grep -c 'executing_step = min(current_step + 1, total_steps)' >= 1`.
      A one-line reference ("see pipeline.md's Step rendering rule section") satisfies the
      first grep but not the formula grep, so the collapse fails the existing suite.
      Plan quote (Step 13 Files): only pipeline.md ~1198/~2628, aid-run.md ~317,
      aid-status.md ~491 are listed; aid-stop.md and skills/memory.md are not in the plan at
      all, and the bats edit is described only as "extend ... new cases assert the
      `Plan Step N` wording". Plan AC: "Exactly one full 'Step rendering rule' definition
      remains (grep -c across the four files = 1 definition + 3 references)" — unreachable
      while the shipped test demands the formula in five files.

  - id: C0-RC-2
    step: 13
    claim: "Rewording `_fsm_human_step` output to 'Plan Step N of T' changes a contract four shipped test assertions pin verbatim; the plan only adds cases, never updates them."
    evidence: |
      scripts/aid-fsm.sh:1132-1141 — helper emits ` (human: step %s of %s complete)` /
      ` (human: step %s of %s is next)`.
      scripts/tests/bats/test-fsm-step-render.bats asserts those exact strings at 4 places:
      `(human: step 3 of 3 complete)`, `(human: step 3 of 7 is next)`,
      `(human: step 2 of 5 is next)`, `(human: step 1 of 4 is next)`, plus the negative
      `[[ "$output" != *"step 0 of"* ]]`.
      Plan quote (Step 13 Files): "extend `_fsm_human_step` output wording to `Plan Step N of T`"
      and, for the suite, "new cases assert the `Plan Step N` wording" — no instruction to
      update the four existing assertions, so the step as written lands red.

  - id: C0-RC-3
    step: 6
    claim: "The preset 'single source of truth' does not contain the presets the step says it contains; the step's own two instructions (policy-file-wins vs delete 'Two presets') contradict each other."
    evidence: |
      defaults/policies/permissions.yaml:15 `active_preset: "autonomous"  # autonomous | custom`;
      :17 `presets:` with exactly ONE child key at :18 `autonomous:` (the other 2-space keys in
      the file, :136 `security:` / :141 `qa:` / :145 `release:`, sit under `role_overrides:`).
      `grep -rn 'aspirin\|steroids' plugins/` → only commands/aid-setup.md:80 and two archived
      CHANGELOG lines. No aspirin/steroids preset exists.
      Therefore skills/setup/permissions.md:60 "Two presets: autonomous (default), custom" is
      CORRECT against the policy file, and aid-setup.md:80 is the actual dangling claim.
      Plan quote (Step 6): "the 'Two presets: autonomous (default), custom' claim replaced by
      the actual preset list read from `defaults/policies/permissions.yaml` (grounded:
      autonomous, aspirin, steroids + custom overlay)" — the parenthetical is false at HEAD.
      Plan AC: "`grep -rn 'Two presets' skills/setup/permissions.md` returns nothing" forces
      deleting a true statement, while the second AC ("no surface names a preset absent from
      the policy file") forbids the replacement list. The two ACs cannot both be met.

findings:
  - id: C0-RC-F1
    severity: high
    step: 5
    finding: "Step 5 delegates all CLAUDE.md content authority to setup's claude-md module, but that module has no notion of the standards profile init currently enforces — the capability is dropped, not moved."
    evidence: |
      commands/aid-init.md:240-242 — "When `vulcan` standards are selected, the project
      CLAUDE.md must reference the authoritative ecosystem documents … Mandatory references
      added to project CLAUDE.md".
      `grep -n 'standards\|vulcan\|ecosystem' plugins/aid-orchestrator/skills/setup/claude-md.md`
      → no output. The receiving module is standards-blind.
      Plan quote (Step 5 Implementation Detail): "setup's claude-md module is the sole AID
      writer (init's current 'mandates Vulcan ecosystem references' text becomes a pointer to
      the setup module — init itself stops instructing CLAUDE.md content)".
    recommendation: "Make Step 5's carve-out conditional on Step 5 (or a new sub-item) also porting the standards-driven mandatory-reference rule into skills/setup/claude-md.md, with a grep AC that the vulcan-standards reference list survives somewhere. Otherwise the pointer points at a module that will not do it."

  - id: C0-RC-F2
    severity: medium
    step: 14
    finding: "Step 14 mis-states the reused audit renderer's contract as 6-part; the shipped renderer is FOUR-part since P078. Following the step literally stamps a false number on a component it does not own."
    evidence: |
      scripts/lib/aid-test-audit-chat-summary.sh:4-10 — "Renders the mandatory FOUR-part
      plain-language chat message — P072 Step 19, narrowed by P078"; section headings in the
      heredoc are `## 2.` … `## 4.` + a Technical evidence appendix.
      commands/aid-audit-tests.md:50 "The four-part block below", :285 "## The four-part chat
      handoff", :331 "the four-part text"; the single stale line is :202 "render the mandatory
      5-part chat summary".
      Plan quote (Step 14 Edge Cases): "its 6-part renderer mandate unchanged (its '5-part' vs
      6-part drift is corrected as part of the reference edit — one word)".
    recommendation: "Correct the step text to: aid-audit-tests.md:202 '5-part' → 'four-part', matching the renderer and the three other in-file mentions. Add an AC `grep -c '5-part\\|6-part' commands/aid-audit-tests.md` == 0."

  - id: C0-RC-F3
    severity: medium
    step: 11
    finding: "The gate renderer's declared input names the wrong producer and ignores the two-location ambiguity of the real artifact; 'the merged gate report' only exists on the escalation path."
    evidence: |
      scripts/lib/aid-run-gates-report.sh exposes exactly one function, `merge_escalation_report
      <targeted_report_json> <full_report_json> <reason>` (:33), used only when a targeted pass
      escalates to a full pass — a normal run never produces a "merged" report.
      The canonical artifact is `gates_report.json` written by aid-run-gates.sh
      (default path `${_evidence_dir}/gates/gates_report.json`, aid-run-gates.sh:1629), and
      consumers already accept BOTH locations: aid-release-policy.sh:792-795 checks
      `${EVIDENCE_DIR}/gates_report.json` then `${EVIDENCE_DIR}/gates/gates_report.json`.
      Plan quote (Step 11 Architecture Context): "Input is the existing merged gate report JSON
      (produced by `lib/aid-run-gates-report.sh` — verified canonical input per grounding)".
    recommendation: "Restate the input as `gates_report.json` produced by aid-run-gates.sh, with merge_escalation_report's output accepted as the same shape on escalation runs, and require the caller/renderer to resolve both the root and `gates/` locations (mirror aid-release-policy.sh:792-795) rather than assuming one path."

  - id: C0-RC-F4
    severity: low
    step: 2
    finding: "Half of Step 2's reuse citation is wrong: aid-lint-skill.sh:58-70 is a sed line-window + grep, not an awk frontmatter scan. The fenced_stripped citation is correct."
    evidence: |
      scripts/aid-lint-skill.sh:58 `fm=$(sed -n '1,8p' "$file")` + `grep -qE '^name:'` etc.;
      :70 `grep -qE '^description:' <(sed -n '1,6p' "$file")`. No awk in that region.
      scripts/aid-lint-skill.sh:39-44 `fenced_stripped() { awk ' … ' "$file"; }` — matches the
      plan's second citation exactly.
      Also note `fenced_stripped` closes over the script-local `$file` and aid-lint-skill.sh is
      an executable, not a sourceable lib, so "reuse" here means copy-into-aid-help-index.sh,
      i.e. a third copy of the fence-stripper (Step 9's wiring test wants it too).
    recommendation: "Reword Step 2 to 'the fixed line-window frontmatter scan (sed -n 1,6p + grep) at aid-lint-skill.sh:58-70' and, since Steps 2 and 9 both need fence-stripping, put one `aid_strip_fences <file>` in scripts/lib/aid-help-index.sh (or a shared lib) instead of a second and third copy."

  - id: C0-RC-F5
    severity: low
    step: 7
    finding: "The 'both surfaces already invoke scripts this way' premise holds for init but not for setup, and one of the shared script's states is unreachable from setup."
    evidence: |
      commands/aid-init.md sources libs today (:121, :151 `source "$AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh"`).
      `grep -n '\.sh\|scripts/' commands/aid-setup.md` → no output: setup invokes zero scripts;
      it routes to skills/setup/*.md prose only.
      commands/aid-setup.md:22-28 Prerequisites: "CHECK: Does .aid-o/config/project.yaml exist?
      NO → 'Workspace not initialized. Run /aid-init first.' → EXIT" — so the summary's
      `workspace: absent` line (Step 7 AC1) can never render from setup.
    recommendation: "State in Step 7 that setup gains its first script invocation (and that permissions/exec-bit/AID_PLUGIN_PATH resolution must be spelled out for a prose-executed surface with no prior example), and scope the `workspace: absent` bats case to the init/standalone caller only."

  - id: C0-RC-F6
    severity: low
    step: "3, 12, 13, 14"
    finding: "Several cited line anchors have already drifted past recognition on the post-P076 tree — in one case the cited range now covers an unrelated subject, so 'rebase the anchors' is not a formality."
    evidence: |
      Step 12 cites skills/pipeline.md ~2145-2174 for the pm-brief plan boundary; that range at
      HEAD is the CP4/CP5 dispatch section. The real pm-brief handoff is :2262-2302
      ("canonical machine handoff", `aid-pm-brief.sh` at :2273/:2281).
      Step 13 cites `_fsm_human_step` at aid-fsm.sh ~819-840 and call sites :2430/:2442/:3935/:3945;
      actual helper at :1128-1141 and exactly THREE call sites (:2858, :2870, :5246). The cited
      machine-surface site ":4141 verify-state JSON payload" is now `_resume_say` output.
      Step 14 cites aid-run.md ESCALATION ~294-315 / DONE-review ~352-360; actual `### State:
      ESCALATION` at :377 and `DONE REVIEW —` at :440.
    recommendation: "Downgrade every numeric anchor in Steps 3/12/13/14 to a literal anchor (the plan already has the drift protocol for 3/13/14 — extend it to Step 12), and fix the two counts that are not drift but wrong facts: 6 rule copies not 4, 3 helper call sites not 4."

confidence: high
