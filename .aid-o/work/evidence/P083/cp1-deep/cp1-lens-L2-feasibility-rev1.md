# CP1-deep rev1 — Lens L2 FEASIBILITY — P083

Plan: `.aid-o/plans/P083-ten-verified-defects.md` @ `c0458cb` (revision 1, 517 lines, 10 steps / 3 EPICs)
Repo: `/opt/eco/projects/aid-orchestrator` @ `main` (HEAD `c0458cb`, v2.83.1)
Method: every claim re-measured first-hand. All generation experiments ran in a
`git clone --local` at
`/tmp/claude-1000/-opt-eco-projects-aid-orchestrator/50d5999a-d6f6-42c1-a512-479b5d12dbb9/scratchpad/rev1/repo`.
The primary checkout was never mutated — only read.

## What was executed

1. `git clone --local` of the repo (HEAD = `c0458cb`); the plan is tracked, md5 identical to the primary copy.
2. `_aid_files_bullet_tier` from `lib/aid-scoping.sh` over all ten `- Test:` bullets.
3. `aid-plan-lint.sh`, `aid-generation-readiness.sh --write-provisional`.
4. `aid-plan-diff.sh --plan … --evidence-dir <tmp> --base-commit HEAD`, then a full row dump of `plan-diff.json`.
5. All eleven `verification_pattern.cmd` strings parsed out of the plan with PyYAML and each run through `bash -n`.
6. Full three-phase generation in the clone (`aid-plan-to-epic.sh` phases 1/2/3) with the CP1 adjudicator and C0 gates stubbed **inside the clone only** (a `verdict: pass` / `accepted_blockers: []` stub file and a `cp1-pm-escalation-override.json` — those are exactly the artifacts this review produces), then `aid-epic-to-json.sh` over each generated EPIC.
7. Reproduced the Step 4 BRE fix on a scratch copy of `README.md:3` with `CURRENT` set to both 2.69.0 and 2.83.1.
8. Read `aid-plan-fsm.sh:4530-4540` and `:4697-4701` to confirm the plan-final blocking mechanism Step 5 relies on.
9. `git check-ignore -v`, `git ls-files`, `git worktree list`, and a directory listing of `.aid-worktrees/plan-P080/.aid-o/config/`.

stop_rule_blockers: 2

findings:

