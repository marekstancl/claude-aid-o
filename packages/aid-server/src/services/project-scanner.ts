/**
 * Project scanner (EPIC E-047-2_7, Step 6).
 *
 * NET-NEW cross-project discovery service. Auto-discovers top-level `.aid-o`
 * workspaces under `config.projectsRoot`, applies the denylist + layout sanity
 * check, builds the `Project[]` list, and selects the latest run per EPIC
 * CORRECTLY — by `started_at` (from `fsm-state.yaml`) descending, falling back
 * to file mtime, NEVER lexicographic `runs.sort().pop()`.
 *
 * This service functionally REPLACES `ProjectRegistry` but does NOT delete it:
 * routes/{epics,pipeline,queue}.ts still import the registry, and wiring the
 * scanner into routes is a later phase. The scanner is purely additive here.
 *
 * Reliability posture (§4.0): NEVER throws on a broken or partial workspace.
 * A missing `work/` or `tasks/` degrades the project to `partial: true` and is
 * still listed. All disk reads route through `FsReader`, whose methods are
 * already never-throw.
 */

import { basename, dirname, join } from 'node:path';
import { readdir, stat } from 'node:fs/promises';
import pLimit from 'p-limit';
import type { FsmState, Project, RunFormat } from '@aid/contract';
import { FsReader } from './fs-reader.js';

// Step 7 (E-047-2_7): the two-tier cache machinery lives in scanner-cache.ts
// (kept separable for testability). Re-exported here so consumers can pull the
// scanner + its cache from one module. The cache wraps a ProjectScanner for the
// Tier-1 index build and memoizes Tier-2 RunDetail via an INJECTED loader (the
// real loader arrives in Step 8). The ProjectScanner class below is UNCHANGED —
// Step 6 behavior and all its tests are preserved.
export {
  ScannerCache,
  CircularBuffer,
  runKey,
  planKey,
  extractFrontmatter,
  createScannerCache,
} from './scanner-cache.js';
export type {
  RunDetailLoader,
  ScannerCacheConfig,
  ScannerCacheFactoryConfig,
  Tier1Index,
  IndexedProject,
  IndexedEpic,
  IndexedRun,
  IndexedSourceFile,
} from './scanner-cache.js';

// Step 8 (E-047-2_7): the RunDetail builder + its loader factory. Re-exported
// here so consumers pull the scanner, its cache, and the assembler from one
// module surface. The builder is wired into the cache via createScannerCache.
export { buildRunDetail, createRunDetailLoader } from './run-detail.js';
export type { RunDetailDeps } from './run-detail.js';

/** Concurrency cap for the cold-scan disk reads (spec §7.2). */
const SCAN_CONCURRENCY = 16;

/** The six valid v3 FSM states (from the raw contract, §4.0 #9). */
const VALID_FSM_STATES: ReadonlySet<string> = new Set<FsmState>([
  'READY',
  'EXECUTE',
  'GATES',
  'ESCALATION',
  'DONE',
  'ERROR',
]);

/**
 * Denylist regexes for project directory names (spec §7.2).
 *
 * A project dir is EXCLUDED when its basename matches any of:
 * - `/\.(broken|bak|old)\b/` — `.broken` / `.bak` / `.old` markers anywhere
 *   (e.g. `vulcan.broken-20260430-0741`, `cicero.broken-20260430-0735`)
 * - `/-\d{8}-\d{4}$/` — a trailing `-YYYYMMDD-HHMM` timestamp suffix
 * - a leading dot (hidden dir)
 * - contains the substring "backup" (case-insensitive)
 */
const DENY_BROKEN = /\.(broken|bak|old)\b/;
const DENY_TIMESTAMP_SUFFIX = /-\d{8}-\d{4}$/;
const DENY_LEADING_DOT = /^\./;
const DENY_BACKUP = /backup/i;

