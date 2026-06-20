/**
 * View-model assembly (EPIC E-047-3_7, Step 5).
 *
 * Pure, never-throw helpers that compose the cross-project read contract shapes
 * — {@link EpicSummary}, {@link ProjectDetail}, {@link EpicDetail}, and the
 * {@link RunSummary} / {@link MetricSet} sub-shapes — from the Phase-2
 * {@link ScannerCache} Tier-1 index plus on-demand {@link RunDetail} loads.
 *
 * Design rules (Phase-2 lesson — NEVER fabricate):
 *  - Counts come from the real index (run dirs, frontmatter), not guesses.
 *  - Absent data is `null` / `[]`, never a fabricated zero/score.
 *  - The latest run is selected via the index `started_at`/mtime ordering the
 *    scanner already applied (we re-derive only what the index lacks).
 *  - These helpers do NO disk writes and route every read through the cache.
 *
 * Module: src/services/view-assembly.ts
 */

import { join } from 'node:path';
import type {
  ActivityEvent,
  AuditSummary,
  EpicDetail,
  EpicSpec,
  EpicSummary,
  FsmState,
  MetricSet,
  Project,
  ProjectDetail,
  QueueEntry,
  RunDetail,
  RunStep,
  RunSummary,
} from '@aid/contract';
import type { AuditTrend, AuditTrendPoint } from '@aid/contract';
import type { IndexedEpic, IndexedProject, IndexedRun, ScannerCache } from './scanner-cache.js';
import { FsReader } from './fs-reader.js';
import { parseEpicSpec } from '../parsers/index.js';

// ===========================================================================
// Empty / conservative shapes (never fabricate)
// ===========================================================================

/** A conservative, type-valid empty {@link AuditSummary}. */
function emptyAudit(rawRelPath: string, warnings: string[] = []): AuditSummary {
  return {
    present: false,
    overallScore: null,
    scoreSource: null,
    blockingFindings: null,
    blockingFindingsSource: null,
    categories: [],
    topReasons: [],
    topRisks: [],
    countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 0 },
    autoFixableCount: 0,
    nextSteps: [],
    headlineCs: '',
    previousScoreHint: null,
    rawRelPath,
    warnings,
  };
}

/** An empty {@link AuditTrend} for the given scope. */
function emptyTrend(scope: AuditTrend['scope']): AuditTrend {
  return { scope, points: [], scoredPointCount: 0, delta: null };
}

// ===========================================================================
// EpicSummary
// ===========================================================================

/**
 * Build an {@link EpicSummary} from a project's Tier-1 EPIC entry. Run counts
 * come from the index run map; the "latest run" is the run with the most-recent
 * mtime (the cheap Tier-1 ordering key — `started_at` is a Tier-2 detail).
 * `runsCompleted` counts runs whose cheap state is `DONE`.
 */
export function buildEpicSummary(
  project: IndexedProject,
  epic: IndexedEpic,
): EpicSummary {
  const runs = [...epic.runs.values()];
  const runsTotal = runs.length;
  const runsCompleted = runs.filter((r) => r.state === 'DONE').length;

  const latest = pickLatestIndexedRun(runs);

  const fm = epic.frontmatter ?? {};
  const title = fm.title ?? epic.epicId;
  const status = fm.status ?? 'unknown';
  const planRef = fm.planRef ?? fm.planPath ?? null;

  const lastActivityAt = latestMtimeIso(runs);

  return {
    projectId: project.projectId,
    id: epic.epicId,
    title,
    status,
    planRef,
    runsTotal,
    runsCompleted,
    latestRun: latest
      ? {
          runId: latest.runId,
          state: latest.state ?? 'READY',
          format: latest.format,
          // started_at is a Tier-2 field; the cheap index carries only mtime,
          // so we surface the run-dir mtime as the best-effort start marker.
          startedAt: latest.mtimeMs !== null ? new Date(latest.mtimeMs).toISOString() : null,
        }
      : null,
    lastActivityAt,
  };
}

