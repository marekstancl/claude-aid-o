# Backlog verification — block 4 (2026-08-11, against main @ 3da7331, v2.83.1)

All evidence below was opened first-hand in the working tree. Read-only pass.

---

## OBS-20260708-02 — Version skew: release advance retroactively demands new-plugin artifacts from old-plugin runs (backlog:1579, refinement at :1640)

verdict: REAL

evidence:
- `plugins/aid-orchestrator/scripts/aid-fsm.sh:1184-1196` — `fsm_check_grandfather()` is the ONLY era mechanism: `created_at < DEPLOY_DATE`, and it `return 1` (= strict) whenever `created_at` or the threshold is missing.
- `plugins/aid-orchestrator/DEPLOY_DATE` contains `2026-05-08T00:00:00Z`; `git log -- plugins/aid-orchestrator/DEPLOY_DATE` shows exactly two commits, the newest `f634316` = **v2.18.0**. The file has not moved in ~65 releases.
- `grep -n DEPLOY_DATE plugins/aid-orchestrator/scripts/aid-release.sh defaults/policies/release-policy.yaml` → **no hits**. DEPLOY_DATE is not in the release workflow and not in `version_files[]`.
- `plugins/aid-orchestrator/scripts/aid-release-policy.sh:726-729` — plan-final mode calls `check_required_present` for `review-profile.json`, `delivery-gate.json`, `semantic-review-final.json`, `acceptance-evidence.json`; `check_required_present()` (`:229-245`) has no era/capability branch at all — missing artifact ⇒ `add_blocker … blocking`.
- Partial mitigations that DO exist: the C3 presence check is observe-by-default and its comment names the motive verbatim — `aid-fsm.sh:6740-6742` *"grandfather-safe for in-flight EPICs (e.g. E-046-3_3) that predate the producer wiring"*; and `scripts/aid-compliance-backfill.sh:1-45` is a documented, idempotent backfill (`created_at` + `compliance.json`) — i.e. one artifact class has the "documented backfill command" the entry asked for.

what_is_true: The specific 2026-07-08 symptom (done-advance failing on `review_profile_missing_lenses`) can no longer hard-fail, because that hook and the C3 presence check both default to `enforcement: observe`. But the entry's general claim — "retroactive preconditions have no migration/grandfather policy" — is still true. The generic mechanism exists and is wired, yet its threshold has been frozen since v2.18.0 and no release step advances it, so `fsm_check_grandfather` is effectively always false today; and the newest and strictest precondition surface (plan-final `aid-release-policy.sh`) never consults it in the first place.

impact: A project that upgrades the plugin mid-plan still gets the newest preconditions applied to runs produced under the old one, with the only escape being `--force`/`--no-verify`. Hurts consumer projects (WAN, VULCAN) at their next plan-final/release advance, and AID itself the first time a plan spans a release.

fix_sketch: Add `DEPLOY_DATE` to `release-policy.yaml:version_files[]` and stamp it in `aid-release.sh` at every release, so `fsm_check_grandfather` means "created before the plugin the run is now being judged by"; separately decide whether `aid-release-policy.sh check_required_present` should consult it (that part is a policy call, not a bug).

effort: S for the DEPLOY_DATE stamping; M if plan-final preconditions are also made era-aware.

---

## OBS-20260708-03 — C3 audit gate never fires: absent review-profile.json resolves to "not required" (backlog:1684; update at :2199)

verdict: ALREADY_FIXED (the fail-open is gone; the remaining non-blocking behaviour is DELIBERATE and documented)

evidence:
- `plugins/aid-orchestrator/scripts/lib/aid-audit-mode.sh:52-57` — absent `review-profile.json` now **fails closed**: prints a WARN and echoes `c3` with exit 3 ("defaulting to c3 (fail-closed)"). Header `:22-26` documents the same contract. The "no else-branch ⇒ C3 not required" path the entry describes no longer exists.
- Risk-gate policy `plugins/aid-orchestrator/defaults/policies/c3-audit-policy.yaml:26-32` — only `high` and `unverifiable` are listed, both `c3_required: true`, and the file's own header states unverifiable stays true "so the pipeline still demands a C3 pass … rather than silently skipping the audit".
- Producer is wired: `scripts/aid-prefilter.sh:351,668-727` emits `review-profile.json` + `review_profile_emitted`; called from `skills/pipeline.md:1846` (per-EPIC DONE review) and `scripts/aid-plan-fsm.sh:9638` (plan range).
- Consumer presence check exists: `scripts/aid-fsm.sh:6742-6754` — absent file ⇒ `review_profile_would_block` event; `exit 2` with `fsm_done_advance_fail` when enforcement is blocking.
- Plan-final is already hard: `scripts/aid-release-policy.sh:726` makes a missing `review-profile.json` a blocking blocker with no observe escape.

