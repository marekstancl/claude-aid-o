/**
 * Companion routes — SSE streaming chat, session management, adapter status.
 *
 * Endpoints:
 *   POST   /api/p/:projectId/companion/send     — SSE-streamed chat response
 *   GET    /api/p/:projectId/companion/sessions  — list sessions (summary)
 *   GET    /api/p/:projectId/companion/sessions/:sessionId — session detail
 *   DELETE /api/p/:projectId/companion/sessions/:sessionId — delete session
 *   PATCH  /api/p/:projectId/companion/sessions/:sessionId — rename session
 *   POST   /api/p/:projectId/companion/sessions/:sessionId/archive — archive
 *   GET    /api/p/:projectId/companion/status    — adapter availability
 */

import { randomUUID } from 'node:crypto';
import { Router, type Request, type Response } from 'express';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';
import {
  createCompanionService,
  type CompanionBundle,
  type CompanionMessage,
} from '../companion/index.js';
import { buildProjectContext } from '../companion/build-context.js';
import { buildCompanionTools } from '../companion/build-tools.js';

// ---------------------------------------------------------------------------
// Route param types
// ---------------------------------------------------------------------------

interface SessionParams extends ProjectParams {
  sessionId: string;
}

interface SendBody {
  message: string;
  sessionId?: string;
  systemPrompt?: string;
}

// ---------------------------------------------------------------------------
// Lazy per-project companion cache
// ---------------------------------------------------------------------------

const companionCache = new Map<string, CompanionBundle>();

async function getCompanion(
  aidoPath: string,
  projectId: string,
): Promise<CompanionBundle> {
  if (!companionCache.has(projectId)) {
    const bundle = await createCompanionService(aidoPath);
    companionCache.set(projectId, bundle);
  }
  return companionCache.get(projectId)!;
}

// ---------------------------------------------------------------------------
// Route factory
// ---------------------------------------------------------------------------

