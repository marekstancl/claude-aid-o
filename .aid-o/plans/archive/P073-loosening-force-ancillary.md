---
id: P073
type: plan
status: done
created: 2026-08-04
author: PM + AI
risk: high
---

> **Closure (2026-08-09):** Implemented and released (v2.7x line); deep-check record in interim-P073.md + evidence/P073/

# Plan: AID Loosening — Quick Wins, PM Force Backdoor, Review-Equivalent Ancillary Writes

## Stakeholder Brief

AID has accumulated safety mechanisms faster than escape hatches, and three classes of friction now cost real time: review budgets exhaust after 3 Codex sessions with no discoverable PM override; a defective bookkeeping path can strand the PM with no supported way to finish a plan; and any tracked write after candidate freeze — even a harmless report — throws away a completed review and forces a full re-review cycle. This plan delivers three EPICs of deliberate loosening. EPIC 1 ships quick wins: 5 Codex sessions per review loop, fail-loud release preparation, human-readable step numbering, one coherent dependency grammar, and a hard stop when batch generation strands the checkout on the wrong branch. EPIC 2 gives the PM a universal, audited `--force --reason` backdoor across the plan lifecycle, removes the P082 Reporter contradiction and the P083 uncommitted-plan trap, and adds a supported recovery transaction so force stays the last resort. EPIC 3 introduces review equivalence: an ancillary commit (report, backlog note, runtime record) after freeze no longer invalidates the review, while any change to the delivery surface still does. Every mechanism lands wired to its enforcement point — no prose-only promises. The main risk is regression in the plan-final freshness chain; it is mitigated by an integration fixture that drives one ancillary commit and one protected change through every touched consumer.

## Context

Source document: `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md` §10 (PM emergency override, P082/P083 dogfood traps), §11 (release truthfulness, grounding items 3-4), §12 (review-equivalent ancillary writes), §13 (Codex budgets and one PM force path). The PM triaged that document into five categories on 2026-08-04 and directed that categories 1-3 become this plan, one EPIC per category, with the binding constraint that the work must simplify and loosen AID rather than add new unpolished prohibitions. Categories 4 (entry-point UX) and 5 (Release-Impact trailers, coverage ledger, evidence inventory) are deferred to later plans. Two read-only grounding agents verified every claim against the current tree (branch `feat/p072-test-audit-decision-quality`), and an adversarial Codex opponent round reviewed the draft design; agreements are folded in below, disagreements were escalated to the PM in the brainstorm log (`.aid-o/work/interim-P073.md`).

## Goal

Ship three EPICs that measurably reduce AID process friction — 5-session review budgets, a universal audited PM force path with trap fixes, and review-equivalent ancillary writes — with every new check, receipt, and flag wired to a named enforcement point and covered by regression tests.

## Scope

**In scope:**
- Codex review budgets raised to 5 total sessions for the C0/CP1 loop and the C3 fix loop, with every stale numeric assumption in code, docs, and tests updated.
- `aid-release.sh` fail-loud repair of the three unguarded probes and validation of the target-version CHANGELOG entry before any release commit.
- Human step rendering `Step N/T` (1-based) on every enumerated prose surface and FSM operator message.
- One documented dependency grammar (`Depends on: none` and `---`) with loud, propagated failures instead of silent token drops.
- Immediate hard stop with recovery instructions when batch generation cannot restore the original branch.
- `--force --reason` (audited, min 20 chars) on the eight public state-TRANSITION commands in `aid-plan-fsm.sh` (plan-start, epic-start, epic-complete, epic-merge-to-plan, plan-finalize, plan-merge-to-main, plan-close, plan-rollback), plus repair of the three existing force anomalies in `aid-fsm.sh` and `aid-release.sh`. Deliberately NON-forceable mutators: `plan-state` (`--repair`, `--attest-source-ref`, and Step 13's `--supersede-epic`) and `inventory --apply` — these ARE the audited recovery/bookkeeping mechanisms force falls back to; a forced repair tool could fabricate the very records other commands trust, so they stay truthful-or-refuse by design.
- One shared PM-override artifact schema for C0 and C3 exhaustion with an atomic claim, a public grant subcommand, and one-release env-var compatibility.
- Committed-source preflight before plan lifecycle creation (P083); Reporter post-freeze boundary fix (P082); supersede/attest recovery transaction.
- Ancillary-path policy, protected path set at freeze, read-only equivalence checker, controller-only acceptance receipt, and wiring into candidate drift plus `plan-merge-to-main`.

**Out of scope:**
- P069 scheduler/test-catalog contract and P072 in-flight work (both untouched).
- Entry-point UX (help/init/setup) and human-first handoff renderers — source doc categories 4.
- Release-Impact commit trailers, Codex coverage ledger, evidence minimisation inventory — source doc category 5, PM-deferred.
- CP3 freshness, C3 audit freshness, and `aid-plan-close-check` docs-only classifier keep their existing mechanisms (deliberate EPIC 3 scope cut after the opponent round; extend only if dogfood shows they still force re-reviews).
- `aid-evidence-verify --at-head`, pre-commit scope guards, gate waivers, release-prep staging: deliberately exact-SHA-only, unchanged.

## Approach

**Chosen approach: minimal-mechanism loosening on existing primitives.** Each EPIC reuses the strongest existing primitive instead of inventing a parallel subsystem: budgets change a constant plus one policy default rather than adding CP1 policy plumbing (no consumer override path exists today — verified); the plan-level force handler mirrors `fsm_handle_force_override`'s three-record pattern (timeline + audit log + HEAD-bound waiver artifact) with one added field; the C3 override adopts the existing CP1 single-use artifact claim; review equivalence uses git ancestry plus a changed-path check against one shared classifier, with no content digest (a git SHA already proves content).

**Alternative A (rejected): full source-doc fidelity.** Policy-driven budgets with per-project overrides, a `protected_surface_digest`, equivalence wired into six consumers, and a separate `--accept-exhausted` flag. Rejected as over-engineering by both the controller and the Codex opponent: it adds three persistence mechanisms and a broad semantic rewrite of independent freshness regimes for a plan-final-review problem.

**Alternative B (rejected): pure config bump.** Only edit the two YAML defaults and stop. Rejected because grounding proved the CP1 YAML value is documentation-only — `aid-cp1-ledger.sh` enforces `MAX_ATTEMPTS=3` and its validator rejects any other ledger `max` as tampering, so the bump would change nothing mechanically.

## Architecture

Three subsystems are touched; all live under `plugins/aid-orchestrator/`.

**Review budgets (EPIC 1).** The CP1/C0 loop budget authority is `scripts/lib/aid-cp1-ledger.sh` (`MAX_ATTEMPTS=3` at line 95; validator at line 296 rejects any ledger whose `max` differs). `scripts/aid-cp1-gate.sh` delegates to `check-budget` and holds no literal. The C3 loop reads `defaults/policies/c3-audit-policy.yaml` via `scripts/lib/aid-c3-dispatch.sh:1790-1794` with a triple fail-closed fallback of 2. The change is: constant 3→5 in the ledger (validator follows automatically because it compares against the same constant), fallback literals 2→4 in the C3 reader, both YAML defaults 2→4, and every prose/test literal updated to the new numbers. No new policy-read path is introduced.

**Force and recovery (EPIC 2).** `scripts/aid-fsm.sh` already implements the audited force pattern: `fsm_handle_force_override()` (line 846) validates `--reason` ≥20 chars and writes three records — timeline event via `log_event`, append-only `.aid-o/work/audit-log.jsonl` via `fsm_emit_audit_log`, and a HEAD-bound protocol-v2 waiver artifact surfaced by the C4 aggregator in `waivers_applied[]`. `scripts/aid-plan-fsm.sh` currently hard-rejects `--force` on every subcommand. A new `_pfsm_handle_force()` in `aid-plan-fsm.sh` mirrors the three-record pattern, adds a `bypassed_preconditions` array field to the waiver artifact, and writes it into the plan-final evidence dir so C4 sees it. Preconditions are classified `forceable` or `hard` per command; `hard` covers only physical git impossibilities (unresolvable merge, missing branch object). The C0 and C3 PM overrides converge on one artifact schema (`pm_ref` ≥20 chars, `target`, `plan_id`, `created_at`) claimed atomically with the existing `mv -n` + sha256-corroboration pattern from `scripts/aid-cp1-gate.sh:344-359`. The P083 committed-source preflight lives in `scripts/aid-auto-pipeline.sh` (the production caller that knows the plan path) plus an optional `--plan-file` argument on `plan-start`. The P082 fix rewrites `agents/reporter.md` so plan-final agents write run-scoped evidence only; the committed human projection becomes a `plan-close` controller render.

**Review equivalence (EPIC 3).** A new `defaults/policies/plan-final-policy.yaml` carries `plan_final.ancillary_paths`; a new `scripts/lib/aid-ancillary.sh` exposes `aid_ancillary_match`, `aid_ancillary_filter_porcelain` (replacing the dirty-exception regex duplicated verbatim at `aid-plan-fsm.sh:277`, `aid-plan-fsm.sh:3069`, `aid-release.sh:597`, and the 4-entry variant at `aid-fsm.sh:2662`), and `aid_ancillary_overlap_warn`. At freeze, `plan_manifest_freeze_candidate()` additionally stores the protected path set: the union of all steps' `plan.json` `allowed_paths`, the source plan path, the lifecycle manifest path, and the close-consumed receipt paths. Equivalence is a read-only predicate: frozen candidate is an ancestor of the current `plan/<id>` head, every path in `git diff --name-only candidate..head` matches the ancillary policy, and the changed set is disjoint from the protected set. Acceptance is a controller-only subcommand that writes one JSON receipt and records `accepted_head` in the manifest; `candidate_sha` itself never moves. Consumers wired: `_pfsm_review_candidate_drift()` (which the review/c4 stages call) and `plan-merge-to-main` (which re-verifies live at merge time). Protected paths take precedence over ancillary globs at the path level, so close-consumed evidence under `.aid-o/work/` can never ride an ancillary glob.

## Implementation Steps

**EPIC 1: Steps 1-6 — Quick Wins and Pure Loosening**

### Step 1: Raise both Codex review budgets to 5 total sessions

**Objective:** The C0/CP1 loop and the C3 fix loop each allow an initial review plus 4 rechecks (5 genuinely dispatched Codex sessions), with every stale numeric assumption in code, policy, docs, and tests updated to match.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-cp1-ledger.sh` (lines ~51-95, ~272-296, ~358) — change `MAX_ATTEMPTS=3` to `MAX_ATTEMPTS=5`; update the schema doc comment at line 51 and the validator design comment at lines 272-275 to state the new fixed budget (1 initial + 4 revisions); the validator at line 296 and the init writer at line 358 already reference `$MAX_ATTEMPTS` and follow automatically.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh` (lines ~1748, ~1790-1794) — change the three fallback literals in `local ... max_rechecks=2`, `.c3_fix_loop.max_rechecks // 2`, and `|| echo 2` to 4; update the fail-closed doc comment at line 1748.
- Modify: `plugins/aid-orchestrator/defaults/policies/review-checkpoints.yaml` (lines ~31-34) — `cp1_codex_review.max_rechecks: 2` → `4`; comment becomes "initial review + up to 4 rechecks = 5 Codex runs max".
- Modify: `plugins/aid-orchestrator/defaults/policies/c3-audit-policy.yaml` (lines ~66-67) — `c3_fix_loop.max_rechecks: 2` → `4`; same comment update.
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` (lines ~482-544) — replace every "2 rechecks", "3 Codex runs", "4th review run" literal with the new static numbers (4 rechecks, 5 runs, 6th attempt where the override text applies).
- Modify: `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md` (lines ~208-237) — same literal replacement: "3 Codex runs max" becomes "5 Codex runs max", "3rd review run (initial + 2 rechecks)" becomes "5th review run (initial + 4 rechecks)".
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~1582-1661) — same literal replacement in the C3 fix-loop contract text, including the fail-closed fallback wording (now 4).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-cp1-ledger.bats` — update every assertion of `max == "3"`, `attempts == "3"`, and `attempts_log|length == 3` (lines ~67, ~186, ~369-397, ~416, ~480-508) to 5; the tamper test at lines ~648-650 keeps its shape (`.max = 100` still rejected).

**Architecture Context:** Per the Review budgets subsystem above: the ledger constant is the sole mechanical CP1 budget authority (`aid-cp1-gate.sh` delegates to `check-budget` and holds no literal), while C3 reads its policy file with a fail-closed fallback. This step changes the constant and the fallback rather than introducing a CP1 policy-read path, per the opponent-round agreement — no consumer policy copy exists in any `.aid-o/config/policies/` directory today.

**Implementation Detail:** In `aid-cp1-ledger.sh`, the single edit `MAX_ATTEMPTS=5` propagates through `init` (writes `max: 5` into new ledgers), `check-budget` (`attempts >= max`), `increment` (refusal at exhaustion), and the tamper validator (`. == $max` at line 296). Pre-existing ledgers written with `max: 3` must not fail validation as "tampered". Migration is split read/write to keep the validator pure: the VALIDATOR (`_ledger_read_json`, lines 288-300, a read-only predicate) additionally ACCEPTS `max == 3 && attempts <= 3` as legacy-valid (any other mismatch stays rejected as tampering); the actual re-stamp to `max: 5, migrated_from: 3` is performed ONLY inside the existing locked WRITE path (`increment`, which already holds the ledger lock) the next time the ledger is genuinely written. Read-only consumers (`check-budget`, `read`) therefore never write; a legacy ledger simply reports budget against 5 via the same tolerance arithmetic (`remaining = 5 - attempts`). In `aid-c3-dispatch.sh` keep the regex guard `[[ "$mr" =~ ^[0-9]+$ ]]` unchanged so a malformed policy value still falls back — now to 4. Doc edits are static text replacements; do not claim numbers are derived from policy (they are shipped defaults).

**Error Handling:** A malformed or missing `c3-audit-policy.yaml` falls back to 4 (never unbounded). A CP1 ledger with `max` neither 3-legacy-tolerated nor 5 is rejected exactly as today (tamper path, `exhausted` fail-closed). A FAILED re-stamp write inside `increment` (read-only checkout, lock contention, disk error) leaves the ledger bytes untouched and the increment fails with the existing locked-write error path — the legacy-tolerance read arithmetic keeps working on the unmigrated file, so a second read after a failed write is byte-identical and reports the same budget (idempotent). If `review-checkpoints.yaml` is edited by a project to a different value, nothing reads it mechanically for CP1 — the docs updated in this step state that explicitly instead of implying an override exists.

**Edge Cases:**
- In-flight plan with a `max: 3` ledger and `attempts: 3` (exhausted under the old budget): migration re-stamps to `max: 5`, so the PM gains 2 more sessions without an override artifact — intended loosening, called out in the CHANGELOG entry.
- Ledger with `max: 3` but `attempts: 4` (impossible under old rules): stays rejected as tampered.
- `yq` absent when C3 reads policy: existing `command -v yq` guard falls back to 4.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] `bats plugins/aid-orchestrator/scripts/tests/bats/test-cp1-ledger.bats` passes with all assertions on the new budget of 5.
- [ ] `grep -rn 'max_rechecks: 2' plugins/aid-orchestrator/defaults/policies/` returns zero matches.
- [ ] `grep -rn '3 Codex runs\|2 rechecks' plugins/aid-orchestrator/commands/ plugins/aid-orchestrator/skills/` returns zero matches.
- [ ] A fixture ledger with `max: 3, attempts: 2` validates read-only (two consecutive `check-budget` reads are byte-identical, reporting 3 remaining) and is re-stamped `max: 5, migrated_from: 3` by the next `increment`; a re-stamp on a read-only filesystem fails the increment while leaving the ledger bytes and reported budget unchanged.