what_is_true: Both halves the entry named are closed — the resolver's missing else-branch (fail-closed to `c3`) and the missing producer (`aid-prefilter.sh profile`, wired at EPIC and plan range). What remains is the staged enforcement: `c3-audit-policy.yaml:23` is `enforcement: observe`, so at per-EPIC done-advance an absent profile is telemetry, not a block. That is an explicit, recorded staging decision — `aid-fsm.sh:6708-6712`: *"The C3 gate is staged OBSERVE by default; E10 promotion flips the policy default to blocking. See AID-v3-principles.md §1."* The backlog's own "do not over-claim fully fixed" nuance (per-lens verification evidence) is likewise still open and disclosed, unchanged since the :2199 update.

impact: None new. The residual is a known E10 promotion item, and the plan-final boundary already blocks.

fix_sketch: n/a
effort: n/a

---

## OBS-20260708-05 — Permanently-failing advisory gate `shell_pipeline_smoke` (backlog:1740)

verdict: MOOT (premise removed by P081 / v2.83.0), with one narrow residual path

evidence:
- `.aid-o/config/execution.yaml` — `yq '.gate_profiles | keys'` returns `quick, targeted, standard, full, release, bats_all_quarantine, release_quarantine, p064-closure`; `shell_pipeline_smoke` appears in **no** `include[]` (searching the whole `gate_profiles` block turns up only two comment lines, one of which states it plainly: *"shell_pipeline_smoke (the whole portfolio, 3 h 23 min measured) is the nightly's command … they run at 02:40 UTC instead of in front of a merge"*).
- The gate definition survives with `required: false` and `timeout_seconds: 18300` (`yq '.gates.shell_pipeline_smoke'`), i.e. it is defined but unreachable from any profile.
- The nightly runs the suite directly, not through the gate: `.github/workflows/nightly-tests.yml:62-64` invokes `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh`.
- `CHANGELOG.md:64-65` records the change ("`shell_pipeline_smoke` and `bats_boundary` left every merge-path profile and run in the nightly").
- Residual: `scripts/aid-fsm.sh:5322-5329` — if the auto-resolved profile name is not defined under `gate_profiles`, the FSM logs `gate_profile_auto_resolve_skipped` and passes **no** `--profile`; `aid-run-gates.sh:1572-1576` then applies no include-whitelist, so every defined gate runs — including this 5-hour one. All five canonical profiles are defined in this repo, so the path is an edge case, not the normal one.

what_is_true: The gate no longer runs on any merge path, so it cannot "fail every EPIC under overall: pass". Its cost moved to the nightly, where it runs as a direct suite invocation rather than as a gate.

impact: n/a (the residual would show up as a merge-path run that suddenly takes hours; it has not been observed).

fix_sketch: n/a for the entry itself.
effort: n/a

---

## OBS-20260708-04 — fsm-state `steps[].status` born "pending", never updated (backlog:1717 header; recurrence #3 at :2237, #4 at :2517)

verdict: ALREADY_FIXED

evidence:
- `plugins/aid-orchestrator/scripts/aid-fsm.sh:5997-6032` (`cmd_increment_step`): after the `sed` that bumps `current_step` (`:5981-5983`), a block headed `── OBS-20260708-04: steps[] array sync ──` runs `yq -i '.steps[N].status = "completed" | .steps[N].completed_at = <ISO ts>'`, backfills `started_at` only when it was `null`, and emits a `step_status_synced` timeline event.
- Guards present as the recurrence-#4 note described: numeric-only `[[ "$step" =~ ^[0-9]+$ ]]` (yq-expression-injection guard) and `yq -e ".steps[N]"` existence probe, so a legacy `fsm-state.yaml` without `steps[]` is skipped rather than crashed.
- The `git log` on the file shows this landed and is on `main` — the fix branch named in recurrence #4 (`0be5e6f`, `fix/plan-close-consistency`) is no longer pending; the code is in the shipped controller.

