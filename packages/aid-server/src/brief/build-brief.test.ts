/**
 * Managerial `Brief` projection tests — spec §13.1-§13.4 (EPIC E-047-4_7 Step 4).
 *
 * Pure-function coverage of buildBrief over assembled run sets. The route-level
 * integration (real fixture tree, supertest) lives in routes/brief.test.ts.
 *
 * AC matrix:
 *   AC1  — infra brief: scope:'infra', probability {null,null}, blockers/decisions
 *          sorted blocking→warn→info across all projects
 *   AC2  — value===null && source===null on EVERY scope (MVP1 invariant)
 *   AC3  — no since → sinceLastSeen {since:null, items:[]} (first visit)
 *   AC4  — infra risk = worst across DETERMINABLE projects; neurceno listed in
 *          reasons, NEVER lowering the level
 *   AC6  — every BriefItem.explanation resolves via explain() over a real key
 */

import { describe, it, expect } from 'vitest';
import type {
  AuditSummary,
  ComplianceRun,
  GateResult,
  RunDetail,
} from '@aid/contract';
import {
  buildBrief,
  collectFacts,
  buildSinceLastSeen,
  extractRiskSignals,
  infraRisk,
  type BriefRunMember,
  type BriefRunSet,
} from './build-brief.js';

const GENERATED_AT = '2026-06-20T12:00:00.000Z';

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

function emptyAudit(overrides: Partial<AuditSummary> = {}): AuditSummary {
  return {
    present: false,
    overallScore: null,
    scoreSource: null,
    blockingFindings: null,
    blockingFindingsSource: null,
    categories: [],
    topReasons: [],
    topRisks: [],
    countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 0 },
    autoFixableCount: 0,
    nextSteps: [],
    headlineCs: '',
    previousScoreHint: null,
    rawRelPath: '',
    warnings: [],
    ...overrides,
  };
}

function makeDetail(overrides: Partial<RunDetail> = {}): RunDetail {
  return {
    projectId: 'wan',
    epicId: 'E-035-1_1',
    runId: 'R-E035-1',
    format: 'v3',
    state: 'DONE',
    mode: 'full',
    branch: 'task/E-035/main',
    baseCommit: 'abc123',
    currentStep: 2,
    totalSteps: 2,
    gateRetries: 0,
    escalationCount: 0,
    startedAt: '2026-06-18T10:00:00.000Z',
    createdAt: '2026-06-18T10:00:00.000Z',
    donePhase: null,
    pmDecision: null,
    planPath: null,
    steps: [],
    checkpoints: [],
    gates: [],
    compliance: null,
    reports: [],
    audit: emptyAudit(),
    timeline: [],
    files: [],
    ...overrides,
  };
}

function cleanCompliance(overrides: Partial<ComplianceRun> = {}): ComplianceRun {
  return {
    epicId: 'E-035-1_1',
    runId: 'R-E035-1',
    aidVersion: 'v3',
    deployEra: 'post-session-b',
    evaluatedAt: '2026-06-18T11:00:00.000Z',
    coverageMode: 'full',
    overall: 'pass',
    checks: {},
    failures: [],
    forceOverrideCount: 0,
    forceOverrideReasons: [],
    notes: [],
    ...overrides,
  };
}

function passGate(name: string): GateResult {
  return {
    gate: name,
    result: 'pass',
    exitCode: 0,
    durationMs: 10,
    attempts: 1,
    outputPreview: '',
  };
}

function member(overrides: Partial<BriefRunMember> & { detail: RunDetail }): BriefRunMember {
  return {
    projectId: overrides.detail.projectId,
    epicId: overrides.detail.epicId,
    runId: overrides.detail.runId,
    touchedAt: '2026-06-18T11:00:00.000Z',
    touchedAtMs: Date.parse('2026-06-18T11:00:00.000Z'),
    ...overrides,
  };
}

function runSetOf(members: BriefRunMember[], projectId: string | null = null): BriefRunSet {
  const projectIds = [...new Set(members.map((m) => m.projectId))];
  return {
    projectId,
    planId: null,
    members,
    projects: projectIds.map((id) => ({ projectId: id, queue: [], queuePartial: false })),
    partialProjects: [],
  };
}

// A blocking-compliance member (drives vysoke risk + a blocker item). archiveStatus
// 'active' so the §A3 lifecycle classifies it as a CURRENT blocker (the route
// derives 'active' for a live/decision-pending EPIC; without evidence it would be
// 'unknown' → needsTriage, never a confident current blocker).
function blockingMember(projectId: string, epicId: string): BriefRunMember {
  return member({
    archiveStatus: 'active',
    detail: makeDetail({
      projectId,
      epicId,
      runId: `R-${epicId}`,
      state: 'GATES',
      compliance: cleanCompliance({
        epicId,
        runId: `R-${epicId}`,
        overall: 'fail',
        failures: [{ check: 'verifier_provenance', evidence: 'unverifiable', severity: 'blocking' }],
      }),
    }),
  });
}

