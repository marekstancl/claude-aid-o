/**
 * Unit tests for the InsightsSlice in the Zustand store.
 *
 * Covered fields:
 *   backlogEntries    — improvement backlog items
 *   lessonEntries     — lessons learned and gotcha entries
 *   insightsLoading   — loading indicator
 *
 * All tests reset the store to its initial state before running, preventing
 * state leaks from the singleton Zustand store across tests.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { useStore } from '../../src/store.ts';
import type { BacklogEntry, LessonEntry } from '../../src/types/api.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function resetStore(): void {
  useStore.setState(useStore.getInitialState());
}

function makeBacklogEntry(overrides: Partial<BacklogEntry> = {}): BacklogEntry {
  return {
    id: 'BL-001',
    type: 'refactoring',
    area: 'src/api/',
    description: 'Extract shared validation logic',
    priority: 'medium',
    source: 'auditor-agent',
    status: 'open',
    ...overrides,
  };
}

function makeLessonEntry(overrides: Partial<LessonEntry> = {}): LessonEntry {
  return {
    id: 'LL-001',
    category: 'lesson',
    lesson: 'Always validate input at the boundary',
    context: 'API endpoint testing revealed missing validation',
    impact: 'Prevented 3 downstream bugs',
    ...overrides,
  };
}

function makeGotchaEntry(overrides: Partial<LessonEntry> = {}): LessonEntry {
  return {
    id: 'GC-001',
    category: 'gotcha',
    gotcha: 'Express middleware order matters',
    when: 'Adding new middleware after error handler',
    workaround: 'Always register error handler last',
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Test setup
// ---------------------------------------------------------------------------

beforeEach(() => {
  resetStore();
});

// ===========================================================================
// InsightsSlice — initial state
// ===========================================================================

describe('InsightsSlice — initial state', () => {
  it('starts with an empty backlogEntries array', () => {
    expect(useStore.getState().backlogEntries).toEqual([]);
  });

  it('starts with an empty lessonEntries array', () => {
    expect(useStore.getState().lessonEntries).toEqual([]);
  });

  it('starts with insightsLoading false', () => {
    expect(useStore.getState().insightsLoading).toBe(false);
  });
});

// ===========================================================================
// InsightsSlice — setBacklogEntries
// ===========================================================================

describe('InsightsSlice — setBacklogEntries', () => {
  it('replaces the backlog entries list', () => {
    const entries = [
      makeBacklogEntry({ id: 'BL-001', type: 'refactoring' }),
      makeBacklogEntry({ id: 'BL-002', type: 'performance' }),
    ];
    useStore.getState().setBacklogEntries(entries);

    const { backlogEntries } = useStore.getState();
    expect(backlogEntries).toHaveLength(2);
    expect(backlogEntries[0].id).toBe('BL-001');
    expect(backlogEntries[0].type).toBe('refactoring');
    expect(backlogEntries[1].id).toBe('BL-002');
    expect(backlogEntries[1].type).toBe('performance');
  });

  it('accepts an empty array to clear all entries', () => {
    useStore.getState().setBacklogEntries([makeBacklogEntry()]);
    useStore.getState().setBacklogEntries([]);
    expect(useStore.getState().backlogEntries).toEqual([]);
  });

  it('replaces the previous list entirely on successive calls', () => {
    useStore.getState().setBacklogEntries([makeBacklogEntry({ id: 'BL-001' })]);
    useStore.getState().setBacklogEntries([makeBacklogEntry({ id: 'BL-002' })]);

    const { backlogEntries } = useStore.getState();
    expect(backlogEntries).toHaveLength(1);
    expect(backlogEntries[0].id).toBe('BL-002');
  });

  it('preserves all BacklogEntry fields', () => {
    const entry = makeBacklogEntry({
      id: 'BL-005',
      type: 'security',
      area: 'server/auth/',
      description: 'Add rate limiting',
      priority: 'high',
      source: 'security-audit',
      status: 'planned',
    });
    useStore.getState().setBacklogEntries([entry]);

    const stored = useStore.getState().backlogEntries[0];
    expect(stored.id).toBe('BL-005');
    expect(stored.type).toBe('security');
    expect(stored.area).toBe('server/auth/');
    expect(stored.description).toBe('Add rate limiting');
    expect(stored.priority).toBe('high');
    expect(stored.source).toBe('security-audit');
    expect(stored.status).toBe('planned');
  });
});

// ===========================================================================
// InsightsSlice — setLessonEntries
// ===========================================================================

describe('InsightsSlice — setLessonEntries', () => {
  it('replaces the lesson entries list', () => {
    const entries = [
      makeLessonEntry({ id: 'LL-001' }),
      makeGotchaEntry({ id: 'GC-001' }),
    ];
    useStore.getState().setLessonEntries(entries);

    const { lessonEntries } = useStore.getState();
    expect(lessonEntries).toHaveLength(2);
    expect(lessonEntries[0].category).toBe('lesson');
    expect(lessonEntries[1].category).toBe('gotcha');
  });

  it('accepts an empty array to clear all entries', () => {
    useStore.getState().setLessonEntries([makeLessonEntry()]);
    useStore.getState().setLessonEntries([]);
    expect(useStore.getState().lessonEntries).toEqual([]);
  });

  it('replaces the previous list entirely on successive calls', () => {
    useStore.getState().setLessonEntries([makeLessonEntry({ id: 'LL-001' })]);
    useStore.getState().setLessonEntries([makeLessonEntry({ id: 'LL-002' })]);

    const { lessonEntries } = useStore.getState();
    expect(lessonEntries).toHaveLength(1);
    expect(lessonEntries[0].id).toBe('LL-002');
  });

  it('preserves lesson-category fields', () => {
    const lesson = makeLessonEntry({
      id: 'LL-010',
      lesson: 'Test edge cases first',
      context: 'Missing edge case test caused regression',
      impact: 'Critical bug caught in QA',
    });
    useStore.getState().setLessonEntries([lesson]);

    const stored = useStore.getState().lessonEntries[0];
    expect(stored.category).toBe('lesson');
    expect(stored.lesson).toBe('Test edge cases first');
    expect(stored.context).toBe('Missing edge case test caused regression');
    expect(stored.impact).toBe('Critical bug caught in QA');
  });

  it('preserves gotcha-category fields', () => {
    const gotcha = makeGotchaEntry({
      id: 'GC-010',
      gotcha: 'File watcher races on macOS',
      when: 'Rapid file saves during auto-mode',
      workaround: 'Add 50ms debounce to watcher events',
    });
    useStore.getState().setLessonEntries([gotcha]);

    const stored = useStore.getState().lessonEntries[0];
    expect(stored.category).toBe('gotcha');
    expect(stored.gotcha).toBe('File watcher races on macOS');
    expect(stored.when).toBe('Rapid file saves during auto-mode');
    expect(stored.workaround).toBe('Add 50ms debounce to watcher events');
  });

  it('handles mixed lesson and gotcha entries', () => {
    const entries = [
      makeLessonEntry({ id: 'LL-001' }),
      makeGotchaEntry({ id: 'GC-001' }),
      makeLessonEntry({ id: 'LL-002' }),
      makeGotchaEntry({ id: 'GC-002' }),
    ];
    useStore.getState().setLessonEntries(entries);

    const { lessonEntries } = useStore.getState();
    expect(lessonEntries).toHaveLength(4);

    const lessons = lessonEntries.filter((e) => e.category === 'lesson');
    const gotchas = lessonEntries.filter((e) => e.category === 'gotcha');
    expect(lessons).toHaveLength(2);
    expect(gotchas).toHaveLength(2);
  });
});

// ===========================================================================
// InsightsSlice — setInsightsLoading
// ===========================================================================

describe('InsightsSlice — setInsightsLoading', () => {
  it('sets insightsLoading to true', () => {
    useStore.getState().setInsightsLoading(true);
    expect(useStore.getState().insightsLoading).toBe(true);
  });

  it('sets insightsLoading back to false', () => {
    useStore.getState().setInsightsLoading(true);
    useStore.getState().setInsightsLoading(false);
    expect(useStore.getState().insightsLoading).toBe(false);
  });

  it('does not affect backlogEntries when toggling loading', () => {
    useStore.getState().setBacklogEntries([makeBacklogEntry()]);
    useStore.getState().setInsightsLoading(true);
    useStore.getState().setInsightsLoading(false);

    expect(useStore.getState().backlogEntries).toHaveLength(1);
  });

  it('does not affect lessonEntries when toggling loading', () => {
    useStore.getState().setLessonEntries([makeLessonEntry()]);
    useStore.getState().setInsightsLoading(true);
    useStore.getState().setInsightsLoading(false);

    expect(useStore.getState().lessonEntries).toHaveLength(1);
  });
});

// ===========================================================================
// Cross-slice isolation — InsightsSlice
// ===========================================================================

describe('InsightsSlice — cross-slice isolation', () => {
  it('updating backlogEntries does not affect ideas', () => {
    useStore.getState().setIdeas([{
      id: 'I-001',
      title: 'Test idea',
      description: '',
      tags: [],
      priority: 'medium',
      status: 'idea',
      autoStatus: null,
      linkedPlan: null,
      linkedEpic: null,
      createdAt: '2026-02-27T00:00:00Z',
      updatedAt: '2026-02-27T00:00:00Z',
    }]);

    useStore.getState().setBacklogEntries([makeBacklogEntry(), makeBacklogEntry({ id: 'BL-002' })]);

    expect(useStore.getState().ideas).toHaveLength(1);
    expect(useStore.getState().ideas[0].id).toBe('I-001');
  });

  it('updating lessonEntries does not affect queueEntries', () => {
    useStore.getState().setQueueEntries([{
      epicId: 'E-001',
      path: '.aid-o/tasks/E-001.md',
      priority: 'high',
      status: 'queued',
      addedAt: '2026-02-27T00:00:00Z',
      startedAt: null,
      completedAt: null,
    }]);

    useStore.getState().setLessonEntries([makeLessonEntry(), makeGotchaEntry()]);

    expect(useStore.getState().queueEntries).toHaveLength(1);
    expect(useStore.getState().queueEntries[0].epicId).toBe('E-001');
  });

  it('updating InsightsSlice does not corrupt ConnectionSlice', () => {
    useStore.getState().setWsStatus('connected');

    useStore.getState().setBacklogEntries([makeBacklogEntry()]);
    useStore.getState().setLessonEntries([makeLessonEntry()]);
    useStore.getState().setInsightsLoading(true);

    expect(useStore.getState().wsStatus).toBe('connected');
  });
});

// ===========================================================================
// Store reset validation — InsightsSlice
// ===========================================================================

describe('InsightsSlice — store reset between tests', () => {
  it('state set in this test does not leak (first test)', () => {
    useStore.getState().setBacklogEntries([makeBacklogEntry()]);
    useStore.getState().setLessonEntries([makeLessonEntry(), makeGotchaEntry()]);
    useStore.getState().setInsightsLoading(true);

    expect(useStore.getState().backlogEntries).toHaveLength(1);
    expect(useStore.getState().lessonEntries).toHaveLength(2);
    expect(useStore.getState().insightsLoading).toBe(true);
  });

  it('state from previous test is fully reset (second test)', () => {
    expect(useStore.getState().backlogEntries).toEqual([]);
    expect(useStore.getState().lessonEntries).toEqual([]);
    expect(useStore.getState().insightsLoading).toBe(false);
  });
});
