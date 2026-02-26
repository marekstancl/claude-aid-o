import { Router } from 'express';
import type { ProjectRegistry } from '../services/project-registry.js';

export function projectRoutes(registry: ProjectRegistry): Router {
  const router = Router();

  router.get('/projects', (_req, res) => {
    const projects = registry.getAll();
    res.json({ ok: true, data: projects });
  });

  return router;
}
