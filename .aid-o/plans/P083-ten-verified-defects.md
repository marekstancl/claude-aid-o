---
id: P083
type: plan
status: draft
created: 2026-08-11
author: PM + AI
risk: high
---

# Plan: The Defects That Survived a Live-Code Sieve

## Stakeholder Brief

Forty-six open backlog entries were re-verified against the tree on 2026-08-11, one at a time, with file:line evidence for every verdict. Eleven turned out to be already fixed, moot or deliberate decisions. Thirty-three were real, but most were smaller than their descriptions and seven named the wrong file entirely. The PM then applied a second sieve by hand: keep only what repairs the pipeline we actually run today, only where the benefit is demonstrable, and prefer removing machinery to adding it. Ten items survived, and all three of their open questions were then decided by measurement before this plan was finalised. Four break something on the path we use every day — a gates report written where nobody reads it, acceptance criteria cut mid-sentence, a release rollback that strands one file, a README tagline whose configured pattern cannot match the line it is aimed at. Three are guards that report success while checking nothing, including one that fails open in production library code. Two are deletions of machinery that outlived its purpose. The tenth — retiring the test-portfolio audit, which the PM chose to delete outright — turned out to be entangled with a live merge-path selector and is therefore its own removal plan rather than a step here; this plan records the decision. Nothing here adds a new detector, a new event or a new ceremony.

## Context

Source: `.aid-o/work/evidence/backlog-verify-2026-08-11/block-{1..7}.md` — seven independent verifications of `docs/plans/2026-06-29-BACKLOG.md` against `main` at v2.83.1, each required to open the code first-hand and forbidden to accept an entry's paraphrase.

That method was chosen because the previous approach failed publicly. Plan P082 was written from the backlog's own descriptions of the surviving entries; its CP1-deep review returned **fail with 15 accepted blockers**, seven of twelve steps grounded against code that does not exist, is not the runtime path, or reverses a documented deliberate decision. P082 is superseded by this plan and must not be generated. Its review evidence stays at `.aid-o/work/evidence/P082/` as the record of why this plan is written differently.

Three verification results deserve recording because they changed what is worth doing:

- The `gate_profiles` entry named `defaults/execution.yaml`, which has **no runtime reader at all**. The real defect is one function away and has a different shape: `render_gate_profiles_block` emits two of five canonical profiles and never `release`, while shipped policy sets `plan_final_profile_floor: release`. A consumer therefore flips to `plan_branch` and then hard-fails at `plan-finalize`.
- IMP-491 was reproduced end to end in a throwaway clone, and the reproduction surfaced the fact nobody had written down: `.aid-o/config/project.yaml` is gitignored, so **every worktree and clone takes the buggy fallback path** — which is the live plan-final release path, not a hypothetical one.
- The `grep -oP` portability guard sees 4 of 13 live PCRE call sites. One of the nine it cannot see is `lib/aid-review-signals.sh:24-25`, production library code whose `if` collapses to "enabled" when PCRE is unavailable — a config-honouring toggle that silently ignores `enabled: false`.

## Goal

The nine verified defects this plan owns are fixed or consciously deleted, each with a regression that pins the specific behaviour the verification observed; the tenth's decision is recorded; and the backlog reflects the verification's verdicts.

## Scope

**In scope:**
- Four live-path repairs: the streamlined integration-review gates-report path; the EPIC generator's acceptance-criteria line filter; the release rollback's incomplete file bookkeeping; the README tagline pattern that cannot match its own target line.
- Three guards that pass without checking: the self-host `plan_diff` gate with no `command`; the fail-open PCRE toggle read in `aid-review-signals.sh`; the consumer profile table that cannot satisfy its own policy floor.
- Two decided deletions: the dead parallel-concurrency vocabulary in the gate-runtime baseline, and the C0 prompt's requirement for a dependency graph that has never once reached the review it feeds.
- Backlog reconciliation for exactly these ten entries plus the eleven the verification closed.

**Out of scope:**
- The 22 verified-real entries the PM's sieve rejected. They stay in the backlog with their verification verdict recorded, so a later reader sees "verified real, deliberately not scheduled" rather than "unexamined".
- IMP-261 (model/effort configuration), IMP-490 (legal force past a dead stage), IMP-471 (standing whole-plan auto-GO), OBS-20260702-07 (generation supersede cleanup), IMP-487 (visual-companion service migration) — each is its own plan.
- IMP-495 (rendered decision card) — P080 EPIC 3 already covers the substance; only the refusal-without-options half would be new, and it is pointless before P080 lands.
- Widening the `grep -oP` detector itself. Step 6 fixes the one production call site that fails open. Making the guard see all 13 sites adds machinery the PM's sieve rejected; it stays in the backlog with the count recorded.
- Anything in `commands/aid-init.md`, `skills/` help surfaces or `defaults/templates/` — P080 is live in `.aid-worktrees/plan-P080` and owns those files.

## Approach

Chosen: **ten independent fixes, each pinned by a regression that reproduces the verification's own observation**, grouped so that each EPIC is separately releasable. The grouping is by who is hurt and how loudly: first the four that break a run we do today, then the three that report success while verifying nothing, then the three decisions.

Alternatives rejected: (a) one "guard hardening" refactor — the verification shows these fail for unrelated reasons (a flat path constant, a line-filter regex, missing array bookkeeping, a missing config key); coupling them would couple ten independent risks; (b) scheduling all 33 verified-real items — the PM's sieve exists precisely because most of them do not repair anything we run; (c) fixing the guards by widening their detectors — that adds machinery, and the sieve's stated rule is to prefer removal.

**Every step's Files list names a line range the verification opened.** Where a step's premise came from a review rather than from a first-hand read, the step says so and its first task is to re-confirm.

## Architecture

Three groups.

