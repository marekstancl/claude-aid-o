# CP1-deep Adjudicator rev2 — P083

I read my own round-0 verdict, the three rev1 rechecks (L2 feasibility, L3 enforcement, C0 idempotency_matrix) and the current plan text at `3e10857` (523 lines, 10 steps, 3 EPICs). I did not re-review from scratch; I verified each grading against the rev2 text and re-derived by hand only what would change a decision. First-hand in this checkout and in a scratchpad harness: I reproduced `aid-release.sh:572-577`'s exact `SEARCH`/`REPLACE`/`sed -i "s|…|…|g"` construction over **three consecutive simulated releases** against the real `README.md:3` in all three pattern forms — the shipped escaped form never matches (line stays v2.83.1 forever), revision 1's bracket form corrupts the markdown link on release 1 and then no-ops forever, and revision 2's bare-parenthesis form tracks v2.83.1 → v2.83.2 → v2.83.3 → v2.83.4 with the link byte-intact. Revision 2's headline reversal is therefore correct, verified, not merely asserted. I read `render_gate_profiles_block` (`lib/aid-init-execution-yaml.sh:206`, `local stacks=("$@")`), both of its callers, and `compose_execution_yaml`'s emission block — which is wrapped in `{ … } > "${output_file}"` at `:417`, meaning the target file is **truncated before the renderer runs**. I read `update_changelog`'s "pre-written entry" no-op branch (`:487-489`) against its unconditional `UPDATED+=("$REPO_ROOT/CHANGELOG.md")` callers (`:518`, `:524`). I ran `aid-plan-lint.sh` (PASS — all Files entries canonical) and `aid-generation-readiness.sh` (PASS, acyclic, 10 steps / 0 edges) on rev2. I re-confirmed `.aid-o/config/execution.yaml` is tracked, that `plan_diff.command` is `NULL` in both the main checkout and the live P080 worktree, and that `gate_profile_defaults` is `null`. Shape of the verdict: **revise, narrowly**. Eight of the ten original blockers are fully discharged; AB-5 and AB-6 remain PARTIAL in exactly the shape the lens that raised them declined to call a blocker. The one rev1 finding that was fatal — the corrupting escape — is fixed and independently verified. What survives is one medium and two low findings, all of them one-sentence edits to plan prose, none of them re-opening a design. This is the last round: the three edits below need no lens re-run.

verdict: revise

revision_count: 2

