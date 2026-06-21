/**
 * `AuditTrend` read routes (EPIC E-047-4_7, Step 6) — spec §7.4, §13.5.4.
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api`, BEFORE the `/api/*`
 * catch-all (the bootstrap appends this router in src/index.ts). Three scopes,
 * one pure projection ({@link buildAuditTrend}):
 *
 *   - `GET /api/audit-trend/:projectId`               → scope `'project'`
 *       one point per AUDITED EPIC (its latest run that has an audit-report.md).
 *   - `GET /api/audit-trend/:projectId/:epicId`       → scope `'epic'`
 *       one point per RUN of the EPIC that has an audit-report.md (§13.5.4).
 *   - `GET /api/audit-trend/:projectId/plan/:planId`  → scope `'plan'`
 *       one point per member EPIC of the plan (latest audited run, §5.4).
 *
 * The route does the I/O (loads per-run `RunDetail` from the never-throw scanner
 * cache, whose `RunDetail.audit` is the per-run {@link AuditSummary} and
 * `RunDetail.startedAt` the run `started_at`); the ordering / gap / delta logic is
 * the pure {@link buildAuditTrend}. Ordering key is run `started_at` — NOT
 * lexicographic run-id, NOT report mtime; when `started_at` is unparseable for a
 * run, the point falls back to the run-dir mtime (still placed, never dropped).
 *
 * The server writes NOTHING (read-only; the §7.6 grep test stays green).
 *
 * Module: src/routes/audit-trend.ts
 */

import { Router } from 'express';
import type { AuditTrendPoint, RunDetail } from '@aid/contract';
import type {
  IndexedEpic,
  IndexedProject,
  IndexedRun,
  ScannerCache,
} from '../services/scanner-cache.js';
import { pickLatestIndexedRun } from '../services/view-assembly.js';
import { sendOk, send404, send400 } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import { buildAuditTrend } from '../audit/build-audit-trend.js';
import { resolvePlanMembers } from './brief.js';

/**
 * Build one trend point from a run's `RunDetail`. The score is taken from the
 * per-run {@link RunDetail.audit} (`overallScore`, null = a real gap). `startedAt`
 * prefers the run `started_at`; when that is null/unparseable it falls back to the
 * run-dir mtime so the point is still PLACED (never dropped, §13.5.4) — the
 * warning about the fallback lives on the audit summary itself.
 */
function pointFromRun(detail: RunDetail, indexedRun: IndexedRun | null): AuditTrendPoint {
  const startedAt =
    detail.startedAt ??
    (indexedRun?.mtimeMs != null ? new Date(indexedRun.mtimeMs).toISOString() : null);
  return {
    runId: detail.runId,
    epicId: detail.epicId,
    startedAt,
    score: detail.audit.overallScore,
    blockingFindings: detail.audit.blockingFindings,
  };
}

/**
 * Assemble one trend point per RUN of an EPIC that HAS an audit-report.md
 * (EPIC scope, §13.5.4). A run without an audit-report.md (`audit.present:false`)
 * contributes no point — distinct from a present-but-score-less run, which IS
 * kept as a `score:null` gap.
 */
async function epicRunPoints(
  scanner: ScannerCache,
  indexed: IndexedProject,
  epic: IndexedEpic,
): Promise<AuditTrendPoint[]> {
  const points: AuditTrendPoint[] = [];
  for (const run of epic.runs.values()) {
    const detail = await scanner.getRunDetail(indexed.projectId, epic.epicId, run.runId);
    if (!detail.audit.present) continue; // no audit-report.md for this run
    points.push(pointFromRun(detail, run));
  }
  return points;
}

/**
 * Assemble one trend point per AUDITED EPIC (project / plan scope): the EPIC's
 * latest run (shared selector) — but only when that latest run HAS an
 * audit-report.md. An EPIC whose latest run is not audited contributes no point
 * (§13.5.4: one point per audited EPIC). Returns null for such an EPIC.
 */
