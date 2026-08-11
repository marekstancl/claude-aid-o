---
id: P082
type: plan
status: draft
created: 2026-08-11
author: PM + AI
risk: high
---

# Plan: Close the Live Holes the Backlog Audit Found, and Make the Backlog Tell the Truth

## Stakeholder Brief

A full audit of the 101-entry backlog against the current tree found that forty-five entries were already fixed but still filed as open, three were dead, and roughly thirty remained real. This plan does two things. First it closes the handful of remaining defects that are genuinely dangerous — several of which will bite the other projects the moment the test-tier standard rolls out to them: a placeholder in a plan's file list silently blocks every commit through the pre-commit hook, the shipped configuration template is missing the one table that decides a project's release model, and the release script rewrites README version references with a blind global substitution. Second it fixes a class the audit kept finding: a guard whose name promises more than it checks — a portability check that cannot see two live violations, a review-range that is silently guessed when its input is missing while its twin fails closed, and a prefilter that destroys valid evidence when pointed at the wrong checkpoint. The rest is honest bookkeeping: the backlog is split into a short live queue and a dated archive, every closed entry carries the evidence that closed it, and everything consciously parked says so with a reason. Risk is moderate and spread thin — twelve small, independent fixes rather than one large mechanism, each with its own regression.

## Context

Source: a two-part audit of `docs/plans/2026-06-29-BACKLOG.md` performed 2026-08-11 against `main` at v2.82.0, verifying every entry's concrete claim against live code rather than against its recorded status. Results: **45 entries verified DONE** (12 shipped by P079, 12 from the older IMP-261..282 block, 20 from the OBS/B block, plus IMP-489 as a duplicate of an already-shipped entry) and marked as such in the file with their closing evidence; **3 DEAD** (the live-usage probe is a concluded activity; the parallel-group conflict guard died with P078's removal; the methodology blind spots were disclosed non-goals). What survives is this plan's scope.

The audit also corrected two beliefs worth recording: IMP-282 was closed by P073's probe primitive, not by P079's tag-seal guard (they are different controls on the same file), and the `grep -oP` portability guard that has looked green for weeks is evadable — it matches a literal string, so two live PCRE call sites are invisible to it, one of them in production review-signal logic where a non-GNU grep would silently misfire a whole branch.

Timing matters: the ecosystem test-tier standard is published and AID's pilot (P081) is being implemented, after which the standard rolls out to WAN, ACTA, Sousto, AI-Agenti and VULCAN. Three of the defects below are consumer-facing and would meet those projects on arrival.

## Goal

Every defect the audit proved still live is either fixed with a regression that pins it, or parked with a written reason; and the backlog is a short, honest queue instead of a four-thousand-line mixture of history and work.

## Scope

**In scope:**
- The three consumer-facing defects: unresolved `{rev}`-style placeholders in `allowed_paths` blocking commits, the shipped `defaults/execution.yaml` lacking a `gate_profiles` table, and the release script's blind README substitution.
- The guard-honesty class: widening the `grep -oP` detector and clearing the two live PCRE sites; making the CP3 review range fail closed like its CP2 twin; stopping the CP3 prefilter from overwriting CP2 evidence; pointing the streamlined integration check at the path the runner actually writes.
- Two evidence-truth fixes: `set-field` emitting a timeline event, and task frontmatter being restamped at archival instead of staying `active / runs_completed: 0` forever.
- The dogfood ref-isolation preflight (IMP-280) and closing the debug CLI path that can still mint `lineage: proven` (IMP-268).
- The EPIC generator's silent truncation of multi-line acceptance criteria.
- Backlog hygiene: split into a live queue and a dated archive, ensure every surviving entry has a status, and record the parked items with reasons.
- Three leftovers from the P081 whole-diff review, added 2026-08-11 because they are the same class this plan already treats — a mechanism that promises more than it delivers: **(a)** the durations journal is written under `.aid-o/` inside the CI checkout and wiped every run, so the nightly's `--timing` pass refreshes nothing and the lint's "has this suite outgrown its tier" check is machine-local despite the workflow claiming otherwise; **(b)** 156 of 161 T2 suites were tiered by subject-resolution failure rather than by cost — 82 of them run under 2 s and all 41 shell suites are among them — so the merge path is far thinner than the pilot intended and nothing distinguishes a deliberate scope call from a naming gap; **(c)** the nightly report writes `quarantine_unreadable` and `quarantine_write_failed` that no consumer reads, so an unreadable quarantine record hides behind a green status line.

