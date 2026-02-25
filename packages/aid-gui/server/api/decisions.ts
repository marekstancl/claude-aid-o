/**
 * Decision management routes.
 *
 * GET  /           — Decision history (all pm_decision.json and pm_plan_approval.json files)
 * GET  /pending    — Pending decisions (runs awaiting PM action)
 * POST /           — Write a new decision
 *
 * All paths are relative to `{req.aidoPath}/04-engine/evidence/`.
 */

import { Router, type Request, type Response } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { sendOk, send404, send400, sendError, invalidateActiveRunCache } from './middleware.ts';
import { parseJson } from '../parsers/index.ts';
import type { Decision, PendingDecision, DecisionWriteRequest, PlanProgress } from '../types.ts';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Recursively collect all file paths under `dir` whose basename matches one of
 * the given `filenames`. Returns absolute paths. Never throws -- returns an
 * empty array on any filesystem error.
 */
async function findFilesRecursive(
  dir: string,
  filenames: string[],
): Promise<string[]> {
  const results: string[] = [];

  let entries: import('node:fs').Dirent[];
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch {
    return results;
  }

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const nested = await findFilesRecursive(fullPath, filenames);
      results.push(...nested);
    } else if (filenames.includes(entry.name)) {
      results.push(fullPath);
    }
  }

  return results;
}

/**
 * Extract epicId and runId from an evidence file path.
 *
 * Expected structure: .../evidence/{epicId}/{runId}/filename.json
 * Returns null if the path does not contain the expected segments.
 */
function extractEpicAndRun(filePath: string): { epicId: string; runId: string } | null {
  const parts = filePath.split(path.sep);
  const evidenceIdx = parts.lastIndexOf('evidence');
  if (evidenceIdx === -1 || evidenceIdx + 2 >= parts.length) {
    return null;
  }
  return {
    epicId: parts[evidenceIdx + 1],
    runId: parts[evidenceIdx + 2],
  };
}

