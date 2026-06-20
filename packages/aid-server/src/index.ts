/**
 * Read-only cross-project server bootstrap (EPIC E-047-3_7, Step 4).
 *
 * This is the rewritten MVP1 Phase 3 bootstrap. It wires:
 *   - Express + cors + JSON body parsing over an `http.Server`,
 *   - the two-tier {@link ScannerCache} (Phase 2) for cross-project discovery
 *     and lazy RunDetail assembly,
 *   - the {@link CrossProjectWatcher} (Step 1) fleet, one chokidar watcher per
 *     discovered `.aid-o/` workspace, with cache-slice invalidation,
 *   - the {@link AidWebSocket} server (Step 2) attached to the same http server,
 *     fed live events from the watcher and replay snapshots from the cache's
 *     merged-activity ring,
 *   - the static GUI `dist/` fallback (tolerated absent in dev/test).
 *
 * Route surface in THIS step: ONLY `/api/health` plus an `/api/*` 404 catch-all
 * (before the static GUI fallback). Steps 5-9 append the cross-project read
 * routes (`/api/projects`, …) onto the same app.
 *
 * Removed vs. the old single-project bootstrap: the project registry, the
 * IDEAS.md import/export migration, the per-project route mounts, the assistant
 * route mounts, and the old single-project websocket handler (replaced here by
 * {@link AidWebSocket}).
 *
 * Testability: {@link createApp} returns a wired Express app WITHOUT listening
 * on a port (supertest drives it directly). {@link buildServer} additionally
 * constructs the http server + watcher + ws and runs the boot reconcile, again
 * without listening. The `listen()` call is guarded behind a main-module check
 * so importing this file (e.g. from a test) never opens a socket.
 *
 * Module: src/index.ts
 */

import { fileURLToPath } from 'node:url';
import { createServer, type Server as HttpServer } from 'node:http';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import express, { type Express } from 'express';
import cors from 'cors';
import { loadConfig, type ServerConfig } from './config.js';
import { createScannerCache, type ScannerCache } from './services/scanner-cache.js';
import { ProjectScanner } from './services/project-scanner.js';
import { FsReader } from './services/fs-reader.js';
import { CrossProjectWatcher } from './watchers/file-watcher.js';
import { AidWebSocket } from './ws/websocket.js';
import { send404 } from './api/middleware.js';
import { healthRoutes } from './routes/health.js';
import { projectRoutes } from './routes/projects.js';
import { epicRoutes } from './routes/epics.js';

// ---------------------------------------------------------------------------
// App factory — pure Express wiring, no http server, no listen.
// ---------------------------------------------------------------------------

/**
 * Build the Express app: cors + JSON + the `/api/health` route + the `/api/*`
 * 404 catch-all + the static GUI fallback. No http server, no port — supertest
 * can drive the returned app directly.
 *
 * The `scanner` is the Phase-2 {@link ScannerCache}; the cross-project read
 * routes mounted below read from it. Steps 6-9 append further `/api/*` routes
 * before the catch-all.
 */
export function createApp(config: ServerConfig, scanner: ScannerCache): Express {
  const app = express();
  app.use(cors({ origin: config.corsOrigins }));
  app.use(express.json());

  // --- API routes (Step 4 health + Step 5 cross-project read routes) ---
  app.use('/api/health', healthRoutes());
  app.use('/api', projectRoutes(scanner));
  app.use('/api', epicRoutes(scanner));

  // --- API catch-all 404 (MUST come before the static GUI fallback) ---
  app.all('/api/*', (_req, res) => {
    send404(res, 'API route');
  });

  // --- Serve the GUI static bundle when present (tolerate absent dist) ---
  const guiDistPath = resolveGuiDist();
  if (guiDistPath) {
    // Hashed assets are long-cached; index.html is always revalidated below.
    app.use(express.static(guiDistPath, { maxAge: '7d', immutable: true, index: false }));
    app.get('*', (_req, res) => {
      res.setHeader('Cache-Control', 'no-cache');
      res.sendFile(join(guiDistPath, 'index.html'), (err) => {
        if (err) {
          res
            .status(404)
            .json({ ok: false, error: { code: 'NOT_FOUND', message: 'GUI not built' } });
        }
      });
    });
  }

  return app;
}

/**
 * Resolve the GUI `dist/` directory across the Docker (`../gui-dist`) and local
 * dev (`../../aid-gui/dist`) layouts. Returns null when neither exists so the
 * server still boots without a built GUI (dev/test tolerance).
 */
