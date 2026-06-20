/**
 * Two-tier scanner cache (EPIC E-047-2_7, Step 7).
 *
 * Cache machinery for the ProjectScanner, kept separable from
 * `project-scanner.ts` for testability. This step provides ONLY the caching
 * layer — it does NOT assemble `RunDetail` (that is Step 8). The full
 * `RunDetail` is produced by an INJECTED loader callback ({@link RunDetailLoader}),
 * so there is no compile-time dependency on Step 8 here.
 *
 * Design (spec §7.2):
 *
 * - **Tier 1 (boot, sub-second):** a project/EPIC index = dir listing +
 *   frontmatter + per-run `{ mtime, state-line }`. ALSO indexes the managerial-
 *   projection source files (Rev3 SF2): `plans/*.md`, the per-EPIC
 *   `work/evidence/<epic>/audit-report.md`, `work/backlog.md`, and
 *   `work/lessons-learned.md` — storing presence
 *   + mtime + frontmatter ONLY (never the full body). This lets later
 *   PlanSummary/AuditSummary/BacklogDelta/LessonsView be cheap projections.
 *   Tier-1 NEVER invokes the RunDetail loader.
 *
 * - **Tier 2 (lazy, memoized):** full `RunDetail` produced on-demand by the
 *   injected loader, memoized in an `lru-cache@10` keyed by
 *   `projectId/epicId/runId`. The cache only memoizes — it does not know how a
 *   RunDetail is built.
 *
 * - **Invalidation:** watcher PRIMARY (call {@link ScannerCache.invalidate}),
 *   a max-file-mtime backstop (a nested-file change that does not bump the run-
 *   DIR mtime still marks the entry stale on next access), and a 10-min TTL
 *   safety sweep ({@link ScannerCache.sweep}, `config.scanTtlMs`).
 *
 * - **Bounded merged activity:** a {@link CircularBuffer} ring of the last
 *   `config.activityBufferSize` timeline events across all projects.
 *
 * Reliability posture: NEVER throws on a broken/partial workspace. All disk
 * reads route through the never-throw `FsReader`.
 */

import { join } from 'node:path';
import { readdir, stat } from 'node:fs/promises';
import { LRUCache } from 'lru-cache';
import type { ActivityEvent, FsmState, RunDetail, RunFormat } from '@aid/contract';
import { FsReader } from './fs-reader.js';
import { ProjectScanner } from './project-scanner.js';

// ===========================================================================
// CircularBuffer — salvaged from packages/aid-gui/server/watchers/
//   stage-log-stream.ts (lines ~40-140), adapted to NodeNext `.js` (no imports
//   needed — it is dependency-free). Copied in, NOT imported cross-package
//   (the parts-bin is a different package and must not be a runtime dependency).
// ===========================================================================

/**
 * Fixed-size circular buffer providing O(1) insertion and O(n) ordered
 * retrieval. When full, the oldest entry is overwritten.
 */
export class CircularBuffer<T> {
  private readonly items: (T | undefined)[];
  private head = 0;
  private count = 0;
  private readonly capacity: number;

  constructor(capacity: number) {
    if (capacity < 1) {
      throw new Error(`CircularBuffer capacity must be >= 1, got ${capacity}`);
    }
    this.capacity = capacity;
    this.items = new Array<T | undefined>(capacity).fill(undefined);
  }

  /** Add an item to the buffer. Overwrites the oldest entry when full. */
  push(item: T): void {
    this.items[this.head] = item;
    this.head = (this.head + 1) % this.capacity;
    if (this.count < this.capacity) {
      this.count++;
    }
  }

  /** Return all buffered items in insertion order (oldest first). */
  toArray(): T[] {
    if (this.count === 0) return [];

    const result: T[] = [];
    // When the buffer is not yet full, items start at index 0. When full, the
    // oldest item is at `head` (where the next write will go).
    const start = this.count < this.capacity ? 0 : this.head;
    for (let i = 0; i < this.count; i++) {
      const idx = (start + i) % this.capacity;
      result.push(this.items[idx] as T);
    }
    return result;
  }

  /** Clear all entries from the buffer. */
  clear(): void {
    this.items.fill(undefined);
    this.head = 0;
    this.count = 0;
  }

  /** Current number of items in the buffer. */
  get size(): number {
    return this.count;
  }

  /** Configured maximum number of items. */
  get max(): number {
    return this.capacity;
  }
}

// ===========================================================================
// Tier-1 index types (internal — NOT in the @aid/contract surface)
// ===========================================================================

