/**
 * Conformance test over the COMMITTED minimal fixture (EPIC E-047-4_7 REOPEN,
 * PM #1/#2/#3/#6). This is the BLOCKING regression guard that the round-4 test
 * failed to be: every assertion below checks a concrete behaviour the PM runtime
 * reviews caught the server getting wrong, against an independent expectation
 * derived from the committed fixture + the aid-diagnostic.sh oracle — NOT a
 * self-reconciling tautology.
 *
 * Fixture (sanitized, hand-authored, NO real-data copy, NO secrets):
 *   - generator: tests/fixtures/build-mini-fixture.mjs  (deterministic)
 *   - tree:      tests/fixtures/mini/                    (committed)
 *   - oracle:    tests/fixtures/mini-oracle.json         (committed, from aid-diagnostic.sh)
 *   - refresh:   scripts/refresh-fixtures.sh             (regen + secret-scan)
 *
 * Cases exercised (see the generator header for the full map):
 *   #1 stem-primary collision  — P702-first vs P702-second; explicit plan_path
 *      attaches to P702-second ONLY; alias "P702" → 409; exact stem → 200.
 *   #2 historical failure       — P701 member E-701-1_1 has an older ERROR run +
 *      a newer passing run → plan outcome `passed`, not `failed`.
 *   #6 metrics partial          — E-703-1_1 run has no usable data → partial:true.
 *   decision b                  — P709-lonely (0 members) is present + unverifiable, not 404.
 *
 * Blocking behaviour (PM #3/#4): a MISSING fixture/oracle FAILS with an
 * instruction to run scripts/refresh-fixtures.sh — it is NEVER skipped.
 *
 * Module: src/integration/real-data-conformance.test.ts
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import supertest from 'supertest';
import { buildServer, type BuiltServer } from '../index.js';
import type { ServerConfig } from '../config.js';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));

const FIXTURE_ROOT = join(__dirname, '../../tests/fixtures/mini');
const PLANS_DIR = join(FIXTURE_ROOT, 'demo/.aid-o/plans');
const ORACLE_PATH = join(__dirname, '../../tests/fixtures/mini-oracle.json');
const REFRESH_HINT =
  'Run `bash packages/aid-server/scripts/refresh-fixtures.sh` to (re)generate the committed fixture + oracle.';

interface OracleRun {
  epic_id: string;
  run_id: string;
  has_state_yaml: boolean;
  has_gates_report: boolean;
  has_compliance: boolean;
  has_audit_report: boolean;
  gates_overall: string;
  compliance_overall: string;
}

let server: BuiltServer;
let oracle: OracleRun[];

/** Unwrap the `{ ok, data }` envelope, asserting 200 + ok. */
function okData<T = any>(res: { status: number; body: any }): T {
  expect(res.status).toBe(200);
  expect(res.body?.ok).toBe(true);
  return res.body.data as T;
}

beforeAll(async () => {
  // BLOCKING (PM #4): a missing fixture/oracle is a HARD FAILURE, not a skip.
  if (!existsSync(FIXTURE_ROOT) || !existsSync(PLANS_DIR)) {
    throw new Error(
      `Conformance fixture missing at ${FIXTURE_ROOT}. This blocking test cannot run.\n${REFRESH_HINT}`,
    );
  }
  if (!existsSync(ORACLE_PATH)) {
    throw new Error(`Conformance oracle missing at ${ORACLE_PATH}.\n${REFRESH_HINT}`);
  }
  oracle = JSON.parse(readFileSync(ORACLE_PATH, 'utf-8')) as OracleRun[];

  const config: ServerConfig = {
    port: 0,
    host: '127.0.0.1',
    projectsRoot: FIXTURE_ROOT,
    hostRoot: FIXTURE_ROOT,
    corsOrigins: '*',
    wsHeartbeatInterval: 30_000,
    wsIdleTimeout: 90_000,
    scanTtlMs: 600_000,
    activityBufferSize: 500,
  } as ServerConfig;
  server = buildServer(config);
  await server.boot();
});

afterAll(async () => {
  if (server) await server.shutdown();
});

describe('conformance: oracle + fixture are committed and well-formed', () => {
  it('oracle has the 6 expected runs', () => {
    expect(oracle.length).toBe(6);
    const ids = new Set(oracle.map((r) => `${r.epic_id}/${r.run_id}`));
    expect(ids.has('E-701-1_1/R-701-1-old')).toBe(true); // the historical ERROR run
    expect(ids.has('E-701-1_1/R-701-1-new')).toBe(true);
    expect(ids.has('E-703-1_1/R-703-1')).toBe(true); // the partial-metrics run
  });
});

