import { Router, type Request } from 'express';
import { join } from 'node:path';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';

export function knowledgeRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/knowledge
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const items: any[] = [];
    const project = registry.get(req.params.projectId);
    if (!project) return res.json({ ok: true, data: [] });

    // Scan agent playbooks
    const agentsDir = join(project.path, 'plugins', 'aid-orchestrator', 'agents');
    const agentFiles = await fs.listDir(agentsDir);
    for (const file of agentFiles.filter((f) => f.endsWith('.md'))) {
      const name = file.replace('.md', '');
      items.push({ type: 'agent', name, description: `Agent playbook: ${name}`, filename: file });
    }

    // Scan skills
    const skillsDir = join(project.path, 'plugins', 'aid-orchestrator', 'skills');
    const skillFiles = await fs.listDir(skillsDir);
    for (const file of skillFiles.filter((f) => f.endsWith('.md'))) {
      const name = file.replace('.md', '');
      items.push({ type: 'skill', name, description: `Skill: ${name}`, filename: file });
    }

    // Scan commands
    const commandsDir = join(project.path, 'plugins', 'aid-orchestrator', 'commands');
    const commandFiles = await fs.listDir(commandsDir);
    for (const file of commandFiles.filter((f) => f.endsWith('.md'))) {
      const name = file.replace('.md', '');
      items.push({ type: 'command', name, description: `Command: ${name}`, filename: file });
    }

    res.json({ ok: true, data: items });
  });

  return router;
}
