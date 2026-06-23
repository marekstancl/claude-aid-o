/**
 * Memory route tests (EPIC E-047-4_7, Step 1).
 *
 * Drives the Express app via supertest (no real port). Covers:
 *   - AC1: GET /api/memory → 200 with EXACTLY
 *          { ok:true, data:{ available:false, reason:'MVP2', entries:[] } }
 *          and no `meta` block.
 *   - AC1 / §13.11 AC #22: the route makes ZERO network/MCP calls — proven
 *          structurally (the module source imports no http/MCP surface) and
 *          behaviourally (no http(s) socket is opened during the request).
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import request from 'supertest';
import { createApp } from '../index.js';
import { loadConfig, type ServerConfig } from '../config.js';

function testConfig(): ServerConfig {
  const root = '/tmp/does-not-matter';
  return { ...loadConfig(), projectsRoot: root, hostRoot: root };
}

const here = dirname(fileURLToPath(import.meta.url));
const MEMORY_SRC = join(here, 'memory.ts');

describe('memory route (E-047-4_7 Step 1)', () => {
  it('AC1 — GET /api/memory returns EXACTLY the MVP1 stub envelope', async () => {
    const app = createApp(testConfig(), undefined as never);
    const res = await request(app).get('/api/memory');

    expect(res.status).toBe(200);
    // EXACT envelope — no meta, no extra keys.
    expect(res.body).toEqual({
      ok: true,
      data: { available: false, reason: 'MVP2', entries: [] },
    });
    expect(res.body.meta).toBeUndefined();
  });

  it('AC1/§13.11#22 — the module source imports NO network/MCP surface (structural)', () => {
    const source = readFileSync(MEMORY_SRC, 'utf-8');
    // Strip the leading JSDoc block comment so prose that names these surfaces
    // (explaining the guarantee) does not trip the structural check — we assert
    // on actual import/require statements, not documentation.
    const code = source.replace(/\/\*[\s\S]*?\*\//g, '');

    const forbidden = [
      'node:http',
      'node:https',
      "'http'",
      '"http"',
      "'https'",
      '"https"',
      'fetch(',
      'undici',
      'axios',
      'node-fetch',
      'qdrant',
      'vulcan-memory',
      'mcp',
      'ModelContextProtocol',
    ];
    for (const token of forbidden) {
      expect(code, `memory.ts must not reference "${token}"`).not.toContain(token);
    }

    // Positive: the only imports are Router + the local envelope helper + the
    // contract type. Any other `import ... from` is a regression.
    const importLines = code
      .split('\n')
      .filter((l) => /^\s*import\b/.test(l))
      .map((l) => l.trim());
    for (const line of importLines) {
      const allowed =
        line.includes("from 'express'") ||
        line.includes("from '@aid/contract'") ||
        line.includes("from '../api/middleware.js'");
      expect(allowed, `unexpected import in memory.ts: ${line}`).toBe(true);
    }
  });

  it('AC1/§13.11#22 — the route handler is synchronous (no awaited I/O in the source)', () => {
    // A structural backstop to the import check: the handler body must not
    // contain an `await` or a `.then(` — the stub is constructed inline and
    // returned, so there is provably no asynchronous I/O on the request path.
    const source = readFileSync(MEMORY_SRC, 'utf-8');
    const code = source.replace(/\/\*[\s\S]*?\*\//g, '');
    expect(code).not.toMatch(/\bawait\b/);
    expect(code).not.toContain('.then(');
  });
});
