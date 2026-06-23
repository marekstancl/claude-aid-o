/**
 * Metrics computation test suite (EPIC E-047-4_7, Step 2).
 *
 * The HIGH fixture-only-false-green risk in this step is the §5.7 available-runs
 * denominator: it only proves its value on a HETEROGENEOUS run set. So these
 * tests deliberately mix runs that are MISSING different signals — some without
 * gates_report.json, some without compliance.json, some with only fsm-state —
 * and assert the missing-signal run is DROPPED from the relevant term's
 * denominator (NEVER counted as a clean 0). A uniform fixture would pass a buggy
 * total-run denominator too; the heterogeneous mix is what catches it.
 *
 * Acceptance Criteria (Step 2 dispatch):
 *  AC1  computeFsmAdherenceScore uses per-term available-runs denominators; a run
 *       missing gates_report.json is DROPPED from the gate term (not 0),
 *       partial:true; value:null+confidence:'low' below the ≥3-fsm-runs threshold.
 *  AC2  computeHealth value:null ("bez dat") when zero runs have compliance.json;
 *       openViolations hard-zeros the health term when an open blocking fail exists.
 *  AC3  buildTimeBy emits user/dev as {durationS:null, source:null}; ai/controller
 *       best-effort source:'timeline'.
 *  AC4  gateRuns/gateRetries/runCount stay NON-null on a v3 run.
 *  AC5  per-step durationS:null + no-step-timing flag when verify mtimes absent;
 *       NEVER 0.
 *  AC6  run-start anchor is READY→EXECUTE from the timeline (NOT fsm_init).
 */

import { describe, expect, it } from 'vitest';
import type {
  ActivityEvent,
  GateResult,
  ComplianceRun,
  ComplianceFailure,
  RunDetail,
  RunStep,
  RunSummary,
} from '@aid/contract';
import {
  buildTimeBy,
  computeCheckpointRepeats,
  computeFsmAdherenceScore,
  computeHealth,
  computeMetrics,
  computeRunDuration,
} from './compute.js';

// ---------------------------------------------------------------------------
// RunDetail factory — minimal, every field overridable per test.
// ---------------------------------------------------------------------------

let seq = 0;
function makeRun(over: Partial<RunDetail> = {}): RunDetail {
  seq += 1;
  return {
    projectId: 'proj',
    epicId: over.epicId ?? `E-${seq}`,
    runId: over.runId ?? `R-${seq}`,
    format: 'v3',
    state: 'DONE',
    mode: '',
    branch: '',
    baseCommit: '',
    currentStep: 0,
    totalSteps: 0,
    gateRetries: 0,
    escalationCount: 0,
    startedAt: '2026-06-01T00:00:00Z',
    createdAt: null,
    donePhase: null,
    pmDecision: null,
    planPath: null,
    steps: [],
    checkpoints: [],
    gates: [],
    compliance: null,
    reports: [],
    audit: {
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
      rawRelPath: 'audit-report.md',
      warnings: [],
    },
    timeline: [],
    files: [],
    ...over,
  };
}

function ev(event: string, over: Partial<ActivityEvent> = {}): ActivityEvent {
  return {
    projectId: 'proj',
    ts: '2026-06-01T00:00:00Z',
    event,
    raw: {},
    ...over,
  };
}

function gate(over: Partial<GateResult> = {}): GateResult {
  return {
    gate: 'typecheck',
    result: 'pass',
    exitCode: 0,
    durationMs: 100,
    attempts: 1,
    outputPreview: '',
    ...over,
  };
}

function compliance(over: Partial<ComplianceRun> = {}): ComplianceRun {
  return {
    epicId: 'E',
    runId: 'R',
    aidVersion: '',
    deployEra: '',
    evaluatedAt: '',
    coverageMode: null,
    overall: 'pass',
    checks: {},
    failures: [],
    forceOverrideCount: 0,
    forceOverrideReasons: [],
    notes: [],
    ...over,
  };
}

function fail(check: string, severity: ComplianceFailure['severity'] = 'blocking'): ComplianceFailure {
  return { check, evidence: '', severity };
}

function step(over: Partial<RunStep> = {}): RunStep {
  return {
    id: 1,
    name: 's',
    status: 'done',
    role: null,
    startedAt: null,
    completedAt: null,
    durationS: null,
    ...over,
  };
}

const sum = (n: number): RunSummary => ({
  runId: `R${n}`,
  format: 'v3',
  state: 'DONE',
  startedAt: null,
  finishedAt: null,
  durationS: null,
  overallGate: null,
  complianceOverall: null,
});

// ===========================================================================
// AC6 — computeRunDuration: READY→EXECUTE anchor, NOT fsm_init
// ===========================================================================

