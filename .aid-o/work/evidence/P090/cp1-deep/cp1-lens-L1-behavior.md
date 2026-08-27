# CP1-deep L1 — behavior lens (P090)

Plan: `.aid-o/plans/P090-fronta-ktera-nezastavi.md` (7 steps, 2 EPICs, band=full)
Lens: request → branch → sink flow, undeclared outcomes, user-visible regressions, edge cases
Reviewer: controller (single-provider). The cross-provider pass is `c0-plan-review.json`,
which after five rounds returned `findings: 0`, `blocking_findings: false`.

stop_rule_blockers: []

findings:
  - id: L1-1
    severity: high
    title: two different caps on continuation, and the one that matters lives in prose
    evidence: |
      Step 3: "Strop na počet pokračování za turn drží volající (`aid-run.md`) a zapisuje ho do
      timeline" — the caller is an instruction file, so the cap is a request, not a mechanism.
      Step 6 then introduces a SECOND cap, `autonomy.max_spawned_epics`, read from configuration
      by code and persisted in `continue-state.json` as `spawned_count`.
      Nothing says how the two relate. The plan's whole argument against the P089 design was that
      a rule living in prose is a rule that gets skipped.
    why_it_matters: |
      With spawning off (the default), the only brake on a runaway queue is the prose cap — exactly
      the class this plan exists to remove. With spawning on, two caps govern one loop and the
      plan does not say which binds.
    recommendation: |
      Give `aid-plan-continue.sh` ONE cap it enforces itself, persisted where Step 4 already
      persists `spawned_count`, and let `aid-run.md` describe it rather than hold it.
  - id: L1-2
    severity: medium
    title: a spawned session reaches the same merge and spawns again — the recursion is real and its brake is thin
    evidence: |
      Step 6 spawns `claude -p "/aid-run <epic_id>"`. That session runs the EPIC and reaches
      `epic-merge-to-plan`, which by Step 3 calls the continuation IMPLICITLY in an autonomous run.
      So the spawned session spawns the next one. That is the intent — but the only brake is
      `spawned_count` in `continue-state.json`, written by whichever process ran last.
    why_it_matters: |
      Two processes that both read-modify-write that file (a job that has not exited and a new
      one) can lose a count, and a lost count means the cap silently rises.
    recommendation: |
      Say that `spawned_count` is incremented under the same lock the queue uses, and that the
      count is read AFTER the no-overlap check, not before.
  - id: L1-3
    severity: low
    title: SessionStart fires on compaction too, so the reminder can repeat inside one logical run
    evidence: |
      Step 5 adds the rule to `SessionStart` so a crashed controller is told what was pending.
      A compaction also produces a session start, and the continuity capsule (P086) rides that
      same event — so the same "unfinished plan" line can appear several times in what the PM
      experiences as one run.
    recommendation: |
      Either suppress the reminder when a live job for this plan exists (Step 6 already computes
      that), or state that repetition is accepted and why.
  - id: L1-4
    severity: low
    title: checked and NOT a problem — the ancestry proof holds because the merge is a real merge
    evidence: |
      Step 3's proof step uses `git merge-base --is-ancestor`. That would be defeated by a squash
      merge. Verified: `aid-plan-fsm.sh:3643` merges with `git merge --no-ff --no-edit`, and the
      queue's own dependency check uses the same ancestry test (`aid-queue-write.sh:847`).
    assessment: no action — recorded so the next reader does not re-open it.

confidence: high
