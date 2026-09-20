/**
 * PLAN read routes (EPIC E-047-4_7, Step 7) — spec §7.4, §13.6 / SF4 / MF6.
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api`, BEFORE the `/api/*`
 * catch-all:
 *
 *   - `GET /api/plans/:projectId`            → `PlanSummary[]` (every tier-1-to-3
 *      plan in the project, four-tier membership per §13.6).
 *   - `GET /api/plans/:projectId/:planId`    → `PlanDetail` (one plan: members,
 *      progress/AC%, durationS, boundary+aggregate audit, delivery+simplifier,
 *      backlog rows, full LessonsView, §13.6/SF4/MF6).
 *
 * The route does the scanner I/O (members, AC, audits, lessons, delivery,
 * simplifier, backlog via `plan-assembly.ts`); the pure builders shape the read
 * model (`build-plan.ts`). `:planId` accepts the bare plan number (`P046`) or a
 * plan-file stem (`P046-foo`); both normalize to `P046`. The server writes
 * NOTHING (read-only; the §7.6 grep test stays green).
 *
 * Module: src/routes/plans.ts
 */

import { Router } from 'express';
import type { PlanSummary } from '@aid/contract';
import type { ScannerCache } from '../services/scanner-cache.js';
import { FsReader } from '../services/fs-reader.js';
import { sendOk, send404, send400, sendError, isoNow } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import { planNumberPrefix, buildPlanSummary, buildPlanDetail } from '../plan/build-plan.js';
import {
  discoverPlans,
  assemblePlanBuildInput,
  stemsForNumber,
} from '../plan/plan-assembly.js';

/**
 * Build the READ-ONLY plans router backed by the {@link ScannerCache}. GET only.
 */
export function plansRoutes(scanner: ScannerCache): Router {
  const router = Router();
  const fs = new FsReader();

  // -------------------------------------------------------------------------
  // GET /plans/:projectId — every tier-1-to-3 plan as a PlanSummary list-row.
  // -------------------------------------------------------------------------
  router.get('/plans/:projectId', async (req, res) => {
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

    const discovered = await discoverPlans(scanner, indexed);
    const summaries: PlanSummary[] = [];
    for (const plan of discovered) {
      // STEM is the primary identity — always look the plan up by its stem, never
      // by number (PM #1: a number key collapses colliding stems to the first).
      const input = await assemblePlanBuildInput(scanner, fs, indexed, plan.planStem);
      if (input) summaries.push(buildPlanSummary(input));
    }

    sendOk(res, summaries, { scannedAt: isoNow(), partialProjects: [] });
  });

  // -------------------------------------------------------------------------
  // GET /plans/:projectId/:planId — one plan's full PlanDetail.
  // -------------------------------------------------------------------------
  router.get('/plans/:projectId/:planId', async (req, res) => {
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

    // STEM-PRIMARY lookup (PM #1):
    //  1. exact stem (`P022-b-foo`, or number-less stems like `ideas`) → use it.
    //  2. bare number (`P022`): resolve the stems sharing it —
    //       0 → 404, 1 → that stem, >1 → 409 AMBIGUOUS (never pick one at random).
    let lookupKey: string | null = null;
    if (indexed.plans.has(planId)) {
      lookupKey = planId; // exact stem
    } else {
      const planNumber = planNumberPrefix(planId);
      if (planNumber === null) {
        send404(res, `Plan "${planId}"`);
        return;
      }
      const candidates = stemsForNumber(indexed, planNumber);
      if (candidates.length === 0) {
        send404(res, `Plan "${planNumber}" in project "${projectId}"`);
        return;
      }
      if (candidates.length > 1) {
        sendError(
          res,
          409,
          'AMBIGUOUS_PLAN_NUMBER',
          `Plan number "${planNumber}" is ambiguous in project "${projectId}" — ${candidates.length} plans share it. Request one by its exact stem.`,
          { candidates: candidates.slice().sort((a, b) => a.localeCompare(b)) },
        );
        return;
      }
      lookupKey = candidates[0];
    }

    const input = await assemblePlanBuildInput(scanner, fs, indexed, lookupKey);
    if (input === null) {
      send404(res, `Plan "${planId}" in project "${projectId}"`);
      return;
    }

    sendOk(res, buildPlanDetail(input), { scannedAt: isoNow(), partialProjects: [] });
  });

  return router;
}