describe('computeRunDuration (§5.1) — run-start anchor', () => {
  it('AC6: anchors at READY→EXECUTE, NOT fsm_init (idle gap excluded)', () => {
    const timeline = [
      ev('fsm_init', { ts: '2026-06-18T14:04:00Z' }), // 13h idle before work
      ev('fsm_transition', { ts: '2026-06-19T03:00:00Z', from: 'READY', to: 'EXECUTE' }),
      ev('fsm_done_advance', { ts: '2026-06-19T04:00:00Z' }),
    ];
    const r = computeRunDuration(timeline, []);
    expect(r.startSource).toBe('ready_execute');
    expect(r.endSource).toBe('done_advance');
    // 1 hour of real work — NOT 14 hours (which fsm_init anchoring would give).
    expect(r.durationS).toBe(3600);
  });

  it('falls back to fsm_init (init_idle_included) when no READY→EXECUTE, with warning', () => {
    const timeline = [
      ev('fsm_init', { ts: '2026-06-19T00:00:00Z' }),
      ev('fsm_transition', { ts: '2026-06-19T01:00:00Z', to: 'DONE' }),
    ];
    const r = computeRunDuration(timeline, []);
    expect(r.startSource).toBe('init_idle_included');
    expect(r.warnings.some((w) => w.includes('fsm_init'))).toBe(true);
  });

  it('end fallback chain: compliance_written when no done_advance (common case)', () => {
    const timeline = [
      ev('fsm_transition', { ts: '2026-06-19T03:00:00Z', from: 'READY', to: 'EXECUTE' }),
      ev('compliance_written', { ts: '2026-06-19T03:30:00Z' }),
    ];
    const r = computeRunDuration(timeline, []);
    expect(r.endSource).toBe('compliance_written');
    expect(r.durationS).toBe(1800);
  });

  it('null (NOT_COMPUTABLE), never 0, when no parseable start anchor', () => {
    const r = computeRunDuration([ev('gate_start')], []);
    expect(r.durationS).toBeNull();
    expect(r.warnings.some((w) => w.includes('NOT_COMPUTABLE'))).toBe(true);
  });

  it('open run → max-mtime end source + incomplete flag', () => {
    const timeline = [
      ev('fsm_transition', { ts: '2026-06-19T03:00:00Z', from: 'READY', to: 'EXECUTE' }),
      ev('gate_start', { ts: '2026-06-19T03:10:00Z' }),
    ];
    const r = computeRunDuration(timeline, []);
    expect(r.endSource).toBe('max_mtime');
    expect(r.incomplete).toBe(true);
    expect(r.durationS).toBe(600);
  });
});

// ===========================================================================
// AC3 — buildTimeBy: the TimeSource seam
// ===========================================================================

describe('buildTimeBy (§13.9) — TimeSource seam', () => {
  it('AC3: user/dev are {durationS:null, source:null}; ai/controller best-effort timeline', () => {
    const timeline = [
      ev('fsm_transition', { ts: '2026-06-19T03:00:00Z', from: 'READY', to: 'EXECUTE' }),
      ev('fsm_done_advance', { ts: '2026-06-19T04:00:00Z' }),
    ];
    const tb = buildTimeBy(timeline);
    const byKind = Object.fromEntries(tb.map((t) => [t.kind, t]));

    expect(byKind.user).toEqual({ kind: 'user', durationS: null, source: null });
    expect(byKind.dev).toEqual({ kind: 'dev', durationS: null, source: null });

    expect(byKind.ai.source).toBe('timeline');
    expect(byKind.ai.durationS).toBe(3600);
    expect(byKind.controller.source).toBe('timeline'); // present-but-unmeasured actor
    expect(byKind.controller.durationS).toBeNull();
  });

  it('ai source is null (never fabricated) when timeline yields no anchor', () => {
    const tb = buildTimeBy([]);
    const ai = tb.find((t) => t.kind === 'ai')!;
    expect(ai.durationS).toBeNull();
    expect(ai.source).toBeNull();
  });
});

// ===========================================================================
// AC4 + AC5 — computeMetrics
// ===========================================================================

