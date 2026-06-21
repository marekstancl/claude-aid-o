/**
 * Typed fetch layer for the AID Cockpit, one helper per aid-server endpoint.
 *
 * Every helper unwraps the server envelope `{ ok: true, data } | { ok: false, error }`
 * (see aid-server `api/middleware.ts`) and returns the bare `data` typed against
 * the shared `@aid/contract` shapes. On a non-OK envelope OR a transport/parse
 * failure it throws an {@link ApiError} carrying `code` + `message`, so callers
 * (react-query) get a normal rejected promise to surface in `error`.
 *
 * URL policy (read-only monitoring PWA, served same-origin behind the server):
 *   - ALL paths are RELATIVE (`/api/...`). The client never hardcodes a host or
 *     the dev server port — the browser resolves against `location.origin`, so
 *     the same bundle works behind a tunnel, a reverse proxy, or localhost.
 */

import type {
  Project,
  ProjectDetail,
  Brief,
  EpicDetail,
  EpicSummary,
  ComplianceView,
  ActivityEvent,
  BacklogItem,
  PlanSummary,
  PlanDetail,
  PlanOutcomeAnalytics,
  PlanOutcome,
  LessonsView,
  AuditSummary,
  AuditTrend,
  DictionaryEntry,
} from '@aid/contract';

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------

/**
 * Thrown by every api helper on a failed request. `code` is the server's
 * machine-readable error code (e.g. `NOT_FOUND`, `AMBIGUOUS_PLAN_NUMBER`) or a
 * synthetic transport code (`NETWORK_ERROR`, `INVALID_RESPONSE`, `HTTP_<status>`).
 */
export class ApiError extends Error {
  readonly code: string;
  readonly details?: unknown;

  constructor(code: string, message: string, details?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.details = details;
  }
}

// ---------------------------------------------------------------------------
// Envelope types (mirror aid-server api/middleware.ts)
// ---------------------------------------------------------------------------

interface ApiOk<T> {
  ok: true;
  data: T;
  meta?: unknown;
}

interface ApiFail {
  ok: false;
  error: { code: string; message: string; details?: unknown };
}

type ApiEnvelope<T> = ApiOk<T> | ApiFail;

// ---------------------------------------------------------------------------
// Core fetch — unwrap envelope or throw ApiError
// ---------------------------------------------------------------------------

/**
 * GET a relative API path and unwrap the `{ ok, data }` envelope.
 * Throws {@link ApiError} on transport failure, non-JSON body, or `ok:false`.
 */
async function apiGet<T>(path: string): Promise<T> {
  let response: Response;
  try {
    response = await fetch(path, { headers: { Accept: 'application/json' } });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    throw new ApiError('NETWORK_ERROR', `Network error for ${path}: ${message}`);
  }

  let body: unknown;
  try {
    body = await response.json();
  } catch {
    throw new ApiError(
      response.ok ? 'INVALID_RESPONSE' : `HTTP_${response.status}`,
      `Expected JSON from ${path} but received a non-JSON body (HTTP ${response.status})`,
    );
  }

  if (typeof body === 'object' && body !== null && 'ok' in body) {
    const env = body as ApiEnvelope<T>;
    if (env.ok === true) return env.data;
    const fail = env as ApiFail;
    throw new ApiError(fail.error.code, fail.error.message, fail.error.details);
  }

  throw new ApiError(
    `HTTP_${response.status}`,
    `Unexpected response shape from ${path}`,
    body,
  );
}

/** Build a `?k=v` query string from defined values; empty → ''. */
function qs(params: Record<string, string | undefined>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== '') search.set(key, value);
  }
  const str = search.toString();
  return str ? `?${str}` : '';
}

/** Encode a single path segment safely. */
const seg = (s: string): string => encodeURIComponent(s);

// ---------------------------------------------------------------------------
// Endpoint helpers — one per aid-server route (all GET, all read-only)
// ---------------------------------------------------------------------------

/** GET /api/projects → all discovered projects. */
export function getProjects(): Promise<Project[]> {
  return apiGet<Project[]>('/api/projects');
}

/** GET /api/projects/:projectId → full ProjectDetail (epics + queue + recentActivity + aggregateAudit + auditTrend). */
export function getProjectDetail(project: string): Promise<ProjectDetail> {
  return apiGet<ProjectDetail>(`/api/projects/${seg(project)}`);
}

/** GET /api/projects/:projectId/epics → EpicSummary[] for one project. */
export function getEpics(project: string): Promise<EpicSummary[]> {
  return apiGet<EpicSummary[]>(`/api/projects/${seg(project)}/epics`);
}

/**
 * GET /api/brief[/:project][?since=] → managerial Brief.
 * `scope` selects the route: infra (no project), project, or plan.
 */
export function getBrief(
  scope: { project?: string; plan?: string },
  since?: string,
): Promise<Brief> {
  const query = qs({ since });
  if (scope.project && scope.plan) {
    return apiGet<Brief>(`/api/brief/${seg(scope.project)}/${seg(scope.plan)}${query}`);
  }
  if (scope.project) {
    return apiGet<Brief>(`/api/brief/${seg(scope.project)}${query}`);
  }
  return apiGet<Brief>(`/api/brief${query}`);
}