/**
 * Return true if a project directory basename is denylisted (spec §7.2).
 *
 * NOTE: the layout sanity check (`config/` AND `work/` must exist under
 * `.aid-o/`) is applied separately in {@link ProjectScanner.scan}, because it
 * requires disk access. This name-only predicate is exported for unit testing.
 */
export function isDenylistedName(name: string): boolean {
  return (
    DENY_BROKEN.test(name) ||
    DENY_TIMESTAMP_SUFFIX.test(name) ||
    DENY_LEADING_DOT.test(name) ||
    DENY_BACKUP.test(name)
  );
}

/** Internal: one discovered run directory plus its sort key material. */
interface RunCandidate {
  runId: string;
  runDir: string;
  /** `started_at` from fsm-state.yaml when parseable (epoch ms), else null. */
  startedAtMs: number | null;
  /** Raw ISO `started_at` string when present (for activeRun reporting). */
  startedAtIso: string | null;
  /** Directory mtime in epoch ms (fallback sort key), null if unreadable. */
  mtimeMs: number | null;
  /** v3 / legacy / stub classification (§4.0 #9/#10). */
  format: RunFormat;
  /** FSM state when v3, else null. */
  state: FsmState | null;
}

/** Conservative health placeholder — full computation arrives with Step 8. */
function placeholderHealth(): Project['health'] {
  return {
    value: null,
    partial: true,
    confidence: 'low',
    compliancePassRate: null,
    openViolations: 0,
    lastGateOverall: null,
    warnings: [],
  };
}

export class ProjectScanner {
  private readonly fs: FsReader;
  /** Limiter for top-level project scan (buildProject tasks). */
  private readonly limitProjects = pLimit(SCAN_CONCURRENCY);
  /** Limiter for EPIC discovery within projects (discoverEpics tasks). */
  private readonly limitEpics = pLimit(SCAN_CONCURRENCY);
  /** Limiter for run collection within EPICs (collectRunCandidates tasks). */
  private readonly limitRuns = pLimit(SCAN_CONCURRENCY);

  /**
   * @param projectsRoot - cross-project discovery root (`config.projectsRoot`,
   *   `AID_PROJECTS_ROOT`, default `/opt/eco/projects`). The directory whose
   *   immediate children are candidate projects.
   * @param fs - optional FsReader (stateless, no-arg instance). Injectable for
   *   tests; defaults to a fresh stateless instance.
   */
  constructor(
    private readonly projectsRoot: string,
    fs?: FsReader,
  ) {
    this.fs = fs ?? new FsReader();
  }

  /**
   * Discover all candidate `.aid-o` workspaces at depth 1 under `projectsRoot`,
   * apply the denylist + layout sanity check, and build the `Project[]` list.
   *
   * Discovery rules (spec §7.2):
   * - glob `<projectsRoot>/<project>/.aid-o` at DEPTH 1 only — a single path
   *   segment between root and `.aid-o`. Nested `.aid-o` (e.g.
   *   `krok/backend/.aid-o`) is NEVER reached and never surfaced.
   * - exclude denylisted names AND any workspace lacking BOTH `config/` and
   *   `work/` subdirs (layout-drift sanity check — this also rejects the
   *   work-only nested workspaces).
   * - projectId = basename(dirname(.aid-o)).
   *
   * Never throws: an unreadable root yields an empty list; a broken project
   * degrades to `partial: true`.
   */
  async scan(): Promise<Project[]> {
    const entries = await this.safeReaddir(this.projectsRoot);

    // Depth-1 candidates: each immediate child that is a directory.
    const candidateNames: string[] = [];
    await Promise.all(
      entries.map((name) =>
        this.limitProjects(async () => {
          if (isDenylistedName(name)) return;
          const projectDir = join(this.projectsRoot, name);
          if (!(await this.isDir(projectDir))) return;
          candidateNames.push(name);
        }),
      ),
    );

    const projects: Project[] = [];
    await Promise.all(
      candidateNames.map((name) =>
        this.limitProjects(async () => {
          const project = await this.buildProject(name);
          if (project) projects.push(project);
        }),
      ),
    );

    // Stable, deterministic ordering by id (the scan itself is concurrent).
    projects.sort((a, b) => a.id.localeCompare(b.id));
    return projects;
  }