- severity: blocker
  ref: "Step 4 — AC3, Error Handling and the Test bullet all require an `aid-release.sh` edit that no step declares"
  summary: "Shrinking Step 4 removed `aid-release.sh` from its Files list but left three requirements behind that can only be delivered by editing it. Step 4 cannot satisfy its own acceptance criteria within its own scope."
  evidence: |
    Step 4's Files list (plan lines 166-168) names exactly three paths:
    `.aid-o/config/project.yaml`, `README.md`, and the new bats suite. Confirmed
    in the generated plan.json from the clone:
      step_4_backend allowed_paths = [".aid-o/config/project.yaml", "README.md",
                                      "…/test-aid-release-readme.bats"]
    But three of Step 4's own requirements are code changes in `aid-release.sh`:
      - AC3 (line 188): "A configured pattern that matches nothing is reported by
        name rather than counted as an update."
      - Error Handling (line 174): "A configured pattern that matches nothing is
        reported per file and per row at the end of the release, by name. Today a
        no-match `sed` still prints `Updated: README.md (regex)`."
      - Test bullet (line 168): "a line stranded at an older version is detected
        and reported by name rather than silently skipped".
    The behaviour named lives at `aid-release.sh:572-576`:
        regex)
          SEARCH=$(echo "$FILE_PATTERN" | sed "s/{VERSION}/$CURRENT/g")
          REPLACE=$(echo "$FILE_PATTERN" | sed "s/{VERSION}/$NEW_VERSION/g")
          sed -i "s|$SEARCH|$REPLACE|g" "$FULL_PATH"
          echo "Updated: $FILE_PATH (regex)"
    Reporting a no-match requires comparing the file before/after (or a `grep -q`
    pre-check) and changing that `echo` — i.e. editing lines 572-576.
    Those lines are in NO step's declared range. Step 3's ranges are `~645-681`,
    `:823` and `~1048-1053`; nothing covers 560-600. Step 3's own allowed_paths do
    include `aid-release.sh`, but Step 3's AC set says nothing about no-match
    reporting, so an implementer working Step 3 has no instruction to add it and an
    implementer working Step 4 has no path to write it.
    `scope_check` is not defined in this repo's `execution.yaml`, so this is a
    silent scope escape rather than a loud one — which is why it needs saying here.
  suggested_fix: |
    Either (a) add `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~566-577)
    back to Step 4's Files list, scoped narrowly to the regex branch's no-match
    reporting and explicitly disjoint from Step 3's `~645-681` — which re-opens the
    declared dependency the revision just removed; or (b) drop AC3, the Error
    Handling paragraph and the third clause of the Test bullet, leaving Step 4 as
    the two-line repair the adjudicator asked for (fix the BRE, reset line 3) and
    recording "a no-match pattern is silently reported as an update" as deferred
    work. (b) is consistent with the shrink and is what I would do.

- severity: blocker
  ref: "Step 4 — `.aid-o/config/project.yaml` is gitignored and untracked; the Modify cannot merge and the T1 suite cannot run outside this one working copy"
  summary: "The file Step 4 repairs exists in exactly one checkout on this machine. The edit produces no commit, reaches no worktree, no clone and no CI, and the merge-path suite that asserts 'the real row-3 pattern substitutes' has no file to read anywhere else — a red T1 gate, the same shape the adjudicator accepted as AB-5."
  evidence: |
    $ git check-ignore -v .aid-o/config/project.yaml
      .gitignore:98:**/.aid-o/	.aid-o/config/project.yaml     (rc=0)
    $ git check-ignore -v .aid-o/config/execution.yaml
      (rc=1 — force-added and tracked, which is why Step 5's edit is fine)
    $ git ls-files .aid-o/config/project.yaml | wc -l  →  0
    In the fresh `git clone --local` I made, `.aid-o/config/` contains only
    `counter.yaml`, `execution.yaml`, `test-catalog.yaml` — no `project.yaml`.
    Same in the live worktree that will run these gates:
    $ ls .aid-worktrees/plan-P080/.aid-o/config/
      counter.yaml  execution.yaml  test-catalog.yaml
    Step 3's own Implementation Detail (line 140) states this fact correctly and
    builds on it — "`.aid-o/config/project.yaml` … is gitignored, so **any clone or
    worktree takes the fallback**" — but Step 4 then declares `Modify:` on that same
    file (line 166) without noticing that the same sentence makes its fix
    unmergeable and its test unrunnable.
    Step 4's Test bullet says "**the real row-3 pattern** substitutes on a fixture
    line containing literal parentheses" (line 168) and its tier is `t1`, i.e. the
    merge path. Reading "the real row" means reading `.aid-o/config/project.yaml`,
    which does not exist in the P080 worktree, in any clone, or in
    `.github/workflows/ci.yml`'s checkout (no workflow references `.aid-o` at all).
    NOTE — the underlying repair is still mechanically correct and I confirmed it.
    Reproduced on a scratch copy of `README.md:3`:
      CURRENT=2.69.0, pattern with `\(`/`\)`   → NO MATCH
      CURRENT=2.69.0, pattern with `[(]`/`[)]` → SUBSTITUTED
      CURRENT=2.83.1, either pattern           → NO MATCH
    So both halves of Step 4's diagnosis hold: the BRE grouping is the bug AND the
    one-time reset of line 3 is genuinely required (the search token is built from
    `CURRENT`, so a stranded line is self-perpetuating). And after the one-time
    reset, the fallback at `aid-release.sh:666-670` (`grep -q "v$CURRENT"` then
    `sed -i "s/v$CURRENT/v$NEW_VERSION/g"`) DOES keep line 3 current in worktrees.
    The defect is durability and testability, not correctness: the config-path fix
    is a private edit in one working copy, and the suite pinned to it is red
    everywhere else.
  suggested_fix: |
    Say in Step 4 which checkout the `project.yaml` edit lives in and that it is
    deliberately uncommittable, and make `test-aid-release-readme.bats` read a
    FIXTURE row (a copy of the pattern string checked into
    `scripts/tests/fixtures/`) rather than the live untracked config — asserting the
    pattern's shape, not the file's presence. Alternatively, since after the
    one-time README.md:3 reset the tracked fallback already keeps the line current,
    consider whether the untracked config edit belongs in this plan at all.

- severity: medium
  ref: "Step 3 — the `**Edge Cases:**` heading was lost in revision 1"
  summary: "Nine of ten steps carry an `**Edge Cases:**` header; Step 3's four edge-case bullets now dangle directly under its Error Handling paragraph with no heading. Introduced by this revision."
  evidence: |
    $ grep -c '^\*\*Edge Cases:\*\*' .aid-o/plans/P083-ten-verified-defects.md → 9
    An awk sweep over `### Step` sections shows `**Error Handling:**` and
    `**Dependencies:**` present in all ten steps, `**Edge Cases:**` present in
    Steps 1, 2, 4, 5, 6, 7, 8, 9, 10 — absent in Step 3.
    Plan lines 142-147: the Error Handling paragraph is followed immediately by
      "- A file listed by config and by fallback, or carrying two version fields…"
      "- A rollback with an empty `UPDATED[]`…"
      "- A repo where `project.yaml` IS present…"
      "- **Declared consequence:** …"
    with no heading between them. The AB-8 edit that added the "Declared
    consequence" bullet and rewrote Error Handling appears to have eaten the header.
    Not a generation blocker — `aid-plan-lint.sh` PASSes, readiness PASSes, and the
    EPIC generated cleanly (the EPIC template does not carry Edge Cases through at
    all). It is a plan-readability regression: the implementer reads the plan, and
    four edge cases now read as a continuation of an error-handling paragraph.
  suggested_fix: "Re-insert `**Edge Cases:**` before plan line 144."

