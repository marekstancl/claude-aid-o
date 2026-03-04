/**
 * Chokidar-based file watcher for the `.aid-o/` directory tree.
 *
 * Watches the `.aid-o/` root directory recursively, debounces rapid changes
 * at 50ms, classifies each changed file into a semantic EventTopic using
 * regex-based path rules, parses the file content using the appropriate
 * parser, and emits typed FileChangeEvent objects via Node.js EventEmitter.
 *
 * Stage log files (`timeline.jsonl`) are explicitly excluded from this
 * watcher — they are handled by the dedicated StageLogStream (tail-follow).
 *
 * Module: server/watchers/file-watcher.ts
 * Depends on: server/parsers/, server/types.ts
 */

import { EventEmitter } from 'node:events';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import chokidar, { type FSWatcher as ChokidarFSWatcher } from 'chokidar';
import type {
  EventTopic,
  FileChangeEvent,
  PathClassification,
  WatcherOptions,
} from '../types.ts';
import {
  parseYaml,
  parseJson,
  parseMarkdownWithFrontmatter,
  parseEpicSpec,
} from '../parsers/index.ts';

// ---------------------------------------------------------------------------
// Path Classification Rules
// ---------------------------------------------------------------------------

/**
 * Classification rules evaluated in order. First match wins.
 *
 * The pattern operates on the relative path from the `.aid-o/` root,
 * using forward slashes regardless of platform.
 */
const PATH_RULES: ReadonlyArray<{
  pattern: RegExp;
  classification: PathClassification;
}> = [
  // Priority 1: Stage log — excluded from file watcher (handled by streamer)
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/timeline\.jsonl$/,
    classification: { topic: 'pipeline.stage_log', parser: 'jsonl', excluded: true },
  },
  // Priority 2: Pipeline state (FSM state, current EPIC/step)
  {
    pattern: /^work\/auto-mode-state\.yaml$/,
    classification: { topic: 'pipeline', parser: 'yaml', excluded: false },
  },
  // Priority 3: Per-run progress tracking
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/state\.yaml$/,
    classification: { topic: 'pipeline', parser: 'yaml', excluded: false },
  },
  // Priority 4: Execution plan (initial load)
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/plan\.json$/,
    classification: { topic: 'pipeline', parser: 'json', excluded: false },
  },
  // Priority 5: Queue state and ordering
  {
    pattern: /^config\/queue\.yaml$/,
    classification: { topic: 'queue', parser: 'yaml', excluded: false },
  },
  // Priority 6-8: Decision records (merge, plan approval, escalation)
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/pm_(decision|plan_approval|merge_approval)\.json$/,
    classification: { topic: 'decisions', parser: 'json', excluded: false },
  },
  // Priority 9-10: Gate reports (both paths)
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/(gates\/)?gates_report\.json$/,
    classification: { topic: 'pipeline', parser: 'json', excluded: false },
  },
  // Priority 11-13: Audit reports (YAML and Markdown, at EPIC or run level)
  // Parser is determined at runtime based on file extension.
  {
    pattern: /^work\/evidence(\/[^/]+){1,2}\/audit-report\.(yaml|md)$/,
    classification: { topic: 'audit', parser: null, excluded: false },
  },
  // Priority 14-16: Evidence catch-all (reports, step outputs, etc.)
  {
    pattern: /^work\/evidence\//,
    classification: { topic: 'evidence', parser: null, excluded: false },
  },
  // Priority 17: Configuration files
  {
    pattern: /^config\//,
    classification: { topic: 'config', parser: null, excluded: false },
  },
  // Priority 18: Task spec changes
  {
    pattern: /^tasks\/.*\.md$/,
    classification: { topic: 'pipeline', parser: 'epicSpec', excluded: false },
  },
  // Priority 19-20: Plan documents and IDEAS
  {
    pattern: /^plans\//,
    classification: { topic: 'config', parser: 'markdown', excluded: false },
  },
  // Priority 21: Run specification files
  {
    pattern: /^work\/runs\//,
    classification: { topic: 'pipeline', parser: null, excluded: false },
  },
  // Priority 22: Engine knowledge base (catch-all for work/ not matched above)
  {
    pattern: /^work\//,
    classification: { topic: 'config', parser: null, excluded: false },
  },
];

// ---------------------------------------------------------------------------
// Default ignore patterns
// ---------------------------------------------------------------------------

/** File patterns that the watcher always ignores. */
const DEFAULT_IGNORE_PATTERNS: string[] = [
  '**/node_modules/**',
  '**/.git/**',
  '**/*.tmp',
  '**/*.swp',
  '**/*.png',
  '**/*.jpg',
  '**/*.gif',
  '**/*.zip',
  '**/*.tar',
  '**/*.gz',
];

