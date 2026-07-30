---
name: aid-audit-tests
description: Test portfolio audit — inventory, safe measurement, and a plain-language recommendation
user_invocable: true
---

# `/aid-audit-tests` — Test Portfolio Audit

Deterministically inventories a project's test portfolio (Bats, package-script/CI,
and declared-gate run_units), optionally measures a bounded subset of it safely,
and ends every run with a mandatory plain-language chat recommendation.

**`STATIC MODE NEVER EXECUTES TESTS`** — `static` mode is discovery-only: static
`@test`/script/gate parsing, never a `bash -c`/test-runner invocation of any kind.

## What this command never does on its own

- Never edits, deletes, renames, or quarantines any test file.
- Never changes `execution.yaml`/gate/quarantine state.
- Never schedules or batches test execution (no scheduler exists in this plan —
  see P069, a separate, dependent follow-up).
- Never modifies `aid-select-tests.sh`.
- **Never auto-invokes itself** — this command runs only when a user (or the
  controller, on an explicit user request) types `/aid-audit-tests`. It is never
  dispatched after an EPIC, a plan, or a release, and it carries no FSM/gate/CI
  wiring of any kind (enforced: `test_audit_never_auto_invoked`,
  `defaults/enforcement-registry.yaml`).

## Invocation

```
/aid-audit-tests [repo|path:<path>|runner:<id>] [--mode static|measure|full]
                  [--budget-minutes N] [--max-agents N] [--repeat N]
                  [--write-plan] [--resume <audit-id>]
```

| Argument | Meaning |
|---|---|
| `repo` (default) | Scope: the whole project root. |
| `path:<path>` | Scope: a subdirectory only. |
| `runner:<id>` | Scope: one discovered runner family only (e.g. `runner:bats`). |
| `--mode static\|measure\|full` | `static` (default): discovery + static analysis only. `measure`: adds bounded, sequential command execution against the approved-catalog-only allowlist. `full`: adds a deeper flake/order/isolation probe. |
| `--budget-minutes N` | Wall-clock budget for `measure`/`full`. **Required for `--mode full`** — hard error, not a default. |
| `--max-agents N` | Ceiling on concurrent read-only audit agents (independent of `dispatch.max_parallel`). |
| `--repeat N` | Repeat a measured command N times (flake-probing use). |
| `--write-plan` | Non-interactive equivalent of the natural-language "vytvoř plán oprav" continuation (see below) — for CI/scripted use. |
| `--resume <audit-id>` | Resume an interrupted audit; short-circuits to the resumable state machine before any new scan. |

The command file documents this contract; it performs no validation itself. The
controller invokes the real, deterministic parser
(`scripts/aid-audit-tests-cli-parse.sh`) first — every malformed input (unknown
option, nonexistent project root, nonexistent scope, missing `--budget-minutes`
for `full`, `--max-agents 0`, an unrecognized `runner:<id>`) fails loudly with a
distinct exit code, never silently defaulted. The parser's JSON output includes
the resolved, canonical `project_root` — **every later step in this command
(the scanner, the dispatch manifest, the measurement runner) MUST use this
exact value**, never re-resolve or re-derive their own; this is what makes the
parser's own project-root validation load-bearing rather than advisory.

## What it does

1. Parse and validate arguments (`aid-audit-tests-cli-parse.sh`).
2. Run the Wave-0 scanner (`aid-test-inventory.sh`) to resolve `scope` and produce
   the gitignored `test-catalog.proposed.yaml` — zero LLM dispatch.
