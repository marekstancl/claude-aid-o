/**
 * ScannerCache test suite (EPIC E-047-2_7, Step 7).
 *
 * Uses temp-dir fixtures (mkdtemp) that replicate the real `/opt/eco/projects`
 * layout — NEVER the live tree. The injected RunDetail loader is a counting
 * spy so we can assert memoization, invalidation, and the max-file-mtime
 * backstop precisely.
 *
 * Acceptance Criteria (Step 7 dispatch):
 *  AC1 — Tier-1 index builds on boot; index read does NO RunDetail load
 *        (loader NOT called during buildIndex / getProjects).
 *  AC2 — RunDetail request memoized: 2nd call → loader NOT re-invoked.
 *  AC3 — invalidate() evicts exactly the matching key; next request reloads.
 *  AC4 — max-file-mtime backstop: bump nested gates/gates_report.json WITHOUT
 *        touching run-dir mtime → entry stale on next access (reload).
 *  AC5 — merged-activity ring holds ≤ activityBufferSize, evicts oldest-first.
 *  AC6 — Tier-1 indexes plans/*.md, audit-report.md, backlog.md,
 *        lessons-learned.md with mtime+presence (no Tier-2 body parse).
 *  AC7 — CircularBuffer copied in; capacity>=1 guard, wrap-around, toArray order.
 */

import { mkdtemp, mkdir, writeFile, rm, utimes, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ActivityEvent, RunDetail } from '@aid/contract';
import {
  ScannerCache,
  CircularBuffer,
  runKey,
  type ScannerCacheConfig,
} from './scanner-cache.js';

let scanRoot: string;

const CONFIG: ScannerCacheConfig = {
  scanTtlMs: 600_000,
  activityBufferSize: 500,
};

beforeEach(async () => {
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-cache-'));
});

