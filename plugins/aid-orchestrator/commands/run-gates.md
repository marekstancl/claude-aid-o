Run quality gates for an EPIC — standalone or as part of `/run-epic`. Reads `gates.yaml`, executes each gate, generates `gates_report.json`, and offers retry on failure.

## Usage

```
/run-gates <epic-id>              # Run gates for a specific EPIC
/run-gates --plan <plan.json>     # Run gates defined in a plan file
/run-gates --gates <gates.yaml>   # Run with custom gates config
/run-gates --dry-run              # Show which gates would run (no execution)
/run-gates --dry-run <epic-id>    # Dry-run for specific EPIC
```

**Examples:**
```
/run-gates TEST-0001
/run-gates --dry-run
/run-gates --gates ./custom-gates.yaml
```

## Prerequisites

- `.aid-o/` workspace must exist (run `/aid-init` first)
- Gates config at `.aid-o/03-config/policies/gates.yaml` (or custom path via `--gates`)
- For EPIC-specific runs: evidence directory should exist (from `/run-epic` or `/plan-epic`)

## Core Instruction

**Read `skills/gates-engine.md` FIRST.** It defines the complete gates execution protocol —
parsing, execution, reporting, evidence storage. This command orchestrates the user-facing
interaction around that protocol.

## What It Does

### Step 1: Resolve Configuration

```
1. FIND gates config:
   - If --gates flag → use specified path
   - Else → read .aid-o/03-config/policies/gates.yaml
   - If not found → ERROR: "Gates config not found. Run /aid-init or specify --gates."

2. FIND EPIC context (if epic-id provided):
   - Search .aid-o/02-epics/ for matching EPIC
   - Find latest run in .aid-o/04-engine/evidence/{epic_id}/
   - Load plan.json to check if it specifies a gates subset
   - If plan.json has `gates` array → run only those gates
   - If no plan.json → run ALL required gates from gates.yaml

3. DETERMINE run_id:
   - If existing EPIC run → use that run_id
   - If standalone → generate: run_{YYYYMMDD}_{4char-hash}

4. ENSURE evidence directory exists:
   - Create: .aid-o/04-engine/evidence/{epic_id}/{run_id}/gates/
   - If no epic_id → use "standalone" as epic_id
```

### Step 2: Dry-Run Mode (if `--dry-run`)

If `--dry-run` flag is set, show gates without executing:

```
AID Gates — Dry Run
====================================
Config: .aid-o/03-config/policies/gates.yaml

REQUIRED GATES:
  1. tests_pass
     Command: pytest -q --tb=short
     Timeout: 300s
     Pass: exit code 0

  2. lint_pass
     Command: ruff check . && ruff format --check .
     Timeout: 120s
     Pass: exit code 0

  3. security_scan_pass
     Command: bandit -q -r . -ll
     Timeout: 180s
     Pass: exit code 0, no HIGH or CRITICAL findings

  4. docs_updated
     Rule: docs/ or CHANGELOG.md updated if public API changed
     Pass: manual or automated check

CONDITIONAL GATES (will evaluate conditions first):
  5. type_check
     Command: npx tsc --noEmit
     Timeout: 120s
     Condition: frontend files changed

  6. build_pass
     Command: npm run build
     Timeout: 180s
     Condition: frontend files changed

Retry: max 3 attempts, fixed backoff (5s)
Escalation: inline (chat-based)
```

**After dry-run → STOP.** Do not execute gates.

### Step 3: Execute Gates

Follow `skills/gates-engine.md` Section 2 (Gate Execution Protocol) for each gate.

Display real-time progress as each gate completes:

```
Running Gates{epic_id_suffix}
====================================

[1/6] tests_pass .............. PASS (3.2s)
[2/6] lint_pass ............... FAIL (1.1s)
      → ruff: 3 violations in api/routes.py
[3/6] security_scan_pass ...... PASS (5.4s)
[4/6] docs_updated ............ PASS (0.3s)
      → No public API changes detected
[5/6] type_check .............. SKIP (condition not met)
[6/6] build_pass .............. SKIP (condition not met)

====================================
Result: FAIL (1 required gate failed, 2 skipped)
```

Where `{epic_id_suffix}` is ` for: {epic_id}` if an EPIC was specified, empty otherwise.

