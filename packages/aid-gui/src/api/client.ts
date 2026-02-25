/**
 * Typed API client for the AID Dashboard backend.
 *
 * Uses native `fetch` -- no external HTTP libraries. All methods return
 * `ApiResult<T>` which is a discriminated union of `ApiResponse<T>` (success)
 * and `ApiError` (failure). Callers narrow on the `ok` field.
 *
 * Error handling:
 *   - Network errors (DNS, connection refused, timeout) -> ApiError with
 *     code "NETWORK_ERROR"
 *   - Non-JSON responses -> ApiError with code "INVALID_RESPONSE"
 *   - Server 4xx/5xx with JSON error body -> returned as-is (ApiError)
 *   - Server 4xx/5xx with non-JSON body -> ApiError with code "HTTP_{status}"
 *
 * @example
 * ```ts
 * const client = createApiClient('my-project');
 * const result = await client.getPipelineState();
 * if (result.ok) {
 *   console.log(result.data.currentState);
 * } else {
 *   console.error(result.error.message);
 * }
 * ```
 */

import type {
  ApiResult,
  ApiError,
  PipelineStateResponse,
  PipelineStepsResponse,
  StageLogEntryResponse,
  QueueResponse,
  DecisionsResponse,
  PendingDecisionsResponse,
  DecisionWriteRequest,
  DecisionEntry,
  UsageResponse,
  AuditReportResponse,
  EvidenceEpicEntry,
  EvidenceFileResponse,
  StoredIdea,
  IdeaCreateRequest,
  IdeaUpdateRequest,
  ScheduleConfig,
  ScheduleStatusResponse,
  QueueScheduleEntry,
  KnowledgeItem,
} from '../types/api';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/**
 * Configuration options for the API client.
 */
export interface ApiClientConfig {
  /**
   * Base URL for the API. Defaults to '' (same-origin, relative paths).
   * Set to 'http://localhost:4200' for development against a remote server.
   */
  baseUrl?: string;

  /**
   * Default timeout for requests in milliseconds. Defaults to 15000 (15s).
   */
  timeoutMs?: number;
}

const DEFAULT_CONFIG: Required<ApiClientConfig> = {
  baseUrl: '',
  timeoutMs: 15_000,
};

// ---------------------------------------------------------------------------
// Error factory
// ---------------------------------------------------------------------------

function makeApiError(code: string, message: string, details?: unknown): ApiError {
  return {
    ok: false,
    error: { code, message, ...(details !== undefined ? { details } : {}) },
  };
}

// ---------------------------------------------------------------------------
// Core fetch wrapper
// ---------------------------------------------------------------------------

async function typedFetch<T>(
  url: string,
  timeoutMs: number,
): Promise<ApiResult<T>> {
  let response: Response;

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

    response = await fetch(url, {
      method: 'GET',
      headers: { 'Accept': 'application/json' },
      signal: controller.signal,
    });

    clearTimeout(timeoutId);
  } catch (err: unknown) {
    // AbortController timeout or network failure
    if (err instanceof DOMException && err.name === 'AbortError') {
      return makeApiError(
        'TIMEOUT',
        `Request timed out after ${timeoutMs}ms: ${url}`,
      );
    }
    const message = err instanceof Error ? err.message : String(err);
    return makeApiError('NETWORK_ERROR', `Network error: ${message}`);
  }

  // Try to parse JSON body
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    // Non-JSON response body
    if (!response.ok) {
      return makeApiError(
        `HTTP_${response.status}`,
        `Server returned ${response.status} ${response.statusText} with non-JSON body`,
      );
    }
    return makeApiError(
      'INVALID_RESPONSE',
      `Expected JSON response from ${url} but received ${response.headers.get('content-type') ?? 'unknown content type'}`,
    );
  }

  // The server always returns { ok: true, data: T } or { ok: false, error: {...} }
  // Validate the shape minimally and return
  if (
    typeof body === 'object' &&
    body !== null &&
    'ok' in body
  ) {
    // Trust the discriminant -- if ok is true, it has data; if false, it has error
    return body as ApiResult<T>;
  }

  // If the server returned JSON but not in our envelope, wrap it
  if (response.ok) {
    // Some endpoints might return raw data without the envelope during development.
    // Wrap it in the envelope shape so callers always get a consistent type.
    return { ok: true, data: body as T };
  }

  return makeApiError(
    `HTTP_${response.status}`,
    `Server returned ${response.status} with unexpected JSON shape`,
    body,
  );
}

