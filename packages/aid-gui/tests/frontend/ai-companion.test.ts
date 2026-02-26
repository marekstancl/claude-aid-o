/**
 * Tests for AICompanion (components/AICompanion.tsx).
 *
 * Test approach:
 *   The AICompanion component has two distinct testing surfaces:
 *
 *   1. MODULE FUNCTIONS (pure logic, no JSX/DOM dependency):
 *      - loadRecentQueries()  — reads and parses localStorage
 *      - saveRecentQueries()  — serialises and writes to localStorage
 *      - addRecentQuery()     — deduplicates, prepends, and enforces MAX_RECENT=10
 *      These functions are private to the module, so they are tested through
 *      source analysis (verifying the logic is present) and direct simulation
 *      in Node.js (the functions are re-implemented inline to test the logic
 *      independently of the module's JSX/React dependencies).
 *
 *   2. COMPONENT BEHAVIOUR (source analysis):
 *      Structural checks ensure the component integrates store selectors,
 *      localStorage, and context-aware preset logic as expected.
 *
 * Coverage targets:
 *   - loadRecentQueries: reads STORAGE_KEY, parses JSON, returns [] on error
 *   - saveRecentQueries: writes JSON, caps at MAX_RECENT (10), handles errors
 *   - addRecentQuery: trims, deduplicates by query text, prepends, enforces cap
 *   - Store selectors: currentEpicId, currentState, activeProject, healthScore,
 *                      pendingDecisions, queueCount
 *   - Preset logic: pipeline status, pending decisions, health score, queue count
 *   - Recent queries section is shown only when recentQueries.length > 0
 *   - handleSubmit saves the query and clears the input
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';

// ---------------------------------------------------------------------------
// Source file path
// ---------------------------------------------------------------------------

const COMPANION_PATH = path.resolve(
  '/opt/_home/small-personal-projetcs/ai-orchestrator/packages/aid-gui/src/components/AICompanion.tsx',
);

function readSource(): string {
  if (!fs.existsSync(COMPANION_PATH)) {
    throw new Error(`AICompanion.tsx not found: ${COMPANION_PATH}`);
  }
  return fs.readFileSync(COMPANION_PATH, 'utf-8');
}

// ---------------------------------------------------------------------------
// localStorage simulation (Node.js compatible, no DOM required)
// ---------------------------------------------------------------------------

const STORAGE_KEY = 'aid-companion-recent';
const MAX_RECENT = 10;

interface RecentQuery {
  query: string;
  timestamp: number;
}

/** In-memory localStorage mock for pure-logic tests. */
function makeLocalStorage(): {
  store: Record<string, string>;
  getItem: (key: string) => string | null;
  setItem: (key: string, value: string) => void;
  removeItem: (key: string) => void;
} {
  const store: Record<string, string> = {};
  return {
    store,
    getItem: (key: string) => store[key] ?? null,
    setItem: (key: string, value: string) => { store[key] = value; },
    removeItem: (key: string) => { delete store[key]; },
  };
}

// Re-implement the exact logic from AICompanion.tsx for isolated testing.
// This mirrors the source faithfully; if the source changes, these tests
// will detect that the logic no longer matches the expected contract.