### Step 4: Generate Report

Follow `skills/gates-engine.md` Section 3 (Gates Report Generation).

- Write `gates_report.json` to evidence directory
- Write individual gate outputs to `gates/{gate_name}.txt`

Display report location:

```
Report: .aid-o/04-engine/evidence/{epic_id}/{run_id}/gates_report.json
Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/gates/
```

### Step 5: Handle Results

Based on `gates_report.json` overall status:

**ALL PASS:**
```
All required gates passed.

{If called from /run-epic: transition to PM_APPROVAL}
{If standalone: "Gates check complete. No action needed."}
```

**ANY REQUIRED GATE FAILED:**

Present failure summary and options:

```
Failed gates:
  - lint_pass: 3 ruff violations (api/routes.py:12, api/routes.py:28, api/models.py:5)

Options:
  A) Auto-fix + retry — dispatch gate-fixer agent to fix, then re-run
  B) Manual fix — you fix the issues, then run /run-gates again
  C) Skip and proceed — mark as skipped (not recommended for required gates)

Choice:
```

**STOP and wait for user response.**

**User Responses:**

- **A (Auto-fix):**
  1. Read `skills/retry-engine.md`
  2. Follow Failure Analysis Protocol (Section 2) for the failed gate
  3. Follow Fix Agent Dispatch Protocol (Section 3) — dispatch `gate-fixer` agent
  4. Follow Re-run Protocol (Section 4) — re-run the failed gate
  5. If fixed → re-run ALL gates (show progress again)
  6. If still failing → check retry count:
     - Retries remaining → offer options again
     - Max retries → show escalation (Section 5 of retry-engine.md)
  7. Loop until all gates pass or escalation triggered

- **B (Manual fix):**
  1. Print: "Fix the issues and run `/run-gates` again when ready."
  2. STOP.

- **C (Skip):**
  1. If gate is required → WARNING:
     ```
     WARNING: Skipping a required gate. This gate will be marked as
     skipped_by_pm in the report. Proceed? (Y/N)
     ```
  2. If confirmed → update gates_report.json:
     - gate status → "skipped_by_pm"
     - Recalculate overall
  3. If other gates still failing → continue with next failure
  4. If all resolved → print final status

### Step 6: Final Summary

After all gates resolved:

```
Gates Summary
====================================
  tests_pass .............. PASS
  lint_pass ............... PASS (fixed on attempt 2)
  security_scan_pass ...... PASS
  docs_updated ............ PASS
  type_check .............. SKIP
  build_pass .............. SKIP

Overall: PASS
Retries: 1 (lint_pass: 2 attempts)
Report: .aid-o/04-engine/evidence/{epic_id}/{run_id}/gates_report.json

{If called from /run-epic: "Proceeding to PM Approval..."}
{If standalone: "All gates passed. Ready for next step."}
```

## Non-Interactive Mode

When called internally by `/run-epic` (GATES state), run in non-interactive mode:

- Do NOT present options to user
- Follow `gates-engine.md` decision logic automatically:
  - All pass → return "proceed_to_pm_approval"
  - Fail + retries → auto-dispatch gate-fixer (per `retry-engine.md`)
  - Fail + max retries → return "escalation" (let run-epic handle PM interaction)
- Still generate full evidence and gates_report.json

## Reference Files

- **PRIMARY:** `skills/gates-engine.md` — execution protocol, report format, evidence
- **RETRY:** `skills/retry-engine.md` — failure analysis, fix dispatch, escalation
- **AGENT:** `agents/gate-fixer.md` — fix agent definition
- `defaults/policies/gates.yaml` — gate definitions
- `defaults/policies/decision-policies.yaml` — auto-decision rules

## Important

- **Read `skills/gates-engine.md` BEFORE executing** — it is the authoritative protocol
- **Evidence is mandatory** — every gate run produces files in `gates/`
- **Never skip required gates silently** — always ask for explicit user confirmation
- In non-interactive mode (from `/run-epic`): follow auto-decision rules, escalate only when needed
- If `$ARGUMENTS` is empty → run all gates from default gates.yaml (standalone mode)
- If a gate command is not found (tool not installed) → status: "error", show install instructions