1. **The live path (Steps 1-4).** `fsm_check_streamlined_integration_review` reads a flat `gates_report.json` while every writer and every other reader uses the `gates/` subdirectory, so a correct streamlined run is pushed toward a force waiver. `aid-plan-to-epic.sh` filters acceptance criteria to flush-left bullet lines in two copy-pasted awk blocks, so continuation lines vanish from both the human EPIC and the machine-read `ac[]`. `_release_update_files`' fallback path omits three files from `UPDATED[]`, and `_release_rollback_updated` restores only what that array holds. And the README tagline's configured pattern escapes literal parentheses as BRE groups, so it can never match the line it is aimed at — the line itself was repaired by hand at the v2.84.0 release, but the mechanism that froze it is untouched.
2. **Guards that pass without checking (Steps 5-7).** A gate with no `command` records `skip/no_command` and never touches `overall`; `plan_diff` sits in five profiles in exactly that state. A `grep -qP` inside an `if` returns "enabled" on any grep without PCRE. A profile table that omits `release` cannot satisfy a policy floor of `release`.
3. **Decided by measurement (Steps 8-10).** Each carried an open question answered before generation rather than handed to the implementer: the dead parallel vocabulary is deleted outright; the C0 prompt stops requiring a dependency graph the review never receives (producing it early was measured, then rejected on review because it would have made C0 a second writer of a producer-integrity seal); and the backlog is reconciled with the verification's verdicts. The catalog-status question was answered too — retire the audit — but measuring its blast radius moved it out of this plan (see Deferred).

## Implementation Steps

**EPIC 1: Steps 1-4 — What breaks on the path we run today**

### Step 1: The streamlined integration review reads the gates report where gates write it

**Objective:** A streamlined-mode EPIC that passed its gates advances from review to release without a force waiver.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~1817-1845) — `fsm_check_streamlined_integration_review` reads `${evidence_dir}/gates/gates_report.json`, the path every writer and every other reader already uses, and accepts the flat sibling only as an explicitly-logged legacy fallback so an in-flight run started before this change still advances.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-streamlined-integration-review.bats` — a streamlined run whose report sits at the canonical path passes the precondition; one with no report at either location still fails with the existing named message; a report at the legacy flat path passes and logs that it took the fallback (tier: t1).

**Architecture Context:** Group 1. The one outlier against seven agreeing readers and one writer default, verified at `aid-run-gates.sh:1628-1629` (writer), `aid-fsm.sh:2453,2880,2991,3286,5262` plus `aid-diagnostic.sh:57` and `aid-compliance-backfill.sh:103` (readers), and `commands/aid-run.md:211` / `skills/pipeline.md:1115,1135` (documentation).

**Implementation Detail:** The precondition is called from `cmd_done_advance` at `aid-fsm.sh:6608` when `streamlined_mode: true`. The failure message at `:1834-1836` names the evidence directory, which is why the mismatch reads as "no report" rather than "wrong path" — the message must name the path it actually looked at, in both branches.

**Error Handling:** A report present at both paths uses the canonical one and logs the duplicate; it never silently prefers the stale copy.

**Edge Cases:**
- Report at the flat path only (an in-flight run) — accepted, with the fallback recorded in the log line, not silently.
- Report present but unparseable — the existing invalid-JSON behaviour is unchanged; this step moves a path, not a parser.
- Non-streamlined runs — untouched; the precondition is not reached.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] A streamlined run whose gates wrote to `<evidence>/gates/gates_report.json` advances `done-advance review release` without `--force`.
- [ ] A run with no report at either path still fails, and the failure message names both paths searched.
- [ ] The legacy flat path is accepted and its use appears in the run log.

**Effort:** S
**AID Role:** backend

### Step 2: Acceptance criteria keep their continuation lines

**Objective:** A multi-line acceptance criterion reaches the EPIC and the machine-read `ac[]` whole.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (lines ~909-949) — the two copy-pasted awk blocks (`step_ac` at :909-925 feeding the flattened section, `step_ac_raw` at :936-949 feeding the per-step `ac[]`) are replaced by calls to one shared extractor, so a fix cannot land in one copy and leave the other divergent.
- Create: `plugins/aid-orchestrator/scripts/lib/aid-ac-extract.sh` — the shared extractor: a criterion begins at a flush-left `- ` bullet and continues through indented lines until the next flush-left bullet or the section terminator; continuation lines are joined with a single space.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-scoping.sh` — one comment at `_aid_extract_files_bullets` saying it handles Files bullets ONLY and pointing at the new extractor. Listed here because the C0 review caught the instruction without the file: this repository derives each step's allowed paths from its Files list, so an edit prescribed in prose but absent from the list is out of scope and the implementer could not legally make it.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-ac-extraction.bats` — the P068 Step 2 criterion the verification reproduced comes out whole in both the prefixed and unprefixed forms; a single-line criterion is byte-identical to today's output; a criterion followed by a `**`-prefixed terminator stops there; the two call sites produce the same criterion set (tier: t1).

**Architecture Context:** Group 1. Verified by running the `:909-925` block verbatim against the entry's own example: output ends mid-sentence at "has a matching", and the three continuation lines carrying the binding rule vanish. The same truncated text lands in `ac[]`, so C3's AC lenses verify against a criterion that no longer states its own requirement.

**Implementation Detail:** The cause is a line filter (`if (in_ac && $0 ~ /^-[[:space:]]/)`), not a truncation: indented lines match neither the emit test nor the `^\*\*` terminator. The backlog entry's pointer to `lib/aid-scoping.sh::_aid_extract_*` is wrong — those handle Files bullets — so the step leaves a comment at that spot saying so, because the wrong pointer is what makes the next reader edit the wrong file. That file is now in the Files list above; it was prescribed without being listed until the C0 review caught it.

**Error Handling:** A continuation line that itself looks like a new section heading terminates the criterion rather than being absorbed; the ambiguity is resolved toward under-joining, never toward swallowing the next section.

**Edge Cases:**
- A criterion whose continuation contains a code span with a leading dash — joined, not split (pinned).
- An empty line inside a criterion — terminates it; plans use blank lines between criteria.
- Existing single-line plans — output byte-identical, asserted against the current suites.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] The reproduced P068 criterion emerges whole from both extraction paths.
- [ ] Both call sites produce identical criterion sets for the same plan.
- [ ] Every existing plan-to-epic suite stays green with byte-identical output for single-line criteria.

**Effort:** S
**AID Role:** backend

### Step 3: A rolled-back release leaves no file on the new version

