/**
 * Czech dictionary coverage tests (EPIC E-047-3_7, Step 9) — spec §6.3 + §13.10.
 *
 * AC1: the dictionary covers every term §6.3 / §13.10 lists (transcribed, not
 * invented) — key presence + a few exact Czech values.
 * AC4: FSM states, checkpoint verdicts and gate results all map to non-empty
 * Czech strings.
 * AC5: all dictionary VALUES are Czech (no English UI strings).
 */

import { describe, it, expect } from 'vitest';
import { STATUS } from '@aid/contract';
import type { StatusKey } from '@aid/contract';
import { DICTIONARY_CS } from './dictionary.cs.js';

const ALL_STATUS_KEYS = Object.keys(STATUS) as StatusKey[];

describe('dictionary.cs — structural integrity', () => {
  it('every entry has the full DictionaryEntry shape with non-empty Czech values (AC4)', () => {
    for (const [key, entry] of Object.entries(DICTIONARY_CS)) {
      expect(entry.id, `${key}.id`).toBeTruthy();
      expect(entry.kind, `${key}.kind`).toBeTruthy();
      expect(entry.headlineTemplate.length, `${key}.headlineTemplate`).toBeGreaterThan(0);
      expect(entry.detailTemplate.length, `${key}.detailTemplate`).toBeGreaterThan(0);
      expect(entry.term.length, `${key}.term`).toBeGreaterThan(0);
      expect(entry.keywords.length, `${key}.keywords`).toBeGreaterThan(0);
    }
  });

  it('every status is a valid §6.2 STATUS token', () => {
    for (const [key, entry] of Object.entries(DICTIONARY_CS)) {
      expect(ALL_STATUS_KEYS, `${key}.status=${entry.status}`).toContain(entry.status);
    }
  });

  it('every kind is a valid DictionaryEntry kind', () => {
    const validKinds = ['state', 'event', 'cp', 'role', 'verdict', 'severity', 'check', 'concept'];
    for (const [key, entry] of Object.entries(DICTIONARY_CS)) {
      expect(validKinds, `${key}.kind`).toContain(entry.kind);
    }
  });
});

describe('dictionary.cs — §6.3 A. FSM states (6)', () => {
  const states = ['READY', 'EXECUTE', 'GATES', 'ESCALATION', 'DONE', 'ERROR'];

  it('covers all 6 FSM states (AC4)', () => {
    for (const s of states) {
      expect(DICTIONARY_CS[`state:${s}`], `state:${s}`).toBeDefined();
    }
  });

  it('transcribes exact §6.3 Czech values + statuses', () => {
    expect(DICTIONARY_CS['state:READY'].headlineTemplate).toBe('Připraveno ke spuštění');
    expect(DICTIONARY_CS['state:READY'].status).toBe('ceka');
    expect(DICTIONARY_CS['state:EXECUTE'].headlineTemplate).toBe(
      'Pracuje se — krok {step} z {total_steps}',
    );
    expect(DICTIONARY_CS['state:EXECUTE'].status).toBe('bezi');
    expect(DICTIONARY_CS['state:GATES'].headlineTemplate).toBe('Kontroly kvality');
    expect(DICTIONARY_CS['state:ESCALATION'].status).toBe('eskalace');
    expect(DICTIONARY_CS['state:DONE'].status).toBe('proslo');
    expect(DICTIONARY_CS['state:ERROR'].status).toBe('selhalo');
  });
});

describe('dictionary.cs — §6.3 C. CP1-CP6 checkpoints', () => {
  const cps = ['CP1', 'CP2', 'CP3', 'CP4', 'CP5', 'CP6'];

  it('covers all 6 checkpoints (AC4)', () => {
    for (const cp of cps) {
      expect(DICTIONARY_CS[`cp:${cp}`], `cp:${cp}`).toBeDefined();
    }
  });

  it('transcribes the exact CP3 / CP5 detail text', () => {
    expect(DICTIONARY_CS['cp:CP3'].detailTemplate).toContain('integrační kontrola celé EPICy');
    expect(DICTIONARY_CS['cp:CP3'].detailTemplate).toContain('base..HEAD');
    expect(DICTIONARY_CS['cp:CP5'].detailTemplate).toContain('blocking_findings');
  });
});