what_is_true: The write-once decoration is gone on the increment path. One honest caveat I could not close from source alone: the sync fires inside `increment-step`, so a step's `completed` stamp depends on the increment being called for that step — I did not find a separate archival/DONE sweep that would stamp a final step whose increment never ran.

impact: n/a
fix_sketch: n/a
effort: n/a

---

## OBS-20260709-03 — task file YAML frontmatter never updates after init (backlog:2358)

verdict: REAL — and both of the reviewer's specific corrections are CONFIRMED

evidence:
- **The "archival path" at ~6890-6910 is a read-only PRECONDITION.** `plugins/aid-orchestrator/scripts/aid-fsm.sh:6894-6906`: it `find`s `${_tasks_dir}/${epic_id}*`, and if the file is still there prints *"PRECONDITION FAIL: EPIC task file still in tasks/ (not archived)"* plus *"Move to tasks/archive/ before advancing: mv …"*. It neither moves the file nor touches its frontmatter — archival is a human `mv`.
- **`runs_completed` has no producer.** Grep across `plugins/aid-orchestrator/scripts/**`, `skills/**` and `defaults/templates/**` yields exactly three write sites, all literal `0`: `scripts/aid-plan-to-epic.sh:1463`, `defaults/templates/epic-example.md:6`, `defaults/templates/epic.md:7`. The template line even carries the comment `runs_completed: 0      # incremented at each run DONE` — a contract nothing implements.
- No writer for the `status:` field either: no `sed`/`yq -i` in any script targets `.aid-o/tasks/`. The only related remark in the codebase is about the *queue*, `aid-fsm.sh:8430-8432`: *"`status: completed` in particular has only ever been written by hand."*
- Live drift on the newest archived EPIC: `.aid-o/tasks/archive/E-076-3_3-auto-mode-owns-its-waits.md:2,9` still reads `status: active` / `runs_completed: 0` after the v2.80.0 merge. Sampling `.aid-o/tasks/archive/*.md` shows the field is essentially noise (`active`, `draft`, `completed` mixed among long-finished EPICs).

what_is_true: Exactly as filed, and the archival hook people assume exists does not. Frontmatter is written once by `aid-plan-to-epic.sh` and never again by any stage; archival is a manual move gated by a check that only asserts the move already happened.

impact: Any tooling reading frontmatter (a Cockpit list, a status sweep, `runs_total`/`runs_completed` progress math) sees every finished EPIC as `active`, `0` runs done. Also blocks the obvious multi-run EPIC feature: `runs_total: N` cannot be reconciled against a counter nobody increments.

fix_sketch: In the plan-close/archival command, replace the read-only precondition with a stamp-then-move: `yq -i '.status="completed"' `-equivalent frontmatter edit plus `runs_completed` increment at each DONE, then `mv` into `archive/`, evented — or, cheapest honest option, delete `runs_completed` from the template so no field lies.

effort: M (frontmatter edit is trivial; deciding whether the FSM may move files in `.aid-o/tasks/` and back-stamping existing archives is the real work).

---

## Cross-repo CP3 manual-dispatch gap — VULCAN E-56-2_2 (backlog:2422)

verdict: REAL

evidence:
- `plugins/aid-orchestrator/scripts/aid-prefilter.sh:343` — `local ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"`; every diff/rev-parse in the script runs `git -C "$ROOT"` (e.g. `:377-379`, `:670+`). One repo, by construction.
- `:354-368` — the diff range comes only from `--range` or `fsm-state.yaml.base_commit` as `base..HEAD`; when neither resolves, the script deliberately refuses a `HEAD~1..HEAD` fallback (`# CRITICAL: no silent HEAD~1..HEAD fallback (FC-41)`) and emits an `unverifiable` profile with empty surfaces — i.e. it is careful about *unknown* ranges, but has no concept of a *second* repository.
- `grep -rn "cross_repo\|cross-repo\|different repo\|other repo" plugins/aid-orchestrator/{scripts,skills,agents}` → zero relevant hits. No `cross_repo_diff_unreviewable` event, no detector reading step-verify disclosures for foreign repo paths.

