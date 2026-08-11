# CP1-deep rev1 — C0 lens idempotency_matrix — P083

Re-run of the idempotency lens over `.aid-o/plans/P083-ten-verified-defects.md`
at revision 1 (`c0458cb`), against the adjudicated blocker set in
`cp1-adjudicator.md`. Repo `/opt/eco/projects/aid-orchestrator`, main, v2.83.1.

All reproduction ran in `git clone --local` and scratch fixtures under
`/tmp/claude-1000/-opt-eco-projects-aid-orchestrator/50d5999a-d6f6-42c1-a512-479b5d12dbb9/scratchpad/`
(`r1/clone`, `s4`, `s8`). The real repo was read only; `aid-release.sh` was
never run inside it.

Verdict per requested item:

| # | Item | Verdict |
|---|------|---------|
| 1 | AB-8 — Step 3 count / rollback / staging | **DISCHARGED** (two residues, both LOW/MEDIUM) |
| 2 | AB-4 — Step 9 second-writer hazard | **DISCHARGED** |
| 3 | AB-10 — Step 10 convergence on the half-annotated file | **DISCHARGED** |
| 4 | Step 8's shrink — legacy read→write→read | **DISCHARGED** |
| 5 | Step 4's rewrite — idempotence of the pattern fix | **NOT DISCHARGED** — the prescribed fix corrupts the file and re-freezes the line |
| 6 | New hazards introduced by the edits | **two found** — one HIGH (Step 4, same as item 5), one MEDIUM (dependency edge deleted, Risks/Architecture now contradict the steps) |

stop_rule_blockers:

- **R1 (High, reproduced) — Step 4's prescribed escaping fix is itself
  non-idempotent: it corrupts `README.md:3` on the first release and re-freezes
  it on the second.** The plan (line 166) prescribes that the `\(` … `\)` in the
  `project.yaml` row-3 pattern "become bracket expressions (`[(]`, `[)]`)".
  `aid-release.sh:574-576` derives BOTH the search and the replacement from the
  same single `pattern` string:
  `SEARCH=$(echo "$FILE_PATTERN" | sed "s/{VERSION}/$CURRENT/g")`,
  `REPLACE=$(echo "$FILE_PATTERN" | sed "s/{VERSION}/$NEW_VERSION/g")`,
  `sed -i "s|$SEARCH|$REPLACE|g"`. sed's replacement side is a literal string:
  `\*` and `\[` de-escape to `*` and `[`, but `[(]` carries no backslash and is
  written through **verbatim**.
  Reproduced (`scratchpad/s4/run.sh`), starting from the real line 3 set to the
  current version:
  ```
  release 1 (2.83.1→2.83.2):
    **Multi-agent orchestration plugin for [Claude Code][(]https://claude.com/claude-code[)].** v2.83.2
  release 2 (2.83.2→2.83.3):
    **Multi-agent orchestration plugin for [Claude Code][(]https://claude.com/claude-code[)].** v2.83.2   <-- no-op
  ```
  Two failures in one: the rendered markdown link is destroyed, and the search
  side (where `[(]` is a bracket expression matching a literal `(`) no longer
  matches the now-literal `[(]` in the file, so line 3 **freezes again at
  v2.83.2, permanently** — the exact defect AB-2 was raised to close, restored
  one release later and now with a broken link on top.
  This passes Step 4's own AC1 ("the row-3 pattern substitutes on a line
  containing literal `(https://…)`") — it does substitute — and passes AC2's
  first release. Only a **second** release exposes it, so a single-release test
  cannot catch it. This is precisely the "AC that would fail on a second run"
  class.
  The config schema cannot express a search-side-only escape: `aid-release.sh:558-561`
  reads exactly `path`, `type`, `field`, `pattern` — one pattern, both sides.
  **The fix that works** (reproduced, `scratchpad/s4/run2.sh`): leave the
  parentheses **bare**. POSIX BRE treats an unescaped `(` as a literal, which is
  why the sibling `\*\*v{VERSION}\*\* (current)` row has tracked correctly for
  fourteen releases. Three consecutive releases with the bare-paren pattern:
  ```
  v2.83.1 → v2.83.2 → v2.83.3 → v2.83.4, link intact at every step
  ```
  Step 4 must specify bare parentheses (or add a separate `search`/`replace`
  pair to the schema and to `aid-release.sh:558-576`), and its suite must assert
  **two consecutive** substitutions plus link integrity, not one.

