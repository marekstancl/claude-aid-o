import { describe, it, expect } from 'vitest';
import type {
  AidFsmState,
  FsmState,
  SuccessProbability,
  ComplianceFailure,
  ComplianceRun,
  MembershipSource,
} from '../src/index.js';
import { STATUS, ALL_EVENT_TOPICS } from '../src/index.js';

// ── 1. AidFsmState (raw) accepts 'ERROR' ─────────────────────────────────────
describe('AidFsmState', () => {
  it('accepts ERROR as a member', () => {
    const x: AidFsmState = 'ERROR';
    expect(x).toBe('ERROR');
  });
});

// ── 2. FsmState (view) — 6-member union, accepts 'ERROR' ─────────────────────
describe('FsmState (view)', () => {
  it('accepts ERROR as a member', () => {
    const x: FsmState = 'ERROR';
    expect(x).toBe('ERROR');
  });
});

// ── 3. SuccessProbability MVP1 invariant ──────────────────────────────────────
describe('SuccessProbability', () => {
  it('MVP1 invariant: value === null && source === null', () => {
    const sp: SuccessProbability = { value: null, source: null };
    expect(sp.value).toBeNull();
    expect(sp.source).toBeNull();
  });
});

// ── 4. STATUS — exactly 8 tokens with §6.2 keys and hex values ───────────────
describe('STATUS', () => {
  it('has exactly 8 keys', () => {
    expect(Object.keys(STATUS)).toHaveLength(8);
  });

  it('has all §6.2 keys', () => {
    const keys = Object.keys(STATUS);
    for (const k of ['bezi','ceka','proslo','selhalo','zablokovano','eskalace','pozor','necinne']) {
      expect(keys).toContain(k);
    }
  });

  it('has exact §6.2 hex values', () => {
    expect(STATUS.bezi.hex).toBe('#0284c7');
    expect(STATUS.ceka.hex).toBe('#64748b');
    expect(STATUS.proslo.hex).toBe('#059669');
    expect(STATUS.selhalo.hex).toBe('#dc2626');
    expect(STATUS.zablokovano.hex).toBe('#d97706');
    expect(STATUS.eskalace.hex).toBe('#ea580c');
    expect(STATUS.pozor.hex).toBe('#ca8a04');
    expect(STATUS.necinne.hex).toBe('#475569');
  });
});

// ── 5. ComplianceRun.failures is ComplianceFailure[] (object shape) ───────────
describe('ComplianceRun.failures', () => {
  it('accepts ComplianceFailure objects with check/evidence/severity', () => {
    const f: ComplianceFailure = {
      check: 'bats_fsm',
      evidence: 'step-0-verify.md',
      severity: 'blocking',
    };
    const run: Pick<ComplianceRun, 'failures'> = { failures: [f] };
    expect(run.failures[0].severity).toBe('blocking');
    expect(run.failures[0].check).toBe('bats_fsm');
  });
});

// ── 6. MembershipSource accepts 'derived' ────────────────────────────────────
describe('MembershipSource', () => {
  it('accepts the derived tier', () => {
    const s: MembershipSource = 'derived';
    expect(s).toBe('derived');
  });
});

// ── 7. ALL_EVENT_TOPICS — exact P047 §7.3 vocabulary (regression guard) ──────
describe('ALL_EVENT_TOPICS', () => {
  const REQUIRED_TOPICS = [
    'pipeline', 'pipeline.timeline', 'gates', 'compliance',
    'checkpoints', 'queue', 'decisions', 'audit',
    'epics', 'backlog', 'config', 'system',
  ] as const;

  it('contains exactly 12 topics', () => {
    expect(ALL_EVENT_TOPICS).toHaveLength(12);
  });

  it('contains all required P047 §7.3 topics', () => {
    for (const topic of REQUIRED_TOPICS) {
      expect(ALL_EVENT_TOPICS).toContain(topic);
    }
  });

  it('does NOT contain deprecated topics (pipeline.stage_log, evidence, usage)', () => {
    expect(ALL_EVENT_TOPICS).not.toContain('pipeline.stage_log');
    expect(ALL_EVENT_TOPICS).not.toContain('evidence');
    expect(ALL_EVENT_TOPICS).not.toContain('usage');
  });
});

// ── 8. Mismatch guard: FsmState has ERROR (regression guard for §4.1) ─────────
// If someone removes ERROR from FsmState, this type-level check becomes never
// and the assignment below fails to compile — catching the regression at build time.
type Legacy5State = 'READY' | 'EXECUTE' | 'GATES' | 'ESCALATION' | 'DONE';
type _ErrorPresentGuard = FsmState extends Legacy5State ? never : 'ok';
describe('FsmState mismatch guard (§4.1 regression)', () => {
  it('FsmState is NOT a subtype of the 5-member legacy union (ERROR present)', () => {
    const guard: _ErrorPresentGuard = 'ok';
    expect(guard).toBe('ok');
  });
});
