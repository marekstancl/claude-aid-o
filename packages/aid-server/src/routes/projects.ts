/**
 * Cross-project read routes (EPIC E-047-3_7, Step 5).
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api` by the bootstrap,
 * so this router's paths resolve to:
 *   - `GET /api/projects`                 → `Project[]` (active/running first)
 *   - `GET /api/projects/:projectId`      → `ProjectDetail`
 *   - `GET /api/projects/:projectId/epics`→ `EpicSummary[]`
 *
 * Every response uses the standard envelope (`{ ok, data, meta? }` /
 * `{ ok, error }`). Path components are validated against `..`/separators (400),
 * and unknown projects return 404 — both through the envelope. Replaces the old
 * single-project `projectRoutes(registry)` that scanned a lone workspace.
 *
 * Module: src/routes/projects.ts
 */

import { Router } from 'express';
import type { Project } from '@aid/contract';
import type { ScannerCache } from '../services/scanner-cache.js';
import { FsReader } from '../services/fs-reader.js';
import { sendOk, send404, send400 } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import {
  buildProjectDetail,
  buildEpicSummaries,
  compareProject,
  partialProjectIds,
} from '../services/view-assembly.js';

/** Current time as an ISO 8601 string (cross-project scan marker for `meta`). */
function isoNow(): string {
  return new Date().toISOString();
}

/**
 * Build the cross-project read router backed by the Phase-2 {@link ScannerCache}.
 * A stateless {@link FsReader} is used for the small queue/spec reads the detail
 * assemblers need (everything else routes through the cache).
 */
export function projectRoutes(scanner: ScannerCache): Router {
  const router = Router();
  const fs = new FsReader();

  // -------------------------------------------------------------------------
  // GET /projects — full Project[] list, active/running sorted first.
  // -------------------------------------------------------------------------
  router.get('/projects', async (_req, res) => {
    const projects: Project[] = await scanner.listProjects();
    const sorted = [...projects].sort(compareProject);

    sendOk(res, sorted, {
      scannedAt: isoNow(),
      partialProjects: partialProjectIds(sorted),
      total: sorted.length,
    });
  });

  // -------------------------------------------------------------------------
  // GET /projects/:projectId — ProjectDetail (epics + queue + recentActivity).
  // -------------------------------------------------------------------------
  router.get('/projects/:projectId', async (req, res) => {
    const { projectId } = req.params;
    if (!isValidPathComponent(projectId)) {
      send400(res, 'Invalid projectId path component');
      return;
    }

    const detail = await buildProjectDetail(scanner, fs, projectId);
    if (detail === null) {
      send404(res, `Project "${projectId}"`);
      return;
    }

    sendOk(res, detail, {
      scannedAt: isoNow(),
      partialProjects: detail.partial ? [detail.id] : [],
    });
  });

  // -------------------------------------------------------------------------
  // GET /projects/:projectId/epics — EpicSummary[] for one project.
  // -------------------------------------------------------------------------
  router.get('/projects/:projectId/epics', async (req, res) => {
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

    const epics = buildEpicSummaries(indexed);
    sendOk(res, epics, {
      scannedAt: isoNow(),
      partialProjects: [],
      total: epics.length,
    });
  });

  return router;
}