  /**
   * Build a single `Project` from a candidate directory name, or `null` when
   * the candidate is not a valid AID workspace (no `.aid-o/`, or fails the
   * `config/` + `work/` layout sanity check).
   */
  private async buildProject(name: string): Promise<Project | null> {
    const projectDir = join(this.projectsRoot, name);
    const aidoPath = join(projectDir, '.aid-o');

    // Depth-1 .aid-o must exist and be a directory.
    if (!(await this.isDir(aidoPath))) return null;

    // Layout sanity check (spec §7.2): BOTH config/ and work/ must exist.
    // This rejects work-only nested workspaces surfaced by accident and any
    // layout-drift dir. NOTE: a project missing only work/ is handled below as
    // `partial` — but the sanity check requires config/ AND work/, so a dir
    // with neither is dropped entirely. We treat config/ as the structural
    // gate (an AID workspace always has config/) and surface a missing work/
    // as partial.
    const hasConfig = await this.isDir(join(aidoPath, 'config'));
    if (!hasConfig) return null;

    const hasWork = await this.isDir(join(aidoPath, 'work'));
    const hasTasks = await this.isDir(join(aidoPath, 'tasks'));

    const projectId = basename(dirname(aidoPath));

    // --- (1) EPIC list from tasks/*.md (excluding archive/) via frontmatter ---
    const epicIds = await this.discoverEpics(join(aidoPath, 'tasks'));

    // --- (2) EPIC-run dirs from work/evidence/*/ ---
    const evidenceDir = join(aidoPath, 'work', 'evidence');
    const evidenceEpicDirs = hasWork
      ? (await this.safeReaddir(evidenceDir)).filter(
          (d) => !d.startsWith('.') && d !== 'archive',
        )
      : [];

    // For each evidence EPIC dir, collect run candidates and pick the latest.
    let runsTotal = 0;
    let epicsActive = 0;
    let lastActivityAtMs: number | null = null;
    let activeRun: Project['activeRun'] = null;
    let activeRunStartedAtMs = -Infinity;

    // Union of EPICs known via tasks/ frontmatter and via evidence dirs.
    const allEpicIds = new Set<string>(epicIds);
    for (const d of evidenceEpicDirs) allEpicIds.add(d);

    for (const epicDir of evidenceEpicDirs) {
      const absEpicDir = join(evidenceDir, epicDir);
      const candidates = await this.collectRunCandidates(absEpicDir);
      if (candidates.length === 0) continue;

      runsTotal += candidates.length;
      epicsActive += 1; // has >=1 run dir → active

      // Track the most-recent run-dir mtime across the whole project.
      for (const c of candidates) {
        if (c.mtimeMs !== null && (lastActivityAtMs === null || c.mtimeMs > lastActivityAtMs)) {
          lastActivityAtMs = c.mtimeMs;
        }
      }

      const latest = this.pickLatestRun(candidates);
      if (latest) {
        // activeRun = latest run of the most-recently-active EPIC. We rank
        // EPICs by their latest run's effective start time (started_at when
        // parseable, else mtime), and keep the global winner.
        const effective =
          latest.startedAtMs ?? latest.mtimeMs ?? -Infinity;
        if (effective > activeRunStartedAtMs && latest.state !== null) {
          activeRunStartedAtMs = effective;
          activeRun = {
            epicId: epicDir,
            runId: latest.runId,
            state: latest.state,
          };
        }
      }
    }

    // A project is partial when expected subdirs are missing (never throws).
    const partial = !hasWork || !hasTasks;

    return {
      id: projectId,
      name: projectId,
      path: projectDir,
      aidoPath,
      discovered: true,
      partial,
      epicsTotal: allEpicIds.size,
      epicsActive,
      runsTotal,
      activeRun,
      health: placeholderHealth(),
      lastActivityAt:
        lastActivityAtMs !== null ? new Date(lastActivityAtMs).toISOString() : null,
    };
  }

