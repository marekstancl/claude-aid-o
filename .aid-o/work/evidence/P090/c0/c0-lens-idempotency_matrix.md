# C0 lens — idempotency_matrix (P090)

Focus: non-idempotent mutations against at-most-once criteria.
Observe-only in E4.

stop_rule_blockers: []

findings:
  - id: IM-1
    severity: high
    mutation: "spawning a session (Step 6)"
    finding: |
      This is the plan's one genuinely at-most-once mutation: a spawned session costs money and
      does work. The guard is a pre-check that no job is running for this plan plus a persistent
      `spawned_count`. Both live in `continue-state.json`, and the plan does not say the
      check-and-increment happens under a lock. Two continuations racing (a supervisor-launched
      session that has not yet exited, and a fresh manual invocation) can both observe "no live
      job" and both spawn.
    recommendation: |
      Do check-and-increment under the SAME lock the queue uses (`aid_lock_acquire` on the queue
      lock path), and make the no-overlap check `aid-job.sh status <job_id>` on the recorded id
      rather than an inference from the file.
  - id: IM-2
    severity: medium
    mutation: "queue set-status merged_to_plan (Step 3)"
    finding: |
      Declared idempotent ("druhé spuštění … zrcadlení přeskočí") and it now has a proof step in
      front of it, so a repeat is safe. What the plan does not name is the SIGNAL it keys on —
      presumably the entry already being `merged_to_plan`. Unnamed, an implementer may key on the
      artifact hint instead, which is explicitly "vodítko, ne autorita".
    recommendation: name the signal (the queue entry's own status).
  - id: IM-3
    severity: medium
    mutation: "claim-next (Step 3, step 3)"
    finding: |
      Claiming is inherently once-only: it writes `running` and `started_at`. The plan handles the
      failure after a successful claim by reconciling back to `pending` — good. But if the process
      DIES between claim and reconciliation, the entry stays `running` with no live run, and the
      plan's own rule says `peek` never returns such an entry.
    consequence: the plan can wedge itself: nothing reclaims it, and `peek` reports `none`.
    recommendation: |
      Say who clears a stale `running`: the plan already reports it to a human (Step 4, AC12), so
      state that this is deliberate and manual — or give `aid-plan-continue.sh` a documented
      `--reclaim` that a human runs. Silence here is what turns an edge case into a stuck plan.
  - id: IM-4
    severity: low
    mutation: "continue-state.json write (Step 4)"
    finding: written atomically (temp + rename) and last-write-wins is stated. Adequate.
    assessment: no action.

confidence: high
