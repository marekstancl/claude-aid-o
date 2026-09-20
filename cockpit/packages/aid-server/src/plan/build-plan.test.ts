/**
 * Unit tests for the pure Plan builders (EPIC E-047-4_7, Step 7 — §13.6 / §5.4 /
 * §5.5 / SF4 / MF6).
 *
 * Covers the four-tier membership precedence (incl. the E-041 → orphan case),
 * the progress/AC roll-ups (`acPct:null` → fast-mode, never 0%), plan_duration,
 * the reporter-delivery existence check (a missing `_test_evidence` file →
 * exists:false + a warning, never dropped), and simplifier parsing.
 */

import { describe, it, expect } from 'vitest';
import type { AuditSummary, EpicSummary, LessonEntry } from '@aid/contract';
import {
  resolveMembership,
  buildPlanSummary,
  buildPlanDetail,
  buildReporterDelivery,
  buildSimplifierSummary,
  parseDeliveryOutcome,
  parseSimplifierProposals,
  rollupAcPct,
  rollupPlanDuration,
  type PlanBuildInput,
  type PlanMemberInput,
} from './build-plan.js';
import type { AggregateAudit } from '../audit/build-aggregate-audit.js';

// ---------------------------------------------------------------------------
// resolveMembership — four-tier precedence (§13.6)
// ---------------------------------------------------------------------------

describe('resolveMembership — four-tier precedence (§13.6)', () => {
  const exists = (n: string) => n === 'P046' || n === 'P038';

  it('tier-1: fsm-state plan_path wins when its plan file exists', () => {
    const r = resolveMembership(
      { epicId: 'E-038-1_1', planPath: '.aid-o/plans/P038-foo.md', planRef: null },
      exists,
    );
    expect(r.source).toBe('plan_path');
    expect(r.planNumber).toBe('P038');
  });

  it('tier-2: frontmatter plan_ref when no plan_path (authoritative)', () => {
    const r = resolveMembership(
      { epicId: 'E-046-3_3', planPath: null, planRef: '/abs/.aid-o/plans/P046-foo.md' },
      exists,
    );
    expect(r.source).toBe('plan_ref');
    expect(r.planNumber).toBe('P046');
  });

  it('tier-3: id-derived (E-{NNN} → P{NNN}) when a real plan file exists (weaker)', () => {
    const r = resolveMembership(
      { epicId: 'E-046-1_3', planPath: null, planRef: null },
      exists,
    );
    expect(r.source).toBe('derived');
    expect(r.planNumber).toBe('P046');
  });

  it('tier-4 (the E-041 trap): plan_ref → P041 but NO P041 file → orphan, never tier-2', () => {
    const r = resolveMembership(
      { epicId: 'E-041-1_3', planPath: null, planRef: '.aid-o/plans/P041-skill-instruction-audit.md' },
      exists, // P041 does NOT exist
    );
    expect(r.source).toBe('orphan');
    expect(r.planNumber).toBeNull();
  });

  it('tier-4: id-derived to a non-existent plan file → orphan', () => {
    const r = resolveMembership(
      { epicId: 'E-099-1_1', planPath: null, planRef: null },
      exists,
    );
    expect(r.source).toBe('orphan');
  });

  it('precedence: plan_path beats plan_ref when both resolve to real files', () => {
    const r = resolveMembership(
      { epicId: 'E-046-3_3', planPath: 'P038', planRef: 'P046' },
      exists,
    );
    expect(r.source).toBe('plan_path');
    expect(r.planNumber).toBe('P038');
  });
});

// ---------------------------------------------------------------------------
// Roll-ups (§5.4 / §5.5 / §5.1)
// ---------------------------------------------------------------------------

function member(over: Partial<PlanMemberInput> = {}): PlanMemberInput {
  return {
    epicId: over.epicId ?? 'E-046-1_3',
    membershipSource: over.membershipSource ?? 'derived',
    summary: over.summary ?? epicSummary(over.epicId ?? 'E-046-1_3'),
    latestRun: over.latestRun ?? {
      runId: 'R-1',
      state: 'DONE',
      startedAtMs: Date.parse('2026-06-18T14:04:10Z'),
      lastActivityMs: Date.parse('2026-06-18T15:00:00Z'),
    },
    ac: over.ac ?? null,
  };
}

function epicSummary(id: string, status = 'completed'): EpicSummary {
  return {
    projectId: 'aid-orchestrator',
    id,
    title: id,
    status,
    planRef: null,
    runsTotal: 1,
    runsCompleted: 1,
    latestRun: null,
    lastActivityAt: null,
  };
}

