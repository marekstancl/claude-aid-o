# Changelog — AID Cockpit

All notable changes to the AID Cockpit packages are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/). Version: semver from `0.1.0`.

## [0.2.0] — Unreleased

### Added

- **AID Cockpit backend (Phases 1–4)** — @aid/contract package (RunDetail / EpicSummary / AuditSummary contracts), @aid/server with tolerant parsers (six-form blocking_findings, three-shape overall_score), ProjectScanner + two-tier cache (Tier-1 index, Tier-2 mtime-memoized), RunDetail builder (9+ read endpoints), read-only HTTP+WS server with hardened /file access and watcher fleet integration, and managerial read-model (brief/risk/audit/plan/lessons/metrics/memory/explanations with PlanOutcome analytics)

## [0.1.0] — 2026-06-19

### Added

- **Monorepo foundation** — npm-workspaces wiring for aid-contract/aid-server/aid-gui, independent of the plugin version registry