describe('computeMetrics (§5.1–§5.3)', () => {
  it('AC4: gateRuns/gateRetries/runCount stay NON-null on a v3 run', () => {
    const run = makeRun({
      gates: [gate(), gate({ gate: 'lint' })],
      gateRetries: 2,
    });
    const m = computeMetrics(run, [sum(1), sum(2), sum(3)]);
    expect(m.gateRuns).toBe(2);
    expect(m.gateRetries).toBe(2);
    expect(m.runCount).toBe(3);
    // Confirm these are real numbers, not nullable.
    expect(typeof m.gateRuns).toBe('number');
    expect(typeof m.gateRetries).toBe('number');
    expect(typeof m.runCount).toBe('number');
  });

  it('AC5: per-step durationS:null + no_step_timing flag when mtimes absent; NEVER 0', () => {
    const run = makeRun({
      steps: [step({ durationS: null }), step({ id: 2, durationS: null })],
    });
    const m = computeMetrics(run, [sum(1)]);
    expect(m.stepDurationsS).toEqual([null, null]); // null, NOT 0
    expect(m.avgStepDurationS).toBeNull();
    expect(m.longestStep).toBeNull();
    expect(m.stepTimingSource).toBeNull();
    expect(m.warnings.some((w) => w.includes('no_step_timing'))).toBe(true);
  });

  it('emits mtime source + longestStep when step durations ARE measured', () => {
    const run = makeRun({
      steps: [step({ durationS: 100 }), step({ id: 2, durationS: 300 })],
    });
    const m = computeMetrics(run, [sum(1)]);
    expect(m.stepTimingSource).toBe('mtime');
    expect(m.avgStepDurationS).toBe(200);
    expect(m.longestStep).toEqual({ id: 2, durationS: 300 });
  });

  it('null latest → partial:true, timeBy seam still present (user/dev null)', () => {
    const m = computeMetrics(null, []);
    expect(m.partial).toBe(true);
    expect(m.runCount).toBe(0);
    const user = m.timeBy.find((t) => t.kind === 'user')!;
    expect(user).toEqual({ kind: 'user', durationS: null, source: null });
  });

  it('checkpointRepeats preserves null (NEVER 0) when no repeat signal', () => {
    const run = makeRun({
      checkpoints: [
        { id: 'CP1', label: '', dispatched: true, verdict: 'pass', provenance: null, provenanceSource: null, repeatCount: 2, repeatSource: 'files', outputs: [] },
        { id: 'CP2', label: '', dispatched: true, verdict: 'pass', provenance: null, provenanceSource: null, repeatCount: null, repeatSource: null, outputs: [] },
      ],
    });
    const reps = computeCheckpointRepeats(run);
    expect(reps.CP1).toBe(2);
    expect(reps.CP2).toBeNull();
    expect(reps.CP3).toBeNull();
  });
});

// ===========================================================================
// AC1 — computeFsmAdherenceScore: per-term available-runs denominators
// ===========================================================================

describe('computeFsmAdherenceScore (§5.7) — available-runs denominators', () => {
  it('AC1: a run missing gates_report.json is DROPPED from the gate term (not 0)', () => {
    // 4 runs, all with fsm-state + timeline (so above threshold). Only 2 of them
    // have a gates_report — one of THOSE failed its gate on first try. The 2 runs
    // WITHOUT gates_report must NOT count toward the gate-first-pass denominator.
    const withGoodGate = makeRun({
      timeline: [ev('fsm_init')],
      gates: [gate({ result: 'pass', attempts: 1 })],
    });
    const withBadGate = makeRun({
      timeline: [ev('fsm_init')],
      gates: [gate({ result: 'fail', attempts: 3 })],
    });
    const noGate1 = makeRun({ timeline: [ev('fsm_init')], files: [] });
    const noGate2 = makeRun({ timeline: [ev('fsm_init')], files: [] });

    const score = computeFsmAdherenceScore([withGoodGate, withBadGate, noGate1, noGate2]);

    // gate term: 1 of 2 gate-bearing runs passed first try → fraction = 0.5.
    // If the 2 no-gate runs had been (wrongly) counted as clean passes, the
    // first-pass rate would be 3/4=0.75 and the penalty would be smaller.
    // gate_first_pass_rate component proves the denominator = ONLY gate-bearing runs.
    expect(score.components.gate_first_pass_rate).toBe(0.5);
    expect(score.value).not.toBeNull(); // 4 fsm runs ≥ 3 threshold
  });

  it('AC1: dropped term (zero available runs) sets partial:true + re-normalizes', () => {
    // 3 fsm runs (above threshold) but NONE has a gates_report → gate term dropped.
    const runs = [
      makeRun({ timeline: [ev('fsm_init')], files: [] }),
      makeRun({ timeline: [ev('fsm_init')], files: [] }),
      makeRun({ timeline: [ev('fsm_init')], files: [] }),
    ];
    const score = computeFsmAdherenceScore(runs);
    expect(score.partial).toBe(true);
    expect(score.warnings.some((w) => w.includes('gate_first_pass') && w.includes('dropped'))).toBe(true);
    // Clean process otherwise → value still computable from the surviving terms.
    expect(score.value).toBe(100);
  });

  it('AC1: below ≥3-fsm-runs threshold → value:null, partial:true, confidence:low', () => {
    const runs = [
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()] }),
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()] }),
    ];
    const score = computeFsmAdherenceScore(runs);
    expect(score.value).toBeNull();
    expect(score.partial).toBe(true);
    expect(score.confidence).toBe('low');
    expect(score.warnings.some((w) => w.includes('málo dat (n=2)'))).toBe(true);
    // Components still exposed for the breakdown.
    expect(score.components).toHaveProperty('force_override_count');
  });

  it('a forced override penalizes; precondition fail penalizes; clean = 100', () => {
    const clean = [
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()] }),
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()] }),
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()] }),
    ];
    expect(computeFsmAdherenceScore(clean).value).toBe(100);

    const withOverride = [
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()], compliance: compliance({ forceOverrideCount: 1 }) }),
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()] }),
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()] }),
    ];
    const s = computeFsmAdherenceScore(withOverride);
    expect(s.value!).toBeLessThan(100);
    expect(s.components.force_override_count).toBe(1);
  });

  it('precondition-fail denominator = runs with a non-empty timeline only', () => {
    const runs = [
      makeRun({ timeline: [ev('fsm_init'), ev('fsm_precondition_fail')], gates: [gate()] }),
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()] }),
      makeRun({ timeline: [ev('fsm_init')], gates: [gate()] }),
    ];
    const s = computeFsmAdherenceScore(runs);
    expect(s.components.runs_with_precondition_fail).toBe(1);
  });
});