**Objective:** An aborted release restores every file it touched, including the ones the fallback path forgets.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~487-524 and ~645-681, plus the staging loop at ~:1048-1053 and :823) — the `.metadata.version` branch (:651-656, comment `# Don't double-add`), the `.plugins[0].version` branch (:657-662) and the README `Plugin: ` branch (:672-675) record their file in `UPDATED[]`, and the array is de-duplicated (`sort -u`) before the count at :681, before the staging loop, and before `_release_rollback_updated` (:775-791) — `marketplace.json` has two version fields and must appear once, not twice.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-rollback.bats` — a prepare run aborted by a CHANGELOG validation failure leaves `git status --porcelain` empty for every file that was clean beforehand; the printed count equals the number of DISTINCT files the run edited; a file with two version fields is counted and restored once; a file that was already dirty before the run is left alone and named in the output (tier: t1).

**Architecture Context:** Group 1. Reproduced first-hand in a clone: the run printed seven `Updated:` lines and "Updated 4 files total", then rolled back four files, leaving `.claude-plugin/marketplace.json` at 2.83.2 while everything else returned to 2.83.1.

**Implementation Detail:** The verification's most important finding is why this bites in production and not in the main checkout: `_release_update_files` has a config-driven path (:544-598) and a fallback (:599-677); the config path reads `.aid-o/config/project.yaml`, which is gitignored, so **any clone or worktree takes the fallback** — and plan-final releases run inside plan worktrees. The regression must therefore exercise the fallback path explicitly, not the config path.

**Error Handling:** A file that cannot be restored is a loud failure naming the file and the version it is stranded at; a partial rollback that reports success is the exact defect being fixed. The deliberate pre-dirty exclusion at `:785` stays — the rollback must not discard a PM's uncommitted work — but it is now *named in the output* instead of silently skipped, because "rolled back successfully" while a file still carries the new version is the same lie in a smaller costume.

**Edge Cases:**
- A file listed by config and by fallback, or carrying two version fields — recorded and restored once (the `# Don't double-add` intent is preserved, only its bookkeeping corrected).
- A rollback with an empty `UPDATED[]` — prints that nothing needed restoring, exit 0.
- A repo where `project.yaml` IS present — the config path is unaffected and its existing suites stay green.
- **Declared consequence:** with the array corrected, the prepare commit now also stages `marketplace.json`, because the staging loop reads the same array. That changes what the frozen review candidate contains, and is stated rather than discovered. The plugin README's `Plugin: ` branch is included in the correction for symmetry, but the review found it does not fire on the current file shape; the step must report which of the two it actually observed rather than assuming both.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] After an aborted prepare in a checkout without `.aid-o/config/project.yaml`, every file that was clean beforehand is clean again.
- [ ] The printed count equals the number of distinct files the run edited, and every one of them that was not already dirty is restored — including the normal plan-final flow, where `update_changelog`'s pre-written-entry branch (`:487-489`) currently records an edit it did not make (`:518`, `:524`).
- [ ] Existing release suites stay green.

**Effort:** S
**AID Role:** backend

### Step 4: The README tagline pattern can match the line it is aimed at

**Objective:** `README.md`'s tagline stops being frozen at a version nobody released, and cannot silently freeze again.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~571-577) — the `regex` branch reports, by file and by row, a configured pattern that matched nothing, instead of printing `Updated: <file> (regex)` unconditionally. This is the shipped, tracked half: it is why a frozen version line cannot hide again in this project or in any consumer.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-readme.bats` — a configured pattern that matches nothing is reported by name and does not print `Updated`; a bare-parenthesis pattern substitutes across two consecutive releases with the markdown link intact; a backslash-escaped parenthesis pattern is shown to corrupt the line, so the trap is pinned by a tracked fixture rather than remembered (tier: t1).

**Architecture Context — RE-GROUNDED 2026-08-11 evening, and the correction is the point.** The C0 cross-provider review read this plan against the CURRENT head and found the step stale: it claimed `README.md:3` reads v2.69.0, but that line was repaired by hand during the v2.84.0 release the same afternoon and now reads the current version. Eight CP1 lenses could not see it — they reviewed the plan hours BEFORE that release. This is precisely what a second provider reading the live tree is for.

What survives re-grounding, verified at the reviewed head: the CONFIG path's pattern is still wrong. `.aid-o/config/project.yaml:32` escapes the URL parentheses as `\(`/`\)`, and `aid-release.sh:568-576` applies it through `sed -i "s|…|…|g"`, where BRE reads those as group delimiters — so that row still cannot match a line containing literal `(https://…)`. The sibling `(current)` row has no such escape, which is why one line tracks and the other did not. The line is current only because a human fixed it once; the mechanism that will freeze it again is untouched.

**Implementation Detail — the escaping fix goes the OPPOSITE way, and the review caught me prescribing the wrong one.** Revision 1 said to replace `\(` with a bracket expression `[(]`. Two lenses independently reproduced that this **corrupts the file**: `aid-release.sh:573-575` derives `SEARCH` and `REPLACE` from the same `pattern` string, so a bracket expression is written through verbatim into the replacement and the line becomes `[Claude Code][(]https://…[)]` — a destroyed markdown link that then re-freezes, and it survives the first release so only a second one exposes it. The config schema has no search-side-only escape to express. Removing the backslashes works and was reproduced over three consecutive releases with the link intact.

**Scope shrunk after review.** The original step rewrote the fallback updater to discover an anchor and edit by structure. That is dropped: the fallback greps `v$CURRENT` and never matched the stale line either, so rewriting it fixes nothing; and a version-file registry already exists twice in tracked files (`defaults/orchestration.yaml:64-83`, `.aid-o/config/policies/release-policy.yaml:76+`), read by nothing — a fourth declaration of the same fact is precisely the machinery this plan's sieve rejects.

**What this step no longer attempts, and why — the second C0 blocker.** Earlier revisions had this step edit `.aid-o/config/project.yaml` and `README.md:3` directly. Both are removed. `project.yaml` is gitignored and untracked, so that edit cannot ride in an EPIC commit, is absent from every clone and worktree, and no tracked acceptance check could ever prove the real configuration was repaired — a step that states in its own text that it does not reach anywhere is not a step. `README.md:3` was already repaired by hand at the v2.84.0 release, so asking for it again would be work the tree does not need.

