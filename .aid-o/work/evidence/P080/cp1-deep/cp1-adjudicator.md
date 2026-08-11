# CP1-deep adjudicator — P080 (iteration 2, authoritative)

_generated_by: aid-orchestrator:verifier@cp1-deep-adjudicator
_generated_at: 2026-08-11T10:20:00Z
Reviewed-Head: cd1ab4af145b5272b200741ed41818ae058b2a18

verdict: pass
revision_count: 2
accepted_blockers: []

adjudication_note: |
  The iteration-2 lenses read the plan BEFORE the controller applied a further round of fixes.
  Every blocker they raise was re-tested against the plan as it stands on disk at this HEAD,
  with my own commands. Both surviving blocker claims are closed by post-lens fixes 1 and 2.
  Nothing survives that would make an implementer build the wrong thing or let a test go green
  on a falsehood, so this is a PASS, not a revision-count-2 escalation.
  Caveat recorded for the PM: the plan file itself is untracked (`.gitignore:98 **/.aid-o/`),
  so `Reviewed-Head` binds the repo I verified against, not the document text.

rejected_blockers:
  - id: L1-B8 (= L2-F1, = L3-F10) — "Czech grep matches 2 of 4 lines; plan-level AC7 never widened"
    rejection_reason: |
      Closed by post-lens fix 1 — verified by reading the plan and re-running the grep.
      Plan line 542 (Step 14 AC) and plan line 706 (plan-level AC7) both now read
        grep -rn Czech plugins/aid-orchestrator/commands/aid-verify-plan.md \
                       plugins/aid-orchestrator/commands/aid-verify-implementation.md
      — the BARE word, across BOTH files, so it matches all four occurrences and no
      asterisk form can slip through:
      $ grep -rn -i czech <the two files> -> 4 hits (plan:33, plan:122, impl:59, impl:149)
      $ grep -rn Czech   <the two files> -> 4 (same lines; the bare-word pattern catches
        both `in **Czech**` at :33/:59 and `**in Czech**` at :122/:149)
      The AC is scoped to the two verify files precisely so aid-audit-tests.md:54's legitimate
      "a Czech user" prose is not swept. Lens narrative describes the pre-fix text.

  - id: L1-B9 (= L2-B6) — "Step 11 card rule reads a per-gate `required` key that no row carries"
    rejection_reason: |
      Closed by post-lens fix 2 — verified by reading plan line 417 and the producer.
      The plan now states, emphasised: "**Card selection reads the envelope's `.overall`, never a
      per-gate verdict.**  … `.overall == "fail"` → Blocked card; otherwise Finished card", and
      records that rows carry no `required` key, that required-ness lives in execution.yaml and
      survives only into `.overall` (aid-run-gates.sh :2001/:2259, waived-required at :2145).
      A new AC pins exactly the case the lenses said was unwritable (plan line 433):
        "A fixture with a FAILING non-required gate but `overall: pass` selects the Finished card
         — proving the card follows `.overall` and not a per-row verdict."
      Producer re-verified: $ grep -n '"required"' scripts/aid-run-gates.sh scripts/lib/aid-gate-row.sh
      -> no row ever carries it; the envelope carries `overall`. The renderer's declared inputs suffice.
      Residual (advisory, not blocking): a legacy sentence later in the same paragraph still says
      "all required gates pass → Finished card". It is semantically equivalent and the emphasised
      rule + the AC are unambiguous, but it should be deleted at implementation time.

  - id: L1-F14 (high) — "three preset display strings; Step 6 AC unsatisfiable against Step 7"
    rejection_reason: |
      Closed by post-lens fix 6. Plan line 255 now defines exactly TWO canonical strings
      ("Case A, key present: `<preset> (preset) — autonomous_mode: <value>`"; "Case B, key absent:
      `autonomous (implicit — key missing, will be written on first change)`") and binds all three
      surfaces to them verbatim. Step 7's spec (plan line 287) no longer hardcodes a third string —
      it reads "rendered with the two canonical display strings defined in Step 6 — verbatim, no
      third phrasing". Step 6 AC (line 270) matches. The lens quoted the pre-fix line 283.

  - id: L1-F16 (= L3-F9, high) — "grandfathering decision is prose in Step 3 only; no Files entry, no AC"
    rejection_reason: |
      Closed by post-lens fix 5 — verified by grep over the plan:
      $ grep -n 'test-skill-lint.sh\|aid-lint-skill.sh' <plan>
        :136  Step 3 Files  — remove commands/aid-help.md from GRANDFATHERED
        :159  Step 3 AC     — aid-lint-skill.sh commands/aid-help.md zero findings + delisted
        :214  Step 5 Files  — remove aid-init.md AND aid-setup.md from GRANDFATHERED
        :238  Step 5 AC     — both files lint clean + neither on the list
      All three delistings now sit inside a declared step's Files list, so the scope gate permits
      the mutation and an AC detects a silent retention. (The :161 paragraph's phrasing "Steps 5-6"
      is loose — Step 5 owns both files — but the mechanics are complete; carried as advisory.)

  - id: L2-B5 / AB-9 residual — "the per-value no-slash skip leaves ~40 false positives, so the
      Step 4 harness can never exit 0, failing plan-level AC2"
    rejection_reason: |
      Closed by post-lens fix 4 (plan line 176: "**The 'no slash = prose label' skip is applied PER
      TOKEN, after tokenising — never per whole value.**"). Verified by IMPLEMENTING the plan's rule
      myself and running it over the shipped registry
      (scratchpad/cite2.py: three-base resolution, `;`/` + ` split, `:N`/`:~N`/`:ident`/possessive/
      `(…)`/`§`/` — `/` Step ` strips, per-token no-slash skip, skip status dead|removed_scoped):
        rows: 423   violating rows: 9   false positives: 0
        knowledge_base_write_protect, knowledge_dedup_threshold, provenance_aggregate_fabricated,
        release_policy_preempted, release_version_sealed, research_idempotency,
        research_quality_gates, test_audit_catalog_approval_boundary, test_audit_never_auto_invoked
      Exactly the lower end of the plan's declared 9–13 bracket, drawn from its own candidate list.
      The harness CAN exit 0 after those repairs, so Step 4 AC1 and plan-level AC2 are satisfiable.

  - id: L1-F12 / L2-B1(a)(b) — "Step 12 promises gate totals that plan_summary has not; tag
      vocabulary says `tagged`"
    rejection_reason: |
      Closed by post-lens fix 3. Plan line 445 now enumerates the shipped field set verbatim from
      the producer, states "**There are no gate totals in this artifact** — only a single
      `plan_final_gates.result` verdict plus the path to the report", says EPIC totals are COUNTED
      from `epics[]`, and fixes the vocabulary to `not_tagged | none | v<version>` with "the value
      `tagged` does not exist". Cross-checked against
      $ sed -n '1114,1136p' scripts/aid-release-policy.sh — field-for-field accurate. Line 452 also
      records that all 13 in-repo release-decision.json artifacts are EPIC-mode (`plan_summary: null`),
      so fixtures are hand-authored. (Only `plan_final_gates.quarantine_substitutes` is omitted from
      the list — advisory.)

  - id: L2-F2 — "the two CP1-mandated dependency edges are discarded by the shipped grammar"
    rejection_reason: |
      Parsing half closed by post-lens fix 8: plan lines 264 and 536 now place every step number
      BEFORE the first em dash, so `parse_step_deps` (aid-plan-to-epic.sh:645, which sed-strips from
      the first em dash) records [3,5] and [1,2,9,11,12,13] respectively.
      The cross-EPIC half stands but is not a blocker: `strip_cross_phase_deps` still drops 3→6 and
      1,2→14, and the real ordering guarantee is the sequential EPIC queue. The plan no longer
      asserts a false generator mechanism at line 264 (it states a requirement, not an enforcement);
      line 536's "so parse_step_deps actually records them" is true of parsing. Carried as advisory.

  - id: C0-PCF-1, C0-RC-1, C0-AUTH-1, C0-IDEM-1, C0-DAG-1 (all C0 lens blockers)
    rejection_reason: |
      Contract: C0 lens blockers are advisory by construction and never enter accepted_blockers or
      change the verdict. Additionally, the C0 set is iteration-1 vintage (files timestamped 06:29-06:30,
      before the 06:38 iteration-1 adjudicator) and its two loudest claims are already closed:
      C0-PCF-1 ("Step 12 takes the brief as its ONLY input") — the renderer is now two-input (line 445);
      C0-RC-1 ("the plan only knows about four copies") — the plan now names all six copies in five files.

resolution_verification:
  - id: AB-1 (Step 12 — single-input renderer reading facts the brief does not carry)
    status: RESOLVED
    check: |
      Plan line 445 declares `aid_plan_close_render <pm_decision_brief_json> <release_decision_json>
      <plan_id> <out_dir>` with the fact list split brief-vs-plan_summary.
      $ sed -n '1114,1136p' scripts/aid-release-policy.sh -> every named field present.
  - id: AB-2 (Step 13 — six copies in five files, wrong fsm anchors, bats rewrite)
    status: RESOLVED
    check: |
      $ grep -rc 'Step rendering rule' commands skills | grep -v ':0$'
        -> memory.md:1, aid-stop.md:1, aid-run.md:1, aid-status.md:1, pipeline.md:2  (= six in five)
      Plan lines 477-483 name all six sites, locate `_fsm_human_step` by literal, state THREE call
      sites, and make the bats rewrite an explicit Files entry with both blocks named.
  - id: AB-3 (hardcoded Czech in two files)
    status: RESOLVED
    check: "See rejected_blockers L1-B8 — Step 14 AC (:542) and plan AC7 (:706) both bare-word, both files, 4/4 lines."
  - id: AB-4 (preset vocabulary)
    status: RESOLVED
    check: |
      $ yq '.presets | keys' defaults/policies/permissions.yaml -> ["autonomous"]
      $ grep -rn 'aspirin\|steroids' commands/ skills/ -> commands/aid-setup.md:80 only.
      Plan Step 6 targets exactly that surface and leaves skills/setup/permissions.md:60 (correct) alone.
  - id: AB-5 (aid-init.md count contradictions + Lazy-Created heading)
    status: RESOLVED
    check: "Plan line 211 mandates the recount incl. execution.yaml, enumerates all four count statements (:3/:16/:35/:668) and the heading repair; Step 5 ACs (:233-234) and Step 8 (:319) consume the recomputed manifest."
  - id: AB-6 (Step 11 gate report input + card rule)
    status: RESOLVED
    check: "See rejected_blockers L1-B9 — `.overall` is now the card selector with a dedicated non-required-fail AC at plan line 433."
  - id: AB-7 (README target)
    status: RESOLVED
    check: "Plan line 215 targets repo-root README.md with the verified anchors (:66-78 table, :72, :110) and the Step 16 co-touch rule; plugin README carries none of those strings."
  - id: AB-8 (aid-audit-tests.md missing from Files; wrong part count)
    status: RESOLVED
    check: "$ grep -nE '[0-9]-part|four-part' commands/aid-audit-tests.md -> :50/:285/:331 four-part, :202 '5-part', no '6-part'. Plan line 519 states exactly this; AC :543 greps '5-part' == 0; the file is in Step 14 Files and Step 9's surface list."
  - id: AB-9 (Step 4 cite base, parser grammar, repair set)
    status: RESOLVED
    check: "My own implementation of the plan's rule: 423 rows -> 9 violating rows, 0 false positives, inside the plan's declared 9–13 bracket. Effort re-sized to L. Row-id uniqueness assertion verified green: yq '.enforcements[].id' | sort | uniq -d -> empty (yq v4.53.2)."
  - id: AB-10 (gitignored in-repo fallback)
    status: RESOLVED
    check: "$ git check-ignore -v plugins/aid-orchestrator/defaults/templates/artifact-templates-spec.md -> exit 1 (not ignored); Step 16 AC (:612) asserts `git ls-files` returns it, not mere existence."
  - id: AB-11 (cross-repo docs page: sidebar + commit authority + AC)
    status: PARTIAL
    check: |
      (a) and (b) landed: plan line 586 adds /opt/eco/docs/sidebars.ts as an explicit modified file and
      records that _category_.json is inert there (grep -c autogenerated sidebars.ts -> 0); line 589
      declares the separate PM-owned docs-repo commit with the command + SHA recorded in verify output.
      (c) landed but soft: AC :611 asserts ls-files AND sidebar id, then permits a "PM-pending" report.
      Residual carried to advisory — Success Criterion 6 still has no plan-level verification_pattern.
  - id: L1-F15 (Step 14 aid-run.md line anchors stale post-P076)
    status: UNRESOLVED (advisory)
    check: |
      Plan lines 349 and 513 still cite ~352-360 (DONE-review) and ~294-315 (ESCALATION).
      $ grep -n 'DONE REVIEW —\|Auditor Score:\|ESCALATION: {reason}' commands/aid-run.md
        -> :440, :443, :385   ($ sed -n '352,354p' -> EXECUTE transition bullets; '294,296p' -> "### State: READY")
      Not blocking: the step's Error Handling (:528) already mandates literal-anchor location on drift,
      and the sweep AC (:526) uses the literal `DONE REVIEW —`. Fix the two ranges at implementation time.
  - id: L3-F11 (artifact_publication_wiring has no nominated literal)
    status: UNRESOLVED (advisory)
    check: |
      Plan :349 (a2) requires "the publish-before-present clause" at each renderer-invoking site, but
      Step 11 (:411) says "publishing the artifact body via the Artifact tool first" and Step 12 (:446)
      says "artifact published before the card" — two wordings, no canonical token, no enumerated site list.
      Not blocking (the check exists, runs, and gates via plan AC5), but it can be satisfied weakly.
  - id: L3-F13 / L1-F17 / L2-F4 (Step 13 literals unnamed; grep -rc AC)
    status: UNRESOLVED (advisory)
    check: |
      $ grep -rl 'executing_step = min(current_step + 1, total_steps)' commands skills -> 5 files today.
      The discriminator the AC needs already exists and is unique to the full rule, so after the collapse
      `grep -rl` on it must return exactly skills/pipeline.md. Naming it turns AC :502 from eyeballed
      into mechanical. Implementation-time fix, not a plan defect.
  - id: L3-F6 (8-location version registry unenforced)
    status: RESOLVED
    check: "Post-lens fix 7 verified: plan AC :609 requires RUNNING plugins/aid-orchestrator/scripts/tests/verify-version-files.sh (file exists, 10 KB, executable), registers it as `version_registry_sync`, and records the deliberate decision to keep it release-boundary rather than joining the suite glob."
  - id: L3-F3 (invented run-all-tests.sh scoping flag)
    status: RESOLVED
    check: "Plan :554 explicitly denies the flag, cites the :132 unknown-argument exit, and offers the two real invocation forms with 'state which'."
  - id: L3-F5 (every new mechanical check registered)
    status: RESOLVED
    check: "Plan :584 lists nine new registry rows including config_summary_read_only and step_seam_human_rendering; $ grep -n 'fsm-step-render\\|executing_step' defaults/enforcement-registry.yaml -> no match, so the seam row is a genuine new registration."
  - id: NEW-1 (Step 8 declared idempotency exception)
    status: RESOLVED
    check: "lib/aid-init-execution-yaml.sh:337 is the only clock read in the replayed substrate; gitignore-backfill and the hook install emit static bytes. The single declared exception (plan :313) is sufficient and accurate."

c0_lens_observations:
  - lens: authority_runtime_matrix
    blockers_count: 2
    confidence: high
  - lens: dep_api_grounding
    blockers_count: 1
    confidence: high
  - lens: idempotency_matrix
    blockers_count: 2
    confidence: high
  - lens: planned_call_feasibility
    blockers_count: 1
    confidence: high
  - lens: reuse_compat
    blockers_count: 3
    confidence: high
  - note: |
      All five C0 outputs are iteration-1 vintage (06:29-06:30, pre-dating the 06:38 iteration-1
      adjudicator). Recorded as advisory observations only; they do not enter accepted_blockers and
      did not influence the verdict. Their two headline claims (C0-PCF-1 single-input Step 12,
      C0-RC-1 four-copy undercount) are already closed by the revisions. C0-IDEM-1's double-bump
      concern is addressed at plan :597 ("The release sub-step is idempotent by declaration") —
      by prose, with no assertion; carried below.

advisory_notes:
  - "Step 11 — delete the leftover legacy sentence 'Card selection: all required gates pass … → Finished card' at plan :417; the authoritative rule two sentences earlier is `.overall`."
  - "Step 11 — the report carries a canonical top-level `waived_gates[]` array (aid-run-gates.sh :2512-2537, IMP-270) that the plan never names; it takes waivers only from the optional `[waiver_dir]`. Make `waived_gates[]` the primary waiver source and the receipts dir the detail source."
  - "Step 11 — the gates report path is not single-valued in shipped code (`gates/gates_report.json` from the runner :1629 vs flat `gates_report.json` at aid-fsm.sh:1825 / aid-plan-close-check.sh:834) and both layouts exist in the evidence corpus. Accept both, or take the path the runner reported."
  - "Step 11 — 37 rows in the shipped corpus predate the current format (`status` instead of `result`, `attempts` as an array). Render a row without `result` as `unknown`, or scope the renderer explicitly to current-runner reports."
  - "Step 14 and Step 9 — replace the stale aid-run.md ranges (~352-360, ~294-315) with the literals the step already names: `DONE REVIEW —` / `Auditor Score:` (real :440-443) and `ESCALATION: {reason}` (real :385)."
  - "Steps 9/11/12/14/16 — nominate ONE canonical publish-before-present clause in communication.md, paste it verbatim at the four enumerated wiring sites, assert that literal in test-communication-wiring.sh, and word the `artifact_publication_wiring` registry row as a wiring-PRESENCE guard (the plan already says this at :584 — carry it into the test's match token)."
  - "Step 13 — name the two literals: the reference token asserted once per surface, and `executing_step = min(current_step + 1, total_steps)` whose repo-wide file count must equal 1 (it is 5 today). AC :502's `grep -rc` cannot distinguish a definition from a reference."
  - "Step 16 — AC3 permits a 'PM-pending' report, so the primary cross-repo path is not unconditionally falsifiable, and no plan-level verification_pattern (AC1-AC8) covers Success Criterion 6. Declare the in-repo fallback's `git ls-files` assertion as the mechanical floor that always holds."
  - "Step 16 — consider splitting into 16a (in-repo docs + registry rows) and 16b (cross-repo page + sidebar + release ceremony) so a pending docs-repo commit cannot hold the release; keep sidebars.ts and its page adjacent (both onBrokenLinks and onBrokenAnchors are `throw`)."
  - "Step 16 — the double-bump guard is prose only ('idempotent by declaration', :597) with no assertion; a fix-loop re-dispatch is the failure path P079 already carried."
  - "Step 16 — CLAUDE.md:195 cites a nonexistent registry path (`docs/plans/AID-audit-2026-06/enforcement-registry.yaml`); the file is gitignored, so state the correct path in docs/extending-aid.md and hand the CLAUDE.md line to the PM in the verify output."
  - "Steps 6 and 14 — the dependency numbers now parse correctly, but `strip_cross_phase_deps` still drops cross-EPIC edges (3→6, 1,2→14); the real ordering guarantee is the sequential EPIC queue. Do not rely on the declared edge as enforcement."
  - "Step 6 — the grandfathering paragraph (:161) says 'Steps 5-6' while Step 5 actually owns both aid-init.md and aid-setup.md delistings. Mechanics are complete; only the wording is loose. Note that Step 6 edits aid-setup.md AFTER Step 5 delisted it, so Step 6's edit must keep it lint-clean."
  - "Step 12 — `plan_final_gates` also carries `quarantine_substitutes` (aid-release-policy.sh:1133), omitted from the plan's field list; decide whether the card surfaces it."
  - "Step 4 — the registry has 423 rows (both lenses' '183' is an undercount); the 9-row repair set I measured with the plan's own rule is the lower bound of the declared bracket. Effort L is correctly sized."
  - "Step 15 — measure the bash-tests wall clock after adding nine inline suites (186 today, ci.yml records a run reaching only suite 53/131 in 20 minutes, current timeout 60); delegate test-init-idempotency.sh via DELEGATED_SUITES if the job approaches budget."
  - "Step 9 — the card-uniqueness grep targets `Potřebuji tvoje rozhodnutí:`, which matches nothing at HEAD, so it can only ever assert count==1 against the file Step 9 itself creates. Add a language-independent structural probe."
  - "Step 3 — /opt/eco/docs/docs/ecosystem/specs/help-authoring-standard.md exists and is unmentioned; one sentence in Architecture Context recording that the CLI layer adopts only its completeness rule."
  - "Plan-level — the plan document is untracked (`.gitignore:98 **/.aid-o/`) while 165 other .aid-o files are tracked. `git add -f` the plan and this CP1 evidence set so the reviewed text is pinned to a SHA."
