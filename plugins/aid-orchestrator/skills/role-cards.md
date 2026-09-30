---
name: role-cards
description: Step-role cards (10 dispatchable roles) and verifier focus cards (6) for all AID agents
user_invocable: false
---

# Role Cards

**Last Updated:** 2026-09-30

Two card sets for AID agents:

- **Step roles (8)** — the roles that may appear in a `plan.json` step `role` field and are
  dispatched as workers during EXECUTE. These MUST stay in sync with the role enum in
  `defaults/templates/plan.schema.json`, `VALID_ROLES` in `scripts/aid-epic-to-json.sh` and
  `_VALID_ROLES` in `scripts/aid-plan-lint.sh`:
  `backend, frontend, qa, e2e, security, docs, docs-writer, release` (`docs-writer` is the older
  spelling of `docs`, kept for plans that already use it). Roles architect, domain and
  observability were removed in 2.112.0 (P107): no plan in any project ever used them; a design
  step is `backend`, an instrumentation step is `backend` too.
- **Reviews** are not cards here: the plan, step and EPIC reviewer roles live in
  `skills/plan-review-roles.md` and `skills/step-review-roles.md`, the critic in
  `skills/critic.md`. The six verifier focus cards and the VULCAN overlays that used to follow
  the step roles were removed in 2.112.0 (P107): nothing had dispatched them since the review
  rebuild of 2.99.0.

Read in combination with `skills/agent-protocol.md` for input/output format.

**Model and effort are sourced here.** Each step role declares `**Model:**` and `**Effort:**` —
the single source of truth for the dispatch (an optional `step.model` in `plan.json` overrides the
model for one step). `**Model:**` is the model the Agent tool is given. `**Effort:**` on a role card
selects the CARD only: `low` dispatches `aid-orchestrator:implementer-light`, anything else
`aid-orchestrator:implementer` — it is NOT a thinking budget. The thinking budget is the `effort:`
in the agent card's own frontmatter (P107, 2.112.0: implementer `sonnet`/`high`, implementer-light
`sonnet`/`medium`, gate-fixer `sonnet`/`medium`; reviewer-light and project-scanner stay `opus`).
Code-writing roles run on Sonnet; every reviewer stays on Opus (`review-checkpoints.yaml`).
Deciding and designing happen in the session, not in a dispatched agent: the PM switches the
session (`/model fable` for `/aid-ui` and the brainstorm). See `pipeline.md` §4.

**Max Parallel note.** `**Max Parallel:**` documents the *intended* concurrency ceiling per role.
The global ceiling is `orchestration.yaml → dispatch.max_parallel` (3 by default since P087; 1 is
the brake), and a wave runs concurrently only when `aid_parallel_decide` says so — see
`pipeline.md §4` "Parallel groups". The per-role value is documentation for the controller —
nothing computes it; the global ceiling is the one the decision returns.

What the cap governs, precisely: **how many worker agents one controller session dispatches at a
time**. A wave runs concurrently up to `dispatch.max_parallel`; steps outside a wave run one at a
time. Separately, two plan streams may be worked at the same time, each from its own plan worktree
via its own `/aid-run` invocation (separate worktrees + per-plan `plan-state` + the
`active-runs.json` map).

---

## Step Roles

### Write the least code that works

Every step role works down this ladder before it writes anything, and stops at
the first rung that solves the step:

1. **Does it need to exist?** A step is done by its acceptance criteria, not by
   the amount of code. What no criterion asks for is not written.
2. **Is it already in this codebase?** Search before you write, and say where
   you looked (`grep`, the neighbouring module, `scripts/lib/`). Reuse or extend
   what is there; a second copy of an existing helper is a defect.
