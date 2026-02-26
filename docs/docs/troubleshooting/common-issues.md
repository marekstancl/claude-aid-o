---
sidebar_position: 1
title: "Common Issues"
description: "Symptoms, causes, and solutions for the most frequently encountered problems when running AID Orchestrator."
---

# Common Issues

This page documents the most common problems encountered when using AID Orchestrator,
with the exact symptoms to look for, the root cause, and step-by-step resolution
instructions. If your issue is not listed here, check the [FAQ](./faq) or run
`/aid-audit` for a project health report.

---

## 1. Gate Failure: `type_check` (TypeScript)

**Symptom**

The GATES state reports a `type_check` failure. The error log contains TypeScript
compiler output such as:

```text
src/api/users.ts(42,7): error TS2345: Argument of type 'string | undefined'
is not assignable to parameter of type 'string'.
```

**Cause**

The `type_check` gate runs `npx tsc --noEmit` against the entire project. A type
error introduced (or exposed) by an agent step fails this gate. The gate-fixer agent
attempts a fix automatically, but type errors caused by incorrect interface usage or
missing type narrowing may require manual correction.

**Solution**

1. Read the full compiler output in `.aid-o/04-engine/evidence/{epic_id}/{run_id}/gates_report.json`
   — the `attempts` array contains the raw `tsc` output for each retry attempt.
2. If the gate-fixer attempted a fix but the error persists, respond to the PM escalation
   with option A (Fix) and include the specific narrowing or assertion you want applied.
3. If TypeScript checking is not relevant to your project (for example, you are
   working on a Python-only codebase that includes JavaScript tooling), set
   `required: false` on the `type_check` gate in `.aid-o/03-config/policies/gates.yaml`:

```yaml
type_check:
  required: false
  when: "frontend files changed"
```

---

## 2. Gate Failure: `lint_pass`

**Symptom**

The GATES state reports a `lint_pass` failure. The log shows output from your
linter such as:

```text
src/api/users.py:12:1: F401 'os' imported but unused
src/api/users.py:34:80: E501 line too long (92 > 88 characters)
```

**Cause**

An agent introduced code that violates the project's linting or formatting rules.
The retry engine categorizes lint failures by rule prefix: `F4xx` (unused imports),
`E1xx–E5xx` (style), `S` (security), `C9xx` (complexity). Auto-fixable violations
(style, unused imports) are retried automatically with `ruff check --fix` or
equivalent. Security and complexity violations require a targeted fix.

**Solution**

1. Auto-fixable violations (the majority): the gate-fixer agent handles these
   automatically within the 3-attempt retry budget. No action needed unless all
   retries are exhausted.
2. If retries are exhausted, check `gates_report.json` to see which rules failed
   after all attempts. Respond to the PM escalation with specific guidance (for
   example, "remove the unused import and shorten line 34 by extracting to a variable").
3. If your linting configuration is stricter than intended, update the linter config
   file in your project (e.g., `pyproject.toml`, `.eslintrc`) and re-run the gate.

---

## 3. Gate Failure: `tests_pass`

**Symptom**

The GATES state reports a `tests_pass` failure. The log shows test output such as:

```text
FAILED tests/test_users.py::test_pagination_empty_result - AssertionError
1 failed, 47 passed in 3.42s
```

**Cause**

An agent's implementation introduced a regression, or a QA agent wrote a test
that does not match the implementation. The retry engine parses the pytest or Jest
output to extract the failing test name, error type, and affected files. The
gate-fixer agent attempts to fix the implementation within allowed paths.

**Solution**

1. Check `gates_report.json` for the parsed failure details. Look at the `attempts`
   array to see what the gate-fixer tried.
2. If the failing test is in the agent's `allowed_paths`, the gate-fixer can fix
   the implementation. Respond to the escalation with option A (Fix) and include
   the expected behavior.
3. If the failing test is a pre-existing failure unrelated to the EPIC, respond
   with option B (Skip) to proceed — and file a separate task to fix it.
4. If tests are consistently flaky (timeouts, environment issues), increase the
   timeout in `gates.yaml`:

```yaml
tests_pass:
  timeout_seconds: 600
```

---

## 4. Gate Failure: `build_pass`

**Symptom**

The GATES state reports a `build_pass` failure. A build error like the following appears:

```text
> npm run build
ERROR in ./src/components/UserTable.tsx
Module not found: Error: Can't resolve './PaginationControls'
```

**Cause**

An agent created a file reference (import, require, or module path) that does not
resolve to an existing file. This is a common outcome when parallel agents work on
different modules and one references a file the other was supposed to create.

**Solution**

1. Check which file the module resolution is looking for and verify whether it exists.
2. If the missing file is within the EPIC's scope, respond to the escalation with
   option A (Fix) and specify that the gate-fixer should create the missing module
   with the correct exports.
3. If the build gate is not relevant to your project (e.g., you have no build step),
   set `required: false` in `gates.yaml`.

---

## 5. Gate Failure: `security_scan_pass`

**Symptom**

The GATES state reports a `security_scan_pass` failure. The security scanner output shows:

