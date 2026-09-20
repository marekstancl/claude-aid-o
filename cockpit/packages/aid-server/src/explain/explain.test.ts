/**
 * explain() behaviour tests (EPIC E-047-3_7, Step 9) — spec §6.4.
 *
 * AC2: deterministic — same input → identical Czech string across calls.
 * AC3: a null/absent signal explains as a flagged Czech phrase, never a
 *      fabricated positive.
 * AC4: FSM states / checkpoint verdicts / gate results map to non-empty Czech.
 * Plus: never-throws, key resolution precedence, status→colour wiring.
 */

import { afterEach, describe, it, expect, vi } from 'vitest';
import { STATUS } from '@aid/contract';
import {
  explain,
  interpolate,
  resolveEntry,
  resolveKeyCandidates,
  setUnknownIdSink,
  MISSING_VAR_PLACEHOLDER,
} from './explain.js';

describe('explain() — AC2: deterministic', () => {
  it('returns an identical object across repeated calls', () => {
    const input = { kind: 'state' as const, id: 'EXECUTE', context: { step: 3, total_steps: 9 } };
    const a = explain(input);
    const b = explain(input);
    expect(a).toEqual(b);
    expect(a.headline).toBe('Pracuje se — krok 3 z 9');
  });

  it('interpolates context vars deterministically (no Date, no randomness)', () => {
    const out1 = explain({ kind: 'event', id: 'gate_complete', context: { gate: 'lint', passed: true } });
    const out2 = explain({ kind: 'event', id: 'gate_complete', context: { gate: 'lint', passed: true } });
    expect(out1.headline).toBe('Brána lint prošla.');
    expect(out1).toEqual(out2);
  });
});

describe('explain() — AC3: honesty for null / absent signals', () => {
  it('a null interpolation var renders the flagged placeholder, never an empty positive', () => {
    const out = explain({ kind: 'state', id: 'EXECUTE', context: { step: 3, total_steps: null } });
    expect(out.headline).toContain(MISSING_VAR_PLACEHOLDER);
    expect(out.headline).not.toBe('Pracuje se — krok 3 z '); // never a silent gap
  });

  it('an absent context renders all vars as the flagged placeholder', () => {
    const out = explain({ kind: 'state', id: 'EXECUTE' });
    expect(out.headline).toBe(`Pracuje se — krok ${MISSING_VAR_PLACEHOLDER} z ${MISSING_VAR_PLACEHOLDER}`);
  });

  it('a not-yet-run verdict explains as "ještě neproběhla", never a pass', () => {
    const out = explain({ kind: 'verdict', id: 'pending' });
    expect(out.status).toBe('ceka');
    expect(out.headline).toContain('neproběhla');
    expect(out.headline).not.toContain('PROŠLO');
  });

  it('risk with insufficient data explains as "zatím nelze určit", never low risk', () => {
    const out = explain({ kind: 'concept', id: 'risk:neurceno' });
    expect(out.status).toBe('ceka');
    expect(out.detail).toContain('zatím nelze určit');
    expect(out.detail).not.toContain('nízké');
  });

  it('success probability slot is the MVP2 placeholder, never a fabricated number', () => {
    const out = explain({ kind: 'concept', id: 'success_probability_mvp2' });
    expect(out.status).toBe('ceka');
    expect(out.detail).toContain('MVP2');
    expect(out.detail).not.toMatch(/\d+\s*%/);
  });

  it('a missing discriminator does NOT silently match a positive-coded specific key', () => {
    // gate_complete with no pass/fail flavour falls back to the generic event key,
    // not to the ":pass" (proslo) key.
    const out = explain({ kind: 'event', id: 'gate_complete', context: { gate: 'tests' } });
    expect(out.status).not.toBe('proslo');
  });
});

