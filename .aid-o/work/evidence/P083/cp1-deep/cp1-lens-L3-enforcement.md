# CP1-deep — Lens L3 ENFORCEMENT — P083

Plan: `.aid-o/plans/P083-ten-verified-defects.md` (497 lines, risk high, 10 steps / 3 EPICs)
Repo: `/opt/eco/projects/aid-orchestrator` @ main, v2.83.1
Lens: gitignored artifacts, remote CI visibility, test execution, release/CI breakage,
detector-without-enforcement.

stop_rule_blockers: 2

findings:

## BLOCKER-1 (Step 4) — the README defect the step cites cannot be fixed by the step, and the step removes the only mechanism that currently would

Plan quote (Architecture Context, line 169): *"Group 1, and the visible proof: `README.md:3` still
reads v2.69.0 while main is at v2.83.1."* Plan quote (Implementation Detail, line 171): *"The config
path (`project.yaml → versioning.files[]`, executed at :574-577) already does a regex substitution
for this repo and **is not the failing path** in a worktree; this step fixes the fallback."*

That premise is false. The config path IS the failing path for `README.md:3`, and the failure is a
BRE-escaping bug:

- `.aid-o/config/project.yaml` (tracked; see BLOCKER-3 note) declares three README rows, the third being
  `pattern: "\\*\\*Multi-agent orchestration plugin for \\[Claude Code\\]\\(https://claude.com/claude-code\\)\\.\\*\\* v{VERSION}"`.
- `aid-release.sh:568-572` applies it as `sed -i "s|$SEARCH|$REPLACE|g"`. In POSIX BRE, `\(` and `\)`
  are **group delimiters, not literal parentheses**, so the pattern cannot match a line containing
  literal `(https://…)`.
- Reproduced: writing README line 3 verbatim to a scratch file and running exactly that
  `SEARCH`/`REPLACE` sed substitutes **nothing** (file unchanged). The sibling row
  `"\\*\\*v{VERSION}\\*\\* (current)"` has no `\(`, which is precisely why `README.md:120` reads
  `- **v2.83.1** (current)` while `README.md:3` is frozen at v2.69.0.

Consequences as the step is written:

1. Step 4's Files list touches only `aid-release.sh` (~660-677, the fallback). The config path is
   explicitly declared out of scope, so `README.md:3` stays at v2.69.0 after this plan lands.
2. Step 4 AC (line 185) requires *"prose mentioning the previous version outside the list is
   untouched"* — i.e. it **codifies** leaving line 3 stale.
3. It is a regression on the fallback path: today's fallback (`aid-release.sh:672-675`) does
   `sed -i "s/v$CURRENT/v$NEW_VERSION/g"` over every README within 3 levels, which *does* fix line 3.
   Replacing it with an anchor-scoped edit under `## Changelog` (README.md:118) removes the only
   mechanism in the tree that currently updates line 3 anywhere.
4. Success Criterion 2 (line 388) — *"`README.md` shows the current version after the next release"* —
   is therefore unachievable by this plan as scoped, on both the config and the fallback path.

Fix that clears the blocker: either add `.aid-o/config/project.yaml` (its README row 3 pattern) to
Step 4's Files list and fix the BRE grouping (`\(` → `[(]` or switch to `sed -E`), or make Step 4's
anchored updater own the version-badge line explicitly and drop the "prose untouched" AC for it.

## BLOCKER-2 (Step 7) — a T0 merge-path suite is broken by the step and is not in the step's Files list

`plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` (`# aid-tier: t0`, line 2) pins the
exact two-profile output that Step 7 replaces with a five-profile ladder:

- `:100-104` — `.gate_profile_defaults.step == "targeted"`, `.gate_profile_defaults.epic == "full"`
- `:108-111` — `.gate_profiles.targeted.include | join(",") == "ts_test,targeted_tests"` and
  `.gate_profiles.full.include | join(",") == "ts_test,ts_lint,ts_type_check"`
- `:208-212` — the same two assertions on the existing-project upgrade path
  (`render_gate_profiles_block` + `append_gate_profiles_block`)

Step 7's Files list (plan lines 261-263) names only
`plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` and the new
`test-init-gate-profiles.bats`. Under AID's own scope enforcement (`allowed_paths` derived from the
Files list, `scripts/gates/scope-check.sh`) the implementer cannot legitimately edit
`test-aid-init.bats`, so the step as scoped either fails the scope gate or lands red.

This is a merge-path break, not a nightly one: `.github/workflows/ci.yml` `bash-tests` runs
`run-all-tests.sh --tier t0` **first**, and the self-host gate `tier_lint`/`bats_all` path runs the
same portfolio. A red T0 suite blocks every merge.

