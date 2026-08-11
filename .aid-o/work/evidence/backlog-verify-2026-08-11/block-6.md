# Backlog verification — block 6 (OBS-20260711-01 … -05)

Repo `/opt/eco/projects/aid-orchestrator`, branch `main` @ `3da7331` (v2.83.1).
Cross-repo evidence from `/opt/eco/projects/wan` (read-only inspection).
All file:line references opened first-hand.

---

## OBS-20260711-01 — D4 CP3-Freshness-Exception has no GATES/evidence-pack equivalent

verdict: **REAL** (fix never applied; IMP-201 still `pending`)

evidence:
- The trailer mechanism exists in exactly one place: `plugins/aid-orchestrator/scripts/aid-fsm.sh:1430-1431`
  (contract comment), `:1557-1566` (per-commit `%(trailers:key=CP3-Freshness-Exception,valueonly)` loop),
  `:1579` (`cp3_freshness_exception` disclosure event). It is scoped entirely to `fsm_check_cp3_freshness`.
- `grep -rn "Freshness-Exception\|freshness_exception"` over `plugins/aid-orchestrator/` returns hits only in
  `scripts/aid-fsm.sh`, `agents/verifier.md:176`, `skills/pipeline.md:1004`, `defaults/enforcement-registry.yaml:1008`.
  **Zero hits in `scripts/aid-evidence-verify.sh` and `scripts/aid-release-policy.sh`** — the two consumers the entry names.
- The blocking path is live and unchanged: `scripts/aid-release-policy.sh:797-806` —
  `_artifact_head_match "$gates_report_path" direct` → on `false` it emits
  `add_input gates_report ... "blocked" "gates_report.json stale: revision.head_sha != HEAD (out-of-pack; not covered by --at-head verification)"`
  **plus** `add_blocker gates_report "blocking" ...`. No trailer/exemption branch anywhere in the function.
- `.aid-o/work/backlog.md:220` — IMP-201 status is still `pending` (auto-approved, never implemented).
- `docs/plans/2026-07-23-POST-P064-TO-E10-EXECUTION-CHECKLIST.md:598` still carries the open item
  "Resolve IMP-201 or explicitly keep the affected C4 control in observe" — unchecked.

what_is_true: The entry is accurate and nothing has changed in 4 weeks. A CP3 review correctly exempted under D4
(cosmetic trailing commit + trailer) still leaves `gates_report.json` stamped one commit behind HEAD, and
`aid-release-policy.sh` counts that as a hard blocker with no knowledge that the trailing commit was adjudicated cosmetic.

impact: Latent, exactly as the entry predicted. Confirmed still latent, not live:
`plugins/aid-orchestrator/defaults/policies/release-decision-policy.yaml:40-41` — `enforcement: observe`,
`head_match_policy: observe`. So today it only produces a `release_policy_dual_run` divergence event.
The moment E10 flips `enforcement: blocking`, every EPIC that legitimately used a D4 exception will compute
`release_ready=false` and be refused at review→release — the system blocking correctly-shipped work over its own gap.

fix_sketch: In `aid-release-policy.sh`'s gates_report branch (`:797`), before `add_blocker`, re-use the D4 predicate —
if every commit in `recorded_head_sha..HEAD` carries a `CP3-Freshness-Exception:` trailer, downgrade to
`pass`/advisory with an explicit `freshness_exception` reason field; factor the loop out of `aid-fsm.sh:1558-1565`
into `scripts/lib/` so both callers share one implementation instead of two.
effort: **M**

---

## OBS-20260711-02 — CP2 review scope (unit + targeted integration) misses full e2e

verdict: **PARTIALLY_FIXED** — the WAN instance is gone; the systemic half (no mechanical scope rule) is unbuilt

evidence:
- Instance side: in `/opt/eco/projects/wan` the named test no longer exists —
  `grep -rn "smlouva_unmatched" tests/` returns nothing, and `tests/e2e/test_doc_routing_e2e.py` has been reworked.
  Both commits the entry cites (`3742454`, `017cce5`) are unreachable (`git show` → "unknown revision"; branch
  squashed/deleted). The stale assertion is verifiably not in the tree.