describe('roll-ups (§5.5 / §5.1)', () => {
  it('acPct is null when NO member measured ACs (fast mode), never 0%', () => {
    expect(rollupAcPct([member({ ac: null }), member({ epicId: 'E-046-2_3', ac: null })])).toBeNull();
  });

  it('acPct sums present/total across members that measured ACs', () => {
    expect(
      rollupAcPct([
        member({ ac: { present: 4, total: 5 } }),
        member({ epicId: 'E-046-2_3', ac: { present: 5, total: 5 } }),
      ]),
    ).toBe(90); // 9/10
  });

  it('plan_duration spans min start → max end across members; null when no anchors', () => {
    expect(
      rollupPlanDuration([
        member({ latestRun: { runId: 'R1', state: 'DONE', startedAtMs: 1000, lastActivityMs: 5000 } }),
        member({ epicId: 'E-2', latestRun: { runId: 'R2', state: 'DONE', startedAtMs: 3000, lastActivityMs: 9000 } }),
      ]),
    ).toBe(8); // (9000-1000)/1000
    expect(
      rollupPlanDuration([member({ latestRun: { runId: 'R1', state: 'DONE', startedAtMs: null, lastActivityMs: null } })]),
    ).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// buildPlanSummary / buildPlanDetail (P046-shaped fixture)
// ---------------------------------------------------------------------------

function emptyAudit(): AuditSummary {
  return {
    present: false, overallScore: null, scoreSource: null,
    blockingFindings: null, blockingFindingsSource: null,
    categories: [], topReasons: [], topRisks: [],
    countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 0 },
    autoFixableCount: 0, nextSteps: [], headlineCs: '',
    previousScoreHint: null, rawRelPath: 'audit-report.md', warnings: [],
  };
}

function p046Input(): PlanBuildInput {
  const boundary: AuditSummary = { ...emptyAudit(), present: true, overallScore: 84, scoreSource: 'frontmatter' };
  const aggregate: AggregateAudit = {
    ...emptyAudit(), present: true, overallScore: 89, scoreSource: 'table',
    scoredEpicCount: 3, medianEpicId: 'E-046-1_3',
  };
  const lessons: LessonEntry[] = [
    { date: '2026-06-18', lesson: 'membership reconciliation matters', epicId: 'E-046-1_3', kind: 'lesson' },
  ];
  return {
    projectId: 'aid-orchestrator',
    planId: 'P046-plan-boundary',
    title: 'P046',
    planRef: '.aid-o/plans/P046-plan-boundary.md',
    description: 'Plan boundary enforcement.',
    members: [
      member({ epicId: 'E-046-3_3', membershipSource: 'plan_ref', summary: epicSummary('E-046-3_3', 'active') }),
      member({ epicId: 'E-046-1_3', membershipSource: 'derived' }),
      member({ epicId: 'E-046-2_3', membershipSource: 'derived', summary: epicSummary('E-046-2_3') }),
    ],
    orphanEpicCount: 0,
    auditTrend: { scope: 'plan', points: [], scoredPointCount: 0, delta: null },
    allLessons: lessons,
    boundaryAudit: boundary,
    aggregateAudit: aggregate,
    deliveryReport: buildReporterDelivery({ present: false, text: null, rawRelPath: null, testEvidence: [] }),
    simplifierSummary: buildSimplifierSummary({ present: false, text: null, rawRelPath: null }),
    backlog: { items: [], openCount: 0, closedCount: 0, warnings: [] },
  };
}

describe('buildPlanSummary / buildPlanDetail (P046 fixture, AC #16/#19)', () => {
  it('summary: 3 members, mixed source, planId is the STEM (PM #1, stem-primary)', () => {
    const s = buildPlanSummary(p046Input());
    expect(s.planId).toBe('P046-plan-boundary');
    expect(s.epicMembers).toHaveLength(3);
    expect(s.membershipMixed).toBe(true);
    const byId = Object.fromEntries(s.epicMembers.map((m) => [m.epicId, m.membershipSource]));
    expect(byId['E-046-3_3']).toBe('plan_ref');
    expect(byId['E-046-1_3']).toBe('derived');
    expect(byId['E-046-2_3']).toBe('derived');
    expect(s.acPct).toBeNull(); // fast-mode → N/A, never 0
  });

  it('detail: boundary 84 vs aggregate 89 are DISTINCT (SF4)', () => {
    const d = buildPlanDetail(p046Input());
    expect(d.boundaryAudit.overallScore).toBe(84);
    expect(d.aggregateAudit.overallScore).toBe(89);
    expect(d.aggregateAudit.overallScore).not.toBe(d.boundaryAudit.overallScore);
  });

  it('detail: derived members carry a transparency warning (weaker grouping)', () => {
    const d = buildPlanDetail(p046Input());
    expect(d.warnings.some((w) => w.includes('E-046-1_3') && w.includes('podle čísla'))).toBe(true);
  });

  it('detail: lessons filtered to plan members', () => {
    const d = buildPlanDetail(p046Input());
    expect(d.lessons.total).toBe(1);
    expect(d.lessons.entries[0].epicId).toBe('E-046-1_3');
  });

  it('progress is done/total*100', () => {
    const d = buildPlanDetail(p046Input());
    expect(d.progressPct).toBe(100); // all DONE
  });
});

// ---------------------------------------------------------------------------
// Reporter delivery (MF6) — present:false + existence-check (AC #24)
// ---------------------------------------------------------------------------

describe('buildReporterDelivery (MF6, AC #24)', () => {
  it('present:false when no delivery report', () => {
    const d = buildReporterDelivery({ present: false, text: null, rawRelPath: null, testEvidence: [] });
    expect(d.present).toBe(false);
    expect(d.outcome).toBeNull();
    expect(d.testEvidence).toEqual([]);
  });

  it('parses _generated_by/_generated_at + outcome; passes evidence through', () => {
    const text = [
      '---',
      '_generated_by: aid-orchestrator:reporter@E-046-3_3',
      '_generated_at: "2026-06-19T08:00:00Z"',
      'test_outcome: pass',
      '---',
      '',
      '# Delivery',
      '',
      '## 1. Co bylo dodáno',
      '',
      'Dodali jsme plan-close a CI floor.',
    ].join('\n');
    const d = buildReporterDelivery({
      present: true,
      text,
      rawRelPath: 'reports/P046-delivery.md',
      testEvidence: [{ name: 'test-suite.txt', relPath: 'reporter/test-suite.txt', exists: true }],
    });
    expect(d.present).toBe(true);
    expect(d.generatedBy).toBe('aid-orchestrator:reporter@E-046-3_3');
    expect(d.generatedAt).toBe('2026-06-19T08:00:00Z');
    expect(d.outcome).toBe('pass');
    expect(d.summaryCs).toContain('plan-close');
    expect(d.warnings).toEqual([]);
  });

  it('a cited _test_evidence file missing on disk → exists:false + a warning, never dropped', () => {
    const text = '---\n_generated_by: x\ntest_outcome: no-runtime\n---\n# d\n';
    const d = buildReporterDelivery({
      present: true,
      text,
      rawRelPath: 'reports/P046-delivery.md',
      testEvidence: [
        { name: 'real.txt', relPath: 'reporter/real.txt', exists: true },
        { name: 'ghost.html', relPath: 'reporter/ghost.html', exists: false },
      ],
    });
    expect(d.testEvidence).toHaveLength(2); // never dropped
    expect(d.testEvidence.find((e) => e.name === 'ghost.html')!.exists).toBe(false);
    expect(d.warnings.some((w) => w.includes('chybí'))).toBe(true);
    // no-runtime is not pass/fail/partial → outcome null (never fabricated)
    expect(d.outcome).toBeNull();
  });

  it('parseDeliveryOutcome maps pass/fail/partial, null for anything else', () => {
    expect(parseDeliveryOutcome('outcome: pass')).toBe('pass');
    expect(parseDeliveryOutcome('outcome: FAIL')).toBe('fail');
    expect(parseDeliveryOutcome('test_outcome: partial')).toBe('partial');
    expect(parseDeliveryOutcome('test_outcome: no-runtime')).toBeNull();
    expect(parseDeliveryOutcome('nothing here')).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Simplifier (MF6)
// ---------------------------------------------------------------------------

describe('buildSimplifierSummary (MF6)', () => {
  it('present:false when no simplifier report', () => {
    const s = buildSimplifierSummary({ present: false, text: null, rawRelPath: null });
    expect(s.present).toBe(false);
    expect(s.proposalCount).toBe(0);
    expect(s.proposals).toEqual([]);
  });

  it('parses the real simplifier-report.md proposal shape (id/area/effort/disposition)', () => {
    const text = [
      '_generated_by: aid-orchestrator:simplifier@x',
      'simplifier_report:',
      '  proposals:',
      '    - id: "SMP-001"',
      '      title: "Regex duplicated across 4 surfaces"',
      '      area: "scripts/aid-cp1-gate.sh:107"',
      '      effort: L',
      '      recommended_disposition: defer',
      '    - id: "SMP-002"',
      '      title: "Three near-identical exit paths"',
      '      area: "scripts/aid-cp1-gate.sh:210-263"',
      '      effort: M',
      '      recommended_disposition: approve',
    ].join('\n');
    const s = buildSimplifierSummary({ present: true, text, rawRelPath: 'work/.../simplifier-report.md' });
    expect(s.present).toBe(true);
    expect(s.proposalCount).toBe(2);
    expect(s.proposals[0]).toMatchObject({ id: 'SMP-001', effort: 'L', disposition: 'defer' });
    expect(s.proposals[0].proposal).toContain('Regex duplicated');
    expect(s.proposals[1]).toMatchObject({ id: 'SMP-002', effort: 'M', disposition: 'approve' });
    expect(s.headlineCs).toContain('2');
  });

  it('parseSimplifierProposals tolerates a block-scalar rationale before effort', () => {
    const text = [
      '  proposals:',
      '    - id: "SMP-001"',
      '      title: "X"',
      '      rationale: >',
      '        a long multi-line rationale that should not break parsing',
      '      effort: S',
      '      recommended_disposition: reject',
    ].join('\n');
    const props = parseSimplifierProposals(text);
    expect(props).toHaveLength(1);
    expect(props[0]).toMatchObject({ id: 'SMP-001', effort: 'S', disposition: 'reject' });
  });
});