Fix: add `test-aid-init.bats` to Step 7's Files list with an explicit statement of the new expected
profile set, and add an AC that its three assertion sites are updated (not deleted).

## MEDIUM-3 (Step 5) — the step's stated justification rests on a false fact that the repo can disprove in one command

Plan quote (line 203): *"Because `.aid-o/` is gitignored there is no history to say when the command
disappeared — which is precisely why the runner-side refusal matters more than the config fix."*

`.aid-o/config/execution.yaml` matches `**/.aid-o/` (`.gitignore:98`) but is **force-added and
tracked**: `git ls-files .aid-o/` returns 203 files including `.aid-o/config/execution.yaml`, and
`git log --oneline -- .aid-o/config/execution.yaml` returns 16 commits (most recent `6490797`,
`2290ccc`, `cdd960b`).

The history is therefore available, and it says something different from the plan:
`git log -S'aid-plan-diff' --oneline -- .aid-o/config/execution.yaml` returns **nothing** — the
`command:` was never present in the tracked self-host config. So the plan's framing (line 205,
*"its `skip/no_command` row is a pure regression in the self-host config"*) is unsupported; this is a
first-time addition, not a restoration. That matters for the exemption-note rewrite the step commits
to, and for the CHANGELOG wording of a breaking configuration check.