export function companionRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // -------------------------------------------------------------------------
  // POST /send — SSE streaming chat
  // -------------------------------------------------------------------------
  router.post('/send', async (req: Request<ProjectParams>, res: Response) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) {
      return res
        .status(404)
        .json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
    }

    const body = req.body as SendBody;

    if (!body.message || typeof body.message !== 'string') {
      return res
        .status(400)
        .json({ ok: false, error: { code: 'BAD_REQUEST', message: 'message is required' } });
    }

    // Prevent resource exhaustion — cap at 32 000 characters (~8 K tokens at ~4 chars/token)
    if (body.message.length > 32_000) {
      return res
        .status(400)
        .json({ ok: false, error: { code: 'MESSAGE_TOO_LONG', message: 'message must not exceed 32 000 characters' } });
    }

    // Initialise companion lazily
    let companion: CompanionBundle;
    try {
      companion = await getCompanion(fs.aidoPath, req.params.projectId);
    } catch (err) {
      return res.status(503).json({
        ok: false,
        error: {
          code: 'SERVICE_UNAVAILABLE',
          message: `Failed to initialize companion: ${err instanceof Error ? err.message : String(err)}`,
        },
      });
    }

    const { service, sessionStore } = companion;

    // Resolve or create session
    let sessionId = body.sessionId;
    if (!sessionId) {
      const session = await sessionStore.createSession(
        req.params.projectId,
        service.name,
      );
      sessionId = session.id;
    } else {
      // Verify session exists
      const existing = await sessionStore.getSession(sessionId);
      if (!existing) {
        return res.status(404).json({
          ok: false,
          error: { code: 'NOT_FOUND', message: `Session ${sessionId} not found` },
        });
      }
    }

    // Save user message to session
    const userMessage: CompanionMessage = {
      id: randomUUID(),
      role: 'user',
      content: body.message,
      timestamp: new Date().toISOString(),
    };
    await sessionStore.appendMessage(sessionId, userMessage);

    // Set SSE response headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no'); // disable nginx buffering
    res.flushHeaders();

    // Build project context as system prompt (unless caller provided custom one)
    let systemPrompt = body.systemPrompt;
    const project = registry.get(req.params.projectId);
    if (!systemPrompt && project) {
      systemPrompt = await buildProjectContext(project, fs);
    }

    // Build tools for file access (only for adapters that support it)
    let tools;
    if (project) {
      try {
        tools = await buildCompanionTools(project.path, fs);
      } catch {
        // Tools require `ai` + `zod` — not available in all adapters, skip
      }
    }

    // Stream response
    try {
      let fullText = '';

      for await (const chunk of service.stream(body.message, sessionId, systemPrompt, tools)) {
        if (chunk.type === 'text') {
          fullText += chunk.text;
          res.write(`data: ${JSON.stringify({ type: 'text', text: chunk.text })}\n\n`);
        } else if (chunk.type === 'done') {
          // Save assistant response to session
          const assistantMessage: CompanionMessage = {
            id: randomUUID(),
            role: 'assistant',
            content: fullText,
            timestamp: new Date().toISOString(),
            model: chunk.model,
          };
          await sessionStore.appendMessage(sessionId, assistantMessage);

          res.write(
            `data: ${JSON.stringify({
              type: 'done',
              sessionId: chunk.sessionId,
              model: chunk.model,
              usage: chunk.usage,
            })}\n\n`,
          );
          res.end();
          return;
        }
      }

      // If the generator ends without a 'done' chunk, close gracefully
      res.end();
    } catch (err) {
      const errorMessage =
        err instanceof Error ? err.message : 'Unknown streaming error';
      res.write(`data: ${JSON.stringify({ type: 'error', error: errorMessage })}\n\n`);
      res.end();
    }
  });

  // -------------------------------------------------------------------------
  // GET /sessions — list sessions for project
  // -------------------------------------------------------------------------
  router.get('/sessions', async (req: Request<ProjectParams>, res: Response) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) {
      return res
        .status(404)
        .json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
    }

    let companion: CompanionBundle;
    try {
      companion = await getCompanion(fs.aidoPath, req.params.projectId);
    } catch (err) {
      return res.status(503).json({
        ok: false,
        error: {
          code: 'SERVICE_UNAVAILABLE',
          message: `Failed to initialize companion: ${err instanceof Error ? err.message : String(err)}`,
        },
      });
    }

    const sessions = await companion.sessionStore.listSessions(req.params.projectId);

    // Return summary fields only
    const data = sessions.map((s) => ({
      id: s.id,
      title: s.title,
      updatedAt: s.updatedAt,
      createdAt: s.createdAt,
      messageCount: s.messages.length,
      adapterUsed: s.adapterUsed,
    }));

    res.json({ ok: true, data });
  });

  // -------------------------------------------------------------------------
  // GET /sessions/:sessionId — full session detail
  // -------------------------------------------------------------------------
  router.get(
    '/sessions/:sessionId',
    async (req: Request<SessionParams>, res: Response) => {
      const fs = registry.getFsReader(req.params.projectId);
      if (!fs) {
        return res
          .status(404)
          .json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
      }

      let companion: CompanionBundle;
      try {
        companion = await getCompanion(fs.aidoPath, req.params.projectId);
      } catch (err) {
        return res.status(503).json({
          ok: false,
          error: {
            code: 'SERVICE_UNAVAILABLE',
            message: `Failed to initialize companion: ${err instanceof Error ? err.message : String(err)}`,
          },
        });
      }

      const session = await companion.sessionStore.getSession(req.params.sessionId);
      if (!session) {
        return res.status(404).json({
          ok: false,
          error: { code: 'NOT_FOUND', message: `Session ${req.params.sessionId} not found` },
        });
      }

      res.json({ ok: true, data: session });
    },
  );

  // -------------------------------------------------------------------------
  // DELETE /sessions/:sessionId — delete a session permanently
  // -------------------------------------------------------------------------
  router.delete(
    '/sessions/:sessionId',
    async (req: Request<SessionParams>, res: Response) => {
      const fs = registry.getFsReader(req.params.projectId);
      if (!fs) {
        return res
          .status(404)
          .json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
      }

      let companion: CompanionBundle;
      try {
        companion = await getCompanion(fs.aidoPath, req.params.projectId);
      } catch (err) {
        return res.status(503).json({
          ok: false,
          error: {
            code: 'SERVICE_UNAVAILABLE',
            message: `Failed to initialize companion: ${err instanceof Error ? err.message : String(err)}`,
          },
        });
      }

      const deleted = await companion.sessionStore.deleteSession(req.params.sessionId);
      if (!deleted) {
        return res.status(404).json({
          ok: false,
          error: { code: 'NOT_FOUND', message: `Session ${req.params.sessionId} not found` },
        });
      }

      res.json({ ok: true, data: { deleted: true } });
    },
  );

  // -------------------------------------------------------------------------
  // POST /sessions/:sessionId/archive — archive a session
  // -------------------------------------------------------------------------
  router.post(
    '/sessions/:sessionId/archive',
    async (req: Request<SessionParams>, res: Response) => {
      const fs = registry.getFsReader(req.params.projectId);
      if (!fs) {
        return res
          .status(404)
          .json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
      }

      let companion: CompanionBundle;
      try {
        companion = await getCompanion(fs.aidoPath, req.params.projectId);
      } catch (err) {
        return res.status(503).json({
          ok: false,
          error: {
            code: 'SERVICE_UNAVAILABLE',
            message: `Failed to initialize companion: ${err instanceof Error ? err.message : String(err)}`,
          },
        });
      }

      const archived = await companion.sessionStore.archiveSession(req.params.sessionId);
      if (!archived) {
        return res.status(404).json({
          ok: false,
          error: { code: 'NOT_FOUND', message: `Session ${req.params.sessionId} not found` },
        });
      }

      res.json({ ok: true, data: { archived: true } });
    },
  );

  // -------------------------------------------------------------------------
  // PATCH /sessions/:sessionId — rename a session
  // -------------------------------------------------------------------------
  router.patch(
    '/sessions/:sessionId',
    async (req: Request<SessionParams>, res: Response) => {
      const fs = registry.getFsReader(req.params.projectId);
      if (!fs) {
        return res
          .status(404)
          .json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
      }

      const { title } = req.body as { title?: string };
      if (!title || typeof title !== 'string' || title.trim().length === 0) {
        return res
          .status(400)
          .json({ ok: false, error: { code: 'BAD_REQUEST', message: 'title is required' } });
      }

      let companion: CompanionBundle;
      try {
        companion = await getCompanion(fs.aidoPath, req.params.projectId);
      } catch (err) {
        return res.status(503).json({
          ok: false,
          error: {
            code: 'SERVICE_UNAVAILABLE',
            message: `Failed to initialize companion: ${err instanceof Error ? err.message : String(err)}`,
          },
        });
      }

      const newTitle = await companion.sessionStore.renameSession(req.params.sessionId, title);
      if (newTitle === null) {
        return res.status(404).json({
          ok: false,
          error: { code: 'NOT_FOUND', message: `Session ${req.params.sessionId} not found` },
        });
      }

      res.json({ ok: true, data: { title: newTitle } });
    },
  );

  // -------------------------------------------------------------------------
  // GET /status — adapter availability
  // -------------------------------------------------------------------------
  router.get('/status', async (req: Request<ProjectParams>, res: Response) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) {
      return res
        .status(404)
        .json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
    }

    let companion: CompanionBundle;
    try {
      companion = await getCompanion(fs.aidoPath, req.params.projectId);
    } catch (err) {
      return res.status(503).json({
        ok: false,
        error: {
          code: 'SERVICE_UNAVAILABLE',
          message: `Failed to initialize companion: ${err instanceof Error ? err.message : String(err)}`,
        },
      });
    }

    const available = await companion.service.isAvailable();

    res.json({
      ok: true,
      data: {
        adapter: companion.service.name,
        available,
      },
    });
  });

  return router;
}
