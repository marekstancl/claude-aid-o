# C3 Cross-Provider Audit Report

| Field | Value |
|---|---|
| status | `unverifiable` |
| blocking_findings | `false` |
| review_status | `unverifiable` |
| outcome | `review_unverifiable` |
| provider | `codex` |
| model | `gpt-5.6-terra` |
| independence | `cross_provider` |
| reviewed_head | `30b4f6c2f83114d30678a7d368b9b08912d65cb7` |
| findings | 0 |

**Unverifiable** — no trusted pass/fail was produced (outcome: `review_unverifiable`).

### Reasons

- The explicit allowed-command list is empty, so I could not re-derive the commit-range diff, verify manifest hashes, inspect committed gate artifacts, or produce the required lifecycle state matrix from evidence.