function resolveGuiDist(): string | null {
  const here = dirname(fileURLToPath(import.meta.url));
  const candidates = [
    join(here, '..', 'gui-dist'), // Docker production
    join(here, '..', '..', 'aid-gui', 'dist'), // local dev (from src/dist)
  ];
  return candidates.find((p) => existsSync(p)) ?? null;
}

// ---------------------------------------------------------------------------
// Server factory — app + http server + scanner + watcher + ws, no listen.
// ---------------------------------------------------------------------------

/** The fully-wired server surface returned by {@link buildServer}. */
export interface BuiltServer {
  app: Express;
  server: HttpServer;
  scanner: ScannerCache;
  watcher: CrossProjectWatcher;
  ws: AidWebSocket;
  /** Discover + reconcile watchers + build the boot index. Idempotent. */
  boot: () => Promise<void>;
  /** Graceful teardown: stop ws, close watchers, close the http server. */
  shutdown: () => Promise<void>;
}

/**
 * Construct the http server and all read-only infrastructure WITHOUT listening.
 * Discovery feeds the watcher fleet; the watcher feeds the ws; the ws replay
 * snapshot is fed from the cache's merged-activity ring.
 */
export function buildServer(config: ServerConfig): BuiltServer {
  const fs = new FsReader();

  // Two-tier cache: cross-project index + lazy RunDetail (Phase 2 wiring —
  // createScannerCache injects the real buildRunDetail loader internally).
  const scanner = createScannerCache(
    {
      projectsRoot: config.projectsRoot,
      hostRoot: config.hostRoot,
      scanTtlMs: config.scanTtlMs,
      activityBufferSize: config.activityBufferSize,
    },
    fs,
  );

  // A plain ProjectScanner drives watcher reconciliation. It shares the same
  // root + FsReader as the cache, so both observe the same workspace set.
  const projectScanner = new ProjectScanner(config.projectsRoot, fs);

  const app = createApp(config, scanner);
  const server = createServer(app);

  // Watcher fleet: invalidates the matching cache slice on run-scoped changes.
  const watcher = new CrossProjectWatcher({ cache: scanner });

  // WebSocket: attached to the same http server, fed by the watcher + cache.
  const ws = new AidWebSocket(server, '/ws', {
    heartbeatIntervalMs: config.wsHeartbeatInterval,
    idleTimeoutMs: config.wsIdleTimeout,
  });
  watcher.on('event', (event) => ws.broadcast(event));
  watcher.on('error', (err) => {
    console.error('[aid-server] watcher error:', err.message);
  });
  ws.setActivityBufferSupplier(() => scanner.getActivity());

  let booted = false;
  const boot = async (): Promise<void> => {
    if (booted) return;
    booted = true;
    // Build the Tier-1 index (sub-second) and reconcile the watcher fleet
    // against the discovered project list. Never throws on a broken workspace.
    await scanner.buildIndex();
    await watcher.reconcile(await projectScanner.scan());
  };

  const shutdown = async (): Promise<void> => {
    ws.stop();
    await watcher.closeAll();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  };

  return { app, server, scanner, watcher, ws, boot, shutdown };
}

// ---------------------------------------------------------------------------
// Entry point — only runs when this module is executed directly.
// ---------------------------------------------------------------------------

/** Start listening + wire signal handlers. Separated so it is unit-importable. */
async function main(): Promise<void> {
  const config = loadConfig();
  const built = buildServer(config);

  await built.boot();
  built.ws.start();

  built.server.listen(config.port, config.host, () => {
    console.log(
      `[aid-server] listening on http://${config.host}:${config.port} ` +
        `(ws ws://${config.host}:${config.port}/ws, root ${config.projectsRoot})`,
    );
  });

  for (const sig of ['SIGINT', 'SIGTERM'] as const) {
    process.on(sig, () => {
      console.log(`[aid-server] shutting down (${sig})...`);
      built
        .shutdown()
        .then(() => process.exit(0))
        .catch((err: unknown) => {
          console.error('[aid-server] shutdown error:', err);
          process.exit(1);
        });
    });
  }
}

// Main-module guard: importing this file (tests) must NOT open a socket.
if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err: unknown) => {
    console.error('[aid-server] fatal startup error:', err);
    process.exit(1);
  });
}
