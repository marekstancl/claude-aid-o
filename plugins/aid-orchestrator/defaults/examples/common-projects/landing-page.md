---
type: example
archetype: "marketing-landing-page"
frameworks: [nextjs, react, tailwindcss, typescript]
complexity: low
description: "Marketing landing page with CMS integration, contact forms, analytics, SEO optimization"
platforms: []
ui: nextjs
---

# Example EPIC: Marketing Landing Page

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building a marketing or product landing page for lead generation or product launch
- Content should be editable by non-technical team members (CMS or MDX)
- SEO optimization, Open Graph tags, and page speed are critical success metrics
- Need contact/signup forms with server-side submission and validation
- Analytics integration (Google Analytics, Plausible, or PostHog) is required

### When NOT to use
- Complex web application with user accounts and dynamic data (use full-stack template)
- E-commerce with shopping cart and checkout (use e-commerce template)
- Blog or documentation site with many pages (use Astro or dedicated CMS platform)
- Rapid prototype that will be discarded (use plain HTML/CSS)
- Team prefers a no-code builder (use Webflow or Framer)

Tech stack: Next.js 15+ (App Router, static export) + React 19 + TypeScript 5+ + Tailwind CSS 4+ + MDX.
Greenfield: new Next.js project optimized for static generation with `output: "export"`.
Pattern: Static-first with ISR fallback, component-driven sections, CMS-managed content.

## Goal

When complete, the landing page loads in under 2 seconds (LCP), scores 90+ on
Lighthouse performance, displays a hero section with CTA, feature highlights,
testimonials, pricing table, FAQ accordion, and a contact form that submits to a
Server Action or API endpoint. All content is editable via MDX files or a headless
CMS. Analytics tracking fires on page load and form submission events.

## Scope

### Allowed files/paths
- `{project_root}/app/` (App Router pages)
  - `{project_root}/app/layout.tsx` — root layout with metadata, fonts, analytics script
  - `{project_root}/app/page.tsx` — landing page (composes section components)
  - `{project_root}/app/api/contact/route.ts` — form submission API route
  - `{project_root}/app/thank-you/page.tsx` — post-submission confirmation
  - `{project_root}/app/privacy/page.tsx` — privacy policy (MDX)
  - `{project_root}/app/terms/page.tsx` — terms of service (MDX)
- `{project_root}/components/sections/` (landing page sections)
  - `Hero.tsx`, `Features.tsx`, `Testimonials.tsx`
  - `Pricing.tsx`, `FAQ.tsx`, `CTA.tsx`, `Footer.tsx`, `Navbar.tsx`
- `{project_root}/components/ui/` (reusable primitives)
  - `Button.tsx`, `Input.tsx`, `Card.tsx`, `Accordion.tsx`, `Badge.tsx`
- `{project_root}/components/forms/ContactForm.tsx`
- `{project_root}/content/` (MDX or JSON content files)
- `{project_root}/lib/analytics.ts` — analytics event helpers
- `{project_root}/public/` (images, favicon, og-image)
- `{project_root}/CHANGELOG.md`

### Forbidden zones
- `{project_root}/node_modules/` (managed by package manager)
- `{project_root}/.next/` (build output)

## Artifacts

- page: / (landing page with all sections composed)
- page: /thank-you (form submission confirmation)
- page: /privacy (privacy policy from MDX)
- page: /terms (terms of service from MDX)
- section: Hero (headline, subheadline, CTA button, hero image/video)
- section: Features (grid of feature cards with icons)
- section: Testimonials (carousel or grid of customer quotes)
- section: Pricing (2-3 tier comparison table with CTA per tier)
- section: FAQ (accordion with expandable questions)
- section: CTA (final call-to-action with email capture)
- component: ContactForm (name, email, message — validated, submitted to API)
- component: Navbar (logo, nav links, CTA button — sticky on scroll)
- component: Footer (links, social icons, copyright)
- api: POST /api/contact (validate + email or store submission)
- config: `next.config.ts` with image optimization, metadata, sitemap
- asset: `public/og-image.png` (1200x630 Open Graph image)

## Constraints

- Tenant-safe: no (single landing page, no multi-tenancy)
- Audit trail: no
- Structured outputs: yes (TypeScript strict mode)
- Budget: $8 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- lighthouse_pass
- docs_updated

## Acceptance Criteria

