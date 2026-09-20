/**
 * Unit tests for the lessons-per-plan builder + never-throw parser
 * (EPIC E-047-4_7, Step 8 — §13.8 / §4.7 / §7.6, AC #21).
 *
 * Pure-function coverage of {@link buildLessons} (3 scopes), {@link parseLessons}
 * (kind classification, ragged rows, malformed/absent → []), {@link classifyKind},
 * {@link parseLessonDate} (ISO / raw / null), and the chronological-desc-vs-file-
 * order sort. The route integration (real HTTP + real scanner) lives in
 * routes/lessons.test.ts; this file is the pure layer.
 */

import { describe, it, expect } from 'vitest';
import type { LessonEntry } from '@aid/contract';
import {
  buildLessons,
  parseLessons,
  classifyKind,
  parseLessonDate,
  sortLessons,
} from './build-lessons.js';

const MAIN_TABLE = `# Lessons Learned

| Date | Lesson | Context |
|------|--------|---------|
| 2026-02-19 | Older lesson about parallel groups | E-046-1_3 |
| 2026-06-18 | Newest lesson about membership reconciliation | E-046-3_3 |
| 2026-03-01 | A lesson with no context cell | |

## Known Gotchas

| Area | Gotcha |
|------|--------|
| Agent dispatch | Switch model to sonnet on Claude 500 |
| Gates | docs_updated must be type: rule on plugin repos |
`;

describe('parseLessons (§4.7 never-throw parser)', () => {
  it('parses main-table rows as kind:lesson and Known-Gotchas rows as kind:gotcha (AC#2)', () => {
    const entries = parseLessons(MAIN_TABLE);
    const lessons = entries.filter((e) => e.kind === 'lesson');
    const gotchas = entries.filter((e) => e.kind === 'gotcha');

    expect(lessons.length).toBe(3);
    expect(gotchas.length).toBe(2);

    // Main-table row: date + lesson + epicId.
    expect(lessons[0]).toMatchObject({
      date: '2026-02-19',
      lesson: 'Older lesson about parallel groups',
      epicId: 'E-046-1_3',
      kind: 'lesson',
    });

    // Known-Gotchas row: Area cell is free text (raw date), no Context → epicId null.
    expect(gotchas[0]).toMatchObject({
      date: 'Agent dispatch',
      epicId: null,
      kind: 'gotcha',
    });
    expect(gotchas[0].lesson).toContain('Switch model to sonnet');
  });

  it('a lesson row with an empty Context cell → epicId:null (AC#6)', () => {
    const entries = parseLessons(MAIN_TABLE);
    const noCtx = entries.find((e) => e.lesson === 'A lesson with no context cell');
    expect(noCtx).toBeDefined();
    expect(noCtx!.epicId).toBeNull();
    expect(noCtx!.kind).toBe('lesson');
  });

  it('returns [] for null / empty / whitespace input (AC#3 — never throws)', () => {
    expect(parseLessons(null)).toEqual([]);
    expect(parseLessons('')).toEqual([]);
    expect(parseLessons('   \n  \n')).toEqual([]);
  });

  it('tolerates malformed / ragged tables without throwing (AC#3)', () => {
    const malformed = `# Lessons

| Date | Lesson | Context |
|------|--------|---------|
| 2026-01-01 | one good lesson | E-001-1_1 |
| ragged-no-closing-pipe
| | | |
not a table line at all
| 2026-01-02 |
`;
    let entries: LessonEntry[] = [];
    expect(() => {
      entries = parseLessons(malformed);
    }).not.toThrow();
    // Only the one well-formed lesson row survives; the date-only row (no lesson
    // text) and the non-table lines are dropped, never crash.
    expect(entries.length).toBe(1);
    expect(entries[0].lesson).toBe('one good lesson');
  });

  it('skips header + separator rows', () => {
    const entries = parseLessons(MAIN_TABLE);
    expect(entries.some((e) => e.lesson.toLowerCase() === 'lesson')).toBe(false);
    expect(entries.some((e) => /^:?-+:?$/.test(e.lesson))).toBe(false);
  });
});

describe('classifyKind (§4.7)', () => {
  it('Known Gotchas heading → gotcha (any level, case-insensitive)', () => {
    expect(classifyKind('## Known Gotchas')).toBe('gotcha');
    expect(classifyKind('### known gotchas')).toBe('gotcha');
    expect(classifyKind('Known Gotchas')).toBe('gotcha');
  });

  it('any other heading / null → lesson', () => {
    expect(classifyKind('## Lessons Learned')).toBe('lesson');
    expect(classifyKind(null)).toBe('lesson');
    expect(classifyKind('')).toBe('lesson');
  });
});