/** Pick the run with the most-recent mtime (null-safe). Returns null when empty. */
function pickLatestIndexedRun(runs: IndexedRun[]): IndexedRun | null {
  let best: IndexedRun | null = null;
  for (const r of runs) {
    if (best === null) {
      best = r;
      continue;
    }
    const rm = r.mtimeMs ?? -Infinity;
    const bm = best.mtimeMs ?? -Infinity;
    if (rm > bm) best = r;
  }
  return best;
}

/** ISO of the most-recent run-dir mtime across the EPIC, or null. */
function latestMtimeIso(runs: IndexedRun[]): string | null {
  let max: number | null = null;
  for (const r of runs) {
    if (r.mtimeMs !== null && (max === null || r.mtimeMs > max)) max = r.mtimeMs;
  }
  return max !== null ? new Date(max).toISOString() : null;
}

/** Build all EpicSummaries for a project, sorted active/running first then by id. */
export function buildEpicSummaries(project: IndexedProject): EpicSummary[] {
  const out: EpicSummary[] = [];
  for (const epic of project.epics.values()) {
    out.push(buildEpicSummary(project, epic));
  }
  out.sort(compareEpicSummary);
  return out;
}

/** Status sort priority — active/running EPICs first, then by id. */
const STATUS_PRIORITY: Record<string, number> = {
  active: 0,
  running: 0,
  in_progress: 1,
  ready: 2,
  draft: 3,
  completed: 4,
  archived: 5,
};

function statusWeight(status: string): number {
  return STATUS_PRIORITY[status.toLowerCase()] ?? 3;
}

function compareEpicSummary(a: EpicSummary, b: EpicSummary): number {
  const sw = statusWeight(a.status) - statusWeight(b.status);
  if (sw !== 0) return sw;
  return a.id.localeCompare(b.id);
}

// ===========================================================================
// ProjectDetail
// ===========================================================================

/**
 * Assemble a {@link ProjectDetail} for `projectId`: the base contract
 * {@link Project} (from `cache.listProjects()`) enriched with epics, queue,
 * recentActivity, and best-effort aggregate audit + project-scope audit trend.
 * Returns null when the project is not discovered (404 at the route layer).
 */
export async function buildProjectDetail(
  cache: ScannerCache,
  fs: FsReader,
  projectId: string,
): Promise<ProjectDetail | null> {
  const projects = await cache.listProjects();
  const base = projects.find((p) => p.id === projectId) ?? null;
  if (base === null) return null;

  const idx = await cache.getIndex();
  const indexed = idx.projects.get(projectId) ?? null;

  const epics = indexed ? buildEpicSummaries(indexed) : [];
  const queue = indexed ? await readQueue(fs, indexed.aidoPath) : [];
  const recentActivity = cache
    .getActivity()
    .filter((e) => e.projectId === projectId);

  return {
    ...base,
    epics,
    queue,
    recentActivity,
    // Aggregate audit is a later managerial phase; surface a type-valid empty
    // projection here (never a fabricated score) plus its trend.
    aggregateAudit: {
      ...emptyAudit('', ['aggregate audit not computed in MVP1 read path']),
      scoredEpicCount: 0,
      medianEpicId: null,
    },
    auditTrend: emptyTrend('project'),
  };
}

/**
 * Read `config/queue.yaml` into {@link QueueEntry}[] (camelCased). Never throws —
 * a missing/unreadable queue yields `[]`.
 */
async function readQueue(fs: FsReader, aidoPath: string): Promise<QueueEntry[]> {
  const queue = await fs.readYaml<{ queue?: unknown[] }>(
    join(aidoPath, 'config', 'queue.yaml'),
  );
  const rows = Array.isArray(queue?.queue) ? queue.queue : [];
  const out: QueueEntry[] = [];
  for (const r of rows) {
    if (typeof r !== 'object' || r === null) continue;
    const e = r as Record<string, unknown>;
    out.push({
      epicId: asString(e.epic_id ?? e.epicId) ?? '',
      path: asString(e.path) ?? '',
      priority: asString(e.priority) ?? 'medium',
      status: asString(e.status) ?? 'queued',
      addedAt: asString(e.added_at ?? e.addedAt) ?? '',
    });
  }
  return out;
}

// ===========================================================================
// EpicDetail
// ===========================================================================

