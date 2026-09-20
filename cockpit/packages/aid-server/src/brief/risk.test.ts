/**
 * Deterministic RISK model tests — spec §13.2 (D2 "flag, never fake").
 *
 * Covers the §13.2.5 worked fixtures (E-042-1_1 vysoké, clean merged nízké,
 * fsm-only neurceno) plus the AC matrix from EPIC E-047-4_7 Step 3:
 *   AC1 — open blocking violation → vysoke / open_blocking_violations / high (single file)
 *   AC2 — clean DONE+merged → nizke / [no_adverse_signal] / high (clean-compliance floor)
 *   AC3 — fsm-state.yaml only → neurceno (NEVER nizke) / low / insufficient_coverage
 *   AC4 — coverage count over {S1,S3,S4,S5,S6,S8} only (S7 + S2 fsm-presence excluded)
 *   AC5 — the floor wins: nizke requires compliance(S1/S3) OR gates(S4) present AND clean
 *   AC6 — computeRisk total: every branch returns a fully-shaped Risk, never throws
 */

import { describe, it, expect } from 'vitest';
import { computeRisk, RISK, type RiskSignals } from './risk.js';

/** A fully-absent signal set: nothing available, nothing firing (the fsm-only floor). */
function emptySignals(): RiskSignals {
  return {
    openBlockingViolations: 0,
    escalationCount: 0,
    escalationActive: false,
    forceOverrideCount: 0,
    forceOverrideSystematic: false,
    gateFirstPassRate: null,
    gateRunCount: 0,
    repeatedPreconditionFails: false,
    stuckOrLoopingFsm: false,
    staleRun: false,
    auditBlockingFindings: false,
    complianceAvailable: false,
    gatesAvailable: false,
    timelineAvailable: false,
    auditAvailable: false,
    fsmStateAvailable: false,
    runDirAvailable: false,
  };
}

/** A clean, fully-covered run (compliance + gates present & clean). */
function cleanCoveredSignals(): RiskSignals {
  return {
    ...emptySignals(),
    gateFirstPassRate: 1,
    gateRunCount: 1,
    complianceAvailable: true,
    gatesAvailable: true,
    timelineAvailable: true,
    fsmStateAvailable: true,
    runDirAvailable: true,
  };
}

describe('RISK thresholds (§13.2.2)', () => {
  it('are the verbatim spec constants', () => {
    expect(RISK).toEqual({
      STALE_DAYS: 3,
      STUCK_DWELL_SEC: 86400,
      REPEAT_FAIL_MIN: 2,
      INCREMENT_FAIL_MIN: 2,
      GATE_FIRST_PASS_WARN: 0.6,
      GATE_FIRST_PASS_BAD: 0.4,
      FORCE_OVERRIDE_WARN: 1,
      COVERAGE_MIN_SIGNALS: 2,
    });
  });
});

describe('AC1 / §13.2.5 — E-042-1_1 open blocking violation → vysoke', () => {
  it('sets vysoke, open_blocking_violations reason, high confidence from one file', () => {
    // Real E-042-1_1: failures=[{check:verifier_provenance,severity:blocking}], force_override_count:1.
    const s: RiskSignals = {
      ...emptySignals(),
      openBlockingViolations: 1,
      forceOverrideCount: 1,
      complianceAvailable: true,
    };
    const r = computeRisk(s);
    expect(r.level).toBe('vysoke');
    expect(r.confidence).toBe('high'); // S1 authoritative single-file → high from ONE run (SF3)
    const blocking = r.reasons.find((x) => x.signal === 'open_blocking_violations');
    expect(blocking).toBeDefined();
    expect(blocking?.status).toBe('selhalo');
    expect(blocking?.value).toBe(1);
    // The force-override watch accumulates as a reason even though S1 set the level.
    expect(r.reasons.some((x) => x.signal === 'force_override')).toBe(true);
  });
});

describe('AC2 / §13.2.5 — clean DONE+merged → nizke', () => {
  it('sets nizke, [no_adverse_signal], high (clean-compliance floor)', () => {
    const r = computeRisk(cleanCoveredSignals());
    expect(r.level).toBe('nizke');
    expect(r.confidence).toBe('high'); // rests on present+clean compliance.json
    expect(r.reasons).toHaveLength(1);
    expect(r.reasons[0]?.signal).toBe('no_adverse_signal');
    expect(r.reasons[0]?.status).toBe('proslo');
  });

  it('nizke is low-confidence when the ONLY clean evidence is the gate rate with <3 runs', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      gateFirstPassRate: 1,
      gateRunCount: 2, // <3 → rate signal cannot be high
      gatesAvailable: true,
      timelineAvailable: true, // 2nd covering source so coverage ≥ 2
    };
    const r = computeRisk(s);
    expect(r.level).toBe('nizke');
    expect(r.confidence).toBe('low'); // honest-but-thin green, never fake-confident
  });
});

