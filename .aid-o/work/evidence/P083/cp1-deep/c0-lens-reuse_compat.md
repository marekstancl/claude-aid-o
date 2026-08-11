# CP1-deep — C0 lens reuse_compat — P083

Question: does the plan reuse an existing component in a way that component does not
actually support? Every claim below was verified by opening the component and
enumerating its callers with grep; the plan's description of a component was never
taken as evidence.

stop_rule_blockers: none

findings:

---

### F1 — Step 7 rewires a shared renderer whose SECOND caller appends into a file the composer never built
- severity: high
- ref: Step 7 (`lib/aid-init-execution-yaml.sh`, `render_gate_profiles_block`)
- summary: `render_gate_profiles_block` has two consumers, not one. Besides
  `compose_execution_yaml` (fresh init), the `/aid-init` **existing-project upgrade**
  path calls it and appends the emitted block verbatim to a PM's hand-maintained
  `.aid-o/config/execution.yaml`. Step 7's safety argument ("every emitted profile names
  only gates the composed file defines") holds only for the composed file; the upgrade
  target is a different file whose `gates:` mapping the composer did not write. A
  five-profile ladder derived from *detected stacks* and appended to a hand-authored
  `gates:` mapping can name gates that file does not define — which `aid-run-gates.sh`
  refuses upfront, before any gate runs.
- evidence:
  - `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh:199-205` — the
    function's own header: "compose_execution_yaml (fresh-init) and
    append_gate_profiles_block callers (existing-project upgrade) both call this — one
    derivation, no drift."
  - `plugins/aid-orchestrator/commands/aid-init.md:157` —
    `proposed_block="$(render_gate_profiles_block "${stacks[@]}")"`, then `:160`
    `append_gate_profiles_block .aid-o/config/execution.yaml "$proposed_block"`.
  - `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh:299-314` —
    `append_gate_profiles_block` is a pure `>>` append; it never validates the block
    against the target file's `gates:` keys.
  - `plugins/aid-orchestrator/scripts/aid-run-gates.sh:1583` + `:1596-1601` — "A
    profile's include[] lists a gate not defined under .gates" is a validated fail-loud
    case, `exit 1` before any gate runs.
  - `plugins/aid-orchestrator/commands/aid-init.md:186-197` — the PM-facing report
    template prints a literal two-profile block (`targeted` / `full`); after Step 7 it
    would advertise a block different from the one actually appended.
  - Plan quote contradicted: Step 7 Error Handling — "A composed profile naming a gate
    the composed file does not define is a build-time failure in the new test, not a
    consumer's first-run surprise" (line 269); and Step 7 Edge Cases — "An existing
    project re-running init — the additive-upgrade contract is unchanged" (line 274).
    The contract's *shape* is unchanged; its *content* is not, and the plan's own
    Constraint (line 476) forbids editing `commands/aid-init.md`, so this step cannot
    repair the consumer it changes.
- suggested_fix: give `render_gate_profiles_block` an explicit "gates available in the
  target file" input (or a second entry point for the upgrade path), so the upgrade path
  emits profiles restricted to gates the target file actually defines; assert that case
  in `test-init-gate-profiles.bats`, and state in the step that the appended block is
  validated against the target's `gates:` keys before the append. If the upgrade path
  cannot be touched while P080 holds `commands/aid-init.md`, note that the upgrade path
  keeps the two-profile shape until then — do not leave it implicitly changed.

---

### F2 — Step 4 re-invents a version-file registry that already exists, twice, under a different name
- severity: medium
- ref: Step 4 (`aid-release.sh` fallback README updater)
- summary: The plan's fix is "discover the anchor from the file". But a declarative
  registry of exactly these files, with the exact regex and replacement for the README
  version line, already ships in the repo — and nothing reads it. Step 4 would add a
  FOURTH mechanism (in-file anchor discovery) alongside three existing declarations of
  the same fact, and it picks the one that has to re-derive at runtime what the other
  three state literally.