**Effort:** M
**AID Role:** backend

### Step 2: Fail-loud optional probes in aid-release.sh

**Objective:** The three unguarded grep-into-head optional probes under `set -euo pipefail` no longer abort the script silently; every no-match case reaches the script's own explicit diagnostic.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~188, ~209, ~254) — wrap each probe in an explicit conditional that distinguishes "no match" (variable set empty, flow continues to the existing diagnostics) from a real I/O failure (file unreadable — die with the path).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-release-detection.bats` — new fixtures: CHANGELOG.md without any `## [X.Y.Z]` header plus an authoritative `plugin.json` version (detection must succeed via JSON); no version source at all (must exit non-zero printing the existing "ERROR: Cannot detect version" diagnostic, not a silent abort); `pyproject.toml` present without a top-level `version = "X.Y.Z"` line (must fall through, not abort at line 209).

**Architecture Context:** `aid-release.sh` sets `set -euo pipefail` at line 52, so a probe pipeline whose `grep` matches nothing returns 1 and kills the script before the explicit three-way header handling at lines 255-279 or the version-source diagnostic at lines 225-228 can run. Line 424 (`|| echo` guard) proves the intended idiom; this step makes the three broken sites consistent with it.

**Implementation Detail:** Replace each `VAR=$(grep -oP '<pattern>' "$file" | head -1)` with:
```bash
VAR=""
if [[ -r "$file" ]]; then
  VAR=$(grep -oP '<pattern>' "$file" | head -1) || VAR=""
else
  echo "ERROR: cannot read $file while detecting version" >&2; exit 1
fi
```
The `|| VAR=""` form neutralises only the pipeline's exit status; an unreadable file is reported loudly instead of masked (Codex-round refinement: do not blanket-`|| true` the whole probe). The three sites are: `CHANGELOG_HEADER` (line 188), `RELEASED_VERSION` pyproject probe (line 209), `header` in `update_changelog()` (line 254).

**Error Handling:** File unreadable → explicit `ERROR` naming the file, exit 1. No match → empty variable, existing downstream logic decides (lines 210, 225-228, 255-279 already handle the empty case correctly once reached).

**Edge Cases:**
- CHANGELOG.md is a landing page with no version ledger but `plugin.json` carries the version: detection succeeds via the JSON source, no abort.
- Both CHANGELOG header and every JSON/pyproject source missing: the run reaches lines 225-228 and prints the actionable diagnostic naming all accepted sources.
- `grep` itself fails for a non-match reason (binary file flag): treated as no-match; the readability pre-check covers the I/O class.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] Fixture "no CHANGELOG header + plugin.json version" exits 0 with `VERSION_SOURCE` reported as `plugin.json`.
- [ ] Fixture "no version source anywhere" exits non-zero AND stderr contains "Cannot detect version".
- [ ] Fixture "pyproject without top-level version" does not abort at the pyproject probe (script reaches its own diagnostic path).

**Effort:** S
**AID Role:** backend

### Step 3: Validate the target-version CHANGELOG entry before release commit

**Objective:** No release commit or plan-candidate preparation can succeed while the target version's CHANGELOG section is missing, empty, or still contains the generated placeholder; historical placeholders outside the target section never block.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~418-430, ~629-684) — add `_release_validate_changelog_entry <file> <version>` and call it at the two hook points: inside `cmd_prepare_plan` after `_release_update_files` (line ~629) and before staging (line ~637); inside `_release_commit_and_tag` before the `git commit` at line ~425.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-release-changelog-entry.bats` — fixtures: target section containing `_PM/agent: fill in entry content_` (blocked, names file+version+required edit, worktree left uncommitted); target section with one real bullet (passes); an OLD version's section containing the placeholder while the target section is complete (passes, placeholder reported as debt on stderr only).

**Architecture Context:** `update_changelog()` at lines 266-278 writes the literal placeholder `- _PM/agent: fill in entry content_` when it prepends a new section, and grounding confirmed no checker anywhere reads it back. `cmd_prepare_plan` is the high-value hook because its commit becomes the frozen, reviewed candidate; it already carries a battery of `PRECONDITION FAIL` checks (lines 632, 640, 660) that this validation joins.

**Implementation Detail:** `_release_validate_changelog_entry` extracts the block between `## [<version>]` and the next `## [` heading using awk; fails (exit 1, message `PRECONDITION FAIL: CHANGELOG entry for <version> in <file> is incomplete — replace the placeholder with a real user-facing description and rerun`) when the block is absent, contains the placeholder marker string, or has no line matching `^- [^_[:space:]]` (at least one real bullet). Placeholders found outside the target block produce a single stderr `WARNING: historical placeholder in section [X.Y.Z] — debt, not blocking`. Both CHANGELOGs (root and `plugins/aid-orchestrator/CHANGELOG.md`) are validated when both are in the update set.

**Error Handling:** Validation failure in `cmd_prepare_plan` exits before `git add`, leaving the worktree uncommitted for correction (matching the existing precondition style at line 630). In the legacy path it exits before `git commit`, leaving edits staged with an instruction to amend the entry and rerun.

**Edge Cases:**
- Target section exists with only a `### Changed` heading and no bullets: blocked (no real bullet).
- CHANGELOG uses a configured non-standard heading format so the target block cannot be located: blocked with a message naming the expected `## [<version>]` form (never a silent pass).
- Placeholder text appears inside a legitimate bullet as quoted prose (a bullet ABOUT the placeholder): the check matches the exact full placeholder line form `- _PM/agent: fill in entry content_` only, so quoted mentions pass.

**Dependencies:**
- Depends on: Step 2

**Acceptance Criteria:**
- [ ] Fixture with placeholder in target section: `prepare-plan` exits non-zero, stderr names file, version, and the required edit; `git status` shows no new commit.
- [ ] Fixture with completed target section but historical placeholder: exits 0 with a debt warning on stderr.
- [ ] Legacy `_release_commit_and_tag` path blocked by the same function (no commit, no tag created).

**Effort:** M
**AID Role:** backend

### Step 4: Human step rendering "Step N/T" on every prose surface and FSM message

**Objective:** Every human-facing rendering of `current_step` shows the 1-based executing step (`Step N/T` where N = current_step + 1 while executing), while machine fields, JSON output, and evidence filenames keep the 0-based compatibility index untouched.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-status.md` (lines ~60-70) — change the status template line to render `Step {current_step + 1}/{total_steps}` with an explicit instruction line "current_step is 0-based; render current_step+1 as the executing step; when state is GATES/DONE render {total_steps}/{total_steps}".
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~285-295) — same template change and rendering instruction for the run progress line.
- Modify: `plugins/aid-orchestrator/commands/aid-stop.md` (lines ~105-112) — same template change and rendering instruction for the stop status line.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~1030-1040) — same rendering rule applied to the progress template at line 1035 and the stale-state message at line 2306.
- Modify: `plugins/aid-orchestrator/skills/memory.md` (lines ~18-26) — same rendering rule applied to the memory read-out description at line 22.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~1787, ~1799, ~2931, ~2941) — extend the four operator-facing messages to append the human form, keeping the machine values first for grep compatibility: `PRECONDITION FAIL: current_step=${current} < total_steps=${total} (human: step $((current + 1)) of ${total} is next). Not all steps completed.`
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-fsm-step-render.bats` — asserts the four messages contain the `(human: step` suffix and that `get-state` JSON output (line ~3127) is byte-identical to before (still bare `current_step`).

**Architecture Context:** There is no `aid-status.sh`; rendering is prose-driven from the command/skill markdown, so the fix is an exhaustive enumeration of those templates (opponent-round requirement: a convention alone is not enforcement, and `skills/memory.md` must be included). The FSM's machine JSON (`get-state`, line 3127) and `fsm-state.yaml` are compatibility surfaces and stay 0-based.

**Implementation Detail:** Prose surfaces get both the rendered template and the one-line rendering rule so an agent reading a single file cannot re-derive the 0-based confusion. The semantics adopted: `current_step` counts completed steps; the human line names the step being executed (completed + 1), capped at `total_steps` when all are complete. The bash messages compute `$((current + 1))` inline; no shared helper is warranted for four sites (opponent-round simplification: no internal-index parenthetical in the default render).

**Error Handling:** If `current_step` is non-integer, the existing malformed-state error at line 2931 fires before any arithmetic; the new suffix is added only on the two arithmetic-safe messages at lines 1787/1799 plus a guarded form at 2941.

**Edge Cases:**
- `current_step == total_steps` (all done, pre-GATES): human form renders `step ${total} of ${total} complete` rather than a nonsensical `step N+1`.
- `total_steps == 0` (degenerate plan): messages render machine values only, no human suffix.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] `grep -n 'current_step}/{total_steps}' plugins/aid-orchestrator/commands/ plugins/aid-orchestrator/skills/ -r` returns zero matches (all templates rewritten to the +1 form).
- [ ] New bats test passes: four messages carry the human suffix; `get-state` JSON unchanged.
- [ ] `commands/aid-status.md` documents the 0-based machine field explicitly next to the rendered form.

**Effort:** S
**AID Role:** backend

### Step 5: One dependency grammar — `none` accepted, silent drops abolished

