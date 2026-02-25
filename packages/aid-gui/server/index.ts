import express from "express";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createServer as createViteServer } from "vite";
import { FileWatcher } from "./watchers/file-watcher.ts";
import { StageLogStream } from "./watchers/stage-log-stream.ts";
import { AidWebSocket } from "./ws/websocket.ts";
import type { FileChangeEvent } from "./types.ts";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/** Project root for packages/aid-gui (one level up from server/) */
const PROJECT_ROOT = path.join(__dirname, "..");

/**
 * Resolve the `.aid-o/` directory path.
 *
 * Priority:
 *   1. `AID_PROJECT_PATH` environment variable (absolute path to .aid-o/)
 *   2. Default: `../../.aid-o` relative to this package (the monorepo root)
 */
function resolveAidoPath(): string {
  if (process.env.AID_PROJECT_PATH) {
    return path.resolve(process.env.AID_PROJECT_PATH);
  }
  return path.resolve(PROJECT_ROOT, "..", "..", ".aid-o");
}

/**
 * Find the most recent stage_log.jsonl file path by reading auto-mode-state
 * or falling back to a glob of the evidence directory.
 *
 * Returns null if no stage_log.jsonl can be found (pipeline may not have run
 * yet). The StageLogStream will be started later when the FileWatcher detects
 * a new stage_log.jsonl file.
 */
