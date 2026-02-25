/**
 * Integration tests for the typed API client (`src/api/client.ts`).
 *
 * All network calls are intercepted via a `vi.fn()` mock on the global
 * `fetch`.  No real server is started; tests are fully self-contained.
 *
 * Coverage strategy
 * -----------------
 * - Happy path: every endpoint returns `{ ok: true, data: <typed payload> }`
 * - Error path: 404 / 500 with JSON error body -> forwarded as ApiError
 * - Non-JSON body on error -> code `HTTP_<status>`
 * - Non-JSON body on 200 -> code `INVALID_RESPONSE`
 * - JSON without `ok` key on 200 -> wrapped in `{ ok: true, data: body }`
 * - Network failure (fetch throws) -> code `NETWORK_ERROR`
 * - AbortController timeout -> code `TIMEOUT`
 * - Custom `baseUrl` is honoured in request URL construction
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createApiClient } from '../../src/api/client.ts';
import type { ApiClient } from '../../src/api/client.ts';
import type { ApiError } from '../../src/types/api.ts';
import type {
  PipelineStateResponse,
  PipelineStepsResponse,
  StageLogEntryResponse,
  QueueResponse,
  DecisionsResponse,
  UsageResponse,
  AuditReportResponse,
} from '../../src/types/api.ts';

// ---------------------------------------------------------------------------
// Mock helpers
// ---------------------------------------------------------------------------

/** Build a minimal mock `Response` whose `.json()` returns `body`. */
function mockResponse(
  status: number,
  body: unknown,
  contentType = 'application/json',
): Response {
  const text = JSON.stringify(body);
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 200 ? 'OK' : status === 404 ? 'Not Found' : 'Internal Server Error',
    headers: new Headers({ 'content-type': contentType }),
    json: () => Promise.resolve(body),
  } as unknown as Response;
}

/** Build a mock `Response` whose `.json()` rejects (non-JSON body). */
function mockNonJsonResponse(status: number, contentType = 'text/plain'): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 200 ? 'OK' : 'Error',
    headers: new Headers({ 'content-type': contentType }),
    json: () => Promise.reject(new SyntaxError('Unexpected token')),
  } as unknown as Response;
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const PIPELINE_STATE: PipelineStateResponse = {
  currentState: 'EXECUTING',
  currentEpicId: 'E-001',
  currentStepId: 'step_1',
  progress: { epicsCompleted: 1, epicsTotal: 3, stepsCompleted: 2, stepsTotal: 8 },
};

const PIPELINE_STEPS: PipelineStepsResponse = [
  { id: 'step_1', role: 'architect', objective: 'Design the system' },
  { id: 'step_2', role: 'backend', objective: 'Implement API' },
];

const STAGE_LOG_ENTRIES: StageLogEntryResponse[] = [
  {
    timestamp: '2026-02-25T10:00:00.000Z',
    state: 'EXECUTING',
    step: 'step_1',
    action: 'dispatch_agent',
    details: 'Dispatching architect',
    result: 'pass',
  },
];

const QUEUE_RESPONSE: QueueResponse = {
  paused: false,
  queue: [
    {
      epicId: 'E-002',
      path: '.aid-o/02-epics/E-002.md',
      priority: 'high',
      status: 'queued',
      addedAt: '2026-02-25T09:00:00.000Z',
      startedAt: null,
      completedAt: null,
    },
  ],
};

const DECISIONS_RESPONSE: DecisionsResponse = [
  {
    timestamp: '2026-02-25T08:00:00.000Z',
    type: 'plan_approval',
    epicId: 'E-001',
    decision: 'approved',
  },
];

const USAGE_RESPONSE: UsageResponse = {
  totalEvents: 150,
  agentDispatches: 42,
  gateEvaluations: 12,
  escalations: 2,
  perEpic: [],
};

const AUDIT_RESPONSE: AuditReportResponse = {
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
};

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
// Happy-path tests — all 7 endpoint methods
// ---------------------------------------------------------------------------