**What ships instead is the only part that can:** the no-match report in `aid-release.sh`, which is tracked, reaches every consumer, and makes the whole class visible — a pattern that changes nothing may no longer print `Updated`. The broken pattern in the untracked config, and the deeper fact that the release script reads an untracked file at all, are handed to the deferred item that owns them (see Deferred), where they can be given a reproducible target and completion evidence instead of being smuggled in as an implementation file.

**Error Handling:** A configured pattern that matches nothing is reported per file and per row, by name, and is not printed as `Updated`. (The `Updated N files total` counter lives at `:589`, outside this step's range; correcting the count is Step 3's business, not this step's.) Today `aid-release.sh:576` prints `Updated: $FILE_PATH (regex)` whether or not the `sed` changed a byte, which is how this survived fourteen releases.

**Edge Cases:**
- A pattern that matches more than one line — substitutes all, unchanged behaviour, asserted.
- A README row whose target line is already current — no-match is expected there and must not be reported as a miss.
- A checkout without `project.yaml` (a worktree) — the fallback path runs, unchanged by this step.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] A configured pattern that matches nothing is reported by name and is not printed as `Updated`.
- [ ] A bare-parenthesis pattern substitutes on a fixture line containing literal `(https://…)` and leaves the markdown link byte-intact across two consecutive simulated releases; the backslash-escaped form is pinned as the corrupting one.
- [ ] The suite runs entirely on tracked fixtures — no assertion depends on an untracked config or on the state of this working copy.

**Effort:** S
**AID Role:** backend

**EPIC 2: Steps 5-7 — Guards that report success without checking**

### Step 5: `plan_diff` either checks the plan or leaves the profiles

**Objective:** The merge path stops carrying a gate row that verifies nothing.

**Files:**
- Modify: `.aid-o/config/execution.yaml` (lines ~218-243) — the self-host `plan_diff` gate gains the `command:` the shipped default has always had (`defaults/execution.yaml:109-116`) and an explicit `required: false` for the duration of this plan; the self-expiring exemption note that still names "P038+" is replaced by the resolved decision with its date, and by the true history (the command was never present, so this is an addition).
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (lines ~1944-1963) — a gate that appears in a profile's `include[]` with no `command` is a loud configuration refusal, not a `skip/no_command` row, so this cannot silently recur in any project.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — the new runner refusal is registered with its `type`/`source`/`instruction`/`severity`/`surface`, as this repository's contributor rules require of every new enforcement.
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — the refusal is a breaking configuration check for consumers mid-rollout, so it is named in both identical CHANGELOGs rather than left to be discovered on a first failed run.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-gate-command-required.bats` — a profile including a command-less gate fails the runner with a message naming the gate and the profile; a gate absent from every profile with no command is ignored; the shipped defaults pass unchanged; the refusal is present in the enforcement registry (tier: t1).

**Architecture Context:** Group 2. Verified: `yq '.gates.plan_diff.command'` returns null on the self-host config while the gate sits in **five** profiles — `standard`, `full`, `release`, `bats_all_quarantine`, `release_quarantine` — and `aid-run-gates.sh:1953-1963` turns a null command into `skip/no_command` with `required` defaulting to false. The history is knowable and the CP1 review corrected an earlier claim here: `.aid-o/config/execution.yaml` is force-added and tracked, with 16 commits since 2026-08-04, and `git log -S 'aid-plan-diff.sh --plan'` over that window returns nothing — so the command was **never** there. This is a first-time addition, not a restoration, and the same false "no history" claim embedded in the config file's own `plan_diff` note is corrected while the step is in there.

**Implementation Detail — decision made 2026-08-11, wire it up; advisory for now.** The gate is meaningful on every plan we currently write: `aid-plan-diff.sh` runs clean against this plan, parses its eleven criteria, and the convention is alive (P080 carries 8 `verification_pattern` blocks, P081 nine, P082 eight). It also closes OBS-20260702-09's heading concern, since `aid-plan-diff.sh:164` already accepts both `## Acceptance Criteria` and `## Success Criteria`.

**`required` stays `false` for the duration of this plan, and the CP1 review is why.** The gate evaluates the WHOLE source plan's criteria on every EPIC-level run, and eight of this plan's eleven suites do not exist until later steps land. Measured: exit 1, 11 of 11 absent. **Re-grounded 2026-08-11 evening after the C0 review found this stale:** `gate_profile_defaults` was `null` when this step was written, so every gate ran on every phase; it is now `{step: targeted, epic: standard}`, set the same afternoon. That changes the arithmetic but not the conclusion — `plan_diff` is a member of `standard`, so an EPIC run still executes it; `aid-run-gates.sh:2001` turns a failing required gate into `overall: fail` and `aid-fsm.sh:2989-3002` then refuses GATES→DONE. A `required: true` here would make this plan unable to finish itself. The blocking evaluation belongs at plan-final, where every suite exists. The runner-side refusal — the half that stops this recurring anywhere — lands regardless of the flag.

**Declared consequence:** once `plan-diff.json` exists, the `plan_ac_match` compliance key flips from `null` to `false` (`aid-fsm.sh:2573-2595`). It is registered `severity: blocking`; in this repository it degrades to advisory only because there is no `.aid-o/config/check-severity.yaml`. A consumer that has one would see `overall: fail` from two directions, which is a further reason the flag stays `false` until plan-final.

**Ordering obligation.** The config repair merges to main BEFORE the runner refusal ships, and any live worktree refreshes from main before its next gate run. `.aid-o/config/execution.yaml` is tracked but each worktree carries its own snapshot copy — including `.aid-worktrees/plan-P080`, whose copy still has the command-less `plan_diff` in five profiles. Without this ordering the shipped refusal hard-fails a concurrent session on a config it cannot repair by merging. Acceptance is evaluated in the checkout that runs the gate, not in whichever checkout is convenient.

**Error Handling:** The runner's new refusal names the gate, the profile and the config file — a misconfiguration must be actionable without reading the runner's source.

