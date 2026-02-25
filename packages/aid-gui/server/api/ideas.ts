/**
 * Ideas CRUD routes.
 *
 * GET    /           - List all ideas for the current project (with optional filtering)
 * GET    /:ideaId    - Get a single idea by ID
 * POST   /           - Create a new idea
 * PUT    /:ideaId    - Update an existing idea
 * DELETE /:ideaId    - Delete an idea
 *
 * Ideas are stored per-project in ~/.aid-gui/ideas.json, keyed by the
 * resolved .aid-o/ path (req.aidoPath). The file is auto-created on first
 * write if it does not exist.
 */

import { Router, type Request, type Response } from 'express';
import * as fs from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import { sendOk, send404, send400, sendError } from './middleware.ts';
import type {
  IdeasStorage,
  ProjectIdeas,
  StoredIdea,
  IdeaCreateRequest,
  IdeaUpdateRequest,
} from '../types.ts';

const router = Router();

// ---------------------------------------------------------------------------
// Storage helpers
// ---------------------------------------------------------------------------

function getStoragePath(): string {
  return path.join(os.homedir(), '.aid-gui', 'ideas.json');
}

/**
 * Read the ideas storage file. Returns the default empty structure if the
 * file does not exist or contains invalid JSON.
 */
async function readIdeasStorage(): Promise<IdeasStorage> {
  const filePath = getStoragePath();
  try {
    const content = await fs.readFile(filePath, 'utf-8');
    const parsed = JSON.parse(content) as IdeasStorage;
    // Basic shape validation
    if (
      typeof parsed === 'object' &&
      parsed !== null &&
      typeof parsed.version === 'number' &&
      typeof parsed.projects === 'object' &&
      parsed.projects !== null
    ) {
      return parsed;
    }
    return { version: 1, projects: {} };
  } catch {
    return { version: 1, projects: {} };
  }
}

/**
 * Atomically write the ideas storage file. Writes to a temporary file first,
 * then renames it into place (atomic on POSIX). Ensures the ~/.aid-gui/
 * directory exists.
 */
async function writeIdeasStorage(storage: IdeasStorage): Promise<void> {
  const filePath = getStoragePath();
  const dir = path.dirname(filePath);

  await fs.mkdir(dir, { recursive: true });

  const tmpPath = `${filePath}.tmp`;
  const jsonContent = JSON.stringify(storage, null, 2);
  try {
    await fs.writeFile(tmpPath, jsonContent, 'utf-8');
    await fs.rename(tmpPath, filePath);
  } catch (err: unknown) {
    // Clean up temp file on failure, then re-throw.
    await fs.unlink(tmpPath).catch(() => {});
    throw err;
  }
}

/**
 * Get the ProjectIdeas entry for a given project key, or a default empty one.
 */
