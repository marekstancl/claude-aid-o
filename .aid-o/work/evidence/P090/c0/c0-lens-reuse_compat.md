# C0 lens — reuse_compat (P090)

Focus: does planned reuse break the reused component's contract or invariants?
Observe-only in E4.

stop_rule_blockers: []

findings:
  - id: RC-1
    severity: medium
    component: "queue_claim_next (lib/aid-queue-write.sh)"
    finding: |
      Step 1 pulls the selection logic out of `queue_claim_next` into a shared inner function so
      `queue_peek_next` can use it. The plan promises `claim` stays unchanged from the outside
      ("`claim` zůstane beze změny navenek"), which is the right invariant — but the extraction
      touches a function whose header documents lock discipline in detail: the loop deliberately
      uses `$(...)` command substitution rather than process substitution, because a subshell
      inheriting a duplicate of the lock fd would hold the flock past `aid_lock_release`
      (recorded as CP2 finding 5 in that file's comments).
    why_it_matters: |
      A refactor that moves that loop into a helper can reintroduce exactly the bug the comment
      documents — and the symptom is a lock held too long, which no unit test of `peek` would show.
    recommendation: |
      Step 1 should say that the extracted helper keeps the command-substitution form, and the
      suite should assert the lock is released after `peek` (a second `peek` in the same test).
  - id: RC-2
    severity: low
    component: "epic-merge-to-plan (aid-plan-fsm.sh)"
    finding: |
      Step 3 adds an implicit call after a successful merge. The file's own header (`:89-92`)
      states that neither `epic-start` nor `epic-merge-to-plan` performs a queue write; the plan
      keeps that literally true (the write happens in the separate program) but the SPIRIT of the
      note — that merge and queue are decoupled — is now weaker, because merge triggers the writer.
    assessment: |
      Judged acceptable and the plan argues it explicitly: the invariant protected there is the
      absence of a producer/consumer CYCLE, and a one-way call out to a separate program does not
      create one. Recorded so the next reader of that header knows it was considered.
    recommendation: update the header note in Step 3 so it describes the new arrangement.
  - id: RC-3
    severity: low
    component: "aid-job.sh (IMP-262)"
    finding: |
      Step 6 reuses the job supervisor for a new KIND of command (an interactive-model session
      rather than a gate command). The supervisor's design invariants say completion is read from
      the owned process and its exit status, never from log growth — which holds for `claude -p`
      as well. Its `--deadline` becomes a session timeout, a meaning the supervisor never had.
    recommendation: |
      Say in Step 6 that a deadline hit is a normal terminal result for a spawned session, not an
      error, so `collect` reporting a timeout does not read as a failure of the plan.

confidence: medium