// ---------------------------------------------------------------------------
// Core request wrapper (supports all HTTP methods)
// ---------------------------------------------------------------------------

async function typedRequest<T>(
  url: string,
  timeoutMs: number,
  method: string,
  body?: unknown,
): Promise<ApiResult<T>> {
  let response: Response;

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

    const init: RequestInit = {
      method,
      headers: {
        'Accept': 'application/json',
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      },
      signal: controller.signal,
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    };

    response = await fetch(url, init);
    clearTimeout(timeoutId);
  } catch (err: unknown) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      return makeApiError('TIMEOUT', `Request timed out after ${timeoutMs}ms: ${url}`);
    }
    const message = err instanceof Error ? err.message : String(err);
    return makeApiError('NETWORK_ERROR', `Network error: ${message}`);
  }

  let responseBody: unknown;
  try {
    responseBody = await response.json();
  } catch {
    if (!response.ok) {
      return makeApiError(
        `HTTP_${response.status}`,
        `Server returned ${response.status} ${response.statusText} with non-JSON body`,
      );
    }
    return makeApiError(
      'INVALID_RESPONSE',
      `Expected JSON response from ${url} but received ${response.headers.get('content-type') ?? 'unknown content type'}`,
    );
  }

  if (typeof responseBody === 'object' && responseBody !== null && 'ok' in responseBody) {
    return responseBody as ApiResult<T>;
  }

  if (response.ok) {
    return { ok: true, data: responseBody as T };
  }

  return makeApiError(`HTTP_${response.status}`, `Server returned ${response.status} with unexpected JSON shape`, responseBody);
}

// ---------------------------------------------------------------------------
// API client interface
// ---------------------------------------------------------------------------

/**
 * Typed API client bound to a specific project.
 */
export interface ApiClient {
  /** The project ID this client is bound to. */
  readonly projectId: string;

  /** GET /api/p/:projectId/pipeline */
  getPipelineState(): Promise<ApiResult<PipelineStateResponse>>;

  /** GET /api/p/:projectId/pipeline/steps */
  getPipelineSteps(): Promise<ApiResult<PipelineStepsResponse>>;

  /** GET /api/p/:projectId/pipeline/stage-log */
  getStageLog(): Promise<ApiResult<StageLogEntryResponse[]>>;

  /** GET /api/p/:projectId/queue */
  getQueue(): Promise<ApiResult<QueueResponse>>;

  /** GET /api/p/:projectId/decisions */
  getDecisions(): Promise<ApiResult<DecisionsResponse>>;

  /** GET /api/p/:projectId/usage */
  getUsage(): Promise<ApiResult<UsageResponse>>;

  /** GET /api/p/:projectId/audit */
  getAuditHealth(): Promise<ApiResult<AuditReportResponse>>;

  // ----- Decisions -----

  /** GET /api/p/:projectId/decisions/pending */
  getDecisionsPending(): Promise<ApiResult<PendingDecisionsResponse>>;

  /** POST /api/p/:projectId/decisions */
  postDecision(request: DecisionWriteRequest): Promise<ApiResult<DecisionEntry>>;

  // ----- Evidence -----

  /** GET /api/p/:projectId/evidence */
  getEvidence(): Promise<ApiResult<EvidenceEpicEntry[]>>;

  /** GET /api/p/:projectId/evidence/:epicId/:runId/files/:filePath */
  getEvidenceFile(epicId: string, runId: string, filePath: string): Promise<ApiResult<EvidenceFileResponse>>;

  // ----- Ideas -----

  /** GET /api/p/:projectId/ideas */
  getIdeas(): Promise<ApiResult<StoredIdea[]>>;

  /** POST /api/p/:projectId/ideas */
  createIdea(request: IdeaCreateRequest): Promise<ApiResult<StoredIdea>>;

  /** PUT /api/p/:projectId/ideas/:ideaId */
  updateIdea(ideaId: string, request: IdeaUpdateRequest): Promise<ApiResult<StoredIdea>>;

  /** DELETE /api/p/:projectId/ideas/:ideaId */
  deleteIdea(ideaId: string): Promise<ApiResult<{ deleted: boolean }>>;

  // ----- Queue Schedule -----

  /** GET /api/p/:projectId/queue/schedule */
  getQueueSchedule(): Promise<ApiResult<ScheduleConfig>>;

  /** PUT /api/p/:projectId/queue/schedule */
  updateQueueSchedule(config: Partial<ScheduleConfig>): Promise<ApiResult<ScheduleConfig>>;

