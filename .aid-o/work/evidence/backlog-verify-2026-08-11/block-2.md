# Backlog verification — block 2 (2026-08-11, main @ v2.83.1)

All verdicts below rest on files opened first-hand in this session. Live
experiments ran in `git clone --local` copies under the session scratchpad
(`exp268.sh`, `exp_ac.sh`); the repo was not modified.

---

## IMP-261 — Project-scoped configuration and INIT/SETUP redesign
verdict: REAL

evidence:
- `plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh:142` —
  `CODEX_MODEL="${AID_C3_CODEX_MODEL:-gpt-5.6-terra}"`. Environment variable is
  the ONLY override; no YAML surface.
- `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh:118-120` —
  `# CODEX_MODEL is a plain global (sourced default "gpt-5.6-terra")` /
  `CODEX_MODEL="${AID_C0_CODEX_MODEL:-$CODEX_MODEL}"`. C0 genuinely inherits
  C3's default, exactly as the entry says.
- `plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh:1112-1113` —
  `-m "$CODEX_MODEL" \` / `-c model_reasoning_effort=high \`. This is the
  single shared transport (its own header at :1085 says it is also "the C0
  plan-review Codex launch"), and the reasoning effort is a literal. Repo-wide
  grep for `model_reasoning_effort` returns this one non-test line.
- `plugins/aid-orchestrator/defaults/execution.yaml` and
  `defaults/orchestration.yaml` — grep for `codex` returns nothing. There is no
  tracked project surface for any of this.
- Live evidence from the most recent real plan review:
  `.aid-o/work/evidence/P080/c0/codex/c0-dispatch.json` records
  `executor.reported_model = "gpt-5.6-terra"` and has NO reasoning-effort field
  anywhere (`jq keys` = artifact_type, created_at, dispatch, executor,
  independence, producer, prompt, provenance, schema_version, subject). C0 ran
  on terra, not the desired `sol`, and the effort is unrecorded.
- Nothing has closed it: `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md:133-142`
  claims to "explicitly discharge the **analysis** portion of IMP-261" and
  itself re-confirms the same gap ("C0/C3 models have environment-only
  overrides while their shared Codex transport hard-codes
  `model_reasoning_effort=high`"), then explicitly defers the settings schema
  to "a separate next plan". That plan (P080) is written but not merged.

what_is_true: Every concrete claim in the entry checks out against live code,
including the one that is easiest to get wrong (that C0 and C3 share one Codex
transport with a literal `high`). Configuration for Codex actions exists only as
environment variables read at source time; there is no tracked, reviewable
project surface and no `config effective` view. The recently written entrypoint
plan claims the *analysis* half, but its own deliverable (the disposition table)
is not in the tree and the implementation is deliberately out of its scope.

impact: A consumer project cannot durably pick per-action model/effort without
patching the plugin or exporting shell variables; two projects on the same
plugin version can silently behave differently, and the resulting evidence does
not record the effort actually used, so an audit cannot reconstruct the run.

fix_sketch: Not a one-shot fix — the entry's own first deliverable (the setting
inventory + precedence document under `docs/plans/`) is the correct next unit;
the cheapest *partial* is a codex action-profile block in a tracked config read
by `aid-c3-dispatch.sh` at :142/:1112-1113 and stamped into `c0-dispatch.json`.

effort: L

---

## IMP-268 — Debug CLI path that can mint `lineage: proven`
verdict: REAL

evidence:
- `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh:1639` —
  `add-epic) plan_manifest_add_epic "$@"; exit $? ;;`. Raw `"$@"` pass-through.
- `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh:997-1000` —
  `plan_manifest_add_epic()` takes `lineage="${8:-unproven}"`; :1008 accepts
  exactly `proven` or `unproven`. So the CLI's 8th positional IS a lineage
  argument.
- `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh:1622` (usage) and
  `:200` (header USAGE block) both document `add-epic` with SEVEN positionals —
  the lineage argument is undocumented on the CLI surface, which is what makes
  it a hidden writer rather than a declared one.
- The contradicted claim, verbatim, at
  `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh:8297-8298`: "The only two
  sources of lineage:proven in the whole system are (1) a normal epic-start …",
  echoed at `aid-plan-fsm.sh:2693` ("the only two sources of lineage:proven
  remain …").
- Live experiment (scratchpad clone, `exp268.sh`):
  `bash aid-plan-manifest.sh add-epic P999 E-999-1_2 R-1 task/E-999-1_2 <sha> plan/P999 .aid-o/work/evidence/E-999-1_2/ proven`
  → `add rc=0`, and `get ... .epic_runs[0].lineage` → `proven`.
- Same experiment, a fourth writer the entry does not mention:
  `bash aid-plan-manifest.sh update P999 '.plan_boundary_manifest.epic_runs[1].lineage = "proven"'`
  → `update rc=0`, lineage flips `unproven` → `proven`. The dispatcher at :1642
  routes `update` to `plan_manifest_update` with an arbitrary jq filter, and the
  protocol validator does not object to a lineage value it did not authorise.
- IMP-265's fail-closed default is genuinely in place (omitting the 8th arg
  yields `unproven`), so the *omission* hole the entry mentions is already shut.
  The *explicit* hole is not.

what_is_true: The entry is right and understates the problem. `add-epic` is an
undocumented third writer of `lineage: proven`, and the same CLI's `update`
subcommand is an unconstrained fourth writer that can flip an existing entry.
Both are reachable by anything that can run the script, and the code's own
"only two sources" comment is therefore false in two places.

impact: `aid-plan-fsm.sh:1080` and `:3435` treat `lineage == proven` as
authorisation to trust a task branch as authoritative and to mint the delivery
claim. Anything that can invoke this script — a stray automation, a repair
script, a copy-pasted debug line — can hand itself that authorisation without
any Git ancestry ever being observed, and no audit event marks it.

fix_sketch: Drop the 8th positional from the `add-epic` CLI dispatcher (force
`unproven` on the standalone path) and gate `update` against writing
`.lineage`, both behind an explicit audited maintenance flag; then correct the
"only two sources" comments to enumerate what remains.

effort: S

---

## IMP-274 — no-`grep -oP` portability invariant across all shell sources
verdict: REAL

evidence:
- The guard: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats:7221-7228`
  (`_imp274_scan`) — `grep -n 'grep -oP' "$f"` over `find "$dir" -name '*.sh'`.
  Two independent narrowings, both confirmed: it matches the LITERAL string
  `grep -oP`, and it only walks `*.sh`.