describe('AC3 / §13.2.5 — fsm-state.yaml only → neurceno NEVER nizke', () => {
  it('returns neurceno, low confidence, insufficient_coverage', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      fsmStateAvailable: true, // S2 presence — does NOT count toward coverage
      runDirAvailable: true, // S7 — does NOT count toward coverage
    };
    const r = computeRisk(s);
    expect(r.level).toBe('neurceno');
    expect(r.level).not.toBe('nizke'); // the binding honesty guarantee
    expect(r.confidence).toBe('low');
    expect(r.reasons).toHaveLength(1);
    expect(r.reasons[0]?.signal).toBe('insufficient_coverage');
  });
});

describe('AC4 — coverage count is over {S1,S3,S4,S5,S6,S8} only', () => {
  it('S7 (staleRun avail) + S2 (fsm presence) do NOT count toward COVERAGE_MIN_SIGNALS', () => {
    // Only the always-on sources present; zero level-relevant sources → neurceno.
    const s: RiskSignals = {
      ...emptySignals(),
      fsmStateAvailable: true, // S2 presence (excluded)
      runDirAvailable: true, // S7 (excluded)
    };
    expect(computeRisk(s).level).toBe('neurceno');
  });

  it('exactly one level-relevant source = coverage 1 < 2 → still neurceno even when clean', () => {
    // compliance present and clean (floor met) but only 1 covering source → count fails.
    const s: RiskSignals = {
      ...emptySignals(),
      complianceAvailable: true, // S1/S3 source = 1
      openBlockingViolations: 0,
      runDirAvailable: true,
    };
    const r = computeRisk(s);
    expect(r.level).toBe('neurceno'); // count rule (belt) fails even though floor (suspenders) holds
  });

  it('two level-relevant sources reach the coverage floor', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      complianceAvailable: true, // source 1 (S1/S3)
      timelineAvailable: true, // source 2 (S5/S6)
      openBlockingViolations: 0,
    };
    const r = computeRisk(s);
    expect(r.level).toBe('nizke'); // count ≥ 2 AND compliance clean floor met
    expect(r.confidence).toBe('high');
  });
});

describe('AC5 — the floor wins: nizke requires compliance(S1/S3) OR gates(S4) present AND clean', () => {
  it('two NON-compliance/NON-gates sources satisfy the count but FAIL the floor → neurceno', () => {
    // timeline + audit available (count = 2) but neither compliance nor gates → no clean floor.
    const s: RiskSignals = {
      ...emptySignals(),
      timelineAvailable: true, // S5/S6 source
      auditAvailable: true, // S8 source
      auditBlockingFindings: false,
    };
    const r = computeRisk(s);
    expect(r.level).toBe('neurceno'); // count satisfied, floor NOT met → floor wins
    expect(r.reasons[0]?.signal).toBe('insufficient_coverage');
  });

  it('compliance present but with an open blocking violation never reaches the floor path (it fires T1)', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      complianceAvailable: true,
      timelineAvailable: true,
      openBlockingViolations: 2,
    };
    expect(computeRisk(s).level).toBe('vysoke');
  });

  it('gates present and clean satisfies the floor even without compliance (with ≥3 runs → high)', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      gatesAvailable: true,
      gateFirstPassRate: 0.9,
      gateRunCount: 3,
      timelineAvailable: true, // 2nd source for the count
    };
    const r = computeRisk(s);
    expect(r.level).toBe('nizke');
    expect(r.confidence).toBe('high'); // ≥3 runs → rate-clean green is high
  });
});