// A clean, fully-covered member (drives nizke risk).
function cleanMember(projectId: string, epicId: string): BriefRunMember {
  return member({
    detail: makeDetail({
      projectId,
      epicId,
      runId: `R-${epicId}`,
      state: 'DONE',
      compliance: cleanCompliance({ epicId, runId: `R-${epicId}` }),
      gates: [passGate('bats_fsm'), passGate('plan_diff')],
    }),
  });
}

// An fsm-only member (no compliance/gates/audit → neurceno risk).
function fsmOnlyMember(projectId: string, epicId: string): BriefRunMember {
  return member({
    detail: makeDetail({
      projectId,
      epicId,
      runId: `R-${epicId}`,
      state: 'READY',
      compliance: null,
      gates: [],
      timeline: [],
    }),
  });
}

// ---------------------------------------------------------------------------
// AC2 — MVP1 successProbability invariant on EVERY scope
// ---------------------------------------------------------------------------

describe('AC2 — successProbability {null,null} on every scope (MF5 invariant)', () => {
  for (const scope of ['infra', 'project', 'plan'] as const) {
    it(`scope=${scope} → value===null && source===null`, () => {
      const rs = runSetOf([cleanMember('wan', 'E-035-1_1')], scope === 'infra' ? null : 'wan');
      if (scope === 'plan') {
        rs.planId = 'P035';
        rs.plan = { planId: 'P035', progressPct: 100, epicsTotal: 1, epicsDone: 1, lessons: [] };
      }
      const brief = buildBrief(rs, scope, null, GENERATED_AT);
      expect(brief.successProbability.value).toBeNull();
      expect(brief.successProbability.source).toBeNull();
    });
  }
});

// ---------------------------------------------------------------------------
// AC1 — infra brief shape + cross-project sorted blockers/decisions
// ---------------------------------------------------------------------------

describe('AC1 — infra brief shape + sorting', () => {
  it('scope:"infra", probability {null,null}, blockers sorted blocking→warn→info', () => {
    const rs = runSetOf([
      blockingMember('zeta', 'E-099-1_1'),
      cleanMember('alpha', 'E-001-1_1'),
    ]);
    const brief = buildBrief(rs, 'infra', null, GENERATED_AT);

    expect(brief.scope).toBe('infra');
    expect(brief.projectId).toBeNull();
    expect(brief.successProbability).toEqual({ value: null, source: null });

    // The blocking violation appears in blockers; sort is blocking-first.
    expect(brief.blockers.length).toBeGreaterThan(0);
    const weights = brief.blockers.map((b) =>
      b.severity === 'blocking' ? 0 : b.severity === 'warn' ? 1 : 2,
    );
    expect(weights).toEqual([...weights].sort((a, b) => a - b));
  });

  it('blocker items carry a human title (NEVER raw snake_case) + managerial fields', () => {
    const rs = runSetOf([blockingMember('zeta', 'E-099-1_1')]);
    const brief = buildBrief(rs, 'infra', null, GENERATED_AT);
    const item = brief.blockers[0];
    expect(item).toBeDefined();
    // humanTitle is human Czech, not the signal id.
    expect(item.humanTitle).not.toMatch(/^[a-z_]+$/);
    expect(item.humanTitle.length).toBeGreaterThan(0);
    expect(item.whyItMatters.length).toBeGreaterThan(0);
    expect(item.rootCauseKey).toContain('verifier_provenance'); // concrete check, not just the signal
    expect(item.lifecycle).toBe('active');
    expect(item.occurrenceCount).toBe(1);
  });

  it('an archive-UNKNOWN blocking signal goes to needsTriage, never to blockers (§A3)', () => {
    // No archiveStatus → 'unknown' → not a confident current blocker.
    const unknownMember = member({
      detail: makeDetail({
        projectId: 'wan',
        epicId: 'E-044-2_3',
        runId: 'R-E044-2',
        state: 'DONE',
        compliance: cleanCompliance({
          epicId: 'E-044-2_3',
          runId: 'R-E044-2',
          overall: 'fail',
          failures: [{ check: 'verifier_provenance', evidence: 'x', severity: 'blocking' }],
        }),
      }),
    });
    const brief = buildBrief(runSetOf([unknownMember]), 'infra', null, GENERATED_AT);
    expect(brief.blockers).toHaveLength(0);
    expect(brief.needsTriage.length).toBeGreaterThan(0);
    expect(brief.needsTriage[0].inconsistencyFlags).toContain('archive_status_unknown');
  });

  it('decision > blocker precedence — an item never appears in BOTH lists', () => {
    const rs = runSetOf([blockingMember('zeta', 'E-099-1_1')]);
    const brief = buildBrief(rs, 'infra', null, GENERATED_AT);
    const ids = new Set(brief.decisionsNeeded.map((i) => i.id));
    for (const b of brief.blockers) expect(ids.has(b.id)).toBe(false);
  });

  it('ecosystemLine is a non-empty human one-liner', () => {
    const rs = runSetOf([blockingMember('zeta', 'E-099-1_1')]);
    const brief = buildBrief(rs, 'infra', null, GENERATED_AT);
    expect(brief.ecosystemLine).toMatch(/projekt|riziko/);
  });
});

