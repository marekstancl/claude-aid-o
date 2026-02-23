---
type: example
archetype: "saas-starter"
frameworks: [nextjs, prisma, stripe, postgresql]
complexity: high
description: "SaaS starter template with multi-tenancy, Stripe billing, authentication, and admin dashboard"
platforms: []
ui: nextjs
---

# Example EPIC: SaaS Starter Template

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Starting a new SaaS product with subscription billing
- Need multi-tenancy with organization-level data isolation
- Authentication with multiple providers (email/password, Google, GitHub)
- Admin dashboard for managing users, organizations, and subscriptions

### When NOT to use
- Single-tenant application (skip multi-tenancy layer)
- No billing required (use simpler auth-only starter)
- Mobile-first product (use React Native or Flutter starter instead)
- Enterprise with existing identity provider (integrate directly with SSO)

Tech stack: Next.js 14+ (App Router) + Prisma + PostgreSQL + Stripe + NextAuth.js.
Greenfield: full project scaffold from scratch.
Pattern: App Router with server components, Prisma ORM, Stripe webhooks, NextAuth.js.

## Goal

When complete, the SaaS starter provides: user authentication (email + OAuth),
organization management with role-based access (owner, admin, member), Stripe
subscription billing with plan management, and an admin dashboard. The template
is ready for teams to add their domain-specific features.

## Scope

### Allowed files/paths
- `{project_root}/src/app/` (Next.js App Router pages)
- `{project_root}/src/components/` (React components)
- `{project_root}/src/lib/` (shared utilities, Prisma client, Stripe helpers)
- `{project_root}/prisma/` (schema + migrations)
- `{project_root}/src/app/api/` (API routes: auth, billing, webhooks)
- `{project_root}/tests/`
- `{project_root}/docs/`

### Forbidden zones
- None (greenfield project)

## Artifacts

- page: /login, /register, /dashboard, /settings, /billing
- page: /admin/users, /admin/organizations
- api: /api/auth/[...nextauth] (authentication)
- api: /api/billing/checkout, /api/billing/portal, /api/webhooks/stripe
- model: User, Organization, Membership, Subscription, Plan (Prisma)
- config: docker-compose.yml, .env.example

## Constraints

- Tenant-safe: yes (all queries scoped by organizationId)
- Audit trail: yes (createdAt, updatedAt on all models)
- Budget: $25 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- security_scan_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] NextAuth.js authenticates via email/password + Google + GitHub providers
- [ ] [backend] Organization CRUD: create, invite members, assign roles (owner/admin/member)
- [ ] [backend] All database queries filter by organizationId (multi-tenant isolation)
- [ ] [backend] Stripe Checkout creates subscription; webhook updates DB on payment events
- [ ] [backend] Stripe Customer Portal accessible for subscription management
- [ ] [frontend] Dashboard shows organization stats, recent activity
- [ ] [frontend] Settings page: profile, organization, team members, billing
- [ ] [frontend] Responsive layout with sidebar navigation
- [ ] [qa] Integration tests for auth flow, billing webhook, organization CRUD
- [ ] [security] RBAC middleware prevents unauthorized access to admin routes
- [ ] [docs] Setup guide covers: env vars, Stripe keys, OAuth app setup, DB migration

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design DB schema (Prisma), API contracts, auth flow, billing integration architecture | — | — |
| 2 | backend | Implement Prisma schema + migrations: User, Organization, Membership, Subscription, Plan | 1 | — |
| 3 | backend | Implement NextAuth.js with email + OAuth providers + session management | 2 | — |
| 4 | backend | Implement Stripe integration: checkout, webhooks, customer portal API routes | 3 | group-impl |
| 5 | frontend | Build dashboard, settings, billing pages with server components | 3 | group-impl |
| 6 | backend | Implement organization management: CRUD, invitations, RBAC middleware | 3 | group-impl |
| 7 | security | Review auth flow, RBAC enforcement, Stripe webhook signature verification | 4, 5, 6 | group-verify |
| 8 | qa | Write integration tests for auth, billing, organization flows | 4, 5, 6 | group-verify |
| 9 | docs | Setup guide + architecture overview | 7, 8 | — |

## Docker Compose

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: saas
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: saas
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U saas"]
      interval: 5s
      timeout: 5s
      retries: 5

  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://saas:${POSTGRES_PASSWORD}@postgres:5432/saas
      NEXTAUTH_URL: http://localhost:3000
      NEXTAUTH_SECRET: ${NEXTAUTH_SECRET}
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET}
      GITHUB_CLIENT_ID: ${GITHUB_CLIENT_ID}
      GITHUB_CLIENT_SECRET: ${GITHUB_CLIENT_SECRET}
      STRIPE_SECRET_KEY: ${STRIPE_SECRET_KEY}
      STRIPE_WEBHOOK_SECRET: ${STRIPE_WEBHOOK_SECRET}
      NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: ${STRIPE_PUBLISHABLE_KEY}
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  postgres_data:
```

## Notes

- Use Next.js App Router with server components for data fetching — avoid client-side API calls where possible
- Prisma schema should use `@@index([organizationId])` on all tenant-scoped models
- Stripe webhook handler must verify signature with `stripe.webhooks.constructEvent()`
- For local Stripe testing, use `stripe listen --forward-to localhost:3000/api/webhooks/stripe`
- NextAuth.js v5 with the `auth()` helper in server components for session access
- RBAC: middleware checks `membership.role` before allowing access to admin routes
