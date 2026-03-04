/**
 * Integration tests for the 13 new API client methods added in the
 * screen integration phase (`src/api/client.ts`).
 *
 * All network calls are intercepted via a `vi.fn()` mock on the global
 * `fetch`. No real server is started; tests are fully self-contained.
 *
 * New methods covered:
 *   getDecisionsPending  — GET /decisions/pending
 *   postDecision         — POST /decisions
 *   getEvidence          — GET /evidence
 *   getEvidenceFile      — GET /evidence/:epicId/:runId/files/:filePath
 *   getIdeas             — GET /ideas
 *   createIdea           — POST /ideas
 *   updateIdea           — PUT /ideas/:ideaId
 *   deleteIdea           — DELETE /ideas/:ideaId
 *   getQueueSchedule     — GET /queue/schedule
 *   updateQueueSchedule  — PUT /queue/schedule
 *   getQueueScheduleStatus — GET /queue/schedule/status
 *   updateQueueEntry     — PUT /queue/:epicId
 *   getKnowledge         — GET /knowledge
 *
 * For each method, tests verify:
 *   - Correct URL is constructed
 *   - Correct HTTP method is used
 *   - Request body is sent for POST/PUT (and not for GET/DELETE)
 *   - Content-Type header is set for POST/PUT
 *   - Success responses are correctly parsed
 *   - Error responses are correctly returned
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createApiClient } from '../../src/api/client.ts';
import type { ApiError } from '../../src/types/api.ts';
import type {
  PendingDecisionEntry,
  DecisionEntry,
  EvidenceEpicEntry,
  EvidenceFileResponse,
  StoredIdea,
  ScheduleConfig,
  ScheduleStatusResponse,
  QueueScheduleEntry,
  KnowledgeItem,
} from '../../src/types/api.ts';

// ---------------------------------------------------------------------------
// Mock helpers (same pattern as the existing api-client.test.ts)
// ---------------------------------------------------------------------------

function mockResponse(status: number, body: unknown, contentType = 'application/json'): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 200 ? 'OK' : status === 404 ? 'Not Found' : 'Internal Server Error',
    headers: new Headers({ 'content-type': contentType }),
    json: () => Promise.resolve(body),
  } as unknown as Response;
}

function mockNonJsonResponse(status: number): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 200 ? 'OK' : 'Error',
    headers: new Headers({ 'content-type': 'text/plain' }),
    json: () => Promise.reject(new SyntaxError('Unexpected token')),
  } as unknown as Response;
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const PENDING_DECISIONS: PendingDecisionEntry[] = [
  {
    epicId: 'E-001',
    runId: 'run-001',
    state: 'PLAN_REVIEW',
    evidencePath: '/path/to/evidence',
  },
  {
    epicId: 'E-002',
    runId: 'run-002',
    state: 'PM_APPROVAL',
    evidencePath: '/path/to/evidence2',
  },
];

const DECISION_ENTRY: DecisionEntry = {
  timestamp: '2026-02-25T10:00:00.000Z',
  type: 'plan_approval',
  epicId: 'E-001',
  runId: 'run-001',
  decision: 'approved',
  channel: 'gui',
  latencyMinutes: 2,
};

const EVIDENCE_EPICS: EvidenceEpicEntry[] = [
  {
    epicId: 'E-001',
    runs: [
      {
        runId: 'run-001',
        files: ['plan.json', 'timeline.jsonl', 'gates_report.json'],
        hasStageLog: true,
        hasPlan: true,
        hasGatesReport: true,
      },
    ],
  },
];

const EVIDENCE_FILE: EvidenceFileResponse = {
  filePath: 'plan.json',
  format: 'json',
  content: { steps: [{ id: 'step_1', role: 'architect', objective: 'Design the system' }] },
};

const STORED_IDEAS: StoredIdea[] = [
  {
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
  },
];

const CREATED_IDEA: StoredIdea = {
  id: 'I-002',
  title: 'Add CI pipeline',
  description: 'Configure GitHub Actions for automated testing',
  tags: ['devops'],
  priority: 'high',
  status: 'idea',
  autoStatus: null,
  linkedPlan: null,
  linkedEpic: null,
  createdAt: '2026-02-25T10:00:00.000Z',
  updatedAt: '2026-02-25T10:00:00.000Z',
};

const SCHEDULE_CONFIG: ScheduleConfig = {
  enabled: true,
  cooldownSeconds: 1800,
  maxConcurrent: 1,
  delayedStartAt: null,
  autoPauseAtCcLimit: true,
  ccLimitThreshold: 100000,
  lastRunCompletedAt: null,
};

const SCHEDULE_STATUS: ScheduleStatusResponse = {
  state: 'idle',
  remainingSeconds: null,
  config: SCHEDULE_CONFIG,
  timestamp: '2026-02-25T10:00:00.000Z',
};

const QUEUE_ENTRY: QueueScheduleEntry = {
  epicId: 'E-001',
  path: '.aid-o/tasks/E-001.md',
  priority: 'high',
  status: 'queued',
  addedAt: '2026-02-25T08:00:00.000Z',
  startedAt: null,
  completedAt: null,
};

const KNOWLEDGE_ITEMS: KnowledgeItem[] = [
  { type: 'agent', name: 'architect', description: 'Designs system architecture', filename: 'architect.md' },
  { type: 'skill', name: 'epic-orchestration', description: 'Orchestrates EPICs', filename: 'epic-orchestration.md' },
  { type: 'command', name: '/aid-run-epic', description: 'Runs an EPIC', filename: 'aid-run-epic.md' },
];

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn();
  global.fetch = fetchMock as typeof fetch;
});

afterEach(() => {
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// getDecisionsPending — GET /api/p/:projectId/decisions/pending
// ---------------------------------------------------------------------------

describe('getDecisionsPending', () => {
  it('returns pending decisions on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: PENDING_DECISIONS }));

    const result = await client.getDecisionsPending();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toHaveLength(2);
      expect(result.data[0].epicId).toBe('E-001');
      expect(result.data[0].state).toBe('PLAN_REVIEW');
      expect(result.data[1].runId).toBe('run-002');
    }
  });

  it('constructs the correct URL with /decisions/pending path', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: [] }));

    await client.getDecisionsPending();

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/decisions/pending');
  });

  it('uses GET method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: [] }));

    await client.getDecisionsPending();

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('GET');
  });

  it('returns an error result on 404', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(404, { ok: false, error: { code: 'NOT_FOUND', message: 'No pending decisions endpoint' } }),
    );

    const result = await client.getDecisionsPending();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('NOT_FOUND');
    }
  });
});

// ---------------------------------------------------------------------------
// postDecision — POST /api/p/:projectId/decisions
// ---------------------------------------------------------------------------

describe('postDecision', () => {
  it('returns the created decision entry on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: DECISION_ENTRY }));

    const result = await client.postDecision({
      epicId: 'E-001',
      runId: 'run-001',
      decision: 'approved',
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.decision).toBe('approved');
      expect(result.data.epicId).toBe('E-001');
      expect(result.data.channel).toBe('gui');
    }
  });

  it('uses POST method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: DECISION_ENTRY }));

    await client.postDecision({ epicId: 'E-001', runId: 'run-001', decision: 'approved' });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('POST');
  });

  it('sends the request body as JSON', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: DECISION_ENTRY }));

    const requestBody = { epicId: 'E-001', runId: 'run-001', decision: 'rejected', feedback: 'Needs revision' };
    await client.postDecision(requestBody);

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.body).toBe(JSON.stringify(requestBody));
  });

  it('sets Content-Type: application/json header', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: DECISION_ENTRY }));

    await client.postDecision({ epicId: 'E-001', runId: 'run-001', decision: 'approved' });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect((options.headers as Record<string, string>)?.['Content-Type']).toBe('application/json');
  });

  it('constructs the correct URL /decisions', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: DECISION_ENTRY }));

    await client.postDecision({ epicId: 'E-001', runId: 'run-001', decision: 'approved' });

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/decisions');
  });

  it('returns an error result on 500', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(500, { ok: false, error: { code: 'INTERNAL_ERROR', message: 'Failed to write decision' } }),
    );

    const result = await client.postDecision({ epicId: 'E-001', runId: 'run-001', decision: 'approved' });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('INTERNAL_ERROR');
    }
  });
});

// ---------------------------------------------------------------------------
// getEvidence — GET /api/p/:projectId/evidence
// ---------------------------------------------------------------------------

describe('getEvidence', () => {
  it('returns evidence EPIC list on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: EVIDENCE_EPICS }));

    const result = await client.getEvidence();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toHaveLength(1);
      expect(result.data[0].epicId).toBe('E-001');
      expect(result.data[0].runs[0].files).toContain('plan.json');
    }
  });

  it('constructs the correct /evidence URL', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: [] }));

    await client.getEvidence();

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/evidence');
  });

  it('uses GET method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: [] }));

    await client.getEvidence();

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('GET');
  });

  it('returns an error result on 500', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(500, { ok: false, error: { code: 'FS_ERROR', message: 'Cannot read evidence directory' } }),
    );

    const result = await client.getEvidence();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('FS_ERROR');
    }
  });
});

// ---------------------------------------------------------------------------
// getEvidenceFile — GET /api/p/:projectId/evidence/:epicId/:runId/files/:filePath
// ---------------------------------------------------------------------------

describe('getEvidenceFile', () => {
  it('returns the file content on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: EVIDENCE_FILE }));

    const result = await client.getEvidenceFile('E-001', 'run-001', 'plan.json');

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.filePath).toBe('plan.json');
      expect(result.data.format).toBe('json');
    }
  });

  it('constructs the correct URL with epicId, runId, and filePath path params', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: EVIDENCE_FILE }));

    await client.getEvidenceFile('E-001', 'run-001', 'plan.json');

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/evidence/E-001/run-001/files/plan.json');
  });

  it('URL-encodes epicId and runId in path params', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: EVIDENCE_FILE }));

    await client.getEvidenceFile('E 001', 'run/001', 'plan.json');

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toContain('E%20001');
    expect(calledUrl).toContain('run%2F001');
  });

  it('uses GET method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: EVIDENCE_FILE }));

    await client.getEvidenceFile('E-001', 'run-001', 'plan.json');

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('GET');
  });

  it('returns an error result on 404 (file not found)', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(404, { ok: false, error: { code: 'NOT_FOUND', message: 'File not found' } }),
    );

    const result = await client.getEvidenceFile('E-001', 'run-001', 'missing.json');

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('NOT_FOUND');
    }
  });
});

// ---------------------------------------------------------------------------
// getIdeas — GET /api/p/:projectId/ideas
// ---------------------------------------------------------------------------

describe('getIdeas', () => {
  it('returns the ideas list on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: STORED_IDEAS }));

    const result = await client.getIdeas();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toHaveLength(1);
      expect(result.data[0].id).toBe('I-001');
      expect(result.data[0].status).toBe('idea');
    }
  });

  it('constructs the correct /ideas URL', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: [] }));

    await client.getIdeas();

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/ideas');
  });

  it('uses GET method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: [] }));

    await client.getIdeas();

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('GET');
  });

  it('returns an error result on server error', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(500, { ok: false, error: { code: 'FS_ERROR', message: 'Cannot read ideas file' } }),
    );

    const result = await client.getIdeas();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('FS_ERROR');
    }
  });
});

// ---------------------------------------------------------------------------
// createIdea — POST /api/p/:projectId/ideas
// ---------------------------------------------------------------------------

describe('createIdea', () => {
  it('returns the created idea on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    const result = await client.createIdea({ title: 'Add CI pipeline', priority: 'high', tags: ['devops'] });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.id).toBe('I-002');
      expect(result.data.title).toBe('Add CI pipeline');
      expect(result.data.priority).toBe('high');
    }
  });

  it('uses POST method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    await client.createIdea({ title: 'Test idea' });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('POST');
  });

  it('sends the request body as JSON', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    const requestBody = { title: 'Test idea', priority: 'high' as const, tags: ['test'] };
    await client.createIdea(requestBody);

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.body).toBe(JSON.stringify(requestBody));
  });

  it('sets Content-Type: application/json header', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    await client.createIdea({ title: 'Test idea' });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect((options.headers as Record<string, string>)?.['Content-Type']).toBe('application/json');
  });

  it('constructs the correct /ideas URL', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    await client.createIdea({ title: 'Test idea' });

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/ideas');
  });
});

// ---------------------------------------------------------------------------
// updateIdea — PUT /api/p/:projectId/ideas/:ideaId
// ---------------------------------------------------------------------------

describe('updateIdea', () => {
  it('returns the updated idea on success', async () => {
    const client = createApiClient('my-project');
    const updatedIdea = { ...CREATED_IDEA, status: 'planned' as const };
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: updatedIdea }));

    const result = await client.updateIdea('I-002', { status: 'planned' });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.status).toBe('planned');
    }
  });

  it('uses PUT method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    await client.updateIdea('I-001', { status: 'exploring' });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('PUT');
  });

  it('constructs the correct URL with ideaId path param', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    await client.updateIdea('I-001', { status: 'done' });

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/ideas/I-001');
  });

  it('URL-encodes the ideaId in the path', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    await client.updateIdea('I 001', { status: 'done' });

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toContain('I%20001');
  });

  it('sends the update body as JSON', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    const updates = { status: 'exploring' as const, linkedEpic: 'E-005' };
    await client.updateIdea('I-001', updates);

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.body).toBe(JSON.stringify(updates));
  });

  it('sets Content-Type: application/json header', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: CREATED_IDEA }));

    await client.updateIdea('I-001', { title: 'Updated Title' });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect((options.headers as Record<string, string>)?.['Content-Type']).toBe('application/json');
  });
});

// ---------------------------------------------------------------------------
// deleteIdea — DELETE /api/p/:projectId/ideas/:ideaId
// ---------------------------------------------------------------------------

describe('deleteIdea', () => {
  it('returns { deleted: true } on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: { deleted: true } }));

    const result = await client.deleteIdea('I-001');

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.deleted).toBe(true);
    }
  });

  it('uses DELETE method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: { deleted: true } }));

    await client.deleteIdea('I-001');

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('DELETE');
  });

  it('constructs the correct URL with ideaId path param', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: { deleted: true } }));

    await client.deleteIdea('I-001');

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/ideas/I-001');
  });

  it('does not send a request body for DELETE', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: { deleted: true } }));

    await client.deleteIdea('I-001');

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.body).toBeUndefined();
  });

  it('does not set Content-Type header for DELETE', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: { deleted: true } }));

    await client.deleteIdea('I-001');

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect((options.headers as Record<string, string>)?.['Content-Type']).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// getQueueSchedule — GET /api/p/:projectId/queue/schedule
// ---------------------------------------------------------------------------

describe('getQueueSchedule', () => {
  it('returns the schedule config on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_CONFIG }));

    const result = await client.getQueueSchedule();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.cooldownSeconds).toBe(1800);
      expect(result.data.maxConcurrent).toBe(1);
      expect(result.data.autoPauseAtCcLimit).toBe(true);
    }
  });

  it('constructs the correct /queue/schedule URL', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_CONFIG }));

    await client.getQueueSchedule();

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/queue/schedule');
  });

  it('uses GET method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_CONFIG }));

    await client.getQueueSchedule();

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('GET');
  });
});

// ---------------------------------------------------------------------------
// updateQueueSchedule — PUT /api/p/:projectId/queue/schedule
// ---------------------------------------------------------------------------

describe('updateQueueSchedule', () => {
  it('returns the updated schedule config on success', async () => {
    const client = createApiClient('my-project');
    const updatedConfig = { ...SCHEDULE_CONFIG, cooldownSeconds: 3600, maxConcurrent: 2 };
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: updatedConfig }));

    const result = await client.updateQueueSchedule({ cooldownSeconds: 3600, maxConcurrent: 2 });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.cooldownSeconds).toBe(3600);
      expect(result.data.maxConcurrent).toBe(2);
    }
  });

  it('uses PUT method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_CONFIG }));

    await client.updateQueueSchedule({ cooldownSeconds: 900 });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('PUT');
  });

  it('sends the partial config as JSON request body', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_CONFIG }));

    const partialConfig = { autoPauseAtCcLimit: false };
    await client.updateQueueSchedule(partialConfig);

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.body).toBe(JSON.stringify(partialConfig));
  });

  it('sets Content-Type: application/json header', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_CONFIG }));

    await client.updateQueueSchedule({ cooldownSeconds: 900 });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect((options.headers as Record<string, string>)?.['Content-Type']).toBe('application/json');
  });

  it('constructs the correct /queue/schedule URL', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_CONFIG }));

    await client.updateQueueSchedule({ enabled: false });

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/queue/schedule');
  });
});

// ---------------------------------------------------------------------------
// getQueueScheduleStatus — GET /api/p/:projectId/queue/schedule/status
// ---------------------------------------------------------------------------

describe('getQueueScheduleStatus', () => {
  it('returns the schedule status on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_STATUS }));

    const result = await client.getQueueScheduleStatus();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.state).toBe('idle');
      expect(result.data.remainingSeconds).toBeNull();
      expect(result.data.config.cooldownSeconds).toBe(1800);
    }
  });

  it('constructs the correct /queue/schedule/status URL', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_STATUS }));

    await client.getQueueScheduleStatus();

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/queue/schedule/status');
  });

  it('uses GET method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: SCHEDULE_STATUS }));

    await client.getQueueScheduleStatus();

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('GET');
  });
});

// ---------------------------------------------------------------------------
// updateQueueEntry — PUT /api/p/:projectId/queue/:epicId
// ---------------------------------------------------------------------------

describe('updateQueueEntry', () => {
  it('returns the updated queue entry on success', async () => {
    const client = createApiClient('my-project');
    const updatedEntry = { ...QUEUE_ENTRY, priority: 'critical' as const };
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: updatedEntry }));

    const result = await client.updateQueueEntry('E-001', { priority: 'critical' });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.epicId).toBe('E-001');
      expect(result.data.priority).toBe('critical');
    }
  });

  it('uses PUT method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: QUEUE_ENTRY }));

    await client.updateQueueEntry('E-001', { priority: 'low' });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('PUT');
  });

  it('constructs the correct URL with epicId path param', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: QUEUE_ENTRY }));

    await client.updateQueueEntry('E-001', { priority: 'medium' });

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/queue/E-001');
  });

  it('URL-encodes the epicId in the path', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: QUEUE_ENTRY }));

    await client.updateQueueEntry('E 001', { priority: 'high' });

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toContain('E%20001');
  });

  it('sends the update body as JSON', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: QUEUE_ENTRY }));

    const updates = { priority: 'critical' as const };
    await client.updateQueueEntry('E-001', updates);

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.body).toBe(JSON.stringify(updates));
  });

  it('sets Content-Type: application/json header', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: QUEUE_ENTRY }));

    await client.updateQueueEntry('E-001', { priority: 'low' });

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect((options.headers as Record<string, string>)?.['Content-Type']).toBe('application/json');
  });
});

// ---------------------------------------------------------------------------
// getKnowledge — GET /api/p/:projectId/knowledge
// ---------------------------------------------------------------------------

describe('getKnowledge', () => {
  it('returns knowledge items on success', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: KNOWLEDGE_ITEMS }));

    const result = await client.getKnowledge();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toHaveLength(3);
      expect(result.data[0].type).toBe('agent');
      expect(result.data[1].type).toBe('skill');
      expect(result.data[2].type).toBe('command');
      expect(result.data[0].name).toBe('architect');
    }
  });

  it('constructs the correct /knowledge URL', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: [] }));

    await client.getKnowledge();

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://srv/api/p/proj/knowledge');
  });

  it('uses GET method', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: [] }));

    await client.getKnowledge();

    const options = fetchMock.mock.calls[0][1] as RequestInit;
    expect(options.method).toBe('GET');
  });

  it('returns an error result on 500', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(500, { ok: false, error: { code: 'FS_ERROR', message: 'Cannot scan plugin files' } }),
    );

    const result = await client.getKnowledge();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('FS_ERROR');
    }
  });

  it('returns an empty array when no knowledge items exist', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockResponse(200, { ok: true, data: [] }));

    const result = await client.getKnowledge();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toEqual([]);
    }
  });
});

// ---------------------------------------------------------------------------
// URL construction — all 13 new endpoints in one table-driven test
// ---------------------------------------------------------------------------

describe('URL construction — all 13 new endpoint methods', () => {
  it('builds correct URL for each new endpoint method', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    const okResponse = { ok: true, data: {} };

    const endpointMap: [() => Promise<unknown>, string][] = [
      [() => client.getDecisionsPending(), '/api/p/proj/decisions/pending'],
      [() => client.postDecision({ epicId: 'E-001', runId: 'r-001', decision: 'approved' }), '/api/p/proj/decisions'],
      [() => client.getEvidence(), '/api/p/proj/evidence'],
      [() => client.getEvidenceFile('E-001', 'run-001', 'plan.json'), '/api/p/proj/evidence/E-001/run-001/files/plan.json'],
      [() => client.getIdeas(), '/api/p/proj/ideas'],
      [() => client.createIdea({ title: 'Test' }), '/api/p/proj/ideas'],
      [() => client.updateIdea('I-001', { title: 'Updated' }), '/api/p/proj/ideas/I-001'],
      [() => client.deleteIdea('I-001'), '/api/p/proj/ideas/I-001'],
      [() => client.getQueueSchedule(), '/api/p/proj/queue/schedule'],
      [() => client.updateQueueSchedule({ cooldownSeconds: 900 }), '/api/p/proj/queue/schedule'],
      [() => client.getQueueScheduleStatus(), '/api/p/proj/queue/schedule/status'],
      [() => client.updateQueueEntry('E-001', { priority: 'low' }), '/api/p/proj/queue/E-001'],
      [() => client.getKnowledge(), '/api/p/proj/knowledge'],
    ];

    for (const [method, expectedPath] of endpointMap) {
      fetchMock.mockResolvedValueOnce(mockResponse(200, okResponse));
      await method();
      const calledUrl = fetchMock.mock.calls[fetchMock.mock.calls.length - 1][0] as string;
      expect(calledUrl).toBe(`http://srv${expectedPath}`);
    }
  });
});

// ---------------------------------------------------------------------------
// HTTP method verification — table-driven test for all 13 methods
// ---------------------------------------------------------------------------

describe('HTTP method verification — new endpoints', () => {
  it('uses the correct HTTP method for each new endpoint', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    const okResponse = { ok: true, data: {} };

    const methodMap: [() => Promise<unknown>, string][] = [
      [() => client.getDecisionsPending(), 'GET'],
      [() => client.postDecision({ epicId: 'E-001', runId: 'r-001', decision: 'approved' }), 'POST'],
      [() => client.getEvidence(), 'GET'],
      [() => client.getEvidenceFile('E-001', 'run-001', 'plan.json'), 'GET'],
      [() => client.getIdeas(), 'GET'],
      [() => client.createIdea({ title: 'Test' }), 'POST'],
      [() => client.updateIdea('I-001', { title: 'Updated' }), 'PUT'],
      [() => client.deleteIdea('I-001'), 'DELETE'],
      [() => client.getQueueSchedule(), 'GET'],
      [() => client.updateQueueSchedule({ cooldownSeconds: 900 }), 'PUT'],
      [() => client.getQueueScheduleStatus(), 'GET'],
      [() => client.updateQueueEntry('E-001', { priority: 'low' }), 'PUT'],
      [() => client.getKnowledge(), 'GET'],
    ];

    for (const [method, expectedHttpMethod] of methodMap) {
      fetchMock.mockResolvedValueOnce(mockResponse(200, okResponse));
      await method();
      const options = fetchMock.mock.calls[fetchMock.mock.calls.length - 1][1] as RequestInit;
      expect(options.method).toBe(expectedHttpMethod);
    }
  });
});

// ---------------------------------------------------------------------------
// Error handling — non-JSON body from server on new methods
// ---------------------------------------------------------------------------

describe('Error handling for new methods', () => {
  it('produces HTTP_500 when getDecisionsPending returns non-JSON error', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockNonJsonResponse(500));

    const result = await client.getDecisionsPending();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('HTTP_500');
    }
  });

  it('produces NETWORK_ERROR when getKnowledge fetch throws', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockRejectedValueOnce(new TypeError('Connection refused'));

    const result = await client.getKnowledge();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('NETWORK_ERROR');
      expect((result as ApiError).error.message).toContain('Connection refused');
    }
  });

  it('produces HTTP_404 when getEvidence returns non-JSON 404 body', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockNonJsonResponse(404));

    const result = await client.getEvidence();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('HTTP_404');
    }
  });

  it('produces INVALID_RESPONSE when createIdea returns non-JSON 200', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockNonJsonResponse(200));

    const result = await client.createIdea({ title: 'Test' });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('INVALID_RESPONSE');
    }
  });
});