/** A managerial-projection source file: presence + mtime + frontmatter ONLY. */
export interface IndexedSourceFile {
  /** Logical name / id of the file (e.g. plan id, or 'backlog'). */
  name: string;
  /** Absolute path on disk. */
  path: string;
  /** Always true when present in the index (presence marker). */
  present: boolean;
  /** Last-modified time (epoch ms), null if unreadable. */
  mtimeMs: number | null;
  /** Parsed frontmatter (camelCase keys), or null if none / unreadable. */
  frontmatter: Record<string, string> | null;
}

/** A run's Tier-1 entry: cheap `{ mtime, state-line }` — no full RunDetail. */
export interface IndexedRun {
  runId: string;
  runDir: string;
  /** Run-DIR mtime (epoch ms), null if unreadable. */
  mtimeMs: number | null;
  /** v3 / legacy / stub classification (mirrors the scanner). */
  format: RunFormat;
  /** The `state:` line value when v3, else null (the cheap "state-line"). */
  state: FsmState | null;
}

/** An EPIC's Tier-1 entry: id, frontmatter, and its run index. */
export interface IndexedEpic {
  epicId: string;
  /** Source `tasks/<id>.md` path, when the EPIC is known via a task file. */
  taskPath: string | null;
  /** EPIC task-file frontmatter (camelCase), or null. */
  frontmatter: Record<string, string> | null;
  /** Per-run cheap entries (keyed by runId). */
  runs: Map<string, IndexedRun>;
}

/** A project's Tier-1 entry. */
export interface IndexedProject {
  projectId: string;
  projectDir: string;
  aidoPath: string;
  /** EPIC entries keyed by epicId. */
  epics: Map<string, IndexedEpic>;
  /** Indexed plan files (`plans/*.md`) keyed by plan id (filename stem). */
  plans: Map<string, IndexedSourceFile>;
  /** Indexed per-EPIC `audit-report.md` files keyed by epicId. */
  auditReports: Map<string, IndexedSourceFile>;
  /** Indexed `work/backlog.md` (presence + mtime + frontmatter), or null. */
  backlog: IndexedSourceFile | null;
  /** Indexed `work/lessons-learned.md`, or null. */
  lessons: IndexedSourceFile | null;
}

/** The boot-time Tier-1 index: all projects keyed by projectId. */
export interface Tier1Index {
  projects: Map<string, IndexedProject>;
  /** When the index was built (epoch ms) — used by the TTL sweep. */
  builtAtMs: number;
}

// ===========================================================================
// Injected loader type (Step 8 supplies the real implementation)
// ===========================================================================

/**
 * Produces a full `RunDetail` for a `(projectId, epicId, runId)` triple. The
 * cache memoizes the RESULT; it does not know how a RunDetail is assembled.
 * Step 8 supplies the real loader; tests pass a counting stub.
 */
export type RunDetailLoader = (
  projectId: string,
  epicId: string,
  runId: string,
) => Promise<RunDetail>;

// ===========================================================================
// LRU value — RunDetail plus the max-file-mtime backstop material
// ===========================================================================

/** A memoized RunDetail plus the max mtime over the files the load read. */
interface CachedRunDetail {
  detail: RunDetail;
  /**
   * The MAX mtime (epoch ms) over the files the loader read for this run.
   * A nested-file change (e.g. `gates/gates_report.json`) may NOT bump the
   * run-DIR mtime — so we re-scan the run's files on access and compare. If the
   * observed max moves past this value, the entry is stale (loader re-invoked).
   */
  maxFileMtimeMs: number;
}

// ===========================================================================
// Config slice consumed by the cache
// ===========================================================================

/** The subset of `ServerConfig` the cache needs. */
export interface ScannerCacheConfig {
  /** TTL for the safety sweep / re-discover cadence, in ms (default 600000). */
  scanTtlMs: number;
  /** Size of the merged-activity ring buffer (default 500). */
  activityBufferSize: number;
  /** Optional max number of RunDetail entries in the LRU (default 256). */
  runDetailCacheMax?: number;
}

const DEFAULT_RUN_DETAIL_CACHE_MAX = 256;

/** The six valid v3 FSM states (mirrors project-scanner.ts). */
const VALID_FSM_STATES: ReadonlySet<string> = new Set<FsmState>([
  'READY',
  'EXECUTE',
  'GATES',
  'ESCALATION',
  'DONE',
  'ERROR',
]);

