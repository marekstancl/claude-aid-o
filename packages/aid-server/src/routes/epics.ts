/**
 * Cross-project EPIC + run read routes (EPIC E-047-3_7, Step 5).
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api` by the bootstrap,
 * so this router's paths resolve to:
 *   - `GET /api/epics/:projectId/:epicId`                → `EpicDetail`
 *   - `GET /api/epics/:projectId/:epicId/runs/:runId`    → `RunDetail`
 *
 * Every response uses the standard envelope. Path components are validated
 * against `..`/separators (400); unknown project/epic/run returns 404 — both
 * through the envelope. Replaces the old single-project `epicRoutes(registry)`
 * that also exposed a POST `/run` mutation (dropped — this surface is read-only).
 *
 * Module: src/routes/epics.ts
 */

import { Router } from 'express';
import type { ScannerCache } from '../services/scanner-cache.js';
import { FsReader } from '../services/fs-reader.js';
import { sendOk, send404, send400 } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import { buildEpicDetail } from '../services/view-assembly.js';

/** Current time as an ISO 8601 string (scan marker for `meta`). */
function isoNow(): string {
  return new Date().toISOString();
}

/**
 * Build the cross-project EPIC/run read router backed by the Phase-2
 * {@link ScannerCache}. RunDetail is produced by the cache's injected, memoizing
 * loader; EpicDetail is assembled from the Tier-1 index plus that loader.
 */
export function epicRoutes(scanner: ScannerCache): Router {
  const router = Router();
  const fs = new FsReader();

  // -------------------------------------------------------------------------
  // GET /epics/:projectId/:epicId — full EpicDetail.
  // -------------------------------------------------------------------------
  router.get('/epics/:projectId/:epicId', async (req, res) => {
    const { projectId, epicId } = req.params;
    if (!isValidPathComponent(projectId) || !isValidPathComponent(epicId)) {
      send400(res, 'Invalid projectId/epicId path component');
      return;
    }

    const detail = await buildEpicDetail(scanner, fs, projectId, epicId);
    if (detail === null) {
      send404(res, `EPIC "${epicId}" in project "${projectId}"`);
      return;
    }

    sendOk(res, detail, { scannedAt: isoNow(), partialProjects: [] });
  });

  // -------------------------------------------------------------------------
  // GET /epics/:projectId/:epicId/runs/:runId — full RunDetail.
  // -------------------------------------------------------------------------
  router.get('/epics/:projectId/:epicId/runs/:runId', async (req, res) => {
    const { projectId, epicId, runId } = req.params;
    if (
      !isValidPathComponent(projectId) ||
      !isValidPathComponent(epicId) ||
      !isValidPathComponent(runId)
    ) {
      send400(res, 'Invalid projectId/epicId/runId path component');
      return;
    }

    // The run must be known to the index; otherwise 404 (avoid emitting a stub
    // for a path that was never discovered).
    const idx = await scanner.getIndex();
    const known =
      idx.projects.get(projectId)?.epics.get(epicId)?.runs.has(runId) ?? false;
    if (!known) {
      send404(res, `Run "${runId}" (EPIC "${epicId}", project "${projectId}")`);
      return;
    }

    const detail = await scanner.getRunDetail(projectId, epicId, runId);
    sendOk(res, detail, { scannedAt: isoNow(), partialProjects: [] });
  });

  return router;
}
