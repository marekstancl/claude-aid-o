/**
 * Unit tests for the 6 new Zustand store slices added for the API-integrated screens.
 *
 * Covered slices:
 *   DecisionsSlice    — pending decisions list, decision history, optimistic updates
 *   EvidenceSlice     — evidence tree, selection, file content
 *   AuditSlice        — audit reports, latestAudit derivation, healthScore cross-slice update
 *   IdeasSlice        — CRUD operations for ideas (Kanban)
 *   QueueDetailSlice  — queue entries, schedule config, status, usage data, reorder
 *   KnowledgeSlice    — knowledge items list
 *
 * All tests reset the store to its initial state before running, preventing
 * state leaks from the singleton Zustand store across tests.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { useStore } from '../../src/store.ts';
import type {
  PendingDecisionEntry,
  DecisionEntry,
  EvidenceEpicEntry,
  EvidenceFileResponse,
  AuditReportResponse,
  StoredIdea,
  QueueScheduleEntry,
  ScheduleConfig,
  ScheduleStatusResponse,
  UsageResponse,
  KnowledgeItem,
} from '../../src/types/api.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function resetStore(): void {
  useStore.setState(useStore.getInitialState());
}

function makePendingDecision(overrides: Partial<PendingDecisionEntry> = {}): PendingDecisionEntry {
  return {
    epicId: 'E-001',
    runId: 'run-001',
    state: 'PLAN_REVIEW',
    evidencePath: '/path/to/evidence',
    ...overrides,
  };
}

function makeDecisionEntry(overrides: Partial<DecisionEntry> = {}): DecisionEntry {
  return {
    timestamp: '2026-02-25T10:00:00.000Z',
    type: 'plan_approval',
    epicId: 'E-001',
    runId: 'run-001',
    decision: 'approved',
    channel: 'gui',
    ...overrides,
  };
}

function makeEvidenceEpic(overrides: Partial<EvidenceEpicEntry> = {}): EvidenceEpicEntry {
  return {
    epicId: 'E-001',
    runs: [
      {
        runId: 'run-001',
        files: ['plan.json', 'stage_log.jsonl'],
        hasStageLog: true,
        hasPlan: true,
        hasGatesReport: false,
      },
    ],
    ...overrides,
  };
}

function makeAuditReport(overrides: Partial<AuditReportResponse> = {}): AuditReportResponse {
  return {
    epicId: 'E-001',
    timestamp: '2026-02-25T07:00:00.000Z',
    auditor: 'auditor-agent',
    scores: {
      overall: 88,
      codeQuality: 90,
      security: 85,
      documentation: 80,
      process: 95,
      frontend: null,
      database: null,
    },
    findings: [],
    ...overrides,
  };
}

function makeStoredIdea(overrides: Partial<StoredIdea> = {}): StoredIdea {
  return {
    id: 'I-001',
    title: 'Implement dark mode',
    description: 'Add a dark mode toggle to the dashboard',
    tags: ['ui', 'accessibility'],
    priority: 'medium',
    status: 'idea',
    autoStatus: null,
    linkedPlan: null,
    linkedEpic: null,
    createdAt: '2026-02-25T09:00:00.000Z',
    updatedAt: '2026-02-25T09:00:00.000Z',
    ...overrides,
  };
}

function makeQueueEntry(overrides: Partial<QueueScheduleEntry> = {}): QueueScheduleEntry {
  return {
    epicId: 'E-001',
    path: '.aid-o/02-epics/E-001.md',
    priority: 'high',
    status: 'queued',
    addedAt: '2026-02-25T08:00:00.000Z',
    startedAt: null,
    completedAt: null,
    ...overrides,
  };
}

function makeScheduleConfig(overrides: Partial<ScheduleConfig> = {}): ScheduleConfig {
  return {
    enabled: true,
    cooldownSeconds: 1800,
    maxConcurrent: 1,
    delayedStartAt: null,
    autoPauseAtCcLimit: true,
    ccLimitThreshold: 100000,
    lastRunCompletedAt: null,
    ...overrides,
  };
}

function makeScheduleStatus(overrides: Partial<ScheduleStatusResponse> = {}): ScheduleStatusResponse {
  return {
    state: 'idle',
    remainingSeconds: null,
    config: makeScheduleConfig(),
    timestamp: '2026-02-25T10:00:00.000Z',
    ...overrides,
  };
}

function makeUsageData(overrides: Partial<UsageResponse> = {}): UsageResponse {
  return {
    totalEvents: 150,
    agentDispatches: 42,
    gateEvaluations: 12,
    escalations: 2,
    perEpic: [],
    ...overrides,
  };
}

function makeKnowledgeItem(overrides: Partial<KnowledgeItem> = {}): KnowledgeItem {
  return {
    type: 'agent',
    name: 'architect',
    description: 'Designs system architecture',
    filename: 'architect.md',
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
// DecisionsSlice
// ===========================================================================

describe('DecisionsSlice — initial state', () => {
  it('starts with an empty pendingDecisionsList', () => {
    expect(useStore.getState().pendingDecisionsList).toEqual([]);
  });

  it('starts with an empty decisionHistory', () => {
    expect(useStore.getState().decisionHistory).toEqual([]);
  });

  it('starts with decisionsLoading false', () => {
    expect(useStore.getState().decisionsLoading).toBe(false);
  });
});

describe('DecisionsSlice — setPendingDecisionsList', () => {
  it('replaces the pending decisions list', () => {
    const decisions = [
      makePendingDecision({ epicId: 'E-001', runId: 'run-001' }),
      makePendingDecision({ epicId: 'E-002', runId: 'run-002' }),
    ];
    useStore.getState().setPendingDecisionsList(decisions);

    const { pendingDecisionsList } = useStore.getState();
    expect(pendingDecisionsList).toHaveLength(2);
    expect(pendingDecisionsList[0].epicId).toBe('E-001');
    expect(pendingDecisionsList[1].epicId).toBe('E-002');
  });

  it('accepts an empty array to clear all pending decisions', () => {
    useStore.getState().setPendingDecisionsList([makePendingDecision()]);
    useStore.getState().setPendingDecisionsList([]);
    expect(useStore.getState().pendingDecisionsList).toEqual([]);
  });

  it('replaces the previous list entirely on successive calls', () => {
    useStore.getState().setPendingDecisionsList([makePendingDecision({ epicId: 'E-001' })]);
    useStore.getState().setPendingDecisionsList([makePendingDecision({ epicId: 'E-002' })]);

    const { pendingDecisionsList } = useStore.getState();
    expect(pendingDecisionsList).toHaveLength(1);
    expect(pendingDecisionsList[0].epicId).toBe('E-002');
  });
});

describe('DecisionsSlice — setDecisionHistory', () => {
  it('replaces the decision history list', () => {
    const history = [
      makeDecisionEntry({ epicId: 'E-001', decision: 'approved' }),
      makeDecisionEntry({ epicId: 'E-002', decision: 'rejected' }),
    ];
    useStore.getState().setDecisionHistory(history);

    const { decisionHistory } = useStore.getState();
    expect(decisionHistory).toHaveLength(2);
    expect(decisionHistory[0].decision).toBe('approved');
    expect(decisionHistory[1].decision).toBe('rejected');
  });

  it('accepts an empty array to clear the history', () => {
    useStore.getState().setDecisionHistory([makeDecisionEntry()]);
    useStore.getState().setDecisionHistory([]);
    expect(useStore.getState().decisionHistory).toEqual([]);
  });
});

describe('DecisionsSlice — addDecisionToHistory', () => {
  it('prepends a decision to an empty history', () => {
    const decision = makeDecisionEntry({ epicId: 'E-001' });
    useStore.getState().addDecisionToHistory(decision);

    expect(useStore.getState().decisionHistory).toHaveLength(1);
    expect(useStore.getState().decisionHistory[0].epicId).toBe('E-001');
  });

  it('prepends to the front of existing history (newest first)', () => {
    useStore.getState().setDecisionHistory([makeDecisionEntry({ epicId: 'E-001' })]);
    useStore.getState().addDecisionToHistory(makeDecisionEntry({ epicId: 'E-002' }));

    const { decisionHistory } = useStore.getState();
    expect(decisionHistory).toHaveLength(2);
    expect(decisionHistory[0].epicId).toBe('E-002');
    expect(decisionHistory[1].epicId).toBe('E-001');
  });

  it('preserves all existing history entries after prepend', () => {
    const existing = [
      makeDecisionEntry({ epicId: 'E-001' }),
      makeDecisionEntry({ epicId: 'E-002' }),
    ];
    useStore.getState().setDecisionHistory(existing);
    useStore.getState().addDecisionToHistory(makeDecisionEntry({ epicId: 'E-003' }));

    expect(useStore.getState().decisionHistory).toHaveLength(3);
    expect(useStore.getState().decisionHistory[0].epicId).toBe('E-003');
    expect(useStore.getState().decisionHistory[2].epicId).toBe('E-002');
  });
});

describe('DecisionsSlice — removePendingDecision', () => {
  it('removes the matching pending decision by epicId and runId', () => {
    const decisions = [
      makePendingDecision({ epicId: 'E-001', runId: 'run-001' }),
      makePendingDecision({ epicId: 'E-002', runId: 'run-002' }),
    ];
    useStore.getState().setPendingDecisionsList(decisions);
    useStore.getState().removePendingDecision('E-001', 'run-001');

    const { pendingDecisionsList } = useStore.getState();
    expect(pendingDecisionsList).toHaveLength(1);
    expect(pendingDecisionsList[0].epicId).toBe('E-002');
  });

  it('does nothing when the epicId/runId pair does not exist', () => {
    const decisions = [makePendingDecision({ epicId: 'E-001', runId: 'run-001' })];
    useStore.getState().setPendingDecisionsList(decisions);
    useStore.getState().removePendingDecision('NONEXISTENT', 'run-999');

    expect(useStore.getState().pendingDecisionsList).toHaveLength(1);
  });

  it('only removes entries where both epicId AND runId match (not partial match)', () => {
    const decisions = [
      makePendingDecision({ epicId: 'E-001', runId: 'run-001' }),
      makePendingDecision({ epicId: 'E-001', runId: 'run-002' }),
    ];
    useStore.getState().setPendingDecisionsList(decisions);
    useStore.getState().removePendingDecision('E-001', 'run-001');

    const { pendingDecisionsList } = useStore.getState();
    expect(pendingDecisionsList).toHaveLength(1);
    expect(pendingDecisionsList[0].runId).toBe('run-002');
  });

  it('decrements pendingDecisions count when removing an entry', () => {
    useStore.getState().setPendingDecisions(3);
    useStore.getState().setPendingDecisionsList([
      makePendingDecision({ epicId: 'E-001', runId: 'run-001' }),
    ]);
    useStore.getState().removePendingDecision('E-001', 'run-001');

    expect(useStore.getState().pendingDecisions).toBe(2);
  });

  it('does not decrement pendingDecisions below 0', () => {
    useStore.getState().setPendingDecisions(0);
    useStore.getState().setPendingDecisionsList([makePendingDecision()]);
    useStore.getState().removePendingDecision('E-001', 'run-001');

    expect(useStore.getState().pendingDecisions).toBe(0);
  });

  it('is safe to call on an empty list', () => {
    useStore.getState().removePendingDecision('E-001', 'run-001');
    expect(useStore.getState().pendingDecisionsList).toEqual([]);
  });
});

describe('DecisionsSlice — setDecisionsLoading', () => {
  it('sets decisionsLoading to true', () => {
    useStore.getState().setDecisionsLoading(true);
    expect(useStore.getState().decisionsLoading).toBe(true);
  });

  it('sets decisionsLoading back to false', () => {
    useStore.getState().setDecisionsLoading(true);
    useStore.getState().setDecisionsLoading(false);
    expect(useStore.getState().decisionsLoading).toBe(false);
  });
});

// ===========================================================================
// EvidenceSlice
// ===========================================================================

describe('EvidenceSlice — initial state', () => {
  it('starts with empty evidenceEpics array', () => {
    expect(useStore.getState().evidenceEpics).toEqual([]);
  });

  it('starts with null selections and file content', () => {
    const { selectedEvidenceEpic, selectedEvidenceRun, selectedEvidenceFile, evidenceFileContent } =
      useStore.getState();
    expect(selectedEvidenceEpic).toBeNull();
    expect(selectedEvidenceRun).toBeNull();
    expect(selectedEvidenceFile).toBeNull();
    expect(evidenceFileContent).toBeNull();
  });

  it('starts with evidenceLoading false', () => {
    expect(useStore.getState().evidenceLoading).toBe(false);
  });
});

describe('EvidenceSlice — setEvidenceEpics', () => {
  it('replaces the evidence epics list', () => {
    const epics = [
      makeEvidenceEpic({ epicId: 'E-001' }),
      makeEvidenceEpic({ epicId: 'E-002', runs: [] }),
    ];
    useStore.getState().setEvidenceEpics(epics);

    const { evidenceEpics } = useStore.getState();
    expect(evidenceEpics).toHaveLength(2);
    expect(evidenceEpics[0].epicId).toBe('E-001');
    expect(evidenceEpics[0].runs).toHaveLength(1);
  });

  it('accepts an empty array to clear evidence epics', () => {
    useStore.getState().setEvidenceEpics([makeEvidenceEpic()]);
    useStore.getState().setEvidenceEpics([]);
    expect(useStore.getState().evidenceEpics).toEqual([]);
  });
});

describe('EvidenceSlice — setEvidenceSelection', () => {
  it('sets all three selection fields atomically', () => {
    useStore.getState().setEvidenceSelection('E-001', 'run-001', 'plan.json');

    const state = useStore.getState();
    expect(state.selectedEvidenceEpic).toBe('E-001');
    expect(state.selectedEvidenceRun).toBe('run-001');
    expect(state.selectedEvidenceFile).toBe('plan.json');
  });

  it('accepts null values to deselect', () => {
    useStore.getState().setEvidenceSelection('E-001', 'run-001', 'plan.json');
    useStore.getState().setEvidenceSelection(null, null, null);

    const state = useStore.getState();
    expect(state.selectedEvidenceEpic).toBeNull();
    expect(state.selectedEvidenceRun).toBeNull();
    expect(state.selectedEvidenceFile).toBeNull();
  });

  it('clears evidenceFileContent when file is set to null', () => {
    const fileContent: EvidenceFileResponse = {
      filePath: 'plan.json',
      format: 'json',
      content: { steps: [] },
    };
    useStore.getState().setEvidenceFileContent(fileContent);
    useStore.getState().setEvidenceSelection('E-001', 'run-001', null);

    expect(useStore.getState().evidenceFileContent).toBeNull();
  });

  it('allows selecting a run without a file', () => {
    useStore.getState().setEvidenceSelection('E-002', 'run-003', null);

    const state = useStore.getState();
    expect(state.selectedEvidenceEpic).toBe('E-002');
    expect(state.selectedEvidenceRun).toBe('run-003');
    expect(state.selectedEvidenceFile).toBeNull();
  });
});

describe('EvidenceSlice — setEvidenceFileContent', () => {
  it('stores file content', () => {
    const content: EvidenceFileResponse = {
      filePath: 'plan.json',
      format: 'json',
      content: { steps: [{ id: 'step_1' }] },
    };
    useStore.getState().setEvidenceFileContent(content);

    const { evidenceFileContent } = useStore.getState();
    expect(evidenceFileContent).not.toBeNull();
    expect(evidenceFileContent?.filePath).toBe('plan.json');
    expect(evidenceFileContent?.format).toBe('json');
  });

  it('accepts null to clear file content', () => {
    useStore.getState().setEvidenceFileContent({
      filePath: 'plan.json',
      format: 'json',
      content: {},
    });
    useStore.getState().setEvidenceFileContent(null);
    expect(useStore.getState().evidenceFileContent).toBeNull();
  });

  it('stores markdown format content as a string', () => {
    const content: EvidenceFileResponse = {
      filePath: 'README.md',
      format: 'markdown',
      content: '# Plan\n\nThis is a plan.',
    };
    useStore.getState().setEvidenceFileContent(content);

    expect(useStore.getState().evidenceFileContent?.format).toBe('markdown');
    expect(useStore.getState().evidenceFileContent?.content).toBe('# Plan\n\nThis is a plan.');
  });
});

describe('EvidenceSlice — setEvidenceLoading', () => {
  it('sets evidenceLoading to true', () => {
    useStore.getState().setEvidenceLoading(true);
    expect(useStore.getState().evidenceLoading).toBe(true);
  });

  it('sets evidenceLoading back to false', () => {
    useStore.getState().setEvidenceLoading(true);
    useStore.getState().setEvidenceLoading(false);
    expect(useStore.getState().evidenceLoading).toBe(false);
  });
});

// ===========================================================================
// AuditSlice
// ===========================================================================

describe('AuditSlice — initial state', () => {
  it('starts with empty auditReports array', () => {
    expect(useStore.getState().auditReports).toEqual([]);
  });

  it('starts with null latestAudit', () => {
    expect(useStore.getState().latestAudit).toBeNull();
  });

  it('starts with auditLoading false', () => {
    expect(useStore.getState().auditLoading).toBe(false);
  });
});

describe('AuditSlice — setAuditReports', () => {
  it('stores the reports list', () => {
    const reports = [makeAuditReport({ epicId: 'E-001' })];
    useStore.getState().setAuditReports(reports);

    expect(useStore.getState().auditReports).toHaveLength(1);
    expect(useStore.getState().auditReports[0].epicId).toBe('E-001');
  });

  it('derives latestAudit as the first report in the list', () => {
    const reports = [
      makeAuditReport({ epicId: 'E-002', scores: { overall: 92, codeQuality: 95, security: 88, documentation: 85, process: 99, frontend: null, database: null } }),
      makeAuditReport({ epicId: 'E-001', scores: { overall: 75, codeQuality: 80, security: 70, documentation: 65, process: 85, frontend: null, database: null } }),
    ];
    useStore.getState().setAuditReports(reports);

    const { latestAudit } = useStore.getState();
    expect(latestAudit).not.toBeNull();
    expect(latestAudit?.epicId).toBe('E-002');
    expect(latestAudit?.scores.overall).toBe(92);
  });

  it('also updates the healthScore in SatelliteSlice from the first report', () => {
    const reports = [makeAuditReport({ scores: { overall: 88, codeQuality: 90, security: 85, documentation: 80, process: 95, frontend: null, database: null } })];
    useStore.getState().setAuditReports(reports);

    expect(useStore.getState().healthScore).toBe(88);
  });

  it('sets latestAudit to null when given an empty array', () => {
    useStore.getState().setAuditReports([makeAuditReport()]);
    useStore.getState().setAuditReports([]);

    expect(useStore.getState().latestAudit).toBeNull();
    expect(useStore.getState().auditReports).toEqual([]);
  });

  it('sets healthScore to null when given an empty reports array', () => {
    useStore.getState().setAuditReports([makeAuditReport()]);
    useStore.getState().setAuditReports([]);

    expect(useStore.getState().healthScore).toBeNull();
  });

  it('replaces the previous reports on successive calls', () => {
    useStore.getState().setAuditReports([makeAuditReport({ epicId: 'E-001' })]);
    useStore.getState().setAuditReports([makeAuditReport({ epicId: 'E-003' })]);

    expect(useStore.getState().auditReports).toHaveLength(1);
    expect(useStore.getState().latestAudit?.epicId).toBe('E-003');
  });
});

describe('AuditSlice — setAuditLoading', () => {
  it('sets auditLoading to true', () => {
    useStore.getState().setAuditLoading(true);
    expect(useStore.getState().auditLoading).toBe(true);
  });

  it('sets auditLoading back to false', () => {
    useStore.getState().setAuditLoading(true);
    useStore.getState().setAuditLoading(false);
    expect(useStore.getState().auditLoading).toBe(false);
  });
});

// ===========================================================================
// IdeasSlice
// ===========================================================================

describe('IdeasSlice — initial state', () => {
  it('starts with an empty ideas array', () => {
    expect(useStore.getState().ideas).toEqual([]);
  });

  it('starts with ideasLoading false', () => {
    expect(useStore.getState().ideasLoading).toBe(false);
  });
});

describe('IdeasSlice — setIdeas', () => {
  it('replaces the ideas list', () => {
    const ideas = [
      makeStoredIdea({ id: 'I-001', title: 'Idea One' }),
      makeStoredIdea({ id: 'I-002', title: 'Idea Two' }),
    ];
    useStore.getState().setIdeas(ideas);

    const { ideas: stored } = useStore.getState();
    expect(stored).toHaveLength(2);
    expect(stored[0].title).toBe('Idea One');
    expect(stored[1].id).toBe('I-002');
  });

  it('accepts an empty array to clear ideas', () => {
    useStore.getState().setIdeas([makeStoredIdea()]);
    useStore.getState().setIdeas([]);
    expect(useStore.getState().ideas).toEqual([]);
  });
});

describe('IdeasSlice — addIdea', () => {
  it('appends a new idea to an empty list', () => {
    const idea = makeStoredIdea({ id: 'I-001' });
    useStore.getState().addIdea(idea);

    expect(useStore.getState().ideas).toHaveLength(1);
    expect(useStore.getState().ideas[0].id).toBe('I-001');
  });

  it('appends a new idea to the end of an existing list', () => {
    useStore.getState().setIdeas([makeStoredIdea({ id: 'I-001' })]);
    useStore.getState().addIdea(makeStoredIdea({ id: 'I-002', title: 'New Idea' }));

    const { ideas } = useStore.getState();
    expect(ideas).toHaveLength(2);
    expect(ideas[0].id).toBe('I-001');
    expect(ideas[1].id).toBe('I-002');
    expect(ideas[1].title).toBe('New Idea');
  });

  it('preserves all existing ideas when adding a new one', () => {
    const existing = [
      makeStoredIdea({ id: 'I-001' }),
      makeStoredIdea({ id: 'I-002' }),
      makeStoredIdea({ id: 'I-003' }),
    ];
    useStore.getState().setIdeas(existing);
    useStore.getState().addIdea(makeStoredIdea({ id: 'I-004' }));

    expect(useStore.getState().ideas).toHaveLength(4);
  });
});

describe('IdeasSlice — updateIdea', () => {
  it('updates the matching idea by id with partial updates', () => {
    useStore.getState().setIdeas([makeStoredIdea({ id: 'I-001', title: 'Old Title', status: 'idea' })]);
    useStore.getState().updateIdea('I-001', { title: 'New Title', status: 'exploring' });

    const { ideas } = useStore.getState();
    expect(ideas[0].title).toBe('New Title');
    expect(ideas[0].status).toBe('exploring');
  });

  it('does not affect other ideas when updating one', () => {
    useStore.getState().setIdeas([
      makeStoredIdea({ id: 'I-001', title: 'First' }),
      makeStoredIdea({ id: 'I-002', title: 'Second' }),
    ]);
    useStore.getState().updateIdea('I-001', { title: 'Updated First' });

    const { ideas } = useStore.getState();
    expect(ideas[0].title).toBe('Updated First');
    expect(ideas[1].title).toBe('Second');
  });

  it('merges partial updates without overwriting unspecified fields', () => {
    const original = makeStoredIdea({ id: 'I-001', tags: ['ui'], priority: 'high', status: 'idea' });
    useStore.getState().setIdeas([original]);
    useStore.getState().updateIdea('I-001', { status: 'planned' });

    const { ideas } = useStore.getState();
    expect(ideas[0].status).toBe('planned');
    expect(ideas[0].tags).toEqual(['ui']);
    expect(ideas[0].priority).toBe('high');
  });

  it('is a no-op when the ideaId does not exist', () => {
    useStore.getState().setIdeas([makeStoredIdea({ id: 'I-001' })]);
    useStore.getState().updateIdea('NONEXISTENT', { title: 'Ghost' });

    const { ideas } = useStore.getState();
    expect(ideas).toHaveLength(1);
    expect(ideas[0].id).toBe('I-001');
  });
});

describe('IdeasSlice — removeIdea', () => {
  it('removes the idea with the matching id', () => {
    useStore.getState().setIdeas([
      makeStoredIdea({ id: 'I-001' }),
      makeStoredIdea({ id: 'I-002' }),
    ]);
    useStore.getState().removeIdea('I-001');

    const { ideas } = useStore.getState();
    expect(ideas).toHaveLength(1);
    expect(ideas[0].id).toBe('I-002');
  });

  it('is a no-op when the id does not exist', () => {
    useStore.getState().setIdeas([makeStoredIdea({ id: 'I-001' })]);
    useStore.getState().removeIdea('NONEXISTENT');
    expect(useStore.getState().ideas).toHaveLength(1);
  });

  it('is safe to call on an empty list', () => {
    useStore.getState().removeIdea('I-001');
    expect(useStore.getState().ideas).toEqual([]);
  });
});

describe('IdeasSlice — setIdeasLoading', () => {
  it('sets ideasLoading to true', () => {
    useStore.getState().setIdeasLoading(true);
    expect(useStore.getState().ideasLoading).toBe(true);
  });

  it('sets ideasLoading back to false', () => {
    useStore.getState().setIdeasLoading(true);
    useStore.getState().setIdeasLoading(false);
    expect(useStore.getState().ideasLoading).toBe(false);
  });
});

// ===========================================================================
// QueueDetailSlice
// ===========================================================================

describe('QueueDetailSlice — initial state', () => {
  it('starts with empty queueEntries array', () => {
    expect(useStore.getState().queueEntries).toEqual([]);
  });

  it('starts with null scheduleConfig, scheduleStatus, and usageData', () => {
    expect(useStore.getState().scheduleConfig).toBeNull();
    expect(useStore.getState().scheduleStatus).toBeNull();
    expect(useStore.getState().usageData).toBeNull();
  });

  it('starts with queueDetailLoading false', () => {
    expect(useStore.getState().queueDetailLoading).toBe(false);
  });
});

describe('QueueDetailSlice — setQueueEntries', () => {
  it('replaces the queue entries list', () => {
    const entries = [
      makeQueueEntry({ epicId: 'E-001' }),
      makeQueueEntry({ epicId: 'E-002', priority: 'critical' }),
    ];
    useStore.getState().setQueueEntries(entries);

    const { queueEntries } = useStore.getState();
    expect(queueEntries).toHaveLength(2);
    expect(queueEntries[0].epicId).toBe('E-001');
    expect(queueEntries[1].priority).toBe('critical');
  });

  it('accepts empty array to clear queue', () => {
    useStore.getState().setQueueEntries([makeQueueEntry()]);
    useStore.getState().setQueueEntries([]);
    expect(useStore.getState().queueEntries).toEqual([]);
  });
});

describe('QueueDetailSlice — setScheduleConfig', () => {
  it('stores schedule configuration', () => {
    const config = makeScheduleConfig({ cooldownSeconds: 3600, maxConcurrent: 2 });
    useStore.getState().setScheduleConfig(config);

    const { scheduleConfig } = useStore.getState();
    expect(scheduleConfig?.cooldownSeconds).toBe(3600);
    expect(scheduleConfig?.maxConcurrent).toBe(2);
  });

  it('accepts null to clear schedule config', () => {
    useStore.getState().setScheduleConfig(makeScheduleConfig());
    useStore.getState().setScheduleConfig(null);
    expect(useStore.getState().scheduleConfig).toBeNull();
  });
});

describe('QueueDetailSlice — setScheduleStatus', () => {
  it('stores schedule status', () => {
    const status = makeScheduleStatus({ state: 'cooldown', remainingSeconds: 900 });
    useStore.getState().setScheduleStatus(status);

    const { scheduleStatus } = useStore.getState();
    expect(scheduleStatus?.state).toBe('cooldown');
    expect(scheduleStatus?.remainingSeconds).toBe(900);
  });

  it('accepts null to clear schedule status', () => {
    useStore.getState().setScheduleStatus(makeScheduleStatus());
    useStore.getState().setScheduleStatus(null);
    expect(useStore.getState().scheduleStatus).toBeNull();
  });
});

describe('QueueDetailSlice — setUsageData', () => {
  it('stores usage data', () => {
    const usage = makeUsageData({ totalEvents: 200, agentDispatches: 60 });
    useStore.getState().setUsageData(usage);

    const { usageData } = useStore.getState();
    expect(usageData?.totalEvents).toBe(200);
    expect(usageData?.agentDispatches).toBe(60);
  });

  it('accepts null to clear usage data', () => {
    useStore.getState().setUsageData(makeUsageData());
    useStore.getState().setUsageData(null);
    expect(useStore.getState().usageData).toBeNull();
  });
});

describe('QueueDetailSlice — setQueueDetailLoading', () => {
  it('sets queueDetailLoading to true', () => {
    useStore.getState().setQueueDetailLoading(true);
    expect(useStore.getState().queueDetailLoading).toBe(true);
  });

  it('sets queueDetailLoading back to false', () => {
    useStore.getState().setQueueDetailLoading(true);
    useStore.getState().setQueueDetailLoading(false);
    expect(useStore.getState().queueDetailLoading).toBe(false);
  });
});

describe('QueueDetailSlice — reorderQueueEntry', () => {
  it('moves an entry from its current index to the target index', () => {
    const entries = [
      makeQueueEntry({ epicId: 'E-001' }),
      makeQueueEntry({ epicId: 'E-002' }),
      makeQueueEntry({ epicId: 'E-003' }),
    ];
    useStore.getState().setQueueEntries(entries);
    useStore.getState().reorderQueueEntry('E-001', 2);

    const { queueEntries } = useStore.getState();
    expect(queueEntries[0].epicId).toBe('E-002');
    expect(queueEntries[1].epicId).toBe('E-003');
    expect(queueEntries[2].epicId).toBe('E-001');
  });

  it('moves an entry to the first position', () => {
    const entries = [
      makeQueueEntry({ epicId: 'E-001' }),
      makeQueueEntry({ epicId: 'E-002' }),
      makeQueueEntry({ epicId: 'E-003' }),
    ];
    useStore.getState().setQueueEntries(entries);
    useStore.getState().reorderQueueEntry('E-003', 0);

    const { queueEntries } = useStore.getState();
    expect(queueEntries[0].epicId).toBe('E-003');
    expect(queueEntries[1].epicId).toBe('E-001');
    expect(queueEntries[2].epicId).toBe('E-002');
  });

  it('is a no-op when the entry is already at the target index', () => {
    const entries = [
      makeQueueEntry({ epicId: 'E-001' }),
      makeQueueEntry({ epicId: 'E-002' }),
    ];
    useStore.getState().setQueueEntries(entries);
    useStore.getState().reorderQueueEntry('E-001', 0);

    const { queueEntries } = useStore.getState();
    expect(queueEntries[0].epicId).toBe('E-001');
    expect(queueEntries[1].epicId).toBe('E-002');
  });

  it('is a no-op when the epicId does not exist in the list', () => {
    const entries = [makeQueueEntry({ epicId: 'E-001' })];
    useStore.getState().setQueueEntries(entries);
    useStore.getState().reorderQueueEntry('NONEXISTENT', 0);

    expect(useStore.getState().queueEntries[0].epicId).toBe('E-001');
  });

  it('preserves all entries and does not change the list length', () => {
    const entries = [
      makeQueueEntry({ epicId: 'E-001' }),
      makeQueueEntry({ epicId: 'E-002' }),
      makeQueueEntry({ epicId: 'E-003' }),
      makeQueueEntry({ epicId: 'E-004' }),
    ];
    useStore.getState().setQueueEntries(entries);
    useStore.getState().reorderQueueEntry('E-002', 3);

    expect(useStore.getState().queueEntries).toHaveLength(4);
  });
});

// ===========================================================================
// KnowledgeSlice
// ===========================================================================

describe('KnowledgeSlice — initial state', () => {
  it('starts with an empty knowledgeItems array', () => {
    expect(useStore.getState().knowledgeItems).toEqual([]);
  });

  it('starts with knowledgeLoading false', () => {
    expect(useStore.getState().knowledgeLoading).toBe(false);
  });
});

describe('KnowledgeSlice — setKnowledgeItems', () => {
  it('replaces the knowledge items list', () => {
    const items = [
      makeKnowledgeItem({ type: 'agent', name: 'architect' }),
      makeKnowledgeItem({ type: 'skill', name: 'epic-orchestration' }),
      makeKnowledgeItem({ type: 'command', name: '/aid-run-epic' }),
    ];
    useStore.getState().setKnowledgeItems(items);

    const { knowledgeItems } = useStore.getState();
    expect(knowledgeItems).toHaveLength(3);
    expect(knowledgeItems[0].type).toBe('agent');
    expect(knowledgeItems[1].name).toBe('epic-orchestration');
    expect(knowledgeItems[2].type).toBe('command');
  });

  it('accepts an empty array to clear items', () => {
    useStore.getState().setKnowledgeItems([makeKnowledgeItem()]);
    useStore.getState().setKnowledgeItems([]);
    expect(useStore.getState().knowledgeItems).toEqual([]);
  });

  it('replaces the previous list on successive calls', () => {
    useStore.getState().setKnowledgeItems([makeKnowledgeItem({ name: 'old' })]);
    useStore.getState().setKnowledgeItems([makeKnowledgeItem({ name: 'new' })]);

    expect(useStore.getState().knowledgeItems).toHaveLength(1);
    expect(useStore.getState().knowledgeItems[0].name).toBe('new');
  });
});

describe('KnowledgeSlice — setKnowledgeLoading', () => {
  it('sets knowledgeLoading to true', () => {
    useStore.getState().setKnowledgeLoading(true);
    expect(useStore.getState().knowledgeLoading).toBe(true);
  });

  it('sets knowledgeLoading back to false', () => {
    useStore.getState().setKnowledgeLoading(true);
    useStore.getState().setKnowledgeLoading(false);
    expect(useStore.getState().knowledgeLoading).toBe(false);
  });
});

// ===========================================================================
// Cross-slice isolation — new slices
// ===========================================================================

describe('Cross-slice isolation — new slices do not interfere with each other', () => {
  it('updating DecisionsSlice does not affect KnowledgeSlice', () => {
    const items = [makeKnowledgeItem({ name: 'architect' })];
    useStore.getState().setKnowledgeItems(items);

    useStore.getState().setPendingDecisionsList([makePendingDecision()]);
    useStore.getState().setDecisionsLoading(true);
    useStore.getState().addDecisionToHistory(makeDecisionEntry());

    expect(useStore.getState().knowledgeItems).toHaveLength(1);
    expect(useStore.getState().knowledgeItems[0].name).toBe('architect');
  });

  it('updating IdeasSlice does not affect QueueDetailSlice', () => {
    const entries = [makeQueueEntry({ epicId: 'E-001' })];
    useStore.getState().setQueueEntries(entries);

    useStore.getState().setIdeas([makeStoredIdea({ id: 'I-001' })]);
    useStore.getState().addIdea(makeStoredIdea({ id: 'I-002' }));
    useStore.getState().removeIdea('I-001');

    expect(useStore.getState().queueEntries).toHaveLength(1);
    expect(useStore.getState().queueEntries[0].epicId).toBe('E-001');
  });

  it('AuditSlice setAuditReports updates healthScore in SatelliteSlice but does not touch DecisionsSlice', () => {
    useStore.getState().setPendingDecisionsList([makePendingDecision()]);
    useStore.getState().setDecisionHistory([makeDecisionEntry()]);

    useStore.getState().setAuditReports([makeAuditReport({ scores: { overall: 77, codeQuality: null, security: null, documentation: null, process: null, frontend: null, database: null } })]);

    expect(useStore.getState().healthScore).toBe(77);
    expect(useStore.getState().pendingDecisionsList).toHaveLength(1);
    expect(useStore.getState().decisionHistory).toHaveLength(1);
  });

  it('EvidenceSlice updates do not affect IdeasSlice', () => {
    useStore.getState().setIdeas([makeStoredIdea({ id: 'I-001' })]);

    useStore.getState().setEvidenceEpics([makeEvidenceEpic()]);
    useStore.getState().setEvidenceSelection('E-001', 'run-001', 'plan.json');
    useStore.getState().setEvidenceLoading(true);

    expect(useStore.getState().ideas).toHaveLength(1);
    expect(useStore.getState().ideas[0].id).toBe('I-001');
  });

  it('new slices do not corrupt existing ConnectionSlice', () => {
    useStore.getState().setWsStatus('connected');
    useStore.getState().handleHeartbeat('2026-02-25T10:00:00.000Z', 5);

    useStore.getState().setAuditReports([makeAuditReport()]);
    useStore.getState().setKnowledgeItems([makeKnowledgeItem()]);
    useStore.getState().setQueueDetailLoading(true);

    expect(useStore.getState().wsStatus).toBe('connected');
    expect(useStore.getState().serverClientCount).toBe(5);
  });
});

// ===========================================================================
// Store reset validation
// ===========================================================================

describe('Store reset — new slices are cleaned between tests', () => {
  it('state set in this test does not leak (first test)', () => {
    useStore.getState().setPendingDecisionsList([makePendingDecision()]);
    useStore.getState().setIdeas([makeStoredIdea()]);
    useStore.getState().setKnowledgeItems([makeKnowledgeItem()]);
    useStore.getState().setAuditReports([makeAuditReport()]);

    expect(useStore.getState().pendingDecisionsList).toHaveLength(1);
  });

  it('state from previous test is fully reset (second test)', () => {
    expect(useStore.getState().pendingDecisionsList).toEqual([]);
    expect(useStore.getState().ideas).toEqual([]);
    expect(useStore.getState().knowledgeItems).toEqual([]);
    expect(useStore.getState().auditReports).toEqual([]);
    expect(useStore.getState().latestAudit).toBeNull();
  });
});
