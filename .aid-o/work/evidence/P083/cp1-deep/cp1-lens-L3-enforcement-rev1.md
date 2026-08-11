# CP1-deep rev1 — Lens L3 ENFORCEMENT — P083

Plan: `.aid-o/plans/P083-ten-verified-defects.md` @ `c0458cb` (revision 1, 517 lines)
Repo: `/opt/eco/projects/aid-orchestrator` @ main, v2.83.1
Lens: gitignored artifacts, remote CI visibility, test execution, release/CI breakage,
detector-without-enforcement.

Method: every claim below is a command run or a file:line read in this checkout, or a
reproduction in
`/tmp/claude-1000/-opt-eco-projects-aid-orchestrator/50d5999a-d6f6-42c1-a512-479b5d12dbb9/scratchpad/r4`.
No paraphrase from the plan or the adjudicator is taken on trust. Nothing was written
outside the scratchpad and this file.

stop_rule_blockers: 1

findings:

## Item 1 — AB-2 (Step 4, README tagline) — **NOT DISCHARGED**

The step now names `.aid-o/config/project.yaml` and `README.md:3` in its Files list and
drops the fallback rewrite. The diagnosis is right and the one-time repair is right. The
**prescribed remedy is wrong**, and it is wrong in a way that is worse than the defect.

### Leg A — the bracket-expression fix corrupts the line it repairs (NEW BLOCKER)

Plan line 166: *"they become bracket expressions (`[(]`, `[)]`)"*. This is the adjudicator's
own required_change (AB-2), so it was never re-tested against the runtime.

`aid-release.sh:573-575` derives **both** sides of the substitution from the SAME
`FILE_PATTERN`:

```
SEARCH=$(echo "$FILE_PATTERN"  | sed "s/{VERSION}/$CURRENT/g")
REPLACE=$(echo "$FILE_PATTERN" | sed "s/{VERSION}/$NEW_VERSION/g")
sed -i "s|$SEARCH|$REPLACE|g" "$FULL_PATH"
```

The pattern doubles as the replacement template. The existing escapes survive only because
GNU sed collapses `\x` → `x` in the replacement (`\*`→`*`, `\[`→`[`, `\.`→`.`). A **bracket
expression does not collapse** — it is emitted literally.

Reproduced verbatim (scratchpad `r4/test.sh`, exact `SEARCH`/`REPLACE`/`sed` from
`:573-575`), on the real line 3 repaired to v2.83.1, CURRENT=2.83.1 → NEW=2.84.0:

```
IN : **Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v2.83.1
OUT: **Multi-agent orchestration plugin for [Claude Code][(]https://claude.com/claude-code[)].** v2.84.0
```

The substitution succeeds — and destroys the markdown link on the repository's first
visible line. It also re-freezes the line permanently: the pattern `[(]` matches one `(`,
and the corrupted line now holds `[`,`(`,`]`, so no subsequent release matches it either.
Step 4 would trade "frozen at v2.69.0" for "broken link, frozen at v2.84.0", and its AC2
("`README.md:3` states the current version … after the next release") would be false on the
release after next.

**The correct fix is the opposite move: delete the backslashes, do not convert them.** In
POSIX BRE a bare `(` is already a literal. Verified in the same harness:

```
pattern: \*\*Multi-agent orchestration plugin for \[Claude Code\](https://claude.com/claude-code)\.\*\* v{VERSION}
OUT: **Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v2.84.0   ← correct
```

This is also what the sibling row proves independently: `"\\*\\*v{VERSION}\\*\\* (current)"`
carries bare parens and is the row that keeps `README.md:120` current
(`- **v2.83.1** (current)` — read at HEAD). The working row in the same file already
demonstrates the right answer; the plan copied the wrong one.

Required change: Step 4 line 166 replaces the bracket-expression instruction with
*"the parentheses lose their backslashes (BRE reads a bare `(` as a literal; the pattern
string is also the replacement template at `aid-release.sh:574`, so any escape that does
not collapse to itself is emitted verbatim into the file)"*, and
`test-aid-release-readme.bats` asserts the **output line**, not merely that a substitution
occurred. As written the step's own test spec ("the real row-3 pattern substitutes on a
fixture line containing literal parentheses") passes on the corrupting fix.

### Leg B — the config file the fix lives in cannot be committed

`git check-ignore -v .aid-o/config/project.yaml` → `.gitignore:98:**/.aid-o/`, and
`git ls-files .aid-o/config/` returns only `counter.yaml`, `execution.yaml`,
`test-catalog.yaml`. **`project.yaml` is ignored AND untracked.** Step 4's Files list says
"Modify" without stating that this edit reaches no other checkout, no clone, and no CI job.