**Out of scope:**
- IMP-261 (project-scoped configuration and the versioned settings schema) — it is a plan of its own; P080 discharges only its init/setup-ownership slice, and the audit confirmed the rest is untouched. Parked with that note.
- IMP-281 (`docs_updated` manufacturing a pass) — its own precondition, a local reproduction, is still unmet; this repo's gate is a genuine heuristic. Parked deliberately.
- The C3 no-op when `review-profile.json` is entirely absent, and the release-decision `head_match` promotion to blocking — both are explicitly deferred to E10 by existing policy; this plan does not pre-empt that decision.
- CP2 test-scope selection (OBS-20260711-02), cross-repo CP3 dispatch, the E6/E8 deferred blocks and the P041 Wave-2 items — no mechanism exists for any of them and none is urgent; they stay in the live queue with their reasons.
- The two P081 leftovers already fixed in v2.83.1 (quarantine ownership; the retry that laundered a real failure into a green night) — done, not planned.
- Anything the test-tier pilot (P081) already covers — in particular the advisory-gate wallpaper around `shell_pipeline_smoke`, which P081 removes from the merge path.

## Approach

Chosen: **twelve independent small fixes, ordered by who gets hurt** — consumer-facing first (because the standard rollout starts soon), then the guards that lie about their own coverage, then the local truth fixes, then the bookkeeping. Each fix carries a regression that pins the specific incident the audit found, so a later refactor cannot quietly restore it.

Alternatives rejected: (a) one sweeping "guard hardening" refactor — the audit shows these guards fail for unrelated reasons (a literal-string pattern, a missing fail-closed branch, a path constant, a filename computed before the checkpoint is known); a single refactor would couple twelve independent risks; (b) fixing everything the audit listed — several items are correctly parked and forcing them now would repeat the pattern the whole backlog cleanup exists to end; (c) leaving the backlog file whole and only marking statuses — the audit proved that half the file is July narrative, and a queue nobody can read is a queue nobody prunes.

## Architecture

Four groups, each independently releasable.

1. **Consumer-facing (Steps 1-3).** These are defects a fresh project meets on day one. The `{rev}` placeholder case is the sharpest: `defaults/hooks/pre-commit` matches `allowed_paths` entries by literal equality or prefix, so a plan that writes `migrations/{rev}_name.py` — the Alembic convention, i.e. every project with database migrations — produces an entry that matches nothing and the hook **blocks the commit**. The `gate_profiles` gap is quieter but wider: the shipped template lacks the table, and the plan-mode default keys on its presence, so every project initialised from defaults silently falls back to per-EPIC releases, undoing the settled plan-branch policy. The README substitution is a blind global `sed` over every README within three levels, run on every release.
2. **Guards that under-deliver (Steps 4-7).** A detector whose name promises more than its pattern checks is worse than no detector, because it produces a green that stops anyone looking. Four instances: the `grep -oP` scanner matches one literal spelling; the CP3 prefilter guesses its review range when `base_commit` is missing while the CP2 path fails closed; the same prefilter computes its output filename before it knows the checkpoint, so a CP3 invocation overwrites CP2 evidence; and the streamlined integration check reads a gates report at a path the runner stopped writing.
3. **Truth of the local record (Steps 8-10).** `set-field` mutates state without an event, so "state matches events" cannot be verified; task frontmatter is stamped once at generation and never again; the dogfood preflight that would stop a self-test mutating the repository it tests does not exist, and the manifest CLI can still mint proven lineage by hand.
4. **The backlog itself (Steps 11-12).** Split live from archive, guarantee every surviving entry has a status and a reason, and add the small check that keeps it that way.

## Implementation Steps

**EPIC 1: Steps 1-4 — What a consumer project meets first**

### Step 1: Unresolved path placeholders stop blocking commits