**Edge Cases:**
- A gate with a `command` but `required` absent — unchanged behaviour (advisory), since only a *missing command* is the new refusal.
- A consumer project whose config predates this change — the refusal fires on their first run with a message that says what to add; this is stated in the CHANGELOG as a breaking configuration check. The test-tier standard is mid-rollout to five other projects, so the CHANGELOG entry names the check explicitly rather than burying it.
- `bats_all_quarantine` and `release_quarantine` — treated exactly as the other three profiles; both carry `plan_diff` today.
- A mid-plan EPIC run — held to criteria the plan has not produced yet, which is why `required` is `false` until plan-final.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] No profile in this repository's own `execution.yaml` includes a gate without a `command`, asserted in the checkout that runs the gate.
- [ ] The runner refuses, by name, a profile that includes a command-less gate, and the refusal is registered in the enforcement registry.
- [ ] The "P038+" exemption note no longer exists in any form, and the note's replacement states the true history.

**Effort:** M
**AID Role:** backend

### Step 6: The config toggle stops resolving to "enabled" when it cannot be read

**Objective:** An explicit `enabled: false` is honoured on any grep, and a toggle that cannot be evaluated fails closed.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh` (lines ~20-30) — `_aid_read_toggle` replaces `grep -qP` with bash's own `[[ =~ ]]` or POSIX bracket classes (`[[:space:]]`), never a `\s`/`\b` shorthand: this machine has only GNU grep, which ACCEPTS those shorthands, so a "portable" pattern using them would pass here and fail elsewhere — exactly the irony the P082 review caught in its own portability fix. Bash's ERE genuinely rejects `\s`, so the construct self-polices. The function also distinguishes "read the toggle, it says enabled" from "could not read the toggle": the unreadable case is a named failure, not a silent `return 0`.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — the new fail-closed toggle refusal is registered with its `type`/`source`/`instruction`/`severity`/`surface`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-signal-toggle.bats` — `enabled: false` disables on a grep without PCRE support (simulated by a stub grep that exits 2 on `-P`); `enabled: true` enables; an unparseable toggle fails closed with a named message rather than defaulting to enabled (tier: t1).

**Architecture Context:** Group 2. This is the one PCRE site the sieve kept, because it is production library code rather than tooling: on a grep without PCRE both `-qP` calls exit 2, the `if` is false, and the function returns 0 = enabled — the exact fail-open the no-`grep -oP` invariant was created to prevent, invisible to the guard that enforces it.

**Implementation Detail:** The other twelve live PCRE sites and the guard's own blind spots stay out of scope by the PM's sieve; this step records the verified count (4 of 13 seen, `.bats` never scanned, one allowlist row granting three slots to a file with none) in the backlog entry so a later decision has the numbers.

**Error Handling:** An unreadable or malformed toggle is a refusal naming the config key and file — never an implicit "enabled".

**Edge Cases:**
- Toggle absent entirely — the documented default applies, unchanged, and is asserted so this step cannot quietly change it.
- Toggle present with an unexpected value — refusal, not coercion.
- A grep that supports `-P` — behaviour byte-identical to today for every existing case.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] With a stub grep that rejects `-P`, `enabled: false` disables the signal.
- [ ] An unparseable toggle fails with a named message and does not resolve to enabled.
- [ ] Existing review-signal suites stay green on a PCRE-capable grep.

**Effort:** S
**AID Role:** backend

### Step 7: A fresh consumer's profile table can satisfy the policy floor it is held to