  /**
   * Discover EPIC ids from `tasks/*.md` (excluding `archive/`). EPIC id comes
   * from frontmatter (`epic_id` → camelCase `epicId`, or `id`) when present,
   * else from the filename stem. Never throws.
   */
  private async discoverEpics(tasksDir: string): Promise<string[]> {
    const entries = await this.safeReaddir(tasksDir);
    const mdFiles = entries.filter(
      (e) => e.endsWith('.md') && !e.startsWith('.') && e !== 'archive',
    );

    const ids: string[] = [];
    await Promise.all(
      mdFiles.map((file) =>
        this.limitEpics(async () => {
          const abs = join(tasksDir, file);
          // Only files (skip a dir named like `something.md`, unlikely).
          if (await this.isDir(abs)) return;
          const text = await this.fs.readText(abs);
          const id = this.epicIdFromMarkdown(text, file);
          if (id) ids.push(id);
        }),
      ),
    );
    return ids;
  }

  /**
   * Derive an EPIC id from a markdown file: frontmatter `epic_id`/`id` first,
   * else the filename stem. Lightweight (no full EPIC parse) — the spec only
   * needs the EPIC list here. Returns null only when the file is unreadable.
   */
  private epicIdFromMarkdown(text: string | null, file: string): string | null {
    const stem = file.replace(/\.md$/i, '');
    if (text === null) return stem; // unreadable → still count by filename
    // Cheap frontmatter scan for epic_id / id (avoids a full parseEpicSpec).
    const fmMatch = text.match(/^---\s*\n([\s\S]*?)\n---/);
    if (fmMatch) {
      const fm = fmMatch[1];
      const epicId = fm.match(/^\s*epic_id\s*:\s*(.+?)\s*$/m);
      if (epicId) return stripYamlScalar(epicId[1]);
      const id = fm.match(/^\s*id\s*:\s*(.+?)\s*$/m);
      if (id) return stripYamlScalar(id[1]);
    }
    return stem;
  }

  /**
   * Read all run directories under an EPIC's evidence dir and build a sorted
   * list of run candidates with their sort-key material (started_at + mtime +
   * format classification). Never throws.
   */
  private async collectRunCandidates(epicDir: string): Promise<RunCandidate[]> {
    const runNames = (await this.safeReaddir(epicDir)).filter(
      (d) => !d.startsWith('.'),
    );

    const candidates: RunCandidate[] = [];
    await Promise.all(
      runNames.map((runId) =>
        this.limitRuns(async () => {
          const runDir = join(epicDir, runId);
          if (!(await this.isDir(runDir))) return;
          const candidate = await this.classifyRun(runId, runDir);
          candidates.push(candidate);
        }),
      ),
    );
    return candidates;
  }