**Objective:** A plan whose `allowed_paths` contains a generated-name placeholder no longer blocks every commit in the run.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-commit` (lines ~85-115) — `_aid_in_scope` treats an entry containing a `{...}` placeholder as a glob whose placeholder matches one path segment, so `migrations/{rev}_add_users.py` admits `migrations/a1b2c3_add_users.py`; a placeholder that spans a directory separator is rejected loudly rather than widened.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~6050-6075) — the out-of-band `commit_scope_violation` companion uses the same predicate, so telemetry and the blocking hook cannot disagree.
- Create: `plugins/aid-orchestrator/scripts/lib/aid-scope-match.sh` — the one shared predicate both callers source, so a future third consumer cannot invent a third rule.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-scope-placeholder-match.bats` — an Alembic-shaped entry admits a real migration filename and rejects a file in another directory; a literal entry behaves exactly as before; a placeholder containing `/` is refused with a named error; the hook and the FSM companion agree on every case.

**Architecture Context:** Group 1. The audit found this is not merely noisy telemetry as originally filed — the identical literal predicate lives in the blocking pre-commit hook, so the failure is a blocked commit, systematically, for any project using generated migration filenames.

**Implementation Detail:** The placeholder syntax already appears in plans as `{rev}`; the predicate converts `{name}` to a single-segment wildcard rather than a full glob, so a placeholder cannot silently widen scope across directories. The shared library is the point: the audit's recurring finding is two copies of a rule drifting apart.

**Error Handling:** A malformed placeholder (unbalanced brace) is a loud refusal naming the entry, never a silent literal match — an unparseable scope rule must not resolve to "allow".

**Edge Cases:**
- An entry with two placeholders — each matches one segment; pinned in bats.
- A placeholder at the start of an entry — matches within the declared directory only, never repo-root-wide.
- A literal file whose name genuinely contains braces — escaped form documented and pinned.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] An Alembic-shaped `allowed_paths` entry admits the real generated filename in both the hook and the FSM companion.
- [ ] A placeholder spanning `/` is refused by name; a malformed placeholder is refused, not ignored.
- [ ] Existing literal-entry behaviour is byte-identical (the pre-existing scope suites stay green).

**Effort:** M
**AID Role:** backend

### Step 2: The shipped template carries the table that decides the release model

**Objective:** A project initialised from the plugin's own defaults gets `plan_branch`, not a silent fallback to per-EPIC releases.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/execution.yaml` (lines ~1-160) — add a `gate_profiles` table with the same rank order this repo uses (`quick < targeted < standard < full < release`), each profile listing gates the template actually defines, so the plan-mode default resolves to `plan_branch` for a fresh project.
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — the Plan mode section: state the coupling plainly: the release model follows from this table's presence, and declining the additive upgrade keeps a project on legacy mode.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` — a workspace composed from the shipped template resolves `__default-mode` to `plan_branch`; every profile in the template names only gates the template defines; a project whose table is removed falls back with the named reason.

**Architecture Context:** Group 1. The audit rated this higher than when it was filed, because the plan-mode default now keys on the table's presence: the shipped template's omission silently undoes the settled plan-branch policy for every consumer, which is precisely the population the standard rollout is about to touch.

**Implementation Detail:** The template's profiles reference only gates it defines — the audit's sibling finding is that a profile naming an undefined gate is now a hard error, so an over-copied table would break generation instead of helping.

**Error Handling:** A template profile naming an undefined gate fails the new test at authoring time, not a consumer's first run.

**Edge Cases:**
- An existing project that already added its own table — `/aid-init` upgrades are additive and must not overwrite it (the existing idempotency contract covers this; the test asserts it).
- A project that deliberately wants legacy mode — removing the table is the documented way, with the fallback reason recorded.
- A stack template that defines a different gate set — profiles are composed from the gates present, not hardcoded.

**Dependencies:**
- Depends on: none
- Blocks: Step 12 — the parked-items list references this as closed.

**Acceptance Criteria:**
- [ ] A workspace built from the shipped defaults resolves to `plan_branch`.
- [ ] Every profile in the shipped template names only gates the template defines.
- [ ] Re-running init over a project with its own table changes nothing.

**Effort:** M
**AID Role:** backend

### Step 3: The release script stops rewriting README text blindly