Consequences the plan does not declare:
- The pattern repair is a local working-copy change only. No gate, no suite and no reviewer
  outside this machine can observe it. The step's suite must therefore test a *fixture*
  pattern string, which is exactly what the plan says it does — so nothing anywhere ever
  asserts that the real config was fixed.
- It collides with Step 3's load-bearing premise. Step 3 (plan line 140) rests on
  *"`.aid-o/config/project.yaml` … is gitignored, so any clone or worktree takes the
  fallback"*. Force-adding `project.yaml` (the route `execution.yaml` took) would repair
  Leg B and simultaneously invalidate Step 3's reproduction path. The plan must pick one and
  say which.
- Worth recording as the mitigating fact: after the one-time `README.md:3` repair to
  v2.83.1, the **fallback** path (`aid-release.sh:670-675`, `grep -q "v$CURRENT"` then
  `sed -i "s/v$CURRENT/v$NEW_VERSION/g"`) *does* match line 3 and keeps it current. Since
  plan-final releases run in worktrees, which have no `project.yaml`, the objective is
  actually delivered by the untouched fallback. The config path — the only path Step 4
  edits — runs only in this one checkout, and there it corrupts (Leg A).

### Re-break vectors checked and clean

- `grep -rn 'Multi-agent orchestration plugin'` over all tracked yaml/yml/md → **one hit**,
  `README.md:3`. No `defaults/` template regenerates the pattern, so `/aid-init` cannot
  re-introduce it.
- `defaults/orchestration.yaml:64-83` carries a *separate* registry with distinct
  `pattern`/`replacement` fields (so it does not share this bug) and, as the plan correctly
  says, nothing reads it.
- `defaults/hooks/pre-commit:149-153` derives the release commit whitelist from
  `versioning.files[].path`. Step 4 changes patterns only, not paths — no impact.

### Dropping the fallback rewrite — one obligation now silently owned

The fallback's blunt `s/v$CURRENT/v$NEW_VERSION/g` over every README within 3 levels stays.
Step 4 line 172 says the reconciliation of the three version-file registries "is recorded as
deferred work" — but the plan's `## Deferred` section (lines 511-517) contains **no such
entry**, and no entry for the blunt-substitution behaviour either. That is the AB-9 shape
repeating: an obligation asserted in a step with no declared home. Either add both to
`## Deferred` or drop the sentence. Aside from that the drop is clean: the fallback was
never the mechanism for line 3 (it greps `v$CURRENT`, and line 3 read v2.69.0), so nothing
that worked is being removed.

## Item 2 — AB-5 (Step 7, `test-aid-init.bats` + upgrade path) — **PARTIAL**

Mechanics: **discharged.**
- Suite name is exact: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats`
  exists; the plan's path string matches byte-for-byte.
- Tier tag unaffected: file header is `# aid-tier: t0` (line 2). The step edits assertion
  bodies at `~100-111` and `~208-212`, not the header. CI routing unchanged —
  `.github/workflows/ci.yml:58` runs `run-all-tests.sh --tier t0 --verbose` first, and the
  suite is not in `DELEGATED_SUITES` (`run-all-tests.sh:251-266`), so it stays in the
  aggregate T0 job.
- The file is now in Step 7's Files list, and AC3 pins it green. Scope-gate exposure closed.

Escape hatch: **a deferral in disguise, and it does not need to be — the question is
answerable now, and I answered it.**

`render_gate_profiles_block()` (`lib/aid-init-execution-yaml.sh:206`) takes
`local stacks=("$@")` — **stacks only, no target-file parameter**. Its two callers are
`compose_execution_yaml` (`:395`) and `commands/aid-init.md:157`, both passing
`"${stacks[@]}"` and nothing else. Because the parameter list is varargs-of-stacks, a new
target-file argument must be positional-first, which breaks the caller Step 7 is forbidden
to edit. There is exactly one route left: an **implicit probe** of
`.aid-o/config/execution.yaml` relative to cwd inside the library (aid-init runs from the
project root, and `:153`/`:160` name that literal path). No env-var route exists either —
setting the env var would require editing `aid-init.md`.

So the answer is *possible, by one specific mechanism, with one specific hazard* (a stale
pre-existing `execution.yaml` present at fresh-init time would silently narrow the composed
ladder; guardable by requiring a non-empty `.gates` mapping AND
`execution_yaml_has_gate_profiles` returning false). The step should state that mechanism
and its guard rather than delegate the discovery.