**Objective:** A project initialised by `/aid-init` reaches `plan-finalize` without hitting an empty `release` profile.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` (lines ~206-266) — `render_gate_profiles_block` emits the full canonical ladder (`quick < targeted < standard < full < release`) composed from the gates the project's detected stacks actually define, instead of the two profiles (`targeted`, `full`) the here-doc at :256-265 emits today; the zero-stacks branch at :239-242 is left exactly as it is, because its fallback to `legacy_epic_release_mode` is handled and audited.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` (lines ~100-111 and ~208-212) — this T0 merge-path suite pins the exact two-profile output at three sites and turns red the moment the ladder lands; its expectations move to the five-profile shape in the same commit.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-init-gate-profiles.bats` — a workspace composed with a detected stack yields all five profiles, each naming only gates the composed file defines, and `release` is non-empty; `_pfsm_profile_include` resolves `release` against the composed file to a non-empty set (NOT `gate_profile_max`, which reads a static rank map and would pass vacuously); the zero-stacks branch still produces no table and the audited legacy fallback still fires with its named reason (tier: t1).

**Architecture Context:** Group 2, and the only step here motivated by other projects rather than by this one. Verified chain: shipped `plan-boundary-policy.yaml` sets `default_mode: plan_branch` and `plan_final_profile_floor: release`; a consumer with detected stacks gets `{targeted, full}`, so `_pfsm_has_gate_profiles` (`aid-plan-fsm.sh:9869-9880`) returns 0 and the plan flips to `plan_branch`; `aid-plan-fsm.sh:4485` then resolves at least `release` and `:4490-4493` aborts with "profile 'release' has an empty or missing include[]".

**Implementation Detail:** The recorded decision at `aid-plan-fsm.sh:9861-9868` — that P064 deliberately did not add the table to `defaults/execution.yaml` — is respected: this step does not touch that file. It fixes the composer, which is the path consumers actually take, and therefore does not reverse the decision the P082 review flagged.

**Error Handling:** A composed profile naming a gate the composed file does not define is a build-time failure in the new test, not a consumer's first-run surprise.

**The second consumer, named because the review found it and the plan had not.** `render_gate_profiles_block` also feeds the `/aid-init` EXISTING-project upgrade path, which appends its output verbatim to a PM's hand-authored `execution.yaml` whose `gates:` mapping the composer never wrote. A five-profile ladder appended there can name a gate that project does not define, and `aid-run-gates.sh:1583,1596` makes that a hard `exit 1`. Since `commands/aid-init.md` belongs to P080 and this step may not edit it, the route is fixed rather than left open: `render_gate_profiles_block` takes varargs-of-stacks and both callers pass stacks alone, so a new positional parameter would break the upgrade caller — the ladder is therefore derived from the gates present in the target `execution.yaml` discovered by the library itself — keyed on a **non-empty `gates:` mapping**, never on the file merely existing, because `compose_execution_yaml` truncates the target through `> "${output_file}"` (`lib/aid-init-execution-yaml.sh:417`) before the renderer runs, so an existence probe would always see a zero-byte file on the compose path and emit a degenerate ladder — falling back to the stack-derived set when no such mapping is present. The step's test covers an upgrade against a hand-authored config with a narrower gate set. "Stop and report" is NOT an acceptable landing here: both paths share one derivation, so an abandoned step leaves the composer half-migrated.

**Edge Cases:**
- Zero stacks detected — unchanged, still no table, still the audited legacy fallback.
- A stack whose gate set cannot populate `release` meaningfully — `release` includes what exists and the test asserts non-emptiness, not a fixed membership.
- An existing project re-running init — the additive-upgrade contract is unchanged; a project's own hand-written table is not overwritten.
- An upgrade target whose `gates:` mapping lacks a gate the ladder would name — the gate is omitted from the emitted profile, never named-and-undefined.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] A stack-detected workspace composed by `/aid-init` yields five profiles with a non-empty `release`, resolved through `_pfsm_profile_include` against the composed file.
- [ ] Every emitted profile names only gates the target file defines, on both the compose and the upgrade path.
- [ ] The zero-stacks path is byte-identical to today, fallback reason included, and `test-aid-init.bats` is green.

**Effort:** M
**AID Role:** backend

**EPIC 3: Steps 8-10 — Two decided deletions and the record**

### Step 8: The parallel-concurrency vocabulary leaves the gate-runtime baseline

**Objective:** The baseline library stops reading as though a scheduler still existed.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-gate-runtime-baseline.sh` (lines ~319-591, plus :853 and the usage string at :874) — the acceptor at :329-333 narrows to `sequential`; the non-sequential branches at :401, :507-527, :535, :561 and :591 and the whole `*_by_context` assembly are deleted, fields included.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — the new non-sequential-context refusal is registered with its `type`/`source`/`instruction`/`severity`/`surface`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-gate-baseline-sequential-only.bats` — a legacy baseline file carrying `*_by_context` data still reads and still produces correct percentiles; a non-sequential context argument is refused by name; the live baseline's numbers are numerically identical before and after (tier: t1).

**Architecture Context:** Group 3, and a pure deletion. Verified: both producers hardcode `sequential` (`aid-run-gates.sh:2024`/`:2101` and `aid-fsm.sh:3762-3769`, whose body is `printf 'sequential'` with a comment saying P078 removed the scheduler), the receipt schema is already `enum: ["sequential"]`, and the live baseline has empty `*_by_context` maps on every entry — there is nothing to migrate here.

**Implementation Detail — scope shrunk after review.** The original step kept the two map fields "present-but-empty for read compatibility". The CP1 review measured that apparatus into irrelevance: jq's `// {}` makes an absent key and an empty map indistinguishable to every reader; 9 of the 13 live baseline entries do not have the key at all and the other 4 have `{}`; and the sequential write path's carry-forward (`:435-444`) wipes a legacy file's populated maps on the very next gate run anyway. Preserving data that no consumer reads and the writer erases is exactly the machinery this plan's sieve rejects. Delete the fields with the branches; the test's job is to prove an OLD file still reads and still yields correct numbers, not that its dead keys survive.

**Error Handling:** A non-sequential context passed by a caller is a named refusal, so a resurrection attempt fails loudly instead of silently taking a deleted branch.

**Edge Cases:**
- A legacy file with populated `*_by_context` — reads without error, percentiles unaffected, keys dropped on the next write; asserted.
- A caller passing no context at all — the existing default applies, unchanged.
- `--help` text — updated in the same step; a stale usage string is how the vocabulary survives a deletion.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] The only surviving occurrences of `observe_parallel` or `parallel` in `aid-gate-runtime-baseline.sh` are inside the refusal message, verified by reading the matched lines rather than counting them.
- [ ] A legacy baseline file carrying `*_by_context` data reads without error and yields the same percentiles as before.
- [ ] The live baseline's percentiles are numerically identical before and after.

**Effort:** S
**AID Role:** backend

### Step 9: The C0 plan review stops claiming an input it never receives

**Objective:** The dependency-graph question in the C0 review is either answered from a real artifact or removed from the prompt.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/prompts/c0-plan-review-prompt-v1.md` (lines ~30-45) — mandatory check-table item 2 stops asking for an analysis of an artifact the review does not receive. The substitute is NAMED, not gestured at: **the plan's own per-step `Dependencies:` blocks** (`Depends on:` / `Blocks:`, already canonical and lint-enforced) are the dependency source, and the required output is the same as the graph's — is the ordering acyclic, and does any step consume an output no earlier step produces. The phrase "the pre-generation authority" at :32 either names a real input or goes.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-c0-plan-graph-input.bats` — with BOTH graph fields absent, the RENDERED prompt directs the reviewer at the `Dependencies:` blocks and asks for the cycle/unsatisfied-output analysis by name (fixture-based, asserting the rendered text, not the template's intent); the shipped prompt contains no requirement naming an artifact the manifest can record as absent without that substitute; a manifest recording `absent_pre_generation` still validates; a graph bound to a different plan hash is still refused (tier: t1).

**Architecture Context:** Group 3. Measured, not inferred: `P080/c0/codex/codex-prompt-vars.json` records both graph paths as `absent_pre_generation`, and the graph file's mtime is 37 minutes *after* the review it feeds. P076 and P079 show the same. The zero-byte-seal complaint in the original entry is already fixed and the graph is validated when present — only the ordering defeats it.

**Implementation Detail — decision made 2026-08-11 and then REVERSED by the CP1 review.** The first answer was "produce the graph earlier", on the measurement that the producer is a pure function of the plan: `aid-generation-readiness.sh` takes a plan path and nothing else, and run against this plan it emitted `aid-source-plan-graph/v1` in about a second — 10 steps, 1 edge, no cycles, bound to the plan's own sha256. That measurement stands. The conclusion did not survive review: `<evidence>/generation/provisional-graph.json` has exactly one writer (`aid-plan-to-epic.sh:136`) and one consumer (`aid-generation-finalize.sh:112-119`), where it serves as the producer-integrity seal — provisional bytes must equal final bytes. `--write-provisional` truncates unconditionally, so a C0 review run after generation began would silently re-bind that seal and the "this graph belongs to another plan revision" refusal could never fire again. Two further hazards compound it: the caller runs under `set -euo pipefail` while readiness exits 1 on a lint failure, and readiness prints its banner to the stdout that is `cmd_build_manifest`'s return channel.

**So the step keeps only its second half, which its own Objective already permits ("or removed from the prompt").** A prompt that asks for an analysis of an artifact the review never receives is the defect; not asking for it is a complete fix, costs two lines, and touches no seal. If a future plan wants the graph in the review, it must write to a C0-owned path, capture `rc`, redirect stdout, and say why pre-minting does not hollow out the finalize-time comparison.

**Error Handling:** A graph present but not bound to the reviewed plan hash is refused exactly as it is today; this step loosens nothing and writes nothing.

**Edge Cases:**
- A manifest recording `absent_pre_generation` — the prompt's substitute wording applies and is asserted.
- A plan for which a graph IS somehow present — the existing validation and hash binding are untouched.
- Low-risk plans that skip C0 entirely — unaffected.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] No shipped prompt requires an analysis of an artifact the manifest can record as absent without naming the substitute.
- [ ] With both graph fields absent, the rendered prompt names the `Dependencies:` blocks as the source and asks for the cycle and unsatisfied-output analysis.
- [ ] `provisional-graph.json` still has exactly one writer after this step.
- [ ] The existing C0 review suites stay green.

