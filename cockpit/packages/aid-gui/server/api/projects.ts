/**
 * Multi-project support API router.
 *
 * Manages the project registry stored in ~/.aid-gui/projects.json.
 * This router is NOT behind projectResolver — it manages projects themselves.
 *
 * Routes:
 *   GET    /                    — List all registered projects
 *   GET    /active              — Get the currently active project
 *   POST   /                    — Register a new project
 *   PUT    /:projectId/activate — Set a project as active
 *   DELETE /:projectId          — Remove a project from registry
 *
 * Also exports autoRegisterProject() for use by the CLI entry point.
 */

import { Router, type Request, type Response } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import { sendOk, send400, send404, sendError } from './middleware.ts';
import type { Project, ProjectsStorage } from '../types.ts';

const router = Router();

// ---------------------------------------------------------------------------
// Storage helpers
// ---------------------------------------------------------------------------

/** Return the path to ~/.aid-gui/projects.json. */
function getStoragePath(): string {
  return path.join(os.homedir(), '.aid-gui', 'projects.json');
}

/** Return the default empty storage structure. */
function emptyStorage(): ProjectsStorage {
  return { version: 1, projects: [] };
}

/**
 * Read and parse the projects.json file.
 * Returns the default empty storage if the file does not exist.
 * Throws on other I/O or parse errors.
 */
async function readStorage(): Promise<ProjectsStorage> {
  const filePath = getStoragePath();
  let content: string;
  try {
    content = await fs.readFile(filePath, 'utf-8');
  } catch (err: unknown) {
    if (
      err instanceof Error &&
      'code' in err &&
      (err as NodeJS.ErrnoException).code === 'ENOENT'
    ) {
      return emptyStorage();
    }
    throw err;
  }

  const parsed = JSON.parse(content) as ProjectsStorage;
  if (!Array.isArray(parsed.projects)) {
    parsed.projects = [];
  }
  return parsed;
}

/**
 * Write the storage atomically: write to .tmp, then rename.
 * Creates the ~/.aid-gui/ directory if it does not exist.
 */
async function writeStorage(storage: ProjectsStorage): Promise<void> {
  const filePath = getStoragePath();
  const tmpPath = filePath + '.tmp';

  // Ensure parent directory exists.
  await fs.mkdir(path.dirname(filePath), { recursive: true });

  const content = JSON.stringify(storage, null, 2);
  await fs.writeFile(tmpPath, content, 'utf-8');
  await fs.rename(tmpPath, filePath);
}

/**
 * Check whether the .aid-o/ directory at the given path is accessible.
 * Returns true if the directory can be read, false otherwise.
 */
