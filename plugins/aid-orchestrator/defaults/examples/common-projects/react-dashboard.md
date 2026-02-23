---
type: example
archetype: "admin-dashboard"
frameworks: [react, typescript, recharts, tanstack-query, tailwindcss, vite]
complexity: medium
description: "React admin dashboard with data visualization, authentication, TanStack Query, Recharts"
platforms: []
ui: react
---

# Example EPIC: React Admin Dashboard

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building an admin or analytics dashboard displaying aggregated metrics
- Data is fetched from a REST API with periodic refresh (not real-time streaming)
- Visualization types: line, bar, pie charts + sortable/filterable data tables
- Audience: internal users or admins (not public-facing high-traffic pages)
- Want React 19 with modern data fetching (TanStack Query v5) and Suspense

### When NOT to use
- Real-time streaming with sub-second updates (use WebSockets + canvas-based charts)
- Complex multi-step wizard forms (form-heavy UIs need dedicated form architecture)
- Mobile-first consumer application (dashboard layout is desktop-optimized)
- Data volume > 50k rows rendered at once (use TanStack Virtual for virtualization)
- Server-side rendering required (use Next.js full-stack template instead)

Tech stack: React 19 + TypeScript 5+ + Vite 6+ + TanStack Query v5 + Recharts 2+ + Tailwind CSS 4+ + React Router 7+.
Greenfield: new `{frontend_dir}/src/features/dashboard/` module.
Pattern: Feature-based folder structure, TanStack Query for server state, Suspense for loading states.

## Goal

When complete, authenticated users see an analytics dashboard with summary KPI
cards, a time-series line chart, a bar chart comparison, a pie/donut chart, and
a paginated data table with sort and filter. All data is fetched via TanStack
Query v5 with automatic background refresh, Suspense boundaries for loading
states, and Error Boundaries for failures. The layout is responsive down to 1024px.

## Scope

### Allowed files/paths
- `{frontend_dir}/src/features/dashboard/` (new feature module)
  - `{frontend_dir}/src/features/dashboard/components/` — dashboard components
    - `KpiCard.tsx`, `KpiCardGrid.tsx`
    - `LineChartPanel.tsx`, `BarChartPanel.tsx`, `PieChartPanel.tsx`
    - `DataTable.tsx`, `DataTablePagination.tsx`, `DataTableFilters.tsx`
    - `DashboardSkeleton.tsx` (loading state)
  - `{frontend_dir}/src/features/dashboard/hooks/` — TanStack Query hooks
    - `useDashboardMetrics.ts`
    - `useTableData.ts`
    - `useChartData.ts`
  - `{frontend_dir}/src/features/dashboard/types.ts` — TypeScript interfaces
  - `{frontend_dir}/src/features/dashboard/DashboardPage.tsx` — page entry point
  - `{frontend_dir}/src/features/dashboard/constants.ts` — chart colors, defaults
- `{frontend_dir}/src/router/` (add dashboard route only)
- `{frontend_dir}/src/lib/api-client.ts` (typed fetch wrapper — create if missing)
- `{frontend_dir}/src/tests/dashboard/`
- `{project_root}/docs/components/dashboard.md`
- `{project_root}/CHANGELOG.md`

### Forbidden zones
- `{frontend_dir}/src/shared/` (shared components — import only, do not modify)
- `{frontend_dir}/src/features/auth/` (auth module — use existing hooks/guards)
- `{frontend_dir}/src/router/index.tsx` (add route via extension point only)
- `{frontend_dir}/vite.config.ts` (build config — do not modify)

## Artifacts

- component: DashboardPage (root layout with Suspense boundaries)
- component: KpiCard (metric + trend indicator + sparkline), KpiCardGrid (CSS Grid)
- component: LineChartPanel (time-series, Recharts ResponsiveContainer + LineChart)
- component: BarChartPanel (category comparison, Recharts BarChart with legend)
- component: PieChartPanel (distribution, Recharts PieChart with custom label)
- component: DataTable (TanStack Table v8 integration — columns, sort, filter, pagination)
- component: DashboardSkeleton (skeleton loading state matching dashboard layout)
- hook: useDashboardMetrics() — TanStack Query `useQuery` fetching GET /api/v1/metrics
- hook: useTableData(params) — TanStack Query `useQuery` with pagination params
- hook: useChartData(range) — TanStack Query `useQuery` with date range filter
- config: chart theme tokens (Tailwind CSS custom properties for chart colors)
- doc: `docs/components/dashboard.md`, `CHANGELOG.md`

## Constraints

- Tenant-safe: yes (API client passes auth token; backend enforces tenancy)
- Audit trail: no
- Structured outputs: yes (TypeScript strict mode, no `any`, Zod for API response validation)
- Budget: $12 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- a11y_pass
- docs_updated

