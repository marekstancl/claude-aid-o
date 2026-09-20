import type { Explanation, Project, RunDetail } from '@aid/contract';
import { cn } from '../lib/utils';
import { ProjectTile } from './ProjectTile';

interface ProjectTileGridProps {
  projects: Project[];
  /**
   * Optional per-project active-run detail (keyed by project id) so tiles can
   * render the full §8.2 anatomy. Missing entries fall back to the header-only
   * active tile (never a crash).
   */
  activeRunDetails?: Record<string, RunDetail | null | undefined>;
  /** Optional per-project resolved FSM explanation (keyed by project id). */
  fsmExplanations?: Record<string, Explanation | null | undefined>;
  className?: string;
  /** Honest empty-state line when there are no projects. */
  emptyLabel?: string;
}

/**
 * Responsive grid of {@link ProjectTile}s. Owned by the component layer so both
 * Screen A and Screen G import it from one place. 1 / 2 / 3 columns at the
 * sm / md / lg breakpoints, 16px gap (§8.2).
 */
export function ProjectTileGrid({
  projects,
  activeRunDetails,
  fsmExplanations,
  className,
  emptyLabel = 'žádné projekty',
}: ProjectTileGridProps) {
  if (projects.length === 0) {
    return (
      <p data-project-grid data-empty className={cn('text-sm text-slate-400', className)}>
        {emptyLabel}
      </p>
    );
  }

  return (
    <div
      data-project-grid
      className={cn('grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3', className)}
    >
      {projects.map((project) => (
        <ProjectTile
          key={project.id}
          project={project}
          activeRunDetail={activeRunDetails?.[project.id]}
          fsmExplanation={fsmExplanations?.[project.id]}
        />
      ))}
    </div>
  );
}