**Objective:** `Depends on: none` and the generated-canonical `---` are the two accepted no-dependency forms, documented in plan-writing.md; every other unrecognised token fails loudly in both parsers and aborts conversion; the indented `Blocks:` continuation trap is fixed.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-source-plan-graph.sh` (lines ~19-20, ~66) — accept `none` (case-insensitive) alongside `---` as the explicit no-dependency marker; exclude lines matching `Blocks:` from the continuation fold at line 66 so an indented `- Blocks: Step 5` is never folded into the depends set.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (lines ~421-455, ~918-922) — `parse_step_deps()` gets an else-branch that prints `ERROR: step <N>: unrecognised dependency token '<token>' — accepted: 'Step N', 'Steps N-M', 'none', '---'` and returns 1; both call sites propagate the failure and abort generation (exit non-zero) instead of continuing with a silently emptied dependency.
- Modify: `plugins/aid-orchestrator/scripts/aid-generation-readiness.sh` (lines ~35-37) — the FAIL message now names the accepted forms including both no-dependency markers.
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~287-297) — the Dependency grammar block documents `Depends on: none` as the authoring form and `---` as the generated-canonical equivalent, and states that everything else blocks generation.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-dep-grammar.bats` — cases: `none`/`NONE`/`---` all parse as no-dependency in both parsers; `Depends on: nothing` aborts `aid-plan-to-epic.sh` with the new ERROR and non-zero exit; an indented `- Blocks: Step 5` under a `Depends on: Step 2` block yields exactly `[2]`, no spurious forward-dependency failure.

**Architecture Context:** Grounding found three parsers with three grammars: the canonical `aid-source-plan-graph.sh` accepts only `---` (undocumented), `aid-plan-to-epic.sh:421-455` silently drops unmatched tokens and renders `none` as no-dependency (the exact interpretation plan-writing.md forbids), and `aid-epic-to-json.sh:286-290` accepts a broader punctuation set (left unchanged — it is downstream of generation and its tolerance is harmless once upstream is loud). The `aid-source-plan-graph.sh` header comment "Consumers must not invent a second awk parser" is honoured by making the second parser fail loudly on anything the canonical one would reject, rather than attempting a risky consolidation in this plan.

**Implementation Detail:** In `aid-source-plan-graph.sh` line 19, extend the normalised-input check to `case "$(printf '%s' "$raw" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')" in ---|none) return 0;; esac`. In the awk continuation clause at line 66, add `&& $0 !~ /Blocks:/` to the indented-line branch. In `parse_step_deps()`, the token loop's unmatched branch (currently absent) sets a failure flag with the ERROR message; the function returns 1 and `aid-plan-to-epic.sh`'s caller checks the return and exits (the current behaviour at lines 918-922 that maps unparseable to `---` is deleted).

**Error Handling:** The ERROR message always includes the step number and the offending token verbatim, so the author can fix the exact line. Generation aborts before writing any EPIC file for the affected plan (no partial output).

**Edge Cases:**
- `Depends on: Step 2 — needs the force helper`: an annotation after an em dash is DEFINED as supported syntax — the grammar becomes `Depends on: <refs> [— annotation]`; both parsers split on the FIRST em dash, parse only the left side strictly (every token there must be recognised), and ignore the annotation. `Depends on: Step 2, banana` (unrecognised token on the left side) fails loudly; the bats suite includes mixed valid-plus-invalid cases for both parsers.
- Mixed `Depends on: none, Step 3`: contradictory — fails loudly (a no-dependency marker with any step reference is unrecognised as a whole).
- Legacy plans in `.aid-o/plans/archive/` are never re-parsed; only live generation is affected.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] All new bats cases pass, including the abort-on-unrecognised-token case with non-zero exit of `aid-plan-to-epic.sh`.
- [ ] `plan-writing.md` documents both accepted no-dependency forms in the Dependency grammar block.
- [ ] `aid-generation-readiness.sh` FAIL output names `none` and `---` explicitly.

**Effort:** M
**AID Role:** backend

### Step 6: Hard stop with recovery instructions when batch generation cannot restore the branch

**Objective:** When post-generation branch restoration fails, the pipeline stops immediately with a non-zero exit and an explicit recovery instruction naming the branch to switch back to, instead of continuing on the wrong branch behind a WARNING.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-json-to-run.sh` (lines ~722-731) — the restore-failure branch changes from `WARNING` to `ERROR: generation completed but the checkout is now on '<current>' instead of '<original>' — run: git checkout <original> ; then rerun any follow-on action` and returns a distinct non-zero exit code (3) that `aid-auto-pipeline.sh` propagates.
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (lines ~55-70 argument/flow region) — propagate the restore-failure exit distinctly so the queue/report phase does not run after a failed restore.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-branch-restore.bats` — exercises the actual restore-failure path (fixture makes `git checkout` of the original branch fail by deleting the branch ref between init and restore) and asserts: non-zero exit, the recovery instruction on stderr, and no queue entry written; plus the success case: generation started from a feature branch ends on that branch.

**Architecture Context:** Grounding verified restoration already exists (`aid-json-to-run.sh:722-731`, switch happens in `aid-fsm.sh init` at lines 2596-2607) and that the dirty-runtime-pointer claim from the source doc is refuted for this repo (`.aid-o/` is gitignored). The only real gap is the WARNING-only failure mode, which leaves subsequent phases generating onto the wrong branch. Per the opponent round, the stop happens at the point of failed restore — before any follow-on queue/release action — not merely at the end.

**Implementation Detail:** The restore block already computes `fsm_after_branch` and attempts `git checkout "$fsm_branch"`; on failure it now prints the ERROR with both branch names and `exit 3`. `aid-auto-pipeline.sh` checks the child exit status where it invokes the json-to-run phase and aborts its remaining phases with the same message passed through. Generated artifacts from the completed phase are left in place (they are valid); only continuation is stopped.

**Error Handling:** Restore failure caused by uncommitted changes created during generation prints the underlying `git checkout` stderr beneath the recovery instruction so the operator sees why the switch failed.

**Edge Cases:**
- Original branch deleted mid-run (the fixture case): recovery instruction still names it; operator recreates or picks a new branch consciously.
- Detached-HEAD start: `fsm_branch` is `HEAD`; the existing guard (`fsm_branch != "HEAD"`) skips restore entirely — unchanged, covered by a test assertion.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] Restore-failure fixture: exit 3, stderr contains `git checkout` recovery line, no queue entry exists.
- [ ] Success fixture: run started on `feature/x` ends on `feature/x` with exit 0.
- [ ] Detached-HEAD fixture: no restore attempted, no error.

**Effort:** S
**AID Role:** backend

**EPIC 2: Steps 7-13 — PM Force Backdoor and Trap Elimination**

### Step 7: Plan-level force framework in aid-plan-fsm.sh

**Objective:** A shared `_pfsm_handle_force()` exists that validates `--force --reason` (min 20 chars), classifies each command's preconditions as `forceable` or `hard`, and writes the three audited records (timeline event, audit-log append, HEAD-bound waiver artifact with a `bypassed_preconditions` array) into the plan-final evidence dir where the C4 aggregator surfaces it.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (new function block near line ~250, before `_pfsm_preflight`) — add `_pfsm_handle_force <command> <plan_id> <reason> <bypassed_csv>` mirroring `fsm_handle_force_override` (aid-fsm.sh:846): reason length check, `log_event "$timeline" "plan_force_override" ...`, `fsm_emit_audit_log`-equivalent append via `scripts/aid-audit-log.sh`, and a protocol-v2 waiver artifact written to the plan-final evidence dir (`plan_final_evidence_dir` from the manifest; fallback `.aid-o/work/plan-final/<plan_id>/` when no attempt exists yet) with fields: command, plan_id, from/to state, candidate_sha (when set), bypassed_preconditions[], reason, operator, head_sha, timestamp, `forced_override: true`.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (precondition sites, marker comments) — annotate each precondition check invoked by public subcommands with a `# force: forceable` or `# force: hard` marker comment plus a wrapper `_pfsm_precondition <name> <forceable|hard> <check-fn> ...` so the classification is code, not prose. `hard` is reserved for physical git impossibilities: unresolvable merge state, missing branch/commit object, unreadable repository.
- Modify: `plugins/aid-orchestrator/defaults/schemas/waiver.schema.json` — placement per the schema's actual strictness scope: `additionalProperties: false` applies to the `waiver` SUBOBJECT only, so `bypassed_preconditions` goes as an optional TOP-LEVEL artifact field (sibling of `waiver`), where additions are structurally permitted today; the schema is updated to DECLARE the field explicitly (documentation and validation, not a compatibility workaround), the force-waiver producer writes it there, and `aid-protocol-validate` fixtures cover a force waiver with and without the field.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-plan-force.bats` — helper-level cases: reason under 20 chars dies; a forced call writes all three records; the waiver artifact carries `bypassed_preconditions` and `forced_override: true`; a `hard` precondition is never bypassed even with `--force`.

**Architecture Context:** Per the Force and recovery subsystem: `aid-fsm.sh` already writes three records per force and C4 surfaces the waiver in `waivers_applied[]`; this step ports that exact pattern to the plan FSM with one added field, rather than inventing a fourth persistence mechanism (opponent-round agreement). The force receipt is a record of what happened, never a consumable authorization — the consumable-grant concept exists only for the C0/C3 override artifacts in Step 10.

**Implementation Detail:** The wrapper executes the check; on failure it prints the check's own recovery message FIRST (the normal path), then — only when force is active AND the check is `forceable` — records the bypass name and continues. The waiver artifact reuses the schema shape from `aid-fsm.sh` lines 908-925 (filename `waiver-plan-<command>-<ts>.json`, HEAD-bound via `git rev-parse HEAD`) so `aid-protocol-validate` and the C4 aggregator consume it without schema changes beyond the additive `bypassed_preconditions` array. Timeline file resolution: the plan-final run's timeline when an attempt exists, else the audit log alone (log_event is a silent no-op without a timeline file, matching existing behaviour).

**Error Handling:** If the waiver artifact cannot be written (unwritable evidence dir), the force attempt itself fails closed with `PRECONDITION FAIL: cannot write force receipt — refusing a silent bypass`, leaving state unchanged. Audit-log append stays best-effort (matching `fsm_emit_audit_log`'s `|| true` contract) because the waiver artifact is the authoritative record.

**Edge Cases:**
- Force invoked before any plan-final attempt exists (no evidence dir): fallback dir `.aid-o/work/plan-final/<plan_id>/` is created; because the C4 aggregator scans `waiver-*.json` only under the CURRENT attempt's evidence dir, `_pfsm_finalize_freeze`'s attempt-dir allocation (aid-plan-fsm.sh lines ~2242-2252, modified in this step) additionally SWEEPS any `waiver-plan-*.json` from the fallback dir into the newly allocated run dir (move, not copy, so a receipt is never double-counted) — a bats case in `test-plan-force.bats` proves a pre-attempt force receipt appears in the first C4 aggregation.
- Two forced invocations in one command run: impossible by construction — the flag is parsed once per invocation and nothing is exported to child processes.
- Reason containing shell metacharacters or newlines: passed as a single argv element end-to-end; jq `--arg` encoding in the artifact writer prevents injection.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] Helper bats cases pass: 3 records written, short reason dies, hard precondition never bypassed.
- [ ] The waiver artifact validates against the protocol-v2 waiver schema (additive field tolerated).
- [ ] A C4 aggregation over a fixture evidence dir lists the plan-level force in `waivers_applied[]`.

**Effort:** M
**AID Role:** backend

### Step 8: Wire --force --reason into all eight public plan-lifecycle commands

