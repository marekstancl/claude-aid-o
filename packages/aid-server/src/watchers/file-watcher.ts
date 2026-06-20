/**
 * Cross-project chokidar watcher fleet (EPIC E-047-3_7, Step 1).
 *
 * One chokidar@4 watcher per discovered `.aid-o/` workspace. Each watcher is
 * rooted at `<project>/.aid-o` with `depth: 7` so it reaches deeply-nested
 * evidence files such as
 * `work/evidence/<epic>/<run>/gates/gates_report.json`.
 *
 * For every (debounced) change the watcher:
 *   1. classifies the relative path into one of the 12 contract `EventTopic`s
 *      via the reused `PATH_RULES` table (`classifyPath`),
 *   2. derives the owning `projectId` (segment after `/projects/`) and, when the
 *      path is under `work/evidence/<epic>/<run>/`, a `runRef {epicId, runId}`,
 *   3. invalidates the matching scanner-cache slice (run-scope) when a runRef
 *      is present,
 *   4. emits a typed `FileChangeEvent` (the MVP1 `InternalEvent`) on the
 *      `'event'` channel.
 *
 * chokidar@4 NOTE: v4 dropped glob support in matchers. The salvaged v1
 * node_modules / *.png ignore globs would silently NOT match in v4, so this
 * module uses a `MatchFunction` ignore predicate instead (see
 * {@link shouldIgnore}). This is the load-bearing adaptation that keeps AC2
 * (node_modules / binary writes produce zero events) honest.
 *
 * Module: src/watchers/file-watcher.ts
 * Depends on: @aid/contract (FileChangeEvent / EventTopic / RunRef).
 */

import { EventEmitter } from 'node:events';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import chokidar, { type FSWatcher as ChokidarFSWatcher } from 'chokidar';
import type {
  EventTopic,
  FileChangeEvent,
  Project,
  RunRef,
} from '@aid/contract';

// ---------------------------------------------------------------------------
// Path classification rules — adapted to the 12 contract EventTopics.
// ---------------------------------------------------------------------------

/** A classification rule: a relative-path regex mapped to a contract topic. */
interface PathRule {
  pattern: RegExp;
  topic: EventTopic;
}

/**
 * Classification rules evaluated in order — first match wins. The pattern
 * operates on the path RELATIVE to the `.aid-o/` root, with forward slashes.
 *
 * Topic mapping vs. the v1 aid-gui salvage (old → current 12-topic vocabulary):
 *   - `pipeline.stage_log` (timeline.jsonl) → `pipeline.timeline`
 *   - `evidence` catch-all                  → dropped (not in the 12; → null)
 *   - `plans/` (was `config`)               → dropped (no `plans` topic; → null)
 *   - gates_report.json (was `pipeline`)    → `gates` (now a first-class topic)
 *   - compliance.json (new)                 → `compliance`
 *   - verifier-output-*.md (new)            → `checkpoints`
 *   - work/backlog.md (new)                 → `backlog`
 *   - tasks/*.md (was `pipeline`/epicSpec)  → `epics`
 *   - decisions/*.md + pm_*.json            → `decisions`
 */