**Objective:** A release updates the roadmap line it means to update, and cannot corrupt unrelated version references.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~655-680) — replace the global `sed s/v$CURRENT/v$NEW_VERSION/g` over every README within three levels with an anchored roadmap edit: insert a new `- **vX.Y.Z** (current) — …` line, demote the previous current line, and keep the three most recent versions per the repository's own documented convention; every other occurrence of the old version string is left alone.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-readme.bats` — a README whose prose mentions the previous version outside the roadmap keeps that mention; the roadmap gains the new line and demotes the old; a README with no roadmap section is left untouched with a warning rather than mangled.

**Architecture Context:** Group 1, and the fifth recurrence of this class. The audit notes the root cause was never touched: the substitution is a token replacement with no notion of the structure it edits.

**Implementation Detail:** The roadmap's shape is already specified in the repository's own contributor documentation (three most recent versions, newest first) — this step implements that specification rather than inventing one.

**Error Handling:** No roadmap section found ⇒ warn and skip that file; a release must not fail on a README that never had one, and must not guess where the line belongs.

**Edge Cases:**
- Two READMEs (root and plugin) — both handled, each independently.
- A roadmap already containing the new version (a re-run) — no-op, matching the CHANGELOG's own pre-written-entry behaviour.
- A version string appearing inside a code block — untouched, because only the roadmap list is edited.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] A prose mention of the old version outside the roadmap survives a release.
- [ ] The roadmap gains the new current line and demotes the previous one, keeping three.
- [ ] A README without a roadmap is untouched and the skip is reported.

**Effort:** M
**AID Role:** backend

### Step 4: The multi-line acceptance criterion stops being truncated

**Objective:** An acceptance criterion that wraps onto a second line reaches the EPIC intact.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (lines ~885-910) — the awk block that emits acceptance criteria treats an indented continuation line as part of the preceding criterion instead of dropping it; a continuation with no preceding criterion is a loud error, not a silent skip.
- Test: `plugins/aid-orchestrator/scripts/tests/test-plan-to-epic.sh` — a wrapped criterion arrives whole in the generated EPIC; an orphan continuation fails generation naming the line; single-line criteria are unchanged.

**Architecture Context:** Group 1 by consequence — the generated EPIC is what an implementer reads, so a truncated criterion is a requirement that silently shrank between the plan and the work.

**Implementation Detail:** The rule mirrors the Files-bullet grammar the repository already uses, where an indented line continues the entry above it — one convention, two consumers.

**Error Handling:** An orphan continuation stops generation with the plan path and line, consistent with the loud-refusal class the repository adopted for dropped Files bullets.

**Edge Cases:**
- A criterion wrapped across three lines — all joined.
- A blank line between a criterion and its continuation — ends the criterion; pinned.
- A code fence inside the acceptance-criteria section — not treated as prose.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] A wrapped criterion appears whole in the generated EPIC.
- [ ] An orphan continuation fails generation naming the line.
- [ ] Existing single-line plans generate byte-identically.

**Effort:** S
**AID Role:** backend

**EPIC 2: Steps 5-8 — Guards that promise more than they check**

### Step 5: The portability guard sees every spelling, and the two live violations are cleared

**Objective:** The `grep -oP` invariant is actually enforced, and the two production call sites that evade it today are fixed.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats` — the portability scan: the detector matches any PCRE flag spelling rather than one literal string, and its self-test includes the evading forms; the per-file allowlist is re-derived from the widened scan.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh` (lines ~20-30) — the two `grep -qP` calls become POSIX equivalents; on a grep without PCRE these currently fail with an error exit, which silently means "section not disabled" — the branch never fires.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (line ~341) — the probe primitive's own PCRE use is either converted or explicitly allowlisted with a stated reason, since it is the function introduced to make probes safe.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats` — the widened detector flags each evading spelling in a fixture and stays green over the cleared tree.

**Architecture Context:** Group 2's clearest case: a guard that has been green for weeks while two live violations sat outside its pattern. The review-signals one matters most — it decides whether a review section is disabled, and on a non-GNU grep the whole branch misfires.