## Acceptance Criteria

- [ ] [frontend] DashboardPage renders without errors when API returns valid data
- [ ] [frontend] KpiCard displays value, label, trend percentage, and directional arrow (up/down/neutral)
- [ ] [frontend] LineChartPanel renders X-axis dates and Y-axis values; tooltip shows details on hover
- [ ] [frontend] BarChartPanel renders with legend; shows "No data" empty state when dataset is empty
- [ ] [frontend] PieChartPanel renders distribution with percentage labels and interactive legend
- [ ] [frontend] DataTable renders column headers with sort indicators; clicking header toggles sort direction
- [ ] [frontend] DataTable pagination: Next/Previous buttons update rows; page size selector (10/25/50)
- [ ] [frontend] DataTable filter input narrows visible rows via server-side query (debounced 300ms)
- [ ] [frontend] Suspense boundaries show DashboardSkeleton while TanStack Query fetches data
- [ ] [frontend] Error Boundaries show error message with retry button on API failure
- [ ] [frontend] Layout is usable at 1024px viewport width (no horizontal scroll, responsive grid)
- [ ] [frontend] TypeScript strict mode passes with zero type errors (`tsc --noEmit`)
- [ ] [qa] Vitest + Testing Library: KpiCard renders correct value from mock props
- [ ] [qa] Vitest + Testing Library: DataTable sort changes row order in DOM
- [ ] [qa] Vitest + Testing Library: useDashboardMetrics hook returns data from mocked API
- [ ] [qa] Accessibility: no critical violations via `@axe-core/react` on DashboardPage

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design component hierarchy, state management approach (TanStack Query v5 for server state, no Redux), API contracts (hook signatures, response TypeScript types), chart theme tokens | — | — |
| 2 | frontend | Implement DashboardPage layout shell with CSS Grid + Suspense boundaries + Error Boundaries + React Router route registration | 1 | — |
| 3 | frontend | Implement chart components: LineChartPanel, BarChartPanel, PieChartPanel using Recharts ResponsiveContainer + loading/error/empty states + theme tokens | 2 | group-impl |
| 4 | frontend | Implement KpiCardGrid + KpiCard with trend indicator + DataTable with TanStack Table v8 (column config, sort, filter, pagination) + all TanStack Query hooks | 2 | group-impl |
| 5 | qa | Write Vitest + Testing Library tests for KpiCard, DataTable sort/filter, hooks (vi.mock for API) + axe accessibility audit on DashboardPage | 3, 4 | — |
| 6 | docs | Write component documentation (docs/components/dashboard.md) with props tables + storybook-style usage examples + update CHANGELOG.md | 5 | — |

## Docker Compose

```yaml
version: "3.9"

services:
  dashboard:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: react-dashboard
    ports:
      - "5173:5173"
    environment:
      VITE_API_BASE_URL: http://api:8000/api/v1
      VITE_APP_TITLE: Admin Dashboard
    volumes:
      - ./src:/app/src
      - ./public:/app/public
    command: npm run dev -- --host 0.0.0.0
    restart: unless-stopped

  api:
    image: mockoon/cli:latest
    container_name: dashboard-mock-api
    ports:
      - "8000:8000"
    volumes:
      - ./mocks/api.json:/data/api.json
    command: ["--data", "/data/api.json", "--port", "8000"]
    restart: unless-stopped

  storybook:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: dashboard-storybook
    ports:
      - "6006:6006"
    volumes:
      - ./src:/app/src
    command: npm run storybook -- --host 0.0.0.0
    profiles:
      - dev
    restart: unless-stopped
```

## Notes

- **TanStack Query v5:** Use `useQuery({ queryKey: [...], queryFn: ... })` object syntax.
  Enable `staleTime: 30_000` for dashboard metrics to avoid excessive refetching.
  Use `useSuspenseQuery` inside Suspense boundaries for cleaner loading states.
- **Recharts:** Always wrap charts in `<ResponsiveContainer width="100%" height={300}>`.
  Never set fixed width/height on chart components directly.
- **React 19 patterns:** Use the `use()` hook for reading context/promises where appropriate.
  Prefer `useActionState` for form submissions. Suspense + Error Boundary pattern for data fetching.
- **TanStack Table v8:** Define columns with `createColumnHelper<T>()`. Use
  `useReactTable({ data, columns, getCoreRowModel, getSortedRowModel, getFilteredRowModel })`.
- **Testing:** Use `vi.mock` for API mocking unless MSW is already configured. Import
  `@axe-core/react` only in test files, never in production bundle.
- **Chart colors:** Define as CSS custom properties in Tailwind config. Use `hsl()` format
  for easy dark mode variants: `--chart-1: 220 70% 50%`.
- **Mock API:** Docker Compose includes Mockoon for local development without a real backend.
  Replace with actual API service URL for production.