describe('parseLessonDate (§13.8 AC#5)', () => {
  it('a parseable ISO date stays date-only', () => {
    expect(parseLessonDate('2026-02-19')).toBe('2026-02-19');
  });

  it('a full timestamp keeps its ISO instant', () => {
    expect(parseLessonDate('2026-06-18T14:00:00Z')).toBe('2026-06-18T14:00:00.000Z');
  });

  it('an unparseable cell is kept RAW (never faked into ISO)', () => {
    expect(parseLessonDate('Agent dispatch')).toBe('Agent dispatch');
    expect(parseLessonDate('sometime last week')).toBe('sometime last week');
  });

  it('an empty / whitespace cell → null', () => {
    expect(parseLessonDate('')).toBeNull();
    expect(parseLessonDate('   ')).toBeNull();
  });
});

describe('sortLessons (chronological-desc, undated → file order tail)', () => {
  it('sorts dated entries newest-first; undated entries keep file order after them (AC#5)', () => {
    const input: LessonEntry[] = [
      { date: '2026-02-19', lesson: 'feb', epicId: null, kind: 'lesson' },
      { date: 'undated-A', lesson: 'rawA', epicId: null, kind: 'gotcha' },
      { date: '2026-06-18', lesson: 'jun', epicId: null, kind: 'lesson' },
      { date: 'undated-B', lesson: 'rawB', epicId: null, kind: 'gotcha' },
      { date: null, lesson: 'nullDate', epicId: null, kind: 'lesson' },
    ];
    const sorted = sortLessons(input);
    expect(sorted.map((e) => e.lesson)).toEqual([
      'jun', // 2026-06-18 (newest)
      'feb', // 2026-02-19
      'rawA', // undated → file order
      'rawB',
      'nullDate',
    ]);
  });
});

describe('buildLessons — 3 scopes (§13.8)', () => {
  const parsed = parseLessons(MAIN_TABLE);

  it('project scope → every parsed lesson (incl. no-context + gotchas), sorted desc', () => {
    const view = buildLessons(parsed, 'project', undefined, { projectId: 'demo' });
    expect(view.scope).toBe('project');
    expect(view.projectId).toBe('demo');
    expect(view.planId).toBeNull();
    expect(view.total).toBe(parsed.length); // all 5
    expect(view.entries.length).toBe(5);
    // chronological-desc: the dated 2026-06-18 lesson is first.
    expect(view.entries[0].date).toBe('2026-06-18');
  });

  it('infra scope → all lessons, no project/plan stamp', () => {
    const view = buildLessons(parsed, 'infra');
    expect(view.scope).toBe('infra');
    expect(view.projectId).toBeNull();
    expect(view.planId).toBeNull();
    expect(view.total).toBe(parsed.length);
  });

  it('plan scope → only lessons whose epicId ∈ planEpicIds (AC#1)', () => {
    const view = buildLessons(parsed, 'plan', ['E-046-1_3', 'E-046-3_3'], {
      projectId: 'demo',
      planId: 'P046',
    });
    expect(view.scope).toBe('plan');
    expect(view.planId).toBe('P046');
    // 2 of the main-table rows match; the no-context row + both gotchas excluded.
    expect(view.total).toBe(2);
    expect(view.entries.map((e) => e.epicId).sort()).toEqual(['E-046-1_3', 'E-046-3_3']);
    // newest-first.
    expect(view.entries[0].epicId).toBe('E-046-3_3'); // 2026-06-18
  });

  it('plan scope EXCLUDES a no-context lesson but project/infra KEEP it (AC#6)', () => {
    const planView = buildLessons(parsed, 'plan', ['E-046-1_3', 'E-046-3_3']);
    expect(planView.entries.some((e) => e.epicId === null)).toBe(false);

    const projectView = buildLessons(parsed, 'project');
    expect(projectView.entries.some((e) => e.epicId === null)).toBe(true);
  });

  it('plan scope with NO member ids → empty + a warning (honest, no throw)', () => {
    const view = buildLessons(parsed, 'plan', []);
    expect(view.total).toBe(0);
    expect(view.entries).toEqual([]);
    expect(view.warnings.some((w) => w.toLowerCase().includes('no lessons match'))).toBe(true);
  });

  it('empty parsed input → entries:[] + an "absent/empty" warning (AC#3)', () => {
    const view = buildLessons([], 'project', undefined, { projectId: 'demo' });
    expect(view.entries).toEqual([]);
    expect(view.total).toBe(0);
    expect(view.warnings.some((w) => w.toLowerCase().includes('absent'))).toBe(true);
  });
});
