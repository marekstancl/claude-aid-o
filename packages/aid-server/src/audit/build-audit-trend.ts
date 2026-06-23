/**
 * `AuditTrend` builder (EPIC E-047-4_7, Step 6 — §13.5.4).
 *
 * Score-over-time across runs (EPIC scope), member EPICs (plan scope), or audited
 * EPICs (project scope), assembled from per-point {@link AuditTrendPoint}s and
 * ordered by run `started_at`. The honesty contract (§13.5.4 / §13.5.6 #3):
 *
 *   - **Ordering key = `started_at`** (§5.1 anchor family), NOT lexicographic
 *     run-id, NOT report mtime. On the E-046 trio `started_at` 14:04:10 <
 *     14:04:24 < 14:04:37 → the chart order is **89 → 95 → 84**. When `started_at`
 *     is unparseable, the route falls back to the run-dir mtime BEFORE building
 *     the point (the fallback value still lands in `point.startedAt`), and the
 *     point's enclosing summary carries the warning; here a point whose
 *     `startedAt` is still null sorts LAST (deterministically, by runId) so it is
 *     never silently dropped.
 *   - **Gaps are gaps, never interpolated.** A run/EPIC with no parseable score is
 *     kept as a point with `score:null` — never dropped, never interpolated.
 *     `scoredPointCount` counts only points that actually carry a number.
 *   - **`delta` = last scored − first scored** (in chronological order); `null`
 *     when fewer than two scored points exist. On the E-046 EPIC: first scored 89,
 *     last scored 84 → `delta: -5`.
 *
 * Pure projection over already-built points; no disk reads, no new source of
 * truth, no writes (SF2). Never throws — an empty input yields the honest
 * empty-but-shaped trend (`points:[], scoredPointCount:0, delta:null`).
 *
 * Module: src/audit/build-audit-trend.ts
 */

import type { AuditTrend, AuditTrendPoint } from '@aid/contract';

/** Parse a point's `startedAt` to epoch ms, or null when absent/unparseable. */
function startedAtMs(point: AuditTrendPoint): number | null {
  if (point.startedAt === null) return null;
  const ms = Date.parse(point.startedAt);
  return Number.isNaN(ms) ? null : ms;
}

/**
 * Order points chronologically by run `started_at` (ascending) — the §13.5.4
 * ordering key. A point whose `startedAt` is unparseable/null sorts AFTER every
 * point that has a real timestamp (it could not be placed in time); equal keys
 * (and the null group) break ties deterministically by `runId` then `epicId` so
 * the result is stable regardless of input order. NEVER lexicographic on run-id
 * as the primary key, NEVER report mtime. Pure; returns a new array.
 */
export function orderByStartedAt(points: readonly AuditTrendPoint[]): AuditTrendPoint[] {
  return [...points].sort((a, b) => {
    const ta = startedAtMs(a);
    const tb = startedAtMs(b);
    // A real timestamp always precedes a null one (null = unplaceable → last).
    if (ta === null && tb !== null) return 1;
    if (ta !== null && tb === null) return -1;
    if (ta !== null && tb !== null && ta !== tb) return ta - tb;
    // Equal timestamps (or both null) → deterministic id tiebreak.
    const byRun = a.runId.localeCompare(b.runId);
    if (byRun !== 0) return byRun;
    return a.epicId.localeCompare(b.epicId);
  });
}

/**
 * Build the {@link AuditTrend} from a set of {@link AuditTrendPoint}s.
 *
 * Points are ordered by run `started_at` ({@link orderByStartedAt}); score gaps
 * (`score:null`) are KEPT in place (never dropped, never interpolated);
 * `scoredPointCount` counts only points carrying a real number; `delta` is the
 * last scored minus the first scored point in chronological order, or `null` when
 * fewer than two scored points exist (§13.5.4). Pure; never throws.
 *
 * @param points the per-run / per-EPIC trend points (the route assembles these,
 *   resolving the mtime fallback for an unparseable `started_at` first).
 * @param scope  `'epic' | 'plan' | 'project'` — recorded verbatim on the result.
 */
export function buildAuditTrend(
  points: readonly AuditTrendPoint[],
  scope: AuditTrend['scope'],
): AuditTrend {
  const ordered = orderByStartedAt(points);

  // Real scored points, in chronological order — gaps (score:null) excluded from
  // the count and the delta, but KEPT as points in `ordered` (§13.5.6 #3).
  const scored = ordered.filter((p): p is AuditTrendPoint & { score: number } =>
    typeof p.score === 'number',
  );
  const scoredPointCount = scored.length;

  // delta = last scored − first scored; null until ≥2 real scored points exist.
  const delta =
    scoredPointCount >= 2
      ? scored[scoredPointCount - 1].score - scored[0].score
      : null;

  return { scope, points: ordered, scoredPointCount, delta };
}
