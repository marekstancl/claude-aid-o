/**
 * Unit tests for the pure Plan Outcome Analytics builders (EPIC E-047-4_7,
 * Step 7 — §13.12, AC #25).
 *
 * Covers every classification branch, the honesty invariants (missing proof
 * never passes; unknown CP repeats never folded to zero), the attention-first
 * sort, totals reconciliation, and the filter validators.
 */

import { describe, it, expect } from 'vitest';
import {
  classifyPlanOutcome,
  buildPlanOutcomeSummary,
  buildPlanOutcomeAnalytics,
  comparePlanRow,
  reconcileTotals,
  filterOutcomeRows,
  isValidOutcome,
  isValidSince,
  type OutcomePlanInput,
  type OutcomeMemberRun,
} from './build-plan-outcomes.js';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function member(over: Partial<OutcomeMemberRun> = {}): OutcomeMemberRun {
  // Use `in`-checks so explicit `null` overrides (ac/state/gateFinal/compliance)
  // are honored — `?? default` would silently restore the default on null.
  return {
    epicId: over.epicId ?? 'E-001-1_1',
    runId: over.runId ?? 'R-1',
    format: over.format ?? 'v3',
    state: 'state' in over ? (over.state ?? null) : 'DONE',
    ac: 'ac' in over ? (over.ac ?? null) : { present: 5, total: 5 },
    gateFinal: 'gateFinal' in over ? (over.gateFinal ?? null) : 'pass',
    compliance: 'compliance' in over ? (over.compliance ?? null) : 'pass',
  };
}

function plan(over: Partial<OutcomePlanInput> = {}): OutcomePlanInput {
  return {
    projectId: over.projectId ?? 'projA',
    planId: over.planId ?? 'P001',
    title: over.title ?? 'Plan One',
    members: over.members ?? [member()],
    epicsTotal: over.epicsTotal ?? 1,
    epicsDone: over.epicsDone ?? 1,
    runsTotal: over.runsTotal ?? 1,
    failedRuns: over.failedRuns ?? 0,
    gateFailures: over.gateFailures ?? 0,
    gateRetries: over.gateRetries ?? 0,
    checkpointRetries: over.checkpointRetries ?? { knownTotal: 0, unknownCheckpoints: 0 },
    fsmFailures: over.fsmFailures ?? { precondition: 0, increment: 0, doneAdvance: 0, other: 0 },
    escalations: over.escalations ?? 0,
    forceOverrides: over.forceOverrides ?? 0,
    compliance: over.compliance ?? { passed: 1, failed: 0, unknown: 0 },
    topFailureReasons: over.topFailureReasons ?? [],
    reporterOutcome: over.reporterOutcome ?? null,
    firstStartedAt: over.firstStartedAt ?? '2026-06-01T00:00:00Z',
    lastCompletedAt: over.lastCompletedAt ?? '2026-06-02T00:00:00Z',
    lastActivityAt: over.lastActivityAt ?? '2026-06-02T00:00:00Z',
  };
}

// ---------------------------------------------------------------------------
// classifyPlanOutcome — all 5 branches (binding precedence)
// ---------------------------------------------------------------------------

