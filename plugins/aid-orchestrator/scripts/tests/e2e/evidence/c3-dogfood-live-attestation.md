# C3 Dogfood — Live Attestation (P065 Step 13)

This file is the committed PROVENANCE PROOF that the C3 cross-provider dispatch
bridge (`aid-c3-dispatch.sh`) was run once, for real, against the real Codex
CLI, and that `aid-c3-dispatch.sh verify` (live mode) accepted the result at
run time. The raw evidence directory itself is deliberately NOT committed (it
may contain local filesystem paths or session detail) — this attestation is
the sanitized record of that run.

The regression fixture committed alongside this file
(`c3-dogfood-fixture/`) is a SEPARATE, sanitized, re-hashed copy of the same
run's evidence. It proves the bridge's `verify` logic is internally
self-consistent going forward — it is NOT itself external provenance (sanitizing
changes raw bytes, and therefore hashes). This file is the provenance claim;
the fixture is the regression check.

| Field | Value |
|---|---|
| codex_version | `codex-cli 0.144.4` |
| codex_session_id (prefix only) | `019f69a4...` |
| achieved_independence_level | `cross_provider` |
| run_at (UTC) | `2026-07-16T06:38:20Z` |
| live_verify | passed |
| audit-report.json validator | passed |
| working tree after run | unchanged |

live_verify: passed