accepted_blockers:

  - ref: AB-11
    lenses: [adjudicator-rev2, L3-rev1]
    severity: medium
    summary: >
      Step 7's replacement route for the upgrade path — "the ladder is derived from the
      gates present in the target `execution.yaml` discovered by the library itself when
      one exists, falling back to the stack-derived set when it does not" (plan:289) — is
      implementable without touching `commands/aid-init.md`, but only with a guard the plan
      does not state, and the obvious literal reading of "when one exists" is wrong on the
      compose path. `compose_execution_yaml` emits everything inside `{ … } > "${output_file}"`,
      so the target file is truncated to zero bytes BEFORE `render_gate_profiles_block` is
      called from inside that block. A probe keyed on file existence therefore finds an
      existing, empty file on every fresh init, derives an empty gate set, and emits a
      degenerate ladder — turning Step 7's own AC1 red. The discriminator that actually
      works, and that separates the two callers cleanly, is a **non-empty `gates:` mapping**
      in the target file: false on the compose path (truncated), true on the upgrade path
      (the PM's hand-authored config). L3-rev1 asked for "that mechanism and its guard";
      revision 2 supplied the mechanism and dropped the guard.
    evidence: >
      Read first-hand: `lib/aid-init-execution-yaml.sh:206` `render_gate_profiles_block() {
      local stacks=("$@")` — varargs of stacks, no target-file parameter, so a positional
      target argument would break `commands/aid-init.md:157`, which Step 7 may not edit.
      Callers of the renderer: `compose_execution_yaml:395` and `commands/aid-init.md:157`
      (the latter followed at `:160` by `append_gate_profiles_block .aid-o/config/execution.yaml
      "$proposed_block"`, which is where the literal cwd-relative path the library can probe
      comes from). `compose_execution_yaml:353-417` — the whole emission is `{ cat <<EOF … ;
      render_gate_profiles_block "${clean_stacks[@]:-}" ; … } > "${output_file}"`, i.e. the
      redirect truncates `${output_file}` before the first byte is written. Third indirect
      consumer not named by the plan: `aid-fsm.sh:4907` also calls `compose_execution_yaml`.
      Today's emission is the two-profile here-doc at `:258-265`.
    required_change: >
      One sentence in Step 7's replacement paragraph (plan:289): the library's discovery is
      an implicit probe of `.aid-o/config/execution.yaml` relative to cwd, and it is keyed on
      a **non-empty `gates:` mapping**, not on file existence — because `compose_execution_yaml`
      truncates the target through its `> "${output_file}"` redirect before the renderer runs,
      so the compose path always sees a zero-byte file and must take the stack-derived
      fallback. Add the corresponding assertion to `test-init-gate-profiles.bats`: a fresh
      compose run over a pre-existing zero-byte or gates-less `execution.yaml` still yields
      the full stack-derived ladder. Optionally name `aid-fsm.sh:4907` as the third caller
      that inherits the compose behaviour.

  - ref: AB-12
    lenses: [idempotency_matrix-rev1, adjudicator-rev2]
    severity: low
    summary: >
      Step 3's AC2 — "The printed count equals the number of distinct files the run edited"
      (plan:156) — is false on the pre-written-CHANGELOG flow, which is the flow a plan-final
      release actually uses, and the code responsible is outside every declared line range.
      `update_changelog` has a no-op branch that prints "Skipped: … pre-written entry" and
      edits nothing, while both of its callers append `CHANGELOG.md` to `UPDATED[]`
      unconditionally. `sort -u` does not address it: the entry is not a duplicate, it is a
      no-op still recorded. The count over-reports by one and the rollback then "restores" a
      file it never touched. Rollback correctness is unaffected (a checkout of an unmodified
      file is a no-op), so this is a wording-or-scope defect, not a behavioural one — but it
      is precisely the class of stated-vs-true mismatch this plan exists to eliminate, and
      revision 2 left the rev1 finding unanswered.
    evidence: >
      Read first-hand: `aid-release.sh:487-489` — `if [[ "$header" == "$NEW_VERSION" ]]; then
      echo "Skipped: $file (header already $NEW_VERSION — pre-written entry)"`, no edit.
      `:518` and `:524` — `update_changelog "$REPO_ROOT/CHANGELOG.md"; UPDATED+=("$REPO_ROOT/CHANGELOG.md")`
      with no conditional on either. Step 3's declared ranges are `~645-681`, `:823` and
      `~1048-1053`; `:518-529` is in none of them. The C0 idempotency lens measured the
      symptom on a successful prepare in a clone: `Updated 4 files total` while the commit
      contained 3.
    required_change: >
      Either narrow Step 3's AC2 to the flow its own test bullet exercises ("on a prepare
      aborted by a CHANGELOG validation failure, the printed count equals the number of
      distinct files the run edited"), or add `aid-release.sh:518-529` to Step 3's Files
      list and make the CHANGELOG's `UPDATED[]` entry conditional on `update_changelog`
      having edited the file. Narrowing the AC is the smaller move and is consistent with
      the plan's sieve.

  - ref: AB-13
    lenses: [adjudicator-rev2, L3-rev1]
    severity: low
    summary: >
      Two residual over-claims in Step 4, both one word or one line. (a) Its Error Handling
      (plan:180) says a no-match pattern "is not **counted** as an update", but the counting
      is the unconditional `echo "$FULL_PATH" >> /tmp/aid-release-updated-$$` at
      `aid-release.sh:589`, which is outside Step 4's declared range `~571-577`. The step's
      own AC3 (plan:194) claims only "is not printed as `Updated`", which IS deliverable in
      range — so the AC is satisfiable and the prose over-reaches past its own scope by one
      verb. This is the same shape as the rev1 blocker revision 2 just closed by restoring
      `aid-release.sh` to the Files list. (b) Step 4 states (plan:178) that teaching the
      release script to read a tracked registry "is deferred work with its own plan", but
      `## Deferred` (plan:516-523) contains no such entry — an obligation with no declared
      home, which is the AB-9 shape recurring in a smaller costume.
    evidence: >
      Read first-hand: `aid-release.sh:572-577` is the whole `regex)` branch (`SEARCH` at
      `:573`, `REPLACE` at `:574`, `sed -i` at `:575`, `echo "Updated: $FILE_PATH (regex)"`
      at `:576`) — Step 4's `~571-577` covers it exactly. The `UPDATED[]` collection for that
      loop is at `:589`, read back at `:593-597`. `## Deferred` enumerated: audit retirement,
      `grep -oP` widening, the 22 sieved entries, IMP-261/490/471/487/OBS-20260702-07,
      IMP-495, IMP-496 — no version-registry or untracked-config entry.
    required_change: >
      (a) Change "is not counted as an update" to "is not printed as `Updated`" in Step 4's
      Error Handling, matching its own AC3, or add `aid-release.sh:589` to the range and keep
      the stronger claim. (b) Add one line to `## Deferred`: teaching `aid-release.sh` to read
      one of the two tracked version-file registries instead of the untracked
      `.aid-o/config/project.yaml`, which would close both this step's shipping gap and
      Step 3's fallback premise at once.

discharged:

  - ref: AB-1
    status: DISCHARGED
    evidence: >
      Step 5 now specifies `command:` plus "an explicit `required: false` for the duration of
      this plan" (plan:206), with a dedicated paragraph (plan:216) giving the mechanism —
      `gate_profile_defaults` null, `aid-run-gates.sh:2001`, `aid-fsm.sh:2989-3002`, measured
      "exit 1, 11 of 11 absent" — and the `plan_ac_match` null→false flip declared as a
      consequence with its blocking-severity registration (plan:218). I re-confirmed
      `gate_profile_defaults` is `null` and `plan_diff.command` is `NULL` today. L2-rev1
      independently verified that no other passage implies `required: true` (the only
      `required: true` in the plan is `tier_lint`) and that the plan-final blocking half is
      mechanically real and independent of the flag (`aid-plan-fsm.sh:4530-4540`, `:4697-4701`).
      The AC-label half is discharged too: the eleven plan-level bullets use the `AC1:` colon
      form and L2/C0 both measured all eleven `plan-diff.json` rows carrying populated
      `ac_label`, where the first pass measured `""` on all eleven.

  - ref: AB-2
    status: DISCHARGED
    evidence: >
      This was NOT DISCHARGED at rev1 and is the reversal I verified most carefully myself.
      Step 4 now names all four surfaces: `aid-release.sh:~571-577` for the no-match report
      (the shipped, tracked half), `README.md:3` for the one-time reset, `.aid-o/config/project.yaml:~27-32`
      for the pattern with the untracked status declared, and a fixture-based suite. I
      reproduced `aid-release.sh:572-577` verbatim over three consecutive releases on the real
      line 3 in all three forms:
        shipped `\(`…`\)`   → no substitution at any release (frozen forever)
        rev1's `[(]`…`[)]`  → r1 yields `[Claude Code][(]https://…[)]` at v2.83.2, r2 and r3 no-op (corrupted AND re-frozen)
        rev2's bare parens  → v2.83.2 → v2.83.3 → v2.83.4, markdown link byte-identical at every step
      The plan's cited cause (`aid-release.sh:573-575` derives SEARCH and REPLACE from one
      pattern string, so any escape that does not collapse to itself is emitted verbatim) is
      exactly what I observed. The Test bullet now pins the corrupting form as a negative
      assertion rather than trusting prose, and asserts two consecutive releases — enough to
      expose the bracket trap, which a single-release test cannot.

  - ref: AB-3
    status: DISCHARGED
    evidence: >
      `**AID Role:** docs-writer` at plan:408, unchanged by revision 2. L2-rev1 drove the plan
      through all three `aid-plan-to-epic.sh` phases and all three `aid-epic-to-json.sh`
      conversions in an isolated clone: rc=0 six times, EPIC 3 rendering `step_3_docs_writer`.
      The exact command that previously returned `{"error": "Invalid role 'docs'…"}` now
      returns a `plan.json` path. I re-ran the two upstream gates on rev2 in this checkout:
      `aid-plan-lint.sh` → "PASS — all Files entries are canonical"; `aid-generation-readiness.sh`
      → "READINESS: PASS … graph: acyclic", 10 steps / 0 edges.

  - ref: AB-4
    status: DISCHARGED
    evidence: >
      Step 9's Files list (plan:348-349) names only `defaults/prompts/c0-plan-review-prompt-v1.md`
      and the new suite — no `--write-provisional` call, no edit to `lib/aid-c0-plan-review.sh`.
      The C0 idempotency lens re-enumerated the writer set at rev1 and found it unchanged:
      one production writer (`aid-plan-to-epic.sh:136`), one seal consumer
      (`aid-generation-finalize.sh:112-119`), the readiness flag parser, the C0 probe at
      `lib/aid-c0-plan-review.sh:385`, and fixtures. The `set -euo pipefail` and
      stdout-channel hazards disappear with the call. AC2 ("still exactly one writer") is a
      real grep-checkable guard against the reverted design, and AC1 is currently red against
      the shipped prompt (`:32` "the pre-generation authority"), so it is a genuine assertion.
      Revision 2's Implementation Detail states the reversal and its reasoning explicitly.

  - ref: AB-5
    status: PARTIAL
    evidence: >
      The mechanical half is discharged and I re-checked it: `test-aid-init.bats` is in Step 7's
      Files list at plan:280 with the three assertion sites named (`~100-111`, `~208-212`),
      AC3 pins it green, and the suite's `# aid-tier: t0` header is untouched so CI routing is
      unchanged. The escape hatch is materially improved — rev1's "stop and report" is replaced
      by a named route (plan:289) and by an explicit statement that "stop and report" is NOT an
      acceptable landing, which is the right call given the two paths share one derivation. It
      remains PARTIAL because the route's guard is unstated and its literal reading is wrong
      against `compose_execution_yaml`'s truncating redirect; that residue is carried as AB-11
      rather than counted twice here. The step's own Objective is still worded as "a project
      initialised by `/aid-init`" without the fresh-init narrowing my round-0 required_change
      asked for, but the Files list, the upgrade-path paragraph and AC2 ("on both the compose
      and the upgrade path") now cover the upgrade case explicitly, which is a stronger answer
      than the narrowing would have been. No further change required beyond AB-11.

  - ref: AB-6
    status: PARTIAL
    evidence: >
      The literal required_change is met: the ordering is stated twice (plan:220 as an
      "Ordering obligation" paragraph, plan:502 as a Constraint), and AC1 (plan:235) now says
      "asserted in the checkout that runs the gate", which closes the which-checkout ambiguity.
      Judged as enforcement it is still prose, not a mechanism: both edits live in one step and
      normally one commit, so nothing can observe "config merged before refusal shipped", and
      the second half is an obligation on a session P083 cannot reach. I re-measured the
      exposure today: `.aid-worktrees/plan-P080/.aid-o/config/execution.yaml` still returns
      `NULL` for `plan_diff.command`. L3-rev1 deliberately declined to raise this to a blocker
      and I agree with its reasoning — the refusal is profile-scoped (`aid-run-gates.sh:1586`
      guards it behind `-n "$profile"`) and this repo's `gate_profile_defaults` is `null`
      (re-confirmed), so ordinary EPIC gate runs never reach it; P080's exposure is confined to
      an explicit `--profile` run, i.e. its plan-final. Recommended, not required: make the
      refusal's message name the remedy verbatim ("merge main into this worktree") so the
      failure is self-clearing, and say the two edits may not share a commit.

  - ref: AB-7
    status: DISCHARGED
    evidence: >
      Step 5's Architecture Context (plan:212) now states the true history: `.aid-o/config/execution.yaml`
      is force-added and tracked with 16 commits since 2026-08-04, `git log -S 'aid-plan-diff.sh --plan'`
      over that window returns nothing, "so the command was **never** there. This is a
      first-time addition, not a restoration", and it commits to correcting the same false
      claim embedded in the config file's own note. The profile count is corrected to five and
      all five are named including `bats_all_quarantine` and `release_quarantine`. I
      re-confirmed the file is tracked (`git ls-files .aid-o/config/` → counter.yaml,
      execution.yaml, test-catalog.yaml).

  - ref: AB-8
    status: DISCHARGED
    evidence: >
      Step 3 (plan:135) now records the file in all three previously-silent branches and
      de-duplicates `UPDATED[]` with `sort -u` before the count at `:681`, before the staging
      loop and before `_release_rollback_updated`, naming `marketplace.json`'s two version
      fields as the reason. The pre-dirty exclusion at `:785` is declared and required to be
      named in the output (plan:142), AC2 is re-worded to "the number of distinct files the
      run edited, and every one of them that was not already dirty is restored" (plan:156),
      and the staging consequence for the frozen review candidate is declared (plan:148). The
      C0 idempotency lens reproduced the corrected fix in a clone across all three cases —
      abort/rollback (`Updated 5 files total`, five distinct paths, `marketplace.json` once,
      `git status --porcelain` empty), successful staging (staged ⊆ counted, no duplicate
      `git add`), and pre-dirty (README kept its bump and stayed ` M`, exactly what the
      re-worded AC permits). Revision 2 also folds in the lens's F2: the plugin README's
      `Plugin: ` branch is included for symmetry but "the review found it does not fire on the
      current file shape; the step must report which of the two it actually observed rather
      than assuming both" (plan:148) — converting an assumption into an observation, which is
      the right disposition. The one residue the lens raised and revision 2 did not answer is
      carried as AB-12.

  - ref: AB-9
    status: DISCHARGED
    evidence: >
      `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` is now a `Modify:` bullet
      in Steps 5 (plan:208), 6 (plan:248) and 8 (plan:317) — the three steps that add a
      refusal — and L2-rev1 confirmed it appears in the generated `allowed_paths` for
      EPIC2/step_1, EPIC2/step_2 and EPIC3/step_1, not merely in prose. The Constraint
      (plan:501) is rewritten to guard the real P080 collision (the registry and its two
      cite-tests) instead of the two files P080 never touches, and states the coordination
      rule. L3-rev1 confirmed the registry is tracked, committable, self-declared canonical,
      and that its row shape matches what the three steps promise. Step numbers in the
      Constraint are corrected to 5/6/8. Residue kept advisory: no clause requires the three
      new rows to carry unique ids and resolving cites against P080's incoming T0
      `test-enforcement-registry-cites.sh`; all three cite files that exist, so it is
      satisfiable as written.

  - ref: AB-10
    status: DISCHARGED
    evidence: >
      Step 10 states the replace-in-place rule keyed on entry id with the verification winning
      over the older v2.82.0 annotations and the anchor discrepancy resolved in the same edit
      (plan:388), its suite asserts "**at most one** verdict line per entry" (plan:382), the
      tier is `t1` with the reasoning stated (plan:390), and `test-deferred-work-registration.bats:123`
      is named as the only consumer of the file's shape. The C0 lens verified convergence
      (run 1 maps {no verdict, v2.82.0 verdict} → {single v2.83.1 verdict}; run 2 is a no-op)
      against the measured current state of 32 annotations on 32 distinct headings. L3-rev1
      verified the t1 claim is safe against `aid-test-tier-lint.sh` both before and after
      measurement. Residue kept advisory: 19 entries currently carry two `**Status:**` lines
      each, so "per entry" needs an entry boundary; the heading scan the step already names is
      the obvious one and should be stated in the suite.

rejected_blockers: []

## New findings from the rev1 rechecks — disposition

- **L3-rev1 Item 1 Leg A (bracket expression corrupts the line) — DISCHARGED.** Reproduced
  first-hand in both directions over three releases; revision 2 adopts the correct fix and
  pins the corrupting form as a negative test assertion. See AB-2.
- **L2-rev1 blocker 1 (Step 4's AC3 / Error Handling / Test bullet need an `aid-release.sh`
  edit no step declares) — DISCHARGED.** `aid-release.sh (lines ~571-577)` is back in Step 4's
  Files list and I verified the range covers the whole `regex)` branch at `:572-577`.
  `aid-plan-lint.sh` passes on rev2. One-word residue carried as AB-13(a).
- **L2-rev1 blocker 2 / L3-rev1 Leg B (`project.yaml` is untracked; the fix cannot merge and
  the T1 suite cannot read it elsewhere) — DISCHARGED.** Plan:169 declares the file untracked
  and the repair workspace-only, and names the shipped protection (the no-match report). The
  Test bullet no longer says "the real row-3 pattern"; it asserts pattern shapes on fixtures,
  so the suite is runnable in any clone, worktree and CI checkout. Step 3's load-bearing
  premise (the fallback is what worktrees take) is preserved rather than invalidated, and
  plan:178 states the untracked-config root cause as deferred. Residue carried as AB-13(b).
- **C0-rev1 F8 (Architecture and Risks still asserted mechanisms rev1 deleted) — DISCHARGED,
  and I swept for this specifically as instructed.** Architecture group 3 (plan:61) now reads
  "the C0 prompt stops requiring a dependency graph the review never receives (producing it
  early was measured, then rejected on review…)" — it describes the deletion and labels the
  rejected design as rejected. The stale Risks bullet ("Step 3 and Step 4 edit the same block.
  Mitigation: explicit dependency…") is gone, replaced by a bullet about the regex whose
  search and replacement are one string (plan:513). A grep for every deleted mechanism —
  `produced earlier`, `write-provisional`, `bracket expression`, `[(]`, `discover an anchor`,
  `edit the same block`, `shared fallback fixture` — returns hits only at plan:174, :176 and
  :353, and all three are retrospective narration explicitly marked as reversed or dropped.
  Scope (plan:34-45) and Success Criteria (plan:410-417) name no deleted mechanism. Nothing in
  the prose would lead an implementer to build something the plan removed.
- **L2-rev1 medium (Step 3 lost its `**Edge Cases:**` heading) — DISCHARGED.** Ten headings
  in ten steps.
- **L3-rev1 Item 6 (CHANGELOGs unowned) — DISCHARGED.** Both CHANGELOGs are a `Modify:` bullet
  in Step 5 (plan:209), the step that promises the content. Step 8 no longer promises a
  CHANGELOG entry, so nothing is owed there.
- **C0-rev1 F3 (unconditional CHANGELOG entry in `UPDATED[]`) — NOT DISCHARGED.** Carried as
  AB-12, verified first-hand.
- **C0-rev1 F9 (Step 5 says both "runs clean" and "exit 1" four lines apart) — advisory.**
  Plan:214 now qualifies it ("runs clean against this plan, **parses its eleven criteria**")
  and plan:216 gives the measurement, so the two readings are reconcilable, but one sentence
  saying "parses cleanly; exits 1 because the suites are not built yet" would end it.
- **C0-rev1 F11 / round-0 idempotency F7-F8 (no `trap` in `aid-release.sh`; PID-named temp
  file at `:589`) — advisory, still unaddressed.** Step 3 already touches `UPDATED[]`
  bookkeeping; `mktemp` + `trap` is nearly free there, and one sentence saying interrupt-resume
  is out of scope costs nothing. Not a blocker at either round.
- **C0-rev1 F5 caveat (entry boundary for "at most one verdict line per entry") — advisory.**
  See AB-10.
- **L2-rev1 low (P080's `test-enforcement-registry-cites.sh` will meet the three new rows) —
  advisory.** See AB-9.
- **C0-rev1 F2 residue (in every worktree release the plugin README's version line is never
  bumped at all, because the fallback's `grep -q "Plugin: $CURRENT"` cannot match
  `- **Plugin:** 2.83.1`) — advisory, and worth a backlog line.** Revision 2 correctly requires
  Step 3 to report what it observes rather than assume; the underlying "a registry file is
  silently left behind on the live plan-final path" belongs with the version-registry deferral
  AB-13(b) asks for.

## Plan-level judgment against the PM's standing standard

*Fix only what repairs the pipeline we actually run, only where the benefit is demonstrable,
prefer deleting machinery to adding it.*

The plan meets it. Every step's premise that I opened first-hand across two rounds has held
up, which remains the strongest thing that can be said about it and the opposite of P082. Two
rounds of review have shrunk it in the right direction: Step 9 lost its second writer, Step 8
lost its read-compatibility apparatus, Step 4 lost an anchor-discovery mechanism that would
have been a fourth declaration of an unread registry, and Step 5's config edit is now the
small part with the runner refusal as the durable part. Nothing has been added in exchange
except three refusals inside existing checks, each with a declared registry home.

**No remaining step should be dropped.** Two observations the PM may want anyway:

- **Step 7 is the step furthest from today's pipeline** — the only one motivated by other
  projects rather than by this repo — and it is the one that has now generated a blocker in
  both rounds (AB-5, then AB-11). Its defect is real and hard (a fresh consumer aborts at
  `plan-finalize` with "profile 'release' has an empty or missing include[]"), so it earns its
  place; but if the plan has to get smaller, this is what goes first, and nothing else in the
  plan depends on it.
- **Step 4's `project.yaml` bullet is the least load-bearing third of the least load-bearing
  step.** All three of Step 4's ACs are satisfiable without it: AC1 is a fixture assertion,
  AC2 is the `README.md:3` reset, AC3 is the tracked no-match report. The config edit reaches
  one working copy and, once line 3 carries the current token, the untouched fallback
  (`grep -q "v$CURRENT"` then `sed "s/v$CURRENT/v$NEW/g"`) keeps line 3 current in every
  worktree anyway — which is where plan-final releases run. Keeping it is defensible (two
  characters, and it stops this checkout's own config from re-freezing the line); dropping it
  would cost nothing the ACs measure. Either way, say which, because right now the step reads
  as though the config edit is the fix and the report is the backstop, when mechanically it is
  the other way round.

handoff_readiness: >
  NOT READY as-is — but by three edits, not by another design round. Nothing below re-opens an
  approach, touches a Files list except by one optional line range, or needs a lens to re-verify;
  a PM or the implementing session can apply all three in about fifteen minutes, and this
  adjudication is the last gate rather than an invitation to a rev3 ceremony.
  (1) AB-11 — one sentence in Step 7 (plan:289) naming the discovery guard as a non-empty
  `gates:` mapping rather than file existence, because `compose_execution_yaml` truncates the
  target through its `> "${output_file}"` redirect before the renderer runs, plus the matching
  assertion in `test-init-gate-profiles.bats`. Without it the first implementer of Step 7
  writes an existence probe, gets an empty ladder on the compose path, and burns a debugging
  cycle rediscovering `:417`.
  (2) AB-12 — narrow Step 3's AC2 to the aborted-prepare flow its own test exercises, or add
  `aid-release.sh:518-529` to its Files list. As written the AC is false on the normal
  plan-final release flow.
  (3) AB-13 — change "not counted as an update" to "not printed as `Updated`" in Step 4's
  Error Handling so the prose matches its own AC3 and its own line range, and add the
  version-registry / untracked-config item to `## Deferred` so the obligation Step 4 asserts
  has a home.
  Everything else is advisory and can be carried into implementation: the AB-6 ordering remains
  prose rather than a mechanism (bounded, measured, and the lens that raised it declined to
  block on it), `aid-release.sh` still has no `trap`, Step 10 needs an entry boundary stated in
  its suite, and Step 5 should say "parses cleanly; exits 1 because the suites are not built
  yet" once instead of twice in two voices. With the three edits applied the plan is generation-
  ready — `aid-plan-lint.sh` and `aid-generation-readiness.sh` already pass on it at rev2, and
  L2 drove rev1 through all three generation phases and all three JSON conversions in an
  isolated clone — and can be handed to an implementer in a different session.
