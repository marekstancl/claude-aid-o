/**
 * Static source verification tests for the 6 API-integrated screens.
 *
 * These tests read the screen source files directly and apply regex checks
 * to verify:
 *
 *   1. No hardcoded mock data arrays remain — patterns like
 *      `const xxx = [{ id: ...` or `const xxx = [{ epicId: ...` with
 *      inline objects are banned.
 *
 *   2. Each screen imports `createApiClient` or uses `useStore` — at least
 *      one of the real integration patterns must be present.
 *
 *   3. Each screen calls API methods (on a `client.` object) or store
 *      setters (matching `set[A-Z]` calls) — the screen must actively
 *      use the integration.
 *
 * Rationale: After migrating from hardcoded data to live API integration,
 * these checks act as a regression guard — if a developer accidentally
 * re-introduces a mock data constant, this test will fail immediately.
 *
 * Note: These tests check structure and intent, not runtime behavior.
 * They complement the store and API client unit tests, not replace them.
 */

import { describe, it, expect } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';

// ---------------------------------------------------------------------------
// Resolve screen paths relative to the project root
// ---------------------------------------------------------------------------

const SCREENS_DIR = path.resolve(
  '/opt/_home/small-personal-projetcs/ai-orchestrator/packages/aid-gui/src/screens',
);

const SCREEN_FILES: Record<string, string> = {
  DecisionHub: path.join(SCREENS_DIR, 'DecisionHub.tsx'),
  EvidenceVault: path.join(SCREENS_DIR, 'EvidenceVault.tsx'),
  HealthObservatory: path.join(SCREENS_DIR, 'HealthObservatory.tsx'),
  IdeasToExecution: path.join(SCREENS_DIR, 'IdeasToExecution.tsx'),
  QueueScheduler: path.join(SCREENS_DIR, 'QueueScheduler.tsx'),
  KnowledgeBase: path.join(SCREENS_DIR, 'KnowledgeBase.tsx'),
};

/** Read a screen file and return its content. Throws if the file does not exist. */
function readScreen(screenName: string): string {
  const filePath = SCREEN_FILES[screenName];
  if (!fs.existsSync(filePath)) {
    throw new Error(`Screen file not found: ${filePath}`);
  }
  return fs.readFileSync(filePath, 'utf-8');
}

// ---------------------------------------------------------------------------
// Pattern definitions
// ---------------------------------------------------------------------------

/**
 * Matches hardcoded mock array declarations that contain realistic API data,
 * specifically looking for:
 *
 *   const xxx = [{ epicId: '...', ...    — mock queue/decision entries
 *   const xxx = [{ timestamp: '...', ... — mock log entries or decisions
 *   const xxx = [{ decision: '...', ...  — mock decision records
 *   const xxx = [{ findings: ...         — mock audit findings
 *   const xxx = [{ scores: ...           — mock audit scores
 *
 * This deliberately avoids flagging legitimate UI configuration arrays like:
 *   const COLUMNS = [{ id: 'idea', title: 'Ideas' }]    — short UI labels
 *   const PRIORITY_ORDER = ['critical', 'high', ...]    — ordering constants
 *   const filterButtons = [{ label: 'All', value: 'all' }] — filter config
 *
 * The pattern requires keys that are specific to API response shapes and
 * not common UI configuration keys (id alone is too generic — it is used
 * in both UI config arrays and data arrays).
 */
