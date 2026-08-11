# C0 lens: idempotency_matrix — P080 (observe, advisory)

_generated_by: aid-orchestrator:verifier@c0-lens-idempotency_matrix
_generated_at: 2026-08-11T04:27:52Z
Reviewed-Head: 6154ebd714cc69ffa4dd222542cf1e820e078ab8

stop_rule_blockers:
  - id: C0-IDEM-1
    step: 16
    claim: "Step 16's release work is a hand-edited version bump with no idempotency guard and no AC that can see a double-bump; a re-run (fix loop, crash after the CHANGELOG edit, re-dispatch) bumps a second time and every AC still passes. This is the exact residual P079 carried for aid-release.sh."
    evidence: "P080 Step 16 Files list edits CHANGELOG.md + plugins/.../CHANGELOG.md + marketplace.json + plugin.json + both READMEs by hand; Implementation Detail says 'version chosen at implementation time from the then-current head', Error Handling says 're-read the current version and bump from it; never hardcode' — both instructions make a second run bump AGAIN from the already-bumped head. Step 16 never names scripts/aid-release.sh or `prepare-plan` (grep over the plan: zero hits), so the shipped no-double-bump guard (defaults/enforcement-registry.yaml:257 `release_changelog_paths`, test scripts/tests/bats/test-aid-release.bats) is out of the loop. ACs are 'all 8 version locations agree' + 'both CHANGELOGs byte-identical' — both true of a double-bumped tree."
  - id: C0-IDEM-2
    step: "4, 16"
    claim: "Registry rows are appended, never keyed-upserted, and nothing in the repo or in P080 asserts row-id uniqueness — a re-run of Step 4 or Step 16 duplicates enforcement rows and the plan's own ACs pass on the duplicated file."
    evidence: "defaults/enforcement-registry.yaml is a flat `- {id: ...}` list; `scripts/aid-registry-ttl-guard.sh` has no uniqueness/duplicate check (grep 'unique|duplicate' → 0 hits) and no other test asserts it. Step 4 AC is `grep -c 'aid-research'` == 0 (blind to duplicates) plus the new cite test, which validates path existence per row — a duplicated row's cite exists, so it passes. Step 16 AC is 'registry totals match the recompute command's output', and the totals comment (defaults/enforcement-registry.yaml:50-51 `enforcements: 423  # recompute: yq '.enforcements | length'`) is itself recomputed in the same step, so it always agrees with whatever count duplication produced."

