/**
 * Cross-project compliance read-route tests (EPIC E-047-3_7, Step 7).
 *
 * Drives the FULLY-WIRED Express app (via {@link buildServer}.app + supertest,
 * no real port) over a REAL temp fixture `.aid-o` tree — the scanner is NOT
 * mocked. A genuine scan + RunDetail assembly exercises the compliance roll-up.
 *
 * Covered ACs (compliance surface):
 *  - AC1: GET /api/compliance → ComplianceView scope:'all' whose
 *         violations[].failures are STRUCTURED ComplianceFailure[]
 *         (check/evidence/severity), NOT string[].
 *  - AC1: GET /api/compliance/<proj> → scoped ComplianceView.
 *  - 400 on a traversal projectId; 404 on an unknown scoped project.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import request from 'supertest';
import { buildServer, type BuiltServer } from '../index.js';
import { loadConfig, type ServerConfig } from '../config.js';
import { buildFixtureTree } from './__fixtures__/fixture-tree.js';
import { writeComplianceFailRun } from './__fixtures__/fixture-tree.js';

let scanRoot: string;
const builtServers: BuiltServer[] = [];

function testConfig(projectsRoot: string): ServerConfig {
  return { ...loadConfig(), projectsRoot, hostRoot: projectsRoot };
}

async function bootServer(projectsRoot: string): Promise<BuiltServer> {
  const built = buildServer(testConfig(projectsRoot));
  builtServers.push(built);
  await built.boot();
  return built;
}

beforeEach(async () => {
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-routes-compliance-'));
  await buildFixtureTree(scanRoot);
});

afterEach(async () => {
  for (const b of builtServers.splice(0)) await b.shutdown();
  await rm(scanRoot, { recursive: true, force: true });
});

describe('GET /api/compliance (Step 7, AC1)', () => {
  it('returns a cross-project ComplianceView scope:all', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/compliance');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const v = res.body.data;
    expect(v.scope).toBe('all');
    // Score envelope (§5.7) — never a bare number.
    expect(v.fsmAdherenceScore).toBeTruthy();
    expect('value' in v.fsmAdherenceScore).toBe(true);
    expect(Array.isArray(v.fsmAdherenceScore.warnings)).toBe(true);
    // Totals over EVALUATED runs (those with compliance.json). The fixture has
    // one passing compliance.json (vulcan DONE-evidence run).
    expect(v.totals.runs).toBeGreaterThanOrEqual(1);
    expect(v.totals.passed).toBeGreaterThanOrEqual(1);
    expect(typeof v.passRate).toBe('number');
  });

  it('violations[].failures are STRUCTURED ComplianceFailure[], not string[]', async () => {
    // Add a failing compliance.json run with structured failures.
    await writeComplianceFailRun(scanRoot);
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/compliance');
    expect(res.status).toBe(200);

    const v = res.body.data;
    expect(Array.isArray(v.violations)).toBe(true);
    expect(v.violations.length).toBeGreaterThan(0);

    const viol = v.violations[0];
    expect(viol.overall).toBe('fail');
    expect(Array.isArray(viol.failures)).toBe(true);
    expect(viol.failures.length).toBeGreaterThan(0);

    // Each failure is a STRUCTURED object — NOT a raw string.
    for (const f of viol.failures) {
      expect(typeof f).toBe('object');
      expect(typeof f).not.toBe('string');
      expect(typeof f.check).toBe('string');
      expect(typeof f.evidence).toBe('string');
      expect(['blocking', 'advisory']).toContain(f.severity);
    }
    // failed count reflects the failing run.
    expect(v.totals.failed).toBeGreaterThanOrEqual(1);
  });
});

describe('GET /api/compliance/:projectId (Step 7, AC1)', () => {
  it('returns a project-scoped ComplianceView', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/compliance/vulcan');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data.scope).toBe('vulcan');
    // Scoped view only counts vulcan's evaluated runs.
    expect(res.body.data.totals.passed).toBeGreaterThanOrEqual(1);
  });

  it('rejects a traversal projectId with 400 (envelope)', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/compliance/..%2fetc');
    expect(res.status).toBe(400);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 404 for an unknown scoped project (envelope)', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/compliance/no-such-project');
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});

describe('compliance honesty (Step 7, §5.7)', () => {
  it('records a warning when runs lack a compliance.json (never 0-as-pass)', async () => {
    // cicero has a single LEGACY run with NO compliance.json → it must NOT be
    // counted as passing; the headline score carries an "excluded" warning.
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/compliance');
    expect(res.status).toBe(200);
    const warnings: string[] = res.body.data.fsmAdherenceScore.warnings;
    expect(warnings.some((w) => w.toLowerCase().includes('compliance.json'))).toBe(true);
  });
});
