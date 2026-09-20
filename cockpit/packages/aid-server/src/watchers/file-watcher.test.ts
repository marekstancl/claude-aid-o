/**
 * CrossProjectWatcher test suite (EPIC E-047-3_7, Step 1).
 *
 * REAL chokidar watchers + REAL file I/O into temp `.aid-o` fixtures laid out
 * under a `projects/` segment (so `extractProjectId` works). No mocked
 * filesystem — this is the Phase-2 lesson: prove depth-7 reach and the ignore
 * predicate against actual disk events.
 *
 * Acceptance Criteria:
 *  AC1 — depth-6 file work/evidence/<epic>/<run>/gates/gates_report.json emits
 *        exactly ONE event, topic 'gates', projectId set, runRef populated.
 *  AC2 — writes under node_modules/ or to a *.png produce ZERO events.
 *  AC3 — classifyPath maps timeline.jsonl→pipeline.timeline, queue.yaml→queue,
 *        tasks/E-007.md→epics, unmatched→null.
 *  AC4 — reconcile() attaches a new project and detach/closes a removed one
 *        (Map size + close() observed).
 */

import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FileChangeEvent, Project } from '@aid/contract';
import {
  CrossProjectWatcher,
  classifyPath,
  extractProjectId,
  extractRunRef,
} from './file-watcher.js';

// ---------------------------------------------------------------------------
// Fixture scaffolding — layout: <root>/projects/<id>/.aid-o/...
// ---------------------------------------------------------------------------

let root: string;
const liveWatchers: CrossProjectWatcher[] = [];

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'aid-watch-'));
});

afterEach(async () => {
  // Close any watcher created in a test so no FSWatcher handle leaks.
  await Promise.all(liveWatchers.map((w) => w.closeAll().catch(() => {})));
  liveWatchers.length = 0;
  await rm(root, { recursive: true, force: true });
});

/** Create a watcher tracked for afterEach cleanup. */
function makeWatcher(
  opts?: ConstructorParameters<typeof CrossProjectWatcher>[0],
): CrossProjectWatcher {
  const w = new CrossProjectWatcher({ debounceMs: 60, ...opts });
  liveWatchers.push(w);
  return w;
}

/** Materialize a `.aid-o` workspace under `<root>/projects/<id>` and return a Project. */
async function makeProject(id: string): Promise<Project> {
  const projectDir = join(root, 'projects', id);
  const aidoPath = join(projectDir, '.aid-o');
  await mkdir(join(aidoPath, 'config'), { recursive: true });
  await mkdir(join(aidoPath, 'work', 'evidence'), { recursive: true });
  await mkdir(join(aidoPath, 'tasks'), { recursive: true });
  return {
    id,
    name: id,
    path: projectDir,
    aidoPath,
    discovered: true,
    partial: false,
    epicsTotal: 0,
    epicsActive: 0,
    runsTotal: 0,
    activeRun: null,
    health: {
      value: null,
      partial: false,
      confidence: 'low',
      compliancePassRate: null,
      openViolations: 0,
      lastGateOverall: null,
      warnings: [],
    },
    lastActivityAt: null,
  };
}

/** Resolve on the FIRST emitted event (or reject on timeout). */
function nextEvent(w: CrossProjectWatcher, timeoutMs = 3000): Promise<FileChangeEvent> {
  return new Promise<FileChangeEvent>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timed out waiting for event')), timeoutMs);
    w.on('event', (e) => {
      clearTimeout(t);
      resolve(e);
    });
  });
}

/** Collect all events for `windowMs`, then resolve with the list. */
function collectEvents(w: CrossProjectWatcher, windowMs: number): Promise<FileChangeEvent[]> {
  return new Promise<FileChangeEvent[]>((resolve) => {
    const events: FileChangeEvent[] = [];
    w.on('event', (e) => events.push(e));
    setTimeout(() => resolve(events), windowMs);
  });
}

// ===========================================================================
// AC3 — classifyPath / pure path helpers (no watcher needed)
// ===========================================================================

describe('AC3 — classifyPath topic mapping', () => {
  it('maps work/evidence/X/Y/timeline.jsonl → pipeline.timeline', () => {
    expect(classifyPath('work/evidence/E-1/R-1/timeline.jsonl')).toBe('pipeline.timeline');
  });

  it('maps config/queue.yaml → queue', () => {
    expect(classifyPath('config/queue.yaml')).toBe('queue');
  });

  it('maps tasks/E-007.md → epics', () => {
    expect(classifyPath('tasks/E-007.md')).toBe('epics');
  });

  it('returns null for an unmatched path', () => {
    expect(classifyPath('some/random/file.txt')).toBeNull();
  });

  it('maps the depth-6 gates report → gates', () => {
    expect(classifyPath('work/evidence/E-1/R-1/gates/gates_report.json')).toBe('gates');
  });
});

describe('path helpers', () => {
  it('extractProjectId returns the segment after /projects/', () => {
    expect(extractProjectId('/opt/eco/projects/vulcan/.aid-o/config/queue.yaml')).toBe('vulcan');
    expect(extractProjectId('/tmp/no-projects-here/file')).toBeNull();
  });

  it('extractRunRef populates from work/evidence/<epic>/<run>/', () => {
    expect(extractRunRef('work/evidence/E-1/R-2/gates/gates_report.json')).toEqual({
      epicId: 'E-1',
      runId: 'R-2',
    });
    expect(extractRunRef('config/queue.yaml')).toBeNull();
  });
});

// ===========================================================================
// AC1 — depth-6 nested gates report emits exactly one gates event (REAL I/O)
// ===========================================================================

