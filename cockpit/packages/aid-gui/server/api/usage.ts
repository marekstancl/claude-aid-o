/**
 * Usage API router — aggregated metrics from timeline.jsonl files.
 *
 * Scans `.aid-o/work/evidence/` for all `timeline.jsonl` files,
 * parses each with the JSONL parser, and aggregates activity metrics
 * into a UsageSummary.
 *
 * Routes:
 *   GET / — Aggregated usage summary across all EPICs/runs
 */

import { Router, type Request, type Response } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { sendOk, sendError } from './middleware.ts';
import { parseJsonl } from '../parsers/index.ts';
import type { StageLogEntry, UsageSummary } from '../types.ts';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** An empty UsageSummary with all counters zeroed. */
function emptyUsageSummary(): UsageSummary {
  return {
    totalEvents: 0,
    agentDispatches: 0,
    gateEvaluations: 0,
    escalations: 0,
    perEpic: [],
  };
}

/**
 * Recursively scan the evidence directory for timeline.jsonl files.
 *
 * Expected structure:
 *   evidence/{epicId}/{runId}/timeline.jsonl
 *
 * Returns an array of { epicId, runId, filePath } for each found file.
 */
async function findStageLogFiles(
  aidoPath: string,
): Promise<Array<{ epicId: string; runId: string; filePath: string }>> {
  const evidenceDir = path.join(aidoPath, 'work', 'evidence');
  const results: Array<{ epicId: string; runId: string; filePath: string }> = [];

  let epicDirs: string[];
  try {
    epicDirs = await fs.readdir(evidenceDir);
  } catch {
    // Evidence directory does not exist — no logs at all.
    return results;
  }

  for (const epicDir of epicDirs) {
    const epicFullPath = path.join(evidenceDir, epicDir);

    let stat;
    try {
      stat = await fs.stat(epicFullPath);
    } catch {
      continue;
    }
    if (!stat.isDirectory()) continue;

    let runDirs: string[];
    try {
      runDirs = await fs.readdir(epicFullPath);
    } catch {
      continue;
    }

    for (const runDir of runDirs) {
      const runFullPath = path.join(epicFullPath, runDir);

      let runStat;
      try {
        runStat = await fs.stat(runFullPath);
      } catch {
        continue;
      }
      if (!runStat.isDirectory()) continue;

      const stageLogPath = path.join(runFullPath, 'timeline.jsonl');
      try {
        await fs.access(stageLogPath);
        results.push({
          epicId: epicDir,
          runId: runDir,
          filePath: stageLogPath,
        });
      } catch {
        // No timeline.jsonl in this run directory — skip.
      }
    }
  }

  return results;
}

/**
 * Compute the duration in seconds between the first and last timestamp
 * in an array of stage log entries. Returns 0 if fewer than 2 entries
 * or timestamps cannot be parsed.
 */
function computeDurationSeconds(entries: StageLogEntry[]): number {
  if (entries.length < 2) return 0;

  let earliest = Infinity;
  let latest = -Infinity;

  for (const entry of entries) {
    if (!entry.timestamp) continue;
    const ts = new Date(entry.timestamp).getTime();
    if (Number.isNaN(ts)) continue;

    if (ts < earliest) earliest = ts;
    if (ts > latest) latest = ts;
  }

  if (earliest === Infinity || latest === -Infinity) return 0;

  const durationMs = latest - earliest;
  return Math.round(durationMs / 1000);
}

// ---------------------------------------------------------------------------
// GET / — Aggregated usage summary
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response) => {
  try {
    const stageLogFiles = await findStageLogFiles(req.aidoPath);

    if (stageLogFiles.length === 0) {
      sendOk(res, emptyUsageSummary());
      return;
    }

    const summary: UsageSummary = emptyUsageSummary();

    for (const { epicId, runId, filePath } of stageLogFiles) {
      let content: string;
      try {
        content = await fs.readFile(filePath, 'utf-8');
      } catch {
        // File became inaccessible between scan and read — skip.
        continue;
      }

      const result = parseJsonl<StageLogEntry>(content, filePath);
      const entries = result.data ?? [];

      const eventCount = entries.length;
      summary.totalEvents += eventCount;

      // Count categorized events by checking the action field.
      let dispatches = 0;
      let gates = 0;
      let escalationCount = 0;

      for (const entry of entries) {
        const action = (entry.action ?? '').toLowerCase();

        if (action.includes('dispatch')) {
          dispatches++;
        }
        if (action.includes('gate')) {
          gates++;
        }
        if (action.includes('escalat')) {
          escalationCount++;
        }
      }

      summary.agentDispatches += dispatches;
      summary.gateEvaluations += gates;
      summary.escalations += escalationCount;

      const durationSeconds = computeDurationSeconds(entries);

      summary.perEpic.push({
        epicId,
        runId,
        events: eventCount,
        durationSeconds,
      });
    }

    sendOk(res, summary);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to compute usage summary';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

export default router;