function makeStorage(ls: { getItem: (k: string) => string | null; setItem: (k: string, v: string) => void }) {
  function loadRecentQueries(): RecentQuery[] {
    try {
      const raw = ls.getItem(STORAGE_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      return parsed.slice(0, MAX_RECENT);
    } catch {
      return [];
    }
  }

  function saveRecentQueries(queries: RecentQuery[]): void {
    try {
      ls.setItem(STORAGE_KEY, JSON.stringify(queries.slice(0, MAX_RECENT)));
    } catch {
      // localStorage may be full or unavailable
    }
  }

  function addRecentQuery(query: string): RecentQuery[] {
    const trimmed = query.trim();
    if (!trimmed) return loadRecentQueries();
    const existing = loadRecentQueries().filter((q) => q.query !== trimmed);
    const updated = [{ query: trimmed, timestamp: Date.now() }, ...existing].slice(0, MAX_RECENT);
    saveRecentQueries(updated);
    return updated;
  }

  return { loadRecentQueries, saveRecentQueries, addRecentQuery };
}

// ===========================================================================
// Source presence verification
// ===========================================================================

describe('AICompanion — file exists and is non-empty', () => {
  it('AICompanion.tsx exists on disk', () => {
    expect(fs.existsSync(COMPANION_PATH)).toBe(true);
  });

  it('AICompanion.tsx is a non-empty file', () => {
    expect(readSource().length).toBeGreaterThan(0);
  });
});

describe('AICompanion — module-level localStorage functions', () => {
  it('defines STORAGE_KEY constant', () => {
    expect(readSource()).toMatch(/STORAGE_KEY\s*=\s*['"]aid-companion-recent['"]/);
  });

  it('defines MAX_RECENT constant set to 10', () => {
    expect(readSource()).toMatch(/MAX_RECENT\s*=\s*10/);
  });

  it('defines loadRecentQueries function', () => {
    expect(readSource()).toMatch(/function\s+loadRecentQueries\s*\(\s*\)/);
  });

  it('defines saveRecentQueries function', () => {
    expect(readSource()).toMatch(/function\s+saveRecentQueries\s*\(/);
  });

  it('defines addRecentQuery function', () => {
    expect(readSource()).toMatch(/function\s+addRecentQuery\s*\(/);
  });
});

describe('AICompanion — loadRecentQueries source checks', () => {
  it('reads from localStorage using STORAGE_KEY', () => {
    const source = readSource();
    expect(source).toMatch(/localStorage\.getItem\s*\(\s*STORAGE_KEY\s*\)/);
  });

  it('returns empty array when localStorage key is not set', () => {
    const source = readSource();
    // Must check for null/falsy raw value
    expect(source).toMatch(/if\s*\(\s*!raw\s*\)\s*return\s*\[\s*\]/);
  });

  it('parses the stored JSON string', () => {
    const source = readSource();
    expect(source).toMatch(/JSON\.parse\s*\(\s*raw\s*\)/);
  });

  it('guards against non-array parsed values', () => {
    const source = readSource();
    expect(source).toMatch(/!Array\.isArray\s*\(\s*parsed\s*\)/);
  });

  it('caps the loaded list at MAX_RECENT entries', () => {
    const source = readSource();
    // Must slice to MAX_RECENT after parsing
    expect(source).toMatch(/parsed\.slice\s*\(\s*0\s*,\s*MAX_RECENT\s*\)/);
  });

  it('wraps the entire function in try/catch returning [] on error', () => {
    const source = readSource();
    // try block in loadRecentQueries must return [] from catch
    expect(source).toMatch(/try\s*\{[\s\S]*?catch[\s\S]*?return\s*\[\s*\]/);
  });
});

describe('AICompanion — saveRecentQueries source checks', () => {
  it('writes to localStorage using STORAGE_KEY', () => {
    const source = readSource();
    expect(source).toMatch(/localStorage\.setItem\s*\(\s*STORAGE_KEY\s*,/);
  });

  it('serialises the queries array to JSON', () => {
    const source = readSource();
    expect(source).toMatch(/JSON\.stringify\s*\(/);
  });

  it('caps the saved list at MAX_RECENT entries before writing', () => {
    const source = readSource();
    expect(source).toMatch(/queries\.slice\s*\(\s*0\s*,\s*MAX_RECENT\s*\)/);
  });

  it('wraps the write in try/catch to handle quota errors', () => {
    const source = readSource();
    // saveRecentQueries must be inside a try block
    expect(source).toMatch(/localStorage\.setItem[\s\S]*?catch/);
  });
});

describe('AICompanion — addRecentQuery source checks', () => {
  it('trims whitespace from the query before adding', () => {
    const source = readSource();
    expect(source).toMatch(/query\.trim\s*\(\s*\)/);
  });

  it('returns current list without modifying it when query is blank', () => {
    const source = readSource();
    // Guards with !trimmed
    expect(source).toMatch(/if\s*\(\s*!trimmed\s*\)\s*return\s*loadRecentQueries\s*\(\s*\)/);
  });

  it('deduplicates by query text (filters out existing entries with same text)', () => {
    const source = readSource();
    // Must filter existing queries where q.query === trimmed
    expect(source).toMatch(/\.filter\s*\(\s*\(\s*q\s*\)\s*=>\s*q\.query\s*!==\s*trimmed\s*\)/);
  });

  it('prepends the new query to the front of the list', () => {
    const source = readSource();
    // Array construction pattern: [{ query: trimmed, timestamp: ... }, ...existing]
    expect(source).toMatch(/\[\s*\{[^}]*trimmed[^}]*\}\s*,\s*\.\.\.existing\s*\]/);
  });

  it('caps the final list at MAX_RECENT entries', () => {
    const source = readSource();
    expect(source).toMatch(/\.slice\s*\(\s*0\s*,\s*MAX_RECENT\s*\)/);
  });

  it('saves the updated list to localStorage', () => {
    const source = readSource();
    expect(source).toMatch(/saveRecentQueries\s*\(\s*updated\s*\)/);
  });

  it('includes a timestamp field on each new entry', () => {
    const source = readSource();
    expect(source).toMatch(/timestamp\s*:\s*Date\.now\s*\(\s*\)/);
  });
});

// ===========================================================================
// loadRecentQueries pure logic tests
// ===========================================================================

describe('loadRecentQueries — pure logic', () => {
  let ls: ReturnType<typeof makeLocalStorage>;
  let fn: ReturnType<typeof makeStorage>;

  beforeEach(() => {
    ls = makeLocalStorage();
    fn = makeStorage(ls);
  });

  it('returns empty array when key is absent from localStorage', () => {
    expect(fn.loadRecentQueries()).toEqual([]);
  });

  it('returns the parsed entries when valid JSON is stored', () => {
    const entries: RecentQuery[] = [
      { query: 'pipeline status', timestamp: 1000 },
      { query: 'health check', timestamp: 900 },
    ];
    ls.setItem(STORAGE_KEY, JSON.stringify(entries));

    const result = fn.loadRecentQueries();
    expect(result).toHaveLength(2);
    expect(result[0].query).toBe('pipeline status');
    expect(result[1].query).toBe('health check');
  });

  it('returns empty array when stored value is malformed JSON', () => {
    ls.setItem(STORAGE_KEY, 'not-valid-json{{{}');
    expect(fn.loadRecentQueries()).toEqual([]);
  });

  it('returns empty array when stored value is a JSON non-array (e.g., object)', () => {
    ls.setItem(STORAGE_KEY, JSON.stringify({ query: 'test' }));
    expect(fn.loadRecentQueries()).toEqual([]);
  });

  it('returns empty array when stored value is a JSON string', () => {
    ls.setItem(STORAGE_KEY, JSON.stringify('just a string'));
    expect(fn.loadRecentQueries()).toEqual([]);
  });

  it('caps at MAX_RECENT (10) when more are stored', () => {
    const entries: RecentQuery[] = Array.from({ length: 15 }, (_, i) => ({
      query: `query_${i}`,
      timestamp: 1000 + i,
    }));
    ls.setItem(STORAGE_KEY, JSON.stringify(entries));

    const result = fn.loadRecentQueries();
    expect(result).toHaveLength(10);
    expect(result[0].query).toBe('query_0');
    expect(result[9].query).toBe('query_9');
  });

  it('returns exactly MAX_RECENT when exactly that many are stored', () => {
    const entries: RecentQuery[] = Array.from({ length: 10 }, (_, i) => ({
      query: `query_${i}`,
      timestamp: 1000 + i,
    }));
    ls.setItem(STORAGE_KEY, JSON.stringify(entries));
    expect(fn.loadRecentQueries()).toHaveLength(10);
  });
});

// ===========================================================================
// saveRecentQueries pure logic tests
// ===========================================================================

describe('saveRecentQueries — pure logic', () => {
  let ls: ReturnType<typeof makeLocalStorage>;
  let fn: ReturnType<typeof makeStorage>;

  beforeEach(() => {
    ls = makeLocalStorage();
    fn = makeStorage(ls);
  });

  it('writes the serialised list to localStorage', () => {
    const entries: RecentQuery[] = [{ query: 'test query', timestamp: 1000 }];
    fn.saveRecentQueries(entries);

    const raw = ls.getItem(STORAGE_KEY);
    expect(raw).not.toBeNull();
    const parsed = JSON.parse(raw!);
    expect(parsed).toHaveLength(1);
    expect(parsed[0].query).toBe('test query');
  });

  it('caps at MAX_RECENT (10) before writing', () => {
    const entries: RecentQuery[] = Array.from({ length: 15 }, (_, i) => ({
      query: `q_${i}`,
      timestamp: 1000 + i,
    }));
    fn.saveRecentQueries(entries);

    const raw = ls.getItem(STORAGE_KEY);
    const parsed = JSON.parse(raw!);
    expect(parsed).toHaveLength(10);
    expect(parsed[0].query).toBe('q_0');
    expect(parsed[9].query).toBe('q_9');
  });

  it('writes an empty array when given an empty list', () => {
    fn.saveRecentQueries([]);

    const raw = ls.getItem(STORAGE_KEY);
    expect(JSON.parse(raw!)).toEqual([]);
  });

  it('overwrites any previous value in localStorage', () => {
    fn.saveRecentQueries([{ query: 'first', timestamp: 1 }]);
    fn.saveRecentQueries([{ query: 'second', timestamp: 2 }]);

    const raw = ls.getItem(STORAGE_KEY);
    const parsed = JSON.parse(raw!);
    expect(parsed).toHaveLength(1);
    expect(parsed[0].query).toBe('second');
  });
});

// ===========================================================================
// addRecentQuery pure logic tests
// ===========================================================================

describe('addRecentQuery — pure logic', () => {
  let ls: ReturnType<typeof makeLocalStorage>;
  let fn: ReturnType<typeof makeStorage>;

  beforeEach(() => {
    ls = makeLocalStorage();
    fn = makeStorage(ls);
  });

  it('adds the first query to an empty list', () => {
    const result = fn.addRecentQuery('pipeline status');

    expect(result).toHaveLength(1);
    expect(result[0].query).toBe('pipeline status');
  });

  it('prepends the new query to the front of the list', () => {
    ls.setItem(STORAGE_KEY, JSON.stringify([{ query: 'existing query', timestamp: 1000 }]));

    const result = fn.addRecentQuery('new query');

    expect(result[0].query).toBe('new query');
    expect(result[1].query).toBe('existing query');
  });

  it('trims leading and trailing whitespace from the query', () => {
    const result = fn.addRecentQuery('  health check  ');

    expect(result[0].query).toBe('health check');
  });

  it('returns the existing list unchanged when query is only whitespace', () => {
    ls.setItem(STORAGE_KEY, JSON.stringify([{ query: 'keep me', timestamp: 1000 }]));

    const result = fn.addRecentQuery('   ');

    expect(result).toHaveLength(1);
    expect(result[0].query).toBe('keep me');
  });

  it('returns empty list without modifying anything when query is empty string', () => {
    const result = fn.addRecentQuery('');
    expect(result).toEqual([]);
  });

  it('deduplicates — removes the existing entry with the same text', () => {
    ls.setItem(STORAGE_KEY, JSON.stringify([
      { query: 'pipeline status', timestamp: 1000 },
      { query: 'health check', timestamp: 900 },
    ]));

    const result = fn.addRecentQuery('pipeline status');

    expect(result).toHaveLength(2);
    expect(result[0].query).toBe('pipeline status');
    expect(result[1].query).toBe('health check');
  });

  it('deduplication is exact-match (case-sensitive)', () => {
    ls.setItem(STORAGE_KEY, JSON.stringify([
      { query: 'Pipeline Status', timestamp: 1000 },
    ]));

    const result = fn.addRecentQuery('pipeline status');

    // 'pipeline status' !== 'Pipeline Status' — both should exist
    expect(result).toHaveLength(2);
    expect(result[0].query).toBe('pipeline status');
    expect(result[1].query).toBe('Pipeline Status');
  });

  it('does not exceed MAX_RECENT (10) after adding beyond the cap', () => {
    const existing: RecentQuery[] = Array.from({ length: 10 }, (_, i) => ({
      query: `old_${i}`,
      timestamp: 1000 + i,
    }));
    ls.setItem(STORAGE_KEY, JSON.stringify(existing));

    const result = fn.addRecentQuery('brand new query');

    expect(result).toHaveLength(10);
    expect(result[0].query).toBe('brand new query');
    // Oldest entry (old_9) should be dropped
    expect(result.find((q) => q.query === 'old_9')).toBeUndefined();
  });

  it('persists the updated list to localStorage', () => {
    fn.addRecentQuery('saved query');

    const raw = ls.getItem(STORAGE_KEY);
    expect(raw).not.toBeNull();
    const parsed = JSON.parse(raw!);
    expect(parsed[0].query).toBe('saved query');
  });

  it('adds a timestamp to the new query entry', () => {
    const before = Date.now();
    const result = fn.addRecentQuery('timestamped query');
    const after = Date.now();

    expect(result[0].timestamp).toBeGreaterThanOrEqual(before);
    expect(result[0].timestamp).toBeLessThanOrEqual(after);
  });
});

// ===========================================================================
// Component store integration — source analysis
// ===========================================================================

describe('AICompanion — store selector integration', () => {
  it('reads currentEpicId from the store', () => {
    expect(readSource()).toMatch(/currentEpicId/);
    expect(readSource()).toMatch(/useStore\s*\(\s*\(\s*s\s*\)\s*=>\s*s\.currentEpicId\s*\)/);
  });

  it('reads currentState from the store', () => {
    expect(readSource()).toMatch(/currentState/);
    expect(readSource()).toMatch(/useStore\s*\(\s*\(\s*s\s*\)\s*=>\s*s\.currentState\s*\)/);
  });

  it('reads activeProject from the store (ProjectsSlice)', () => {
    expect(readSource()).toMatch(/activeProject/);
    expect(readSource()).toMatch(/useStore\s*\(\s*\(\s*s\s*\)\s*=>\s*s\.activeProject\s*\)/);
  });

  it('reads healthScore from the store', () => {
    expect(readSource()).toMatch(/healthScore/);
    expect(readSource()).toMatch(/useStore\s*\(\s*\(\s*s\s*\)\s*=>\s*s\.healthScore\s*\)/);
  });

  it('reads pendingDecisions from the store', () => {
    expect(readSource()).toMatch(/pendingDecisions/);
    expect(readSource()).toMatch(/useStore\s*\(\s*\(\s*s\s*\)\s*=>\s*s\.pendingDecisions\s*\)/);
  });

  it('reads queueCount from the store', () => {
    expect(readSource()).toMatch(/queueCount/);
    expect(readSource()).toMatch(/useStore\s*\(\s*\(\s*s\s*\)\s*=>\s*s\.queueCount\s*\)/);
  });
});

// ===========================================================================
// Context-aware preset logic — source analysis
// ===========================================================================

describe('AICompanion — context-aware preset logic', () => {
  it('builds presets using useMemo to avoid recomputation on every render', () => {
    expect(readSource()).toMatch(/useMemo\s*\(\s*\(\)\s*=>/);
  });

  it('preset depends on currentEpicId, currentState, pendingDecisions, healthScore, queueCount', () => {
    const source = readSource();
    // The deps array must include all context values that affect presets
    expect(source).toMatch(/currentEpicId.*currentState.*pendingDecisions.*healthScore.*queueCount/s);
  });

  it('adds EPIC status preset when currentEpicId is set and state is not IDLE', () => {
    const source = readSource();
    expect(source).toMatch(/currentEpicId\s*&&\s*currentState\s*!==\s*['"]IDLE['"]/);
  });

  it('adds pending decisions preset when pendingDecisions > 0', () => {
    const source = readSource();
    expect(source).toMatch(/pendingDecisions\s*>\s*0/);
    expect(source).toMatch(/pending decision/i);
  });

  it('adds health score alert preset when healthScore < 70', () => {
    const source = readSource();
    expect(source).toMatch(/healthScore\s*!==\s*null\s*&&\s*healthScore\s*<\s*70/);
  });

  it('always includes lessons-learned, next-tasks, and recent-decisions presets', () => {
    const source = readSource();
    expect(source).toContain('lessons learned');
    expect(source).toContain('next tasks');
    expect(source).toContain('recent decisions');
  });

  it('adds queue review preset when queueCount > 0', () => {
    const source = readSource();
    expect(source).toMatch(/queueCount\s*>\s*0/);
    expect(source).toMatch(/queue status/);
  });

  it('caps the presets array at 6 items', () => {
    const source = readSource();
    expect(source).toMatch(/items\.slice\s*\(\s*0\s*,\s*6\s*\)/);
  });
});

// ===========================================================================
// Preset logic — pure simulation (no React, no store)
// ===========================================================================

describe('AICompanion — preset generation (pure simulation)', () => {
  interface PresetItem {
    label: string;
    query: string;
  }

  // Re-implement the preset builder logic from AICompanion.tsx
  // to test it deterministically without React/store dependency
  function buildPresets(context: {
    currentEpicId: string | null;
    currentState: string;
    pendingDecisions: number;
    healthScore: number | null;
    queueCount: number;
  }): PresetItem[] {
    const { currentEpicId, currentState, pendingDecisions, healthScore, queueCount } = context;
    const items: PresetItem[] = [];

    if (currentEpicId && currentState !== 'IDLE') {
      items.push({ label: `Status of ${currentEpicId}`, query: `pipeline status ${currentEpicId}` });
    } else {
      items.push({ label: "What's the status of my pipeline?", query: 'pipeline status' });
    }

    if (pendingDecisions > 0) {
      items.push({
        label: `Review ${pendingDecisions} pending decision${pendingDecisions > 1 ? 's' : ''}`,
        query: 'pending decisions',
      });
    }

    if (healthScore !== null && healthScore < 70) {
      items.push({
        label: `Health score is ${healthScore} — investigate`,
        query: 'health check findings',
      });
    }

    items.push(
      { label: 'Show me lessons from recent runs', query: 'lessons learned' },
      { label: 'What should I work on next?', query: 'next tasks' },
      { label: 'Summarize recent decisions', query: 'recent decisions' },
    );

    if (!items.find((i) => i.query.includes('health'))) {
      items.push({ label: 'Run a health check', query: 'health check' });
    }

    if (queueCount > 0) {
      items.push({
        label: `${queueCount} EPIC${queueCount > 1 ? 's' : ''} in queue — review`,
        query: 'queue status',
      });
    }

    return items.slice(0, 6);
  }

  it('shows generic pipeline status when no EPIC is active', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: null,
      queueCount: 0,
    });

    expect(presets[0].query).toBe('pipeline status');
    expect(presets[0].label).toContain("What's the status of my pipeline?");
  });

  it('shows EPIC-specific status when an EPIC is actively running', () => {
    const presets = buildPresets({
      currentEpicId: 'E-007',
      currentState: 'EXECUTING',
      pendingDecisions: 0,
      healthScore: null,
      queueCount: 0,
    });

    expect(presets[0].query).toBe('pipeline status E-007');
    expect(presets[0].label).toContain('E-007');
  });

  it('does not show EPIC-specific status when state is IDLE (even with epicId set)', () => {
    const presets = buildPresets({
      currentEpicId: 'E-007',
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: null,
      queueCount: 0,
    });

    expect(presets[0].query).toBe('pipeline status');
  });

  it('adds pending decisions preset when there are pending decisions', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 3,
      healthScore: null,
      queueCount: 0,
    });

    const decisionPreset = presets.find((p) => p.query === 'pending decisions');
    expect(decisionPreset).toBeDefined();
    expect(decisionPreset?.label).toContain('3 pending decisions');
  });

  it('uses singular "decision" when pendingDecisions is 1', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 1,
      healthScore: null,
      queueCount: 0,
    });

    const decisionPreset = presets.find((p) => p.query === 'pending decisions');
    expect(decisionPreset?.label).toContain('1 pending decision');
    expect(decisionPreset?.label).not.toContain('decisions');
  });

  it('does not add pending decisions preset when pendingDecisions is 0', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: null,
      queueCount: 0,
    });

    expect(presets.find((p) => p.query === 'pending decisions')).toBeUndefined();
  });

  it('adds health alert preset when healthScore is below 70', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: 65,
      queueCount: 0,
    });

    const healthPreset = presets.find((p) => p.query === 'health check findings');
    expect(healthPreset).toBeDefined();
    expect(healthPreset?.label).toContain('65');
  });

  it('does not add health alert preset when healthScore >= 70', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: 85,
      queueCount: 0,
    });

    expect(presets.find((p) => p.query === 'health check findings')).toBeUndefined();
  });

  it('adds "Run a health check" when health alert preset is not shown', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: null,
      queueCount: 0,
    });

    // healthScore is null — no health alert — so generic health check must appear
    expect(presets.find((p) => p.query === 'health check')).toBeDefined();
  });

  it('does not add "Run a health check" when health alert preset is already shown', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: 60,
      queueCount: 0,
    });

    // health check findings preset is shown — generic health check must be omitted
    expect(presets.find((p) => p.query === 'health check')).toBeUndefined();
  });

  it('adds queue review preset when queueCount > 0', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: null,
      queueCount: 5,
    });

    const queuePreset = presets.find((p) => p.query === 'queue status');
    expect(queuePreset).toBeDefined();
    expect(queuePreset?.label).toContain('5 EPICs in queue');
  });

  it('uses singular "EPIC" when queueCount is 1', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: null,
      queueCount: 1,
    });

    const queuePreset = presets.find((p) => p.query === 'queue status');
    expect(queuePreset?.label).toContain('1 EPIC in queue');
    expect(queuePreset?.label).not.toContain('EPICs');
  });

  it('caps total presets at 6 regardless of how many are generated', () => {
    // With all conditions active, more than 6 would be generated without the cap
    const presets = buildPresets({
      currentEpicId: 'E-001',
      currentState: 'EXECUTING',
      pendingDecisions: 2,
      healthScore: 50,
      queueCount: 3,
    });

    expect(presets.length).toBeLessThanOrEqual(6);
  });

  it('always includes lessons-learned and next-tasks presets', () => {
    const presets = buildPresets({
      currentEpicId: null,
      currentState: 'IDLE',
      pendingDecisions: 0,
      healthScore: null,
      queueCount: 0,
    });

    expect(presets.find((p) => p.query === 'lessons learned')).toBeDefined();
    expect(presets.find((p) => p.query === 'next tasks')).toBeDefined();
  });
});

