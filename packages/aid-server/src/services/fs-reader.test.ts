/**
 * FsReader test suite (EPIC E-047-2_7, Step 4).
 *
 * Covers the Phase 2 additive surface (per-call multi-project scoping,
 * statMtime, and the tolerant-parse methods that route through the Step 1
 * parsers) WITHOUT regressing the legacy single-project, raw-parse API that
 * routes/queue.ts, companion/build-tools.ts, and the project registry depend on.
 */

import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { FsReader } from './fs-reader.js';

// MED-2 concurrency probe: a shared, hoisted counter the readFile mock updates.
// Inactive by default so it does NOT slow the other tests; the MED-2 test flips
// `active` on. Because FsReader imports `readFile` as a destructured builtin
// binding, a namespace vi.spyOn cannot intercept it — vi.mock replaces the
// module binding itself, which is the only thing FsReader actually calls.
const probe = vi.hoisted(() => ({ inFlight: 0, max: 0, active: false, delayMs: 20 }));
vi.mock('node:fs/promises', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:fs/promises')>();
  return {
    ...actual,
    readFile: async (...args: Parameters<typeof actual.readFile>) => {
      if (!probe.active) return actual.readFile(...args);
      probe.inFlight++;
      probe.max = Math.max(probe.max, probe.inFlight);
      try {
        await new Promise((r) => setTimeout(r, probe.delayMs));
        return await actual.readFile(...args);
      } finally {
        probe.inFlight--;
      }
    },
  };
});

// Two independent project workspaces, each with its own .aid-o tree, plus a
// "missing" path that is never created.
let rootA: string;
let rootB: string;
let aidoA: string;
let aidoB: string;
let missingPath: string;

beforeAll(async () => {
  const base = await mkdtemp(join(tmpdir(), 'aid-fsreader-'));
  rootA = join(base, 'project-a');
  rootB = join(base, 'project-b');
  aidoA = join(rootA, '.aid-o');
  aidoB = join(rootB, '.aid-o');
  await mkdir(aidoA, { recursive: true });
  await mkdir(aidoB, { recursive: true });

  // Project A: a good YAML config (snake_case keys), a good JSON, and a JSONL
  // timeline with one corrupt line.
  await writeFile(
    join(aidoA, 'queue.yaml'),
    'queue_version: 1\nentries:\n  - epic_id: E-001\n    base_commit: abc123\n',
    'utf-8',
  );
  await writeFile(
    join(aidoA, 'plan.json'),
    JSON.stringify({ epic_id: 'E-001', total_steps: 4 }),
    'utf-8',
  );
  await writeFile(
    join(aidoA, 'timeline.jsonl'),
    '{"event":"step_dispatch","step_id":"s1"}\nNOT JSON\n{"event":"step_complete","step_id":"s1"}\n',
    'utf-8',
  );

  // Project B: a different config to prove per-call (not per-instance) scoping.
  await writeFile(
    join(aidoB, 'queue.yaml'),
    'queue_version: 2\nentries:\n  - epic_id: E-999\n    base_commit: def456\n',
    'utf-8',
  );

  // A malformed YAML to exercise the tolerant-parse error path.
  await writeFile(
    join(aidoA, 'broken.yaml'),
    'foo: bar\n  bad: : indentation\n\t- mixed',
    'utf-8',
  );

  missingPath = join(aidoA, 'does-not-exist.yaml');
});

