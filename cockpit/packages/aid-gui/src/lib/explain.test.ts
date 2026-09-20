/**
 * Tests for explain.ts — resolveExplanation + explainEvent (§6.4).
 *
 * The §6.3/§13.10 dictionary is normally served by /api/explanations; these
 * tests build a minimal dictionary fixture carrying the exact §6.3/§13.10 Czech
 * headlines + status tokens for the keys under test.
 */

import { describe, it, expect } from 'vitest';
import type { ActivityEvent, DictionaryEntry } from '@aid/contract';
import { STATUS } from '@aid/contract';
import { resolveExplanation, explainEvent, eventKey, type Dictionary } from './explain';

function entry(partial: Partial<DictionaryEntry> & Pick<DictionaryEntry, 'id' | 'kind' | 'status'>): DictionaryEntry {
  return {
    headlineTemplate: '',
    detailTemplate: '',
    term: partial.id,
    keywords: [],
    ...partial,
  };
}

// Minimal dictionary with the exact §6.3 / §13.10 strings for the keys under test.
const DICT: Dictionary = {
  'event:fsm_transition:GATES_to_DONE': entry({
    id: 'event:fsm_transition:GATES_to_DONE',
    kind: 'event',
    status: 'proslo',
    headlineTemplate: 'Všechny brány prošly — míříme k dokončení.',
    detailTemplate: 'Brány GATES prošly, běh míří do DONE.',
  }),
  'role:auditor:blocking': entry({
    id: 'role:auditor:blocking',
    kind: 'role',
    status: 'zablokovano',
    headlineTemplate: 'Auditor našel kritický nález — merge je zablokovaný, dokud to PM neposoudí.',
    detailTemplate: 'Auditor flagnul blocking_findings.',
  }),
  'concept:risk:vysoke': entry({
    id: 'concept:risk:vysoke',
    kind: 'concept',
    status: 'zablokovano',
    headlineTemplate:
      'Riziko vysoké - blokující porušení, kritický nález auditu, systematické obcházení kontrol nebo padající brány.',
    detailTemplate: '',
  }),
};

function activity(partial: Partial<ActivityEvent> & Pick<ActivityEvent, 'event'>): ActivityEvent {
  return {
    projectId: 'wan',
    ts: '2026-06-21T10:00:00Z',
    raw: {},
    ...partial,
  };
}

describe('eventKey', () => {
  it('builds the GATES_to_DONE transition key', () => {
    expect(eventKey(activity({ event: 'fsm_transition', from: 'GATES', to: 'DONE' }))).toBe(
      'event:fsm_transition:GATES_to_DONE',
    );
  });

  it('builds the auditor:blocking role key', () => {
    expect(eventKey(activity({ event: 'audit', role: 'auditor', raw: { verdict: 'blocking' } }))).toBe(
      'role:auditor:blocking',
    );
  });
});

describe('explainEvent — resolves §6.3 keys', () => {
  it('event:fsm_transition:GATES_to_DONE → exact headline + proslo', () => {
    const ex = explainEvent(activity({ event: 'fsm_transition', from: 'GATES', to: 'DONE' }), DICT);
    expect(ex.headline).toBe('Všechny brány prošly — míříme k dokončení.');
    expect(ex.status).toBe('proslo');
    expect(ex.color).toBe(STATUS.proslo.color);
  });

  it('role:auditor:blocking → exact headline + zablokovano', () => {
    const ex = explainEvent(activity({ event: 'audit', role: 'auditor', raw: { verdict: 'blocking' } }), DICT);
    expect(ex.headline).toBe(
      'Auditor našel kritický nález — merge je zablokovaný, dokud to PM neposoudí.',
    );
    expect(ex.status).toBe('zablokovano');
    expect(ex.color).toBe(STATUS.zablokovano.color);
  });

  it('unknown key → graceful ceka fallback (never throws/blank)', () => {
    const ex = explainEvent(activity({ event: 'totally_unknown_event' }), DICT);
    expect(ex.status).toBe('ceka');
    expect(ex.color).toBe(STATUS.ceka.color);
    expect(ex.headline).toBe('totally_unknown_event');
    expect(ex.detail.length).toBeGreaterThan(0);
  });
});

describe('resolveExplanation', () => {
  it('concept:risk:vysoke → exact §13.10 headline + zablokovano colour', () => {
    const ex = resolveExplanation(DICT['concept:risk:vysoke']);
    expect(ex.headline).toBe(
      'Riziko vysoké - blokující porušení, kritický nález auditu, systematické obcházení kontrol nebo padající brány.',
    );
    expect(ex.status).toBe('zablokovano');
    expect(ex.color).toBe(STATUS.zablokovano.color);
  });

  it('interpolates {count} / {staleDays} vars into the headline', () => {
    const e = entry({
      id: 'concept:stale_run',
      kind: 'concept',
      status: 'pozor',
      headlineTemplate: 'Rozdělaný běh se {staleDays} dní nehnul.',
    });
    expect(resolveExplanation(e, { staleDays: 5 }).headline).toBe('Rozdělaný běh se 5 dní nehnul.');
  });

  it('absent/unknown status token → ceka fallback, colour never undefined', () => {
    const e = entry({
      id: 'concept:weird',
      kind: 'concept',
      // deliberately invalid status token
      status: 'nonsense' as never,
      headlineTemplate: 'x',
    });
    const ex = resolveExplanation(e);
    expect(ex.status).toBe('ceka');
    expect(ex.color).toBe(STATUS.ceka.color);
    expect(ex.color).toBeDefined();
  });
});