// ---------------------------------------------------------------------------
// FileWatcher class
// ---------------------------------------------------------------------------

/**
 * Watches the `.aid-o/` directory tree for file changes, classifies each
 * change into a semantic topic, parses the file content, and emits typed
 * FileChangeEvent objects.
 *
 * Usage:
 * ```typescript
 * const watcher = new FileWatcher('/path/to/.aid-o');
 * watcher.on('event', (event: FileChangeEvent) => {
 *   console.log(`[${event.topic}] ${event.changeType}: ${event.filePath}`);
 * });
 * await watcher.start();
 * // ... later
 * await watcher.stop();
 * ```
 *
 * Events emitted:
 * - `'event'`  — a FileChangeEvent for every classified, non-excluded file change.
 * - `'error'`  — an Error when the watcher encounters a fatal problem.
 * - `'ready'`  — emitted once Chokidar has finished the initial scan.
 */
export class FileWatcher extends EventEmitter {
  /** Absolute path to the `.aid-o/` directory being watched. */
  private readonly aidoPath: string;

  /** Merged ignore patterns (defaults + user-supplied). */
  private readonly ignorePatterns: string[];

  /** Debounce threshold in milliseconds. */
  private readonly debounceMs: number;

  /** Chokidar watcher instance. Null when not started. */
  private watcher: ChokidarFSWatcher | null = null;

  /**
   * Debounce timers keyed by absolute file path.
   * Each timer delays event emission until the file has been stable for
   * `debounceMs` milliseconds.
   */
  private debounceTimers: Map<string, ReturnType<typeof setTimeout>> = new Map();