describe('explain() — AC4: states / checkpoints / gates map to non-empty Czech', () => {
  it('every FSM state resolves to a non-empty headline + detail', () => {
    for (const s of ['READY', 'EXECUTE', 'GATES', 'ESCALATION', 'DONE', 'ERROR']) {
      const out = explain({ kind: 'state', id: s, context: { step: 1, total_steps: 1 } });
      expect(out.headline.length, s).toBeGreaterThan(0);
      expect(out.detail.length, s).toBeGreaterThan(0);
    }
  });

  it('every checkpoint resolves to a non-empty explanation', () => {
    for (const cp of ['CP1', 'CP2', 'CP3', 'CP4', 'CP5', 'CP6']) {
      const out = explain({ kind: 'cp', id: cp });
      expect(out.detail.length, cp).toBeGreaterThan(0);
    }
  });

  it('gate pass / fail / skip results resolve to distinct non-empty Czech', () => {
    expect(explain({ kind: 'verdict', id: 'pass' }).headline).toContain('PROŠLO');
    expect(explain({ kind: 'verdict', id: 'fail' }).headline).toContain('NEPROŠLO');
    expect(explain({ kind: 'verdict', id: 'SKIP', context: { reason: 'triviální' } }).headline).toContain(
      'přeskočena',
    );
  });
});

describe('explain() — status → colour wiring (§6.2)', () => {
  it('attaches the resolved CSS-var colour for the entry status', () => {
    const out = explain({ kind: 'state', id: 'DONE' });
    expect(out.status).toBe('proslo');
    expect(out.color).toBe(STATUS.proslo.color);
  });
});

describe('explain() — never throws + unknown-id fallback (§6.3 narrator)', () => {
  afterEach(() => {
    // Restore the default sink after any swap.
    setUnknownIdSink((key) => {
      // eslint-disable-next-line no-console
      console.warn(`[explain] unknown dictionary key: ${key}`);
    });
  });

  it('unknown id returns a flagged "Neznámá událost" explanation, not a throw', () => {
    const sink = vi.fn();
    setUnknownIdSink(sink);
    const out = explain({ kind: 'event', id: 'totally_made_up_event_xyz' });
    expect(out.headline).toBe('Neznámá událost: totally_made_up_event_xyz');
    expect(out.detail).toContain('zatím nemá lidský popis');
    expect(out.status).toBe('ceka');
    expect(out.color).toBe(STATUS.ceka.color);
    expect(sink).toHaveBeenCalledOnce();
  });

  it('survives weird input shapes without throwing', () => {
    expect(() => explain({ kind: 'event', id: '' })).not.toThrow();
    expect(() => explain({ kind: 'concept', id: 'x', context: {} })).not.toThrow();
  });
});

describe('resolveKeyCandidates — precedence (§6.4)', () => {
  it('event transition: from→to, then *→to, then bare', () => {
    const keys = resolveKeyCandidates({
      kind: 'event',
      id: 'fsm_transition',
      context: { from: 'GATES', to: 'EXECUTE' },
    });
    expect(keys).toEqual([
      'event:fsm_transition:GATES→EXECUTE',
      'event:fsm_transition:*→EXECUTE',
      'event:fsm_transition',
    ]);
  });

  it('resolves the wildcard *→ESCALATION when the specific composite is absent', () => {
    const entry = resolveEntry({
      kind: 'event',
      id: 'fsm_transition',
      context: { from: 'EXECUTE', to: 'ESCALATION' },
    });
    expect(entry?.headlineTemplate).toBe('Zaseklo se to, eskaluje se k řešení.');
  });

  it('compliance overall:pass resolves via the overall discriminator', () => {
    const out = explain({ kind: 'check', id: 'overall', context: { overall: 'pass' } });
    expect(out.headline).toBe('Soulad s pravidly: v pořádku.');
  });

  it('bare key always backs a specific one', () => {
    const keys = resolveKeyCandidates({ kind: 'state', id: 'READY' });
    expect(keys[keys.length - 1]).toBe('state:READY');
  });
});

describe('interpolate — unit', () => {
  it('substitutes present vars', () => {
    expect(interpolate('krok {step} z {total}', { step: 2, total: 5 })).toBe('krok 2 z 5');
  });
  it('flags null / undefined / empty-string vars', () => {
    expect(interpolate('a {x} b', { x: null })).toBe(`a ${MISSING_VAR_PLACEHOLDER} b`);
    expect(interpolate('a {x} b', {})).toBe(`a ${MISSING_VAR_PLACEHOLDER} b`);
    expect(interpolate('a {x} b', { x: '' })).toBe(`a ${MISSING_VAR_PLACEHOLDER} b`);
  });
  it('renders 0 (not flagged — zero is a real measured value)', () => {
    expect(interpolate('{count} oprav', { count: 0 })).toBe('0 oprav');
  });
});