/** Build the LRU key for a run-scope RunDetail. */
export function runKey(projectId: string, epicId: string, runId: string): string {
  return `${projectId}/${epicId}/${runId}`;
}

/** Build the LRU key for a plan-scope entry (reserved for plan-detail memoization). */
export function planKey(projectId: string, planId: string): string {
  return `${projectId}/${planId}`;
}

// ===========================================================================
// ScannerCache
// ===========================================================================

export class ScannerCache {
  private readonly fs: FsReader;
  private readonly scanner: ProjectScanner;
  private readonly config: ScannerCacheConfig;

  /** Tier-2 LRU: RunDetail memoization keyed by `projectId/epicId/runId`. */
  private readonly runDetailCache: LRUCache<string, CachedRunDetail>;

  /** Bounded merged-activity ring (last N timeline events across projects). */
  private readonly activity: CircularBuffer<ActivityEvent>;

  /** The injected RunDetail assembler (Step 8 / stub in tests). */
  private readonly loader: RunDetailLoader;

  /** Boot-time Tier-1 index. Null until {@link buildIndex} runs. */
  private index: Tier1Index | null = null;

  /**
   * @param projectsRoot - cross-project discovery root.
   * @param loader - injected RunDetail assembler (Step 8 supplies the real one).
   * @param config - TTL + buffer-size + optional LRU max.
   * @param fs - optional FsReader (stateless). Injectable for tests.
   * @param scanner - optional ProjectScanner. Injectable for tests; defaults to
   *   a fresh instance bound to `projectsRoot` and `fs`.
   */
  constructor(
    private readonly projectsRoot: string,
    loader: RunDetailLoader,
    config: ScannerCacheConfig,
    fs?: FsReader,
    scanner?: ProjectScanner,
  ) {
    this.fs = fs ?? new FsReader();
    this.scanner = scanner ?? new ProjectScanner(projectsRoot, this.fs);
    this.loader = loader;
    this.config = config;
    this.runDetailCache = new LRUCache<string, CachedRunDetail>({
      max: config.runDetailCacheMax ?? DEFAULT_RUN_DETAIL_CACHE_MAX,
    });
    this.activity = new CircularBuffer<ActivityEvent>(
      Math.max(1, config.activityBufferSize),
    );
  }

  // -------------------------------------------------------------------------
  // Tier 1 — boot index
  // -------------------------------------------------------------------------

  /**
   * Build (or rebuild) the boot-time Tier-1 index. Sub-second: dir listing +
   * frontmatter + per-run `{ mtime, state-line }` + managerial-projection
   * source-file presence/mtime/frontmatter. NEVER invokes the RunDetail loader.
   *
   * Discovery reuses {@link ProjectScanner.scan} for the project list (denylist
   * + layout sanity), then enriches each project with its EPIC/run/source-file
   * index. Never throws.
   */
  async buildIndex(): Promise<Tier1Index> {
    const projects = await this.scanner.scan();
    const map = new Map<string, IndexedProject>();

    for (const p of projects) {
      const indexed = await this.indexProject(p.id, p.path, p.aidoPath);
      map.set(p.id, indexed);
    }

    this.index = { projects: map, builtAtMs: Date.now() };
    return this.index;
  }

  /** Return the current Tier-1 index, building it on first access. */
  async getIndex(): Promise<Tier1Index> {
    if (this.index === null) {
      return this.buildIndex();
    }
    return this.index;
  }

  /**
   * Cheap project listing straight from the Tier-1 index — performs NO per-run
   * RunDetail load (the injected loader is never called here). Builds the index
   * lazily on first call.
   */
  async getProjects(): Promise<IndexedProject[]> {
    const idx = await this.getIndex();
    return [...idx.projects.values()].sort((a, b) =>
      a.projectId.localeCompare(b.projectId),
    );
  }

