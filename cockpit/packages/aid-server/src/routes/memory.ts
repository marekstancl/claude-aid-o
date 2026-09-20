/**
 * Memory route for the cross-project aid-server (EPIC E-047-4_7, Step 1).
 *
 * MVP1 stub for AID's architectural memory (Qdrant `clavi_facts_{tenant}` via
 * vulcan-memory MCP). Per the §13.9 seam, MVP1 ships ONLY the stable contract
 * shape and a typed placeholder — it makes NO network/MCP call. MVP2 wires this
 * route against {@link MemoryQuery}/{@link MemoryResult} (see seams.ts) without
 * any contract churn.
 *
 * Mounted at `/api` by the bootstrap, so `GET /api/memory` resolves to this
 * router's `GET /memory` and returns the standard success envelope:
 * `{ ok: true, data: { available: false, reason: 'MVP2', entries: [] } }`.
 *
 * STRUCTURAL GUARANTEE (§13.11 AC #22): this module imports NOTHING that can
 * reach the network or an MCP server — no http/https/fetch client, no Qdrant or
 * vulcan-memory client. The only imports are Express's Router and the local
 * response-envelope helper. Keep it that way until MVP2.
 *
 * Module: src/routes/memory.ts
 */

import { Router } from 'express';
import type { MemoryResult } from '@aid/contract';
import { sendOk } from '../api/middleware.js';

/**
 * Build the memory router. `GET /memory` → the MVP1 stub
 * `{ available: false, reason: 'MVP2', entries: [] }`.
 *
 * The handler is fully synchronous and self-contained: it constructs the typed
 * placeholder inline and never awaits anything, so there is provably no I/O.
 */
export function memoryRoutes(): Router {
  const router = Router();

  router.get('/memory', (_req, res) => {
    const stub: MemoryResult = { available: false, reason: 'MVP2', entries: [] };
    sendOk(res, stub);
  });

  return router;
}