matrix:
  - step: 1
    mutation: "create defaults/help-index.yaml (13 surface rows)"
    rerun_trigger: "fix loop after Step 2 fails; re-dispatch"
    second_run_result: "full-file rewrite → identical; if the implementer appends instead of rewriting, rows duplicate"
    detected_by_ac: yes  # AC `yq '.surfaces | length'` == 13 and the Step 2 uniqueness assertion both catch duplication
  - step: 2
    mutation: "create bats suite + scripts/lib/aid-help-index.sh"
    rerun_trigger: "fix loop"
    second_run_result: "file create/overwrite — byte-stable"
    detected_by_ac: n/a
  - step: 3
    mutation: "full rewrite of commands/aid-help.md + flip 4 index rows"
    rerun_trigger: "CP2 fix loop; P076 rebase retry"
    second_run_result: "rewrite is replace-semantics → stable; a partial second pass that re-adds topic sections is caught"
    detected_by_ac: yes  # `grep -c '^### Topic:'` == router row count catches duplicated sections; coverage test catches missing ones
  - step: 4
    mutation: "repair 3 aid-research rows + refresh init_idempotency cite + APPEND the help_index_coverage row"
    rerun_trigger: "fix loop after the cite test fails; crash between the repair edit and the append"
    second_run_result: "repairs are idempotent (search/replace, second run finds nothing to fix); the APPEND duplicates the help_index_coverage row"
    detected_by_ac: no  # see C0-IDEM-2: cite test validates paths per-row, `grep -c aid-research` is unaffected by duplicates, no id-uniqueness assertion anywhere
  - step: 5
    mutation: "prose edits in aid-init.md / aid-setup.md / README.md + fill help-index `writes:`"
    rerun_trigger: "docs-review fix loop; partial-application after a mid-step abort"
    second_run_result: "removals ('Merges the old', footer move) idempotent; the ADDITIVE carve-out sentences (4 sites × 2 files), the roots paragraph and the README rows duplicate on a re-run"
    detected_by_ac: partial  # `grep -c '11 items'` == 1 catches the count sentence duplicating, but the carve-out/roots/README ACs are existence greps (`contains lib/aid-roots.sh at least once`, 'has a carve-out sentence') that pass with 2-3 copies
  - step: 6
    mutation: "add active_preset to init's template block; replace preset vocabulary in 4 surfaces"
    rerun_trigger: "fix loop"
    second_run_result: "a second insert of `active_preset:` into the same template block yields a duplicate YAML key in a shipped template"
    detected_by_ac: no  # AC is 'the init template block contains active_preset:' (presence), not count; no YAML-lint of the doc's fenced template block exists
  - step: 7
    mutation: "create scripts/aid-config-summary.sh (read-only) + bats + 2 wiring edits"
    rerun_trigger: "fix loop"
    second_run_result: "script re-created identically; the two wiring lines in aid-init.md/aid-setup.md can duplicate"
    detected_by_ac: partial  # `grep -rn 'aid-config-summary.sh'` shows both wiring points but passes with duplicates; the read-only AC is a grep pattern with real gaps (see C0-IDEM-F4)
  - step: 8
    mutation: "create test-init-idempotency.sh; add a sentence to aid-init.md; flip the registry row to ALIGNED + add `test:`"
    rerun_trigger: "fix loop; harness authored against a fixture that drifted"
    second_run_result: "harness re-created; registry row edit is an upsert on an existing row → idempotent; the aid-init.md sentence can duplicate"
    detected_by_ac: no  # ACs are about the harness's own behavior, none counts the added sentence
  - step: 9
    mutation: "create skills/communication.md + wiring test"
    rerun_trigger: "fix loop"
    second_run_result: "file create/overwrite → stable"
    detected_by_ac: yes  # the wiring test's 'exactly one file may define `Potřebuji tvoje rozhodnutí:`' catches a stray second definition file
  - step: 10
    mutation: "create aid-artifact-render.sh + artifact-outcome.html + golden bats"
    rerun_trigger: "fix loop"
    second_run_result: "files re-created; RENDERER OUTPUT is not declared deterministic — the vendored ecosystem masthead carries a timestamp slot, so two renders of the same facts differ"
    detected_by_ac: no  # no AC or Implementation Detail pins a clock (no SOURCE_DATE_EPOCH / injected `generated_at` fact); Step 15 nonetheless declares 'byte-golden for the artifact block ORDER check'
  - step: 11
    mutation: "create gate renderer + write <run_dir>/gate-outcome-artifact.html + publish an Artifact page + 2 wiring edits"
    rerun_trigger: "gate fix loop → second GATES attempt in the same run"
    second_run_result: "the artifact BODY file is overwritten in place (first attempt's evidence body lost); the PUBLISHED page has no pinned identity — a retry in a new session mints a second URL"
    detected_by_ac: no  # no AC or step text records/reuses the artifact URL, and no attempt/sequence qualifier in the filename
  - step: 12
    mutation: "create plan-close renderer + <out_dir>/plan-close-artifact.html + publish + 2 wiring edits"
    rerun_trigger: "PM re-runs the plan-close boundary after a deferred decision"
    second_run_result: "same as Step 11 — body overwritten, second publication mints a second page unless the URL was carried over"
    detected_by_ac: no
  - step: 13
    mutation: "append `Plan Step N of T` at additional aid-fsm.sh human seams; collapse 4 doc copies to 1 + 3 references"
    rerun_trigger: "post-P076 rebase retry; fix loop"
    second_run_result: "a second append at an already-edited echo site double-renders the suffix; the doc collapse is idempotent"
    detected_by_ac: partial  # the doc side is counted (`grep -c` = 1 definition + 3 references), the aid-fsm.sh side is asserted by presence of the wording only
  - step: 14
    mutation: "add communication.md reference lines to ~10 surfaces; reshape DONE-review/ESCALATION blocks; fill final_turn"
    rerun_trigger: "CP2/CP3 fix loop (this step is L and touches the most files → most likely to be partially applied)"
    second_run_result: "reference lines duplicate; a re-applied block reshape can leave two card blocks if the first pass matched a drifted anchor"
    detected_by_ac: no  # test-communication-wiring.sh asserts 'contains the literal reference' (presence) and absence of superseded fragments; both pass with duplicated reference lines and with two card blocks
  - step: 15
    mutation: "create integration harness + checked-in fixtures under scripts/tests/fixtures/handoff/"
    rerun_trigger: "fix loop; fixture regeneration after a renderer wording change"
    second_run_result: "hand-authored fixtures are stable; REGENERATED goldens inherit Step 10's un-pinned timestamp, so a golden captured at T1 fails at T2"
    detected_by_ac: no  # 'goldens assert structure not bytes (except block order)' is the mitigation, but the byte-golden block-order carve-out is exactly where a timestamped masthead lands
  - step: 16
    mutation: "docs sections + 6 registry rows + cross-repo Docusaurus page + 2 CHANGELOG entries + 8-location version bump + commit/tag/release"
    rerun_trigger: "any failure after the CHANGELOG edit (cross-repo write refused, tag exists, push rejected) → step re-dispatch"
    second_run_result: "registry rows duplicate (C0-IDEM-2); CHANGELOG gains a second entry or a second version header; version double-bumps (C0-IDEM-1); `git tag` and `gh release create` fail loudly (the only self-protecting mutations in the step)"
    detected_by_ac: no  # all four ACs (8 locations agree / CHANGELOGs byte-identical / docs page exists / totals recomputed) are satisfied by the double-applied state

