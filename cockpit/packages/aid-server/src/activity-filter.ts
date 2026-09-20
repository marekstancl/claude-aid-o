/**
 * Single source of truth for ActivityEvent filtering (EPIC E-047-3_7, Step 8).
 *
 * Both channels that surface the merged activity ring filter through THIS module
 * so REST and WS can never drift:
 *   - REST  `GET /api/activity` (src/routes/activity.ts) — bootstrap / 5s polling
 *     fallback when `/ws` is down (§7.3 / AC #9c).
 *   - WS    replay-on-subscribe (src/ws/websocket.ts) — the live `type:'replay'`
 *     frame sent on a new subscription.
 *
 * Because the polling fallback must be a COMPLETE WS-replay bootstrap source, the
 * REST `/activity` output has to be payload-shape-equal to the WS replay items
 * (identical {@link ActivityEvent} fields) with identical project + topic + limit
 * filtering. Sharing one helper is how that parity is guaranteed structurally
 * (per AID-v3 principle — no two copies that can diverge).
 *
 * Topic-filter semantics (IMPORTANT):
 *   {@link ActivityEvent} has NO top-level `topic` field. A topic filter matches
 *   an event when EITHER its `raw.topic` (when a string) OR its `event` name
 *   equals the requested topic. This same rule is applied in BOTH channels — the
 *   WS replay no longer ignores topic (it previously filtered by project only).
 *   Project filtering is an exact `projectId` match.
 *
 * Wildcard semantics (consistent with WS subscription intent):
 *   - empty / undefined `projects` → match ALL projects.
 *   - empty / undefined `topics`   → match ALL topics.
 * For a multi-valued filter an event matches when it matches ANY listed project
 * AND ANY listed topic (OR within a dimension, AND across dimensions). The REST
 * route passes at most one project and one topic, so this reduces to the single
 * `?project=&topic=` case; the WS subscription can carry several of each.
 *
 * Module: src/activity-filter.ts
 */

import type { ActivityEvent } from '@aid/contract';

/** Default cap on the number of returned events (REST `/activity` default). */
export const DEFAULT_ACTIVITY_LIMIT = 100;

/** Hard ceiling on `limit`; larger requests are CLAMPED (never rejected). */
export const MAX_ACTIVITY_LIMIT = 500;

/**
 * Normalised filter for {@link filterActivity}. Every field is optional; an
 * absent or empty array is the wildcard for that dimension.
 */
export interface ActivityFilter {
  /** Exact `projectId` matches (empty/undefined = all projects). */
  projects?: string[];
  /** Topic matches via `raw.topic` or `event` name (empty/undefined = all). */
  topics?: string[];
  /**
   * Positive integer cap on the returned count. Values above
   * {@link MAX_ACTIVITY_LIMIT} are CLAMPED to it (no error). Omit / non-positive
   * → no explicit cap is applied by this helper. The cap keeps the NEWEST `n`
   * events for either input ordering: a sorted-desc input keeps its head, an
   * oldest→newest input keeps its tail (see `keepNewest`).
   */
  limit?: number;
  /**
   * Ordering of `events` as supplied, so the limit cap can keep the NEWEST `n`
   * regardless of channel:
   *   - `'desc'` (default) — newest first; cap keeps the head (REST path).
   *   - `'asc'`            — oldest first; cap keeps the tail (WS replay path).
   */
  order?: 'asc' | 'desc';
}

/** True when the event's `projectId` exactly equals `project`. */
export function matchesProject(event: ActivityEvent, project: string): boolean {
  return event.projectId === project;
}

/**
 * True when the event matches the requested topic. ActivityEvent carries no
 * top-level `topic`, so we match `raw.topic` (when a string) OR the `event`
 * name. Applied identically by REST and WS replay.
 */
export function matchesTopic(event: ActivityEvent, topic: string): boolean {
  const rawTopic = typeof event.raw.topic === 'string' ? event.raw.topic : null;
  return rawTopic === topic || event.event === topic;
}

/** Clamp a requested limit into `[1, MAX_ACTIVITY_LIMIT]`; non-positive → undefined. */
export function clampLimit(limit: number | undefined): number | undefined {
  if (limit === undefined || !Number.isFinite(limit) || limit <= 0) {
    return undefined;
  }
  return Math.min(Math.trunc(limit), MAX_ACTIVITY_LIMIT);
}

/**
 * Filter (and optionally cap) a list of {@link ActivityEvent}s. The SINGLE code
 * path shared by REST `/activity` and the WS replay frame so the polling
 * fallback stays a complete bootstrap source.
 *
 * The input ORDER is preserved; this helper never sorts. When a `limit` is
 * given it keeps the NEWEST `n` events using `filter.order` to know which end is
 * newest, so a sorted-desc REST list and an oldest→newest WS list yield the
 * SAME set of events for the same `limit`. Project + topic matching is identical
 * across both channels.
 *
 * Pure: never mutates the input array or its elements.
 */
export function filterActivity(
  events: readonly ActivityEvent[],
  filter: ActivityFilter = {},
): ActivityEvent[] {
  const projects = filter.projects ?? [];
  const topics = filter.topics ?? [];

  const matched = events.filter((event) => {
    const projectOk =
      projects.length === 0 || projects.some((p) => matchesProject(event, p));
    const topicOk =
      topics.length === 0 || topics.some((t) => matchesTopic(event, t));
    return projectOk && topicOk;
  });

  const cap = clampLimit(filter.limit);
  if (cap === undefined) return matched;

  // Keep the NEWEST `cap` events, preserving input order. For a desc list the
  // newest are the head; for an asc list they are the tail.
  return filter.order === 'asc'
    ? matched.slice(Math.max(0, matched.length - cap))
    : matched.slice(0, cap);
}