/** GET /api/epics/:project/:epic → full EpicDetail. */
export function getEpic(project: string, epic: string): Promise<EpicDetail> {
  return apiGet<EpicDetail>(`/api/epics/${seg(project)}/${seg(epic)}`);
}

/** GET /api/compliance/:project → project-scoped ComplianceView. */
export function getCompliance(project: string): Promise<ComplianceView> {
  return apiGet<ComplianceView>(`/api/compliance/${seg(project)}`);
}

/** GET /api/activity?project=&topic=&limit= → merged activity feed (newest first). */
export function getActivity(params: {
  project?: string;
  topic?: string;
  limit?: number;
} = {}): Promise<ActivityEvent[]> {
  const query = qs({
    project: params.project,
    topic: params.topic,
    limit: params.limit !== undefined ? String(params.limit) : undefined,
  });
  return apiGet<ActivityEvent[]>(`/api/activity${query}`);
}

/** GET /api/backlog?project= → project backlog items. */
export function getBacklog(project: string): Promise<BacklogItem[]> {
  return apiGet<BacklogItem[]>(`/api/backlog${qs({ project })}`);
}

/** GET /api/plans/:project → plan summaries for a project. */
export function getPlans(project: string): Promise<PlanSummary[]> {
  return apiGet<PlanSummary[]>(`/api/plans/${seg(project)}`);
}

/**
 * GET /api/plans/:project/:planId → full PlanDetail.
 * `planId` MUST be the plan STEM (e.g. "P046-foo"). A bare ambiguous plan
 * NUMBER resolves server-side to HTTP 409 AMBIGUOUS_PLAN_NUMBER (thrown here as
 * an ApiError with that code).
 */
export function getPlanDetail(project: string, planId: string): Promise<PlanDetail> {
  return apiGet<PlanDetail>(`/api/plans/${seg(project)}/${seg(planId)}`);
}

/** GET /api/analytics/plans?project=&outcome=&since= → cross-project outcomes. */
export function getPlanOutcomes(
  params: { project?: string; outcome?: PlanOutcome; since?: string } = {},
): Promise<PlanOutcomeAnalytics> {
  const query = qs({
    project: params.project,
    outcome: params.outcome,
    since: params.since,
  });
  return apiGet<PlanOutcomeAnalytics>(`/api/analytics/plans${query}`);
}

/** GET /api/lessons?project=&plan= → lessons-per-plan (or project scope when no plan). */
export function getLessons(project: string, plan?: string): Promise<LessonsView> {
  return apiGet<LessonsView>(`/api/lessons${qs({ project, plan })}`);
}

/** GET /api/audit-summary/:project → project-scope aggregate audit summary. */
export function getAuditSummary(
  project: string,
): Promise<AuditSummary & { scoredEpicCount: number; medianEpicId: string | null }> {
  return apiGet<AuditSummary & { scoredEpicCount: number; medianEpicId: string | null }>(
    `/api/audit-summary/${seg(project)}`,
  );
}

/**
 * GET /api/audit-trend/:project[/:epic | /plan/:planId] → AuditTrend.
 * Scope is chosen by which of `epic` / `plan` is supplied (project-scope when neither).
 */
export function getAuditTrend(
  project: string,
  scope: { epic?: string; plan?: string } = {},
): Promise<AuditTrend> {
  if (scope.plan) {
    return apiGet<AuditTrend>(`/api/audit-trend/${seg(project)}/plan/${seg(scope.plan)}`);
  }
  if (scope.epic) {
    return apiGet<AuditTrend>(`/api/audit-trend/${seg(project)}/${seg(scope.epic)}`);
  }
  return apiGet<AuditTrend>(`/api/audit-trend/${seg(project)}`);
}

/** GET /api/explanations?lang=cs → dictionary source entries (un-interpolated). */
export function getExplanations(lang = 'cs'): Promise<Record<string, DictionaryEntry>> {
  return apiGet<Record<string, DictionaryEntry>>(`/api/explanations${qs({ lang })}`);
}

/**
 * GET /api/epics/:projectId/:epicId/runs/:runId/file?name=<name> → parsed artifact content.
 *
 * Fetches a run-scoped artifact (audit report, evidence file, etc.) from the hardened
 * file endpoint. The `name` must be an allow-listed artifact name per §7.4.1.
 *
 * @param projectId — the project ID (will be encoded)
 * @param epicId — the EPIC ID (will be encoded)
 * @param runId — the run ID (will be encoded)
 * @param name — the allow-listed artifact name (e.g. 'audit-report.md', 'reporter/foo.txt')
 * @returns Promise resolving to `{ format, content }` where `content` is the parsed file
 * @throws ApiError if the name is not allow-listed, not found, or fetch fails
 */
export function getRunFile(
  projectId: string,
  epicId: string,
  runId: string,
  name: string,
): Promise<{ format: string; content: string }> {
  const path = `/api/epics/${seg(projectId)}/${seg(epicId)}/runs/${seg(runId)}/file${qs({ name })}`;
  return apiGet<{ format: string; content: string }>(path);
}