describe('§13.2.3 tier table — precedence and confidence', () => {
  it('T1 S8 audit blocking → vysoke/high', () => {
    const s: RiskSignals = { ...emptySignals(), auditAvailable: true, auditBlockingFindings: true };
    const r = computeRisk(s);
    expect(r.level).toBe('vysoke');
    expect(r.confidence).toBe('high');
    expect(r.reasons[0]?.signal).toBe('audit_blocking_findings');
  });

  it('T1 S3 systematic override → vysoke/high', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      complianceAvailable: true,
      forceOverrideCount: 5,
      forceOverrideSystematic: true,
    };
    const r = computeRisk(s);
    expect(r.level).toBe('vysoke');
    expect(r.reasons[0]?.signal).toBe('force_override_systematic');
    // systematic suppresses the plain force_override reason (mutually exclusive)
    expect(r.reasons.some((x) => x.signal === 'force_override')).toBe(false);
  });

  it('T1 S4 gate rate < BAD with ≥3 runs → vysoke/high', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      gatesAvailable: true,
      gateFirstPassRate: 0.3,
      gateRunCount: 4,
    };
    const r = computeRisk(s);
    expect(r.level).toBe('vysoke');
    expect(r.confidence).toBe('high');
    expect(r.reasons[0]?.signal).toBe('gate_first_pass_bad');
  });

  it('S4 gate rate < BAD with <3 runs does NOT fire (rate signal needs ≥3 runs)', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      gatesAvailable: true,
      gateFirstPassRate: 0.3,
      gateRunCount: 2,
      timelineAvailable: true,
    };
    const r = computeRisk(s);
    // floor: gatesClean requires rate ≥ WARN, so 0.3 is NOT clean → floor not met → neurceno
    expect(r.level).toBe('neurceno');
  });

  it('T2 escalation_active → stredni/high', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      fsmStateAvailable: true,
      escalationActive: true,
      escalationCount: 1,
    };
    const r = computeRisk(s);
    expect(r.level).toBe('stredni');
    expect(r.confidence).toBe('high');
    expect(r.reasons[0]?.signal).toBe('escalation_active');
  });

  it('T2 repeated precondition fail → stredni/high', () => {
    const s: RiskSignals = { ...emptySignals(), timelineAvailable: true, repeatedPreconditionFails: true };
    const r = computeRisk(s);
    expect(r.level).toBe('stredni');
    expect(r.reasons[0]?.signal).toBe('repeated_precondition_fail');
  });

  it('T2 stuck/looping → stredni/high', () => {
    const s: RiskSignals = { ...emptySignals(), timelineAvailable: true, stuckOrLoopingFsm: true };
    const r = computeRisk(s);
    expect(r.level).toBe('stredni');
    expect(r.reasons[0]?.signal).toBe('stuck_or_looping');
  });

  it('T2 stale_run → stredni/high and the reason interpolates staleDays', () => {
    const s: RiskSignals = { ...emptySignals(), runDirAvailable: true, staleRun: true, staleDays: 7 };
    const r = computeRisk(s);
    expect(r.level).toBe('stredni');
    expect(r.reasons[0]?.signal).toBe('stale_run');
    expect(r.reasons[0]?.text).toContain('7 dní');
    expect(r.reasons[0]?.value).toBe(7);
  });

  it('precedence: a blocking S1 (vysoke) outranks a T2 escalation but BOTH reasons appear', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      complianceAvailable: true,
      openBlockingViolations: 1,
      fsmStateAvailable: true,
      escalationActive: true,
    };
    const r = computeRisk(s);
    expect(r.level).toBe('vysoke'); // level = max precedence (S1)
    expect(r.confidence).toBe('high'); // confidence follows the level-setting signal (S1)
    expect(r.reasons.some((x) => x.signal === 'open_blocking_violations')).toBe(true);
    expect(r.reasons.some((x) => x.signal === 'escalation_active')).toBe(true); // reasons are the union
  });
});

describe('§13.2.4 — low confidence never moves the level', () => {
  it('a low-confidence clean green stays nizke (not downgraded to neurceno)', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      gatesAvailable: true,
      gateFirstPassRate: 1,
      gateRunCount: 1, // thin → low confidence
      timelineAvailable: true,
    };
    const r = computeRisk(s);
    expect(r.level).toBe('nizke'); // level unchanged
    expect(r.confidence).toBe('low'); // annotation only
  });
});

describe('AC6 — computeRisk is total (never throws, always fully shaped)', () => {
  it('every result has level + reasons[] + confidence, all reasons fully shaped', () => {
    const cases: RiskSignals[] = [
      emptySignals(),
      cleanCoveredSignals(),
      { ...emptySignals(), openBlockingViolations: 9 },
      { ...emptySignals(), staleRun: true },
      { ...emptySignals(), gatesAvailable: true, gateFirstPassRate: 0, gateRunCount: 5 },
    ];
    for (const c of cases) {
      const r = computeRisk(c);
      expect(['nizke', 'stredni', 'vysoke', 'neurceno']).toContain(r.level);
      expect(Array.isArray(r.reasons)).toBe(true);
      expect(r.reasons.length).toBeGreaterThanOrEqual(1);
      expect(['high', 'low']).toContain(r.confidence);
      for (const reason of r.reasons) {
        expect(typeof reason.text).toBe('string');
        expect(reason.text.length).toBeGreaterThan(0);
        expect(typeof reason.signal).toBe('string');
        expect(typeof reason.status).toBe('string');
      }
    }
  });

  it('is deterministic: same input → identical output across repeated calls', () => {
    const s: RiskSignals = {
      ...emptySignals(),
      complianceAvailable: true,
      openBlockingViolations: 1,
      forceOverrideCount: 1,
    };
    const a = computeRisk(s);
    const b = computeRisk(s);
    expect(a).toEqual(b);
  });
});