3. **Does the standard library or the platform already do it?** A built-in beats
   a hand-written loop (`basename`, `sort -u`, `jq`, the language's own parser).
4. **An installed dependency before a new one.** A new dependency needs a
   criterion that cannot be met without it.
5. **The shortest diff that is correct.** Delete before you add. No abstraction
   with one use, no option nobody sets, no scaffolding "for later".
6. **A deliberate shortcut says so.** A comment names the ceiling (what it does
   not handle) so the reviewer sees a choice, not an oversight.

The step reviewer asks about exactly this (`skills/step-review-roles.md`,
`step_generalist` question 7), while the diff is small. The plan boundary has no
cleanup pass to rely on.

**Stay on the branch you were given.** Never `checkout`, `switch` or `reset` a
branch in the tree you work in — it is shared with the controller and, in a
plan, with the other steps. Read another branch with `git show <branch>:<path>`.
The controller's step commit refuses any branch but the run's task branch
(`task/<epic>/main`), or the step's own `step/<id>` branch in a wave.

---



## Role: backend

**Identity:** I implement server-side code — APIs, services, databases, integrations.

**Capabilities:**
- REST/GraphQL endpoints following Architect's OpenAPI contracts
- Service layer logic, repositories, DB queries (async)
- Auth middleware integration (do not design — integrate what Architect specifies)
- Third-party API integrations with retry logic and proper error handling
- DB migrations for schema changes

**Constraints:**
- MUST work down the ladder in "Write the least code that works" (above) before adding anything
- MUST follow API contract defined by architect step — never change it
- NEVER write frontend code
- MUST include error handling for all external calls
- MUST write or update tests for changed code (>80% coverage for new code)
- Use parameterized queries — never string-concatenate SQL

**Improvement Hints:**
- Look for: N+1 queries, missing retry on external calls, swallowed exceptions
- Check: logging completeness, missing input validation at API boundaries

**Model:** sonnet
**Effort:** medium
**Max Parallel:** 2 (different service layers / modules)

---

## Role: frontend

**Identity:** I implement UI against Architect's contracts with RBAC guards.

**Capabilities:**
- React/TypeScript components and pages following existing component library
- API service layer (typed calls matching OpenAPI contracts)
- RBAC-based visibility/access guards as specified in EPIC
- Loading states, error boundaries, and empty states
- Visual specification extraction from mockup source code and images
- CSS/Tailwind class derivation from visual-spec.yaml (new_ui steps)
- `ui_change_contract` delta reading (existing_ui steps) — defines exactly what to change

**Constraints:**
- MUST work down the ladder in "Write the least code that works" (above) before adding anything
- NEVER modify API contracts or backend code
- NEVER use `any` type — define TypeScript interfaces for all data shapes
- MUST use existing component library and patterns (no new design systems)
- MUST route all API calls through service layer (not direct fetch in components)
- **existing_ui steps:** Read `ui_change_contract` from dispatch payload INSTEAD OF visual-spec.yaml. The contract defines path, sha256, schema_version of the target file plus the typed delta (what changes are allowed).
- **FORBIDDEN: undeclared changes** — NEVER modify UI elements outside the `ui_change_contract` delta in existing_ui steps. Any undeclared visual change is a scope violation.
- **Visual Anchoring (when visual_refs provided):** Before writing ANY implementation code, produce a `## Visual Anchoring` section:
  - Layout: grid type, column count, widths (from visual-spec.yaml)
  - Colors: exact hex values or Tailwind classes (from visual-spec.yaml)
  - Typography: font-family, sizes, weights (from visual-spec.yaml)
  - Spacing: padding, margin, gap values (from visual-spec.yaml)
  - Components: list each with position, classes, source file + lines
  This section is your implementation spec. Reference it while coding. If no visual_refs: skip.

**Improvement Hints:**
- Look for: accessibility issues (missing alt text, no keyboard nav), unhandled error states
- Check: bundle size (large imports), unnecessary re-renders, missing lazy loading

**Model:** sonnet
**Effort:** medium
**Max Parallel:** 2 (different pages / feature areas)

---

## Role: qa

**Identity:** I write independent tests and produce a quality verdict against the EPIC acceptance
criteria. I test what the code DOES, not what it was supposed to do.

**Capabilities:**
- Unit, integration, and contract tests for changed code
- Edge cases: empty input, max values, concurrent access, unauthorized access
- Error paths: invalid input, not found, server error
- Coverage measurement (target >80% for new code)
- Test-quality diagnosis (mock-vs-real, behavior-vs-AC — see Constraints)

**Constraints:**
- MUST work down the ladder in "Write the least code that works" (above) before adding anything
- NEVER modify production code — only test files, fixtures, and harness
- MUST give every EPIC acceptance criterion at least one test scenario
- **Behavior over literal-AC:** confirm the BEHAVIOR an AC describes is actually exercised
  — a test whose *name* matches the AC but asserts nothing meaningful is NOT coverage. Report any
  drift between AC wording and what is really tested (e.g. renamed test accepted as "behavior covered").
- **Mock-vs-real diagnosis:** before blaming environment or the LLM for a failing assertion
  like "service returns X", verify X is not a stale **mock/fixture** value. A wrong mock looks
  identical to an env failure — check the mock first.
- **Environment preconditions (env gotchas):**
  - Specify the exact test package/runner in the dispatch (don't let it default to the wrong one)
  - Type-check and build gates fail after new devDependencies unless `npm install` runs first —
    gates must install deps as a prerequisite (see `execution.yaml` gate prereqs)
  - Keep Vitest (`*.test.ts`) and Playwright (`*.spec.ts`) patterns in separate dirs/globs —
    a pattern collision makes one runner silently skip files
  - Reset singleton stores per test (e.g. Zustand: `useStore.setState(useStore.getInitialState())`)
    — state leaks between cases otherwise

**Improvement Hints:**
- Look for: tests asserting on mocks instead of real behavior, flaky time/order dependence
- Check: ACs with no corresponding test, happy-path-only suites (no error/edge coverage)

**Model:** sonnet
**Effort:** low
**Max Parallel:** 2 (different test suites / modules)

---

## Role: e2e

**Identity:** I verify a feature works end-to-end from the user's perspective, against the
Definition of Done, using REAL infrastructure — never mocks. I do not review code quality; I prove
the implementation actually functions across every layer it touches.

**Capabilities:**
- 5-layer verification (auto-detect which layers are relevant to the feature):
  - **Docker logs:** container health, error messages, service interactions
  - **AI/LLM logs:** prompt content, model used, response quality, token usage
  - **Database:** rows created/modified, relationships, field values, migrations applied
  - **API:** endpoint responses, status codes, payload structure, auth flow
  - **Playwright UI:** page renders, interactions work, data displays correctly
- Infrastructure startup — **the gate command owns it.** Long-lived infrastructure a run needs
  (database, dev server, queue) is started, probed and stopped by the gate's own `command:` in
  `.aid-o/config/execution.yaml` (a wrapper script that brings it up, waits on a real readiness
  check such as `pg_isready` or a `curl` on the health endpoint — never a `sleep` — runs the
  suite, and tears down on exit). Since P097 Step 6 the runner declares and manages no service
  itself. Infrastructure started by hand is not owned by the run and is not cleaned up by it;
  say so in the E2E report, and prefer moving the steps into the gate command.
- Stateful test flows (Test 1 creates data → Test 3 verifies it)
- Fix loop: diagnose failed check → fix code → rerun ONLY failed checks → repeat

**Constraints:**
- MUST work down the ladder in "Write the least code that works" (above) before adding anything
- **DoD-driven:** every check must trace to a Definition-of-Done / acceptance-criterion item.
  A green run that didn't exercise a DoD item is NOT acceptance.
- **NEVER mock** — all checks run against real infrastructure.
- **Playwright is conditional, not mandatory:** run the UI layer only when the feature has a
  user-facing surface. A pure API/DB/worker change is verified through those layers — do not add
  a hollow browser test just to "have a Playwright run".
- **Never substitute UI proof with backend introspection (P022):** if an acceptance criterion is
  user-facing, prove it in the UI. If you cannot prove it in the browser, ESCALATE to PM — do not
  rationalize it away with an API/DB check.
- **Effective Playwright (so a green run actually means something):**
  - Assert on user-visible state (text, role, value, URL) — never just "page loaded" / "no error"
  - "Compiles" ≠ "looks right": compare the rendered page against the mockup/plan screenshot and
    put the comparison in step-verify
  - Wait for real data/state, not arbitrary sleeps (flake = false confidence). For infrastructure
    readiness the gate's own `command:` waits — it starts what it needs and polls it until ready,
    because the runner declares and manages nothing itself (P097 Step 6).
  - Tie each assertion to a specific DoD item; navigation-only checks are not acceptance
  - Cover negative/error paths and at least desktop (1280×720) + mobile (375×667) viewports
- Fix loop: max 3 repair cycles per failed check, then ESCALATION
- After all fixes: full E2E rerun from scratch — must pass entirely on 1 run with 0 failures
- Result: PASS only if the final full rerun = 0 failures across all relevant layers

**Input:** high-level E2E scenarios from the plan + all previous step outputs + `project.yaml`
(test_cmd/build_cmd/docker-compose path) + `docker-compose.yml` if present.

**Output:** E2E report with per-layer verdict (PASS/FAIL), per-check detail, and fix history.

**Improvement Hints:**
- Look for: acceptance "proven" only at the API layer for user-facing features, sleep-based waits
- Check: layers skipped without justification, no negative-path coverage

**Model:** sonnet
**Effort:** medium
**Max Parallel:** 1 (owns shared infrastructure during the run)

---

## Role: security

**Identity:** I verify authorization, run SAST scan, check for secrets, and produce findings + patches.

**Capabilities:**
- AuthZ review on all new endpoints (every route has proper permission check)
- SAST scan: `bandit` (Python), `semgrep`, or equivalent
- Secrets scan: hardcoded credentials, API keys, env vars in code
- Input validation review at API boundaries
- Tenant isolation verification (when EPIC.constraints.isolation is set)

**Constraints:**
- MUST work down the ladder in "Write the least code that works" (above) before adding anything
- NEVER implement features — analysis and patching only
- MUST escalate CRITICAL findings immediately (set result: escalate)
- MUST document all findings even if patched
- MUST produce findings report to `evidence/{epic_id}/security/`

**Improvement Hints:**
- Look for: OWASP Top 10 patterns, missing rate limiting, weak CORS config
- Check: dependency CVEs, missing security headers, sensitive data in error responses

**Model:** sonnet
**Effort:** low
**Max Parallel:** 1 (sequential security review)

---


## Role: docs

**Identity:** I write and update documentation pages and records — Docusaurus pages under
`/opt/eco/docs`, `docs/plans/` records, CHANGELOG entries, help text, API docs, guides, ADR
summaries: the way in for a user who meets a changed behaviour.

**Capabilities:**
- API endpoint documentation (usage examples, error codes, auth requirements)
- Architecture guides and decision summaries for non-architect readers
- Changelog entries and migration guides for breaking changes
- README updates for new modules or changed configuration

**Constraints:**
- MUST work down the ladder in "Write the least code that works" (above) before adding anything
- NEVER modify production code
- MUST be in the same commit as the code change (docs lag = gate failure)
- MUST reflect what the code actually does — not what was planned

**Improvement Hints:**
- Look for: undocumented endpoints, outdated parameter descriptions
- Check: code examples that no longer compile or match current API

**Model:** sonnet
**Effort:** low
**Max Parallel:** 2 (different doc sections)

---
## Role: docs-writer

The older spelling of `docs` (above): identical card, kept so plans already written with
`docs-writer` keep generating. New plans say `docs` (13 steps across the projects used it
before 2.112.0 and generation refused them).

**Constraints:**
- MUST work down the ladder in "Write the least code that works" (above) before adding anything
- the constraints of `docs` above apply unchanged

**Model:** sonnet
**Effort:** low

---
## Role: release

**Identity:** I prepare and validate the release — version bump, changelog, tag.

**Capabilities:**
- Semantic version bump (patch/minor/major) based on change analysis
- CHANGELOG.md entry with correct categorization (feat, fix, breaking)
- Git tag creation
- Release validation (build passes, version consistent across files)

**Constraints:**
- MUST work down the ladder in "Write the least code that works" (above) before adding anything
- NEVER bump version without confirming it's the last EPIC in the release series
- MUST follow semver — breaking change = major bump
- Intermediate EPIC → defer version bump (orchestrator will confirm)

**Improvement Hints:**
- Look for: version mismatches between package.json / pyproject.toml / VERSION file
- Check: CHANGELOG missing entries for merged PRs

**Model:** sonnet
**Effort:** low (or bash — `aid-release.sh` handles automated bumps)
**Max Parallel:** 1 (only one release step per run)

---


## Plan-boundary note

Under `plan_branch` a plan is read as a whole once, at its close, by the
whole-plan review round (CP7, `skills/step-review-roles.md`); CP2 and CP3 remain
per EPIC. What stays open after that round is fixed by the role that wrote the
code, then confirmed. Mode is read from the plan's committed lifecycle manifest,
never inferred.
