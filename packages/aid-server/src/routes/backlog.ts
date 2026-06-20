/**
 * Cross-project backlog read route (EPIC E-047-3_7, Step 7).
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api` by the bootstrap:
 *   - `GET /api/backlog?project=<id>` → `BacklogItem[]` (CURRENT rows) +
 *     `meta.openCount` / `meta.closedCount` / `meta.warnings`.
 *
 * Honesty contract (§5.7 / Phase-2 lesson — NEVER fabricate):
 *  - Counts are derived from the ACTUAL parsed rows, NOT from any declared
 *    counter in the file. ABSOLUTE counts only — there is NO delta and NO write.
 *  - When a frontmatter counter (`open_count` / `closed_count`) DISAGREES with
 *    the real row counts, the real counts win and a `meta.warnings` note records
 *    the discrepancy. A stale counter never produces a fabricated number.
 *  - A missing/empty backlog yields `[]` + `openCount:0` + `closedCount:0` (a
 *    truthful "nothing here", distinguished by a warning when the file is absent).
 *  - There is deliberately NO `/api/backlog-delta` endpoint (delta is out of
 *    scope for the current-rows surface).
 *
 * Module: src/routes/backlog.ts
 */

import { Router } from 'express';
import { join } from 'node:path';
import type { BacklogItem } from '@aid/contract';
import type { ScannerCache } from '../services/scanner-cache.js';
import { FsReader } from '../services/fs-reader.js';
import { sendOk, send400, send404 } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';

/** Current time as an ISO 8601 string (scan marker for `meta`). */
function isoNow(): string {
  return new Date().toISOString();
}

/** Status values that count as "closed" (case-insensitive). */
const CLOSED_STATUSES = new Set(['done', 'closed', 'resolved', 'fixed', 'complete', 'completed']);

/**
 * Parse a markdown table from `work/backlog.md` into {@link BacklogItem}[].
 *
 * Tolerant: a row's columns are matched positionally, with the first cell taken
 * as the id, a Status-like column (when present) as status, and the remaining
 * text as the title. The whole row's source text is preserved in `raw`. The
 * header row and the `|---|` separator are skipped. Never throws.
 */
function parseBacklogTable(text: string, projectId: string): BacklogItem[] {
  const items: BacklogItem[] = [];
  const lines = text.split('\n');

  // Locate the header row to learn which column holds the status (best-effort).
  let statusCol = -1;
  let titleCol = -1;
  let idCol = 0;
  let headerSeen = false;

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('|')) continue;
    if (/^\|[\s:|-]+\|?$/.test(trimmed)) continue; // separator row (|---|---|)

    const cells = splitRow(trimmed);
    if (cells.length === 0) continue;

    if (!headerSeen) {
      // First table-ish line is treated as the header — map known columns.
      headerSeen = true;
      cells.forEach((c, i) => {
        const lc = c.toLowerCase();
        if (lc === 'status') statusCol = i;
        if (lc === 'description' || lc === 'title' || lc === 'item') titleCol = i;
        if (lc === '#' || lc === 'id' || lc === 'no') idCol = i;
      });
      // If the first cell wasn't a recognizable id header, it is a data row.
      const first = cells[idCol]?.toLowerCase() ?? '';
      if (first !== '#' && first !== 'id' && first !== 'no' && first !== 'status' &&
          first !== 'type' && first !== 'description' && first !== 'title' && first !== 'item') {
        // Not a header — re-process this line as data below by falling through.
        items.push(rowToItem(cells, projectId, idCol, statusCol, titleCol, trimmed));
      }
      continue;
    }

    items.push(rowToItem(cells, projectId, idCol, statusCol, titleCol, trimmed));
  }

  return items;
}

/** Split a markdown table row into trimmed, non-empty cell texts. */
function splitRow(row: string): string[] {
  return row
    .split('|')
    .slice(1, -1) // drop the empty leading/trailing splits around the pipes
    .map((c) => c.trim());
}

