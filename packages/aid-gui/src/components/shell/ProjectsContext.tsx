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
  /** True when the project-list fetch FAILED (offline / server down). Callers
   *  MUST check this BEFORE concluding a project is missing — an API outage is
   *  NOT the same as "Projekt nenalezen" (it would mislabel every deep-link). */
  error: boolean;
}

const ProjectsContext = createContext<ProjectsContextValue>({
  projects: [],
  loading: true,
  loaded: false,
  error: false,
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
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    getProjects()
      .then((list) => {
        if (cancelled) return;
        setProjects(list as ProjectSummary[]);
        setError(false);
      })
      .catch(() => {
        // offline / server down — record it as an ERROR, NOT an empty success.
        // A consumer must show "nepodařilo se načíst projekty", never conclude a
        // deep-linked project is "nenalezen" just because the list fetch failed.
        if (cancelled) return;
        setError(true);
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
    <ProjectsContext.Provider value={{ projects, loading, loaded, error }}>
      {children}
    </ProjectsContext.Provider>
  );
}

export function useProjects(): ProjectsContextValue {
  return useContext(ProjectsContext);
}