// ---------------------------------------------------------------------------
// GET / — Decision history
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response): Promise<void> => {
  try {
    const evidenceDir = path.join(req.aidoPath, '04-engine', 'evidence');
    const decisionFiles = await findFilesRecursive(evidenceDir, [
      'pm_decision.json',
      'pm_plan_approval.json',
    ]);

    const decisions: Decision[] = [];

    for (const filePath of decisionFiles) {
      try {
        const content = await fs.readFile(filePath, 'utf-8');
        const result = parseJson<Decision>(content, filePath);
        if (result.data) {
          // Enrich with epicId and runId from the path if not already present.
          const ids = extractEpicAndRun(filePath);
          if (ids) {
            if (!result.data.epicId) result.data.epicId = ids.epicId;
            if (!result.data.runId) result.data.runId = ids.runId;
          }
          // Determine type from filename when not set in the data.
          if (!result.data.type) {
            const basename = path.basename(filePath);
            if (basename === 'pm_plan_approval.json') {
              result.data.type = 'plan_approval';
            } else {
              result.data.type = 'decision';
            }
          }
          decisions.push(result.data);
        }
      } catch {
        // Skip files that cannot be read or parsed.
      }
    }

    // Sort by timestamp descending (newest first). Missing timestamps go last.
    decisions.sort((a, b) => {
      const ta = a.timestamp ?? '';
      const tb = b.timestamp ?? '';
      return tb.localeCompare(ta);
    });

    sendOk(res, decisions, { total: decisions.length });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error reading decisions';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// GET /pending — Pending decisions
// ---------------------------------------------------------------------------

router.get('/pending', async (req: Request, res: Response): Promise<void> => {
  try {
    const evidenceDir = path.join(req.aidoPath, '04-engine', 'evidence');

    // Collect all plan_progress.json files to identify active runs.
    const progressFiles = await findFilesRecursive(evidenceDir, ['plan_progress.json']);

    // Collect all pm_decision.json files to know which runs already have decisions.
    const decisionFiles = await findFilesRecursive(evidenceDir, ['pm_decision.json']);
    const decidedPaths = new Set(decisionFiles.map((fp) => path.dirname(fp)));

    const pending: PendingDecision[] = [];

    for (const progressPath of progressFiles) {
      const runDir = path.dirname(progressPath);

      // Skip runs that already have a decision.
      if (decidedPaths.has(runDir)) {
        continue;
      }

      try {
        const content = await fs.readFile(progressPath, 'utf-8');
        const result = parseJson<PlanProgress>(content, progressPath);
        if (!result.data) continue;

        const progress = result.data;

        // Check if the run state indicates a decision is needed.
        const needsDecision = isDecisionNeeded(progress);
        if (!needsDecision) continue;

        const ids = extractEpicAndRun(progressPath);
        if (!ids) continue;

        pending.push({
          epicId: ids.epicId,
          runId: ids.runId,
          state: progress.state ?? progress.currentStep ?? 'unknown',
          evidencePath: runDir,
        });
      } catch {
        // Skip unreadable progress files.
      }
    }

    sendOk(res, pending, { total: pending.length });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error reading pending decisions';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

/**
 * Determine if a plan progress record indicates a PM decision is needed.
 *
 * A decision is needed when:
 * - The overall run state contains "PLAN_REVIEW" or "PM_APPROVAL"
 * - Any step has a status of "executing" (may indicate blocked on approval)
 */
function isDecisionNeeded(progress: PlanProgress): boolean {
  const state = (progress.state ?? '').toUpperCase();

  if (state.includes('PLAN_REVIEW') || state.includes('PM_APPROVAL')) {
    return true;
  }

  // Check per-step statuses for signs of awaiting approval.
  if (progress.steps) {
    for (const stepId of Object.keys(progress.steps)) {
      const step = progress.steps[stepId];
      if (step.status === 'executing') {
        return true;
      }
    }
  }

  return false;
}

// ---------------------------------------------------------------------------
// POST / — Write a decision
// ---------------------------------------------------------------------------

router.post('/', async (req: Request, res: Response): Promise<void> => {
  try {
    const body = req.body as Partial<DecisionWriteRequest> | undefined;

    // Validate required fields.
    if (!body || typeof body.epicId !== 'string' || !body.epicId.trim()) {
      send400(res, 'epicId is required and must be a non-empty string');
      return;
    }
    if (typeof body.runId !== 'string' || !body.runId.trim()) {
      send400(res, 'runId is required and must be a non-empty string');
      return;
    }
    if (typeof body.decision !== 'string' || !body.decision.trim()) {
      send400(res, 'decision is required and must be a non-empty string');
      return;
    }

    const epicId = body.epicId.trim();
    const runId = body.runId.trim();
    const decisionValue = body.decision.trim();
    const feedback = body.feedback !== undefined && body.feedback !== null
      ? String(body.feedback)
      : null;

    // Verify the evidence directory exists.
    const runDir = path.join(req.aidoPath, '04-engine', 'evidence', epicId, runId);
    try {
      const stat = await fs.stat(runDir);
      if (!stat.isDirectory()) {
        send404(res, `Evidence directory for EPIC "${epicId}" run "${runId}"`);
        return;
      }
    } catch {
      send404(res, `Evidence directory for EPIC "${epicId}" run "${runId}"`);
      return;
    }

    // Build the decision object.
    const decision: Decision = {
      timestamp: new Date().toISOString(),
      type: 'decision',
      epicId,
      runId,
      decision: decisionValue,
      feedback,
      channel: 'gui',
    };

    // Atomic write: write to .tmp, then rename.
    const targetPath = path.join(runDir, 'pm_decision.json');
    const tmpPath = `${targetPath}.tmp`;

    const jsonContent = JSON.stringify(decision, null, 2);
    await fs.writeFile(tmpPath, jsonContent, 'utf-8');
    await fs.rename(tmpPath, targetPath);

    // Invalidate cache since we just wrote a decision.
    invalidateActiveRunCache();

    res.status(201);
    sendOk(res, decision);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error writing decision';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

export default router;