what_is_true: Unchanged since it was filed. A cross-repo EPIC's out-of-repo diff is invisible to CP3 prefiltering, and nothing in the pipeline notices or says so — the tool cannot distinguish "no changes outside this repo" from "changes it cannot see".

impact: Whoever runs a cross-repo EPIC (the VULCAN/eco-services pattern) gets a normal-looking green pipeline over a partially reviewed change set; the out-of-repo half is reviewed only if a human remembers a manual dispatch. Silent, no skip event — the worst shape for a false green.

fix_sketch: In `aid-prefilter.sh`, scan the run's `step-*-verify.md` / step disclosures for absolute paths outside `$ROOT` (or an explicit `external_repo:` field), and on any hit emit `cross_repo_diff_unreviewable` into the timeline and set `risk_profile: unverifiable` — detection + honest downgrade, no attempt to widen the diff.

effort: S for the warning-and-downgrade; L if the diff scope is genuinely widened to multiple repos.

---

## OBS-20260709-07 — `plan_diff` exemption note names "P038+" (backlog:2653)

verdict: REAL — the note is still stale, and the gate is now in a worse state than the entry describes

evidence:
- `.aid-o/config/execution.yaml:223-225` — the note is verbatim unchanged: `'required=false for AID self-host: P037 plan predates plan-level AC convention; gate becomes meaningful for P038+'`. We are on P082 (`git log -1` = `plan: P082 absorbs the three remaining P081 review leftovers`).
- `yq '.gates.plan_diff' .aid-o/config/execution.yaml` returns only `note`, `description`, `timeout_seconds: 300`, `pass_criteria`, `max_retries` — **no `required:` key and no `command:` key**. `yq '.gates.plan_diff.command'` → `null`.
- `plugins/aid-orchestrator/scripts/aid-run-gates.sh:1944-1945` reads `command` and `required // false`; `:1953-1963` — a null command records `result: "skip", reason: "no_command"` and `required` defaults to false, so it never touches `overall`.
- `plan_diff` IS in four profiles' `include[]`: `standard`, `full`, `release`, `release_quarantine` (`.aid-o/config/execution.yaml:365,390,397,436`) — so on every merge-path run it produces a `skip/no_command` row that verifies nothing.
- The shipped default is different: `plugins/aid-orchestrator/defaults/execution.yaml:109-116` has `required: true` and a real `command:` (`aid-plan-diff.sh --plan {plan_path} …`). Only AID's own (git-ignored) self-host config is degraded.
- The timeout half IS fixed, as the 2026-07-10 update claims: `scripts/aid-plan-diff.sh:91` `AC_CMD_TIMEOUT="${AID_PLAN_DIFF_AC_TIMEOUT:-120}"`, `:222-224` wraps each AC in `timeout "$AC_CMD_TIMEOUT" bash -c` and records `verdict=absent … reason=timeout`; commit `8b9d88b` is on main.
- Plan-final still catches the artifact's absence independently: `scripts/aid-release-policy.sh:734-737` blocks when `plan-diff.json` is missing or invalid.

what_is_true: Two of three sub-claims hold. (1) The self-expiring exemption note has still never been revisited, 40+ plans past its own stated threshold. (2) `required` is still effectively false — now by omission rather than by an explicit key. (3) The timeout is genuinely fixed. What is new and worse: the self-host gate has lost its `command` entirely, so `plan_diff` is not merely advisory, it is a no-op skip row inside `standard`/`full`/`release`. Because `.aid-o/` is git-ignored there is no history to say when or why the command disappeared — I cannot attribute it, only report it.

impact: AID's own merge path shows a `plan_diff` row in every gates report that proves nothing; anyone reading `gates_report.json` reasonably assumes plan ACs were checked against HEAD. The plan-final release policy is the only thing still demanding the artifact.

fix_sketch: Restore `command:` (and an explicit `required:`) in `.aid-o/config/execution.yaml` from `defaults/execution.yaml:109-116`, run it once to see whether it passes at `required: true`, then either flip it or replace the "P038+" note with a fresh, dated justification.

effort: S (config restore + one gate run); M if the first honest run surfaces real AC failures that have been hidden.