const PATH_RULES: ReadonlyArray<PathRule> = [
  // Timeline stage log (was pipeline.stage_log in v1 salvage).
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/timeline\.jsonl$/,
    topic: 'pipeline.timeline',
  },
  // Gate report (with or without the `gates/` subdir) — first-class topic now.
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/(gates\/)?gates_report\.json$/,
    topic: 'gates',
  },
  // Compliance report.
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/compliance\.json$/,
    topic: 'compliance',
  },
  // Checkpoint verifier outputs.
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/.*verifier-output[^/]*\.md$/,
    topic: 'checkpoints',
  },
  // PM decision records under a run.
  {
    pattern:
      /^work\/evidence\/[^/]+\/[^/]+\/pm_(decision|plan_approval|merge_approval)\.json$/,
    topic: 'decisions',
  },
  // Standalone decision records.
  {
    pattern: /^decisions\/.*\.md$/,
    topic: 'decisions',
  },
  // FSM / pipeline state at the run level.
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/(fsm-state|state)\.yaml$/,
    topic: 'pipeline',
  },
  // Execution plan (initial load) at the run level.
  {
    pattern: /^work\/evidence\/[^/]+\/[^/]+\/plan\.json$/,
    topic: 'pipeline',
  },
  // Global auto-mode pipeline state.
  {
    pattern: /^work\/auto-mode-state\.yaml$/,
    topic: 'pipeline',
  },
  // Per-EPIC or per-run audit report (yaml or md).
  {
    pattern: /^work\/evidence(\/[^/]+){1,2}\/audit-report\.(yaml|md)$/,
    topic: 'audit',
  },
  // Backlog.
  {
    pattern: /^work\/backlog\.md$/,
    topic: 'backlog',
  },
  // EPIC spec files.
  {
    pattern: /^tasks\/[^/]+\.md$/,
    topic: 'epics',
  },
  // Queue state and ordering.
  {
    pattern: /^config\/queue\.yaml$/,
    topic: 'queue',
  },
  // Any other configuration file.
  {
    pattern: /^config\//,
    topic: 'config',
  },
];

// ---------------------------------------------------------------------------
// Ignore predicate — chokidar@4 MatchFunction (NOT globs; v4 dropped globs).
// ---------------------------------------------------------------------------

/** Path fragments that must never be watched, regardless of extension. */
const IGNORED_DIR_FRAGMENTS: ReadonlyArray<string> = [
  '/node_modules/',
  '/.git/',
];

/** Binary / cache / volatile file extensions the watcher always ignores. */
const IGNORED_EXTENSIONS: ReadonlySet<string> = new Set([
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.ico',
  '.svg',
  '.zip',
  '.tar',
  '.gz',
  '.tgz',
  '.bin',
  '.lock',
  '.tmp',
  '.swp',
]);

/**
 * chokidar@4 ignore predicate. Receives an absolute path (and, for files, a
 * stat). Returns true to ignore. Operates on the normalized path so it works
 * the same on POSIX and Windows.
 *
 * Replaces the v1 glob list — v4 matchers are NOT glob strings, so a function
 * is the only reliable way to exclude `node_modules`, `.git`, and binaries.
 */
function shouldIgnore(absPath: string): boolean {
  const norm = absPath.replace(/\\/g, '/');
  for (const frag of IGNORED_DIR_FRAGMENTS) {
    if (norm.includes(frag)) return true;
  }
  // Trailing-segment dir match (e.g. the directory itself, no trailing slash).
  if (norm.endsWith('/node_modules') || norm.endsWith('/.git')) return true;

  const ext = path.extname(norm).toLowerCase();
  return IGNORED_EXTENSIONS.has(ext);
}

// ---------------------------------------------------------------------------
// Cache-slice invalidation seam
// ---------------------------------------------------------------------------

/**
 * The slice of the scanner cache the watcher needs to invalidate. Kept as a
 * narrow interface (not the concrete `ScannerCache`) so the watcher has no
 * hard compile-time dependency on the cache and is trivially testable with a
 * spy. The real `ScannerCache.invalidate` matches this shape.
 */
export interface CacheInvalidator {
  invalidate(projectId: string, epicId: string, runId: string): void;
}

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

export interface CrossProjectWatcherOptions {
  /** Per-path debounce window in ms (default 150). Coalesces rapid writes. */
  debounceMs?: number;
  /** chokidar recursion depth (default 7 — reaches run/gates nested files). */
  depth?: number;
  /**
   * Optional scanner-cache slice to invalidate on run-scoped changes. When
   * omitted the watcher still emits events but performs no invalidation.
   */
  cache?: CacheInvalidator;
}

// ---------------------------------------------------------------------------
// Typed event map
// ---------------------------------------------------------------------------