  /**
   * Build a single project's Tier-1 entry: EPIC index (frontmatter + per-run
   * cheap entries) + managerial-projection source files (plans, audit-report,
   * backlog, lessons — presence + mtime + frontmatter only). Never throws.
   */
  private async indexProject(
    projectId: string,
    projectDir: string,
    aidoPath: string,
  ): Promise<IndexedProject> {
    const epics = new Map<string, IndexedEpic>();

    // --- EPIC index from tasks/*.md (frontmatter + filename stem) ---
    const tasksDir = join(aidoPath, 'tasks');
    const taskFiles = (await this.fs.listDir(tasksDir)).filter(
      (e) => e.endsWith('.md') && !e.startsWith('.') && e !== 'archive',
    );
    for (const file of taskFiles) {
      const abs = join(tasksDir, file);
      const text = await this.fs.readText(abs);
      const fm = extractFrontmatter(text);
      const epicId = epicIdFrom(fm, file);
      epics.set(epicId, {
        epicId,
        taskPath: abs,
        frontmatter: fm,
        runs: new Map(),
      });
    }

    // --- Per-run cheap entries from work/evidence/<epicId>/<runId>/ ---
    const evidenceDir = join(aidoPath, 'work', 'evidence');
    const auditReports = new Map<string, IndexedSourceFile>();
    const evidenceEpicDirs = (await this.fs.listDir(evidenceDir)).filter(
      (d) => !d.startsWith('.') && d !== 'archive',
    );
    for (const epicDir of evidenceEpicDirs) {
      const absEpicDir = join(evidenceDir, epicDir);
      // Ensure an EPIC entry exists even when only known via evidence dirs.
      let epicEntry = epics.get(epicDir);
      if (!epicEntry) {
        epicEntry = { epicId: epicDir, taskPath: null, frontmatter: null, runs: new Map() };
        epics.set(epicDir, epicEntry);
      }

      const runNames = (await this.fs.listDir(absEpicDir)).filter(
        (d) => !d.startsWith('.'),
      );
      for (const runId of runNames) {
        const runDir = join(absEpicDir, runId);
        const cheap = await this.indexRun(runId, runDir);
        if (cheap) epicEntry.runs.set(runId, cheap);
      }

      // Managerial projection: per-EPIC audit-report.md (presence + mtime + fm).
      const auditPath = join(absEpicDir, 'audit-report.md');
      const audit = await this.indexSourceFile(epicDir, auditPath);
      if (audit) auditReports.set(epicDir, audit);
    }

    // --- Managerial projection sources: plans/*.md ---
    const plans = new Map<string, IndexedSourceFile>();
    const plansDir = join(aidoPath, 'plans');
    const planFiles = (await this.fs.listDir(plansDir)).filter(
      (e) => e.endsWith('.md') && !e.startsWith('.') && e !== 'archive',
    );
    for (const file of planFiles) {
      const planId = file.replace(/\.md$/i, '');
      const sf = await this.indexSourceFile(planId, join(plansDir, file));
      if (sf) plans.set(planId, sf);
    }

    // --- Managerial projection sources: work/backlog.md + lessons-learned.md ---
    const backlog = await this.indexSourceFile(
      'backlog',
      join(aidoPath, 'work', 'backlog.md'),
    );
    const lessons = await this.indexSourceFile(
      'lessons-learned',
      join(aidoPath, 'work', 'lessons-learned.md'),
    );

    return {
      projectId,
      projectDir,
      aidoPath,
      epics,
      plans,
      auditReports,
      backlog,
      lessons,
    };
  }

  /**
   * Build a run's cheap Tier-1 entry: run-DIR mtime + format + state-line. Only
   * reads the `state:` line out of `fsm-state.yaml` (no full parse). Returns
   * null when the path is not a directory we can read. Never throws.
   */
  private async indexRun(runId: string, runDir: string): Promise<IndexedRun | null> {
    const mtimeMs = await this.fs.statMtime(runDir);

    const fsmPath = join(runDir, 'fsm-state.yaml');
    const fsmText = await this.fs.readText(fsmPath);
    if (fsmText !== null) {
      const state = stateLineFrom(fsmText);
      return {
        runId,
        runDir,
        mtimeMs,
        format: state !== null ? 'v3' : 'legacy',
        state,
      };
    }

    // No fsm-state.yaml → legacy marker (state.yaml / plan_progress.json) or stub.
    const legacy =
      (await this.fs.exists(join(runDir, 'state.yaml'))) ||
      (await this.fs.exists(join(runDir, 'plan_progress.json')));
    return {
      runId,
      runDir,
      mtimeMs,
      format: legacy ? 'legacy' : 'stub',
      state: null,
    };
  }

  /**
   * Index one managerial-projection source file: presence + mtime + frontmatter
   * ONLY (never the full body). Returns null when the file is absent. Never
   * throws.
   */
  private async indexSourceFile(
    name: string,
    path: string,
  ): Promise<IndexedSourceFile | null> {
    const mtimeMs = await this.fs.statMtime(path);
    if (mtimeMs === null) return null; // absent / unreadable
    // Read only enough to extract frontmatter; body is deliberately discarded.
    const text = await this.fs.readText(path);
    return {
      name,
      path,
      present: true,
      mtimeMs,
      frontmatter: extractFrontmatter(text),
    };
  }