describe('classifyPlanOutcome — five branches (§13.12)', () => {
  it('branch 1: failed — a member run is ERROR', () => {
    const r = classifyPlanOutcome(plan({ members: [member({ state: 'ERROR' })] }));
    expect(r.outcome).toBe('failed');
  });

  it('branch 1: failed — final gate fails', () => {
    const r = classifyPlanOutcome(plan({ members: [member({ gateFinal: 'fail' })] }));
    expect(r.outcome).toBe('failed');
  });

  it('branch 1: failed — compliance fails (E-042 verifier_provenance shape)', () => {
    const r = classifyPlanOutcome(
      plan({ members: [member({ compliance: 'fail' })], compliance: { passed: 0, failed: 1, unknown: 0 } }),
    );
    expect(r.outcome).toBe('failed');
  });

  it('branch 1: failed — plan-boundary Reporter says fail', () => {
    const r = classifyPlanOutcome(plan({ reporterOutcome: 'fail' }));
    expect(r.outcome).toBe('failed');
  });

  it('branch 2: passed — every member DONE + AC 100% + gates pass + compliance pass', () => {
    const r = classifyPlanOutcome(
      plan({ members: [member(), member({ epicId: 'E-001-2_2', runId: 'R-2' })] }),
    );
    expect(r.outcome).toBe('passed');
    expect(r.dataPartial).toBe(false);
  });

  it('branch 2 honesty: missing proof can NEVER pass — AC not measured → not passed', () => {
    const r = classifyPlanOutcome(plan({ members: [member({ ac: null })] }));
    expect(r.outcome).not.toBe('passed');
  });

  it('branch 2 honesty: AC measured but < 100% → not passed', () => {
    const r = classifyPlanOutcome(plan({ members: [member({ ac: { present: 3, total: 5 } })] }));
    expect(r.outcome).not.toBe('passed');
  });

  it('branch 3: in_progress — a non-terminal member, no explicit failure', () => {
    const r = classifyPlanOutcome(
      plan({ members: [member({ state: 'EXECUTE' }), member({ epicId: 'E-001-2_2' })] }),
    );
    expect(r.outcome).toBe('in_progress');
  });

  it('branch 3: ESCALATION counts as in_progress (escalations still counted)', () => {
    const r = classifyPlanOutcome(plan({ members: [member({ state: 'ESCALATION' })], escalations: 2 }));
    expect(r.outcome).toBe('in_progress');
  });

  it('branch 4: partial — one member fully passed, another known incomplete', () => {
    const r = classifyPlanOutcome(
      plan({
        members: [
          member({ epicId: 'E-001-1_2' }), // passed
          member({ epicId: 'E-001-2_2', runId: 'R-2', state: 'DONE', ac: { present: 2, total: 5 } }), // incomplete AC
        ],
      }),
    );
    expect(r.outcome).toBe('partial');
  });

  it('branch 5: unverifiable — legacy member, no defensible proof', () => {
    const r = classifyPlanOutcome(
      plan({ members: [member({ format: 'legacy', state: null, ac: null, gateFinal: null, compliance: null })] }),
    );
    expect(r.outcome).toBe('unverifiable');
    expect(r.dataPartial).toBe(true);
  });

  it('branch 5: unverifiable — stub run', () => {
    const r = classifyPlanOutcome(
      plan({ members: [member({ format: 'stub', state: null, ac: null, gateFinal: null, compliance: null })] }),
    );
    expect(r.outcome).toBe('unverifiable');
  });
});

// ---------------------------------------------------------------------------
// Honesty: unknown CP repeats are NEVER folded to zero (AC #25)
// ---------------------------------------------------------------------------

describe('honesty — unknown checkpoints never zeroed (AC #25)', () => {
  it('known + unknown CP repeats both survive into the summary', () => {
    const summary = buildPlanOutcomeSummary(
      plan({ checkpointRetries: { knownTotal: 3, unknownCheckpoints: 4 } }),
    );
    expect(summary.checkpointRetries.knownTotal).toBe(3);
    expect(summary.checkpointRetries.unknownCheckpoints).toBe(4);
    expect(summary.checkpointRetries.unknownCheckpoints).not.toBe(0);
  });

  it('unknown CP repeats force dataPartial:true and block a passed verdict', () => {
    const r = classifyPlanOutcome(
      plan({ checkpointRetries: { knownTotal: 0, unknownCheckpoints: 2 } }),
    );
    expect(r.dataPartial).toBe(true);
    expect(r.outcome).not.toBe('passed');
  });

  it('an all-pass plan with unknown CPs degrades to unverifiable (not passed)', () => {
    const r = classifyPlanOutcome(
      plan({ members: [member()], checkpointRetries: { knownTotal: 0, unknownCheckpoints: 1 } }),
    );
    expect(r.outcome).toBe('unverifiable');
  });
});

// ---------------------------------------------------------------------------
// Sort + totals
// ---------------------------------------------------------------------------