/** Events emitted by {@link CrossProjectWatcher}. */
export interface CrossProjectWatcherEvents {
  /** A classified, non-ignored file change in some watched workspace. */
  event: [FileChangeEvent];
  /** A watcher-level error (chokidar error or processing failure). */
  error: [Error];
}

// ---------------------------------------------------------------------------
// Pure helpers (exported for unit testing)
// ---------------------------------------------------------------------------

/**
 * Classify a path RELATIVE to the `.aid-o/` root into a contract `EventTopic`.
 * Returns null when no rule matches (the file is outside the known surface).
 *
 * @param relPath - forward-slash path relative to the `.aid-o/` root.
 */
export function classifyPath(relPath: string): EventTopic | null {
  const normalized = relPath.replace(/\\/g, '/').replace(/^\/+/, '');
  for (const rule of PATH_RULES) {
    if (rule.pattern.test(normalized)) return rule.topic;
  }
  return null;
}

/**
 * Extract the project id from an absolute path: the single path segment that
 * immediately follows a `/projects/` segment. Returns null when there is no
 * `/projects/` segment (the path is not under a projects root).
 *
 * Example: `/opt/eco/projects/vulcan/.aid-o/config/queue.yaml` → `vulcan`.
 */
export function extractProjectId(absPath: string): string | null {
  const norm = absPath.replace(/\\/g, '/');
  const m = norm.match(/\/projects\/([^/]+)(?:\/|$)/);
  return m ? m[1] : null;
}

/**
 * Extract a `RunRef` when the relative path is under
 * `work/evidence/<epic>/<run>/...`. Returns null otherwise (runRef is
 * optional per the contract and omitted for non-run paths).
 *
 * @param relPath - forward-slash path relative to the `.aid-o/` root.
 */