// ===========================================================================
// AC2 — computeHealth
// ===========================================================================

describe('computeHealth (§5.7) — quality blend', () => {
  it('AC2: value:null ("bez dat") when zero runs have compliance.json', () => {
    const runs = [makeRun({ gates: [gate()] }), makeRun({ gates: [gate()] })];
    const h = computeHealth(runs);
    expect(h.value).toBeNull();
    expect(h.compliancePassRate).toBeNull();
    expect(h.warnings.some((w) => w.includes('bez dat'))).toBe(true);
  });

  it('AC2: an open blocking failure hard-zeros the openViolations term', () => {
    const allChecksPass = { c1: 'pass', c2: 'pass' };
    // Latest run of an EPIC has an UNRESOLVED blocking failure → openViolations>0.
    const run = makeRun({
      epicId: 'E-042-1_1',
      gates: [gate({ result: 'pass' })],
      compliance: compliance({ overall: 'fail', checks: allChecksPass, failures: [fail('verifier_provenance')] }),
    });
    const h = computeHealth([run]);
    expect(h.openViolations).toBe(1);
    // compliance term = 100, gate term = 100, openViolations term = 0 (hard zero).
    // blend = 0.5*100 + 0.3*100 + 0.2*0 = 80.
    expect(h.value).toBe(80);
  });

  it('openViolations resolved when a LATER run of the same EPIC clears the .check', () => {
    const older = makeRun({
      epicId: 'E-99',
      startedAt: '2026-06-01T00:00:00Z',
      compliance: compliance({ overall: 'fail', checks: { c1: 'pass' }, failures: [fail('verifier_provenance')] }),
    });
    const newer = makeRun({
      epicId: 'E-99',
      startedAt: '2026-06-02T00:00:00Z',
      compliance: compliance({ overall: 'pass', checks: { c1: 'pass' }, failures: [] }),
    });
    const h = computeHealth([older, newer]);
    // The latest run (newer) has no blocking failure → 0 open violations.
    expect(h.openViolations).toBe(0);
  });

  it('compliance_checks_pass_rate excludes null checks from the denominator', () => {
    const run = makeRun({
      compliance: compliance({ checks: { c1: 'pass', c2: 'fail', c3: null } }),
    });
    const h = computeHealth([run]);
    // 1 pass of 2 non-null checks = 50% (c3:null excluded).
    expect(h.compliancePassRate).toBe(50);
  });

  it('confidence:low below 3 contributing runs, high at ≥3', () => {
    const mk = () => makeRun({ compliance: compliance({ checks: { c1: 'pass' } }), gates: [gate()] });
    expect(computeHealth([mk()]).confidence).toBe('low');
    expect(computeHealth([mk(), mk(), mk()]).confidence).toBe('high');
  });

  it('gate_final_pass term dropped (partial) when no run has a gates_report', () => {
    const run = makeRun({ compliance: compliance({ checks: { c1: 'pass' } }) });
    const h = computeHealth([run]);
    expect(h.partial).toBe(true);
    expect(h.warnings.some((w) => w.includes('gate_final_pass') && w.includes('dropped'))).toBe(true);
    // compliance 100 + openViolations 100 (no open), gate dropped → re-normalize.
    expect(h.value).toBe(100);
  });
});