findings:
  - id: C0-IDEM-F1
    severity: high
    step: 16
    finding: "Release sub-step is non-idempotent in three independent ways (version bump, CHANGELOG entry, registry row append) and its ACs are all existence/agreement checks that a double-applied tree satisfies."
    evidence: "Plan Step 16 Files + Implementation Detail + Acceptance Criteria (plan lines 552-583); no reference to scripts/aid-release.sh anywhere in the plan; the shipped guard for exactly this class is registry row `release_changelog_paths` (defaults/enforcement-registry.yaml:257) with test scripts/tests/bats/test-aid-release.bats."
    recommendation: "Either route the bump through `aid-release.sh` (so the existing no-double-bump logic applies) or add a precondition to Step 16: 'if the CHANGELOG's top header already equals the target version, the bump is already applied — verify and stop'. Add an AC that the CHANGELOG contains exactly one `## [<new version>]` header and that `git diff` of the version files against the pre-step SHA shows exactly one bump."
  - id: C0-IDEM-F2
    severity: high
    step: "4, 16"
    finding: "No row-id uniqueness invariant on the enforcement registry — the plan adds 7 rows across two steps by append, and nothing detects a duplicate."
    evidence: "defaults/enforcement-registry.yaml flat list; aid-registry-ttl-guard.sh contains no uniqueness check; Step 4's new cite test is per-row path validation; totals are recomputed in the same step that duplicates."
    recommendation: "Add one assertion to Step 4's test-enforcement-registry-cites.sh: `yq '.enforcements[].id' | sort | uniq -d` must be empty. Costs three lines, converts every registry append in this plan (and every future one) from silently duplicating to loudly failing."
  - id: C0-IDEM-F3
    severity: high
    step: 8
    finding: "Step 8's 'zero byte changes outside declared exceptions' is not testable as written: the only declared exception (`work/active.md`) is never produced by the scripted substrate the harness replays, while the substrate's real nondeterminism source — the generation timestamp in execution.yaml — is undeclared. The shipped doc also declares the exception two contradictory ways."
    evidence: "Step 8 Files: harness replays `lib/aid-init-execution-yaml.sh` compose, `lib/aid-gitignore-backfill.sh`, hook install, defaults copy, 'asserting only the declared exceptions may change (work/active.md index rewrite)'. But active.md is lifecycle-rendered, not written by any of those libs (commands/aid-init.md:594-597 says so explicitly: 'exception owned by the lifecycle, not by init'). Meanwhile scripts/lib/aid-init-execution-yaml.sh:336-353 emits `# AUTO-GENERATED by aid-init at ${now_iso}` from `date -u`, so any path that re-composes (fresh-create branch, or a fixture whose execution.yaml was removed between replays) diverges on the header line alone. And commands/aid-init.md:610 states `[EXISTS] work/active.md — keeping existing (never overwrite)`, contradicting the exception at :594 — so 'declared exceptions' has two conflicting declarations in the same file the harness cross-checks."
    recommendation: "Make Step 8 enumerate the exception set explicitly and in one place: (a) `work/active.md` (lifecycle-owned), (b) the execution.yaml `# AUTO-GENERATED ... at <ts>` header line — normalised out of the sha256 manifest, or the compose called with an injected timestamp. Add to Step 5 or Step 8 the reconciliation of aid-init.md:610 vs :594 so the doc declares one exception list; the harness's doc cross-check should read THAT list, not a hardcoded copy."
  - id: C0-IDEM-F4
    severity: medium
    step: 7
    finding: "The read-only contract of aid-config-summary.sh is asserted by a grep whose pattern misses the most likely way a summary renderer becomes a writer (lazy creation of a missing config)."
    evidence: "Step 7 AC3: `grep -nE '>>|>[^&]|yq -i|sed -i' scripts/aid-config-summary.sh` returns nothing. That pattern does not match `mkdir -p`, `touch`, `cp`, `install`, `tee`, or a heredoc written via a function — and Step 7's own Edge Cases describe branches ('repo with .aid-o but no config/ subdir (ancient v1)') that invite exactly such a fix. A lazily-created config file would break Step 8's byte-identity contract from the other direction."
    recommendation: "Extend the AC pattern to `mkdir|touch|cp |mv |tee|install |yq -i|sed -i|>>|>[^&]` AND add a bats case that runs the script against a read-only fixture directory (chmod a-w) asserting exit 0 and an unchanged sha256 tree manifest — behavioural proof beats a grep."
  - id: C0-IDEM-F5
    severity: medium
    step: "11, 12"
    finding: "No stable artifact identity: the plan defines the artifact BODY path but never how the published page is identified across a retry, so a fix loop or a re-run in a new session mints a second Artifact URL for the same outcome; and the body file itself is overwritten in place, destroying the previous attempt's evidence."
    evidence: "Step 11 writes `<run_dir>/gate-outcome-artifact.html`, Step 12 writes `<out_dir>/plan-close-artifact.html`; both say 'the controller publishes the artifact via the Artifact tool' with no URL capture, no `url`-reuse instruction and no attempt qualifier in the filename. Repo-wide grep for an existing convention ('artifact url', 'redeploy', 'same file path') returns nothing — there is no shipped rule to inherit. Same-file-path redeploy only preserves the URL within one conversation; a CP2/CP3 fix loop resumed in a new session has no way to target the earlier page."
    recommendation: "Two lines in Steps 11-12: (a) the renderer records the published URL next to the body (e.g. `<run_dir>/gate-outcome-artifact.url`) and the controller instruction says 'if that file exists, republish with that url so the link stays stable'; (b) either qualify the body filename with the gate attempt / boundary sequence, or state explicitly that overwriting is intended and the superseded body is not evidence."
  - id: C0-IDEM-F6
    severity: medium
    step: "10, 15"
    finding: "Renderer output determinism is never stated, while Step 15 keeps a byte-golden for the artifact block order — the vendored ecosystem masthead carries a timestamp, so the same facts render differently on the second run."
    evidence: "Step 10 vendors the ecosystem template 'masthead with eyebrow + serif title + timestamp' (plan line 361) and lists no clock injection in Implementation Detail or Error Handling; facts_json is caller-computed but no fact key for the render time is named. Step 15 Edge Cases: 'goldens assert structure ... byte-golden only for the artifact block ORDER check'."
    recommendation: "Declare the render clock as an INPUT: `facts_json.generated_at` (caller supplies; tests supply a fixed value), and add a Step 10 AC 'rendering the same facts twice produces byte-identical output'. Without it, the second CI run after midnight is a plausible flake and the golden churns on every re-record."
  - id: C0-IDEM-F7
    severity: medium
    step: "5, 6, 14"
    finding: "The prose-edit steps are additive with existence-grep ACs, so a partially-applied step that is re-dispatched leaves duplicated sentences/keys/reference lines while every AC stays green — the largest exposure is Step 14 (L effort, ~10 files, most likely to be retried)."
    evidence: "Step 5 AC: 'Both files contain the string lib/aid-roots.sh at least once; each of the four filenames has a carve-out sentence' — presence, not count. Step 6 AC: 'the init template block contains active_preset:' — a second insert yields a duplicate YAML key in a shipped template with no lint over the fenced block. Step 14 AC: test-communication-wiring.sh asserts each surface 'contains the literal reference skills/communication.md' — duplicates pass. Only Step 5's `grep -c '11 items'` == 1 is count-based."
    recommendation: "Convert the load-bearing existence greps to `grep -c ... == 1` (roots paragraph, active_preset key, communication.md reference per surface). This is the cheapest possible change — the ACs already run the grep — and it makes every one of these steps self-detecting on re-run."
  - id: C0-IDEM-F8
    severity: low
    step: 5
    finding: "The 'one authoritative count' AC can pass on a partially-applied edit: `grep -c '11 items' == 1` proves the new sentence exists once but says nothing about the two OTHER count phrasings the step exists to remove."
    evidence: "Step 5 Objective names 'three item counts' as the defect and the Files entry says the count is 'stated once in ## Files Created with the frontmatter description and ## Important referencing it without numbers'; the AC only counts the literal '11 items'. Step 8 then cross-checks 'the count sentence in aid-init.md' by grep, inheriting the same ambiguity. README.md today carries a '10-file structure' mention (Step 5 Files list, line ~110) that the AC also cannot see."
    recommendation: "Add an AC that no other item-count literal survives, e.g. `! grep -nE '10-file|6 files \\+ 5|10 items' commands/aid-init.md README.md` (final literal set fixed at implementation time from the actual three phrasings)."
  - id: C0-IDEM-F9
    severity: low
    step: 13
    finding: "The aid-fsm.sh half of the step-seam edit is asserted by presence of the `Plan Step N` wording; a re-applied append at an already-edited echo site would double-render the suffix undetected."
    evidence: "Step 13 AC: 'Extended bats suite passes; the frozen-surface case proves verify-state JSON unchanged; exactly one full Step rendering rule definition remains' — the count-based assertion covers only the four DOC copies, not the script's echo sites."
    recommendation: "Add one bats assertion per newly covered seam that the rendered line matches `Plan Step [0-9]+ of [0-9]+` exactly once (`grep -c`), not merely contains it."

confidence: high