  /**
   * Classify a single run directory (§4.0 #9/#10):
   * - `fsm-state.yaml` present with a valid `state` → **v3** (state captured).
   * - only `state.yaml` / legacy markers → **legacy** (counted, no detail).
   * - only `timeline.jsonl` or empty → **stub** (minimal).
   *
   * Also extracts `started_at` (when v3) for non-lexicographic latest-run
   * selection, and the dir mtime as the universal fallback sort key. Old
   * `01-epics/`, root `plan_progress.json`/`stage_log.jsonl`, and `work/runs/`
   * are NEVER read (§4.0 #10 — out of scope).
   */
  private async classifyRun(runId: string, runDir: string): Promise<RunCandidate> {
    const mtimeMs = await this.fs.statMtime(runDir);

    const fsmStatePath = join(runDir, 'fsm-state.yaml');
    const fsmExists = await this.fs.exists(fsmStatePath);

    if (fsmExists) {
      const parsed = await this.fs.readYamlParsed<{
        state?: string;
        startedAt?: string | Date;
      }>(fsmStatePath);
      const data = parsed.data ?? {};
      const state =
        typeof data.state === 'string' && VALID_FSM_STATES.has(data.state)
          ? (data.state as FsmState)
          : null;

      if (state !== null) {
        let startedAtIso: string | null = null;
        if (typeof data.startedAt === 'string') {
          startedAtIso = data.startedAt;
        } else if (data.startedAt instanceof Date) {
          startedAtIso = data.startedAt.toISOString();
        }
        const startedAtMs = parseIsoMs(startedAtIso);
        return {
          runId,
          runDir,
          startedAtMs,
          startedAtIso,
          mtimeMs,
          format: 'v3',
          state,
        };
      }
      // fsm-state.yaml present but unparseable / invalid state → treat as legacy
      // (it exists but yields no usable v3 detail).
      return {
        runId,
        runDir,
        startedAtMs: null,
        startedAtIso: null,
        mtimeMs,
        format: 'legacy',
        state: null,
      };
    }

    // No fsm-state.yaml → legacy marker (state.yaml) or stub.
    const legacyMarker =
      (await this.fs.exists(join(runDir, 'state.yaml'))) ||
      (await this.fs.exists(join(runDir, 'plan_progress.json')));
    if (legacyMarker) {
      return {
        runId,
        runDir,
        startedAtMs: null,
        startedAtIso: null,
        mtimeMs,
        format: 'legacy',
        state: null,
      };
    }

    // timeline.jsonl-only or empty → stub.
    return {
      runId,
      runDir,
      startedAtMs: null,
      startedAtIso: null,
      mtimeMs,
      format: 'stub',
      state: null,
    };
  }

  /**
   * Pick the latest run from a candidate list (spec §7.2 — CRITICAL).
   *
   * Sort by `started_at` DESC when parseable, else by dir mtime DESC. NEVER
   * `runs.sort().pop()` — run ids like `R-005-4_4-1`, `run_20260224_115f`,
   * `R-ABSPATH-001` are NOT lexicographically ordered (§4.0 #8). Runs whose
   * `started_at` is parseable always outrank runs that only have mtime; among
   * started_at-bearing runs, the max started_at wins; among the rest, max
   * mtime wins. Returns null for an empty list.
   */
  private pickLatestRun(candidates: RunCandidate[]): RunCandidate | null {
    if (candidates.length === 0) return null;

    const sorted = [...candidates].sort((a, b) => {
      const aHas = a.startedAtMs !== null;
      const bHas = b.startedAtMs !== null;

      // Both have a parseable started_at → started_at DESC.
      if (aHas && bHas) {
        return (b.startedAtMs as number) - (a.startedAtMs as number);
      }
      // Exactly one has started_at → it wins (parseable started_at preferred).
      if (aHas !== bHas) {
        return aHas ? -1 : 1;
      }
      // Neither has started_at → fall back to mtime DESC.
      const am = a.mtimeMs ?? -Infinity;
      const bm = b.mtimeMs ?? -Infinity;
      return bm - am;
    });

    return sorted[0];
  }

  // ---------------------------------------------------------------------------
  // Low-level never-throw helpers
  // ---------------------------------------------------------------------------

  /** readdir that returns [] instead of throwing on a missing/denied dir. */
  private async safeReaddir(dir: string): Promise<string[]> {
    try {
      return await readdir(dir);
    } catch {
      return [];
    }
  }

  /** True iff `path` exists and is a directory. Never throws. */
  private async isDir(path: string): Promise<boolean> {
    try {
      const s = await stat(path);
      return s.isDirectory();
    } catch {
      return false;
    }
  }
}

/**
 * Parse an ISO 8601 timestamp into epoch ms, or null when absent/unparseable.
 * Used for non-lexicographic latest-run selection (spec §7.2 / §4.0 #8).
 */
function parseIsoMs(iso: string | null): number | null {
  if (!iso) return null;
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? null : ms;
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
