---
sidebar_position: 3
title: "Verifier Agent"
description: "Parametric agent that adopts verification focus via focus cards — QA, security review, code review, docs review."
---

# Verifier Agent

The Verifier is a **parametric agent** for read-only verification. Like the [Implementer](./implementer), it loads a card from `role-cards.md` at dispatch time — but instead of role cards, it uses **focus cards** that define what to verify and how to produce a verdict.

## Role

The Verifier reviews implementation outputs and produces a structured verdict: **PASS**, **FAIL**, or **PASS_WITH_NOTES**. It does not write implementation code — it analyzes, tests, and reports.

## When Dispatched

- After an implementer step completes, when the plan includes a verification step
- During analysis groups (parallel read-only reviews)
- The pipeline reads the step's `focus` field and dispatches the verifier with that focus

## How It Works

1. Read `skills/role-cards.md` — find the focus section under **Verifier Focus Cards**
2. Read `skills/agent-protocol.md` — follow the universal input/output format
3. Read all `context_files` from the task input (implementation outputs to verify)
4. Run verification checks defined by the focus card
5. Produce output with a verdict and evidence

## Available Focus Cards

| Focus | Scope | Output |
|-------|-------|--------|
| **qa** | Unit tests, integration tests, contract tests. Verifies acceptance criteria coverage, edge cases, error paths. Target: >80% coverage for new code. | `qa_report.md` + test files |
| **security-review** | OWASP patterns, hardcoded secrets, SQL injection, XSS, SSRF, AuthZ checks, tenant isolation. Read-only analysis; patches only for clear low-risk findings. | `security/findings.md` + patches |
| **code-review** | Module boundary compliance, error handling patterns, DRY violations, type safety, performance (N+1 queries, unbounded lists). | `code_review.md` |
| **docs-review** | All new endpoints documented, code examples compile, CHANGELOG present, no placeholder text or TODO markers. | `docs_review.md` |

An additional **e2e** focus card is available for browser-level E2E testing via Playwright MCP tools.

## Model

All focus types use **sonnet**. Verification is analytical and structured, not creative.

## Verdict Format

Every verifier output includes a verdict:

| Verdict | Meaning |
|---------|---------|
| **PASS** | All checks pass, no issues found |
| **FAIL** | Blocking issues found — must be resolved before proceeding |
| **PASS_WITH_NOTES** | Non-blocking observations recorded — can proceed |

The verdict always includes evidence: which checks were run, what was found, and specific file/line references.

## Key Behaviors

- **Read-only by default.** Verifiers analyze but do not modify production code. The `qa` focus card writes test files; `security-review` may apply low-risk patches. All others are strictly read-only.
- **Evidence-based verdicts.** Every PASS or FAIL is backed by specific findings with file paths and line references.
- **Does not write implementation code.** If the verifier finds an issue that requires implementation changes, it reports it — the pipeline handles the fix dispatch.
- **Follows agent-protocol.md for all I/O.** Same structured output format as the implementer.

## Related

- [Implementer Agent](./implementer)
- [Role Cards Skill](../skills/role-cards)
- [Agent Protocol Skill](../skills/agent-protocol)
- [Pipeline Skill](../skills/pipeline)
