import { Fragment } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import { ChevronRight } from 'lucide-react';

interface Crumb {
  label: string;
  to?: string;
}

/**
 * Renders the drill-spine path (e.g. "Přehled › vulcan › Plán P003") derived
 * purely from the active route's params + pathname. Works on a deep-link with
 * no nav stack. Top-level sibling screens (G/D/E/F) get a single crumb.
 */
export function Breadcrumb() {
  const { pathname } = useLocation();
  const { project, planId, epic } = useParams();

  const crumbs = buildCrumbs(pathname, { project, planId, epic });
  if (crumbs.length === 0) return null;

  return (
    <nav aria-label="Drobečková navigace" className="flex h-10 items-center px-4 text-sm">
      <ol className="flex items-center gap-1 text-slate-500">
        {crumbs.map((c, i) => {
          const isLast = i === crumbs.length - 1;
          return (
            <Fragment key={`${c.label}-${i}`}>
              {i > 0 && <ChevronRight className="h-4 w-4 text-slate-300" aria-hidden="true" />}
              {c.to && !isLast ? (
                <li>
                  <Link to={c.to} className="hover:text-slate-900">
                    {c.label}
                  </Link>
                </li>
              ) : (
                <li className={isLast ? 'font-medium text-slate-900' : undefined} aria-current={isLast ? 'page' : undefined}>
                  {c.label}
                </li>
              )}
            </Fragment>
          );
        })}
      </ol>
    </nav>
  );
}

function buildCrumbs(
  pathname: string,
  params: { project?: string; planId?: string; epic?: string },
): Crumb[] {
  const { project, planId, epic } = params;

  // Sibling top-level screens — single crumb, no drill spine.
  if (pathname === '/') return [{ label: 'Co potřebuju vědět' }];
  if (pathname === '/prehled') return [{ label: 'Přehled' }];
  if (pathname === '/activity') return [{ label: 'Dění' }];
  if (pathname === '/compliance') return [{ label: 'Compliance' }];
  if (pathname === '/help') return [{ label: 'Nápověda' }];

  // Drill spine: Přehled › <project> › (Plán <planId> | EPIC <epic>)
  if (project) {
    const crumbs: Crumb[] = [
      { label: 'Přehled', to: '/prehled' },
      { label: project, to: `/p/${project}` },
    ];
    if (planId) crumbs.push({ label: `Plán ${planId}` });
    else if (epic) crumbs.push({ label: `EPIC ${epic}` });
    return crumbs;
  }

  return [];
}