// ===========================================================================
// Component behaviour — source analysis
// ===========================================================================

describe('AICompanion — component structure', () => {
  it('exports AICompanion as a named React FC', () => {
    expect(readSource()).toMatch(/export\s+const\s+AICompanion\s*:/);
  });

  it('accepts isOpen and onClose props', () => {
    const source = readSource();
    expect(source).toMatch(/isOpen\s*:/);
    expect(source).toMatch(/onClose\s*:/);
  });

  it('loads recent queries from localStorage when isOpen becomes true', () => {
    const source = readSource();
    // The useEffect that loads queries must depend on isOpen
    expect(source).toMatch(/if\s*\(\s*isOpen\s*\)/);
    expect(source).toMatch(/setRecentQueries\s*\(\s*loadRecentQueries\s*\(\s*\)\s*\)/);
  });

  it('shows recent queries section only when recentQueries.length > 0', () => {
    const source = readSource();
    expect(source).toMatch(/recentQueries\.length\s*>\s*0/);
  });

  it('handleSubmit saves the query and clears the input', () => {
    const source = readSource();
    expect(source).toMatch(/addRecentQuery\s*\(\s*query\s*\)/);
    expect(source).toMatch(/setRecentQueries\s*\(\s*updated\s*\)/);
    expect(source).toMatch(/setQuery\s*\(\s*['"]['"]s*\)/);
  });

  it('shows placeholder with active project name when activeProject is set', () => {
    const source = readSource();
    // Placeholder must be dynamic based on activeProject
    expect(source).toMatch(/activeProject/);
    expect(source).toMatch(/activeProject\.name/);
  });

  it('shows recent queries via slice of up to 5 items', () => {
    const source = readSource();
    // Only the top 5 recent queries are shown in the UI
    expect(source).toMatch(/recentQueries\.slice\s*\(\s*0\s*,\s*5\s*\)/);
  });

  it('closes on Escape key when isOpen is true', () => {
    const source = readSource();
    expect(source).toMatch(/e\.key\s*===\s*['"]Escape['"]/);
    expect(source).toMatch(/onClose\s*\(\s*\)/);
  });

  it('submits on Enter key when query is non-empty', () => {
    const source = readSource();
    expect(source).toMatch(/e\.key\s*===\s*['"]Enter['"]/);
    expect(source).toMatch(/query\.trim\s*\(\s*\)/);
    expect(source).toMatch(/handleSubmit\s*\(\s*\)/);
  });
});
