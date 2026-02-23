---
type: example
archetype: "fullstack-webapp"
frameworks: [nextjs, react, prisma, typescript, tailwindcss]
complexity: high
description: "Next.js 15 full-stack app with App Router, Server Actions, Prisma ORM, authentication, Tailwind CSS"
platforms: []
ui: nextjs
---

# Example EPIC: Next.js Full-Stack Application

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building a full-stack web application with React Server Components and Server Actions
- Need server-side rendering (SSR), static generation (SSG), and API routes in one framework
- Want type-safe database access with Prisma ORM and PostgreSQL
- Authentication with session-based cookies or NextAuth.js is required
- Deploying to Vercel, Docker, or Node.js hosting with edge middleware support

### When NOT to use
- Static marketing site with no dynamic data (use Astro or plain HTML/CSS)
- Mobile-first application requiring native capabilities (use React Native)
- Real-time collaborative application (use dedicated WebSocket framework)
- Microservices architecture where frontend and backend must be independently deployed
- Team unfamiliar with React and TypeScript (steep learning curve)

Tech stack: Next.js 15+ (App Router) + React 19 + TypeScript 5+ + Prisma 6+ + PostgreSQL 16 + Tailwind CSS 4+ + Docker.
Greenfield: new Next.js project with `app/` directory, Server Components by default.
Pattern: App Router with layouts, Server Actions for mutations, Prisma for data access, middleware for auth.

## Goal

When complete, the application has a working authentication flow (signup, login,
logout), a protected dashboard area, and at least one CRUD resource managed via
Server Actions with Prisma. All pages use Server Components by default, with
Client Components only where interactivity is required. The app is deployable via
Docker or Vercel with environment-based configuration.

## Scope

### Allowed files/paths
- `{project_root}/app/` (App Router pages, layouts, Server Actions)
  - `{project_root}/app/layout.tsx` — root layout with metadata
  - `{project_root}/app/page.tsx` — landing page
  - `{project_root}/app/(auth)/login/page.tsx` — login page
  - `{project_root}/app/(auth)/signup/page.tsx` — signup page
  - `{project_root}/app/(auth)/actions.ts` — auth Server Actions
  - `{project_root}/app/dashboard/layout.tsx` — protected layout with auth check
  - `{project_root}/app/dashboard/page.tsx` — dashboard home
  - `{project_root}/app/dashboard/{resource}/page.tsx` — resource list
  - `{project_root}/app/dashboard/{resource}/[id]/page.tsx` — resource detail
  - `{project_root}/app/dashboard/{resource}/actions.ts` — CRUD Server Actions
  - `{project_root}/app/api/health/route.ts` — health check API route
- `{project_root}/components/` (shared UI components)
  - `{project_root}/components/ui/` — reusable primitives (Button, Input, Card)
  - `{project_root}/components/forms/` — form components with validation
- `{project_root}/lib/` (utilities)
  - `{project_root}/lib/db.ts` — Prisma client singleton
  - `{project_root}/lib/session.ts` — session management (encrypt/decrypt JWT cookie)
  - `{project_root}/lib/dal.ts` — Data Access Layer (verifySession, getUser)
  - `{project_root}/lib/validations.ts` — Zod schemas for form validation
- `{project_root}/prisma/`
  - `{project_root}/prisma/schema.prisma` — database schema
  - `{project_root}/prisma/migrations/` — migration history
  - `{project_root}/prisma/seed.ts` — seed data
- `{project_root}/middleware.ts` — route protection middleware
- `{project_root}/tests/`
- `{project_root}/CHANGELOG.md`

### Forbidden zones
- `{project_root}/node_modules/` (managed by package manager)
- `{project_root}/.next/` (build output)
- `{project_root}/public/` (static assets — add images only, do not restructure)

## Artifacts