- Allowlist at `:7234-7239`: `aid-release.sh`=3, `lib/delivery-checks/dg08-runtime-env.sh`=1,
  `tests/test-instruction-consistency.sh`=2, `aid-fsm.sh`=1 ("`:1411` step_n").
- What the guard actually sees today (re-ran `_imp274_scan`'s exact logic over
  `plugins/aid-orchestrator/scripts`): `aid-fsm.sh` 1,
  `lib/delivery-checks/dg08-runtime-env.sh` 1,
  `tests/test-instruction-consistency.sh` 2. **`aid-release.sh` scores 0** — its
  real call site is `aid-release.sh:341`
  `out="$(grep -m1 -oP "$pattern" "$file")"`, which does not contain the literal
  `grep -oP`. The allowlist therefore grants 3 free slots in a file that has
  none, and the line-number annotation for `aid-fsm.sh` is stale (the site is
  now `aid-fsm.sh:2475`, not `:1411`).
- ACTUAL live PCRE call sites across the whole tree, non-comment, `.sh` + `.bats`
  — **13 lines in 6 files**, of which the guard sees 4:
  - `scripts/aid-release.sh:341` — `grep -m1 -oP` (INVISIBLE)
  - `scripts/lib/aid-review-signals.sh:24` and `:25` — `grep -qP` (INVISIBLE,
    and this is production library code, not tooling)
  - `scripts/lib/delivery-checks/dg08-runtime-env.sh:109` — `grep -oP` (seen)
  - `scripts/tests/test-instruction-consistency.sh:90`, `:130` — `grep -oP` (seen)
  - `scripts/tests/test-instruction-consistency.sh:158`, `:169`, `:180` —
    `grep -rohP` (INVISIBLE; the file is allowlisted at 2 but really has 5)
  - `scripts/tests/bats/test-aid-release.bats:56`, `:92` — `grep -oP` (INVISIBLE:
    `.bats` is not scanned at all)
  - `scripts/aid-fsm.sh:2475` — `grep -oP` (seen)