- evidence:
  - `plugins/aid-orchestrator/defaults/orchestration.yaml:64-83` — `release.version_files[]`
    with `path: "README.md"`, `field: roadmap_current`,
    `pattern: '^\- \*\*v[\d.]+\*\* \(current\)'`,
    `replacement: '- **v${version}** (current)'`, plus the plugin README's
    `- **Plugin:** X.Y.Z` entry. This file is **tracked**, so unlike `project.yaml` it is
    present in every worktree and clone — precisely the failure mode Steps 3 and 4 exist
    to fix.
  - `.aid-o/config/policies/release-policy.yaml:76+` — the same registry a third time.
  - `grep -rn "version_files" --include=*.sh plugins/aid-orchestrator/scripts` → **no
    hits**: no script reads either registry. `aid-release.sh:544-546` reads only
    `.aid-o/config/project.yaml` → `versioning.files[]`.
  - `README.md:118-120` — the list the plan wants to edit is real (`## Changelog`,
    `- **v2.83.1** (current)`), and it is exactly what the shipped `roadmap_current`
    pattern matches. The stale `v2.69.0` is `README.md:3`, a subtitle outside any list.
  - `CLAUDE.md` "Version File Registry" points at `defaults/policies/release-policy.yaml`,
    which does not exist (`ls plugins/aid-orchestrator/defaults/policies/` — 11 files,
    none of them release-policy.yaml).
  - Plan quote: "the fallback README updater edits the version list by its real heading
    …; the anchor is discovered from the file" (line 166).
- suggested_fix: make the fallback read `defaults/orchestration.yaml`
  `release.version_files[]` (shipped, tracked, already carries path+pattern+replacement),
  and treat in-file anchor discovery as the last resort for a consumer project with no
  registry at all. State in the step which of the three existing registries becomes the
  authority and what happens to the other two — otherwise this step adds a fourth
  competing source of the same truth.

---

### F3 — Step 9 invokes readiness from a `set -euo pipefail` context whose stdout is a contract
- severity: medium
- ref: Step 9 (`lib/aid-c0-plan-review.sh` `build-manifest` → `aid-generation-readiness.sh --write-provisional`)
- summary: The invocation is supported in argument shape, but two properties of the
  calling context make an unguarded call wrong, and the plan states neither.
  (a) readiness exits **1** on a lint failure or an invalid dependency grammar and **2**
  on argument errors; `lib/aid-c0-plan-review.sh` runs under `set -euo pipefail`, so an
  unguarded call aborts `build-manifest` for exactly the plans the C0 review exists to
  examine — today those plans get a manifest with `absent_pre_generation` and are
  reviewed anyway. (b) readiness prints `READINESS: PASS — …` (4 lines) to **stdout**,
  and `cmd_build_manifest`'s stdout is its return channel: it ends with
  `echo "$manifest_out"`. An unredirected call corrupts the manifest path every caller
  reads.
- evidence:
  - `plugins/aid-orchestrator/scripts/aid-generation-readiness.sh:29-37` — `exit 1` on
    `aid-plan-lint.sh` failure and on invalid dependency grammar; `:22,26,27` — `exit 2`
    on unknown option / missing plan.
  - `plugins/aid-orchestrator/scripts/aid-generation-readiness.sh:43-49` — the PASS
    banner goes to stdout.
  - `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh:92` — `set -euo pipefail`.
  - `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh:547` —
    `echo "$manifest_out"` is the function's output contract.
  - `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh:94` — `SCRIPT_DIR` is
    `scripts/lib`, so the target is `${SCRIPT_DIR}/../aid-generation-readiness.sh`; the
    plan's Files list does not name the resolution.
  - Plan quote: "`build-manifest` produces the provisional graph itself, by invoking
    `aid-generation-readiness.sh --write-provisional` for the plan under review" (line
    328) — and Step 9's AC "a plan that fails readiness still seals the absent status
    with its recorded reason" (line 330), which cannot hold under `set -e` without an
    explicit guard.
- suggested_fix: state the invocation literally in the step —
  `rc=0; bash "${SCRIPT_DIR}/../aid-generation-readiness.sh" "$plan_file" \
  --write-provisional "$repo_root/$source_graph_rel" >/dev/null 2>"$tmp_err" || rc=$?` —
  with rc≠0 recorded as the `absent_pre_generation` reason, never propagated. Assert
  in `test-c0-plan-graph-input.bats` that `build-manifest`'s stdout is still exactly the
  manifest path.

---