afterAll(async () => {
  // base is the parent of rootA/rootB; remove the whole tree.
  await rm(join(rootA, '..'), { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// AC1 — a single no-arg instance reads from TWO different .aid-o trees
// ---------------------------------------------------------------------------

describe('AC1 — one stateless instance serves multiple projects (per-call scoping)', () => {
  it('reads files from two different project .aid-o paths via one instance', async () => {
    const fs = new FsReader(); // no projectRoot — stateless multi-project mode

    const a = await fs.readYamlParsed<{ queueVersion: number }>(join(aidoA, 'queue.yaml'));
    const b = await fs.readYamlParsed<{ queueVersion: number }>(join(aidoB, 'queue.yaml'));

    expect(a.data?.queueVersion).toBe(1);
    expect(b.data?.queueVersion).toBe(2);
    expect(a.source).toBe(join(aidoA, 'queue.yaml'));
    expect(b.source).toBe(join(aidoB, 'queue.yaml'));
  });
});

// ---------------------------------------------------------------------------
// AC2 — legacy aidoPath getter behavior preserved + clear error in stateless mode
// ---------------------------------------------------------------------------

describe('AC2 — aidoPath getter: legacy works, stateless throws clearly', () => {
  it('legacy new FsReader(root).aidoPath returns <root>/.aid-o', () => {
    const fs = new FsReader(rootA);
    expect(fs.aidoPath).toBe(join(rootA, '.aid-o'));
  });

  it('accessing aidoPath on a no-arg instance throws a clear error', () => {
    const fs = new FsReader();
    expect(() => fs.aidoPath).toThrow(/projectRoot/);
  });
});

// ---------------------------------------------------------------------------
// AC3 — readYamlParsed: malformed → no throw + warning; good → snakeToCamel
// ---------------------------------------------------------------------------

describe('AC3 — readYamlParsed routes through the Step 1 parser', () => {
  it('returns { data: null, warnings, source } on a malformed file (no throw)', async () => {
    const fs = new FsReader();
    let result: Awaited<ReturnType<FsReader['readYamlParsed']>> | undefined;
    await expect(
      (async () => {
        result = await fs.readYamlParsed(join(aidoA, 'broken.yaml'));
      })(),
    ).resolves.not.toThrow();

    expect(result?.data).toBeNull();
    expect(result?.warnings.length).toBeGreaterThan(0);
    expect(result?.source).toBe(join(aidoA, 'broken.yaml'));
  });

  it('applies snakeToCamel on a good file', async () => {
    const fs = new FsReader();
    const r = await fs.readYamlParsed<{ queueVersion: number; entries: unknown[] }>(
      join(aidoA, 'queue.yaml'),
    );
    // snake_case `queue_version` becomes camelCase `queueVersion`.
    expect(r.data?.queueVersion).toBe(1);
    expect((r.data as Record<string, unknown>).queue_version).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// AC4 — readJsonlParsed skips corrupt lines, returns valid entries
// ---------------------------------------------------------------------------

describe('AC4 — readJsonlParsed tolerates corrupt lines', () => {
  it('returns valid entries (camelCased) and skips the corrupt line', async () => {
    const fs = new FsReader();
    const r = await fs.readJsonlParsed<{ event: string; stepId: string }>(
      join(aidoA, 'timeline.jsonl'),
    );
    expect(r.data?.length).toBe(2);
    expect(r.data?.[0].event).toBe('step_dispatch');
    expect(r.data?.[0].stepId).toBe('s1'); // step_id → stepId
    // one warning for the corrupt middle line.
    expect(r.warnings.some((w) => w.severity === 'warning')).toBe(true);
  });

  it('returns { data: [], warnings } for a missing file (no throw)', async () => {
    const fs = new FsReader();
    const r = await fs.readJsonlParsed(join(aidoA, 'no-timeline.jsonl'));
    expect(r.data).toEqual([]);
    expect(r.warnings.length).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// AC5 — statMtime: numeric for existing, null for missing
// ---------------------------------------------------------------------------

describe('AC5 — statMtime', () => {
  it('returns a numeric epoch-ms mtime for an existing file', async () => {
    const fs = new FsReader();
    const mtime = await fs.statMtime(join(aidoA, 'plan.json'));
    expect(typeof mtime).toBe('number');
    expect(mtime as number).toBeGreaterThan(0);
  });

  it('returns null for a missing file (never throws)', async () => {
    const fs = new FsReader();
    await expect(fs.statMtime(missingPath)).resolves.toBeNull();
  });
});

// ---------------------------------------------------------------------------
// AC6 — legacy raw readYaml/readJson stay RAW (no camelCase) — guards queue.ts
//        and companion/build-tools.ts consumers.
// ---------------------------------------------------------------------------

describe('AC6 — legacy raw reads preserve snake_case keys (backward compat)', () => {
  it('raw readYaml keeps snake_case keys untouched', async () => {
    const fs = new FsReader(rootA);
    const raw = await fs.readYaml<Record<string, unknown>>(join(aidoA, 'queue.yaml'));
    expect(raw).not.toBeNull();
    // Raw read MUST keep snake_case; transforming it would break queue.ts.
    expect(raw?.queue_version).toBe(1);
    expect((raw as Record<string, unknown>).queueVersion).toBeUndefined();
  });

  it('raw readJson keeps snake_case keys untouched', async () => {
    const fs = new FsReader(rootA);
    const raw = await fs.readJson<Record<string, unknown>>(join(aidoA, 'plan.json'));
    expect(raw?.epic_id).toBe('E-001');
    expect((raw as Record<string, unknown>).epicId).toBeUndefined();
  });

  it('raw readJsonl keeps snake_case keys and skips corrupt lines', async () => {
    const fs = new FsReader(rootA);
    const raw = await fs.readJsonl<Record<string, unknown>>(join(aidoA, 'timeline.jsonl'));
    expect(raw.length).toBe(2);
    expect(raw[0].step_id).toBe('s1');
    expect((raw[0] as Record<string, unknown>).stepId).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// MED-2 — concurrency limiter: ≤16 in-flight fs calls (module-level pLimit)
// ---------------------------------------------------------------------------

describe('MED-2 — concurrency limiting (fsLimit caps in-flight fs calls at 16)', () => {
  it('never exceeds 16 simultaneous in-flight fs reads under 50 concurrent calls', async () => {
    // Real instrumentation (P047:547): spy node:fs/promises.readFile with a slow
    // wrapper that tracks the in-flight count, so reads genuinely OVERLAP and the
    // max observed concurrency is measurable. If the spy did NOT intercept the
    // FsReader's calls, maxInFlight would stay 0 and the `> 1` assertion below
    // fails — so this test CANNOT pass trivially (the prior decorative version,
    // which only asserted "50 reads succeed", could).
    const testDir = await mkdtemp(join(tmpdir(), 'aid-concurrency-'));
    const filePaths: string[] = [];
    for (let i = 0; i < 50; i++) {
      const path = join(testDir, `file-${String(i).padStart(3, '0')}.txt`);
      await writeFile(path, `content-${i}`, 'utf-8');
      filePaths.push(path);
    }

    probe.inFlight = 0;
    probe.max = 0;
    probe.active = true;
    try {
      const fs = new FsReader();
      const results = await Promise.all(filePaths.map((p) => fs.readText(p)));

      // Correctness: all reads still succeed through the limiter.
      expect(results.length).toBe(50);
      expect(results.every((r) => r !== null && r.length > 0)).toBe(true);

      // The real assertions (P047:547): the limiter is enforced AND reads overlapped.
      // If the mock did not intercept FsReader's readFile, probe.max stays 0 and the
      // first assertion fails — so this test cannot pass trivially.
      expect(probe.max).toBeGreaterThan(1); // reads genuinely overlapped (mock intercepted)
      expect(probe.max).toBeLessThanOrEqual(16); // pLimit(16) caps in-flight
    } finally {
      probe.active = false;
      await rm(testDir, { recursive: true, force: true });
    }
  });
});