**Objective:** `plan-start`, `epic-start`, `epic-complete`, `epic-merge-to-plan`, `plan-finalize`, `plan-merge-to-main`, `plan-close`, and `plan-rollback` each parse `--force`, bypass only their forceable preconditions through `_pfsm_handle_force`, print the exact normal recovery before offering force, and — for merge/close — durably attach the force receipt to the lifecycle record with a reconciliation fallback. The force reason is supplied via `--reason` on seven commands; `plan-rollback` alone uses `--force-reason` (its `--reason` already carries the rollback business reason) — this single documented exception is part of the public CLI contract and repeated in every usage/help text this step touches.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (argument loops at lines ~442, ~655, ~1058, ~1438, ~4180, ~4426, ~5036, ~6659) — each `--*) ... unknown flag` rejection gains `--force) force=1; shift ;;` and `--reason) reason="$2"; shift 2 ;;` branches ahead of it; each command's forceable precondition failures route through the Step 7 wrapper when `force=1`.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (merge/close receipt attachment, lines ~3301-3340 close-evidence region and ~5036-5200 plan-close region) — a forced merge/close embeds `forced_override: true` plus the waiver artifact's sha256 into the close-evidence receipt (`_pfsm_seal_plan_final_close_evidence`) and the lifecycle closure receipt (`aid_lifecycle_commit_receipt`); when that durable write is itself the broken operation, the local waiver artifact is kept and the command prints `RECONCILIATION REQUIRED: force receipt written locally at <path> — attach it to the lifecycle record once <operation> is repaired` and still completes the forced operation. The two receipt contracts are updated IN THIS STEP, atomically with the producer: the close-receipt grammar validator `_pfsm_validate_plan_final_close_receipt_json` accepts the optional `forced_override`/`force_waiver_sha256` keys, and `plugins/aid-orchestrator/defaults/schemas/plan-lifecycle-receipt.schema.json` plus the receipt builder/validator in `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (`aid_lifecycle_build_receipt`, `aid_lifecycle_validate_artifact` call sites) gain the same optional fields — a legacy receipt without them still validates.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (plan-rollback argument loop, lines ~6659 region) — CLI grammar collision resolved explicitly: `cmd_plan_rollback` KEEPS its existing `--reason` as the rollback business reason; the force path on this one command uses a distinct `--force-reason "<text>"` flag (validated ≥20 chars by the shared handler); passing `--force` without `--force-reason` on plan-rollback dies naming both flags; every other command uses plain `--reason` as documented. A forced-rollback bats case asserts both values land in their respective records (rollback record vs force waiver).
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (plan-final sections, lines ~1270-1330) — document the force path per command: normal recovery first, force as the explicit second route, forced close ends the plan with ordinary closure semantics plus the visible `forced_override` marker.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-plan-force-commands.bats` — one normal fail-closed case AND one forced case per command (8 pairs); the forced-close fixture uses a deliberately corrupted manifest, ends terminal, and its closure receipt carries `forced_override: true`; a forced case never bypasses a `hard` precondition.

**Architecture Context:** Grounding inventoried every entry point and its current hard rejection of `--force` (the source of the P082 stranding: `plan-close` is the terminal operation a PM must always be able to complete). The PM decided universality (source doc D6) over the opponent's narrow-force preference; the forceable/hard split is the agreed compromise — universality of the FLAG, bounded scope of what it can bypass. Scope boundary (per the Scope section): force covers the eight state-TRANSITION commands only; `plan-state` (repair/attest/supersede) and `inventory --apply` remain non-forceable because they are themselves the audited recovery mechanisms — each of the eight commands' refusal messages that point at a recovery command name this distinction.

**Implementation Detail:** Per command, the forceable set (initial classification, adjustable during implementation review): `plan-start` — clean-worktree, lineage-mismatch-on-existing-branch; `epic-start` — lineage verification, manifest-entry absence; `epic-complete`/`epic-merge-to-plan` — state-order preconditions, evidence completeness; `plan-finalize` — stage-order, dirty-tree (non-review stages), target-drift refusal at freeze; `plan-merge-to-main` — decision/candidate timestamp ordering, stale-target invalidation (NOT the three-way SHA identity when the decision SHA is absent entirely — that is `hard` since there is nothing the PM authorized); `plan-close` — every bookkeeping completeness check (unreachable receipts, missing delivery records); `plan-rollback` — delivered-path overlap warnings. Each forced completion routes state transitions through the existing sanctioned mutators (`plan_manifest_*` functions), never raw yq edits, so manifest invariants hold even under force.

