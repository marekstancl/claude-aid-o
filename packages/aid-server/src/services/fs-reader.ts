/**
 * File-system reader service.
 * Reads and parses files from the .aid-o/ workspace.
 */

import { readFile, readdir, stat, access } from 'node:fs/promises';
import { join, extname, relative } from 'node:path';
import yaml from 'js-yaml';

export class FsReader {
  constructor(private readonly projectRoot: string) {}

  get aidoPath(): string {
    return join(this.projectRoot, '.aid-o');
  }

  async exists(path: string): Promise<boolean> {
    try {
      await access(path);
      return true;
    } catch {
      return false;
    }
  }

  async readText(path: string): Promise<string | null> {
    try {
      return await readFile(path, 'utf-8');
    } catch {
      return null;
    }
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
    try {
      return await readdir(path);
    } catch {
      return [];
    }
  }

  async listDirRecursive(dirPath: string): Promise<string[]> {
    const results: string[] = [];
    const entries = await this.listDir(dirPath);
    for (const entry of entries) {
      const full = join(dirPath, entry);
      try {
        const s = await stat(full);
        if (s.isDirectory()) {
          const sub = await this.listDirRecursive(full);
          results.push(...sub);
        } else {
          results.push(relative(dirPath, full));
        }
      } catch {
        // skip inaccessible
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
}