afterEach(async () => {
  await rm(scanRoot, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

async function makeWorkspace(name: string): Promise<string> {
  const aido = join(scanRoot, name, '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'work', 'evidence'), { recursive: true });
  await mkdir(join(aido, 'tasks'), { recursive: true });
  return aido;
}

async function makeTask(aido: string, epicId: string, status = 'active'): Promise<void> {
  await writeFile(
    join(aido, 'tasks', `${epicId}.md`),
    `---\nstatus: ${status}\nepic_id: ${epicId}\ntitle: Demo ${epicId}\n---\n\n# EPIC ${epicId}\n`,
    'utf-8',
  );
}

async function makeV3Run(
  aido: string,
  epicId: string,
  runId: string,
  state: string,
  startedAt: string,
): Promise<string> {
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  await writeFile(
    join(runDir, 'fsm-state.yaml'),
    `epic_id: ${epicId}\nrun_id: ${runId}\nstate: ${state}\nstarted_at: "${startedAt}"\n`,
    'utf-8',
  );
  return runDir;
}

/** A counting stub loader: records every (projectId/epicId/runId) call. */
function makeLoaderSpy() {
  const calls: string[] = [];
  const loader = vi.fn(
    async (projectId: string, epicId: string, runId: string): Promise<RunDetail> => {
      calls.push(runKey(projectId, epicId, runId));
      return stubRunDetail(projectId, epicId, runId);
    },
  );
  return { loader, calls };
}

function stubRunDetail(projectId: string, epicId: string, runId: string): RunDetail {
  return {
    projectId,
    epicId,
    runId,
    format: 'v3',
    state: 'DONE',
    mode: 'standard',
    branch: 'main',
    baseCommit: 'abc123',
    currentStep: 1,
    totalSteps: 1,
    gateRetries: 0,
    escalationCount: 0,
    startedAt: null,
    createdAt: null,
    donePhase: null,
    pmDecision: null,
    steps: [],
    checkpoints: [],
    gates: [],
    compliance: null,
    reports: [],
    audit: {} as RunDetail['audit'],
    timeline: [],
    files: [],
  };
}

// ===========================================================================
// AC1 — Tier-1 boot index does NO RunDetail load
// ===========================================================================

describe('AC1 — Tier-1 boot index (no RunDetail load)', () => {
  it('builds the index and lists projects without invoking the loader', async () => {
    const aido = await makeWorkspace('alpha');
    await makeTask(aido, 'E-001');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader, calls } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);

    const idx = await cache.buildIndex();
    expect(idx.projects.has('alpha')).toBe(true);

    const projects = await cache.getProjects();
    expect(projects.map((p) => p.projectId)).toEqual(['alpha']);

    // The cheap index must classify the run WITHOUT a full RunDetail load.
    const epic = idx.projects.get('alpha')!.epics.get('E-001')!;
    expect(epic.runs.get('R-001')!.format).toBe('v3');
    expect(epic.runs.get('R-001')!.state).toBe('DONE');

    expect(loader).not.toHaveBeenCalled();
    expect(calls).toHaveLength(0);
  });
});

// ===========================================================================
// AC2 — RunDetail memoization
// ===========================================================================

describe('AC2 — RunDetail memoization', () => {
  it('memoizes: the second identical request does not re-invoke the loader', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    const a = await cache.getRunDetail('alpha', 'E-001', 'R-001');
    const b = await cache.getRunDetail('alpha', 'E-001', 'R-001');

    expect(a).toBe(b); // same memoized object
    expect(loader).toHaveBeenCalledTimes(1);
    expect(cache.runDetailCacheSize).toBe(1);
  });

  it('keeps distinct keys independent', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');
    await makeV3Run(aido, 'E-001', 'R-002', 'DONE', '2026-06-01T11:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    await cache.getRunDetail('alpha', 'E-001', 'R-001');
    await cache.getRunDetail('alpha', 'E-001', 'R-002');
    expect(loader).toHaveBeenCalledTimes(2);
  });
});

// ===========================================================================
// AC3 — invalidate evicts exactly the matching key
// ===========================================================================

describe('AC3 — invalidate(projectId, epicId, runId)', () => {
  it('evicts exactly the matching key; subsequent request reloads', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');
    await makeV3Run(aido, 'E-001', 'R-002', 'DONE', '2026-06-01T11:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    await cache.getRunDetail('alpha', 'E-001', 'R-001'); // load 1
    await cache.getRunDetail('alpha', 'E-001', 'R-002'); // load 2
    expect(loader).toHaveBeenCalledTimes(2);

    cache.invalidate('alpha', 'E-001', 'R-001');

    // R-002 still memoized (no reload), R-001 reloads.
    await cache.getRunDetail('alpha', 'E-001', 'R-002');
    expect(loader).toHaveBeenCalledTimes(2);

    await cache.getRunDetail('alpha', 'E-001', 'R-001');
    expect(loader).toHaveBeenCalledTimes(3);
  });
});

// ===========================================================================
// AC4 — max-file-mtime backstop (nested file change, dir mtime unchanged)
// ===========================================================================

describe('AC4 — max-file-mtime backstop', () => {
  it('bumping a nested file (gates/gates_report.json) marks the entry stale', async () => {
    const aido = await makeWorkspace('alpha');
    const runDir = await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');
    const gatesDir = join(runDir, 'gates');
    await mkdir(gatesDir, { recursive: true });
    const gatesFile = join(gatesDir, 'gates_report.json');
    await writeFile(gatesFile, '{"overall":"pass"}', 'utf-8');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    await cache.getRunDetail('alpha', 'E-001', 'R-001');
    expect(loader).toHaveBeenCalledTimes(1);

    // Capture the run-DIR mtime, then bump ONLY the nested file forward and
    // restore the run-dir mtime so the dir-level mtime does NOT move.
    const dirStat = await stat(runDir);
    const future = new Date(Date.now() + 60_000);
    await utimes(gatesFile, future, future);
    await utimes(runDir, dirStat.atime, dirStat.mtime); // restore dir mtime

    // Sanity: the run-DIR mtime is unchanged but the nested file moved.
    const dirStat2 = await stat(runDir);
    expect(dirStat2.mtimeMs).toBeCloseTo(dirStat.mtimeMs, 0);

    // Next access must detect the nested change and reload.
    await cache.getRunDetail('alpha', 'E-001', 'R-001');
    expect(loader).toHaveBeenCalledTimes(2);
  });

  it('an unchanged run stays memoized across accesses', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    await cache.getRunDetail('alpha', 'E-001', 'R-001');
    await cache.getRunDetail('alpha', 'E-001', 'R-001');
    await cache.getRunDetail('alpha', 'E-001', 'R-001');
    expect(loader).toHaveBeenCalledTimes(1);
  });
});

