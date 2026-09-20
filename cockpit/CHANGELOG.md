# Changelog — AID Cockpit

All notable changes to the AID Cockpit packages are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/). Version: semver from `0.1.0`.

## [0.2.0] — Unreleased

### Added

- **Cockpit productization — managerial read-model (E-047-6 REOPEN, slice 1)** — the Brief is no longer a flat per-signal telemetry list. A new `managerial-model.ts` groups raw signal facts by **root cause** (`projectId:signal:concreteCheck|gate|reason`) into one `BriefItem` carrying human Czech `humanTitle`, `whatHappened`/`whyItMatters`/`whatBlocks`/`recommendedAction`/`nextActor`, `occurrenceCount` (distinct runs) + `affectedEpics[]`, `evidenceRefs[]`, and an **evidence-based `lifecycle`** (`active`/`stale`/`historical`/`resolved`/`unknown`). Archive status is evidence-based tri-state — an EPIC is `historical` only with explicit proof; unprovable archive + not-demonstrably-active → `unknown` (surfaced in a new `needsTriage` bucket, never a fake current blocker). `decisionsNeeded`/`blockers` are projections of ONE deduplicated set (decision > blocker precedence — no problem shown twice). `Brief.ecosystemLine` adds a one-line state summary. Binding spec: `docs/design/E-047-6-productization-addendum.md`.

### Changed

- **Screen G is a decision brief, not a telemetry dump** — leads with the ecosystem one-liner, then grouped decisions/blockers each showing impact + recommended action + next actor, lifecycle badges (e.g. "déle bez pohybu"), occurrence chips ("17 běhů · 3 EPIC"), a "Stav nejasný (k prověření)" section for `unknown`-lifecycle items, and long lists capped behind "Zobrazit vše". Raw identifiers (signal, rootCauseKey, evidence, flags) moved behind a per-item "technický detail" expander — no raw snake_case or `{placeholder}` on the managerial surface. Check ids render as Czech labels.

- **AID Cockpit Phase 6 UI completion — eight-screen live drill with A-G spine** — ScreenA (dashboard + activity + plans), ScreenB (project detail tabs), ScreenC (EPIC detail + run state), ScreenD (live activity feed + filter), ScreenE (compliance matrix/cards), ScreenF (help), ScreenG (landing brief), ScreenPlan (plan detail + AC/backlog/lessons); all eight screens wired to live WS epic-detail topic for keysForEvent-driven refresh, shared TabButton/FilterChip/SegButton components in common/, czechPlural utility, and BeforeInstallPromptEvent interface export; AC% honesty fix (null → "neměřeno" instead of 0% bar)
- **AID Cockpit frontend scaffold (Phase 5, Step 1)** — `@aid/gui` rebuilt as a read-only monitoring PWA on a Node-18-compatible toolchain: Vite 6 + Tailwind 4 + `vite-plugin-pwa@0.21.2` (`registerType:'autoUpdate'`, `NetworkOnly` runtime rule on `/api`, app-shell precache that never caches live AID data), light-theme web manifest (`theme_color:#0284c7`, `background_color:#f8fafc`) with 192/512/512-maskable PNG icons generated from `favicon.svg`, dev `server.proxy` forwarding `/api`+`/ws` to `:3911`, and `@aid/contract` consumed as a workspace dep
- **AID Cockpit frontend Phase 5 completion** — Seven-step scaffold → shell → data layer → lib/explain + FSM status → atoms → pipeline components → managerial components (BriefPanel, DecisionsNeededList, ChangedSinceList, PlanPhaseTimeline, AuditTrendChart, RawMarkdownDialog, PlanOutcomeTable with stem-primary honesty-convention null states)
- **AID Cockpit backend (Phases 1–4)** — @aid/contract package (RunDetail / EpicSummary / AuditSummary contracts), @aid/server with tolerant parsers (six-form blocking_findings, three-shape overall_score), ProjectScanner + two-tier cache (Tier-1 index, Tier-2 mtime-memoized), RunDetail builder (9+ read endpoints), read-only HTTP+WS server with hardened /file access and watcher fleet integration, and managerial read-model (brief/risk/audit/plan/lessons/metrics/memory/explanations with PlanOutcome analytics)

### Fixed

- **"Od poslední návštěvy" + backlog delta now persist** — the project (ScreenB) and plan (ScreenPlan) brief tabs gained an "Označit jako přečtené" writer that calls `setLastSeen`, and the plan backlog tab now calls `saveBacklogSnapshot` on acknowledge; previously both scopes only ever READ `lastSeen`/the snapshot and never wrote them, so the brief and backlog delta were stuck forever in first-visit mode.
- **Dění pause truly freezes the list** — pausing now snapshots the event source so new poll/WS events buffer (with an "N nových během pauzy" indicator) instead of prepending into the visible feed; the old impl only capped scroll height while newest-first rows kept appearing at the top.
- **Activity row deep-link anchors in Screen C** — Screen C now reads the `?ts=` query param a Dění row links to, opens directly on the Dění tab, scrolls to that event and highlights it; the param was emitted but never consumed, so the link always landed on the default FSM tab.
- **Node engine matches the runtime** — root `package.json` `engines.node` and `.nvmrc` corrected from `24` to `18`, matching the eco-dev host (Node 18.20.4), the plan §7.6 pin, and every build/verification this project actually runs on.
- **Mobile horizontal overflow** — the main content flex column gained `min-w-0` (+ `overflow-x-auto` on `<main>`) so wide tables/ids scroll internally instead of pushing the layout past a 390px viewport.
- **Plan-boundary EPIC selection** — `boundaryRunCoords` now picks the highest-step EPIC parsed from the id (`E-…-{step}_{total}`) rather than the last element of the server's status-weighted array, so P047 resolves to E-047-7_7, not whichever status sorts last.
- **File tree hides non-servable artifacts** — Screen C's raw-artifact tree now filters to the server's `/file` allow-list (mirrored client-side), so on-disk-but-not-allow-listed files (e.g. `epic_input.md`) are no longer offered as links that 404.
- **Help checkpoint labels corrected** — the Nápověda CheckpointStrip demo now labels CP2 as per-step, CP3 as integration (code-review + security), CP4 as curator validation, and CP6 as Fast-Mode-only, matching the real checkpoint roles.
- **Node-18 PWA build** — `npm run build` failed on Node 18.20.4 because `workbox-build@7.4.1` pulls `serialize-javascript@7` (Node-20-only, references a global `crypto`); pinned via root `overrides` to `serialize-javascript@6.0.2` (`require('crypto')`, no engine restriction). `vite-plugin-pwa` kept at `0.21.2` (latest 0.21.x resolving Vite 6 only). The npm optional-dependencies bug (npm 9.2.0) can omit `@tailwindcss/oxide-linux-x64-gnu`; if the build errors with "Cannot find native binding", run `npm i @tailwindcss/oxide-linux-x64-gnu --no-save` to restore it.

## [0.1.0] — 2026-06-19

### Added

- **Monorepo foundation** — npm-workspaces wiring for aid-contract/aid-server/aid-gui, independent of the plugin version registry