export function extractRunRef(relPath: string): RunRef | null {
  const normalized = relPath.replace(/\\/g, '/').replace(/^\/+/, '');
  const m = normalized.match(/^work\/evidence\/([^/]+)\/([^/]+)\//);
  if (!m) return null;
  return { epicId: m[1], runId: m[2] };
}

// ---------------------------------------------------------------------------
// CrossProjectWatcher
// ---------------------------------------------------------------------------

/**
 * Manages a fleet of per-workspace chokidar watchers and emits typed
 * `FileChangeEvent`s carrying `projectId`.
 *
 * Usage:
 * ```typescript
 * const watcher = new CrossProjectWatcher({ cache });
 * watcher.on('event', (e) => { ... });
 * await watcher.reconcile(await scanner.scan());
 * // ... later
 * await watcher.closeAll();
 * ```
 */
export class CrossProjectWatcher extends EventEmitter {
  /** One chokidar watcher per projectId, rooted at `<project>/.aid-o`. */
  private readonly watchers = new Map<string, ChokidarFSWatcher>();

  /** The `.aid-o/` root path per projectId (for relative-path computation). */
  private readonly aidoPaths = new Map<string, string>();

  /** Per-path debounce timers (keyed by absolute file path). */
  private readonly debounceTimers = new Map<
    string,
    ReturnType<typeof setTimeout>
  >();

  /** Latest pending change type per absolute path (coalesced by the timer). */
  private readonly pendingChangeType = new Map<
    string,
    'add' | 'change' | 'unlink'
  >();

  private readonly debounceMs: number;
  private readonly depth: number;
  private readonly cache: CacheInvalidator | undefined;

  constructor(options?: CrossProjectWatcherOptions) {
    super();
    this.debounceMs = options?.debounceMs ?? 150;
    this.depth = options?.depth ?? 7;
    this.cache = options?.cache;
  }

  // Strongly-typed EventEmitter surface.
  override on<K extends keyof CrossProjectWatcherEvents>(
    event: K,
    listener: (...args: CrossProjectWatcherEvents[K]) => void,
  ): this {
    return super.on(event, listener as (...args: unknown[]) => void);
  }

  override emit<K extends keyof CrossProjectWatcherEvents>(
    event: K,
    ...args: CrossProjectWatcherEvents[K]
  ): boolean {
    return super.emit(event, ...args);
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /**
   * Attach a watcher for a single discovered project. Idempotent: attaching a
   * project that is already watched is a no-op. Resolves once chokidar has
   * completed its initial scan (`ready`).
   */
  async attach(proj: Project): Promise<void> {
    if (this.watchers.has(proj.id)) return;

    const aidoPath = path.resolve(proj.aidoPath);
    this.aidoPaths.set(proj.id, aidoPath);

    const watcher = chokidar.watch(aidoPath, {
      persistent: true,
      ignoreInitial: true,
      depth: this.depth,
      followSymlinks: false,
      ignored: (p: string) => shouldIgnore(p),
    });

    watcher.on('add', (filePath: string) =>
      this.scheduleChange(proj.id, filePath, 'add'),
    );
    watcher.on('change', (filePath: string) =>
      this.scheduleChange(proj.id, filePath, 'change'),
    );
    watcher.on('unlink', (filePath: string) =>
      this.scheduleChange(proj.id, filePath, 'unlink'),
    );
    watcher.on('error', (err: unknown) => {
      this.emit('error', err instanceof Error ? err : new Error(String(err)));
    });

    this.watchers.set(proj.id, watcher);

    await new Promise<void>((resolve) => {
      watcher.once('ready', () => resolve());
    });
  }

  /**
   * Detach and close the watcher for `projectId`. Clears any pending debounce
   * timers for that workspace so no leaked timer fires after close. No-op when
   * the project is not currently watched.
   */
  async detach(projectId: string): Promise<void> {
    const watcher = this.watchers.get(projectId);
    if (!watcher) return;

    const aidoPath = this.aidoPaths.get(projectId);
    if (aidoPath) {
      // Drop pending timers rooted under this workspace.
      for (const [absPath, timer] of this.debounceTimers) {
        if (absPath.startsWith(aidoPath)) {
          clearTimeout(timer);
          this.debounceTimers.delete(absPath);
          this.pendingChangeType.delete(absPath);
        }
      }
    }

    await watcher.close();
    this.watchers.delete(projectId);
    this.aidoPaths.delete(projectId);
  }

  /**
   * Reconcile the watcher fleet against a freshly-discovered project list:
   * attach watchers for newly-present projects and detach/close watchers for
   * projects that disappeared. Leaves untouched projects running. Guarantees
   * no leaked `FSWatcher` (removed projects are always `close()`d).
   */
  async reconcile(discovered: Project[]): Promise<void> {
    const discoveredIds = new Set(discovered.map((p) => p.id));

    // Detach removed projects.
    const toDetach = [...this.watchers.keys()].filter(
      (id) => !discoveredIds.has(id),
    );
    await Promise.all(toDetach.map((id) => this.detach(id)));

    // Attach newly-discovered projects.
    const toAttach = discovered.filter((p) => !this.watchers.has(p.id));
    await Promise.all(toAttach.map((p) => this.attach(p)));
  }

  /** Close every watcher and clear all pending timers. */
  async closeAll(): Promise<void> {
    for (const timer of this.debounceTimers.values()) clearTimeout(timer);
    this.debounceTimers.clear();
    this.pendingChangeType.clear();

    await Promise.all([...this.watchers.values()].map((w) => w.close()));
    this.watchers.clear();
    this.aidoPaths.clear();
  }

  /** Number of currently-attached watchers (test/observability helper). */
  get size(): number {
    return this.watchers.size;
  }

  /** True when a watcher is currently attached for `projectId`. */
  isWatching(projectId: string): boolean {
    return this.watchers.has(projectId);
  }

  // -------------------------------------------------------------------------
  // Change handling
  // -------------------------------------------------------------------------

  /**
   * Debounce a raw chokidar event. Rapid writes to the same absolute path
   * within `debounceMs` are coalesced into a single emit using the latest
   * change type.
   */
  private scheduleChange(
    projectId: string,
    filePath: string,
    changeType: 'add' | 'change' | 'unlink',
  ): void {
    const abs = path.resolve(filePath);
    this.pendingChangeType.set(abs, changeType);

    const existing = this.debounceTimers.get(abs);
    if (existing) clearTimeout(existing);

    const timer = setTimeout(() => {
      this.debounceTimers.delete(abs);
      const finalType = this.pendingChangeType.get(abs) ?? changeType;
      this.pendingChangeType.delete(abs);
      this.processChange(projectId, abs, finalType).catch((err: unknown) => {
        this.emit('error', err instanceof Error ? err : new Error(String(err)));
      });
    }, this.debounceMs);

    this.debounceTimers.set(abs, timer);
  }

  /**
   * Process a debounced change: classify, derive projectId + runRef, invalidate
   * the matching cache slice, read+parse the file (best effort), and emit a
   * `FileChangeEvent`. Unclassifiable paths are silently dropped.
   */
  private async processChange(
    projectId: string,
    absPath: string,
    changeType: 'add' | 'change' | 'unlink',
  ): Promise<void> {
    const aidoPath = this.aidoPaths.get(projectId);
    if (!aidoPath) return; // watcher detached mid-flight

    const relPath = this.toRelativePath(aidoPath, absPath);
    if (relPath === null) return;

    const topic = classifyPath(relPath);
    if (topic === null) return; // outside the known surface — drop

    // projectId from the path takes precedence (matches `/projects/<id>/`); fall
    // back to the watcher's own id when the workspace is not under /projects/.
    const resolvedProjectId = extractProjectId(absPath) ?? projectId;
    const runRef = extractRunRef(relPath);

    // Cache-slice invalidation: only run-scoped changes invalidate a RunDetail.
    if (runRef && this.cache) {
      this.cache.invalidate(resolvedProjectId, runRef.epicId, runRef.runId);
    }

    // Best-effort parse (skip for unlink — the file is gone).
    let parsedData: unknown = null;
    if (changeType !== 'unlink') {
      parsedData = await this.readParsed(absPath);
    }

    const event: FileChangeEvent = {
      type: 'file_change',
      projectId: resolvedProjectId,
      topic,
      filePath: relPath,
      changeType,
      ...(runRef ? { runRef } : {}),
      parsedData,
      ts: new Date().toISOString(),
    };

    this.emit('event', event);
  }

  /**
   * Read and best-effort parse a file by extension. Never throws: a missing
   * file or parse failure yields `null` (the event is still emitted).
   */
  private async readParsed(absPath: string): Promise<unknown> {
    let content: string;
    try {
      content = await fs.readFile(absPath, 'utf-8');
    } catch {
      return null; // deleted between event and read
    }

    const ext = path.extname(absPath).toLowerCase();
    try {
      if (ext === '.json') return JSON.parse(content);
      // JSONL: parse line-by-line, skip blanks/malformed.
      if (ext === '.jsonl') {
        const rows: unknown[] = [];
        for (const line of content.split('\n')) {
          const t = line.trim();
          if (t.length === 0) continue;
          try {
            rows.push(JSON.parse(t));
          } catch {
            // skip malformed line
          }
        }
        return rows;
      }
    } catch {
      return null;
    }
    // yaml / md / other: return raw text (no heavy parser dependency here).
    return content;
  }

  /**
   * Convert an absolute path to one relative to the workspace `.aid-o/` root,
   * with forward slashes. Returns null when the path is not inside the root.
   */
  private toRelativePath(aidoPath: string, absPath: string): string | null {
    const resolved = path.resolve(absPath);
    if (resolved !== aidoPath && !resolved.startsWith(aidoPath + path.sep)) {
      return null;
    }
    const rel = resolved.slice(aidoPath.length).replace(/\\/g, '/');
    return rel.startsWith('/') ? rel.slice(1) : rel;
  }
}
