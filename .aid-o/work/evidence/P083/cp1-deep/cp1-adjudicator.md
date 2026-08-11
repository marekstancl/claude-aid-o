# CP1-deep Adjudicator — P083

I read the plan (497 lines) and all eight lens reports, then re-derived the six claims that would change the plan materially rather than trusting any lens. First-hand, in this checkout: I ran `aid-plan-diff.sh` against P083 (exit 1, `ac_count: 11`, `absent_count: 11`, `ac_label: ""` on every row), enumerated the profiles that carry `plan_diff` (five, not four), confirmed `gate_profile_defaults` is `null` in the self-host config so an EPIC gate run executes every gate, and traced the chain `aid-plan-diff.sh:365 exit 1` → `aid-run-gates.sh:2001 overall="fail"` → `aid-fsm.sh:2996-3002 PRECONDITION FAIL`. I reproduced the README BRE bug by writing `README.md:3` to a scratch file and running the exact `SEARCH`/`REPLACE` sed with `CURRENT=2.69.0` (the version actually on the line): no substitution; swapping `\(`/`\)` for `[(]`/`[)]` substitutes. I read `VALID_ROLES` at `aid-epic-to-json.sh:63` and the refusal at `:234`. I confirmed `generation/provisional-graph.json` has exactly one writer (`aid-plan-to-epic.sh:136`) and one seal consumer (`aid-generation-finalize.sh:112-119`, sha-binding plus byte-canonical equality), and that `aid-generation-readiness.sh:39-42` writes with an unconditional `>`. I confirmed `.aid-o/config/execution.yaml` is force-added and tracked with 16 commits while `.aid-o/config/project.yaml` is not tracked at all, and that the P080 worktree carries its own tracked copy still holding the command-less gate. I confirmed `test-aid-init.bats` is `# aid-tier: t0` and pins the two-profile output at `:99-111` and `:207-211`. Shape of the verdict: **revise**. The plan's diagnostic work is sound — nearly every defect premise I opened held up, which is the opposite of P082 — but three defects are fatal on the path this plan itself runs (an invalid role enum, a self-blocking gate, a red T0 suite), one step (4) is diagnosing the wrong path, and three steps are larger than the PM's sieve permits. Ten blockers accepted, three lens blockers refuted outright.

verdict: revise

revision_count: 1

