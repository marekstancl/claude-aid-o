# C0 Lens: Idempotency Matrix

lens: idempotency_matrix
epic_id: E-C0-LENS-IDEM-1_1
created_at: 2026-06-28T00:00:00Z

## Findings

Two operations lack idempotency guarantees.

stop_rule_blockers:
  - Database migration step is not idempotent (no IF NOT EXISTS guards)
  - Config file write has no atomic replacement (no tmp+rename pattern)

## Notes

Both blockers must be resolved before the implementation steps are dispatched.