async function findActiveStageLog(aidoPath: string): Promise<string | null> {
  const fs = await import("node:fs/promises");

  // Strategy 1: Read auto-mode-state.yaml for the current EPIC/run.
  try {
    const autoModeStatePath = path.join(aidoPath, "04-engine", "auto-mode-state.yaml");
    const content = await fs.readFile(autoModeStatePath, "utf-8");
    // Simple regex to extract current EPIC and run from the YAML.
    const epicMatch = content.match(/current_epic:\s*["']?([^"'\s\n]+)/);
    const runMatch = content.match(/current_run:\s*["']?([^"'\s\n]+)/);
    if (epicMatch && runMatch) {
      const stageLogPath = path.join(
        aidoPath,
        "04-engine",
        "evidence",
        epicMatch[1],
        runMatch[1],
        "stage_log.jsonl",
      );
      try {
        await fs.access(stageLogPath);
        return stageLogPath;
      } catch {
        // File does not exist; continue to next strategy.
      }
    }
  } catch {
    // auto-mode-state.yaml may not exist; continue.
  }

  // Strategy 2: Look for the most recently modified stage_log.jsonl in evidence.
  try {
    const evidencePath = path.join(aidoPath, "04-engine", "evidence");
    const epicDirs = await fs.readdir(evidencePath).catch(() => [] as string[]);
    let latestPath: string | null = null;
    let latestMtime = 0;

    for (const epicDir of epicDirs) {
      const epicFullPath = path.join(evidencePath, epicDir);
      const stat = await fs.stat(epicFullPath).catch(() => null);
      if (!stat?.isDirectory()) continue;

      const runDirs = await fs.readdir(epicFullPath).catch(() => [] as string[]);
      for (const runDir of runDirs) {
        const stageLogPath = path.join(epicFullPath, runDir, "stage_log.jsonl");
        try {
          const logStat = await fs.stat(stageLogPath);
          if (logStat.mtimeMs > latestMtime) {
            latestMtime = logStat.mtimeMs;
            latestPath = stageLogPath;
          }
        } catch {
          // This run directory has no stage_log.jsonl; skip.
        }
      }
    }

    return latestPath;
  } catch {
    return null;
  }
}

export function createApp() {
  const app = express();

  app.use(express.json());

  // TODO: Mount API routes here (EPIC E-005-1_4, Step 3+)
  // Example: app.use("/api", apiRouter);

  return app;
}

async function startServer() {
  const app = createApp();
  const PORT = Number(process.env.PORT) || 3000;
  const aidoPath = resolveAidoPath();

  // ---------------------------------------------------------------------------
  // Create HTTP server from Express (required for WebSocket upgrade)
  // ---------------------------------------------------------------------------
  const server = http.createServer(app);

  // ---------------------------------------------------------------------------
  // Vite middleware for development
  // ---------------------------------------------------------------------------
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      root: PROJECT_ROOT,
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(PROJECT_ROOT, "dist");
    app.use(express.static(distPath));
    app.get("*", (_req, res) => {
      res.sendFile(path.join(distPath, "index.html"));
    });
  }

  // ---------------------------------------------------------------------------
  // Initialize watchers and WebSocket server
  // ---------------------------------------------------------------------------
  const fileWatcher = new FileWatcher(aidoPath);
  const stageLogStream = new StageLogStream({ bufferSize: 100 });
  const aidWebSocket = new AidWebSocket(server);

  // Provide the stage log buffer supplier for replay on subscription.
  aidWebSocket.setStageLogBufferSupplier(() => stageLogStream.getBuffer());

  // Wire up: FileWatcher events -> WebSocket broadcast
  fileWatcher.on("event", (event: FileChangeEvent) => {
    aidWebSocket.broadcast(event);

    // Detect new stage_log.jsonl files for automatic rotation.
    if (
      event.changeType === "add" &&
      event.filePath.endsWith("stage_log.jsonl") &&
      event.filePath !== stageLogStream.currentFilePath
    ) {
      console.log(`[index] New stage_log.jsonl detected: ${event.filePath}`);
      stageLogStream.switchFile(event.filePath).catch((err: unknown) => {
        const msg = err instanceof Error ? err.message : String(err);
        console.error(`[index] Failed to switch stage log file: ${msg}`);
      });
    }
  });

  // Wire up: StageLogStream events -> WebSocket broadcast
  stageLogStream.on("event", (event) => {
    aidWebSocket.broadcast(event);
  });

  // Log watcher errors (non-fatal).
  fileWatcher.on("error", (err: Error) => {
    console.error(`[FileWatcher] Error: ${err.message}`);
  });

  stageLogStream.on("error", (err: Error) => {
    console.error(`[StageLogStream] Error: ${err.message}`);
  });

  // ---------------------------------------------------------------------------
  // Start everything
  // ---------------------------------------------------------------------------
  server.listen(PORT, "0.0.0.0", () => {
    console.log(`AID Dashboard server running on http://localhost:${PORT}`);
    console.log(`WebSocket server available at ws://localhost:${PORT}/ws`);
    console.log(`Watching .aid-o/ at: ${aidoPath}`);
  });

  // Start the WebSocket heartbeat and idle timers.
  aidWebSocket.start();

  // Start file watcher (non-blocking — logs ready state).
  fileWatcher
    .start()
    .then(() => {
      console.log("[FileWatcher] Ready — watching for .aid-o/ changes");
    })
    .catch((err: unknown) => {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[FileWatcher] Failed to start: ${msg}`);
    });

  // Start stage log stream if an active stage_log.jsonl exists.
  findActiveStageLog(aidoPath)
    .then((stageLogPath) => {
      if (stageLogPath) {
        console.log(`[StageLogStream] Tailing: ${stageLogPath}`);
        return stageLogStream.start(stageLogPath);
      } else {
        console.log(
          "[StageLogStream] No active stage_log.jsonl found — will start on detection",
        );
      }
    })
    .catch((err: unknown) => {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[StageLogStream] Failed to start: ${msg}`);
    });

  // ---------------------------------------------------------------------------
  // Graceful shutdown
  // ---------------------------------------------------------------------------
  const shutdown = () => {
    console.log("\n[Shutdown] Stopping server...");

    aidWebSocket.stop();
    stageLogStream.stop();

    fileWatcher
      .stop()
      .then(() => {
        server.close(() => {
          console.log("[Shutdown] Server stopped.");
          process.exit(0);
        });
      })
      .catch(() => {
        server.close(() => {
          process.exit(1);
        });
      });

    // Force exit after 5 seconds if graceful shutdown stalls.
    setTimeout(() => {
      console.error("[Shutdown] Forced exit after timeout.");
      process.exit(1);
    }, 5000);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

startServer();
