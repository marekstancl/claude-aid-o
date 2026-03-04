/**
 * Express router for EPIC specification endpoints.
 *
 * GET /         — List all EPICs (summary entries)
 * GET /:epicId  — Full parsed EPIC specification
 *
 * Source directory: `{aidoPath}/tasks/`
 */

import { Router } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { sendOk, send404 } from './middleware.ts';
import { parseEpicSpec } from '../parsers/index.ts';
import type { EpicListEntry, EpicSpec } from '../types.ts';

const router = Router();

// ---------------------------------------------------------------------------
// GET / — List all EPICs
// ---------------------------------------------------------------------------

router.get('/', async (req, res) => {
  const epicsDir = path.join(req.aidoPath, 'tasks');

  let files: string[];
  try {
    files = await fs.readdir(epicsDir);
  } catch {
    // Directory does not exist or is unreadable — return empty list.
    sendOk<EpicListEntry[]>(res, [], { total: 0 });
    return;
  }

  const mdFiles = files.filter(
    (f) => f.endsWith('.md') && !f.startsWith('.'),
  );

  if (mdFiles.length === 0) {
    sendOk<EpicListEntry[]>(res, [], { total: 0 });
    return;
  }

  const entries: EpicListEntry[] = [];
  const warnings: string[] = [];

  for (const file of mdFiles) {
    const filePath = path.join(epicsDir, file);
    try {
      const content = await fs.readFile(filePath, 'utf-8');
      const result = parseEpicSpec(content, filePath);

      if (result.data) {
        entries.push({
          epicId: file.replace(/\.md$/, ''),
          title: result.data.title || file.replace(/\.md$/, ''),
          status: result.data.status || 'unknown',
          planRef: result.data.planRef || '',
        });
      } else {
        warnings.push(`Failed to parse ${file}`);
      }

      // Collect parser warnings.
      for (const w of result.warnings) {
        if (w.severity === 'error') {
          warnings.push(`${file}: ${w.message}`);
        }
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      warnings.push(`Error reading ${file}: ${msg}`);
    }
  }

  sendOk<EpicListEntry[]>(res, entries, {
    total: entries.length,
    ...(warnings.length > 0 && { warnings }),
  });
});

// ---------------------------------------------------------------------------
// GET /:epicId — Single EPIC detail
// ---------------------------------------------------------------------------

router.get('/:epicId', async (req, res) => {
  const { epicId } = req.params;
  const filePath = path.join(req.aidoPath, 'tasks', `${epicId}.md`);

  let content: string;
  try {
    content = await fs.readFile(filePath, 'utf-8');
  } catch {
    send404(res, `EPIC "${epicId}"`);
    return;
  }

  const result = parseEpicSpec(content, filePath);

  if (!result.data) {
    send404(res, `EPIC "${epicId}" (parse failed)`);
    return;
  }

  const warnings =
    result.warnings.length > 0
      ? result.warnings.map((w) => w.message)
      : undefined;

  sendOk<EpicSpec>(res, result.data, {
    ...(warnings && { warnings }),
  });
});

export default router;
