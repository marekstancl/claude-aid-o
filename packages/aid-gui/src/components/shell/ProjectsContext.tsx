import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Project } from '@aid/contract';
import { getProjects } from '../../lib/api';

export interface ProjectSummary extends Project {
  // ProjectSummary shape matches the Project contract from api.getProjects()
}

interface ProjectsContextValue {
  projects: ProjectSummary[];
  loading: boolean;
  /** True once a fetch has completed (success or failure), so callers can
   *  distinguish "still loading" from "loaded, project genuinely missing". */
  loaded: boolean;
}

const ProjectsContext = createContext<ProjectsContextValue>({
  projects: [],
  loading: true,
  loaded: false,
});

/**
 * Fetches the project list via getProjects() and exposes it to the shell.
 * The breadcrumb and the B/Plan/C detail screens use it to render a
 * "Projekt nenalezen" empty state for an unknown :project param instead of
 * crashing. Uses the api.ts envelope unwrapping and error handling.
 */
export function ProjectsProvider({ children }: { children: ReactNode }) {
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let cancelled = false;
    getProjects()
      .then((list) => {
        if (cancelled) return;
        setProjects(list as ProjectSummary[]);
      })
      .catch(() => {
        /* offline / server down — ApiError is caught, treat as empty state */
      })
      .finally(() => {
        if (cancelled) return;
        setLoading(false);
        setLoaded(true);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <ProjectsContext.Provider value={{ projects, loading, loaded }}>
      {children}
    </ProjectsContext.Provider>
  );
}

export function useProjects(): ProjectsContextValue {
  return useContext(ProjectsContext);
}
