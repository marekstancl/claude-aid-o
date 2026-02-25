/**
 * Queue API router — CRUD operations on the EPIC execution queue.
 *
 * Reads and writes `.aid-o/04-engine/epic-queue.yaml`.
 * All mutations use atomic write (write to .tmp, then rename) to avoid
 * partial writes on crash.
 *
 * Routes:
 *   GET    /  — Read current queue state
 *   POST   /  — Add an entry to the queue
 *   PUT    /:epicId — Update an existing queue entry
 *   DELETE /:epicId — Remove a queued entry
 */

import { Router, type Request, type Response } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import yaml from 'js-yaml';
import { sendOk, send400, send404, sendError } from './middleware.ts';
import { parseYaml } from '../parsers/index.ts';
import type { EpicQueue, QueueSchedule } from '../types.ts';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Canonical path to the epic-queue.yaml file. */
function queueFilePath(aidoPath: string): string {
  return path.join(aidoPath, '04-engine', 'epic-queue.yaml');
}

/** Valid priority values for queue entries. */
const VALID_PRIORITIES = new Set(['low', 'medium', 'high', 'critical']);

/** Valid status values for queue entries. */
const VALID_STATUSES = new Set(['queued', 'running', 'completed', 'failed', 'paused']);

/**
 * Read and parse the epic-queue.yaml file.
 * Returns null if the file does not exist. Throws on other I/O errors.
 */
async function readQueue(aidoPath: string): Promise<EpicQueue | null> {
  const filePath = queueFilePath(aidoPath);
  let content: string;
  try {
    content = await fs.readFile(filePath, 'utf-8');
  } catch (err: unknown) {
    if (err instanceof Error && 'code' in err && (err as NodeJS.ErrnoException).code === 'ENOENT') {
      return null;
    }
    throw err;
  }

  const result = parseYaml<EpicQueue>(content, filePath);
  if (!result.data) {
    return null;
  }
  // Ensure the queue array exists even if the YAML had none.
  if (!Array.isArray(result.data.queue)) {
    result.data.queue = [];
  }
  return result.data;
}

/**
 * Convert a camelCase QueueSchedule back to snake_case for YAML serialization.
 */
function toSnakeCase(entry: QueueSchedule): Record<string, unknown> {
  return {
    epic_id: entry.epicId,
    path: entry.path,
    priority: entry.priority,
    status: entry.status,
    added_at: entry.addedAt,
    started_at: entry.startedAt,
    completed_at: entry.completedAt,
  };
}

/**
 * Serialize the full EpicQueue back to snake_case YAML and write atomically.
 */
async function writeQueue(aidoPath: string, queue: EpicQueue): Promise<void> {
  const filePath = queueFilePath(aidoPath);
  const tmpPath = filePath + '.tmp';

  const snakeData = {
    paused: queue.paused,
    queue: queue.queue.map(toSnakeCase),
  };

  const content = yaml.dump(snakeData, {
    lineWidth: 120,
    noRefs: true,
    sortKeys: false,
  });

  // Ensure directory exists.
  await fs.mkdir(path.dirname(filePath), { recursive: true });

  // Atomic write: write to .tmp then rename.
  await fs.writeFile(tmpPath, content, 'utf-8');
  await fs.rename(tmpPath, filePath);
}

// ---------------------------------------------------------------------------
// GET / — Read current queue state
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response) => {
  try {
    const queue = await readQueue(req.aidoPath);
    if (!queue) {
      send404(res, 'Epic queue file');
      return;
    }
    sendOk(res, queue);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to read queue';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// POST / — Add entry to the queue
// ---------------------------------------------------------------------------

router.post('/', async (req: Request, res: Response) => {
  try {
    const { epicId, path: epicPath, priority } = req.body ?? {};

    // Validate required fields.
    if (!epicId || typeof epicId !== 'string') {
      send400(res, 'epicId is required and must be a string');
      return;
    }
    if (!epicPath || typeof epicPath !== 'string') {
      send400(res, 'path is required and must be a string');
      return;
    }

    // Validate priority if provided.
    const resolvedPriority = priority ?? 'medium';
    if (!VALID_PRIORITIES.has(resolvedPriority)) {
      send400(res, `Invalid priority "${resolvedPriority}". Must be one of: ${[...VALID_PRIORITIES].join(', ')}`);
      return;
    }

    // Read current queue or create a new one.
    let queue = await readQueue(req.aidoPath);
    if (!queue) {
      queue = { paused: false, queue: [] };
    }

    // Check for duplicate epicId.
    const existing = queue.queue.find((e) => e.epicId === epicId);
    if (existing) {
      send400(res, `Entry for epic "${epicId}" already exists in the queue`);
      return;
    }

    const newEntry: QueueSchedule = {
      epicId,
      path: epicPath,
      priority: resolvedPriority as QueueSchedule['priority'],
      status: 'queued',
      addedAt: new Date().toISOString(),
      startedAt: null,
      completedAt: null,
    };

    queue.queue.push(newEntry);
    await writeQueue(req.aidoPath, queue);

    res.status(201);
    sendOk(res, newEntry);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to add queue entry';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// PUT /:epicId — Update an existing queue entry
// ---------------------------------------------------------------------------

router.put('/:epicId', async (req: Request, res: Response) => {
  try {
    const { epicId } = req.params;
    const { priority, status } = req.body ?? {};

    // Validate that at least one field is provided.
    if (priority === undefined && status === undefined) {
      send400(res, 'At least one of priority or status must be provided');
      return;
    }

    // Validate priority if provided.
    if (priority !== undefined && !VALID_PRIORITIES.has(priority)) {
      send400(res, `Invalid priority "${priority}". Must be one of: ${[...VALID_PRIORITIES].join(', ')}`);
      return;
    }

    // Validate status if provided.
    if (status !== undefined && !VALID_STATUSES.has(status)) {
      send400(res, `Invalid status "${status}". Must be one of: ${[...VALID_STATUSES].join(', ')}`);
      return;
    }

    const queue = await readQueue(req.aidoPath);
    if (!queue) {
      send404(res, 'Epic queue file');
      return;
    }

    const entry = queue.queue.find((e) => e.epicId === epicId);
    if (!entry) {
      send404(res, `Queue entry for epic "${epicId}"`);
      return;
    }

    if (priority !== undefined) {
      entry.priority = priority as QueueSchedule['priority'];
    }
    if (status !== undefined) {
      entry.status = status as QueueSchedule['status'];
    }

    await writeQueue(req.aidoPath, queue);
    sendOk(res, entry);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to update queue entry';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// DELETE /:epicId — Remove a queued entry
// ---------------------------------------------------------------------------

router.delete('/:epicId', async (req: Request, res: Response) => {
  try {
    const { epicId } = req.params;

    const queue = await readQueue(req.aidoPath);
    if (!queue) {
      send404(res, 'Epic queue file');
      return;
    }

    const index = queue.queue.findIndex((e) => e.epicId === epicId);
    if (index === -1) {
      send404(res, `Queue entry for epic "${epicId}"`);
      return;
    }

    const entry = queue.queue[index];

    // Only allow removing entries with status "queued".
    if (entry.status !== 'queued') {
      send400(res, `Cannot remove entry with status "${entry.status}". Only entries with status "queued" can be removed`);
      return;
    }

    queue.queue.splice(index, 1);
    await writeQueue(req.aidoPath, queue);
    sendOk(res, entry);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to remove queue entry';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

export default router;
