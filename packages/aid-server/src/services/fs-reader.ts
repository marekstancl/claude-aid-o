/**
 * File-system reader service.
 * Reads and parses files from the .aid-o/ workspace.
 *
 * MED-2: All fs calls route through a module-level pLimit(16) to prevent
 * thundering herd during cold cross-project scans (277 runs × 6 projects).
 * See P047:547.
 */

import { readFile, readdir, stat, access } from 'node:fs/promises';
import { join, extname, relative } from 'node:path';
import yaml from 'js-yaml';
import pLimit from 'p-limit';
import type { ParseResult } from '@aid/contract';
import { parseJson, parseYaml, parseJsonl } from '../parsers/index.js';

/**
 * Module-level concurrency limiter for all fs.promises calls (MED-2 / P047:547).
 * Prevents thundering herd during cross-project scans.
 */
const fsLimit = pLimit(16);

export class FsReader {
  /**
   * `projectRoot` is OPTIONAL.
   *
   * - `new FsReader('/some/root')` — legacy single-project mode. The `aidoPath`
   *   getter and all existing routes/companion consumers keep working.
   * - `new FsReader()` — stateless multi-project mode (Phase 2). One instance
   *   serves every project; callers pass absolute paths per call. `aidoPath`
   *   is not available in this mode and throws if accessed.
   */
  constructor(private readonly projectRoot?: string) {}

  get aidoPath(): string {
    if (this.projectRoot === undefined) {
      throw new Error(
        'FsReader.aidoPath is unavailable: this instance was constructed without a projectRoot ' +
          '(stateless multi-project mode). Pass absolute paths to the read methods instead.',
      );
    }
    return join(this.projectRoot, '.aid-o');
  }

  async exists(path: string): Promise<boolean> {
    return fsLimit(async () => {
      try {
        await access(path);
        return true;
      } catch {
        return false;
      }
    });
  }

  async readText(path: string): Promise<string | null> {
    return fsLimit(async () => {
      try {
        return await readFile(path, 'utf-8');
      } catch {
        return null;
      }
    });
  }

  async readJson<T = unknown>(path: string): Promise<T | null> {
    const text = await this.readText(path);
    if (!text) return null;
    try {
      return JSON.parse(text) as T;
    } catch {
      return null;
    }
  }

  async readYaml<T = unknown>(path: string): Promise<T | null> {
    const text = await this.readText(path);
    if (!text) return null;
    try {
      return yaml.load(text) as T;
    } catch {
      return null;
    }
  }

  async readJsonl<T = unknown>(path: string): Promise<T[]> {
    const text = await this.readText(path);
    if (!text) return [];
    return text
      .split('\n')
      .filter((line) => line.trim())
      .map((line) => {
        try {
          return JSON.parse(line) as T;
        } catch {
          return null;
        }
      })
      .filter((item): item is T => item !== null);
  }

  async listDir(path: string): Promise<string[]> {
    return fsLimit(async () => {
      try {
        return await readdir(path);
      } catch {
        return [];
      }
    });
  }

  async listDirRecursive(dirPath: string): Promise<string[]> {
    const results: string[] = [];
    const entries = await this.listDir(dirPath);
    for (const entry of entries) {
      const full = join(dirPath, entry);
      const s = await fsLimit(async () => {
        try {
          return await stat(full);
        } catch {
          return null;
        }
      });
      if (s === null) continue;
      if (s.isDirectory()) {
        const sub = await this.listDirRecursive(full);
        results.push(...sub);
      } else {
        results.push(relative(dirPath, full));
      }
    }
    return results;
  }

  detectFormat(filePath: string): string {
    const ext = extname(filePath).toLowerCase();
    switch (ext) {
      case '.json': return 'json';
      case '.yaml':
      case '.yml': return 'yaml';
      case '.jsonl': return 'jsonl';
      case '.md': return 'markdown';
      default: return 'text';
    }
  }

  async readParsed(filePath: string): Promise<{ format: string; content: unknown }> {
    const format = this.detectFormat(filePath);
    switch (format) {
      case 'json': return { format, content: await this.readJson(filePath) };
      case 'yaml': return { format, content: await this.readYaml(filePath) };
      case 'jsonl': return { format, content: await this.readJsonl(filePath) };
      default: return { format, content: await this.readText(filePath) };
    }
  }

  // -------------------------------------------------------------------------
  // Phase 2 ADDITIVE methods (E-047-2_7, Step 4).
  //
  // These are NET-NEW and do NOT alter the raw read* methods above. They route
  // reads through the Step 1 tolerant parsers and return a full ParseResult
  // with snakeToCamel applied — for scanner/builder use. The never-throw
  // contract holds: a missing file yields { data: null/[], warnings, source }.
  // -------------------------------------------------------------------------

  /**
   * Return the last-modified time of a file as epoch milliseconds.
   *
   * Never throws. Returns `null` for a missing or inaccessible path. Used by
   * Steps 6/7/8 for latest-run selection, step timing, and the cache max-mtime
   * backstop.
   */
  async statMtime(path: string): Promise<number | null> {
    return fsLimit(async () => {
      try {
        const s = await stat(path);
        return s.mtimeMs;
      } catch {
        return null;
      }
    });
  }

  /**
   * Check if a path is a directory.
   *
   * Never throws. Returns `false` for a missing, inaccessible, or non-directory path.
   * Used by Steps 6/7 to filter directory entries during EPIC/run discovery.
   */
  async isDirectory(path: string): Promise<boolean> {
    return fsLimit(async () => {
      try {
        const s = await stat(path);
        return s.isDirectory();
      } catch {
        return false;
      }
    });
  }

  /**
   * Tolerant JSON read → ParseResult<T> with snakeToCamel applied.
   * Missing file → { data: null, warnings: [...], source: path } (no throw).
   */
  async readJsonParsed<T>(path: string): Promise<ParseResult<T>> {
    const text = await this.readText(path);
    if (text === null) {
      return {
        data: null,
        warnings: [{ message: `File not found or unreadable: ${path}`, severity: 'warning' }],
        source: path,
      };
    }
    return parseJson<T>(text, path);
  }

  /**
   * Tolerant YAML read → ParseResult<T> with snakeToCamel applied.
   * Missing file → { data: null, warnings: [...], source: path } (no throw).
   */
  async readYamlParsed<T>(path: string): Promise<ParseResult<T>> {
    const text = await this.readText(path);
    if (text === null) {
      return {
        data: null,
        warnings: [{ message: `File not found or unreadable: ${path}`, severity: 'warning' }],
        source: path,
      };
    }
    return parseYaml<T>(text, path);
  }

  /**
   * Tolerant JSONL read → ParseResult<T[]> with snakeToCamel applied.
   * Corrupt lines are skipped with per-line warnings (Step 1 parser).
   * Missing file → { data: [], warnings: [...], source: path } (no throw).
   */
  async readJsonlParsed<T>(path: string): Promise<ParseResult<T[]>> {
    const text = await this.readText(path);
    if (text === null) {
      return {
        data: [],
        warnings: [{ message: `File not found or unreadable: ${path}`, severity: 'warning' }],
        source: path,
      };
    }
    return parseJsonl<T>(text, path);
  }
}
