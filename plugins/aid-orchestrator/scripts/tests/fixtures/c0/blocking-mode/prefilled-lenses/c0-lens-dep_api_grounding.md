# C0 Lens: Dependency API Grounding

lens: dep_api_grounding
epic_id: E-C0-P045-1_1
created_at: 2026-06-28T00:00:00Z

## Findings

One dependency API is ungrounded in the plan.

stop_rule_blockers:
  - step_2 references service_a.get_status() which has no contract defined

## Notes

Contract must be specified before implementation proceeds.