findings:

- **F1 (item 1, AB-8) — DISCHARGED for the count/rollback/staging agreement.**
  Simulated the described fix in `r1/clone` (added `UPDATED+=("$jf")` to the
  `.metadata.version` and `.plugins[0].version` branches and `UPDATED+=("$readme")`
  to the `Plugin: ` branch, then `mapfile -t UPDATED < <(printf '%s\n' "${UPDATED[@]}" | sort -u)`
  immediately before `echo "Updated ${#UPDATED[@]} files total."`), and re-ran
  the three cases the first pass failed on.
  - Abort/rollback case (`prepare-plan P999 --bump patch`, CHANGELOG placeholder
    → validation refusal): `Updated 5 files total`; rollback line named exactly
    5 distinct paths (`.claude-plugin/marketplace.json CHANGELOG.md README.md
    plugins/aid-orchestrator/.claude-plugin/plugin.json plugins/aid-orchestrator/CHANGELOG.md`)
    — `marketplace.json` appears **once**, not twice; `git status --porcelain`
    empty afterwards. The first pass's `Updated 6 files total` / duplicated
    rollback entry is gone.
  - Staging case (CHANGELOGs pre-written, successful prepare): `Updated 4 files
    total`, staging loop staged the 4, commit contains the 3 that actually
    changed. Staged set ⊆ counted set, no duplicate `git add`.
  - Pre-dirty case (`printf '\nPM local note\n' >> README.md`, then legacy
    `aid-release.sh patch` with a placeholder CHANGELOG): `Updated 5 files
    total`, rollback restored 4, `README.md` kept its bump and stayed ` M`.
    That is exactly what the **re-worded** AC2 now permits — "the printed count
    equals the number of distinct files this run edited, **and every one of them
    that was not already dirty is restored**" — so the AC is now satisfiable,
    where the old wording was not. The pre-dirty exclusion is now declared
    (plan:142) rather than discovered.
  Count, rollback set and staged set agree. **DISCHARGED.**

- **F2 (Medium, new, follows from F1) — Step 3's "Declared consequence" names a
  file that will not in fact be staged.** Plan:147 states "the prepare commit
  now also stages `marketplace.json` **and the plugin README**". Measured: the
  fallback's guard is `grep -q "Plugin: $CURRENT" "$readme"`, and the file reads
  `- **Plugin:** 2.83.1` — `grep -c 'Plugin: 2.83.1' plugins/aid-orchestrator/README.md`
  → **0**, and `grep -c 'v2.83.1' plugins/aid-orchestrator/README.md` → **0**.
  The `Plugin: ` branch at `:672-675` therefore never fires in this repo, so
  the `UPDATED+=` Step 3 adds to it is dead code and the plugin README is
  neither edited nor staged on the fallback path. (On the config path it was
  already in `UPDATED[]` via the temp-file readback at `:663-671`, so it is not
  "now also" staged there either.) Consequence beyond the wording: in every
  worktree/clone release — the live plan-final path, per Step 3's own
  Implementation Detail — the plugin README's version line is **never bumped at
  all**, a registry file silently left behind. Either correct the declared
  consequence, or widen the branch's grep and say so.

- **F3 (Low, new, follows from F1) — the printed count still over-reports by one
  on the normal plan-final path.** `aid-release.sh:518-529` appends
  `$REPO_ROOT/CHANGELOG.md` to `UPDATED[]` **unconditionally**, including when
  `update_changelog` took its `header == NEW_VERSION` no-op branch
  ("Skipped: … pre-written entry"). Measured in the successful prepare run:
  `Updated 4 files total` while only 3 files were edited (the commit contains 3).
  So AC2's first clause ("equals the number of distinct files the run edited")
  is false on exactly the pre-written-CHANGELOG flow a plan-final release uses.
  `sort -u` does not address it — the entry is not a duplicate, it is a
  no-op-still-recorded. `:518-529` is not in Step 3's Files list. Same class as
  the "no-match sed still prints Updated" defect Step 4's AC3 fixes for regex
  rows; the natural home is Step 3.