function getProjectIdeas(storage: IdeasStorage, projectKey: string): ProjectIdeas {
  return storage.projects[projectKey] ?? { counter: 0, ideas: [] };
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

const VALID_PRIORITIES = new Set(['low', 'medium', 'high']);
const VALID_STATUSES = new Set(['idea', 'exploring', 'planned', 'done']);

function isValidPriority(value: unknown): value is StoredIdea['priority'] {
  return typeof value === 'string' && VALID_PRIORITIES.has(value);
}

function isValidStatus(value: unknown): value is StoredIdea['status'] {
  return typeof value === 'string' && VALID_STATUSES.has(value);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
}

// ---------------------------------------------------------------------------
// GET / — List all ideas for the current project
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response): Promise<void> => {
  try {
    const projectKey = req.aidoPath;
    const storage = await readIdeasStorage();
    const project = getProjectIdeas(storage, projectKey);

    let ideas = project.ideas;

    // Apply optional query filters.
    const { status, priority, tag } = req.query;

    if (typeof status === 'string' && status.length > 0) {
      ideas = ideas.filter((idea) => idea.status === status);
    }

    if (typeof priority === 'string' && priority.length > 0) {
      ideas = ideas.filter((idea) => idea.priority === priority);
    }

    if (typeof tag === 'string' && tag.length > 0) {
      ideas = ideas.filter((idea) => idea.tags.includes(tag));
    }

    sendOk(res, ideas, { total: ideas.length });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error reading ideas';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// GET /:ideaId — Get a single idea
// ---------------------------------------------------------------------------

router.get('/:ideaId', async (req: Request, res: Response): Promise<void> => {
  try {
    const projectKey = req.aidoPath;
    const { ideaId } = req.params;

    const storage = await readIdeasStorage();
    const project = getProjectIdeas(storage, projectKey);
    const idea = project.ideas.find((i) => i.id === ideaId);

    if (!idea) {
      send404(res, `Idea "${ideaId}"`);
      return;
    }

    sendOk(res, idea);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error reading idea';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// POST / — Create a new idea
// ---------------------------------------------------------------------------

router.post('/', async (req: Request, res: Response): Promise<void> => {
  try {
    const body = req.body as Partial<IdeaCreateRequest> | undefined;

    // Validate required field: title must be a non-empty string.
    if (!body || typeof body.title !== 'string' || !body.title.trim()) {
      send400(res, 'title is required and must be a non-empty string');
      return;
    }

    // Validate optional fields when present.
    if (body.description !== undefined && typeof body.description !== 'string') {
      send400(res, 'description must be a string');
      return;
    }

    if (body.tags !== undefined && !isStringArray(body.tags)) {
      send400(res, 'tags must be an array of strings');
      return;
    }

    if (body.priority !== undefined && !isValidPriority(body.priority)) {
      send400(res, 'priority must be one of: low, medium, high');
      return;
    }

    if (body.linkedPlan !== undefined && body.linkedPlan !== null && typeof body.linkedPlan !== 'string') {
      send400(res, 'linkedPlan must be a string or null');
      return;
    }

    if (body.linkedEpic !== undefined && body.linkedEpic !== null && typeof body.linkedEpic !== 'string') {
      send400(res, 'linkedEpic must be a string or null');
      return;
    }

    const projectKey = req.aidoPath;
    const storage = await readIdeasStorage();
    const project = getProjectIdeas(storage, projectKey);

    // Increment the per-project counter and generate the ID.
    project.counter += 1;
    const now = new Date().toISOString();

    const newIdea: StoredIdea = {
      id: `idea-${project.counter}`,
      title: body.title.trim(),
      description: body.description ?? '',
      tags: body.tags ?? [],
      priority: body.priority ?? 'medium',
      status: 'idea',
      linkedPlan: body.linkedPlan ?? null,
      linkedEpic: body.linkedEpic ?? null,
      createdAt: now,
      updatedAt: now,
    };

    project.ideas.push(newIdea);
    storage.projects[projectKey] = project;

    await writeIdeasStorage(storage);

    res.status(201);
    sendOk(res, newIdea);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error creating idea';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// PUT /:ideaId — Update an existing idea
// ---------------------------------------------------------------------------

router.put('/:ideaId', async (req: Request, res: Response): Promise<void> => {
  try {
    const body = req.body as Partial<IdeaUpdateRequest> | undefined;
    const projectKey = req.aidoPath;
    const { ideaId } = req.params;

    const storage = await readIdeasStorage();
    const project = getProjectIdeas(storage, projectKey);
    const ideaIndex = project.ideas.findIndex((i) => i.id === ideaId);

    if (ideaIndex === -1) {
      send404(res, `Idea "${ideaId}"`);
      return;
    }

    // Validate optional fields when present.
    if (body?.title !== undefined) {
      if (typeof body.title !== 'string' || !body.title.trim()) {
        send400(res, 'title must be a non-empty string');
        return;
      }
    }

    if (body?.description !== undefined && typeof body.description !== 'string') {
      send400(res, 'description must be a string');
      return;
    }

    if (body?.tags !== undefined && !isStringArray(body.tags)) {
      send400(res, 'tags must be an array of strings');
      return;
    }

    if (body?.priority !== undefined && !isValidPriority(body.priority)) {
      send400(res, 'priority must be one of: low, medium, high');
      return;
    }

    if (body?.status !== undefined && !isValidStatus(body.status)) {
      send400(res, 'status must be one of: idea, exploring, planned, done');
      return;
    }

    if (body?.linkedPlan !== undefined && body.linkedPlan !== null && typeof body.linkedPlan !== 'string') {
      send400(res, 'linkedPlan must be a string or null');
      return;
    }

    if (body?.linkedEpic !== undefined && body.linkedEpic !== null && typeof body.linkedEpic !== 'string') {
      send400(res, 'linkedEpic must be a string or null');
      return;
    }

    const idea = project.ideas[ideaIndex];

    // Apply updates. Only override fields that are explicitly provided.
    if (body?.title !== undefined) idea.title = body.title.trim();
    if (body?.description !== undefined) idea.description = body.description;
    if (body?.tags !== undefined) idea.tags = body.tags;
    if (body?.priority !== undefined) idea.priority = body.priority;
    if (body?.status !== undefined) idea.status = body.status;
    if (body?.linkedPlan !== undefined) idea.linkedPlan = body.linkedPlan;
    if (body?.linkedEpic !== undefined) idea.linkedEpic = body.linkedEpic;

    idea.updatedAt = new Date().toISOString();

    storage.projects[projectKey] = project;
    await writeIdeasStorage(storage);

    sendOk(res, idea);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error updating idea';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// DELETE /:ideaId — Delete an idea
// ---------------------------------------------------------------------------

router.delete('/:ideaId', async (req: Request, res: Response): Promise<void> => {
  try {
    const projectKey = req.aidoPath;
    const { ideaId } = req.params;

    const storage = await readIdeasStorage();
    const project = getProjectIdeas(storage, projectKey);
    const ideaIndex = project.ideas.findIndex((i) => i.id === ideaId);

    if (ideaIndex === -1) {
      send404(res, `Idea "${ideaId}"`);
      return;
    }

    project.ideas.splice(ideaIndex, 1);
    storage.projects[projectKey] = project;
    await writeIdeasStorage(storage);

    sendOk(res, { deleted: true });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error deleting idea';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

export default router;
