# CP1-deep — C0 lens idempotency_matrix — P083

Lens question: does the plan introduce a mutation that is not idempotent — where
running it twice, or resuming after an interrupt, produces a different or
corrupted result?

Repo: `/opt/eco/projects/aid-orchestrator` @ `1d5cd04` (main, v2.83.1).
Plan: `.aid-o/plans/P083-ten-verified-defects.md` (497 lines).
All reproduction was done in `git clone --local` at
`/tmp/claude-1000/-opt-eco-projects-aid-orchestrator/50d5999a-d6f6-42c1-a512-479b5d12dbb9/scratchpad/w1/clone`.
The real repo was never mutated (read-only commands only).

stop_rule_blockers:

- **B1 — Step 3's second acceptance criterion cannot be satisfied by the fix it
  describes.** AC (plan:155): *"The printed 'Updated N files total' equals the
  number of files the rollback restores."* Two independent reasons it is false:
  (a) `_release_rollback_updated` deliberately skips any path that was already
  dirty before the run (`aid-release.sh:785`,
  `grep -qxF -- "$rel" <<<"$_RELEASE_PREDIRTY" && continue`), so the restored
  set is a strict subset of `UPDATED[]` whenever the operator had a version file
  modified — the legacy entry point (`_release_legacy_bump`, `:841`) has no
  clean-tree precondition, unlike `prepare-plan` (`:1002-1006`); (b) the
  fallback edits `marketplace.json` in two branches (`.metadata.version` at
  `:651-656`, `.plugins[0].version` at `:657-662`), so "record their file in
  `UPDATED[]` exactly once" (plan:135) per branch yields **two array entries for
  one file** — the printed count is then an array length, not a file count.
  Reproduced (see F1): with the plan's fix simulated, the run printed
  `Updated 6 files total` for **5 distinct files**, and the rollback line named
  `.claude-plugin/marketplace.json` twice. The plan does not say which number
  `Updated N files total` is supposed to be, and it never mentions
  `_RELEASE_PREDIRTY` at all.

- **B2 — Step 3's Objective ("An aborted release restores every file it
  touched", plan:132) is contradicted by an existing, deliberate control the
  plan does not acknowledge.** A version file that was dirty before the run gets
  the version edit applied and is then *not* rolled back. Reproduced (F2):
  `README.md` was left carrying `**v2.83.2** (current)` after the rollback
  reported success. Fixing `UPDATED[]` bookkeeping (all Step 3 proposes) does not
  touch this path; the step needs an explicit decision — either the pre-dirty
  exclusion stays and the Objective/AC are re-worded, or the exclusion changes
  and `_release_rollback_updated`'s documented contract at `:765-776` is revised
  in the same step.

- **B3 — Step 9 makes C0 `build-manifest` a second writer of a single-writer
  provenance artifact, and the plan names neither the existing writer nor the
  consumer that depends on it.** Plan:328 — *"`build-manifest` produces the
  provisional graph itself, by invoking `aid-generation-readiness.sh
  --write-provisional` for the plan under review."* That path is
  `<evidence>/generation/provisional-graph.json`
  (`lib/aid-c0-plan-review.sh:385`). It is already written, exactly once, by the
  generation pipeline at `aid-plan-to-epic.sh:136`, and it is read by
  `aid-generation-finalize.sh:112-121` as the **staleness seal**: `jq -e ... 
  .plan_sha256 == $sha` → `"ERROR: provisional graph is stale, malformed, or
  belongs to another plan"`, followed by a byte-equality check against the final
  graph. `aid-generation-readiness.sh:40-42` writes with `> "$out"` — an
  unconditional truncate. So any C0 review run after generation has begun
  silently re-binds that seal to the current plan bytes, and the finalize-time
  "belongs to another plan" refusal can no longer fire from a plan revision. The
  mutation is idempotent in isolation (write-then-read within one invocation,
  overwrite converges) and *destructive* in composition. Step 9's Files list
  (plan:327-330) names only `lib/aid-c0-plan-review.sh` and the prompt.

