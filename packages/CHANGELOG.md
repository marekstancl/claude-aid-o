# Changelog — AID Cockpit

All notable changes to the AID Cockpit packages are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/). Version: semver from `0.1.0`.

## [0.2.0] — Unreleased

### Added

- **AID Cockpit Phase 6 UI completion — eight-screen live drill with A-G spine** — ScreenA (dashboard + activity + plans), ScreenB (project detail tabs), ScreenC (EPIC detail + run state), ScreenD (live activity feed + filter), ScreenE (compliance matrix/cards), ScreenF (help), ScreenG (landing brief), ScreenPlan (plan detail + AC/backlog/lessons); all eight screens wired to live WS epic-detail topic for keysForEvent-driven refresh, shared TabButton/FilterChip/SegButton components in common/, czechPlural utility, and BeforeInstallPromptEvent interface export; AC% honesty fix (null → "neměřeno" instead of 0% bar)
- **AID Cockpit frontend scaffold (Phase 5, Step 1)** — `@aid/gui` rebuilt as a read-only monitoring PWA on a Node-18-compatible toolchain: Vite 6 + Tailwind 4 + `vite-plugin-pwa@0.21.2` (`registerType:'autoUpdate'`, `NetworkOnly` runtime rule on `/api`, app-shell precache that never caches live AID data), light-theme web manifest (`theme_color:#0284c7`, `background_color:#f8fafc`) with 192/512/512-maskable PNG icons generated from `favicon.svg`, dev `server.proxy` forwarding `/api`+`/ws` to `:3911`, and `@aid/contract` consumed as a workspace dep
- **AID Cockpit frontend Phase 5 completion** — Seven-step scaffold → shell → data layer → lib/explain + FSM status → atoms → pipeline components → managerial components (BriefPanel, DecisionsNeededList, ChangedSinceList, PlanPhaseTimeline, AuditTrendChart, RawMarkdownDialog, PlanOutcomeTable with stem-primary honesty-convention null states)
- **AID Cockpit backend (Phases 1–4)** — @aid/contract package (RunDetail / EpicSummary / AuditSummary contracts), @aid/server with tolerant parsers (six-form blocking_findings, three-shape overall_score), ProjectScanner + two-tier cache (Tier-1 index, Tier-2 mtime-memoized), RunDetail builder (9+ read endpoints), read-only HTTP+WS server with hardened /file access and watcher fleet integration, and managerial read-model (brief/risk/audit/plan/lessons/metrics/memory/explanations with PlanOutcome analytics)

### Fixed

- **Node-18 PWA build** — `npm run build` failed on Node 18.20.4 because `workbox-build@7.4.1` pulls `serialize-javascript@7` (Node-20-only, references a global `crypto`); pinned via root `overrides` to `serialize-javascript@6.0.2` (`require('crypto')`, no engine restriction). `vite-plugin-pwa` kept at `0.21.2` (latest 0.21.x resolving Vite 6 only). The npm optional-dependencies bug (npm 9.2.0) can omit `@tailwindcss/oxide-linux-x64-gnu`; if the build errors with "Cannot find native binding", run `npm i @tailwindcss/oxide-linux-x64-gnu --no-save` to restore it.

## [0.1.0] — 2026-06-19

### Added

- **Monorepo foundation** — npm-workspaces wiring for aid-contract/aid-server/aid-gui, independent of the plugin version registry