- The worst of the invisible ones, opened in full:
  `plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh:22-29`,
  `_aid_read_toggle()` — `if grep -qP … && grep -A5 … | grep -qP …; then return 1; fi; return 0`.
  On a grep without PCRE both `-qP` calls fail (exit 2), the `if` is false, and
  the function returns 0 = **enabled**. An explicit `enabled: false` in
  `execution.yaml` is silently ignored — exactly the fail-open the invariant was
  created to stop.

what_is_true: Both halves of the prior review hold. The detector matches one
literal spelling of one PCRE flag combination in one file extension, so 9 of 13
live PCRE call sites are invisible to it — including two in a production library
whose failure mode is fail-open, and three more in a file the allowlist already
names (so the count there is wrong even for a file it does watch). The
`aid-release.sh` allowlist row is pure slack: 3 permitted, 0 detected.

impact: On any host whose grep lacks PCRE (BSD/macOS default, busybox, a
minimally-built GNU grep), `_aid_read_toggle` silently re-enables reviewer
toggles a project turned off, and `aid-release.sh:341` version extraction
fails; the guard stays green throughout and the allowlist quietly licenses three
new violations in `aid-release.sh`.

fix_sketch: Widen `_imp274_scan` to `grep -nE 'grep [^|;&]*-[a-zA-Z]*P'` over
`*.sh` + `*.bats`, re-baseline the allowlist from the measured 13, and convert
`aid-review-signals.sh:24-25` to POSIX ERE (it needs no PCRE).

effort: S

---

## Shipped `defaults/execution.yaml` has no `gate_profiles` block
verdict: WRONG_ADDRESS — but a real defect exists at the address it should have named

evidence:
- The literal claim is TRUE: `grep -n gate_profiles plugins/aid-orchestrator/defaults/execution.yaml`
  returns nothing.
- It does not matter, because that file has **no runtime reader**. A repo-wide
  grep for `defaults/execution.yaml` outside CHANGELOG returns only test files
  (`tests/test-instruction-consistency.sh:108`,
  `tests/bats/test-tier-gate-routing.bats:32`,
  `tests/bats/test-run-mode-field.bats:28`,
  `tests/bats/test-service-declaration.bats:55`,
  `tests/bats/test-owned-jobs-integration.bats:977-979`) plus a comment at
  `aid-plan-fsm.sh:9863`. No script copies it into a project.
- What consumers actually get: `plugins/aid-orchestrator/commands/aid-init.md:119-125` —
  `compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"`,
  implemented in `scripts/lib/aid-init-execution-yaml.sh:329`, which at :395
  calls `render_gate_profiles_block`.
- `scripts/lib/aid-init-execution-yaml.sh:206-265` — `render_gate_profiles_block`
  emits, at most, **two** profiles: `targeted` and `full` (the here-doc at
  :256-265). The canonical vocabulary is **five**: this repo's own
  `.aid-o/config/execution.yaml:297-302` says "the five canonical risk profiles
  … (quick < targeted < standard < full < release)".
- The zero-stacks branch is NOT the hole: :239-242 emits only the comment
  `# gate_profiles: no stacks detected …`, and the FSM guard
  `_pfsm_has_gate_profiles` (`aid-plan-fsm.sh:9869-9880`) then falls back to
  `legacy_epic_release_mode` with the logged reason
  `plan_branch_unavailable: no_gate_profiles` (`:9895-9899`). That path is
  handled and audited.
