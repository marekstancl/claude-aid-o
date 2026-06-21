import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';

export interface ProjectSummary {
  id: string;
  name?: string;
  [key: string]: unknown;
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
 * Fetches the project list from /api/projects once and exposes it to the shell.
 * The breadcrumb and the B/Plan/C detail screens use it to render a
 * "Projekt nenalezen" empty state for an unknown :project param instead of
 * crashing. The API returns a { ok, data } envelope (legacy: bare array).
 */
export function ProjectsProvider({ children }: { children: ReactNode }) {
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetch('/api/projects')
      .then((res) => res.json())
      .then((result) => {
        if (cancelled) return;
        const list = result && result.ok ? result.data : result;
        if (Array.isArray(list)) setProjects(list as ProjectSummary[]);
      })
      .catch(() => {
        /* offline / server down — treat as empty, screens show empty state */
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