Why "stops and reports" is not an acceptable resolution as written:
- The two paths **share one derivation by design** (`:203-205`: *"one derivation, no
  drift"*). There is no edit to `render_gate_profiles_block` that widens fresh-init without
  also widening what `append_gate_profiles_block` writes into a hand-authored config. So
  "the step stops" is not a partial landing — it is the whole step abandoned mid-EPIC, with
  AC2 ("on both the compose and the upgrade path") unsatisfiable.
- The hazard it defers is real and enforced by a hard exit: `aid-run-gates.sh:1596-1601`
  aborts with *"gate profile 'X' includes undefined gate 'Y'"* before any gate runs. Note it
  is guarded by `if [[ -n "$profile" ]]` (`:1586`), so it fires only on an explicit
  `--profile` invocation — which is precisely what `plan_final_profile_floor: release`
  produces. The ladder widens a hazard that already exists at two profiles to five.
- Enforcement-lens verdict: an escape hatch whose trigger condition is knowable at plan time
  is a detector without enforcement. Replace *"if that proves impossible … the step stops and
  reports"* with the named mechanism above plus a stated fallback (e.g. "if the implicit
  probe is rejected, the upgrade path keeps rendering the two-profile block and the ladder is
  fresh-init-only until P080 releases `aid-init.md`") — that is a real, small, landable
  answer; "stop and report" is not.

## Item 3 — AB-9 (enforcement registry) — **DISCHARGED**

- `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` exists (313 814 bytes),
  is returned by `git ls-files`, and `git check-ignore` exits 1 → **tracked and
  committable**.
- Its own header (`:1-8`) declares it *"the canonical list of every enforcement mechanism
  shipped with the plugin distribution"* and demotes the `docs/plans/` copy to
  *"mirror/archive"*. It is the live one.
- Row shape is consistent with what Steps 5/6/8 promise: `:20-46` documents
  `id/type/source/description/instruction/severity/surface/status/verdict/test`. All three
  steps name `type`/`source`/`instruction`/`severity`/`surface`; all three also name their
  own suite, which satisfies the `test:` field. Existing rows follow the same shape
  (`:2713 test_tier_runner_refusal`, `:2725`, `:2737`).
- P080 **is** editing it, first-hand:
  `git -C .aid-worktrees/plan-P080 diff --name-only main...HEAD` →
  `…/defaults/enforcement-registry.yaml`, plus `commands/aid-help.md`,
  `defaults/help-index.yaml`, `lib/aid-help-index.sh`, `test-help-index-coverage.bats`,
  `test-enforcement-registry-cites.sh`, `test-enforcement-registry-test-audit.sh`,
  `test-skill-lint.sh`. `commands/aid-init.md` and `defaults/templates/` are **absent** from
  that list, exactly as the revised Constraint (line 494) now states. The constraint guards
  the real collision.

## Item 4 — AB-6 (ordering obligation) — **PARTIAL**

The literal required_change ("Step 5 states the ordering explicitly") is satisfied: plan
lines 213 and 495 state it, and AC1 now says *"asserted in the checkout that runs the gate"*.
Judged as enforcement, it is hope, not a mechanism:

- Both halves live in **one step** (Step 5 modifies `.aid-o/config/execution.yaml` and
  `aid-run-gates.sh`). A step is one implementation unit and normally one commit. There is
  no precondition, gate, or test that can observe "config merged before refusal shipped"
  when both arrive together. The sentence is unfalsifiable in the shape the plan gives it.
- The second half — *"every live worktree refreshes from main before its next gate run"* —
  is an obligation on a **concurrent session P083 cannot reach**. The exposure is measured
  and current: `yq '.gates.plan_diff.command // "NULL"'
  .aid-worktrees/plan-P080/.aid-o/config/execution.yaml` → `NULL`, today.
- The adjudicator offered a real mechanism as the alternative ("gate the refusal behind a
  config-generation key"). The plan took the prose option. Per AID principle #1 that is a
  detector (the refusal) whose migration path is decoration.

Not raised to a blocker: the refusal is profile-scoped (`aid-run-gates.sh:1586`), and this
repo's `gate_profile_defaults` is `null` (measured), so ordinary EPIC gate runs pass no
`--profile` and never reach it. P080's exposure is confined to an explicit `--profile` run,
i.e. its plan-final. Real, bounded, and now at least named. Recommended minimum: make the
refusal's message name the remedy verbatim ("merge main into this worktree") so the failure
is self-clearing, and say in the step that the two edits may not share a commit.

## Item 5 — AB-10 (Step 10 tier) — **DISCHARGED**

- Tier moved to `t1` (plan lines 375, 383) and the rationale is stated.
- Defensible against the lint: `lib/aid-test-tier.sh:60-61` sets
  `AID_TIER_T0_MAX_MS=2000`, `AID_TIER_T1_MAX_MS=30000`. `cost_tier()`
  (`aid-test-tier-lint.sh:100-108`) computes per-case ms and a `t1` claim only violates when
  the newest measurement supports no cheaper than `t2` — i.e. ≥30 s **per case**. A per-entry
  grep sweep over a 4 050-line file is orders of magnitude under that.
- Until measured, `aid-test-tier-lint.sh:145-152` records it as `UNVERIFIED` (tag accepted),
  not a violation. So `tier_lint` — `required: true` in every profile — accepts the suite
  both before and after measurement. The t0 trap the first pass flagged is gone.
- The "at most one verdict line per entry" assertion is present (line 375, bolded), the
  replace-in-place rule is stated (line 381), the v2.82.0/v2.83.1 anchor discrepancy is
  resolved in the same edit, and the only consumer of the file's shape
  (`test-deferred-work-registration.bats:123`) is named and pinned. All four AB-10 legs met.

Advisory: nine new `t1` suites land at once against a whole-tier budget of 10 min. The
budget is enforced by `aid-test-tier-assign.sh` (which proposes/demotes), not by
`tier_lint`, so nothing turns red — but the merge path's 13-minute figure from P081 has no
headroom stated in this plan.

## Item 6 — new Files entries, suite discovery, CI routing — **PARTIAL**

Discovery and execution: **discharged.**
- All ten suites are `bats/test-*.bats` under
  `plugins/aid-orchestrator/scripts/tests/bats/`, discovered by the glob at
  `run-all-tests.sh:284-287`. None is in `DELEGATED_SUITES` (`:251-266`), so none is skipped.
- All ten filenames are free (checked each against the directory) and none collides with a
  near neighbour (`test-aid-release.bats`, `test-aid-gate-runtime-baseline.bats`, etc. are
  distinct).
- All ten now declare `t1` (Step 10's move to t1 removed the only t0). `ci.yml:58-59` runs
  `--tier t0` then `--tier t1`, so every one is executed on the merge path. No new CI job
  needed.
- All ten pass `is_plan_numbered` (`aid-test-tier-lint.sh:86-98`): no `p<digits>` segment and
  no `e`/`t` segment followed by digits. `test-c0-plan-graph-input` is safe (`c0` is not a
  plan token).
- Step 8's deletion breaks no existing suite: `grep -rn '_by_context'` across the whole repo
  returns **only** `lib/aid-gate-runtime-baseline.sh` (and the P080 worktree's copy of it)
  plus `.aid-o/metrics/gate-runtime-baselines.yaml` data and plan prose. The current
  `test-aid-gate-runtime-baseline.bats` (`# aid-tier: t1`) has no `by_context` or `parallel`
  assertion left — P078 already removed them. No unlisted test file is touched.

Files-list completeness: **one gap.**
- `CHANGELOG.md` and `plugins/aid-orchestrator/CHANGELOG.md` appear in **no** step's Files
  list, while Step 5 commits to a specific CHANGELOG obligation (line 219: *"this is stated
  in the CHANGELOG as a breaking configuration check … the CHANGELOG entry names the check
  explicitly rather than burying it"*) and the adjudicator asked the same of Step 8
  ("state the loss in the CHANGELOG"). This is the identical defect AB-9 was raised for — a
  named obligation with no declared home and no `allowed_paths` coverage. Mitigating: the
  Release Sub-Phase writes the placeholder heading mechanically. Not mitigating: the
  *content* Step 5 promises is a step-level deliverable that no step owns. Add both
  CHANGELOGs to Step 5's Files list (and Step 8's), or delete the promise.
- Minor: Step 7's implicit-probe workaround (item 2) would leave
  `commands/aid-init.md:211-213`'s description of `render_gate_profiles_block` stale. P080
  owns that file, so the drift is accepted rather than fixed — worth one sentence in the
  step so it is a decision, not an oversight.

## Summary table

| Item | Blocker | Verdict |
|---|---|---|
| 1 | AB-2 Step 4 README | **NOT DISCHARGED** — remedy corrupts the line; config file uncommittable |
| 2 | AB-5 Step 7 init suite | **PARTIAL** — mechanics clean; escape hatch is a deferral |
| 3 | AB-9 enforcement registry | **DISCHARGED** |
| 4 | AB-6 ordering | **PARTIAL** — stated, not enforceable |
| 5 | AB-10 Step 10 tier | **DISCHARGED** |
| 6 | New suites / Files lists | **PARTIAL** — discovery clean; CHANGELOG unowned |

confidence: high — Leg A of Item 1 is a byte-level reproduction of `aid-release.sh:573-575`
against the real `README.md:3` with both the plan's prescribed pattern and the corrected one;
every other claim is a `git ls-files` / `git check-ignore` / `git diff --name-only` /
`yq` / `grep` result or a file:line read in this checkout at `c0458cb`. The single blocker is
a one-line correction to Step 4 (unescape rather than bracket) plus a sentence about the
untracked config; it does not re-open the plan's approach.
