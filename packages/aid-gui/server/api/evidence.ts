/**
 * Evidence REST API router.
 *
 * Provides endpoints for browsing the evidence directory tree, listing runs
 * for an EPIC, viewing run file trees, and serving individual evidence files
 * with automatic format-aware parsing.
 *
 * Mounted at: /api/projects/:projectId/evidence
 */

import { Router, type Request, type Response } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { sendOk, send404, sendError } from './middleware.ts';
import {
  parseYaml,
  parseJson,
  parseJsonl,
  parseMarkdownWithFrontmatter,
} from '../parsers/index.ts';
import type {
  EvidenceEpicEntry,
  EvidenceRunEntry,
  EvidenceFileResponse,
} from '../types.ts';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Base evidence directory path within .aid-o/. */
function evidenceBase(aidoPath: string): string {
  return path.join(aidoPath, '04-engine', 'evidence');
}

/**
 * Check whether a path exists and is a directory.
 * Returns false on any error (ENOENT, permission, etc.).
 */
async function isDirectory(dirPath: string): Promise<boolean> {
  try {
    const stat = await fs.stat(dirPath);
    return stat.isDirectory();
  } catch {
    return false;
  }
}

/**
 * Recursively list all files under a directory, returning paths relative to
 * the given root directory.
 */
async function listFilesRecursive(dirPath: string, rootPath: string): Promise<string[]> {
  const results: string[] = [];

  let names: string[];
  try {
    names = await fs.readdir(dirPath);
  } catch {
    return results;
  }

  for (const name of names) {
    const fullPath = path.join(dirPath, name);
    let stat;
    try {
      stat = await fs.stat(fullPath);
    } catch {
      continue;
    }

    if (stat.isDirectory()) {
      const nested = await listFilesRecursive(fullPath, rootPath);
      results.push(...nested);
    } else if (stat.isFile()) {
      results.push(path.relative(rootPath, fullPath));
    }
  }

  return results;
}

/**
 * Check whether a specific file exists within a run directory.
 */