Note the same false claim is embedded in the config file the step edits (`.aid-o/config/execution.yaml`,
`plan_diff` note: *"`.aid-o/config/execution.yaml` is git-ignored (`**/.aid-o/` in .gitignore), so
there is no commit history to trace…"`). Step 5 should correct it while it is in there.

Positive: because the file is tracked, AC6's verification
`test -n "$(yq -r '.gates.plan_diff.command // "") .aid-o/config/execution.yaml)"` is reachable in a
fresh clone and in CI. No blocker.

## MEDIUM-4 (Constraints, line 479) — the enforcement registry the plan promises to write to is not at the path the repo's own instructions name

Plan quote: *"Steps 5 and 10 add a refusal inside an existing check; … both are registered in the
enforcement registry in the same commit that adds them."*

- `docs/plans/AID-audit-2026-06/enforcement-registry.yaml` — **does not exist** (the path CLAUDE.md
  still names).
- `docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml` — exists, tracked; it is the
  archived seed.
- `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — exists, tracked, 313 KB, and its own
  header (`:1-8`) declares it the canonical distributed registry and the `docs/` copy a "mirror/archive".

The claim is actionable, but the plan must name the distributed file; writing only to the archived
seed would register the two new enforcements where nothing ships or reads them (the TTL guard
`aid-registry-ttl-guard.sh` is wired against the distributed registry via
`scripts/aid-evidence-verify.sh:26`). Recommend: Steps 5 and 10 list
`plugins/aid-orchestrator/defaults/enforcement-registry.yaml` in their Files lists (neither does today).

## MEDIUM-5 (Step 10) — a `t0` declaration on a suite that parses a 4,050-line file, with no measurement behind it

Step 10 declares `(tier: t0)` for `test-backlog-verdicts.bats`, whose subject
(`docs/plans/2026-06-29-BACKLOG.md`) is 4,050 lines and whose ACs demand a per-entry sweep over 46
entries plus a contradiction check. T0's ceiling is under 2 s/case (`lib/aid-test-tier.sh` thresholds,
used by both `aid-test-tier-assign.sh` and `aid-test-tier-lint.sh`'s AFFORDABLE check).

The tag will lint clean at first (an unmeasured suite is reported UNVERIFIED, not a violation —
`aid-test-tier-lint.sh:145-152`), but the first `--timing` run that records a duration above the T0
ceiling turns the `tier_lint` gate red, and that gate is `required: true` in
`.aid-o/config/execution.yaml` and sits in every profile. Recommend declaring `t1` unless the step
measures first.

## LOW-6 (Step 5) — the profile count is wrong

Plan quote (line 60 and line 203): *"`plan_diff` sits in four merge-path profiles"*. It is in **five**:
`yq -r '.gate_profiles | to_entries[] | .key + ": " + ((.value.include//[])|join(","))'
.aid-o/config/execution.yaml` → `standard`, `full`, `release`, `bats_all_quarantine`,
`release_quarantine`. Step 5's AC1 ("no profile … includes a gate without a command") covers all of
them, so this is cosmetic — but the number appears twice and should be corrected.

## LOW-7 (Step 5) — two existing behaviours the new refusal must be written not to break, neither named in the step

Both are compatible with the step's stated profile-scoped design; naming them in the new suite is what
keeps a later implementer from widening the refusal to a config-validation pass over all gates:

- `plugins/aid-orchestrator/defaults/execution.yaml` ships `standards_compliance` **deliberately
  command-less** (`type: llm_evaluated`, in-file note *"No bash command — evaluated by LLM auditor
  during DONE state review"*). It is in no profile (defaults ship no `gate_profiles:` at all), so a
  profile-scoped refusal leaves it alone; an all-gates refusal would break the shipped default for
  every consumer on first run.
- `test-aid-run-gates.bats:104-125` (`# aid-tier: t1`, merge path) asserts that a null-command gate
  invoked **without** `--profile` still emits `{result: skip, reason: no_command}` and `overall: pass`.
  A profile-scoped refusal preserves it; a global one turns a T1 merge-path suite red.

Step 5's third test case (*"the shipped defaults pass unchanged"*) should name both explicitly.

## Verified clean (no finding — checked and passing)

- **All ten new suites execute.** `run-all-tests.sh:277-287` discovers `bats/test-*.bats`; none of the
  ten is in `DELEGATED_SUITES` (`:241-266`); `.github/workflows/ci.yml` `bash-tests` runs
  `--tier t0` then `--tier t1`, which covers the nine `t1` suites and the one `t0` suite. No new
  dedicated CI job is needed.
- **Tier tags will lint.** All 161 existing bats suites carry `# aid-tier:`, so the runner's absolute
  untagged refusal (`run-all-tests.sh:334-342`, exit 1 for the whole portfolio) applies — the plan's
  Constraint at line 480 is the right one and is load-bearing. All ten proposed filenames pass
  `is_plan_numbered` (`aid-test-tier-lint.sh:78-90`): no `p<digits>` segment and no bare `e`/`t`
  segment followed by digits (`test-c0-plan-graph-input` is safe — `c0` is not a plan token). No
  filename collides with an existing suite.
- **Step 10's artifact is committable and findable.** `docs/` is ignored but
  `!docs/plans/2026-06-29-BACKLOG.md` is an effective negation *because the file is already tracked*
  (`git ls-files docs/` lists it along with 10+ other tracked docs files) — the parent-directory rule
  that bit P065 does not apply to an already-tracked path. Precedent for a suite reading it from the
  runner's cwd exists: `test-deferred-work-registration.bats:35` uses
  `BACKLOG="$REPO_ROOT/docs/plans/2026-06-29-BACKLOG.md"`. No new file under `docs/` is created, per
  the step's own Implementation Detail — correct.
- **Step 5's refusal is reachable and breaks no shipped default or existing profile.** The only
  command-less gate in any profile in this repo is `plan_diff` itself (checked with `yq` over all 8
  profiles); no profile references an undefined gate (checked programmatically). `defaults/execution.yaml`
  ships no `gate_profiles:` block at all.
- **No Step 5 × Step 7 collision.** `compose_execution_yaml`
  (`lib/aid-init-execution-yaml.sh:351-388`) builds a consumer's gate set from
  `defaults/execution-stacks/*.yaml` + `render_targeted_tests_gate_block` only — every one of those
  gates has a `command:`. The command-less `standards_compliance` from `defaults/execution.yaml` never
  reaches a composed consumer file, so Step 7's wider profile ladder cannot trip Step 5's refusal.
- **Step 9's producer exists.** `aid-generation-readiness.sh:7,21` accepts
  `--write-provisional <path>`; `defaults/prompts/c0-plan-review-prompt-v1.md` exists and is tracked.
- **Step 1's premise holds.** Writer default is `${_evidence_dir}/gates/gates_report.json`
  (`aid-run-gates.sh:1628-1629`); `fsm_check_streamlined_integration_review`
  (`aid-fsm.sh:1817-1845`) reads the flat `${evidence_dir}/gates_report.json` — the mismatch is real.
- **Step 3's premise holds.** `.metadata.version` (`aid-release.sh:657-662`), `.plugins[0].version`
  (`:663-668`) and the `Plugin: ` README branch (`:673-676`) all omit `UPDATED+=(…)`, and
  `_release_rollback_updated` (`:775-793`) iterates `UPDATED[]` only.
- **Release/CI plumbing otherwise untouched.** `.github/workflows/version-sync.yml` checks only
  `packages/*/package.json` against `package.json` (plugin version explicitly commented out), so
  Steps 3/4 cannot break it. `markdown-lint.yml` is path-filtered to
  `plugins/aid-orchestrator/{skills,commands,agents}/**` — Step 10's markdown edit is out of its scope.
  No step touches hooks.

confidence: high — every claim above is anchored to a file:line read or a command run in this checkout
(`yq` over both `execution.yaml` files, `git ls-files` / `git log -S`, a literal `sed` reproduction of
the README pattern, and `grep` over the tests tree). The two blockers are scope/ordering defects that a
Files-list amendment resolves; neither requires re-deciding the plan's approach.