3. Dispatch bounded, read-only shard/specialist waves via the
   `test-portfolio-analyst` agent card — one dispatch per manifest entry the
   controller reads from `aid-test-audit-dispatch.sh`'s output (`{max_concurrent_
   agents, entries: [...]}`; at most `max_concurrent_agents` entries live at once
   per `batch` within a wave), writing each result to the entry's
   `artifact_path`. This command's own `audit-state.json` is the complete
   dispatch-progress record.
4. In `measure`/`full` mode, run allowlisted commands sequentially via
   `aid-job.sh` (never batched, never a second process supervisor) —
   `aid-test-audit-measure.sh` checks every command against
   `aid_test_audit_check_allowed` (Step 13) before it ever reaches `aid-job.sh`.
5. Consolidate all wave artifacts deterministically
   (`aid-test-audit-consolidate.sh`) and render the mandatory 5-part chat
   recommendation (`aid-test-audit-chat-summary.sh`) as this command's own
   final turn — the controller calls the renderer and presents its output
   directly in chat; the renderer's text is ordinary, deterministic, fully
   Bats-tested code, but the controller's act of presenting it as the
   session's actual final turn is a live, session-level behavior verified
   once at release (Step 24 Part B), never claimed as covered by that
   script's own test suite.

## Chat handoff (natural-language continuation)

Every completed audit's final turn always contains: (1) a verdict
(`clean`/`needs measurement`/`remediation recommended`), (2) up to 5 evidenced
reasons — one per top finding, never fabricated/padded to reach a minimum
count (a sparse audit with 1 real finding gets exactly 1 real reason), (3) what
changed (nothing, unless a separately-approved step ran), (4) one
plain-language next action, (5) residual risk / PM-decision-needed.

**Same-conversation convention, never a global interceptor.** Immediately
following that turn, in the SAME conversation, a reply like "pokračuj" or "vytvoř
plán oprav" is recognized as authorizing the controller to invoke `/aid-plan write`
for that one audit's durable record (`audit_id`, `verdict`, `recommended_action`).
Outside that specific context — a different conversation, the same conversation
long after the recommendation, or an ambiguous reply — the controller asks for
clarification rather than guessing. This mechanism never fires from anywhere
outside an active `/aid-audit-tests` conversation, and it enforces nothing at any
FSM/gate/release boundary.

**Controller-side contract.** `/aid-plan write` is a skill the LLM controller
invokes directly (not a subprocess a shell script can call). Both `--write-plan`
(CI/scripted use — never required end-user knowledge) and a recognized
same-conversation continuation reply resolve to the **identical** validator
call: `aid-test-audit-write-plan-bridge.sh`'s `aid_test_audit_write_plan_bridge_check`.
The controller (a) runs this validator, and (b) on a `{ready:true}` verdict,
invokes `/aid-plan write` itself with the validator's `brief_path` as input. The
validator itself **never invokes `/aid-plan write`** — it only checks: the
durable record exists and its verdict is `remediation recommended`;
`consolidated-findings.json`/`implementation-plan-brief.{json,md}` exist, are
schema-valid, and the brief was derived from the current findings file (not a
stale one); every cited `run_unit_id` still resolves in the current catalog. A
`clean`/`needs measurement` verdict, or a stale `run_unit_id`, returns
`{ready:false, reason:...}` and blocks the handoff — verified to block it, not
merely asserted to.

## Parallel-safety findings

`safe|constrained|exclusive|unknown` is a descriptive audit finding only — this
plan ships no scheduler that consumes it (see P069, `depends_on_plans: [P066]`,
for the dependent scheduler work). `unknown` is the default absent direct, cited
adapter evidence; this command never promotes a test to `safe` optimistically.

## Reads / Writes

- Reads: the target project's real `execution.yaml`/`gate_profiles`, the tracked
  `.aid-o/config/test-catalog.yaml` (if approved), `.aid-o/config/test-audit.yaml`.
- Writes: `.aid-o/work/test-audits/<audit-id>/` (gitignored, evidence-only) —
  `inventory.json`, `test-catalog.proposed.yaml`, `audit-state.json`, per-wave
  agent artifacts, `consolidated-findings.json`, `implementation-plan-brief.{md,json}`.
- Never writes to `.aid-o/config/test-catalog.yaml` directly — that is the
  separate, explicit catalog-approval step's job.

**Last Updated:** 2026-07-30