findings:

- **F1 (High, reproduced) — the count Step 3 promises to make trustworthy is a
  double-counting array length.**
  What I ran, in the clone (no `.aid-o/config/project.yaml` → fallback path, as
  Step 3 requires at plan:140):
  `git checkout -b plan/P999 && bash plugins/aid-orchestrator/scripts/aid-release.sh prepare-plan P999 --bump patch --plan-branch plan/P999`
  Unpatched result (the defect, exactly as plan:138 describes): seven `Updated:`
  lines, `Updated 4 files total`, rollback restored 4, and
  `git status --porcelain` showed ` M .claude-plugin/marketplace.json` stranded
  at `2.83.2` while `plugin.json` was back at `2.83.1`.
  Then I applied Step 3's stated fix mechanically (`UPDATED+=("$jf")` in the
  `.metadata.version` branch replacing the `# Don't double-add` comment, in the
  `.plugins[0].version` branch, and in the README `Plugin: ` branch), committed
  it, and re-ran the same command. Result: tree clean afterwards (the defect is
  genuinely fixed), but the run printed `Updated 6 files total` while touching
  five distinct files, and printed
  `Rolled back ... .claude-plugin/marketplace.json .claude-plugin/marketplace.json ...`.
  Step 3's own Edge Case (plan:145) covers only "a file listed by config **and**
  by fallback"; the duplicate that actually occurs is two fallback branches
  editing two JSON fields of one file. The step must state whether `N` counts
  files or edits, and de-duplicate `UPDATED[]` accordingly (`sort -u` before the
  count and before the `git add` loop at `:1048-1053`).

- **F2 (High, reproduced) — a pre-dirty version file keeps the bump after a
  "successful" rollback.**
  What I ran, in the same clone with the simulated Step 3 fix committed:
  `printf '\nPM local note\n' >> README.md` then
  `bash plugins/aid-orchestrator/scripts/aid-release.sh patch` (legacy entry
  point — no clean-tree precondition). Result: `Updated 6 files total`, the
  rollback listed 5 entries (4 distinct files) and did **not** list `README.md`,
  and afterwards `grep -n '2\.83\.2' README.md` returned
  `120:- **v2.83.2** (current) — ...`. So the release left one file on the new
  version and reported the rollback as complete — the same class of defect Step
  3 exists to fix, on a path Step 3 does not cover. Evidence:
  `aid-release.sh:785` (the exclusion), `:765-776` (its rationale).

- **F3 (High, reproduced) — Step 4 fixes the fallback, but README.md:3's freeze
  at v2.69.0 is a *config-path* defect, and no step in the plan repairs it.**
  Plan:171 asserts *"The config path ... already does a regex substitution for
  this repo and is not the failing path in a worktree"*, and Success Criterion 2
  (plan:388) requires *"`README.md` shows the current version after the next
  release"*. Reproduced: I copied the real (gitignored) `.aid-o/config/project.yaml`
  into the clone and ran `aid-release.sh patch`. The config path executed and
  printed `Updated: README.md (regex)` **twice**, yet `sed -n '3p' README.md`
  still read
  `**Multi-agent orchestration plugin for [Claude Code](...).** v2.69.0`.
  Cause: `project.yaml` registers the pattern
  `\*\*Multi-agent orchestration plugin for \[Claude Code\]\(...\)\.\*\* v{VERSION}`
  and `aid-release.sh:574-577` substitutes `{VERSION}` → `$CURRENT` (2.83.1) as
  the *search* string. That string is not in the file, so the `sed` is a no-op —
  and it prints "Updated" and enters `UPDATED[]` regardless. This is the purest
  non-convergent mutation in the whole area: a token substitution keyed on the
  previous version can never repair itself once it misses one release, and
  nothing detects the miss. Step 4 as scoped leaves README.md:3 at v2.69.0
  forever, so Success Criterion 2 is not met by any step in the plan.