**Effort:** S
**AID Role:** backend

### Step 10: The backlog records what the verification found

**Objective:** Every entry the 2026-08-11 verification touched carries its verdict, so no later plan is written from a stale description again.

**Files:**
- Modify: `docs/plans/2026-06-29-BACKLOG.md` — the eleven verified-closed entries (7 already fixed, 2 moot, 2 deliberate) are marked closed with the file:line evidence that closed them; the ten entries this plan fixes point at it; the 22 verified-real-but-not-scheduled entries carry `verified real 2026-08-11` plus the sieve's reason for not scheduling them; the seven wrong-address entries have their descriptions replaced by what is actually true.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-backlog-verdicts.bats` — every entry touched by the verification carries a verdict line with a date; **at most one** verdict line per entry; no entry carries two contradictory framings; the file still parses for `test-deferred-work-registration.bats:123`'s `^#+ .*IMP-nnn` heading scan, the only consumer of this file's shape found in the tree (tier: t1).

**Architecture Context:** Group 3. This is the step that makes the whole exercise durable: the P082 failure was caused by descriptions that had drifted from the code, and a verdict line with a date is what stops the next reader trusting a stale one.

**Implementation Detail:** No archive split, no file move — the P082 review established that `docs/` is gitignored except for this one negated path, so a new file under `docs/plans/archive/` cannot be committed. Everything stays in the tracked file.

**The file is already half-annotated, and the rule is replace-in-place.** 32 of the 46 entries carry a `(verified 2026-08-11 …)` line from the audit pass that preceded this plan, written against v2.82.0 rather than v2.83.1. A verdict line is keyed on the entry id and REPLACED, never appended; where the older annotation and this verification disagree, the verification wins and the older line is deleted, not stacked. The anchor version discrepancy is resolved in the same edit so the file states one date and one baseline.

**Tier is `t1`, not `t0`.** A per-entry sweep over 46 entries in a 4 050-line file has no measurement behind a sub-two-second claim, and `tier_lint` is `required: true` in every merge-path profile — the first `--timing` run above the ceiling would turn a required gate red. `t1` is claimed from cost, and re-measured after the suite exists.

**Error Handling:** An entry the verification could not resolve is marked `UNRESOLVED` with what would be needed — never quietly left as-is.

**Edge Cases:**
- An entry with a later correction elsewhere in the file — the correction wins and the original framing is deleted, not annotated.
- An entry outside the verification's 46 — untouched and unmarked, so the absence of a verdict line means "not examined", which is honest.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] Every one of the 46 verified entries carries a dated verdict line.
- [ ] No entry contains both a retracted and a current framing.
- [ ] The eleven closed entries name the evidence that closed them.

**Effort:** S
**AID Role:** docs-writer

## Success Criteria

1. A streamlined-mode EPIC advances review→release without a force waiver, and a multi-line acceptance criterion survives generation intact in both the human section and `ac[]`.
2. An aborted release in a worktree leaves every previously-clean file clean, and `README.md`'s tagline shows the current version and keeps up with the next release.
3. No profile in this repository's `execution.yaml` includes a gate without a `command`, the runner refuses one by name, and `plan_diff` runs and reports this plan's own criteria instead of recording a skip — advisory during the plan, blocking at plan-final.
4. `enabled: false` is honoured on a grep without PCRE support, and a stack-detected `/aid-init` workspace yields a non-empty `release` profile.
5. The gate-runtime baseline carries no live non-sequential branch while a legacy file still reads and still yields correct numbers, and no shipped prompt asks the C0 reviewer to analyse an artifact the manifest records as absent.
6. All 46 verified backlog entries carry a dated verdict, including the recorded decision to retire the test-portfolio audit.

## Acceptance Criteria

- [ ] AC1: The streamlined integration review reads the gates report where gates write it.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-streamlined-integration-review.bats"
  expected_exit: 0
```
- [ ] AC2: Multi-line acceptance criteria survive generation in both extraction paths.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-ac-extraction.bats"
  expected_exit: 0
```
- [ ] AC3: A rolled-back release restores every file it touched.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-rollback.bats"
  expected_exit: 0
```
- [ ] AC4: The README tagline pattern matches a line containing literal parentheses.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-readme.bats"
  expected_exit: 0
```
- [ ] AC5: A profile including a command-less gate is refused by name.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-gate-command-required.bats"
  expected_exit: 0
```
- [ ] AC6: The self-host `plan_diff` gate has a command again.
```yaml
verification_pattern:
  type: cmd
  cmd: "test -n \"$(yq -r '.gates.plan_diff.command // \"\"' .aid-o/config/execution.yaml)\""
  expected_exit: 0
