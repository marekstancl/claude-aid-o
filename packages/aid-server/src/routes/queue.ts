/**
 * Cross-project queue read route (EPIC E-047-3_7, Step 7).
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api` by the bootstrap:
 *   - `GET /api/queue?project=<id>` → `QueueEntry[]` (read straight from
 *     `config/queue.yaml`, camelCased).
 *
 * This is the rewritten MVP1 Phase 3 surface. The old single-project queue route
 * exposed MUTATIONS (`PUT /:epicId`, `PUT /schedule`, `POST /launch`) — those are
 * DELIBERATELY DROPPED here: the cross-project cockpit is read-only, so this file
 * defines ONLY `router.get`. There is no write path, no scheduler config, and no
 * launch trigger.
 *
 * Every response uses the standard envelope. A missing `project` query param or a
 * traversal value yields 400; an unknown project yields 404 — both through the
 * envelope. A project with no `queue.yaml` yields `[]` (truthful empty, never an
 * error).
 *
 * Module: src/routes/queue.ts
 */

import { Router } from 'express';
import { join } from 'node:path';
import type { QueueEntry } from '@aid/contract';
import type { ScannerCache } from '../services/scanner-cache.js';
import { FsReader } from '../services/fs-reader.js';
import { sendOk, send400, send404, isoNow } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';

/** Coerce an unknown to a non-empty string, else null. */
function asString(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

/**
 * Read `config/queue.yaml` into {@link QueueEntry}[] (camelCased). Never throws —
 * a missing/unreadable queue yields `[]`. Uses the tolerant parser so a corrupt
 * file surfaces a warning but does not present an empty queue as "genuinely empty".
 */
async function readQueue(
  fs: FsReader,
  aidoPath: string,
): Promise<{ entries: QueueEntry[]; warning?: string }> {
  const queuePath = join(aidoPath, 'config', 'queue.yaml');
  const parsed = await fs.readYamlParsed<{ queue?: unknown[] }>(queuePath);

  // Honesty: if the parse failed (warnings with severity 'error'), surface that.
  const hasError = parsed.warnings?.some((w) => w.severity === 'error');
  const warning = hasError
    ? `queue.yaml unparseable: ${parsed.warnings?.find((w) => w.severity === 'error')?.message ?? 'unknown error'}`
    : undefined;

  // If parsing failed, return empty with warning (not an error, but flagged).
  if (parsed.data === null) {
    return { entries: [], warning };
  }

  const rows = Array.isArray(parsed.data.queue) ? parsed.data.queue : [];
  const out: QueueEntry[] = [];
  for (const r of rows) {
    if (typeof r !== 'object' || r === null) continue;
    const e = r as Record<string, unknown>;
    out.push({
      epicId: asString(e.epic_id ?? e.epicId) ?? '',
      path: asString(e.path) ?? '',
      priority: asString(e.priority) ?? 'medium',
      status: asString(e.status) ?? 'queued',
      addedAt: asString(e.added_at ?? e.addedAt) ?? '',
    });
  }
  return { entries: out, warning };
}

/**
 * Build the READ-ONLY queue router backed by the Phase-2 {@link ScannerCache}.
 * GET only — no mutation endpoints exist on this surface.
 */
export function queueRoutes(scanner: ScannerCache): Router {
  const router = Router();
  const fs = new FsReader();

  // -------------------------------------------------------------------------
  // GET /queue?project=<id> — read-only QueueEntry[].
  // -------------------------------------------------------------------------
  router.get('/queue', async (req, res) => {
    const projectId = typeof req.query.project === 'string' ? req.query.project : '';
    if (projectId === '' || !isValidPathComponent(projectId)) {
      send400(res, 'Query param "project" is required and must be a valid path component');
      return;
    }

    const idx = await scanner.getIndex();
    const indexed = idx.projects.get(projectId) ?? null;
    if (indexed === null) {
      send404(res, `Project "${projectId}"`);
      return;
    }

    const { entries, warning } = await readQueue(fs, indexed.aidoPath);
    const partialProjects = warning ? [projectId] : [];
    sendOk(res, entries, {
      scannedAt: isoNow(),
      partialProjects,
      total: entries.length,
      ...(warning ? { warnings: [warning] } : {}),
    });
  });

  return router;
}