- **F4 (High) — Step 9's third acceptance criterion is unreachable under either
  possible ordering.** Plan:330: *"a graph bound to a different plan hash is
  still refused"*, and Edge Case plan:340: *"a stale graph must never pass"*.
  Today's refusal is `lib/aid-c0-plan-review.sh:386-397`
  (`[[ "$graph_plan_sha" == "$reviewed_plan_hash" ]] || _fail "provisional plan
  graph hash does not match reviewed plan"`). If the new
  `--write-provisional` call is placed *before* that block (as plan:328's
  "before sealing the manifest" implies), the graph is always freshly bound and
  the refusal can never fire from `build-manifest`. If it is placed *after*, a
  stale graph still hard-fails and the step's whole purpose (a graph present at
  review time) is never reached on the exact plans it targets. One of AC10's
  three bullets must be re-stated against a different entry point, or the step
  must specify an explicit "refuse stale, then regenerate" order.

- **F5 (High) — Step 10 has no rule for an entry that already carries a verdict,
  and 32 of the 46 already do, at HEAD.**
  `git show HEAD:docs/plans/2026-06-29-BACKLOG.md | grep -c '(verified 2026-08-11'`
  → **32** (of 118 `**Status:**` lines). Examples: `:97`, `:629`, `:700`, `:752`
  — each already reads `**Status:** **DONE** (verified 2026-08-11 against
  v2.82.0) — ...`. So the "second pass" this lens asks about is in fact the
  *first* pass: Step 10 starts on a half-annotated file. The plan's Edge Cases
  (plan:369-371) cover "an entry with a later correction elsewhere" and "an entry
  outside the 46", but say nothing about re-annotating an entry that already has
  a dated verdict, nor whether an existing verdict is updated in place, appended
  to, or left alone. Worse, the specified test cannot detect the failure: plan:361
  asserts only *"every entry touched by the verification carries a verdict line
  with a date; no entry carries two contradictory framings"* — an entry that
  ends up with two *non*-contradictory verdict lines from two dates passes.
  A double pass over a 4050-line file is exactly the mutation that needs an
  explicit "verdict line is replaced, never appended, and is keyed on the entry
  id" rule plus a test asserting **at most one** verdict line per entry.
  Secondary: the plan's own Context (plan:18) says the verification ran against
  v2.83.1, while the 32 committed verdict lines say "against v2.82.0" — a second
  pass with a different anchor version compounds the ambiguity.

- **F6 (Medium) — Step 8's "present-but-empty" map fields make read→write→read
  non-convergent for exactly the legacy files the step's test is about.**
  Plan:297: *"the two map fields stay present-but-empty so a legacy baseline file
  still reads"*, and plan:298 requires the test to show that a legacy file's
  `observe_parallel` samples are *"reported under the sequential aggregate or
  ignored by a stated rule"*. But the sequential write path is not read-only:
  `lib/aid-gate-runtime-baseline.sh:435-444` explicitly carries the existing
  entry's `recent_samples_by_context` / `percentiles_by_context` forward into the
  rewritten entry. Deleting "the `*_by_context` assembly" (plan:297) while
  emitting the fields empty means the **first ordinary sequential gate run after
  this change silently wipes** a legacy file's populated maps. Read once: data
  present. Read again after any gate ran: data gone. If the chosen rule is
  "report them under the sequential aggregate", the reported percentiles differ
  between the first and the second read of the same file — which also makes
  AC9's *"The live baseline's percentiles are numerically identical before and
  after"* (plan:318) true only for this repo (whose maps are already empty, as
  plan:300 verifies) and untested for the other-projects case that plan:302 calls
  "the whole risk". The step must pick one rule (carry-forward-verbatim, or
  drop-with-a-migration-note) and pin it in the test.

