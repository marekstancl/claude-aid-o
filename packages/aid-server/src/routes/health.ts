/**
 * Health route for the cross-project aid-server (EPIC E-047-3_7, Step 4).
 *
 * A single read-only liveness probe. Mounted at `/api/health` by the bootstrap,
 * so `GET /api/health` resolves to this router's `GET /`. Returns the standard
 * success envelope: `{ ok: true, data: { status: 'ok', ts } }`.
 *
 * Deliberately self-contained — it touches no scanner/watcher/ws state so it can
 * answer even on an empty or partially-broken projects root (AC4).
 *
 * Module: src/routes/health.ts
 */

import { Router } from 'express';
import { sendOk } from '../api/middleware.js';

/** Current time as an ISO 8601 string (kept local — no shared helper exists). */
function isoNow(): string {
  return new Date().toISOString();
}

/** Build the health router. `GET /` → `{ ok, data: { status: 'ok', ts } }`. */
export function healthRoutes(): Router {
  const router = Router();

  router.get('/', (_req, res) => {
    sendOk(res, { status: 'ok', ts: isoNow() });
  });

  return router;
}