describe('AC1 — depth-7 reach (real chokidar + real write)', () => {
  it('emits exactly ONE gates event with projectId + runRef for a nested gates_report.json', async () => {
    const proj = await makeProject('alpha');
    const w = makeWatcher();
    await w.attach(proj);

    const epicId = 'E-047-3_7';
    const runId = 'R-1';
    const gatesDir = join(proj.aidoPath, 'work', 'evidence', epicId, runId, 'gates');
    await mkdir(gatesDir, { recursive: true });
    const gatesFile = join(gatesDir, 'gates_report.json');

    const eventP = nextEvent(w);
    const all = collectEvents(w, 800);

    await writeFile(gatesFile, '{"overall":"pass"}', 'utf-8');

    const event = await eventP;
    expect(event.type).toBe('file_change');
    expect(event.topic).toBe('gates');
    expect(event.projectId).toBe('alpha');
    expect(event.runRef).toEqual({ epicId, runId });
    expect(event.filePath).toBe(`work/evidence/${epicId}/${runId}/gates/gates_report.json`);
    expect(event.parsedData).toEqual({ overall: 'pass' });

    // Exactly one event for the single write.
    const collected = await all;
    expect(collected.filter((e) => e.topic === 'gates')).toHaveLength(1);
  });
});

// ===========================================================================
// AC2 — node_modules / *.png writes produce ZERO events
// ===========================================================================

describe('AC2 — ignore predicate (node_modules + binary)', () => {
  it('produces ZERO events for node_modules and *.png writes', async () => {
    const proj = await makeProject('beta');
    const w = makeWatcher();
    await w.attach(proj);

    const all = collectEvents(w, 700);

    // node_modules write (should be ignored).
    const nmDir = join(proj.aidoPath, 'node_modules', 'pkg');
    await mkdir(nmDir, { recursive: true });
    await writeFile(join(nmDir, 'index.js'), 'module.exports = {}', 'utf-8');

    // *.png write inside a watched dir (extension-ignored).
    await writeFile(join(proj.aidoPath, 'config', 'logo.png'), 'binary', 'utf-8');

    const collected = await all;
    expect(collected).toHaveLength(0);
  });

  it('still emits for a real config change alongside ignored writes', async () => {
    const proj = await makeProject('gamma');
    const w = makeWatcher();
    await w.attach(proj);

    const all = collectEvents(w, 800);

    await writeFile(join(proj.aidoPath, 'config', 'logo.png'), 'binary', 'utf-8');
    await writeFile(join(proj.aidoPath, 'config', 'queue.yaml'), 'order: []\n', 'utf-8');

    const collected = await all;
    expect(collected.map((e) => e.topic)).toEqual(['queue']);
  });
});

// ===========================================================================
// AC4 — reconcile attaches new + detaches removed (no leaked FSWatcher)
// ===========================================================================

describe('AC4 — reconcile lifecycle', () => {
  it('attaches a newly-added project and detach/closes a removed one', async () => {
    const a = await makeProject('proj-a');
    const b = await makeProject('proj-b');

    const w = makeWatcher();
    await w.reconcile([a, b]);
    expect(w.size).toBe(2);
    expect(w.isWatching('proj-a')).toBe(true);
    expect(w.isWatching('proj-b')).toBe(true);

    // Spy on the underlying chokidar close() for proj-b before it is detached.
    // Access the private map via a typed cast (test-only introspection).
    const internalMap = (w as unknown as {
      watchers: Map<string, { close: () => Promise<void> }>;
    }).watchers;
    const bWatcher = internalMap.get('proj-b')!;
    let closed = false;
    const originalClose = bWatcher.close.bind(bWatcher);
    bWatcher.close = async () => {
      closed = true;
      return originalClose();
    };

    const c = await makeProject('proj-c');
    // Second reconcile: proj-b removed, proj-c added, proj-a unchanged.
    await w.reconcile([a, c]);

    expect(w.size).toBe(2);
    expect(w.isWatching('proj-a')).toBe(true);
    expect(w.isWatching('proj-c')).toBe(true);
    expect(w.isWatching('proj-b')).toBe(false);
    expect(closed).toBe(true); // removed watcher was actually closed
  });

  it('attach is idempotent', async () => {
    const a = await makeProject('solo');
    const w = makeWatcher();
    await w.attach(a);
    await w.attach(a);
    expect(w.size).toBe(1);
  });
});

// ===========================================================================
// Cache-slice invalidation — run-scoped change invalidates the matching slice
// ===========================================================================

describe('cache-slice invalidation', () => {
  it('invalidates exactly (projectId, epicId, runId) on a run-scoped change', async () => {
    const proj = await makeProject('delta');
    const calls: Array<[string, string, string]> = [];
    const w = makeWatcher({
      cache: {
        invalidate: (p: string, e: string, r: string) => calls.push([p, e, r]),
      },
    });
    await w.attach(proj);

    const runDir = join(proj.aidoPath, 'work', 'evidence', 'E-9', 'R-3');
    await mkdir(runDir, { recursive: true });

    const eventP = nextEvent(w);
    await writeFile(join(runDir, 'fsm-state.yaml'), 'state: DONE\n', 'utf-8');
    await eventP;

    expect(calls).toContainEqual(['delta', 'E-9', 'R-3']);
  });

  it('does NOT invalidate for a non-run change (config/queue.yaml)', async () => {
    const proj = await makeProject('epsilon');
    const calls: Array<[string, string, string]> = [];
    const w = makeWatcher({
      cache: {
        invalidate: (p: string, e: string, r: string) => calls.push([p, e, r]),
      },
    });
    await w.attach(proj);

    const eventP = nextEvent(w);
    await writeFile(join(proj.aidoPath, 'config', 'queue.yaml'), 'order: []\n', 'utf-8');
    await eventP;

    expect(calls).toHaveLength(0);
  });
});