- severity: medium
  ref: "Risks (plan line 506) — a stale bullet asserting a dependency the revision deleted"
  summary: "\"Step 3 and Step 4 edit the same block. Mitigation: explicit dependency and a shared fallback fixture\" is now false in both halves: they no longer edit the same file and there is no declared dependency."
  evidence: |
    Step 4's Files list no longer names `aid-release.sh` (confirmed above and in the
    generated allowed_paths). Both steps now declare "Depends on: none / Blocks:
    none" (plan lines 149-151 and 181-183).
    $ aid-generation-readiness.sh … --write-provisional <tmp>; jq …
      { "n_steps": 10, "n_edges": 0, "edges": [] }
    (was 10 steps / 1 edge `step-3 → step-4` before the revision).
    The Risks bullet's stated mitigation therefore names a control that does not
    exist. In a plan whose Context says P082 died of stale second-hand facts, a
    risk register that mitigates with a deleted dependency is the wrong kind of
    residue — and it is also the only place a reader would learn that the two steps
    were ever coupled.
  suggested_fix: "Replace with the real residual risk: Step 3 corrects `UPDATED[]` in the fallback while Step 4 corrects the config-path pattern; no step asserts that a future rewrite of either keeps the other's invariant. Or delete the bullet."

- severity: low
  ref: "Steps 5, 6, 8 — the three new registry rows will meet P080's new `test-enforcement-registry-cites.sh`, which no step names"
  summary: "P080 introduces a T0 registry-hygiene harness that does not exist on main. P083 adds three registry rows and must satisfy it, but the constraint only says 'coordinate on the registry'."
  evidence: |
    `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-cites.sh`
    does not exist on main; it exists only in `.aid-worktrees/plan-P080` and is
    `# aid-tier: t0`. It asserts that every `source:`/`instruction:` cite names an
    existing file or directory, and that every row id is unique.
    P083's Constraint (plan line 494) correctly identifies the registry as the P080
    collision and says the three steps "rebase onto its merge, or land after it",
    but does not state that each new row's cites must resolve and its id must be
    unique against P080's post-merge registry.
    Satisfiable — the three refusals cite `aid-run-gates.sh`,
    `lib/aid-review-signals.sh` and `lib/aid-gate-runtime-baseline.sh`, all of which
    exist — so this is a note, not a blocker.
  suggested_fix: "Add one clause to the Constraint: new rows carry unique ids and cites that resolve, per P080's `test-enforcement-registry-cites.sh`."

## The six items, verdict by verdict

**1. AB-3 — Step 10's role is `docs-writer`; does the whole plan generate? — DISCHARGED.**
All three EPICs generate AND all three convert to `plan.json`. Nothing stops.

    $ aid-plan-to-epic.sh --phase 1|2|3 --total 3 …   →  rc=0, rc=0, rc=0
      /tmp/claude-1000/gen1/E-083-1_3-….md
      /tmp/claude-1000/gen1/E-083-2_3-….md
      /tmp/claude-1000/gen1/E-083-3_3-….md
    $ aid-epic-to-json.sh --epic <each> --schema …/plan.schema.json …  →  rc=0 ×3
      …/E-083-1_3/R-E083-1/plan.json   (step_1..4_backend)
      …/E-083-2_3/R-E083-2/plan.json   (step_1..3_backend)
      …/E-083-3_3/R-E083-3/plan.json   (step_1_backend, step_2_backend,
                                        step_3_docs_writer)

