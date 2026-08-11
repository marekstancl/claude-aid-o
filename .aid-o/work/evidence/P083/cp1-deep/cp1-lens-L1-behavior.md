# CP1-deep — Lens L1 BEHAVIOR — P083

I read the whole plan, then traced each step's runtime path in the tree at `main` (1d5cd04, v2.83.1) rather than trusting the plan's or the block-verification's paraphrase. Concretely: I opened `fsm_check_streamlined_integration_review` (`aid-fsm.sh:1817-1855`) and grepped every `gates_report.json` reader and writer including `aid-plan-fsm.sh:4554` and `aid-plan-close-check.sh:834`; I read both AC awk blocks in `aid-plan-to-epic.sh:909-949` and followed `step_ac_raw` to its JSON sink at `:1148-1153`; I read `_release_update_files` (`aid-release.sh:544-681`), `_release_rollback_updated` (`:775-791`) and every `UPDATED[]` consumer including the explicit staging loop at `:1044-1075`; for Step 5 I mapped `plan_diff` to the profiles that include it (`standard`, `full`, `release`, `bats_all_quarantine`, `release_quarantine`) and **ran the gate command for real** against P083 itself; I read `_aid_read_toggle` and all five of its call sites; I read `render_gate_profiles_block` (`aid-init-execution-yaml.sh:206-266`) and `append_gate_profiles_block` (`:395-410`) and re-walked the `_pfsm_has_gate_profiles` → `plan_branch` → `plan-finalize` chain the plan cites; I checked the live baseline's `*_by_context` maps for Step 8 and `aid-generation-readiness.sh:16-44` for Step 9. Most of the plan's premises hold up: Step 3's gitignored-`project.yaml` fallback claim, Step 7's four-link chain, Step 8's empty-map claim and Step 9's "the graph is a pure function of the plan" are all confirmed first-hand. The findings below are where a branch the change creates has no declared outcome.

stop_rule_blockers: [L1-1]

