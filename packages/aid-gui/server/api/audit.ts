/**
 * Audit report routes.
 *
 * GET  /          — List all audit reports across all EPICs
 * GET  /:epicId   — Audit report for a specific EPIC
 *
 * Scans `{req.aidoPath}/work/evidence/` for audit-report.yaml and
 * audit-report.md files.
 */

import { Router, type Request, type Response } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { sendOk, send404, sendError } from './middleware.ts';
import { parseYaml, parseMarkdownWithFrontmatter } from '../parsers/index.ts';
import type { AuditReport } from '../types.ts';

const router = Router();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const AUDIT_FILENAMES = ['audit-report.yaml', 'audit-report.md'];

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
 * Extract the epicId from an audit report file path.
 *
 * Expected structures:
 *   .../evidence/{epicId}/audit-report.yaml
 *   .../evidence/{epicId}/{runId}/audit-report.yaml
 *
 * Returns the first directory segment after "evidence".
 */
function extractEpicId(filePath: string): string | null {
  const parts = filePath.split(path.sep);
  const evidenceIdx = parts.lastIndexOf('evidence');
  if (evidenceIdx === -1 || evidenceIdx + 1 >= parts.length) {
    return null;
  }
  return parts[evidenceIdx + 1];
}

/**
 * Parse an audit report file into an AuditReport object.
 *
 * Handles both .yaml and .md formats. Returns null if parsing fails or
 * produces no meaningful data.
 */
async function parseAuditFile(filePath: string): Promise<AuditReport | null> {
  let content: string;
  try {
    content = await fs.readFile(filePath, 'utf-8');
  } catch {
    return null;
  }

  const ext = path.extname(filePath).toLowerCase();

  if (ext === '.yaml' || ext === '.yml') {
    const result = parseYaml<AuditReport>(content, filePath);
    return result.data ?? null;
  }

  if (ext === '.md') {
    const result = parseMarkdownWithFrontmatter<AuditReport>(content, filePath);
    if (!result.data) return null;
    // The frontmatter contains the structured audit data; the body is the
    // prose narrative. Merge them so the frontmatter fields are top-level.
    const { frontmatter } = result.data;
    if (!frontmatter) return null;
    return frontmatter;
  }

  return null;
}

// ---------------------------------------------------------------------------
// GET / — List all audit reports
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response): Promise<void> => {
  try {
    const evidenceDir = path.join(req.aidoPath, 'work', 'evidence');
    const auditFiles = await findFilesRecursive(evidenceDir, AUDIT_FILENAMES);

    const reports: AuditReport[] = [];

    for (const filePath of auditFiles) {
      const report = await parseAuditFile(filePath);
      if (!report) continue;

      // Enrich with epicId from path if not already present.
      if (!report.epicId) {
        const epicId = extractEpicId(filePath);
        if (epicId) {
          report.epicId = epicId;
        }
      }

      reports.push(report);
    }

    // Sort by timestamp descending (newest first). Missing timestamps go last.
    reports.sort((a, b) => {
      const ta = a.timestamp ?? '';
      const tb = b.timestamp ?? '';
      return tb.localeCompare(ta);
    });

    sendOk(res, reports, { total: reports.length });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error reading audit reports';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// GET /:epicId — Audit report for a specific EPIC
// ---------------------------------------------------------------------------

router.get('/:epicId', async (req: Request, res: Response): Promise<void> => {
  try {
    const epicId = req.params.epicId;
    if (!epicId) {
      send404(res, 'Audit report');
      return;
    }

    const epicEvidenceDir = path.join(req.aidoPath, 'work', 'evidence', epicId);

    // Verify the EPIC evidence directory exists.
    try {
      const stat = await fs.stat(epicEvidenceDir);
      if (!stat.isDirectory()) {
        send404(res, `Audit report for EPIC "${epicId}"`);
        return;
      }
    } catch {
      send404(res, `Audit report for EPIC "${epicId}"`);
      return;
    }

    // Search for audit report files in the EPIC directory and its subdirectories.
    const auditFiles = await findFilesRecursive(epicEvidenceDir, AUDIT_FILENAMES);

    if (auditFiles.length === 0) {
      send404(res, `Audit report for EPIC "${epicId}"`);
      return;
    }

    // Parse the first valid audit report found.
    for (const filePath of auditFiles) {
      const report = await parseAuditFile(filePath);
      if (report) {
        // Enrich with epicId if not present.
        if (!report.epicId) {
          report.epicId = epicId;
        }
        sendOk(res, report);
        return;
      }
    }

    // All files found but none parsed successfully.
    send404(res, `Audit report for EPIC "${epicId}"`);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error reading audit report';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

export default router;
