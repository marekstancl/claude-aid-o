/**
 * Project registry — discovers and manages project registrations.
 * Reads from a simple projects.yaml in the server data dir or env.
 */

import { join } from 'node:path';
import { FsReader } from './fs-reader.js';

export interface Project {
  id: string;
  name: string;
  path: string;
  active: boolean;
  aidoPath: string;
  registeredAt: string;
  lastActivityAt: string | null;
  accessible: boolean;
}

export class ProjectRegistry {
  private projects: Map<string, Project> = new Map();

  constructor(private readonly defaultProjectRoot: string) {}

  async init(): Promise<void> {
    // Auto-register the default project from AID_PROJECT_ROOT
    const fs = new FsReader(this.defaultProjectRoot);
    const aidoExists = await fs.exists(fs.aidoPath);

    const project: Project = {
      id: 'default',
      name: this.defaultProjectRoot.split('/').pop() ?? 'project',
      path: this.defaultProjectRoot,
      active: aidoExists,
      aidoPath: join(this.defaultProjectRoot, '.aid-o'),
      registeredAt: new Date().toISOString(),
      lastActivityAt: null,
      accessible: aidoExists,
    };

    this.projects.set(project.id, project);

    // Also try to read a registry file if it exists
    const registryPath = join(this.defaultProjectRoot, '.aid-o', 'config', 'projects.yaml');
    const registry = await fs.readYaml<{ projects?: Array<{ id: string; name: string; path: string }> }>(registryPath);
    if (registry?.projects) {
      for (const p of registry.projects) {
        if (this.projects.has(p.id)) continue;
        const pFs = new FsReader(p.path);
        const pExists = await pFs.exists(pFs.aidoPath);
        this.projects.set(p.id, {
          id: p.id,
          name: p.name,
          path: p.path,
          active: pExists,
          aidoPath: join(p.path, '.aid-o'),
          registeredAt: new Date().toISOString(),
          lastActivityAt: null,
          accessible: pExists,
        });
      }
    }
  }

  getAll(): Project[] {
    return Array.from(this.projects.values());
  }

  get(id: string): Project | undefined {
    return this.projects.get(id);
  }

  getFsReader(projectId: string): FsReader | null {
    const project = this.projects.get(projectId);
    if (!project) return null;
    return new FsReader(project.path);
  }
}
