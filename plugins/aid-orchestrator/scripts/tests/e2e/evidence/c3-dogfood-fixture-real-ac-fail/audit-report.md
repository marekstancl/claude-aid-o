# C3 Cross-Provider Audit Report

| Field | Value |
|---|---|
| status | `fail` |
| blocking_findings | `true` |
| review_status | `findings` |
| outcome | `dispatched` |
| provider | `codex` |
| model | `gpt-5.6-terra` |
| independence | `cross_provider` |
| reviewed_head | `88f26978c56ada592cf14bbd2638dff85e0fd063` |
| findings | 4 |

## Findings

### [high] acceptance behavior

- **finding:** Allow-listed `scripts/e2e-ac-demo/increment.sh` computes `$1 + 2`, not the required input integer plus exactly 1.
- **recommendation:** Change the arithmetic to add exactly 1 and provide evidence that exercises the required behavior.
- **action_owner:** implementer
- **occurrence_id:** `c3-E-c3-dogfood-real-ac-0`

### [medium] acceptance documentation

- **finding:** Allow-listed `scripts/e2e-ac-demo/increment.sh` has no one-line explanatory comment directly above `increment_by_one`.
- **recommendation:** Add the required one-line comment immediately above the function definition.
- **action_owner:** implementer
- **occurrence_id:** `c3-E-c3-dogfood-real-ac-1`

### [high] gate evidence

- **finding:** Repository inspection found no committed gate artifact for this run that binds a PASS to the reviewed HEAD with a recorded exit code and command fingerprint; the empty recheck allow-list prevents rerunning a gate.
- **recommendation:** Provide a committed, HEAD-bound gate artifact containing the exact command fingerprint and successful exit code, then re-audit after correcting the implementation.
- **action_owner:** gate-fixer
- **occurrence_id:** `c3-E-c3-dogfood-real-ac-2`

### [info] lifecycle state matrix

- **finding:** No stateful mechanism is in scope: `increment_by_one` is stateless arithmetic, so no state-by-event transitions or inverse-edge tests apply.
- **recommendation:** No lifecycle action is required.
- **occurrence_id:** `c3-E-c3-dogfood-real-ac-3`