/**
 * Assemble an {@link EpicDetail} for `(projectId, epicId)`. Loads the EPIC spec
 * (from `tasks/<id>.md` when present), the per-run summaries, the latest full
 * {@link RunDetail} (via the cache loader, which memoizes), derived metrics, and
 * a best-effort epic-scope audit trend (one point per run). Returns null when
 * the EPIC is unknown (404 at the route layer).
 */
export async function buildEpicDetail(
  cache: ScannerCache,
  fs: FsReader,
  projectId: string,
  epicId: string,
): Promise<EpicDetail | null> {
  const idx = await cache.getIndex();
  const indexed = idx.projects.get(projectId) ?? null;
  if (indexed === null) return null;

  const epic = indexed.epics.get(epicId) ?? null;
  if (epic === null) return null;

  const summary = buildEpicSummary(indexed, epic);
  const spec = await readEpicSpec(fs, epic.taskPath, epicId);

  // Per-run summaries from the cheap index; latest run gets a full RunDetail.
  const runs = [...epic.runs.values()];
  const latestIndexed = pickLatestIndexedRun(runs);
  const latest: RunDetail | null = latestIndexed
    ? await cache.getRunDetail(projectId, epicId, latestIndexed.runId)
    : null;

  const runSummaries = buildRunSummaries(runs);
  const metrics = buildMetrics(latest, runSummaries);
  const auditTrend = await buildEpicAuditTrend(cache, projectId, epicId, runs);

  return {
    ...summary,
    spec,
    runs: runSummaries,
    latest,
    metrics,
    explanations: [],
    auditTrend,
  };
}

/**
 * Read + parse the EPIC spec from `tasks/<id>.md`. When the task file is absent
 * (EPIC known only via evidence dirs), returns a conservative empty spec keyed
 * by epicId. Never throws.
 */
async function readEpicSpec(
  fs: FsReader,
  taskPath: string | null,
  epicId: string,
): Promise<EpicSpec> {
  if (taskPath !== null) {
    const text = await fs.readText(taskPath);
    if (text !== null && text.trim().length > 0) {
      const parsed = parseEpicSpec(text, taskPath);
      if (parsed.data !== null) return parsed.data;
    }
  }
  return emptyEpicSpec(epicId);
}

/** A type-valid empty {@link EpicSpec} for an EPIC with no readable task file. */
function emptyEpicSpec(epicId: string): EpicSpec {
  return {
    epicId,
    status: '',
    planRef: '',
    planEpicsTotal: 0,
    runsTotal: 0,
    runsCompleted: 0,
    title: epicId,
    context: '',
    goal: '',
    scope: { allowedPaths: [], forbiddenPaths: [], rawMarkdown: '' },
    constraints: '',
    dodGates: [],
    acceptanceCriteria: [],
    steps: [],
  };
}

/** Build cheap {@link RunSummary}[] from the Tier-1 run index (no Tier-2 load). */
function buildRunSummaries(runs: IndexedRun[]): RunSummary[] {
  const out: RunSummary[] = runs.map((r) => ({
    runId: r.runId,
    format: r.format,
    state: r.state ?? 'READY',
    startedAt: r.mtimeMs !== null ? new Date(r.mtimeMs).toISOString() : null,
    finishedAt: null,
    durationS: null,
    overallGate: null,
    complianceOverall: null,
  }));
  // Newest first by mtime-derived startedAt (stable).
  out.sort((a, b) => (b.startedAt ?? '').localeCompare(a.startedAt ?? ''));
  return out;
}

/**
 * Derive a best-effort {@link MetricSet} from the latest full RunDetail plus the
 * run summaries. Step timings come from the RunDetail (file-mtime derived);
 * everything unmeasurable stays null with a warning rather than a fake zero.
 */