findings:

  - severity: critical
    ref: L1-1
    summary: >
      Step 5 gives `plan_diff` a `command:` and `required: true` in a config where the
      gate sits in the EPIC-level profiles `standard` (.aid-o/config/execution.yaml:365)
      and `full` (:390), not only in `release` (:397). The gate verifies the WHOLE plan's
      `## Acceptance Criteria`, and P083's own AC1-AC11 each run a bats suite that does
      not exist until its own step lands. Run today against this plan,
      `aid-plan-diff.sh --plan .aid-o/plans/P083-ten-verified-defects.md` exits **1** with
      `overall_verdict: "fail"`, `ac_count: 11`, `absent_count: 11`. With `required: true`
      that is a failing row in `gates_report.json`, `overall != pass`, and the GATES:DONE
      precondition at `aid-fsm.sh:2990-3002` refuses the transition. EPIC 1 and EPIC 2 of
      this very plan cannot reach DONE — a merge path that is green today turns red for
      every EPIC of every multi-EPIC plan, and the plan declares no branch for it. The
      second, undeclared sink is the compliance record: `aid-fsm.sh:2573-2595` turns the
      now-present `plan-diff.json` into `plan_ac_match=false` (today it is `null`, since
      the file is never produced), a key registered `severity: blocking`
      (`defaults/check-severity.yaml:25`, `defaults/enforcement-registry.yaml:182`) and
      folded into `overall` at `aid-fsm.sh:2720-2723`. This repo happens to have no
      `.aid-o/config/check-severity.yaml`, so the blocking routing degrades to advisory
      here — but any consumer that has the file gets `overall: fail` on top of the gate
      failure.
    evidence: >
      Measured: `bash plugins/aid-orchestrator/scripts/aid-plan-diff.sh --plan
      .aid-o/plans/P083-ten-verified-defects.md --evidence-dir $(mktemp -d)
      --base-commit HEAD` → `exit=1`, `{"overall_verdict":"fail","ac_count":11,
      "summary":{"present_count":0,"absent_count":11,"skipped_count":0}}`.
      Profiles: `.aid-o/config/execution.yaml:365 (standard), :390 (full), :397 (release),
      :409 (bats_all_quarantine), :436 (release_quarantine)`. Refusal:
      `aid-fsm.sh:2996-3002`. Plan quote (Step 5 Files): "the self-host `plan_diff` gate
      regains the `command:` the shipped default has had all along … and an explicit
      `required: true`". Plan quote (Risks): "Step 5's decision could go either way and
      the profiles are the merge path" — the risk named is the decision, not this outcome.
    suggested_fix: >
      Step 5 must declare the per-EPIC outcome and choose one explicitly: (a) restore the
      `command:` but keep `required: false` for the self-host config, so the gate reports
      an honest `fail` row without blocking an EPIC whose plan is by definition incomplete,
      and let only the plan-final `release` profile treat it as blocking; or (b) remove
      `plan_diff` from `standard`/`full`/`bats_all_quarantine` and keep `required: true`
      only in `release`/`release_quarantine`. Either way the step must state, in Edge Cases,
      what a mid-plan EPIC run does with a plan whose later ACs are not yet satisfied, and
      must name the `plan_ac_match` compliance flip (null → false) and its blocking
      severity registration as a declared consequence.

  - severity: high
    ref: L1-2
    summary: >
      Step 5's config edit cannot reach the trees where plan-final gates actually run,
      while its runner-side refusal can. `.aid-o/config/execution.yaml` is gitignored and
      each worktree carries its own physical copy: `.aid-worktrees/plan-P080/.aid-o/config/
      execution.yaml:223-243` still holds the command-less `plan_diff` with the same
      "P038+" note, and lists it in the same profiles (`:365,:390,:397,:409,:436`).
      So after Step 5 lands, a plan-final run inside an existing worktree hits the NEW
      runner refusal ("a gate in a profile's include[] with no command is a loud
      configuration refusal") against an OLD config the step never edited — the plan's
      own live worktree becomes unrunnable, and this is not the "consumer project whose
      config predates this change" case the plan does declare. AC6's verification pattern
      (`yq -r '.gates.plan_diff.command' .aid-o/config/execution.yaml`) is likewise
      evaluated against whichever tree runs it, so it can read PASS in the main checkout
      and FAIL in the worktree that runs the gate.
    evidence: >
      `grep -n -A6 '^  plan_diff:' .aid-worktrees/plan-P080/.aid-o/config/execution.yaml`
      → `:223-226` note `'required=false for AID self-host: … gate becomes meaningful for
      P038+'`, no `command:`; `grep -n plan_diff` on the same file → `:365,:390,:397,:409,
      :436`. Plan quote (Step 5 Edge Cases): "A consumer project whose config predates this
      change — the refusal fires on their first run with a message that says what to add".
    suggested_fix: >
      Step 5 must name the per-tree copies as part of its change surface: either state that
      every live worktree's `.aid-o/config/execution.yaml` is updated in the same step (and
      list them), or make the runner refusal apply only to gates whose absence is not
      explained by an older config generation. AC6 must state which tree it is evaluated in.

  - severity: high
    ref: L1-3
    summary: >
      Step 1 calls the flat `<evidence>/gates_report.json` an "explicitly-logged legacy
      fallback" and its Architecture Context calls it "the one outlier against seven
      agreeing readers and one writer default". The flat path is not legacy: it is the
      path the plan-final gates stage writes TODAY — `aid-plan-fsm.sh:4554` sets
      `report_file="${run_dir_abs}/gates_report.json"` and passes it as `--report-file`
      at `:4572`, and `aid-plan-close-check.sh:834` reads exactly that flat path for its
      check5 verdict. So there are two live conventions (EPIC runs → `gates/`, plan-final
      runs → flat), and mislabelling one of them as legacy sets up the next reader to
      delete a fallback that is a current writer's only sink. The plan's Edge Case
      "Report at the flat path only (an in-flight run)" describes a transient, but the
      flat path is permanent for plan-final.
    evidence: >
      `aid-plan-fsm.sh:4554` `local report_file="${run_dir_abs}/gates_report.json"`;
      `:4572` `--report-file "$report_file"`; `aid-plan-close-check.sh:834`
      `local gr="${run_dir}/gates_report.json"`. Plan quote (Step 1 Files): "accepts the
      flat sibling only as an explicitly-logged legacy fallback so an in-flight run started
      before this change still advances".
    suggested_fix: >
      Restate Step 1's Architecture Context to say the flat path is the CURRENT plan-final
      writer (`aid-plan-fsm.sh:4554`), not a legacy artifact, and that the fallback is
      therefore permanent, not transitional. Say explicitly whether
      `fsm_check_streamlined_integration_review` is ever reached on a plan-final evidence
      dir; if it is not, say so, so the fallback's justification does not rest on a false
      "in-flight run" premise.

  - severity: medium
    ref: L1-4
    summary: >
      Step 6 adds a third outcome to a two-valued contract with no sink. `_aid_read_toggle`
      returns 0=enabled / 1=disabled and every one of its five call sites consumes it as
      `cmd || enabled=false` — `aid-fsm.sh:2406` (`|| { echo null; return 0; }`), `:7970`,
      `:7971`, `aid-release-policy.sh:434`, `:490`. A "named failure, not a silent
      `return 0`" is indistinguishable from `1` at every one of those sites, so the intended
      loud refusal degrades to "the toggle is off": `fsm_eval_simplifier_present` emits
      `null` (the compliance dimension is not evaluated at all) and the C4 aggregator
      records reporter/simplifier as disabled. The plan says what the function should do
      and nothing about what the five callers do with it.
    evidence: >
      `plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh:20-30`; callers
      `aid-fsm.sh:2406,7970,7971`, `aid-release-policy.sh:434,490`. Plan quote (Step 6
      Files): "distinguishes 'read the toggle, it says enabled' from 'could not read the
      toggle': the unreadable case is a named failure, not a silent `return 0`".
    suggested_fix: >
      Step 6 must state the mechanism (a distinct exit code plus an out-of-band message, or
      a `die`) AND what each of the five call sites does with it — in particular whether
      `fsm_eval_simplifier_present` returns `null`, `false`, or aborts. Add an AC that pins
      the observable behaviour at a caller, not only inside the helper.

  - severity: medium
    ref: L1-5
    summary: >
      Step 3 describes `UPDATED[]` as the rollback set and the source of the printed count.
      It is also the release's explicit git-staging list: `aid-release.sh:823`
      (`git add "${UPDATED[@]}"`, legacy path) and `:1049-1053` (prepare-plan, one
      `git add --` per entry), followed by the "files outside the version-file registry are
      staged" cross-check at `:1062-1075` and the empty-set refusal at `:1044`. Adding
      `.claude-plugin/marketplace.json` (the `.metadata.version` / `.plugins[0].version`
      branches) and the plugin README to `UPDATED[]` therefore changes what the prepare
      commit CONTAINS, not only what a rollback restores — files that are edited but
      unstaged today become staged and committed. That is very likely the desired outcome,
      but it is an undeclared change to a commit that becomes the frozen review candidate.
    evidence: >
      `aid-release.sh:823`, `:1044-1053`, `:1062-1075`, `:781-791`. Plan quote (Step 3
      Files): "record their file in `UPDATED[]` exactly once, so `_release_rollback_updated`
      (:775-791) restores them; the 'Updated N files total' count at :681 is derived from
      the same array it restores from".
    suggested_fix: >
      Step 3 must name the staging consumers (`:823`, `:1049-1053`) and declare that the
      prepare commit gains these files, and add an AC asserting the staged set after a
      successful prepare equals `UPDATED[]` — otherwise the only pinned behaviour is the
      abort path.

  - severity: medium
    ref: L1-6
    summary: >
      Step 7 fixes the composer, but the population it names as broken — projects that
      already carry the two-profile `{targeted, full}` table — is not reached.
      `append_gate_profiles_block` (`aid-init-execution-yaml.sh:395-410`) is a pure append
      guarded by `execution_yaml_has_gate_profiles`, and the step's own Edge Case says "a
      project's own hand-written table is not overwritten". An existing consumer keeps its
      two profiles, `_pfsm_has_gate_profiles` still returns 0, `plan-finalize` still aborts
      at `aid-plan-fsm.sh:4490-4493` with "profile 'release' has an empty or missing
      include[]". The Objective ("A project initialised by `/aid-init` reaches
      `plan-finalize`") reads as covering all consumers; only fresh inits are covered.
    evidence: >
      `aid-init-execution-yaml.sh:395-410` (append-only); `:239-242` zero-stacks branch;
      `:256-265` the two-profile here-doc; `aid-plan-fsm.sh:9867-9879`
      (`_pfsm_has_gate_profiles` is true for ANY non-empty table); `:4485-4493`. Plan quote
      (Step 7 Edge Cases): "An existing project re-running init — the additive-upgrade
      contract is unchanged; a project's own hand-written table is not overwritten."
    suggested_fix: >
      Step 7 should narrow its Objective to fresh inits, or add a declared repair path for
      an existing two-profile table (detect the composer's own signature and extend it,
      leaving genuinely hand-written tables alone), with the discrimination rule stated and
      an AC for each of the two populations.

  - severity: medium
    ref: L1-7
    summary: >
      Step 2's continuation rule is undefined for a flush-left line that is neither a
      bullet nor the `**` terminator. Today's filter (`if (in_ac && $0 ~ /^-[[:space:]]/)`)
      simply drops such lines; the new rule is stated only as "continues through indented
      lines until the next flush-left bullet or the section terminator". Real plans put
      prose paragraphs, numbered lists and fenced blocks inside step Acceptance Criteria
      sections (e.g. `.aid-o/plans/P040-dispatch-lifecycle.md:1222-1231`, where a fenced
      ```yaml block follows AC prose). If such a line neither terminates nor joins, the
      criterion stays open and a LATER indented line — including an indented line inside a
      fenced block — is appended to a criterion it does not belong to, and lands in `ac[]`
      (`aid-plan-to-epic.sh:1148-1153`) which C3's AC lenses read.
    evidence: >
      `aid-plan-to-epic.sh:915` `if (in_ac && $0 ~ /^-[[:space:]]/)`; `:917` terminator
      `if (in_ac && $0 ~ /^\*\*/) { in_ac = 0 }`; sink `:1148-1153`
      (`step_ac_json` → `<!-- step-N: files=…; ac=… -->`). Plan quote (Step 2 Create):
      "a criterion begins at a flush-left `- ` bullet and continues through indented lines
      until the next flush-left bullet or the section terminator".
    suggested_fix: >
      State the rule for a flush-left non-bullet line explicitly (recommendation: it
      terminates the criterion, consistent with the plan's own "resolve toward
      under-joining"), and add a pinned case to `test-ac-extraction.bats` for a step AC
      section containing prose and a fenced block between two criteria.

  - severity: low
    ref: L1-8
    summary: >
      Step 6's claim that a POSIX rewrite is "byte-identical to today for every existing
      case" on a PCRE-capable grep is not pinned for whitespace forms. The current patterns
      use `\s` (`^\s{0,4}${section}:\s*$` and `^\s+enabled:\s+false\s*$`,
      `aid-review-signals.sh:24-25`), which matches tabs; a naive ERE rewrite using literal
      spaces or `[[:space:]]{0,4}` differs on tab-indented YAML, and the second pattern's
      `\s+` means a flush-left `enabled: false` does not disable today. Nothing in the
      step's ACs asserts either shape.
    evidence: >
      `plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh:24-25`. Plan quote
      (Step 6 Edge Cases): "A grep that supports `-P` — behaviour byte-identical to today
      for every existing case."
    suggested_fix: >
      Add tab-indented and flush-left `enabled:` cases to `test-review-signal-toggle.bats`
      so the equivalence claim is pinned rather than asserted.

confidence: high