- page: / (public landing page with hero section)
- page: /login (auth form with Server Action)
- page: /signup (registration form with password hashing via bcrypt)
- page: /dashboard (protected, shows overview metrics)
- page: /dashboard/{resource} (CRUD list with create/edit/delete actions)
- page: /dashboard/{resource}/[id] (detail view with edit form)
- action: auth Server Actions (signup, login, logout with session cookies)
- action: CRUD Server Actions (create, update, delete {resource})
- middleware: route protection (redirect unauthenticated users from /dashboard/*)
- schema: Prisma schema with User and {Resource} models
- api: GET /api/health (liveness probe)
- config: `middleware.ts` with matcher config for protected routes

## Constraints

- Tenant-safe: no (single-tenant by default; add organization_id for multi-tenancy)
- Audit trail: yes (createdAt, updatedAt on all Prisma models)
- Structured outputs: yes (TypeScript strict mode, Zod validation on all inputs)
- Budget: $15 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- build_pass
- docs_updated

## Acceptance Criteria

- [ ] [frontend] Landing page (/) renders with hero section and navigation to /login and /signup
- [ ] [frontend] Signup form validates fields with Zod, hashes password with bcrypt, creates user via Server Action
- [ ] [frontend] Login form authenticates user, creates encrypted session cookie, redirects to /dashboard
- [ ] [frontend] Middleware redirects unauthenticated users from /dashboard/* to /login
- [ ] [frontend] Dashboard layout shows current user info and logout button
- [ ] [backend] Server Actions for {resource} CRUD: create returns new record, update modifies fields, delete removes record
- [ ] [backend] Server Actions verify session via `verifySession()` from DAL before mutations
- [ ] [backend] Prisma schema includes User (id, name, email, password, role) and {Resource} models with relations
- [ ] [backend] `prisma migrate dev` runs cleanly on fresh database; `prisma db seed` populates test data
- [ ] [frontend] {Resource} list page displays paginated items fetched via Server Component (no client fetch)
- [ ] [frontend] {Resource} detail page shows edit form; save triggers Server Action and `revalidatePath()`
- [ ] [qa] Playwright e2e tests: signup flow, login flow, CRUD operations on {resource}
- [ ] [qa] TypeScript strict mode passes: `tsc --noEmit` with zero errors
- [ ] [qa] `next build` completes without errors
- [ ] [infra] `docker compose up` starts Next.js + PostgreSQL with healthy status within 60s

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design page hierarchy, data model (Prisma schema), auth flow (session cookies vs. NextAuth), and Server Action contracts | — | — |
| 2 | backend | Set up Prisma schema with User and {Resource} models, create initial migration, seed script, and `lib/db.ts` singleton | 1 | — |
| 3 | backend | Implement auth: `lib/session.ts` (JWT cookie encrypt/decrypt), Server Actions for signup (bcrypt hash), login, logout, `lib/dal.ts` (verifySession, getUser) | 2 | — |
| 4 | frontend | Build root layout, landing page, login/signup pages with form validation (Zod + `useActionState`), and `middleware.ts` for route protection | 3 | — |
| 5 | frontend | Build dashboard layout (sidebar nav, user info), {resource} list page (Server Component with Prisma query), and {resource} detail page with edit form | 4 | — |
| 6 | backend | Implement CRUD Server Actions for {resource}: create, update, delete with `revalidatePath()`, input validation with Zod, auth check via `verifySession()` | 5 | — |
| 7 | qa | Write Playwright e2e tests for auth flows and CRUD operations + verify `tsc --noEmit` and `next build` pass | 6 | group-verify |
| 8 | devops | Create Dockerfile (multi-stage Node 22-alpine) + docker-compose.yml with PostgreSQL and Next.js service | 6 | group-verify |
| 9 | docs | Write setup guide + update CHANGELOG.md | 7, 8 | — |

## Docker Compose

```yaml
version: "3.9"

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: runner
    container_name: nextjs-app
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://app_user:app_password@db:5432/app_db
      SESSION_SECRET: ${SESSION_SECRET:-change-me-in-production-min-32-chars}
      NEXT_PUBLIC_APP_URL: http://localhost:3000
      NODE_ENV: development
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    volumes:
      - ./app:/app/app
      - ./components:/app/components
      - ./lib:/app/lib
      - ./prisma:/app/prisma
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    container_name: nextjs-db
    environment:
      POSTGRES_USER: app_user
      POSTGRES_PASSWORD: app_password
      POSTGRES_DB: app_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app_user -d app_db"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

volumes:
  postgres_data:
```

## Notes

- **App Router patterns:** All pages are Server Components by default. Use `"use client"` only
  for interactive components (forms, buttons with onClick, state). Server Actions replace
  API routes for mutations.
- **Auth flow:** Use encrypted JWT session cookies (not NextAuth) for simplicity. The
  `middleware.ts` performs optimistic checks by reading the session cookie and redirecting.
  Server Actions and DAL functions call `verifySession()` for authoritative checks.
- **Server Actions:** Mark files with `"use server"` at top. Always validate input with Zod,
  check auth via `verifySession()`, call Prisma, then `revalidatePath()` to refresh cache.
- **Prisma singleton:** Use `globalThis` pattern in `lib/db.ts` to prevent multiple Prisma
  Client instances in development (Next.js hot reload creates new modules).
- **Tailwind CSS 4:** Uses CSS-first configuration with `@import "tailwindcss"` in globals.css.
  No `tailwind.config.js` needed unless customizing beyond CSS variables.
- **Alternative auth:** For OAuth/social login, replace custom session with NextAuth.js v5
  (`next-auth@beta`) which integrates natively with App Router.
