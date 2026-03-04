/**
 * Build AI SDK tools that give the companion the ability to explore the project.
 *
 * Uses the Vercel AI SDK `tool()` helper + zod schemas.  These are passed to
 * `streamText({ tools })` so the model can call them mid-response.
 */

import { join, resolve, relative } from 'node:path';
import { FsReader } from '../services/fs-reader.js';
import type { CompanionTools } from './types.js';

/**
 * Build tools scoped to a specific project root.
 *
 * All file operations are sandboxed — paths are resolved relative to
 * `projectRoot` and prevented from escaping.
 */
export async function buildCompanionTools(
  projectRoot: string,
  fs: FsReader,
): Promise<CompanionTools> {
  // Dynamic imports — `ai` and `zod` are optional deps
  const zodPkg = 'zod';
  const { z } = await import(/* @vite-ignore */ zodPkg);
  const aiPkg = 'ai';
  const { tool } = await import(/* @vite-ignore */ aiPkg);

  /** Resolve path safely within project root. Returns null if escaping. */
  const safePath = (userPath: string): string | null => {
    const resolved = resolve(projectRoot, userPath);
    if (!resolved.startsWith(projectRoot)) return null;
    // Block node_modules, .git
    const rel = relative(projectRoot, resolved);
    if (rel.startsWith('node_modules') || rel.startsWith('.git/') || rel === '.git') {
      return null;
    }
    return resolved;
  };

  return {
    readFile: tool({
      description:
        'Read the contents of a file in the project. Use relative paths from project root. Returns the file text or an error message.',
      parameters: z.object({
        path: z
          .string()
          .describe('Relative path from project root, e.g. "src/index.ts" or "CLAUDE.md"'),
      }),
      execute: async ({ path }: { path: string }) => {
        const abs = safePath(path);
        if (!abs) return `Error: path "${path}" is outside the project or blocked.`;
        const content = await fs.readText(abs);
        if (content === null) return `File not found: ${path}`;
        // Limit to 8000 chars to avoid blowing up context
        if (content.length > 8000) {
          return content.slice(0, 8000) + `\n\n... (truncated, ${content.length} chars total)`;
        }
        return content;
      },
    }),

    listDirectory: tool({
      description:
        'List files and subdirectories in a directory. Returns names only (not contents). Use to explore project structure.',
      parameters: z.object({
        path: z
          .string()
          .default('.')
          .describe('Relative path from project root, e.g. "src" or "packages/aid-gui/src"'),
      }),
      execute: async ({ path }: { path: string }) => {
        const abs = safePath(path);
        if (!abs) return `Error: path "${path}" is outside the project or blocked.`;
        const entries = await fs.listDir(abs);
        if (entries.length === 0) return `Empty or not found: ${path}`;
        return entries.join('\n');
      },
    }),

    searchContent: tool({
      description:
        'Search for a text pattern across project files. Returns matching file paths and line snippets. Use for finding functions, variables, imports, etc.',
      parameters: z.object({
        pattern: z.string().describe('Text or regex pattern to search for'),
        directory: z
          .string()
          .default('.')
          .describe('Directory to search in (relative to project root)'),
      }),
      execute: async ({ pattern, directory }: { pattern: string; directory: string }) => {
        const abs = safePath(directory);
        if (!abs) return `Error: path "${directory}" is outside the project or blocked.`;

        // Use a simple recursive file search since we don't have ripgrep
        const results: string[] = [];
        const regex = new RegExp(pattern, 'i');

        const searchDir = async (dir: string, depth: number) => {
          if (depth > 5 || results.length > 30) return;
          const entries = await fs.listDir(dir);
          for (const entry of entries) {
            if (entry === 'node_modules' || entry === '.git' || entry === 'dist' || entry === 'coverage') continue;
            const fullPath = join(dir, entry);
            const exists = await fs.exists(fullPath);
            if (!exists) continue;

            // Try as file first
            const content = await fs.readText(fullPath);
            if (content !== null) {
              const lines = content.split('\n');
              for (let i = 0; i < lines.length; i++) {
                if (regex.test(lines[i])) {
                  const relPath = relative(projectRoot, fullPath);
                  results.push(`${relPath}:${i + 1}: ${lines[i].trim().slice(0, 120)}`);
                  if (results.length > 30) return;
                  break; // One match per file
                }
              }
            } else {
              // Might be a directory
              await searchDir(fullPath, depth + 1);
            }
          }
        };

        await searchDir(abs, 0);
        if (results.length === 0) return `No matches found for "${pattern}" in ${directory}`;
        return results.join('\n');
      },
    }),

    readYaml: tool({
      description:
        'Read and parse a YAML file from the project. Returns the parsed content as formatted text. Good for .aid-o/ config files.',
      parameters: z.object({
        path: z
          .string()
          .describe('Relative path to YAML file, e.g. ".aid-o/config/queue.yaml"'),
      }),
      execute: async ({ path }: { path: string }) => {
        const abs = safePath(path);
        if (!abs) return `Error: path "${path}" is outside the project or blocked.`;
        const data = await fs.readYaml<unknown>(abs);
        if (data === null) return `File not found or invalid YAML: ${path}`;
        const text = JSON.stringify(data, null, 2);
        if (text.length > 6000) {
          return text.slice(0, 6000) + `\n\n... (truncated)`;
        }
        return text;
      },
    }),

    readEpic: tool({
      description:
        'Read the full content of an EPIC specification from .aid-o/tasks/. Pass just the filename.',
      parameters: z.object({
        filename: z
          .string()
          .describe('EPIC filename, e.g. "E-017.md"'),
      }),
      execute: async ({ filename }: { filename: string }) => {
        const abs = join(fs.aidoPath, 'tasks', filename);
        if (!abs.startsWith(fs.aidoPath)) return 'Error: invalid path';
        const content = await fs.readText(abs);
        if (!content) return `EPIC not found: ${filename}`;
        if (content.length > 8000) {
          return content.slice(0, 8000) + `\n\n... (truncated, ${content.length} chars total)`;
        }
        return content;
      },
    }),

    readPlan: tool({
      description:
        'Read the full content of a plan from .aid-o/plans/. Pass just the filename.',
      parameters: z.object({
        filename: z
          .string()
          .describe('Plan filename, e.g. "plan-001.md"'),
      }),
      execute: async ({ filename }: { filename: string }) => {
        const abs = join(fs.aidoPath, 'plans', filename);
        if (!abs.startsWith(fs.aidoPath)) return 'Error: invalid path';
        const content = await fs.readText(abs);
        if (!content) return `Plan not found: ${filename}`;
        if (content.length > 8000) {
          return content.slice(0, 8000) + `\n\n... (truncated, ${content.length} chars total)`;
        }
        return content;
      },
    }),

    getPipelineState: tool({
      description:
        'Get the current pipeline state including FSM state, current EPIC, steps, aggregate stats, and escalation info.',
      parameters: z.object({}),
      execute: async () => {
        const autoState = await fs.readYaml<any>(join(fs.aidoPath, 'work', 'auto-mode-state.yaml'));
        const queue = await fs.readYaml<any>(join(fs.aidoPath, 'config', 'queue.yaml'));

        if (!autoState?.session) return 'No active pipeline session.';

        const s = autoState.session;
        const agg = s.aggregate ?? {};
        const queueItems = queue?.queue ?? [];

        return JSON.stringify({
          currentState: s.progress?.current_state ?? 'IDLE',
          currentEpic: s.progress?.current_epic_id ?? null,
          currentStep: s.progress?.current_step_id ?? null,
          mode: s.mode,
          escalation: s.escalation,
          aggregate: agg,
          queue: queueItems.map((e: any) => ({
            epicId: e.epic_id,
            status: e.status,
            priority: e.priority,
          })),
        }, null, 2);
      },
    }),
  };
}