```text
>> Issue: [B105:hardcoded_password_string] Possible hardcoded password.
   Severity: Medium   Confidence: Medium
   Location: src/config/db.py:12
```

**Cause**

The security gate runs a static analyzer (bandit for Python, eslint-plugin-security
for Node.js) and fails on findings above the configured severity threshold. Common
causes: hardcoded credentials, SQL string formatting instead of parameterized queries,
or use of `eval()` / `exec()`.

**Solution**

1. Read the finding details in `gates_report.json`. The retry engine classifies
   findings by type and recommends a fix approach.
2. Hardcoded credentials: move to environment variables (`os.environ.get("DB_PASSWORD")`).
3. SQL injection patterns: switch to parameterized queries or an ORM.
4. If a finding is a false positive (for example, a test fixture with a dummy password
   string), add a `# nosec` comment to suppress it, or configure an exception in
   your security tool's configuration file.
5. CRITICAL findings trigger immediate escalation (trigger E2) — they are never
   auto-fixed. You must review and resolve them manually.

---

## 6. Permission Errors During FIRST AID (`/aid-first-aid`)

**Symptom**

`/aid-first-aid` starts but immediately fails or refuses to execute with an error
such as:

```text
Error: Cannot read settings.json — file is not valid JSON
```

or agents are blocked mid-run with "permission denied" when attempting to write files.

**Cause**

The permission sandwich requires `.claude/settings.json` to be valid JSON before
it can back up and elevate permissions. A corrupted or manually edited `settings.json`
prevents the startup sequence from completing. Separately, if `permissions-auto.yaml`
does not include the Bash commands your gates need, agents will be blocked when
those commands are denied at runtime.

**Solution**

1. **Invalid settings.json**: validate the file with `cat ~/.claude/settings.json | python3 -m json.tool`.
   Fix any JSON syntax errors (trailing commas, missing quotes) and retry.
2. **Missing permissions**: run `/aid-first-aid --dry-run` to preview which permissions
   will be applied without executing. Add any missing command patterns to
   `.aid-o/03-config/policies/permissions-auto.yaml`:

```yaml
allow:
  - "Bash(cargo test:*)"      # Rust projects
  - "Bash(npx vitest run:*)"  # Vitest projects
```

3. **Leftover backup file**: if `permissions-backup.json` exists from a previous crashed
   session, `/aid-first-aid` will attempt crash recovery. Run `/aid-first-aid --resume`
   to restore permissions and resume from the last safe state.

---

## 7. EPIC Stuck in a State

**Symptom**

The orchestration pipeline is not advancing. `/aid-epic-status` shows the same
state repeatedly, or the Controller has stopped responding without an escalation.

**Cause**

The most common causes are: a long-running agent that has not produced output yet;
a gate command that is taking longer than its configured `timeout_seconds`; or a
session context reset that interrupted the Controller mid-state.

**Solution**

1. Check `stage_log.jsonl` in the evidence directory to see the last recorded state
   transition:

```bash
tail -5 .aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl
```

2. If the last entry is `EXECUTING` and no new entries have been written, the
   dispatched agent may be processing a slow step. Allow more time before intervening.
3. If the session was reset, re-run the same command (`/aid-run-epic {epic_id}`).
   The Controller reads `plan_progress.json` and resumes from the last completed step.
4. If `plan_progress.json` is corrupted, the Controller rebuilds state from
   `stage_log.jsonl` automatically.
5. In FIRST AID mode, use `/aid-stop` to safely disengage autonomous execution,
   then `/aid-first-aid --resume` to restart from the saved session state.

---

## 8. Queue Paused After EPIC Failure

**Symptom**

After an EPIC fails, `/aid-epic-queue list` shows `paused: true` and no further
EPICs are being picked up automatically.

**Cause**

This is the intended safety behavior. When an EPIC transitions to `failed` status,
the queue automatically sets `paused: true` to prevent the next EPIC from starting
with potentially corrupted state. The queue will not auto-advance until explicitly
resumed.

**Solution**

1. Investigate the failed EPIC by reviewing its `final_report.md` and `stage_log.jsonl`
   in the evidence directory.
2. Decide whether to re-queue the failed EPIC or skip it.
3. Resume the queue:

```text
/aid-epic-queue resume
```

4. To re-run the failed EPIC first:

```text
/aid-run-epic {epic_id}
```

Then resume the queue after it completes successfully.

5. To change the paused status without fixing the failed EPIC (proceed at your own risk):

```yaml
# .aid-o/04-engine/epic-queue.yaml
paused: false
```

---

## 9. Qdrant / Memory Connection Failures

**Symptom**

During agent dispatch or at run-end, an error appears such as:

```text
Warning: Qdrant memory operation failed — qdrant-store returned error
Continuing without memory indexing.
```

or the `pre_step_search` memory context is empty despite having completed EPICs.

**Cause**

The Qdrant MCP server is not running, not reachable, or was not configured. AID's
memory system is entirely optional — failures are non-blocking by design. The plugin
falls back to file-based memory (`lessons-learned.md`, `active-work.md`) and continues.

**Solution**

