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
  UsageResponse,
  AuditReportResponse,
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
  };
}
