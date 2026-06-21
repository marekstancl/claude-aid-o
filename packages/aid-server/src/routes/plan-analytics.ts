/**
 * Cross-project Plan Outcome Analytics route (EPIC E-047-4_7, Step 7) — spec
 * §7.4, §13.12 (Rev 4.1 addendum).
 *
 *   - `GET /api/analytics/plans?project=&outcome=&since=` → `PlanOutcomeAnalytics`
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api`, BEFORE the `/api/*`
 * catch-all. The route does pure scanner reads (`plan-assembly.ts`) and defers
 * classification / roll-up / sort / filters to the pure
 * {@link buildPlanOutcomeAnalytics} + {@link filterOutcomeRows}.
 *
 * Filter contract (§13.12):
 *   - `project` — exact project id. Unknown explicit project → 404.
 *   - `outcome` — exact enum (`passed|partial|failed|in_progress|unverifiable`).
 *      Invalid → 400.
 *   - `since`   — ISO-8601 lower bound on `lastActivityAt`. Invalid → 400.
 *   - `totals` reconcile EXACTLY to the returned filtered rows; `partialProjects`
 *      is a sorted unique list.
 *
 * It MUST NOT execute the shell diagnostic on a request (pure read). The server
 * writes NOTHING (read-only; the §7.6 grep test stays green).
 *
 * Module: src/routes/plan-analytics.ts
 */

import { Router } from 'express';
import type { PlanOutcome } from '@aid/contract';
import type { IndexedProject, ScannerCache } from '../services/scanner-cache.js';
import { FsReader } from '../services/fs-reader.js';
import { sendOk, send404, send400, isoNow } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import {
  buildPlanOutcomeAnalytics,
  filterOutcomeRows,
  reconcileTotals,
  isValidOutcome,
  isValidSince,
} from '../plan/build-plan-outcomes.js';
import {
  discoverPlans,
  assembleOutcomePlanInput,
} from '../plan/plan-assembly.js';

/** First value of a (possibly array) query param, or null. */
function firstQuery(v: unknown): string | null {
  if (typeof v === 'string') return v.length > 0 ? v : null;
  if (Array.isArray(v) && typeof v[0] === 'string') return v[0];
  return null;
}

/**
 * Build the READ-ONLY plan-analytics router backed by the {@link ScannerCache}.
 * GET only — no mutation endpoints. NEVER execs the shell diagnostic.
 */
export function planAnalyticsRoutes(scanner: ScannerCache): Router {
  const router = Router();
  const fs = new FsReader();

  router.get('/analytics/plans', async (req, res) => {
    const projectFilter = firstQuery(req.query.project);
    const outcomeFilter = firstQuery(req.query.outcome);
    const sinceFilter = firstQuery(req.query.since);

    // --- Validate filters (invalid enum/timestamp → 400). ---
    if (outcomeFilter !== null && !isValidOutcome(outcomeFilter)) {
      send400(res, `Invalid outcome filter "${outcomeFilter}"`);
      return;
    }
    if (sinceFilter !== null && !isValidSince(sinceFilter)) {
      send400(res, `Invalid since timestamp "${sinceFilter}"`);
      return;
    }
    if (projectFilter !== null && !isValidPathComponent(projectFilter)) {
      send400(res, 'Invalid project filter path component');
      return;
    }

    const idx = await scanner.getIndex();

    // --- Resolve the project scope (unknown explicit project → 404). ---
    let projects: IndexedProject[];
    if (projectFilter !== null) {
      const indexed = idx.projects.get(projectFilter) ?? null;
      if (indexed === null) {
        send404(res, `Project "${projectFilter}"`);
        return;
      }
      projects = [indexed];
    } else {
      projects = [...idx.projects.values()];
    }

    // --- Assemble per-plan outcome inputs across the scoped projects. ---
    const inputs = [];
    for (const indexed of projects) {
      const discovered = await discoverPlans(scanner, indexed);
      for (const plan of discovered) {
        const input = await assembleOutcomePlanInput(scanner, fs, indexed, plan);
        if (input) inputs.push(input);
      }
    }

    // Build the full analytics, then apply outcome/since filters; recompute the
    // totals + partialProjects EXACTLY against the filtered rows (§13.12).
    const full = buildPlanOutcomeAnalytics(inputs, isoNow());
    const filteredRows = filterOutcomeRows(full.plans, {
      outcome: (outcomeFilter as PlanOutcome | null) ?? null,
      since: sinceFilter,
    });
    const partialProjects = [
      ...new Set(filteredRows.filter((r) => r.dataPartial).map((r) => r.projectId)),
    ].sort((a, b) => a.localeCompare(b));

    sendOk(
      res,
      {
        generatedAt: full.generatedAt,
        plans: filteredRows,
        totals: reconcileTotals(filteredRows),
        partialProjects,
      },
      { scannedAt: full.generatedAt, partialProjects },
    );
  });

  return router;
}
