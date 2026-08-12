# CP1-deep — C0 lens reuse_compat — P082

I read all 551 lines of the plan and then verified every component it names against the live tree at `main` (v2.82.0): the pre-commit hook's `_aid_in_scope` and its FSM `commit_scope_violation` twin, the `/aid-init` execution.yaml composer chain (`compose_execution_yaml` → `render_gate_profiles_block` → `execution-stacks/*.yaml`) and the plan-mode resolver `_pfsm_has_gate_profiles`, `aid-prefilter.sh`'s CP2/CP3 range resolution and its output-filename derivation plus every consumer of `verifier-output-step-N.md`, the IMP-274 portability scanner and its per-file allowlist (with an actual re-scan of the tree under the widened pattern), `_aid_read_toggle` in `aid-review-signals.sh` and both of its callers, `aid-release.sh`'s README substitution and probe primitive, the two acceptance-criteria awk extractors in `aid-plan-to-epic.sh`, every reader of `gates_report.json`, `plan_manifest_add_epic`'s lineage parameter and all of its sourced call sites, `cmd_set_field`, and the test runner's suite discovery. Six of the twelve steps reuse an existing component in a way the component does not support as described; the remainder check out.

stop_rule_blockers: []

findings:

  - severity: high
    ref: C0-RC-1
    summary: >
      Step 1 plans a shared predicate library sourced by BOTH the pre-commit hook
      and the FSM, but the hook is architecturally unable to source any plugin
      library — `plugins/aid-orchestrator/defaults/hooks/pre-commit:36-42` states
      the rule explicitly and already keeps a deliberate hand-copy of
      `scripts/lib/aid-roots.sh::aid_state_root` for exactly this reason: "a
      consumer-repo hook cannot know the plugin cache path, so it cannot source
      the lib". The hook is installed into a consumer's `.git/hooks/` and has no
      `AID_PLUGIN_PATH` and no plugin-dir resolver. As written the step either
      does not work in a consumer project, or reintroduces the plugin-path
      dependency the hook was built to avoid — while its own AC ("the hook and
      the FSM companion agree on every case") is what motivated the shared lib.
    evidence: plugins/aid-orchestrator/defaults/hooks/pre-commit:36-42 ("a consumer-repo hook cannot know the plugin cache path, so it cannot source the lib") vs plan line 73 ("Create: plugins/aid-orchestrator/scripts/lib/aid-scope-match.sh — the one shared predicate both callers source")
    suggested_fix: >
      Drop the "both callers source it" framing. Either (a) keep the hook's
      established pattern — a marked, deliberate copy of the predicate inside the
      hook block, with the shared lib as the single AUTHORITY and a test that
      asserts the hook's copy is byte-identical to the lib's function body (this
      is the mechanism that actually keeps the two from drifting, and it is
      already proven by `_aid_state_root`); or (b) state a concrete plugin-path
      resolution strategy for the hook and cost it. Restate the Step 1 AC as
      "hook copy and lib agree, asserted mechanically", not "both source".

  - severity: high
    ref: C0-RC-2
    summary: >
      Step 2 fixes `plugins/aid-orchestrator/defaults/execution.yaml`, but that
      file is on NO consumer init path. `/aid-init` composes
      `.aid-o/config/execution.yaml` from per-stack fragments under
      `defaults/execution-stacks/` via `compose_execution_yaml`
      (`commands/aid-init.md:120-124`, `scripts/lib/aid-init-execution-yaml.sh:316`);
      nothing copies `defaults/execution.yaml` into a project. Worse, the composer
      ALREADY emits a `gate_profiles` table (`aid-init-execution-yaml.sh:258-264`,
      profiles `targeted` + `full`), and the mode resolver counts entries in the
      project's own file (`aid-plan-fsm.sh:9866-9871`,
      `ey="${root}/.aid-o/config/execution.yaml"`, `yq '.gate_profiles | length' > 0`).
      So a fresh project WITH a detected stack already resolves to `plan_branch`;
      the premise "every project initialised from defaults silently falls back to
      per-EPIC releases" is false. The one real gap is the zero-detected-stacks
      branch, which emits only `# gate_profiles: no stacks detected …`
      (`aid-init-execution-yaml.sh:238-241`). Additionally the omission from
      `defaults/execution.yaml` is a documented deliberate decision, not an
      oversight: `aid-plan-fsm.sh:9861-9865` says P064 added the table to the
      self-host file "not to the defaults/execution.yaml that /aid-init
      distributes, so a consumer project that merely upgrades the plugin would
      flip to plan_branch and resolve its gates against nothing at all." The plan
      reverses a recorded design decision without naming it.
    evidence: plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh:316-345 + :238-264; plugins/aid-orchestrator/commands/aid-init.md:120-124; plugins/aid-orchestrator/scripts/aid-plan-fsm.sh:9861-9871 — vs plan lines 101-106 ("A project initialised from the plugin's own defaults gets plan_branch… Modify: plugins/aid-orchestrator/defaults/execution.yaml")
    suggested_fix: >
      Re-target the step at the actual consumer path: close the zero-stacks
      branch of `render_gate_profiles_block` (emit a minimal, named table or a
      loud, actionable refusal instead of a comment), and state explicitly
      whether the plugin-upgrade-only population is meant to flip — quoting and
      overriding `aid-plan-fsm.sh:9861-9865` if so. If `defaults/execution.yaml`
      is still to be edited, say what reads it (today: only
      `tests/test-instruction-consistency.sh:108` and a runner assertion) and
      drop the claim that editing it changes a consumer's release model.

  - severity: medium
    ref: C0-RC-3
    summary: >
      Step 2 also proposes giving the shipped template "the same rank order this
      repo uses (`quick < targeted < standard < full < release`)". The composer
      derives profiles from the gate names each detected stack fragment actually
      defines and emits exactly two (`targeted`, `full`), explicitly "never
      references self-host names like bats_fsm/bats_all (D3 isolation)"
      (`aid-init-execution-yaml.sh:17-22`, `:258-264`). This repo's own five-rank
      table carries a written warning that its include lists are deliberately
      NOT a monotonic chain while the rank order is consumed as a SAFETY order by
      the FSM (`.aid-o/config/execution.yaml:316-322`). Copying the five-name
      rank into a consumer-facing template hands consumers a rank order whose
      profiles cannot be populated from their gates and whose non-monotonicity
      caveat does not travel with it.
    evidence: plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh:258-264; /opt/eco/projects/aid-orchestrator/.aid-o/config/execution.yaml:316-322 — vs plan line 104 ("add a gate_profiles table with the same rank order this repo uses (quick < targeted < standard < full < release)")
    suggested_fix: >
      Keep the consumer table derived, not copied: reuse
      `render_gate_profiles_block`'s derivation as the single authority and state
      which rank names a consumer gets. If a five-rank order is genuinely wanted
      for consumers, that is a change to the composer and to D3 isolation, and it
      needs its own step and its own risk row.

  - severity: high
    ref: C0-RC-4
    summary: >
      Step 7's preferred option ("the output filename is derived after the
      checkpoint is known and carries it") renames an evidence file that the plan
      itself lists as a frozen surface, and that has many hardcoded consumers.
      `aid-prefilter.sh:96` writes `${evidence_dir}/verifier-output-step-${step_n}.md`;
      that exact literal is reconstructed independently by
      `aid-acceptance-evidence.sh:164` (`evidence_ref="verifier-output-step-${step_num}.md"`),
      asserted by the FSM's CP2 precondition (`aid-fsm.sh:5707` via
      `fsm_check_verifier_output`), and documented as the CP2 contract in
      `defaults/templates/verifier-output-template.md:15` and
      `agents/verifier.md:248` ("The FSM gate reads this file — format must not
      change"). A CP3-specific name also makes Step 7's own AC ("the FSM's
      wrong-checkpoint refusal still fires") vacuous, since the FSM would never
      see the renamed file. The plan's Constraints line 463 already forbids this
      ("Frozen surfaces: evidence filenames").
    evidence: plugins/aid-orchestrator/scripts/aid-prefilter.sh:96; plugins/aid-orchestrator/scripts/aid-acceptance-evidence.sh:164; plugins/aid-orchestrator/scripts/aid-fsm.sh:5707; plugins/aid-orchestrator/defaults/templates/verifier-output-template.md:15 — vs plan lines 264 and 463
    suggested_fix: >
      Resolve the choice at plan time rather than deferring it to the step, and
      resolve it toward the non-renaming option: refuse a CP3 classify whose
      target file already exists carrying a different `checkpoint:` value (the
      "never silently overwritten — refuse and name both" behaviour the step's
      Error Handling already describes), which fixes the destruction without
      touching a frozen filename. If the rename option is kept, enumerate the
      four consumers above in the Files list and drop it from the frozen-surface
      constraint explicitly.

  - severity: medium
    ref: C0-RC-5
    summary: >
      Step 5 says "the per-file allowlist is re-derived from the widened scan",
      but that allowlist is not a current-state count — it is a provenance ledger
      of instances "verified present at the P064 base 2a51a2f", declared "tracked
      to shrink, never to grow"
      (`tests/bats/test-aid-plan-release-boundary.bats:7205-7217`). Re-deriving it
      silently changes the key's meaning to "whatever is in the tree today". The
      numbers move materially: under the widened pattern
      `tests/test-instruction-consistency.sh` goes 2 → 5 (lines 90, 130, 158, 169,
      180 — three of them `grep -rohP`), which is a GROW the existing invariant
      forbids. Conversely the recorded `aid-release.sh 3` currently scans as **0**,
      because `_imp274_scan` matches the literal `grep -oP` and the live call site
      is `grep -m1 -oP` (`aid-release.sh:341`) — so that allowlist row has been
      dead for as long as it has existed. Neither fact is in the plan.
    evidence: plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats:7205-7224 (allowlist comment + `_imp274_scan` literal match); plugins/aid-orchestrator/scripts/aid-release.sh:341 (`grep -m1 -oP`); `grep -c 'grep -oP' plugins/aid-orchestrator/scripts/aid-release.sh` → 0 — vs plan line 200 ("the per-file allowlist is re-derived from the widened scan")
    suggested_fix: >
      Say in the step that the ledger's semantics change, and re-anchor it: after
      widening, re-baseline each row with a written reason per row (the allowlist
      comment already requires one) and restate the shrink-only invariant against
      the new baseline. Call out `test-instruction-consistency.sh` 2 → 5 as an
      expected, reasoned re-baseline rather than a silent number edit. Note also
      that `_imp274_scan` only walks `*.sh`, so the `-oP` uses in
      `tests/bats/test-aid-release.bats:56,92` stay invisible after widening —
      state whether that is deliberate.

  - severity: medium
    ref: C0-RC-6
    summary: >
      Step 4 speaks of "the awk block that emits acceptance criteria" (singular).
      There are two, in the same function and with identical extraction logic:
      `step_ac` (`aid-plan-to-epic.sh:909-925`, emits the role-prefixed flattened
      list) and `step_ac_raw` (`:936-950`, emits the unprefixed text that feeds
      the per-step scoping block and the frozen `ac[]` fixture convention).
      Fixing only one produces exactly the two-drifting-copies shape the plan
      says it exists to end, and would make the EPIC's flattened AC section and
      its per-step `ac[]` disagree on the same criterion. Separately, the step's
      justification — "The rule mirrors the Files-bullet grammar the repository
      already uses, where an indented line continues the entry above it" — is not
      what that grammar does: `_AID_FILES_BULLETS_AWK`
      (`scripts/lib/aid-scoping.sh:126-138`) captures only lines whose `-` sits at
      column 0 and silently DROPS an indented continuation; it never joins it.
      The plan is inventing a join rule, not reusing one.
    evidence: plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh:909-925 and :936-950; plugins/aid-orchestrator/scripts/lib/aid-scoping.sh:126-138 — vs plan lines 167 and 172 ("the awk block that emits acceptance criteria…"; "The rule mirrors the Files-bullet grammar… one convention, two consumers")
    suggested_fix: >
      Name both awk blocks in the Files list, or factor the AC extraction into
      one shared awk program in `lib/aid-scoping.sh` the way
      `_AID_FILES_BULLETS_AWK` already is, and add an AC that the flattened
      section and the per-step `ac[]` carry the same joined text. Rewrite the
      Implementation Detail: state that this INTRODUCES a continuation rule
      (and, if intended, that the Files grammar should later adopt it), rather
      than claiming it already exists.

  - severity: low
    ref: C0-RC-7
    summary: >
      Step 8 claims the streamlined check "is the last consumer still on the
      pre-consolidation path" and its AC asserts "No other reader's resolution
      changed". Two other readers are still on the flat path:
      `aid-plan-close-check.sh:834` (`local gr="${run_dir}/gates_report.json"`,
      flat only) and `aid-release-policy.sh:791-795` (flat first, `gates/` as
      fallback). The canonical writer is
      `aid-run-gates.sh:1629` (`${_evidence_dir}/gates/gates_report.json`), matching
      the FSM's other readers at `aid-fsm.sh:2453`, `:2880`, `:2991`. The fix
      itself is right; the "last consumer" claim is not, and
      `aid-plan-close-check.sh` will keep failing on a run whose report is only at
      the canonical path.
    evidence: plugins/aid-orchestrator/scripts/aid-plan-close-check.sh:834; plugins/aid-orchestrator/scripts/aid-release-policy.sh:791-795; plugins/aid-orchestrator/scripts/aid-run-gates.sh:1629 — vs plan line 298 ("the audit found it is the last consumer still on the pre-consolidation path") and line 300 ("One constant, one reader")
    suggested_fix: >
      Correct the claim and decide `aid-plan-close-check.sh:834` in this step —
      either fix it alongside (it is one line) or record it as a knowingly
      untouched second flat-path reader. Consider extracting the resolution into
      one helper, since the plan's own recurring lesson is that a path constant
      copied into four files is what produced this defect.

confidence: high