describe('createApiClient — happy path responses', () => {
  it('getPipelineState returns typed pipeline state on 200', async () => {
    const client: ApiClient = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: PIPELINE_STATE }),
    );

    const result = await client.getPipelineState();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.currentState).toBe('EXECUTING');
      expect(result.data.currentEpicId).toBe('E-001');
      expect(result.data.progress.stepsTotal).toBe(8);
    }
  });

  it('getPipelineSteps returns typed steps array on 200', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: PIPELINE_STEPS }),
    );

    const result = await client.getPipelineSteps();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toHaveLength(2);
      expect(result.data[0].id).toBe('step_1');
      expect(result.data[1].role).toBe('backend');
    }
  });

  it('getStageLog returns typed log entries array on 200', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: STAGE_LOG_ENTRIES }),
    );

    const result = await client.getStageLog();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toHaveLength(1);
      expect(result.data[0].action).toBe('dispatch_agent');
      expect(result.data[0].result).toBe('pass');
    }
  });

  it('getQueue returns typed queue response on 200', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: QUEUE_RESPONSE }),
    );

    const result = await client.getQueue();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.paused).toBe(false);
      expect(result.data.queue).toHaveLength(1);
      expect(result.data.queue[0].epicId).toBe('E-002');
    }
  });

  it('getDecisions returns typed decisions array on 200', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: DECISIONS_RESPONSE }),
    );

    const result = await client.getDecisions();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toHaveLength(1);
      expect(result.data[0].decision).toBe('approved');
    }
  });

  it('getUsage returns typed usage metrics on 200', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: USAGE_RESPONSE }),
    );

    const result = await client.getUsage();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.totalEvents).toBe(150);
      expect(result.data.agentDispatches).toBe(42);
      expect(result.data.escalations).toBe(2);
    }
  });

  it('getAuditHealth returns typed audit report on 200', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: AUDIT_RESPONSE }),
    );

    const result = await client.getAuditHealth();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.scores.overall).toBe(88);
      expect(result.data.epicId).toBe('E-001');
    }
  });
});

// ---------------------------------------------------------------------------
// Error-path tests — server returns 4xx / 5xx
// ---------------------------------------------------------------------------

describe('createApiClient — error responses', () => {
  it('forwards server { ok: false, error } body on 404', async () => {
    const client = createApiClient('my-project');
    const serverError = {
      ok: false,
      error: { code: 'NOT_FOUND', message: 'Project not found' },
    };
    fetchMock.mockResolvedValueOnce(mockResponse(404, serverError));

    const result = await client.getPipelineState();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('NOT_FOUND');
      expect((result as ApiError).error.message).toBe('Project not found');
    }
  });

  it('forwards server { ok: false, error } body on 500', async () => {
    const client = createApiClient('my-project');
    const serverError = {
      ok: false,
      error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' },
    };
    fetchMock.mockResolvedValueOnce(mockResponse(500, serverError));

    const result = await client.getPipelineState();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('INTERNAL_ERROR');
    }
  });

  it('produces HTTP_404 code when 404 returns non-JSON body', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockNonJsonResponse(404));

    const result = await client.getPipelineState();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('HTTP_404');
      expect((result as ApiError).error.message).toContain('404');
    }
  });

  it('produces HTTP_500 code when 500 returns non-JSON body', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockNonJsonResponse(500));

    const result = await client.getPipelineState();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('HTTP_500');
    }
  });

  it('produces INVALID_RESPONSE code when 200 returns non-JSON body', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(mockNonJsonResponse(200));

    const result = await client.getPipelineState();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('INVALID_RESPONSE');
    }
  });
});

// ---------------------------------------------------------------------------
// Network failure and timeout tests
// ---------------------------------------------------------------------------

describe('createApiClient — network errors and timeouts', () => {
  it('returns NETWORK_ERROR when fetch throws a TypeError', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockRejectedValueOnce(new TypeError('Failed to fetch'));

    const result = await client.getPipelineState();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('NETWORK_ERROR');
      expect((result as ApiError).error.message).toContain('Failed to fetch');
    }
  });

  it('returns NETWORK_ERROR when fetch throws a generic Error', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockRejectedValueOnce(new Error('Connection refused'));

    const result = await client.getPipelineState();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('NETWORK_ERROR');
      expect((result as ApiError).error.message).toContain('Connection refused');
    }
  });

  it('returns TIMEOUT when fetch throws a DOMException AbortError', async () => {
    const client = createApiClient('my-project', { timeoutMs: 100 });
    const abortError = new DOMException('The operation was aborted', 'AbortError');
    fetchMock.mockRejectedValueOnce(abortError);

    const result = await client.getPipelineState();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('TIMEOUT');
      expect((result as ApiError).error.message).toContain('100ms');
    }
  });
});