- The hole is the OPPOSITE case. `defaults/policies/plan-boundary-policy.yaml`
  ships `default_mode: plan_branch` and `plan_final_profile_floor: release`. A
  consumer WITH detected stacks gets `{targeted, full}`, so
  `_pfsm_has_gate_profiles` returns 0, the plan flips to `plan_branch` — and then
  `aid-plan-fsm.sh:4485` runs `resolved="$(gate_profile_max "$required_profile" release)"`
  (always ≥ `release`) and `:4490-4493` aborts:
  `PRECONDITION FAIL: plan-finalize --stage gates: profile 'release' has an empty or missing include[]`.
  `aid-run-gates.sh:1588-1591` fails the same way for a direct `--profile release`.
- The recorded comment the prior review flagged as "DELIBERATE", verbatim
  (`aid-plan-fsm.sh:9861-9868`): "P064 adds it to THIS repository's self-host
  execution.yaml, not to the defaults/execution.yaml that /aid-init distributes,
  so a consumer project that merely upgrades the plugin would flip to plan_branch
  and resolve its gates against nothing at all." Read in full, this is a
  *rationale for the guard*, not a decision to leave defaults short — and the
  same wording is repeated in `defaults/policies/plan-boundary-policy.yaml`. I
  would not call it a recorded intentional omission; it explains why absence is
  survivable, and absence IS survivable. Partial presence is not.

what_is_true: `defaults/execution.yaml` is a dead template as far as the runtime
is concerned, so seeding `gate_profiles` into it would fix nothing — the entry
names the wrong artifact. The generator that consumers actually run,
`render_gate_profiles_block`, emits two of the five canonical profiles and never
emits `release`, while the shipped plan-boundary policy makes `release` the
mandatory plan-final floor. The all-or-nothing guard the code relies on
(`_pfsm_has_gate_profiles`) only tests that the table is non-empty, so a
consumer clears the guard on `targeted`+`full` and then dies at plan-finalize.

impact: any consumer project with a detected stack that runs a plan to its
release boundary hits a hard PRECONDITION FAIL at the last stage of the plan,
after all EPIC work is done. (Self-host is immune — this repo hand-authored all
five profiles.)

fix_sketch: Extend `render_gate_profiles_block` to emit all five canonical
profiles (quick ⊂ targeted ⊂ standard ⊂ full ⊂ release) and tighten
`_pfsm_has_gate_profiles` to require the profile named by
`plan_final_profile_floor` rather than merely a non-empty table.

effort: M

---

## EPIC generator truncates multi-line acceptance criteria to their first line
verdict: REAL

