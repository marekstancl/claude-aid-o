# CP1-deep L2 (feasibility) — P080 (iteration 2)

_generated_by: aid-orchestrator:verifier@cp1-lens-L2
_generated_at: 2026-08-11T07:55:00Z
Reviewed-Head: cd1ab4af145b5272b200741ed41818ae058b2a18

stop_rule_blockers:
  - id: L2-B6
    step: 11
    new_in_iteration: 2
    claim: "Step 11's card-selection rule reads a per-gate `required` field that `gates_report.json` has never carried, and the renderer's declared signature has no second input that could supply it — a consumer reading a field the producer does not emit."
    evidence: |
      Plan Step 11 Implementation Detail (line 413): "Card rule: only `fail` on a REQUIRED gate
      selects the Blocked card — `skip` and `profile_excluded` are reported in the core table and
      never counted as failures." Signature (line 406):
      `aid_gate_outcome_render <gates_report_json> <run_dir> [waiver_dir]` — three inputs, none of
      them the gate configuration.
      Producer at HEAD:
        $ grep -n '"required"' plugins/aid-orchestrator/scripts/aid-run-gates.sh \
              plugins/aid-orchestrator/scripts/lib/aid-gate-row.sh
          -> (no output; the key is never written into a row)
        aid-run-gates.sh:1945  required=$(yq ".gates.\"${gate_name}\".required // false" "$execution_yaml")
          -> `required` is a SHELL variable read from `.aid-o/config/execution.yaml`, consumed only
             to set the run-level verdict (`:2001`, `:2338`: if required==true then overall="fail").
        Row assembly at :1937, :1961, :1997-1999, :2014, :2240-2241 and lib/aid-gate-row.sh:110-118
        emits exactly {gate,result,exit_code,duration_ms,output,attempts,(reason),(runtime_baseline),
        (job_id,job_state)} — no `required`.
      Real artifacts (six modern reports sampled):
        $ jq -r '.gates|to_entries[]|"\(.key): result=\(.value.result) required=\(.value.required // "ABSENT")"' \
            .aid-o/work/evidence/E-076-2_3/R-E076-2/gates/gates_report.json (and P076/R-P076-final-1,
            E-058-1_1, E-042-1_1, E-047-1_7, P076/R-P076-final-2)
          -> `required=ABSENT` on EVERY row of every report; result values observed across all 82
             shipped reports: pass 52, fail 49, skip 11, profile_excluded 25, null 37 (pre-2026-06
             format), 2 prose strings (E-005-3_4 legacy).
    impact: |
      The renderer cannot implement its own card rule. The implementer's escapes are (a) read
      `.aid-o/config/execution.yaml` — an input the step does not declare and the fixtures do not
      carry, so every fixture-driven bats case would need a synthetic config; or (b) treat ANY
      `fail` as blocking — which silently contradicts the plan's stated rule and turns a
      non-required gate failure into a Blocked card at the PM's boundary. Step 11's AC "a fixture
      whose report contains one `skip` and one `profile_excluded` row selects the Finished card" is
      satisfiable, but the AC that matters (a non-required `fail` → Finished) is unwritable.
    fix: |
      Select the card from the report's own top-level `.overall` field, which already encodes exactly
      "a REQUIRED gate failed" (aid-run-gates.sh:2001/:2338 set `overall="fail"` only under
      `required==true`; observed values across shipped artifacts: `pass` 79, `fail` 2, absent 1).
      Restate the rule as: "`.overall == "fail"` selects the Blocked card; the per-gate rows populate
      the core table, where `skip`/`profile_excluded` are reported and never counted as failures; a
      `fail` row while `.overall == "pass"` renders as a non-required failure line on the Finished
      card." Add the missing-`.overall` legacy case (one report in the shipped corpus) to Error
      Handling: fall back to "any `fail` row → Blocked" and say so in the card.

