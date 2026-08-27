# C0 lens — authority_runtime_matrix (P090)

Focus: mutations crossing ownership or privilege boundaries without explicit authorization.
Observe-only in E4.

stop_rule_blockers: []

findings:
  - id: AR-1
    severity: high
    boundary: "a process that starts another autonomous process"
    finding: |
      Step 6 lets an automated run start a NEW Claude session with the user's credentials, which
      may in turn start another. That is a privilege-shaped decision — spend, and unattended
      action — not merely a scheduling one. The plan's controls are: default off, a configured cap,
      a no-overlap check, and a deadline.
    assessment: |
      Proportionate, and the plan states the reason for opt-in explicitly. Two things are missing
      from the AUTHORITY side rather than the mechanism side:
        1. nothing records WHO enabled it and when — the config key is a silent switch;
        2. nothing bounds the total across plans: the cap is per plan, so two plans with the
           feature on can spawn independently.
    recommendation: |
      Log the spawn decision (plan, EPIC, job id, count, deadline) to the plan timeline AND state
      whether the cap is per plan or per workspace. If per plan, say so — it is a defensible
      choice, but it should be a choice.
  - id: AR-2
    severity: medium
    boundary: "one workspace's rule reading another run's records"
    finding: |
      Step 5 scans ALL active-run records in the workspace and fires when any shows
      `auto_controller: active`. The plan added an isolation criterion (AC14) so a manual turn is
      not blocked by someone else's autonomous run — but the rule still READS records it does not
      own, and the plan does not say what it does when two autonomous plans are active.
    recommendation: |
      State it: report both (the reminder is degree 3 and cannot block), naming each plan — that is
      the honest behaviour and it is testable.
  - id: AR-3
    severity: low
    boundary: "queue file, written by a program the merge path invokes"
    finding: |
      The queue is a derived view whose writer authority the plan deliberately keeps outside
      `epic-merge-to-plan`. The new program is the writer and it proves the merge before writing.
      No boundary is crossed that the repository did not already sanction.
    assessment: no action.

confidence: medium