```
- [ ] AC7: The review-signal toggle fails closed instead of open.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-review-signal-toggle.bats"
  expected_exit: 0
```
- [ ] AC8: A composed consumer workspace yields five profiles with a non-empty `release`.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-init-gate-profiles.bats"
  expected_exit: 0
```
- [ ] AC9: The gate-runtime baseline is sequential-only and still reads legacy files correctly.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-gate-baseline-sequential-only.bats"
  expected_exit: 0
```
- [ ] AC10: No shipped prompt requires an artifact the manifest can record as absent.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-c0-plan-graph-input.bats"
  expected_exit: 0
```
- [ ] AC11: Every verified backlog entry carries a dated verdict.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-backlog-verdicts.bats"
  expected_exit: 0
```

## Constraints

- **The P080 collision is `defaults/enforcement-registry.yaml` and its two cite-tests, not the files this plan first guessed.** The CP1 review checked P080's actual branch: it does not touch `commands/aid-init.md` or `defaults/templates/` at all, but it does edit the enforcement registry — the exact file Steps 5, 6 and 8 must write to. Those three steps therefore coordinate with P080 on the registry (rebase onto its merge, or land after it), and Step 7 still avoids `commands/aid-init.md` because P080 owns the command surface by ownership even where it has not yet edited it.
- **Ordering: the self-host config repair merges to main before the runner refusal ships** (Step 5), and every live worktree refreshes from main before its next gate run. Each worktree carries its own snapshot of `.aid-o/config/execution.yaml`; a refusal shipped ahead of the config would hard-fail a concurrent session on a file it cannot repair by merging.
- **P082 is superseded**, not paused. It must not be generated; its CP1 evidence is retained as the record of why.
- Evidence filenames (`verifier-output-step-N.md` and the CP3 sibling) are frozen; no step renames them.
- No step adds a new detector, telemetry field or FSM precondition. Steps 5, 6 and 8 each add a refusal *inside an existing check*; those are the only new enforcement surfaces in the plan, each is named in its own step's Files list, and each is registered in `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — the live registry — in the same commit that adds it.
- Every new suite carries an `# aid-tier:` tag matching what its step declares.

## Risks

- **Step 5's decision could go either way and the profiles are the merge path.** Mitigation: the decision is made from one real `aid-plan-diff.sh` run against this plan, before the config is edited, and the runner-side refusal lands regardless of which way it goes.
- **Step 7 changes what every future consumer's workspace looks like.** Mitigation: the zero-stacks branch is untouched and asserted byte-identical; only the populated branch grows, and the new test proves every emitted profile is internally satisfiable.
- **Step 8 deletes ~90 lines from a hot library.** Mitigation: measured — no reader outside the writer library touches the `*_by_context` fields, and a legacy fixture with populated maps was shown to produce byte-identical output with and without them, so the deletion is strictly more convergent than emitting the fields empty.
- **Step 4 prescribes an edit to a regex whose search and replacement are the same string.** Mitigation: the corrupting form is pinned by a test of its own, not merely avoided in prose — the review caught this plan prescribing exactly that corruption once already.
- **The verification itself could be wrong somewhere.** Mitigation: every step names the line range its premise came from, and any step whose first read contradicts its premise stops and reports instead of proceeding — the P082 failure is the reason this sentence is here.

## Deferred

- **The untracked release config, and the pattern inside it.** Two things now live here because the C0 review refused to let them be smuggled into an implementation step: the broken BRE escaping in `.aid-o/config/project.yaml:32` (still wrong at the reviewed head — the tagline is current only because a human fixed the line once), and the one-time repair pattern itself. Neither can ride in an EPIC commit, so both belong to an operational remediation with a reproducible target and completion evidence, not to a plan step that would have to admit in its own text that it reaches nowhere.
- **`aid-release.sh`'s config path reads an UNTRACKED file.** `.aid-o/config/project.yaml` carries `versioning.files[]`, is gitignored and untracked, so no repair to it reaches a clone, a worktree or CI — and every worktree therefore silently takes the fallback path, which is the root of the rollback defect Step 3 patches and the reason Step 4's pattern fix cannot ship. Two tracked registries of the same fact already exist and are read by nothing (`defaults/orchestration.yaml:64-83`, `.aid-o/config/policies/release-policy.yaml:76+`). Teaching the release script to read one of them fixes both symptoms at their source; it is a plan of its own, not a fourth mechanism, and Step 4 asserts this deferral rather than quietly owning it.
- **Retiring the test-portfolio audit — decided, sized, and moved to its own removal plan.** The PM chose deletion over approval on 2026-08-11: the capability was built to decide test parallelism, that line was cancelled in P078, and the tier standard now answers the questions it was meant to answer, more cheaply. Measuring the blast radius is what moved it out of this plan: the audit layer is **16 scripts, 5 260 lines** (`aid-test-audit-*`, `aid-test-catalog-*`, `aid-audit-tests-finalize.sh`, `aid-init-upgrade-test-audit.sh`, `lib/aid-test-audit-*`), plus the `/aid-audit-tests` command, the `test-portfolio-analyst` agent, `defaults/config/test-audit.yaml`, enforcement-registry rows and their suites. But `aid-select-tests.sh` is **not** part of it: it is gate `targeted_tests` in the `targeted`, `standard` and `p064-closure` profiles, and it reads the catalog's `source_pattern_mappings[]` as its path→suite map. So the catalog file survives as the selector's mapping table while the audit around it goes, and the root `status` field with its command allowlist dies with the audit — which is how IMP-492 closes. That is a P078-shaped removal plan, not a step, and it must not be attempted inside this one.
- Widening the `grep -oP` guard to see all 13 live PCRE sites, `.bats` files included, and re-deriving its stale allowlist (the counts are recorded in the backlog entry).
- The 22 verified-real entries the PM's sieve rejected, each with its recorded reason.
- IMP-261, IMP-490, IMP-471, IMP-487, OBS-20260702-07 — separate plans.
- IMP-495 — waits for P080.
- IMP-496 (plans are never archived) — the verification found tasks have an enforcement and plans have nothing; doing it by hand until it hurts.