- **F4 (item 2, AB-4) — DISCHARGED. The second-writer hazard is removed
  completely.** Step 9's Files list (plan:340-342) now names only
  `defaults/prompts/c0-plan-review-prompt-v1.md` and a new bats suite. No
  `--write-provisional` invocation, no edit to `lib/aid-c0-plan-review.sh`.
  Verified the writer set is unchanged: `grep -rn 'write-provisional|provisional-graph.json'`
  over `scripts/` + `defaults/` returns one production writer
  (`aid-plan-to-epic.sh:136`), the flag parser in `aid-generation-readiness.sh:21`,
  the consumer `aid-generation-finalize.sh:112`, the probe
  `lib/aid-c0-plan-review.sh:385`, and test fixtures only. The seal at
  `aid-generation-finalize.sh:112-119` keeps its single-writer invariant, and
  the `set -euo pipefail` / stdout-channel hazards disappear with the call.
  The remaining edit is a static text change to a shipped prompt — idempotent
  by construction (no runtime mutation at all).
  ACs are satisfiable and non-vacuous:
  - AC1 ("no shipped prompt requires an analysis of an artifact the manifest can
    record as absent without naming the substitute") **fails today** — the
    prompt's "What you were given" line 32 reads "Whole-plan source dependency
    graph (**the pre-generation authority**): `{{source_plan_graph_path}}`" and
    check-table item 2 asks "is the dependency graph acyclic and satisfiable?"
    So it is a real, currently-red assertion.
  - AC2 ("`provisional-graph.json` still has exactly one writer after this
    step") is grep-checkable and is a genuine guard against the design the
    review reverted, not a tautology.
  - AC3 (existing C0 suites green) is checkable — `test-c0-plan-review.bats:446-474`
    already covers the hash-binding refusal the step promises not to loosen.

- **F5 (item 3, AB-10) — DISCHARGED. A second full run of Step 10 is a no-op.**
  Measured current state: `grep -c 'verified 2026-08-11' docs/plans/2026-06-29-BACKLOG.md`
  → **32**; all 32 read "against v2.82.0"
  (`grep -c 'verified 2026-08-11 against v2.82.0'` → 32); they sit on **32
  distinct headings** (`awk '/^#+ /{h=$0} /verified 2026-08-11/{print h}' | sort -u | wc -l`
  → 32), matching the plan's "32 of the 46".
  The revised rule (plan:381) — "keyed on the entry id and REPLACED, never
  appended; where the older annotation and this verification disagree, the
  verification wins and the older line is deleted, not stacked", plus "the
  anchor version discrepancy is resolved in the same edit so the file states one
  date and one baseline" — makes the operation a projection: run 1 maps
  {no verdict, v2.82.0 verdict} → {single v2.83.1 verdict}; run 2 maps
  {single v2.83.1 verdict} → the same line. Converges on the current
  half-annotated file, which is the state that actually exists.
  The suite now asserts **at most one** verdict line per entry (plan:375),
  closing the first pass's F5 hole where two non-contradictory verdict lines
  from two anchors passed. The `test-deferred-work-registration.bats:123`
  `^#+ .*IMP-nnn` consumer is named (F11 of the first pass discharged too).
  Caveat, not a blocker: 19 entries currently carry **two** `**Status:**` lines
  each (e.g. `OBS-20260702-03`, `OBS-20260702-05`, `B-004`, `B-006` — measured
  by per-heading awk count), so "at most one verdict line per entry" needs an
  entry-boundary definition the plan does not give. The heading scan is the
  obvious boundary and the plan already names it; state it, or the suite's own
  entry-splitting becomes the untested part.

- **F6 (item 4, Step 8's shrink) — DISCHARGED. The new shape converges, and the
  AC is checkable.** Reproduced (`scratchpad/s8`): built a legacy baseline entry
  with four sequential samples plus populated
  `recent_samples_by_context.observe_parallel` and
  `percentiles_by_context.observe_parallel`, then deleted both maps (the
  post-Step-8 written shape) and compared every read surface via
  `AID_GATE_BASELINE_FILE`:
  ```
  WITH maps:    legacy_gate [fp:aaaa, last sample 2026-01-04T00:00:00Z]: p95 9s, recommended insufficient data, timeout 2m
  WITHOUT maps: legacy_gate [fp:aaaa, last sample 2026-01-04T00:00:00Z]: p95 9s, recommended insufficient data, timeout 2m
  gate_baseline_report_json: byte-identical both ways
    {"samples_count":4,"non_censored_samples_count":4,"p95_ms":9000,
     "timeout_recommended_seconds":30,"run_mode_recommended":"foreground",
     "data_sufficient":true,"last_attempt_result":"pass","policy_result":"none",
     "retryable":true,"operator_action":null}
  ```
  Cause: every reader (`gate_baseline_show:783-806`,
  `gate_baseline_report_json:834-846`, `gate_baseline_policy_check`,
  `gate_baseline_recommend_*`) reads only sequential-owned top-level fields
  (`.p95_ms`, `.recent_samples`, `.non_censored_samples_count`), never
  `*_by_context`. `grep -rln by_context plugins/aid-orchestrator/` returns
  **exactly one file** — the writer library itself. So read→write→read on a
  legacy file with populated maps: the maps are dropped, the percentiles are
  unchanged, and the second read equals the first. The first pass's F6 (empty
  maps making read→write→read non-convergent) is dissolved by the shrink rather
  than repaired — dropping the fields is strictly more convergent than emitting
  them empty.
  AC checkability: AC-"a legacy baseline file carrying `*_by_context` data reads
  without error and yields the same percentiles as before" is checkable — the
  fixture above is exactly the test, with hard-coded expected numbers.
  AC-"the live baseline's percentiles are numerically identical before and
  after" is **only checkable manually**, because a bats suite running after the
  change has no "before". Note it as a one-time pre/post verification rather than
  a suite assertion, or capture the current values as a committed fixture. Not a
  blocker and not new to rev1 — carried over.

- **F7 (item 5, Step 4) — NOT DISCHARGED.** See R1 above. The manual repair half
  IS idempotent (applying `s|\*\* v[0-9][0-9.]*$|** v2.83.1|` twice yields the
  same line — reproduced), and once line 3 carries the current token the
  FALLBACK path also repairs it (`grep -q "v$CURRENT"` matches, `sed
  "s/v$CURRENT/v$NEW/g"` rewrites line 3 — reproduced). Second release with the
  **correct** pattern is a clean bump, and a same-version rerun is a no-op.
  So the step's shape is right; its prescribed escaping is wrong and
  self-corrupting.
  One re-freeze state survives even with the correct pattern, and Step 4 does
  not close it: on the fallback path, `grep -q "v$CURRENT"` matches line 120,
  the whole-file `sed` misses a stranded line 3, and the run still prints
  `Updated: README.md (readme version refs)`. Reproduced. Step 4's AC3
  ("a configured pattern that matches nothing is reported by name") covers the
  **config** path only — and Step 3's own Implementation Detail establishes that
  worktrees, i.e. plan-final releases, take the **fallback**. So the miss
  detector is armed on the path the plan says is not the live one. Any manual
  bump that skips line 3 (the CLAUDE.md release workflow bumps six files by hand)
  re-strands it silently and permanently.

- **F8 (item 6, Medium, new) — the revision deleted the only dependency edge in
  the plan and left three passages asserting it still exists.** Rev 0 declared
  Step 3 `Blocks: Step 4 — both edit the same fallback block and Step 4's test
  reuses this step's fallback fixture` and Step 4 `Depends on: Step 3`
  (`git show c0458cb~1` lines 150-151, 181-182). Rev 1 sets **all ten** steps to
  `Depends on: none` / `Blocks: none`. Deleting the edge is defensible given the
  shrink — Step 4 no longer touches the fallback block at all — but three
  statements were not updated with it:
  1. Risks (plan:506): "**Step 3 and Step 4 edit the same block.** Mitigation:
     explicit dependency and a shared fallback fixture" — there is no longer an
     explicit dependency, and they no longer edit the same block.
  2. The adjudicator's rejection of the "Steps 3 and 4 overlap" blocker rested
     on "the dependency is declared in both directions and the generated graph
     carries exactly that edge". That premise is now false; the generated graph
     will carry **zero** edges (the plan's own advisory note about "10 steps, 1
     edge" referred to this edge).
  3. Architecture, group 3 (plan:61) still reads "dead vocabulary is deleted;
     **the graph is produced earlier, because its producer needs nothing but the
     plan file**; and the backlog is reconciled" — a verbatim description of the
     Step 9 design AB-4 reverted. The Architecture section still specifies the
     hazard the step no longer contains.
  Not an idempotency defect in itself, but a real second-writer risk if an
  implementer reads Architecture rather than the step. Fix: delete the graph
  clause from plan:61, and either restore the ordering edge or rewrite the Risks
  bullet to what is now true (Step 3 edits the fallback; Step 4 edits
  `project.yaml` and `README.md:3`; the only shared surface is `README.md`, and
  either order converges).

- **F9 (Low, new) — Step 5's Implementation Detail contradicts itself four lines
  apart.** Plan:207 says "`aid-plan-diff.sh` **runs clean** against this plan";
  plan:209 says "Measured: exit 1, 11 of 11 absent". Both cannot be read the same
  way. I re-measured against rev 1: `aid-plan-diff.sh --plan
  .aid-o/plans/P083-ten-verified-defects.md --evidence-dir $(mktemp -d)
  --base-commit HEAD` → **EXIT=1**, `{"ac_count":11,"summary":{"present_count":0,
  "absent_count":11,"skipped_count":0}}`. The gate parses the plan fine; it fails
  because the suites do not exist yet. Say "parses cleanly, exits 1 because the
  suites are not built yet" once, in one place.

- **F10 (positive confirmation) — AB-1's label half is discharged.** The
  plan-level AC bullets were re-written from `AC1 — …` to `AC1: …`. Re-measured
  on rev 1: every row now carries a real label —
  `[{"ac_label":"AC1","ac_text":"The streamlined integration review reads the
  gates report where gates write it.",…},{"ac_label":"AC2",…},…]` — where the
  first pass measured `"ac_label": ""` on all eleven. Also confirmed
  `**AID Role:** docs-writer` at plan:401 (AB-3).

- **F11 (carried, still open) — the first pass's F7/F8 remain unaddressed and
  the adjudicator kept them advisory.** `grep -n 'trap ' aid-release.sh` → still
  no matches; the config-path loop still appends to `/tmp/aid-release-updated-$$`
  (`:663-671`), read back and `rm -f`'d only if the reader is reached. Step 3
  owns `UPDATED[]` bookkeeping and adds a `sort -u` to it; adding `mktemp` +
  `trap` in the same edit is nearly free, and the alternative — one sentence
  saying interrupt-resume is out of scope — costs nothing. Neither is in rev 1.

confidence: high

Grounds: item 1 was reproduced end-to-end in `r1/clone` with the described fix
mechanically applied, across all three cases (abort, success/staging, pre-dirty),
with the printed count, the rollback line and the commit's file list compared
directly. Item 5's blocker was reproduced twice — the corrupting `[(]` form and
the working bare-paren form — over three consecutive simulated releases each,
using the exact `SEARCH`/`REPLACE`/`sed -i "s|…|…|g"` construction read off
`aid-release.sh:574-576`, and the one-pattern-for-both-sides constraint was read
off `:558-561`. Item 4 was reproduced on a purpose-built legacy fixture with
populated maps through both public read surfaces, with byte-identical output.
Items 2 and 3 are read off named file:line and measured counts in the real repo
(`grep -rn` writer enumeration, `grep -c`/awk over the backlog). Item 6's
dependency regression is a direct `git show c0458cb~1` vs working-tree diff.
Lower confidence only on F3's blast radius: I measured the over-count on one
pre-written-CHANGELOG run and did not enumerate every `VERSION_SOURCE` branch.