// ===========================================================================
// AC5 — bounded merged-activity ring
// ===========================================================================

describe('AC5 — bounded merged-activity ring', () => {
  function ev(n: number): ActivityEvent {
    return {
      projectId: 'alpha',
      ts: `2026-06-01T10:00:${String(n).padStart(2, '0')}Z`,
      event: `e${n}`,
      raw: {},
    };
  }

  it('holds at most activityBufferSize events and evicts oldest-first', async () => {
    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, { ...CONFIG, activityBufferSize: 3 });

    cache.appendActivity(ev(1));
    cache.appendActivity(ev(2));
    cache.appendActivity(ev(3));
    expect(cache.activitySize).toBe(3);
    expect(cache.getActivity().map((e) => e.event)).toEqual(['e1', 'e2', 'e3']);

    cache.appendActivity(ev(4)); // evicts e1
    expect(cache.activitySize).toBe(3);
    expect(cache.getActivity().map((e) => e.event)).toEqual(['e2', 'e3', 'e4']);

    cache.appendActivityBatch([ev(5), ev(6)]); // evicts e2, e3
    expect(cache.getActivity().map((e) => e.event)).toEqual(['e4', 'e5', 'e6']);
  });
});

// ===========================================================================
// AC6 — Tier-1 indexes managerial-projection source files (no body parse)
// ===========================================================================

describe('AC6 — managerial-projection source-file index', () => {
  it('indexes plans/*.md, audit-report.md, backlog.md, lessons-learned.md', async () => {
    const aido = await makeWorkspace('alpha');
    await makeTask(aido, 'E-001');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    // plans/*.md with frontmatter
    await mkdir(join(aido, 'plans'), { recursive: true });
    await writeFile(
      join(aido, 'plans', 'P022-redesign.md'),
      `---\nstatus: approved\ntitle: Redesign\n---\n\n# Plan body (should NOT be parsed)\n`,
      'utf-8',
    );

    // per-EPIC audit-report.md
    await writeFile(
      join(aido, 'work', 'evidence', 'E-001', 'audit-report.md'),
      `---\nscore: 87\n---\n\n# Audit\n`,
      'utf-8',
    );

    // work/backlog.md + lessons-learned.md
    await writeFile(join(aido, 'work', 'backlog.md'), '# Backlog\n- item\n', 'utf-8');
    await writeFile(join(aido, 'work', 'lessons-learned.md'), '# Lessons\n', 'utf-8');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    const idx = await cache.buildIndex();
    const p = idx.projects.get('alpha')!;

    // Plans: presence + mtime + frontmatter (no body).
    const plan = p.plans.get('P022-redesign')!;
    expect(plan.present).toBe(true);
    expect(plan.mtimeMs).toBeGreaterThan(0);
    expect(plan.frontmatter).toEqual({ status: 'approved', title: 'Redesign' });

    // Audit report keyed by epicId.
    const audit = p.auditReports.get('E-001')!;
    expect(audit.present).toBe(true);
    expect(audit.frontmatter).toEqual({ score: '87' });

    // Backlog + lessons present with mtime.
    expect(p.backlog?.present).toBe(true);
    expect(p.backlog?.mtimeMs).toBeGreaterThan(0);
    expect(p.lessons?.present).toBe(true);

    // All queryable WITHOUT a Tier-2 RunDetail body parse.
    expect(loader).not.toHaveBeenCalled();
  });

  it('absent source files index as null (never throws)', async () => {
    const aido = await makeWorkspace('beta');
    await makeTask(aido, 'E-009');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    const idx = await cache.buildIndex();
    const p = idx.projects.get('beta')!;

    expect(p.backlog).toBeNull();
    expect(p.lessons).toBeNull();
    expect(p.plans.size).toBe(0);
  });
});

// ===========================================================================
// AC7 — CircularBuffer (copied in)
// ===========================================================================

