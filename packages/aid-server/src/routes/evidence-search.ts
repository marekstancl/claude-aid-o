/**
 * Evidence search route.
 *
 * Provides grep-like text search across all evidence files stored in
 * .aid-o/work/evidence/. Walks epicId/runId directories recursively,
 * searches for case-insensitive substring matches, and returns results
 * sorted by epicId (asc), runId (desc = newest first), then filePath (asc).
 */

import { Router, type Request } from 'express';
import { join, resolve } from 'node:path';
import { readFile } from 'node:fs/promises';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';

/** A single search match result. */
interface SearchMatch {
  epicId: string;
  runId: string;
  filePath: string;
  matchLine: number;
  context: string;
}

/** Maximum allowed limit value. */
const MAX_LIMIT = 200;
/** Default limit when not specified. */
const DEFAULT_LIMIT = 50;
/** Number of bytes to read for binary detection. */
const BINARY_CHECK_BYTES = 512;

/**
 * Detect whether a file is binary by checking for null bytes (0x00)
 * in the first 512 bytes.
 */
async function isBinaryFile(filePath: string): Promise<boolean> {
  try {
    const fd = await readFile(filePath);
    const slice = fd.subarray(0, BINARY_CHECK_BYTES);
    return slice.includes(0x00);
  } catch {
    // If we cannot read the file, skip it
    return true;
  }
}

export function evidenceSearchRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/evidence/search?q=:query&limit=:limit
  router.get('/search', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) {
      return res.status(404).json({
        ok: false,
        error: { code: 'NOT_FOUND', message: 'Project not found' },
      });
    }

    const query = req.query.q;
    if (!query || typeof query !== 'string' || query.trim().length === 0) {
      return res.status(400).json({
        ok: false,
        error: { code: 'BAD_REQUEST', message: 'Query parameter "q" is required' },
      });
    }

    const rawLimit = Number(req.query.limit);
    const limit = Number.isFinite(rawLimit) && rawLimit > 0
      ? Math.min(rawLimit, MAX_LIMIT)
      : DEFAULT_LIMIT;

    const evidenceBase = join(fs.aidoPath, 'work', 'evidence');
    const resolvedBase = resolve(evidenceBase);

    // Walk epic directories
    const epicDirs = await fs.listDir(evidenceBase);
    const allMatches: SearchMatch[] = [];
    const queryLower = query.toLowerCase();

    for (const epicDir of epicDirs) {
      const epicPath = join(evidenceBase, epicDir);
      const runDirs = await fs.listDir(epicPath);

      for (const runDir of runDirs) {
        const runPath = join(evidenceBase, epicDir, runDir);
        const files = await fs.listDirRecursive(runPath);

        for (const relFile of files) {
          const fullPath = resolve(join(runPath, relFile));

          // Path traversal protection: ensure resolved path stays within evidence base
          if (!fullPath.startsWith(resolvedBase)) {
            continue;
          }

          // Skip binary files
          if (await isBinaryFile(fullPath)) {
            continue;
          }

          // Read file and search line by line
          const text = await fs.readText(fullPath);
          if (!text) continue;

          const lines = text.split('\n');
          for (let i = 0; i < lines.length; i++) {
            if (lines[i].toLowerCase().includes(queryLower)) {
              allMatches.push({
                epicId: epicDir,
                runId: runDir,
                filePath: relFile,
                matchLine: i + 1,
                context: lines[i].trim(),
              });
            }
          }
        }
      }
    }

    // Sort: epicId ascending, runId descending (newest first), filePath ascending
    allMatches.sort((a, b) => {
      const epicCmp = a.epicId.localeCompare(b.epicId);
      if (epicCmp !== 0) return epicCmp;

      const runCmp = b.runId.localeCompare(a.runId); // descending
      if (runCmp !== 0) return runCmp;

      return a.filePath.localeCompare(b.filePath);
    });

    const total = allMatches.length;
    const results = allMatches.slice(0, limit);

    res.json({
      ok: true,
      data: {
        results,
        total,
        limit,
        query,
      },
    });
  });

  return router;
}