**Implementation Detail:** The widened pattern tolerates flag order and combination (`-oP`, `-qP`, `-Pq`, `--perl-regexp`); the self-test asserts the detector catches each, so the scan cannot regress to literal matching.

**Error Handling:** A file that legitimately needs PCRE is allowlisted with a written reason in the allowlist itself, never by weakening the pattern.

**Edge Cases:**
- A comment mentioning `grep -oP` — excluded, as today.
- A test fixture that deliberately contains the pattern — allowlisted by path.
- `--perl-regexp` long form — caught.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] The widened detector flags every evading spelling in its self-test.
- [ ] The scan is green over the tree with no PCRE left in `aid-review-signals.sh`.
- [ ] Any remaining allowlist entry carries a written reason.

**Effort:** M
**AID Role:** backend

### Step 6: The CP3 review range fails closed, like its CP2 twin

**Objective:** A CP3 review whose base cannot be resolved refuses instead of guessing.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-prefilter.sh` (lines ~155-170) — the CP3 path adopts the CP2 resolution order: the recorded base, else the step boundary, else refuse with the same `range_undetermined` exit rather than falling back to `merge-base` or `HEAD~5`; the observe-policy escape mirrors CP2's, including its loud event.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-prefilter.bats` — a CP3 invocation with no resolvable base refuses; with a recorded base it classifies exactly as today; the observe escape emits its event and warns.

**Architecture Context:** Group 2. The audit's sharpest asymmetry: the CP2 half of this exact defect was hardened to fail closed, and the CP3 half was left guessing — so the more consequential review (the final one) has the weaker range guarantee.

**Implementation Detail:** The two paths share one resolution helper after this step, so the asymmetry cannot reappear by editing one branch.

**Error Handling:** Refusal names which input was missing (`base_commit`, `fsm-state.yaml`, or the step boundary) so the operator knows what to supply.

**Edge Cases:**
- A legitimate first-step CP3 where no prior boundary exists — the recorded base covers it; pinned.
- A run whose `fsm-state.yaml` is absent (ad-hoc invocation) — refuses with the named reason.
- The observe escape — allowed, evented, warned, exactly as CP2.

**Dependencies:**
- Depends on: none
- Blocks: Step 7 — both touch the same script.

**Acceptance Criteria:**
- [ ] CP3 with no resolvable base refuses with `range_undetermined`.
- [ ] CP2 and CP3 resolve through one shared helper.
- [ ] The observe escape behaves identically on both paths.

**Effort:** M
**AID Role:** backend

### Step 7: The prefilter stops overwriting the evidence of another checkpoint

**Objective:** A CP3 prefilter invocation can no longer destroy a valid CP2 verifier output.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-prefilter.sh` (lines ~90-100) — the output filename is derived after the checkpoint is known and carries it, so CP2 and CP3 cannot collide; alternatively the CP3 checkpoint is refused for the classify path with a named error. The step picks one and states which in its verify output.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-prefilter.bats` — a CP3 classify run leaves an existing CP2 output byte-identical; the FSM's checkpoint assertion still rejects a wrong-checkpoint file; a CP2 run is unchanged.

**Architecture Context:** Group 2. The FSM already fails loud when a step verifier output carries the wrong checkpoint, so the damage is no longer silent — but the valid evidence is still destroyed, and no regression pins it.

**Implementation Detail:** Deriving the filename after the checkpoint is the smaller change and preserves the ability to prefilter CP3 at all; refusing the checkpoint is simpler but removes a capability. The step's verify output records which was chosen and why.

**Error Handling:** An existing file at the target path is never silently overwritten by a different checkpoint — the run refuses and names both.

**Edge Cases:**
- A legitimate re-run of the same checkpoint — overwrite is correct and stays allowed.
- A step with no prior output — unchanged.
- The FSM's checkpoint assertion — must keep failing on a wrong-checkpoint file, proving this fix did not weaken it.

**Dependencies:**
- Depends on: Step 6 — same script.
- Blocks: none

**Acceptance Criteria:**
- [ ] A CP3 classify run leaves an existing CP2 output byte-identical.
- [ ] The FSM's wrong-checkpoint refusal still fires.
- [ ] The chosen approach and its reason are recorded in the step's verify output.

**Effort:** M
**AID Role:** backend