describe('conformance #1: stem-primary identity + collision (PM #1)', () => {
  it('analytics returns EVERY plan stem in the fixture — no drop (fixture-derived count)', async () => {
    // Independent expectation: count plan .md files on disk. A drop bug (the
    // original 125→83) would make plans.length < this count and FAIL — this is
    // NOT the self-reconciling totals===length check the round-4 test had.
    const expected = readdirSync(PLANS_DIR).filter((f) => f.endsWith('.md')).length;
    expect(expected).toBe(5);
    const data = okData<{ plans: Array<{ planId: string }> }>(
      await supertest(server.app).get('/api/analytics/plans?project=demo'),
    );
    expect(data.plans.length).toBe(expected);
    // Every stem present by its STEM id (not collapsed to a number).
    const ids = data.plans.map((p) => p.planId).sort();
    expect(ids).toEqual(
      ['P701-alpha', 'P702-first-foo', 'P702-second-bar', 'P703-partial', 'P709-lonely'].sort(),
    );
  });

  it('colliding stems are DISTINCT rows, both flagged ambiguousNumber', async () => {
    const data = okData<{ plans: Array<{ planId: string; ambiguousNumber: boolean }> }>(
      await supertest(server.app).get('/api/analytics/plans?project=demo'),
    );
    const p702 = data.plans.filter((p) => p.planId.startsWith('P702-'));
    expect(p702.map((p) => p.planId).sort()).toEqual(['P702-first-foo', 'P702-second-bar']);
    expect(p702.every((p) => p.ambiguousNumber === true)).toBe(true);
  });

  it('explicit plan_path attaches to P702-SECOND only, never P702-first by number', async () => {
    const second = okData<{ planId: string; epicIds: string[] }>(
      await supertest(server.app).get('/api/plans/demo/P702-second-bar'),
    );
    expect(second.planId).toBe('P702-second-bar');
    expect(second.epicIds).toEqual(['E-702-1_1']); // the explicit-plan_path member

    const first = okData<{ planId: string; epicIds: string[] }>(
      await supertest(server.app).get('/api/plans/demo/P702-first-foo'),
    );
    expect(first.planId).toBe('P702-first-foo');
    expect(first.epicIds).toEqual([]); // NOT the E-702 member
  });

  it('exact stem resolves 200; ambiguous number alias → 409 (never a random pick)', async () => {
    const exact = await supertest(server.app).get('/api/plans/demo/P702-second-bar');
    expect(exact.status).toBe(200);

    const alias = await supertest(server.app).get('/api/plans/demo/P702');
    expect(alias.status).toBe(409);
    expect(alias.body?.error?.code).toBe('AMBIGUOUS_PLAN_NUMBER');
    expect(alias.body?.error?.details?.candidates).toHaveLength(2);
  });
});

describe('conformance #2: historical failure does NOT flip current outcome (PM #2)', () => {
  it('P701-alpha = 3 members, outcome passed despite an older ERROR run on a member', async () => {
    // Oracle proves the historical ERROR run is really present in the fixture.
    const errRun = oracle.find((r) => r.run_id === 'R-701-1-old');
    expect(errRun).toBeDefined();

    const detail = okData<{ planId: string; epicIds: string[] }>(
      await supertest(server.app).get('/api/plans/demo/P701-alpha'),
    );
    expect(detail.epicIds.sort()).toEqual(['E-701-1_1', 'E-701-2_1', 'E-701-4_1']);

    const analytics = okData<{ plans: Array<{ planId: string; outcome: string }> }>(
      await supertest(server.app).get('/api/analytics/plans?project=demo'),
    );
    const p701 = analytics.plans.find((p) => p.planId === 'P701-alpha')!;
    expect(p701.outcome).toBe('passed'); // NOT 'failed' — latest runs all pass
  });
});

describe('conformance decision-b: member-less plan present, not 404', () => {
  it('P709-lonely returns 200 with 0 members and outcome unverifiable', async () => {
    const detail = await supertest(server.app).get('/api/plans/demo/P709-lonely');
    expect(detail.status).toBe(200); // present, NOT dropped/404
    expect(okData<{ epicIds: string[] }>(detail).epicIds).toEqual([]);

    const analytics = okData<{ plans: Array<{ planId: string; outcome: string }> }>(
      await supertest(server.app).get('/api/analytics/plans?project=demo'),
    );
    const lonely = analytics.plans.find((p) => p.planId === 'P709-lonely')!;
    expect(lonely.outcome).toBe('unverifiable');
  });
});

describe('conformance #6: metrics partial with no usable data (PM #6)', () => {
  it('E-703-1_1 (no timing/checkpoints) → metrics.partial true', async () => {
    const m = okData<{ partial: boolean; epicWallTimeS: number | null }>(
      await supertest(server.app).get('/api/metrics/demo/E-703-1_1'),
    );
    expect(m.epicWallTimeS).toBeNull();
    expect(m.partial).toBe(true);
  });
});

describe('conformance: server agrees with the aid-diagnostic.sh oracle', () => {
  it('per-EPIC run counts match the oracle', async () => {
    // Oracle is the independent source of truth for which runs exist on disk.
    const byEpic = new Map<string, number>();
    for (const r of oracle) byEpic.set(r.epic_id, (byEpic.get(r.epic_id) ?? 0) + 1);
    // E-701-1_1 has TWO runs in the oracle (old ERROR + new pass).
    expect(byEpic.get('E-701-1_1')).toBe(2);

    // The server's metrics runCount for that EPIC must match the oracle count.
    const m = okData<{ runCount: number }>(
      await supertest(server.app).get('/api/metrics/demo/E-701-1_1'),
    );
    expect(m.runCount).toBe(byEpic.get('E-701-1_1'));
  });
});