async function latestAuditedEpicPoint(
  scanner: ScannerCache,
  indexed: IndexedProject,
  epic: IndexedEpic,
): Promise<AuditTrendPoint | null> {
  const latest = pickLatestIndexedRun([...epic.runs.values()]);
  if (latest === null) return null;
  const detail = await scanner.getRunDetail(indexed.projectId, epic.epicId, latest.runId);
  if (!detail.audit.present) return null;
  return pointFromRun(detail, latest);
}

/**
 * Build the READ-ONLY audit-trend router backed by the {@link ScannerCache}.
 * GET only — no mutation endpoints exist on this surface. NOTE: the `/plan/`
 * route is registered BEFORE the bare `/:projectId/:epicId` route so the literal
 * `plan` segment is not captured as an `:epicId`.
 */
export function auditTrendRoutes(scanner: ScannerCache): Router {
  const router = Router();

  // -------------------------------------------------------------------------
  // GET /audit-trend/:projectId/plan/:planId — PLAN scope. One point per member
  // EPIC of the plan (latest audited run). Registered first so `plan` is not
  // mistaken for an `:epicId` by the route below.
  // -------------------------------------------------------------------------
  router.get('/audit-trend/:projectId/plan/:planId', async (req, res) => {
    const { projectId, planId } = req.params;
    if (!isValidPathComponent(projectId) || !isValidPathComponent(planId)) {
      send400(res, 'Invalid projectId/planId path component');
      return;
    }

    const idx = await scanner.getIndex();
    const indexed = idx.projects.get(projectId) ?? null;
    if (indexed === null) {
      send404(res, `Project "${projectId}"`);
      return;
    }

    const memberEpicIds = resolvePlanMembers(indexed, planId);
    const points: AuditTrendPoint[] = [];
    for (const epicId of memberEpicIds) {
      const epic = indexed.epics.get(epicId);
      if (!epic) continue;
      const p = await latestAuditedEpicPoint(scanner, indexed, epic);
      if (p) points.push(p);
    }

    sendOk(res, buildAuditTrend(points, 'plan'));
  });

  // -------------------------------------------------------------------------
  // GET /audit-trend/:projectId/:epicId — EPIC scope. One point per audited RUN.
  // -------------------------------------------------------------------------
  router.get('/audit-trend/:projectId/:epicId', async (req, res) => {
    const { projectId, epicId } = req.params;
    if (!isValidPathComponent(projectId) || !isValidPathComponent(epicId)) {
      send400(res, 'Invalid projectId/epicId path component');
      return;
    }

    const idx = await scanner.getIndex();
    const indexed = idx.projects.get(projectId) ?? null;
    if (indexed === null) {
      send404(res, `Project "${projectId}"`);
      return;
    }
    const epic = indexed.epics.get(epicId) ?? null;
    if (epic === null) {
      send404(res, `EPIC "${epicId}"`);
      return;
    }

    const points = await epicRunPoints(scanner, indexed, epic);
    sendOk(res, buildAuditTrend(points, 'epic'));
  });

  // -------------------------------------------------------------------------
  // GET /audit-trend/:projectId — PROJECT scope. One point per audited EPIC.
  // -------------------------------------------------------------------------
  router.get('/audit-trend/:projectId', async (req, res) => {
    const { projectId } = req.params;
    if (!isValidPathComponent(projectId)) {
      send400(res, 'Invalid projectId path component');
      return;
    }

    const idx = await scanner.getIndex();
    const indexed = idx.projects.get(projectId) ?? null;
    if (indexed === null) {
      send404(res, `Project "${projectId}"`);
      return;
    }

    const points: AuditTrendPoint[] = [];
    for (const epic of indexed.epics.values()) {
      const p = await latestAuditedEpicPoint(scanner, indexed, epic);
      if (p) points.push(p);
    }

    sendOk(res, buildAuditTrend(points, 'project'));
  });

  return router;
}
