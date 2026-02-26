import { Router, type Request } from 'express';
import { join } from 'node:path';
import { writeFile } from 'node:fs/promises';
import yaml from 'js-yaml';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams, EpicParams } from './types.js';

export function queueRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/queue
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const queue = await fs.readYaml<any>(join(fs.aidoPath, '04-engine', 'epic-queue.yaml'));

    const entries = (queue?.queue ?? []).map((e: any) => ({
      epicId: e.epic_id,
      path: e.path,
      priority: e.priority ?? 'medium',
      status: e.status ?? 'queued',
      addedAt: e.added_at ?? null,
      startedAt: e.started_at ?? null,
      completedAt: e.completed_at ?? null,
    }));

    res.json({
      ok: true,
      data: { paused: queue?.paused ?? false, entries },
    });
  });

  // GET /api/p/:projectId/queue/schedule
  router.get('/schedule', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const config = await fs.readYaml<any>(join(fs.aidoPath, '03-config', 'schedule.yaml'));

    res.json({
      ok: true,
      data: {
        enabled: config?.enabled ?? false,
        cooldownSeconds: config?.cooldown_seconds ?? 60,
        maxConcurrent: config?.max_concurrent ?? 1,
        delayedStartAt: config?.delayed_start_at ?? null,
        autoPauseAtCcLimit: config?.auto_pause_at_cc_limit ?? false,
        ccLimitThreshold: config?.cc_limit_threshold ?? 80000,
        lastRunCompletedAt: config?.last_run_completed_at ?? null,
      },
    });
  });

  // PUT /api/p/:projectId/queue/schedule
  router.put('/schedule', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const schedulePath = join(fs.aidoPath, '03-config', 'schedule.yaml');
    const existing = (await fs.readYaml<any>(schedulePath)) ?? {};
    const body = req.body;

    const updated = {
      ...existing,
      ...(body.enabled !== undefined && { enabled: body.enabled }),
      ...(body.cooldownSeconds !== undefined && { cooldown_seconds: body.cooldownSeconds }),
      ...(body.maxConcurrent !== undefined && { max_concurrent: body.maxConcurrent }),
      ...(body.delayedStartAt !== undefined && { delayed_start_at: body.delayedStartAt }),
      ...(body.autoPauseAtCcLimit !== undefined && { auto_pause_at_cc_limit: body.autoPauseAtCcLimit }),
      ...(body.ccLimitThreshold !== undefined && { cc_limit_threshold: body.ccLimitThreshold }),
    };

    await writeFile(schedulePath, yaml.dump(updated), 'utf-8');
    res.json({
      ok: true,
      data: {
        enabled: updated.enabled ?? false,
        cooldownSeconds: updated.cooldown_seconds ?? 60,
        maxConcurrent: updated.max_concurrent ?? 1,
        delayedStartAt: updated.delayed_start_at ?? null,
        autoPauseAtCcLimit: updated.auto_pause_at_cc_limit ?? false,
        ccLimitThreshold: updated.cc_limit_threshold ?? 80000,
        lastRunCompletedAt: updated.last_run_completed_at ?? null,
      },
    });
  });

  // GET /api/p/:projectId/queue/schedule/status
  router.get('/schedule/status', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const config = await fs.readYaml<any>(join(fs.aidoPath, '03-config', 'schedule.yaml'));

    res.json({
      ok: true,
      data: {
        state: config?.enabled ? 'idle' : 'paused',
        remainingSeconds: null,
        config: {
          enabled: config?.enabled ?? false,
          cooldownSeconds: config?.cooldown_seconds ?? 60,
          maxConcurrent: config?.max_concurrent ?? 1,
          delayedStartAt: config?.delayed_start_at ?? null,
          autoPauseAtCcLimit: config?.auto_pause_at_cc_limit ?? false,
          ccLimitThreshold: config?.cc_limit_threshold ?? 80000,
          lastRunCompletedAt: config?.last_run_completed_at ?? null,
        },
        timestamp: new Date().toISOString(),
      },
    });
  });

  // PUT /api/p/:projectId/queue/:epicId
  router.put('/:epicId', async (req: Request<EpicParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const queuePath = join(fs.aidoPath, '04-engine', 'epic-queue.yaml');
    const queue = await fs.readYaml<any>(queuePath);
    if (!queue?.queue) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Queue not found' } });

    const entry = queue.queue.find((e: any) => e.epic_id === req.params.epicId);
    if (!entry) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'EPIC not found in queue' } });

    if (req.body.status) entry.status = req.body.status;
    if (req.body.priority) entry.priority = req.body.priority;

    await writeFile(queuePath, yaml.dump(queue), 'utf-8');

    res.json({
      ok: true,
      data: {
        epicId: entry.epic_id,
        path: entry.path,
        priority: entry.priority,
        status: entry.status,
        addedAt: entry.added_at,
        startedAt: entry.started_at,
        completedAt: entry.completed_at,
      },
    });
  });

  // POST /api/p/:projectId/queue/launch
  router.post('/launch', async (_req: Request<ProjectParams>, res) => {
    res.json({
      ok: true,
      data: { launched: false, message: 'Queue launch via GUI not yet implemented. Use /aid-first-aid from CLI.' },
    });
  });

  return router;
}
