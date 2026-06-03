---
name: aid-audit
description: Project health audit (0-100 score)
user_invocable: true
---

Run a project health audit.

Read `agents/auditor.md` for the full audit protocol, scoring, and per-check definitions.

**Audit type:** $ARGUMENTS

Audit types map 1:1 to the auditor's categories (A–J).

**Always-run:**
- `code` — Code Audit (A): complexity, duplication, dead code, coupling, anti-patterns
- `security` — Security Audit (B): secrets, injection/XSS, authN/Z, dependency CVEs, headers
- `documentation` — Documentation Audit (C): API/doc drift, README, CHANGELOG, declared docs
- `process` — Process Audit (F): EPIC lifecycle, evidence completeness, cross-validation
- `efficiency` — Token Efficiency (H): token usage vs baseline (advisory, never blocks)

**Conditional (run only when their condition is met):**
- `frontend` — Frontend Audit (D): a11y, performance, bundle, structure — if `project.yaml` lists a frontend framework or `src/` contains `.tsx`/`.jsx`/`.vue`/`.svelte` files
- `database` — Database Audit (E): migrations, indexes, N+1, schema docs — if migration files exist, an ORM config is present, or `project.yaml` lists a database
- `instruction` — Instruction File Quality (G): frontmatter, cross-refs, dev markers — AID repo only (`plugins/aid-orchestrator/` exists)
- `standards` — Standards Compliance (I): project standards & guardrails — if `standards.active != none`
- `memory` — Memory Health (J): stale/conflicting memory entries — if `memory.enabled: true` in `integrations.yaml`

- `full` — all applicable categories above

If no type specified, ask the user which audit to run.

Output: severity levels **Critical / High / Medium / Low** (matching the auditor's global severity
scale). Two artifacts are written to `.aid-o/work/evidence/{epic_id}/`:
- `audit-report.yaml` — primary, machine-readable (consumed by the Orchestrator and Curator)
- `audit-report.md` — human-readable summary for PM review


**Last Updated:** 2026-06-03
