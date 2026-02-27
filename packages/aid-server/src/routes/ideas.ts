import { Router, type Request } from 'express';
import { join } from 'node:path';
import { writeFile, mkdir } from 'node:fs/promises';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams, IdeaParams, IdeaLinkBody } from './types.js';
import type { FsReader } from '../services/fs-reader.js';

function ideasPath(aidoPath: string): string {
  return join(aidoPath, '04-engine', 'ideas.json');
}

async function readIdeas(fs: FsReader): Promise<any[]> {
  return (await fs.readJson(ideasPath(fs.aidoPath))) ?? [];
}

async function saveIdeas(ideas: any[], aidoPath: string): Promise<void> {
  await mkdir(join(aidoPath, '04-engine'), { recursive: true });
  await writeFile(ideasPath(aidoPath), JSON.stringify(ideas, null, 2), 'utf-8');
}

export function ideaRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/ideas
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
    const ideas = await readIdeas(fs);
    res.json({ ok: true, data: ideas });
  });

  // POST /api/p/:projectId/ideas
  router.post('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const { title, description, tags, priority, linkedPlan, linkedEpic } = req.body;
    if (!title) return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'title is required' } });

    const ideas = await readIdeas(fs);
    const idea = {
      id: `idea-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      title,
      description: description ?? '',
      tags: tags ?? [],
      priority: priority ?? 'medium',
      status: 'idea',
      linkedPlan: linkedPlan ?? null,
      linkedEpic: linkedEpic ?? null,
      autoStatus: linkedEpic ? 'epic' : linkedPlan ? 'plan' : null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    ideas.push(idea);
    try {
      await saveIdeas(ideas, fs.aidoPath);
    } catch {
      return res.status(500).json({ ok: false, error: { code: 'WRITE_ERROR', message: 'Failed to save ideas' } });
    }
    res.json({ ok: true, data: idea });
  });

  // PUT /api/p/:projectId/ideas/:ideaId
  router.put('/:ideaId', async (req: Request<IdeaParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const ideas = await readIdeas(fs);
    const idx = ideas.findIndex((i: any) => i.id === req.params.ideaId);
    if (idx === -1) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Idea not found' } });

    const { title, description, tags, priority, status, linkedPlan, linkedEpic } = req.body;
    const updated = {
      ...ideas[idx],
      ...(title !== undefined && { title }),
      ...(description !== undefined && { description }),
      ...(tags !== undefined && { tags }),
      ...(priority !== undefined && { priority }),
      ...(status !== undefined && { status }),
      updatedAt: new Date().toISOString(),
    };
    ideas[idx] = updated;
    try {
      await saveIdeas(ideas, fs.aidoPath);
    } catch {
      return res.status(500).json({ ok: false, error: { code: 'WRITE_ERROR', message: 'Failed to save ideas' } });
    }
    res.json({ ok: true, data: updated });
  });

  // PUT /api/p/:projectId/ideas/:ideaId/link
  router.put('/:ideaId/link', async (req: Request<IdeaParams, any, IdeaLinkBody>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const ideas = await readIdeas(fs);
    const idx = ideas.findIndex((i: any) => i.id === req.params.ideaId);
    if (idx === -1) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Idea not found' } });

    const { linkedPlan, linkedEpic } = req.body;
    const idea = ideas[idx];

    if (linkedPlan !== undefined) idea.linkedPlan = linkedPlan || null;
    if (linkedEpic !== undefined) idea.linkedEpic = linkedEpic || null;

    // Derive autoStatus from current link state
    if (idea.linkedEpic) {
      idea.autoStatus = 'epic';
    } else if (idea.linkedPlan) {
      idea.autoStatus = 'plan';
    } else {
      idea.autoStatus = null;
    }

    idea.updatedAt = new Date().toISOString();
    ideas[idx] = idea;
    try {
      await saveIdeas(ideas, fs.aidoPath);
    } catch {
      return res.status(500).json({ ok: false, error: { code: 'WRITE_ERROR', message: 'Failed to save ideas' } });
    }
    res.json({ ok: true, data: idea });
  });

  // DELETE /api/p/:projectId/ideas/:ideaId
  router.delete('/:ideaId', async (req: Request<IdeaParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const ideas = await readIdeas(fs);
    const filtered = ideas.filter((i: any) => i.id !== req.params.ideaId);
    if (filtered.length === ideas.length) {
      return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Idea not found' } });
    }
    try {
      await saveIdeas(filtered, fs.aidoPath);
    } catch {
      return res.status(500).json({ ok: false, error: { code: 'WRITE_ERROR', message: 'Failed to save ideas' } });
    }
    res.json({ ok: true, data: { deleted: true } });
  });

  return router;
}