EPIC 3's Steps table now renders `| 3 | docs-writer | … |` and `aid-epic-to-json.sh:234`
accepts it against `VALID_ROLES` at `:63`. The exact command that returned
`{"error": "Invalid role 'docs'…"}` in my first pass now returns a `plan.json` path.
The clone required stubbing the CP1 adjudicator (currently `verdict: revise` with ten
accepted blockers) and the C0 review — both are artifacts this review produces, and
both stubs live only in the clone.

**2. AB-1 — Step 5 keeps `required: false`; is the reasoning right and is nothing else implying `true`? — DISCHARGED.**
`grep -n 'required.*true'` over the plan returns three hits and none of them is
`plan_diff`: line 200 and 209 both state `required: false` explicitly, and line 383's
`required: true` is about `tier_lint`, correctly. Step 5's Files bullet (line 200)
says "an explicit `required: false` for the duration of this plan"; the dedicated
paragraph at line 209 states the mechanism correctly and I re-verified every link in
it (`aid-run-gates.sh:2001`, `aid-fsm.sh:2989-3002`, `gate_profile_defaults: null`,
exit 1 with 11/11 absent).

Success Criterion 3 (line 407) reads "advisory during the plan, blocking at
plan-final" and AC6 (line 449) asserts only that the gate *has a command*. Neither
implies `required: true`. I checked that the "blocking at plan-final" half is not
wishful — it is mechanically real and independent of the config flag:

    aid-plan-fsm.sh:4530-4540 — "UNION `plan_diff` — which this stage treats as
      plan-required for the plan-final run regardless of its `required: false`
      default"
    aid-plan-fsm.sh:4697-4701 — pd="$(jq -r '.gates.plan_diff.result …')";
      [[ "$pd" == "pass" ]] || _gassert "plan_diff result is '${pd}', expected 'pass'…"

So the shrink is coherent: advisory at EPIC level because eight suites do not exist
yet, blocking at plan-final by a separate, already-shipped assertion.

**3. The AC bullets rewritten to `AC1:` — DISCHARGED.**

    $ aid-plan-diff.sh --plan .aid-o/plans/P083-ten-verified-defects.md \
        --evidence-dir <tmp> --base-commit HEAD          →  EXIT=1 (correct pre-impl)
    $ jq '{ac_count, summary}'  →  ac_count 11, present 0, absent 11, skipped 0
    $ jq '[.results[] | select((.ac_label // "") == "")] | length'  →  0
    $ jq '.results | length'  →  11

All eleven rows now carry `AC1`…`AC11` with full `ac_text` (previously all `""`).
`plan-diff.json` is legible: "which AC failed?" is answerable, which was the whole
point of arming the gate in Step 5.

All eleven `cmd:` strings extracted through PyYAML (which unescapes the same
double-quoted scalars `extract_yaml_val` does) and run through `bash -n`: **11/11
clean**, including AC6, whose nested quoting unescapes to
`test -n "$(yq -r '.gates.plan_diff.command // ""' .aid-o/config/execution.yaml)"`
and executes (it returns 1 today, correctly — the command is not there yet).

**4. Tier tags after the Step 4 replacement and Step 10's t0→t1 — DISCHARGED.**
`_aid_files_bullet_tier` sourced from `lib/aid-scoping.sh` and called on each of the
ten `- Test:` bullets verbatim:

    line  73 rc=0 t1    line 203 rc=0 t1    line 311 rc=0 t1
    line 105 rc=0 t1    line 242 rc=0 t1    line 342 rc=0 t1
    line 136 rc=0 t1    line 274 rc=0 t1    line 375 rc=0 t1
    line 168 rc=0 t1

10/10 rc=0, and the plan is now uniformly `t1` — Step 10 (line 375) moved off `t0` as
AB-10 required. P082's `aid-plan-to-epic.sh:1064` refusal does not fire; all ten
suites are genuinely new (`ls` — none of the ten exist).