  // -------------------------------------------------------------------------
  // Tier 2 — lazy memoized RunDetail
  // -------------------------------------------------------------------------

  /**
   * Return a `RunDetail`, memoized. On a hit, the entry is revalidated against
   * the max-file-mtime backstop: if any file under the run dir is newer than
   * when it was cached (even when the run-DIR mtime did NOT move), the entry is
   * dropped and the loader re-invoked. On a miss, the injected loader runs and
   * the result is cached with its observed max-file-mtime.
   */
  async getRunDetail(
    projectId: string,
    epicId: string,
    runId: string,
  ): Promise<RunDetail> {
    const key = runKey(projectId, epicId, runId);
    const cached = this.runDetailCache.get(key);

    if (cached) {
      const runDir = this.resolveRunDir(projectId, epicId, runId);
      const observedMax = runDir ? await this.maxFileMtime(runDir) : null;
      // Fresh only if no file is newer than what we cached. If we cannot
      // resolve the dir (e.g. removed), treat as stale to force a reload.
      if (observedMax !== null && observedMax <= cached.maxFileMtimeMs) {
        return cached.detail;
      }
      this.runDetailCache.delete(key);
    }

    const detail = await this.loader(projectId, epicId, runId);
    const runDir = this.resolveRunDir(projectId, epicId, runId);
    const maxFileMtimeMs = runDir ? ((await this.maxFileMtime(runDir)) ?? 0) : 0;
    this.runDetailCache.set(key, { detail, maxFileMtimeMs });
    return detail;
  }

  /**
   * Evict exactly the matching run-scope LRU key (watcher PRIMARY invalidation).
   * The next {@link getRunDetail} re-invokes the loader.
   */
  invalidate(projectId: string, epicId: string, runId: string): void {
    this.runDetailCache.delete(runKey(projectId, epicId, runId));
  }

  /** Evict a plan-scope key (reserved for plan-detail memoization). */
  invalidatePlan(projectId: string, planId: string): void {
    this.runDetailCache.delete(planKey(projectId, planId));
  }

  /** Current number of memoized RunDetail entries (test/observability helper). */
  get runDetailCacheSize(): number {
    return this.runDetailCache.size;
  }

  /**
   * Resolve a run directory from the Tier-1 index (preferred) or by convention
   * under `<projectsRoot>/<projectId>/.aid-o/work/evidence/<epicId>/<runId>`.
   * Returns null only if the project is not in the index and the convention
   * path cannot be formed.
   */
  private resolveRunDir(
    projectId: string,
    epicId: string,
    runId: string,
  ): string | null {
    const indexed = this.index?.projects.get(projectId);
    const fromIndex = indexed?.epics.get(epicId)?.runs.get(runId)?.runDir;
    if (fromIndex) return fromIndex;
    if (indexed) {
      return join(indexed.aidoPath, 'work', 'evidence', epicId, runId);
    }
    // Fall back to the discovery convention.
    return join(this.projectsRoot, projectId, '.aid-o', 'work', 'evidence', epicId, runId);
  }

  /**
   * Compute the MAX mtime (epoch ms) over all files under a run dir, recursively.
   * This is the backstop: a nested-file change (e.g. `gates/gates_report.json`)
   * that does not bump the run-DIR mtime still moves this value. Returns null if
   * the dir is unreadable / has no readable files. Never throws.
   */
  private async maxFileMtime(runDir: string): Promise<number | null> {
    let max: number | null = null;

    // Recursive walk that joins FULL nested paths (the salvaged
    // FsReader.listDirRecursive flattens to basenames, which would miss a
    // nested `gates/gates_report.json` mtime — the exact backstop case). Never
    // throws: unreadable entries are skipped.
    const walk = async (dir: string): Promise<void> => {
      let entries: import('node:fs').Dirent[];
      try {
        entries = await readdir(dir, { withFileTypes: true });
      } catch {
        return;
      }
      // The dir's own mtime is a baseline so an empty run dir still has a value.
      try {
        const ds = await stat(dir);
        if (max === null || ds.mtimeMs > max) max = ds.mtimeMs;
      } catch {
        // ignore
      }
      for (const ent of entries) {
        const full = join(dir, ent.name);
        if (ent.isDirectory()) {
          await walk(full);
        } else {
          const m = await this.fs.statMtime(full);
          if (m !== null && (max === null || m > max)) max = m;
        }
      }
    };

    await walk(runDir);
    return max;
  }

