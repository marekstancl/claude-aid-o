/**
 * `AuditTrend` builder test suite (EPIC E-047-4_7, Step 6 — §13.5.4 / §13.5.6 #3).
 *
 * The trend orders points by run `started_at` (NOT lexicographic run-id, NOT
 * report mtime), keeps score-less runs as `score:null` gaps (never dropped, never
 * interpolated), counts only real scored points, and computes `delta` (last −
 * first scored) only when ≥2 scored points exist. The flagship fixture is the
 * E-046 trio: started_at 14:04:10 (89) < 14:04:24 (95) < 14:04:37 (84) → ordered
 * 89,95,84, scoredPointCount 3, delta -5 (AC #18).
 */

import { describe, expect, it } from 'vitest';
import type { AuditTrendPoint } from '@aid/contract';
import { buildAuditTrend, orderByStartedAt } from './build-audit-trend.js';

/** A trend point with sensible defaults; override what a case cares about. */
function point(p: Partial<AuditTrendPoint> & { runId: string }): AuditTrendPoint {
  return {
    runId: p.runId,
    epicId: p.epicId ?? 'E-046',
    startedAt: p.startedAt ?? null,
    score: p.score ?? null,
    blockingFindings: p.blockingFindings ?? null,
  };
}

// The E-046 trio — deliberately shuffled so a correct sort must reorder them.
const E046_TRIO: AuditTrendPoint[] = [
  point({ runId: 'R-E046-3', epicId: 'E-046-3_3', startedAt: '2026-06-18T14:04:37Z', score: 84 }),
  point({ runId: 'R-E046-1', epicId: 'E-046-1_3', startedAt: '2026-06-18T14:04:10Z', score: 89 }),
  point({ runId: 'R-E046-2', epicId: 'E-046-2_3', startedAt: '2026-06-18T14:04:24Z', score: 95 }),
];

describe('buildAuditTrend — ordering by started_at (AC #1 / #18)', () => {
  it('orders the E-046 trio 89 → 95 → 84 by started_at (NOT run-id, NOT mtime)', () => {
    const trend = buildAuditTrend(E046_TRIO, 'epic');
    expect(trend.points.map((p) => p.score)).toEqual([89, 95, 84]);
    expect(trend.points.map((p) => p.runId)).toEqual(['R-E046-1', 'R-E046-2', 'R-E046-3']);
    expect(trend.scoredPointCount).toBe(3);
    expect(trend.delta).toBe(-5); // 84 − 89
    expect(trend.scope).toBe('epic');
  });

  it('does NOT order lexicographically by run-id (R-005-4_4-1 vs run_2026…)', () => {
    // A lexicographic sort would put "R-005…" before "run_2026…"; started_at must
    // override that — the later-started run comes last regardless of its id string.
    const points = [
      point({ runId: 'run_20260224_115f', startedAt: '2026-02-24T11:00:00Z', score: 70 }),
      point({ runId: 'R-005-4_4-1', startedAt: '2026-02-25T11:00:00Z', score: 80 }),
    ];
    const trend = buildAuditTrend(points, 'epic');
    expect(trend.points.map((p) => p.runId)).toEqual(['run_20260224_115f', 'R-005-4_4-1']);
    expect(trend.delta).toBe(10);
  });

  it('orderByStartedAt is stable for equal timestamps (runId tiebreak)', () => {
    const points = [
      point({ runId: 'R-b', startedAt: '2026-06-18T14:04:10Z', score: 1 }),
      point({ runId: 'R-a', startedAt: '2026-06-18T14:04:10Z', score: 2 }),
    ];
    expect(orderByStartedAt(points).map((p) => p.runId)).toEqual(['R-a', 'R-b']);
  });
});