**5. New Files entries — PARTIAL.**
Everything mechanical passes; one entry is a file git cannot carry.

    exists: plugins/aid-orchestrator/defaults/enforcement-registry.yaml     OK (tracked)
    exists: plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats  OK (# aid-tier: t0,
            pins the two-profile output at :99-102, :108-111, :207-211 — the three sites
            Step 7's new `Modify:` bullet names at "~100-111 and ~208-212", correct)
    exists: README.md                                                       OK (line 3 = v2.69.0, as claimed)
    exists: .aid-o/config/project.yaml                                      on disk, but GITIGNORED + UNTRACKED
    absent (Create, correct): lib/aid-ac-extract.sh and all ten new bats suites

    $ aid-plan-lint.sh … → "PASS — all Files entries are canonical." (exit 0)
    $ aid-generation-readiness.sh … → "READINESS: PASS … graph: acyclic." (exit 0)
    $ jq … provisional-graph → { n_steps: 10, n_edges: 0, edges: [] }

The graph matches the declared edges exactly: every step now says "Depends on: none /
Blocks: none", and every generated `plan.json` step has `depends_on: []`. Acyclic
trivially.

The registry lands in exactly the three steps AB-9 named — confirmed in the generated
allowed_paths, not just in the prose: EPIC2 `step_1_backend` (Step 5), EPIC2
`step_2_backend` (Step 6), EPIC3 `step_1_backend` (Step 8) each carry
`plugins/aid-orchestrator/defaults/enforcement-registry.yaml`. And I re-checked P080's
branch: `git -C .aid-worktrees/plan-P080 diff --name-only main...HEAD` still lists the
registry and does NOT list `commands/aid-init.md` or `defaults/templates/` — so the
rewritten Constraint at line 494 is factually right.

PARTIAL because of `.aid-o/config/project.yaml` — see blocker 2 above. The entry is
canonical to the linter and resolves to a real path in this checkout, so no automated
check catches it; it simply cannot be committed, cannot reach a worktree, and cannot
be read by the T1 suite that depends on it.

**6. Step 3 no longer blocks Step 4 — DISCHARGED on the mechanical claim, with two residues.**
Step 4's Files list names `.aid-o/config/project.yaml`, `README.md` and the bats suite
— `aid-release.sh` is gone, confirmed in the plan text and in the generated
`allowed_paths`. The only remaining mention of `aid-release.sh` inside Step 4 is a
read-only citation in Architecture Context ("applied through `aid-release.sh:568-576`'s
`sed`"), which is a pointer, not an edit. Both steps declare no dependencies and the
provisional graph carries zero edges. The overlap is genuinely gone.

The two residues are the findings above: the Risks bullet still asserts the overlap
and mitigates it with a dependency that no longer exists (medium), and three of Step 4's
own requirements still need the `aid-release.sh` edit that the shrink removed (blocker).

## Blockers from my first pass — status

- **L2 B1 (`AID Role: docs`)** → adjudicated AB-3 → **DISCHARGED**, reproduced clean end to end.
- **L2 B2 (`required: true` on `plan_diff`)** → adjudicated AB-1 → **DISCHARGED**, and the plan-final blocking half independently verified as real.
- L2 medium "Step 5 line 203, `.aid-o/` has no history" → corrected at line 205, now states tracked-since-2026-08-04 and `git log -S` shows the command was never present. **Fixed.**
- L2 medium "Step 9 line 334, 11 steps / 2 edges" → line 346 now says "10 steps, 1 edge". Measured today it is **10 steps / 0 edges**, because the revision also deleted the one dependency the number described. A one-word residue of the same class the plan is trying to eliminate; not worth a finding of its own beyond noting it here.
- L2 medium "Step 5 line 205, exits 0" → the false claim is gone; line 209 now states "Measured: exit 1, 11 of 11 absent". **Fixed.**
- L2 medium "enforcement registry has no declared home" → **Fixed**, verified in allowed_paths.
- L2 medium "Steps 3/4 overlap" → **Fixed by removal**, with the residues noted above.
- L2 medium "Step 9 AC1 unsatisfiable as phrased" → AC1 (line 362) now reads "No shipped prompt requires an analysis of an artifact the manifest can record as absent **without naming the substitute**". The qualifier gives it a mechanical reading. **Fixed.**
- L2 low "Step 8 AC1 uses `grep -c`" → AC1 (line 329) now says "verified by reading the matched lines rather than counting them". **Fixed.**
- L2 low "AC bullets use `AC1 —`" → adjudicated into AB-1 → **DISCHARGED**, 11/11 labels populated.

confidence: high

Rationale: every verdict above is backed by a command whose output is quoted. The
generation claim is the strongest kind of evidence available — the plan was driven
through lint, readiness, all three generation phases and all three JSON conversions in
an isolated clone, and it completes. Both new blockers were established from the tree
rather than inferred: the Step 4 scope escape from a side-by-side read of the step's
declared `allowed_paths` against the code that implements the behaviour its ACs
demand, and the `project.yaml` finding from `git check-ignore`, `git ls-files`, an
empty clone and the live P080 worktree's own directory listing. The residual
uncertainty is confined to how the PM wants blocker 1 resolved — restoring the
`aid-release.sh` scope (and with it the Step 3 dependency) or dropping Step 4's
no-match-reporting requirements is a scope judgment, not a measurement.