- Systemic side: the entry's proposed mechanical rule does not exist as such. The nearest thing is
  `plugins/aid-orchestrator/scripts/aid-select-tests.sh` — a path→test **selector run as a gate command**
  (`:1-66`), with a hardcoded "Initial mapping" for **this repo's own** production roots
  (`:184` "Initial mapping (fixed — see plan Step 9)", `:234` "plugin's Initial-mapping production roots:
  scripts/ or defaults/"), optionally replaced by P066's catalog `source_pattern_mappings[]` **only when**
  `mapping_approval.status == "approved"` (`:254-280`). It is not consulted by CP2 at all and it never adds
  "run the whole e2e directory" for a routing/attach-layer edit.
- `grep -n "e2e" agents/verifier.md scripts/aid-prefilter.sh` → **no hits**. CP2's test scope is still pure
  per-step implementer/verifier judgment; the pre-filter classifies SKIP/RUN/FAIL only.
- Consumer reality check: WAN's own gate command
  (`/opt/eco/projects/wan/.aid-o/config/execution.yaml:204`) is a hand-curated ~70-file pytest list that
  includes two `tests/e2e/test_p079_*.py` files and omits the rest of `tests/e2e/` — precisely the
  "narrower than the risk surface, by hand" shape the entry describes.

what_is_true: The concrete regression was fixed and has since been refactored away. The finding's real claim —
"nothing forces the full e2e suite when a step deliberately changes shared routing/attach behaviour" — is still
true on current main, for AID and for consumers.

impact: A step that changes shared behaviour can pass CP2 green while invalidating an e2e assertion elsewhere;
detection is deferred to whichever later step happens to run the full suite (or to the merge-path gate). WAN
caught it inside the same EPIC; a project whose gate list also omits the affected e2e file would not.

fix_sketch: Cheapest honest version is not a per-project path list — add a pre-filter rule that, when a step's
diff touches any path also touched by ≥1 test outside the selected set (or simply any path listed under a new
`execution.yaml: cp2_full_suite_paths[]`), raises the CP2 classification to require the full suite and records
the reason in `verifier-output-step-N.md`. Enforced by `fsm_check_verifier_output` reading the field.
effort: **M**

---

## OBS-20260711-03 — `commit_scope_violation` companion false-positives on templated/globbed allowed_paths

verdict: **REAL**, and the live defect is broader than the entry's `{rev}` framing

evidence:
- The companion is unchanged since it was introduced: `git log -S 'if [[ "$_cf" == "$_sp" || "$_cf" == "$_sp"/* ]]' --`
  returns exactly one commit, `f2c13cc` ("P060 E2 step6 — commit-scope + branch guard").
- Current code `plugins/aid-orchestrator/scripts/aid-fsm.sh:6032-6072`: scope set is built from
  `.steps[$i].allowed_paths[]` (`:6053-6055`) and each committed file is tested with
  `if [[ "$_cf" == "$_sp" || "$_cf" == "$_sp"/* ]]; then _inscope=1; break; fi` (`:6060`) —
  **literal equality or directory-prefix only; `[[ == ]]` here has the RHS quoted, so no glob expansion.**
  Violations are logged as `commit_scope_violation` (`:6069-6071`), non-blocking as documented (`:6040-6041`).
- The asymmetry that makes this a systematic false positive: the *gate* that enforces the same rule expands globs —
  `plugins/aid-orchestrator/scripts/gates/scope-check.sh:28` ("supports globs via bash") and `:35-39`
  `case "$file" in $pattern) allowed=true ;; esac` (unquoted → real glob match). So one and the same
  `allowed_paths` entry is in-scope for the gate and out-of-scope for the telemetry companion.
- The specific `{rev}` trigger is no longer emitted by this plugin — `grep -rn "{rev}"` over
  `plugins/aid-orchestrator/` returns nothing, and `scripts/aid-plan-lint.sh:101-105` explicitly refuses
  path tokens with "placeholder brackets". That closes the entry's example, not the mechanism: any
  legitimately globbed entry (`migrations/versions/*_add_x.py`, `tests/**/test_*.py`) still fires falsely.

what_is_true: The companion's matcher is still literal while the gate's is glob-aware. `{rev}` specifically is
now lint-blocked upstream, so the entry's exact reproduction is stale, but the false-positive class it names is
live and reachable by ordinary glob usage.

impact: Signal-fatigue on the one out-of-band guard that exists specifically to catch `--no-verify` pre-commit-hook
bypasses. A reviewer who has learned to skim `commit_scope_violation` events will skim the real one too.

fix_sketch: Replace `aid-fsm.sh:6058-6062`'s literal test with the same `case "$_cf" in $_sp) ...` glob form
`gates/scope-check.sh:36-38` already uses (keep the `$_sp/*` directory-prefix arm), and add one bats case per arm.
effort: **S**

---

## OBS-20260711-04 — CP2 verifier output written to repo root instead of the evidence dir

verdict: **ALREADY_FIXED** (instance resolved; and a silent recurrence is now structurally impossible)

evidence:
- The stray file is gone and was never committed: in `/opt/eco/projects/wan`,
  `ls verifier-output*` at repo root → no such file; `git status --short` shows only
  `.aid-o/config/counter.yaml` and one untracked plan file; `git log --all -- verifier-output-step-1.md` → empty.
- The content landed in the canonical directory: `/opt/eco/projects/wan/.aid-o/work/evidence/E-062-3_3/R-E062-3/`
  now contains `verifier-output-step-0.md`, `-step-1.md`, `-step-2.md` alongside `step-0/1/2-verify.md`.
  `verifier-output-step-0.md:1-7` carries `Reviewed-Head: 686f216c…`, `checkpoint: cp2`, `verdict: pass` —
  the exact head and verdict the entry attributes to the root-level file.
- Enforcement makes the "silently missing from the evidence dir" outcome non-silent:
  `plugins/aid-orchestrator/scripts/aid-fsm.sh:5705` builds
  `local verifier_output="${evidence_dir}/verifier-output-step-${step}.md"` and `:5707` calls
  `fsm_check_verifier_output` (`:1237-1290`), whose first line is `[[ -f "$file" ]] || return 1`;
  failure reaches `die "ERROR: verifier-output-step-${step}.md missing or invalid."` at `:5729`.
  A root-only write — or a 1-based misnaming — blocks `increment-step` rather than passing.
- The numbering-drift sub-claim ("the canonical dir calls it step-0-verify.md, the output was step-1") does not
  hold on current code: both names derive from the same 0-based `$step`
  (`aid-fsm.sh:5569`/`:5609` `step-${step}-verify.md`, `:5705` `verifier-output-step-${step}.md`), and the
  completeness check at `:2468-2477` joins them by the digit extracted from the verify filename.
- Dispatch always passes an absolute evidence path: `skills/pipeline.md:828`
  `--output-file "$evidence_dir/verifier-output-step-<N>.md"`; the canonical location table is
  `defaults/templates/verifier-output-template.md:15-20`.

what_is_true: A one-off misplacement by a dispatched verifier, since corrected in the WAN evidence pack. No
AID-side code path writes verifier output cwd-relative, and the FSM precondition converts any repeat into a
loud increment failure instead of a quiet gap.

impact: None outstanding.

fix_sketch: n/a
effort: n/a

---

## OBS-20260711-05 — release automation misattributes a pre-written `[Unreleased]` section; README Roadmap likewise

verdict: **PARTIALLY_FIXED** — the destructive rename is sealed; `[Unreleased]` recognition and the README
Roadmap updater are both untouched

evidence — what IS fixed:
- `plugins/aid-orchestrator/scripts/aid-release.sh:468-475` `_release_version_sealed()` — `git tag -l "v${ver}"`,
  and it refuses to guess (`exit 1`) if it cannot list tags.
- `:490-491` the retitle branch is now conditional: `elif [[ "$header" == "$CURRENT" ]] && ! _release_version_sealed "$CURRENT"`.
  For the exact OBS scenario (CURRENT=2.54.0, tag `v2.54.0` exists) the rename no longer fires; control falls to
  `:497-515`, which prints "Sealed: v$CURRENT is tagged — its heading is preserved" and prepends a new section.
- The same seal was applied to the second, fallback retitle site: `:634-652`.
- Covered by tests: `scripts/tests/bats/test-aid-release-seal.bats` (header comment `:4-17` states the mechanism
  and asserts tagged/untagged as a pair), plus `scripts/tests/bats/test-release-changelog-entry.bats`.
- A placeholder-content check exists (`:682-700` and its two call sites) so a release cannot ship with
  "_PM/agent: fill in entry content_" as its entire description.

evidence — what is NOT fixed:
- `grep -n "Unreleased" scripts/aid-release.sh` → **no hits**. The header probe is still numeric-only:
  `:378` and `:482` both `_release_probe_first "$file" '## \[\K[0-9]+\.[0-9]+\.[0-9]+'`. A pre-written
  `## [Unreleased]` section is invisible to the script: it is never promoted to `## [X.Y.Z]`, and the prepend
  branch (`:499-513`, `head -4` + new stub + `tail -n +5`) inserts a **stub above it**, leaving the real pending
  content orphaned under `[Unreleased]` and the shipped section empty of the actual changes.
- The seal only holds when the current version is tagged. On a project that does not tag releases (or a
  re-cut before tagging), `:492` still executes `sed -i "s/## \[$CURRENT\].*/## [$NEW_VERSION] — $TODAY/"` —
  the original misattribution, unchanged.
- README half: no Roadmap awareness anywhere. The fallback path is still the blind global substitution the
  entry named — `:665-670`
  `for readme in $(find ...); do if grep -q "v$CURRENT" ...; then sed -i "s/v$CURRENT/v$NEW_VERSION/g" "$readme"`.
  For this repo the config path is used instead, and it is the same shape: `.aid-o/config/project.yaml:27-32`
  registers `README.md` as `type: regex` with patterns `\*\*v{VERSION}\*\* (current)` and the tagline pattern,
  executed at `aid-release.sh:574-577` (`SEARCH`/`REPLACE` = pattern with `{VERSION}` substituted, then
  `sed -i "s|$SEARCH|$REPLACE|g"`). Either way only the **version token** moves; the previous release's
  description stays attached to the new number, and no "insert a new top line, push the old one down" step exists.
- No post-release content self-check (the entry's suggestion (c)) — the only validator (`:682-700`) checks the
  CHANGELOG section for absence/placeholder/emptiness, never that the text matches the shipped diff, and never
  looks at README at all.
- Live corroboration of the same defect class right now: `README.md:3` still reads
  "…plugin for [Claude Code](…).** v2.69.0" while the project is at v2.83.1 — the registered tagline pattern
  (`project.yaml:30-32`) has been out of sync for 14 releases. `README.md:120` carries a correct v2.83.1 Roadmap
  line, i.e. the Roadmap is being maintained by hand, exactly as before.

what_is_true: The half that destroyed history (renaming a released heading) is genuinely closed and tested.
The half the entry called "still live and unfixed" — README Roadmap — is still live and unfixed, and the
`[Unreleased]` convention the entry identified as the 4th trigger is still unrecognized by the script.

impact: A release cut through `aid-release.sh` on a repo using `[Unreleased]` produces a CHANGELOG with a stub
section for the new version and the real content stranded under `[Unreleased]` (loud, since the placeholder
check blocks the commit — so this is now noisy-wrong rather than silently-wrong). The README Roadmap is
silently wrong: the new version inherits the previous release's one-line description, with nothing to catch it.

fix_sketch: (a) in `update_changelog` add a first branch — if `grep -q '^## \[Unreleased\]'`, rewrite only that
heading to `## [$NEW_VERSION] — $TODAY` and return; (b) replace the README Roadmap substitution with a
Roadmap-aware updater that inserts a new `- **v$NEW_VERSION** (current) — _fill in_` line, demotes the old top
line verbatim (strip its `(current)`), and let the existing placeholder validator cover the new line too.
(a) is S on its own; (b) plus the shared validator is the bulk.
effort: **M**
