---
type: example
archetype: "dashboard"
frameworks: [react, typescript, recharts]
complexity: medium
description: "Analytics dashboard with charts, data tables, and REST API integration"
---

# Example EPIC: React Analytics Dashboard

> **NOTE:** This is a community example EPIC. Adapt component names, routes,
> and API endpoints to your project. Replace all `{placeholder}` values with
> your actual project paths and domain terms.

## Context

### When to use
- Building an admin or analytics dashboard displaying aggregated metrics
- Data is fetched from a REST API and refreshed periodically (not streamed)
- Visualization types: line, bar, pie charts + sortable/filterable data tables
- Audience: internal users or admins (not public-facing high-traffic pages)

### When NOT to use
- Real-time data streaming with sub-second updates (use WebSockets + canvas-based charts)
- Complex multi-step forms or wizard flows (form-heavy UIs need different architecture)
- Mobile-first consumer app (dashboard layout is desktop-optimized by default)
- Data volume > 10k rows rendered at once (use virtualization library instead)

Tech stack: React 18+ + TypeScript 5+ + Recharts 2+ + React Router 6+.
Greenfield: new `{frontend_dir}/src/features/dashboard/` module.
Pattern: feature-based folder structure, custom API hooks (no Redux unless existing).

## Goal

When complete, authenticated users see an analytics dashboard with summary KPI
cards, a time-series line chart, a bar chart comparison, and a paginated data
table. All data is fetched from REST API endpoints with loading and error states.
The layout is responsive down to 1024px wide.

## Scope

### Allowed files/paths
- `{frontend_dir}/src/features/dashboard/` (new feature module)
  - `{frontend_dir}/src/features/dashboard/components/` — all dashboard components
  - `{frontend_dir}/src/features/dashboard/hooks/` — data-fetching hooks
  - `{frontend_dir}/src/features/dashboard/types.ts` — TypeScript interfaces
  - `{frontend_dir}/src/features/dashboard/DashboardPage.tsx` — page entry point
- `{frontend_dir}/src/router/` (add dashboard route only)
- `{frontend_dir}/src/tests/dashboard/`
- `{project_root}/docs/components/dashboard.md`
- `{project_root}/CHANGELOG.md`

### Forbidden zones
- `{frontend_dir}/src/shared/` (shared components — import and use, do not modify)
- `{frontend_dir}/src/features/auth/` (auth module — use existing hooks/guards)
- `{frontend_dir}/src/router/index.tsx` (add route via provided extension point only)

## Artifacts

- component: DashboardPage (root layout), Sidebar, TopBar, ContentArea
- component: KpiCard (metric + trend indicator), KpiCardGrid (responsive grid)
- component: LineChartPanel (time-series, Recharts LineChart + ResponsiveContainer)
- component: BarChartPanel (category comparison, Recharts BarChart)
- component: DataTable (columns config, sort, filter, pagination controls)
- hook: useDashboardMetrics() — fetches KPI summary from GET /api/v1/metrics
- hook: useTableData(params) — fetches paginated rows from GET /api/v1/data
- config: chart theme tokens (colors, fonts) aligned to design system
- doc: `docs/components/dashboard.md`, `CHANGELOG.md`

## Constraints

- Tenant-safe: yes (API hooks pass auth token; backend enforces tenancy)
- Audit trail: no
- Outbox pattern: no
- Structured outputs: yes (TypeScript strict mode, no `any`)
- Budget: $12 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- docs_updated

## Acceptance Criteria

- [ ] [frontend] DashboardPage renders without errors when API returns valid data
- [ ] [frontend] KpiCard displays value, label, and trend arrow (up/down/neutral)
- [ ] [frontend] LineChartPanel renders with X-axis dates and Y-axis values; tooltip on hover
- [ ] [frontend] BarChartPanel renders with legend and displays "No data" state when empty
- [ ] [frontend] DataTable renders column headers with sort indicators; clicking header sorts rows
- [ ] [frontend] DataTable pagination: "Next" / "Prev" buttons update displayed rows
- [ ] [frontend] DataTable search/filter input narrows visible rows client-side
- [ ] [frontend] All components show a loading skeleton while API request is in flight
- [ ] [frontend] All components show an error message with retry button on API failure
- [ ] [frontend] Layout is usable at 1024px viewport width (no horizontal scroll)
- [ ] [frontend] TypeScript strict mode passes with zero type errors (`tsc --noEmit`)
- [ ] [qa] Vitest + Testing Library: KpiCard renders correct value from mock props
- [ ] [qa] Vitest + Testing Library: DataTable sort changes row order in DOM
- [ ] [qa] Vitest + Testing Library: useDashboardMetrics hook fetches and returns data
- [ ] [qa] Accessibility: no critical axe violations on DashboardPage (`@axe-core/react`)
- [ ] [docs] `docs/components/dashboard.md` lists all components with props table

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design component hierarchy diagram + state management approach (local state + custom hooks, no Redux) + API integration layer contracts (hook signatures, response types) | — | — |
| 2 | frontend | Implement layout shell: Sidebar (nav links), TopBar (user info, breadcrumb), ContentArea (slot for page content) + React Router route for /dashboard | 1 | — |
| 3 | frontend | Implement chart components: LineChartPanel and BarChartPanel using Recharts with ResponsiveContainer + loading/error/empty states + chart theme tokens | 2 | group-impl |
| 4 | frontend | Implement DataTable with column config, client-side sort, filter input, and pagination controls + useDashboardMetrics and useTableData API hooks with error/loading state | 2 | group-impl |
| 5 | qa | Write Vitest + Testing Library tests for KpiCard, DataTable sort/filter, and useDashboardMetrics hook (MSW or vi.mock for API) + axe accessibility checks on DashboardPage | 3, 4 | — |
| 6 | docs | Write component documentation (docs/components/dashboard.md) with props tables + deployment guide (env vars, build output, CDN config) + update CHANGELOG.md | 5 | — |

## Run Breakdown

This EPIC fits in a single orchestrated run.

### Run 1: Full Dashboard Implementation
**Goal:** Complete layout, charts, data table, API hooks, tests, and docs.
**Deliverables:** DashboardPage rendering real API data, Vitest suite green, docs written.

## Hints

- expected_steps: 6
- complexity: medium
- parallelism_potential: medium (steps 3 and 4 can run in parallel after step 2)
- notes: >
    Steps 3 and 4 are independent after the layout shell exists — chart panels
    and data table components don't depend on each other. Use Recharts
    `ResponsiveContainer` wrapping all chart components (not fixed width/height).
    For API hooks, use native `fetch` with `useEffect` + `AbortController` for
    cancellation, or a lightweight fetcher like SWR — avoid adding Redux unless
    already present in the project. For testing, prefer `vi.mock` over MSW
    unless MSW is already configured. Accessibility: import `@axe-core/react`
    in test setup only, not in production bundle.