function buildMetrics(latest: RunDetail | null, runs: RunSummary[]): MetricSet {
  const warnings: string[] = [];
  const stepDurationsS: (number | null)[] = latest
    ? latest.steps.map((s: RunStep) => s.durationS)
    : [];
  const measured = stepDurationsS.filter((d): d is number => d !== null);
  const avgStepDurationS =
    measured.length > 0
      ? Math.round(measured.reduce((a, b) => a + b, 0) / measured.length)
      : null;

  let longestStep: MetricSet['longestStep'] = null;
  if (latest) {
    for (const s of latest.steps) {
      if (s.durationS === null) continue;
      if (longestStep === null || s.durationS > longestStep.durationS) {
        longestStep = { id: s.id, durationS: s.durationS };
      }
    }
  }

  const epicWallTimeS =
    measured.length > 0 ? measured.reduce((a, b) => a + b, 0) : null;
  if (latest === null) warnings.push('no latest run — metrics unavailable');

  return {
    epicWallTimeS,
    runCount: runs.length,
    stepDurationsS,
    avgStepDurationS,
    longestStep,
    stepTimingSource: latest && measured.length > 0 ? 'mtime' : null,
    gateRuns: latest ? latest.gates.length : 0,
    gateRetries: latest ? latest.gateRetries : 0,
    checkpointRepeats: {
      CP1: latest?.checkpoints.find((c) => c.id === 'CP1')?.repeatCount ?? null,
      CP2: latest?.checkpoints.find((c) => c.id === 'CP2')?.repeatCount ?? null,
      CP3: latest?.checkpoints.find((c) => c.id === 'CP3')?.repeatCount ?? null,
      CP4: latest?.checkpoints.find((c) => c.id === 'CP4')?.repeatCount ?? null,
      CP5: latest?.checkpoints.find((c) => c.id === 'CP5')?.repeatCount ?? null,
      CP6: latest?.checkpoints.find((c) => c.id === 'CP6')?.repeatCount ?? null,
    },
    escalations: latest ? latest.escalationCount : 0,
    timeBy: [],
    partial: latest === null,
    warnings,
  };
}

/**
 * Build an epic-scope {@link AuditTrend}: one point per run, scored from that
 * run's RunDetail audit summary (loaded via the memoizing cache). Gaps stay
 * `score:null` (never interpolated). Chronological by the run's startedAt.
 */
async function buildEpicAuditTrend(
  cache: ScannerCache,
  projectId: string,
  epicId: string,
  runs: IndexedRun[],
): Promise<AuditTrend> {
  const points: AuditTrendPoint[] = [];
  for (const r of runs) {
    const detail = await cache.getRunDetail(projectId, epicId, r.runId);
    points.push({
      runId: r.runId,
      epicId,
      startedAt: detail.startedAt,
      score: detail.audit.overallScore,
      blockingFindings: detail.audit.blockingFindings,
    });
  }
  points.sort((a, b) => (a.startedAt ?? '').localeCompare(b.startedAt ?? ''));

  const scored = points.filter((p) => p.score !== null);
  const delta =
    scored.length >= 2
      ? (scored[scored.length - 1].score as number) - (scored[0].score as number)
      : null;

  return {
    scope: 'epic',
    points,
    scoredPointCount: scored.length,
    delta,
  };
}

// ===========================================================================
// Project list sort (active/running first)
// ===========================================================================

/** Compare two contract {@link Project}s — running/active first, then by id. */
export function compareProject(a: Project, b: Project): number {
  const aw = projectActivityWeight(a);
  const bw = projectActivityWeight(b);
  if (aw !== bw) return aw - bw;
  return a.id.localeCompare(b.id);
}

/**
 * Lower weight sorts first. A project with an `activeRun` in a live FSM state
 * (EXECUTE / GATES / READY / ESCALATION) is "running" → weight 0; any other
 * project with an activeRun → 1; the rest → 2.
 */
function projectActivityWeight(p: Project): number {
  if (p.activeRun === null) return 2;
  const live: ReadonlySet<FsmState> = new Set<FsmState>([
    'READY',
    'EXECUTE',
    'GATES',
    'ESCALATION',
  ]);
  return live.has(p.activeRun.state) ? 0 : 1;
}

// ===========================================================================
// recentActivity / queue helpers
// ===========================================================================

/** Project IDs that returned partial data (for the response `meta`). */
export function partialProjectIds(projects: Project[]): string[] {
  return projects.filter((p) => p.partial).map((p) => p.id);
}

/** Filter merged activity to a single project (used by ProjectDetail). */
export function activityForProject(
  events: ActivityEvent[],
  projectId: string,
): ActivityEvent[] {
  return events.filter((e) => e.projectId === projectId);
}

// ===========================================================================
// Local coercion (never throw)
// ===========================================================================

function asString(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}
