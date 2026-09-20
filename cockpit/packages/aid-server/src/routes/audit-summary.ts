/**
 * Project-scope `aggregateAudit` read route (EPIC E-047-4_7, Step 6) — spec §7.4,
 * §13.5.7 / MF7.
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api`, BEFORE the `/api/*`
 * catch-all:
 *
 *   - `GET /api/audit-summary/:projectId` → the project-scope `aggregateAudit`
 *     (an {@link AuditSummary} plus `scoredEpicCount` / `medianEpicId`): the
 *     median-EPIC summary across the project's audited member EPICs (§13.5.7).
 *
 * The route assembles one {@link MemberEpicSummary} per EPIC whose LATEST run has
 * an audit-report.md (using `RunDetail.audit` as the per-run summary and
 * `RunDetail.startedAt` as the tie-break key), then defers the median-EPIC pick to
 * the pure {@link buildAggregateAudit} (Step 5). Honest sparse handling lives
 * there: 0 scored EPICs → `present:true, overallScore:null` + a warning (verified
 * empty-but-honest on sousto-na-miru, 0 audit-report.md); 1 → an "n=1" warning.
 * The headline `overallScore` is a REAL on-disk report's median score, never a
 * synthesized mean (§13.5.7 "flag, never fake").
 *
 * The server writes NOTHING (read-only; the §7.6 grep test stays green).
 *
 * Module: src/routes/audit-summary.ts
 */

import { Router } from 'express';
import type { ScannerCache } from '../services/scanner-cache.js';
import { pickLatestIndexedRun } from '../services/view-assembly.js';
import { sendOk, send404, send400 } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import {
  buildAggregateAudit,
  type MemberEpicSummary,
} from '../audit/build-aggregate-audit.js';

/**
 * Build the READ-ONLY audit-summary router backed by the {@link ScannerCache}.
 * GET only — no mutation endpoints exist on this surface.
 */
export function auditSummaryRoutes(scanner: ScannerCache): Router {
  const router = Router();

  // -------------------------------------------------------------------------
  // GET /audit-summary/:projectId — project-scope aggregateAudit (median-EPIC).
  // -------------------------------------------------------------------------
  router.get('/audit-summary/:projectId', async (req, res) => {
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

    // One member per EPIC whose LATEST run has an audit-report.md (§5.4 run→EPIC
    // = latest-run rule). An EPIC whose latest run is not audited contributes a
    // `present:false` summary, which buildAggregateAudit excludes from the median.
    const members: MemberEpicSummary[] = [];
    for (const epic of indexed.epics.values()) {
      const latest = pickLatestIndexedRun([...epic.runs.values()]);
      if (latest === null) continue;
      const detail = await scanner.getRunDetail(indexed.projectId, epic.epicId, latest.runId);
      members.push({
        epicId: epic.epicId,
        startedAt: detail.startedAt,
        summary: detail.audit,
      });
    }

    sendOk(res, buildAggregateAudit(members));
  });

  return router;
}