### Step 8: The streamlined check reads the report that exists

**Objective:** The streamlined integration review looks for the gates report where the runner writes it.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~1820-1840) — `fsm_check_streamlined_integration_review` resolves the gates report through the same path the runner and every other reader use, instead of a flat sibling path the runner stopped writing.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` — a streamlined run with a real gates report passes the check; a run with no report still hard-fails with its documented message; no other reader's path changes.

**Architecture Context:** Group 2. A documented hard-fail check that points at a path nothing writes is a check that always fails or always misleads, depending on the run; the audit found it is the last consumer still on the pre-consolidation path.

**Implementation Detail:** One constant, one reader — the fix is small precisely because every other consumer already migrated.

**Error Handling:** Genuine absence keeps its existing hard error; only the location changes.

**Edge Cases:**
- A legacy run with an old flat report present — accepted with a note, so an in-flight run is not stranded.
- Streamlined mode disabled — untouched.
- A report that exists but is malformed — the existing malformed-report handling applies.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] The streamlined check passes on a run whose report is at the canonical path.
- [ ] Absence still hard-fails with the documented message.
- [ ] No other reader's resolution changed.

**Effort:** S
**AID Role:** backend

**EPIC 3: Steps 9-12 — Local truth and the backlog itself**

### Step 9: State changes leave a trace, and a finished EPIC says so

**Objective:** `set-field` emits an event, and an archived EPIC's frontmatter reflects that it finished.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~6085-6125) — `cmd_set_field` emits an `fsm_field_change` timeline event carrying field, old value, new value and caller, so "state matches events" becomes checkable.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~6890-6910) — the archival path: archiving a completed EPIC restamps its task frontmatter (`status`, `runs_completed`) instead of moving a file that still claims to be active with zero runs.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` — a set-field call appends exactly one event with both values; archival restamps the frontmatter; a legacy task file without those keys is archived unchanged rather than failing.

**Architecture Context:** Group 3. Both are "the record disagrees with reality" defects: one makes the timeline incomplete, the other leaves every completed EPIC's own file lying about its state.

**Implementation Detail:** The event uses the existing logging helper, which never fails a command — telemetry must not become a new failure mode on a state write.

**Error Handling:** A timeline that cannot be written warns and the field write still succeeds; the reverse (event written, field not) must not happen — the event is emitted after a successful write.

**Edge Cases:**
- Setting a field to its current value — event still emitted, values equal, so a no-op is visible rather than invisible.
- Archival of an EPIC that never ran — `runs_completed: 0` is correct and stays.
- A task file with hand-edited frontmatter — restamp only the two known keys.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] A set-field call appends exactly one event with old and new values.
- [ ] An archived completed EPIC's frontmatter shows its terminal status and run count.
- [ ] A legacy task file archives without failing.

**Effort:** M
**AID Role:** backend

### Step 10: A self-test cannot mutate the repository it tests