**Error Handling:** A force that would still fail on a `hard` precondition reports both: the hard failure AND the note that force cannot bypass it, with the concrete repair (or `plan-rollback`/manual git surgery) named. Receipt-attachment failure downgrades to the reconciliation message — never a silent success, never a blocked terminal operation. Lifecycle-state truthfulness under a broken receipt write: because `aid-lifecycle.sh` defines `closed` as receipt-committed-and-reachable, a forced close whose lifecycle receipt write is the broken operation does NOT claim `closed` — it records the terminal state as `closed_pending_receipt` (a NEW enum value added in this step to `plugins/aid-orchestrator/defaults/schemas/plan-lifecycle-receipt.schema.json`'s state enum and to every state-enum check in `lib/aid-lifecycle.sh` — the schema today permits only `closed`/`delivered-but-unreconciled`/`legacy-unverifiable`, so the enum extension ships atomically with the producer) with the local waiver sha256 and the reconciliation instruction; the follow-up receipt commit (once the write path is repaired) flips it to `closed`. The lifecycle contract is never silently contradicted.

**Edge Cases:**
- Forced `plan-close` on a plan whose branch was deleted manually: closure receipt records `plan_branch: missing`; close completes (that is exactly the stranding scenario the backdoor exists for).
- `--force` without `--reason` or with reason under 20 chars: dies with the same message as `aid-fsm.sh` (consistent operator experience).
- Force on a command whose preconditions all pass: no-op flag; a `force_unused: true` note is logged to the timeline, no waiver artifact is written (nothing was bypassed).

**Dependencies:**
- Depends on: Step 7

**Acceptance Criteria:**
- [ ] All 8 command pairs (normal fail-closed + forced) pass in bats.
- [ ] Forced-close-on-corrupted-fixture is terminal; CLI output and closure receipt both state the override.
- [ ] A forced merge with a broken lifecycle write completes with the RECONCILIATION message and a local receipt.
- [ ] No command accepts `--force` silently: either it forces (with receipt) or it rejects with the unknown-flag error (non-lifecycle read-only commands).

**Effort:** L
**AID Role:** backend

### Step 9: Repair the three existing force anomalies

**Objective:** `aid-fsm.sh plan-close` parses `--force --reason` through the audited path instead of silently swallowing it; `aid-fsm.sh init` rejects unknown flags loudly; the legacy `aid-release.sh --force` requires a reason and writes the same three audit records.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~5405-5412, ~2305-2308) — `cmd_plan_close` gains an argument loop with `--force/--reason` routed through `fsm_handle_force_override` and an unknown-flag rejection; the `init` argument parser's silent `*)` fallthrough becomes `die "Unknown flag for init: $1"`.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~3-4 usage, ~145-160) — the legacy `--force` requires `--reason` ≥20 chars; on use it appends an audit-log record via `scripts/aid-audit-log.sh` and writes a HEAD-bound waiver artifact into the active run's evidence dir when a state file exists, else into `.aid-o/work/release-force-<ts>.json`; usage text updated.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-force-anomalies.bats` — `plan-close --force` without reason dies; with reason writes records; `init --bogus-flag` dies naming the flag; `aid-release.sh auto --force` without reason dies, with reason writes the audit record.

**Architecture Context:** Grounding flagged these as the only inconsistencies in the force landscape: a silently ignored `--force` (worse than rejection — the operator believes they forced something), a silent unknown-flag sink on `init`, and the one unaudited bypass in the system (`aid-release.sh:149-157` recommends `--force` with no reason and no record).

**Implementation Detail:** `cmd_plan_close`'s three positionals stay positional; flags are peeled first in a loop identical in shape to `cmd_transition`'s. For `init`, the existing comment claims unknown flags are "safe to ignore" — the new rejection is compatible because all sanctioned callers pass only documented flags (verified by grepping `commands/*.md` and `skills/*.md` for init invocations during implementation; any undocumented caller surfaces loudly, which is the point). The release-path waiver artifact reuses the writer from `fsm_handle_force_override` extracted into a small shared function if extraction is trivial; otherwise a local 20-line jq writer with identical fields.

**Error Handling:** Waiver-write failure in `aid-release.sh` fails the force (consistent with Step 7's fail-closed receipt rule).

**Edge Cases:**
- `plan-close` called with legacy positional-only arguments: unchanged behaviour, no flags parsed, no regression.
- `aid-release.sh --force` in a repo with no `.aid-o/` at all: artifact path falls back to the repo root temp-adjacent `.aid-release-force-<ts>.json` with a stderr note (never silently skipped).

**Dependencies:**
- Depends on: Step 7

**Acceptance Criteria:**
- [ ] All four anomaly bats cases pass.
- [ ] `grep -n 'Or use --force to bypass' plugins/aid-orchestrator/scripts/aid-release.sh` returns zero matches (message rewritten to name the reason requirement).
- [ ] No call site in `commands/` or `skills/` passes an init flag that the new strict parser rejects.

**Effort:** S
**AID Role:** backend

### Step 10: One PM-override artifact schema for C0 and C3 exhaustion

**Objective:** C3 exhaustion is unlocked by the same single-use, atomically-claimed artifact mechanism C0 already uses — produced by a public grant subcommand, consumed with the `mv -n` + sha256 pattern — and the bare `AID_C3_FORCE_BEYOND_ESCALATION` env var becomes a one-release deprecated compatibility input that is converted, warned about, and claimed through the same path.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (dispatcher region, lines ~6107-6131) — new subcommand `pm-override grant <c0|c3> <plan_id> --reason "<text>"` writing the artifact: C0 target → `.aid-o/work/evidence/<plan_id>/cp1-pm-escalation-override.json` (existing path, existing schema `{pm_ref: ...}` extended additively with `target`, `plan_id`, `created_at`); C3 target → `<c3_evidence_root>/c3-pm-escalation-override.json` with the identical schema. Refuses to overwrite an existing unconsumed artifact.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh` (lines ~1995-2010) — the exhaustion gate replaces the env-var check with: (1) look for `c3-pm-escalation-override.json`; (2) if absent AND the env var is set with ≥20 chars, write the artifact from the env value with `WARNING: AID_C3_FORCE_BEYOND_ESCALATION is deprecated — converted to a single-use override artifact; this compatibility path is removed in the next release`; (3) atomically claim the artifact (`mv -n` to `.consumed-<epoch>`, sha256 recorded in the C3 loop state) exactly like `aid-cp1-ledger.sh:234-249`; a claim grants exactly one additional fresh session.
- Modify: `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md` (lines ~230-240) — document the grant command as THE PM route for the C0 loop; agents are forbidden from creating the artifact or setting the env var themselves.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~1655-1665) — document the grant command as THE PM route for the C3 loop with the same agent prohibition.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-c3-fix-loop.bats` (lines ~681, ~686, ~734, ~739, ~786, ~996) — update every assertion of the direct env-var gate (`AID_C3_FORCE_BEYOND_ESCALATION` set/unset/short cases) to the artifact-based flow: env-present cases now assert the deprecation-conversion warning plus a consumed artifact; artifact cases assert the single-use `mv -n` claim; the short-reason rejection assertion is retargeted at the artifact `pm_ref` validation.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-pm-override.bats` — grant writes a valid artifact and refuses a duplicate; C3 claim is single-use (second exhausted attempt without a fresh grant fails closed); env-var conversion emits the deprecation warning and still consumes atomically (no double-use when both env and artifact exist); a hand-written artifact with a short `pm_ref` is rejected.

**Architecture Context:** Grounding showed two opposite override philosophies coexist: C3's receipt-less env var (stderr only, reusable) versus C0's single-use corroborated artifact (`aid-cp1-gate.sh:344-359`, `aid-cp1-ledger.sh:483,689-700`) — with C0's own error text explicitly rejecting the env model. Convergence direction (artifact) was agreed by both reviewers; housing the producer as an `aid-fsm.sh` subcommand (not a new script) was the opponent-round simplification.

**Implementation Detail:** The grant subcommand validates reason length, resolves the target evidence root (C0: plan evidence root; C3: the C3 evidence root recorded in the loop state, or the current run's evidence dir), and writes with a `mktemp`+`mv` atomic pattern. The env-var compatibility conversion is implemented in ONE named function `_c3_convert_env_override()` in `aid-c3-dispatch.sh` — the deprecated variable may be referenced ONLY inside that function (and its doc comment), which is what plan-level AC4 mechanically checks. The consumer-side claim in `aid-c3-dispatch.sh` records `override_consumed_sha256` in the loop state file mirroring the ledger's corroboration fields so a later audit can verify the claim (fields named identically to `aid-cp1-ledger.sh`'s for consistency). Existing `cp1-pm-escalation-override.json` consumers (`aid-cp1-gate.sh`, `aid-cp1-ledger.sh`) are untouched — the additive fields are ignored by their `jq -r '.pm_ref'` reads.

**Error Handling:** Grant into an unresolvable evidence root dies naming the expected directory. A claim race (artifact consumed between check and claim) fails closed exactly like the CP1 primitive: on installed coreutils 9.1 a skipped `mv -n` exits 0, so the loser is detected by the mandatory `[[ ! -f src ]]` post-check from `aid-cp1-gate.sh:352` — copy that corroboration pattern verbatim, never trust the `mv -n` exit code alone.

**Edge Cases:**
- Env var set with a value under 20 chars: rejected with the existing message shape; no artifact written.
- Both env var and an unconsumed artifact present: the artifact wins; env is ignored with a notice (prevents the double-use race the opponent flagged).
- Env compatibility is itself single-use per plan: the conversion stamps `origin: env` into the artifact it writes, and BEFORE converting, `_c3_convert_env_override` scans for any existing `.consumed-*` sibling whose `origin` is `env` — if one exists, the still-exported variable is NOT converted again; the gate refuses with `the deprecated env override was already consumed once — use 'aid-fsm.sh pm-override grant c3 <plan_id> --reason ...' for a further attempt`, so a lingering export can never become a standing multi-use bypass.
- Grant for a plan with no C3 loop state yet: written into the current run's evidence dir with a stderr note naming where the consumer will look.

**Dependencies:**
- Depends on: Step 7

**Acceptance Criteria:**
- [ ] All bats cases pass, including single-use enforcement and the both-sources race case.
- [ ] `grep -rn 'AID_C3_FORCE_BEYOND_ESCALATION' plugins/aid-orchestrator/scripts/` shows only the deprecation-conversion site plus updated comments (the stale doc comment at `aid-c3-dispatch.sh:185` is rewritten in this step); no gate reads the env directly.
- [ ] The grant subcommand appears in `review-checkpoint-contracts.md` and `pipeline.md` as the sole PM route.

**Effort:** M
**AID Role:** backend

### Step 11: Committed-source preflight before plan lifecycle creation (P083)

**Objective:** No plan branch, task branch, or lifecycle manifest can be created while the source plan is absent from the target branch or differs from the worktree bytes being generated; gitignored plans are bound via `source_plan_sha` in the committed manifest instead.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (lines ~60-70, before lifecycle stamping at ~325-350) — after the file-exists check: if the plan path is NOT matched by `.gitignore` (`git check-ignore -q`), require `git cat-file -e <target_branch>:<plan_path>` and byte-equality between `git show <target_branch>:<plan_path>` and the worktree file; on failure refuse with exactly `PRECONDITION FAIL: source plan is not committed on <target_branch> (or differs from the worktree copy) — commit the plan on <target_branch> and rerun generation.`; if the path IS gitignored, log `plan_source_binding: source_plan_sha` and proceed (the manifest's existing `source_plan_sha` field is the binding).
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~435-470, `cmd_plan_start`) — optional `--plan-file <path>` argument; when provided, run the identical check before `_pfsm_preflight`; when absent (legacy callers), behaviour is unchanged (the production caller `aid-auto-pipeline.sh` always passes it after this step). When `--plan-file` is provided, the repo-relative path is additionally stamped into the lifecycle manifest as the new optional field `source_plan_path` (consumed by Step 15's protected-set computation; legacy manifests without it use Step 15's documented glob fallback).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — this step registers its own preflight entry (type: out-of-band hard fail, surface: aid-auto-pipeline/plan-start) so the step's acceptance criterion is satisfiable at step completion, independent of Step 19.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-committed-source.bats` — fixtures: tracked plan uncommitted (refused; `git branch -a` and `.aid-lifecycle/manifests/` prove no branch/manifest was created); tracked plan committed but worktree edited (refused, same proof); tracked plan committed and identical (proceeds); gitignored plan (proceeds with the binding log line).

**Architecture Context:** Grounding confirmed the P083 gap end-to-end: `aid-auto-pipeline.sh:60-61` checks only disk existence, `cmd_plan_start` never sees a path, and the clean-worktree preflight's `--untracked-files=no` makes a never-added plan invisible. The check lives where the path is known (opponent-round blocking finding), refuses BEFORE any git mutation, and the gitignored carve-out exists because this very repository gitignores `.aid-o/plans/` — a hard tracked-only rule would break the plugin's own dogfood workflow.

**Implementation Detail:** Byte-equality via `git show <target>:<path> | cmp -s - <worktree_path>`. Target branch resolved from the same source `aid-auto-pipeline.sh` already uses for the manifest-mode probe (line ~329 `aid_target_branch`). The PM decision (brainstorm log item 4) keeps strict byte equality: an intentional newer edit is committed first — that is the entire point of the preflight. Register the new refusal in `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` (type: out-of-band hard fail, surface: aid-auto-pipeline/plan-start).

**Error Handling:** `git cat-file`/`git show` failures for reasons other than absence (corrupt object store) print the underlying git stderr beneath the PRECONDITION FAIL line.

**Edge Cases:**
- Plan committed on a different branch than target: refused (the check is target-branch-specific by design; the message names the target).
- Plan path tracked but target branch does not exist yet (fresh repo): refused with a message to create/commit the target branch first.
- CRLF-vs-LF differences from an editor: byte equality fails — intended (commit normalises what will be generated from).

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] All four fixtures pass; the two refusal fixtures prove zero branches and zero manifest files were created.
- [ ] The refusal message matches the specified wording including the target branch name.
- [ ] Enforcement-registry entry exists for the new preflight.

**Effort:** M
**AID Role:** backend

### Step 12: Immutable review boundary — Reporter writes run-scoped evidence only (P082)

**Objective:** The plan-final Reporter contract no longer instructs committing anything; delivery report and boundary manifest are run-scoped evidence during review, the committed-claims/gitignore self-contradiction in reporter.md is resolved, the human/CI projection is rendered by `plan-close`, and one identical boundary rule lives in pipeline.md with role cards referencing it.

**Files:**
- Modify: `plugins/aid-orchestrator/agents/reporter.md` (lines ~105-165) — delete every "Committed" claim (lines 110-111, 143-146, 157, 161-162); both outputs are written to the run evidence dir (`delivery-report.json` authoritative, `<plan_id>-delivery.md` + `<plan_id>-boundary.md` as evidence-dir projections); the at-HEAD binding paragraph (lines 135-138) stays as the single source of truth it already was.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (plan-close region, lines ~5036-5200) — `cmd_plan_close` renders the human projection `.aid-o/reports/<plan_id>-delivery.md` and `.aid-o/reports/<plan_id>-boundary.md` from the verified `delivery-report.json` in the run evidence dir recorded in the manifest (`plan_final_evidence_dir`); rendering failure is a warning, never a close blocker (the JSON remains authoritative).
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~1307-1320) — one boundary rule stated once: "After freeze, plan-final agents write only run-scoped evidence. A tracked candidate write is a FIX and requires a new candidate/review. The controller alone renders committed/worktree projections, after merge/close."; role-card and agent files REFERENCE this paragraph instead of restating it.
- Modify: `plugins/aid-orchestrator/skills/role-cards.md` (plan-final roles region) — replace any commit instruction for plan-final specialists with the pipeline.md reference.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-reporter-boundary.bats` — a full simulated Reporter review round (fixture evidence dir + plan branch) completes with `git rev-parse plan/<id>` unchanged and `_pfsm_review_candidate_drift` returning 0; `plan-close` produces both projections from the fixture `delivery-report.json`.

**Architecture Context:** Grounding proved the contradiction is triple-layered: reporter.md orders commits, pipeline.md:1312-1319 invalidates on any tracked write during review, and the ordered path `.aid-o/reports/` is gitignored (`.gitignore:96,98`) making the order unexecutable — reporter.md:135-138 even says so itself. The projection moves to `plan-close` because grounding located the concrete wiring point (opponent-round blocking finding: an unnamed "post-close transaction" is not wiring).

**Implementation Detail:** The `plan-close` renderer is a deterministic jq/awk transform of `delivery-report.json` (summary, per-EPIC verdicts, delivered paths) plus the boundary manifest fields reporter.md already specifies (delivery_report filename, run_id, candidate_sha). In consumer repositories where `.aid-o/` is tracked, these writes occur AFTER close — outside any freeze window — and fall under EPIC 3's ancillary policy for any later plan.

**Error Handling:** Missing or schema-invalid `delivery-report.json` at close: projection skipped with `WARNING: no verified delivery-report.json — human projection not rendered`; close proceeds (bookkeeping completeness for the JSON itself is a close-check concern, forceable per Step 8).

**Edge Cases:**
- Legacy `legacy_epic_release_mode` plans: Reporter cadence is per-EPIC there; reporter.md edits scope the run-evidence-only rule to plan-final dispatch, leaving legacy per-EPIC behaviour explicitly unchanged.
- Re-close after a forced close: projections are overwritten idempotently (derived artifacts, no history value).
- `.aid-o/reports/` unwritable at close (permissions or read-only checkout): the projection warning names the directory and close still completes — projection rendering is never a close blocker.

**Dependencies:**
- Depends on: Step 8

**Acceptance Criteria:**
- [ ] `grep -n 'Committed' plugins/aid-orchestrator/agents/reporter.md` returns zero matches in the outputs section.
- [ ] The Reporter-round bats fixture completes one review round without moving `candidate_sha` and without drift invalidation.
- [ ] `plan-close` renders both projections from fixture JSON; a missing JSON yields the warning and a completed close.

**Effort:** M
**AID Role:** backend

### Step 13: Supported recovery — supersede a stale EPIC run, attest a moved base

**Objective:** A PM-audited `plan-state --supersede-epic` archives a stale EPIC FSM run and permits re-initialization against a new plan.json hash under a precisely-bound supersede record, and `--attest-source-ref` is extended to recompute the recorded `epic_base_commit` from real git ancestry, so a manually moved task branch has a supported recovery that is not `--force`.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (plan-state region, lines ~5279-5360) — new flag `--supersede-epic <epic_id> --reason "<text>"`: refuses after the EPIC merged (manifest entry state), renames the EPIC's `fsm-state.yaml` to `fsm-state.yaml.superseded-<epoch>` (evidence dirs untouched), and writes a supersede record `.aid-o/work/plan-state/supersede-<plan_id>-<epic_id>-<epoch>.json` (the SAME epoch as the state-file rename, so producer and archive names pair 1:1 and a second supersede never collides with or overwrites the first) binding `{plan_id, epic_id, old_state_sha256, old_run_id, new_plan_json_sha256, reason, operator, created_at}`; init-side selection is deterministic: among records for the plan/EPIC pair, exactly the one whose `old_state_sha256` matches the newest archived state file authorizes, and consumption renames exactly that record to `.consumed-<consume_epoch>` — older records stay inert forever; extend `_pfsm_plan_state_attest` (lines ~5341-5360) with `--recompute-base`: recomputes `merge-base(task_branch, plan/<id>)` and updates the manifest's recorded `epic_base_commit` alongside the existing unproven→proven flip, with the old and new base recorded in the audit log.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~2491-2494) — the unconditional duplicate-init rejection gains one narrow branch: when the state file at the path is a `.superseded-<epoch>` sibling situation (live state file absent, matching supersede record present whose `old_state_sha256` equals the archived file's hash AND whose `new_plan_json_sha256` equals the hash of the plan.json now being initialized), init proceeds and consumes the record (renames it `.consumed-<epoch>`); any mismatch keeps the existing hard rejection.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — this step registers its two recovery-transaction entries (supersede verifier in init, recompute-base attestation) so the step's acceptance criterion is satisfiable at step completion, independent of Step 19.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-supersede-recovery.bats` — supersede then re-init succeeds with the new plan.json and preserves the old evidence dir; re-init with a mismatched plan.json hash is rejected; supersede after the EPIC merged is refused; a stale/forged supersede record (wrong `old_state_sha256`) never authorizes init; `--attest-source-ref --recompute-base` updates the recorded base and the subsequent `_pfsm_verify_epic_lineage` passes.

**Architecture Context:** Grounding established the existing primitives this extends: `plan-state --repair` deliberately cannot rewrite lineage, `--attest-source-ref` is THE sanctioned unproven→proven flip (aid-plan-fsm.sh:5341), the lineage check compares `merge-base` against `recorded epic_base_commit` (lines 357-363), and `aid-fsm.sh:2491` rejects duplicate init unconditionally. The opponent round demanded the precise supersede-record binding (blocking finding 3) and preferred deferring a separate `--rebase-epic`; the PM decision (brainstorm log item 7) adopts the attestation extension as the moved-branch recovery.

**Implementation Detail:** `--supersede-epic` validates the EPIC belongs to the plan (manifest entry exists) and its state is not merged; the record is written with `mktemp`+`mv`. The init-side verifier loads the record, hashes the archived state file and the incoming plan.json, and compares both — four-field binding means a record can authorize exactly one specific re-init. `--recompute-base` requires the task branch to exist and `merge-base` to resolve; it never touches `lineage` semantics beyond what attest already does (base update + proven flip are one audited operation). Register both new transactions in the enforcement registry (type: PM-audited recovery transaction).

**Error Handling:** Supersede of an EPIC with no state file: refused ("nothing to supersede"). Init finding a supersede record but no archived sibling: hard rejection naming the inconsistency. `--recompute-base` on an unresolvable merge-base: refused with the existing `cannot compute merge-base` message shape.

**Edge Cases:**
- Two consecutive supersedes of the same EPIC: each produces a distinct epoch-named record; only the one matching the current archived state hash can authorize; older records are inert — covered by a two-cycle supersede→re-init→supersede→re-init bats case.
- Supersede record present but PM re-runs generation producing a DIFFERENT plan.json than recorded: init rejected — the PM re-runs supersede against the current state (deliberate: the record binds one exact transition).
- Evidence dirs from the superseded run: preserved verbatim; the new run allocates a new run_id so nothing collides.

**Dependencies:**
- Depends on: Step 8

**Acceptance Criteria:**
- [ ] All five bats cases pass, including the forged-record rejection.
- [ ] Superseded run's evidence dir is byte-identical after the recovery cycle.
- [ ] `--attest-source-ref --recompute-base` leaves `_pfsm_verify_epic_lineage` passing on a genuinely rebased fixture branch.
- [ ] Enforcement-registry entries exist for both transactions.

**Effort:** L
**AID Role:** backend

**EPIC 3: Steps 14-19 — Review-Equivalent Ancillary Writes**

### Step 14: Ancillary policy file and one shared dirty-path classifier

**Objective:** `defaults/policies/plan-final-policy.yaml` defines `plan_final.ancillary_paths`; a new `lib/aid-ancillary.sh` provides matching, porcelain filtering, and overlap warning; the dirty-exception regex duplicated verbatim at four call sites is replaced by the shared classifier with each caller's current semantics preserved.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/policies/plan-final-policy.yaml` — `plan_final.ancillary_paths` default list: the five existing runtime paths (`.aid-o/config/queue.yaml`, `.aid-o/work/audit-log.jsonl`, `.aid-o/metrics/gate-runtime-baselines.yaml`, `.aid-o/metrics/gate-runtime-baselines.yaml.lock`, `.aid-o/work/plan-state/**`) plus `.aid-o/work/**`, `.aid-o/reports/**`, `.aid-o/metrics/**`; a `schema_version` field; comments stating the precedence rule (protected paths always win) and the explicit absence of any `docs/**` default.
- Create: `plugins/aid-orchestrator/scripts/lib/aid-ancillary.sh` — functions: `aid_ancillary_load <project_root>` (reads project policy `.aid-o/config/policies/plan-final-policy.yaml` when present, else shipped defaults; malformed file → fail closed to the five legacy runtime paths with a stderr warning); `aid_ancillary_match <path>` (glob match against the loaded policy, 0/1); `aid_ancillary_filter_porcelain --mode <legacy5|legacy4|policy>` (stdin porcelain filter; `legacy5` reproduces exactly the current 5-path exception set, `legacy4` the 4-entry variant without `plan-state/`, `policy` the full loaded ancillary policy — the mode argument is MANDATORY so no caller silently inherits a wider set); `aid_ancillary_overlap_warn <protected_paths_file>` (prints each glob/protected-path collision as a warning naming both). The four Step 14 call sites all use `--mode legacy5` (or `legacy4` for `aid-fsm.sh`), which is what makes the byte-identical acceptance test satisfiable; ONLY Step 17 switches the drift detector to `--mode policy`. Both modes are covered by the classifier bats file.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~274-284) — replace both inline `grep -vE '<5-path regex>'` occurrences (the second is at lines ~3059-3075) with `aid_ancillary_filter_porcelain --mode legacy5`; behaviour at these sites stays classification-only and byte-identical — the broader `--mode policy` activates only at the drift detector together with Step 17's wiring.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~594-600) — same replacement with `--mode legacy5`.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~2661-2665) — same replacement with `--mode legacy4` to preserve the 4-entry semantics.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-ancillary-classifier.bats` — glob matching cases (match, non-match); all three filter modes tested (`legacy5` vs `legacy4` differ exactly by `plan-state/`; `policy` widens to the loaded globs; a missing `--mode` argument is a usage error); malformed policy falls back to the five legacy paths with a warning; overlap warning names both sides; the four call sites produce byte-identical filter results to the old inline regexes on a fixture porcelain stream.

**Architecture Context:** Grounding found the identical regex at `aid-plan-fsm.sh:277`, `aid-plan-fsm.sh:3069`, `aid-release.sh:597` and the 4-entry variant at `aid-fsm.sh:2662`, with the codebase's own comment noting the shared shape. Both reviewers agreed the new classifier must become the single source rather than a fifth copy. The path-level precedence rule (protected wins over ancillary glob) replaces the source doc's hard glob-overlap rejection because close-consumed evidence lives under `.aid-o/work/` — a hard rejection would forbid the very defaults the source doc lists (PM decision, brainstorm log item 6).

**Implementation Detail:** Glob matching uses bash `case` patterns compiled from the YAML list (same technique as `gates/scope-check.sh:33-42`). `aid_ancillary_load` caches into a module variable so porcelain filtering is one pass. This step is deliberately behaviour-neutral at the four existing sites: they keep filtering exactly the five legacy paths until Step 17 flips drift/preflight to the full policy — allowing this step to merge green without touching plan-final semantics.

**Error Handling:** Unreadable/malformed policy YAML never widens the filter: fail closed to the five legacy runtime paths and warn once per process.

**Edge Cases:**
- A project policy that removes even the five runtime paths: honoured for drift/equivalence classification, but the preflight callers always retain the five legacy paths as a floor (removing queue.yaml from the exception would deadlock routine operation).
- Paths with spaces: porcelain `-z` handling is not introduced; the existing callers use newline porcelain, and the filter preserves their exact input/output contract.
- Glob `.aid-o/work/**` matching the evidence dir of the CURRENT run: allowed at classification level; protection of consumed receipts is Step 15's protected-set precedence.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] Fixture porcelain streams filter byte-identically through the shared classifier at all four call sites.
- [ ] Malformed-policy fallback warns and uses exactly the five legacy paths.
- [ ] `bash -c '! grep -n "gate-runtime-baselines" plugins/aid-orchestrator/scripts/aid-plan-fsm.sh plugins/aid-orchestrator/scripts/aid-release.sh plugins/aid-orchestrator/scripts/aid-fsm.sh'` exits 0 — zero inline occurrences remain outside the shared lib (the negated grep enforces the zero, unlike a bare count).

**Effort:** M
**AID Role:** backend

### Step 15: Protected path set stored at freeze

**Objective:** Freezing a candidate additionally computes and stores the protected path set — the union of all steps' `plan.json` `allowed_paths`, the source plan path, the lifecycle manifest path, and the close-consumed receipt paths — in the manifest alongside `candidate_sha`, with the ancillary overlap warning emitted at freeze time.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` (lines ~1205-1260, `plan_manifest_freeze_candidate`) — the atomic freeze write additionally stores `protected_paths` (sorted list) computed by the caller; invariant extension at lines ~467-490: `protected_paths` non-empty exactly when `candidate_sha` is non-null (cleared together by `plan_final_invalidate`).
- Modify: `plugins/aid-orchestrator/defaults/schemas/plan-boundary-manifest.schema.json` — ALL six new manifest fields introduced across this plan (`source_plan_path` from Step 11, `protected_paths` + `protected_paths_complete` from this step, `accepted_head` + `equivalence_receipt_path` + `equivalence_receipt_sha256` from Step 16) are declared here as OPTIONAL fields in one additive schema change, so every schema-validated manifest write keeps passing; a legacy manifest without any of them stays valid; the manifest validator's field checks in `lib/aid-plan-manifest.sh` are extended in the same commit.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~2151-2270, `_pfsm_finalize_freeze`) — before the freeze write: collect `allowed_paths` from every EPIC's plan.json recorded in the manifest (same jq read the pre-commit hook uses on `plan.json`), add the source plan path, the manifest path itself (`.aid-lifecycle/manifests/<plan_id>.yaml`), and the receipt paths (`.aid-lifecycle/receipts/<plan_id>.yaml`); pass the set to `plan_manifest_freeze_candidate`; run `aid_ancillary_overlap_warn` and print its output (warning only). Source-plan-path resolution (the manifest today records only `source_plan_sha`, no path): Step 11's preflight ADDITIONALLY stamps the plan's repo-relative path as a new optional manifest field `source_plan_path` at lifecycle creation; at freeze, a manifest carrying the field uses it, and a legacy manifest without it falls back to the deterministic glob `.aid-o/plans/<plan_id>-*.md` (first match; no match → the source plan contributes nothing to the set and the freeze records `protected_paths_complete: false`, disabling equivalence per this step's Error Handling).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-protected-surface.bats` — freeze on a fixture plan stores the expected sorted set; `plan_final_invalidate` clears it together with the candidate pair; a fixture whose ancillary policy overlaps a protected path emits the named warning at freeze; a manifest with `protected_paths` but null candidate fails validation.

**Architecture Context:** `plan_manifest_freeze_candidate()` is the single sanctioned freeze write with an all-or-nothing invariant (grounding F1), so extending it keeps the pair-write atomicity. The opponent round killed the content digest (blocking finding: acceptance writing `accepted_head` into the manifest would change any digest that covered the manifest; simplification: git SHAs already prove content, so a PATH set plus ancestry is sufficient). `plan.json` `allowed_paths` is the machine-readable delivery contract that already drives the pre-commit scope hook and `gates/scope-check.sh`.

**Implementation Detail:** Path collection normalises to repo-relative form and de-duplicates order-preservingly (reusing `_aid_allowed_paths_from_files_json` output stored in each plan.json — read via `jq -r '.steps[].allowed_paths[]?'` across the plan's EPIC plan.json files recorded in the manifest's `epic_runs[]` evidence dirs, falling back to the union recorded at generation time). Directory-shaped entries keep a trailing `/**` marker so Step 16's disjointness test treats them as prefixes.

**Error Handling:** A plan whose EPIC plan.json files cannot all be located at freeze: freeze proceeds (normal plan-final flow must not break), but the manifest records `protected_paths_complete: false` alongside the partial set and prints `WARNING: protected set incomplete — <epic_id> plan.json unlocatable`; review EQUIVALENCE is then unavailable for this freeze — the Step 16 predicate fails closed on `protected_paths_complete: false` (returns the same code as a legacy freeze), so no acceptance receipt can ever be minted from a partial protected set and behaviour degrades exactly to today's any-movement-invalidates rule. The set is never silently empty (the three lifecycle paths are the floor).

**Edge Cases:**
- Plan with zero declared `allowed_paths` (docs-free bookkeeping plan): protected set = the three lifecycle paths; equivalence still refuses source-plan/manifest edits.
- Re-freeze after invalidation: the set is recomputed fresh (a fix may have changed allowed_paths).
- Manifest older than this schema (no `protected_paths` field): validation treats absence as legacy-valid when candidate is also from a pre-P073 freeze; Step 17 then behaves exactly as today for that plan (no equivalence available).

**Dependencies:**
- Depends on: Step 14

**Acceptance Criteria:**
- [ ] Freeze stores the expected sorted protected set on the fixture plan.
- [ ] Invalidate clears candidate and protected set together; the half-cleared state is rejected by manifest validation.
- [ ] Overlap fixture emits the named warning listing glob and protected path.

**Effort:** M
**AID Role:** backend

### Step 16: Read-only equivalence checker and controller-only acceptance receipt

**Objective:** `plan_final_review_equivalent()` is a side-effect-free predicate (ancestry + all-changed-ancillary + protected-set disjointness), and `plan-finalize --stage accept-ancillary` is the controller-only acceptance operation that writes one JSON receipt and records `accepted_head` in the manifest while `candidate_sha` never moves.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (new functions near the drift detector, lines ~3040-3100) — `plan_final_review_equivalent <root> <plan_id>`: returns 0 only when (1) `git merge-base --is-ancestor <candidate> <plan_head>`, (2) every path in `git diff --name-only <candidate>..<plan_head>` passes `aid_ancillary_match`, (3) no changed path matches the stored `protected_paths` (prefix-aware), and (4) the worktree carries no tracked dirt outside the ancillary policy; prints the changed-path classification on failure. No writes.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (stage dispatcher, lines ~4180-4235) — new stage `accept-ancillary`: requires an existing frozen candidate and a passing `plan_final_review_equivalent`; writes the receipt `<plan_final_evidence_dir>/review-equivalence-receipt.json` with `{schema_version, plan_id, run_id, candidate_sha, prior_accepted_head, accepted_head, changed_paths[], ancillary_policy_sha256, protected_paths_count, operator, created_at}` (mktemp+mv atomic); records `accepted_head` in the manifest via a new sanctioned mutator `plan_manifest_set_accepted_head` (lib/aid-plan-manifest.sh); refuses when equivalence fails, naming every offending path.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` (new mutator + invariant) — `accepted_head` may only be non-null when `candidate_sha` is non-null and must be a descendant (validated at write); cleared by `plan_final_invalidate` together with the pair.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (plan-final region, lines ~1270-1330) — document the stage: agents never invoke it; the controller runs it after a deliberate ancillary commit; a receipt can never waive a protected-surface change and never substitutes a normal fix.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-equivalence.bats` — ancillary-only commit → predicate passes, acceptance writes receipt + `accepted_head`; source-file commit → predicate fails naming the path, acceptance refuses; mixed commit (ancillary + protected) → fails; non-ancestor head (force-pushed branch) → fails; second ancillary commit after acceptance → a second acceptance updates `accepted_head` and appends a second receipt file suffixed `-2`.

**Architecture Context:** The opponent round's blocking finding 4 required splitting the read check from the write acceptance — drift consumers need a pure predicate, while minting receipts is a deliberate controller act. Honest enforcement classification per AID-v3 §1: controller-only invocation is an INSTRUCTION-ONLY rule (agents have Bash and no actor-identity guard exists in either FSM script); the mechanical guarantees are the effect bounds — the predicate cannot pass a protected-surface change, the receipt durably records the invocation (operator, timestamp, paths), and merge re-verifies live — so a rogue acceptance is detectable and cannot widen what review equivalence permits. One JSON receipt plus the manifest field replaces the three-mechanism design (opponent simplification); merge-time safety comes from live re-verification in Step 18, which also neutralises the stale-policy-receipt concern.

**Implementation Detail:** The disjointness test uses the SAME matching semantics as the existing `allowed_paths` consumer `gates/scope-check.sh:33-42` — each protected entry is evaluated as a bash `case` glob pattern against the changed path, plus the directory-prefix rule the pre-commit hook uses (`path == entry || path == entry/*`); one shared matcher function in `lib/aid-ancillary.sh` implements it so protected-set matching and scope checking can never diverge on the same entry. `ancillary_policy_sha256` hashes the loaded policy file bytes for audit provenance (not for validity — Step 18 re-verifies live). The receipt writer follows the waiver atomic-write pattern (`aid-gate-waiver.sh:187-189`). `accepted_head` in the manifest is what merge consults; the receipt is the audit trail binding the decision.

**Error Handling:** Acceptance with no frozen candidate: `PRECONDITION FAIL: nothing is frozen — accept-ancillary is meaningful only between freeze and merge`. Receipt write failure: acceptance fails closed, manifest untouched (mutator runs only after the receipt file exists).

**Edge Cases:**
- Ancillary commit that touches a path both gitignored and tracked in a consumer repo variant: classification runs on git's own diff output, so only genuinely tracked paths are ever evaluated.
- Equivalence invoked when `accepted_head` already equals plan head: predicate passes trivially; acceptance is idempotent (no duplicate receipt for a no-op).
- Receipt authority across repeated acceptances: each acceptance writes the receipt path AND its sha256 into the manifest alongside `accepted_head` (fields `equivalence_receipt_path`/`equivalence_receipt_sha256`, updated atomically by the same mutator) — the manifest binding, never a directory listing, names the authoritative receipt; superseded `-N` suffixed receipts remain as audit history only.
- A plan frozen before Step 15 (no protected set) OR frozen with `protected_paths_complete: false` (partial set, Step 15 Error Handling): predicate returns 2 (`equivalence unavailable`), and callers treat it exactly like today's invalidation path — a partial protected set can never mint an acceptance receipt.

**Dependencies:**
- Depends on: Step 15

**Acceptance Criteria:**
- [ ] All six bats cases pass, including the legacy-freeze unavailability code.
- [ ] The predicate performs zero writes (verified by running it under a read-only bind mount fixture or by asserting no new files and unchanged manifest mtime semantics).
- [ ] `candidate_sha` is byte-identical before and after a successful acceptance; only `accepted_head` changes.

**Effort:** L
**AID Role:** backend

### Step 17: Wire equivalence into candidate drift, review, and C4

**Objective:** `_pfsm_review_candidate_drift()` stops invalidating on ancillary-only dirt or an accepted equivalent head: tracked dirty paths are filtered through the full ancillary policy, and a moved head is tolerated exactly when it equals the manifest's `accepted_head` recorded by a valid acceptance — every other movement still invalidates as today.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~3059-3075, `_pfsm_review_candidate_drift`) — head branch: `plan_head == candidate` passes (unchanged); `plan_head == accepted_head` (non-null, from the manifest) passes with a stderr note `review preserved via review-equivalence receipt <path>`; anything else invalidates (unchanged). Dirty branch: the porcelain filter switches from the five legacy paths to the loaded ancillary policy; a dirty PROTECTED path always invalidates regardless of policy (precedence rule).
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (review pre/post at lines ~3390 and ~3825, c4 at ~3957) — no logic change needed beyond the detector (they all call it); update their invalidation messages to mention `accept-ancillary` as the recovery when the failed classification was ancillary-shaped: `an ancillary-only commit can preserve this review: run plan-finalize <plan> --stage accept-ancillary`.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (C4 dual-run region, lines ~4019-4048) — the dual-run decision record gains `accepted_head` and `review_equivalence: true|false` fields so the PM surface shows when equivalence was used.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-drift-equivalence.bats` — ancillary dirty file during review → drift passes; protected dirty file → invalidates; head at accepted_head → review and c4 stages proceed and the C4 record carries `review_equivalence: true`; head moved WITHOUT acceptance → invalidates with the accept-ancillary hint; legacy-freeze plan → behaviour byte-identical to pre-P073 (five-path filter, any movement invalidates).

**Architecture Context:** The detector is the single choke point the review pre/post and c4 stages all call (grounding F3), so wiring it once covers those three consumers automatically. The invalidation-message hint is the loosening UX: the operator learns the recovery at the exact moment of the failure instead of losing the review first.

**Implementation Detail:** `accepted_head` is read from the manifest (never from the receipt — the receipt is audit, the manifest is state); a non-null `accepted_head` that is NOT an ancestor-descendant of the candidate fails manifest validation upstream (Step 16 invariant), so the detector may trust it. The stage-gating exemption list at lines ~4215-4231 gains `accept-ancillary` alongside review/c4/summary (a dirty tree is its input, not a refusal condition).

**Error Handling:** Policy load failure inside the detector: fail closed to the five legacy paths (Step 14 contract) — equivalence via `accepted_head` still works because it depends on the manifest, not the policy.

**Edge Cases:**
- Dirt appears BETWEEN acceptance and the review stage re-check: filtered by the same policy; ancillary dirt passes, protected dirt invalidates — no ordering hazard.
- `accepted_head` set but the branch then moves one commit further (unaccepted): invalidates (only the exact accepted head is tolerated) with the hint to re-run acceptance.
- summary stage: consumes the same detector via its callers; no separate change.

**Dependencies:**
- Depends on: Step 16

**Acceptance Criteria:**
- [ ] All five bats scenarios pass, including byte-identical legacy behaviour.
- [ ] The C4 decision record schema carries the two new fields and existing consumers ignore them (additive).
- [ ] Invalidation messages contain the accept-ancillary recovery hint only for ancillary-shaped failures.

**Effort:** M
**AID Role:** backend

### Step 18: Wire equivalence into plan-merge-to-main with live re-verification

**Objective:** `plan-merge-to-main` merges the accepted equivalent head — the PM decision stays bound to the frozen candidate, the plan head must equal either the candidate (unchanged path) or the manifest's `accepted_head`, and in the latter case the merge re-verifies equivalence live (ancestry, changed-path classification against the CURRENT policy, protected disjointness) before proceeding; provenance retains the frozen candidate everywhere.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~4570-4640, `cmd_plan_merge_to_main`) — the three-way identity check at line ~4576 becomes: `d_cand == candidate` (PM decision binds the frozen candidate, unchanged, hard); `plan_head == candidate` OR (`plan_head == accepted_head` AND `plan_final_review_equivalent` re-run passes AND the AUTHORITATIVE receipt — resolved via the manifest's `equivalence_receipt_path`, its bytes matching `equivalence_receipt_sha256` — parses with matching `candidate_sha`/`accepted_head`); on the equivalence path the merge message and the close-evidence receipt record both SHAs (`candidate_sha`, `merged_head`) plus `review_equivalence: true`; any re-verification failure refuses with the classification output (no invalidation — merge is read-only until its git action).
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (close-evidence builder, lines ~3301-3330) — `plan_final_close_evidence_receipt` gains `merged_head` and `review_equivalence` fields; `merge_commit` parentage naturally reflects the accepted head; the close-receipt grammar validator `_pfsm_validate_plan_final_close_receipt_json` (lines ~3266-3300, exact-key-set contract) is extended IN THE SAME COMMIT to accept the two new keys, and the durable-receipt read-back verifier is updated with it.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-close-check.sh` (report freshness/receipt consumption region) — every place that parses or validates the close-evidence receipt's key set accepts the two new fields; a legacy receipt without them still validates (additive schema, no version bump needed beyond a schema_version comment).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-merge-equivalence.bats` — additional fixtures: an equivalence-path close receipt passes both the grammar validator and `aid-plan-close-check.sh`; a legacy-shaped receipt (no new fields) still passes both.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-merge-equivalence.bats` — the full integration path: freeze → review outputs bound to candidate → ancillary commit → accept-ancillary → merge succeeds carrying both SHAs; a protected commit after acceptance → merge refuses at re-verification; a receipt whose `accepted_head` mismatches the manifest → refuses; decision SHA naming anything but the frozen candidate → refuses (unchanged hard binding); op-key remains keyed on the candidate (idempotence preserved).

**Architecture Context:** Grounding F4 mapped every binding in the merge path; the opponent's blocking finding 2 demanded the identity contract be reconciled explicitly rather than "accept accepted_head at one comparison". The resolution: the decision-SHA leg is untouched (the PM authorized the frozen candidate's review — equivalence explicitly means that review still describes the delivery surface), the plan-head leg gains exactly one alternative, and live re-verification at merge closes both the stale-receipt and the post-acceptance-commit windows. This is the integration test the whole EPIC hangs on (drift→accept→merge, per the opponent's testing simplification).

**Implementation Detail:** Re-verification reuses the Step 16 predicate verbatim (same code path, no merge-local variant). The `stale_authorization` re-check against the target branch (line ~4635) is unchanged — target movement still invalidates to PLAN_SYNC. The op-key stays `plan_op_key ... "$candidate"` so a retried merge after transient failure remains idempotent regardless of which head was merged.

**Error Handling:** Receipt unreadable/missing while `accepted_head` is set: refuse with `PRECONDITION FAIL: accepted_head is recorded but its receipt is missing — rerun plan-finalize --stage accept-ancillary`; never merge on manifest state alone.

**Edge Cases:**
- Ancillary commit lands AFTER acceptance but before merge: re-verification sees head != accepted_head → refuse with the hint to re-accept (the fresh acceptance updates the manifest and a second receipt).
- Equivalence policy tightened between acceptance and merge: live re-verification applies the CURRENT policy — a previously-ancillary path now unclassified refuses the merge (deliberate: policy is authoritative at the moment of irreversible action).
- Legacy plan without `accepted_head`: the original three-way identity check applies byte-identically.

**Dependencies:**
- Depends on: Step 17

**Acceptance Criteria:**
- [ ] The five integration/refusal bats cases pass.
- [ ] A merged equivalence-path plan's close-evidence receipt carries `candidate_sha`, `merged_head`, `review_equivalence: true`.
- [ ] Decision-SHA binding to the frozen candidate is provably unchanged (existing merge tests still pass unmodified).

**Effort:** M
**AID Role:** backend

### Step 19: Regression suite, enforcement registry, and documentation closure

**Objective:** The cross-cutting regression fixture proves one ancillary commit travels drift→accept→merge without a second review while one protected change fails at each of those consumers; every new enforcement is registered; contributor docs and both CHANGELOGs describe the three EPICs; the source planning document is annotated with this plan's ID.

**Files:**
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-p073-integration.bats` — end-to-end fixture repo: EPIC 1 behaviours (budget 5 visible in a ledger init; release fixtures), EPIC 2 behaviours (one forced command with full receipt chain; committed-source refusal; Reporter round without candidate movement), EPIC 3 full path (ancillary commit through drift, acceptance, merge; protected commit refused at drift AND at merge; exact-only consumers — pre-commit scope guard and release-prep staging — demonstrably unchanged on the same fixture).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — entries for: changelog-entry validation (Step 3), dependency-token hard fail (Step 5), branch-restore hard stop (Step 6), plan-level force framework + per-command forceable classification (Steps 7-8), init strict-flag rejection + release-force reason gate (Step 9), single-use C3 override claim + grant producer (Step 10), ancillary classifier + equivalence acceptance + merge re-verification (Steps 14-18); Steps 11 and 13 self-register in their own Files lists — this step VERIFIES their entries exist rather than re-adding them; each entry with type/source/instruction/severity/surface per AID-v3-principles §1.
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — identical entries for the three EPICs under the release the plan-final boundary assigns (Added: PM force backdoor, pm-override grant, accept-ancillary stage, supersede recovery; Changed: budgets to 5 sessions, step rendering, dependency grammar; Fixed: release-script silent aborts, placeholder release entries, Reporter contradiction, branch-restore continuation).
- Modify: `docs/extending-aid.md` (contributor reference) — sections describing the force framework contract (forceable vs hard), the PM-override artifact schema, and the ancillary/equivalence model with the consumer table (equivalence: drift/review/C4/merge; exact-only: scope guards, waivers, release prep, `--at-head`, CP3, C3, close-check).
- Modify: `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md` (section headers of §10, §12, §13 and the §11 grounding items 3-4) — annotate `> **Plan written: P073 (EPIC 1|2|3)** — implementation tracked in .aid-o/plans/P073-loosening-force-ancillary.md` at each covered section; uncovered portions (§11 D8/D9 trailer+hook design, §13 D15) explicitly noted as remaining.
- Test: `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` — confirm the modified skills/commands still lint clean (run, not modify, unless a touched file needs a `Last Updated` bump, which each modified skill receives).

**Architecture Context:** CLAUDE.md mandates the enforcement registry for every new detection capability at design time, identical CHANGELOGs, `Last Updated` bumps on modified skills, and the version-file registry during release (handled by the plan-final Release Sub-Phase under `plan_branch` mode — no per-EPIC release). The integration fixture is the EPIC 3 implementation gate: consumers not exercised by it remain exact-only by default.

**Implementation Detail:** The fixture repo is built by a bats `setup_file` that initializes a disposable git repo with a two-step plan, runs generation, drives the plan-final stages with stub review outputs (the same stubbing approach the existing plan-final bats suites use), and layers the EPIC 1/2 assertions on the same repo where possible to keep runtime bounded. Registry entries follow the existing YAML shape in the file (key, type, source, instruction, severity, surface).

**Error Handling:** Any integration assertion failure names the consumer and the fixture commit it was driving, so a regression bisects to one wiring step.

**Edge Cases:**
- Suite runtime: new suites enter the P069 test catalog through its EXISTING sanctioned flow, which this step schedules explicitly — run the catalog proposal refresh and approve the new suites via `plugins/aid-orchestrator/scripts/aid-test-catalog-approve.sh` (writing the consumer `.aid-o/config/test-catalog.yaml` through its own approval mechanism, never by hand-editing), and record measured runtimes via the existing baseline tooling (`aid-gate-runtime-baseline.sh` measurement path) so `bats_all` headroom stays honest; the integration suite's Error Handling covers the yq/codex-absent skip so a baseline is never fabricated.
- The source-doc annotation must not break its own §-numbering: blockquote lines only, no header edits.
- CI environment without `yq` or `codex` available: the integration fixture stubs the Codex-dependent stages (same stubbing approach as the existing plan-final suites) and skips with a named reason when `yq` is genuinely absent, so the suite never reports a false PASS.

**Dependencies:**
- Depends on: Step 18

**Acceptance Criteria:**
- [ ] `test-p073-integration.bats` passes end-to-end on a clean checkout.
- [ ] Every Step 3/5/6/7/8/9/10/11/13/14-18 enforcement has a registry entry (spot-checked by grep for the new keys).
- [ ] Both CHANGELOGs are byte-identical for the new entries; modified skills carry a 2026 `Last Updated` bump.
- [ ] The source doc carries the three P073 annotations and names what remains uncovered.

**Effort:** L
**AID Role:** qa

## Testing Strategy

Every step lands with its own bats coverage in `plugins/aid-orchestrator/scripts/tests/bats/` (the new suite files named in the step Files entries plus edits to existing suites), and Step 19 adds the cross-cutting integration fixture. Convention note: a `Test:` Files entry naming a bats file that does not yet exist in the repository IS the instruction to CREATE that file in that step (the repository-wide Files grammar uses the `Test:` verb for new and existing test files alike; all eighteen new suite files enumerated across Steps 1-19 are created by their owning steps and auto-discovered by `scripts/tests/run-all-tests.sh`). Test tiers: unit-level function tests (classifier matching, force helper records, equivalence predicate), command-level fixture tests (refusals, forced paths, recovery transactions — each builds a disposable git fixture repo in `$BATS_TEST_TMPDIR`), and one end-to-end integration file proving the EPIC 3 consumer matrix plus the exact-only consumers' unchanged behaviour. Existing suites guard regressions: `test-cp1-ledger.bats` (budget), the plan-final and merge suites (drift/identity), and `test-skill-lint.sh` over every modified skill/command. Runtime discipline per the repository quarantine policy: no full-suite requirement per step; the integration file registers a measured runtime baseline for the P069 scheduler. Target: every new enforcement point has at least one failing-path test and one passing-path test; every loosening has a test proving the previously-blocked flow now completes.

## Constraints

- Implementation starts from a clean post-P072 base on `main`; P072 merges first (its own sequencing note), and the three uncommitted P072 files on the current branch are never touched by this plan.
- P069's scheduler and test-catalog contract are untouched; the only contact point is registering new suites with runtime baselines.
- All plugin code and documentation in English; conversation with the PM in Czech.
- CHANGELOG discipline per CLAUDE.md: root and plugin CHANGELOGs identical; version bumps only through the plan-final release boundary (`plan_branch` mode — no per-EPIC releases).
- Every new detection capability is registered in `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` with its enforcement mechanism named at design time (AID-v3-principles §1).
- The loosening directive is binding: no step may add a new blocking PROCESS GATE beyond the three the PM explicitly sanctioned (changelog-entry validation, committed-source preflight, branch-restore hard stop), and each of those prints its exact recovery action. Error-surface corrections are NOT process gates and are expressly permitted: replacing a silent wrong result with a loud refusal (Step 5 dependency-token abort, Step 9 init unknown-flag rejection) and the internal validity checks of the sanctioned force/override/recovery mechanisms themselves (Step 10 artifact validation, Step 13 supersede binding) — these convert existing silent failure modes into named errors, which is the loosening directive's own spirit.
- Machine compatibility surfaces are frozen: `fsm-state.yaml` fields, `get-state` JSON, evidence filenames, and the 0-based `current_step` value itself.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Equivalence wiring regresses plan-final invalidation (a protected change slips through) | Medium | High | Path-level protected precedence; live re-verification at merge; integration fixture drives a protected change through every wired consumer and asserts refusal |
| Widening the dirty filter to `.aid-o/work/**` hides a meaningful tracked change in consumer repos | Medium | Medium | Protected set always wins; preflight floor keeps the five legacy paths; no `docs/**` default; PM decision log records the broad-vs-narrow tradeoff for revisit |
| Force on merge/close corrupts lifecycle invariants | Low | High | Forced paths route through the sanctioned manifest mutators only; `hard` classification protects physical git impossibilities; receipt-write failure fails the force closed |
| CP1 ledger migration (max 3→5) breaks in-flight plans | Low | Medium | One-shot migration branch with `migrated_from: 3`; tamper rejection retained for any other mismatch; bats cover both |
| Behaviour drift while replacing the four inline dirty regexes | Low | Medium | Step 14 is behaviour-neutral by contract (byte-identical filter tests); policy activation deferred to Step 17 |
| Init strict-flag rejection (Step 9) breaks an undocumented caller | Low | Low | Caller sweep of commands/skills during implementation; loud failure is the desired surfacing mechanism |
| Plan size causes EPIC-boundary integration gaps | Medium | Medium | Steps ordered with explicit dependencies; Step 19 integration fixture spans all three EPICs; chain queue mode at generation |

## Success Criteria

- A high-risk plan and a C3 review each get 5 genuinely dispatched Codex sessions before PM escalation, verified by ledger and loop-state fixtures.
- A PM can complete every lifecycle operation on a deliberately corrupted fixture using `--force --reason`, with three audit records and a visible `forced_override` marker in the terminal artifacts — and cannot do so silently or without a reason.
- The P083 fixture (uncommitted plan) fails before any branch or manifest exists; the P082 fixture (Reporter round) completes one review cycle with zero candidate movement.
- An ancillary commit after freeze reaches merge without a second review; a protected-surface commit is refused at drift and at merge on the same fixture.
- No regression in the exact-only consumers: pre-commit scope, waivers, release-prep staging, `--at-head` behave byte-identically on the integration fixture.
- All new suites green in CI; `test-skill-lint.sh` clean over modified files; enforcement registry complete.

## Acceptance Criteria

- [ ] AC1: Both shipped policy defaults declare 4 rechecks.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/defaults/policies/review-checkpoints.yaml
  regex: "max_rechecks: 4"
```
- [ ] AC2: The CP1 ledger budget constant is 5.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/lib/aid-cp1-ledger.sh
  regex: "MAX_ATTEMPTS=5"
```
- [ ] AC3: plan-close accepts an audited force flag.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/aid-plan-fsm.sh
  regex: "_pfsm_handle_force"
```
- [ ] AC4: The deprecated C3 environment variable is referenced only inside the conversion function (no direct gate read anywhere else).
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -c 'f=plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh; total=$(grep -c AID_C3_FORCE_BEYOND_ESCALATION \"$f\" || true); infn=$(awk \"/^_c3_convert_env_override\\\\(\\\\)/,/^}/\" \"$f\" | grep -c AID_C3_FORCE_BEYOND_ESCALATION || true); test \"$total\" -gt 0 && test \"$total\" -eq \"$infn\"'"
  expected_exit: 0
```
- [ ] AC5: The shared ancillary classifier exists and is executable.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -n plugins/aid-orchestrator/scripts/lib/aid-ancillary.sh"
  expected_exit: 0
```
- [ ] AC6: The equivalence acceptance stage is dispatchable.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/aid-plan-fsm.sh
  regex: "accept-ancillary"
```
- [ ] AC7: The Reporter contract no longer orders a commit of the gitignored reports path.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -c '! grep -n \"boundary.md.*It must be committed\" plugins/aid-orchestrator/agents/reporter.md'"
  expected_exit: 0
```
- [ ] AC8: The P073 integration suite exists.
```yaml
verification_pattern:
  type: cmd
  cmd: "test -f plugins/aid-orchestrator/scripts/tests/bats/test-p073-integration.bats"
  expected_exit: 0
```

## Next Steps

- All eight design decision points were reviewed and CONFIRMED by the PM on 2026-08-04 (decision record: `.aid-o/work/interim-P073.md`, Reconciliation section — budget of 5 sessions explicitly confirmed from live experience; no recommendation was overruled). Like any plan, this document remains revisable through the normal review mechanisms; the note above records only that no PM decision is currently pending.
- `/aid-plan epic .aid-o/plans/P073-loosening-force-ancillary.md` — EPIC generation (chain queue mode: EPIC 1 → 2 → 3); the plan is high-risk, so CP1-deep plus the C0 cross-provider review loop gate generation.
- Implementation begins only from a clean post-P072 `main` base per the Constraints section.