async function checkAccessible(aidoPath: string): Promise<boolean> {
  try {
    await fs.access(aidoPath);
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// GET / — List all registered projects
// ---------------------------------------------------------------------------

router.get('/', async (_req: Request, res: Response): Promise<void> => {
  try {
    const storage = await readStorage();

    // Update the accessible field for each project by checking fs.access.
    const updatedProjects = await Promise.all(
      storage.projects.map(async (project) => ({
        ...project,
        accessible: await checkAccessible(project.aidoPath),
      })),
    );

    sendOk(res, updatedProjects, { total: updatedProjects.length });
  } catch (err: unknown) {
    const message =
      err instanceof Error ? err.message : 'Unknown error reading projects';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// GET /active — Get the currently active project
// ---------------------------------------------------------------------------

router.get('/active', async (_req: Request, res: Response): Promise<void> => {
  try {
    const storage = await readStorage();
    const active = storage.projects.find((p) => p.active === true);

    if (!active) {
      send404(res, 'Active project');
      return;
    }

    // Refresh the accessible field before returning.
    active.accessible = await checkAccessible(active.aidoPath);

    sendOk(res, active);
  } catch (err: unknown) {
    const message =
      err instanceof Error ? err.message : 'Unknown error reading active project';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// POST / — Register a new project
// ---------------------------------------------------------------------------

router.post('/', async (req: Request, res: Response): Promise<void> => {
  try {
    const body = req.body as Partial<{ name: string; path: string }> | undefined;

    // Validate required fields.
    if (!body || typeof body.name !== 'string' || !body.name.trim()) {
      send400(res, 'name is required and must be a non-empty string');
      return;
    }
    if (typeof body.path !== 'string' || !body.path.trim()) {
      send400(res, 'path is required and must be a non-empty string');
      return;
    }

    const projectName = body.name.trim();
    const projectPath = path.resolve(body.path.trim());
    const aidoPath = path.join(projectPath, '.aid-o');

    const storage = await readStorage();

    // Check for duplicate paths.
    const duplicate = storage.projects.find((p) => p.path === projectPath);
    if (duplicate) {
      send400(res, `A project with path "${projectPath}" is already registered`);
      return;
    }

    // Auto-generate ID based on existing project count.
    const id = `proj-${storage.projects.length + 1}`;

    const accessible = await checkAccessible(aidoPath);

    const newProject: Project = {
      id,
      name: projectName,
      path: projectPath,
      active: storage.projects.length === 0,
      aidoPath,
      registeredAt: new Date().toISOString(),
      accessible,
    };

    storage.projects.push(newProject);
    await writeStorage(storage);

    res.status(201);
    sendOk(res, newProject);
  } catch (err: unknown) {
    const message =
      err instanceof Error ? err.message : 'Unknown error registering project';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// PUT /:projectId/activate — Set a project as active
// ---------------------------------------------------------------------------

router.put(
  '/:projectId/activate',
  async (req: Request, res: Response): Promise<void> => {
    try {
      const { projectId } = req.params;
      const storage = await readStorage();

      const target = storage.projects.find((p) => p.id === projectId);
      if (!target) {
        send404(res, `Project "${projectId}"`);
        return;
      }

      // Deactivate all other projects and activate the target.
      for (const project of storage.projects) {
        project.active = project.id === projectId;
      }

      target.lastActivityAt = new Date().toISOString();

      await writeStorage(storage);

      // Refresh accessibility before returning.
      target.accessible = await checkAccessible(target.aidoPath);

      sendOk(res, target);
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : 'Unknown error activating project';
      sendError(res, 500, 'INTERNAL_ERROR', message);
    }
  },
);

// ---------------------------------------------------------------------------
// DELETE /:projectId — Remove a project from registry
// ---------------------------------------------------------------------------

router.delete(
  '/:projectId',
  async (req: Request, res: Response): Promise<void> => {
    try {
      const { projectId } = req.params;
      const storage = await readStorage();

      const index = storage.projects.findIndex((p) => p.id === projectId);
      if (index === -1) {
        send404(res, `Project "${projectId}"`);
        return;
      }

      const project = storage.projects[index];

      // Cannot delete the active project.
      if (project.active) {
        send400(
          res,
          'Cannot delete the active project. Activate a different project first.',
        );
        return;
      }

      storage.projects.splice(index, 1);
      await writeStorage(storage);

      sendOk(res, { deleted: true });
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : 'Unknown error deleting project';
      sendError(res, 500, 'INTERNAL_ERROR', message);
    }
  },
);

// ---------------------------------------------------------------------------
// Auto-register helper (exported for CLI entry point)
// ---------------------------------------------------------------------------

/**
 * Auto-register a project on startup. Called by the CLI entry point.
 * If the project path is already registered, updates lastActivityAt and
 * marks it as active. If not registered, adds it as the active project.
 *
 * @param projectPath - Absolute path to the project root.
 * @param name - Optional human-readable name. Defaults to the directory basename.
 * @returns The registered or updated Project record.
 */
export async function autoRegisterProject(
  projectPath: string,
  name?: string,
): Promise<Project> {
  const resolvedPath = path.resolve(projectPath);
  const aidoPath = path.join(resolvedPath, '.aid-o');
  const projectName = name ?? path.basename(resolvedPath);

  const storage = await readStorage();

  // Check if this project path is already registered.
  const existing = storage.projects.find((p) => p.path === resolvedPath);

  if (existing) {
    // Update activity timestamp and mark as active.
    existing.lastActivityAt = new Date().toISOString();
    existing.accessible = await checkAccessible(aidoPath);

    // Deactivate all, then activate this one.
    for (const project of storage.projects) {
      project.active = project.id === existing.id;
    }

    await writeStorage(storage);
    return existing;
  }

  // New project registration.
  const id = `proj-${storage.projects.length + 1}`;
  const accessible = await checkAccessible(aidoPath);

  const newProject: Project = {
    id,
    name: projectName,
    path: resolvedPath,
    active: true,
    aidoPath,
    registeredAt: new Date().toISOString(),
    lastActivityAt: new Date().toISOString(),
    accessible,
  };

  // Deactivate all existing projects before adding the new active one.
  for (const project of storage.projects) {
    project.active = false;
  }

  storage.projects.push(newProject);
  await writeStorage(storage);

  return newProject;
}

export default router;
