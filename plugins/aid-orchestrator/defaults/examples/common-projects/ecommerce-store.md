---
type: example
archetype: "ecommerce-store"
frameworks: [nextjs, prisma, stripe, postgresql]
complexity: high
description: "E-commerce store with product catalog, shopping cart, checkout, and Stripe payment integration"
platforms: []
ui: nextjs
---

# Example EPIC: E-Commerce Store

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building an online store with product catalog and checkout flow
- Need shopping cart with session persistence (guest + authenticated)
- Stripe payment integration for one-time purchases
- Server-side rendered product pages for SEO

### When NOT to use
- Marketplace with multiple sellers (need vendor management layer)
- Subscription-only product (use SaaS starter with Stripe recurring billing)
- Physical inventory management (need warehouse integration — WMS)
- High-traffic flash sales (need dedicated caching/CDN strategy)

Tech stack: Next.js 14+ (App Router) + Prisma + PostgreSQL + Stripe + Redis.
Greenfield: full e-commerce project from scratch.
Pattern: SSR product pages, client-side cart state, Stripe Checkout for payment.

## Goal

When complete, customers can browse a product catalog, add items to a persistent
shopping cart, proceed to checkout via Stripe, and view order history. Admin
users can manage products (CRUD) and view orders.

## Scope

### Allowed files/paths
- `{project_root}/src/app/` (pages: home, products, cart, checkout, orders, admin)
- `{project_root}/src/components/` (ProductCard, CartDrawer, CheckoutForm, etc.)
- `{project_root}/src/lib/` (Prisma client, Stripe helpers, cart utils)
- `{project_root}/prisma/` (schema + migrations)
- `{project_root}/src/app/api/` (API routes)
- `{project_root}/tests/`

### Forbidden zones
- None (greenfield project)

## Artifacts

- page: /, /products, /products/[slug], /cart, /checkout, /orders, /admin/products
- api: /api/cart (CRUD), /api/checkout (create Stripe session), /api/webhooks/stripe
- model: Product, ProductVariant, Cart, CartItem, Order, OrderItem (Prisma)
- component: ProductCard, ProductGrid, CartDrawer, CheckoutForm, OrderSummary

## Constraints

- Tenant-safe: no (single-store)
- Audit trail: yes (order history, timestamps)
- Budget: $20 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- docs_updated

## Acceptance Criteria

- [ ] [frontend] Product listing page with grid layout, filtering by category, pagination
- [ ] [frontend] Product detail page with images, description, variant selection, "Add to Cart"
- [ ] [frontend] Cart drawer shows items with quantity adjustment and total
- [ ] [frontend] Checkout redirects to Stripe Checkout with correct line items
- [ ] [backend] Cart persists across sessions (cookie-based for guests, DB for authenticated)
- [ ] [backend] Stripe webhook updates order status on successful payment
- [ ] [backend] Admin CRUD for products: create, update, delete, upload images
- [ ] [backend] Order history page shows past orders with status
- [ ] [qa] Integration test: add to cart → checkout → verify order created on webhook
- [ ] [qa] Product page passes Core Web Vitals (LCP < 2.5s with SSR)
- [ ] [docs] Setup guide covers Stripe configuration and product seeding

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design DB schema, cart strategy (cookie vs DB), Stripe Checkout flow, API contracts | — | — |
| 2 | backend | Implement Prisma schema + migrations + seed script for sample products | 1 | — |
| 3 | backend | Implement cart API (add, remove, update quantity) with dual persistence | 2 | — |
| 4 | frontend | Build product catalog: listing page (SSR), detail page, ProductCard component | 2 | group-impl |
| 5 | frontend | Build cart drawer + checkout page with Stripe redirect | 3 | group-impl |
| 6 | backend | Implement Stripe Checkout + webhook + order creation | 3 | group-impl |
| 7 | frontend | Build admin product management + order history pages | 6 | — |
| 8 | qa | Write integration tests for cart → checkout → order flow | 6, 7 | — |
| 9 | docs | Setup guide + product seeding instructions | 8 | — |

## Docker Compose

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: ecommerce
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ecommerce
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ecommerce"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://ecommerce:${POSTGRES_PASSWORD}@postgres:5432/ecommerce
      REDIS_URL: redis://redis:6379
      STRIPE_SECRET_KEY: ${STRIPE_SECRET_KEY}
      STRIPE_WEBHOOK_SECRET: ${STRIPE_WEBHOOK_SECRET}
      NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: ${STRIPE_PUBLISHABLE_KEY}
      NEXTAUTH_URL: http://localhost:3000
      NEXTAUTH_SECRET: ${NEXTAUTH_SECRET}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started

volumes:
  postgres_data:
  redis_data:
```

## Notes

- Use Next.js SSR for product pages — critical for SEO and Core Web Vitals
- Cart dual persistence: cookie (JSON, <4KB) for guests, Redis/DB for authenticated users
- Stripe Checkout handles PCI compliance — never collect card details on your server
- Product images: use Next.js Image component with CDN (Cloudinary, AWS S3 + CloudFront)
- Seed script (`prisma/seed.ts`) with sample products speeds up development
- For production, add Stripe tax calculation and shipping rate configuration