- [ ] [frontend] Landing page renders all sections: Hero, Features, Testimonials, Pricing, FAQ, CTA, Footer
- [ ] [frontend] Navbar is sticky on scroll with smooth-scroll anchor links to each section
- [ ] [frontend] Hero section displays headline, subheadline, and primary CTA button above the fold
- [ ] [frontend] Features section shows 3-6 feature cards in a responsive grid (1 col mobile, 3 col desktop)
- [ ] [frontend] Pricing section shows 2-3 tiers with feature comparison and CTA per tier
- [ ] [frontend] FAQ accordion expands/collapses with accessible keyboard navigation (Enter/Space)
- [ ] [frontend] ContactForm validates required fields (name, email, message) with inline error messages
- [ ] [backend] POST /api/contact returns 200 on valid submission, 422 on validation failure
- [ ] [seo] Page has complete metadata: title, description, og:image, og:title, og:description, canonical URL
- [ ] [seo] Sitemap generated at /sitemap.xml with all public pages
- [ ] [perf] Lighthouse performance score >= 90 on mobile simulation
- [ ] [perf] Largest Contentful Paint (LCP) < 2.5 seconds
- [ ] [perf] Images use Next.js `<Image>` component with proper width/height and lazy loading
- [ ] [a11y] No critical axe-core violations; all interactive elements have accessible labels
- [ ] [analytics] Page view event fires on load; form submission event fires on successful submit

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design page wireframe (section order), component hierarchy, content schema (MDX vs CMS), and SEO metadata strategy | — | — |
| 2 | frontend | Implement root layout with metadata, Navbar (sticky, smooth-scroll), Footer, and responsive design tokens (Tailwind CSS 4 theme) | 1 | — |
| 3 | frontend | Implement Hero, Features, and Testimonials sections with responsive grid layouts and Next.js Image optimization | 2 | group-sections |
| 4 | frontend | Implement Pricing table (tier comparison), FAQ accordion (accessible), and CTA section with email capture | 2 | group-sections |
| 5 | frontend | Implement ContactForm with Zod validation, Server Action or API route for submission, and /thank-you confirmation page | 3, 4 | — |
| 6 | qa | Run Lighthouse audit (target >= 90 performance), axe-core a11y scan, test form validation, verify SEO metadata and sitemap | 5 | — |
| 7 | docs | Write content guide (how to edit MDX/CMS), deploy instructions, and update CHANGELOG.md | 6 | — |

## Docker Compose

```yaml
version: "3.9"

services:
  landing:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: landing-page
    ports:
      - "3000:3000"
    environment:
      NEXT_PUBLIC_SITE_URL: http://localhost:3000
      CONTACT_EMAIL: ${CONTACT_EMAIL:-hello@example.com}
      ANALYTICS_ID: ${ANALYTICS_ID:-}
      NODE_ENV: development
    volumes:
      - ./app:/app/app
      - ./components:/app/components
      - ./content:/app/content
      - ./public:/app/public
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/"]
      interval: 10s
      timeout: 5s
      retries: 3
    restart: unless-stopped

  mailhog:
    image: mailhog/mailhog:latest
    container_name: landing-mailhog
    ports:
      - "1025:1025"
      - "8025:8025"
    profiles:
      - dev
    restart: unless-stopped
```

## Notes

- **Static export:** For pure static hosting (Netlify, Cloudflare Pages), set
  `output: "export"` in `next.config.ts`. This disables Server Actions — use a
  third-party form service (Formspree, Basin) or client-side fetch to an external API.
- **Content management:** For small teams, MDX files in `content/` directory are sufficient.
  For larger teams or frequent updates, integrate a headless CMS (Sanity, Contentful,
  Keystatic) with `generateStaticParams()` for static generation.
- **Image optimization:** Use `<Image>` from `next/image` for all images. Set explicit
  `width` and `height` to prevent layout shift. Use `priority` prop for above-the-fold hero image.
- **Analytics:** Use `next/script` with `strategy="afterInteractive"` for analytics scripts.
  Wrap tracking calls in `lib/analytics.ts` helper to support easy provider switching.
- **Fonts:** Use `next/font/google` or `next/font/local` for zero-layout-shift font loading.
  Define in root layout and apply via CSS variable.
- **Accessibility:** FAQ accordion must support keyboard navigation. Use `<details>/<summary>`
  for native HTML semantics or `@radix-ui/react-accordion` for enhanced behavior.
- **MailHog:** Docker Compose includes MailHog for testing email submissions in development.
  Access the web UI at http://localhost:8025.