describe('dictionary.cs — §6.3 E. verifier verdicts (gate/verifier results)', () => {
  const verdicts = ['RUN', 'SKIP', 'FULL_REVIEW', 'pass', 'pass_with_notes', 'fail', 'pending'];

  it('covers all 7 verdicts incl. gate pass/fail/skip semantics (AC4)', () => {
    for (const v of verdicts) {
      expect(DICTIONARY_CS[`verdict:${v}`], `verdict:${v}`).toBeDefined();
    }
  });

  it('gate results map to distinct non-empty Czech', () => {
    expect(DICTIONARY_CS['verdict:pass'].headlineTemplate).toBe('Kontrolor: PROŠLO.');
    expect(DICTIONARY_CS['verdict:fail'].status).toBe('selhalo');
    expect(DICTIONARY_CS['verdict:SKIP'].status).toBe('proslo');
    expect(DICTIONARY_CS['event:gate_complete:pass'].status).toBe('proslo');
    expect(DICTIONARY_CS['event:gate_complete:fail'].status).toBe('selhalo');
  });
});

describe('dictionary.cs — §6.3 F. compliance severities + checks', () => {
  it('covers severities + overall pass/fail', () => {
    expect(DICTIONARY_CS['severity:blocking'].status).toBe('zablokovano');
    expect(DICTIONARY_CS['severity:advisory'].status).toBe('pozor');
    expect(DICTIONARY_CS['compliance:overall:pass'].status).toBe('proslo');
    expect(DICTIONARY_CS['compliance:overall:fail'].status).toBe('selhalo');
  });

  it('covers every §6.3 F check key', () => {
    const checks = [
      'verifier_provenance',
      'gates_generated_by',
      'plan_ac_match',
      'dispatch_orphan_complete',
      'branch_correct',
      'memory_substantive',
      'dod_present',
      'delivery_report_present',
    ];
    for (const c of checks) {
      expect(DICTIONARY_CS[`check:${c}`], `check:${c}`).toBeDefined();
    }
  });
});

describe('dictionary.cs — §6.3 D. role verdicts', () => {
  it('covers auditor / curator / reporter / simplifier outcomes', () => {
    const roles = [
      'role:auditor:clean',
      'role:auditor:blocking',
      'role:auditor:recommended',
      'role:curator:proposals',
      'role:curator:empty',
      'role:reporter:pass',
      'role:reporter:fail',
      'role:reporter:no_evidence',
      'role:simplifier:proposals',
      'role:simplifier:none',
    ];
    for (const r of roles) {
      expect(DICTIONARY_CS[r], r).toBeDefined();
    }
    expect(DICTIONARY_CS['role:auditor:blocking'].status).toBe('zablokovano');
  });
});

describe('dictionary.cs — §13.10 concept keys (additive)', () => {
  it('covers all 11 concept:* keys with exact statuses', () => {
    expect(DICTIONARY_CS['concept:risk:nizke'].status).toBe('proslo');
    expect(DICTIONARY_CS['concept:risk:stredni'].status).toBe('pozor');
    expect(DICTIONARY_CS['concept:risk:vysoke'].status).toBe('zablokovano');
    expect(DICTIONARY_CS['concept:risk:neurceno'].status).toBe('ceka');
    expect(DICTIONARY_CS['concept:stale_run'].headlineTemplate).toContain('{staleDays}');
    expect(DICTIONARY_CS['concept:stuck_or_looping']).toBeDefined();
    expect(DICTIONARY_CS['concept:decision_needed'].status).toBe('eskalace');
    expect(DICTIONARY_CS['concept:success_probability_mvp2'].status).toBe('ceka');
    expect(DICTIONARY_CS['concept:since_first_visit']).toBeDefined();
    expect(DICTIONARY_CS['concept:plan_membership_derived'].status).toBe('pozor');
    expect(DICTIONARY_CS['concept:aggregate_audit_sparse']).toBeDefined();
  });
});

describe('dictionary.cs — AC5: all VALUES are Czech, no English UI strings', () => {
  // A small denylist of English function words that would betray un-translated
  // prose. Machine tokens are intentionally NOT listed: {var} placeholders,
  // RUN/SKIP/FAIL verdicts, CPn, HEAD/base..HEAD, MVP2, AID, PM, and the
  // tool name "code-review" are all legitimate spec vocabulary, not prose.
  // The boundary is hyphen-aware so "code-review" does not trip "review".
  const ENGLISH_PROSE = /(^|[\s.,;:()])(the|and|with|from|that|this|failed|passed|running|because)([\s.,;:()]|$)/i;

  it('no headline/detail contains English prose', () => {
    for (const [key, entry] of Object.entries(DICTIONARY_CS)) {
      expect(ENGLISH_PROSE.test(entry.headlineTemplate), `${key}.headline: ${entry.headlineTemplate}`).toBe(
        false,
      );
      expect(ENGLISH_PROSE.test(entry.detailTemplate), `${key}.detail: ${entry.detailTemplate}`).toBe(
        false,
      );
    }
  });
});