  constructor(aidoPath: string, options?: WatcherOptions) {
    super();
    this.aidoPath = path.resolve(aidoPath);
    this.debounceMs = options?.debounceMs ?? 50;
    this.ignorePatterns = [
      ...DEFAULT_IGNORE_PATTERNS,
      ...(options?.ignorePatterns ?? []),
    ];
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /**
   * Start watching the `.aid-o/` directory tree.
   *
   * Initializes a Chokidar watcher with debounced `awaitWriteFinish` and
   * the configured ignore patterns. Resolves when Chokidar reports `ready`.
   */
  async start(): Promise<void> {
    if (this.watcher) {
      return; // Already started.
    }

    this.watcher = chokidar.watch(this.aidoPath, {
      persistent: true,
      ignoreInitial: true,
      ignored: this.ignorePatterns,
      awaitWriteFinish: {
        stabilityThreshold: this.debounceMs,
        pollInterval: Math.max(10, Math.floor(this.debounceMs / 5)),
      },
      // Follow symlinks is off by default; keep it off for safety.
      followSymlinks: false,
    });

    // Wire Chokidar events into the debounced handler.
    this.watcher.on('add', (filePath: string) => this.handleChange(filePath, 'add'));
    this.watcher.on('change', (filePath: string) => this.handleChange(filePath, 'change'));
    this.watcher.on('unlink', (filePath: string) => this.handleChange(filePath, 'unlink'));

    this.watcher.on('error', (error: Error) => {
      this.emit('error', error);
    });

    // Wait for the initial scan to complete.
    return new Promise<void>((resolve) => {
      this.watcher!.on('ready', () => {
        this.emit('ready');
        resolve();
      });
    });
  }

  /**
   * Stop watching and release all resources.
   *
   * Clears pending debounce timers and closes the Chokidar watcher.
   */
  async stop(): Promise<void> {
    // Clear all pending debounce timers.
    for (const timer of this.debounceTimers.values()) {
      clearTimeout(timer);
    }
    this.debounceTimers.clear();

    if (this.watcher) {
      await this.watcher.close();
      this.watcher = null;
    }
  }

  // -------------------------------------------------------------------------
  // Path Classification (public for testing)
  // -------------------------------------------------------------------------

  /**
   * Classify a file path into a semantic topic and parser strategy.
   *
   * @param filePath - Absolute path to the changed file.
   * @returns Classification result with topic, parser hint, and whether the
   *          file should be excluded from this watcher (e.g., timeline.jsonl).
   *          Returns null if the file does not match any classification rule.
   */
  classifyPath(filePath: string): PathClassification | null {
    const relativePath = this.toRelativePath(filePath);
    if (relativePath === null) {
      return null;
    }

    for (const rule of PATH_RULES) {
      if (rule.pattern.test(relativePath)) {
        // For audit reports, determine parser from file extension at runtime.
        if (rule.classification.parser === null && rule.classification.topic === 'audit') {
          return {
            ...rule.classification,
            parser: this.inferParserFromExtension(filePath),
          };
        }
        return rule.classification;
      }
    }

    // No rule matched — file is outside the known directory structure.
    return null;
  }

  // -------------------------------------------------------------------------
  // Internal: Change Handling Pipeline
  // -------------------------------------------------------------------------

  /**
   * Handle a raw Chokidar event with debouncing.
   *
   * Multiple rapid changes to the same file within the debounce window are
   * coalesced into a single event using the latest change type.
   */
  private handleChange(filePath: string, changeType: 'add' | 'change' | 'unlink'): void {
    // Clear any pending timer for this file path.
    const existing = this.debounceTimers.get(filePath);
    if (existing) {
      clearTimeout(existing);
    }

    const timer = setTimeout(() => {
      this.debounceTimers.delete(filePath);
      this.processChange(filePath, changeType).catch((error: unknown) => {
        this.emit('error', error instanceof Error ? error : new Error(String(error)));
      });
    }, this.debounceMs);

    this.debounceTimers.set(filePath, timer);
  }

  /**
   * Process a debounced file change: classify, parse, normalize, emit.
   */
  private async processChange(
    filePath: string,
    changeType: 'add' | 'change' | 'unlink',
  ): Promise<void> {
    // Step 1: Classify
    const classification = this.classifyPath(filePath);
    if (classification === null) {
      // File does not match any known pattern — silently ignore.
      return;
    }

    if (classification.excluded) {
      // File is handled by another watcher (e.g., timeline.jsonl by StageLogStream).
      return;
    }

    // Step 2: Parse (skip for unlink events — file no longer exists)
    let parsedData: unknown | null = null;
    if (changeType !== 'unlink') {
      parsedData = await this.parseFile(filePath, classification);
    }

    // Step 3: Normalize into a FileChangeEvent
    const event: FileChangeEvent = {
      type: 'file_change',
      topic: classification.topic,
      filePath,
      changeType,
      parsedData,
      timestamp: new Date().toISOString(),
    };

    // Step 4: Emit
    this.emit('event', event);
  }

  /**
   * Read and parse a file using the appropriate parser.
   *
   * Returns the parsed data or null if the file cannot be read or parsed.
   * Parser errors are logged but never thrown — the event is still emitted
   * with parsedData: null.
   */
  private async parseFile(
    filePath: string,
    classification: PathClassification,
  ): Promise<unknown | null> {
    let content: string;
    try {
      content = await fs.readFile(filePath, 'utf-8');
    } catch {
      // File may have been deleted between the change event and this read.
      return null;
    }

    const parser = classification.parser ?? this.inferParserFromExtension(filePath);
    if (parser === null) {
      // No parser available — return raw content as string.
      return content;
    }

    try {
      switch (parser) {
        case 'yaml': {
          const result = parseYaml(content, filePath);
          return result.data;
        }
        case 'json': {
          const result = parseJson(content, filePath);
          return result.data;
        }
        case 'markdown': {
          const result = parseMarkdownWithFrontmatter(content, filePath);
          return result.data;
        }
        case 'epicSpec': {
          const result = parseEpicSpec(content, filePath);
          return result.data;
        }
        case 'jsonl': {
          // JSONL files should not be parsed by the file watcher — they are
          // handled by the StageLogStream. If we reach here, return null.
          return null;
        }
        default: {
          // Exhaustive check: if a new parser type is added but not handled,
          // TypeScript will flag this as an error.
          const _exhaustive: never = parser;
          return _exhaustive;
        }
      }
    } catch {
      // Parser threw unexpectedly — should not happen since parsers are
      // defensive, but guard against it anyway.
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Internal: Utilities
  // -------------------------------------------------------------------------

  /**
   * Convert an absolute file path to a path relative to the `.aid-o/` root,
   * using forward slashes.
   *
   * Returns null if the path is not inside the watched directory.
   */
  private toRelativePath(filePath: string): string | null {
    const resolved = path.resolve(filePath);
    if (!resolved.startsWith(this.aidoPath)) {
      return null;
    }

    // Remove the aidoPath prefix and leading separator.
    const relative = resolved.slice(this.aidoPath.length);
    const normalized = relative.replace(/\\/g, '/');

    // Remove leading slash if present.
    return normalized.startsWith('/') ? normalized.slice(1) : normalized;
  }

  /**
   * Infer a parser type from the file extension.
   *
   * Used when the classification rule has `parser: null` (catch-all rules)
   * or for audit reports where the parser depends on the file extension.
   */
  private inferParserFromExtension(
    filePath: string,
  ): 'yaml' | 'json' | 'markdown' | null {
    const ext = path.extname(filePath).toLowerCase();
    switch (ext) {
      case '.yaml':
      case '.yml':
        return 'yaml';
      case '.json':
        return 'json';
      case '.md':
        return 'markdown';
      default:
        return null;
    }
  }
}