  // -------------------------------------------------------------------------
  // Bounded merged activity
  // -------------------------------------------------------------------------

  /** Append a timeline event to the bounded merged-activity ring. */
  appendActivity(event: ActivityEvent): void {
    this.activity.push(event);
  }

  /** Append many events (incremental refresh) in order. */
  appendActivityBatch(events: ActivityEvent[]): void {
    for (const e of events) this.activity.push(e);
  }

  /** Return the merged activity in insertion order (oldest first). */
  getActivity(): ActivityEvent[] {
    return this.activity.toArray();
  }

  /** Number of events currently retained (≤ activityBufferSize). */
  get activitySize(): number {
    return this.activity.size;
  }

  // -------------------------------------------------------------------------
  // TTL safety sweep
  // -------------------------------------------------------------------------

  /**
   * 10-min TTL safety sweep (spec §7.2, `config.scanTtlMs`). Re-discovers
   * projects (rebuilds the Tier-1 index) and drops stale Tier-2 entries whose
   * max-file-mtime has moved since they were cached. Idempotent; never throws.
   *
   * @returns the number of Tier-2 entries dropped as stale.
   */
  async sweep(): Promise<number> {
    await this.buildIndex();

    let dropped = 0;
    // Snapshot keys first — we mutate the cache while iterating.
    for (const key of [...this.runDetailCache.keys()]) {
      const cached = this.runDetailCache.peek(key);
      if (!cached) continue;
      const [projectId, epicId, runId] = key.split('/');
      const runDir = this.resolveRunDir(projectId, epicId, runId);
      const observedMax = runDir ? await this.maxFileMtime(runDir) : null;
      // Drop when the dir vanished, or any file is newer than cached.
      if (observedMax === null || observedMax > cached.maxFileMtimeMs) {
        this.runDetailCache.delete(key);
        dropped++;
      }
    }
    return dropped;
  }

  /** TTL (ms) after which a sweep should run (caller schedules the timer). */
  get ttlMs(): number {
    return this.config.scanTtlMs;
  }
}

// ===========================================================================
// Frontmatter / state-line helpers (lightweight — Tier-1 must stay cheap)
// ===========================================================================

/**
 * Extract YAML frontmatter as a flat `Record<string,string>` of scalar keys.
 * Lightweight (regex), not a full YAML parse — Tier-1 must stay sub-second and
 * only needs scalar frontmatter (status, epic_id, title, …). Returns null when
 * there is no frontmatter or the text is unreadable.
 */
export function extractFrontmatter(text: string | null): Record<string, string> | null {
  if (text === null) return null;
  const m = text.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!m) return null;
  const out: Record<string, string> = {};
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^\s*([A-Za-z0-9_]+)\s*:\s*(.*?)\s*$/);
    if (!kv) continue;
    const key = snakeToCamelKey(kv[1]);
    const value = stripYamlScalar(kv[2]);
    if (value.length > 0) out[key] = value;
  }
  return Object.keys(out).length > 0 ? out : null;
}

/** Derive an EPIC id from frontmatter (epicId/id) or the filename stem. */
function epicIdFrom(fm: Record<string, string> | null, file: string): string {
  const stem = file.replace(/\.md$/i, '');
  if (fm) {
    if (fm.epicId) return fm.epicId;
    if (fm.id) return fm.id;
  }
  return stem;
}

/**
 * Extract the `state:` line value from raw fsm-state.yaml text, validated
 * against the six v3 states. Returns null when absent or invalid (→ legacy).
 * Reads only the state line — no full YAML parse (Tier-1 cheapness).
 */
function stateLineFrom(text: string): FsmState | null {
  const m = text.match(/^\s*state\s*:\s*(.+?)\s*$/m);
  if (!m) return null;
  const v = stripYamlScalar(m[1]);
  return VALID_FSM_STATES.has(v) ? (v as FsmState) : null;
}

/** Convert a snake_case key to camelCase (matches the parsers' convention). */
function snakeToCamelKey(key: string): string {
  return key.replace(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

/** Strip surrounding quotes from a YAML scalar value. */
function stripYamlScalar(raw: string): string {
  const v = raw.trim();
  if (
    (v.startsWith('"') && v.endsWith('"')) ||
    (v.startsWith("'") && v.endsWith("'"))
  ) {
    return v.slice(1, -1);
  }
  return v;
}
