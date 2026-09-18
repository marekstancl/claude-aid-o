# Recorded reviewer answers — where they come from

Produced by the live acceptance run of P093 Step 12 on 2026-09-18, and replayed
by `scripts/tests/test-plan-review-acceptance.sh` without any model call.

- Plan: `../acta-p025.md` — ACTA `.aid-o/plans/P025-katalog-druhu-rady-typ-dd-export.md`
  at ACTA commit 9b68f91c98a0, id P998, reviewed in a clone of ACTA at that
  commit (ACTA itself was not modified).
- Round 1: six reviewers, all `claude`/`opus` (Codex was over its usage limit
  until 2026-09-21, so `generalist_b` ran on the same model: `degraded: true`).
  Answers: `round-1/reviewer-*.json`; the Agent tool's `subagent_tokens` per
  reviewer: `round-1/tokens.json`.
- The author's fix after round 1: `plan-round-2.md` (the packet of round 2).
- Round 2: the confirmation round asked four reviewers; `round-2/`.
- The author's last edit (fixes plus the acceptance criterion quoting the open
  blocker), snapshotted by `finalize`: `plan-final.md`.

The evidence paths the answers cite exist in ACTA at that commit, so a replay
needs that checkout; the suite clones it and skips, saying so, when ACTA is not
on the host.
