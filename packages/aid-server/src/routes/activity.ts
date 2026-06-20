/**
 * Merged cross-project activity feed route (EPIC E-047-3_7, Step 7).
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api` by the bootstrap:
 *   - `GET /api/activity?project=<id>&topic=<t>&limit=<n>` → `ActivityEvent[]`,
 *     merged across all projects, TIME-SORTED DESCENDING by `ts` (newest first),
 *     capped at `limit`.
 *
 * The feed is read from the cache's bounded merged-activity ring via an injected
 * supplier (`() => ActivityEvent[]`) so the route stays decoupled from the cache
 * internals and is trivially testable with a fixed event list.
 *
 * Filtering (all optional, all AND-combined) — applied through the SHARED
 * {@link filterActivity} helper (`src/activity-filter.ts`) so this REST feed and
 * the WS replay frame can never drift; the REST output is therefore a complete
 * WS-replay bootstrap source for the 5s polling fallback (§7.3 / AC #9c):
 *  - `project` — exact `projectId` match.
 *  - `topic`   — matches the event's `raw.topic` when present, else its `event`
 *    name; lets a client narrow to e.g. `gates` / `compliance` without the
 *    server fabricating a topic the source event never carried.
 *  - `limit`   — positive integer cap (default 100, hard ceiling 500); applied
 *    AFTER sorting so the newest N events are returned. A `limit` above 500 is
 *    CLAMPED to 500 (HTTP 200, never a 400).
 *
 * Never throws — a malformed query degrades to the unfiltered (still sorted +
 * capped) feed where sensible, and an invalid `project` value yields a 400.
 *
 * Module: src/routes/activity.ts
 */

import { Router } from 'express';
import type { ActivityEvent } from '@aid/contract';
import { sendOk, send400, isoNow } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import {
  filterActivity,
  clampLimit,
  DEFAULT_ACTIVITY_LIMIT,
} from '../activity-filter.js';

/** Supplier of the current merged-activity snapshot (e.g. `scanner.getActivity`). */
export type ActivitySupplier = () => ActivityEvent[];

/**
 * Parse a positive-integer `limit` query param, falling back to the default.
 * The hard 500 ceiling is enforced downstream by {@link clampLimit} (clamp, not
 * reject), so an over-large `limit` still returns 200.
 */
function parseLimit(raw: unknown): number {
  if (typeof raw !== 'string') return DEFAULT_ACTIVITY_LIMIT;
  const n = parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_ACTIVITY_LIMIT;
}

/**
 * Build the merged-activity read router. `getActivity` supplies the current ring
 * snapshot (the bootstrap passes `() => scanner.getActivity()`).
 */
export function activityRoutes(getActivity: ActivitySupplier): Router {
  const router = Router();

  // -------------------------------------------------------------------------
  // GET /activity?project=&topic=&limit= — merged, time-sorted desc, capped.
  // -------------------------------------------------------------------------
  router.get('/activity', (req, res) => {
    const projectRaw = req.query.project;
    const project = typeof projectRaw === 'string' && projectRaw.length > 0 ? projectRaw : null;
    if (project !== null && !isValidPathComponent(project)) {
      send400(res, 'Query param "project" must be a valid path component');
      return;
    }

    const topic = typeof req.query.topic === 'string' && req.query.topic.length > 0
      ? req.query.topic
      : null;
    const limit = parseLimit(req.query.limit);

    // Project + topic filtering via the SHARED helper (identical to WS replay).
    // No limit here: we sort first, then cap, so the newest N survive.
    const filtered = filterActivity(getActivity(), {
      projects: project !== null ? [project] : [],
      topics: topic !== null ? [topic] : [],
    });

    // Time-sorted DESCENDING by ts (newest first); empty/invalid ts sorts last.
    const sorted = [...filtered].sort((a, b) => (b.ts ?? '').localeCompare(a.ts ?? ''));
    // Clamp the limit to the hard ceiling (no 400) and keep the newest N (head).
    const capped = sorted.slice(0, clampLimit(limit) ?? DEFAULT_ACTIVITY_LIMIT);

    sendOk(res, capped, {
      scannedAt: isoNow(),
      partialProjects: [],
      total: capped.length,
    });
  });

  return router;
}