describe('AC7 — CircularBuffer', () => {
  it('rejects capacity < 1', () => {
    expect(() => new CircularBuffer<number>(0)).toThrow(/capacity must be >= 1/);
    expect(() => new CircularBuffer<number>(-5)).toThrow(/capacity must be >= 1/);
  });

  it('accepts capacity 1 (boundary)', () => {
    const b = new CircularBuffer<number>(1);
    b.push(10);
    b.push(20);
    expect(b.toArray()).toEqual([20]);
    expect(b.size).toBe(1);
    expect(b.max).toBe(1);
  });

  it('preserves insertion order before wrap', () => {
    const b = new CircularBuffer<number>(5);
    b.push(1);
    b.push(2);
    b.push(3);
    expect(b.toArray()).toEqual([1, 2, 3]);
    expect(b.size).toBe(3);
  });

  it('wraps around oldest-first when full', () => {
    const b = new CircularBuffer<number>(3);
    [1, 2, 3, 4, 5].forEach((n) => b.push(n));
    expect(b.toArray()).toEqual([3, 4, 5]);
    expect(b.size).toBe(3);
  });

  it('clear() resets to empty', () => {
    const b = new CircularBuffer<number>(3);
    b.push(1);
    b.push(2);
    b.clear();
    expect(b.toArray()).toEqual([]);
    expect(b.size).toBe(0);
  });
});

// ===========================================================================
// TTL sweep — re-discovers + drops stale entries
// ===========================================================================

describe('TTL sweep', () => {
  it('rebuilds the index and drops stale Tier-2 entries', async () => {
    const aido = await makeWorkspace('alpha');
    const runDir = await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    await cache.getRunDetail('alpha', 'E-001', 'R-001');
    expect(cache.runDetailCacheSize).toBe(1);

    // Bump a file forward so the sweep sees the entry as stale.
    const future = new Date(Date.now() + 120_000);
    await writeFile(join(runDir, 'fsm-state.yaml'), 'state: DONE\n', 'utf-8');
    await utimes(join(runDir, 'fsm-state.yaml'), future, future);

    const dropped = await cache.sweep();
    expect(dropped).toBe(1);
    expect(cache.runDetailCacheSize).toBe(0);
  });

  it('exposes the configured TTL', () => {
    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, { ...CONFIG, scanTtlMs: 123 });
    expect(cache.ttlMs).toBe(123);
  });
});

// ===========================================================================
// Security — CWE-22 path traversal defense
// ===========================================================================

describe('Security — CWE-22 path traversal defense (resolveRunDir)', () => {
  it('rejects traversal in projectId (e.g. "../../etc")', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    // Attempt traversal: invalid projectId should be rejected
    const result = await cache.getRunDetail('../../etc', 'E-001', 'R-001');
    // Should return a stub (safe degradation, never throw)
    expect(result.format).toBe('stub');
    expect(result.projectId).toBe('../../etc');
    // Loader should NOT be called for traversal attempts
    expect(loader).not.toHaveBeenCalled();
  });

  it('rejects traversal in epicId', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    // Attempt traversal via epicId
    const result = await cache.getRunDetail('alpha', '../../../etc', 'R-001');
    expect(result.format).toBe('stub');
    expect(loader).not.toHaveBeenCalled();
  });

  it('rejects traversal in runId', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    // Attempt traversal via runId
    const result = await cache.getRunDetail('alpha', 'E-001', '../../secret');
    expect(result.format).toBe('stub');
    expect(loader).not.toHaveBeenCalled();
  });

  it('rejects empty segments', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    // Empty projectId should be rejected
    const result = await cache.getRunDetail('', 'E-001', 'R-001');
    expect(result.format).toBe('stub');
    expect(loader).not.toHaveBeenCalled();
  });

  it('rejects segments with forward slashes', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    // epicId containing / should be rejected
    const result = await cache.getRunDetail('alpha', 'E-001/../../etc', 'R-001');
    expect(result.format).toBe('stub');
    expect(loader).not.toHaveBeenCalled();
  });

  it('accepts valid segments and loads normally', async () => {
    const aido = await makeWorkspace('alpha');
    await makeV3Run(aido, 'E-001', 'R-001', 'DONE', '2026-06-01T10:00:00Z');

    const { loader } = makeLoaderSpy();
    const cache = new ScannerCache(scanRoot, loader, CONFIG);
    await cache.buildIndex();

    // Valid segments should work
    const result = await cache.getRunDetail('alpha', 'E-001', 'R-001');
    expect(result.format).toBe('v3');
    expect(result.state).toBe('DONE');
    expect(loader).toHaveBeenCalledTimes(1);
  });
});
