---
sidebar_position: 6
title: "Gate Fixer Agent"
description: "Fix failing quality gates by analyzing error output, identifying root cause, and making minimal targeted changes."
---

# Gate Fixer Agent

The Gate Fixer agent's sole purpose is to fix a specific failing quality gate so it passes on re-run. It receives the gate failure output, an analysis of the root cause, and scope constraints. It makes the minimal changes necessary — nothing more.

## Role

The Gate Fixer is a **utility agent**. It does not have domain expertise and does not participate in Epic step execution. It handles specific gate failures based on clear error output, dispatched by the pipeline when gates fail.

## When Dispatched

- When a quality gate fails during the GATES state and retries remain
- The pipeline dispatches it with failure details and `gates_report.json`
- One fix attempt per cycle, up to the configured maximum retry count

## Capabilities

| Gate | What It Fixes |
|------|--------------|
| `tests_pass` | Wrong assertions, missing fixtures, import errors, API changes |
| `lint_pass` | Unused imports, formatting issues, style violations |
| `security_scan_pass` | Hardcoded secrets, insecure functions, subprocess calls, injection vulnerabilities |
| `docs_updated` | Missing CHANGELOG entries, outdated API docs, README updates |
| `type_check` | TypeScript type annotations, interfaces, generic parameters |
| `build_pass` | Missing imports/exports, circular dependencies, config issues |

## Output Format

```yaml
gate_fix_result:
  gate: "{gate_name}"
  attempt: {N}
  status: "fixed|partial|unable"
  changes:
    - file: "path/to/file.py"
      description: "What was changed and why"
  explanation: "Root cause analysis"
  confidence: "high|medium|low"
```

## Key Behaviors

- **Never circumvents the gate check.** Forbidden: `@pytest.mark.skip`, `# noqa` without reason, `@ts-ignore`, removing tests, lowering thresholds, commenting out code, `try/except: pass`.
- **Suppression only for genuine false positives** with documented justification.
- **Minimal changes only.** Fix what is needed, do not refactor or add features.
- **Respects `allowed_paths`.** If the fix requires changes outside allowed paths, reports `status: unable`.
- **Reads prior attempts** to avoid repeating failed approaches.
- **Model:** haiku (fast, targeted fixes)

## Related

- [Quality Gates Skill](../skills/quality-gates)
- [Pipeline Skill](../skills/pipeline)
- [Implementer Agent](./implementer)
