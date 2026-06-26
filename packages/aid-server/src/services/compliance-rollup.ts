/**
 * Cross-project compliance roll-up (EPIC E-047-3_7, Step 7).
 *
 * Folds the per-run {@link ComplianceRun} data (read from each run's
 * `compliance.json` by the Step-8 RunDetail builder, via the memoizing
 * {@link ScannerCache}) into the cross-project {@link ComplianceView} the cockpit
 * compliance surface renders.
 *
 * Design rules (§5.7 / Phase-2 lesson — NEVER fabricate):
 *  - A run with no `compliance.json` (ComplianceRun === null) is NOT counted as a
 *    pass: it is excluded from the evaluated totals and recorded as a warning on
 *    the headline {@link Score}. Missing data → warning, never 0-as-pass.
 *  - `violations[].failures` carry the STRUCTURED {@link ComplianceFailure}[]
 *    (check / evidence / severity) straight from the RunDetail, never `string[]`.
 *  - `passRate` is a real ratio over EVALUATED runs only; when nothing was
 *    evaluated the rate is 0 and the headline score is `null` + low confidence.
 *  - All reads route through the never-throw cache; this helper never throws.
 *
 * Module: src/services/compliance-rollup.ts
 */

import type {
  ComplianceRun,
  ComplianceView,
  Score,
} from '@aid/contract';
import type { ScannerCache, Tier1Index } from './scanner-cache.js';

/** One evaluated run paired with the project it belongs to (internal). */
interface EvaluatedRun {
  projectId: string;
  compliance: ComplianceRun;
}

/**
 * Build a cross-project (or single-project, when `scopeProjectId` is set)
 * {@link ComplianceView} from the Tier-1 index + per-run RunDetail compliance.
 *
 * `scope` is `'all'` for the cross-project roll-up, else the scoped project id.
 * Returns null only when `scopeProjectId` names a project absent from the index
 * (the route maps that to a 404). A cross-project roll-up over an empty fleet
 * returns a type-valid empty view (never null).
 */
export async function buildComplianceView(
  cache: ScannerCache,
  scopeProjectId?: string,
): Promise<ComplianceView | null> {
  const idx = await cache.getIndex();

  if (scopeProjectId !== undefined && !idx.projects.has(scopeProjectId)) {
    return null;
  }

  const { evaluated, unevaluatedRunCount } = await collectEvaluated(
    cache,
    idx,
    scopeProjectId,
  );

  const totalRuns = evaluated.length;
  const passed = evaluated.filter((r) => r.compliance.overall === 'pass').length;
  const failed = totalRuns - passed;
  const forceOverrides = evaluated.reduce(
    (sum, r) => sum + r.compliance.forceOverrideCount,
    0,
  );

  // passRate is a ratio over EVALUATED runs only (never over runs with no
  // compliance.json — those are not "passing", they are "not evaluated").
  const passRate = totalRuns > 0 ? passed / totalRuns : 0;

  const violations: ComplianceView['violations'] = evaluated
    .filter((r) => r.compliance.overall === 'fail')
    .map((r) => ({
      projectId: r.projectId,
      epicId: r.compliance.epicId,
      runId: r.compliance.runId,
      overall: 'fail' as const,
      // STRUCTURED ComplianceFailure[] straight from the RunDetail — never string[].
      failures: r.compliance.failures,
      forceOverrideCount: r.compliance.forceOverrideCount,
      evaluatedAt: r.compliance.evaluatedAt,
    }));

  return {
    scope: scopeProjectId ?? 'all',
    fsmAdherenceScore: buildAdherenceScore(passRate, totalRuns, unevaluatedRunCount),
    passRate,
    totals: { runs: totalRuns, passed, failed, forceOverrides },
    violations,
  };
}

/**
 * Walk the index (optionally scoped to one project), load each run's RunDetail
 * via the memoizing cache, and partition into evaluated runs (those with a real
 * `compliance.json`) and a count of runs that had none. Never throws.
 */
async function collectEvaluated(
  cache: ScannerCache,
  idx: Tier1Index,
  scopeProjectId: string | undefined,
): Promise<{ evaluated: EvaluatedRun[]; unevaluatedRunCount: number }> {
  const evaluated: EvaluatedRun[] = [];
  let unevaluatedRunCount = 0;

  for (const project of idx.projects.values()) {
    if (scopeProjectId !== undefined && project.projectId !== scopeProjectId) {
      continue;
    }
    for (const epic of project.epics.values()) {
      for (const run of epic.runs.values()) {
        const detail = await cache.getRunDetail(
          project.projectId,
          epic.epicId,
          run.runId,
        );
        if (detail.compliance === null) {
          // No compliance.json → NOT evaluated. Excluded from totals, surfaced
          // as a warning on the headline score (never silently counted as pass).
          unevaluatedRunCount += 1;
          continue;
        }
        evaluated.push({ projectId: project.projectId, compliance: detail.compliance });
      }
    }
  }

  return { evaluated, unevaluatedRunCount };
}

/**
 * Build the headline FSM-adherence {@link Score} envelope (§5.7 — never a bare
 * number). The value is the evaluated pass-rate as a 0-100 score; it is `null`
 * with low confidence when there were no evaluated runs. Runs lacking a
 * `compliance.json` surface as a warning + the `partial` flag, never as a
 * fabricated zero.
 */
function buildAdherenceScore(
  passRate: number,
  evaluatedRuns: number,
  unevaluatedRuns: number,
): Score {
  const warnings: string[] = [];
  if (unevaluatedRuns > 0) {
    warnings.push(
      `${unevaluatedRuns} run(s) had no compliance.json and were excluded from the pass-rate (not counted as passing)`,
    );
  }
  if (evaluatedRuns === 0) {
    warnings.push('no runs carried a compliance.json — adherence score unavailable');
  }

  const value = evaluatedRuns > 0 ? Math.round(passRate * 100) : null;
  const partial = unevaluatedRuns > 0 || evaluatedRuns === 0;

  return {
    value,
    partial,
    confidence: evaluatedRuns > 0 ? 'high' : 'low',
    components: { passRate: evaluatedRuns > 0 ? passRate : null },
    warnings,
  };
}
