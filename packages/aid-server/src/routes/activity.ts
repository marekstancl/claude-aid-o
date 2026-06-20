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
 * Filtering (all optional, all AND-combined):
 *  - `project` — exact `projectId` match.
 *  - `topic`   — matches the event's `raw.topic` when present, else its `event`
 *    name; lets a client narrow to e.g. `gates` / `compliance` without the
 *    server fabricating a topic the source event never carried.
 *  - `limit`   — positive integer cap (default 100); applied AFTER sorting so
 *    the newest N events are returned.
 *
 * Never throws — a malformed query degrades to the unfiltered (still sorted +
 * capped) feed where sensible, and an invalid `project` value yields a 400.
 *
 * Module: src/routes/activity.ts
 */

import { Router } from 'express';
import type { ActivityEvent } from '@aid/contract';
import { sendOk, send400 } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';

/** Current time as an ISO 8601 string (scan marker for `meta`). */
function isoNow(): string {
  return new Date().toISOString();
}

/** Default cap on the number of returned events. */
const DEFAULT_LIMIT = 100;

/** Supplier of the current merged-activity snapshot (e.g. `scanner.getActivity`). */
export type ActivitySupplier = () => ActivityEvent[];

/** Parse a positive-integer `limit` query param, falling back to the default. */
function parseLimit(raw: unknown): number {
  if (typeof raw !== 'string') return DEFAULT_LIMIT;
  const n = parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_LIMIT;
}

/** True when the event matches the requested topic (raw.topic, else event name). */
function matchesTopic(event: ActivityEvent, topic: string): boolean {
  const rawTopic = typeof event.raw.topic === 'string' ? event.raw.topic : null;
  return rawTopic === topic || event.event === topic;
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

    let events = getActivity();
    if (project !== null) events = events.filter((e) => e.projectId === project);
    if (topic !== null) events = events.filter((e) => matchesTopic(e, topic));

    // Time-sorted DESCENDING by ts (newest first); empty/invalid ts sorts last.
    const sorted = [...events].sort((a, b) => (b.ts ?? '').localeCompare(a.ts ?? ''));
    const capped = sorted.slice(0, limit);

    sendOk(res, capped, {
      scannedAt: isoNow(),
      partialProjects: [],
      total: capped.length,
    });
  });

  return router;
}