resolution_verification:
  - id: L2-B1
    step: 12
    status: PARTIAL
    check: |
      RESOLVED half — the two-input renderer is real and the split is correct:
        $ grep -n 'plan_summary' plugins/aid-orchestrator/scripts/aid-release-policy.sh
          :1096-1137 build `plan_summary` (PLAN mode ONLY) with plan_id, plan_final_run_id,
          reviewed_candidate_sha, approved_target_sha, target_ref, final_merge_sha,
          release_tag_status, epics[], plan_final_gates{}, specialist_review, remaining_backlog.
        $ sed -n '170,190p' plugins/aid-orchestrator/defaults/schemas/release-decision.schema.json
          -> `plan_summary` object with those exact properties.
        $ grep -n 'plan_summary' plugins/aid-orchestrator/scripts/aid-plan-fsm.sh
          :6634 plan-finalize --stage summary already hard-fails without it.
      So four of the five named facts (reviewed candidate SHA, approved target SHA, final merge SHA,
      release tag status) and the EPIC totals (`.epics | length`) are genuinely available, and the
      "no options field" correction matches the producer. The fail-closed fixture is writable.
      NOT RESOLVED — two residues the revision carried over verbatim from the adjudicator text:
      (a) **gate totals are not in `plan_summary`.** It carries only
          `plan_final_gates: {report: <path>, result: <string>, quarantine_substitutes: []}`
          (aid-release-policy.sh:1132-1133). There are no passed/failed counts. Step 12 (line 440)
          promises "EPIC and gate totals" from `plan_summary`; a totals tile can only render `—`,
          or the renderer must open `plan_final_gates.report` — a THIRD file, which is precisely the
          "no sibling evidence" clause at line 445.
      (b) **the tag vocabulary stated at line 447 is wrong.** Plan: "the shipped vocabulary is
          `not_tagged`/tagged". Real values: `not_tagged` (aid-release-policy.sh:1128 default),
          `none` and `v<version>` (aid-plan-fsm.sh:7440-7450 `tag_status="none"` /
          `tag_status="v${version}"`). A fixture asserting `tagged` fails; a tile switching on
          `tagged` never fires.
      Also worth stating in the step: NO plan-mode release-decision.json exists anywhere in this
      repo — `grep -rl plan_summary .aid-o --include='*.json'` returns nothing across 13 shipped
      release-decision.json artifacts (all EPIC-mode), so every fixture is hand-authored, and the
      schema marks plan_summary `"$comment": "reference — not validated by aid-protocol-validate.sh"`.
      Fix: change "EPIC and gate totals" to "EPIC totals (`.epics | length`, plus the skipped
      count) and the plan-final gate RESULT (`plan_final_gates.result`) — there are no gate counts in
      the decision; the totals tile renders the result word, not a count"; correct the tag vocabulary
      to `not_tagged | none | v<version>` and render it verbatim.

  - id: L2-B2
    step: 13
    status: RESOLVED
    check: |
      $ grep -rn 'Step rendering rule' plugins/aid-orchestrator/commands plugins/aid-orchestrator/skills
        commands/aid-stop.md:119, commands/aid-status.md:984, commands/aid-run.md:402,
        skills/memory.md:28, skills/pipeline.md:1322, skills/pipeline.md:2756
        -> the revised Files list (plan lines 473-477) now names exactly these six sites in five
        files, with pipeline.md's double copy called out and every numeric aid-fsm.sh anchor replaced
        by literals. Verified the literals: `_fsm_human_step` comment :1128, definition :1132, and
        exactly THREE call sites — :2858, :2870, :5246 — as the plan now states.
      Bats rewrite is satisfiable:
        $ sed -n '103,116p' scripts/tests/bats/test-fsm-step-render.bats
          the P073 block asserts per file `grep -c 'Step rendering rule' >= 1` AND
          `grep -c 'executing_step = min(current_step + 1, total_steps)' >= 1`.
        $ grep -rn 'executing_step = min(current_step + 1, total_steps)' commands skills scripts
          -> the six prose copies + the test's own grep line, nothing else.
        So the discriminator the rewritten assertion needs already exists and is unique to the full
        rule: after the collapse, `grep -rl` on that literal returns exactly skills/pipeline.md
        (= "exactly one file states the full rule") while all five files keep a line containing
        "Step rendering rule" (= "each surface contains a reference"). The block's three template
        guards (`{current_step}/{total_steps}`, `{current_step} of {total_steps}`,
        `{current_step + 1}`) are unaffected by a reference line.
        $ grep -rn 'human: step' --include='*.sh' --include='*.bats' --include='*.md' plugins/
          -> only aid-fsm.sh:1137/:1139 (the producer) and the four assertions at
          test-fsm-step-render.bats:33/41/49/76 that Step 13 now explicitly rewrites. No third
          consumer pins the wording.
      Residual (low, recorded as L2-F4 below): the AC's `grep -rc` cannot itself distinguish a
      definition from a reference.

  - id: L2-B3
    step: 5
    status: RESOLVED
    check: |
      $ sed -n '64,78p' README.md      -> "| Command | What it does |" at :66, a NINE-row table
        missing /aid-setup, /aid-verify-plan, /aid-verify-implementation, /visual-companion.
      $ sed -n '72p' README.md         -> "…10-file structure, stack auto-detection, idempotent"
      $ sed -n '110p' README.md        -> "`/aid-init` auto-configures everything. Fine-tune in …"
      $ grep -n '^| Command\|10-file\|auto-configures' plugins/aid-orchestrator/README.md -> (none)
      The revised Files bullet (plan line 212) targets repo-root README.md with those exact anchors,
      AC5 (line 234) is stated against the repo-root file, and the Step 16 :110 collision is called
      out. Nothing left to fix.

  - id: L2-B4
    step: 14
    status: PARTIAL
    check: |
      RESOLVED half — both files are now in scope with correct facts:
        $ grep -nE '[0-9]-part|four-part' plugins/aid-orchestrator/commands/aid-audit-tests.md
          :50 four-part, :202 "5-part" (the single outlier), :285 four-part, :331 four-part
          -> plan line 514 states exactly this, and "6-part" appears nowhere. Step 9's required-
             surface list (line 345) now includes commands/aid-audit-tests.md.
        $ grep -rn -i 'czech' commands/aid-verify-implementation.md commands/aid-verify-plan.md
          aid-verify-plan.md:33, :122 and aid-verify-implementation.md:59, :149 — four lines, exactly
          as the Files bullets (lines 512-513) now say.
      NOT RESOLVED — the acceptance commands do not cover the edit set they were widened for:
        $ grep -rn 'in \*\*Czech\*\*' plugins/aid-orchestrator/commands/ | wc -l   -> 2
        The two matches are :59 and :33 ("delivered in **Czech**"). Lines :149 and :122 read
        "5–10 sentences **in Czech**" — the literal is `**in Czech**`, so the pattern `in \*\*Czech\*\*`
        does NOT match them. Plan-level AC7 (line 701) and Step 14 AC3 (line 537) therefore both pass
        with two of the four hardcoded-Czech mandates still in the tree — the exact failure mode
        AB-3 was raised to close, reproduced one level down.
        Fix: make both ACs `bash -c '! grep -rni "czech" plugins/aid-orchestrator/commands/'`
        (zero legitimate occurrences exist today), or enumerate the four line anchors explicitly.

  - id: L2-B5 / AB-9
    step: 4
    status: PARTIAL
    check: |
      Executed the revised spec LITERALLY (three-base resolution order + the stated tokeniser) over
      the shipped registry — script:
      /tmp/claude-1000/-opt-eco-projects-aid-orchestrator/9c2f71e9-.../scratchpad/cite_spec.py
        rows=423  tokens_checked=811  violations=52
          - 40 violations whose token contains NO slash  (grammar false positives)
          - 12 violations whose token is path-shaped      (real dangles, 9 distinct rows)
          - 40 distinct rows flagged in total
      Huge improvement over iteration 1 (764 tokens flagged): the three-base rule WORKS —
      `docs/extending-aid.md` resolves at the repo root, `commands/…`/`scripts/…`/`defaults/…` under
      the plugin root, bare `lib/…` under plugin+scripts/. The `'s`, `:~<digits>`, `:<identifier>`
      and ` (…)` strips all fire correctly on the four grammars the plan quotes.
      Residual defect: the "skip values not containing `/`" rule is applied to the VALUE, before the
      `;` / ` + ` split, so every non-path continuation part becomes a flagged token. Real examples
      the spec flags today:
        lifecycle_isolated_index_commit | source | '_aid_lc_isolated_commit)'
          (value: "scripts/lib/aid-lifecycle.sh (_aid_lc_precheck_write + _aid_lc_isolated_commit)")
        test_execution_no_double_dispatch | source | 'gate_runner_direct'
        plan_mode_unresolved_block | source | 'cmd_done_advance)'
        invalidation_map_observe | instruction | "'CP6'"
      With the spec as written the harness cannot exit 0 after the repairs, so Step 4 AC1 ("exits 0
      after the repairs") and plan-level AC2 (line 666, `test-enforcement-registry-cites.sh`
      expected_exit 0) both fail. One clause closes it: "a split part whose leading token contains no
      `/` is prose, not a cite — skip it" (apply the no-slash skip per TOKEN, not per value).
      Second residual: the enumerated repair list over-counts. Under the revised three-base rule only
      NINE rows carry path-shaped dead cites — provenance_aggregate_fabricated, research_quality_gates,
      knowledge_base_write_protect, research_idempotency, knowledge_dedup_threshold,
      release_policy_preempted, test_audit_catalog_approval_boundary, test_audit_never_auto_invoked,
      release_version_sealed. Four of the plan's 13 now resolve cleanly and need no repair:
        $ for r in c2_completed_lenses_e5 c2_wiring_gate_observe recovery_escalation_terminus \
              semantic_wiring_would_block; do yq ... ; done
          -> their cites are scripts/lib/review-profile-check.sh:~84,
             defaults/schemas/review-profile.schema.json, scripts/aid-fsm.sh:~2250,
             defaults/policies/semantic-review.yaml, agents/verifier.md,
             scripts/lib/aid-recovery-ladder.sh — all present.
      The plan's own "re-measure at implementation time and reconcile any delta" clause covers this,
      so it is a sizing note, not a defect: 9 repairs, not 13.
      Row-id uniqueness assertion verified against the INSTALLED yq:
        $ yq --version                                            -> v4.53.2 (mikefarah)
        $ yq '.enforcements[].id' defaults/enforcement-registry.yaml | wc -l   -> 423
        $ yq '.enforcements[].id' … | sort | uniq -d              -> (empty)
      The AC command works as written and is green on the current tree.

  - id: NEW-1 (init idempotency declared exception)
    step: 8
    status: RESOLVED
    check: |
      $ grep -n 'date -u\|date +' plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh
        337:  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)     (the ONLY clock read in the lib)
      $ sed -n '336,353p' <same>   -> `# AUTO-GENERATED by aid-init at ${now_iso}` is emitted as the
        FIRST line of the composed file; everything else in the header is static
        (`generated_by: "aid-init v2.16.0"`, stack label derived from the fixture).
      $ grep -n 'date -u\|date +' plugins/aid-orchestrator/scripts/lib/aid-gitignore-backfill.sh
        -> (no output)
      $ grep -n 'date' plugins/aid-orchestrator/defaults/hooks/pre-commit
        -> :75 only, inside `_aid_emit` which runs at COMMIT time, not install time; the installed
           bytes are static.
      So normalising that one header line is sufficient for the scripted substrate the harness
      replays (execution.yaml compose + gitignore backfill + hook marker install + defaults copy).
      The plan's exception declaration (line 309) is accurate and the `work/active.md` exclusion
      reasoning matches commands/aid-init.md:594-597.

  - id: NEW-2 (gate-report object iteration)
    step: 11
    status: PARTIAL
    check: |
      Object shape and enum confirmed on real artifacts:
        $ jq '.gates | to_entries[0]' .aid-o/work/evidence/E-061-3_6/R-E061-3/gates/gates_report.json
          -> {gate, result:"pass", exit_code:0, duration_ms:100417, output, attempts:1,
              runtime_baseline:{…}}  — `attempts` is an INTEGER, as the step assumes.
        Enum across all 82 shipped reports: pass|fail|skip|profile_excluded (+ 37 legacy rows with
        no `result` at all and 2 legacy rows whose `result` holds prose, from the pre-2026-06
        `{status, required, attempts:[…]}` format at
        .aid-o/work/evidence/E-004-1_1/run_20260224_115f/gates_report.json).
      Two gaps remain: the missing `required` field (blocker L2-B6 above), and the input PATH is not
      single-valued in shipped code —
        aid-run-gates.sh:1629      "${_evidence_dir}/gates/gates_report.json"   (runner default)
        aid-fsm.sh:1825            "${evidence_dir}/gates_report.json"          (DONE precondition)
        aid-plan-close-check.sh:834 "${run_dir}/gates_report.json"
      and both layouts occur in the corpus (E-076 under gates/, P076/R-P076-final-1 flat). Step 11
      line 411 names only the `gates/` form. State both, or take the path the runner reported.

  - id: NEW-3 (new dependency edges Step 3→6, Steps 1,2→14)
    status: PARTIAL
    check: |
      No cycle introduced — the full declared graph is strictly forward
      (1←none, 2←1, 3←2, 4←2, 5←1, 6←5+3, 7←6, 8←5, 9←none, 10←9, 11←10, 12←10, 13←9,
       14←9,11,12,13,1,2, 15←14, 16←4,8,15).
      But BOTH new edges are discarded by the shipped generator. Extracted `parse_step_deps`
      (scripts/aid-plan-to-epic.sh:629-720) and ran it on the plan's actual dependency lines:
        IN : "Step 5 — ownership carve-outs land first …; Step 3 — this step also modifies …"
        OUT: [5]                       # aid-plan-to-epic.sh:645 strips everything from the FIRST
                                       # em dash on, so the Step 3 edge never reaches the parser
        IN : "Step 9, Step 11, Step 12, Step 13 — wires what they built; and Steps 1 + 2 — …"
        OUT: [9, 11, 12, 13]           # the "Steps 1 + 2" edge is likewise inside the prose tail
      And even if they parsed, `strip_cross_phase_deps` (:1138) drops every dependency outside the
      current EPIC's step range — both new edges are cross-EPIC (3∈EPIC1→6∈EPIC2; 1,2∈EPIC1→14∈EPIC3).
      So the plan's justification at lines 260 and 531 ("`aid-epic-to-json.sh` turns declared edges
      into execution order, and without it the two steps race on one file") is FALSE for exactly the
      two edges it was written for. The ordering that actually protects commands/aid-help.md is the
      sequential EPIC queue (EPIC 1 completes before EPIC 2). Recorded as finding L2-F2 — the edges
      are harmless documentation, but the enforcement claim must not stand as written.