1. Verify that `memory.enabled` is `true` in `.aid-o/03-config/policies/memory-config.yaml`.
   If it is `false`, Qdrant is intentionally disabled.
2. Confirm the Qdrant MCP server is running and accessible. The data directory is
   `~/.local/share/aid-orchestrator/qdrant-data` by default.
3. Check your MCP configuration in `~/.claude/claude_desktop_config.json` to confirm
   the Qdrant server entry is correct.
4. Run `/aid-setup` and choose option 6a (Qdrant MCP) to re-run the guided setup.
5. If Qdrant is not needed, confirm `enabled: false` in `memory-config.yaml` to
   suppress warning messages.

---

## 10. Broken Pipe During Long Runs

**Symptom**

A long-running agent step or gate command exits unexpectedly with a broken pipe error:

```text
BrokenPipeError: [Errno 32] Broken pipe
```

or the agent output is truncated and the step is marked as incomplete.

**Cause**

Long-running shell commands (tests that take several minutes, large build operations)
can exceed the session's context or shell timeout. This is most common with test
suites that run for more than 5 minutes or build steps that produce very large output.

**Solution**

1. Increase the `timeout_seconds` for the affected gate in `gates.yaml`:

```yaml
tests_pass:
  timeout_seconds: 600   # 10 minutes
```

2. For test suites, consider splitting the gate into a faster smoke-test gate (required)
   and a slower full-suite gate (conditional):

```yaml
tests_smoke:
  required: true
  command: "pytest tests/unit/ -q --tb=short"
  timeout_seconds: 120

tests_full:
  required: false
  command: "pytest -q --tb=short"
  timeout_seconds: 600
  when: "pre-release check"
```

3. If the issue is with a specific agent step producing large output, add guidance
   in the relevant playbook to limit output verbosity.
4. If the run was interrupted mid-step, re-run `/aid-run-epic {epic_id}`. The
   Controller will re-execute the incomplete step from scratch.

---

## 11. Missing `.aid-o/` Directory

**Symptom**

Running any `/aid-*` command fails with:

```text
Error: .aid-o/ workspace not found. Run /aid-init to initialize.
```

**Cause**

The `.aid-o/` workspace has not been initialized in the current project, or you
are running the command from the wrong directory (not the project root).

**Solution**

1. Confirm you are in the project root:

```bash
pwd
ls .aid-o/
```

2. If `.aid-o/` is missing, initialize it:

```text
/aid-init
```

3. After initialization, run the setup to configure your project's tech stack:

```text
/aid-setup
```

4. If `.aid-o/` exists but is incomplete (missing subdirectories), run
   `/aid-init --upgrade` to repair the workspace structure without overwriting
   your existing configuration.

---

## 12. Config File Syntax Errors

**Symptom**

An orchestration command fails at startup with an error referencing a configuration
file:

```text
Error parsing gates.yaml: mapping values are not allowed here
  in ".aid-o/03-config/policies/gates.yaml", line 14, column 12
```

**Cause**

A YAML syntax error in one of the policy files (`gates.yaml`, `decision-policies.yaml`,
`memory-config.yaml`, `slack-config.yaml`). Common causes: indentation with tabs
instead of spaces, missing colon after a key, unquoted strings containing special
characters (`:`, `#`, `{`).

**Solution**

1. Validate the file with a YAML linter:

```bash
python3 -c "import yaml; yaml.safe_load(open('.aid-o/03-config/policies/gates.yaml'))"
```

2. The error message includes the file name, line number, and column. Open the file
   and inspect the indicated line.
3. Common fixes:
   - Replace tab characters with two or four spaces
   - Quote strings that contain colons: `description: "All tests: unit + integration"`
   - Ensure nested keys are consistently indented under their parent

4. If you cannot identify the error, restore the default from the plugin:

```text
/aid-init --upgrade
```

This classifies your modified file as `CUSTOM` and shows a diff between your version
and the default, so you can manually merge the correction.

---

## 13. Agent Dispatch Timeout

**Symptom**

A step in EXECUTING state fails with a timeout message, and the escalation trigger
E5 fires:

```text
Escalation E5: Agent timed out or produced no output.
Step: step_3_backend
```

**Cause**

The dispatched agent did not produce a `step_output` YAML block within the expected
time. This can happen when: the agent's task is too large for a single step, the
model is under high load, or the step's acceptance criteria are too broad, causing
the agent to attempt more work than a single context allows.

**Solution**

1. Respond to the escalation with option A (Fix) and include one of these instructions:
   - "Break this step into smaller pieces — implement only the data model in this step"
   - "Focus only on the API endpoint, defer tests to the QA step"
2. If the step is genuinely too large, revise the EPIC to split it into two steps.
   You can edit the EPIC file and re-run `/aid-plan-epic` to regenerate the plan.
3. In FIRST AID auto-mode, a second timeout on the same step triggers escalation
   E1 (step fails twice). The PM must intervene before a third attempt.
4. If the issue is persistent with certain agent roles, consider adding more specific
   scope constraints in the EPIC's `allowed_paths` and `acceptance_criteria` fields
   to reduce the agent's decision surface.