/** Map one parsed row to a {@link BacklogItem} (never throws). */
function rowToItem(
  cells: string[],
  projectId: string,
  idCol: number,
  statusCol: number,
  titleCol: number,
  raw: string,
): BacklogItem {
  const id = cells[idCol]?.length ? cells[idCol] : null;
  const status = statusCol >= 0 && cells[statusCol]?.length ? cells[statusCol] : null;
  // Title: the configured title column, else the longest remaining cell.
  let title = titleCol >= 0 ? (cells[titleCol] ?? '') : '';
  if (title === '') {
    title = cells
      .filter((_, i) => i !== idCol && i !== statusCol)
      .sort((a, b) => b.length - a.length)[0] ?? '';
  }
  return { projectId, id, title, status, raw };
}

/** Count open vs closed from the ACTUAL rows (status-driven; never fabricated). */
function countRows(items: BacklogItem[]): { openCount: number; closedCount: number } {
  let closedCount = 0;
  for (const it of items) {
    const s = (it.status ?? '').toLowerCase();
    if (CLOSED_STATUSES.has(s)) closedCount += 1;
  }
  return { openCount: items.length - closedCount, closedCount };
}

/**
 * Detect a DECLARED counter in the file's frontmatter (`open_count` /
 * `closed_count` or `open`/`closed`) and, when it disagrees with the real row
 * counts, return a warning. The real counts always win — a stale counter never
 * overrides them (§5.7 anti-fabrication). Returns [] when no counter is declared
 * or when it matches reality.
 */
function staleCounterWarnings(
  text: string,
  actual: { openCount: number; closedCount: number },
): string[] {
  const warnings: string[] = [];
  const fm = text.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!fm) return warnings;

  const declaredOpen = readCounter(fm[1], /(?:^|\n)\s*open(?:_count)?\s*:\s*(\d+)\s*(?:\n|$)/i);
  const declaredClosed = readCounter(fm[1], /(?:^|\n)\s*closed(?:_count)?\s*:\s*(\d+)\s*(?:\n|$)/i);

  if (declaredOpen !== null && declaredOpen !== actual.openCount) {
    warnings.push(
      `backlog frontmatter declares open_count:${declaredOpen} but ${actual.openCount} open row(s) are present — using the actual row count (declared counter is stale)`,
    );
  }
  if (declaredClosed !== null && declaredClosed !== actual.closedCount) {
    warnings.push(
      `backlog frontmatter declares closed_count:${declaredClosed} but ${actual.closedCount} closed row(s) are present — using the actual row count (declared counter is stale)`,
    );
  }
  return warnings;
}

/** Read a single integer counter via the given regex, or null when absent. */
function readCounter(fmText: string, re: RegExp): number | null {
  const m = fmText.match(re);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  return Number.isFinite(n) ? n : null;
}

/**
 * Build the backlog read router backed by the Phase-2 {@link ScannerCache}. A
 * stateless {@link FsReader} performs the single backlog.md read.
 */
export function backlogRoutes(scanner: ScannerCache): Router {
  const router = Router();
  const fs = new FsReader();

  // -------------------------------------------------------------------------
  // GET /backlog?project=<id> — current BacklogItem[] + open/closed counts.
  // -------------------------------------------------------------------------
  router.get('/backlog', async (req, res) => {
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

    const backlogPath = join(indexed.aidoPath, 'work', 'backlog.md');
    const text = await fs.readText(backlogPath);

    if (text === null || text.trim().length === 0) {
      sendOk(res, [] as BacklogItem[], {
        scannedAt: isoNow(),
        partialProjects: [],
        total: 0,
        openCount: 0,
        closedCount: 0,
        warnings: ['no work/backlog.md for this project'],
      });
      return;
    }

    const items = parseBacklogTable(text, projectId);
    const counts = countRows(items);
    const warnings = staleCounterWarnings(text, counts);

    sendOk(res, items, {
      scannedAt: isoNow(),
      partialProjects: [],
      total: items.length,
      openCount: counts.openCount,
      closedCount: counts.closedCount,
      warnings,
    });
  });

  return router;
}
