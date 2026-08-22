---
id: REF-P082
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P082-backlog-truth-and-live-holes.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P082

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-commit` (lines ~85-115) — `_aid_in_scope` treats an entry containing a `{...}` placeholder as a glob whose placeholder matches one path segment, so `migrations/{rev}_add_users.py` admits `migrations/a1b2c3_add_users.py`; a placeholder that spans a directory separator is rejected loudly rather than widened.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~6050-6075) — the out-of-band `commit_scope_violation` companion uses the same predicate, so telemetry and the blocking hook cannot disagree.
- Create: `plugins/aid-orchestrator/scripts/lib/aid-scope-match.sh` — the one shared predicate both callers source, so a future third consumer cannot invent a third rule.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-scope-placeholder-match.bats` — an Alembic-shaped entry admits a real migration filename and rejects a file in another directory; a literal entry behaves exactly as before; a placeholder containing `/` is refused with a named error; the hook and the FSM companion agree on every case.
- Modify: `plugins/aid-orchestrator/defaults/execution.yaml` (lines ~1-160) — add a `gate_profiles` table with the same rank order this repo uses (`quick < targeted < standard < full < release`), each profile listing gates the template actually defines, so the plan-mode default resolves to `plan_branch` for a fresh project.
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — the Plan mode section: state the coupling plainly: the release model follows from this table's presence, and declining the additive upgrade keeps a project on legacy mode.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` — a workspace composed from the shipped template resolves `__default-mode` to `plan_branch`; every profile in the template names only gates the template defines; a project whose table is removed falls back with the named reason.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~655-680) — replace the global `sed s/v$CURRENT/v$NEW_VERSION/g` over every README within three levels with an anchored roadmap edit: insert a new `- **vX.Y.Z** (current) — …` line, demote the previous current line, and keep the three most recent versions per the repository's own documented convention; every other occurrence of the old version string is left alone.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-readme.bats` — a README whose prose mentions the previous version outside the roadmap keeps that mention; the roadmap gains the new line and demotes the old; a README with no roadmap section is left untouched with a warning rather than mangled.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (lines ~885-910) — the awk block that emits acceptance criteria treats an indented continuation line as part of the preceding criterion instead of dropping it; a continuation with no preceding criterion is a loud error, not a silent skip.
- Test: `plugins/aid-orchestrator/scripts/tests/test-plan-to-epic.sh` — a wrapped criterion arrives whole in the generated EPIC; an orphan continuation fails generation naming the line; single-line criteria are unchanged.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats` — the portability scan: the detector matches any PCRE flag spelling rather than one literal string, and its self-test includes the evading forms; the per-file allowlist is re-derived from the widened scan.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh` (lines ~20-30) — the two `grep -qP` calls become POSIX equivalents; on a grep without PCRE these currently fail with an error exit, which silently means "section not disabled" — the branch never fires.
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (line ~341) — the probe primitive's own PCRE use is either converted or explicitly allowlisted with a stated reason, since it is the function introduced to make probes safe.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats` — the widened detector flags each evading spelling in a fixture and stays green over the cleared tree.
- Modify: `plugins/aid-orchestrator/scripts/aid-prefilter.sh` (lines ~155-170) — the CP3 path adopts the CP2 resolution order: the recorded base, else the step boundary, else refuse with the same `range_undetermined` exit rather than falling back to `merge-base` or `HEAD~5`; the observe-policy escape mirrors CP2's, including its loud event.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-prefilter.bats` — a CP3 invocation with no resolvable base refuses; with a recorded base it classifies exactly as today; the observe escape emits its event and warns.
- Modify: `plugins/aid-orchestrator/scripts/aid-prefilter.sh` (lines ~90-100) — the output filename is derived after the checkpoint is known and carries it, so CP2 and CP3 cannot collide; alternatively the CP3 checkpoint is refused for the classify path with a named error. The step picks one and states which in its verify output.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-prefilter.bats` — a CP3 classify run leaves an existing CP2 output byte-identical; the FSM's checkpoint assertion still rejects a wrong-checkpoint file; a CP2 run is unchanged.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~1820-1840) — `fsm_check_streamlined_integration_review` resolves the gates report through the same path the runner and every other reader use, instead of a flat sibling path the runner stopped writing.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` — a streamlined run with a real gates report passes the check; a run with no report still hard-fails with its documented message; no other reader's path changes.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~6085-6125) — `cmd_set_field` emits an `fsm_field_change` timeline event carrying field, old value, new value and caller, so "state matches events" becomes checkable.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~6890-6910) — the archival path: archiving a completed EPIC restamps its task frontmatter (`status`, `runs_completed`) instead of moving a file that still claims to be active with zero runs.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` — a set-field call appends exactly one event with both values; archival restamps the frontmatter; a legacy task file without those keys is archived unchanged rather than failing.
- Create: `plugins/aid-orchestrator/scripts/lib/aid-dogfood-guard.sh` — compares the source repository's and the dogfood target's absolute common git directory and refuses when they are equal unless a namespaced target ref or a separate clone is supplied; records the evaluated paths and the selected safe mode so the receipt shows what was checked.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` (lines ~1630-1660) — the `add-epic` subcommand on the executable path no longer accepts a lineage argument (or is removed), so the documented invariant "only epic-start and attestation establish proven lineage" becomes literally true.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-dogfood-guard.bats` — shared common dir refuses; namespaced ref or separate clone passes and records the mode; the manifest CLI can no longer mint `proven` (negative test).
- Create: `docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md` — every entry the audit verified as DONE or DEAD, moved whole with its closing evidence and an archive header stating the audit date and the tree it was verified against.
- Modify: `docs/plans/2026-06-29-BACKLOG.md` — retains only live entries (OPEN, PARTIAL and consciously parked), each with a status line and, for parked ones, the reason and the condition that would revive it; a short header states the live count and points at the archive.
- Test: `plugins/aid-orchestrator/scripts/tests/test-backlog-hygiene.sh` — every entry heading in the live file has a status line; no entry marked DONE or DEAD remains in the live file; every parked entry carries a reason; the archive is append-only relative to the previous commit.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows for the shared scope predicate, the widened portability detector, the CP3 range refusal, the prefilter collision refusal, the dogfood guard and the backlog hygiene check, each with source, instruction, severity, surface and test; totals recomputed by the file's own command.
- Modify: `docs/extending-aid.md` — a short section recording the audit's standing lesson: a guard is only as wide as its pattern, and every new detector ships with a self-test that proves it catches the evading form.
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — one identical entry per the repository format.
- Modify: `.claude-plugin/marketplace.json` + `plugins/aid-orchestrator/.claude-plugin/plugin.json` + `plugins/aid-orchestrator/README.md` + `README.md` — the remaining version-registry locations, with the roadmap updated through Step 3's new anchored edit (this release is its first live exercise).
- Test: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — full pass including the CHANGELOG byte-identity assertion.