async function fileExists(filePath: string): Promise<boolean> {
  try {
    const stat = await fs.stat(filePath);
    return stat.isFile();
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// GET / — Evidence EPIC list
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response): Promise<void> => {
  const aidoPath = req.aidoPath;
  const basePath = evidenceBase(aidoPath);

  try {
    let epicDirNames: string[];
    try {
      epicDirNames = await fs.readdir(basePath);
    } catch {
      // Evidence directory does not exist — return empty list.
      sendOk<EvidenceEpicEntry[]>(res, []);
      return;
    }

    const epicEntries: EvidenceEpicEntry[] = [];

    for (const epicDirName of epicDirNames) {
      // Skip FIRST-AID directories.
      if (epicDirName.startsWith('FIRST-AID')) continue;

      const epicDirPath = path.join(basePath, epicDirName);
      if (!(await isDirectory(epicDirPath))) continue;

      // List run subdirectories.
      let runDirNames: string[];
      try {
        runDirNames = await fs.readdir(epicDirPath);
      } catch {
        runDirNames = [];
      }

      const runs: EvidenceRunEntry[] = [];
      for (const runDirName of runDirNames) {
        const runDirPath = path.join(epicDirPath, runDirName);
        if (!(await isDirectory(runDirPath))) continue;

        // Check for key files.
        const [hasStageLog, hasPlan, hasGatesReport] = await Promise.all([
          fileExists(path.join(runDirPath, 'stage_log.jsonl')),
          fileExists(path.join(runDirPath, 'plan.json')),
          fileExists(path.join(runDirPath, 'gates_report.json')),
        ]);

        // List top-level files in the run directory (non-recursive for the summary).
        let files: string[] = [];
        try {
          const runEntries = await fs.readdir(runDirPath, { withFileTypes: true });
          files = runEntries
            .filter((e) => e.isFile())
            .map((e) => e.name);
        } catch {
          // Ignore read errors.
        }

        runs.push({
          runId: runDirName,
          files,
          hasStageLog,
          hasPlan,
          hasGatesReport,
        });
      }

      epicEntries.push({
        epicId: epicDirName,
        runs,
      });
    }

    sendOk(res, epicEntries);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error listing evidence';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// GET /:epicId — Runs for an EPIC
// ---------------------------------------------------------------------------

router.get('/:epicId', async (req: Request, res: Response): Promise<void> => {
  const aidoPath = req.aidoPath;
  const { epicId } = req.params;
  const epicDirPath = path.join(evidenceBase(aidoPath), epicId);

  try {
    if (!(await isDirectory(epicDirPath))) {
      send404(res, `Evidence for EPIC "${epicId}"`);
      return;
    }

    let runDirNames: string[];
    try {
      runDirNames = await fs.readdir(epicDirPath);
    } catch {
      runDirNames = [];
    }

    const runs: EvidenceRunEntry[] = [];

    for (const runDirName of runDirNames) {
      const runDirPath = path.join(epicDirPath, runDirName);
      if (!(await isDirectory(runDirPath))) continue;

      const [hasStageLog, hasPlan, hasGatesReport] = await Promise.all([
        fileExists(path.join(runDirPath, 'stage_log.jsonl')),
        fileExists(path.join(runDirPath, 'plan.json')),
        fileExists(path.join(runDirPath, 'gates_report.json')),
      ]);

      // List top-level files in the run directory.
      let files: string[] = [];
      try {
        const runEntries = await fs.readdir(runDirPath, { withFileTypes: true });
        files = runEntries
          .filter((e) => e.isFile())
          .map((e) => e.name);
      } catch {
        // Ignore read errors.
      }

      runs.push({
        runId: runDirName,
        files,
        hasStageLog,
        hasPlan,
        hasGatesReport,
      });
    }

    sendOk(res, runs);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error listing runs';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// GET /:epicId/:runId — Run detail with full file tree
// ---------------------------------------------------------------------------

router.get('/:epicId/:runId', async (req: Request, res: Response): Promise<void> => {
  const aidoPath = req.aidoPath;
  const { epicId, runId } = req.params;
  const runDirPath = path.join(evidenceBase(aidoPath), epicId, runId);

  try {
    if (!(await isDirectory(runDirPath))) {
      send404(res, `Run "${runId}" for EPIC "${epicId}"`);
      return;
    }

    const files = await listFilesRecursive(runDirPath, runDirPath);

    sendOk(res, { epicId, runId, files });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error listing run files';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// GET /:epicId/:runId/files/* — Serve a specific evidence file
// ---------------------------------------------------------------------------

router.get(
  '/:epicId/:runId/files/*',
  async (req: Request, res: Response): Promise<void> => {
    const aidoPath = req.aidoPath;
    const { epicId, runId } = req.params;

    // The wildcard portion is the file path after "files/".
    // Express stores it in req.params[0] for a /* wildcard.
    const relativePath = req.params[0];
    if (!relativePath) {
      send404(res, 'File path');
      return;
    }

    // Security: prevent path traversal.
    const normalizedRelative = path.normalize(relativePath);
    if (normalizedRelative.startsWith('..') || path.isAbsolute(normalizedRelative)) {
      sendError(res, 400, 'BAD_REQUEST', 'Invalid file path');
      return;
    }

    const runDirPath = path.join(evidenceBase(aidoPath), epicId, runId);
    const filePath = path.join(runDirPath, normalizedRelative);

    // Verify the resolved path is still within the run directory.
    const resolvedFilePath = path.resolve(filePath);
    const resolvedRunDir = path.resolve(runDirPath);
    if (!resolvedFilePath.startsWith(resolvedRunDir + path.sep) && resolvedFilePath !== resolvedRunDir) {
      sendError(res, 400, 'BAD_REQUEST', 'File path escapes run directory');
      return;
    }

    try {
      let content: string;
      try {
        content = await fs.readFile(filePath, 'utf-8');
      } catch {
        send404(res, `File "${relativePath}"`);
        return;
      }

      const ext = path.extname(filePath).toLowerCase();
      let response: EvidenceFileResponse;

      switch (ext) {
        case '.json': {
          const result = parseJson<unknown>(content, filePath);
          response = {
            filePath: relativePath,
            format: 'json',
            content: result.data,
          };
          break;
        }

        case '.yaml':
        case '.yml': {
          const result = parseYaml<unknown>(content, filePath);
          response = {
            filePath: relativePath,
            format: 'yaml',
            content: result.data,
          };
          break;
        }

        case '.jsonl': {
          const result = parseJsonl<unknown>(content, filePath);
          response = {
            filePath: relativePath,
            format: 'jsonl',
            content: result.data,
          };
          break;
        }

        case '.md': {
          const result = parseMarkdownWithFrontmatter<unknown>(content, filePath);
          response = {
            filePath: relativePath,
            format: 'markdown',
            content: result.data,
          };
          break;
        }

        default: {
          response = {
            filePath: relativePath,
            format: 'text',
            content,
          };
          break;
        }
      }

      sendOk(res, response);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Unknown error reading file';
      sendError(res, 500, 'INTERNAL_ERROR', message);
    }
  },
);

export default router;
