/**
 * Hardened raw-artifact endpoint tests (`/file`) — EPIC E-047-3_7, Step 6.
 *
 * Drives the FULLY-WIRED app over a REAL temp fixture `.aid-o` tree (the Step-5
 * `buildFixtureTree`), then plants REAL on-disk anomalies into the discovered
 * run dir — a REAL symlink (`fs.symlink`) and a REAL >1 MB file (`fs.writeFile`
 * of 1 MB + 1 bytes). Nothing is mocked: `lstat`/`stat`/`realpath` run against
 * the real filesystem, so the §7.4.1 security behavior is observed end-to-end.
 *
 * Covered §7.4.1 ACs:
 *  - AC1: an allow-listed artifact (`gates_report.json`) is served 200 as
 *         `{ok:true, data:{format:'json', content}}`.
 *  - AC2: `../`, an absolute `/etc/passwd`, and an allow-list miss (`secrets.env`)
 *         each → 404.
 *  - AC3: a REAL symlink under the run dir → 403 (the required symlink test).
 *  - AC4: a REAL >1 MB artifact → 413; an over-long `name` (>1024) → 414.
 *
 * Module: src/routes/file.test.ts
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm, writeFile, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import request from 'supertest';
import { buildServer, type BuiltServer } from '../index.js';
import { loadConfig, type ServerConfig } from '../config.js';
import { buildFixtureTree } from './__fixtures__/fixture-tree.js';

let scanRoot: string;
let runDir: string;
const builtServers: BuiltServer[] = [];

// The fixture's full DONE run: vulcan / E-100-1_1 / R-E100-1 (real on-disk dir
// with real gates_report.json + audit-report.md + verifier-output-*.md).
const PROJECT = 'vulcan';
const EPIC = 'E-100-1_1';
const RUN = 'R-E100-1';

function testConfig(projectsRoot: string): ServerConfig {
  return { ...loadConfig(), projectsRoot, hostRoot: projectsRoot };
}

async function bootServer(projectsRoot: string): Promise<BuiltServer> {
  const built = buildServer(testConfig(projectsRoot));
  builtServers.push(built);
  await built.boot();
  return built;
}

/** URL for the /file endpoint with a given (unescaped) name query. */
function fileUrl(name: string): string {
  return `/api/epics/${PROJECT}/${EPIC}/runs/${RUN}/file?name=${encodeURIComponent(name)}`;
}

beforeEach(async () => {
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-routes-file-'));
  await buildFixtureTree(scanRoot);
  runDir = join(scanRoot, PROJECT, '.aid-o', 'work', 'evidence', EPIC, RUN);
});

afterEach(async () => {
  for (const b of builtServers.splice(0)) await b.shutdown();
  await rm(scanRoot, { recursive: true, force: true });
});

describe('GET /file — allow-listed artifact (§7.4.1, AC1)', () => {
  it('serves gates_report.json as {ok:true, data:{format:json, content}} (200)', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get(fileUrl('gates_report.json'));
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data.format).toBe('json');
    // Parsed JSON content (FsReader.readParsed) — real fixture values.
    expect(res.body.data.content.overall).toBe('pass');
    expect(res.body.data.content.epic_id).toBe('E-100-1_1');
  });

  it('serves an audit-report.md as markdown text (200)', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get(fileUrl('audit-report.md'));
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data.format).toBe('markdown');
    expect(typeof res.body.data.content).toBe('string');
    expect(res.body.data.content).toContain('Audit Report');
  });

  it('serves a pattern-matched verifier-output-*.md (200)', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get(fileUrl('verifier-output-step-0.md'));
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data.content).toContain('Result: PASS');
  });
});

describe('GET /file — traversal / absolute / allow-list miss (§7.4.1, AC2)', () => {
  it('rejects a name containing ../ → 404', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get(fileUrl('../../../etc/passwd'));
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
  });

  it('rejects an absolute /etc/passwd → 404', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get(fileUrl('/etc/passwd'));
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
  });

  it('rejects an allow-list miss (secrets.env) → 404', async () => {
    const built = await bootServer(scanRoot);

    // Plant a REAL secrets.env in the run dir — it must STILL be refused
    // (allow-list miss, not just absence).
    await writeFile(join(runDir, 'secrets.env'), 'API_KEY=super-secret\n', 'utf-8');

    const res = await request(built.app).get(fileUrl('secrets.env'));
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
  });
});

describe('GET /file — REAL symlink → 403 (§7.4.1, AC3 — required test)', () => {
  it('returns 403 for a REAL symlink planted under the run dir', async () => {
    const built = await bootServer(scanRoot);

    // The symlink uses an allow-listed name so it passes the name allow-list
    // and the containment assert — the ONLY thing that stops it is the lstat
    // symlink guard. It points at the real gates_report.json (a valid target),
    // proving the endpoint refuses to follow even an in-tree symlink.
    const linkPath = join(runDir, 'curator-report.md');
    await symlink(join(runDir, 'gates_report.json'), linkPath);

    const res = await request(built.app).get(fileUrl('curator-report.md'));
    expect(res.status).toBe(403);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });
});

describe('GET /file — size cap 413 / URI cap 414 (§7.4.1, AC4)', () => {
  it('returns 413 for a REAL >1 MB artifact', async () => {
    const built = await bootServer(scanRoot);

    // A REAL file of exactly 1 MB + 1 byte under an allow-listed name.
    const oversized = Buffer.alloc(1024 * 1024 + 1, 0x61); // 'a'
    await writeFile(join(runDir, 'plan.json'), oversized);

    const res = await request(built.app).get(fileUrl('plan.json'));
    expect(res.status).toBe(413);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('PAYLOAD_TOO_LARGE');
  });

  it('returns 414 for a name over 1024 chars', async () => {
    const built = await bootServer(scanRoot);

    const longName = 'a'.repeat(1100) + '.md';
    const res = await request(built.app).get(fileUrl(longName));
    expect(res.status).toBe(414);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('URI_TOO_LONG');
  });
});

describe('GET /file — bad coordinates / missing name', () => {
  it('returns 400 when name is missing', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get(`/api/epics/${PROJECT}/${EPIC}/runs/${RUN}/file`);
    expect(res.status).toBe(400);
    expect(res.body.ok).toBe(false);
  });

  it('returns 404 for an allow-listed but absent artifact', async () => {
    const built = await bootServer(scanRoot);

    // timeline.jsonl is allow-listed but not present in this fixture run dir.
    const res = await request(built.app).get(fileUrl('timeline.jsonl'));
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
  });
});