### F4 — Step 2's "one shared extractor" is two of three AC parsers, and the third is the gate Step 5 restores
- severity: medium
- ref: Step 2 (`lib/aid-ac-extract.sh`), interacts with Step 5
- summary: The plan's stated reason for the shared extractor is "so a fix cannot land in
  one copy and leave the other divergent". A third, independent AC parser exists in
  `aid-plan-diff.sh`, with the same bullet-line-only truncation, over the plan-level
  `## Acceptance Criteria` section. Step 5 puts that gate back on four merge-path
  profiles in the same plan — so the plan simultaneously fixes AC truncation in the EPIC
  generator and re-arms a gate that still truncates the same way. The new extractor's
  stated grammar (indented continuation until the next flush-left bullet) also cannot
  serve that section without change: its criteria carry **flush-left** ```yaml
  verification_pattern fences.
- evidence:
  - `plugins/aid-orchestrator/scripts/aid-plan-diff.sh:167-175` — `ac_text` is taken from
    the bullet line only (`extract_text($0)` / `extract_text_role($0)`); nothing joins a
    following indented line.
  - `plugins/aid-orchestrator/scripts/aid-plan-diff.sh:176-192` — the parser's own
    handling of `^[[:space:]]*```yaml` fences, i.e. the section shape the new extractor
    would have to tolerate.
  - This plan's own lines 397-402 — a flush-left ```yaml block directly under an AC
    bullet.
  - Plan quote: "the two copy-pasted awk blocks … are replaced by calls to one shared
    extractor, so a fix cannot land in one copy and leave the other divergent" (line 103).