describe('buildPlanOutcomeAnalytics — sort + reconcile', () => {
  it('sorts attention-first then lastActivityAt desc', () => {
    const analytics = buildPlanOutcomeAnalytics(
      [
        plan({ planId: 'PA', members: [member()], lastActivityAt: '2026-01-01T00:00:00Z' }), // passed
        plan({ planId: 'PB', members: [member({ state: 'ERROR' })], lastActivityAt: '2026-01-01T00:00:00Z' }), // failed
        plan({ planId: 'PC', members: [member({ state: 'EXECUTE' })], lastActivityAt: '2026-06-01T00:00:00Z' }), // in_progress
        plan({
          planId: 'PD',
          members: [member({ format: 'stub', state: null, ac: null, gateFinal: null, compliance: null })],
          lastActivityAt: '2026-03-01T00:00:00Z',
        }), // unverifiable
      ],
      '2026-06-20T00:00:00Z',
    );
    expect(analytics.plans.map((p) => p.outcome)).toEqual([
      'failed',
      'in_progress',
      'unverifiable',
      'passed',
    ]);
  });

  it('newest activity wins within the same outcome', () => {
    const a = buildPlanOutcomeSummary(plan({ planId: 'PX', members: [member({ state: 'ERROR' })], lastActivityAt: '2026-05-01T00:00:00Z' }));
    const b = buildPlanOutcomeSummary(plan({ planId: 'PY', members: [member({ state: 'ERROR' })], lastActivityAt: '2026-06-01T00:00:00Z' }));
    expect(comparePlanRow(a, b)).toBeGreaterThan(0); // b (newer) sorts first
  });

  it('totals reconcile EXACTLY to the rows', () => {
    const analytics = buildPlanOutcomeAnalytics(
      [
        plan({ planId: 'P1', members: [member()] }), // passed
        plan({ planId: 'P2', members: [member({ state: 'ERROR' })], failedRuns: 1 }), // failed
        plan({ planId: 'P3', members: [member({ state: 'GATES' })] }), // in_progress
      ],
      'now',
    );
    expect(analytics.totals.plans).toBe(3);
    expect(analytics.totals.passed).toBe(1);
    expect(analytics.totals.failed).toBe(1);
    expect(analytics.totals.inProgress).toBe(1);
    const sum =
      analytics.totals.passed +
      analytics.totals.partial +
      analytics.totals.failed +
      analytics.totals.inProgress +
      analytics.totals.unverifiable;
    expect(sum).toBe(analytics.totals.plans);
  });

  it('partialProjects is sorted + unique', () => {
    const analytics = buildPlanOutcomeAnalytics(
      [
        plan({ projectId: 'zeta', planId: 'P1', members: [member({ format: 'stub', state: null, ac: null, gateFinal: null, compliance: null })] }),
        plan({ projectId: 'alpha', planId: 'P2', members: [member({ format: 'legacy', state: null, ac: null, gateFinal: null, compliance: null })] }),
        plan({ projectId: 'alpha', planId: 'P3', members: [member({ format: 'stub', state: null, ac: null, gateFinal: null, compliance: null })] }),
      ],
      'now',
    );
    expect(analytics.partialProjects).toEqual(['alpha', 'zeta']);
  });
});

// ---------------------------------------------------------------------------
// Filters + validators
// ---------------------------------------------------------------------------

describe('filters + validators', () => {
  it('isValidOutcome accepts only the five enum values', () => {
    for (const v of ['passed', 'partial', 'failed', 'in_progress', 'unverifiable']) {
      expect(isValidOutcome(v)).toBe(true);
    }
    expect(isValidOutcome('bogus')).toBe(false);
    expect(isValidOutcome('PASSED')).toBe(false);
  });

  it('isValidSince accepts ISO timestamps, rejects junk', () => {
    expect(isValidSince('2026-06-01T00:00:00Z')).toBe(true);
    expect(isValidSince('not-a-date')).toBe(false);
    expect(isValidSince('')).toBe(false);
  });

  it('filterOutcomeRows applies the outcome filter', () => {
    const rows = [
      buildPlanOutcomeSummary(plan({ planId: 'P1', members: [member({ state: 'ERROR' })] })),
      buildPlanOutcomeSummary(plan({ planId: 'P2', members: [member()] })),
    ];
    const failed = filterOutcomeRows(rows, { outcome: 'failed' });
    expect(failed).toHaveLength(1);
    expect(failed[0].outcome).toBe('failed');
  });

  it('filterOutcomeRows applies the since lower bound on lastActivityAt', () => {
    const rows = [
      buildPlanOutcomeSummary(plan({ planId: 'P1', members: [member()], lastActivityAt: '2026-01-01T00:00:00Z' })),
      buildPlanOutcomeSummary(plan({ planId: 'P2', members: [member()], lastActivityAt: '2026-06-01T00:00:00Z' })),
    ];
    const recent = filterOutcomeRows(rows, { since: '2026-03-01T00:00:00Z' });
    expect(recent.map((r) => r.planId)).toEqual(['P2']);
  });

  it('reconcileTotals over a filtered subset matches the subset', () => {
    const rows = [
      buildPlanOutcomeSummary(plan({ planId: 'P1', members: [member({ state: 'ERROR' })] })),
    ];
    const t = reconcileTotals(rows);
    expect(t.plans).toBe(1);
    expect(t.failed).toBe(1);
  });
});
