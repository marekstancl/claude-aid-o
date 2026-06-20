/**
 * ProjectScanner test suite (EPIC E-047-2_7, Step 6).
 *
 * Uses temp-dir fixtures that replicate the real `/opt/eco/projects` layout —
 * NEVER the live tree. Each test builds an isolated mkdtemp scan-root with the
 * project/.aid-o/{config,work,tasks} structure under test.
 *
 * Acceptance Criteria covered (see Step 6 dispatch):
 *  AC1 — HARD REGRESSION: both `vulcan.broken-*` and `cicero.broken-*` excluded;
 *        sibling dirs without `.aid-o` absent from results.
 *  AC2 — nested `.aid-o` (work/ only, no config/) NOT surfaced (depth-1 + sanity).
 *  AC3 — latestRun picks max started_at (NON-lexicographic); mtime fallback.
 *  AC4 — workspace missing work/ still listed, partial:true, no throw.
 *  AC5 — per-run format classification v3 / legacy / stub.
 *  AC6 — normal project: correct epicsTotal/runsTotal rollups + non-null activeRun.
 */

import { mkdtemp, mkdir, writeFile, rm, utimes } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { ProjectScanner, isDenylistedName } from './project-scanner.js';

let scanRoot: string;

beforeEach(async () => {
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-scanner-'));
});

