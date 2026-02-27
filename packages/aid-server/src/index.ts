import express from 'express';
import cors from 'cors';
import { createServer } from 'node:http';
import { join } from 'node:path';
import { loadConfig } from './config.js';
import { ProjectRegistry } from './services/project-registry.js';
import { WsHandler } from './ws/handler.js';
import { projectRoutes } from './routes/projects.js';
import { pipelineRoutes } from './routes/pipeline.js';
import { queueRoutes } from './routes/queue.js';
import { decisionRoutes } from './routes/decisions.js';
import { evidenceSearchRoutes } from './routes/evidence-search.js';
import { evidenceRoutes } from './routes/evidence.js';
import { auditRoutes } from './routes/audit.js';
import { ideaRoutes } from './routes/ideas.js';
import { usageRoutes } from './routes/usage.js';
import { knowledgeRoutes } from './routes/knowledge.js';
import { backlogRoutes } from './routes/backlog.js';
import { lessonsRoutes } from './routes/lessons.js';
import { epicRoutes } from './routes/epics.js';
import { companionRoutes } from './routes/companion.js';
import { voiceRoutes } from './routes/voice.js';
import { importFromIdeasMd, exportToIdeasMd } from './services/ideas-migration.js';

const config = loadConfig();

const app = express();
app.use(cors({ origin: config.corsOrigins }));
app.use(express.json());

// --- Health check ---
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// --- Initialize project registry ---
const registry = new ProjectRegistry(config.projectRoot);
await registry.init();

// --- Import ideas from IDEAS.md (deduplicates by title) ---
await importFromIdeasMd(config.projectRoot);

// --- API routes ---
app.use('/api', projectRoutes(registry));
app.use('/api/p/:projectId/pipeline', pipelineRoutes(registry));
app.use('/api/p/:projectId/queue', queueRoutes(registry));
app.use('/api/p/:projectId/decisions', decisionRoutes(registry));
app.use('/api/p/:projectId/evidence', evidenceSearchRoutes(registry));
app.use('/api/p/:projectId/evidence', evidenceRoutes(registry));
app.use('/api/p/:projectId/audit', auditRoutes(registry));
app.use('/api/p/:projectId/ideas', ideaRoutes(registry));
app.use('/api/p/:projectId/usage', usageRoutes(registry));
app.use('/api/p/:projectId/knowledge', knowledgeRoutes(registry));
app.use('/api/p/:projectId/backlog', backlogRoutes(registry));
app.use('/api/p/:projectId/lessons', lessonsRoutes(registry));
app.use('/api/p/:projectId/epics', epicRoutes(registry));
app.use('/api/p/:projectId/companion', voiceRoutes(registry));
app.use('/api/p/:projectId/companion', companionRoutes(registry));

// --- API catch-all 404 (must come before static fallback) ---
app.all('/api/*', (_req, res) => {
  res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'API route not found' } });
});

// --- Serve GUI static files in production ---
// Check multiple possible locations: Docker (/app/gui-dist), dev (../aid-gui/dist)
import { existsSync } from 'node:fs';
const guiCandidates = [
  join(import.meta.dirname, '..', 'gui-dist'),              // Docker production
  join(import.meta.dirname, '..', '..', 'aid-gui', 'dist'), // Local dev (from src/)
];
const guiDistPath = guiCandidates.find((p) => existsSync(p)) ?? guiCandidates[1];
app.use(express.static(guiDistPath));
app.get('*', (_req, res) => {
  res.sendFile(join(guiDistPath, 'index.html'), (err) => {
    if (err) res.status(404).json({ error: 'GUI not built. Run: cd packages/aid-gui && npm run build' });
  });
});

// --- HTTP + WebSocket server ---
const server = createServer(app);
const wsHandler = new WsHandler(config);
wsHandler.attach(server);

server.listen(config.port, config.host, () => {
  console.log(`
  ┌──────────────────────────────────────────┐
  │  AID Orchestrator Server                 │
  │  ════════════════════════                │
  │                                          │
  │  HTTP:  http://${config.host}:${config.port}          │
  │  WS:    ws://${config.host}:${config.port}/ws          │
  │  Root:  ${config.projectRoot.slice(0, 36).padEnd(36)}│
  │                                          │
  │  GUI:   http://localhost:${config.port}              │
  └──────────────────────────────────────────┘
`);
});

// Graceful shutdown
for (const sig of ['SIGINT', 'SIGTERM'] as const) {
  process.on(sig, async () => {
    console.log(`\n  Shutting down (${sig})...`);
    try {
      await exportToIdeasMd(config.projectRoot);
    } catch (err) {
      console.error('  Failed to export IDEAS.md on shutdown:', err);
    }
    wsHandler.close();
    server.close(() => process.exit(0));
  });
}