- suggested_fix: either scope the claim ("the two generator copies; `aid-plan-diff.sh`
  keeps its own plan-level parser and is out of scope, with the reason") or design the
  extractor to take the terminator set as a parameter so the third call site can adopt
  it later. Add a fence rule to the extractor's grammar explicitly, whichever way.

---

### F5 — Step 6 adds a third outcome to a function whose two callers and existing suite pin two
- severity: low
- ref: Step 6 (`lib/aid-review-signals.sh::_aid_read_toggle`)
- summary: `_aid_read_toggle` is a strictly 2-valued contract (0 = enabled, 1 =
  disabled), and all four production call sites collapse *any* non-zero into "disabled"
  via `|| enabled=false`. A "named failure" third outcome is therefore
  indistinguishable from "disabled" at every caller — acceptable as fail-closed, but it
  cannot propagate as a distinct state, and the plan should not assume it can. Separately,
  `[[ ! -f "$exec_yaml" ]] && return 0  # file missing → enabled by default` is pinned by
  an existing test; Step 6's "the unreadable case is a named failure, not a silent
  `return 0`" must exclude the missing-file case or that suite breaks.
- evidence:
  - `plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh:19-30` — the 2-valued
    contract and the missing-file default.
  - Callers: `aid-release-policy.sh:434`, `aid-release-policy.sh:490`,
    `aid-fsm.sh:2406` (`|| { echo null; return 0; }`), `aid-fsm.sh:7970-7971`.
  - `plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats:530-531` —
    `run _aid_read_toggle "$TEST_TMPDIR/does-not-exist.yaml" reporter; [ "$status" -eq 0 ]`.
  - Plan quote: "distinguishes 'read the toggle, it says enabled' from 'could not read
    the toggle': the unreadable case is a named failure, not a silent `return 0`" (line 231).
- suggested_fix: name the two cases explicitly in the step — missing FILE stays exit 0
  (documented default, pinned by test-release-policy.bats:530), malformed/unreadable
  CONTENT becomes exit ≥2 with a message on stderr — and say that callers observe it as
  "disabled" by design.

---

### F6 — Step 8's "named refusal" is swallowed by both live callers
- severity: low
- ref: Step 8 (`lib/aid-gate-runtime-baseline.sh`)
- summary: The premise checks out — both producers pass `sequential` literally, and no
  external consumer reads the `*_by_context` maps, so the deletion is compatible. But
  "a resurrection attempt fails loudly instead of silently taking a deleted branch"
  overstates what the callers permit: both invoke the function with `|| true`, and the
  CLI defaults the context argument to `sequential`, so a refusal can only ever be
  observed as stderr plus a return code inside the function.
- evidence:
  - Producers pass sequential: `aid-run-gates.sh:2023` (`local gate_concurrency_context="sequential"`)
    → `:2100-2101`; `aid-fsm.sh:3768-3770` (`_resume_concurrency_context` is
    `printf 'sequential'`) → `:3809`.
  - Both call sites end in `|| true` (`aid-run-gates.sh:2101`, `aid-fsm.sh:3809`).
  - `lib/aid-gate-runtime-baseline.sh:853` — CLI `update` defaults arg 8 to `sequential`.
  - No external consumer: `grep -rn "percentiles_by_context\|recent_samples_by_context"`
    over `plugins/` outside the library itself → no hits.
  - Today's behaviour for a bad context is warn + `return 0` (skip write),
    `lib/aid-gate-runtime-baseline.sh:329-333`.
  - Plan quote: "A non-sequential context passed by a caller is a named refusal, so a
    resurrection attempt fails loudly instead of silently taking a deleted branch" (line 304).
- suggested_fix: have the new test assert the function's own stderr and return code
  directly (and the CLI's), not a run-level failure; say in the step that both callers
  intentionally swallow it.

---

### F7 — Step 2 creates a second library for a convention `lib/aid-scoping.sh` already owns
- severity: low
- ref: Step 2 (`Create: lib/aid-ac-extract.sh`)
- summary: `aid-plan-to-epic.sh` already sources `lib/aid-scoping.sh`, and the
  flush-left-bullet-vs-indented-continuation rule the new extractor needs is already
  implemented in this generator for Files bullets. A second library encoding the same
  rule re-creates, at the library level, exactly the divergence Step 2 exists to remove.
  Advisory only — the step's own note (that the backlog's `aid-scoping.sh` pointer was
  wrong) is about Files vs AC, not about where the code should live.
- evidence:
  - `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh:33` — `source "${SCRIPT_DIR}/lib/aid-scoping.sh"`.
  - `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh:972-985` — the existing
    top-level-only bullet rule ("Only a bullet with NO leading whitespace before its '-'
    is a real, distinct entry").
- suggested_fix: consider placing the extractor in `lib/aid-scoping.sh` (already sourced,
  already the home of this convention) or state why a separate file is preferred.

---

### Checked and clean (no finding)
- **Step 1 path reuse** — `${evidence_dir}/gates/gates_report.json` is the same variable
  the file's other readers use: writer `aid-run-gates.sh:1629`, readers
  `aid-fsm.sh:2453` and `aid-fsm.sh:2990`; the outlier at `aid-fsm.sh:1823` is real
  (`local gates="${evidence_dir}/gates_report.json"`). Reuse is compatible.
- **Step 9 `--total` omission** — `build-manifest` cannot supply `--total`, but
  `expected_epics` only ADDS validation errors (`lib/aid-source-plan-graph.sh:145,147-151`);
  it does not change the emitted JSON. So a graph written without it is byte-identical to
  the one `aid-plan-to-epic.sh:136` writes with it, and
  `aid-generation-finalize.sh:112-119`'s byte-canonical provisional-vs-final comparison
  still holds. Both writers target the same path when `PLAN_EVIDENCE_ROOT` is
  `.aid-o/work/evidence/<plan_id>/` as `commands/aid-plan.md:555` prescribes.
- **Step 9 graph shape** — `aid_source_plan_graph` emits `schema:"aid-source-plan-graph/v1"`
  and `plan_sha256:"sha256:<hex>"` (`lib/aid-source-plan-graph.sh:174-176`), exactly what
  `lib/aid-c0-plan-review.sh:388-399` validates. Compatible.
- **Step 5 refusal vs shipped stacks** — every gate in every
  `defaults/execution-stacks/*.yaml` fragment carries a `command:`, so the new
  command-less refusal cannot fire on a freshly composed workspace.
- **Step 4 README anchors** — both claimed shapes exist: `README.md:118-120`
  (`## Changelog` + `- **v2.83.1** (current)`) and
  `plugins/aid-orchestrator/README.md:3` (`- **Plugin:** 2.83.1`, no list).

confidence: high — every component named in Steps 1-9 was opened, and every caller was
enumerated by grep across `plugins/` (scripts, commands, skills, defaults, tests). The
one place my coverage is thinner is Step 10 (backlog reconciliation), which reuses no
component beyond the status extractor and was not exercised.