- **F7 (Medium) — nothing in Steps 3/4 covers the interrupt case; the rollback
  runs only on one branch, and there is no trap.**
  `grep -n 'trap ' plugins/aid-orchestrator/scripts/aid-release.sh` → **no
  matches**. `_release_rollback_updated` is called from exactly two places
  (`:820` in `_release_commit_and_tag`, `:1040` in `cmd_prepare_plan`), both on
  the CHANGELOG-validation failure branch. A killed session (a live scenario for
  this project's background/auto runs) between `_release_update_files` and the
  validation leaves the whole bump applied. Reproduced consequence: with a single
  file stranded, the very next `prepare-plan` for the same plan does **not**
  resume — it aborts at `aid-release.sh:1002-1006` with `PRECONDITION FAIL:
  prepare-plan refuses to run with modified tracked files`, and the crash-resume
  short-circuit at `:987-996` does not apply because no commit was made. Step 3
  claims to make an aborted release safe to rerun ("the rerun bumps from the same
  base"); that only holds for the one abort branch it inherits. Recommend the
  step either add an `ERR`/`EXIT` trap around the update window or state
  explicitly that interrupt-resume is out of scope.

- **F8 (Low) — `UPDATED[]` can be contaminated across runs by a stale PID temp
  file.** `aid-release.sh:663-671`: the config-path loop runs in a pipeline
  subshell and appends (`>>`) to `/tmp/aid-release-updated-$$`, which is read
  back and `rm -f`'d only if the reader is reached. An abort between the loop and
  the read leaves the file; a later run that draws the same PID inherits those
  paths into `UPDATED[]` and would `git checkout --` files it never touched
  during rollback. Step 3 is the step that owns `UPDATED[]` bookkeeping and is
  the natural place to switch to `mktemp` + `trap`-cleanup.

- **F9 (Low, reverse case — an acceptance criterion with no reachable
  invocation) — Step 4's *"Re-running a release for the same version changes
  nothing"* (plan:187).** Neither entry point accepts a target version:
  `_release_detect_version` derives `CURRENT` from `plugin.json` /
  `marketplace.json` / CHANGELOG (`:382-415`) and `NEW_VERSION` is always
  `CURRENT` + one bump (`:426-430`). After a successful release, a rerun bumps to
  the *next* version, not the same one. `--version` exists only on `tag-plan`.
  The criterion is therefore only testable through a synthetic fixture; the step
  should say which invocation it means (most likely: "the fallback README updater
  called twice with the same NEW_VERSION is a no-op the second time"), otherwise
  the implementer will write a test that proves something else.

- **F10 (Low, advisory — reverse case) — AC9 as written cannot pass.** Plan:316:
  *"`grep -c 'observe_parallel\|parallel' aid-gate-runtime-baseline.sh` returns
  only the refusal message and the read-compat handling."* `grep -c` returns a
  count, not lines; the criterion is unfalsifiable as phrased. Reword to a
  `grep -n` inspection with an expected line set, or an exact expected count.

- **F11 (Low, advisory) — Step 10's "descriptions replaced" must not touch entry
  headings.** `scripts/tests/bats/test-deferred-work-registration.bats:123`
  requires `grep -qE "^#+ .*\b${imp}\b"` against
  `docs/plans/2026-06-29-BACKLOG.md`. Deleting an original framing (plan:370:
  *"the original framing is deleted, not annotated"*) for a closed entry breaks
  this existing suite if a heading goes with it. Also note plan:361's test is to
  assert *"the file parses as the status extractor expects"* — no script named a
  backlog status extractor other than this bats file; the step should name the
  consumer it means.

confidence: high

Grounds: B1/B2/F1/F2/F3 were reproduced end-to-end in a throwaway clone with the
exact commands recorded above, on both the fallback and the config path, with
Step 3's fix mechanically simulated. B3, F4, F5, F6, F7, F8 are read directly
off named file:line in the real repo. F9-F11 are read off the plan against the
real entry points. Lower confidence only on F6's blast radius: I could not
measure a real legacy baseline file with populated `*_by_context` maps (none
exists in this repo — which is itself what plan:300 verified), so the wipe is
established from the writer's code path (`:435-444`), not from a run.
