# Verifier output step 3

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T18:49:50Z
classification: FULL_REVIEW
verdict: pass
checkpoint: cp2
reason: Both guards were proven to fail as well as pass, the allowlist carries reasons rather than silence, and the one hit that could not be fixed in scope is recorded as a known temporary red instead of being allowlisted away.

## The temptation this step had to resist

A denylist check over documentation has an obvious cheat: when it fires,
allowlist the hit and move on. That converts a real finding into permanent
silence and leaves the check looking like coverage. The sweep found one genuine
unqualified instruction (pipeline.md's DONE-summary MERGE option). It was NOT
allowlisted. The fix is a mode fork, and because pipeline.md belongs to step 3's
allowed_paths rather than this step's, the fix is held back for the integration
boundary and the resulting temporary red is stated in the commit message.

Every allowlist entry that does exist carries a reason: pipeline.md and
aid-run.md document both modes side by side, the CHANGELOG is history rather
than instruction, and the enforcement registry necessarily describes superseded
rows.

## Verified by execution

- Denylist: a fixture containing "The per-EPIC release is what happens" fails
  with file, line and pattern (exit 1); the same sentence prefixed with its mode
  passes (exit 0).
- Completeness: every command, skill and agent file carries a disposition.
- The qualification window is 15 lines either side, so a legacy passage stays
  documentable as long as it says which world it belongs to.
- Headings carry no version stamp — the linter rejects those, and the first
  attempt failed on exactly that (`## Plan-boundary note (P068)`).

## Scope discipline

The commit-scope hook refused pipeline.md and the refusal was accepted rather
than bypassed. No `--no-verify`, no allowlist workaround.

## Tests

test-skill-lint.sh 5/5; test-control-boundary.sh OK; test-instruction-sweep.sh
OK in the working tree, with the one known-red line documented.