const HARDCODED_DATA_ARRAY_PATTERN =
  /const\s+\w+\s*(?::\s*[\w<[\]|, ]+)?\s*=\s*\[\s*\{\s*(?:epicId|runId|timestamp|decision|findings|scores)\s*:/;

/**
 * Matches import of createApiClient from the api client module.
 */
const IMPORTS_CREATE_API_CLIENT = /import\s+.*createApiClient.*from\s+['"]\.\.\/api\/client['"]/;

/**
 * Matches usage of the Zustand store via useStore hook.
 */
const USES_STORE = /useStore\s*\(/;

/**
 * Matches API client method calls — any `client.` followed by a method name.
 */
const CALLS_API_METHOD = /\bclient\.\w+\s*\(/;

/**
 * Matches store setter calls — any `set[A-Z]...` function call.
 * Covers: setPendingDecisionsList, setDecisionHistory, setEvidenceEpics,
 *         setAuditReports, setIdeas, setQueueEntries, setKnowledgeItems, etc.
 */
const CALLS_STORE_SETTER = /\bset[A-Z]\w+\s*\(/;

// ---------------------------------------------------------------------------
// Helper to run all checks against a single screen
// ---------------------------------------------------------------------------

interface ScreenCheckResult {
  name: string;
  source: string;
  hasHardcodedMockData: boolean;
  importsCreateApiClient: boolean;
  usesStore: boolean;
  callsApiMethod: boolean;
  callsStoreSetter: boolean;
}

function checkScreen(screenName: string): ScreenCheckResult {
  const source = readScreen(screenName);
  return {
    name: screenName,
    source,
    hasHardcodedMockData: HARDCODED_DATA_ARRAY_PATTERN.test(source),
    importsCreateApiClient: IMPORTS_CREATE_API_CLIENT.test(source),
    usesStore: USES_STORE.test(source),
    callsApiMethod: CALLS_API_METHOD.test(source),
    callsStoreSetter: CALLS_STORE_SETTER.test(source),
  };
}

// ---------------------------------------------------------------------------
// Tests — per-screen verification
// ---------------------------------------------------------------------------

describe('Screen source verification — no hardcoded mock data', () => {
  for (const screenName of Object.keys(SCREEN_FILES)) {
    it(`${screenName} does not contain hardcoded mock data arrays`, () => {
      const result = checkScreen(screenName);
      expect(
        result.hasHardcodedMockData,
        `${screenName} appears to contain a hardcoded mock data array. ` +
          'All data must come from the API or store.',
      ).toBe(false);
    });
  }
});

describe('Screen source verification — imports createApiClient or useStore', () => {
  for (const screenName of Object.keys(SCREEN_FILES)) {
    it(`${screenName} imports createApiClient or uses useStore`, () => {
      const result = checkScreen(screenName);
      const hasIntegration = result.importsCreateApiClient || result.usesStore;
      expect(
        hasIntegration,
        `${screenName} does not import createApiClient or use useStore. ` +
          'Every screen must integrate with either the API client or the store.',
      ).toBe(true);
    });
  }
});

describe('Screen source verification — calls API methods or store setters', () => {
  for (const screenName of Object.keys(SCREEN_FILES)) {
    it(`${screenName} calls API client methods or store setter actions`, () => {
      const result = checkScreen(screenName);
      const hasDataIntegration = result.callsApiMethod || result.callsStoreSetter;
      expect(
        hasDataIntegration,
        `${screenName} does not appear to call any API client methods (client.*()) ` +
          'or store setter actions (set*(...)). ' +
          'The screen must actively fetch or write data.',
      ).toBe(true);
    });
  }
});

// ---------------------------------------------------------------------------
// Comprehensive combined check — all screens pass all checks
// ---------------------------------------------------------------------------

describe('Screen source verification — all 6 screens pass combined checks', () => {
  it('all 6 screens are present on disk', () => {
    for (const [screenName, filePath] of Object.entries(SCREEN_FILES)) {
      expect(
        fs.existsSync(filePath),
        `Screen file missing: ${screenName} at ${filePath}`,
      ).toBe(true);
    }
  });

  it('all 6 screens are non-empty files', () => {
    for (const screenName of Object.keys(SCREEN_FILES)) {
      const source = readScreen(screenName);
      expect(
        source.length,
        `${screenName} source file is empty`,
      ).toBeGreaterThan(0);
    }
  });

  it('no screen contains a hardcoded data array (batch check)', () => {
    const violators: string[] = [];
    for (const screenName of Object.keys(SCREEN_FILES)) {
      const result = checkScreen(screenName);
      if (result.hasHardcodedMockData) {
        violators.push(screenName);
      }
    }
    expect(
      violators,
      `These screens still contain hardcoded mock data: ${violators.join(', ')}`,
    ).toEqual([]);
  });

  it('all 6 screens import createApiClient (primary API integration pattern)', () => {
    const missing: string[] = [];
    for (const screenName of Object.keys(SCREEN_FILES)) {
      const result = checkScreen(screenName);
      if (!result.importsCreateApiClient) {
        missing.push(screenName);
      }
    }
    expect(
      missing,
      `These screens do not import createApiClient: ${missing.join(', ')}`,
    ).toEqual([]);
  });

  it('all 6 screens use useStore for state management', () => {
    const missing: string[] = [];
    for (const screenName of Object.keys(SCREEN_FILES)) {
      const result = checkScreen(screenName);
      if (!result.usesStore) {
        missing.push(screenName);
      }
    }
    expect(
      missing,
      `These screens do not use useStore: ${missing.join(', ')}`,
    ).toEqual([]);
  });

  it('all 6 screens both import createApiClient AND use useStore (full integration)', () => {
    const missing: string[] = [];
    for (const screenName of Object.keys(SCREEN_FILES)) {
      const result = checkScreen(screenName);
      if (!result.importsCreateApiClient || !result.usesStore) {
        missing.push(
          `${screenName} (api=${result.importsCreateApiClient}, store=${result.usesStore})`,
        );
      }
    }
    expect(
      missing,
      `These screens are missing full API+store integration: ${missing.join('; ')}`,
    ).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Screen-specific content checks
// ---------------------------------------------------------------------------

describe('DecisionHub — specific integration checks', () => {
  it('calls getDecisionsPending for pending decisions data', () => {
    const source = readScreen('DecisionHub');
    expect(source).toMatch(/client\.getDecisionsPending\s*\(/);
  });

  it('calls postDecision for approve/reject actions', () => {
    const source = readScreen('DecisionHub');
    expect(source).toMatch(/client\.postDecision\s*\(/);
  });

  it('calls getDecisions for decision history', () => {
    const source = readScreen('DecisionHub');
    expect(source).toMatch(/client\.getDecisions\s*\(/);
  });

  it('uses removePendingDecision for optimistic update', () => {
    const source = readScreen('DecisionHub');
    expect(source).toMatch(/removePendingDecision\s*\(/);
  });

  it('uses addDecisionToHistory for optimistic update', () => {
    const source = readScreen('DecisionHub');
    expect(source).toMatch(/addDecisionToHistory\s*\(/);
  });
});

describe('EvidenceVault — specific integration checks', () => {
  it('calls getEvidence to populate the evidence tree', () => {
    const source = readScreen('EvidenceVault');
    expect(source).toMatch(/client\.getEvidence\s*\(/);
  });

  it('calls getEvidenceFile when a file is selected', () => {
    const source = readScreen('EvidenceVault');
    expect(source).toMatch(/client\.getEvidenceFile\s*\(/);
  });

  it('uses setEvidenceEpics to store the evidence tree', () => {
    const source = readScreen('EvidenceVault');
    expect(source).toMatch(/setEvidenceEpics\s*\(/);
  });

  it('uses setEvidenceFileContent to store file content', () => {
    const source = readScreen('EvidenceVault');
    expect(source).toMatch(/setEvidenceFileContent\s*\(/);
  });
});

describe('HealthObservatory — specific integration checks', () => {
  it('calls getAuditHealth to load audit data', () => {
    const source = readScreen('HealthObservatory');
    expect(source).toMatch(/client\.getAuditHealth\s*\(/);
  });

  it('uses setAuditReports to store audit data in the store', () => {
    const source = readScreen('HealthObservatory');
    expect(source).toMatch(/setAuditReports\s*\(/);
  });

  it('reads latestAudit from the store for display', () => {
    const source = readScreen('HealthObservatory');
    expect(source).toMatch(/latestAudit/);
  });
});

describe('IdeasToExecution — specific integration checks', () => {
  it('calls getIdeas to load the Kanban board data', () => {
    const source = readScreen('IdeasToExecution');
    expect(source).toMatch(/client\.getIdeas\s*\(/);
  });

  it('calls createIdea for Quick Capture', () => {
    const source = readScreen('IdeasToExecution');
    expect(source).toMatch(/client\.createIdea\s*\(/);
  });

  it('calls updateIdea for drag-to-reorder status change', () => {
    const source = readScreen('IdeasToExecution');
    expect(source).toMatch(/client\.updateIdea\s*\(/);
  });

  it('calls deleteIdea for removing ideas', () => {
    const source = readScreen('IdeasToExecution');
    expect(source).toMatch(/client\.deleteIdea\s*\(/);
  });

  it('uses addIdea from the store', () => {
    const source = readScreen('IdeasToExecution');
    expect(source).toMatch(/\baddIdea\s*\(/);
  });

  it('uses removeIdea from the store', () => {
    const source = readScreen('IdeasToExecution');
    expect(source).toMatch(/\bremoveIdea\s*\(/);
  });
});

describe('QueueScheduler — specific integration checks', () => {
  it('calls getQueue to load queue entries', () => {
    const source = readScreen('QueueScheduler');
    expect(source).toMatch(/client\.getQueue\s*\(/);
  });

  it('calls getQueueSchedule to load schedule config', () => {
    const source = readScreen('QueueScheduler');
    expect(source).toMatch(/client\.getQueueSchedule\s*\(/);
  });

  it('calls getUsage to load CC usage data', () => {
    const source = readScreen('QueueScheduler');
    expect(source).toMatch(/client\.getUsage\s*\(/);
  });

  it('calls updateQueueEntry for drag-to-reorder persistence', () => {
    const source = readScreen('QueueScheduler');
    expect(source).toMatch(/client\.updateQueueEntry\s*\(/);
  });

  it('calls updateQueueSchedule for settings changes', () => {
    const source = readScreen('QueueScheduler');
    expect(source).toMatch(/client\.updateQueueSchedule\s*\(/);
  });

  it('uses reorderQueueEntry from the store for optimistic update', () => {
    const source = readScreen('QueueScheduler');
    expect(source).toMatch(/reorderQueueEntry\s*\(/);
  });
});

describe('KnowledgeBase — specific integration checks', () => {
  it('calls getKnowledge to load knowledge items', () => {
    const source = readScreen('KnowledgeBase');
    expect(source).toMatch(/client\.getKnowledge\s*\(/);
  });

  it('uses setKnowledgeItems to store the knowledge data', () => {
    const source = readScreen('KnowledgeBase');
    expect(source).toMatch(/setKnowledgeItems\s*\(/);
  });

  it('reads knowledgeItems from the store for display', () => {
    const source = readScreen('KnowledgeBase');
    expect(source).toMatch(/knowledgeItems/);
  });
});
