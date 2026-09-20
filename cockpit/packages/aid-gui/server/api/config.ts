/**
 * Express router for configuration file endpoints.
 *
 * GET / — Config summary (all parsed YAML config files)
 *
 * Source directory: `{aidoPath}/config/`
 */

import { Router } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { sendOk } from './middleware.ts';
import { parseYaml } from '../parsers/index.ts';
import type { ConfigSummary } from '../types.ts';

const router = Router();

/** File extensions to skip (backup / temporary files). */
const SKIP_EXTENSIONS = ['.bak', '.tmp'];

/**
 * Check whether a filename should be skipped.
 */
function isBackupFile(filename: string): boolean {
  return SKIP_EXTENSIONS.some((ext) => filename.endsWith(ext));
}

/**
 * Check whether a filename is a YAML file.
 */
function isYamlFile(filename: string): boolean {
  return filename.endsWith('.yaml') || filename.endsWith('.yml');
}

// ---------------------------------------------------------------------------
// GET / — Config summary
// ---------------------------------------------------------------------------

router.get('/', async (req, res) => {
  const configDir = path.join(req.aidoPath, 'config');

  let files: string[];
  try {
    files = await fs.readdir(configDir);
  } catch {
    // Directory does not exist or is unreadable — return empty config.
    const empty: ConfigSummary = { files: [] };
    sendOk<ConfigSummary>(res, empty, { total: 0 });
    return;
  }

  const yamlFiles = files.filter(
    (f) => isYamlFile(f) && !isBackupFile(f) && !f.startsWith('.'),
  );

  if (yamlFiles.length === 0) {
    const empty: ConfigSummary = { files: [] };
    sendOk<ConfigSummary>(res, empty, { total: 0 });
    return;
  }

  const configFiles: ConfigSummary['files'] = [];
  const warnings: string[] = [];

  for (const file of yamlFiles) {
    const filePath = path.join(configDir, file);
    try {
      const content = await fs.readFile(filePath, 'utf-8');
      const result = parseYaml<unknown>(content, filePath);

      configFiles.push({
        filename: file,
        parsed: result.data,
      });

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

  const summary: ConfigSummary = { files: configFiles };

  sendOk<ConfigSummary>(res, summary, {
    total: configFiles.length,
    ...(warnings.length > 0 && { warnings }),
  });
});

export default router;