// ---------------------------------------------------------------------------
// JSON envelope edge cases
// ---------------------------------------------------------------------------

describe('createApiClient — JSON envelope edge cases', () => {
  it('wraps raw JSON array (no ok key) from successful 200 response', async () => {
    const client = createApiClient('my-project');
    // Server returns raw array without { ok, data } envelope
    const rawArray = [{ id: 'step_1' }];
    fetchMock.mockResolvedValueOnce(mockResponse(200, rawArray));

    const result = await client.getPipelineSteps();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(Array.isArray(result.data)).toBe(true);
    }
  });

  it('wraps raw JSON object (no ok key) from successful 200 response', async () => {
    const client = createApiClient('my-project');
    const rawObject = { currentState: 'IDLE', currentEpicId: null };
    fetchMock.mockResolvedValueOnce(mockResponse(200, rawObject));

    const result = await client.getPipelineState();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toBeDefined();
    }
  });

  it('produces HTTP_500 code when 500 returns JSON without ok key', async () => {
    const client = createApiClient('my-project');
    const unexpectedJson = { error: 'crash', detail: 'stack trace' };
    fetchMock.mockResolvedValueOnce(mockResponse(500, unexpectedJson));

    const result = await client.getPipelineState();

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect((result as ApiError).error.code).toBe('HTTP_500');
    }
  });
});

// ---------------------------------------------------------------------------
// URL construction — baseUrl and projectId encoding
// ---------------------------------------------------------------------------

describe('createApiClient — URL construction', () => {
  it('uses default same-origin relative URL when no baseUrl provided', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: PIPELINE_STATE }),
    );

    await client.getPipelineState();

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('/api/p/my-project/pipeline');
  });

  it('prepends custom baseUrl to all requests', async () => {
    const client = createApiClient('my-project', {
      baseUrl: 'http://localhost:4200',
    });
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: PIPELINE_STATE }),
    );

    await client.getPipelineState();

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toBe('http://localhost:4200/api/p/my-project/pipeline');
  });

  it('URL-encodes the projectId in all request paths', async () => {
    const client = createApiClient('my project/v2', {
      baseUrl: 'http://localhost:4200',
    });
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: QUEUE_RESPONSE }),
    );

    await client.getQueue();

    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toContain('my%20project%2Fv2');
  });

  it('exposes the projectId on the client instance', () => {
    const client = createApiClient('test-proj');
    expect(client.projectId).toBe('test-proj');
  });

  it('builds correct URL for each of the 7 endpoint methods', async () => {
    const client = createApiClient('proj', { baseUrl: 'http://srv' });
    const okResponse = { ok: true, data: {} };

    const endpointMap: [() => Promise<unknown>, string][] = [
      [() => client.getPipelineState(), '/api/p/proj/pipeline'],
      [() => client.getPipelineSteps(), '/api/p/proj/pipeline/steps'],
      [() => client.getStageLog(), '/api/p/proj/pipeline/stage-log'],
      [() => client.getQueue(), '/api/p/proj/queue'],
      [() => client.getDecisions(), '/api/p/proj/decisions'],
      [() => client.getUsage(), '/api/p/proj/usage'],
      [() => client.getAuditHealth(), '/api/p/proj/audit'],
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
// Request format tests
// ---------------------------------------------------------------------------

describe('createApiClient — request format', () => {
  it('uses GET method for all requests', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: PIPELINE_STATE }),
    );

    await client.getPipelineState();

    const calledOptions = fetchMock.mock.calls[0][1] as RequestInit;
    expect(calledOptions.method).toBe('GET');
  });

  it('sets Accept: application/json header', async () => {
    const client = createApiClient('my-project');
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, { ok: true, data: PIPELINE_STATE }),
    );

    await client.getPipelineState();

    const calledOptions = fetchMock.mock.calls[0][1] as RequestInit;
    expect((calledOptions.headers as Record<string, string>)?.['Accept']).toBe('application/json');
  });
});