evidence:
- TWO near-identical awk blocks in `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh`,
  confirmed — the entry names neither explicitly and the reader would find only one:
  - `:909-925` — `step_ac`, which feeds the flattened `## Acceptance Criteria`
    section (`all_ac` at :927).
  - `:936-949` — `step_ac_raw`, the unprefixed copy that feeds the per-step
    scoping block / `ac[]` (the comment at :931-935 says "Same
    extraction/scope as step_ac above").
- The mechanism in both: `if (in_ac && $0 ~ /^-[[:space:]]/)` — only a
  FLUSH-LEFT bullet line is emitted. Indented continuation lines match neither
  that test nor the `^\*\*` terminator, so they are silently dropped. The
  effect is the entry's "first line only", but the cause is line filtering, not
  truncation.
- Reproduced (`exp_ac.sh`, the `:909-925` block verbatim against the entry's own
  P068 Step 2 example): output is
  `- [ ] [backend] Every quarantined gate satisfied by a substitute has a matching`
  — mid-sentence, exactly as reported. The three continuation lines carrying
  `gate_id, receipt_sha256, command_sha256, head_sha == candidate_sha` vanish.
- The entry's "Open question" pointer is misdirected: it says to check
  `_aid_extract_*` in `lib/aid-scoping.sh`. Those functions
  (`aid-scoping.sh:140-145`, `_aid_extract_files_bullets` /
  `_aid_extract_files_bullets_numbered`) handle **Files** bullets only and have
  nothing to do with acceptance criteria. Anyone following that pointer would
  edit the wrong code.
- Nothing in v2.81.0–v2.83.1 touches it.

what_is_true: The reported behaviour is real and reproducible, and it lives in
two separate copy-pasted awk blocks in `aid-plan-to-epic.sh`, so a fix applied
to one leaves the other producing a divergent, still-truncated `ac[]`. The
entry's diagnostic pointer to `lib/aid-scoping.sh` is wrong.

impact: An implementer working from the EPIC gets criteria cut mid-sentence —
field lists, binding rules and fail-closed conditions disappear. Worse, the
truncated text also lands in the machine-read per-step `ac[]`, so downstream AC
lenses (C3's `ac_to_test_identity`) verify against a criterion that no longer
states what it requires.

fix_sketch: Factor the two blocks into one shared extractor in
`lib/aid-scoping.sh` that appends continuation lines (any line that is neither a
new `- ` bullet nor a `**` header) to the current criterion before emitting.

effort: S

---

## C0 plan-review requires a dependency graph that no pre-generation producer creates
verdict: REAL (premise has shifted — the producer now exists but runs too late)

evidence:
- The producer the entry says does not exist NOW EXISTS:
  `plugins/aid-orchestrator/scripts/lib/aid-source-plan-graph.sh:176` emits
  schema `aid-source-plan-graph/v1`, written via
  `scripts/aid-generation-readiness.sh --write-provisional` (`:5-21`), invoked at
  `scripts/aid-plan-to-epic.sh:136` into
  `.aid-o/work/evidence/<plan_id>/generation/provisional-graph.json`.
- The zero-byte-seal complaint is FIXED:
  `scripts/lib/aid-c0-plan-review.sh:364-374` records the reasoning — "It used to
  be sealed as an ordinary absent input: the empty-string sha256 with `size: 0`
  … The manifest now records the explicit status string `absent_pre_generation`
  … and drops the phantom entry from `files[]`/`allowlist` entirely" — and
  `:448-461` implements it for both graphs.
- The source graph is now validated when present (`:387-395`: schema check,
  `plan_sha256 == reviewed_plan_hash` binding, and a shape assertion on
  `steps/edges/topological_order/cycles`), so a stale or hand-authored graph
  cannot influence the review.
- BUT the ordering defeats it, and this is measured, not inferred:
  - `.aid-o/work/evidence/P080/c0/codex/codex-prompt-vars.json` —
    `plan_graph_path` = `absent_pre_generation` AND
    `source_plan_graph_path` = `absent_pre_generation`.
  - `.aid-o/work/evidence/P080/c0/codex/audit-input-manifest.json` —
    `.c0_plan_review_input.plan_graph` = null, `.source_plan_graph` = null.
  - File times: `.aid-o/work/evidence/P080/c0-plan-review.json` written
    `2026-08-11 07:46:45`; `.aid-o/work/evidence/P080/generation/provisional-graph.json`
    written `2026-08-11 08:23:47` — **37 minutes after the review it is meant to
    feed**. Same picture in P076 and P079 (`source_plan_graph_path` =
    `absent_pre_generation` in both).
- The review still asks for the analysis regardless:
  `defaults/prompts/c0-plan-review-prompt-v1.md:32` calls the source graph "the
  pre-generation authority", and mandatory check-table item 2 (`:42`) asks "is
  the dependency graph acyclic and satisfiable? Does any step depend on an
  output no step produces?" with no artifact and no defined text-derived
  substitute.

what_is_true: Half the entry has been overtaken — the opaque zero-byte seal is
gone and a schema-valid, plan-bound pre-generation graph producer was built. But
it is wired into `aid-plan-to-epic.sh`, i.e. into EPIC generation, which runs
strictly after the C0 plan review. Every real plan review to date (P076, P079,
P080) therefore sealed BOTH graphs as `absent_pre_generation` and answered a
mandatory graph-based check with no graph.

impact: C0's acyclicity / "output no step produces" check is answered from prose
on every run. A plan with a genuine dependency cycle or an unproduced input can
pass C0 and CP1 while the sealed manifest honestly records that the authority
artifact was absent — the failure is invisible unless someone reads the manifest.

fix_sketch: Call `aid-generation-readiness.sh --write-provisional` from the
plan-review path (before `aid-c0-plan-review.sh build-manifest` seals its
inputs) instead of only from `aid-plan-to-epic.sh:136`.

effort: S