  /** PUT /api/p/:projectId/queue/:epicId */
  updateQueueEntry(epicId: string, updates: Partial<QueueScheduleEntry>): Promise<ApiResult<QueueScheduleEntry>>;

  /** GET /api/p/:projectId/queue/schedule/status */
  getQueueScheduleStatus(): Promise<ApiResult<ScheduleStatusResponse>>;

  // ----- Knowledge -----

  /** GET /api/p/:projectId/knowledge */
  getKnowledge(): Promise<ApiResult<KnowledgeItem[]>>;
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/**
 * Create a typed API client bound to the given project.
 *
 * @param projectId - The project identifier used in URL paths.
 * @param config    - Optional configuration overrides.
 * @returns An `ApiClient` instance with methods for each endpoint.
 *
 * @example
 * ```ts
 * const client = createApiClient('default');
 * const pipeline = await client.getPipelineState();
 * ```
 */
export function createApiClient(
  projectId: string,
  config?: ApiClientConfig,
): ApiClient {
  const { baseUrl, timeoutMs } = { ...DEFAULT_CONFIG, ...config };
  const base = `${baseUrl}/api/p/${encodeURIComponent(projectId)}`;

  return {
    projectId,

    getPipelineState: () =>
      typedFetch<PipelineStateResponse>(`${base}/pipeline`, timeoutMs),

    getPipelineSteps: () =>
      typedFetch<PipelineStepsResponse>(`${base}/pipeline/steps`, timeoutMs),

    getStageLog: () =>
      typedFetch<StageLogEntryResponse[]>(`${base}/pipeline/stage-log`, timeoutMs),

    getQueue: () =>
      typedFetch<QueueResponse>(`${base}/queue`, timeoutMs),

    getDecisions: () =>
      typedFetch<DecisionsResponse>(`${base}/decisions`, timeoutMs),

    getUsage: () =>
      typedFetch<UsageResponse>(`${base}/usage`, timeoutMs),

    getAuditHealth: () =>
      typedFetch<AuditReportResponse>(`${base}/audit`, timeoutMs),

    // ----- Decisions -----

    getDecisionsPending: () =>
      typedFetch<PendingDecisionsResponse>(`${base}/decisions/pending`, timeoutMs),

    postDecision: (request: DecisionWriteRequest) =>
      typedRequest<DecisionEntry>(`${base}/decisions`, timeoutMs, 'POST', request),

    // ----- Evidence -----

    getEvidence: () =>
      typedFetch<EvidenceEpicEntry[]>(`${base}/evidence`, timeoutMs),

    getEvidenceFile: (epicId: string, runId: string, filePath: string) =>
      typedFetch<EvidenceFileResponse>(
        `${base}/evidence/${encodeURIComponent(epicId)}/${encodeURIComponent(runId)}/files/${filePath}`,
        timeoutMs,
      ),

    // ----- Ideas -----

    getIdeas: () =>
      typedFetch<StoredIdea[]>(`${base}/ideas`, timeoutMs),

    createIdea: (request: IdeaCreateRequest) =>
      typedRequest<StoredIdea>(`${base}/ideas`, timeoutMs, 'POST', request),

    updateIdea: (ideaId: string, request: IdeaUpdateRequest) =>
      typedRequest<StoredIdea>(`${base}/ideas/${encodeURIComponent(ideaId)}`, timeoutMs, 'PUT', request),

    deleteIdea: (ideaId: string) =>
      typedRequest<{ deleted: boolean }>(`${base}/ideas/${encodeURIComponent(ideaId)}`, timeoutMs, 'DELETE'),

    // ----- Queue Schedule -----

    getQueueSchedule: () =>
      typedFetch<ScheduleConfig>(`${base}/queue/schedule`, timeoutMs),

    updateQueueSchedule: (config: Partial<ScheduleConfig>) =>
      typedRequest<ScheduleConfig>(`${base}/queue/schedule`, timeoutMs, 'PUT', config),

    updateQueueEntry: (epicId: string, updates: Partial<QueueScheduleEntry>) =>
      typedRequest<QueueScheduleEntry>(`${base}/queue/${encodeURIComponent(epicId)}`, timeoutMs, 'PUT', updates),

    getQueueScheduleStatus: () =>
      typedFetch<ScheduleStatusResponse>(`${base}/queue/schedule/status`, timeoutMs),

    // ----- Knowledge -----

    getKnowledge: () =>
      typedFetch<KnowledgeItem[]>(`${base}/knowledge`, timeoutMs),
  };
}
