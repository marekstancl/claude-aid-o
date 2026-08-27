# C0 lens — planned_call_feasibility (P090)

Focus: does a step call an output another step does not clearly produce?
Observe-only in E4.

stop_rule_blockers: []

findings:
  - id: PF-1
    severity: medium
    finding: |
      Step 6 requires two things at runtime: "neběží jiný job pro tenhle plán" and a persistent
      spawn cap. Both are read from `continue-state.json`, whose fields (`job_id`, `jobs_dir`,
      `job_fingerprint`, `spawned_count`) are defined by Step 4. Step 6's Dependencies now name
      Step 4, so the ordering is right — but Step 6's own prose never names the fields it consumes,
      so a reviewer of Step 6 alone cannot check the producer emits them.
    recommendation: name the four fields in Step 6, with Step 4 as their source.
  - id: PF-2
    severity: medium
    finding: |
      Step 5's `SessionStart` branch reports "vodítko z Kroku 4 i to, co je na řadě" (AC13b). The
      hint is `continue-state.json`, produced by Step 4 — but Step 5 declares
      `Depends on: Step 1` only. Step 5 can therefore be implemented before its input exists.
    recommendation: |
      Either add Step 4 to Step 5's dependencies, or state that a missing hint is the ordinary
      case and the SessionStart branch degrades to "here is what the queue says" — which is what
      Step 5's error handling already implies.
  - id: PF-3
    severity: low
    finding: |
      Step 3 step 2 calls `aid-plan-fsm.sh next-epic`, produced by Step 2 — declared, ordered and
      consistent. Step 3 step 4 calls `epic-start`, which exists today. No gap.
    assessment: no action.
  - id: PF-4
    severity: low
    finding: |
      Step 7's registry rows are said to cover "three layers" (query, loop, reminder). The plan now
      has FOUR mechanisms after Step 6 was added: query, loop, spawn, reminder. AC16 still says
      three.
    recommendation: make it four, or say why spawn shares a row with the loop.

confidence: high