// ---------------------------------------------------------------------------
// AC3 — first visit (no since) → empty sinceLastSeen, server writes nothing
// ---------------------------------------------------------------------------

describe('AC3 — sinceLastSeen first visit', () => {
  it('no since → {since:null, items:[]} with zeroed counts', () => {
    const rs = runSetOf([cleanMember('wan', 'E-035-1_1')]);
    const sls = buildSinceLastSeen(rs, null);
    expect(sls.since).toBeNull();
    expect(sls.items).toEqual([]);
    expect(sls.counts).toEqual({
      newRuns: 0,
      newGateFails: 0,
      newViolations: 0,
      newBacklog: 0,
      stateTransitions: 0,
    });
  });

  it('with a since older than a touched run → newRuns counted', () => {
    const rs = runSetOf([
      member({
        detail: makeDetail({ state: 'EXECUTE' }),
        touchedAt: '2026-06-19T00:00:00.000Z',
        touchedAtMs: Date.parse('2026-06-19T00:00:00.000Z'),
      }),
    ]);
    const sls = buildSinceLastSeen(rs, '2026-06-18T00:00:00.000Z');
    expect(sls.since).toBe('2026-06-18T00:00:00.000Z');
    expect(sls.counts.newRuns).toBe(1);
    expect(sls.items.length).toBe(1);
  });

  it('a touched run with a gate fail + violations bumps the right buckets', () => {
    const rs = runSetOf([
      member({
        detail: makeDetail({
          state: 'GATES',
          gates: [{ ...passGate('g'), result: 'fail' }],
          compliance: cleanCompliance({
            overall: 'fail',
            failures: [{ check: 'x', evidence: 'e', severity: 'advisory' }],
          }),
        }),
        touchedAt: '2026-06-19T00:00:00.000Z',
        touchedAtMs: Date.parse('2026-06-19T00:00:00.000Z'),
      }),
    ]);
    const sls = buildSinceLastSeen(rs, '2026-06-18T00:00:00.000Z');
    expect(sls.counts.newGateFails).toBe(1);
    expect(sls.counts.newViolations).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// AC4 — infra risk = worst across determinable; neurceno never lowers it
// ---------------------------------------------------------------------------

describe('AC4 — infra worst-level rule (neurceno never lowers)', () => {
  it('vysoke project + nizke project + neurceno project → infra vysoke', () => {
    const rs = runSetOf([
      blockingMember('zeta', 'E-099-1_1'), // vysoke
      cleanMember('alpha', 'E-001-1_1'), // nizke
      fsmOnlyMember('mid', 'E-050-1_1'), // neurceno
    ]);
    const brief = buildBrief(rs, 'infra', null, GENERATED_AT);
    expect(brief.risk.level).toBe('vysoke');
    // The neurceno project is NAMED in reasons but never lowers the level.
    const text = brief.risk.reasons.map((r) => r.text).join(' ');
    expect(text).toMatch(/zeta/); // driver named
    expect(text).toMatch(/málo dat/); // neurceno tail surfaced
  });

  it('all projects neurceno → infra neurceno (never a fake green)', () => {
    const rs = runSetOf([fsmOnlyMember('a', 'E-1'), fsmOnlyMember('b', 'E-2')]);
    const brief = buildBrief(rs, 'infra', null, GENERATED_AT);
    expect(brief.risk.level).toBe('neurceno');
  });

  it('infraRisk: a lone neurceno never drags a clean project to green-or-worse', () => {
    const r = infraRisk([
      { projectId: 'clean', risk: { level: 'nizke', reasons: [], confidence: 'high' } },
      { projectId: 'thin', risk: { level: 'neurceno', reasons: [], confidence: 'low' } },
    ]);
    expect(r.level).toBe('nizke'); // determinable max = nizke; neurceno excluded
    expect(r.reasons.some((x) => x.signal === 'insufficient_coverage')).toBe(true);
  });

  it('infraRisk: stredni beats nizke', () => {
    const r = infraRisk([
      { projectId: 'a', risk: { level: 'nizke', reasons: [], confidence: 'high' } },
      { projectId: 'b', risk: { level: 'stredni', reasons: [], confidence: 'high' } },
    ]);
    expect(r.level).toBe('stredni');
  });
});

// ---------------------------------------------------------------------------
// AC6 — every BriefItem.explanation resolves via explain() over a real key
// ---------------------------------------------------------------------------

describe('AC6 — explanations resolve via explain() (never the unknown fallback)', () => {
  it('every managerial item carries a resolved Czech explanation (no unknown-id fallback)', () => {
    const rs: BriefRunSet = {
      projectId: 'wan',
      planId: null,
      members: [
        member({
          archiveStatus: 'active',
          detail: makeDetail({
            state: 'ESCALATION',
            escalationCount: 1,
            audit: emptyAudit({ present: true, blockingFindings: false, nextSteps: [{ finding: 'x', severity: 'Low', effort: 'S', autoFixable: true, rank: 1 }] }),
            compliance: cleanCompliance({
              overall: 'fail',
              forceOverrideCount: 1,
              forceOverrideReasons: ['PM override: provenance noise on cp2'],
              failures: [{ check: 'dod_present', evidence: 'no DoD', severity: 'advisory' }],
            }),
          }),
        }),
      ],
      projects: [
        {
          projectId: 'wan',
          queue: [{ epicId: 'E-036-1_1', priority: 'critical', status: 'queued', addedAt: '2026-06-19T00:00:00Z' }],
          queuePartial: false,
        },
      ],
      partialProjects: [],
    };

    const brief = buildBrief(rs, 'project', null, GENERATED_AT);
    const allItems = [
      ...brief.blockers,
      ...brief.watchOuts,
      ...brief.nextUp,
      ...brief.decisionsNeeded,
      ...brief.needsTriage,
    ];
    expect(allItems.length).toBeGreaterThan(0);
    for (const item of allItems) {
      expect(item.explanation.headline.length).toBeGreaterThan(0);
      expect(item.explanation.headline).not.toMatch(/^Neznámá událost/);
      // humanTitle is the user-facing label — NEVER a raw snake_case signal.
      expect(item.humanTitle).not.toBe(item.signal);
    }

    // ESCALATION is a DECISION only (decision > blocker precedence) — not duplicated.
    const inDecisions = brief.decisionsNeeded.some((i) => i.signal === 'escalation_active');
    const inBlockers = brief.blockers.some((i) => i.signal === 'escalation_active');
    expect(inDecisions).toBe(true);
    expect(inBlockers).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// extractRiskSignals — real-data extraction feeds computeRisk
// ---------------------------------------------------------------------------

describe('extractRiskSignals (§13.2.1 from real run data)', () => {
  it('blocking compliance → openBlockingViolations + complianceAvailable', () => {
    const s = extractRiskSignals([blockingMember('wan', 'E-035-1_1')], Date.parse(GENERATED_AT));
    expect(s.openBlockingViolations).toBe(1);
    expect(s.complianceAvailable).toBe(true);
  });

  it('clean covered run → gates first-pass rate 1 + gatesAvailable', () => {
    const s = extractRiskSignals([cleanMember('wan', 'E-035-1_1')], Date.parse(GENERATED_AT));
    expect(s.gatesAvailable).toBe(true);
    expect(s.gateFirstPassRate).toBe(1);
    expect(s.gateRunCount).toBe(1);
  });

  it('fsm-only run → no level-relevant sources available', () => {
    const s = extractRiskSignals([fsmOnlyMember('wan', 'E-035-1_1')], Date.parse(GENERATED_AT));
    expect(s.complianceAvailable).toBe(false);
    expect(s.gatesAvailable).toBe(false);
    expect(s.auditAvailable).toBe(false);
  });

  it('stale active run vs refNow → staleRun fires with the idle days', () => {
    const old = '2026-06-10T00:00:00.000Z'; // 10 days before GENERATED_AT
    const s = extractRiskSignals(
      [
        member({
          detail: makeDetail({ state: 'EXECUTE' }),
          touchedAt: old,
          touchedAtMs: Date.parse(old),
        }),
      ],
      Date.parse(GENERATED_AT),
    );
    expect(s.staleRun).toBe(true);
    expect(s.staleDays).toBeGreaterThanOrEqual(3);
  });
});

// ---------------------------------------------------------------------------
// Determinism — same input → identical output (no LLM, no clock in decisions)
// ---------------------------------------------------------------------------

describe('determinism', () => {
  it('two calls with the same runSet + generatedAt are byte-identical', () => {
    const rs = runSetOf([blockingMember('zeta', 'E-099-1_1'), cleanMember('a', 'E-1')]);
    const a = buildBrief(rs, 'infra', '2026-06-18T00:00:00.000Z', GENERATED_AT);
    const b = buildBrief(rs, 'infra', '2026-06-18T00:00:00.000Z', GENERATED_AT);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });
});