accepted_blockers:

  - ref: AB-1
    lenses: [L2, L1, dep_api_grounding]
    severity: critical
    summary: >
      Step 5 gives the self-host `plan_diff` gate a `command:` AND `required: true`.
      That gate evaluates the WHOLE source plan's eleven acceptance criteria on every
      EPIC-level gate run, and eight of the eleven suites do not exist until later
      steps land. `gate_profile_defaults` is `null` in this repo's config, so an EPIC
      run has no profile and executes every gate; `plan_diff` sits in five profiles
      besides. The gate therefore exits 1 on EPIC 1's and EPIC 2's own gate runs,
      `overall` becomes `fail`, and GATES:DONE refuses the transition. P083 makes
      itself ungeneratable-to-DONE. Separately, the now-present `plan-diff.json` flips
      the `plan_ac_match` compliance key from `null` to `false`; it is registered
      `severity: blocking`, which degrades to advisory here only because this repo has
      no `.aid-o/config/check-severity.yaml` — a consumer that has one gets
      `overall: fail` twice over. The plan declares no branch for any of this; its
      Risks entry names only "the decision could go either way".
    evidence: >
      Measured by me: `aid-plan-diff.sh --plan .aid-o/plans/P083-ten-verified-defects.md
      --evidence-dir $(mktemp -d) --base-commit HEAD` → EXIT=1,
      `{"ac_count":11,"summary":{"present_count":0,"absent_count":11},"overall_verdict":"fail"}`.
      `yq '.gate_profile_defaults' .aid-o/config/execution.yaml` → `null`.
      Profiles carrying `plan_diff`: standard, full, release, bats_all_quarantine,
      release_quarantine. Chain: `aid-plan-diff.sh:365` `[[ "$absent_count" -gt 0 ]] && exit 1`;
      `aid-run-gates.sh:2001` `if [[ "${required:-false}" == "true" ]]; then overall="fail"; fi`;
      `aid-fsm.sh:2989-3002` GATES:DONE requires `overall == "pass"`.
      Contradicted plan quote (line 199): "the self-host `plan_diff` gate regains the
      `command:` … and an explicit `required: true`".
    required_change: >
      Step 5 restores the `command:` and keeps `required: false` in the self-host config
      for the duration of this plan, with an Edge Case stating in one sentence why: a
      mid-plan EPIC run is held to criteria the plan has not produced yet. The
      plan-final `release` run — where all eleven suites exist — is the blocking one.
      The runner-side refusal (the part that carries the value) lands regardless. The
      step must also name the `plan_ac_match` null→false flip and its blocking severity
      registration as a declared consequence. Additionally, rewrite the eleven plan-level
      AC bullets from `- [ ] AC1 — …` to `- [ ] AC1: …`: I measured every row coming back
      with `"ac_label": ""` because `aid-plan-diff.sh:167` requires a colon, so the gate
      this step arms produces eleven unattributable rows.

  - ref: AB-2
    lenses: [L3, idempotency_matrix, reuse_compat]
    severity: critical
    summary: >
      Step 4 diagnoses the wrong path. `README.md:3`'s freeze at v2.69.0 is a defect in
      the CONFIG path, caused by BRE escaping, and Step 4 explicitly declares the config
      path out of scope. `.aid-o/config/project.yaml`'s third README row escapes the
      URL parentheses as `\(` … `\)`; `aid-release.sh:575` applies the pattern through
      `sed -i "s|…|…|g"`, where BRE reads those as group delimiters, so the pattern can
      never match a line containing literal `(https://…)`. Its sibling row
      (`\*\*v{VERSION}\*\* (current)`) has no `\(` — which is exactly why `README.md:120`
      tracks the current version while line 3 does not. I also establish a second layer
      no lens stated cleanly: `SEARCH` substitutes `{VERSION}` → `$CURRENT` (2.83.1),
      so even with the escaping repaired the pattern cannot match a line stranded at
      2.69.0 — the miss is self-perpetuating and needs a one-time repair. Step 4 as
      written therefore cannot deliver Success Criterion 2, and its AC ("prose mentioning
      the previous version outside the list is untouched") actively codifies leaving
      line 3 stale.
    evidence: >
      Reproduced by me: wrote `README.md:3` verbatim to a scratch file, ran the exact
      `SEARCH`/`REPLACE` sed with CURRENT set to 2.69.0 (the version really on the line)
      → file unchanged. Replacing `\(`/`\)` with `[(]`/`[)]` → substitution succeeds.
      Pattern at `.aid-o/config/project.yaml:32`; sed at `aid-release.sh:568-576`.
      Contradicted plan quotes: line 169 "the visible proof: `README.md:3` still reads
      v2.69.0"; line 171 "The config path … is not the failing path in a worktree; this
      step fixes the fallback"; line 388 "`README.md` shows the current version after
      the next release".
    required_change: >
      Step 4 must add `.aid-o/config/project.yaml` to its Files list, fix the BRE
      grouping in the README row-3 pattern, and perform a one-time repair of
      `README.md:3` to the current version — otherwise no release will ever un-freeze it.
      See the plan-level judgment below: the anchored structure-discovering rewrite of
      the fallback should be dropped, not repaired.

  - ref: AB-3
    lenses: [L2]
    severity: critical
    summary: >
      Step 10 declares `**AID Role:** docs`. That is not a valid AID role; the enum is
      `docs-writer`. EPIC 3 generates fine and then hard-fails at machine conversion,
      after the CP1/C0 gates have already been consumed — the exact "ungeneratable"
      shape P082 died of.
    evidence: >
      Confirmed by me: `aid-epic-to-json.sh:63`
      `VALID_ROLES="architect domain backend frontend qa security observability docs-writer release e2e"`;
      refusal at `:234` `error_exit "Invalid role '$role' in step $num…"`. L2 reproduced
      the failure end to end in a clone and confirmed the patched row succeeds.
      Plan line 383: `**AID Role:** docs`.
    required_change: >
      Plan line 383 becomes `**AID Role:** docs-writer`.

  - ref: AB-4
    lenses: [idempotency_matrix, authority_runtime_matrix, reuse_compat, dep_api_grounding]
    severity: high
    summary: >
      Step 9 makes C0 `build-manifest` a second writer of
      `<evidence>/generation/provisional-graph.json` — an artifact with exactly one
      writer today, whose whole purpose downstream is a producer-integrity seal. A
      C0 review run after generation has begun silently re-binds that seal to the
      current plan bytes, and the finalize-time "belongs to another plan" refusal can
      no longer fire from a plan revision. The plan names neither the path, nor the
      existing writer, nor the consumer. Two further defects compound it: the caller
      runs under `set -euo pipefail` and readiness exits 1 on a lint failure (so
      Step 9's own AC "a plan that fails readiness still seals the absent status"
      cannot hold without an explicit guard), and readiness prints four lines to
      stdout while `cmd_build_manifest`'s stdout IS its return channel.
    evidence: >
      Confirmed by me: sole writer `aid-plan-to-epic.sh:136` (`--write-provisional
      …/generation/provisional-graph.json`); seal `aid-generation-finalize.sh:112-119`
      (`.plan_sha256 == $sha` then `provisional_canonical == final_canonical`);
      `aid-generation-readiness.sh:39-42` writes with `printf … > "$out"` (unconditional
      truncate) and `:29-37` exits 1 on lint failure; `lib/aid-c0-plan-review.sh:92`
      `set -euo pipefail`, `:547` `echo "$manifest_out"`.
      Plan quote (line 328): "`build-manifest` produces the provisional graph itself,
      by invoking `aid-generation-readiness.sh --write-provisional` for the plan under
      review, before sealing the manifest."
    required_change: >
      Drop the production. Step 9 keeps only its prompt-wording half — the check-table
      item and the phrase "the pre-generation authority" at
      `defaults/prompts/c0-plan-review-prompt-v1.md:32` stop describing an input the
      manifest records as absent. That is a two-line edit that fully satisfies the
      step's own stated Objective ("either answered from a real artifact **or removed
      from the prompt**") and touches no seal. If the PM insists on producing the graph,
      it must go to a C0-owned path (never `generation/`), with `rc` captured and
      stdout redirected, and the step must say why pre-minting does not hollow out
      `aid-generation-finalize.sh:119`.

  - ref: AB-5
    lenses: [L3, reuse_compat, L1]
    severity: high
    summary: >
      Step 7 replaces the composer's two-profile output with a five-profile ladder.
      `test-aid-init.bats` is a T0 merge-path suite that pins the exact two-profile
      output in three places, and it is not in Step 7's Files list — so the step either
      violates its own scope or lands with a red T0 suite that blocks every merge.
      Second, `render_gate_profiles_block` has a second consumer: the `/aid-init`
      existing-project upgrade path appends its output verbatim to a PM's hand-authored
      `execution.yaml` whose `gates:` mapping the composer never wrote, and
      `aid-run-gates.sh` refuses a profile naming an undefined gate before any gate
      runs. The plan's own Constraint forbids editing `commands/aid-init.md`, so the
      step cannot repair the consumer it changes. Third, Step 7's Objective ("A project
      initialised by `/aid-init` reaches `plan-finalize`") is only true for fresh inits:
      `append_gate_profiles_block` is a pure append guarded by
      `execution_yaml_has_gate_profiles`, so an existing two-profile consumer stays
      broken.
    evidence: >
      Confirmed by me: `test-aid-init.bats:2` `# aid-tier: t0`; assertions at `:99-102`
      (`gate_profile_defaults.step == "targeted"`, `.epic == "full"`), `:108-111`
      (`gate_profiles.targeted.include | join(",") == "ts_test,targeted_tests"`),
      `:207-211` (the same on the upgrade path). Step 7 Files list (plan lines 261-263)
      names only `lib/aid-init-execution-yaml.sh` and the new suite.
      Second caller: `commands/aid-init.md:157,160`; append is unvalidated
      (`lib/aid-init-execution-yaml.sh:299-314`); refusal `aid-run-gates.sh:1583,1596-1601`.
      Contradicted plan quote (line 274): "An existing project re-running init — the
      additive-upgrade contract is unchanged."
    required_change: >
      Add `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` to Step 7's
      Files list with the new expected profile set stated, and an AC that its three
      assertion sites are updated rather than deleted. Narrow the Objective to fresh
      inits. State explicitly that the upgrade path keeps its current shape until P080
      releases `commands/aid-init.md` — do not leave it implicitly changed.

  - ref: AB-6
    lenses: [authority_runtime_matrix, L1]
    severity: high
    summary: >
      Step 5 ships a hard runner refusal with no ordering or migration statement, and
      the only exposure it declares is "a consumer project whose config predates this
      change". That misses this repo's own live worktree: `.aid-worktrees/plan-P080`
      carries its own tracked copy of `execution.yaml` still holding the command-less
      `plan_diff` in the same five profiles. Once the refusal reaches a runner P080's
      tree executes, P080's gate run hard-fails on a config it can only repair by
      merging main. A CHANGELOG line is not a migration.
    evidence: >
      Confirmed by me: `git -C .aid-worktrees/plan-P080 ls-files .aid-o/config/execution.yaml`
      returns the file (tracked in that checkout); `diff` against the main copy → identical;
      the `plan_diff` block at `:223-231` has no `command:` and still carries the "P038+"
      note. Plan quote (line 211): "A consumer project whose config predates this change
      — the refusal fires on their first run…".
    required_change: >
      Step 5 states the ordering explicitly: the config repair merges to main before the
      refusal ships, and live worktrees refresh from main as a named obligation of the
      step. Alternatively gate the refusal behind a config-generation key. Also state
      which checkout AC6 is evaluated in — as written it can read PASS in the main
      checkout and FAIL in the tree that actually runs the gate.

  - ref: AB-7
    lenses: [L2, L3]
    severity: medium
    summary: >
      Step 5's stated justification rests on a fact the repo disproves in one command.
      The plan says `.aid-o/` is gitignored so "there is no history to say when the
      command disappeared — which is precisely why the runner-side refusal matters more
      than the config fix". `.aid-o/config/execution.yaml` is force-added and tracked
      with 16 commits. And the history says something different from the plan: the
      command was NEVER present in the tracked window, so this is a first-time addition,
      not the "pure regression in the self-host config" the step calls it. That wording
      is load-bearing for the exemption-note rewrite and for the CHANGELOG framing of a
      breaking configuration check.
    evidence: >
      Confirmed by me: `git ls-files .aid-o/config/` → `counter.yaml`, `execution.yaml`,
      `test-catalog.yaml`; `git log --oneline -- .aid-o/config/execution.yaml | wc -l` → 16;
      `git log -S'aid-plan-diff' -- .aid-o/config/execution.yaml` → no output.
      (`.aid-o/config/project.yaml` genuinely is untracked, so Step 3's separate
      fallback premise holds.) Plan quotes: lines 203 and 205.
    required_change: >
      Reword Step 5's Architecture Context to: tracked since 2026-08-04; `git log -S`
      over that window shows the command was never present, so this is an addition, not
      a restoration. Correct the same false claim embedded in the config file's own
      `plan_diff` note while the step is in there. Also correct "four merge-path
      profiles" to five and name `bats_all_quarantine`.

  - ref: AB-8
    lenses: [idempotency_matrix]
    severity: high
    summary: >
      Step 3's fix, applied exactly as the plan describes it, produces an array that
      double-counts and an AC that cannot be satisfied. The `.version`, `.metadata.version`
      and `.plugins[0].version` branches all edit the same `marketplace.json`, and
      `.version` already appends to `UPDATED[]` — so adding the other two yields multiple
      entries for one file. The lens reproduced it in a clone with the fix simulated:
      "Updated 6 files total" for five distinct files, and a rollback line naming
      `marketplace.json` twice. Step 3's AC2 ("the printed count equals the number of
      files the rollback restores") is false for a second, independent reason the plan
      never mentions: `_release_rollback_updated` deliberately skips any path that was
      already dirty when the run started, so the restored set is a strict subset of
      `UPDATED[]` — and the legacy entry point has no clean-tree precondition, so a
      pre-dirty version file keeps its bump after a "successful" rollback.
    evidence: >
      Confirmed by me from code: `aid-release.sh:643-663` — `.version` branch appends
      `UPDATED+=("$jf")`, `.metadata.version` branch (`# Don't double-add`) and
      `.plugins[0].version` branch do not, all three operating on the same `$jf`;
      `:785` `grep -qxF -- "$rel" <<<"$_RELEASE_PREDIRTY" && continue` with its rationale
      documented at `:773-774`; `:680` `echo "Updated ${#UPDATED[@]} files total."`.
      Lens reproduction commands and outputs recorded in
      `c0-lens-idempotency_matrix.md` F1/F2. Plan quote (line 135) and AC (line 155).
    required_change: >
      Step 3 states whether `N` counts files or edits and de-duplicates `UPDATED[]`
      (`sort -u`) before the count, before the `git add` loop at `:1048-1053`, and
      before the rollback. It states the pre-dirty exclusion explicitly and re-words
      AC2 to "the printed count equals the number of distinct files this run edited,
      and every one not already dirty is restored". Step 3 must also name the staging
      consumers (`:823`, `:1049-1053`) and declare that the prepare commit now contains
      `marketplace.json` and the plugin README — that is an undeclared change to the
      frozen review candidate.

  - ref: AB-9
    lenses: [L2, L3, authority_runtime_matrix, planned_call_feasibility]
    severity: medium
    summary: >
      The plan's Constraints commit two enforcements to be registered in the enforcement
      registry "in the same commit that adds them", but no step's Files list names the
      registry — the edit has no declared home and falls outside every step's
      `allowed_paths`. The path CLAUDE.md names does not exist; the live registry is
      `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`, which is also the
      one file P080's worktree is actually modifying. So the plan's P080 constraint
      protects two files P080 never touches (`commands/aid-init.md`,
      `defaults/templates/`) and leaves the single real collision unguarded. The
      constraint also names the wrong steps: Step 10 adds no refusal; Steps 6 and 8 do.
    evidence: >
      Confirmed by me: `docs/plans/AID-audit-2026-06/enforcement-registry.yaml` does not
      exist; `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` and
      `docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml` do.
      `git -C .aid-worktrees/plan-P080 diff --name-only main...HEAD` →
      `commands/aid-help.md`, `defaults/enforcement-registry.yaml`, `defaults/help-index.yaml`,
      `lib/aid-help-index.sh`, `test-help-index-coverage.bats`,
      `test-enforcement-registry-cites.sh`, `test-enforcement-registry-test-audit.sh`,
      `test-skill-lint.sh` — `commands/aid-init.md` and `defaults/templates/` are absent.
      Plan quotes: lines 45, 476, 479.
    required_change: >
      Name `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` in the Files
      list of every step that adds a refusal (5, 6, 8), fix the step numbers in the
      Constraint, and rewrite the P080 constraint to guard the registry and its two
      cite-tests instead of the two files P080 does not touch.

  - ref: AB-10
    lenses: [idempotency_matrix, L2, planned_call_feasibility]
    severity: medium
    summary: >
      Step 10 starts on a half-annotated file and has no rule for it. 32 of the 118
      status lines in the committed backlog already carry a `verified 2026-08-11`
      verdict — and they say "against v2.82.0" while the plan's Context says the
      verification ran against v2.83.1. The step's own test ("every entry carries a
      verdict line with a date; no entry carries two contradictory framings") passes an
      entry that ends up with two non-contradictory verdict lines from two anchors, so
      the test cannot detect the failure it needs to detect.
    evidence: >
      Confirmed by me: `git show HEAD:docs/plans/2026-06-29-BACKLOG.md | grep -c
      'verified 2026-08-11'` → 32; total `Status:` lines → 118. Plan line 18 says the
      verification ran "against `main` at v2.83.1"; the committed verdict lines say
      v2.82.0. Plan test spec at line 361; Edge Cases at lines 369-371.
    required_change: >
      Step 10 states the rule — a verdict line is replaced in place, keyed on the entry
      id, never appended — and its suite asserts AT MOST ONE verdict line per entry.
      Resolve the v2.82.0 / v2.83.1 anchor discrepancy in the same step. Declare the
      tier `t1`, not `t0`: a per-entry sweep over 46 entries in a 4,050-line file has no
      measurement behind a sub-2s claim, and `tier_lint` is `required: true` in every
      profile — the first `--timing` run above the ceiling turns a required gate red.
      Also name the "status extractor" the AC means; the only consumer found is
      `test-deferred-work-registration.bats:123`, whose `^#+ .*IMP-nnn` heading grep
      breaks if a deleted framing takes a heading with it.

rejected_blockers:

  - ref: "authority_runtime_matrix B1 — Step 5's config fix has no owning checkout, is never committed and never merges anywhere"
    rejection_reason: >
      REFUTED on its central premise. `.aid-o/config/execution.yaml` is force-added and
      tracked (`git ls-files .aid-o/config/` lists it; 16 commits). The edit IS committed,
      DOES merge, and DOES reach other checkouts by the ordinary route. The worktree copy
      is a tracked file on another branch, not an unreachable snapshot. The surviving,
      genuine half of this finding — that the refusal can fire in a worktree before that
      merge happens — is accepted as AB-6.

  - ref: "L3 BLOCKER-1 sub-claim 3 — today's fallback `sed -i \"s/v$CURRENT/v$NEW_VERSION/g\"` does fix README.md:3, and Step 4 removes the only mechanism that currently would"
    rejection_reason: >
      REFUTED. The fallback is guarded by `grep -q "v$CURRENT"` and substitutes
      `v$CURRENT` (= v2.83.1). `README.md:3` reads v2.69.0, so the fallback does not
      match it either and never has. No mechanism in the tree currently updates line 3.
      The blocker's core — that line 3's freeze is a config-path defect Step 4 does not
      touch — stands, and is accepted as AB-2.

  - ref: "L1-4 / reuse_compat F5 — Step 6's third outcome has no sink; five callers collapse it to 'disabled'"
    rejection_reason: >
      Not a blocker. Collapsing an unreadable toggle to "disabled" at the callers IS the
      fail-closed behaviour Step 6 exists to produce; the step's value is that
      `enabled: false` stops resolving to enabled, and that is unaffected. The
      missing-file default the lens worries about is already pinned by the step's own
      Edge Case ("Toggle absent entirely — the documented default applies, unchanged,
      and is asserted"). Kept as an advisory note below.

  - ref: "L1-6 — Step 7's Objective covers all consumers but only fresh inits are repaired"
    rejection_reason: >
      Duplicate of the third leg of AB-5; merged there rather than counted twice.

  - ref: "L2 medium — Steps 3 and 4 overlap on the README loop"
    rejection_reason: >
      The lens itself concludes this is not a blocker: the dependency is declared in both
      directions and the generated graph carries exactly that edge. Its useful residue
      (Step 4 has no AC pinning the `UPDATED[]` invariant Step 3 establishes) is folded
      into AB-8's required change.

  - ref: "planned_call_feasibility 2 — Step 7's test calls `gate_profile_max`, which cannot see a composed table"
    rejection_reason: >
      Correct as an observation but not a stop-rule blocker: it makes one named test
      assertion vacuous, not the step infeasible. Kept as an advisory below.

advisory_findings_worth_keeping:

  - ref: "L1-3 — Step 1 calls the flat gates_report.json a 'legacy fallback'; it is a current writer"
    summary: >
      Confirmed first-hand: `aid-plan-fsm.sh:4554` writes the flat path for every
      plan-final gates run and `aid-plan-close-check.sh:834` reads it. Two live
      conventions exist (EPIC → `gates/`, plan-final → flat). Step 1's fix is correct
      and the two paths do not meet at this precondition, but the "legacy" label invites
      a future reader to delete a live writer's only sink. Restate it as permanent.

  - ref: "dep_api_grounding F1 — Step 6's 'POSIX-portable' fix cannot be validated on this machine"
    summary: >
      `\s`/`\b`/`\d` are GNU extensions that pass here only because GNU grep 3.8 is
      installed and there is no second implementation on the box — this is exactly the
      mistake P082's review caught. Step 6 should name POSIX bracket classes or bash
      `[[ =~ ]]`, forbid backslash shorthand, and have its suite assert the pattern
      contains none.

  - ref: "dep_api_grounding F2 — Step 2's extractor runs on mawk, not gawk"
    summary: >
      `awk` here is mawk 1.3.4; gawk is not installed. Regex intervals `{n,m}` and `\s`
      silently do not work. An "indented continuation" matcher written as
      `/^[[:space:]]{1,}/` reads correct and matches nothing. State the constraint in
      the step.

  - ref: "reuse_compat F2 — Step 4 would add a fourth declaration of the version-file registry"
    summary: >
      `defaults/orchestration.yaml:64-83` already ships a tracked `release.version_files[]`
      with path + pattern + replacement for both READMEs, and I confirmed nothing reads
      it (`grep -rn version_files plugins/aid-orchestrator/scripts` → no hits). A third
      copy lives in `.aid-o/config/policies/release-policy.yaml`, and CLAUDE.md points at
      a `defaults/policies/release-policy.yaml` that does not exist. Whatever Step 4 does,
      it should not become a fourth source of the same truth.

  - ref: "L1-7 — Step 2's rule is undefined for a flush-left non-bullet line"
    summary: >
      Real plans put prose and fenced blocks inside step AC sections. State that a
      flush-left non-bullet terminates the criterion (consistent with the step's own
      "resolve toward under-joining") and pin it in the suite.

  - ref: "reuse_compat F4 — a third AC parser exists in aid-plan-diff.sh with the same truncation"
    summary: >
      Step 2's "one shared extractor" covers two of three parsers; Step 5 re-arms the
      third, which truncates the same way over the plan-level section. Scope the claim
      explicitly rather than implying the divergence is closed.

  - ref: "idempotency F6 / dep_api F4 — Step 8's read-compat premise"
    summary: >
      The sequential write path carries `*_by_context` forward
      (`aid-gate-runtime-baseline.sh:435-444`), so emitting the fields empty wipes a
      legacy file on the first ordinary gate run. Also the plan's "empty on every entry"
      is wrong: 4 of 13 entries carry `{}` and 9 carry no such key. See the step-shape
      judgment below — the cheap answer is to stop pretending to preserve it.

  - ref: "planned_call_feasibility 2 and 6 — Step 7's vacuous assertion, Step 9's line range"
    summary: >
      `gate_profile_max` reads a static rank table and returns `release` on any repo, so
      that assertion passes vacuously; the function that reads the composed table is
      `_pfsm_profile_include`. Step 9's cited `~440-465` is the entry-assembly tail; the
      presence probe is `:385-397`.

  - ref: "L2 medium + planned_call 5 — two stale measurements in a plan whose thesis is that stale facts killed P082"
    summary: >
      Line 205 says `aid-plan-diff.sh` "exits 0" (it exits 1, measured twice
      independently and once by me). Line 334 says the provisional graph has "11 steps,
      2 edges" (it has 10 and 1 — the plan has ten steps and one declared dependency).
      Neither changes a conclusion, both should be corrected on principle.

  - ref: "idempotency F7/F8 — no trap around the release update window; PID-named temp file"
    summary: >
      `aid-release.sh` has no `trap` at all, and the config path appends to
      `/tmp/aid-release-updated-$$`, read back and removed only if the reader is reached.
      An interrupted run strands a half-applied bump that the next `prepare-plan` refuses
      to resume. Step 3 is the natural home for `mktemp` + trap, or for an explicit
      "interrupt-resume is out of scope" sentence.

## Plan-level judgment: which steps should shrink or go

The PM's standard — repair the pipeline we actually run, only where the benefit is
demonstrable, prefer deleting machinery to adding it — is met by Steps 1, 2, 3, 5
(once AB-1 is applied), 6 and 10. It is NOT met by three steps as written, and in
each case the correct move is to make the step smaller, not to repair it:

- **Step 9 — drop the production half.** Its own Objective offers two ways to satisfy
  itself, and the cheap one (delete the false claim from the prompt) is a two-line edit
  that touches nothing. The expensive one adds a second writer to a single-writer
  provenance seal (AB-4) and needs an `rc` guard, a stdout redirect and a new test to be
  safe. Adding a writer to a staleness seal in order to make a prompt sentence true is
  the plan's fix being worse than the defect. Keep the prompt correction; drop the rest.

- **Step 4 — drop the anchored structure-discovering rewrite; keep a two-line repair.**
  The observed symptom (README.md:3 frozen at v2.69.0) is a one-character escaping bug
  in a config pattern plus a stranded token that needs a one-time correction (AB-2). The
  step instead proposes a new anchor-discovery mechanism in the fallback — a fourth
  declaration of a registry that already exists twice, tracked and unread. Fix the BRE,
  repair line 3, and if the fallback's blunt `s/v$CURRENT/v$NEW/g` is genuinely a risk,
  say so as a separate, later item. As written the step builds machinery and still
  leaves line 3 stale.

- **Step 8 — drop the read-compatibility apparatus, keep the deletion.** The step's own
  Implementation Detail says to "budget the effort on that test, not on the deletion",
  for data that no consumer outside the library reads, that 9 of 13 live entries do not
  even have, and that the write path would wipe on the first gate run anyway. That is
  machinery preserved for a hypothetical file. Delete the branches, drop the fields,
  state the loss in the CHANGELOG, and let the refusal be the whole compatibility story.

Steps 5 and 7 stay, but only in their shrunken form: Step 5 as `command:` +
`required: false` + the runner refusal (the config edit is the small part; the refusal
is the durable part), and Step 7 scoped to fresh inits with the T0 suite in its Files
list and the upgrade path explicitly left alone until P080 releases `aid-init.md`.

One structural note. Six of the ten accepted blockers are Files-list or wording
amendments, not design failures — the diagnostic core of this plan is sound, and every
defect premise I opened first-hand held up. That is the opposite of P082 and it is worth
saying plainly. But three of the ten (AB-1, AB-3, AB-5) would each stop this plan from
completing itself on the merge path, so the revision is not optional.