describe('buildAuditTrend — gaps kept null, never interpolated (AC #2)', () => {
  it('keeps a score-less run as a point with score:null between scored points', () => {
    const points = [
      point({ runId: 'R-1', startedAt: '2026-06-18T14:00:00Z', score: 89 }),
      point({ runId: 'R-2', startedAt: '2026-06-18T14:05:00Z', score: null }), // gap
      point({ runId: 'R-3', startedAt: '2026-06-18T14:10:00Z', score: 84 }),
    ];
    const trend = buildAuditTrend(points, 'epic');
    // The gap is KEPT in place — three points, the middle one null.
    expect(trend.points.map((p) => p.score)).toEqual([89, null, 84]);
    expect(trend.points).toHaveLength(3);
    // Counted: only the two real points; delta uses them, NOT the gap.
    expect(trend.scoredPointCount).toBe(2);
    expect(trend.delta).toBe(-5);
  });

  it('a score-less run is never dropped and never interpolated to a number', () => {
    const points = [point({ runId: 'R-1', startedAt: '2026-06-18T14:00:00Z', score: null })];
    const trend = buildAuditTrend(points, 'epic');
    expect(trend.points).toHaveLength(1);
    expect(trend.points[0].score).toBeNull();
    expect(trend.scoredPointCount).toBe(0);
  });
});

describe('buildAuditTrend — delta honesty (AC #3 / §13.5.6 #3)', () => {
  it('delta is null with fewer than 2 scored points (one scored)', () => {
    const points = [
      point({ runId: 'R-1', startedAt: '2026-06-18T14:00:00Z', score: 89 }),
      point({ runId: 'R-2', startedAt: '2026-06-18T14:05:00Z', score: null }),
    ];
    const trend = buildAuditTrend(points, 'epic');
    expect(trend.scoredPointCount).toBe(1);
    expect(trend.delta).toBeNull();
  });

  it('delta is null with zero scored points', () => {
    const trend = buildAuditTrend(
      [point({ runId: 'R-1', startedAt: '2026-06-18T14:00:00Z', score: null })],
      'epic',
    );
    expect(trend.delta).toBeNull();
  });

  it('delta uses chronological first/last scored, not input order', () => {
    // Shuffled input; chronological scored order is 89 (first) … 84 (last).
    const trend = buildAuditTrend(E046_TRIO, 'epic');
    expect(trend.delta).toBe(-5);
  });
});

describe('buildAuditTrend — unparseable / null started_at fallback (AC #4)', () => {
  it('a point whose started_at is null sorts LAST and is still PLACED', () => {
    const points = [
      point({ runId: 'R-2', startedAt: null, score: 84 }), // unplaceable in time
      point({ runId: 'R-1', startedAt: '2026-06-18T14:00:00Z', score: 89 }),
    ];
    const trend = buildAuditTrend(points, 'epic');
    expect(trend.points.map((p) => p.runId)).toEqual(['R-1', 'R-2']);
    expect(trend.points).toHaveLength(2); // never dropped
    expect(trend.scoredPointCount).toBe(2);
  });

  it('an unparseable started_at string is treated as null (sorts last)', () => {
    const points = [
      point({ runId: 'R-bad', startedAt: 'not-a-date', score: 50 }),
      point({ runId: 'R-good', startedAt: '2026-06-18T14:00:00Z', score: 90 }),
    ];
    const trend = buildAuditTrend(points, 'epic');
    expect(trend.points.map((p) => p.runId)).toEqual(['R-good', 'R-bad']);
  });
});

describe('buildAuditTrend — empty + scope (AC #6)', () => {
  it('zero points → points:[], scoredPointCount:0, delta:null, scope preserved', () => {
    const trend = buildAuditTrend([], 'project');
    expect(trend.points).toEqual([]);
    expect(trend.scoredPointCount).toBe(0);
    expect(trend.delta).toBeNull();
    expect(trend.scope).toBe('project');
  });

  it('records the requested scope verbatim (epic | plan | project)', () => {
    expect(buildAuditTrend([], 'epic').scope).toBe('epic');
    expect(buildAuditTrend([], 'plan').scope).toBe('plan');
    expect(buildAuditTrend([], 'project').scope).toBe('project');
  });

  it('is pure — does not mutate the input array order', () => {
    const input = [...E046_TRIO];
    const snapshot = input.map((p) => p.runId);
    buildAuditTrend(input, 'epic');
    expect(input.map((p) => p.runId)).toEqual(snapshot);
  });
});
