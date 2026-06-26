/**
 * Cross-project compliance read routes (EPIC E-047-3_7, Step 7).
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api` by the bootstrap,
 * so this router's paths resolve to:
 *   - `GET /api/compliance`              → cross-project `ComplianceView` (scope 'all')
 *   - `GET /api/compliance/:projectId`   → project-scoped `ComplianceView`
 *
 * The view folds each run's `compliance.json` (read by the Step-8 RunDetail
 * builder) into totals + pass-rate + structured violations. `violations[].failures`
 * carry STRUCTURED {@link ComplianceFailure}[] (check / evidence / severity),
 * never `string[]`; runs without a `compliance.json` are NOT counted as passing —
 * they are surfaced as a warning on the headline score (§5.7 — never fabricate).
 *
 * Every response uses the standard envelope. Path components are validated against
 * `..`/separators (400); an unknown scoped project returns 404 — both through the
 * envelope.
 *
 * Module: src/routes/compliance.ts
 */

import { Router } from 'express';
import type { ScannerCache } from '../services/scanner-cache.js';
import { sendOk, send404, send400, isoNow } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import { buildComplianceView } from '../services/compliance-rollup.js';

/**
 * Build the compliance read router backed by the Phase-2 {@link ScannerCache}.
 * Both endpoints are GET-only.
 */
export function complianceRoutes(scanner: ScannerCache): Router {
  const router = Router();

  // -------------------------------------------------------------------------
  // GET /compliance — cross-project ComplianceView (scope 'all').
  // -------------------------------------------------------------------------
  router.get('/compliance', async (_req, res) => {
    const view = await buildComplianceView(scanner);
    // Cross-project scope is never null (empty fleet → empty type-valid view).
    sendOk(res, view, {
      scannedAt: isoNow(),
      partialProjects: [],
      warnings: view?.fsmAdherenceScore.warnings ?? [],
    });
  });

  // -------------------------------------------------------------------------
  // GET /compliance/:projectId — project-scoped ComplianceView.
  // -------------------------------------------------------------------------
  router.get('/compliance/:projectId', async (req, res) => {
    const { projectId } = req.params;
    if (!isValidPathComponent(projectId)) {
      send400(res, 'Invalid projectId path component');
      return;
    }

    const view = await buildComplianceView(scanner, projectId);
    if (view === null) {
      send404(res, `Project "${projectId}"`);
      return;
    }

    sendOk(res, view, {
      scannedAt: isoNow(),
      partialProjects: [],
      warnings: view.fsmAdherenceScore.warnings,
    });
  });

  return router;
}