findings:
  - id: L2-F1
    severity: high
    step: 14
    finding: "AC7 and Step 14 AC3 use a pattern that matches only 2 of the 4 hardcoded-Czech lines the step is required to fix."
    evidence: |
      $ grep -rn 'in \*\*Czech\*\*' plugins/aid-orchestrator/commands/
        commands/aid-verify-plan.md:33  |  commands/aid-verify-implementation.md:59   (2 hits)
      aid-verify-implementation.md:149 and aid-verify-plan.md:122 read
      "5–10 sentences **in Czech**" — literal `**in Czech**`, which the pattern cannot match.
      Plan AC7 (line 701) and Step 14 AC3 (line 537) both use that pattern.
    recommendation: "Use `! grep -rni 'czech' plugins/aid-orchestrator/commands/` (zero legitimate occurrences today) or enumerate all four anchors."

  - id: L2-F2
    severity: medium
    steps: [6, 14]
    finding: "The two CP1-mandated dependency edges are inert: the shipped dependency grammar discards them and cross-EPIC edges are stripped anyway — the plan asserts an enforcement that does not exist."
    evidence: |
      aid-plan-to-epic.sh:645 `raw="$(sed 's/[—–].*$//; s/ - .*$//; s/ (.*$//')"` — everything from
      the first em dash is prose. Executed against the plan's own lines: Step 6's line yields [5];
      Step 14's yields [9, 11, 12, 13]. aid-plan-to-epic.sh:1135-1139 then strips cross-EPIC numbers.
    recommendation: |
      Either write the edges BEFORE the first annotation dash ("Depends on: Step 3, Step 5 — …"),
      or replace the false mechanism sentence with the true one: "Step 3 is in EPIC 1 and Step 6 in
      EPIC 2; the sequential EPIC queue is what orders them — the declared edge is documentation,
      because aid-plan-to-epic.sh strips cross-EPIC dependencies."

  - id: L2-F3
    severity: medium
    step: 16
    finding: "Step 16's AC3 is binary while the step text sanctions a 'PM-pending' outcome — the step cannot pass its own acceptance in the outcome it explicitly allows."
    evidence: |
      Plan line 584: "If the PM has not committed at plan-close, the step reports the deliverable as
      PM-pending — never as done." Plan line 606 (AC3): "`git -C /opt/eco/docs ls-files
      docs/aid/specs/artifact-templates.md` returns the file AND `sidebars.ts` references its id …
      If the PM commit is still pending, the step reports PM-pending with the exact command handed
      over." A verify gate reads the command, not the sentence after it.
    recommendation: "Make the primary-path AC conditional in machine terms: 'either the ls-files+sidebar assertion holds, or the fallback path's `git ls-files` assertion holds AND the verify output carries the PM handover command' — one of the two must be mechanically true."

  - id: L2-F4
    severity: low
    step: 13
    finding: "Step 13's AC uses `grep -rc`, which cannot distinguish the one full definition from the five references."
    evidence: |
      Plan line 497: "`grep -rc 'Step rendering rule' plugins/aid-orchestrator/commands
      plugins/aid-orchestrator/skills` yields exactly one full definition plus five references."
      Measured now: aid-stop.md:1, aid-status.md:1, aid-run.md:1, memory.md:1, pipeline.md:2 —
      the same counts a fully-collapsed tree would produce, since a reference line also contains the
      phrase.
    recommendation: "Add the discriminator that already exists: `grep -rl 'executing_step = min(current_step + 1, total_steps)' commands skills` returns exactly one file (skills/pipeline.md)."

  - id: L2-F5
    severity: low
    step: 11
    finding: "The renderer must tolerate a second legacy report shape, not only the escalation variant the step names."
    evidence: |
      .aid-o/work/evidence/E-004-1_1/run_20260224_115f/gates_report.json rows are
      `{status:"pass", required:true, type:"rule", attempts:[{attempt,timestamp,result,details}]}` —
      `status` not `result`, `attempts` an ARRAY not an integer. 37 rows across the corpus have no
      `result` key at all. Step 11 (line 411) names only the escalation-shaped variant as the second
      accepted shape.
    recommendation: "State that a row without `result` is rendered `unknown` and never counted as pass/fail; the renderer must not crash on the pre-2026-06 shape (or scope it explicitly to reports produced by the current runner)."

  - id: L2-F6
    severity: low
    step: 16
    finding: "EPIC 3 remains shippable, but Step 16 is now the plan's single largest risk concentration and its terminal position leaves no room to absorb a docs-repo refusal."
    evidence: |
      EPIC 3 = 8 steps (9-16); L-effort at Step 10, Step 14, Step 16 (Step 4's growth to L sits in
      EPIC 1 and does not load EPIC 3). Step 16 now touches: docs/extending-aid.md (110 KB), the
      423-row registry (9 new rows), both CHANGELOGs, marketplace.json, plugin.json, both READMEs,
      PLUS two files in a separate repository (`/opt/eco/docs/docs/aid/specs/artifact-templates.md`
      and `/opt/eco/docs/sidebars.ts`) whose commit authority the step itself says this plan does not
      have. Verified: `/opt/eco/docs/sidebars.ts` lists every AID page by explicit id (:519-554,
      `link: {type:'doc', id:'aid/intro'}`), `docs/aid/specs/` does not exist, and both
      `onBrokenLinks`/`onBrokenAnchors` are `throw` — a page added without the sidebar edit is
      invisible, and a sidebar id without the page breaks the docs build.
    recommendation: "Split into 16a (in-repo docs + registry rows) and 16b (cross-repo page + sidebar + release ceremony), so a PM-pending docs commit cannot hold the release step, and keep the two cross-repo writes adjacent so sidebars.ts is never committed without its page."

  - id: L2-F7
    severity: low
    steps: [1, 2, 4, 5, 8, 9]
    finding: "Everything else re-verified clean at this HEAD — the revision did not break any previously-verified baseline."
    evidence: |
      13-surface enumeration, the aid-init.md defects, the `active_preset` gap, the aid-help.md
      `### Topic:` convention, the Step 9 uniqueness grep and the reuse anchors all still hold as
      recorded in iteration 1 (unchanged files at cd1ab4a). New this round:
        $ yq '.presets|keys' defaults/policies/permissions.yaml -> ["autonomous"]; Step 6 now names
          commands/aid-setup.md:80 as the single stale surface and leaves skills/setup/permissions.md:60
          alone — matches the file.
        $ yq '.enforcements | length' -> 423 rows (the adjudicator's "183 rows" undercounts; the
          registry has 423 ids). Step 4's totals-recompute AC is unaffected.
    recommendation: "None."

confidence: high
