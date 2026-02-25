/**
 * Shared API middleware for project resolution and error handling.
 *
 * Resolves :projectId to an .aid-o/ directory path and attaches it to the
 * request. Provides helpers for consistent API responses.
 */

import { Router, type Request, type Response, type NextFunction } from 'express';
import * as path from 'node:path';
import * as fs from 'node:fs/promises';
import type { ApiResponse, ApiError } from '../types.ts';

// ---------------------------------------------------------------------------
// Extend Express Request with aidoPath
// ---------------------------------------------------------------------------

declare global {
  namespace Express {
    interface Request {
      aidoPath: string;
    }
  }
}

// ---------------------------------------------------------------------------
// Response helpers
// ---------------------------------------------------------------------------

export function sendOk<T>(res: Response, data: T, meta?: ApiResponse<T>['meta']): void {
  const response: ApiResponse<T> = { ok: true, data };
  if (meta) response.meta = meta;
  res.json(response);
}

export function sendError(
  res: Response,
  status: number,
  code: string,
  message: string,
  details?: unknown,
): void {
  const response: ApiError = {
    ok: false,
    error: { code, message, ...(details !== undefined && { details }) },
  };
  res.status(status).json(response);
}

export function send404(res: Response, resource: string): void {
  sendError(res, 404, 'NOT_FOUND', `${resource} not found`);
}

export function send400(res: Response, message: string): void {
  sendError(res, 400, 'BAD_REQUEST', message);
}

// ---------------------------------------------------------------------------
// Project resolution middleware
// ---------------------------------------------------------------------------

function resolveDefaultAidoPath(): string {
  if (process.env.AID_PROJECT_PATH) {
    return path.resolve(process.env.AID_PROJECT_PATH);
  }
  // Default: monorepo root .aid-o/
  return path.resolve(process.cwd(), '.aid-o');
}

/**
 * Middleware that resolves :projectId to an .aid-o/ directory path.
 *
 * For "default" projectId, uses the AID_PROJECT_PATH env var or the
 * monorepo root. Attaches the resolved path to req.aidoPath.
 */
export function projectResolver(req: Request, res: Response, next: NextFunction): void {
  const projectId = req.params.projectId;

  if (projectId === 'default') {
    req.aidoPath = resolveDefaultAidoPath();
    next();
    return;
  }

  // Future: look up in ~/.aid-gui/projects.json
  // For now, only "default" is supported
  sendError(res, 404, 'PROJECT_NOT_FOUND', `Project "${projectId}" not found. Use "default".`);
}

// ---------------------------------------------------------------------------
// Active run resolution
// ---------------------------------------------------------------------------

interface ActiveRun {
  epicId: string;
  runId: string;
  evidencePath: string;
}

let cachedActiveRun: { value: ActiveRun | null; expiresAt: number } | null = null;

/**
 * Find the active run (most recent running or completed run).
 * Caches result for 5 seconds to avoid repeated filesystem scans.
 */
export async function findActiveRun(aidoPath: string): Promise<ActiveRun | null> {
  const now = Date.now();
  if (cachedActiveRun && cachedActiveRun.expiresAt > now) {
    return cachedActiveRun.value;
  }

  let result: ActiveRun | null = null;

  // Strategy 1: Read auto-mode-state.yaml for current EPIC
  try {
    const statePath = path.join(aidoPath, '04-engine', 'auto-mode-state.yaml');
    const content = await fs.readFile(statePath, 'utf-8');
    const epicMatch = content.match(/current_epic_id:\s*(?:"([^"]+)"|(\S+))/);
    if (epicMatch) {
      const epicId = epicMatch[1] || epicMatch[2];
      if (epicId && epicId !== 'null') {
        // Find the latest run for this EPIC
        const epicDir = path.join(aidoPath, '04-engine', 'evidence', epicId);
        const runs = await fs.readdir(epicDir).catch(() => [] as string[]);
        const sortedRuns = runs.sort().reverse();
        if (sortedRuns.length > 0) {
          result = {
            epicId,
            runId: sortedRuns[0],
            evidencePath: path.join(epicDir, sortedRuns[0]),
          };
        }
      }
    }
  } catch {
    // Fall through to strategy 2
  }

  // Strategy 2: Find most recently modified evidence directory
  if (!result) {
    try {
      const evidencePath = path.join(aidoPath, '04-engine', 'evidence');
      const epicDirs = await fs.readdir(evidencePath).catch(() => [] as string[]);
      let latestMtime = 0;

      for (const epicDir of epicDirs) {
        if (epicDir.startsWith('FIRST-AID')) continue;
        const epicFullPath = path.join(evidencePath, epicDir);
        const stat = await fs.stat(epicFullPath).catch(() => null);
        if (!stat?.isDirectory()) continue;

        const runDirs = await fs.readdir(epicFullPath).catch(() => [] as string[]);
        for (const runDir of runDirs) {
          const runFullPath = path.join(epicFullPath, runDir);
          const runStat = await fs.stat(runFullPath).catch(() => null);
          if (runStat && runStat.mtimeMs > latestMtime) {
            latestMtime = runStat.mtimeMs;
            result = {
              epicId: epicDir,
              runId: runDir,
              evidencePath: runFullPath,
            };
          }
        }
      }
    } catch {
      // No evidence at all
    }
  }

  cachedActiveRun = { value: result, expiresAt: now + 5000 };
  return result;
}

/**
 * Invalidate the active run cache. Call after writes that may change the active run.
 */
export function invalidateActiveRunCache(): void {
  cachedActiveRun = null;
}