**Objective:** The dogfood ref-isolation preflight exists, and the hand path that could mint proven lineage is closed.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-dogfood-guard.sh` — compares the source repository's and the dogfood target's absolute common git directory and refuses when they are equal unless a namespaced target ref or a separate clone is supplied; records the evaluated paths and the selected safe mode so the receipt shows what was checked.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` (lines ~1630-1660) — the `add-epic` subcommand on the executable path no longer accepts a lineage argument (or is removed), so the documented invariant "only epic-start and attestation establish proven lineage" becomes literally true.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-dogfood-guard.bats` — shared common dir refuses; namespaced ref or separate clone passes and records the mode; the manifest CLI can no longer mint `proven` (negative test).

**Architecture Context:** Group 3, and the audit's highest-risk open item: a dogfood run sharing refs with the repository under test has already advanced the real branch once and needed a compare-and-swap restore.

**Implementation Detail:** The comparison uses the absolute common directory rather than the working-tree root, so a linked worktree is correctly recognised as the same repository.

**Error Handling:** An unresolvable common directory refuses — an unknown relationship between two repositories is not evidence of separation.

**Edge Cases:**
- A legitimate separate clone that happens to share a path prefix — compared by common dir, not by prefix.
- A bare repository target — handled or refused explicitly, never assumed safe.
- An existing caller that passes a lineage argument to the CLI — fails loudly at the call site rather than silently ignoring it.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] A shared-common-dir dogfood target is refused; a namespaced or cloned target passes and records the mode.
- [ ] The manifest CLI cannot produce `lineage: proven`, proven by a negative test.
- [ ] The receipt shows the evaluated paths.

**Effort:** M
**AID Role:** backend

### Step 11: The backlog becomes a queue again

**Objective:** Split the four-thousand-line mixture into a short live queue and a dated archive, with every closed entry carrying the evidence that closed it.

**Files:**
- Create: `docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md` — every entry the audit verified as DONE or DEAD, moved whole with its closing evidence and an archive header stating the audit date and the tree it was verified against.
- Modify: `docs/plans/2026-06-29-BACKLOG.md` — retains only live entries (OPEN, PARTIAL and consciously parked), each with a status line and, for parked ones, the reason and the condition that would revive it; a short header states the live count and points at the archive.
- Test: `plugins/aid-orchestrator/scripts/tests/test-backlog-hygiene.sh` — every entry heading in the live file has a status line; no entry marked DONE or DEAD remains in the live file; every parked entry carries a reason; the archive is append-only relative to the previous commit.

**Architecture Context:** Group 4. The audit's own finding: 101 headings, of which 45 were already done and a large middle section is July narrative. A queue that cannot be read in one sitting does not get pruned, which is how it reached this size.

**Implementation Detail:** Entries move whole, never summarised — the closing evidence is the value. The live file keeps its filename so every existing cross-reference still resolves.

**Error Handling:** An entry whose verdict is ambiguous stays live and is marked as needing a decision, rather than being archived on a guess.

**Edge Cases:**
- An entry referenced by a live plan or checklist — moving it must not break the reference; the archive header records the original file so a reader can follow.
- Section-level items with no id — carried with their section heading.
- The narrative probe-update sections — archived as history, not as entries.

**Dependencies:**
- Depends on: none — the hygiene check ships with this step.
- Blocks: Step 12.

**Acceptance Criteria:**
- [ ] The live file contains no DONE or DEAD entry and every heading has a status.
- [ ] Every parked entry states its reason and its revival condition.
- [ ] The hygiene harness passes and is discovered by the runner.

**Effort:** M
**AID Role:** docs-writer

### Step 12: Register, document and release

**Objective:** Every new mechanical check is registered, the parked decisions are written down, and the work ships.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows for the shared scope predicate, the widened portability detector, the CP3 range refusal, the prefilter collision refusal, the dogfood guard and the backlog hygiene check, each with source, instruction, severity, surface and test; totals recomputed by the file's own command.
- Modify: `docs/extending-aid.md` — a short section recording the audit's standing lesson: a guard is only as wide as its pattern, and every new detector ships with a self-test that proves it catches the evading form.
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — one identical entry per the repository format.
- Modify: `.claude-plugin/marketplace.json` + `plugins/aid-orchestrator/.claude-plugin/plugin.json` + `plugins/aid-orchestrator/README.md` + `README.md` — the remaining version-registry locations, with the roadmap updated through Step 3's new anchored edit (this release is its first live exercise).
- Test: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — full pass including the CHANGELOG byte-identity assertion.

**Architecture Context:** The repository's standing mandate that every detection capability is registered, executed once at the end when all the mechanisms exist.

**Implementation Detail:** The release exercises Step 3's roadmap edit for the first time; the step's verification records the before and after roadmap lines so the fix is proven on a real release rather than only in fixtures.

**Error Handling:** Registry totals mismatch fails this step's own verification before the release proceeds.

**Edge Cases:**
- Another plan releasing first — bump from the actual head.
- A registry row whose source path this plan renamed — re-verified here.
- The roadmap edit misbehaving on the real release — caught by the recorded before/after, and the release stops rather than shipping a corrupted README.

**Dependencies:**
- Depends on: Step 1, Step 5, Step 6, Step 7, Step 10, Step 11 — registers and documents what they built.
- Blocks: none — terminal step.

**Acceptance Criteria:**
- [ ] Registry tests pass with the new rows and recomputed totals.
- [ ] All eight version locations agree; both CHANGELOGs byte-identical.
- [ ] The release's roadmap edit is recorded before and after and is correct.

**Effort:** M
**AID Role:** release

## Testing Strategy

- Every fix ships a regression that reproduces the exact incident the audit found, so the specific defect cannot return unnoticed.
- The two shared-predicate steps (1 and 6) additionally assert that both consumers agree, since the audit's recurring shape is one rule with two drifting copies.
- The portability detector ships a self-test that proves it catches the forms that evaded it — a detector without one is the defect this plan is fixing.
- Per the ecosystem test standard, new suites declare their tier; no full-portfolio run is required to close this plan.

## Constraints

- Sequenced after P081's tier work where they touch the same runner configuration; if P081 has not landed, Step 12's release notes say so and the tier declarations follow the standard's defaults.
- Frozen surfaces: evidence filenames, machine-facing JSON field names, and the 0-based `current_step` semantics.
- No new runtime dependency: bash, jq, yq, awk, git, bats.
- Parked items stay parked: this plan must not quietly start IMP-261's settings schema, IMP-281's disposition contract, the C3 absent-profile promotion or the release-decision `head_match` promotion.
- Language: plan and code in English, PM conversation in Czech.

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| The placeholder predicate widens scope more than intended | Medium | High | Single-segment matching only, `/`-spanning refused, both consumers share one predicate and are asserted equal |
| Adding `gate_profiles` to the shipped template breaks an existing consumer's upgrade | Low | High | Additive only; the idempotency contract is asserted in the same step |
| The roadmap edit misfires on the real release | Medium | Medium | Fixture-covered, and Step 12 records the before/after on the live release |
| The CP3 range refusal blocks a legitimate first-step review | Medium | Medium | Recorded base covers it; the observe escape mirrors CP2's and is evented |
| Archiving the backlog breaks a cross-reference | Medium | Low | Filename preserved, archive header records provenance, ambiguous entries stay live |
| The audit's own verdicts are wrong somewhere | Low | Medium | Every closure carries its evidence in the file; a wrong closure is visible and reversible |

## Success Criteria

1. A project with generated migration filenames can commit; a project initialised from the shipped defaults gets `plan_branch`; a release leaves unrelated README prose alone.
2. The portability guard catches every PCRE spelling and the tree is clean of the two live violations.
3. CP3 refuses an unresolvable review range and cannot destroy CP2 evidence; the streamlined check reads the report that exists.
4. State changes are evented and a finished EPIC's own file says it finished.
5. A dogfood run cannot mutate the repository it tests, and proven lineage has exactly two producers.
6. The live backlog is short enough to read in one sitting, every entry has a status, and everything parked says why.

## Acceptance Criteria

- [ ] AC1 — Placeholder scope matching is correct and shared.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-scope-placeholder-match.bats"
  expected_exit: 0
```
- [ ] AC2 — The shipped template yields plan_branch.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats"
  expected_exit: 0
```
- [ ] AC3 — The release leaves unrelated README prose alone.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-readme.bats"
  expected_exit: 0
```
- [ ] AC4 — Multi-line acceptance criteria survive generation.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/tests/test-plan-to-epic.sh"
  expected_exit: 0
```
- [ ] AC5 — The prefilter fails closed on range and cannot overwrite another checkpoint.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-prefilter.bats"
  expected_exit: 0
```
- [ ] AC6 — The dogfood guard refuses a shared-ref target and the CLI cannot mint proven lineage.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-dogfood-guard.bats"
  expected_exit: 0
```
- [ ] AC7 — The backlog is hygienic.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/tests/test-backlog-hygiene.sh"
  expected_exit: 0
```
- [ ] AC8 — No PCRE remains in the review-signals library.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -c '! grep -nE \"grep[^|;]*-[A-Za-z]*P\\\\b\" plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh'"
  expected_exit: 0
```

## Next Steps

1. `aid-plan-lint.sh` + `aid-generation-readiness.sh --total 3`; repair diagnostics.
2. CP1 verifier with the evidence protocol; risk high ⇒ CP1-deep + C0 Codex loop at generation.
3. Implement after P081 lands, or in parallel if the PM prefers — the two plans touch different files except the runner configuration.
