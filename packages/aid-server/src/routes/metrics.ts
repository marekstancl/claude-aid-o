/**
 * Per-EPIC metrics read route (EPIC E-047-3_7, Step 7).
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api` by the bootstrap:
 *   - `GET /api/metrics/:projectId/:epicId` → `MetricSet`.
 *
 * The {@link MetricSet} is the Step-5 view-assembly `buildMetrics` output: step
 * timings, gate runs/retries, checkpoint repeats, escalations — all derived from
 * the EPIC's latest full {@link RunDetail} (loaded via the memoizing cache) plus
 * the cheap per-run summaries. Unmeasurable values stay `null` with a warning,
 * never a fabricated zero (§5.7 — Phase-2 honesty lesson).
 *
 * Every response uses the standard envelope. Path components are validated
 * against `..`/separators (400); an unknown project/epic returns 404 — both
 * through the envelope.
 *
 * Module: src/routes/metrics.ts
 */

import { Router } from 'express';
import type { ScannerCache } from '../services/scanner-cache.js';
import { sendOk, send404, send400 } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import { buildMetrics, buildRunSummaries } from '../services/view-assembly.js';

/** Current time as an ISO 8601 string (scan marker for `meta`). */
function isoNow(): string {
  return new Date().toISOString();
}

/** Pick the run with the most-recent mtime (null-safe). Returns null when empty. */
function pickLatestRunId(
  runs: { runId: string; mtimeMs: number | null }[],
): string | null {
  let best: { runId: string; mtimeMs: number | null } | null = null;
  for (const r of runs) {
    if (best === null || (r.mtimeMs ?? -Infinity) > (best.mtimeMs ?? -Infinity)) {
      best = r;
    }
  }
  return best?.runId ?? null;
}

/**
 * Build the per-EPIC metrics read router backed by the Phase-2
 * {@link ScannerCache}.
 */
export function metricsRoutes(scanner: ScannerCache): Router {
  const router = Router();

  // -------------------------------------------------------------------------
  // GET /metrics/:projectId/:epicId — MetricSet for the EPIC's latest run.
  // -------------------------------------------------------------------------
  router.get('/metrics/:projectId/:epicId', async (req, res) => {
    const { projectId, epicId } = req.params;
    if (!isValidPathComponent(projectId) || !isValidPathComponent(epicId)) {
      send400(res, 'Invalid projectId/epicId path component');
      return;
    }

    const idx = await scanner.getIndex();
    const epic = idx.projects.get(projectId)?.epics.get(epicId) ?? null;
    if (epic === null) {
      send404(res, `EPIC "${epicId}" in project "${projectId}"`);
      return;
    }

    const runs = [...epic.runs.values()];
    const runSummaries = buildRunSummaries(runs);
    const latestRunId = pickLatestRunId(runs);
    const latest = latestRunId
      ? await scanner.getRunDetail(projectId, epicId, latestRunId)
      : null;

    const metrics = buildMetrics(latest, runSummaries);

    sendOk(res, metrics, { scannedAt: isoNow(), partialProjects: [] });
  });

  return router;
}