afterEach(async () => {
  await rm(scanRoot, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

/** Create a minimal valid workspace: <scanRoot>/<name>/.aid-o/{config,work,tasks}. */
async function makeWorkspace(
  name: string,
  opts: { config?: boolean; work?: boolean; tasks?: boolean } = {},
): Promise<string> {
  const { config = true, work = true, tasks = true } = opts;
  const aido = join(scanRoot, name, '.aid-o');
  await mkdir(aido, { recursive: true });
  if (config) await mkdir(join(aido, 'config'), { recursive: true });
  if (work) await mkdir(join(aido, 'work', 'evidence'), { recursive: true });
  if (tasks) await mkdir(join(aido, 'tasks'), { recursive: true });
  return aido;
}

/** Write a tasks/<epicId>.md with frontmatter declaring epic_id. */
async function makeTask(aido: string, epicId: string): Promise<void> {
  await writeFile(
    join(aido, 'tasks', `${epicId}.md`),
    `---\nstatus: active\nepic_id: ${epicId}\n---\n\n# EPIC: ${epicId} --- Test\n`,
    'utf-8',
  );
}

/** Create a v3 run dir with fsm-state.yaml (state + started_at). */
async function makeV3Run(
  aido: string,
  epicId: string,
  runId: string,
  state: string,
  startedAt: string | null,
): Promise<string> {
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  const started = startedAt === null ? '' : `started_at: "${startedAt}"\n`;
  await writeFile(
    join(runDir, 'fsm-state.yaml'),
    `epic_id: ${epicId}\nrun_id: ${runId}\nstate: ${state}\n${started}`,
    'utf-8',
  );
  return runDir;
}

/** Create a legacy run dir (state.yaml, no fsm-state.yaml). */
async function makeLegacyRun(aido: string, epicId: string, runId: string): Promise<string> {
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  await writeFile(join(runDir, 'state.yaml'), 'state: in_progress\n', 'utf-8');
  return runDir;
}

/** Create a stub run dir (timeline.jsonl only). */
async function makeStubRun(aido: string, epicId: string, runId: string): Promise<string> {
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  await writeFile(join(runDir, 'timeline.jsonl'), '{"event":"started"}\n', 'utf-8');
  return runDir;
}

// ---------------------------------------------------------------------------
// AC1 — HARD REGRESSION: both broken dirs excluded; non-.aid-o siblings absent
// ---------------------------------------------------------------------------

describe('AC1 — denylist excludes broken dirs; non-workspace siblings absent', () => {
  it('excludes BOTH vulcan.broken-* and cicero.broken-*, omits dirs without .aid-o', async () => {
    // Two real, valid workspaces.
    await makeWorkspace('acta');
    await makeWorkspace('vulcan');

    // Broken siblings (denylisted by name) — even WITH a full .aid-o tree.
    await makeWorkspace('vulcan.broken-20260430-0741');
    await makeWorkspace('cicero.broken-20260430-0735');

    // Sibling dirs with NO .aid-o at all.
    await mkdir(join(scanRoot, 'cicero'), { recursive: true });
    await mkdir(join(scanRoot, 'myinvoice'), { recursive: true });
    await mkdir(join(scanRoot, 'panopticon'), { recursive: true });
    await mkdir(join(scanRoot, '_refs'), { recursive: true });

    const scanner = new ProjectScanner(scanRoot);
    const projects = await scanner.scan();
    const ids = projects.map((p) => p.id).sort();

    expect(ids).toEqual(['acta', 'vulcan']);
    expect(ids).not.toContain('vulcan.broken-20260430-0741');
    expect(ids).not.toContain('cicero.broken-20260430-0735');
    // Non-.aid-o siblings absent.
    for (const sibling of ['cicero', 'myinvoice', 'panopticon', '_refs']) {
      expect(ids).not.toContain(sibling);
    }
  });

  it('isDenylistedName flags broken/bak/old, timestamp suffix, leading dot, and backup', () => {
    expect(isDenylistedName('vulcan.broken-20260430-0741')).toBe(true);
    expect(isDenylistedName('cicero.broken-20260430-0735')).toBe(true);
    expect(isDenylistedName('foo.bak')).toBe(true);
    expect(isDenylistedName('foo.old')).toBe(true);
    expect(isDenylistedName('snapshot-20260430-0741')).toBe(true);
    expect(isDenylistedName('.hidden')).toBe(true);
    expect(isDenylistedName('my-backup-dir')).toBe(true);
    expect(isDenylistedName('Backup')).toBe(true);
    // Real project names pass.
    expect(isDenylistedName('vulcan')).toBe(false);
    expect(isDenylistedName('acta')).toBe(false);
    expect(isDenylistedName('aid-orchestrator')).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// AC2 — nested .aid-o (work/ only, no config/) NOT surfaced
// ---------------------------------------------------------------------------

describe('AC2 — nested .aid-o never surfaced (depth-1 glob + config/+work/ sanity)', () => {
  it('does not surface krok/backend/.aid-o or vulcan/ui/.aid-o as projects', async () => {
    // A valid top-level project.
    await makeWorkspace('krok');

    // A nested .aid-o at depth 2 with work/ only (no config/) — must be invisible.
    const nested = join(scanRoot, 'krok', 'backend', '.aid-o');
    await mkdir(join(nested, 'work', 'evidence'), { recursive: true });

    // Another nested one under a different top-level project.
    await makeWorkspace('vulcan');
    const nested2 = join(scanRoot, 'vulcan', 'ui', '.aid-o');
    await mkdir(join(nested2, 'work'), { recursive: true });

    const scanner = new ProjectScanner(scanRoot);
    const projects = await scanner.scan();
    const ids = projects.map((p) => p.id).sort();

    // Only the top-level projects appear — nested segments never become ids.
    expect(ids).toEqual(['krok', 'vulcan']);
    expect(ids).not.toContain('backend');
    expect(ids).not.toContain('ui');
  });

  it('a depth-1 workspace that lacks config/ (work-only) is rejected by sanity check', async () => {
    await makeWorkspace('halfbaked', { config: false, work: true, tasks: false });
    const scanner = new ProjectScanner(scanRoot);
    const projects = await scanner.scan();
    expect(projects.map((p) => p.id)).not.toContain('halfbaked');
  });
});

// ---------------------------------------------------------------------------
// AC3 — latestRun: max started_at (NON-lexicographic), mtime fallback
// ---------------------------------------------------------------------------

describe('AC3 — latestRun picks max started_at, not lexicographic, mtime fallback', () => {
  it('picks the run with the newest started_at even when lexicographic order disagrees', async () => {
    const aido = await makeWorkspace('proj');
    await makeTask(aido, 'E-100');

    // Three run ids that are NOT lexicographically ordered by recency.
    // Lexicographic sort().pop() would return "run_20260224_115f" (last alpha),
    // but the NEWEST started_at belongs to "R-005-4_4-1".
    await makeV3Run(aido, 'E-100', 'R-ABSPATH-001', 'DONE', '2026-01-01T10:00:00Z');
    await makeV3Run(aido, 'E-100', 'run_20260224_115f', 'GATES', '2026-02-24T11:00:00Z');
    await makeV3Run(aido, 'E-100', 'R-005-4_4-1', 'EXECUTE', '2026-06-01T09:00:00Z');

    const scanner = new ProjectScanner(scanRoot);
    const projects = await scanner.scan();
    const proj = projects.find((p) => p.id === 'proj');

    expect(proj).toBeDefined();
    expect(proj?.activeRun).not.toBeNull();
    // The newest started_at wins — NOT the lexicographic last.
    expect(proj?.activeRun?.runId).toBe('R-005-4_4-1');
    expect(proj?.activeRun?.state).toBe('EXECUTE');
    // Sanity: lexicographic sort().pop() would have been wrong.
    const lexLast = ['R-ABSPATH-001', 'run_20260224_115f', 'R-005-4_4-1']
      .slice()
      .sort()
      .pop();
    expect(lexLast).toBe('run_20260224_115f');
    expect(proj?.activeRun?.runId).not.toBe(lexLast);
  });

  it('falls back to max mtime when started_at is absent/unparseable', async () => {
    const aido = await makeWorkspace('proj');
    await makeTask(aido, 'E-200');

    // Both runs lack started_at — selection must use mtime.
    const older = await makeV3Run(aido, 'E-200', 'R-zzz-old', 'DONE', null);
    const newer = await makeV3Run(aido, 'E-200', 'R-aaa-new', 'EXECUTE', null);

    // Force mtimes: older dir = 1000s ago, newer dir = now.
    const now = Date.now() / 1000;
    await utimes(older, now - 1000, now - 1000);
    await utimes(newer, now, now);

    const scanner = new ProjectScanner(scanRoot);
    const projects = await scanner.scan();
    const proj = projects.find((p) => p.id === 'proj');

    // Lexicographically "R-zzz-old" > "R-aaa-new", but newer mtime must win.
    expect(proj?.activeRun?.runId).toBe('R-aaa-new');
  });
});

// ---------------------------------------------------------------------------
// AC4 — workspace missing work/ → listed, partial:true, no throw
// ---------------------------------------------------------------------------

describe('AC4 — partial workspace (missing work/) is listed, never throws', () => {
  it('lists a config-only workspace as partial:true without throwing', async () => {
    await makeWorkspace('partialproj', { config: true, work: false, tasks: false });

    const scanner = new ProjectScanner(scanRoot);
    let projects: Awaited<ReturnType<ProjectScanner['scan']>> = [];
    await expect(
      (async () => {
        projects = await scanner.scan();
      })(),
    ).resolves.not.toThrow();

    const proj = projects.find((p) => p.id === 'partialproj');
    expect(proj).toBeDefined();
    expect(proj?.partial).toBe(true);
    expect(proj?.discovered).toBe(true);
    expect(proj?.runsTotal).toBe(0);
    expect(proj?.activeRun).toBeNull();
    expect(proj?.lastActivityAt).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// AC5 — per-run format classification: v3 / legacy / stub
// ---------------------------------------------------------------------------

describe('AC5 — per-run format classification', () => {
  it('classifies v3, legacy, and stub runs across distinct EPICs', async () => {
    const aido = await makeWorkspace('classproj');
    await makeV3Run(aido, 'E-V3', 'R-v3-1', 'DONE', '2026-03-01T10:00:00Z');
    await makeLegacyRun(aido, 'E-LEG', 'R-leg-1');
    await makeStubRun(aido, 'E-STUB', 'R-stub-1');

    const scanner = new ProjectScanner(scanRoot);
    const projects = await scanner.scan();
    const proj = projects.find((p) => p.id === 'classproj');

    // All three EPIC dirs counted as active (each has >=1 run dir).
    expect(proj?.epicsActive).toBe(3);
    expect(proj?.runsTotal).toBe(3);

    // Only the v3 run produces a usable FSM state → it must be the activeRun
    // (legacy/stub have state:null and are never chosen as activeRun).
    expect(proj?.activeRun).not.toBeNull();
    expect(proj?.activeRun?.epicId).toBe('E-V3');
    expect(proj?.activeRun?.state).toBe('DONE');
  });

  it('does not pick a legacy/stub-only EPIC as activeRun (state null)', async () => {
    const aido = await makeWorkspace('legacyonly');
    await makeLegacyRun(aido, 'E-LEG', 'R-leg-1');
    await makeStubRun(aido, 'E-STUB', 'R-stub-1');

    const scanner = new ProjectScanner(scanRoot);
    const projects = await scanner.scan();
    const proj = projects.find((p) => p.id === 'legacyonly');

    expect(proj?.runsTotal).toBe(2);
    expect(proj?.activeRun).toBeNull(); // no v3 run → no usable state
  });
});

// ---------------------------------------------------------------------------
// AC6 — normal project: rollups + non-null activeRun
// ---------------------------------------------------------------------------

describe('AC6 — normal project: epicsTotal/runsTotal rollups + non-null activeRun', () => {
  it('computes correct rollups and a non-null activeRun', async () => {
    const aido = await makeWorkspace('normal');

    // EPICs declared via tasks/*.md frontmatter.
    await makeTask(aido, 'E-001');
    await makeTask(aido, 'E-002');
    // An archived task must NOT count toward epicsTotal.
    await mkdir(join(aido, 'tasks', 'archive'), { recursive: true });
    await writeFile(
      join(aido, 'tasks', 'archive', 'E-OLD.md'),
      '---\nepic_id: E-OLD\n---\n# old\n',
      'utf-8',
    );

    // Evidence runs: E-001 has two runs, E-002 has one.
    await makeV3Run(aido, 'E-001', 'R-001-1', 'DONE', '2026-01-01T10:00:00Z');
    await makeV3Run(aido, 'E-001', 'R-001-2', 'GATES', '2026-05-01T10:00:00Z');
    await makeV3Run(aido, 'E-002', 'R-002-1', 'EXECUTE', '2026-02-01T10:00:00Z');

    const scanner = new ProjectScanner(scanRoot);
    const projects = await scanner.scan();
    const proj = projects.find((p) => p.id === 'normal');

    expect(proj).toBeDefined();
    expect(proj?.partial).toBe(false);
    // E-001, E-002 (tasks) — archive/E-OLD excluded. Evidence adds no new ids.
    expect(proj?.epicsTotal).toBe(2);
    expect(proj?.epicsActive).toBe(2); // both have run dirs
    expect(proj?.runsTotal).toBe(3);
    expect(proj?.lastActivityAt).not.toBeNull();

    // activeRun = latest run of the most-recently-active EPIC. E-001/R-001-2
    // (started 2026-05-01) is the global newest started_at.
    expect(proj?.activeRun).not.toBeNull();
    expect(proj?.activeRun?.epicId).toBe('E-001');
    expect(proj?.activeRun?.runId).toBe('R-001-2');
    expect(proj?.activeRun?.state).toBe('GATES');

    // Health placeholder shape (full computation lands in Step 8).
    expect(proj?.health.value).toBeNull();
    expect(proj?.health.partial).toBe(true);
    expect(proj?.health.confidence).toBe('low');
  });

  it('returns an empty list for an unreadable / nonexistent scan root (no throw)', async () => {
    const scanner = new ProjectScanner(join(scanRoot, 'does-not-exist'));
    await expect(scanner.scan()).resolves.toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// REGRESSION: Deadlock fix for nested-semaphore (Finding 1, CRITICAL)
// ---------------------------------------------------------------------------

describe('REGRESSION: deadlock with >16 concurrent projects (nested semaphore)', () => {
  it('completes scan of 20 projects without deadlock', async () => {
    // Create 20 projects (exceeds the SCAN_CONCURRENCY=16 threshold).
    // Each has 1 task (EPIC) and 1 v3 run to exercise all three nesting levels.
    const projectCount = 20;
    const projects = [];
    for (let i = 1; i <= projectCount; i++) {
      const name = `proj-${String(i).padStart(2, '0')}`;
      const aido = await makeWorkspace(name);
      const epicId = `E-${i}`;
      await makeTask(aido, epicId);
      // Create 2 runs per epic to stress-test run collection
      await makeV3Run(aido, epicId, `R-${i}-1`, 'DONE', `2026-01-0${(i % 9) + 1}T10:00:00Z`);
      await makeV3Run(aido, epicId, `R-${i}-2`, 'EXECUTE', `2026-02-0${(i % 9) + 1}T10:00:00Z`);
      projects.push(name);
    }

    const scanner = new ProjectScanner(scanRoot);
    const startTime = Date.now();

    // This should complete quickly (~1-2 seconds), not hang indefinitely.
    // The test timeout is 10 seconds via vitest config; we'll assert completion.
    const results = await scanner.scan();
    const elapsed = Date.now() - startTime;

    // Verify all projects were discovered.
    expect(results).toHaveLength(projectCount);
    expect(results.map((p) => p.id).sort()).toEqual(projects.sort());

    // Each project should have epicsTotal=1, runsTotal=2.
    for (const proj of results) {
      expect(proj.epicsTotal).toBe(1);
      expect(proj.runsTotal).toBe(2);
      expect(proj.epicsActive).toBe(1);
      expect(proj.activeRun).not.toBeNull();
    }

    // Assert completion within reasonable time (< 5 seconds).
    // With the per-level limiters, this stress test should complete in ~1-2 seconds.
    expect(elapsed).toBeLessThan(5000);
  });
});

// ---------------------------------------------------------------------------
// Date-object guard for started_at (Finding 2, LOW)
// ---------------------------------------------------------------------------

describe('REGRESSION: started_at Date-object guard (js-yaml unquoted timestamp)', () => {
  it('honors started_at as Date object (js-yaml unquoted timestamp parsing)', async () => {
    const aido = await makeWorkspace('dateproj');
    const epicId = 'E-date-test';
    await makeTask(aido, epicId);

    // Write fsm-state.yaml with UNQUOTED started_at (js-yaml parses as Date object).
    // This mimics how js-yaml treats unquoted ISO timestamps.
    const runDir = join(aido, 'work', 'evidence', epicId, 'R-date-1');
    await mkdir(runDir, { recursive: true });
    await writeFile(
      join(runDir, 'fsm-state.yaml'),
      `epic_id: ${epicId}
run_id: R-date-1
state: DONE
started_at: 2026-04-15T14:30:00Z
`,
      'utf-8',
    );

    const scanner = new ProjectScanner(scanRoot);
    const projects = await scanner.scan();
    const proj = projects.find((p) => p.id === 'dateproj');

    // The run should be recognized as v3 with a valid started_at (not null).
    expect(proj).toBeDefined();
    expect(proj?.activeRun).not.toBeNull();
    expect(proj?.activeRun?.runId).toBe('R-date-1');
    expect(proj?.activeRun?.state).toBe('DONE');
  });
});
